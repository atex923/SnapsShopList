# SnapsShopList V0.1.3 驗證紀錄

驗證日期：2026-09-07

## 裝置與尺寸

- iPhone 17 Pro，iOS 26.5 Simulator，1206 × 2622 px（402 × 874 pt）。
- SnapshotBuyCheck iPhone 16，iOS 26.5 Simulator，1179 × 2556 px（393 × 852 pt）。

## UI／UX 驗證

- iPhone 17 Pro 套用寬版首頁規格：18 pt 水平留白、14 pt 卡片間距、116 pt 最小操作卡高度及 46 pt 主圖示。
- iPhone 16 保留緊密規格：16 pt 水平留白、12 pt 卡片間距、108 pt 最小操作卡高度及 42 pt 主圖示。
- 兩種尺寸首頁都能在單頁完整顯示，沒有加入捲動。
- 設定頁與歷次商品紀錄在 iPhone 17 Pro 安全區內正常顯示。
- 以長商品名稱測試待買清單；空間不足時條碼顯示「...」，完整條碼仍保留於可點擊浮動內容。
- 首頁內容最大閱讀寬度為 520 pt，避免未來更寬手機讓操作卡過度拉伸。

## 程式驗證

- Debug iPhone 17 Pro 模擬器建置成功。
- Debug 靜態分析成功。
- Release 模擬器建置成功。
- `PurchaseLogicSmoke` 通過。
- `BackupSupportSmoke` 通過。
- 備份、重複合併、清除、覆蓋還原，以及孤立採買紀錄／照片清理均納入資料層測試。
- 模擬器測試資料清除後，商品、採買紀錄、照片、店家及待買項目皆為 0。

## 版本邊界

- V0.1.2 已完整保存在 `history/V0.1.2/`。
- V0.1.3 僅安裝於 iPhone 16／iPhone 17 Pro 模擬器，未同步至實體手機。
- 實體手機仍維持 V0.1.1 Build 11。
