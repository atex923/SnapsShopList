import CoreLocation
import Foundation

final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var statusText = "尚未取得定位"
    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = "等待定位權限"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        location = newest
        isLocating = false
        statusText = String(format: "GPS 已取得（誤差約 %.0f 公尺）", newest.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        statusText = "GPS 取得失敗，仍可存檔"
        AppErrorLogger.record(error, category: "GPS", context: "新增採買紀錄")
    }
}
