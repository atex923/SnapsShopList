# SnapsShopList V0.6.0 驗證報告

驗證日期：2026-09-09

## 本版功能

- 國內模式首頁顯示食材庫，海外模式改顯示海外購物數量庫。
- 海外購物數量庫以商品分組，顯示每次購買時間、數量、價格與店家。
- 支援商品名稱、條碼與店家搜尋，注音組字完成後才刷新結果。
- 沿用既有 `PurchaseRecord`，沒有新增 SwiftData 欄位或變更備份 schema。

## 自動化驗證

- PurchaseLogic smoke tests：通過。
- BackupSupport smoke tests：通過。
- ManualProduct smoke tests：通過。
- Overseas OCR smoke tests：通過。
- iOS Simulator Debug build：通過。
- iOS Simulator Release build：通過。
- Xcode Analyze：通過。

## UI 驗證

- iPhone 16 模擬器海外模式首頁：通過；食材庫已隱藏，海外購物數量庫卡片完整顯示，首頁不需捲動。
- 畫面證據：`V0.6.0_Overseas_Home_iPhone16_Simulator.png`。
- 截圖後已將測試模擬器恢復為預設國內模式。

## 實機狀態

- 2026-09-09 已成功覆蓋安裝到 Atex-iPhone16；裝置回報版本 0.6.0、Build 60。
- 已成功由裝置服務啟動 `com.atex1.SnapshotBuyCheck`。
- 安裝前後資料庫 UUID 均為 `B211DA81-5C4F-49DD-93A4-A4E423FAD060`，確認沿用原 App 資料容器。
- 本次未執行刪除、重置或清除資料。
