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
│   ├── Theme.lua         -- token system, theme registry, active theme
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
│   └── Modal.lua         -- dialog with optional input
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
└── Themes/
    ├── Default.lua        -- read-only default dark theme
    └── Modern.lua         -- read-only modern theme (ships as default active)
```

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
  onInit   = function(p) end,  -- called once after all addons load
  onEnable = function(p) end,  -- called when plugin is enabled
  onDisable= function(p) end,  -- called when plugin is disabled
})

-- Returned plugin handle methods
plugin:GetSettings()    -- returns plugin's live settings table
plugin:GetProfile()     -- returns plugin's profile sub-table
plugin:IsEnabled()
plugin:Enable()
plugin:Disable()
```

The core calls `onInit` during `ADDON_LOADED`, then `onEnable`/`onDisable`
as appropriate. Plugins must NOT assume load order of other plugins.

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

Flat token table. Token names: camelCase with category prefix.

Categories: `color`, `font`, `space`, `size`, `border`, `anim`

Token aliases: a token value that is a string resolves to another token key.
Example: `tokens.colorAccent = "colorBlue400"` → `Theme:GetToken("colorAccent")`
returns the value of `colorBlue400`. Aliases enable cascading theme changes.

Example tokens:
```lua
-- Colors (RGBA arrays)
colorBg        = {0.08, 0.08, 0.10, 0.95}
colorBgAlt     = {0.11, 0.11, 0.14, 0.95}
colorBgHover   = {0.15, 0.15, 0.18, 0.95}
colorBlue400   = {0.25, 0.55, 1.00, 1.00}
colorAccent    = "colorBlue400"          -- alias
colorText      = {0.92, 0.92, 0.92, 1.00}
colorTextMuted = {0.55, 0.55, 0.60, 1.00}
colorBorder    = {0.20, 0.20, 0.24, 1.00}
-- Fonts
fontSizeSm     = 11
fontSizeMd     = 13
fontSizeLg     = 15
fontFamilyMain = "Fonts\\FRIZQT__.TTF"
-- Spacing
spaceSm        = 4
spaceMd        = 8
spaceLg        = 16
spaceXl        = 24
-- Note: Use space tokens for both gaps (between items) and padding (container insets)
-- Border
borderWidth    = 1
borderRadius   = 4    -- simulated via corner textures
-- Animation durations (seconds)
animFast       = 0.15
animMid        = 0.25
animSlow       = 0.40
```

Built-in themes are read-only. User themes stored in profile under
`profile.themes[name]` as a partial token override table.

**API:**
```lua
SuuUI.Theme:GetToken(key)                       -- resolves aliases
SuuUI.Theme:SetActive(name)                     -- fires SUUUI_THEME_CHANGED
SuuUI.Theme:GetActive()
SuuUI.Theme:List()
SuuUI.Theme:CreateUserTheme(name, baseTheme)
SuuUI.Theme:DeleteUserTheme(name)               -- error on built-ins
SuuUI.Theme:SetUserToken(themeName, key, value)
SuuUI.Theme:ApplyToFrame(frame)                 -- utility: styles bg+border
```

Components listen for `SUUUI_THEME_CHANGED` and call `ApplyTheme()` internally.

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

**These four files are the only place in the addon that calls `SetPoint`.**

- **FlowLayout** (`Layout/FlowLayout.lua`): horizontal or vertical flow with flexible sizing.
  - `width="fill"` / `height="fill"` distribute remaining main-axis space
  - `align` gives cross-axis placement (`start`/`center`/`end`/`stretch`)
  - Respects padding on all 4 sides
- **GridLayout** (`Layout/GridLayout.lua`): fixed columns, equal cells.
  - Column width derived from container width, padding, and gap
- **StackLayout** (`Layout/StackLayout.lua`): overlays children on the container box.
  - `inset` (number or per-edge table), `align`, `valign`, explicit `width`/`height`
  - Replaces `SetAllPoints`, centred labels, edge-spanning text, and inset icons
  - This is what components use internally
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
3. Cache token values in `ApplyTheme()` and re-read only there.
4. Clean up in `Destroy()`: `SuuUI.UISignals:DisconnectAll(self)` plus
   `SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)`.

**Missing a component?** Build it in `Components/<Name>.lua` rather than inlining raw
frames in a page. Register it in the `.toc` and document it here.

**Components:**
- `Frame` — base styled container. `variant`: `"bg"|"bgAlt"|"bgActive"|"transparent"`,
  `border = false` to drop the border.
- `Text` — FontString with token font/size/color.
- `Button` — fully custom, animated hover/press states.
- `IconButton` — Button + texture slot.
- `NavItem` — selectable labelled row with hover/selected states, for nav lists.
- `Toggle` — animated sliding switch, no Blizzard checkbox.
- `Slider` — custom track + thumb, label, value display.
- `Dropdown` — custom panel, animated open/close.
- `Input` — EditBox (Blizzard, unavoidable), themed styling.
- `ColorSwatch` — clickable colour square with token border, `GetHex()` helper.
- `ColorPicker` — custom HSV picker + hex input.
- `KeyCapture` — button that captures the next keypress into a binding string.
- `ScrollFrame` — custom scrollbar + masked content.
- `Tooltip` — cursor-following or frame-anchored, animated fade.
- `Divider` — horizontal/vertical line, optional label.
- `Modal` — dialog with optional input, container-composed.
- `ClickAway` — non-visual helper; polls for clicks outside a panel only while armed.

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
  gap     = SuuUI.Theme:GetToken("spaceSm"),
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
