#!/usr/bin/env python3
"""Generate the Stranglethorn themes' art (Ruins and Canopy) into
Media/Textures/Themes/Stranglethorn. Standard library only.

    python3 -I tools/stv_art.py                 every file
    python3 -I tools/stv_art.py VineTop Firefly only these
    python3 -I tools/stv_art.py --sheet out.png a preview sheet of the art

Coloured art (the dress: vines, leaves, flowers, the parrot, headers) is
drawn in its own colours (RGBA); masks (patterns, bars, the edge, motes,
glyphs) are white with alpha, tinted by a colour token in game, as SuuUI's
own textures are.

The drawing: shapes painted in order (later over earlier), each pixel
supersampled ss x ss, so edges are smooth. Shapes: ellipses (turned),
polygons, thick polylines (a vine, a stalk), leaves (two curves meeting at
a point, a vein down the middle).
"""

import math
import os
import random
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_textures as mt  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Media", "Textures", "Themes", "Stranglethorn")


# --- colours -----------------------------------------------------------------

def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c1, c2, t):
    return tuple(round(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


# --- shapes (each: bbox, inside(x, y) -> colour or None) ----------------------

class Shape:
    def __init__(self, bbox, fn):
        self.bbox = bbox
        self.fn = fn


def ellipse(cx, cy, rx, ry, color, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    r = max(rx, ry)

    def fn(x, y):
        dx, dy = x - cx, y - cy
        u, v = dx * c + dy * s, -dx * s + dy * c
        if (u / rx) ** 2 + (v / ry) ** 2 <= 1:
            return color(u / rx, v / ry) if callable(color) else color
        return None
    return Shape((cx - r, cy - r, cx + r, cy + r), fn)


def polygon(pts, color):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]

    def fn(x, y):
        return (color(x, y) if callable(color) else color) if mt.inside_polygon(x, y, pts) else None
    return Shape((min(xs), min(ys), max(xs), max(ys)), fn)


def seg_dist(x, y, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    ll = vx * vx + vy * vy
    t = 0 if ll == 0 else max(0, min(1, ((x - ax) * vx + (y - ay) * vy) / ll))
    dx, dy = x - (ax + t * vx), y - (ay + t * vy)
    return math.sqrt(dx * dx + dy * dy), t


def stroke(pts, width, color, taper=None):
    """A thick polyline; `taper` (w0, w1) narrows it from start to end."""
    segs = list(zip(pts, pts[1:]))
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in segs) or 1
    starts, acc = [], 0
    for a, b in segs:
        starts.append(acc)
        acc += math.hypot(b[0] - a[0], b[1] - a[1])
    pad = max(width, (taper or (0, 0))[0]) / 2 + 1
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]

    def fn(x, y):
        for i, (a, b) in enumerate(segs):
            d, t = seg_dist(x, y, a[0], a[1], b[0], b[1])
            if taper:
                along = (starts[i] + t * math.hypot(b[0] - a[0], b[1] - a[1])) / total
                w = taper[0] + (taper[1] - taper[0]) * along
            else:
                w = width
            if d <= w / 2:
                return color(d / (w / 2)) if callable(color) else color
        return None
    return Shape((min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad), fn)


def bez(p0, p1, p2, p3, n=24):
    out = []
    for k in range(n + 1):
        t = k / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def leaf_points(x, y, length, width, angle, curl=0.0, n=14):
    """A leaf from its stem at (x, y) along `angle` (radians, 0 = right,
    y down): two curves meeting at the tip; `curl` bends it."""
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n, -1, -1)
        for k in rng:
            t = k / n
            u = t * length
            v = side * width * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t)
            v += curl * length * t * t
            pts.append((x + u * ca - v * sa, y + u * sa + v * ca))
    return pts


def leaf(x, y, length, width, angle, light, dark, vein=None, curl=0.0):
    """A filled leaf, lighter along one side, with a vein."""
    pts = leaf_points(x, y, length, width, angle, curl)
    ca, sa = math.cos(angle), math.sin(angle)

    def color(px, py):
        u = (px - x) * ca + (py - y) * sa
        v = -(px - x) * sa + (py - y) * ca
        t = max(0.0, min(1.0, 0.5 + v / (2 * width + 1e-6)))
        c = mix(dark, light, t)
        if vein is not None:
            mid = curl * length * (u / length) ** 2 if length else 0
            if abs(v - mid) < 0.55 and 0.08 * length < u < 0.9 * length:
                return vein
        return c
    shapes = [polygon(pts, color)]
    return shapes


# --- rendering ----------------------------------------------------------------

def render(w, h, shapes, ss=3, background=(0, 0, 0, 0)):
    """RGBA rows: each pixel the average of ss x ss samples, each sample the
    last shape that covers it (premultiplied average, so edges blend)."""
    rows = []
    inv = 1.0 / ss
    for py in range(h):
        row = []
        cand_y = [s for s in shapes if s.bbox[1] - 1 <= py + 1 and s.bbox[3] + 1 >= py]
        for px in range(w):
            cand = [s for s in cand_y if s.bbox[0] - 1 <= px + 1 and s.bbox[2] + 1 >= px]
            if not cand:
                row.append(background)
                continue
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x, y = px + (sx + 0.5) * inv, py + (sy + 0.5) * inv
                    col = None
                    for s in reversed(cand):
                        col = s.fn(x, y)
                        if col is not None:
                            break
                    if col is None:
                        col = background
                    al = col[3] / 255.0
                    r += col[0] * al
                    g += col[1] * al
                    b += col[2] * al
                    a += al
            n = ss * ss
            if a <= 0:
                row.append((0, 0, 0, 0))
            else:
                row.append((round(r / a), round(g / a), round(b / a), round(255 * a / n)))
        rows.append(row)
    return rows


def write_rgba_tga(path, rows):
    h, w = len(rows), len(rows[0])
    mt.write_tga(path, w, h, lambda x, y: rows[y][x])


def write_png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


# --- palettes -----------------------------------------------------------------

RUINS = dict(
    leaf_light=hexc("#7FA94A"), leaf_dark=hexc("#2E5A22"), vein=hexc("#244A1A"),
    vine=hexc("#2F4A22"), vine_light=hexc("#4B6B30"),
    stone_light=hexc("#3A4436"), stone=hexc("#2C3428"), stone_dark=hexc("#1C221A"),
    ember=hexc("#E8873A"), berry=hexc("#C7463A"),
)
CANOPY = dict(
    leaf_light=hexc("#5CC878"), leaf_dark=hexc("#1A6B40"), vein=hexc("#145533"),
    vine=hexc("#1E6B3F"), vine_light=hexc("#2E8A52"),
    hibiscus=hexc("#F26B5B"), hibiscus_light=hexc("#F7907F"), hibiscus_dark=hexc("#D9483A"),
    orchid=hexc("#F2D24A"), orchid_light=hexc("#F8E58A"), pollen=hexc("#FFE07A"), lip=hexc("#C2512F"),
)


def vine_line(pts, pal, width):
    """A vine: a dark stalk with a lighter streak along it."""
    def color(d):
        return pal["vine_light"] if d < 0.35 else pal["vine"]
    return stroke(pts, width, color)


def leaves_along(pts, pal, every, length, width, rng, hang=1.0, flip=False, down=1.0):
    """Leaves hanging off a vine's points, alternating sides."""
    out = []
    for k in range(0, len(pts) - 1, every):
        (x0, y0), (x1, y1) = pts[k], pts[k + 1]
        ang = math.atan2(y1 - y0, x1 - x0)
        side = 1 if (k // every) % 2 == 0 else -1
        if flip:
            side = -side
        a = ang + side * (0.9 + rng.uniform(-0.25, 0.25)) * hang
        size = down if side > 0 else 1.0
        out += leaf(x0, y0, length * size * rng.uniform(0.85, 1.15), width * (0.6 + 0.4 * size), a, pal["leaf_light"], pal["leaf_dark"],
                    pal["vein"], curl=side * 0.06)
    return out


def hibiscus(cx, cy, r, pal):
    out = []
    for k in range(5):
        a = k * 2 * math.pi / 5 - math.pi / 2
        out.append(ellipse(cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55, r * 0.55, r * 0.42,
                           lambda u, v: mix(pal["hibiscus_light"], pal["hibiscus_dark"], max(0, min(1, (u + 1) / 2))),
                           rot=a))
    out.append(ellipse(cx, cy, r * 0.3, r * 0.3, pal["hibiscus_dark"]))
    out.append(ellipse(cx, cy, r * 0.13, r * 0.13, pal["pollen"]))
    return out


def orchid(cx, cy, r, pal):
    out = []
    for k in range(5):
        a = k * 2 * math.pi / 5 - math.pi / 2
        out.append(ellipse(cx + math.cos(a) * r * 0.5, cy + math.sin(a) * r * 0.5, r * 0.5, r * 0.3,
                           lambda u, v: mix(pal["orchid_light"], pal["orchid"], max(0, min(1, (u + 1) / 2))), rot=a))
    out.append(ellipse(cx, cy + r * 0.1, r * 0.22, r * 0.18, pal["lip"]))
    return out


# --- the dress -------------------------------------------------------------------

# the vine's row in vine_top's art: a theme puts it on the window's edge
# (its y offset: 48 - VINE_Y = 16 px of art under the edge)
VINE_Y = 32


def vine_top(pal, flowers=False, seed=1, h=48):
    """256 x h (48: windows, 32: the unit frames), tiled along a frame's top:
    a vine waving across (it meets itself at the edges: a whole sine) on the
    frame's edge (row VINE_Y of 48, scaled), big leaves rising over it,
    small ones dipping under it (they keep off the title)."""
    rng = random.Random(seed)
    w = 256
    k = h / 48
    vy = VINE_Y * k

    def at(x):
        return vy + 4 * k * math.sin(2 * math.pi * x / w)
    pts = [(x, at(x)) for x in range(-8, w + 9, 4)]
    shapes = [vine_line(pts, pal, 4.2 * max(k, 0.8))]
    shapes += leaves_along(pts[2:-2], pal, 3, 20 * k, 6.4 * k, rng, down=0.5)
    if flowers:
        for x in (52, 180):
            shapes += hibiscus(x, at(x) - 4 * k, 9 * k, pal)
        for x in (118, 236):
            shapes += orchid(x, at(x) - 5 * k, 5.5 * k, pal)
    else:
        for x in (64, 196):
            shapes.append(ellipse(x, at(x) + 5 * k, 2.6 * k, 2.6 * k, pal["berry"]))
            shapes.append(ellipse(x + 4 * k, at(x) + 6 * k, 2.2 * k, 2.2 * k, pal["berry"]))
    return render(w, h, shapes)


def corner_clump(pal, flowers=False, seed=2):
    """128x112, a window's top left corner: a vine coming over the corner
    and hanging down the side, a clump of big leaves."""
    rng = random.Random(seed)
    w, h = 128, 112
    over = bez((14, 30), (44, 14), (90, 22), (124, 32), 20)
    down = bez((18, 28), (6, 52), (20, 80), (12, 108), 20)
    shapes = [vine_line(over, pal, 5), vine_line(down, pal, 4)]
    shapes += leaves_along(over, pal, 3, 22, 7, rng)
    shapes += leaves_along(down, pal, 3, 20, 6.5, rng, flip=True)
    shapes += leaf(20, 30, 34, 11, -0.55, pal["leaf_light"], pal["leaf_dark"], pal["vein"], curl=-0.05)
    shapes += leaf(20, 30, 30, 10, 0.9, pal["leaf_light"], pal["leaf_dark"], pal["vein"], curl=0.05)
    shapes += leaf(20, 30, 28, 9, -2.2, pal["leaf_light"], pal["leaf_dark"], pal["vein"], curl=0.04)
    if flowers:
        shapes += hibiscus(34, 34, 11, pal)
        shapes += orchid(12, 76, 6, pal)
    else:
        shapes.append(ellipse(26, 42, 3, 3, pal["berry"]))
        shapes.append(ellipse(31, 45, 2.6, 2.6, pal["berry"]))
    return render(w, h, shapes)


def side_drop(pal, flowers=False, seed=3):
    """40x160, a vine hanging down a window's side from its top."""
    rng = random.Random(seed)
    w, h = 40, 160
    pts = bez((20, 0), (8, 50), (32, 100), (18, 156), 24)
    shapes = [vine_line(pts, pal, 3.6)]
    shapes += leaves_along(pts, pal, 3, 15, 5, rng)
    if flowers:
        shapes += orchid(20, 120, 5.5, pal)
    return render(w, h, shapes)


def firefly():
    """32x32 white, a soft glow with a bright core (motes, tinted)."""
    def pixel(x, y):
        d = math.hypot(x + 0.5 - 16, y + 0.5 - 16) / 16
        a = max(0.0, 1 - d) ** 2.2
        core = max(0.0, 1 - d * 4.5)
        return (255, 255, 255, round(255 * min(1.0, a * 0.8 + core)))
    return [[pixel(x, y) for x in range(32)] for y in range(32)]


# --- masks: white art, its coverage as alpha (tinted in game) ------------------

WHITE = (255, 255, 255, 255)
CUT = (0, 0, 0, 0)  # a shape in this colour cuts the shapes under it


def white(a=1.0):
    return (255, 255, 255, round(255 * a))


def coverage(w, h, shapes, ss=3):
    return [[px[3] / 255 for px in row] for row in render(w, h, shapes, ss)]


def as_mask(cov, strength=1.0):
    return [[(255, 255, 255, round(255 * strength * c)) for c in row] for row in cov]


def as_shade(cov, shade):
    """A white fill whose motif is `shade` white (a bar's fill, tinted by
    its colour: the motif darker than the fill, names keep their contrast)."""
    return [[(v, v, v, 255) for v in (round(255 * (1 - (1 - shade) * c)) for c in row)] for row in cov]


def tiled(w, h, make, xs=True, ys=True):
    """The shapes of make(dx, dy) at every neighbouring tile, so art that
    crosses an edge comes back on the other side (seamless when repeated)."""
    out = []
    for dx in ((-w, 0, w) if xs else (0,)):
        for dy in ((-h, 0, h) if ys else (0,)):
            out += make(dx, dy)
    return out


def spiral(cx, cy, r, turns, width, color):
    """A carved spiral (troll stonework) from its centre out to radius r."""
    n = int(24 * turns)
    pts = []
    for k in range(n + 1):
        t = k / n
        a = t * turns * 2 * math.pi
        pts.append((cx + math.cos(a) * r * t, cy + math.sin(a) * r * t))
    return stroke(pts, width, color)


def zigzag(x0, x1, y, amp, step, width, color):
    pts, x, up = [], x0, True
    while x <= x1 + 0.01:
        pts.append((x, y - amp if up else y + amp))
        x += step
        up = not up
    return stroke(pts, width, color)


def monstera(cx, cy, size, angle, body, cut=CUT):
    """A monstera leaf: a broad heart, slits from the edge toward the
    midrib, a few holes beside it, the midrib itself."""
    ca, sa = math.cos(angle), math.sin(angle)

    def at(u, v):
        return (cx + u * ca - v * sa, cy + u * sa + v * ca)
    shapes = [ellipse(cx, cy, size, size * 0.8, body, rot=angle)]
    for k, side in ((-3, 1), (-1, 1), (1, 1), (3, 1), (-3, -1), (-1, -1), (1, -1), (3, -1)):
        u = k * size * 0.2
        a, b = at(u * 0.35, side * size * 0.22), at(u * 1.05, side * size * 0.95)
        shapes.append(stroke([a, b], max(1.0, size * 0.07), cut))
    for k in (-2, 0, 2):
        for side in (1, -1):
            hx, hy = at(k * size * 0.2, side * size * 0.15)
            shapes.append(ellipse(hx, hy, size * 0.05, size * 0.035, cut, rot=angle))
    shapes.append(stroke([at(-size * 0.95, 0), at(size * 0.9, 0)], max(0.8, size * 0.045), cut))
    return shapes


PATTERN_ALPHA = 0.16  # as Pink Cat's: ink-faint keeps 3:1 over it


def ruins_pattern():
    """128x128: stonework (blocks in a running bond, faint joints), a carved
    spiral and a zigzag band in two of the stones."""
    def make(dx, dy):
        out = []
        for row in range(4):
            y = row * 32 + dy
            out.append(stroke([(dx - 2, y), (dx + 130, y)], 1.3, white(0.55)))
            off = 0 if row % 2 == 0 else 32
            for k in range(3):
                x = off + k * 64 + dx
                out.append(stroke([(x, y), (x, y + 32)], 1.3, white(0.55)))
        out.append(spiral(32 + dx, 16 + dy, 9, 2.2, 1.6, WHITE))
        out.append(zigzag(70 + dx, 122 + dx, 80 + dy, 4, 6.5, 1.5, WHITE))
        out.append(stroke([(100 + dx, 35 + dy), (106 + dx, 44 + dy), (103 + dx, 52 + dy)], 1.0, white(0.7)))
        return out
    return as_mask(coverage(128, 128, tiled(128, 128, make)), PATTERN_ALPHA)


def canopy_pattern():
    """128x128: two monstera leaves, faint, at angles."""
    def make(dx, dy):
        return (monstera(36 + dx, 40 + dy, 26, -0.6, white(0.6)) +
                monstera(96 + dx, 100 + dy, 22, 2.3, white(0.6)))
    return as_mask(coverage(128, 128, tiled(128, 128, make)), PATTERN_ALPHA)


def ruins_track():
    """32x32 behind the bars: a carved zigzag."""
    def make(dx, dy):
        return [zigzag(dx - 4, dx + 36, 16 + dy, 3, 4, 1.4, WHITE)]
    return as_mask(coverage(32, 32, tiled(32, 32, make)), 0.13)


def canopy_track():
    """32x32 behind the bars: a small leaf."""
    def make(dx, dy):
        return leaf(8 + dx, 24 + dy, 18, 5, -0.8, WHITE, WHITE)
    return as_mask(coverage(32, 32, tiled(32, 32, make)), 0.13)


BAR_SHADE = 0.64  # as Pink Cat's bars


def vine_bar(h):
    """256 x h: a bar's fill, a vine along it with leaves both sides
    (repeated along the bar at its height)."""
    def make(dx, dy):
        mid = h / 2
        amp = h * 0.14
        pts = [(x + dx, mid + amp * math.sin(2 * math.pi * x / 128)) for x in range(-4, 261, 4)]
        out = [stroke(pts, max(1.4, h * 0.08), WHITE)]
        rng = random.Random(7)
        for k in range(0, len(pts) - 1, 3):
            (x0, y0), (x1, y1) = pts[k], pts[k + 1]
            ang = math.atan2(y1 - y0, x1 - x0)
            side = 1 if (k // 3) % 2 == 0 else -1
            out += leaf(x0, y0, h * 0.42 * rng.uniform(0.9, 1.1), h * 0.13, ang + side * 0.95, WHITE, WHITE)
        return out
    return as_shade(coverage(256, h, tiled(256, h, make, ys=False)), BAR_SHADE)


def rib_bar(h):
    """256 x h: a leaf's ribs along the bar: a midrib, veins sweeping back
    from it every few px."""
    def make(dx, dy):
        mid = h / 2
        out = [stroke([(dx - 2, mid), (dx + 258, mid)], max(1.2, h * 0.07), WHITE)]
        step = h * 0.75
        x = 0.0
        while x < 256 + step:
            for side in (1, -1):
                out.append(stroke([(x + dx, mid), (x + dx - h * 0.55, mid + side * h * 0.46)], max(1.0, h * 0.045),
                                  WHITE))
            x += step
        return out
    return as_shade(coverage(256, h, tiled(256, h, make, ys=False)), BAR_SHADE + 0.06)


def carved_edge():
    """8x8: the windows' edge as stone blocks (6 px on, a 2 px joint)."""
    def pixel(x, y):
        on = x < 6 if y == 0 else y < 6 if x == 0 else x < 6
        return (255, 255, 255, 255 if on else 80)
    return [[pixel(x, y) for x in range(8)] for y in range(8)]


def spiral_corner():
    """32x32: a carved spiral for the corners."""
    return as_mask(coverage(32, 32, [spiral(16, 16, 13, 2.4, 2.6, WHITE)]))


def leaf_corner():
    """32x32: a leaf for the corners, its tip out over the corner."""
    return as_mask(coverage(32, 32, leaf(27, 27, 30, 8.5, -2.356, WHITE, WHITE, CUT)))


def eye_jewel():
    """64x64: a carved troll eye: a diamond, its pupil."""
    outer = [(32, 6), (58, 32), (32, 58), (6, 32)]
    inner = [(32, 16), (48, 32), (32, 48), (16, 32)]
    return as_mask(coverage(64, 64, [polygon(outer, WHITE), polygon(inner, CUT), ellipse(32, 32, 7, 7, WHITE)]))


def orchid_jewel():
    """64x64: an orchid."""
    shapes = []
    for k in range(5):
        a = k * 2 * math.pi / 5 - math.pi / 2
        shapes.append(ellipse(32 + math.cos(a) * 14, 32 + math.sin(a) * 14, 14, 9, WHITE, rot=a))
    shapes.append(ellipse(32, 32, 6, 6, CUT))
    shapes.append(ellipse(32, 32, 3.5, 3.5, WHITE))
    return as_mask(coverage(64, 64, shapes))


def leaf_mark():
    """64x64: a leaf (the marks on toggles, sliders and names)."""
    return as_mask(coverage(64, 64, leaf(10, 54, 60, 17, -0.785, WHITE, WHITE, CUT)))


def ruins_divider():
    """32x8: a carved zigzag along the line under a title."""
    def make(dx, dy):
        return [zigzag(dx - 4, dx + 36, 4, 2.2, 4, 1.2, WHITE)]
    return as_mask(coverage(32, 8, tiled(32, 8, make, ys=False)))


def canopy_divider():
    """32x8: a thin vine with a leaf on it."""
    def make(dx, dy):
        pts = [(x + dx, 4 + 1.2 * math.sin(2 * math.pi * x / 32)) for x in range(-2, 35, 2)]
        return [stroke(pts, 1.1, WHITE)] + leaf(10 + dx, 4, 9, 2.6, -0.5, WHITE, WHITE)
    return as_mask(coverage(32, 8, tiled(32, 8, make, ys=False)))


# --- header bands (in their own colours, repeated along a header) -------------

def ruins_header():
    """128x40: carved stone behind a window's title: blocks of mossy stone,
    dark joints, a carved spiral, moss creeping along the bottom."""
    rng = random.Random(11)
    pal = RUINS
    shapes = []
    blocks = [(0, 0, 40, 20), (40, 0, 88, 20), (88, 0, 128, 20), (-20, 20, 24, 40), (24, 20, 76, 40),
              (76, 20, 108, 40), (108, 20, 148, 40)]
    for x0, y0, x1, y1 in blocks:
        tone = mix(pal["stone_dark"], pal["stone"], rng.uniform(0.35, 0.8))
        shapes.append(polygon([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x1 - 1, y1 - 1), (x0 + 1, y1 - 1)], tone))
        shapes.append(stroke([(x0 + 2, y0 + 1.6), (x1 - 2, y0 + 1.6)], 1.0, mix(tone, pal["stone_light"], 0.6)))
    shapes.append(spiral(64, 30, 6.5, 2.0, 1.6, mix(pal["stone_dark"], hexc("#000000"), 0.3)))
    shapes.append(spiral(64.6, 30.6, 6.5, 2.0, 0.8, mix(pal["stone_light"], pal["ember"], 0.15)))
    for k in range(18):
        x = k * 128 / 18 + rng.uniform(-2, 2)
        drop = rng.uniform(2, 7)
        shapes.append(ellipse(x, 40 - drop / 2, rng.uniform(2.5, 4.5), drop, mix(pal["vine"], pal["leaf_dark"],
                                                                                   rng.uniform(0, 0.6))))
    ground = mix(pal["stone_dark"], hexc("#000000"), 0.35)
    rows = render(128, 40, tiled(128, 40, lambda dx, dy: [_moved(s, dx) for s in shapes], ys=False),
                  background=ground)
    return rows


def _moved(shape, dx):
    if dx == 0:
        return shape
    b = shape.bbox
    return Shape((b[0] + dx, b[1], b[2] + dx, b[3]), lambda x, y, f=shape.fn: f(x - dx, y))


def canopy_header():
    """128x40: leaves behind a window's title, dark and overlapping, a lighter
    edge on the nearest."""
    rng = random.Random(12)
    deep, mid, near = hexc("#0E3022"), hexc("#12402C"), hexc("#185338")
    shapes = []
    for k in range(9):
        x = k * 16 + rng.uniform(-3, 3)
        shapes += leaf(x, 44, rng.uniform(26, 36), rng.uniform(6, 8), -math.pi / 2 + rng.uniform(-0.7, 0.7),
                       mid, deep)
    for k in range(5):
        x = k * 26 + 8 + rng.uniform(-3, 3)
        shapes += leaf(x, 46, rng.uniform(22, 30), rng.uniform(7, 9), -math.pi / 2 + rng.uniform(-0.9, 0.9),
                       near, mid, hexc("#0F3826"))
    ground = hexc("#0A2218")
    return render(128, 40, tiled(128, 40, lambda dx, dy: [_moved(s, dx) for s in shapes], ys=False),
                  background=ground)


# --- the minimap: a vine round it, the parrot -----------------------------------

def ring_vine(pal, flowers=False, seed=5):
    """256x256, stretched round the minimap's disc (its art 6 px past it):
    a vine along the rim over the top left and the bottom right, leaves
    out over the edge."""
    rng = random.Random(seed)
    c, r = 128, 117
    shapes = []
    # (the flowers and berries off the minimap's buttons: zoom at about 30
    # and 40 degrees below the right, the tracking button lower left)
    for a0, a1, bloom in ((math.radians(150), math.radians(275), 0.6), (math.radians(-20), math.radians(70), 0.92)):
        pts = []
        n = 40
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            rr = r + 2.5 * math.sin(k * 0.9)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        shapes.append(vine_line(pts, pal, 4.5))
        for k in range(1, n, 3):
            (x0, y0), (x1, y1) = pts[k], pts[k + 1]
            ang = math.atan2(y1 - y0, x1 - x0)
            out = (k // 3) % 2 == 0
            # leaves outward (over the rim) big, inward small
            a = ang - 0.95 if out else ang + 0.95
            size = 1.0 if out else 0.55
            shapes += leaf(x0, y0, 20 * size * rng.uniform(0.9, 1.15), 6.5 * (0.6 + 0.4 * size), a,
                           pal["leaf_light"], pal["leaf_dark"], pal["vein"], curl=0.05)
        mid = pts[int(n * bloom)]
        if flowers:
            shapes += hibiscus(mid[0], mid[1], 10, pal)
            q = pts[n // 4]
            shapes += orchid(q[0], q[1], 6, pal)
        else:
            shapes.append(ellipse(mid[0], mid[1] + 3, 3, 3, pal["berry"]))
            shapes.append(ellipse(mid[0] + 5, mid[1] + 5, 2.6, 2.6, pal["berry"]))
    return render(256, 256, shapes)


def parrot():
    """64x80: a scarlet macaw perched on a twig, facing left (the Canopy's
    minimap)."""
    red, red_dark = hexc("#D8352B"), hexc("#A8231D")
    yellow, green, blue, blue_dark = hexc("#F2C230"), hexc("#4FA64A"), hexc("#2D6FD0"), hexc("#1F4E9A")
    cream, beak_dark, eye = hexc("#F2EADB"), hexc("#2A2622"), hexc("#141210")
    shapes = []
    # tail: long feathers down and back
    shapes.append(polygon([(36, 48), (44, 50), (46, 79), (40, 79)], lambda x, y: blue if y > 68 else red_dark))
    shapes.append(polygon([(31, 48), (38, 50), (39, 76), (34, 76)], lambda x, y: blue_dark if y > 66 else red))
    # twig and feet
    shapes.append(stroke([(4, 57), (30, 55), (60, 58)], 3.2, hexc("#4A3A26")))
    shapes += leaf(52, 57, 12, 4, 0.5, CANOPY["leaf_light"], CANOPY["leaf_dark"])
    shapes.append(ellipse(25, 54, 3, 2, beak_dark))
    shapes.append(ellipse(31, 54, 3, 2, beak_dark))
    # body
    shapes.append(ellipse(30, 38, 11, 16, lambda u, v: mix(red, red_dark, max(0, min(1, (u + 1) / 2))), rot=-0.25))
    # wing: yellow band, green, blue flight feathers
    def wing(u, v):
        t = (u + 1) / 2
        return yellow if t < 0.3 else green if t < 0.45 else blue if t < 0.85 else blue_dark
    shapes.append(ellipse(35, 40, 7.5, 14, wing, rot=1.35))
    # head, face, eye, beak
    shapes.append(ellipse(24, 20, 9.5, 9, red))
    shapes.append(ellipse(20.5, 20.5, 5.5, 4.5, cream))
    shapes.append(ellipse(21, 19.5, 1.8, 1.8, eye))
    shapes.append(ellipse(21.5, 19, 0.6, 0.6, WHITE))
    shapes.append(polygon([(16, 17), (10, 19), (9, 25), (12, 28), (14, 24), (17, 23)], cream))
    shapes.append(polygon([(13, 24), (17, 23), (17, 27), (13, 27)], beak_dark))
    return render(64, 80, shapes)


# --- the jungle's icons (both themes: white, tinted in game) -------------------
#
# Every one of SuuUI's glyphs (make_textures.GLYPHS, 24 units, stroke 1.9)
# drawn as a vine: its lines a little thicker and gently bent (their ends
# kept where they were, so lines still meet), a leaf or two sprouting
# outward from the longest; a few redrawn outright (a palm for the talents'
# tree, a woven basket for the bags).

GLYPH_PX, GLYPH_BOX = 64, 24.0
GLYPH_REDRAWN = {
    # a palm: a leaning trunk, five fronds, two coconuts
    "tree": "M12.6 21C13 17.6 12.6 14 11.2 10.2M11.2 10.2C9 7.8 6 7.6 3.6 9.6M11.2 10.2C10 7 7.6 5.2 4.8 5"
            "M11.2 10.2C12.4 7.2 15 5.6 18.2 6M11.2 10.2C13.8 8.8 17 9.4 19.8 12M11.2 10.2C11.4 7.4 10.8 5 9.6 3.2"
            "M10.2 12h.01M12.6 12.2h.01",
    # a woven basket with its handle
    "bag": "M5 9.5h14l-1.6 10.5H6.6L5 9.5zM8.5 9.5a3.5 3.5 0 0 1 7 0M5.8 13.2h12.4M6.3 16.6h11.4M10 9.5l.4 10.5M14 9.5l-.4 10.5",
    # a coiled vine
    "swirl": "M12 12.5a1.6 1.6 0 1 1 1.6-1.6 3.4 3.4 0 0 1-3.4 3.4 5 5 0 0 1-5-5 6.6 6.6 0 0 1 6.6-6.6 8 8 0 0 1 8 8",
}


BARE = {"chevronDown", "chevronUp", "chevronLeft", "chevronRight", "check", "dash", "minus", "sort"}


def _length(pts):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


def _resample(pts, step=0.45):
    total = _length(pts)
    if total < 1e-6:
        return list(pts)
    n = max(2, int(total / step))
    out, seg, acc = [], 0, 0.0
    starts = [0.0]
    for a, b in zip(pts, pts[1:]):
        starts.append(starts[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    for k in range(n + 1):
        s = total * k / n
        while seg < len(pts) - 2 and starts[seg + 1] < s:
            seg += 1
        a, b = pts[seg], pts[seg + 1]
        ll = starts[seg + 1] - starts[seg]
        t = 0 if ll == 0 else (s - starts[seg]) / ll
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _wobble(pts, amp, seed):
    """Each point pushed sideways by a slow wave, nothing at the ends."""
    if len(pts) < 3 or amp <= 0:
        return pts
    total = _length(pts) or 1
    out, s = [pts[0]], 0.0
    phase = seed * 1.7
    for i in range(1, len(pts) - 1):
        s += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        tx, ty = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        tl = math.hypot(tx, ty) or 1
        nx, ny = -ty / tl, tx / tl
        off = amp * math.sin(s * 0.45 + phase) * math.sin(math.pi * s / total)
        out.append((pts[i][0] + nx * off, pts[i][1] + ny * off))
    out.append(pts[-1])
    return out


def _sprout(pts, frac, size, width, centre=(12.0, 12.0)):
    """A leaf from the line `frac` along it, outward (away from the
    middle), leaning forward; None if it would leave the box."""
    total = _length(pts)
    target, s = total * frac, 0.0
    for i in range(1, len(pts)):
        s += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        if s >= target:
            break
    x, y = pts[i]
    tx, ty = pts[min(i + 1, len(pts) - 1)][0] - pts[i - 1][0], pts[min(i + 1, len(pts) - 1)][1] - pts[i - 1][1]
    ang_t = math.atan2(ty, tx)
    sides = [1, -1]
    nx, ny = -math.sin(ang_t), math.cos(ang_t)
    if nx * (x - centre[0]) + ny * (y - centre[1]) < 0:
        sides = [-1, 1]
    for scale in (1.0, 0.75):
        for side in sides:
            a = ang_t + side * (math.pi / 2 - 0.55)
            ln = size * scale
            tip = (x + math.cos(a) * ln, y + math.sin(a) * ln)
            if 0.7 <= tip[0] <= GLYPH_BOX - 0.7 and 0.7 <= tip[1] <= GLYPH_BOX - 0.7:
                return x, y, ln, width * scale, a
    return None


def glyph_shapes(name, d):
    k = GLYPH_PX / GLYPH_BOX
    lines = mt.path_polylines(d)
    shapes, drawn = [], []
    for i, line in enumerate(lines):
        total = _length(line)
        if total < 0.05:
            shapes.append(ellipse(line[0][0] * k, line[0][1] * k, 1.2 * k, 1.2 * k, WHITE))
            continue
        pts = _wobble(_resample(line), 0.3 if total > 6 else 0.0, i + len(name))
        drawn.append(pts)
        # (in pieces: each piece only looks at its own few segments)
        for a in range(0, len(pts) - 1, 8):
            chunk = pts[a:a + 9]
            shapes.append(stroke([(x * k, y * k) for x, y in chunk], 1.9 * k, WHITE))
    lengths = sorted(((_length(p), j) for j, p in enumerate(drawn)), reverse=True)
    leaves = 2 if sum(n for n, _ in lengths) > 34 else 1
    # (arrows, the tick, the dash and the raid marks keep their shape: a
    # leaf turned a chevron into a tick)
    if name in BARE or name.startswith("mark"):
        leaves = 0
    for n, (_, j) in enumerate(lengths[:leaves]):
        got = _sprout(drawn[j], 0.55 if n == 0 else 0.3, 6.6 if n == 0 else 5.2, 2.5 if n == 0 else 2.1)
        if got:
            x, y, ln, wd, a = got
            shapes += leaf(x * k, y * k, ln * k, wd * k, a, WHITE, WHITE, curl=0.04)
    return shapes


def jungle_glyph(name):
    d = GLYPH_REDRAWN.get(name) or mt.GLYPHS[name]
    return as_mask(coverage(GLYPH_PX, GLYPH_PX, glyph_shapes(name, d)))


GLYPH_NAMES = sorted(mt.GLYPHS)


def write_glyphs(names):
    out = os.path.join(OUT, "Glyphs")
    os.makedirs(out, exist_ok=True)
    for name in names:
        write_rgba_tga(os.path.join(out, name + ".tga"), jungle_glyph(name))
    print("wrote", len(names), "glyphs to", os.path.relpath(out, ROOT))


def glyph_sheet(path, names):
    """Every glyph at 64 px, cream on the dark ground, 12 a row."""
    per, cell = 12, 72
    rows_n = (len(names) + per - 1) // per
    ground = (0x16, 0x1C, 0x15)
    canvas = [[ground + (255,)] * (per * cell) for _ in range(rows_n * cell)]
    for idx, name in enumerate(names):
        img = jungle_glyph(name)
        ox, oy = (idx % per) * cell + 4, (idx // per) * cell + 4
        for y, row in enumerate(img):
            for x, (_, _, _, a) in enumerate(row):
                t = a / 255
                canvas[oy + y][ox + x] = (round(236 * t + ground[0] * (1 - t)), round(231 * t + ground[1] * (1 - t)),
                                          round(210 * t + ground[2] * (1 - t)), 255)
    write_png(path, canvas)
    print("wrote", path)


def write(name, rows):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    write_rgba_tga(path, rows)
    print("wrote", os.path.relpath(path, ROOT))


ART = {
    "RuinsVineTop": lambda: vine_top(RUINS),
    "RuinsVineSmall": lambda: vine_top(RUINS, h=32),
    "RuinsCorner": lambda: corner_clump(RUINS),
    "RuinsSide": lambda: side_drop(RUINS),
    "CanopyVineTop": lambda: vine_top(CANOPY, flowers=True),
    "CanopyVineSmall": lambda: vine_top(CANOPY, flowers=True, h=32),
    "CanopyCorner": lambda: corner_clump(CANOPY, flowers=True),
    "CanopySide": lambda: side_drop(CANOPY, flowers=True),
    "Firefly": firefly,
    "RuinsHeader": ruins_header,
    "CanopyHeader": canopy_header,
    "RuinsRing": lambda: ring_vine(RUINS),
    "CanopyRing": lambda: ring_vine(CANOPY, flowers=True),
    "Parrot": parrot,
    "RuinsPattern": ruins_pattern,
    "CanopyPattern": canopy_pattern,
    "RuinsTrack": ruins_track,
    "CanopyTrack": canopy_track,
    "VineBar": lambda: vine_bar(32),
    "VineBarThin": lambda: vine_bar(16),
    "RibBar": lambda: rib_bar(32),
    "RibBarThin": lambda: rib_bar(16),
    "CarvedEdge": carved_edge,
    "SpiralCorner": spiral_corner,
    "LeafCorner": leaf_corner,
    "EyeJewel": eye_jewel,
    "OrchidJewel": orchid_jewel,
    "LeafMark": leaf_mark,
    "RuinsDivider": ruins_divider,
    "CanopyDivider": canopy_divider,
}


def sheet(path, names):
    """The art side by side on a dark ground, each at 2x."""
    imgs = [(n, ART[n]()) for n in names]
    pad, zoom = 16, 2
    width = pad + sum(len(r[0]) * zoom + pad for _, r in imgs)
    height = pad * 2 + max(len(r) * zoom for _, r in imgs)
    ground = (0x16, 0x1C, 0x15)
    canvas = [[ground + (255,)] * width for _ in range(height)]
    x = pad
    for _, rows in imgs:
        for y, row in enumerate(rows):
            for xx, (r, g, b, a) in enumerate(row):
                t = a / 255
                col = (round(r * t + ground[0] * (1 - t)), round(g * t + ground[1] * (1 - t)),
                       round(b * t + ground[2] * (1 - t)), 255)
                for zy in range(zoom):
                    for zx in range(zoom):
                        canvas[pad + y * zoom + zy][x + xx * zoom + zx] = col
        x += len(rows[0]) * zoom + pad
    write_png(path, canvas)
    print("wrote", path)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--glyphs"]:
        write_glyphs(args[1:] or GLYPH_NAMES)
        return
    if args[:1] == ["--glyph-sheet"]:
        glyph_sheet(args[1], args[2:] or GLYPH_NAMES)
        return
    if args[:1] == ["--sheet"]:
        sheet(args[1], args[2:] or list(ART))
        return
    for name, make in ART.items():
        if args and name not in args:
            continue
        write(name, make())


if __name__ == "__main__":
    main()
