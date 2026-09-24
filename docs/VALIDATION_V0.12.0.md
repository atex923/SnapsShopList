# SnapsShopList V0.12.0 驗證紀錄

日期：2026-09-25

## 已通過

- Xcode 實機 Debug 建置及開發簽署成功。
- 版本資訊為 `0.12.0`、Build `120`，Bundle ID 維持 `com.atex1.SnapshotBuyCheck`。
- 已覆蓋安裝至已配對的 `Atex-iPhone16`，未先解除安裝。
- 實機啟動命令成功，系統回報 App 已以既有 Bundle ID 啟動。
- 首頁版號格式為 `V0.12.0(20260925)`，版本號讀取 Xcode `MARKETING_VERSION`。
- 設定頁顯示 `atexapp.lin@gmail.com` 使用回饋郵件連結。
- Swift 編譯已涵蓋查詢卡分離點擊、淺紅色新購買按鈕與待買卡空／有資料圖示。

## 環境限制

- 沙箱內 CoreSimulatorService 無法使用，因此本次未完成模擬器啟動與畫面截圖。
- 相機、條碼、郵件 App 跳轉及既有資料內容仍需由使用者在手機畫面操作確認。
