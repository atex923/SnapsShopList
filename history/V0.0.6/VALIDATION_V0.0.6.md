# SnapshotBuyCheck V0.0.6 驗證紀錄

驗證日期：2026-09-06

## 已驗證

- iOS 26.5 SDK 通用模擬器 Debug build。
- Xcode Analyze 靜態分析。
- 通用 iPhoneOS Debug build，Automatic Signing／Personal Team。
- iPhoneOS Release build（停用簽署），包含 CloudKit 程式分支與 entitlement。
- 標準 iPhone 16、iOS 26.5 模擬器安裝與啟動。
- 首頁以 1179 × 2556 原生解析度確認：不需捲動、兩個上方方格內容對齊、頁尾與 Log 圖示位於底部。
- iOS 26 Liquid Glass 與自訂 AVFoundation 相機 API 語法。
- V0.0.5 完整保存在 `history/V0.0.5/`。

## 仍需 iOS 26 實機驗證

- 商品相機實際拍照、相簿寫入與前後切換流程。
- 支援超廣角鏡頭機型的近拍小花模式與最近對焦距離。
- 首次要求相機權限、拒絕權限及從設定重新開啟權限。
- 大量舊照片資料的首次背景移轉時間。

目前連接的 Atex-iPhone12mini 為 iOS 15.5，低於本專案 iOS 26.0 最低版本，無法執行上述實機測試。
