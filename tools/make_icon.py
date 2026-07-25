#!/usr/bin/env python3
"""
App icon generator for Chroma Cascade.

There is no imaging library in this toolchain, so this renders the icon from
first principles — signed-distance rounded rectangles with analytic
anti-aliasing, composited over a gradient — and writes the PNGs with a minimal
zlib-backed encoder.

    python3 tools/make_icon.py

Produces every size the iPhone asset catalogue needs plus the 1024 marketing
icon, all opaque RGB (App Store icons may not carry an alpha channel).
"""

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "ChromaCascade", "Resources", "Assets.xcassets", "AppIcon.appiconset")

MASTER = 1024

BG_TOP = (0x24, 0x0A, 0x47)
BG_BOTTOM = (0x07, 0x03, 0x12)

# Same palette as Theme.swift.
BLOCKS = [
    ((0, 0), (0x00, 0xE5, 0xFF)),   # cyan
    ((0, 1), (0xFF, 0x2D, 0x95)),   # magenta
    ((1, 0), (0x9B, 0xFF, 0x3C)),   # lime
    ((1, 1), (0xFF, 0xB0, 0x20)),   # amber
]


# ---------------------------------------------------------------- png writer

def write_png(path, width, height, pixels):
    """`pixels` is a bytearray of width*height*3 bytes, top row first."""
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


# ---------------------------------------------------------------- rendering

def rounded_rect_distance(px, py, cx, cy, half, radius):
    """Signed distance to a rounded rect; negative inside."""
    dx = abs(px - cx) - (half - radius)
    dy = abs(py - cy) - (half - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def render_master():
    size = MASTER
    pixels = bytearray(size * size * 3)

    # Background: a vertical gradient, built one constant-colour row at a time.
    for y in range(size):
        t = y / (size - 1.0)
        eased = t * t * (3 - 2 * t)
        row = bytes((
            int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * eased),
            int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * eased),
            int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * eased),
        )) * size
        pixels[y * size * 3:(y + 1) * size * 3] = row

    block = size * 0.325
    gap = size * 0.060
    half = block / 2.0
    radius = block * 0.26
    span = block * 2 + gap
    origin = (size - span) / 2.0 + half

    for (row_index, col_index), color in BLOCKS:
        cx = origin + col_index * (block + gap)
        cy = origin + row_index * (block + gap)

        # Glow falls off exponentially; reach six radii out so it has decayed
        # to nothing by the edge of the box (a tighter box leaves a visible
        # square seam where the glow is clipped).
        glow_radius = block * 0.095
        reach = int(half + glow_radius * 7)
        x0 = max(0, int(cx) - reach)
        x1 = min(size - 1, int(cx) + reach)
        y0 = max(0, int(cy) - reach)
        y1 = min(size - 1, int(cy) + reach)

        highlight_top = cy - half + block * 0.16
        highlight_bottom = cy - half + block * 0.34

        for y in range(y0, y1 + 1):
            base = y * size * 3
            for x in range(x0, x1 + 1):
                distance = rounded_rect_distance(x + 0.5, y + 0.5, cx, cy, half, radius)

                coverage = 0.0
                if distance < 1.0:
                    coverage = min(1.0, max(0.0, 0.5 - distance))

                glow = 0.0
                if distance > -2.0:
                    glow = math.exp(-max(distance, 0.0) / glow_radius) * 0.5

                if coverage <= 0.0 and glow <= 0.004:
                    continue

                # Face shading: brighter at the top-left, deeper at the bottom-right.
                shade = 0.48 + 0.55 * (1.0 - ((x - (cx - half)) + (y - (cy - half))) / (block * 2.0))
                shade = max(0.34, min(1.0, shade))

                red = color[0] * shade
                green = color[1] * shade
                blue = color[2] * shade

                # Rim light just inside the edge.
                if -radius * 0.30 < distance < 0.0:
                    rim = 1.0 - abs(distance) / (radius * 0.30)
                    red += (255 - red) * 0.38 * rim
                    green += (255 - green) * 0.38 * rim
                    blue += (255 - blue) * 0.38 * rim

                # Glass highlight bar near the top of the face.
                if coverage > 0 and highlight_top < y < highlight_bottom and abs(x - cx) < half - block * 0.22:
                    red += (255 - red) * 0.22
                    green += (255 - green) * 0.22
                    blue += (255 - blue) * 0.22

                index = base + x * 3
                for offset, value in enumerate((red, green, blue)):
                    current = pixels[index + offset]
                    # additive glow first, then the solid face on top
                    lit = current + color[offset] * glow
                    mixed = lit + (value - lit) * coverage
                    pixels[index + offset] = int(max(0, min(255, mixed)))

    return pixels


def downsample(master, target):
    """Box filter from the 1024 master down to `target` pixels."""
    if target == MASTER:
        return master
    out = bytearray(target * target * 3)
    ratio = MASTER / float(target)
    for y in range(target):
        sy0 = int(y * ratio)
        sy1 = max(sy0 + 1, int((y + 1) * ratio))
        for x in range(target):
            sx0 = int(x * ratio)
            sx1 = max(sx0 + 1, int((x + 1) * ratio))
            r = g = b = 0
            count = 0
            for sy in range(sy0, sy1):
                base = sy * MASTER * 3
                for sx in range(sx0, sx1):
                    index = base + sx * 3
                    r += master[index]
                    g += master[index + 1]
                    b += master[index + 2]
                    count += 1
            index = (y * target + x) * 3
            out[index] = r // count
            out[index + 1] = g // count
            out[index + 2] = b // count
    return out


SIZES = [40, 58, 60, 80, 87, 120, 180, 1024]

CONTENTS = """{
  "images" : [
    { "filename" : "icon-40.png", "idiom" : "iphone", "scale" : "2x", "size" : "20x20" },
    { "filename" : "icon-60.png", "idiom" : "iphone", "scale" : "3x", "size" : "20x20" },
    { "filename" : "icon-58.png", "idiom" : "iphone", "scale" : "2x", "size" : "29x29" },
    { "filename" : "icon-87.png", "idiom" : "iphone", "scale" : "3x", "size" : "29x29" },
    { "filename" : "icon-80.png", "idiom" : "iphone", "scale" : "2x", "size" : "40x40" },
    { "filename" : "icon-120.png", "idiom" : "iphone", "scale" : "3x", "size" : "40x40" },
    { "filename" : "icon-120.png", "idiom" : "iphone", "scale" : "2x", "size" : "60x60" },
    { "filename" : "icon-180.png", "idiom" : "iphone", "scale" : "3x", "size" : "60x60" },
    { "filename" : "icon-1024.png", "idiom" : "ios-marketing", "scale" : "1x", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    master = render_master()
    for size in SIZES:
        pixels = downsample(master, size)
        path = os.path.join(OUT_DIR, "icon-%d.png" % size)
        write_png(path, size, size, pixels)
        print("  icon-%-5d %6.1f KB" % (size, os.path.getsize(path) / 1024.0))
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as handle:
        handle.write(CONTENTS)
    print("wrote %d icons into %s" % (len(SIZES), OUT_DIR))


if __name__ == "__main__":
    main()
