//
//  TodoNotification.swift
//  voicecalender
//

// App 自己的通知停用，改由提醒事項 App 依 alarm 通知；等實機確認後再刪除（見 docs/specs/notifications.md 的「App 自己的通知」）。
/*
import Foundation

/// 一筆待辦的通知（見 docs/specs/notifications.md）：通知是待辦清單算出來的結果，每次存檔整份重排。
struct TodoNotification: Equatable {
    /// `todo-<待辦的 id>`
    let id: String
    /// `yyyy-MM-dd`
    let date: String
    /// `HH:mm`
    let time: String
    /// `15:00 看牙醫`
    let body: String

    /// 系統對每個 App 最多保留 64 個排好的通知。
    static let limit = 64

    /// 未完成、有時間、不是示範資料、時間在現在之後（同一分鐘不算）的待辦，依待辦的排序取最早的 64 個。
    static func plan(_ todos: [Todo], now: Date) -> [TodoNotification] {
        let components = DatePhrase.calendar.dateComponents([.hour, .minute], from: now)
        let current = TodoStore.dayString(now) + String(format: " %02d:%02d", components.hour ?? 0, components.minute ?? 0)
        return todos
            .filter { !$0.isDone && !$0.isDemo }
            .compactMap { todo in todo.time.map { (todo, $0) } }
            .filter { todo, time in "\(todo.date) \(time)" > current }
            .sorted { $0.0.order < $1.0.order }
            .prefix(limit)
            .map { todo, time in TodoNotification(id: "todo-\(todo.id)", date: todo.date, time: time, body: "\(time) \(todo.content)") }
    }
}

/// 排通知（見 docs/specs/notifications.md）。
protocol NotificationScheduler {
    /// 請求通知的權限；已經決定過時直接回傳結果，不再詢問。
    func requestAccess() async -> Bool
    /// 移除 App 排好的所有通知，換成這些。
    func replaceAll(with notifications: [TodoNotification])
}
*/
