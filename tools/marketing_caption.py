#!/usr/bin/env python3
# tools/marketing_caption.py: the store pages' screenshots (tests/marketing).
# Puts each scene's caption bar under its screenshot and writes, into OUT:
#   NN-name.png        the scene with its caption bar under it (1920 x 1218)
#   clean/NN-name.png  the scene alone (1920 x 1080)
#   captions.txt       each image's headline and line, for the stores' image
#                      descriptions
# The scenes and bars come from `wowlua test` (dist/screenshots/...); the
# list, its order and the captions from tests/marketing/captions.wowlua.
# Standard library only (no Pillow): the PNGs are stacked row by row.
#
#   python3 -I tools/marketing_caption.py [OUT]     (OUT: dist/marketing)

import os, re, shutil, struct, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "dist", "screenshots")
CAPTIONS = os.path.join(ROOT, "tests", "marketing", "captions.wowlua")
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def captions():
    entry = re.compile(r'file = "([^"]+)",\s*shot = "([^"]+)",\s*headline = "([^"]+)",\s*subline = "([^"]+)"')
    return entry.findall(open(CAPTIONS, encoding="utf-8").read())


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, head = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        pos += 12 + length
    width, height, depth, color, _, _, interlace = head
    if depth != 8 or interlace != 0 or color not in CHANNELS:
        raise SystemExit(f"{path}: only 8-bit, non-interlaced PNGs")
    return width, height, color, zlib.decompress(b"".join(idat))


def first_row_plain(raw, stride, bpp):
    # The first row's filter undone (it may lean on the row above, which is
    # nothing in its own picture but the scene's last row once stacked).
    kind, row = raw[0], bytearray(raw[1 : 1 + stride])
    if kind in (1, 4):  # Sub; Paeth with no row above is Sub
        for i in range(bpp, stride):
            row[i] = (row[i] + row[i - bpp]) & 0xFF
    elif kind == 3:  # Average with no row above
        for i in range(bpp, stride):
            row[i] = (row[i] + (row[i - bpp] >> 1)) & 0xFF
    return b"\x00" + bytes(row) + raw[1 + stride :]


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def stack(top, bottom, out):
    w1, h1, c1, raw1 = read_png(top)
    w2, h2, c2, raw2 = read_png(bottom)
    if (w1, c1) != (w2, c2):
        raise SystemExit(f"{bottom}: {w2} wide (colour type {c2}), the scene {w1} ({c1})")
    bpp = CHANNELS[c1]
    raw = raw1 + first_row_plain(raw2, w2 * bpp, bpp)
    with open(out, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w1, h1 + h2, 8, c1, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "dist", "marketing")
    os.makedirs(os.path.join(out, "clean"), exist_ok=True)
    lines = []
    for name, shot, headline, subline in captions():
        scene = os.path.join(SHOTS, shot + ".png")
        bar = os.path.join(SHOTS, "caption.test.wowlua", name + ".png")
        for p in (scene, bar):
            if not os.path.exists(p):
                raise SystemExit(f"missing {os.path.relpath(p, ROOT)}: run its test first (tests/marketing/README.md)")
        shutil.copyfile(scene, os.path.join(out, "clean", name + ".png"))
        stack(scene, bar, os.path.join(out, name + ".png"))
        lines.append(f"{name}.png\n  {headline}\n  {subline}\n")
        print(f"{name}.png")
    with open(os.path.join(out, "captions.txt"), "w", encoding="utf-8") as f:
        f.write("SuuUI screenshots: each image's headline and the line under it.\n\n")
        f.write("\n".join(lines))
    print(f"wrote {len(lines)} images to {out}")


if __name__ == "__main__":
    main()
