# SuuUI public API

Version **0.16.0** (`SuuUI.API_VERSION`). Everything below is on the global `SuuUI`. SuuUI's built-in modules use only this API, so a plugin can do anything they do. Anything not listed here is private and may change without notice.

A plugin is an addon with `## Dependencies: SuuUI` that calls `SuuUI.RegisterModule`. [PluginGuide.md](PluginGuide.md) walks through writing one. `Examples/SuuUI_HelloPlugin` is a complete one, and `Examples/SuuUI_LevelBadge` adds to SuuUI's own unit frames.

## Versioning

The API follows semantic versioning. A module declares the oldest API it works with (`api = "0.1"`). If this SuuUI can't serve it (a different major version, or an older minor), the module is listed as incompatible and never loads. Additions bump the minor version. Breaking changes bump the major version, which is `0` until the first release.

| | |
|---|---|
| `SuuUI.API_VERSION` | `"0.17.0"`. 0.2 added the screen root, components, layouts and motion; 0.3 the settings window and its controls; 0.4 edit mode; 0.5 unit frames; 0.6 anchors, cast bars and the swing timer; 0.7 aura containers; 0.8 action bars; 0.9 roles and party frames; 0.10 alerts and the threat meter; 0.11 a module's own data per character; 0.12 windows, talents, Legacy, the spellbook; 0.13 professions, the right-click menu, filters, whole names and the Social window; 0.14 the world map; 0.15 map marks; 0.16 the Defensives list and Warded; 0.17 the money input, window tabs, the loading mark, IsTooltipSkinned, WINDOW_HEAD_H, the collection sources, ShowTalentsOf, ModelStage, Motion.Reduced, the edit mode's group preview, SetGroupFilter, M:Peek, extending SuuUI's own UI (Each, Hook, Override, Instances), services and `replaces`, the totem bar and duration text bindings, menu entries, micro and game menu items, notification kinds, role preset values, themes, the first-run welcome (ShowWelcome), role presets (RolePresetName, ApplyRolePreset), colour vision (ColorVisionModes, ColorVision, SetColorVision, ColorVisionColor), AccountData, and SuuUI.Raw |
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
    combatSafe = false,           -- true: no secure frames; after a reload in combat it starts at once (0.12)
    replaces = nil,               -- 0.17: a module's id this one stands in for (see Replacing a module)
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
- After a `/reload` in combat, modules start when the fight ends; one marked `combatSafe` (it makes no secure or protected frames) starts at once (0.12).

| | |
|---|---|
| `SuuUI.RegisterModule(def)` | Registers a module; returns it |
| `SuuUI.GetModule(id)` | The module, or `nil` |
| `SuuUI.ListModules()` | A snapshot: `{ id, name, description, state, source, builtIn, error, pendingReload }` for each module. `state` is `registered`, `enabled`, `disabled`, `errored` or `incompatible` |

### Module methods

| Settings (namespace = the module's id) | |
|---|---|
| `M:Get(key)` | The value; a copy for tables |
| `M:Peek(key)` (0.17) | The value itself, not a copy, to read only: a table changed in place changes the profile without its watchers knowing. For large tables read often, where `Get`'s copy would be garbage each time |
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
| `M:Provide(name, functions)` (0.17) | Offers a service other modules reach by name; see *Services and replacing a module* |
| `M:Print(...)` | A chat line prefixed with SuuUI and the module's name |
| `M:IsEnabled()` | |
| `M.id`, `M.name`, `M.description`, `M.api`, `M.source`, `M.builtIn`, `M.state`, `M.error` | SuuUI's own fields: read them, never set them. 0.17: setting one is an error naming the field and the module (keep your own values under other names) |

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
| `SUUUI_ROLE_PROFILES_CHANGED` (0.9) | — (which profile a role uses changed, General › Profiles › By role) |
| `SUUUI_COOLDOWNS_SETUP` (0.8) | — (the Cooldown Manager switched to another spec's setup) |
| `SUUUI_TALENTS_SHOWN` (0.12) | `shown` (SuuUI's Talents window opened, true, or closed, false) |
| `SUUUI_ADDITIONS_CHANGED` (0.17) | `list` (what modules added to a menu or list changed) |
| `SUUUI_SERVICE_CHANGED` (0.17) | `name` (a service came or went) |
| `SUUUI_SPELLS_TO_TRAIN` | `count, cost` (0.12, the Spellbook module: spells you could train now at your class trainer, across every school, and what that costs in copper; `cost` is nil while its Training cost setting is off) |

## Extending SuuUI's own UI (0.17)

Every unit frame, nameplate, cast bar, action button and the rest SuuUI builds is registered by its kind when it's made. A module can reach all of them, now and as each new one is made, and change how they draw. Everything a module adds here is removed when it turns off.

| | |
|---|---|
| `SuuUI.KINDS` | The kinds: `unitframe`, `nameplate`, `castbar`, `auracontainer`, `actionbar`, `actionbutton`, `window` (SuuUI's windows, and Blizzard windows in SuuUI's look: `info.skinned` is the Blizzard frame), `inventory` (bags, bank), `tracker` (objectives), `cooldowns` (the Cooldown Manager), `meter` (`info.meter` is `"damage"` or `"threat"`), `micromenu`, `notification` |
| `M:Each(kind, fn[, undo])` | `fn(object, info)` for every instance of the kind: at once for those that exist, and at the end of the frame each new one is made in (by then its module has placed and tagged it). `undo(object, info)` runs for each when your module turns off: take away what you added |
| `M:Hook(kind, method, fn)` | `fn(object, ...)` after the method runs on any instance of the kind (with the method's arguments). Several hooks run in the order they were added |
| `M:Override(kind, method, fn)` | `fn(object, original, ...)` instead of the method: call `original(object, ...)` to keep SuuUI's drawing. If `fn` errors, the original runs instead. Overrides chain: the last one added is called first |
| `SuuUI.Instances(kind)` | The instances, in the order they were made |
| `SuuUI.InstanceInfo(object)` | `{ kind, module, role, unit, name, preview }`: `module` is the id of the module that made it, `role` what it is there (unit frames: `player`, `target`, `targettarget`, `focus`, `pet`, `boss`, `party`, `raid`; cast bars: `player`, the unit frame's, `nameplate`), `preview` true for a settings preview's stand-in |
| `SuuUI.AddInstance(kind, object, info)` / `SuuUI.TagInstance(object, fields)` | Registers a component of your own as a kind (a module that replaces one of SuuUI's), so other plugins reach it too; adds fields to an instance's info |

Hooks and overrides patch each instance, so they reach frames whose methods were copied onto them. Errors in your functions are reported under your module's name and SuuUI's drawing carries on. In combat a frame's values may be secret: pass them on to the game's own setters, never compare them.

Methods to hook (stable):

| Kind | Methods |
|---|---|
| `unitframe` | `Refresh`, `UpdateHealth`, `UpdatePower`, `UpdateIdentity` (name, class, level), `UpdateRaidMarker`, `SetState(tone, word)` |
| `nameplate` | `Refresh`, `UpdateHealth`, `UpdateName`, `UpdateThreat`, `UpdateBorder`, `UpdateTarget`, `UpdateQuest` |
| `castbar` | `Start`, `Stop`, `Refresh`, `SetInterruptible` |
| `actionbutton` | `Update`, `UpdateCooldown`, `UpdateUsable`, `UpdateActive`, `UpdateCount`, `UpdateArt` |
| `actionbar` | `Layout`, `UpdatePage` |
| `auracontainer` | `SetUnit`, `Refresh` |
| `tracker` | `SetQuests`, `DrawQuest(row, quest)` |
| `cooldowns` | `Build`, `Layout`, `UpdateCooldowns` |
| `inventory` | `LayoutSlots` |
| `meter` | `Refresh` (damage), `SetRows` (threat) |
| `micromenu` | `SetItems`, `SetActive` |
| `notification` | `SetData` |

### Services and replacing a module (0.17)

What one module does for others goes through a **service**, named, with a table of functions. A module provides one with `M:Provide(name, functions)`, removed when it turns off. Callers use `SuuUI.Service(name)` (nil while nothing provides it) or the API functions built on it, never the module itself.

| Service | Functions | Used by |
|---|---|---|
| `bags` | `Toggle()` | `SuuUI.ToggleBags()` |
| `talents` | `Toggle()`, `ShowInspect(unit)`, `IsShown()` | `SuuUI.ToggleTalents()`, `ShowTalentsOf(unit)`, `TalentsShown()` |
| `collections` | `Toggle(tab)`, `IsShown()` | `SuuUI.ToggleCollections(tab)`, `CollectionsShown()` |
| `professions` | `OpenRecipe(recipeID)`, `ExpectRecipe(recipeID)`, `ShownRecipe()` | `SuuUI.OpenRecipe`, `ExpectRecipe`, `ShownRecipe` |
| `notifications` | `Notify(def)` → id, `Dismiss(id)` | `SuuUI.Notify`, `DismissNotification` |
| `alerts` | `Show(key, tone, title, detail, ...)`, `ShowLevelUp(key, def)`, `Hide(key)`, `AllowOutOfCombat(key)` | `SuuUI.ShowAlert`, `ShowLevelUp`, `HideAlert`, `AllowAlertOutOfCombat` |

`SUUUI_SERVICE_CHANGED(name)` fires when a service comes or goes.

**Replacing a module.** A module with `replaces = "bags"` stands in for SuuUI's Bags module. While it is on, the Bags module stays off ("Replaced by …" in Settings › Modules and `/suu modules`). Whether a module is replaced is decided at login, so turning the replacement on or off takes a `/reload`. To stand in fully, the replacement:
- provides the replaced module's services, if it has any;
- publishes the same anchors (`SuuUI.PublishAnchor`);
- registers its frames as the same kind (`SuuUI.AddInstance`) so other plugins' `Each` and hooks reach them;
- registers movers and settings of its own.

### Menus, buttons and presets (0.17)

Entries a module adds here are its own, and they go away when it turns off.

| | |
|---|---|
| `M:ExtendMenu(id, fn)` | `fn(menu, context)` before one of SuuUI's right-click menus opens: `menu.title`, `menu.items` (each `{ label, onClick, disabled }` or `{ separator = true }`; add, insert or remove). Menus and their context: `quest` (`questID`, the objective tracker), `trackedRecipe` (`recipeID`), `chatPlayer` (`name`, a name in chat), `chatTab` (`chatFrame`, a whisper tab), `guildMember` (`member`), `friend` (`row`), `recentAlly` (`row`), `groupMember` (`member`, Social › Group). `UI.ContextMenu(owner, { id, context, … })` and `UI.ContextMenuFrom(owner, fn, id, context)` give your own menus an id too |
| `M:AddMicroItem(item)` | A micro menu button: `{ key, label, glyph, onClick, open = fn → shown, bind }` (`glyph`: one of SuuUI's glyphs; `open` lights the button while your window shows; `bind` the binding whose key its tooltip shows). It comes before the game menu's button; a new one starts shown, and the player can hide it under Micro menu › Buttons |
| `M:AddGameMenuItem(item)` | An entry in SuuUI's game menu: `{ group = "Game"\|"Help"\|"Session"\|your own, label, glyph, onClick, blocked = fn → reason }` (the menu closes, then `onClick` runs; while `blocked` returns a reason the entry is dimmed and its tooltip says why). A group of your own comes before Session |
| `M:AddNotificationKind(which, def)` | A game popup (`StaticPopupDialogs[which]`) shown as a notification card: `def = { category, glyph, tone, primary = button index, danger = button index, item = true (the item it's about), confirm = true (a typed confirmation) }` |
| `M:AddToRolePreset(role, values)` | Your module's own settings in a role's preset (`"TANK"`, `"HEALER"`, `"DAMAGER"`): `values = { key = value }`. Applying a preset (Settings › Profiles › Role presets) sets them in SuuTank, SuuHeal or SuuDps; a key you set for one role goes back to its default in the others |
| `SuuUI.Additions(list)` | What modules added to `"micromenu"`, `"gamemenu"`, `"notificationkinds"` or `"rolepresets"`, for a module that draws one of them itself. `SUUUI_ADDITIONS_CHANGED(list)` when one changes |

Settings: a module's settings section with `merge = "<section id>"` adds its groups to that built-in page (e.g. `merge = "unitframes"`), instead of a page of its own.

### Themes (0.17)

| | |
|---|---|
| `SuuUI.RegisterTheme(def)` | A theme the player can pick in Settings › General › Appearance › Theme: `{ id, name, description, colors = { [token] = { r, g, b[, a] } }, fonts = { [style] = { file, size, lineHeight } } }`; `colors` can also be `function(class)` returning that table, worked out at login for the player's class (`"MAGE"`, …). SuuUI ships its own: High contrast, Class accent, Darker, OLED black. `colors` change design tokens (`SuuUI.Tokens.color`; a token's own alpha is kept unless you give one), `fonts` change text styles (`SuuUI.Tokens.type`; keep `size` within the style's `lineHeight`). Register it when your addon's files load: the chosen theme applies at login, before SuuUI builds its frames, and a change takes a reload. Colour vision applies on top of it. An unknown token or style is an error |

### Raw access (unstable)

`SuuUI.ProbeShowsBlizzardSocial()` is internal: a diagnostic's switch, not for plugins.

`SuuUI.Raw` is everything SuuUI is made of, for what the API above doesn't cover. **It may change in any version, without an API version bump**: a plugin using it should check what it finds.

| | |
|---|---|
| `SuuUI.Raw.UI` | Every component, the ones not exported too |
| `SuuUI.Raw.Mixins` | The components' method tables by name (`UnitFrame`, `ActionButton`, `CastBar`, `AuraContainer`, `ActionBar`, `Panel`, `WindowChrome`, `Inventory`, `ObjectiveTracker`, `CooldownTracker`, `DamageMeter`, `ThreatMeter`, `MicroMenu`, `Notification`). Most are copied onto each frame when it's made: a change made when your plugin loads reaches every frame SuuUI builds later (its modules build at login) |
| `SuuUI.Raw.Module(id)` | A module with its internals |
| `SuuUI.Raw.ns` | SuuUI's private namespace |

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
| `MoneyInput(parent, { value, onChange })` (0.17) | An amount as gold, silver and copper fields with their coin letters: `:GetCopper()`, `:SetCopper(copper)`, `:Clear()`, `:SetDisabled(disabled)`; `onChange(copper)` as it's typed |
| `LoadingMark(parent, { size, wings })` (0.17) | The SuuUI emblem for long waits: the gilt-framed diamond with its cyan gem, gilt wing lines ending in small diamonds (4 × `size` wide, 1.2 × `size` tall; `wings = false`: the mark alone, `size` square; `size` default 60). `:Start()` shows it, assembles it (0.6 s) and lights the gem's facets in turn every 1.6 s until `:Stop()` hides it. Still with `ui.reducedMotion`. Not for waits under a second |
| `ModelStage(frame, { floor, shade })` (0.17) | The model stage (the Collections and dressing room stage) drawn on a frame, under a 3D model: a gradient base, a soft key light, a floor band with its glow and a contact shadow, vignette edges and a gilt-faint frame. `floor`: the shadow's height above the bottom (default 40); `shade`: a card strip's width at the left. `frame:CentreOn(x)` moves the light, glow and shadow under a model `x` px off the middle (and `frame.ctl`, when set); `frame:Tint(token)` warms the light and glow in a token's colour |
| `WindowFrame(parent, { name, title, meta, keybind, width, height, footer, onClose, tabs, onTab })` | The shell of every full window: draggable, Escape closes it (with a `name`), content in `window.content` (scrolls), optional `window.footer`; 0.17: `tabs = { { key, label } }` puts text tabs under the title, `window:SetTab(key)` chooses one and calls `onTab(key)`; 0.17: a tab's `disabled` (true or a function) and `reason`: ink-faint at opacity-disabled, a cover takes its click and its tooltip says why; `window:DrawTabs()` after what it depends on changed |
| `Button(parent, { text, variant = "quiet" or "primary", onClick, width, disabled, tooltip, icon })` | `:SetLabel(text)`, `:SetEnabledState(enabled)` (0.15: a disabled button still shows its `tooltip` on hover, the place to say why it's off); `icon` (0.13): a glyph name (`"reset"`, `"close"`), 12px left of the label; `:SetIcon(name)` changes it (nil: none) |
| `CloseButton(parent, onClick)`, `KeyChip(parent, key)` | Header pieces |
| `StateBadge(parent, tone, text)` | Tones: `danger`, `warning`, `magic`, `curse`, `poison`, `disease`, `ward`, `info`, `neutral`; `:SetState(tone, text)` |
| `Crest(parent, variant)` (0.17) | The rare and elite crest: `"frame"` (wings both ways, for a unit frame's top edge) or `"plate"` (one wing, beside a nameplate bar); `:SetClassification(UnitClassification(unit))` shows elite, rare, rare elite or world boss and hides otherwise (a secret classification too). A unit frame's `opts.crest` puts one over its right end; with `opts.dragon` the game's own elite dragon shows in its place |
| `DragonArt(classification, isBoss)`, `PlaceDragon(texture, art, anchor, height)` (0.17) | The game's elite dragon: the art for a classification (elite gold, rare and rare elite winged silver, a boss winged gold; nil otherwise), and that art set on `texture` round the right end of `anchor`, `height` tall (nil art hides it) |
| `Icon(parent, size)` | `:SetArt(texture)`, `:SetState("rest"/"ready"/"dim"/"active")`, `:SetBorder(token)`, `:SetGlow(shadowToken)`, `:SetCount(n)`, `:Pop()` |
| `StatusBar(parent, { width, height, fill, deep, track, border, ghost })` | `:SetMinMax(min, max)`, `:SetValue(v)` (secret values are fine; the ghost drains after 150ms), `:SetValueNow(v)`, `:SetFill(fill, deep)` |
| `Text(parent, style, color)` | A FontString in a text style: `:SetValue(v)` (secret-safe, skips unchanged readable values), `:SetStyle`, `:SetColor`, `:SetShadowed`, `:SetFixedWidth`, `:SetVisible` |
| `ShowTooltip(owner, data)`, `HideTooltip()`, `AttachTooltip(frame, data)`, `TooltipFrame(parent)` | SuuUI's tooltip. `data`: `{ title, titleColor, subtitle, lines = { { left, right } }, description, meta }` ; 0.17: a line's `gap` (space before it), `data.maxWidth` (default 280: wider, and a description then wraps at that width), `RefreshTooltip(owner)` asks a `data` function again while the tooltip shows for `owner` (a modifier key changed what it says) |

Drawing helpers: `Fill(parent, color, layer)`, `Border(frame, color, { width, inset, layer })` (stays one physical pixel), `Hairline(parent, color, fade = "out"/"both"/nil)`, `Diamond(parent, size, color)`, `Shadow(frame, shadowToken)`, `SoftEdge(frame)`, `Cross(parent, size, color)`, `RGBA(token[, alpha])`, `Size(token)`.

## Layout and motion (0.2)

| | |
|---|---|
| `SuuUI.Layout.Stack(container, { direction, gap, padding, align, autoSize })` | Lays out `:Add(child[, { gapBefore }])`ed children in a row or column, once per frame. Texts whose value may be secret need a fixed width |
| `SuuUI.Layout.Grid(container, { columns, cellWidth, cellHeight, gap, padding })` | Fixed cells, row by row |
| `SuuUI.Motion.FadeIn(frame[, duration])`, `.Enter(frame[, duration])`, `.Pop(frame)`, `.Stop(frame)` | The design's presets; nothing animates with `ui.reducedMotion` on |
| `SuuUI.Motion.Reduced()` (0.17) | Whether `ui.reducedMotion` is on, for motion of your own (text that types in shows at once) |

## The settings window (0.3)

`/suu` opens it; so do the "SuuUI settings" button under the game menu and `SuuUI.OpenSettings([sectionId])`. `SuuUI.ToggleSettings()` (0.10) opens it, or closes it while it's open.

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
| `Select(parent, { options, value, onChange, multiple, width, placeholder, maxShown })` | One (or several) of a longer list; `:SetOptions(options)`. Nothing chosen shows the placeholder in ink-muted (0.13; a multiple select without one reads "None") |
| `Slider(parent, { min, max, step, value, unit, format, width, onChange })` | A size or amount you judge by eye |
| `Stepper(parent, { min, max, step, value, unit, onChange })` | An exact number, in whole steps from `min` |
| `TextField(parent, { width, placeholder, value, onChange, onTextChanged })` | Text; `onChange` on Enter or when it loses focus |
| `AnchorPicker(parent, { value, onChange })` (0.9) | One of the nine points (`"TOPLEFT"` … `"BOTTOMRIGHT"`, `"CENTER"`) on a 3×3 grid of diamonds, the chosen one larger and arcane, each point's name in its tooltip. No offsets. Default `"TOPRIGHT"` |
| `SwatchRow(parent, { options, value, onChange })` (0.9) | A colour token from a row of swatches: `options = { { value = token, label } }`, the chosen one ringed in arcane, the label in its tooltip |
| `ToggleChips(parent, { options, value, onChange })` (0.9) | On/off chips for choices that combine (`options = { { value, label } }`): the value is a list of the options that are on, and `onChange` gets that list; `:GetValue()` |
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
| `SuuUI.EditMode.GroupPreview()` / `.SetGroupPreview(size[, auras])` (0.17) | The edit mode panel's Group preview: made-up players fill the party frames (5) or the raid frames (10, 20, 40) at their real place and size while edit mode is open; 0 is off. `auras`: everyone carries defensives and a debuff of every type, and made-up auras fill your buffs and debuffs and the target's, focus's and bosses' ("Buffs and debuffs on every frame"; it works without a group size too). `GroupPreview()` returns size, auras. `SUUUI_EDITMODE_GROUP_PREVIEW(size, auras)` fires when either changes, and with 0 when edit mode closes |

Settings: `layout.snap`, `layout.gridSize` (4–32 px).

## Anchors (0.6)

Modules find each other's frames through published anchors, never through each other's internals.

| | |
|---|---|
| `SuuUI.PublishAnchor(name, frame)` | Publishes a frame under a name (`nil` unpublishes) |
| `SuuUI.GetAnchor(name)` | The frame, or `nil`; listen to `SUUUI_ANCHOR_CHANGED` for changes |

Published by SuuUI: `microMenu` (0.12: the micro menu; windows that join its row line up under it), `player`, `target`, `targettarget`, `focus`, `pet`, `boss1` … `boss5` (unit frames), `party` and `raid` (the group frames' holders), `playerBuffs` (0.12: your buffs' holder while they show), `encounterTimeline` (0.17: the encounter timeline while it is on).

## Unit frames and cast bars (0.5, 0.6)

| | |
|---|---|
| `SuuUI.UI.UnitFrame(parent, unit, opts)` | The unit frame; `:Activate()`, `:Deactivate()`, `:Refresh()`, `:SetState(tone, word)`; 0.9: `:SetUnit(unit)`, `:Resize(w, h)`, `:SetDispelBadges("all"|"removable"|"off")` (debuff-type border and badge, in combat too) (out of combat) and the opts `height`, `lowHealth`, `incoming`, `powerFor(unit)`. See `UI/UnitFrame.lua` for `opts`; 0.9 too: the opt `raidMarker = true` (the raid target icon over the top edge; `:UpdateRaidMarker()`), and a built-in offline state ("Offline" in the right-hand text, an empty bar, a faint name, no power line) |
| Buff indicators (0.9) | `f:SetIndicators(list)` (live, out of combat) and `f:SetPreviewIndicators(list)` on a unit frame; `SuuUI.UI.GroupIndicators()` (list, version) and `SuuUI.UI.SetGroupIndicators(list)` (emits `SUUUI_INDICATORS_CHANGED`); an indicator is `{ name, ids, kind = "icon"|"square"|"border"|"fill", point, size, color, source = "mine"|"any" }`, `SuuUI.UI.INDICATOR_POINTS` lists the points |
| Defensives and Warded (0.16) | `SuuUI.UI.GroupDefensives()` (`{ external, defensive, warded, all }`, each a list of spell IDs, and a version) and `SuuUI.UI.SetGroupDefensives(d)` (emits `SUUUI_DEFENSIVES_CHANGED`; the Defensives module sets them from Frames › Defensives, nil clears them): which buffs party and raid frames show in their external and defensive slots, leave out of their other buffs, and take as Warded. The game hides who cast another player's buffs and its own defensive filters then let every buff through, so the frames go by these lists. On a unit frame: `f:SetWardSpells(ids)` (out of combat; the first call makes an engine slot: while one of the spells is up the frame shows the Warded badge, the `ward` border and glow, in combat too; a debuff type's badge covers it, it covers Aggro's), `f:WardDecoration(parent)` (that look over the frame, on `parent`; `deco:SetWarded(on)` for previews). `SuuUI.Defensives()`: SuuUI's default list, `{ { name, kind = "external"|"defensive", ward, note, ids } }` (generated `Data/Defensives.lua`) |
| `SuuUI.UI.GROUP_TIERS` (0.9) | `{ "5", "10", "20", "40" }`: the group sizes an indicator can be limited to, with `sizes = { ["10"] = true, … }` on the indicator (nil or empty: every size) |
| `SuuUI.UI.GroupTier([count])` (0.9) | The current group's size tier: `"5"` in a party or with no group; in a raid the smallest of `"10"`, `"20"`, `"40"` it fits in. With `count`, the tier for that many players (5 or fewer is `"5"` only outside a raid) |
| `SuuUI.UI.IndicatorsFor(list, tier)` (0.9) | The indicators of `list` active at `tier`: those without `sizes` (or with an empty one), and those whose `sizes` holds the tier |
| `SuuUI.UI.UnitStandIn(person)` (0.9) | Stand-in Unit* functions for a preview: `person(unit)` returns `{ name, class, role, health (0-1), max, power, incoming, absorb, dead, you, offline, marker (1-8) }`; pass the result as a unit frame's `opts.api`; the stand-in also answers `UnitIsConnected` and `GetRaidTargetIndex` |
| `SuuUI.UI.UnitFrameCurveValue(curve, x)` (0.9) | What one of a unit frame's curves (the ones it passes to `UnitHealthPercent` and `UnitPowerPercent`) gives for a 0-1 fraction `x`: the low-health and low-mana steps 1 below their threshold and 0 from it; the low-health tint 0.55 at 10% and below, falling to 0 at 70%; nil for any other curve. For stand-ins that work curves out themselves (`UnitStandIn` uses it) |
| `SuuUI.UI.LevelColor(level)` (0.17) | A colour token for a level by how hard it is for you, as the game rates it: `quest-trivial` (grey), `quest-standard` (green), `quest-difficult` (yellow), `quest-very-difficult` (orange), `quest-impossible` (red, also for an unknown or secret level). The target frames' and tooltips' levels use it |
| `SuuUI.UI.RaidMarker(parent, size[, layer])`, `SuuUI.UI.ShowRaidMarker(texture, unit[, api])` (0.9) | A raid target marker texture (hidden until shown), and the unit's marker on it or hidden; a marker that is secret in combat still shows (through the texture's sprite sheet cell). Unit frames and nameplates use them |
| `SuuUI.UI.DEBUFF_TYPES` (0.9) | `{ "Magic", "Curse", "Poison", "Disease" }`: the debuff types a unit frame shows a border and badge for (`:SetDispelBadges`), in drawing order: with several up, the first in the list is on top |
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
| `SuuUI.UI.AuraContainer(parent, unit, opts)` | An engine aura container styled as the design's AuraIcon. `opts`: `size` (token), `anchor`, `growth` (`{ "LEFT", "UP" }`), `lineWidth`, `groups` (`{ key, filter = { "HARMFUL", "PLAYER" }, max, dispel, cancel, drain }`). Returns `{ container, ... }` with `:SetUnit(unit)`, `:Refresh()`, `:SetGroupMax(key, n)`; 0.9: `:SetFlow(anchor, growth)`, `:SetLineWidth(px)`, `:SetGroupSize(key, size)` (live; out of combat, as the engine's buttons refuse it in combat), `:Release()` (containers can never be freed: a released one has no unit, is hidden and stops listening until the next `:SetUnit(unit)`, so whoever rebuilds can reuse it). Addon code can't read auras in combat, so the engine fills it 0.17: `c:ShowPreview({ { icon, border } }, place)` / `c:HidePreview()`: made-up icons laid out as the engine lays out its own (corner, growth, line width, first group's size), the engine's out of sight meanwhile; `place = { point, relativeTo, relativePoint, x, y }` is where you put the container (the game neither lets a frame anchor to an aura container nor gives its point) |
| Group options (0.9) | `include = { spellIDs }` (only those spells), `dispelTypes = { "Curse" }` (only debuffs of those types, matched by the engine in combat too), `initialize = fn(button)` (build the button yourself, once, when the engine creates it: decorations hung on it show and hide with it, which is how party frames draw a debuff type's border and badge in combat) |
| Group options (0.16) | `exclude = { spellIDs }` (never those spells; with `include` too), `harmfulEdge = true` (the ember edge on a debuff, which a typed debuff's dispel border covers: every debuff row has it, so a debuff never looks like a buff). `c:SetGroupSpells(key, ids, exclude)` changes both after creation (out of combat). 0.17: `index = n, gap = px`: a group's place among the container's groups (lower first) and the extra space before it when icons precede it, so one row can hold sets that follow each other however many icons each shows; `c:SetGroupPlace(key, index, gap)` changes them live. 0.17: `c:SetGroupFilter(key, filter)` changes a group's filter live, so one group can serve whoever the unit is; with the container's `lazy = true`, a group whose `max` is 0 goes into the engine only when `SetGroupMax` first gives it a count (the engine makes ten buttons for every group up front, whatever its count) |

## Action bars (0.8)

SuuUI's own secure buttons: no Blizzard button template. Make them out of combat.

| | |
|---|---|
| `SuuUI.UI.ActionBar(parent, opts)` | Up to 12 buttons on a secure header. `opts`: `name` (global name; buttons are `name .. "Button" .. i`), `slot` (first action slot), `count`, `columns`, `gap`, `size`, `binding` (the game's binding command prefix, e.g. `"MULTIACTIONBAR1BUTTON"`: every key bound to it clicks the button), `paging` (macro conditions, e.g. `SuuUI.UI.ActionBarPaging()`), `onPage(bar, page)`. Returns a bar with `.header`, `.buttons`, `:Page()`, `:SetHotkeysShown(on)`, `:SetShowEmpty(on)`, `:Layout(columns, gap)`, `:UpdateBindings()` |
| `SuuUI.UI.SetVisibility(frame, mode, also)` | When a frame shows: `"always"`, `"combat"` (a secure driver, so it works for frames holding secure buttons), `"mouseover"` (fades in while the mouse is over it or you drag something) or `"hidden"`. 0.9: `also`, a list of frames outside `frame` whose hover counts as its own for mouseover; setting the mode a frame already has changes nothing. Edit mode and keybind mode show every managed frame that isn't hidden (keybind mode the pet bar too). Bars: `bar:SetVisibility(mode)`, `bar:Layout(columns, gap, count, size)` |
| `SuuUI.UI.VISIBILITY_OPTIONS` (0.9) | The `{ value, label }` choices `"always"`, `"combat"`, `"mouseover"`, for a settings row's `options` |
| `SuuUI.UI.ActionBarPaging()` | Bar 1's paging on Forever: override and vehicle bars, manual pages 2–6, then stance/form pages 7–10 |
| `SuuUI.UI.ActionButton(parent, name, size)` | One button's art on a `SecureActionButtonTemplate` button (the bar sets the secure attributes). `:SetSlot(slot)`, `:SetHotkey(text)`, `:SetHotkeyShown(on)`, `:Update()` |
| `SuuUI.UI.SetActionTextSize(px)` | The size of the text on every SuuUI action button (key binding, count, cooldown numbers), in px, never below `micro` (9.5). Buttons made later take it too |
| `SuuUI.UI.ShortKey(key)` | A binding in button size: `"SHIFT-1"` → `"S1"`, `"BUTTON4"` → `"M4"` |
| `SuuUI.UI.StanceBar(parent, { name })` | Your stances or forms as `action-sm` buttons, one per form you know. `.header`, `:SetEnabled(on)`, `:SetHotkeysShown(on)` |
| `SuuUI.UI.TotemBar(parent, { name, label, page, onPage, onLayout })` (0.17) | A shaman's totem bar: earth, fire, water and air as `action-sm` buttons that cast the totem the game's totem bar holds for each (left click; right click dismisses it), a strip above them with each totem's time left and drain, Totemic Recall at the strip's end while a totem is down, Call of the Elements after a hairline once learned; an element with no totem yet is dashed. Hovering an element shows an arrow that opens the list of its totems (out of combat). `.header`, `:SetButtonSize(px)`, `:SetEnabled(on)`; `onLayout(bar)` after it lays itself out. Sets: `opts.page` (1-3: Call of the Elements, of the Ancestors, of the Spirits, each with its own four totems), `onPage(page)` when the player picks another from the Call button's arrow, `:SetPage(page)` (out of combat) |
| `SuuUI.UI.DurationTextBinding(fontString[, expiringSeconds])` (0.17) | A text line the engine keeps showing a duration object's time left, in the aura icons' format ("42", "1:30", "5m"), amber below `expiringSeconds` (3): `b:SetDuration(d)`, `b:SetEnabled(on)`. Works in combat, where the duration's values are secret. Nil on a client without duration text bindings |
| `SuuUI.UI.PetBar(parent, { name })` | The pet's 10 actions, shown while you have a pet; right click toggles autocast. `.header`, `:SetEnabled(on)`, `:SetHotkeysShown(on)` |
| `SuuUI.UI.MakeModal(panel)` | Makes a panel a modal: centred over a dimmed screen (the game can't blur its interface), taking every click; Esc or a click on the shade closes it. `:Show()`/`:Hide()` as usual |
| `SuuUI.UI.ScrollArea(parent[, bar])` (0.9) | A mouse-wheel scroll frame; put content in `area.child` and size it to the content. With `bar`, a thin scrollbar sits `bar` px right of the area while the content overflows (the settings window and the Behaviour panel use it) |
| `SuuUI.UI.Confirm({ title, text, confirm, cancel, onConfirm, onCancel, input, typeToConfirm, enterConfirms })` | A modal yes/no question; Cancel, Esc or a click outside counts as cancel; 0.13: `input = { label, placeholder, value }` (a text to enter, given to `onConfirm(text)`), `typeToConfirm = "WORD"`; 0.17: `enterConfirms = false` (Enter in the field leaves the dialog open: only the button confirms). Returns the dialog (`.ok`, `.field`) |
| `SuuUI.UI.CooldownTracker(parent, { name })` | SuuUI's own Cooldown Manager: `:SetLists({ essential, utility, buffs, debuffs, procs })` (entries `{ name, ids, mine }`; a group `{ group = true, name, members = { { name, ids, icon, source }, ... }, ids, source, max, icon, fixedIcon }`: in an aura list one slot whose members show while up, members of different `source`s getting one engine group each; with none up the slot shows `icon` when `fixedIcon` is true, else an automatic one: the first member (of those its conditions leave in) that you know, else the first whose `when` is met, else `icon` (a member's art: its `icon`, else its first ID; picked again on each rebuild); in essential or utility one cooldown, the last member you know, members in order of preference; a collection `{ collection = true, uid, name, hidden, entries }`, aura lists only, its entries (single entries and groups) shown side by side in its place), `:SetOptions({ essentialSize, utilityInline, readyPop, procHighlight })` (what an aura does while missing is its entry's own `missing`: buffs `"grey"`, debuffs `"target"` unless set); 0.9: `:Stop()` (no events, aura sounds or containers in use) and `:Start()` (again; a new tracker runs). Cooldowns are its own icons; buffs, debuffs and procs are engine aura containers with spell lists. Any entry, group, group member or collection may carry `when` (see `SuuUI.UI.CooldownConditionMet`): not met, it's left out (a member: out of its slot); a collection's applies to its entries too |
| `SuuUI.UI.CooldownConditionMet(when)` | Whether a Cooldown Manager condition is met now. `when = { match = "all"\|"any", conditions = { ... } }` (default `"all"`), each condition `{ type, ..., ["not"] = true? }`: `{ type = "group", value = "solo"\|"group"\|"raid" }` (a raid counts as a group), `{ type = "classes", classes = { "DRUID", ... }, others = true? }` (anyone in your group, you too; with `others`, only the others), `{ type = "role", roles = { "TANK"\|"HEALER"\|"DAMAGER", ... } }` (`SuuUI.Role()`), `{ type = "stance", stances = { "battle", "defensive", "berserker", "caster", "bear", "cat", "moonkin", "travel", "aquatic", "stealth", "shadowform" } }`, `{ type = "combat" }`, `{ type = "instance", kinds = { "none", "party", "raid", "pvp" } }` (an arena is pvp), `{ type = "target", kinds = { "boss", "elite", "player", "normal" } }` (one kind per target: player, else boss, else elite, else normal; no target matches none), `{ type = "talent", talents = { spellID, ... } }` (you've learned any of them: a node with a rank in the active talent config, or a spell you know; any class's IDs may be listed, another class's are never learned). No `when`, no conditions, or a condition with an empty list: always met. The tracker checks group, classes, role, instance and talent when it builds (rebuilding after combat when they change) and stance, combat and target in place, in combat too |
| `SuuUI.UI.TrackerSound(key)` | Plays one of the Cooldown Manager's sounds: `"chime"`, `"ping"`, `"proc"` or `"warning"` (a sound file on the Master channel, or its sound kit when the file won't play). Any other key plays nothing |
| `SuuUI.CooldownPresets()` | Your class's presets: `{ { id, name, lists } }`, every entry carrying all the IDs with its name in Forever's client; groups and collections as for `:SetLists` (no `uid`: the Cooldown Manager gives each one when it copies a preset) |
| `SuuUI.ClassTalents(class)` (0.9) | Every talent of a class, any of the nine (generated from the class data, `Data/Talents.lua`): `{ { id = spellID, name, tree = 1-3 }, ... }`; nil for an unknown class. The Cooldown Manager's talent condition picks from it |
| `SuuUI.AuraCatalog()` (0.9) | Every aura any class's presets track (their buffs, debuffs, procs and cooldowns' effects): `{ [name] = { classes = "Priest", ids = { ... } } }` (generated `Data/AuraCatalog.lua`). The Cooldown Manager's "+ Add" offers them to every class, noting the class |
| `SuuUI.KeybindMode.Enter()`, `.Exit()`, `.Toggle()`, `.IsActive()` | Keybind mode (`/suu keybind`): hover a button, press a key. It binds the game's own command for the button, so the game's Key Bindings window shows it too. Message: `SUUUI_KEYBINDMODE_CHANGED (active)` |
| Keybinds settings (0.9) | General › Keybinds, in the `actionbars` namespace: `showKeys` (show key bindings on buttons at all) and `keyBars` (the bars that show them: a list of `"1"` … `"8"`, `"stance"`, `"pet"`) |
| Bindable buttons | A button made with `SuuUI.UI.ActionButton` takes part in keybind mode when it has `b.bindCommand` (a game binding command) and `b.bindLabel`; `ActionBar`, `StanceBar` and `PetBar` set both |

## Alerts and the threat meter (0.10)

| | |
|---|---|
| `SuuUI.ShowAlert(key, tone, title, detail, ...)` | One alert at a time, centred 320px down from the top of the screen, in combat only (the Alerts module; nothing while it's off). `tone`: `"danger"`, `"warning"` or `"info"`. `detail` is text, or a format whose arguments may be secret (a target's name in a dungeon); plain text may hold several lines (`\n`, 0.12: the band grows down). The same `key` updates its alert in place; a new key replaces the alert showing unless that one is more urgent (danger > warning > info); the replaced one comes back when the new one goes, unless its owner hid it meanwhile (0.12). Combat ending clears it. Danger alerts can play a sound |
| `SuuUI.HideAlert(key)` | Takes that key's alert away (raise an alert while its reason holds, hide it when it doesn't) |
| `SuuUI.ShowLevelUp(key, def)` | 0.12: the level-up card (`UI.LevelUp`) in the alert's place, tone info: `def = { title, detail, spells = { { icon, name, rank, isNew, note, text, meta } }, more, cost }` (note: ink-faint words after the rank, "Level 18"; `text` and `meta` go in the spell's tooltip). The card stays while the mouse is over it, until a second after it leaves (cost in copper; one column up to four spells, two from five, at most ten). `HideAlert(key)` takes it away |
| `SuuUI.UI.Alert(parent)` | The alert band itself: `a:SetAlert(tone, title, detail[, ...])` sizes it to its text (a detail with a secret argument can't be measured: the band is then at least `notice-w` wide and cuts it) |
| `SuuUI.UI.LevelUp(parent)` (0.12) | The level-up card itself (what `ShowLevelUp` shows): `c:SetLevelUp({ title, detail, spells = { { icon, name, rank, isNew, note, spellID, text, meta } }, more, cost })` (`more`: a line such as "+ 3 more"; cost in copper). Hovering a spell with a `spellID` shows the game's spell tooltip with `meta` as its last line, else SuuUI's tooltip (name, rank, `text`, `meta`). The card takes the mouse: `c:IsHovered()`, `c.onClick` (a click on it). One column up to four spells, two from five, at most ten rows |
| `SuuUI.UI.ThreatMeter(parent, { rows })` | The threat meter panel, `meter-w` wide and always `rows` rows tall (default 8). `m:SetTarget(name)` (may be secret); `m:SetRows(list, opts)`, `list` in group order: `{ name, class, role ("TANK", "HEALER", "DAMAGER", "PET"), status (0-3, nil unknown), percent (scaled, possibly secret), raw (possibly secret), you }`; `opts`: `show` (`"group"`, `"tanks"`, `"self"`), `byState` (order by threat state then group, with the boss note; otherwise by %, ranked), `marker` (`"role"`, `"class"`, `"none"`), `raw` (show the threat value; readable ones only), `nameColor` (`"class"` or `"ink"`). States come from the status alone: Aggro, Pulling, Losing, Tanking |
| `m:SetMaxRows(n)` | The threat meter's height in rows, live (the Threat meter module matches the damage meter's Rows) |
| `SuuUI.UI.DamageMeter(parent, opts)` | One damage meter window on Blizzard's data (`C_DamageMeter`): `meter-w` wide, a head with the type and fight selects, the fight's time and a menu, then `rows` rows. `opts`: `rows`, `onView(type, session)`, `onNewWindow`, `onClose` (shows "Close this window"), `onReset`, `onSettings`. `w:SetView(type, session)` (`type` one of `SuuUI.UI.DAMAGE_METER_TYPES`' values: `"damage"`, `"dps"`, `"damageTaken"`, `"avoidable"`, `"enemyDamageTaken"`, `"healing"`, `"hps"`, `"interrupts"`, `"dispels"`, `"deaths"`; `session` `"current"`, `"overall"` or a sessionID), `w:SetOptions({ numbers = "minimal"\|"compact"\|"complete", barColor = "neutral"\|"class", marker = "icon"\|"diamond"\|"none", nameColor = "class"\|"ink", pinYou })`, `w:SetMaxRows(n)`, `w:SetCanAddWindow(on)`, `w:Refresh()` (read the data again; the caller drives it: about once a second in combat, on the meter's events out of it). Rows keep the engine's order; secret amounts and names go to the engine untested; your row opens your spell breakdown any time, others' after combat; deaths open their recap |
| `SuuUI.AllowAlertOutOfCombat(key)` | That key's alerts may also show out of combat (the pull countdown's) |
| `SuuUI.UI.EncounterTimeline(parent, { variant, window, soonAt })` | The encounter timeline: `"track"` (a line `timeline-w` wide, now at the left, `window` seconds, default 30, to the right; abilities ride toward now, amber under `soonAt`, default 5) or `"list"` (the older panel). `t:SetEvents({ { id, label, icon, badge = { tone, text }, endsAt (GetTime() it happens) or paused (seconds left, frozen) } })` (it moves them every frame while it has any), `t:SetVariant(v)`, `t:SetMeta(text)` (the list's head) |
| `SuuUI.UI.Readiness(parent, { onReadyCheck })` | The readiness panel (340px, "Readiness · before pull"): `r:SetRows({ { icon, spell, who, class, endsAt } })` (no `endsAt` or a past one: "Ready" in arcane; otherwise the time left, the icon dim), `r:SetActionShown(on)` (the Ready check button in the foot) |
| `SuuUI.UI.ObjectiveTracker(parent, { width, maxHeight, toggle })` (0.11) | The objective tracker on the world: `t:SetQuests({ { questID, title, difficulty ("trivial" … "impossible"), complete, failed, turnIn, tooltip, objectives = { { text, progress, done } }, item = { preview = true, icon } } }, freeze)` (`freeze`: places kept and heights only grow, for secure item buttons beside titles in combat), `t:QuestTop(questID)` (the title's offset down from the top, for such a button), `t:SetCollapsed(on)`, `t:SetMeta(text)`, `t.onQuestClick(questID, button, row)`, `t.onToggle`; `toggle`: your own (secure) toggle button, drawn by the tracker, placed by you at its top left (`UI.TRACKER_HEAD_H` square) |
| `SuuUI.AddFriend(name)` (0.13) | A friend request by a character's whole name, from a click: Forever's own way (`C_BattleNet.SendTitleFriendInviteByName`; its classic friends list is off, so `C_FriendList.AddFriend` does nothing). Returns true when sent |
| `SuuUI.Notify({ id, kind, category, title, body, icon, tone, duration, until, actions })` (0.11) | A note in the notification stack (Notifications module): `kind` `"timed"` (goes after `duration`, default 8 s), `"sticky"` (until closed), `"until"` (until you dismiss it: `until` says what makes it go) or `"roll"` (0.12: a request, shown in combat; with `duration` and `remaining` it counts down by itself and stays until dismissed); `icon = { glyph = "bell" }` (a glyph from `Media/Textures/Glyphs`) or `{ texture }`, either with `tooltip = fn(owner)` (0.12: what hovering the icon shows, e.g. an item's GameTooltip); `tone` `"warning"`/`"danger"`; `bodyTooltip = { title, description }` (0.12: on hovering the body), `actions = { { label, variant = "primary"|"quiet"|"danger", onClick(card), count, pressed, disabled, tooltip } }` (0.12: `count` after the label, `pressed` in arcane, `tooltip` a `UI.ShowTooltip` table; 0.13: `icon`, a glyph left of the label; `macro`, a macro text or a function returning one: a secure button over the action runs it, for what only a secure click may do, out of combat only, `onClick` running after it). 0.13: `source = { tool, channel, text }` shows where a Group Finder note came from (badges and the post as written). Returns the id; the same `id` again replaces it. Nothing while the module is off |
| `SuuUI.DismissNotification(id)` (0.11) | Takes a note away |
| `SuuUI.UI.Notification(parent)` / `SuuUI.UI.NotificationStack(parent, { max })` (0.11) | The card (`n:SetData(d)` with the fields above plus `item = { icon, label, quality }`, `confirmText`, `duration`/`remaining`; `n:SetRemaining(s)`; 0.13: `host = { roles = n }` keeps a row for hosted role buttons in `n.rolesRow`, `warning` an amber line under it) and the stack (`s:SetItems(list, inCombat)`: requests, conditions, notes, timed; in combat only the first two; at most `max`, the rest behind "+N more") |
| `SuuUI.UI.Inventory(parent, { title, columns, name, sortTip, characters })` (0.11; `characters` 0.12) | The bags (and bank) panel: search field (`inv.search`), sort button (`inv.sort`), a grid (`inv.grid`; `inv:LayoutSlots(buttons[, sections])` places your slot buttons row by row, `slot` square, space-2 apart; 0.17: `sections = { { at, label, meta, note } }` starts a new row under a hairline head ("Reagents · 36 · 12 free") before the button at `at`, `#buttons + 1` after them all, a `note` alone a quiet line), the foot (`inv:SetNote(text)`, `inv:SetMoney(copper)`: no money shows until you set it, `nil` hides it), `inv:SetMeta("18 free of 80")`, `inv.onClose`, `inv:SetColumns(n)`, `inv:SetAction({ text, onClick, tooltip })` (a quiet button at the start of the foot; `nil` removes it). With `characters` (0.12): a character picker in the header (`inv.who`, a bare Select), Bags/Bank (`inv.view`) and All characters (`inv.all`), `inv:SetBanner(text)` (an eye and a caption over the grid), `inv:SetResults(list)` (found items in place of the grid: `{ icon, quality, label, count, places }`; `nil` brings the grid back; returns how many didn't fit) |
| `SuuUI.UI.SkinItemSlot(button)` / `SuuUI.UI.ItemSlot(parent, size)` / `SuuUI.UI.Money(parent)` (0.11) | SuuUI's item slot look on any button (Blizzard's bag slot template included: its own art hidden): `skin:SetItem({ icon, count, quality, dim, locked })` or `nil` for an empty slot; a plain slot (`b.skin`); money as "1,204g 37s 9c" (`m:SetCopper(n)`; 0.15: zero coins at the end left out, "38g 50s", "0c" for none) |
| `SuuUI.ToggleBags()` (0.12) | Opens or closes the bags without Blizzard's bag functions (called from addon code, they taint Esc in combat): SuuUI's bags while the Bags module is on, else Blizzard's (`ToggleAllBags`) |
| `SuuUI.UI.LootWindow(parent, { name })` (0.12) | The loot window: "Loot" with the source as its meta, one row per thing (`lw:SetItems({ { index, icon, count, quality, label, copper, locked } })`: an item slot and the name in its quality colour, or money), `lw:SetSource(text)`, `lw.onClick(index, button)`, `lw.onEnter(index, row)` / `lw.onLeave`, `lw.onClose`; `lw:FirstSlotOffset()` (the first slot's centre from the top left, to open it under the cursor) |
| `SuuUI.UI.SkinTooltip(tooltip)` (0.12) | SuuUI's look on one of Blizzard's tooltips (a `GameTooltip`): surface-glass, a gilt-line edge, the gilt diamond at the top left; its NineSlice hidden after every `SharedTooltip_SetBackdropStyle`. Lines and set functions stay Blizzard's |
| `SuuUI.UI.IsTooltipSkinned(tooltip)` (0.17) | Whether `SkinTooltip` already gave this tooltip SuuUI's look |
| `SuuUI.UI.SpellTooltip(owner, spellID, extra[, anchor])` (0.12) | The game's spell tooltip (GameTooltip, `SetSpellByID`) on `owner` (`anchor` default `"ANCHOR_RIGHT"`) with `extra` (a line of text, or a list of lines) as its last lines. They stay when the game redraws the tooltip as the spell's data arrives (the first hover of a spell not loaded yet) |
| `SuuUI.UI.SkinWindow(frame, { title, icon, binding, close, hide, topInset, headExtra, under })` (0.12; `headExtra` 0.15) | One of Blizzard's windows in the WindowFrame look, in place: a header grows above it (gilt diamond, icon glyph and title in `header` gilt-text, the binding's key chip, Blizzard's close button with SuuUI's cross), surface-glass in a gilt-line edge behind, `hide` (frames or regions) at alpha 0; `topInset` is the window's own strip above its content; `headExtra` (px) makes the header's second row taller, the header growing down into the window (count it in `topInset`). `under`: an anchor name (`"microMenu"`): the window joins the row under that anchor, the row's windows side by side from its left edge, their headers `space-5` below it and `space-5` apart, in the order they opened; when Blizzard places the window again it goes back to the row. The window moves to the HIGH strata; skinning it again returns the same chrome. A protected window's tabs and place change only out of combat. `chrome:SetTabs({ { button, label, short, selected = fn, selectedTexture, disabled = fn, reason } })` turns the window's tab buttons into text tabs along the header's bottom (0.17: while `disabled()` is true a tab is ink-faint at opacity-disabled and a cover takes its click, its tooltip saying `reason`) (their clicks stay Blizzard's; short labels when the window is too narrow; `selectedTexture` is the texture that shows on the selected tab, when it isn't the button's `SelectedTexture` or `LeftActive`), `chrome:UpdateTabs()` after a switch, `chrome:LayoutTabs()` lays the tabs out again, `chrome:SetTitle(text)`, `chrome:SetBinding(binding)` (the key chip for another binding), `chrome.rowMid` (0.15: the line, up from the header's bottom, that controls in the header's second row sit centred on: anchor them by `LEFT`/`RIGHT` to `chrome.head`'s `BOTTOMLEFT`/`BOTTOMRIGHT` with it as y) |
| `SuuUI.UI.WINDOW_HEAD_H` (0.17) | The height of the header `SkinWindow` grows above a window, in px |
| `SuuUI.UI.IsCoveredByWindow(frame)` (0.12) | Whether an open window in SuuUI's look (a `SkinWindow`, its header included) covers part of `frame`; notes under one hide. Edges that are secret (in combat) count as not covered |
| `SuuUI.UI.CenterWindow(frame, on)` (0.12) | A window skinned with `under` in the middle of the screen (`on`) or back in its row (`off`); SuuUI's Talents tab centres the spells window while it shows. The middle holds one window: opening a centred one closes another centred one, unless that one is protected (then the two sit side by side, centred together). A protected window moves only out of combat. Does nothing for a window without `under` |
| `SuuUI.UI.Reskin(frame)` (0.12) | Blizzard's parts in `frame` (up to six levels down) in SuuUI's look, in place, by the helpers below: list rows and their collapsible category bars (the name in `header` gilt-text over a gilt-faint rule), status and fill bars, check buttons, edit boxes, dropdowns, panel buttons, collapse buttons, scrollbars and scroll boxes. Highlight textures become surface-raised, selected ones arcane-soft; Blizzard's text colours become SuuUI's (yellow and white ink, grey ink-muted, green fel, red ember-text) and its fonts the text styles, with big titles in `header` gilt-text. Clicks and data stay Blizzard's, and a pass only changes looks, so call it again whenever Blizzard redraws. Skipped: forbidden frames, frames marked `suuOwn = true` (SuuUI's own pages inside a Blizzard window), check buttons marked `suuNoCheck`, buttons marked `suuNoButton`, FontStrings marked `suuSkip` |
| `SuuUI.UI.ReskinScrollBox(box)` (0.12) | Every row of a Blizzard ScrollBox restyled by the same pass, now and after each update (its `Update`, a data range change, showing); its shadows hidden |
| `SuuUI.UI.ReskinScrollBar(bar)` (0.12) | Blizzard's minimal scrollbar: no track art or step arrows, a 2px gilt-line thumb (gilt and 4px wide under the mouse) |
| `SuuUI.UI.ReskinStatusBar(bar)` (0.12) | A flat fill on a track in a gilt-hairline edge, as tall as Blizzard's fill. Its colour comes from the fill's atlas (`stat-bar-red`, `-orange`, `-yellow`, `-green`: the standing colours; `-purple` arcane, `-gold` gilt-text; otherwise progress-fill), and it goes flat again whenever Blizzard sets the fill. Its text centred in `numeric` ink |
| `SuuUI.UI.ReskinFillBar(bar)` (0.12) | A bar Blizzard draws itself (a frame with a `Fill` texture it sizes and tints, like the reputation's standing bars): the fill flat in Blizzard's tint, a track in a gilt-hairline edge, the text centred in `numeric` ink. Nothing without `bar.Fill` |
| `SuuUI.UI.ReskinCheckButton(button)` (0.12) | A 16px surface-sunk box in a gilt-line edge; checked, an arcane check and edge. It follows `SetChecked` and clicks |
| `SuuUI.UI.ReskinButton(button)` (0.12) | Blizzard's panel button (Left/Middle/Right art, or a button atlas) as SuuUI's quiet button: surface-raised in a gilt-line edge (gilt on hover), its label in `label` ink, dimmed while disabled |
| `SuuUI.UI.ReskinEditBox(editBox)` (0.12) | An input box: Blizzard's art away, surface-sunk in a gilt-line edge (arcane while typing), `body` ink |
| `SuuUI.UI.ReskinDropdown(dropdown[, opts])` (0.12) | Blizzard's dropdown (WowStyle): surface-sunk in a gilt-line edge (gilt on hover), its text in `label` ink, SuuUI's chevron on the right. 0.13: the menu it opens too, in the context menu's look (`ReskinMenu`). 0.14: `opts.glyph` (a glyph's name, "filter") makes it an icon-only dropdown: the glyph in muted ink, its gilt-line edge on hover |
| `SuuUI.UI.ReskinIconButton(button)` (0.12) | An icon button (a grid of icons to pick from, the icon picked): Blizzard's art away, the icon cropped on a surface-sunk well in a gilt-hairline edge, gilt on hover, arcane while the button's `SelectedTexture` shows |
| `SuuUI.UI.ReskinCollapseButton(button)` (0.12) | A small collapse/expand button: SuuUI's minus or plus in gilt-text, following the state Blizzard sets |
| `SuuUI.UI.Spellbook(parent, { rows })` (0.12) | The Spellbook page: schools down the left (`book:SetSchools({ { label, icon, trainable, active } })`, `book.onSchool(i)`), the head (`book:SetHead(title, toTrain)`, the Unlearned spells / All ranks switches: `book:SetSwitches(a, b)`, `book.onSwitch(key, on)`), two columns of spells (`book:SetSpells({ { label, rank, sub, icon, status = "learned"\|"passive"\|"trainable"\|"future" } })`), the pager (`book:SetPage(page, pages)`, `book.onPage(delta)`). `book.cells[i].button` is a SecureActionButton: set what it casts out of combat; `book.onEnter`, `onLeave`, `onDragStart(i, cell)` |
| `SuuUI.ToggleTalents()` / `SuuUI.TalentsShown()` (0.12) | Opens or closes SuuUI's Talents window (the Talents module): `true`, or `false` while that module is off; whether the window is open (`false` while the module is off) |
| `SuuUI.ShowTalentsOf(unit)` (0.17) | SuuUI's Talents window with an inspected player's talents, read only (call it after `INSPECT_READY` for that unit), its title "Talents · Name"; the talents key or closing the window goes back to your own. `false` while the Talents module is off |
| `SuuUI.UI.TalentTree(parent)` (0.12) | The Talents page: the class's trees side by side, each a panel with its name and points and its talents on a 4-column grid with prerequisite arrows; above, the spec's name and the points per tree; below, the points to spend, what is planned, Undo and Apply. `tt:SetData({ name, available, pending, editable, hint, rows, trees = { { name, points, more, nodes, links } } })` (`rows` default 7; `more` a line under the tree; `hint` the status line while nothing is planned; `editable = false` keeps Apply off), a node `{ row, col, rank, pending, max, icon, locked, canSpend }` (`row` and `col` count from 0), a link `{ from = node, to = node, met }`. `tt:SetSpecs({ { label, name, active, locked } }, viewing)`: a row to switch specs when there is more than one (`locked` ones can't be picked; `viewing` an index), with an Active badge or an Activate button. 0.17: `head = { name, class, line }` shows someone else's talents: their class diamond, the name in its class colour, the line and the points per tree by name, with a "Read only" badge; `readOnly = true` drops the points to spend, Undo and Apply; `back = "label"` puts a button at the foot's right that calls `tt.onBack()`. `tt.noSummary = true` drops the summary line, `tt.fillPanels = true` stretches the panels down to the foot. `tt.onClick(node)`, `onRemove(node)` (a right click), `onEnter(button, node)`, `onLeave()`, `onApply()`, `onUndo()`, `onSpec(i)`, `onActivate()` |
| `SuuUI.UI.TALENT_TREE_W` (0.12) | The width `TalentTree` needs for three trees and their gaps (688) |
| `SuuUI.UI.TraitTooltip(owner, configID, nodeID, { name, treeName, conditions, canSpend, pending, needs, blocked })` (0.12) | A talent's tooltip on GameTooltip, as the game's own talent buttons build it: `name` as the title, "Rank 2/5", the talent's text at this rank and the next, "Click to learn" with `canSpend` (else, with `pending` planned ranks, how to take one back), then what it still needs: the unmet one of `conditions` that asks the most points (`treeName` for the game's "spend N more points in the X tree" line), and in red `needs` (a list of lines) and `blocked` (why nothing can change now). Nothing when the game has no info for the node |
| `SuuUI.UI.LegacyPoints(parent[, { account = false }])` (0.12) | Forever's Legacy points: `p:SetPoints({ earned, total, spent, cap, pending, character })` shows "Legacy points · account" over "16 of 81 earned" and "Spent on Veyra" over "9 of 16", with planned points (`pending`) as "· 2 not applied" in arcane. `account = false` shows the character's points only |
| `SuuUI.UI.LegacyChallenges(parent)` (0.12) | The Legacy challenges: `c:SetCategories({ { name, done, total, items, groups = { { name, done, items } } } })` draws a card per category, three to a row: its done/total, a bar and its first five `items` (`{ name, done, progress ("45/150"), points, onEnter(owner), onLeave() }`). A card opens the category's full list (one panel per group, scrolling); there an item may also carry `id`, `count = { have, need }`, `stepsN`, `stepsDone` and `steps` (a function returning its steps, `{ id, text, done, count }`, or with `steps` of their own), and a click opens its steps. `c:Open(i)`, `c:Close()` (back to the cards). Setting the categories again keeps an open list where it was scrolled |
| `SuuUI.UI.LEGACY_CARD_H` (0.12) | The height of one `LegacyChallenges` card |
| `SuuUI.UI.LegacyTrack(parent)` (0.12) | The reward track, a strip for the Legacy window's foot: `t:SetTrack({ earned, total, max, next, stops = { { at, icon, quality, collected, onEnter(owner), onLeave() } } })`. The account's points on the left, then a bar filled to `earned` of `max` with each reward at its `at`: its icon dim until reached, a check once `collected`, the level under it; `next` as a caption under the bar. Names go in the tooltip your `onEnter` shows |
| `SuuUI.UI.LEGACY_TRACK_H` (0.12) | The height of the `LegacyTrack` strip |
| `SuuUI.TrainerSpells()` (0.12) | What your class trainer teaches: `{ { name, level, cost, school, icon, text } }` (cost in copper; Data/Trainer, from the class probes; no ranks) |
| `SuuUI.TrainerSpellIDs()` | 0.12: every spell ID this client has for each trainer spell name, `{ [name] = { id, ... } }` (players' ranks and others alike; pick a rank with `C_Spell.GetSpellLevelLearned`) |
| `SuuUI.UI.MicroMenu(parent, { name })` | The micro menu panel: `m:SetItems({ { key, glyph, label, click = "<Blizzard micro button>" } or { …, onClick = fn } })` (out of combat: `click` items are secure buttons clicking the Blizzard button; glyphs from `Media/Textures/Glyphs`), `m:SetAlert(key, text)` (the arcane diamond, `nil` clears); 0.17: `m:SetCount(key, text[, colorToken[, fillToken]])` (a count in a small pill on the button's bottom right corner: its text colour, `ink` by default, and the pill's fill, `surface` by default; `nil` clears; the Bags button shows your free slots) |

## Professions, menus and social (0.13)

| | |
|---|---|
| `SuuUI.FullName(unit)` | A unit's whole name. Forever's characters have a surname: its `UnitName` returns first name and surname where other clients give name and realm; this gives "Suther Stargazer" (with "-Realm" for another realm), the form whispers, invites, the roster and chat use |
| `SuuUI.UI.ContextMenu(owner, { title, items = { { label, onClick, disabled } \| { separator = true } } })` | SuuUI's right-click menu in the tooltip's look, at the cursor; a click outside, Esc or a choice closes it. `UI.ContextMenuFrom(owner, fn(owner, root))` builds the same from MenuUtil's generator shape (`root:CreateTitle`, `CreateButton`, `CreateDivider`); `UI.CloseContextMenu()` |
| `SuuUI.UI.FilterMenu(parent, { groups, defaults, value, placeholder, width, onChange })` | A grouped filter field and panel: groups of `kind` `"one"` (a Segmented row), `"many"` (chips with a colour diamond, none = any) or `"toggles"` (checkboxes); "Filters · N" counts choices off the defaults; Reset. `menu:SetValue(v)`, `GetValue()`, `Count()`, `Close()`. 0.14: a group's `column = true` starts a new column (each at least 180px, the foot spans them); `style = "button"` makes the field a quiet button (the filter glyph, the placeholder, an ink diamond while the filters differ from their defaults); `height`; `done = true` adds Done to the foot |
| `SuuUI.UI.MapPin(parent)` (0.14) | One mark on the world map: a disc on surface with an edge (26 px with a 17 px glyph, small 21 px with 14 px), a glyph or a character in it. `pin:SetData({ glyph = name or char = "!", color, edge, edgeWidth (px, 1; 0.15), small (21px, else 26px), ring (a token: a second ring), count (a merged pin's, 2 and up), spin (true: the glyph turns once in 6 s, the disc stays still) })`, `pin:PinSize()`, `pin:SetHighlight(true | "dim" | nil)` (an ink ring: one of the hovered quest's pins; faded back; as it was), `pin:SetBaseAlpha(a)` (0.15: its usual opacity). A Button; its owner sets clicks and hover; 0.17: `outline = true` (a 1 px surface line outside the edge), `arcs = { token, … }` (a split edge, an arc per item, 2-4, clockwise from the top), `bar = token` (a 16 x 4 bar under the pin) |
| `SuuUI.UI.Confirm({ …, typeToConfirm, input })` | `typeToConfirm = "UNLEARN"`: the confirm button works once that word is typed; `input = { label, placeholder, value }`: a text to enter, given to `onConfirm(text)` |
| `SuuUI.UI.Professions(parent, { edgeInset })` | The Professions window's body (overview cards, a profession's recipe list and the chosen recipe); see UI/Professions.lua's header for its data |
| `SuuUI.UI.PROFESSIONS_W`, `SuuUI.UI.PROFESSIONS_H` | The Professions window's size: 720 × 600 |
| `SuuUI.UI.PROFESSION_FILTER_DEFAULTS` | The recipe list's filters at rest, `{ show = "learned", difficulty = {}, quality = {}, other = {} }`: the `defaults` of the Professions body's filter menu (what its Reset goes back to), in the shape `onFilters` gets |
| `SuuUI.QuestStarts()` / `SuuUI.MapPlaces()` (0.14) | The world map's generated data (from QuestieDB, `tools/update_quest_starts.sh`): where Forever's quests are picked up (who gives them; for a quest started by an item, where the mobs that drop it live) and the dungeon, raid and battleground entrances (Data/QuestStarts.lua); the town services by NPC, mailboxes, rares and treasure chests (Data/MapPlaces.lua). Layouts in the files' headers; 0.17: `QuestStarts().objectives[questID]`, what a quest asks of you (its objectives text, with the game's `$N`, `$C`, `$R` and `$Gmale:female;`); `QuestStarts().tags[questID]`, a quest's tag where the game's is wrong (`1` elite, `41` PvP, `62` raid, `81` dungeon; Questie's corrections); `QuestStarts().group[questID]`, `"elite"`, `"dungeon"` or `"raid"`: a guess for a quest the game hasn't told about yet (Classic's quest types from cMaNGOS, and quests set in a dungeon or raid) |
| `SuuUI.MapOverlays()` (0.14) | Every area overlay of Forever's maps by map art, for drawing areas you haven't explored (Data/MapOverlays.lua, from the client tables WorldMapOverlay and WorldMapOverlayTile: `tools/update_map_overlays.sh`): `{ [uiMapArtID] = { { textureWidth, textureHeight, offsetX, offsetY, fileDataID, ... } } }` |
| `SuuUI.InstanceLevels()` (0.14) | The recommended levels of Forever's dungeons, raids and battlegrounds, by the names of their entrances in `SuuUI.QuestStarts().entrances` (Data/InstanceLevels.lua, the group finder's ranges from the client table GroupFinderActivity: `tools/update_instance_levels.sh`): `{ dungeon = { [name] = { min, max, { wing, min, max }, ... } }, raid = { … }, battleground = { … } }`. `min`, `max` span the wings (Scarlet Monastery's, Dire Maul's …) and a battleground's brackets. Season of Discovery's activities, still in the client, are left out |
| `SuuUI.GetModule("marks")` (0.15) | Your own map marks (module `marks`, saved per character): `:Marks()` (list of `{ id, map, x, y, name, symbol, from, at }`; `from` the sharer's name for a shared one), `:Get(id)`, `:Add(map, x, y, { name, symbol })`, `:Update(id, fields)`, `:Remove(id)`, `:PlaceOn(mark, mapID)` (its x, y on another map: a zone's mark on its continent), `:Follow(id or nil)` (the game's waypoint and navigation arrow; one at a time), `:Post(id)` (from a click: a chat line with the game's map pin link to party, raid or instance chat, and the mark to group members with SuuUI, who keep it as a shared mark), `:OpenCard(id[, pin])`, `.SYMBOLS` (star, circle, diamond, triangle, moon, square, cross, skull; colours `mark-<symbol>`, glyphs `mark<Symbol>`). Emits `SUUUI_MARKS_CHANGED`. Ctrl+click on the world map makes one |
| `SuuUI.RecipeSources(recipeID)` | Where a profession recipe is learned (Data/RecipeSources.lua): `{ { t = "t", s, n } \| { t = "a" } \| { t = "i", i, s, v, d, dn, o, q, c } }` (trainer with the skill it asks; automatic; a recipe item with its skill, vendors, drops, chests, quests, containers), or nil |
| `SuuUI.CollectionSources()` (0.17) | Where Forever's mounts, toys and appearance items come from (Data/CollectionSources.lua, from the client tables and QuestieDB: `tools/gen_collection_sources.py`): `{ npc = { [npcID] = "Name|Zone|Level|Faction" }, obj = { [objectID] = "Name|Zone" }, mount = { [mountID] = source }, toy = { [itemID] = source }, toys = { itemID, ... }, item = { [itemID] = source } }`; a source is `{ i, x, v, d, dn, o, q, c, p }` (the mount's item, the client's own text, sold by, dropped by and of how many, found in, quests, inside, crafted by profession) |
| `SuuUI.ToggleCollections([tab])` / `SuuUI.CollectionsShown()` (0.17) | SuuUI's Collections window (the collections module): open or close it, on a tab (`"mounts"`, `"toys"`, `"wardrobe"`); whether it is open. `ToggleCollections` returns false when that module is off |
| `SuuUI.OpenRecipe(recipeID)` / `SuuUI.ShownRecipe()` / `SuuUI.ExpectRecipe(recipeID)` / `SuuUI.ProfessionOpener(skillLine)` | A recipe in SuuUI's Professions window (its profession opened, the recipe chosen); the recipe it shows; the recipe to choose once its window opens; the spell that opens a profession's window. Opening a profession from addon code is protected: cast `ProfessionOpener`'s spell from a secure button |
| `SuuUI.UI.ObjectiveTracker`: `t:SetRecipes(list, collapsed, meta)`, `t:SetQuestsCollapsed(on)`, `t.onRecipeClick`, `t.onSectionToggle`, `t.onRowEnter` | Tracked recipes as a section after the quests, in the same scrolling list; entries take `color`, `icon` and `count` |
| `SuuUI.Notify({ presence = { online, source, people, invite } })` | A friend or guild member came online or went offline (the Notification card's presence mode) |
| `SuuUI.UI.Contacts(parent)` | The Social window's Contacts page: `c:SetData({ view, status, online, total, friends, ignored, selected })`; `onView`, `onStatus`, `onSelect`, `onWhisper`, `onInvite`, `onAdd`, `onIgnore`, `onUnignore`, `onMenu` |
| `SuuUI.UI.RaidGroups(parent)` | The Social window's Raid page: "17 of 40", Ready check, Role check and Raid Info, then eight groups of five. `r:SetData({ inRaid, inParty, canLead, reason, size, members = { { index, name, class, role, group, leader, assistant, online, dead, you, level, className, zone } } })` (`size` default 40; without `canLead` the checks are disabled with `reason`; not in a raid, "Convert to raid" in a party). A member's tooltip shows its level, class, zone and whether it's offline. The leader and assistants (`canLead`) drag members out of combat: onto an empty slot `r.onMove(index, group)`, onto another member `r.onSwap(index, otherIndex)`. `r.onReadyCheck()`, `onRoleCheck()`, `onRaidInfo()`, `onConvert()`, `onMember(member, button, owner)` (a click) |
| `SuuUI.UI.PeopleList(parent)` | A list of people (the Social window's Recent allies and Requests): `l:SetData({ title, empty, rows = { { key, name, color, glyph, online, detail, note, pinned, actions = { { label, variant, onClick(row), disabled } } } } })`. A heading "title · count", then a row each: the class diamond (or, with `glyph`, the people glyph), the name in `color` (faded while `online` is false), `detail` with the note in quotes, a pin with `pinned`, its `actions` as buttons at the right. `empty` shows when there are no rows. `l.onMenu(row, owner)` on a right click |
| `SuuUI.UI.GuildRoster(parent)` | The Guild window's Roster page: `r:SetData({ online, total, showOffline, sort, members, selected, actions })`, a member `{ key, name, class, className, level, zone, rank, rankIndex, note, officerNote, online, away, busy, lastOnline }`; `actions = { whisper, invite, promote, demote, remove, guildInvite }`, each `{ enabled, why }` (a disabled button gives `why`). Columns Name, Level, Class, Zone, Rank, Note; `sort` is a column's key (default `"rank"`). `r.onSearch(text)`, `onShowOffline(on)`, `onSort(column)`, `onSelect(key)`, `onAction(name, member)` (`"whisper"`, `"invite"`, `"promote"`, `"demote"`, `"remove"`, `"guildInvite"`; a double click whispers an online member), `onMenu(member, owner)` (a right click), `onRowEnter(row, member)`, `onRowLeave(row)` |
| `SuuUI.UI.GuildInfo(parent)` | The Guild window's Info page: `i:SetData({ info, canEditInfo, ranks = { { name, count } } })`: the guild information down the left (an Edit button with `canEditInfo`: `i.onEdit("info")`), the ranks and how many hold each at the right |
| `SuuUI.UI.GuildLog(parent)` | The Guild window's Log page: `l:SetData({ lines = { { text, when } } })`, a row per line in the order given, `when` at the right; with none, "Nothing has happened in the guild yet." |
| `SuuUI.UI.GuildControl(host, GuildControlUI)` | The Guild window's Settings tab: the game's guild control window (load `Blizzard_GuildControlUI` first) laid out in `host` in SuuUI's look, its controls still the game's own so your clicks save. `c:Layout()` again after the game redraws a page (it follows the game's own updates itself) |
| `SuuUI.UI.GuildMotdBanner(parent)` | The guild's message of the day pinned to the top of a box: `b:SetData({ text, canEdit })` (no text: hidden), `b:Height()` (0 when hidden), `b.onEdit`, `b.edit` |
| `SuuUI.UI.ReskinDialog(frame)` / `SuuUI.UI.ReskinMenu(menu)` / `SuuUI.UI.ReskinPopup(dialog)` | One of Blizzard's small dialogs (the guild's text editor) as a SuuUI panel, its clicks still Blizzard's; an open Blizzard menu in the context menu's look, undone when it closes (the game reuses its menu frames); one of the game's shared popups (StaticPopup1-4) likewise, undone when it hides. `UI.ReskinDropdown` now restyles the menu its dropdown opens |

## Group finder: ForeverLFG (0.13)

`SuuUI.LFG` is a library with no UI: the game's group finder (the tool) and the public chat channels as one list of groups and players looking for groups. Its design, and what the game allows, is in `Docs/ForeverLFG.md`. It does nothing until `Start()` (SuuUI's Group Finder module calls it).

| | |
|---|---|
| `SuuUI.LFG.Start()` / `Stop()` | Starts reading the tool and chat, joins LookingForGroup (and keeps it off the chat windows); stops |
| `SuuUI.LFG.Configure({ channels, joinLookingForGroup, hideLookingForGroup, chatExpiry, staleAfter, expiringSoon, minConfidence, extraLanguages })` | Its settings (`SuuUI.LFG.config` holds the defaults) |
| `SuuUI.LFG.On(event, fn)` / `Off(event, fn)` | Events: `EntryAdded(entry)`, `EntryUpdated(entry)`, `EntryRefreshed(entry)` (posted again, unchanged), `EntryRemoved(entry, reason)`, `Match(entry, reasons)`, `Contacted(entry, "full" \| "gone" \| "reposted")`, `ToolSearched(category, count)`, `ToolSearchFailed(category)`, `ToolStale(category, age)`, `ListingChanged(listing)`, `ListingExpiring(secondsLeft)`, `Delisted()` |
| `SuuUI.LFG.Entries(filter)` / `Entry(key)` | The merged list (newest first); `filter = { intent, kinds, activities, sources, minConfidence, search, notYou }`. An entry: `key` (the leader's whole name), `intent` ("group" \| "player"), `activities`, `quests`, `roles = { needed, offered }`, `classes`, `need`, `members`, `level`, `leader`, `text`, `confidence`, `sources = { tool, chat }` |
| `SuuUI.LFG.Refresh(category)` | Searches the tool. Only from a click or key press (the game blocks it otherwise); 2 Dungeons, 116 Quests & Zones, 120 Custom |
| `SuuUI.LFG.Listing()` / `Delist()` | Your listing (activities, roles, comment, play style, time left); delisting from a click. Making or changing a listing is blocked for addon code: use the game's own listing panel |
| `SuuUI.LFG.Whisper(entry)` / `CanInvite(entry)` / `Invite(entry)` | An empty whisper to the leader; inviting a single player looking (the tool's rule; there's no sign-up on Forever) |
| `SuuUI.LFG.Interest()` / `Watch(key, on)` / `Watches()` / `MatchReasons(entry)` | What you're after (listing, roles, quests, level, zone, watches); an activity to hear about; why an entry concerns you: "role", "activity", "player", "quest", "zone", "boss", "friend" |
| `SuuUI.LFG.ContactedAt(key)` / `Social(name)` (0.13) | When you whispered that leader (`SuuUI.LFG.Now()` time), or nil; "friend", "guild" or nil for a player's name |
| `SuuUI.LFG.Catalogue` | `Get(key)`, `All(kind)`, `Expand(key)`, `ForTool(activityID)`: the activities ("dungeon:rfk", "zone:westfall", "raid:mc", "boss:azuregos", "tool:<id>") |
| `SuuUI.LFG.Parser.Parse(text, { languages })` / `SuuUI.LFG.Lang.Register(code, def)` / `SuuUI.LFG.Languages()` | The chat parser on its own; a language module (see `Lang/enUS.lua`); the languages in use |
| `SuuUI.LFG.IsHiddenChannel(name)` | Channels it reads but keeps off the chat windows (LookingForGroup) |
| `SuuUI.UI.SkinGroupFinderListing(LFGListingFrame)` (0.13) | The game's List yourself panel in SuuUI's look, in place: round role toggles, New player friendly, the categories as cards, Playstyle (amber until chosen), the activity tree in a sunk box, the details with a count, Voice Chat, Back and List Self (primary). Its clicks and data stay the game's. Once per session; returns the skin |
| `SuuUI.UI.SettingsMatrix(parent, { width, columns, rows, onChange })` (0.13) | Settings repeated per row as one grid (a sunk box, a 28px header of column names, 36px rows): `columns = { { key, label, width, kind = "check" or "select", options, title, master } }`, `rows = { { key, label, description } }`; `m:SetValue({ [rowKey] = { [colKey] = value } })` (no value: "—"), `m:GetValue()`, `onChange(value)`. The `master` column turns its row off: the name greys and the other cells are disabled, keeping their values. For a settings row: `control = "custom"`, `build = function(parent, onChange) return SuuUI.UI.SettingsMatrix(parent, { … onChange = onChange }) end` |
| `SuuUI.UI.GroupFinderWho(parent)` (0.13) | The Group Finder's Who page: `w:SetData({ state = "idle" or "results" or "none", query, total, capped, results = { { name, level, race, class (file), className, guild, zone } } })`; `onSearch(text)`, `onFilter(button)`, `onAddFriend(row)`, `onWhisper(row)`, `onInvite(row)`, `onMenu(row)` (right-click) |
| `SuuUI.UI.GroupFinderListed(parent)` (0.13) | The Group Finder's My listing page: `p:SetData({ listing = { listedFor, left, category, activities, roles, playstyle, comment, voice }, ad = { text, channel, channels, lastPost, max } })`; `onDelist`, `onUpdate`, `onChannel(value)`, `onText(text)`, `onRewrite`, `onPost(channel, text)` |
| `SuuUI.UI.GroupFinderBrowse(parent)` | The Group Finder's Browse page: `b:SetData({ groups, players, collapsed, tool = { age, stale, searching, loading }, category, categories, activities, activityOptions, search, fits, show })` (see UI/GroupFinder.lua for a row); `onRefresh`, `onFilter(changes)`, `onWhisper(row)`, `onInvite(row)`, `onToggle(section)`, `onClear()` (the empty state's Clear filters) |


## The welcome, role presets and colour vision (0.17)

The first-run welcome (the Welcome module) shows once per account, at the first login with SuuUI: your role layout, colour vision and where things are. Settings › General › Appearance › Welcome and `/suu welcome` open it again.

| | |
|---|---|
| `SuuUI.ShowWelcome()` (0.17) | Opens the first-run welcome. `false` when the Welcome module is off |
| `SuuUI.RolePresetName(role)` (0.17) | A role's preset profile name: `"TANK"` → `"SuuTank"`, `"HEALER"` → `"SuuHeal"`, `"DAMAGER"` → `"SuuDps"`; `nil` for anything else |
| `SuuUI.ApplyRolePreset(role[, switch])` (0.17) | Creates (or resets the layout of) the role's preset profile, copied from the profile you use, and puts it in its role's place under Profiles › By role, as Settings › Profiles › Role presets does. With `switch`, this character uses it from now on. Out of combat. Returns `true`, or `false` and why not |
| `SuuUI.ColorVisionModes()` (0.17) | The colour vision presets this SuuUI has, in order: `{ { id = "normal" \| "redgreen" \| "blueyellow", label, hint } }` |
| `SuuUI.ColorVision()` (0.17) | The colour vision chosen for the account, and the one in effect this session: they differ until a reload |
| `SuuUI.SetColorVision(mode)` (0.17) | Chooses the account's colour vision (every character); it takes effect after a reload, which addon code can't start on Forever (a secure `/reload` macro button can). Returns `true`, or `false` and why not |
| `SuuUI.ColorVisionColor(mode, token)` (0.17) | `r, g, b, a`: a colour token as a preset draws it, for previews of a preset that isn't in effect (`"normal"`: the design's own colour, whatever this session applied). An unknown token is an error |
| `SuuUI.AccountData(namespace)` (0.17) | Your module's own table for the whole account (not per character or profile), saved with SuuUI and made on first use: a flag shown once per account. Never in a profile, an export or a reset. From `OnEnable` on; use your module's id as the namespace |
