//
//  TodoStorage.swift
//  voicecalender
//

import Foundation

/// 待辦的存檔（見 docs/specs/storage.md 的「介面」）：整份讀、整份寫，和背後是提醒事項還是 JSON 無關。
/// 待辦的 id 由存檔給：同一筆資料重新讀取時沿用原本的 id。
protocol TodoStorage: AnyObject {
    /// 讀取目前讀過的範圍（第一次是常用的部分）；需要權限時在這裡請求。沒有權限或讀取失敗時丟出錯誤，附上原因。
    func load() async throws -> [Todo]
    /// 讀取時沒給的其餘待辦；已經讀過或一次就能全讀的存檔回傳空的。
    func loadRest() async throws -> [Todo]
    /// 給整份待辦，存檔自己算出差異並套用；沒讀過的項目不受影響。
    func save(_ todos: [Todo]) throws
    /// 換成只有 `seed` 的獨立測試資料；nil 是換回真實的資料（見 docs/specs/storage.md 的「測試清單」）。
    func useTestData(_ seed: [Todo]?) async throws
    /// 存檔被 App 以外的地方改了時呼叫；只有 App 會改的存檔永遠不呼叫。
    var onExternalChange: (() -> Void)? { get set }
}
