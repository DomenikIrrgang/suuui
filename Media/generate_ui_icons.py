"""Generates Media/ui-icons.tga -- the SHARED UI glyph sheet.

Follows generate_micro_icons.py exactly: every dimension is a number in this file, the art is
rendered with Pillow at 4x and downsampled, and verify() MEASURES THE RESULT rather than trusting a
comment that claims precision.

    Media/ui-icons.tga   64x64 uncompressed 32-bit, a 2x2 grid of 32x32 glyphs

WHY A SECOND SHEET RATHER THAN THE TWO FREE CELLS IN micro-icons.tga. The micro sheet has exactly
two cells spare, so it would have fitted -- and it would have been wrong. Its coord table lives in
Plugins/DataBar, so an inventory window reading a glyph from it would be one plugin reaching into
another plugin's internals, which is the one thing plugins may never do. This sheet is consumed
through Core/Icons.lua instead, so any plugin can ask for a glyph and none of them depend on each
other. The cost is one extra texture; the alternative is a dependency that cannot be undone later.

WHITE ON TRANSPARENT, deliberately, for the same reason the micro sheet is: the Lua side tints each
glyph with SetVertexColor so it follows colorTextMuted at rest and colorAccent on hover. Any hue
baked in here would ignore the theme.

GLYPH ORDER IS A CONTRACT. Core/Icons.lua mirrors this list by INDEX, so inserting a glyph in the
middle silently re-points every entry after it. Append only.
"""
from pathlib import Path

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Geometry. Every number the art depends on lives here.
# ---------------------------------------------------------------------------
CELL = 32            # one glyph, in final pixels -- same as the micro sheet, so glyphs are swappable
GRID = 2             # 2x2 cells
SHEET = CELL * GRID  # 64 -- a power of two, which the client requires for a texture
SCALE = 4            # supersample factor
PAD = 4              # keep-clear margin inside a cell, in final pixels

# The ink. White, because the tint is applied at draw time in Lua.
INK = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)

# Stroke weights, in final pixels.
STROKE = 2.5
THIN = 1.75

# ORDER IS A CONTRACT -- see the module docstring. Append only.
GLYPHS = [
    "sort",     # 0  two arrows, one up one down -- change the ordering
    "account",  # 1  a globe -- this is account-wide rather than this character
]
assert len(GLYPHS) <= GRID * GRID, (
    f"{len(GLYPHS)} glyphs will not fit a {GRID}x{GRID} sheet"
)


def cell_origin(index):
    """Top-left of a glyph's cell in FINAL pixels, left to right then top to bottom."""
    return (index % GRID) * CELL, (index // GRID) * CELL


def tex_coords(index):
    """The SetTexCoord tuple for a glyph: left, right, top, bottom as 0..1 fractions."""
    x, y = cell_origin(index)
    return (x / SHEET, (x + CELL) / SHEET, y / SHEET, (y + CELL) / SHEET)


# ---------------------------------------------------------------------------
# Drawing. Each glyph is drawn into its own supersampled cell, in cell-local
# coordinates from 0..CELL, so a glyph never has to know where it sits on the sheet.
# ---------------------------------------------------------------------------
def _arrow(d, u, x, y0, y1, head):
    """A shaft from (x, y0) to (x, y1) with a chevron head at the y1 end.

    Two straight lines rather than a filled triangle: at 32px a filled head of a readable size
    swamps the shaft and the glyph reads as a pin, while a chevron keeps the arrow's line weight
    consistent with every other glyph on the sheet.
    """
    d.line([u.p(x, y0), u.p(x, y1)], fill=INK, width=u.w(STROKE))
    back = y1 - head if y1 > y0 else y1 + head
    d.line([u.p(x - head, back), u.p(x, y1)], fill=INK, width=u.w(THIN))
    d.line([u.p(x + head, back), u.p(x, y1)], fill=INK, width=u.w(THIN))


def _draw_sort(d, u):
    """Two arrows side by side, one pointing up and one pointing down.

    The conventional sort affordance, and it has to be TWO arrows: a single one reads as a
    scroll or a move, and only the opposed pair says "the order can go either way". Drawn as a
    pair of full-height shafts rather than the stacked-lines-with-one-arrow variant, which loses
    its short lines entirely at this size.
    """
    _arrow(d, u, 11, 25, 7, 4)    # up
    _arrow(d, u, 21, 7, 25, 4)    # down


def _draw_account(d, u):
    """A globe: a circle with an equator and a meridian.

    Both interior curves are needed. The circle alone is a dot or a ring depending on weight; the
    equator alone makes it a coin. The meridian is an ELLIPSE rather than a straight vertical --
    a straight line plus a straight equator reads as a crosshair, which means something else
    entirely on a button.
    """
    d.ellipse(u.box(6, 6, 20, 20), outline=INK, width=u.w(THIN))
    d.line([u.p(6.5, 16), u.p(25.5, 16)], fill=INK, width=u.w(THIN))
    d.ellipse(u.box(12, 6, 8, 20), outline=INK, width=u.w(THIN))


DRAW = {
    "sort": _draw_sort,
    "account": _draw_account,
}
assert set(DRAW) == set(GLYPHS), "every glyph in GLYPHS needs a draw function"


class _Units:
    """Cell-local coordinates in final pixels, scaled to the supersampled canvas.

    A glyph is written in 0..32 and never has to know the scale factor or where its cell sits.
    """

    def __init__(self, scale):
        self.scale = scale

    def p(self, x, y):
        return (x * self.scale, y * self.scale)

    def box(self, x, y, w, h):
        return [x * self.scale, y * self.scale,
                (x + w) * self.scale - 1, (y + h) * self.scale - 1]

    def w(self, stroke):
        return max(1, round(stroke * self.scale))


def render(scale=SCALE):
    """Draws the whole sheet, supersampled, and returns it at final size."""
    u = _Units(scale)
    sheet = Image.new("RGBA", (SHEET * scale, SHEET * scale), CLEAR)

    for index, name in enumerate(GLYPHS):
        cell = Image.new("RGBA", (CELL * scale, CELL * scale), CLEAR)
        DRAW[name](ImageDraw.Draw(cell), u)
        x, y = cell_origin(index)
        sheet.paste(cell, (x * scale, y * scale))

    return sheet.resize((SHEET, SHEET), Image.LANCZOS)


# ---------------------------------------------------------------------------
# verify() -- measures the render. Comments claiming precision are not evidence.
# ---------------------------------------------------------------------------
def _cell_ink_bbox(img, index):
    """Bounding box of the drawn pixels in a cell, in cell-local final pixels, or None."""
    ox, oy = cell_origin(index)
    px = img.load()
    xs, ys = [], []
    for y in range(CELL):
        for x in range(CELL):
            if px[ox + x, oy + y][3] > 8:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def verify(img):
    """Asserts what 'a usable glyph sheet' actually means, glyph by glyph."""
    assert img.size == (SHEET, SHEET), f"sheet is {img.size}, expected {(SHEET, SHEET)}"
    assert img.mode == "RGBA", f"sheet mode is {img.mode}, expected RGBA"
    assert SHEET & (SHEET - 1) == 0, f"{SHEET} is not a power of two"

    px = img.load()
    for index, name in enumerate(GLYPHS):
        bbox = _cell_ink_bbox(img, index)
        assert bbox is not None, f"glyph {index} ({name}) drew nothing at all"
        x0, y0, x1, y1 = bbox

        # INSIDE ITS OWN CELL, with the keep-clear margin respected. A glyph that bleeds past its
        # cell shows a sliver of its neighbour everywhere it is used.
        assert x0 >= PAD - 1 and y0 >= PAD - 1, (
            f"glyph {index} ({name}) starts at {x0},{y0}, inside the {PAD}px margin"
        )
        assert x1 <= CELL - PAD and y1 <= CELL - PAD, (
            f"glyph {index} ({name}) ends at {x1},{y1}, past the {PAD}px margin"
        )

        # BIG ENOUGH TO READ. A glyph that renders as a few stray pixels passes a "drew something"
        # check and is invisible on the button.
        w, h = x1 - x0 + 1, y1 - y0 + 1
        assert w >= CELL * 0.4, f"glyph {index} ({name}) is only {w}px wide"
        assert h >= CELL * 0.4, f"glyph {index} ({name}) is only {h}px tall"

        # ROUGHLY CENTRED, so a glyph does not read as misaligned next to its neighbours.
        cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
        assert abs(cx - CELL / 2) <= 3.5, f"glyph {index} ({name}) is {cx:.1f} off centre in x"
        assert abs(cy - CELL / 2) <= 3.5, f"glyph {index} ({name}) is {cy:.1f} off centre in y"

    # WHITE, so the Lua tint decides the colour.
    for index in range(len(GLYPHS)):
        ox, oy = cell_origin(index)
        for y in range(CELL):
            for x in range(CELL):
                r, g, b, a = px[ox + x, oy + y]
                if a > 200:
                    assert r == g == b, (
                        f"glyph {index} has a coloured pixel at {x},{y}: {(r, g, b)} -- the sheet "
                        f"must be monochrome so SetVertexColor can tint it"
                    )

    # UNUSED CELLS ARE EMPTY, so a coord table pointing at one shows nothing rather than debris.
    for index in range(len(GLYPHS), GRID * GRID):
        assert _cell_ink_bbox(img, index) is None, f"unused cell {index} is not empty"


def main():
    out = Path(__file__).resolve().parent
    sheet = render()
    verify(sheet)

    # PNG alongside for eyeballing; the client only reads the TGA.
    sheet.save(out / "ui-icons.png")
    # Uncompressed -- Pillow's default, stated so a future edit keeps it.
    sheet.save(out / "ui-icons.tga", compression=None)

    print(f"ui-icons.tga  {sheet.size[0]}x{sheet.size[1]}  mode={sheet.mode}  "
          f"{len(GLYPHS)} glyphs")
    print("\nLua coord table (mirror of GLYPHS -- order is a contract):")
    for index, name in enumerate(GLYPHS):
        l, r, t, b = tex_coords(index)
        print(f'    {name:10s} = {{ {l:.5f}, {r:.5f}, {t:.5f}, {b:.5f} }},')


if __name__ == "__main__":
    main()
