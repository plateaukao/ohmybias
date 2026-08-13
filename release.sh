#!/bin/bash
set -euo pipefail

# Release script: build → sign with Developer ID → notarize → staple
# 用法: ./release.sh
# 產出: build 目錄內已簽章+公證的 .app，以及 repo 根目錄的 OhMyBiasIM.zip / OhMyBiasPrefs.zip

ROOT="$(cd "$(dirname "$0")" && pwd)"
CODESIGN_IDENTITY="Developer ID Application: MAO YUAN KAO (3WD42GF27D)"
KEYCHAIN_PROFILE="notarytool"

IM_APP="$ROOT/OhMyBiasIM/build/OhMyBiasIM.app"
PREFS_APP="$ROOT/OhMyBiasPrefs/build/OhMyBiasPrefs.app"

# Step 1: 建置
echo "==> Step 1/4: 建置..."
"$ROOT/ohmybias.sh" build > /dev/null
[ -d "$IM_APP" ] || { echo "建置失敗：$IM_APP 不存在"; exit 1; }
[ -d "$PREFS_APP" ] || { echo "建置失敗：$PREFS_APP 不存在"; exit 1; }

# Step 2: 簽章（hardened runtime）
echo "==> Step 2/4: Developer ID 簽章..."
for APP in "$IM_APP" "$PREFS_APP"; do
    codesign --deep --force --options runtime --timestamp \
        --sign "$CODESIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
    echo "    signed: $(basename "$APP")"
done

# Step 3: 打包送公證
echo "==> Step 3/4: 送 Apple 公證（需數分鐘）..."
for APP in "$IM_APP" "$PREFS_APP"; do
    NAME="$(basename "$APP" .app)"
    ZIP="$ROOT/$NAME.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait
done

# Step 4: staple 後重新打包（zip 內含 staple ticket，離線也能過 Gatekeeper）
echo "==> Step 4/4: Stapling..."
for APP in "$IM_APP" "$PREFS_APP"; do
    NAME="$(basename "$APP" .app)"
    xcrun stapler staple "$APP"
    rm -f "$ROOT/$NAME.zip"
    ditto -c -k --keepParent "$APP" "$ROOT/$NAME.zip"
done

echo ""
echo "==> 完成！"
echo "    $IM_APP"
echo "    $PREFS_APP"
echo "    $ROOT/OhMyBiasIM.zip / OhMyBiasPrefs.zip（已含 staple ticket，可上 GitHub Release）"
