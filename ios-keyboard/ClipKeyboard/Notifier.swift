import UserNotifications

/// Ensures notifications appear even while the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Local notifications for transcription results.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let attachment = iconAttachment() {
            content.attachments = [attachment]
        }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(req)
    }

    /// Attaches the app icon so the notification always carries a visible image
    /// (the small system icon can look generic right after a fresh install).
    private static func iconAttachment() -> UNNotificationAttachment? {
        guard let src = Bundle.main.url(forResource: "NotifIcon", withExtension: "png") else {
            return nil
        }
        // Attachments consume the file, so copy to a unique temp location first.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        do {
            try FileManager.default.copyItem(at: src, to: tmp)
            return try UNNotificationAttachment(identifier: "icon", url: tmp)
        } catch {
            return nil
        }
    }
}
