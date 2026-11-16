# Writing a SuuUI plugin

A SuuUI plugin is an ordinary addon that adds a **module** to SuuUI. SuuUI's own features are modules written against the same public API (API 0.47: their files import nothing of SuuUI's but its API, and a check holds them to it), so a plugin can do anything they do: build its own frames from SuuUI's components, add to SuuUI's frames, change how they draw, add to its menus, stand in for a whole module, or bring a theme. The one thing a plugin writes differently is the module itself: SuuUI's own are wowlua classes, which another addon can't extend, so a plugin hands SuuUI a definition table instead (section 2; the class style and the differences are in section 2b). This guide goes from an empty folder to all of that. [API.md](API.md) is the full reference.

Two examples ship with SuuUI:
- `Examples/SuuUI_HelloPlugin` covers a module, a setting, a chat command, events and a movable frame.
- `Examples/SuuUI_LevelBadge` adds a badge to every one of SuuUI's unit frames, with its settings on SuuUI's own Unit frames page.

Both are written in [wowlua](https://github.com/DomenikIrrgang/wowlua), like SuuUI itself: run `wowlua install` in either folder to build it into `Interface/AddOns` (or `wowlua build` and copy `dist/dev/<Name>` there). A plugin doesn't have to use wowlua: the plain Lua addon below works as well.

**In wowlua, SuuUI is typed.** A wowlua plugin in SuuUI's workspace that lists `SuuUI` in `addon-dependencies` sees the `SuuUI` global with all its types: `SuuUI.RegisterModule` gives a module whose `M:Get(key)` has each default's type, `M:Each("unitframe", fn)` hands `fn` a `UnitFrame`, and a mistake in a call is an error when you build. You can import SuuUI's types, never its code (SuuUI's values come through the global). The types are exported from SuuUI's API (API 0.47; API.md › Types lists them):

```lua
import type UnitFrame, Text, InstanceInfo from "suuui/Core/API"
```

Keep what your plugin adds beside SuuUI's frames (a weak table by frame, as the LevelBadge example does) rather than in fields of their own: SuuUI's classes don't declare your fields, so wowlua can't type them.

## 1. The addon

A folder in `Interface/AddOns`, for example `MyPlugin/`, with a TOC and a Lua file:

```
## Interface: 16001
## AllowLoadGameType: camelot
## Title: My Plugin
## Version: 0.1.0
## Dependencies: SuuUI

MyPlugin.lua
```

`Dependencies: SuuUI` makes your files load after SuuUI's, so the global `SuuUI` is there. A new addon folder is only found when the game starts or you go back to character select. After that, `/reload` picks up changes to your files.

## 2. A module

```lua
local M = SuuUI.RegisterModule({
    id = "myplugin",                 -- lower case; also your settings' namespace
    name = "My Plugin",
    description = "One line for the module list.",
    api = "0.17",                    -- the oldest SuuUI API you need
    enabledByDefault = false,        -- off until the player turns it on
    defaults = { greeting = "Hi", position = { point = "CENTER", x = 0, y = 0 } },
})

function M:OnEnable()
    -- build, listen, register: everything here is undone when the module turns off
end

function M:OnDisable()
    -- hide what you built
end
```

- **Turning it on:** `/suu enable myplugin`, or its toggle under Settings › Modules (plugins are listed under Plugins).
- **When modules start:** at login, after every addon has loaded. A module registered after login (a plugin that loads on demand) starts on the next frame, once its file has run to the end, so callbacks assigned after `RegisterModule` as above are in place (API 0.47).
- **Register everything in `OnEnable`:** events (`M:OnGameEvent`, `M:OnUnitEvent`), messages (`M:On`), setting watchers (`M:Watch`), chat commands (`M:RegisterCommand`), timers (`M:After`, `M:Every`), hooks on the game's functions and frames (`M:SecureHook`, `M:HookScript`), game CVars you change (`M:SetCVar`), addon messages you take (`M:OnAddonMessage`) and everything in the sections below. SuuUI removes all of it when the module turns off: timers are cancelled (and one asked for while the module is off never starts, so its callback needs no `IsEnabled()` check), hooks go quiet (a hook can't be taken off; enabling again re-arms the same one), the player's CVar values come back. For a frame you give to `SuuUI.UI.SetVisibility` or publish with `SuuUI.PublishAnchor`, pass your module last (`SuuUI.UI.SetVisibility(frame, "combat", nil, self)`, `SuuUI.PublishAnchor("myAnchor", frame, self)`) and SuuUI lets go of it too.
- **`M:IsEnabled()`** is already true while `OnEnable` runs and already false while `OnDisable` runs (API 0.47), so a helper both call (`self:Refresh()`) can ask it to know which way things are going.
- **A popup of your own** (a menu, a box, a dialog) closes the way SuuUI's do with `SuuUI.UI.Dismissable(frame, { close = ..., outside = "catch" })` (API 0.47): Esc, a click outside, a dimmed screen with `shade = true`. It takes the keyboard only out of combat and lets every key through to the game when a fight starts; don't call `EnableKeyboard` or `SetPropagateKeyboardInput` on that frame yourself.
- **Errors stay contained.** An error in `OnEnable` turns your module off with one line in chat, and SuuUI keeps running. Errors in your events, hooks and callbacks are recorded under your module's name.
  - `/suu errors` lists them.
  - The game's own error display is off on this client by default; `/console scriptErrors 1` turns it on.
- **Your module's own fields** (`id`, `name`, `state`…) are SuuUI's and can't be set, and neither can its methods' names (`Get`, `Hook`, `On`, `Print`, `IsEnabled`…, API 0.47): a field of yours by one of those names would hide SuuUI's method from SuuUI and from other modules. Keep your own values under other names (one that differs only by case, `hook`, is yours). Setting one is an error that names the field.
- **Methods of your own** can come with the definition (API 0.47): every field of the table that isn't one of SuuUI's keys stays on the module, so `Refresh = function(self) … end` in it is `M:Refresh()`. Assigning them after the call (`function M:Refresh()`) works as well.

## 2b. A module as a class: how SuuUI's own are written

SuuUI's built-in modules are wowlua classes. Reading one helps when you look for how SuuUI does something:

```lua
import SuuUI, Module from "/Core/API"
import type SettingsSection, Position from "/Core/API"

local DEFAULTS = { greeting = "Hi", position = { point = "CENTER", x = 0, y = 0 } :: Position }

class Hello extends Module<typeof(DEFAULTS)>
    frame: Frame? = nil

    constructor()
        super({ id = "hello", name = "Hello", api = "0.47", defaults = DEFAULTS })
    end

    override function OnEnable()
        -- the same methods as a plugin's module: self:Get, self:RegisterMover, self:Watch…
    end
end

SuuUI.AddModule(Hello.new())
```

How it differs from section 2:
- **Where it can be written.** Only inside SuuUI's own package: wowlua extends a class only when it can import it as a value from the same addon. A plugin can import SuuUI's types (`import type`, which can't be extended) but not its code, and `class X extends SuuUI.Module` isn't a class name to wowlua. So a plugin uses `SuuUI.RegisterModule`.
- **The definition** goes to `super(…)` (the keys of `RegisterModule`'s table), and the callbacks are the class's `override function OnEnable()`, `OnDisable()`, `OnInitialize()`.
- **Fields and methods** are declared in the class, so wowlua types them (a plugin's own fields are loose: wowlua types its settings, not the rest).
- **The same everywhere else.** `SuuUI.AddModule` registers it with the same checks, it starts and stops the same way, and it has the same methods. The classes SuuUI's modules extend besides `Module` (`Panel`, `ItemSlot`, `UnitFrame`, `MapPin`, `ActionButton`) are `SuuUI.Classes`; a plugin can make their objects (`SuuUI.Classes.UnitFrame.new(…)`) but, for the same reason, not extend them.

## 3. Settings and a frame

```lua
function M:OnEnable()
    if not self.frame then
        local UI = SuuUI.UI
        self.frame = UI.Panel(SuuUI.Root, { title = "My Plugin", width = 220 })
        self.frame.text = UI.Text(self.frame.body, "body", "ink")
        self.frame.text:SetPoint("TOPLEFT")
    end
    self.frame.text:SetValue(self:Get("greeting"))
    self.frame:Show()
    self:RegisterMover(self.frame, { key = "position", label = "My Plugin" })   -- movable in /suu edit
    self:Watch("greeting", function(v) self.frame.text:SetValue(v) end)
    self:RegisterSettings({
        id = "myplugin", label = "My Plugin",
        groups = { { title = "Greeting", rows = {
            { key = "greeting", label = "Greeting", control = "text" },
        } } },
    })
end
```

- `SuuUI.Root` is the parent for anything on the screen. One unit there is one design pixel.
- SuuUI's components (`Panel`, `WindowFrame`, `Button`, `Icon`, `UnitFrame`, `AuraContainer`…) and the design tokens (`SuuUI.Tokens`) give a plugin SuuUI's look. See API.md › Components.
- Settings are saved per profile. `M:Get` returns a copy of a table; `M:Peek` reads a large table without copying it.
- Positions are saved per screen size within a profile (API 0.46): a 1080p and a 1440p setup each keep their own. Settings of yours that depend on the screen, such as a size, can join them with `layout = { "width" }` in `RegisterModule`. See API.md › Layouts per screen size.
- `merge = "<section id>"` on the settings section adds your groups to one of SuuUI's own pages instead of a page of your own. For example, `merge = "unitframes"` (the Level badge example does this).

## 4. Adding to SuuUI's own frames

Every unit frame, nameplate, cast bar, aura container, action bar and button, window, the bags, the objective tracker, the Cooldown Manager, the meters, the micro menu and the notifications is registered by its **kind** when SuuUI makes it.

```lua
function M:OnEnable()
    -- a badge on every unit frame: now, and on each one SuuUI makes later
    self:Each("unitframe", function(f, info)
        -- info.role: "player", "target", "party", "raid", "boss"…; info.preview for settings stand-ins
        f.myBadge = f.myBadge or SuuUI.UI.Text(f, "micro", "gilt-text")
        f.myBadge:SetPoint("TOPLEFT", 2, 7)
    end, function(f)
        if f.myBadge then f.myBadge:Hide() end   -- undo: the module turned off
    end)

    -- after SuuUI redraws a frame's identity, redraw yours
    self:Hook("unitframe", "UpdateIdentity", function(f)
        if f.myBadge then f.myBadge:SetValue(UnitName(f.unit) or "") end
    end)

    -- or replace how something draws, keeping SuuUI's version at hand
    self:Override("actionbutton", "UpdateUsable", function(b, original, ...)
        original(b, ...)            -- SuuUI's drawing
        -- then your change
    end)
end
```

- **Which methods to hook:** each kind's stable ones are listed in API.md › Extending SuuUI's own UI. Other methods work too, but may change.
- **Secret values in combat:** the game hands addons secret values (health, names, auras), which can be passed on but never compared. Hand them to the game's setters (`SetValue`, `SetText`, `SetAlphaFromBoolean`), or check with `issecretvalue(v)` and skip.
- **Ordering:** several plugins' hooks chain in the order they were added. If an override fails, SuuUI's original runs instead.
- **Finding instances:** `SuuUI.Instances(kind)` lists the existing ones, and `SuuUI.InstanceInfo(frame)` tells you what one is.
- **In wowlua** each kind's instances have their class (`KindInstances` in `Core/Extend`): `"unitframe"` gives `UnitFrame`, `"actionbutton"` `ActionButton`, `"meter"` `DamageMeter | ThreatMeter`, and so on, in `Each`, `Hook`, `Override` and `SuuUI.Instances`.

## 5. Menus, buttons and presets

```lua
-- an entry in the objective tracker's right-click menu on a quest
self:ExtendMenu("quest", function(menu, context)
    table.insert(menu.items, { label = "Share on my site", onClick = function() share(context.questID) end })
end)

-- a micro menu button and a game menu entry
self:AddMicroItem({ key = "myplugin", label = "My Plugin", glyph = "gem", onClick = toggleMyWindow,
    open = function() return myWindow:IsShown() end })
self:AddGameMenuItem({ group = "Game", label = "My Plugin", glyph = "gem", onClick = toggleMyWindow })

-- one of the game's popups as a notification card
self:AddNotificationKind("MY_ADDON_CONFIRM", { category = "My Plugin", glyph = "gem", primary = 1 })

-- your settings per role, set by the role presets (SuuTank, SuuHeal, SuuDps)
self:AddToRolePreset("HEALER", { showGroup = true })
```

The menu ids and their context are listed in API.md › Menus, buttons and presets.

## 6. Standing in for a module

A plugin can replace one of SuuUI's modules, its own unit frames for example:

```lua
local M = SuuUI.RegisterModule({ id = "myframes", name = "My Frames", api = "0.17", replaces = "unitframes" })
```

While your module is on, SuuUI's stays off. Settings › Modules says "Replaced by My Frames", and a change takes a `/reload`. To stand in fully:
- Provide the replaced module's **services**, if it has any. For example, a bags replacement provides `self:ProvideService(SuuUI.Services.BAGS, { Toggle = … })` (or by name, `self:Provide("bags", …)`), so the bags key and SuuUI's other windows reach yours. In wowlua the key types the functions.
- Publish the same **anchors** (`SuuUI.PublishAnchor("player", frame, self)`), so other modules attach to your frames. With your module last, the anchor is withdrawn when it turns off.
- Register your frames as the same **kind** (`SuuUI.AddInstance("unitframe", frame, { role = "player" })`), so other plugins' `Each` and hooks reach them.
- Give your frames **movers and settings** of your own.

## 6b. What SuuUI's own modules use

Everything SuuUI's modules use is in the API (0.47), so a plugin has it too. A few things worth knowing ([API.md](API.md) › What the built-in modules use):
- **Another module's service:** `SuuUI.UseService(SuuUI.Services.WORLD_MAP)` (nil while that module is off). Ask a module for a setting with `SuuUI.GetModule(id):Setting(key)` and whether it's on with `:IsEnabled()`; its other methods are its own business.
- **Work built ahead:** `SuuUI.BuildAhead("myplugin: rows", function() … return more end)` makes things a step a frame after login, out of combat, instead of all at once the first time they're needed.
- **The big data tables** (`SuuUI.Data.QuestStarts`, …) build on first use: `:Ready()`, then `:Prepare(done)` to build them over a few frames; `SuuUI.QuestStarts()` builds all of it in one frame.
- **The theme's art on your frame:** `SuuUI.UI.Dress(frame, "window")`.

## 7. A theme

```lua
SuuUI.RegisterTheme({
    id = "frost", name = "Frost", description = "Cold blues instead of gilt.",
    colors = { ["gilt-text"] = { 0.6, 0.85, 1 }, ["gilt-line"] = { 0.4, 0.65, 0.9 } },
    fonts = { header = { file = "Interface\\AddOns\\MyPlugin\\MyFont.ttf", size = 13 } },
    textures = { ["health-bar"] = "Interface\\AddOns\\MyPlugin\\Smooth.tga", bar = "Interface\\AddOns\\MyPlugin\\Smooth.tga" },
    glyphs = { bag = "Interface\\AddOns\\MyPlugin\\Bag.tga", search = "Interface\\AddOns\\MyPlugin\\Search.tga" },
    colors = { shade = { 0.05, 0.08, 0.15 } },
    space = { ["space-4"] = 6, ["space-5"] = 10 },
    sizes = { ["icon-md"] = 22, slot = 32 },
})
```

- **When to call it:** at file load, not in `OnEnable`. Themes apply at login, before SuuUI builds its frames.
- **Choosing it:** the player picks it under Settings › General › Appearance › Theme. A change applies at once.
- **What to change:** colour token names are the keys of `SuuUI.Tokens.color`, and text styles the keys of `SuuUI.Tokens.type`. The chat's lines use `body`'s face (at the player's chat font size), its tabs `header`'s. The chat's colours (`chat-*`) can't be themed (API 0.36): players set them in the game's chat settings, and a theme that sets one gets a warning in the chat.
- **Textures (API 0.35):** `textures` replaces the files the unit frames and nameplates draw: the bars' fill (`health-bar`, `power-bar`, `cast-bar`, `aura-drain`), the absorb shield and the tagged mob's stripes (`absorb`, `tapped`, tiled), the glows, role icons, raid markers, the cast lock and the combat sign. The keys are `SuuUI.Tokens.texture`, and `SuuUI.Tokens.usage[key]` says how each is drawn ([API.md](API.md) lists them under "Textures that follow the theme"). Use white or light art: SuuUI colours it with the colour tokens. API 0.37 adds the rest of the UI: `bar` (every other plain bar: XP and reputation, the swing timer, the meters, the totem and weapon-enchant drains, the tooltip's health), `swing-delay`, the discs and rings (`circle-fill`, `circle-soft`, `circle-band`, `circle-edge`, `circle-dash`, `ring-arc-2` to `-4`: map pins, the minimap, the micro menu's caps), the checkbox tick (`check`) and the settings' reset and lock (`setting-reset`, `setting-lock`).
- **Icons (API 0.37):** `glyphs` replaces SuuUI's icons by name: the window icons, buttons, bags, map pins, the micro menu, menus, professions, notifications and the rest. The names are the keys of `SuuUI.Tokens.glyph` (the file names in SuuUI's `Media/Textures/Glyphs`: `bag`, `search`, `gear`, `chevronDown`, …); give only the ones you want to change. 64 px white art works best: SuuUI colours and sizes it.
- **Nameplate names (API 0.42):** the colour token `plate-name` colours the names on nameplates: white in SuuUI's own look. Friendly players keep their class colour.
- **Quest items (API 0.43):** the texture token `quest-start` is the mark in the bottom-left corner of a bag or bank slot whose item starts a quest: the game's yellow exclamation mark in SuuUI's own look, drawn in its own colours.
- **Dark overlays (API 0.37):** the colour token `shade` (black) colours every dark layer: the shade behind a dialog, the vignettes, the model stage's floor, the minimap's shadow, the aura timers' shade. Each keeps its own strength.
- **Sizes:** text SuuUI draws at a size of its own (big numbers, the NPC dialogue, titles, the minimap's N) grows and shrinks with its text style's `size`.
- **Spacing and sizes (API 0.38):** `space` changes the spacing tokens (`space-1` to `space-7`, 0 to four times the design's px) and `sizes` the size tokens (`icon-md`, `slot`, `unit-lg`, `bar-lg`, `minimap`, `notice-w`, `settings-nav`, …, a quarter to four times), for a denser or roomier UI. Picking the theme lays the windows, unit frames, nameplates, action bar dock, bags, chat, tooltips, minimap, notifications, settings, auction house, tracker and micro menu out again at once; protected frames (unit, party and raid frames, the action bars) after combat. A few parts (the meters, cast bars, aura icons, some windows' lists) take it at their next draw or after a /reload. The player's own sizes win: the player and target frames and the minimap follow your `bar-lg`, `unit-lg` and `minimap` only at their default size. `radius` is accepted too (`radius-sm`, `radius-md`, `radius-round`), but SuuUI draws square corners for now. [API.md](API.md) has the details.
- **Windows (API 0.39):** `textures` also gives the windows a look of their own. `surface-pattern` is tiled over the ground of every panel and window (bags, chat, tooltips, notifications, the settings window) and `track-pattern` behind the bars, both white art in `gilt` whose alpha says how strong it shows (keep text readable over its brightest pixels); `border` draws the panels' 1px edge from its first row and column (a dotted or stitched edge); `corner`, `jewel` and `mark` replace the gilt diamonds on corners, on dividers and under the chosen tab, and the small marks (toggles, sliders, the class mark), drawn upright at twice the diamond's side; `divider` draws the line under a panel's head as an 8 px strip; `plate-health-bar` and `plate-cast-bar` give the thin nameplate bars art of their own. Left out, each stays SuuUI's plain look, and SuuUI makes nothing for it. SuuUI's Pink Cat theme uses every one: see `src/Core/ThemesBuiltin.wowlua` and the art in `tools/pinkcat_art.py`.
- **Art on the frames (API 0.40):** `dress` hangs art on the frames themselves, past their edges where it likes: vines over every window (`window`), a ring of leaves and a parrot on the minimap (`minimap`), a vine on the player and target frames (`unit`), leaves at the chat's corner (`chat`). Each kind takes a `header` (art behind a window's title), `pieces` (art at a point, along an edge or over the whole frame, in front or behind, swaying if you like) and `motes` (fireflies drifting up). [API.md](API.md) has the fields under "Art on the frames"; SuuUI's Stranglethorn themes use every one (`src/Core/ThemesBuiltin.wowlua`, art from `tools/stv_art.py`).
- **The game's fonts:** a `fonts` file can be one of the game's own, such as `Fonts\\MORPHEUS.TTF` (the carved face of quest texts), `Fonts\\FRIZQT__.TTF`, `Fonts\\ARIALN.TTF` or `Fonts\\SKURRI.TTF`, so a theme needs no font of its own for a different face.
- **Class-coloured health (API 0.26):** `health = "class"` shows players' health on every unit frame and nameplate in their class colour, toned. It matters when the player sets "Health colour" to The theme's: class colours are the default, and win over your theme. NPCs are in their reaction colours by default; with NPC reaction colours off they keep `unit-fill`.
- **Cast bar and swing timer (API 0.46):** `cast = "class"` draws the player's cast bar and swing timer in their class colour. Otherwise they're drawn from `cast-fill-deep` to `cast-fill`, with a `cast-edge` leading edge; leave those colours out and they follow your `ghost` (its deep end clear) and `ink`, as before. Like health, this matters when the player sets "Cast bar colour" to The theme's: class colours are the default.
- **Colour vision** applies on top of any theme, so its signal colours always win.

## 8. Aura filter lists

A plugin can bring lists of spells for the player to put on SuuUI's frames (Settings › Frames › Aura filters): a **block** list leaves its spells out, an **allow** list shows only them.

```lua
SuuUI.RegisterAuraFilter({
    id = "myplugin:mechanics", name = "Raid mechanics", kind = "allow",
    description = "The debuffs this raid's fights put on you.",
    spells = { 12345, { ids = { 23456, 23457 }, name = "Doom", notFor = { "PALADIN" } } },
    lists = { "suuui:camping" },
})
```

- **When to call it:** at file load, like a theme.
- **Where it goes:** nowhere until the player attaches it to a frame (party, raid, theirs, the target, focus, bosses, nameplates; buffs and debuffs separately). Your list is read-only for them; they can copy it to edit, and your list updates with your plugin.
- **Entries:** spell IDs (every rank you list), other lists by ID (yours or SuuUI's, `suuui:noise` and the lists inside it), and `notFor`: classes it doesn't apply to, on an entry or the whole list.
- **The game decides some of it:** on players you can help (their debuffs) and on enemies (their buffs) the game lets addons leave out only spells it never keeps secret.

## 9. Everything else: raw access

`SuuUI.Raw` reaches everything SuuUI is made of, for what the API doesn't cover:
- `Raw.UI`: every component, including the ones not exported.
- `Raw.Mixins`: the components' classes (0.19). Change a method on one when your file loads and every frame SuuUI builds afterwards has it, the class's subclasses' frames too.
- `Raw.Module(id)`: a module's internals.
- `Raw.ns`: SuuUI's addon table, which holds the wowlua runtime (`Raw.ns.__wowlua.require("UI/Panel")` gives a module's exports).

**None of it is versioned:** it can change in any SuuUI release. Check what you find, and prefer the documented API where it covers what you need.

## Versions

Declare the oldest API you need (`api = "0.17"`). A SuuUI whose API can't serve that version lists your module as "Can't load" instead of running it. Each entry in API.md says which version added it.
