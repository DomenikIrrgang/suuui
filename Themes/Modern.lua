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
    -- See Default: MAGENTA (near-zero green, red at least as strong as blue), not a violet. A
    -- blue-dominant purple reads as the warlock class colour rather than as experience. Modern's is a
    -- touch brighter, like its blues.
    colorMagenta400  = {0.84, 0.16, 0.78, 1.00},
    colorMagenta500  = {0.72, 0.11, 0.66, 1.00},
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
    -- How faint a StatusBar's SECONDARY fill is, as a multiple of the main fill's own alpha. Rested
    -- experience is the case: visible enough to read as reach, faint enough not to compete with actual
    -- progress. A multiplier rather than a colour, because the ghost derives from whatever the bar's
    -- fill is -- XP blue on one watch bar, a faction colour on the other.
    opacityBarGhost  = 0.35,
    -- Edit mode's drag overlay. Low enough to read the frame underneath while dragging it.
    opacityEditOverlay = 0.20,
    -- A SELECTED SEGMENT'S WASH: the accent at low alpha, so a chosen segment reads as chosen
    -- without becoming a second button. Its own token rather than a reuse of
    -- opacityEditOverlay, which is the same value today by coincidence -- retinting edit mode
    -- must not retint every segmented control in the addon.
    opacityAccentSubtle = 0.18,
    -- HOW STRONG AN INTENT WASH IS behind a whole line of text -- the amber "this is a cached
    -- snapshot" strip. Its own token rather than sharing opacityAccentSubtle: one is a selected
    -- control, the other is a standing warning, and they want tuning separately.
    opacityWarningWash = 0.18,

    -- See Themes/Default.lua: a Chip's wash and ring. Slightly stronger here to match this
    -- theme's higher contrast.
    opacityRailIdle   = 0.50,
    -- How dark the shadow under text that sits over the GAME WORLD is. A frameless log
    -- has no panel behind it, so this is what separates a glyph from terrain.
    opacityTextShadow = 0.90,
    opacityChipBorder = 0.45,
    -- The resting keybind wash. See Themes/Default.lua for why it is its own token: it pairs with
    -- opacityEditOverlay (0.20, the HOVERED wash) and the two must stay clearly apart.
    opacityKeybindRest = 0.08,
    -- See Themes/Default.lua: how far a disabled control fades.
    opacityDisabled  = 0.40,
    -- Edit mode grid line visibility. Very faint so lines stay out of the way.
    opacityGrid      = 0.15,
    -- opacityDimmed: how far a cell RECEDES when it does not match a search. Its own token rather than
    -- a reuse of opacityGrid, which is the EDIT-MODE grid overlay -- sharing that one meant a player
    -- nudging the grid's opacity silently changed how search dimming looks, and a user theme that had
    -- done so made search appear not to work at all. Not opacityDisabled either: a non-matching item is
    -- not inert, it is just not the one you asked for.
    opacityDimmed    = 0.16,
    -- Smart guide lines (element alignment) are brighter than the base grid.
    opacityGuide     = 0.40,
    -- See Themes/Default.lua: the action bar plate's dense edge, open edge and lit top
    -- hairline. Denser here than in Default, matching this theme's higher contrast.
    opacityGlass      = 0.85,
    opacityGlassFade  = 0.30,
    opacityGlassSheen = 0.10,

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
    -- The wash behind a selected segment (Components/SegmentedControl.lua). The concept names this
    -- colour itself, as `--accent-subtle`.
    colorAccentSubtle = { ref = "colorAccent", alpha = "opacityAccentSubtle" },
    -- The wash behind a warning STRIP, as opposed to warning-coloured text on nothing.
    colorWarningSubtle = { ref = "colorWarning", alpha = "opacityWarningWash" },
    -- Keybind mode's washes. See Themes/Default.lua for the reasoning, including why the HOVERED
    -- state reuses colorEditOverlay instead of declaring a fifth token.
    colorKeybindRest = { ref = "colorAccent", alpha = "opacityKeybindRest" },
    colorSuccessSubtle = { ref = "colorSuccess", alpha = "opacityWarningWash" },
    colorDangerSubtle  = { ref = "colorDanger",  alpha = "opacityWarningWash" },
    -- Edit mode grid lines: the accent colour at grid opacity.
    colorGrid        = { ref = "colorAccent",  alpha = "opacityGrid" },
    -- Smart guides: brighter accent for element-to-element alignment lines.
    colorGuide       = { ref = "colorAccent", alpha = "opacityGuide" },
    -- See Themes/Default.lua: locked frame overlay.
    colorEditOverlayLocked = { ref = "colorWarning", alpha = "opacityEditOverlay" },
    -- See Themes/Default.lua: selected frame overlay.
    colorEditOverlaySelected = { ref = "colorAccent", alpha = "opacityOverlay" },
    -- A handle drawn ON TOP of arbitrary colour (a picker thumb over a hue bar), so it
    -- tracks the lightest neutral rather than the text colour it would otherwise borrow.
    colorMarker      = { ref = "colorGray100", alpha = 0.90 },
    -- See Themes/Default.lua: the empty part of a frameless bar, over the game world.
    colorBarTrack    = { ref = "colorGray950", alpha = "opacityBarTrack" },
    -- See Themes/Default.lua: the action bar plate. Its own tokens rather than a reuse of
    -- colorBarTrack, and the sheen refs the lightest neutral because it is a highlight.
    colorGlass       = { ref = "colorGray950", alpha = "opacityGlass" },
    colorGlassFade   = { ref = "colorGray950", alpha = "opacityGlassFade" },
    colorGlassSheen  = { ref = "colorGray100", alpha = "opacityGlassSheen" },
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

    -- See Default: purple is progress, blue is rested, and they are separate tokens because those
    -- colours carry meaning to the player rather than being decoration.
    colorXp          = "colorMagenta400",
    colorXpRested    = { ref = "colorBlue400", alpha = 0.55 },

    -- See Themes/Default.lua. On here: this is the shipped active theme, and class
    -- colouring is the modern convention for a health bar. Turn it off to fall back to
    -- colorHealth.
    colorUseClassColors = true,

    -- Tier 2: content
    colorText         = "colorGray100",
    colorTextMuted    = "colorGray400",
    colorTextDisabled = "colorGray600",
    colorBorder       = "colorGray700",
    -- See Default.lua: an icon's ring has to read against spell art, not against the
    -- game world, so it is brighter than a panel's edge and carries its own semantic.
    colorBorderIcon   = "colorGray400",
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
    -- See Themes/Default.lua: the open accordion's accent rail.
    sizeRail         = 2,

    borderWidth      = 1,
    -- See Themes/Default.lua: the rounded-surface corner radius.
    borderRadius     = 3,

    animFast         = 0.10,
    animMid          = 0.20,
    animSlow         = 0.35,
    animBarFill      = 0.22,
    animPopScale     = 1.06,
})
