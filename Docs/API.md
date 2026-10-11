# SuuUI public API

Version **0.4.0** (`SuuUI.API_VERSION`). Everything below is on the global `SuuUI`. SuuUI's built-in modules use only this API, so a plugin can do anything they do. Anything not listed here is private and may change without notice.

A plugin is an addon with `## Dependencies: SuuUI` that calls `SuuUI.RegisterModule`. `Examples/SuuUI_HelloPlugin` is a complete one.

## Versioning

The API follows semantic versioning. A module declares the oldest API it works with (`api = "0.1"`). If this SuuUI can't serve it (a different major version, or an older minor), the module is listed as incompatible and never loads. Additions bump the minor version. Breaking changes bump the major version, which is `0` until the first release.

| | |
|---|---|
| `SuuUI.API_VERSION` | `"0.3.0"`. 0.2 added the screen root, components, layouts and motion; 0.3 the settings window and its controls; 0.4 edit mode |
| `SuuUI.version` | The addon's version |
| `SuuUI.APIAtLeast(version)` | `true` when this API can serve a module written for `version` |

## Modules

```lua
local M = SuuUI.RegisterModule({
    id = "hello",                 -- lower case letters, digits, _; also the settings namespace
    name = "Hello",               -- shown in lists
    description = "One line.",
    api = "0.1",                  -- the oldest API this module works with
    defaults = { greeting = "Hi" },
    enabledByDefault = true,      -- default true
    reloadToToggle = false,       -- true: turning it on or off takes effect after /reload
    OnInitialize = function(self) end,  -- once, before the first enable
    OnEnable = function(self) end,
    OnDisable = function(self) end,
})
```

- A module that is off is never initialised and costs nothing. Its `enabled` setting is saved per profile.
- Everything a module registers through its own methods (events, setting watchers, chat commands) belongs to it and is removed when it turns off. Register them in `OnEnable`.
- Turning a module on or off waits for the end of combat.
- If `OnInitialize` or `OnEnable` errors, the module is marked errored and turned off. The player sees one line, and SuuUI and the other modules keep running. `/suu enable <id>` retries.
- Use `reloadToToggle` for modules that replace protected Blizzard frames.

| | |
|---|---|
| `SuuUI.RegisterModule(def)` | Registers a module; returns it |
| `SuuUI.GetModule(id)` | The module, or `nil` |
| `SuuUI.ListModules()` | A snapshot: `{ id, name, description, state, source, builtIn, error, pendingReload }` for each module. `state` is `registered`, `enabled`, `disabled`, `errored` or `incompatible` |

### Module methods

| Settings (namespace = the module's id) | |
|---|---|
| `M:Get(key)` | The value; a copy for tables |
| `M:Set(key, value)` | Returns `true`, or `false` and a veto's reason. The value's type must match the default's |
| `M:Reset([key])` | One key, or the module's whole namespace |
| `M:Watch(key, fn)` | `fn(value, namespace, key)` after each change, including profile switches |
| `M:Veto(key, fn)` | `fn(new, old)` returning `false, reason` refuses a change |

| Events | |
|---|---|
| `M:OnGameEvent(event, fn)` | `fn(event, ...)` for a game event |
| `M:OnUnitEvent(event, units, fn)` | `fn(event, ...)` for a unit event, only for `units` (a unit token or a list) |
| `M:On(message, fn)` | `fn(message, ...)` for a message |
| `M:Off(message)` | Stops listening to a message or event |
| `M:Emit(message, ...)` | Sends a message. Prefix your messages with your plugin's name |

| Other | |
|---|---|
| `M:RunOutOfCombat(key, fn)` | Runs `fn` now, or after combat. A later call with the same key replaces a waiting one |
| `M:RegisterCommand(name, help, fn)` | Adds `/suu <name>`; `fn(rest of the line)` |
| `M:RegisterSettings(section)` | A section in the settings window for the module's own settings; it goes away when the module turns off (0.3) |
| `M:RegisterMover(frame, { key = "position", label })` | An edit-mode handle for one of the module's frames (0.4); see *Edit mode* |
| `M:Print(...)` | A chat line prefixed with SuuUI and the module's name |
| `M:IsEnabled()` | |
| `M.id`, `M.name`, `M.source`, `M.builtIn`, `M.state` | |

### SuuUI's messages

| Message | Arguments |
|---|---|
| `SUUUI_SETTINGS_READY` | — |
| `SUUUI_SETTING_CHANGED` | `namespace, key` |
| `SUUUI_PROFILE_CHANGED` | `profileName` |
| `SUUUI_MODULE_REGISTERED` / `_ENABLED` / `_DISABLED` / `_ERRORED` | `moduleId` |
| `SUUUI_SETTINGS_SECTIONS_CHANGED` | — |
| `SUUUI_EDITMODE_CHANGED` | `active` |
| `SUUUI_PIXEL_CHANGED` | `screenHeight, uiParentScale` |
| `SUUUI_ROOT_SCALED` | `effectiveScale` (after the root's scale changed) |

## Design tokens and text

| | |
|---|---|
| `SuuUI.Tokens` | The design system's tokens (read only). `Tokens.color[name]` is `{ r, g, b, a, hex = "rrggbb" }`. `size`, `space` and `radius` are in px; `opacity`; `duration` in seconds; `easing[name].smoothing`; `shadow`; `type[name]`; `order[family]` lists names in the design's order; `usage[name]` is the design's note |
| `SuuUI.Fonts.Get(style)` | The Font object for a text style (`"body"`, `"label"`, `"numeric"`, `"header"`, …) |
| `SuuUI.Fonts.Apply(fontString, style)` | Sets a FontString to a text style |

## Pixels and Blizzard frames

| | |
|---|---|
| `SuuUI.Pixel.Size([region])` | One physical pixel in `region`'s units (UIParent by default) |
| `SuuUI.Pixel.Snap(value, [region])` | `value` rounded to whole physical pixels |
| `SuuUI.Pixel.PerfectScale()` | The effective scale at which one UI unit is one pixel |
| `SuuUI.SuppressBlizzard(frame, [opts])` | Hides a Blizzard frame by reparenting it, after combat if needed. `opts.unregisterEvents` also stops its events; it then only comes back after a reload |
| `SuuUI.RestoreBlizzard(frame)` | Gives it back; `false` if only a reload can |

## The screen root (0.2)

| | |
|---|---|
| `SuuUI.Root` | The frame every SuuUI frame on the screen lives under. It runs at pixel-perfect scale times `ui.scale`, so one unit is one design pixel: design sizes and offsets from the screen's edges or centre are used as they are. Rescales wait for the end of combat |

Settings in the `ui` namespace: `ui.scale` (0 = automatic: 1 up to 1440p, larger on taller screens; otherwise 0.5–2) and `ui.reducedMotion` (drops decorative motion, keeps every value change).

## Components (0.2)

All on `SuuUI.UI`. Colours and sizes are token names (`"ink"`, `"icon-lg"`) or plain numbers.

| | |
|---|---|
| `Panel(parent, { title, meta, closable, onClose, keybind, anchor, ornament, solid, shadow, width, height, name })` | The one container. Put content in `panel.body`; without a fixed size the panel fits its body. `anchor` is for the player frame, minimap and dock only |
| `SectionHeader(parent, label, meta, width)` | A label on the world with a fading gilt rule; `:SetLabel(label, meta)` |
| `WindowFrame(parent, { name, title, meta, keybind, width, height, footer, onClose })` | The shell of every full window: draggable, Escape closes it (with a `name`), content in `window.content` (scrolls), optional `window.footer` |
| `Button(parent, { text, variant = "quiet" or "primary", onClick, width, disabled, tooltip })` | `:SetLabel(text)`, `:SetEnabledState(enabled)` |
| `CloseButton(parent, onClick)`, `KeyChip(parent, key)` | Header pieces |
| `StateBadge(parent, tone, text)` | Tones: `danger`, `warning`, `magic`, `curse`, `poison`, `disease`, `ward`, `info`, `neutral`; `:SetState(tone, text)` |
| `Icon(parent, size)` | `:SetArt(texture)`, `:SetState("rest"/"ready"/"dim"/"active")`, `:SetBorder(token)`, `:SetGlow(shadowToken)`, `:SetCount(n)`, `:Pop()` |
| `StatusBar(parent, { width, height, fill, deep, track, border, ghost })` | `:SetMinMax(min, max)`, `:SetValue(v)` (secret values are fine; the ghost drains after 150ms), `:SetValueNow(v)`, `:SetFill(fill, deep)` |
| `Text(parent, style, color)` | A FontString in a text style: `:SetValue(v)` (secret-safe, skips unchanged readable values), `:SetStyle`, `:SetColor`, `:SetShadowed`, `:SetFixedWidth`, `:SetVisible` |
| `ShowTooltip(owner, data)`, `HideTooltip()`, `AttachTooltip(frame, data)`, `TooltipFrame(parent)` | SuuUI's tooltip. `data`: `{ title, titleColor, subtitle, lines = { { left, right } }, description, meta }` |

Drawing helpers: `Fill(parent, color, layer)`, `Border(frame, color, { width, inset, layer })` (stays one physical pixel), `Hairline(parent, color, fade = "out"/"both"/nil)`, `Diamond(parent, size, color)`, `Shadow(frame, shadowToken)`, `SoftEdge(frame)`, `Cross(parent, size, color)`, `RGBA(token[, alpha])`, `Size(token)`.

## Layout and motion (0.2)

| | |
|---|---|
| `SuuUI.Layout.Stack(container, { direction, gap, padding, align, autoSize })` | Lays out `:Add(child[, { gapBefore }])`ed children in a row or column, once per frame. Texts whose value may be secret need a fixed width |
| `SuuUI.Layout.Grid(container, { columns, cellWidth, cellHeight, gap, padding })` | Fixed cells, row by row |
| `SuuUI.Motion.FadeIn(frame[, duration])`, `.Enter(frame[, duration])`, `.Pop(frame)`, `.Stop(frame)` | The design's presets; nothing animates with `ui.reducedMotion` on |

## The settings window (0.3)

`/suu` opens it; so do the "SuuUI settings" button under the game menu and `SuuUI.OpenSettings([sectionId])`.

A section is plain data. `module:RegisterSettings(section)` ties it to the module (namespace = the module's id); `SuuUI.RegisterSettings(section)` registers one that is always there.

```lua
M:RegisterSettings({
    id = "hello", label = "Hello",
    category = "Plugins",          -- Frames, Insights, World, General or Plugins (the default)
    order = 100,
    groups = {
        { title = "Greeting", description = "…", rows = {
            { key = "greeting", label = "Greeting", control = "text", description = "What /suu hello says." },
            { key = "size", label = "Size", control = "slider", min = 16, max = 32, step = 2, unit = "px" },
            { key = "mode", label = "Mode", control = "segmented",
              options = { { value = "a", label = "A" }, { value = "b", label = "B" } } },
            { key = "on", label = "Something", control = "toggle",
              disabled = function() return not SuuUI.GetModule("hello"):Get("size"), "Why it's off." end },
        } },
    },
    build = function(page) end,    -- optional: page:AddGroup(groupDef), page:Clear(), page:Refresh()
    preview = function(parent) return frame end,  -- optional live preview (scaled to fit 320px)
})
```

A row: `key` (or `get`, `set`, `isDefault`, `reset` functions), `label`, `description` (a string or a function), `control` (`toggle`, `checkbox`, `segmented`, `select`, `slider`, `stepper`, `text`, `button`, `custom`), the control's options (`options` (a list or a function), `multiple`, `min`, `max`, `step`, `unit`, `format`, `width`, `placeholder`, `text`, `onClick`, `build`), `stacked`, and `disabled = function() return disabled, reason end`. Rows update live, show a diamond and a reset arrow when changed, and are found by the window's search.

Controls on `SuuUI.UI`, all with `:SetValue(v)`, `.onChange = fn(v)` and `:SetDisabled(disabled)`:

| | |
|---|---|
| `Toggle(parent, { value, onChange })` | On or off |
| `Checkbox(parent, { label, value, onChange })` | Several things that can all be on |
| `Segmented(parent, { options, value, onChange })` | One of two to five named options |
| `Select(parent, { options, value, onChange, multiple, width, placeholder, maxShown })` | One (or several) of a longer list; `:SetOptions(options)` |
| `Slider(parent, { min, max, step, value, unit, format, width, onChange })` | A size or amount you judge by eye |
| `Stepper(parent, { min, max, step, value, unit, onChange })` | An exact number |
| `TextField(parent, { width, placeholder, value, onChange, onTextChanged })` | Text; `onChange` on Enter or when it loses focus |
| `SettingRow(parent, { label, description, control, stacked, onReset, width })`, `SettingsGroup(parent, { title, meta, description, width })` | The pieces sections are made of |

## Edit mode (0.4)

`/suu edit` (or Appearance › Edit layout) shows every registered frame on a snap grid: drag to move, click to select, arrow keys to nudge (Shift: 10px), Hide/Show and Reset on the selected frame, Snap to grid, Grid size and Reset all in the panel. It closes when combat starts and runs beside the game's own Edit Mode.

A frame's position is a setting in its module's namespace, declared in the defaults, so it is saved per profile:

```lua
defaults = { position = { point = "TOP", x = 0, y = -160 } },
OnEnable = function(self)
    self:RegisterMover(self.frame, { key = "position", label = "Hello" })
end,
```

`point` is one of the nine screen anchors (`TOPLEFT` … `BOTTOMRIGHT`, `CENTER`) and `x`, `y` the offset of the frame's same point from it, in design pixels; `hidden = true` hides the frame. A dropped frame takes the anchor of the screen third its centre is in, so layouts keep their shape on every resolution. Protected frames are placed after combat.

| | |
|---|---|
| `SuuUI.RegisterMover(frame, { namespace, key, label })` | The same for a frame outside a module |
| `SuuUI.EditMode.Enter()`, `.Exit()`, `.Toggle()`, `.IsActive()` | |

Settings: `layout.snap`, `layout.gridSize`.
