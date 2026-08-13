#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 使用者安裝腳本（隨 release zip 發佈）

G='\033[32m'; Y='\033[33m'; N='\033[0m'
ok()   { printf "${G}[OK] %s${N}\n" "$1"; }
warn() { printf "${Y}[!!] %s${N}\n" "$1"; }

[ -d OhMyBiasIM.app ] && [ -d OhMyBiasPrefs.app ] || { echo "請在解壓後的資料夾內執行 ./install.sh"; exit 1; }

echo "安裝 OhMyBias 輸入法（需要管理員密碼）..."
killall OhMyBiasIM 2>/dev/null || true; sleep 1

sudo rm -rf "/Library/Input Methods/OhMyBiasIM.app"
sudo cp -R OhMyBiasIM.app "/Library/Input Methods/"
sudo chmod -R a+rX "/Library/Input Methods/OhMyBiasIM.app"
ok "OhMyBiasIM.app -> /Library/Input Methods/"

rm -rf /Applications/OhMyBiasPrefs.app
cp -R OhMyBiasPrefs.app /Applications/
ok "OhMyBiasPrefs.app -> /Applications/"

# 使用者資料夾
USER_DIR="$HOME/Library/Application Support/OhMyBias"
mkdir -p "$USER_DIR/tables"

# 註冊並啟動（免登出）
if [ -x /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent ]; then
    /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent 2>/dev/null || true
fi
open "/Library/Input Methods/OhMyBiasIM.app" 2>/dev/null || true
sleep 2
pgrep -q OhMyBiasIM && ok "輸入法已啟動" || warn "系統未自動啟動，請登出再登入"

ok "完成！系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → OhMyBias"
[ -f "$USER_DIR/liu.cin" ] || [ -f "$USER_DIR/liu.bin" ] || warn "首次切換到 OhMyBias 時會引導匯入 liu.cin 字表"
