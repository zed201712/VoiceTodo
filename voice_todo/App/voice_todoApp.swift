//
//  voice_todoApp.swift
//  voicecalender
//
//  Created by A on 2026/9/28.
//

import SwiftUI

@main
struct voice_todoApp: App {
    @State private var elf = Elf(
        autoAI: isTesting ? nil : makeAutoAI(loadSettings()),
        speech: isTesting ? nil : SpeechManager(locale: Locale(identifier: "zh-TW")),
        todoList: TodoList(
            storage: isTesting ? nil : EventKitTodoStorage(),
            boardPage: isTesting ? nil : SettingsStorage.loadBoardPage(),
            showDone: SettingsStorage.loadBoardShowDone()),
        weather: isTesting ? nil : WeatherLookup(service: OpenMeteoWeather(), locator: SystemLocator(), towns: TownBoundaries.load()),
        speaker: isTesting ? nil : SystemSpeechOutput(),
        clipboard: isTesting ? nil : SystemClipboard(),
        reportOn: SettingsStorage.loadSpokenReport(),
        chatRotation: SettingsStorage.loadChatRotation(),
        greetingIndex: SettingsStorage.loadGreetingIndex(),
        guideUsed: SettingsStorage.loadGuideUsed(),
        showsGuide: SettingsStorage.loadShowsGuide(),
        includesPrompts: SettingsStorage.loadIncludesPrompts(),
        wait: displayWait
    )
    @State private var showsSettings = false
    @State private var debugMode = SettingsStorage.loadDebugMode()

    /// 單元測試以 App 為 host，不要打開麥克風。
    private static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 自動 AI 由設定決定（見 docs/specs/settings.md）；第一次開啟時用預設。
    /// 報告顯示時間的等待（見 docs/specs/queue.md）；單元測試時不等。
    private static var displayWait: ((Duration) async -> Void)? {
        guard !isTesting else {
            return nil
        }
        return { duration in
            try? await Task.sleep(for: duration)
        }
    }

    private static func loadSettings() -> AISettings {
        SettingsStorage.loadSettings() ?? AISettings.initial()
    }

    private static func makeAutoAI(_ settings: AISettings) -> (any AutoAI)? {
        AIFactory.autoAI(
            for: settings,
            foundationModelsUnavailable: FoundationModelsAI.unavailableReason,
            geminiKey: SettingsStorage.loadGeminiKey
        )
    }

    private func settingsView() -> some View {
        SettingsView(settings: Self.loadSettings(), geminiKey: SettingsStorage.loadGeminiKey() ?? "", debugMode: debugMode, includesPrompts: elf.includesPrompts, testLog: { elf.testLogText(includesPrompts: $0) }) { settings, key, debug, prompts in
            SettingsStorage.saveSettings(settings)
            SettingsStorage.saveGeminiKey(key)
            SettingsStorage.saveDebugMode(debug)
            SettingsStorage.saveIncludesPrompts(prompts)
            debugMode = debug
            elf.includesPrompts = prompts
            elf.setAutoAI(Self.makeAutoAI(settings))
        }
    }

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            // 除錯模式時，除錯 UI 接在使用者畫面右邊（見 docs/specs/ui.md）。
            MacRoot(elf: elf, debugMode: debugMode)
                .opensSettings(when: !elf.hasAutoAI)
                .savesBoardDisplay(of: elf)
                .savesSpokenReport(of: elf)
                .savesChatRotation(of: elf)
                .savesGreeting(of: elf)
                .savesGuide(of: elf)
                .reloadsOnForeground(elf)
#else
            HomeView(elf: elf) {
                showsSettings = true
            }
            .savesBoardDisplay(of: elf)
            .savesSpokenReport(of: elf)
            .savesChatRotation(of: elf)
            .savesGreeting(of: elf)
            .savesGuide(of: elf)
            .reloadsOnForeground(elf)
            .sheet(isPresented: $showsSettings) {
                settingsView()
            }
            .task {
                await elf.start()
                showsSettings = !elf.hasAutoAI
            }
#endif
        }
        .defaultSize(width: 390, height: 763)
#if os(macOS)
        Settings {
            settingsView()
        }
#endif
    }
}

private extension View {
    /// 黑板的 checkbox 與一頁一改就存檔；導覽紀錄不存檔（見 docs/specs/todos.md 的「黑板」）。
    func savesBoardDisplay(of elf: Elf) -> some View {
        onChange(of: elf.showDone) { _, showDone in
            SettingsStorage.saveBoardShowDone(showDone)
        }
        .onChange(of: elf.boardPage) { _, page in
            SettingsStorage.saveBoardPage(BoardPage.Saved(day: TodoStore.dayString(.now), page: page))
        }
    }

    func savesSpokenReport(of elf: Elf) -> some View {
        onChange(of: elf.isReportOn) { _, on in
            SettingsStorage.saveSpokenReport(on)
        }
    }

    func savesChatRotation(of elf: Elf) -> some View {
        onChange(of: elf.chatRotation) { _, rotation in
            SettingsStorage.saveChatRotation(rotation)
        }
    }

    func savesGreeting(of elf: Elf) -> some View {
        onChange(of: elf.greetingIndex) { _, index in
            SettingsStorage.saveGreetingIndex(index)
        }
    }

    func savesGuide(of elf: Elf) -> some View {
        onChange(of: elf.guideUsed) { _, used in
            SettingsStorage.saveGuideUsed(used)
        }
        .onChange(of: elf.showsGuide) { _, on in
            SettingsStorage.saveShowsGuide(on)
        }
    }

    /// 回到前景時重新讀取存檔：在提醒事項 App 改的、在系統設定打開的權限，回來就看得到（見 docs/specs/storage.md）。
    func reloadsOnForeground(_ elf: Elf) -> some View {
        modifier(ReloadsOnForeground(elf: elf))
    }
}

private struct ReloadsOnForeground: ViewModifier {
    let elf: Elf
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase == .active {
                elf.storageChanged()
            }
        }
    }
}

#if os(macOS)
private struct MacRoot: View {
    let elf: Elf
    let debugMode: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            HomeView(elf: elf) {
                openSettings()
            }
            .frame(width: 390)
            if debugMode {
                Divider()
                ContentView(elf: elf)
            }
        }
        .frame(minHeight: 700)
        .task {
            await elf.start()
        }
        .onDisappear {
            elf.stop()
        }
    }
}

private extension View {
    /// 開啟時沒有可以使用的 AI，直接打開設定視窗。
    func opensSettings(when condition: Bool) -> some View {
        modifier(OpensSettings(condition: condition))
    }
}

private struct OpensSettings: ViewModifier {
    let condition: Bool
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.task {
            if condition {
                openSettings()
            }
        }
    }
}
#endif
