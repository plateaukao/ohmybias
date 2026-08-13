#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# OhMyBias 建置／安裝工具（開發用；使用者請用 release 的 OhMyBias.pkg）
# 用法: ./ohmybias.sh            編譯 + 安裝
#       ./ohmybias.sh build      只編譯
#       ./ohmybias.sh install    只安裝（已編譯過）
#       ./ohmybias.sh uninstall  移除

G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; N='\033[0m'
ok()   { printf "${G}[OK] %s${N}\n" "$1"; }
warn() { printf "${Y}[!!] %s${N}\n" "$1"; }
err()  { printf "${R}[ERR] %s${N}\n" "$1"; exit 1; }

IM_SRC="$ROOT/OhMyBiasIM/Sources"
IM_RES="$ROOT/OhMyBiasIM/Resources"
IM_BUILD="$ROOT/OhMyBiasIM/build"
IM_APP="$IM_BUILD/OhMyBiasIM.app"
INSTALL_DIR="/Library/Input Methods"
USER_DIR="$HOME/Library/Application Support/OhMyBias"
IM_BUNDLE_ID="info.plateaukao.inputmethod.ohmybias"

check_xcode() {
    if ! xcode-select -p &>/dev/null; then
        warn "需要 Xcode Command Line Tools，正在安裝..."
        xcode-select --install
        err "安裝完成後請重新執行 ./ohmybias.sh"
    fi
}

build_im() {
    printf "${C}> 編譯輸入法...${N}\n"
    rm -rf "$IM_BUILD"
    mkdir -p "$IM_APP/Contents/MacOS" "$IM_APP/Contents/Resources"

    cp "$IM_RES/Info.plist" "$IM_APP/Contents/Info.plist"
    local VER; VER=$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" | sed 's/.*\[\(.*\)\].*/\1/')
    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VER}" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    for f in icon.icns menu_icon.pdf \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json char_freq.json \
             ohmybias_capture.sh commands-example.json; do
        [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$IM_RES/tables" ] && cp -R "$IM_RES/tables" "$IM_APP/Contents/Resources/"
    for d in "$IM_RES"/*.lproj; do
        [ -d "$d" ] && cp -R "$d" "$IM_APP/Contents/Resources/"
    done
    echo -n "APPL????" > "$IM_APP/Contents/PkgInfo"

    swiftc -module-name OhMyBiasIM \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O \
        -o "$IM_APP/Contents/MacOS/OhMyBiasIM" \
        $(find "$IM_SRC" -name "*.swift" | sort)

    ok "OhMyBiasIM.app (build $STAMP.$HASH, $(du -sh "$IM_APP" | cut -f1))"
}

do_install() {
    [ -d "$IM_APP" ] || err "請先執行 ./ohmybias.sh build"
    printf "${C}> 安裝輸入法（需要管理員密碼）...${N}\n"
    killall OhMyBiasIM 2>/dev/null || true; sleep 1

    sudo rm -rf "$INSTALL_DIR/OhMyBiasIM.app"
    sudo cp -R "$IM_APP" "$INSTALL_DIR/"
    sudo chmod -R a+rX "$INSTALL_DIR/OhMyBiasIM.app"
    ok "輸入法已安裝"

    printf "${C}> 重新啟動輸入法...${N}\n"
    if [ -x /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent ]; then
        /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent 2>/dev/null || true
    fi
    open "$INSTALL_DIR/OhMyBiasIM.app" 2>/dev/null || true
    sleep 2

    if pgrep -q OhMyBiasIM; then
        ok "輸入法已啟動"
        ok "到 系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → OhMyBias"
    else
        warn "系統未自動啟動，請登出再登入"
    fi
    [ -f "$USER_DIR/liu.cin" ] || [ -f "$USER_DIR/liu.bin" ] || warn "首次切換到 OhMyBias 時會引導匯入 liu.cin 字表"
}

do_uninstall() {
    printf "確定要移除 OhMyBias？[y/N] "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] || { echo "已取消。"; return; }
    killall OhMyBiasIM 2>/dev/null || true; sleep 0.5
    sudo rm -rf "$INSTALL_DIR/OhMyBiasIM.app"
    defaults delete $IM_BUNDLE_ID 2>/dev/null || true
    printf "一併刪除使用者資料（字表、字頻）？[y/N] "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] && rm -rf "$USER_DIR" && echo "已刪除 $USER_DIR"
    ok "移除完成，請登出再登入"
}

check_xcode
case "${1:-}" in
    build)     build_im;;
    install)   do_install;;
    uninstall) do_uninstall;;
    "")        build_im; do_install;;
    *)         echo "用法: $0 [build|install|uninstall]"; exit 1;;
esac
