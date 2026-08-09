-- Modern theme: darker surfaces, higher contrast accent, quicker animations.
-- Same two-tier structure as Default: primitives first, semantics as aliases.
SuuUI.Theme:RegisterBuiltin("Modern", {
    -- Tier 1: neutral scale
    colorGray950     = {0.04, 0.04, 0.06, 1.00},
    colorGray900     = {0.06, 0.06, 0.08, 1.00},
    colorGray850     = {0.09, 0.09, 0.12, 1.00},
    colorGray800     = {0.13, 0.13, 0.17, 1.00},
    colorGray750     = {0.16, 0.16, 0.22, 1.00},
    colorGray700     = {0.18, 0.18, 0.22, 1.00},
    colorGray600     = {0.32, 0.32, 0.36, 1.00},
    colorGray400     = {0.50, 0.52, 0.58, 1.00},
    colorGray100     = {0.95, 0.95, 0.95, 1.00},

    -- Tier 1: hues
    colorBlue400     = {0.30, 0.60, 1.00, 1.00},
    colorBlue500     = {0.20, 0.48, 0.92, 1.00},
    colorGreen400    = {0.22, 0.85, 0.45, 1.00},
    -- See Themes/Default.lua: health's own green, brighter here to match this theme's
    -- higher contrast. Only visible while colorUseClassColors is off, or on a unit whose
    -- class is unknown.
    colorGreen500    = {0.24, 0.84, 0.36, 1.00},
    colorRed400      = {0.95, 0.28, 0.28, 1.00},
    colorYellow400   = {1.00, 0.84, 0.22, 1.00},

    opacityPanel     = 0.97,
    opacityOverlay   = 0.45,
    -- See Themes/Default.lua: the empty part of a frameless bar.
    opacityBarTrack  = 0.60,
    -- Edit mode's drag overlay. Low enough to read the frame underneath while dragging it.
    opacityEditOverlay = 0.20,
    -- See Themes/Default.lua: how far a disabled control fades.
    opacityDisabled  = 0.40,

    -- Tier 2: surfaces
    colorBg          = { ref = "colorGray900", alpha = "opacityPanel" },
    colorBgAlt       = { ref = "colorGray850", alpha = "opacityPanel" },
    colorBgHover     = { ref = "colorGray800", alpha = "opacityPanel" },
    colorBgActive    = { ref = "colorGray750", alpha = "opacityPanel" },
    colorBgPressed   = { ref = "colorGray750", alpha = "opacityPanel" },

    -- Overlays. A modal's scrim dims the screen behind it; edit mode's drag surface takes
    -- the accent hue so "you can move this" reads the same as every other affordance.
    colorOverlay     = { ref = "colorGray950", alpha = "opacityOverlay" },
    colorEditOverlay = { ref = "colorAccent",  alpha = "opacityEditOverlay" },
    -- A handle drawn ON TOP of arbitrary colour (a picker thumb over a hue bar), so it
    -- tracks the lightest neutral rather than the text colour it would otherwise borrow.
    colorMarker      = { ref = "colorGray100", alpha = 0.90 },
    -- See Themes/Default.lua: the empty part of a frameless bar, over the game world.
    colorBarTrack    = { ref = "colorGray950", alpha = "opacityBarTrack" },
    -- See Themes/Default.lua: the uninterruptible-cast outline.
    colorShield      = "colorGray400",
    -- See Themes/Default.lua: a unit's health when it is not class-coloured.
    colorHealth      = "colorGreen500",

    -- Tier 2: intent
    colorAccent      = "colorBlue400",
    colorAccentHover = "colorBlue500",
    colorSuccess     = "colorGreen400",
    colorDanger      = "colorRed400",
    colorWarning     = "colorYellow400",

    -- See Themes/Default.lua. On here: this is the shipped active theme, and class
    -- colouring is the modern convention for a health bar. Turn it off to fall back to
    -- colorHealth.
    colorUseClassColors = true,

    -- Tier 2: content
    colorText         = "colorGray100",
    colorTextMuted    = "colorGray400",
    colorTextDisabled = "colorGray600",
    colorBorder       = "colorGray700",
    colorBorderFocus  = "colorAccent",

    fontSizeSm          = 11,
    fontSizeMd          = 13,
    fontSizeLg          = 15,
    fontSizeXl          = 18,
    -- A font name, not a path: SuuUI.Fonts resolves it. See Themes/Default.lua.
    fontFamilyMain      = "Friz Quadrata TT",

    spaceXxs         = 2,
    spaceXs          = 4,
    spaceSm          = 8,
    spaceMd          = 12,
    spaceLg          = 16,
    spaceXl          = 24,

    sizeControlSm    = 18,
    sizeControlMd    = 22,
    sizeControlLg    = 24,
    sizeRow          = 28,

    sizeNavRow       = 32,
    sizeTitleBar     = 26,
    sizeToggleW      = 36,
    sizeIcon         = 16,
    sizeScrollbar    = 8,

    borderWidth      = 1,

    animFast         = 0.10,
    animMid          = 0.20,
    animSlow         = 0.35,
    animBarFill      = 0.22,
    animPopScale     = 1.06,
})
