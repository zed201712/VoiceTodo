//
//  SettingsStorage.swift
//  voicecalender
//

import Foundation
import Security

/// 設定的存放：AI 的選擇、除錯模式與預設提示詞存在 UserDefaults，Gemini API key 存在 Keychain（見 docs/specs/settings.md）。
enum SettingsStorage {

    private static let settingsKey = "aiSettings"
    private static let keychainService = "z.voice-todo.gemini"
    private static let keychainAccount = "apiKey"

    /// 讀取設定；第一次開啟時是 nil。
    static func loadSettings() -> AISettings? {
        UserDefaults.standard.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(AISettings.self, from: $0) }
    }

    static func saveSettings(_ settings: AISettings) {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }

    // MARK: - 除錯模式（只在 macOS）

    private static let debugModeKey = "debugMode"

    static func loadDebugMode() -> Bool {
        UserDefaults.standard.bool(forKey: debugModeKey)
    }

    static func saveDebugMode(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: debugModeKey)
    }

    // MARK: - 預設提示詞（測試紀錄附上固定提示詞）

    private static let includesPromptsKey = "logIncludesPrompts"

    static func loadIncludesPrompts() -> Bool {
        UserDefaults.standard.bool(forKey: includesPromptsKey)
    }

    static func saveIncludesPrompts(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: includesPromptsKey)
    }

    // MARK: - 黑板的 checkbox 與一頁（見 docs/specs/todos.md 的「黑板」）

    private static let showDoneKey = "boardShowDone"

    /// 「完成」checkbox；第一次是不勾。
    static func loadBoardShowDone() -> Bool {
        UserDefaults.standard.bool(forKey: showDoneKey)
    }

    static func saveBoardShowDone(_ showDone: Bool) {
        UserDefaults.standard.set(showDone, forKey: showDoneKey)
    }

    private static let boardPageKey = "boardPage"

    /// 黑板最後顯示的一頁；沒存過或讀不出來是 nil。
    static func loadBoardPage() -> BoardPage.Saved? {
        UserDefaults.standard.data(forKey: boardPageKey).flatMap { try? JSONDecoder().decode(BoardPage.Saved.self, from: $0) }
    }

    static func saveBoardPage(_ saved: BoardPage.Saved) {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: boardPageKey)
    }

    // MARK: - 語音報告開關（見 docs/specs/spoken-report.md）

    private static let spokenReportKey = "spokenReport"

    /// 第一次是打開。
    static func loadSpokenReport() -> Bool {
        UserDefaults.standard.object(forKey: spokenReportKey) as? Bool ?? true
    }

    static func saveSpokenReport(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: spokenReportKey)
    }

    // MARK: - 聊天補充資訊的循環（見 docs/specs/chat.md 的「補充資訊」）

    private static let greetingIndexKey = "greetingIndex"

    /// 開場問候輪到的提示頁（見 docs/specs/help.md 的「開場問候」）。
    static func loadGreetingIndex() -> Int {
        UserDefaults.standard.integer(forKey: greetingIndexKey)
    }

    static func saveGreetingIndex(_ index: Int) {
        UserDefaults.standard.set(index, forKey: greetingIndexKey)
    }

    private static let chatRotationKey = "chatRotation"

    /// 第一次從頭開始。
    static func loadChatRotation() -> ChatRotation {
        UserDefaults.standard.data(forKey: chatRotationKey).flatMap { try? JSONDecoder().decode(ChatRotation.self, from: $0) } ?? ChatRotation()
    }

    static func saveChatRotation(_ rotation: ChatRotation) {
        UserDefaults.standard.set(try? JSONEncoder().encode(rotation), forKey: chatRotationKey)
    }

    // MARK: - 便條（見 docs/specs/help.md 的「便條」）

    private static let guideUsedKey = "guideUsed"
    private static let showsGuideKey = "showsGuide"

    /// 第一次是空的：新手階段。
    static func loadGuideUsed() -> Set<Guide.Step> {
        UserDefaults.standard.data(forKey: guideUsedKey).flatMap { try? JSONDecoder().decode(Set<Guide.Step>.self, from: $0) } ?? []
    }

    static func saveGuideUsed(_ used: Set<Guide.Step>) {
        UserDefaults.standard.set(try? JSONEncoder().encode(used), forKey: guideUsedKey)
    }

    /// 第一次是打開。
    static func loadShowsGuide() -> Bool {
        UserDefaults.standard.object(forKey: showsGuideKey) as? Bool ?? true
    }

    static func saveShowsGuide(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: showsGuideKey)
    }

    // MARK: - Gemini API key

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    static func loadGeminiKey() -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { $1 } as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// 空字串就刪除。
    static func saveGeminiKey(_ key: String) {
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else {
            return
        }
        let status = SecItemAdd(query.merging([kSecValueData as String: Data(key.utf8)]) { $1 } as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Settings] Keychain 寫入失敗：\(status)")
        }
    }
}
