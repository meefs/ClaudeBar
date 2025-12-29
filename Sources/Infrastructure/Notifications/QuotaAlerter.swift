import Foundation
import Domain
import UserNotifications
import Mockable

// MARK: - Internal Protocol (for testability)

/// Internal protocol for sending system alerts. Enables testing without UNUserNotificationCenter.
@Mockable
protocol AlertSender: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, categoryIdentifier: String) async throws
}

// MARK: - System Implementation

/// System alert sender using macOS UNUserNotificationCenter.
final class SystemAlertSender: AlertSender, @unchecked Sendable {

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            AppLog.notifications.warning("No bundle identifier - alerts unavailable")
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    func requestPermission() async -> Bool {
        guard let center = notificationCenter else {
            AppLog.notifications.error("Notification center unavailable")
            return false
        }

        let settings = await center.notificationSettings()
        AppLog.notifications.info("Current alert permission status: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            AppLog.notifications.info("Alerts already authorized")
            return true
        case .denied:
            AppLog.notifications.warning("Alerts denied by user - check System Settings > Notifications > ClaudeBar")
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                AppLog.notifications.info("Alert authorization result: \(granted)")
                return granted
            } catch {
                AppLog.notifications.error("Alert authorization error: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            AppLog.notifications.warning("Unknown alert authorization status")
            return false
        }
    }

    func send(title: String, body: String, categoryIdentifier: String) async throws {
        guard let center = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try await center.add(request)
    }
}

// MARK: - QuotaAlerter

/// Alerts users when their AI quota status degrades.
/// Sends system notifications for warning, critical, and depleted states.
public final class QuotaAlerter: QuotaStatusListener, @unchecked Sendable {

    private let alertSender: AlertSender

    /// Public initializer - uses system alerts
    public init() {
        self.alertSender = SystemAlertSender()
    }

    /// Internal initializer for testing
    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    // MARK: - Public API

    /// Requests permission to send quota alerts.
    public func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - QuotaStatusListener

    public func onStatusChanged(providerId: String, oldStatus: QuotaStatus, newStatus: QuotaStatus) async {
        AppLog.notifications.debug("Status change: \(providerId) \(oldStatus) -> \(newStatus)")

        // Only alert on degradation (getting worse)
        guard newStatus > oldStatus else {
            AppLog.notifications.debug("Status improved or same, skipping alert")
            return
        }

        guard shouldAlert(for: newStatus) else {
            AppLog.notifications.debug("Status \(newStatus) does not require alert")
            return
        }

        let providerName = providerDisplayName(for: providerId)
        let title = "\(providerName) Quota Alert"
        let body = alertBody(for: newStatus, providerName: providerName)

        AppLog.notifications.notice("Sending quota alert for \(providerId): \(newStatus)")

        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: "QUOTA_ALERT")
            AppLog.notifications.info("Alert sent successfully")
        } catch {
            AppLog.notifications.error("Failed to send alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers (internal for testability)

    func shouldAlert(for status: QuotaStatus) -> Bool {
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

    func alertBody(for status: QuotaStatus, providerName: String) -> String {
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
