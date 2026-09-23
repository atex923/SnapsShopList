# SnapsShopList V0.5.1 驗證報告

驗證日期：2026-09-09

## 本版修正

- 新增食材庫紀錄後，商品關聯與勾選狀態會立即更新。
- 既有在庫資料需先按「編輯」才能修改；「已用畢」只在編輯模式顯示並需二次確認。
- 首頁掃描商品的食材庫狀態以綠色「在庫」文字顯示。
- 商品簡單查閱頁在歷次價格下方顯示最近購入時間與保存期限。

## 自動化驗證

- PurchaseLogic smoke tests：通過。
- BackupSupport smoke tests：通過。
- ManualProduct smoke tests：通過。
- Overseas OCR smoke tests：通過。
- iOS Simulator Debug build：通過。
- iOS Simulator Release build：通過。
- Xcode Analyze：通過。

## 實機同步

- Atex-iPhone16 實機簽章建置與覆蓋安裝：通過。
- 裝置回報 App 版本 0.5.1、Build 51，Bundle ID 為 `com.atex1.SnapshotBuyCheck`。
- 裝置服務啟動 App：通過。
- 沿用原 Bundle ID，安裝不會主動清除既有 App 資料；本次未執行刪除或重置。
