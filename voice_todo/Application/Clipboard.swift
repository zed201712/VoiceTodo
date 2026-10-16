//
//  Clipboard.swift
//  voicecalender
//

import Foundation

/// 剪貼簿：點內容複製文字（見 docs/specs/todos.md 的「黑板」）；備份也用它（暫停，見 docs/specs/backup.md）。
protocol Clipboard {
    func copy(_ text: String)
    /// 沒有文字時是 nil。
    func paste() -> String?
}
