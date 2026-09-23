# SnapsShopList V0.9.0 驗證紀錄

日期：2026-09-15

## 已完成

- Xcode Debug Simulator Build 通過，目標為 iOS 26.5 iPhone 17 Pro。
- Xcode Analyze 通過；只有未使用 AppIntents framework 時的 metadata skipped 提示，無程式分析錯誤。
- `PurchaseLogicSmoke` 通過：包含數量空白、比較紀錄、容量參考單價、貨幣與食材庫排序。
- `BackupSupportSmoke` 通過：schema 4 完整匯出／匯入、同步檔保留3份歷史，且 schema 1～3 缺少新欄位仍可解碼及驗證。
- V0.9.0 以相同 Bundle ID 覆蓋安裝至既有 V0.8.3 iPhone 17 Pro 模擬器資料後可正常啟動，未觀察到 SwiftData migration 閃退。
- iPhone 16 與 iPhone 17 Pro 模擬器均完成首頁快速模式及快速紀錄畫面檢查；首頁保持單頁不捲動，快速相機在主卡下方保留可用空間。
- 快速紀錄畫面確認價格無內容時「暫存」及「正式儲存」反白停用，照片區顯示10張暫存／5張正式上限。

## 畫面

- `V0.9.0_quick_home_iPhone16.png`
- `V0.9.0_quick_entry_iPhone16.png`
- `V0.9.0_quick_home_iPhone17Pro.png`
- `V0.9.0_quick_entry_iPhone17Pro.png`

## 尚待實體手機

- 本輪未同步或安裝實體 iPhone。
- 相機連拍10張、寫入系統相簿、照片 GPS metadata、定位權限、海外 OCR 相機／相簿選取仍需下次在實體手機逐項操作。
- Simulator 驗證不能取代實體相機、相簿、GPS、CloudKit 或耗電量證據。
