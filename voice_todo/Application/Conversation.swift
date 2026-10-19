//
//  Conversation.swift
//  voice_todo
//

import Foundation
import Observation

/// 對話流（見 CONTEXT.md、docs/specs/ui.md 的「對話流」）：固定的話與回話、還在更新的最後一則回話，
/// 以及提示對話框（見 docs/specs/help.md 的「提示對話框」）。
/// 最多只有一個還沒凍結的提示對話框，而且一定是最後一則：回話換成別的文字，或固定進對話流（凍結）時就不是了。
@Observable
final class Conversation {

    enum Mood {
        case listening, thinking, done, confused
    }

    /// 一則對話：使用者說的一句話（有句子編號），或小精靈的回話。
    struct Message: Identifiable, Equatable {
        let id: Int
        let sentence: Int?
        var text: String
        /// 查到天氣的回話：標示一直跟著它（見 docs/specs/weather.md 的「標示」）。
        var showsWeatherCredit = false
        /// 小精靈的回話的插畫：回話結束時的狀態，之後固定（見 docs/specs/ui.md 的「對話流」）。
        var mood = Mood.done
        /// 凍結的提示對話框停的那一頁（見 docs/specs/help.md 的「提示對話框」）。
        var hint: String?

        var isUser: Bool { sentence != nil }
    }

    /// 已經固定的話與回話，不存檔；最後一則回話還在更新時不在這裡，見 `liveReply`。
    private(set) var messages: [Message] = []
    /// 最後一則回話的文字，固定之後也留著（畫面資訊與紀錄用）；空字串是還沒有回話。
    private(set) var reply = ""
    private var isArchived = false
    /// 回話是提示對話框時的那一頁。
    private var hintPage: HintPage?

    /// 每一筆變化記進測試紀錄；句子編號是 nil 時記在目前的句子底下。
    var onLog: ((_ text: String, _ sentence: Int?) -> Void)?

    /// 還在更新的最後一則回話：下一句話開始或觸控產生新的回話時才固定，放進 `messages`。畫面上位置相同。
    var liveReply: String? {
        isArchived || reply.isEmpty ? nil : reply
    }

    /// 還沒凍結的提示對話框目前那一頁：最後一則回話還在更新、而且是提示對話框。
    var liveHint: HintPage? {
        liveReply == nil ? nil : hintPage
    }

    /// 回話換成這段文字（還在更新）；不是提示頁的文字時就不是提示對話框了
    /// （一句話裡還有其他指令時，提示頁只是回話裡的文字）。
    func setReply(_ text: String) {
        if hintPage?.text != text {
            hintPage = nil
        }
        if text != reply {
            let lost = !isArchived && !reply.isEmpty ? "（舊的沒留下）" : ""
            onLog?("回話：「\(reply)」→「\(text)」\(lost)", nil)
        }
        reply = text
        isArchived = false
    }

    /// 回話是這一頁提示：還沒凍結就是原地換頁，否則是新的提示對話框。
    func showHint(_ page: HintPage) {
        hintPage = page
        setReply(page.text)
    }

    /// 回話固定在對話流：還沒凍結的提示對話框在這時凍結，停在當時那一頁。
    func archive(mood: Mood, showsWeatherCredit: Bool) {
        if let reply = liveReply {
            append(sentence: nil, reply, showsWeatherCredit: showsWeatherCredit, mood: mood, hint: liveHint?.name)
        }
        isArchived = true
    }

    /// 加入一則固定的話（使用者的話有句子編號）或小精靈的回話。
    func append(sentence: Int?, _ text: String, showsWeatherCredit: Bool = false, mood: Mood = .done, hint: String? = nil) {
        onLog?("加入 \(sentence == nil ? "小精靈" : "使用者")：\(text)", sentence)
        messages.append(Message(id: (messages.last?.id ?? 0) + 1, sentence: sentence, text: text, showsWeatherCredit: showsWeatherCredit, mood: mood, hint: hint))
    }

    /// 校正後的句子換掉對話流裡的原句（只換最後一則，而且是那一句的時候）。
    func replaceUserText(sentence: Int, with text: String) {
        guard let last = messages.indices.last, messages[last].sentence == sentence else {
            return
        }
        onLog?("取代 使用者：\(messages[last].text) → \(text)", sentence)
        messages[last].text = text
    }

    /// 重新開始：清空對話流（回話由上層先清掉）。
    func reset() {
        messages = []
    }

    /// 說明、上個提示、下個提示要顯示的那一頁：上個、下個從還沒凍結的提示算起，沒有就從最後一個凍結的提示算起，
    /// 都沒有是總導覽（上一頁、下一頁借用時相同）。頁名不在清單裡是 nil。
    func hintTarget(_ command: Command) -> HintPage? {
        let overview = HintPage.named(HintPage.overview)!
        switch command.action {
        case .help:
            return HintPage.named(command.page ?? HintPage.overview)
        default:
            let offset = [.previousHint, .previousPage].contains(command.action) ? -1 : 1
            let frozen = messages.last { $0.hint != nil }?.hint.flatMap(HintPage.named)
            return (liveHint ?? frozen)?.step(offset) ?? overview
        }
    }
}
