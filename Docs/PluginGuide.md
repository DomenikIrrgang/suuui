# Writing a SuuUI plugin

A SuuUI plugin is an ordinary addon that adds a **module** to SuuUI. SuuUI's own features are modules written against the same public API, so a plugin can do anything they do: build its own frames from SuuUI's components, add to SuuUI's frames, change how they draw, add to its menus, stand in for a whole module, or bring a theme. This guide goes from an empty folder to all of that. [API.md](API.md) is the full reference.

Two examples ship with SuuUI:
- `Examples/SuuUI_HelloPlugin` covers a module, a setting, a chat command, events and a movable frame.
- `Examples/SuuUI_LevelBadge` adds a badge to every one of SuuUI's unit frames, with its settings on SuuUI's own Unit frames page.

Both are written in [wowlua](https://github.com/DomenikIrrgang/wowlua), like SuuUI itself: run `wowlua install` in either folder to build it into `Interface/AddOns` (or `wowlua build` and copy `dist/dev/<Name>` there). A plugin doesn't have to use wowlua: the plain Lua addon below works as well.

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
- **When modules start:** at login, after every addon has loaded. Register everything in `OnEnable`: events (`M:OnGameEvent`, `M:OnUnitEvent`), messages (`M:On`), setting watchers (`M:Watch`), chat commands (`M:RegisterCommand`) and everything in the sections below. SuuUI removes all of it when the module turns off.
- **Errors stay contained.** An error in `OnEnable` turns your module off with one line in chat, and SuuUI keeps running. Errors in your events, hooks and callbacks are recorded under your module's name.
  - `/suu errors` lists them.
  - The game's own error display is off on this client by default; `/console scriptErrors 1` turns it on.
- **Your module's own fields** (`id`, `name`, `state`…) are SuuUI's and can't be set. Keep your own values under other names. Setting one is an error that names the field.

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
- Provide the replaced module's **services**, if it has any. For example, a bags replacement provides `self:Provide("bags", { Toggle = … })`, so the bags key and SuuUI's other windows reach yours.
- Publish the same **anchors** (`SuuUI.PublishAnchor("player", frame)`), so other modules attach to your frames.
- Register your frames as the same **kind** (`SuuUI.AddInstance("unitframe", frame, { role = "player" })`), so other plugins' `Each` and hooks reach them.
- Give your frames **movers and settings** of your own.

## 7. A theme

```lua
SuuUI.RegisterTheme({
    id = "frost", name = "Frost", description = "Cold blues instead of gilt.",
    colors = { ["gilt-text"] = { 0.6, 0.85, 1 }, ["gilt-line"] = { 0.4, 0.65, 0.9 } },
    fonts = { header = { file = "Interface\\AddOns\\MyPlugin\\MyFont.ttf", size = 13 } },
})
```

- **When to call it:** at file load, not in `OnEnable`. Themes apply at login, before SuuUI builds its frames.
- **Choosing it:** the player picks it under Settings › General › Appearance › Theme. A change takes a reload.
- **What to change:** colour token names are the keys of `SuuUI.Tokens.color`, and text styles the keys of `SuuUI.Tokens.type`.
- **Colour vision** applies on top of any theme, so its signal colours always win.

## 8. Everything else: raw access

`SuuUI.Raw` reaches everything SuuUI is made of, for what the API doesn't cover:
- `Raw.UI`: every component, including the ones not exported.
- `Raw.Mixins`: the components' classes (0.19). Change a method on one when your file loads and every frame SuuUI builds afterwards has it, the class's subclasses' frames too.
- `Raw.Module(id)`: a module's internals.
- `Raw.ns`: SuuUI's addon table, which holds the wowlua runtime (`Raw.ns.__wowlua.require("UI/Panel")` gives a module's exports).

**None of it is versioned:** it can change in any SuuUI release. Check what you find, and prefer the documented API where it covers what you need.

## Versions

Declare the oldest API you need (`api = "0.17"`). A SuuUI whose API can't serve that version lists your module as "Can't load" instead of running it. Each entry in API.md says which version added it.
