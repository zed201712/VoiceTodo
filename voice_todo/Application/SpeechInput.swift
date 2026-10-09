//
//  SpeechInput.swift
//  voicecalender
//

import Foundation

/// 語音輸入：把麥克風的聲音轉成辨識結果（見 docs/specs/voice-input.md）。
protocol SpeechInput {
    /// 開始聆聽；每次有辨識結果就呼叫 onResult（文字、是否為確定結果）。
    func start(onResult: @escaping (String, Bool) -> Void) async
    /// 把目前為止的音訊定稿。
    func finalize() async
    func stop()
}
