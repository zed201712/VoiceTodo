//
//  Board.swift
//  voicecalender
//

import Foundation
import Observation

/// 黑板的一頁：範圍與查詢條件（見 docs/specs/todos.md 的「黑板」）。「完成」checkbox 不屬於頁，在 `Board`。
struct BoardPage: Equatable, Codable {

    enum Range: Equatable, Codable {
        /// `yyyy-MM-dd`，含頭尾；label 是範圍的說法（例如「下週」），沒有說法時是 nil。
        case days(from: String, to: String, label: String?)
        /// 「所有」：所有的待辦，不限日期。使用者說的「全部」是黑板上目前顯示的全部，不是這個。
        case everything
    }

    var range: Range
    var keyword: String?
    /// 查詢條件的時間範圍；沒有時間的待辦不顯示（見 docs/specs/todos.md 的「黑板」）。
    var time: TimeRange?

    /// 標題的範圍部分，例如 `目前 10/2–10/8`、`明天 10/3（六）`、`明年 2027`；「所有」不顯示範圍。查詢條件另外顯示。
    var title: String {
        guard case .days(let from, let to, let label) = range else {
            return ""
        }
        return [label, Self.dates(from: from, to: to)].compactMap { $0 }.joined(separator: " ")
    }

    /// 範圍的日期，例如 `10/5–10/11`、`10/3（六）`；「所有」是 nil。
    var dates: String? {
        guard case .days(let from, let to, _) = range else {
            return nil
        }
        return Self.dates(from: from, to: to)
    }

    /// 標題的查詢條件：時間範圍、關鍵字，例如 `18:00 以後 會議`；沒有是 nil。
    var condition: String? {
        let parts = [time?.label, keyword].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// 待辦符合查詢條件（關鍵字與時間範圍）。
    func matches(_ todo: Todo) -> Bool {
        (keyword.map { todo.content.contains($0) } ?? true) && (time.map { $0.contains(todo.time) } ?? true)
    }

    private static func dates(from: String, to: String) -> String {
        if from == to {
            return DatePhrase.dayLabel(from)
        }
        if from.hasSuffix("-01-01"), to.hasSuffix("-12-31"), from.prefix(4) == to.prefix(4) {
            return String(from.prefix(4))
        }
        return "\(short(from))–\(short(to))"
    }

    /// `M/D`
    private static func short(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? "\(parts[1])/\(parts[2])" : day
    }

    /// 範圍內、符合查詢條件的待辦，包括今天以前的；只有「完成」checkbox 能隱藏。由早到晚，沒有日期的在最後。
    func visible(_ todos: [Todo], showDone: Bool, today: String) -> [Todo] {
        inScope(todos).filter { !$0.isDone || showDone }
    }

    /// 日期都在範圍內；「所有」涵蓋所有日期。
    func covers(from: String, to: String) -> Bool {
        guard case .days(let start, let end, _) = range else {
            return true
        }
        return start <= from && to <= end
    }

    /// 沒有日期的待辦在任何範圍都看得到（見 docs/specs/todos.md 的「沒有日期的待辦」）。
    private func inScope(_ todos: [Todo]) -> [Todo] {
        todos
            .filter { todo in
                guard case .days(let from, let to, _) = range, let date = todo.date else { return true }
                return date >= from && date <= to
            }
            .filter(matches)
            .sorted { $0.order < $1.order }
    }

    /// 存檔的一頁，連同存的那天（`yyyy-MM-dd`）；App 啟動時照今天換算（見 docs/specs/todos.md 的「黑板」的「App 啟動」）。
    struct Saved: Equatable, Codable {
        let day: String
        let page: BoardPage

        /// 「目前」從今天重算；不是存的那天時拿掉說法，日期不變；「所有」不變。
        func restored(today: Date) -> BoardPage {
            var restored = page
            guard case .days(let from, let to, let label?) = page.range else {
                return restored
            }
            if label == "目前" {
                restored.range = Board.current(today)
            } else if day != TodoStore.dayString(today) {
                restored.range = .days(from: from, to: to, label: nil)
            }
            return restored
        }
    }
}

/// 黑板：目前的一頁與導覽紀錄，像瀏覽器的上一頁、下一頁；「完成」checkbox 是整個黑板共用的，不加入紀錄。
/// 目前的一頁與 checkbox 由 App 存檔，紀錄不存檔。
@Observable
final class Board {

    private(set) var pages: [BoardPage]
    private(set) var index = 0
    /// 「完成」checkbox（在畫面上是工具列的「顯示已完成」開關）。
    private(set) var showDone: Bool

    var page: BoardPage { pages[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < pages.count - 1 }

    /// App 啟動：從存的那一頁開始；沒存過是「目前」、沒有查詢條件。
    init(today: Date, saved: BoardPage.Saved? = nil, showDone: Bool = false) {
        pages = [saved?.restored(today: today) ?? BoardPage(range: Self.current(today))]
        self.showDone = showDone
    }

    /// 目前這一頁看得到的待辦。
    func visible(_ todos: [Todo], today: String) -> [Todo] {
        page.visible(todos, showDone: showDone, today: today)
    }

    /// 編號對到的待辦（見 docs/specs/todos.md 的「編號」）：一句話開始時記下，同一句話裡的增刪改不重排；換頁才重記。
    @ObservationIgnored private var numbering: (page: BoardPage, showDone: Bool, ids: [Int])?

    func fixNumbers(_ todos: [Todo], today: String) {
        numbering = (page, showDone, visible(todos, today: today).map(\.id))
    }

    /// 編號依序對到的待辦 id；換頁後改對到新的那一頁。
    func numberedIDs(_ todos: [Todo], today: String) -> [Int] {
        if numbering?.page != page || numbering?.showDone != showDone {
            fixNumbers(todos, today: today)
        }
        return numbering?.ids ?? []
    }

    /// 和目前的頁不同才加入紀錄；在中間時之後的紀錄清空。
    func go(_ page: BoardPage) {
        guard page != self.page else {
            return
        }
        pages = Array(pages[...index]) + [page]
        index += 1
    }

    /// 重新開始：只剩「目前」這一頁，checkbox 不變。
    func reset(today: Date) {
        pages = [BoardPage(range: Self.current(today))]
        index = 0
    }

    /// 「目前」：今天起 7 天。
    static func current(_ today: Date) -> BoardPage.Range {
        try! DatePhrase.parse("目前", today: today).get().focus!
    }

    /// 換範圍與查詢條件。
    func move(to range: BoardPage.Range, keyword: String? = nil, time: TimeRange? = nil) {
        go(BoardPage(range: range, keyword: keyword, time: time))
    }

    /// 變動的待辦被查詢條件擋住看不到時，清除查詢條件，範圍不變；被 checkbox 擋住的不處理（見 docs/specs/todos.md 的「黑板」）。
    func reveal(_ todos: [Todo]) {
        guard !todos.allSatisfy(page.matches) else {
            return
        }
        move(to: page.range)
    }

    /// 新增、修改、刪除、設定完成、undo／redo：讓這段日期看得到，黑板不放大（見 docs/specs/todos.md 的「黑板」的「範圍」）。
    /// 已涵蓋就不動，查詢條件也保留；否則保持天數、平移到以這段日期為中心（多出的一天放在後面），
    /// 這段日期比黑板長時移到它本身；移動時清除查詢條件。
    func reveal(from: String, to: String) {
        guard !page.covers(from: from, to: to), case .days(let start, let end, _) = page.range,
              let length = Self.days(start, end), let span = Self.days(from, to)
        else {
            return
        }
        guard span <= length, let first = Self.shift(from, by: -(length - span) / 2),
              let last = Self.shift(first, by: length - 1)
        else {
            move(to: .days(from: from, to: to, label: nil))
            return
        }
        move(to: .days(from: first, to: last, label: nil))
    }

    /// 含頭尾的天數。
    private static func days(_ from: String, _ to: String) -> Int? {
        guard let start = try? TodoStore.dayFormat.parse(from), let end = try? TodoStore.dayFormat.parse(to) else {
            return nil
        }
        return DatePhrase.calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 }
    }

    private static func shift(_ day: String, by offset: Int) -> String? {
        guard let date = try? TodoStore.dayFormat.parse(day),
              let shifted = DatePhrase.calendar.date(byAdding: .day, value: offset, to: date)
        else {
            return nil
        }
        return TodoStore.dayString(shifted)
    }

    /// 換「完成」checkbox，不加入導覽紀錄。
    func setDisplay(showDone: Bool) {
        self.showDone = showDone
    }

    func goBack() {
        if canGoBack { index -= 1 }
    }

    func goForward() {
        if canGoForward { index += 1 }
    }
}

/// 黑板的日期分組（參考提醒事項 App 的「排程」；見 docs/specs/ui.md 的「黑板」）：以今天為準，不看黑板的範圍。
/// 編號跨組連續，`firstNumber` 是這組第一筆的編號。
struct BoardSection: Equatable {
    let title: String
    let isToday: Bool
    /// 月份組（含「M月其餘」）裡每換一天有日期小標題；一天一組的沒有。
    let isMonth: Bool
    let firstNumber: Int
    let todos: [Todo]

    /// `todos` 是黑板上看得到的待辦，已經排好序；同一組的待辦相鄰。
    static func make(_ todos: [Todo], today: String) -> [BoardSection] {
        var sections: [BoardSection] = []
        for (index, todo) in todos.enumerated() {
            let (title, isMonth) = group(todo.date, today: today)
            if let last = sections.last, last.title == title {
                sections[sections.count - 1] = BoardSection(title: title, isToday: last.isToday, isMonth: isMonth, firstNumber: last.firstNumber, todos: last.todos + [todo])
            } else {
                sections.append(BoardSection(title: title, isToday: todo.date == today, isMonth: isMonth, firstNumber: index + 1, todos: [todo]))
            }
        }
        return sections
    }

    /// 畫面用的一層清單：每組的標題接著那組的待辦，每筆帶著自己的編號；月份組裡每換一天先加日期小標題。
    /// 兩層的清單在待辦換組時，畫面沿用了換組前的編號（實測出現兩個「2.」）。
    static func lines(_ todos: [Todo], today: String) -> [BoardLine] {
        make(todos, today: today).flatMap { section in
            var lines = [BoardLine.header(title: section.title, isToday: section.isToday, isMonth: section.isMonth)]
            for (offset, todo) in section.todos.enumerated() {
                if section.isMonth, let date = todo.date, offset == 0 || section.todos[offset - 1].date != date {
                    lines.append(.header(title: DatePhrase.dayLabel(date), isToday: false, isMonth: false))
                }
                lines.append(.todo(todo, number: section.firstNumber + offset))
            }
            return lines
        }
    }

    private static let near = [-1: "昨天", 0: "今天", 1: "明天", 2: "後天"]

    /// 昨天到後天只寫詞；今天以前 7 天到今天起 7 天內一天一組；這個月更後面是「M月其餘」；其他依月份。
    private static func group(_ date: String?, today: String) -> (title: String, isMonth: Bool) {
        guard let date else {
            return ("沒有日期", false)
        }
        guard let offset = days(from: today, to: date) else {
            return (date, false)
        }
        if let word = near[offset] {
            return (word, false)
        }
        if (-7...6).contains(offset) {
            return (DatePhrase.dayLabel(date), false)
        }
        let (year, month) = (date.prefix(4), Int(date.dropFirst(5).prefix(2)) ?? 0)
        if offset > 0, date.prefix(7) == today.prefix(7) {
            return ("\(month)月其餘", true)
        }
        return (year == today.prefix(4) ? "\(month)月" : "\(year)年\(month)月", true)
    }

    private static func days(from: String, to: String) -> Int? {
        guard let start = try? TodoStore.dayFormat.parse(from), let end = try? TodoStore.dayFormat.parse(to) else {
            return nil
        }
        return DatePhrase.calendar.dateComponents([.day], from: start, to: end).day
    }
}

/// 黑板的一行：分組標題（月份組的標題，或一天的標題），或一筆待辦。
/// 月份組裡的日期小標題和一天一組的標題同一種；同一天只會在其中一種出現，標題不重複。
enum BoardLine: Identifiable, Equatable {
    case header(title: String, isToday: Bool, isMonth: Bool)
    case todo(Todo, number: Int)

    var id: String {
        switch self {
        case .header(let title, _, _): "組-\(title)"
        case .todo(let todo, _): "待辦-\(todo.id)"
        }
    }
}
