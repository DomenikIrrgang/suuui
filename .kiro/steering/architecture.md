# SuuUI Architecture

## Overview

SuuUI is a modular, full interface replacement addon for WoW Classic Anniversary TBC.
It consists of a Core addon and any number of plugins — either bundled inside this
folder or as separate addon folders that declare SuuUI as a dependency.

No external libraries. Everything is built from scratch.

---

## Directory Structure

```
SuuUI/
├── SuuUI.toc
├── Core/
│   ├── Init.lua          -- bootstrap, version, global namespace
│   ├── Game.lua          -- game facts: power colours, spell schools (never themeable)
│   ├── EventBus.lua      -- addon-wide pub/sub (theme, profile, settings)
│   ├── UISignals.lua     -- per-element signal system (Godot-style)
│   ├── UIRoot.lua        -- single fullscreen root, layer management
│   ├── Plugin.lua        -- plugin registry and lifecycle
│   ├── AttachPoints.lua  -- named places one plugin offers another to attach UI to
│   ├── Profile.lua       -- profile storage, CRUD, character linking
│   ├── Settings.lua      -- settings schema registry, value I/O, reactive watchers
│   ├── Fonts.lua         -- font registry: client faces, locale faces, LibSharedMedia
│   ├── Theme.lua         -- token system, theme registry, active theme
│   ├── Pixel.lua         -- pixel grid: root scale, snapping, cursor space conversion
│   ├── ReloadGuard.lua   -- confirmation modal for settings needing a UI reload
│   ├── ToggleUI.lua      -- edit mode state + moveable-frame registry
│   ├── MoveableFrame.lua -- mixin making a frame repositionable in edit mode
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
│   ├── ClickAway.lua     -- shared click-outside watcher for transient panels
│   ├── Button.lua        -- full custom button (no Blizzard template)
│   ├── Icon.lua          -- display-only texture, optional themed border, bevel trim
│   ├── IconButton.lua
│   ├── NavItem.lua       -- selectable labelled row (nav lists)
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
│   └── StatusBar.lua     -- progress/resource bar; fill is a fractional stack child
├── SettingsUI/
│   ├── SettingsWindow.lua -- unified settings window (left nav + content)
│   ├── PageBuilder.lua    -- auto-builds a settings page from schema
│   └── Controls/          -- per-type setting control renderers
│       ├── Row.lua
│       ├── Dependency.lua
│       ├── ColorPopup.lua
│       ├── ThemeTokens.lua
│       ├── Section.lua
│       ├── Toggle.lua
│       ├── Slider.lua
│       ├── Dropdown.lua
│       ├── Color.lua
│       ├── Text.lua
│       ├── Keybind.lua
│       ├── SubTabs.lua
│       ├── ProfileManager.lua
│       └── ThemeManager.lua
├── Plugins/               -- bundled first-party plugins live here
│   ├── UnitFrames/        -- UnitFrame.lua (widget, one per unit) + UnitFrames.lua (plugin)
│   ├── CastBars/          -- CastBar.lua (widget, one per unit) + CastBars.lua (plugin)
│   └── ...
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
`SUUUI_PLUGIN_DISABLED`. Deprecated: `SUUUI_EDIT_MODE_CHANGED` — still emitted for
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
  type     = "toggle",       -- toggle|slider|dropdown|color|text|keybind|section
  default  = true,
  -- type-specific:
  min=, max=, step=          -- slider
  options={}                 -- dropdown: array of {value, label}
  validate = function(v) end -- optional, returns true or error string
  transient = true           -- optional: session state, never saved (see 5b)
}
```

**API:**
```lua
SuuUI.Settings:Register(pluginId, schemaArray)
SuuUI.Settings:GetSchema(pluginId)
SuuUI.Settings:Get(pluginId, key)          -- stored value, else the schema default
SuuUI.Settings:Set(pluginId, key, value)   -- writes, notifies watchers, fires the event
SuuUI.Settings:Reset(pluginId, key)        -- resets to schema default
SuuUI.Settings:ResetAll(pluginId)
SuuUI.Settings:IsTransient(pluginId, key)
```

Event payload: `"SUUUI_SETTING_CHANGED"` → `pluginId, key, value, oldValue`

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

SuuUI.MoveableFrame:Apply(frame, {
  pluginId = "unit_frames", key = "player_position",
  displayName = "Player Frame",
  defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 },
  -- Only for a frame that grows around content it does not own (see below)
  coreInset = function() return aboveInset, belowInset end,
})
SuuUI.MoveableFrame:RestorePosition(frame)
SuuUI.MoveableFrame:ResetPosition(frame)
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
-- The "you cannot stop this" cue: the hairline outline a cast bar draws around itself and
-- its icon while a spell is uninterruptible. A light neutral rather than an intent colour —
-- it describes the spell, not a warning, and it has to stay readable over any fill colour.
colorShield      = "colorGray400"
-- A unit's health when class colouring is off or the class is unknown: an NPC, a totem,
-- the login moment before the class is available. Its own hue rather than a reuse of
-- Success — retinting "Success" to orange should not turn the health bar orange.
colorHealth      = "colorGreen500"

-- Tier 2: intent
colorAccent      = "colorBlue400"
colorAccentHover = "colorBlue500"
colorSuccess     = "colorGreen400"
colorDanger      = "colorRed400"
colorWarning     = "colorYellow400"
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
| 1 | the unit's class (`Game:UnitClassColor`) | every player, and anything the client reports a class for |
| 2 | its reaction to the player (`Game:UnitReactionColor`) | a mob, a critter, a quest giver, a totem — everything with no class |
| 3 | the named token | class colouring off, or no unit to ask about |

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
SuuUI.Pixel:Refresh()            -- recompute; emits SUUUI_PIXEL_GRID_CHANGED if it moved
SuuUI.Pixel:Attach(frame)        -- drive a frame's scale (UIRoot attaches the root)
SuuUI.Pixel:SetEnabled(bool)     -- scaling on/off; snapping stays on either way
SuuUI.Pixel:SetMultiplier(n)     -- override; nil returns to automatic
SuuUI.Pixel.grid / .mult / .scale / .multiplier / .physicalHeight
```

`Snap` is **idempotent**, which is load-bearing: `Container:Layout` re-runs its strategy
after hugging, and a non-idempotent rounding would drift on every pass and never settle.

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
SuuUI.Game:UnitClassColor(unit)       -- ClassColor(UnitClass(unit)), or nil
SuuUI.Game.REACTION                   -- { HOSTILE = 2, NEUTRAL = 4, FRIENDLY = 5 }
SuuUI.Game:ReactionColor(reaction)    -- the client's 1..8 standing -> {r,g,b,a}, or nil
SuuUI.Game:UnitReactionColor(unit)    -- ReactionColor(UnitReaction(unit, "player")), or nil
SuuUI.Game.SCHOOL                     -- PHYSICAL HOLY FIRE NATURE FROST SHADOW ARCANE
SuuUI.Game:SchoolColor(mask)          -- nil when the mask says nothing — callers fall back
SuuUI.Game:SchoolOf(spellId)          -- cached mask, or nil
SuuUI.Game:LearnSchool(spellId, mask) -- returns whether it changed what we knew
SuuUI.Game:LearnFromCombatLog()       -- reads the line being dispatched; returns spellId, mask
```

**Reaction colours are the answer for every unit that has no class** — a mob, a critter, a
quest giver, a totem. `UnitReaction` reports a full reputation standing (1 hated to 8
exalted) and `ReactionColor` collapses it onto **three** bands, because a health bar is
answering "can this thing hurt me" and the client's own colour table makes the same
collapse: keeping eight would give the player five shades that all mean "friendly". Hostile
takes everything at or below unfriendly, since that is the set that will fight you.

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
response.

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
  token; an unknown key degrades to `fontSizeMd` rather than raising.
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
- `NavItem` — selectable labelled row with hover/selected states, for nav lists.
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

Opened via: `/suuui`, keybind (configurable), minimap button.

Layout: fixed left nav (plugin list) + right content area.
Nav auto-populates from all registered plugins in registration order.
Selecting a plugin renders its page via PageBuilder.

### Page Builder (`SettingsUI/PageBuilder.lua`)

Reads schema, maps each entry to a control renderer, mounts in a ScrollFrame.
Schema order = render order. Controls read/write through Settings API.
No plugin writes any UI code for standard settings.

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
