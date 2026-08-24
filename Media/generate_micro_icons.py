"""Generates Media/micro-icons.tga -- the micro menu's glyph sheet.

Follows generate_logo.py: every dimension is a number in this file, the art is rendered with
Pillow, and verify() MEASURES THE RESULT rather than trusting a comment that claims precision.

    Media/micro-icons.tga   128x128 uncompressed 32-bit, a 4x4 grid of 32x32 glyphs

WHITE ON TRANSPARENT, deliberately. The Lua side tints each glyph with SetVertexColor so it
follows colorTextMuted at rest and colorAccent on hover -- so the art carries no colour of its
own and a theme change needs no new file. Anything drawn here in colour would ignore the theme.

RENDERED AT 4x AND DOWNSAMPLED. A 32x32 glyph drawn directly has no room for a smooth diagonal,
and the client does not antialias a texture for you. Supersampling is what makes a sword edge or
a paw print read at 32 pixels instead of turning into a staircase.

GLYPH ORDER IS A CONTRACT. The Lua coord table in Plugins/DataBar mirrors this list by INDEX, so
inserting a glyph in the middle silently re-points every entry after it. Append only.
"""
from pathlib import Path

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Geometry. Every number the art depends on lives here.
# ---------------------------------------------------------------------------
CELL = 32           # one glyph, in final pixels
GRID = 4            # 4x4 cells
SHEET = CELL * GRID  # 128 -- a power of two, which the client requires for a texture
SCALE = 4           # supersample factor
PAD = 4             # keep-clear margin inside a cell, in final pixels

# The ink. White, because the tint is applied at draw time in Lua.
INK = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)

# Stroke weights, in final pixels. Thin enough to read as a line at 32px, thick enough not to
# disappear when the client downscales a bar to a smaller button size.
STROKE = 2.5
THIN = 1.75

# ORDER IS A CONTRACT -- see the module docstring. Append only.
GLYPHS = [
    "char",         # 0  a person
    "spells",       # 1  an open book
    "talents",      # 2  a branching tree
    "quests",       # 3  a scroll
    "social",       # 4  two people
    "guild",        # 5  a banner
    "pvp",          # 6  crossed swords
    "lfg",          # 7  an eye
    "map",          # 8  a folded map
    "menu",         # 9  three bars
    "help",         # 10 a question mark
    "collections",  # 11 a paw print
    "bags",         # 12 a pouch
    "keys",         # 13 a key
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
def _draw_char(d, u):
    """A head and shoulders."""
    d.ellipse(u.box(16 - 5, 7, 10, 10), outline=INK, width=u.w(STROKE))
    d.arc(u.box(16 - 9, 18, 18, 16), 180, 360, fill=INK, width=u.w(STROKE))


def _draw_spells(d, u):
    """A book seen face-on: a cover with a spine down the left and two page lines.

    THREE attempts, and the two rejected ones are worth recording because both failed the same way.
    An OPEN book does not survive 32 pixels: an outline plus a centre stroke read as a barrel, and
    two leaning polygons read as a hexagonal gem, because `polygon(outline=...)` closes the shape and
    the outer edges join. A closed book is unambiguous at this size, and its vertical spine is what
    tells it apart from the scroll glyph, which is horizontal lines with rolled ends.
    """
    d.rectangle(u.box(9, 7, 15, 19), outline=INK, width=u.w(THIN))
    d.line([u.p(12, 7), u.p(12, 25)], fill=INK, width=u.w(STROKE))
    d.line([u.p(16, 13), u.p(21, 13)], fill=INK, width=u.w(THIN))
    d.line([u.p(16, 19), u.p(21, 19)], fill=INK, width=u.w(THIN))


def _draw_talents(d, u):
    """A trunk that forks twice -- the shape of a talent tree."""
    d.line([u.p(16, 26), u.p(16, 17)], fill=INK, width=u.w(STROKE))
    d.line([u.p(16, 17), u.p(9, 11)], fill=INK, width=u.w(STROKE))
    d.line([u.p(16, 17), u.p(23, 11)], fill=INK, width=u.w(STROKE))
    for cx, cy in ((9, 8), (23, 8), (16, 17)):
        d.ellipse(u.box(cx - 3, cy - 3, 6, 6), fill=INK)


def _draw_quests(d, u):
    """A scroll: a narrow page whose rolled ends stick out WIDER than the body.

    The overhang is the whole point. With the rolls flush to the body this was a bordered rectangle
    with lines in it -- which is what the spellbook next to it also is. A scroll's silhouette is the
    thing that distinguishes them, not the detail inside.
    """
    d.rectangle(u.box(10, 9, 12, 14), outline=INK, width=u.w(THIN))
    d.line([u.p(6, 9), u.p(26, 9)], fill=INK, width=u.w(STROKE))
    d.line([u.p(6, 23), u.p(26, 23)], fill=INK, width=u.w(STROKE))
    for y in (14, 18):
        d.line([u.p(13, y), u.p(19, y)], fill=INK, width=u.w(THIN))


def _draw_social(d, u):
    """Two heads, one behind the other."""
    # Narrower than a single figure needs: two of them side by side have to leave the keep-clear
    # margin at BOTH cell edges, and a stroke is drawn centred so it bleeds half its width past the
    # box. verify() rejected the first attempt at x=2 for exactly that.
    d.ellipse(u.box(7, 8, 8, 8), outline=INK, width=u.w(THIN))
    d.arc(u.box(5, 17, 13, 13), 180, 360, fill=INK, width=u.w(THIN))
    d.ellipse(u.box(17, 8, 8, 8), outline=INK, width=u.w(THIN))
    d.arc(u.box(14, 17, 13, 13), 180, 360, fill=INK, width=u.w(THIN))


def _draw_guild(d, u):
    """A hanging banner with a notched hem."""
    d.line([u.p(7, 6), u.p(25, 6)], fill=INK, width=u.w(STROKE))
    d.line([u.p(9, 6), u.p(9, 22)], fill=INK, width=u.w(THIN))
    d.line([u.p(23, 6), u.p(23, 22)], fill=INK, width=u.w(THIN))
    d.line([u.p(9, 22), u.p(16, 18)], fill=INK, width=u.w(THIN))
    d.line([u.p(23, 22), u.p(16, 18)], fill=INK, width=u.w(THIN))


def _draw_pvp(d, u):
    """Crossed swords."""
    for x0, x1 in ((8, 24), (24, 8)):
        d.line([u.p(x0, 25), u.p(x1, 8)], fill=INK, width=u.w(STROKE))
    d.line([u.p(6, 21), u.p(11, 26)], fill=INK, width=u.w(THIN))
    d.line([u.p(26, 21), u.p(21, 26)], fill=INK, width=u.w(THIN))


def _draw_lfg(d, u):
    """An eye -- looking for a group."""
    d.arc(u.box(4, 8, 24, 16), 180, 360, fill=INK, width=u.w(THIN))
    d.arc(u.box(4, 8, 24, 16), 0, 180, fill=INK, width=u.w(THIN))
    d.ellipse(u.box(13, 13, 6, 6), fill=INK)


def _draw_map(d, u):
    """A folded map: a rectangle creased into three panels."""
    d.rectangle(u.box(5, 9, 22, 14), outline=INK, width=u.w(THIN))
    d.line([u.p(12, 9), u.p(12, 23)], fill=INK, width=u.w(THIN))
    d.line([u.p(20, 9), u.p(20, 23)], fill=INK, width=u.w(THIN))


def _draw_menu(d, u):
    """Three bars."""
    for y in (11, 16, 21):
        d.line([u.p(8, y), u.p(24, y)], fill=INK, width=u.w(STROKE))


def _draw_help(d, u):
    """A question mark: a hook over a dot."""
    d.arc(u.box(10, 7, 12, 12), 160, 20, fill=INK, width=u.w(STROKE))
    d.line([u.p(16, 15), u.p(16, 20)], fill=INK, width=u.w(STROKE))
    d.ellipse(u.box(14.5, 23, 3, 3), fill=INK)


def _draw_collections(d, u):
    """A paw print. Collections was missing from the concept's thirteen."""
    d.ellipse(u.box(12, 14, 8, 7), fill=INK)
    for cx in (9, 14.5, 20):
        d.ellipse(u.box(cx - 2, 9, 4, 4), fill=INK)
    d.ellipse(u.box(22, 13, 4, 4), fill=INK)


def _draw_bags(d, u):
    """A bag: a body that widens downward, with a handle over it.

    The first attempt was a drawstring pouch and read as a SHIELD outline. A handle above a
    trapezoid body is what makes it unmistakably a bag at this size.
    """
    d.polygon([u.p(10, 14), u.p(22, 14), u.p(25, 26), u.p(7, 26)],
              outline=INK, width=u.w(THIN))
    d.arc(u.box(11, 8, 10, 12), 180, 360, fill=INK, width=u.w(STROKE))


def _draw_keys(d, u):
    """A key: a ring and a toothed shaft."""
    # Drawn on the diagonal. A horizontal key is only as tall as its ring, which verify() rejected
    # at 12px -- next to glyphs that fill their cell it reads as a different icon set.
    d.ellipse(u.box(6, 6, 11, 11), outline=INK, width=u.w(STROKE))
    d.line([u.p(15, 15), u.p(25, 25)], fill=INK, width=u.w(STROKE))
    d.line([u.p(19, 22), u.p(23, 18)], fill=INK, width=u.w(THIN))
    d.line([u.p(22, 25), u.p(25, 22)], fill=INK, width=u.w(THIN))


DRAW = {
    "char": _draw_char, "spells": _draw_spells, "talents": _draw_talents,
    "quests": _draw_quests, "social": _draw_social, "guild": _draw_guild,
    "pvp": _draw_pvp, "lfg": _draw_lfg, "map": _draw_map, "menu": _draw_menu,
    "help": _draw_help, "collections": _draw_collections, "bags": _draw_bags,
    "keys": _draw_keys,
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
        # cell shows a sliver of its neighbour in every field that uses it -- the exact defect a
        # coord table cannot fix later.
        assert x0 >= PAD - 1 and y0 >= PAD - 1, (
            f"glyph {index} ({name}) starts at {x0},{y0}, inside the {PAD}px margin"
        )
        assert x1 <= CELL - PAD and y1 <= CELL - PAD, (
            f"glyph {index} ({name}) ends at {x1},{y1}, past the {PAD}px margin"
        )

        # BIG ENOUGH TO READ. A glyph that renders as a few stray pixels passes a "drew something"
        # check and is invisible on the bar.
        w, h = x1 - x0 + 1, y1 - y0 + 1
        assert w >= CELL * 0.4, f"glyph {index} ({name}) is only {w}px wide"
        assert h >= CELL * 0.4, f"glyph {index} ({name}) is only {h}px tall"

        # ROUGHLY CENTRED. An off-centre glyph reads as misaligned next to its neighbours even
        # though each one is individually fine.
        cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
        assert abs(cx - CELL / 2) <= 3.5, f"glyph {index} ({name}) is {cx:.1f} off centre in x"
        assert abs(cy - CELL / 2) <= 3.5, f"glyph {index} ({name}) is {cy:.1f} off centre in y"

    # WHITE, so the Lua tint decides the colour. Any hue baked in here would ignore the theme.
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
    sheet.save(out / "micro-icons.png")
    # Uncompressed -- Pillow's default, stated so a future edit keeps it.
    sheet.save(out / "micro-icons.tga", compression=None)

    print(f"micro-icons.tga  {sheet.size[0]}x{sheet.size[1]}  mode={sheet.mode}  "
          f"{len(GLYPHS)} glyphs")
    print("\nLua coord table (mirror of GLYPHS -- order is a contract):")
    for index, name in enumerate(GLYPHS):
        l, r, t, b = tex_coords(index)
        print(f'    {name:12s} = {{ {l:.5f}, {r:.5f}, {t:.5f}, {b:.5f} }},')


if __name__ == "__main__":
    main()
