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


def vine_top(pal, flowers=False, seed=1):
    """256x48, tiled along a window's top: a vine waving across (it meets
    itself at the edges: a whole sine) on the window's edge (row 32), big
    leaves rising over it, small ones dipping under it (they keep off the
    title)."""
    rng = random.Random(seed)
    w, h = 256, 48
    pts = [(x, VINE_Y + 4 * math.sin(2 * math.pi * x / w)) for x in range(-8, w + 9, 4)]
    shapes = [vine_line(pts, pal, 4.2)]
    shapes += leaves_along(pts[2:-2], pal, 3, 20, 6.4, rng, down=0.5)
    if flowers:
        for x in (52, 180):
            y = VINE_Y + 4 * math.sin(2 * math.pi * x / w)
            shapes += hibiscus(x, y - 4, 9, pal)
        for x in (118, 236):
            y = VINE_Y + 4 * math.sin(2 * math.pi * x / w)
            shapes += orchid(x, y - 5, 5.5, pal)
    else:
        for x in (64, 196):
            y = VINE_Y + 4 * math.sin(2 * math.pi * x / w)
            shapes.append(ellipse(x, y + 5, 2.6, 2.6, pal["berry"]))
            shapes.append(ellipse(x + 4, y + 6, 2.2, 2.2, pal["berry"]))
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


def write(name, rows):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    write_rgba_tga(path, rows)
    print("wrote", os.path.relpath(path, ROOT))


ART = {
    "RuinsVineTop": lambda: vine_top(RUINS),
    "RuinsCorner": lambda: corner_clump(RUINS),
    "RuinsSide": lambda: side_drop(RUINS),
    "CanopyVineTop": lambda: vine_top(CANOPY, flowers=True),
    "CanopyCorner": lambda: corner_clump(CANOPY, flowers=True),
    "CanopySide": lambda: side_drop(CANOPY, flowers=True),
    "Firefly": firefly,
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
    if args[:1] == ["--sheet"]:
        sheet(args[1], args[2:] or list(ART))
        return
    for name, make in ART.items():
        if args and name not in args:
            continue
        write(name, make())


if __name__ == "__main__":
    main()
