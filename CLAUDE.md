# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OhMyBias 米 — macOS 嘸蝦米（Boshiamy）輸入法，Yabomish 的極簡分支（*OhMyBias* 為 *Boshiamy* 之字母重組）。純 Swift、零依賴、單一版本、**單一 app**：**OhMyBiasIM.app**（IMK 輸入法 → `/Library/Input Methods/`），SwiftUI 設定視窗內建其中（`Sources/PrefsUI/`，輸入法選單 →「偏好設定⋯」開啟；`PrefsWindow` 只隱藏不 terminate — terminate 會殺掉輸入法本體）。只有打字、查碼、繁簡轉換、字頻排序、`,,` 指令、擴充表 — **沒有**聯想／詞庫／語料，也刻意不加回去。文件、commit、註解、UI 皆用繁體中文。

## Build & install

沒有 Xcode 專案、沒有 SPM — `ohmybias.sh` 直接呼叫 swiftc，編所有 `OhMyBiasIM/Sources/**/*.swift`（含 `PrefsUI/`）。新增檔案＝放進目錄即可。

```bash
./ohmybias.sh            # 編譯 + 安裝（開發用，sudo）
./ohmybias.sh build      # 只編譯
./ohmybias.sh uninstall  # 移除（互動確認）
./release.sh             # 簽 app + pkgbuild/productbuild + 簽 pkg + 公證 + staple → OhMyBias-x.y.z.pkg
```

編譯目標 `arm64-apple-macos14.0`（Apple Silicon、macOS 14+）。公證用 keychain profile `notarytool`。打包必須經 component plist 把 `BundleIsRelocatable` 設 false（release.sh 已處理，勿改回 `pkgbuild --component`）— 否則機器上若有同 bundle id 的副本（開發機的 `build/`），Installer 會把 payload relocate 去蓋那份，`/Library/Input Methods` 裝不進去。

單一版本、無模式選項。版本號取自 CHANGELOG.md 第一個 `## [x.y.z]`（改版＝加 CHANGELOG 條目）。發佈給使用者的是 **pkg**（`pkg/` 內有 distribution.xml、postinstall、welcome/conclusion 頁；不設 `onConclusion` — `RequireLogout` 會讓結尾只剩強制「登出」鈕，登出僅作為 conclusion 頁的建議）。release 需要 Developer ID Application＋Installer 兩張憑證。簽章後的 bundle 不可再修改。使用者資料夾由 app 啟動時建立（`AppDelegate.setUpUserDir`），pkg postinstall 不碰使用者家目錄。

## Tests

```bash
OhMyBiasIM/Tests/run_tests.sh
```

無 XCTest — 純函式 + `check`/`checkEqual`，由 `Tests/main.swift` 逐一呼叫；一律整包跑，無單測篩選。新增測試＝寫 `func testXxx()` 並在 main.swift 加呼叫。編譯範圍是 `Sources/` 與 `Sources/Shared/` 頂層（`PrefsUI/` 因 maxdepth 不編入），UI／IMK 檔再以 run_tests.sh 的 `EXCLUDE` regex 剔除；被剔除的檔案若被測試目標引用，在 `Tests/Stubs/` 補 stub（現有 `DebugLogStub.swift`）。`MockEngineDelegate.swift` 記錄所有 delegate callback，是測引擎的標準做法。

## Architecture

平台層／引擎層分離：

- `OhMyBiasIM/Sources/`（macOS）：`OhMyBiasInputController.swift`＝IMKInputController（鍵盤事件、IMK 整合）；`CandidatePanel.swift`＝選字窗（游標跟隨＋固定模式，可拖曳）；`AppDelegate.swift` 啟動 IMKServer。
- `OhMyBiasIM/Sources/Shared/`：**禁止 import AppKit/IMK**。`InputEngine.swift` 是核心狀態機（組字、選字、`,,` 指令），透過 `InputEngineDelegate` 回呼；`IMEPreferences.swift` 為可注入的偏好協定。

按鍵資料流：keyCode → `OhMyBiasInputController` → `InputEngine`（`CINTable` 查表、`CandidateRanker`＋`FreqTracker` n-gram 排序）→ delegate → 選字窗。

儲存：使用者匯入 `liu.cin` → `CINCompiler` 編成 `liu.bin`（mmap 零拷貝）。使用者資料在 `~/Library/Application Support/OhMyBias/`（cin/bin、`freq.db`、`tables/` 擴充表、`commands.json`）。偏好透過 `info.plateaukao.inputmethod.ohmybias` defaults domain（＝bundle id，**必須含 `inputmethod` 子字串**，否則 TIS 不註冊、系統設定看不到）共享，變更以 distributed notification `info.plateaukao.ohmybias.prefsChanged` 通知（通知名為寫死字串，與 bundle id 無關）。

## 與 Yabomish 的關係

抽出時已把上游的 `#if MINIMAL`／`#if os(iOS)` 條件實體化（保留極簡／macOS 側），聯想引擎、詞庫、語料 binary、下載器整組移除。從 Yabomish 移植修正時，該處若在上游是 `#if !MINIMAL` 內的程式碼，這裡不存在也不該補回。
