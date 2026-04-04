import Foundation
import UserNotifications

enum DailyPromptNotificationManager {
    static let notificationIdentifier = "anky-daily-reminder"
    private static let lastPromptKey = "anky.notification.lastPrompt"
    private static let pendingSessionKey = "anky.notification.pendingSessionId"

    // MARK: - Schedule with dynamic prompt

    /// Schedule (or replace) the daily reminder with the given prompt.
    /// Called when status poll returns a non-null nextPrompt.
    static func scheduleWithPrompt(_ prompt: String) async {
        guard !prompt.isEmpty else { return }

        // Persist the prompt locally as fallback
        UserDefaults.standard.set(prompt, forKey: lastPromptKey)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Request permission if not yet determined (first session completion)
        if settings.authorizationStatus == .notDetermined {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted == true else { return }
        }

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ||
              settings.authorizationStatus == .notDetermined else {
            return
        }

        await scheduleNotification(prompt: prompt, using: center)
    }

    /// Reschedule using the last stored prompt (called on app active).
    static func rescheduleIfAuthorized() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        // Check if we already have a pending notification
        let pending = await center.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == notificationIdentifier }) {
            return
        }

        let prompt = lastStoredPrompt
        await scheduleNotification(prompt: prompt, using: center)
    }

    /// Request authorization explicitly (for settings toggle).
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted == true
    }

    /// Cancel any scheduled reminder.
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier]
        )
    }

    // MARK: - Stored prompt

    static var lastStoredPrompt: String {
        UserDefaults.standard.string(forKey: lastPromptKey) ?? "the page is waiting."
    }

    // MARK: - Pending session recovery

    static func savePendingSession(_ sessionId: String) {
        UserDefaults.standard.set(sessionId, forKey: pendingSessionKey)
    }

    static func clearPendingSession() {
        UserDefaults.standard.removeObject(forKey: pendingSessionKey)
    }

    static var pendingSessionId: String? {
        UserDefaults.standard.string(forKey: pendingSessionKey)
    }

    // MARK: - Private

    private static func scheduleNotification(prompt: String, using center: UNUserNotificationCenter) async {
        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        let settings = UserSettings.shared
        guard settings.remindersEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "anky"
        content.body = prompt
        content.sound = .default
        content.userInfo = ["prompt": prompt]

        var dateComponents = DateComponents()
        dateComponents.hour = settings.reminderHour
        dateComponents.minute = settings.reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }
}
