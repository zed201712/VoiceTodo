//
//  SystemLocator.swift
//  voicecalender
//

import CoreLocation
import MapKit

/// 所在地（CoreLocation）與地名搜尋（MapKit）。第一次查所在地時才請求定位權限（見 docs/specs/weather.md 的「地點」）。
struct SystemLocator: Locator {

    func current() async throws -> Coordinate {
        // iOS 有 session 時系統才會請求權限；macOS 沒有 CLServiceSession，改由 CLLocationManager 請求。拿到位置就結束。
        #if os(iOS)
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        #else
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()
        defer { withExtendedLifetime(manager) {} }
        #endif
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                throw LocatorError.denied
            }
            if let location = update.location {
                return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        }
        throw ToolError(message: "沒有取得位置")
    }

    /// 取第一筆，不釐清同名的地點。只用座標：MapKit 的名稱不能在沒有 Apple 地圖的地方顯示（Apple Developer Program License Agreement 的 Attachment 6 §2.4）。
    func search(_ name: String) async throws -> Coordinate? {
        guard let request = MKGeocodingRequest(addressString: name) else {
            return nil
        }
        request.preferredLocale = Locale(identifier: "zh-TW")
        let items: [MKMapItem]
        do {
            items = try await request.mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return nil
        }
        guard let item = items.first else {
            return nil
        }
        let coordinate = item.location.coordinate
        return Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
