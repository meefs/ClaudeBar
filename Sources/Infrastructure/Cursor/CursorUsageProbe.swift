import Foundation
import Domain

/// Infrastructure adapter that probes Cursor's usage API to fetch quota data.
///
/// Cursor stores its authentication in a local SQLite database. This probe:
/// 1. Reads the access token from `state.vscdb`
/// 2. Decodes the JWT to extract the user ID
/// 3. Calls `https://cursor.com/api/usage-summary` with cookie auth
/// 4. Parses the response into quota percentages
///
/// The auth cookie format is: `WorkosCursorSessionToken={userId}::{accessToken}`
///
/// API response shape (usage-summary):
/// ```json
/// {
///   "membershipType": "pro",
///   "planUsage": {
///     "used": 123,
///     "limit": 500,
///     "remaining": 377,
///     "percentUsed": 24.6
///   },
///   "onDemandUsage": { "used": 5, "limit": 100 },
///   "billingCycleStart": "2025-01-01T00:00:00Z",
///   "billingCycleEnd": "2025-02-01T00:00:00Z"
/// }
/// ```
public struct CursorUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private let dbPathOverride: String?

    private static let usageSummaryURL = "https://cursor.com/api/usage-summary"

    /// The default path to Cursor's SQLite database on macOS
    static let defaultDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15.0,
        dbPathOverride: String? = nil
    ) {
        self.networkClient = networkClient
        self.timeout = timeout
        self.dbPathOverride = dbPathOverride
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath
        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        if !dbExists {
            AppLog.probes.debug("Cursor: Database not found at \(dbPath)")
        }
        return dbExists
    }

    public func probe() async throws -> UsageSnapshot {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath

        guard FileManager.default.fileExists(atPath: dbPath) else {
            AppLog.probes.error("Cursor: Database not found at \(dbPath)")
            throw ProbeError.cliNotFound("Cursor (database not found)")
        }

        AppLog.probes.info("Cursor: Reading auth token from database...")

        let accessToken = try readAccessToken(from: dbPath)
        let userId = try Self.extractUserIdFromJWT(accessToken)
        let cookie = "WorkosCursorSessionToken=\(userId)::\(accessToken)"

        AppLog.probes.info("Cursor: Fetching usage summary...")

        let response = try await fetchUsageSummary(cookie: cookie)
        let snapshot = try Self.parseUsageSummary(response)

        AppLog.probes.info("Cursor: Probe success - \(snapshot.quotas.count) quotas found")
        return snapshot
    }

    // MARK: - Token Extraction

    /// Reads the access token from Cursor's SQLite database using the sqlite3 CLI.
    private func readAccessToken(from dbPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLog.probes.error("Cursor: Failed to run sqlite3 - \(error.localizedDescription)")
            throw ProbeError.executionFailed("Failed to read Cursor database: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            AppLog.probes.error("Cursor: sqlite3 exited with status \(process.terminationStatus)")
            throw ProbeError.executionFailed("sqlite3 exited with status \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !token.isEmpty else {
            AppLog.probes.error("Cursor: No access token found in database (not logged in?)")
            throw ProbeError.authenticationRequired
        }

        return token
    }

    /// Extracts the user ID (`sub` claim) from a JWT token by base64-decoding the payload.
    static func extractUserIdFromJWT(_ token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw ProbeError.parseFailed("Invalid JWT format")
        }

        // JWT payload is base64url-encoded
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw ProbeError.parseFailed("Failed to decode JWT payload")
        }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let sub = json["sub"] as? String, !sub.isEmpty else {
            throw ProbeError.parseFailed("JWT payload missing 'sub' claim")
        }

        return sub
    }

    // MARK: - API Call

    private func fetchUsageSummary(cookie: String) async throws -> Data {
        guard let url = URL(string: Self.usageSummaryURL) else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Cursor: API response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            AppLog.probes.error("Cursor: Authentication failed (401) - token may be expired")
            throw ProbeError.sessionExpired
        case 403:
            AppLog.probes.error("Cursor: Forbidden (403)")
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Cursor: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Response Parsing (static for testability)

    /// Parses the Cursor usage-summary API response into a UsageSnapshot.
    public static func parseUsageSummary(_ data: Data) throws -> UsageSnapshot {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProbeError.parseFailed("Response is not a JSON object")
            }
            json = parsed
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        var quotas: [UsageQuota] = []

        let membershipType = json["membershipType"] as? String ?? "unknown"

        // Parse billing cycle dates for reset time
        var resetsAt: Date?
        if let cycleEnd = json["billingCycleEnd"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: cycleEnd) {
                resetsAt = date
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                resetsAt = formatter.date(from: cycleEnd)
            }
        }

        // Parse plan usage (included requests)
        if let planUsage = json["planUsage"] as? [String: Any],
           let enabled = planUsage["enabled"] as? Bool, enabled {
            let used = (planUsage["used"] as? Int) ?? (planUsage["used"] as? Double).map { Int($0) } ?? 0
            let limit = (planUsage["limit"] as? Int) ?? (planUsage["limit"] as? Double).map { Int($0) } ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                let requestsText = "\(used)/\(limit) requests"

                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("Monthly"),
                    providerId: "cursor",
                    resetsAt: resetsAt,
                    resetText: requestsText
                ))
            }
        }

        // Parse on-demand usage (usage-based pricing)
        if let onDemand = json["onDemandUsage"] as? [String: Any],
           let enabled = onDemand["enabled"] as? Bool, enabled {
            let used = (onDemand["used"] as? Int) ?? (onDemand["used"] as? Double).map { Int($0) } ?? 0
            let limit = (onDemand["limit"] as? Int) ?? (onDemand["limit"] as? Double).map { Int($0) } ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("On-Demand"),
                    providerId: "cursor",
                    resetsAt: resetsAt,
                    resetText: "\(used)/\(limit) on-demand"
                ))
            }
        }

        // Check for unlimited plans
        if let isUnlimited = json["isUnlimited"] as? Bool, isUnlimited {
            quotas.append(UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Monthly"),
                providerId: "cursor",
                resetText: "Unlimited"
            ))
        }

        // If no quotas found, the user might be on a free plan with no data
        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No usage data found in Cursor response")
        }

        // Determine account tier from membership type
        let tier: AccountTier? = switch membershipType.lowercased() {
        case "pro": .custom("PRO")
        case "business": .custom("BUSINESS")
        case "free": .custom("FREE")
        default: membershipType.isEmpty ? nil : .custom(membershipType.uppercased())
        }

        return UsageSnapshot(
            providerId: "cursor",
            quotas: quotas,
            capturedAt: Date(),
            accountTier: tier
        )
    }
}
