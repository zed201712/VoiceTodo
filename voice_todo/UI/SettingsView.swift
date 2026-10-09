//
//  SettingsView.swift
//  voicecalender
//

import SwiftUI

/// 設定（見 docs/specs/settings.md）：選擇自動 AI、Gemini API key、Ollama 位址與模型、除錯模式（只在 macOS）、預設提示詞、分享測試紀錄。沒有儲存按鈕，離開時儲存。
struct SettingsView: View {

    /// 離開設定時呼叫：交出設定、Gemini API key（空字串表示清除）、除錯模式與預設提示詞。
    let onSave: (AISettings, String, Bool, Bool) -> Void
    /// 分享的測試紀錄（參數是是否附上固定提示詞）：和除錯 UI「複製」的內容相同。只在設定畫面顯示時才組出文字。
    let testLog: (Bool) -> String

    @State private var settings: AISettings
    @State private var geminiKey: String
    @State private var debugMode: Bool
    @State private var includesPrompts: Bool
    @State private var geminiResult = ""
    @State private var ollamaResult = ""
    @State private var isTesting = false

    private let appleUnavailable = FoundationModelsAI.unavailableReason

    init(settings: AISettings, geminiKey: String, debugMode: Bool, includesPrompts: Bool, testLog: @escaping (Bool) -> String, onSave: @escaping (AISettings, String, Bool, Bool) -> Void) {
        _settings = State(initialValue: settings)
        _geminiKey = State(initialValue: geminiKey)
        _debugMode = State(initialValue: debugMode)
        _includesPrompts = State(initialValue: includesPrompts)
        self.testLog = testLog
        self.onSave = onSave
    }

    var body: some View {
        Form {
            // 開放的 AI 只有一個時，不顯示開關與模型欄位（見 docs/specs/settings.md 的「目前狀態」）。
            if AIChoice.foundationModels.isOpen {
                Section("Apple Intelligence") {
                    Toggle("使用 Apple Intelligence", isOn: enabled(.foundationModels))
                        .disabled(appleUnavailable != nil)
                    if let appleUnavailable {
                        Text(appleUnavailable).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Gemini") {
                if AIChoice.isChoosable {
                    Toggle("使用 Gemini", isOn: enabled(.gemini))
                }
                HStack {
                    SecureField("API key", text: $geminiKey)
                        .plainInput()
                    Button {
                        geminiKey = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(geminiKey.isEmpty)
                    .help("清除 API key")
                }
                Text(geminiKey.isEmpty ? "未設定" : "已設定（…\(geminiKey.suffix(4))）")
                    .foregroundStyle(.secondary)
                if AIChoice.isChoosable {
                    TextField("模型", text: $settings.geminiModel)
                        .plainInput()
                }
                connectionTest(geminiResult) {
                    geminiResult = await GeminiAI(model: settings.geminiModel, apiKey: { geminiKey }).testConnection()
                }
            }

            if AIChoice.ollama.isOpen {
                Section("Ollama") {
                    if AIChoice.isChoosable {
                        Toggle("使用 Ollama", isOn: enabled(.ollama))
                    }
                    TextField("IP", text: $settings.ollamaHost)
                        .plainInput()
                    TextField("Port", text: $settings.ollamaPort)
                        .plainInput()
                    TextField("模型", text: $settings.ollamaModel)
                        .plainInput()
                    connectionTest(ollamaResult) {
                        ollamaResult = await OllamaAI(model: settings.ollamaModel, host: settings.ollamaHost, port: settings.ollamaPort).testConnection()
                    }
                }
            }

            Section("開發") {
                #if os(macOS)
                Toggle("除錯模式", isOn: $debugMode)
                #endif
                Toggle("預設提示詞", isOn: $includesPrompts)
                // 沒有除錯 UI 的 iPhone 也能把測試紀錄交出去（見 docs/specs/settings.md 的「分享測試紀錄」）。
                ShareLink("分享測試紀錄", item: testLog(includesPrompts))
            }

            // Open-Meteo（CC BY 4.0）與地名資料（政府資料開放授權條款）要標註來源（見 docs/specs/settings.md 的「天氣資料的標示」）。
            Section {
                Text(LocalizedStringKey(OpenMeteoWeather.credit))
                Text(LocalizedStringKey(TownBoundaries.credit))
            }
        }
        .onDisappear {
            onSave(settings, geminiKey, debugMode, includesPrompts)
        }
    }

    /// 一次只開一個：開一個，其他自動關。
    private func enabled(_ ai: AIChoice) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(ai) }, set: { settings.set(ai, enabled: $0) })
    }

    private func connectionTest(_ result: String, test: @escaping () async -> Void) -> some View {
        HStack {
            Button {
                isTesting = true
                Task {
                    await test()
                    isTesting = false
                }
            } label: {
                Image(systemName: "powerplug")
            }
            .disabled(isTesting)
            .help("測試連線")
            Text(result).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    /// key、位址、模型名稱要原樣輸入：不自動修正、不自動大寫。
    func plainInput() -> some View {
        #if os(iOS)
        autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
        autocorrectionDisabled()
        #endif
    }
}
