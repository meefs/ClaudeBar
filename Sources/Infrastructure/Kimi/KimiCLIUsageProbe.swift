import Foundation
import Domain

/// Infrastructure adapter that probes the Kimi CLI to fetch usage quotas.
/// Starts the interactive `kimi` CLI, sends `/usage`, and parses the output.
///
/// Sample CLI output:
/// ```
/// ╭─────────────────────────────── API Usage ───────────────────────────────╮
/// │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
/// │  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
/// ╰─────────────────────────────────────────────────────────────────────────╯
/// ```
public struct KimiCLIUsageProbe: UsageProbe {
    private let kimiBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        kimiBinary: String = "kimi",
        timeout: TimeInterval = 15.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.kimiBinary = kimiBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(kimiBinary) != nil {
            return true
        }
        AppLog.probes.error("Kimi binary '\(kimiBinary)' not found in PATH")
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate(kimiBinary) != nil else {
            throw ProbeError.cliNotFound(kimiBinary)
        }

        AppLog.probes.info("Starting Kimi CLI probe with /usage command...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: kimiBinary,
                args: [],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [
                    "💫": "/usage\r",
                ]
            )
        } catch {
            AppLog.probes.error("Kimi CLI probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.info("Kimi CLI /usage output:\n\(result.output)")

        let snapshot = try Self.parse(result.output)

        AppLog.probes.info("Kimi CLI probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses the Kimi CLI `/usage` output into a UsageSnapshot.
    ///
    /// Expected format per quota line:
    /// ```
    /// Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)
    /// 5h limit      ━━━━━━━━━━━━━━━━━━━━  75% left   (resets in 4h 22m)
    /// ```
    public static func parse(_ text: String) throws -> UsageSnapshot {
        // Pattern: label + optional progress bar + percent + "left" + reset info
        // Real CLI output may omit progress bar chars (just whitespace between label and %)
        let pattern = #"([\w\s]+?)\s{2,}[━░─]*\s*(\d+)%\s+left\s+\(resets\s+in\s+(.+?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw ProbeError.parseFailed("Invalid regex pattern")
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        guard !matches.isEmpty else {
            throw ProbeError.parseFailed("No quota data found in Kimi CLI output")
        }

        var quotas: [UsageQuota] = []

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let labelRange = Range(match.range(at: 1), in: text),
                  let percentRange = Range(match.range(at: 2), in: text),
                  let resetRange = Range(match.range(at: 3), in: text) else {
                continue
            }

            let label = String(text[labelRange]).trimmingCharacters(in: .whitespaces).lowercased()
            let percent = Double(text[percentRange]) ?? 0.0
            let resetText = String(text[resetRange]).trimmingCharacters(in: .whitespaces)

            let quotaType: QuotaType
            if label.contains("weekly") {
                quotaType = .weekly
            } else if label.contains("5h") || label.contains("hour") {
                quotaType = .session
            } else {
                quotaType = .timeLimit(label)
            }

            let resetsAt = parseResetDuration(resetText)

            quotas.append(UsageQuota(
                percentRemaining: percent,
                quotaType: quotaType,
                providerId: "kimi",
                resetsAt: resetsAt,
                resetText: "Resets in \(resetText)"
            ))
        }

        return UsageSnapshot(
            providerId: "kimi",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Private Helpers

    /// Parses a relative duration string like "6d 23h 22m" or "4h 22m" into a future Date.
    static func parseResetDuration(_ text: String) -> Date? {
        var totalSeconds: TimeInterval = 0

        // Extract days
        if let dayMatch = text.range(of: #"(\d+)\s*d"#, options: .regularExpression) {
            let dayStr = String(text[dayMatch])
            if let days = Int(dayStr.filter { $0.isNumber }) {
                totalSeconds += Double(days) * 24 * 3600
            }
        }

        // Extract hours
        if let hourMatch = text.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Int(hourStr.filter { $0.isNumber }) {
                totalSeconds += Double(hours) * 3600
            }
        }

        // Extract minutes
        if let minMatch = text.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Int(minStr.filter { $0.isNumber }) {
                totalSeconds += Double(minutes) * 60
            }
        }

        guard totalSeconds > 0 else { return nil }
        return Date().addingTimeInterval(totalSeconds)
    }
}
