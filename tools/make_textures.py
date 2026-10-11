#!/usr/bin/env python3
"""Generate SuuUI's texture assets into Media/Textures. Standard library only.

    python3 tools/make_textures.py

Soft.tga (64x64, white): a solid 32x32 core with a Gaussian falloff to the
edges, sliced as a 3x3 grid (16px corners). UI/Draw.lua stretches it around a
frame to draw the design's glows (glow-arcane, glow-ember, glow-ward) and the
panel shadow, tinted by vertex colour.

Hatch.tga (16x16): the absorb hatch. RoleTank/RoleHealer/RoleDamage.tga
(32x32): the role icons before a unit's name.
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


# --- Hatch.tga: the absorb pattern, white diagonal stripes 4px on, 4px off;
# tiles seamlessly at 16px. Tinted ward-absorb in game.

def hatch_alpha(x, y):
    return 255 if (x + y) % 8 < 4 else 0


# --- Role icons (32x32, white, antialiased by 4x4 supersampling): a shield
# for tanks, a cross for healers, a sword for damage. Drawn in ink in game.

def inside_polygon(px, py, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def raster(shapes, size=32, ss=4):
    """shapes: polygons in a 0..1 box. Returns an alpha function."""
    cache = {}
    for y in range(size):
        for x in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = (x + (sx + 0.5) / ss) / size
                    py = (y + (sy + 0.5) / ss) / size
                    if any(inside_polygon(px, py, poly) for poly in shapes):
                        hits += 1
            cache[(x, y)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


def shield():
    pts = [(0.5, 0.06), (0.86, 0.18), (0.84, 0.52)]
    # the curved lower half, as a polyline down to the point
    for i in range(1, 8):
        t = i / 8
        pts.append((0.84 - 0.34 * t, 0.52 + 0.42 * t * (1.2 - 0.2 * t)))
    pts.append((0.5, 0.95))
    left = [(1 - x, y) for (x, y) in reversed(pts[1:-1])]
    return [pts + left]


def cross():
    w = 0.13
    return [[(0.5 - w, 0.1), (0.5 + w, 0.1), (0.5 + w, 0.5 - w), (0.9, 0.5 - w), (0.9, 0.5 + w),
             (0.5 + w, 0.5 + w), (0.5 + w, 0.9), (0.5 - w, 0.9), (0.5 - w, 0.5 + w), (0.1, 0.5 + w),
             (0.1, 0.5 - w), (0.5 - w, 0.5 - w)]]


def sword():
    # blade from bottom-left to top-right, a crossguard and a grip
    def rect(cx, cy, length, width, angle):
        dx, dy = math.cos(angle), math.sin(angle)
        nx, ny = -dy, dx
        hl, hw = length / 2, width / 2
        return [(cx - dx * hl - nx * hw, cy - dy * hl - ny * hw), (cx + dx * hl - nx * hw, cy + dy * hl - ny * hw),
                (cx + dx * hl + nx * hw, cy + dy * hl + ny * hw), (cx - dx * hl + nx * hw, cy - dy * hl + ny * hw)]
    a = -math.pi / 4
    blade = rect(0.58, 0.42, 0.72, 0.13, a)
    tip = [(0.88, 0.12), (0.80, 0.11), (0.89, 0.20)]
    guard = rect(0.30, 0.70, 0.36, 0.09, a + math.pi / 2)
    grip = rect(0.2, 0.8, 0.2, 0.09, a)
    return [blade, tip, guard, grip]


def main():
    os.makedirs(OUT, exist_ok=True)
    root = os.path.dirname(HERE)
    jobs = [
        ("Soft.tga", SIZE, lambda x, y: (255, 255, 255, round(255 * soft_alpha(x, y)))),
        ("Hatch.tga", 16, lambda x, y: (255, 255, 255, hatch_alpha(x, y))),
        ("RoleTank.tga", 32, raster(shield())),
        ("RoleHealer.tga", 32, raster(cross())),
        ("RoleDamage.tga", 32, raster(sword())),
    ]
    for name, size, pixel in jobs:
        path = os.path.join(OUT, name)
        write_tga(path, size, size, pixel)
        print("wrote", os.path.relpath(path, root))


if __name__ == "__main__":
    main()
