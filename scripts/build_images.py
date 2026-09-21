#!/usr/bin/env python3
"""Turn the README screenshots into the web copies the landing page ships.

The PNGs under docs/screenshots are lossless captures with rounded, transparent
corners — right for GitHub, far too heavy for a page whose largest one is the
LCP element. This writes WebP at the sizes the layout actually uses, flattened
onto the background colour of the section each one sits in so the rounded
corners keep blending into the page instead of showing a grey fringe.

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

# (source, output, target width, background of the section it sits in, quality)
# The backgrounds mirror --bg / --bg-alt in site/app.css.
JOBS = [
    ("panel.png", "panel.webp", 688, "#0a0a0c", 92),
    ("settings-about.png", "settings.webp", 1400, "#0d0d12", 88),
]


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    for name, out_name, width, background, quality in JOBS:
        source = SRC / name
        if not source.exists():
            print(f"missing source: {source}", file=sys.stderr)
            return 1

        image = Image.open(source).convert("RGBA")
        if image.width != width:
            height = round(image.height * width / image.width)
            image = image.resize((width, height), Image.LANCZOS)

        # Composite rather than convert: a straight RGB conversion drops alpha
        # onto black, which shows as dark teeth around the rounded corners.
        canvas = Image.new("RGB", image.size, hex_to_rgb(background))
        canvas.paste(image, (0, 0), image)

        target = OUT / out_name
        canvas.save(target, "WEBP", quality=quality, method=6)
        kib = target.stat().st_size / 1024
        print(f"{out_name:16} {canvas.width}x{canvas.height}  {kib:6.1f} KiB")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
