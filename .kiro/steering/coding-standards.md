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

**ALWAYS use the Container-based layout system. NEVER manually position UI elements.**

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
  gap     = T:GetToken("spaceSm"),      -- use space tokens for gaps
  padding = {
    top    = T:GetToken("spaceMd"),     -- use space tokens for padding
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
  },
})
container:Add(btn, { width = "fill", height = 32 })
container:Add(row, { width = "fill" })
```

**Spacing token usage:**
- Use `spaceSm` (4px) for tight spacing - list gaps, compact UIs
- Use `spaceMd` (8px) for standard spacing - most containers, panels
- Use `spaceLg` (16px) for loose spacing - section separation
- Use `spaceXl` (24px) for major spacing - page-level separation

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

- Prefer SuuUI component API over raw WoW API for any UI that touches the theme.
- Only use Blizzard templates when there is no reasonable alternative
  (EditBox for text input is the main exception).
- When hiding Blizzard frames, use `frame:Hide()` or `frame:UnregisterAllEvents()`.
  Do NOT nil them or `frame:SetParent(nil)` — this can cause taint.
- Check for frame existence before operating: `if frame and frame.Hide then`.

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
