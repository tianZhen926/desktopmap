#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 产物必须落在 iCloud 同步范围之外：
# ~/Documents 里的 bundle 会被持续贴 com.apple.FinderInfo，codesign 报 "detritus not allowed"。
APP="$HOME/Applications/DesktopMap.app"
STAGE="$HOME/Developer/.build/DesktopMap.app"
ARCH="$(uname -m)"

# 先在暂存目录里编译签名，全部成功才替换线上那份：
# 之前有一版是先 rm -rf 线上 App，编译一失败你手上就没程序了。
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK="$(xcrun --sdk macosx --show-sdk-path)"
echo "==> swiftc ($ARCH, macOS 13 target)"
swiftc -O -sdk "$SDK" -target "${ARCH}-apple-macos13.0" \
  -o "$STAGE/Contents/MacOS/DesktopMap" Sources/*.swift

cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# 「恢复出厂清单」的种子。想留一份自己的清单又不提交进仓库，
# 就放 Resources/default_list.local.json（已在 .gitignore 里），它会盖掉公开那份。
SEED="Resources/default_list.json"
[ -f Resources/default_list.local.json ] && SEED="Resources/default_list.local.json"
echo "==> 种子清单：$SEED"
cp "$SEED" "$STAGE/Contents/Resources/default_list.json"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

xattr -cr "$STAGE"
codesign --force --sign - --identifier dev.fengtianzeng.desktopmap "$STAGE"

mkdir -p "$HOME/Applications"
rm -rf "$APP"
mv "$STAGE" "$APP"

echo "==> 完成：~/Applications/DesktopMap.app"
echo "    启动：open ~/Applications/DesktopMap.app"
echo "    自检：~/Applications/DesktopMap.app/Contents/MacOS/DesktopMap --dump"
echo "    窗口/卡片/状态栏检查：~/Applications/DesktopMap.app/Contents/MacOS/DesktopMap --probe"
