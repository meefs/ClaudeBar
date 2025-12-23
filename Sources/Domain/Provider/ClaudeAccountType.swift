import Foundation

/// Represents the type of Claude account being used.
/// Different account tiers have different quota and cost tracking features.
public enum ClaudeAccountType: String, Sendable, Equatable, Hashable {
    /// Claude Max subscription with session/weekly quotas + optional extra usage cost tracking
    case max
    /// Claude Pro subscription with session/weekly quotas + optional extra usage cost tracking
    case pro
    /// Claude API account with pay-per-use pricing (cost tracking only)
    case api

    // MARK: - Display Properties

    /// Display name for the account type
    public var displayName: String {
        switch self {
        case .max: return "Claude Max"
        case .pro: return "Claude Pro"
        case .api: return "API Usage"
        }
    }

    /// Short badge text for compact display
    public var badgeText: String {
        switch self {
        case .max: return "MAX"
        case .pro: return "PRO"
        case .api: return "API"
        }
    }
}
