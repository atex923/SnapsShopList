# SnapsShopList V0.10.0 驗證紀錄

日期：2026-09-16

## 已完成

- Xcode Debug Simulator Build 通過，目標為 iOS 26.5 iPhone 17 Pro，版本 `0.10.0`、Build `100`。
- Xcode Analyze 通過。
- `PurchaseLogicSmoke` 通過，確認既有價格、包裝、貨幣及食材庫排序邏輯未回歸。
- `BackupSupportSmoke` 通過，確認 schema 5 匯出／匯入與同步檔歷史流程。
- `ManualProductSmoke` 通過，確認無條碼商品及備份還原流程。
- V0.10.0 已覆蓋安裝並正常啟動於 iPhone 16 與 iPhone 17 Pro 模擬器，保留既有模擬器資料。
- 首頁站立角色在國內淺綠與海外淺藍背景的透明邊緣、縮放、點擊穿透及版本資訊間距完成畫面檢查。
- 首頁截圖：`V0.10.0_home_iPhone16.png`、`V0.10.0_home_iPhone17Pro.png`。

## 驗證邊界

- 模擬器沒有實體相機，倒地角色狀態、實際條碼掃描、相簿、GPS 與鍵盤種類仍需互動或實機複驗。
- 已於 2026-09-16 完成 Atex-iPhone16 實體裝置簽署建置及覆蓋安裝；Bundle ID 為 `com.atex1.SnapshotBuyCheck`。
- 自動啟動因手機維持鎖定而被 iOS 拒絕，尚未宣告實體相機、相簿、GPS、鍵盤或資料遷移的操作結果。
- 本輪未執行 iCloud／Google Drive 真實跨裝置同步。
