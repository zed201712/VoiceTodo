//
//  TodoStore.swift
//  voicecalender
//

import Foundation
import Observation

struct Todo: Identifiable, Equatable {
    let id: Int
    /// `yyyy-MM-dd`；從提醒事項讀進來的可以沒有（見 docs/specs/todos.md 的「沒有日期的待辦」）。
    var date: String?
    /// `HH:mm`；可以沒有（見 docs/specs/todos.md 的「資料」）。
    var time: String?
    var content: String
    var isDone = false

    /// 回話列出待辦的一行，格式和黑板相同：`☐ 10/3（六） 06:00 看牙醫`；沒有日期、時間的省略（見 docs/specs/todos.md）。
    var line: String {
        [isDone ? "☑" : "☐", date.map { DatePhrase.dayLabel($0) }, time, content].compactMap { $0 }.joined(separator: " ")
    }

    /// 排序：有日期的在前，依日期、時間（沒有時間當成 00:00，排在同一天最前面），再依 id；沒有日期的排在最後。
    var order: (Int, String, String, Int) { (date == nil ? 1 : 0, date ?? "", time ?? "00:00", id) }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 待辦的資料與基本操作，由待辦清單（TodoList）使用（見 docs/specs/todos.md）。每個操作檢查參數，不合法就丟出 ToolError。
@Observable
final class TodoStore {

    private(set) var todos: [Todo] = []
    /// 沒有權限或讀取失敗的原因：這時沒有存檔，所有指令都放棄（見 docs/specs/storage.md 的「權限」）。
    private(set) var unavailableReason: String?

    /// 只增不減：存檔讀進來的 id 也算，刪掉的 id 不會再被新增的待辦用到（undo 的歷史與刪除快照靠 id 對應）。
    private var nextID = 1
    private var snapshot: [Todo]?
    /// nil 時不存檔（單元測試、Preview）。
    private let storage: (any TodoStorage)?

    /// `todos` 是沒有存檔時（單元測試、Preview）一開始的待辦。
    init(storage: (any TodoStorage)? = nil, todos: [Todo] = []) {
        self.storage = storage
        adopt(todos)
    }

    /// 讀取存檔：App 啟動、重新開始、外部變動、回到前景時（見 docs/specs/storage.md）。
    /// 回傳待辦是否和讀取前不同；沒有權限或讀取失敗時待辦清空，原因放在 `unavailableReason`。
    @discardableResult
    func load() async -> Bool {
        guard let storage else {
            return false
        }
        let before = todos
        do {
            adopt(try await storage.load())
            unavailableReason = nil
        } catch {
            adopt([])
            unavailableReason = error.localizedDescription
        }
        return Self.sorted(before) != Self.sorted(todos)
    }

    /// 延遲讀取：讀取時沒給的其餘待辦（已完成的），加進目前的待辦並回傳；已經讀過時是空的（見 docs/specs/storage.md 的「延遲讀取」）。
    func loadRest() async throws -> [Todo] {
        guard let storage else {
            return []
        }
        let rest = try await storage.loadRest()
        adopt(todos + rest)
        return rest
    }

    /// 測試清單：換成只有 `seed` 的獨立資料；nil 是換回真實的資料（見 docs/specs/storage.md 的「測試清單」）。
    func useTestData(_ seed: [Todo]?) async throws {
        try await storage?.useTestData(seed)
        await load()
    }

    private func adopt(_ todos: [Todo]) {
        self.todos = todos
        nextID = max(nextID, (todos.map(\.id).max() ?? 0) + 1)
    }

    private static func sorted(_ todos: [Todo]) -> [Todo] {
        todos.sorted { $0.id < $1.id }
    }

    // MARK: - 任務

    /// 任務開始：拍快照。
    func beginTask() {
        snapshot = todos
    }

    /// 任務結束。`restore` 為 true 時（取消、放棄）還原到任務開始前。
    func endTask(restore: Bool) {
        if restore, let snapshot {
            todos = snapshot
        }
        snapshot = nil
        save()
    }

    /// undo／redo：整份換成記錄的狀態並存檔（見 docs/specs/recovery.md）。
    func replace(with todos: [Todo]) {
        self.todos = todos
        save()
    }

    // 換成備份暫停（見 docs/specs/backup.md）。
    // /// 換成備份：整份取代、重新編 id 並存檔（見 docs/specs/backup.md）。
    // func replace(withBackup backup: [Todo]) {
    //     todos = backup.map {
    //         defer { nextID += 1 }
    //         return Todo(id: nextID, date: $0.date, time: $0.time, content: $0.content, isDone: $0.isDone)
    //     }
    //     save()
    // }

    // MARK: - 執行器

    func queryTodos(from: String, to: String) throws -> [Todo] {
        let from = try Self.validDay(from)
        let to = try Self.validDay(to)
        return todos
            .filter { $0.date.map { $0 >= from && $0 <= to } ?? false }
            .sorted { $0.order < $1.order }
    }

    @discardableResult
    func addTodo(date: String, time: String? = nil, content: String) throws -> Todo {
        let date = try Self.validDay(date)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ToolError(message: "內容是空白的")
        }
        let todo = Todo(id: nextID, date: date, time: time, content: content)
        nextID += 1
        todos.append(todo)
        return todo
    }

    func setDone(id: Int, isDone: Bool) throws {
        let index = try index(of: id)
        todos[index].isDone = isDone
    }

    func modifyTodo(id: Int, date: String?, time: String? = nil, content: String?) throws {
        let index = try index(of: id)
        let date = try date.map(Self.validDay)
        let content = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard date != nil || time != nil || content?.isEmpty == false else {
            throw ToolError(message: "沒有要修改的日期、時間或內容")
        }
        if let date { todos[index].date = date }
        if let time { todos[index].time = time }
        if let content, !content.isEmpty { todos[index].content = content }
    }

    /// 刪除。確認由判斷階段負責（見 docs/specs/judgment.md 的「刪除確認」）。
    func delete(ids: [Int]) {
        todos.removeAll { ids.contains($0.id) }
    }

    // MARK: - Helpers

    /// 寫入失敗只印到 console：資料仍在記憶體裡，App 可以繼續用（見 docs/specs/storage.md 的「寫入」）。
    private func save() {
        do {
            try storage?.save(todos)
        } catch {
            print("[Storage] 寫入失敗：\(error)")
        }
    }

    private func index(of id: Int) throws -> Int {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            throw ToolError(message: "找不到 id \(id) 的待辦")
        }
        return index
    }

    static let dayFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    static func dayString(_ date: Date) -> String {
        date.formatted(dayFormat)
    }

    static func isValidDay(_ text: String) -> Bool {
        guard let date = try? dayFormat.parse(text) else {
            return false
        }
        return dayString(date) == text
    }

    private static func validDay(_ text: String) throws -> String {
        guard isValidDay(text) else {
            throw ToolError(message: "日期不合法：\(text)，格式應為 yyyy-MM-dd")
        }
        return text
    }
}
