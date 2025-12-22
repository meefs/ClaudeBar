import Foundation
import UserNotifications

/// Default implementation of NotificationService using UNUserNotificationCenter.
/// This is excluded from code coverage as it's a pure adapter for system APIs.
public final class UserNotificationService: NotificationService, @unchecked Sendable {
    private var notificationCenter: UNUserNotificationCenter? {
        // Only access notification center when running in a proper app context
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    public init() {}

    public func requestPermission() async -> Bool {
        guard let center = notificationCenter else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func send(title: String, body: String, categoryIdentifier: String) async throws {
        guard let center = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await center.add(request)
    }
}
