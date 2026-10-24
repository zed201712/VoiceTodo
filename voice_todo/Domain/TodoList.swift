//
//  TodoList.swift
//  voice_todo
//

import Foundation
import Observation

/// 待辦清單（見 CONTEXT.md）：待辦、黑板、undo 與改變它們的執行器。
/// 上層交給它指令、拿回結構化的結果（`Report`），不直接碰 TodoStore、Board、TodoHistory；回話與念的句子由上層組成。
@Observable
final class TodoList {

    private let store: TodoStore
    private let board: Board
    private var history = TodoHistory()
    /// 這句話的 undo 狀態從哪裡開始；同一句話裡復原、重做後移到那之後（見 docs/specs/todos.md 的「指令」）。
    private var undoStart: [Todo] = []
    private let storage: (any TodoStorage)?
    /// 有沒有存檔：沒有時（單元測試、Preview）不讀寫。
    var hasStorage: Bool { storage != nil }
    /// 存檔被 App 以外的地方改了（見 docs/specs/storage.md 的「外部變動」）。
    var onExternalChange: (() -> Void)? {
        get { storage?.onExternalChange }
        set { storage?.onExternalChange = newValue }
    }

    /// `todos` 是沒有存檔時（單元測試、Preview）一開始的待辦，沒給是測試待辦；`boardPage`、`showDone` 是存檔的黑板頁與 checkbox。
    init(storage: (any TodoStorage)? = nil, todos: [Todo]? = nil, boardPage: BoardPage.Saved? = nil, showDone: Bool = false) {
        self.storage = storage
        store = TodoStore(storage: storage, todos: storage == nil ? todos ?? TestTodos.make() : [])
        board = Board(today: .now, saved: boardPage, showDone: showDone)
    }

    // MARK: - 讀

    var todos: [Todo] { store.todos }
    var page: BoardPage { board.page }
    var showDone: Bool { board.showDone }
    var canGoBack: Bool { board.canGoBack }
    var canGoForward: Bool { board.canGoForward }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    /// 沒有權限或讀取失敗的原因：這時待辦的所有指令都放棄（見 docs/specs/storage.md 的「權限」）。
    var unavailableReason: String? { store.unavailableReason }

    /// 黑板看得到的待辦，依編號的順序。
    func visible(today: Date = .now) -> [Todo] {
        board.visible(store.todos, today: TodoStore.dayString(today))
    }

    // MARK: - 存檔（見 docs/specs/storage.md）

    /// 讀取存檔；回傳待辦是否改變。沒有存檔時不讀。
    @discardableResult
    func load() async -> Bool {
        hasStorage ? await store.load() : false
    }

    /// 延遲讀取已完成的待辦，補進 undo 歷史的每一個狀態；回傳讀到幾筆。沒有存檔時不讀。
    func loadRest() async throws -> Int {
        guard hasStorage else {
            return 0
        }
        let rest = try await store.loadRest()
        history.insert(rest)
        undoStart += rest
        return rest.count
    }

    /// 勾選「完成」之前要先讀已完成的：設定顯示勾選完成、刪除完成自動勾選（見 docs/specs/todos.md 的「黑板」）。
    func needsRest(_ command: Command) -> Bool {
        guard hasStorage, !board.showDone else {
            return false
        }
        return command.action == .setDisplay && command.showDone == true
            || command.action == .deleteTodos && command.isDone == true
    }

    /// 測試清單：換成 `seed` 或換回所有清單，清空 undo 的歷史。
    func useTestData(_ seed: [Todo]?) async throws {
        history = TodoHistory()
        try await store.useTestData(seed)
    }

    /// 存檔被外部改了、讀回來的從 before 變成 after：差 5 項以內記成 undo 的一步，超過就清空 undo 的歷史
    /// （見 docs/specs/storage.md 的「外部變動」）。回傳有沒有記成一步。
    @discardableResult
    func externalChange(from before: [Todo], to after: [Todo]) -> Bool {
        guard TodoHistory.storageChanges(from: before, to: after).count <= 5 else {
            history = TodoHistory()
            return false
        }
        history.record(before: before, after: after)
        return true
    }

    /// 重新開始：清空 undo 的歷史，黑板回到「目前」；不改待辦。
    func restart(today: Date = .now) {
        history = TodoHistory()
        board.reset(today: today)
    }

    // MARK: - 一句話

    /// 一句話開始執行：記下 undo 狀態的起點。
    func beginSentence() {
        undoStart = store.todos
    }

    /// 一句話處理完：待辦有改變才記一個 undo 狀態。
    func endSentence() {
        history.record(before: undoStart, after: store.todos)
    }

    /// 記下黑板上的編號：一句話開始執行指令時，以使用者看到的那一頁為準（見 docs/specs/todos.md 的「編號」）。
    func fixNumbers(today: Date = .now) {
        board.fixNumbers(store.todos, today: TodoStore.dayString(today))
    }

    // MARK: - 任務

    /// 執行一條待辦清單的指令（查天氣、說明、全部念完由上層執行）。完成時保留、放棄或找不到時還原；釐清與刪除確認時任務保持開著，
    /// 等 `confirmDelete`、`cancelTask` 結束。
    func run(_ command: Command, today: Date = .now) -> CommandOutcome {
        switch command.action {
        case .undo, .redo:
            // 同一句話裡前面的改變先記成一個 undo 狀態，再復原或重做。
            history.record(before: undoStart, after: store.todos)
            let report = moveHistory(undo: command.action == .undo)
            undoStart = store.todos
            return .done(report)
        case .previousPage: return .done(navigate(.back))
        case .nextPage: return .done(navigate(.forward))
        case .showEverything: return .done(navigate(.showEverything))
        default:
            store.beginTask()
            let outcome = CommandExecutor(store: store, board: board, today: today).execute(command)
            switch outcome {
            case .done: store.endTask(restore: false)
            case .abandon, .notFound: store.endTask(restore: true)
            case .clarify, .confirmDelete: break
            }
            return outcome
        }
    }

    /// 刪除確認回答 yes：刪除並結束任務，回傳刪掉的待辦。
    @discardableResult
    func confirmDelete(ids: [Int]) -> [Todo] {
        let deleted = store.todos.filter { ids.contains($0.id) }
        store.delete(ids: ids)
        store.endTask(restore: false)
        return deleted
    }

    /// 取消開著的任務（刪除確認回答 no、釐清後由新的指令取代）：資料還原到任務開始前。
    func cancelTask() {
        store.endTask(restore: true)
    }

    // MARK: - 觸控

    /// 按復原、重做，或錯誤確認中說的復原、重做。
    func undo() -> Report { moveHistory(undo: true) }
    func redo() -> Report { moveHistory(undo: false) }

    /// 點方框：等於一條用編號指定的設定完成指令，記一個 undo 狀態；不在黑板上時是 nil。
    func toggleDone(id: Int, today: Date = .now) -> Report? {
        guard let index = visible(today: today).firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let isDone = !store.todos[store.todos.firstIndex { $0.id == id }!].isDone
        beginSentence()
        fixNumbers(today: today)
        let outcome = run(Command(.setDone, number: "\(index + 1)", isDone: isDone), today: today)
        endSentence()
        guard case .done(let report) = outcome else {
            return nil
        }
        return report
    }

    /// 黑板的上一頁、下一頁、顯示全部。
    @discardableResult
    func navigate(_ action: BoardAction) -> Report {
        switch action {
        case .showEverything:
            board.move(to: .everything)
            return .navigated(action, moved: true)
        case .back:
            defer { board.goBack() }
            return .navigated(action, moved: board.canGoBack)
        case .forward:
            defer { board.goForward() }
            return .navigated(action, moved: board.canGoForward)
        }
    }

    // MARK: - Helpers

    /// 資料換成上一個（undo）或 undo 之前（redo）的狀態，回報差異並存檔；黑板沒有涵蓋這些變化時，才移到看得到它們的範圍。
    private func moveHistory(undo: Bool) -> Report {
        let current = store.todos
        guard let target = undo ? history.undo(current: current) : history.redo(current: current) else {
            return .nothingToRecover(undo: undo)
        }
        store.replace(with: target)
        let days = TodoHistory.changedDays(from: current, to: target)
        if let first = days.min(), let last = days.max() {
            board.reveal(from: first, to: last)
        }
        board.reveal(target.filter { !current.contains($0) })
        return .recovered(undo: undo, before: current, after: target)
    }
}
