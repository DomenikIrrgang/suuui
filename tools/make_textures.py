#!/usr/bin/env python3
"""Generate SuuUI's texture assets into Media/Textures. Standard library only.

    python3 tools/make_textures.py

Soft.tga (64x64, white): a solid 32x32 core with a Gaussian falloff to the
edges, sliced as a 3x3 grid (16px corners). UI/Draw.lua stretches it around a
frame to draw the design's glows (glow-arcane, glow-ember, glow-ward) and the
panel shadow, tinted by vertex colour.
"""

import math
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Media", "Textures")

SIZE, MARGIN = 64, 16
SIGMA = MARGIN / 3.0  # the falloff reaches ~1% at the texture edge


def soft_alpha(x, y):
    """1 inside the core, then a Gaussian falloff with the distance to it."""
    cx = min(max(x + 0.5, MARGIN), SIZE - MARGIN)
    cy = min(max(y + 0.5, MARGIN), SIZE - MARGIN)
    d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
    return math.exp(-(d * d) / (2 * SIGMA * SIGMA))


def write_tga(path, width, height, pixel):
    """Uncompressed 32-bit BGRA, top-left origin."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    rows = bytearray()
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixel(x, y)
            rows += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + bytes(rows))


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "Soft.tga")
    write_tga(path, SIZE, SIZE, lambda x, y: (255, 255, 255, round(255 * soft_alpha(x, y))))
    print("wrote", os.path.relpath(path, os.path.dirname(HERE)))


if __name__ == "__main__":
    main()
