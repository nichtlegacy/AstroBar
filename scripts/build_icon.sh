#!/usr/bin/env bash
# Render the AstroBar app icon into Sources/AstroBar/Resources/AppIcon.icns.
#
# Design: modern macOS-style icon --
#   * squircle (continuous-corner approximation, radius 22.37%) inset ~8% on a
#     transparent 1024px canvas
#   * diagonal gradient: deep night indigo (bottom) -> astro blue -> cyan (top-left)
#   * subtle inner top hairline highlight + faint bottom edge shading for depth
#   * minimal geometric over-ear headset glyph (capsule band stroke + capsule ear
#     cups), drawn purely with CoreGraphics (no SF Symbols)
#   * small glowing status dot bottom-right as signature detail
#
# Everything is rendered via CGContext into an NSBitmapImageRep (sRGB, alpha);
# NSImage.lockFocus() is intentionally NOT used (deprecated).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/astrobar-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/makeicon.swift" <<'SWIFT'
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments[1]

// ---- canvas / squircle ------------------------------------------------------
let S: CGFloat = 1024
let inset: CGFloat = 80                              // ~8% transparent border
let bodyRect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let bodyRadius = bodyRect.width * 0.2237             // continuous-corner ratio
let body = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    let colors: [CGColor] = stops.map { $0.1 }
    let locations: [CGFloat] = stops.map { $0.0 }
    return CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high

// ---- background: diagonal night-indigo -> astro-blue -> cyan ----------------
ctx.saveGState()
ctx.addPath(body)
ctx.clip()

let bg = grad([
    (0.00, col(0.063, 0.110, 0.247)),   // #101C3F deep night indigo (bottom)
    (0.52, col(0.118, 0.482, 0.839)),   // #1E7BD6 astro blue
    (1.00, col(0.208, 0.769, 0.910)),   // #35C4E8 cyan accent (top-left)
])
ctx.drawLinearGradient(bg,
                       start: CGPoint(x: 748, y: 108),
                       end: CGPoint(x: 268, y: 800),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// subtle deep-blue backlight behind the glyph (adds depth + contrast)
let backlight = grad([
    (0.00, col(0.039, 0.078, 0.188, 0.34)),
    (1.00, col(0.039, 0.078, 0.188, 0.0)),
])
ctx.drawRadialGradient(backlight,
                       startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 440,
                       options: [.drawsAfterEndLocation])

// faint light bloom top-left: the gradient reads as lit from the upper left
let bloom = grad([
    (0.00, col(0.596, 0.898, 0.980, 0.12)),
    (1.00, col(0.596, 0.898, 0.980, 0.0)),
])
ctx.drawRadialGradient(bloom,
                       startCenter: CGPoint(x: 340, y: 745), startRadius: 0,
                       endCenter: CGPoint(x: 340, y: 745), endRadius: 470,
                       options: [.drawsAfterEndLocation])

// hairline inner highlight along the top edge (fades out towards the middle)
ctx.saveGState()
ctx.setLineWidth(4)
ctx.addPath(body)
ctx.replacePathWithStrokedPath()
ctx.clip()
let topEdge = grad([
    (0.00, col(1, 1, 1, 0.0)),
    (1.00, col(1, 1, 1, 0.55)),
])
ctx.drawLinearGradient(topEdge,
                       start: CGPoint(x: 512, y: bodyRect.midY),
                       end: CGPoint(x: 512, y: bodyRect.maxY),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// faint inner shading along the bottom edge (grounds the icon)
ctx.saveGState()
ctx.setLineWidth(6)
ctx.addPath(body)
ctx.replacePathWithStrokedPath()
ctx.clip()
let bottomEdge = grad([
    (0.00, col(0.031, 0.055, 0.145, 0.0)),
    (1.00, col(0.031, 0.055, 0.145, 0.22)),
])
ctx.drawLinearGradient(bottomEdge,
                       start: CGPoint(x: 512, y: bodyRect.midY),
                       end: CGPoint(x: 512, y: bodyRect.minY),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

ctx.restoreGState() // end body clip

// ---- headset glyph ----------------------------------------------------------
// Over-ear headset: capsule band (thick round-capped arc) + two capsule cups.
// Glyph occupies ~55% of the tile width, optically centered.
let cx: CGFloat = 512
let bandCY: CGFloat = 525          // arc pivot
let bandR: CGFloat = 166           // arc reaches cup centers
let bandW: CGFloat = 60            // capsule stroke thickness
let cupDX: CGFloat = 166           // cup center distance from cx
let cupW: CGFloat = 144
let cupH: CGFloat = 304
let cupCY: CGFloat = 455           // cups hang below the band ends

let a0 = 200.0 * Double.pi / 180
let a1 = -20.0 * Double.pi / 180
let band = CGMutablePath()
band.move(to: CGPoint(x: cx + bandR * CGFloat(cos(a0)), y: bandCY + bandR * CGFloat(sin(a0))))
band.addArc(center: CGPoint(x: cx, y: bandCY), radius: bandR,
            startAngle: CGFloat(a0), endAngle: CGFloat(a1), clockwise: true)

func cupPath(_ dx: CGFloat) -> CGPath {
    let x: CGFloat = cx + dx - cupW / 2
    let y: CGFloat = cupCY - cupH / 2
    let r: CGFloat = cupW / 2
    let rect = CGRect(x: x, y: y, width: cupW, height: cupH)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// soft material gradient: pure white -> faint blue tint at the bottom
let glyphTop = CGPoint(x: cx, y: bandCY + bandR + bandW / 2)
let glyphBottom = CGPoint(x: cx, y: cupCY - cupH / 2)
let glyphGrad = grad([
    (0.00, col(1.0, 1.0, 1.0)),
    (1.00, col(0.886, 0.933, 0.984)),
])

func fillGlyphPath(_ path: CGPath, stroke: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    if stroke > 0 {
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath()
    }
    ctx.clip()
    ctx.drawLinearGradient(glyphGrad, start: glyphTop, end: glyphBottom,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// one unified soft shadow for the whole glyph (transparency layer)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 44,
              color: col(0.012, 0.047, 0.137, 0.38))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
fillGlyphPath(band, stroke: bandW)
fillGlyphPath(cupPath(-cupDX), stroke: 0)
fillGlyphPath(cupPath(cupDX), stroke: 0)
ctx.endTransparencyLayer()
ctx.restoreGState()

// ---- signature detail: small glowing status LED dot under the right cup -----
let dotC = CGPoint(x: cx + cupDX, y: 218)
let dotGlow = grad([
    (0.00, col(0.949, 0.992, 1.0, 0.95)),
    (0.24, col(0.208, 0.769, 0.910, 0.55)),
    (1.00, col(0.208, 0.769, 0.910, 0.0)),
])
ctx.drawRadialGradient(dotGlow,
                       startCenter: dotC, startRadius: 0,
                       endCenter: dotC, endRadius: 68,
                       options: [.drawsAfterEndLocation])
ctx.setFillColor(col(0.949, 0.992, 1.0, 1))
ctx.fillEllipse(in: CGRect(x: dotC.x - 12, y: dotC.y - 12, width: 24, height: 24))

// ---- export ------------------------------------------------------------------
let cgimg = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: cgimg)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$WORK/makeicon.swift" "$WORK/icon_1024.png"

# ---- full .iconset (sips downscale from the 1024 master) ---------------------
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" "$WORK/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    d=$((sz * 2))
    sips -z "$d" "$d" "$WORK/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
# exact 1024 master for icon_512x512@2x (no resample)
cp "$WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

# ---- icns + preview -----------------------------------------------------------
iconutil -c icns "$ICONSET" -o "$ROOT/Sources/AstroBar/Resources/AppIcon.icns"

mkdir -p "$ROOT/tmp"
sips -z 512 512 "$WORK/icon_1024.png" --out "$ROOT/tmp/icon_preview.png" >/dev/null

echo "✓ Wrote Sources/AstroBar/Resources/AppIcon.icns ($(du -h "$ROOT/Sources/AstroBar/Resources/AppIcon.icns" | cut -f1 | tr -d ' '))"
echo "✓ Wrote tmp/icon_preview.png"
