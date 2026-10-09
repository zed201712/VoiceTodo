//
//  SentenceBuilder.swift
//  voicecalender
//

import Foundation

/// 把確定結果累積成一句話（見 docs/specs/voice-input.md）。
///
/// 確定結果比暫定結果晚 1～7 秒，時機由辨識器決定，一句話也可能被切成好幾段，所以不能拿它判斷說完了沒。
/// 新的話一定先以暫定結果出現，所以只有暫定結果代表「還在說」。
/// 停頓時若還有暫定結果，呼叫端要叫辨識器定稿；定稿的確定結果到達後才送出。
/// 每個辨識結果附上時間點（遞增的整數）；一句話交出時帶著開口的時間點：這句話第一個辨識結果的時間點。
struct SentenceBuilder {

    static let pause: Duration = .seconds(1.5)

    /// 定稿的一句話與開口的時間點。
    struct Finished: Equatable {
        let text: String
        let spokenAt: Int
    }

    private(set) var finalText = ""
    private(set) var volatileText = ""
    /// 這句話第一個辨識結果的時間點。
    private var spokenAt: Int?

    /// 已經停頓，等定稿的確定結果到達就送出。
    private var paused = false

    mutating func receiveVolatile(_ text: String, at moment: Int) {
        mark(text, at: moment)
        volatileText = text
        paused = false
    }

    /// 回傳完成的一句話；還沒停頓時回傳 nil。
    mutating func receiveFinal(_ text: String, at moment: Int) -> Finished? {
        mark(text, at: moment)
        finalText += text
        volatileText = ""
        return paused ? take() : nil
    }

    /// 停頓時呼叫。沒有暫定結果就直接送出；否則回傳 nil，由呼叫端定稿。
    mutating func pause() -> Finished? {
        paused = true
        return volatileText.isEmpty ? take() : nil
    }

    private mutating func mark(_ text: String, at moment: Int) {
        if spokenAt == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            spokenAt = moment
        }
    }

    private mutating func take() -> Finished? {
        paused = false
        let sentence = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let moment = spokenAt
        finalText = ""
        spokenAt = nil
        guard !sentence.isEmpty, let moment else {
            return nil
        }
        return Finished(text: sentence, spokenAt: moment)
    }
}
