# SnapsShopList V0.2.0 驗證紀錄

驗證日期：2026-09-07

## 功能範圍

- 掃描畫面提供無條碼商品入口，購買紀錄與待買清單兩種流程皆支援。
- 無條碼商品使用內部 UUID，所有使用者介面隱藏內部識別碼。
- 名稱輸入 2 個字後顯示相似商品，可選擇既有商品或繼續建立新品。
- 無條碼商品完整支援照片、GPS、店家、分店、歷史價格、編輯、刪除、備份及還原。
- 秤重與容量商品支援 g、kg、ml、cc、L 等單位的每 100 g／ml 換算。

## 已完成驗證

- iPhone 17 Pro Simulator（iOS 26.5）Debug 建置成功。
- Xcode 靜態分析成功（`ANALYZE SUCCEEDED`）。
- iPhone 17 Pro Simulator（iOS 26.5）Release 建置成功。
- V0.2.0 已安裝並成功啟動於 iPhone 17 Pro 與 iPhone 16 Simulator。
- 兩種尺寸的首頁版面皆完整顯示、不需捲動，標題、按鈕與頁尾未發生截斷或重疊。
- `PurchaseLogicSmoke`、`BackupSupportSmoke` 與 `ManualProductSmoke` 全數通過。
- `ManualProductSmoke` 已驗證無條碼識別碼、介面顯示、每 100 g 單價，以及備份刪除後還原。
- 無相機狀態下的「建立無條碼商品」入口及購買／待買路由已通過編譯與程式邏輯檢查。

## 尚待實機驗證

- 無條碼入口至建立表單的完整點擊操作。
- 真實相機、照片寫入系統相簿、GPS 與 iCloud／檔案選擇器。

## 2026-09-07 重新檢驗與實機同步

- `PurchaseLogicSmoke`、`BackupSupportSmoke`、`ManualProductSmoke` 重新執行並全數通過。
- iPhone 17 Pro Simulator（iOS 26.5）Debug 與 Release 重新建置成功。
- Xcode 靜態分析重新執行成功（`ANALYZE SUCCEEDED`）。
- 偵測到已配對裝置 `Atex-iPhone16`，機型為 iPhone 16。
- Debug 實機簽署建置成功，並以相同 Bundle ID 更新安裝；未執行解除安裝或清除 App 資料。
- 手機端安裝資訊確認為「購物記本」V0.2.0（Build 20），Bundle ID 為 `com.atex1.SnapshotBuyCheck`。
- 手機處於鎖定狀態，macOS 因此拒絕遠端啟動；解鎖後仍需由使用者確認首頁、相機、相簿與 GPS 實際操作。
- Release 實機簽署受個人開發團隊限制：此帳號的 Provisioning Profile 不支援 iCloud 與 Push Notifications。手機測試版因此採用不含這兩項 entitlement 的 Debug 組態，iCloud 同步不在本次實機測試範圍。

## 版本邊界

- V0.1.4 已完整保存在 `history/V0.1.4/`。
- V0.2.0 已同步至 Atex-iPhone16；實機相機、相簿、GPS 與雲端檔案選擇器操作仍待解鎖後確認。
