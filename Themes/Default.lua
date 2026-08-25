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
    -- MAGENTA, not purple, and the name matters: "purple" is how the first attempt drifted into a
    -- violet ({0.64, 0.29, 0.86}) that reads as the WARLOCK class colour, which is a blue-dominant
    -- lavender ({0.58, 0.51, 0.79}).
    --
    -- Experience is a saturated fuchsia -- near-zero GREEN, and red at least as strong as blue. The
    -- client's own bar is {0.58, 0.00, 0.55}; this keeps that structure and lifts the brightness,
    -- because Blizzard's value goes muddy on a dark surface. Blue-dominance is what makes a purple look
    -- like a class colour, so it is the thing to avoid here.
    colorMagenta400  = {0.78, 0.12, 0.72, 1.00},
    colorMagenta500  = {0.66, 0.08, 0.61, 1.00},
    colorGreen400    = {0.20, 0.80, 0.40, 1.00},
    -- Health's own green rather than a reuse of Success: they are the same hue family but
    -- answer to different things, and a user retinting "Success" to orange should not turn
    -- their health bar orange.
    colorGreen500    = {0.22, 0.78, 0.32, 1.00},
    colorRed400      = {0.90, 0.25, 0.25, 1.00},
    colorYellow400   = {0.95, 0.80, 0.20, 1.00},

    -- Opacity, applied to the semantics below via { ref, alpha }
    opacityPanel     = 0.95,
    opacityOverlay   = 0.35,
    -- How visible the empty part of a frameless bar is. It is the only surface a unit
    -- frame bar has, so at 0 rage this is the whole widget: too low and the bar vanishes
    -- against the game world.
    opacityBarTrack  = 0.60,
    -- How faint a StatusBar's SECONDARY fill is, as a multiple of the main fill's own alpha. Rested
    -- experience is the case: visible enough to read as reach, faint enough not to compete with actual
    -- progress. A multiplier rather than a colour, because the ghost derives from whatever the bar's
    -- fill is -- XP blue on one watch bar, a faction colour on the other.
    opacityBarGhost  = 0.35,
    -- Edit mode's drag overlay. Low enough to read the frame underneath while dragging it.
    opacityEditOverlay = 0.20,
    -- How far a disabled control fades. It is the ONLY signal that a control is inert, so
    -- it has to read at a glance on every widget, in every value state; low enough to be
    -- unmistakable, high enough that the label is still readable.
    opacityDisabled  = 0.40,
    -- Edit mode grid lines: visible enough to guide placement, faint enough not to
    -- distract from the frames being moved.
    opacityGrid      = 0.15,
    -- opacityDimmed: how far a cell RECEDES when it does not match a search. Its own token rather than
    -- a reuse of opacityGrid, which is the EDIT-MODE grid overlay -- sharing that one meant a player
    -- nudging the grid's opacity silently changed how search dimming looks, and a user theme that had
    -- done so made search appear not to work at all. Not opacityDisabled either: a non-matching item is
    -- not inert, it is just not the one you asked for.
    opacityDimmed    = 0.35,
    -- Smart guide lines (element-to-element alignment) are brighter than the grid so
    -- they stand out as contextual feedback during a drag.
    opacityGuide     = 0.40,
    -- The glass plate behind an action bar: dense along its top edge, fading out towards
    -- the bottom, with a lit hairline on the top edge. Three numbers rather than one
    -- because the plate's whole legibility comes from the DIFFERENCE between its ends — a
    -- single opacity makes it a flat panel, which is the look it exists to avoid.
    opacityGlass      = 0.80,
    opacityGlassFade  = 0.30,
    -- The lit top edge. Deliberately very low: it reads as a catch of light, and much
    -- above 0.15 it stops being an edge and becomes a white line drawn on the plate.
    opacityGlassSheen = 0.10,

    -- Tier 2: surfaces. { ref, alpha } takes the primitive's RGB with a token alpha,
    -- so panel translucency is one slider instead of four colour edits.
    colorBg          = { ref = "colorGray900", alpha = "opacityPanel" },
    colorBgAlt       = { ref = "colorGray850", alpha = "opacityPanel" },
    colorBgHover     = { ref = "colorGray800", alpha = "opacityPanel" },
    colorBgActive    = { ref = "colorGray750", alpha = "opacityPanel" },
    colorBgPressed   = { ref = "colorGray750", alpha = "opacityPanel" },

    -- Overlays. A modal's scrim dims the screen behind it; edit mode's drag surface takes
    -- the accent hue so "you can move this" reads the same as every other affordance.
    colorOverlay     = { ref = "colorGray950", alpha = "opacityOverlay" },
    colorEditOverlay = { ref = "colorAccent",  alpha = "opacityEditOverlay" },
    -- Edit mode grid lines: the accent colour at grid opacity.
    colorGrid        = { ref = "colorAccent",  alpha = "opacityGrid" },
    -- Locked frame overlay: a warning tint so "you cannot move this" reads at a glance.
    colorEditOverlayLocked = { ref = "colorWarning", alpha = "opacityEditOverlay" },
    -- Selected frame overlay: brighter accent so the selected element stands out.
    colorEditOverlaySelected = { ref = "colorAccent", alpha = "opacityOverlay" },
    -- Smart guides (alignment lines to other elements) are brighter than the base grid.
    colorGuide       = { ref = "colorAccent", alpha = "opacityGuide" },
    -- A handle drawn ON TOP of arbitrary colour (a picker thumb over a hue bar), so it
    -- tracks the lightest neutral rather than the text colour it would otherwise borrow.
    colorMarker      = { ref = "colorGray100", alpha = 0.90 },
    -- The empty part of a frameless bar — a unit frame's health track, a cast bar's.
    -- Its own semantic rather than a panel colour: a bar sits over the game world, not
    -- over a panel, so it takes the darkest neutral at the bar-track opacity.
    colorBarTrack    = { ref = "colorGray950", alpha = "opacityBarTrack" },
    -- The glass plate an action bar's buttons sit on. Its own tokens rather than a reuse
    -- of colorBarTrack: that token is a BAR'S EMPTY TRACK, so sharing it would mean
    -- retinting a health bar's background silently retinted every action bar plate.
    colorGlass       = { ref = "colorGray950", alpha = "opacityGlass" },
    colorGlassFade   = { ref = "colorGray950", alpha = "opacityGlassFade" },
    -- The only place in this palette where a light neutral and a dark one meet inside one
    -- treatment: the sheen is a highlight ON the plate, so it refs the lightest neutral
    -- rather than the darkest. Pairing it with colorGlass above is the whole effect.
    colorGlassSheen  = { ref = "colorGray100", alpha = "opacityGlassSheen" },
    -- A unit's health, when it is not being coloured by class. See colorUseClassColors:
    -- with that flag on this becomes the fallback for a unit whose class is unknown — an
    -- NPC, a totem — rather than going unused.
    colorHealth      = "colorGreen500",
    -- The "you cannot stop this" cue: the hairline outline a cast bar draws around itself
    -- and its icon while the spell is uninterruptible. A light neutral rather than an
    -- intent colour — it is a property of the spell, not a warning, and it has to stay
    -- legible against whatever fill colour the player picked.
    colorShield      = "colorGray400",

    -- Tier 2: intent
    colorAccent      = "colorBlue400",
    colorAccentHover = "colorBlue500",
    colorSuccess     = "colorGreen400",
    colorDanger      = "colorRed400",
    colorWarning     = "colorYellow400",

    -- Experience, and the rested bonus that extends past it.
    --
    -- These are SEPARATE tokens rather than the accent, because in WoW their colours MEAN something:
    -- purple is progress, blue is rested. Painting progress in the accent made the bar claim a rested
    -- bonus that was not there. The rested region is drawn past current progress rather than under it,
    -- so it can be near-solid without muddying the fill -- the alpha only marks it as potential rather
    -- than earned.
    colorXp          = "colorMagenta400",
    colorXpRested    = { ref = "colorBlue400", alpha = 0.55 },

    -- Colour a unit by its class instead of by a fixed colour. A boolean rather than a
    -- colour token because it is a mode, not a value: it selects WHICH source a unit's
    -- colour comes from, while the class colours themselves are facts about the client and
    -- live in SuuUI.Game. Read through Theme:GetUnitColor, never directly.
    --
    -- Off here so Default is the fixed-palette theme; Modern turns it on. That is the kind
    -- of difference two built-in themes exist to carry.
    colorUseClassColors = false,

    -- Tier 2: content
    colorText         = "colorGray100",
    colorTextMuted    = "colorGray400",
    colorTextDisabled = "colorGray600",
    colorBorder       = "colorGray700",
    -- The ring around an icon's art, brighter than a panel's edge on purpose. A panel
    -- border separates a dark surface from the game world, where a near-black hairline
    -- reads fine; an icon border has to separate a tile from spell art that is itself
    -- dark at the edges, and colorGray700 there is invisible. Its own semantic rather
    -- than a retint of colorBorder, so making icons legible does not lighten every panel.
    colorBorderIcon   = "colorGray400",
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
    spaceXxs         = 2,
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
    -- The accent rail down the left edge of an OPEN accordion. Deliberately thicker than
    -- borderWidth: a border is a hairline that separates two surfaces, while this is a
    -- state marker that has to answer "which group am I in" from across the panel.
    sizeRail         = 2,

    borderWidth      = 1,
    -- borderRadius: the corner radius of a rounded surface (Backdrop.Panel). Its own token
    -- rather than a derivation of borderWidth, which is a thickness: a hairline border and
    -- a softly rounded corner are separate design decisions and move independently. 0 is
    -- square corners, so the rounding is disableable UI-wide without touching code.
    borderRadius     = 3,

    animFast         = 0.12,
    animMid          = 0.22,
    animSlow         = 0.38,
    -- Time for a status bar fill to travel its whole length. Its own token rather than
    -- animMid: bar smoothing reads as physical motion and wants to be slower than a
    -- panel transition, and a player who wants bars to snap should not have to speed up
    -- every dropdown to get it. 0 disables smoothing entirely.
    animBarFill      = 0.28,
    -- How far a button scales on press. 1 disables the pop without touching code.
    animPopScale     = 1.08,
})
