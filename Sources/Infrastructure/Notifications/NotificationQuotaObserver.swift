import Foundation
import Domain

/// Infrastructure adapter that sends macOS notifications when quota status changes.
/// Implements StatusChangeObserver from the domain layer.
public final class NotificationQuotaObserver: StatusChangeObserver, @unchecked Sendable {
    private let notificationService: NotificationService

    public init(notificationService: NotificationService? = nil) {
        self.notificationService = notificationService ?? UserNotificationService()
    }

    /// Requests notification permission from the user
    public func requestPermission() async -> Bool {
        await notificationService.requestPermission()
    }

    // MARK: - StatusChangeObserver

    public func onStatusChanged(providerId: String, oldStatus: QuotaStatus, newStatus: QuotaStatus) async {
        // Only notify on degradation (getting worse)
        guard newStatus > oldStatus else { return }

        // Skip if status improved or stayed the same
        guard shouldNotify(for: newStatus) else { return }

        let providerName = providerDisplayName(for: providerId)
        let title = "\(providerName) Quota Alert"
        let body = notificationBody(for: newStatus, providerName: providerName)

        do {
            try await notificationService.send(
                title: title,
                body: body,
                categoryIdentifier: "QUOTA_ALERT"
            )
        } catch {
            // Silently fail - notifications are non-critical
        }
    }

    // MARK: - Helpers (internal for testability)

    func shouldNotify(for status: QuotaStatus) -> Bool {
        switch status {
        case .warning, .critical, .depleted:
            return true
        case .healthy:
            return false
        }
    }

    func providerDisplayName(for providerId: String) -> String {
        AIProviderRegistry.shared.provider(for: providerId)?.name ?? providerId.capitalized
    }

    func notificationBody(for status: QuotaStatus, providerName: String) -> String {
        switch status {
        case .warning:
            return "Your \(providerName) quota is running low. Consider pacing your usage."
        case .critical:
            return "Your \(providerName) quota is critically low! Save important work."
        case .depleted:
            return "Your \(providerName) quota is depleted. Usage may be blocked."
        case .healthy:
            return "Your \(providerName) quota has recovered."
        }
    }
}
