//
//  DatePhrase.swift
//  voicecalender
//

import Foundation

/// 解析後的日期與時間（見 docs/specs/date-time.md）。
struct ParsedDate: Equatable {

    enum Days: Equatable {
        /// `yyyy-MM-dd`，含頭尾。
        case range(from: String, to: String)
        /// 今天起最早符合的一筆。
        case next
        /// 「所有」：不限日期。
        case everything
        /// 只有時間，沒有日期。
        case none
    }

    let days: Days
    /// 時間說法，還沒換成時間點或範圍；沒說時間是 nil。
    let time: TimePhrase?
    /// 切出來的單位，給測試紀錄。
    let units: [String]
    /// 查詢時黑板的範圍：說法本身的日期；「下次」與只有時刻時是 nil。
    let focus: BoardPage.Range?

    /// 只有一天時是那一天。
    var singleDay: String? {
        if case .range(let from, let to) = days, from == to { from } else { nil }
    }

    /// 換算結果，時間當成範圍：`2026/11/15 15:30`、`2026/11/15 18:00 以後`、`2026/11/01 ~ 2026/11/30`。
    /// 找目標的回話顯示這個；新增、修改、查詢改顯示實際用的值（見 docs/specs/todos.md 的「指令」）。
    var result: String {
        let dates = switch days {
        case .range(let from, let to): from == to ? Self.slashed(from) : "\(Self.slashed(from)) ~ \(Self.slashed(to))"
        case .next: "下次"
        case .everything: "所有"
        case .none: ""
        }
        return [dates, time?.range.label ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 完整的分析：`下個月 15日 下午 3點 30分 → 2026/11/15 15:30`。測試紀錄記這個。
    var analysis: String {
        "\(units.joined(separator: " ")) → \(result)"
    }

    static func slashed(_ day: String) -> String {
        day.replacingOccurrences(of: "-", with: "/")
    }
}

/// 日期看不懂：已經切出來的單位與卡住的字。
struct DateParseError: LocalizedError, Equatable {
    let units: [String]
    let rest: String

    var errorDescription: String? { "看不懂「\(rest)」" }

    var analysis: String {
        (units + ["→ 看不懂「\(rest)」"]).joined(separator: " ")
    }
}

/// 日期的語法與換算：AI 依單位順序（年、月、週、日、時間）寫成一個字串，這裡從大到小比對，
/// 比對到就拿掉那段字，只能往小的單位走；時間交給 TimePhrase（見 docs/specs/date-time.md）。
/// 一週從星期一開始：從星期日開始的話，在星期二說「本週日」會變成前天，新增到過去的日子，使用者也看不出錯誤。
enum DatePhrase {

    static let weekdays = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]
    static let relativeDays = ["前天": -2, "昨天": -1, "今天": 0, "明天": 1, "後天": 2]
    static let weeks = ["上週": -1, "本週": 0, "下週": 1]
    static let months = ["上個月": -1, "這個月": 0, "下個月": 1]
    static let years = ["去年": -1, "今年": 0, "明年": 1]

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    static func parse(_ text: String, today: Date) -> Result<ParsedDate, DateParseError> {
        let text = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "～", with: "~")
        let today = calendar.startOfDay(for: today)
        if text == "所有" {
            return .success(ParsedDate(days: .everything, time: nil, units: ["所有"], focus: .everything))
        }
        if text == "下次" {
            return .success(ParsedDate(days: .next, time: nil, units: ["下次"], focus: nil))
        }
        if text == "目前", let last = calendar.date(byAdding: .day, value: 6, to: today) {
            let range = (TodoStore.dayString(today), TodoStore.dayString(last))
            return .success(ParsedDate(days: .range(from: range.0, to: range.1), time: nil, units: ["目前"], focus: .days(from: range.0, to: range.1, label: "目前")))
        }
        let sides = text.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        switch sides.count {
        case 1:
            return Point.parse(text).flatMap { $0.resolve(today: today) }
        case 2:
            return range(sides[0], sides[1], today: today)
        default:
            return .failure(DateParseError(units: [], rest: text))
        }
    }

    /// `單點~單點`：兩邊都是日期（不含時刻）。結束早於開始、而且結束沒寫年時，結束算明年。
    private static func range(_ start: String, _ end: String, today: Date) -> Result<ParsedDate, DateParseError> {
        let first: Point
        let last: Point
        switch (Point.parse(start), Point.parse(end)) {
        case (.success(let a), .success(let b)):
            first = a
            last = b
        case (.failure(let error), _):
            return .failure(error)
        case (.success(let a), .failure(let error)):
            return .failure(DateParseError(units: a.units + ["~"] + error.units, rest: error.rest))
        }
        let units = first.units + ["~"] + last.units
        guard first.time == nil, last.time == nil else {
            return .failure(DateParseError(units: units, rest: start + "~" + end))
        }
        guard case .success(let from) = first.resolve(today: today), case .range(let begin, _) = from.days,
              case .success(let to) = last.resolve(today: today), case .range(_, var finish) = to.days
        else {
            return .failure(DateParseError(units: units, rest: start + "~" + end))
        }
        if finish < begin, last.year == nil, let date = try? TodoStore.dayFormat.parse(finish),
           let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
            finish = TodoStore.dayString(nextYear)
        }
        guard begin <= finish else {
            return .failure(DateParseError(units: units, rest: start + "~" + end))
        }
        return .success(ParsedDate(days: .range(from: begin, to: finish), time: nil, units: units, focus: .days(from: begin, to: finish, label: nil)))
    }

    /// 「查詢日期」的回報，例如 `下週週五是 2026-10-09（星期五）`、`明年是 2027 年`、`下個月是 2026-11-01 到 2026-11-30`。
    static func answer(_ text: String, _ date: ParsedDate) -> String? {
        guard case .range(let from, let to) = date.days else {
            return nil
        }
        if from == to, let day = try? TodoStore.dayFormat.parse(from) {
            return "\(text)是 " + describe(day)
        }
        if from.hasSuffix("-01-01"), to.hasSuffix("-12-31"), from.prefix(4) == to.prefix(4) {
            return "\(text)是 \(from.prefix(4)) 年"
        }
        return "\(text)是 \(from) 到 \(to)"
    }

    /// `M/D（星期）`，例如 `10/3（六）`：黑板與回話列出待辦用（見 docs/specs/todos.md）。
    static func dayLabel(_ day: String) -> String {
        guard let date = try? TodoStore.dayFormat.parse(day) else {
            return day
        }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))（\(weekdays[weekday].dropFirst())）"
    }

    /// 例如 `2026-10-02（星期五）`。
    static func describe(_ date: Date) -> String {
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7
        return TodoStore.dayString(date) + "（星期\(weekdays[weekday].dropFirst())）"
    }
}

/// 單點：依序比對到的單位，還沒換算。
private struct Point {

    enum Year { case relative(Int), absolute(Int) }
    enum Month { case relative(Int), absolute(Int) }
    enum Day { case relative(Int), date(Int), weekday(Int) }

    var year: Year?
    var month: Month?
    var week: Int?
    var day: Day?
    var time: TimePhrase?
    /// 每個單位的原文，依序。
    var units: [String] = []
    /// 各單位的原文，給錯誤訊息與黑板的說法。
    var yearText = "", monthText = "", weekText = "", dayText = ""

    /// 從大到小比對，比對到就拿掉；剩下比對不到的字就不合法。
    static func parse(_ text: String) -> Result<Point, DateParseError> {
        var point = Point()
        var rest = Substring(text)

        func take(_ words: some Collection<String>) -> String? {
            guard let word = words.first(where: { rest.hasPrefix($0) }) else {
                return nil
            }
            rest = rest.dropFirst(word.count)
            point.units.append(word)
            return word
        }
        func take(_ regex: Regex<(Substring, Substring)>) -> Int? {
            guard let match = rest.prefixMatch(of: regex), let value = Int(match.1) else {
                return nil
            }
            rest = rest[match.range.upperBound...]
            point.units.append(String(match.0))
            return value
        }

        if let word = take(DatePhrase.years.keys) {
            point.year = .relative(DatePhrase.years[word]!)
            point.yearText = word
        } else if let year = take(/(\d{4})年/) {
            point.year = .absolute(year)
            point.yearText = point.units.last!
        }
        if let word = take(DatePhrase.months.keys) {
            point.month = .relative(DatePhrase.months[word]!)
            point.monthText = word
        } else if let month = take(/(\d{1,2})月/) {
            point.month = .absolute(month)
            point.monthText = point.units.last!
        }
        if let word = take(DatePhrase.weeks.keys) {
            point.week = DatePhrase.weeks[word]!
            point.weekText = word
        }
        if let word = take(DatePhrase.relativeDays.keys) {
            point.day = .relative(DatePhrase.relativeDays[word]!)
            point.dayText = word
        } else if let word = take(DatePhrase.weekdays) {
            point.day = .weekday(DatePhrase.weekdays.firstIndex(of: word)!)
            point.dayText = word
        } else if let day = take(/(\d{1,2})日/) {
            point.day = .date(day)
            point.dayText = point.units.last!
        }
        if !rest.isEmpty {
            switch TimePhrase.parse(rest) {
            case .success(let time):
                point.time = time
                point.units += time.units
                rest = ""
            case .failure(let error):
                return .failure(DateParseError(units: point.units + error.units, rest: error.rest))
            }
        }

        guard rest.isEmpty, !point.units.isEmpty else {
            return .failure(DateParseError(units: point.units, rest: rest.isEmpty ? text : String(rest)))
        }
        return .success(point)
    }

    /// 換算成日期範圍與時間；不合法的組合回傳卡住的那個單位。
    func resolve(today: Date) -> Result<ParsedDate, DateParseError> {
        let calendar = DatePhrase.calendar
        let thisYear = calendar.component(.year, from: today)
        let fail = { (text: String) in Result<ParsedDate, DateParseError>.failure(DateParseError(units: units, rest: text)) }

        // 不合法的組合（見 docs/specs/date-time.md 的「日期」）。
        if case .relative = month, year != nil { return fail(monthText) }
        if week != nil, year != nil || month != nil { return fail(weekText) }
        switch day {
        case .relative?: if year != nil || month != nil || week != nil { return fail(dayText) }
        case .weekday?: if year != nil || month != nil { return fail(dayText) }
        case .date?: if week != nil || (year != nil && month == nil) { return fail(dayText) }
        case nil: break
        }
        if time != nil, day == nil, year != nil || month != nil || week != nil {
            return fail(units.last!)
        }
        if case .absolute(let value) = month, !(1...12).contains(value) { return fail(monthText) }

        guard let range = days(today: today, thisYear: thisYear) else {
            return fail(units.joined())
        }
        return .success(ParsedDate(days: range.map { .range(from: $0.0, to: $0.1) } ?? .none, time: time, units: units, focus: focus(today: today, thisYear: thisYear)))
    }

    /// 最小單位的整段；只有時刻時是 nil 的範圍（.some(nil)）；日期不存在時是 nil。
    private func days(today: Date, thisYear: Int) -> (String, String)?? {
        let calendar = DatePhrase.calendar
        let text = { (date: Date) in TodoStore.dayString(date) }
        let whole = { (component: Calendar.Component, date: Date) -> (String, String)? in
            guard let interval = calendar.dateInterval(of: component, for: date),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
            return (text(interval.start), text(last))
        }
        let baseYear: Int = switch year {
        case .relative(let offset)?: thisYear + offset
        case .absolute(let value)?: value
        case nil: thisYear
        }
        /// 月的第一天。
        let monthStart: Date? = switch month {
        case .relative(let offset)?: calendar.date(byAdding: .month, value: offset, to: today)
            .flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
        case .absolute(let value)?: calendar.date(from: DateComponents(year: baseYear, month: value, day: 1))
        case nil: nil
        }
        let monday = calendar.date(byAdding: .weekOfYear, value: week ?? 0, to: today)
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }

        switch day {
        case .relative(let offset)?:
            return calendar.date(byAdding: .day, value: offset, to: today).map { (text($0), text($0)) }
        case .weekday(let index)?:
            return monday.flatMap { calendar.date(byAdding: .day, value: index, to: $0) }.map { (text($0), text($0)) }
        case .date(let value)?:
            let start = monthStart ?? calendar.dateInterval(of: .month, for: today)!.start
            var components = calendar.dateComponents([.year, .month], from: start)
            components.day = value
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == value,
                  calendar.component(.month, from: date) == components.month
            else {
                return nil
            }
            return (text(date), text(date))
        case nil:
            break
        }
        if week != nil {
            return monday.flatMap { whole(.weekOfYear, $0) }
        }
        if month != nil {
            return monthStart.flatMap { whole(.month, $0) }
        }
        if year != nil {
            return calendar.date(from: DateComponents(year: baseYear, month: 1, day: 1)).flatMap { whole(.year, $0) }
        }
        return .some(nil)
    }

    /// 查詢時黑板的範圍：說法本身的日期（10月6日 → 10/6），時刻不算。
    private func focus(today: Date, thisYear: Int) -> BoardPage.Range? {
        let texts = [yearText, monthText, weekText, dayText].filter { !$0.isEmpty }
        guard !texts.isEmpty, case .some(.some(let range)) = days(today: today, thisYear: thisYear) else {
            return nil
        }
        return .days(from: range.0, to: range.1, label: texts.joined())
    }
}
