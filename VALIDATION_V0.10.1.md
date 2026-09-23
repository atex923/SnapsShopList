# SnapsShopList V0.10.1 驗證紀錄

日期：2026-09-16

## 已完成

- Xcode Debug Simulator Build 通過，目標為 iOS 26.5 iPhone 17 Pro，版本 `0.10.1`、Build `101`。
- Xcode Analyze 通過。
- `PurchaseLogicSmoke` 通過，價格、包裝、貨幣與食材庫排序邏輯未回歸。
- `BackupSupportSmoke` 通過，schema 5 匯出／匯入與同步檔歷史流程正常。
- `ManualProductSmoke` 通過，無條碼商品與備份還原流程正常。
- iPhone 17 Pro 模擬器已覆蓋安裝並啟動；完整商品表單的相機條碼按鈕、相簿辨識按鈕及欄位排版完成畫面檢查。
- 實機 Debug 建置及 Apple Development 簽署通過，輸出可安裝的 `SnapsShopList.app`。
- 已在 Atex-iPhone16（iPhone 16）完成 V0.10.1 覆蓋安裝，保留既有 App 資料。
- 已透過 CoreDevice 成功啟動 `com.atex1.SnapshotBuyCheck`。
- 完整表單截圖：`V0.10.1_full_form_iPhone17Pro.png`。

## 驗證邊界

- 實機覆蓋安裝與程式啟動已通過；即時條碼掃描、相簿內容辨識、GPS、相機權限及實機鍵盤的互動效果仍需人工操作複驗。
- 未執行 iCloud／Google Drive 真實跨裝置同步。
