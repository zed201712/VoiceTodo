//
//  ReminderSync.swift
//  voicecalender
//

import Foundation

/// 提醒事項存檔的純邏輯（不碰 EventKit，可以單元測試）：差異、提醒事項與待辦的轉換、alarm 的平移
/// （見 docs/specs/storage.md、docs/specs/notifications.md）。
enum ReminderSync {

    struct Update: Equatable {
        let before: Todo
        let after: Todo
    }

    /// 上次讀取或寫入的那份與這次的比較，依 id 找出差異（見 docs/specs/storage.md 的「寫入」）。
    struct Changes: Equatable {
        var added: [Todo] = []
        var updated: [Update] = []
        var removed: [Todo] = []

        var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty }
    }

    static func changes(from old: [Todo], to new: [Todo]) -> Changes {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newIDs = Set(new.map(\.id))
        var changes = Changes()
        for todo in new {
            if let before = oldByID[todo.id] {
                if before != todo {
                    changes.updated.append(Update(before: before, after: todo))
                }
            } else {
                changes.added.append(todo)
            }
        }
        changes.removed = old.filter { !newIDs.contains($0.id) }
        return changes
    }

    // MARK: - 提醒事項與待辦

    /// 一筆提醒事項變成待辦：標題空白的不讀進來（見 docs/specs/storage.md 的「讀取」）。
    static func todo(id: Int, title: String?, due: DateComponents?, isCompleted: Bool) -> Todo? {
        let content = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return nil
        }
        return Todo(id: id, date: day(due), time: time(due), content: content, isDone: isCompleted)
    }

    /// 到期日的那一天；年月日不全就是沒有日期。用使用者的曆法組回日期。
    static func day(_ due: DateComponents?) -> String? {
        guard let due, let year = due.year, let month = due.month, let day = due.day,
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        else {
            return nil
        }
        return date.formatted(TodoStore.dayFormat)
    }

    static func time(_ due: DateComponents?) -> String? {
        guard day(due) != nil, let hour = due?.hour else {
            return nil
        }
        return String(format: "%02d:%02d", hour, due?.minute ?? 0)
    }

    /// 待辦的日期與時間寫成提醒事項的到期日；只有日期時不帶時、分。
    static func dueComponents(_ todo: Todo) -> DateComponents? {
        guard let date = todo.date else {
            return nil
        }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        var components = DateComponents(calendar: Calendar.current, year: parts[0], month: parts[1], day: parts[2])
        if let time = todo.time {
            let clock = time.split(separator: ":").compactMap { Int($0) }
            components.hour = clock.first
            components.minute = clock.count > 1 ? clock[1] : 0
        }
        return components
    }

    /// 到期的時間點：只有日期時是那天 00:00。
    static func dueDate(_ todo: Todo) -> Date? {
        dueComponents(todo).flatMap { Calendar.current.date(from: $0) }
    }

    // MARK: - alarm（見 docs/specs/notifications.md 的「alarm 的規則」）

    /// 提醒事項上和平移有關的部分：絕對時間的 alarm、有沒有相對時間的 alarm、開始日期。
    struct Alarms: Equatable {
        var absolute: [Date] = []
        var hasRelative = false
        var start: Date?
    }

    /// 寫入後的 alarm：新增（`before` 是 nil）有時間就加一個；改了日期或時間時，絕對時間的 alarm 與開始日期平移相同的差距，
    /// 改完有時間但沒有任何 alarm 就補一個；沒改日期與時間就不動。
    /// 要不要寫到期日（與跟著移的 alarm、開始日期）：新的一筆一定要，包括用刪除快照重建的（日期通常沒變）；
    /// 已經存在的只在日期或時間改變時。
    static func writesDue(isNew: Bool, before: Todo?, after: Todo) -> Bool {
        isNew || before?.date != after.date || before?.time != after.time
    }

    static func alarms(_ alarms: Alarms, before: Todo?, after: Todo) -> Alarms {
        guard let before else {
            return after.time == nil ? alarms : added(alarms, at: dueDate(after))
        }
        guard before.date != after.date || before.time != after.time else {
            return alarms
        }
        var result = alarms
        if let from = dueDate(before), let to = dueDate(after) {
            let offset = to.timeIntervalSince(from)
            result.absolute = alarms.absolute.map { $0.addingTimeInterval(offset) }
            result.start = alarms.start?.addingTimeInterval(offset)
        }
        guard after.time != nil, result.absolute.isEmpty, !result.hasRelative else {
            return result
        }
        return added(result, at: dueDate(after))
    }

    private static func added(_ alarms: Alarms, at date: Date?) -> Alarms {
        var result = alarms
        if let date {
            result.absolute.append(date)
        }
        return result
    }
}
