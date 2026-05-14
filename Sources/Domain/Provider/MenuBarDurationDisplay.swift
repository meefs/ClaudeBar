import Foundation

/// Formatted reset-duration value for the menu bar duration label.
/// Sibling to `MenuBarPercentageDisplay`; both display types are driven by the
/// same underlying `UsageQuota` but render different facets.
public struct MenuBarDurationDisplay: Sendable, Equatable {
    public let text: String
    public let status: QuotaStatus
    public let quota: UsageQuota

    public init(
        quota: UsageQuota,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) {
        self.quota = quota
        self.text = quota.compactResetTime ?? "—"
        self.status = burnRateWarningEnabled
            ? quota.paceAwareStatus(burnRateThreshold: burnRateThreshold)
            : quota.status
    }
}
