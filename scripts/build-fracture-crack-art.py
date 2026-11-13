#!/usr/bin/env python3
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageOps


def enhanced_alpha(image, multiplier):
    return image.point(lambda value: min(255, round(value * multiplier)))


def save_fracture(source, alpha, destination):
    result = source.convert("RGBA")
    result.putalpha(enhanced_alpha(alpha, 1.25))
    result.save(destination)


def angular_distance(a, b):
    return abs((a - b + math.pi) % (2 * math.pi) - math.pi)


def light_selection(x, y, cx, cy, stage):
    dx = x - cx
    dy = y - cy
    radius = math.hypot(dx, dy)
    angle = math.atan2(dy, dx)

    if stage == 1:
        directions = [(-0.04, 0.12, 1.0), (2.18, 0.15, 0.9)]
        selected = 0.0
    elif stage == 2:
        directions = [
            (-0.04, 0.15, 1.0),
            (2.18, 0.18, 0.95),
            (-1.55, 0.14, 0.9),
            (-0.82, 0.13, 0.8),
            (0.88, 0.15, 0.9),
            (-2.5, 0.13, 0.75),
        ]
        selected = 0.0
    else:
        variation = 0.5 + 0.5 * math.sin(angle * 7 + radius * 0.018)
        selected = 0.58 + 0.34 * variation
        directions = []

    for direction, width, strength in directions:
        distance = angular_distance(angle, direction)
        if distance < width:
            selected = max(selected, strength * (1 - 0.25 * distance / width))

    centre_light = max(0.0, 1.0 - radius / 72.0)
    selected = max(selected, centre_light)
    if stage > 1 and radius < 72.0:
        centre_attenuation = 0.18 if stage == 2 else 0.3
        selected *= centre_attenuation + (1.0 - centre_attenuation) * radius / 72.0
    distance_fade = max(0.58, 1.0 - radius / 1800.0)
    return min(1.0, selected * distance_fade)


def save_light(source, stage, destination):
    width, height = source.size
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    sharp = Image.new("RGBA", source.size)
    output = sharp.load()
    pixels = source.load()

    for y in range(height):
        for x in range(width):
            luminance = pixels[x, y]
            if luminance < 2:
                continue
            selection = light_selection(x, y, cx, cy, stage)
            if selection < 0.015:
                continue
            heat = selection * (0.35 + 0.65 * luminance / 255.0)
            red = 255
            green = round(25 + 76 * heat)
            blue = round(8 + 13 * heat)
            alpha = min(255, round(luminance * selection * 1.35))
            output[x, y] = (red, green, blue, alpha)

    glow = sharp.filter(ImageFilter.GaussianBlur(14))
    glow.putalpha(glow.getchannel("A").point(lambda value: min(255, round(value * 1.3))))
    Image.alpha_composite(glow, sharp).save(destination)


def split_outer_cracks(luminance, fraction=0.65):
    width, height = luminance.size
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    pixels = luminance.load()
    bin_count = 2048
    endpoints = [0.0] * bin_count

    for y in range(height):
        for x in range(width):
            if pixels[x, y] < 8:
                continue
            dx = x - cx
            dy = y - cy
            radius = math.hypot(dx, dy)
            if radius < 24:
                continue
            index = int((math.atan2(dy, dx) + math.pi) / math.tau * bin_count) % bin_count
            endpoints[index] = max(endpoints[index], radius)

    endpoints = [
        max(endpoints[(index + offset) % bin_count] for offset in range(-2, 3))
        for index in range(bin_count)
    ]
    core = Image.new("L", luminance.size)
    core_pixels = core.load()

    for y in range(height):
        for x in range(width):
            value = pixels[x, y]
            if value == 0:
                continue
            dx = x - cx
            dy = y - cy
            radius = math.hypot(dx, dy)
            index = int((math.atan2(dy, dx) + math.pi) / math.tau * bin_count) % bin_count
            limit = max(32.0, endpoints[index] * fraction)
            tip = min(1.0, max(0.0, (limit - radius) / 24.0))
            core_pixels[x, y] = round(value * tip)

    return core, ImageChops.subtract(luminance, core)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: build-fracture-crack-art.py <art-kit-directory>")

    source_dir = Path(sys.argv[1])
    output_dir = Path(__file__).resolve().parent.parent / "Support" / "assets"
    sources = []
    luminance = []

    for level in (1, 2, 3):
        source = Image.open(source_dir / f"lvl{level}-impact.png").convert("RGB")
        if source.size != (1254, 1254):
            raise ValueError(f"lvl{level}-impact.png must be 1254x1254, got {source.size}")
        sources.append(source)
        luminance.append(ImageOps.grayscale(source))

    core, extension = split_outer_cracks(luminance[0])
    save_fracture(sources[0], core, output_dir / "lvl1-fracture-core.png")
    save_fracture(sources[0], extension, output_dir / "lvl1-fracture-extension.png")
    save_light(core, 1, output_dir / "lvl1-fracture-core-glow.png")

    save_fracture(sources[0], luminance[0], output_dir / "lvl1-fracture.png")
    save_fracture(
        sources[1],
        ImageChops.subtract(luminance[1], luminance[0]),
        output_dir / "lvl2-fracture.png",
    )
    save_fracture(
        sources[2],
        ImageChops.subtract(luminance[2], luminance[1]),
        output_dir / "lvl3-fracture.png",
    )

    for level, source_luminance in enumerate(luminance, start=1):
        save_light(source_luminance, level, output_dir / f"lvl{level}-fracture-glow.png")

    for level in (1, 2, 3):
        for suffix in ("fracture.png", "fracture-glow.png"):
            print(output_dir / f"lvl{level}-{suffix}")


if __name__ == "__main__":
    main()
