//
//  TimePhrase.swift
//  voicecalender
//

import Foundation

/// 時間的範圍，`HH:mm`；`from` 含，`to` 依 `includesEnd`。沒有時間的待辦不在任何範圍內。
struct TimeRange: Equatable, Codable {
    /// nil 是從一天的開頭。
    let from: String?
    /// nil 是到一天的結束。
    let to: String?
    let includesEnd: Bool

    func contains(_ time: String?) -> Bool {
        guard let time else {
            return false
        }
        if let from, time < from {
            return false
        }
        if let to {
            return includesEnd ? time <= to : time < to
        }
        return true
    }

    /// 黑板標題的時間條件：`18:00 以後`、`08:00 以前`、`13:00–15:00`、`15:30`。
    var label: String {
        switch (from, to) {
        case (let from?, let to?): from == to ? from : "\(from)–\(to)"
        case (let from?, nil): "\(from) 以後"
        case (nil, let to?): "\(to) 以前"
        case (nil, nil): ""
        }
    }
}

/// 時間說法（見 docs/specs/date-time.md 的「時間」）：解析後保留說法本身，
/// 用的時候才依用途換成時間點（新增、修改）或範圍（查詢、找目標）。
struct TimePhrase: Equatable {

    /// 時段，或時段加上 H點：還沒換算。
    struct Moment: Equatable {
        let slot: String?
        /// 已依時段換算成 24 小時制；只有時段時是 nil。
        let hour: Int?
        let minute: Int

        /// 當作時間點：有 H點 就是那個時間，只有時段時是時段的時間點（凌晨沒有）。
        var point: String? {
            if let hour {
                return Self.format(hour, minute)
            }
            return slot.flatMap { TimePhrase.slots[$0]?.point }
        }

        /// 當作以前、以後的邊界：有 H點 就是那個時間，只有時段時是時段範圍的開頭。
        var boundary: String {
            if let hour {
                return Self.format(hour, minute)
            }
            return TimePhrase.slots[slot!]!.from
        }

        static func format(_ hour: Int, _ minute: Int) -> String {
            String(format: "%02d:%02d", hour, minute)
        }
    }

    enum Kind: Equatable {
        case moment(Moment)
        case before(Moment)
        case after(Moment)
        case between(Moment, Moment)
    }

    let kind: Kind
    /// 切出來的單位，給測試紀錄。
    let units: [String]

    /// 時段：時間點（新增時）與範圍（查詢時，`to` 不含）。
    static let slots: [String: (point: String?, from: String, to: String?)] = [
        "凌晨": (nil, "00:00", "06:00"),
        "清晨": ("06:00", "06:00", "09:00"),
        "上午": ("09:00", "00:00", "12:00"),
        "早上": ("09:00", "09:00", "12:00"),
        "白天": ("09:00", "06:00", "18:00"),
        "中午": ("12:00", "12:00", "15:00"),
        "下午": ("15:00", "12:00", "18:00"),
        "晚上": ("18:00", "18:00", nil),
    ]

    /// 時段的公開說法，依時間排序（給提示詞）。
    static let slotNames = ["凌晨", "清晨", "上午", "早上", "白天", "中午", "下午", "晚上"]

    /// 新增時用的時段，依時間排序：下一個時段由這裡推測。
    private static let nextSlots = ["06:00", "09:00", "12:00", "15:00", "18:00"]

    /// 當作時間點；範圍（以前、以後、到）與凌晨不是時間點，回傳 nil。
    var point: String? {
        if case .moment(let moment) = kind { moment.point } else { nil }
    }

    /// 當作範圍：時段是它的範圍，H點 是剛好那個時間。
    var range: TimeRange {
        switch kind {
        case .moment(let moment):
            if moment.hour != nil {
                let time = moment.boundary
                return TimeRange(from: time, to: time, includesEnd: true)
            }
            let slot = Self.slots[moment.slot!]!
            return TimeRange(from: slot.from, to: slot.to, includesEnd: false)
        case .before(let moment):
            return TimeRange(from: nil, to: moment.boundary, includesEnd: false)
        case .after(let moment):
            return TimeRange(from: moment.boundary, to: nil, includesEnd: false)
        case .between(let start, let end):
            return TimeRange(from: start.point, to: end.point, includesEnd: true)
        }
    }

    /// 現在之後的下一個時段（新增今天的待辦沒說時間時用）；18:00 以後沒有。
    static func nextSlot(after now: String) -> String? {
        nextSlots.first { $0 > now }
    }

    /// 整段字都要是時間：`時刻`、`時刻以前`、`時刻以後`、`時刻到時刻`。
    static func parse(_ text: Substring) -> Result<TimePhrase, DateParseError> {
        var rest = text
        var units: [String] = []
        let fail = { Result<TimePhrase, DateParseError>.failure(DateParseError(units: units, rest: rest.isEmpty ? String(text) : String(rest))) }

        func take(_ words: some Collection<String>) -> String? {
            guard let word = words.first(where: { rest.hasPrefix($0) }) else {
                return nil
            }
            rest = rest.dropFirst(word.count)
            units.append(word)
            return word
        }
        func number(_ regex: Regex<(Substring, Substring)>) -> Int? {
            guard let match = rest.prefixMatch(of: regex), let value = Int(match.1) else {
                return nil
            }
            rest = rest[match.range.upperBound...]
            units.append(String(match.0))
            return value
        }
        /// `[時段][H點[M分]]`，至少一項；`inherited` 是點到點後半沿用的時段。
        func moment(inherited: String? = nil) -> Moment?? {
            let slot = take(slots.keys)
            guard let hour = number(/(\d{1,2})點/) else {
                return slot.map { .some(Moment(slot: $0, hour: nil, minute: 0)) }
            }
            let minute = number(/(\d{1,2})分/) ?? 0
            guard (0...59).contains(minute), let converted = convert(hour, slot: slot ?? inherited) else {
                return .some(nil)
            }
            return .some(Moment(slot: slot, hour: converted, minute: minute))
        }

        guard case .some(.some(let first)) = moment() else {
            return fail()
        }
        let kind: Kind
        if take(["以前"]) != nil {
            kind = .before(first)
        } else if take(["以後"]) != nil {
            kind = .after(first)
        } else if take(["到"]) != nil {
            guard case .some(.some(let last)) = moment(inherited: first.slot),
                  let from = first.point, let to = last.point, from <= to
            else {
                return fail()
            }
            kind = .between(first, last)
        } else {
            kind = .moment(first)
        }
        guard rest.isEmpty else {
            return fail()
        }
        return .success(TimePhrase(kind: kind, units: units))
    }

    /// 依時段把 H 換成 24 小時制；不合法是 nil（見 docs/specs/date-time.md 的「時段加上 H點」）。
    private static func convert(_ hour: Int, slot: String?) -> Int? {
        switch slot {
        case nil:
            return (0...23).contains(hour) ? hour : nil
        case "下午", "晚上":
            guard (1...12).contains(hour), !(slot == "晚上" && hour == 12) else {
                return nil
            }
            return hour < 12 ? hour + 12 : hour
        case "中午":
            guard (0...12).contains(hour) else {
                return nil
            }
            return hour < 6 ? hour + 12 : hour
        default:
            return (0...12).contains(hour) ? hour : nil
        }
    }
}
