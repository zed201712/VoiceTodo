//
//  TodoHistory.swift
//  voicecalender
//

import Foundation

/// undo／redo：記錄待辦的狀態，不記錄說過的話（見 docs/specs/recovery.md）。
struct TodoHistory {

    private var undoStates: [[Todo]] = []
    private var redoStates: [[Todo]] = []

    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    /// 一句話處理完：待辦有改變才記錄，並清空 redo。
    mutating func record(before: [Todo], after: [Todo]) {
        guard before != after else {
            return
        }
        undoStates.append(before)
        redoStates = []
    }

    /// 回傳上一個狀態；沒有就是 nil。
    mutating func undo(current: [Todo]) -> [Todo]? {
        guard let previous = undoStates.popLast() else {
            return nil
        }
        redoStates.append(current)
        return previous
    }

    /// 回傳 undo 之前的狀態；沒有就是 nil。
    mutating func redo(current: [Todo]) -> [Todo]? {
        guard let next = redoStates.popLast() else {
            return nil
        }
        undoStates.append(current)
        return next
    }

    /// 延遲讀取的待辦本來就一直存在，只是之前沒讀：補進每一個狀態，undo 換回舊的狀態時才不會被當成刪除
    /// （見 docs/specs/storage.md 的「延遲讀取」）。
    mutating func insert(_ todos: [Todo]) {
        undoStates = undoStates.map { $0 + todos }
        redoStates = redoStates.map { $0 + todos }
    }

    /// 從 current 變成 target 的差異，每項一行，給回話回報。
    static func changes(from current: [Todo], to target: [Todo]) -> [String] {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })
        let removed = current.filter { targetByID[$0.id] == nil }.map { "移除 \($0.line)" }
        let added = target.filter { currentByID[$0.id] == nil }.map { "加回 \($0.line)" }
        let changed = target
            .filter { todo in currentByID[todo.id].map { $0 != todo } ?? false }
            .map { "改為 \($0.line)" }
        return removed + added + changed
    }

    /// 外部變動的差異，給測試紀錄：帶 id 與加引號的內容，看得出識別碼換了、前後空白（見 docs/specs/storage.md 的「外部變動」）。
    static func storageChanges(from current: [Todo], to target: [Todo]) -> [String] {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })
        func describe(_ todo: Todo) -> String {
            "\(todo.isDone ? "☑" : "☐") \(todo.date ?? "-") \(todo.time ?? "-")「\(todo.content)」"
        }
        let removed = current.filter { targetByID[$0.id] == nil }.map { "移除 #\($0.id) \(describe($0))" }
        let added = target.filter { currentByID[$0.id] == nil }.map { "新增 #\($0.id) \(describe($0))" }
        let changed = target.compactMap { todo in
            currentByID[todo.id].flatMap { $0 != todo ? "修改 #\(todo.id) \(describe($0)) → \(describe(todo))" : nil }
        }
        return removed + added + changed
    }

    /// 從 current 變成 target 時有變化的待辦的日期：移除的取原本的日期，加回與改變的取之後的日期；沒有日期的不算。
    static func changedDays(from current: [Todo], to target: [Todo]) -> [String] {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })
        let removed = current.filter { targetByID[$0.id] == nil }
        let addedOrChanged = target.filter { currentByID[$0.id] != $0 }
        return (removed + addedOrChanged).compactMap(\.date)
    }
}
