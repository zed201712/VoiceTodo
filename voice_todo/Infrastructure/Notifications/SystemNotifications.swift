//
//  SystemNotifications.swift
//  voicecalender
//

// App 自己的通知停用，改由提醒事項 App 依 alarm 通知；等實機確認後再刪除（見 docs/specs/notifications.md 的「App 自己的通知」）。
/*
import UserNotifications

/// 系統的本地通知（見 docs/specs/notifications.md）。也是通知中心的 delegate：App 在前景時照樣跳出橫幅。
final class SystemNotifications: NSObject, NotificationScheduler, UNUserNotificationCenterDelegate {

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// 第一次會跳出系統的權限對話框；已經決定過時直接回傳結果。
    func requestAccess() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("[Notifications] 請求權限失敗：\(error)")
            return false
        }
    }

    /// 通知中心依呼叫的順序處理，先移除的不會蓋掉後加的。
    func replaceAll(with notifications: [TodoNotification]) {
        center.removeAllPendingNotificationRequests()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.body = notification.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(notification), repeats: false)
            center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)) { error in
                if let error {
                    print("[Notifications] 排程失敗：\(notification.body)：\(error)")
                }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// `yyyy-MM-dd`、`HH:mm` → 本地時間的年月日時分。
    private static func components(_ notification: TodoNotification) -> DateComponents {
        let day = notification.date.split(separator: "-").compactMap { Int($0) }
        let time = notification.time.split(separator: ":").compactMap { Int($0) }
        return DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1])
    }
}
*/
