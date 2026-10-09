//
//  FoundationModelsAI.swift
//  voicecalender
//

import Foundation
import FoundationModels

/// 自動 AI 的 Foundation Models 實作：結構化輸出（@Generable）轉成 JSON 字串（見 docs/specs/judgment.md 的「自動 AI」）。
/// 每次請求一個新的 session，不保留紀錄。只做判斷與刪除確認：不聊天（太慢）；不校正（改錯的比改對的多，見 docs/specs/correction.md）。
struct FoundationModelsAI: AutoAI {

    let name = "Foundation Models"

    var status: String {
        let model = SystemLanguageModel.default
        let zhTW = model.supportsLocale(Locale(identifier: "zh-TW"))
        return "模型：\(model.availability == .available ? "可用" : "\(model.availability)")　" +
            "zh-TW：\(zhTW ? "支援" : "不支援")　上下文：\(model.contextSize) tokens"
    }

    let judgePrompt = FixedPrompt(instructions: Self.judgeInstructions, schema: Self.schemaText(CommandPlan.generationSchema))
    let confirmPrompt = FixedPrompt(instructions: JudgePrompt.confirmInstructions, schema: Self.schemaText(Confirmation.generationSchema))

    /// 下一次判斷用的 session，先 prewarm 載入模型。
    private final class Warm {
        var session: LanguageModelSession?
    }

    private let warm = Warm()

    init() {
        prepare()
    }

    private func prepare() {
        guard warm.session == nil else {
            return
        }
        let session = LanguageModelSession(instructions: Self.judgeInstructions)
        session.prewarm()
        warm.session = session
    }

    /// 測試紀錄用的 schema 文字。
    private static func schemaText(_ schema: GenerationSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try? encoder.encode(schema)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(schema)"
    }

    /// 這台裝置不能用 Apple Intelligence 的原因；能用就是 nil（見 docs/specs/settings.md）。
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "這台裝置不支援 Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence 沒有開啟"
        case .unavailable(.modelNotReady): "模型還沒準備好"
        case .unavailable: "Apple Intelligence 無法使用"
        }
    }

    // MARK: - 判斷

    // 2026-10-08 在 M1 8 GB 量測：這台裝置每秒只讀得了幾十個提示詞的 token，共用的判斷提示詞（1,842 token）一次要 40～50 秒；
    // 輸出結構展開後約 2,600 token，放進提示詞會超過 4,096 的上下文。所以判斷用 FM 專用的精簡提示詞，加上句型參考說明欄位的用法；輸出結構不放進提示詞（放進去每句多 2,500 token、比較慢，而且實測反而更常選錯指令），結構仍然限制輸出；
    // regex 的 @Guide 只要有中文字就失敗（GenerativeError 1020000）；新的 session 要等載入模型，先 prewarm 好下一個（短提示詞從 10～19 秒降到 2～5 秒）。

    // 不放「可能有同音錯字」：2026-10-09 實測加了反而從 20/33 掉到 18/33，錯字句（「10月6號麵是」）也沒有改對。
    private static let intro = "你把使用者對待辦清單 App 說的話翻成指令清單。"

    private static let commandList = """
        指令：
        - 新增待辦：記下要做的事
        - 查詢待辦：問有哪些待辦
        - 查詢日期：問日期或星期
        - 設定完成：已經有的待辦做完了，或改回沒做完
        - 修改待辦：改已經有的待辦的日期或內容
        - 刪除待辦：刪掉已經有的待辦
        - 復原：不要剛才的改變；重做：做回剛才復原的
        - 上一頁、下一頁、顯示全部：切換畫面
        - 設定顯示：顯示或隱藏已完成的待辦
        - 全部念完：之後的結果全部念出來
        - 說明：問 App 怎麼用；上個提示、下個提示：翻提示
        - 查天氣：問天氣、會不會下雨
        - 聽不懂：App 做不到、跟待辦無關、只是雜音
        """

    private static let fieldRules = """
        欄位：
        - 使用者沒說的欄位一律省略，不要猜。
        - 新增待辦時，先把日期與時間寫進 date，其餘寫進 content；content 不含日期、時間與句號。
        - keyword：要找的待辦內容裡的詞，不含日期；泛稱不是關鍵字，要省略。
        - number：畫面上的編號，「第2項」寫「2」，「3到10項」寫「3~10」。
        - date、newDate：照使用者說的詞寫，不換算成數字日期。例如：今天、明天、週五、下週、下週週五、下個月、10月6日、下個月15日、下午3點30分、明天晚上。「號」寫成「日」，「禮拜」「星期」寫成「週」，數字用阿拉伯數字；時間寫成「9點」「9點30分」，不寫「9:00」。
        """

    /// 句型參考：開發者決定給 FM 句型（2026-10-08）；小模型只看說明常選錯指令。用 < > 的句型而不是具體的例句：
    /// 具體的例句會被照抄（「嗯」被判成例句的三條指令、編號照抄例句的 4）。
    private static let examples = """
        句型（< > 是照使用者說的話填的部分）：
        - 新增<日期><事情>、<日期>要<事情> → 新增待辦，date <日期>，content <事情>
        - 第<N>項改到<日期> → 修改待辦，number <N>，newDate <日期>
        - <事情>改到<日期> → 修改待辦，keyword <事情>，newDate <日期>
        - <事情>完成、<事情>做完了 → 設定完成，keyword <事情>，isDone true
        - 第<N>項做完了 → 設定完成，number <N>，isDone true
        - 刪除第<N>項 → 刪除待辦，number <N>
        - 第<N>和第<M>項<動作> → 兩條指令，number 分別是 <N>、<M>
        - 刪除<日期>的<事情> → 刪除待辦，date <日期>，keyword <事情>
        - <日期>有什麼事 → 查詢待辦，date <日期>
        - 有什麼<事情> → 查詢待辦，keyword <事情>
        - <日期>幾號 → 查詢日期，date <日期>
        - <日期>會下雨嗎 → 查天氣，date <日期>
        - 怎麼<做某件事> → 說明
        - 和待辦、日期、天氣無關的話，或只有語氣詞 → 聽不懂
        """

    static let judgeInstructions = [intro, commandList, fieldRules, examples].joined(separator: "\n\n")

    func judge(_ request: String) async throws -> String {
        let session = warm.session ?? LanguageModelSession(instructions: Self.judgeInstructions)
        warm.session = nil
        defer { prepare() }
        let start = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - start
            Task { await Self.printTranscript("Judge", session, elapsed) }
        }
        do {
            // 釐清後判斷（有「小精靈剛才問」）是在回答問題，不經過關卡：「10月9號那個」單看不像要 App 做事。
            async let isCommand = request.contains("小精靈剛才問") ? true : Self.isCommand(request)
            let response = try await session.respond(to: request, generating: CommandPlan.self, includeSchemaInPrompt: false, options: GenerationOptions(sampling: .greedy))
            guard try await isCommand else {
                return CommandJSON.encode([Command(.unknown)])
            }
            return CommandJSON.encode(response.content.commands.map(Self.command))
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw AutoAIError("內容太長")
        }
    }

    // MARK: - 關卡：是不是要 App 做事

    // 小模型對無關的話（「嗯」「今天的新聞是什麼」）也會編出指令；是非題比較準，和判斷同時跑，幾乎不多花時間（2026-10-08 實測）。

    static let gateInstructions = """
        判斷使用者的話是不是要待辦清單 App 做事：新增、查詢、修改、刪除待辦，標成完成，查日期，查天氣，翻頁，復原、重做，或問 App 怎麼用。
        是就回答 true。只是聊天、問 App 做不到的事（新聞、訂票等）、問小精靈自己、只有語氣詞，回答 false。
        """

    @Generable
    struct Gate {
        @Guide(description: "要 App 做事為 true")
        var isCommand: Bool
    }

    private static func isCommand(_ request: String) async throws -> Bool {
        let session = LanguageModelSession(instructions: gateInstructions)
        return try await session.respond(to: request, generating: Gate.self, options: GenerationOptions(sampling: .greedy)).content.isCommand
    }

    // MARK: - 刪除確認

    @Generable
    struct Confirmation {
        @Guide(description: "使用者同意刪除全部、拒絕，或指定其中某些項目與新需求", .anyOf(["yes", "no", "other"]))
        var answer: String
    }

    func confirmDelete(_ request: String) async throws -> String {
        let session = LanguageModelSession(instructions: JudgePrompt.confirmInstructions)
        let start = ContinuousClock.now
        defer {
            let elapsed = ContinuousClock.now - start
            Task { await Self.printTranscript("Confirm", session, elapsed) }
        }
        let response = try await session.respond(to: request, generating: Confirmation.self)
        return CommandJSON.encodeAnswer(ConfirmAnswer(rawValue: response.content.answer) ?? .no)
    }

    // MARK: - 判斷的輸出結構

    // 每種指令只有自己的欄位：共用一組欄位時，模型會把用不到的欄位也填上（year: 2025、date: 部門會議）。

    // 欄位依宣告的順序產生：要找待辦的指令先產生 keyword 再產生 date，讓模型先寫出要找什麼，再決定要不要給日期。

    /// 日期是依單位順序組成的字串，合法與否由日期解析判斷（見 docs/specs/date-time.md）。
    private static let dateGuide = "日期字串，寫法見提示詞的 date、newDate"

    @Generable
    struct DateFields {
        @Guide(description: "要查的日期；" + dateGuide)
        var date: String
    }

    @Generable
    struct TargetFields {
        @Guide(description: "待辦內容的關鍵字，沒說就省略")
        var keyword: String?
        @Guide(description: "要找的待辦的日期，沒說就省略；" + dateGuide)
        var date: String?
    }

    @Generable
    struct DeleteFields {
        @Guide(description: "待辦內容的關鍵字，沒說就省略")
        var keyword: String?
        @Guide(description: "畫面上的編號：一個「2」或一段「3~10」；用編號指定時才填，keyword、date 省略")
        var number: String?
        @Guide(description: "要刪的待辦的日期，沒說就省略；刪除畫面上的全部時和 keyword 都省略；" + dateGuide)
        var date: String?
        @Guide(description: "只刪已完成的待辦時為 true，否則省略")
        var isDone: Bool?
    }

    @Generable
    struct AddFields {
        @Guide(description: "待辦的日期與時間，沒說就省略；" + dateGuide)
        var date: String?
        @Guide(description: "待辦內容")
        var content: String
    }

    @Generable
    struct SetDoneFields {
        @Guide(description: "待辦內容的關鍵字；用編號指定時省略")
        var keyword: String?
        @Guide(description: "畫面上的編號：一個「2」或一段「3~10」；用編號指定時才填，keyword、date 省略")
        var number: String?
        @Guide(description: "要找的待辦的日期，沒說就省略；" + dateGuide)
        var date: String?
        @Guide(description: "設為已完成為 true，未完成為 false")
        var isDone: Bool
    }

    @Generable
    struct ModifyFields {
        @Guide(description: "要修改的待辦的內容關鍵字；用編號指定時省略")
        var keyword: String?
        @Guide(description: "畫面上的編號：一個「2」或一段「3~10」；用編號指定時才填，keyword、date 省略")
        var number: String?
        @Guide(description: "要修改的待辦的日期，沒說就省略；" + dateGuide)
        var date: String?
        @Guide(description: "修改後的日期或時刻，不改就省略；" + dateGuide)
        var newDate: String?
        @Guide(description: "修改後的內容，不改就省略")
        var newContent: String?
    }

    @Generable
    struct DisplayFields {
        @Guide(description: "「完成」是否勾選")
        var showDone: Bool
    }

    @Generable
    struct WeatherFields {
        @Guide(description: "地名，照使用者說的；沒說就省略，是所在地")
        var place: String?
        @Guide(description: "要查天氣的日期與時間，沒說就省略；" + dateGuide)
        var date: String?
    }

    @Generable
    struct HelpFields {
        @Guide(description: "提示的頁名", .anyOf(HintPage.all.map(\.name)))
        var page: String
    }

    @Generable
    // FM 明顯偏向第一個 case（2026-10-08 實測）：查詢日期排第一時直述句被判成查詢日期，新增待辦排第一後「第1項改到明天」被判成新增。
    // 新增是最常用的，所以排第一。
    enum GeneratedCommand {
        case 新增待辦(AddFields)
        case 查詢待辦(TargetFields)
        case 查詢日期(DateFields)
        case 設定完成(SetDoneFields)
        case 修改待辦(ModifyFields)
        case 刪除待辦(DeleteFields)
        case 設定顯示(DisplayFields)
        case 復原
        case 重做
        case 上一頁
        case 下一頁
        case 顯示全部
        // case 建立備份  // 備份暫停（見 docs/specs/backup.md）
        // case 換成備份
        case 全部念完
        case 說明(HelpFields)
        case 上個提示
        case 下個提示
        case 查天氣(WeatherFields)
        case 聽不懂
    }

    // 指令最多 3 條：小模型會把清單裡的指令一條一條全部列出來（2026-10-08 實測），一句話實際上最多兩件事。
    @Generable
    struct CommandPlan {
        @Guide(description: "依使用者說的順序，只列使用者明確要求的指令；跟待辦、日期與天氣無關、聽不清楚或只是雜音時只有一條「聽不懂」", .maximumCount(3))
        var commands: [GeneratedCommand]
    }

    private static func command(_ generated: GeneratedCommand) -> Command {
        let clean = { (text: String?) in text.flatMap { $0.isEmpty ? nil : $0 } }
        switch generated {
        case .查詢日期(let f): return Command(.queryDate, date: f.date)
        case .查詢待辦(let f): return Command(.queryTodos, date: clean(f.date), keyword: clean(f.keyword))
        case .新增待辦(let f): return Command(.addTodo, date: clean(f.date), content: f.content)
        case .設定完成(let f): return Command(.setDone, date: clean(f.date), keyword: clean(f.keyword), number: clean(f.number), isDone: f.isDone)
        case .修改待辦(let f):
            return Command(.modifyTodo, date: clean(f.date), keyword: clean(f.keyword), number: clean(f.number), content: clean(f.newContent), newDate: clean(f.newDate))
        case .刪除待辦(let f): return Command(.deleteTodos, date: clean(f.date), keyword: clean(f.keyword), number: clean(f.number), isDone: f.isDone)
        case .設定顯示(let f): return Command(.setDisplay, showDone: f.showDone)
        case .復原: return Command(.undo)
        case .重做: return Command(.redo)
        case .上一頁: return Command(.previousPage)
        case .下一頁: return Command(.nextPage)
        case .顯示全部: return Command(.showEverything)
        // case .建立備份: return Command(.createBackup)
        // case .換成備份: return Command(.replaceBackup)
        case .全部念完: return Command(.readAll)
        case .說明(let f): return Command(.help, page: f.page)
        case .上個提示: return Command(.previousHint)
        case .下個提示: return Command(.nextHint)
        case .查天氣(let f): return Command(.weather, date: clean(f.date), place: clean(f.place))
        case .聽不懂: return Command(.unknown)
        }
    }

    /// 印出完整的 transcript（instructions、prompt、回應）、耗時與 token 用量。
    private static func printTranscript(_ stage: String, _ session: LanguageModelSession, _ elapsed: Duration) async {
        let model = SystemLanguageModel.default
        let tokens = (try? await model.tokenCount(for: session.transcript)).map(String.init) ?? "?"
        let seconds = elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
        print("""
            ==================== [\(stage)] \(seconds)　tokens \(tokens) / \(model.contextSize)
            \(session.transcript.map { String(describing: $0) }.joined(separator: "\n----\n"))
            ====================
            """)
    }
}
