//
//  Commands.swift
//  voicecalender
//

import Foundation

/// AI 輸出的一條指令（見 docs/specs/todos.md）。目標待辦用日期＋內容關鍵字描述，不用 id。
struct Command: Equatable {

    enum Action: String, CaseIterable {
        case queryDate = "查詢日期"
        case queryTodos = "查詢待辦"
        case addTodo = "新增待辦"
        case setDone = "設定完成"
        case modifyTodo = "修改待辦"
        case copyTodo = "複製待辦"
        case deleteTodos = "刪除待辦"
        case setDisplay = "設定顯示"
        // 以下由小精靈執行：要用到 undo 的紀錄、語音報告，不在 CommandExecutor 裡。
        case undo = "復原"
        case redo = "重做"
        case previousPage = "上一頁"
        case nextPage = "下一頁"
        case showEverything = "顯示全部"
        // 備份暫停（見 docs/specs/backup.md）。
        // case createBackup = "建立備份"
        // case replaceBackup = "換成備份"
        case readAll = "全部念完"
        /// 提示頁（見 docs/specs/help.md）：不改待辦，由小精靈顯示提示對話框。
        case help = "說明"
        case previousHint = "上個提示"
        case nextHint = "下個提示"
        /// 額外能力（見 docs/specs/weather.md）：要連網路，由小精靈執行。
        case weather = "查天氣"
        /// 不是執行器：明確的「聽不懂」選項，整句都不執行（見 docs/specs/judgment.md 的「流程」）。
        case unknown = "聽不懂"

        /// 給 AI 的指令語意；所有 AI 的提示詞都由這裡組出指令清單。
        var meaning: String {
            switch self {
            case .queryDate: "只問某天是幾號、星期幾"
            case .queryTodos: "問某段時間有什麼事、行程或待辦，要顯示某段時間，或某件事在哪天"
            case .addTodo: "在某一天加一件事"
            case .setDone: "把某件事標成已完成或未完成"
            case .modifyTodo: "改某件事的日期或內容"
            case .copyTodo: "把已經存在的某件事在另一天（或另一個時間）再加一份，原本的留著"
            case .deleteTodos: "刪掉某些事"
            case .setDisplay: "勾選或取消畫面上的「完成」，決定是否顯示已完成的待辦"
            case .undo: "讓待辦回到上一次改變之前的樣子"
            case .redo: "把剛才復原的改變做回來"
            case .previousPage: "畫面回到上一頁，像瀏覽器的上一頁"
            case .nextPage: "畫面到下一頁，像瀏覽器的下一頁"
            case .showEverything: "畫面顯示所有的待辦，不帶任何查詢條件"
            // case .createBackup: "把所有待辦做成一份備份，放到剪貼簿"
            // case .replaceBackup: "用剪貼簿裡的備份整份取代目前的待辦"
            case .readAll: "之後查詢的結果全部念出來，不只念前 3 項"
            case .help: "問 App 怎麼用、要怎麼說：顯示那一頁提示"
            case .previousHint: "提示換到上一頁"
            case .nextHint: "提示換到下一頁"
            case .weather: "查某天（可以加時段）、某地的天氣預報；要記下跟天氣有關的事是新增待辦"
            case .unknown: "跟待辦、日期與天氣無關、聽不清楚或只是雜音，不做任何事"
            }
        }

        /// 給 AI 的欄位說明，接在 meaning 後面。
        var fieldsText: String {
            switch self {
            case .queryDate: "欄位：date（必填）"
            case .queryTodos: "欄位：date、keyword（沒說就省略）"
            case .addTodo: "欄位：date（沒說就省略）、content（必填，新待辦的內容）"
            case .setDone: "欄位：date（沒說就省略）、keyword 或 number（必填其一）、isDone（必填，true 為已完成、false 為未完成）"
            case .modifyTodo: "欄位：date（要修改的待辦的日期，沒說就省略）、keyword 或 number（必填其一，要修改的待辦）、newDate、newContent（不改就省略）"
            case .copyTodo: "欄位：date（要複製的待辦的日期，沒說就省略）、keyword 或 number（必填其一，要複製的待辦）、newDate（必填，複製到的日期或時刻）"
            case .deleteTodos: "欄位：date、keyword、number（沒說就省略）、isDone（只刪已完成的待辦時為 true，否則省略）"
            case .setDisplay: "欄位：showDone（「完成」是否勾選）"
            case .weather: "欄位：date、place（地名，照使用者說的；沒說就省略，是所在地）"
            case .help: "欄位：page（必填，提示的頁名：\(HintPage.all.map(\.name).joined(separator: "、"))）"
            case .undo, .redo, .previousPage, .nextPage, .showEverything, .readAll, .previousHint, .nextHint, .unknown: "沒有欄位"
            }
        }

        /// AI 輸出的欄位：名字照 JSON（修改待辦的新內容是 newContent）；所有 AI 的輸出結構都照這份。
        var fields: [Field] {
            switch self {
            case .queryDate: [.text("date", required: true)]
            case .queryTodos: [.text("date"), .text("keyword")]
            case .addTodo: [.text("date"), .text("content", required: true)]
            case .setDone: [.text("date"), .text("keyword"), .text("number"), .flag("isDone", required: true)]
            case .modifyTodo: [.text("date"), .text("keyword"), .text("number"), .text("newDate"), .text("newContent")]
            case .copyTodo: [.text("date"), .text("keyword"), .text("number"), .text("newDate", required: true)]
            case .deleteTodos: [.text("date"), .text("keyword"), .text("number"), .flag("isDone")]
            case .setDisplay: [.flag("showDone", required: true)]
            case .weather: [.text("date"), .text("place")]
            case .help: [Field(name: "page", kind: .oneOf(HintPage.all.map(\.name)), required: true)]
            case .undo, .redo, .previousPage, .nextPage, .showEverything, .readAll, .previousHint, .nextHint, .unknown: []
            }
        }
    }

    /// 一個欄位；日期也是字串，合法與否由日期解析判斷。
    struct Field: Equatable {
        enum Kind: Equatable {
            case text
            case flag
            case oneOf([String])
        }

        let name: String
        let kind: Kind
        var required = false

        static func text(_ name: String, required: Bool = false) -> Field { Field(name: name, kind: .text, required: required) }
        static func flag(_ name: String, required: Bool = false) -> Field { Field(name: name, kind: .flag, required: required) }
    }

    var action: Action
    /// 日期字串，依單位順序組成（見 docs/specs/date-time.md）。
    var date: String?
    var keyword: String?
    /// 黑板上的編號：一個（`2`）或一段（`3~10`）；有編號時不看日期與關鍵字（見 docs/specs/todos.md 的「編號」）。
    var number: String?
    var content: String?
    var newDate: String?
    var isDone: Bool?
    var showDone: Bool?
    /// 查天氣的地名，照使用者說的；沒說是所在地。
    var place: String?
    /// 說明的頁名（見 docs/specs/help.md 的「提示頁」）。
    var page: String?

    init(
        _ action: Action,
        date: String? = nil,
        keyword: String? = nil,
        number: String? = nil,
        content: String? = nil,
        newDate: String? = nil,
        isDone: Bool? = nil,
        showDone: Bool? = nil,
        place: String? = nil,
        page: String? = nil
    ) {
        self.action = action
        self.date = date
        self.keyword = keyword
        self.number = number
        self.content = content
        self.newDate = newDate
        self.isDone = isDone
        self.showDone = showDone
        self.place = place
        self.page = page
    }

    /// 給小精靈與除錯 UI，例如 `刪除待辦（下次・買牛奶）`。
    var summary: String {
        let fields = [date, keyword, number.map { "第\($0)項" }, content, newDate.map { action == .copyTodo ? "到\($0)" : "改到\($0)" }, isDone.map { $0 ? "已完成" : "未完成" }, showDone.map { "完成\($0 ? "顯示" : "隱藏")" }, place, page]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return fields.isEmpty ? action.rawValue : "\(action.rawValue)（\(fields.joined(separator: "・"))）"
    }
}

/// 執行一條指令的結果。
enum CommandOutcome: Equatable {
    /// 回話的文字與語音報告用的結構化結果；不念的指令（設定顯示）沒有結果。
    case done(String, Report? = nil)
    /// 找到多筆，需要使用者說是哪一筆。
    case clarify(String)
    /// 刪除前確認；附要刪的 id。
    case confirmDelete(String, ids: [Int])
    /// 參數不合法。
    case abandon(String)
    /// 黑板上找不到目標：和放棄一樣還原，回話只說「找不到」。
    case notFound
}

/// App 執行指令：換算日期、移動黑板、在黑板上找出目標、執行（見 docs/specs/todos.md 的「黑板」、
/// docs/specs/judgment.md 的「找出目標」）。
struct CommandExecutor {

    let store: TodoStore
    let board: Board
    let today: Date

    func execute(_ command: Command) -> CommandOutcome {
        do {
            return try run(command)
        } catch is NotFound {
            return .notFound
        } catch {
            return .abandon(error.localizedDescription)
        }
    }

    private struct NotFound: Error {}

    private func run(_ command: Command) throws -> CommandOutcome {
        switch command.action {

        case .queryDate:
            // 沒有日期以黑板為準：單日就是那一天，否則是今天（見 docs/specs/todos.md 的「各指令的日期與時間」）。
            var text = command.date ?? ""
            var date = try command.date.map(parse)
            if date == nil || date?.days == ParsedDate.Days.none {
                if case .days(let from, let to, _) = board.page.range, from == to {
                    text = "這天"
                    date = ParsedDate(days: .range(from: from, to: from), time: nil, units: [], focus: nil)
                } else {
                    text = "今天"
                    date = try parse(text)
                }
            }
            guard let date else {
                throw ToolError(message: "沒有日期")
            }
            guard let answer = DatePhrase.answer(text, date), case .range(let from, let to) = date.days else {
                throw ToolError(message: "沒有日期：\(text)")
            }
            return .done(answer, .date(phrase: text, from: from, to: to))

        case .queryTodos:
            // 有日期就顯示那段日期；沒有日期時範圍不變。關鍵字與時間範圍成為查詢條件（見 docs/specs/todos.md 的「各指令的日期與時間」）。
            let keyword = command.keyword.flatMap { $0.isEmpty ? nil : $0 }
            let date = try command.date.map(parse)
            let time = date?.time?.range
            switch date?.days {
            case nil, .none?:
                board.move(to: board.page.range, keyword: keyword, time: time)
            case .everything?:
                board.move(to: .everything, keyword: keyword, time: time)
            case .range?, .next?:
                guard let date, let days = days(date, keyword: keyword) else {
                    return .done("找不到", .queried([]))
                }
                board.move(to: date.focus ?? .days(from: days.from, to: days.to, label: nil), keyword: keyword, time: time)
            }
            let found = board.visible(store.todos, today: TodoStore.dayString(today))
            return .done(found.isEmpty ? "找不到" : "\(found.count) 件待辦", .queried(found))

        case .addTodo:
            // 沒說日期以黑板為準，黑板是「目前」時用今天，其他超過一天時釐清（見 docs/specs/todos.md 的「沒說日期時：以黑板為準」）。
            let date = try command.date.map(parse)
            let day: String
            if date == nil || date?.days == ParsedDate.Days.none {
                switch board.page.range {
                case .days(let from, let to, _) where from == to:
                    day = from
                case .days(_, _, "目前"):
                    day = TodoStore.dayString(today)
                case .days:
                    return .clarify("你是指 \(board.page.dates ?? "") 的哪一天？")
                case .everything:
                    day = TodoStore.dayString(today)
                }
            } else if let single = date?.singleDay {
                day = single
            } else {
                throw ToolError(message: "日期不是單一天：\(command.date ?? "")")
            }
            var time = try point(date?.time)
            // 今天沒說時間：推測接下來的時段，18:00 以後留空（見 docs/specs/todos.md 的「各指令的日期與時間」）。
            if date?.time == nil, day == TodoStore.dayString(today) {
                let now = DatePhrase.calendar.dateComponents([.hour, .minute], from: today)
                time = TimePhrase.nextSlot(after: String(format: "%02d:%02d", now.hour ?? 0, now.minute ?? 0))
            }
            let todo = try store.addTodo(date: day, time: time, content: command.content ?? "")
            board.reveal(from: day, to: day)
            board.reveal([todo])
            return .done("已新增 \(todo.line)", .added(todo))

        case .setDone:
            let isDone = command.isDone ?? true
            return try withTargets(command) { todos in
                for todo in todos {
                    try store.setDone(id: todo.id, isDone: isDone)
                }
                return (todos.map { Self.doneReport($0, isDone: isDone) }.joined(separator: "\n"), .setDone(todos, isDone: isDone))
            }

        case .modifyTodo:
            // 新日期只有時刻時只改時間；只有日期時保留原本的時間。
            let newDate = try command.newDate.map(parse)
            let newDay = newDate?.singleDay
            if let newDate, newDate.days != .none, newDay == nil {
                throw ToolError(message: "日期不是單一天：\(command.newDate ?? "")")
            }
            let newTime = try point(newDate?.time)
            let content = command.content.flatMap { $0.isEmpty ? nil : $0 }
            guard newDay != nil || newTime != nil || content != nil else {
                throw ToolError(message: "沒有要修改的日期、時間或內容")
            }
            let outcome = try withTargets(command) { todos in
                for todo in todos {
                    try store.modifyTodo(id: todo.id, date: newDay, time: newTime, content: content)
                }
                let after = todos.map { todo in store.todos.first { $0.id == todo.id } ?? todo }
                let describe = { (todo: Todo) in [todo.date, todo.time, todo.content].compactMap { $0 }.joined(separator: " ") }
                let message = zip(todos, after).map { "已將 \(describe($0)) 改為 \(describe($1))" }.joined(separator: "\n")
                return (message, .modified(before: todos, after: after))
            }
            if case .done = outcome, let newDay {
                board.reveal(from: newDay, to: newDay)
            }
            if case .done(_, .modified(_, let after)) = outcome {
                board.reveal(after)
            }
            return outcome

        case .copyTodo:
            // 新日期只有時刻時日期不變；沒說時刻時沿用原本的時間；複製出來的是未完成（見 docs/specs/todos.md 的「指令」）。
            guard let text = command.newDate else {
                throw ToolError(message: "沒有要複製到的日期")
            }
            let newDate = try parse(text)
            let newDay = newDate.singleDay
            if newDate.days != .none, newDay == nil {
                throw ToolError(message: "日期不是單一天：\(text)")
            }
            let newTime = try point(newDate.time)
            let outcome = try withTargets(command) { todos in
                let copies = try todos.map { todo in
                    guard let day = newDay ?? todo.date else {
                        throw ToolError(message: "沒有日期：\(todo.content)")
                    }
                    return try store.addTodo(date: day, time: newTime ?? todo.time, content: todo.content)
                }
                return (copies.map { "已複製 \($0.line)" }.joined(separator: "\n"), .copied(copies))
            }
            if case .done(_, .copied(let copies)) = outcome {
                let days = copies.compactMap(\.date).sorted()
                if let first = days.first, let last = days.last {
                    board.reveal(from: first, to: last)
                }
                board.reveal(copies)
            }
            return outcome

        case .deleteTodos:
            // 日期與關鍵字都沒給是黑板上的全部；isDone 是只刪已完成的。
            let found = try targets(command, onlyDone: command.isDone == true)
            guard !found.isEmpty else {
                throw NotFound()
            }
            return .confirmDelete(
                "即將刪除\(Self.describe(command))（\(found.count) 項）：\n\(Self.list(found))\n\(found.count > 1 ? "這 \(found.count) 項都要刪掉嗎？" : "要刪掉嗎？")",
                ids: found.map(\.id)
            )

        case .setDisplay:
            guard let showDone = command.showDone else {
                throw ToolError(message: "沒有指定要顯示什麼")
            }
            board.setDisplay(showDone: showDone)
            return .done("完成：\(board.showDone ? "顯示" : "隱藏")")

        case .unknown:
            // 小精靈不會執行到這裡：清單裡有「聽不懂」時整句都不執行。
            throw ToolError(message: "聽不懂")

        case .undo, .redo, .previousPage, .nextPage, .showEverything, .readAll, .weather, .help, .previousHint, .nextHint:
            // 小精靈不會執行到這裡：這些執行器由小精靈執行（見 Command.Action）。
            throw ToolError(message: "由小精靈執行")
        }
    }

    // MARK: - 黑板與找出目標

    /// 解析日期字串；看不懂就放棄，原因是「看不懂「…」」。
    func parse(_ text: String) throws -> ParsedDate {
        switch DatePhrase.parse(text, today: today) {
        case .success(let date): return date
        case .failure(let error): throw ToolError(message: error.localizedDescription)
        }
    }

    /// 新增、修改的時間：換成時間點；範圍（以前、以後、到）與凌晨不是時間點，放棄（見 docs/specs/date-time.md 的「時間」）。
    private func point(_ time: TimePhrase?) throws -> String? {
        guard let time else {
            return nil
        }
        guard let point = time.point else {
            throw ToolError(message: "時間不是一個時間點：\(time.units.joined())")
        }
        return point
    }

    /// 日期本身的範圍；「下次」是今天起最早符合關鍵字的那一天，找不到、「所有」或只有時間時是 nil。
    private func days(_ date: ParsedDate, keyword: String?) -> (from: String, to: String)? {
        switch date.days {
        case .range(let from, let to):
            return (from, to)
        case .next:
            let today = TodoStore.dayString(today)
            return store.todos
                .filter { ($0.date.map { $0 >= today } ?? false) && (keyword.map($0.content.contains) ?? true) }
                .min { $0.order < $1.order }
                .flatMap(\.date)
                .map { ($0, $0) }
        case .everything, .none:
            return nil
        }
    }

    /// 黑板上看得到的待辦，依日期本身的範圍、時間範圍與關鍵字篩選；有日期時先讓黑板涵蓋它。
    /// 時間換成範圍（「晚上」是 18:00 以後），沒有時間的待辦不列入（見 docs/specs/todos.md 的「各指令的日期與時間」）。
    /// `onlyDone`（刪除完成）時，「完成」沒勾就自動勾選，讓要刪的項目出現在黑板上。
    func targets(_ command: Command, onlyDone: Bool = false) throws -> [Todo] {
        if let number = command.number {
            return try numbered(number)
        }
        let keyword = command.keyword.flatMap { $0.isEmpty ? nil : $0 }
        var range: (from: String, to: String)?
        var time: TimeRange?
        if let text = command.date {
            let date = try parse(text)
            time = date.time?.range
            // 「所有」「全部」是黑板上顯示的全部：當成沒給日期（見 docs/specs/todos.md 的「黑板」）。
            if date.days != .none, date.days != .everything {
                guard let days = days(date, keyword: keyword) else {
                    return []
                }
                board.reveal(from: days.from, to: days.to)
                range = days
            }
        }
        if onlyDone && !board.showDone {
            board.setDisplay(showDone: true)
        }
        return board.visible(store.todos, today: TodoStore.dayString(today))
            // 說了日期時只在那段日期裡找，沒有日期的待辦找不到（見 docs/specs/todos.md 的「沒有日期的待辦」）。
            .filter { todo in range.map { range in todo.date.map { $0 >= range.from && $0 <= range.to } ?? false } ?? true }
            .filter { todo in time.map { $0.contains(todo.time) } ?? true }
            .filter { todo in keyword.map { todo.content.contains($0) } ?? true }
            .filter { todo in !onlyDone || todo.isDone }
    }

    /// 編號（`2`、`3~10`）對到黑板上的第幾筆，以使用者看到的那一頁為準；超出範圍或看不懂就放棄（見 docs/specs/todos.md 的「編號」）。
    /// 同一句話裡前面已經刪掉的找不到。
    private func numbered(_ number: String) throws -> [Todo] {
        let bounds = number.split(separator: "~", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (1...2).contains(bounds.count), let first = bounds.first ?? nil, let last = bounds.last ?? nil else {
            throw ToolError(message: "看不懂編號「\(number)」")
        }
        let ids = board.numberedIDs(store.todos, today: TodoStore.dayString(today))
        guard !ids.isEmpty else {
            throw ToolError(message: "黑板上沒有待辦")
        }
        guard 1 <= first, first <= last, last <= ids.count else {
            throw ToolError(message: "黑板上只有 1～\(ids.count)")
        }
        return ids[(first - 1)...(last - 1)].compactMap { id in store.todos.first { $0.id == id } }
    }

    /// 日期＋關鍵字找到多筆時釐清；用編號指定的是使用者明確要的全部，直接執行。
    private func withTargets(_ command: Command, _ body: ([Todo]) throws -> (String, Report)) throws -> CommandOutcome {
        let found = try targets(command)
        guard !found.isEmpty else {
            throw NotFound()
        }
        guard found.count == 1 || command.number != nil else {
            return .clarify("有 \(found.count) 筆\(Self.describe(command))：\n\(Self.list(found))\n要哪一筆？")
        }
        let (message, report) = try body(found)
        return .done(message, report)
    }

    /// 設定完成的回報；點黑板的方框也用這個。
    static func doneReport(_ todo: Todo, isDone: Bool) -> String {
        "已將 \([todo.date, todo.content].compactMap { $0 }.joined(separator: " ")) 設為\(isDone ? "已完成" : "未完成")"
    }

    /// 沒有日期與關鍵字時是黑板上的「全部」。
    private static func describe(_ command: Command) -> String {
        let done = command.action == .deleteTodos && command.isDone == true ? "已完成的待辦" : nil
        if let number = command.number {
            return "第\(number)項" + (done.map { "的\($0)" } ?? "")
        }
        let parts = [command.date, command.keyword, done].compactMap { $0 }
        // 不用「全部」：念的期間回答「全部」會被當成回音（見 docs/specs/spoken-report.md 的「念問題」）。
        return parts.isEmpty ? "所有待辦" : parts.joined(separator: "的")
    }

    private static func list(_ todos: [Todo]) -> String {
        todos
            .map(\.line)
            .joined(separator: "\n")
    }
}

/// 刪除確認的回答：other 是指定其中某些項目或說了新需求（見 docs/specs/judgment.md 的「刪除確認」）。
enum ConfirmAnswer: String {
    case yes, no, other
}

/// 刪除確認的回答先用關鍵字判斷；判斷不出來回傳 nil，交給 AI（見 docs/specs/judgment.md 的「刪除確認」）。
enum ConfirmationKeywords {

    static let yes: Set = ["好", "好的", "好啊", "可以", "確定", "確認", "是", "對", "沒問題", "全部", "同意", "ok", "yes"]
    static let no: Set = ["不", "不要", "不用", "取消", "算了", "否", "no"]

    /// 去掉標點與空白後完全相等才算：「不好」包含「好」，用包含會誤判成 yes。
    static func answer(_ text: String) -> Bool? {
        let word = normalized(text)
        if yes.contains(word) { return true }
        if no.contains(word) { return false }
        return nil
    }

    /// 比對用的形式：小寫，只留文字與數字。
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum RecoveryAction {
    case undo, redo, retry, skip
}

/// 語音的補救：App 用關鍵字判斷，不送 AI（見 docs/specs/recovery.md 的「語音的補救」）。
enum RecoveryKeywords {

    static let words: [RecoveryAction: Set<String>] = [
        .undo: ["復原", "上一步", "undo"],
        .redo: ["重做", "下一步", "redo"],
        .retry: ["重試", "重複", "再試一次", "retry"],
        .skip: ["略過", "跳過", "pass"],
    ]

    /// 比對方式和刪除確認的關鍵字相同。
    static func action(_ text: String) -> RecoveryAction? {
        let word = ConfirmationKeywords.normalized(text)
        return words.first { $0.value.contains(word) }?.key
    }
}

/// 用語音關閉語音輸入：App 用關鍵字判斷，不送 AI；關閉後不能用語音打開（見 docs/specs/ui.md 的「按鈕列」）。
enum VoiceOffKeywords {

    static let words: Set = ["關閉語音", "停止聆聽", "關閉麥克風"]

    /// 比對方式和刪除確認的關鍵字相同。
    static func matches(_ text: String) -> Bool {
        words.contains(ConfirmationKeywords.normalized(text))
    }
}

/// 全部取消：唯一會影響任務與佇列的優先關鍵字；只比對語音定稿的原句（見 docs/specs/queue.md 的「全部取消」）。
enum CancelAllKeywords {

    static let words: Set = ["全部取消", "全部停止", "取消全部", "停止全部"]

    /// 比對方式和刪除確認的關鍵字相同。
    static func matches(_ text: String) -> Bool {
        words.contains(ConfirmationKeywords.normalized(text))
    }
}

/// 語音報告的話：App 用關鍵字判斷，不送 AI（見 docs/specs/spoken-report.md）。比對方式和刪除確認的關鍵字相同。
enum ReportKeywords {

    static let readAll: Set = ["全部念出來", "全部唸出來", "全部念完", "全部唸完", "全部念", "全部唸"]
    static let yes: Set = ["好", "好的", "要", "可以", "念完", "唸完", "全部", "繼續", "ok", "yes"]
    static let no: Set = ["不要", "不用", "不", "算了", "停止", "no"]

    /// 「要全部念完嗎？」的回答；不是要或不要時是 nil。
    static func moreAnswer(_ text: String) -> Bool? {
        let word = ConfirmationKeywords.normalized(text)
        if yes.contains(word) || readAll.contains(word) { return true }
        if no.contains(word) { return false }
        return nil
    }

    /// 整句話只有「全部念完」。
    static func isReadAll(_ text: String) -> Bool {
        readAll.contains(ConfirmationKeywords.normalized(text))
    }

    /// 句子裡帶著「全部念完」。
    static func containsReadAll(_ text: String) -> Bool {
        let word = ConfirmationKeywords.normalized(text)
        return readAll.contains { word.contains($0) }
    }

    static func isStop(_ text: String) -> Bool {
        ConfirmationKeywords.normalized(text) == "停止"
    }

    /// 打開是 true、關閉是 false，其他是 nil。
    static func toggle(_ text: String) -> Bool? {
        switch ConfirmationKeywords.normalized(text) {
        case "打開語音報告", "開啟語音報告", "打開音效", "開啟音效": true
        case "關閉語音報告", "關閉音效": false
        default: nil
        }
    }
}

// 備份暫停（見 docs/specs/backup.md）。
// enum BackupAction {
//     case create, replace
// }
//
// /// 建立備份、換成備份的固定說法，給規則判斷（見 docs/specs/judge-tool.md 的「固定的話」）。
// enum BackupKeywords {
//
//     static let words: [BackupAction: Set<String>] = [
//         .create: ["建立備份", "備份"],
//         .replace: ["換成備份", "貼上備份"],
//     ]
//
//     /// 比對方式和刪除確認的關鍵字相同。
//     static func action(_ text: String) -> BackupAction? {
//         let word = ConfirmationKeywords.normalized(text)
//         return words.first { $0.value.contains(word) }?.key
//     }
// }

enum BoardAction {
    case showEverything, back, forward
}

/// 顯示全部、上一頁、下一頁的固定說法，給規則判斷（見 docs/specs/judge-tool.md 的「固定的話」）。
enum BoardKeywords {

    static let words: [BoardAction: Set<String>] = [
        .showEverything: ["顯示全部", "顯示所有資料"],
        .back: ["上一頁"],
        .forward: ["下一頁"],
    ]

    /// 說「顯示全部」時，這句話記成這樣：「全部」指的是黑板上顯示的全部，「所有」才是所有的待辦。
    static let showEverythingText = "顯示所有資料"

    /// 比對方式和刪除確認的關鍵字相同。
    static func action(_ text: String) -> BoardAction? {
        let word = ConfirmationKeywords.normalized(text)
        return words.first { $0.value.contains(word) }?.key
    }
}
