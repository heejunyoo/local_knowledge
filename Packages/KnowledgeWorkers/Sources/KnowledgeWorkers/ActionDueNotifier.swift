import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Surfaces open action items (Meeting pipeline: action due notify).
public enum ActionDueNotifier {
    public struct Item: Equatable, Sendable {
        public var id: String
        public var meetingId: String
        public var text: String
        public var dueOn: String?
        public init(id: String, meetingId: String, text: String, dueOn: String?) {
            self.id = id
            self.meetingId = meetingId
            self.text = text
            self.dueOn = dueOn
        }
    }

    public static func dueSoon(items: [Item], withinDays: Int = 3, today: Date = Date()) -> [Item] {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: withinDays, to: cal.startOfDay(for: today)) ?? today
        return items.filter { it in
            guard let d = it.dueOn, let date = f.date(from: d) else { return false }
            return date <= end
        }
    }

    #if canImport(UserNotifications)
    public static func requestAuthAndNotify(items: [Item]) {
        guard !items.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else { return }
            for (i, it) in items.prefix(5).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "할 일 기한"
                content.body = it.dueOn.map { "\($0) · \(it.text)" } ?? it.text
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(2 + i), repeats: false)
                let req = UNNotificationRequest(identifier: "action-\(it.id)", content: content, trigger: trigger)
                center.add(req, withCompletionHandler: nil)
            }
        }
    }
    #endif
}
