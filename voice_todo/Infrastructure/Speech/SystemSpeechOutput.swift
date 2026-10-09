//
//  SystemSpeechOutput.swift
//  voicecalender
//

import AVFoundation

/// 語音報告的 TTS：系統的 AVSpeechSynthesizer，zh-TW（見 docs/specs/spoken-report.md 的「TTS 與麥克風」）。
/// 在裝置上執行，不需要網路、沒有次數限制；有使用者在系統設定下載的增強語音就用品質最好的。
/// iOS 用 App 的 audio session（SpeechManager 設成同時播放與錄音）。
final class SystemSpeechOutput: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "zh-TW" }
        .max { $0.quality.rawValue < $1.quality.rawValue }
        ?? AVSpeechSynthesisVoice(language: "zh-TW")
    /// 念到一半的句子，念完或取消時讓 speak 返回。
    private var pending: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        await withCheckedContinuation { continuation in
            pending[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
    }

    /// 排隊中還沒開始的句子不一定會收到取消的回呼，所以全部在這裡結束。
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending.values.forEach { $0.resume() }
        pending = [:]
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    nonisolated private func finish(_ id: ObjectIdentifier) {
        Task { @MainActor in
            self.pending.removeValue(forKey: id)?.resume()
        }
    }
}
