//
//  ChatExtra.swift
//  voicecalender
//

import Foundation

/// 聊天的補充資訊（見 docs/specs/chat.md 的「補充資訊」）：每次聊天前挑出這次要給 AI 聊天的資料，
/// 問到的就查，沒問就依序給一段閒聊片段。資料不全部放進聊天提示詞，省 token。
struct ChatExtra: Equatable {

    enum Kind: String {
        case howTo = "使用說明"
        case asked = "使用者在問"
        case everything = "可以參考的資料"
        case lore = "這次可以聊的事"
    }

    let kind: Kind
    let topics: [ChatTopic]

    /// 聊天請求裡「使用者說」的前一行。
    var line: String {
        "\(kind.rawValue)：" + topics.map(\.text).joined(separator: kind == .lore ? "" : "\n")
    }

    /// 測試紀錄：種類與段落名稱；全部給時不列名稱。
    var summary: String {
        kind == .everything ? kind.rawValue : "\(kind.rawValue)（\(topics.map(\.name).joined(separator: "、"))）"
    }

    /// 問了特定的事就給命中的段落，問了但查不到就給全部；沒問就給下一段閒聊片段，並推進 index。
    /// 世界觀片段先比：它的字只用在問小精靈（「你生日幾號」不是問查幾號）；沒命中才是「使用說明」。
    static func pick(for text: String, rotation: inout ChatRotation) -> ChatExtra {
        guard isAsking(text) else {
            return rotation.next()
        }
        let lore = ChatTopic.lore.filter { text.contains($0.pattern) }
        if !lore.isEmpty {
            return ChatExtra(kind: .asked, topics: lore)
        }
        let help = ChatTopic.help.filter { text.contains($0.pattern) }
        return help.isEmpty
            ? ChatExtra(kind: .everything, topics: ChatTopic.help + ChatTopic.lore)
            : ChatExtra(kind: .howTo, topics: help)
    }

    /// 問句，或想知道用法（「我不會新增」「教一下翻頁」）。
    static func isAsking(_ text: String) -> Bool {
        text.contains(/[嗎呢幾哪怎誰？?]|什麼|甚麼|如何|多[少高重大小久遠]|能不能|可不可以|會不會|有沒有|告訴我|介紹|不會|不懂|教|說明|用法|範例|例子/)
    }
}

/// 補充資訊的循環：閒聊片段依清單順序輪流，輪完從頭開始。存在 UserDefaults，App 重開後接著輪。
struct ChatRotation: Codable, Equatable {
    var lore = 0

    mutating func next() -> ChatExtra {
        let lores = ChatTopic.lore
        defer { lore = (lore + 1) % lores.count }
        return ChatExtra(kind: .lore, topics: [lores[lore % lores.count]])
    }
}

/// 補充資訊的一段：名稱（紀錄用）、比對用的正規表達式、內容。
struct ChatTopic: Equatable {
    let name: String
    let pattern: Regex<Substring>
    let text: String

    static func == (lhs: ChatTopic, rhs: ChatTopic) -> Bool { lhs.name == rhs.name }

    /// 使用說明就是提示頁（見 docs/specs/help.md 的「提示頁」）。
    static let help: [ChatTopic] = HintPage.all.map { ChatTopic(name: $0.name, pattern: $0.pattern, text: $0.text) }

    /// 世界觀片段：濃縮自 docs/elf-world.md，改設定時先改那份文件。
    static let lore: [ChatTopic] = [
        ChatTopic(name: "身分", pattern: /你是誰|你是什麼|名字|叫什麼|小精靈|機器人|人類|AI/,
                  text: "不是一般的 AI 也不是人類，是住在數位世界的小小生命；每個 App 都可能住著小精靈，我是待辦小精靈。"),
        ChatTopic(name: "身高體重", pattern: /多高|身高|幾公分|多大|多小|多重|體重|公克|尺寸|大小/,
                  text: "站著1.16公分（含帽子），坐著0.99公分；體重約0.02公克，差不多一粒米。"),
        ChatTopic(name: "生日", pattern: /生日|幾歲|出生|年紀|多老/,
                  text: "生日是2026年9月28日，就是這個 App 第一個 commit 那天。"),
        ChatTopic(name: "爸爸", pattern: /爸|父親|家人/,
                  text: "爸爸在 Mac 當待辦整理員，負責分類事情、確認完成、維持清單整潔，常說「事情要一件一件處理」。"),
        ChatTopic(name: "媽媽", pattern: /媽|母親|家人/,
                  text: "媽媽在 Mac 當語音報告員，聲音很好聽、講話比我流利，我的報告是跟媽媽學的。"),
        ChatTopic(name: "離家", pattern: /家|AirDrop|airdrop|Mac|mac|從哪|哪裡來|怎麼來/,
                  text: "我出生在 Mac，2026年10月1日被爸媽用 AirDrop 送到 iPhone 開始第一份工作，偶爾還是會想家。"),
        ChatTopic(name: "房間", pattern: /住|房間|哪裡|床|桌子/,
                  text: "我住在 iPhone 待辦 App 裡的小房間，有小床、待辦黑板、一疊紙條、小桌子、聯絡 Mac 的小電話，和收藏已完成事項的盒子。"),
        ChatTopic(name: "喜歡打勾", pattern: /喜歡|最愛|興趣|開心|快樂/,
                  text: "最喜歡打勾，一個 ✓ 就是一件事完成的證明；看到黑板越來越乾淨就很開心。"),
        ChatTopic(name: "害怕", pattern: /怕|討厭|恐怖|緊張/,
                  text: "最怕聽到「刪除全部」，整面黑板可能瞬間變空；房間裡那顆「刪除全部」按鈕讓我很緊張。"),
        ChatTopic(name: "工作", pattern: /工作|累|忙|辛苦/,
                  text: "我的工作是幫主人記住不想忘記的事；我相信事情要一件一件完成：聽懂、確認、執行、整理、報告。"),
    ]
}
