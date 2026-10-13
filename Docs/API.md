# SuuUI public API

Version **0.11.0** (`SuuUI.API_VERSION`). Everything below is on the global `SuuUI`. SuuUI's built-in modules use only this API, so a plugin can do anything they do. Anything not listed here is private and may change without notice.

A plugin is an addon with `## Dependencies: SuuUI` that calls `SuuUI.RegisterModule`. `Examples/SuuUI_HelloPlugin` is a complete one.

## Versioning

The API follows semantic versioning. A module declares the oldest API it works with (`api = "0.1"`). If this SuuUI can't serve it (a different major version, or an older minor), the module is listed as incompatible and never loads. Additions bump the minor version. Breaking changes bump the major version, which is `0` until the first release.

| | |
|---|---|
| `SuuUI.API_VERSION` | `"0.11.0"`. 0.2 added the screen root, components, layouts and motion; 0.3 the settings window and its controls; 0.4 edit mode; 0.5 unit frames; 0.6 anchors, cast bars and the swing timer; 0.7 aura containers; 0.8 action bars; 0.9 roles and party frames; 0.10 alerts and the threat meter; 0.11 a module's own data per character |
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
- If `OnInitialize` or `OnEnable` errors, the module is marked errored and turned off. The player sees one line, and SuuUI and the other modules keep running. `OnDisable` runs after a failed `OnEnable`, so it should cope with a half-built module. `/suu enable <id>` retries (a `reloadToToggle` module after the next `/reload`).
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
| `M:Veto(key, fn)` | `fn(new, old)` returning `false, reason` refuses a change. A refused value a profile brings in (switching, copying, importing) is dropped, so the default applies |
| `M:CharData()` (0.11) | The module's own table for this character, saved with SuuUI: what it keeps that isn't a setting (a history, a cache). Never in a profile, an export or a reset. From `OnEnable` on |
| `M:AllCharData()` / `M:CharKey()` / `M:ForgetCharData(key)` (0.12) | Every character's `CharData` table for the module (`{ [key] = data }`, this character's included), this character's key ("Name - Realm"), and dropping another character's table (never your own) |
| `M:Guard(fn)` (0.12) | `fn` wrapped so an error in it is reported under the module's name (`/suu errors`, SuuUIDB.errors), as errors in its events and settings are: for callbacks from UI controls and timers |
| `M:Migrate(id, fn)` (0.9) | `fn(values)` brings one profile's stored values of the module into a new shape (a renamed key, a changed type) by changing `values` in place. See *Migrations* |

#### Migrations

A stored value of another type than the default's is ignored, so when you rename a key or change its type, register a migration right after `RegisterModule`, at file load:

```lua
local M = SuuUI.RegisterModule({ id = "hello", api = "0.9", defaults = { healthText = "percent" } })

-- 1.1 turned the toggle `showHealth` into the choice `healthText`
M:Migrate("healthText", function(values)
    if type(values.showHealth) == "boolean" then
        values.healthText = values.showHealth and "percent" or "none"
    end
    values.showHealth = nil
end)
```

- `values` is the module's stored values in one profile: only what differs from the defaults. `fn` is called only for profiles that have stored values for the module; values the migration leaves at their default are dropped.
- Each migration (`id`, unique per module) runs once per profile, and the profile remembers it. It runs on every profile when SuuUI loads (a plugin's, when it registers), and on profiles that come in later: switched to, copied from or imported (an older export too). It runs before values are checked by type and by vetoes, so converted values survive.
- Migrations run in the order they were registered. One that errors is reported and runs again at the next load.

| Events | |
|---|---|
| `M:OnGameEvent(event, fn)` | `fn(event, ...)` for a game event |
| `M:OnUnitEvent(event, units, fn)` | `fn(event, ...)` for a unit event, only for `units` (a unit token or a list of any length) |
| `M:On(message, fn)` | `fn(message, ...)` for a message |
| `M:Off(message)` | Stops listening to a message or event |
| `M:Emit(message, ...)` | Sends a message. Prefix your messages with your plugin's name |

| Other | |
|---|---|
| `M:RunOutOfCombat(key, fn)` | Runs `fn` now, or after combat. A later call with the same key (per module) replaces a waiting one |
| `M:RegisterCommand(name, help, fn)` | Adds `/suu <name>`; `fn(rest of the line)` |
| `M:RegisterSettings(section)` | A section in the settings window for the module's own settings; it goes away when the module turns off (0.3) |
| `M:RegisterMover(frame, { key = "position", label, enabled })` | An edit-mode handle for one of the module's frames (0.4); see *Edit mode* |
| `M:Print(...)` | A chat line prefixed with SuuUI and the module's name |
| `M:IsEnabled()` | |
| `M.id`, `M.name`, `M.source`, `M.builtIn`, `M.state` | |

### SuuUI's messages

| Message | Arguments |
|---|---|
| `SUUUI_SETTINGS_READY` | — |
| `SUUUI_SETTING_CHANGED` | `namespace, key` |
| `SUUUI_PROFILE_CHANGED` | `profileName` |
| `SUUUI_PROFILES_CHANGED` (0.9) | — (a profile was created, imported or deleted) |
| `SUUUI_SPEC_CHANGED` (0.9) | `spec` (the talent tree with the most points, 1-3; 0 unspecced) |
| `SUUUI_ROLE_CHANGED` (0.9) | `role` ("TANK", "HEALER", "DAMAGER"), before any profile switch it causes |
| `SUUUI_MODULE_REGISTERED` / `_ENABLED` / `_DISABLED` / `_ERRORED` | `moduleId` |
| `SUUUI_SETTINGS_SECTIONS_CHANGED` | — |
| `SUUUI_EDITMODE_CHANGED` | `active` |
| `SUUUI_ANCHOR_CHANGED` | `name, frame` |
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
| `SuuUI.SuppressBlizzard(frame, [opts])` | Stands a Blizzard frame down: stops its events, hides it and moves it under a hidden parent (after combat for protected frames, never while the game's Edit Mode is open). `opts.children`: dotted paths of children whose events stop too. `opts.keepParent`: stop events and hide, but don't reparent. `opts.noHide`: reparent without calling Hide (frames Edit Mode shows through a protected setter, such as the action bars). Only a reload brings it back |
| `SuuUI.IsSuppressed(frame)` | Whether a frame is stood down |
| `SuuUI.RestoreBlizzard(frame)` | Kept for compatibility: always `false` for a suppressed frame (only a reload restores it) |

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
    -- optional: the live preview column (320px): the view at its real size,
    -- centred (wider ones start at the column's left edge and clip on the right). Return the same frame each time.
    preview = function(parent) return myPreviewFrame end,
    previewTitle = "Live preview",
    previewNote = function() return "5 frames at 200 × 28 px" end, -- 0.9
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
    preview = function(parent) return frame end,  -- optional live preview (real size, 320px column)
    merge = "castbars",            -- optional (0.9): show the groups on another section's page
})
```

`merge` (0.9): the id of another section. The merged section isn't listed in the section list; its groups show on that section's page, after the page's own groups. Each group keeps its own section's namespace, so its rows read and write the merged module's settings. They are found by the search, count towards the page's change diamond, are reset by its Reset section, and go away with their section (when its module turns off). Only `groups` merge (not `build` or `preview`), and merges don't chain. While the other section isn't registered (its module is off), the merged one is listed on its own, by its own category and order. `SuuUI.OpenSettings(id)` with a merged section's id opens the page it shows on. The swing timer merges into the cast bars' section this way.

A row: `key` (or `get`, `set`, `isDefault`, `reset` functions), `label`, `description` (a string or a function), `control` (`toggle`, `checkbox`, `segmented`, `select`, `slider`, `stepper`, `text`, `button`, `custom`), the control's options (`options` (a list or a function), `multiple`, `min`, `max`, `step`, `unit`, `format`, `width`, `placeholder`, `text`, `onClick`, `build`), `stacked`, `disabled = function() return disabled, reason end`, and `combat = true` (0.9) for a change that waits for the end of combat: the window adds "Waits for the end of combat." to the description (or shows it alone), so don't write it yourself. Rows update live, show a diamond and a reset arrow when changed, and are found by the window's search.

A `custom` row (0.9): `build(parent, onChange, def)` returns the control. With a `key` (or `get`), the row binds it like a built-in control: the control calls `onChange(value)` to write the setting (a refused value goes back, the row shows its change diamond and reset arrow), and the window calls `control:SetValue(value)` on every refresh (a reset, a profile switch), when the control has `SetValue`. Without a key or get it is left alone.

Controls on `SuuUI.UI`, all with `:SetValue(v)`, `.onChange = fn(v)` and `:SetDisabled(disabled)`:

| | |
|---|---|
| `Toggle(parent, { value, onChange })` | On or off |
| `Checkbox(parent, { label, value, onChange })` | Several things that can all be on |
| `Segmented(parent, { options, value, onChange })` | One of two to five named options |
| `Select(parent, { options, value, onChange, multiple, width, placeholder, maxShown })` | One (or several) of a longer list; `:SetOptions(options)` |
| `Slider(parent, { min, max, step, value, unit, format, width, onChange })` | A size or amount you judge by eye |
| `Stepper(parent, { min, max, step, value, unit, onChange })` | An exact number, in whole steps from `min` |
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
| `opts.place()` (0.8) | The mover positions its frame itself (e.g. relative to another frame) instead of from its position table |
| `opts.onDrop(l, b, w, h)` (0.8) | Called with the dropped (or nudged) rectangle in root units; return `true` when it handled the drop, else the position table is saved as usual |
| `opts.action = { label = fn, onClick = fn }` (0.8) | One extra button in the selected frame's toolbar (e.g. "Attach to dock") |
| `opts.dragFrame()` (0.8) | The frame a drag moves live, when it isn't the mover's own (a bar attached to the dock moves the dock) |
| `opts.reset()` (0.8) | What Reset (the toolbar's, and Reset all) does for this frame, instead of resetting the position table |
| `SuuUI.EditMode.Rect(frame)`, `.AnchorFor(l, b, w, h)` (0.8) | A frame's rectangle in root units, and the screen anchor edit mode would save for a rectangle |
| `opts.enabled` (0.8) | A function: while it returns false the frame is turned off and gets no mover in edit mode (a bar switched off in the settings). Hiding in edit mode is for frames that are on |
| `SuuUI.EditMode.Refresh()` (0.8) | Re-reads every mover's `enabled`; call it when one changes |

Settings: `layout.snap`, `layout.gridSize` (4–32 px).

## Anchors (0.6)

Modules find each other's frames through published anchors, never through each other's internals.

| | |
|---|---|
| `SuuUI.PublishAnchor(name, frame)` | Publishes a frame under a name (`nil` unpublishes) |
| `SuuUI.GetAnchor(name)` | The frame, or `nil`; listen to `SUUUI_ANCHOR_CHANGED` for changes |

Published by SuuUI: `player`, `target`, `targettarget`, `focus`, `pet`, `boss1` … `boss5` (unit frames).

## Unit frames and cast bars (0.5, 0.6)

| | |
|---|---|
| `SuuUI.UI.UnitFrame(parent, unit, opts)` | The unit frame; `:Activate()`, `:Deactivate()`, `:Refresh()`, `:SetState(tone, word)`; 0.9: `:SetUnit(unit)`, `:Resize(w, h)`, `:SetDispelBadges("all"|"removable"|"off")` (debuff-type border and badge, in combat too) (out of combat) and the opts `height`, `lowHealth`, `incoming`, `powerFor(unit)`. See `UI/UnitFrame.lua` for `opts`; 0.9 too: the opt `raidMarker = true` (the raid target icon over the top edge; `:UpdateRaidMarker()`), and a built-in offline state ("Offline" in the right-hand text, an empty bar, a faint name, no power line) |
| Buff indicators (0.9) | `f:SetIndicators(list)` (live, out of combat) and `f:SetPreviewIndicators(list)` on a unit frame; `SuuUI.UI.GroupIndicators()` (list, version) and `SuuUI.UI.SetGroupIndicators(list)` (emits `SUUUI_INDICATORS_CHANGED`); an indicator is `{ name, ids, kind = "icon"|"square"|"border"|"fill", point, size, color, source = "mine"|"any" }`, `SuuUI.UI.INDICATOR_POINTS` lists the points |
| `SuuUI.UI.UnitStandIn(person)` (0.9) | Stand-in Unit* functions for a preview: `person(unit)` returns `{ name, class, role, health (0-1), max, power, incoming, absorb, dead, you, offline, marker (1-8) }`; pass the result as a unit frame's `opts.api`; the stand-in also answers `UnitIsConnected` and `GetRaidTargetIndex` |
| `SuuUI.UI.RaidMarker(parent, size[, layer])`, `SuuUI.UI.ShowRaidMarker(texture, unit[, api])` (0.9) | A raid target marker texture (hidden until shown), and the unit's marker on it or hidden; a marker that is secret in combat still shows (through the texture's sprite sheet cell). Unit frames and nameplates use them |
| `SuuUI.Role()` (0.9) | Your role ("TANK", "HEALER", "DAMAGER") and where it came from ("chosen", "assigned", "talents"). Profiles can switch with it (General > Profiles > By role) |
| `SuuUI.Spec()` (0.9) | The talent tree with the most points (1-3; 0 with none spent) and the points per tree |
| `SuuUI.UI.CastBar(parent, unit, { size, width, icon, kick })` | A cast bar; `:Activate()`, `:Deactivate()`, `:SetIconShown(on)`, `:SetKickShown(on)`; 0.9: `size = "plate"`, `:SetUnit(unit)`, `:SetBarHeight(px)`, `:SetBarWidth(px)`, opt `target` (who the spell is aimed at: on plates a line under the spell name, on other sizes after it, "Spell › Target", in the spell name's width) and `:SetTargetShown(on)`, `:SetNeutral(on)` (a friendly unit's cast: no arcane layer, lock or interrupt) |
| `SuuUI.UI.Flag(v)` | A possibly secret boolean as a plain one (secret reads as false). Show from a secret boolean with `region:SetAlphaFromBoolean` instead |
| `SuuUI.UI.MeasureText(style, text)` | A text's width, measured where no anchor chain can make it secret |
| `SuuUI.Motion.AlphaTo(frame, alpha, duration)` | Fades to an alpha; works on secure frames in combat |
| `SuuUI.UI.SwingTimer(parent, { width, name })` | The swing timer from the game's own `PLAYER_SWING`; `:Activate()`, `:Deactivate()`; 0.9: `:SetBarWidth(px)` |

## Auras (0.7)

| | |
|---|---|
| `SuuUI.UI.AuraContainer(parent, unit, opts)` | An engine aura container styled as the design's AuraIcon. `opts`: `size` (token), `anchor`, `growth` (`{ "LEFT", "UP" }`), `lineWidth`, `groups` (`{ key, filter = { "HARMFUL", "PLAYER" }, max, dispel, cancel, drain }`). Returns `{ container, ... }` with `:SetUnit(unit)`, `:Refresh()`, `:SetGroupMax(key, n)`; 0.9: `:SetFlow(anchor, growth)`, `:SetLineWidth(px)`, `:SetGroupSize(key, size)` (live; out of combat, as the engine's buttons refuse it in combat), `:Release()` (containers can never be freed: a released one has no unit, is hidden and stops listening until the next `:SetUnit(unit)`, so whoever rebuilds can reuse it). Addon code can't read auras in combat, so the engine fills it |
| Group options (0.9) | `include = { spellIDs }` (only those spells), `dispelTypes = { "Curse" }` (only debuffs of those types, matched by the engine in combat too), `initialize = fn(button)` (build the button yourself, once, when the engine creates it: decorations hung on it show and hide with it, which is how party frames draw a debuff type's border and badge in combat) |

## Action bars (0.8)

SuuUI's own secure buttons: no Blizzard button template. Make them out of combat.

| | |
|---|---|
| `SuuUI.UI.ActionBar(parent, opts)` | Up to 12 buttons on a secure header. `opts`: `name` (global name; buttons are `name .. "Button" .. i`), `slot` (first action slot), `count`, `columns`, `gap`, `size`, `binding` (the game's binding command prefix, e.g. `"MULTIACTIONBAR1BUTTON"`: every key bound to it clicks the button), `paging` (macro conditions, e.g. `SuuUI.UI.ActionBarPaging()`), `onPage(bar, page)`. Returns a bar with `.header`, `.buttons`, `:Page()`, `:SetHotkeysShown(on)`, `:SetShowEmpty(on)`, `:Layout(columns, gap)`, `:UpdateBindings()` |
| `SuuUI.UI.SetVisibility(frame, mode, also)` | When a frame shows: `"always"`, `"combat"` (a secure driver, so it works for frames holding secure buttons), `"mouseover"` (fades in while the mouse is over it or you drag something) or `"hidden"`. 0.9: `also`, a list of frames outside `frame` whose hover counts as its own for mouseover; setting the mode a frame already has changes nothing. Edit mode and keybind mode show every managed frame that isn't hidden (keybind mode the pet bar too). Bars: `bar:SetVisibility(mode)`, `bar:Layout(columns, gap, count, size)` |
| `SuuUI.UI.VISIBILITY_OPTIONS` (0.9) | The `{ value, label }` choices `"always"`, `"combat"`, `"mouseover"`, for a settings row's `options` |
| `SuuUI.UI.ActionBarPaging()` | Bar 1's paging on Forever: override and vehicle bars, manual pages 2–6, then stance/form pages 7–10 |
| `SuuUI.UI.ActionButton(parent, name, size)` | One button's art on a `SecureActionButtonTemplate` button (the bar sets the secure attributes). `:SetSlot(slot)`, `:SetHotkey(text)`, `:SetHotkeyShown(on)`, `:Update()` |
| `SuuUI.UI.ShortKey(key)` | A binding in button size: `"SHIFT-1"` → `"S1"`, `"BUTTON4"` → `"M4"` |
| `SuuUI.UI.StanceBar(parent, { name })` | Your stances or forms as `action-sm` buttons, one per form you know. `.header`, `:SetEnabled(on)`, `:SetHotkeysShown(on)` |
| `SuuUI.UI.PetBar(parent, { name })` | The pet's 10 actions, shown while you have a pet; right click toggles autocast. `.header`, `:SetEnabled(on)`, `:SetHotkeysShown(on)` |
| `SuuUI.UI.MakeModal(panel)` | Makes a panel a modal: centred over a dimmed screen (the game can't blur its interface), taking every click; Esc or a click on the shade closes it. `:Show()`/`:Hide()` as usual |
| `SuuUI.UI.ScrollArea(parent[, bar])` (0.9) | A mouse-wheel scroll frame; put content in `area.child` and size it to the content. With `bar`, a thin scrollbar sits `bar` px right of the area while the content overflows (the settings window and the Behaviour panel use it) |
| `SuuUI.UI.Confirm({ title, text, confirm, cancel, onConfirm, onCancel })` | A modal yes/no question; Cancel, Esc or a click outside counts as cancel |
| `SuuUI.UI.CooldownTracker(parent, { name })` | SuuUI's own Cooldown Manager: `:SetLists({ essential, utility, buffs, debuffs, procs })` (entries `{ name, ids, mine }`; a group `{ group = true, name, members = { { name, ids, icon, source }, ... }, ids, source, max, icon, fixedIcon }`: in an aura list one slot whose members show while up, members of different `source`s getting one engine group each; with none up the slot shows `icon` when `fixedIcon` is true, else an automatic one: the first member (of those its conditions leave in) that you know, else the first whose `when` is met, else `icon` (a member's art: its `icon`, else its first ID; picked again on each rebuild); in essential or utility one cooldown, the last member you know, members in order of preference; a collection `{ collection = true, uid, name, hidden, entries }`, aura lists only, its entries (single entries and groups) shown side by side in its place), `:SetOptions({ essentialSize, utilityInline, readyPop, procHighlight })` (what an aura does while missing is its entry's own `missing`: buffs `"grey"`, debuffs `"target"` unless set); 0.9: `:Stop()` (no events, aura sounds or containers in use) and `:Start()` (again; a new tracker runs). Cooldowns are its own icons; buffs, debuffs and procs are engine aura containers with spell lists. Any entry, group, group member or collection may carry `when` (see `SuuUI.UI.CooldownConditionMet`): not met, it's left out (a member: out of its slot); a collection's applies to its entries too |
| `SuuUI.UI.CooldownConditionMet(when)` | Whether a Cooldown Manager condition is met now. `when = { match = "all"\|"any", conditions = { ... } }` (default `"all"`), each condition `{ type, ..., ["not"] = true? }`: `{ type = "group", value = "solo"\|"group"\|"raid" }` (a raid counts as a group), `{ type = "classes", classes = { "DRUID", ... }, others = true? }` (anyone in your group, you too; with `others`, only the others), `{ type = "role", roles = { "TANK"\|"HEALER"\|"DAMAGER", ... } }` (`SuuUI.Role()`), `{ type = "stance", stances = { "battle", "defensive", "berserker", "caster", "bear", "cat", "moonkin", "travel", "aquatic", "stealth", "shadowform" } }`, `{ type = "combat" }`, `{ type = "instance", kinds = { "none", "party", "raid", "pvp" } }` (an arena is pvp), `{ type = "target", kinds = { "boss", "elite", "player", "normal" } }` (one kind per target: player, else boss, else elite, else normal; no target matches none), `{ type = "talent", talents = { spellID, ... } }` (you've learned any of them: a node with a rank in the active talent config, or a spell you know; any class's IDs may be listed, another class's are never learned). No `when`, no conditions, or a condition with an empty list: always met. The tracker checks group, classes, role, instance and talent when it builds (rebuilding after combat when they change) and stance, combat and target in place, in combat too |
| `SuuUI.CooldownPresets()` | Your class's presets: `{ { id, name, lists } }`, every entry carrying all the IDs with its name in Forever's client; groups and collections as for `:SetLists` (no `uid`: the Cooldown Manager gives each one when it copies a preset) |
| `SuuUI.ClassTalents(class)` (0.9) | Every talent of a class, any of the nine (generated from the class data, `Data/Talents.lua`): `{ { id = spellID, name, tree = 1-3 }, ... }`; nil for an unknown class. The Cooldown Manager's talent condition picks from it |
| `SuuUI.AuraCatalog()` (0.9) | Every aura any class's presets track (their buffs, debuffs, procs and cooldowns' effects): `{ [name] = { classes = "Priest", ids = { ... } } }` (generated `Data/AuraCatalog.lua`). The Cooldown Manager's "+ Add" offers them to every class, noting the class |
| `SuuUI.KeybindMode.Enter()`, `.Exit()`, `.Toggle()`, `.IsActive()` | Keybind mode (`/suu keybind`): hover a button, press a key. It binds the game's own command for the button, so the game's Key Bindings window shows it too. Message: `SUUUI_KEYBINDMODE_CHANGED (active)` |
| Keybinds settings (0.9) | General › Keybinds, in the `actionbars` namespace: `showKeys` (show key bindings on buttons at all) and `keyBars` (the bars that show them: a list of `"1"` … `"8"`, `"stance"`, `"pet"`) |
| Bindable buttons | A button made with `SuuUI.UI.ActionButton` takes part in keybind mode when it has `b.bindCommand` (a game binding command) and `b.bindLabel`; `ActionBar`, `StanceBar` and `PetBar` set both |

## Alerts and the threat meter (0.10)

| | |
|---|---|
| `SuuUI.ShowAlert(key, tone, title, detail, ...)` | One alert at a time, centred 320px down from the top of the screen, in combat only (the Alerts module; nothing while it's off). `tone`: `"danger"`, `"warning"` or `"info"`. `detail` is text, or a format whose arguments may be secret (a target's name in a dungeon). The same `key` updates its alert in place; a new key replaces the alert showing unless that one is more urgent (danger > warning > info). Combat ending clears it. Danger alerts can play a sound |
| `SuuUI.HideAlert(key)` | Takes that key's alert away (raise an alert while its reason holds, hide it when it doesn't) |
| `SuuUI.UI.Alert(parent)` | The alert band itself: `a:SetAlert(tone, title, detail[, ...])` sizes it to its text (a detail with a secret argument can't be measured: the band is then at least `notice-w` wide and cuts it) |
| `SuuUI.UI.ThreatMeter(parent, { rows })` | The threat meter panel, `meter-w` wide and always `rows` rows tall (default 8). `m:SetTarget(name)` (may be secret); `m:SetRows(list, opts)`, `list` in group order: `{ name, class, role ("TANK", "HEALER", "DAMAGER", "PET"), status (0-3, nil unknown), percent (scaled, possibly secret), raw (possibly secret), you }`; `opts`: `show` (`"group"`, `"tanks"`, `"self"`), `byState` (order by threat state then group, with the boss note; otherwise by %, ranked), `marker` (`"role"`, `"class"`, `"none"`), `raw` (show the threat value; readable ones only), `nameColor` (`"class"` or `"ink"`). States come from the status alone: Aggro, Pulling, Losing, Tanking |
| `m:SetMaxRows(n)` | The threat meter's height in rows, live (the Threat meter module matches the damage meter's Rows) |
| `SuuUI.UI.DamageMeter(parent, opts)` | One damage meter window on Blizzard's data (`C_DamageMeter`): `meter-w` wide, a head with the type and fight selects, the fight's time and a menu, then `rows` rows. `opts`: `rows`, `onView(type, session)`, `onNewWindow`, `onClose` (shows "Close this window"), `onReset`, `onSettings`. `w:SetView(type, session)` (`type` one of `SuuUI.UI.DAMAGE_METER_TYPES`' values: `"damage"`, `"dps"`, `"damageTaken"`, `"avoidable"`, `"enemyDamageTaken"`, `"healing"`, `"hps"`, `"interrupts"`, `"dispels"`, `"deaths"`; `session` `"current"`, `"overall"` or a sessionID), `w:SetOptions({ numbers = "minimal"\|"compact"\|"complete", barColor = "neutral"\|"class", marker = "icon"\|"diamond"\|"none", nameColor = "class"\|"ink", pinYou })`, `w:SetMaxRows(n)`, `w:SetCanAddWindow(on)`, `w:Refresh()` (read the data again; the caller drives it: about once a second in combat, on the meter's events out of it). Rows keep the engine's order; secret amounts and names go to the engine untested; your row opens your spell breakdown any time, others' after combat; deaths open their recap |
| `SuuUI.AllowAlertOutOfCombat(key)` | That key's alerts may also show out of combat (the pull countdown's) |
| `SuuUI.UI.EncounterTimeline(parent, { variant, window, soonAt })` | The encounter timeline: `"track"` (a line `timeline-w` wide, now at the left, `window` seconds, default 30, to the right; abilities ride toward now, amber under `soonAt`, default 5) or `"list"` (the older panel). `t:SetEvents({ { id, label, icon, badge = { tone, text }, endsAt (GetTime() it happens) or paused (seconds left, frozen) } })` (it moves them every frame while it has any), `t:SetVariant(v)`, `t:SetMeta(text)` (the list's head) |
| `SuuUI.UI.Readiness(parent, { onReadyCheck })` | The readiness panel (340px, "Readiness · before pull"): `r:SetRows({ { icon, spell, who, class, endsAt } })` (no `endsAt` or a past one: "Ready" in arcane; otherwise the time left, the icon dim), `r:SetActionShown(on)` (the Ready check button in the foot) |
| `SuuUI.UI.ObjectiveTracker(parent, { width, maxHeight, toggle })` (0.11) | The objective tracker on the world: `t:SetQuests({ { questID, title, difficulty ("trivial" … "impossible"), complete, failed, turnIn, tooltip, objectives = { { text, progress, done } }, item = { preview = true, icon } } }, freeze)` (`freeze`: places kept and heights only grow, for secure item buttons beside titles in combat), `t:QuestTop(questID)` (the title's offset down from the top, for such a button), `t:SetCollapsed(on)`, `t:SetMeta(text)`, `t.onQuestClick(questID, button, row)`, `t.onToggle`; `toggle`: your own (secure) toggle button, drawn by the tracker, placed by you at its top left (`UI.TRACKER_HEAD_H` square) |
| `SuuUI.Notify({ id, kind, category, title, body, icon, tone, duration, until, actions })` (0.11) | A note in the notification stack (Notifications module): `kind` `"timed"` (goes after `duration`, default 8 s), `"sticky"` (until closed) or `"until"` (until you dismiss it: `until` says what makes it go); `icon = { glyph = "bell" }` (a glyph from `Media/Textures/Glyphs`) or `{ texture }`; `tone` `"warning"`/`"danger"`; `actions = { { label, variant = "primary"|"quiet"|"danger", onClick(card) } }`. Returns the id; the same `id` again replaces it. Nothing while the module is off |
| `SuuUI.DismissNotification(id)` (0.11) | Takes a note away |
| `SuuUI.UI.Notification(parent)` / `SuuUI.UI.NotificationStack(parent, { max })` (0.11) | The card (`n:SetData(d)` with the fields above plus `item = { icon, label, quality }`, `confirmText`, `duration`/`remaining`; `n:SetRemaining(s)`) and the stack (`s:SetItems(list, inCombat)`: requests, conditions, notes, timed; in combat only the first two; at most `max`, the rest behind "+N more") |
| `SuuUI.UI.Inventory(parent, { title, columns, name, sortTip, characters })` (0.11; `characters` 0.12) | The bags (and bank) panel: search field (`inv.search`), sort button (`inv.sort`), a grid (`inv.grid`; `inv:LayoutSlots(buttons)` places your slot buttons row by row, `slot` square, space-2 apart), the foot (`inv:SetNote(text)`, `inv:SetMoney(copper)`: no money shows until you set it, `nil` hides it), `inv:SetMeta("18 free of 80")`, `inv.onClose`, `inv:SetColumns(n)`. With `characters` (0.12): a character picker in the header (`inv.who`, a bare Select), Bags/Bank (`inv.view`) and All characters (`inv.all`), `inv:SetBanner(text)` (an eye and a caption over the grid), `inv:SetResults(list)` (found items in place of the grid: `{ icon, quality, label, count, places }`; `nil` brings the grid back; returns how many didn't fit) |
| `SuuUI.UI.SkinItemSlot(button)` / `SuuUI.UI.ItemSlot(parent, size)` / `SuuUI.UI.Money(parent)` (0.11) | SuuUI's item slot look on any button (Blizzard's bag slot template included: its own art hidden): `skin:SetItem({ icon, count, quality, dim, locked })` or `nil` for an empty slot; a plain slot (`b.skin`); money as "1,204g 37s 9c" (`m:SetCopper(n)`) |
| `SuuUI.UI.MicroMenu(parent, { name })` | The micro menu panel: `m:SetItems({ { key, glyph, label, click = "<Blizzard micro button>" } or { …, onClick = fn } })` (out of combat: `click` items are secure buttons clicking the Blizzard button; glyphs from `Media/Textures/Glyphs`), `m:SetAlert(key, text)` (the arcane diamond, `nil` clears) |
