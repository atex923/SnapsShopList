# SnapsShopList V0.10.2 驗證紀錄

日期：2026-09-22

## 已完成

- Xcode Debug Simulator Build 通過；iOS 26.5 SDK、版本 `0.10.2`、Build `102`、顯示名稱「購物記本」。
- Xcode Analyze 通過。
- `PurchaseLogicSmoke` 通過，價格、包裝、貨幣、暫存判定與食材庫排序邏輯未回歸。
- `BackupSupportSmoke` 通過，schema 5 匯出／匯入及同步歷史相容流程正常。
- `ManualProductSmoke` 通過，無條碼商品建立、價格統計、完整備份與還原流程正常。
- iPhone 17 Pro（iOS 26.5）模擬器完成覆蓋安裝及採買記事啟動。
- SnapshotBuyCheck iPhone 16（iOS 26.5）模擬器完成覆蓋安裝及採買記事啟動。
- 兩種尺寸的空白採買記事、搜尋欄、安全區域及導覽標題沒有可見裁切或水平捲動。
- Assets JSON 可解析，AppIcon 為有效 `1024 × 1024` PNG。
- iPhoneOS Debug 實機版簽署建置通過；Bundle ID `com.atex1.SnapshotBuyCheck`、版本 `0.10.2`、Build `102`。
- 已於 2026-09-22 以 USB 覆蓋安裝至 Atex-iPhone16（iPhone 16、iOS 27.0），未執行解除安裝或資料清除。

## 本版程式檢查

- 採買記事不再只保留 `.complete`，完整表單的暫存／比較紀錄可再次進入商品資料編輯。
- 快速草稿會由本機 `QuickDraftStore` 讀入「快速暫存」區；點擊後依 `productID` 或條碼接回既有商品，無相符商品時開啟新商品完整表單。
- 手動商品識別碼維持 `MANUAL-UUID`，畫面顯示「無條碼商品」，不需建立假的消費條碼。
- 商品照片入口直接觸發相機；相機頁右上角提供 `PhotosPicker`，相簿來源不會重複存回系統相簿。
- 商品相機在一般鏡頭及近拍鏡頭切換後都將 `videoZoomFactor` 設為可用範圍內的 `1.0`。
- 音量鍵快門使用 `AVCaptureEventInteraction`；僅在相機頁可見時啟用，並避免相機尚未啟動或連續事件重複送出拍照要求。

## 畫面證據

- `V0.10.2_history_iPhone17Pro.png`
- `V0.10.2_history_iPhone16.png`
- 先前本版完整表單：`V0.10.2_new_product_iPhone17Pro.png`、`V0.10.2_new_product_iPhone16.png`

## 尚待實機驗證

- 模擬器沒有商品相機輸入，無法證明 `1.0×` 實際視角、音量加／減鍵快門、近拍鏡頭切換、拍照結果或相簿選取權限。
- 實機安裝已完成；電腦端兩次啟動要求都因 iPhone 鎖定而被系統拒絕，因此本次尚未取得 App 實機啟動成功證據。
- 解鎖後仍需實際確認拍照、音量鍵、相簿寫入及暫存資料冷啟動回復。
- 未執行 iCloud／Google Drive 真實跨裝置同步，本版未變更 SwiftData model 或備份 schema。
