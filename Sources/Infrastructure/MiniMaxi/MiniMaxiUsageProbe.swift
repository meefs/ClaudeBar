import Foundation
import Domain

/// Probes MiniMaxi Coding Plan API for usage quota information.
/// Uses REST API: GET https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains
/// Authentication: Bearer token from env var or stored API key.
public struct MiniMaxiUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any MiniMaxiSettingsRepository
    private let timeout: TimeInterval

    private static let apiURL = "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains"

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any MiniMaxiSettingsRepository,
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.minimaxiAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "MINIMAX_API_KEY" : envVarName
        if let envValue = ProcessInfo.processInfo.environment[effectiveEnvVar], !envValue.isEmpty {
            AppLog.probes.debug("MiniMaxi: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // Fall back to stored API key
        if let storedKey = settingsRepository.getMinimaxiApiKey(), !storedKey.isEmpty {
            AppLog.probes.debug("MiniMaxi: Using stored API key")
            return storedKey
        }

        return nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("MiniMaxi: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("MiniMaxi: No API key configured (check env var or settings)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting MiniMaxi probe...")

        guard let url = URL(string: Self.apiURL) else {
            throw ProbeError.executionFailed("Invalid MiniMaxi API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("MiniMaxi API returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("MiniMaxi API returned HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("MiniMaxi API response: \(responseText.prefix(500))")
        }

        let snapshot = try Self.parseResponse(data, providerId: "minimaxi")

        AppLog.probes.info("MiniMaxi probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the MiniMaxi Coding Plan remains API response into a UsageSnapshot
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: MiniMaxiRemainsResponse
        do {
            response = try decoder.decode(MiniMaxiRemainsResponse.self, from: data)
        } catch {
            AppLog.probes.error("MiniMaxi parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("MiniMaxi raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        // Check API error status
        if response.baseResp.statusCode != 0 {
            let message = response.baseResp.statusMsg ?? "Unknown error"
            AppLog.probes.error("MiniMaxi API error: \(response.baseResp.statusCode) - \(message)")
            throw ProbeError.executionFailed("MiniMaxi API error: \(message)")
        }

        let modelRemains = response.modelRemains ?? []

        guard !modelRemains.isEmpty else {
            AppLog.probes.error("MiniMaxi: Empty model_remains in response")
            throw ProbeError.noData
        }

        let quotas = modelRemains.map { model -> UsageQuota in
            let total = model.currentIntervalTotalCount
            // ⚠️ MiniMaxi API naming is misleading:
            // Despite being called "current_interval_usage_count", this field
            // actually represents the REMAINING count, not the used count.
            // Confirmed via MiniMaxi dashboard: when dashboard shows "3% used",
            // API returns usage_count=1459 out of total=1500 (i.e. 1459 remaining).
            // (MiniMaxi API 命名有误导性：usage_count 实际是剩余次数，非已用次数)
            let remainingCount = model.currentIntervalUsageCount
            let usedCount = total - remainingCount
            let remaining = total > 0 ? Double(remainingCount) / Double(total) * 100.0 : 0.0

            // Parse end_time as millisecond timestamp (毫秒时间戳)
            let resetsAt: Date? = model.endTime.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }

            let resetText = "\(usedCount)/\(total) requests"

            return UsageQuota(
                percentRemaining: remaining,
                quotaType: .modelSpecific(model.modelName),
                providerId: providerId,
                resetsAt: resetsAt,
                resetText: resetText
            )
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date()
        )
    }
}

// MARK: - Response Models (Internal)

struct MiniMaxiRemainsResponse: Decodable {
    let baseResp: BaseResp
    let modelRemains: [ModelRemain]?
}

struct BaseResp: Decodable {
    let statusCode: Int
    let statusMsg: String?
}

struct ModelRemain: Decodable {
    let modelName: String
    let currentIntervalTotalCount: Int
    let currentIntervalUsageCount: Int
    let remainsTime: Int?
    let endTime: Int64?
}
