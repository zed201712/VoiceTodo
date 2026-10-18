//
//  JudgePrompt.swift
//  voicecalender
//

import Foundation

/// 自動 AI 共用的提示詞，與以 JSON Schema 限制輸出的自動 AI（Ollama、Gemini）的輸出結構。
enum JudgePrompt {

    static let confirmInstructions = """
        判斷使用者對刪除確認的回答是 yes、no 還是 other：
        - yes：同意刪除列出的全部；回答要刪的是列出的全部，也算同意。
        - other：只指定其中某些項目，或說了新的需求。
        - no：其他情況，包括拒絕、猶豫或不明確。
        """

    // MARK: - 提示詞

    // 判斷提示詞的片段；Ollama、Gemini、Foundation Models 都用 judgeInstructions。
    // 手動 AI 的提示詞（docs/eval/judge-prompt.md）是 judgeInstructions 的複本，改這裡要手動同步那份文件；不一致時單元測試失敗。

    static let intro = "你是待辦清單 App 的助理。把使用者的話翻成指令清單，由 App 執行。"

    static let dates = """
        日期（最重要，App 只認得下列寫法）：
        - date、newDate 是一個字串，由下列單位依順序組成（大到小），至少一項；沒說的單位就省略，單位之間不留空白：
          1. 年：\(DatePhrase.years.keys.sorted { DatePhrase.years[$0]! < DatePhrase.years[$1]! }.joined(separator: "、"))、YYYY年
          2. 月：\(DatePhrase.months.keys.sorted { DatePhrase.months[$0]! < DatePhrase.months[$1]! }.joined(separator: "、"))、M月
          3. 週：\(DatePhrase.weeks.keys.sorted { DatePhrase.weeks[$0]! < DatePhrase.weeks[$1]! }.joined(separator: "、"))
          4. 日：\(DatePhrase.relativeDays.keys.sorted { DatePhrase.relativeDays[$0]! < DatePhrase.relativeDays[$1]! }.joined(separator: "、"))、D日、\(DatePhrase.weekdays.joined(separator: "、"))
          5. 時間：時刻，或「時刻以前」「時刻以後」「時刻到時刻」
             時刻：時段（\(TimePhrase.slotNames.joined(separator: "、"))），後面可以接「H點」或「H點M分」；也可以只有「H點」「H點M分」
        - 另外四種寫法：「下次」（今天起最早的一筆）、「目前」（今天起 7 天）、「所有」（只用在查詢待辦：使用者明確說「所有」「全部的〇〇」，不限日期）、範圍「單點~單點」（兩邊都不含時間）。
        - 照使用者說的單位改寫，不要換算成實際日期，也不要補上使用者沒說的單位；年份、星期由 App 換算。使用者沒說日期就不要寫日期，由 App 依畫面決定。
        - 寫法：「號」寫成「日」；「星期」「禮拜」寫成「週」，下週的星期五寫成「下週週五」；數字用阿拉伯數字；「半」寫成「30分」；「接下來」「接下來一週」「接下來七天」寫成「目前」；時間的範圍用「到」（「下午1點到3點」），日期的範圍用「~」。
        - 一週從週一開始。
        """

    static let rules = """
        規則：
        - 只輸出使用者明確要求的指令，依使用者說的順序；跟待辦、日期與天氣無關、聽不清楚或只是雜音時，只輸出一條「聽不懂」。
        - 問天氣狀況是查天氣；要記下一件跟天氣有關的事是新增待辦。
        - 問 App 怎麼用（有什麼功能、要怎麼說、要範例、例子或說明）：對得到某一頁提示就輸出「說明」，page 填那一頁；對不到才輸出一條「聽不懂」。
        - 有「提示」那一行時，使用者正在看那一頁提示；說了其中的連結（或想看那一頁）就輸出「說明」，page 填那個連結。
        - 用關鍵字描述要找的待辦，不要編造使用者沒說的內容。「事」「行程」「待辦」這類泛稱不是關鍵字，要省略。
        - 有「小精靈剛才問」時：使用者在回答問題，就輸出補齊後的指令；說的是新需求，就照新需求輸出。「不要」「算了」「取消」是不要做小精靈問的這件事，不是復原。
        - 使用者用畫面上的編號指定待辦時（「第2項」「3到10項」「第5到第10項」），number 填一個編號「2」或一段「3~10」，不寫 date、keyword；「第2和第5項」寫成兩條指令；日期（「10月3日」「3號」）不是編號。
        - 除了查詢待辦，使用者說的「全部」「所有」都是畫面上顯示的全部待辦：刪除全部時 date、keyword 都省略，不要寫「所有」。
        - 所有字串都用繁體中文（台灣用字），不可用簡體字；指令名稱與日期的單位要和上面的清單一字不差。
        """

    /// 判斷提示詞。
    static let judgeInstructions = """
        \(intro)

        指令（action）與欄位：
        \(Command.Action.allCases.map { "- \($0.rawValue)：\($0.meaning)。\($0.fieldsText)" }.joined(separator: "\n"))

        欄位說明：
        - date、newDate：日期字串，見下方「日期」；新增、修改、複製的時刻也寫在裡面。
        - content：新待辦的內容，只用在新增待辦。
        - keyword：用來找出已經存在的待辦，填待辦內容裡的關鍵字；新增待辦不用 keyword。
        - number：畫面上每筆待辦前面的編號，用來找出已經存在的待辦，見「規則」。
        - place：查天氣的地名，只用在查天氣。
        - page：提示的頁名，只用在說明。
        - isDone、showDone 是布林值，其他欄位都是字串。

        \(dates)

        \(rules)
        """

    // MARK: - 輸出結構

    // 每種指令只列自己的欄位（見 FoundationModelsAI 的同一段說明）；格式與 CommandJSON 相同。

    private static func schema(_ field: Command.Field) -> [String: Any] {
        switch field.kind {
        case .text: ["type": "string"]
        case .flag: ["type": "boolean"]
        case .oneOf(let values): ["enum": values]
        }
    }

    private static func command(_ action: Command.Action) -> [String: Any] {
        [
            "type": "object",
            "properties": Dictionary(uniqueKeysWithValues: action.fields.map { ($0.name, schema($0)) }).merging(["action": ["const": action.rawValue]]) { $1 },
            "required": ["action"] + action.fields.filter(\.required).map(\.name),
            "additionalProperties": false,
        ]
    }

    /// 每種指令一個選項，順序同 Command.Action。
    static let commandSchemas: [[String: Any]] = Command.Action.allCases.map(command)

    static let judgeSchema: [String: Any] = [
        "type": "object",
        "properties": ["commands": ["type": "array", "items": ["anyOf": commandSchemas]]],
        "required": ["commands"],
        "additionalProperties": false,
    ]

    static let confirmSchema: [String: Any] = [
        "type": "object",
        "properties": ["answer": ["enum": ["yes", "no", "other"]]],
        "required": ["answer"],
        "additionalProperties": false,
    ]

    /// 測試紀錄用的 Schema 文字。
    static func text(_ schema: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(schema)"
    }
}
