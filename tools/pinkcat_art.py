#!/usr/bin/env python3
"""Generate the Pink Cat theme's art into Media/Textures/Themes/PinkCat.
Standard library only; the drawing helpers are make_textures.py's (the dress:
tools/raid_art.py's renderer).

    python3 -I tools/pinkcat_art.py              every file
    python3 -I tools/pinkcat_art.py bag gear     only these
    python3 -I tools/pinkcat_art.py --preview out.png
                                                 a sheet of every cat glyph
                                                 beside SuuUI's, at 64, 24
                                                 and 16 px, on the theme's
                                                 surface in its colours

Glyphs/<name>.tga (64x64, white, tinted in game): cat versions of SuuUI's
most seen line glyphs, drawn as SuuUI's own are (a 24-unit box, stroke 1.9,
round caps and joins: make_textures.stroke_alpha), so they sit where SuuUI's
did. Each keeps what it stands for (a bag, a magnifier, a gear) and gains
cat ears, a cat's face, whiskers, a slit pupil, a yarn ball or a sprig of
catnip.

PawBar.tga (256x32, white): the health bars' fill, repeated along the bar
at its height (seamless left to right) and tinted by its colour; paw prints at 76% (BAR_SHADE), darker than the
fill so names on it keep their contrast, still one fill. CastBar.tga
(256x16): the cast bars' row of paws. PlateBar.tga (256x20): the
nameplates' bars (about 140x10), simpler three-toed paws that stay paws.

SurfacePattern.tga (128x128, white, alpha up to PATTERN_ALPHA): paws and
hearts tiled over every window's ground, in gilt, far apart (asked
2026-11-13: fainter, repeating less often). TrackPattern.tga (32x32):
a tiny paw a tile behind the bars. Stitch.tga (8x8): the panels' edge as
stitches. CornerPaw.tga (32x32): the corners' paw print. Divider.tga
(32x8): a tiny paw and a dot, tiled along the line under a panel's head.

PawTapped.tga (32x32, white): a tagged mob's stripes as tiny paw prints,
tiled at their own size over the fill (in unit-fill-tapped-stripe).

Heart.tga (64x64, white): the checkbox's tick as a little heart (tinted
on-signal in game), the jewels and the small marks (toggles, sliders).

BeanBar.tga (256x16, white): the thin bars (power lines, XP and the other
plain bars, aura drains), a row of toe beans at 70%, repeated along the bar
at its height like the paw bars.

Hearts.tga (16x16, white): small hearts, tiled: the absorb shield and a
swing's delay, where SuuUI draws its hatch.

The dress (asked 2026-11-14: the corners that wrap round the frames, as
the Icecrown Citadel and Ulduar themes' do, white and sparkles), in its own
colours: Wrap.tga and WrapLow.tga (96x96, drawn 48x48 on a window's and
the chat's top and bottom corners): pink satin ribbon round the corner
with a white shine and white stitches, at most 4 px past the edges; a
white heart edged in pink on the bottom ones. Bow.tga (64x48, drawn 16x12,
swaying): the white bow tied over the top corners. Pearls.tga (64x10): a
string of pearls and hearts along a window's top. Header.tga (128x40):
plum wallpaper with faint white sparkles behind a window's title (kept
dark: check_header). Ring.tga (256, drawn RING_PAST px past the minimap's
disc): a ribbon of pearls with a cat's two ears. Ears.tga (56x24, drawn
28x12): a cat's two small ears on the big unit frames. Sparkle.tga
(32x32): the motes, a white sparkle with a little pink one, in a pink
glow. `--dress out.png` draws them side by side.

RoleTank/RoleHealer/RoleDamage.tga (32x32, white, filled): a shield with
cat's ears, a heart, three claw marks. Claws.tga (64x64, line): the combat
sign. CircleDots.tga (104x104): a ring of round dots where SuuUI's ring is
dashed (waypoints, unknown flight points). Glyphs/lock.tga and reset.tga
also stand for the cast lock and the settings' lock and reset.
"""

import functools
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_textures as mt  # noqa: E402
import raid_art as ra  # noqa: E402
from stv_art import write_rgba_tga  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Media", "Textures", "Themes", "PinkCat")
GLYPH_DIR = os.path.join(ROOT, "Media", "Textures", "Glyphs")


# --- path helpers (24-unit box, y down) -------------------------------------

def f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, deg, sq=1.0):
    """A point on a circle (an ellipse `sq` times as tall); 0 degrees is
    right, 90 is up."""
    a = math.radians(deg)
    return cx + r * math.cos(a), cy - r * sq * math.sin(a)


def poly(*pts, close=False):
    d = "M" + " L".join(f(x) + " " + f(y) for x, y in pts)
    return d + ("z" if close else "")


def circle(cx, cy, r):
    return "M%s %sa%s %s 0 1 0 0 %s %s %s 0 0 0 0-%s" % (f(cx), f(cy - r), f(r), f(r), f(2 * r), f(r), f(r), f(2 * r))


def dot(x, y):
    return "M%s %sh.01" % (f(x), f(y))


def arc_pts(cx, cy, r, a1, a2, step=6, sq=1.0):
    """Points along a circle from angle a1 to a2 (degrees, either way)."""
    n = max(1, int(abs(a2 - a1) / step))
    return [pt(cx, cy, r, a1 + (a2 - a1) * k / n, sq) for k in range(n + 1)]


# A cat's ears on a head of radius r: each stands on the outline from
# `outer` to `inner` degrees (the left one; the right mirrors it), its tip
# at `tip` = (degrees, distance in r) from the head's centre.
EARS = dict(outer=160, inner=112, tip=(122, 1.5))


def ear_pts(cx, cy, r, sq, outer, inner, tip, side):
    """One ear's three points, from the outer foot (side -1: the left)."""
    ta, tr = tip
    if side > 0:
        outer, inner, ta = 180 - outer, 180 - inner, 180 - ta
        return [pt(cx, cy, r, inner, sq), pt(cx, cy, r * tr, ta), pt(cx, cy, r, outer, sq)]
    return [pt(cx, cy, r, outer, sq), pt(cx, cy, r * tr, ta), pt(cx, cy, r, inner, sq)]


def head(cx, cy, r, sq=0.88, **ears):
    """A cat's head: a round face (`sq` times as tall as wide) whose top
    grows two ears, as one outline (no line under the ears)."""
    e = dict(EARS, **ears)
    pts = ear_pts(cx, cy, r, sq, e["outer"], e["inner"], e["tip"], -1)
    pts += arc_pts(cx, cy, r, e["inner"], 180 - e["inner"], sq=sq)[1:-1]
    pts += ear_pts(cx, cy, r, sq, e["outer"], e["inner"], e["tip"], 1)
    pts += arc_pts(cx, cy, r, 180 - e["outer"], e["outer"] - 360, sq=sq)[1:]
    return poly(*pts, close=True)


def dome(cx, cy, r, **ears):
    """The top half of a cat's head (a half circle whose top grows two
    ears), as points from its left end to its right end."""
    e = dict(EARS, **ears)
    pts = arc_pts(cx, cy, r, 180, e["outer"])[:-1]
    pts += ear_pts(cx, cy, r, 1.0, e["outer"], e["inner"], e["tip"], -1)
    pts += arc_pts(cx, cy, r, e["inner"], 180 - e["inner"])[1:-1]
    pts += ear_pts(cx, cy, r, 1.0, e["outer"], e["inner"], e["tip"], 1)
    pts += arc_pts(cx, cy, r, 180 - e["outer"], 0)[1:]
    return pts


def clipped_arc(cx, cy, r, ball, steps=90):
    """The parts of a circle (cx, cy, r) inside a disc ball = (bx, by, br)
    (a little inside its edge), as polyline paths."""
    bx, by, br = ball
    out, cur = [], []
    for i in range(steps + 1):
        a = 2 * math.pi * i / steps
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        if math.hypot(x - bx, y - by) <= br - 1.1:
            cur.append((x, y))
        elif cur:
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return "".join(poly(*c) for c in out if len(c) > 1)


def heart_points(cx, cy, w, n=120):
    """The classic heart curve, `w` units wide, centred on (cx, cy)."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x, y))
    # the curve spans x -16..16, y -17..12 (up): fit and centre it
    s = w / 32
    return [(cx + x * s, cy - (y + 2.5) * s) for x, y in pts]


def bezier(p0, p1, p2, p3, n=10):
    """A cubic curve's points after p0."""
    out = []
    for k in range(1, n + 1):
        t = k / n
        m = 1 - t
        out.append((m ** 3 * p0[0] + 3 * m * m * t * p1[0] + 3 * m * t * t * p2[0] + t ** 3 * p3[0],
                    m ** 3 * p0[1] + 3 * m * m * t * p1[1] + 3 * m * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def corner_ears(x1, x2, y, w=4, h=4.4, drop=1.2):
    """A top edge from x1 to x2 at y whose two corners rise into ears: the
    sides come up `drop` below the edge, go up to a tip and down to the
    edge `w` in from the corner."""
    return [(x1, y + drop), (x1 + 0.25, y - h + drop), (x1 + w, y), (x2 - w, y), (x2 - 0.25, y - h + drop), (x2, y + drop)]


def gear_with_ears():
    """A gear (teeth and a hole) whose top is a cat's head: two ears where
    the upper teeth were."""
    cx, cy, R, Rt = 12, 13.2, 6.6, 9.0
    ears = {120: (138, 104, (125, 1.62)), 60: (76, 42, (55, 1.62))}
    teeth = [0, -45, -90, -135, -180]
    pts = []
    # from the left ear clockwise: ear, ear, then the teeth round the bottom
    lo, li, (lt, lr) = ears[120]
    pts += [pt(cx, cy, R, lo), pt(cx, cy, R * lr, lt), pt(cx, cy, R, li)]
    pts += arc_pts(cx, cy, R, li, 76)[1:]
    ro, ri, (rt, rr) = ears[60]
    pts += [pt(cx, cy, R * rr, rt), pt(cx, cy, R, ri)]
    last = ri
    for a in teeth:
        pts += arc_pts(cx, cy, R, last, a + 12)[1:]
        pts += [pt(cx, cy, Rt, a + 8), pt(cx, cy, Rt, a - 8), pt(cx, cy, R, a - 12)]
        last = a - 12
    pts += arc_pts(cx, cy, R, last, lo - 360)[1:]
    return poly(*pts, close=True) + circle(cx, cy, 2.5)


def yarn():
    """A ball of yarn with two knitting needles: professions."""
    bx, by, br = 10, 14, 6.6
    d = circle(bx, by, br)
    d += clipped_arc(bx + 9, by - 8, 9.5, (bx, by, br))
    d += clipped_arc(bx + 9, by - 8, 13, (bx, by, br))
    d += clipped_arc(bx - 8, by + 1, 9.5, (bx, by, br))
    d += poly((13.4, 8.4), (20.2, 2.6)) + dot(21, 1.9)
    d += poly((15.3, 10.6), (21.4, 6.8)) + dot(22.2, 6.3)
    return d


def catnip():
    """A sprig of catnip: talents."""
    d = "M12 21.5V7.5"
    d += "M12 16.5Q7.5 17.5 5.5 13Q10 12 12 16.5"
    d += "M12 16.5Q16.5 17.5 18.5 13Q14 12 12 16.5"
    d += "M12 11.5Q8.5 12 7 8.5Q10.5 7.8 12 11.5"
    d += "M12 11.5Q15.5 12 17 8.5Q13.5 7.8 12 11.5"
    d += "M12 7.5Q10.2 5.2 12 2.5Q13.8 5.2 12 7.5"
    return d


def cat_face():
    """A cat's face, whiskers out: collections (mounts and pets)."""
    cx, cy, r = 12, 13.6, 7
    d = head(cx, cy, r, sq=0.9)
    d += dot(9.3, 12.9) + dot(14.7, 12.9)
    d += "M10.8 15.7L12 16.7L13.2 15.7"
    d += "M1.4 13.4L4.6 14.3M1.7 17.6L4.8 16.5M22.6 13.4L19.4 14.3M22.3 17.6L19.2 16.5"
    return d


def paw_mark(cx, cy, s=1.0):
    """A small paw print in dots: a pad and three toes."""
    d = "M%s %sh%s" % (f(cx - 0.7 * s), f(cy + 1.3 * s), f(1.4 * s))
    for dx, dy in ((-2.3, -1.0), (0, -2.4), (2.3, -1.0)):
        d += dot(cx + dx * s, cy + dy * s)
    return d


def pin():
    cx, cy, r = 12, 11, 6
    pts = [(12, 22)] + bezier((12, 22), (8.5, 18.5), (6, 14.5), (6, 11), 8)
    pts += dome(cx, cy, r)[1:]
    pts += bezier((18, 11), (18, 14.5), (15.5, 18.5), (12, 22), 8)
    return poly(*pts) + circle(cx, cy, 2)


def bell():
    pts = [(6, 17)] + dome(12, 12, 6) + [(18, 17)]
    return poly(*pts) + "M6 17l-2 2h16l-2-2M10 21a2 2 0 0 0 4 0"


def peeking(x1, x2, y, cx, r):
    """A line from x1 to x2 at y with a cat's head peeking over it at cx."""
    return poly((x1, y), *dome(cx, y, r, inner=110, tip=(121, 1.7)), (x2, y)) + dot(cx - r * 0.42, y - r * 0.4) + \
        dot(cx + r * 0.42, y - r * 0.4)


# The cat glyphs, by the SuuUI glyph each stands in for.
CAT = {
    # the micro menu
    "person": head(12, 9.2, 4.2) + "M4.5 21.5c1-4 4-6 7.5-6s6.5 2 7.5 6",
    "hammer": yarn(),
    "book": "M4 19V7.2L4.3 2.8L7.8 6H10a2 2 0 0 1 2 2v13a2 2 0 0 0-2-2H4z" +
    "M20 19V7.2L19.7 2.8L16.2 6H14a2 2 0 0 0-2 2v13a2 2 0 0 1 2-2h6z",
    "tree": catnip(),
    # (simplified 2026-11-12: busy at 16 px) SuuUI's cup, its rim's corners
    # rising into two small ears
    "trophy": poly(*corner_ears(8, 16, 5, w=2.8, h=4, drop=0)) + "M16 5V9a4 4 0 0 1-8 0V5" +
    "M8 6.5H5a3 3 0 0 0 3 4M16 6.5h3a3 3 0 0 1-3 4M12 13v4M8 20h8",
    "scroll": poly((7, 15), *corner_ears(7, 18, 6, w=3.6, h=4.2, drop=1.2), (18, 18)) +
    "M18 18a3 3 0 0 1-3 3H6a3 3 0 0 1 0-6h1M10 10.5h5M10 13.5h5",
    "people": head(8.6, 10.6, 3.6) + "M2.5 21.5c.7-3.5 3-5 6.1-5s5.4 1.5 6.1 5" +
    head(16.8, 8.4, 2.9) + "M17.6 14c2 .4 3.6 2.6 4 6",
    "search": head(10.5, 11.5, 6.2) + "M15 16L20.5 21.5",
    "mount": cat_face(),
    "coin": head(12, 13.4, 8, tip=(122, 1.42)) + paw_mark(12, 14, 1.3),
    "map": "M3 8.5L3.3 3.6L6.6 5.9L9 5L15 7L17.5 6.1L20.7 3.6L21 7V19L15 21L9 19L3 21ZM9 5V19M15 7V21",
    "bag": "M5.5 8.5h13l-1.2 12.5H6.7z" + "M9 8.5V6.5a3 3 0 0 1 6 0v2" + paw_mark(12, 15.6, 1.25),
    "menu": peeking(4, 20, 11, 12, 5) + "M4 16h16M4 21h16",
    # windows, settings, lists
    "close": "M6.5 6.5Q12.5 11 17.5 17.5M17.5 6.5Q11.5 11 6.5 17.5",
    "gear": gear_with_ears(),
    "filter": poly(*corner_ears(4, 20, 7, w=4, h=4.4, drop=1.2), (13.5, 14), (13.5, 19.5), (10.5, 21), (10.5, 14),
                   close=True),
    "sort": "M7 20V7.5C7 5.5 5.5 4 3.8 4.6M4 17l3 3 3-3" + "M17 4v12.5c0 2 1.5 3.5 3.2 2.9M14 7l3-3 3 3",
    "chat": poly((4, 21.5), *corner_ears(4, 20, 8, w=4.2, h=4.6, drop=1.2), (20, 18), (9, 18), close=True) +
    dot(9.5, 12.8) + dot(14.5, 12.8),
    "mail": poly(*corner_ears(4, 20, 8.5, w=4.2, h=4.6, drop=1.2), (20, 19.5), (4, 19.5), close=True) +
    "M4 10l8 5.5 8-5.5",
    "check": poly(*heart_points(12, 12.5, 17), close=True),
    # the map and the minimap
    "pin": pin(),
    "inn": poly((3, 12), (7, 8.6), (7.9, 4.2), (10.8, 6.6), (13.2, 6.6), (16.1, 4.2), (17, 8.6), (21, 12)) +
    "M5.5 10.4V21h13V10.4M10 21v-5h4v5",
    # notifications, bags, everywhere
    "bell": bell(),
    # (simplified 2026-11-12) SuuUI's bin, two ears on its lid for the handle
    "trash": "M5 7h14M7 7l1 13h8l1-13" + poly((7, 7), (7.4, 2.8), (10.4, 7)) + poly((13.6, 7), (16.6, 2.8), (17, 7)),
    "eye": "M2.5 12c3-5.5 16-5.5 19 0-3 5.5-16 5.5-19 0z" + "M12 7.8c-1.7 2.4-1.7 6 0 8.4 1.7-2.4 1.7-6 0-8.4z",
    # locks, resets, roles and the rest (also the cast lock, the settings'
    # lock and reset, and the welcome's Tank)
    "lock": poly((5, 21), *corner_ears(5, 19, 11, w=3.4, h=3.8, drop=1.2), (19, 21), close=True) +
    "M9.2 11V7.4a2.8 2.8 0 0 1 5.6 0V11" + dot(9.6, 15.2) + dot(14.4, 15.2) + "M11 17.2L12 18.1L13 17.2",
    "reset": "M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4" + dot(9.4, 11.4) + dot(14.6, 11.4) + "M10.9 14.2L12 15.2L13.1 14.2",
    "shield": None,  # (filled in below: the shield's outline is shared with the tank's icon)
    "userPlus": head(9.6, 9, 3.8) + "M2.5 21.5c0-4 3-6 7.1-6s7.1 2 7.1 6M19.5 8v6M16.5 11h6",
    "spirit": poly((6, 21.5), *dome(12, 11, 6), (18, 21.5), (16, 20), (14, 21.5), (12, 20), (10, 21.5), (8, 20),
                   close=True) + dot(10, 11.5) + dot(14, 11.5),
}


def shield_points():
    """A shield whose top corners rise into cat's ears (24 units)."""
    pts = [(5, 8), (5.3, 2.6), (9, 5.1), (12, 4.3), (15, 5.1), (18.7, 2.6), (19, 8)]
    pts += bezier((19, 8), (19, 15), (15.5, 19.5), (12, 21.2), 10)
    pts += bezier((12, 21.2), (8.5, 19.5), (5, 15), (5, 8), 10)[:-1]
    return pts


CAT["shield"] = poly(*shield_points(), close=True)

# three claw marks: the combat sign and the damage role
CLAWS = "M14.5 3Q11.5 10.5 4.5 15.5M18.5 5Q15.5 12.5 8.5 17.5M21.5 9Q18.5 15.5 12.5 20.5"


# --- textures ---------------------------------------------------------------

def supersample(size_w, size_h, inside, ss=4):
    """Coverage (0..1) per pixel of `inside(x, y)` (pixel units)."""
    out = {}
    for py in range(size_h):
        for px in range(size_w):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    if inside(px + (sx + 0.5) / ss, py + (sy + 0.5) / ss):
                        hits += 1
            out[(px, py)] = hits / (ss * ss)
    return out


def in_ellipse(x, y, cx, cy, rx, ry, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    dx, dy = x - cx, y - cy
    u, v = dx * c + dy * s, -dx * s + dy * c
    return (u / rx) ** 2 + (v / ry) ** 2 <= 1


def paw_shapes(cx, cy, size, rot):
    """A paw print `size` px tall as ellipses (pad and four toes), turned."""
    s = size / 12.0
    parts = [(0, 2.2, 3.5, 2.9)]  # pad
    parts += [(-3.9, -1.6, 1.25, 1.6), (-1.35, -3.9, 1.3, 1.7), (1.35, -3.9, 1.3, 1.7), (3.9, -1.6, 1.25, 1.6)]
    c, sn = math.cos(rot), math.sin(rot)
    out = []
    for dx, dy, rx, ry in parts:
        x, y = dx * s, dy * s
        out.append((cx + x * c - y * sn, cy + x * sn + y * c, rx * s, ry * s, rot))
    return out


def paw_field(width, height, paws, wrap=True):
    shapes = []
    for cx, cy, size, rot in paws:
        for ox in ((-width, 0, width) if wrap else (0,)):
            for oy in ((-height, 0, height) if wrap else (0,)):
                shapes += [(x + ox, y + oy, rx, ry, r) for x, y, rx, ry, r in paw_shapes(cx, cy, size, rot)]

    def inside(x, y):
        for sx, sy, rx, ry, r in shapes:
            if abs(x - sx) <= max(rx, ry) + 0.1 and abs(y - sy) <= max(rx, ry) + 0.1 and in_ellipse(x, y, sx, sy, rx, ry, r):
                return True
        return False
    return supersample(width, height, inside)


def paw_tapped():
    """32x32: four small paws, tiled over a tagged mob's fill."""
    paws = [(8, 8, 10, math.radians(-15)), (24, 24, 10, math.radians(-15)),
            (24, 8, 10, math.radians(15)), (8, 24, 10, math.radians(15))]
    cov = paw_field(32, 32, paws)
    return 32, 32, lambda x, y: (255, 255, 255, round(255 * cov[(x, y)]))


def heart_texture():
    """64x64: a filled heart, the checkbox's tick."""
    pts = [(x / 24 * 64, y / 24 * 64) for x, y in heart_points(12, 12.3, 17.5)]
    cov = supersample(64, 64, lambda x, y: mt.inside_polygon(x, y, pts))
    return 64, 64, lambda x, y: (255, 255, 255, round(255 * cov[(x, y)]))


def hearts():
    """16x16: two small hearts, tiled (the absorb shield, a swing's delay)."""
    shapes = []
    for cx, cy in ((4, 4.4), (12, 12.4), (12, -3.6), (-4, 12.4), (20, 4.4), (4, 20.4)):
        shapes.append(heart_points(cx, cy, 6.6, 60))

    def inside(x, y):
        return any(mt.inside_polygon(x, y, p) for p in shapes)
    cov = supersample(16, 16, inside)
    return 16, 16, lambda x, y: (255, 255, 255, round(255 * cov[(x, y)]))


def role(kind):
    """32x32 role icons, filled: a cat-eared shield (tank), a heart (healer),
    claw marks (damage)."""
    def make():
        if kind == "damage":
            fn = mt.stroke_alpha(mt.path_polylines(CLAWS), 3.2, 24.0, 32)
            return 32, 32, fn
        pts = shield_points() if kind == "tank" else heart_points(12, 12.6, 20)
        pts = [(x / 24 * 32, y / 24 * 32) for x, y in pts]
        cov = supersample(32, 32, lambda x, y: mt.inside_polygon(x, y, pts))
        return 32, 32, lambda x, y: (255, 255, 255, round(255 * cov[(x, y)]))
    return make


def claws():
    """64x64: the combat sign, three claw marks in line."""
    return 64, 64, mt.stroke_alpha(mt.path_polylines(CLAWS), 2.1)


def circle_dots():
    """104x104: a ring of round dots (toe beans) where SuuUI's is dashed:
    waypoints and unknown flight points (2 px at the pin's 26 px)."""
    r, n, dr = 52 - 2, 18, 2.4

    def inside(x, y):
        a = math.atan2(y - 52, x - 52)
        k = round(a / (2 * math.pi / n))
        ca = k * 2 * math.pi / n
        return math.hypot(x - 52 - r * math.cos(ca), y - 52 - r * math.sin(ca)) <= dr
    cov = supersample(104, 104, inside)
    return 104, 104, lambda x, y: (255, 255, 255, round(255 * cov[(x, y)]))


def shade_pixel(cov, shade):
    """A white fill whose motif (coverage `cov`) is `shade` white."""
    def pixel(x, y):
        v = round(255 * (1 - (1 - shade) * cov[(x, y)]))
        return (v, v, v, 255)
    return pixel


def alpha_pixel(cov, strength=1.0):
    """White art: the motif's coverage as alpha, at most `strength`."""
    return lambda x, y: (255, 255, 255, round(255 * strength * cov[(x, y)]))


# How dark the bars' motifs are: the paws and beans darker than the fill so
# names on the bars keep their contrast, still one fill with a pattern in
# it. 87% was "too faint" (2026-11-12), 64% then a bit strong (2026-11-13,
# "a bit fainter"): 76%.
BAR_SHADE = 0.76


def paw_bar():
    """256x32: the health bar's fill, a trail of paw prints walking along
    it, stretched (a unit frame's bar is about 300x30)."""
    paws = []
    for i in range(8):
        x = 16 + 32 * i
        y = 11 if i % 2 == 0 else 21
        paws.append((x, y, 15, math.radians(-16 if i % 2 == 0 else 16)))
    return 256, 32, shade_pixel(paw_field(256, 32, paws), BAR_SHADE)


def cast_bar():
    """256x16: the cast bars' fill (about 300x20), a row of paws, stretched."""
    paws = [(12.8 + 25.6 * i, 8, 11, math.radians(-12 if i % 2 == 0 else 12)) for i in range(10)]
    return 256, 16, shade_pixel(paw_field(256, 16, paws), BAR_SHADE)


def simple_paw(cx, cy, size):
    """A paw for small sizes: a round pad and three toes, as ellipses."""
    s = size / 12.0
    return [(cx, cy + 2.4 * s, 3.6 * s, 3.0 * s), (cx - 3.6 * s, cy - 2.6 * s, 1.6 * s, 1.9 * s),
            (cx, cy - 4.0 * s, 1.7 * s, 2.0 * s), (cx + 3.6 * s, cy - 2.6 * s, 1.6 * s, 1.9 * s)]


def plate_bar():
    """256x20: the nameplates' fill (about 140x10, so drawn at twice that):
    simple three-toed paws, few and bold, that stay paws at 10 px."""
    shapes = []
    for i in range(6):
        shapes += simple_paw(21.3 + 42.67 * i, 10, 15)

    def inside(x, y):
        return any(in_ellipse(x, y, cx, cy, rx, ry) for cx, cy, rx, ry in shapes)
    return 256, 20, shade_pixel(supersample(256, 20, inside), BAR_SHADE)


def bean_bar():
    """256x16: the thin bars' fill (power lines, XP, meters, drains): a row
    of toe beans, stretched along the bar."""
    def inside(x, y):
        i = int(x // 16)
        return in_ellipse(x, y, 8 + 16 * i, 8, 4.2, 5.4)
    return 256, 16, shade_pixel(supersample(256, 16, inside), BAR_SHADE + 0.06)


# The windows' pattern at most this strong (white art in gilt over the
# surfaces): ink-faint keeps 3:1 on its brightest pixels, ink-muted 4.5:1
# (tests/unit/Core/ThemesBuiltin.test.wowlua, PATTERN_ALPHA).
# (0.16 until 2026-11-13: the user asked for it fainter.)
PATTERN_ALPHA = 0.10


def surface_pattern():
    """128x128, tiled over windows and panels: two paw prints and two small
    hearts on a wide staggered grid (each motif 64 px from the next), faint
    pink on the plum."""
    paws = [(30, 34, 13, math.radians(-18)), (94, 98, 13, math.radians(14))]
    hearts = [heart_points(96, 30, 9, 60), heart_points(32, 96, 9, 60)]
    paw = paw_field(128, 128, paws)
    heart = supersample(128, 128, lambda x, y: any(mt.inside_polygon(x, y, p) for p in hearts))
    cov = {k: max(paw[k], heart[k]) for k in paw}
    return 128, 128, alpha_pixel(cov, PATTERN_ALPHA)


def track_pattern():
    """32x32, tiled behind the bars (the missing health): one tiny paw a
    tile, fainter than the windows'."""
    cov = paw_field(32, 32, [(16, 16, 11, math.radians(-15))])
    return 32, 32, alpha_pixel(cov, 0.09)


def stitch():
    """8x8: the panels' edge as stitches (its first row and column are what
    a 1 px line shows): 5 px on, 3 px softly through."""
    def pixel(x, y):
        on = x < 5 if y == 0 else y < 5 if x == 0 else x < 5
        return (255, 255, 255, 255 if on else 70)
    return 8, 8, pixel


def corner_paw():
    """32x32: a paw print for the panels' corners."""
    cov = paw_field(32, 32, [(16, 16.5, 27, 0)], wrap=False)
    return 32, 32, alpha_pixel(cov)


def divider():
    """32x8: the divider under a panel's head, a tiny paw and a dot a tile."""
    shapes = simple_paw(10, 4, 7.6)
    shapes.append((26, 4.5, 1.3, 1.3))

    def inside(x, y):
        return any(in_ellipse(x, y, cx, cy, rx, ry) for cx, cy, rx, ry in shapes)
    return 32, 8, alpha_pixel(supersample(32, 8, inside))


# --- the dress (asked 2026-11-14: the corners that wrap, white, sparkles) ---
#
# Coloured art in its own colours (RGBA, drawn with tools/raid_art.py's
# renderer: later shapes over earlier ones). Pink satin ribbon with white
# stitches and a white edge wraps round every corner of the windows and the
# chat (an L along both edges, at most 4 px past them and 6 in, as the
# Icecrown Citadel and Ulduar themes' corners); a white bow on the top
# corners, a heart on the bottom ones; a string of pearls and hearts along a
# window's top between them; pink-and-white sparkles drifting up. The
# minimap in a pink ribbon with pearls and a cat's two ears, the big unit
# frames with a cat's two small ears on their top.

PINK, PINK_HI, PINK_DEEP = ra.c("#E48DBA"), ra.c("#F8BCD8"), ra.c("#B55A8A")
RIBBON_EDGE = ra.c("#86385F")
SNOW, SNOW_SHADE = ra.c("#FFFFFF"), ra.c("#F0CFE0")
EAR_INNER = ra.c("#FFE4F0")


def flip_y(shape, h):
    """A shape upside down in a file `h` tall."""
    b = shape.bbox
    return ra.Shape((b[0], h - b[3], b[2], h - b[1]), lambda x, y, fn=shape.fn: fn(x, h - y))


def sparkle_shapes(cx, cy, r, col, thin=0.2):
    """A four-point sparkle `r` from its middle to a point (a star twinkle)."""
    return [ra.polygon(ra.star(cx, cy, r, r * thin, 4, 0), col)]


def heart_shapes(cx, cy, w, fill, edge=None, shine=None):
    """A heart `w` wide: its fill, a white edge round it, a shine."""
    out = []
    if edge:
        out.append(ra.polygon(heart_points(cx, cy, w + 3.2, 80), edge))
    out.append(ra.polygon(heart_points(cx, cy, w, 80), fill))
    if shine:
        out.append(ra.ellipse(cx - w * 0.22, cy - w * 0.16, w * 0.12, w * 0.08, shine, -0.6))
    return out


def ribbon_arm():
    """The wrap's top arm (96 x 20 of the 96x96 file, the frame's edge at
    y 8, its corner at x 88): pink satin lit from above, a white shine along
    its top, white stitches down its middle and one white sparkle; its end
    cut as a ribbon's (a notch)."""
    ws, wt = ra.WS, ra.WT
    band = [(8, 0), (ws, 0), (ws - wt, wt), (8, wt), (14, wt / 2)]
    shapes = [ra.polygon(band, ra.lit(PINK_HI, PINK_DEEP, 0, wt)),
              ra.stroke([(12, 18.9), (ws - wt + 1, 18.9)], 1.6, RIBBON_EDGE),
              ra.stroke([(11, 2.0), (ws - 2, 2.0)], 1.5, ra.fade(SNOW, 0.85))]
    # the stitches, a gap for the sparkle (kept off the corner: the bow's)
    for x0 in (19, 26, 44, 51, 58, 65):
        shapes.append(ra.stroke([(x0, 10.4), (x0 + 3.6, 10.4)], 1.7, ra.fade(SNOW, 0.92)))
    shapes.append(ra.glow(36, 10, 9, SNOW, 0.35))
    shapes += sparkle_shapes(36, 10, 6.5, SNOW, 0.18)
    return shapes


@functools.lru_cache(None)
def wrap_top():
    """96x96 (drawn 48x48 at the top corners; flipped for the left): the
    ribbon round the corner, mitred (the bow is its own piece, over it)."""
    return ra.wrap(ribbon_arm())


@functools.lru_cache(None)
def wrap_low():
    """96x96, the bottom corners: the ribbon upside down, a white heart
    edged in deep pink on the corner (upright)."""
    arm = ribbon_arm()
    shapes = [flip_y(s, ra.WS) for s in arm + [ra.diag(s) for s in arm]]
    shapes += heart_shapes(ra.WS - 10, ra.WS - 10, 15, ra.lit(SNOW, SNOW_SHADE, ra.WS - 18, ra.WS - 3), PINK_DEEP,
                           ra.fade(PINK, 0.8))
    return ra.render(ra.WS, ra.WS, shapes)


@functools.lru_cache(None)
def bow():
    """64x48 (drawn 16x12 on the top corners, swaying a little): a white
    satin bow, pink in its folds, a pink knot."""
    k = (32, 19)
    shapes = []
    for side in (-1, 1):
        def sx(x, side=side):
            return k[0] + side * (k[0] - x)
        # the tail, then the loop (its outline a pink line, its hollow pink)
        tail = [(sx(30), 22), (sx(19), 44), (sx(23.5), 41), (sx(26.5), 46.5), (sx(36), 24)]
        shapes.append(ra.polygon(tail, ra.lit(SNOW, SNOW_SHADE, 22, 46)))
        shapes.append(ra.stroke(tail + [tail[0]], 1.4, ra.fade(PINK_DEEP, 0.75)))
        loop = ra.bez((sx(30), 16), (sx(22), 1), (sx(6), 1), (sx(4), 13), 14) + \
            ra.bez((sx(4), 13), (sx(2), 26), (sx(17), 29), (sx(30), 23), 14)[1:]
        shapes.append(ra.polygon(loop, ra.lit(SNOW, SNOW_SHADE, 2, 28)))
        shapes.append(ra.stroke(loop + [loop[0]], 1.6, ra.fade(PINK_DEEP, 0.8)))
        shapes.append(ra.ellipse(sx(17), 15, 7.5, 3.6, ra.fade(PINK, 0.55), side * -0.25))
    shapes.append(ra.ellipse(k[0], k[1] + 1, 5.6, 6.6, ra.lit(PINK_HI, PINK_DEEP, 13, 26)))
    shapes.append(ra.ellipse(k[0] - 1.8, k[1] - 1.6, 1.6, 2.2, ra.fade(SNOW, 0.85)))
    return ra.render(64, 48, shapes)


def pearls():
    """64x10 (drawn as it is, along a window's top between the wraps): a
    string of white pearls swagged between two small pink hearts."""
    shapes = []
    for xa, xb in ((16, 48), (48, 80), (-16, 16)):
        for k in range(1, 8):
            x = xa + (xb - xa) * k / 8
            y = 3.4 + 2.6 * math.sin(math.pi * k / 8)
            shapes.append(ra.ellipse(x, y, 1.35, 1.35, ra.lit(SNOW, SNOW_SHADE, y - 1.3, y + 1.3)))
    for x in (16, 48):
        shapes += heart_shapes(x, 4.4, 6.2, PINK, None, ra.fade(SNOW, 0.85))
    return ra.band(64, 10, shapes)


def ear_outline(bl, tip, br, bulge=0.07, round_=0.2):
    """A cat's ear's outline from one foot over its rounded tip to the
    other: its sides bowed a little outward (points y down)."""
    cx, cy = (bl[0] + tip[0] + br[0]) / 3, (bl[1] + tip[1] + br[1]) / 3

    def lerp(p, q, t):
        return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)

    def side(p, q):
        dx, dy = q[0] - p[0], q[1] - p[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        if (mx - cx) * nx + (my - cy) * ny < 0:
            nx, ny = -nx, -ny
        c1, c2 = lerp(p, q, 0.33), lerp(p, q, 0.66)
        return ra.bez(p, (c1[0] + nx * bulge * length, c1[1] + ny * bulge * length),
                      (c2[0] + nx * bulge * length, c2[1] + ny * bulge * length), q, 12)
    tl, tr = lerp(bl, tip, 1 - round_), lerp(br, tip, 1 - round_)
    top = ra.bez(tl, lerp(tl, tip, 0.7), lerp(tr, tip, 0.7), tr, 8)
    return side(bl, tl) + top[1:] + list(reversed(side(br, tr)))[1:]


def ear_shapes(bl, tip, br, inner, lit_y):
    """A cat's ear: pink, a white edge along its sides, its inside pale
    (`inner`: how much of the ear it fills, from the foot's middle)."""
    outer = ear_outline(bl, tip, br)
    mx, my = (bl[0] + br[0]) / 2, (bl[1] + br[1]) / 2

    def toward(p, t):
        return (mx + (p[0] - mx) * t, my + (p[1] - my) * t)
    pale = ear_outline(toward(bl, inner * 0.8), toward(tip, inner), toward(br, inner * 0.8))
    return [ra.polygon(outer, ra.lit(PINK, PINK_DEEP, *lit_y)),
            ra.polygon(pale, ra.lit(EAR_INNER, PINK_HI, *lit_y)),
            ra.stroke(outer, 1.5, ra.fade(SNOW, 0.92))]


# The minimap's ring: drawn this many px past the disc (room for the ears).
RING_PAST = 28


def ring():
    """The minimap (256, drawn RING_PAST px past its disc, behind its
    buttons) in a pink satin ribbon with a white line each side and white
    pearls on it, and a cat's two ears on its top (clear of the N and the
    buttons)."""
    cx = cy = 128
    r = ra.rim(RING_PAST)
    k = 128 / (88 + RING_PAST)  # file px a screen px
    shapes = []
    # (each ear on the ring at `deg`, its tip leaning `lean` degrees up from
    # the ring's outward line, as a cat's ears stand)
    for deg, lean in ((230, 16), (310, -16)):
        a = math.radians(deg)
        spread = math.radians(10.5)

        def p(rr, da, a=a):
            return ra.polar(cx, cy, rr, a + da)
        foot = p(r + 3, 0)
        tip = ra.polar(foot[0], foot[1], 23 * k, a + math.radians(lean))
        shapes += ear_shapes(p(r + 3, -spread), tip, p(r + 3, spread), 0.62, (tip[1], foot[1] + 6))
    # (a deeper pink than the corners' ribbon: lighter, it outshone the map)
    band = 7 * k
    shapes.append(ra.ring_band(cx, cy, r - 0.5, r + band, ra.ridge(PINK, RIBBON_EDGE, 1.1)))
    shapes.append(ra.annulus(cx, cy, r + 0.9, r + 0.9, 1.1, ra.fade(SNOW, 0.8)))
    shapes.append(ra.annulus(cx, cy, r + band - 0.6, r + band - 0.6, 1.0, ra.fade(SNOW, 0.6)))
    for deg in range(0, 360, 18):
        if ra.clear(deg):
            continue
        x, y = ra.polar(cx, cy, r + band / 2, math.radians(deg))
        shapes.append(ra.ellipse(x + 0.5, y + 0.7, 2.6, 2.6, ra.fade(RIBBON_EDGE, 0.5)))
        shapes.append(ra.ellipse(x, y, 2.5, 2.5, ra.lit(SNOW, SNOW_SHADE, y - 2.5, y + 2.5)))
    return ra.render(256, 256, shapes)


def unit_ears():
    """56x24 (drawn 28x12 on the big unit frames' top, twitching a little):
    a cat's two ears peeking over the frame."""
    shapes = []
    for x0, lean in ((5, -1.4), (32, 1.4)):
        shapes += ear_shapes((x0, 25), (x0 + 9.5 + lean, 2.6), (x0 + 19, 25), 0.6, (2, 25))
    return ra.render(56, 24, shapes)


def sparkle():
    """32x32 (the motes, drawn in their own colours, added to what's under
    them): a white sparkle with a little pink one beside it, in a soft pink
    glow."""
    shapes = [ra.glow(16, 16, 15.5, PINK, 0.55, power=1.8)]
    shapes += sparkle_shapes(16, 16.5, 12.5, SNOW, 0.17)
    shapes += [ra.polygon(ra.star(16, 16.5, 5.5, 1.3, 4, math.pi / 4), SNOW)]
    shapes += [ra.glow(25, 7, 5, PINK_HI, 0.8)] + sparkle_shapes(25, 7, 4.6, PINK_HI, 0.25)
    return ra.render(32, 32, shapes)


def header():
    """128x40, behind a window's title (stretched to its height, repeated
    along it): plum wallpaper in soft stripes, a few faint white sparkles
    (stretched, they stay sparkles), darker at its foot. Kept dark: the
    titles keep their contrast over its brightest pixel (check_header)."""
    shapes = []
    for x in range(0, 128, 16):
        shapes.append(ra.polygon(ra.rect(x, 0, x + 8, 40), ra.c("#25152A")))
        shapes.append(ra.polygon(ra.rect(x + 8, 0, x + 16, 40), ra.c("#2C1830")))
        shapes.append(ra.stroke([(x + 8, 0), (x + 8, 40)], 0.6, ra.fade(PINK, 0.12)))
    for x, y, r in ((22, 11, 3.4), (61, 27, 2.4), (97, 14, 2.8), (118, 31, 2.0), (40, 33, 1.8)):
        shapes += sparkle_shapes(x, y, r, ra.fade(SNOW, 0.24), 0.22)
    for x, y in ((80, 8), (8, 26), (52, 6), (106, 24)):
        shapes.append(ra.ellipse(x, y, 0.7, 0.7, ra.fade(PINK_HI, 0.3)))
    shade = ra.c("#120914")
    shapes.append(ra.polygon(ra.rect(-1, 22, 129, 40), ra.lit(ra.fade(shade, 0.02), ra.fade(shade, 0.45), 22, 40)))
    return ra.band(128, 40, shapes)


def lum(c3):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c3[0]) + 0.7152 * lin(c3[1]) + 0.0722 * lin(c3[2])


def check_header(rows):
    """The titles over the header's brightest pixel: gilt-text and ink at
    7:1, ink-muted at 4.5:1 (as over the windows' pattern)."""
    surface = (0x19, 0x0D, 0x1B)
    worst = 0.0
    for row in rows:
        for px in row:
            t = px[3] / 255
            worst = max(worst, lum(tuple(px[i] * t + surface[i] * (1 - t) for i in range(3))))
    for name, text, least in (("gilt-text", (0xFB, 0xCD, 0xE3), 7), ("ink", (0xFF, 0xF4, 0xE8), 7),
                              ("ink-muted", (0xBF, 0xA3, 0xBA), 4.5)):
        ratio = (lum(text) + 0.05) / (worst + 0.05)
        assert ratio >= least, "%s on the header: %.2f:1, under %s:1" % (name, ratio, least)


DRESS = {
    "Header": header,
    "Wrap": wrap_top,
    "WrapLow": wrap_low,
    "Bow": bow,
    "Pearls": pearls,
    "Ring": ring,
    "Ears": unit_ears,
    "Sparkle": sparkle,
}


TEXTURES = {
    "PawBar": paw_bar,
    "CastBar": cast_bar,
    "PlateBar": plate_bar,
    "BeanBar": bean_bar,
    "SurfacePattern": surface_pattern,
    "TrackPattern": track_pattern,
    "Stitch": stitch,
    "CornerPaw": corner_paw,
    "Divider": divider,
    "PawTapped": paw_tapped,
    "Hearts": hearts,
    "Heart": heart_texture,
    "RoleTank": role("tank"),
    "RoleHealer": role("healer"),
    "RoleDamage": role("damage"),
    "Claws": claws,
    "CircleDots": circle_dots,
}


# --- files ------------------------------------------------------------------

def glyph_pixels(name):
    return mt.stroke_alpha(mt.path_polylines(CAT[name]), 1.9)


def read_tga(path):
    with open(path, "rb") as fh:
        data = fh.read()
    idlen, _, kind = data[0], data[1], data[2]
    w, h = struct.unpack("<HH", data[12:16])
    bpp, desc = data[16], data[17]
    assert kind == 2 and bpp == 32, path
    px = data[18 + idlen:]
    rows = [px[y * w * 4:(y + 1) * w * 4] for y in range(h)]
    if not desc & 0x20:
        rows.reverse()
    return w, h, [[(r[x * 4 + 2], r[x * 4 + 1], r[x * 4], r[x * 4 + 3]) for x in range(w)] for r in rows]


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def resample(alpha, n):
    """An n x n area average of a square alpha grid."""
    size = len(alpha)
    k = size / n
    out = []
    for oy in range(n):
        row = []
        for ox in range(n):
            x0, x1, y0, y1 = ox * k, (ox + 1) * k, oy * k, (oy + 1) * k
            acc = 0.0
            for y in range(int(y0), min(size, math.ceil(y1))):
                wy = min(y + 1, y1) - max(y, y0)
                for x in range(int(x0), min(size, math.ceil(x1))):
                    wx = min(x + 1, x1) - max(x, x0)
                    acc += alpha[y][x] * wx * wy
            row.append(acc / (k * k))
        out.append(row)
    return out


def preview(path, names=None):
    """Each glyph's row: SuuUI's and the cat's at 64, then 24 and 16 px
    (each pixel drawn 3x3), on the theme's surface in ink and gilt."""
    bg, ink, pink = (0x19, 0x0D, 0x1B), (0xFF, 0xF4, 0xE8), (0xE4, 0x8D, 0xBA)
    names = names or sorted(CAT)
    cell = 64 + 8
    cols = [64, 64, 72, 72, 48, 48]
    width = 8 + sum(c + 8 for c in cols) + 8
    height = 8 + len(names) * (cell + 8)
    canvas = [[bg] * width for _ in range(height)]

    def blit(alpha, ox, oy, zoom, color):
        for y, row in enumerate(alpha):
            for x, a in enumerate(row):
                a = a / 255
                c = tuple(round(color[i] * a + bg[i] * (1 - a)) for i in range(3))
                for zy in range(zoom):
                    for zx in range(zoom):
                        canvas[oy + y * zoom + zy][ox + x * zoom + zx] = c

    for i, name in enumerate(names):
        oy = 8 + i * (cell + 8)
        w, h, own = read_tga(os.path.join(GLYPH_DIR, name + ".tga"))
        own_a = [[p[3] for p in row] for row in own]
        fn = glyph_pixels(name)
        cat_a = [[fn(x, y)[3] for x in range(64)] for y in range(64)]
        x = 8
        blit(own_a, x, oy, 1, ink); x += 72
        blit(cat_a, x, oy, 1, pink); x += 72
        blit(resample(own_a, 24), x, oy, 3, ink); x += 80
        blit(resample(cat_a, 24), x, oy, 3, pink); x += 80
        blit(resample(own_a, 16), x, oy, 3, ink); x += 56
        blit(resample(cat_a, 16), x, oy, 3, pink)
    write_png(path, width, height, canvas)
    print("wrote", path)


def dress_sheet(path):
    """The dress's art side by side on the theme's surface, at 2x (the ring
    at 1x)."""
    ground = (0x19, 0x0D, 0x1B)
    items = [make() for make in DRESS.values()]
    pad = 12
    placed, x, height = [], pad, 0
    for rows in items:
        h, w = len(rows), len(rows[0])
        zoom = 1 if w > 128 else 2
        placed.append((x, zoom, rows))
        x += w * zoom + pad
        height = max(height, h * zoom)
    width, height = x, height + 2 * pad
    canvas = [[ground] * width for _ in range(height)]
    for ox, zoom, rows in placed:
        for yy, row in enumerate(rows):
            for xx, px in enumerate(row):
                t = px[3] / 255
                col = tuple(round(px[i] * t + ground[i] * (1 - t)) for i in range(3))
                for zy in range(zoom):
                    for zx in range(zoom):
                        canvas[pad + yy * zoom + zy][ox + xx * zoom + zx] = col
    write_png(path, width, height, canvas)
    print("wrote", path)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--preview"]:
        preview(args[1], args[2:])
        return
    if args[:1] == ["--dress"]:
        dress_sheet(args[1])
        return
    only = set(args)
    os.makedirs(os.path.join(OUT, "Glyphs"), exist_ok=True)
    for name in CAT:
        if only and name not in only:
            continue
        path = os.path.join(OUT, "Glyphs", name + ".tga")
        mt.write_tga(path, 64, 64, glyph_pixels(name))
        print("wrote", os.path.relpath(path, ROOT))
    for name, make in TEXTURES.items():
        if only and name not in only:
            continue
        w, h, pixel = make()
        path = os.path.join(OUT, name + ".tga")
        mt.write_tga(path, w, h, pixel)
        print("wrote", os.path.relpath(path, ROOT))
    for name, make in DRESS.items():
        if only and name not in only:
            continue
        rows = make()
        if name == "Header":
            check_header(rows)
        path = os.path.join(OUT, name + ".tga")
        write_rgba_tga(path, rows)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
