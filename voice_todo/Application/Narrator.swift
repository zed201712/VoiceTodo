//
//  Narrator.swift
//  voice_todo
//

import Foundation
import Observation

/// 語音報告（見 CONTEXT.md、docs/specs/spoken-report.md）：念、中斷、念提示頁，與念的期間（給回音比對）。
/// 念什麼、什麼時候念由上層決定（句子由 `SpokenReport` 組成）。
@Observable
final class Narrator {

    /// 語音報告開關；初始狀態由 App 從存檔提供。
    private(set) var isOn: Bool
    /// 查詢念全部；中斷時重設（念提示被停掉除外）。
    var readAll = false
    private(set) var isSpeaking = false
    /// 正在念提示頁：念的時候不擋住後面的結果，換頁或下一個結果輪到就停（見 docs/specs/spoken-report.md 的「中斷」）。
    private(set) var isSpeakingHint = false

    /// nil 時不念（單元測試、Preview）。
    private let speaker: (any SpeechOutput)?
    /// 每次念或中斷就加一：被中斷的那次念完時，不能把新的念的狀態改掉。
    private var speechID = 0
    /// 每次念提示或停止就加一：還沒開始念就被停掉的那次不念。
    private var hintSpeechID = 0
    /// 最近一次念的文字與期間，給回音比對。
    private var spoken: (text: String, from: Int, to: Int?)?

    /// 遞增的時間點，和語音輸入共用，只用來比先後。
    var tick: () -> Int = { 0 }
    /// 「報告」「中斷」記進測試紀錄。
    var onLog: ((_ stage: String, _ text: String) -> Void)?

    init(speaker: (any SpeechOutput)?, isOn: Bool) {
        self.speaker = speaker
        self.isOn = isOn
    }

    /// 開關打開而且有 TTS。
    var canSpeak: Bool { isOn && speaker != nil }

    /// 切換開關；關閉時要不要中斷由上層先決定（見 docs/specs/spoken-report.md 的「語音報告開關」）。
    func setOn(_ on: Bool) {
        isOn = on
    }

    /// 念完回傳 true；被中斷回傳 false。關閉或沒有 TTS 時不念，回傳 true。
    @discardableResult
    func speak(_ text: String) async -> Bool {
        guard isOn, let speaker else {
            return true
        }
        onLog?("報告", text)
        speechID += 1
        let id = speechID
        isSpeaking = true
        spoken = (text, tick(), nil)
        await speaker.speak(text)
        guard speechID == id else {
            return false
        }
        isSpeaking = false
        spoken?.to = tick()
        return true
    }

    /// 正在念時停止，readAll 回到預設（`resetsReadAll` 為 false 時不變）；有中斷就回傳 true。
    @discardableResult
    func interrupt(_ reason: String, resetsReadAll: Bool = true) -> Bool {
        guard isSpeaking else {
            return false
        }
        speechID += 1
        isSpeaking = false
        isSpeakingHint = false
        spoken?.to = tick()
        if resetsReadAll {
            readAll = false
        }
        speaker?.stop()
        onLog?("中斷", reason)
        return true
    }

    /// 念提示頁，不等念完：後面的結果照常輪到（見 docs/specs/queue.md 的「報告顯示時間」）。正在念的提示先停。
    func speakHint(_ page: HintPage) {
        stopHint("換頁")
        guard canSpeak else {
            return
        }
        isSpeakingHint = true
        let id = hintSpeechID
        Task {
            guard id == hintSpeechID else {
                return
            }
            await speak(page.text)
            if id == hintSpeechID {
                isSpeakingHint = false
            }
        }
    }

    /// 換頁或下一個結果輪到時停止念提示；不重設 readAll。
    func stopHint(_ reason: String) {
        guard isSpeakingHint else {
            return
        }
        hintSpeechID += 1
        isSpeakingHint = false
        interrupt(reason, resetsReadAll: false)
    }

    /// 在 `spokenAt` 開口的這句話是不是自己的聲音漏進麥克風：開口時正在念、內容是念的文字的一部分。是的話回傳當時念的文字。
    func echo(of text: String, at spokenAt: Int) -> String? {
        guard let spoken, spoken.from <= spokenAt, spoken.to.map({ spokenAt <= $0 }) ?? true, Echo.isEcho(text, of: spoken.text) else {
            return nil
        }
        return spoken.text
    }
}
