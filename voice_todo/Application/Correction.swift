//
//  Correction.swift
//  voicecalender
//

import Foundation

/// 校正階段的規則（見 docs/specs/correction.md）：規則校正拿掉多餘的空白、決定採不採用 AI 校正的句子。請求是畫面資訊（`ScreenInfo`）。
enum Correction {

    /// 規則校正：拿掉多餘的空白，再把時刻改成幾點幾分（見 docs/specs/correction.md 的「規則校正」）。
    static func tool(_ text: String) -> String {
        rewriteTimes(removeSpaces(text))
    }

    /// `H:MM` 改成「H點」或「H點M分」（「9:00」→「9點」、「9:30」→「9點30分」）：日期與時間解析只認得「點」。
    static func rewriteTimes(_ text: String) -> String {
        text.replacing(/(^|\D)(\d{1,2})[:：](\d{2})(?!\d)/) { match in
            let minutes = Int(match.3) ?? 0
            return "\(match.1)\(match.2)點" + (minutes == 0 ? "" : "\(minutes)分")
        }
    }

    /// 空白兩邊都是英文字母或數字才保留，其他都拿掉（「10月 6號」→「10月6號」）。
    static func removeSpaces(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            guard character.isWhitespace else {
                result.append(character)
                continue
            }
            let before = characters[..<index].last { !$0.isWhitespace }
            let after = characters[(index + 1)...].first { !$0.isWhitespace }
            if let before, let after, Self.isLatin(before), Self.isLatin(after) {
                result.append(character)
            }
        }
        return result
    }

    private static func isLatin(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// 句子裡的數字（阿拉伯數字與國字數字），依出現的順序：校正不能改（見 docs/specs/correction.md 的「採用規則」）。
    private static func numerals(_ text: String) -> [Character] {
        text.filter { $0.isASCII ? $0.isNumber : "零一二兩三四五六七八九十百".contains($0) }.map { $0 }
    }

    /// 只修錯別字：數字不變、字數相同、內容不同才採用，否則用原句。`note` 給除錯 UI 與測試紀錄。
    static func accept(_ output: String, for original: String) -> (text: String, note: String) {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output == original {
            return (original, "未修改")
        }
        if numerals(output) != numerals(original) {
            return (original, "改了數字，不採用：\(output)")
        }
        if output.count != original.count {
            return (original, "字數不同，不採用：\(output)")
        }
        return (output, "\(original) → \(output)")
    }
}
