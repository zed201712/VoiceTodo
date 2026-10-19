//
//  SpokenReport.swift
//  voice_todo
//

import Foundation

/// 語音報告念的句子：由規則從一句話的結果組成，不經過 AI（見 docs/specs/spoken-report.md 的「念的內容」）。
enum SpokenReport {

    /// `readAll` 關閉時，查詢只念這麼多項。
    static let limit = 3
    /// 不含回答的關鍵字：念的期間回答會被當成回音丟掉（見 docs/specs/spoken-report.md 的「念問題」）。
    static let askMore = "還有其他項目，其他的也念出來嗎？"
    static let seeScreen = "其他天請看畫面。"

    /// 念問題：第一行與最後一行之間列出的項目只念前 3 項，其餘請看畫面；回話照樣列出全部。
    static func question(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let items = lines.dropFirst().dropLast()
        guard lines.count > 2, items.count > limit else {
            return text
        }
        return ([lines[0]] + items.prefix(limit) + ["還有 \(items.count - limit) 項請看畫面。", lines[lines.count - 1]]).joined(separator: "\n")
    }

    /// 同一種動作合併，依第一次出現的順序；查詢念在最後。超過 3 項且可以詢問時，`unread` 是還沒念的項目。
    /// 沒有可念的結果時是 nil。
    static func compose(_ reports: [Report], readAll: Bool, canAsk: Bool = true) -> (text: String, unread: [Todo])? {
        var sentences: [String] = []
        var merged: Set<String> = []
        for report in reports {
            switch report {
            case .added:
                guard merged.insert("added").inserted else { continue }
                let count = reports.count { if case .added = $0 { true } else { false } }
                sentences.append(count == 1 ? "已新增一個待辦事項。" : "已新增 \(count) 個待辦事項。")
            case .deleted:
                guard merged.insert("deleted").inserted else { continue }
                let count = reports.reduce(0) { if case .deleted(let count) = $1 { $0 + count } else { $0 } }
                sentences.append("已刪除 \(count) 個待辦事項。")
            case .copied:
                guard merged.insert("copied").inserted else { continue }
                let count = reports.reduce(0) { if case .copied(let todos) = $1 { $0 + todos.count } else { $0 } }
                sentences.append(count == 1 ? "已複製一個待辦事項。" : "已複製 \(count) 個待辦事項。")
            case .modified(let before, let after):
                // 好幾筆只念筆數，細節看畫面。
                sentences.append(before.count == 1 && after.count == 1 ? modified(before[0], after[0]) : "已修改 \(before.count) 個待辦事項。")
            case .setDone(let todos, let isDone):
                let what = todos.count == 1 ? todos[0].content : " \(todos.count) 個待辦事項"
                sentences.append("已將\(what)設為\(isDone ? "完成" : "未完成")。")
            case .date(let phrase, let from, let to):
                sentences.append(date(phrase, from: from, to: to))
            case .chat(let reply):
                sentences.append(reply)
            case .weather(let days):
                // 天氣不詢問要不要全部念完，超過 3 天請使用者看畫面（見 docs/specs/spoken-report.md 的「念的內容」）。
                let read = readAll ? days : Array(days.prefix(limit))
                sentences.append(read.joined() + (read.count < days.count ? seeScreen : ""))
            case .queried, .display, .recovered, .nothingToRecover, .navigated:
                continue
            }
        }

        var unread: [Todo] = []
        let queried = reports.compactMap { if case .queried(let todos) = $0 { todos } else { nil } }
        if let todos = queried.last {
            if todos.isEmpty {
                sentences.append("沒有待辦事項。")
            } else {
                let read = readAll ? todos : Array(todos.prefix(limit))
                unread = canAsk ? Array(todos.dropFirst(read.count)) : []
                sentences.append("有 \(todos.count) 個待辦事項：" + items(read) + (unread.isEmpty ? "" : askMore))
            }
        }
        return sentences.isEmpty ? nil : (sentences.joined(), unread)
    }

    /// 逐項念：日期、星期、時刻（沒有時間就不念）、內容，已完成的加「已完成」；沒有日期的只念內容。項目之間用「；」，最後加句號。
    static func items(_ todos: [Todo]) -> String {
        todos.map { todo in
            let when = "\(todo.date.map { SpokenDate.day($0) } ?? "")\(todo.time.map { SpokenDate.time($0) } ?? "")"
            return "\(when.isEmpty ? "" : "\(when)，")\(todo.content)\(todo.isDone ? "，已完成" : "")"
        }
        .joined(separator: "；") + "。"
    }

    /// 日期或時刻有改就念完整的日期＋時刻；內容有改就念新內容。
    private static func modified(_ before: Todo, _ after: Todo) -> String {
        var parts: [String] = []
        if before.date != after.date || before.time != after.time {
            parts.append("時間修改為\(after.date.map { SpokenDate.day($0) } ?? "")\(after.time.map { SpokenDate.time($0) } ?? "")")
        }
        if before.content != after.content {
            parts.append("內容修改為\(after.content)")
        }
        return parts.isEmpty ? "已修改待辦事項。" : "已將待辦事項" + parts.joined(separator: "，") + "。"
    }

    private static func date(_ phrase: String, from: String, to: String) -> String {
        if from == to {
            return "\(phrase)是\(SpokenDate.day(from))。"
        }
        if from.hasSuffix("-01-01"), to.hasSuffix("-12-31"), from.prefix(4) == to.prefix(4) {
            return "\(phrase)是\(from.prefix(4))年。"
        }
        return "\(phrase)是\(SpokenDate.day(from))到\(SpokenDate.day(to))。"
    }
}

/// 回話的文字（見 docs/specs/todos.md 的「指令」）：和念的句子（`SpokenReport.compose`）由同一個結果組成，措辭只在這裡。
extension Report {

    /// 語音報告念不念它：設定顯示、復原、重做、換頁只有回話。
    var isSpoken: Bool {
        switch self {
        case .display, .recovered, .nothingToRecover, .navigated: false
        default: true
        }
    }

    var reply: String {
        switch self {
        case .added(let todo):
            "已新增 \(todo.line)"
        case .modified(let before, let after):
            zip(before, after).map { "已將 \(Self.describe($0)) 改為 \(Self.describe($1))" }.joined(separator: "\n")
        case .setDone(let todos, let isDone):
            todos.map { Self.done($0, isDone: isDone) }.joined(separator: "\n")
        case .copied(let copies):
            copies.map { "已複製 \($0.line)" }.joined(separator: "\n")
        case .deleted(let count):
            "已刪除 \(count) 項"
        case .date(let phrase, let from, let to):
            DatePhrase.answer(phrase, from: from, to: to)
        case .queried(let todos):
            todos.isEmpty ? "找不到" : "\(todos.count) 件待辦"
        case .chat(let text):
            text
        case .weather(let days):
            days.joined(separator: "\n")
        case .display(let showDone):
            "完成：\(showDone ? "顯示" : "隱藏")"
        case .recovered(let undo, let before, let after):
            ([undo ? "已復原：" : "已重做："] + Self.changes(from: before, to: after)).joined(separator: "\n")
        case .nothingToRecover(let undo):
            undo ? "沒有可以復原的狀態" : "沒有可以重做的狀態"
        case .navigated(.showEverything, _):
            "已顯示所有資料"
        case .navigated(.back, let moved):
            moved ? "已回到上一頁" : "沒有上一頁"
        case .navigated(.forward, let moved):
            moved ? "已到下一頁" : "沒有下一頁"
        }
    }

    /// 設定完成的回話；點黑板的方框也是這一句。
    private static func done(_ todo: Todo, isDone: Bool) -> String {
        "已將 \([todo.date, todo.content].compactMap { $0 }.joined(separator: " ")) 設為\(isDone ? "已完成" : "未完成")"
    }

    private static func describe(_ todo: Todo) -> String {
        [todo.date, todo.time, todo.content].compactMap { $0 }.joined(separator: " ")
    }

    /// 復原、重做從 before 變成 after 的差異，每項一行。
    static func changes(from before: [Todo], to after: [Todo]) -> [String] {
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let removed = before.filter { afterByID[$0.id] == nil }.map { "移除 \($0.line)" }
        let added = after.filter { beforeByID[$0.id] == nil }.map { "加回 \($0.line)" }
        let changed = after
            .filter { todo in beforeByID[todo.id].map { $0 != todo } ?? false }
            .map { "改為 \($0.line)" }
        return removed + added + changed
    }
}
