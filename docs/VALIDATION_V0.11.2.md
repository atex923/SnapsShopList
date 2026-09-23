# SnapsShopList V0.11.2 驗證紀錄

日期：2026-09-23

## 驗證範圍

- 商品照片相機每次顯示時重設為 `1.0×`。
- 一般鏡頭與近拍小花模式切換後皆套用 `1.0×`。
- 條碼掃描相機未修改。
- 版本 `0.11.2`、Build `112`；SwiftData 與備份 schema 未變更。

## 已通過

- iOS Generic Device Debug Build 通過。
- Xcode Analyze 通過。
- iPhone 17 Pro（iOS 26.3）Simulator Build、覆蓋安裝與基本啟動通過。
- 產物版本為 `0.11.2`、Build `112`，顯示名稱「購物記本」、Bundle ID `com.atex1.SnapshotBuyCheck`。
- 原始碼確認商品相機建立工作階段、每次畫面顯示，以及一般／小花鏡頭切換時都會套用 `1.0×`。
- Atex-iPhone16 實機簽署建置通過；簽章 Team ID `Y3ZLRY9835`。
- 已用相同 Bundle ID 覆蓋安裝至 Atex-iPhone16；手機回報版本 `0.11.2`、Build `112`。
- 安裝過程沒有解除安裝 App，裝置回報的安裝資料庫識別與前版相同。

## 尚待實機驗證

- 模擬器沒有實體相機，無法證明 iPhone 實際鏡頭視角與倍率顯示。
- 需在 iPhone 分別測試新增照片、補拍及更換照片三個入口。
- 自動啟動時手機處於鎖定狀態，iOS 拒絕遠端啟動；安裝本身已成功。解鎖後可直接點選「購物記本」。
