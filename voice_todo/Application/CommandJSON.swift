//
//  CommandJSON.swift
//  voicecalender
//

import Foundation

/// 判斷階段的邊界：自動 AI 與手動 AI 的結果一律是 JSON 字串，走同一個解析器
/// （見 docs/specs/judgment.md 的「JSON 格式」）。
enum CommandJSON {

    /// AI 回應不合法：描述就是要顯示的原因。
    struct Invalid: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Plan: Codable {
        var commands: [Entry]
    }

    /// 一條指令；日期是依單位順序組成的字串。修改待辦的新內容用 `newContent`，對應 `Command.content`。
    private struct Entry: Codable {
        var action: String
        var date: String?
        var keyword: String?
        var number: String?
        var content: String?
        var newDate: String?
        var newContent: String?
        var isDone: Bool?
        var showDone: Bool?
        var place: String?
        var page: String?
    }

    private struct Answer: Codable {
        var answer: String
    }

    static func encode(_ commands: [Command]) -> String {
        let entries = commands.map { command in
            let isModify = command.action == .modifyTodo
            return Entry(
                action: command.action.rawValue,
                date: command.date,
                keyword: command.keyword,
                number: command.number,
                content: isModify ? nil : command.content,
                newDate: command.newDate,
                newContent: isModify ? command.content : nil,
                isDone: command.isDone,
                showDone: command.showDone,
                place: command.place,
                page: command.page
            )
        }
        return string(Plan(commands: entries))
    }

    /// 不合法（不是 JSON、沒有 commands、action 不認得、型別錯誤）就丟出 Invalid。
    /// 指令名稱與日期說法只認繁體：自動 AI 偶爾輸出簡體，解析前先轉成繁體（繁體字不受影響；「周」也是繁體，不會變成「週」）。
    static func decode(_ json: String) throws -> [Command] {
        let json = json.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? json
        let plan = try parse(Plan.self, json)
        let clean = { (text: String?) in text.flatMap { $0.isEmpty ? nil : $0 } }
        // 日期套用說法改寫：提示詞要求的寫法（「號」寫成「日」等），AI 常沒照寫（見 docs/specs/judgment.md 的「JSON 格式」）。
        let date = { (text: String?) in clean(text).map(JudgeTool.rewrite) }
        return try plan.commands.map { entry in
            guard let action = Command.Action(rawValue: entry.action) else {
                throw Invalid(message: "不認得的指令：\(entry.action)")
            }
            var content = clean(action == .modifyTodo ? entry.newContent : entry.content)
            var when = clean(entry.date)
            if action == .addTodo, let text = content, let moved = movedTime(from: text, date: when) {
                (when, content) = moved
            }
            // keyword 整個是編號（「第一項」）就是 number。
            let numberInKeyword = clean(entry.keyword).flatMap(JudgeTool.number)
            return Command(
                action,
                date: date(when),
                keyword: numberInKeyword == nil ? clean(entry.keyword) : nil,
                number: numberInKeyword ?? clean(entry.number),
                content: content,
                newDate: date(entry.newDate),
                isDone: entry.isDone,
                showDone: entry.showDone,
                place: clean(entry.place),
                page: clean(entry.page)
            )
        }
    }

    /// 新增的 content 開頭是時刻（一定要有「點」）、date 沒有時間時，把時刻移到 date（「下午3點半看牙醫」→ date 加上「下午3點半」）。
    private static func movedTime(from content: String, date: String?) -> (date: String?, content: String)? {
        guard date?.contains("點") != true else {
            return nil
        }
        let slots = TimePhrase.slotNames.joined(separator: "|")
        guard let match = content.prefixMatch(of: try! Regex("(\(slots))?[0-9零一二兩三四五六七八九十]{1,3}點([0-9零一二兩三四五六七八九十]{1,3}分|半)?")) else {
            return nil
        }
        let rest = String(content[match.range.upperBound...])
        return rest.isEmpty ? nil : ((date ?? "") + content[match.range], rest)
    }

    static func encodeAnswer(_ answer: ConfirmAnswer) -> String {
        string(Answer(answer: answer.rawValue))
    }

    static func decodeAnswer(_ json: String) throws -> ConfirmAnswer {
        let answer = try parse(Answer.self, json).answer
        guard let value = ConfirmAnswer(rawValue: answer) else {
            throw Invalid(message: "answer 只能是 yes、no 或 other：\(answer)")
        }
        return value
    }

    private static func string(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }

    private static func parse<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch DecodingError.dataCorrupted {
            throw Invalid(message: "不是合法的 JSON")
        } catch DecodingError.keyNotFound(let key, _) {
            throw Invalid(message: "缺少欄位：\(key.stringValue)")
        } catch DecodingError.typeMismatch(_, let context) {
            throw Invalid(message: "欄位型別錯誤：\(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw Invalid(message: "格式不符：\(error.localizedDescription)")
        }
    }
}
