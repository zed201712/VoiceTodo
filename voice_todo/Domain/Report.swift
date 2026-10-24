//
//  Report.swift
//  voice_todo
//

import Foundation

/// 一條指令成功的結構化結果（見 docs/specs/spoken-report.md 的「結構」）：Domain 只回傳它，回話與念的句子由 Application 的 SpokenReport 組成。
/// 刪除 2 項以上時在確認後由小精靈產生。
enum Report: Equatable {
    case added(Todo)
    /// 用編號一次改好幾筆時有多筆，修改前後依同樣的順序。
    case modified(before: [Todo], after: [Todo])
    case deleted([Todo])
    case setDone([Todo], isDone: Bool)
    /// 複製出來的新待辦。
    case copied([Todo])
    /// 查詢日期：使用者的說法與換算出的範圍（`yyyy-MM-dd`）。
    case date(phrase: String, from: String, to: String)
    /// 查詢後黑板上看得到的項目。
    case queried([Todo])
    /// 聊天的回應，照原文念（見 docs/specs/chat.md）。
    case chat(String)
    /// 查天氣：每天一句（見 docs/specs/weather.md 的「回報」）。
    case weather([String])
    // 以下不念，只有回話。
    /// 設定顯示：「完成」是否勾選。
    case display(showDone: Bool)
    /// 復原、重做：資料從 before 換成 after。
    case recovered(undo: Bool, before: [Todo], after: [Todo])
    /// 復原、重做：沒有可以回到的狀態。
    case nothingToRecover(undo: Bool)
    /// 上一頁、下一頁、顯示全部；`moved` 是黑板有沒有換頁。
    case navigated(BoardAction, moved: Bool)
}


/// 日期與時刻的念法：語音報告與天氣的句子共用（見 docs/specs/spoken-report.md 的「念的內容」）。
enum SpokenDate {

    /// `yyyy-MM-dd` → `10月9日星期五`
    static func day(_ day: String) -> String {
        guard let date = try? TodoStore.dayFormat.parse(day) else {
            return day
        }
        let calendar = DatePhrase.calendar
        let weekday = DatePhrase.weekdays[(calendar.component(.weekday, from: date) + 5) % 7].dropFirst()
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日星期\(weekday)"
    }

    /// `HH:mm` → 依時段念，例如 `13:30` → `下午1點30分`、`06:00` → `清晨6點`。
    static func time(_ time: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            return time
        }
        let (hour, minute) = (parts[0], parts[1])
        let period = switch hour {
        case ..<6: "凌晨"
        case ..<9: "清晨"
        case ..<12: "早上"
        case 12: "中午"
        case ..<18: "下午"
        default: "晚上"
        }
        let clock = hour > 12 ? hour - 12 : hour
        return "\(period)\(clock)點" + (minute == 0 ? "" : "\(minute)分")
    }
}
