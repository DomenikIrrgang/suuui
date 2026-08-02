# SuuUI Plugin Authoring Guide

## What is a Plugin?

A plugin is any addon that registers with SuuUI Core via `SuuUI:CreatePlugin(...)`.
It can live inside `SuuUI/Plugins/` (bundled) or be a completely separate addon
folder with `## Dependencies: SuuUI` in its `.toc`.

---

## Minimal External Plugin Structure

```
MyPlugin/
├── MyPlugin.toc
└── MyPlugin.lua
```

**MyPlugin.toc:**
```
## Interface: 20504
## Title: MyPlugin
## Dependencies: SuuUI
## SavedVariables:

MyPlugin.lua
```

**MyPlugin.lua:**
```lua
local Events = CreateFrame("Frame")
Events:RegisterEvent("ADDON_LOADED")
Events:SetScript("OnEvent", function(_, event, name)
  if name ~= "MyPlugin" then return end

  local plugin = SuuUI:CreatePlugin({
    id      = "my_plugin",
    name    = "My Plugin",
    version = "1.0",

    onInit = function(p)
      SuuUI.Settings:Register("my_plugin", {
        { key="enabled", label="Enable", type="toggle", default=true },
      })
      SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(id, key, val)
        if id == "my_plugin" and key == "enabled" then
          if val then p:Enable() else p:Disable() end
        end
      end, "my_plugin")
    end,

    onEnable = function(p)
      -- hide/modify Blizzard frames here
    end,

    onDisable = function(p)
      -- restore Blizzard frames here
    end,
  })
end)
```

---

## CreatePlugin Options

```lua
SuuUI:CreatePlugin({
  id       = string,   -- required, unique snake_case, used as namespace key
  name     = string,   -- required, shown in settings nav
  version  = string,   -- optional, shown in settings nav
  onInit   = function(plugin) end,    -- called once on PLAYER_LOGIN
  onEnable = function(plugin) end,    -- called when plugin becomes active
  onDisable= function(plugin) end,    -- called when plugin is deactivated
})
```

Returns a **plugin handle** (see below).

---

## Plugin Handle API

```lua
--- Returns the plugin's live settings values from the active profile.
-- @return table
plugin:GetSettings()

--- Returns the plugin's raw profile sub-table.
-- @return table
plugin:GetProfile()

--- Returns whether the plugin is currently enabled.
-- @return bool
plugin:IsEnabled()

--- Enables the plugin, calls onEnable if not already enabled.
plugin:Enable()

--- Disables the plugin, calls onDisable if enabled.
plugin:Disable()
```

---

## Settings Schema

Register in `onInit`. Schema controls the auto-generated settings page.

```lua
SuuUI.Settings:Register("my_plugin", {
  { key="myToggle",   label="Enable Feature",  type="toggle",   default=true },
  { key="mySlider",   label="Size",            type="slider",   default=16, min=8, max=32, step=1 },
  { key="myColor",    label="Color",           type="color",    default={1,1,1,1} },
  { key="myDrop",     label="Style",           type="dropdown", default="solid",
    options={ {value="solid",label="Solid"}, {value="flat",label="Flat"} } },
  { key="myText",     label="Label",           type="text",     default="" },
  { key="myBind",     label="Toggle Keybind",  type="keybind",  default="" },
  { key="",           label="Advanced",        type="section" },
})
```

Types: `toggle` `slider` `dropdown` `color` `text` `keybind` `section`

Optional field on any entry:
```lua
validate = function(value) return true end
-- or: return false, "Error message shown in UI"
```

---

## Settings API

```lua
SuuUI.Settings:Get("my_plugin", "myToggle")        -- current value
SuuUI.Settings:Set("my_plugin", "myToggle", false)  -- write + fire event
SuuUI.Settings:Reset("my_plugin", "myToggle")       -- reset to default
SuuUI.Settings:ResetAll("my_plugin")
```

---

## Event Bus

Plugins communicate via events, never by direct calls into each other.

```lua
-- Subscribe
SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pluginId, key, val, old)
  -- ...
end, "my_plugin")  -- owner tag used for cleanup

-- Unsubscribe all for owner
SuuUI.Events:Off("SUUUI_SETTING_CHANGED", "my_plugin")

-- Fire a custom event (prefix with your plugin id)
SuuUI.Events:Emit("MY_PLUGIN_SOMETHING_HAPPENED", payload)

-- Subscribe once
SuuUI.Events:Once("SUUUI_PROFILE_LOADED", function() end, "my_plugin")
```

**Built-in events:**

| Event | Payload |
|---|---|
| `SUUUI_PROFILE_LOADED` | `profileName` |
| `SUUUI_THEME_CHANGED` | `themeName` |
| `SUUUI_SETTING_CHANGED` | `pluginId, key, value, oldValue` |
| `SUUUI_PLUGIN_ENABLED` | `pluginId` |
| `SUUUI_PLUGIN_DISABLED` | `pluginId` |

---

## Using the Frame Pool

Register a pool type in `onInit`, use it wherever you create repeated frames.

```lua
-- Register
SuuUI.Pool:Register("my_plugin.row", function(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(200, 24)
  -- initial setup only
  return f
end)

-- Acquire (called when you need a frame)
local row = SuuUI.Pool:Acquire("my_plugin.row", containerFrame)
row:Show()

-- Release (called when you no longer need it)
SuuUI.Pool:Release("my_plugin.row", row)

-- Release all (e.g. on data refresh)
SuuUI.Pool:ReleaseAll("my_plugin.row")
```

Pool type IDs must be prefixed with your plugin id.

---

## Using the Component Library

```lua
local T = SuuUI.Theme  -- alias for token access

-- Styled frame
local frame = SuuUI.Components.Frame({
  w=200, h=100,
}, parentFrame)

-- Button
local btn = SuuUI.Components.Button({
  label   = "Click Me",
  onClick = function() print("clicked") end,
}, parentFrame)

-- Text
local lbl = SuuUI.Components.Text({
  text  = "Hello",
  size  = "md",   -- "sm"|"md"|"lg"
  color = "text", -- token suffix: "text"|"textMuted"|"accent"
}, parentFrame)

-- All components share:
comp:SetSize(w, h)
comp:SetPoint(point, relativeTo, relativePoint, x, y)
comp:Show() / comp:Hide()
comp:SetEnabled(bool)
comp:Destroy()
comp:GetFrame()
```

---

## Using the Layout Engine

**CRITICAL: All plugin UI must use the Container-based layout system.**

```lua
local T = SuuUI.Theme

-- Container with vertical flow
local col = SuuUI.Layout:CreateContainer({
  parent  = contentFrame,
  layout  = "flow",
  dir     = "vertical",
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = T:GetToken("spaceMd"),
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
  },
})

-- Add children with flexible sizing
col:Add(headerFrame, { width = "fill", height = 32 })  -- stretches to full width
col:Add(contentFrame, { width = "fill" })              -- fills width, natural height
col:Add(buttonFrame, { width = 120, height = 24 })    -- fixed size

-- positions recalculate automatically

-- Window
local win = SuuUI.Layout:CreateWindow({
  id    = "my_plugin.mainWindow",
  title = "My Plugin",
  w=400, h=300,
})
local content = win:GetContentFrame()
win:Show()
```

**Layout Properties:**

When adding children to containers, pass optional layout properties:

```lua
container:Add(frame, {
  width  = "fill" | number,  -- "fill" = take available space, number = fixed px
  height = "fill" | number,  -- "fill" = distribute space (flow only)
})
```

- `width = "fill"` — stretches to container width (respects padding, all layouts)
- `height = "fill"` — distributes available vertical space (flow layouts only)
- Fixed numbers — explicit pixel dimensions
- Omit property — uses frame's natural size

**Spacing Tokens:**

Always use theme tokens for consistent spacing:

```lua
local T = SuuUI.Theme
gap     = T:GetToken("spaceSm")   -- 4px:  tight spacing (list gaps)
gap     = T:GetToken("spaceMd")   -- 8px:  standard spacing (most containers)
gap     = T:GetToken("spaceLg")   -- 16px: loose spacing (section separation)
gap     = T:GetToken("spaceXl")   -- 24px: major spacing (page-level)
```

Use the same tokens for both `gap` and `padding` to maintain visual rhythm.

**NEVER manually position UI with SetPoint chains:**

```lua
-- ❌ FORBIDDEN
btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -10)
for i, item in ipairs(items) do
  item:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
  y = y - height - gap
end

-- ✅ REQUIRED
local container = SuuUI.Layout:CreateContainer({...})
for i, item in ipairs(items) do
  container:Add(item, { width = "fill" })
end
```

**If the layout system doesn't support what you need:**

1. **Document the requirement** — what layout behavior is missing?
2. **Bring it up for discussion** — don't implement workarounds
3. **Extend the system generically** — make it reusable for all plugins
4. **Update architecture docs** — document the new capability

Examples of features to discuss if needed:
- Alignment (center/right, middle/bottom)
- Wrapping flow layouts  
- Percentage-based sizing
- Min/max constraints
- Nested complex layouts

---

## Using Animations

```lua
-- Fade in a frame
SuuUI.Anim.Presets.FadeIn(myFrame, 0.2)

-- Custom animation
local anim = SuuUI.Anim:New({
  target   = myFrame,
  property = "alpha",
  from=0, to=1,
  duration = 0.25,
  easing   = "easeOut",
})
anim:Play()

-- Sequence
SuuUI.Anim:Sequence({
  SuuUI.Anim:New({ target=f, property="alpha", from=0, to=1, duration=0.2 }),
  SuuUI.Anim:New({ target=f, property="y",     from=-10, to=0, duration=0.15 }),
})
```

---

## Hiding Blizzard UI

Do this in `onEnable`, undo in `onDisable`. Never nil Blizzard frames.

```lua
onEnable = function()
  if MinimapCluster then MinimapCluster:Hide() end
end,
onDisable = function()
  if MinimapCluster then MinimapCluster:Show() end
end,
```

For frames that re-show themselves, unregister their events:
```lua
frame:UnregisterAllEvents()
frame:Hide()
```

---

## Profile Data

Plugin-scoped data lives at `profile.plugins["my_plugin"]`.
Access via `SuuUI.Settings:Get/Set` for tracked settings, or directly via
`plugin:GetProfile()` for arbitrary plugin-private data.

Do not write raw tables to SVs yourself — they are written on PLAYER_LOGOUT.

---

## Rules Summary

1. Always prefix pool IDs, event names, and frame names with your plugin id.
2. Never call another plugin's functions directly.
3. Never allocate tables in OnUpdate.
4. Always clean up (Destroy components, Off events) in onDisable.
5. Restore all Blizzard frames in onDisable.
6. Register settings schema in onInit, not at file load time.
7. **ALWAYS use Container-based layouts. NEVER manually position UI elements.**
8. **If a layout feature is missing, discuss and extend the system — don't hack workarounds.**
