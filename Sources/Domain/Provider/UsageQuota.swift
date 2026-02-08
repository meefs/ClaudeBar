import Foundation

/// Represents a single usage quota measurement for an AI provider.
/// This is a rich domain model that encapsulates quota-related behavior.
public struct UsageQuota: Sendable, Equatable, Hashable, Comparable {
    /// The percentage of quota remaining (can be negative when over quota, capped at 100)
    public let percentRemaining: Double

    /// The type of quota (session, weekly, model-specific)
    public let quotaType: QuotaType

    /// The provider ID this quota belongs to (e.g., "claude", "codex", "gemini")
    public let providerId: String

    /// When this quota will reset (if known)
    public let resetsAt: Date?

    /// Raw reset text from CLI (e.g., "Resets 11am", "Resets Jan 15")
    public let resetText: String?

    // MARK: - Initialization

    public init(
        percentRemaining: Double,
        quotaType: QuotaType,
        providerId: String,
        resetsAt: Date? = nil,
        resetText: String? = nil
    ) {
        self.percentRemaining = min(100, percentRemaining)  // Allow negative, cap at 100
        self.quotaType = quotaType
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.resetText = resetText
    }

    // MARK: - Domain Behavior

    /// The current health status based on percentage remaining.
    /// This is a domain rule: status is determined by business thresholds.
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    /// The percentage that has been used (0-100)
    public var percentUsed: Double {
        100 - percentRemaining
    }

    /// Whether this quota is completely exhausted
    public var isDepleted: Bool {
        percentRemaining <= 0
    }

    /// Whether this quota needs attention (warning, critical, or depleted)
    public var needsAttention: Bool {
        status.needsAttention
    }

    /// Returns the display percentage based on the display mode.
    /// - In `.remaining` mode: returns `percentRemaining`
    /// - In `.used` mode: returns `percentUsed` (100 - percentRemaining)
    /// - In `.pace` mode: returns `percentRemaining` (familiar number, with pace context from badge + insight)
    public func displayPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining: percentRemaining
        case .used: percentUsed
        case .pace: percentRemaining
        }
    }

    /// Returns the percentage to use for progress bar width based on the display mode.
    /// - In `.remaining` mode: bar fills from right to left as quota depletes
    /// - In `.used` mode: bar fills from left to right as quota is consumed
    /// - In `.pace` mode: bar shows remaining (same as remaining mode)
    public func displayProgressPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining: percentRemaining
        case .used: percentUsed
        case .pace: percentRemaining
        }
    }

    /// Returns the expected progress bar position based on time elapsed and display mode.
    /// This represents where the bar "should be" if usage were perfectly on pace.
    /// Returns nil when reset time is unknown.
    public func expectedProgressPercent(mode: UsageDisplayMode) -> Double? {
        guard let percentTimeElapsed else { return nil }
        switch mode {
        case .remaining, .pace: return 100 - percentTimeElapsed
        case .used: return percentTimeElapsed
        }
    }

    // MARK: - Pace

    /// The percentage of the reset period that has elapsed (0-100), or nil if no reset time is known.
    ///
    /// Calculated as: `(totalDuration - timeUntilReset) / totalDuration * 100`
    public var percentTimeElapsed: Double? {
        guard let timeUntilReset else { return nil }
        let totalDuration = quotaType.duration.seconds
        guard totalDuration > 0 else { return nil }
        let elapsed = totalDuration - timeUntilReset
        return min(100, max(0, elapsed / totalDuration * 100))
    }

    /// The difference between actual usage and expected usage based on time elapsed.
    /// Positive means ahead (consuming faster), negative means behind (room to spare).
    /// Returns nil if time-based pace cannot be determined.
    public var pacePercent: Double? {
        guard let percentTimeElapsed else { return nil }
        return percentUsed - percentTimeElapsed
    }

    /// The pace classification for this quota.
    public var pace: UsagePace {
        guard let pacePercent, let percentTimeElapsed else { return .unknown }
        return UsagePace.from(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed)
    }

    /// A human-readable insight about the pace deviation (e.g., "37% below expected usage").
    /// Returns nil when pace cannot be determined.
    public var paceInsight: String? {
        guard let pacePercent, pace != .unknown else { return nil }
        let delta = Int(abs(pacePercent))
        switch pace {
        case .behind: return "\(delta)% below expected usage"
        case .ahead: return "\(delta)% above expected usage"
        case .onPace: return "Right on track"
        case .unknown: return nil
        }
    }

    /// Time until this quota resets (if known)
    public var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// Human-readable description of time until reset
    public var resetDescription: String? {
        guard let timeUntilReset else { return nil }

        let hours = Int(timeUntilReset / 3600)
        let minutes = Int((timeUntilReset.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "Resets in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }

    // MARK: - Comparable

    public static func < (lhs: UsageQuota, rhs: UsageQuota) -> Bool {
        lhs.percentRemaining < rhs.percentRemaining
    }
}
