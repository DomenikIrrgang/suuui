# SuuUI public API

Version **0.1.0** (`SuuUI.API_VERSION`). Everything below is on the global `SuuUI`. SuuUI's built-in modules use only this API, so a plugin can do anything they do. Anything not listed here is private and may change without notice.

A plugin is an addon with `## Dependencies: SuuUI` that calls `SuuUI.RegisterModule`. `Examples/SuuUI_HelloPlugin` is a complete one.

## Versioning

The API follows semantic versioning. A module declares the oldest API it works with (`api = "0.1"`). If this SuuUI can't serve it (a different major version, or an older minor), the module is listed as incompatible and never loads. Additions bump the minor version. Breaking changes bump the major version, which is `0` until the first release.

| | |
|---|---|
| `SuuUI.API_VERSION` | `"0.1.0"` |
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
| `M:Print(...)` | A chat line prefixed with SuuUI and the module's name |
| `M:IsEnabled()` | |
| `M.id`, `M.name`, `M.source`, `M.builtIn`, `M.state` | |

### SuuUI's messages

| Message | Arguments |
|---|---|
| `SUUUI_SETTINGS_READY` | — |
| `SUUUI_SETTING_CHANGED` | `namespace, key` |
| `SUUUI_PROFILE_CHANGED` | `profileName` |
| `SUUUI_MODULE_ENABLED` / `_DISABLED` / `_ERRORED` | `moduleId` |
| `SUUUI_PIXEL_CHANGED` | `screenHeight, uiParentScale` |

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
