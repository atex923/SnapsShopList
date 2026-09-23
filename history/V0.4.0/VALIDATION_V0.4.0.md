# SnapsShopList V0.4.0 驗證報告

驗證日期：2026-09-09

## 結果

- PurchaseLogic smoke tests：通過
- ManualProduct smoke tests：通過
- BackupSupport smoke tests：通過
- iOS Simulator Debug build：通過
- iOS Simulator Release build：通過
- Xcode Analyze：通過
- iPhone 16 模擬器首頁 UI：通過，單頁顯示且底部只保留版本資訊
- iPhone 17 Pro 模擬器首頁 UI：通過，單頁顯示且響應式間距正常
- iPhone 17 Pro 新增無條碼商品 UI：通過，照片置頂、固定欄位名稱、付款與數量優先
- iPhone 16 設定頁 UI：通過，備份、匯入及資料統計版面正常
- Atex-iPhone16 Debug 實機簽署建置：通過
- Atex-iPhone16 覆蓋安裝：通過
- Atex-iPhone16 App 啟動：通過

## 本版專項檢查

- 一維條碼的 metadata 類型及回傳選擇順序優先於 QR Code。
- 相似商品搜尋可排除目前商品，依名稱正規化、包含關係及 bigram 相似度排列。
- 歷次採買紀錄排序名稱為「時間／價格／店家」。
- 1500 ml 的換算測試會顯示「每 1 L」；1000 ml 維持「每 100 ml」。
- 新增表單不顯示海外貨幣切換，新紀錄固定保存為 TWD；既有外幣資料模型與備份相容性保留。
- 商品照片具正方形、4:3、3:4 中央裁切入口。

## 實機限制

本次使用 Personal Team 的 Debug 設定安裝，因此採本機 SwiftData，沒有 CloudKit entitlement。Release 模擬器建置已通過，但 iCloud 跨裝置同步仍需具 CloudKit 權限的 Apple Developer Team 才能在實機驗證。

實體相機的一維條碼辨識、近拍對焦、拍照寫入相簿與裁切操作仍建議由使用者在手機上以真實商品完成操作測試；電腦端已確認 App 可安裝及啟動，但無法代替手持相機情境。
