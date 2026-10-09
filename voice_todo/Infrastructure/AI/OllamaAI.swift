//
//  OllamaAI.swift
//  voicecalender
//

import Foundation

/// 自動 AI 的 Ollama 實作：/api/chat，位址由設定提供，以 JSON Schema 限制輸出結構（見 docs/specs/judgment.md 的「自動 AI」）。
/// 每次請求只帶提示詞與這個請求，不保留紀錄。
struct OllamaAI: AutoAI {

    let model: String
    let host: String
    let port: String

    var name: String { "Ollama \(model)" }
    var status: String { "端點：\(host):\(port)" }
    let judgePrompt = FixedPrompt(instructions: JudgePrompt.judgeInstructions, schema: JudgePrompt.text(JudgePrompt.judgeSchema))
    let confirmPrompt = FixedPrompt(instructions: JudgePrompt.confirmInstructions, schema: JudgePrompt.text(JudgePrompt.confirmSchema))

    /// 設定的位址加上 API 的路徑；位址不合法時是 nil。
    private func endpoint(_ path: String) -> URL? {
        URL(string: "http://\(host):\(port)\(path)")
    }

    private static let timeout: TimeInterval = 120

    func judge(_ request: String) async throws -> String {
        try await chat("Judge", instructions: JudgePrompt.judgeInstructions, request: request, schema: JudgePrompt.judgeSchema, maxTokens: 512)
    }

    func confirmDelete(_ request: String) async throws -> String {
        try await chat(
            "Confirm",
            instructions: JudgePrompt.confirmInstructions,
            request: request,
            schema: JudgePrompt.confirmSchema,
            maxTokens: 20
        )
    }

    // MARK: - 呼叫 Ollama

    private struct Reply: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message?
        let error: String?
        let done_reason: String?
        let prompt_eval_count: Int?
        let eval_count: Int?
    }

    private func chat(_ stage: String, instructions: String, request: String, schema: [String: Any], maxTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": request],
            ],
            "format": schema,
            "stream": false,
            "think": false,
            "options": ["temperature": 0, "num_predict": maxTokens],
        ]
        guard let url = endpoint("/api/chat") else {
            throw AutoAIError("Ollama 位址不正確：\(host):\(port)")
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: Self.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = ContinuousClock.now
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw AutoAIError("Ollama 沒有啟動")
        } catch let error as URLError where error.code == .timedOut {
            throw AutoAIError("Ollama 超過 \(Int(Self.timeout)) 秒沒有回應")
        }
        let elapsed = ContinuousClock.now - start

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw AutoAIError("Ollama 回應格式不符")
        }
        if let error = reply.error {
            // 例如找不到模型：model "xxx" not found
            throw AutoAIError("Ollama：\(error)")
        }
        guard let content = reply.message?.content else {
            throw AutoAIError("Ollama 回應沒有內容")
        }
        Self.printExchange(stage, instructions, request, content, reply, elapsed)
        if reply.done_reason == "length" {
            throw AutoAIError("輸出超過上限（\(maxTokens) token）")
        }
        return content
    }

    // MARK: - 測試連線

    /// 讀取已下載的模型清單：確認連得到、模型已下載（見 docs/specs/settings.md）。
    func testConnection() async -> String {
        guard let url = endpoint("/api/tags") else {
            return "Ollama 位址不正確：\(host):\(port)"
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            return Self.connectionResult(data, model: model)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return "Ollama 沒有啟動"
        } catch let error as URLError where error.code == .timedOut {
            return "Ollama 超過 10 秒沒有回應"
        } catch {
            return "Ollama：\(error.localizedDescription)"
        }
    }

    private struct Tags: Decodable {
        struct Model: Decodable {
            let name: String
        }

        let models: [Model]
    }

    /// 測試連線的回應：清單裡有這個模型就成功。沒寫標籤的模型名稱，Ollama 會補上 `:latest`。
    static func connectionResult(_ data: Data, model: String) -> String {
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else {
            return "Ollama 回應格式不符"
        }
        let names = Set(tags.models.map(\.name))
        return names.contains(model) || names.contains("\(model):latest") ? "連線成功" : "Ollama 沒有下載模型 \(model)"
    }

    /// 印出提示詞、請求、回應、耗時與 token 用量。
    private static func printExchange(_ stage: String, _ instructions: String, _ request: String, _ content: String, _ reply: Reply, _ elapsed: Duration) {
        let seconds = elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
        let tokens = "prompt \(reply.prompt_eval_count.map(String.init) ?? "?")　output \(reply.eval_count.map(String.init) ?? "?")"
        print("""
            ==================== [Ollama \(stage)] \(seconds)　tokens \(tokens)
            \(instructions)
            ----
            \(request)
            ----
            \(content)
            ====================
            """)
    }
}
