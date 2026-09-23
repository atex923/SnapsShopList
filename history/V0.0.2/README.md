# SnapshotBuyCheck V0.0.2

中文名稱：採買記事工

以 iPhone 16 直向畫面為主要設計目標的 SwiftUI 食品採買筆記 App。

## V0.0.2 功能

- 使用相機讀取 EAN-8、EAN-13、UPC-E、Code 39、Code 93、Code 128 與 QR Code。
- 掃描後顯示條碼內容，並自動搜尋 SwiftData 商品資料庫。
- 找不到條碼時開啟「建立商品資訊」，可輸入名稱、時間、店家、容（重）量、單位、價格、特價及買一送一。
- 找到既有商品時開啟「新增採買紀錄」，保留同一商品的歷次價格與店家資料。
- 商品歷史清單及商品詳細歷史頁。
- 商品照片拍攝、手機相簿保存、最多三張、切換瀏覽與刪除。
- SwiftData 本機資料庫及 CloudKit 私有資料庫同步架構。

## 版本保存

完整 V0.0.1 專案保存在 `history/V0.0.1/`。

## iCloud 設定

專案預設 CloudKit Container 為 `iCloud.com.atex1.SnapshotBuyCheck`。第一次使用時，請在 Xcode 的 Signing & Capabilities 確認：

1. Team 已選擇正確的 Apple Developer 團隊。
2. iCloud 已啟用 CloudKit，並勾選上述 Container。
3. Background Modes 已啟用 Remote notifications。

CloudKit 功能需要 Apple Developer 帳號具備建立 iCloud Container 的權限。

目前專案的 Debug 設定使用本機 SwiftData，讓 Personal Team 可以安裝到實機；Release 設定保留 CloudKit entitlement。升級或改用支援 iCloud 的 Apple Developer 團隊後，以 Release 建置即可啟用同步。
