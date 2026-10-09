//
//  JudgeTool.swift
//  voicecalender
//

import Foundation

/// 規則判斷（見 docs/specs/judge-tool.md）：整句完全符合固定句型、日期時間能被完整解析時，
/// 直接產生指令，取代那一次的 AI 判斷；不確定就回傳 nil，交給 AI。寧可不命中，也不能命中錯誤。
enum JudgeTool {

    /// 固定的話：整句完全等於。
    private static let fixed: [String: Command] = [
        "顯示完成": Command(.setDisplay, showDone: true),
        "勾選完成": Command(.setDisplay, showDone: true),
        "隱藏完成": Command(.setDisplay, showDone: false),
        "取消勾選完成": Command(.setDisplay, showDone: false),
        "刪除全部": Command(.deleteTodos),
        "刪除完成": Command(.deleteTodos, isDone: true),
        "刪除完成項目": Command(.deleteTodos, isDone: true),
        "刪除已完成": Command(.deleteTodos, isDone: true),
        "刪除已完成項目": Command(.deleteTodos, isDone: true),
        "清除完成項目": Command(.deleteTodos, isDone: true),
        "今天會下雨嗎": Command(.weather, date: "今天"),
        "明天會下雨嗎": Command(.weather, date: "明天"),
    ]

    /// 查詢待辦：`<日期時間>` 接在後面的句型（較長的先比對）；`allowsEmpty` 是可以沒有日期時間。
    private static let querySuffixes: [(suffix: String, allowsEmpty: Bool)] = [
        ("有什麼事情", true), ("有什麼事", true), ("有什麼待辦", true), ("有什麼行程", true), ("有什麼安排", true),
        ("有哪些事", true), ("要做什麼", true), ("有事嗎", true), ("的待辦", false),
    ]
    private static let queryPrefixes = ["顯示", "查詢"]

    /// 查詢日期：`<日期>` 接在後面的句型，可以沒有日期。
    private static let dateSuffixes = ["是幾月幾號", "是幾號", "是星期幾", "是禮拜幾", "幾號", "星期幾", "禮拜幾"]

    /// 一般判斷之前才比對的固定說法：等回答時它們有別的意思（錯誤確認的復原、要全部念完嗎的回答），
    /// 所以不在 `command` 裡（見 docs/specs/judge-tool.md 的「固定的話」）。
    static func generalCommand(_ text: String) -> Command? {
        switch RecoveryKeywords.action(text) {
        case .undo?: return Command(.undo)
        case .redo?: return Command(.redo)
        default: break
        }
        switch BoardKeywords.action(text) {
        case .showEverything?: return Command(.showEverything)
        case .back?: return Command(.previousPage)
        case .forward?: return Command(.nextPage)
        case nil: break
        }
        // 備份暫停（見 docs/specs/backup.md）。
        // switch BackupKeywords.action(text) {
        // case .create?: return Command(.createBackup)
        // case .replace?: return Command(.replaceBackup)
        // case nil: break
        // }
        return ReportKeywords.isReadAll(text) ? Command(.readAll) : nil
    }

    /// 叫出總導覽的話（見 docs/specs/judge-tool.md 的「提示」）。
    private static let overview: Set = ["提示", "幫助", "說明", "怎麼用", "怎麼使用", "如何使用"]

    /// 提示：總導覽、`如何<頁名>`、`怎麼<頁名>`、`<頁名>怎麼用`、上個提示、下個提示，
    /// 與還沒凍結的提示那一頁的連結名稱（`links`，沒有就是空的）。
    private static func hint(_ word: String, links: [String]) -> Command? {
        if overview.contains(word) {
            return Command(.help, page: HintPage.overview)
        }
        switch word {
        case "上個提示": return Command(.previousHint)
        case "下個提示": return Command(.nextHint)
        default: break
        }
        if links.contains(word) {
            return Command(.help, page: word)
        }
        let page = HintPage.all.first { ["如何\($0.name)", "怎麼\($0.name)", "\($0.name)怎麼用"].contains(word) }
        return page.map { Command(.help, page: $0.name) }
    }

    /// `links` 是快照裡還沒凍結的提示那一頁的連結名稱，只在一般判斷時給。
    static func command(_ text: String, today: Date, links: [String] = []) -> Command? {
        let word = ConfirmationKeywords.normalized(text)
        // 編號的句型不去掉結尾的「呢」「嗎」：「刪除第3項嗎」是在問（見 docs/specs/judge-tool.md 的「編號」）。
        if let command = numbered(word, today: today) {
            return command
        }
        // 結尾可以多一個「呢」「嗎」：原句沒命中才去掉再試（「有事嗎」本身就帶「嗎」）。
        var candidates = [word]
        if let last = word.last, "呢嗎".contains(last) {
            candidates.append(String(word.dropLast()))
        }
        for candidate in candidates {
            if let command = match(candidate, today: today, links: links) {
                return command
            }
        }
        return nil
    }

    private static func match(_ word: String, today: Date, links: [String]) -> Command? {
        if let command = fixed[word] ?? hint(word, links: links) {
            return command
        }
        for (suffix, allowsEmpty) in querySuffixes where word.hasSuffix(suffix) {
            let phrase = String(word.dropLast(suffix.count))
            if phrase.isEmpty {
                return allowsEmpty ? Command(.queryTodos) : nil
            }
            return date(phrase, today: today, mustBeDays: false).map { Command(.queryTodos, date: $0) }
        }
        for prefix in queryPrefixes where word.hasPrefix(prefix) {
            let phrase = String(word.dropFirst(prefix.count))
            return phrase.isEmpty ? nil : date(phrase, today: today, mustBeDays: false).map { Command(.queryTodos, date: $0) }
        }
        for suffix in dateSuffixes where word.hasSuffix(suffix) {
            let phrase = String(word.dropLast(suffix.count))
            if phrase.isEmpty {
                return Command(.queryDate)
            }
            return date(phrase, today: today, mustBeDays: true).map { Command(.queryDate, date: $0) }
        }
        return nil
    }

    /// `<編號>`：第N項、第N項到第M項、第N到M項、第N到第M項；N、M 是阿拉伯數字或國字數字。長的寫法先比對。
    private static let number = /第([0-9零一二兩三四五六七八九十]+)(?:項到第([0-9零一二兩三四五六七八九十]+)項|到第?([0-9零一二兩三四五六七八九十]+)項|項)/

    /// 整句是 `<編號>` 時的 number 寫法（「2」或「3~10」）；AI 把編號寫進 keyword 時用（見 docs/specs/judgment.md 的「JSON 格式」）。
    static func number(_ text: String) -> String? {
        guard let match = text.wholeMatch(of: number), let first = value(match.1) else {
            return nil
        }
        guard let end = match.2 ?? match.3 else {
            return String(first)
        }
        return value(end).map { "\(first)~\($0)" }
    }

    /// 只用編號描述目標的刪除、設定完成、修改日期（見 docs/specs/judge-tool.md 的「編號」）。
    private static func numbered(_ word: String, today: Date) -> Command? {
        guard let match = word.firstMatch(of: number), let first = value(match.1) else {
            return nil
        }
        var range = String(first)
        if let end = match.2 ?? match.3 {
            guard let last = value(end) else {
                return nil
            }
            range += "~\(last)"
        }
        // 開頭的「將」和「把」相同（「將第三項改到明天」）。
        let before = String(word[..<match.range.lowerBound]).replacingOccurrences(of: "將", with: "把")
        let after = String(word[match.range.upperBound...])
        switch (before, after) {
        case ("刪除", ""), ("刪掉", ""), ("", "刪除"), ("", "刪掉"), ("把", "刪除"), ("把", "刪掉"):
            return Command(.deleteTodos, number: range)
        case ("完成", ""), ("", "完成"), ("把", "設為完成"):
            return Command(.setDone, number: range, isDone: true)
        case ("", _), ("把", _):
            for verb in ["移到", "改到", "延到"] where after.hasPrefix(verb) {
                let phrase = String(after.dropFirst(verb.count))
                return phrase.isEmpty ? nil : date(phrase, today: today, mustBeDays: false).map { Command(.modifyTodo, number: range, newDate: $0) }
            }
            return nil
        default:
            return nil
        }
    }

    private static func value(_ text: Substring) -> Int? {
        Int(text) ?? numeral(String(text))
    }

    /// 改寫成公開的寫法，日期與時間解析完整解析成功才回傳；查詢日期要有一段日期。
    private static func date(_ phrase: String, today: Date, mustBeDays: Bool) -> String? {
        let text = rewrite(phrase)
        guard case .success(let date) = DatePhrase.parse(text, today: today) else {
            return nil
        }
        if mustBeDays, case .range = date.days {
            return text
        }
        return mustBeDays ? nil : text
    }

    /// 說法改寫，和判斷提示詞的「寫法」相同（見 docs/specs/judge-tool.md 的「說法改寫」）。
    static func rewrite(_ phrase: String) -> String {
        var text = phrase
            .replacingOccurrences(of: "接下來一週", with: "目前")
            .replacingOccurrences(of: "接下來七天", with: "目前")
            .replacingOccurrences(of: "接下來", with: "目前")
        // 國字數字：後面接年月日號點分，或接在「月」後面（「十月十二」）。
        text = text.replacing(/月([零一二兩三四五六七八九十]+)/) { match in
            "月" + (numeral(String(match.1)).map(String.init) ?? String(match.1))
        }
        text = text.replacing(/([零一二兩三四五六七八九十]+)(?=[年月日號點分])/) { match in
            numeral(String(match.1)).map(String.init) ?? String(match.1)
        }
        text = text
            .replacingOccurrences(of: "點半", with: "點30分")
            .replacingOccurrences(of: "號", with: "日")
            .replacingOccurrences(of: "禮拜", with: "週")
            .replacingOccurrences(of: "星期", with: "週")
            .replacingOccurrences(of: "週天", with: "週日")
            .replacingOccurrences(of: "這週", with: "本週")
        // M月D 後面沒有接日、點時補上日（「10月12」→「10月12日」）；接點時分不清是日還是時，不補。
        text = text.replacing(/(\d{1,2})月(\d{1,2})(?![\d日點])/) { "\($0.1)月\($0.2)日" }
        return text.replacing(/(上|本|下)週([一二三四五六日])/) { "\($0.1)週週\($0.2)" }
    }

    /// 國字數字：一～九、十、十一～九十九、兩，以及逐位的寫法（「二零二六」）。
    private static func numeral(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        guard text.contains("十") else {
            let values = text.compactMap { digits[$0] }
            return values.count == text.count ? values.reduce(0) { $0 * 10 + $1 } : nil
        }
        let parts = text.split(separator: "十", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count <= 1, parts[1].count <= 1 else {
            return nil
        }
        let tens = parts[0].isEmpty ? 1 : digits[parts[0].first!]
        let ones = parts[1].isEmpty ? 0 : digits[parts[1].first!]
        guard let tens, let ones else {
            return nil
        }
        return tens * 10 + ones
    }
}
