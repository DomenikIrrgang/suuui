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

Types: `toggle` `slider` `dropdown` `color` `text` `keybind` `section` `subtabs`

Optional field on any entry:
```lua
validate = function(value) return true end
-- or: return false, "Error message shown in UI"
```

**`Register` states your schema; it is not the last word on it.** `Settings:Extend(pluginId,
entries)` appends to a plugin's schema afterwards and `Settings:Retract(pluginId, keys)` takes
entries back out, which is what lets a surface owned by one plugin carry a control contributed
by another — the data bar's page is the case that needed it. You will rarely call either
yourself: the surface doing the hosting makes those calls on your behalf from the data you
registered with it. Full account in "Where your widget's settings belong" under the data bar.

### A section is a collapsible group

A `section` entry is not a row. It used to render a labelled divider; it now opens an
**`Accordion`**, and every entry after it is built into that accordion's body until the next
section. Grouping is derived from the schema you already declare, so order is the whole API:

```lua
SuuUI.Settings:Register("my_plugin", {
  { key="enabled",   label="Enable",      type="toggle", default=true },  -- always visible
  { key="",          label="General",     type="section" },
  { key="showName",  label="Show Name",   type="toggle", default=true },  -- inside General
  { key="",          label="Health Bar",  type="section" },
  { key="barHeight", label="Height",      type="slider", default=39, min=8, max=60, step=1 },
})
```

- **A setting belongs to the section that precedes it.** Move a section and everything under it
  moves with it; insert one in the middle and you have re-homed every entry below it as far as
  the next section. There is no end marker and no nesting.
- **Entries before the first section stay on the page itself and are always visible.** That is
  where a plugin-level enable toggle belongs: it is not part of any group, and a player must not
  have to open a group to find the switch that turns the plugin off.
- **One group is open at a time**, per page and per subtab pane. Clicking the open group's header
  collapses it and leaves the page fully collapsed, which is how a long page is scanned by its
  headers alone.
- **The first section is open when a page is built** — snapped, not animated, so a page does not
  open with something already sliding that the player did not ask for.
- **Which group is open is session UI state**, remembered by label per page and per tab while the
  client runs and never written to the profile. Same rule as the open subtab below.

A schema with no sections builds a flat page exactly as before, so no plugin had to be edited to
gain this.

### Settings that depend on another setting

A control that only means something while another setting is on states that with
`enabledIf`, naming the key it depends on:

```lua
{ key="show_level",       label="Show Level",       type="toggle", default=true },
{ key="hide_level_at_max", label="Hide at Max Level", type="toggle", default=true,
  enabledIf="show_level" },
```

While the dependency is falsy the control is **greyed out, not hidden, and never
cleared** — its stored value still applies the moment the dependency comes back on, and a
control that vanishes leaves the player unable to see what it was set to. The widget
refuses the mouse, so the state is real rather than cosmetic.

Truthiness is not always the condition you need. A control that is live only for one
*value* of a dropdown, or only while a toggle is **off**, states that instead of inverting
the setting it depends on:

```lua
enabledIf = "player_show_level"                             -- the key is truthy
enabledIf = { key = "player_anchor", equals = "detached" }   -- the key equals a value
enabledIf = { key = "player_anchor", notEquals = "detached" }
```

`equals` compares with `==`, so `equals = false` is a valid condition and means exactly
what it says.

Do not gate a control on itself, and do not gate the control that switches the dependency
— that is the one the player needs in order to undo it.

Wired for `toggle` today; any control adopts it with one line, because the binder takes
handles rather than knowing the control type:

```lua
SuuUI._SettingsDeps.Bind(pluginId, entry, control, label)
```

### Grouping a page into tabs

A plugin that repeats the same settings for several similar things — one group per unit
frame, per bar, per module — uses `subtabs` instead of one long scroll. Each tab owns a
slice of schema:

```lua
SuuUI.Settings:Register("unit_frames", {
  { key="enabled", label="Enable Unit Frames", type="toggle", default=true },
  { key="unit", type="subtabs", tabs={
    { id="player", label="Player", schema={
      { key="",                   label="General",    type="section" },
      { key="player_show_name",   label="Show Name",  type="toggle", default=true },
      { key="",                   label="Health Bar", type="section" },
      { key="player_health_height", label="Height",   type="slider",
        default=39, min=8, max=60, step=1 },
    }},
    { id="target", label="Target", schema={ --[[ ... ]] }},
  }},
})
```

**Declare a setting once, in the tab it is rendered in.** `Register` walks a tab's
schema exactly like the top level, so a nested entry's `default`, range and `validate`
all work from there. Repeating the key at the top level "for the default" gives one
setting two declarations, and `Get` reads its default from one while the slider reads its
range from the other — they drift. `Register` logs a warning when it sees conflicting
defaults for one key.

Which tab is open is session UI state, not a preference: it is remembered per plugin
while the client runs and never written to the profile.

A key that needs a default and a home in the profile but no control — a position written
by `MoveableFrame`, say — uses `type="position"` or `type="internal"`, which the page
builder skips deliberately rather than warning about.

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

## Opening the Settings Window

`SuuUI.SettingsWindow` is the seam for anything that wants to put the settings window on
screen:

```lua
SuuUI.SettingsWindow.Open()      -- opens it, building it on first use
SuuUI.SettingsWindow.Toggle()    -- opens if closed, closes if open
SuuUI.SettingsWindow.IsShown()   -- whether it exists and is currently shown
```

Until there was a second way in, there was no seam at all. The window is built lazily —
register the core schemas, create the window, build the nav — and that sequence lived inside
the `/suuui` handler, so the only route in from anywhere else was `SlashCmdList["SUUUI"]()`:
reaching into a global command table for behaviour that had no other name. It also inherits
the slash command's argument parsing, so the call is only "open the settings" by accident of
which branch an empty string falls through to — pass the wrong string and you get edit mode
instead.

The minimap button is a separate plugin, so it needed something that is part of the addon's
API rather than a side effect of a command. Both callers now go through these three
functions, which is also what keeps the lazy build to a single implementation: a second
caller that built the window itself would be a second nav, disagreeing with the first about
which plugins exist. `Open` and `Toggle` build on first use, so there is nothing to wait for
and no login ordering to get right — call them whenever your own UI says to.

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

## Putting your UI inside another plugin's frame

Never reach for another plugin's frame. Ask for an **attach point** instead: the owner of a
frame publishes a named place, you subscribe to that name, and neither plugin needs to know
the other exists. This is also the only version that survives load order — whichever of you
loads second still gets told.

```lua
-- Consumer: a cast bar that wants to be part of the player unit frame
SuuUI.AttachPoints:Request("unitframe.player", function(provider)
  if not provider then
    -- The point is gone (that plugin was disabled). Detach and tear down; you are holding
    -- a child inside a frame that is about to be destroyed.
    teardown()
    return
  end
  local bar = buildBar(provider.frame)          -- parent it to the frame you are joining
  provider.Attach(bar, { position = "below" })  -- the OWNER places it and resizes itself
end, "my_plugin")

-- On teardown
SuuUI.AttachPoints:Release("my_plugin")
```

The callback runs **immediately** with the current provider (or nil) and again on every
publish and revoke, so there is nothing to read separately and no ordering to get right.

Publishing one is the mirror image. Keep placement yours — hand out a parent frame and take
the child, never your containers:

```lua
SuuUI.AttachPoints:Publish("myplugin.panel", {
  frame  = myWrapper,
  Attach = function(child, opts) mySlot:Add(child, { width = "fill" }); self:_syncSize() end,
  Detach = function(child) mySlot:Remove(child); self:_syncSize() end,
})

-- In onDisable, BEFORE destroying anything
SuuUI.AttachPoints:Revoke("myplugin.panel")
```

**If your frame is moveable, tell `MoveableFrame` how far it now extends past your own
content.** A stored position resolves against the frame's bounding box, so growing to hold
someone else's widget moves everything you own — and only on the edge your anchor does not
pin, so it looks fine in one configuration and broken in the other:

```lua
-- What the frame extends past its own content, per edge. Bands carry their gap with them.
function MyWidget:GetCoreInset()
  local gap = SuuUI.Theme:GetToken("spaceXs")
  local above = self:_slotHeight(self._slotAbove)
  local below = self:_slotHeight(self._slotBelow)
  if above > 0 then above = above + gap end
  if below > 0 then below = below + gap end
  return above, below
end

SuuUI.MoveableFrame:Apply(frame, {
  pluginId = "my_plugin", key = "position", defaults = { ... },
  coreInset = function() return widget:GetCoreInset() end,
})

-- After Attach/Detach changed the inset — compare the INSET, not the frame's height:
-- swapping a band from above to below leaves the height identical.
SuuUI.MoveableFrame:RefreshAnchor(frame)
```

Name points dotted and namespaced by your plugin (`"unitframe.player"`). `opts` is your own
vocabulary — document what you accept. Adding the child with `width = "fill"` is what makes
an attached widget exactly as wide as your frame and follow your own width setting without
the consumer ever reading it. See `architecture.md` §3b for the full contract.

### Aura bands share that inset with you

A unit frame's buff and debuff bands are placed by the same mechanism your attached widget
is, and that matters to you: **a band is one more entry in the frame's `GetCoreInset`**, so a
mob applying a second row of debuffs mid-fight grows the frame the same way your cast bar
attaching does. The frame re-anchors by exactly that much, which is what keeps the player's
stored position meaning "where my bars are" rather than "where the bounding box is". If it
did not, gaining a debuff row would shove the bars up under the player's cursor in the middle
of a pull.

The consequence for you is the one already stated above, sharpened: **compare the inset, not
the frame's height.** A band appearing above while your bar sits below changes both insets
and can leave the total height untouched, so a height comparison misses it and the frame
never re-anchors. `RefreshAnchor` is gated on the inset moving for that reason.

Each band carries two settings and no more, per unit:

| Key | Type | Meaning |
|---|---|---|
| `<unit>_<kind>_position` | dropdown | `"above"` ｜ `"below"` ｜ `"hidden"` — which side of the frame the band sits on, or nowhere. Buffs default above, debuffs below |
| `<unit>_<kind>_size` | slider | The icon edge in pixels (8–48, default 24). Dead while the band is hidden rather than silently ignored |

`<kind>` is `buffs` or `debuffs`; build the keys with `AuraBand.PositionKey(prefix, kind)` and
`AuraBand.SizeKey(prefix, kind)` rather than concatenating, so a third band is one entry in
`AuraBand.KINDS` and no edit anywhere else.

**How many rows a band takes is deliberately not a setting.** It follows from the icon size
and the frame's width, and the band wraps to as many rows as the auras need — a row count the
player could set would be a cap that silently hides auras, which is the one thing a debuff
display must never do. The icon edge is a plugin setting because it is a widget dimension; the
*gap* between icons comes from `spaceXxs`, because spacing is design language.

## Adding a widget to the data bar

The data bar is a full-width strip along the top of the screen, divided into a left, centre and
right section of fields. **A widget definition is data, not UI.** The bar owns the surface, the
dividers, the hover rail, the font step, the padding and one shared ticker; you describe what
your field should say and register it with `SuuUI.DataBar`, which is in Core so it answers
whether or not the bar plugin is loaded, enabled, or came up before you. Same division the
settings schema draws, and for the same reason: eight plugins each building their own field is
eight different paddings.

```lua
-- onInit: your widget's settings are yours, declared under your own plugin id.
SuuUI.Settings:Register("my_plugin", {
    { key = "show_gold", label = "Show Gold", type = "toggle", default = true },
})

-- Cheap and allocation-free: see the rule under GetText below.
local lastCopper, lastText
local function goldText()
    local copper = GetMoney() or 0
    if copper ~= lastCopper then
        lastCopper = copper
        lastText   = string.format("%dg", math.floor(copper / 10000))
    end
    return lastText
end

local GOLD = {
    id      = "my_plugin.gold",   -- namespaced, like a pool id or an event name
    label   = "Gold",
    prefix  = "GOLD",
    section = "right",
    order   = 100,
    events  = { "PLAYER_MONEY" },
    GetText = goldText,
    OnClick = function(field, button) openCurrencyPanel() end,
}

-- onEnable: register through the setting rather than once, so switching the widget off
-- removes the field immediately and exercises the unregister path the player actually uses.
SuuUI.Settings:Watch("my_plugin", "show_gold", function(on)
    if on then
        SuuUI.DataBar:RegisterWidget(GOLD)
    else
        SuuUI.DataBar:UnregisterWidget(GOLD.id)
    end
end, "my_plugin.gold", { immediate = true })

-- onDisable
SuuUI.Settings:Unwatch("my_plugin.gold")
SuuUI.DataBar:UnregisterWidget("my_plugin.gold")
```

Registering is enough. The bar subscribes to the registry rather than reading it once, so a
widget added at any point — during login, from a settings toggle, from an addon that loads
minutes later — appears without anyone being told about it.

**The definition, field by field:**

| Field | Meaning |
|---|---|
| `id` | **Required**, unique, namespaced with your plugin id. A duplicate id *replaces* the existing widget rather than raising, so a plugin re-registering on re-enable cannot take the client down from inside its own `onEnable` — the collision is logged through `SuuUI.Debug` instead |
| `label` | Human name for the widget. Nothing renders it today (see the note below) |
| `prefix` | Optional muted text drawn before the value — `"GOLD"`, `"FPS"`, `"MS"` |
| `section` | `"left"` ｜ `"center"` ｜ `"right"`, default `"left"`. An unknown value raises rather than being quietly filed under one |
| `order` | Ascending within the section, default 100. Ties break on `id`, so ordering is total and a bar's fields cannot swap places between logins |
| `events` | Game events that should refresh the field. The bar registers the union of every widget's events on one frame and refreshes only the widgets that asked for the event that fired |
| `update` | Seconds between refreshes, for a value **nothing announces**. Omit it whenever an event exists — a ticker where an event would do is a per-frame cost for nothing |
| `GetText` | `function() -> string [, tone]` — the value, plus an OPTIONAL tone as a **second** return value: nil ｜ `"success"` ｜ `"warning"` ｜ `"danger"`. See "A tone says what the reading means" below. **Required unless `Build` is given** |
| `Build` | `function(parent) -> handle` — custom visuals instead of a text field. The escape hatch; see below |
| `Refresh` | `function(field)` — refresh hook for a `Build` widget, called where `GetText` would be. Named `Refresh` rather than `Update` on purpose: a hook differing from the `update` interval by case alone is a footgun, and the convention here is that functions are PascalCase |
| `OnClick` | `function(field, button)` |
| `OnEnter` | `function(field)` — the field handle is passed, so `field:GetFrame()` is what you anchor a tooltip to |
| `OnLeave` | `function(field)` |
| `schema` | Optional array of settings-schema entries, rendered on the **data bar's** settings page rather than on yours. This field used to read "there is no such field", and the objection behind that was real: `Settings:Register` may be called only once per plugin, in `onInit`, while a widget may register at any point — during login, from a toggle, from an addon that loads minutes later — so there was no moment at which the bar's page could splice in a stranger's schema. Two changes removed it. A plugin's schema is now **extendable** rather than stated once, and the bar's page **reads the registry when it builds** rather than once at registration, so a widget arriving after the bar's `onInit` is picked up by the next build with nothing having to be spliced into a call that already ran. See "Where your widget's settings belong" below — your own page is still the default answer |

Everything you hand over runs through `pcall` and logs through `SuuUI.Debug`, because it is
plugin code on a shared path: one throwing `GetText` must not stop the tick loop and take every
other widget's refresh with it.

**Where your widget's settings belong.** Your own page, for everything that is a preference
about your feature — the example above declares `show_gold` under `my_plugin` and that is the
default answer. The bar's page is for the smaller set of settings that are about **the field on
the bar**: which section it sits in, what it reads there, the thresholds that decide its tone.
A player looking for those goes to the data bar's page, because that is the thing they can see;
sending them hunting through a plugin list for a control that governs one strip of text is the
kind of split that makes a settings window feel arbitrary. Declare those as `schema` on the
definition and the bar renders them alongside its own controls.

**How the contribution actually reaches the page.** Two calls on the settings registry, and the
bar makes both of them — you declare data and never call either yourself:

```lua
SuuUI.Settings:Extend(pluginId, entries)   -- append to a plugin's schema, creating it if absent
SuuUI.Settings:Retract(pluginId, keys)     -- remove them again
```

`Extend` appends your entries to the named plugin's schema, creating the schema when that plugin
has none yet, **skipping any key that is already present** — so the same definition arriving
twice, which is exactly what a re-register on re-enable does, adds nothing the second time
rather than producing a page with two of every control. It then fires `SUUUI_SCHEMA_CHANGED`,
which is what tells an open settings window that the page it is showing has more on it than it
did a moment ago. `Retract` takes the keys back out when your widget unregisters, and it also
drops **a section header left empty by the removal**, because a collapsible section with nothing
inside it is a control that opens onto nothing — the player reads it as a bug in the page rather
than as an absent widget.

**A schema entry may name an `owner`, and ownership stays with the contributor.** Set
`owner = "my_plugin"` on an entry and the **control renders on the bar's page** while the
**value lives in your own settings namespace** — `Settings:Get("my_plugin", key)` is still how
you read it, and the page writes there rather than into `data_bar`. That split is deliberate and
it is not a detail. It is your data: it stays profile-scoped to *you*, so a player switching
profiles gets your value moving with the rest of your plugin's state instead of with the bar's;
and it **survives the widget being unregistered**, so switching your field off and on again does
not silently reset the thresholds the player tuned. Parking the value under `data_bar` would tie
one plugin's configuration to the lifetime of another plugin's page, and the failure would show
up as settings that quietly forget themselves.

**The watcher owner string stays keyed to the PAGE's plugin id, not yours.** This is the subtle
part, so take it as a rule: a control the bar's page builds for your entry watches under
`Settings.ControlOwner("data_bar", kind, key)` even when the entry's `owner` is `my_plugin`.
`PageBuilder` drops a rebuilt page's watchers by calling `UnwatchPrefix` with that page's
prefix, so a watcher keyed to the contributor's id is outside the prefix the rebuild sweeps: it
survives, the rebuild adds another, and the page leaks **one watcher per rebuild** — a leak that
is invisible until every write and every profile switch is firing into a stack of destroyed
controls. The `owner` field decides where the **value** lives; the watcher owner decides who
**cleans the control up**, and those two answers are not the same one.

**`prefix` is optional, and the clock omits it deliberately.** `"14:32"` is self-evident, and a
muted `TIME` in front of it is noise on a strip where horizontal space is the scarce thing. Use
a prefix where the number alone is ambiguous — `1.2k` could be gold, honour or damage — and
leave it off where the format already says what it is.

**A field advertises a hover rail only when your definition declares `OnClick` or `OnEnter`.**
The rail is the "you can act on this" cue, so a pure readout and an interactive one look
different on purpose: painting it on a field that does nothing promises an interaction that is
not there. You neither ask for it nor switch it on — the bar derives it from your definition, so
what the field promises and what it does cannot drift apart. The clock and the latency readout
get one, because both explain themselves on hover; the framerate readout does not.

**`GetText` must be cheap and allocation-free.** It is called by a shared `OnUpdate` ticker as
well as on events, so it sits on the same per-frame path the performance rules cover: no table
allocation, and no `string.format` unless the value behind the string actually moved.
`Plugins/DataBar/TimeWidget.lua` is the reference. It computes an integer key naming the string
that *should* be on screen — `time()` rather than `date("*t")`, because the former returns a
number and allocates nothing where the latter allocates a table on every tick — compares that
key against the last one, and formats only on a change. The clock ticks twice a second so a
seconds display does not visibly stutter, which means most of those ticks format nothing at
all; the field then drops the unchanged write on top of that. Fold your settings into the key
as the clock does, or a format change waits for the next value change to appear.

**A tone says what the reading MEANS; the theme decides what it looks like.** Return it as
`GetText`'s second value and the field colours the value with the matching intent token —
`"success"`, `"warning"`, `"danger"`, or nil for the default text colour. Those four are the
whole vocabulary: you state that a reading is past a threshold and the theme states what past a
threshold looks like, so one retint moves every threshold colour in the addon at once.
Composing your own `|cff…|r` escape instead hardcodes a hue, bypasses that retint, and gives
every plugin author a different way to do one thing. There is no separate tone hook, on purpose:
returned together with the value, the two come from a single reading and cannot disagree about
what is on screen. Hand back the two values and stop — the bar captures both into locals,
because a Lua multi-return expands only in the last argument position (`architecture.md` 3c).

**Thresholds are your SETTINGS, not constants.** "Bad" is not a fact about the client — a player
on a laptop and a player on a desktop disagree about what 40 fps means, and someone on a 200 ms
baseline should not sit permanently in red — so a fixed threshold is a number that is wrong for
somebody. Declare them on your own page and read them in the tone decision:

```lua
local lastPct, lastText, lastTone

-- Chest durability as a percentage. One client call, and nothing allocated on a tick that
-- changes nothing.
local function readPct()
    local cur, max = GetInventoryItemDurability(5)   -- 5 = chest slot
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return math.floor(cur / max * 100)
end

local function toneFor(pct)
    local danger = SuuUI.Settings:Get("my_plugin", "dura_danger")
    local warn   = SuuUI.Settings:Get("my_plugin", "dura_warn")
    if type(danger) == "number" and pct <= danger then return "danger" end
    if type(warn)   == "number" and pct <= warn   then return "warning" end
    return "success"
end

local function duraText()
    local pct = readPct()
    if not pct then return "—", nil end
    local tone = toneFor(pct)
    -- The TONE is part of the cache key rather than derived separately, which is what makes
    -- dragging a threshold slider repaint on the next refresh instead of waiting for the
    -- percentage itself to move.
    if pct ~= lastPct or tone ~= lastTone then
        lastPct, lastTone = pct, tone
        lastText = pct .. "%"
    end
    return lastText, lastTone
end

SuuUI.DataBar:RegisterWidget({
    id      = "my_plugin.durability",
    label   = "Durability",
    prefix  = "DUR",
    section = "right",
    order   = 150,
    events  = { "UPDATE_INVENTORY_DURABILITY" },
    GetText = duraText,
})
```

`Plugins/DataBar/FpsWidget.lua` and `LatencyWidget.lua` are the shipped reference for this
shape, including the guards a client reading needs: both check the global exists before calling
it, and both reject a non-finite number with `v ~= v`, since NaN is a number and every
comparison against it is false — a `< 0` range check alone lets it through. Both are **built-in
widgets** rather than a separate plugin, so they read their own settings under the `data_bar`
plugin id; a third-party widget does the same thing under its own id.

**A widget must not build frames.** No `CreateFrame`, no textures, no `SetPoint`, and no
components of your own for the field itself: the bar owns the field, its tokens, its divider
and its rail, which is what makes eight widgets from eight authors line up. `Build` is the
escape hatch for visuals that genuinely have no textual form — a row of icons, a meter. It
returns a handle the bar adds to the section stretched to the bar's height, and if it returns
nothing the widget is skipped with a `Debug` line. Two things follow for a `Build` widget: the
bar does **not** refresh it at construction, so paint it in `Build` itself, and `OnClick` /
`OnEnter` / `OnLeave` are not wired for it — its handle is its own, so it owns its own input.

**Drop what you registered.** `UnregisterWidget` in `onDisable` alongside your `Unwatch` and
your `Events:Off`; a widget left registered keeps its `GetText` on the ticker after the plugin
that owns it is gone.

**Reading the bar's height.** Anything of yours that hugs the top of the screen has to move
down by it. `SuuUI.DataBar:GetOccupiedHeight()` answers 0 when there is no bar rather than
erroring, so you need no second code path, and `WatchHeight(cb, owner)` fires immediately and
again whenever the height moves — a font or size token edit changes it. It is a length in the
**UI root's** units: for one of your own frames that is the space you are already in, and for
a frame anchored to `UIParent` you must convert it (see `Pixel.Convert` in `architecture.md`
6c). Full registry contract in `architecture.md` 3c.

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
| `SUUUI_MOVEABLE_LIST_CHANGED` | — (a moveable frame was registered or unregistered) |

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
  color = "text", -- key: "text"|"muted"|"accent", or an intent: "success"|"warning"|"danger"
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

## Letting the player click a unit

Targeting a unit and opening its context menu are **protected**: the client refuses both
from addon code, so there is no `onClick` you could write that would work. Ask for a
`UnitClickArea` instead — it states the secure attributes the client acts on, and the menu
that opens is the client's own, with every entry that unit offers.

```lua
-- Parented to the ROOT, not to your frame. The rule below says why.
local root = SuuUI.UIRoot:GetRootContainer():GetFrame()
local area = SuuUI.Components.UnitClickArea({
    unit = "target",
    name = "SuuUI_my_plugin_click_target",   -- optional; follows the frame naming rule
}, root)

-- Its own host, on a frame that only resizes with the screen, and an anchor descriptor
-- carrying your frame's size — so the surface covers all of it and a right click anywhere
-- reaches the unit.
local host = CreateFrame("Frame", nil, root)
local box  = SuuUI.Layout:CreateContainer({ host = host, layout = "anchor" })
box:Add(area, { anchor = {
    point = "TOPLEFT", relativeTo = myWrapper, relativePoint = "TOPLEFT", x = 0, y = 0,
    width = myWrapper:GetWidth(), height = myWrapper:GetHeight(),
} })

-- On teardown, alongside your other handles
area:Destroy()
```

Left click targets, right click opens the menu. Connect `CLICKED` if your widget wants to
react to the click as well — it is emitted after the client has acted.

**If your frame resizes at runtime, the surface goes BESIDE it, not inside it.** This is the
rule to take away from this section, and it is invisible in the code you write: the surface is
built from a secure template, which makes it **protected**; protection propagates down to
descendants, and the refusal propagates *up*. So while `InCombatLockdown()` is true the client
refuses addon-driven geometry on any frame whose subtree holds the surface — your plain wrapper
included, with one secure grandchild. Nothing throws. The size call returns, the frame keeps
its old box, and the player gets `Interface action failed because of an AddOn` in chat.

`UnitFrames` shipped with the surface inside the wrapper and it took ten days to find. That
wrapper grows during a fight by design — an aura band gains a row when a debuff lands, a cast
bar attaches when a cast starts — so every growth was refused, the band was carved out of a box
frozen at its pre-combat height, and the frame's own bars were shoved down by the band's
height. `GetPreferredSize` returned 227 while `GetHeight` stayed 188, with `InCombatLockdown()`
true on every mismatch and false on every match.

Two things follow, and both are in the example above:

- **Parent the surface to the root container and anchor it to your frame.** The anchor is what
  keeps it covering the frame as the frame grows, including any aura bands, without the frame
  ever containing it. Its host container must sit on a frame that only resizes with the screen:
  host it on your resizing wrapper and the container chains onto that wrapper's
  `OnSizeChanged`, so every mid-combat resize re-lays out a protected child and sprays blocked
  actions into the player's chat.
- **Guard every geometry call on the surface with `InCombatLockdown()` and defer it to
  `PLAYER_REGEN_ENABLED`.** Set a flag, return, and catch up on leaving combat — do not
  attempt the call and lose, because a refused call costs the player a chat error you already
  knew was coming. Skipping is cheap here: the surface is invisible, so a stale one costs at
  most that a band strip which appeared mid-fight is not click-to-target until the fight ends.
  Clicking the bars keeps working throughout. `UnitFrame:_syncClickArea` is the reference
  implementation.

**Do not build the secure frame yourself.** `SecureUnitButtonTemplate`, `RegisterForClicks`
and the `type` attributes are component territory (see `WOW_API_ENCAPSULATION.md`), and
getting any of the three wrong fails silently: the surface still sizes, still takes the
mouse, and does nothing.

**Your specs cannot catch the lockdown mistake.** The harness models no combat lockdown, so
2728 assertions passed while this was broken in every fight. Assert the structure instead —
that the surface is not a descendant of the frame it covers — the way
`Tests/spec/41_unit_click_area_spec.lua` does.

**Edit mode needs no work from you.** The drag overlay sits five frame levels above the
frame's own children, so while the player is positioning a frame the click goes to the drag
rather than to the unit.

---

## Hiding Blizzard UI

Do this in `onEnable`, undo in `onDisable`. Never nil a Blizzard frame and never
`SetParent(nil)` it — both taint.

```lua
onEnable = function()
  if MinimapCluster then MinimapCluster:Hide() end
end,
onDisable = function()
  if MinimapCluster then MinimapCluster:Show() end
end,
```

**`onDisable` really does have to restore.** It is not only the path to a reload: a
`plugin:Disable()` from a settings watcher, another plugin, or a spec runs with nothing
behind it, and a frame left hidden there stays hidden for the rest of the session.

### A frame that re-shows itself

Most Blizzard frames show themselves again from their own events — entering the world,
changing power type, an Edit Mode client applying a layout. `Hide()` alone does not survive
that, so suppression needs a hook, and the hook needs a flag:

```lua
-- Keyed by frame: what THIS plugin is currently suppressing, and what it has hooked.
local suppressed, hooked = {}, {}

local function suppress(frame)
    suppressed[frame] = true
    -- HookScript cannot be undone, so the hook asks the flag on every show instead of
    -- assuming it should always hide. It also keeps Blizzard's own handler, unlike SetScript.
    if not hooked[frame] then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self)
            if suppressed[self] then self:Hide() end
        end)
    end
    frame:Hide()
end

local function restore(frame)
    if not suppressed[frame] then return end   -- never show a frame someone else hid
    suppressed[frame] = nil                    -- BEFORE the Show, or the hook undoes it
    frame:Show()
end
```

Three details are load-bearing, and each has a regression test:

- **Do not `UnregisterAllEvents()`.** Nothing in the API enumerates a frame's registered
  events, so unregistering is a one-way door: `onDisable` can never hand the frame back
  alive. The guarded hook is a complete suppression mechanism on its own — a hidden frame
  can only become visible through a show, and every show fires `OnShow` — so leave the
  registrations where Blizzard put them.
- **Clear the flag before the `Show()`.** The hook is permanent; restore in the other order
  and it hides the frame straight back on the way out.
- **Restore only what you suppressed.** With your feature switched off you never hid
  anything, and showing the frame anyway overrides whatever else did.

Both first-party plugins that suppress a Blizzard frame follow exactly this shape —
`Plugins/UnitFrames/UnitFrames.lua` (`PlayerFrame`, `TargetFrame`) and `Plugins/CastBars/CastBars.lua`
(`PlayerCastingBarFrame` / `CastingBarFrame`). Keep the existence check: a global whose name
changed between client generations is simply absent on the other one.

---

## Secure Action Bars

Everything else in this document assumes the client will do what you ask. A **secure** frame — one
built from `SecureActionButtonTemplate` or holding buttons that are — inverts that: the client
refuses calls it would normally accept, refuses them *only in combat*, and mostly refuses them
**silently**. A bar that works perfectly at a target dummy and does nothing in a fight is the
normal failure here, not an exotic one.

If you are building anything that casts a spell, uses an item, or shows the player's action slots,
read this section first. `Components/ActionButton.lua`, `Components/StanceButton.lua` and
`Plugins/ActionBars/` are the worked examples.

### Three failure modes, all silent

This is the single most useful thing to know, because it changes how you diagnose:

1. **A refused call in combat.** `SetAttribute`, `SetFrameRef`, geometry, `Show`/`Hide`,
   `SetOverrideBindingClick` — all refused while `InCombatLockdown()` is true. The player gets
   "Interface action failed because of an AddOn" at best, and nothing at all at worst.
2. **A throw inside a Settings watcher.** Watcher callbacks are `pcall`'d and logged through
   `SuuUI.Debug`, **which prints nothing with debug off**. A constructor that raises leaves the
   player with no bar and no message. Two separate bugs cost multiple rounds of wrong diagnosis to
   exactly this silence — use `SuuUI.Fault` for anything the player must know about.
3. **A protected function that is a no-op rather than an error.** `CastShapeshiftForm` was probed
   bracketed — read form 7, cast form 3, read form 7 again. No error, no message, no change.

**Assume any client function that changes game state is PROTECTED until you have proved otherwise,
and prove it by reading the state back rather than by watching for a complaint.** Two functions
were assumed callable this build and were not: `CastShapeshiftForm` and `TogglePetAutocast`.

### Attributes: state them once, and never cache the slot

```lua
f:SetAttribute("type", "action")
f:SetAttribute("action", props.slot)
f:SetAttribute("useOnKeyDown", wantKeyDown)
```

State every secure attribute **once, at construction**, and expose no way to re-point a live
button from Lua — the client refuses `SetAttribute` on a protected frame in combat, so a setter
that re-states an attribute is a setter that fails exactly when it is needed. Re-pointing is the
state driver's job (see the state-driver carve-out in `WOW_API_ENCAPSULATION.md`).

**Read the action slot from the `action` attribute on every refresh. Never cache it.** The secure
snippet rewrites that attribute *inside* the secure environment, where Lua cannot observe the
write. A button caching its slot in a local keeps drawing the spell it had before the player
changed stance. `GetAttribute` is a read and is never refused.

### `RegisterForClicks` and `useOnKeyDown` MUST agree

This invariant has been broken twice, in two different phases, with the identical symptom: **every
button looked perfect and did nothing.**

A `Button` fires for left-up alone until told otherwise, so `RegisterForClicks` is not optional.
But registering a phase is only half of it — the secure handler compares the `down` flag it is
given against `useOnKeyDown` and returns early when they disagree. Register release only while
`useOnKeyDown` says "act on the press", and the button never receives the phase the client acts
on.

- **Action buttons**: `RegisterForClicks("AnyDown", "AnyUp")`, `useOnKeyDown` from the
  `ActionButtonUseKeyDown` CVar (read through `pcall`; default to release, since `GetCVarBool` is
  absent on some client generations).
- **Pet buttons**: `RegisterForClicks("AnyUp")` and `useOnKeyDown = false` — one phase, because
  the right-click is forwarded and the client runs the handler once per registered phase. Two
  phases would forward twice and toggle autocast straight back.

A green suite will not catch this. Dragging keeps working throughout, because drag never goes
through that handler.

**Gate your `PostClick` observer on the same rule**, or a consumer sees two `CLICKED` signals per
click and anything counting them is wrong in a way that looks like a double-click.

**Never `SetScript("OnClick")` on a secure button.** The template owns that handler; replacing it
breaks the button silently — it still sizes, still takes the mouse, still reports as shown. Use
`HookScript("PostClick")` to observe.

### Reaching a protected function you cannot call

Forward the click into a trusted Blizzard button inside the secure environment. Pet autocast is
the worked example: `TogglePetAutocast` raised "blocked from an action only available to the
Blizzard UI" even from a hardware-event context, so instead

```lua
f:SetAttribute("type2", "click")
f:SetAttribute("clickbutton2", _G["PetActionButton" .. index])
```

and the *client* presses Blizzard's button, whose own trusted handler does the protected work.
This is the mechanism Clique uses for click-casting.

**A forwarded target must keep existing.** Blizzard's pet buttons are hidden with their container
— never destroyed, never unparented.

### Clearing art on a protected button

**`SetNormalTexture(nil)` is REFUSED**: `bad argument #2 to '?' (Usage: self:SetNormalTexture(asset))`.
Clear the art by fetching the Texture object through its getter, emptying it, and hiding *that*:

```lua
for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
    local tex = f[get] and f[get](f)
    if tex then tex:SetTexture(nil) tex:Hide() end
end
```

That throw happened during construction, which meant the bar was never built — and per failure
mode 2 above, the player saw nothing at all.

**Clear the texture, do not hide the region.** Hiding a frame inside a protected button is refused
in combat, and an action appearing or disappearing mid-fight is the ordinary case — so the hide
fires exactly when it cannot land. Keep the button live and mouse-enabled even for an empty slot:
a player drags an action *onto* an empty cell.

**Do not install `SetEnabled` on a secure button.** Disabling drops mouse input, which the client
refuses on a protected frame in combat — and `Dependency.Bind`'s `if target.SetEnabled` guard
would pass while nothing was actually inert. Render unusable instead.

**On teardown, `Hide()`.** Do not clear attributes and do not `SetParent(nil)`; both are calls the
client can refuse on a protected frame.

### Combat deferral is the caller's job, and it is all-or-nothing

The component refuses to guess. `ActionButton:SetSize` is refused in combat like any other
geometry, and the **caller** owns the deferral, because only the caller knows the whole grid has
to move together.

The pattern, from `ActionBars.lua`:

```lua
if type(InCombatLockdown) == "function" and InCombatLockdown() then
    p._pendingAttach = p._pendingAttach or {}
    p._pendingAttach[def.id] = def       -- a SET keyed by bar id, so repeats collapse
    return
end
```

then drain the set on `PLAYER_REGEN_ENABLED`.

**Defer the WHOLE transition, not just the visible part.** Deferring only the reflow left a bar
stranded: the moveable removed, the dock not yet anchoring, nothing holding it.

**Short-circuit a no-op before deferring it.** `SetSlots` has no equality check of its own, so it
always runs a geometry pass — and the client fires the form-count event on login and on changes
that leave the count alone. Deferring that would leave the bar waiting on the end of a fight for
no reason.

**Only protected things need deferring.** A font string showing or hiding is not protected, so
readout toggles apply immediately; only shape settings defer.

**Where a trigger can occur in combat, use a secure state driver instead of deferring.** A pet is
summoned, dismissed, killed and revived mid-fight, so pet-bar visibility is
`RegisterStateDriver(frame, "visibility", "[pet,nooverridebar,nopossessbar] show; hide")` — and
once a driver owns visibility, **never call `Show`/`Hide` on that frame from Lua**. Two owners
fight, and yours loses in combat anyway. Contrast the stance bar, where a plain `Hide` is enough
because the form *count* only changes at a trainer.

**Order matters on release.** Release the attach point and detach the dock *before* the moveable
goes back on, or both write the same anchor and the winner is whichever fired last. Revoke a
published point *before* teardown. `UnregisterStateDriver` *before* the frame goes, or the client
keeps evaluating a conditional against a frame that no longer exists.

### Keybindings

**A Blizzard binding family acts on the SLOT, not on the button.** Whatever is bound to
`ACTIONBUTTON1` fires `UseAction(1)` whether Blizzard's own button is on screen or not — which is
why suppressing Blizzard's bars never costs the player their keys, and why bars using a Blizzard
family need no binding code at all.

**Slots with no Blizzard family need your own names and explicit routing.** Declare them in
`Bindings.xml` (SuuUI declares `SUUUIBAR9BUTTON1`..`SUUUIBAR13BUTTON12` for the pages Blizzard
exposes no bar for), then route the key the player chose to a **click** on your secure button:

```lua
SetOverrideBindingClick(frame, false, key, "SuuUIBar9Button1", "LeftButton")
```

That is the only route to a protected `UseAction`; a Lua binding body calling it directly is
refused. Which means **every secure button needs a global name**, because the client resolves the
override binding by name — set `namePrefix` on the grid.

**Apply the keys from the grid's `CHILDREN_CHANGED` signal, not from an event.** A bar built in
combat has no buttons yet, so there is nothing to bind to — and catching up on
`PLAYER_REGEN_ENABLED` *races the grid's own catch-up on that same event*. The signal exists for
this.

**Clear and reapply the whole set; do not diff.** And `ClearOverrideBindings` when the bar is
destroyed: an override binding outlives the frame it was set on.

Register `UPDATE_BINDINGS` (or the old key keeps working until the next reload) and
`PLAYER_ENTERING_WORLD` (the first moment saved keys are readable).

### Suppressing Blizzard's own bars

**Hiding a Blizzard action bar is itself protected**, so it defers like everything else — including
the restoring `Show()`, which matters more than it sounds because that is the escape hatch.

**Resolve targets by candidate LIST and hide every name that exists**, not the first match. This
client has both `MainMenuBar` and `MainActionBar`: the first carries the art, the second holds the
buttons. Stopping at the first hid the gryphons and left twelve buttons on screen while the check
reported success. **Establish which frame holds the buttons by walking the parent chain from a
button** — the frame that exists is not always the frame that holds them.

**Never `UnregisterAllEvents`** — nothing in the API enumerates a frame's registered events, so it
is a one-way door and `onDisable` could never hand the frame back. **Never `SetParent(nil)`** —
reparenting a frame with protected children is protected too.

**Hook `OnShow` and consult your suppressed table on every call.** `HookScript` cannot be undone,
which is exactly what makes `Restore` possible — so **clear the flag before the restoring `Show()`**,
or the hook you cannot uninstall hides it again on the way out.

**Verify with witness buttons.** Hiding a container is the means; a button off the screen is the
end. Log the failure rather than raising: a stray visible button is cosmetic, not a reason to take
the plugin down mid-session.

### Participating in the dock

`SuuUI.Dock` asks a participant for exactly three things: `GetFrame()`, `GetWidth()`/`GetHeight()`,
and a `SIZE_CHANGED` signal. Anything satisfying that can dock — which is how the experience and
reputation bars joined a service written for action bars without the service changing.

**An anchor is the same dependency as parentage.** The client refuses geometry on a frame whose
movement would move a protected one, and does not care whether the link is a parent or a point. So
the *plugin* defers the dock/free transition; the dock itself carries no combat guard.

**Anchor, never contain.** Containing makes the dock's frame resize when a bar attaches — and the
dock holds protected buttons, so that resize is refused in combat.

**State `relativeTo` explicitly in every anchor descriptor.** Layout props live on the *frame*, so
a frame in two containers has one props table, and an anchor without `relativeTo` resolves against
whichever container applies it. That pinned every docked bar to the top of the screen once.

**Resolve a target's attach point through `Dock.PointFor(id)`.** Building the name from your own
prefix is what made an action bar silently fail to dock to a watch bar: the request went to a point
that never existed, and `Request`'s "not published yet" path looks identical.

**Refuse cycles in the settings validator, and bound the walk.** A circular anchor is a hard client
error, not a cosmetic fault. The walk must be bounded as well as identity-checked, because a
hand-edited profile may already contain a loop. Use `Dock.WouldCycleIds`, which spans plugins — a
walk that only knows about your own settings cannot see the half held by someone else.

**Do not coerce a participant id with `tonumber`.** Ids are not all numeric (`"stance"`, `"pet"`,
`"watch:xp"`), and coercing silently yields nil, which reads as "not docked".

### Two plugin-handle traps

**Never store your own state under `_def` on your plugin handle.** That name used to hold the
framework's own plugin definition, and a plugin that claimed it destroyed its own `onDisable` — no
error, because the hook was simply never called. Definitions now live in a private weak-keyed table
`Core/Plugin.lua` keeps off the handle, so the collision cannot recur, but the lesson stands: name
your state distinctly (`p._widgetDef`, `p._bars`).

**Do not pass `immediate = true` on the plugin's own top-level `enabled` watcher.**
`Plugins:autoEnable` already applies the stored value during the login pass, and an immediate
callback would run `onEnable` from inside the init pass — before other plugins' `onInit` had run,
which is the ordering the two phases exist to guarantee.

### Settings-schema traps that break a bar page

**Every subtab needs a non-nil `id`.** `SubTabs` builds `byId[tab.id]`, so a nil id raises "table
index is nil" and the **entire page build throws** — taking the top-level toggles with it,
including the suppression escape hatch. That shipped once and was caught by looking at the settings
window, not by a spec: asserting a schema is not asserting that it renders.

**Give suppression its own top-level toggle, outside any group.** A player whose bars are
misbehaving needs Blizzard's cluster back without disabling the plugin whose settings page they are
standing on.

**Never offer a control for a value the client owns.** The stance bar has no button-count slider,
because a slider would let a player set 12 and get 8. Read `GetNumShapeshiftForms()`; do not read
`NUM_STANCE_SLOTS`, which is an array bound (10), not what a class has.

### Scaling: share the event frame and the ticker

Ninety-six buttons with an event frame each would be ninety-six frames and ninety-six dispatches
for the same handful of events, and a per-button `OnUpdate` is ninety-six scripts running every
frame forever. Use **one** shared event frame and **one** shared ticker, registered while at least
one button is live and dropped with the last one. `pcall` every `RegisterEvent`: an event absent on
this client generation must not take the bar down.

Range has to be polled because nothing announces it — throttle it, and treat `inRange == nil` as
"range is not a question" rather than out of range, or every self-cast on the bar gets a danger
tint.

---

## Profile Data

Plugin-scoped data lives at `profile.plugins["my_plugin"]`.
Access via `SuuUI.Settings:Get/Set` for tracked settings, or directly via
`plugin:GetProfile()` for arbitrary plugin-private data.

Do not write raw tables to SVs yourself — they are written on PLAYER_LOGOUT.

### When something else owns the shape of your table

There is one case where `GetProfile()` is not merely permitted but **required**: a stored
table whose shape belongs to a third party that **mutates it in place**. That table cannot
live in the settings schema, and what makes it a rule rather than a preference is that both
plausible ways of trying are silent no-ops.

`Settings:Get` hands back the stored value itself, so a library that writes into the table it
was given has written straight *past* the store — nothing was notified, no watcher fired, and
the schema still believes the old contents. And `Settings:Set` cannot repair it afterwards,
because the value you would pass **is** the stored table: the equality check that suppresses a
redundant write compares it against itself, finds them equal, and returns having done nothing.
Neither route errors, and neither leaves a trace to notice.

`Plugins/MinimapButton/MinimapButton.lua` is the worked example. LibDBIcon owns its own
position and visibility store, and it writes `self.db.minimapPos = pos` on **every tick** of a
drag, so the table has to sit somewhere our change tracking is not in the path:

```lua
--- The LibDBIcon position/visibility store: plugin-private data whose shape something else
--- owns, so it lives in the profile rather than behind Settings:Get.
local function iconDB(p)
    local profile = p:GetProfile()
    profile.icon = profile.icon or {}
    return profile.icon
end
```

Being a profile sub-table, it is profile-aware for free and reaches SavedVariables on logout
with no write path of our own — which is the whole reason the answer is `GetProfile()` and not
a hand-rolled global.

The companion rule is not to store the same fact twice. LibDBIcon keeps its own `hide` mirror
in that table and reads it at register time, so the plugin **seeds** it from the `enabled`
setting on enable rather than persisting it independently: two stored copies of "is the button
shown" drift, and the one the player edits must win.

Generalised: **a stored table that something other than you writes into belongs in
`GetProfile()`, and any fact inside it that also exists as a setting is seeded from the
setting rather than mirrored.** Settings are for values you own end to end.

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
    and `Settings:Watch`. Game facts (class colours, reaction colours, power colours, spell
    school colours, level caps) are neither: read them from `SuuUI.Game` rather than copying
    them into your plugin. To paint a unit's colour — class-coloured when the theme says so,
    falling back to its reaction to the player for a unit with no class, and to a token when
    class colouring is off — call `Theme:GetUnitColor(token, unit)` rather than resolving that
    chain yourself. See "No Magic Numbers" in `coding-standards.md`.
13. **Test the UI you build.** A new component is not finished without a spec in
    `Tests/spec/`. Run `lua Tests/run.lua` before calling a change done. See `TESTING.md`.
14. **Secure frames refuse calls, in combat, silently.** If your plugin casts a spell, uses an
    item, or shows the player's action slots, read "Secure Action Bars" above before writing any
    of it. In particular: state secure attributes once at construction, read the action slot from
    the attribute rather than caching it, make `RegisterForClicks` agree with `useOnKeyDown`,
    never `SetScript("OnClick")` on a secure button, and assume any client function that changes
    game state is protected until you have proved otherwise by reading the state back.
