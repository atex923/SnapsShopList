# SnapsShopList V0.8.2 驗證紀錄

驗證日期：2026-09-15

## 驗證範圍

- Xcode 專案及 Asset Catalog 格式。
- iPhone 17 Pro／iOS 26.5 模擬器 Debug 建置與 Analyze。
- 購買計算及 schema 3 備份相容測試。
- 新建商品畫面的條碼照片鈕、圓框 M、相簿／相機來源入口及立體玻璃視覺。
- 食材庫曾登記商品排序與保存期限紅色顯示。

## 已通過

- `plutil -lint` 專案設定檢查及所有 Asset Catalog JSON 檢查。
- iPhone 17 Pro／iOS 26.5 模擬器 Debug Build。
- iPhone 17 Pro／iOS 26.5 Xcode Analyze。
- `PurchaseLogicSmoke`，包含已用畢食材仍優先於未登記商品。
- `BackupSupportSmoke`，確認資料格式與既有 schema 3 相容。
- 模擬器覆蓋安裝、啟動及新建商品畫面檢查。
- 新建商品畫面截圖：`V0.8.2_new_product_iPhone17Pro.png`。

## 證據界線

- PhotosPicker、Vision 條碼辨識及相機權限需要在實體手機選取真實照片後再確認辨識率。
- 模擬器食材庫沒有既有資料，因此保存期限紅字已完成程式碼與建置檢查，仍待有資料的實機畫面確認。
- 系統鍵盤本體不能由 App 改變位置；本版把可控制的鍵盤收合工具放在輸入附屬列最右側。
- 本版未安裝或同步至實體手機。
