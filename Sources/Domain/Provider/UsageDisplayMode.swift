import Foundation

/// Controls whether quota percentages are displayed as "remaining" or "used".
///
/// - `.remaining`: Shows how much quota is left (e.g., "25% Remaining")
/// - `.used`: Shows how much quota has been consumed (e.g., "75% Used")
public enum UsageDisplayMode: String, Sendable, Equatable, CaseIterable {
    case remaining
    case used

    /// The label shown alongside the percentage in quota cards.
    public var displayLabel: String {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        }
    }
}