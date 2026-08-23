# OhMyBias 米

macOS 嘸蝦米（Boshiamy）輸入法 — 純 Swift、零依賴、極簡、單一 app。

[Yabomish](https://github.com/plateaukao/yabomish) 的極簡分支：只保留打字本體 —
打字、查碼（注音／拼音反查）、繁簡轉換、字頻學習排序、`,,` 指令、擴充表。
沒有聯想、沒有詞庫、沒有語料，約 2MB。
設定視窗內建在輸入法裡（輸入法選單 →「偏好設定⋯」），沒有獨立設定 app。

（*OhMyBias* 是 *Boshiamy* 的字母重組；輸入來源清單顯示為「無米蝦」。）

## 安裝

從 Release 下載對應機器的 pkg，雙擊安裝（需 macOS 14 Sonoma 以上）：

- Apple Silicon（M 系列）：`OhMyBias-x.y.z-arm64.pkg`
- Intel（2019 以後的 iMac 等）：`OhMyBias-x.y.z-x86_64.pkg`

裝錯架構 Installer 會直接擋下。安裝結尾建議登出再登入
（也可以稍後），然後到 系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → 無米蝦。
首次切換時會引導匯入你的 `liu.cin` 字表（需自備合法取得的嘸蝦米字表）。

## 開發

```bash
./ohmybias.sh                  # 編譯 + 安裝（開發用，需要管理員密碼）
./ohmybias.sh build            # 只編譯（無 Xcode 專案，raw swiftc；ARCH=x86_64 可交叉編譯）
OhMyBiasIM/Tests/run_tests.sh  # 單元測試
./release.sh                   # 簽章 + 公證 → OhMyBias-x.y.z-{arm64,x86_64}.pkg（可只給一種架構）
```

單一 app：**OhMyBiasIM.app**（InputMethodKit 輸入法＋內建 SwiftUI 設定視窗，
裝到 `/Library/Input Methods/`）。版本號取自 CHANGELOG.md 第一個 `## [x.y.z]` 標題。

release 需要兩張憑證：Developer ID **Application**（簽 app）與 Developer ID
**Installer**（簽 pkg）。

使用者資料在 `~/Library/Application Support/OhMyBias/`（字表、freq.db、tables/、commands.json），
由 app 首次啟動時自動建立。

## 授權

MIT（見 LICENSE）。注音對照表來自威注音 VanguardLexicon（MIT）、
繁簡對照表來自 OpenCC（Apache 2.0）、字頻來自萌典（CC0）。
