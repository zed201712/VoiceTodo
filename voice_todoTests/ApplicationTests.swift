//
//  ApplicationTests.swift
//  voicecalenderTests
//

import Foundation
import Testing
@testable import voice_todo

/// 測試待辦，再加上今天的這幾件（沒有時間）。
func testTodos(addingToday contents: [String]) -> [Todo] {
    let base = TestTodos.make()
    let next = (base.map(\.id).max() ?? 0) + 1
    return base + contents.enumerated().map { Todo(id: next + $0.offset, date: TodoStore.dayString(.now), content: $0.element) }
}

/// 黑板顯示全部、勾選「完成」的待辦清單，和移動黑板的效果相同（加入導覽紀錄）。
func everythingList(todos: [Todo]? = nil) -> TodoList {
    let list = TodoList(todos: todos, showDone: true)
    _ = list.navigate(.showEverything)
    return list
}

// MARK: - JSON

@MainActor
struct CommandJSONTests {

    @Test(arguments: [
        Command(.queryDate, date: "下週週五"),
        Command(.queryTodos, date: "下個月"),
        Command(.queryTodos),
        Command(.addTodo, date: "明天", content: "買水果"),
        Command(.setDone, keyword: "買牛奶", isDone: true),
        Command(.modifyTodo, date: "明天", keyword: "部門會議", content: "部門週會", newDate: "下週週一"),
        Command(.deleteTodos, date: "下次", keyword: "買牛奶"),
        Command(.queryTodos, date: "12月10日~1月10日"),
        Command(.queryTodos, date: "11月"),
        Command(.unknown),
        Command(.setDisplay, showDone: false),
        Command(.deleteTodos, number: "3~10"),
        Command(.modifyTodo, number: "2", newDate: "明天"),
        Command(.setDone, number: "5", isDone: true),
        Command(.queryTodos, date: "12月10日~1月10日"),
        Command(.queryTodos, date: "11月"),
        Command(.readAll),
        Command(.weather, date: "明天下午", place: "台北"),
        Command(.weather),
    ])
    func 轉成JSON再解析回來不變(command: Command) throws {
        #expect(try CommandJSON.decode(CommandJSON.encode([command])) == [command])
    }

    @Test(arguments: [
        ("復原", Command.Action.undo), ("重做", .redo), ("上一頁", .previousPage), ("下一頁", .nextPage),
        ("顯示全部", .showEverything), ("全部念完", .readAll),
    ])
    func 沒有欄位的執行器可以解析(name: String, action: Command.Action) throws {
        #expect(try CommandJSON.decode(#"{"commands": [{"action": "\#(name)"}]}"#) == [Command(action)])
    }

    @Test func 修改的新內容用newContent() throws {
        let json = CommandJSON.encode([Command(.modifyTodo, keyword: "部門會議", content: "部門週會")])
        #expect(json.contains("\"newContent\":\"部門週會\""))
        #expect(!json.contains("\"content\""))
    }

    @Test func 多條指令依序() throws {
        let json = """
            {"commands": [
              {"action": "新增待辦", "date": "明天", "content": "買水果"},
              {"action": "刪除待辦", "date": "下次", "keyword": "買牛奶"}
            ]}
            """
        #expect(try CommandJSON.decode(json) == [
            Command(.addTodo, date: "明天", content: "買水果"),
            Command(.deleteTodos, date: "下次", keyword: "買牛奶"),
        ])
    }

    @Test func 空清單() throws {
        #expect(try CommandJSON.decode(#"{"commands": []}"#).isEmpty)
    }

    @Test func 簡體字先轉成繁體() throws {
        let json = #"{"commands": [{"action": "删除待办", "date": "下个月", "keyword": "买水果"}]}"#
        #expect(try CommandJSON.decode(json) == [Command(.deleteTodos, date: "下個月", keyword: "買水果")])
    }

    @Test(arguments: [
        ("下週一", "下週週一"), ("10月1號", "10月1日"), ("後天下午兩點", "後天下午2點"), ("下禮拜三", "下週週三"),
        ("下個月15日下午3點半", "下個月15日下午3點30分"), ("明天", "明天"), ("1月2日~2月5日", "1月2日~2月5日"),
    ])
    func AI的日期套上說法改寫(raw: String, expected: String) throws {
        let json = #"{"commands": [{"action": "修改待辦", "date": "\#(raw)", "keyword": "買牛奶", "newDate": "\#(raw)"}]}"#
        let command = try #require(try CommandJSON.decode(json).first)
        #expect(command.date == expected)
        #expect(command.newDate == expected)
    }

    @Test(arguments: [("第一項", "1"), ("第3項", "3"), ("第3到5項", "3~5")])
    func keyword是編號就改成number(keyword: String, number: String) throws {
        let json = #"{"commands": [{"action": "設定完成", "keyword": "\#(keyword)", "isDone": true}]}"#
        #expect(try CommandJSON.decode(json) == [Command(.setDone, number: number, isDone: true)])
    }

    @Test(arguments: [
        ("下個月15日", "下午3點半看牙醫", "下個月15日下午3點30分", "看牙醫"),
        ("明天", "9點開會", "明天9點", "開會"),
        ("明天", "下午茶", "明天", "下午茶"),
        ("明天下午3點", "4點開會", "明天下午3點", "4點開會"),
    ])
    func 新增的content開頭是時刻就移到date(date: String, content: String, newDate: String, newContent: String) throws {
        let json = #"{"commands": [{"action": "新增待辦", "date": "\#(date)", "content": "\#(content)"}]}"#
        #expect(try CommandJSON.decode(json) == [Command(.addTodo, date: newDate, content: newContent)])
    }

    @Test func 空字串視為沒給不認得的欄位忽略() throws {
        let json = #"{"commands": [{"action": "查詢待辦", "date": "下週", "keyword": "會議", "reason": "x"}]}"#
        #expect(try CommandJSON.decode(json) == [Command(.queryTodos, date: "下週", keyword: "會議")])
    }

    @Test func 看不懂的日期保留下來由執行時放棄() throws {
        let commands = try CommandJSON.decode(#"{"commands": [{"action": "新增待辦", "date": "某天", "content": "買水果"}]}"#)
        #expect(commands == [Command(.addTodo, date: "某天", content: "買水果")])
        guard case .abandon = CommandExecutor(store: TodoStore(), board: Board(today: .now), today: .now).execute(commands[0]) else {
            Issue.record("應該放棄")
            return
        }
    }

    @Test(arguments: [
        "明天買水果",
        #"```json {"commands": []} ```"#,
        #"{"cmds": []}"#,
        #"{"commands": [{"action": "買東西"}]}"#,
        #"{"commands": [{"action": "設定完成", "keyword": "買牛奶", "isDone": "true"}]}"#,
        #"{"commands": [{"action": "查詢待辦", "date": {"specificDay": "明天"}}]}"#,
    ])
    func 不合法就失敗(json: String) {
        #expect(throws: CommandJSON.Invalid.self) { try CommandJSON.decode(json) }
    }

    @Test func 刪除確認的回答() throws {
        #expect(try CommandJSON.decodeAnswer(CommandJSON.encodeAnswer(.yes)) == .yes)
        #expect(try CommandJSON.decodeAnswer(#"{"answer": "no"}"#) == .no)
        #expect(try CommandJSON.decodeAnswer(#"{"answer": "other"}"#) == .other)
        #expect(throws: CommandJSON.Invalid.self) { try CommandJSON.decodeAnswer(#"{"answer": "好"}"#) }
        #expect(throws: CommandJSON.Invalid.self) { try CommandJSON.decodeAnswer("yes") }
    }
}

// MARK: - 手動 AI

@MainActor
struct ManualAITests {

    /// 黑板顯示全部的待辦：這些測試在全部的測試待辦裡找目標。
    private func makeElf() -> Elf {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)), todoList: everythingList())
        elf.useAutoAI = false
        return elf
    }

    /// 等處理佇列的 Task 跑到條件成立。
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 測試輸入去掉空白行每行一句() {
        #expect(Elf.sentences(in: "明天有什麼預定行程\n\n  \n 下個月有什麼事 \n") == ["明天有什麼預定行程", "下個月有什麼事"])
    }

    @Test func 多行各自是一句話依序處理() async {
        let elf = makeElf()
        elf.submitTestInput("明天有什麼預定行程\n下個月有什麼節目")
        await until { elf.manualRequest != nil }
        #expect(elf.manualRequest == .init(kind: "一般判斷", text: "明天有什麼預定行程"))
        #expect(elf.processingSentence?.text == "明天有什麼預定行程")
        #expect(elf.pending.map(\.text) == ["下個月有什麼節目"])

        elf.submitManualResponse(#"{"commands": [{"action": "查詢待辦", "date": "明天"}]}"#)
        await until { elf.manualRequest?.text == "下個月有什麼節目" }
        #expect(elf.pending.map(\.text) == ["下個月有什麼節目"])

        elf.submitManualResponse(#"{"commands": []}"#)
        await until { elf.isIdle }
        #expect(elf.elfMessage == "聽不懂「下個月有什麼節目」")
        #expect(elf.testLog.contains { $0.line == "[#1 輸入] 文字：明天有什麼預定行程" })
        #expect(elf.testLog.contains { $0.line == "[#2 輸入] 文字：下個月有什麼節目" })
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#1 指令 1/1] 查詢待辦（明天） → 完成") })
    }

    @Test func 回應不合法就進入錯誤確認() async {
        let elf = makeElf()
        elf.submitTestInput("新增明天買水果\n嗯")
        await until { elf.manualRequest != nil }
        let count = elf.todos.count

        elf.submitManualResponse("新增待辦")
        await until { elf.canRetry && elf.manualRequest != nil }
        // 背景照樣解讀後面的話，但結果不出現。
        #expect(elf.manualRequest?.text == "嗯")
        #expect(elf.pending.map(\.text) == ["嗯"])
        #expect(elf.todos.count == count)
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#1 判斷] 手動 AI 回應無法解析") })
    }

    @Test func 釐清後判斷失敗後重試_送出的請求相同() async {
        let elf = makeElf()
        elf.submitTestInput("部門會議完成了")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "設定完成", "keyword": "部門會議", "isDone": true}]}"#)
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("下個月那個")
        await until { elf.manualRequest?.kind == "釐清後判斷" }
        let request = elf.manualRequest

        elf.submitManualResponse("壞掉")
        await until { elf.canRetry }
        elf.retry()
        await until { elf.manualRequest != nil }
        #expect(elf.manualRequest == request)
    }

    @Test func 等刪除確認時說復原當成回答() async {
        let elf = makeElf()
        elf.submitTestInput("刪除所有買牛奶")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("復原")
        await until { elf.manualRequest?.kind == "刪除確認" }
        #expect(!elf.canUndo)
        #expect(elf.manualRequest?.text.hasSuffix("\n回答：復原") == true)
    }

    @Test func 沒在等時貼的JSON不處理() {
        let elf = makeElf()
        elf.submitManualResponse(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
        #expect(elf.elfMessage == "目前沒有等待手動 AI")
        #expect(elf.todos.count == 8)
    }

    @Test func 刪除確認交給手動AI() async {
        let elf = makeElf()
        elf.submitTestInput("刪除所有買牛奶")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("好啊刪吧")
        await until { elf.manualRequest?.kind == "刪除確認" }
        #expect(elf.manualRequest?.text.hasSuffix("\n回答：好啊刪吧") == true)

        elf.submitManualResponse(#"{"answer": "yes"}"#)
        await until { elf.isIdle }
        #expect(!elf.todos.contains { $0.content == "買牛奶" })
    }

    @Test func 刪除確認回應不合法當成no() async {
        let elf = makeElf()
        elf.submitTestInput("刪除所有買牛奶")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("好啊刪吧")
        await until { elf.manualRequest?.kind == "刪除確認" }

        elf.submitManualResponse("yes")
        await until { elf.isIdle }
        #expect(elf.todos.count { $0.content == "買牛奶" } == 2)
    }

    @Test func 刪除確認時指定其中一項就縮小範圍再確認() async {
        let elf = makeElf()
        elf.submitTestInput("刪除所有買牛奶")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("只刪第一個")
        await until { elf.manualRequest?.kind == "刪除確認" }

        elf.submitManualResponse(#"{"answer": "other"}"#)
        await until { elf.manualRequest?.kind == "釐清後判斷" }
        let request = elf.manualRequest?.text ?? ""
        #expect(request.hasPrefix("小精靈剛才問：即將刪除買牛奶（2 項）"))
        #expect(request.hasSuffix("這 2 項都要刪掉嗎？\n原本的指令：刪除待辦（買牛奶）\n使用者說：只刪第一個"))

        let first = try! TodoStore.dayFormat.parse(elf.todos.filter { $0.content == "買牛奶" }.compactMap(\.date).min()!)
        let day = "\(DatePhrase.calendar.component(.month, from: first))月\(DatePhrase.calendar.component(.day, from: first))日"
        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "date": "\#(day)", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle }
        #expect(elf.todos.count { $0.content == "買牛奶" } == 2)
        #expect(elf.waitingText.contains("（1 項）"))
        #expect(!elf.testLog.contains { $0.text.contains("已取消刪除") })
    }

    @Test func 重新開始清空一切_不改待辦() async {
        let elf = makeElf()
        elf.submitTestInput("明天要買水果\n嗯")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
        await until { elf.manualRequest?.text == "嗯" }
        #expect(elf.todos.count == 9)

        elf.restart()
        #expect(elf.manualRequest == nil)
        #expect(elf.isIdle)
        #expect(elf.todos.count == 9)
        #expect(!elf.canUndo)
        // 重新開始後的第一筆紀錄，接著印出整個黑板。
        #expect(elf.testLog.map(\.stage).dropFirst() == ["黑板"])

        elf.submitTestInput("下週有什麼節目")
        await until { elf.manualRequest != nil }
        #expect(elf.manualRequest?.text == "下週有什麼節目")
        #expect(elf.processingSentence?.number == 1)
        #expect(elf.pending.isEmpty)
    }
}

// MARK: - 自動 AI

/// 假的自動 AI：判斷回傳固定的結果，不呼叫模型。
struct FakeAI: AutoAI {
    let name = "假的 AI"
    let status = ""
    let judgment: Result<String, AutoAIError>
    let judgePrompt = FixedPrompt(instructions: "假的判斷指示", schema: #"{"type": "object"}"#)
    let confirmPrompt = FixedPrompt(instructions: "假的確認指示", schema: #"{"enum": ["yes", "no"]}"#)

    func judge(_ request: String) async throws -> String {
        try judgment.get()
    }

    func confirmDelete(_ request: String) async throws -> String {
        #"{"answer": "no"}"#
    }
}

@MainActor
struct AutoAITests {

    /// 等處理佇列的 Task 跑到條件成立。
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 判斷後依序執行() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        #expect(elf.todos.count == 9)
        #expect(elf.testLogText.hasPrefix("測試紀錄") && elf.testLogText.contains("AI：自動（假的 AI）"))
    }

    @Test func 準備好的紀錄有耗時_規則判斷命中也有() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)))
        elf.submitTestInput("明天要買水果\n顯示全部")
        await until { elf.isIdle && elf.pending.isEmpty }
        let ready = elf.testLog.filter { $0.stage == "準備好" }.map(\.line)
        #expect(ready.count == 2)
        #expect(ready.allSatisfy { $0.contains("] 耗時 ") && $0.contains(" sec：") })
    }

    @Test func 下一句話的編號對到前一句改完後的黑板() async {
        let list = TodoList()
        _ = list.navigate(.showEverything)
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)), todoList: list)
        let second = elf.visibleTodos()[1]
        elf.submitTestInput("第1項移到12月31日\n完成第1項")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(elf.todos.first { $0.id == second.id }?.isDone == true)
    }

    @Test func 測試紀錄預設不附固定提示詞() {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        #expect(!elf.testLogText.contains("固定提示詞"))
    }

    @Test func 黑板內容變了就印出整個黑板_帶編號() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let board = elf.testLog.last { $0.stage == "黑板" && $0.sentence == 1 }
        #expect(board?.text.contains { $0.isNewline } == true)
        #expect(board?.text.split(separator: "\n").contains { $0.first?.isNumber == true && $0.contains(". ☐ ") && $0.hasSuffix("買水果") } == true)
    }

    @Test func 黑板內容沒變就不印() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        let before = elf.testLog.filter { $0.stage == "黑板" }.count
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(elf.testLog.filter { $0.stage == "黑板" }.count == before)
    }

    @Test func 測試紀錄開頭定義固定提示詞_請求只寫名稱() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        elf.includesPrompts = true
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        let text = elf.testLogText
        #expect(text.contains("固定提示詞「判斷提示詞」：\n假的判斷指示\n輸出結構：\n{\"type\": \"object\"}"))
        #expect(text.contains("固定提示詞「刪除確認提示詞」：\n假的確認指示\n輸出結構：\n{\"enum\": [\"yes\", \"no\"]}"))
        #expect(text.contains("[#1 判斷] 自動 AI｜一般判斷｜判斷提示詞"))
        #expect(!elf.testLog.contains { $0.text.contains("假的判斷指示") })
    }

    @Test func 失敗時進入錯誤確認並回報實作提供的原因() async {
        let elf = Elf(autoAI: FakeAI(judgment: .failure(AutoAIError("模型沒有啟動"))))
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        #expect(elf.todos.count == 8)
        #expect(elf.elfMessage == "判斷失敗：模型沒有啟動。說『重試』再試一次，或說『略過』。")
    }
}

// MARK: - 畫面資訊

struct ScreenInfoTests {

    private func info(board: [String] = [], dialog: [String] = [], question: String? = nil) -> ScreenInfo {
        ScreenInfo(now: "2026/10/2（五）14:30", boardTitle: "", board: board, dialog: dialog, question: question)
    }

    @Test func 剛好100字不省略() {
        let units = [String(repeating: "一", count: 60), String(repeating: "二", count: 40)]
        #expect(ScreenInfo.fit(units) == (units, 0))
    }

    @Test func 超過時停在單位的邊界() {
        let units = ["甲甲甲", String(repeating: "乙", count: 98), "丙"]
        #expect(ScreenInfo.fit(units) == (["甲甲甲"], 2))
    }

    @Test func 第一個單位太長時在最後一個標點後切開() {
        let long = String(repeating: "甲", count: 50) + "，" + String(repeating: "乙", count: 60)
        #expect(ScreenInfo.fit([long, "丙"]) == ([String(repeating: "甲", count: 50) + "，"], 2))
    }

    @Test func 沒有標點時取前100字() {
        #expect(ScreenInfo.fit([String(repeating: "甲", count: 120)]) == ([String(repeating: "甲", count: 100)], 1))
    }

    @Test func 句子以句號問號驚嘆號與換行切開() {
        #expect(ScreenInfo.sentences("好。要嗎？好！\n嗯\n刪除") == ["好。", "要嗎？", "好！\n", "嗯\n", "刪除"])
    }

    @Test func 句子太長時截斷加上刪節號() {
        let text = String(repeating: "甲", count: 60) + "。" + String(repeating: "乙", count: 60) + "。"
        #expect(ScreenInfo.clip(text) == String(repeating: "甲", count: 60) + "。…")
        #expect(ScreenInfo.clip("沒事。") == "沒事。")
    }

    @Test func 請求依欄位順序_多行的欄位第一行接在名稱後面() {
        let request = ScreenInfo(now: "2026/10/2（五）14:30", boardTitle: "下週 10/5–10/11",
                                 board: ["☐ 10/5（一） 09:00 看牙醫"], dialog: ["已新增", "下一件：10/5（一）看牙醫"],
                                 question: "要刪除哪一個？").request(userSaid: "嗯")
        #expect(request == """
            現在：2026/10/2（五）14:30
            黑板：下週 10/5–10/11
            ☐ 10/5（一） 09:00 看牙醫
            小精靈說：已新增
            下一件：10/5（一）看牙醫
            小精靈剛才問：要刪除哪一個？
            使用者說：嗯
            """)
    }

    @Test func 沒有內容的欄位省略_黑板沒有待辦是無資料() {
        #expect(info().request(userSaid: "嗯") == "現在：2026/10/2（五）14:30\n黑板：無資料\n使用者說：嗯")
    }

    @Test func 黑板省略時寫出還有幾項() {
        let lines = (1...10).map { "☐ 10/\($0)（一） 09:00 部門會議第\($0)次" }
        let request = info(board: lines).request(userSaid: "嗯")
        #expect(request.contains("黑板：☐ 10/1（一） 09:00 部門會議第1次\n"))
        #expect(request.contains("\n…還有 6 項\n使用者說：嗯"))
    }

    @Test func 回話省略時加一行刪節號() {
        let lines = (1...10).map { "已新增 ☐ 10/\($0)（一） 09:00 部門會議" }
        #expect(info(dialog: lines).request(userSaid: "嗯").contains("部門會議\n…\n使用者說：嗯"))
    }

    @Test func 現在的格式() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9, minute: 5))!
        #expect(ScreenInfo.now(date) == "2026/10/2（五）09:05")
    }
}

// MARK: - 校正

struct CorrectionTests {

    @Test(arguments: [
        ("10月 6號有什麼事 ？", "10月6號有什麼事？"),
        ("買 iPhone 17", "買iPhone 17"),
        ("buy  milk", "buy  milk"),
        ("ok ?", "ok?"),
        (" 嗯 ", "嗯"),
        ("看牙醫", "看牙醫"),
    ])
    func 規則校正拿掉多餘的空白(text: String, expected: String) {
        #expect(Correction.removeSpaces(text) == expected)
    }

    @Test(arguments: [
        ("晚上 9:00跟小明吃飯。", "晚上9點跟小明吃飯。"),
        ("明天9:30開會", "明天9點30分開會"),
        ("下午3：05看牙醫", "下午3點5分看牙醫"),
        ("21:00", "21點"),
        ("比數3:2", "比數3:2"),
    ])
    func 規則校正把時刻改成幾點幾分(text: String, expected: String) {
        #expect(Correction.tool(text) == expected)
    }


    @Test func 字數相同且內容不同才採用() {
        let result = Correction.accept("10月6號面試", for: "10月6號麵是")
        #expect(result.text == "10月6號面試")
        #expect(result.note == "10月6號麵是 → 10月6號面試")
    }

    @Test func 內容相同是未修改() {
        let result = Correction.accept("看牙醫", for: "看牙醫")
        #expect(result.text == "看牙醫")
        #expect(result.note == "未修改")
    }

    @Test func 字數不同不採用() {
        let result = Correction.accept("去看牙醫", for: "看牙醫")
        #expect(result.text == "看牙醫")
        #expect(result.note == "字數不同，不採用：去看牙醫")
    }

    @Test(arguments: [
        ("幫我刪掉第1項", "幫我刪掉第2項"), ("把部門會議改到下週二", "把部門會議改到下週一"), ("10月12號面試", "10月6號麵是"),
    ])
    func 改了數字不採用(output: String, original: String) {
        let result = Correction.accept(output, for: original)
        #expect(result.text == original)
        #expect(result.note == "改了數字，不採用：\(output)")
    }

    @Test func 數字沒變的錯字照樣採用() {
        #expect(Correction.accept("將第二項改到明天", for: "降低二項改到明天").text == "將第二項改到明天")
    }

    @Test func 先去掉頭尾空白() {
        #expect(Correction.accept(" 跟小美出去玩\n", for: "跟小每出去玩").text == "跟小美出去玩")
        #expect(Correction.accept("看牙醫", for: " 看牙醫 ").note == "未修改")
    }
}

/// 有校正功能的假 AI：校正回傳固定的結果，記下每次的校正請求；判斷依序回傳排好的結果。
@MainActor
final class CorrectingAI: AutoAI, CorrectionAI {
    let name = "會校正的 AI"
    let status = ""
    let judgePrompt = FixedPrompt(instructions: "", schema: "")
    let confirmPrompt = FixedPrompt(instructions: "", schema: "")
    let correctionPrompt = FixedPrompt(instructions: "假的校正指示", schema: #"{"type": "object"}"#)
    private let correction: Result<String, AutoAIError>
    private var judgments: [Result<String, AutoAIError>]
    private(set) var correctionRequests: [String] = []

    init(_ correction: Result<String, AutoAIError>, judgments: [Result<String, AutoAIError>] = []) {
        self.correction = correction
        self.judgments = judgments
    }

    func correct(_ request: String) async throws -> String {
        correctionRequests.append(request)
        return try correction.get()
    }

    func judge(_ request: String) async throws -> String {
        judgments.isEmpty ? #"{"commands": []}"# : try judgments.removeFirst().get()
    }

    func confirmDelete(_ request: String) async throws -> String {
        #"{"answer": "no"}"#
    }
}

@MainActor
struct ElfCorrectionTests {

    private let busy = Result<String, AutoAIError>.failure(AutoAIError("忙線"))
    private let clear = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func requested(_ elf: Elf, _ text: String) -> Bool {
        elf.testLog.contains { $0.stage == "判斷" && $0.text == "請求：\(text)" }
    }

    @Test func 校正後的句子送進判斷() async {
        let elf = Elf(autoAI: CorrectingAI(.success("10月6號面試")))
        elf.submitTestInput("10月6號麵是")
        await until { elf.isIdle }
        #expect(requested(elf, "10月6號面試"))
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 10月6號麵是 → 10月6號面試" })
        #expect(elf.testLog.contains { $0.stage == "校正" && $0.text.hasPrefix("回應（") && $0.text.hasSuffix(" sec）：10月6號面試") })
        #expect(elf.correctionOutput == "10月6號麵是 → 10月6號面試")
        #expect(elf.elfMessage == "聽不懂「10月6號面試」")
    }

    @Test func 校正請求是畫面資訊() async {
        let ai = CorrectingAI(.success("跟小美出去玩"))
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["跟小美吃飯"])))
        elf.setDisplay(showDone: false)
        let message = elf.elfMessage
        elf.submitTestInput("跟小每出去玩")
        await until { elf.isIdle }
        #expect(ai.correctionRequests.count == 1)
        let request = ai.correctionRequests.first ?? ""
        #expect(request.hasPrefix("現在：\(ScreenInfo.now(.now).prefix(9))"))
        #expect(request.contains("） 跟小美吃飯\n"))
        // 開口時的回話，不是處理中的「思考中…」；便條不在畫面資訊裡。
        #expect(request.contains("小精靈說：\(message)\n"))
        #expect(!request.contains(elf.guide.text))
        #expect(!request.contains("思考中"))
        #expect(!request.contains("小精靈剛才問"))
        #expect(request.hasSuffix("使用者說：跟小每出去玩"))
        #expect(requested(elf, "跟小美出去玩"))
    }

    @Test func 釐清時校正請求附上問題() async {
        let ai = CorrectingAI(.success("嗯"), judgments: [.success(#"{"commands": [{"action": "設定完成", "keyword": "看牙醫", "isDone": true}]}"#)])
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["看牙醫", "看牙醫複診"])))
        elf.submitTestInput("看牙醫做完了")
        await until { elf.isIdle }
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        let request = ai.correctionRequests.last ?? ""
        #expect(ai.correctionRequests.count == 2)
        #expect(request.contains("\n小精靈剛才問："))
    }

    @Test func 校正採用時聽到的話換成校正後的句子() async {
        let elf = Elf(autoAI: CorrectingAI(.success("10月6號面試")))
        elf.submitTestInput("10月6號麵是")
        await until { elf.isIdle }
        #expect(requested(elf, "10月6號面試"))
        #expect(elf.processingSentence?.text == "10月6號面試")
        #expect(elf.processingSentence?.number == 1)
    }

    @Test func 校正未採用時聽到的話不變() async {
        let elf = Elf(autoAI: CorrectingAI(.success("去10月6號面試")))
        elf.submitTestInput("10月6號麵是")
        await until { elf.isIdle }
        #expect(elf.processingSentence?.text == "10月6號麵是")
    }

    @Test func 規則校正先拿掉空白_AI校正與判斷都用處理後的句子() async {
        let ai = CorrectingAI(.success("10月6號有什麼節目？"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("10月 6號有什麼節目 ？")
        await until { elf.isIdle }
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 規則：10月 6號有什麼節目 ？ → 10月6號有什麼節目？" })
        #expect(ai.correctionRequests.first?.hasSuffix("使用者說：10月6號有什麼節目？") == true)
        #expect(elf.correctionOutput == "未修改")
        #expect(requested(elf, "10月6號有什麼節目？"))
        #expect(elf.processingSentence?.text == "10月6號有什麼節目？")
    }

    @Test func 字數不同時用原句() async {
        let elf = Elf(autoAI: CorrectingAI(.success("去看牙醫")))
        elf.submitTestInput("看牙醫")
        await until { elf.isIdle }
        #expect(requested(elf, "看牙醫"))
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 字數不同，不採用：去看牙醫" })
    }

    @Test func 校正失敗時用原句_不進入錯誤確認() async {
        let elf = Elf(autoAI: CorrectingAI(.failure(AutoAIError("Gemini 忙線，請再說一次")), judgments: [clear]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        #expect(!elf.canRetry)
        #expect(elf.todos.count == 9)
        #expect(requested(elf, "明天要買水果"))
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 校正失敗，用原句：Gemini 忙線，請再說一次" })
    }

    @Test func 手動AI時不校正() async {
        let ai = CorrectingAI(.success("10月6號面試"))
        let elf = Elf(autoAI: ai)
        elf.useAutoAI = false
        elf.submitTestInput("10月6號麵是")
        await until { elf.manualRequest != nil }
        #expect(ai.correctionRequests.isEmpty)
        #expect(elf.manualRequest?.text == "10月6號麵是")
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 手動 AI，不校正" })
        elf.restart()
    }

    @Test func 沒有校正功能的AI不校正() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        elf.submitTestInput("10月6號麵是")
        await until { elf.isIdle }
        #expect(requested(elf, "10月6號麵是"))
        #expect(elf.testLog.contains { $0.line == "[#1 校正] 目前的 AI 沒有校正功能，不校正" })
    }

    @Test func 關鍵字不校正() async {
        let ai = CorrectingAI(.success("上一部。"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("上一步。")
        await until { elf.isIdle }
        #expect(ai.correctionRequests.isEmpty)
    }

    @Test func 重試沿用校正結果_不再校正() async {
        let ai = CorrectingAI(.success("明天要買水果"), judgments: [busy, clear])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        elf.retry()
        await until { elf.isIdle }
        #expect(ai.correctionRequests.count == 1)
        #expect(elf.todos.count == 9)
        #expect(elf.testLog.filter { $0.text == "請求：明天要買水果" && $0.stage == "判斷" }.count == 2)
    }

    @Test func 測試紀錄開頭定義校正提示詞() {
        let elf = Elf(autoAI: CorrectingAI(.success("")))
        elf.includesPrompts = true
        #expect(elf.testLogText.contains("固定提示詞「校正提示詞」：\n假的校正指示\n輸出結構：\n{\"type\": \"object\"}"))
    }
}

// MARK: - 校正與判斷同時進行

/// 校正與判斷都停在閘門，由測試決定哪一個先回來；判斷依請求文字回傳結果。取消時放行並丟出取消。
/// 綁在主執行緒：測試和 AI 的呼叫會同時讀寫閘門。
@MainActor
final class GatedAI: AutoAI, CorrectionAI, ChatAI {
    let name = "閘門 AI"
    let status = ""
    let judgePrompt = FixedPrompt(instructions: "", schema: "")
    let confirmPrompt = FixedPrompt(instructions: "", schema: "")
    let correctionPrompt = FixedPrompt(instructions: "", schema: "")
    let chatPrompt = FixedPrompt(instructions: "", schema: "")
    private let correction: String
    private let judgments: [String: Result<String, AutoAIError>]
    private(set) var events: [String] = []
    private(set) var chatRequests: [String] = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var opened: Set<String> = []

    init(correction: String, judgments: [String: Result<String, AutoAIError>]) {
        self.correction = correction
        self.judgments = judgments
    }

    func correct(_ request: String) async throws -> String {
        events.append("校正")
        await wait("校正")
        return correction
    }

    func judge(_ request: String) async throws -> String {
        events.append("判斷：\(request)")
        await wait(request)
        try Task.checkCancellation()
        return try (judgments[request] ?? .success(#"{"commands": []}"#)).get()
    }

    func confirmDelete(_ request: String) async throws -> String {
        #"{"answer": "no"}"#
    }

    func chat(_ request: String) async throws -> String {
        chatRequests.append(request)
        return "怎麼了嗎？"
    }

    func isWaiting(_ key: String) -> Bool {
        gates[key] != nil
    }

    func open(_ key: String) {
        opened.insert(key)
        gates.removeValue(forKey: key)?.resume()
    }

    private func wait(_ key: String) async {
        guard !opened.contains(key) else {
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { gates[key] = $0 }
        } onCancel: {
            Task { @MainActor in self.open(key) }
        }
    }
}

@MainActor
struct ParallelCorrectionTests {

    private let clear = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
    private let busy = Result<String, AutoAIError>.failure(AutoAIError("忙線"))

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 校正與原句的判斷同時開始_校正沒改就用原句的判斷() async {
        let ai = GatedAI(correction: "明天要買水果", judgments: ["明天要買水果": clear])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要買水果")
        await until { ai.isWaiting("校正") && ai.isWaiting("明天要買水果") }
        ai.open("明天要買水果")
        ai.open("校正")
        await until { elf.isIdle }
        #expect(ai.events == ["校正", "判斷：明天要買水果"])
        #expect(elf.todos.count == 9)
    }

    @Test func 原句的判斷先回來也等校正_校正改了就作廢並重判() async {
        let ai = GatedAI(correction: "明天要買水果", judgments: ["明天要賣水果": .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "賣水果"}]}"#), "明天要買水果": clear])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要賣水果")
        await until { ai.isWaiting("校正") && ai.isWaiting("明天要賣水果") }
        ai.open("明天要賣水果")
        for _ in 0..<50 { await Task.yield() }
        #expect(elf.commands.isEmpty)
        ai.open("校正")
        await until { ai.isWaiting("明天要買水果") }
        ai.open("明天要買水果")
        await until { elf.isIdle }
        #expect(ai.events == ["校正", "判斷：明天要賣水果", "判斷：明天要買水果"])
        #expect(elf.todos.count == 9)
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 校正改了句子，作廢原句的判斷，重新判斷" })
    }

    @Test func 校正先回來且改了就取消原句的判斷() async {
        let ai = GatedAI(correction: "明天要買水果", judgments: ["明天要買水果": clear])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要賣水果")
        await until { ai.isWaiting("校正") && ai.isWaiting("明天要賣水果") }
        ai.open("校正")
        await until { ai.isWaiting("明天要買水果") }
        ai.open("明天要買水果")
        await until { elf.isIdle }
        #expect(elf.todos.count == 9)
        #expect(!elf.testLog.contains { $0.text.hasPrefix("回應") && $0.text.contains("建立") })
        #expect(!elf.canRetry)
    }

    @Test func 原句的判斷失敗但校正改了_不進入錯誤確認() async {
        let ai = GatedAI(correction: "明天要買水果", judgments: ["明天要賣水果": busy, "明天要買水果": clear])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要賣水果")
        await until { ai.isWaiting("校正") && ai.isWaiting("明天要賣水果") }
        ai.open("明天要賣水果")
        ai.open("校正")
        await until { ai.isWaiting("明天要買水果") }
        ai.open("明天要買水果")
        await until { elf.isIdle }
        #expect(!elf.canRetry)
        #expect(elf.todos.count == 9)
    }

    @Test func 原句的判斷失敗且校正沒改_進入錯誤確認_重試不再校正() async {
        let ai = GatedAI(correction: "明天要買水果", judgments: ["明天要買水果": busy])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("明天要買水果")
        await until { ai.isWaiting("校正") && ai.isWaiting("明天要買水果") }
        ai.open("明天要買水果")
        ai.open("校正")
        await until { elf.canRetry }
        #expect(elf.todos.count == 8)
        elf.retry()
        await until { !elf.canRetry && elf.isIdle || elf.canRetry && ai.events.count == 3 }
        #expect(ai.events.filter { $0 == "校正" }.count == 1)
    }

    @Test func 判斷先回來且沒有指令_等校正回來才聊天() async {
        let ai = GatedAI(correction: "嗯", judgments: [:])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("嗯")
        await until { ai.isWaiting("校正") && ai.isWaiting("嗯") }
        ai.open("嗯")
        for _ in 0..<50 { await Task.yield() }
        #expect(ai.chatRequests.isEmpty)
        ai.open("校正")
        await until { elf.isIdle }
        #expect(ai.chatRequests.count == 1)
        #expect(elf.elfMessage == "怎麼了嗎？")
    }

    @Test func 校正改了句子_重判後沒有指令才聊天_用採用的句子() async {
        let ai = GatedAI(correction: "恩", judgments: [:])
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("嗯")
        await until { ai.isWaiting("校正") && ai.isWaiting("嗯") }
        ai.open("嗯")
        ai.open("校正")
        await until { ai.isWaiting("恩") }
        #expect(ai.chatRequests.isEmpty)
        ai.open("恩")
        await until { elf.isIdle }
        #expect(ai.chatRequests.count == 1)
        #expect(ai.chatRequests.first?.hasSuffix("使用者說：恩") == true)
    }

    @Test func 釐清後判斷也同時開始() async {
        let ai = GatedAI(correction: "第一筆", judgments: ["看牙醫做完了": .success(#"{"commands": [{"action": "設定完成", "keyword": "看牙醫", "isDone": true}]}"#)])
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["看牙醫", "看牙醫複診"])))
        elf.submitTestInput("看牙醫做完了")
        await until { ai.isWaiting("校正") && ai.isWaiting("看牙醫做完了") }
        ai.open("校正")
        ai.open("看牙醫做完了")
        await until { elf.isIdle }
        let clarified = "小精靈剛才問："
        elf.submitTestInput("第一筆")
        await until { ai.events.count == 4 }
        #expect(ai.events[2] == "校正")
        #expect(ai.events[3].hasPrefix("判斷：\(clarified)"))
        elf.restart()
    }
}

// MARK: - 規則判斷

@MainActor
struct ElfJudgeToolTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func judged(_ elf: Elf) -> Int {
        elf.testLog.filter { $0.stage == "判斷" && $0.text.hasPrefix("請求：") }.count
    }

    @Test func 一般判斷命中_不呼叫校正與判斷AI() async {
        let ai = CorrectingAI(.success("顯示完成"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("顯示完成")
        await until { elf.isIdle }
        #expect(elf.showDone)
        #expect(ai.correctionRequests.isEmpty)
        #expect(judged(elf) == 0)
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 規則：設定顯示（完成顯示）" })
        #expect(elf.correctionOutput == "規則判斷，不校正")
    }

    @Test func 釐清中命中_原本的任務取消_執行新指令() async {
        let ai = CorrectingAI(.success("看牙醫做完了"), judgments: [.success(#"{"commands": [{"action": "設定完成", "keyword": "看牙醫", "isDone": true}]}"#)])
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["看牙醫", "看牙醫複診"])))
        elf.submitTestInput("看牙醫做完了")
        await until { elf.isIdle }
        elf.submitTestInput("顯示完成")
        await until { elf.isIdle }
        #expect(elf.showDone)
        #expect(ai.correctionRequests.count == 1)
        #expect(judged(elf) == 1)
        #expect(elf.todos.allSatisfy { !$0.isDone })
        #expect(elf.canUndo == false)
    }

    @Test func 刪除確認中命中_原本的刪除取消_執行新指令() async {
        let ai = CorrectingAI(.success("刪除看眼科"), judgments: [.success(#"{"commands": [{"action": "刪除待辦", "keyword": "看眼科"}]}"#)])
        // 測試待辦沒有的內容：刪除目標只有這一項，不受今天是幾號影響。
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["看眼科"])))
        elf.submitTestInput("刪除看眼科")
        await until { elf.isIdle }
        #expect(elf.elfMessage.contains("要刪掉嗎？"))
        elf.submitTestInput("顯示完成")
        await until { elf.isIdle }
        #expect(elf.showDone)
        #expect(elf.todos.contains { $0.content == "看眼科" })
        #expect(!elf.elfMessage.contains("要刪掉嗎？"))
    }

    @Test func 校正改了句子_先用規則判斷再重判() async {
        let ai = CorrectingAI(.success("顯示完成"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("顯式完成")
        await until { elf.isIdle }
        #expect(elf.showDone)
        // 校正後的句子沒有送 AI 判斷（用原句的判斷何時記下請求取決於時序，不檢查）。
        #expect(!elf.testLog.contains { $0.stage == "判斷" && $0.text == "請求：顯示完成" })
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 規則：設定顯示（完成顯示）" })
        #expect(elf.correctionOutput == "顯式完成 → 顯示完成")
    }

    @Test func 手動AI時命中_不出現AI請求() async {
        let elf = Elf(autoAI: CorrectingAI(.success("")))
        elf.useAutoAI = false
        elf.submitTestInput("顯示完成")
        await until { elf.isIdle }
        #expect(elf.manualRequest == nil)
        #expect(elf.showDone)
    }
}

// MARK: - 聊天

/// 有聊天功能的假 AI：判斷依序回傳排好的結果（用完是空清單），聊天回傳固定的結果並記下請求。
@MainActor
final class ChattingAI: AutoAI, ChatAI {
    let name = "會聊天的 AI"
    let status = ""
    let judgePrompt = FixedPrompt(instructions: "", schema: "")
    let confirmPrompt = FixedPrompt(instructions: "", schema: "")
    let chatPrompt = FixedPrompt(instructions: "假的聊天指示", schema: #"{"type": "object"}"#)
    private let reply: Result<String, AutoAIError>
    private var judgments: [Result<String, AutoAIError>]
    private(set) var chatRequests: [String] = []

    init(_ reply: Result<String, AutoAIError>, judgments: [Result<String, AutoAIError>] = []) {
        self.reply = reply
        self.judgments = judgments
    }

    func chat(_ request: String) async throws -> String {
        chatRequests.append(request)
        return try reply.get()
    }

    func judge(_ request: String) async throws -> String {
        judgments.isEmpty ? #"{"commands": []}"# : try judgments.removeFirst().get()
    }

    func confirmDelete(_ request: String) async throws -> String {
        #"{"answer": "no"}"#
    }
}

@MainActor
struct ElfChatTests {

    private let weather = "這個 App 沒有提供天氣資訊。不過希望今天是個好天氣！"

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 聽不懂時聊天_請求是畫面資訊_回應顯示並念出() async {
        let speaker = FakeSpeaker()
        let ai = ChattingAI(.success(weather), judgments: [.success(#"{"commands": [{"action": "聽不懂"}]}"#)])
        let elf = Elf(autoAI: ai, speaker: speaker)
        elf.setDisplay(showDone: false)
        let message = elf.elfMessage
        elf.submitTestInput("今天天氣如何")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(ai.chatRequests.count == 1)
        #expect(ai.chatRequests.first?.hasPrefix("現在：") == true)
        #expect(ai.chatRequests.first?.contains("小精靈說：\(message)\n") == true)
        #expect(ai.chatRequests.first?.hasSuffix("使用者說：今天天氣如何") == true)
        #expect(elf.elfMessage == weather)
        #expect(elf.mood == .done)
        #expect(speaker.spoken == [weather])
        #expect(elf.testLog.contains { $0.line == "[#1 聊天] \(weather)" })
        #expect(elf.todos.count == 8)
        #expect(!elf.canUndo)
    }

    @Test func 空清單也聊天() async {
        let ai = ChattingAI(.success("怎麼了嗎？"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(elf.elfMessage == "怎麼了嗎？")
    }

    @Test func 釐清後判斷沒有指令時不聊天() async {
        let ai = ChattingAI(.success("怎麼了嗎？"), judgments: [.success(#"{"commands": [{"action": "設定完成", "keyword": "看牙醫", "isDone": true}]}"#)])
        let elf = Elf(autoAI: ai, todoList: TodoList(todos: testTodos(addingToday: ["看牙醫", "看牙醫複診"])))
        elf.submitTestInput("看牙醫做完了")
        await until { elf.isIdle }
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(ai.chatRequests.isEmpty)
        #expect(elf.elfMessage != "怎麼了嗎？")
    }

    @Test(arguments: [
        (Result<String, AutoAIError>.failure(AutoAIError("Gemini 忙線，請再說一次")), "聊天失敗：Gemini 忙線，請再說一次"),
        (.success("  "), "聊天的回應是空的"),
    ])
    func 聊天失敗時退回聽不懂_不進入錯誤確認_不念(reply: Result<String, AutoAIError>, note: String) async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ChattingAI(reply), speaker: speaker)
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(elf.elfMessage == "聽不懂「嗯」")
        #expect(elf.mood == .confused)
        #expect(!elf.canRetry)
        #expect(speaker.spoken.isEmpty)
        #expect(elf.testLog.contains { $0.line == "[#1 聊天] \(note)" })
    }

    @Test func 沒有聊天功能的AI退回聽不懂() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(elf.elfMessage == "聽不懂「嗯」")
        #expect(elf.testLog.contains { $0.line == "[#1 聊天] 目前的 AI 沒有聊天功能" })
    }

    @Test func 手動AI時不聊天() async {
        let ai = ChattingAI(.success("怎麼了嗎？"))
        let elf = Elf(autoAI: ai)
        elf.useAutoAI = false
        elf.submitTestInput("嗯")
        await until { elf.manualRequest != nil }
        elf.submitManualResponse(#"{"commands": []}"#)
        await until { elf.isIdle }
        #expect(ai.chatRequests.isEmpty)
        #expect(elf.elfMessage == "聽不懂「嗯」")
        #expect(elf.testLog.contains { $0.line == "[#1 聊天] 手動 AI，不聊天" })
    }

    @Test func 回應超過100字時截斷() async {
        let long = String(repeating: "好", count: 60) + "。" + String(repeating: "啊", count: 60) + "。"
        let elf = Elf(autoAI: ChattingAI(.success(long)))
        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(elf.elfMessage == String(repeating: "好", count: 60) + "。…")
    }

    @Test func 重試後聊天沿用開口時的畫面() async {
        let ai = ChattingAI(.success("怎麼了嗎？"), judgments: [.failure(AutoAIError("忙線"))])
        let elf = Elf(autoAI: ai)
        elf.setDisplay(showDone: false)
        let message = elf.elfMessage
        elf.submitTestInput("嗯")
        await until { elf.canRetry }
        elf.retry()
        await until { elf.isIdle }
        #expect(ai.chatRequests.first?.contains("小精靈說：\(message)\n") == true)
        #expect(ai.chatRequests.first?.contains("判斷失敗") == false)
    }

    @Test func 測試紀錄開頭定義聊天提示詞() {
        let elf = Elf(autoAI: ChattingAI(.success("")))
        elf.includesPrompts = true
        #expect(elf.testLogText.contains("固定提示詞「聊天提示詞」：\n假的聊天指示\n輸出結構：\n{\"type\": \"object\"}"))
    }

    @Test func 補充資訊在使用者說的前一行_沒問時推進index() async {
        let ai = ChattingAI(.success("嗨！"))
        let elf = Elf(autoAI: ai)
        elf.submitTestInput("你好")
        await until { elf.isIdle && ai.chatRequests.count == 1 }
        let lore = ChatTopic.lore[0]
        #expect(ai.chatRequests.first?.hasSuffix("\n這次可以聊的事：\(lore.text)\n使用者說：你好") == true)
        #expect(elf.testLog.contains { $0.line == "[#1 聊天] 補充資訊：這次可以聊的事（\(lore.name)）" })
        #expect(elf.chatRotation == ChatRotation(lore: 1))
    }

    @Test func 問了特定的事_給命中的段落_不推進循環() async {
        let ai = ChattingAI(.success("1.16 公分！"))
        let start = ChatRotation(lore: 4)
        let elf = Elf(autoAI: ai, chatRotation: start)
        elf.submitTestInput("你多高")
        await until { elf.isIdle && ai.chatRequests.count == 1 }
        #expect(ai.chatRequests.first?.contains("使用者在問：站著1.16公分") == true)
        #expect(elf.chatRotation == start)
    }
}

// MARK: - 聊天的補充資訊

@MainActor
struct ChatExtraTests {

    @Test func 使用說明是提示頁() {
        #expect(ChatTopic.help.map(\.name) == HintPage.all.map(\.name))
        #expect(ChatTopic.help.first?.text == HintPage.named(HintPage.overview)?.text)
    }

    @Test func 接下來要做什麼命中規則判斷() {
        #expect(JudgeTool.command("接下來要做什麼", today: .now) == Command(.queryTodos, date: "目前"))
    }

    @Test(arguments: [
        ("怎麼翻頁", "翻頁"),
        ("怎麼看已完成的", "完成"),
        ("要怎麼新增待辦", "新增"),
        ("要怎麼關掉聲音", "聲音與麥克風"),
        ("這個怎麼用", "總導覽"),
        ("使用範例", "總導覽"),
        ("我不會新增", "新增"),
        ("教一下翻頁", "翻頁"),
        ("黃色的日期是什麼意思", "畫面"),
        ("橘色的日期是什麼意思", "畫面"),
        ("藍色的字是什麼", "畫面"),
        ("10月其餘是什麼意思", "畫面"),
        ("為什麼標題不寫日期", "畫面"),
    ])
    func 問用法是使用說明(text: String, topic: String) {
        var rotation = ChatRotation()
        let extra = ChatExtra.pick(for: text, rotation: &rotation)
        #expect(extra.kind == .howTo)
        #expect(extra.topics.map(\.name).contains(topic))
        #expect(rotation == ChatRotation())
    }

    @Test(arguments: ["總導覽", "修改", "完成", "刪除"])
    func 用內容指定的說明也提到編號(name: String) {
        #expect(ChatTopic.help.first { $0.name == name }?.text.contains("第") == true)
    }

    @Test(arguments: [
        ("你多高", "身高體重"),
        ("你生日幾號", "生日"),
        ("你爸爸是做什麼的", "爸爸"),
        ("你住在哪裡", "房間"),
    ])
    func 問小精靈是使用者在問(text: String, topic: String) {
        var rotation = ChatRotation()
        let extra = ChatExtra.pick(for: text, rotation: &rotation)
        #expect(extra.kind == .asked)
        #expect(extra.topics.map(\.name).contains(topic))
        #expect(rotation == ChatRotation())
    }

    @Test func 問句沒命中時給全部() {
        var rotation = ChatRotation()
        let extra = ChatExtra.pick(for: "要吃什麼", rotation: &rotation)
        #expect(extra.kind == .everything)
        #expect(extra.topics.count == ChatTopic.help.count + ChatTopic.lore.count)
        #expect(extra.summary == "可以參考的資料")
    }

    @Test(arguments: ["你好", "好累", "嗯"])
    func 不是問句給閒聊片段_不帶提示(text: String) {
        var rotation = ChatRotation()
        #expect(ChatExtra.pick(for: text, rotation: &rotation).kind == .lore)
    }

    @Test func 閒聊片段依序輪流_輪完從頭開始() {
        var rotation = ChatRotation(lore: ChatTopic.lore.count - 2)
        let picks = (0..<3).map { _ in rotation.next().topics }
        #expect(picks == [[ChatTopic.lore[ChatTopic.lore.count - 2]], [ChatTopic.lore.last!], [ChatTopic.lore[0]]])
        #expect(rotation == ChatRotation(lore: 1))
    }

    @Test func 開場問候依提示頁的順序輪_輪完從頭開始() {
        #expect(Greeting.pages.map(\.name) == HintPage.all.map(\.name))
        #expect(Greeting.page(0).page.name == HintPage.overview)
        #expect(Greeting.page(0).next == 1)
        #expect(Greeting.page(Greeting.pages.count - 1).next == 0)
    }

    @Test func 循環存檔後讀回來接著輪() throws {
        let rotation = ChatRotation(lore: 7)
        let data = try JSONEncoder().encode(rotation)
        #expect(try JSONDecoder().decode(ChatRotation.self, from: data) == rotation)
    }
}

// MARK: - 補救

/// 依序回傳預先排好的判斷結果；用完就回傳空清單。
final class ScriptedAI: AutoAI {
    let name = "排好的 AI"
    let status = ""
    let judgePrompt = FixedPrompt(instructions: "", schema: "")
    let confirmPrompt = FixedPrompt(instructions: "", schema: "")
    private var judgments: [Result<String, AutoAIError>]

    init(_ judgments: [Result<String, AutoAIError>]) {
        self.judgments = judgments
    }

    func judge(_ request: String) async throws -> String {
        judgments.isEmpty ? #"{"commands": []}"# : try judgments.removeFirst().get()
    }

    func confirmDelete(_ request: String) async throws -> String {
        #"{"answer": "no"}"#
    }
}

@MainActor
struct RecoveryTests {

    private let busy = Result<String, AutoAIError>.failure(AutoAIError("Gemini 忙線，請再說一次"))
    private let clear = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
    private let query = Result<String, AutoAIError>.success(#"{"commands": [{"action": "查詢待辦"}]}"#)

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func requested(_ elf: Elf, _ text: String) -> Bool {
        elf.testLog.contains { $0.text == "請求：\(text)" }
    }

    @Test func 判斷失敗輪到時進入錯誤確認_後面的結果不出現_重試成功就繼續() async {
        let elf = Elf(autoAI: ScriptedAI([busy, query, clear]))
        elf.submitTestInput("明天要買水果\n下週有什麼節目")
        await until { elf.canRetry && elf.isIdle }
        #expect(elf.pending.map(\.text) == ["下週有什麼節目"])
        #expect(elf.elfMessage.hasSuffix("說『重試』再試一次，或說『略過』。"))
        // 背景照樣判斷後面的話，但結果不出現。
        #expect(requested(elf, "下週有什麼節目"))
        #expect(!elf.testLog.contains { $0.line.hasPrefix("[#2 指令") })

        elf.retry()
        await until { elf.isIdle && elf.pending.isEmpty && !elf.canRetry }
        #expect(elf.todos.count == 9)
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 重試" })
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#2 指令 1/1] 查詢待辦") })
    }

    @Test func 錯誤確認中說重試等於按重試() async {
        let elf = Elf(autoAI: ScriptedAI([busy, clear]))
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        elf.submitTestInput("再試一次。")
        await until { elf.isIdle }
        #expect(elf.todos.count == 9)
        #expect(elf.testLog.contains { $0.line == "[#2 輸入] 文字：再試一次。" })
        #expect(!requested(elf, "再試一次。"))
    }

    @Test func 錯誤確認中說別的話等於略過_這句話馬上判斷() async {
        let elf = Elf(autoAI: ScriptedAI([busy, query]))
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry && elf.isIdle }
        elf.submitTestInput("下週有什麼事")
        await until { elf.isIdle && !elf.canRetry }
        #expect(elf.todos.count == 8)
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 略過" })
        #expect(elf.testLog.contains { $0.line == "[#2 插隊] 回答：錯誤確認" })
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#2 指令 1/1] 查詢待辦") })
    }

    @Test func 錯誤確認中說略過就丟掉失敗的話並繼續() async {
        let elf = Elf(autoAI: ScriptedAI([busy, query]))
        elf.submitTestInput("明天要買水果\n下週有什麼節目")
        await until { elf.canRetry }
        elf.submitTestInput("略過。")
        await until { elf.isIdle }
        #expect(elf.todos.count == 8)
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 略過" })
        #expect(requested(elf, "下週有什麼節目"))
        #expect(!requested(elf, "略過。"))
    }

    @Test func 不在錯誤確認中說略過照常交給AI() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.submitTestInput("略過")
        await until { elf.isIdle }
        #expect(requested(elf, "略過"))
    }

    @Test func 錯誤確認中說復原就略過並復原_按鈕被彈窗擋住() async {
        let elf = Elf(autoAI: ScriptedAI([clear, busy]))
        elf.submitTestInput("明天要買水果\n嗯")
        await until { elf.canRetry && elf.isIdle }
        #expect(elf.todos.count == 9)
        #expect(!elf.canUndo)

        elf.submitTestInput("復原")
        await until { elf.isIdle && !elf.canRetry }
        #expect(elf.todos.count == 8)
        #expect(!elf.canRetry)
        #expect(elf.testLog.contains { $0.line == "[#2 判斷] 略過" })
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#- 復原] 已復原：\n移除 ") })
    }

    @Test func 沒在等時說復原重做不送AI() async {
        let elf = Elf(autoAI: ScriptedAI([clear]))
        elf.submitTestInput("明天要買水果\n上一步。")
        await until { elf.isIdle }
        #expect(elf.todos.count == 8)
        #expect(!requested(elf, "上一步。"))

        elf.submitTestInput("下一步")
        await until { elf.isIdle }
        #expect(elf.todos.count == 9)
        #expect(elf.elfMessage.hasPrefix("已重做：\n加回 "))
    }

    @Test func 查詢不產生狀態_重新開始清空歷史() async {
        let elf = Elf(autoAI: ScriptedAI([clear]))
        #expect(!elf.canUndo)
        // 規則判斷命中，不用 AI。
        elf.submitTestInput("下週有什麼事")
        await until { elf.isIdle }
        #expect(!elf.canUndo)

        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        #expect(elf.canUndo)
        elf.restart()
        #expect(!elf.canUndo && !elf.canRedo)
    }
}

// MARK: - 黑板與觸控

@MainActor
struct ElfBoardTests {

    private let clear = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
    private let busy = Result<String, AutoAIError>.failure(AutoAIError("忙線"))

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 點方框切換完成_可以undo_黑板沒涵蓋就移到那一天() throws {
        let list = TodoList()
        let elf = Elf(autoAI: nil, todoList: list)
        let todo = try #require(elf.visibleTodos().first)
        elf.toggleDone(todo.id)
        _ = list.run(Command(.queryTodos, date: "2000年1月1日"))
        #expect(elf.todos.first { $0.id == todo.id }?.isDone == true)
        #expect(elf.elfMessage == "已將 \(todo.date!) \(todo.content) 設為已完成")

        elf.undo()
        #expect(elf.todos.first { $0.id == todo.id }?.isDone == false)
        #expect(elf.elfMessage.hasPrefix("已復原："))
        #expect(elf.boardPage.range == .days(from: todo.date!, to: todo.date!, label: nil))
    }

    @Test func undo時黑板保持天數平移() throws {
        let list = TodoList()
        let elf = Elf(autoAI: nil, todoList: list)
        let todo = try #require(elf.visibleTodos().first)
        elf.toggleDone(todo.id)
        _ = list.run(Command(.queryTodos, date: "2000年1月1日~2000年1月7日"))
        elf.undo()
        let day = try TodoStore.dayFormat.parse(todo.date!)
        let shifted = { (offset: Int) in TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: offset, to: day)!) }
        #expect(elf.boardPage.range == .days(from: shifted(-3), to: shifted(3), label: nil))
    }

    @Test func undo時黑板已涵蓋變化就不移動() throws {
        let list = TodoList()
        let elf = Elf(autoAI: nil, todoList: list)
        let today = TodoStore.dayString(.now)
        let todo = try #require(elf.todos.first { $0.date! >= today })
        _ = list.navigate(.showEverything)
        elf.toggleDone(todo.id)
        elf.undo()
        #expect(elf.boardPage.range == .everything)
        #expect(elf.canGoBack && !elf.canGoForward)
    }

    @Test func 點內容複製內容_不改待辦_不產生undo狀態_不進對話流() throws {
        let clipboard = FakeClipboard()
        let elf = Elf(autoAI: nil, clipboard: clipboard)
        let todo = try #require(elf.todos.first)
        let before = elf.todos
        #expect(elf.copyContent(todo.id) == "已複製「\(todo.content)」")
        #expect(clipboard.text == todo.content)
        #expect(elf.todos == before)
        #expect(!elf.canUndo)
        #expect(elf.conversation.isEmpty && elf.elfMessage.isEmpty)
    }

    @Test func 不能點方框時也能點內容複製() async throws {
        let clipboard = FakeClipboard()
        let elf = Elf(autoAI: FakeAI(judgment: busy), clipboard: clipboard)
        let todo = try #require(elf.todos.first)
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        #expect(!elf.canTouch)
        #expect(elf.copyContent(todo.id) != nil)
        #expect(clipboard.text == todo.content)
    }

    @Test func 複製待辦_一次undo拿掉複製的全部() async {
        let list = TodoList()
        _ = list.navigate(.showEverything)
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)), todoList: list)
        let count = elf.todos.count
        elf.submitTestInput("複製第1到2項到12月31日")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(elf.todos.count == count + 2)
        elf.undo()
        #expect(elf.todos.count == count)
    }

    @Test func 點checkbox不加入導覽紀錄_不產生undo狀態() {
        let elf = Elf(autoAI: nil)
        elf.setDisplay(showDone: true)
        #expect(elf.showDone)
        #expect(!elf.canGoBack)
        #expect(!elf.canUndo)
    }

    @Test func 錯誤確認時不能點() async {
        let elf = Elf(autoAI: FakeAI(judgment: busy))
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        #expect(!elf.canTouch)
        elf.setDisplay(showDone: true)
        #expect(!elf.showDone)
    }

    @Test func 彈窗的略過丟掉失敗的話() async {
        let elf = Elf(autoAI: ScriptedAI([busy]))
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        #expect(elf.failureMessage == "判斷失敗：忙線")
        elf.skip()
        await until { elf.isIdle }
        #expect(!elf.canRetry)
        #expect(elf.elfMessage == "已略過「明天要買水果」")
    }

    @Test func 說關閉語音不排隊不送AI() async {
        let elf = Elf(autoAI: ScriptedAI([clear]))
        elf.submitTestInput("關閉語音。")
        await until { elf.isIdle }
        #expect(elf.todos.count == 8)
        #expect(!elf.testLog.contains { $0.text.hasPrefix("請求：") })
        #expect(!elf.isVoiceOn)
    }

    @Test func 顯示全部記成顯示所有資料_不送AI() async {
        let elf = Elf(autoAI: ScriptedAI([clear]))
        elf.submitTestInput("顯示全部。")
        await until { elf.isIdle }
        #expect(elf.boardPage.range == .everything && elf.boardPage.keyword == nil)
        #expect(elf.testLog.contains { $0.line == "[#1 輸入] 文字：顯示所有資料" })
        #expect(!elf.testLog.contains { $0.text.hasPrefix("請求：") })
        #expect(elf.todos.count == 8)
    }

    @Test func 說上一頁下一頁不送AI() async {
        let elf = Elf(autoAI: nil)
        elf.submitTestInput("顯示所有資料\n上一頁")
        await until { elf.isIdle }
        #expect(elf.boardPage.title.hasPrefix("目前"))
        elf.submitTestInput("下一頁")
        await until { elf.isIdle }
        #expect(elf.boardPage.range == .everything)
        // 黑板沒有下一頁時翻提示（見 docs/specs/help.md 的「說明」）。
        elf.submitTestInput("下一頁")
        await until { elf.isIdle }
        #expect(elf.liveHint == HintPage.named(HintPage.overview))
        #expect(elf.boardPage.range == .everything)
    }

    @Test func 聽不懂單獨或混在其他指令裡都不執行() async {
        let elf = Elf(autoAI: ScriptedAI([
            .success(#"{"commands": [{"action": "聽不懂"}]}"#),
            .success(#"{"commands": [{"action": "聽不懂"}, {"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#),
        ]))
        elf.submitTestInput("嗯\n今天天氣如何")
        await until { elf.isIdle }
        #expect(elf.todos.count == 8)
        #expect(elf.elfMessage == "聽不懂「今天天氣如何」")
        #expect(elf.mood == .confused)
        #expect(!elf.canUndo)
    }

    @Test func 新增沒說日期而黑板超過一天_釐清後新增到回答的那一天() async {
        let list = TodoList()
        let elf = Elf(autoAI: ScriptedAI([
            .success(#"{"commands": [{"action": "新增待辦", "content": "看牙醫"}]}"#),
            .success(#"{"commands": [{"action": "新增待辦", "date": "後天", "content": "看牙醫"}]}"#),
        ]), todoList: list)
        _ = list.run(Command(.queryTodos, date: "下週"))
        let before = elf.todos.count
        elf.submitTestInput("看牙醫")
        await until { elf.isIdle }
        #expect(elf.elfMessage.hasPrefix("你是指 "))
        #expect(elf.elfMessage.contains("的哪一天？"))
        #expect(elf.todos.count == before)
        elf.submitTestInput("後天")
        await until { elf.isIdle }
        let dayAfter = TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: 2, to: .now)!)
        #expect(elf.todos.contains { $0.content == "看牙醫" && $0.date == dayAfter })
    }

    @Test func 換算結果是實際用的日期與時間() async {
        let elf = Elf(autoAI: ScriptedAI([
            .success(#"{"commands": [{"action": "新增待辦", "date": "晚上", "content": "看電影"}]}"#),
        ]))
        let day = TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: 2, to: .now)!).replacingOccurrences(of: "-", with: "/")
        elf.submitTestInput("後天晚上有什麼事")
        await until { elf.isIdle }
        #expect(elf.elfMessage.hasPrefix("\(day) 18:00 以後\n"))
        elf.submitTestInput("晚上看電影")
        await until { elf.isIdle }
        #expect(elf.elfMessage.hasPrefix("\(day) 18:00\n已新增"))
    }

    @Test func 找不到時回話只說找不到() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "刪除待辦", "keyword": "看電影"}]}"#)]))
        elf.submitTestInput("刪除看電影")
        await until { elf.isIdle }
        #expect(elf.elfMessage == "找不到")
    }
}

// MARK: - 設定

struct AISettingsTests {

    @Test func 第一次開啟是Gemini() {
        #expect(AISettings.initial().choice == .gemini)
    }

    @Test func 開一個其他自動關_可以全部關() {
        var settings = AISettings.initial()
        settings.set(.ollama, enabled: true)
        #expect(settings.choice == .ollama)
        #expect(!settings.isEnabled(.gemini))
        settings.set(.ollama, enabled: false)
        #expect(settings.choice == nil)
    }

    @Test func 預設的模型與Ollama位址() {
        let settings = AISettings.initial()
        #expect(settings.geminiModel == "gemini-3.1-flash-lite")
        #expect(settings.ollamaModel == "gemma4:e2b")
        #expect(settings.ollamaHost == "localhost" && settings.ollamaPort == "11434")
    }
}

@MainActor
struct NoAITests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 沒有AI時提示無法運作_判斷進入錯誤確認() async {
        let elf = Elf(autoAI: nil)
        await elf.start()
        #expect(elf.elfMessage == "目前沒有可以使用的 AI，無法運作，請到設定開啟。")

        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }
        #expect(elf.elfMessage.hasPrefix("判斷失敗：目前沒有可以使用的 AI"))
        #expect(elf.todos.count == 8)
    }

    @Test func 換成可以用的AI後重試就能繼續() async {
        let elf = Elf(autoAI: nil)
        elf.submitTestInput("明天要買水果")
        await until { elf.canRetry }

        elf.setAutoAI(FakeAI(judgment: .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)))
        #expect(elf.modelStatus.hasPrefix("假的 AI"))
        elf.retry()
        await until { elf.isIdle }
        #expect(elf.todos.count == 9)
    }

    @Test func 手動AI不受影響() async {
        let elf = Elf(autoAI: nil)
        elf.useAutoAI = false
        elf.submitTestInput("明天要買水果")
        await until { elf.manualRequest != nil }
        #expect(!elf.canRetry)
    }
}

// MARK: - 使用者畫面

@MainActor
struct ElfDisplayTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 第1行是正在處理的那一句_排隊數是排在它後面的() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        elf.useAutoAI = false
        #expect(elf.processingSentence == nil)
        #expect(elf.mood == .done)

        elf.submitTestInput("新增明天看牙醫\n嗯")
        await until { elf.manualRequest != nil }
        #expect(elf.manualRequest?.text == "新增明天看牙醫")
        #expect(elf.processingSentence?.text == "新增明天看牙醫")
        #expect(elf.pending.map(\.text) == ["嗯"])
        #expect(elf.mood == .thinking)

        elf.submitManualResponse(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "看牙醫"}]}"#)
        await until { elf.manualRequest?.text == "嗯" }

        elf.submitManualResponse(#"{"commands": []}"#)
        await until { elf.isIdle }
        #expect(elf.processingSentence?.text == "嗯")
        #expect(elf.pending.isEmpty)
        #expect(elf.mood == .confused)
    }

    @Test func 錯誤確認時聽不懂_失敗的話不算排隊() async {
        let elf = Elf(autoAI: FakeAI(judgment: .failure(AutoAIError("忙線"))))
        elf.submitTestInput("明天要買水果\n嗯")
        await until { elf.canRetry }
        #expect(elf.mood == .confused)
        #expect(elf.processingSentence?.text == "明天要買水果")
        #expect(elf.pending.map(\.text) == ["嗯"])
    }

    @Test func 等回答時聆聽中_完成後是完成() async {
        let elf = Elf(autoAI: ScriptedAI([
            .success(#"{"commands": [{"action": "刪除待辦", "date": "下個月", "keyword": "買牛奶"}]}"#),
        ]))
        elf.submitTestInput("刪除下個月的買牛奶")
        await until { elf.isIdle }
        #expect(elf.mood == .listening)

        elf.submitTestInput("不要")
        await until { elf.isIdle }
        #expect(elf.mood == .done)
    }

    @Test func 有任務時也有便條() async {
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)))
        #expect(!elf.guide.text.isEmpty)

        elf.useAutoAI = false
        elf.submitTestInput("刪除所有買牛奶")
        await until { elf.manualRequest != nil }
        #expect(!elf.guide.text.isEmpty)

        elf.submitManualResponse(#"{"commands": [{"action": "刪除待辦", "date": "下個月", "keyword": "買牛奶"}]}"#)
        await until { elf.isIdle }
        #expect(!elf.guide.text.isEmpty)
    }
}

// MARK: - 對話流（見 docs/specs/ui.md 的「對話流」）

@MainActor
struct ConversationTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private let add = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)

    /// 對話紀錄的每一則：使用者說的開頭標「你」，小精靈的標「精靈」。
    private func lines(_ elf: Elf) -> [String] {
        elf.conversation.map { ($0.isUser ? "你：" : "精靈：") + $0.text }
    }

    @Test func 下一句話開始時_上一句的回話留在原位_插畫固定() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let added = elf.elfMessage
        #expect(lines(elf) == ["你：明天要買水果"])
        #expect(elf.liveReply == added)

        elf.submitTestInput("嗯")
        await until { elf.isIdle }
        #expect(lines(elf) == ["你：明天要買水果", "精靈：\(added)", "你：嗯"])
        #expect(elf.conversation[1].mood == .done)
        #expect(elf.liveReply == elf.elfMessage)

        elf.submitTestInput("好")
        await until { elf.isIdle && elf.conversation.count == 5 }
        #expect(elf.conversation[3].mood == .confused)
    }

    @Test func 等回答的回話插畫是等回答() async {
        let elf = Elf(autoAI: ScriptedAI([
            .success(#"{"commands": [{"action": "新增待辦", "date": "下個月", "content": "買牛奶"}]}"#),
            .success(#"{"commands": [{"action": "刪除待辦", "date": "下個月", "keyword": "買牛奶"}]}"#),
        ]))
        elf.submitTestInput("下個月買牛奶\n刪除下個月的買牛奶")
        await until { elf.isIdle && elf.elfMessage.contains("要刪掉嗎") }
        elf.submitTestInput("不要")
        await until { elf.isIdle && elf.conversation.count == 5 }
        #expect(elf.conversation[3].text.contains("要刪掉嗎"))
        #expect(elf.conversation[3].mood == .listening)
    }

    @Test func 開App時第一則是開場問候_插畫完成_不念_不在畫面資訊() async {
        let ai = CorrectingAI(.success("跟小美出去玩"))
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ai, speaker: speaker)
        await elf.start()
        let greeting = elf.conversation.first
        #expect(elf.conversation.count == 1)
        #expect(greeting?.isUser == false)
        #expect(greeting?.mood == .done)
        #expect(greeting?.text == Greeting.novice)
        #expect(elf.chatRotation == ChatRotation())
        #expect(elf.testLog.contains { $0.stage == "提示" && $0.text == "開場問候：新手" })
        #expect(speaker.spoken.isEmpty)

        elf.submitTestInput("跟小每出去玩")
        await until { elf.isIdle }
        let request = ai.correctionRequests.first ?? ""
        #expect(!request.contains("小精靈說："))
        #expect(!request.contains(Greeting.novice))
    }

    @Test func 按復原_原本的回話留在原位_復原的回話不屬於任何一句話() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let added = elf.elfMessage

        elf.undo()
        #expect(lines(elf) == ["你：明天要買水果", "精靈：\(added)"])
        #expect(elf.liveReply?.hasPrefix("已復原") == true)
    }

    @Test func 點顯示已完成_原本的回話留在原位_不被蓋掉() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let added = elf.elfMessage

        elf.setDisplay(showDone: false)
        #expect(lines(elf) == ["你：明天要買水果", "精靈：\(added)"])
        #expect(elf.liveReply?.hasPrefix("完成：隱藏") == true)
    }

    @Test func 點方框_原本的回話留在原位_不被蓋掉() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let added = elf.elfMessage

        elf.toggleDone(elf.todos.first { $0.content == "買水果" }!.id)
        #expect(lines(elf) == ["你：明天要買水果", "精靈：\(added)"])
        #expect(elf.liveReply != added)
    }

    @Test func 輔助關鍵字沒有回話_不重複上一句的回話() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        let added = elf.elfMessage

        elf.submitTestInput("關閉語音")
        await until { elf.isIdle }
        #expect(lines(elf) == ["你：明天要買水果", "精靈：\(added)", "你：關閉語音"])
        #expect(elf.liveReply == nil)
    }

    @Test func 重新開始清空對話紀錄() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天要買水果\n嗯")
        await until { elf.isIdle && elf.conversation.count == 3 }

        elf.restart()
        #expect(elf.conversation.isEmpty)
        #expect(elf.liveReply == nil)
    }
}

/// 直接測對話流 module：提示對話框的凍結與下一個提示的起點（見 docs/specs/help.md 的「提示對話框」）。
@MainActor
struct ConversationStateTests {

    private let add = HintPage.named("新增")!
    private let modify = HintPage.named("修改")!

    @Test func 原地換頁不產生泡泡() {
        let flow = Conversation()
        flow.showHint(add)
        flow.showHint(modify)
        #expect(flow.messages.isEmpty)
        #expect(flow.liveHint == modify)
    }

    @Test func 回話換成別的文字就不是提示對話框() {
        let flow = Conversation()
        flow.showHint(add)
        flow.setReply("已新增 買牛奶")
        #expect(flow.liveHint == nil)
        #expect(flow.liveReply == "已新增 買牛奶")
    }

    @Test func 固定時凍結_停在當時那一頁() {
        let flow = Conversation()
        flow.showHint(add)
        flow.archive(mood: .done, showsWeatherCredit: false)
        #expect(flow.liveHint == nil)
        #expect(flow.liveReply == nil)
        #expect(flow.messages.last?.hint == add.name)
    }

    @Test func 下一個提示_從還沒凍結的算起_沒有就從最後凍結的_都沒有是總導覽() {
        let flow = Conversation()
        #expect(flow.hintTarget(Command(.nextHint))?.name == HintPage.overview)
        flow.showHint(add)
        flow.archive(mood: .done, showsWeatherCredit: false)
        flow.setReply("別的回話")
        #expect(flow.hintTarget(Command(.nextHint)) == add.step(1))
        flow.showHint(modify)
        #expect(flow.hintTarget(Command(.previousHint)) == modify.step(-1))
        #expect(flow.hintTarget(Command(.help, page: "沒有這頁")) == nil)
    }
}

// MARK: - 存檔（見 docs/specs/storage.md）

@MainActor
struct ElfStorageTests {

    private let denied = "沒有取用提醒事項的權限，請到系統設定允許"
    private let today = TodoStore.dayString(.now)
    private let add = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 讀取存檔_測試紀錄記下筆數() async {
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏"), Todo(id: 2, date: today, content: "看牙醫")])))
        await elf.start()
        #expect(elf.todos.count == 2)
        #expect(elf.testLog.contains { $0.stage == "存檔" && $0.text.hasPrefix("讀取：2 筆") })
    }

    @Test func 沒有權限時開啟就提示_沒有AI的提示接在後面() async {
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: FakeTodoStorage(loadError: ToolError(message: denied))))
        await elf.start()
        #expect(elf.todos.isEmpty)
        #expect(elf.elfMessage.hasPrefix("\(denied)\n\n目前沒有可以使用的 AI"))
        #expect(!elf.canTouch)
    }

    @Test func 沒有權限時所有指令都放棄() async {
        let elf = Elf(autoAI: FakeAI(judgment: add), todoList: TodoList(storage: FakeTodoStorage(loadError: ToolError(message: denied))))
        await elf.start()
        elf.submitTestInput("新增明天買水果\n上一頁")
        await until { elf.isIdle && elf.testLog.contains { $0.text.contains("上一頁 → 放棄") } }
        #expect(elf.todos.isEmpty)
        #expect(elf.testLog.contains { $0.text.contains("新增待辦（明天・買水果） → 放棄：沒有執行「新增待辦（明天・買水果）」：\(denied)") })
    }

    @Test func 外部變動_相同就忽略_不同就換掉並清空undo() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")])
        let elf = Elf(autoAI: FakeAI(judgment: add), todoList: TodoList(storage: storage))
        await elf.start()
        elf.submitTestInput("新增明天買水果")
        await until { elf.isIdle && elf.canUndo }
        // App 自己寫入也會觸發：讀回來的相同，undo 保留。
        storage.onExternalChange?()
        await until { elf.testLog.contains { $0.text.hasPrefix("外部變動：2 筆") } }
        #expect(elf.canUndo)
        storage.stored = [Todo(id: 1, content: "買牙膏"), Todo(id: 5, date: today, content: "別處新增的")]
        storage.onExternalChange?()
        // 對話流加一則小精靈的話，不改回話。
        await until { elf.conversation.last == Elf.Message(id: elf.conversation.count, sentence: nil, text: "提醒事項有變動，已更新") }
        #expect(elf.liveReply == nil)
        #expect(elf.todos.map(\.content) == ["買牙膏", "別處新增的"])
        #expect(!elf.canUndo)
        #expect(elf.testLog.contains { $0.stage == "存檔" && $0.text.hasPrefix("外部變動的差異：") && $0.text.contains("「別處新增的」") })
    }

    @Test func 任務進行中先不套用外部變動_任務結束後才套用() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")])
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "刪除待辦", "keyword": "買牙膏"}]}"#)), todoList: TodoList(storage: storage))
        await elf.start()
        elf.submitTestInput("刪除買牙膏")
        await until { elf.isIdle && elf.waitingText.contains("要刪掉") }
        storage.stored = [Todo(id: 1, content: "買牙膏"), Todo(id: 5, content: "別處新增的")]
        storage.onExternalChange?()
        await Task.yield()
        #expect(elf.todos.count == 1)
        elf.submitTestInput("不要")
        await until { elf.todos.count == 2 }
        #expect(!elf.canUndo)
    }

    @Test func 背景讀取中不開始任務_讀完才執行_兩邊的改變都保留() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")])
        let elf = Elf(autoAI: FakeAI(judgment: add), todoList: TodoList(storage: storage))
        await elf.start()
        storage.holdsLoad = true
        storage.stored.append(Todo(id: 5, content: "別處新增的"))
        storage.onExternalChange?()
        await until { storage.isHoldingLoad }
        elf.submitTestInput("新增明天買水果")
        for _ in 0..<50 { await Task.yield() }
        #expect(elf.todos.count == 1, "讀取完成前不執行任務")
        #expect(!elf.canTouch)
        storage.holdsLoad = false
        storage.release()
        await until { elf.isIdle && elf.todos.count == 3 }
        #expect(elf.todos.map(\.content).sorted() == ["別處新增的", "買水果", "買牙膏"].sorted())
        #expect(storage.stored.count == 3)
    }

    @Test func 勾選完成時才讀已完成的_補進undo歷史_undo後還在() async {
        let done = Todo(id: 9, date: "2026-09-01", content: "繳房租", isDone: true)
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")], rest: [done])
        let elf = Elf(autoAI: FakeAI(judgment: add), todoList: TodoList(storage: storage))
        await elf.start()
        #expect(storage.restLoads == 0)
        elf.submitTestInput("新增明天買水果")
        await until { elf.isIdle && elf.canUndo }
        elf.setDisplay(showDone: true)
        await until { elf.showDone }
        #expect(elf.todos.contains(done))
        elf.undo()
        #expect(elf.todos.map(\.id) == [1, 9])
        #expect(storage.saved?.contains(done) == true)
        elf.setDisplay(showDone: false)
        elf.setDisplay(showDone: true)
        await until { elf.showDone }
        #expect(elf.todos.count { $0.id == 9 } == 1)
    }

    @Test func 說顯示完成也先讀已完成的() async {
        let done = Todo(id: 9, date: "2026-09-01", content: "繳房租", isDone: true)
        let storage = FakeTodoStorage(stored: [], rest: [done])
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: storage))
        await elf.start()
        elf.submitTestInput("顯示完成")
        await until { elf.isIdle && elf.showDone }
        #expect(elf.todos == [done])
    }

    @Test func 完成已勾選時開啟就讀已完成的() async {
        let done = Todo(id: 9, date: "2026-09-01", content: "繳房租", isDone: true)
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: FakeTodoStorage(stored: [], rest: [done]), showDone: true))
        await elf.start()
        #expect(elf.todos == [done])
    }

    @Test func 重新開始從存檔重新讀取_不寫入() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")])
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: storage))
        await elf.start()
        storage.stored.append(Todo(id: 2, content: "看牙醫"))
        elf.restart()
        await until { elf.todos.count == 2 }
        #expect(storage.saved == nil)
    }

    @Test func 測試清單_打開換成測試待辦_重新開始換回_關閉回到真實資料() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")])
        let elf = Elf(autoAI: nil, todoList: TodoList(storage: storage))
        await elf.start()
        elf.setTestList(true)
        await until { elf.todos.count == 8 }
        #expect(storage.testSeeds.count == 1)
        elf.restart()
        await until { storage.testSeeds.count == 2 }
        elf.setTestList(false)
        await until { storage.testSeeds.count == 3 }
        #expect(storage.testSeeds.last == .some(nil))
    }
}

// MARK: - 語音報告

struct SpokenReportTests {

    @Test func 問題裡的項目只念前3項() {
        let items = (1...4).map { "☐ 10/9（五） 事\($0)" }
        let question = (["有 4 筆事："] + items + ["要哪一筆？"]).joined(separator: "\n")
        #expect(SpokenReport.question(question)
            == (["有 4 筆事："] + items.prefix(3) + ["還有 1 項請看畫面。", "要哪一筆？"]).joined(separator: "\n"))
        let three = (["有 3 筆事："] + items.prefix(3) + ["要哪一筆？"]).joined(separator: "\n")
        #expect(SpokenReport.question(three) == three)
        #expect(SpokenReport.question("判斷失敗：忙線。說『重試』再試一次，或說『略過』。") == "判斷失敗：忙線。說『重試』再試一次，或說『略過』。")
    }

    @Test func 要全部念完嗎的說法不含回答的關鍵字() {
        let question = ConfirmationKeywords.normalized(SpokenReport.askMore)
        for word in ReportKeywords.yes.union(ReportKeywords.no).union(ReportKeywords.readAll) {
            #expect(!question.contains(word), "說法含回答的關鍵字「\(word)」")
        }
    }

    private func todo(_ date: String, _ time: String = "06:00", content: String, done: Bool = false) -> Todo {
        Todo(id: 0, date: date, time: time, content: content, isDone: done)
    }

    @Test func 沒有時間的不念時刻() {
        #expect(SpokenReport.items([Todo(id: 0, date: "2026-10-05", content: "看牙醫")]) == "10月5日星期一，看牙醫。")
    }

    @Test func 新增一筆與多筆() {
        let a = todo("2026-10-09", content: "a")
        #expect(SpokenReport.compose([.added(a)], readAll: false)?.text == "已新增一個待辦事項。")
        #expect(SpokenReport.compose([.added(a), .added(a)], readAll: false)?.text == "已新增 2 個待辦事項。")
    }

    @Test func 複製一筆與多筆_同一句話合併() {
        let a = todo("2026-10-09", content: "a")
        #expect(SpokenReport.compose([.copied([a])], readAll: false)?.text == "已複製一個待辦事項。")
        #expect(SpokenReport.compose([.copied([a, a]), .copied([a])], readAll: false)?.text == "已複製 3 個待辦事項。")
    }

    @Test func 修改只念改到的部分() {
        let before = todo("2026-01-01", "12:00", content: "看牙醫")
        var time = before
        time.time = "13:00"
        #expect(SpokenReport.compose([.modified(before: [before], after: [time])], readAll: false)?.text == "已將待辦事項時間修改為1月1日星期四下午1點。")
        var content = before
        content.content = "看醫生"
        #expect(SpokenReport.compose([.modified(before: [before], after: [content])], readAll: false)?.text == "已將待辦事項內容修改為看醫生。")
        var both = time
        both.content = "看醫生"
        #expect(SpokenReport.compose([.modified(before: [before], after: [both])], readAll: false)?.text == "已將待辦事項時間修改為1月1日星期四下午1點，內容修改為看醫生。")
    }

    @Test func 用編號改好幾筆只念筆數() {
        let a = todo("2026-10-09", content: "a"), b = todo("2026-10-10", content: "b")
        var later = [a, b]
        later[0].date = "2026-10-12"
        later[1].date = "2026-10-12"
        #expect(SpokenReport.compose([.modified(before: [a, b], after: later)], readAll: false)?.text == "已修改 2 個待辦事項。")
        #expect(SpokenReport.compose([.setDone([a, b], isDone: true)], readAll: false)?.text == "已將 2 個待辦事項設為完成。")
    }

    @Test func 其他動作的念法() {
        let milk = todo("2026-10-09", content: "買牛奶")
        #expect(SpokenReport.compose([.deleted(count: 2), .deleted(count: 1)], readAll: false)?.text == "已刪除 3 個待辦事項。")
        #expect(SpokenReport.compose([.setDone([milk], isDone: true)], readAll: false)?.text == "已將買牛奶設為完成。")
        #expect(SpokenReport.compose([.setDone([milk], isDone: false)], readAll: false)?.text == "已將買牛奶設為未完成。")
        #expect(SpokenReport.compose([.date(phrase: "下週五", from: "2026-10-09", to: "2026-10-09")], readAll: false)?.text == "下週五是10月9日星期五。")
        #expect(SpokenReport.compose([.date(phrase: "明年", from: "2027-01-01", to: "2027-12-31")], readAll: false)?.text == "明年是2027年。")
        #expect(SpokenReport.compose([.date(phrase: "下週", from: "2026-10-05", to: "2026-10-11")], readAll: false)?.text == "下週是10月5日星期一到10月11日星期日。")
    }

    @Test func 沒有日期的只念內容() {
        #expect(SpokenReport.items([Todo(id: 0, content: "買牙膏"), Todo(id: 1, content: "繳費", isDone: true)]) == "買牙膏；繳費，已完成。")
    }

    @Test func 依第一次出現的順序合併_查詢念在最後() {
        let a = todo("2026-10-09", content: "a")
        let text = SpokenReport.compose([.queried([]), .deleted(count: 1), .added(a), .deleted(count: 1)], readAll: false)?.text
        #expect(text == "已刪除 2 個待辦事項。已新增一個待辦事項。沒有待辦事項。")
    }

    @Test func 查詢念3項並詢問_回傳還沒念的() {
        let items = (1...5).map { todo("2026-10-09", "09:00", content: "事\($0)", done: $0 == 2) }
        let speech = SpokenReport.compose([.queried(items)], readAll: false)
        #expect(speech?.text == "有 5 個待辦事項：10月9日星期五早上9點，事1；10月9日星期五早上9點，事2，已完成；10月9日星期五早上9點，事3。還有其他項目，其他的也念出來嗎？")
        #expect(speech?.unread == Array(items.suffix(2)))
        #expect(SpokenReport.items(Array(items.suffix(2))) == "10月9日星期五早上9點，事4；10月9日星期五早上9點，事5。")
    }

    @Test func readAll時念全部_不能詢問時只念3項() {
        let items = (1...4).map { todo("2026-10-09", content: "事\($0)") }
        let all = SpokenReport.compose([.queried(items)], readAll: true)
        #expect(all?.unread == [])
        #expect(all?.text.contains("事4") == true)
        let noAsk = SpokenReport.compose([.queried(items)], readAll: false, canAsk: false)
        #expect(noAsk?.unread == [])
        #expect(noAsk?.text.hasSuffix("事3。") == true)
    }

    @Test func 剛好3項不詢問_沒有結果不念() {
        let items = (1...3).map { todo("2026-10-09", content: "事\($0)") }
        #expect(SpokenReport.compose([.queried(items)], readAll: false)?.unread == [])
        #expect(SpokenReport.compose([], readAll: false) == nil)
    }

    // 回話的文字：和念的句子由同一個結果組成（念的句子在上面）。

    @Test func 回話_設定顯示_復原重做_換頁() {
        #expect(Report.display(showDone: false).reply == "完成：隱藏")
        #expect(Report.nothingToRecover(undo: true).reply == "沒有可以復原的狀態")
        #expect(Report.nothingToRecover(undo: false).reply == "沒有可以重做的狀態")
        let milk = Todo(id: 1, date: "2026-10-03", content: "買牛奶")
        #expect(Report.recovered(undo: true, before: [milk], after: []).reply == "已復原：\n移除 \(milk.line)")
        #expect(Report.navigated(.back, moved: true).reply == "已回到上一頁")
        #expect(Report.navigated(.forward, moved: false).reply == "沒有下一頁")
        #expect(Report.navigated(.showEverything, moved: true).reply == "已顯示所有資料")
    }

    @Test func 只有回話的結果不念() {
        let silent: [Report] = [.display(showDone: true), .nothingToRecover(undo: true), .recovered(undo: false, before: [], after: []), .navigated(.back, moved: true)]
        #expect(silent.allSatisfy { !$0.isSpoken })
        #expect(SpokenReport.compose(silent, readAll: false) == nil)
    }
}



/// 假的 TTS：記下念的內容；`holds` 時念到被停止或 finish() 才返回，模擬正在念。
final class FakeSpeaker: SpeechOutput {
    var holds = false
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    func speak(_ text: String) async {
        spoken.append(text)
        if holds {
            await withCheckedContinuation { pending.append($0) }
        }
    }

    func stop() {
        stops += 1
        finish()
    }

    func finish() {
        pending.forEach { $0.resume() }
        pending = []
    }
}

/// 直接測語音報告 module：中斷、念提示、回音比對（見 docs/specs/spoken-report.md 的「中斷」）。
@MainActor
struct NarratorTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func holding() -> (Narrator, FakeSpeaker) {
        let speaker = FakeSpeaker()
        speaker.holds = true
        return (Narrator(speaker: speaker, isOn: true), speaker)
    }

    @Test func 中斷時停止_重設readAll() async {
        let (narrator, _) = holding()
        narrator.readAll = true
        let speaking = Task { await narrator.speak("已新增 買牛奶") }
        await until { narrator.isSpeaking }
        #expect(narrator.interrupt("停止"))
        #expect(await speaking.value == false)
        #expect(!narrator.isSpeaking)
        #expect(!narrator.readAll)
        #expect(!narrator.interrupt("停止"))
    }

    @Test func 念提示被停掉_不重設readAll() async {
        let (narrator, speaker) = holding()
        narrator.readAll = true
        narrator.speakHint(HintPage.named("新增")!)
        await until { narrator.isSpeaking }
        narrator.stopHint("下一個結果")
        #expect(!narrator.isSpeakingHint)
        #expect(narrator.readAll)
        #expect(speaker.stops == 1)
    }

    @Test func 換頁時停掉上一頁_改念新的一頁() async {
        let (narrator, speaker) = holding()
        let add = HintPage.named("新增")!, modify = HintPage.named("修改")!
        narrator.speakHint(add)
        await until { speaker.spoken == [add.text] }
        narrator.speakHint(modify)
        await until { speaker.spoken.count == 2 }
        #expect(speaker.spoken == [add.text, modify.text])
        #expect(speaker.stops == 1)
        #expect(narrator.isSpeakingHint)
    }

    @Test func 被中斷的那次念完_不改新的狀態() async {
        let (narrator, speaker) = holding()
        let first = Task { await narrator.speak("第一段") }
        await until { speaker.spoken.count == 1 }
        let second = Task { await narrator.speak("第二段") }
        await until { speaker.spoken.count == 2 }
        speaker.finish()
        #expect(await first.value == false)
        #expect(await second.value == true)
        #expect(!narrator.isSpeaking)
    }

    @Test func 回音只算念的期間() async {
        let narrator = Narrator(speaker: FakeSpeaker(), isOn: true)
        var clock = 0
        narrator.tick = { clock += 1; return clock }
        await narrator.speak("已新增 明天 買牛奶")
        // 念的期間是時間點 1～2。
        #expect(narrator.echo(of: "明天買牛奶", at: 1) == "已新增 明天 買牛奶")
        #expect(narrator.echo(of: "明天買牛奶", at: 3) == nil)
        #expect(narrator.echo(of: "刪除第1項", at: 1) == nil)
    }

    /// 念提示的 Task 比小精靈活得久：念完時小精靈已經釋放，也不能當掉。
    @Test func 小精靈釋放後念提示才念完_不會當掉() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        var elf: Elf? = Elf(autoAI: nil, speaker: speaker)
        elf?.openHint(HintPage.overview)
        await until { speaker.spoken.count == 1 }
        elf = nil
        speaker.finish()
        for _ in 0..<10 { await Task.yield() }
        #expect(elf == nil)
    }

    @Test func 關閉或沒有TTS時不念() async {
        let speaker = FakeSpeaker()
        let off = Narrator(speaker: speaker, isOn: false)
        #expect(await off.speak("已新增"))
        #expect(speaker.spoken.isEmpty)
        #expect(!Narrator(speaker: nil, isOn: true).canSpeak)
    }
}

/// 假的語音輸入：記下回呼，由測試送出辨識結果。
final class FakeSpeechInput: SpeechInput {
    private(set) var onResult: ((String, Bool) -> Void)?

    func start(onResult: @escaping (String, Bool) -> Void) async {
        self.onResult = onResult
    }

    func finalize() async {}
    func stop() {}
}

@MainActor
struct SpokenReportFlowTests {

    private let query = Result<String, AutoAIError>.success(#"{"commands": [{"action": "查詢待辦"}]}"#)

    private func add(_ content: String) -> Result<String, AutoAIError> {
        .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "\#(content)"}]}"#)
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func requested(_ elf: Elf, _ text: String) -> Bool {
        elf.testLog.contains { $0.stage == "判斷" && $0.text == "請求：\(text)" }
    }

    /// 黑板上只有今天的 5 件待辦。
    private func elfWithFiveTodos(_ judgments: [Result<String, AutoAIError>], speaker: FakeSpeaker) -> Elf {
        let todos = (1...5).map { Todo(id: $0, date: TodoStore.dayString(.now), content: "事\($0)") }
        return Elf(autoAI: ScriptedAI(judgments), todoList: TodoList(todos: todos), speaker: speaker)
    }

    @Test func 處理完一句話念成功的結果() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([add("買水果")]), speaker: speaker)
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(speaker.spoken == ["已新增一個待辦事項。"])
        #expect(elf.testLog.contains { $0.line == "[#1 報告] 已新增一個待辦事項。" })
    }

    @Test func 聽不懂時不念_錯誤確認念出問題() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": []}"#), .failure(AutoAIError("忙線"))]), speaker: speaker)
        elf.submitTestInput("嗯\n明天要買水果")
        await until { elf.canRetry && elf.isIdle }
        #expect(speaker.spoken == ["判斷失敗：忙線。說『重試』再試一次，或說『略過』。"])
    }

    @Test func 停在刪除確認時先念已成功的與問題_確認後念刪除() async {
        let speaker = FakeSpeaker()
        let judgment = #"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}, {"action": "刪除待辦", "date": "明天", "keyword": "買水果"}]}"#
        let elf = Elf(autoAI: ScriptedAI([.success(judgment)]), speaker: speaker)
        elf.submitTestInput("明天買水果然後刪掉")
        await until { elf.isIdle && speaker.spoken.count == 2 }
        #expect(speaker.spoken.first == "已新增一個待辦事項。")
        #expect(speaker.spoken.last?.hasPrefix("即將刪除明天的買水果（1 項）") == true)
        elf.submitTestInput("好")
        await until { speaker.spoken.count == 3 }
        #expect(speaker.spoken.last == "已刪除 1 個待辦事項。")
    }

    @Test func 超過3項時詢問_回答要就念剩下的並打開readAll() async {
        let speaker = FakeSpeaker()
        let elf = elfWithFiveTodos([query, query], speaker: speaker)
        elf.submitTestInput("有什麼事")
        await until { elf.isIdle && speaker.spoken.count == 2 }
        #expect(speaker.spoken.first?.contains("事3") == true)
        #expect(speaker.spoken.last == "還有其他項目，其他的也念出來嗎？")
        #expect(elf.elfMessage.hasSuffix("還有其他項目，其他的也念出來嗎？"))

        elf.submitTestInput("繼續")
        await until { speaker.spoken.count == 3 }
        #expect(speaker.spoken.last?.contains("事4") == true)
        #expect(elf.readAll)
        #expect(!requested(elf, "繼續"))

        elf.submitTestInput("有什麼事")
        await until { speaker.spoken.count == 4 }
        #expect(speaker.spoken.last?.contains("事5") == true)
        #expect(speaker.spoken.last?.hasSuffix("嗎？") == false)
    }

    @Test func 回答不要就停下_回答其他就中斷並照常判斷() async {
        let speaker = FakeSpeaker()
        let elf = elfWithFiveTodos([query, query], speaker: speaker)
        elf.submitTestInput("有什麼事")
        await until { elf.isIdle && speaker.spoken.count == 2 }
        elf.submitTestInput("不要")
        await until { elf.isIdle && elf.waitingText.isEmpty }
        #expect(speaker.spoken.count == 2)
        #expect(!elf.readAll)
        #expect(!requested(elf, "不要"))

        elf.submitTestInput("有什麼事")
        await until { elf.isIdle && speaker.spoken.count == 4 }
        elf.submitTestInput("明天看牙醫")
        await until { requested(elf, "明天看牙醫") }
        #expect(!elf.readAll)
        #expect(elf.testLog.contains { $0.stage == "插隊" })
    }

    @Test func 念的時候說別的話不中斷_結果排在後面() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([add("買水果"), add("看牙醫")]), speaker: speaker)
        speaker.holds = true
        elf.submitTestInput("明天買水果")
        await until { elf.isSpeaking }
        elf.submitTestInput("明天看牙醫")
        await until { elf.pending.isEmpty || elf.testLog.contains { $0.stage == "準備好" && $0.sentence == 2 } }
        for _ in 0..<50 { await Task.yield() }
        #expect(elf.isSpeaking)
        #expect(speaker.stops == 0)
        #expect(speaker.spoken.count == 1)
        #expect(!elf.testLog.contains { $0.stage == "輪到" && $0.sentence == 2 })

        speaker.finish()
        await until { speaker.spoken.count == 2 }
        speaker.finish()
        await until { elf.isIdle }
        #expect(elf.testLog.contains { $0.stage == "輪到" && $0.sentence == 2 })
    }

    @Test func 念的時候開口不中斷_說停止才中斷() async {
        let speaker = FakeSpeaker()
        let speech = FakeSpeechInput()
        let elf = Elf(autoAI: ScriptedAI([add("買水果")]), speech: speech, speaker: speaker)
        await elf.start()
        await until { speech.onResult != nil }
        speaker.holds = true
        elf.submitTestInput("明天買水果")
        await until { elf.isSpeaking }
        elf.setVoice(true)
        await until { speech.onResult != nil }
        speech.onResult?("停", false)
        #expect(elf.isSpeaking)

        elf.submitTestInput("停止")
        #expect(!elf.isSpeaking)
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "停止" })
        #expect(!requested(elf, "停止"))
    }

    @Test func 念的時候按復原就中斷_點方框不中斷() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([add("買水果")]), speaker: speaker)
        speaker.holds = true
        elf.submitTestInput("明天買水果")
        await until { elf.isSpeaking }
        elf.toggleDone(elf.todos[0].id)
        #expect(elf.isSpeaking)

        elf.undo()
        #expect(!elf.isSpeaking)
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "復原" })
    }

    @Test func 只說全部念完時不送AI_句子裡帶著時照常判斷() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([]), speaker: speaker)
        elf.submitTestInput("全部念出來")
        await until { !speaker.spoken.isEmpty }
        #expect(elf.readAll)
        #expect(speaker.spoken == ["好，之後會全部念完。"])
        #expect(!requested(elf, "全部念出來"))

        let other = Elf(autoAI: ScriptedAI([]), speaker: FakeSpeaker())
        other.submitTestInput("下週有什麼事，全部念出來")
        await until { other.isIdle }
        #expect(other.readAll)
        #expect(requested(other, "下週有什麼事，全部念出來"))
    }

    @Test func 停止不送AI_等詢問時和不要相同() async {
        let speaker = FakeSpeaker()
        let elf = elfWithFiveTodos([query], speaker: speaker)
        elf.submitTestInput("停止")
        #expect(!requested(elf, "停止"))
        elf.submitTestInput("有什麼事")
        await until { elf.isIdle && speaker.spoken.count == 2 }
        elf.submitTestInput("停止")
        #expect(elf.waitingText.isEmpty)
        elf.submitTestInput("要")
        await until { elf.isIdle && requested(elf, "要") }
        // 不是回答，是新的使用者意圖。
        #expect(!elf.readAll)
        #expect(!elf.testLog.contains { $0.stage == "插隊" })
    }

    @Test func 開關關閉時不念也不詢問() async {
        let speaker = FakeSpeaker()
        let elf = elfWithFiveTodos([query], speaker: speaker)
        elf.setReport(false)
        elf.submitTestInput("有什麼事")
        await until { elf.isIdle }
        #expect(speaker.spoken.isEmpty)
        #expect(!elf.elfMessage.contains("要全部念完嗎"))
    }

    @Test func 念的時候關閉開關就中斷() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([add("買水果")]), speaker: speaker)
        speaker.holds = true
        elf.submitTestInput("全部念出來")
        await until { elf.isSpeaking }
        elf.setReport(false)
        #expect(!elf.isSpeaking && !elf.readAll && !elf.isReportOn)
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "關閉開關" })
    }

    @Test func 用說的切換開關() {
        let elf = Elf(autoAI: ScriptedAI([]), speaker: FakeSpeaker())
        elf.submitTestInput("關閉語音報告")
        #expect(!elf.isReportOn)
        elf.submitTestInput("打開語音報告")
        #expect(elf.isReportOn)
        #expect(elf.isIdle)
    }

    @Test func 開關的初始狀態由App提供() {
        #expect(!Elf(autoAI: nil, reportOn: false).isReportOn)
        #expect(Elf(autoAI: nil).isReportOn)
    }
}

// MARK: - 佇列與報告顯示時間

/// 報告顯示時間的等待：記下每次等多久；`holds` 時等到 release() 才返回。
@MainActor
final class FakeWait {
    var holds = false
    private(set) var durations: [Duration] = []
    private var pending: [CheckedContinuation<Void, Never>] = []

    func wait(_ duration: Duration) async {
        durations.append(duration)
        if holds {
            await withCheckedContinuation { pending.append($0) }
        }
    }

    func release() {
        pending.forEach { $0.resume() }
        pending = []
    }
}

@MainActor
struct QueueTests {

    private func add(_ content: String) -> Result<String, AutoAIError> {
        .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "\#(content)"}]}"#)
    }

    private let deleteMilk = Result<String, AutoAIError>.success(#"{"commands": [{"action": "刪除待辦", "keyword": "買牛奶"}]}"#)

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// 閘門都打開的 AI：判斷依請求文字回傳結果，不用等。
    private func openAI(_ judgments: [String: Result<String, AutoAIError>]) -> GatedAI {
        let ai = GatedAI(correction: "", judgments: judgments)
        ai.open("校正")
        judgments.keys.forEach(ai.open)
        return ai
    }

    /// 黑板顯示全部：在全部的測試待辦裡找目標。
    private func makeElf(_ ai: any AutoAI, todos: [Todo]? = nil, speaker: FakeSpeaker? = nil, wait: FakeWait? = nil) -> Elf {
        Elf(autoAI: ai, todoList: everythingList(todos: todos), speaker: speaker, wait: wait.map { fake in { await fake.wait($0) } })
    }

    private func turns(_ elf: Elf) -> [Int?] {
        elf.testLog.filter { $0.stage == "輪到" }.map(\.sentence)
    }

    private func index(_ elf: Elf, _ line: String) -> Int? {
        elf.testLog.firstIndex { $0.line.hasPrefix(line) }
    }

    // MARK: 順序

    @Test func 後面的先解讀好_仍然照說話的順序呈現() async {
        let ai = GatedAI(correction: "", judgments: ["明天買水果呢": add("水果"), "明天看牙醫呢": add("牙醫")])
        ai.open("校正")
        let elf = makeElf(ai)
        elf.submitTestInput("明天買水果呢\n明天看牙醫呢")
        await until { ai.isWaiting("明天買水果呢") && ai.isWaiting("明天看牙醫呢") }

        ai.open("明天看牙醫呢")
        await until { elf.testLog.contains { $0.stage == "準備好" && $0.sentence == 2 } }
        await settle()
        #expect(turns(elf).isEmpty)
        #expect(!elf.todos.contains { $0.content == "牙醫" })

        ai.open("明天買水果呢")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(turns(elf) == [1, 2])
    }

    @Test func 同時最多解讀兩句_一句準備好下一句才開始() async {
        let ai = GatedAI(correction: "", judgments: [:])
        ai.open("校正")
        let elf = makeElf(ai)
        elf.submitTestInput("甲呢\n乙呢\n丙呢")
        await until { ai.isWaiting("甲呢") && ai.isWaiting("乙呢") }
        await settle()
        #expect(!ai.events.contains("判斷：丙呢"))

        ai.open("乙呢")
        await until { ai.isWaiting("丙呢") }
    }

    @Test func 背景不改狀態_等刪除確認時後面的結果準備好也不執行() async {
        let ai = openAI(["刪除所有買牛奶呢": deleteMilk, "明天看牙醫呢": add("牙醫")])
        let elf = makeElf(ai)
        let before = elf.todos
        elf.submitTestInput("刪除所有買牛奶呢\n明天看牙醫呢")
        await until { elf.isIdle && !elf.waitingText.isEmpty && elf.testLog.contains { $0.stage == "準備好" && $0.sentence == 2 } }
        #expect(elf.todos == before)
        #expect(turns(elf) == [1])
        #expect(elf.pending.map(\.text) == ["明天看牙醫呢"])

        elf.submitTestInput("不要")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(elf.todos.contains { $0.content == "牙醫" })
        // 回答插隊：排在之前說的話前面。
        #expect(index(elf, "[#3 插隊]")! < index(elf, "[#2 輪到]")!)
    }

    @Test func 錯誤確認只在輪到失敗的結果時出現() async {
        let ai = GatedAI(correction: "", judgments: ["明天買水果呢": add("水果"), "把資料清掉呢": .failure(AutoAIError("忙線"))])
        ai.open("校正")
        ai.open("把資料清掉呢")
        let elf = makeElf(ai)
        elf.submitTestInput("明天買水果呢\n把資料清掉呢")
        await until { elf.testLog.contains { $0.stage == "準備好" && $0.sentence == 2 } }
        await settle()
        #expect(!elf.canRetry)

        ai.open("明天買水果呢")
        await until { elf.canRetry }
        #expect(turns(elf) == [1, 2])
    }

    // MARK: 回答

    @Test func 問題出現前開口_出現後才定稿的話不是回答() async throws {
        let ai = GatedAI(correction: "", judgments: ["刪除所有買牛奶呢": deleteMilk])
        ai.open("校正")
        let speech = FakeSpeechInput()
        let elf = Elf(autoAI: ai, speech: speech, todoList: everythingList())
        elf.submitTestInput("刪除所有買牛奶呢")
        elf.setVoice(true)
        await until { speech.onResult != nil }

        speech.onResult?("明天", false)
        ai.open("刪除所有買牛奶呢")
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        speech.onResult?("明天看牙醫呢", true)
        try await Task.sleep(for: .seconds(1.7))
        await until { elf.testLog.contains { $0.sentence == 2 && $0.stage == "排隊" } }
        #expect(!elf.testLog.contains { $0.stage == "插隊" })
        #expect(!elf.waitingText.isEmpty)
    }

    @Test func 輔助關鍵字不佔用回答的機會() async {
        let ai = openAI(["刪除所有買牛奶呢": deleteMilk])
        let elf = makeElf(ai)
        elf.submitTestInput("刪除所有買牛奶呢")
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        elf.submitTestInput("關閉語音報告")
        #expect(!elf.isReportOn)
        #expect(!elf.waitingText.isEmpty)

        elf.submitTestInput("不要")
        await until { elf.isIdle && elf.waitingText.isEmpty }
        #expect(elf.testLog.contains { $0.line.hasPrefix("[#3 插隊] 回答：刪除確認") })
        #expect(elf.todos.count { $0.content == "買牛奶" } == 2)
    }

    // MARK: 聊天

    @Test func 畫面資訊的黑板帶編號() async {
        let ai = ChattingAI(.success("怎麼了嗎？"))
        let elf = makeElf(ai)
        elf.submitTestInput("嗯")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(ai.chatRequests.first?.contains("黑板：1. ☐ ") == true)
        #expect(ai.chatRequests.first?.contains("\n2. ☐ ") == true)
    }

    @Test func 前面的結果改了黑板就重做聊天_只有回話變了不重做() async {
        let ai = ChattingAI(.success("怎麼了嗎？"))
        // 下週要有待辦，畫面資訊才有黑板的標題（黑板是空的只寫「無資料」）；今天起第 7 天一定在下週。
        let nextWeek = TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: 7, to: .now)!)
        let elf = makeElf(ai, todos: TestTodos.make() + [Todo(id: 100, date: nextWeek, content: "下週的事")])
        elf.submitTestInput("下週有什麼事\n嗯")
        await until { elf.isIdle && elf.pending.isEmpty }
        #expect(ai.chatRequests.count == 2)
        #expect(elf.testLog.contains { $0.text == "黑板或待辦變了，用現在的畫面重做" })
        #expect(ai.chatRequests.last?.contains("黑板：下週") == true)

        let other = ChattingAI(.success("怎麼了嗎？"))
        let quiet = makeElf(other)
        quiet.submitTestInput("嗯\n嗯嗯")
        await until { quiet.isIdle && quiet.pending.isEmpty }
        #expect(other.chatRequests.count == 2)
        #expect(!quiet.testLog.contains { $0.text == "黑板或待辦變了，用現在的畫面重做" })
    }

    // MARK: 報告顯示時間

    @Test func 沒有念時用公式_時間到了才換下一個() async {
        let wait = FakeWait()
        wait.holds = true
        let elf = makeElf(ChattingAI(.success("怎麼了嗎？")), wait: wait)
        elf.submitTestInput("顯示全部\n嗯")
        await until { wait.durations.count == 1 }
        await settle()
        #expect(turns(elf) == [1])
        #expect(wait.durations.first == DisplayTime.of(elf.elfMessage))

        wait.release()
        await until { turns(elf) == [1, 2] }
    }

    @Test func 念完就換_等回答時不計時() async {
        let wait = FakeWait()
        let elf = makeElf(openAI(["明天要買水果": .success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#), "刪除所有買牛奶呢": deleteMilk]), speaker: FakeSpeaker(), wait: wait)
        elf.submitTestInput("明天要買水果")
        await until { elf.isIdle }
        #expect(wait.durations.isEmpty)

        elf.submitTestInput("復原")
        await until { elf.isIdle }
        elf.submitTestInput("刪除所有買牛奶呢")
        await until { elf.isIdle && !elf.waitingText.isEmpty }
        // 復原沒有念的內容，用公式；刪除確認在等回答，不計時。
        #expect(wait.durations.count == 1)
    }

    @Test func 念的時候關閉語音報告_改用公式() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let wait = FakeWait()
        let elf = makeElf(ScriptedAI([.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)]), speaker: speaker, wait: wait)
        elf.submitTestInput("明天要買水果")
        await until { elf.isSpeaking }
        elf.setReport(false)
        await until { wait.durations.count == 1 }
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "關閉開關" })
    }

    @Test func 按復原中斷報告_回報也有報告顯示時間() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let wait = FakeWait()
        let elf = makeElf(ScriptedAI([.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)]), speaker: speaker, wait: wait)
        elf.submitTestInput("明天要買水果")
        await until { elf.isSpeaking }
        elf.undo()
        #expect(!elf.isSpeaking)
        #expect(elf.elfMessage.hasPrefix("已復原："))
        await until { !wait.durations.isEmpty }
        #expect(wait.durations == [DisplayTime.of(elf.elfMessage)])
    }

    // MARK: 全部取消

    @Test func 全部取消清空佇列_背景的結果丟掉() async {
        let ai = GatedAI(correction: "", judgments: ["明天買水果呢": add("水果"), "明天看牙醫呢": add("牙醫")])
        ai.open("校正")
        let elf = makeElf(ai)
        elf.submitTestInput("明天買水果呢\n明天看牙醫呢")
        await until { ai.isWaiting("明天買水果呢") && ai.isWaiting("明天看牙醫呢") }

        elf.submitTestInput("全部取消。")
        #expect(elf.pending.isEmpty)
        #expect(elf.elfMessage == "已全部取消")
        #expect(elf.testLog.contains { $0.line == "[#3 全部取消] 清掉 #1、#2" })
        ai.open("明天買水果呢")
        ai.open("明天看牙醫呢")
        await settle()
        #expect(turns(elf).isEmpty)
        #expect(!elf.todos.contains { $0.content == "水果" || $0.content == "牙醫" })
    }

    @Test func 全部取消時目前的任務取消_已經執行的不還原() async {
        let ai = openAI(["明天買水果呢": add("水果"), "刪除所有買牛奶呢": deleteMilk])
        let elf = makeElf(ai)
        elf.submitTestInput("明天買水果呢\n刪除所有買牛奶呢")
        await until { elf.isIdle && !elf.waitingText.isEmpty }

        elf.submitTestInput("取消全部")
        #expect(elf.waitingText.isEmpty)
        #expect(elf.todos.contains { $0.content == "水果" })
        #expect(elf.todos.count { $0.content == "買牛奶" } == 2)
        #expect(elf.canUndo)
    }

    @Test func 校正改出的全部取消不算() async {
        let ai = CorrectingAI(.success("全部取消"))
        let elf = makeElf(ai)
        elf.submitTestInput("全部取笑")
        await until { elf.isIdle }
        #expect(!elf.testLog.contains { $0.stage == "全部取消" })
        #expect(elf.testLog.contains { $0.text == "請求：全部取消" })
    }

    // MARK: 回音

    @Test func 念的期間開口是念的文字的一部分就丟掉() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = makeElf(ScriptedAI([.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)]), speaker: speaker)
        elf.submitTestInput("明天要買水果")
        await until { elf.isSpeaking }
        let spoken = speaker.spoken.last ?? ""
        elf.submitTestInput(String(spoken.dropFirst().dropLast()))
        #expect(elf.testLog.contains { $0.stage == "回音" })
        #expect(elf.pending.isEmpty)

        speaker.finish()
        await until { elf.isIdle }
        elf.submitTestInput(String(spoken.dropFirst().dropLast()))
        #expect(elf.testLog.contains { $0.stage == "排隊" && $0.sentence == 3 })
    }

    @Test func 念刪除確認的問題時回答確定_不被當成回音() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = makeElf(ScriptedAI([.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}, {"action": "刪除待辦", "date": "明天", "keyword": "買水果"}]}"#)]), speaker: speaker)
        elf.submitTestInput("明天買水果然後刪掉")
        await until { speaker.spoken.count == 1 }
        speaker.finish()
        await until { elf.isSpeaking && speaker.spoken.count == 2 }
        elf.submitTestInput("確定")
        #expect(!elf.testLog.contains { $0.stage == "回音" })
        #expect(elf.testLog.contains { $0.stage == "插隊" })
        speaker.holds = false
        speaker.finish()
        await until { speaker.spoken.last == "已刪除 1 個待辦事項。" }
    }

    @Test func 刪除確認只念前3項_回話列出全部() async {
        let speaker = FakeSpeaker()
        let elf = makeElf(ScriptedAI([.success(#"{"commands": [{"action": "刪除待辦", "keyword": "測項"}]}"#)]), todos: testTodos(addingToday: (1...5).map { "測項\($0)" }), speaker: speaker)
        elf.submitTestInput("刪除測項")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(speaker.spoken.last?.contains("還有 2 項請看畫面。") == true)
        #expect(speaker.spoken.last?.contains("測項4") == false)
        #expect(elf.elfMessage.contains("測項5"))
    }
}

/// 存在記憶體的剪貼簿。
final class FakeClipboard: Clipboard {
    var text: String?

    init(_ text: String? = nil) {
        self.text = text
    }

    func copy(_ text: String) {
        self.text = text
    }

    func paste() -> String? {
        text
    }
}

// 備份暫停（見 docs/specs/backup.md）；程式恢復時一起恢復。
/*
// MARK: - 備份

@MainActor
struct ElfBackupTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private let backup = #"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "content": "看牙醫", "isDone": false}]}"#

    @Test func 建立備份放到剪貼簿_待辦不變不送AI() async throws {
        let clipboard = FakeClipboard()
        let elf = Elf(autoAI: nil, clipboard: clipboard)
        let before = elf.todos
        elf.submitTestInput("建立備份")
        await until { elf.isIdle }
        #expect(elf.todos == before)
        #expect(try Backup.read(clipboard.text ?? "").map(\.content) == before.map(\.content))
        #expect(elf.elfMessage == "已建立備份，共 8 筆待辦，已放到剪貼簿")
        #expect(!elf.canUndo)
        #expect(!elf.testLog.contains { $0.text.hasPrefix("請求：") })
    }

    @Test func 換成備份取代待辦_黑板是所有_undo一次回去() async {
        let elf = Elf(autoAI: nil, clipboard: FakeClipboard(backup))
        let before = elf.todos
        elf.submitTestInput("換成備份")
        await until { elf.isIdle }
        #expect(elf.todos.map(\.content) == ["看牙醫"])
        #expect(elf.todos.allSatisfy { !$0.isDemo })
        #expect(elf.boardPage.range == .everything)
        #expect(elf.elfMessage == "已換成備份，共 1 筆待辦")
        elf.undo()
        #expect(elf.todos == before)
    }

    @Test func AI判斷出建立備份_結果和規則判斷相同() async throws {
        let clipboard = FakeClipboard()
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "建立備份"}]}"#)]), clipboard: clipboard)
        let before = elf.todos
        elf.submitTestInput("把待辦存一份到剪貼簿")
        await until { elf.isIdle }
        #expect(try Backup.read(clipboard.text ?? "").map(\.content) == before.map(\.content))
        #expect(elf.elfMessage == "已建立備份，共 8 筆待辦，已放到剪貼簿")
        #expect(elf.testLog.contains { $0.text.hasPrefix("請求：") })
    }

    @Test func AI判斷出換成備份_整份取代() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "換成備份"}]}"#)]), clipboard: FakeClipboard(backup))
        elf.submitTestInput("用剪貼簿的資料取代現在的待辦")
        await until { elf.isIdle }
        #expect(elf.todos.map(\.content) == ["看牙醫"])
        #expect(elf.boardPage.range == .everything)
    }

    @Test func 剪貼簿不是備份就不動待辦() async {
        let elf = Elf(autoAI: nil, clipboard: FakeClipboard("買牛奶"))
        let before = elf.todos
        elf.submitTestInput("換成備份")
        await until { elf.isIdle }
        #expect(elf.todos == before)
        #expect(elf.elfMessage == "剪貼簿裡沒有備份")
        #expect(!elf.canUndo)
    }
}
*/

// MARK: - 補救、黑板、念的方式也是執行器

@MainActor
struct KeywordToolTests {

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private let clear = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)

    @Test func AI判斷出復原_回到上一個狀態() async {
        let elf = Elf(autoAI: ScriptedAI([clear, .success(#"{"commands": [{"action": "復原"}]}"#)]))
        elf.submitTestInput("明天要買水果\n剛剛那個不要了")
        await until { elf.isIdle }
        #expect(elf.todos.count == 8)
        #expect(elf.canRedo)
    }

    @Test func 同一句話裡新增後復原_前面的先記成一個狀態() async {
        let add = #"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買鳳梨"}, {"action": "復原"}]}"#
        let elf = Elf(autoAI: ScriptedAI([.success(add)]))
        elf.submitTestInput("新增明天買鳳梨，然後復原")
        await until { elf.isIdle }
        #expect(!elf.todos.contains { $0.content == "買鳳梨" })
        elf.redo()
        #expect(elf.todos.contains { $0.content == "買鳳梨" })
    }

    @Test func AI判斷出上一頁() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "上一頁"}]}"#)]))
        elf.submitTestInput("顯示全部\n回到前一頁")
        await until { elf.isIdle }
        #expect(elf.boardPage.title.hasPrefix("目前"))
    }

    @Test func AI判斷出全部念完() async {
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "全部念完"}]}"#)]), speaker: speaker)
        elf.submitTestInput("之後都念給我聽")
        await until { !speaker.spoken.isEmpty }
        #expect(elf.readAll)
        #expect(speaker.spoken == ["好，之後會全部念完。"])
    }
}

// MARK: - 天氣

/// 假的天氣服務與定位：記下查詢，回傳排好的結果。
@MainActor
final class FakeWeather: WeatherService, Locator {
    var forecasts: [Weather.Forecast] = []
    var hours: [Weather.Hour] = []
    var serviceError: Error?
    var locationError: Error?
    var places: [String: Coordinate] = [:]
    private(set) var queries: [String] = []
    private(set) var searched: [String] = []
    private(set) var coordinates: [Coordinate] = []

    nonisolated func daily(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Forecast] {
        await MainActor.run { log("請求：daily") }
        await recordCoordinate(place)
        try await record("daily \(place.latitude) \(from)~\(to)")
        return await forecasts
    }

    nonisolated func hourly(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Hour] {
        try await record("hourly \(place.latitude) \(from)~\(to)")
        return await hours
    }

    private func recordCoordinate(_ place: Coordinate) {
        coordinates.append(place)
    }

    private func record(_ query: String) throws {
        queries.append(query)
        if let serviceError { throw serviceError }
    }

    nonisolated func current() async throws -> Coordinate {
        if let error = await locationError { throw error }
        return Coordinate(latitude: 25, longitude: 121.5)
    }

    nonisolated func search(_ name: String) async throws -> Coordinate? {
        await recordSearch(name)
        return await places[name]
    }

    private func recordSearch(_ name: String) {
        searched.append(name)
    }
}

@MainActor
struct WeatherLookupTests {

    private let today = TodoStore.dayString(.now)
    private let fake = FakeWeather()
    private var lookup: WeatherLookup { WeatherLookup(service: fake, locator: fake) }
    /// 假定位的所在地（25, 121.5）落在這一區。
    static let towns = Towns([.init(name: "臺北市大安區", rings: [[121, 24.9, 122, 24.9, 122, 25.1, 121, 25.1, 121, 24.9]])])

    @Test func 沒說地點_不在任何一區是所在地_每天一句() async {
        fake.forecasts = [.init(day: today, code: 0, low: 18, high: 25, rainChance: 20)]
        guard case .done(let message, let days, _) = await lookup.run(Command(.weather), now: .now) else {
            Issue.record("沒有完成"); return
        }
        #expect(fake.queries == ["daily 25.0 \(today)~\(today)"])
        #expect(days == [message])
        #expect(message.hasPrefix("所在地，"))
        #expect(message.hasSuffix("：晴，18～25 度，降雨機率 20%。"))
    }

    @Test func 沒說地點用鄉鎮市區的名稱() async {
        fake.forecasts = [.init(day: today, code: 0, low: 18, high: 25, rainChance: 20)]
        let lookup = WeatherLookup(service: fake, locator: fake, towns: Self.towns)
        guard case .done(let message, _, let log) = await lookup.run(Command(.weather), now: .now) else {
            Issue.record("沒有完成"); return
        }
        #expect(message.hasPrefix("臺北市大安區，"))
        #expect(log.hasPrefix("臺北市大安區（25.0,121.5）"))
    }

    @Test func 說了地點用使用者說的地名_不用搜尋結果的名稱() async {
        fake.places["台北"] = Coordinate(latitude: 25.05, longitude: 121.53)
        fake.forecasts = [.init(day: today, code: 80, low: 22, high: 26, rainChance: 60)]
        let lookup = WeatherLookup(service: fake, locator: fake, towns: Self.towns)
        guard case .done(let message, _, _) = await lookup.run(Command(.weather, place: "台北"), now: .now) else {
            Issue.record("沒有完成"); return
        }
        #expect(fake.queries == ["daily 25.05 \(today)~\(today)"])
        #expect(message.hasPrefix("台北，"))
    }

    @Test func 不像地名的不送出_座標四捨五入到小數2位() async {
        guard case .failed(let message, _) = await lookup.run(Command(.weather, place: "sk-ab12cd34ef"), now: .now) else {
            Issue.record("應該不查"); return
        }
        #expect(message == "這不像地名，沒有查詢")
        #expect(fake.searched.isEmpty)
        #expect(fake.queries.isEmpty)

        fake.places["台北"] = Coordinate(latitude: 25.04776, longitude: 121.51713)
        _ = await lookup.run(Command(.weather, place: "台北"), now: .now)
        #expect(fake.coordinates == [Coordinate(latitude: 25.05, longitude: 121.52)])
    }

    @Test func 說了時間用逐小時預報() async {
        let tomorrow = TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: 1, to: .now)!)
        fake.hours = [.init(day: tomorrow, time: "13:00", code: 61, temperature: 23, rainChance: 70)]
        guard case .done(let message, _, _) = await lookup.run(Command(.weather, date: "明天下午"), now: .now) else {
            Issue.record("沒有完成"); return
        }
        #expect(fake.queries == ["hourly 25.0 \(tomorrow)~\(tomorrow)"])
        #expect(message.contains("下午：雨，23 度，降雨機率 70%。"))
    }

    @Test func 部分超過16天_最後加說明() async {
        fake.forecasts = [.init(day: today, code: 0, low: 18, high: 25, rainChance: 20)]
        let last = DatePhrase.calendar.dateComponents([.month, .day], from: DatePhrase.calendar.date(byAdding: .day, value: 20, to: .now)!)
        guard case .done(let message, let days, _) = await lookup.run(Command(.weather, date: "今天~\(last.month!)月\(last.day!)日"), now: .now) else {
            Issue.record("沒有完成"); return
        }
        #expect(days.count == 1)
        #expect(message.hasSuffix("\n其他天只能查今天起 16 天內的天氣。"))
    }

    @Test func 查不到的原因() async {
        guard case .failed(let far, _) = await lookup.run(Command(.weather, date: "昨天"), now: .now) else {
            Issue.record("沒有失敗"); return
        }
        #expect(far == Weather.outOfRange)

        guard case .failed(let missing, _) = await lookup.run(Command(.weather, place: "火星"), now: .now) else {
            Issue.record("沒有失敗"); return
        }
        #expect(missing == "找不到「火星」這個地方")

        fake.locationError = LocatorError.denied
        guard case .failed(let denied, _) = await lookup.run(Command(.weather), now: .now) else {
            Issue.record("沒有失敗"); return
        }
        #expect(denied == "沒有定位權限，查不到所在地的天氣，請到系統設定允許")

        fake.locationError = nil
        fake.serviceError = ToolError(message: "逾時")
        guard case .failed(let service, let log) = await lookup.run(Command(.weather), now: .now) else {
            Issue.record("沒有失敗"); return
        }
        #expect(service == "天氣服務沒有回應")
        #expect(log.hasSuffix("：逾時"))
    }

    @Test func 下次與看不懂是放棄() async {
        #expect(await lookup.run(Command(.weather, date: "下次"), now: .now) == .abandon("天氣要說哪一天"))
        guard case .abandon = await lookup.run(Command(.weather, date: "下週晚上"), now: .now) else {
            Issue.record("沒有放棄"); return
        }
    }
}

@MainActor
struct ElfWeatherTests {

    private let today = TodoStore.dayString(.now)

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    @Test func 今天會下雨嗎_規則判斷_念出結果_不改待辦() async {
        let fake = FakeWeather()
        fake.forecasts = [.init(day: today, code: 61, low: 20, high: 24, rainChance: 80)]
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)), weather: WeatherLookup(service: fake, locator: fake), speaker: speaker)
        let todos = elf.todos
        elf.submitTestInput("今天會下雨嗎")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(elf.testLog.contains { $0.line == "[#1 判斷] 規則：查天氣（今天）" })
        #expect(elf.elfMessage.hasPrefix("所在地，"))
        #expect(speaker.spoken.first?.hasSuffix("：雨，20～24 度，降雨機率 80%。") == true)
        #expect(elf.testLog.contains { $0.stage == "天氣" && $0.text.hasPrefix("所在地（25.0,121.5）\(today)~\(today)") })
        #expect(elf.testLog.contains { $0.line == "[#1 天氣服務] 請求：daily" })
        #expect(elf.todos == todos)
        #expect(!elf.canUndo)
    }

    @Test func 天氣的回話有資料來源標示_下一句話輪到後仍然有() async {
        let fake = FakeWeather()
        fake.forecasts = [.init(day: today, code: 0, low: 18, high: 25, rainChance: 0)]
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "顯示全部"}]}"#)), weather: WeatherLookup(service: fake, locator: fake))
        #expect(!elf.showsWeatherCredit)
        elf.submitTestInput("今天會下雨嗎")
        await until { elf.isIdle && elf.elfMessage.hasPrefix("所在地，") }
        #expect(elf.showsWeatherCredit)
        elf.submitTestInput("顯示所有資料")
        await until { elf.isIdle && !elf.elfMessage.contains("所在地，") }
        #expect(!elf.showsWeatherCredit)
        let replies = elf.conversation.filter { !$0.isUser }
        #expect(replies.filter(\.showsWeatherCredit).map(\.text) == replies.filter { $0.text.hasPrefix("所在地，") }.map(\.text))
        #expect(replies.contains { $0.showsWeatherCredit })
    }

    @Test func 查不到時沒有資料來源標示() async {
        let fake = FakeWeather()
        fake.serviceError = ToolError(message: "逾時")
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)), weather: WeatherLookup(service: fake, locator: fake))
        elf.submitTestInput("今天會下雨嗎")
        await until { elf.isIdle && elf.testLog.contains { $0.stage == "天氣" } }
        #expect(!elf.showsWeatherCredit)
    }

    @Test func 查不到時念出原因_不進入錯誤確認() async {
        let fake = FakeWeather()
        fake.locationError = LocatorError.denied
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "查天氣", "date": "明天"}]}"#)), weather: WeatherLookup(service: fake, locator: fake), speaker: speaker)
        elf.submitTestInput("明天天氣怎樣")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(speaker.spoken == ["沒有定位權限，查不到所在地的天氣，請到系統設定允許"])
        #expect(elf.failureMessage.isEmpty)
    }

    @Test func 超過3天念前3天_回話全部() async {
        let fake = FakeWeather()
        fake.forecasts = (0..<7).map { .init(day: TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: $0, to: .now)!), code: 0, low: 18, high: 25, rainChance: 0) }
        let speaker = FakeSpeaker()
        let elf = Elf(autoAI: FakeAI(judgment: .success(#"{"commands": [{"action": "查天氣", "date": "目前"}]}"#)), weather: WeatherLookup(service: fake, locator: fake), speaker: speaker)
        elf.submitTestInput("這幾天天氣")
        await until { elf.isIdle && !speaker.spoken.isEmpty }
        #expect(elf.elfMessage.components(separatedBy: "所在地，").count - 1 == 7)
        #expect(speaker.spoken.first?.components(separatedBy: "所在地，").count == 4)
        #expect(speaker.spoken.first?.hasSuffix(SpokenReport.seeScreen) == true)
    }

    @Test func 沒有提醒事項權限時照常查() async {
        let fake = FakeWeather()
        fake.forecasts = [.init(day: today, code: 0, low: 18, high: 25, rainChance: 0)]
        let elf = Elf(
            autoAI: FakeAI(judgment: .success(#"{"commands": []}"#)),
            todoList: TodoList(storage: FakeTodoStorage(loadError: ToolError(message: "沒有取用提醒事項的權限，請到系統設定允許"))),
            weather: WeatherLookup(service: fake, locator: fake)
        )
        await elf.start()
        elf.submitTestInput("今天會下雨嗎")
        await until { elf.isIdle && elf.testLog.contains { $0.stage == "天氣" } }
        #expect(elf.elfMessage.hasPrefix("所在地，"))
    }
}

// MARK: - 提示（見 docs/specs/help.md）

@MainActor
struct HintFlowTests {

    private let add = Result<String, AutoAIError>.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}]}"#)
    private let overview = HintPage.named(HintPage.overview)!

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("等待逾時")
    }

    private func requested(_ elf: Elf) -> [String] {
        elf.testLog.filter { $0.stage == "判斷" && $0.text.hasPrefix("請求：") }.map { String($0.text.dropFirst(3)) }
    }

    /// 說「提示」打開總導覽，等它出現。
    private func openOverview(_ elf: Elf) async {
        elf.submitTestInput("提示")
        await until { elf.isIdle && elf.liveHint != nil }
    }

    @Test func 說提示_新的提示對話框是總導覽_不送AI_這句話在對話流() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        #expect(elf.liveHint == overview)
        #expect(elf.elfMessage == overview.text)
        #expect(elf.conversation.last?.text == "提示")
        #expect(elf.mood == .done)
        #expect(requested(elf).isEmpty)
        #expect(elf.testLog.contains { $0.stage == "指令 1/1" && $0.text.hasPrefix("說明（總導覽） → 完成") })
    }

    @Test func 還沒凍結時說下個提示_原地換頁_這句話不在對話流() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        let count = elf.conversation.count
        elf.submitTestInput("下個提示")
        await until { elf.isIdle && elf.liveHint == overview.step(1) }
        #expect(elf.conversation.count == count)
        #expect(elf.testLog.contains { $0.text == "下個提示 → 完成：提示：\(overview.step(1).name)（原地）" })
    }

    @Test func 還沒凍結時說連結名稱_換到那一頁_不送AI() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        elf.submitTestInput("顯示")
        await until { elf.isIdle && elf.liveHint?.name == "顯示" }
        #expect(requested(elf).isEmpty)
    }

    @Test func 說如何新增_還沒凍結時原地換頁() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        let count = elf.conversation.count
        elf.submitTestInput("如何新增")
        await until { elf.isIdle && elf.liveHint?.name == "新增" }
        #expect(elf.conversation.count == count)
    }

    @Test func 下面出現新的泡泡就凍結_停在那一頁() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        await openOverview(elf)
        elf.submitTestInput("下個提示")
        await until { elf.isIdle && elf.liveHint?.name == "新增" }
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle && elf.todos.count == 9 }
        #expect(elf.liveHint == nil)
        #expect(elf.conversation.contains { $0.hint == "新增" })
    }

    @Test func 觸控的回話也讓它凍結() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        elf.toggleDone(elf.visibleTodos()[0].id)
        #expect(elf.liveHint == nil)
        #expect(elf.conversation.last?.hint == HintPage.overview)
    }

    @Test func 凍結後說下個提示_從凍結那一頁開新的() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        await openOverview(elf)
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle && elf.todos.count == 9 }
        elf.submitTestInput("下個提示")
        await until { elf.isIdle && elf.liveHint != nil }
        #expect(elf.liveHint == overview.step(1))
        #expect(elf.conversation.last?.text == "下個提示")
        #expect(elf.conversation.filter { $0.hint != nil }.count == 1)
    }

    @Test func 沒有提示時說上個提示_打開總導覽() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.submitTestInput("上個提示")
        await until { elf.isIdle && elf.liveHint != nil }
        #expect(elf.liveHint == overview)
    }

    @Test func 箭頭頭尾相接() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        elf.stepHint(-1)
        #expect(elf.liveHint == HintPage.all.last)
        elf.stepHint(1)
        #expect(elf.liveHint == overview)
        #expect(elf.testLog.contains { $0.stage == "觸控" && $0.text == "提示：\(HintPage.all.last!.name)（原地）" })
    }

    @Test func 黑板沒有上一頁時_上一頁翻提示() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await openOverview(elf)
        #expect(!elf.canGoBack)
        elf.submitTestInput("上一頁")
        await until { elf.isIdle && elf.liveHint == HintPage.all.last }
        elf.submitTestInput("下一頁")
        await until { elf.isIdle && elf.liveHint == overview }
    }

    @Test func 黑板有上一頁時_上一頁照舊() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.submitTestInput("顯示明天")
        await until { elf.isIdle }
        await openOverview(elf)
        elf.submitTestInput("上一頁")
        await until { elf.isIdle && elf.liveHint == nil }
        #expect(elf.elfMessage == "已回到上一頁")
    }

    @Test func 觸控_沒有提示時開新的_還沒凍結時原地() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.openHint(HintPage.overview)
        #expect(elf.liveHint == overview)
        let count = elf.conversation.count
        elf.openHint("刪除")
        #expect(elf.liveHint?.name == "刪除")
        #expect(elf.conversation.count == count)
        #expect(elf.testLog.contains { $0.stage == "觸控" && $0.text == "提示：總導覽（新的）" })
    }

    @Test func 還沒凍結時一般判斷的請求多一行提示() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "說明", "page": "顯示"}]}"#)]))
        await openOverview(elf)
        elf.submitTestInput("顯示那個點進去")
        await until { elf.isIdle && elf.liveHint?.name == "顯示" }
        #expect(requested(elf) == ["提示：總導覽（連結：新增、修改、刪除、顯示）\n使用者說：顯示那個點進去"])
    }

    @Test func 沒有提示時請求只有這句話() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle }
        #expect(requested(elf) == ["明天買水果"])
    }

    @Test func 判斷失敗後重試_請求相同() async {
        let elf = Elf(autoAI: ScriptedAI([.failure(AutoAIError("忙線")), add]))
        await openOverview(elf)
        elf.submitTestInput("想加一件事")
        await until { elf.canRetry }
        elf.retry()
        await until { elf.isIdle && !elf.canRetry }
        let requests = requested(elf)
        #expect(requests.count == 2 && requests[0] == requests[1])
        #expect(requests[0].hasPrefix("提示：總導覽"))
    }

    @Test func 頁名不在清單裡就放棄() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "說明", "page": "不存在"}]}"#)]))
        elf.submitTestInput("教我一些奇怪的東西")
        await until { elf.isIdle }
        #expect(elf.liveHint == nil)
        #expect(elf.testLog.contains { $0.text.hasPrefix("說明（不存在） → 放棄") })
    }

    @Test func 一句話裡還有其他指令_提示頁只是回話裡的文字() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "新增待辦", "date": "明天", "content": "買水果"}, {"action": "說明", "page": "修改"}]}"#)]))
        elf.submitTestInput("明天買水果，然後教我怎麼改")
        await until { elf.isIdle && elf.todos.count == 9 }
        #expect(elf.liveHint == nil)
        #expect(elf.elfMessage.contains(HintPage.named("修改")!.text))
    }

    // MARK: 念提示

    @Test func 念提示不擋住後面的結果_下一個結果輪到就停() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = Elf(autoAI: ScriptedAI([add]), speaker: speaker)
        elf.submitTestInput("提示")
        await until { speaker.spoken == [overview.text] }
        elf.submitTestInput("明天買水果")
        await until { elf.todos.count == 9 && speaker.spoken.count == 2 }
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "下一個結果" })
        speaker.finish()
        await until { elf.isIdle }
    }

    @Test func 念提示時說下個提示_馬上換頁改念新的一頁() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = Elf(autoAI: ScriptedAI([]), speaker: speaker)
        elf.submitTestInput("提示")
        await until { speaker.spoken == [overview.text] }
        elf.submitTestInput("下個提示")
        await until { speaker.spoken == [overview.text, overview.step(1).text] }
        #expect(elf.liveHint == overview.step(1))
        #expect(elf.testLog.contains { $0.stage == "中斷" && $0.text == "換頁" })
        speaker.finish()
    }

    @Test func 念提示頁時說連結名稱不是回音() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = Elf(autoAI: ScriptedAI([]), speaker: speaker)
        elf.submitTestInput("提示")
        await until { speaker.spoken == [overview.text] }
        elf.submitTestInput("新增")
        await until { elf.liveHint?.name == "新增" }
        #expect(!elf.testLog.contains { $0.stage == "回音" })
        speaker.finish()
    }

    @Test func 念提示時換頁不重設全部念完() async {
        let speaker = FakeSpeaker()
        speaker.holds = true
        let elf = Elf(autoAI: ScriptedAI([]), speaker: speaker)
        elf.submitTestInput("全部念完")
        await until { elf.readAll && speaker.spoken.count == 1 }
        speaker.finish()
        await until { elf.isIdle }
        elf.submitTestInput("提示")
        await until { speaker.spoken.last == overview.text }
        elf.stepHint(1)
        #expect(elf.readAll)
        speaker.finish()
    }

    // MARK: 便條

    @Test func 便條依用過的操作推進_存在用過的紀錄() async {
        let elf = Elf(autoAI: ScriptedAI([add]))
        #expect(elf.guide == Guide.Line(text: "可以說「如何新增」", page: "新增"))
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle && elf.todos.count == 9 }
        #expect(elf.guideUsed == [.add])
        #expect(elf.guide.page == "顯示")
        elf.toggleDone(elf.visibleTodos()[0].id)
        #expect(elf.guideUsed == [.add, .setDone])
    }

    @Test func 聽不懂之後便條引導到最接近的頁_之後成功就不再是這條() async {
        let elf = Elf(autoAI: ScriptedAI([.success(#"{"commands": [{"action": "聽不懂"}]}"#), add]))
        elf.submitTestInput("我想刪掉東西")
        await until { elf.isIdle && elf.elfMessage.hasPrefix("聽不懂") }
        #expect(elf.guide == Guide.Line(text: "可以說「如何刪除」", page: "刪除"))
        elf.submitTestInput("明天買水果")
        await until { elf.isIdle && elf.todos.count == 9 }
        #expect(elf.guide.page == "顯示")
    }

    @Test func 點便條等於說出那句話() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.openHint(elf.guide.page)
        #expect(elf.liveHint?.name == "新增")
    }

    @Test func 用過任何操作就不是新手_開場問候是下一頁提示_一般的回話() async {
        let elf = Elf(autoAI: ScriptedAI([]), greetingIndex: 2, guideUsed: [.add])
        await elf.start()
        #expect(elf.conversation.first?.text == Greeting.pages[2].text)
        #expect(elf.conversation.first?.hint == nil)
        #expect(elf.greetingIndex == 3)
        #expect(elf.chatRotation == ChatRotation())
        #expect(elf.testLog.contains { $0.stage == "提示" && $0.text == "開場問候：\(Greeting.pages[2].name)" })
    }

    @Test func 新手的開場問候教使用者問提示() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        await elf.start()
        #expect(elf.conversation.first?.text == Greeting.novice)
    }

    @Test func 說關閉音效就關掉語音報告_不送AI() async {
        let elf = Elf(autoAI: ScriptedAI([]))
        elf.submitTestInput("關閉音效")
        #expect(!elf.isReportOn)
        elf.submitTestInput("打開音效")
        #expect(elf.isReportOn)
        #expect(requested(elf).isEmpty)
    }
}

@MainActor
struct HintScreenInfoTests {

    @Test func 提示那一行_沒有連結時不列括號() {
        #expect(ScreenInfo.Hint(page: "總導覽", links: ["新增", "顯示"]).line == "提示：總導覽（連結：新增、顯示）")
        #expect(ScreenInfo.Hint(page: "設定", links: []).line == "提示：設定")
    }
}
