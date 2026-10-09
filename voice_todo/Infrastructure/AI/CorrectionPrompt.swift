//
//  CorrectionPrompt.swift
//  voicecalender
//

import Foundation

/// 校正的提示詞與輸出結構（見 docs/specs/correction.md）。和判斷提示詞分開：
/// 不放執行器與日期語法，舊的校正放了指令清單，AI 會往指令的方向改寫（「新增」→「新增待辦」）。
enum CorrectionPrompt {

    static let instructions = """
        你是語音辨識的錯字校正。使用者用語音說出對待辦清單的需求，語音辨識可能把字聽成同音或近音的錯字。
        - 依常識修正錯字，例如「10月6號麵是」→「10月6號面試」。
        - 和「黑板上的待辦」裡的人名、名詞發音相近時，改成黑板上的寫法，例如黑板有「跟小美吃飯」，「跟小每出去玩」→「跟小美出去玩」。
        - 「小精靈剛才問」是使用者正在回答的問題，可以當作線索。
        - 只能一個字換一個字，字數必須和原句相同；不加字、不刪字、不改語序與語氣，不回答問題。
        - 沒有錯字就原樣輸出「使用者說」的內容，這是最常見的結果。
        """

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["text": ["type": "string"]],
        "required": ["text"],
        "additionalProperties": false,
    ]
}
