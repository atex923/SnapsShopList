# SnapshotBuyCheck V0.0.5 驗證紀錄

驗證日期：2026-09-06

## 已通過

- iOS 26.5 SDK、通用 iOS Simulator Debug build。
- Xcode Analyze 靜態分析。
- 通用 iPhoneOS Debug build，Automatic Signing／Personal Team。
- iPhoneOS Release build（停用簽署），包含 CloudKit 程式分支與 entitlement。
- 標準 iPhone 16、iOS 26.5 模擬器安裝及啟動成功。
- 首頁以 iPhone 16 原生 1179 × 2556 截圖確認，無截字或控制項重疊。
- `project.pbxproj` 與 entitlement 格式檢查通過。
- `history/V0.0.4/` 與原 V0.0.4 專案內容一致。

## 仍需實機驗證

- 相機條碼辨識與商品拍照。
- GPS 定位及台灣縣市／行政區反向地理編碼結果。
- 照片寫入手機相簿。
- 具正式 iCloud／CloudKit entitlement 的 Apple Developer 團隊跨裝置同步。

目前連接的 Atex-iPhone12mini 為 iOS 15.5，低於本專案 iOS 26.0 最低版本，無法用於本次實機執行測試。
