// SPDX-License-Identifier: BUSL-1.1
import Foundation
import UserNotifications

/// Posts a local notification per fresh alert. Alerts are read-only information: the notification has
/// no actions. Skipped when the app has no bundle identifier (a bare binary cannot post).
enum AlertNotifications {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ alerts: [VytrixAlert], host: String) {
        guard available else { return }
        for a in alerts {
            let c = UNMutableNotificationContent()
            c.title = "\(a.severity.label): \(a.title)"
            c.subtitle = host
            c.body = a.text
            if a.severity == .critical { c.sound = .default }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "vytrix-\(a.id)", content: c, trigger: nil))
        }
    }
}
