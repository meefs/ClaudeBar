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
        AppLog.notifications.debug("Requesting notification permission...")
        let granted = await notificationService.requestPermission()
        AppLog.notifications.info("Notification permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - StatusChangeObserver

    public func onStatusChanged(providerId: String, oldStatus: QuotaStatus, newStatus: QuotaStatus) async {
        AppLog.notifications.debug("Status change: \(providerId) \(String(describing: oldStatus)) -> \(String(describing: newStatus))")
        
        // Only notify on degradation (getting worse)
        guard newStatus > oldStatus else {
            AppLog.notifications.debug("Status improved or same, skipping notification")
            return
        }

        // Skip if status improved or stayed the same
        guard shouldNotify(for: newStatus) else {
            AppLog.notifications.debug("Status \(String(describing: newStatus)) does not require notification")
            return
        }

        let providerName = providerDisplayName(for: providerId)
        let title = "\(providerName) Quota Alert"
        let body = notificationBody(for: newStatus, providerName: providerName)

        AppLog.notifications.notice("Sending quota alert for \(providerId): \(String(describing: newStatus))")
        
        do {
            try await notificationService.send(
                title: title,
                body: body,
                categoryIdentifier: "QUOTA_ALERT"
            )
            AppLog.notifications.info("Notification sent successfully")
        } catch {
            AppLog.notifications.error("Failed to send notification: \(error.localizedDescription)")
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
