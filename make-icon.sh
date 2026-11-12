#!/bin/bash
# 从一张方图生成 Resources/AppIcon.icns。
# 用法：./make-icon.sh path/to/source.png
# 流程：裁中心主体 → 画圆角遮罩（去掉生成图的白边）→ 按 Apple 网格留边 → 切 10 个尺寸 → iconutil。
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:?用法: ./make-icon.sh <源图.png>（正方形，图标主体居中）}"
OUT="Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/mask.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard let img = NSImage(contentsOfFile: args[1]),
      let tiff = img.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: tiff),
      let src = srcRep.cgImage else { fatalError("读不到 \(args[1])") }

let cs = CGColorSpaceCreateDeviceRGB()
func bitmap(_ side: Int) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
              bytesPerRow: side * 4, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// 生成图里的 squircle 大约占画布 88%，居中。裁掉外圈白底，只留主体。
let w = src.width, h = src.height
let cropSide = Int(Double(min(w, h)) * 0.88)
let origin = (w - cropSide) / 2
let cropped = src.cropping(to: CGRect(x: origin, y: (h - cropSide) / 2,
                                      width: cropSide, height: cropSide))!

// 自己画圆角遮罩：半径取 0.26，比 squircle 略大，宁可切掉一点图也不留白角。
let R = CGFloat(cropSide) * 0.26
let mask = bitmap(cropSide)
let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: cropSide, height: cropSide),
                  cornerWidth: R, cornerHeight: R, transform: nil)
mask.addPath(path)
mask.clip()
mask.draw(cropped, in: CGRect(x: 0, y: 0, width: cropSide, height: cropSide))
guard let rounded = mask.makeImage() else { fatalError("遮罩失败") }

// 放到 1024 网格上，主体 840pt 居中（Apple 图标网格要求四周留呼吸空间）。
let canvas = 1024, side = 840
let out = bitmap(canvas)
out.draw(rounded, in: CGRect(x: (canvas - side) / 2, y: (canvas - side) / 2,
                             width: side, height: side))
guard let final = out.makeImage() else { fatalError("合成失败") }
let rep = NSBitmapImageRep(cgImage: final)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("主体裁切 \(cropSide)pt，圆角半径 \(Int(R))，画布 \(canvas)")
SWIFT

DEVELOPER_DIR=/Library/Developer/CommandLineTools swift "$WORK/mask.swift" "$SRC" "$WORK/base.png"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" -s format png "$WORK/base.png" --out "$WORK/raw_$size.png" >/dev/null
done
cp "$WORK/raw_16.png"   "$SET/icon_16x16.png"
cp "$WORK/raw_32.png"   "$SET/icon_16x16@2x.png"
cp "$WORK/raw_32.png"   "$SET/icon_32x32.png"
cp "$WORK/raw_64.png"   "$SET/icon_32x32@2x.png"
cp "$WORK/raw_128.png"  "$SET/icon_128x128.png"
cp "$WORK/raw_256.png"  "$SET/icon_128x128@2x.png"
cp "$WORK/raw_256.png"  "$SET/icon_256x256.png"
cp "$WORK/raw_512.png"  "$SET/icon_256x256@2x.png"
cp "$WORK/raw_512.png"  "$SET/icon_512x512.png"
cp "$WORK/raw_1024.png" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$OUT"
cp "$WORK/base.png" Resources/AppIcon-source.png
echo "==> $OUT（$(du -h "$OUT" | cut -f1)），网格图已存 Resources/AppIcon-source.png"
