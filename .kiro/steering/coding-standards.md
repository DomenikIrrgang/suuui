# SuuUI Coding Standards

## File Structure

Every Lua file follows this layout, in order:

```lua
-- 1. Local aliases for globals used in this file (perf: avoids global lookup)
local pairs, ipairs, type = pairs, ipairs, type
local tinsert, tremove = table.insert, table.remove

-- 2. Module upvalue
local M = {}

-- 3. Private helpers (no doc comment needed)

-- 4. Public API functions (--- doc comment required)

-- 5. Return or registration
return M
-- or: SuuUI.MyModule = M
```

## Component File Conventions

A component defines its own methods on its metatable first, then calls `InstallBase`
last, just before the constructor:

```lua
local CompMeta = {}
CompMeta.__index = CompMeta

function CompMeta:ApplyTheme() ... end
function CompMeta:Destroy() ... end
function CompMeta:Show() ... end          -- custom: drives an overlay and a fade

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Hide. Show is defined
-- above and survives.
SuuUI.Components.InstallBase(CompMeta, "_f")
```

`InstallBase(meta, field)` only fills gaps — it never overwrites a method the metatable
already defines, so calling it before the definitions would silently do nothing useful
and calling it after keeps every custom override. `field` defaults to `"_f"`; pass the
handle field that holds the widget (`"_window"` for `Modal`). Its `SetSize` deliberately
does not emit `SIZE_CHANGED`; that comes from the frame's own `OnSizeChanged` hook.

Backdrops go through `SuuUI.Backdrop.Apply` / `SetBg` / `SetBorder` and text through
`SuuUI.Components.Text`. Never re-implement a primitive inside a component — see
`WOW_API_ENCAPSULATION.md`.

## Anatomy of a Component

Every component in `Components/` follows this shape. A new one that departs from it is
almost certainly rebuilding something that already exists. Read `Components/NavItem.lua`
as the shortest complete example, `Components/Dropdown.lua` for one with pooled children.

```lua
local S = SuuUI.UISignals

local CompMeta = {}
CompMeta.__index = CompMeta

-- 1. Transient state: recolour only, never rebuild the backdrop table. Note what is
--    NOT here: the enabled state. A paint path must never branch on `_enabled` — see
--    "Disabled State" below.
function CompMeta:_paint()
    local B = SuuUI.Backdrop
    B.SetBg(self._f, self._hovered and "colorBgHover" or "colorBgAlt")
    B.SetBorder(self._f, "colorBorder")
    self._labelText:SetColor("text")
end

-- 2. Re-derive token-driven size. Font tokens are user-editable, so a height taken
--    once at construction goes stale and the content overflows. Skip when the caller
--    pinned a size. The frame's resize hook reports the new size onwards.
function CompMeta:_autosize()
    if not self._autoH then return end
    local h = SuuUI.Theme:GetControlHeight("sizeControlMd")
    if math.abs((self._f:GetHeight() or 0) - h) <= 0.5 then return end
    self._f:SetHeight(h)
end

-- 3. Full restyle: backdrop, owned child handles, colours, then re-derive the size.
--    No box:Layout() needed — see "Let the container track your children" below.
function CompMeta:ApplyTheme()
    SuuUI.Backdrop.Apply(self._f, { bg = "colorBgAlt", border = "colorBorder" })
    -- The event bus fires listeners newest-first, so a child handle's own subscription
    -- may not have run yet. Apply it explicitly or this component measures the old font.
    self._labelText:ApplyTheme()
    self:_paint()
    -- opacityDisabled is user-editable, so re-assert the disabled fade here too or a
    -- live token edit never reaches a control that is already sitting disabled.
    self:_applyEnabled()
    self:_autosize()
end

function CompMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._labelText:Destroy()   -- every handle this component owns
    self._box:Destroy()
    self._f:Hide()
end

-- 4. A custom SetSize drops token sizing, then InstallBase fills the rest. It goes
--    last so every override above survives. InstallEnable follows for the enabled
--    state; both are gap-fill only.
function CompMeta:SetSize(w, h)
    self._autoH = false
    self._f:SetSize(w, h)
end

SuuUI.Components.InstallBase(CompMeta, "_f")
SuuUI.Components.InstallEnable(CompMeta, "_f")

--- Creates a thing. Emits CLICKED (button), MOUSE_ENTER, MOUSE_LEAVE, SIZE_CHANGED.
-- @param props table  { label, w, h }
-- @param parent frame
-- @return table  handle
function SuuUI.Components.Thing(props, parent)
    local T = SuuUI.Theme
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Text-bearing, so the height is floored against the font metrics.
    f:SetSize(props.w or 160, props.h or T:GetControlHeight("sizeControlMd"))
    f:EnableMouse(true)

    -- 5. Resize hook BEFORE the host container adopts the frame, so the container
    --    chains onto it instead of replacing it. A parent layout resizes the frame
    --    directly and never calls the handle's SetSize, so this is the only place
    --    that sees a layout-driven resize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- 6. Internals are positioned by a host container. No SetPoint, ever.
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- 7. Compose. Text owns the font and colour tokens and re-measures itself.
    local labelText = SuuUI.Components.Text({
        text = props.label or "", size = "md", justify = "LEFT",
    }, f)
    box:Add(labelText, {
        valign = "center",
        inset  = { left = T:GetToken("spaceSm"), right = T:GetToken("spaceXs") },
    })

    local id = "thing_" .. tostring(f)
    handle = setmetatable({
        _f = f, _box = box, _eid = id, _enabled = true,
        _autoH = props.h == nil,   -- the caller did not pin a height, so tokens own it
        -- Keep the original field pointing at the region when you wrap it in a handle;
        -- callers and specs reach _label, while _labelText owns it.
        _label = labelText:GetFrame(), _labelText = labelText,
    }, CompMeta)

    -- 8. Blizzard scripts are translated into signals and never escape this file.
    f:SetScript("OnMouseUp", function(_, btn)
        if handle._enabled == false then return end
        S:Emit(handle, S.SIGNALS.CLICKED, btn or "LeftButton")
    end)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
```

The rules that shape it, and why:

| Do | Because |
|---|---|
| `SuuUI.Backdrop` for bg/border | a hand-built `SetBackdrop` table stops tracking `borderWidth` |
| `Components.Text` for any text | it re-measures on a `fontSize*` change; a raw font string does not |
| Compose existing components | `Notice` is a `Modal`; `Modal` is `Text` + `Input` + `Button`; `Window`'s close is a `Button` |
| `InstallBase` after your methods | gap-fill only, so custom overrides survive |
| `InstallEnable` for the enabled state | one fade covers every value state; a recolour only covers the parts you remembered |
| Host container for internals | `SetPoint` belongs to the four layout strategies alone |
| `_paint()` vs `ApplyTheme()` | a hover should not rebuild a backdrop table every frame |
| `GetControlHeight` for text | font tokens are user-editable; a literal height clips |
| Re-derive size in `ApplyTheme` | a height read once at construction goes stale and the content overflows |
| Apply owned handles explicitly | the event bus fires newest-first, so children may lag a theme change |
| Emit from the frame's resize hook | layout-driven resizes never go through the handle's `SetSize` |
| Destroy every handle you own | otherwise each rebuild leaks a theme subscription |

### Let the container track your children

`container:Add` connects to the child's `SIZE_CHANGED` and re-runs layout on its own —
but only when you hand it the **handle**. Pass `labelText` and a font-token change
re-measures the label, emits, and the box re-flows for free. Pass
`labelText:GetFrame()` and the connection lands on the frame, which never emits that
re-measure, so you have to call `self._box:Layout()` by hand in `ApplyTheme` and
`SetText` and remember to keep doing it.

```lua
-- ✅ preferred: the container follows the child's re-measure
box:Add(labelText, { valign = "center" })

-- ⚠️ raw region: works, but now every restyle path owes a manual box:Layout()
box:Add(labelText:GetFrame(), { valign = "center" })
```

Pass the handle unless you have a reason not to. `Components/NavItem.lua` does, and needs
no `Layout()` call anywhere.

**The handle is not always sufficient.** `Text` emits `SIZE_CHANGED` on a *height* change
only — it owns its height but lets the layout assign its width, and emitting on width
would loop against the container that just sized it. So a text change that keeps the same
height can leave a child at a stale width depending on how the layout sized it.
`Components/Divider.lua` hits this and calls `self._box:Layout()` after `SetText` and in
`ApplyTheme`; its spec fails without those calls, so they are load-bearing, not habit.

If you add a `SetText` path and are not certain, write the spec first: assert the label's
width after the change and see whether it needs the manual re-run. Do not add the call
speculatively, and do not assume you can drop it.

**Deliberate exception:** `Button` keeps a raw font string, because its autosize pipeline
measures through `SuuUI.TextMetrics` and pins the label width itself — `Components.Text`
would fight it. If you need a similar exception, say why in a comment at the call site.

## UI Layout Rules

**Everything is positioned by the layout engine. `SetPoint` lives only in the four
layout strategies** (`Layout/{Flow,Grid,Stack,Anchor}Layout.lua`) — not in
`SettingsUI/`, not in plugins, and not in components. Components lay out their own
internals with a host container:

```lua
local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
box:Add(label, { align = "center", valign = "center" })
```

No public handle exposes `SetPoint`. If a layout algorithm or property is missing,
implement it in the engine — see `LAYOUT_SYSTEM.md`.

```lua
-- ❌ FORBIDDEN: Manual positioning
btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -10)
row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
y = y - height - gap

-- ✅ REQUIRED: Container-based layout with theme tokens
local T = SuuUI.Theme
local container = SuuUI.Layout:CreateContainer({
  parent  = parent,
  layout  = "flow",
  dir     = "vertical",
  gap     = T:GetToken("spaceXs"),      -- use space tokens for gaps
  padding = {
    top    = T:GetToken("spaceSm"),     -- use space tokens for padding
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
  },
})
container:Add(btn, { width = "fill", height = 32 })
container:Add(row, { width = "fill" })
```

**Spacing token usage:**
- Use `spaceXs` (4px) for tight spacing - list gaps, compact UIs
- Use `spaceSm` (8px) for standard spacing - most containers, panels
- Use `spaceMd` (12px) for roomier rows and insets
- Use `spaceLg` (16px) for loose spacing - section separation
- Use `spaceXl` (24px) for major spacing - page-level separation

**Never hardcode a control height.** Font size tokens are user-editable, so a control
pinned to a literal height clips its own text once the font grows past it. Read the size
tokens instead, and floor text-bearing controls against the font metrics:

```lua
-- ❌ FORBIDDEN
row:Add(input, { width = 140, height = 22 })

-- ✅ REQUIRED: the component derives its own height from tokens
row:Add(input, { width = 140 })

-- ✅ REQUIRED when a container needs the number itself
local h = T:GetControlHeight("sizeControlLg")   -- max(token, fontSizeMd + spaceXs*2)
local n = T:GetToken("sizeControlSm")           -- no text: the token as-is
```

**Layout properties you MUST use:**
- `width = "fill"` — stretch to container width (respects padding)
- `width = number` — fixed pixel width
- `height = "fill"` — distribute vertical space (flow) or fill container (horizontal)
- `height = number` — fixed pixel height
- Omit property — use child's natural size

**When you encounter a layout need not supported by the current system:**
1. **STOP** — do not implement manual positioning workarounds
2. **DOCUMENT** — clearly describe what layout behavior you need
3. **DISCUSS** — bring it up for architectural discussion
4. **IMPLEMENT** — extend the layout system generically after agreement
5. **APPLY** — use the new generic solution

Example missing features to discuss:
- Alignment within container (left/center/right, top/middle/bottom)
- Wrapping flow layouts
- Percentage-based sizing (`width = "50%"`)
- Min/max size constraints
- Absolute positioning within container
- Z-order/layering control

## No Magic Numbers

**A visual value in code is a bug waiting to happen. Name it, or read it from the theme.**
Every size, spacing, colour, duration and font size that ends up on screen must come from
a theme token. Tokens are the design system: they are user-editable in the theme editor,
they cascade to every consumer, and they re-emit `SUUUI_THEME_CHANGED` so the UI re-derives
without a reload. A literal does none of that and has to be hunted down in every file that
copied it.

```lua
-- ❌ FORBIDDEN: literals decided locally
frame:SetSize(234, 66)
container:Add(bar, { width = "fill", height = 30 })
local gap = 2
tex:SetColorTexture(0.1, 0.1, 0.12, 1)

-- ✅ REQUIRED: tokens for design language, settings for a widget's own dimensions
local T = SuuUI.Theme
frame:SetWidth(SuuUI.Settings:Get("unit_frames", "player_width"))
container:Add(bar, {
  width  = "fill",
  height = SuuUI.Settings:Get("unit_frames", "player_health_height"),
})
local gap = T:GetToken("spaceXxs")
SuuUI.Backdrop.Apply(frame, { bg = "colorBgAlt", border = "colorBorder" })
```

**The token does not exist yet? Add it** — to `Themes/Default.lua`, `Themes/Modern.lua`,
and `SettingsUI/Controls/ThemeTokens.lua` so it is editable. Component-specific sizes are
welcome there (`sizeToggleW`, `sizeScrollbar` are precedents); a theme is where design
decisions live, not just colours.

### Token or setting?

Not every named number belongs in the theme. Ask what the value *is*:

| The value | Home | Why |
|---|---|---|
| Design language the whole UI shares — spacing scale, font steps, border width, surface colours, animation timings, the size of a shared control | **theme token** | One edit retints or re-scales every consumer |
| One plugin's own widget dimensions and behaviour — a unit frame's width, which bars it shows, where it sits | **plugin setting** (`Settings:Register`, with the number as the entry's `default`) | It describes that widget, not the design language, and a player wants it per profile and on that plugin's own page |
| A fact about the client — a power type's colour, a spell school's colour, a class colour, a level cap | **`Core/Game.lua`** (`SuuUI.Game`) | It is not a choice anyone gets to make. In the theme it would be a control that is wrong to touch; in a plugin it would be a second copy of a fact, and copies drift |

A plugin's own dimensions in the theme is a category error: the theme editor fills up with
one plugin's controls, every other theme has to carry values it does not use, and the
player cannot vary them per profile. A schema `default` is a perfectly good single
declaration of a number — it is named, discoverable, and editable.

A mode that selects between two value sources is a **token** (it is UI-wide design
language), but it is a boolean rather than a colour, because what it decides is WHERE a
colour comes from — the class table in `SuuUI.Game` or a colour primitive — not what the
colour is. `colorUseClassColors` is this case: it lives in the theme because "class-colour
units" is a look decision, while the class colours themselves are facts and live in
`Core/Game.lua`. A plugin resolves the pair through `Theme:GetUnitColor(key, unit)` and
never reads the flag directly.

Both sources are live, and code must react to either:

```lua
SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:Relayout() end, id)
SuuUI.Settings:Watch(pluginId, "player_width", function() self:Relayout() end, owner)
```

**Read tokens through the narrowest API available**, so a rename or a casing slip cannot
happen twice:

| Need | Use | Not |
|---|---|---|
| Pixel size of a text step | `T:GetFontSize("lg")` | `T:GetToken("fontSize" .. key:upper())` |
| Height of a text-bearing control | `T:GetControlHeight(sizeKey, fontKey)` | a literal, or the bare size token |
| Height of a text row | Let it hug its measured text | any literal row height |
| A backdrop colour | `Backdrop.Apply/SetBg` with a token key | `SetBackdropColor(r, g, b, a)` |

**Re-derive on `SUUUI_THEME_CHANGED`.** Reading a token once at build time and keeping the
number is the same failure as hardcoding it — the value is now stale the moment the user
moves a slider. Cache in `ApplyTheme()` and rebind there:

```lua
SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
```

**The narrow exceptions**, all of which must carry a comment saying why:
1. **Game data, not design** — Blizzard's own power-type colours, spell school colours,
   class colours, level caps. These are facts about the client, not choices the theme gets
   to make. They are not local literals either: they live in `Core/Game.lua` so a resource
   bar, a cast bar and a nameplate all read the same fact. See `architecture.md` §6d.
2. **A structural constant with no visual meaning** — an array index, a loop bound, a
   pixel-grid divisor, `0` / `1` identities.
3. **A defensive fallback** on a token read (`T:GetToken("spaceXs") or 4`), for code that
   must survive a hand-edited SavedVariable. Not needed for tokens that ship in every
   built-in theme, since user themes merge onto a built-in base.

**Tests follow the same rule**: assert against `H.token(...)`, `H.textWidth(...)`,
`H.lineHeight(...)`. A spec that hardcodes 234 passes for the wrong reason and fails the
moment a token moves — see `TESTING.md`.

## Disabled State

**A disabled control must look different from the enabled one in EVERY state it can be
in** — every value, selection, variant and focus combination. Not "usually different":
off-and-disabled has to differ from off-and-enabled just as clearly as on-and-disabled
differs from on-and-enabled. A user scanning a settings page decides what is live from the
pixels alone.

**One mechanism owns it: `SuuUI.Components.InstallEnable(Meta, "_f")`.** It fades the root
frame to `opacityDisabled` and drops mouse input. Never hand-write `SetEnabled`.

```lua
-- Extra per-component behaviour hangs off the hook, not off a bespoke SetEnabled.
function CompMeta:_onEnabledChanged(en)
    self._hit:EnableMouse(en)     -- an inner hit frame the root fade cannot reach
end
```

Why a fade and not a recolour: a recolour dims only the parts the component remembers to
dim. That is exactly how a disabled Toggle used to keep a fully saturated accent track
while only its knob greyed, and how a disabled Slider stayed pixel-identical to a live one
at every value. A root-frame fade is state-independent by construction — there is no value
or variant it can fail to cover.

The rules that follow from it:

| Rule | Because |
|---|---|
| Paint paths never branch on `_enabled` | the fade already carries the state; a recolour under a fade double-dims |
| Call `_applyEnabled()` from `ApplyTheme` | `opacityDisabled` is user-editable and must reach an already-disabled widget |
| Only the OUTERMOST handle fades | frame alpha cascades, so a composite delegating to a child multiplies the fades (0.4² = 0.16) — set `_fade = false` on the inner handle |
| A faded widget must be inert | dropping the root frame's mouse is not always enough: an EditBox takes mouse without `EnableMouse`, and pooled menu rows are separate frames |
| Never write an empty `SetEnabled` stub | `Dependency.Bind` guards with `if target.SetEnabled`, so a stub makes the guard pass and the caller believes the widget was greyed |
| No disabled surface tokens | a `colorBgDisabled` that resolved to the same value as `colorBgAlt` is what hid this whole bug class; `colorTextDisabled` survives for `Components.Text` only |

`Components.Text` is the one deliberate exception: it dims through `colorTextDisabled` and
sets `_fade = false`, because fading a label that is already disabled-grey leaves it
unreadable. Its root element is a `FontString`, which has no mouse to drop.

**Test every state, not one.** A disabled-state spec asserts `GetAlpha()` against
`H.token("opacityDisabled")` for each value the control can hold, plus that interaction is
genuinely inert. A single "it dims" test is how a component ships passing while one of its
states still looks live.

## Comments

Only `---` single-line doc comments on **public API functions**.
No block comments (`--[[ ]]`) in shipped code.
No inline comments on obvious code.

Doc comment format:
```lua
--- Brief description of what the function does.
-- @param name string  Description
-- @param value any    Description
-- @return bool
function M:DoThing(name, value) end
```

## Performance Rules

- **No table allocations in OnUpdate.** Pre-allocate scratch tables as upvalues.
- **Unregister OnUpdate when idle.** Use a shared ticker pattern:
  ```lua
  local frame = CreateFrame("Frame")
  local function onUpdate(_, dt) ... end
  -- enable:  frame:SetScript("OnUpdate", onUpdate)
  -- disable: frame:SetScript("OnUpdate", nil)
  ```
- **Alias globals at file top** for any global used more than once in the file.
- **Pre-build strings.** Do not call `string.format` per frame. Build display
  strings only when the underlying value changes.
- **Cache token values** in local upvalues inside component closures.
  Re-read only in `ApplyTheme()`, which is only called on theme change.
- **Avoid string concatenation in loops.** Use a table + `table.concat`.

## SavedVariables

- Write only on `PLAYER_LOGOUT` or explicit user action (Save button).
- Never mutate SV tables directly from component code — go through
  `SuuUI.Settings:Set` or `SuuUI.Profiles` API.

## Error Handling

- Use `assert(condition, "SuuUI: message")` for programmer errors (wrong API usage).
- Use `SuuUI.Debug(msg)` for non-fatal warnings, gated by debug flag.
- Never `error()` inside event callbacks or OnUpdate — it will freeze the client.
  Use `pcall` when calling plugin-provided callbacks:
  ```lua
  local ok, err = pcall(plugin.onInit, plugin)
  if not ok then SuuUI.Debug("Plugin init failed: " .. tostring(err)) end
  ```

## Frame Naming

Global frame names must follow: `"SuuUI_" .. pluginId .. "_" .. role`
Example: `"SuuUI_minimap_container"`, `"SuuUI_unitframes_playerFrame"`

Anonymous frames (pool frames, throwaway containers) use `nil` as name.

## Module Registration Pattern

Each subsystem file assigns itself onto the `SuuUI` namespace:
```lua
local M = {}
-- ... implementation ...
SuuUI.Theme = M
```

The `.toc` file controls load order. Subsystems must not `require` each other.
Dependencies are implicit via load order.

## WoW API Usage

**Raw WoW UI API is confined to `Components/`, `Layout/`, and `Core/UIRoot.lua`**, plus the
three engine files `WOW_API_ENCAPSULATION.md` whitelists (`Core/Pixel.lua`'s resolution
watcher, `Core/MoveableFrame.lua`'s drag overlay, `Animation/Animator.lua`'s `OnUpdate`
driver). UI construction code (`SettingsUI/`, plugin pages, controls) composes components
and containers only. Positioning calls are tighter still: only the layout strategies.
Full rules, including the allow-table and the narrow exceptions, in
`WOW_API_ENCAPSULATION.md` — that file is authoritative when the two disagree.

Two exceptions apply to plugins specifically, and they are not loopholes:

- **A bare grouping frame** — `CreateFrame("Frame", nil, parent)` with no styling, no
  scripts and no `SetPoint`, existing only so a container has something to lay out. Prefer
  `Layout:CreateContainer` even here.
- **Game data plumbing** — an invisible frame with `RegisterEvent` +
  `SetScript("OnEvent")`, plus `UnitHealth`/`UnitName`/`GetSpellInfo` and friends. Reading
  the game is not building UI.

The forbidden list below is about **building visible UI**: a styled frame, a texture, a
backdrop, a strata, mouse plumbing, or a Blizzard script used to wire one part of our UI to
another.

```lua
-- ❌ FORBIDDEN in UI construction code
local row = CreateFrame("Frame", nil, parent)
local tex = row:CreateTexture(nil, "ARTWORK")
tex:SetColorTexture(0.3, 0.3, 0.3, 1)
row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
row:SetFrameStrata("FULLSCREEN_DIALOG")
row:EnableMouse(true)
row:SetScript("OnClick", fn)

-- ✅ REQUIRED
local C = SuuUI.Components
local swatch = C.ColorSwatch({ value = T:GetToken("colorBg") }, parent)
container:Add(swatch:GetFrame(), { width = 24, height = 24 })
SuuUI.UISignals:Connect(swatch, SuuUI.UISignals.SIGNALS.CLICKED, openPicker)
```

Narrow exceptions: a bare unstyled grouping frame handed straight to a container,
`GetCursorPosition()` inside a component, and game data APIs in plugins.

- Only use Blizzard templates when there is no reasonable alternative
  (EditBox for text input is the main exception) — and wrap it in a component.
- When hiding Blizzard frames, use `frame:Hide()` plus a guarded `OnShow` hook for a frame
  that re-shows itself — never `frame:UnregisterAllEvents()`, which nothing can undo, so
  `onDisable` could never hand the frame back. Do NOT nil them or `frame:SetParent(nil)` —
  this can cause taint. See "Hiding Blizzard UI" in `plugin-authoring.md`.
- Check for frame existence before operating: `if frame and frame.Hide then`.
- If a needed widget does not exist, build it in `Components/` — do not inline it.

## UI Signals

**Never use Blizzard frame scripts to notify other UI elements.** Use
`SuuUI.UISignals`. Full contract in `UI_SIGNALS.md`.

```lua
-- ❌ FORBIDDEN: Blizzard script as UI wiring
container:GetFrame():SetScript("OnSizeChanged", function(_, w, h) resizeScroll(h) end)
toggle:GetFrame():SetScript("OnMouseUp", handler)

-- ✅ REQUIRED: signals
local S = SuuUI.UISignals
S:Connect(container, S.SIGNALS.SIZE_CHANGED, function(w, h) resizeScroll(h) end)
S:Connect(toggle, S.SIGNALS.VALUE_CHANGED, function(new, old) handler(new) end)
```

Components emit; consumers connect. Inside a component, translate the Blizzard script
into an emit:

```lua
hit:SetScript("OnMouseUp", function()
  local old = self._value
  self._value = not old
  self:_render()
  SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.VALUE_CHANGED, self._value, old)
end)
```

Always disconnect in `Destroy()`:
```lua
function CompMeta:Destroy()
  SuuUI.UISignals:DisconnectAll(self)
  SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end
```

Use `SuuUI.Events` for addon-wide state (theme, profile, settings) and
`frame:RegisterEvent` for WoW game data. Neither replaces UISignals for UI wiring.

## Pixel Grid

The UI is laid out in units, not pixels: one unit spans `physicalHeight / 768` pixels, so
a 1-unit border is 1.4 pixels at 1080p and renders as a grey smear. `Core/Pixel.lua` fixes
this by scaling the root to a whole-pixel grid and snapping every coordinate onto it. Full
rationale in `architecture.md`.

Two rules follow for code you write:

**Never do your own cursor scale math.** `GetCursorPosition()` is in raw screen
coordinates; a frame's `GetLeft`/`GetBottom` are in that frame's space. They differ by the
frame's effective scale, and the root carries one, so dividing by `UIParent`'s is wrong for
everything under it — a slider tracks ~40% too far at 1080p.

```lua
-- ❌ correct only while nothing in the chain has a scale, which is never
local cx = GetCursorPosition() / UIParent:GetEffectiveScale()

-- ✅ the space you are actually comparing against
local cx, cy = SuuUI.Pixel.CursorIn(track)
```

**Never call `SetScale` on your own frames.** A second scale in the chain puts units back
between pixels. `Core/Pixel.lua` owns the only one, on the root.

**One exception: `Presets.ScalePop`.** The prohibition is about a scale a frame *keeps* —
it breaks the pixel grid for the frame's entire lifetime. `ScalePop` is transient and
self-reverting: it scales up to `animPopScale` and back down to exactly 1.0 in a single
sequence, is never nested, never persisted, and never read back by layout. Because the
final value is 1.0, the grid is restored as soon as the animation settles.

This guarantee rests on the animator always writing an animation's final value even when
the target is hidden. Without that, a frame hidden mid-pop kept a fractional scale
indefinitely — precisely the persistent violation the rule exists to prevent. The animator
now guarantees the final write lands regardless of visibility (see `Animator.lua`'s
`applyValue`). Callers wanting no pop at all pass `scalePop = false` (Button, IconButton),
or set the `animPopScale` token to 1 to disable it UI-wide without code changes.

The rule stays absolute everywhere else: no other code path may call `SetScale`.

Snapping happens inside the four layout strategies, so component and page code needs no
calls. Reach for the helpers directly only where you produce geometry outside a strategy:

```lua
SuuUI.Pixel.Snap(v)   -- nearest grid step
SuuUI.Pixel.Floor(v)  -- must not overflow its space
SuuUI.Pixel.Ceil(v)   -- must not clip its content
SuuUI.Pixel.Line(v)   -- thickness, floored at one pixel so it never disappears
```

## Table Utilities

A small set of table helpers lives in `Core/Init.lua` as `SuuUI.Utils`:

```lua
SuuUI.Utils.DeepCopy(t)          -- recursive copy, no metatables
SuuUI.Utils.Merge(target, src)   -- shallow merge src into target
SuuUI.Utils.Find(t, predFn)      -- returns first matching value
SuuUI.Utils.Keys(t)              -- returns array of keys
```

Do not implement these inline elsewhere.

## Metatables

Component handles use metatables for method dispatch. The pattern:
```lua
local CompMeta = { __index = CompMeta }

local function CreateComp(props, parent)
  local self = setmetatable({}, CompMeta)
  -- ...
  return self
end
```

Do not use inheritance chains deeper than one level.

## Testing

**Every component, layout strategy and core subsystem has a spec. Run the suite before
calling a change done:**

```bash
lua Tests/run.lua                      # from the addon root
lua Tests/run.lua --filter Slider       # while iterating
```

- New behaviour needs a spec that would fail without the change.
- Changed behaviour means updating the existing spec, never deleting it.
- Geometry assertions derive expected values from theme tokens and `H.textWidth` /
  `H.lineHeight`, never from hardcoded pixels — a literal passes under one theme and
  lies under every other.
- Assert results, not intent: check the size and position a layout property produced,
  not that the property was stored.
- Behaviour that is arguably wrong but needs a decision gets pinned with a passing test
  for what happens today plus an `xit` naming the invariant. Never leave the suite red.

Full contract and spec checklist: `TESTING.md`.

## File Size Discipline

Rough target: **~200 lines** for component files, **~150 lines** for core files. Fewer
lines load faster, and every byte is read from disk at login.

**These are guidelines, not limits.** A cohesive component that needs 300 lines to be
correct is better than two files that have to reach into each other's internals to stay
in step. Split when the file is doing two separable jobs — that is why `Notice` lives
apart from `Modal` — not to hit a number. `ColorPicker`, `Container` and `Theme` are all
over target and are all one coherent thing each.

If you do split, a `-Internal.lua` helper alongside the main file is the pattern. Never
split a component in a way that puts `SetPoint`, backdrop building, or token resolution
outside the primitives that own them.
