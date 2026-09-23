# SnapsShopList V0.7.0 驗證報告

驗證日期：2026-09-10

## 完成項目

- 手機設定新增 iCloud／Google Drive 單一同步來源、立即同步及第一份同步檔建立入口。
- 自動同步預設關閉；桌機版完成前會阻止開啟，避免尚無完整衝突欄位時誤覆蓋。
- 每次同步前先建立並回讀驗證完整備份；本機只保留最近3份。
- `.snapssync` 內含目前資料與最近3份雲端歷史。
- 支援雲端優先或手機優先合併、回寫及回讀驗證。
- 最近3次本機備份可確認後還原，且還原前再次備份目前資料。
- 設定、本次採買、GPS及價格換算說明改用圓框 `i`。
- macOS 與 Python／Windows 只建立相容規劃文件，沒有建立桌機程式。

## 自動化驗證

- iOS Simulator Debug build：通過。
- iOS Simulator Release build：通過。
- Xcode Analyze：通過。
- BackupSupport／Sync envelope smoke tests：通過。
- 驗證同步 envelope 連續更新後只保留3份歷史：通過。
- 驗證 synchronize 模式能更新既有商品名稱及採買店家：通過。
- Debug App 資訊讀回：`購物記本`、版本 `0.7.0`、Build `70`、Bundle ID `com.atex1.SnapshotBuyCheck`。

## 尚未驗證

- 本輪沒有安裝或同步實體 iPhone。
- 尚未以真實 iCloud Drive／Google Drive 帳號完成同步檔往返。
- macOS 與 Python／Windows 桌機版尚未實作，因此沒有跨平台實際編輯結果。
- 依簡化流程，本版沒有製作轉移 ZIP。
