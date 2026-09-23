# SnapsShopList V0.9.1 驗證紀錄

日期：2026-09-15

## 驗證範圍

- 雲端服務未選擇與資料夾未設定時的阻擋提示。
- 雲端資料夾內同步檔自動搜尋、固定檔名優先及缺檔建立路徑。
- schema 4 備份、同步交換格式與舊 schema 匯入相容性。
- Xcode Build、Analyze 與 iPhone 17 Pro 模擬器啟動。

## 已完成

- Xcode Debug Simulator Build 通過，版本為 `0.9.1`、Build `91`。
- Xcode Analyze 通過；只有未使用 AppIntents framework 的 metadata skipped 提示。
- `BackupSupportSmoke` 通過：空資料夾回報沒有同步檔、自訂檔名可被找到、固定檔名 `SnapsShopList.snapssync` 優先使用，schema 1～4 備份相容測試通過。
- V0.9.1 已覆蓋安裝並啟動於 iPhone 17 Pro 模擬器；設定頁確認「設定雲端位置」「已設定位置」「立即同步」顯示正常，且已移除「建立第一份同步檔」。
- 設定頁截圖：`V0.9.1_settings_iPhone17Pro.png`。

## 實體服務邊界

- Simulator 可驗證 UI、檔案搜尋與本機資料夾交換邏輯，但不能證明 iCloud Drive／Google Drive 文件提供者的登入、下載速度或跨裝置同步結果。
- 本輪不安裝實體手機；實際雲端資料夾權限與跨裝置回讀留待下次手機同步時驗證。
