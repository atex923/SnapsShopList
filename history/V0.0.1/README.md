# SnapshotBuyCheck V0.0.1

中文名稱：採買記事工

以 iPhone 16 直向畫面為主要設計目標的 SwiftUI 食品採買筆記 App。

## V0.0.1 功能

- 使用相機讀取 EAN-8、EAN-13、UPC-E、Code 39、Code 93、Code 128 與 QR Code。
- 掃描後顯示條碼內容。
- 商品歷史清單及商品詳細歷史頁。
- 商品照片拍攝、手機相簿保存、最多三張、切換瀏覽與刪除。
- SwiftData 本機資料庫及 CloudKit 私有資料庫同步架構。

## 下一版本

V0.0.2 將在掃描條碼後查詢商品資料庫；找不到商品時，顯示新增商品資訊頁面。

## iCloud 設定

專案預設 CloudKit Container 為 `iCloud.com.atex1.SnapshotBuyCheck`。第一次使用時，請在 Xcode 的 Signing & Capabilities 確認：

1. Team 已選擇正確的 Apple Developer 團隊。
2. iCloud 已啟用 CloudKit，並勾選上述 Container。
3. Background Modes 已啟用 Remote notifications。

CloudKit 功能需要 Apple Developer 帳號具備建立 iCloud Container 的權限。

目前專案的 Debug 設定使用本機 SwiftData，讓 Personal Team 可以安裝到實機；Release 設定保留 CloudKit entitlement。升級或改用支援 iCloud 的 Apple Developer 團隊後，以 Release 建置即可啟用同步。
