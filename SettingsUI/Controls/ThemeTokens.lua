-- Editable theme tokens exposed by the theme manager page, in render order.
--
-- Only tier 1 primitives are offered for colour editing. The semantic tokens
-- (colorBg, colorText, colorBorder, ...) are aliases onto these, so editing a
-- primitive cascades everywhere it is referenced. Exposing the semantics too would let
-- a user replace an alias with a literal colour and silently break that cascade.
-- Semantics remain overridable through Theme:SetUserToken for advanced use.
SuuUI._ThemeEditableTokens = {
    { key="colorGray950",   label="Neutral 950 (darkest)", type="color" },
    { key="colorGray900",   label="Neutral 900 (panel)",   type="color" },
    { key="colorGray850",   label="Neutral 850 (raised)",  type="color" },
    { key="colorGray800",   label="Neutral 800 (hover)",   type="color" },
    { key="colorGray750",   label="Neutral 750 (active)",  type="color" },
    { key="colorGray700",   label="Neutral 700 (border)",  type="color" },
    { key="colorGray600",   label="Neutral 600 (disabled text)", type="color" },
    { key="colorGray400",   label="Neutral 400 (muted text)",    type="color" },
    { key="colorGray100",   label="Neutral 100 (text)",    type="color" },

    { key="colorBlue400",   label="Accent",                type="color" },
    { key="colorBlue500",   label="Accent Hover",          type="color" },
    { key="colorGreen400",  label="Success",               type="color" },
    { key="colorRed400",    label="Danger",                type="color" },
    { key="colorYellow400", label="Warning",               type="color" },

    { key="opacityPanel",   label="Panel Opacity",   type="number", min=0.3,  max=1.0, step=0.05 },
    { key="opacityOverlay", label="Overlay Opacity", type="number", min=0.1,  max=1.0, step=0.05 },
    { key="opacityBarTrack", label="Bar Track Opacity", type="number", min=0.0, max=1.0, step=0.05 },

    -- Stored as a font name, not a path; SuuUI.Fonts resolves it. Options come from the
    -- client's own faces plus anything LibSharedMedia-3.0 exposes, if the player has it.
    { key="fontFamilyMain", label="Font",           type="font" },

    { key="fontSizeSm",   label="Font Size Small",  type="number", min=8,    max=20,  step=1 },
    { key="fontSizeMd",   label="Font Size Medium", type="number", min=10,   max=24,  step=1 },
    { key="fontSizeLg",   label="Font Size Large",  type="number", min=12,   max=28,  step=1 },
    { key="fontSizeXl",   label="Font Size XL",     type="number", min=14,   max=32,  step=1 },

    { key="spaceXxs",     label="Space XXS",        type="number", min=0,    max=8,   step=1 },
    { key="spaceXs",      label="Space XS",         type="number", min=0,    max=12,  step=1 },
    { key="spaceSm",      label="Space Small",      type="number", min=0,    max=16,  step=1 },
    { key="spaceMd",      label="Space Medium",     type="number", min=0,    max=24,  step=1 },
    { key="spaceLg",      label="Space Large",      type="number", min=0,    max=32,  step=1 },
    { key="spaceXl",      label="Space XL",         type="number", min=0,    max=48,  step=1 },

    { key="sizeControlSm", label="Control Small",   type="number", min=12,   max=32,  step=1 },
    { key="sizeControlMd", label="Control Medium",  type="number", min=16,   max=40,  step=1 },
    { key="sizeControlLg", label="Control Large",   type="number", min=18,   max=44,  step=1 },
    { key="sizeRow",       label="Row Height",      type="number", min=18,   max=48,  step=1 },
    { key="sizeNavRow",    label="Nav Row Height",  type="number", min=20,   max=56,  step=1 },
    { key="sizeTitleBar",  label="Title Bar",       type="number", min=18,   max=48,  step=1 },
    { key="sizeToggleW",   label="Toggle Width",    type="number", min=24,   max=64,  step=1 },
    { key="sizeIcon",      label="Icon Size",       type="number", min=8,    max=32,  step=1 },
    { key="sizeScrollbar", label="Scrollbar Width", type="number", min=4,    max=20,  step=1 },

    { key="sizeUnitFrameW",    label="Unit Frame Width",  type="number", min=120, max=400, step=2 },
    { key="sizeUnitHealthBar", label="Unit Health Bar",    type="number", min=8,   max=60,  step=1 },
    { key="sizeUnitPowerBar",  label="Unit Resource Bar",  type="number", min=4,   max=40,  step=1 },

    { key="borderWidth",  label="Border Width",     type="number", min=1,    max=4,   step=1 },
    { key="animFast",     label="Animation Fast",   type="number", min=0.05, max=0.5, step=0.05 },
    { key="animMid",      label="Animation Mid",    type="number", min=0.1,  max=0.8, step=0.05 },
    { key="animSlow",     label="Animation Slow",   type="number", min=0.2,  max=1.0, step=0.05 },
}
