#!/usr/bin/env python3
"""Build Figtree Tabular: Figtree with its tabular digits as the default digits.

WoW renders fonts without OpenType features, so Figtree's `tnum` feature never
applies in game and timers jitter as their digits change width. This copies a
Figtree weight, points 0-9 in the character map at the feature's tabular
glyphs (zero.tf ... nine.tf), and renames the family so it can't be mistaken
for the original. Figtree's licence (OFL 1.1) names no Reserved Font Name, so
a modified version may keep "Figtree" in its name.

Usage (needs fontTools: pip install fonttools):
    python3 tools/make_tabular_font.py Media/Fonts/Figtree-Bold.ttf Media/Fonts/FigtreeTabular-Bold.ttf
"""

import sys

from fontTools.ttLib import TTFont

DIGITS = "0123456789"


def tnum_mapping(font):
    """The single-substitution mapping of the font's first `tnum` lookup."""
    gsub = font["GSUB"].table
    for record in gsub.FeatureList.FeatureRecord:
        if record.FeatureTag != "tnum":
            continue
        for index in record.Feature.LookupListIndex:
            for sub in gsub.LookupList.Lookup[index].SubTable:
                sub = getattr(sub, "ExtSubTable", sub)
                mapping = getattr(sub, "mapping", None)
                if mapping:
                    return mapping
    raise SystemExit("no tnum single substitution found")


def rename(font, suffix):
    """Insert `suffix` after "Figtree" in every family and full name."""
    for record in font["name"].names:
        if record.nameID in (1, 3, 4, 6, 16):
            text = record.toUnicode()
            joiner = "" if record.nameID == 6 else " "
            record.string = text.replace("Figtree", "Figtree" + joiner + suffix, 1)


def main(src, dst):
    font = TTFont(src)
    mapping = tnum_mapping(font)
    for table in font["cmap"].tables:
        if not table.isUnicode():
            continue
        for ch in DIGITS:
            glyph = table.cmap.get(ord(ch))
            if glyph is not None and glyph in mapping:
                table.cmap[ord(ch)] = mapping[glyph]
    rename(font, "Tabular")
    font.save(dst)

    check = TTFont(dst)
    widths = {check["hmtx"][check.getBestCmap()[ord(c)]][0] for c in DIGITS}
    if len(widths) != 1:
        raise SystemExit("digits still differ in width: %s" % sorted(widths))
    print("%s: digits %s, all %d units wide" % (dst, DIGITS, widths.pop()))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
