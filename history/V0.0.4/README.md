# SnapshotBuyCheck V0.0.4

中文名稱：採買記事工

以 iPhone 16 直向畫面為主要設計目標的 SwiftUI 食品採買筆記 App。

## V0.0.4 新增功能

- 記住曾輸入的店家、分店、縣市及行政區，新增紀錄時可從最近使用清單快速帶入。
- 同一組店家資訊會更新使用次數與最近使用時間，不會每次重複新增。
- 採買紀錄新增分店、縣市、行政區欄位，歷史清單、搜尋及詳細頁均可顯示。
- 建立紀錄時可取得 GPS 經緯度及定位誤差；拒絕定位或定位失敗時仍可正常存檔。
- 首頁新增「程式錯誤紀錄」，保留最近 200 筆資料庫、照片、相機、GPS 與相簿錯誤，可查看及清除。
- 新增定位用途說明，僅在建立採買紀錄頁請求「使用 App 期間」定位權限。

## 既有功能

- 使用相機讀取 EAN-8、EAN-13、UPC-E、Code 39、Code 93、Code 128 與 QR Code。
- 掃描後顯示條碼內容，並自動搜尋 SwiftData 商品資料庫。
- 找不到條碼時開啟「建立商品資訊」，可輸入名稱、時間、店家、容（重）量、單位、價格、特價及買一送一。
- 找到既有商品時開啟「新增採買紀錄」，保留同一商品的歷次價格與店家資料。
- 商品歷史清單及商品詳細歷史頁。
- 商品照片拍攝、手機相簿保存、最多三張、切換瀏覽與刪除。
- 商品照片以 SwiftData 外部儲存資料同步，並保留本機 JPEG 相容路徑。
- 相機工作移至專用背景佇列，掃描完成後依畫面關閉事件立即切頁，不再使用固定等待時間。
- 條碼無法辨識時可手動輸入。
- 歷史頁可搜尋商品名稱、條碼或店家。
- 再次購買既有商品時，自動帶入上次店家、容量、單位與價格。
- 價格支援小數點與逗號格式，並檢查負數及零容量。
- SwiftData 本機資料庫及 CloudKit 私有資料庫同步架構。

## 版本保存

完整 V0.0.1、V0.0.2、V0.0.3 專案分別保存在對應的 `history/` 版本目錄。

## 檢討與後續構想

- `REVIEW_V0.0.3.md`：本次程式檢討及修正內容。
- `COMPETITOR_RESEARCH.md`：中英文同類 App 功能研究。
- `ROADMAP_V0.0.5.md`：下一版 V0.0.5 建議及優先順序。

## iCloud 設定

專案預設 CloudKit Container 為 `iCloud.com.atex1.SnapshotBuyCheck`。第一次使用時，請在 Xcode 的 Signing & Capabilities 確認：

1. Team 已選擇正確的 Apple Developer 團隊。
2. iCloud 已啟用 CloudKit，並勾選上述 Container。
3. Background Modes 已啟用 Remote notifications。

CloudKit 功能需要 Apple Developer 帳號具備建立 iCloud Container 的權限。

目前專案的 Debug 設定使用本機 SwiftData，讓 Personal Team 可以安裝到實機；Release 設定保留 CloudKit entitlement。升級或改用支援 iCloud 的 Apple Developer 團隊後，以 Release 建置即可啟用同步。
