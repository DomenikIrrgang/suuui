#!/usr/bin/env python3
"""Generate SuuUI's texture assets into Media/Textures. Standard library only.

    python3 tools/make_textures.py

Soft.tga (64x64, white): a solid 32x32 core with a Gaussian falloff to the
edges, sliced as a 3x3 grid (16px corners). UI/Draw.lua stretches it around a
frame to draw the design's glows (glow-arcane, glow-ember, glow-ward) and the
panel shadow, tinted by vertex colour.

Hatch.tga (16x16): the absorb hatch. RoleTank/RoleHealer/RoleDamage.tga
(32x32): the role icons before a unit's name.

Glyphs/<name>.tga (64x64, white): the design system's line glyphs (its Glyph
component: 24-unit SVG paths, stroke 1.9, round caps), stroked here by a
small path rasterizer (M L H V C S Q A Z, relative and absolute). Tinted in
game. Mark.tga (64x64, colour): the SuuUI mark (Docs/assets/suuui-mark.svg).

Circle textures (white, tinted in game): CircleFill.tga (64, a disc),
CircleEdge.tga (256, a ring 1/176 of the width at the edge: the minimap's 1px
gilt line at 176px; also the round buttons' edge), CircleBand.tga (256, the
inset-anchor's 3px dark band just inside the edge at 176px), CircleSoft.tga
(128, a disc fading out: round shadows and glows).

ChatDiamond.tga (32, white): the class chip as an inline texture in chat
lines (|T…|t, tinted by its colour arguments): a diamond half the height,
centred, so at the line's height it's the design's 5px square turned 45°.

LoadingMark.tga (128, colour): the SuuUI mark again at 128 for the design's
LoadingMark (60 px and up). LoadingFacet1-4.tga (128, white): one quarter of
the gem each (top-left, top-right, bottom-left, bottom-right), in the same
box as the mark, flashed over it in turn while it waits.

PlayerArrow.tga (64, colour): your arrow on the minimap, the design's
(Minimap: "M8 1.5l5 12.5-5-3-5 3z" on 16 units) in arcane with a dark rim
and a soft arcane glow; the engine draws it untinted.
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


# --- SVG paths: flattened into polylines ---------------------------------------

def _tokens(d):
    import re
    for m in re.finditer(r"[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?", d):
        yield m.group(0)


def _arc(x1, y1, rx, ry, phi, large, sweep, x2, y2, steps=24):
    """SVG elliptical arc (endpoint form) as points, without the start."""
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    phi = math.radians(phi)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0, num / den)) if den else 0
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    pts = []
    for i in range(1, steps + 1):
        t = t1 + dt * i / steps
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cp * x - sp * y + cx, sp * x + cp * y + cy))
    return pts


def path_polylines(d, steps=16):
    """An SVG path's subpaths as lists of points (curves flattened)."""
    toks = list(_tokens(d))
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    lastc = None
    lines, cur = [], []

    def num():
        nonlocal i
        v = float(toks[i]); i += 1
        return v
    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]; i += 1
            if cmd in "Zz":
                if cur:
                    cur.append(cur[0]); lines.append(cur); cur = []
                x, y = sx, sy
                lastc = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == "M":
            if cur:
                lines.append(cur)
            x, y = ox + num(), oy + num()
            sx, sy = x, y
            cur = [(x, y)]
            cmd = "l" if rel else "L"
            lastc = None
        elif c == "L":
            x, y = ox + num(), oy + num(); cur.append((x, y)); lastc = None
        elif c == "H":
            x = ox + num() if rel else num(); cur.append((x, y)); lastc = None
        elif c == "V":
            y = oy + num() if rel else num(); cur.append((x, y)); lastc = None
        elif c in "CS":
            if c == "C":
                x1, y1 = ox + num(), oy + num()
            else:
                x1, y1 = (2 * x - lastc[0], 2 * y - lastc[1]) if lastc else (x, y)
            x2, y2, ex, ey = ox + num(), oy + num(), ox + num(), oy + num()
            for k in range(1, steps + 1):
                t = k / steps
                mt = 1 - t
                cur.append((mt ** 3 * x + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t ** 3 * ex,
                            mt ** 3 * y + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t ** 3 * ey))
            lastc = (x2, y2)
            x, y = ex, ey
        elif c == "Q":
            x1, y1, ex, ey = ox + num(), oy + num(), ox + num(), oy + num()
            for k in range(1, steps + 1):
                t = k / steps
                mt = 1 - t
                cur.append((mt * mt * x + 2 * mt * t * x1 + t * t * ex, mt * mt * y + 2 * mt * t * y1 + t * t * ey))
            x, y = ex, ey
            lastc = None
        elif c == "A":
            rx, ry, phi, large, sweep = num(), num(), num(), num(), num()
            ex, ey = ox + num(), oy + num()
            cur.extend(_arc(x, y, rx, ry, phi, int(large), int(sweep), ex, ey))
            x, y = ex, ey
            lastc = None
        else:
            raise ValueError("unsupported path command " + cmd)
    if cur:
        lines.append(cur)
    return lines


def stroke_alpha(lines, width, box=24.0, size=64, ss=4):
    """Coverage of a stroke `width` (round caps and joins) along the lines,
    in a `box`-unit square drawn at `size` px; 4x4 supersampling."""
    segs = []
    for pts in lines:
        for a, b in zip(pts, pts[1:]):
            segs.append((a[0], a[1], b[0], b[1]))
        if len(pts) == 1:
            segs.append((pts[0][0], pts[0][1], pts[0][0], pts[0][1]))
    half = width / 2
    scale = box / size
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss) * scale
                    y = (py + (sy + 0.5) / ss) * scale
                    for (ax, ay, bx, by) in segs:
                        if x < min(ax, bx) - half or x > max(ax, bx) + half or y < min(ay, by) - half or y > max(ay, by) + half:
                            continue
                        vx, vy = bx - ax, by - ay
                        ll = vx * vx + vy * vy
                        t = 0 if ll == 0 else max(0, min(1, ((x - ax) * vx + (y - ay) * vy) / ll))
                        dx, dy = x - (ax + t * vx), y - (ay + t * vy)
                        if dx * dx + dy * dy <= half * half:
                            hits += 1
                            break
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


# The design system's glyphs SuuUI draws (bundle.js, Glyph: 24-unit, stroke 1.9)
GLYPHS = {
    "person": "M12 4a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zM5 20c1-4 4-6 7-6s6 2 7 6",
    "book": "M4 5h6a2 2 0 0 1 2 2v13a2 2 0 0 0-2-2H4zM20 5h-6a2 2 0 0 0-2 2v13a2 2 0 0 1 2-2h6z",
    "tree": "M12 20V10M12 10L6 5M12 10l6-5M12 14.5l-4-3M12 14.5l4-3",
    "scroll": "M7 4h11v13a3 3 0 0 1-3 3H6a3 3 0 0 1 0-6h1V4zM10 8h5M10 11h5",
    "people": "M9 5a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM3 20c.7-3.5 3-5 6-5s5.3 1.5 6 5M16 5.5a3 3 0 0 1 0 5.5M18 15c1.6.6 2.6 2.2 3 5",
    "map": "M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2V6zM9 4v14M15 6v14",
    "bag": "M6 8h12l-1 12H7L6 8zM9 8V6a3 3 0 0 1 6 0v2",
    "menu": "M4 7h16M4 12h16M4 17h16",
    "mail": "M4 6h16v12H4zM4 7l8 6 8-6",
    "plus": "M12 5v14M5 12h14",
    "minus": "M5 12h14",
    "flag": "M5 21V4M5 4h12l-2 4 2 4H5",
    "hammer": "M14 4l6 6-3 3-6-6 3-3zM11 7L4 14a2 2 0 0 0 3 3l7-7",
    "trophy": "M8 4h8v5a4 4 0 0 1-8 0V4zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8 20h8",
    "search": "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM15.5 15.5L20 20",
    "gem": "M12 3l6 6-6 12-6-12 6-6zM6 9h12",
    "coin": "M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM9 9.5h6M9 14.5h6",
    "bell": "M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2zM10 20a2 2 0 0 0 4 0",
    "hourglass": "M7 3h10M7 21h10M8 3v3l4 6-4 6v3M16 3v3l-4 6 4 6v3",
    "skull": "M12 3a7 7 0 0 0-7 7c0 2.6 1.3 4.2 3 5.2V18h8v-2.8c1.7-1 3-2.6 3-5.2a7 7 0 0 0-7-7zM9.5 11h.01M14.5 11h.01M10 21v-3M14 21v-3",
    "trash": "M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13",
    "door": "M6 21V8a6 6 0 0 1 12 0v13M4 21h16M10 21v-5a2 2 0 0 1 4 0v5",
    "sword": "M19 5L9 15M19 5h-4M19 5v4M7 13l4 4M8.5 15.5L5 19",
    "close": "M6 6l12 12M18 6L6 18",
    "sort": "M7 4v16M4 17l3 3 3-3M17 20V4M14 7l3-3 3 3",
    "filter": "M4 5h16l-6.5 7.5V18l-3 1.5v-7L4 5z",
    "chain": "M9 15l6-6M10.5 6.5l1-1a4 4 0 0 1 5.7 5.7l-1 1M13.5 17.5l-1 1a4 4 0 0 1-5.7-5.7l1-1",
    "eye": "M2.5 12c3-5.5 16-5.5 19 0-3 5.5-16 5.5-19 0zM12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
    "campfire": "M12 3c1 3 4 5 4 9a4 4 0 0 1-8 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 0-8zM5 21l14-4M5 17l14 4",
    "chevronLeft": "M15 6l-6 6 6 6",
    "chevronRight": "M9 6l6 6-6 6",
    "chevronDown": "M6 9l6 6 6-6",
    "chevronUp": "M6 15l6-6 6 6",
    "pushpin": "M9 3h6M10 3v6l-3.5 4.5h11L14 9V3M12 13.5V21",
    "check": "M5 12.5l4.5 4.5L19 7",
    "crown": "M4 17l-1-10 5 4 4-6 4 6 5-4-1 10H4zM4 20h16",
    "leaf": "M12 21c-4 0-7-3-7-6.5C5 10 9 9 12 3c3 6 7 7 7 11.5 0 3.5-3 6.5-7 6.5zM12 21V11",
    "reset": "M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4",
    "lock": "M7 11V8a5 5 0 0 1 10 0v3M5 11h14v10H5z",
    "chat": "M4 5h16v11H9l-5 4V5z",
    "userPlus": "M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM3 21c0-4 3-6 7-6s7 2 7 6M19 8v6M16 11h6",
    # a cogwheel: one outline with six teeth around a hole (eight rays read as a sun, found in game)
    "gear": "M9.71 4.75 L9.89 1.61 L14.11 1.61 L14.29 4.75 L17.13 6.40 L19.94 4.98 L22.05 8.64 L19.42 10.36 L19.42 13.64 L22.05 15.36 L19.94 19.02 L17.13 17.60 L14.29 19.25 L14.11 22.39 L9.89 22.39 L9.71 19.25 L6.87 17.60 L4.06 19.02 L1.95 15.36 L4.58 13.64 L4.58 10.36 L1.95 8.64 L4.06 4.98 L6.87 6.40z M12 8.8a3.2 3.2 0 1 0 0 6.4 3.2 3.2 0 0 0 0-6.4z",
    # the map's pins (MapPin, 3.5 stage 2)
    "wing": "M20 4C13 4 7 7 4 13l4 .5L5 18c5 0 9-1.5 12-4.5l-4-.5 5-3-4-.5c2.5-1.5 4.5-3.5 6-5.5z",
    "pin": "M12 21s-6-6.2-6-11a6 6 0 0 1 12 0c0 4.8-6 11-6 11zM12 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
    "gate": "M4 21V10a8 7 0 0 1 16 0v11M2 21h20M9 21V3.6M15 21V3.6M4 14h16",
    "swords": "M4 4l9 9M4 4v3M4 4h3M20 4l-9 9M20 4v3M20 4h-3M7 16l-3 3M17 16l3 3M9 14l-3-3M15 14l3-3",
    "chest": "M4 10h16v9H4zM4 10a4 4 0 0 1 4-4h8a4 4 0 0 1 4 4M11 12h2v3h-2z",
    "inn": "M3 11l9-7 9 7M5.5 9v11h13V9M10 20v-5h4v5",
    "mug": "M5 6h10v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6zM15 9h2.5a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1-1.5 1.5H15M8.5 10v6M11.5 10v6",
    # the game's repair icon in line: a block seen from above at three quarters, the horn
    # to the left, a tapered waist, a wide foot (a flat side view didn't read as repair)
    "anvil": "M6.5 7.5L10.5 3.5H21.5L17.5 7.5ZM6.5 7.5V12H17.5V7.5M17.5 12L21.5 8V3.5M6.5 7.5L1.5 9.5L6.5 11M9 12L10 16.5M15 12L14 16.5M6 16.5H18L19.5 21H4.5Z",
    # a dungeon's portal: three arms turning out from the middle (Archimedean, r 1.5 to 9
    # over 200°), balanced so it can spin on the map
    "swirl": "M13.5 12.0L14.1 12.8L14.3 13.9L13.9 15.2L12.8 16.4L11.1 17.2L9.0 17.2L6.8 16.3L5.0 14.6L3.8 12.0L3.5 8.9M11.2 13.3L10.3 13.4L9.2 13.0L8.2 12.0L7.8 10.5L8.0 8.6L9.0 6.8L10.8 5.4L13.3 4.6L16.1 4.9L18.9 6.2M11.2 10.7L11.6 9.8L12.5 9.0L13.9 8.8L15.4 9.1L16.9 10.2L18.0 12.0L18.3 14.3L17.7 16.8L16.1 19.1L13.6 20.9",
    "bank": "M3 9l9-5 9 5H3zM5 9v9M9.7 9v9M14.3 9v9M19 9v9M3 20.5h18",
    "gavel": "M13 3l6 6-3 3-6-6 3-3zM13 9l-8.5 8.5M3 21h9",
    "tabard": "M8 3h8l3 3-2 2v13l-5-2.5L7 21V8L5 6l3-3zM10 10.5h4",
    "spirit": "M6 21V11a6 6 0 0 1 12 0v10l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5-2 1.5zM10 11h.01M14 11h.01",
    "paw": "M6 10.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0M9.5 7a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0M12.5 7a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0M15.5 10.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0M12 12.5c-2.8 0-5 3.2-5 5.2 0 1.8 2 2.1 5 1.3 3 .8 5 .5 5-1.3 0-2-2.2-5.2-5-5.2z",
    "star": "M12 3l2.4 6.6L21 12l-6.6 2.4L12 21l-2.4-6.6L3 12l6.6-2.4L12 3z",
    "flask": "M10 3h4M10 3v6l-5 9a1.5 1.5 0 0 0 1.3 2.2h11.4A1.5 1.5 0 0 0 19 18l-5-9V3M7.5 15h9",
    "pot": "M4 10h16v3a6 6 0 0 1-6 6h-4a6 6 0 0 1-6-6v-3zM8 10V7M12 10V5M16 10V7",
    "bandage": "M7 17L17 7a3 3 0 0 0-4-4L3 13a3 3 0 0 0 4 4zM10 10h.01M12 12h.01M14 10h.01",
    "fish": "M3 12c3-4 8-6 13-3l4-3v12l-4-3c-5 3-10 1-13-3zM15 11h.01",
    "pick": "M4.2 16.2C4.2 9.9 9.9 4.2 16.2 4.2M7.9 7.9L18.4 18.4",
    "needle": "M20 4L7 17M18.5 3.8l1.7 1.7M7 17l-2.5 2.5M7 17c-4-1-4.5 3-2 4 2.5 1 5-1 7-3",
    "knife": "M4 20l5-5M9 15l2 2M9 15l9.5-9.5c1.5 3.5.5 7.5-3 10l-2.5 1.5",
    "hide": "M6 4c2 1 4 1 6 0 2 1 4 1 6 0-.5 3 1 5 2 6-1 2-1.5 5-1 8-2-.5-4 0-5 2-1-2-3-2.5-5-2s-4-.5-5 0c.5-3 0-6-1-8 1-1 2.5-3 2-6z",
    # the map's profession trainers, drawn after the game's own icons (players know
    # those; ours didn't read as them, found in game; /suu probe proficons):
    "profAlchemy": "M2.8 6.8L6.8 2.8M4.2 8.2L8.2 4.2L18.2 14.2A2.9 2.9 0 0 1 14.2 18.2ZM8.4 12.4l4-4",  # a vial lying from its stopper (top left) to its round bottom
    "profBlacksmithing": "M7 6L10.5 3H20L16.5 6ZM7 6V9.5H16.5V6M16.5 9.5L20 6.5V3M7 6L3 7.8L7 9M9.5 9.5L10.3 13M14 9.5L13.2 13M5 21V16.5H19V21M8 13H16L17 16.5H7Z",  # the anvil on its block
    "profEnchanting": "M3.5 19L16 6.5M5.5 21L18 8.5M16 6.5l2 2M13.5 15l2.5-1 .5 2.5 2.5-1 .5 2.5M19.5 2v4M17.5 4h4",  # a rod with runes and a spark
    "profHerbalism": "M3 21L21 3M8 16C4.5 14.5 2 16 1.5 19 4.5 20 7 18.5 8 16zM12.5 11.5c-1-3.5.5-6.5 4-7.5 1 3.5-.5 6.5-4 7.5zM15 9c3.5-1 6.5.5 7.5 4-3.5 1-6.5-.5-7.5-4zM12 16a1.8 1.8 0 1 0 0 .01",  # a branch with three leaves and a berry
    "profLeatherworking": "M8.5 9.5C5.5 12 5 17 7.5 19.5h9c2.5-2.5 2-7.5-1-10zM8.5 9.5L7 5h10l-1.5 4.5M12 9.5l-2.5 4.5M12 9.5l2.5 4.5M9 17h.01M12 17.5h.01M15 17h.01",  # a tied leather pouch, stitched
    "profMining": "M15 7L12 21.5M15 6L3 12.5l2.5 4.5 11.5-8.5zM16 5.5L21.5 2",  # a pick with its wide blade down to the left
    "profTailoring": "M5 4.5h10M5 19.5h10M6.5 4.5v15M13.5 4.5v15M6.5 9h7M6.5 12h7M6.5 15h7M21 2.5L9 21.5M20 4.5l-1 1.5",  # a spool of thread and a needle
    "profCooking": "M8 16c0-4.5 3.5-8 8-8 3.5 0 6 2.5 6 6s-3 6.5-7 6.5h-4c-2 0-3-2-3-4.5zM11 10.5c-1.5-1.5-2.5-3-3-5M14 8.5c-1-1.5-2-3-2.5-4.5M8 5.5L6 3.5M11.5 4L10 1.5M4.5 4.5a1.4 1.4 0 1 0 2-2M8.5 2.5a1.4 1.4 0 1 0 2.5-.5",  # a roast bird, its leg up to the left
    "profFirstAid": "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 6.5l3.5 7a3.5 3.5 0 1 1-7 0z",  # a drop in a ring
    "profFishing": "M12 2.5a1.5 1.5 0 1 0 .01 0M12 4v12a3.5 3.5 0 0 1-7 0V13l2 2M17 9c2 1 2.5 4 1 6s-1 4.5 1 5.5M8 7c-2 1-2 3.5 0 4.5",  # a hook with worms
    # map marks (3.5 stage 3): the eight symbols, after the game's raid markers
    "markStar": "M12.0 3.4L14.3 9.4L20.7 9.8L15.7 13.8L17.4 20.0L12.0 16.5L6.6 20.0L8.3 13.8L3.3 9.8L9.7 9.4Z",
    "markCircle": "M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16z",
    "markDiamond": "M12 2.5l7 9.5-7 9.5-7-9.5z",
    "markTriangle": "M12 3.5l9 16H3z",
    "markMoon": "M14.5 3.5a8.5 8.5 0 1 0 6 13.5 7 7 0 0 1-6-13.5z",
    "markSquare": "M5 5h14v14H5z",
    "markCross": "M7 3.5l5 5 5-5 3.5 3.5-5 5 5 5-3.5 3.5-5-5-5 5-3.5-3.5 5-5-5-5z",
    "markArrow": "M12 4l7 14H5z",  # a mark's direction on the minimap's edge
    # the game's quest markers restyled (3.5): in progress, and its next step on another map
    "questDots": "M5.8 12a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 1 0-2.4 0M10.8 12a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 1 0-2.4 0M15.8 12a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 1 0-2.4 0",
    "dash": "M3 12h11M10 6l6 6-6 6M20 5v14",
    # the first-run welcome: the Tank role, and "turn a feature off" (modules)
    "shield": "M12 3l7 3v5c0 5-3.5 8.5-7 10-3.5-1.5-7-5-7-10V6l7-3z",
    "layers": "M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5M3 17l9 5 9-5",
    # the totem bar (1.6d): an empty element's glyph, and Call of the Elements
    "rock": "M3 19l6-10 4 6 3-4 5 8H3z",
    "sun": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4",
    "drop": "M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z",
    "wave": "M3 10c2-3 4-3 6 0s4 3 6 0 4-3 6 0M3 16c2-3 4-3 6 0s4 3 6 0 4-3 6 0",
    "totem": "M9 3h6v4H9zM8 7h8v5H8zM10 12h4v9h-4z",
    "markSkull": "M12 3a6.5 6.5 0 0 0-6.5 6.5c0 2.3 1.1 3.7 2.5 4.6V16.5h8v-2.4c1.4-.9 2.5-2.3 2.5-4.6A6.5 6.5 0 0 0 12 3zM9.5 10h.01M14.5 10h.01M11 13.5h2M4 18l16 3.5M20 18L4 21.5",
}


# --- The SuuUI mark (Docs/assets/suuui-mark.svg, 100 units): layered colour

def _hex(h, a=1.0):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mark_pixel(size=64, ss=4):
    outer = [(50, 6), (94, 50), (50, 94), (6, 50)]
    inner = [(50, 18), (82, 50), (50, 82), (18, 50)]
    core = [(50, 31), (69, 50), (50, 69), (31, 50)]
    light = [(50, 31), (50, 50), (31, 50)]
    dark = [(69, 50), (50, 69), (50, 50)]

    def near_outline(px, py, pts, half):
        for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
            vx, vy = bx - ax, by - ay
            ll = vx * vx + vy * vy
            t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / ll))
            dx, dy = px - (ax + t * vx), py - (ay + t * vy)
            if dx * dx + dy * dy <= half * half:
                return True
        return False
    # layers in paint order: (test, colour)
    layers = [
        (lambda x, y: inside_polygon(x, y, outer), _hex("131116")),
        (lambda x, y: near_outline(x, y, outer, 1.75), _hex("C9A75A")),
        (lambda x, y: near_outline(x, y, inner, 0.6), _hex("C9A75A", 0.5)),
        (lambda x, y: inside_polygon(x, y, core), _hex("3FD0FF")),
        (lambda x, y: inside_polygon(x, y, light), _hex("FFFFFF", 0.45)),
        (lambda x, y: inside_polygon(x, y, dark), _hex("000000", 0.18)),
    ]
    cache = {}
    for py in range(size):
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss) * 100 / size
                    y = (py + (sy + 0.5) / ss) * 100 / size
                    r = g = b = a = 0.0
                    for test, (cr, cg, cb, ca) in layers:
                        if test(x, y):  # source over
                            r = cr * ca + r * (1 - ca)
                            g = cg * ca + g * (1 - ca)
                            b = cb * ca + b * (1 - ca)
                            a = ca + a * (1 - ca)
                    acc[0] += r; acc[1] += g; acc[2] += b; acc[3] += a
            n = ss * ss
            a = acc[3] / n
            # un-premultiply
            col = [min(255, round(acc[k] / n / a)) if a > 0 else 0 for k in range(3)]
            cache[(px, py)] = (col[0], col[1], col[2], round(255 * a))
    return lambda x, y: cache[(x, y)]


# The gem's quarters (the mark's 100 units), for LoadingFacet1-4
FACETS = [
    [(50, 31), (50, 50), (31, 50)],
    [(50, 31), (69, 50), (50, 50)],
    [(31, 50), (50, 69), (50, 50)],
    [(69, 50), (50, 69), (50, 50)],
]


def facet(i, size=128, ss=4):
    pts = FACETS[i]
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss) * 100 / size
                    y = (py + (sy + 0.5) / ss) * 100 / size
                    if inside_polygon(x, y, pts):
                        hits += 1
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


# --- Circles: radial coverage with 4x4 supersampling

def circle(size, inner, outer, ss=4):
    """Alpha of the band inner..outer (fractions of the radius)."""
    r = size / 2
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss - r
                    y = py + (sy + 0.5) / ss - r
                    d = math.hypot(x, y) / r
                    if inner <= d <= outer:
                        hits += 1
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


def diamond(size, diagonal, ss=4):
    """Alpha of a diamond `diagonal` (fraction of the size) wide, centred."""
    r = size / 2
    half = diagonal * size / 2
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss - r
                    y = py + (sy + 0.5) / ss - r
                    if abs(x) + abs(y) <= half:
                        hits += 1
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


def soft_circle(size, core=0.6):
    """A disc solid to `core` of the radius, then a smooth fall to the edge."""
    r = size / 2

    def pixel(px, py):
        d = math.hypot(px + 0.5 - r, py + 0.5 - r) / r
        if d <= core:
            a = 1.0
        elif d >= 1:
            a = 0.0
        else:
            t = (d - core) / (1 - core)
            a = (1 - t) ** 2 * (1 + 2 * t)  # smoothstep down
        return (255, 255, 255, round(255 * a))
    return pixel


def player_arrow(size=64, ss=4):
    # the design's path on 16 units, centred, drawn in the middle 60% (room for the glow)
    pts = [(8, 1.5), (13, 14), (8, 11), (3, 14)]
    scale = size * 0.6 / 16
    off = size * 0.2
    poly = [(off + x * scale, off + y * scale) for x, y in pts]

    def dist_outline(px, py):
        best = 1e9
        for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
            vx, vy = bx - ax, by - ay
            ll = vx * vx + vy * vy
            t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / ll))
            dx, dy = px - (ax + t * vx), py - (ay + t * vy)
            best = min(best, math.hypot(dx, dy))
        return best
    arcane = (63, 208, 255)
    rim = (8, 20, 28)
    cache = {}
    for py in range(size):
        for px in range(size):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x, y = px + (sx + 0.5) / ss, py + (sy + 0.5) / ss
                    inside = inside_polygon(x, y, poly)
                    d = dist_outline(x, y)
                    if inside and d > 1.6:
                        c, al = arcane, 1.0
                    elif inside or d <= 1.6:
                        c, al = rim, 0.95
                    else:
                        glow = math.exp(-(d * d) / (2 * 4.0 * 4.0)) * 0.55
                        c, al = arcane, glow
                    r += c[0] * al; g += c[1] * al; b += c[2] * al; a += al
            n = ss * ss
            a /= n
            if a > 0:
                cache[(px, py)] = (round(r / n / a), round(g / n / a), round(b / n / a), round(255 * min(1, a)))
            else:
                cache[(px, py)] = (0, 0, 0, 0)
    return lambda x, y: cache[(x, y)]


def ring_arc(size, inner, outer, start, stop, ss=4):
    """Alpha of a ring inner..outer (fractions of the radius) from `start` to
    `stop` degrees, clockwise from the top (the map pins' split ring: turned
    in game for each quest's arc)."""
    r = size / 2
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss - r
                    y = py + (sy + 0.5) / ss - r
                    d = math.hypot(x, y) / r
                    a = math.degrees(math.atan2(x, -y)) % 360
                    if inner <= d <= outer and start <= a <= stop:
                        hits += 1
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


def dashed_ring(size, inner, outer, dashes=16, ss=4):
    """Alpha of a ring inner..outer (fractions of the radius) in `dashes` dashes, half on."""
    r = size / 2
    cache = {}
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss - r
                    y = py + (sy + 0.5) / ss - r
                    d = math.hypot(x, y) / r
                    a = (math.atan2(y, x) / (2 * math.pi)) % 1
                    if inner <= d <= outer and (a * dashes) % 1 < 0.5:
                        hits += 1
            cache[(px, py)] = round(255 * hits / (ss * ss))
    return lambda x, y: (255, 255, 255, cache[(x, y)])


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(OUT, "Glyphs"), exist_ok=True)
    root = os.path.dirname(HERE)
    jobs = [
        ("Soft.tga", SIZE, lambda x, y: (255, 255, 255, round(255 * soft_alpha(x, y)))),
        ("Hatch.tga", 16, lambda x, y: (255, 255, 255, hatch_alpha(x, y))),
        ("RoleTank.tga", 32, raster(shield())),
        ("RoleHealer.tga", 32, raster(cross())),
        ("RoleDamage.tga", 32, raster(sword())),
    ]
    for name, d in GLYPHS.items():
        jobs.append((os.path.join("Glyphs", name + ".tga"), 64, stroke_alpha(path_polylines(d), 1.9)))
    jobs.append(("Mark.tga", 64, mark_pixel()))
    jobs.append(("LoadingMark.tga", 128, mark_pixel(128)))
    for i in range(4):
        jobs.append(("LoadingFacet%d.tga" % (i + 1), 128, facet(i)))
    jobs.append(("CircleFill.tga", 64, circle(64, 0, 1)))
    jobs.append(("CircleEdge.tga", 256, circle(256, 1 - 2 / 176, 1)))
    jobs.append(("CircleBand.tga", 256, circle(256, 1 - 8 / 176, 1 - 2 / 176)))
    jobs.append(("CircleSoft.tga", 128, soft_circle(128)))
    # a pin's dashed edge (a quest's next step on another map): 1 px at 26 px
    jobs.append(("CircleDash.tga", 104, dashed_ring(104, 1 - 2 / 26, 1)))
    jobs.append(("PlayerArrow.tga", 64, player_arrow()))
    # a map pin's split ring (design "Map quest difficulty" D): one arc per
    # quest of 2, 3 or 4, 8 degrees apart; 2 px at the pin's 26 px
    for n in (2, 3, 4):
        jobs.append(("RingArc%d.tga" % n, 104, ring_arc(104, 1 - 2 / 13, 1, 4, 360 / n - 4)))
    jobs.append(("ChatDiamond.tga", 32, diamond(32, 0.5)))
    only = set(os.sys.argv[1:])
    for name, size, pixel in jobs:
        if only and name not in only and os.path.splitext(os.path.basename(name))[0] not in only:
            continue
        path = os.path.join(OUT, name)
        write_tga(path, size, size, pixel)
        print("wrote", os.path.relpath(path, root))


if __name__ == "__main__":
    main()
