#!/usr/bin/env python3
"""Render site/og.png, the 1200x630 social preview for the landing page.

Same palette and type as the page: off-black canvas, one blue wash in the top
right, the app icon, and the real panel capture bleeding off the bottom edge.
Run it again whenever the panel screenshot or the wording changes.

    scripts/build_og.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "docs" / "screenshots" / "panel.png"
ICON = ROOT / "site" / "app-icon.png"
OUT = ROOT / "site" / "og.png"

W, H = 1200, 630
BG = (10, 10, 12)
INK = (243, 243, 246)
INK_2 = (155, 155, 168)
INK_3 = (107, 107, 120)
ACCENT = (10, 132, 255)

# SFNS is a variable font; the named instance is picked per size below. The
# Helvetica fallback keeps the script working off a stock macOS too.
SANS = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
SANS_FALLBACK = "/System/Library/Fonts/HelveticaNeue.ttc"
MONO_FALLBACK = "/System/Library/Fonts/Menlo.ttc"


def font(path: str, size: int, weight: str | None = None, fallback: str = SANS_FALLBACK):
    try:
        f = ImageFont.truetype(path, size)
    except OSError:
        try:
            return ImageFont.truetype(fallback, size)
        except OSError:
            return ImageFont.load_default(size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except (OSError, AttributeError):
            pass
    return f


def radial(size: tuple[int, int], center: tuple[int, int], radius: int,
           color: tuple[int, int, int], alpha: int) -> Image.Image:
    """One soft circular wash, drawn as concentric rings rather than blurred:
    a Gaussian blur of this radius costs more than the whole rest of the file."""
    layer = Image.new("RGBA", size, (*color, 0))
    draw = ImageDraw.Draw(layer)
    steps = 56
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (1 - i / steps) ** 2.2)
        draw.ellipse(
            (center[0] - r, center[1] - r, center[0] + r, center[1] + r),
            fill=(*color, a),
        )
    return layer


def main() -> int:
    for path in (PANEL, ICON):
        if not path.exists():
            print(f"missing: {path}", file=sys.stderr)
            return 1

    canvas = Image.new("RGB", (W, H), BG)
    canvas = Image.alpha_composite(
        canvas.convert("RGBA"),
        radial((W, H), (1010, 70), 620, ACCENT, 66),
    )
    canvas = Image.alpha_composite(
        canvas, radial((W, H), (1160, 330), 430, (53, 196, 232), 26)
    )
    draw = ImageDraw.Draw(canvas)

    # --- panel capture, bleeding off the bottom edge -------------------------
    panel = Image.open(PANEL).convert("RGBA")
    pw = 302
    panel = panel.resize((pw, round(panel.height * pw / panel.width)), Image.LANCZOS)
    canvas.alpha_composite(panel, (832, 92))

    # --- app icon ------------------------------------------------------------
    icon = Image.open(ICON).convert("RGBA")
    icon = icon.resize((104, 104), Image.LANCZOS)
    canvas.alpha_composite(icon, (64, 62))

    # --- copy ----------------------------------------------------------------
    draw.text((80, 186), "AstroBar", font=font(SANS, 34, "Semibold"), fill=INK_2)

    head = font(SANS, 62, "Semibold")
    draw.text((78, 238), "Astro A50 Gen 4,", font=head, fill=INK)
    draw.text((78, 312), "from the Mac menu bar.", font=head, fill=INK)

    draw.text(
        (80, 412),
        "Battery  ·  Equalizer  ·  Mix  ·  Microphone",
        font=font(SANS, 27),
        fill=INK_2,
    )

    draw.line((80, 506, 700, 506), fill=(255, 255, 255, 28), width=1)
    draw.text(
        (80, 526),
        "astrobar.nichtlegacy.com   ·   macOS 14+   ·   MIT",
        font=font(MONO, 22, fallback=MONO_FALLBACK),
        fill=INK_3,
    )

    canvas.convert("RGB").save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)}  {OUT.stat().st_size / 1024:.0f} KiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
