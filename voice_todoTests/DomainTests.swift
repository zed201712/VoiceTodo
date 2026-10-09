//
//  DomainTests.swift
//  voicecalenderTests
//

import Foundation
import Testing
@testable import voice_todo

// MARK: - 語音輸入階段

@MainActor
struct SentenceBuilderTests {

    @Test func 多段確定結果串成一句話() {
        var builder = SentenceBuilder()
        builder.receiveVolatile("幫我在", at: 1)
        #expect(builder.receiveFinal("幫我在下週五", at: 2) == nil)
        builder.receiveVolatile("加一個", at: 3)
        #expect(builder.receiveFinal("加一個看牙醫", at: 4) == nil)
        #expect(builder.pause() == .init(text: "幫我在下週五加一個看牙醫", spokenAt: 1))
    }

    @Test func 停頓時還有暫定結果就等定稿() {
        var builder = SentenceBuilder()
        builder.receiveVolatile("明天買牛奶", at: 5)
        #expect(builder.pause() == nil)
        #expect(builder.receiveFinal("明天買牛奶", at: 6) == .init(text: "明天買牛奶", spokenAt: 5))
    }

    @Test func 停頓後又說話就不送出() {
        var builder = SentenceBuilder()
        builder.receiveVolatile("明天", at: 1)
        #expect(builder.pause() == nil)
        builder.receiveVolatile("明天買", at: 2)
        #expect(builder.receiveFinal("明天買牛奶", at: 3) == nil)
    }

    @Test func 沒有內容不送出() {
        var builder = SentenceBuilder()
        #expect(builder.pause() == nil)
        builder.receiveVolatile("嗯", at: 1)
        #expect(builder.receiveFinal("  ", at: 2) == nil)
        #expect(builder.pause() == nil)
    }

    @Test func 開口時間是第一個辨識結果_下一句重新計算() {
        var builder = SentenceBuilder()
        builder.receiveVolatile(" ", at: 1)
        builder.receiveVolatile("好", at: 2)
        #expect(builder.receiveFinal("好", at: 3) == nil)
        #expect(builder.pause()?.spokenAt == 2)
        builder.receiveVolatile("不要", at: 7)
        #expect(builder.pause() == nil)
        #expect(builder.receiveFinal("不要", at: 8)?.spokenAt == 7)
    }
}

// MARK: - 佇列

struct IntentQueueTests {

    private func queue(limit: Int = 2) -> IntentQueue<String, String> {
        var queue = IntentQueue<String, String>()
        queue.limit = limit
        return queue
    }

    @Test func 同時最多兩句_一句準備好下一句才開始() {
        var queue = queue()
        let first = queue.enqueue(1, "A", spokenAt: 1)
        let second = queue.enqueue(2, "B", spokenAt: 2)
        let third = queue.enqueue(3, "C", spokenAt: 3)
        let after = queue.prepared(2, "結果 B")
        #expect(first.map(\.number) == [1])
        #expect(second.map(\.number) == [2])
        #expect(third.isEmpty)
        #expect(after.map(\.number) == [3])
    }

    @Test func 後面的先準備好仍然照輸入順序輪到() {
        var queue = queue()
        _ = queue.enqueue(1, "A", spokenAt: 1)
        _ = queue.enqueue(2, "B", spokenAt: 2)
        _ = queue.prepared(2, "結果 B")
        let early = queue.next()
        #expect(early == nil)
        #expect(queue.isHeadPending)
        _ = queue.prepared(1, "結果 A")
        let a = queue.next()
        let b = queue.next()
        let none = queue.next()
        #expect(a?.intent == "結果 A")
        #expect(b?.intent == "結果 B")
        #expect(none == nil)
        #expect(!queue.isHeadPending)
    }

    @Test func 上限是一句時一次只解讀一句_上限變大就補上() {
        var queue = queue(limit: 1)
        let first = queue.enqueue(1, "A", spokenAt: 1)
        let second = queue.enqueue(2, "B", spokenAt: 2)
        queue.limit = 2
        let more = queue.startable()
        #expect(first.map(\.number) == [1])
        #expect(second.isEmpty)
        #expect(more.map(\.number) == [2])
    }

    @Test func 問題出現後開口的第一句才是回答() {
        var queue = queue()
        queue.ask(at: 10)
        let before = queue.claimAnswer(spokenAt: 9)
        let answer = queue.claimAnswer(spokenAt: 11)
        let second = queue.claimAnswer(spokenAt: 12)
        queue.ask(at: 20)
        let again = queue.claimAnswer(spokenAt: 21)
        queue.endQuestion()
        let ended = queue.claimAnswer(spokenAt: 30)
        #expect(!before)
        #expect(answer)
        #expect(!second)
        #expect(again)
        #expect(!ended)
    }

    @Test func 全部取消清空並回傳被丟掉的句子() {
        var queue = queue()
        _ = queue.enqueue(1, "A", spokenAt: 1)
        _ = queue.enqueue(2, "B", spokenAt: 2)
        _ = queue.enqueue(3, "C", spokenAt: 3)
        let dropped = queue.removeAll()
        let next = queue.enqueue(4, "D", spokenAt: 4)
        #expect(dropped.map(\.number) == [1, 2, 3])
        #expect(next.map(\.number) == [4])
        #expect(queue.entries.map(\.number) == [4])
    }

    @Test func 報告顯示時間_兩秒加每字零點一秒_最多五秒() {
        #expect(DisplayTime.of("好，不念了") == .milliseconds(2500))
        #expect(DisplayTime.of("已新增一個待辦事項。") == .seconds(3))
        #expect(DisplayTime.of("已 新增\n") == .milliseconds(2300))
        #expect(DisplayTime.of(String(repeating: "字", count: 40)) == .seconds(5))
    }

    @Test func 回音是正在念的文字的一部分() {
        let spoken = "已刪除 3 個待辦事項。"
        #expect(Echo.isEcho("刪除3個待辦事項", of: spoken))
        #expect(!Echo.isEcho("刪除部門會議", of: spoken))
        #expect(!Echo.isEcho("。", of: spoken))
    }

    @Test func 全部取消的關鍵字() {
        #expect(CancelAllKeywords.matches("全部取消。"))
        #expect(CancelAllKeywords.matches("停止全部"))
        #expect(!CancelAllKeywords.matches("取消"))
        #expect(!CancelAllKeywords.matches("全部取消明天的"))
    }
}

// MARK: - 日期

@MainActor
struct DatePhraseTests {

    /// 2026-09-28 是星期一。
    private func day(_ text: String) -> Date {
        try! Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse(text)
    }

    private func single(_ text: String, today: String) -> String? {
        try? DatePhrase.parse(text, today: day(today)).get().singleDay
    }

    @Test(arguments: [
        ("前天", "2026-09-26"), ("昨天", "2026-09-27"), ("今天", "2026-09-28"), ("明天", "2026-09-29"), ("後天", "2026-09-30"),
        ("本週週一", "2026-09-28"), ("本週週日", "2026-10-04"), ("上週週五", "2026-09-25"), ("下週週五", "2026-10-09"),
        ("週五", "2026-10-02"), ("15日", "2026-09-15"), ("10月3日", "2026-10-03"), ("明年1月2日", "2027-01-02"), ("2027年3月1日", "2027-03-01"),
    ])
    func 星期一時(text: String, expected: String) {
        #expect(single(text, today: "2026-09-28") == expected)
    }

    @Test(arguments: [("本週週一", "2026-09-28"), ("下週週一", "2026-10-05"), ("本週週日", "2026-10-04"), ("週日", "2026-10-04")])
    func 星期日時一週從星期一開始(text: String, expected: String) {
        #expect(single(text, today: "2026-10-04") == expected)
    }

    @Test(arguments: [
        ("下週週五", "下週週五是 2026-10-09（星期五）"),
        ("週五", "週五是 2026-10-02（星期五）"),
        ("這個月", "這個月是 2026-09-01 到 2026-09-30"),
        ("下個月", "下個月是 2026-10-01 到 2026-10-31"),
        ("上個月", "上個月是 2026-08-01 到 2026-08-31"),
        ("明年", "明年是 2027 年"),
        ("去年", "去年是 2025 年"),
    ])
    func 查詢日期的回傳(text: String, expected: String) {
        let date = try! DatePhrase.parse(text, today: day("2026-09-28")).get()
        #expect(DatePhrase.answer(text, date) == expected)
    }

    @Test func 短日期是月日與星期() {
        #expect(DatePhrase.dayLabel("2026-10-03") == "10/3（六）")
        #expect(DatePhrase.dayLabel("2026-10-04") == "10/4（日）")
        #expect(DatePhrase.dayLabel("2026-12-21") == "12/21（一）")
    }

    @Test func 描述含星期() {
        #expect(DatePhrase.describe(day("2026-10-02")) == "2026-10-02（星期五）")
        #expect(DatePhrase.describe(day("2026-10-04")) == "2026-10-04（星期日）")
    }
}

// MARK: - 時間說法

struct TimePhraseTests {

    private func phrase(_ text: String) -> TimePhrase? {
        try? TimePhrase.parse(Substring(text)).get()
    }

    @Test(arguments: [
        ("凌晨3點", "03:00"), ("清晨7點", "07:00"), ("早上8點", "08:00"), ("上午10點", "10:00"), ("白天11點", "11:00"),
        ("中午12點", "12:00"), ("中午1點", "13:00"), ("下午3點", "15:00"), ("下午12點", "12:00"), ("晚上7點", "19:00"),
        ("15點", "15:00"), ("下午3點30分", "15:30"), ("0點", "00:00"),
    ])
    func 時段加H點換成時間(text: String, time: String) {
        #expect(phrase(text)?.point == time)
    }

    @Test(arguments: [
        "晚上12點", "下午13點", "早上13點", "下午0點", "24點", "3點60分", "下午3點到1點", "凌晨到早上", "以後", "晚上以後以前", "傍晚",
    ])
    func 不合法(text: String) {
        #expect(phrase(text) == nil)
    }

    @Test(arguments: [
        ("凌晨", nil), ("清晨", "06:00"), ("上午", "09:00"), ("早上", "09:00"), ("白天", "09:00"),
        ("中午", "12:00"), ("下午", "15:00"), ("晚上", "18:00"), ("晚上7點以後", nil), ("下午1點到3點", nil),
    ])
    func 時間點(text: String, time: String?) {
        #expect(phrase(text)?.point == time)
    }

    @Test(arguments: [
        ("凌晨", TimeRange(from: "00:00", to: "06:00", includesEnd: false)),
        ("清晨", TimeRange(from: "06:00", to: "09:00", includesEnd: false)),
        ("上午", TimeRange(from: "00:00", to: "12:00", includesEnd: false)),
        ("早上", TimeRange(from: "09:00", to: "12:00", includesEnd: false)),
        ("白天", TimeRange(from: "06:00", to: "18:00", includesEnd: false)),
        ("中午", TimeRange(from: "12:00", to: "15:00", includesEnd: false)),
        ("下午", TimeRange(from: "12:00", to: "18:00", includesEnd: false)),
        ("晚上", TimeRange(from: "18:00", to: nil, includesEnd: false)),
        ("下午3點30分", TimeRange(from: "15:30", to: "15:30", includesEnd: true)),
        ("上午8點以前", TimeRange(from: nil, to: "08:00", includesEnd: false)),
        ("晚上7點以後", TimeRange(from: "19:00", to: nil, includesEnd: false)),
        ("中午以前", TimeRange(from: nil, to: "12:00", includesEnd: false)),
        ("下午以後", TimeRange(from: "12:00", to: nil, includesEnd: false)),
        ("下午1點到3點", TimeRange(from: "13:00", to: "15:00", includesEnd: true)),
        ("中午到下午", TimeRange(from: "12:00", to: "15:00", includesEnd: true)),
        ("上午10點到下午2點", TimeRange(from: "10:00", to: "14:00", includesEnd: true)),
    ])
    func 範圍(text: String, range: TimeRange) {
        #expect(phrase(text)?.range == range)
    }

    @Test func 範圍的邊界_沒有時間的不在範圍內() {
        let before = phrase("上午8點以前")!.range
        #expect(before.contains("07:59") && !before.contains("08:00"))
        let after = phrase("晚上7點以後")!.range
        #expect(after.contains("19:00") && after.contains("23:59") && !after.contains("18:59"))
        let between = phrase("下午1點到3點")!.range
        #expect(between.contains("13:00") && between.contains("15:00") && !between.contains("15:01"))
        #expect(!phrase("晚上")!.range.contains(nil))
    }

    @Test(arguments: [
        ("晚上", "18:00 以後"), ("上午8點以前", "08:00 以前"), ("下午1點到3點", "13:00–15:00"), ("下午3點30分", "15:30"), ("清晨", "06:00–09:00"),
    ])
    func 黑板標題的時間條件(text: String, label: String) {
        #expect(phrase(text)?.range.label == label)
    }

    @Test func 切出的單位() {
        #expect(phrase("晚上7點以後")?.units == ["晚上", "7點", "以後"])
        #expect(phrase("下午1點到3點")?.units == ["下午", "1點", "到", "3點"])
    }

    @Test(arguments: [
        ("05:59", "06:00"), ("06:00", "09:00"), ("08:59", "09:00"), ("09:00", "12:00"), ("14:00", "15:00"),
        ("17:59", "18:00"), ("18:00", nil), ("23:00", nil),
    ])
    func 下一個時段(now: String, slot: String?) {
        #expect(TimePhrase.nextSlot(after: now) == slot)
    }
}

// MARK: - 規則判斷

struct JudgeToolTests {

    private let today = try! TodoStore.dayFormat.parse("2026-09-29")

    @Test(arguments: [
        ("復原", Command.Action.undo), ("上一步。", .undo), ("Undo", .undo), ("重做", .redo), ("下一步", .redo),
        ("上一頁", .previousPage), ("下一頁", .nextPage), ("顯示全部", .showEverything), ("顯示所有資料", .showEverything),
        ("全部念出來！", .readAll), ("全部念完", .readAll),
    ])
    func 一般判斷之前的固定說法產生指令(text: String, action: Command.Action) {
        #expect(JudgeTool.generalCommand(text) == Command(action))
    }

    @Test(arguments: ["幫我備份明天的待辦", "下週有什麼事，全部念出來", "重試", "略過"])
    func 不完全相等就不是一般判斷之前的固定說法(text: String) {
        #expect(JudgeTool.generalCommand(text) == nil)
    }

    private func hit(_ text: String) -> Command? {
        JudgeTool.command(text, today: today)
    }

    @Test(arguments: [
        ("10月6號有什麼事？", "10月6日"), ("明天有什麼事情", "明天"), ("下週有什麼待辦", "下週"), ("後天有什麼行程呢", "後天"),
        ("明天有什麼安排", "明天"), ("明天有哪些事", "明天"), ("明天要做什麼", "明天"), ("明天有事嗎", "明天"),
        ("明天的待辦", "明天"), ("顯示十一月", "11月"), ("查詢下個月", "下個月"), ("晚上有什麼事", "晚上"),
        ("下禮拜三有什麼行程", "下週週三"), ("星期天有什麼事", "週日"), ("這禮拜有什麼事", "本週"),
        ("晚上七點半以後有什麼事", "晚上7點30分以後"), ("下午一點到三點有什麼事", "下午1點到3點"),
        ("接下來七天有什麼事", "目前"), ("接下來有什麼事", "目前"),
        ("10月12有什麼事", "10月12日"), ("十月十二有什麼事", "10月12日"), ("10月12下午3點以後有什麼事", "10月12日下午3點以後"), ("所有的待辦", "所有"), ("二十一號有什麼事", "21日"),
    ])
    func 查詢待辦(text: String, date: String) {
        #expect(hit(text) == Command(.queryTodos, date: date))
    }

    @Test func 沒有日期的查詢() {
        #expect(hit("有什麼事") == Command(.queryTodos))
        #expect(hit("有什麼事嗎") == Command(.queryTodos))
    }

    @Test(arguments: [
        ("下週五是幾號", "下週週五"), ("10月6號是星期幾", "10月6日"), ("今天幾號", "今天"), ("明天是幾月幾號", "明天"), ("後天禮拜幾", "後天"),
    ])
    func 查詢日期(text: String, date: String) {
        #expect(hit(text) == Command(.queryDate, date: date))
    }

    @Test func 查詢日期沒有日期() {
        #expect(hit("是幾號") == Command(.queryDate))
    }

    @Test(arguments: [
        ("顯示完成", Command(.setDisplay, showDone: true)), ("勾選完成", Command(.setDisplay, showDone: true)),
        ("隱藏完成", Command(.setDisplay, showDone: false)), ("取消勾選完成", Command(.setDisplay, showDone: false)),
        ("刪除全部", Command(.deleteTodos)), ("刪除完成", Command(.deleteTodos, isDone: true)),
        ("刪除完成項目", Command(.deleteTodos, isDone: true)), ("刪除已完成項目", Command(.deleteTodos, isDone: true)),
        ("刪除已完成", Command(.deleteTodos, isDone: true)), ("清除完成項目。", Command(.deleteTodos, isDone: true)),
    ])
    func 固定的話(text: String, command: Command) {
        #expect(hit(text) == command)
    }

    @Test(arguments: [
        "明天要看牙醫", "明天有什麼會議", "下下週有什麼事", "晚上是幾號", "明天有什麼事啊", "建立示範資料", "建立備份",
        "顯示", "的待辦", "新增明天買水果", "顯示明天，刪除買牛奶", "下次是幾號", "10月12點有什麼事",
        "顯示過去項目", "隱藏過去項目",
    ])
    func 不命中(text: String) {
        #expect(hit(text) == nil)
    }

    @Test(arguments: [
        ("刪除第3項", Command(.deleteTodos, number: "3")), ("刪除第5到10項", Command(.deleteTodos, number: "5~10")),
        ("第五到第十項刪除", Command(.deleteTodos, number: "5~10")), ("刪掉第2項到第4項", Command(.deleteTodos, number: "2~4")),
        ("把第十二項刪掉。", Command(.deleteTodos, number: "12")),
        ("完成第2項", Command(.setDone, number: "2", isDone: true)), ("第3到5項完成", Command(.setDone, number: "3~5", isDone: true)),
        ("把第2項設為完成", Command(.setDone, number: "2", isDone: true)),
        ("第2項移到明天", Command(.modifyTodo, number: "2", newDate: "明天")),
        ("把第3到10項移到後天", Command(.modifyTodo, number: "3~10", newDate: "後天")),
        ("把第三項延到下禮拜三", Command(.modifyTodo, number: "3", newDate: "下週週三")),
        ("第2項改到下午3點", Command(.modifyTodo, number: "2", newDate: "下午3點")),
        ("將第三項改到明天。", Command(.modifyTodo, number: "3", newDate: "明天")),
        ("將第2項刪除", Command(.deleteTodos, number: "2")),
        ("將第2項設為完成", Command(.setDone, number: "2", isDone: true)),
    ])
    func 編號(text: String, command: Command) {
        #expect(hit(text) == command)
    }

    @Test(arguments: [
        "把3到10移到後天", "刪除第三向", "刪除第3項嗎", "第2項移到下下週", "刪除第3項和第5項", "刪除第項", "第2項移到",
    ])
    func 編號不命中(text: String) {
        #expect(hit(text) == nil)
    }
}

// MARK: - 待辦清單的執行器

@MainActor
struct TodoStoreTests {

    @Test func 沒有時間的待辦排在同一天最前面_不顯示時間() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-10-05", time: "05:00", content: "晨跑")
        try store.addTodo(date: "2026-10-05", content: "看牙醫")
        #expect(store.todos.sorted { $0.order < $1.order }.map(\.content) == ["看牙醫", "晨跑"])
        #expect(store.todos.first { $0.content == "看牙醫" }?.line == "☐ 10/5（一） 看牙醫")
        #expect(store.todos.first { $0.content == "晨跑" }?.line == "☐ 10/5（一） 05:00 晨跑")
    }

    @Test func 沒有日期的待辦排在最後_不顯示日期() {
        let todos = [Todo(id: 1, content: "買牙膏"), Todo(id: 2, date: "2026-10-05", content: "看牙醫"), Todo(id: 3, date: "2026-12-31", content: "跨年")]
        #expect(todos.sorted { $0.order < $1.order }.map(\.id) == [2, 3, 1])
        #expect(todos[0].line == "☐ 買牙膏")
    }

    @Test func 測試待辦有時間與沒有時間的都有() {
        let todos = TestTodos.make()
        #expect(todos.count == 8)
        #expect(todos.contains { $0.time == nil })
        #expect(todos.contains { $0.time != nil })
    }

    @Test func 新增與查詢() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-10-02", content: "看牙醫")
        try store.addTodo(date: "2026-11-01", content: "繳房租")
        let result = try store.queryTodos(from: "2026-10-01", to: "2026-10-31")
        #expect(result.map(\.content) == ["看牙醫"])
    }

    @Test func 查詢不到不算失敗() throws {
        let store = TodoStore()
        #expect(try store.queryTodos(from: "2026-10-01", to: "2026-10-31").isEmpty)
    }

    @Test func 參數不合法就失敗() throws {
        let store = TodoStore()
        #expect(throws: ToolError.self) { try store.addTodo(date: "2026-13-01", content: "x") }
        #expect(throws: ToolError.self) { try store.addTodo(date: "明天", content: "x") }
        #expect(throws: ToolError.self) { try store.addTodo(date: "2026-10-01", content: " ") }
        #expect(throws: ToolError.self) { try store.setDone(id: 99, isDone: true) }
    }

    @Test func 修改至少要給一項() throws {
        let store = TodoStore()
        let todo = try store.addTodo(date: "2026-10-02", content: "看牙醫")
        #expect(throws: ToolError.self) { try store.modifyTodo(id: todo.id, date: nil, content: nil) }
        try store.modifyTodo(id: todo.id, date: "2026-10-03", content: nil)
        #expect(store.todos.first?.date == "2026-10-03")
    }

    @Test func 任務還原到開始前() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-10-02", content: "看牙醫")
        store.beginTask()
        try store.addTodo(date: "2026-10-03", content: "買牛奶")
        store.endTask(restore: true)
        #expect(store.todos.map(\.content) == ["看牙醫"])
    }

    @Test func 任務完成保留結果() throws {
        let store = TodoStore()
        store.beginTask()
        try store.addTodo(date: "2026-10-03", content: "買牛奶")
        store.endTask(restore: false)
        #expect(store.todos.count == 1)
    }
}

// MARK: - 存檔

/// 存在記憶體的存檔；`saved` 是最後一次寫入的內容。和提醒事項一樣只寫入差異：
/// 別處改的（直接改 `stored`）不會被寫入蓋掉。
final class FakeTodoStorage: TodoStorage {
    var stored: [Todo]
    /// 上次讀取或寫入的那份。
    private var known: [Todo] = []
    /// 延遲讀取的其餘待辦；讀過一次就併進 `stored`。
    var rest: [Todo]
    var loadError: Error?
    private(set) var saved: [Todo]?
    private(set) var restLoads = 0
    private(set) var testSeeds: [[Todo]?] = []
    var onExternalChange: (() -> Void)?
    /// true 時讀取停住，等 `release()`：模擬讀取提醒事項要花時間。
    var holdsLoad = false
    private var heldLoads: [CheckedContinuation<Void, Never>] = []
    var isHoldingLoad: Bool { !heldLoads.isEmpty }

    func release() {
        heldLoads.forEach { $0.resume() }
        heldLoads = []
    }

    init(stored: [Todo] = [], rest: [Todo] = [], loadError: Error? = nil) {
        self.stored = stored
        self.rest = rest
        self.loadError = loadError
    }

    func load() async throws -> [Todo] {
        if holdsLoad {
            await withCheckedContinuation { heldLoads.append($0) }
        }
        if let loadError { throw loadError }
        known = stored
        return stored
    }

    func loadRest() async throws -> [Todo] {
        if let loadError { throw loadError }
        restLoads += 1
        defer { rest = [] }
        stored += rest
        known += rest
        return rest
    }

    func save(_ todos: [Todo]) throws {
        saved = todos
        let removed = Set(known.map(\.id)).subtracting(todos.map(\.id))
        var result = stored.filter { !removed.contains($0.id) }
        for todo in todos {
            if let index = result.firstIndex(where: { $0.id == todo.id }) {
                result[index] = todo
            } else {
                result.append(todo)
            }
        }
        stored = result
        known = todos
    }

    func useTestData(_ seed: [Todo]?) async throws {
        testSeeds.append(seed)
        stored = seed ?? []
        known = []
    }
}

@MainActor
struct TodoStorageTests {

    @Test func 讀取存檔並接續id() async throws {
        let storage = FakeTodoStorage(stored: [Todo(id: 7, date: "2026-10-01", content: "買水果")])
        let store = TodoStore(storage: storage)
        #expect(await store.load())
        #expect(store.todos == [Todo(id: 7, date: "2026-10-01", content: "買水果")])
        try store.addTodo(date: "2026-10-02", content: "看牙醫")
        #expect(store.todos.last?.id == 8)
    }

    @Test func 沒有權限或讀取失敗時沒有存檔_原因可以顯示() async {
        let storage = FakeTodoStorage(loadError: ToolError(message: "沒有取用提醒事項的權限，請到系統設定允許"))
        let store = TodoStore(storage: storage)
        await store.load()
        #expect(store.todos.isEmpty)
        #expect(store.unavailableReason == "沒有取用提醒事項的權限，請到系統設定允許")
        storage.loadError = nil
        storage.stored = [Todo(id: 1, content: "買牙膏")]
        await store.load()
        #expect(store.unavailableReason == nil)
        #expect(store.todos.count == 1)
    }

    @Test func 讀回來和記憶體相同就是沒有改變() async {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏"), Todo(id: 2, content: "看牙醫")])
        let store = TodoStore(storage: storage)
        await store.load()
        storage.stored.reverse()
        #expect(!(await store.load()))
        storage.stored.removeLast()
        #expect(await store.load())
    }

    @Test func 任務結束才寫入() async throws {
        let storage = FakeTodoStorage()
        let store = TodoStore(storage: storage)
        await store.load()
        store.beginTask()
        try store.addTodo(date: "2026-10-01", content: "買水果")
        #expect(storage.saved == nil)
        store.endTask(restore: false)
        #expect(storage.saved?.map(\.content) == ["買水果"])
    }

    @Test func 還原後寫入還原的資料() async throws {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, date: "2026-10-01", content: "買水果")])
        let store = TodoStore(storage: storage)
        await store.load()
        store.beginTask()
        store.delete(ids: [1])
        store.endTask(restore: true)
        #expect(storage.saved?.map(\.content) == ["買水果"])
    }

    @Test func 刪掉的id不會再被新增的待辦用到() async throws {
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏"), Todo(id: 2, content: "看牙醫")])
        let store = TodoStore(storage: storage)
        await store.load()
        store.delete(ids: [2])
        store.endTask(restore: false)
        await store.load()
        #expect(try store.addTodo(date: "2026-10-01", content: "繳費").id == 3)
    }

    @Test func 延遲讀取加進目前的待辦_讀過就不再讀() async throws {
        let done = Todo(id: 9, date: "2026-09-01", content: "繳房租", isDone: true)
        let storage = FakeTodoStorage(stored: [Todo(id: 1, content: "買牙膏")], rest: [done])
        let store = TodoStore(storage: storage)
        await store.load()
        #expect(try await store.loadRest() == [done])
        #expect(store.todos.map(\.id) == [1, 9])
        #expect(try await store.loadRest().isEmpty)
        #expect(try store.addTodo(date: "2026-10-01", content: "繳費").id == 10)
    }
}

// App 自己的通知停用（見 docs/specs/notifications.md 的「App 自己的通知」）；程式恢復時一起恢復。
/*
// MARK: - 通知

@MainActor
struct TodoNotificationTests {

    /// 2026-10-05 15:00（本地時間）
    let now = DatePhrase.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15, minute: 0, second: 30))!

    @Test func 只有未完成_有時間_不是示範資料_時間還沒到的待辦有通知() {
        let todos = [
            Todo(id: 1, date: "2026-10-05", time: "15:01", content: "看牙醫"),
            Todo(id: 2, date: "2026-10-05", time: "16:00", content: "買水果", isDone: true),
            Todo(id: 3, date: "2026-10-06", content: "繳電費"),
            Todo(id: 4, date: "2026-10-06", time: "09:00", content: "開會", isDemo: true),
            Todo(id: 5, date: "2026-10-05", time: "15:00", content: "同一分鐘"),
            Todo(id: 6, date: "2026-10-04", time: "20:00", content: "昨天"),
        ]
        #expect(TodoNotification.plan(todos, now: now) == [
            TodoNotification(id: "todo-1", date: "2026-10-05", time: "15:01", body: "15:01 看牙醫"),
        ])
    }

    @Test func 依待辦的排序最多64個() {
        let todos = (1...70).reversed().map { Todo(id: $0, date: "2026-10-\(String(format: "%02d", 6 + $0 / 10))", time: String(format: "%02d:00", $0 % 10), content: "第\($0)") }
        let plan = TodoNotification.plan(todos, now: now)
        #expect(plan.count == 64)
        #expect(plan.map(\.id) == todos.sorted { $0.order < $1.order }.prefix(64).map { "todo-\($0.id)" })
    }
}

/// 記錄最後一次整份取代的通知。
final class FakeNotificationScheduler: NotificationScheduler {
    private(set) var scheduled: [TodoNotification]?

    func requestAccess() async -> Bool { true }

    func replaceAll(with notifications: [TodoNotification]) {
        scheduled = notifications
    }
}

@MainActor
struct NotificationSyncTests {

    let dentist = Todo(id: 1, date: "2099-10-05", time: "15:00", content: "看牙醫")

    @Test func 讀取存檔後重排() {
        let scheduler = FakeNotificationScheduler()
        let store = TodoStore(storage: FakeTodoStorage(stored: [dentist]), notifications: scheduler)
        store.load()
        #expect(scheduler.scheduled?.map(\.body) == ["15:00 看牙醫"])
    }

    @Test func 任務進行中不排_結束後重排_還原後和還原的待辦一致() throws {
        let scheduler = FakeNotificationScheduler()
        let store = TodoStore(storage: FakeTodoStorage(stored: [dentist]), notifications: scheduler)
        store.load()
        store.beginTask()
        try store.addTodo(date: "2099-10-06", time: "09:00", content: "開會")
        store.delete(ids: [1])
        #expect(scheduler.scheduled?.map(\.body) == ["15:00 看牙醫"])
        store.endTask(restore: true)
        #expect(scheduler.scheduled?.map(\.body) == ["15:00 看牙醫"])
        store.beginTask()
        try store.setDone(id: 1, isDone: true)
        store.endTask(restore: false)
        #expect(scheduler.scheduled == [])
    }

    @Test func undo刪除後通知回來() {
        let scheduler = FakeNotificationScheduler()
        let store = TodoStore(storage: FakeTodoStorage(stored: [dentist]), notifications: scheduler)
        store.load()
        let before = store.todos
        store.beginTask()
        store.delete(ids: [1])
        store.endTask(restore: false)
        #expect(scheduler.scheduled == [])
        store.replace(with: before)
        #expect(scheduler.scheduled?.map(\.id) == ["todo-1"])
    }

    @Test func 換成備份後只有備份裡的待辦的通知() {
        let scheduler = FakeNotificationScheduler()
        let store = TodoStore(storage: FakeTodoStorage(stored: [dentist]), notifications: scheduler)
        store.load()
        store.replace(withBackup: [Todo(id: 0, date: "2099-10-07", time: "08:00", content: "晨跑")])
        #expect(scheduler.scheduled?.map(\.body) == ["08:00 晨跑"])
        #expect(scheduler.scheduled?.map(\.id) == store.todos.map { "todo-\($0.id)" })
    }
}
*/

// MARK: - 日期說法

@MainActor
struct DateScopeTests {

    /// 2026-09-29 是星期二。
    private let today = try! TodoStore.dayFormat.parse("2026-09-29")

    private func parse(_ text: String) -> ParsedDate? {
        try? DatePhrase.parse(text, today: today).get()
    }

    @Test(arguments: [
        ("明天", "2026-09-30", "2026-09-30"),
        ("下週週五", "2026-10-09", "2026-10-09"),
        ("下週", "2026-10-05", "2026-10-11"),
        ("下個月", "2026-10-01", "2026-10-31"),
        ("明年", "2027-01-01", "2027-12-31"),
        ("11月", "2026-11-01", "2026-11-30"),
        ("明年1月", "2027-01-01", "2027-01-31"),
        ("目前", "2026-09-29", "2026-10-05"),
        ("1月10日~2月10日", "2026-01-10", "2026-02-10"),
        ("12月10日~1月10日", "2026-12-10", "2027-01-10"),
        ("明天~10月3日", "2026-09-30", "2026-10-03"),
        ("11月~12月", "2026-11-01", "2026-12-31"),
    ])
    func 範圍是最小單位的整段(text: String, from: String, to: String) {
        #expect(parse(text)?.days == .range(from: from, to: to))
    }

    @Test(arguments: [
        ("明天", nil), ("明天晚上", "18:00"), ("下個月15日下午3點30分", "15:30"), ("下午7點", "19:00"),
        ("晚上9點", "21:00"), ("中午1點", "13:00"), ("中午12點30分", "12:30"), ("清晨", "06:00"), ("早上", "09:00"),
        ("中午", "12:00"), ("下午", "15:00"), ("20點", "20:00"), ("早上8點", "08:00"),
    ])
    func 時刻(text: String, time: String?) {
        #expect(parse(text)?.time?.point == time)
    }

    @Test func 日期後面接時間範圍_所有() {
        #expect(parse("明天晚上7點以後")?.time?.range == TimeRange(from: "19:00", to: nil, includesEnd: false))
        #expect(parse("明天晚上7點以後")?.result == "2026/09/30 19:00 以後")
        #expect(parse("明天晚上")?.result == "2026/09/30 18:00 以後")
        #expect(parse("所有")?.days == .everything)
        #expect(parse("明天上午")?.days == .range(from: "2026-09-30", to: "2026-09-30"))
    }

    @Test func 只有時刻沒有日期() {
        #expect(parse("晚上")?.days == ParsedDate.Days.none)
    }

    @Test func 解析結果() {
        #expect(parse("下個月15日下午3點30分")?.analysis == "下個月 15日 下午 3點 30分 → 2026/10/15 15:30")
        #expect(parse("下個月")?.result == "2026/10/01 ~ 2026/10/31")
        #expect(parse("1月2日~2月5日")?.analysis == "1月 2日 ~ 2月 5日 → 2026/01/02 ~ 2026/02/05")
    }

    @Test func 看不懂時回傳卡住的字() {
        guard case .failure(let error) = DatePhrase.parse("下個月15日下午X", today: today) else {
            Issue.record("應該看不懂")
            return
        }
        #expect(error.analysis == "下個月 15日 下午 → 看不懂「X」")
        #expect(error.localizedDescription == "看不懂「X」")
    }

    @Test func 下次() {
        #expect(parse("下次")?.days == .next)
    }

    @Test(arguments: [
        "", "某天", "13月1日", "下禮拜", "星期五", "2月30日",
        "15日下個月", "明年明天", "下個月下週", "下個月週五", "明年下個月", "下週15日", "明年15日",
        "下個月下午", "下週下午3點", "下次週五", "明天~後天下午", "2026年12月10日~2026年1月10日", "明天明天",
    ])
    func 不合法就無法換算(text: String) {
        #expect(parse(text) == nil)
    }

    @Test(arguments: [
        ("明天", BoardPage.Range.days(from: "2026-09-30", to: "2026-09-30", label: "明天")),
        ("明天晚上", .days(from: "2026-09-30", to: "2026-09-30", label: "明天")),
        ("10月3日", .days(from: "2026-10-03", to: "2026-10-03", label: "10月3日")),
        ("下週週五", .days(from: "2026-10-09", to: "2026-10-09", label: "下週週五")),
        ("週五", .days(from: "2026-10-02", to: "2026-10-02", label: "週五")),
        ("下個月", .days(from: "2026-10-01", to: "2026-10-31", label: "下個月")),
        ("下個月15日", .days(from: "2026-10-15", to: "2026-10-15", label: "下個月15日")),
        ("明年1月", .days(from: "2027-01-01", to: "2027-01-31", label: "明年1月")),
        ("目前", .days(from: "2026-09-29", to: "2026-10-05", label: "目前")),
        ("11月", .days(from: "2026-11-01", to: "2026-11-30", label: "11月")),
        ("12月10日~1月10日", .days(from: "2026-12-10", to: "2027-01-10", label: nil)),
    ])
    func 查詢時黑板的範圍是說法本身(text: String, range: BoardPage.Range) {
        #expect(parse(text)?.focus == range)
    }

    @Test func 下次與只有時刻沒有黑板範圍() {
        #expect(parse("下次")?.focus == nil)
        #expect(parse("晚上")?.focus == nil)
    }

    @Test func 黑板標題() {
        #expect(BoardPage(range: parse("11月")!.focus!).title == "11月 11/1–11/30")
        #expect(BoardPage(range: parse("12月10日~1月10日")!.focus!).title == "12/10–1/10")
    }
}

// MARK: - 指令

@MainActor
struct CommandExecutorTests {

    /// 2026-09-29 是星期二；黑板一開始是「目前」9/29–10/5，「完成」不勾。
    private static let today = try! Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse("2026-09-29")
    private let board = Board(today: Self.today)

    private func makeStore() throws -> TodoStore {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-25", content: "買牛奶")
        try store.addTodo(date: "2026-10-02", content: "買牛奶")
        try store.addTodo(date: "2026-10-09", content: "部門會議")
        try store.addTodo(date: "2026-09-18", content: "部門會議")
        return store
    }

    private func run(_ store: TodoStore, _ command: Command) -> CommandOutcome {
        CommandExecutor(store: store, board: board, today: Self.today).execute(command)
    }

    @Test func 新增換算日期_黑板已涵蓋就不動() throws {
        let store = TodoStore()
        #expect(run(store, Command(.addTodo, date: "明天", content: "買水果")) .message == ("已新增 ☐ 9/30（三） 買水果"))
        #expect(board.page.title == "目前 9/29–10/5")
        #expect(!board.canGoBack)
    }

    @Test func 新增帶時刻_沒說時刻就沒有時間() throws {
        let store = TodoStore()
        #expect(run(store, Command(.addTodo, date: "明天下午7點", content: "看電影")) .message == ("已新增 ☐ 9/30（三） 19:00 看電影"))
        _ = run(store, Command(.addTodo, date: "明天", content: "買水果"))
        #expect(store.todos.map(\.time) == ["19:00", nil])
    }

    @Test func 修改只有時刻時只改時間_只有日期時保留時間() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-30", time: "19:00", content: "看牙醫")
        _ = run(store, Command(.modifyTodo, keyword: "看牙醫", newDate: "晚上"))
        #expect(store.todos.first.map { [$0.date, $0.time] } == ["2026-09-30", "18:00"])
        _ = run(store, Command(.modifyTodo, keyword: "看牙醫", newDate: "後天"))
        #expect(store.todos.first.map { [$0.date, $0.time] } == ["2026-10-01", "18:00"])
    }

    @Test func 有時刻時只找那個時間的() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-30", time: "18:00", content: "找工作")
        try store.addTodo(date: "2026-09-30", time: "09:00", content: "找工作")
        guard case .confirmDelete(_, let ids) = run(store, Command(.deleteTodos, date: "晚上", keyword: "找工作")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(ids == [1])
        guard case .confirmDelete(_, let all) = run(store, Command(.deleteTodos, keyword: "找工作")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(all.count == 2)
    }

    @Test func 新增後黑板保持天數平移到新日期() throws {
        let store = TodoStore()
        _ = run(store, Command(.addTodo, date: "下週週五", content: "買水果"))
        #expect(board.page.title == "10/6–10/12")
    }

    @Test func 單日的黑板平移到那一天() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "明天"))
        _ = run(store, Command(.addTodo, date: "10月2日", content: "買水果"))
        #expect(board.page.range == .days(from: "2026-10-02", to: "2026-10-02", label: nil))
    }

    @Test func 天數是偶數時多出的一天放在後面() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "10月1日~10月2日"))
        _ = run(store, Command(.addTodo, date: "10月20日", content: "買水果"))
        #expect(board.page.range == .days(from: "2026-10-20", to: "2026-10-21", label: nil))
    }

    @Test func 說法比黑板長時移到說法本身() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "明天"))
        guard case .confirmDelete(_, let ids) = run(store, Command(.deleteTodos, date: "下週", keyword: "部門會議")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(ids.count == 1)
        #expect(board.page.range == .days(from: "2026-10-05", to: "2026-10-11", label: nil))
    }

    @Test func 查詢某一天只顯示那一天() throws {
        let store = try makeStore()
        try store.addTodo(date: "2026-10-06", content: "看牙醫")
        #expect(run(store, Command(.queryTodos, date: "10月6日")).message == "1 件待辦")
        #expect(board.page.title == "10月6日 10/6（二）")
        #expect(board.visible(store.todos, today: "2026-09-29").map(\.content) == ["看牙醫"])
    }

    @Test func 修改後黑板以新日期為準() throws {
        let store = try makeStore()
        try store.addTodo(date: "2026-10-06", content: "看牙醫")
        _ = run(store, Command(.queryTodos, date: "10月6日"))
        _ = run(store, Command(.modifyTodo, keyword: "看牙醫", newDate: "明天"))
        #expect(board.page.range == .days(from: "2026-09-30", to: "2026-09-30", label: nil))
    }

    @Test func 新增沒有日期_黑板單日就用那一天() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "10月6日"))
        _ = run(store, Command(.addTodo, content: "看牙醫"))
        _ = run(store, Command(.addTodo, date: "晚上", content: "看電影"))
        #expect(store.todos.map(\.date) == ["2026-10-06", "2026-10-06"])
        #expect(store.todos.map(\.time) == [nil, "18:00"])
    }

    @Test func 新增沒有日期_黑板是目前就用今天() throws {
        let store = TodoStore()
        _ = run(store, Command(.addTodo, content: "看牙醫"))
        _ = run(store, Command(.addTodo, date: "晚上", content: "看電影"))
        #expect(store.todos.map(\.date) == ["2026-09-29", "2026-09-29"])
        #expect(store.todos.last?.time == "18:00")
    }

    @Test func 新增沒有日期_黑板超過一天就釐清() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "下週"))
        #expect(run(store, Command(.addTodo, content: "看牙醫")) == .clarify("你是指 10/5–10/11 的哪一天？"))
        #expect(run(store, Command(.addTodo, date: "晚上", content: "看牙醫")) == .clarify("你是指 10/5–10/11 的哪一天？"))
        #expect(store.todos.isEmpty)
    }

    @Test func 新增沒有日期_黑板包含今天但不是目前就釐清() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "本週"))
        #expect(run(store, Command(.addTodo, content: "看牙醫")) == .clarify("你是指 9/28–10/4 的哪一天？"))
        #expect(store.todos.isEmpty)
    }

    @Test func 新增沒有日期_黑板是所有就用今天() throws {
        let store = TodoStore()
        _ = run(store, Command(.queryTodos, date: "所有"))
        _ = run(store, Command(.addTodo, content: "看牙醫"))
        #expect(store.todos.map(\.date) == ["2026-09-29"])
    }

    @Test(arguments: [("05:30", "06:00"), ("14:00", "15:00"), ("17:59", "18:00"), ("19:00", nil)])
    func 新增今天沒說時間_推測下一個時段(now: String, time: String?) throws {
        let store = TodoStore()
        let parts = now.split(separator: ":").map { Int($0)! }
        let date = DatePhrase.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Self.today)!
        _ = CommandExecutor(store: store, board: board, today: date).execute(Command(.addTodo, date: "今天", content: "看牙醫"))
        _ = CommandExecutor(store: store, board: board, today: date).execute(Command(.addTodo, date: "明天", content: "買菜"))
        #expect(store.todos.map(\.time) == [time, nil])
    }

    @Test func 查詢日期沒有日期_黑板單日就用那一天_否則今天() throws {
        let store = TodoStore()
        #expect(run(store, Command(.queryDate)).message == "今天是 2026-09-29（星期二）")
        _ = run(store, Command(.queryTodos, date: "10月6日"))
        #expect(run(store, Command(.queryDate)).message == "這天是 2026-10-06（星期二）")
    }

    @Test func 刪除說所有_只在黑板上找() throws {
        let store = try makeStore()
        let range = board.page.range
        #expect(run(store, Command(.deleteTodos, date: "所有", keyword: "部門會議")) == .notFound)
        #expect(board.page.range == range)
    }

    @Test func 新增說了時間範圍就放棄() throws {
        let store = TodoStore()
        guard case .abandon = run(store, Command(.addTodo, date: "明天晚上7點以後", content: "看電影")) else {
            Issue.record("應該放棄")
            return
        }
        #expect(store.todos.isEmpty)
    }

    @Test func 新增只接受單日() throws {
        let store = TodoStore()
        guard case .abandon = run(store, Command(.addTodo, date: "下週", content: "買水果")) else {
            Issue.record("應該放棄")
            return
        }
        #expect(store.todos.isEmpty)
    }

    @Test func 下次_找今天起最早一筆_那一天在黑板上就不動() throws {
        let store = try makeStore()
        guard case .confirmDelete(let question, let ids) = run(store, Command(.deleteTodos, date: "下次", keyword: "買牛奶")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(question.contains("☐ 10/2（五） 買牛奶"))
        #expect(question.hasSuffix("要刪掉嗎？"))
        #expect(ids.count == 1)
        #expect(store.todos.count == 4)
        #expect(board.page.title == "目前 9/29–10/5")
    }

    @Test func 下次找不到時黑板不動() throws {
        let store = try makeStore()
        let before = board.page
        #expect(run(store, Command(.queryTodos, date: "下次", keyword: "看電影")) .message == ("找不到"))
        #expect(board.page == before)
    }

    @Test func 修改刪除只找黑板上看得到的() throws {
        let store = try makeStore()
        #expect(run(store, Command(.deleteTodos, keyword: "部門會議")) == .notFound)

        _ = run(store, Command(.queryTodos, date: "所有", keyword: "部門會議"))
        guard case .confirmDelete(_, let ids) = run(store, Command(.deleteTodos, keyword: "部門會議")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(ids.count == 2, "範圍內過去的待辦也看得到")
    }

    @Test func 完成被隱藏就找不到_勾選後找得到() throws {
        let store = try makeStore()
        let date = "10月2日"
        _ = run(store, Command(.setDone, date: date, keyword: "買牛奶", isDone: true))
        #expect(run(store, Command(.setDone, date: date, keyword: "買牛奶", isDone: false)) == .notFound)
        _ = run(store, Command(.setDisplay, showDone: true))
        #expect(run(store, Command(.setDone, date: date, keyword: "買牛奶", isDone: false)) .message == ("已將 2026-10-02 買牛奶 設為未完成"))
    }

    @Test func 設定完成找到多筆就釐清_格式和黑板相同() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "所有"))
        #expect(run(store, Command(.setDone, keyword: "部門會議", isDone: true))
            == .clarify("有 2 筆部門會議：\n☐ 9/18（五） 部門會議\n☐ 10/9（五） 部門會議\n要哪一筆？"))
        #expect(store.todos.allSatisfy { !$0.isDone })
    }

    @Test func 設定完成有日期就先移動黑板() throws {
        let store = try makeStore()
        #expect(run(store, Command(.setDone, date: "下週週五", keyword: "部門會議", isDone: true))
            .message == ("已將 2026-10-09 部門會議 設為已完成"))
        #expect(board.page.title == "10/6–10/12")
    }

    @Test func 修改日期後黑板平移到新日期() throws {
        let store = try makeStore()
        _ = run(store, Command(.modifyTodo, date: "下次", keyword: "買牛奶", newDate: "下週週六"))
        #expect(store.todos.contains { $0.date == "2026-10-10" && $0.content == "買牛奶" })
        #expect(board.page.title == "10/7–10/13")
    }

    @Test func 查詢只有關鍵字_範圍不變_關鍵字成為查詢條件() throws {
        let store = try makeStore()
        let range = board.page.range
        #expect(run(store, Command(.queryTodos, keyword: "買牛奶")) .message == ("1 件待辦"))
        #expect(board.page.range == range && board.page.keyword == "買牛奶")
        #expect(board.visible(store.todos, today: "2026-09-29").map(\.date) == ["2026-10-02"])
    }

    @Test func 查詢所有() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "所有", keyword: "部門會議"))
        #expect(board.page.range == .everything && board.page.keyword == "部門會議")
        #expect(board.visible(store.todos, today: "2026-09-29").map(\.date) == ["2026-09-18", "2026-10-09"], "過去的也顯示")
    }

    private func eveningStore() throws -> TodoStore {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-30", time: "19:00", content: "看電影")
        try store.addTodo(date: "2026-09-30", time: "09:00", content: "開會")
        try store.addTodo(date: "2026-09-30", content: "買菜")
        try store.addTodo(date: "2026-10-01", time: "20:00", content: "看書")
        return store
    }

    @Test func 查詢的時間成為查詢條件_沒有時間的不列出() throws {
        let store = try eveningStore()
        #expect(run(store, Command(.queryTodos, date: "明天晚上")).message == "1 件待辦")
        #expect(board.page.range == .days(from: "2026-09-30", to: "2026-09-30", label: "明天"))
        #expect(board.page.time == TimeRange(from: "18:00", to: nil, includesEnd: false))
        #expect(board.visible(store.todos, today: "2026-09-29").map(\.content) == ["看電影"])
    }

    @Test func 查詢只有時間_範圍不變() throws {
        let store = try eveningStore()
        let range = board.page.range
        #expect(run(store, Command(.queryTodos, date: "晚上")).message == "2 件待辦")
        #expect(board.page.range == range)
        #expect(board.visible(store.todos, today: "2026-09-29").map(\.content) == ["看電影", "看書"])
    }

    @Test func 查詢條件是時間範圍加關鍵字() throws {
        let store = try eveningStore()
        _ = run(store, Command(.queryTodos, date: "明天晚上", keyword: "電影"))
        #expect(board.page.condition == "18:00 以後 電影")
    }

    @Test func 新增的待辦被查詢條件擋住_清除條件_範圍不變() throws {
        let store = try eveningStore()
        _ = run(store, Command(.queryTodos, date: "明天晚上", keyword: "看"))
        _ = run(store, Command(.addTodo, date: "明天早上", content: "買菜"))
        #expect(board.page.range == .days(from: "2026-09-30", to: "2026-09-30", label: "明天"))
        #expect(board.page.time == nil && board.page.keyword == nil)
    }

    @Test func 新增的待辦符合查詢條件_保留條件() throws {
        let store = try eveningStore()
        _ = run(store, Command(.queryTodos, date: "明天晚上", keyword: "看"))
        _ = run(store, Command(.addTodo, date: "明天晚上8點", content: "看書"))
        #expect(board.page.condition == "18:00 以後 看")
    }

    @Test func 修改後被查詢條件擋住_清除條件() throws {
        let store = try eveningStore()
        _ = run(store, Command(.queryTodos, date: "明天", keyword: "電影"))
        _ = run(store, Command(.modifyTodo, keyword: "電影", content: "聚餐"))
        #expect(board.page.keyword == nil)
    }

    @Test func 查詢有日期移到那個範圍_沒有結果說找不到() throws {
        let store = try makeStore()
        #expect(run(store, Command(.queryTodos, date: "明天")) .message == ("找不到"))
        #expect(board.page.title == "明天 9/30（三）" && board.page.keyword == nil)
    }

    @Test func 黑板已涵蓋就不動_保留查詢條件() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "所有", keyword: "買牛奶"))
        _ = run(store, Command(.deleteTodos, date: "10月2日"))
        #expect(board.page.range == .everything && board.page.keyword == "買牛奶")
    }

    @Test func 黑板沒涵蓋就移動_清除查詢條件() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "明天", keyword: "買牛奶"))
        _ = run(store, Command(.deleteTodos, date: "10月2日"))
        #expect(board.page.range == .days(from: "2026-10-02", to: "2026-10-02", label: nil) && board.page.keyword == nil)
    }

    @Test func 新增在黑板範圍內不移動() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "下個月", keyword: "買"))
        _ = run(store, Command(.addTodo, date: "10月5日", content: "買水果"))
        #expect(board.page.title == "下個月 10/1–10/31" && board.page.keyword == "買")
    }

    @Test func 找目標只找說法本身的日期_不是黑板的整個範圍() throws {
        let store = try makeStore()
        try store.addTodo(date: "2026-10-06", content: "部門會議")
        #expect(run(store, Command(.setDone, date: "下週週五", keyword: "部門會議", isDone: true))
            .message == ("已將 2026-10-09 部門會議 設為已完成"))
        #expect(board.page.title == "10/6–10/12")
        #expect(store.todos.filter(\.isDone).map(\.date) == ["2026-10-09"])
    }

    @Test func 刪除全部是黑板上看得到的全部() throws {
        let store = try makeStore()
        _ = run(store, Command(.queryTodos, date: "下個月"))
        guard case .confirmDelete(let question, let ids) = run(store, Command(.deleteTodos)) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(ids.count == 2)
        #expect(question.hasPrefix("即將刪除所有待辦（2 項）"))
        // 念的期間回答會被當成回音丟掉：固定的說法不能含回答的關鍵字（見 docs/specs/spoken-report.md 的「念問題」）。
        let lines = question.components(separatedBy: "\n")
        let fixed = ConfirmationKeywords.normalized(lines.first! + lines.last!)
        for word in ConfirmationKeywords.yes.union(ConfirmationKeywords.no) {
            #expect(!fixed.contains(word), "說法含回答的關鍵字「\(word)」")
        }
    }

    @Test func 刪除完成_完成沒勾就自動勾選() throws {
        let store = try makeStore()
        _ = run(store, Command(.setDone, date: "10月2日", keyword: "買牛奶", isDone: true))
        guard case .confirmDelete(let question, let ids) = run(store, Command(.deleteTodos, isDone: true)) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(board.showDone)
        #expect(ids.count == 1)
        #expect(question.hasPrefix("即將刪除已完成的待辦（1 項）"))
    }

    @Test func 沒有日期的待辦_沒說日期找得到_說了日期找不到_變動不移動黑板() throws {
        let store = TodoStore(todos: [Todo(id: 1, content: "買牙膏")])
        #expect(run(store, Command(.setDone, date: "明天", keyword: "買牙膏")) == .notFound)
        #expect(run(store, Command(.setDone, keyword: "買牙膏")).message == "已將 買牙膏 設為已完成")
        #expect(!board.canGoBack)
    }

    @Test func 沒有日期的待辦_修改加上日期後讓新日期看得到() throws {
        let store = TodoStore(todos: [Todo(id: 1, content: "買牙膏")])
        #expect(run(store, Command(.modifyTodo, keyword: "買牙膏", newDate: "10月9日")).message == "已將 買牙膏 改為 2026-10-09 買牙膏")
        #expect(board.page.dates == "10/6–10/12")
    }

    @Test func 下次不算沒有日期的待辦() throws {
        let store = TodoStore(todos: [Todo(id: 1, content: "買牙膏"), Todo(id: 2, date: "2026-10-20", content: "買牙膏")])
        _ = run(store, Command(.queryTodos, date: "下次", keyword: "買牙膏"))
        #expect(board.page.dates == "10/20（二）")
    }

    @Test func 查詢日期不移動黑板() {
        let store = TodoStore()
        let before = board.page
        #expect(run(store, Command(.queryDate, date: "下週週五")) .message == ("下週週五是 2026-10-09（星期五）"))
        #expect(board.page == before)
    }

    @Test func 設定顯示() {
        let store = TodoStore()
        #expect(run(store, Command(.setDisplay, showDone: true)) .message == ("完成：顯示"))
        #expect(board.showDone)
        guard case .abandon = run(store, Command(.setDisplay)) else {
            Issue.record("沒給應該放棄")
            return
        }
    }

    // MARK: 編號

    /// 「目前」9/29–10/5 上的 1～5：9/30 A、10/1 B、10/2 C、10/3 D、沒有日期的 E。
    private func numberedStore() throws -> TodoStore {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-30", time: "09:00", content: "A")
        try store.addTodo(date: "2026-10-01", content: "B")
        try store.addTodo(date: "2026-10-02", content: "C")
        try store.addTodo(date: "2026-10-03", content: "D")
        store.replace(with: store.todos + [Todo(id: 99, content: "E")])
        return store
    }

    private func ids(_ store: TodoStore, _ contents: String...) -> [Int] {
        contents.compactMap { content in store.todos.first { $0.content == content }?.id }
    }

    @Test func 編號刪除_一段全部列入確認() throws {
        let store = try numberedStore()
        guard case .confirmDelete(let question, let found) = run(store, Command(.deleteTodos, number: "2~3")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(found == ids(store, "B", "C"))
        #expect(question.hasPrefix("即將刪除第2~3項（2 項）：\n☐ 10/1（四） B\n☐ 10/2（五） C"))
    }

    @Test func 編號包括沒有日期的待辦() throws {
        let store = try numberedStore()
        #expect(run(store, Command(.setDone, number: "5", isDone: true)).message == "已將 E 設為已完成")
        #expect(store.todos.first { $0.content == "E" }?.isDone == true)
    }

    @Test func 編號修改一段_每一筆都改_不釐清() throws {
        let store = try numberedStore()
        let outcome = run(store, Command(.modifyTodo, number: "1~2", newDate: "後天"))
        #expect(outcome.message == "已將 2026-09-30 09:00 A 改為 2026-10-01 09:00 A\n已將 2026-10-01 B 改為 2026-10-01 B")
        #expect(store.todos.filter { ["A", "B"].contains($0.content) }.allSatisfy { $0.date == "2026-10-01" })
        guard case .modified(let before, let after)? = outcome.report else {
            Issue.record("應該是修改的結果")
            return
        }
        #expect(before.map(\.content) == ["A", "B"] && after.map(\.date) == ["2026-10-01", "2026-10-01"])
    }

    @Test func 編號設定完成一段() throws {
        let store = try numberedStore()
        #expect(run(store, Command(.setDone, number: "3~4", isDone: true)).message == "已將 2026-10-02 C 設為已完成\n已將 2026-10-03 D 設為已完成")
    }

    /// 實測：「二到三項移到明天」拆成兩條，第一條讓黑板重排，第二條改到了別筆。
    @Test func 同一句話裡修改後重排_編號仍對到原本那幾筆() throws {
        let store = try numberedStore()
        board.fixNumbers(store.todos, today: TodoStore.dayString(Self.today))
        _ = run(store, Command(.modifyTodo, number: "1", newDate: "10月2日"))
        #expect(run(store, Command(.setDone, number: "2", isDone: true)).message == "已將 2026-10-01 B 設為已完成")
    }

    @Test func 同一句話裡刪除後_後面的編號不前移() throws {
        let store = try numberedStore()
        board.fixNumbers(store.todos, today: TodoStore.dayString(Self.today))
        store.replace(with: store.todos.filter { $0.content != "A" })
        #expect(run(store, Command(.setDone, number: "2", isDone: true)).message == "已將 2026-10-01 B 設為已完成")
        #expect(run(store, Command(.setDone, number: "1", isDone: true)) == .notFound)
    }

    @Test func 換頁後編號對到新的那一頁() throws {
        let store = try numberedStore()
        board.fixNumbers(store.todos, today: TodoStore.dayString(Self.today))
        _ = run(store, Command(.queryTodos, keyword: "C"))
        #expect(run(store, Command(.setDone, number: "1", isDone: true)).message == "已將 2026-10-02 C 設為已完成")
    }

    @Test func 有編號就不看日期與關鍵字_也不移動黑板() throws {
        let store = try numberedStore()
        let before = board.page
        guard case .confirmDelete(_, let found) = run(store, Command(.deleteTodos, date: "下週", keyword: "X", number: "1")) else {
            Issue.record("應該要求確認")
            return
        }
        #expect(found == ids(store, "A"))
        #expect(board.page == before)
    }

    @Test(arguments: [("6", "黑板上只有 1～5"), ("0", "黑板上只有 1～5"), ("3~2", "黑板上只有 1～5"), ("4~6", "黑板上只有 1～5"), ("abc", "看不懂編號「abc」")])
    func 編號不合法就放棄(number: String, reason: String) throws {
        let store = try numberedStore()
        #expect(run(store, Command(.deleteTodos, number: number)) == .abandon(reason))
    }

    @Test func 黑板是空的時編號放棄() {
        #expect(run(TodoStore(), Command(.setDone, number: "1", isDone: true)) == .abandon("黑板上沒有待辦"))
    }

    @Test func 日期無法換算就放棄() throws {
        let store = try makeStore()
        guard case .abandon = run(store, Command(.deleteTodos, date: "下個月週五")) else {
            Issue.record("應該放棄")
            return
        }
    }
}

// MARK: - 黑板

struct BoardTests {

    private static let today = try! TodoStore.dayFormat.parse("2026-09-29")
    private let todos = [
        Todo(id: 1, date: "2026-09-25", content: "買牛奶"),
        Todo(id: 2, date: "2026-09-20", content: "繳房租", isDone: true),
        Todo(id: 3, date: "2026-10-02", content: "看牙醫", isDone: true),
        Todo(id: 4, date: "2026-10-01", content: "部門會議"),
    ]

    @Test func 啟動是目前_沒有上一頁下一頁() {
        let board = Board(today: Self.today)
        #expect(board.page.title == "目前 9/29–10/5")
        #expect(!board.canGoBack && !board.canGoForward)
    }

    @Test func 啟動從存的那一頁開始_查詢條件也還原_沒有上一頁() {
        let page = BoardPage(range: .days(from: "2026-10-05", to: "2026-10-11", label: "下週"), keyword: "會議", time: TimeRange(from: "18:00", to: nil, includesEnd: true))
        let board = Board(today: Self.today, saved: BoardPage.Saved(day: "2026-09-29", page: page))
        #expect(board.page == page, "同一天打開，說法保留")
        #expect(!board.canGoBack && !board.canGoForward)
    }

    @Test func 存的頁照今天換算() {
        let tomorrow = BoardPage(range: .days(from: "2026-09-29", to: "2026-09-29", label: "明天"), keyword: "牙醫")
        #expect(BoardPage.Saved(day: "2026-09-28", page: tomorrow).restored(today: Self.today)
            == BoardPage(range: .days(from: "2026-09-29", to: "2026-09-29", label: nil), keyword: "牙醫"), "隔天打開，日期不變、拿掉說法")
        let current = BoardPage(range: .days(from: "2026-09-20", to: "2026-09-26", label: "目前"), keyword: "會議")
        #expect(BoardPage.Saved(day: "2026-09-20", page: current).restored(today: Self.today)
            == BoardPage(range: .days(from: "2026-09-29", to: "2026-10-05", label: "目前"), keyword: "會議"), "「目前」從今天重算")
        let everything = BoardPage(range: .everything)
        #expect(BoardPage.Saved(day: "2026-09-01", page: everything).restored(today: Self.today) == everything)
        #expect(Board(today: Self.today, saved: nil).page.title == "目前 9/29–10/5", "沒存過是「目前」")
    }

    @Test func 存的頁可以存成JSON再讀回來() throws {
        let saved = BoardPage.Saved(day: "2026-09-29", page: BoardPage(range: .days(from: "2026-10-05", to: "2026-10-11", label: "下週"), keyword: "會議", time: TimeRange(from: "18:00", to: nil, includesEnd: true)))
        #expect(try JSONDecoder().decode(BoardPage.Saved.self, from: JSONEncoder().encode(saved)) == saved)
    }

    @Test func 範圍內全部顯示_包括過去_只有完成看checkbox() {
        let page = BoardPage(range: .everything)
        #expect(page.visible(todos, showDone: false, today: "2026-09-29").map(\.id) == [1, 4])
        #expect(page.visible(todos, showDone: true, today: "2026-09-29").map(\.id) == [2, 1, 4, 3])
    }

    @Test func 沒有日期的待辦在任何範圍都顯示在最後() {
        let undated = [Todo(id: 5, content: "買牙膏"), Todo(id: 6, content: "繳費", isDone: true)]
        let all = todos + undated
        let past = BoardPage(range: .days(from: "2026-09-21", to: "2026-09-27", label: "上週"))
        #expect(past.visible(all, showDone: false, today: "2026-09-29").map(\.id) == [1, 5])
        #expect(BoardPage(range: .everything).visible(all, showDone: false, today: "2026-09-29").map(\.id) == [1, 4, 5])
        var done = BoardPage(range: .days(from: "2026-09-29", to: "2026-09-29", label: nil))
        #expect(done.visible(all, showDone: true, today: "2026-09-29").map(\.id) == [5, 6], "「完成」照樣適用")
        done.keyword = "牙膏"
        #expect(done.visible(all, showDone: true, today: "2026-09-29").map(\.id) == [5], "關鍵字照樣適用")
        done.keyword = nil
        done.time = TimeRange(from: "18:00", to: nil, includesEnd: true)
        #expect(done.visible(all, showDone: true, today: "2026-09-29").isEmpty, "時間範圍下沒有時間的不顯示")
    }

    @Test func 依日期分組_近幾天只寫詞_7天內一天一組_其他依月份() {
        let dates = ["2026-09-15", "2026-09-30", "2026-10-06", "2026-10-07", "2026-10-07", "2026-10-08", "2026-10-09",
                     "2026-10-13", "2026-10-14", "2026-10-31", "2026-11-02", "2027-01-05"]
        let todos = dates.enumerated().map { Todo(id: $0.offset + 1, date: $0.element, content: "\($0.offset)") } + [Todo(id: 99, content: "沒日期")]
        let sections = BoardSection.make(todos, today: "2026-10-07")
        #expect(sections.map(\.title) == ["9月", "9/30（三）", "昨天", "今天", "明天", "後天", "10/13（二）", "10月其餘", "11月", "2027年1月", "沒有日期"])
        #expect(sections.map(\.firstNumber) == [1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13])
        #expect(sections.map(\.todos.count) == [1, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1])
        #expect(sections.filter(\.isMonth).map(\.title) == ["9月", "10月其餘", "11月", "2027年1月"])
        #expect(sections.filter(\.isToday).map(\.title) == ["今天"])
    }

    /// 實測：「買水」從昨天移到明天後，畫面出現兩個「2.」；一層的清單每筆帶著自己的編號。
    @Test func 一層清單的編號跨組連續() {
        let todos = [
            Todo(id: 1, date: "2026-10-06", content: "買飯"),
            Todo(id: 3, date: "2026-10-07", time: "18:00", content: "買西瓜"),
            Todo(id: 4, date: "2026-10-09", time: "15:00", content: "買水果"),
            Todo(id: 2, date: "2026-10-09", time: "15:00", content: "買水"),
            Todo(id: 5, date: "2026-11-02", content: "買水果"),
        ]
        let numbers = BoardSection.lines(todos, today: "2026-10-08").compactMap { line -> String? in
            guard case .todo(let todo, let number) = line else { return nil }
            return "\(number) \(todo.content)"
        }
        #expect(numbers == ["1 買飯", "2 買西瓜", "3 買水果", "4 買水", "5 買水果"])
    }

    /// 實測：月份組的每行多一欄日期，和一天一組的行對不齊；改成組裡每換一天加日期小標題。
    @Test func 月份組裡每換一天有日期小標題_行裡不寫日期() {
        let todos = [
            Todo(id: 1, date: "2026-10-12", time: "09:00", content: "吃飯"),
            Todo(id: 2, date: "2026-10-20", content: "a"),
            Todo(id: 3, date: "2026-11-02", time: "12:00", content: "買水果"),
            Todo(id: 4, date: "2026-11-02", content: "b"),
            Todo(id: 5, date: "2026-11-05", content: "c"),
        ]
        let lines = BoardSection.lines(todos, today: "2026-10-09").map { line -> String in
            switch line {
            case .header(let title, _, let isMonth): isMonth ? "[\(title)]" : "<\(title)>"
            case .todo(let todo, let number): "\(number) \(todo.content)"
            }
        }
        #expect(lines == ["<10/12（一）>", "1 吃飯", "[10月其餘]", "<10/20（二）>", "2 a",
                          "[11月]", "<11/2（一）>", "3 買水果", "4 b", "<11/5（四）>", "5 c"])
    }

    @Test func 這個月7天以前的過去依月份() {
        let todos = [Todo(id: 1, date: "2026-10-05", content: "a"), Todo(id: 2, date: "2026-10-20", content: "b")]
        #expect(BoardSection.make(todos, today: "2026-10-20").map(\.title) == ["10月", "今天"])
    }

    @Test func 沒有待辦就沒有分組() {
        #expect(BoardSection.make([], today: "2026-10-07").isEmpty)
    }

    @Test func 同一天依時間排序() {
        let page = BoardPage(range: .everything)
        let day = [
            Todo(id: 1, date: "2026-10-01", time: "18:00", content: "晚餐"),
            Todo(id: 2, date: "2026-10-01", time: "09:00", content: "開會"),
        ]
        #expect(page.visible(day, showDone: false, today: "2026-09-29").map(\.id) == [2, 1])
    }

    @Test func 查詢條件只留符合的() {
        let page = BoardPage(range: .everything, keyword: "會議")
        #expect(page.visible(todos, showDone: false, today: "2026-09-29").map(\.id) == [4])
    }

    @Test func 標題() {
        #expect(BoardPage(range: .everything).title.isEmpty)
        #expect(BoardPage(range: .days(from: "2027-01-01", to: "2027-12-31", label: "明年")).title == "明年 2027")
        #expect(BoardPage(range: .days(from: "2026-10-03", to: "2026-10-09", label: nil)).title == "10/3–10/9")
    }

    @Test func 導覽紀錄_相同的頁不加入_中間加入新頁清空之後() {
        let board = Board(today: Self.today)
        board.move(to: .everything)
        board.move(to: .everything)
        #expect(board.pages.count == 2)

        board.goBack()
        #expect(board.page.title == "目前 9/29–10/5")
        #expect(board.canGoForward)

        board.move(to: .everything, keyword: "買牛奶")
        #expect(!board.canGoForward)
        #expect(board.pages.count == 2)
    }

    @Test func 換checkbox不加入導覽紀錄_上一頁下一頁不改checkbox() {
        let board = Board(today: Self.today)
        board.setDisplay(showDone: true)
        #expect(!board.canGoBack)
        board.move(to: .everything)
        board.setDisplay(showDone: false)
        #expect(board.pages.count == 2)
        board.goBack()
        #expect(!board.showDone)
        board.setDisplay(showDone: true)
        board.goForward()
        #expect(board.page.range == .everything && board.showDone)
    }
}

// MARK: - 刪除確認

struct ConfirmationKeywordsTests {

    @Test(arguments: ["好", "好的。", "OK", "確定！", "yes", "全部。", "同意。"])
    func yes(text: String) {
        #expect(ConfirmationKeywords.answer(text) == true)
    }

    @Test(arguments: ["不", "不要", "取消。", "算了", "No"])
    func no(text: String) {
        #expect(ConfirmationKeywords.answer(text) == false)
    }

    @Test(arguments: ["不好", "好啊刪吧", "等一下"])
    func 判斷不出來交給AI(text: String) {
        #expect(ConfirmationKeywords.answer(text) == nil)
    }
}

// MARK: - 補救

struct RecoveryKeywordsTests {

    @Test(arguments: [
        ("復原", RecoveryAction.undo), ("上一步。", .undo), ("Undo", .undo),
        ("重做", .redo), ("下一步", .redo), ("redo", .redo),
        ("重試", .retry), ("重複", .retry), ("再試一次！", .retry), ("Retry", .retry),
        ("略過", .skip), ("跳過。", .skip), ("pass", .skip),
    ])
    func 比對關鍵字(text: String, action: RecoveryAction) {
        #expect(RecoveryKeywords.action(text) == action)
    }

    @Test(arguments: ["復原一下", "把買牛奶略過", "好"])
    func 不完全相等就不算(text: String) {
        #expect(RecoveryKeywords.action(text) == nil)
    }
}

struct TodoHistoryTests {

    private let milk = Todo(id: 1, date: "2026-10-02", content: "買牛奶")
    private let fruit = Todo(id: 2, date: "2026-10-03", content: "買水果")

    @Test func 沒有改變就不記錄() {
        var history = TodoHistory()
        history.record(before: [milk], after: [milk])
        #expect(!history.canUndo)
    }

    @Test func undo回到上一個狀態_redo回到undo之前() {
        var history = TodoHistory()
        history.record(before: [milk], after: [milk, fruit])
        #expect(history.undo(current: [milk, fruit]) == [milk])
        #expect(!history.canUndo)
        #expect(history.redo(current: [milk]) == [milk, fruit])
        #expect(!history.canRedo)
        #expect(history.canUndo)
    }

    @Test func 連續undo() {
        var history = TodoHistory()
        history.record(before: [], after: [milk])
        history.record(before: [milk], after: [milk, fruit])
        #expect(history.undo(current: [milk, fruit]) == [milk])
        #expect(history.undo(current: [milk]) == [])
        #expect(history.undo(current: []) == nil)
    }

    @Test func 新的改變清空redo() {
        var history = TodoHistory()
        history.record(before: [], after: [milk])
        _ = history.undo(current: [milk])
        history.record(before: [], after: [fruit])
        #expect(!history.canRedo)
    }

    @Test func 有變化的日期_改日期取之後的_沒有日期的不算() {
        var moved = milk
        moved.date = "2026-10-09"
        #expect(TodoHistory.changedDays(from: [milk, fruit], to: [moved]) == ["2026-10-03", "2026-10-09"])
        #expect(TodoHistory.changedDays(from: [], to: [Todo(id: 3, content: "買牙膏")]).isEmpty)
    }

    @Test func 延遲讀取的待辦補進每一個狀態_undo後還在() {
        let done = Todo(id: 9, date: "2026-09-01", content: "繳房租", isDone: true)
        var history = TodoHistory()
        history.record(before: [], after: [milk])
        history.record(before: [milk], after: [milk, fruit])
        history.insert([done])
        #expect(history.undo(current: [milk, fruit, done]) == [milk, done])
        #expect(history.undo(current: [milk, done]) == [done])
        #expect(history.redo(current: [done]) == [milk, done])
    }

    @Test func 回報資料的差異() {
        var done = milk
        done.isDone = true
        #expect(TodoHistory.changes(from: [milk, fruit], to: [milk]) == ["移除 ☐ 10/3（六） 買水果"])
        #expect(TodoHistory.changes(from: [milk], to: [milk, fruit]) == ["加回 ☐ 10/3（六） 買水果"])
        #expect(TodoHistory.changes(from: [done], to: [milk]) == ["改為 ☐ 10/2（五） 買牛奶"])
        #expect(TodoHistory.changes(from: [milk], to: [done]) == ["改為 ☑ 10/2（五） 買牛奶"])
    }

    @Test func 外部變動的差異_帶id與加引號的內容() {
        let renumbered = Todo(id: 7, date: milk.date, content: milk.content)
        #expect(TodoHistory.storageChanges(from: [milk], to: [renumbered])
            == ["移除 #\(milk.id) ☐ 2026-10-02 -「買牛奶」", "新增 #7 ☐ 2026-10-02 -「買牛奶」"])
        let spaced = Todo(id: milk.id, date: milk.date, time: "09:00", content: "買牛奶 ")
        #expect(TodoHistory.storageChanges(from: [spaced], to: [milk])
            == ["修改 #\(milk.id) ☐ 2026-10-02 09:00「買牛奶 」 → ☐ 2026-10-02 -「買牛奶」"])
        #expect(TodoHistory.storageChanges(from: [milk], to: [milk]).isEmpty)
    }
}

extension CommandOutcome {
    /// 完成時回話的文字；結構化的結果另外測。
    var message: String? {
        if case .done(let message, _) = self { message } else { nil }
    }

    var report: Report? {
        if case .done(_, let report) = self { report } else { nil }
    }
}

// MARK: - 語音報告

struct CommandReportTests {

    /// 2026-09-29 是星期二；黑板一開始是「目前」9/29–10/5。
    private static let today = try! Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse("2026-09-29")
    private let board = Board(today: Self.today)

    private func run(_ store: TodoStore, _ command: Command) -> CommandOutcome {
        CommandExecutor(store: store, board: board, today: Self.today).execute(command)
    }

    @Test func 新增回傳新增的待辦() throws {
        let store = TodoStore()
        let outcome = run(store, Command(.addTodo, date: "明天", content: "買水果"))
        #expect(outcome.report == .added(try #require(store.todos.first)))
    }

    @Test func 修改回傳修改前後() throws {
        let store = TodoStore()
        let before = try store.addTodo(date: "2026-09-30", time: "12:00", content: "看牙醫")
        let outcome = run(store, Command(.modifyTodo, keyword: "看牙醫", newDate: "下午1點"))
        #expect(outcome.report == .modified(before: [before], after: [try #require(store.todos.first)]))
    }

    @Test func 設定完成回傳待辦與狀態() throws {
        let store = TodoStore()
        let todo = try store.addTodo(date: "2026-09-30", content: "買牛奶")
        #expect(run(store, Command(.setDone, keyword: "買牛奶", isDone: true)).report == .setDone([todo], isDone: true))
    }

    @Test func 查詢回傳黑板上的項目() throws {
        let store = TodoStore()
        try store.addTodo(date: "2026-09-30", content: "買牛奶")
        try store.addTodo(date: "2026-10-01", content: "看牙醫")
        let outcome = run(store, Command(.queryTodos, date: "本週"))
        #expect(outcome.report == .queried(board.visible(store.todos, today: "2026-09-29")))
        #expect(outcome.report.map { if case .queried(let todos) = $0 { todos.count } else { 0 } } == 2)
    }

    @Test func 查詢日期回傳說法與範圍() {
        #expect(run(TodoStore(), Command(.queryDate, date: "明天")).report == .date(phrase: "明天", from: "2026-09-30", to: "2026-09-30"))
    }

    @Test func 設定顯示沒有報告() {
        #expect(run(TodoStore(), Command(.setDisplay, showDone: true)).report == nil)
    }
}

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

    @Test func 時刻依時段念() {
        #expect(SpokenReport.time("00:00") == "凌晨0點")
        #expect(SpokenReport.time("06:00") == "清晨6點")
        #expect(SpokenReport.time("09:15") == "早上9點15分")
        #expect(SpokenReport.time("12:00") == "中午12點")
        #expect(SpokenReport.time("13:30") == "下午1點30分")
        #expect(SpokenReport.time("18:00") == "晚上6點")
    }

    @Test func 日期念月日星期() {
        #expect(SpokenReport.day("2026-10-09") == "10月9日星期五")
    }

    @Test func 新增一筆與多筆() {
        let a = todo("2026-10-09", content: "a")
        #expect(SpokenReport.compose([.added(a)], readAll: false)?.text == "已新增一個待辦事項。")
        #expect(SpokenReport.compose([.added(a), .added(a)], readAll: false)?.text == "已新增 2 個待辦事項。")
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
}

struct ReportKeywordsTests {

    @Test func 要不要() {
        #expect(ReportKeywords.moreAnswer("好。") == true)
        #expect(ReportKeywords.moreAnswer("要") == true)
        #expect(ReportKeywords.moreAnswer("全部念出來") == true)
        #expect(ReportKeywords.moreAnswer("繼續") == true)
        #expect(ReportKeywords.moreAnswer("不要") == false)
        #expect(ReportKeywords.moreAnswer("停止") == false)
        #expect(ReportKeywords.moreAnswer("明天看牙醫") == nil)
    }

    @Test func 全部念完() {
        #expect(ReportKeywords.isReadAll("全部念出來！"))
        #expect(!ReportKeywords.isReadAll("下週有什麼事，全部念出來"))
        #expect(ReportKeywords.containsReadAll("下週有什麼事，全部念出來"))
        #expect(!ReportKeywords.containsReadAll("下週有什麼事"))
    }

    @Test func 停止與開關() {
        #expect(ReportKeywords.isStop("停止。"))
        #expect(!ReportKeywords.isStop("停止聆聽"))
        #expect(ReportKeywords.toggle("關閉語音報告") == false)
        #expect(ReportKeywords.toggle("打開語音報告") == true)
        #expect(ReportKeywords.toggle("關閉語音") == nil)
    }
}


// 備份暫停（見 docs/specs/backup.md）；程式恢復時一起恢復。
/*
// MARK: - 備份

struct BackupTests {

    private let todos = [
        Todo(id: 3, date: "2026-10-05", time: "09:00", content: "看牙醫", isDone: true, reminderID: "r1"),
        Todo(id: 7, date: "2026-10-06", content: "買牙膏", isDemo: true),
    ]

    @Test func 建立後讀回內容相同_不帶id與示範資料() throws {
        let read = try Backup.read(Backup.make(todos))
        #expect(read.map(\.date) == ["2026-10-05", "2026-10-06"])
        #expect(read.map(\.time) == ["09:00", nil])
        #expect(read.map(\.content) == ["看牙醫", "買牙膏"])
        #expect(read.map(\.isDone) == [true, false])
        #expect(read.map(\.reminderID) == ["r1", nil])
        #expect(read.allSatisfy { !$0.isDemo })
    }

    @Test func 沒有的欄位不輸出() {
        let text = Backup.make([todos[1]])
        #expect(!text.contains("time") && !text.contains("reminderID"))
        #expect(!text.contains("\"id\"") && !text.contains("isDemo"))
        #expect(text.contains(#""format" : "voicetodo-backup""#))
    }

    @Test func 不認得的欄位忽略() throws {
        let read = try Backup.read(#"{"format": "voicetodo-backup", "app": "other", "version": 1, "todos": [{"date": "2026-10-05", "content": "看牙醫", "isDone": false, "color": "red"}]}"#)
        #expect(read.map(\.content) == ["看牙醫"])
    }

    @Test func 沒有待辦的備份也合法() throws {
        #expect(try Backup.read(#"{"format": "voicetodo-backup", "version": 1, "todos": []}"#).isEmpty)
    }

    @Test(arguments: [
        ("", "剪貼簿裡沒有備份"),
        ("看牙醫", "剪貼簿裡沒有備份"),
        (#"{"todos": []}"#, "剪貼簿裡沒有備份"),
        (#"{"format": "other", "version": 1, "todos": []}"#, "剪貼簿裡沒有備份"),
        (#"{"format": "voicetodo-backup", "version": 2, "todos": []}"#, "看不懂第 2 版的備份"),
        (#"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "content": "a", "isDone": false}, {"date": "2026-13-01", "content": "b", "isDone": false}]}"#, "備份的第 2 筆不合法：日期 2026-13-01"),
        (#"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "time": "25:00", "content": "a", "isDone": false}]}"#, "備份的第 1 筆不合法：時間 25:00"),
        (#"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "time": "9:00", "content": "a", "isDone": false}]}"#, "備份的第 1 筆不合法：時間 9:00"),
        (#"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "content": " ", "isDone": false}]}"#, "備份的第 1 筆不合法：內容空白"),
        (#"{"format": "voicetodo-backup", "version": 1, "todos": [{"date": "2026-10-05", "content": "a"}]}"#, "剪貼簿裡沒有備份"),
    ])
    func 不合法就整份不用(text: String, message: String) {
        do {
            _ = try Backup.read(text)
            Issue.record("沒有丟出錯誤")
        } catch {
            #expect((error as? ToolError)?.message == message)
        }
    }

    @Test(arguments: [
        ("建立備份", BackupAction.create), ("備份。", .create),
        ("換成備份", .replace), ("貼上 備份", .replace),
    ])
    func 比對關鍵字(text: String, action: BackupAction) {
        #expect(BackupKeywords.action(text) == action)
    }

    @Test(arguments: ["幫我備份明天的待辦", "備份好了嗎"])
    func 不完全相等就不算(text: String) {
        #expect(BackupKeywords.action(text) == nil)
    }

    @Test func 換成備份重新編id並存檔() throws {
        let storage = FakeTodoStorage()
        let store = TodoStore(storage: storage)
        store.load()
        let maxID = store.todos.map(\.id).max()!
        store.replace(withBackup: try Backup.read(Backup.make(todos)))
        #expect(store.todos.map(\.content) == ["看牙醫", "買牙膏"])
        #expect(store.todos.map(\.id) == [maxID + 1, maxID + 2])
        #expect(storage.saved == store.todos)
    }
}
*/

// MARK: - 天氣

@MainActor
struct WeatherTests {

    @Test func 地名檢查_不像地名的不送出() {
        #expect(Weather.isPlaceName("台北"))
        #expect(Weather.isPlaceName("台北101"))
        #expect(Weather.isPlaceName("Tokyo"))
        #expect(!Weather.isPlaceName("sk-ab12cd34ef"))
        #expect(!Weather.isPlaceName("0912345678"))
        #expect(!Weather.isPlaceName(String(repeating: "台", count: 21)))
        #expect(!Weather.isPlaceName("  "))
    }

    /// 2026-10-05（週一）15:20。
    private let now = DatePhrase.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15, minute: 20))!

    private func request(_ date: String?) -> Weather.Request? {
        try? Weather.request(date, now: now).get()
    }

    private func failure(_ date: String?) -> String? {
        guard case .failure(let error) = Weather.request(date, now: now) else { return nil }
        return error.message
    }

    @Test func 沒說日期是今天() {
        #expect(request(nil) == .init(from: "2026-10-05", to: "2026-10-05", time: nil, timeLabel: "", clipped: false))
    }

    @Test func 日期照查詢的換算() {
        #expect(request("明天") == .init(from: "2026-10-06", to: "2026-10-06", time: nil, timeLabel: "", clipped: false))
        #expect(request("下週") == .init(from: "2026-10-12", to: "2026-10-18", time: nil, timeLabel: "", clipped: false))
    }

    @Test func 時間照範圍換算() {
        let afternoon = request("明天下午")
        #expect(afternoon?.time == TimeRange(from: "12:00", to: "18:00", includesEnd: false))
        #expect(afternoon?.timeLabel == "下午")
        #expect(request("今天中午以前")?.time == TimeRange(from: nil, to: "12:00", includesEnd: false))
        #expect(request("今天中午以前")?.timeLabel == "中午以前")
        // 只有時間：今天。
        #expect(request("晚上")?.from == "2026-10-05")
        #expect(request("下午1點到3點")?.time == TimeRange(from: "13:00", to: "15:00", includesEnd: true))
    }

    @Test func 超出16天() {
        #expect(failure("下個月") == Weather.outOfRange)
        #expect(failure("12月1日") == Weather.outOfRange)
        #expect(failure("昨天") == Weather.outOfRange)
        // 部分超過：截到今天起 16 天（10/5～10/20）。
        #expect(request("10月15日~10月25日") == .init(from: "2026-10-15", to: "2026-10-20", time: nil, timeLabel: "", clipped: true))
        #expect(request("本週")?.clipped == false)
        #expect(request("上週週日~明天") == .init(from: "2026-10-05", to: "2026-10-06", time: nil, timeLabel: "", clipped: true))
    }

    @Test func 下次所有與看不懂_放棄() {
        #expect(failure("下次") == "天氣要說哪一天")
        #expect(failure("所有") == "天氣要說哪一天")
        #expect(failure("下下週")?.hasPrefix("看不懂") == true)
        // 時間要接在一天之後（見 docs/specs/date-time.md 的「不合法的組合」）。
        #expect(failure("下週晚上")?.hasPrefix("看不懂") == true)
    }

    private func hour(_ day: String, _ time: String, code: Int = 0, temperature: Double = 20, rain: Int = 0) -> Weather.Hour {
        .init(day: day, time: time, code: code, temperature: temperature, rainChance: rain)
    }

    @Test func 濃縮_代碼取最大_溫度取最低最高_降雨取最高() {
        let request = request("明天下午")!
        let hours = [
            hour("2026-10-06", "11:00", code: 95, temperature: 10, rain: 90),
            hour("2026-10-06", "12:00", code: 1, temperature: 22.4, rain: 10),
            hour("2026-10-06", "15:00", code: 61, temperature: 25.6, rain: 60),
            hour("2026-10-06", "17:00", code: 3, temperature: 24, rain: 30),
            hour("2026-10-06", "18:00", code: 99, temperature: 30, rain: 100),
        ]
        #expect(Weather.summarize(hours, request: request, now: now) == [.init(day: "2026-10-06", code: 61, low: 22.4, high: 25.6, rainChance: 60)])
    }

    @Test func 濃縮_H點是那一個小時() {
        let hours = [hour("2026-10-06", "14:00", code: 1), hour("2026-10-06", "15:00", code: 2), hour("2026-10-06", "16:00", code: 3)]
        #expect(Weather.summarize(hours, request: request("明天下午3點")!, now: now).map(\.code) == [2])
        #expect(Weather.summarize(hours, request: request("明天下午3點30分")!, now: now).map(\.code) == [2])
    }

    @Test func 濃縮_今天只算還沒到的小時_整段過了是空的() {
        let hours = [hour("2026-10-05", "14:00", code: 95), hour("2026-10-05", "15:00", code: 2), hour("2026-10-05", "17:00", code: 3)]
        #expect(Weather.summarize(hours, request: request("今天下午")!, now: now).map(\.code) == [3])
        #expect(Weather.summarize(hours, request: request("今天早上")!, now: now).isEmpty)
    }

    @Test func 濃縮_不同天各自一句() {
        let hours = [hour("2026-10-06", "19:00", code: 1), hour("2026-10-07", "20:00", code: 2)]
        let request = Weather.Request(from: "2026-10-06", to: "2026-10-07", time: TimeRange(from: "18:00", to: nil, includesEnd: false), timeLabel: "晚上", clipped: false)
        #expect(Weather.summarize(hours, request: request, now: now).map(\.code) == [1, 2])
    }

    @Test func 代碼表() {
        let table: [(Int, String)] = [(0, "晴"), (1, "大致晴朗"), (2, "多雲"), (3, "陰"), (45, "霧"), (48, "霧"), (51, "毛毛雨"), (57, "毛毛雨"),
                                      (61, "雨"), (65, "雨"), (66, "凍雨"), (67, "凍雨"), (71, "雪"), (77, "雪"), (80, "陣雨"), (82, "陣雨"),
                                      (85, "陣雪"), (86, "陣雪"), (95, "雷雨"), (99, "雷雨")]
        for (code, name) in table {
            #expect(Weather.name(code) == name)
        }
    }

    @Test func 句子() {
        let forecast = Weather.Forecast(day: "2026-10-07", code: 0, low: 17.6, high: 24.5, rainChance: 20)
        #expect(Weather.sentence(forecast, place: "所在地", timeLabel: "") == "所在地，10月7日星期三：晴，18～25 度，降雨機率 20%。")
        let rain = Weather.Forecast(day: "2026-10-09", code: 80, low: 22, high: 26, rainChance: 60)
        #expect(Weather.sentence(rain, place: "台北市", timeLabel: "下午") == "台北市，10月9日星期五下午：陣雨，22～26 度，降雨機率 60%。")
        let same = Weather.Forecast(day: "2026-10-07", code: 3, low: 20.2, high: 19.8, rainChance: 0)
        #expect(Weather.sentence(same, place: "所在地", timeLabel: "下午3點") == "所在地，10月7日星期三下午3點：陰，20 度，降雨機率 0%。")
    }

    @Test func 規則判斷_兩句固定的話() {
        #expect(JudgeTool.command("今天會下雨嗎", today: now) == Command(.weather, date: "今天"))
        #expect(JudgeTool.command("明天會下雨嗎？", today: now) == Command(.weather, date: "明天"))
        #expect(JudgeTool.command("明天下午會下雨嗎", today: now) == nil)
        #expect(JudgeTool.command("後天會下雨嗎", today: now) == nil)
    }

    @Test func 語音報告_念前3天_超過請看畫面_不詢問() {
        let days = ["一。", "二。", "三。", "四。"]
        let three = SpokenReport.compose([.weather(days)], readAll: false)
        #expect(three?.text == "一。二。三。" + SpokenReport.seeScreen)
        #expect(three?.unread.isEmpty == true)
        #expect(SpokenReport.compose([.weather(days)], readAll: true)?.text == "一。二。三。四。")
        #expect(SpokenReport.compose([.weather(["一。"])], readAll: false)?.text == "一。")
    }
}

@MainActor
struct TownsTests {

    /// 方形：經度 121～122、緯度 25～26。
    private static let square = Towns.Town(name: "臺北市信義區", rings: [[121, 25, 122, 25, 122, 26, 121, 26, 121, 25]])
    /// L 形：外框是經度 120～121、緯度 23～24，右上角缺一塊；另一個區塊是離島。
    private static let shaped = Towns.Town(name: "澎湖縣馬公市", rings: [
        [120, 23, 121, 23, 121, 23.5, 120.5, 23.5, 120.5, 24, 120, 24, 120, 23],
        [119, 22, 119.2, 22, 119.2, 22.2, 119, 22.2, 119, 22],
    ])
    private let towns = Towns([square, shaped])

    @Test func 座標在邊界內是那一區() {
        #expect(towns.name(latitude: 25.5, longitude: 121.5) == "臺北市信義區")
        #expect(towns.name(latitude: 23.2, longitude: 120.8) == "澎湖縣馬公市")
    }

    @Test func 在外框內但在邊界外不算() {
        #expect(towns.name(latitude: 23.8, longitude: 120.8) == nil)
    }

    @Test func 多個區塊的另一塊也算() {
        #expect(towns.name(latitude: 22.1, longitude: 119.1) == "澎湖縣馬公市")
    }

    @Test func 中間的洞是另一區() {
        let county = Towns.Town(name: "嘉義縣民雄鄉", rings: [[120, 23, 121, 23, 121, 24, 120, 24, 120, 23], [120.4, 23.4, 120.6, 23.4, 120.6, 23.6, 120.4, 23.6, 120.4, 23.4]])
        let city = Towns.Town(name: "嘉義市東區", rings: [[120.4, 23.4, 120.6, 23.4, 120.6, 23.6, 120.4, 23.6, 120.4, 23.4]])
        let towns = Towns([county, city])
        #expect(towns.name(latitude: 23.5, longitude: 120.5) == "嘉義市東區")
        #expect(towns.name(latitude: 23.2, longitude: 120.2) == "嘉義縣民雄鄉")
    }

    @Test func 不在任何一區是nil() {
        #expect(towns.name(latitude: 35.68, longitude: 139.76) == nil)
        #expect(Towns().name(latitude: 25.5, longitude: 121.5) == nil)
    }
}

// MARK: - 提示（見 docs/specs/help.md）

@MainActor
struct HintPageTests {

    private let today = try! TodoStore.dayFormat.parse("2026-09-29")

    /// 只靠 AI 判斷才認得的範例句：要列在 docs/eval/judge-cases.md 的「提示頁的範例句」。
    private let judgedByAI: Set = ["新增明天買牛奶", "新增今天下午3點買牛奶", "新增10月10日上午9點看牙醫", "買牛奶改到後天", "買牛奶完成", "下週五台北天氣如何"]

    @Test func 第一頁是總導覽_頁名不重複() {
        #expect(HintPage.all.first?.name == HintPage.overview)
        #expect(Set(HintPage.all.map(\.name)).count == HintPage.all.count)
    }

    @Test func 每個連結都是存在的頁名() {
        for page in HintPage.all {
            for link in page.links {
                #expect(HintPage.named(link) != nil, "\(page.name) 的連結 \(link)")
            }
        }
    }

    @Test func 更多連到總導覽沒有連的每一頁() {
        #expect(Set(HintPage.named("更多")!.links) == Set(HintPage.all.map(\.name)).subtracting([HintPage.overview, "更多", "新增", "修改", "刪除", "顯示"]))
    }

    @Test func 總導覽連到四種操作與更多_也教關閉音效() {
        let overview = HintPage.named(HintPage.overview)!
        #expect(overview.links == ["新增", "修改", "刪除", "顯示", "更多"])
        #expect(overview.text.contains("「關閉音效」"))
    }

    @Test func 頁名不和固定的說法相同() {
        for page in HintPage.all {
            let name = page.name
            #expect(JudgeTool.generalCommand(name) == nil, "\(name)")
            #expect(JudgeTool.command(name, today: today) == nil, "\(name)")
            #expect(ReportKeywords.toggle(name) == nil && !ReportKeywords.isStop(name), "\(name)")
            #expect(!VoiceOffKeywords.matches(name) && !CancelAllKeywords.matches(name), "\(name)")
            #expect(ConfirmationKeywords.answer(name) == nil && RecoveryKeywords.action(name) == nil, "\(name)")
        }
    }

    @Test func 範例句都認得_規則判斷關鍵字或列在judgeCases() throws {
        let cases = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/eval/judge-cases.md"), encoding: .utf8)
        // 日期說法只列片段，不是一句話。
        for page in HintPage.all where page.name != "日期說法" {
            for match in page.text.matches(of: /「([^」]+)」/) {
                let phrase = String(match.1)
                let known = JudgeTool.generalCommand(phrase) != nil || JudgeTool.command(phrase, today: today) != nil
                    || ReportKeywords.toggle(phrase) != nil || ReportKeywords.isStop(phrase) || CancelAllKeywords.matches(phrase)
                    || VoiceOffKeywords.matches(phrase) || ConfirmationKeywords.answer(phrase) != nil || RecoveryKeywords.action(phrase) != nil
                if !known {
                    #expect(judgedByAI.contains(phrase) && cases.contains("| \(phrase) |"), "\(page.name)：\(phrase)")
                }
            }
        }
    }

    @Test func 翻頁頭尾相接() {
        let first = HintPage.all.first!
        let last = HintPage.all.last!
        #expect(last.step(1) == first)
        #expect(first.step(-1) == last)
        #expect(first.step(1) == HintPage.all[1])
    }

    @Test func 連結嵌在文字裡_純文字只留頁名() {
        let overview = HintPage.named(HintPage.overview)!
        #expect(overview.lines.first == "[新增]：說「新增明天買牛奶」")
        #expect(overview.text.hasPrefix("新增：說「新增明天買牛奶」\n修改："))
        #expect(overview.text.hasSuffix("看更多用法。"))
        #expect(!HintPage.all.contains { $0.text.contains("[") })
    }

    @Test func 每頁都有文字_放得進對話流() {
        for page in HintPage.all {
            #expect(!page.lines.isEmpty && page.lines.count <= 6, "\(page.name)")
        }
    }
}

@MainActor
struct GuideTests {

    @Test func 剛聽不懂_命中的頁() {
        #expect(Guide.line(unclear: "我想刪掉買牛奶的方法", used: [], boardHasTodos: true) == Guide.Line(text: "可以說「如何刪除」", page: "刪除"))
    }

    @Test func 剛聽不懂_沒命中就問提示() {
        #expect(Guide.line(unclear: "好累", used: Set(Guide.Step.allCases), boardHasTodos: true) == Guide.Line(text: "可以說「提示」看怎麼用", page: HintPage.overview))
    }

    @Test func 還沒用過的操作依序() {
        #expect(Guide.line(unclear: nil, used: [], boardHasTodos: true).page == "新增")
        #expect(Guide.line(unclear: nil, used: [.add], boardHasTodos: true).page == "顯示")
        #expect(Guide.line(unclear: nil, used: [.add, .show], boardHasTodos: true) == Guide.Line(text: "可以說「如何修改」", page: "修改"))
        #expect(Guide.line(unclear: nil, used: [.add, .show, .modify, .setDone], boardHasTodos: true).page == "刪除")
    }

    @Test func 黑板沒有待辦時只引導新增與顯示() {
        #expect(Guide.line(unclear: nil, used: [.add, .show], boardHasTodos: false) == Guide.Line(text: "可以說「提示」看更多用法", page: HintPage.overview))
    }

    @Test func 都用過了() {
        #expect(Guide.line(unclear: nil, used: Set(Guide.Step.allCases), boardHasTodos: true).text == "可以說「提示」看更多用法")
    }

    @Test func 用過的種類() {
        #expect(Guide.Step(.queryTodos) == .show)
        #expect(Guide.Step(.showEverything) == .show)
        #expect(Guide.Step(.help) == nil)
    }

    @Test func 用過的紀錄可以存檔() throws {
        let used: Set<Guide.Step> = [.add, .delete]
        #expect(try JSONDecoder().decode(Set<Guide.Step>.self, from: JSONEncoder().encode(used)) == used)
    }
}

@MainActor
struct HintJudgeToolTests {

    private let today = try! TodoStore.dayFormat.parse("2026-09-29")

    @Test(arguments: ["提示", "幫助", "說明", "怎麼用", "怎麼使用", "如何使用", "怎麼用呢"])
    func 總導覽(text: String) {
        #expect(JudgeTool.command(text, today: today) == Command(.help, page: HintPage.overview))
    }

    @Test(arguments: [("如何新增", "新增"), ("怎麼刪除", "刪除"), ("翻頁怎麼用", "翻頁"), ("如何新增呢", "新增"), ("怎麼設定完成", "設定完成")])
    func 如何怎麼加頁名(text: String, page: String) {
        #expect(JudgeTool.command(text, today: today) == Command(.help, page: page))
    }

    @Test func 上個提示下個提示() {
        #expect(JudgeTool.command("上個提示", today: today) == Command(.previousHint))
        #expect(JudgeTool.command("下個提示。", today: today) == Command(.nextHint))
    }

    @Test func 連結名稱只在有連結時命中_只比對給的那幾個() {
        #expect(JudgeTool.command("顯示", today: today) == nil)
        #expect(JudgeTool.command("顯示", today: today, links: ["新增", "顯示"]) == Command(.help, page: "顯示"))
        #expect(JudgeTool.command("天氣", today: today, links: ["新增", "顯示"]) == nil)
    }

    @Test func 有日期的句型照舊() {
        #expect(JudgeTool.command("顯示明天", today: today, links: ["顯示"]) == Command(.queryTodos, date: "明天"))
    }
}

@MainActor
struct SoundKeywordTests {

    @Test func 音效的說法和語音報告相同() {
        #expect(ReportKeywords.toggle("關閉音效") == false)
        #expect(ReportKeywords.toggle("打開音效。") == true)
        #expect(ReportKeywords.toggle("關閉語音報告") == false)
    }
}
