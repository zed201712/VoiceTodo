//
//  GeminiAI.swift
//  voicecalender
//

import Foundation

/// 自動 AI 的 Gemini 實作：Gemini API 的 generateContent，以 JSON Schema 限制輸出結構（見 docs/specs/judgment.md 的「自動 AI」）。
/// API key 由設定提供（Keychain），每次請求時才讀；每次請求只帶提示詞與這個請求，不保留紀錄。
///
/// Gemini 的限制（2026-09-30 實測 gemini-3.1-flash-lite、gemini-3.5-flash）：
/// - 照 Schema 裡欄位的順序產生輸出，順序會影響判斷，所以用 propertyOrdering 固定順序（見 judgeSchema）。
/// - 會隱藏思考，思考的 token 算進 maxOutputTokens 卻不回報，thinkingBudget 0 關不掉；
///   所以刪除確認的輸出上限比 Ollama 高。
struct GeminiAI: AutoAI, CorrectionAI, ChatAI {

    let model: String
    /// 讀設定裡的 API key；沒有就是 nil。
    let apiKey: () -> String?

    var name: String { "Gemini \(model)" }
    var status: String { key == nil ? Self.missingKey : "模型：\(model)" }
    let judgePrompt = FixedPrompt(instructions: JudgePrompt.judgeInstructions, schema: JudgePrompt.text(Self.judgeSchema))
    let confirmPrompt = FixedPrompt(instructions: JudgePrompt.confirmInstructions, schema: JudgePrompt.text(JudgePrompt.confirmSchema))
    let correctionPrompt = FixedPrompt(instructions: CorrectionPrompt.instructions, schema: JudgePrompt.text(CorrectionPrompt.schema))
    let chatPrompt = FixedPrompt(instructions: ChatPrompt.instructions, schema: JudgePrompt.text(ChatPrompt.schema))

    private static let missingKey = "未設定 Gemini API key，請到設定填入"

    private var key: String? {
        apiKey().flatMap { $0.isEmpty ? nil : $0 }
    }
    private static let timeout: TimeInterval = 60

    func judge(_ request: String) async throws -> String {
        try await generate("Judge", instructions: JudgePrompt.judgeInstructions, request: request, schema: Self.judgeSchema, maxTokens: 512)
    }

    func confirmDelete(_ request: String) async throws -> String {
        try await generate("Confirm", instructions: JudgePrompt.confirmInstructions, request: request, schema: JudgePrompt.confirmSchema, maxTokens: 64)
    }

    private struct Text: Decodable {
        let text: String
    }

    /// 校正（見 docs/specs/correction.md）：輸出上限含隱藏的思考，所以比一句話需要的高。
    func correct(_ request: String) async throws -> String {
        try await text("Correct", instructions: CorrectionPrompt.instructions, request: request, schema: CorrectionPrompt.schema)
    }

    /// 聊天（見 docs/specs/chat.md）：回答問題時最多 80 字，加上隱藏的思考，輸出上限比校正高。
    func chat(_ request: String) async throws -> String {
        try await text("Chat", instructions: ChatPrompt.instructions, request: request, schema: ChatPrompt.schema, maxTokens: 512)
    }

    private func text(_ label: String, instructions: String, request: String, schema: [String: Any], maxTokens: Int = 256) async throws -> String {
        let json = try await generate(label, instructions: instructions, request: request, schema: schema, maxTokens: maxTokens)
        guard let output = try? JSONDecoder().decode(Text.self, from: Data(json.utf8)) else {
            throw AutoAIError("Gemini 回應格式不符")
        }
        return output.text
    }

    // MARK: - 呼叫 Gemini

    private struct Reply: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
            let finishReason: String?
        }

        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
        }

        struct APIError: Decodable {
            let status: String?
            let message: String?
        }

        let candidates: [Candidate]?
        let usageMetadata: Usage?
        let error: APIError?
    }

    private func generate(_ stage: String, instructions: String, request: String, schema: [String: Any], maxTokens: Int) async throws -> String {
        guard let apiKey = key else {
            throw AutoAIError(Self.missingKey)
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": [["text": request]]]],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": maxTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": schema,
            ],
        ]
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var urlRequest = URLRequest(url: url, timeoutInterval: Self.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = ContinuousClock.now
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw AutoAIError("沒有網路")
        } catch let error as URLError where error.code == .timedOut {
            throw AutoAIError("Gemini 超過 \(Int(Self.timeout)) 秒沒有回應")
        }
        let elapsed = ContinuousClock.now - start

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw AutoAIError("Gemini 回應格式不符")
        }
        if let error = reply.error {
            // 例如 key 無效、超過配額、找不到模型
            if error.status == "UNAVAILABLE" {
                throw AutoAIError("Gemini 忙線，請再說一次")
            }
            throw AutoAIError("Gemini：\(error.message ?? error.status ?? "未知錯誤")")
        }
        let candidate = reply.candidates?.first
        guard let content = candidate?.content?.parts?.compactMap(\.text).joined(), !content.isEmpty else {
            throw AutoAIError("Gemini 回應沒有內容（\(candidate?.finishReason ?? "沒有結果")）")
        }
        Self.printExchange(stage, instructions, request, content, reply, elapsed)
        if candidate?.finishReason == "MAX_TOKENS" {
            throw AutoAIError("輸出超過上限（\(maxTokens) token）")
        }
        return content
    }

    // MARK: - 測試連線

    /// 查詢模型的資訊：確認 key 有效、模型存在；不呼叫生成，不耗 token（見 docs/specs/settings.md）。
    func testConnection() async -> String {
        guard let apiKey = key else {
            return Self.missingKey
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model)") else {
            return "模型名稱不正確"
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: Self.timeout)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        do {
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            return Self.connectionResult(data)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            return "沒有網路"
        } catch let error as URLError where error.code == .timedOut {
            return "Gemini 超過 \(Int(Self.timeout)) 秒沒有回應"
        } catch {
            return "Gemini：\(error.localizedDescription)"
        }
    }

    private struct ModelInfo: Decodable {
        let name: String?
        let error: Reply.APIError?
    }

    /// 測試連線的回應：有模型名稱就成功，否則回報 API 的錯誤（key 無效、找不到模型）。
    static func connectionResult(_ data: Data) -> String {
        guard let info = try? JSONDecoder().decode(ModelInfo.self, from: data) else {
            return "Gemini 回應格式不符"
        }
        if let error = info.error {
            return "Gemini：\(error.message ?? error.status ?? "未知錯誤")"
        }
        return info.name == nil ? "Gemini 回應格式不符" : "連線成功"
    }

    /// 印出提示詞、請求、回應、耗時與 token 用量。
    private static func printExchange(_ stage: String, _ instructions: String, _ request: String, _ content: String, _ reply: Reply, _ elapsed: Duration) {
        let seconds = elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
        let usage = reply.usageMetadata
        let tokens = "prompt \(usage?.promptTokenCount.map(String.init) ?? "?")　output \(usage?.candidatesTokenCount.map(String.init) ?? "?")"
        print("""
            ==================== [Gemini \(stage)] \(seconds)　tokens \(tokens)
            \(instructions)
            ----
            \(request)
            ----
            \(content)
            ====================
            """)
    }

    // MARK: - 輸出結構

    /// 欄位的產生順序。Swift 的 Dictionary 每次啟動順序都不同，送出的 Schema 順序也跟著變；
    /// 2026-09-30 實測（gemini-3.1-flash-lite）「明天買水果」：順序隨機時 12 次都錯（混用各指令的欄位、自己加上 year、
    /// 同一條指令寫兩次、星期填進 specificDay），字母排序也錯；固定成下列順序後都正確。
    private static let propertyOrder = [
        "commands", "action", "date", "content", "keyword", "number", "newDate", "newContent", "isDone", "showDone", "place", "page",
    ]

    /// JudgePrompt 的判斷結構，每個物件加上 propertyOrdering。
    static let judgeSchema = ordered(JudgePrompt.judgeSchema) as! [String: Any]

    static func ordered(_ schema: Any) -> Any {
        if let array = schema as? [Any] {
            return array.map(ordered)
        }
        guard var object = (schema as? [String: Any])?.mapValues(ordered) else {
            return schema
        }
        if let properties = object["properties"] as? [String: Any] {
            object["propertyOrdering"] = propertyOrder.filter { properties[$0] != nil }
        }
        return object
    }
}
