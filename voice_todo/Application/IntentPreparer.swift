//
//  IntentPreparer.swift
//  voicecalender
//

import Foundation

/// 釐清或刪除確認的問題，與原本的指令。
struct Clarification {
    let question: String
    let command: Command
}

/// 判斷失敗的那次判斷：重試時用同一份使用者提示詞，不再校正（見 docs/specs/recovery.md 的「重試的範圍」）。
struct Failure {
    /// 校正後送去判斷的句子。
    let text: String
    let clarification: Clarification?
    /// 同一句話裡排在後面、還沒執行的指令。
    let rest: [Command]
    /// 一般判斷時還沒凍結的提示：請求多的那一行。
    var hint: ScreenInfo.Hint? = nil
}

/// 使用者意圖：一句話解讀之後的結果，輪到時才執行（見 docs/specs/queue.md）。
struct UserIntent {
    enum Kind {
        case commands([Command])
        /// 判斷沒有指令：聊天的回應；nil 時退回「聽不懂」，`note` 是原因。
        case chat(reply: String?, note: String, screen: ScreenInfo)
        case failed(message: String, failure: Failure)
    }

    let kind: Kind
    /// 採用的句子（校正後）。
    let text: String
    /// 句子裡帶著「全部念完」：輪到時先打開 readAll。
    var readAll = false
}

/// 校正 ∥ 判斷的結果。
enum Interpretation {
    case commands([Command], text: String)
    /// 一般判斷沒有指令（聽不懂、空清單）。
    case none(text: String)
    case failed(message: String, failure: Failure)
}

/// 背景的部分（見 docs/specs/queue.md）：把一句話解讀成使用者意圖。
/// 只讀句子與畫面資訊的快照，拿不到待辦與黑板，所以不會改任何狀態；使用者提示詞送給 AI 的方式由小精靈提供。
struct IntentPreparer {

    /// 把使用者提示詞交給自動 AI 或手動 AI（句子編號、階段、種類、固定提示詞名稱、使用者提示詞、自動 AI 的呼叫）；
    /// 自動 AI 失敗時丟出錯誤，取消時回傳 nil。
    let respond: (Int, String, String, String, String, @escaping () async throws -> String) async throws -> String?
    let log: (Int, String, String) -> Void
    /// 校正的輸入與結果，給除錯 UI。
    let showCorrection: (String, String) -> Void
    /// 校正採用了新句子（句子編號、校正後的句子）：對話流裡的這句話馬上換掉（見 docs/specs/correction.md 的「之後用哪一句」）。
    let adoptCorrection: (Int, String) -> Void
    /// 開始解讀時的設定：之後才換的 AI 不影響這句話。
    let autoAI: (any AutoAI)?
    let useAutoAI: Bool
    /// 挑出這次聊天的補充資訊（見 docs/specs/chat.md 的「補充資訊」）；循環的狀態在小精靈。
    let chatExtra: (String) -> ChatExtra

    static let noAI = "目前沒有可以使用的 AI，無法運作，請到設定開啟"
    static let judgePromptName = "判斷提示詞"
    static let correctionPromptName = "校正提示詞"
    static let chatPromptName = "聊天提示詞"

    /// 規則判斷（含只在一般判斷之前比對的固定說法、還沒凍結的提示的連結）：不用等，命中就是使用者意圖。
    func rule(_ text: String, number: Int, screen: ScreenInfo) -> UserIntent? {
        if let command = JudgeTool.generalCommand(text) {
            showCorrection(text, "規則判斷，不校正")
            log(number, "判斷", "規則：\(command.summary)")
            return UserIntent(kind: .commands([command]), text: text)
        }
        return judgeTool(text, number: number, links: screen.hint?.links ?? []).map { UserIntent(kind: .commands([$0]), text: text) }
    }

    /// 一般的一句話：規則判斷、校正 ∥ 一般判斷，沒有指令就聊天。取消時回傳 nil。
    func prepare(_ text: String, number: Int, screen: ScreenInfo) async -> UserIntent? {
        if let intent = rule(text, number: number, screen: screen) {
            return intent
        }
        let readAll = ReportKeywords.containsReadAll(text)
        guard let result = await interpret(text, number: number, screen: screen, clarification: nil, rest: []) else {
            return nil
        }
        switch result {
        case .commands(let list, let adopted):
            return UserIntent(kind: .commands(list), text: adopted, readAll: readAll)
        case .failed(let message, let failure):
            return UserIntent(kind: .failed(message: message, failure: failure), text: failure.text, readAll: readAll)
        case .none(let adopted):
            guard let (reply, note) = await chat(adopted, number: number, screen: screen) else {
                return nil
            }
            return UserIntent(kind: .chat(reply: reply, note: note, screen: screen), text: adopted, readAll: readAll)
        }
    }

    /// 規則判斷，沒命中就校正和用原句的判斷同時開始（見 docs/specs/correction.md 的「和判斷同時進行」）：
    /// 校正採用了新句子就作廢原句的判斷、用新句子重判，否則用原句的判斷。兩邊都回來才決定。
    func interpret(_ text: String, number: Int, screen: ScreenInfo, clarification: Clarification?, rest: [Command]) async -> Interpretation? {
        // 規則判斷命中的句型是完整的指令，不會是回答：在釐清中也當成新需求（見 docs/specs/judge-tool.md）。
        // 一般判斷才看還沒凍結的提示；釐清中的提示一定已經凍結。
        let hint = clarification == nil ? screen.hint : nil
        if let hit = judgeTool(text, number: number, links: hint?.links ?? []) {
            return .commands([hit] + rest, text: text)
        }
        let original = Task { await self.judgment(text, number: number, clarification: clarification, hint: hint) }
        let corrected = await withTaskCancellationHandler {
            await correct(text, number: number, screen: screen)
        } onCancel: {
            original.cancel()
        }
        guard let corrected else {
            original.cancel()
            return nil
        }
        guard corrected == text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            original.cancel()
            adoptCorrection(number, corrected)
            log(number, "判斷", "校正改了句子，作廢原句的判斷，重新判斷")
            // 重判也是一次 AI 判斷的呼叫，先用規則判斷（見 docs/specs/judge-tool.md 的「什麼時候調用」）。
            if let hit = judgeTool(corrected, number: number, links: hint?.links ?? [], corrected: true) {
                return .commands([hit] + rest, text: corrected)
            }
            return await judge(corrected, number: number, clarification: clarification, rest: rest, hint: hint)
        }
        let judged = await withTaskCancellationHandler {
            await original.value
        } onCancel: {
            original.cancel()
        }
        guard let judged, !Task.isCancelled else {
            return nil
        }
        return await judge(text, number: number, clarification: clarification, rest: rest, hint: hint, judged: judged)
    }

    /// `judged` 是已經取得的判斷；沒有就現在判斷（重試也從這裡開始，不再校正）。
    func judge(_ text: String, number: Int, clarification: Clarification?, rest: [Command], hint: ScreenInfo.Hint? = nil, judged: Judgment? = nil) async -> Interpretation? {
        var result = judged
        if result == nil {
            result = await judgment(text, number: number, clarification: clarification, hint: hint)
        }
        switch result {
        case nil:
            return nil
        case .failed(let message):
            return .failed(message: message, failure: Failure(text: text, clarification: clarification, rest: rest, hint: hint))
        case .commands(var list):
            // 有「聽不懂」時整句都不執行：和其他指令混在一起代表 AI 也不確定。
            if list.contains(where: { $0.action == .unknown }) {
                list = []
            }
            // 沒有指令：一般判斷交給聊天；釐清後判斷是取消（見 docs/specs/flow.md）。
            if clarification == nil && list.isEmpty {
                return .none(text: text)
            }
            return .commands(list + rest, text: text)
        }
    }

    /// 規則判斷（見 docs/specs/judge-tool.md）：命中就取代這次的 AI 判斷；`corrected` 是校正後的句子，保留校正的紀錄。
    private func judgeTool(_ text: String, number: Int, links: [String], corrected: Bool = false) -> Command? {
        guard let command = JudgeTool.command(text, today: .now, links: links) else {
            return nil
        }
        if !corrected {
            showCorrection(text, "規則判斷，不校正")
        }
        log(number, "判斷", "規則：\(command.summary)")
        return command
    }

    // MARK: - 判斷

    /// 判斷的結果：指令清單，或失敗的原因（由呼叫的一方決定要不要進入錯誤確認）。
    enum Judgment {
        case commands([Command])
        case failed(String)
    }

    /// AI 把一句話翻成指令清單。失敗的原因由自動 AI 的實作提供，回應不合法也算失敗；取消時回傳 nil。
    private func judgment(_ text: String, number: Int, clarification: Clarification?, hint: ScreenInfo.Hint?) async -> Judgment? {
        let request = clarification.map {
            "小精靈剛才問：\($0.question)\n原本的指令：\($0.command.summary)\n使用者說：\(text)"
        } ?? hint.map { "\($0.line)\n使用者說：\(text)" } ?? text
        let kind = clarification == nil ? "一般判斷" : "釐清後判斷"
        let ai = autoAI

        let json: String?
        do {
            json = try await respond(number, "判斷", kind, Self.judgePromptName, request) {
                guard let ai else {
                    throw AutoAIError(Self.noAI)
                }
                return try await ai.judge(request)
            }
        } catch {
            return .failed("判斷失敗：\(error.localizedDescription)")
        }
        guard let json else {
            return nil
        }
        do {
            return .commands(try CommandJSON.decode(json))
        } catch {
            let source = useAutoAI ? "自動 AI" : "手動 AI"
            return .failed("\(source) 回應無法解析：\(error.localizedDescription)")
        }
    }

    // MARK: - 校正

    /// 只修錯別字（見 docs/specs/correction.md）：不校正、失敗或不採用時回傳原句，不進入錯誤確認；取消時回傳 nil。
    private func correct(_ text: String, number: Int, screen: ScreenInfo) async -> String? {
        let result: (text: String, note: String)
        if !useAutoAI {
            result = (text, "手動 AI，不校正")
        } else if let corrector = autoAI as? any CorrectionAI {
            let request = screen.request(userSaid: text)
            log(number, "校正", "自動 AI｜\(Self.correctionPromptName)")
            log(number, "校正", "請求：\(request)")
            do {
                let start = ContinuousClock.now
                let output = try await corrector.correct(request)
                guard !Task.isCancelled else {
                    return nil
                }
                log(number, "校正", "回應（\(Self.elapsed(since: start))）：\(output)")
                result = Correction.accept(output, for: text)
            } catch {
                guard !Task.isCancelled else {
                    return nil
                }
                result = (text, "校正失敗，用原句：\(error.localizedDescription)")
            }
        } else {
            result = (text, "目前的 AI 沒有校正功能，不校正")
        }
        showCorrection(text, result.note)
        log(number, "校正", result.note)
        return result.text
    }

    // MARK: - 聊天

    /// 判斷沒有指令時接話（見 docs/specs/chat.md）：回傳回應，或退回「聽不懂」的原因；取消時回傳 nil。
    func chat(_ text: String, number: Int, screen: ScreenInfo) async -> (reply: String?, note: String)? {
        let result = await reply(to: text, number: number, screen: screen)
        if let result {
            log(number, "聊天", result.note)
        }
        return result
    }

    private func reply(to text: String, number: Int, screen: ScreenInfo) async -> (reply: String?, note: String)? {
        guard useAutoAI else {
            return (nil, "手動 AI，不聊天")
        }
        guard let chatter = autoAI as? any ChatAI else {
            return (nil, "目前的 AI 沒有聊天功能")
        }
        let extra = chatExtra(text)
        let request = screen.request(userSaid: text, extra: extra.line)
        log(number, "聊天", "自動 AI｜\(Self.chatPromptName)")
        log(number, "聊天", "補充資訊：\(extra.summary)")
        log(number, "聊天", "請求：\(request)")
        do {
            let reply = ScreenInfo.clip(try await chatter.chat(request))
            guard !Task.isCancelled else {
                return nil
            }
            return reply.isEmpty ? (nil, "聊天的回應是空的") : (reply, reply)
        } catch {
            guard !Task.isCancelled else {
                return nil
            }
            return (nil, "聊天失敗：\(error.localizedDescription)")
        }
    }

    /// 測試紀錄的耗時，例如 `1.7 sec`。
    static func elapsed(since start: ContinuousClock.Instant) -> String {
        (ContinuousClock.now - start).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
    }
}
