#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 产物必须落在 iCloud 同步范围之外：
# ~/Documents 里的 bundle 会被持续贴 com.apple.FinderInfo，codesign 报 "detritus not allowed"。
APP="${DM_OUT:-$HOME/Applications/DesktopMap.app}"
STAGE="${DM_STAGE:-$HOME/Developer/.build/DesktopMap.app}"

# 先在暂存目录里编译签名，全部成功才替换线上那份：
# 之前有一版是先 rm -rf 线上 App，编译一失败你手上就没程序了。
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_ID="dev.fengtianzeng.desktopmap"

# 日常开发只编本机架构（一份约 40 秒）；DM_UNIVERSAL=1 时 arm64 + x86_64 合成通用二进制。
if [ "${DM_UNIVERSAL:-}" = "1" ]; then ARCHES=(arm64 x86_64); else ARCHES=("$(uname -m)"); fi

slice="$STAGE/Contents/MacOS/.slices"
mkdir -p "$slice"
for arch in "${ARCHES[@]}"; do
  echo "==> swiftc ($arch, macOS 13 target)"
  swiftc -O -sdk "$SDK" -target "${arch}-apple-macos13.0" \
    -o "$slice/$arch" Sources/*.swift
done
if [ "${#ARCHES[@]}" -gt 1 ]; then
  lipo -create "$slice/arm64" "$slice/x86_64" -output "$STAGE/Contents/MacOS/DesktopMap"
else
  cp "$slice/${ARCHES[0]}" "$STAGE/Contents/MacOS/DesktopMap"
fi
chmod +x "$STAGE/Contents/MacOS/DesktopMap"
rm -rf "$slice"

cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# 「恢复出厂清单」的种子。想留一份自己的清单又不提交进仓库，
# 就放 Resources/default_list.local.json（已在 .gitignore 里），它会盖掉公开那份。
# 打包对外发布时必须 DM_SEED=public，别把自己的目录名发到网上。
SEED="Resources/default_list.json"
if [ "${DM_SEED:-}" != "public" ] && [ -f Resources/default_list.local.json ]; then
  SEED="Resources/default_list.local.json"
fi
echo "==> 种子清单：$SEED"
cp "$SEED" "$STAGE/Contents/Resources/default_list.json"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

xattr -cr "$STAGE"
codesign --force --sign - --identifier "$SIGN_ID" "$STAGE"

mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mv "$STAGE" "$APP"

echo "==> 完成：$APP"
echo "    启动：open \"$APP\""
echo "    自检：\"$APP/Contents/MacOS/DesktopMap\" --dump"
echo "    窗口/卡片/状态栏检查：\"$APP/Contents/MacOS/DesktopMap\" --probe"
