# Changelog

格式基於 [Keep a Changelog](https://keepachangelog.com/)。

## 未發佈

### 新增
- **Intel 版 pkg** — `release.sh` 改為 arm64 與 x86_64 各出一個 pkg（`OhMyBias-x.y.z-arm64.pkg`／`-x86_64.pkg`），pkg 的 `hostArchitectures` 對應架構，裝錯機器 Installer 會直接擋下。程式碼沒有任何架構相關分支，Intel 版只是換編譯目標；0.6.0 的 Intel 版已用同一份程式碼補上。系統需求仍為 macOS 14（2019 以後的 Intel iMac 可用）。

## [0.6.0] — 2026-08-21

### 修正
- **切換輸入法偶爾靜默失敗（heap corruption）** — `activateServer` 會一邊在背景執行緒建反查表、一邊在主執行緒重載同一個共用的 `CINTable`，兩邊同時讀寫同一批 Dictionary，把 heap freelist 寫壞（`BUG IN CLIENT OF LIBMALLOC` / SIGTRAP），輸入法 process 死在切換途中，系統退回英文、使用者得再按一次。`CINTable` 改成「不可變快照＋整份原子替換」：載入端在區域變數上組好完整快照再上鎖換掉，讀取端只在鎖內取出參考、其餘全在鎖外操作，建表不再擋按鍵路徑。
- **每換一個 app 就整表重載一次** — IMK 每個 client app 各建一個 controller，其 `engine` getter 又呼叫 `InputEngine.loadTable()` → `cinTable.reload()`，而共用的 `static let cinTable` 初始化時已經載過。移除這條重載路徑（`InputEngine.loadTable()` 一併刪除），字表只在啟動、`,,RL`、匯入字表、以及偏好設定改擴充表時重載。
- **偏好設定改擴充表沒有生效** — `info.plateaukao.ohmybias.reloadTables` 通知從來沒有人接收（以前靠上述「換 app 就重載」矇混過去）；改由 `AppDelegate` 明確接起來呼叫 `reloadTable()`。

### 變更
- **不再預先建立反查表** — 反查表只有注音／同音模式、簡碼／長碼模式、字碼提示會用到，一般打字完全不碰，卻在每次從別的輸入法切進來時就丟到背景整份重建（peak footprint 一度到 207 MB）。改為真的用到才建，並在匯入完成的訊息改用只掃一次碼表的字數統計。
- **鍵盤佈局不再每次 activate 都重套** — 補回 `lastAppliedKeyboardLayout` 判斷（宣告了但從未使用）：從別的輸入法切回來時仍一律重套 ABC 佈局（對方可能改過），app 之間切換則跳過。

## [0.5.0] — 2026-08-21

### 新增
- **英文補空白（預設關閉）** — 設定 →「輸入功能」新增卡片：開啟後，英文直印送出的字母尾端自動補一個空白（無候選字按空白鍵、或按 Enter 送出原碼皆適用），接著打下一個英文單字不必自己補空白。只對純英文字母的組字串生效，含標點或萬用字元（`*`）的組字串維持原樣。
- **設定顯示版本號** — 說明分頁「原始碼」連結上方加上版本行（`x.y.z（build …）`），回報問題時可直接對照。

## [0.4.0] — 2026-08-17

### 變更
- **無候選字時可續打，空白鍵原樣送出字母** — 輸入碼查無候選字時不再自動清空組字串：可以繼續打（不受碼長上限限制），按空白鍵把打到一半的字母原樣送出，作為無蝦米模式下快速輸入英文單字的途徑（與 Enter 送出原文一致）。原「打滿碼長無候選自動清空」與空白鍵清空行為移除；要放棄組字改用 Esc 或退格。注意：模糊比對（相鄰鍵）開啟時，打錯的碼若被模糊比對找到候選字，空白鍵仍會送出該候選字。

## [0.3.0] — 2026-08-14

### 變更
- **候選字排序改為「字表順序＋`,,PIN` 固定排序」** — 打字路徑不再查詢／記錄字頻：原本每個按鍵最多兩次同步 SQLite 查詢（跨執行緒），且每 500 字觸發的字頻衰減（全表 UPDATE＋DELETE）會讓當下那一鍵卡住。現在排序是純記憶體操作：有 `,,PIN` 的碼把固定字排前，其餘一律維持字表順序。字頻機制（記錄、排序、衰減、JSON 遷移／同步）整組移除，`,,RS` 指令一併移除。
- **FreqTracker 瘦身更名為 PinnedStore、改用 `pinned.db`** — 只剩 `,,PIN` 固定排序單表＋記憶體快取；首次啟動自動把舊 `freq.db` 的固定排序搬進 `pinned.db` 並刪除舊檔。全 controller 共用單一實例（IMK 每個 client app 各建一個 controller，原本每個都另開自己的 SQLite 連線與 pinned 快取），`,,PIN` 立即跨 app 生效。

## [0.2.0] — 2026-08-14

### 變更
- **合併為單一 app** — 設定視窗內建於 OhMyBiasIM.app（輸入法選單 →「偏好設定⋯」），移除獨立的 OhMyBiasPrefs.app。
- **pkg 安裝** — `release.sh` 改產出已簽章＋公證的 `OhMyBias-x.y.z.pkg`：雙擊安裝、自動註冊輸入法、結尾建議登出再登入（可稍後）。移除 install.sh。
- **安裝結尾不再只有「登出」按鈕** — 移除 `onConclusion="RequireLogout"`（它讓結尾只剩強制登出、無法稍後再說），改回一般「關閉」；postinstall 已註冊輸入法，多數情況不登出即可加入，清單沒出現再登出即可。

### 變更（顯示名稱）
- **輸入來源顯示名稱改為「無米蝦」** — 系統設定輸入來源清單、輸入法選單皆顯示「無米蝦」；灰色副標（app 名稱）維持 OhMyBias，不再上下兩行重複同名。副標為系統設定對第三方輸入法的固定標示（Squirrel 亦同），宣告 input mode 時無法移除。

### 修正
- **輸入法完全不出現在系統設定** — bundle id 改為 `info.plateaukao.inputmethod.ohmybias`：macOS TIS 只註冊 bundle id 含 `inputmethod` 子字串的輸入法（`TISRegisterInputSource` 對不合規的 app 回報成功但實際不註冊），原 id `info.plateaukao.ohmybias` 因此在「繁體中文」輸入方式清單完全找不到。
- **pkg 裝不進 `/Library/Input Methods`** — `pkgbuild --component` 預設允許 bundle relocation：機器上若已註冊同 bundle id 的 app（如開發機 `build/` 裡的副本），Installer 會把 payload 搬去蓋那份，輸入法清單自然找不到。改用 `--root`＋component plist 將 `BundleIsRelocatable` 設為 false。
- 使用者資料夾（capture script、commands.json）改由 app 首次啟動時自動部署。
- **每次切換視窗都跳出模式提示** — 輸入來源觀察者仍比對舊 bundle id 子字串 `plateaukao.ohmybias`，改名為 `info.plateaukao.inputmethod.ohmybias` 後永遠比不到，每次視窗切換都被誤判為「從其他輸入法切回」而重播切入提示；改比對 `inputmethod.ohmybias`。切入提示本身可在 偏好設定 → 外觀 → 「切入提示」關閉。
- **游標選字窗寬度不會隨候選字縮小**（移植自 Yabomish `fix/cursor-panel-stale-width`）— 隱藏中的固定模式標籤殘留 Auto Layout constraint 與舊文字，把視窗寬度撐在舊尺寸；改為切換佈局時停用／啟用該組 constraint，選字窗寬度隨候選字數自動縮放。
- **直向選字窗貼齊內容寬** — 移除 80pt 最小寬度下限，候選字少（如兩字一行）時不再留一大截空白。

## [0.1.0] — 2026-08-14

### 新功能
- 初版 — 自 Yabomish 抽出的純極簡嘸蝦米輸入法：打字、查碼（注音／拼音反查）、繁簡轉換、字頻學習排序、`,,` 指令、擴充表。無聯想、無詞庫、無語料。
- 全新識別：OhMyBias（`info.plateaukao.ohmybias`）、「米」鍵帽圖示。
- 固定選字列可任意拖曳並記住位置。
