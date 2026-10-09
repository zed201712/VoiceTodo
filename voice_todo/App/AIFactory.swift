//
//  AIFactory.swift
//  voicecalender
//

import Foundation

/// 依設定產生自動 AI（見 docs/specs/settings.md）。沒有可以使用的 AI 時是 nil：
/// 沒選、選的不開放、Apple Intelligence 不能用、Gemini 沒有 API key。
enum AIFactory {

    static func autoAI(
        for settings: AISettings,
        foundationModelsUnavailable: String?,
        geminiKey: @escaping () -> String?
    ) -> (any AutoAI)? {
        let open = AIChoice.allCases.filter(\.isOpen)
        let choice = open.count == 1 ? open.first : settings.choice.flatMap { $0.isOpen ? $0 : nil }
        return switch choice {
        case .foundationModels:
            foundationModelsUnavailable == nil ? FoundationModelsAI() : nil
        case .gemini:
            geminiKey()?.isEmpty == false ? GeminiAI(model: settings.geminiModel, apiKey: geminiKey) : nil
        case .ollama:
            OllamaAI(model: settings.ollamaModel, host: settings.ollamaHost, port: settings.ollamaPort)
        case nil:
            nil
        }
    }
}
