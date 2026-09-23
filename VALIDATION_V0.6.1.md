# SnapsShopList V0.6.1 驗證報告

驗證日期：2026-09-09

## 本版修正

- 首頁兩個主按鈕的圖案與文字向下微調 6 pt。
- 食材庫及海外購物數量庫搜尋欄使用固定高度，避免版面拉伸。
- 海外購物數量庫只讀取非 TWD 紀錄。
- 非台幣紀錄支援編輯、單筆確認刪除及全部確認清除。
- 清除海外資料不刪除商品、照片、食材庫與台幣採買紀錄。

## 自動化驗證

- PurchaseLogic smoke tests：通過；確認 TWD 不屬於海外紀錄，JPY 與 USD 屬於海外紀錄。
- BackupSupport smoke tests：通過；確認清除全部非台幣紀錄後 TWD 紀錄仍保留。
- ManualProduct smoke tests：通過。
- Overseas OCR smoke tests：通過。
- iOS Simulator Debug build：通過。
- iOS Simulator Release build：通過。
- Xcode Analyze：通過。

## UI 驗證

- iPhone 16 模擬器首頁：通過；兩個主按鈕內容下移後留白平衡，首頁維持單頁。
- iPhone 16 模擬器海外購物數量庫：通過；只顯示 JPY／USD 測試商品，清除全部入口及搜尋欄完整顯示。
- iPhone 16 模擬器食材庫：通過；底部搜尋欄維持固定膠囊比例。
- 畫面證據：`V0.6.1_Overseas_Home_iPhone16_Simulator.png`、`V0.6.1_Overseas_Library_iPhone16_Simulator.png`、`V0.6.1_Pantry_iPhone16_Simulator.png`。
- 截圖完成後已清除模擬器範例商品並恢復國內模式。

## 實機狀態

- 2026-09-10 已以相同 Bundle ID `com.atex1.SnapshotBuyCheck` 覆蓋安裝至 `Atex-iPhone16`，未執行解除安裝或清除 App 資料。
- 實機已安裝版本讀回為 `0.6.1`（Build `61`）。
- 自動啟動驗證未完成：執行時手機處於鎖定狀態，iOS 以 `Locked` 拒絕遠端啟動；請解鎖後直接點選「購物記本」確認首頁與既有資料。
- `devicectl install app` 回傳的 installation database UUID 有更新；這是安裝服務紀錄，不能用來證明 SwiftData 使用者資料是否保留，因此不把它列為資料完整性證據。
