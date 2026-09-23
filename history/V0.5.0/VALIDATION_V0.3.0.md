# SnapsShopList V0.3.0 驗證紀錄

驗證日期：2026-09-08

## 版本與資產

- App 顯示名稱：購物記本
- 行銷版本：0.3.0
- Build：30
- App 內版本：V0.3.0 (20260908)
- App 圖示：1024 × 1024、RGB PNG，已換成移除紅色箭頭的手繪貓咪／條碼圖示。

## Xcode 驗證

- iOS Simulator Debug Build：通過（BUILD SUCCEEDED）
- iOS Simulator Release Build：通過（BUILD SUCCEEDED）
- Xcode Analyze：通過（ANALYZE SUCCEEDED）
- 編譯目標：iOS 26、iPhone

## 自動化邏輯測試

- `PurchaseLogicSmoke`：通過
  - TWD／JPY／KRW／USD／EUR 代碼正規化
  - 未知貨幣安全回退為 TWD
  - 日圓與美金符號及小數格式
- `BackupSupportSmoke`：通過
  - schema 2 備份／還原品牌、廠商與貨幣
  - schema 1 舊備份仍可讀取；缺少新欄位時安全回退
- `ManualProductSmoke`：通過
  - 無條碼商品仍能保存與還原
  - 品牌及廠商可往返保存
  - TWD 與 JPY 價格統計分開計算，不混合比較

## 模擬器與 UI

- iPhone 17 Pro：直接覆蓋既有 V0.2.0 安裝後可正常啟動。
- iPhone 16：直接覆蓋既有 V0.2.0 安裝後可正常啟動。
- 首頁：V0.3.0 版號與固定單頁版面正常。
- 設定頁：預設貨幣選項在 iPhone 16 與 iPhone 17 Pro 均正常顯示。
- 新增商品頁：品牌、廠商及貨幣欄位已完成編譯與畫面確認。模擬器仍可能顯示 iOS 定位權限系統提示，此提示不屬於 App 表單版面。

## 2026-09-08 實機同步前回歸

- 等待其他三個 iOS 專案工作結束後才開始，避免同時占用 Xcode、模擬器與手機。
- iPhone 16（iOS 26.5）Debug Build：通過（BUILD SUCCEEDED）。
- iPhone 17 Pro（iOS 26.5）Analyze：通過（ANALYZE SUCCEEDED）。
- 兩台模擬器均重新安裝、啟動並擷取首頁；固定單頁、標題與 V0.3.0 版號顯示正常。
- 已連線 Atex-iPhone16 的 Debug 實機簽章建置通過，V0.3.0 已成功安裝並保留相同 Bundle ID。
- 自動啟動驗證因 iPhone 保持鎖定而被 iOS 拒絕；安裝本身已完成，解鎖後可由使用者直接開啟。

## 相容性與限制

- SwiftData 新欄位均有安全預設值，保留既有資料。
- 備份格式升級為 schema 2，並保留 schema 1 匯入相容性。
- 本次已安裝到 Atex-iPhone16；因使用 Apple 個人開發團隊簽章，實機 Debug 版不含 CloudKit entitlement。
- 實體相機、相簿寫入及真實 CloudKit 跨裝置同步，仍需下一次實機驗證。
- 「海外模式」目前只有 V0.3.1 規劃，本版不載入 OCR、AI 或網頁查詢功能。
