#!/bin/bash
set -euo pipefail

# Release: build → 簽 app → pkgbuild → productbuild → productsign → notarize → staple
# 用法: ./release.sh
# 產出: OhMyBias-<版本>.pkg（已公證＋staple，可上 GitHub Release）
#
# 需要兩張憑證：
#   - Developer ID Application（簽 app）
#   - Developer ID Installer（簽 pkg）— 若缺少，到 Xcode → Settings → Accounts →
#     Manage Certificates → + → Developer ID Installer 建立（一次性）

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_IDENTITY="Developer ID Application: MAO YUAN KAO (3WD42GF27D)"
PKG_IDENTITY="Developer ID Installer: MAO YUAN KAO (3WD42GF27D)"
KEYCHAIN_PROFILE="notarytool"

IM_APP="$ROOT/OhMyBiasIM/build/OhMyBiasIM.app"
VER=$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" | sed 's/.*\[\(.*\)\].*/\1/')
PKG_OUT="$ROOT/OhMyBias-$VER.pkg"

security find-identity -v -p basic | grep -q "Developer ID Installer" || {
    echo "[ERR] 找不到「Developer ID Installer」憑證 — pkg 需要它才能簽章＋公證。"
    echo "      Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Installer"
    exit 1
}

# Step 1: 建置
echo "==> Step 1/5: 建置..."
"$ROOT/ohmybias.sh" build > /dev/null
[ -d "$IM_APP" ] || { echo "建置失敗：$IM_APP 不存在"; exit 1; }

# Step 2: 簽 app（hardened runtime）
echo "==> Step 2/5: Developer ID 簽章 (app)..."
codesign --deep --force --options runtime --timestamp --sign "$APP_IDENTITY" "$IM_APP"
codesign --verify --deep --strict "$IM_APP"

# Step 3: 組 pkg（component → distribution → 簽章）
echo "==> Step 3/5: 打包 pkg..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pkgbuild --component "$IM_APP" \
    --install-location "/Library/Input Methods" \
    --scripts "$ROOT/pkg/scripts" \
    --identifier info.plateaukao.ohmybias.pkg \
    --version "$VER" \
    "$TMP/OhMyBiasIM-component.pkg"
productbuild --distribution "$ROOT/pkg/distribution.xml" \
    --package-path "$TMP" \
    --resources "$ROOT/pkg/resources" \
    "$TMP/OhMyBias-unsigned.pkg"
rm -f "$PKG_OUT"
productsign --sign "$PKG_IDENTITY" "$TMP/OhMyBias-unsigned.pkg" "$PKG_OUT"

# Step 4: 公證
echo "==> Step 4/5: 送 Apple 公證（需數分鐘）..."
xcrun notarytool submit "$PKG_OUT" --keychain-profile "$KEYCHAIN_PROFILE" --wait

# Step 5: staple
echo "==> Step 5/5: Stapling..."
xcrun stapler staple "$PKG_OUT"

echo ""
echo "==> 完成！"
echo "    ${PKG_OUT}（雙擊安裝；結尾建議登出再登入，也可稍後）"
