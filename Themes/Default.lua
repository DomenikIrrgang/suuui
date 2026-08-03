-- Default theme: dark, moderate contrast.
-- Tier 1 holds primitives (raw values, named for what they are). Tier 2 holds
-- semantics (named for what they are used for) as aliases onto tier 1. Components
-- only ever reference tier 2, so retinting the UI is a tier 1 edit.
SuuUI.Theme:RegisterBuiltin("Default", {
    -- Tier 1: neutral scale (low number = light, high = dark)
    colorGray950     = {0.05, 0.05, 0.07, 1.00},
    colorGray900     = {0.08, 0.08, 0.10, 1.00},
    colorGray850     = {0.11, 0.11, 0.14, 1.00},
    colorGray800     = {0.15, 0.15, 0.19, 1.00},
    colorGray750     = {0.18, 0.18, 0.23, 1.00},
    colorGray700     = {0.20, 0.20, 0.24, 1.00},
    colorGray600     = {0.35, 0.35, 0.38, 1.00},
    colorGray400     = {0.55, 0.55, 0.60, 1.00},
    colorGray100     = {0.92, 0.92, 0.92, 1.00},

    -- Tier 1: hues
    colorBlue400     = {0.25, 0.55, 1.00, 1.00},
    colorBlue500     = {0.18, 0.44, 0.90, 1.00},
    colorGreen400    = {0.20, 0.80, 0.40, 1.00},
    colorRed400      = {0.90, 0.25, 0.25, 1.00},
    colorYellow400   = {0.95, 0.80, 0.20, 1.00},

    -- Opacity, applied to the semantics below via { ref, alpha }
    opacityPanel     = 0.95,
    opacityOverlay   = 0.35,

    -- Tier 2: surfaces. { ref, alpha } takes the primitive's RGB with a token alpha,
    -- so panel translucency is one slider instead of four colour edits.
    colorBg          = { ref = "colorGray900", alpha = "opacityPanel" },
    colorBgAlt       = { ref = "colorGray850", alpha = "opacityPanel" },
    colorBgHover     = { ref = "colorGray800", alpha = "opacityPanel" },
    colorBgActive    = { ref = "colorGray750", alpha = "opacityPanel" },
    colorBgPressed   = { ref = "colorGray750", alpha = "opacityPanel" },
    colorBgDisabled  = { ref = "colorGray850", alpha = "opacityPanel" },

    -- Tier 2: intent
    colorAccent      = "colorBlue400",
    colorAccentHover = "colorBlue500",
    colorSuccess     = "colorGreen400",
    colorDanger      = "colorRed400",
    colorWarning     = "colorYellow400",

    -- Tier 2: content
    colorText         = "colorGray100",
    colorTextMuted    = "colorGray400",
    colorTextDisabled = "colorGray600",
    colorBorder       = "colorGray700",
    colorBorderFocus  = "colorAccent",

    -- Typography
    fontSizeSm          = 11,
    fontSizeMd          = 13,
    fontSizeLg          = 15,
    fontSizeXl          = 18,
    -- A font name, not a path: SuuUI.Fonts resolves it, and falls back to a loadable
    -- face if it ever goes missing. A literal path still works here.
    fontFamilyMain      = "Friz Quadrata TT",

    -- Spacing scale, used for both gaps and padding
    spaceXs          = 4,
    spaceSm          = 8,
    spaceMd          = 12,
    spaceLg          = 16,
    spaceXl          = 24,

    -- Control sizes. Text-bearing controls treat these as floors and grow with the
    -- font size tokens; see Theme:GetControlHeight.
    sizeControlSm    = 18,
    sizeControlMd    = 22,
    sizeControlLg    = 24,
    sizeRow          = 28,

    -- Component sizes
    sizeNavRow       = 32,
    sizeTitleBar     = 26,
    sizeToggleW      = 36,
    sizeIcon         = 16,
    sizeScrollbar    = 8,

    borderWidth      = 1,

    animFast         = 0.12,
    animMid          = 0.22,
    animSlow         = 0.38,
})
