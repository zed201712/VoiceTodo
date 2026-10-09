//
//  InfrastructureTests.swift
//  voicecalenderTests
//

import Foundation
import Testing
@testable import voice_todo

@MainActor
struct OllamaAITests {

    @Test func 輸出結構涵蓋每種指令() throws {
        let actions = JudgePrompt.commandSchemas.map { schema in
            ((schema["properties"] as? [String: Any])?["action"] as? [String: String])?["const"]
        }
        #expect(actions == Command.Action.allCases.map(\.rawValue))
        #expect(JudgePrompt.commandSchemas.allSatisfy(JSONSerialization.isValidJSONObject))
    }

    @Test func 解析器能讀Ollama的真實輸出() throws {
        // 2026-09-30 gemma4:e4b 對「下週五新增開會」的回應。
        let json = #"{"commands": [{"action": "新增待辦", "date": "下週週五", "content": "開會"}]}"#
        #expect(try CommandJSON.decode(json) == [Command(.addTodo, date: "下週週五", content: "開會")])
    }
}

struct GeminiAITests {

    /// 每個物件的欄位都有排進 propertyOrdering；新增欄位時要一起加進 GeminiAI.propertyOrder。
    @Test func 每個欄位都有固定順序() throws {
        func check(_ schema: Any) {
            if let array = schema as? [Any] { array.forEach(check) }
            guard let object = schema as? [String: Any] else { return }
            if let properties = object["properties"] as? [String: Any] {
                #expect(Set(object["propertyOrdering"] as? [String] ?? []) == Set(properties.keys))
            }
            object.values.forEach(check)
        }
        check(GeminiAI.judgeSchema)
        #expect(JSONSerialization.isValidJSONObject(GeminiAI.judgeSchema))
    }
}

@MainActor
struct ReminderSyncTests {

    private let dentist = Todo(id: 1, date: "2026-10-05", time: "15:00", content: "看牙醫")
    private let milk = Todo(id: 2, date: "2026-10-06", content: "買牛奶")

    private func date(_ text: String) -> Date {
        Calendar.current.date(from: DateComponents(
            year: Int(text.prefix(4)), month: Int(text.dropFirst(5).prefix(2)), day: Int(text.dropFirst(8).prefix(2)),
            hour: Int(text.dropFirst(11).prefix(2)) ?? 0, minute: Int(text.dropFirst(14).prefix(2)) ?? 0))!
    }

    // MARK: 到期日

    @Test func 用刪除快照重建的新一筆_日期沒變也要寫到期日() {
        // 實機發生過：刪除後 undo，重建的提醒事項沒有到期日，讀回來被當成外部變動而清空 undo。
        #expect(ReminderSync.writesDue(isNew: true, before: milk, after: milk))
        #expect(ReminderSync.writesDue(isNew: true, before: nil, after: milk))
    }

    @Test func 已經存在的_只在日期或時間改變時寫到期日() {
        var renamed = milk
        renamed.content = "買鮮奶"
        #expect(!ReminderSync.writesDue(isNew: false, before: milk, after: renamed))
        var moved = milk
        moved.date = "2026-10-07"
        #expect(ReminderSync.writesDue(isNew: false, before: milk, after: moved))
    }

    // MARK: 差異

    @Test func 依id找出新增_修改_刪除_沒變的不寫() {
        var changed = milk
        changed.isDone = true
        let added = Todo(id: 3, content: "買牙膏")
        let changes = ReminderSync.changes(from: [dentist, milk], to: [changed, added])
        #expect(changes.added == [added])
        #expect(changes.updated == [ReminderSync.Update(before: milk, after: changed)])
        #expect(changes.removed == [dentist])
        #expect(ReminderSync.changes(from: [dentist, milk], to: [milk, dentist]).isEmpty)
    }

    @Test func 被刪的id又出現是新增() {
        let changes = ReminderSync.changes(from: [milk], to: [milk, dentist])
        #expect(changes.added == [dentist])
    }

    // MARK: 提醒事項與待辦

    @Test func 到期日只有日期_有時間_沒有到期日() {
        let day = ReminderSync.todo(id: 1, title: " 看牙醫 ", due: DateComponents(year: 2026, month: 10, day: 5), isCompleted: false)
        #expect(day == Todo(id: 1, date: "2026-10-05", content: "看牙醫"))
        let timed = ReminderSync.todo(id: 2, title: "開會", due: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 30), isCompleted: true)
        #expect(timed == Todo(id: 2, date: "2026-10-05", time: "09:30", content: "開會", isDone: true))
        let undated = ReminderSync.todo(id: 3, title: "買牙膏", due: nil, isCompleted: false)
        #expect(undated == Todo(id: 3, content: "買牙膏"))
        #expect(ReminderSync.todo(id: 4, title: "繳費", due: DateComponents(hour: 9), isCompleted: false)?.date == nil)
    }

    @Test func 標題空白不讀() {
        #expect(ReminderSync.todo(id: 1, title: "  ", due: nil, isCompleted: false) == nil)
        #expect(ReminderSync.todo(id: 1, title: nil, due: nil, isCompleted: false) == nil)
    }

    @Test func 待辦寫成到期日再讀回相同() {
        for todo in [dentist, milk] {
            let due = ReminderSync.dueComponents(todo)
            #expect(ReminderSync.todo(id: todo.id, title: todo.content, due: due, isCompleted: false) == todo)
        }
        #expect(ReminderSync.dueComponents(Todo(id: 3, content: "買牙膏")) == nil)
    }

    // MARK: alarm

    @Test func 新增有時間加alarm_沒時間不加() {
        #expect(ReminderSync.alarms(.init(), before: nil, after: dentist).absolute == [date("2026-10-05 15:00")])
        #expect(ReminderSync.alarms(.init(), before: nil, after: milk) == .init())
    }

    @Test func 改時間時絕對alarm與開始日期平移_相對alarm不動() {
        var later = dentist
        later.time = "16:00"
        let current = ReminderSync.Alarms(absolute: [date("2026-10-05 14:30")], hasRelative: true, start: date("2026-10-05 15:00"))
        let next = ReminderSync.alarms(current, before: dentist, after: later)
        #expect(next.absolute == [date("2026-10-05 15:30")])
        #expect(next.hasRelative)
        #expect(next.start == date("2026-10-05 16:00"))
    }

    @Test func 只有日期時以天平移() {
        var moved = milk
        moved.date = "2026-10-08"
        let current = ReminderSync.Alarms(absolute: [date("2026-10-06 09:00")])
        #expect(ReminderSync.alarms(current, before: milk, after: moved).absolute == [date("2026-10-08 09:00")])
    }

    @Test func 只改內容或完成不動alarm() {
        var renamed = dentist
        renamed.content = "洗牙"
        renamed.isDone = true
        let current = ReminderSync.Alarms(absolute: [date("2026-10-05 14:30")])
        #expect(ReminderSync.alarms(current, before: dentist, after: renamed) == current)
    }

    @Test func 改完有時間但沒有alarm就補一個() {
        let undated = Todo(id: 3, content: "買牙膏")
        var dated = undated
        dated.date = "2026-10-07"
        dated.time = "18:00"
        #expect(ReminderSync.alarms(.init(), before: undated, after: dated).absolute == [date("2026-10-07 18:00")])
        // 只有相對 alarm 時不補：它本來就跟著到期日。
        #expect(ReminderSync.alarms(.init(hasRelative: true), before: undated, after: dated).absolute.isEmpty)
    }
}

struct FixedPromptTests {

    /// 測試紀錄列出的輸出結構是 JSON，不是轉換失敗時的備用文字。
    @Test func 每個實作的輸出結構都是JSON() throws {
        let ais: [any AutoAI] = [OllamaAI(model: "m", host: "localhost", port: "11434"), GeminiAI(model: "m", apiKey: { nil }), FoundationModelsAI()]
        for ai in ais {
            let extra = ((ai as? any CorrectionAI).map { [$0.correctionPrompt] } ?? []) + ((ai as? any ChatAI).map { [$0.chatPrompt] } ?? [])
            for prompt in [ai.judgePrompt, ai.confirmPrompt] + extra {
                #expect(!prompt.instructions.isEmpty)
                #expect((try? JSONSerialization.jsonObject(with: Data(prompt.schema.utf8))) != nil, "\(ai.name)：\(prompt.schema.prefix(80))")
            }
        }
    }
}

struct AIFactoryTests {

    private let settings = AISettings.initial()

    private func settings(_ choice: AIChoice?) -> AISettings {
        var chosen = settings
        chosen.set(.gemini, enabled: false)
        if let choice {
            chosen.set(choice, enabled: true)
        }
        return chosen
    }

    @Test func 開放AppleIntelligence與Gemini_用選的那個() {
        #expect(AIChoice.allCases.filter(\.isOpen) == [.foundationModels, .gemini])
        #expect(AIFactory.autoAI(for: settings(.gemini), foundationModelsUnavailable: nil, geminiKey: { "k" })?.name == "Gemini gemini-3.1-flash-lite")
        #expect(AIFactory.autoAI(for: settings(.foundationModels), foundationModelsUnavailable: nil, geminiKey: { "k" })?.name == "Foundation Models")
    }

    @Test func 沒選_選了不開放的_AppleIntelligence不能用_就沒有AI() {
        #expect(AIFactory.autoAI(for: settings(nil), foundationModelsUnavailable: nil, geminiKey: { "k" }) == nil)
        #expect(AIFactory.autoAI(for: settings(.ollama), foundationModelsUnavailable: nil, geminiKey: { "k" }) == nil)
        #expect(AIFactory.autoAI(for: settings(.foundationModels), foundationModelsUnavailable: "模型還沒準備好", geminiKey: { "k" }) == nil)
    }

    @Test func Gemini沒有key就沒有AI() {
        #expect(AIFactory.autoAI(for: settings, foundationModelsUnavailable: nil, geminiKey: { nil }) == nil)
        #expect(AIFactory.autoAI(for: settings, foundationModelsUnavailable: nil, geminiKey: { "" }) == nil)
    }
}

struct FoundationModelsAITests {

    @Test func 不校正_不聊天() {
        let ai: any AutoAI = FoundationModelsAI()
        #expect(!(ai is any CorrectionAI))
        #expect(!(ai is any ChatAI))
    }
}

struct ConnectionTests {

    @Test func Gemini沒有key() async {
        let ai = GeminiAI(model: "gemini-3.1-flash-lite", apiKey: { nil })
        #expect(ai.status == "未設定 Gemini API key，請到設定填入")
        await #expect(throws: AutoAIError.self) { try await ai.judge("嗯") }
        #expect(await ai.testConnection() == "未設定 Gemini API key，請到設定填入")
        await #expect(throws: AutoAIError.self) { try await ai.correct("使用者說：嗯") }
        await #expect(throws: AutoAIError.self) { try await ai.chat("使用者說：嗯") }
    }

    @Test func Gemini的回應判讀() {
        #expect(GeminiAI.connectionResult(Data(#"{"name": "models/gemini-3.1-flash-lite"}"#.utf8)) == "連線成功")
        let invalid = #"{"error": {"code": 400, "message": "API key not valid.", "status": "INVALID_ARGUMENT"}}"#
        #expect(GeminiAI.connectionResult(Data(invalid.utf8)) == "Gemini：API key not valid.")
        #expect(GeminiAI.connectionResult(Data("<html>".utf8)) == "Gemini 回應格式不符")
    }

    @Test func Ollama的回應判讀() {
        let tags = Data(#"{"models": [{"name": "gemma4:e2b"}, {"name": "qwen3:latest"}]}"#.utf8)
        #expect(OllamaAI.connectionResult(tags, model: "gemma4:e2b") == "連線成功")
        #expect(OllamaAI.connectionResult(tags, model: "qwen3") == "連線成功")
        #expect(OllamaAI.connectionResult(tags, model: "gemma4:e4b") == "Ollama 沒有下載模型 gemma4:e4b")
    }

    @Test func Ollama的位址() {
        #expect(OllamaAI(model: "m", host: "192.168.1.5", port: "11434").status == "端點：192.168.1.5:11434")
    }
}

// MARK: - 天氣服務

struct OpenMeteoWeatherTests {

    @Test func 標示有兩個連結並註明經過整理() {
        // CC BY 4.0：連到 Open-Meteo、連到授權、註明有改動（見 docs/specs/weather.md 的「標示」）。
        #expect(OpenMeteoWeather.credit.contains("](https://open-meteo.com/)"))
        #expect(OpenMeteoWeather.credit.contains("](https://creativecommons.org/licenses/by/4.0/)"))
        #expect(OpenMeteoWeather.credit.contains("經過整理"))
    }

    @Test func 地名資料的標示有條款連結並註明經過簡化() {
        // 政府資料開放授權條款：提供機關、年份、資料名稱、依條款釋出與條款連結（見 docs/specs/weather.md 的「標示」）。
        #expect(TownBoundaries.credit.contains("內政部國土測繪中心 2025 鄉鎮市區界線（1140318 版）"))
        #expect(TownBoundaries.credit.contains("](https://data.gov.tw/license)"))
        #expect(TownBoundaries.credit.contains("經過簡化"))
    }

    @Test func 內建的鄉鎮市區邊界() {
        let towns = TownBoundaries.load()
        #expect(towns.towns.count == 368)
        #expect(towns.name(latitude: 25.0340, longitude: 121.5645) == "臺北市信義區")
        #expect(towns.name(latitude: 22.6273, longitude: 120.3014) == "高雄市前金區")
        #expect(towns.name(latitude: 35.68, longitude: 139.76) == nil)
    }

    @Test func 解析每日預報_null的那天不列() throws {
        let json = #"{"daily": {"time": ["2026-10-06", "2026-10-07"], "weather_code": [61, null], "temperature_2m_max": [25.4, 26], "temperature_2m_min": [18.2, 19], "precipitation_probability_max": [80, 10]}}"#
        #expect(try OpenMeteoWeather.decodeDaily(Data(json.utf8)) == [.init(day: "2026-10-06", code: 61, low: 18.2, high: 25.4, rainChance: 80)])
    }

    @Test func 解析逐小時預報_降雨機率null當成0() throws {
        let json = #"{"hourly": {"time": ["2026-10-06T13:00", "2026-10-06T14:00"], "weather_code": [3, 2], "temperature_2m": [23.1, null], "precipitation_probability": [null, 5]}}"#
        #expect(try OpenMeteoWeather.decodeHourly(Data(json.utf8)) == [.init(day: "2026-10-06", time: "13:00", code: 3, temperature: 23.1, rainChance: 0)])
    }
}
