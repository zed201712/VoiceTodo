//
//  OpenMeteoWeather.swift
//  voicecalender
//

import Foundation

/// 天氣服務的 Open-Meteo 實作（見 docs/specs/weather.md 的「資料」）：不用 key；非商業用途每天 1 萬次。
struct OpenMeteoWeather: WeatherService {

    /// 資料來源的標示（Markdown，連結可以點）。Open-Meteo 的資料是 CC BY 4.0（https://open-meteo.com/en/licence）：
    /// 顯示資料的地方旁邊要有連到 Open-Meteo 的連結、連到授權的連結，並註明有改動（我們濃縮了逐小時預報、把代碼翻成中文）。
    static let credit = "天氣資料：[Open-Meteo.com](https://open-meteo.com/)（[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)），經過整理"

    private static let endpoint = "https://api.open-meteo.com/v1/forecast"
    private static let timeout: TimeInterval = 15

    func daily(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Forecast] {
        let data = try await fetch(place, from: from, to: to, fields: ["daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"], log: log)
        return try Self.decodeDaily(data)
    }

    func hourly(at place: Coordinate, from: String, to: String, log: @escaping (String) -> Void) async throws -> [Weather.Hour] {
        let data = try await fetch(place, from: from, to: to, fields: ["hourly": "weather_code,temperature_2m,precipitation_probability"], log: log)
        return try Self.decodeHourly(data)
    }

    /// `timezone=auto`：時間是那個地點的當地時間。
    private func fetch(_ place: Coordinate, from: String, to: String, fields: [String: String], log: (String) -> Void) async throws -> Data {
        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: from),
            URLQueryItem(name: "end_date", value: to),
        ] + fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Self.timeout
        log("請求：\(components.url!.absoluteString)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("回應：\(error.localizedDescription)")
            throw error
        }
        log("回應：HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) \(String(decoding: data, as: UTF8.self))")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(Failure.self, from: data))?.reason ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw ToolError(message: reason)
        }
        return data
    }

    private struct Failure: Decodable {
        let reason: String
    }

    // 數值可能是 null（沒有資料），那一筆就不列。

    private struct DailyResponse: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]
        }
        let daily: Daily
    }

    private struct HourlyResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m: [Double?]
            let precipitation_probability: [Int?]
        }
        let hourly: Hourly
    }

    static func decodeDaily(_ data: Data) throws -> [Weather.Forecast] {
        let daily = try JSONDecoder().decode(DailyResponse.self, from: data).daily
        return daily.time.indices.compactMap { index in
            guard let code = daily.weather_code[index], let high = daily.temperature_2m_max[index], let low = daily.temperature_2m_min[index] else {
                return nil
            }
            return Weather.Forecast(day: daily.time[index], code: code, low: low, high: high, rainChance: daily.precipitation_probability_max[index] ?? 0)
        }
    }

    /// 時間是 `yyyy-MM-ddTHH:mm`。
    static func decodeHourly(_ data: Data) throws -> [Weather.Hour] {
        let hourly = try JSONDecoder().decode(HourlyResponse.self, from: data).hourly
        return hourly.time.indices.compactMap { index in
            let parts = hourly.time[index].split(separator: "T")
            guard parts.count == 2, let code = hourly.weather_code[index], let temperature = hourly.temperature_2m[index] else {
                return nil
            }
            return Weather.Hour(day: String(parts[0]), time: String(parts[1]), code: code, temperature: temperature, rainChance: hourly.precipitation_probability[index] ?? 0)
        }
    }
}
