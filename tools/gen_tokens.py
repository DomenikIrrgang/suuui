#!/usr/bin/env python3
"""Generate Core/Tokens.wowlua from Design/tokens.json.

Design/tokens.json is a copy of the SuuUI design system's tokens.json
(https://claude.ai/artifact/NcdJv21GMnN9gaQ5mF1oSw). To update the addon after
the design changes: replace that copy, then run

    python3 tools/gen_tokens.py

from the addon folder. Standard library only.

What it writes, a wowlua module exporting `tokens` (typed: each family a
record with a field per token, so a token read by name is checked):
  color     name -> { r, g, b, a, hex = "rrggbb" }, 0-1 components
  space, size, radius
            name -> number in px at the design's reference scale
            (radius-round is the string "50%")
  opacity   name -> number
  duration  name -> seconds
  easing    name -> { smoothing = AnimationGroup smoothing, bezier = { x1, y1, x2, y2 } }
  shadow    name -> list of { x, y, blur, spread, inset, color = { r, g, b, a } }
  type      name -> { family, file, size, lineHeight, weight, letterSpacing (em), tabular }
  texture   name -> a texture file (SuuUI's own, not the design system's:
            TEXTURES below), which themes can replace
  glyph     name -> an icon's file (Media/Textures/Glyphs/<name>.tga), which
            themes can replace
  order     family -> names in the design's order, for listings
  usage     name -> the design's usage note
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "Design", "tokens.json")
DST = os.path.join(ROOT, "src", "Core", "Tokens.wowlua")

FONT_DIR = "Interface\\AddOns\\SuuUI\\Media\\Fonts\\"

# (family, weight, tabular) -> file in Media/Fonts. The design names its
# faces by family and weight; WoW needs one static file per weight.
FONT_FILES = {
    ("display", 400, False): "MarcellusSC-Regular.ttf",
    ("sans", 400, False): "Figtree-Regular.ttf",
    ("sans", 500, False): "Figtree-Medium.ttf",
    ("sans", 600, False): "Figtree-SemiBold.ttf",
    ("sans", 700, False): "Figtree-Bold.ttf",
    ("sans", 700, True): "FigtreeTabular-Bold.ttf",
}

# Styles the design sets "with tabular figures" (README: Typography).
TABULAR = {"numeric", "micro"}

# SuuUI's own colours, not (yet) in the design system's tokens.json: the
# map marks' eight symbols (added with the map marks, 5d12037). They follow
# the design's colours in Tokens.wowlua and take part in themes like them.
EXTRA_COLORS = [
    ("mark-star", "#fff27a"), ("mark-circle", "#ff8c00"), ("mark-diamond", "#e25cf5"),
    ("mark-triangle", "#2ecc71"), ("mark-moon", "#b5c9f0"), ("mark-square", "#1e5bff"),
    ("mark-cross", "#f0365a"), ("mark-skull", "#ffffff"),
    # every dark overlay (asked 2026-11-12: the modal shade, the vignettes and
    # floors, the minimap's shadow, the aura timers' shade…): each keeps its
    # own alpha, the colour comes from here
    ("shade", "#000000"),
]

# SuuUI's own texture tokens (asked 2026-11-12: every texture the unit frames
# and nameplates draw comes from the theme): the files a theme can replace
# with its own (Core/Themes.wowlua, `textures`). They aren't in the design
# system's tokens.json, which has no textures; they follow its shadows in
# Tokens.wowlua and take part in themes like colours. (name, file, usage)
MEDIA = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
WHITE = "Interface\\Buttons\\WHITE8X8"
TEXTURES = [
    ("health-bar", WHITE,
     "Health fill of unit frames and nameplates, stretched along the bar; also the low-health fill, the damage ghost "
     "and incoming heals. Coloured by unit-fill and the others through its vertex colour: a white or light texture."),
    ("power-bar", WHITE,
     "The power line on unit frames and the resource bar (its spend and low-power fills, combo points and the druid's "
     "mana line too), stretched; coloured like health-bar."),
    ("cast-bar", WHITE, "The fill of cast bars (unit frames' and nameplates'), stretched; coloured like health-bar."),
    ("absorb", MEDIA + "Hatch.tga",
     "Absorb-shield segment on the health bar: tiled (repeats at its own size), in ward-absorb."),
    ("tapped", MEDIA + "Hatch.tga",
     "The stripes over a tagged mob's health fill (unit frames and nameplates): tiled, in unit-fill-tapped-stripe."),
    ("aura-drain", WHITE, "The duration bar along an aura icon's bottom edge, stretched."),
    ("glow", MEDIA + "Soft.tga",
     "Soft glows (the glow- shadows: aggro, warded, casts, aura highlights), cut as a 3x3 slice: the corners are "
     "its outer quarters, the middle stretches. White, coloured by the shadow's colour."),
    ("role-tank", MEDIA + "RoleTank.tga", "Role icon of a tank in a unit frame's name row, in ink."),
    ("role-healer", MEDIA + "RoleHealer.tga", "Role icon of a healer in a unit frame's name row, in ink."),
    ("role-damage", MEDIA + "RoleDamage.tga", "Role icon of a damage dealer in a unit frame's name row, in ink-muted."),
    ("raid-markers", "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
     "Raid target markers on unit frames and nameplates: the game's sheet, eight markers in a 4x4 grid of equal cells "
     "(star, circle, diamond, triangle on the first row; moon, square, cross, skull on the second)."),
    ("cast-lock", "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
     "The lock on a cast that can't be interrupted (cast bars and nameplates), desaturated, in ink."),
    ("combat", MEDIA + "Glyphs\\swords.tga", "The combat sign on the player frame: crossed swords, in gilt-text."),
    # (asked 2026-11-12: the rest of the UI's plain fills and round shapes)
    ("bar", WHITE,
     "Plain bar fills outside the unit frames: XP and reputation, progress and skill bars, the swing timer, class "
     "bars and the totem drain, damage and threat meter bars, the weapon-enchant drain, the tooltip's health bar; "
     "stretched, coloured through its vertex colour: a white or light texture."),
    ("swing-delay", MEDIA + "Hatch.tga", "The swing timer's delay hatch over a pushed-back swing: tiled, in amber."),
    ("circle-fill", MEDIA + "CircleFill.tga",
     "A filled disc: map pins, the minimap's face and its N, the micro menu's pill caps, the rested sign, mark and "
     "notification discs. White, coloured by its token."),
    ("circle-soft", MEDIA + "CircleSoft.tga",
     "A soft round glow: pin glows, the minimap's shadow, the NPC dialogue's and the model stage's light. White."),
    ("circle-band", MEDIA + "CircleBand.tga", "A thick ring: the minimap's inner band, group finder and notification rims."),
    ("circle-edge", MEDIA + "CircleEdge.tga", "A thin ring: the minimap's edge and its N's ring."),
    ("circle-dash", MEDIA + "CircleDash.tga", "A dashed ring: waypoints and unknown flight points on the maps."),
    ("ring-arc-2", MEDIA + "RingArc2.tga", "A half ring, turned for each part: a map pin split between two colours."),
    ("ring-arc-3", MEDIA + "RingArc3.tga", "A third of a ring, turned for each part: a pin split between three colours."),
    ("ring-arc-4", MEDIA + "RingArc4.tga", "A quarter ring, turned for each part: a pin split between four colours."),
    ("check", "Interface\\Buttons\\UI-CheckBox-Check",
     "The tick in a checkbox (the game's, desaturated), in on-signal."),
    ("setting-reset", "Interface\\Buttons\\UI-RefreshButton",
     "The reset arrow after a changed setting (the game's), desaturated, in ink-muted."),
    ("setting-lock", "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
     "The lock on a setting that can't be changed now (the game's), desaturated, in ink-muted."),
]

# SuuUI's glyphs (asked 2026-11-12: a theme replaces any icon by its name):
# every file in Media/Textures/Glyphs, by its name without .tga. White art,
# coloured by a colour token where it's drawn.
GLYPH_DIR = os.path.join(ROOT, "Media", "Textures", "Glyphs")

# README, In-game implementation: easing -> AnimationGroup smoothing.
SMOOTHING = {"ease-out": "OUT", "ease-in": "IN", "ease-in-out": "IN_OUT", "ease-linear": "NONE"}


# --- Parsing -----------------------------------------------------------------

def parse_color(value, colors):
    """'#rgb', '#rrggbb', '#rrggbbaa', 'rgba(r, g, b, a)', 'rgb(...)' or '{alias}'."""
    if isinstance(value, dict):  # per-theme values: the first theme is the in-game one
        value = next(iter(value.values()))
    value = value.strip()
    alias = re.fullmatch(r"\{(.+)\}", value)
    if alias:
        return colors[alias.group(1)]
    if value.startswith("#"):
        h = value[1:]
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
        return r / 255, g / 255, b / 255, a
    fn = re.fullmatch(r"rgba?\(([^)]*)\)", value)
    if fn:
        parts = [p.strip() for p in fn.group(1).replace("/", ",").split(",")]
        r, g, b = (float(p) / 255 for p in parts[:3])
        a = float(parts[3]) if len(parts) > 3 else 1.0
        return r, g, b, a
    raise ValueError("unsupported colour: %r" % value)


def px(value):
    if isinstance(value, (int, float)):
        return value
    m = re.fullmatch(r"(-?[\d.]+)px", value.strip())
    if not m:
        raise ValueError("not a px length: %r" % value)
    return float(m.group(1))


def em(value):
    m = re.fullmatch(r"(-?[\d.]+)em", value.strip())
    if not m:
        raise ValueError("not an em length: %r" % value)
    return float(m.group(1))


def parse_shadow(value, colors):
    layers = []
    for part in re.split(r",(?![^(]*\))", value):
        tokens = part.split()
        inset = tokens[0] == "inset"
        if inset:
            tokens = tokens[1:]
        lengths = [px(t) if t != "0" else 0 for t in tokens[:-1]]
        lengths += [0] * (4 - len(lengths))
        layers.append({
            "x": lengths[0], "y": lengths[1], "blur": lengths[2], "spread": lengths[3],
            "inset": inset, "color": parse_color(tokens[-1], colors),
        })
    return layers


# --- Lua output --------------------------------------------------------------

def num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if float(v).is_integer():
        return str(int(v))
    return ("%.4f" % v).rstrip("0").rstrip(".")


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_color(c, hexstr=None):
    body = ", ".join(num(x) for x in c)
    if hexstr:
        body += ", hex = " + lua_str(hexstr)
    return "{ " + body + " }"


def hex_of(c):
    return "%02x%02x%02x" % tuple(round(x * 255) for x in c[:3])


def main():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)

    out = []
    w = out.append
    w("-- Core/Tokens.wowlua")
    w("-- GENERATED by tools/gen_tokens.py from Design/tokens.json (%s tokens v%s). Do not edit;"
      % (data.get("name", "?"), data.get("version", "?")))
    w("-- change the design system, copy its tokens.json to Design/ and regenerate.")
    w("")
    w("--- A colour: r, g, b, a (0-1) and its hex. Themes and colour vision change")
    w("--- the components in place, so every table holding a token sees the change.")
    w("export type Color = number[] & { hex: string }")
    w("export type Easing = { smoothing: string, bezier: number[]? }")
    w("export type ShadowLayer = { x: number, y: number, blur: number, spread: number, inset: boolean, color: number[] }")
    w("export type TextStyle = { family: string, file: string, size: number, lineHeight: number, weight: number, letterSpacing: number, tabular: boolean, sample: string }")
    w("")

    usage = []
    order = {}
    families = []  # (key, type name, value type)

    def record(key, typename, valuetype, entries):
        """entries: [(name, lua value)]"""
        families.append((key, typename))
        w("export type %s = {" % typename)
        for name, _ in entries:
            w("    [%s]: %s," % (lua_str(name), valuetype))
        w("}")
        if key == "color":
            w("-- A colour's name.")
            w("export type ColorToken = keyof Colors")
            w("")
        w("local %s: %s = {" % (key, typename))
        for name, value in entries:
            w("    [%s] = %s," % (lua_str(name), value))
        w("}")
        w("")
        order[key] = [n for n, _ in entries]

    # Colours, resolving aliases in order.
    colors = {}
    entries = []
    for tok in data["color"]["tokens"]:
        c = parse_color(tok["value"], colors)
        colors[tok["name"]] = c
        usage.append((tok["name"], tok.get("usage")))
        entries.append((tok["name"], lua_color(c, hex_of(c))))
    for name, value in EXTRA_COLORS:
        c = parse_color(value, colors)
        colors[name] = c
        entries.append((name, lua_color(c, hex_of(c))))
    record("color", "Colors", "Color", entries)

    def simple(family, key, typename, valuetype, convert):
        entries = []
        for tok in data[family]["tokens"]:
            usage.append((tok["name"], tok.get("usage")))
            entries.append((tok["name"], convert(tok)))
        record(key, typename, valuetype, entries)

    simple("spacing", "space", "Spaces", "number", lambda t: num(px(t["value"])))
    simple("size", "size", "Sizes", "number", lambda t: num(px(t["value"])))
    simple("radius", "radius", "Radii", "number | string",
           lambda t: lua_str(t["value"]) if str(t["value"]).endswith("%") else num(px(t["value"])))
    simple("opacity", "opacity", "Opacities", "number", lambda t: num(float(t["value"])))

    def duration(t):
        m = re.fullmatch(r"([\d.]+)(ms|s)", t["value"].strip())
        seconds = float(m.group(1)) / (1000 if m.group(2) == "ms" else 1)
        return num(seconds)
    simple("duration", "duration", "Durations", "number", duration)

    def easing(t):
        bez = re.fullmatch(r"cubic-bezier\(([^)]*)\)", t["value"].strip())
        curve = "{ " + ", ".join(num(float(x)) for x in bez.group(1).split(",")) + " }" if bez else "nil"
        return "{ smoothing = %s, bezier = %s }" % (lua_str(SMOOTHING[t["name"]]), curve)
    simple("easing", "easing", "Easings", "Easing", easing)

    def shadow(t):
        layers = []
        for l in parse_shadow(t["value"], colors):
            layers.append("{ x = %s, y = %s, blur = %s, spread = %s, inset = %s, color = %s }" % (
                num(l["x"]), num(l["y"]), num(l["blur"]), num(l["spread"]), num(l["inset"]),
                lua_color(l["color"])))
        return "{ " + ", ".join(layers) + " }"
    simple("shadow", "shadow", "Shadows", "ShadowLayer[]", shadow)

    entries = []
    for name, file, note in TEXTURES:
        usage.append((name, note))
        entries.append((name, lua_str(file)))
    record("texture", "Textures", "string", entries)

    entries = []
    glyphs = sorted(f[:-4] for f in os.listdir(GLYPH_DIR) if f.endswith(".tga"))
    for name in glyphs:
        entries.append((name, lua_str(MEDIA + "Glyphs\\" + name + ".tga")))
    record("glyph", "Glyphs", "string", entries)

    # Text styles.
    entries = []
    for group in data["type"]["groups"]:
        family = group["family"]
        for s in group["styles"]:
            weight = int(str(s.get("fontWeight", 400)).split()[0])
            tabular = s["name"] in TABULAR
            file = FONT_FILES.get((family, weight, tabular))
            if not file:
                sys.exit("no font file for %s %d%s (style %s)"
                         % (family, weight, " tabular" if tabular else "", s["name"]))
            usage.append((s["name"], s.get("usage")))
            entries.append((s["name"], "{ family = %s, file = %s, size = %s, lineHeight = %s, weight = %d, letterSpacing = %s, tabular = %s, sample = %s }" % (
                lua_str(family), lua_str(FONT_DIR + file),
                num(px(s["fontSize"])), num(px(s["lineHeight"])), weight,
                num(em(s["letterSpacing"])) if s.get("letterSpacing") else "0",
                num(tabular), lua_str(s.get("sample", s["name"])))))
    record("type", "TextStyles", "TextStyle", entries)
    names = order["type"]

    w("local usage: { [string]: string } = {}")
    for name, note in usage:
        if note:
            # (the fonts have no arrow: the game draws an empty box, 830e9b0e)
            w("usage[%s] = %s" % (lua_str(name), lua_str(note.replace(" ↔ ", " and "))))
    w("")

    w("export type Tokens = {")
    w("    version: number,")
    for key, typename in families:
        w("    %s: %s," % (key, typename))
    w("    order: { [string]: string[] },")
    w("    usage: { [string]: string },")
    w("    --- the colour vision presets (Core/VisionPresets.wowlua)")
    w("    vision?: { [string]: { [string]: Color } },")
    w("}")
    w("")
    w("export const tokens = {")
    w("    version = %s," % num(data.get("version", 0)))
    for key, _ in families:
        w("    %s = %s," % (key, key))
    w("    order = {")
    for key, _ in families:
        w("        %s = { %s }," % (key, ", ".join(lua_str(n) for n in order[key])))
    w("    },")
    w("    usage = usage,")
    w("} :: Tokens")

    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %s: %d colours, %d text styles, %d textures, %d glyphs"
          % (os.path.relpath(DST, ROOT), len(colors), len(names), len(TEXTURES), len(glyphs)))


if __name__ == "__main__":
    main()
