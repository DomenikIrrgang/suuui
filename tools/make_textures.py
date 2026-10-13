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
    "eye": "M2.5 12c3-5.5 16-5.5 19 0-3 5.5-16 5.5-19 0zM12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
    "campfire": "M12 3c1 3 4 5 4 9a4 4 0 0 1-8 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 0-8zM5 21l14-4M5 17l14 4",
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
    jobs.append(("CircleFill.tga", 64, circle(64, 0, 1)))
    jobs.append(("CircleEdge.tga", 256, circle(256, 1 - 2 / 176, 1)))
    jobs.append(("CircleBand.tga", 256, circle(256, 1 - 8 / 176, 1 - 2 / 176)))
    jobs.append(("CircleSoft.tga", 128, soft_circle(128)))
    jobs.append(("PlayerArrow.tga", 64, player_arrow()))
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
