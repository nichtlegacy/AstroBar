#!/usr/bin/env python3
"""Turn the README screenshots into the web copies the landing page ships.

The PNGs under docs/screenshots are lossless captures — right for GitHub, far
too heavy for a page whose largest one is the LCP element. This writes WebP at
the sizes the layout actually uses.

The hero panel keeps its alpha: it hangs inside the page's drawn Mac screen,
over a gradient, so no flat colour would match, and the capture already has
transparent rounded corners. The settings window is flattened onto the page
background so its corners keep blending in.

The feature tiles reuse slices of the panel capture, so they always show the
panel exactly as the hero does. The slices stay inside the panel's border, so
the page can round their corners itself instead of inheriting a cut edge.

Running this locally and committing the result keeps the Pages build free of
image tooling; scripts/build_site.sh only copies what is already here.

    scripts/build_images.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "screenshots"
OUT = ROOT / "site" / "screenshots"

BG_PAGE = (10, 10, 12)  # --bg in site/app.css

# source, output, target width, background (None = keep alpha), crop box, quality
JOBS = [
    ("panel.png", "panel.webp", 688, None, None, 90),
    ("panel.png", "panel-status.webp", 676, None, (6, 6, 682, 512), 88),
    ("panel.png", "panel-controls.webp", 676, None, (6, 520, 682, 1222), 88),
    ("settings-about.png", "settings.webp", 1400, BG_PAGE, None, 86),
]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0

    for name, out_name, width, background, crop, quality in JOBS:
        source = SRC / name
        if not source.exists():
            print(f"missing source: {source}", file=sys.stderr)
            return 1

        image = Image.open(source).convert("RGBA")
        if crop is not None:
            image = image.crop(crop)
        if image.width > width:
            height = round(image.height * width / image.width)
            image = image.resize((width, height), Image.LANCZOS)

        if background is not None:
            # Composite rather than convert: a straight RGB conversion drops
            # alpha onto black, which shows as dark teeth around the corners.
            canvas = Image.new("RGB", image.size, background)
            canvas.paste(image, (0, 0), image)
            image = canvas

        target = OUT / out_name
        image.save(target, "WEBP", quality=quality, method=6)
        size = target.stat().st_size
        total += size
        print(f"{out_name:20} {image.width}x{image.height}  {size / 1024:6.1f} KiB")

    print(f"total {total / 1024:.1f} KiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
