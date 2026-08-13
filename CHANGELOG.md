# Changelog

格式基於 [Keep a Changelog](https://keepachangelog.com/)。

## [0.2.0] — 2026-08-14

### 變更
- **合併為單一 app** — 設定視窗內建於 OhMyBiasIM.app（輸入法選單 →「偏好設定⋯」），移除獨立的 OhMyBiasPrefs.app。
- **pkg 安裝** — `release.sh` 改產出已簽章＋公證的 `OhMyBias-x.y.z.pkg`：雙擊安裝、自動註冊輸入法、結尾建議登出再登入（可稍後）。移除 install.sh。
- 使用者資料夾（capture script、commands.json）改由 app 首次啟動時自動部署。

## [0.1.0] — 2026-08-14

### 新功能
- 初版 — 自 Yabomish 抽出的純極簡嘸蝦米輸入法：打字、查碼（注音／拼音反查）、繁簡轉換、字頻學習排序、`,,` 指令、擴充表。無聯想、無詞庫、無語料。
- 全新識別：OhMyBias（`info.plateaukao.ohmybias`）、「米」鍵帽圖示。
- 固定選字列可任意拖曳並記住位置。
