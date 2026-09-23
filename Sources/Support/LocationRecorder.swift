import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var statusText = "尚未取得定位"
    @Published private(set) var isLocating = false
    @Published private(set) var suggestedCity = ""
    @Published private(set) var suggestedDistrict = ""
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var transientFailureRetryCount = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    func requestLocation() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        switch authorizationStatus {
        case .notDetermined:
            statusText = "等待定位權限"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            transientFailureRetryCount = 0
            isLocating = true
            statusText = "正在取得 GPS…"
            manager.requestLocation()
        case .denied:
            isLocating = false
            statusText = "定位權限已關閉，仍可存檔"
        case .restricted:
            isLocating = false
            statusText = "此裝置限制定位，仍可存檔"
        @unknown default:
            isLocating = false
            statusText = "無法判斷定位狀態"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization
            guard manager.authorizationStatus != .notDetermined else { return }
            self.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.location = newest
            self.isLocating = false
            self.accuracyAuthorization = manager.accuracyAuthorization
            let accuracyLabel = manager.accuracyAuthorization == .reducedAccuracy ? "約略定位" : "GPS"
            self.statusText = String(format: "%@ 已取得（誤差約 %.0f 公尺）", accuracyLabel, newest.horizontalAccuracy)
            self.resolveRegion(for: newest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let locationError = error as? CLError,
               locationError.code == .locationUnknown,
               self.transientFailureRetryCount < 1 {
                self.transientFailureRetryCount += 1
                self.statusText = "定位暫時失敗，正在重試…"
                manager.requestLocation()
                return
            }
            self.isLocating = false
            self.statusText = "GPS 取得失敗，仍可存檔"
            AppErrorLogger.record(error, category: "GPS", context: "新增採買紀錄")
        }
    }

    private func resolveRegion(for location: CLLocation) {
        reverseGeocodingRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        request.preferredLocale = Locale(identifier: "zh_TW")
        reverseGeocodingRequest = request
        request.getMapItems { [weak self] mapItems, error in
            guard let self else { return }
            if let error {
                AppErrorLogger.record(error, category: "GPS 地址", context: "反查縣市與行政區")
                return
            }
            guard let mapItem = mapItems?.first else { return }
            let fullAddress = mapItem.address?.fullAddress ?? ""
            let city = mapItem.addressRepresentations?.cityName
                ?? self.firstMatch(in: fullAddress, pattern: #"[^\s,，0-9]{2,3}[縣市]"#)
                ?? ""
            let addressAfterCity = city.isEmpty
                ? fullAddress
                : fullAddress.replacingOccurrences(of: city, with: "")
            let district = self.firstMatch(
                in: addressAfterCity,
                pattern: #"[^\s,，0-9]{1,5}(?:區|鄉|鎮|市)"#
            ) ?? ""
            self.suggestedCity = city
            self.suggestedDistrict = district
            if !city.isEmpty || !district.isEmpty {
                let region = [city, district].filter { !$0.isEmpty }.joined(separator: " ")
                self.statusText = "GPS 已取得・已帶入 \(region)"
            }
        }
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
