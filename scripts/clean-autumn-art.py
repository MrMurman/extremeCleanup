#!/usr/bin/env python3
"""Prepare the generated autumn art for the game.

The generated realistic PNGs carry a faint alpha haze across the frame and a soft glow band
around every leaf, and their bodies sit just below full opacity. This tightens each edge, drops
the haze, makes bodies opaque, bleeds edge colour into transparent pixels (so linear filtering
draws no dark or light fringe), and halves the leaf and pile sheets, which the game draws far
below their native 512 px. Retro pixel art only loses its haze and loose specks and gets opaque bodies:
its edges are drawn crisp, so they are left exactly as they are.

    scripts/clean-autumn-art.py <source-dir> Support/assets

<source-dir> holds the original generated sheets in assets/ and their atlas.json (the originals are
not in this repo). Always run it from the originals, never on its own output: the sheets would be
halved again.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

EDGE_LO, EDGE_HI = 16, 240   # alpha below LO is haze, above HI is body
MIN_SPECK = 400              # opaque islands smaller than this (px) are haze, not art
HALVED = ("leaves", "pile")  # branches stay native: the canopy draws them near 1:1


def drop_specks(a):
    labels, n = ndimage.label(a > 0)
    sizes = ndimage.sum(np.ones_like(a), labels, range(1, n + 1))
    a[np.isin(labels, np.flatnonzero(sizes < MIN_SPECK) + 1)] = 0
    return a


def despeck(img: Image.Image) -> Image.Image:
    px = np.asarray(img.convert("RGBA")).copy()
    a = px[..., 3].astype(np.float32)
    a[a < EDGE_LO] = 0
    a[a > EDGE_HI] = 255
    px[..., 3] = drop_specks(a).astype(np.uint8)
    return Image.fromarray(px, "RGBA")


def clean(img: Image.Image) -> Image.Image:
    px = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb, a = px[..., :3], px[..., 3]

    a = drop_specks(np.clip((a - EDGE_LO) / (EDGE_HI - EDGE_LO), 0, 1) * 255)

    solid = a >= 128
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    rgb = rgb[iy, ix]

    return Image.fromarray(np.dstack([rgb, a]).round().astype(np.uint8), "RGBA")


def halve(img: Image.Image) -> Image.Image:
    # Resize premultiplied so transparent pixels don't bleed colour into the edge.
    pm = np.asarray(img).astype(np.float32)
    pm[..., :3] *= pm[..., 3:] / 255
    small = Image.fromarray(pm.round().astype(np.uint8), "RGBA").resize(
        (img.width // 2, img.height // 2), Image.LANCZOS)
    out = np.asarray(small).astype(np.float32)
    alpha = np.maximum(out[..., 3:], 1)
    out[..., :3] = np.clip(out[..., :3] * 255 / alpha, 0, 255)
    return Image.fromarray(out.round().astype(np.uint8), "RGBA")


def scaled(frames):
    return [{k: v // 2 for k, v in f.items()} for f in frames]


def main(source: Path, dst: Path):
    atlas = json.loads((source / "atlas.json").read_text())
    dst.mkdir(parents=True, exist_ok=True)
    for style in atlas["styles"].values():
        for key in ("leaves", "branches", "pile"):
            name = Path(style[key]).name
            src = source / "assets" / name
            if style["filter"] == "nearest":
                despeck(Image.open(src)).save(dst / name, optimize=True)
                continue
            img = clean(Image.open(src))
            if key in HALVED:
                img = halve(img)
            img.save(dst / name, optimize=True)
        if style["filter"] != "nearest":
            style["atlasSize"] = [v // 2 for v in style["atlasSize"]]
            style["frames"] = scaled(style["frames"])
            style["pileAtlasSize"] = [v // 2 for v in style["pileAtlasSize"]]
            style["pileFrames"] = scaled(style["pileFrames"])
    (dst / "atlas.json").write_text(json.dumps(atlas, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
