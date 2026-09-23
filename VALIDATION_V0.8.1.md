# SnapsShopList V0.8.1 驗證紀錄

驗證日期：2026-09-15

## 已完成

- Xcode 專案設定檔與 Asset Catalog JSON 格式檢查通過。
- iPhone 17 Pro／iOS 26.5 模擬器 Debug 建置成功。
- iPhone 17 Pro／iOS 26.5 目的地 Analyze 成功。
- `PurchaseLogicSmoke` 通過，包含一組包裝有效數量、單價換算及錯誤輸入驗證。
- `BackupSupportSmoke` 通過，包含 V0.8.1 新欄位匯出、匯入及舊 schema 缺少欄位的相容測試。
- App 可覆蓋安裝至既有 iPhone 17 Pro 模擬器資料並正常啟動，未發生資料模型升級閃退。
- 使用 Apple Development 簽署對 Atex-iPhone16 實機建置成功。
- V0.8.1 已使用相同 Bundle ID `com.atex1.SnapshotBuyCheck` 覆蓋安裝至 Atex-iPhone16；未先刪除 App。
- 實機 App 清單回讀確認「購物記本」版本為 `0.8.1`、Bundle Version 為 `81`。

## 證據界線

- 模擬器可驗證建置、靜態分析、資料模型啟動及畫面排版。
- 實機安裝與版本回讀完成；兩次遠端啟動時手機均處於鎖定狀態，iOS 以 `Locked` 拒絕啟動，因此尚待使用者解鎖後直接點選 App，或後續補做遠端啟動確認。
- 實體相機近拍、照片寫入系統相簿、實體鍵盤手感、CloudKit／Google Drive 真實帳號同步與耗電量，仍需後續實機測試才能確認。
