//
//  AIAlignmentEval.swift
//  voicecalenderTests
//

import Foundation
import Testing
@testable import voicecalender

// MARK: - 判斷的對齊評估（見 docs/eval/ai-alignment.md）

// 平常不跑：要呼叫真的 AI。環境變數 AI_EVAL 決定跑哪一段（xcodebuild 用 TEST_RUNNER_AI_EVAL 傳入）：
// - gemini：每句用真的 Elf 與 Gemini 跑一次，記錄最後採用的判斷 → AIAlignmentGemini.json
// - fm：每句用真的 Elf 與 Foundation Models 跑一次，和預期、Gemini 的記錄比對 → AIAlignmentReport.md
// AI_EVAL_ONLY 只跑這些句子（「|」分隔），調整時只重跑錯的。
// 檔案寫在 App 容器的暫存資料夾（測試在 App 的沙盒裡）：~/Library/Containers/z.voicecalender/Data/tmp/；
// macOS 27 起終端機讀不到 App 的容器，所以也附在測試結果裡（xcresulttool export attachments）。

/// 一句測試句與預期的指令清單（依 spec 寫，不是 Gemini 的輸出）。都不會命中關鍵字與規則判斷。
struct AlignmentCase {
    let sentence: String
    let expected: String

    /// 聽不懂交給聊天。
    static let unknown = #"{"commands":[{"action":"聽不懂"}]}"#

    static let all: [AlignmentCase] = [
        // 評估句
        .init(sentence: "明天要看牙醫", expected: #"{"commands":[{"action":"新增待辦","date":"明天","content":"看牙醫"}]}"#),
        .init(sentence: "明天有什麼預定行程", expected: #"{"commands":[{"action":"查詢待辦","date":"明天"}]}"#),
        .init(sentence: "下個月要忙些什麼", expected: #"{"commands":[{"action":"查詢待辦","date":"下個月"}]}"#),
        .init(sentence: "下禮拜三我要忙什麼", expected: #"{"commands":[{"action":"查詢待辦","date":"下週週三"}]}"#),
        .init(sentence: "把部門會議改到下週一", expected: #"{"commands":[{"action":"修改待辦","keyword":"部門會議","newDate":"下週週一"}]}"#),
        .init(sentence: "刪除明天的買水果", expected: #"{"commands":[{"action":"刪除待辦","date":"明天","keyword":"買水果"}]}"#),
        .init(sentence: "買牛奶已經完成了", expected: #"{"commands":[{"action":"設定完成","keyword":"買牛奶","isDone":true}]}"#),
        .init(sentence: "下個月十五號下午三點半看牙醫", expected: #"{"commands":[{"action":"新增待辦","date":"下個月15日下午3點30分","content":"看牙醫"}]}"#),
        .init(sentence: "看牙醫", expected: #"{"commands":[{"action":"新增待辦","content":"看牙醫"}]}"#),
        .init(sentence: "有什麼會議", expected: #"{"commands":[{"action":"查詢待辦","keyword":"會議"}]}"#),
        .init(sentence: "我不知道怎麼把事情加進去", expected: #"{"commands":[{"action":"說明","page":"新增"}]}"#),
        .init(sentence: "剛剛那個不要了", expected: #"{"commands":[{"action":"復原"}]}"#),
        .init(sentence: "明天天氣好的話去爬山", expected: #"{"commands":[{"action":"新增待辦","date":"明天","content":"天氣好的話去爬山"}]}"#),
        .init(sentence: "提醒我後天下午三點跟小美吃飯", expected: #"{"commands":[{"action":"新增待辦","date":"後天下午3點","content":"跟小美吃飯"}]}"#),
        .init(sentence: "嗯", expected: unknown),
        .init(sentence: "今天的新聞是什麼", expected: unknown),
        .init(sentence: "小精靈你叫什麼名字", expected: unknown),
        .init(sentence: "幫我訂明天的高鐵票", expected: unknown),
        .init(sentence: "先生明天看牙醫", expected: #"{"commands":[{"action":"新增待辦","date":"明天","content":"看牙醫"}]}"#),
        .init(sentence: "10月6號麵是", expected: #"{"commands":[{"action":"新增待辦","date":"10月6日","content":"面試"}]}"#),
        // 提示頁裡規則判斷不收的句型
        .init(sentence: "新增明天買牛奶", expected: #"{"commands":[{"action":"新增待辦","date":"明天","content":"買牛奶"}]}"#),
        .init(sentence: "新增今天下午3點買牛奶", expected: #"{"commands":[{"action":"新增待辦","date":"今天下午3點","content":"買牛奶"}]}"#),
        .init(sentence: "新增10月10日上午9點看牙醫", expected: #"{"commands":[{"action":"新增待辦","date":"10月10日上午9點","content":"看牙醫"}]}"#),
        .init(sentence: "買牛奶改到後天", expected: #"{"commands":[{"action":"修改待辦","keyword":"買牛奶","newDate":"後天"}]}"#),
        .init(sentence: "買牛奶完成", expected: #"{"commands":[{"action":"設定完成","keyword":"買牛奶","isDone":true}]}"#),
        // 換說法（實機說過的與相近的）
        .init(sentence: "讓第二項改到明天", expected: #"{"commands":[{"action":"修改待辦","number":"2","newDate":"明天"}]}"#),
        .init(sentence: "降低二項改到明天", expected: #"{"commands":[{"action":"修改待辦","number":"2","newDate":"明天"}]}"#),
        .init(sentence: "弄第三跟第四項改到10月1號", expected: #"{"commands":[{"action":"修改待辦","number":"3","newDate":"10月1日"},{"action":"修改待辦","number":"4","newDate":"10月1日"}]}"#),
        .init(sentence: "第一項做完了", expected: #"{"commands":[{"action":"設定完成","number":"1","isDone":true}]}"#),
        .init(sentence: "幫我刪掉第2項", expected: #"{"commands":[{"action":"刪除待辦","number":"2"}]}"#),
        .init(sentence: "晚上9:00跟小明吃飯", expected: #"{"commands":[{"action":"新增待辦","date":"晚上9點","content":"跟小明吃飯"}]}"#),
        .init(sentence: "新增後天下午兩點開會", expected: #"{"commands":[{"action":"新增待辦","date":"後天下午2點","content":"開會"}]}"#),
        .init(sentence: "買牛奶改到下週一", expected: #"{"commands":[{"action":"修改待辦","keyword":"買牛奶","newDate":"下週週一"}]}"#),
    ]
}

/// 一次 AI 呼叫。
struct AlignmentCall: Codable {
    let stage: String
    let request: String
    let response: String
    let seconds: Double
}

/// 一句話的結果：最後採用的判斷、校正的回應與整句的耗時。
struct AlignmentResult: Codable {
    let sentence: String
    let judge: String?
    let correction: String?
    let seconds: Double
}

/// 把真的 AI 包起來，記錄每次呼叫的請求與回應。
@MainActor
final class RecordingAI: AutoAI, CorrectionAI, ChatAI {
    let base: any AutoAI
    private(set) var calls: [AlignmentCall] = []

    init(_ base: any AutoAI) {
        self.base = base
    }

    private static let unsupported = FixedPrompt(instructions: "", schema: "{}")

    var name: String { base.name }
    var status: String { base.status }
    var judgePrompt: FixedPrompt { base.judgePrompt }
    var confirmPrompt: FixedPrompt { base.confirmPrompt }
    var correctionPrompt: FixedPrompt { (base as? any CorrectionAI)?.correctionPrompt ?? Self.unsupported }
    var chatPrompt: FixedPrompt { (base as? any ChatAI)?.chatPrompt ?? Self.unsupported }

    func judge(_ request: String) async throws -> String {
        try await record("判斷", request) { try await self.base.judge(request) }
    }

    func confirmDelete(_ request: String) async throws -> String {
        try await record("刪除確認", request) { try await self.base.confirmDelete(request) }
    }

    /// 沒有校正、聊天功能的 AI 記成「沒有這個功能」。
    func correct(_ request: String) async throws -> String {
        try await record("校正", request) {
            guard let ai = self.base as? any CorrectionAI else { throw AutoAIError("沒有校正功能") }
            return try await ai.correct(request)
        }
    }

    func chat(_ request: String) async throws -> String {
        try await record("聊天", request) {
            guard let ai = self.base as? any ChatAI else { throw AutoAIError("沒有聊天功能") }
            return try await ai.chat(request)
        }
    }

    private func record(_ stage: String, _ request: String, _ call: () async throws -> String) async throws -> String {
        let start = ContinuousClock.now
        for attempt in 1...3 {
            do {
                let response = try await call()
                calls.append(AlignmentCall(stage: stage, request: request, response: response, seconds: AIAlignmentEval.seconds(since: start)))
                return response
            } catch where attempt < 3 && error.localizedDescription.contains("quota") {
                // Gemini 的免費額度用完：等一下再試，不記錄這次
                try await Task.sleep(for: .seconds(40))
            } catch {
                calls.append(AlignmentCall(stage: stage, request: request, response: "錯誤：\(error.localizedDescription)", seconds: AIAlignmentEval.seconds(since: start)))
                throw error
            }
        }
        fatalError("不會到這裡")
    }
}

private final class BundleToken {}

@MainActor
struct AIAlignmentEval {

    nonisolated private static let mode = ProcessInfo.processInfo.environment["AI_EVAL"]
    private static let only = ProcessInfo.processInfo.environment["AI_EVAL_ONLY"].map { Set($0.split(separator: "|").map(String.init)) }
    private static let referenceName = "AIAlignmentGemini"

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private static var cases: [AlignmentCase] {
        AlignmentCase.all.filter { only?.contains($0.sentence) != false }
    }

    /// 每句一個新的 Elf（測試待辦、黑板是「目前」），走 App 的路徑：規則校正 → 規則判斷 → AI 校正 ∥ 判斷，校正採用時重判。
    private func run(_ item: AlignmentCase, on ai: any AutoAI) async -> AlignmentResult {
        if JudgeTool.command(Correction.tool(item.sentence), today: .now) != nil {
            Issue.record("「\(item.sentence)」命中規則判斷，兩邊一樣，換一句")
        }
        let recorder = RecordingAI(ai)
        let elf = Elf(autoAI: recorder, wait: { _ in })
        let start = ContinuousClock.now
        elf.submitTestInput(item.sentence)
        try? await Task.sleep(for: .seconds(1))
        let deadline = ContinuousClock.now + .seconds(300)
        while !elf.isIdle, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        // 最後採用的判斷：作廢的（校正採用後被取消的）不算
        let judge = recorder.calls.last { $0.stage == "判斷" && !$0.response.hasPrefix("錯誤：cancelled") }?.response
        let correction = recorder.calls.first { $0.stage == "校正" }?.response
        return AlignmentResult(sentence: item.sentence, judge: judge, correction: correction, seconds: Self.seconds(since: start))
    }

    @Test(.enabled(if: mode == "gemini"))
    func 記錄Gemini() async throws {
        let key = try #require(SettingsStorage.loadGeminiKey(), "Keychain 裡沒有 Gemini API key")
        var results: [AlignmentResult] = []
        for item in Self.cases {
            results.append(await run(item, on: GeminiAI(model: AISettings.initial().geminiModel, apiKey: { key })))
            // 免費額度每分鐘 15 次，一句最多 4 次呼叫
            try await Task.sleep(for: .seconds(15))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(results)
        try data.write(to: FileManager.default.temporaryDirectory.appending(path: "\(Self.referenceName).json"))
        Attachment.record(data, named: "\(Self.referenceName).json")
    }

    @Test(.enabled(if: mode == "fm"))
    func FoundationModels對照() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: Self.referenceName, withExtension: "json"), "缺少 \(Self.referenceName).json")
        let gemini = try JSONDecoder().decode([AlignmentResult].self, from: Data(contentsOf: url))
        let fm = FoundationModelsAI()
        try await Task.sleep(for: .seconds(8))
        var report = AlignmentReport()
        for item in Self.cases {
            let result = await run(item, on: fm)
            report.add(item, gemini: gemini.first { $0.sentence == item.sentence }, fm: result)
            try report.text.write(to: FileManager.default.temporaryDirectory.appending(path: "AIAlignmentReport.md"), atomically: true, encoding: .utf8)
            // 實際使用時句子之間有空檔，讓 prewarm 好下一個 session
            try await Task.sleep(for: .seconds(3))
        }
        Attachment.record(report.text, named: "AIAlignmentReport.md")
    }
}

// MARK: - 報告

/// 比對規則：最後採用的指令清單和預期完全相同；聽不懂和空清單相同。
struct AlignmentReport {
    private var lines: [String] = []
    private var score = (gemini: 0, fm: 0, total: 0)
    private var seconds: [Double] = []

    mutating func add(_ item: AlignmentCase, gemini: AlignmentResult?, fm: AlignmentResult) {
        let expected = Self.commands(item.expected)
        let geminiOK = Self.commands(gemini?.judge) == expected
        let fmOK = Self.commands(fm.judge) == expected
        score.total += 1
        score.gemini += geminiOK ? 1 : 0
        score.fm += fmOK ? 1 : 0
        seconds.append(fm.seconds)
        lines.append("""
            - \(item.sentence)（FM \(String(format: "%.1f", fm.seconds)) 秒）
              - 預期 `\(item.expected)`
              - Gemini \(geminiOK ? "✅" : "❌") `\(Self.oneLine(gemini?.judge))`
              - FM \(fmOK ? "✅" : "❌") `\(Self.oneLine(fm.judge))`　校正：\(Self.oneLine(fm.correction))
            """)
    }

    var text: String {
        let average = seconds.reduce(0, +) / Double(max(seconds.count, 1))
        return """
            # 判斷的對齊評估

            Gemini \(score.gemini)/\(score.total)　FM \(score.fm)/\(score.total)　FM 每句平均 \(String(format: "%.1f", average)) 秒、最長 \(String(format: "%.1f", seconds.max() ?? 0)) 秒

            \(lines.joined(separator: "\n"))
            """
    }

    private static func commands(_ json: String?) -> [Command]? {
        guard let json, let commands = try? CommandJSON.decode(json) else {
            return nil
        }
        return commands.isEmpty ? [Command(.unknown)] : commands
    }

    private static func oneLine(_ text: String?) -> String {
        (text ?? "（沒有）").replacingOccurrences(of: "\n", with: " ")
    }
}
