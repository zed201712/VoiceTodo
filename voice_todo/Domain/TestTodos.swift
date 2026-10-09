//
//  TestTodos.swift
//  voicecalender
//

import Foundation

/// 測試待辦：除錯 UI 的測試清單、單元測試與 Preview 用的固定起點（見 docs/specs/storage.md 的「測試清單」、
/// docs/eval/judge-cases.md 的「測試待辦」）。這個月和下個月各 4 筆，一部分有時間、一部分沒有。
enum TestTodos {

    static func make(today: Date = .now) -> [Todo] {
        let samples: [(month: Int, day: Int, time: String?, content: String)] = [
            (0, 3, nil, "繳電話費"), (0, 12, "15:00", "看牙醫"), (0, 18, "09:00", "部門會議"), (0, 25, nil, "買牛奶"),
            (1, 2, nil, "買牛奶"), (1, 9, "09:00", "部門會議"), (1, 16, nil, "媽媽生日"), (1, 28, nil, "繳房租"),
        ]
        let calendar = DatePhrase.calendar
        let thisMonth = calendar.dateInterval(of: .month, for: today)!.start
        return samples.enumerated().map { index, sample in
            let month = calendar.date(byAdding: .month, value: sample.month, to: thisMonth)!
            let date = calendar.date(byAdding: .day, value: sample.day - 1, to: month)!
            return Todo(id: index + 1, date: TodoStore.dayString(date), time: sample.time, content: sample.content)
        }
    }
}
