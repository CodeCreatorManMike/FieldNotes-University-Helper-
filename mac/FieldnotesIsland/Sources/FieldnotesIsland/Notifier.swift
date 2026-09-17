import Foundation
import UserNotifications

/// Best-effort local notifications. UNUserNotificationCenter needs a proper
/// .app bundle (see build.sh) to authorize reliably — everything here fails
/// silently rather than crashing when run as a loose binary without one.
final class Notifier {
    static let shared = Notifier()
    private let defaults = UserDefaults.standard
    private var authorized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func consider(previous: NextPayload?, current: NextPayload) {
        guard authorized else { return }
        deadlineCheck(current)
        targetHitCheck(current)
    }

    /// Fire once per (topic, "deadline passed" vs "due today") state — not
    /// once per poll — tracked by a UserDefaults key so restarting the app
    /// doesn't re-spam an alert already seen.
    private func deadlineCheck(_ payload: NextPayload) {
        guard let top = payload.top else { return }
        let urgent = top.reason.first(where: { $0.contains("deadline has passed") || $0.contains("is due in 0 day") || $0.contains("is due in 1 day") })
        guard let reason = urgent else { return }
        let key = "notified.deadline.\(top.id)"
        guard defaults.string(forKey: key) != reason else { return }
        defaults.set(reason, forKey: key)
        send(title: "\(top.module) · \(top.title)", body: reason.prefix(1).uppercased() + reason.dropFirst())
    }

    /// Fire once per calendar day when the daily plan's used minutes first
    /// reach the target.
    private func targetHitCheck(_ payload: NextPayload) {
        guard payload.dailyTarget > 0, payload.planUsedMinutes >= payload.dailyTarget else { return }
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let key = "notified.target"
        guard defaults.string(forKey: key) != today else { return }
        defaults.set(today, forKey: key)
        send(title: "Daily target hit", body: "\(payload.planUsedMinutes) of \(payload.dailyTarget) minutes planned — nice work.")
    }

    func sendFocusComplete() {
        send(title: "Focus session complete", body: "25 minutes done. Take a short break before the next one.")
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
