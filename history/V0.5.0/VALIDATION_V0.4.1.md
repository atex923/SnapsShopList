# SnapsShopList V0.4.1 驗證報告

驗證日期：2026-09-09

## 自動測試

- PurchaseLogic smoke tests：通過，包含國內模式強制 TWD、海外模式採用所選貨幣及未知貨幣回復 TWD。
- ManualProduct smoke tests：通過。
- BackupSupport smoke tests：通過，既有外幣備份相容性保持正常。
- Overseas OCR smoke tests：通過；以程式產生的 `MILK 1000ml` 圖片實際執行 Apple Vision 辨識。
- iOS Simulator Debug build：通過。
- iOS Simulator Release build：通過。
- Xcode Analyze：通過。

## UI 驗證

- iPhone 16 國內模式首頁：通過；維持單頁配置，沒有顯示 OCR、外文查詢或貨幣控制。
- iPhone 17 Pro 海外模式設定頁：通過；顯示總開關、日圓選擇與效能說明。
- iPhone 17 Pro 海外模式新增商品頁：通過；顯示商品名稱、店家、品牌及廠商文字擷取入口。
- iPhone 17 Pro 外文名稱查詢頁：通過；先顯示將送出的查詢文字，再提供網頁搜尋及 AI／搜尋 App 分享。

## 隱私與效能檢查

- Vision request 僅在使用者拍攝文字後建立，App 啟動與國內模式不會建立 OCR request 或相機 session。
- OCR 照片只供當次本機辨識，不寫入商品照片或系統相簿。
- 外部查詢只包含條碼、目前商品名稱及查詢提示，不包含照片、GPS、價格或採買歷史。
- 網路查詢由使用者在確認頁主動觸發，結果不會自動寫入資料庫。

## 尚未執行

- 本版依目前指示沒有同步實體 iPhone。
- 真實海外包裝的日文／韓文 OCR、弱光招牌、彎曲瓶身及網頁結果品質仍需後續實機情境測試。
- Debug 實機仍使用 Personal Team 本機 SwiftData；CloudKit 跨裝置同步不在本次驗證範圍。
