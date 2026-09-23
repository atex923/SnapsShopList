# 購物記本跨平台同步規劃

V0.9.1 手機端會記住使用者指定的雲端資料夾，並優先使用固定檔名 `SnapsShopList.snapssync`；若資料夾中只有其他 `.snapssync`，則讀取修改時間最新者。找不到同步檔時，必須經使用者確認才建立第一份並同步。桌機版應沿用固定檔名與缺檔確認規則。

V0.9.0 將正式資料交換格式升級為 schema 4。`PurchaseRecord` 新增選填的 `recordStatus`、`quantityWasEntered` 與 `locationSource`；缺少欄位的 schema 1～3 資料分別預設為正式紀錄、已知數量，以及依座標判斷為 GPS 或無定位。

快速草稿與最多10張暫存照片只存在 iPhone 本機，不加入 `.snapssync`、CloudKit 或桌機資料庫。草稿轉為 `comparison` 或 `complete` 後才參與正式同步。

## V0.8.1 手機資料相容補充

V0.8.1 手機版的 `PurchaseRecord` 新增 `isGroupPackage` 與 `groupContentCount`。在 schema 3 JSON 中兩欄皆為向前相容的選填欄位；舊資料缺少欄位時分別視為 `false` 與 `1`。桌機端尚未提供這兩欄的編輯介面前，匯入、編輯與重新輸出時不得主動刪除未知欄位。

照片上限提高為5張不改變照片資料格式。海外庫新增的三個建立入口都沿用既有商品與採買紀錄模型，不新增獨立資料表。

## 共用交換格式

- 副檔名：`.snapssync`
- 外層格式：`SnapsSyncEnvelope` schema 1
- 目前資料：`current`
- 雲端歷史：`history`，最多3份
- 每份資料沿用 `SnapsBackupArchive` schema 4；可讀取 schema 1～3
- 日期使用 ISO 8601；識別碼使用 UUID；貨幣保存 ISO 代碼。

## macOS 版方向

- 使用 Xcode、SwiftUI 與 SwiftData。
- 只提供瀏覽、搜尋、編輯、合併重複商品、同步、備份及還原。
- 不加入相機、GPS、OCR及即時條碼掃描。
- 必須讀取國內與海外資料、外幣、食材庫及海外購物數量庫。
- 必須保留 schema 4 的三個新欄位；`quantityWasEntered = false` 的紀錄不得加入累計數量或被改寫成已購買1組。
- 同步前建立本機備份，保留最近3份；支援雲端優先與本機優先。

## Python／Windows 版方向

- 初期支援 Google Drive及手動 `.snapssync` 檔。
- 使用相同 UUID、schema、ISO 8601 日期與貨幣代碼。
- 建議以 Decimal 處理價格，不使用二進位浮點數作交換格式。
- 只提供瀏覽、編輯、衝突選擇、備份及還原。
- 每次手機資料格式升版時，同步更新 Python migration 與測試 fixture。
- schema 4 需把缺少 `quantityWasEntered` 的舊資料視為 `true`；新資料為 `false` 時不得自動補成1後回寫。

## 手機後續資料模型方向

正式製作雙向桌機同步前，再以向前相容方式補入 `modifiedAt`、`modifiedBy`、`revision`、`isDeleted` 與刪除保留期限；CloudKit 正式 schema 不直接刪除或改名既有欄位。
