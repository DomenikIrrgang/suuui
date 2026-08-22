# WoW API Encapsulation

## Mandatory Rule

**Raw WoW UI API calls live ONLY inside `Components/`, `Layout/`, and `Core/UIRoot.lua`.
UI construction code (SettingsUI, plugins, controls) must never touch the Blizzard API directly.**

**Positioning is stricter still.** `SetPoint`, `SetAllPoints`, and `ClearAllPoints`
belong to the four layout strategies alone — `Layout/FlowLayout.lua`,
`Layout/GridLayout.lua`, `Layout/StackLayout.lua`, `Layout/AnchorLayout.lua`. Not
`SettingsUI/`, not plugins, and **not components**. A component positions its own
internals by hosting a container on its own frame:

```lua
local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
box:Add(label, { align = "center", valign = "center" })
```

`SetPoint` is not exposed on component handles, containers, or windows. See
`LAYOUT_SYSTEM.md` for the strategies, child properties, and the raw-call translation
table. Missing a layout capability? Add it to the engine.

Code that assembles a screen describes *what* it wants. Code inside a component decides
*how* to make Blizzard render it. When those two mix, the theme system, layout engine,
and signal system all get bypassed.

---

## Where Each Layer May Call the WoW API

| Layer | Raw WoW UI API allowed? | `SetPoint` allowed? |
|---|---|---|
| `Layout/{Flow,Grid,Stack,Anchor}Layout.lua` | Yes | **Yes — only here** |
| `Layout/Container.lua` | Yes | Only to self-anchor its own frame |
| `Core/UIRoot.lua` | Yes — owns the single `UIParent` anchor | Only that one anchor |
| `Core/Pool.lua` | Yes | `ClearAllPoints` + `SetScale(1)` on release |
| `Core/Pixel.lua` | Yes — an invisible event watcher only, no visible UI | **No** |
| `Core/MoveableFrame.lua` | Yes — drag overlay internals, as a component would | **No** — hosts containers |
| `Animation/*` | Yes — one invisible `OnUpdate` driver frame | **No** — position animates through `container:SetChildAnchor`; `ScalePop` is the one sanctioned `SetScale` (transient, self-reverting to 1.0; see `coding-standards.md`) |
| `Components/*` | Yes — internal frame/texture/fontstring construction, but z-order via `UIRoot:SetLayer` | **No** — use a host container |
| `Layout/Window.lua` | Yes — z-order via `UIRoot:SetLayer`/`RaiseAbove` | **No** — use host containers |
| `SettingsUI/*` | **No** — compose components and containers only | **No** |
| `Plugins/*` | **No** for UI. Yes for game data (`RegisterEvent`, `UnitHealth`, ...) | **No** |

The three engine rows are narrow, and worth stating explicitly because a blanket "only
`Components/`, `Layout/` and `UIRoot`" reads as though they were violations:

- **`Core/Pixel.lua`** creates one frame that is never shown, purely to receive
  `DISPLAY_SIZE_CHANGED` / `UI_SCALE_CHANGED`. Event plumbing, not UI.
- **`Animation/Animator.lua`** creates one frame to hang `OnUpdate` on. It animates
  `alpha`, `width`, `height` and `scale` through the client's setters, but **position is
  animated through the layout engine** — `x`/`y` require a container and drive
  `SetChildAnchor`, so a tween never fights a strategy for the same anchor. `ScalePop` is
  the one sanctioned *transient* `SetScale`: self-reverting to exactly 1.0, and never
  nested. `Core/Pool.lua`'s `SetScale(1)` on release is the other sanctioned call — it
  restores the identity the pixel grid assumes, the exact inverse of `ScalePop`'s
  temporary departure. See `coding-standards.md` for the full carve-out rationale.
- **`Core/MoveableFrame.lua`** builds an edit-mode drag overlay, which is component work in
  everything but its folder. It gets the component licence and the component restriction:
  raw `CreateFrame`/`CreateTexture` for its own internals, but its overlay, backdrop and
  label are placed by host containers, and the frame's own position goes through
  `UIRoot:UpdateElementAnchor` — never `SetPoint` against `UIParent`.

**Placement never goes to `UIParent`.** The root carries the addon's own scale
(`Pixel:Attach`), so `UIParent` is a *different unit space*: the same offsets resolve
somewhere else at any pixel multiplier other than 1. A frame that positions itself states
its placement to `UIRoot` and lets `AnchorLayout` resolve it in root space.

Hiding Blizzard's own frames (`MinimapCluster:Hide()`) is a plugin responsibility and
stays allowed — that is not building our UI, it is suppressing theirs.

## Z-order Goes Through the Layer System

`SetFrameStrata` is `Core/UIRoot.lua`'s alone — it is the file that owns the ladder, and
the one place a client strata string may appear. Everywhere else, including `Components/*`
and `Layout/Window.lua`, names a layer:

```lua
-- ❌ a raw strata, decided locally, in the client's vocabulary
panel:SetFrameStrata("TOOLTIP")
overlay:SetFrameStrata("DIALOG")
closeBtn:SetFrameLevel(win:GetFrameLevel() + 10)

-- ✅ a layer, decided by the ladder
SuuUI.UIRoot:SetLayer(panel, "tooltip")
SuuUI.UIRoot:RaiseAbove(overlay, frame, 5)     -- same layer, higher level
SuuUI.UIRoot:AddElement(win, "window", anchor) -- layer + placement
```

Scattered strata strings are how two frames end up on the same rung by accident, and there
is no single place to read the resulting z-order back. Layer names in
`UI_ROOT_ARCHITECTURE.md`.

---

## Forbidden in UI Construction Code

```lua
-- ❌ Creating raw frames
local row = CreateFrame("Frame", nil, parent)
local btn = CreateFrame("Button", nil, parent)
local box = CreateFrame("EditBox", nil, parent)

-- ❌ Creating raw textures and font strings
local tex = frame:CreateTexture(nil, "ARTWORK")
tex:SetColorTexture(0.3, 0.3, 0.3, 1)
local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

-- ❌ Backdrops, strata, mouse plumbing
frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", ... })
frame:SetBackdropColor(0.1, 0.1, 0.1, 1)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetFrameLevel(100)
frame:EnableMouse(true)
btn:RegisterForClicks("LeftButtonDown")

-- ❌ Blizzard scripts as UI wiring
frame:SetScript("OnClick", fn)
frame:SetScript("OnUpdate", fn)
frame:SetScript("OnSizeChanged", fn)

-- ❌ Manual positioning
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -10)
frame:SetAllPoints(parent)

-- ❌ Hardcoded colors and sizes instead of tokens
tex:SetColorTexture(0.3, 0.3, 0.3, 1)
frame:SetHeight(28)
```

## Required Instead

```lua
local T = SuuUI.Theme
local C = SuuUI.Components
local S = SuuUI.UISignals

-- Components for anything visible
local label   = C.Text({ text = "Background", size = "sm", color = "text" }, parent)
local swatch  = C.ColorSwatch({ value = T:GetToken("colorBg") }, parent)
local input   = C.Input({ value = "1A1A1A", w = 80 }, parent)

-- Containers for all positioning
local row = SuuUI.Layout:CreateContainer({
  parent = parent,
  layout = "flow",
  dir    = "horizontal",
  gap    = T:GetToken("spaceXs"),
})
row:Add(label:GetFrame(), { width = "fill" })
row:Add(input:GetFrame(), { width = 80, height = 22 })
row:Add(swatch:GetFrame(), { width = 24, height = 24 })

-- Signals for all wiring
S:Connect(swatch, S.SIGNALS.CLICKED, function() openPicker() end)
S:Connect(input,  S.SIGNALS.TEXT_CHANGED, function(text) applyHex(text) end)
```

---

## Narrow, Documented Exceptions

These are the only cases where UI construction code may still call the WoW API:

1. **A bare grouping frame passed straight into a container.** A frame with no styling,
   no scripts, and no manual `SetPoint` — it exists only so a container has something
   to position.
   ```lua
   local row = CreateFrame("Frame", nil, parent)  -- OK: no styling, no scripts
   container:Add(row, { width = "fill", height = 28 })
   ```
   Prefer `SuuUI.Layout:CreateContainer` even here when the frame will hold children —
   a container is itself a frame, so `CreateContainer{ parent = p }` usually replaces
   the bare frame outright.

2. **`GetCursorPosition()` / `UIParent:GetEffectiveScale()`** when a component genuinely
   needs cursor math. This belongs in `Components/`, not in page code.

3. **Game data APIs** in plugins: `RegisterEvent`, `UnitName`, `GetSpellInfo`, and friends.

Everything else needs a component.

---

## Protected Actions Go Through A Secure Component

Some things the client will not let an addon do at all: targeting a unit, opening its
context menu, casting. They are **protected**, so there is no handler you can write — the
only route is a frame built from a secure template, carrying attributes that the template's
own click handler reads and acts on.

That makes secure templates component work, and `Components/UnitClickArea.lua` is the one
that owns it today. A plugin asks for the surface and places it; it never builds one.

```lua
-- ❌ FORBIDDEN in plugin code: a protected action the client will refuse anyway
frame:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then TogglePlayerMenu() end   -- protected; does nothing
end)

-- ✅ REQUIRED: the component states the attributes, the CLIENT performs the action.
-- Parented BESIDE the frame it covers, never inside it — see the parentage rule below.
local root = SuuUI.UIRoot:GetRootContainer():GetFrame()
local area = SuuUI.Components.UnitClickArea({ unit = "target" }, root)

-- Its own host, on a frame that only resizes with the screen, and an anchor descriptor
-- that carries the covered frame's size. Growing `wrapper` moves the surface with it.
local host = CreateFrame("Frame", nil, root)
local box  = SuuUI.Layout:CreateContainer({ host = host, layout = "anchor" })
box:Add(area, { anchor = {
    point = "TOPLEFT", relativeTo = wrapper, relativePoint = "TOPLEFT", x = 0, y = 0,
    width = wrapper:GetWidth(), height = wrapper:GetHeight(),
} })
```

Three rules follow for anyone extending a secure component. The first is the one that
actually costs days:

- **A secure component must never be parented inside a frame whose geometry changes at
  runtime.** A frame built from a secure template is protected, protection propagates DOWN
  to every descendant, and the refusal propagates UP: the client refuses addon-driven
  geometry on *any* frame whose subtree holds a protected one while `InCombatLockdown()` is
  true, so a plain wrapper with one secure grandchild is refused along with it. Nothing
  throws. The size call returns, the frame keeps its old box, and the player gets
  `Interface action failed because of an AddOn` in chat — a line most players have learned
  to ignore.

  This shipped. `UnitClickArea` was parented to the unit frame's wrapper, and that wrapper
  resizes during a fight by design: an aura band grows it when a debuff lands, the cast bar
  grows it when a cast starts. Every one of those resizes was refused, so the band was
  carved out of a box frozen at its pre-combat height and pushed the frame's own bars down
  by the band's height. Measured in the live client: `GetPreferredSize` returned 227 while
  `GetHeight` stayed 188, with `InCombatLockdown()` true on every mismatch and false on
  every match. Ten days of in-game debugging, because the mechanism is invisible in the
  code — the parentage line reads like an implementation detail.

  So the surface goes **beside** the resizing frame, parented to something stable (the root
  container) and **anchored** to the frame, which is what keeps it covering it. Its host
  matters too: hosting the surface's container on the resizing wrapper would chain onto that
  wrapper's `OnSizeChanged`, so every mid-combat resize would re-lay out a protected child
  and spray blocked-action lines into the player's chat. Give it a host that only resizes
  with the screen.

- **Geometry on a protected frame is guarded and deferred, not attempted.** Ask
  `InCombatLockdown()` first and set a flag; catch up on `PLAYER_REGEN_ENABLED`. Attempting
  it and losing is not free — it costs the player a chat error for a call you already knew
  would fail. `UnitFrame:_syncClickArea` is the reference: it skips in combat, records
  `_clickDeferred`, and re-runs on leaving combat. Skipping is honest rather than lossy
  there because the surface is invisible, so a stale one costs at most that a band strip
  which appeared mid-fight is not click-to-target until the fight ends.

- **Never `SetScript("OnClick")` on a secure button.** The template installs the handler
  that performs the action, and replacing it breaks every action silently — the frame still
  sizes, still takes the mouse, still reports as shown. Use `PreClick` / `PostClick`, the
  hooks the template offers, and translate those into signals.

- **State attributes once, at construction.** A frame built from a secure template is
  protected, and the client refuses to let an addon reshape a protected frame in combat. A
  setter that re-states an attribute is a setter that fails exactly when it is needed.

**A green suite proves nothing here.** The simulated client models no combat lockdown, so
2728 assertions passed while this was broken in every fight. What a spec *can* assert is the
structural invariant — that the secure surface is not a descendant of the frame it covers —
and that is what `Tests/spec/41_unit_click_area_spec.lua` does. See "Known Gaps in the
Simulated Client" in `TESTING.md`.

---

## Missing a Component? Build It.

When a page needs a visual element the library does not have:

1. **Stop** — do not inline `CreateFrame` + `CreateTexture` in the page.
2. **Name it** — what is the reusable widget? (`ColorSwatch`, `Badge`, `SegmentedControl`)
3. **Discuss the props** — what does its `props` table accept?
4. **Implement** in `Components/<Name>.lua` following the standard shape. The full
   annotated skeleton is **"Anatomy of a Component" in `coding-standards.md`** — start
   there and copy it rather than assembling the rules below from scratch:
   - `(props, parent)` signature returning a metatable handle
   - Shared API: `SetSize` `GetWidth` `GetHeight` `Show` `Hide` `IsShown` `SetEnabled`
     `Destroy` `GetFrame` `ApplyTheme` — **no `SetPoint`**
   - Internal parts positioned by a host container, never by `SetPoint`
   - Backdrop via `SuuUI.Backdrop.Apply(f, { bg, border })`, recoloured with
     `SetBg` / `SetBorder` — never a hand-built `SetBackdrop` table. A rounded surface goes
     through `SuuUI.Backdrop.Pill` / `Circle` / `CircleMask` instead: a backdrop's corners
     are square by construction, so rounding one is not a matter of styling it differently
   - Shared accessors installed with `SuuUI.Components.InstallBase(Meta, "_f")`, not
     retyped by hand
   - Enabled state installed with `SuuUI.Components.InstallEnable(Meta, "_f")` — never a
     hand-written `SetEnabled`, and never a raw `SetAlpha` for the disabled fade
   - Text via `SuuUI.Components.Text`, so it re-measures on a `fontSize*` change
   - Token-driven colors and sizes, cached in `ApplyTheme()`
   - Blizzard scripts translated into `SuuUI.UISignals` emissions
   - `Destroy()` calls `SuuUI.UISignals:DisconnectAll(self)` and `SuuUI.Events:Off(...)`
5. **Register** it in `SuuUI.toc` load order and `SuuUI.Components`.
6. **Spec** it in `Tests/spec/` — geometry, token-driven sizing, every signal, disabled
   state, theme reaction, edge cases, teardown. See `TESTING.md`.
7. **Document** it in `architecture.md` under Component Library.

A one-off inline frame in a page is always cheaper today and always more expensive
later. Build the component.

---

## Duplicating a Primitive Is Also a Violation

Being inside `Components/` licenses the raw API, not the copy-paste. A component that
hand-rolls something a shared primitive already does is the same failure as a page that
hand-rolls a component: the fix has to be made in fifteen files instead of one, and one
of them is always missed.

```lua
-- ❌ the backdrop table, the texture path, and the token resolution, per component
local c  = SuuUI.Theme:GetToken("colorBg")
local bc = SuuUI.Theme:GetToken("colorBorder")
local bw = SuuUI.Theme:GetToken("borderWidth") or 1
f:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = bw,
    insets   = { left = bw, right = bw, top = bw, bottom = bw },
})
f:SetBackdropColor(c[1], c[2], c[3], c[4])
f:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])

-- ✅ one primitive, tokens resolved for you
SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })

-- ✅ and a hover or selection flip recolours without rebuilding the table
SuuUI.Backdrop.SetBg(f, "colorBgHover")
```

Same for the accessors (`InstallBase`), text (`Components.Text`), and text measurement
(`TextMetrics.Measure`). If a primitive is missing the shape you need, extend the
primitive — that is one file, and every component gets the fix.

---

## Why This Matters

- **Theming** — a raw texture never reacts to `SUUUI_THEME_CHANGED`.
- **Layout** — a manually anchored frame breaks when its container resizes.
- **Signals** — a raw `OnClick` is invisible to anything else in the UI.
- **Pooling** — raw frames cannot be recycled through `SuuUI.Pool`.
- **Consistency** — two pages built with raw frames will never look identical.
