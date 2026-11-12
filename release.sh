#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 对外发布只走这个脚本：它强制用公开种子清单 + 通用二进制，
# 并在打包前后各扫一遍私人路径。不要拿 build.sh 装到 ~/Applications 那份直接压 zip——
# 那份里带的是你自己整理的清单（Resources/default_list.local.json）。

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
OUT="$PWD/.releases"
APP="$OUT/DesktopMap.app"
BIN="$APP/Contents/MacOS/DesktopMap"

# 公开渠道拿不到的目录名，一条都不许出现在包里
PRIVATE_PATTERN='天真|tianzhenai|tianzhen-admin|sub2api|house-resource|批发代码|剧本杀|AiMaMi|get_jobs|私有知识库|ComfyUI-Shared|New project|MacAppData|/Users/'

echo "==> 构建 v$VERSION（公开种子 + 通用二进制）"
rm -rf "$OUT"
mkdir -p "$OUT"
DM_SEED=public DM_UNIVERSAL=1 DM_OUT="$APP" ./build.sh >/dev/null

echo "==> 上线前自检"
echo "    架构：$(lipo -archs "$BIN")"
codesign --verify --strict --verbose=1 "$APP" 2>&1 | sed 's/^/    /'
SEED="$APP/Contents/Resources/default_list.json"
echo "    公开种子：$(python3 -c "import json;print(len(json.load(open('$SEED'))))") 条"
if grep -qE "$PRIVATE_PATTERN" "$SEED"; then
  echo "!! 种子里出现私人路径，停止打包"; grep -nE "$PRIVATE_PATTERN" "$SEED"; exit 1
fi
if strings -a "$BIN" | grep -qE "$PRIVATE_PATTERN"; then
  echo "!! 二进制里出现私人路径，停止打包"; strings -a "$BIN" | grep -E "$PRIVATE_PATTERN" | head; exit 1
fi
echo "    私人路径扫描：通过"

echo "==> 打包"
ZIP="$OUT/DesktopMap-$VERSION.zip"
DMG="$OUT/DesktopMap-$VERSION.dmg"
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

ROOT="$OUT/.dmgroot"
mkdir -p "$ROOT"
cp -R "$APP" "$ROOT/DesktopMap.app"
ln -s /Applications "$ROOT/Applications"
hdiutil create -volname DesktopMap -srcfolder "$ROOT" -ov -quiet -format UDZO "$DMG"
# 拖拽安装要能用，挂载点上的那份也得能起
hdiutil attach -nobrowse -quiet -mountpoint "$OUT/.mnt" "$DMG"
echo "    挂载后校验：$(lipo -archs "$OUT/.mnt/DesktopMap.app/Contents/MacOS/DesktopMap")"
hdiutil detach -quiet "$OUT/.mnt"
rm -rf "$ROOT" "$OUT/.mnt"

(cd "$OUT" && shasum -a 256 "DesktopMap-$VERSION.zip" "DesktopMap-$VERSION.dmg" > SHA256SUMS.txt)

echo "==> 产物"
ls -lh "$OUT" | awk 'NR>1{printf "    %-34s %s\n", $9, $5}'
echo "    SHA256：$(cat "$OUT/SHA256SUMS.txt" | tr '\n' ' ')"
