//
//  AISettings.swift
//  voicecalender
//

import Foundation

/// 設定裡可以選的自動 AI（見 docs/specs/settings.md）。
enum AIChoice: String, Codable, CaseIterable {
    case foundationModels
    case gemini
    case ollama

    /// 目前開放 Apple Intelligence 與 Gemini（見 docs/specs/settings.md 的「目前狀態」）。
    var isOpen: Bool {
        self != .ollama
    }

    /// 開放的 AI 有兩個以上才需要選；只有一個時固定使用它。
    static var isChoosable: Bool {
        allCases.filter(\.isOpen).count > 1
    }
}

/// 自動 AI 的設定：一次只開一個，也可以全部關。Gemini API key 不在這裡，存在 Keychain。
struct AISettings: Codable, Equatable {

    private(set) var choice: AIChoice?
    var geminiModel = "gemini-3.1-flash-lite"
    var ollamaHost = "localhost"
    var ollamaPort = "11434"
    var ollamaModel = "gemma4:e2b"

    /// 第一次開啟：開 Gemini；Apple Intelligence 由使用者自己打開。
    static func initial() -> AISettings {
        AISettings(choice: .gemini)
    }

    func isEnabled(_ ai: AIChoice) -> Bool {
        choice == ai
    }

    /// 開一個，其他自動關。
    mutating func set(_ ai: AIChoice, enabled: Bool) {
        if enabled {
            choice = ai
        } else if choice == ai {
            choice = nil
        }
    }
}
