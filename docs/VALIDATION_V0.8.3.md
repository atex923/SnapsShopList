# SnapsShopList V0.8.3 驗證紀錄

驗證日期：2026-09-15

## 驗證範圍

- 食材庫依「目前在庫、曾加入但已用畢、從未加入」分組排序。
- 首頁掃描商品從未加入食材庫時不顯示狀態小標記。
- Xcode 專案、Asset Catalog、iPhone 17 Pro／iOS 26.5 模擬器建置與 Analyze。
- 購買邏輯及 schema 3 備份相容測試。

## 證據界線

- 本版未修改資料模型或備份格式。
- 已覆蓋安裝到 Atex-iPhone16，未刪除 App 或既有資料。
- 自動啟動時手機處於鎖定狀態，系統以 `Locked` 拒絕啟動；因此尚未把實機畫面操作列為通過。

## 已通過

- iPhone 17 Pro／iOS 26.5 模擬器 Debug Build 與 Xcode Analyze。
- `PurchaseLogicSmoke`：驗證在庫排在已用畢之前、已用畢排在從未加入之前。
- `BackupSupportSmoke`：確認 schema 3 備份相容性不變。
- `plutil -lint` 專案設定及全部 Asset Catalog JSON 格式檢查。
- 模擬器覆蓋安裝、啟動及首頁畫面檢查；截圖為 `V0.8.3_home_iPhone17Pro.png`。
- Atex-iPhone16 實機 Debug 簽章建置及安裝通過；裝置回報「購物記本」Version `0.8.3`、Bundle Version `83`。
