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
│   ├── EventBus.lua      -- internal pub/sub system
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
│   ├── Container.lua     -- base container with layout support
│   ├── FlowLayout.lua    -- horizontal / vertical flow
│   ├── GridLayout.lua    -- fixed grid
│   └── AnchorLayout.lua  -- manual anchor-based layout
├── Components/
│   ├── Frame.lua         -- styled base frame (border, bg, radius)
│   ├── Text.lua          -- styled FontString wrapper
│   ├── Button.lua        -- full custom button (no Blizzard template)
│   ├── IconButton.lua
│   ├── Toggle.lua        -- custom checkbox/toggle
│   ├── Slider.lua        -- custom slider
│   ├── Dropdown.lua      -- custom dropdown
│   ├── Input.lua         -- EditBox wrapper (Blizzard required)
│   ├── ColorPicker.lua   -- custom HSV color picker
│   ├── ScrollFrame.lua   -- scroll container
│   ├── Tooltip.lua       -- custom tooltip
│   └── Divider.lua
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
  padding = {top=8, right=8, bottom=8, left=8},
})

-- Add child with flexible sizing
c:Add(child, { width = "fill", height = 32 })  -- fill width, fixed height
c:Add(child, { width = 200 })                  -- fixed width, natural height
c:Add(child)                                   -- natural dimensions

c:Remove(child)
c:Layout()            -- auto-called on Add/Remove
c:SetSize(w, h)
c:GetContentSize()    -- returns computed w, h of all children
```

**Layout Properties:**
- `width = "fill"` — child takes available horizontal space
- `width = number` — fixed width in pixels
- `height = "fill"` — child takes available vertical space (flow layouts only)
- `height = number` — fixed height in pixels
- Omit property to use child's natural size

### Layout Strategies

- **FlowLayout** (`Layout/FlowLayout.lua`): horizontal or vertical flow with flexible sizing.
  - Supports `width="fill"` to stretch children to container width
  - Supports `height="fill"` to distribute available vertical space among fill children
  - Calculates available space after accounting for fixed-size children and gaps
  - Respects padding on all 4 sides
- **GridLayout** (`Layout/GridLayout.lua`): fixed columns, equal or weighted cells.
  - Automatically calculates column width based on container width, padding, and gap
  - Respects padding on all 4 sides
- **AnchorLayout** (`Layout/AnchorLayout.lua`): children provide anchor descriptors,
  engine resolves and applies them — avoids manual SetPoint chains in plugin code.

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
- No alignment control (left/center/right, top/middle/bottom) within containers
- No wrapping in flow layouts
- No percentage-based sizing (`width = "50%"`)
- No min/max size constraints
- No margin (distinct from container padding)
- No z-index/layer control for overlapping children

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

**Shared API (all components):**
```lua
comp:SetSize(w, h)
comp:SetPoint(...)
comp:Show() / comp:Hide() / comp:IsShown()
comp:SetEnabled(bool)
comp:Destroy()
comp:GetFrame()
comp:ApplyTheme()
```

**Components:**
- `Frame` — base styled container (bg, border, simulated corner radius).
- `Text` — FontString with token font/size/color.
- `Button` — fully custom, animated hover/press states.
- `IconButton` — Button + texture slot.
- `Toggle` — animated sliding switch, no Blizzard checkbox.
- `Slider` — custom track + thumb, label, value display.
- `Dropdown` — custom panel, animated open/close, keyboard nav.
- `Input` — EditBox (Blizzard, unavoidable), themed styling.
- `ColorPicker` — custom HSV picker + hex input.
- `ScrollFrame` — custom scrollbar + masked content.
- `Tooltip` — cursor-following or frame-anchored, animated fade.
- `Divider` — horizontal/vertical line, optional label.

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
