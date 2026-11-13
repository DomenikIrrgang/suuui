#!/usr/bin/env python3
"""Generate the raid themes' art (asked 2026-11-13: three themes for each of
SuuUI's five raids, using every capability a theme has; the user took all
fifteen concepts) into Media/Textures/Themes/Raids/<Theme>. Standard
library only: the shapes and the rasteriser are tools/stv_art.py's, with a
renderer that blends translucent shapes (glows, light).

    python3 -I tools/raid_art.py                           every theme's art
    python3 -I tools/raid_art.py KarazhanOpera ...         only these themes
    python3 -I tools/raid_art.py --glyphs KarazhanOpera    their 95 glyphs
    python3 -I tools/raid_art.py --sheet KarazhanOpera out.png
    python3 -I tools/raid_art.py --check                   the colours' ratios

Coloured art (the dress: headers, pieces, rings) is drawn in its own
colours; masks (patterns, bars, edges, ornaments, motes, glyphs) are white
with alpha, tinted by a colour token in game.

The unit frames' dress stays small (the user, 2026-11-13: Stranglethorn's
vines were too big and crowded): at most about 12 px over the frame, one or
two small motifs, nothing over the name or the bar's middle.
"""

import math
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_textures as mt  # noqa: E402
import stv_art as sa  # noqa: E402
from stv_art import (Shape, ellipse, polygon, stroke, bez, hexc, mix, leaf, leaf_points, WHITE, CUT,  # noqa: E402
                     white, as_mask, as_shade, tiled, spiral, _moved, write_rgba_tga, write_png)

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Media", "Textures", "Themes", "Raids")
TAU = 2 * math.pi


# --- colours -------------------------------------------------------------------

def c(h, a=255):
    return hexc(h, a)


def fade(col, a):
    return (col[0], col[1], col[2], max(1, min(255, round(255 * a))))


def dark(col, t):
    return mix(col, (0, 0, 0, col[3]), t)


def light(col, t):
    return mix(col, (255, 255, 255, col[3]), t)


def clamp(t, a=0.0, b=1.0):
    return max(a, min(b, t))


def ramp(stops, t):
    """A colour along stops [(t, colour), ...]."""
    t = clamp(t)
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, 0 if t1 == t0 else (t - t0) / (t1 - t0))
    return stops[-1][1]


# --- rendering: shapes blended front to back ---------------------------------------

def render(w, h, shapes, ss=3, background=(0, 0, 0, 0)):
    """RGBA rows; each sample blends the shapes over it from the top down
    (a translucent glow shows what's under it), stopping at an opaque one;
    CUT (alpha 0) makes a hole through everything under it."""
    rows = []
    inv = 1.0 / ss
    n = ss * ss
    bg_a = background[3] / 255.0
    for py in range(h):
        row = []
        cand_y = [s for s in shapes if s.bbox[1] - 1 <= py + 1 and s.bbox[3] + 1 >= py]
        for px in range(w):
            cand = [s for s in cand_y if s.bbox[0] - 1 <= px + 1 and s.bbox[2] + 1 >= px]
            if not cand:
                row.append(background)
                continue
            cand.reverse()
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x, y = px + (sx + 0.5) * inv, py + (sy + 0.5) * inv
                    cr = cg = cb = 0.0
                    tr = 1.0
                    hole = False
                    for s in cand:
                        col = s.fn(x, y)
                        if col is None:
                            continue
                        if col[3] == 0:
                            hole = True
                            break
                        al = col[3] / 255.0
                        k = al * tr
                        cr += col[0] * k
                        cg += col[1] * k
                        cb += col[2] * k
                        tr *= 1 - al
                        if tr < 0.004:
                            break
                    if not hole and tr > 0 and bg_a > 0:
                        k = bg_a * tr
                        cr += background[0] * k
                        cg += background[1] * k
                        cb += background[2] * k
                        tr *= 1 - bg_a
                    if hole:
                        tr = 1.0
                        cr = cg = cb = 0.0
                    r += cr
                    g += cg
                    b += cb
                    a += 1 - tr
            if a <= 0:
                row.append((0, 0, 0, 0))
            else:
                row.append((round(r / a), round(g / a), round(b / a), round(255 * a / n)))
        rows.append(row)
    return rows


def band(w, h, shapes, ground=None):
    """Art that repeats left to right (headers, spans): its shapes again a
    tile to each side, so what crosses an edge comes back on the other."""
    out = []
    for dx in (-w, 0, w):
        out += [_moved(s, dx) for s in shapes]
    return render(w, h, out, background=ground or (0, 0, 0, 0))


def coverage(w, h, shapes, ss=3):
    return [[px[3] / 255 for px in row] for row in sa.render(w, h, shapes, ss)]


def mask(w, h, shapes, strength=1.0):
    return as_mask(coverage(w, h, shapes), strength)


def pattern(w, h, make, strength):
    return as_mask(coverage(w, h, tiled(w, h, make)), strength)


def bar(h, make, shade=0.64):
    """256 x h: a bar's fill, its motif `shade` white (names keep their
    contrast over the darker motif), repeated along the bar."""
    return as_shade(coverage(256, h, tiled(256, h, make, ys=False)), shade)


def edge(seq):
    """8x8: a panel's edge, its first row (top, bottom) and column (sides)."""
    return [[(255, 255, 255, seq[y] if x == 0 else seq[x]) for x in range(8)] for y in range(8)]


def soft(size, shapes, glow=0.7, power=2.2):
    """A mote: the shapes, over a soft glow round the middle."""
    cov = coverage(size, size, shapes) if shapes else [[0] * size for _ in range(size)]
    out = []
    for y in range(size):
        row = []
        for x in range(size):
            d = math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2) / (size / 2)
            g = glow * max(0.0, 1 - d) ** power
            row.append((255, 255, 255, round(255 * min(1.0, max(cov[y][x], g)))))
        out.append(row)
    return out


# --- shapes ----------------------------------------------------------------------

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def regular(cx, cy, r, n, rot=0.0, ry=None):
    ry = ry or r
    return [(cx + math.cos(rot + k * TAU / n) * r, cy + math.sin(rot + k * TAU / n) * ry) for k in range(n)]


def star(cx, cy, ro, ri, n, rot=-math.pi / 2):
    pts = []
    for k in range(2 * n):
        r = ro if k % 2 == 0 else ri
        a = rot + k * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def turn(pts, cx, cy, ang):
    ca, sn = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * ca - (y - cy) * sn, cy + (x - cx) * sn + (y - cy) * ca) for x, y in pts]


def flip_x(pts, w):
    return [(w - x, y) for x, y in pts]


def glow(cx, cy, rx, col, strength=1.0, ry=None, power=2.0):
    ry = ry or rx

    def fn(x, y):
        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
        if d >= 1:
            return None
        a = strength * (1 - math.sqrt(d)) ** power
        if a < 0.004:
            return None
        return (col[0], col[1], col[2], max(1, round(255 * a)))
    return Shape((cx - rx, cy - ry, cx + rx, cy + ry), fn)


def glow_line(pts, width, col, strength=1.0, power=1.6):
    def color(d):
        return (col[0], col[1], col[2], max(1, round(255 * strength * (1 - d) ** power)))
    return stroke(pts, width, color)


def annulus(cx, cy, rx, ry, t, col, rot=0.0):
    """A ring (a chain link face on): between the ellipse and one t inside."""
    ca, sn = math.cos(rot), math.sin(rot)
    r = max(rx, ry)

    def fn(x, y):
        dx, dy = x - cx, y - cy
        u, v = dx * ca + dy * sn, -dx * sn + dy * ca
        if (u / rx) ** 2 + (v / ry) ** 2 > 1:
            return None
        if rx > t and ry > t and (u / (rx - t)) ** 2 + (v / (ry - t)) ** 2 < 1:
            return None
        return col(u / rx, v / ry) if callable(col) else col
    return Shape((cx - r, cy - r, cx + r, cy + r), fn)


def vesica(cx, cy, w, h, rot=0.0, n=28):
    """A pointed oval (the draenei lens), its points up and down."""
    pts = []
    for k in range(n + 1):
        t = -1 + 2 * k / n
        pts.append((cx + w / 2 * (1 - abs(t) ** 1.5), cy + t * h / 2))
    for k in range(n - 1, 0, -1):
        t = -1 + 2 * k / n
        pts.append((cx - w / 2 * (1 - abs(t) ** 1.5), cy + t * h / 2))
    return turn(pts, cx, cy, rot) if rot else pts


def flame_pts(x, y, h, w, lean=0.0, wave=0.0, n=18):
    """A flame tongue from its base (x, y) up to a tip h above: a round
    bottom, widest a quarter up, a wavering point."""
    left, right = [], []
    for k in range(n + 1):
        t = k / n
        half = w / 2 * (1 - t) ** 0.85 * math.sin(math.pi / 2 * min(1.0, t / 0.26 + 0.08)) ** 0.6
        mid = x + lean * h * t * t + wave * w * math.sin(t * math.pi * 1.6) * t
        yy = y - h * t
        right.append((mid + half, yy))
        left.append((mid - half, yy))
    return right + left[::-1]


def flame(x, y, h, w, cols, lean=0.0, wave=0.0):
    """Outer tongue (base to tip colour), inner tongue, core."""
    outer_base, outer_tip, inner, core = cols
    return [
        polygon(flame_pts(x, y, h, w, lean, wave), lambda px, py: mix(outer_base, outer_tip, clamp((y - py) / h))),
        polygon(flame_pts(x, y - h * 0.02, h * 0.64, w * 0.56, lean * 0.8, wave * 0.6), inner),
        polygon(flame_pts(x, y - h * 0.03, h * 0.32, w * 0.28, lean * 0.5, 0), core),
    ]


def crystal_pts(cx, cy, length, width, ang):
    """An elongated hexagon: a crystal, pointed both ends."""
    pts = [(length / 2, 0), (length * 0.28, width / 2), (-length * 0.3, width / 2), (-length / 2, 0),
           (-length * 0.3, -width / 2), (length * 0.28, -width / 2)]
    ca, sn = math.cos(ang), math.sin(ang)
    return [(cx + u * ca - v * sn, cy + u * sn + v * ca) for u, v in pts]


def crystal(cx, cy, length, width, ang, lit, shade, glint=None):
    """A crystal: its lit half and its shaded half, a glint along the lit."""
    p = crystal_pts(cx, cy, length, width, ang)
    out = [polygon([p[0], p[1], p[2], p[3]], lit), polygon([p[3], p[4], p[5], p[0]], shade)]
    if glint:
        ca, sn = math.cos(ang), math.sin(ang)
        a = (cx + length * 0.22 * ca - width * 0.22 * sn, cy + length * 0.22 * sn + width * 0.22 * ca)
        b = (cx - length * 0.2 * ca - width * 0.22 * sn, cy - length * 0.2 * sn + width * 0.22 * ca)
        out.append(stroke([a, b], max(0.7, width * 0.12), glint))
    return out


def feather(x, y, length, width, ang, base, tip, quill, curl=0.0, barbs=3):
    """A feather from its quill's end (x, y): the vane from base to tip
    colour, the quill down its middle, a few splits in the vane."""
    pts = leaf_points(x, y, length, width, ang, curl)
    ca, sn = math.cos(ang), math.sin(ang)

    def color(px, py):
        u = ((px - x) * ca + (py - y) * sn) / length
        return mix(base, tip, clamp(u * 1.15))
    out = [polygon(pts, color)]
    split = dark(base, 0.45)
    for k in range(barbs):
        u = length * (0.35 + 0.5 * k / max(1, barbs))
        side = 1 if k % 2 == 0 else -1
        v0 = side * width * 0.95 * math.sin(math.pi * u / length) ** 0.8
        a = (x + u * ca - v0 * sn, y + u * sn + v0 * ca)
        u1, v1 = u - length * 0.08, v0 * 0.35
        b = (x + u1 * ca - v1 * sn, y + u1 * sn + v1 * ca)
        out.append(stroke([a, b], max(0.6, width * 0.14), split))
    qa = (x - ca * length * 0.06, y - sn * length * 0.06)
    qb = (x + ca * length * 0.92, y + sn * length * 0.92)
    out.append(stroke([qa, qb], max(0.7, width * 0.16), quill))
    return out


def bone(x0, y0, x1, y1, w, col, edge_col=None):
    """A bone: its shaft, two knobs at each end (edge_col: an outline)."""
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)
    ux, uy = math.cos(ang), math.sin(ang)
    out = []
    for col_, grow in ((edge_col, 0.9), (col, 0.0)):
        if col_ is None:
            continue
        out.append(stroke([(x0, y0), (x1, y1)], w + grow, col_))
        for (ex, ey, s) in ((x0, y0, 1), (x1, y1, -1)):
            for side in (1, -1):
                cx = ex + nx * side * w * 0.55 + ux * s * w * 0.15
                cy = ey + ny * side * w * 0.55 + uy * s * w * 0.15
                r = w * 0.62 + grow / 2
                out.append(ellipse(cx, cy, r, r, col_))
    return out


RUNE_PARTS = [
    [(0.5, 0.18), (0.88, 0.45)], [(0.5, 0.18), (0.12, 0.45)], [(0.5, 0.55), (0.88, 0.82)],
    [(0.5, 0.55), (0.12, 0.82)], [(0.5, 0.0), (0.88, 0.28)], [(0.12, 0.3), (0.5, 0.52), (0.88, 0.3)],
    [(0.5, 0.38), (0.88, 0.38), (0.88, 0.62)], [(0.12, 0.7), (0.5, 0.9)], [(0.5, 0.25), (0.15, 0.1)],
]


def rune_strokes(rng):
    """An invented rune in a unit box: a stave and two branches."""
    parts = rng.sample(RUNE_PARTS, 2)
    return [[(0.5, 0.0), (0.5, 1.0)]] + parts


def draw_rune(cx, cy, s, strokes, width, col):
    return [stroke([(cx + (x - 0.5) * s * 0.8, cy + (y - 0.5) * s) for x, y in line], width, col)
            for line in strokes]


def web(cx, cy, a0, a1, spokes, radii, col, width=0.9, sag=0.22):
    """A web from (cx, cy): spokes from a0 to a1 (radians), threads between
    them at each radius, sagging toward the middle."""
    out = []
    angs = [a0 + (a1 - a0) * k / (spokes - 1) for k in range(spokes)]
    far = radii[-1] * 1.12
    for a in angs:
        out.append(stroke([(cx, cy), (cx + math.cos(a) * far, cy + math.sin(a) * far)], width, col))
    for r in radii:
        for a, b in zip(angs, angs[1:]):
            p = (cx + math.cos(a) * r, cy + math.sin(a) * r)
            q = (cx + math.cos(b) * r, cy + math.sin(b) * r)
            m = (cx + math.cos((a + b) / 2) * r * (1 - sag), cy + math.sin((a + b) / 2) * r * (1 - sag))
            out.append(stroke(bez(p, m, m, q, 8), width * 0.85, col))
    return out


def spider(x, y, s, body, eye):
    """A spider hanging (its back up), centred at (x, y), s its size."""
    out = []
    for side in (1, -1):
        for k, (a, b) in enumerate(((-0.9, -1.6), (-0.3, -0.7), (0.3, 0.6), (0.8, 1.5))):
            p0 = (x, y)
            p1 = (x + side * s * 0.55, y + a * s * 0.45)
            p2 = (x + side * s * 0.95, y + b * s * 0.45)
            out.append(stroke([p0, p1, p2], max(0.7, s * 0.09), body))
    out.append(ellipse(x, y + s * 0.42, s * 0.42, s * 0.5, body))
    out.append(ellipse(x, y - s * 0.12, s * 0.26, s * 0.24, body))
    out.append(ellipse(x - s * 0.09, y - s * 0.2, s * 0.06, s * 0.06, eye))
    out.append(ellipse(x + s * 0.09, y - s * 0.2, s * 0.06, s * 0.06, eye))
    return out


def crack_walk(rng, x, y, ang, length, step=3.0, turn_=0.55):
    pts = [(x, y)]
    walked = 0.0
    while walked < length:
        ang += rng.uniform(-turn_, turn_)
        x += math.cos(ang) * step
        y += math.sin(ang) * step
        pts.append((x, y))
        walked += step
    return pts


def lava_crack(pts, width, glow_col, hot_col, core_col):
    return [glow_line(pts, width * 3.2, glow_col, 0.55), stroke(pts, width, hot_col),
            stroke(pts, max(0.5, width * 0.4), core_col)]


def rim(x):
    """The minimap's edge in a 256 ring drawn `x` px past its 176 disc."""
    return 128 * 88 / (88 + x)


def clear(deg):
    """An angle on the minimap's rim (degrees, y down) that art keeps off:
    the zoom buttons, the clock under it, the tracking button, the N."""
    deg %= 360
    return 15 <= deg <= 55 or 75 <= deg <= 105 or 135 <= deg <= 162 or 258 <= deg <= 282


def polar(cx, cy, r, a):
    return (cx + math.cos(a) * r, cy + math.sin(a) * r)


def arc_pts(cx, cy, r, a0, a1, n=48):
    return [polar(cx, cy, r, a0 + (a1 - a0) * k / n) for k in range(n + 1)]


# ======================================================================================
# The glyphs: 15 treatments of SuuUI's 95 line icons (make_textures.GLYPHS,
# 24 units, stroke 1.9), white, tinted in game. Arrows, the tick, the dash
# and the raid marks keep their plain shape (nothing sprouting off them).
# ======================================================================================

GK = 64 / 24.0
BOX = 24.0
BARE = sa.BARE


def _scaled(pts):
    return [(x * GK, y * GK) for x, y in pts]


def _strokes(pts, w):
    out = []
    for a in range(0, max(1, len(pts) - 1), 8):
        chunk = pts[a:a + 9]
        if len(chunk) >= 2:
            out.append(stroke(_scaled(chunk), w * GK, WHITE))
    return out


def _dot(x, y, r, col=WHITE):
    return ellipse(x * GK, y * GK, r * GK, r * GK, col)


def _lines(name):
    return mt.path_polylines(mt.GLYPHS[name])


def _closed(line):
    return math.hypot(line[0][0] - line[-1][0], line[0][1] - line[-1][1]) < 0.2


def _tangent(pts, i):
    a, b = pts[max(0, i - 2)], pts[min(len(pts) - 1, i + 2)]
    return math.atan2(b[1] - a[1], b[0] - a[0])


def _at(pts, frac):
    total = sa._length(pts)
    target, s = total * frac, 0.0
    for i in range(1, len(pts)):
        s += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        if s >= target:
            return i
    return len(pts) - 1


def _inside(x, y, m=0.7):
    return m <= x <= BOX - m and m <= y <= BOX - m


def _free(lines, x, y, r):
    for line in lines:
        for px, py in line:
            if math.hypot(px - x, py - y) < r:
                return False
    return True


def _plain(name, w=1.9, step=0.45):
    """The glyph's lines resampled, stroked at w; its dots."""
    shapes, drawn = [], []
    for line in _lines(name):
        if sa._length(line) < 0.05:
            shapes.append(_dot(line[0][0], line[0][1], w * 0.63))
            continue
        pts = sa._resample(line, step)
        drawn.append(pts)
        shapes += _strokes(pts, w)
    return shapes, drawn


def _outward(pts, i, centre=(12.0, 12.0)):
    """The normal at pts[i] that points away from the middle."""
    ang = _tangent(pts, i)
    nx, ny = -math.sin(ang), math.cos(ang)
    x, y = pts[i]
    if nx * (x - centre[0]) + ny * (y - centre[1]) < 0:
        nx, ny = -nx, -ny
    return ang, nx, ny


def _corner_free(drawn, r, spots=((20.0, 4.0), (4.0, 4.0), (20.0, 20.0), (4.0, 20.0))):
    for x, y in spots:
        if _free(drawn, x, y, r):
            return x, y
    return None


def g_calligraphy(name):
    """A broad nib at 45 degrees: strokes across it thick, along it thin."""
    nib = math.pi / 4
    shapes = []
    for line in _lines(name):
        if sa._length(line) < 0.05:
            shapes.append(_dot(line[0][0], line[0][1], 1.25))
            continue
        pts = sa._resample(line, 0.35)
        for i in range(0, len(pts) - 1, 2):
            seg = pts[i:i + 3]
            a = math.atan2(seg[-1][1] - seg[0][1], seg[-1][0] - seg[0][0])
            w = 1.9 * (0.3 + 1.1 * abs(math.sin(a - nib)))
            shapes.append(stroke(_scaled(seg), w * GK, WHITE))
    return shapes


def g_outline(name):
    """Inlaid: each line drawn as two fine lines (a gilt inlay)."""
    outer, inner = [], []
    for line in _lines(name):
        if sa._length(line) < 0.05:
            outer.append(_dot(line[0][0], line[0][1], 1.6))
            inner.append(_dot(line[0][0], line[0][1], 0.5, CUT))
            continue
        pts = sa._resample(line, 0.45)
        outer += _strokes(pts, 3.1)
        inner += [stroke(_scaled(pts[a:a + 9]), 1.05 * GK, CUT) for a in range(0, len(pts) - 1, 8)
                  if len(pts[a:a + 9]) >= 2]
    return outer + inner


def g_constellation(name):
    """Fine lines, a star at each end and corner."""
    shapes, drawn = _plain(name, 1.25)
    for pts in drawn:
        nodes = [] if _closed(pts) else [pts[0], pts[-1]]
        last = -99
        for i in range(3, len(pts) - 3):
            a = math.atan2(pts[i][1] - pts[i - 3][1], pts[i][0] - pts[i - 3][0])
            b = math.atan2(pts[i + 3][1] - pts[i][1], pts[i + 3][0] - pts[i][0])
            d = abs((b - a + math.pi) % TAU - math.pi)
            if d > 0.75 and i - last > 5:
                nodes.append(pts[i])
                last = i
        for x, y in nodes:
            shapes.append(_dot(x, y, 1.45))
    return shapes


def g_sparkle(name):
    """SuuUI's line, a four-point sparkle in a free corner."""
    shapes, drawn = _plain(name, 1.9)
    if name not in BARE and not name.startswith("mark"):
        spot = _corner_free(drawn, 4.1)
        if spot:
            x, y = spot
            shapes.append(polygon(_scaled(star(x, y, 3.1, 0.9, 4, 0)), WHITE))
    return shapes


def g_feather(name):
    """A small feather sprouting from the longest line or two."""
    shapes, drawn = _plain(name, 1.9)
    if name in BARE or name.startswith("mark"):
        return shapes
    lengths = sorted(((sa._length(p), j) for j, p in enumerate(drawn)), reverse=True)
    count = 2 if sum(n for n, _ in lengths) > 34 else 1
    for n, (_, j) in enumerate(lengths[:count]):
        got = sa._sprout(drawn[j], 0.55 if n == 0 else 0.3, 7.4 if n == 0 else 5.8, 1.9 if n == 0 else 1.6)
        if got:
            x, y, ln, wd, a = got
            pts = leaf_points(x * GK, y * GK, ln * GK, wd * GK, a, 0.05)
            shapes.append(polygon(pts, WHITE))
            for f in (0.45, 0.7):
                ux, uy = math.cos(a), math.sin(a)
                px, py = x + ux * ln * f, y + uy * ln * f
                nx, ny = -uy, ux
                shapes.append(stroke(_scaled([(px + nx * wd * 0.9, py + ny * wd * 0.9),
                                              (px - ux * 0.9 + nx * 0.2, py - uy * 0.9 + ny * 0.2)]), 0.55 * GK, CUT))
    return shapes


def _faceted(name, w, step):
    shapes, drawn = [], []
    for line in _lines(name):
        total = sa._length(line)
        if total < 0.05:
            shapes.append(polygon(_scaled(regular(line[0][0], line[0][1], w * 0.75, 4, math.pi / 4)), WHITE))
            continue
        n = max(1, round(total / step))
        pts = sa._resample(line, total / n)
        drawn.append(pts)
        shapes += _strokes(pts, w)
    return shapes, drawn


def g_faceted(name):
    """Cut like basalt: every curve in straight facets."""
    return _faceted(name, 2.1, 2.6)[0]


def g_crystal(name):
    """Faceted lines, a crystal shard in a free corner."""
    shapes, drawn = _faceted(name, 1.9, 2.4)
    if name not in BARE and not name.startswith("mark"):
        spot = _corner_free(drawn, 3.8)
        if spot:
            x, y = spot
            shapes.append(polygon(_scaled([(x, y - 3.2), (x + 1.8, y), (x, y + 3.2), (x - 1.8, y)]), WHITE))
    return shapes


def g_cracked(name):
    """Broken stone: a crack through each long line."""
    shapes, drawn = _plain(name, 2.2)
    for pts in drawn:
        total = sa._length(pts)
        fracs = [0.37] + ([0.72] if total > 14 else []) if total > 7 else []
        for f in fracs:
            i = _at(pts, f)
            ang = _tangent(pts, i) + 1.1
            x, y = pts[i]
            ux, uy = math.cos(ang), math.sin(ang)
            crack = [(x - ux * 1.8, y - uy * 1.8), (x + uy * 0.35, y - ux * 0.35), (x + ux * 1.8, y + uy * 1.8)]
            shapes.append(stroke(_scaled(crack), 0.6 * GK, CUT))
    return shapes


def g_riveted(name):
    """Forged iron: heavier lines, a rivet at each end."""
    shapes, drawn = _plain(name, 2.3)
    if name in BARE:
        return shapes
    for pts in drawn:
        if not _closed(pts) and sa._length(pts) > 2.5:
            for x, y in (pts[0], pts[-1]):
                shapes.append(_dot(clamp(x, 1.6, BOX - 1.6), clamp(y, 1.6, BOX - 1.6), 1.6))
    return shapes


def g_runic(name):
    """Carved runes: faceted lines, a branch cut off the longest."""
    shapes, drawn = _faceted(name, 2.0, 2.4)
    if name in BARE or name.startswith("mark"):
        return shapes
    lengths = sorted(((sa._length(p), j) for j, p in enumerate(drawn)), reverse=True)
    for n, (total, j) in enumerate(lengths[:2]):
        if total < 6:
            continue
        pts = drawn[j]
        i = _at(pts, 0.5 if n == 0 else 0.3)
        ang, nx, ny = _outward(pts, i)
        x, y = pts[i]
        bx, by = math.cos(ang), math.sin(ang)
        tip = (x + nx * 2.8 - bx * 1.8, y + ny * 2.8 - by * 1.8)
        if _inside(*tip):
            shapes.append(stroke(_scaled([(x, y), tip]), 1.6 * GK, WHITE))
    return shapes


def g_jagged(name):
    """Rock: every line a little jagged."""
    shapes = []
    for line in _lines(name):
        total = sa._length(line)
        if total < 0.05:
            shapes.append(polygon(_scaled(regular(line[0][0], line[0][1], 1.4, 5, 0.3)), WHITE))
            continue
        pts = sa._resample(line, 1.15)
        out = [pts[0]]
        for i in range(1, len(pts) - 1):
            ang = _tangent(pts, i)
            off = 0.42 * (1 if i % 2 else -1)
            out.append((pts[i][0] - math.sin(ang) * off, pts[i][1] + math.cos(ang) * off))
        out.append(pts[-1])
        shapes += _strokes(out, 2.0)
    return shapes


def g_flame(name):
    """A flame licking up off the top of the icon."""
    shapes, drawn = _plain(name, 1.9)
    if name in BARE or name.startswith("mark"):
        return shapes
    pts = sorted((p for line in drawn for p in line), key=lambda p: p[1])
    total = sum(sa._length(p) for p in drawn)
    want = 2 if total > 34 else 1
    placed = []
    for x, y in pts:
        if len(placed) >= want:
            break
        if any(abs(x - px) < 6.5 for px, _ in placed):
            continue
        h = 5.0
        if y - h < 0.6 or not (2.2 <= x <= BOX - 2.2):
            continue
        placed.append((x, y))
        shapes.append(polygon(_scaled(flame_pts(x, y + 0.6, h + 0.6, 2.6, 0.25, 0.25)), WHITE))
    return shapes


def g_spiked(name):
    """Necropolis iron: thorns along the longest line."""
    shapes, drawn = _plain(name, 1.9)
    if name in BARE or name.startswith("mark") or not drawn:
        return shapes
    lengths = sorted(((sa._length(p), j) for j, p in enumerate(drawn)), reverse=True)
    pts = drawn[lengths[0][1]]
    fracs = (0.25, 0.55, 0.85) if lengths[0][0] > 20 else (0.35, 0.7)
    for f in fracs:
        i = _at(pts, f)
        ang, nx, ny = _outward(pts, i)
        x, y = pts[i]
        bx, by = math.cos(ang), math.sin(ang)
        tip = (x + nx * 2.7 + bx * 0.7, y + ny * 2.7 + by * 0.7)
        if not _inside(*tip):
            continue
        shapes.append(polygon(_scaled([(x - bx * 1.0, y - by * 1.0), (x + bx * 1.0, y + by * 1.0), tip]), WHITE))
    return shapes


def g_bone(name):
    """Bones: knobbed ends on every open line."""
    shapes, drawn = _plain(name, 1.8)
    if name in BARE or name.startswith("mark"):
        return shapes
    for pts in drawn:
        if _closed(pts) or sa._length(pts) < 2.5:
            continue
        for end, nxt in ((pts[0], pts[min(3, len(pts) - 1)]), (pts[-1], pts[max(0, len(pts) - 4)])):
            ang = math.atan2(nxt[1] - end[1], nxt[0] - end[0])
            nx, ny = -math.sin(ang), math.cos(ang)
            for side in (1, -1):
                x = end[0] + nx * side * 0.85 - math.cos(ang) * 0.2
                y = end[1] + ny * side * 0.85 - math.sin(ang) * 0.2
                shapes.append(_dot(clamp(x, 1.2, BOX - 1.2), clamp(y, 1.2, BOX - 1.2), 1.15))
    return shapes


def g_frost(name):
    """Frost: fine lines, ice crystals branching off them."""
    shapes, drawn = _plain(name, 1.7)
    if name in BARE or name.startswith("mark"):
        return shapes
    budget = 6
    for pts in sorted(drawn, key=sa._length, reverse=True):
        total = sa._length(pts)
        if total < 6 or budget <= 0:
            continue
        s = 2.2
        made = 0
        while s < total - 1.5 and made < 3 and budget > 0:
            i = _at(pts, s / total)
            ang = _tangent(pts, i)
            x, y = pts[i]
            for side in (1, -1):
                a = ang + math.pi + side * 0.75
                tip = (x + math.cos(a) * 1.6, y + math.sin(a) * 1.6)
                if _inside(*tip):
                    shapes.append(stroke(_scaled([(x, y), tip]), 0.85 * GK, WHITE))
            s += 3.8
            made += 1
            budget -= 1
    return shapes


GLYPH_STYLES = {
    "calligraphy": g_calligraphy, "outline": g_outline, "constellation": g_constellation,
    "sparkle": g_sparkle, "feather": g_feather, "crystal": g_crystal, "cracked": g_cracked,
    "riveted": g_riveted, "runic": g_runic, "jagged": g_jagged, "faceted": g_faceted,
    "flame": g_flame, "spiked": g_spiked, "bone": g_bone, "frost": g_frost,
}
GLYPH_NAMES = sorted(mt.GLYPHS)


# ======================================================================================
# Motes (32x32, white): what drifts up over the frames
# ======================================================================================

def mote_spark():
    """A four-point sparkle (arcane dust, starlight)."""
    return soft(32, [polygon(star(16, 16, 14, 2.6, 4, 0), WHITE), polygon(star(16, 16, 6, 1.5, 4, math.pi / 4), WHITE)],
                0.5, 2.4)


def mote_ember():
    """A rising ember: a small flame with a glow."""
    return soft(32, [polygon(flame_pts(16, 24, 16, 8, 0, 0.1), WHITE)], 0.55, 2.0)


def mote_spore():
    """A soft spore with two specks."""
    return soft(32, [ellipse(16, 16, 4.5, 4.5, WHITE), ellipse(23, 10, 2, 2, white(0.8)), ellipse(9, 22, 1.7, 1.7, white(0.7))],
                0.6, 1.6)


def mote_snow():
    """A snowflake."""
    shapes = []
    for k in range(6):
        a = k * TAU / 6 - math.pi / 2
        tip = polar(16, 16, 12.5, a)
        shapes.append(stroke([(16, 16), tip], 2.0, WHITE))
        mid = polar(16, 16, 7.5, a)
        for side in (1, -1):
            shapes.append(stroke([mid, polar(mid[0], mid[1], 4.2, a + side * 0.8)], 1.6, WHITE))
    return soft(32, shapes, 0.35, 2.4)


def mote_glint():
    return sa.firefly()


# --- small helpers for the masks ---------------------------------------------------

def gothic_window(x, y, w, h, width, col):
    """A lancet arch's outline: sides and a pointed top, from its foot."""
    top = y - h
    spring = top + w * 0.75
    left = [(x - w / 2, y), (x - w / 2, spring)] + bez((x - w / 2, spring), (x - w / 2, top + w * 0.25), (x - w * 0.15, top + 2),
                                                         (x, top), 10)[1:]
    right = [(x + w / 2, y), (x + w / 2, spring)] + bez((x + w / 2, spring), (x + w / 2, top + w * 0.25), (x + w * 0.15, top + 2),
                                                          (x, top), 10)[1:]
    return [stroke(left, width, col), stroke(right, width, col)]


def checker(w, h, cell):
    return [polygon(rect(i * cell, j * cell, (i + 1) * cell, (j + 1) * cell), WHITE)
            for i in range(int(w / cell)) for j in range(int(h / cell)) if (i + j) % 2 == 0]


def hex_pts(cx, cy, rx, ry=None, flat=True):
    return regular(cx, cy, rx, 6, 0 if flat else math.pi / 6, ry)


def per(span, size):
    """A motif's spacing that fits a whole number of times in `span`."""
    return span / max(1, round(span / size))


# ======================================================================================
# Karazhan
# ======================================================================================

KZ_FLAME = (c("#FF8A2C"), c("#FFC860"), c("#FFE29A"), c("#FFFBEA"))


def candle(cx, base, w, h, flame_h, wax=c("#EDE3CF"), wax_dark=c("#AE9D82"), glow_col=c("#FFC870")):
    top = base - h
    out = [glow(cx, top - flame_h * 0.45, flame_h * 1.25, glow_col, 0.4)]
    out.append(polygon(rect(cx - w / 2, top, cx + w / 2, base),
                       lambda px, py: mix(wax, wax_dark, clamp((px - (cx - w / 2)) / w * 1.2))))
    out.append(ellipse(cx - w * 0.28, top + h * 0.18, w * 0.16, h * 0.16, wax))
    out.append(ellipse(cx + w * 0.3, top + h * 0.1, w * 0.13, h * 0.1, wax))
    out.append(stroke([(cx, top), (cx, top - flame_h * 0.12)], max(0.6, w * 0.1), c("#2A2018")))
    out += flame(cx, top - flame_h * 0.05, flame_h, w * 0.75, KZ_FLAME)
    return out


def book(x0, y0, x1, y1, cover, pages=c("#E6DCC4"), band=c("#B8B0CC")):
    out = [polygon(rect(x0, y0, x1, y1), lambda px, py: mix(light(cover, 0.12), dark(cover, 0.3), clamp((py - y0) / (y1 - y0))))]
    out.append(polygon(rect(x1 - 3.2, y0 + 1, x1 - 0.6, y1 - 1), pages))
    for k in range(3):
        yy = y0 + 1.8 + k * (y1 - y0 - 3.6) / 2
        out.append(stroke([(x1 - 3.0, yy), (x1 - 0.8, yy)], 0.4, dark(pages, 0.25)))
    for xx in (x0 + 3, x0 + 5.5):
        out.append(stroke([(xx, y0 + 0.6), (xx, y1 - 0.6)], 0.8, band))
    return out


def kz_library_header():
    """Bookshelves behind a window's title: muted spines, silver bands, the
    shelf's plank (dark: the title reads over it)."""
    rng = random.Random(21)
    spines = [c("#3A1E3A"), c("#2C1A33"), c("#3B2430"), c("#2A2238"), c("#43292B"), c("#2F2A3A"), c("#352036")]
    shapes, x = [], 0
    while x < 128:
        w = min(rng.choice([5, 6, 7, 8, 9, 10]), 128 - x)
        h = rng.uniform(23, 33)
        col = rng.choice(spines)
        top = 36 - h
        shapes.append(polygon(rect(x + 0.35, top, x + w - 0.35, 36),
                              lambda px, py, x0=x, w=w, col=col: mix(light(col, 0.06), dark(col, 0.45), abs((px - x0) / w - 0.35) * 1.3)))
        if rng.random() < 0.65:
            band_col = mix(col, c("#9A8AB0"), 0.32)
            for yy in (top + 3, 33):
                shapes.append(stroke([(x + 0.8, yy), (x + w - 0.8, yy)], 0.7, band_col))
        if rng.random() < 0.3 and w >= 7:
            shapes.append(polygon(rect(x + 1.6, top + 8, x + w - 1.6, top + 13), mix(col, c("#A898C0"), 0.22)))
        x += w
    shapes.append(polygon(rect(-1, 36, 129, 40), c("#2A1820")))
    shapes.append(stroke([(-1, 36.5), (129, 36.5)], 0.9, c("#4A3040")))
    return band(128, 40, shapes, c("#120910"))


def kz_books():
    """56x38: two books lying on a window's corner, a candle on them."""
    shapes = book(4, 26, 48, 34, c("#3B2048"))
    shapes += [polygon(turn(rect(10, 19.5, 44, 26.2), 27, 23, -0.035), lambda px, py: mix(c("#2E3A58"), c("#1E2640"), clamp((py - 19) / 7)))]
    shapes += [polygon(turn(rect(40.5, 20.4, 43.2, 25.4), 27, 23, -0.035), c("#E6DCC4"))]
    shapes.append(ellipse(25, 19.6, 6.5, 1.6, c("#B8B4D0")))
    shapes += candle(25, 19.4, 5.2, 9, 8)
    return render(56, 38, shapes)


def kz_inkwell():
    """40x40: an inkwell and its quill (the chat's corner)."""
    shapes = feather(18, 22, 25, 4.2, -1.05, c("#CFC4E0"), c("#F4EEE2"), c("#9A90B0"), curl=0.04, barbs=3)
    shapes += [polygon([(8, 38), (28, 38), (26, 27), (10, 27)], lambda px, py: mix(c("#2A2244"), c("#120E1E"), clamp((px - 8) / 20))),
               stroke([(11, 29), (10, 36)], 1.1, c("#4C4270")),
               polygon(rect(13, 23, 23, 27.5), c("#8C88A8")),
               ellipse(18, 23, 6, 1.6, c("#C8C4E0"))]
    return render(40, 40, shapes)


def kz_ring():
    """The minimap: a ring of the tower's stone, faint runes in it."""
    cx = cy = 128
    rng = random.Random(31)
    shapes = []
    r_in, r_out = 110, 125
    for k in range(26):
        a0, a1 = k * TAU / 26 + 0.012, (k + 1) * TAU / 26 - 0.012
        tone = mix(c("#2E2234"), c("#4A3C52"), rng.uniform(0.2, 0.9))
        pts = arc_pts(cx, cy, r_out, a0, a1, 8) + arc_pts(cx, cy, r_in, a1, a0, 8)
        shapes.append(polygon(pts, tone))
        shapes.append(stroke(arc_pts(cx, cy, r_out - 1.2, a0 + 0.01, a1 - 0.01, 8), 1.0, light(tone, 0.18)))
    for a in (math.radians(200), math.radians(250), math.radians(300), math.radians(110)):
        x, y = polar(cx, cy, (r_in + r_out) / 2, a)
        shapes.append(glow(x, y, 9, c("#A47CFF"), 0.45))
        shapes += draw_rune(x, y, 9, rune_strokes(rng), 1.3, c("#C8B0FF"))
    return render(256, 256, shapes)


def kz_raven():
    """40x36: a raven perched, facing left (on the minimap's rim)."""
    body, hi, eye = c("#15111B"), c("#2E2640"), c("#B48CFF")
    shapes = [polygon([(29, 21), (40, 30), (37.5, 33), (27, 26)], body),
              ellipse(22, 20, 11, 7.5, lambda u, v: mix(hi, body, clamp((v + 1) / 1.6)), rot=-0.35),
              ellipse(24, 18, 8, 4.5, mix(hi, body, 0.4), rot=-0.35),
              ellipse(11.5, 11, 5.6, 5.2, body),
              polygon([(7, 9.5), (0.5, 12), (7, 13.2)], c("#2A2430")),
              ellipse(10.2, 10, 1.1, 1.1, eye),
              stroke([(20, 26), (19, 34)], 1.2, body), stroke([(24, 26), (25, 34)], 1.2, body),
              stroke([(16, 34), (28, 34)], 1.0, c("#2A2430"))]
    return render(40, 36, shapes)


def kz_unit_candle():
    """16x32 (drawn 8x16): one small candle for the unit frames."""
    return render(16, 32, candle(8, 30, 5.5, 13, 9))


def kz_library_pattern():
    """Lancet windows (pairs under a round light), faint."""
    def make(dx, dy):
        out = []
        for ox, oy in ((32, 0), (96, 64)):
            x, y = ox + dx, oy + dy
            out += gothic_window(x, y + 58, 34, 50, 1.4, WHITE)
            out += gothic_window(x - 8, y + 58, 12, 30, 1.1, white(0.7))
            out += gothic_window(x + 8, y + 58, 12, 30, 1.1, white(0.7))
            out.append(annulus(x, y + 18, 4.2, 4.2, 1.1, white(0.7)))
        return out
    return pattern(128, 128, make, 0.13)


def kz_library_track():
    def make(dx, dy):
        return [annulus(16 + dx + ox, 16 + dy + oy, 4, 4, 1.1, WHITE) for ox, oy in ((-4, 0), (4, 0), (0, -4), (0, 4))]
    return pattern(32, 32, make, 0.12)


def kz_quatrefoil():
    shapes = [ellipse(16 + ox, 16 + oy, 6.4, 6.4, WHITE) for ox, oy in ((-6, 0), (6, 0), (0, -6), (0, 6))]
    shapes += [polygon(regular(16, 16, 7, 4, math.pi / 4), WHITE), ellipse(16, 16, 2.8, 2.8, CUT)]
    return mask(32, 32, shapes)


def kz_arcane_star():
    shapes = [polygon(star(32, 32, 30, 13, 8), WHITE),
              ellipse(32, 32, 10, 10, CUT), ellipse(32, 32, 5.5, 5.5, WHITE)]
    return mask(64, 64, shapes)


def four_star_mask(size=64, ro=30, ri=8.5):
    return mask(size, size, [polygon(star(size / 2, size / 2, ro, ri, 4, 0), WHITE)])


def kz_library_divider():
    def make(dx, dy):
        return [stroke([(dx - 2, 4), (dx + 34, 4)], 0.9, WHITE), polygon([(12 + dx, 4), (16 + dx, 1.4), (20 + dx, 4), (16 + dx, 6.6)], WHITE)]
    return mask(32, 8, tiled(32, 8, make, ys=False))


def kz_script_bar(h):
    """Arcane stars along the bar, linked by fine swags (loops read as
    zeros beside the percentage)."""
    p = per(256, h * 1.0)

    def make(dx, dy):
        mid = h / 2
        out = []
        k = 0
        while k * p < 256 + p:
            x0 = k * p + dx
            arc = [(x0 + t * p / 12, mid + h * 0.22 * math.sin(math.pi * t / 12)) for t in range(13)]
            out.append(stroke(arc, max(0.9, h * 0.04), WHITE))
            out.append(polygon(star(x0, mid, h * 0.3, h * 0.07, 4, 0), WHITE))
            out.append(ellipse(x0 + p / 2, mid + h * 0.22, h * 0.05, h * 0.05, WHITE))
            k += 1
        return out
    return bar(h, make)


# --- Karazhan B: the opera stage -----------------------------------------------------------

VELVET, VELVET_DARK, VELVET_LIGHT = c("#4A1F52"), c("#22091F"), c("#6E3576")
GOLD_B, GOLD_B_DARK, GOLD_B_LIGHT = c("#C9A45C"), c("#7E5F2A"), c("#EBD392")


def kz_opera_header():
    """A valance behind the title: velvet swags, gold fringe, tassels."""
    shapes = []
    vel, vel_dark = c("#3A1640"), c("#1E0820")
    for s in range(2):
        x0 = s * 64

        def bottom(t):
            return 9 + 15 * math.sin(math.pi * t)
        pts = [(x0 + t * 64 / 24, 0) for t in range(25)] + [(x0 + t * 64 / 24, bottom(t / 24)) for t in range(24, -1, -1)]

        def col(px, py, x0=x0):
            t = (px - x0) / 64
            depth = py / max(1.0, 9 + 15 * math.sin(math.pi * clamp(t)))
            fold = 0.5 + 0.5 * math.cos(depth * math.pi * 3.2)
            return mix(vel_dark, vel, 0.35 + 0.5 * fold)
        shapes.append(polygon(pts, col))
        for k in range(26):
            t = (k + 0.5) / 26
            x = x0 + t * 64
            y = bottom(t)
            shapes.append(stroke([(x, y - 0.6), (x, y + 2.6)], 1.1, GOLD_B_DARK))
        shapes.append(stroke([(x0 + t * 64 / 24, bottom(t / 24) - 0.4) for t in range(25)], 1.0, dark(GOLD_B, 0.25)))
    for x0 in (0, 64, 128):
        shapes.append(stroke([(x0, 0), (x0, 21)], 1.2, GOLD_B_DARK))
        shapes.append(ellipse(x0, 24, 2.8, 3.4, GOLD_B))
        for k in range(5):
            shapes.append(stroke([(x0 - 2 + k, 26), (x0 - 2.6 + k * 1.3, 34)], 0.8, GOLD_B_DARK))
    shapes.append(polygon(rect(-1, 0, 129, 1.6), GOLD_B_DARK))
    return band(128, 40, shapes, c("#13050F"))


def kz_curtain():
    """48x150: a stage curtain drawn back, gathered at a gold tie."""
    tie = 92

    def smooth(t):
        t = clamp(t)
        return t * t * (3 - 2 * t)

    def edge_x(k, y):
        top, mid, bot = k * 48 / 6, 4 + k * 16 / 6, 2 + k * 30 / 6
        if y < tie:
            return top + (mid - top) * smooth(y / tie)
        return mid + (bot - mid) * smooth((y - tie) / (150 - tie))
    shapes = []
    for k in range(6):
        left = [(edge_x(k, y), y) for y in range(0, 151, 3)]
        right = [(edge_x(k + 1, y), y) for y in range(150, -1, -3)]
        lit, shade = (VELVET_LIGHT, VELVET_DARK) if k % 2 == 0 else (VELVET, VELVET_DARK)

        def col(px, py, k=k, lit=lit, shade=shade):
            xl, xr = edge_x(k, py), edge_x(k + 1, py)
            t = clamp((px - xl) / max(0.5, xr - xl))
            return mix(shade, lit, math.sin(math.pi * t) ** 0.8)
        shapes.append(polygon(left + right, col))
    shapes.append(stroke(bez((4, tie - 2), (16, tie + 4), (30, tie + 2), (24, tie - 3), 12), 2.4, GOLD_B))
    shapes.append(stroke([(18, tie + 2), (18, tie + 13)], 1.2, GOLD_B_DARK))
    shapes.append(ellipse(18, tie + 16, 3.4, 4.2, lambda u, v: mix(GOLD_B_LIGHT, GOLD_B_DARK, clamp((u + 1) / 2))))
    for k in range(6):
        shapes.append(stroke([(15.5 + k, tie + 19), (14.5 + k * 1.4, tie + 31)], 0.9, GOLD_B_DARK))
    shapes.append(polygon(rect(0, 0, 48, 2.2), GOLD_B))
    return render(48, 150, shapes)


def kz_masks():
    """52x40: comedy and tragedy (the chat's corner)."""
    cream, cream_dark = c("#F2E6D0"), c("#BFAE90")
    plum, plum_dark = c("#8A5A96"), c("#4E2A58")
    hole = c("#1A0A18")
    shapes = [ellipse(35, 16, 11, 13, lambda u, v: mix(plum, plum_dark, clamp((u + 1) / 2)), rot=0.25),
              ellipse(31.5, 13, 2.6, 1.6, hole, rot=0.6), ellipse(39.5, 15, 2.6, 1.6, hole, rot=-0.1),
              polygon(bez((30, 25), (33, 20), (38, 21), (41, 26), 8) + bez((41, 26), (38, 23), (33, 23), (30, 25), 8), hole),
              ellipse(19, 21, 12.5, 14.5, lambda u, v: mix(cream, cream_dark, clamp((u + 1) / 2)), rot=-0.15),
              polygon(bez((12, 17), (14, 14), (18, 14), (20, 17), 6) + bez((20, 17), (18, 16), (14, 16), (12, 17), 6), hole),
              polygon(bez((21, 16), (23, 13), (27, 14), (28, 17), 6) + bez((28, 17), (26, 15.5), (23, 15.5), (21, 16), 6), hole),
              polygon(bez((11, 25), (15, 33), (24, 33), (28, 24), 10) + bez((28, 24), (22, 28), (16, 28), (11, 25), 10), hole),
              stroke(bez((6, 6), (16, 2), (36, 34), (48, 30), 16), 1.6, GOLD_B)]
    return render(52, 40, shapes)


def kz_opera_ring():
    """The minimap in a gilded frame: a gold band, beads round it."""
    cx = cy = 128
    shapes = []
    r0, r1 = 111, 123

    def col(px, py):
        d = math.hypot(px - cx, py - cy)
        t = (d - r0) / (r1 - r0)
        return ramp([(0, GOLD_B_DARK), (0.35, GOLD_B_LIGHT), (0.6, GOLD_B), (1, GOLD_B_DARK)], t)
    shapes.append(annulus(cx, cy, r1, r1, r1 - r0, col))
    for k in range(48):
        x, y = polar(cx, cy, 125.6, k * TAU / 48)
        shapes.append(ellipse(x, y, 2.2, 2.2, lambda u, v: mix(GOLD_B_LIGHT, GOLD_B_DARK, clamp((u + v + 1) / 2))))
    for k in range(72):
        x, y = polar(cx, cy, 108.6, k * TAU / 72)
        shapes.append(ellipse(x, y, 1.2, 1.2, GOLD_B_DARK))
    for a in (math.radians(225), math.radians(315)):
        x, y = polar(cx, cy, 117, a)
        for k in range(6):
            px, py = polar(x, y, 4, k * TAU / 6)
            shapes.append(ellipse(px, py, 3, 3, GOLD_B))
        shapes.append(ellipse(x, y, 3.2, 3.2, GOLD_B_LIGHT))
    return render(256, 256, shapes)


def fleuron(cx, cy, s, col_fn, width=None):
    """A small gold crest: a teardrop up, a curl each side, a bar."""
    w = width or max(1.2, s * 0.09)
    out = [polygon(vesica(cx, cy - s * 0.12, s * 0.28, s * 0.62), col_fn)]
    for side in (1, -1):
        pts = []
        for k in range(30):
            t = k / 29
            a = side * (math.pi * 0.1 + t * math.pi * 1.6)
            r = s * 0.3 * (1 - t * 0.6)
            pts.append((cx + side * s * 0.28 + math.sin(a) * r * side, cy + s * 0.12 - math.cos(a) * r))
        out.append(stroke(pts, w, col_fn))
    out.append(stroke([(cx - s * 0.5, cy + s * 0.38), (cx + s * 0.5, cy + s * 0.38)], w * 1.1, col_fn))
    out.append(ellipse(cx, cy - s * 0.55, s * 0.07, s * 0.07, col_fn))
    return out


def kz_fleuron_unit():
    """48x28 (drawn 24x14): a small gold crest on the unit frames' top."""
    def col(*_a):
        return GOLD_B
    shapes = fleuron(24, 14, 26, GOLD_B, 2.2)
    return render(48, 28, shapes)


def kz_damask():
    """A damask lily in a drop repeat, faint."""
    def motif(x, y, s):
        out = [polygon(vesica(x, y - s * 0.1, s * 0.3, s * 0.75), WHITE)]
        for side in (1, -1):
            out += leaf(x, y + s * 0.25, s * 0.55, s * 0.16, -math.pi / 2 + side * 1.05, WHITE, WHITE, curl=-side * 0.12)
        out.append(ellipse(x, y + s * 0.34, s * 0.12, s * 0.08, WHITE))
        out.append(ellipse(x, y - s * 0.6, s * 0.06, s * 0.06, WHITE))
        return out

    def make(dx, dy):
        out = motif(32 + dx, 32 + dy, 30) + motif(96 + dx, 96 + dy, 30)
        for x, y in ((96, 32), (32, 96)):
            out += [ellipse(x + dx + ox, y + dy + oy, 1.6, 1.6, white(0.8)) for ox, oy in ((-4, 0), (4, 0), (0, -4), (0, 4))]
        return out
    return pattern(128, 128, make, 0.13)


def kz_opera_track():
    def make(dx, dy):
        return [polygon(regular(x + dx, y + dy, 3, 4, 0), WHITE) for x, y in ((8, 8), (24, 24))]
    return pattern(32, 32, make, 0.12)


def kz_fleuron_mask():
    return mask(32, 32, fleuron(16, 17, 26, WHITE, 2.4))


def kz_mask_jewel():
    shapes = [ellipse(32, 30, 22, 26, WHITE),
              polygon(bez((18, 25), (21, 19), (28, 19), (30, 25), 6) + bez((30, 25), (27, 23), (21, 23), (18, 25), 6), CUT),
              polygon(bez((34, 25), (37, 19), (44, 19), (46, 25), 6) + bez((46, 25), (43, 23), (37, 23), (34, 25), 6), CUT),
              polygon(bez((18, 37), (24, 50), (40, 50), (46, 37), 10) + bez((46, 37), (38, 43), (26, 43), (18, 37), 10), CUT)]
    return mask(64, 64, shapes)


def kz_rosette():
    shapes = [ellipse(*polar(32, 32, 15, k * TAU / 6), 10, 10, WHITE) for k in range(6)]
    shapes.append(ellipse(32, 32, 10, 10, WHITE))
    return mask(64, 64, shapes)


def kz_rope_divider():
    def make(dx, dy):
        return [ellipse(x + dx, 4, 2.4, 1.3, WHITE, rot=0.65) for x in range(2, 34, 4)]
    return mask(32, 8, tiled(32, 8, make, ys=False))


def kz_harlequin_bar(h):
    """Harlequin diamonds: every other filled."""
    w = per(256, h * 0.75)

    def make(dx, dy):
        out = []
        for k in range(int(round(256 / w))):
            x = (k + 0.5) * w + dx
            pts = [(x, 0.5), (x + w / 2, h / 2), (x, h - 0.5), (x - w / 2, h / 2)]
            if k % 2 == 0:
                out.append(polygon(pts, WHITE))
            else:
                out.append(stroke(pts + [pts[0]], max(0.9, h * 0.05), WHITE))
        return out
    return bar(h, make, 0.66)


# --- Karazhan C: the nether over the tower -------------------------------------------------------

SILVER, SILVER_DARK, STAR = c("#C9C6E8"), c("#6E6A98"), c("#ECEAFF")


def kz_sky_header():
    """Night sky behind the title: indigo deepening upward, faint nebula,
    small stars."""
    rng = random.Random(41)
    top, bottom = c("#0A0920"), c("#1C1438")
    shapes = [polygon(rect(-1, -1, 129, 41), lambda px, py: mix(top, bottom, clamp(py / 40)))]
    for _ in range(3):
        shapes.append(glow(rng.uniform(0, 128), rng.uniform(14, 34), rng.uniform(22, 34), c("#4A2A7A"), 0.3, ry=rng.uniform(7, 11)))
    shapes.append(glow(rng.uniform(0, 128), 22, 28, c("#2A3A7A"), 0.22, ry=8))
    for _ in range(26):
        r = rng.uniform(0.35, 0.8)
        shapes.append(ellipse(rng.uniform(0, 128), rng.uniform(1, 39), r, r, fade(STAR, rng.uniform(0.35, 0.8))))
    for x, y in ((24, 10), (90, 28)):
        shapes.append(polygon(star(x, y, 2.6, 0.6, 4, 0), fade(STAR, 0.8)))
    return band(128, 40, shapes, top)


def kz_moon():
    """44x44: a crescent moon, its dark side faintly lit."""
    moon, moon_dark = c("#EAE6F8"), c("#A8A2CC")
    shapes = [glow(22, 22, 21, c("#B8B0FF"), 0.32), ellipse(22, 22, 13, 13, fade(c("#2E2A58"), 0.92))]

    def lit(x, y):
        if (x - 22) ** 2 + (y - 22) ** 2 > 169:
            return None
        if (x - 27.5) ** 2 + (y - 18) ** 2 < 132:
            return None
        return mix(moon, moon_dark, clamp((x - 10) / 14))
    shapes.append(Shape((9, 9, 35, 35), lit))
    return render(44, 44, shapes)


def chess_knight(s, col_fn):
    k = s / 64
    head = [(14, 50), (16, 38), (9, 33), (6, 27), (11, 19), (17, 13), (20, 4), (25, 11), (32, 12), (38, 20), (41, 32), (39, 50)]
    out = [polygon([(x * k, y * k) for x, y in head], col_fn),
           polygon(rect(10 * k, 49 * k, 42 * k, 55 * k), col_fn),
           polygon(rect(6 * k, 55 * k, 46 * k, 62 * k), col_fn),
           ellipse(17 * k, 22 * k, 1.8 * k, 1.8 * k, c("#1A1830"))]
    return out


def chess_rook(s, col_fn):
    k = s / 64
    top = [(8, 10), (14, 10), (14, 15), (20, 15), (20, 10), (28, 10), (28, 15), (34, 15), (34, 10), (40, 10), (40, 22), (8, 22)]
    out = [polygon([(x * k, y * k) for x, y in top], col_fn),
           polygon([(12 * k, 22 * k), (36 * k, 22 * k), (38 * k, 54 * k), (10 * k, 54 * k)], col_fn),
           polygon(rect(6 * k, 54 * k, 42 * k, 62 * k), col_fn)]
    return out


def silver_fn(x0, x1):
    return lambda px, py: mix(c("#E8E6FA"), SILVER_DARK, clamp((px - x0) / (x1 - x0)))


def kz_knight():
    return render(48, 64, chess_knight(64, silver_fn(4, 44)))


def kz_rook():
    return render(48, 64, chess_rook(64, silver_fn(6, 42)))


def kz_stars_top():
    """256x20: a few small stars just over a window's top."""
    shapes = []
    for x, y, r in ((30, 8, 1.0), (92, 13, 0.8), (150, 6, 1.2), (206, 11, 0.9), (240, 15, 0.7)):
        shapes.append(glow(x, y, r * 4, STAR, 0.35))
        shapes.append(ellipse(x, y, r, r, STAR))
    shapes.append(polygon(star(150, 6, 4.2, 0.9, 4, 0), STAR))
    return band(256, 20, shapes)


def kz_astrolabe():
    """The minimap as an astrolabe: a silver degree ring, ticks round it."""
    cx = cy = 128
    shapes = []
    r0, r1 = 111, 120

    def col(px, py):
        d = math.hypot(px - cx, py - cy)
        return ramp([(0, SILVER_DARK), (0.45, c("#E2E0F6")), (1, SILVER_DARK)], (d - r0) / (r1 - r0))
    shapes.append(annulus(cx, cy, r1, r1, r1 - r0, col))
    shapes.append(annulus(cx, cy, 125, 125, 1.3, SILVER))
    for k in range(60):
        a = k * TAU / 60
        long_ = k % 5 == 0
        shapes.append(stroke([polar(cx, cy, 120, a), polar(cx, cy, 126.5 if long_ else 123, a)], 1.5 if long_ else 0.9, SILVER))
    for k in range(12):
        x, y = polar(cx, cy, 115.5, k * TAU / 12 + TAU / 24)
        shapes.append(ellipse(x, y, 1.6, 1.6, c("#2A2650")))
    shapes.append(polygon(star(cx, cy - 126, 6, 1.4, 4, 0), STAR))
    return render(256, 256, shapes)


def kz_unit_star():
    """24x24 (drawn 12x12): a small star for the unit frames."""
    return render(24, 24, [glow(12, 12, 11, c("#B8B0FF"), 0.4), polygon(star(12, 12, 10.5, 2.2, 4, 0), STAR),
                           polygon(star(12, 12, 4.5, 1.2, 4, math.pi / 4), STAR)])


def kz_constellations():
    rng = random.Random(43)
    groups = []
    for gx, gy in ((30, 34), (92, 70), (44, 104)):
        pts = [(gx + rng.uniform(-22, 22), gy + rng.uniform(-18, 18)) for _ in range(5)]
        pts.sort()
        groups.append(pts)
    lone = [(rng.uniform(0, 128), rng.uniform(0, 128), rng.uniform(0.8, 1.4)) for _ in range(10)]

    def make(dx, dy):
        out = []
        for pts in groups:
            moved = [(x + dx, y + dy) for x, y in pts]
            out.append(stroke(moved, 0.7, white(0.55)))
            out += [ellipse(x, y, 1.9, 1.9, WHITE) for x, y in moved]
        out += [ellipse(x + dx, y + dy, r, r, white(0.8)) for x, y, r in lone]
        return out
    return pattern(128, 128, make, 0.15)


def kz_chess_track():
    return as_mask(coverage(32, 32, checker(32, 32, 8)), 0.09)


def kz_crescent():
    return mask(64, 64, [ellipse(32, 32, 25, 25, WHITE), ellipse(42, 25, 21, 21, CUT)])


def kz_star_divider():
    def make(dx, dy):
        out = [ellipse(x + dx, 4, 0.75, 0.75, WHITE) for x in (2, 6, 10, 22, 26, 30)]
        out.append(polygon(star(16 + dx, 4, 3.6, 0.9, 4, 0), WHITE))
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def kz_chess_bar(h):
    cell = h / 2
    return as_shade(coverage(256, h, checker(256, h, cell)), 0.72)


# ======================================================================================
# Sunwell
# ======================================================================================

GOLD, GOLD_MID, GOLD_DEEP, GOLD_DARK = c("#F5DC3A"), c("#D9B52A"), c("#9A7414"), c("#5A4210")
SUN_WHITE = c("#FFF8DC")


def sw_sun_header():
    """Rays fanning up from below the title, a low glow (dim)."""
    shapes = []
    ox, oy = 64, 58
    for k in range(19):
        if k % 2:
            continue
        a0 = math.pi + k * math.pi / 19
        a1 = math.pi + (k + 1) * math.pi / 19
        pts = [(ox, oy), polar(ox, oy, 74, a0), polar(ox, oy, 74, a1)]
        shapes.append(polygon(pts, lambda px, py: mix(c("#4A3A16"), c("#261E10"), clamp(math.hypot(px - ox, py - oy) / 74))))
    shapes.append(glow(64, 46, 72, GOLD, 0.1, ry=12))
    shapes.append(polygon(rect(-1, 38.6, 129, 40), c("#3A2E14")))
    return band(128, 40, shapes, c("#1C150D"))


def sun_shapes(cx, cy, r_disc, r_long, r_short, n, glow_r=None):
    out = []
    if glow_r:
        out.append(glow(cx, cy, glow_r, GOLD, 0.35))
    for k in range(n):
        a = -math.pi / 2 + k * TAU / n
        tip = r_long if k % 2 == 0 else r_short
        half = math.pi / n * 0.55
        pts = [polar(cx, cy, r_disc * 0.92, a - half), polar(cx, cy, tip, a), polar(cx, cy, r_disc * 0.92, a + half)]
        out.append(polygon(pts, lambda px, py: mix(SUN_WHITE, GOLD_MID, clamp((math.hypot(px - cx, py - cy) - r_disc) / (tip - r_disc + 0.1)))))
    out.append(ellipse(cx, cy, r_disc, r_disc, GOLD_DEEP))
    out.append(ellipse(cx, cy, r_disc * 0.8, r_disc * 0.8, lambda u, v: mix(SUN_WHITE, GOLD, clamp(math.hypot(u + 0.3, v + 0.3)))))
    return out


def sw_sun():
    """40x40: a sunburst medallion on a window's top."""
    return render(40, 40, sun_shapes(20, 20, 8.5, 19, 14, 16, 20))


def filigree(pal_line, pal_edge):
    """48x40: gold filigree over a window's corner: a spiral, an S along
    the top, a curl down the side."""
    lines = [bez((8, 16), (16, 4), (30, 11), (46, 5), 20), bez((7, 18), (1, 26), (10, 32), (4, 39), 16),
             bez((30, 9), (34, 13), (38, 13), (40, 10), 8)]
    spirals = [(9, 14, 6.2, 1.6), (40, 9.5, 2.6, 1.2), (5, 36, 2.6, 1.2)]
    shapes = []
    for col, w in ((pal_edge, 3.0), (pal_line, 1.6)):
        shapes += [stroke(p, w, col) for p in lines]
        shapes += [spiral(x, y, r, t, w, col) for x, y, r, t in spirals]
    for x, y, a in ((20, 8.4, -0.6), (27, 9.5, 0.5), (3.6, 27, 2.6)):
        shapes += leaf(x, y, 6, 1.9, a, pal_line, pal_line)
    return render(48, 40, shapes)


def sw_ring():
    """The minimap in rays: long and short, gold, off the buttons."""
    cx = cy = 128
    r = rim(22)
    shapes = [annulus(cx, cy, r + 1.5, r + 1.5, 2.2, GOLD_MID), annulus(cx, cy, r - 2.5, r - 2.5, 0.9, GOLD_DEEP)]
    for k in range(36):
        a = k * TAU / 36
        if clear(math.degrees(a)):
            continue
        tip = 126 if k % 2 == 0 else 116
        half = math.radians(2.6)
        pts = [polar(cx, cy, r + 1, a - half), polar(cx, cy, tip, a), polar(cx, cy, r + 1, a + half)]
        shapes.append(polygon(pts, lambda px, py, tip=tip: mix(SUN_WHITE, GOLD_DEEP, clamp((math.hypot(px - cx, py - cy) - r) / (tip - r)))))
    return render(256, 256, shapes)


def sw_unit_sun():
    """24x24 (drawn 12x12): a tiny sun for the unit frames."""
    return render(24, 24, sun_shapes(12, 12, 4.4, 11, 8, 8, 11))


def sw_sun_pattern():
    def sun(x, y, s):
        out = [annulus(x, y, s * 0.36, s * 0.36, s * 0.1, WHITE)]
        for k in range(12):
            a = k * TAU / 12
            out.append(stroke([polar(x, y, s * 0.55, a), polar(x, y, s * (1.0 if k % 2 == 0 else 0.8), a)], 1.3, WHITE))
        return out

    def make(dx, dy):
        out = sun(32 + dx, 32 + dy, 14) + sun(96 + dx, 96 + dy, 14)
        out += [ellipse(x + dx, y + dy, 1.5, 1.5, WHITE) for x, y in ((96, 32), (32, 96))]
        return out
    return pattern(128, 128, make, PATTERN["SunwellSunburst"])


def sw_ray_track():
    def make(dx, dy):
        return [stroke([(dx - 4 + k * 16, 36 + dy), (dx + 32 + k * 16, dy)], 0.9, WHITE) for k in (-1, 0, 1)]
    return pattern(32, 32, make, 0.09)


def sw_sunburst_orn():
    return mask(32, 32, [polygon(star(16, 16, 15, 6, 8), WHITE), ellipse(16, 16, 3, 3, CUT)])


def sw_sun_jewel():
    shapes = [polygon(star(32, 32, 30, 15, 12), WHITE), ellipse(32, 32, 15.5, 15.5, CUT), ellipse(32, 32, 12, 12, WHITE)]
    return mask(64, 64, shapes)


def sw_bead_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.6, white(0.7))]
        out += [ellipse(x + dx, 4, r, r, WHITE) for x, r in ((4, 1.0), (12, 1.6), (20, 1.0), (28, 1.6))]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def sw_ray_bar(h):
    p = per(256, h * 0.9)

    def make(dx, dy):
        out = []
        for k in range(-1, int(round(256 / p)) + 1):
            x = k * p + dx
            out.append(polygon([(x, h), (x + h * 0.22, h), (x + h * 0.22 + h * 0.5, 0), (x + h * 0.5, 0)], WHITE))
        return out
    return bar(h, make, 0.72)


# --- Sunwell B: the phoenix ---------------------------------------------------------------

PH_RED, PH_RED_DARK, PH_ORANGE = c("#C2321E"), c("#6E160C"), c("#E86A1E")
PH_GOLD, PH_GOLD_LIGHT, PH_QUILL = c("#F2C04A"), c("#FFE49A"), c("#F7E8CC")


def sw_phoenix_header():
    """Phoenix feathers fanning up behind the title (dim)."""
    rng = random.Random(51)
    shapes = []
    for k in range(10):
        x = k * 13 + rng.uniform(-2, 2)
        shapes += feather(x, 48, rng.uniform(34, 44), rng.uniform(5, 6.5), -math.pi / 2 + rng.uniform(-0.55, 0.55),
                          dark(PH_RED_DARK, 0.45), dark(PH_ORANGE, 0.76), dark(PH_GOLD, 0.8), barbs=2)
    return band(128, 40, shapes, c("#1C0C08"))


def sw_feather_fan():
    """96x56: three tail feathers sweeping off a window's corner."""
    shapes = []
    for ang, ln, wd in ((-0.62, 48, 5.6), (-0.36, 66, 6.2), (-0.12, 84, 6.8)):
        shapes += feather(12, 50, ln, wd, ang, PH_RED, PH_GOLD, PH_QUILL, curl=-0.03, barbs=4)
    shapes += feather(12, 50, 20, 4.5, -1.05, PH_RED_DARK, PH_ORANGE, PH_QUILL, barbs=1)
    shapes.append(ellipse(12, 50, 3.2, 3.2, PH_GOLD))
    return render(96, 56, shapes)


def sw_side_feather():
    """24x100: one long feather hanging from a window's top right."""
    return render(24, 100, feather(12, 2, 94, 7, math.pi / 2, PH_RED, PH_GOLD, PH_QUILL, curl=0.02, barbs=5))


def sw_phoenix_ring():
    """The minimap ringed with phoenix feathers, off the buttons."""
    cx = cy = 128
    r = rim(14)
    rng = random.Random(53)
    shapes = []
    cols = [(PH_RED, PH_GOLD), (PH_ORANGE, PH_GOLD_LIGHT), (PH_RED_DARK, PH_ORANGE)]
    for a0, a1 in ((0, 360),):
        a = a0
        k = 0
        while a <= a1:
            ang = math.radians(a)
            if clear(a):
                a += 7
                continue
            x, y = polar(cx, cy, r - 3, ang)
            base, tip = cols[k % 3]
            shapes += feather(x, y, rng.uniform(17, 22), 4.4, ang + 0.28, base, tip, PH_QUILL, barbs=2)
            a += 7
            k += 1
    shapes.append(annulus(cx, cy, r + 1.2, r + 1.2, 2.2, PH_GOLD))
    return render(256, 256, shapes)


def sw_unit_feather():
    """56x20 (drawn 28x10): one small feather lying on the unit frames."""
    return render(56, 20, feather(4, 16, 50, 4.8, -0.13, PH_RED, PH_GOLD, PH_QUILL, barbs=3))


def sw_plumage():
    def make(dx, dy):
        out = []
        for j in range(9):
            for i in range(9):
                x = i * 16 + (8 if j % 2 else 0) + dx
                y = j * 16 + dy
                out.append(stroke(arc_pts(x, y, 9, 0.15, math.pi - 0.15, 12), 1.1, WHITE))
        return out
    return pattern(128, 128, make, 0.12)


def sw_chevron_track():
    def make(dx, dy):
        return [stroke([(4 + dx + ox, 20 + dy), (10 + dx + ox, 13 + dy), (16 + dx + ox, 20 + dy)], 1.2, WHITE) for ox in (0, 16)]
    return pattern(32, 32, make, 0.11)


def flame_mask(size, h, w, inner=False):
    s = size
    shapes = [polygon(flame_pts(s / 2, s - 2, h, w, 0, 0.12), WHITE)]
    if inner:
        shapes.append(polygon(flame_pts(s / 2, s - 6, h * 0.55, w * 0.5, 0, 0.1), CUT))
        shapes.append(ellipse(s / 2, s - 10, w * 0.12, w * 0.12, WHITE))
    return mask(s, s, shapes)


def sw_barb_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.8, WHITE)]
        out += [stroke([(x + dx, 4), (x + dx - 2.6, 1.0)], 0.7, WHITE) for x in range(2, 34, 4)]
        out += [stroke([(x + dx, 4), (x + dx - 2.6, 7.0)], 0.7, WHITE) for x in range(4, 34, 4)]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def sw_feather_bar(h):
    p = per(256, h * 0.36)

    def make(dx, dy):
        mid = h / 2
        out = [stroke([(dx - 2, mid), (dx + 258, mid)], max(1.2, h * 0.07), WHITE)]
        for k in range(-1, int(round(256 / p)) + 2):
            x = k * p + dx
            for side in (1, -1):
                out.append(stroke(bez((x, mid), (x - h * 0.15, mid + side * h * 0.2), (x - h * 0.35, mid + side * h * 0.34),
                                      (x - h * 0.6, mid + side * h * 0.46), 8), max(0.9, h * 0.045), WHITE))
        return out
    return bar(h, make, 0.66)


# --- Sunwell C: naaru light through elven glass -----------------------------------------------------

GLASS_LIT, GLASS_MID, GLASS_DARK, GLASS_WHITE = c("#A8DCFF"), c("#4E9BE0"), c("#1D4F8E"), c("#F2FAFF")
GOLD_C = c("#E6CB6A")


def sw_glass_header():
    """Leaded glass behind the title: a lattice of deep blue panes, a few
    gold, the lead dark (the title reads over it)."""
    rng = random.Random(61)
    panes = [c("#0F1B31"), c("#12223F"), c("#0C172C"), c("#11203A"), c("#262012")]
    shapes = []
    choice = {}
    for j in range(-1, 4):
        for i in range(-1, 5):
            choice[(i % 4, j)] = rng.choices(panes, weights=[3, 3, 3, 3, 1])[0]
    for j in range(-1, 4):
        for i in range(-1, 5):
            x = i * 32 + (16 if j % 2 else 0)
            y = j * 20
            col = choice[((i + (1 if j % 2 and i < 0 else 0)) % 4, j)]
            pts = [(x, y - 9), (x + 15, y), (x, y + 9), (x - 15, y)]
            shapes.append(polygon(pts, lambda px, py, col=col, y=y: mix(light(col, 0.05), col, clamp((py - y + 9) / 18))))
    return band(128, 40, shapes, c("#0B0C10"))


def shard_group(spec, glow_col=c("#BFE6FF")):
    shapes = []
    for x, y, ln, wd, ang in spec:
        shapes.append(glow(x, y, ln * 0.85, glow_col, 0.32))
    for x, y, ln, wd, ang in spec:
        shapes += crystal(x, y, ln, wd, ang, lambda px, py: GLASS_LIT, GLASS_MID, GLASS_WHITE)
    return shapes


def sw_shards():
    """48x36: naaru crystal shards floating over a window's corner."""
    return render(48, 36, shard_group([(12, 21, 20, 7, -1.3), (26, 14, 16, 6, -1.6), (37, 23, 11, 4.5, -1.9)]))


def sw_glass_ring():
    """The minimap: crystal shards orbiting it, a fine gold line."""
    cx = cy = 128
    r = rim(12)
    spec = []
    for a in (172, 204, 236, 300, 332, 65, 118):
        ang = math.radians(a)
        x, y = polar(cx, cy, r + 6, ang)
        spec.append((x, y, 13, 5, ang))
    shapes = [annulus(cx, cy, r + 0.8, r + 0.8, 1.6, GOLD_C)] + shard_group(spec)
    return render(256, 256, shapes)


def sw_unit_shards():
    """32x24 (drawn 16x12): two small crystals for the unit frames."""
    return render(32, 24, shard_group([(12, 14, 14, 5, -1.35), (22, 13, 10, 4, -1.75)]))


def sw_lattice(size, step, strength):
    def make(dx, dy):
        out = []
        for k in range(-1, int(size / step) + 2):
            out.append(stroke([(k * step + dx - size, dy + size), (k * step + dx, dy)], 1.0, WHITE))
            out.append(stroke([(k * step + dx, dy), (k * step + dx + size, dy + size)], 1.0, WHITE))
        return out
    return pattern(size, size, make, strength)


def sw_crystal_orn():
    return mask(32, 32, [polygon([(16, 2), (26, 16), (16, 30), (6, 16)], WHITE), stroke([(16, 4), (16, 28)], 1.2, CUT)])


def sw_gem_jewel():
    shapes = [polygon(regular(32, 32, 28, 8, math.pi / 8), WHITE)]
    inner = regular(32, 32, 16, 8, math.pi / 8)
    shapes.append(stroke(inner + [inner[0]], 1.8, CUT))
    outer = regular(32, 32, 28, 8, math.pi / 8)
    shapes += [stroke([a, b], 1.4, CUT) for a, b in zip(inner, outer)]
    return mask(64, 64, shapes)


def sw_rhombus_mark():
    return mask(64, 64, [polygon([(32, 3), (50, 32), (32, 61), (14, 32)], WHITE)])


def sw_lattice_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.6, white(0.7))]
        for x in (8, 24):
            pts = [(x + dx, 1), (x + dx + 3.5, 4), (x + dx, 7), (x + dx - 3.5, 4)]
            out.append(stroke(pts + [pts[0]], 0.9, WHITE))
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def sw_facet_bar(h):
    p = per(256, h * 0.8)

    def make(dx, dy):
        pts = []
        k = 0
        x = -p
        while x <= 256 + p:
            pts.append((x + dx, 0.5 if k % 2 == 0 else h - 0.5))
            x += p / 2
            k += 1
        return [stroke(pts, max(0.9, h * 0.07), WHITE), stroke([(dx - 2, h / 2), (dx + 258, h / 2)], max(0.6, h * 0.035), white(0.8))]
    return bar(h, make, 0.7)


# ======================================================================================
# Black Temple
# ======================================================================================

BT_STONE, BT_STONE_DARK, BT_STONE_LIGHT, BT_STONE_DEEP = c("#3A3248"), c("#231D2D"), c("#544A66"), c("#16111D")
FEL, FEL_BRIGHT, FEL_DARK = c("#7FD34E"), c("#CFFF9A"), c("#2E5A1C")


def lens_carving(x, y, w, h, rot, edge_col, inner_col, glow_col=None):
    out = []
    if glow_col:
        out.append(glow(x, y, max(w, h) * 0.7, glow_col, 0.3))
    out.append(polygon(vesica(x, y, w, h, rot), edge_col))
    out.append(polygon(vesica(x, y, w * 0.62, h * 0.72, rot), inner_col))
    out.append(ellipse(x, y, min(w, h) * 0.16, min(w, h) * 0.16, edge_col))
    return out


def bt_temple_header():
    """Draenei stone behind the title: big blocks, a lens carved in some,
    fel-lit faintly, cracks."""
    rng = random.Random(71)
    shapes = []
    rows = [(0, 20, [0, 44, 84, 128]), (20, 40, [-20, 22, 64, 106, 148])]
    for y0, y1, xs in rows:
        for x0, x1 in zip(xs, xs[1:]):
            tone = mix(BT_STONE_DEEP, BT_STONE_DARK, rng.uniform(0.5, 1.0))
            shapes.append(polygon(rect(x0 + 0.8, y0 + 0.8, x1 - 0.8, y1 - 0.8), tone))
            shapes.append(stroke([(x0 + 1.5, y0 + 1.4), (x1 - 1.5, y0 + 1.4)], 0.8, light(tone, 0.1)))
    for x, y in ((22, 10), (106, 10), (64, 30)):
        shapes += lens_carving(x, y, 8, 15, math.pi / 2, c("#3A3048"), c("#1E2A1C"), FEL_DARK)
    for _ in range(3):
        pts = crack_walk(rng, rng.uniform(0, 128), rng.uniform(4, 36), rng.uniform(0, TAU), 18, 2.5, 0.7)
        shapes.append(stroke(pts, 0.8, c("#0C0910")))
    return band(128, 40, shapes, c("#0F0B14"))


def bt_broken_slab():
    """88x40: a broken slab of draenei stone lying over a window's corner,
    a lens carved in it, fel in its crack, rubble."""
    rng = random.Random(73)
    slab = [(0, 30), (8, 22), (40, 19), (58, 14), (68, 18), (64, 25), (76, 28), (71, 35), (60, 34), (0, 38)]
    shapes = [polygon(slab, lambda px, py: mix(BT_STONE_LIGHT, BT_STONE_DARK, clamp((py - 14) / 22)))]
    shapes.append(polygon([(8, 22), (40, 19), (58, 14), (60, 17), (40, 22), (9, 25)], light(BT_STONE_LIGHT, 0.1)))
    shapes += lens_carving(28, 29, 7, 15, math.pi / 2, BT_STONE_DARK, c("#22301C"), FEL)
    crack = [(46, 21), (49, 26), (47, 30), (51, 36)]
    shapes += [glow_line(crack, 5, FEL, 0.5), stroke(crack, 0.9, FEL_BRIGHT)]
    for x, y, r in ((80, 34, 3.2), (84, 37, 2.2), (2, 36, 2.6)):
        shapes.append(polygon(regular(x, y, r, 5, rng.uniform(0, 1)), mix(BT_STONE, BT_STONE_DARK, 0.4)))
    return render(88, 40, shapes)


def bt_lintel():
    """256x16: a cracked stone moulding along a window's top, a chunk out."""
    rng = random.Random(75)
    shapes = []
    for k in range(8):
        x0, x1 = k * 32 + 0.6, (k + 1) * 32 - 0.6
        tone = mix(BT_STONE_DARK, BT_STONE, rng.uniform(0.3, 0.8))
        top = 3 if k != 5 else 6
        pts = [(x0, top), (x1, top), (x1, 11), (x0, 11)]
        if k == 5:
            pts = [(x0, 3), (x0 + 9, 3), (x0 + 12, 7), (x0 + 20, 6), (x0 + 23, 3), (x1, 3), (x1, 11), (x0, 11)]
        shapes.append(polygon(pts, tone))
        shapes.append(stroke([(x0 + 0.5, 3.6 if k != 5 else 3.6), (x0 + 8, 3.6)], 0.8, light(tone, 0.16)))
        shapes.append(polygon(rect(x0, 9.6, x1, 11), dark(tone, 0.35)))
    pts = crack_walk(rng, 100, 4, 1.3, 7, 1.8, 0.5)
    shapes += [glow_line(pts, 3.5, FEL, 0.45), stroke(pts, 0.7, FEL_BRIGHT)]
    return band(256, 16, shapes)


def bt_temple_ring():
    """The minimap: a ring of draenei stone, broken at the top right,
    fel glowing in its cracks."""
    cx = cy = 128
    rng = random.Random(77)
    shapes = []
    r_in, r_out = 109, 123
    for k in range(22):
        a0, a1 = k * TAU / 22 + 0.014, (k + 1) * TAU / 22 - 0.014
        deg0 = math.degrees(a0) % 360
        if 298 <= deg0 <= 322:
            continue
        tone = mix(BT_STONE_DARK, BT_STONE_LIGHT, rng.uniform(0.15, 0.7))
        outer = r_out - (rng.uniform(2, 5) if 285 <= deg0 <= 335 else 0)
        pts = arc_pts(cx, cy, outer, a0, a1, 8) + arc_pts(cx, cy, r_in, a1, a0, 8)
        shapes.append(polygon(pts, tone))
        shapes.append(stroke(arc_pts(cx, cy, outer - 1.2, a0 + 0.01, a1 - 0.01, 8), 1.0, light(tone, 0.14)))
    for a in (205, 250, 95):
        ang = math.radians(a)
        x, y = polar(cx, cy, 116, ang)
        pts = crack_walk(rng, x, y, ang + math.pi / 2, 12, 2.2, 0.6)
        shapes += [glow_line(pts, 5, FEL, 0.45), stroke(pts, 0.9, FEL_BRIGHT)]
    for a in (228, 280):
        x, y = polar(cx, cy, 116, math.radians(a))
        shapes += lens_carving(x, y, 5, 10, math.radians(a), BT_STONE_DARK, c("#22301C"), FEL)
    return render(256, 256, shapes)


def bt_unit_lens():
    """28x20 (drawn 14x10): a small carved lens for the unit frames."""
    return render(28, 20, lens_carving(14, 11, 9, 22, math.pi / 2, BT_STONE_LIGHT, c("#2A4220"), FEL))


def bt_temple_pattern():
    def make(dx, dy):
        out = []
        for row in range(4):
            y = row * 32 + dy
            out.append(stroke([(dx - 2, y), (dx + 130, y)], 1.2, white(0.55)))
            off = 0 if row % 2 == 0 else 32
            for k in range(3):
                x = off + k * 64 + dx
                out.append(stroke([(x, y), (x, y + 32)], 1.2, white(0.55)))
        for x, y in ((32, 16), (96, 80)):
            pts = vesica(x + dx, y + dy, 9, 22, math.pi / 2)
            out.append(stroke(pts + [pts[0]], 1.3, WHITE))
            out.append(ellipse(x + dx, y + dy, 2, 2, WHITE))
        return out
    return pattern(128, 128, make, 0.13)


def bt_lens_track():
    def make(dx, dy):
        pts = vesica(16 + dx, 16 + dy, 6, 16, math.pi / 2)
        return [stroke(pts + [pts[0]], 1.1, WHITE)]
    return pattern(32, 32, make, 0.12)


def bt_lens_orn():
    return mask(32, 32, [polygon(vesica(16, 16, 15, 29), WHITE), ellipse(16, 16, 4.2, 4.2, CUT), ellipse(16, 16, 2.2, 2.2, WHITE)])


def bt_lens_jewel():
    return mask(64, 64, [polygon(vesica(32, 32, 30, 58), WHITE), ellipse(32, 32, 11, 11, CUT), ellipse(32, 32, 7, 7, WHITE)])


def bt_vesica_mark():
    return mask(64, 64, [polygon(vesica(32, 32, 36, 60), WHITE)])


def bt_lens_divider():
    def make(dx, dy):
        return [stroke([(dx - 2, 4), (dx + 34, 4)], 0.8, WHITE), polygon(vesica(16 + dx, 4, 4.2, 13, math.pi / 2), WHITE)]
    return mask(32, 8, tiled(32, 8, make, ys=False))


def crack_bar(h, seed):
    rng = random.Random(seed)
    cracks = []
    for k in range(7):
        x = k * 256 / 7 + rng.uniform(0, 20)
        cracks.append(crack_walk(rng, x, rng.uniform(0, h), rng.uniform(-0.6, 0.6), h * 1.6, h * 0.12, 0.7))

    def make(dx, dy):
        return [stroke([(x + dx, y) for x, y in pts], max(0.9, h * 0.05), WHITE) for pts in cracks]
    return bar(h, make, 0.64)


# --- Black Temple B: the chains -----------------------------------------------------------

IRON, IRON_LIGHT, IRON_DARK, IRON_HI = c("#3C3B45"), c("#76747F"), c("#1C1B22"), c("#A4A2B0")


def iron_fn(cy, ry):
    return lambda px, py: mix(IRON_HI, IRON_DARK, clamp((py - (cy - ry)) / (2 * ry)))


def link_face(x, y, rx, ry, t, rot=0.0):
    def col(u, v):
        return mix(IRON_HI, IRON_DARK, clamp((v + 1) / 2 * 1.1))
    return annulus(x, y, rx, ry, t, col, rot)


def link_edge(a, b, w):
    return [stroke([a, b], w, IRON_DARK), stroke([a, b], w * 0.45, IRON_LIGHT)]


def bt_plates_header():
    """Iron plates behind the title: bevelled, riveted, fel in the seams."""
    shapes = []
    for x0 in (0, 64):
        shapes.append(polygon(rect(x0 + 1.5, 2, x0 + 62.5, 38), c("#1A1920")))
        shapes.append(polygon(rect(x0 + 3, 3.5, x0 + 61, 36.5), lambda px, py: mix(c("#2C2B33"), c("#1F1E25"), clamp(py / 40))))
        shapes.append(stroke([(x0 + 3.5, 4), (x0 + 60.5, 4)], 0.9, c("#45444E")))
        for x, y in ((x0 + 7, 8), (x0 + 57, 8), (x0 + 7, 32), (x0 + 57, 32)):
            shapes.append(ellipse(x + 0.5, y + 0.6, 2.2, 2.2, c("#0E0D12")))
            shapes.append(ellipse(x, y, 2.0, 2.0, lambda u, v: mix(c("#6E6C78"), c("#2C2B33"), clamp((u + v + 1) / 2))))
    for x in (0, 64, 128):
        shapes.append(glow_line([(x, 2), (x, 38)], 4, FEL, 0.14))
    return band(128, 40, shapes, c("#0D0C10"))


def bt_chain_top():
    """64x16: a chain along a window's top (links face on, then edge on)."""
    shapes = []
    for k in range(-1, 3):
        x = 24 + k * 32
        shapes += link_edge((x - 9, 8), (x + 9, 8), 3.2)
    for k in range(-1, 3):
        shapes.append(link_face(8 + k * 32, 8, 7.5, 4.8, 2.0))
    return band(64, 16, shapes)


def bt_hanging_chain():
    """20x100: a chain hanging from a window's corner, a shackle on it."""
    shapes = []
    for k in range(5):
        y = 8 + k * 16
        shapes += link_edge((10, y + 4), (10, y + 13), 3.0)
    for k in range(5):
        shapes.append(link_face(10, 8 + k * 16, 4.4, 6.6, 1.7))
    shapes.append(annulus(10, 90, 7.5, 7.5, 2.4, lambda u, v: mix(IRON_HI, IRON_DARK, clamp((u + 1) / 2))))
    shapes.append(polygon(rect(0, 80, 20, 89), CUT))
    shapes += link_edge((1.5, 88), (18.5, 88), 3.2)
    return render(20, 100, shapes)


def bt_chain_ring():
    """The minimap with a chain round it."""
    cx = cy = 128
    r = 117
    n = 44
    shapes = []
    for k in range(n):
        if k % 2 == 1:
            a0, a1 = (k - 0.62) * TAU / n, (k + 0.62) * TAU / n
            shapes += link_edge(polar(cx, cy, r, a0), polar(cx, cy, r, a1), 3.2)
    for k in range(0, n, 2):
        a = k * TAU / n
        x, y = polar(cx, cy, r, a)
        shapes.append(link_face(x, y, 8, 5, 2.0, a + math.pi / 2))
    return render(256, 256, shapes)


def bt_unit_ring():
    """20x20 (drawn 10x10): an iron eyelet for the unit frames' corners."""
    return render(20, 20, [annulus(10, 10, 8, 8, 2.8, lambda u, v: mix(IRON_HI, IRON_DARK, clamp((u + v + 1) / 2))),
                           ellipse(7, 5.5, 1.2, 0.8, c("#C8C6D4"))])


def bt_rivet_pattern():
    def make(dx, dy):
        out = []
        for j in range(4):
            y = j * 32 + dy
            out.append(stroke([(dx - 2, y), (dx + 130, y)], 1.0, white(0.6)))
            for i in range(2):
                x = i * 64 + dx + (32 if j % 2 else 0)
                out.append(stroke([(x, y), (x, y + 32)], 1.0, white(0.6)))
                for ox, oy in ((5, 5), (59, 5), (5, 27), (59, 27)):
                    out.append(ellipse(x + ox, y + oy, 2, 2, WHITE))
        return out
    return pattern(128, 128, make, 0.12)


def bt_rivet_track():
    def make(dx, dy):
        return [ellipse(x + dx, 16 + dy, 1.7, 1.7, WHITE) for x in (8, 24)]
    return pattern(32, 32, make, 0.13)


def bt_bolt_orn():
    return mask(32, 32, [polygon(hex_pts(16, 16, 13.5, flat=False), WHITE), ellipse(16, 16, 4.4, 4.4, CUT)])


def bt_shackle_jewel():
    return mask(64, 64, [annulus(32, 32, 28, 28, 5.5, WHITE), polygon([(32, 13), (44, 32), (32, 51), (20, 32)], WHITE)])


def bt_rivet_mark():
    return mask(64, 64, [ellipse(32, 32, 27, 27, WHITE)])


def bt_chain_divider():
    def make(dx, dy):
        return [annulus(8 + dx, 4, 6, 3.2, 1.3, WHITE), stroke([(13 + dx, 4), (35 + dx, 4)], 1.6, WHITE)]
    return mask(32, 8, tiled(32, 8, make, ys=False))


def bt_chain_bar(h):
    p = per(256, h * 1.1)

    def make(dx, dy):
        mid = h / 2
        out = []
        for k in range(-1, int(round(256 / p)) + 1):
            x = k * p + dx
            out.append(stroke([(x + p * 0.3, mid), (x + p * 0.95, mid)], max(1.1, h * 0.12), WHITE))
            out.append(annulus(x + p * 0.12, mid, p * 0.24, h * 0.3, max(1.0, h * 0.09), WHITE))
        return out
    return bar(h, make, 0.64)


# --- Black Temple C: Illidari fel runes ------------------------------------------------------------

def bt_rune_header():
    """Black stone behind the title, fel runes carved in it, glowing."""
    rng = random.Random(81)
    shapes = []
    for x0, x1 in ((0, 46), (46, 90), (90, 128)):
        shapes.append(polygon(rect(x0 + 0.6, 0, x1 - 0.6, 40), mix(c("#120D17"), c("#1A1421"), rng.uniform(0, 1))))
    runes = [rune_strokes(rng) for _ in range(6)]
    for k, strokes in enumerate(runes):
        x = 10 + k * 21.3
        for line in strokes:
            pts = [(x + (px - 0.5) * 7, 20 + (py - 0.5) * 12) for px, py in line]
            shapes.append(glow_line(pts, 5, FEL, 0.08))
        shapes += draw_rune(x, 20, 12, strokes, 1.1, c("#2C4A21"))
    return band(128, 40, shapes, c("#0E0A12"))


def bt_fel_flame():
    """28x30: fel flames licking up off a window's corner."""
    cols = (FEL_DARK, FEL, c("#C8F890"), c("#F4FFE0"))
    shapes = [glow(14, 20, 14, FEL, 0.35)]
    shapes += flame(7.5, 29, 12, 9, cols, lean=-0.3, wave=0.35)
    shapes += flame(20.5, 29, 15, 10, cols, lean=0.25, wave=-0.35)
    shapes += flame(14, 29, 22, 13, cols, lean=0.08, wave=0.4)
    return render(28, 30, shapes)


def bt_rune_ring():
    """The minimap with fel runes round it, a faint fel glow."""
    cx = cy = 128
    rng = random.Random(83)
    shapes = [annulus(cx, cy, 124, 124, 13, lambda u, v: fade(FEL, 0.18 * (1 - abs(math.hypot(u, v) - 0.95) * 18)))]
    for k in range(16):
        a = k * TAU / 16
        if clear(math.degrees(a)):
            continue
        x, y = polar(cx, cy, 119, a)
        strokes = rune_strokes(rng)
        for line in strokes:
            pts = turn([(x + (px - 0.5) * 6.4, y + (py - 0.5) * 11) for px, py in line], x, y, a + math.pi / 2)
            shapes.append(glow_line(pts, 6, FEL, 0.3))
            shapes.append(stroke(pts, 1.5, FEL_BRIGHT))
    return render(256, 256, shapes)


def bt_unit_rune():
    """20x24 (drawn 10x12): one glowing rune for the unit frames."""
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.12, 0.3), (0.5, 0.52), (0.88, 0.3)], [(0.5, 0.7), (0.88, 0.9)]]
    shapes = [glow(10, 12, 11, FEL, 0.4)]
    shapes += draw_rune(10, 12, 18, strokes, 2.4, FEL_BRIGHT)
    return render(20, 24, shapes)


def bt_tattoo_pattern():
    curves = [((-10, 92), (30, 40), (70, 120), (138, 56)), ((-6, 20), (40, 6), (60, 50), (110, 26)),
              ((20, 128), (40, 100), (80, 96), (100, 70))]

    def make(dx, dy):
        out = []
        for p0, p1, p2, p3 in curves:
            pts = bez(*[(x + dx, y + dy) for x, y in (p0, p1, p2, p3)], 28)
            out.append(stroke(pts, 1, WHITE, taper=(0.6, 3.6)))
        return out
    return pattern(128, 128, make, 0.13)


def bt_rune_track():
    def make(dx, dy):
        return [stroke([(6 + dx, 20 + dy), (10 + dx, 12 + dy), (14 + dx, 20 + dy)], 1.2, WHITE),
                stroke([(24 + dx, 10 + dy), (24 + dx, 22 + dy)], 1.2, WHITE)]
    return pattern(32, 32, make, 0.12)


def bt_rune_orn():
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.5, 0.2), (0.88, 0.45)], [(0.5, 0.55), (0.12, 0.8)]]
    return mask(32, 32, draw_rune(16, 16, 28, strokes, 3.2, WHITE))


def bt_eye_jewel():
    return mask(64, 64, [polygon(vesica(32, 32, 28, 60, math.pi / 2), WHITE), polygon(vesica(32, 32, 7, 24), CUT)])


def bt_rune_mark():
    return mask(64, 64, [polygon([(32, 3), (56, 32), (32, 61), (8, 32)], WHITE), stroke([(32, 14), (32, 50)], 3.0, CUT)])


def bt_rune_divider():
    rng = random.Random(85)
    a, b = rune_strokes(rng), rune_strokes(rng)

    def make(dx, dy):
        out = draw_rune(8 + dx, 4, 7, a, 0.9, WHITE) + draw_rune(24 + dx, 4, 7, b, 0.9, WHITE)
        out += [ellipse(x + dx, 4, 0.7, 0.7, WHITE) for x in (1, 15, 17, 31)]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def bt_tattoo_bar(h):
    p = per(256, h * 2.0)

    def make(dx, dy):
        out = []
        for k in range(-1, int(round(256 / p)) + 1):
            x = k * p + dx
            pts = bez((x, h * 0.85), (x + p * 0.3, h * 0.1), (x + p * 0.6, h * 0.95), (x + p * 1.05, h * 0.2), 20)
            out.append(stroke(pts, 1, WHITE, taper=(max(0.6, h * 0.03), max(1.4, h * 0.14))))
        return out
    return bar(h, make, 0.64)


# ======================================================================================
# Molten Core
# ======================================================================================

OBS, OBS_MID, OBS_LIGHT, OBS_HI = c("#14100F"), c("#241C1B"), c("#3A2E2C"), c("#5A4844")
LAVA, LAVA_HOT, LAVA_CORE, LAVA_DARK = c("#FF6A1A"), c("#FFC04A"), c("#FFF0B0"), c("#9A2C08")


def mc_obsidian_header():
    """Obsidian behind the title: dark facets, lava glowing in its cracks
    (dimmed, so the title reads)."""
    rng = random.Random(91)
    shapes = []
    x = -8.0
    while x < 136:
        w = rng.uniform(14, 26)
        top = rng.uniform(-2, 6)
        pts = [(x, 40), (x + rng.uniform(-3, 3), top + 14), (x + w * 0.4, top), (x + w, top + rng.uniform(4, 10)), (x + w + 2, 40)]
        shapes.append(polygon(pts, mix(OBS, OBS_MID, rng.uniform(0.2, 1.0))))
        x += w
    for _ in range(2):
        pts = crack_walk(rng, rng.uniform(0, 128), rng.uniform(10, 34), rng.uniform(-0.4, 0.4), 40, 3, 0.55)
        shapes += [glow_line(pts, 3.2, LAVA, 0.16), stroke(pts, 0.8, c("#7E300F")), stroke(pts, 0.35, c("#B85A26"))]
    return band(128, 40, shapes, c("#120B0A"))


def mc_rock_top():
    """256x24: a jagged obsidian edge along a window's top, a lava seam."""
    rng = random.Random(93)
    top = []
    x = 0.0
    while x < 256:
        top.append((x, rng.uniform(6, 9) if len(top) % 2 else rng.uniform(10, 14)))
        x += rng.uniform(8, 15)
    top.append((256, top[0][1]))
    pts = [(-0.5, 18)] + top + [(256.5, 18)]
    shapes = [polygon(pts, lambda px, py: mix(OBS_LIGHT, OBS, clamp((py - 6) / 12)))]
    for (x0, y0), (x1, y1) in zip(top, top[1:]):
        if y1 < y0:
            shapes.append(polygon([(x0, y0), (x1, y1), (x1 + 1.5, y1 + 3), (x0 + 1, y0 + 2)], OBS_HI))
    seam = [(x, 15.5 + 0.8 * math.sin(x * 0.11)) for x in range(-4, 261, 4)]
    shapes += lava_crack(seam, 0.9, LAVA, LAVA, LAVA_HOT)
    return band(256, 24, shapes)


def mc_rock_chunk():
    """64x36: an obsidian boulder over a window's corner, lava in its crack."""
    body = [(4, 34), (2, 26), (12, 16), (26, 10), (42, 12), (56, 18), (62, 28), (58, 34)]
    shapes = [polygon(body, lambda px, py: mix(OBS_LIGHT, OBS, clamp((py - 10) / 24)))]
    shapes.append(polygon([(12, 16), (26, 10), (42, 12), (34, 18), (18, 21)], OBS_HI))
    shapes.append(polygon([(42, 12), (56, 18), (50, 22), (34, 18)], mix(OBS_LIGHT, OBS_HI, 0.4)))
    crack = [(20, 33), (24, 26), (30, 23), (34, 26), (42, 22), (47, 25)]
    shapes += lava_crack(crack, 1.2, LAVA, LAVA, LAVA_HOT)
    return render(64, 36, shapes)


def mc_obsidian_ring():
    """The minimap in a ring of obsidian, its rim jagged, lava in it."""
    cx = cy = 128
    rng = random.Random(95)
    shapes = []
    n = 40
    outer = []
    for k in range(n + 1):
        a = k * TAU / n
        outer.append(polar(cx, cy, rng.uniform(119, 126) if k % 2 else rng.uniform(116, 120), a))
    outer[-1] = outer[0]

    def body(px, py):
        d = math.hypot(px - cx, py - cy)
        if d < 109:
            return None
        return mix(OBS_LIGHT, OBS, clamp((d - 109) / 16))
    shapes.append(polygon(outer, body))
    for k in range(0, n, 3):
        a = (k + 0.5) * TAU / n
        shapes.append(polygon([polar(cx, cy, 111, a - 0.05), polar(cx, cy, 120, a), polar(cx, cy, 113, a + 0.06)], OBS_HI))
    for a0, a1 in ((170, 260), (285, 345), (70, 120)):
        pts = [polar(cx, cy, 113 + rng.uniform(-1.5, 1.5), math.radians(a)) for a in range(a0, a1 + 1, 6)]
        shapes += lava_crack(pts, 1.0, LAVA, LAVA, LAVA_HOT)
    return render(256, 256, shapes)


def mc_unit_shard():
    """28x24 (drawn 14x12): a small obsidian shard, a lava crack in it."""
    shapes = [polygon([(4, 23), (8, 10), (14, 2), (20, 8), (25, 23)], lambda px, py: mix(OBS_HI, OBS, clamp((px - 4) / 21)))]
    crack = [(12, 22), (14, 15), (12, 10)]
    shapes += lava_crack(crack, 1.0, LAVA, LAVA, LAVA_HOT)
    return render(28, 24, shapes)


def crack_pattern(seed, count, strength):
    rng = random.Random(seed)
    cracks = []
    for _ in range(count):
        main = crack_walk(rng, rng.uniform(0, 128), rng.uniform(0, 128), rng.uniform(0, TAU), 46, 4, 0.5)
        cracks.append((main, 1.3))
        i = rng.randrange(2, len(main) - 2)
        cracks.append((crack_walk(rng, main[i][0], main[i][1], rng.uniform(0, TAU), 16, 3, 0.6), 0.9))

    def make(dx, dy):
        return [stroke([(x + dx, y + dy) for x, y in pts], w, WHITE) for pts, w in cracks]
    return pattern(128, 128, make, strength)


def mc_crack_track():
    rng = random.Random(97)
    pts = crack_walk(rng, -2, 16, 0, 36, 3, 0.7)

    def make(dx, dy):
        return [stroke([(x + dx, y + dy) for x, y in pts], 1.1, WHITE)]
    return pattern(32, 32, make, 0.12)


def mc_shard_orn():
    return mask(32, 32, [polygon([(5, 29), (10, 12), (17, 2), (24, 10), (28, 29)], WHITE)])


def mc_lava_jewel():
    shapes = [polygon([(32, 3), (58, 32), (32, 61), (6, 32)], WHITE)]
    shapes += [stroke([(32, 12), (28, 26), (35, 34), (30, 52)], 2.0, CUT), stroke([(28, 26), (18, 30)], 1.6, CUT)]
    return mask(64, 64, shapes)


def mc_ember_mark():
    return mask(64, 64, [polygon(regular(32, 32, 28, 4, 0, 30), WHITE), ellipse(32, 32, 20, 20, WHITE)])


def mc_crack_divider():
    def make(dx, dy):
        return [stroke([(dx - 2, 4), (dx + 6, 3), (dx + 11, 5.4), (dx + 18, 2.8), (dx + 24, 5), (dx + 34, 4)], 1.1, WHITE)]
    return mask(32, 8, tiled(32, 8, make, ys=False))


# --- Molten Core B: basalt and molten runes ----------------------------------------------------------

BAS, BAS_LIGHT, BAS_HI, BAS_DARK = c("#2B2A2F"), c("#45434B"), c("#5E5B65"), c("#18171B")
MOLTEN, MOLTEN_HOT, MOLTEN_DARK = c("#FF9A2A"), c("#FFD970"), c("#A8440C")


def hex_tiling(w, h, rx, ry, rows):
    """Flat-top hexes: (centre x, centre y) over w (a whole number of
    columns pairs fit), `rows` rows of height ry * sqrt 3."""
    out = []
    step_x = 1.5 * rx
    hh = math.sqrt(3) * ry
    cols = int(round(w / step_x))
    for i in range(-1, cols + 2):
        for j in range(-1, rows + 2):
            out.append((i * step_x, j * hh + (hh / 2 if i % 2 else 0), i, j))
    return out


def mc_basalt_header():
    """Basalt column tops behind the title: dark hexes, molten seams in a
    few, one rune glowing (dim)."""
    rng = random.Random(101)
    rx = 128 / 12
    shapes = []
    glowing = []
    for x, y, i, j in hex_tiling(128, 40, rx, rx * 0.86, 3):
        if i < 0 or i >= 8:
            continue
        tone = mix(BAS_DARK, BAS, rng.uniform(0.25, 0.85))
        shapes.append(polygon(hex_pts(x, y, rx - 1.1, (rx - 1.1) * 0.86), tone))
        shapes.append(stroke(hex_pts(x, y, rx - 1.6, (rx - 1.6) * 0.86)[3:6], 0.8, light(tone, 0.08)))
        if rng.random() < 0.18:
            glowing.append(hex_pts(x, y, rx - 0.3, (rx - 0.3) * 0.86))
    for pts in glowing:
        a, b = pts[0], pts[1]
        shapes.append(glow_line([a, b], 4, MOLTEN, 0.18))
        shapes.append(stroke([a, b], 0.7, c("#8A4C1E")))
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.12, 0.3), (0.5, 0.52), (0.88, 0.3)]]
    shapes.append(glow(80, 18, 8, MOLTEN, 0.12))
    shapes += draw_rune(80, 18, 10, strokes, 1.0, c("#6E3E18"))
    return band(128, 40, shapes, c("#0F0E11"))


def basalt_column(x, top, bottom, rx, glow_seam=False):
    ry = rx * 0.45
    hexp = hex_pts(x, top, rx, ry)
    out = [polygon([hexp[0], hexp[1], hexp[2], hexp[3], (hexp[3][0], bottom), (hexp[0][0], bottom)], BAS_DARK),
           polygon([hexp[1], hexp[2], (hexp[2][0], bottom), (hexp[1][0], bottom)], BAS),
           polygon([hexp[0], hexp[1], (hexp[1][0], bottom), (hexp[0][0], bottom)], BAS_LIGHT),
           polygon(hexp, lambda px, py: mix(BAS_HI, BAS_LIGHT, clamp((py - top + ry) / (2 * ry))))]
    if glow_seam:
        seam = [(hexp[1][0] + 0.2, top + ry + 2), (hexp[1][0] + 1.2, (top + bottom) / 2), (hexp[1][0] - 0.2, bottom)]
        out += [glow_line(seam, 5, MOLTEN, 0.5), stroke(seam, 0.8, MOLTEN_HOT)]
    return out


def mc_columns():
    """48x40: basalt columns rising off a window's corner."""
    shapes = basalt_column(10, 20, 40, 7.5) + basalt_column(38, 24, 40, 7) + basalt_column(24, 13, 40, 8, True)
    return render(48, 40, shapes)


def mc_rune_tablet():
    """28x40: a basalt tablet on a short chain, a molten rune on it."""
    shapes = [stroke([(14, 0), (14, 12)], 1.2, BAS_HI)]
    shapes.append(annulus(14, 5, 2.4, 3.4, 1.0, BAS_HI))
    shapes.append(polygon(hex_pts(14, 25, 12, flat=False), lambda px, py: mix(BAS_LIGHT, BAS_DARK, clamp((py - 13) / 24))))
    shapes.append(polygon(hex_pts(14, 25, 10, flat=False), BAS))
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.5, 0.18), (0.88, 0.45)], [(0.5, 0.55), (0.12, 0.82)]]
    shapes.append(glow(14, 25, 10, MOLTEN, 0.55))
    shapes += draw_rune(14, 25, 13, strokes, 1.6, MOLTEN_HOT)
    return render(28, 40, shapes)


def mc_basalt_ring():
    """The minimap in a ring of basalt hexes, four runes glowing in it."""
    cx = cy = 128
    rng = random.Random(103)
    shapes = []
    n = 36
    for k in range(n):
        a = k * TAU / n
        if clear(math.degrees(a)):
            continue
        x, y = polar(cx, cy, 118, a)
        tone = mix(BAS_DARK, BAS_LIGHT, rng.uniform(0.2, 0.8))
        shapes.append(polygon(turn(hex_pts(x, y, 10.5), x, y, a), c("#0E0D10")))
        shapes.append(polygon(turn(hex_pts(x, y, 9.5), x, y, a), tone))
    for a in (190, 230, 310, 120):
        x, y = polar(cx, cy, 118, math.radians(a))
        shapes.append(glow(x, y, 10, MOLTEN, 0.5))
        shapes += draw_rune(x, y, 12, rune_strokes(rng), 1.5, MOLTEN_HOT)
    return render(256, 256, shapes)


def mc_unit_stub():
    """24x24 (drawn 12x12): a small basalt hex, a molten rune in it."""
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.12, 0.3), (0.5, 0.52), (0.88, 0.3)]]
    shapes = [polygon(hex_pts(12, 12, 11, flat=False), lambda px, py: mix(BAS_HI, BAS_DARK, clamp((py - 1) / 22))),
              polygon(hex_pts(12, 12, 8.8, flat=False), BAS), glow(12, 12, 9, MOLTEN, 0.6)]
    shapes += draw_rune(12, 12, 11, strokes, 1.8, MOLTEN_HOT)
    return render(24, 24, shapes)


def hex_pattern(size, rows, width, strength):
    ry = size / rows / math.sqrt(3)
    rx = size / (3 * round(size / (3 * ry)))

    def make(dx, dy):
        out = []
        for x, y, i, j in hex_tiling(size, size, rx, ry, rows):
            pts = hex_pts(x + dx, y + dy, rx, ry)
            out.append(stroke(pts + [pts[0]], width, WHITE))
        return out
    return pattern(size, size, make, strength)


def mc_hex_orn():
    pts = hex_pts(16, 16, 9.5)
    return mask(32, 32, [polygon(hex_pts(16, 16, 15), WHITE), stroke(pts + [pts[0]], 1.4, CUT)])


def mc_hex_jewel():
    strokes = [[(0.5, 0.0), (0.5, 1.0)], [(0.12, 0.3), (0.5, 0.52), (0.88, 0.3)]]
    return mask(64, 64, [polygon(hex_pts(32, 32, 29), WHITE)] + draw_rune(32, 32, 30, strokes, 4, CUT))


def mc_hex_mark():
    return mask(64, 64, [polygon(hex_pts(32, 32, 29, flat=False), WHITE)])


def mc_hex_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.7, white(0.7))]
        for x in (8, 24):
            pts = hex_pts(x + dx, 4, 3.4)
            out.append(stroke(pts + [pts[0]], 0.9, WHITE))
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def mc_hex_bar(h):
    ry = h / (2 * math.sqrt(3))
    rx = 256 / (3 * round(256 / (3 * ry)))

    def make(dx, dy):
        out = []
        for x, y, i, j in hex_tiling(256, h, rx, ry, 2):
            pts = hex_pts(x + dx, y, rx, ry)
            out.append(stroke(pts + [pts[0]], max(0.9, h * 0.06), WHITE))
        return out
    return bar(h, make, 0.64)


# --- Molten Core C: Ragnaros' flames -------------------------------------------------------------------

F_RED, F_ORANGE, F_YELLOW, F_CORE, F_DARK = c("#C8301A"), c("#F2741E"), c("#FFC84A"), c("#FFF2B8"), c("#5A1206")
FIRE = (F_RED, F_ORANGE, F_YELLOW, F_CORE)


def mc_flame_header():
    """Flames rising behind the title (dimmed, so it reads)."""
    rng = random.Random(111)
    cols = (dark(F_DARK, 0.2), dark(F_RED, 0.58), dark(F_ORANGE, 0.66), dark(F_YELLOW, 0.7))
    shapes = []
    for k in range(9):
        x = k * 14.2 + rng.uniform(-2, 2)
        shapes += flame(x, 46, rng.uniform(22, 36), rng.uniform(10, 14), cols, rng.uniform(-0.25, 0.25), rng.uniform(-0.3, 0.3))
    return band(128, 40, shapes, c("#150605"))


def mc_flame_top():
    """128x20: small flames along a window's top edge."""
    shapes = []
    for x, h, w, lean in ((12, 9, 5, 0.1), (38, 12, 6, -0.15), (64, 8, 4.6, 0.2), (90, 11, 5.6, -0.05), (116, 9, 5, 0.12)):
        shapes.append(glow(x, 15, 6, F_ORANGE, 0.35))
        shapes += flame(x, 18, h, w, FIRE, lean, 0.2)
    return band(128, 20, shapes)


def mc_flame_cluster():
    """32x32: a cluster of flames off a window's corner."""
    shapes = [glow(16, 20, 15, F_ORANGE, 0.35)]
    shapes += flame(8, 31, 15, 7.5, FIRE, -0.25, 0.2)
    shapes += flame(24, 31, 18, 8, FIRE, 0.2, -0.2)
    shapes += flame(16, 31, 27, 11, FIRE, 0.04, 0.25)
    return render(32, 32, shapes)


def mc_fire_ring():
    """The minimap in a ring of fire, flames leaning outward."""
    cx = cy = 128
    r = rim(16)
    rng = random.Random(113)
    shapes = [annulus(cx, cy, r + 4, r + 4, 8, lambda u, v: fade(F_ORANGE, 0.25))]
    for k in range(44):
        a = k * TAU / 44
        h = rng.uniform(12, 19)
        if clear(math.degrees(a)):
            continue
        base = polar(cx, cy, r - 1, a)
        fl = flame(base[0], base[1], h, rng.uniform(6, 8), FIRE, rng.uniform(-0.15, 0.15), 0.2)
        shapes += [rotated(s, base[0], base[1], a + math.pi / 2) for s in fl]
    return render(256, 256, shapes)


def rotated(shape, cx, cy, ang):
    """A shape turned by ang about (cx, cy)."""
    ca, sn = math.cos(-ang), math.sin(-ang)
    b = shape.bbox
    corners = [(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])]
    moved = turn(corners, cx, cy, ang)
    xs, ys = [p[0] for p in moved], [p[1] for p in moved]

    def fn(x, y, f=shape.fn):
        dx, dy = x - cx, y - cy
        return f(cx + dx * ca - dy * sn, cy + dx * sn + dy * ca)
    return Shape((min(xs), min(ys), max(xs), max(ys)), fn)


def mc_unit_flame():
    """16x24 (drawn 8x12): one small flame for the unit frames."""
    return render(16, 24, [glow(8, 16, 8, F_ORANGE, 0.35)] + flame(8, 23, 20, 9, FIRE, 0.1, 0.2))


def mc_flame_pattern():
    def make(dx, dy):
        out = []
        for x, y, h in ((32, 60, 40), (96, 124, 40), (96, 40, 18), (32, 104, 18)):
            pts = flame_pts(x + dx, y + dy, h, h * 0.42, 0.1, 0.2)
            out.append(stroke(pts + [pts[0]], 1.3, WHITE))
        return out
    return pattern(128, 128, make, 0.13)


def mc_flame_track():
    def make(dx, dy):
        return [polygon(flame_pts(x + dx, 26 + dy, 14, 7, 0.1, 0.2), WHITE) for x in (8, 24)]
    return pattern(32, 32, make, 0.11)


def mc_flame_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 7.2), (dx + 34, 7.2)], 0.7, white(0.7))]
        out += [polygon(flame_pts(x + dx, 7.5, 6.2, 3.4, 0.1, 0.2), WHITE) for x in (4, 12, 20, 28)]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def mc_flame_bar(h):
    p = per(256, h * 0.55)

    def make(dx, dy):
        out = []
        for k in range(-1, int(round(256 / p)) + 1):
            x = k * p + dx + p / 2
            hh = h * (0.78 if k % 2 == 0 else 0.6)
            out.append(polygon(flame_pts(x, h + 1, hh, p * 0.85, 0.15, 0.2), WHITE))
        return out
    return bar(h, make, 0.64)


# ======================================================================================
# Naxxramas
# ======================================================================================

SLATE, SLATE_DARK, SLATE_LIGHT = c("#1F2B31"), c("#11191D"), c("#33454D")
N_IRON, N_IRON_LIGHT, N_TEAL, N_TEAL_DIM = c("#262E35"), c("#56656E"), c("#52E0C8"), c("#2C8A7C")


def nx_necropolis_header():
    """Scourge stone behind the title: dark blocks, pointed windows lit
    teal, a row of small spikes along the foot (dim)."""
    rng = random.Random(121)
    shapes = []
    for x0, x1 in ((0, 32), (32, 64), (64, 96), (96, 128)):
        shapes.append(polygon(rect(x0 + 0.6, 0, x1 - 0.6, 34), mix(SLATE_DARK, SLATE, rng.uniform(0.2, 0.6))))
    for x in (16, 48, 80, 112):
        pts = [(x - 4, 28), (x - 4, 14)] + bez((x - 4, 14), (x - 4, 9), (x - 1, 6), (x, 4), 6)[1:] + \
            bez((x, 4), (x + 1, 6), (x + 4, 9), (x + 4, 14), 6)[1:] + [(x + 4, 28)]
        shapes.append(polygon(pts, N_IRON))
        inner = [(px + (x - px) * 0.35, py + (16 - py) * 0.12) for px, py in pts]
        shapes.append(glow(x, 17, 9, N_TEAL, 0.25))
        shapes.append(polygon(inner, fade(N_TEAL_DIM, 0.55)))
    for k in range(16):
        x = k * 8 + 4
        shapes.append(polygon([(x - 3.2, 40), (x, 33.5), (x + 3.2, 40)], c("#0B1114")))
    shapes.append(polygon(rect(-1, 34, 129, 40), c("#141D22")))
    return band(128, 40, shapes, c("#0C1316"))


def thorn(bx, by, w, h, lean, col):
    """A curved spike from a base w wide at (bx, by), its tip h up."""
    tip = (bx + lean, by - h)
    left = bez((bx - w / 2, by), (bx - w / 2, by - h * 0.4), (bx + lean * 0.4, by - h * 0.8), tip, 10)
    right = bez(tip, (bx + lean * 0.6, by - h * 0.6), (bx + w / 2, by - h * 0.35), (bx + w / 2, by), 10)
    return polygon(left + right[1:], col)


def nx_spikes():
    """64x16: iron thorns rising off a window's top."""
    col = lambda px, py: mix(N_IRON_LIGHT, N_IRON, clamp((py - 2) / 12))  # noqa: E731
    shapes = [thorn(16, 14, 6, 11, 3.5, col), thorn(48, 14, 5, 8, -2.5, col)]
    shapes += [stroke([(15.2, 12), (18, 6)], 0.6, N_TEAL_DIM), stroke([(47.6, 12), (46, 8)], 0.6, N_TEAL_DIM)]
    return band(64, 16, shapes)


def nx_buttress():
    """36x36: the necropolis' iron claws over a window's corner."""
    col = lambda px, py: mix(N_IRON_LIGHT, N_IRON, clamp((py - 4) / 28))  # noqa: E731
    shapes = [thorn(8, 30, 7, 26, -5, col), thorn(16, 30, 6, 18, 7, col), thorn(24, 30, 5, 11, 9, col)]
    shapes.append(polygon([(1, 28), (30, 28), (28, 35), (3, 35)], lambda px, py: mix(SLATE_LIGHT, SLATE_DARK, clamp((py - 28) / 7))))
    shapes += [glow(12, 31.5, 6, N_TEAL, 0.55), ellipse(12, 31.5, 1.6, 1.6, c("#B8FFF2"))]
    return render(36, 36, shapes)


def nx_spiked_ring():
    """The minimap in a dark iron ring, curved spikes outward, teal lights."""
    cx = cy = 128
    r = rim(14)
    shapes = []

    def band_col(px, py):
        d = math.hypot(px - cx, py - cy)
        return mix(N_IRON_LIGHT, N_IRON, clamp(abs(d - (r + 2)) / 5))
    for k in range(14):
        a = k * TAU / 14
        if clear(math.degrees(a)):
            continue
        base = polar(cx, cy, r + 4, a)
        t = thorn(base[0], base[1], 7, 15, 4, lambda px, py: mix(N_IRON_LIGHT, N_IRON, 0.5))
        shapes.append(rotated(t, base[0], base[1], a + math.pi / 2))
    shapes.append(annulus(cx, cy, r + 7, r + 7, 8, band_col))
    for k in range(28):
        x, y = polar(cx, cy, r + 3, k * TAU / 28 + TAU / 56)
        shapes.append(ellipse(x, y, 1.3, 1.3, c("#0F1518")))
    for a in (200, 250, 300, 95):
        x, y = polar(cx, cy, r + 3, math.radians(a))
        shapes += [glow(x, y, 6, N_TEAL, 0.6), ellipse(x, y, 1.5, 1.5, c("#B8FFF2"))]
    return render(256, 256, shapes)


def nx_unit_spike():
    """16x24 (drawn 8x12): one curved iron spike for the unit frames."""
    col = lambda px, py: mix(N_IRON_LIGHT, N_IRON, clamp((py - 2) / 20))  # noqa: E731
    return render(16, 24, [thorn(7, 23, 7, 21, 4, col), stroke([(6.5, 20), (9, 9)], 0.8, N_TEAL_DIM)])


def nx_sigil_pattern():
    rng = random.Random(123)
    runes = [rune_strokes(rng), rune_strokes(rng)]

    def sigil(x, y, s, strokes):
        out = [annulus(x, y, s, s, 1.3, WHITE)]
        out += draw_rune(x, y, s * 1.1, strokes, 1.2, WHITE)
        for k in range(4):
            a = k * TAU / 4 + TAU / 8
            out.append(stroke([polar(x, y, s + 1, a), polar(x, y, s + 4, a)], 1.1, WHITE))
        return out

    def make(dx, dy):
        return sigil(32 + dx, 32 + dy, 13, runes[0]) + sigil(96 + dx, 96 + dy, 13, runes[1])
    return pattern(128, 128, make, 0.13)


def nx_notch_track():
    def make(dx, dy):
        return [stroke([(2 + dx, 16 + dy), (12 + dx, 16 + dy)], 1.1, WHITE), stroke([(18 + dx, 16 + dy), (28 + dx, 16 + dy)], 1.1, WHITE),
                polygon([(14 + dx, 13 + dy), (16 + dx, 16 + dy), (14 + dx, 19 + dy), (12 + dx, 16 + dy)], WHITE)]
    return pattern(32, 32, make, 0.12)


def nx_claw_orn():
    return mask(32, 32, [thorn(12, 30, 10, 28, 9, WHITE)])


def nx_sigil_jewel():
    shapes = [annulus(32, 32, 28, 28, 5.5, WHITE)]
    shapes += [polygon([(x - 4, 20), (x + 4, 20), (x, 36)], WHITE) for x in (22, 32, 42)]
    shapes.append(ellipse(32, 44, 4, 4, WHITE))
    return mask(64, 64, shapes)


def nx_spike_mark():
    return mask(64, 64, [polygon([(32, 2), (45, 32), (32, 62), (19, 32)], WHITE)])


def nx_spike_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 6.6), (dx + 34, 6.6)], 0.7, white(0.7))]
        out += [polygon([(x + dx - 2, 7), (x + dx, 1.6), (x + dx + 2, 7)], WHITE) for x in (4, 12, 20, 28)]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def nx_sigil_bar(h):
    p = per(256, h * 1.3)

    def make(dx, dy):
        out = [stroke([(dx - 2, h / 2), (dx + 258, h / 2)], max(0.7, h * 0.04), white(0.8))]
        for k in range(-1, int(round(256 / p)) + 1):
            x = k * p + dx + p / 2
            out.append(annulus(x, h / 2, h * 0.32, h * 0.32, max(1.0, h * 0.07), WHITE))
            out.append(stroke([(x, h * 0.26), (x, h * 0.74)], max(0.9, h * 0.06), WHITE))
        return out
    return bar(h, make, 0.64)


# --- Naxxramas B: bone and webs -----------------------------------------------------------

BONE, BONE_SHADE, BONE_DARK = c("#D9D0B6"), c("#A39A80"), c("#4E4838")
WEB = c("#D8EEEA")


def nx_rib_header():
    """Ribs behind the title, a spine along the foot (dim bone)."""
    shapes = []
    rib, rib_hi = c("#2C2A24"), c("#383529")
    for k in range(9):
        x = k * 16 + 6
        pts = bez((x, 36), (x - 2, 22), (x - 9, 11), (x - 17, 3), 14)
        shapes.append(stroke(pts, 1, rib, taper=(3.4, 1.4)))
        shapes.append(stroke([(px + 0.5, py - 0.3) for px, py in pts], 1, rib_hi, taper=(1.0, 0.4)))
    for k in range(8):
        x = k * 16 + 6
        shapes.append(ellipse(x, 37, 6.2, 3.0, c("#33302A")))
        shapes.append(ellipse(x, 36.2, 4.6, 1.5, c("#403C31")))
    return band(128, 40, shapes, c("#0F1619"))


def nx_web_corner(size, reach, col=None):
    """A web spun off a frame's corner: its middle at the art's bottom
    right, threads out to the left and up (it hangs outside the frame)."""
    col = col or fade(WEB, 0.55)
    return render(size, size, web(size - 3, size - 3, math.pi, math.pi * 1.5, 6, [reach * f for f in (0.2, 0.38, 0.57, 0.78, 1.0)],
                                  col, 1.0, 0.18))


def nx_spider():
    """20x56 (drawn 10x28): a spider on its thread."""
    shapes = [stroke([(10, 0), (10, 38)], 0.9, fade(WEB, 0.75))]
    shapes += spider(10, 44, 13, c("#8A8F86"), c("#6BFFE6"))
    return render(20, 56, shapes)


def nx_bone_ring():
    """The minimap ringed with bones end to end (gaps at the buttons), a
    web in its top-left corner."""
    cx = cy = 128
    shapes = web(10, 10, 0.02, math.pi / 2 - 0.02, 5, [14, 26, 40, 56], fade(WEB, 0.5), 1.1, 0.2)
    shapes += spider(46, 46, 7, c("#15181B"), c("#5BE8D2"))
    for a in range(0, 360, 20):
        if clear(a) or clear(a + 20):
            continue
        a0, a1 = math.radians(a + 2), math.radians(a + 18)
        p, q = polar(cx, cy, 118, a0), polar(cx, cy, 118, a1)
        shapes += bone(p[0], p[1], q[0], q[1], 4.2, BONE, BONE_DARK)
    return render(256, 256, shapes)


def nx_unit_web():
    """32x24 (drawn 16x12): a wisp of web off the unit frames' corner."""
    return render(32, 24, web(2, 22, -math.pi / 2, 0, 4, [7, 13, 19], fade(WEB, 0.6), 1.0, 0.2))


def nx_web_pattern():
    def make(dx, dy):
        return web(64 + dx, 64 + dy, 0, TAU * 11 / 12, 12, [10, 20, 32, 46], WHITE, 1.0, 0.16)
    return pattern(128, 128, make, 0.1)


def vertebra(x, y, s, col=WHITE):
    return [ellipse(x, y, s * 0.42, s * 0.3, col), ellipse(x - s * 0.42, y, s * 0.22, s * 0.12, col),
            ellipse(x + s * 0.42, y, s * 0.22, s * 0.12, col), ellipse(x, y - s * 0.32, s * 0.12, s * 0.16, col)]


def nx_vertebra_track():
    def make(dx, dy):
        return vertebra(16 + dx, 16 + dy, 18)
    return pattern(32, 32, make, 0.12)


def nx_web_orn():
    return mask(32, 32, web(2, 2, 0, math.pi / 2, 4, [8, 15, 23], WHITE, 1.8, 0.2))


def skull(cx, cy, s, cut=CUT):
    k = s / 64
    return [ellipse(cx, cy - 4 * k, 21 * k, 19 * k, WHITE),
            polygon([(cx - 12 * k, cy + 6 * k), (cx + 12 * k, cy + 6 * k), (cx + 10 * k, cy + 22 * k), (cx - 10 * k, cy + 22 * k)], WHITE),
            ellipse(cx - 8 * k, cy - 2 * k, 5.5 * k, 6 * k, cut), ellipse(cx + 8 * k, cy - 2 * k, 5.5 * k, 6 * k, cut),
            polygon([(cx, cy + 4 * k), (cx - 2.5 * k, cy + 9 * k), (cx + 2.5 * k, cy + 9 * k)], cut)] + \
        [stroke([(cx + x * k, cy + 14 * k), (cx + x * k, cy + 22 * k)], 1.4 * k + 0.4, cut) for x in (-5, 0, 5)]


def nx_skull_jewel():
    return mask(64, 64, skull(32, 30, 64))


def nx_skull_mark():
    return mask(64, 64, [ellipse(32, 30, 26, 24, WHITE), polygon(rect(20, 36, 44, 58), WHITE),
                         ellipse(23, 31, 6, 7, CUT), ellipse(41, 31, 6, 7, CUT)])


def nx_vertebra_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.6, white(0.7))]
        for x in (4, 12, 20, 28):
            out += vertebra(x + dx, 4.4, 6.5)
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def nx_vertebra_bar(h):
    p = per(256, h * 0.7)

    def make(dx, dy):
        out = []
        for k in range(-1, int(round(256 / p)) + 1):
            out += vertebra(k * p + dx + p / 2, h / 2, p * 0.9)
        return out
    return bar(h, make, 0.66)


# --- Naxxramas C: frost --------------------------------------------------------------------

ICE, ICE_MID, ICE_DEEP, FROST = c("#C6F0FF"), c("#86C8E2"), c("#3A7C9C"), c("#F2FCFF")


def nx_frost_header():
    """Frozen stone behind the title: faint frost cracks, ferns of frost
    along the foot (dim)."""
    rng = random.Random(131)
    shapes = []
    for _ in range(4):
        pts = crack_walk(rng, rng.uniform(0, 128), rng.uniform(4, 30), rng.uniform(0, TAU), 20, 2.4, 0.6)
        shapes.append(stroke(pts, 0.7, fade(ICE_MID, 0.18)))
    for k in range(6):
        x = k * 21.3 + 6
        stem = bez((x, 41), (x + 1, 34), (x + 5, 28), (x + 4, 21), 12)
        shapes.append(stroke(stem, 1.0, fade(ICE_MID, 0.24)))
        for i in range(2, len(stem) - 1, 2):
            px, py = stem[i]
            ln = 4 * (1 - i / len(stem)) + 1.2
            shapes.append(stroke([(px, py), (px - ln, py - ln * 0.8)], 0.8, fade(ICE_MID, 0.2)))
            shapes.append(stroke([(px, py), (px + ln, py - ln * 0.7)], 0.8, fade(ICE_MID, 0.2)))
    return band(128, 40, shapes, c("#0D1A24"))


def ice(spec, glow_r=0):
    shapes = []
    if glow_r:
        xs = [s[0] for s in spec]
        ys = [s[1] for s in spec]
        shapes.append(glow(sum(xs) / len(xs), sum(ys) / len(ys), glow_r, ICE, 0.3))
    for x, y, ln, wd, ang in spec:
        shapes += crystal(x, y, ln, wd, ang, lambda px, py: mix(FROST, ICE, 0.4), ICE_MID, FROST)
    return shapes


def nx_crystals():
    """48x40: ice crystals over a window's corner."""
    spec = [(8, 33, 14, 5, -2.3), (38, 33, 12, 4.5, -0.85), (14, 26, 24, 7.5, -1.85), (31, 27, 20, 7, -1.2), (22, 22, 30, 9, -1.55)]
    return render(48, 40, ice(spec, 20))


def nx_frost_top():
    """256x14: rime along a window's top: small ice spikes in clusters."""
    spec = []
    for cx_ in (40, 130, 210):
        for dx, ln, wd, ang in ((-4, 7, 2.6, -1.9), (0, 11, 3.2, -1.57), (4, 8, 2.8, -1.25)):
            spec.append((cx_ + dx + math.cos(ang) * ln / 2, 10 + math.sin(ang) * ln / 2, ln, wd, ang))
    return band(256, 14, ice(spec))


def nx_frost_ring():
    """The minimap in frost: a pale line, clusters of ice crystals out."""
    cx = cy = 128
    r = rim(12)
    shapes = [annulus(cx, cy, r + 0.8, r + 0.8, 1.6, fade(ICE_MID, 0.8))]
    spec = []
    for a in (170, 205, 240, 300, 335, 62, 120):
        base = math.radians(a)
        for off, ln, wd in ((-0.08, 10, 3.6), (0, 15, 4.6), (0.08, 9, 3.4)):
            ang = base + off * 2.4
            x, y = polar(cx, cy, r + ln / 2 + 1, base + off)
            spec.append((x, y, ln, wd, ang))
    shapes += ice(spec)
    return render(256, 256, shapes)


def nx_unit_ice():
    """28x24 (drawn 14x12): a few small crystals for the unit frames."""
    spec = [(7, 19, 8, 3, -2.1), (19, 19, 11, 4, -1.2), (13, 16, 16, 5, -1.65)]
    return render(28, 24, ice(spec, 10))


def snowflake(x, y, r, width, col=WHITE):
    out = []
    for k in range(6):
        a = k * TAU / 6 - math.pi / 2
        out.append(stroke([(x, y), polar(x, y, r, a)], width, col))
        mid = polar(x, y, r * 0.6, a)
        for side in (1, -1):
            out.append(stroke([mid, polar(mid[0], mid[1], r * 0.32, a + side * 0.8)], width * 0.8, col))
    return out


def nx_snow_pattern():
    rng = random.Random(133)
    dots = [(rng.uniform(0, 128), rng.uniform(0, 128), rng.uniform(0.7, 1.3)) for _ in range(14)]

    def make(dx, dy):
        out = snowflake(32 + dx, 32 + dy, 14, 1.4) + snowflake(96 + dx, 96 + dy, 10, 1.2)
        out += [ellipse(x + dx, y + dy, r, r, white(0.8)) for x, y, r in dots]
        return out
    return pattern(128, 128, make, 0.13)


def nx_frost_track():
    def make(dx, dy):
        out = []
        for x in (8, 24):
            out += [stroke([(x + dx, 22 + dy), (x + dx, 10 + dy)], 1.0, WHITE), stroke([(x + dx, 15 + dy), (x + dx - 4, 11 + dy)], 0.9, WHITE),
                    stroke([(x + dx, 15 + dy), (x + dx + 4, 11 + dy)], 0.9, WHITE)]
        return out
    return pattern(32, 32, make, 0.12)


def nx_snow_orn():
    return mask(32, 32, snowflake(16, 16, 14, 2.4))


def nx_hex_ice_jewel():
    outer = hex_pts(32, 32, 29, flat=False)
    shapes = [polygon(outer, WHITE)] + [stroke([(32, 32), p], 2.0, CUT) for p in outer]
    return mask(64, 64, shapes)


def nx_ice_mark():
    return mask(64, 64, [polygon(crystal_pts(32, 32, 60, 30, math.pi / 2), WHITE)])


def nx_frost_divider():
    def make(dx, dy):
        out = [stroke([(dx - 2, 4), (dx + 34, 4)], 0.8, WHITE)]
        for x in (4, 12, 20, 28):
            out += [stroke([(x + dx, 4), (x + dx - 2.2, 1.4)], 0.7, WHITE), stroke([(x + dx, 4), (x + dx + 2.2, 1.4)], 0.7, WHITE)]
        return out
    return mask(32, 8, tiled(32, 8, make, ys=False))


def nx_ice_bar(h):
    rng = random.Random(135)
    p = per(256, h * 0.9)
    tops = [rng.uniform(0.05, 0.35) for _ in range(int(round(256 / p)))]

    def make(dx, dy):
        out = []
        n = len(tops)
        pts = []
        for k in range(-1, n + 2):
            pts.append((k * p + dx, h * tops[k % n]))
            pts.append((k * p + p / 2 + dx, h * (1 - tops[(k + 1) % n])))
        out.append(stroke(pts, max(0.9, h * 0.06), WHITE))
        for k in range(-1, n + 1):
            out.append(stroke([(k * p + dx, h * tops[k % n]), (k * p + p / 2 + dx, h * 0.5)], max(0.7, h * 0.035), white(0.8)))
        return out
    return bar(h, make, 0.68)


# ======================================================================================
# The concepts: each one's art, its glyph treatment, the alpha of its
# windows' pattern (the contrast check reads it), and its sheet colours.
# ======================================================================================

PATTERN = {
    "KarazhanLibrary": 0.13, "KarazhanOpera": 0.13, "KarazhanNether": 0.15, "SunwellSunburst": 0.1, "SunwellPhoenix": 0.12, "SunwellNaaru": 0.1,
    "BlackTempleTemple": 0.13, "BlackTempleChains": 0.12, "BlackTempleRunes": 0.13, "MoltenCoreObsidian": 0.14, "MoltenCoreBasalt": 0.13,
    "MoltenCoreFlames": 0.13, "NaxxramasNecropolis": 0.13, "NaxxramasBones": 0.1, "NaxxramasFrost": 0.13,
}

CONCEPTS = {
    "KarazhanLibrary": dict(glyphs="calligraphy", ground="#1A0D17", tint="#8C6EBD", art={
        "Header": kz_library_header, "Books": kz_books, "Inkwell": kz_inkwell, "Ring": kz_ring,
        "Raven": kz_raven, "Unit": kz_unit_candle, "Mote": mote_spark,
        "Pattern": kz_library_pattern, "Track": kz_library_track, "Edge": lambda: edge([255, 255, 255, 255, 50, 230, 50, 50]),
        "Corner": kz_quatrefoil, "Jewel": kz_arcane_star, "Mark": four_star_mask, "Divider": kz_library_divider,
        "Bar": lambda: kz_script_bar(32), "BarThin": lambda: kz_script_bar(16)}),
    "KarazhanOpera": dict(glyphs="outline", ground="#1C0B19", tint="#C9A45C", art={
        "Header": kz_opera_header, "Curtain": kz_curtain, "Masks": kz_masks, "Ring": kz_opera_ring, "Unit": kz_fleuron_unit,
        "Pattern": kz_damask, "Track": kz_opera_track, "Edge": lambda: edge([255, 255, 255, 150, 255, 255, 255, 150]),
        "Corner": kz_fleuron_mask, "Jewel": kz_mask_jewel, "Mark": kz_rosette, "Divider": kz_rope_divider,
        "Bar": lambda: kz_harlequin_bar(32), "BarThin": lambda: kz_harlequin_bar(16)}),
    "KarazhanNether": dict(glyphs="constellation", ground="#100E1F", tint="#A79FE6", art={
        "Header": kz_sky_header, "Moon": kz_moon, "Knight": kz_knight, "Rook": kz_rook, "Stars": kz_stars_top,
        "Ring": kz_astrolabe, "Unit": kz_unit_star, "Mote": mote_spark,
        "Pattern": kz_constellations, "Track": kz_chess_track, "Edge": lambda: edge([255, 60, 255, 60, 255, 60, 255, 60]),
        "Corner": lambda: four_star_mask(32, 15, 4), "Jewel": kz_crescent, "Mark": four_star_mask, "Divider": kz_star_divider,
        "Bar": lambda: kz_chess_bar(32), "BarThin": lambda: kz_chess_bar(16)}),
    "SunwellSunburst": dict(glyphs="sparkle", ground="#272017", tint="#F5DC3A", art={
        "Header": sw_sun_header, "Sun": sw_sun, "Filigree": lambda: filigree(GOLD, GOLD_DARK), "Ring": sw_ring,
        "Unit": sw_unit_sun, "Mote": mote_glint,
        "Pattern": sw_sun_pattern, "Track": sw_ray_track, "Edge": lambda: edge([255, 255, 255, 80, 255, 255, 255, 80]),
        "Corner": sw_sunburst_orn, "Jewel": sw_sun_jewel, "Mark": four_star_mask, "Divider": sw_bead_divider,
        "Bar": lambda: sw_ray_bar(32), "BarThin": lambda: sw_ray_bar(16)}),
    "SunwellPhoenix": dict(glyphs="feather", ground="#24130E", tint="#E9C24F", art={
        "Header": sw_phoenix_header, "Fan": sw_feather_fan, "Feather": sw_side_feather, "Ring": sw_phoenix_ring,
        "Unit": sw_unit_feather, "Mote": mote_ember,
        "Pattern": sw_plumage, "Track": sw_chevron_track,
        "Corner": lambda: flame_mask(32, 27, 14), "Jewel": lambda: flame_mask(64, 58, 30, True), "Mark": lambda: flame_mask(64, 58, 32),
        "Divider": sw_barb_divider, "Bar": lambda: sw_feather_bar(32), "BarThin": lambda: sw_feather_bar(16)}),
    "SunwellNaaru": dict(glyphs="crystal", ground="#121A24", tint="#E6CB6A", art={
        "Header": sw_glass_header, "Shards": sw_shards, "Ring": sw_glass_ring, "Unit": sw_unit_shards, "Mote": mote_glint,
        "Pattern": lambda: sw_lattice(128, 32, PATTERN["SunwellNaaru"]), "Track": lambda: sw_lattice(32, 16, 0.1),
        "Edge": lambda: edge([255, 255, 255, 255, 255, 255, 90, 90]),
        "Corner": sw_crystal_orn, "Jewel": sw_gem_jewel, "Mark": sw_rhombus_mark, "Divider": sw_lattice_divider,
        "Bar": lambda: sw_facet_bar(32), "BarThin": lambda: sw_facet_bar(16)}),
    "BlackTempleTemple": dict(glyphs="cracked", ground="#140F1B", tint="#7DAF61", art={
        "Header": bt_temple_header, "Slab": bt_broken_slab, "Lintel": bt_lintel, "Ring": bt_temple_ring, "Unit": bt_unit_lens,
        "Mote": mote_spore,
        "Pattern": bt_temple_pattern, "Track": bt_lens_track, "Edge": lambda: edge([255, 255, 255, 255, 255, 255, 255, 70]),
        "Corner": bt_lens_orn, "Jewel": bt_lens_jewel, "Mark": bt_vesica_mark, "Divider": bt_lens_divider,
        "Bar": lambda: crack_bar(32, 79), "BarThin": lambda: crack_bar(16, 79)}),
    "BlackTempleChains": dict(glyphs="riveted", ground="#121016", tint="#86B86A", art={
        "Header": bt_plates_header, "Chain": bt_chain_top, "Hanging": bt_hanging_chain, "Ring": bt_chain_ring,
        "Unit": bt_unit_ring, "Mote": mote_ember,
        "Pattern": bt_rivet_pattern, "Track": bt_rivet_track, "Edge": lambda: edge([255, 255, 255, 255, 255, 255, 70, 70]),
        "Corner": bt_bolt_orn, "Jewel": bt_shackle_jewel, "Mark": bt_rivet_mark, "Divider": bt_chain_divider,
        "Bar": lambda: bt_chain_bar(32), "BarThin": lambda: bt_chain_bar(16)}),
    "BlackTempleRunes": dict(glyphs="runic", ground="#0F0B13", tint="#79B85A", art={
        "Header": bt_rune_header, "Flame": bt_fel_flame, "Ring": bt_rune_ring, "Unit": bt_unit_rune, "Mote": mote_ember,
        "Pattern": bt_tattoo_pattern, "Track": bt_rune_track,
        "Corner": bt_rune_orn, "Jewel": bt_eye_jewel, "Mark": bt_rune_mark, "Divider": bt_rune_divider,
        "Bar": lambda: bt_tattoo_bar(32), "BarThin": lambda: bt_tattoo_bar(16)}),
    "MoltenCoreObsidian": dict(glyphs="jagged", ground="#190D0A", tint="#BE5A0A", art={
        "Header": mc_obsidian_header, "Rock": mc_rock_top, "Chunk": mc_rock_chunk, "Ring": mc_obsidian_ring,
        "Unit": mc_unit_shard, "Mote": mote_ember,
        "Pattern": lambda: crack_pattern(99, 4, PATTERN["MoltenCoreObsidian"]), "Track": mc_crack_track,
        "Corner": mc_shard_orn, "Jewel": mc_lava_jewel, "Mark": mc_ember_mark, "Divider": mc_crack_divider,
        "Bar": lambda: crack_bar(32, 91), "BarThin": lambda: crack_bar(16, 91)}),
    "MoltenCoreBasalt": dict(glyphs="faceted", ground="#17151A", tint="#C46A1A", art={
        "Header": mc_basalt_header, "Columns": mc_columns, "Tablet": mc_rune_tablet, "Ring": mc_basalt_ring,
        "Unit": mc_unit_stub, "Mote": mote_ember,
        "Pattern": lambda: hex_pattern(128, 8, 1.1, PATTERN["MoltenCoreBasalt"]), "Track": lambda: hex_pattern(32, 4, 1.0, 0.12),
        "Corner": mc_hex_orn, "Jewel": mc_hex_jewel, "Mark": mc_hex_mark, "Divider": mc_hex_divider,
        "Bar": lambda: mc_hex_bar(32), "BarThin": lambda: mc_hex_bar(16)}),
    "MoltenCoreFlames": dict(glyphs="flame", ground="#1B0907", tint="#C8501A", art={
        "Header": mc_flame_header, "FlameTop": mc_flame_top, "Cluster": mc_flame_cluster, "Ring": mc_fire_ring,
        "Unit": mc_unit_flame, "Mote": mote_ember,
        "Pattern": mc_flame_pattern, "Track": mc_flame_track,
        "Corner": lambda: flame_mask(32, 27, 13), "Jewel": lambda: flame_mask(64, 58, 30, True), "Mark": lambda: flame_mask(64, 58, 32),
        "Divider": mc_flame_divider, "Bar": lambda: mc_flame_bar(32), "BarThin": lambda: mc_flame_bar(16)}),
    "NaxxramasNecropolis": dict(glyphs="spiked", ground="#0A141B", tint="#52B1A9", art={
        "Header": nx_necropolis_header, "Spikes": nx_spikes, "Buttress": nx_buttress, "Ring": nx_spiked_ring,
        "Unit": nx_unit_spike, "Mote": mote_spore,
        "Pattern": nx_sigil_pattern, "Track": nx_notch_track, "Edge": lambda: edge([255, 255, 255, 255, 255, 255, 255, 60]),
        "Corner": nx_claw_orn, "Jewel": nx_sigil_jewel, "Mark": nx_spike_mark, "Divider": nx_spike_divider,
        "Bar": lambda: nx_sigil_bar(32), "BarThin": lambda: nx_sigil_bar(16)}),
    "NaxxramasBones": dict(glyphs="bone", ground="#0E1316", tint="#CFC6A6", art={
        "Header": nx_rib_header, "Web": lambda: nx_web_corner(64, 58), "Spider": nx_spider, "Ring": nx_bone_ring,
        "Unit": nx_unit_web,
        "Pattern": nx_web_pattern, "Track": nx_vertebra_track, "Edge": lambda: edge([255, 255, 255, 255, 255, 255, 50, 50]),
        "Corner": nx_web_orn, "Jewel": nx_skull_jewel, "Mark": nx_skull_mark, "Divider": nx_vertebra_divider,
        "Bar": lambda: nx_vertebra_bar(32), "BarThin": lambda: nx_vertebra_bar(16)}),
    "NaxxramasFrost": dict(glyphs="frost", ground="#0A1520", tint="#8EC9D2", art={
        "Header": nx_frost_header, "Crystals": nx_crystals, "Rime": nx_frost_top, "Ring": nx_frost_ring,
        "Unit": nx_unit_ice, "Mote": mote_snow,
        "Pattern": nx_snow_pattern, "Track": nx_frost_track,
        "Corner": nx_snow_orn, "Jewel": nx_hex_ice_jewel, "Mark": nx_ice_mark, "Divider": nx_frost_divider,
        "Bar": lambda: nx_ice_bar(32), "BarThin": lambda: nx_ice_bar(16)}),
}

# masks: white art tinted in game (shown tinted on the sheet)
MASKS = {"Mote", "Pattern", "Track", "Edge", "Corner", "Jewel", "Mark", "Divider", "Bar", "BarThin"}


def write(concept, name, rows):
    out = os.path.join(OUT, concept)
    os.makedirs(out, exist_ok=True)
    write_rgba_tga(os.path.join(out, name + ".tga"), rows)


def write_glyphs(concept):
    style = GLYPH_STYLES[CONCEPTS[concept]["glyphs"]]
    out = os.path.join(OUT, concept, "Glyphs")
    os.makedirs(out, exist_ok=True)
    for name in GLYPH_NAMES:
        write_rgba_tga(os.path.join(out, name + ".tga"), as_mask(coverage(64, 64, style(name))))
    print("wrote", len(GLYPH_NAMES), CONCEPTS[concept]["glyphs"], "glyphs for", concept)


def sheet(concept, path, glyphs=("gear", "bag", "search", "close", "book", "map", "chat", "mail", "person", "lock", "scroll", "trophy")):
    """The concept's art on its ground (masks in its gilt), each at 2x up to
    256 px, then a row of its glyphs."""
    spec = CONCEPTS[concept]
    ground = hexc(spec["ground"])[:3]
    tint = hexc(spec["tint"])[:3]
    items = []
    for name, make in spec["art"].items():
        rows = make()
        if name in MASKS:
            rows = [[(round(tint[0] * r / 255), round(tint[1] * g / 255), round(tint[2] * b / 255), a) for r, g, b, a in row] for row in rows]
        items.append(rows)
    style = GLYPH_STYLES[spec["glyphs"]]
    for name in glyphs:
        rows = as_mask(coverage(64, 64, style(name)))
        items.append([[(round(tint[0] * r / 255), round(tint[1] * g / 255), round(tint[2] * b / 255), a) for r, g, b, a in row] for row in rows])
    pad, width = 12, 1400
    placed, x, y, line_h = [], pad, pad, 0
    for rows in items:
        h, w = len(rows), len(rows[0])
        zoom = 2 if max(w, h) <= 128 else 1
        if x + w * zoom > width - pad:
            x, y, line_h = pad, y + line_h + pad, 0
        placed.append((x, y, zoom, rows))
        x += w * zoom + pad
        line_h = max(line_h, h * zoom)
    height = y + line_h + pad
    canvas = [[ground + (255,)] * width for _ in range(height)]
    for ox, oy, zoom, rows in placed:
        for yy, row in enumerate(rows):
            for xx, (r, g, b, a) in enumerate(row):
                t = a / 255
                col = (round(r * t + ground[0] * (1 - t)), round(g * t + ground[1] * (1 - t)), round(b * t + ground[2] * (1 - t)), 255)
                for zy in range(zoom):
                    canvas_row = canvas[oy + yy * zoom + zy]
                    for zx in range(zoom):
                        canvas_row[ox + xx * zoom + zx] = col
    write_png(path, canvas)
    print("wrote", path)


# --- the colours' ratios (the contrast tests' rules) -------------------------------------------------------

DESIGN = {"surface": "#131116", "ink": "#F1EADB", "unit-fill": "#6E604B", "unit-fill-low": "#B53D1E", "track": "#24201A"}


def _lum(c3):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c3[0]) + 0.7152 * lin(c3[1]) + 0.0722 * lin(c3[2])


def _ratio(a, b):
    la, lb = _lum(a), _lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def _over(fg, bg):
    a = fg[3] / 255 if len(fg) > 3 else 1
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3))


def check():
    path = os.path.join(ROOT, "src", "Core", "ThemesRaids.wowlua")
    text = open(path, encoding="utf-8").read()
    bad = 0
    for m in re.finditer(r'local dir = ROOT \.\. "(\w+)\\\\".*?colors = colors\(\{(.*?)\}\)', text, re.S):
        key, body = m.group(1), m.group(2)
        cols = dict(DESIGN)
        cols.update(dict(re.findall(r'\["([a-z-]+)"\] = "(#[0-9A-Fa-f]+)"', body)))
        col = {k: hexc(v, int(v[7:9], 16) if len(v) > 7 else 255) for k, v in cols.items()}
        black = (0, 0, 0)

        def rgb(name):
            return col[name][:3]
        rules = [("ink", "surface", 7), ("ink", "surface-raised", 7), ("ink", "unit-fill", 4.8), ("ink", "unit-fill-low", 4.8),
                 ("ink-muted", "surface", 4.5), ("gilt-text", "surface", 7), ("unit-fill", "surface-sunk", 3.05)]
        out = []
        for fg, bg, least in rules:
            r = _ratio(rgb(fg), rgb(bg))
            if r < least:
                out.append(f"{fg} on {bg} {r:.2f} < {least}")
        faint, muted = _ratio(rgb("ink-faint"), rgb("surface")), _ratio(rgb("ink-muted"), rgb("surface"))
        if not (faint >= 3 and faint < muted):
            out.append(f"ink-faint {faint:.2f} (muted {muted:.2f})")
        for edge_name, least in (("gilt-line", 2.15), ("gilt-hairline", 1.78)):
            r = _ratio(_over(col[edge_name], rgb("surface")), rgb("surface"))
            if r < least:
                out.append(f"{edge_name} {r:.2f} < {least}")
        a = PATTERN[key]
        for ground in ("surface", "surface-glass"):
            g = _over(col[ground], black)
            brightest = _over(rgb("gilt") + (round(255 * a),), g)
            for fg, least in (("ink", 7), ("gilt-text", 7), ("ink-muted", 4.5), ("ink-faint", 3)):
                r = _ratio(rgb(fg), brightest)
                if r < least:
                    out.append(f"{fg} over the pattern on {ground} {r:.2f} < {least}")
        if col["surface-glass"][3] / 255 < 0.96:
            out.append("glass under 0.96")
        fill = _ratio(rgb("ink"), rgb("unit-fill"))
        print(f"{key:13s} ink/fill {fill:.2f}  fill/sunk {_ratio(rgb('unit-fill'), rgb('surface-sunk')):.2f}  ink/surface "
              f"{_ratio(rgb('ink'), rgb('surface')):.1f}  {'OK' if not out else '; '.join(out)}")
        bad += len(out)
    return bad


def main():
    args = sys.argv[1:]
    if args[:1] == ["--check"]:
        sys.exit(1 if check() else 0)
    if args[:1] == ["--glyphs"]:
        for concept in args[1:] or list(CONCEPTS):
            write_glyphs(concept)
        return
    if args[:1] == ["--sheet"]:
        sheet(args[1], args[2])
        return
    names = [a for a in args if not a.startswith("-")]
    for concept, spec in CONCEPTS.items():
        if names and concept not in names:
            continue
        for name, make in spec["art"].items():
            write(concept, name, make())
        print("wrote", len(spec["art"]), "textures for", concept)


if __name__ == "__main__":
    main()
