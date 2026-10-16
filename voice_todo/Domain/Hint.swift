//
//  Hint.swift
//  voicecalender
//

import Foundation

/// 提示頁（見 docs/specs/help.md 的「提示頁」）：固定的使用說明，以可以照著說的句子為主。
/// 頁的順序就是箭頭的順序，頭尾相接。聊天的使用說明也用這份資料（見 docs/specs/chat.md 的「補充資訊」）。
struct HintPage: Equatable {

    let name: String
    /// 每行一句；`[頁名]` 是嵌在文字裡的連結，點了換到那一頁。
    let lines: [String]
    /// 比對用的正規表達式：聊天的補充資訊與便條的「剛聽不懂」用。
    let pattern: Regex<Substring>

    init(_ name: String, _ lines: [String], pattern: Regex<Substring>) {
        self.name = name
        self.lines = lines
        self.pattern = pattern
    }

    static func == (lhs: HintPage, rhs: HintPage) -> Bool { lhs.name == rhs.name }

    /// 連結的標記。
    static let link = /\[([^\]]+)\]/

    /// 這一頁的連結，依出現的順序。
    var links: [String] {
        lines.flatMap { $0.matches(of: Self.link).map { String($0.1) } }
    }

    /// 念、畫面資訊、聊天用的純文字：連結只留頁名。
    var text: String {
        lines.joined(separator: "\n").replacing(Self.link) { String($0.1) }
    }

    static let overview = "總導覽"

    static func named(_ name: String) -> HintPage? {
        all.first { $0.name == name }
    }

    /// 頭尾相接的上一頁、下一頁（見 docs/specs/help.md 的「提示對話框」）。
    func step(_ offset: Int) -> HintPage {
        let index = Self.all.firstIndex(of: self) ?? 0
        let count = Self.all.count
        return Self.all[((index + offset) % count + count) % count]
    }

    // 「」裡的說法要被規則判斷或關鍵字認出來，或列在 docs/eval/judge-cases.md 的「提示頁的範例句」，由單元測試保證。
    // 頁名不和固定的說法相同：還沒凍結時說頁名就是換頁，原本的意思優先。
    // 提示對話框的高度以最長的一頁為準，每頁要放得進對話流：最多約 6 行字，放不下就拆頁。
    // 畫面的顏色與分組和 docs/specs/ui.md 的「黑板」一致，改畫面時一起改。
    static let all: [HintPage] = [
        HintPage(overview, ["[新增]：說「新增明天買牛奶」", "[修改]：說「第1項改到明天」", "[刪除]：說「刪除第1項」", "[顯示]：說「顯示明天」", "說「關閉音效」，我就不再念出聲音。", "說「下個提示」看其他用法。"],
                 pattern: /怎麼用|怎麼使用|如何使用|做什麼|做哪些|什麼功能|哪些功能|說什麼|說哪些|說明|教學|使用方法|用法|範例|例子|攻略|幫助|提示|help/),
        HintPage("新增", ["說「新增今天下午3點買牛奶」。", "說「新增10月10日上午9點看牙醫」。", "沒說日期，就加在黑板上那天；日期怎麼說見[日期說法]。"],
                 pattern: /新增|增加|加入|加一|記下|記住|提醒我/),
        HintPage("修改", ["說「第1項改到明天」。", "說「第1到3項延到下週一」。", "也可以說內容：「買牛奶改到後天」。", "說「第1項複製到明天」，原本的會留著。", "什麼是[編號]？"],
                 pattern: /修改|改成|改到|改時間|改日期|更改|換時間|延後|提前|複製/),
        HintPage("刪除", ["說「刪除第1項」「刪除第1到3項」。", "說「刪除全部」刪黑板上的全部，說「刪除完成」刪已完成的。", "刪之前我會先問，說「好」才刪。", "什麼是[編號]？"],
                 pattern: /刪|移除|清掉|不要了/),
        HintPage("顯示", ["黑板顯示目前的範圍，修改、刪除只找黑板上的待辦。", "說「顯示明天」「顯示下週」換範圍。", "說「顯示全部」看所有日期。", "也可以[翻頁]、看[已完成]的。"],
                 pattern: /顯示|查詢|查待辦|查行程|看某天|那天|哪天|有什麼事|行程|接下來|黑板|全部|所有/),
        HintPage("設定完成", ["說「完成第1項」，或點待辦前面的方框。", "也可以說內容：「買牛奶完成」。"],
                 pattern: /完成|打勾|做完|勾/),
        HintPage("編號", ["黑板每行最前面的數字是編號。", "說「第3項移到明天」「完成第2項」「刪除第5到10項」。"],
                 pattern: /編號|號碼|第幾|幾項|一次|多筆|批次|好幾筆|範圍/),
        HintPage("翻頁", ["說「上一頁」「下一頁」，回到看過的黑板。", "黑板沒有上一頁、下一頁時，換成翻提示。", "說「上個提示」「下個提示」也能翻提示。"],
                 pattern: /頁|上一個|回去|返回/),
        HintPage("查日期", ["說「週五幾號」「明天星期幾」。", "只說「幾號」，查黑板那天。"],
                 pattern: /幾號|星期幾|禮拜幾|日期/),
        HintPage("天氣", ["說「明天會下雨嗎」「今天會下雨嗎」。", "也可以說「下週五台北天氣如何」。"],
                 pattern: /天氣|下雨|溫度|幾度|帶傘|氣象/),
        HintPage("已完成", ["說「顯示完成」「隱藏完成」，或點右上角的勾勾。", "黑板範圍裡過去的待辦都會顯示。"],
                 pattern: /過去|以前|過期|完成的|已完成|隱藏/),
        HintPage("復原與重做", ["說「復原」回到上一步，說「重做」再回來。", "也可以按下面的箭頭。", "說「全部取消」，還沒處理的話都不做。"],
                 pattern: /復原|重做|後悔|改錯|弄錯|恢復|還原|undo|redo|取消|排隊|說錯|太多/),
        HintPage("聲音與麥克風", ["說「停止」停下這次的報告。", "說「關閉音效」不再念，說「打開音效」再打開；右上角的喇叭也可以切換。", "查詢只念前3項，說「全部念完」就都念。", "說「關閉語音」停止聆聽；要再打開，按下面的麥克風按鈕。"],
                 pattern: /聲音|音效|安靜|吵|靜音|不要念|不要唸|報告|喇叭|念完|唸完|只念|只唸|麥克風|聆聽|不要聽|收音/),
        HintPage("日期說法", ["日期說「10月12」「明天」「下週五」「下個月」。", "時間說「下午3點」「晚上」，也可以不說。"],
                 pattern: /說法|怎麼說|時間/),
        HintPage("畫面", ["黃色加粗的是今天。", "標題後面藍色的字是查詢條件，灰色加刪除線的是已完成。"],
                 pattern: /顏色|色|橘|黃|藍|灰|粗體|刪除線|變淡|比較淡|分組|標題|其餘/),
        HintPage("設定", ["按右上角的齒輪，可以選要用的 AI、填 Gemini 的 API key。"],
                 pattern: /設定|API|key|金鑰|Gemini|Ollama|換AI|哪個AI|模型|齒輪/),
        HintPage("判斷失敗", ["說「重試」再試一次，說「略過」跳過。", "聽不懂時，換個說法再說一次。"],
                 pattern: /失敗|錯誤|重試|略過|聽不懂|沒反應/),
    ]
}

/// 開場問候（見 docs/specs/help.md 的「開場問候」）：依提示頁的順序輪一頁的文字，輪完從頭開始；
/// 新手階段改成教使用者問提示。
enum Greeting {
    static let novice = "如果不會用的話，你可以問「提示」、「怎麼使用」，我會告訴你更多技巧唷！"
    static let pages = HintPage.all

    /// 輪到 `index` 的那一頁，與下一次的 index。
    static func page(_ index: Int) -> (page: HintPage, next: Int) {
        (pages[index % pages.count], (index + 1) % pages.count)
    }
}

/// 便條的引導（見 docs/specs/help.md 的「便條」）：告訴使用者下一句可以說什麼。
enum Guide {

    /// 便條引導學的操作，依引導的順序；頁名就是提示頁。
    enum Step: String, CaseIterable, Codable {
        case add = "新增"
        case show = "顯示"
        case modify = "修改"
        case setDone = "設定完成"
        case delete = "刪除"

        /// 執行成功的指令算用過哪一類；顯示是查詢待辦或顯示全部。
        init?(_ action: Command.Action) {
            switch action {
            case .addTodo: self = .add
            case .queryTodos, .showEverything: self = .show
            case .modifyTodo: self = .modify
            case .setDone: self = .setDone
            case .deleteTodos: self = .delete
            default: return nil
            }
        }
    }

    /// 便條的一行，與點便條時要打開的提示頁。
    struct Line: Equatable {
        let text: String
        let page: String
    }

    /// `unclear` 是最近一個沒有指令的句子（之後還沒有指令執行成功）；`used` 是用過的操作。
    static func line(unclear: String?, used: Set<Step>, boardHasTodos: Bool) -> Line {
        if let unclear {
            let page = HintPage.all.first { $0.name != HintPage.overview && unclear.contains($0.pattern) }
            return page.map(ask) ?? Line(text: "可以說「提示」看怎麼用", page: HintPage.overview)
        }
        let usable = Step.allCases.filter { boardHasTodos || $0 == .add || $0 == .show }
        if let next = usable.first(where: { !used.contains($0) }) {
            return ask(HintPage.named(next.rawValue)!)
        }
        return Line(text: "可以說「提示」看更多用法", page: HintPage.overview)
    }

    private static func ask(_ page: HintPage) -> Line {
        Line(text: "可以說「如何\(page.name)」", page: page.name)
    }
}
