# SuuUI Coding Standards

## File Structure

Every Lua file follows this layout, in order:

```lua
-- 1. Local aliases for globals used in this file (perf: avoids global lookup)
local pairs, ipairs, type = pairs, ipairs, type
local tinsert, tremove = table.insert, table.remove

-- 2. Module upvalue
local M = {}

-- 3. Private helpers (no doc comment needed)

-- 4. Public API functions (--- doc comment required)

-- 5. Return or registration
return M
-- or: SuuUI.MyModule = M
```

## UI Layout Rules

**Everything is positioned by the layout engine. `SetPoint` lives only in the four
layout strategies** (`Layout/{Flow,Grid,Stack,Anchor}Layout.lua`) — not in
`SettingsUI/`, not in plugins, and not in components. Components lay out their own
internals with a host container:

```lua
local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
box:Add(label, { align = "center", valign = "center" })
```

No public handle exposes `SetPoint`. If a layout algorithm or property is missing,
implement it in the engine — see `LAYOUT_SYSTEM.md`.

```lua
-- ❌ FORBIDDEN: Manual positioning
btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -10)
row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
y = y - height - gap

-- ✅ REQUIRED: Container-based layout with theme tokens
local T = SuuUI.Theme
local container = SuuUI.Layout:CreateContainer({
  parent  = parent,
  layout  = "flow",
  dir     = "vertical",
  gap     = T:GetToken("spaceXs"),      -- use space tokens for gaps
  padding = {
    top    = T:GetToken("spaceSm"),     -- use space tokens for padding
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
  },
})
container:Add(btn, { width = "fill", height = 32 })
container:Add(row, { width = "fill" })
```

**Spacing token usage:**
- Use `spaceXs` (4px) for tight spacing - list gaps, compact UIs
- Use `spaceSm` (8px) for standard spacing - most containers, panels
- Use `spaceMd` (12px) for roomier rows and insets
- Use `spaceLg` (16px) for loose spacing - section separation
- Use `spaceXl` (24px) for major spacing - page-level separation

**Never hardcode a control height.** Font size tokens are user-editable, so a control
pinned to a literal height clips its own text once the font grows past it. Read the size
tokens instead, and floor text-bearing controls against the font metrics:

```lua
-- ❌ FORBIDDEN
row:Add(input, { width = 140, height = 22 })

-- ✅ REQUIRED: the component derives its own height from tokens
row:Add(input, { width = 140 })

-- ✅ REQUIRED when a container needs the number itself
local h = T:GetControlHeight("sizeControlLg")   -- max(token, fontSizeMd + spaceXs*2)
local n = T:GetToken("sizeControlSm")           -- no text: the token as-is
```

**Layout properties you MUST use:**
- `width = "fill"` — stretch to container width (respects padding)
- `width = number` — fixed pixel width
- `height = "fill"` — distribute vertical space (flow) or fill container (horizontal)
- `height = number` — fixed pixel height
- Omit property — use child's natural size

**When you encounter a layout need not supported by the current system:**
1. **STOP** — do not implement manual positioning workarounds
2. **DOCUMENT** — clearly describe what layout behavior you need
3. **DISCUSS** — bring it up for architectural discussion
4. **IMPLEMENT** — extend the layout system generically after agreement
5. **APPLY** — use the new generic solution

Example missing features to discuss:
- Alignment within container (left/center/right, top/middle/bottom)
- Wrapping flow layouts
- Percentage-based sizing (`width = "50%"`)
- Min/max size constraints
- Absolute positioning within container
- Z-order/layering control

## Comments

Only `---` single-line doc comments on **public API functions**.
No block comments (`--[[ ]]`) in shipped code.
No inline comments on obvious code.

Doc comment format:
```lua
--- Brief description of what the function does.
-- @param name string  Description
-- @param value any    Description
-- @return bool
function M:DoThing(name, value) end
```

## Performance Rules

- **No table allocations in OnUpdate.** Pre-allocate scratch tables as upvalues.
- **Unregister OnUpdate when idle.** Use a shared ticker pattern:
  ```lua
  local frame = CreateFrame("Frame")
  local function onUpdate(_, dt) ... end
  -- enable:  frame:SetScript("OnUpdate", onUpdate)
  -- disable: frame:SetScript("OnUpdate", nil)
  ```
- **Alias globals at file top** for any global used more than once in the file.
- **Pre-build strings.** Do not call `string.format` per frame. Build display
  strings only when the underlying value changes.
- **Cache token values** in local upvalues inside component closures.
  Re-read only in `ApplyTheme()`, which is only called on theme change.
- **Avoid string concatenation in loops.** Use a table + `table.concat`.

## SavedVariables

- Write only on `PLAYER_LOGOUT` or explicit user action (Save button).
- Never mutate SV tables directly from component code — go through
  `SuuUI.Settings:Set` or `SuuUI.Profiles` API.

## Error Handling

- Use `assert(condition, "SuuUI: message")` for programmer errors (wrong API usage).
- Use `SuuUI.Debug(msg)` for non-fatal warnings, gated by debug flag.
- Never `error()` inside event callbacks or OnUpdate — it will freeze the client.
  Use `pcall` when calling plugin-provided callbacks:
  ```lua
  local ok, err = pcall(plugin.onInit, plugin)
  if not ok then SuuUI.Debug("Plugin init failed: " .. tostring(err)) end
  ```

## Frame Naming

Global frame names must follow: `"SuuUI_" .. pluginId .. "_" .. role`
Example: `"SuuUI_minimap_container"`, `"SuuUI_unitframes_playerFrame"`

Anonymous frames (pool frames, throwaway containers) use `nil` as name.

## Module Registration Pattern

Each subsystem file assigns itself onto the `SuuUI` namespace:
```lua
local M = {}
-- ... implementation ...
SuuUI.Theme = M
```

The `.toc` file controls load order. Subsystems must not `require` each other.
Dependencies are implicit via load order.

## WoW API Usage

**Raw WoW UI API is confined to `Components/`, `Layout/`, and `Core/UIRoot.lua`.**
UI construction code (`SettingsUI/`, plugin pages, controls) composes components and
containers only. Positioning calls are tighter still: only the layout strategies.
Full rules in `WOW_API_ENCAPSULATION.md`.

```lua
-- ❌ FORBIDDEN in UI construction code
local row = CreateFrame("Frame", nil, parent)
local tex = row:CreateTexture(nil, "ARTWORK")
tex:SetColorTexture(0.3, 0.3, 0.3, 1)
row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
row:SetFrameStrata("FULLSCREEN_DIALOG")
row:EnableMouse(true)
row:SetScript("OnClick", fn)

-- ✅ REQUIRED
local C = SuuUI.Components
local swatch = C.ColorSwatch({ value = T:GetToken("colorBg") }, parent)
container:Add(swatch:GetFrame(), { width = 24, height = 24 })
SuuUI.UISignals:Connect(swatch, SuuUI.UISignals.SIGNALS.CLICKED, openPicker)
```

Narrow exceptions: a bare unstyled grouping frame handed straight to a container,
`GetCursorPosition()` inside a component, and game data APIs in plugins.

- Only use Blizzard templates when there is no reasonable alternative
  (EditBox for text input is the main exception) — and wrap it in a component.
- When hiding Blizzard frames, use `frame:Hide()` or `frame:UnregisterAllEvents()`.
  Do NOT nil them or `frame:SetParent(nil)` — this can cause taint.
- Check for frame existence before operating: `if frame and frame.Hide then`.
- If a needed widget does not exist, build it in `Components/` — do not inline it.

## UI Signals

**Never use Blizzard frame scripts to notify other UI elements.** Use
`SuuUI.UISignals`. Full contract in `UI_SIGNALS.md`.

```lua
-- ❌ FORBIDDEN: Blizzard script as UI wiring
container:GetFrame():SetScript("OnSizeChanged", function(_, w, h) resizeScroll(h) end)
toggle:GetFrame():SetScript("OnMouseUp", handler)

-- ✅ REQUIRED: signals
local S = SuuUI.UISignals
S:Connect(container, S.SIGNALS.SIZE_CHANGED, function(w, h) resizeScroll(h) end)
S:Connect(toggle, S.SIGNALS.VALUE_CHANGED, function(new, old) handler(new) end)
```

Components emit; consumers connect. Inside a component, translate the Blizzard script
into an emit:

```lua
hit:SetScript("OnMouseUp", function()
  local old = self._value
  self._value = not old
  self:_render()
  SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.VALUE_CHANGED, self._value, old)
end)
```

Always disconnect in `Destroy()`:
```lua
function CompMeta:Destroy()
  SuuUI.UISignals:DisconnectAll(self)
  SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end
```

Use `SuuUI.Events` for addon-wide state (theme, profile, settings) and
`frame:RegisterEvent` for WoW game data. Neither replaces UISignals for UI wiring.

## Table Utilities

A small set of table helpers lives in `Core/Init.lua` as `SuuUI.Utils`:

```lua
SuuUI.Utils.DeepCopy(t)          -- recursive copy, no metatables
SuuUI.Utils.Merge(target, src)   -- shallow merge src into target
SuuUI.Utils.Find(t, predFn)      -- returns first matching value
SuuUI.Utils.Keys(t)              -- returns array of keys
```

Do not implement these inline elsewhere.

## Metatables

Component handles use metatables for method dispatch. The pattern:
```lua
local CompMeta = { __index = CompMeta }

local function CreateComp(props, parent)
  local self = setmetatable({}, CompMeta)
  -- ...
  return self
end
```

Do not use inheritance chains deeper than one level.

## File Size Discipline

Target: **< 200 lines per file** for component files, **< 150 lines** for core files.
If a file grows beyond this, split into a `-Internal.lua` helper file.
Fewer lines = faster load. Every byte loaded is read from disk at login.
