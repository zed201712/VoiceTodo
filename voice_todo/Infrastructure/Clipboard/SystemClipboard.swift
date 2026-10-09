//
//  SystemClipboard.swift
//  voicecalender
//

// 備份暫停（見 docs/specs/backup.md）。
/*
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 系統剪貼簿。iOS 讀別的 App 放進來的內容時，系統會跳出「允許貼上」（見 docs/specs/backup.md）。
struct SystemClipboard: Clipboard {

    func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    func paste() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }
}
*/
