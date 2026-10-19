//
//  Weather.swift
//  voicecalender
//

import Foundation

/// 查天氣的規則（見 docs/specs/weather.md）：日期說法換成查詢範圍、濃縮逐小時預報、組句子。
/// 純函式，不碰網路與定位（天氣服務由 Application 層注入）。
enum Weather {

    /// 地名由 AI 判斷填寫，送到地名搜尋前檢查：超過 20 字、連續 4 個以上的數字、英數混合的字串（金鑰、密碼）不像地名，不送出
    /// （見 docs/specs/weather.md 的「地點」、憲章 D1 的「外部功能的資料進出」）。
    static func isPlaceName(_ text: String) -> Bool {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 20, name.firstMatch(of: /[0-9]{4,}/) == nil else {
            return false
        }
        let tokens = name.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return !tokens.contains { $0.contains(where: \.isLetter) && $0.contains(where: \.isNumber) }
    }

    /// 天氣服務只有今天起這麼多天的預報。
    static let days = 16
    static let outOfRange = "只能查今天起 16 天內的天氣"
    static let passed = "那段時間已經過了"

    /// 一天（或一天裡的一段時間）的預報。
    struct Forecast: Equatable {
        /// `yyyy-MM-dd`
        let day: String
        /// WMO 天氣代碼。
        let code: Int
        let low: Double
        let high: Double
        /// 降雨機率（%）。
        let rainChance: Int
    }

    /// 一個小時的預報。
    struct Hour: Equatable {
        /// `yyyy-MM-dd`
        let day: String
        /// 整點，`HH:mm`。
        let time: String
        let code: Int
        let temperature: Double
        let rainChance: Int
    }

    /// 要查的範圍：日期已經截在今天起 16 天內；`time` 是說了時間時的範圍，`timeLabel` 是那段時間的說法。
    struct Request: Equatable {
        let from: String
        let to: String
        let time: TimeRange?
        let timeLabel: String
        /// 有一部分在 16 天外，被截掉了。
        let clipped: Bool
    }

    /// 日期照查詢的換算；沒說日期（或只說時間）是今天。「下次」「所有」與看不懂的說法放棄。
    static func request(_ date: String?, now: Date) -> Result<Request, ToolError> {
        let today = TodoStore.dayString(now)
        var from = today
        var to = today
        var time: TimePhrase?
        if let date {
            switch DatePhrase.parse(date, today: now) {
            case .failure(let error):
                return .failure(ToolError(message: error.localizedDescription))
            case .success(let parsed):
                time = parsed.time
                switch parsed.days {
                case .range(let start, let end):
                    (from, to) = (start, end)
                case .none:
                    break
                case .next, .everything:
                    return .failure(ToolError(message: "天氣要說哪一天"))
                }
            }
        }
        let last = TodoStore.dayString(DatePhrase.calendar.date(byAdding: .day, value: days - 1, to: now)!)
        let clippedFrom = max(from, today)
        let clippedTo = min(to, last)
        guard clippedFrom <= clippedTo else {
            return .failure(ToolError(message: outOfRange))
        }
        return .success(Request(
            from: clippedFrom,
            to: clippedTo,
            time: time?.range,
            timeLabel: time?.units.joined() ?? "",
            clipped: clippedFrom != from || clippedTo != to
        ))
    }

    /// 說了時間時：每天取那段時間的小時（今天只算還沒到的），濃縮成一句的資料；那天沒有小時就不列。
    /// 天氣代碼取最大（WMO 代碼大致依嚴重程度排列）、溫度取最低～最高、降雨機率取最高。
    static func summarize(_ hours: [Hour], request: Request, now: Date) -> [Forecast] {
        let today = TodoStore.dayString(now)
        let currentHour = String(format: "%02d:00", DatePhrase.calendar.component(.hour, from: now))
        let kept = hours.filter { hour in
            hour.day >= request.from && hour.day <= request.to
                && (request.time.map { overlaps($0, hour: hour.time) } ?? true)
                && (hour.day != today || hour.time >= currentHour)
        }
        let days = kept.map(\.day).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return days.map { day in
            let group = kept.filter { $0.day == day }
            return Forecast(
                day: day,
                code: group.map(\.code).max()!,
                low: group.map(\.temperature).min()!,
                high: group.map(\.temperature).max()!,
                rainChance: group.map(\.rainChance).max()!
            )
        }
    }

    /// 那個小時（`HH:00` 到下一個整點）和時間範圍有重疊：「下午3點30分」落在 15:00 那個小時。
    private static func overlaps(_ range: TimeRange, hour: String) -> Bool {
        let end = String(format: "%02d:00", (Int(hour.prefix(2)) ?? 0) + 1)
        let startsBeforeEnd = (range.from ?? "00:00") < end
        let endsAfterStart = range.to.map { range.includesEnd ? hour <= $0 : hour < $0 } ?? true
        return startsBeforeEnd && endsAfterStart
    }

    /// WMO 天氣代碼的中文。
    static func name(_ code: Int) -> String {
        switch code {
        case 0: "晴"
        case 1: "大致晴朗"
        case 2: "多雲"
        case 3: "陰"
        case 45, 48: "霧"
        case 51...57: "毛毛雨"
        case 61...65: "雨"
        case 66, 67: "凍雨"
        case 71...77: "雪"
        case 80...82: "陣雨"
        case 85, 86: "陣雪"
        case 95...99: "雷雨"
        default: "不明"
        }
    }

    /// `<地點>，<日期><時間>：<天氣>，<低>～<高> 度，降雨機率 <N>%。`；溫度四捨五入，低高相同只說一個。
    static func sentence(_ forecast: Forecast, place: String, timeLabel: String) -> String {
        let low = Int(forecast.low.rounded())
        let high = Int(forecast.high.rounded())
        let temperature = low == high ? "\(low)" : "\(low)～\(high)"
        return "\(place)，\(SpokenDate.day(forecast.day))\(timeLabel)：\(name(forecast.code))，\(temperature) 度，降雨機率 \(forecast.rainChance)%。"
    }
}
