//
//  IntentQueue.swift
//  voicecalender
//

import Foundation

/// 輸入、執行、結果三個佇列（見 docs/specs/queue.md）：一句話照說話的順序排隊，背景同時最多解讀 `limit` 句，
/// 解讀好的使用者意圖照輸入順序輪到；也記住目前的問題，判斷一句話是不是回答。
///
/// 時間點是遞增的整數（開口、問題出現），只用來比先後。
struct IntentQueue<Input, Intent> {

    struct Entry {
        let number: Int
        let input: Input
        /// 開口的時間點。
        let spokenAt: Int
        fileprivate(set) var state: State
    }

    enum State {
        /// 在輸入佇列，還沒開始解讀。
        case queued
        /// 在執行佇列，解讀中。
        case preparing
        /// 在結果佇列，等輪到。
        case ready(Intent)
    }

    /// 同時解讀的上限。
    var limit = 2
    /// 還沒輪到的句子，照輸入順序。
    private(set) var entries: [Entry] = []

    /// 目前問題出現的時間點；沒在等回答是 nil。
    private var question: Int?
    /// 這個問題已經有回答了。
    private var answered = false

    /// 放進輸入佇列；回傳可以開始解讀的句子。
    mutating func enqueue(_ number: Int, _ input: Input, spokenAt: Int) -> [Entry] {
        entries.append(Entry(number: number, input: input, spokenAt: spokenAt, state: .queued))
        return startable()
    }

    /// 解讀完成，放進結果佇列；回傳接著可以開始解讀的句子。
    mutating func prepared(_ number: Int, _ intent: Intent) -> [Entry] {
        guard let index = entries.firstIndex(where: { $0.number == number }) else {
            return []
        }
        entries[index].state = .ready(intent)
        return startable()
    }

    /// 照輸入順序，把還有名額的句子從輸入佇列移到執行佇列。
    mutating func startable() -> [Entry] {
        var started: [Entry] = []
        var preparing = entries.count { if case .preparing = $0.state { true } else { false } }
        for index in entries.indices where preparing < limit {
            guard case .queued = entries[index].state else {
                continue
            }
            entries[index].state = .preparing
            started.append(entries[index])
            preparing += 1
        }
        return started
    }

    /// 輪到最前面的句子：已經解讀好就取出，否則是 nil。
    mutating func next() -> (entry: Entry, intent: Intent)? {
        guard let first = entries.first, case .ready(let intent) = first.state else {
            return nil
        }
        entries.removeFirst()
        return (first, intent)
    }

    /// 最前面的句子還在排隊或解讀中。
    var isHeadPending: Bool {
        guard let first = entries.first else {
            return false
        }
        if case .ready = first.state {
            return false
        }
        return true
    }

    /// 全部取消：清空，回傳被丟掉的句子。
    mutating func removeAll() -> [Entry] {
        defer { entries = [] }
        return entries
    }

    // MARK: - 回答

    /// 目前的結果開始等回答：問題出現在這個時間點。
    mutating func ask(at moment: Int) {
        question = moment
        answered = false
    }

    mutating func endQuestion() {
        question = nil
        answered = false
    }

    /// 問題出現之後才開口的第一句話是回答；是回答就佔用這次回答的機會。
    mutating func claimAnswer(spokenAt: Int) -> Bool {
        guard let question, !answered, spokenAt > question else {
            return false
        }
        answered = true
        return true
    }
}

/// 報告顯示時間（見 docs/specs/queue.md）：沒有念的結果最少顯示 2 秒 + 每字 0.1 秒，最多 5 秒。
enum DisplayTime {

    static func of(_ text: String) -> Duration {
        let count = text.count { !$0.isWhitespace }
        return min(.seconds(2) + .milliseconds(100 * count), .seconds(5))
    }
}

/// 回音：念的期間開口、去掉標點與空白後是正在念的文字的一部分，是小精靈自己的聲音漏進麥克風（見 docs/specs/queue.md）。
enum Echo {

    static func isEcho(_ sentence: String, of spoken: String) -> Bool {
        let word = ConfirmationKeywords.normalized(sentence)
        return !word.isEmpty && ConfirmationKeywords.normalized(spoken).contains(word)
    }
}
