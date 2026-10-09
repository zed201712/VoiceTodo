//
//  TownBoundaries.swift
//  voicecalender
//

import Foundation

/// App 內建的鄉鎮市區邊界（`towns.json`，由 tools/make_towns.py 產生；見 docs/specs/weather.md 的「地點」）。
/// 不用 MapKit 的反向地名搜尋：Apple 的條款不允許不顯示 Apple 地圖就顯示它的地圖資料。
enum TownBoundaries {

    /// 資料來源的標示（Markdown，連結可以點）。政府資料開放授權條款第 1 版（https://data.gov.tw/license）：
    /// 要標示提供機關、年份、資料名稱，說明依條款釋出並附連結；邊界經過簡化。條款沒有規定位置，只放在設定頁。
    static let credit = "地名資料：內政部國土測繪中心 2025 鄉鎮市區界線（1140318 版），依[政府資料開放授權條款](https://data.gov.tw/license)釋出，經過簡化"

    /// 讀不到時是空的，所在地照舊說「所在地」。
    static func load() -> Towns {
        guard let url = Bundle.main.url(forResource: "towns", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let towns = try? JSONDecoder().decode(Towns.self, from: data) else {
            return Towns()
        }
        return towns
    }
}
