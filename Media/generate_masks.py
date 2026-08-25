"""Generates Media/round-mask.tga -- the rounded-rectangle alpha mask.

Follows generate_micro_icons.py: every dimension is a number in this file, the art is rendered with
Pillow at 4x and downsampled, and verify() MEASURES THE RESULT.

    Media/round-mask.tga   64x64 uncompressed 32-bit, one full-bleed rounded rectangle

WHY THIS EXISTS, and it is not the same job as Backdrop.Panel. Panel rounds a SURFACE -- a bg and a
border drawn from textures we own. It cannot round somebody else's texture, and a bag cell is mostly
somebody else's texture: the item icon covers the cell edge to edge, so its square corners are the
corners the player sees and the rounded surface behind it is invisible. Measured in game 2026-08-25
-- the cells rendered hard square with Panel correctly installed underneath them.

The fix is a MASK on the art. The client's mask API is present on this build (probed: both
CreateMaskTexture and AddMaskTexture return "function"), and a mask multiplies its alpha into the
texture it is attached to, so a rounded mask makes any texture rounded -- including art we did not
draw and cannot change.

WHITE WITH A SOFT EDGE, on transparent. Only the ALPHA channel matters to a mask; the colour is
ignored. The edge is antialiased by the supersample, which is what makes the corner read as a curve
rather than as a staircase -- the client does not antialias a mask for you.

THE RADIUS IS PROPORTIONAL, not absolute, and that is a real difference from Panel's. A mask is
stretched over whatever it is attached to, so this radius is a FRACTION of the frame. For a grid of
equal square cells that is exactly right -- every cell gets an identical corner. For a frame that is
much wider than it is tall it would stretch the corner into an ellipse, which is why this is the
cells' mask and not a general-purpose rounding for any rectangle.
"""
from pathlib import Path

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Geometry. Every number the art depends on lives here.
# ---------------------------------------------------------------------------
SIZE = 64       # a power of two, which the client requires for a texture
SCALE = 4       # supersample factor -- this is what antialiases the corner
# Corner radius as a FRACTION of the edge. 0.125 puts the corner at about 4 pixels on a 34-unit bag
# cell, which is the concept's corner. Expressed as a fraction because a mask is stretched to the
# frame it masks, so an absolute pixel radius here would mean nothing.
RADIUS_FRAC = 0.125
RADIUS = round(SIZE * RADIUS_FRAC)   # 8

OPAQUE = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)


def render(scale=SCALE):
    """Draws the mask, supersampled, and returns it at final size."""
    big = SIZE * scale
    img = Image.new("RGBA", (big, big), CLEAR)
    d = ImageDraw.Draw(img)
    # FULL BLEED: the shape touches all four edges. A mask inset from its own edges would shrink
    # every texture it is attached to, which reads as the icon having a mysterious margin.
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius=RADIUS * scale, fill=OPAQUE)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------------------
# verify() -- measures the render. A comment claiming a corner is round is not evidence.
# ---------------------------------------------------------------------------
def verify(img):
    assert img.size == (SIZE, SIZE), f"mask is {img.size}, expected {(SIZE, SIZE)}"
    assert img.mode == "RGBA", f"mask mode is {img.mode}, expected RGBA"
    assert SIZE & (SIZE - 1) == 0, f"{SIZE} is not a power of two"

    px = img.load()
    mid = SIZE // 2

    # THE CENTRE IS FULLY OPAQUE. A mask that is not solid in the middle dims the texture it masks.
    assert px[mid, mid][3] == 255, f"centre alpha is {px[mid, mid][3]}, expected 255"

    # THE EDGE MIDPOINTS ARE OPAQUE -- full bleed, so the mask does not inset the art.
    for x, y in ((mid, 0), (mid, SIZE - 1), (0, mid), (SIZE - 1, mid)):
        assert px[x, y][3] >= 250, f"edge midpoint {x},{y} alpha is {px[x, y][3]}, expected opaque"

    # THE CORNERS ARE CUT. This is the whole point: the extreme corner pixel must be transparent,
    # or the mask is a plain rectangle and rounds nothing.
    for x, y in ((0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1)):
        assert px[x, y][3] <= 8, (
            f"corner {x},{y} alpha is {px[x, y][3]} -- the mask is not rounded at all"
        )

    # THE CUT IS THE RIGHT SIZE, measured as AREA rather than by probing a point. A single probe
    # point needs the diagonal cut boundary worked out -- it sits at r(1 - 1/sqrt2) from the corner,
    # about 2.34px at r=8 -- and my first attempt put the probe at r/3 = 2, which is INSIDE the
    # shape, so verify() failed on correct art. The area a quarter-round removes from its r x r
    # corner block is r^2(1 - pi/4), which is a property of the radius rather than of one pixel.
    expected = RADIUS * RADIUS * (1 - 3.14159265 / 4)
    cut = sum(1 for y in range(RADIUS) for x in range(RADIUS) if px[x, y][3] <= 8)
    assert cut >= expected * 0.55, (
        f"corner cut is {cut}px, expected about {expected:.0f} -- the radius is too small"
    )
    assert cut <= expected * 1.8, (
        f"corner cut is {cut}px, expected about {expected:.0f} -- the radius is too large"
    )

    # ANTIALIASED. A hard-edged mask staircases visibly at a bag-cell size, so there must be at
    # least a few partial pixels along the curve.
    partial = sum(1 for y in range(RADIUS + 2) for x in range(RADIUS + 2)
                  if 8 < px[x, y][3] < 250)
    assert partial >= RADIUS, (
        f"only {partial} partial pixels in the corner -- the curve is not antialiased"
    )


def main():
    out = Path(__file__).resolve().parent
    mask = render()
    verify(mask)

    # PNG alongside for eyeballing; the client only reads the TGA.
    mask.save(out / "round-mask.png")
    # Uncompressed -- Pillow's default, stated so a future edit keeps it.
    mask.save(out / "round-mask.tga", compression=None)

    print(f"round-mask.tga  {mask.size[0]}x{mask.size[1]}  mode={mask.mode}  "
          f"radius={RADIUS}px ({RADIUS_FRAC:.3f} of the edge)")


if __name__ == "__main__":
    main()
