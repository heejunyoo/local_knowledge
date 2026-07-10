import Foundation
import UserNotifications

/// W2 local notifications — no APNs; schedule from gap checklist.
enum LocalNotify {
    private static let gapId = "assistant.gaps.evening"

    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedule one evening reminder if there are gaps (debounced daily).
    static func scheduleGapsIfNeeded(gaps: [[String: Any]], reviewCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [gapId])
        guard !gaps.isEmpty || reviewCount > 0 else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        // Only schedule if still afternoon/evening and something missing.
        guard hour >= 17, hour < 23 else { return }

        let content = UNMutableNotificationContent()
        content.title = "오늘 빠진 기록이 있어요"
        if let label = gaps.first?["label"] as? String {
            content.body = reviewCount > 0
                ? "\(label) · 확인함 \(reviewCount)건"
                : label
        } else {
            content.body = "확인함 \(reviewCount)건을 살펴볼까요?"
        }
        content.sound = .default

        // Fire in ~2 minutes once (session nudge), not spam every open.
        let key = "localNotify.gaps.\(dayKey())"
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        let req = UNNotificationRequest(identifier: gapId, content: content, trigger: trigger)
        center.add(req, withCompletionHandler: nil)
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
