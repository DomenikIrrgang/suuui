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
      -- Watch the key, do not filter the global event. The callback also runs on
      -- profile switches, and `immediate` runs it now with the current value.
      SuuUI.Settings:Watch("my_plugin", "enabled", function(val)
        if val then p:Enable() else p:Disable() end
      end, "my_plugin", { immediate = true })
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
  onInit   = function(plugin) end,    -- exactly once, see below
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
SuuUI.Settings:Get("my_plugin", "myToggle")         -- current value, else the default
SuuUI.Settings:Set("my_plugin", "myToggle", false)  -- write + notify
SuuUI.Settings:Reset("my_plugin", "myToggle")       -- reset to default
SuuUI.Settings:ResetAll("my_plugin")
```

**Never cache a setting in your own variable.** Read it with `Get` when you need it, and
subscribe with `Watch` when you need to react. A local copy is a second source of truth,
and it goes stale the first time the value changes by a route you did not think about —
the settings panel, a slash command, a profile switch, another plugin.

```lua
SuuUI.Settings:Watch("my_plugin", "barHeight", function(val)
  myBar:SetHeight(val)
end, "my_plugin", { immediate = true })
```

- The callback gets the effective value, and also fires on profile switches.
- `{ immediate = true }` runs it once now, so the same line handles first paint.
- The `owner` string ("my_plugin" here) is how you unsubscribe. **Drop your watchers when
  the thing they drive goes away** — `SuuUI.Settings:Unwatch("my_plugin")` in `onDisable`
  if you tear your frames down there. A watcher outlives the frame it updates.

Use `transient = true` on a schema entry for state that should not survive `/reload`
(a mode the player is currently in, not a preference they configured).

See `architecture.md` §5b for the full contract.

---

## Fonts

The font face is a theme token, so text you build from `Components.Text` already follows
whatever the user picked — you never set a font yourself. If your plugin needs to offer
its own font choice, read the registry rather than hardcoding paths:

```lua
local dd = C.Dropdown({ options = SuuUI.Fonts:Options() }, parent)
-- store the name; resolve it only when you need a path
local path = SuuUI.Fonts:Path(SuuUI.Settings:Get("my_plugin", "font"))
```

`Options()` covers the client's own faces, the locale's, and anything
`LibSharedMedia-3.0` exposes if the player has it. Bundling a font with your addon? Call
`SuuUI.Fonts:Register("My Font", "Interface/AddOns/MyPlugin/fonts/mine.ttf")` in `onInit`
and it joins the list everywhere — registered fonts survive the login rescan.

To show each option in the face it names, hand the dropdown a `font` per option:

```lua
local options = SuuUI.Fonts:Options()
for _, opt in ipairs(options) do opt.font = SuuUI.Fonts:Path(opt.value) end
C.Dropdown({ options = options }, parent)
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

**To react to one of your settings, use `Settings:Watch` instead** (see Settings API
above). `SUUUI_SETTING_CHANGED` fires for every write anywhere in the addon, so a
per-key listener has to filter it, gets no initial value, and needs a second
`SUUUI_PROFILE_LOADED` subscription to survive a profile switch.

**Built-in events:**

| Event | Payload |
|---|---|
| `SUUUI_PROFILE_LOADED` | `profileName` |
| `SUUUI_THEME_CHANGED` | `themeName` |
| `SUUUI_FONTS_CHANGED` | — (the available font list grew or shrank) |
| `SUUUI_PIXEL_GRID_CHANGED` | `grid` (resolution or UI scale moved the pixel grid) |
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

-- All components share (note: no SetPoint — containers do the positioning):
comp:SetSize(w, h)
comp:GetWidth() / comp:GetHeight()
comp:Show() / comp:Hide() / comp:IsShown()
comp:SetEnabled(bool)
comp:Destroy()
comp:GetFrame()
comp:ApplyTheme()
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
  gap     = T:GetToken("spaceXs"),
  padding = {
    top    = T:GetToken("spaceSm"),
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
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
container:Add(child, {
  width  = "fill" | number,  -- "fill" = take available space, number = fixed px
  height = "fill" | number,  -- "fill" = distribute space (flow only)
  align  = "start" | "center" | "end" | "stretch",  -- cross-axis alignment
})
```

- `width = "fill"` — stretches to container width (respects padding, all layouts)
- `height = "fill"` — distributes available vertical space (flow layouts only)
- `align` — cross-axis placement; also settable on the container for all children
- Fixed numbers — explicit pixel dimensions
- Omit property — uses child's natural size

`Add()` takes a raw frame, a component handle, or another container. Pass the handle
where you have one — the container unwraps it and can listen to its signals.

A label-left / control-right row is a horizontal flow where the label fills:

```lua
local row = SuuUI.Layout:CreateContainer({
  parent = parent, layout = "flow", dir = "horizontal",
  gap = T:GetToken("spaceSm"), align = "center", h = 28,
})
row:Add(label,  { width = "fill" })
row:Add(toggle, { width = 36, height = 18 })
```

Set `fill = true` on a container to anchor it to every side of its parent and track
parent resizes. Leave `h` unset and the container hugs its content, reporting the new
height through `SIZE_CHANGED` — no manual height maths anywhere.

**Spacing Tokens:**

Always use theme tokens for consistent spacing:

```lua
local T = SuuUI.Theme
gap     = T:GetToken("spaceXs")   -- 4px:  tight spacing (list gaps)
gap     = T:GetToken("spaceSm")   -- 8px:  standard spacing (most containers)
gap     = T:GetToken("spaceMd")   -- 12px: roomier rows and insets
gap     = T:GetToken("spaceLg")   -- 16px: loose spacing (section separation)
gap     = T:GetToken("spaceXl")   -- 24px: major spacing (page-level)
```

Use the same tokens for both `gap` and `padding` to maintain visual rhythm.

**Size Tokens:**

Never hardcode a control height. Font sizes are user-editable, so a literal height clips
its own text once the font grows past it. Omit `height` and let the component size itself
from tokens, or read the token when your container needs the number:

```lua
row:Add(input, { width = 140 })                       -- component derives its height
local h = T:GetControlHeight("sizeControlLg")         -- text-bearing: floored by font
local n = T:GetToken("sizeControlSm")                 -- no text: token as-is
```

`sizeControlSm` / `Md` / `Lg`, `sizeRow`, `sizeNavRow`, `sizeTitleBar`, `sizeIcon`,
`sizeScrollbar`. See `LAYOUT_SYSTEM.md` for what each is used for.

---

## Pixel Perfect: What You Get and What You Must Not Do

The UI is laid out in units, not pixels — one unit spans `physicalHeight / 768` pixels — so
`Core/Pixel.lua` scales the UI root to a whole-pixel grid and the layout strategies snap
every coordinate onto it. **You get this for free**: build with containers and components
and your plugin is crisp at every resolution. A fractional width passed to `Add` comes back
rounded, so assert geometry rather than the number you passed.

Two things will break it, so don't:

```lua
-- ❌ NEVER call SetScale. A second scale in the chain puts units back between pixels,
--    which is the exact problem the root scale removes.
myFrame:SetScale(0.8)

-- ❌ NEVER divide the cursor by UIParent's scale. Your frames live under the scaled root,
--    so this is off by the ratio between the two.
local cx = GetCursorPosition() / UIParent:GetEffectiveScale()

-- ✅ read the cursor in the space of the frame you are comparing against
local cx, cy = SuuUI.Pixel.CursorIn(myFrame)

-- ❌ NEVER mix a widget's own numbers with a screen constant. GetScreenHeight() is in
--    UIParent's units; your frame's GetTop() is in the scaled root's. This breaks the
--    vertical axis only, so it looks half-right.
local y = myFrame:GetTop() - GetScreenHeight()

-- ✅ measure against something that shares your space
local root = SuuUI.UIRoot:GetRootContainer():GetFrame()
local y = myFrame:GetTop() - root:GetTop()
```

Producing geometry outside a layout strategy — a computed anchor offset, a texture
thickness — snap it yourself:

```lua
SuuUI.Pixel.Snap(v)   -- nearest grid step
SuuUI.Pixel.Floor(v)  -- a size that must not overflow its space
SuuUI.Pixel.Ceil(v)   -- a size that must not clip its content
SuuUI.Pixel.Line(v)   -- a thickness, floored at one pixel so it never disappears
```

Listen for `SUUUI_PIXEL_GRID_CHANGED` only if you cache pixel measurements. `Theme`
re-emits `SUUUI_THEME_CHANGED` when the grid moves, so anything already restyling on a
theme change is covered.

---

## Messages, Warnings, and Confirmations

Don't print errors to chat — they scroll away and carry no styling. Use `Notice`:

```lua
local C = SuuUI.Components

-- Blocked but expected: the user asked for something the rules disallow
C.Notice({ title = "Not Allowed", message = "Built-in themes cannot be deleted.",
           tone = "warning" })

-- Something actually failed
local ok, err = pcall(risky)
if not ok then
  C.Notice({ title = "Error", message = tostring(err), tone = "danger" })
end
```

Notices are dismiss-only and free themselves when closed, so calling one per failure
does not accumulate frames. Completed actions can confirm in chat instead — blocking on
a dialog to say "done" costs a click for nothing.

**Intent colour goes on the button that commits the action, never on the one that opens
the dialog:**

```lua
-- ❌ the page shouts before the user has asked for anything
local deleteBtn = C.Button({ label = "Delete", variant = "danger" }, row)

-- ✅ neutral trigger, intent on the confirm button inside the dialog
local deleteBtn = C.Button({ label = "Delete" }, row)
C.Modal({ title = "Delete Profile", message = "This cannot be undone.",
          confirmText = "Delete", confirmVariant = "danger",
          onConfirm = doDelete }):Show()

-- ✅ creation confirms in success
C.Modal({ title = "Create Profile", message = "Name:", input = true,
          confirmText = "Create", confirmVariant = "success",
          onConfirm = doCreate }):Show()
```

**NEVER call SetPoint. It is not available to you.**

`SetPoint`, `SetAllPoints`, and `ClearAllPoints` exist only inside the four layout
strategies (`Flow`, `Grid`, `Stack`, `Anchor`). Component handles and containers do not
expose `SetPoint` at all, so there is nothing to reach for.

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

Need something overlaid, centred, inset, or at a computed offset? Use the `stack` or
`anchor` strategy — see `LAYOUT_SYSTEM.md`. Containers self-anchor to their parent, so
you never position a container either.

**Missing a layout algorithm or property? Add it to the engine.** That is the expected
move, not a local workaround. Adding a strategy is one file in `Layout/` registered in
`Container.lua`; adding a child property is a few lines in one strategy. Document it in
`LAYOUT_SYSTEM.md` and `architecture.md` so every plugin gets it.

**If the layout system doesn't support what you need:**

1. **Document the requirement** — what layout behavior is missing?
2. **Bring it up for discussion** — don't implement workarounds
3. **Extend the system generically** — make it reusable for all plugins
4. **Add tests** — cover the new behaviour in `Tests/spec/` (see `TESTING.md`)
5. **Update architecture docs** — document the new capability

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

## Building Plugin UI: No Raw WoW API

**Your plugin's UI code must not call the WoW UI API.** Compose components and
containers. Raw `CreateFrame`, `CreateTexture`, `CreateFontString`, `SetBackdrop`,
`SetFrameStrata`, `EnableMouse`, and `SetScript` belong inside `Components/` and
`Layout/`. See `WOW_API_ENCAPSULATION.md`.

```lua
-- ❌ FORBIDDEN in plugin UI code
local row = CreateFrame("Frame", nil, parent)
local tex = row:CreateTexture(nil, "ARTWORK")
tex:SetColorTexture(0.2, 0.2, 0.2, 1)
row:SetScript("OnClick", handler)

-- ✅ REQUIRED
local btn = SuuUI.Components.Button({ label = "Apply" }, parent)
container:Add(btn)   -- omit width/height: the button hugs its label
SuuUI.UISignals:Connect(btn, SuuUI.UISignals.SIGNALS.CLICKED, handler)
```

Game data APIs (`RegisterEvent`, `UnitHealth`, `GetSpellInfo`) are fine — that is data,
not UI. Hiding Blizzard's own frames in `onEnable`/`onDisable` is also fine.

**Need a widget the library doesn't have?** Don't inline it. Propose a new component,
build it in `Components/<Name>.lua`, spec it in `Tests/spec/`, and every plugin benefits.
Inside it, lay out the parts with a host container
(`CreateContainer{ host = f, layout = "stack" }`) — a component never calls `SetPoint`
either.

Follow **"Anatomy of a Component" in `coding-standards.md`**: it has the annotated
skeleton every existing component is built from, so a new one comes out in the same
style. In short — backdrops through `SuuUI.Backdrop`, text through `Components.Text`,
accessors through `SuuUI.Components.InstallBase`, internals through a host container,
Blizzard scripts translated into signals, and compose the components that already exist
instead of rebuilding their parts.

---

## Component Signals

Wire UI with `SuuUI.UISignals`, never by attaching Blizzard scripts to a component's
frame. See `UI_SIGNALS.md` for the full signal table and payloads.

```lua
local S = SuuUI.UISignals

-- ❌ FORBIDDEN: reaching through GetFrame() to attach a script
slider:GetFrame():SetScript("OnMouseUp", handler)

-- ✅ REQUIRED: connect to the signal
local id = S:Connect(slider, S.SIGNALS.VALUE_CHANGED, function(new, old)
  SuuUI.Settings:Set("my_plugin", "size", new)
end)

-- Clean up when you drop the handle
S:Disconnect(slider, S.SIGNALS.VALUE_CHANGED, id)
S:DisconnectAll(slider)
```

Common signals: `VALUE_CHANGED` (new, old), `TEXT_CHANGED` (text), `CLICKED` (button),
`SIZE_CHANGED` (w, h), `VISIBILITY_CHANGED` (isVisible), `CONTENT_RESIZED` (height),
`ENABLED_CHANGED` (isEnabled), `MOUSE_ENTER`, `MOUSE_LEAVE`, `FOCUSED`, `UNFOCUSED`.

`SIZE_CHANGED` must fire whenever the element's frame changes size — including when a
parent layout resizes it, which does not go through the handle's `SetSize`. Emit it from
the frame's `OnSizeChanged` hook, not from `SetSize`.

Component-specific signals live on the component table and carry their own payloads:

```lua
SuuUI.Components.INPUT_SIGNALS.SUBMITTED             -- Args: text
SuuUI.Components.COLORPICKER_SIGNALS.COLOR_PICKED    -- Args: r, g, b, a
SuuUI.Components.COLORPICKER_SIGNALS.REQUEST_CLOSE   -- Args: none
SuuUI.Components.MODAL_SIGNALS.CONFIRMED             -- Args: inputValue or nil
SuuUI.Components.MODAL_SIGNALS.CANCELLED             -- Args: none
```

Setter methods (`SetValue`, `SetSelected`) are deliberately silent — they do not emit
`VALUE_CHANGED`. Only user interaction emits, which keeps external state syncing from
looping back on itself.

If your plugin defines custom signals, prefix them with your plugin id and document
the payload inline:
```lua
MY_PLUGIN_SIGNALS = {
  TARGET_SWAPPED = "my_plugin.target_swapped",  -- Args: unitId
}
```

Disconnect every signal in `onDisable` alongside `SuuUI.Events:Off`.

---

## Rules Summary

1. Always prefix pool IDs, event names, signal names, and frame names with your plugin id.
2. Never call another plugin's functions directly.
3. Never allocate tables in OnUpdate.
4. Always clean up in onDisable: `Destroy()` components, `SuuUI.Events:Off`,
   and `SuuUI.UISignals:DisconnectAll`.
5. Restore all Blizzard frames in onDisable.
6. Register settings schema in onInit, not at file load time.
7. **ALWAYS use Container-based layouts. NEVER manually position UI elements.**
8. **If a layout feature is missing, discuss and extend the system — don't hack workarounds.**
9. **NEVER call raw WoW UI API in plugin UI code. Compose components and containers.**
10. **NEVER use Blizzard frame scripts for UI wiring. Connect to UISignals instead.**
11. **If a component is missing, build it in `Components/` — don't inline raw frames.**
12. **NEVER hardcode a visual value.** Design language (spacing, font steps, colours,
    border width, animation timings) comes from theme tokens — add the token to both
    built-in themes and to `ThemeTokens.lua` if it is missing. Your widget's OWN
    dimensions are plugin settings instead, declared with a schema `default` so the
    player can tune them per profile on your page. React to both: `SUUUI_THEME_CHANGED`
    and `Settings:Watch`. Game facts (class colours, power colours, level caps) are the
    exception. See "No Magic Numbers" in `coding-standards.md`.
13. **Test the UI you build.** A new component is not finished without a spec in
    `Tests/spec/`. Run `lua Tests/run.lua` before calling a change done. See `TESTING.md`.
