# SnapsShopList V0.1.2 模擬器測試報告

測試日期：2026-09-07
測試裝置：SnapshotBuyCheck iPhone 16 模擬器
系統：iOS 26.5 Simulator
App：購物記本 V0.1.2（Build 12）

## 已通過

- iPhone 16 Debug 乾淨建置成功。
- iPhone 16 Release 模擬器建置成功；Debug 專用測試入口未影響 Release 編譯。
- Xcode Analyze 靜態分析成功，未回報程式分析錯誤。
- App 安裝及啟動成功；連續終止／啟動 5 次均取得新程序，未發生啟動閃退。
- 首頁在 1179 × 2556 畫面完整顯示，不需捲動；掃描按鈕維持淺藍底，圖示與文字為黑色。
- Info.plist 正確包含相機、加入相簿與使用中定位權限說明。
- SwiftData 本機資料庫成功建立，SQLite `PRAGMA quick_check` 回傳 `ok`。
- 價格、買一送一、每 100 g／ml、店家識別、欄位驗證、暫存／正式儲存判斷測試通過。
- 最新價格、最低價格與最高價格的紀錄選擇測試通過。
- 備份 JSON 編解碼、照片資料保存、重複匯入去重、全部清除及完整還原測試通過。
- 以 2 項商品、3 筆價格及 2 個待買項目測試 SwiftData 與 SwiftUI 資料繫結，設定頁統計數字一致。
- 相機權限提示可正常出現；模擬器沒有相機輸入時會寫入錯誤紀錄，App 沒有閃退。
- 測試結束後已清除模擬器商品、紀錄、照片、店家及待買項目，五類資料筆數皆為 0。

## 發現問題

### 中優先：首頁待買清單長文字條碼顯示不符合需求

商品名稱很長時，名稱會正確顯示省略號，但條碼欄位會被壓縮到只剩一個數字。原需求是條碼放不下時顯示「…」，點擊後再用浮動視窗顯示完整條碼。

本輪依「先檢查跟測試」處理，尚未修改正式 UI。

## 模擬器限制／尚未完成

- 模擬器無實體相機，無法驗證近拍小花模式、實際拍照、照片寫入系統相簿及真實條碼辨識。
- 尚未操作手動輸入條碼、商品新增／編輯表單及刪除確認按鈕的完整觸控流程。
- 尚未操作系統檔案選擇器，因此 iCloud Drive／Google Drive 實際輸出與重新匯入仍待測。
- GPS 定位、縣市／行政區反查仍需模擬位置或實體手機測試。
- macOS 未提供此測試程序直接控制 Simulator 視窗的輔助使用權限；設定、掃描與歷史頁使用 `SNAPS_DEBUG_SCREEN` 的 Debug 專用入口檢查。此入口不會編入 Release 行為，也未同步至手機。

## 測試檔與畫面

- `tests/PurchaseLogicSmoke.swift`
- `tests/BackupSupportSmoke.swift`
- `tests/SimulatorFixture.swift`
- `V0.1.2_Home_iPhone16_Simulator.png`
- `V0.1.2_Home_WithTestData_iPhone16_Simulator.png`
- `V0.1.2_Settings_iPhone16_Simulator.png`
- `V0.1.2_Scanner_iPhone16_Simulator.png`
- `V0.1.2_Scanner_NoCamera_iPhone16_Simulator.png`
- `V0.1.2_Home_CleanAfterTests_iPhone16_Simulator.png`

## 版本邊界

本輪只更新本機 V0.1.2 的測試程式、測試紀錄及截圖，沒有同步至實體 iPhone；實體手機仍維持 V0.1.1 Build 11。
