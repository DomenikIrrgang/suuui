# SuuUI Architecture

## Overview

SuuUI is a modular, full interface replacement addon for WoW Classic Anniversary TBC.
It consists of a Core addon and any number of plugins — either bundled inside this
folder or as separate addon folders that declare SuuUI as a dependency.

No external libraries. Everything is built from scratch.

---

## Directory Structure

```
SuuUI/
├── SuuUI.toc
├── Core/
│   ├── Init.lua          -- bootstrap, version, global namespace
│   ├── EventBus.lua      -- addon-wide pub/sub (theme, profile, settings)
│   ├── UISignals.lua     -- per-element signal system (Godot-style)
│   ├── UIRoot.lua        -- single fullscreen root, layer management
│   ├── Plugin.lua        -- plugin registry and lifecycle
│   ├── Profile.lua       -- profile storage, CRUD, character linking
│   ├── Settings.lua      -- settings schema registry and value I/O
│   ├── Fonts.lua         -- font registry: client faces, locale faces, LibSharedMedia
│   ├── Theme.lua         -- token system, theme registry, active theme
│   ├── Pixel.lua         -- pixel grid: root scale, snapping, cursor space conversion
│   └── Pool.lua          -- typed frame pool
├── Animation/
│   ├── Tween.lua         -- easing functions
│   ├── Animator.lua      -- animation runner, chaining, sequencing
│   └── Presets.lua       -- named animation presets (fadeIn, slideIn, etc.)
├── Layout/
│   ├── Window.lua        -- draggable, resizable top-level window
│   ├── Container.lua     -- base container; creates or adopts (host) a layout box
│   ├── FlowLayout.lua    -- horizontal / vertical flow with fill + align
│   ├── GridLayout.lua    -- fixed grid
│   ├── StackLayout.lua   -- overlay: inset, align, valign (replaces SetAllPoints)
│   └── AnchorLayout.lua  -- absolute / fraction-driven placement (thumbs, panels)
├── Components/
│   ├── Backdrop.lua      -- shared bg+border backdrop primitive (SuuUI.Backdrop)
│   ├── Base.lua          -- InstallBase: shared handle accessors on a metatable
│   ├── Frame.lua         -- styled base frame (border, bg, variant)
│   ├── Text.lua          -- styled FontString wrapper
│   ├── ClickAway.lua     -- shared click-outside watcher for transient panels
│   ├── Button.lua        -- full custom button (no Blizzard template)
│   ├── IconButton.lua
│   ├── NavItem.lua       -- selectable labelled row (nav lists)
│   ├── Toggle.lua        -- custom checkbox/toggle
│   ├── Slider.lua        -- custom slider
│   ├── Dropdown.lua      -- custom dropdown
│   ├── Input.lua         -- EditBox wrapper (Blizzard required)
│   ├── ColorSwatch.lua   -- clickable colour square
│   ├── ColorPicker.lua   -- custom HSV color picker
│   ├── KeyCapture.lua    -- button that captures the next keypress
│   ├── ScrollFrame.lua   -- scroll container
│   ├── Tooltip.lua       -- custom tooltip
│   ├── Divider.lua
│   ├── Modal.lua         -- dialog with optional input
│   └── Notice.lua        -- one-shot dismissible message, built on Modal
├── SettingsUI/
│   ├── SettingsWindow.lua -- unified settings window (left nav + content)
│   ├── PageBuilder.lua    -- auto-builds a settings page from schema
│   └── Controls/          -- per-type setting control renderers
│       ├── Toggle.lua
│       ├── Slider.lua
│       ├── Dropdown.lua
│       ├── Color.lua
│       ├── Text.lua
│       ├── Keybind.lua
│       └── Section.lua
├── Plugins/               -- bundled first-party plugins live here
│   ├── UnitFrames/
│   ├── ActionBars/
│   └── ...
├── Themes/
│   ├── Default.lua        -- read-only default dark theme
│   └── Modern.lua         -- read-only modern theme (ships as default active)
└── Tests/                 -- not shipped to the client; see TESTING.md
    ├── run.lua            -- test runner
    ├── harness/           -- simulated WoW client + assertions
    └── spec/              -- one spec per component / subsystem
```

`Tests/` is not listed in the `.toc`, so the client never loads it.

---

## Layer Diagram

```
┌─────────────────────────────────────────────┐
│              External Addons                │  (separate .toc, dep on SuuUI)
├─────────────────────────────────────────────┤
│           Bundled Plugins (Plugins/)        │
├──────────────┬──────────────────────────────┤
│  SettingsUI  │    Plugin-owned UI           │
├──────────────┴──────────────────────────────┤
│         Components + Layout Engine          │
├─────────────────────────────────────────────┤
│   Animation  │  Theme/Tokens │  Frame Pool  │
├─────────────────────────────────────────────┤
│       Core (EventBus, Plugin, Profile,      │
│              Settings, Init)                │
├─────────────────────────────────────────────┤
│              WoW API / Blizzard             │
└─────────────────────────────────────────────┘
```

---

## Core Subsystems

### 1. Namespace & Bootstrap (`Core/Init.lua`)

- Global table `SuuUI` is the single public namespace.
- `SuuUI.version` string.
- Loads subsystems in dependency order via `.toc` file ordering.
- Provides `SuuUI.Debug(msg)` gated behind a debug flag.

### 2. Event Bus (`Core/EventBus.lua`)

Custom pub/sub layer on top of WoW events. Plugins communicate through this,
never by direct function calls into each other.

**API:**
```lua
SuuUI.Events:On(event, callback, owner)    -- subscribe
SuuUI.Events:Off(event, owner)             -- unsubscribe all for owner
SuuUI.Events:Emit(event, ...)              -- fire with varargs payload
SuuUI.Events:Once(event, callback, owner)  -- auto-removes after first fire
```

Events are plain strings. Convention: `"SUUUI_THEME_CHANGED"`, `"SUUUI_PROFILE_LOADED"`.

### 2b. UI Signals (`Core/UISignals.lua`)

Per-element signal system for UI-to-UI communication. See `UI_SIGNALS.md` for the
full contract. Blizzard frame scripts must never be used to notify other UI elements —
they stay inside the component that owns the frame.

**API:**
```lua
local S = SuuUI.UISignals
local id = S:Connect(obj, S.SIGNALS.SIZE_CHANGED, function(w, h) end)
S:Disconnect(obj, S.SIGNALS.SIZE_CHANGED, id)
S:DisconnectAll(obj, signal)   -- signal optional; omit to clear the object
S:Emit(obj, S.SIGNALS.SIZE_CHANGED, w, h)
S:HasConnections(obj, signal)
```

Registry uses weak keys, so destroyed objects are collected and their connections
vanish with them. Callbacks run through `pcall` and log failures via `SuuUI.Debug`.

Built-in bus events: `SUUUI_PROFILE_LOADED`, `SUUUI_THEME_CHANGED`, `SUUUI_FONTS_CHANGED`,
`SUUUI_PIXEL_GRID_CHANGED`, `SUUUI_SETTING_CHANGED`, `SUUUI_PLUGIN_ENABLED`,
`SUUUI_PLUGIN_DISABLED`.

**Standard signals** (payload in parentheses): `SIZE_CHANGED` (w, h),
`POSITION_CHANGED` (x, y), `VISIBILITY_CHANGED` (isVisible), `MOUSE_ENTER` (—),
`MOUSE_LEAVE` (—), `CLICKED` (button), `VALUE_CHANGED` (new, old),
`TEXT_CHANGED` (text), `SCROLL_CHANGED` (scrollY), `CONTENT_RESIZED` (height),
`ENABLED_CHANGED` (isEnabled), `FOCUSED` (—), `UNFOCUSED` (—).

**Choosing the right bus:**

| Kind | Mechanism |
|---|---|
| UI element notifying another UI element | `SuuUI.UISignals` |
| Addon-wide state change | `SuuUI.Events` |
| WoW game data | `frame:RegisterEvent` in a plugin |

### 3. Plugin System (`Core/Plugin.lua`)

Plugins register with the core. The core drives their lifecycle.

**API:**
```lua
-- Called by plugin author to register
local plugin = SuuUI:CreatePlugin({
  id       = "minimap",        -- unique snake_case string
  name     = "Minimap",        -- display name for settings UI
  version  = "1.0",
  onInit   = function(p) end,  -- exactly once, on login or on late registration
  onEnable = function(p) end,  -- called when plugin is enabled
  onDisable= function(p) end,  -- called when plugin is disabled
})

-- Returned plugin handle methods
plugin:GetSettings()    -- returns plugin's live settings table
plugin:GetProfile()     -- returns plugin's profile sub-table
plugin:IsEnabled()
plugin:Enable()         -- no-op when already enabled
plugin:Disable()        -- no-op when already disabled
```

On `PLAYER_LOGIN` the core runs every `onInit`, then every `onEnable`, in two separate
passes — so an `onEnable` may rely on another plugin's settings and events already
existing, while an `onInit` may not. Plugins must NOT assume load order of other plugins.

**`onInit` runs exactly once per plugin.** `Plugins:InitAll()` skips plugins already
initialised, so it is safe to re-call. A plugin registered *after* the login pass — an
addon whose `.toc` loads later — is initialised and enabled at `CreatePlugin` time
instead, so it comes up identically without re-entering anyone else's `onInit`.

```lua
SuuUI.Plugins:InitAll()            -- idempotent
SuuUI.Plugins:IsInitialised(id)    -- whether onInit has run
```

### 4. Profile System (`Core/Profile.lua`)

- Profiles stored in `SuuUIProfiles` SavedVariable (account-wide).
- Each profile is a named table. Default profile cannot be deleted.
- Characters can be linked to any profile.
- On login, core loads the profile linked to the current character
  (falls back to Default).

**API:**
```lua
SuuUI.Profiles:Create(name)           -- new profile, copies Default as base
SuuUI.Profiles:Delete(name)           -- error if "Default"
SuuUI.Profiles:List()                 -- returns array of profile names
SuuUI.Profiles:SetActive(name)        -- switch, fires SUUUI_PROFILE_LOADED
SuuUI.Profiles:GetActive()            -- returns active profile table
SuuUI.Profiles:LinkCharacter(name)    -- links current character to profile
SuuUI.Profiles:Get(name)              -- returns raw profile table
SuuUI.Profiles:CopyTo(targetName)     -- deep-copies active profile into target
```

Plugin settings are namespaced inside profiles:
`profile.plugins[pluginId] = { ... settings ... }`

### 5. Settings Registry (`Core/Settings.lua`)

Stores schema definitions. Does NOT render UI — that is SettingsUI's job.

Schema entry shape:
```lua
{
  key      = "showBorder",   -- unique within plugin
  label    = "Show Border",
  type     = "toggle",       -- toggle|slider|dropdown|color|text|keybind|section
  default  = true,
  -- type-specific:
  min=, max=, step=          -- slider
  options={}                 -- dropdown: array of {value, label}
  validate = function(v) end -- optional, returns true or error string
}
```

**API:**
```lua
SuuUI.Settings:Register(pluginId, schemaArray)
SuuUI.Settings:GetSchema(pluginId)
SuuUI.Settings:Get(pluginId, key)          -- reads from active profile
SuuUI.Settings:Set(pluginId, key, value)   -- writes, fires SUUUI_SETTING_CHANGED
SuuUI.Settings:Reset(pluginId, key)        -- resets to schema default
SuuUI.Settings:ResetAll(pluginId)
```

Event payload: `"SUUUI_SETTING_CHANGED"` → `pluginId, key, value, oldValue`

### 6. Theme & Token System (`Core/Theme.lua`)

Flat token table, but organised in **two tiers**. Token names: camelCase with category
prefix. Categories: `color`, `opacity`, `font`, `space`, `size`, `border`, `anim`.

**Tier 1 — primitives.** Named for what they *are*: `colorGray900`, `colorBlue400`.
Neutrals run 950 (darkest) to 100 (lightest). These are the only colours the theme
editor exposes.

**Tier 2 — semantics.** Named for what they are *for*: `colorBg`, `colorBorder`,
`colorDanger`. Every semantic is an alias or a derivation onto tier 1.

**Components reference tier 2 only.** That is what makes a retint a one-line edit:
change `colorBlue400` and every focused border, slider fill, and accent label follows.

Three value forms:

| Form | Example | Resolves to |
|---|---|---|
| literal | `colorGray900 = {0.08, 0.08, 0.10, 1.00}` | itself |
| alias (string) | `colorAccent = "colorBlue400"` | the referenced token, chained up to 8 deep |
| derivation (table) | `colorBg = { ref = "colorGray900", alpha = "opacityPanel" }` | the ref's RGB with the alpha token's value |

Derivations are what keep opacity a single control: panel translucency is the
`opacityPanel` token, not an alpha channel repeated across four colour literals.

```lua
-- Tier 1: primitives
colorGray900   = {0.08, 0.08, 0.10, 1.00}   -- 950 850 800 750 700 600 400 100 also defined
colorBlue400   = {0.25, 0.55, 1.00, 1.00}
colorBlue500   = {0.18, 0.44, 0.90, 1.00}
colorGreen400  = {0.20, 0.80, 0.40, 1.00}
colorRed400    = {0.90, 0.25, 0.25, 1.00}
colorYellow400 = {0.95, 0.80, 0.20, 1.00}
opacityPanel   = 0.95
opacityOverlay = 0.35

-- Tier 2: surfaces
colorBg          = { ref = "colorGray900", alpha = "opacityPanel" }
colorBgAlt       = { ref = "colorGray850", alpha = "opacityPanel" }
colorBgHover     = { ref = "colorGray800", alpha = "opacityPanel" }
colorBgActive    = { ref = "colorGray750", alpha = "opacityPanel" }   -- selected
colorBgPressed   = { ref = "colorGray750", alpha = "opacityPanel" }   -- mouse down
colorBgDisabled  = { ref = "colorGray850", alpha = "opacityPanel" }
-- Tier 2: intent
colorAccent      = "colorBlue400"
colorAccentHover = "colorBlue500"
colorSuccess     = "colorGreen400"
colorDanger      = "colorRed400"
colorWarning     = "colorYellow400"
-- Tier 2: content
colorText         = "colorGray100"
colorTextMuted    = "colorGray400"
colorTextDisabled = "colorGray600"
colorBorder       = "colorGray700"
colorBorderFocus  = "colorAccent"

-- Typography
fontSizeSm = 11    fontSizeMd = 13    fontSizeLg = 15    fontSizeXl = 18
fontFamilyMain = "Friz Quadrata TT"   -- a font NAME; GetToken resolves it to a path

-- Spacing, used for both gaps (between items) and padding (container insets)
spaceXs = 4    spaceSm = 8    spaceMd = 12    spaceLg = 16    spaceXl = 24

-- Sizes. Never hardcode a control height; see Theme:GetControlHeight.
sizeControlSm = 18   -- toggle, swatch          sizeRow       = 28  -- settings rows
sizeControlMd = 22   -- input, option row       sizeNavRow    = 32  -- nav items
sizeControlLg = 24   -- dropdown, buttons       sizeTitleBar  = 26  -- window chrome
sizeIcon      = 16   sizeScrollbar = 8          sizeToggleW   = 36

borderWidth = 1
animFast = 0.12    animMid = 0.22    animSlow = 0.38
```

Every token has a consumer. A token nothing reads is worse than an absent one: it shows
up in the theme editor as a control that silently does nothing. If you add a token, wire
it; if you remove a consumer, remove the token.

`colorSuccess` / `colorDanger` / `colorWarning` are the intent tokens — use them for
state colouring rather than reaching for `colorGreen400` directly. They reach the screen
through `Button`'s `variant` and `Modal`'s `confirmVariant`:

| Intent | Where it belongs |
|---|---|
| `danger` | the confirm button of a destructive dialog; a failure notice |
| `success` | the confirm button of a create/copy dialog |
| `warning` | a notice for an action that is blocked but expected |

**Intent colour goes on the button that commits the action, not the one that opens the
dialog.** A "Delete" button on a settings page is neutral; the "Delete" button inside the
confirmation dialog is `danger`. Colouring both makes the page shout before the user has
asked for anything.

**The theme editor exposes tier 1 colours only** (`SettingsUI/Controls/ThemeTokens.lua`).
Editing a primitive cascades through every semantic that references it. Exposing the
semantics too would let a user replace an alias with a literal and break that cascade
permanently, so semantics stay `SetUserToken`-only.

Built-in themes are read-only. User themes stored in profile under
`profile.themes[name]` as a partial token override table, stamped with
`_tokenVersion` so renamed keys from older saves can be migrated on read.

**`fontFamilyMain` is a fourth value form: a font name.** It stores a name rather than a
file path so the choice survives a media addon moving its file, and `GetToken` hands
consumers the resolved path — nothing downstream changes. A literal path still passes
through, which is what a hand-edited SavedVariable may hold. `GetTokenRaw` returns the
stored name, which is what the theme editor's dropdown displays.

**API:**
```lua
SuuUI.Theme:GetToken(key)                       -- resolves aliases, derivations, fonts
SuuUI.Theme:GetTokenRaw(key)                    -- stored value, before resolution
SuuUI.Theme:GetControlHeight(sizeKey, fontKey)  -- size token floored by font metrics
SuuUI.Theme:SetActive(name)                     -- fires SUUUI_THEME_CHANGED
SuuUI.Theme:GetActive()
SuuUI.Theme:List()
SuuUI.Theme:IsBuiltin(name)
SuuUI.Theme:CreateUserTheme(name, baseTheme)
SuuUI.Theme:DeleteUserTheme(name)               -- error on built-ins
SuuUI.Theme:ResetUserTheme(name)
SuuUI.Theme:SetUserToken(themeName, key, value)
SuuUI.Theme:ApplyToFrame(frame)                 -- bg+border via SuuUI.Backdrop.Apply
```

`GetControlHeight` returns `max(sizeToken, fontSize + spaceXs * 2)`. Use it for anything
that holds text, since font sizes are user-editable and a control pinned to a literal
height clips once the font outgrows it. Read the size token directly for elements with no
text of their own (toggles, swatches, scrollbars).

Components listen for `SUUUI_THEME_CHANGED` and call `ApplyTheme()` internally.

### 6b. Font Registry (`Core/Fonts.lua`)

Backs the `fontFamilyMain` token. **There is no filesystem API in WoW** — a font list has
to be assembled from what the client will admit to:

| Source | How |
|---|---|
| curated client faces | Friz Quadrata TT, Arial Narrow, Morpheus, Skurri |
| locale faces | `STANDARD_TEXT_FONT`, `UNIT_NAME_FONT`, `DAMAGE_TEXT_FONT`, `NAMEPLATE_FONT` |
| everything the client loaded | `GetFonts()` returns font *object* names; the path comes off each object via `GetFont()` |
| media addons | `LibSharedMedia-3.0` if the player has it — read only, never a dependency |
| plugins and users | `Fonts:Register(name, path)` |

Every candidate is validated by probing `SetFont` through `TextMetrics.CanLoadFont`, since
applying a font is the only way to test it. Entries are deduplicated by path across slash
style and case, because LSM registers with backslashes and this addon writes forward ones.

**Two traps live here, and both have already cost a broken login:**

- **`SetFont` raises on an invalid asset** — `Invalid font asset (X): file not found` —
  rather than returning false. Every probe is wrapped in `pcall`, and any face that comes
  from a caller (a `Text` `font` prop, a `Dropdown` option's `font`) is resolved through
  `Fonts:Path` before it reaches `SetFont`. An unguarded probe unwound out of the
  `PLAYER_LOGIN` handler and cost plugin init and `SUUUI_READY`.
- **Not every client font global holds a path.** `NAMEPLATE_FONT` is `"GameFontWhite"`, a
  font *object* name. Candidates are shape-checked for a font file extension first, and a
  name that isn't one is resolved via the object's own `GetFont()`.

The scan itself is wrapped too, so the worst case is a short font list rather than a failed
login. The simulated client raises the same way, and ships `NAMEPLATE_FONT` in its real
object-name shape, so the whole suite exercises both traps on every setup.

Names match LSM's for the same files, deliberately: a theme saved while SharedMedia was
installed has to keep resolving once it is gone, and the reverse.

**API:**
```lua
SuuUI.Fonts:List()               -- { { name, path, source } } sorted by name
SuuUI.Fonts:Options()            -- { { value = name, label = name } } for a Dropdown
SuuUI.Fonts:Path(nameOrPath)     -- always returns a loadable path; falls back if not
SuuUI.Fonts:Name(pathOrName)     -- display name, or nil
SuuUI.Fonts:Has(name)
SuuUI.Fonts:Validate(path)
SuuUI.Fonts:Register(name, path, source)
SuuUI.Fonts:Add(path)            -- register by path alone, named after the file
SuuUI.Fonts:Refresh()            -- rescan; emits SUUUI_FONTS_CHANGED if the set moved
SuuUI.Fonts.FALLBACK             -- "Fonts/FRIZQT__.TTF"
```

`Add` backs the theme editor's "Add" button: a font dropped into an addon folder that no
media addon registered is invisible to every discovery source, so taking the path directly
is the only route to it. It returns nil for a file the client cannot load, which is the
caller's cue to say so through a `Notice` rather than storing a broken path.

`Refresh()` runs on `PLAYER_LOGIN` because a media addon can load after SuuUI. `Theme`
listens for `SUUUI_FONTS_CHANGED` and re-emits `SUUUI_THEME_CHANGED` only when the
resolved path actually moved, so a font that was missing at boot appears without a reload.

### 6c. Pixel Grid (`Core/Pixel.lua`)

The engine lays the UI out in **units, not pixels**. The drawing area is always 768 units
tall, so one unit spans `physicalHeight / 768` pixels — 1.40625 at 1080p on the default
scale. A 1-unit border therefore straddles a pixel boundary and the rasteriser renders it
as a grey smear rather than a line. That is the whole "why" behind this module.

Fixing it takes two things, and one without the other is useless:

1. **A grid.** The scale on `SuuUI_UIRoot` is set so one unit is an exact whole number of
   pixels. `SetIgnoreParentScale` detaches it from the player's UI Scale slider; where the
   client lacks that, the parent chain is divided back out so both paths agree.
2. **Coordinates on it.** A perfect grid buys nothing if the layout hands `SetPoint` 13.7.
   Every value the four strategies pass to `SetPoint` / `SetSize` / `SetWidth` goes through
   `Pixel.Snap`.

**Why the root and not `UIParent`.** Scaling `UIParent` moves every Blizzard frame and
every other addon's anchors. Scaling our own root is reversible, invisible to everyone
else, and sidesteps the 0.64 floor the `uiScale` CVar enforces (which is why the CVar
route silently fails above 1200px vertical).

**Why an integer multiplier.** At 1x, a 4K panel yields 2160 units of vertical space and a
520-unit window occupies a quarter of the screen. `multiplier` picks a whole-number
multiple of the base scale — chosen from the physical height, aiming for roughly 1000
units — so a unit is still an exact whole number of pixels and the UI stays exactly as
crisp while being physically usable. A *fractional* multiplier would put units back
between pixels, which is the problem this module exists to remove, so `SetMultiplier`
rounds.

**`grid` vs `mult`.** `mult` is one physical pixel expressed in units. `grid` is the snap
quantum. With scaling active they differ on purpose: units are whole pixels, so `grid` is
1 and every measurement stays integral. With scaling **off** — user preference, or a
custom scale — units are off-grid by definition, so `grid` becomes `mult` and snapping
targets real pixels instead. That indirection is why a border is exactly one pixel either
way instead of 1.4.

**API:**
```lua
SuuUI.Pixel.Snap(v)              -- nearest grid multiple
SuuUI.Pixel.Floor(v)             -- for a size that must not overflow its space
SuuUI.Pixel.Ceil(v)              -- for a size that must not clip its content
SuuUI.Pixel.Line(v)              -- line thickness, floored at one pixel so it never vanishes
SuuUI.Pixel.CursorIn(frame)      -- cursor in that frame's coordinate space
SuuUI.Pixel:Refresh()            -- recompute; emits SUUUI_PIXEL_GRID_CHANGED if it moved
SuuUI.Pixel:Attach(frame)        -- drive a frame's scale (UIRoot attaches the root)
SuuUI.Pixel:SetEnabled(bool)     -- scaling on/off; snapping stays on either way
SuuUI.Pixel:SetMultiplier(n)     -- override; nil returns to automatic
SuuUI.Pixel.grid / .mult / .scale / .multiplier / .physicalHeight
```

`Snap` is **idempotent**, which is load-bearing: `Container:Layout` re-runs its strategy
after hugging, and a non-idempotent rounding would drift on every pass and never settle.

**`CursorIn` is not optional.** `GetCursorPosition()` reports raw screen coordinates,
while a frame's `GetLeft`/`GetBottom` are in that frame's space. The two differ by the
frame's effective scale — and the pixel grid puts a scale on the root, so anything under
it that divides by `UIParent:GetEffectiveScale()` is off by the ratio between the two. Use
`CursorIn(theFrameYouAreComparingAgainst)` for every hit test and drag.

`Refresh` is driven by `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED` and `CVAR_UPDATE`.
`Theme` listens for `SUUUI_PIXEL_GRID_CHANGED` and re-emits `SUUUI_THEME_CHANGED`, since
a moved grid changes what every token-derived size snaps to — the same restyle a theme
change needs. Same pattern as `SUUUI_FONTS_CHANGED`.

### 7. Frame Pool (`Core/Pool.lua`)

Typed pools keyed by string ID. Plugins prefix their IDs: `"minimap.buffIcon"`.

**API:**
```lua
SuuUI.Pool:Register(typeId, createFn)   -- register factory (called when pool empty)
SuuUI.Pool:Acquire(typeId, parent)      -- get frame (pool or new), shows it
SuuUI.Pool:Release(typeId, frame)       -- return to pool, hides and resets frame
SuuUI.Pool:ReleaseAll(typeId)           -- return all active frames of type
```

---

## Layout Engine

### Window (`Layout/Window.lua`)

Top-level draggable, optionally resizable frame. Position saved per-character
in `SuuUIConfig`. Registered windows appear in a window-manager list.

```lua
local win = SuuUI.Layout:CreateWindow({
  id        = "myWindow",
  title     = "My Window",
  w=800, h=560, minW=400, minH=300,
  resizable = true,
})
win:Show() / win:Hide() / win:Toggle()
win:SetTitle(str)
win:GetContentFrame()   -- inner frame, attach children here
win:SavePosition()      -- called automatically on drag stop
```

`minW` / `minH` / `maxW` / `maxH` are handed to the client via `SetResizeBounds`, so a
drag stops dead at the limit. Never clamp after the fact in `OnMouseUp` — the window
overshoots and visibly snaps back. The initial `w`/`h` are clamped into the bounds too.

### Container (`Layout/Container.lua`)

Layout unit with a strategy. Recalculates child positions on `Layout()`.
Supports flexible sizing via layout properties.

```lua
local c = SuuUI.Layout:CreateContainer({
  parent  = frame,
  layout  = "flow",   -- "flow" | "grid" | "anchor"
  dir     = "vertical",
  gap     = 8,
  align   = "center", -- default cross-axis alignment for children
  fill    = true,     -- anchor to all sides of parent, track parent resizes
  padding = {top=8, right=8, bottom=8, left=8},
})

-- Add child with flexible sizing. Accepts a frame, component handle, or container.
c:Add(child, { width = "fill", height = 32 })  -- fill width, fixed height
c:Add(child, { width = 200 })                  -- fixed width, natural height
c:Add(child, { align = "center" })             -- per-child cross-axis override
c:Add(child)                                   -- natural dimensions

c:Remove(child)        -- drops only this container's own signal connection
c:Clear()              -- removes and hides every child
c:Layout()             -- auto-called on Add/Remove/resize
c:SetSize(w, h)
c:GetContentSize()     -- returns computed w, h of all children
c:GetChildren()
c:Destroy()            -- destroys children, drops all connections
```

Containers are frame-like: `GetFrame` `GetWidth` `GetHeight` `SetWidth` `SetHeight`
`SetPoint` `ClearAllPoints` `Show` `Hide` `IsShown`. That is what lets them nest.
A container emits `SIZE_CHANGED` whenever its computed size changes.

**Layout Properties:**
- `width = "fill"` — child takes available horizontal space
- `width = number` — fixed width in pixels
- `height = "fill"` — child takes available vertical space (flow layouts only)
- `height = number` — fixed height in pixels
- `align = "start"|"center"|"end"|"stretch"` — cross-axis alignment
- Omit property to use child's natural size

### Layout Strategies

**These four files are the only place in the addon that calls `SetPoint`.** That is also
what makes them the only place that needs to snap to the pixel grid: every coordinate
reaching `SetPoint` / `SetSize` passes through `SuuUI.Pixel.Snap` here, so components and
plugins get crisp geometry without doing anything. See `Core/Pixel.lua` above.

Sizes use `Floor` where overflowing the parent would be worse than being a pixel short
(content boxes, stretched children) and `Ceil` where clipping content would be worse
(hugging containers, text heights).

- **FlowLayout** (`Layout/FlowLayout.lua`): horizontal or vertical flow with flexible sizing.
  - `width="fill"` / `height="fill"` distribute remaining main-axis space
  - Fill shares are floored onto the grid and the **remainder is handed out one pixel at
    a time** to the leading children. Flooring an equal share loses up to `fillCount - 1`
    pixels, which shows up as the last child in a filled row stopping short of the edge.
  - `align` gives cross-axis placement (`start`/`center`/`end`/`stretch`)
  - Respects padding on all 4 sides
  - Font string children are measured with `GetStringHeight()` after their width is
    assigned, so text re-flows when a `fontSize*` token changes. Omit `height` on
    text children; a fixed height pins them to the old font's metrics.
- **GridLayout** (`Layout/GridLayout.lua`): fixed columns, equal cells.
  - Column width derived from container width, padding, and gap
  - Widths are computed once for the whole grid, so a column is the same width in every
    row, and the flooring remainder is spread across the leftmost columns so the row still
    reaches the right edge
- **StackLayout** (`Layout/StackLayout.lua`): overlays children on the container box.
  - `inset` (number or per-edge table), `align`, `valign`, explicit `width`/`height`
  - Replaces `SetAllPoints`, centred labels, edge-spanning text, and inset icons
  - This is what components use internally
  - Font string children on a non-stretched axis are measured with
    `TextMetrics.Measure`, not from their rect, so they track the `fontSize*` tokens.
    Call `box:Layout()` after changing a font string's font — a token-sized element
    does not resize, so nothing else re-measures it and the client clips the glyphs.
- **AnchorLayout** (`Layout/AnchorLayout.lua`): children carry anchor descriptors.
  - For computed positions: slider fills and thumbs, scrollbar thumbs, floating panels
  - Move a child with `container:SetChildAnchor(child, desc)`
  - `relativeTo` may be a frame, a component handle, `"parent"`, or `nil`

### Host containers

`CreateContainer{ host = existingFrame }` adopts a frame as its layout box instead of
creating one. Components use this so internal layout costs no extra frames and needs no
`SetPoint`. Adopting chains any existing `OnSizeChanged` rather than replacing it.

**Register a frame's own resize script before adopting it.** The container chains onto
whatever is already there, so ordering decides who survives — setting the script after
the container adopts the frame replaces the container's re-layout hook and breaks
resizing silently.

### Components must react to being resized

A parent layout resizes a child's **frame** directly; it never calls the handle's
`SetSize`. So any component whose internals depend on its own width or height must hook
its frame's `OnSizeChanged` (registered before its host container, per above), recompute,
and emit `SIZE_CHANGED`:

```lua
local handle
f:SetScript("OnSizeChanged", function(_, w, h)
    if not (handle and handle._box) then return end   -- guard during construction
    handle:_render()
    S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
end)
```

`SetSize` on the handle should then just set the frame size and let the hook do the work,
so both paths behave identically. `ScrollFrame`, `Slider`, and `Toggle` all rely on this.
Emitting only from `SetSize` is the trap: consumers listening for `SIZE_CHANGED` never
hear about layout-driven resizes and keep stale widths.

Position that is animated should also be applied immediately when the change is a resize
rather than a value change — otherwise the element sits at a stale offset until the
animation ticks. `Toggle:_render(snap)` shows the pattern.

### Container sizing is always explicit

Containers never rely on anchor-derived geometry. WoW does not lay out frames that have
never been displayed, so an anchor-only container inside a hidden window reports width 0
and collapses its children. `fill = true` mirrors the parent's size and tracks its
resizes; containers also re-layout on `OnShow`.

### Shared floating host

`SuuUI.Layout:GetFloatingHost()` returns the single anchor container for transient
screen-level panels (dropdown panels, tooltips, popups). Use it rather than creating a
per-panel screen-level container, which would accumulate resize handlers on `UIParent`
as pages rebuild. Remove your panel on teardown; never destroy the host.

### Animating position

The animator's `x`/`y` properties drive an anchor descriptor through
`container:SetChildAnchor`, so even motion goes through the engine:

```lua
SuuUI.Anim:New({
  container = knobBox, target = knob, anchor = knobAnchor,
  property  = "x", from = 3, to = 20, duration = 0.1, easing = "easeOut",
}):Play()
```

`container` and `anchor` are required for `x`/`y`; there is no `SetPoint` fallback.

### Extending the Layout System

**When you need layout functionality that doesn't exist:**

1. **Identify the gap** — what specific layout behavior is missing?
   - Examples: center alignment, wrapping, percentage widths, min/max constraints
   
2. **Design generically** — think about how to make it reusable:
   ```lua
   -- BAD: Plugin-specific hack
   if self._isNavItem then
     child:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
   end
   
   -- GOOD: Generic alignment support
   container:Add(child, { 
     width = "fill",
     align = "stretch"  -- new generic property
   })
   ```

3. **Discuss the API** — before implementing:
   - What property names make sense?
   - Which layouts should support it?
   - Are there edge cases or interactions with existing features?

4. **Implement in the layout strategy** — extend `FlowLayout.lua`, `GridLayout.lua`, etc.
   - Add property handling in the `Apply()` function
   - Update documentation in this file
   - Update plugin authoring guide with examples

5. **Never bypass the system** — manual positioning creates:
   - Inconsistent behavior across plugins
   - Code that doesn't respond to theme changes
   - Hard-to-maintain spaghetti SetPoint chains
   - Broken layouts when container resizes

**Current known limitations to discuss:**
- No wrapping in flow layouts
- No percentage-based sizing (`width = "50%"`)
- No min/max size constraints
- No margin (distinct from container padding)
- No z-index/layer control for overlapping children (use UIRoot layers)

Resolved: cross-axis `align` (`start`/`center`/`end`/`stretch`) on containers and
children; container `fill` for parent-tracking; nested containers as first-class children.

---

## Animation System

### Tween (`Animation/Tween.lua`)

Pure stateless functions. `Tween.Ease(t, easingType)` where `t` is 0–1.

Types: `linear`, `easeIn`, `easeOut`, `easeInOut`, `spring`

### Animator (`Animation/Animator.lua`)

Runs via a single shared `OnUpdate` frame (not AnimationGroups).
All active animations share one update tick — minimal overhead.

```lua
-- Single animation
local anim = SuuUI.Anim:New({
  target   = frame,
  property = "alpha",   -- "alpha"|"width"|"height"|"x"|"y"|"scale"
  from     = 0, to = 1,
  duration = 0.25,
  easing   = "easeOut",
  onDone   = function() end,
})

-- Parallel (simultaneous)
SuuUI.Anim:Parallel({anim1, anim2})

-- Sequence (one after another)
SuuUI.Anim:Sequence({anim1, anim2, anim3})

anim:Play()
anim:Stop()
anim:Reverse()
anim:IsPlaying()
```

### Presets (`Animation/Presets.lua`)

```lua
SuuUI.Anim.Presets.FadeIn(frame, duration)
SuuUI.Anim.Presets.FadeOut(frame, duration)
SuuUI.Anim.Presets.SlideIn(frame, dir, dist, duration)  -- dir: "up"|"down"|"left"|"right"
SuuUI.Anim.Presets.SlideOut(frame, dir, dist, duration)
SuuUI.Anim.Presets.ScalePop(frame, duration)
```

---

## Component Library

All components accept `(props, parent)`. Return a handle with shared API.
All components auto-restyle on `SUUUI_THEME_CHANGED`.

**Components are the ONLY place raw WoW UI API may be called.** `CreateFrame`,
`CreateTexture`, `CreateFontString`, `SetBackdrop`, `SetFrameStrata`, `EnableMouse`,
and `SetScript` belong inside `Components/`, `Layout/`, and `Core/UIRoot.lua` — never
in `SettingsUI/` or plugin page code. See `WOW_API_ENCAPSULATION.md`.

Allowed there does not mean reached for first. Inside a component, the raw API is for
what genuinely has no primitive: the frame itself, its scripts, textures, cursor math.
Everything with a primitive goes through the primitive:

- backdrop styling → `SuuUI.Backdrop.Apply` / `SetBg` / `SetBorder`, never `SetBackdrop`
  plus a hand-built table and hand-resolved tokens
- text → `Components.Text`, so the element re-measures when a `fontSize*` token changes
- `GetWidth` `GetHeight` `IsShown` `GetFrame` `SetSize` `Show` `Hide` →
  `Components.InstallBase`, never retyped on the metatable

And a component composes the components that already exist rather than rebuilding their
parts — `Notice` is a `Modal`; `Modal` itself is `Text` + `Input` + `Button` in
containers. Re-implementing a sibling's internals is the same duplication as inlining
raw frames in a page, one layer down.

**Writing a new component? Follow "Anatomy of a Component" in `coding-standards.md`.**
It carries the annotated skeleton every component in this directory is built from —
construction order, the `_paint()` / `ApplyTheme()` split, why the resize hook is
registered before the host container adopts the frame, and what `Destroy()` must free.
`Components/NavItem.lua` is the shortest complete example in the codebase.

**Shared API (all components):**
```lua
comp:SetSize(w, h)
comp:GetWidth() / comp:GetHeight()
comp:Show() / comp:Hide() / comp:IsShown()
comp:SetEnabled(bool)
comp:Destroy()
comp:GetFrame()
comp:ApplyTheme()
```

There is deliberately **no `comp:SetPoint`**. Components are positioned by adding them
to a container; they position their own internals with a host container. See
`LAYOUT_SYSTEM.md`.

**Every component must also:**
1. Emit the standard `SuuUI.UISignals` signals that apply to it — a component with a
   value emits `VALUE_CHANGED`, one that resizes emits `SIZE_CHANGED`, and so on.
2. Translate Blizzard scripts into signals internally. The script never escapes the
   component file; consumers connect to signals, not to `GetFrame():SetScript(...)`.
3. Cache token values in `ApplyTheme()` and re-read only there. If the new tokens
   change the element's own size — a font size token changing text metrics, say —
   `ApplyTheme()` must re-measure and emit `SIZE_CHANGED`, or the containing layout
   keeps the geometry it measured under the old theme. `Text` and `Slider` do this.
4. Clean up in `Destroy()`: `SuuUI.UISignals:DisconnectAll(self)` plus
   `SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)`.
5. **Have a spec** in `Tests/spec/` covering its geometry, token-driven sizing, every
   signal, disabled state, theme reaction, edge cases and teardown. A component without
   one is not finished. See `TESTING.md`.

**Missing a component?** Build it in `Components/<Name>.lua` rather than inlining raw
frames in a page. Register it in the `.toc`, write its spec in `Tests/spec/`, and
document it here.

**Shared primitives** (non-visual, consumed by the components above):
- `Backdrop` — `SuuUI.Backdrop.Apply(frame, { bg, border, borderWidth })` builds the
  standard bg+border backdrop; `SetBg` / `SetBorder` recolour without rebuilding it.
  `bg`/`border` take a token key, a literal `{r,g,b,a}`, or `false`/nil for fully
  transparent. `Theme:ApplyToFrame` delegates to it.
- `Base` — `SuuUI.Components.InstallBase(meta, field)` installs `GetWidth` `GetHeight`
  `IsShown` `GetFrame` `SetSize` `Show` `Hide` onto a component metatable, filling only
  the gaps so a custom override survives. `SetSize` never emits `SIZE_CHANGED`.

**Components:**
- `Frame` — base styled container. `variant`: `"bg"|"bgAlt"|"bgActive"|"transparent"`,
  `border = false` to drop the border.
- `Text` — FontString with token font/size/color. `font` (prop or `SetFont(path)`) pins an
  explicit face, overriding the font token while size and colour still follow tokens; it
  re-measures, so a taller face reports its new height. Only for text that must render in
  a face other than the theme's — a font picker previewing its options. Pass `nil` to
  follow the token again.
- `Button` — fully custom, animated hover/press states. Hugs its label: width and
  height are measured from the text plus token padding unless `w`/`h` are given
  (`minW`/`minH` set floors). Re-fits on `SetLabel` and on font token changes, and
  emits `SIZE_CHANGED` so the containing layout re-flows. Add it without `width`/
  `height` props to keep the hug. `variant`: `"danger"|"success"|"warning"` tints the
  border and label with the matching intent token; the background stays on the surface
  tokens so a variant reads as emphasis rather than a different control. Disabled state
  overrides the variant.
- `IconButton` — Button + texture slot.
- `NavItem` — selectable labelled row with hover/selected states, for nav lists.
- `Toggle` — animated sliding switch, no Blizzard checkbox.
- `Slider` — custom track + thumb, label, value display.
- `Dropdown` — custom panel, animated open/close. Shows the `colorBorderFocus` ring
  while hovered or open, like `Input`. Its arrow column is measured from the glyph via
  `TextMetrics`, not pinned to a space token, so it never truncates to an ellipsis. An
  option may carry `font = path` to render in that face — the font picker's preview. Row
  and button heights are then measured from the face rather than assumed equal, since a
  face's line height does not follow from the point size, and the panel is sized from the
  rows it actually laid out.
- `Input` — EditBox (Blizzard, unavoidable), themed styling.
- `ColorSwatch` — clickable colour square with token border, `GetHex()` helper.
- `ColorPicker` — custom HSV picker + hex input.
- `KeyCapture` — button that captures the next keypress into a binding string.
- `ScrollFrame` — custom scrollbar + masked content.
- `Tooltip` — cursor-following or frame-anchored, animated fade.
- `Divider` — horizontal/vertical line, optional label.
- `Modal` — dialog with optional input, container-composed. `confirmVariant` tints the
  confirm button with an intent token; `dismissOnly` drops the cancel button;
  `autoDestroy` frees the modal once it finishes hiding.
- `Notice` — one-shot dismissible message built on Modal. `tone` is
  `"warning"|"danger"|"success"` or nil. **Use this instead of printing errors to chat.**
  Self-destroying, so it is safe to call on every failure.
- `ClickAway` — non-visual helper; polls for clicks outside a panel only while armed.
  Reads the cursor with `Pixel.CursorIn(panel)`, not against `UIParent`.
- `Pixel` — non-visual, in `Core/`: the pixel grid. `Snap` / `Floor` / `Ceil` for geometry,
  `Line` for a thickness that must never round to zero, `CursorIn(frame)` for every hit
  test and drag. `Backdrop` uses `Line` for its edge and `Theme:GetControlHeight` uses
  `Ceil`, so a control never lands half a pixel short of its own text.
- `TextMetrics` — non-visual helper: `SuuUI.TextMetrics.Measure(text, font, size, flags)`
  returns the real width/height of a string. Use it for any fit-to-text sizing. A font
  string's own `GetStringWidth` is clamped to the width its layout assigned, so
  measuring a live label that is already truncated shrinks it further on every pass.

**Component-specific signals:**

| Component | Signal constant | Payload |
|---|---|---|
| `Input` | `Components.INPUT_SIGNALS.SUBMITTED` | `text` |
| `ColorPicker` | `Components.COLORPICKER_SIGNALS.COLOR_PICKED` | `r, g, b, a` |
| `ColorPicker` | `Components.COLORPICKER_SIGNALS.REQUEST_CLOSE` | — |
| `Modal` | `Components.MODAL_SIGNALS.CONFIRMED` | `inputValue` or `nil` |
| `Modal` | `Components.MODAL_SIGNALS.CANCELLED` | — |

---

## Settings UI

### Unified Window (`SettingsUI/SettingsWindow.lua`)

Opened via: `/suuui`, keybind (configurable), minimap button.

Layout: fixed left nav (plugin list) + right content area.
Nav auto-populates from all registered plugins in registration order.
Selecting a plugin renders its page via PageBuilder.

### Page Builder (`SettingsUI/PageBuilder.lua`)

Reads schema, maps each entry to a control renderer, mounts in a ScrollFrame.
Schema order = render order. Controls read/write through Settings API.
No plugin writes any UI code for standard settings.

---

## Plugin Authoring Contract

External addon checklist:

1. `.toc`: `## Dependencies: SuuUI`
2. On own `ADDON_LOADED`: call `SuuUI:CreatePlugin({...})`
3. In `onInit`: call `SuuUI.Settings:Register(id, schema)`
4. In `onInit`: subscribe to events via `SuuUI.Events:On(...)`
5. In `onEnable`: hide/modify default Blizzard UI elements
6. In `onDisable`: restore default Blizzard UI elements
7. Never call into another plugin directly — communicate via EventBus

---

## UI Layout Best Practices

**Golden Rule: Always use Container-based layouts. Never manually position UI elements.**

### Why Container-Based Layouts?

Manual positioning with `SetPoint` chains creates:
- **Fragile code** — one change breaks the entire layout
- **Inconsistent spacing** — hardcoded offsets don't respond to theme changes
- **Broken responsiveness** — layouts don't adapt to container size changes
- **Maintenance nightmares** — tracking Y offsets and cumulative gaps manually
- **Plugin incompatibility** — different plugins use different spacing/positioning styles

Container-based layouts provide:
- **Automatic positioning** — children arranged by layout algorithm
- **Responsive sizing** — `width="fill"` adapts to available space
- **Theme integration** — uses token-based gap and padding values
- **Maintainability** — add/remove children without recalculating positions
- **Consistency** — all plugins use the same layout patterns

### Correct Patterns

```lua
-- ✅ CORRECT: Container-based vertical list
local list = SuuUI.Layout:CreateContainer({
  parent  = scrollContent,
  layout  = "flow",
  dir     = "vertical",
  gap     = SuuUI.Theme:GetToken("spaceXs"),
  padding = {top=8, right=8, bottom=8, left=8},
})

for _, item in ipairs(items) do
  local row = CreateFrame("Frame", nil, scrollContent)
  row:SetHeight(32)
  list:Add(row, { width = "fill" })
end

-- ✅ CORRECT: Two-column grid
local grid = SuuUI.Layout:CreateContainer({
  parent = contentFrame,
  layout = "grid",
  cols   = 2,
  gap    = 8,
  padding= {top=8, right=8, bottom=8, left=8},
})

for _, setting in ipairs(settings) do
  local control = CreateSettingControl(setting)
  grid:Add(control:GetFrame())  -- auto-sized to fit grid
end

-- ✅ CORRECT: Horizontal button row
local buttonRow = SuuUI.Layout:CreateContainer({
  parent = footer,
  layout = "flow",
  dir    = "horizontal",
  gap    = 8,
})

buttonRow:Add(cancelBtn:GetFrame(), { width = 80, height = 24 })
buttonRow:Add(okBtn:GetFrame(), { width = 80, height = 24 })
```

### Anti-Patterns (Forbidden)

```lua
-- ❌ FORBIDDEN: Manual Y-offset tracking
local y = -8
for _, item in ipairs(items) do
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(200, 32)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  y = y - 32 - 4
end

-- ❌ FORBIDDEN: Manual SetPoint chains
header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
footer:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -8)

-- ❌ FORBIDDEN: Conditional positioning hacks
if needsScrollbar then
  row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
else
  row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
end
```

### When to Discuss Extensions

If you need layout behavior that isn't supported:

**Don't**: Implement manual positioning workarounds  
**Do**: Document the requirement and propose a generic solution

Examples of features worth discussing:
- "I need buttons centered in the container" → alignment support
- "I need items to wrap to next line" → wrapping flow layout
- "I need this panel to be 40% of parent width" → percentage sizing
- "I need minimum 200px but expand if space available" → min/max constraints

Bring these up, design a generic API, implement it in the layout system,
and document it for all plugins to use.

---

## Testing

Every component, layout strategy and core subsystem has a spec under `Tests/spec/`, run
with `lua Tests/run.lua` from the addon root. **No change to `Components/`, `Layout/`,
`Core/` or `SettingsUI/` is done until the suite passes and the new behaviour is covered.**

The suite loads the real addon into a sandbox against a simulated WoW client that solves
the actual anchor graph, so specs assert real pixel geometry rather than intent — where a
label sits, whether a thumb stays inside its track, whether two rows overlap. That is the
only way to verify a layout engine, since placement is the thing it produces.

Full contract, spec checklist and harness API: `TESTING.md`.

---

## Performance Rules

- No table allocations inside `OnUpdate` handlers.
- Use frame pool for any repeated UI element.
- `OnUpdate` handlers unregistered when idle, re-registered on demand.
- Token values cached in local upvalues inside component closures after `ApplyTheme`.
- No `string.format` in per-frame code — pre-build display strings.
- SavedVariables written only on `PLAYER_LOGOUT` or explicit user save.
- Lua files: no block comments in shipped code. Public API gets `---` doc comments only.
- Minimize global lookups in hot paths — alias globals to locals at file top.

---

## SavedVariables

```
SuuUIProfiles  -- all profiles, account-wide (## SavedVariablesPerCharacter: no)
SuuUIConfig    -- per-character: active profile name, window positions
```

---

## Naming Conventions

| Thing              | Convention                          |
|--------------------|-------------------------------------|
| Lua locals         | camelCase                           |
| Module upvalues    | camelCase                           |
| Public API keys    | PascalCase                          |
| Event names        | `SUUUI_SCREAMING_SNAKE`             |
| Plugin IDs         | `snake_case`                        |
| Token keys         | `camelCaseWithPrefix`               |
| Pool type IDs      | `"pluginId.frameRole"`              |
| Frame global names | `"SuuUI_" .. pluginId .. "_" .. role` |
