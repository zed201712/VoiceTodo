//
//  SpokenReport.swift
//  voicecalender
//

import Foundation

/// 一條指令成功的結構化結果，給語音報告用（見 docs/specs/spoken-report.md）。刪除在確認後由小精靈產生。
enum Report: Equatable {
    case added(Todo)
    /// 用編號一次改好幾筆時有多筆，修改前後依同樣的順序。
    case modified(before: [Todo], after: [Todo])
    case deleted(count: Int)
    case setDone([Todo], isDone: Bool)
    /// 複製出來的新待辦。
    case copied([Todo])
    /// 查詢日期：使用者的說法與換算出的範圍（`yyyy-MM-dd`）。
    case date(phrase: String, from: String, to: String)
    /// 查詢後黑板上看得到的項目。
    case queried([Todo])
    /// 聊天的回應，照原文念（見 docs/specs/chat.md）。
    case chat(String)
    /// 查天氣：每天一句（見 docs/specs/weather.md 的「回報」）。
    case weather([String])
}

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
            case .queried:
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
            let when = "\(todo.date.map { day($0) } ?? "")\(todo.time.map { time($0) } ?? "")"
            return "\(when.isEmpty ? "" : "\(when)，")\(todo.content)\(todo.isDone ? "，已完成" : "")"
        }
        .joined(separator: "；") + "。"
    }

    /// 日期或時刻有改就念完整的日期＋時刻；內容有改就念新內容。
    private static func modified(_ before: Todo, _ after: Todo) -> String {
        var parts: [String] = []
        if before.date != after.date || before.time != after.time {
            parts.append("時間修改為\(after.date.map { day($0) } ?? "")\(after.time.map { time($0) } ?? "")")
        }
        if before.content != after.content {
            parts.append("內容修改為\(after.content)")
        }
        return parts.isEmpty ? "已修改待辦事項。" : "已將待辦事項" + parts.joined(separator: "，") + "。"
    }

    private static func date(_ phrase: String, from: String, to: String) -> String {
        if from == to {
            return "\(phrase)是\(day(from))。"
        }
        if from.hasSuffix("-01-01"), to.hasSuffix("-12-31"), from.prefix(4) == to.prefix(4) {
            return "\(phrase)是\(from.prefix(4))年。"
        }
        return "\(phrase)是\(day(from))到\(day(to))。"
    }

    /// `yyyy-MM-dd` → `10月9日星期五`
    static func day(_ day: String) -> String {
        guard let date = try? TodoStore.dayFormat.parse(day) else {
            return day
        }
        let calendar = DatePhrase.calendar
        let weekday = DatePhrase.weekdays[(calendar.component(.weekday, from: date) + 5) % 7].dropFirst()
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日星期\(weekday)"
    }

    /// `HH:mm` → 依時段念，例如 `13:30` → `下午1點30分`、`06:00` → `清晨6點`。
    static func time(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            return time
        }
        let (hour, minute) = (parts[0], parts[1])
        let period = switch hour {
        case ..<6: "凌晨"
        case ..<9: "清晨"
        case ..<12: "早上"
        case 12: "中午"
        case ..<18: "下午"
        default: "晚上"
        }
        let clock = hour > 12 ? hour - 12 : hour
        return "\(period)\(clock)點" + (minute == 0 ? "" : "\(minute)分")
    }
}
