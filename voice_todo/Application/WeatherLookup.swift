//
//  WeatherLookup.swift
//  voicecalender
//

import Foundation

/// 經緯度。
struct Coordinate: Equatable {
    let latitude: Double
    let longitude: Double

    /// 送給天氣服務的精度：小數 2 位（約 1 公里），預報的網格本來就是公里級（見 docs/specs/weather.md 的「地點」）。
    var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }
}

/// 天氣服務（見 docs/specs/weather.md 的「資料」）：介面讓測試可以換掉網路。日期是 `yyyy-MM-dd`，含頭尾。
protocol WeatherService {
    /// `log` 記下請求與原始回應（見 docs/specs/weather.md 的「紀錄」）。
    func daily(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Forecast]
    func hourly(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Hour]
}

/// 所在地與地名搜尋：介面讓測試可以換掉定位。
protocol Locator {
    /// 沒有定位權限時丟出 `LocatorError.denied`。
    func current() async throws -> Coordinate
    /// 找不到是 nil。只回傳座標：搜尋結果的名稱不能在沒有 Apple 地圖的地方顯示（見 docs/specs/weather.md 的「地點」）。
    func search(_ name: String) async throws -> Coordinate?
}

enum LocatorError: Error {
    case denied
}

/// 查天氣這個執行器（見 docs/specs/weather.md）：找出地點、查預報、組成回報。不改待辦、不碰黑板。
struct WeatherLookup {

    let service: any WeatherService
    let locator: any Locator
    /// 沒說地點時，用來說出所在地是哪個鄉鎮市區。
    var towns = Towns()

    enum Outcome: Equatable {
        /// 回話的文字、每天一句（給語音報告）、測試紀錄。
        case done(String, days: [String], log: String)
        /// 查不到：原因要念出來（見 docs/specs/spoken-report.md 的「念的內容」）。
        case failed(String, log: String)
        /// 參數不合法：和其他指令的放棄相同。
        case abandon(String)
    }

    /// `log` 是天氣服務的請求與回應，寫進測試紀錄。
    func run(_ command: Command, now: Date, log: @escaping (String) -> Void = { _ in }) async -> Outcome {
        let request: Weather.Request
        switch Weather.request(command.date, now: now) {
        case .success(let value):
            request = value
        case .failure(let error) where error.message == Weather.outOfRange:
            return .failed(error.message, log: error.message)
        case .failure(let error):
            return .abandon(error.message)
        }

        let name: String
        var coordinate: Coordinate
        do {
            if let place = command.place {
                guard Weather.isPlaceName(place) else {
                    return .failed("這不像地名，沒有查詢", log: "地名檢查：不像地名，沒有送出（\(place.count) 字）")
                }
                guard let found = try await locator.search(place) else {
                    let message = "找不到「\(place)」這個地方"
                    return .failed(message, log: message)
                }
                (name, coordinate) = (place, found)
            } else {
                coordinate = try await locator.current()
                // 判斷在裝置上做，用原始座標比較準。
                name = towns.name(latitude: coordinate.latitude, longitude: coordinate.longitude) ?? "所在地"
            }
        } catch LocatorError.denied {
            let message = "沒有定位權限，查不到所在地的天氣，請到系統設定允許"
            return .failed(message, log: message)
        } catch {
            return .failed("找不到所在地", log: "定位失敗：\(error.localizedDescription)")
        }

        coordinate = coordinate.rounded
        let target = "\(name)（\(coordinate.latitude),\(coordinate.longitude)）\(request.from)~\(request.to)"
        let forecasts: [Weather.Forecast]
        do {
            if request.time == nil {
                forecasts = try await service.daily(at: coordinate, from: request.from, to: request.to, log: log)
            } else {
                let hours = try await service.hourly(at: coordinate, from: request.from, to: request.to, log: log)
                forecasts = Weather.summarize(hours, request: request, now: now)
            }
        } catch {
            return .failed("天氣服務沒有回應", log: "\(target)：\(error.localizedDescription)")
        }
        guard !forecasts.isEmpty else {
            return .failed(Weather.passed, log: "\(target)：\(Weather.passed)")
        }

        let days = forecasts.map { Weather.sentence($0, place: name, timeLabel: request.timeLabel) }
        let lines = days + (request.clipped ? ["其他天\(Weather.outOfRange)。"] : [])
        return .done(lines.joined(separator: "\n"), days: days, log: "\(target)：\(lines.joined())")
    }
}
