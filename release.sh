#!/bin/bash
set -euo pipefail

# Release: build → 簽 app → pkgbuild → productbuild → productsign → notarize → staple
# 用法: ./release.sh              兩種架構各出一個 pkg
#       ./release.sh x86_64       只出指定架構（arm64 / x86_64）
# 產出: OhMyBias-<版本>-arm64.pkg（Apple Silicon）、OhMyBias-<版本>-x86_64.pkg（Intel）
#       皆已公證＋staple，可上 GitHub Release
#
# 兩個 pkg 分開出、不做 universal binary：swiftc 一次只能編一種架構，而 pkg 的
# hostArchitectures 又能讓 Installer 在裝錯架構時直接擋下，比 lipo 合併再裝多一層保險。
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

ARCHES="${1:-arm64 x86_64}"
for a in $ARCHES; do
    case "$a" in arm64|x86_64) ;; *) echo "[ERR] 架構只能是 arm64 或 x86_64：$a"; exit 1;; esac
done

security find-identity -v -p basic | grep -q "Developer ID Installer" || {
    echo "[ERR] 找不到「Developer ID Installer」憑證 — pkg 需要它才能簽章＋公證。"
    echo "      Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Installer"
    exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

release_arch() {
    local ARCH="$1"
    local PKG_OUT="$ROOT/OhMyBias-$VER-$ARCH.pkg"
    local WORK="$TMP/$ARCH"
    mkdir -p "$WORK"

    # Step 1: 建置
    echo "==> [$ARCH] Step 1/5: 建置..."
    ARCH="$ARCH" "$ROOT/ohmybias.sh" build > /dev/null
    [ -d "$IM_APP" ] || { echo "建置失敗：$IM_APP 不存在"; exit 1; }
    lipo -archs "$IM_APP/Contents/MacOS/OhMyBiasIM" | grep -qx "$ARCH" || {
        echo "建置失敗：binary 架構不是 $ARCH"; exit 1; }

    # Step 2: 簽 app（hardened runtime）
    echo "==> [$ARCH] Step 2/5: Developer ID 簽章 (app)..."
    codesign --deep --force --options runtime --timestamp --sign "$APP_IDENTITY" "$IM_APP"
    codesign --verify --deep --strict "$IM_APP"

    # Step 3: 組 pkg（component → distribution → 簽章）
    echo "==> [$ARCH] Step 3/5: 打包 pkg..."
    # 不用 --component：它預設 BundleIsRelocatable=true，安裝時 Installer 會把 payload
    # 「搬」去蓋機器上任何同 bundle id 的 app（開發機的 build/ 副本首當其衝），
    # /Library/Input Methods 反而裝不進去。改 --root＋component plist 關掉 relocation。
    mkdir "$WORK/root"
    ditto "$IM_APP" "$WORK/root/OhMyBiasIM.app"
    pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist"
    /usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$WORK/component.plist"
    pkgbuild --root "$WORK/root" \
        --component-plist "$WORK/component.plist" \
        --install-location "/Library/Input Methods" \
        --scripts "$ROOT/pkg/scripts" \
        --identifier info.plateaukao.ohmybias.pkg \
        --version "$VER" \
        "$WORK/OhMyBiasIM-component.pkg"
    # hostArchitectures 代入本次架構：裝錯機器時 Installer 直接擋下
    sed "s/@ARCH@/$ARCH/" "$ROOT/pkg/distribution.xml" > "$WORK/distribution.xml"
    productbuild --distribution "$WORK/distribution.xml" \
        --package-path "$WORK" \
        --resources "$ROOT/pkg/resources" \
        "$WORK/OhMyBias-unsigned.pkg"
    rm -f "$PKG_OUT"
    productsign --sign "$PKG_IDENTITY" "$WORK/OhMyBias-unsigned.pkg" "$PKG_OUT"

    # Step 4: 公證
    echo "==> [$ARCH] Step 4/5: 送 Apple 公證（需數分鐘）..."
    xcrun notarytool submit "$PKG_OUT" --keychain-profile "$KEYCHAIN_PROFILE" --wait

    # Step 5: staple
    echo "==> [$ARCH] Step 5/5: Stapling..."
    xcrun stapler staple "$PKG_OUT"

    OUTS+=("$PKG_OUT")
}

OUTS=()
for a in $ARCHES; do release_arch "$a"; done

# build/ 此時是最後一種架構（x86_64）的 binary；重編回本機架構，
# 免得之後 ./ohmybias.sh install 把 Intel 版裝進 /Library/Input Methods
echo "==> 重編本機架構（$(uname -m)）供開發安裝用..."
ARCH="$(uname -m)" "$ROOT/ohmybias.sh" build > /dev/null

echo ""
echo "==> 完成！"
for o in "${OUTS[@]}"; do
    echo "    $o"
done
echo "    （雙擊安裝；結尾建議登出再登入，也可稍後）"
