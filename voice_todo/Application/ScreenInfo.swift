//
//  ScreenInfo.swift
//  voicecalender
//

import Foundation

/// 畫面資訊（見 docs/specs/screen-info.md）：使用者開口時看到的畫面，給自動 AI 看。
/// 每個欄位最多 100 字，在欄位自己的單位（一行、一句）的邊界截斷。
struct ScreenInfo {
    /// 例如 `2026/10/2（五）14:30`。
    let now: String
    /// 範圍與查詢條件；空的就不列。
    let boardTitle: String
    /// 黑板上看得到的待辦，每筆一行。
    let board: [String]
    /// 最後一則回話的內容，每行一項。
    let dialog: [String]
    /// 等釐清或刪除確認時的問題。
    let question: String?
    /// 還沒凍結的提示對話框目前那一頁；規則判斷與 AI 判斷用（見 docs/specs/help.md 的「判斷」）。
    var hint: Hint? = nil

    struct Hint: Equatable {
        let page: String
        let links: [String]

        /// 一般判斷的請求多的一行；沒有連結時不列括號。
        var line: String {
            "提示：\(page)" + (links.isEmpty ? "" : "（連結：\(links.joined(separator: "、"))）")
        }
    }

    static let limit = 100

    /// 黑板（標題與看得到的待辦）相同：聊天要不要重做只比這個，不比現在時間與回話（見 docs/specs/chat.md）。
    func sameBoard(as other: ScreenInfo) -> Bool {
        boardTitle == other.boardTitle && board == other.board
    }

    /// `extra` 是聊天的補充資訊，放在「使用者說」的前一行，不受 100 字的限制（見 docs/specs/chat.md）。
    func request(userSaid: String, extra: String? = nil) -> String {
        let title = boardTitle.isEmpty ? [] : [boardTitle]
        var fields = [("現在", now)]
        fields.append(("黑板", board.isEmpty ? "無資料" : Self.lines(title + board) { "…還有 \($0) 項" }))
        let dialog = dialog.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !dialog.isEmpty {
            fields.append(("小精靈說", Self.lines(dialog) { _ in "…" }))
        }
        if let question {
            fields.append(("小精靈剛才問", Self.clip(question)))
        }
        let lines = fields.map { "\($0)：\($1)" } + (extra.map { [$0] } ?? [])
        return (lines + ["使用者說：\(Self.clip(userSaid))"]).joined(separator: "\n")
    }

    /// 以一行為單位截斷；有省略時最後加一行標記。
    private static func lines(_ units: [String], marker: (Int) -> String) -> String {
        let (kept, omitted) = fit(units)
        return (kept + (omitted > 0 ? [marker(omitted)] : [])).joined(separator: "\n")
    }

    /// 以一句為單位截斷；有省略時接上 `…`。聊天的回應也用這個規則。
    static func clip(_ text: String) -> String {
        let (kept, omitted) = fit(sentences(text))
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines) + (omitted > 0 ? "…" : "")
    }

    /// `。！？` 與換行切開，標點與換行留在前一句。
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if character.isNewline, current.isEmpty, !result.isEmpty {
                result[result.count - 1].append(character)
                continue
            }
            current.append(character)
            if "。！？".contains(character) || character.isNewline {
                result.append(current)
                current = ""
            }
        }
        result.append(current)
        return result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 從頭取完整的單位，總字數不超過上限；回傳取到的單位與省略的數量。
    /// 第一個單位就超過時，在前 100 字裡最後一個標點之後切開（被切的那個也算省略），沒有標點就取前 100 字。
    static func fit(_ units: [String]) -> ([String], Int) {
        var kept: [String] = []
        var count = 0
        for (index, unit) in units.enumerated() {
            if count + unit.count > limit {
                if kept.isEmpty {
                    let head = unit.prefix(limit)
                    let cut = head.lastIndex { "。！？；，、".contains($0) }.map { head[...$0] } ?? head
                    return ([String(cut)], units.count - index)
                }
                return (kept, units.count - index)
            }
            kept.append(unit)
            count += unit.count
        }
        return (kept, 0)
    }

    /// 例如 `2026/10/2（五）09:05`。
    static func now(_ date: Date) -> String {
        let day = TodoStore.dayString(date)
        let time = Calendar.current.dateComponents([.hour, .minute], from: date)
        return "\(day.prefix(4))/\(DatePhrase.dayLabel(day))" + String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }
}
