//
//  AutoAI.swift
//  voicecalender
//

import Foundation

/// 自動 AI：App 送出 AI 請求、取得 AI 回應（JSON 字串）的介面（見 docs/specs/judgment.md 的「自動 AI」）。
/// 每個實作自己處理提示詞、輸出結構與錯誤；失敗時丟出可以直接顯示的原因。
protocol AutoAI {
    /// 除錯 UI 與測試紀錄顯示的名稱。
    var name: String { get }
    /// 除錯 UI 顯示的狀態，例如模型是否可用。
    var status: String { get }
    /// 一般判斷、釐清後判斷送出的固定提示詞；測試紀錄開頭列出（見 docs/specs/judgment.md 的「紀錄」）。
    var judgePrompt: FixedPrompt { get }
    /// 刪除確認送出的固定提示詞。
    var confirmPrompt: FixedPrompt { get }
    /// 一般判斷或釐清後判斷，回傳指令清單 JSON。
    func judge(_ request: String) async throws -> String
    /// 刪除確認，回傳 `{"answer": "yes"}` 或 `{"answer": "no"}`。
    func confirmDelete(_ request: String) async throws -> String
}

/// 有校正功能的自動 AI（見 docs/specs/correction.md）。校正和判斷是不同的職責，介面分開；
/// 呼叫 API、設定由同一個自動 AI 的實作共用。
protocol CorrectionAI {
    /// 校正送出的固定提示詞。
    var correctionPrompt: FixedPrompt { get }
    /// 回傳 AI 校正後的句子；採不採用由 App 決定。
    func correct(_ request: String) async throws -> String
}

/// 有聊天功能的自動 AI（見 docs/specs/chat.md）。判斷沒有指令時依 App 的定位接話；不改變資料。
protocol ChatAI {
    /// 聊天送出的固定提示詞。
    var chatPrompt: FixedPrompt { get }
    /// 回傳聊天的回應；截斷與顯示由 App 決定。
    func chat(_ request: String) async throws -> String
}

/// 自動 AI 每次請求都帶的提示詞與輸出結構，不隨句子改變。
struct FixedPrompt {
    let instructions: String
    /// 輸出結構的文字（JSON Schema 或 Foundation Models 的 schema）。
    let schema: String
}

/// 實作丟出的錯誤：描述就是要顯示的原因。
struct AutoAIError: LocalizedError {
    let errorDescription: String?

    init(_ reason: String) {
        errorDescription = reason
    }
}
