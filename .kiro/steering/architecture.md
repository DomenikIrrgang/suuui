# SuuUI Architecture

## Overview

SuuUI is a modular, full interface replacement addon for WoW Classic Anniversary TBC.
It consists of a Core addon and any number of plugins — either bundled inside this
folder or as separate addon folders that declare SuuUI as a dependency.

Everything visible is built from scratch — the layout engine, the components, the animation
runner, the theme and token system, the settings UI. The single exception is `Libs/`: four
embedded third-party libraries that exist so the minimap button can be found by the button
collectors and data-broker displays a player already runs, which is interop no hand-rolled
icon can supply. The boundary is narrow and deliberate — nothing in `Core/`, `Layout/`,
`Components/`, `SettingsUI/` or `Themes/` needs them to work, and exactly one bundled plugin
uses them. See [Embedded Libraries](#embedded-libraries-libs).

---

## Directory Structure

```
SuuUI/
├── SuuUI.toc
├── Bindings.xml           -- the 60 binding NAMES SuuUI declares for the action slots no
│                          --   Blizzard bar exposes (bars 9-13). Loaded by the client from the
│                          --   addon root automatically; deliberately NOT in the .toc
├── Libs/                  -- the ONLY external code; loads first (see Embedded Libraries)
│   ├── LibStub/           -- version arbitration; a table with __call, never a function
│   ├── CallbackHandler-1.0/ -- callback registry LibDataBroker is built on
│   ├── LibDataBroker-1.1/ -- data object / launcher registry the collectors watch
│   └── LibDBIcon-1.0/     -- the minimap button itself; errors at load without the three above
├── Core/
│   ├── Init.lua          -- bootstrap, version, global namespace
│   ├── Game.lua          -- game facts: power colours, spell schools (never themeable)
│   ├── EventBus.lua      -- addon-wide pub/sub (theme, profile, settings)
│   ├── UISignals.lua     -- per-element signal system (Godot-style)
│   ├── UIRoot.lua        -- single fullscreen root, layer management
│   ├── Plugin.lua        -- plugin registry and lifecycle
│   ├── AttachPoints.lua  -- named places one plugin offers another to attach UI to
│   ├── Dock.lua          -- bar-to-bar docking: the anchor graph, four edges, the cycle guard,
│   │                     --   and the cross-plugin participant registry
│   ├── DataBar.lua       -- data bar widget registry + the height the bar occupies
│   ├── ItemCache.lua     -- the ACCOUNT-WIDE record of which character holds what, and where. A Core
│   │                     --   service rather than a plugin file: two plugins read it (the inventory
│   │                     --   window and the tooltip's account section), and the answer has to exist
│   │                     --   whether or not the window that writes it is loaded
│   ├── Readout.lua       -- how a bar's value is SPELLED: the shared current/max, current and
│   │                     --   percent formats, the slot list, the dropdown options -- plus
│   │                     --   Duration, the `2h / 30m / 45s / 0.4s` remaining-time format shared
│   │                     --   by an aura's timer and an action button's cooldown number. Neither a
│   │                     --   game fact nor a token — a presentation choice the whole UI has to
│   │                     --   make the same way, so a unit frame and a tooltip cannot disagree
│   ├── Profile.lua       -- profile storage, CRUD, character linking
│   ├── Settings.lua      -- settings schema registry, value I/O, reactive watchers
│   ├── Fonts.lua         -- font registry: client faces, locale faces, LibSharedMedia
│   ├── Theme.lua         -- token system, theme registry, active theme
│   ├── Pixel.lua         -- pixel grid: root scale, snapping, cursor space conversion
│   ├── ReloadGuard.lua   -- confirmation modal for settings needing a UI reload
│   ├── ToggleUI.lua      -- edit mode state + moveable-frame registry
│   ├── MoveableFrame.lua -- mixin making a frame repositionable in edit mode
│   ├── SnapGrid.lua      -- edit mode grid overlay, snap modes, alignment guides
│   ├── EditPanel.lua     -- edit mode properties inspector (floating window)
│   └── Pool.lua          -- typed frame pool
├── Animation/
│   ├── Tween.lua         -- easing functions
│   ├── Animator.lua      -- animation runner, chaining, sequencing
│   ├── Transitions.lua   -- value-transition registry (instant, smooth, rate)
│   └── Presets.lua       -- named animation presets (fadeIn, slideIn, etc.)
├── Layout/
│   ├── Window.lua        -- draggable, resizable top-level window
│   ├── Container.lua     -- base container; creates or adopts (host) a layout box
│   ├── FlowLayout.lua    -- horizontal / vertical flow with fill + align
│   ├── GridLayout.lua    -- fixed grid
│   ├── StackLayout.lua   -- overlay: inset, align, valign (replaces SetAllPoints)
│   └── AnchorLayout.lua  -- absolute / fraction-driven placement (thumbs, panels)
├── Components/
│   ├── TextMetrics.lua   -- non-visual: real width/height of a string (loads first)
│   ├── Backdrop.lua      -- shared bg+border backdrop primitive (SuuUI.Backdrop)
│   ├── Base.lua          -- InstallBase / InstallEnable: shared handle behaviour
│   ├── Frame.lua         -- styled base frame (border, bg, variant)
│   ├── Text.lua          -- styled FontString wrapper
│   ├── ClickAway.lua     -- shared click-outside and cursor-outside watchers for transient panels
│   ├── UnitClickArea.lua -- invisible secure surface: target a unit, open its context menu
│   ├── Button.lua        -- full custom button (no Blizzard template)
│   ├── Icon.lua          -- display-only texture, optional themed border, bevel trim
│   ├── AuraIcon.lua      -- Icon + cooldown swipe, stack count, duration, dispel border
│   ├── ActionButton.lua  -- secure action bar cell: icon, cooldown, count, hotkey, drag
│   ├── IconButton.lua
│   ├── FlyoutPanel.lua   -- floating vertical roster: one row per entry, adopted icon + name
│   ├── NavItem.lua       -- selectable labelled row (nav lists)
│   ├── DataField.lua     -- one data bar field: muted prefix + value, accent rail on hover
│   ├── Accordion.lua     -- collapsible group of rows + AccordionGroup (one open at a time)
│   ├── Toggle.lua        -- custom checkbox/toggle
│   ├── Slider.lua        -- custom slider
│   ├── Dropdown.lua      -- custom dropdown
│   ├── Input.lua         -- EditBox wrapper (Blizzard required)
│   ├── ColorSwatch.lua   -- clickable colour square
│   ├── ColorPicker.lua   -- custom HSV color picker
│   ├── KeyCapture.lua    -- button that captures the next keypress
│   ├── ScrollFrame.lua   -- scroll container
│   ├── Tooltip.lua       -- custom tooltip
│   ├── Divider.lua
│   ├── ResizeGrip.lua    -- corner drag handle; reports the gesture, resizes nothing
│   ├── Modal.lua         -- dialog with optional input
│   ├── Notice.lua        -- one-shot dismissible message, built on Modal
│   ├── ActionButton.lua  -- secure action/pet cell; slot read from the `action` attribute
│   ├── StanceButton.lua  -- secure shapeshift-form cell, on Blizzard's StanceButtonTemplate
│   ├── ActionBarGrid.lua -- rows x columns of buttons on one glass plate, hairline dividers
│   └── StatusBar.lua     -- progress/resource bar; TWO fractional stack children, a primary
│                         --   fill and a secondary "ghost" fill beneath it
├── SettingsUI/
│   ├── SettingsWindow.lua -- unified settings window (left nav + content)
│   ├── PageBuilder.lua    -- auto-builds a settings page from schema
│   └── Controls/          -- per-type setting control renderers
│       ├── Row.lua
│       ├── Dependency.lua
│       ├── ColorPopup.lua
│       ├── ThemeTokens.lua
│       ├── Toggle.lua
│       ├── Slider.lua
│       ├── Dropdown.lua
│       ├── Color.lua
│       ├── Text.lua
│       ├── Note.lua       -- read-only prose; the one control that edits nothing
│       ├── Keybind.lua
│       ├── SubTabs.lua
│       ├── ProfileManager.lua
│       └── ThemeManager.lua
├── Plugins/               -- bundled first-party plugins live here
│   ├── ActionBars/        -- ActionBars.lua (plugin: 13 bars + pet + stance)
│   │   ├── Suppress.lua   -- hides Blizzard's bottom cluster and hands it back exactly
│   │   └── Paging.lua     -- bar 1's page driver: a secure snippet, not an event handler
│   ├── WatchBars/         -- WatchBars.lua: experience and reputation, one shape twice
│   ├── UnitFrames/        -- UnitFrame.lua (widget, one per unit) + UnitFrames.lua (plugin)
│   │   └── AuraBand.lua   -- one wrapping band of aura icons, for one unit + one filter
│   ├── CastBars/          -- CastBar.lua (widget, one per unit) + CastBars.lua (plugin)
│   ├── DataBar/           -- DataBarWidget.lua (the bar itself, three sections of fields)
│   │   ├── TimeWidget.lua -- the built-in clock: the reference widget definition
│   │   ├── FpsWidget.lua  -- built-in framerate readout, polled once a second
│   │   ├── LatencyWidget.lua -- built-in latency readout, polled every 5s, home/world breakdown
│   │   ├── MicroMenuWidget.lua -- the micro menu, one field per entry, in the `left` section
│   │   ├── BagsWidget.lua -- one field reading `BAGS 27`; replaces the six-button bag row
│   │   ├── AddonButtonsWidget.lua -- built-in tray: a flyout roster of collected minimap buttons
│   │   ├── ButtonCollector.lua    -- finds and adopts those buttons; stands down for MBB
│   │   └── DataBar.lua    -- plugin: owns the bar and every built-in, moves Blizzard's top frames down
│   ├── MinimapButton/     -- MinimapButton.lua: the LDB launcher and its LibDBIcon button
│   ├── Tooltips/          -- reskins the CLIENT's tooltips; draws none of its own
│   │   ├── Skin.lua       -- frame list, backdrop, Blizzard's NineSlice, the three font objects
│   │   ├── Signal.lua     -- the border signal: quality, class/reaction, dispel type
│   │   ├── HealthBar.lua  -- a SuuUI StatusBar inside the tooltip; suppresses Blizzard's
│   │   ├── Content.lua    -- the lines it ADDS, plus the one line it rewrites (the level)
│   │   ├── Anchor.lua     -- a moveable anchor, or cursor-follow
│   │   └── Tooltips.lua   -- plugin: schema, watchers, and every hook installed once
│   └── ...
├── Media/                 -- the icon atlas and the Python that generates it
├── Themes/
│   ├── Default.lua        -- read-only default dark theme
│   └── Modern.lua         -- read-only modern theme (ships as default active)
└── Tests/                 -- not shipped to the client; see TESTING.md
    ├── run.lua            -- test runner
    ├── harness/           -- simulated WoW client + assertions
    └── spec/              -- one spec per component / subsystem
```

`Tests/` is not listed in the `.toc`, so the client never loads it.

---

## Embedded Libraries (`Libs/`)

`Libs/` is the only external code in the addon and the only exception to "everything is built
from scratch": LibStub (v2), CallbackHandler-1.0 (v8), LibDataBroker-1.1 (v4) and LibDBIcon-1.0
(v56, a thousand lines on its own). All four are there for one feature — the minimap button —
and the reason is interop, not convenience.

A minimap button is not hard to draw. It is hard to be *found*. Players already run button
collectors and broker displays — ElvUI's button bar, MBB, SexyMap, Titan Panel, Bazooka,
ChocolateBar — and every one of them discovers buttons by looking for a LibDataBroker data
object and a LibDBIcon registration. An icon we hand-rolled onto the minimap's corner is
invisible to all of them: it cannot be dragged around the ring, cannot be hidden with the rest,
cannot be collected into anyone's bar. **That discoverability IS the library.** Writing it
from scratch would not mean writing our own code, it would mean writing a bug-compatible copy
of someone else's registration protocol — and a near-copy that drifts is worse than no button
at all, because the player's collector silently stops seeing us.

Embedding costs nothing at runtime, and that is the whole point of LibStub. `NewLibrary`
version-arbitrates on the `MINOR` number: a library registers only if it is newer than the copy
already in memory, so a player carrying a newer LibDBIcon in any other addon makes ours a
silent no-op and *every* caller — theirs and ours — ends up on the newer one. Exactly one copy
of each library exists in the client however many addons ship it, which is why embedding rather
than declaring a dependency is what the whole ecosystem does.

**The load order at the top of `SuuUI.toc` is not cosmetic.** LibDBIcon does not degrade
without its dependencies, it *errors at load* — it resolves LibStub, CallbackHandler and
LibDataBroker at file scope — and a `.toc` file that raises takes the addon down before
`Core/Init.lua` has run at all. So the four load first, in dependency order, ahead of
everything else. `Core/Fonts.lua` is the second reason for that placement: its scan probes
LibStub for LibSharedMedia-3.0, and a probe that runs before LibStub exists finds nothing and
says nothing about it.

**`LibStub` is a table with a `__call` metamethod, never a function.** `type(_G.LibStub) ==
"function"` is false with LibStub fully loaded, and that mistake meant the SharedMedia probe in
`Core/Fonts.lua` had never once run — not in game, not in the suite — so no SharedMedia font
was ever harvested and nothing failed to report it. Test for the table and call it through
`pcall` with the silent flag, which returns `nil` for a library the player does not have
instead of raising:

```lua
if _G.LibStub then
    local ok, lib = pcall(_G.LibStub, "LibDBIcon-1.0", true)
    if ok and lib then ... end
end
```

That probe is also the line worth keeping straight, because it predates any of this: *reading*
a library the player happens to own was already established practice here, and it is a
dependency on nothing — `Core/Fonts.lua` harvests SharedMedia's font table when it is present
and shrugs when it is not. *Shipping* a library is the new thing, and it stays fenced. No core,
layout, component, theme or settings-UI file requires anything out of `Libs/`;
`Plugins/MinimapButton/` is the only consumer, it reaches the libraries through the silent
probe above, and an absent or unexpectedly old library costs a `SuuUI.Debug` line and a missing
button rather than a broken login. Adding a fifth library is an architecture decision, not a
convenience one — the bar is the same as it was here: the library must be an interop protocol
other addons define, not functionality we could own.

### The button itself (`Plugins/MinimapButton/`)

The launcher is a plugin with id `minimap_button`, not a few lines inside
`SettingsUI/SettingsWindow.lua` where it used to live. A launcher is not part of the settings
window — it is one way *in* to it, and the window has no business owning something that
outlives it on screen. As its own plugin it also gets a settings page and an off switch for
free: `enabled` shows or hides the button, `locked` freezes its position on the ring. Left
click opens the settings window, right click enters edit mode, and the tooltip says both, since
a right click nobody advertises is a right click nobody uses.

It keeps LibDBIcon's **stock ring art on purpose.** A themed button would be the one addon
button on the minimap that does not look like an addon button, which loses the recognition that
made the button worth shipping. The longer-term direction is the other way round anyway —
pulling other addons' icons into the DataBar rather than making ours prettier where it sits.

**LibDBIcon's position store must be a `plugin:GetProfile()` sub-table, never a value from
`Settings:Get`.** The library mutates that table *in place* while the player drags the button,
writing `db.minimapPos` on every tick of the drag. A table handed out by `Settings:Get` would
be written straight past the settings layer, and the matching `Settings:Set` would then be a
no-op, because its change check compares the table against itself and finds them equal.
`GetProfile()` is the sanctioned route for exactly this shape of data — plugin-private state
whose layout something else owns — and being a profile sub-table it stays profile-aware and
reaches SavedVariables on logout with no write path of our own. Visibility is the opposite
case: LibDBIcon keeps its own `hide` mirror and reads it at register time, so it is seeded from
the `enabled` setting on every enable rather than persisted separately, because two stored
copies of one fact drift apart. And note LibDBIcon exposes no unregister — `Hide` *is* the
teardown, the button object survives a disable, and re-enabling re-shows the same one.

---

## Layer Diagram

```
┌─────────────────────────────────────────────┐
│              External Addons                │  (separate .toc, dep on SuuUI)
├─────────────────────────────────────────────┤
│           Bundled Plugins (Plugins/)        │
├──────────────┬──────────────────────────────┤
│  SettingsUI  │    Plugin-owned UI           │
├──────────────┴──────────────────────────────┤
│         Components + Layout Engine          │
├─────────────────────────────────────────────┤
│   Animation  │  Theme/Tokens │  Frame Pool  │
├─────────────────────────────────────────────┤
│       Core (EventBus, Plugin, Profile,      │
│              Settings, Init)                │
├─────────────────────────────────────────────┤
│              WoW API / Blizzard             │
└─────────────────────────────────────────────┘
```

---

## Core Subsystems

### 1. Namespace & Bootstrap (`Core/Init.lua`)

- Global table `SuuUI` is the single public namespace.
- `SuuUI.version` string.
- Loads subsystems in dependency order via `.toc` file ordering.
- Provides `SuuUI.Debug(msg)` gated behind a debug flag.

### 2. Event Bus (`Core/EventBus.lua`)

Custom pub/sub layer on top of WoW events. Plugins communicate through this,
never by direct function calls into each other.

**API:**
```lua
SuuUI.Events:On(event, callback, owner)    -- subscribe
SuuUI.Events:Off(event, owner)             -- unsubscribe owner from one event
SuuUI.Events:OffAll(owner)                 -- unsubscribe owner from ALL events
SuuUI.Events:Emit(event, ...)              -- fire with varargs payload
SuuUI.Events:Once(event, callback, owner)  -- auto-removes after first fire
```

`Emit` dispatches over a snapshot of the listener list, so a callback may safely
unsubscribe itself or siblings mid-dispatch without skipping or double-firing. Entries
removed during dispatch are flagged dead and skipped by remaining iterations.

Events are plain strings. Convention: `"SUUUI_THEME_CHANGED"`, `"SUUUI_PROFILE_LOADED"`.

### 2b. UI Signals (`Core/UISignals.lua`)

Per-element signal system for UI-to-UI communication. See `UI_SIGNALS.md` for the
full contract. Blizzard frame scripts must never be used to notify other UI elements —
they stay inside the component that owns the frame.

**API:**
```lua
local S = SuuUI.UISignals
local id = S:Connect(obj, S.SIGNALS.SIZE_CHANGED, function(w, h) end)
S:Disconnect(obj, S.SIGNALS.SIZE_CHANGED, id)
S:DisconnectAll(obj, signal)   -- signal optional; omit to clear the object
S:Emit(obj, S.SIGNALS.SIZE_CHANGED, w, h)
S:HasConnections(obj, signal)
```

Registry uses weak keys, so destroyed objects are collected and their connections
vanish with them. Callbacks run through `pcall` and log failures via `SuuUI.Debug`.

Built-in bus events: `SUUUI_PROFILE_LOADED`, `SUUUI_THEME_CHANGED`, `SUUUI_FONTS_CHANGED`,
`SUUUI_PIXEL_GRID_CHANGED`, `SUUUI_SETTING_CHANGED`, `SUUUI_PLUGIN_ENABLED`,
`SUUUI_PLUGIN_DISABLED`. `SUUUI_MOVEABLE_LIST_CHANGED` fires when a moveable frame is
registered or unregistered. Deprecated: `SUUUI_EDIT_MODE_CHANGED` — still emitted for
third-party listeners, but new code watches the setting instead (see 5b).

**To react to one setting, use `Settings:Watch`, not `SUUUI_SETTING_CHANGED`.** The event
is a broadcast of every write in the addon, so a listener has to filter by pluginId and
key, gets no initial value, and has to subscribe to `SUUUI_PROFILE_LOADED` separately to
survive a profile switch. `Watch` handles all three. The event remains the right tool for
something that genuinely cares about *any* setting changing, such as `ReloadGuard`.

**Standard signals** (payload in parentheses): `SIZE_CHANGED` (w, h),
`POSITION_CHANGED` (x, y), `VISIBILITY_CHANGED` (isVisible), `MOUSE_ENTER` (—),
`MOUSE_LEAVE` (—), `CLICKED` (button), `VALUE_CHANGED` (new, old),
`TEXT_CHANGED` (text), `SCROLL_CHANGED` (scrollY), `CONTENT_RESIZED` (height),
`ENABLED_CHANGED` (isEnabled), `FOCUSED` (—), `UNFOCUSED` (—).

**Choosing the right bus:**

| Kind | Mechanism |
|---|---|
| UI element notifying another UI element | `SuuUI.UISignals` |
| Reacting to one setting's value | `SuuUI.Settings:Watch` |
| One plugin offering another a place to put UI | `SuuUI.AttachPoints` |
| Addon-wide state change | `SuuUI.Events` |
| WoW game data | `frame:RegisterEvent` in a plugin |

### 3. Plugin System (`Core/Plugin.lua`)

Plugins register with the core. The core drives their lifecycle.

**API:**
```lua
-- Called by plugin author to register
local plugin = SuuUI:CreatePlugin({
  id       = "minimap",        -- unique snake_case string
  name     = "Minimap",        -- display name for settings UI
  version  = "1.0",
  onInit   = function(p) end,  -- exactly once, on login or on late registration
  onEnable = function(p) end,  -- called when plugin is enabled
  onDisable= function(p) end,  -- called when plugin is disabled
})

-- Returned plugin handle methods
plugin:GetSettings()    -- returns plugin's live settings table
plugin:GetProfile()     -- returns plugin's profile sub-table
plugin:IsEnabled()
plugin:Enable()         -- no-op when already enabled
plugin:Disable()        -- no-op when already disabled
```

**The definition is NOT stored on the handle.** `Core/Plugin.lua` keeps it in a module-private
weak-keyed table (`local defs = setmetatable({}, { __mode = "k" })`), written once at
`CreatePlugin` and read by `InitAll`, `Enable` and `Disable`. The handle carries only `id`, `name`,
`version` and its methods, so **every other field on it belongs to the plugin** and cannot collide
with the framework.

It used to live at `plugin._def`, and a plugin storing its own state under that name destroyed its
own `onDisable` — `Disable` reads the definition to find the hook, so the plugin simply stopped
tearing itself down. **The failure was silent in both directions**: no error, because the hook was
never called; and had one been thrown, `Disable` `pcall`s it into `SuuUI.Debug`, which prints
nothing with debug off. That silence is a general hazard, not a one-off — `onInit`, `onEnable` and
`onDisable` are all `pcall`'d into a debug-gated log, so never rely on seeing a throw from a
plugin hook. Use `SuuUI.Fault` for anything the player must know about.

On `PLAYER_LOGIN` the core runs every `onInit`, then every `onEnable`, in two separate
passes — so an `onEnable` may rely on another plugin's settings and events already
existing, while an `onInit` may not. Plugins must NOT assume load order of other plugins.

**`onInit` runs exactly once per plugin.** `Plugins:InitAll()` skips plugins already
initialised, so it is safe to re-call. A plugin registered *after* the login pass — an
addon whose `.toc` loads later — is initialised and enabled at `CreatePlugin` time
instead, so it comes up identically without re-entering anyone else's `onInit`.

```lua
SuuUI.Plugins:InitAll()            -- idempotent
SuuUI.Plugins:IsInitialised(id)    -- whether onInit has run
```

### 3b. Attach Points (`Core/AttachPoints.lua`)

**How one plugin puts UI inside another plugin's frame without either knowing the other
exists.** A cast bar has to become part of the player unit frame — take its width, move
with it, grow it — while living in a different plugin. Reaching into `UnitFrames` for its
frame would couple the two directly, and would break on load order: whichever plugin came
up second would find nothing there.

So the owner of a frame **publishes** a named point and keeps ownership of placement, and a
consumer **requests** that name. The request is delivered immediately with the current
state and again on every change, so a consumer never has to know who loads first — and is
told when the point goes away.

**API:**
```lua
SuuUI.AttachPoints:Publish(name, provider)   -- offer a point
SuuUI.AttachPoints:Revoke(name)              -- withdraw it; consumers are notified with nil
SuuUI.AttachPoints:Get(name)                 -- provider or nil
SuuUI.AttachPoints:Has(name)
SuuUI.AttachPoints:List()
SuuUI.AttachPoints:Request(name, cb, owner)  -- subscribe; fires now and on every change
SuuUI.AttachPoints:Release(owner)            -- drop one owner's requests
SuuUI.AttachPoints:GetRequestCount()         -- live count; specs assert against leaks
```

**Provider shape.** The publisher exposes a parent frame and takes the child, rather than
handing out its containers:

```lua
SuuUI.AttachPoints:Publish("unitframe.player", {
    frame  = wrapper,                                    -- parent for an attaching child
    Attach = function(child, opts) ... end,              -- opts is the publisher's own vocabulary
    Detach = function(child) ... end,
})
```

`Publish` asserts on a provider missing any of the three. Names are dotted and namespaced
by the publisher: `"unitframe.player"`.

**Why the publisher places the child.** The frame that owns a layout is the only thing that
knows how to grow around a new band, and a consumer that added itself to someone else's
container would have to know that container's strategy, its child order, and how the owner
computes its own height. `Attach` is therefore the whole interface: the unit frame keeps
two hidden slot containers (above and below its own content) and adds the child to one with
`width = "fill"`, which is what makes an attached widget exactly as wide as the frame and
follow its width slider without ever reading it.

**Why a subscription rather than an event.** A broadcast fires once, so a consumer that
registered late has to call `Get` as well — the same duplication `Settings:Watch` exists to
remove. `Request` always delivers, and there is deliberately no `immediate` opt-out.

Notification iterates a snapshot with a dead flag, so a callback may `Release` itself or a
sibling mid-dispatch (a consumer that rebuilds its widget does exactly that) without
skipping or double-firing. Callbacks run through `pcall` and log failures via `SuuUI.Debug`.

**Published by the first-party plugins:**

| Name | Publisher | `opts` |
|---|---|---|
| `unitframe.player` | `Plugins/UnitFrames/UnitFrames.lua` | `{ position = "above"｜"below" }` |
| `unitframe.target` | `Plugins/UnitFrames/UnitFrames.lua` | `{ position = "above"｜"below" }` |

One point per unit, named `unitframe.<id>` from the plugin's `UNITS` list, so a new unit
frame publishes its own without a line of code being written for it.

**Revoke before you tear down.** `UnitFrames` revokes in `onDisable` *before* destroying
its frame, so consumers detach while the slot still exists. A consumer left holding a child
inside a destroyed container is the failure this system exists to prevent.

**A publisher must show its slot before adding the child.** The publisher hands out one frame
as the child's **parent** and places it with a **different** container, so the usual escape
does not apply: showing the container afterwards does not dirty a child that is not its own.
A hidden frame has no rect, and a child anchored to one never resolves a position — it draws
nothing while reporting the size it was assigned. See "Show a container before anchoring a
foreign child to it" in `LAYOUT_SYSTEM.md`.

**A moveable publisher must report a core inset.** Growing to hold a foreign child changes
the frame's bounding box, which is what its stored position resolves against — so the
frame's own content slides by the band's height on the edge its anchor does not pin. See
`coreInset` in 5c.

**Nothing protected may live inside a frame that grows.** Both growth paths on a unit frame
happen *in combat by definition* — an aura band gains a row when a debuff lands, the cast bar
attaches when a cast starts — and the client refuses addon-driven geometry on any frame whose
subtree holds a protected frame while `InCombatLockdown()` is true. Protection propagates down
to descendants and the refusal propagates up, so one secure grandchild freezes the whole
wrapper: the growth is refused silently, the band is carved out of a box stuck at its
pre-combat height, and the frame's own bars are pushed down by the band's height. `UnitFrames`
shipped exactly that for ten days, with `GetPreferredSize` returning 227 against a `GetHeight`
of 188 and `InCombatLockdown()` true on every mismatch. The secure click surface therefore
lives *beside* the wrapper and is anchored to it — see the `UnitClickArea` entry in the
Component Library, and "Protected Actions Go Through A Secure Component" in
`WOW_API_ENCAPSULATION.md` for the full account. The rule generalises to anything a publisher
puts in a growing frame: if a child is protected, the frame that grows may not contain it.

### 3c. Data Bar Registry (`Core/DataBar.lua`)

**An ordered list of entries contributed by plugins that know nothing about each other.** The
data bar is a full-width strip along the top of the screen whose fields come from whoever
wants one — a built-in clock, framerate and latency readouts and an addon-button tray today, a
gold readout or a durability meter later. A plugin registers a widget *definition*,
which is data; the bar renders it. Neither side names the other, and registration order does
not matter, so a plugin that loads after the bar is picked up exactly as one that loads before
it.

**No bundled plugin exercises the cross-plugin path any more, and the registry is still the
right shape.** This used to lean on `Plugins/Performance` as the first contributor that did not
own the bar — the one place a definition had actually crossed the boundary the registry draws,
since the clock is registered from inside the `DataBar` plugin, which owns both sides of it.
That claim is no longer true of anything shipped: the framerate, latency and addon-button
widgets have been folded into `Plugins/DataBar` as **built-ins**, so every bundled definition
is now registered by the plugin that owns the bar. What remains is honest to say plainly — the
cross-plugin path is exercised by **third-party plugins and by the suite**, and by nothing in
the bundle. That is a real loss of production proof, and it is the reason the specs covering
registration from a foreign plugin id matter more than they used to rather than less: they are
the only thing standing between a refactor and a boundary nobody walks over on login.

The reason for keeping the registry after the fold is unchanged, and it is not the bundle's
convenience. Ordering across contributors, a definition that survives its plugin loading late,
and an answer that exists whether or not the bar is loaded at all are properties an author
outside this repository depends on. Folding the bundled widgets in changed who happens to call
`RegisterWidget`; it did not change what the call promises.

**A definition may carry a `schema`.** Its entries are rendered on the **bar's own** settings
page, next to the controls for the bar itself, which is where a player looks for a setting about
a strip of text they can see. This was refused for a long time on a real objection:
`Settings:Register` may be called only once per plugin, in `onInit`, while a widget may register
at any point, so there was no moment at which the bar's page could splice in a stranger's
schema. Two changes removed that objection — a plugin's schema is now **extendable** (`5`,
`Settings:Extend` / `Retract`), and the page **reads the registry when it builds** rather than
once at registration, so a widget arriving after `onInit` needs nothing spliced into a call that
has already run. The contributor keeps ownership of the values; the full contract, including why
the watcher owner stays keyed to the page's plugin id, is in `plugin-authoring.md` —
"Where your widget's settings belong".

**The addon-button tray stands down when MinimapButtonButton is loaded.** The two features are
genuinely incompatible rather than merely redundant: both collect the same frames by the same
mechanism, so two collectors reparenting one button take it in turns and the player watches an
icon flicker between two homes. MBB also replaces `SetParent` and `SetPoint` on the buttons it
holds with no-ops, which means a tray that collected anyway could never hand the ring back on
disable. So the collector refuses to run while that addon is present and the field reads `—`
until one of the two is switched off — a visible nothing rather than a silent half-collection,
because a tray that quietly shows three of a player's nine buttons reads as a bug in this addon.

**It is deliberately not an attach point, and the difference is shape rather than intent.** An
attach point is ONE provider per name (3b): `Publish` overwrites, `Get` answers with a single
provider, and a consumer asks for a *place*. A bar field is one of MANY entries spread across
three fixed sections and ordered within each, so expressing the same thing through a
single-provider registry would take a point name per widget — `databar.field.clock`,
`databar.field.gold` — which the bar would then have to discover without having been told
them, and would still carry no ordering at all. Ordering across contributors is the thing
this registry adds.

**API:**
```lua
SuuUI.DataBar.SECTIONS                        -- { "left", "center", "right" }, in screen order
SuuUI.DataBar:RegisterWidget(def)             -- add or replace a widget by its id
SuuUI.DataBar:UnregisterWidget(id)
SuuUI.DataBar:GetWidget(id)                   -- definition or nil
SuuUI.DataBar:Has(id)
SuuUI.DataBar:List()                          -- every widget, section then order then id
SuuUI.DataBar:ListSection(section)            -- one section, in order
SuuUI.DataBar:Subscribe(cb, owner)            -- fires now and on every register/unregister
SuuUI.DataBar:Unsubscribe(owner)              -- returns how many were dropped
SuuUI.DataBar:GetSubscriberCount()            -- live count; specs assert against leaks

SuuUI.DataBar:SetOccupiedHeight(h)            -- the renderer publishes; nobody else calls this
SuuUI.DataBar:GetOccupiedHeight()             -- root units, 0 when there is no bar
SuuUI.DataBar:WatchHeight(cb, owner)          -- fires now and on every change
SuuUI.DataBar:UnwatchHeight(owner)
SuuUI.DataBar:GetHeightWatcherCount()
```

The definition's fields, and the contract each one carries, are in
`plugin-authoring.md` — "Adding a widget to the data bar". `id` plus either `GetText` or
`Build` is the whole requirement; `section` defaults to `"left"` and `order` to 100, and an
unknown section raises rather than being silently filed under one.

**`GetText` may return a TONE as a second value** — nil, `"success"`, `"warning"` or
`"danger"` — which the field resolves onto the matching intent token. The widget says what the
READING MEANS and the theme decides what that looks like, so a retint moves every threshold
colour in the addon at once; a widget composing its own `|cff…|r` escape would hardcode a hue,
bypass that retint, and give every plugin author a different way to do one thing. It is
returned **with** the value rather than from a hook of its own, so the two come from a single
reading and cannot disagree about what is on screen. An unrecognised string degrades to the
default text colour rather than raising, which matters because this is resolved from inside a
ticker callback.

**Whatever renders a definition must capture the two into explicit locals.** A Lua multi-return
expands only in the last argument position, so `field:SetText(def.GetText())` hands the tone
over as `SetText`'s *second argument* — silently, since `SetText` takes one value and ignores
the rest. `DataBarWidget:_refresh` therefore writes `local ok, text, tone = pcall(def.GetText)`
and calls `SetText` and `SetTone` separately.

**Sorted by section, then order, then id.** The id is the last key so the ordering is *total*
rather than merely partial: two widgets sharing a section and an order would otherwise come
out in `pairs` order, which is hash order, which differs between runs — a bar whose fields
swap places on some logins, and a spec that passes intermittently.

**`Subscribe` delivers immediately and there is no opt-out**, for the same reason
`AttachPoints:Request` has none: a subscriber that reads `List()` separately and *then*
subscribes has two code paths for one fact, and its separate read happens before anyone else
has had the chance to register. Notification iterates a snapshot with a dead flag, so a
subscriber may unsubscribe itself or a sibling mid-dispatch — the renderer's rebuild does
exactly that — and callbacks run through `pcall` and log failures via `SuuUI.Debug`.

**Notification carries no payload.** A subscriber re-reads the set. Handing over the
definition that changed would invite acting on one entry while the ordering it belongs to has
moved, and the renderer's rebuild is a handful of frames rather than something worth
optimising — every registration during login costs one rebuild, once, in microseconds.

**A duplicate id overwrites rather than raising**, exactly as `Publish` does: a plugin that
re-registers on re-enable would otherwise take the client down from inside its own `onEnable`.
`SuuUI.Debug` still names the case that is a real bug, two owners claiming one id. `List`
returns a fresh array for the reason `Container:GetPadding` returns a copy — the internal one
is what the renderer's next pass reads, so a caller mutating it would reorder the bar with no
rebuild behind it.

**Why the occupied height lives in Core and not on the renderer.** Everything that used to hug
the top of the screen has to move down by the bar's height — Blizzard's minimap and buff frame
today, a SuuUI replacement for either later — and that answer has to exist when the bar does
not. A consumer reading the renderer's frame breaks the moment the player switches the bar
off, which is precisely when the correct answer is **0** rather than an error or a nil frame;
the same holds while the plugin is disabled, absent from the load, or merely loaded later than
whoever is asking. So the renderer publishes a number into Core, every consumer reads it from
there, and "bar" and "no bar" are one code path instead of two.

**The height is a length in the UI root's units**, so handing it straight to a frame anchored
to `UIParent` is wrong by the ratio between the two effective scales — the vertical-only
failure 6c describes, which looks like the minimap moving down by *almost* the right amount
and only at some resolutions. Convert it with `Pixel.Convert` at that boundary.

### 3d. Dock (`Core/Dock.lua`)

Bar-to-bar arrangement: any bar can attach to any other bar, on any of four edges. Published as
`SuuUI.Dock`.

**It is a Core service because its participants are no longer all action bars.** It began as
`Plugins/ActionBars/Dock.lua`, published under `SuuUI._ActionBars.Dock`, and the experience and
reputation bars now dock through the same code. The move was a rename, not a rewrite, because the
dock never knew what an action bar was — it asks a participant for exactly three things:

| Required of a participant | Why |
|---|---|
| `GetFrame()` | to anchor |
| `GetWidth()` / `GetHeight()` | the span the next child on that edge stacks past |
| a `SIZE_CHANGED` signal | a bar gaining a row moves everything past it, and nothing else would notice — `Attach` and `Detach` are the only other reflow triggers, and neither fires for a resize |

Anything satisfying that can dock. A `StatusBar` handle already did.

**ANCHORED, NOT CONTAINED**, and that is the load-bearing decision. Containing would make the
dock's frame resize whenever a bar attaches — and the dock holds protected buttons, so the client
refuses that resize in combat. Nothing here resizes, so there is nothing to refuse, and no
`coreInset` to keep in step with a stored position. **Chains work for free**, because an anchor is
a live relationship: bar 4 on bar 5 on bar 1 needs no extra machinery, since moving bar 1 moves
bar 5, which moves bar 4. Only a *size* change needs a reflow.

**Cycles are the one thing that must not get through.** A circular anchor is not a cosmetic fault
— the client raises a hard error and leaves the frame unplaced. So `Attach` refuses one outright
rather than half-applying it, and the settings layer rejects the choice before it is ever stored.

**An anchor is the same dependency as parentage.** The client refuses geometry on a frame whose
movement would move a protected one, and does not care whether the link is a parent or a point.
Which is why the *plugin* defers the whole dock/free transition out of combat, and why `Reflow`
carries no combat guard of its own — nothing can ask for a reflow during a fight, and mutation
testing showed such a guard unreachable.

**The graph half:**

| Call | Notes |
|---|---|
| `Dock.EDGES` | `{ "above", "below", "left", "right" }` |
| `Dock.Attach(dock, child, opts)` | `opts = { order, edge }`, edge defaults `"above"`. Idempotent; returns **false** when refused as a cycle. Moving between docks is Detach + re-attach |
| `Dock.Detach(dock, child)` | Leaves the bar where it was until its owner re-positions it |
| `Dock.Release(dock)` | Detaches the dock from **its own** parent first and unconditionally — a bar with nothing attached to it has no record here, so an early return once left it anchored to a destroyed parent |
| `Dock.Reflow(dock)` | Stacks each edge independently; the gap between plates is `spaceXxs` |
| `Dock.WouldCycle(dock, child)` | Walks upward from the candidate dock; **step-bounded** as well as identity-checked, so an already-corrupt graph cannot spin |
| `Dock.Children` / `ParentOf` / `EdgeOf` | Read-only queries; `Children` returns a copy |

`Reflow` states `relativeTo` **explicitly** in every descriptor. Layout props live on the FRAME,
so a frame belonging to two containers has one props table — and an anchor with no `relativeTo`
resolves against whichever container applies it. The root container re-applied this very
descriptor with itself as the relative frame and pinned every docked bar to the top of the screen.

**The participant registry half**, and it exists for one reason: **the settings-level cycle guard
cannot work per plugin.** A watch bar attached to bar 1 while bar 1 is attached to that watch bar
is a real loop, and neither plugin can see it — each holds one half of the graph.

| Call | Notes |
|---|---|
| `Dock.RegisterParticipant(id, spec)` | `spec = { label, group, sort, point, attachedTo }`. `attachedTo` is a closure returning the id this participant is *currently set* to attach to, read from **that plugin's** settings — which is the whole trick |
| `Dock.UnregisterParticipant(id)` | For a plugin going down, so its bars stop being offered |
| `Dock.Participants()` | Sorted group → sort → registration sequence |
| `Dock.PointFor(id)` | The participant's `AttachPoints` name, so a dependent can `Request` it |
| `Dock.OptionsFor(excludeId)` | Dropdown options, `"Free"` first |
| `Dock.WouldCycleIds(fromId, toId)` | Walks the **STORED** graph, because a validator runs before the value is stored |

Handle resolution is deliberately **not** here — `AttachPoints` already solves it, including a
target that does not exist yet or is switched off underneath.

Two details that were learned the hard way. **Ids are profile data**: the action bars keep the
plain ids already written into profiles (`"1".."8"`, plus `"stance"` and `"pet"`, which is why
they were never coerced with `tonumber`), and everything registering later namespaces its own
(`"watch:xp"`). And **`table.sort` is not stable in Lua**, so `RegisterParticipant` stamps a
registration sequence as the final tiebreaker — without it the eight action bars, all tied on the
same sort key, listed as 4, 6, 5, 2, 3, 7, 1, 8.

Labels are **not** group-prefixed. Prefixing them looked like disambiguation and produced eight
consecutive rows of `"Action Bars: Ba..."` in a 140px dropdown; the labels are unique on their
own, and the spec asserts that uniqueness so a future collision is caught at the source.

### 4. Profile System (`Core/Profile.lua`)

- Profiles stored in `SuuUIProfiles` SavedVariable (account-wide).
- Each profile is a named table. Default profile cannot be deleted.
- Characters can be linked to any profile.
- On login, core loads the profile linked to the current character
  (falls back to Default).

**API:**
```lua
SuuUI.Profiles:Create(name)           -- new profile, copies Default as base
SuuUI.Profiles:Delete(name)           -- error if "Default"
SuuUI.Profiles:List()                 -- returns array of profile names
SuuUI.Profiles:SetActive(name)        -- switch, fires SUUUI_PROFILE_LOADED
SuuUI.Profiles:GetActive()            -- returns active profile table
SuuUI.Profiles:LinkCharacter(name)    -- links current character to profile
SuuUI.Profiles:Get(name)              -- returns raw profile table
SuuUI.Profiles:CopyTo(targetName)     -- deep-copies active profile into target
```

Plugin settings are namespaced inside profiles:
`profile.plugins[pluginId] = { ... settings ... }`

### 5. Settings Registry (`Core/Settings.lua`)

Stores schema definitions. Does NOT render UI — that is SettingsUI's job.

Schema entry shape:
```lua
{
  key      = "showBorder",   -- unique within plugin
  label    = "Show Border",
  type     = "toggle",       -- toggle|slider|dropdown|color|text|keybind|note|section|subtabs
                             -- plus position|internal: a key that needs a default and a
                             -- home in the profile but no control (see plugin-authoring.md)
  default  = true,
  -- type-specific:
  min=, max=, step=          -- slider
  options={}                 -- dropdown: array of {value, label}
  validate = function(v) end -- optional, returns true or error string
  transient = true           -- optional: session state, never saved (see 5b)
  owner    = "other_plugin"  -- optional: control renders on THIS page, value lives in that
                             -- plugin's namespace (contributed entries; see below)
}
```

**API:**
```lua
SuuUI.Settings:Register(pluginId, schemaArray)
SuuUI.Settings:Extend(pluginId, entries)   -- append to a schema, creating it if absent
SuuUI.Settings:Retract(pluginId, keys)     -- remove entries again
SuuUI.Settings:GetSchema(pluginId)
SuuUI.Settings:Get(pluginId, key)          -- stored value, else the schema default
SuuUI.Settings:Set(pluginId, key, value)   -- writes, notifies watchers, fires the event
SuuUI.Settings:Reset(pluginId, key)        -- resets to schema default
SuuUI.Settings:ResetAll(pluginId)
SuuUI.Settings:IsTransient(pluginId, key)
```

Event payload: `"SUUUI_SETTING_CHANGED"` → `pluginId, key, value, oldValue`
Event payload: `"SUUUI_SCHEMA_CHANGED"` → `pluginId`

**A schema is not stated once and closed.** `Register` is called once per plugin in `onInit`,
which for a long time meant a page could only ever show controls its own plugin had declared
before anything else loaded. `Extend` appends entries afterwards — creating the schema when the
plugin has none yet — and `Retract` takes them back out, which is what lets a surface owned by
one plugin host a control contributed by another. The data bar is the case that needed it: a
widget may register at any point, so there is no `onInit` moment at which the bar's page could
have spliced in a stranger's schema, and `Extend` plus a page that reads the registry at build
time is what replaces that missing moment.

Three properties of the pair are load-bearing:

- **`Extend` skips a key that already exists.** A re-register on re-enable hands over the same
  entries again, and an append that did not de-duplicate would produce a page carrying two of
  every control — the second one writing the same key as the first.
- **It emits `SUUUI_SCHEMA_CHANGED`.** A settings window already on screen has no other way to
  learn that the page it is showing has grown; without the event the new control appears on the
  player's next visit, which reads as the setting having failed to register at all.
- **`Retract` drops a section header the removal left empty.** A `section` entry opens an
  accordion (5, `SettingsUI`), so a header whose entire body has been retracted is a control
  that opens onto nothing — the player reads an empty group as a rendering fault rather than as
  an absent widget.

**An entry may name an `owner`, which decides where the VALUE lives.** `owner = "<pluginId>"`
means the control renders on the hosting plugin's page while `Get` and `Set` address the
*contributor's* namespace. Ownership stays with the contributor for two reasons that only show
up later: the value is profile-scoped to the plugin that declared it, so a profile switch moves
it with the rest of that plugin's state rather than with the host page's; and it survives the
contribution being retracted, so a player who switches a widget off and on again does not find
their tuned thresholds reset. Parking the value under the host would tie one plugin's
configuration to the lifetime of another plugin's page.

**The watcher owner, by contrast, stays keyed to the PAGE's plugin id.** A control the page
builds watches under `Settings.ControlOwner(<page's pluginId>, kind, key)` even when the entry's
`owner` is someone else, because `PageBuilder` drops a rebuilt page's watchers with
`UnwatchPrefix` on that page's prefix (5b). Keying the watcher to the contributor puts it outside
the prefix the rebuild sweeps: it survives, the rebuild adds another, and the page leaks one
watcher per rebuild into destroyed controls. `owner` answers who owns the data; the watcher owner
answers who cleans the control up, and those are different questions.

**`Set` carries effective values, not raw stored ones.** A key that has never been
written stores `nil` while reading as its schema default, so both the watcher payload and
the event report what `Get` would return — before and after. Handing out the raw `nil`
tells a subscriber the setting is unset when it reads as `true`, and any listener that
writes `oldValue` back (`ReloadGuard` does, to revert a cancelled change) then clears the
key and leaves every bound widget rendering `nil`.

**A write that does not change the effective value is dropped** — no store write, no
watcher call, no event. Tables are compared structurally, not by reference, because
positions and colours are stored as a fresh table on every save and reference equality
would report each one as a change and echo it back to whoever wrote it.

### 5b. Reactive State Bindings (`Settings:Watch`)

**The store is the single source of truth. A feature must never keep its own copy of a
value that also lives in Settings.** Two copies reconciled by events is the bug this
system exists to prevent: the settings panel and a slash command each held their own
edit-mode flag, and whichever the user did not touch went stale.

Do not re-render the UI from scratch on a state change — WoW frames are retained
objects, and rebuilding them loses scroll position, animation state and anchors. Instead
subscribe to the individual key you display and patch that one property. Same guarantee
as a declarative framework ("if state changes, the UI reflects it"), reached the way a
retained-mode toolkit reaches it.

```lua
SuuUI.Settings:Watch(pluginId, key, callback, owner, opts)
SuuUI.Settings:Unwatch(owner)              -- drop one owner's watchers
SuuUI.Settings:UnwatchPrefix(prefix)       -- drop a whole group at once
SuuUI.Settings:GetWatcherCount()           -- live count; tests assert against leaks
SuuUI.Settings.ControlOwnerPrefix(pluginId)      -- "page:<pluginId>:"
SuuUI.Settings.ControlOwner(pluginId, kind, key) -- one settings-page control
```

The callback receives the effective value. It fires when `Set` changes the value **and**
on profile switches, so a bound widget cannot drift from the store regardless of what
caused the change — panel, slash command, keybind, or another plugin.

**Pass `{ immediate = true }` unless you have a reason not to.** It fires the callback
once at registration with the current value, which makes the callback the single place
that renders the value:

```lua
-- The watcher owns the displayed value, initial state included
SuuUI.Settings:Watch(pluginId, entry.key, function(val)
    tog:SetValue(val)
end, SuuUI.Settings.ControlOwner(pluginId, "toggle", entry.key), { immediate = true })
```

Reading the value separately to seed the widget and *then* watching for changes is the
same duplication in miniature, and it is how `MoveableFrame` shipped a frame that was
draggable with no visible overlay: it hid the overlay at construction and waited for a
change that had already happened.

**Every `Watch` needs an owner, and something has to unwatch it.** A watcher outlives the
widget it drives unless someone drops it, and a leaked one keeps firing into a destroyed
handle on every write and every profile switch. Two conventions cover the codebase:

| Subscriber | Owner | Dropped by |
|---|---|---|
| a settings-page control | `Settings.ControlOwner(pluginId, kind, key)` | `PageBuilder` calls `UnwatchPrefix` when it rebuilds that content area |
| anything else | any stable string | whatever owns the teardown (`MoveableFrame:Remove`) |

`GetWatcherCount` exists so a spec can assert that a rebuild is watcher-neutral. Use it:
a subscription leak is invisible until something fires into freed state.

**Callbacks may Watch and Unwatch while a notify is in flight** — rebuilding a settings
page does exactly that, from inside a watcher on the plugin's `enabled` key. Notification
therefore iterates a snapshot, and a watcher removed mid-pass is skipped rather than
delivered to. A watcher added mid-pass is not called until the next change.

**`transient = true` marks session state rather than a preference.** The value lives for
one UI session and never reaches SavedVariables, so it starts at its default on every
login and a profile switch neither reads nor writes it. Edit mode is the case that named
the flag: it is a mode the player is currently in, and persisting it logged them back in
with every frame draggable.

Reach for it when the answer to "should this survive `/reload`?" is no. Everything the
player configures is a preference and stays in the profile.

### 5c. Edit Mode & Moveable Frames

`Core/ToggleUI.lua` holds edit mode; `Core/MoveableFrame.lua` makes one frame
repositionable. Both are consumers of 5b rather than state owners — ToggleUI keeps no
flag of its own, and every surface that cares subscribes to the same key.

```lua
SuuUI.ToggleUI:IsEditMode()          -- reads Settings("_layout", "edit_mode")
SuuUI.ToggleUI:Toggle() / :Enable() / :Disable()
SuuUI.ToggleUI:Register(frame) / :Unregister(frame) / :GetAll()
-- Register/Unregister emit SUUUI_MOVEABLE_LIST_CHANGED. EditPanel rebuilds its element
-- list from it: a frame that changes mode (a resource bar going attached -> detached)
-- is Removed and re-Applied, and a panel that only rebuilt on edit-mode entry would go
-- on listing a frame that no longer exists.

SuuUI.MoveableFrame:Apply(frame, {
  pluginId = "unit_frames", key = "player_position",
  displayName = "Player Frame",
  defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 },
  -- Only for a frame that grows around content it does not own (see below)
  coreInset = function() return aboveInset, belowInset end,
})
SuuUI.MoveableFrame:RestorePosition(frame)
SuuUI.MoveableFrame:ResetPosition(frame)
SuuUI.MoveableFrame:SetLocked(frame, bool)  -- writes `locked` into the stored position
SuuUI.MoveableFrame:IsLocked(frame)
SuuUI.MoveableFrame:RefreshAnchor(frame)  -- re-state placement after coreInset changed
SuuUI.MoveableFrame:Remove(frame)     -- unwatches; required on teardown
```

**`coreInset` is required for any frame that publishes an attach point.** A stored position
describes an anchor point, and the client resolves it against the frame's **bounding box** —
so a frame that grows around a foreign child moves everything it owns. Growth lands on the
edge the anchor does *not* pin, which makes the failure asymmetric and easy to miss: with a
`BOTTOMLEFT` anchor a band in the `above` slot fills the new space and nothing moves, while
a band `below` sits inside the pinned edge and shoves the frame's own content up by the
band's height. That is exactly what moved the player unit frame's bars 26 units whenever a
cast bar attached below them, and moved them back on detach.

The provider reports how far the frame extends past its own content, top and bottom, and
`MoveableFrame` shifts the offset it hands the anchor strategy so the **content** stays
where the player put it and bands extend outward. The shift depends only on the anchor's
vertical family — `TOP*` pins the top, `BOTTOM*` the bottom, `LEFT`/`RIGHT`/`CENTER` the
middle (which takes half the difference).

Two things this must get right, and each has its own regression test:

- **The compensation is applied on read and removed on write.** `OnDragStop` reads the
  frame's bounding-box anchor from the client, so it converts back before saving. Skip that
  half and the inset is baked in again on every drag — the frame walks one band height per
  drag.
- **Re-anchor on inset change, not on size change.** Moving a band from the `above` slot to
  `below` leaves the total height identical, so a size comparison misses it entirely. The
  publisher compares the inset itself and calls `RefreshAnchor`; re-anchoring on every
  layout pass instead would fight a drag in progress.

The provider is plugin code called on every placement pass, so it runs through `pcall` and a
throwing one degrades to no compensation rather than unwinding into the layout engine.

Positions live in the owning plugin's own settings namespace, so they are profile-aware
for free and a plugin's frames travel with its settings. `/suuui toggle`, `/suuui lock`
and `/suuui unlock` are dispatched by `SettingsWindow`'s slash handler — ToggleUI does
not register its own, because `SettingsWindow` loads later in the `.toc` and would
overwrite it.

**A frame that writes its own state must not react to that write.** `OnDragStop` saves
the position the player just dragged to, and the position watcher would immediately
restore it — harmless while restore is a no-op, and a fight with the player's cursor the
moment it starts clamping or snapping. The save sets a `_saving` flag that its own
watcher checks, so only changes from elsewhere (a profile switch, a reset) move the
frame. Any bidirectional binding needs this; it is not specific to dragging.

`SUUUI_EDIT_MODE_CHANGED` is **deprecated**. It was the public edit-mode event before
edit mode became a watched setting, and ToggleUI still emits it from a watcher so
third-party plugins keep working. New code watches the setting.

### 5d. Snap Grid, Guides & The Properties Panel

Two surfaces sit on top of 5c, both driven entirely by watchers on `_layout` keys so
neither owns state of its own.

`Core/SnapGrid.lua` draws the grid and decides where a dropped frame lands.
`Core/EditPanel.lua` is the properties inspector: a moveable, non-resizable window
listing every registered frame, with X/Y inputs, an anchor dropdown, a lock toggle and
the grid controls. Closing it leaves edit mode, and it always keeps one element selected
— a panel with nothing selected has no controls to offer.

**Settings** (all on `_layout`, declared once in `ToggleUI.lua`):

| Key | Type | Meaning |
|---|---|---|
| `snap_mode` | dropdown | `none` ｜ `grid` ｜ `guides` |
| `show_grid` | toggle | draw the grid overlay while in edit mode |
| `grid_size` | slider | grid step, 4–64 |

**API:**
```lua
SuuUI.SnapGrid:Snap(x, y, frame)   -- dispatches on snap_mode; returns possibly-moved x, y
SuuUI.SnapGrid:FindGuides(frame)   -- { h = {y...}, v = {x...} } — NEAR guides only
SuuUI.SnapGrid:BeginGuides(frame)  -- start the live guide ticker (drag start)
SuuUI.SnapGrid:EndGuides()         -- stop it and clear the lines (drag stop)
SuuUI.EditPanel:Select(frame) / :GetSelected() / :Refresh()
```

Four things here are load-bearing, and each cost an in-game round trip to find:

- **A drawn guide is a promise.** `FindGuides` returns only edges within
  `GUIDE_SNAP_THRESHOLD`, and the snap uses that same constant and the same `_edgesOf`
  helper. Drawing every edge of every frame instead — which is what shipped first —
  puts lines on screen with no magnet behind them, and they read as noise.
- **Guides are recomputed while the drag runs**, on a throttled ticker whose `OnUpdate`
  is unregistered on drag stop. Computing them once at drag start freezes them at the
  position the frame was picked up from, so they describe where it *used to be*.
- **The snap result is quantised with `Pixel.Snap` before it is returned.** The delta
  that lands an edge on a guide is almost always fractional, and `AnchorLayout` snaps
  every coordinate on its way to `SetPoint` — so a fractional return gets re-rounded
  *after* being aimed, landing the frame up to half a step off the line it was aimed at.
- **A one-pixel seam at a stacked edge is a rasterisation blend, not a placement error.**
  Measured in game at `multiplier = 1`, where one unit is exactly one physical pixel: a
  flush snap leaves a one-pixel seam, and nudging by one pixel produces a one-pixel
  *overlap* instead. Those are adjacent integer offsets, so no placement makes the two
  fills read as touching — the boundary row is blended by the rasteriser. `EDGE_PAIRINGS`
  therefore enumerates the pairings, so stacking (our bottom to their top) is an explicit
  candidate, and applies no correction to any of them. Both directions were tried in game.

**A locked frame is locked in the position, not in a separate key.** `locked` lives
inside the stored position table, so it travels with the position on a profile switch,
a copy and a reset, and cannot desync from it. A locked frame refuses the drag, paints
`colorEditOverlayLocked` instead of `colorEditOverlay`, and shows a lock badge.

**The panel is built lazily, on first entry into edit mode.** Constructing it at login
would create components — and fire their animations — during the `PLAYER_LOGIN` pass for
a window the player may never open.

### 6. Theme & Token System (`Core/Theme.lua`)

Flat token table, but organised in **two tiers**. Token names: camelCase with category
prefix. Categories: `color`, `opacity`, `font`, `space`, `size`, `border`, `anim`.

**Tier 1 — primitives.** Named for what they *are*: `colorGray900`, `colorBlue400`.
Neutrals run 950 (darkest) to 100 (lightest). These are the only colours the theme
editor exposes.

**Tier 2 — semantics.** Named for what they are *for*: `colorBg`, `colorBorder`,
`colorDanger`. Every semantic is an alias or a derivation onto tier 1.

**Components reference tier 2 only.** That is what makes a retint a one-line edit:
change `colorBlue400` and every focused border, slider fill, and accent label follows.

Three value forms:

| Form | Example | Resolves to |
|---|---|---|
| literal | `colorGray900 = {0.08, 0.08, 0.10, 1.00}` | itself |
| alias (string) | `colorAccent = "colorBlue400"` | the referenced token, chained up to 8 deep |
| derivation (table) | `colorBg = { ref = "colorGray900", alpha = "opacityPanel" }` | the ref's RGB with the alpha token's value |

Derivations are what keep opacity a single control: panel translucency is the
`opacityPanel` token, not an alpha channel repeated across four colour literals.

```lua
-- Tier 1: primitives
colorGray900   = {0.08, 0.08, 0.10, 1.00}   -- 950 850 800 750 700 600 400 100 also defined
colorBlue400   = {0.25, 0.55, 1.00, 1.00}
colorBlue500   = {0.18, 0.44, 0.90, 1.00}
colorGreen400  = {0.20, 0.80, 0.40, 1.00}
colorGreen500  = {0.22, 0.78, 0.32, 1.00}   -- health's own green (see colorHealth below)
colorRed400    = {0.90, 0.25, 0.25, 1.00}
colorYellow400 = {0.95, 0.80, 0.20, 1.00}
opacityPanel   = 0.95
opacityOverlay = 0.35

-- Tier 2: surfaces
colorBg          = { ref = "colorGray900", alpha = "opacityPanel" }
colorBgAlt       = { ref = "colorGray850", alpha = "opacityPanel" }
colorBgHover     = { ref = "colorGray800", alpha = "opacityPanel" }
colorBgActive    = { ref = "colorGray750", alpha = "opacityPanel" }   -- selected
colorBgPressed   = { ref = "colorGray750", alpha = "opacityPanel" }   -- mouse down
-- The empty part of a frameless bar: a unit frame's health track, a cast bar's. Its own
-- semantic rather than a panel colour, because a bar sits over the game world.
colorBarTrack    = { ref = "colorGray950", alpha = "opacityBarTrack" }
-- Edit mode. The overlay takes the accent hue so "you can move this" reads like every
-- other affordance, and the locked variant takes Warning so "you cannot" reads at a
-- glance. The grid is faint enough to ignore; a guide is brighter because it only
-- appears when a magnet is armed behind it (see 5d).
opacityEditOverlay = 0.20   opacityGrid = 0.15   opacityGuide = 0.40
colorEditOverlay       = { ref = "colorAccent",  alpha = "opacityEditOverlay" }
colorEditOverlayLocked = { ref = "colorWarning", alpha = "opacityEditOverlay" }
colorGrid        = { ref = "colorAccent", alpha = "opacityGrid" }
colorGuide       = { ref = "colorAccent", alpha = "opacityGuide" }
-- The "you cannot stop this" cue: the hairline outline a cast bar draws around itself and
-- its icon while a spell is uninterruptible. A light neutral rather than an intent colour —
-- it describes the spell, not a warning, and it has to stay readable over any fill colour.
colorShield      = "colorGray400"
-- A unit's health when class colouring is off or the class is unknown: an NPC, a totem,
-- the login moment before the class is available. Its own hue rather than a reuse of
-- Success — retinting "Success" to orange should not turn the health bar orange.
colorHealth      = "colorGreen500"
-- The glass plate an action bar draws itself on. THREE opacities rather than one, because
-- the plate's legibility comes from the DIFFERENCE between its ends -- a single opacity
-- makes it a flat panel, which is the look it exists to avoid. WoW has no blur, so
-- "frosted" is unavailable; a translucent vertical gradient plus a lit hairline top edge
-- plus an optional hairline border is what actually reads as glass.
--
-- Its own tokens rather than reusing colorBarTrack: that token is a BAR'S EMPTY TRACK, so
-- sharing would mean retinting a health bar silently retinted every action bar plate.
opacityGlass = 0.80   opacityGlassFade = 0.30   opacityGlassSheen = 0.10
colorGlass       = { ref = "colorGray950", alpha = "opacityGlass" }      -- the DENSE end, at the TOP
colorGlassFade   = { ref = "colorGray950", alpha = "opacityGlassFade" }
-- The only place in the palette where a light neutral and a dark one meet inside one
-- treatment: the sheen is a highlight ON the plate, so it refs the lightest neutral. Kept
-- very low deliberately -- above about 0.15 it stops being an edge and becomes a white line
-- drawn on the plate.
colorGlassSheen  = { ref = "colorGray100", alpha = "opacityGlassSheen" }
-- How faint a StatusBar's SECONDARY ("ghost") fill is, as a MULTIPLE of the main fill's own
-- alpha rather than an absolute -- because the ghost derives from whatever the bar's fill is.
opacityBarGhost  = 0.35

-- Tier 2: intent
colorAccent      = "colorBlue400"
colorAccentHover = "colorBlue500"
colorSuccess     = "colorGreen400"
colorDanger      = "colorRed400"
colorWarning     = "colorYellow400"
-- Experience, and the rested bonus that extends past it. SEPARATE from the accent because in
-- WoW these colours MEAN something: purple is progress and blue is rested, so painting
-- progress in the accent made the bar claim a rested bonus that was not there.
--
-- The magenta primitives behind colorXp are a fuchsia -- near-zero GREEN, red at least as
-- strong as blue. Blue-dominance is what makes a purple read as the WARLOCK class colour,
-- which is exactly what the first attempt looked like.
colorXp          = "colorMagenta400"
-- The rested region is drawn PAST current progress rather than under it, so it can be
-- near-solid without muddying the fill; the alpha marks it as potential rather than earned.
colorXpRested    = { ref = "colorBlue400", alpha = 0.55 }
-- Whether a unit's colour comes from its class or from the Health primitive. A boolean
-- rather than a colour because it is a mode: it selects the SOURCE of a unit's colour,
-- and a flag keeps every colour token a real colour so nothing downstream is handed a
-- value it cannot paint with. Read through Theme:GetUnitColor, never directly.
colorUseClassColors = false   -- Modern: true. Default is the fixed-palette theme.
-- Tier 2: content
colorText         = "colorGray100"
colorTextMuted    = "colorGray400"
colorTextDisabled = "colorGray600"
colorBorder       = "colorGray700"
-- The ring around an ICON's art, brighter than a panel's edge on purpose: a panel border
-- separates a dark surface from the game world, where a near-black hairline reads fine,
-- while an icon border has to separate a tile from spell art that is itself dark at the
-- edges. colorBorder there is invisible -- measured in game before this token existed.
colorBorderIcon   = "colorGray400"
colorBorderFocus  = "colorAccent"

-- Typography
fontSizeSm = 11    fontSizeMd = 13    fontSizeLg = 15    fontSizeXl = 18
fontFamilyMain = "Friz Quadrata TT"   -- a font NAME; GetToken resolves it to a path

-- Spacing, used for both gaps (between items) and padding (container insets)
spaceXxs = 2   spaceXs = 4    spaceSm = 8    spaceMd = 12    spaceLg = 16    spaceXl = 24

-- Sizes. Never hardcode a control height; see Theme:GetControlHeight.
sizeControlSm = 18   -- toggle, swatch          sizeRow       = 28  -- settings rows
sizeControlMd = 22   -- input, option row       sizeNavRow    = 32  -- nav items
sizeControlLg = 24   -- dropdown, buttons       sizeTitleBar  = 26  -- window chrome
sizeIcon      = 16   sizeScrollbar = 8          sizeToggleW   = 36

borderWidth = 1
animFast = 0.12    animMid = 0.22    animSlow = 0.38
-- Bar fill: time for a full sweep. Its own token because bar smoothing reads as
-- physical motion and wants to be slower than a panel transition, and a player who
-- wants bars to snap should not have to speed up every dropdown to get it. 0 disables.
animBarFill  = 0.28   -- Modern: 0.22. Read by StatusBar transitions (ctx:Duration).
-- Press pop: how far a button scales. 1 disables the pop without code changes.
animPopScale = 1.08   -- Modern: 1.06. Read by Presets.ScalePop.
```

Every token has a consumer. A token nothing reads is worse than an absent one: it shows
up in the theme editor as a control that silently does nothing. If you add a token, wire
it; if you remove a consumer, remove the token.

`colorSuccess` / `colorDanger` / `colorWarning` are the intent tokens — use them for
state colouring rather than reaching for `colorGreen400` directly. They reach the screen
through `Button`'s `variant` and `Modal`'s `confirmVariant`:

| Intent | Where it belongs |
|---|---|
| `danger` | the confirm button of a destructive dialog; a failure notice |
| `success` | the confirm button of a create/copy dialog |
| `warning` | a notice for an action that is blocked but expected |

**Intent colour goes on the button that commits the action, not the one that opens the
dialog.** A "Delete" button on a settings page is neutral; the "Delete" button inside the
confirmation dialog is `danger`. Colouring both makes the page shout before the user has
asked for anything.

**The theme editor exposes tier 1 colours only** (`SettingsUI/Controls/ThemeTokens.lua`).
Editing a primitive cascades through every semantic that references it. Exposing the
semantics too would let a user replace an alias with a literal and break that cascade
permanently, so semantics stay `SetUserToken`-only.

Built-in themes are read-only. User themes stored in profile under
`profile.themes[name]` as a partial token override table, stamped with
`_tokenVersion` so renamed keys from older saves can be migrated on read.

**`fontFamilyMain` is a fourth value form: a font name.** It stores a name rather than a
file path so the choice survives a media addon moving its file, and `GetToken` hands
consumers the resolved path — nothing downstream changes. A literal path still passes
through, which is what a hand-edited SavedVariable may hold. `GetTokenRaw` returns the
stored name, which is what the theme editor's dropdown displays.

**`colorUseClassColors` is a fifth value form: a boolean.** It is a mode rather than a
visual value — "colour units by class" selects the SOURCE of a unit's colour, not the
colour itself — and modelling it as a flag keeps every colour token a real colour so nothing
downstream can be handed a value it cannot paint with. It is not read directly: consumers
call `Theme:GetUnitColor(key, unit)`, which resolves the flag against the class and reaction
data in `SuuUI.Game` and always returns a usable `{r,g,b,a}`. The theme editor exposes it as
a toggle next to the Health primitive, since the two form one decision. It is the editor's
first non-colour, non-numeric control.

`GetUnitColor` tries **three** sources in order, and the middle one is why a target frame
needs no colour code of its own:

| Order | Source | Covers |
|---|---|---|
| 1 | the unit's class (`Game:UnitClassColor`) | players only — a hostile enemy player still shows their class |
| 2 | its reaction to the player (`Game:UnitReactionColor`) | a mob, a critter, a quest giver, a totem — everything that is not a player |
| 3 | the named token | class colouring off, or no unit to ask about |

**Order 1 is gated on `UnitIsPlayer`, not on whether the client reports a class.** Asking
`UnitClass` about a creature does not fail — it answers, and it almost always answers
`WARRIOR`, because that is what the overwhelming majority of creatures are internally. So a
chain that treated "has a class" as the test painted every mob, critter and quest giver in
warrior tan and never reached step 2 at all. A neutral Vale Moth rendered brown instead of
yellow, which is how the bug was found. `UnitIsPlayer` is the only question that separates a
mage from a moth.

Reaction sits **inside** the `colorUseClassColors` branch rather than behind a toggle of its
own. It is not a second feature: it is what "colour units by what they are" means for a unit
that has no class, and it is what the client itself does. A separate toggle would be a
control that does nothing whenever the first one is off, and a player who switched class
colouring off asked for the flat palette — mobs included.

**API:**
```lua
SuuUI.Theme:GetToken(key)                       -- resolves aliases, derivations, fonts
SuuUI.Theme:GetTokenRaw(key)                    -- stored value, before resolution
SuuUI.Theme:GetUnitColor(key, unit)             -- class colour or token; always usable
SuuUI.Theme:GetColorCode(key)                   -- a colour token as a |cffRRGGBB escape
SuuUI.Theme:GetFontSize(sizeKey)                -- "sm"|"md"|"lg"|"xl" -> the fontSize* value
SuuUI.Theme:GetControlHeight(sizeKey, fontKey)  -- size token floored by font metrics
SuuUI.Theme:SetActive(name)                     -- fires SUUUI_THEME_CHANGED
SuuUI.Theme:GetActive()
SuuUI.Theme:List()
SuuUI.Theme:IsBuiltin(name)
SuuUI.Theme:CreateUserTheme(name, baseTheme)
SuuUI.Theme:DeleteUserTheme(name)               -- error on built-ins
SuuUI.Theme:ResetUserTheme(name)
SuuUI.Theme:SetUserToken(themeName, key, value)
SuuUI.Theme:ApplyToFrame(frame)                 -- bg+border via SuuUI.Backdrop.Apply
```

`GetControlHeight` returns `max(sizeToken, fontSize + spaceXs * 2)`. Use it for anything
that holds text, since font sizes are user-editable and a control pinned to a literal
height clips once the font outgrows it. Read the size token directly for elements with no
text of their own (toggles, swatches, scrollbars).

Components listen for `SUUUI_THEME_CHANGED` and call `ApplyTheme()` internally.

### 6b. Font Registry (`Core/Fonts.lua`)

Backs the `fontFamilyMain` token. **There is no filesystem API in WoW** — a font list has
to be assembled from what the client will admit to:

| Source | How |
|---|---|
| curated client faces | Friz Quadrata TT, Arial Narrow, Morpheus, Skurri |
| locale faces | `STANDARD_TEXT_FONT`, `UNIT_NAME_FONT`, `DAMAGE_TEXT_FONT`, `NAMEPLATE_FONT` |
| everything the client loaded | `GetFonts()` returns font *object* names; the path comes off each object via `GetFont()` |
| media addons | `LibSharedMedia-3.0` if the player has it — read only, never a dependency |
| plugins and users | `Fonts:Register(name, path)` |

Every candidate is validated by probing `SetFont` through `TextMetrics.CanLoadFont`, since
applying a font is the only way to test it. Entries are deduplicated by path across slash
style and case, because LSM registers with backslashes and this addon writes forward ones.

**Two traps live here, and both have already cost a broken login:**

- **`SetFont` raises on an invalid asset** — `Invalid font asset (X): file not found` —
  rather than returning false. Every probe is wrapped in `pcall`, and any face that comes
  from a caller (a `Text` `font` prop, a `Dropdown` option's `font`) is resolved through
  `Fonts:Path` before it reaches `SetFont`. An unguarded probe unwound out of the
  `PLAYER_LOGIN` handler and cost plugin init and `SUUUI_READY`.
- **Not every client font global holds a path.** `NAMEPLATE_FONT` is `"GameFontWhite"`, a
  font *object* name. Candidates are shape-checked for a font file extension first, and a
  name that isn't one is resolved via the object's own `GetFont()`.

The scan itself is wrapped too, so the worst case is a short font list rather than a failed
login. The simulated client raises the same way, and ships `NAMEPLATE_FONT` in its real
object-name shape, so the whole suite exercises both traps on every setup.

Names match LSM's for the same files, deliberately: a theme saved while SharedMedia was
installed has to keep resolving once it is gone, and the reverse.

**API:**
```lua
SuuUI.Fonts:List()               -- { { name, path, source } } sorted by name
SuuUI.Fonts:Options()            -- { { value = name, label = name } } for a Dropdown
SuuUI.Fonts:Path(nameOrPath)     -- always returns a loadable path; falls back if not
SuuUI.Fonts:Name(pathOrName)     -- display name, or nil
SuuUI.Fonts:Has(name)
SuuUI.Fonts:Validate(path)
SuuUI.Fonts:Register(name, path, source)
SuuUI.Fonts:Add(path)            -- register by path alone, named after the file
SuuUI.Fonts:Refresh()            -- rescan; emits SUUUI_FONTS_CHANGED if the set moved
SuuUI.Fonts.FALLBACK             -- "Fonts/FRIZQT__.TTF"
```

`Add` backs the theme editor's "Add" button: a font dropped into an addon folder that no
media addon registered is invisible to every discovery source, so taking the path directly
is the only route to it. It returns nil for a file the client cannot load, which is the
caller's cue to say so through a `Notice` rather than storing a broken path.

`Refresh()` runs on `PLAYER_LOGIN` because a media addon can load after SuuUI. `Theme`
listens for `SUUUI_FONTS_CHANGED` and re-emits `SUUUI_THEME_CHANGED` only when the
resolved path actually moved, so a font that was missing at boot appears without a reload.

### 6c. Pixel Grid (`Core/Pixel.lua`)

The engine lays the UI out in **units, not pixels**. The drawing area is always 768 units
tall, so one unit spans `physicalHeight / 768` pixels — 1.40625 at 1080p on the default
scale. A 1-unit border therefore straddles a pixel boundary and the rasteriser renders it
as a grey smear rather than a line. That is the whole "why" behind this module.

Fixing it takes two things, and one without the other is useless:

1. **A grid.** The scale on `SuuUI_UIRoot` is set so one unit is an exact whole number of
   pixels. `SetIgnoreParentScale` detaches it from the player's UI Scale slider; where the
   client lacks that, the parent chain is divided back out so both paths agree.
2. **Coordinates on it.** A perfect grid buys nothing if the layout hands `SetPoint` 13.7.
   Every value the four strategies pass to `SetPoint` / `SetSize` / `SetWidth` goes through
   `Pixel.Snap`.

**Why the root and not `UIParent`.** Scaling `UIParent` moves every Blizzard frame and
every other addon's anchors. Scaling our own root is reversible, invisible to everyone
else, and sidesteps the 0.64 floor the `uiScale` CVar enforces (which is why the CVar
route silently fails above 1200px vertical).

**Why an integer multiplier.** At 1x, a 4K panel yields 2160 units of vertical space and a
520-unit window occupies a quarter of the screen. `multiplier` picks a whole-number
multiple of the base scale — chosen from the physical height, aiming for roughly 1000
units — so a unit is still an exact whole number of pixels and the UI stays exactly as
crisp while being physically usable. A *fractional* multiplier would put units back
between pixels, which is the problem this module exists to remove, so `SetMultiplier`
rounds.

**`grid` vs `mult`.** `mult` is one physical pixel expressed in units. `grid` is the snap
quantum. With scaling active they differ on purpose: units are whole pixels, so `grid` is
1 and every measurement stays integral. With scaling **off** — user preference, or a
custom scale — units are off-grid by definition, so `grid` becomes `mult` and snapping
targets real pixels instead. That indirection is why a border is exactly one pixel either
way instead of 1.4.

**API:**
```lua
SuuUI.Pixel.Snap(v)              -- nearest grid multiple
SuuUI.Pixel.Floor(v)             -- for a size that must not overflow its space
SuuUI.Pixel.Ceil(v)              -- for a size that must not clip its content
SuuUI.Pixel.Line(v)              -- line thickness, floored at one pixel so it never vanishes
SuuUI.Pixel.CursorIn(frame)      -- cursor in that frame's coordinate space
SuuUI.Pixel.Convert(v, from, to) -- a length in `from`'s units, expressed in `to`'s
SuuUI.Pixel:Refresh()            -- recompute; emits SUUUI_PIXEL_GRID_CHANGED if it moved
SuuUI.Pixel:Attach(frame)        -- drive a frame's scale (UIRoot attaches the root)
SuuUI.Pixel:SetEnabled(bool)     -- scaling on/off; snapping stays on either way
SuuUI.Pixel:SetMultiplier(n)     -- override; nil returns to automatic
SuuUI.Pixel.grid / .mult / .scale / .multiplier / .physicalHeight
```

`Snap` is **idempotent**, which is load-bearing: `Container:Layout` re-runs its strategy
after hugging, and a non-idempotent rounding would drift on every pass and never settle.

**`Floor` and `Ceil` tolerate a hair of round-trip noise, and that tolerance is
load-bearing.** Geometry does not come back out of the client the way it went in: the root's
scale is derived from the physical height and is rarely a binary-exact fraction
(768/1440 = 8/15), so `SetSize(w, 22)` reads back as `21.99996948242`. `Snap` absorbs that
by rounding, but `Floor` and `Ceil` would turn one or two ULPs into a **whole unit** of
error — `Floor(21.99996948242)` is 21, so every stretched child comes out a pixel short of
the box it was told to fill. That shipped as a one-pixel gap under a detached resource bar
that survived four rounds of position fixes, because the bug was in the child's *size* and
every attempted fix moved the *frame*. `GRID_EPS` (0.01) sits orders of magnitude above the
observed noise (3e-5) and far below any fraction a caller could mean.

The diagnostic lesson generalises: when two frames look misaligned, measure the **child**
rects, not just the moveable wrappers. A wrapper can be exactly flush while the bar inside
it is a unit short, and the two look identical on screen.

**Two coordinate spaces, and mixing them is the bug this module invites.** A widget
reports its rect in its own *region units* — screen space divided by its effective scale —
while `GetCursorPosition()` and `GetScreenHeight()` are in screen space and `UIParent`'s
units respectively. They all coincide until something carries a scale, and the pixel grid
puts one on the root. After that, anything under the root measures the screen as 1080 units
tall while `GetScreenHeight()` still says 768.

That failure mode is distinctive: **horizontal stays correct and vertical breaks.** An `x`
offset needs no screen constant, so it never picks up the wrong one; a `y` offset measured
downward from the screen top does. Two places have already hit it:

- `CursorIn` exists because five call sites divided the cursor by
  `UIParent:GetEffectiveScale()`, which made a slider track ~40% too far.
- `Window`'s saved position measures against the root's own rect, not `GetScreenHeight()`.
  Deriving `y` from the screen constant dropped windows 312 units too high at 1080p.

The rule: **measure between two frames that share a space, or convert explicitly.** Never
combine a widget's own numbers with a screen-space constant.

**`Convert` is the second half of that rule, and it exists for the BOUNDARY.** Everything
inside the addon shares the root's space and never needs it. What needs it is the one place a
length of ours is handed to a frame that is not ours: the data bar publishes its height in
root units, and moving Blizzard's `MinimapCluster` down by that number puts it into a frame
anchored to `UIParent`, which measures in different units the moment the pixel grid puts a
scale on the root. `Convert(v, from, to)` multiplies by `from`'s effective scale and divides
by `to`'s, so the same *physical* length comes out in the destination's units:

```lua
-- Our bar's height, expressed in the units of a frame anchored to UIParent
local h = SuuUI.DataBar:GetOccupiedHeight()
local y = SuuUI.Pixel.Convert(h, SuuUI.UIRoot:GetRoot(), MinimapCluster)
```

Skipping it produces the signature failure above rather than an obvious one: the `x` offset
needs no scale so it stays correct, and only the vertical is wrong — by a ratio that is 1 at
the default multiplier, so it looks perfect on the machine it was written on. Either scale
reading as absent or non-positive is treated as 1, so a call during construction degrades to
the identity rather than raising.

`Refresh` is driven by `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED` and `CVAR_UPDATE`.
`Theme` listens for `SUUUI_PIXEL_GRID_CHANGED` and re-emits `SUUUI_THEME_CHANGED`, since
a moved grid changes what every token-derived size snaps to — the same restyle a theme
change needs. Same pattern as `SUUUI_FONTS_CHANGED`.

### 6d. Game Facts (`Core/Game.lua`)

Colours the client decides, not the theme. A power type's colour, a class colour, a
reaction colour and a spell school's colour are what the game says those things **are** —
"frost is cyan", "mages are light blue" and "a mob that wants you dead is red" are as fixed
as each other — so they are constants here rather than theme tokens. Putting them in the
theme would fill the editor with controls that are wrong to touch and let a player retint
frost to green, which would make the UI lie about the game.

They live in Core rather than in whichever plugin paints them first, because a resource bar,
a cast bar, a nameplate and a debuff border all describe the same facts, and two copies of a
fact drift. This is the third home in the token-or-setting split: design language is a
**token**, a widget's own dimensions are a **plugin setting**, and a fact about the client is
here.

Note the split this draws with the theme: whether a health bar is class-coloured at all is
a look decision and lives in the theme as `colorUseClassColors`; WHICH colour a mage gets
is a fact and lives here. `Theme:GetUnitColor` is the one place the two meet.

**There is no API mapping a spell to its school in this client.** Neither `GetSpellInfo` nor
`UnitCastingInfo` reports one, so the combat log is the only source, and the school arrives
*after* a cast has already started the first time a spell is seen. The cache therefore lives
here too: whoever is already reading the log calls `LearnFromCombatLog`, and everything else
reads back out of `SchoolOf`.

**API:**
```lua
SuuUI.Game:PowerColor(powerType)      -- falls back to mana for an unknown type
SuuUI.Game:ClassColor(classFile)      -- {r,g,b,a} or nil; prefers CUSTOM_CLASS_COLORS
SuuUI.Game:UnitClassColor(unit)       -- a PLAYER's class colour; nil for a creature
SuuUI.Game.REACTION                   -- { HOSTILE = 2, NEUTRAL = 4, FRIENDLY = 5 }
SuuUI.Game:ReactionColor(reaction)    -- the client's 1..8 standing -> {r,g,b,a}, or nil
SuuUI.Game:UnitReactionColor(unit)    -- ReactionColor(UnitReaction(unit, "player")), or nil
SuuUI.Game.SCHOOL                     -- PHYSICAL HOLY FIRE NATURE FROST SHADOW ARCANE
SuuUI.Game:SchoolColor(mask)          -- nil when the mask says nothing — callers fall back
SuuUI.Game:SchoolOf(spellId)          -- cached mask, or nil
SuuUI.Game:LearnSchool(spellId, mask) -- returns whether it changed what we knew
SuuUI.Game:LearnFromCombatLog()       -- reads the line being dispatched; returns spellId, mask
SuuUI.Game:DebuffTypeColor(dispel)    -- "Magic"｜"Curse"｜"Disease"｜"Poison" -> {r,g,b,a}; nil otherwise
SuuUI.Game:UntypedDebuffColor()       -- the client's own `none` row: red. Never nil
SuuUI.Game:ItemQualityColor(quality)  -- 0..7 -> {r,g,b,a}; nil for a quality this client does not name
```

**Reaction colours are the answer for every unit that has no class** — a mob, a critter, a
quest giver, a totem. `UnitReaction` reports a full reputation standing (1 hated to 8
exalted) and `ReactionColor` collapses it onto **three** bands, because a health bar is
answering "can this thing hurt me" and the client's own colour table makes the same
collapse: keeping eight would give the player five shades that all mean "friendly". Hostile
takes everything at or below unfriendly, since that is the set that will fight you.

"Has no class" here means **is not a player**, and the difference is not academic: the client
answers `UnitClass` for a creature too. See the gate on order 1 in `GetUnitColor` above.

`REACTION` names the `FACTION_BAR_COLORS` row that carries each band, which is what makes
the live global a drop-in source rather than a coincidence — it is preferred over the
internal copy exactly as `RAID_CLASS_COLORS` is, so SuuUI agrees with the rest of the
player's UI including an addon that retints it. The converted array is cached per band and
validated against the source, so a runtime retint is picked up without allocating per call.

**The unit goes FIRST in `UnitReaction`.** The client reports the first unit's reaction
towards the second, and it is not symmetric in general, so `UnitReaction(unit, "player")` is
the question a unit frame paints: "what is this thing to me". Swapping the arguments reads
the player's own standing and answers nil for every unit — the simulated client models that
asymmetry deliberately rather than hiding it.

Class colours prefer the client's `CUSTOM_CLASS_COLORS` then `RAID_CLASS_COLORS` over the
internal copy, so SuuUI agrees with the rest of the player's UI (including a class-colour
addon that retints them at runtime). The copy covers the login moment before either global
exists. The converted `{r,g,b,a}` array is cached per class and the cache is validated
against the live source, so a palette swap is picked up without allocating per call.

`ClassColor` and `UnitClassColor` return nil for an unknown class — an NPC, a totem, a pet
— exactly like `SchoolColor`. nil is a real answer; the caller's own fallback is the right
response. `UnitClassColor` decides "unknown" by `UnitIsPlayer` rather than by what
`UnitClass` says, so a creature reads as nil however confidently the client calls it a
warrior.

The seven pure schools carry Blizzard's own values deliberately — the point of school
colouring is that it matches what the player already reads everywhere else in the game, so
they are copied rather than chosen. A multi-school mask that the client does not name
outright is **blended** from its parts and memoised, because picking the lowest bit would
paint a frost-fire spell as plain fire and hide exactly the distinction school colouring
exists to show.

Two details are load-bearing and neither is obvious:

- **`SchoolColor` returns nil rather than a stand-in.** A mask of 0, or the absent mask of a
  spell nothing has reported yet, means "not known" — and the caller's own fallback is the
  right response. Inventing a colour for "unknown" gives the player a cue that means nothing.
- **`LearnFromCombatLog` reports a school it already knew.** Two cast bars read the same
  line; returning only on a fresh learn would mean whichever handler ran second never heard
  about its own spell.

`SPELL_ABSORBED` is skipped: after a swing it carries the absorbing caster's GUID where every
other line carries a spell id, so reading it positionally caches nonsense against a nonsense
key. Bit tests are arithmetic rather than `bit.band`, so the module behaves identically under
the client's Lua and the test runner's.

**Dispel colours are a fact for the same reason school colours are.** A debuff border answers
"what removes this", and the player already knows what that colour means from their default
raid frames and from every other addon that shows debuffs — so the four values are copied from
the client rather than chosen, and `DebuffTypeColor` is preferred over the internal table
exactly as `RAID_CLASS_COLORS` is, cache validated against the source so a retint is picked up
without allocating per call. A theme that could decide Curse is blue would make the border a
decoration instead of information. Whether a border is type-coloured **at all** is still a look
decision, and it is one the caller makes: `AuraBand` passes nil for buffs.

That nil is not an oversight, and it cost a debugging round to find out why it has to be there:
**the client reports a `dispelType` for HELPFUL auras too.** Righteous Fury comes back as
`"Magic"`. Colouring a buff's border by it would ring half a paladin's buffs in blue while
meaning nothing — a dispel type answers "what removes this", which is only a thing you want to
know about something you want removed. So the type is read for debuffs and deliberately
discarded for buffs.

`DebuffTypeColor` returns nil for nil, `""`, `"none"` and anything this client does not name,
which is the same contract as `SchoolColor` and `ClassColor`: the caller's own default border
is the right response, and inventing a colour for "unknown" gives the player a cue that means
nothing. Note the client's own table *does* carry a `none` row — reading it would paint every
untyped debuff red — so the guard is checked before the lookup, not after.

**`UntypedDebuffColor` is that `none` row, exposed on purpose and separately.** Red for
"nothing removes this" is a convention the player already reads from their default UI, and a
debuff display always has something to paint — so unlike `DebuffTypeColor` this never returns
nil. It stays a second accessor rather than a fifth row because the two questions differ: a
buff with no dispel type must not go red, and neither must a cast bar, so only a caller that
knows it is describing a debuff may reach for it.

It is also not the rare case. **Most debuffs in this game carry no dispel type at all** —
every physical one, plus plenty of spell DoTs (a mage's Fireball among them, measured in
game) — so red is the common border and the four dispel colours are the exception.

**A buff's border answers a different question, and so reads a different field.** It shows
what a purge or a spellsteal would take, not what kind of magic something is, and the client
answers that directly with `isStealable` — computed against the player's own class and that
unit. Colouring buffs by dispel type instead would ring every blessing a paladin carries in
blue while telling them nothing they can act on, which is what `isStealable` avoids: it is
false across your own bar and true exactly where the purge would land. `Plugins/UnitFrames/AuraBand.lua`
states both rules as a `border` function per kind rather than a shared flag, because the two
bands genuinely disagree about what the pixel means.

### 7. Frame Pool (`Core/Pool.lua`)

Typed pools keyed by string ID. Plugins prefix their IDs: `"minimap.buffIcon"`.

**API:**
```lua
SuuUI.Pool:Register(typeId, createFn)   -- register factory (called when pool empty)
SuuUI.Pool:Acquire(typeId, parent)      -- get frame (pool or new), shows it
SuuUI.Pool:Release(typeId, frame)       -- return to pool, hides and resets frame
SuuUI.Pool:ReleaseAll(typeId)           -- return all active frames of type
```

### 8. UI Root & Layer System (`Core/UIRoot.lua`)

The single fullscreen frame that parents every SuuUI element. It is the backbone of
z-order, the home of the pixel scale, and the only file in the addon that calls
`SetFrameStrata` or `SetFrameLevel`. See `UI_ROOT_ARCHITECTURE.md` for the design
rationale, container hierarchy diagram, and layout rules.

**Invariants:**

- `SetFrameStrata` / `SetFrameLevel` appear ONLY in this file. Every other module
  names a layer and lets UIRoot translate.
- Placement never goes to `UIParent`. The root carries the addon's own scale
  (via `Pixel:Attach`), so anchoring to `UIParent` would put a frame into the wrong
  coordinate space and bypass the pixel grid.

**The five-rung ladder:**

| Layer | Strata | Purpose |
|-------|--------|---------|
| `background` | LOW | Background elements (rarely used) |
| `normal` | MEDIUM | Plugin content — unit frames, bars. The root's own strata; children inherit it without asking |
| `window` | HIGH | Windows the player opened (settings, etc.) |
| `dialog` | DIALOG | Modals/popups opened *from* a window |
| `tooltip` | TOOLTIP | Tooltips and dropdown panels |

`window` sits between `normal` and `dialog` because a window is chrome the player opened
to configure the unit frames it must cover. Frame level alone cannot guarantee it: a plugin
frame parented to the root container is nested one level deeper than a window on the same
strata, so it outranks the window in the level tie-break and draws over it — that is the
exact bug that put the player frame on top of the settings window.

**API:**
```lua
SuuUI.UIRoot:Init()                              -- creates root frame + container; once at ADDON_LOADED
SuuUI.UIRoot:SetLayer(element, layer)            -- z-order only, no placement; usable before Init()
SuuUI.UIRoot:GetLayer(element)                   -- returns layer name or nil
SuuUI.UIRoot:GetLayerStrata(layer)               -- layer → strata string; usable before Init()
SuuUI.UIRoot:RaiseAbove(element, host, steps?)   -- same rung as host, higher level (default steps=1)
SuuUI.UIRoot:AddElement(element, layer, anchorDesc) -- z-order + placement via root container
SuuUI.UIRoot:RemoveElement(element)              -- remove from layer tracking + container
SuuUI.UIRoot:UpdateElementAnchor(element, anchorDesc) -- reposition in place, triggers Layout()
SuuUI.UIRoot:GetRoot()                           -- the raw root frame
SuuUI.UIRoot:GetRootContainer()                  -- the anchor-layout container
SuuUI.UIRoot:GetLayerElements(layer)             -- all elements in a layer (array)
```

`AddElement` overwrites any strata the element set for itself — callers that want a
higher rung ask for a higher layer, not a raw strata. `SetLayer` is the z-order-only
path for frames the root does not position (draggable plugin frames, modals filling
their parent, dropdown panels anchored to their field).

### 9. Reload Guard (`Core/ReloadGuard.lua`)

Generic utility for settings that require a UI reload to take effect. When a guarded
setting changes, the value is reverted immediately and a confirmation modal appears;
on confirm the new value is re-applied and `ReloadUI()` fires.

**API:**
```lua
SuuUI.ReloadGuard:Register(pluginId, key, opts)  -- opts: { title, message, confirmText, cancelText }
SuuUI.ReloadGuard:IsGuarded(pluginId, key)       -- returns bool
SuuUI.ReloadGuard:Unregister(pluginId, key)      -- removes the guard
```

The guard intercepts `SUUUI_SETTING_CHANGED` for registered keys. A `_blocked` flag
prevents recursion when the guard itself writes back the reverted or confirmed value.

---

## Layout Engine

### Window (`Layout/Window.lua`)

Top-level draggable, optionally resizable frame. Position saved per-character
in `SuuUIConfig`. Registered windows appear in a window-manager list.

```lua
local win = SuuUI.Layout:CreateWindow({
  id        = "myWindow",
  title     = "My Window",
  w=800, h=560, minW=400, minH=300,
  resizable = true,
})
win:Show() / win:Hide() / win:Toggle()
win:SetTitle(str)
win:GetContentFrame()   -- inner frame, attach children here
win:GetContentSize()    -- usable content width, height (use instead of reaching through GetContentFrame())
win:SavePosition()      -- called automatically on drag stop
```

`minW` / `minH` / `maxW` / `maxH` are handed to the client via `SetResizeBounds`, so a
drag stops dead at the limit. Never clamp after the fact in `OnMouseUp` — the window
overshoots and visibly snaps back. The initial `w`/`h` are clamped into the bounds too.

### Container (`Layout/Container.lua`)

Layout unit with a strategy. Recalculates child positions on `Layout()`.
Supports flexible sizing via layout properties.

```lua
local c = SuuUI.Layout:CreateContainer({
  parent  = frame,
  layout  = "flow",   -- "flow" | "stack" | "grid" | "anchor"
  dir     = "vertical",
  gap     = 8,
  align   = "center", -- default cross-axis alignment for children
  fill    = true,     -- anchor to all sides of parent, track parent resizes
  padding = {top=8, right=8, bottom=8, left=8},
  wrap    = true,     -- flow, horizontal only: break onto a new line on overflow
  lineGap = 2,        -- space between wrapped lines; omit to track gap
  lineOrder = "reverse", -- wrapped lines stack bottom-up (first line at the bottom)
})

-- Add child with flexible sizing. Accepts a frame, component handle, or container.
c:Add(child, { width = "fill", height = 32 })  -- fill width, fixed height
c:Add(child, { width = 200 })                  -- fixed width, natural height
c:Add(child, { align = "center" })             -- per-child cross-axis override
c:Add(child)                                   -- natural dimensions

c:Remove(child)        -- drops only this container's own signal connection
c:Clear()              -- removes and hides every child
c:Layout()             -- auto-called on Add/Remove/resize
c:SetSize(w, h)
c:GetContentSize()     -- returns computed w, h of all children
c:SetChildProps(child, layoutProps)       -- update a child's layout props and re-layout
c:SetChildFraction(child, axis, fraction) -- axis = "width"|"height"; fraction 0..1
c:SetLineOrder(order) / c:GetLineOrder()  -- wrapping flow: "reverse" for bottom-up, nil for top-down
c:GetChildren()
c:Destroy()            -- destroys children, drops all connections
```

Containers are frame-like: `GetFrame` `GetWidth` `GetHeight` `SetWidth` `SetHeight`
`SetPoint` `ClearAllPoints` `Show` `Hide` `IsShown`. That is what lets them nest.
A container emits `SIZE_CHANGED` whenever its computed size changes.

**Layout Properties:**
- `width = "fill"` — child takes available horizontal space
- `width = number` — fixed width in pixels
- `height = "fill"` — child takes available vertical space (flow layouts only)
- `height = number` — fixed height in pixels
- `align = "start"|"center"|"end"|"stretch"` — cross-axis alignment
- Omit property to use child's natural size

### Layout Strategies

**These four files are the only place in the addon that calls `SetPoint`.** That is also
what makes them the only place that needs to snap to the pixel grid: every coordinate
reaching `SetPoint` / `SetSize` passes through `SuuUI.Pixel.Snap` here, so components and
plugins get crisp geometry without doing anything. See `Core/Pixel.lua` above.

Sizes use `Floor` where overflowing the parent would be worse than being a pixel short
(content boxes, stretched children) and `Ceil` where clipping content would be worse
(hugging containers, text heights).

- **FlowLayout** (`Layout/FlowLayout.lua`): horizontal or vertical flow with flexible sizing.
  - `width="fill"` / `height="fill"` distribute remaining main-axis space
  - `width="auto"` — hugs the child's own content width, re-measured every pass via
    `NaturalWidth`
  - Fill shares are floored onto the grid and the **remainder is handed out one pixel at
    a time** to the leading children. Flooring an equal share loses up to `fillCount - 1`
    pixels, which shows up as the last child in a filled row stopping short of the edge.
  - `align` gives cross-axis placement (`start`/`center`/`end`/`stretch`)
  - Respects padding on all 4 sides
  - **Hidden children are skipped**: a child whose `IsShown()` is false consumes no space
    and no gap
  - Font string children are measured with `GetStringHeight()` after their width is
    assigned, so text re-flows when a `fontSize*` token changes. Omit `height` on
    text children; a fixed height pins them to the old font's metrics.
  - `wrap = true` (**horizontal only** — the strategy checks `dir` before the flag) breaks
    onto a new line when the next child would overflow the content width, with `lineGap`
    between lines and `lineOrder = "reverse"` stacking them bottom-up. Line heights are
    settled in a first pass before anything is positioned, because cross-axis `align`
    resolves against each **line's** height rather than the container's — centring against
    the container would drift a short first line's children toward the middle of the whole
    box. `"fill"` degrades to natural size in a wrapping row: there is no fixed line end to
    distribute leftover space against. The container's hugging height comes from the same
    pass, cached in `_wrapContentH`, so `GetContentSize` reports what was laid out rather
    than re-deriving it and disagreeing.
- **GridLayout** (`Layout/GridLayout.lua`): fixed columns, equal cells.
  - Column width derived from container width, padding, and gap
  - Widths are computed once for the whole grid, so a column is the same width in every
    row, and the flooring remainder is spread across the leftmost columns so the row still
    reaches the right edge
  - **Hidden children are skipped** rather than holding an empty cell
- **StackLayout** (`Layout/StackLayout.lua`): overlays children on the container box.
  - `inset` (number or per-edge table), `align`, `valign`, explicit `width`/`height`
  - `widthFraction` / `heightFraction` (0..1) — size as a share of the inner box on that
    axis, recomputed every pass. Overrides `width`/`height` and stretch on the same axis;
    placement still follows `align`/`valign` (defaulting to `"start"`). Clamped, floored
    to the pixel grid. This is how a progress fill states its percentage without touching
    a point.
  - Replaces `SetAllPoints`, centred labels, edge-spanning text, and inset icons
  - This is what components use internally
  - Hidden children are still laid out (unlike flow/grid) — hiding and resizing a child
    before showing it again is a valid pattern here (a progress fill at 0% is exactly that)
  - Font string children on a non-stretched axis are measured with
    `TextMetrics.Measure`, not from their rect, so they track the `fontSize*` tokens.
    Call `box:Layout()` after changing a font string's font — a token-sized element
    does not resize, so nothing else re-measures it and the client clips the glyphs.
- **AnchorLayout** (`Layout/AnchorLayout.lua`): children carry anchor descriptors.
  - For computed positions: slider fills and thumbs, scrollbar thumbs, floating panels
  - Move a child with `container:SetChildAnchor(child, desc)`
  - `relativeTo` may be a frame, a component handle, `"parent"`, or `nil`

### Host containers

`CreateContainer{ host = existingFrame }` adopts a frame as its layout box instead of
creating one. Components use this so internal layout costs no extra frames and needs no
`SetPoint`. Adopting chains any existing `OnSizeChanged` rather than replacing it.

**Register a frame's own resize script before adopting it.** The container chains onto
whatever is already there, so ordering decides who survives — setting the script after
the container adopts the frame replaces the container's re-layout hook and breaks
resizing silently.

### Components must react to being resized

A parent layout resizes a child's **frame** directly; it never calls the handle's
`SetSize`. So any component whose internals depend on its own width or height must hook
its frame's `OnSizeChanged` (registered before its host container, per above), recompute,
and emit `SIZE_CHANGED`:

```lua
local handle
f:SetScript("OnSizeChanged", function(_, w, h)
    if not (handle and handle._box) then return end   -- guard during construction
    handle:_render()
    S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
end)
```

`SetSize` on the handle should then just set the frame size and let the hook do the work,
so both paths behave identically. `ScrollFrame`, `Slider`, and `Toggle` all rely on this.
Emitting only from `SetSize` is the trap: consumers listening for `SIZE_CHANGED` never
hear about layout-driven resizes and keep stale widths.

Position that is animated should also be applied immediately when the change is a resize
rather than a value change — otherwise the element sits at a stale offset until the
animation ticks. `Toggle:_render(snap)` shows the pattern.

### Container sizing is always explicit

Containers never rely on anchor-derived geometry. WoW does not lay out frames that have
never been displayed, so an anchor-only container inside a hidden window reports width 0
and collapses its children. `fill = true` mirrors the parent's size and tracks its
resizes; containers also re-layout on `OnShow`.

### Shared floating host

`SuuUI.Layout:GetFloatingHost()` returns the single anchor container for transient
screen-level panels (dropdown panels, tooltips, popups). Use it rather than creating a
per-panel screen-level container, which would accumulate resize handlers on `UIParent`
as pages rebuild. Remove your panel on teardown; never destroy the host.

### Animating position

The animator's `x`/`y` properties drive an anchor descriptor through
`container:SetChildAnchor`, so even motion goes through the engine:

```lua
SuuUI.Anim:New({
  container = knobBox, target = knob, anchor = knobAnchor,
  property  = "x", from = 3, to = 20, duration = 0.1, easing = "easeOut",
}):Play()
```

`container` and `anchor` are required for `x`/`y`; there is no `SetPoint` fallback.

### Extending the Layout System

**When you need layout functionality that doesn't exist:**

1. **Identify the gap** — what specific layout behavior is missing?
   - Examples: center alignment, wrapping, percentage widths, min/max constraints
   
2. **Design generically** — think about how to make it reusable:
   ```lua
   -- BAD: Plugin-specific hack
   if self._isNavItem then
     child:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
   end
   
   -- GOOD: Generic alignment support
   container:Add(child, { 
     width = "fill",
     align = "stretch"  -- new generic property
   })
   ```

3. **Discuss the API** — before implementing:
   - What property names make sense?
   - Which layouts should support it?
   - Are there edge cases or interactions with existing features?

4. **Implement in the layout strategy** — extend `FlowLayout.lua`, `GridLayout.lua`, etc.
   - Add property handling in the `Apply()` function
   - Update documentation in this file
   - Update plugin authoring guide with examples

5. **Never bypass the system** — manual positioning creates:
   - Inconsistent behavior across plugins
   - Code that doesn't respond to theme changes
   - Hard-to-maintain spaghetti SetPoint chains
   - Broken layouts when container resizes

**Current known limitations to discuss:**
- No wrapping in flow layouts
- No percentage-based sizing (`width = "50%"`)
- No min/max size constraints
- No margin (distinct from container padding)
- No z-index/layer control for overlapping children (use UIRoot layers)

Resolved: cross-axis `align` (`start`/`center`/`end`/`stretch`) on containers and
children; container `fill` for parent-tracking; nested containers as first-class children.

---

## Animation System

### Tween (`Animation/Tween.lua`)

Pure stateless functions. `Tween.Ease(t, easingType)` where `t` is 0–1.

Types: `linear`, `easeIn`, `easeOut`, `easeInOut`, `easeOutBack`, `spring`

`easeOutBack` overshoots past the target then settles back. `spring` is an alias for it —
the name predates this addon — so new code reaches for `easeOutBack` and old code keeps
working. A real spring would be a damped oscillator with a settle time rather than a fixed
duration, which this is not.

`Tween.Has(name)` returns whether an easing name is registered. Unknown names fall back to
linear inside `Ease` rather than erroring, because the function runs inside the animation
tick and throwing there would take the client's frame with it.

### Animator (`Animation/Animator.lua`)

Runs via a single shared `OnUpdate` frame (not AnimationGroups).
All active animations share one update tick — minimal overhead.

```lua
-- Single animation
local anim = SuuUI.Anim:New({
  target   = frame,
  property = "alpha",   -- "alpha"|"width"|"height"|"scale"|"x"|"y"|"value"
  from     = 0, to = 1,
  duration = 0.25,
  easing   = "easeOut",
  onDone   = function() end,
})

-- Parallel (simultaneous) — returns a group handle
local group = SuuUI.Anim:Parallel({anim1, anim2})

-- Sequence (one after another) — returns a group handle
local group = SuuUI.Anim:Sequence({anim1, anim2, anim3})

anim:Play()
anim:Stop()
anim:Reverse()
anim:IsPlaying()

group:Play()        -- restarts the group
group:Stop()        -- stops every animation in the group
group:IsPlaying()   -- true while any member is still running
```

**The `value` property** animates an arbitrary scalar without a frame. Instead of a
setter on `target`, it calls an `apply` callback:

```lua
SuuUI.Anim:New({
  target   = owner,         -- used only for identity (pre-emption, CancelAll)
  property = "value",
  apply    = function(v) ctx:Set(v) end,   -- the single write path
  from     = 0, to = 1,
  duration = 0.28,
  easing   = "easeOut",
})
```

`value` is what the transition registry uses under the hood: the animated quantity is a
fraction, not a pixel width, so the layout engine stays the only thing computing geometry.

**One animation per (target, property).** Starting a new animation pre-empts any other
running animation that writes the same property of the same target. Two live tweens on one
property fight every tick; the rule that the latest one wins prevents a hover-on/hover-off
pair from stranding a frame at a half-faded alpha.

**Final value is always written.** The animator writes an animation's last value even when
the target is hidden. Intermediate writes are skipped while hidden — nothing can observe
them — but skipping the final write would strand the frame at whatever partial value it
held when it was hidden. This is load-bearing for `ScalePop`: a frame hidden mid-pop must
return to exactly 1.0.

**API:**
```lua
SuuUI.Anim:New(def)                -- create (does not auto-play)
SuuUI.Anim:CancelAll(target)       -- stop all running animations on a target
SuuUI.Anim:GetActiveCount(target?) -- running count, optionally for one target
SuuUI.Anim:Parallel(anims)         -- returns a group handle
SuuUI.Anim:Sequence(anims)         -- returns a group handle
```

### Value Transitions (`Animation/Transitions.lua`)

A registry of named strategies describing HOW a displayed scalar approaches its logical
target when that target moves. `StatusBar` is the first consumer, but the contract is not
bar-specific — it is "a painted value chases a logical value", which is the same shape for
a progress fill, a numeric readout counting up, or a needle following a setting.

**Why fractions, not pixels.** The animated quantity is a scalar fraction (0..1), never a
pixel width. The component translates the fraction into geometry through the layout
engine (`SetChildFraction`), so a strategy never touches geometry, never fights the pixel
grid, and resizes are free — the fraction is scale-independent.

**Why `ctx:Set` is the only write path.** A strategy receives a context whose `Set()` is
the single route to the painted value. It cannot reach past the component into the layout
engine, cannot desync the logical value from the painted one, and cannot skip the
pixel-quantisation guard that keeps 40 raid frames from re-laying out 60 times a second.

**Strategy contract:**

| Hook | Required | Called when |
|------|----------|-------------|
| `Attach(ctx)` | no | the owner adopted this strategy |
| `Apply(ctx, from, to)` | **yes** | the target moved; drive `ctx:Set` from `from` to `to` |
| `Cancel(ctx)` | no | abandon motion in flight, leaving the value where it is |
| `Detach(ctx)` | no | the owner dropped this strategy; release scratch |

**Context object:**

| Field / Method | Returns | Purpose |
|---|---|---|
| `ctx.owner` | handle | the handle that owns the value (a StatusBar handle) |
| `ctx.state` | table | scratch table the strategy owns; allocated once per attach |
| `ctx:Set(v)` | — | paint `v` now — the ONLY write path |
| `ctx:Get()` | number | the currently painted value |
| `ctx:Target()` | number | the current logical target |
| `ctx:Duration()` | number | seconds for a full 0..1 sweep (bar's override or `animBarFill` token) |

**Built-in strategies:**

| Name | Behaviour | When to use |
|------|-----------|-------------|
| `instant` | `Set(to)` immediately | deterministic specs; "off" as a selectable choice |
| `smooth` | fixed-duration ease (easeOut), regardless of distance | sparse, large changes — a health bar taking a single hit |
| `rate` | constant speed (linear), duration scaled by distance | frequent small updates — energy regen, cast progress — where a fixed-duration ease restarts faster than it finishes and the bar permanently lags |

**Override levels (highest wins):**

| Level | How | Scope |
|-------|-----|-------|
| Registry default | `SuuUI.Anim.Transitions:SetDefault("smooth")` | all new bars that do not name one |
| Per-bar by name | `bar:SetTransition("rate")` or `transition = "rate"` prop | one bar |
| Per-bar inline table | `bar:SetTransition({ Apply = function(ctx, from, to) ... end })` | one bar, no registration needed |
| Per-call immediate | `bar:SetValue(50, { immediate = true })` | one write, skips whatever strategy is active |

**API:**
```lua
SuuUI.Anim.Transitions:Register(name, strategy)
SuuUI.Anim.Transitions:Has(name)
SuuUI.Anim.Transitions:Get(name)
SuuUI.Anim.Transitions:List()
SuuUI.Anim.Transitions:SetDefault(name)
SuuUI.Anim.Transitions:GetDefault()
SuuUI.Anim.Transitions:Resolve(spec)   -- nil|name|table → normalised strategy
```

### Presets (`Animation/Presets.lua`)

```lua
SuuUI.Anim.Presets.FadeIn(frame, duration)
SuuUI.Anim.Presets.FadeOut(frame, duration)
SuuUI.Anim.Presets.SlideIn(container, child, anchor, dir, dist, duration)
SuuUI.Anim.Presets.SlideOut(container, child, anchor, dir, dist, duration)
SuuUI.Anim.Presets.ScalePop(frame, duration)
```

`SlideIn`/`SlideOut` animate position through an anchor-layout container — `dir` is
`"up"|"down"|"left"|"right"`. `ScalePop` is the addon's one sanctioned `SetScale`; see
`coding-standards.md` for the carve-out rationale.

---

## Component Library

All components accept `(props, parent)`. Return a handle with shared API.
All components auto-restyle on `SUUUI_THEME_CHANGED`.

**Components are the ONLY place raw WoW UI API may be called.** `CreateFrame`,
`CreateTexture`, `CreateFontString`, `SetBackdrop`, `SetFrameStrata`, `EnableMouse`,
and `SetScript` belong inside `Components/`, `Layout/`, and `Core/UIRoot.lua` — never
in `SettingsUI/` or plugin page code. See `WOW_API_ENCAPSULATION.md`.

Allowed there does not mean reached for first. Inside a component, the raw API is for
what genuinely has no primitive: the frame itself, its scripts, textures, cursor math.
Everything with a primitive goes through the primitive:

- backdrop styling → `SuuUI.Backdrop.Apply` / `SetBg` / `SetBorder`, never `SetBackdrop`
  plus a hand-built table and hand-resolved tokens
- text → `Components.Text`, so the element re-measures when a `fontSize*` token changes
- `GetWidth` `GetHeight` `IsShown` `GetFrame` `SetSize` `Show` `Hide` →
  `Components.InstallBase`, never retyped on the metatable

And a component composes the components that already exist rather than rebuilding their
parts — `Notice` is a `Modal`; `Modal` itself is `Text` + `Input` + `Button` in
containers. Re-implementing a sibling's internals is the same duplication as inlining
raw frames in a page, one layer down.

**Writing a new component? Follow "Anatomy of a Component" in `coding-standards.md`.**
It carries the annotated skeleton every component in this directory is built from —
construction order, the `_paint()` / `ApplyTheme()` split, why the resize hook is
registered before the host container adopts the frame, and what `Destroy()` must free.
`Components/NavItem.lua` is the shortest complete example in the codebase.

**Shared API (all components):**
```lua
comp:SetSize(w, h)
comp:GetWidth() / comp:GetHeight()
comp:Show() / comp:Hide() / comp:IsShown()
comp:SetEnabled(bool)
comp:Destroy()
comp:GetFrame()
comp:ApplyTheme()
```

There is deliberately **no `comp:SetPoint`**. Components are positioned by adding them
to a container; they position their own internals with a host container. See
`LAYOUT_SYSTEM.md`.

**Every component must also:**
1. Emit the standard `SuuUI.UISignals` signals that apply to it — a component with a
   value emits `VALUE_CHANGED`, one that resizes emits `SIZE_CHANGED`, and so on.
2. Translate Blizzard scripts into signals internally. The script never escapes the
   component file; consumers connect to signals, not to `GetFrame():SetScript(...)`.
3. Cache token values in `ApplyTheme()` and re-read only there. If the new tokens
   change the element's own size — a font size token changing text metrics, say —
   `ApplyTheme()` must re-measure and emit `SIZE_CHANGED`, or the containing layout
   keeps the geometry it measured under the old theme. `Text` and `Slider` do this.
4. Clean up in `Destroy()`: `SuuUI.UISignals:DisconnectAll(self)` plus
   `SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)`.
5. **Have a spec** in `Tests/spec/` covering its geometry, token-driven sizing, every
   signal, disabled state, theme reaction, edge cases and teardown. A component without
   one is not finished. See `TESTING.md`.

**Missing a component?** Build it in `Components/<Name>.lua` rather than inlining raw
frames in a page. Register it in the `.toc`, write its spec in `Tests/spec/`, and
document it here.

**Shared primitives** (non-visual, consumed by the components above):
- `Backdrop` — `SuuUI.Backdrop.Apply(frame, { bg, border, borderWidth })` builds the
  standard bg+border backdrop; `SetBg` / `SetBorder` recolour without rebuilding it.
  `bg`/`border` take a token key, a literal `{r,g,b,a}`, or `false`/nil for fully
  transparent. `Theme:ApplyToFrame` delegates to it. `inset` controls how far the
  background sits inside the frame and defaults to the border width; a borderless surface
  that must cover its whole box passes `inset = 0`, which is what keeps a frameless
  `StatusBar`'s track and fill on the same edges.

  **A backdrop cannot be rounded** — its corners are its texture's corners — so the same
  file carries the rounded surfaces, composed from textures and cut with an alpha mask.
  They return a **handle** rather than painting a frame in place, and the frame must be a
  plain `Frame` (a backdrop underneath would show its own square corners):

  | Call | Draws |
  |---|---|
  | `Backdrop.CircleMask(frame, tex)` | attaches a circular mask to one texture; returns it for the caller's container to size onto the texture, or nil where the client has no mask API |
  | `Backdrop.Circle(frame, { bg })` | a solid disc filling the frame → `{ SetBg, Destroy }` |
  | `Backdrop.Pill(frame, { bg, border, borderWidth, inset })` | a stadium: a rectangle with a fully rounded cap at each end → `{ SetBg, SetBorder, Refresh, Destroy }` |
  | `Backdrop.Glass(frame, { from, to, sheen, border, inset })` | the plate an action bar draws itself on: a translucent vertical gradient, a lit hairline top edge, and an optional hairline border → `{ SetColors, SetBorder, IsGradient, Refresh, Destroy }`. Those three things **together** are what reads as glass — WoW has no `backdrop-filter`, so frosted is unavailable. `from` is the DENSE end and it is the **TOP**, which inverts the usual convention that a gradient's `from` is the bottom of a value square. Degrades to a flat fill where the client has no gradient API, which `IsGradient` reports |

  `Pill` mirrors `Apply`'s vocabulary, so swapping a square surface for a rounded one
  changes the call and nothing else. `inset` is the visible ring thickness and defaults to
  the border width, exactly as `Apply`'s does.

  Three things about it are load-bearing:

  - **The caps are half the height wide and their masks span the full height**, so each cap
    shows the outer half of a true circle. One mask stretched across the whole frame would
    draw an *ellipse*, which is why a wide `Circle` is not the same thing as a `Pill`.
  - **The pieces meet edge to edge rather than overlapping.** Overlap is invisible for an
    opaque colour and blends against itself at both ends for a translucent one — and every
    surface token carrying `opacityPanel` is translucent.
  - **Rounded surfaces are tinted, not recoloured.** `SetVertexColor` keeps the white fill
    the mask is attached to; `SetColorTexture` replaces the texture and would take the
    rounding with it. That is why `Circle`/`Pill` expose `SetBg` at all instead of letting
    callers reach for the texture.

  Cap width derives from the frame height, so `Pill` hooks the frame's own
  `OnSizeChanged` (chaining any existing handler) and re-derives itself — a resize needs no
  call from the owner. `Refresh()` covers the other input, a changed `borderWidth` token,
  and belongs in the owner's `ApplyTheme`. Where the client has no mask API the caps stay
  square and the control renders exactly as it did before rounding: a worse look, not a
  broken widget.
- `Base` — `SuuUI.Components.InstallBase(meta, field)` installs `GetWidth` `GetHeight`
  `IsShown` `GetFrame` `SetSize` `Show` `Hide` onto a component metatable, filling only
  the gaps so a custom override survives. `SetSize` never emits `SIZE_CHANGED`.
  `SuuUI.Components.InstallEnable(meta, field)` does the same for the enabled state:
  `SetEnabled` `IsEnabled` `_applyEnabled`, where disabled is one root-frame fade to
  `opacityDisabled` plus dropped mouse input. Components add extra disabling behaviour on
  an `_onEnabledChanged(en)` hook rather than writing their own `SetEnabled`, so no paint
  path has to remember to grey itself. See coding-standards.md "Disabled State".

**Components:**
- `Frame` — base styled container. `variant`: `"bg"|"bgAlt"|"bgActive"|"transparent"`,
  `border = false` to drop the border.
- `Text` — FontString with token font/size/color. `font` (prop or `SetFont(path)`) pins an
  explicit face, overriding the font token while size and colour still follow tokens; it
  re-measures, so a taller face reports its new height. Only for text that must render in
  a face other than the theme's — a font picker previewing its options. Pass `nil` to
  follow the token again. `SetFontSize(key)` / `GetFontSize()` switch which `fontSize*`
  step the element renders at, re-measuring and emitting `SIZE_CHANGED`. The step stays a
  token key, so a size chosen by a plugin setting still follows a user's edit of that
  token; an unknown key degrades to `fontSizeMd` rather than raising. `color` is likewise a
  key rather than a token name — `"text"`, `"muted"` / `"textMuted"`, `"disable"`, `"accent"`,
  plus the three **intent** keys `"success"`, `"warning"` and `"danger"` onto `colorSuccess` /
  `colorWarning` / `colorDanger`, for a label whose value carries state: a readout that is
  fine, close to a threshold, or past it. Named for the intent rather than the hue, so a retint
  moves them with every other warning in the UI. An unknown key degrades to `colorText` rather
  than raising, which is what lets a data bar field pass a widget's tone straight through
  without validating it first.
- `Button` — fully custom, animated hover/press states. Hugs its label: width and
  height are measured from the text plus token padding unless `w`/`h` are given
  (`minW`/`minH` set floors). Re-fits on `SetLabel` and on font token changes, and
  emits `SIZE_CHANGED` so the containing layout re-flows. Add it without `width`/
  `height` props to keep the hug. `variant`: `"danger"|"success"|"warning"` tints the
  border and label with the matching intent token; the background stays on the surface
  tokens so a variant reads as emphasis rather than a different control. Disabled state
  overrides the variant.
- `IconButton` — Button + texture slot.
- `Icon` — display-only texture in a frame. `size` (square; `w`/`h` override per axis, omit
  all three to follow `sizeIcon`), `border` draws the themed edge and insets the art inside
  it, `borderColor` (and `SetBorderColor`) lets that edge carry state — a cast bar marks an
  uninterruptible spell this way — and `trim` crops the bevel Blizzard bakes into its own
  icon files so a themed border is the only one visible. `SetIcon` / `GetIcon`. Takes no
  mouse input, which is what makes it safe to overlay or nest inside something that does —
  for a clickable icon use `IconButton`.
- `ActionButton` — one action bar cell: the client's own action system wearing SuuUI's art.
  A `Button` on `SecureActionButtonTemplate`, composing `Icon` for the art, a Blizzard
  `Cooldown` for the sweep (the same sanctioned exception `AuraIcon` takes), and four `Text`
  readouts in an overlay frame raised above the sweep. Props: `slot` and `size` — **both
  required**, because a button's size is a *plugin setting* and the component must not invent
  a theme token for it — plus `binding`, `showHotkey`, `showMacroText`, `showCount`,
  `showCooldownText`, `name`.
  API: `Refresh` / `GetSlot` / `HasAction` / `IsCurrent` / `IsAutoRepeat` / `IsOutOfRange` /
  `SetShowHotkey` / `SetShowMacroText` / `SetShowCount` / `SetShowCooldownText` / `SetBinding`.
  Emits `CLICKED`,
  `MOUSE_ENTER`, `MOUSE_LEAVE`, `SIZE_CHANGED`. Draws **no border** — the A2 look is one glass
  plate under a whole grid with hairline dividers between cells, so a per-button border would
  draw a second edge inside the first.

  **The remaining cooldown is drawn as a number, centred, and the swipe and the number
  deliberately disagree about the global cooldown.** `GetActionCooldown` reports the GCD on
  *every* slot at once, so an unfiltered countdown puts a number on all ninety-six buttons on
  every cast — which is noise rather than information, and is exactly what a player asking for
  "the cooldown of an ability that actually has one" is asking to be spared. The swipe still
  takes every cooldown the client reports, GCD included, because a sweep across the whole bar is
  how "briefly unavailable" reads and it costs no text. The filter is `GCD_MAX_DURATION`, 1.5s,
  and it is **tested against the cooldown's DURATION rather than its remaining time** — a
  six-second cooldown keeps its number down to 0.1s, while a 1.5-second one never draws at all.
  The number is not invented here: ElvUI ships `minDuration = 1500` (ms) as its cooldown default
  on this client and hands it to the client's own `SetMinimumCountdownDuration`, so it is the
  same line every other bar addon on the machine draws, and it covers the 1.0s GCD some energy
  abilities use. The cost is that a genuine cooldown of 1.5s or shorter shows no number; nothing
  in this expansion has one.

  Two more things about it are load-bearing. The countdown **rides the existing shared range
  ticker** rather than adding a second `OnUpdate` frame, and that throttle already suits it
  exactly — `Readout.Duration`'s decimal band is tenths, so ten times a second is precisely the
  rate at which the string can change; only buttons with a real cooldown running are walked, so
  an idle bar pays one `next`. And the **toggle is checked after the expiry branch**, so a
  cooldown that runs out while the readout is switched off still retires its button from the
  walked set — a mutation moving that check to the top of the paint survived until the spec
  asserted the set rather than only the string.

  It takes **plain `colorText`, not `AuraIcon`'s `colorWarning` under five seconds**: on an aura
  that band means "about to fall off", but every cooldown in the game passes through it on the
  way to zero, so the same rule would turn the number yellow at the tail of every cast and mean
  nothing. Centred because the other three positions are taken and because it is the reading a
  player scans a cooling button for — and at the default 32-unit size it **can overlap both
  right-hand corner readouts**, which `Tests/spec/51_actionbutton_spec.lua` pins along with an
  `xit` naming the three routes past it. The Button Size slider is today's answer.

  Everything below fails **silently in game** — the button still sizes, still takes the mouse,
  still reports as shown — which is why each is pinned by a mutation-verified spec:

  - **Never `SetScript("OnClick")`.** The template installs the handler that performs the
    action. Observe through `PostClick`, exactly as `UnitClickArea` does.
  - **`RegisterForClicks` is not optional.** A `Button` fires for left-up alone until told
    otherwise, so a right-click action never reaches the client without it.
  - **Attributes are stated once, at construction**, and the component exposes no `SetSlot`.
    `SetAttribute` is refused on a protected frame in combat, so a setter that re-pointed a
    live button would fail exactly while a player was fighting. Paging is the secure state
    driver's job.
  - **The slot is read from the ATTRIBUTE on every refresh, never cached in a field.** This is
    the subtle one. Bar 1 pages through six blocks of twelve and the secure snippet rewrites
    `action` *inside the secure environment*, where Lua cannot observe the write — so a cached
    slot keeps drawing the spell the button had before the player changed stance. `GetAttribute`
    is a read and is never refused.
  - **Two buttons may address ONE slot.** Measured, not hypothetical: bar 1's page 3 is exactly
    `MultiBarRight`'s block, so the module keeps a slot → **set of buttons** index and a slot
    change repaints every watcher. A slot → single button map repaints whichever it finds and
    leaves the other showing a stale spell.
  - **`LOCK_ACTIONBAR` is a CVar-backed plain global**, so it is the string `"0"` or `"1"` —
    and `"0"` is *truthy* in Lua. It must be compared, never tested.

  One event frame and one throttled range ticker serve **every** button in the addon, both
  registered only while at least one button exists — sixty event frames and sixty `OnUpdate`
  scripts would be the alternative. Range is polled at 10/sec because nothing announces that a
  target walked out of range; the tick allocates nothing and each button early-returns when its
  state has not moved. `IsCurrent` and autocast **are rendered now, on the button rather than on
  the plate**, and they use two different channels on purpose: active is an **edge bar** (a texture
  on the raised overlay, `Pixel.Line(2)` tall, anchored across the bottom, `colorAccent`), while
  autocast recolours the overlay's **border** to `colorWarning` — gold, matching Blizzard's own
  golden autocast shine. Two states through one channel cannot be told apart, and the bottom bar
  also leaves the icon art unobscured. The motivating bug is a pet detail: a pet's mode
  (Passive/Defensive/Aggressive) is reported as the slot being *current*, so without a distinct
  treatment a player could not tell which mode their pet was in. Only `autoCastEnabled` draws —
  `autoCastAllowed` merely means the command *could* autocast. There is no Lua autocast toggle:
  `TogglePetAutocast` is protected, so a right-click is forwarded into Blizzard's own pet button
  inside the secure environment.

  There is deliberately **no `SetEnabled`**, for the reason `StatusBar` and `UnitClickArea`
  have none: disabling means dropping mouse input, a call the client refuses on a protected
  frame in combat. An action that should not be used renders as unusable instead.

  Props: `slot`, `size`, `binding`, `showHotkey`, `showMacroText`, `showCount`, `name`, and
  **`kind`** — `"action"` or `"pet"`. A pet button is the same secure template addressing the
  same `action` attribute, only with `type = "pet"`; it lives as a `kind` rather than as its own
  `PetButton.lua` because the press-versus-release gate must exist in exactly **one** place. That
  gate was got wrong twice, and each time produced a bar that looked perfect and did nothing.

- `StanceButton` — one shapeshift-form cell. `form` and `size` are asserted; also takes
  `binding`, `showHotkey`, `name`. Emits `CLICKED` (always `"LeftButton"`), `MOUSE_ENTER`,
  `MOUSE_LEAVE`, `SIZE_CHANGED`.

  **It is the only SuuUI button built on a Blizzard template, and both reasons were measured
  rather than assumed.** `StanceButton1:GetAttribute("type")` is **empty** on this client, so
  there is no attribute to state — and `CastShapeshiftForm` is blocked for tainted code, probed
  bracketed: read form 7, cast form 3, read form 7 again. No error, no message, no change, a
  silent no-op. So `CreateFrame("CheckButton", name, parent, "StanceButtonTemplate")` plus
  `f:SetID(form)` is not a shortcut, it is the only path — **`SetID` is the wiring**, because the
  template's own OnClick reads `GetID()`. SuuUI still composes its own visuals; only the click
  plumbing is borrowed, and the template's art is cleared by emptying each Texture through its
  getter and hiding *that* (`SetNormalTexture(nil)` is refused outright).

  `SetShowMacroText()` and `SetShowCount()` are deliberate **no-op stubs**: a form has neither, and
  interface parity means `ActionBarGrid`'s shared painters need no per-kind branch. "Stance"
  follows Blizzard's and ElvUI's naming rather than the scope — it covers warrior stances, druid
  forms, rogue stealth, priest shadowform and paladin auras.

- `ActionBarGrid` — rows × columns of buttons on one glass plate. `slots` and `buttonSize` are
  asserted; `bindings`, `rows` (default 1), `spacing` (default 0), `padding`, `showHotkeys` /
  `showMacroText` / `showCount` (default true), `namePrefix`, and `buttonFactory` (default
  `Components.ActionButton`). Emits `SIZE_CHANGED` and `CHILDREN_CHANGED`.

  **Every geometry change defers out of combat.** A grid contains protected buttons by
  construction, so the client refuses `SetSize` on the grid *and* `SetPoint` on each button while
  `InCombatLockdown()` — a settings change arriving mid-fight sets a flag and catches up on
  `PLAYER_REGEN_ENABLED`. `IsDeferred()` reports that state.

  `CHILDREN_CHANGED` exists for one consumer: the grid **destroys and recreates** its buttons when
  the count or a slot changes, and that rebuild can itself be deferred to the end of a fight — so
  nothing else can tell a holder of button references when they went stale. Secure paging and
  keybinding routing both subscribe to it.

  **The plate takes no mouse input.** A plate that swallowed clicks would make the gaps between
  buttons unclickable in the world behind them. Hairline dividers are drawn **only** for a
  seamless grid (`spacing == 0`), on their own frame raised above the buttons, placed by a second
  container on the same host: a `grid` container places the buttons and an `anchor` container
  places the dividers, because a divider sits *between* cells rather than in one.

  `buttonFactory` is what lets the same grid host stance cells — the grid owns the plate, the
  layout, the dividers, the padding and the resize, and knows nothing about action slots.

- `Icon` gained two art-state methods alongside `SetBorderColor`, and the split is deliberate:
  a **border** carries a property *of* the thing (a cast is uninterruptible), while a tint on
  the **art** carries whether the thing is usable *right now*. `SetArtTint(color, alpha)`
  multiplies the texture — `nil` means untinted rather than black, and the optional `alpha`
  dims without choosing a colour. `SetArtDesaturated(on)` drains the colour and returns
  whether the client actually did it, since not every generation has the shader. Both are
  re-asserted from `ApplyTheme`, so a tint naming a token follows a live token edit.

  `ActionButton` composes them into three distinguishable states without inventing a palette
  entry: **unusable** is desaturated *and* dimmed to `opacityDisabled`, **short of a resource**
  is desaturated but *not* dimmed, and **out of range** takes `colorDanger` and wins over both
  — walking closer is the action a player takes next. Blizzard tints the resource state blue;
  matching that exactly would need a new token, so it is an open design question rather than a
  silent approximation.

- `AuraIcon` — an `Icon` plus everything an aura has to say about itself: a radial cooldown
  swipe, a stack count, a remaining-time readout, and a dispel-type border. Composes `Icon`
  for the art and the edge, a Blizzard `Cooldown` frame for the sweep (a sanctioned template
  exception, like `Input`'s `EditBox` — nothing else draws one), and two `Text` readouts in an
  overlay frame raised above the sweep, because a font string parented to the root would sit
  *behind* it. `SetIcon` / `SetCount` / `SetTimer(duration, expiration)` / `SetTimeLeft` /
  `SetTypeColor` / `SetShowDuration`; size follows `sizeIcon` unless pinned. Takes mouse input
  and emits `CLICKED` / `MOUSE_ENTER` / `MOUSE_LEAVE` — it knows nothing about tooltips or
  which aura it shows, so the owner wires those off the signals and the component stays
  general. Two details are load-bearing: the count shows only at **> 1**, because the client
  reports `count = 0` for a non-stacking aura and a "0" on every buff is noise; and the
  duration text takes `colorWarning` under 5 seconds so an expiring aura reads at a glance.
  `SetTypeColor(nil)` returns the edge to `colorBorder`.

  **The remaining time is centred on the icon and the count sits in the bottom-right corner.**
  Both readouts used to share the bottom row, which put them through each other at every icon
  size the settings allow — the readouts take `fontSizeSm`, whose line height does not scale
  with the icon, so two of them cannot be vertically disjoint inside a 24-unit box. Centring
  the timer is also the right emphasis: remaining time is what a player scans a debuff for.
  It does not fully resolve the crowding at small sizes, and `Tests/spec/41_auraicon_spec.lua`
  pins where the line still is plus an `xit` naming the routes past it.

  **Decimals appear only below one second** — `2h` / `30m` / `45s` / `0.4s` — because that is
  the one band where the whole-second form carries no information: it would read "0s" for the
  entire final second. Every step floors rather than rounds, so a readout never shows time
  that is already gone, and `"%.1f"` on 0.99 would print `"1.0s"` from the branch that had
  just decided the value was under a second.

  **That format is `Readout.Duration`, not this component's own.** It was a file-local here on
  the argument that every consumer of an aura remaining-time would otherwise re-write it — right
  about the hazard, one step too small about the scope. An action button's cooldown countdown is a
  second *surface* spelling the same quantity, and two remaining-time readouts inches apart on
  screen must not disagree, so it moved to Core for the reason `Readout.Money` did.
- `NavItem` — selectable labelled row with hover/selected states, for nav lists.
- `DataField` — one field on the data bar: a muted **prefix**, a **value**, and an accent
  underline along the bottom edge while hovered. Props: `prefix`, `text`, `tone`, `w`, `h`,
  `minW`, `rail` (draw the underline on hover, default true), `size` (font step key for the
  value, default `"md"`). API: `SetText` / `GetText` (the value alone, without the prefix or
  its colour escape), `SetTone` / `GetTone`, `SetPrefix` / `GetPrefix`, `SetRail`, `IsHovered`.
  Emits `CLICKED` (button), `MOUSE_ENTER`, `MOUSE_LEAVE`, `SIZE_CHANGED`, `TEXT_CHANGED`.
  It **hugs its own text** —
  `TextMetrics.Box` plus `spaceMd` on each side, floored by `minW` — while its **height comes
  from whatever lays it out**, which on the bar is a stretched flow child, so a field is
  exactly as tall as the bar. `SetSize` opts out of the hug, for a caller that wants a fixed
  column.

  **The prefix and the value share ONE font string, coloured with an inline escape.** Two
  `Text` handles at two font steps is the obvious build and it is subtly wrong: flow layout
  centres their **boxes**, and a font's ascent is roughly three quarters of its line height
  rather than half, so centring two different line heights leaves the two baselines about
  `(h2 - h1) * 0.28` apart — a whole pixel once the grid rounds it, and it reads as a step
  between the label and the number in every field on the bar. One font string has one baseline
  by construction, needs no ascent metric the client does not expose, and halves the font
  strings the shared ticker rewrites. The cost is that the separator can only be a space
  character, since one string has one font: the gap between prefix and value is a space rather
  than a spacing token. `ApplyTheme` therefore **recomposes** the string rather than only
  restyling it — the prefix's colour is baked in as a `|cff…|r` escape, so a `colorTextMuted`
  edit reaches the screen no other way.

  **The tone rides on that same single font string.** `SetTone("warning")` colours the font
  string itself, and only the value picks the colour up: the prefix carries its own escape, so
  the restore at `|r` lands on whatever colour the string is currently set to. So one baseline
  also buys one colour to set, with no substring bookkeeping. The tone is a **key**, never a
  colour — `"success"` / `"warning"` / `"danger"` resolve through `Text`'s own colour map onto
  the intent tokens, so a widget can state what a reading means and cannot state a hue, and an
  unknown key degrades to `colorText` rather than raising from inside a ticker callback.
  `ApplyTheme` restates it (`SetColor(self._tone or "text")`) rather than assuming the label
  kept it, which is also what makes a `tone` given at construction reach the screen: the
  field's own `_tone` is the single source of truth for the value's colour.

  Three more details are load-bearing:

  - **At rest it paints nothing.** The bar already draws one continuous `colorBg` surface
    underneath, so a field with a background of its own would either match that surface
    exactly (a wasted draw) or blend a second translucent panel colour against it and leave a
    visible seam at every field edge — the trap `Accordion`'s header and body avoid by being
    siblings. Only the hover fill (`colorBgHover`) is painted, and the surface is borderless
    with `inset = 0` so it covers the whole box and meets its own dividers, exactly as a
    frameless `StatusBar` does.
  - **The rail is a texture on `sizeRail`, and it is tied to the hovered state rather than to
    a flag of its own** — a backdrop border draws on all four sides, and a rail driven by its
    own flag can survive a `MOUSE_LEAVE` that some other paint path forgot about. It shares
    `Accordion`'s token rather than adding one, because it is the same accent-rail cue.
    A field only advertises a rail when its widget defines `OnClick` or `OnEnter`: the rail
    means "you can act on this", so painting it on a pure readout promises an interaction
    that is not there.
  - **An unchanged `SetText` is dropped.** A readout is rewritten on every game event and on
    every tick of the bar's shared ticker and usually says exactly what it said last time;
    re-measuring and re-laying out for that would be the bar's entire cost. Same guard as
    `StatusBar`'s overlay readouts. The width comes from `TextMetrics.Box`, never `Measure`,
    because the label is a stretched stack child and the insets subtracted here are handed
    straight back to it — its own box lands at exactly the metric, which is where the client
    truncates with zero tolerance. That is how `NavItem`'s tab strip rendered `Play…` for
    "Player" with every geometry assertion passing.
- `Accordion` — a collapsible group of rows behind a clickable header, with an accent rail
  down its left edge while it is open. Props: `label`, `open`. API: `GetBody`, `GetHeader`,
  `SetOpen(open, { animate = false })`, `IsOpen`, `SetOpenState`, `SetReveal`, `GetReveal`,
  `SetLabel`, `GetLabel`. **Rows go into `GetBody()`**, which is a container — so a row
  appearing, vanishing or growing is an ordinary resize that travels outward on its own, and
  the page above re-hugs and re-ranges its scrollbar on every tick of a reveal without
  anyone driving it. Emits `CLICKED` from the header, plus `SIZE_CHANGED`,
  `VISIBILITY_CHANGED`, `MOUSE_ENTER`, `MOUSE_LEAVE`, `TEXT_CHANGED`.

  **It does not open itself on click.** The header emits `CLICKED` and an owner decides what
  the gesture means — the same division `ResizeGrip` draws between reporting a gesture and
  acting on it. That is precisely what lets `AccordionGroup` arbitrate between members, and
  it is why `SetOpen` is silent: only a header click emits, so driving it from a watcher or a
  group cannot loop back into whatever asked for it. `SetOpenState` flips the logical state
  and repaints without touching geometry, for an owner animating the reveal itself.

  Four things are load-bearing, and each is a trap this codebase has already paid for once
  somewhere else:

  - **The body's window is a separate container with an explicit height, never the body
    itself.** A container with no height of its own hugs its content and re-states that
    height from inside `Layout()` — on the very tick an animation set it. Animating a hugging
    container is a fight the hug always wins.
  - **The window is shown before it is animated, and hidden only once a close finishes.** The
    animator skips intermediate writes on a hidden target and flow layout skips a hidden
    child outright, so a reveal driven while hidden simply jumps. Collapsed means *hidden*,
    not zero-height: flow skips it entirely, so a closed group contributes neither height nor
    gap, and a zero-sized frame is a shape the client is entitled to treat oddly.
  - **The root column's gap is zero**, with the spacing carried inside the header and the body
    instead. A collapsed window contributes no height either way, but a shown one would still
    contribute a gap — which then vanishes the instant it is hidden, popping every group below
    it by `spaceXs` at the end of every close.
  - **The header and the body surface are siblings painted with the same token.** Both carry
    `opacityPanel`, so nesting one inside the other would blend the fill against itself and
    put a visible seam across a group that is meant to read as one surface. The body surface
    passes `inset = 0` for the same reason a frameless `StatusBar` does: a borderless surface
    must cover its whole box, or the body sits a pixel inside the header's fill and the two
    read as different colours where they meet.

  **The window clips its children, and the clip is feature-detected.** Without it the body's
  rows draw straight over the group below for the whole animation, which is worse than not
  animating — so where `SetClipsChildren` is missing the reveal degrades to a snap. Same
  degradation as `Backdrop.Pill` falling back to square caps where there is no mask API: a
  worse look, not a broken widget. The window's height is `Pixel.Ceil`'d rather than floored
  because it is a *window onto* content, and one unit short clips the last row's descenders at
  full reveal.

  **The chevron is ASCII** — `v` open, `>` closed — for the same reason `Dropdown` spends a
  plain `v` on its arrow: the client's faces do not reliably carry the geometric-shape
  triangles, and a face missing one draws a box or nothing at all. Its column is measured
  from the **wider** of the two glyphs rather than the current one, so swapping them never
  shifts the label sideways by the difference, and through `TextMetrics.Box` rather than
  `Measure` because the number becomes the font string's own box. The rail goes through
  `Pixel.Line`, and it is tied to the **reveal** rather than the logical state: it has to stay
  lit for the whole of a close, and a body still 80% visible with no rail beside it reads as a
  glitch.

  Deliberately **no `SetEnabled`**: an accordion holds controls rather than being one, so
  there is no value to grey, and a root-frame fade would multiply with the fade of any
  disabled row inside it (0.40 × 0.40 = 0.16). Absent, `Dependency.Bind`'s
  `if target.SetEnabled` guard skips it honestly instead of believing a stub greyed
  something — the same reasoning as `StatusBar` and `UnitClickArea`.
- `AccordionGroup` — `SuuUI.Components.AccordionGroup({ duration, easing })`: at most one  member open at a time. API: `Add(acc)`, `Open(acc, { animate = false })`, `GetOpen`,
  `GetMembers`, `Destroy`. **Not a widget** — it owns no frame, is never laid out, and exists
  only to arbitrate; `Add` takes over the member's header click. Emits
  `ACCORDION_SIGNALS.OPEN_CHANGED`.

  The reveal is timed by **`animFast`**, the token every panel reveal already uses —
  `Dropdown`'s panel, `Modal`, `Tooltip`, `Window`. A section opening is the same gesture
  as a dropdown opening, so it shares the timing rather than carrying one of its own;
  `opts.duration` overrides it per group, and 0 degrades to a snap.

  Exclusivity is policy, so it lives here rather than in `Accordion` — and so does the
  **motion**. `Open` drives the whole group from **one** tween: two separate height
  animations would write twice per tick and re-flow the whole page twice per frame, while one
  moves every member in a single pass, perfectly in step. Each member's `from` is its
  *current* reveal, so interrupting a half-finished transition continues from where it
  actually is rather than snapping. Every member must be able to clip or the whole group
  snaps, since the one that cannot would spill its rows over the group below for the tween's
  duration.

  **Every member is driven, not just the two the click named.** `Play` pre-empts any running
  animation on `(group, "value")`, so a member the *previous* tween was still closing — click
  one header, then a second, then a third mid-transition — is neither the new tween's
  incoming nor its outgoing member, and driving only those two left it stranded at a
  fractional reveal: window shown, height still contributed to the page, while `IsOpen()`
  reported closed. The page disagreed with itself, and the group's own arbitration was what
  hid it. The `from` table is reused across calls, so covering every member costs no
  allocation per click.

  **Opening the already-open member collapses it, and `Open(nil)` collapses everything**:
  "one at a time" does not mean "one always", and an all-closed page is how a player scans a
  long one for the group they want. `Destroy` drops the group's own subscriptions and cancels
  a transition in flight but does **not** destroy the members — they are laid out by a
  container, and that container's teardown owns them.
- `Toggle` — animated sliding switch, no Blizzard checkbox. The track is a
  `Backdrop.Pill` and the knob a `Backdrop.Circle`, so both ends are fully rounded; a
  square knob inside a stadium reads as a rendering fault rather than a choice.
- `Slider` — custom track + thumb, label, value display. The circular thumb rounds through
  the same `Backdrop.CircleMask` the pill caps use.
- `Dropdown` — custom panel, animated open/close. Shows the `colorBorderFocus` ring
  while hovered or open, like `Input`. Its arrow column is measured from the glyph via
  `TextMetrics`, not pinned to a space token, so it never truncates to an ellipsis. An
  option may carry `font = path` to render in that face — the font picker's preview. Row
  and button heights are then measured from the face rather than assumed equal, since a
  face's line height does not follow from the point size, and the panel is sized from the
  rows it actually laid out.
- `Input` — EditBox (Blizzard, unavoidable), themed styling.
- `ColorSwatch` — clickable colour square with token border, `GetHex()` helper.
- `ColorPicker` — custom HSV picker + hex input.
- `KeyCapture` — button that captures the next keypress into a binding string.
- `ScrollFrame` — custom scrollbar + masked content.
- `StatusBar` — progress/resource bar (health, mana, energy, rage). Props: `w`, `h`,
  `value`, `max`, `fillColor` ({r,g,b,a} literal), `bgColor` (token or literal, default
  `"colorBgAlt"`), `border` (bool, default true), `borderColor` (token or literal, default
  `"colorBorder"`), `transition` (strategy name or inline table, default: the registry
  default), `transitionDuration` (seconds for a full sweep, default: the `animBarFill`
  token), `textSize` (font size key for the overlay readouts, default `"sm"`).
  API: `SetValue`, `SetMax`, `GetValue`, `GetMax`,
  `GetPercent`, `GetDisplayPercent`, `IsTransitioning`, `SetTransition`, `GetTransition`,
  `SetTransitionDuration`, `SnapToTarget`, `SetFillColor`, `SetBgColor`, `SetBorderColor`,
  `SetBorderShown`, `IsBorderShown`, `SetText`, `GetText`, `SetTextSize`, `GetTextSize`,
  `Destroy`. The
  fill is a **fractional stack child** of the track (`widthFraction`), so the layout
  engine owns the fill geometry — the component sets no points, and the fill stays correct
  across resizes and border-width changes without recomputation. A borderless bar insets
  by 0 so track and fill share edges exactly. `GetPercent` reports the logical target
  fraction (what `SetValue` implies); `GetDisplayPercent` reports the painted fraction,
  which lags the target mid-transition. `IsTransitioning` returns true while the two
  differ. `SetTransition` accepts a registered name or an inline strategy table;
  `SetTransitionDuration` overrides the `animBarFill` token for one bar. A theme change
  never animates — `ApplyTheme` restates the current painted fraction without triggering
  the transition. `SetText(slot, text)` fills one of three **overlay readouts** —
  `"left"`, `"center"`, `"right"` — inset past the border and vertically centred; nil or
  `""` clears one, and an unchanged write is dropped, since a readout is rewritten on every
  game event and usually says the same thing. Slots are built on first use and take plain
  strings only: what a number *means* belongs to whoever owns the value, so no formatting
  reaches the component (`Plugins/UnitFrames/UnitFrame.lua` holds the formats its health
  and resource bars share).

  **A SECOND fractional fill — the "ghost" — for a value that extends past progress.**
  `SetSecondary(f)` takes `0..1` (nil or 0 hides it), `GetSecondary()` reads it back, and
  `SetSecondaryColor(color)` overrides its colour. It is a second fractional stack child of the
  same fill box, added so it sits **below** the primary fill in draw order — the only ordering
  that makes a ghost read as a backdrop to progress rather than as a second bar. It carries its
  own pixel-quantisation cache, and is **hidden at zero** rather than left zero-width, because a
  zero-width child still costs the container a cell.

  Two behaviours are load-bearing. The ghost is **clamped to at least the main fill**: one that
  fell behind progress would be drawn entirely underneath it and read as absent, which is
  indistinguishable from a bug — so it is also re-asserted whenever the main fill moves, since the
  main fill is its floor. And **`SetSecondaryColor(nil)` returns it to deriving from the fill** at
  `fillAlpha × opacityBarGhost`, while an explicit `{r,g,b,a}` is used **exactly as given, alpha
  included** — `opacityBarGhost` is not applied on top, because a theme that names this colour has
  already decided how present it should be.

  Derivation is the default because it needs no token. It is *wrong* whenever the ghost means
  something the fill does not, and experience is exactly that case: in WoW blue **is** the rested
  colour, so a blue-derived ghost on a blue fill tells the player they are rested whenever they
  have any progress at all. There are deliberately no `secondary` props — a ghost is a runtime
  value, not a construction-time one.
  `SetTextSize` moves every slot onto another font step at once — a token **key**, never a
  pixel size, so a plugin can expose the step as a setting and the readouts still follow a
  user's edit of that token. One step per bar rather than per slot: three readouts on one
  bar at three sizes reads as a rendering fault, not a choice.
  The bar owns them rather than its caller because the fill lives in a **child frame**, so
  anything drawn in the bar's own layers would sit under it — an overlay raised above the
  fill is the only arrangement that puts text over the coloured part.
  Emits `VALUE_CHANGED`, `SIZE_CHANGED`, `VISIBILITY_CHANGED`, and
  `STATUSBAR_SIGNALS.FILL_SETTLED`. **Deliberately has no `SetEnabled`**: it is
  display-only, takes no mouse input, and is never a settings-page control, so it always
  sits inside a composite whose outer handle owns the enabled fade. Installing
  `InstallEnable` with `_fade = false` would leave a `SetEnabled` that fades nothing and
  drops no mouse — the no-op stub that makes `Dependency.Bind`'s `if target.SetEnabled`
  guard pass while nothing is actually greyed. Absent, it is skipped honestly, like
  `Tooltip`, `Divider` and `ScrollFrame`.
- `Tooltip` — cursor-following or frame-anchored, animated fade.
- `Divider` — horizontal/vertical line, optional label.
- `ResizeGrip` — the corner drag handle: three diagonal runs of one, two and three square
  dots, growing towards the corner. Dots rather than diagonal art because a square lands
  exactly on the pixel grid at any scale, while rotated or scaled line art is resampled
  into a smear at the one size a grip is ever drawn. `size` pins the square; omit it to
  follow `sizeIcon`. Dot side is `spaceXxs` and the pitch is `spaceXs` — one dot plus a
  dot-sized gap on the same scale — and the lattice is centred in the box, so raising the
  spacing scale or the icon token regrows the glyph without a second constant to tune.
  Idle dots are `colorTextMuted`; hovered they take `colorAccent`, the same "you can act
  on this" cue `Input`'s focus ring uses. **It resizes nothing.** It emits
  `RESIZEGRIP_SIGNALS.DRAG_START` / `DRAG_STOP` and the owner decides what the gesture
  means — which frame sizes, from which corner, and whether the result is saved. That is
  what lets one grip serve `Window` and anything else with an edge to drag, rather than
  being a component that knows how a window works.
- `Modal` — dialog with optional input, container-composed. `confirmVariant` tints the
  confirm button with an intent token; `dismissOnly` drops the cancel button;
  `autoDestroy` frees the modal once it finishes hiding.
- `Notice` — one-shot dismissible message built on Modal. `tone` is
  `"warning"|"danger"|"success"` or nil. **Use this instead of printing errors to chat.**
  Self-destroying, so it is safe to call on every failure.
- `ClickAway` — non-visual helper; polls for clicks outside a panel only while armed.
  Reads the cursor with `Pixel.CursorIn(panel)`, not against `UIParent`.
- `HoverAway` — the same file's second watcher, for a panel that closes when the cursor
  **leaves** rather than when something is clicked. `{ frame, guards, onOutside }`, plus
  `Arm` / `Disarm` / `AddGuard` / `Destroy`, and it polls the rect exactly as `ClickAway`
  does. **`OnLeave` cannot express this and that is why the helper exists**: the client moves
  mouse focus to a child the moment the cursor enters one, so a panel whose rows take mouse
  input receives `OnLeave` on the way *in* to the thing the player is reaching for, and a
  panel closing on its own `OnLeave` vanishes from under them. Polling is the only reading
  that treats a panel and its contents as one region. `guards` are the extra frames that
  count as inside — the anchor the panel hangs off, so crossing the seam between the two is
  not "outside" — and a short grace period covers a sample taken mid-crossing. That grace is
  deliberately a constant in the file rather than a theme token: no theme should be able to
  set it to zero and make every flyout in the addon unreachable.
- `FlyoutPanel` — a floating vertical roster, one row per entry, an adopted icon on the left
  and its name to the right, closing when the cursor leaves. Props `{ anchorTo, align,
  iconSize }`; API `SetRows(entries)` (`{ frame, label, onClick }` each), `GetRowCount`,
  `SetIconSize` / `GetIconSize`, `Open` / `Close` / `IsOpen`, `Destroy`. It lives on the
  shared floating host at the `tooltip` layer, wires its own `HoverAway` with the anchor as a
  guard, and emits `VISIBILITY_CHANGED`. A row takes mouse input only when its entry declares
  `onClick`, the same rule `DataField`'s hover rail follows: a highlight on a row that does
  nothing promises an interaction that is not there.

  Three things about it are load-bearing:

  - **It ADOPTS the frames it shows** — `SetParent` onto the row that holds them — rather than
    anchoring them in place. Only parentage makes the panel's visibility govern them: a frame
    merely anchored to a hidden row stays on screen when the panel closes, and a hidden frame
    has no rect, so a foreign frame parented anywhere else draws nothing while still reporting
    the size it was assigned. Adoption is also why `SetRows` swaps a held frame only when it
    actually differs: `Add` is a membership operation, not an upsert, so re-adding the same
    child on every rebuild grows the child list without bound.
  - **A pinned strata has to be RELEASED before it can be re-stated.** LibDBIcon creates its
    buttons with `SetFrameStrata("MEDIUM")` followed by `SetFixedFrameStrata(true)`, and a
    pinned frame does not re-inherit its new parent's strata — so an adopted button stays on
    `MEDIUM` while the panel sits on the tooltip rung and draws *behind* a backdrop carrying
    `opacityPanel`. The labels are ours and appear, the icons are theirs and do not, which
    looks like a layout fault rather than a z-order one. Clear the pin first, then raise
    through `UIRoot:RaiseAbove` — never a raw strata string — and re-assert on every rebuild,
    since the owning addon is free to re-pin its own button at any point.
  - **The layer is registered at construction, not at `Open`.** Raising adopted frames happens
    from `SetRows`, which runs before the first open; with the layer registered later
    `RaiseAbove` has no rung to resolve and silently leaves a pinned foreign frame wherever its
    owner put it.
- `UnitClickArea` — an invisible surface that hands a click over a unit's frame to the
  **client's own** unit actions: left click targets, right click opens that unit's context
  menu, with every entry the client would offer. Props: `unit` (required), `name`
  (optional global frame name). API: `GetUnit`. Emits `CLICKED` (button), `MOUSE_ENTER`,
  `MOUSE_LEAVE`, `SIZE_CHANGED`. Position it by adding it to a container, like anything
  else — but **not a container hosted on the frame it covers**, and it must not be parented
  inside that frame either. See the parentage rule below.

  Both actions are **protected**: the client refuses them from addon code, so no handler we
  could write would work. The only route is the secure template — a `Button` inheriting
  `SecureUnitButtonTemplate` carrying a `unit` attribute plus a per-button `type`
  attribute, which the template's OWN click handler reads and acts on. So this component
  states attributes and never sees the click that matters, and the menu needs no code at
  all: which entries a player, an NPC or a corpse offers is the client's decision.

  Three things about it are load-bearing:

  - **Never `SetScript("OnClick")` on a secure button.** That replaces the handler that
    performs the action, and every action stops silently — the frame still sizes, still
    takes the mouse, still reports as shown. Observe a click through `PostClick`, the hook
    the template offers for exactly this, which is where `CLICKED` is emitted from.
  - **`RegisterForClicks` is not optional.** A `Button` fires its handler for left-up alone
    until told otherwise, so without `"AnyUp"` the right click never reaches the client.
  - **Attributes are stated once, at construction.** A frame built from a secure template is
    protected, and the client refuses to let an addon reshape a protected frame in combat —
    so nothing is re-stated later and the component exposes no setter that would want to be.
  - **It is never parented inside a frame that resizes at runtime.** Protection propagates
    down to descendants and the refusal propagates up, so a plain wrapper holding this
    surface cannot be resized during combat either — the client refuses silently and the
    player gets `Interface action failed because of an AddOn`. The surface goes beside such a
    frame, parented to the root container and **anchored** to the frame so it still covers
    it, bands included. Its own host must be a frame that only resizes with the screen:
    hosting it on the resizing wrapper would chain onto that wrapper's `OnSizeChanged` and
    re-lay out a protected child on every mid-combat resize. Any geometry applied to it is
    guarded with `InCombatLockdown()` and deferred to `PLAYER_REGEN_ENABLED`
    (`UnitFrame:_syncClickArea`). Full account, including the measurements, in
    "Protected Actions Go Through A Secure Component" in `WOW_API_ENCAPSULATION.md`.

  Deliberately **no `SetEnabled`**: it paints nothing, so the disabled fade would be
  invisible, and the only real disabling left — dropping mouse input — is a call the client
  can refuse on a protected frame. A `SetEnabled` that cannot be honoured when it matters is
  worse than none, for the same reason `StatusBar` has none.
- `Pixel` — non-visual, in `Core/`: the pixel grid. `Snap` / `Floor` / `Ceil` for geometry,
  `Line` for a thickness that must never round to zero, `CursorIn(frame)` for every hit
  test and drag. `Backdrop` uses `Line` for its edge and `Theme:GetControlHeight` uses
  `Ceil`, so a control never lands half a pixel short of its own text.
- `TextMetrics` — non-visual helper: `SuuUI.TextMetrics.Measure(text, font, size, flags)`
  returns the real width/height of a string, and `Box(...)` returns the width to **reserve**
  for it. Use `Box` whenever the number ends up as the font string's **own box**. `Measure`
  is only for a caller that adds slack of its own on top of the metric — `Button` and
  `Dropdown`'s arrow column, both `+2`. They
  differ by one physical pixel because the client truncates with **zero tolerance** — a box
  short by any amount at all drops characters and draws an ellipsis — while whole-pixel
  rasterisation means the metric and the rendered extent need not agree exactly.
  **Outer padding does not make a caller a `Measure` caller.** A component that sizes
  itself to `text + insets` and then lays the label out *with those same insets* has handed
  the whole metric straight back to the label, so its box lands at exactly the metric and
  the client truncates it. That is how `NavItem`'s hugging tab strip rendered `Play…` for
  "Player": every geometry assertion passed, because the geometry was the bug. Ask what the
  font string's own box ends up being, not whether the caller added a number.
  A font string's own `GetStringWidth` is clamped to the width its layout assigned, so
  measuring a live label that is already truncated shrinks it further on every pass.
  **Measurement happens inside the UI root**, never against `UIParent`: the client keeps
  glyph advances per rasterised pixel size, so the same font at the same point size
  measures differently under two different effective scales, and the pixel grid puts one on
  the root. A probe on `UIParent` under-reports — which is all it takes. The probe re-homes
  itself, since the first measurement can precede `UIRoot:Init`.

**Component-specific signals:**

| Component | Signal constant | Payload |
|---|---|---|
| `Input` | `Components.INPUT_SIGNALS.SUBMITTED` | `text` |
| `ColorPicker` | `Components.COLORPICKER_SIGNALS.COLOR_PICKED` | `r, g, b, a` |
| `ColorPicker` | `Components.COLORPICKER_SIGNALS.REQUEST_CLOSE` | — |
| `Modal` | `Components.MODAL_SIGNALS.CONFIRMED` | `inputValue` or `nil` |
| `Modal` | `Components.MODAL_SIGNALS.CANCELLED` | — |
| `ResizeGrip` | `Components.RESIZEGRIP_SIGNALS.DRAG_START` | — |
| `ResizeGrip` | `Components.RESIZEGRIP_SIGNALS.DRAG_STOP` | — |

---

## Settings UI

### Unified Window (`SettingsUI/SettingsWindow.lua`)

Layout: fixed left nav (plugin list) + right content area.
Nav auto-populates from all registered plugins in registration order.
Selecting a plugin renders its page via PageBuilder.

### Opening it (`SuuUI.SettingsWindow`)

```lua
SuuUI.SettingsWindow.Open()      -- builds on first use, then shows
SuuUI.SettingsWindow.Toggle()    -- what /suuui and the minimap button both call
SuuUI.SettingsWindow.IsShown()   -- false while the window has never been opened
```

The window is built **lazily** — the first open registers the core schemas, creates the window
and builds the nav — and that sequence used to live inside the slash handler. Anything else that
wanted to open the window therefore had to call `SlashCmdList["SUUUI"]()`: reaching into a
global command table for behaviour that had no other name, dragging the command's argument
parsing along with it, and depending on a global some other addon is free to overwrite. Once
the minimap launcher moved out into its own plugin it needed a seam that was actually part of
the addon's API, so the lazy build now sits behind a single `ensureWindow()` and the two entry
points — `/suuui` with no argument, and a left click on the minimap button — both go through
it. There is one implementation of "build it if it does not exist yet", which is the property
worth having.

`IsShown()` is a function rather than a field because it has to answer for the not-yet-built
case: before the first open there is no window object to ask, and it reports `false` instead of
constructing one just to be interrogated. Anything that wants the window on screen should call
`Open()` — do not test `IsShown()` first and build around it.

The other slash arguments are edit-mode controls and do not touch the window at all:
`/suuui toggle`, `/suuui lock` and `/suuui unlock` drive `SuuUI.ToggleUI` directly.

### Page Builder (`SettingsUI/PageBuilder.lua`)

Reads schema, maps each entry to a control renderer, mounts in a ScrollFrame.
Schema order = render order. Controls read/write through Settings API.
No plugin writes any UI code for standard settings.

---

## Bundled Plugins

The sections above document the *machinery*. This one is an inventory of what ships on top of it,
because several first-party plugins carry decisions that only make sense written down.

### `action_bars` (`Plugins/ActionBars/`)

Thirteen action bars plus two class bars, on SuuUI's own secure buttons. Exports
`SuuUI._ActionBars.BARS`, `.slotsFor`, `.bindingsFor`, `.Paging`, `.Suppress`.

**Every slot block was measured in game, and the mapping has no rule to infer.** Bar 1 is slots
1–12 and *pages*; the four multibars are fixed to 61–72, 49–60, 37–48 and 25–36. `MultiBarLeft` is
`MULTIACTIONBAR4` while `MultiBarRight` is `MULTIACTIONBAR3` — the reverse of the obvious guess,
and the guess shipped until Blizzard's own `buttonType` field was read.

Because pages 3–6 of bar 1 land on the very slots the other bars own, **two SuuUI buttons can
legitimately address one slot** — which is why the button index maps a slot to a *set* of buttons,
and why **only bar 1 gets a state driver**.

**Bars 9–13 cover the sixty slots no Blizzard bar exposes** (pages 2 and 7–10, slots 13–24 and
73–120). They carry `ownBindings = true` and SuuUI's own `bindingPrefix`, because the client ships
no binding family for slots it has no bar for. On a real character, 27 of 72 abilities lived in
that range and were unreachable before those bars existed.

The two class bars take **string** ids (`"pet"`, `"stance"`) deliberately: slots 13–24 would
naturally become "Bar 9", and a numeric id would have silently shared its settings keys. They also
carry a separate numeric `order`, because the dock sorts a stack by it and comparing a string with
a number is a hard error in Lua.

- **`pet`** — `ActionButton`s with `kind = "pet"`; slot count fixed at `NUM_PET_ACTION_SLOTS`.
  Visibility is a **secure state driver** (`[pet,nooverridebar,nopossessbar] show; hide`), because
  a pet is summoned, dismissed, killed and revived mid-combat and hiding a frame holding protected
  buttons is refused during a fight.
- **`stance`** — sized for a paladin's **eight** auras, the widest case, measured. On by default
  unlike bars 3–8, because it is a class control Blizzard also shows by default. A plain `Hide` is
  enough here rather than a driver: the form *count* only changes at a trainer.

**`Suppress.lua`** hides Blizzard's bottom cluster and hands it back exactly. The constraint the
plan did not anticipate: **hiding a Blizzard action bar is itself protected**, since `MainMenuBar`
holds buttons inheriting `SecureActionButtonTemplate` and refusal propagates back up. So does the
restoring `Show()`, which matters more — that is the escape hatch. Targets are **candidate lists**,
never literals, and every matching name is hidden: this client has both `MainMenuBar` (the art) and
`MainActionBar` (the buttons), and stopping at the first match hid the gryphons while twelve buttons
stayed on screen. `Verify()` then asks **witness buttons** directly, because hiding a container is
the means and a button off the screen is the end.

**`Paging.lua`** is bar 1's page driver — a secure snippet, not an event handler. See "State Drivers
Are A Plugin-Level Carve-Out" in `WOW_API_ENCAPSULATION.md`.

### `watch_bars` (`Plugins/WatchBars/`)

Experience and reputation: **one widget shape, two instances**. Rested experience and the reputation
standing are the only differences that reach the component — which is why `StatusBar` grew a
secondary fill rather than this plugin stacking a second bar of its own.

Both hide when they have nothing to say, and **the conditions are not the same shape**: experience
hides at max level *or* when experience is switched off (a trial account) — two separate reasons for
one outcome, and a bar checking only the level would still show for the second. Reputation hides
when nothing is watched. Hiding is a plain `Show`/`Hide`, not a state driver: neither bar holds a
protected button, so there is nothing the client would refuse mid-combat. That is the difference
from the pet bar.

**Reputation is measured within the standing's band**, not against a 0..max range — 4500 of 6000 is
75%, but inside the 3000–6000 Revered band it is halfway. At max standing the client reports the
same number for the band's floor and ceiling, so the bar draws **full** and reports `capped`; an
earlier version returned nil there and hid itself, making an Exalted faction look identical to no
faction at all.

### `inventory` (`Plugins/Inventory/`)

One flat searchable grid of every bag slot, replacing Blizzard's five separate bag frames — plus a
second live window at a banker, a sell-greys button, and a read-only browser for every other
character on the account. `Inventory.lua` owns the plugin, `InventoryWindow.lua` is the renderer,
`Sell.lua` the throttled sale loop, `Suppress.lua` the bag-frame replacement.

**`InventoryWindow` is instantiated at most twice and is the same renderer three times over**: live
bags, a live bank during a session, and any character's snapshot. That is the central structural
decision — a fix to the grid fixes all three — and it is why the window is parameterised by
`{ character, container }` rather than existing in three variants.

**Nothing here is secure, which is the big simplification.** Unlike the action bars, item buttons are
ordinary frames and every call the window makes is unprotected: `PickupContainerItem` and its pair
are callable, verified on this client (ElvUI's sorter drives them from an `OnUpdate`). So no combat
lockdown, no deferred geometry, no attributes-once rule. Do not carry that machinery over out of
habit.

**But the cells DO inherit `ContainerFrameItemButtonTemplate`, and SuuUI must not touch their click
path.** Using an item is protected, so the template's own untainted `OnClick` is the only thing that
can perform a pickup, place, split, sell, deposit or use. A cell therefore calls `SetID`, observes
with `HookScript`, and calls **no** `RegisterForClicks`, no `SetScript("OnClick")`, and adds no
secure template — each of those was tried and each silently destroyed the working handler. Full
account, including the three failed approaches and the taint-source diagnostic, in
`.kiro/specs/inventory.md` §0.

**A cell's KIND is fixed at construction, and there are two.** A live cell carries the template; a
**snapshot** cell carries none, gets no `SetID`, and owns its own tooltip from the cached link. That
is not symmetry for its own sake: an alt's cached `(bag, slot)` are real coordinates addressing
**whoever is logged in**, so one template cell showing an alt's slot 1 would sell *your* item in bag
0 slot 1. Two kinds makes that impossible by construction, which is also why read-only does not drop
a snapshot cell's mouse — it has no handler to stop, and taking its mouse would remove the hover its
tooltip needs.

### The account cache (`Core/ItemCache.lua`)

The account-wide record of which character holds what, and where. **A Core service rather than a
plugin file**, for the reason `DataBar` and `Dock` are: two plugins read it — the inventory window
and the tooltip's account section — a plugin may never call into another plugin, and disabling the
inventory window must not silently stop the tooltip lines working.

```lua
SuuUI.ItemCache:Capture(which)      -- "bags" | "bank"; refuses an unreadable read
SuuUI.ItemCache:Get(key, which)     -- one character's stored container
SuuUI.ItemCache:SeenAt(key, which)  -- freshness, per container
SuuUI.ItemCache:MoneyOf(key)        -- nil, not 0, for a character captured before money was stored
SuuUI.ItemCache:Characters()        -- ordered: current, then this realm, then others
SuuUI.ItemCache:ItemInfo(id)        -- the shared item table's entry
SuuUI.ItemCache:Find(id)            -- { { key, container, count } }, memoised
SuuUI.ItemCache:Total(id)           -- account-wide count
SuuUI.ItemCache:Resolve(id)         -- fill in an item the client finally named
SuuUI.ItemCache.NameFromLink(link)  -- the name inside an item link
SuuUI.ItemCache:Forget(key)
```

**Two tables, not one.** An account-wide `items` table keyed by item id holds the link, icon and
quality once; per-character slots are just `itemID × count`. At ~250 slots per character a 60-byte
link stored per slot per character is ~25 KB each and grows with every alt, and the shared table is
reused by the tooltip, the search index and the ledger for free.

Five properties are load-bearing, and each was learned by getting it wrong:

- **Upsert only ever fills in.** A live read can be thin, and blanking a name that already worked is
  invisible until a player opens an alt and finds a wall of nothing.
- **Capture REFUSES a read reporting no slots at all.** The `PLAYER_LOGOUT` sweep runs when the
  container API is already torn down, and it wrote `money = 0` and an empty slot table over a good
  snapshot — so a cached alt appeared in the dropdown with nothing in it. The discriminator is the
  SLOT count, not the item count: a character can genuinely have empty bags, but every character has
  a backpack.
- **The container API returns NO ITEM NAME.** `GetContainerItemInfo` answers icon, count, quality,
  link and id, so nothing stored a name and a cached character could not be searched at all — the
  filter matched zero items, silently. `NameFromLink` parses it out of the link, needing neither
  `GetItemInfo` nor an event.
- **`GET_ITEM_INFO_RECEIVED` fills in, and only for an id some character already holds.** The event
  fires for every item the client resolves for any reason — a tooltip, a chat link, an auction search
  — so acting on all of them would grow the account table with thousands of items nobody owns. The
  announcement (`SUUUI_ITEMS_RESOLVED`) is coalesced through the capture debounce, because the event
  fires once per item and a fresh login resolves dozens in a few frames.
- **`Find` is memoised, and the invalidation is the whole risk.** It walks characters × containers ×
  bags × slots, and it is on a hover path: the tooltip's account section calls it per item, so moving
  the cursor across an 80-cell grid calls it 80 times. Cleared by `Capture` and `Forget` and nothing
  else — resolving an item's name cannot move it between characters — and it hands out a copy, since
  the memo is what the next caller reads.

**The bank is only readable while the bank frame is open**, which is exactly when the second window
is on screen — so the live bank session *is* the capture window, and the freshness stamp is simply
"when you last stood here". A consequence worth stating: another character's bank is absent from the
cache until that character has visited a banker at least once, and there is no way to read it
retroactively.

**`BankFrame` must never be hidden** — neuter it (alpha 0, mouse off, `ClearAllPoints`). Its
`IsShown()` is meaningless as a state signal; ask `ItemCache:IsBankOpen()`.

### `tooltips` (`Plugins/Tooltips/`)

Reskins the CLIENT's tooltips and supplies the information colour the client withholds. It draws no
tooltip of its own — `Components/Tooltip.lua` is unrelated and not reusable for this.

**Three facts shape it, all measured on this client rather than assumed.** `GameTooltip` is **not
protected**, so nothing here needs a combat guard and adding one would be wrong.
`TooltipDataProcessor` **exists here and must not be used** — ElvUI excludes TBC from it, so a
design built on the modern API compiles and silently does nothing. And Blizzard's border is a
**NineSlice**, so `SetBackdrop` alone leaves a double frame.

**There is essentially one tooltip, not nine.** Item, spell, buff, debuff, unit, vendor and world
object are all the same `GameTooltip` with different lines, so one restyle covers them. Only
`ShoppingTooltip1/2`, `ItemRefTooltip` and `EmbeddedItemTooltip` are separate frames, and only the
last has different regions (an icon plus a real `IconBorder`).

**The client supplies almost no colour**, which is why the border signal is the substance rather
than decoration: name-line quality colour is all Blizzard provides. Quality comes from
`Game:ItemQualityColor` at **uncommon and above only** — a white edge on a dark panel reads as a
selected state and would fire on most tooltips — units from `Theme:GetUnitColor`, and auras from
`AuraBand.KINDS`'s rules **verbatim**, because a buff's border answers "can I take this off them"
(`isStealable`) while a debuff's answers "what removes this" (dispel type, red when untyped).
A spell gets no signal: this client has no spell→school API.

**The health bar is SuuUI's own `StatusBar`, inside the panel.** It drove Blizzard's
`GameTooltipStatusBar` first, which needed `SetScript('OnValueChanged', nil)` plus a re-hook to stop
its handler fighting ours — owning the bar deleted the only non-additive call in the plugin. The
price is that Blizzard's bar is suppressed (guarded `OnShow`) and the value is driven from
`UnitHealth`. It is a **stack** child, so it tracks the tooltip's width as lines are added, and it
is `Add`ed once with later shows going through `SetChildProps`.

**Readouts go through `Core/Readout.lua`.** An earlier version invented k/M abbreviation no other
bar uses, so a tooltip read `7.6k / 15.2k` beside a unit frame printing `7620 / 15240`.

Two things that cost real debugging time and are worth reading before touching this:

- **`GetLine` does not exist on a real tooltip** — it is a harness convenience, and calling it from
  shipped code raised on the first mouseover with the whole suite green. Lines are read through
  `tt.TextLeft<i>`. `00_harness_spec.lua` now fails if any shipped file calls a harness-only name.
- **A line appended from a hooked SETTER needs `tt:Show()`.** `SetUnitBuff` shows the tooltip
  itself, so an added line falls outside an already-measured box. A content script needs nothing.

### `data_bar` built-ins (`Plugins/DataBar/`)

The clock, framerate and latency readouts and the addon-button tray, plus two surfaces that replace
Blizzard clusters outright:

- **`MicroMenuWidget`** — the micro menu as one field per entry in the `left` section, which was
  measured empty (every other built-in is `center` or `right`), so the micro menu owns it.
  **Resolution is by candidate list and an unresolvable entry is SKIPPED**, never rendered as a dead
  field: `MICRO_BUTTONS` is nil on this client so nothing enumerates the strip, and `LFDMicroButton`
  is absent while `LFGMicroButton` is present. Entries call **panel APIs** rather than forwarding
  clicks into Blizzard's buttons — `frame:Click()` on a micro button is a silent no-op here — which
  is also what makes hiding those buttons safe.
- **`BagsWidget`** — one field reading `BAGS 27` in the `right` section, replacing the six-button
  bag row. It is a **built-in widget rather than a plugin of its own, and that is a correctness
  decision**: its first version was a separate `bag_bar` plugin, which put its settings on their own
  page instead of with every other field's *and* broke its own enable toggle one-way — it registered
  the toggle's watcher under its owner prefix, then called `UnwatchPrefix` on that same prefix when
  disabled, destroying the watcher that would switch it back on. A built-in cannot make that
  mistake: its toggle is an ordinary data-bar setting and the plugin re-runs `Enable` for it.

---

## Plugin Authoring Contract

External addon checklist:

1. `.toc`: `## Dependencies: SuuUI`
2. On own `ADDON_LOADED`: call `SuuUI:CreatePlugin({...})`
3. In `onInit`: call `SuuUI.Settings:Register(id, schema)`
4. In `onInit`: subscribe to events via `SuuUI.Events:On(...)`
5. In `onEnable`: hide/modify default Blizzard UI elements
6. In `onDisable`: restore default Blizzard UI elements
7. Never call into another plugin directly — communicate via EventBus

---

## UI Layout Best Practices

**Golden Rule: Always use Container-based layouts. Never manually position UI elements.**

### Why Container-Based Layouts?

Manual positioning with `SetPoint` chains creates:
- **Fragile code** — one change breaks the entire layout
- **Inconsistent spacing** — hardcoded offsets don't respond to theme changes
- **Broken responsiveness** — layouts don't adapt to container size changes
- **Maintenance nightmares** — tracking Y offsets and cumulative gaps manually
- **Plugin incompatibility** — different plugins use different spacing/positioning styles

Container-based layouts provide:
- **Automatic positioning** — children arranged by layout algorithm
- **Responsive sizing** — `width="fill"` adapts to available space
- **Theme integration** — uses token-based gap and padding values
- **Maintainability** — add/remove children without recalculating positions
- **Consistency** — all plugins use the same layout patterns

### Correct Patterns

```lua
-- ✅ CORRECT: Container-based vertical list
local list = SuuUI.Layout:CreateContainer({
  parent  = scrollContent,
  layout  = "flow",
  dir     = "vertical",
  gap     = SuuUI.Theme:GetToken("spaceXs"),
  padding = {top=8, right=8, bottom=8, left=8},
})

for _, item in ipairs(items) do
  local row = CreateFrame("Frame", nil, scrollContent)
  row:SetHeight(32)
  list:Add(row, { width = "fill" })
end

-- ✅ CORRECT: Two-column grid
local grid = SuuUI.Layout:CreateContainer({
  parent = contentFrame,
  layout = "grid",
  cols   = 2,
  gap    = 8,
  padding= {top=8, right=8, bottom=8, left=8},
})

for _, setting in ipairs(settings) do
  local control = CreateSettingControl(setting)
  grid:Add(control:GetFrame())  -- auto-sized to fit grid
end

-- ✅ CORRECT: Horizontal button row
local buttonRow = SuuUI.Layout:CreateContainer({
  parent = footer,
  layout = "flow",
  dir    = "horizontal",
  gap    = 8,
})

buttonRow:Add(cancelBtn:GetFrame(), { width = 80, height = 24 })
buttonRow:Add(okBtn:GetFrame(), { width = 80, height = 24 })
```

### Anti-Patterns (Forbidden)

```lua
-- ❌ FORBIDDEN: Manual Y-offset tracking
local y = -8
for _, item in ipairs(items) do
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(200, 32)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  y = y - 32 - 4
end

-- ❌ FORBIDDEN: Manual SetPoint chains
header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
footer:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -8)

-- ❌ FORBIDDEN: Conditional positioning hacks
if needsScrollbar then
  row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
else
  row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
end
```

### When to Discuss Extensions

If you need layout behavior that isn't supported:

**Don't**: Implement manual positioning workarounds  
**Do**: Document the requirement and propose a generic solution

Examples of features worth discussing:
- "I need buttons centered in the container" → alignment support
- "I need items to wrap to next line" → wrapping flow layout
- "I need this panel to be 40% of parent width" → percentage sizing
- "I need minimum 200px but expand if space available" → min/max constraints

Bring these up, design a generic API, implement it in the layout system,
and document it for all plugins to use.

---

## Testing

Every component, layout strategy and core subsystem has a spec under `Tests/spec/`, run
with `lua Tests/run.lua` from the addon root. **No change to `Components/`, `Layout/`,
`Core/` or `SettingsUI/` is done until the suite passes and the new behaviour is covered.**

The suite loads the real addon into a sandbox against a simulated WoW client that solves
the actual anchor graph, so specs assert real pixel geometry rather than intent — where a
label sits, whether a thumb stays inside its track, whether two rows overlap. That is the
only way to verify a layout engine, since placement is the thing it produces.

Full contract, spec checklist and harness API: `TESTING.md`.

---

## Performance Rules

- No table allocations inside `OnUpdate` handlers.
- Use frame pool for any repeated UI element.
- `OnUpdate` handlers unregistered when idle, re-registered on demand.
- Token values cached in local upvalues inside component closures after `ApplyTheme`.
- No `string.format` in per-frame code — pre-build display strings.
- SavedVariables written only on `PLAYER_LOGOUT` or explicit user save.
- Lua files: no block comments in shipped code. Public API gets `---` doc comments only.
- Minimize global lookups in hot paths — alias globals to locals at file top.

---

## SavedVariables

```
SuuUIProfiles  -- all profiles, account-wide (## SavedVariablesPerCharacter: no)
SuuUIConfig    -- per-character: active profile name, window positions
```

---

## Naming Conventions

| Thing              | Convention                          |
|--------------------|-------------------------------------|
| Lua locals         | camelCase                           |
| Module upvalues    | camelCase                           |
| Public API keys    | PascalCase                          |
| Event names        | `SUUUI_SCREAMING_SNAKE`             |
| Plugin IDs         | `snake_case`                        |
| Token keys         | `camelCaseWithPrefix`               |
| Pool type IDs      | `"pluginId.frameRole"`              |
| Frame global names | `"SuuUI_" .. pluginId .. "_" .. role` |
