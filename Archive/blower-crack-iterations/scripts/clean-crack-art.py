#!/usr/bin/env python3
"""Prepare the generated crack art for the game.

The generated impact PNGs have bright cracks on a pure black background. This crushes black
to zero alpha (so additive blend in SpriteKit shows only the cracks), strips metadata, and
copies them into Support/assets/ at their native 1254×1254 resolution — the blower's big
crack draws them about 460 pt across, so the detail survives downscaling.

    scripts/clean-crack-art.py <art-kit-dir> Support/assets

<art-kit-dir> holds the original generated images (not in this repo). Always run it from the
originals, never on its own output.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BLACK_THRESHOLD = 8  # RGB below this in all channels becomes transparent


def clean(img: Image.Image) -> Image.Image:
    """Crush black to zero alpha, keep everything else as-is."""
    px = np.asarray(img.convert("RGB")).astype(np.float32)
    # Black anywhere there's no bright crack
    is_black = np.all(px <= BLACK_THRESHOLD, axis=-1)
    a = np.where(is_black, 0, 255).astype(np.uint8)
    # Keep the RGB as-is for the bright parts
    rgba = np.dstack([px.astype(np.uint8), a])
    return Image.fromarray(rgba, "RGBA")


def main(source: Path, dst: Path):
    if not source.exists():
        sys.exit(f"Source directory not found: {source}")

    dst.mkdir(parents=True, exist_ok=True)

    # Process all crack images
    for name in ["lvl1-impact.png", "lvl2-impact.png", "lvl3-impact.png", "thin-fissure.png"]:
        src = source / name
        if not src.exists():
            print(f"Skipping {name} (not found)")
            continue

        img = Image.open(src)
        clean(img).save(dst / name, optimize=True)
        print(f"Processed {name} → {dst / name}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
