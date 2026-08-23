#!/usr/bin/env python3
"""Renders the SuuUI logo from its geometric definition.

Not loaded by the game -- the .toc only takes .lua files. This exists so the mark stays
reproducible: the logo is DEFINED by the numbers below rather than by a binary someone
once exported, so a weight or palette change is an edit here plus a re-run.

The geometry is deliberately whole-number, which is the same discipline Core/Pixel.lua
applies to the UI itself. Two bowls share one vertical axis and their CENTRELINES are
tangent at (32,32), the exact centre of the 64-unit box.

Centreline tangency is the load-bearing part, and getting it wrong is how this shipped
visibly broken. Pillow draws an arc's stroke INWARD from its bounding box rather than
centred on the path, so R is the OUTER radius and the ink runs from R-S_W to R. Space the
two bowls by their outer radius and their ink meets at a single point on the axis -- a
knife edge that anti-aliasing then tears open, so the S renders as two disconnected
halves. Space them by their CENTRELINE radius instead and each stroke straddles the join,
overlapping in a lens around it. So the centres are DERIVED here, never typed in:

    centreline = R - S_W/2        centres = (32, 32 +/- centreline)

That also means R and S_W are not free: they have to leave the centreline radius on a
whole number, or the centres land off-grid. verify() asserts all of it against the
rendered pixels -- centring, whole-unit edges, and that the letterform is ONE connected
shape -- because a comment claiming precision is not precision.

The terminals are cut FLAT rather than rounded. Round caps were tried first and read as
bulbous knobs: a 270-degree bowl curls back close to its own terminal, so a disc there
collides with the stroke it is about to meet. A perpendicular cut is also the more honest
finish for a mark whose whole claim is precision.

Outputs:
  Media/logo.tga  64x64 uncompressed 32-bit -- the minimap button texture
  Media/logo.png  512x512 -- README and any large-format use

Usage:  python3 Media/generate_logo.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

# --- the mark, on a 64-unit grid ------------------------------------------------------
BOX = 64
FIELD_XY, FIELD_WH, FIELD_R = 6, 52, 18   # squircle: 52x52 at (6,6), 18-unit corner
RING_W = 3                                 # container stroke
S_W = 6                                    # letterform stroke, drawn inward from R
R = 11                                     # bowl OUTER radius

CENTRELINE = R - S_W / 2                   # 8 -- the radius the stroke is centred on
UPPER_C = (BOX / 2, BOX / 2 - CENTRELINE)  # (32, 24)
LOWER_C = (BOX / 2, BOX / 2 + CENTRELINE)  # (32, 40)

assert float(CENTRELINE).is_integer(), (
    f"R={R} and S_W={S_W} give a centreline radius of {CENTRELINE}, which puts the bowl "
    f"centres off the whole-unit grid. Pick a pair whose R - S_W/2 is an integer.")

# --- palette, lifted from Themes/Default.lua -----------------------------------------
FIELD = (18, 18, 24, 255)        # near colorGray900
GRAD_FROM = (111, 174, 255)      # lighter colorBlue400
GRAD_TO = (46, 91, 216)          # toward colorBlue500
LETTER = (235, 235, 235, 255)    # colorGray100

SCALE = 8                        # supersample; 6*8=48px stroke downsamples to exactly 6


def _linear_gradient(size, c0, c1):
    """Diagonal top-left -> bottom-right ramp."""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x + y) / max(1, (w + h - 2))
            px[x, y] = (
                round(c0[0] + (c1[0] - c0[0]) * t),
                round(c0[1] + (c1[1] - c0[1]) * t),
                round(c0[2] + (c1[2] - c0[2]) * t),
            )
    return img


def render(scale=SCALE):
    s = scale
    size = (BOX * s, BOX * s)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x, y, w, h):
        return [x * s, y * s, (x + w) * s - 1, (y + h) * s - 1]

    # Dark field, clipped to the squircle.
    d.rounded_rectangle(box(FIELD_XY, FIELD_XY, FIELD_WH, FIELD_WH),
                        radius=FIELD_R * s, fill=FIELD)

    # Gradient ring: paint the ramp through a mask that is the outline only.
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        box(FIELD_XY, FIELD_XY, FIELD_WH, FIELD_WH),
        radius=FIELD_R * s, outline=255, width=RING_W * s)
    img.paste(_linear_gradient(size, GRAD_FROM, GRAD_TO), (0, 0), mask)

    # The S: two 270-degree arcs. Pillow measures clockwise from 3 o'clock, so the upper
    # bowl runs 90->360 (bottom, left, top, right) and the lower 270->540 (top, right,
    # bottom, left). Together they trace one continuous S through the tangent point.
    def arc(centre, a0, a1):
        cx, cy = centre
        d.arc([(cx - R) * s, (cy - R) * s, (cx + R) * s - 1, (cy + R) * s - 1],
              a0, a1, fill=LETTER, width=S_W * s)

    arc(UPPER_C, 90, 360)
    arc(LOWER_C, 270, 540)

    return img


def _assert_waist_joined(img, tol=0.05):
    """The two bowls must OVERLAP at the waist, not merely touch.

    Connectivity is the obvious check and it is useless here: at knife-edge spacing the
    bowls still share a pixel column, so a flood fill happily walks across a join that is
    infinitesimally thin -- and then anti-aliasing thins it to nothing and the S renders
    torn in two. The discriminating measurement is the WIDTH of the ink across the waist
    row. With the centrelines tangent the stroke runs horizontally through (32,32), so
    that row carries a broad run; with the bowls spaced by their outer radius it carries
    only the sliver at the bottom of a circle.
    """
    px = img.load()
    unit = img.size[0] / BOX
    row = int(BOX / 2 * unit)
    run = best = 0
    for x in range(img.size[0]):
        r, g, b, a = px[x, row]
        if a > 128 and _is_letter(r, g, b):
            run += 1
            best = max(best, run)
        else:
            run = 0
    width = best / unit
    print(f"  waist join: {width:.2f} units of unbroken ink across y={BOX // 2}")
    assert width >= S_W - tol, (
        f"the waist join is only {width:.2f} units wide against a {S_W}-unit stroke -- the "
        f"bowls are touching rather than overlapping, and the S will render as two "
        f"disconnected halves. Centres must be 2*(R - S_W/2) apart, not 2*R.")


def _is_letter(r, g, b):
    return r > 200 and g > 200 and b > 200


def _ink_bbox(img, pred):
    px = img.load()
    w, h = img.size
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 128 and pred(r, g, b):
                xs.append(x)
                ys.append(y)
    if not xs:
        raise AssertionError("generate_logo: found no ink to measure")
    return min(xs), min(ys), max(xs), max(ys)


def verify(img, tol=0.05):
    """Measures the render and asserts what 'pixel perfect' is supposed to mean.

    Every one of these caught a real defect during design: the S shipped a full unit high
    (centring), and it shipped visibly torn in two (the waist join), with every individual
    coordinate looking reasonable both times. Nothing but a measurement catches that.
    """
    _assert_waist_joined(img)

    unit = img.size[0] / BOX
    fx0, fy0, fx1, fy1 = _ink_bbox(img, lambda r, g, b: True)
    lx0, ly0, lx1, ly1 = _ink_bbox(img, _is_letter)

    dx = ((lx0 + lx1) / 2 - (fx0 + fx1) / 2) / unit
    dy = ((ly0 + ly1) / 2 - (fy0 + fy1) / 2) / unit
    print(f"  offset from field centre: x {dx:+.3f}  y {dy:+.3f} units")
    assert abs(dx) <= tol, f"letterform is {dx:+.3f} units off centre horizontally"
    assert abs(dy) <= tol, f"letterform is {dy:+.3f} units off centre vertically"

    # Whole-unit extents are the other half of the claim: a fractional edge means a
    # coordinate slipped off the grid.
    edges = (("left", lx0 / unit), ("top", ly0 / unit),
             ("right", (lx1 + 1) / unit), ("bottom", (ly1 + 1) / unit))
    for name, v in edges:
        assert abs(v - round(v)) <= tol, f"letter {name} edge lands at {v:.3f}, off-grid"
    print(f"  letter box: x {lx0/unit:g}..{(lx1+1)/unit:g}  y {ly0/unit:g}..{(ly1+1)/unit:g}"
          f"   bowls r={R} stroke={S_W} centreline={CENTRELINE:g}")


def main():
    out = Path(__file__).resolve().parent
    master = render()
    verify(master)

    master.save(out / "logo.png")

    # 64x64 for the minimap button. Power of two is a hard client requirement, and the
    # TGA must be uncompressed -- Pillow's default, but stated so a future edit keeps it.
    icon = master.resize((BOX, BOX), Image.LANCZOS)
    icon.save(out / "logo.tga", compression=None)

    print(f"logo.png  {master.size[0]}x{master.size[1]}")
    print(f"logo.tga  {icon.size[0]}x{icon.size[1]}  mode={icon.mode}")


if __name__ == "__main__":
    main()
