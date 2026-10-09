//
//  Backup.swift
//  voicecalender
//

// 備份暫停（見 docs/specs/backup.md）。
/*
import Foundation

/// 備份：所有待辦的一份 JSON 文字；功能相同的 App 共用這個格式（見 docs/specs/backup.md）。
enum Backup {

    static let format = "voicetodo-backup"
    static let version = 1

    /// 先只讀這兩個欄位：版本不同時，待辦的結構可能也不同。
    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct File: Codable {
        let format: String
        let version: Int
        let todos: [Item]
    }

    /// 沒有 id 與「是否為示範資料」：id 是 App 內部的，換成備份後都是一般待辦。
    private struct Item: Codable {
        let date: String
        let time: String?
        let content: String
        let isDone: Bool
        let reminderID: String?
    }

    static func make(_ todos: [Todo]) -> String {
        let file = File(format: format, version: version, todos: todos.map {
            Item(date: $0.date, time: $0.time, content: $0.content, isDone: $0.isDone, reminderID: $0.reminderID)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(file), as: UTF8.self)
    }

    /// 整份檢查，有一項不對就丟出 ToolError；回傳的待辦 id 由 `TodoStore.replace(withBackup:)` 重新編。
    static func read(_ text: String) throws -> [Todo] {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw ToolError(message: "剪貼簿裡沒有備份")
        }
        guard header.version == version else {
            throw ToolError(message: "看不懂第 \(header.version) 版的備份")
        }
        guard let file = try? decoder.decode(File.self, from: data) else {
            throw ToolError(message: "剪貼簿裡沒有備份")
        }
        return try file.todos.enumerated().map { index, item in
            let invalid = { (reason: String) in ToolError(message: "備份的第 \(index + 1) 筆不合法：\(reason)") }
            guard TodoStore.isValidDay(item.date) else {
                throw invalid("日期 \(item.date)")
            }
            if let time = item.time, time.wholeMatch(of: /([01]\d|2[0-3]):[0-5]\d/) == nil {
                throw invalid("時間 \(time)")
            }
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw invalid("內容空白")
            }
            return Todo(id: 0, date: item.date, time: item.time, content: content, isDone: item.isDone, reminderID: item.reminderID)
        }
    }
}
*/
