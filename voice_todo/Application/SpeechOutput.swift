//
//  SpeechOutput.swift
//  voicecalender
//

import Foundation

/// 語音報告的 TTS（見 docs/specs/spoken-report.md）。
protocol SpeechOutput {
    /// 念出文字；念完或被 stop() 停止才返回。連續呼叫時依序念。
    func speak(_ text: String) async
    /// 立刻停止，丟掉還沒念的。
    func stop()
}
