//
//  Towns.swift
//  voicecalender
//

import Foundation

/// 座標落在哪個鄉鎮市區（見 docs/specs/weather.md 的「地點」）：用 App 內建的邊界判斷，不送出任何東西。
struct Towns: Decodable {

    struct Town: Decodable {
        /// 縣市＋鄉鎮市區，例如「臺北市信義區」。
        let name: String
        /// 每個區塊的邊界：經度、緯度交錯排列。
        let rings: [[Double]]
    }

    let towns: [Town]

    init(_ towns: [Town] = []) {
        self.towns = towns
    }

    init(from decoder: any Decoder) throws {
        towns = try decoder.singleValueContainer().decode([Town].self)
    }

    /// 不在任何一區是 nil。
    func name(latitude: Double, longitude: Double) -> String? {
        towns.first { Self.contains($0, latitude: latitude, longitude: longitude) }?.name
    }

    /// 從那一點往東畫一條線，穿過那一區的邊界奇數次就在裡面；所有區塊一起算，中間的洞（例如嘉義縣包著嘉義市）才不會算進去。
    private static func contains(_ town: Town, latitude: Double, longitude: Double) -> Bool {
        var inside = false
        for ring in town.rings {
            let count = ring.count / 2
            var j = count - 1
            for i in 0..<count {
                let (x1, y1, x2, y2) = (ring[2 * i], ring[2 * i + 1], ring[2 * j], ring[2 * j + 1])
                if (y1 > latitude) != (y2 > latitude), longitude < (x2 - x1) * (latitude - y1) / (y2 - y1) + x1 {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }
}
