#!/usr/bin/env python3
"""Draw Spark's app icon: an amber bolt on a dark graphite tile.

Usage: python3 make_spark_icon.py <output.png>
Needs Pillow. The output is an opaque 1024 x 1024 RGB PNG.
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2  # supersample, then shrink, for smooth edges
ACCENT = (255, 182, 39)
BOLT = [(60, 6), (22, 56), (46, 56), (38, 94), (78, 42), (53, 42)]
FACET = [(60, 6), (22, 56), (46, 56), (53, 42)]


def radial(size, centre, radius, inner, outer):
    """Opaque radial gradient from `inner` at `centre` to `outer` at `radius`."""
    mask = Image.radial_gradient("L").resize((radius * 2, radius * 2))
    falloff = Image.new("L", (size, size), 255)
    falloff.paste(mask, (centre[0] - radius, centre[1] - radius))
    return Image.composite(Image.new("RGB", (size, size), outer),
                           Image.new("RGB", (size, size), inner), falloff)


def points(shape, size, offset=(0, 0)):
    unit = size * 0.69 / 100
    origin = size / 2 - 50 * unit
    return [(origin + x * unit + offset[0], origin + y * unit + offset[1]) for x, y in shape]


def main(output):
    size = SIZE * SCALE
    icon = radial(size, (int(size * 0.3), 0), int(size * 1.1), (43, 48, 62), (11, 13, 18))

    warmth = radial(size, (size // 2, int(size * 0.52)), int(size * 0.48), ACCENT, (0, 0, 0))
    icon = ImageChops.add(icon, warmth.point(lambda value: value * 0.10))

    shadow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow).polygon(points(BOLT, size, (0, size * 0.022)), fill=115)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.018))
    icon = Image.composite(Image.new("RGB", (size, size), (0, 0, 0)), icon, shadow)

    draw = ImageDraw.Draw(icon)
    draw.polygon(points(BOLT, size), fill=ACCENT)
    lighter = tuple(round(channel + (255 - channel) * 0.30) for channel in ACCENT)
    draw.polygon(points(FACET, size), fill=lighter)

    icon.resize((SIZE, SIZE), Image.LANCZOS).save(output, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
