#!/bin/sh
# CloudFlareScan iOS 构建脚本（iSH / Alpine aarch64，无 Mac）
# 产物: out/CloudFlareScan-iOS.ipa  （TrollStore 直接安装）
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
if [ -z "$CFS_SDK" ]; then
    for cand in "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
                "$ROOT/../theos-sdks/iPhoneOS16.5.sdk" \
                "$ROOT/theos-sdks/iPhoneOS16.5.sdk"; do
        [ -d "$cand" ] && CFS_SDK="$cand" && break
    done
fi
if [ -z "$CFS_SDK" ] && command -v xcrun >/dev/null 2>&1; then
    CFS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
fi
SDK=${CFS_SDK:-/var/minis/workspace/cfscan/theos-sdks/iPhoneOS16.5.sdk}
MIN_IOS=14.0
SDK_VER=16.5
NAME=CloudFlareScan
OUT="$ROOT/out"
APP="$OUT/Payload/$NAME.app"

if [ ! -d "$SDK" ]; then
    echo "SDK not found: $SDK" >&2
    exit 1
fi

echo "==> 生成 index.html"
python3 "$ROOT/tools/make_index.py"

echo "==> 清理"
rm -rf "$OUT"
mkdir -p "$APP/www"

EXTRA=""
[ "$1" = "--debug" ] && EXTRA="-DCFS_DEBUG"

echo "==> 编译 (arm64-apple-ios$MIN_IOS)  SDK=$SDK"
clang $EXTRA \
    -target "arm64-apple-ios$MIN_IOS" \
    -isysroot "$SDK" \
    -fobjc-arc -fblocks -O2 \
    -fuse-ld=lld \
    -Wno-unused-parameter \
    -Wno-nullability-completeness \
    -Wno-deprecated-declarations \
    -framework Foundation \
    -framework UIKit \
    -framework WebKit \
    -framework Network \
    -framework Security \
    -framework CoreGraphics \
    -Wl,-platform_version -Wl,ios,$MIN_IOS,$SDK_VER \
    -Wl,-adhoc_codesign \
    -o "$APP/$NAME" \
    "$ROOT"/src/*.m

echo "==> 组装 App 包"
cp "$ROOT/res/Info.plist" "$APP/Info.plist"
cp "$ROOT/src/shim.js" "$APP/shim.js"
cp "$ROOT"/res/icon/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
cp -r "$ROOT/res/www/." "$APP/www/"

if command -v plutil >/dev/null 2>&1; then
    plutil -convert binary1 "$APP/Info.plist" 2>/dev/null || true
fi

echo "==> 打包 IPA"
cd "$OUT"
zip -qry "$NAME-iOS.ipa" Payload
cd "$ROOT"

echo "==> 校验"
python3 "$ROOT/tools/verify_ipa.py" "$OUT/$NAME-iOS.ipa"

ls -l "$OUT/$NAME-iOS.ipa"
