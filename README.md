# OhMyBias 米

macOS 嘸蝦米（Boshiamy）輸入法 — 純 Swift、零依賴、極簡。

Yabomish 的極簡分支：只保留打字本體 — 打字、查碼（注音／拼音反查）、繁簡轉換、
字頻學習排序、`,,` 指令、擴充表。沒有聯想、沒有詞庫、沒有語料，約 2MB。

（*OhMyBias* 是 *Boshiamy* 的字母重組。）

## 安裝

```bash
./ohmybias.sh          # 編譯 + 安裝（需要管理員密碼）
```

安裝後：系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → OhMyBias。
首次切換時會引導匯入你的 `liu.cin` 字表（需自備合法取得的嘸蝦米字表）。

## 開發

```bash
./ohmybias.sh build            # 只編譯（無 Xcode 專案，raw swiftc）
OhMyBiasIM/Tests/run_tests.sh  # 單元測試
./release.sh                   # 簽章 + 公證發佈
```

兩個 app：**OhMyBiasIM.app**（InputMethodKit 輸入法，裝到 `/Library/Input Methods/`）、
**OhMyBiasPrefs.app**（SwiftUI 設定程式，裝到 `/Applications/`）。
版本號取自 CHANGELOG.md 第一個 `## [x.y.z]` 標題。

使用者資料在 `~/Library/Application Support/OhMyBias/`（字表、freq.db、tables/、commands.json）。

## 授權

MIT（見 LICENSE）。注音對照表來自威注音 VanguardLexicon（MIT）、
繁簡對照表來自 OpenCC（Apache 2.0）、字頻來自萌典（CC0）。
