//
//  EventKitTodoStorage.swift
//  voicecalender
//

import EventKit

/// 待辦存在 Apple 提醒事項（見 docs/specs/storage.md）。整份讀寫：記住每個待辦 id 對應哪一筆提醒事項，
/// 寫入時和上次的那份比較，只把差異寫進提醒事項；刪除前留下刪除快照，undo 加回來時帶回 EventKit 讀得到的資料。
final class EventKitTodoStorage: TodoStorage {

    static let testListName = "VoiceTodo 測試"

    var onExternalChange: (() -> Void)?

    private let store = EKEventStore()
    /// 待辦 id → 提醒事項的識別碼。
    private var identifiers: [Int: String] = [:]
    /// 上次讀取或寫入的那份：寫入時和它比較。
    private var known: [Todo] = []
    /// 只增不減：讀進來的新項目用它編 id，不會和 App 用過的 id 重複。
    private var nextID = 1
    private var tombstones: [Int: Tombstone] = [:]
    /// 已完成的讀過了沒（見 docs/specs/storage.md 的「延遲讀取」）。
    private var hasLoadedRest = false
    /// 測試清單打開時只讀寫這個清單；nil 是所有清單。
    private var testCalendar: EKCalendar?
    private var observer: (any NSObjectProtocol)?

    /// 刪除前記下的資料：EventKit 讀得到、待辦沒有的部分，以及刪除時的待辦（alarm 依它平移）。
    private struct Tombstone {
        let todo: Todo
        let calendarIdentifier: String?
        let notes: String?
        let url: URL?
        let priority: Int
        let location: String?
        let alarms: [EKAlarm]
        let recurrenceRules: [EKRecurrenceRule]
        let start: DateComponents?
    }

    /// 在 EventKit 的 callback 裡就轉成這個：EKReminder 不是 Sendable。
    private nonisolated struct Item: Sendable {
        let identifier: String
        let title: String?
        let due: DateComponents?
        let isCompleted: Bool
    }

    init() {
        // App 自己寫入也會觸發，由 App 比較讀回來的和記憶體裡的是否相同（見 docs/specs/storage.md 的「外部變動」）。
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onExternalChange?()
            }
        }
    }

    // MARK: - 讀取

    func load() async throws -> [Todo] {
        try await requestAccess()
        var items = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars))
        if hasLoadedRest {
            items += await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars))
        }
        // 已經知道的每一筆也重新讀（例如這次在 App 裡設成完成的）；讀不到就是在別處被刪了。
        let seen = Set(items.map(\.identifier))
        for identifier in identifiers.values where !seen.contains(identifier) {
            if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
                items.append(Self.item(reminder))
            }
        }
        let todos = adopt(items)
        identifiers = identifiers.filter { id, _ in todos.contains { $0.id == id } }
        known = todos
        return todos
    }

    func loadRest() async throws -> [Todo] {
        guard !hasLoadedRest else {
            return []
        }
        try await requestAccess()
        let items = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars))
        let knownIdentifiers = Set(identifiers.values)
        let rest = adopt(items.filter { !knownIdentifiers.contains($0.identifier) })
        hasLoadedRest = true
        known += rest
        return rest
    }

    private var calendars: [EKCalendar]? {
        testCalendar.map { [$0] }
    }

    private func requestAccess() async throws {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            throw ToolError(message: "讀取提醒事項失敗：\(error.localizedDescription)")
        }
        guard granted else {
            throw ToolError(message: "沒有取用提醒事項的權限，請到系統設定允許")
        }
    }

    private func fetch(_ predicate: NSPredicate) async -> [Item] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: (found ?? []).map(Self.item))
            }
        }
    }

    private nonisolated static func item(_ reminder: EKReminder) -> Item {
        Item(identifier: reminder.calendarItemIdentifier, title: reminder.title, due: reminder.dueDateComponents, isCompleted: reminder.isCompleted)
    }

    /// 提醒事項變成待辦：同一筆沿用原本的 id，新的編新的 id；標題空白的不讀。
    private func adopt(_ items: [Item]) -> [Todo] {
        let ids = Dictionary(identifiers.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in
            let id = ids[item.identifier] ?? newID()
            guard let todo = ReminderSync.todo(id: id, title: item.title, due: item.due, isCompleted: item.isCompleted) else {
                return nil
            }
            identifiers[id] = item.identifier
            return todo
        }
    }

    private func newID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: - 寫入

    /// 一次寫入：全部成功或全部不寫。失敗時丟掉這次的改變，下次寫入再比較一次。
    func save(_ todos: [Todo]) throws {
        nextID = max(nextID, (todos.map(\.id).max() ?? 0) + 1)
        let changes = ReminderSync.changes(from: known, to: todos)
        guard !changes.isEmpty else {
            return
        }
        do {
            for todo in changes.removed {
                try remove(todo)
            }
            for update in changes.updated {
                if let reminder = reminder(update.before.id) {
                    apply(update.after, to: reminder, before: update.before, isNew: false)
                    try store.save(reminder, commit: false)
                } else {
                    try create(update.after)
                }
            }
            for todo in changes.added {
                try create(todo)
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
        known = todos
    }

    private func reminder(_ id: Int) -> EKReminder? {
        identifiers[id].flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
    }

    /// 刪除前留下刪除快照（見 docs/specs/storage.md 的「刪除與刪除快照」）。
    private func remove(_ todo: Todo) throws {
        defer { identifiers[todo.id] = nil }
        guard let reminder = reminder(todo.id) else {
            return
        }
        tombstones[todo.id] = Tombstone(
            todo: todo,
            calendarIdentifier: reminder.calendar?.calendarIdentifier,
            notes: reminder.notes,
            url: reminder.url,
            priority: reminder.priority,
            location: reminder.location,
            alarms: (reminder.alarms ?? []).compactMap { $0.copy() as? EKAlarm },
            recurrenceRules: (reminder.recurrenceRules ?? []).compactMap { $0.copy() as? EKRecurrenceRule },
            start: reminder.startDateComponents
        )
        try store.remove(reminder, commit: false)
    }

    /// 新的待辦放進預設清單（測試清單打開時放進測試清單）；被刪過的 id 用刪除快照重建，放回原本的清單。
    private func create(_ todo: Todo, in calendar: EKCalendar? = nil) throws {
        let reminder = EKReminder(eventStore: store)
        let tombstone = tombstones.removeValue(forKey: todo.id)
        let original = tombstone?.calendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
        guard let target = calendar ?? original ?? testCalendar ?? store.defaultCalendarForNewReminders() else {
            throw ToolError(message: "沒有可以放待辦的提醒事項清單")
        }
        reminder.calendar = target
        if let tombstone {
            reminder.notes = tombstone.notes
            reminder.url = tombstone.url
            reminder.priority = tombstone.priority
            reminder.location = tombstone.location
            reminder.recurrenceRules = tombstone.recurrenceRules
            reminder.startDateComponents = tombstone.start
            tombstone.alarms.forEach(reminder.addAlarm)
        }
        apply(todo, to: reminder, before: tombstone?.todo, isNew: true)
        try store.save(reminder, commit: false)
        identifiers[todo.id] = reminder.calendarItemIdentifier
    }

    /// 只改標題、到期日、完成；改到日期或時間時，alarm 與開始日期跟著移（見 docs/specs/notifications.md）。
    private func apply(_ todo: Todo, to reminder: EKReminder, before: Todo?, isNew: Bool) {
        if reminder.title != todo.content {
            reminder.title = todo.content
        }
        if reminder.isCompleted != todo.isDone {
            reminder.isCompleted = todo.isDone
        }
        guard ReminderSync.writesDue(isNew: isNew, before: before, after: todo) else {
            return
        }
        let current = ReminderSync.Alarms(
            absolute: (reminder.alarms ?? []).compactMap(\.absoluteDate),
            hasRelative: (reminder.alarms ?? []).contains { $0.absoluteDate == nil },
            start: reminder.startDateComponents.flatMap { Calendar.current.date(from: $0) }
        )
        let next = ReminderSync.alarms(current, before: before, after: todo)
        reminder.dueDateComponents = ReminderSync.dueComponents(todo)
        if next.absolute != current.absolute {
            for alarm in reminder.alarms ?? [] where alarm.absoluteDate != nil {
                reminder.removeAlarm(alarm)
            }
            next.absolute.forEach { reminder.addAlarm(EKAlarm(absoluteDate: $0)) }
        }
        if next.start != current.start {
            reminder.startDateComponents = next.start.map {
                Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
            }
        }
    }

    // MARK: - 測試清單（見 docs/specs/storage.md 的「測試清單」）

    func useTestData(_ seed: [Todo]?) async throws {
        try await requestAccess()
        do {
            // 上次沒關就結束 App 時，清單還留著：先刪掉。
            for calendar in store.calendars(for: .reminder) where calendar.title == Self.testListName {
                try store.removeCalendar(calendar, commit: false)
            }
            testCalendar = nil
            // 測試待辦的 id 和真實資料的刪除快照無關。
            tombstones = [:]
            if let seed {
                let calendar = EKCalendar(for: .reminder, eventStore: store)
                calendar.title = Self.testListName
                calendar.source = store.defaultCalendarForNewReminders()?.source
                try store.saveCalendar(calendar, commit: false)
                for todo in seed {
                    try create(todo, in: calendar)
                }
                testCalendar = calendar
            }
            try store.commit()
        } catch {
            store.reset()
            testCalendar = nil
            throw error
        }
        identifiers = [:]
        known = []
        hasLoadedRest = false
    }
}
