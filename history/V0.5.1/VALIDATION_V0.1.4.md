# SnapsShopList V0.1.4 驗證紀錄

驗證日期：2026-09-07

## 功能範圍

- 既有商品新增採買紀錄時，清空店家、分店及價格。
- 自動沿用最新紀錄的數量、單位、容量、特價、買一送一、縣市及行政區，所有欄位仍可修改。
- 選擇記憶店家時，同時帶入分店、縣市及行政區。
- 新增頁顯示最早照片優先排列的既有照片，支援更換、確認刪除與補拍。
- 新增頁欄位依價格、店家、分店、特價、買一送一及其餘資料排列，操作按鈕顯示「新增」。
- AppIcon 使用使用者提供的圖片，輸出為 1024 × 1024 RGB、無 Alpha 的 PNG。

## 已完成驗證

- iPhone 17 Pro Simulator Debug 建置成功，靜態分析成功。
- iPhone 17 Pro Simulator Release 建置成功。
- V0.1.4 已安裝並啟動於 iPhone 17 Pro 與 iPhone 16 Simulator；兩種首頁版面均正常。
- `PurchaseLogicSmoke` 通過。
- `BackupSupportSmoke` 通過，包含合併、覆蓋還原、完整刪除及孤立資料清理。
- Xcode 資產編譯成功；編譯後 AppIcon 已檢查為新版貓咪圖案。
- AppIcon 原始資產為 1024 × 1024 RGB PNG，無 Alpha。

## 尚待實機驗證

- 相機拍攝、照片更換及照片加入系統相簿。
- iCloud Drive／Google Drive 系統檔案選擇器實際匯出與匯入。

## 版本邊界

- V0.1.3 已完整保存在 `history/V0.1.3/`。
- V0.1.4 不同步至實體手機，實機相機及雲端檔案選擇器留待後續測試。
