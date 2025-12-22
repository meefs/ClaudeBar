import Foundation
import Mockable

/// Protocol for sending system notifications - enables testing without UNUserNotificationCenter.
@Mockable
public protocol NotificationService: Sendable {
    /// Requests permission to send notifications.
    func requestPermission() async -> Bool

    /// Sends a notification with the given title and body.
    func send(title: String, body: String, categoryIdentifier: String) async throws
}
