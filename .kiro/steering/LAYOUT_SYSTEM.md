# SuuUI Layout System - Quick Reference

## Mandatory Rules

**Everything is positioned by the layout engine. Nothing else calls `SetPoint`.**

`SetPoint`, `SetAllPoints`, and `ClearAllPoints` appear in exactly four files —
the layout strategies:

```
Layout/FlowLayout.lua    Layout/GridLayout.lua
Layout/StackLayout.lua   Layout/AnchorLayout.lua
```

**Those four files are also where pixel snapping happens.** Every coordinate they hand to
`SetPoint` / `SetSize` / `SetWidth` goes through `SuuUI.Pixel.Snap`, so nothing you build
on top has to think about it: pass a fractional width and you get a crisp frame back. See
"Pixel Grid" in `architecture.md` for why units are not pixels in the first place.

One consequence worth knowing: a value you pass in may come back rounded.
`container:Add(child, { width = 20.6 })` produces a 21-unit child, and a `"fill"` share is
floored with the remainder spread across the leading children so the run still reaches the
far edge. Assert the geometry, not the number you passed.

Nowhere else. Not in plugins, not in `SettingsUI/`, and **not inside components
either**. A component lays out its own internals by hosting a container on its own
frame (see "Component internals" below).

`SetPoint` is deliberately **not exposed** on any component handle, container, or
window. If you are reaching for it, you want a container property instead. The only
sanctioned exceptions, both documented in code:

| Exception | Why |
|---|---|
| `Core/UIRoot.lua` anchors the root to `UIParent` | the single screen-level anchor |
| `Layout/Container.lua` anchors its own frame to its parent | containers self-anchor so callers never position them |
| `Core/Pool.lua` clears points on release | detaching a recycled frame, the inverse of layout |

**If a layout algorithm or setting you need does not exist, add it to the engine.**
Do not work around it locally. Adding a strategy or a child property is the expected
move, and both are cheap.

Two companion rules apply to every piece of UI you build:

- **No raw WoW UI API in construction code** — compose components and containers.
  `CreateFrame`, `CreateTexture`, `SetBackdrop`, `SetFrameStrata`, and `EnableMouse`
  belong inside `Components/` and `Layout/`. See `WOW_API_ENCAPSULATION.md`.
- **No Blizzard frame scripts for UI wiring** — connect to `SuuUI.UISignals` instead
  of `SetScript("OnSizeChanged"/"OnClick"/"OnMouseWheel", ...)`. See `UI_SIGNALS.md`.

---

## Basic Container Usage

```lua
local T = SuuUI.Theme

local container = SuuUI.Layout:CreateContainer({
  parent  = parentFrame,
  layout  = "flow",           -- "flow" | "grid" | "anchor"
  dir     = "vertical",       -- "vertical" | "horizontal" (flow only)
  gap     = T:GetToken("spaceXs"),  -- spacing between children (4px)
  padding = {                 -- space from container edges
    top    = T:GetToken("spaceSm"),  -- 8px
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
  },
  cols = 2,                   -- column count (grid only)
})

-- Add children with layout properties
container:Add(childFrame, {
  width  = "fill",            -- "fill" | number | omit
  height = 32,                -- "fill" | number | omit
})
```

**Spacing Tokens:**
- `spaceXs` = 4px  — tight spacing (list gaps, compact UIs)
- `spaceSm` = 8px  — standard spacing (most containers)
- `spaceMd` = 12px — roomier rows and insets
- `spaceLg` = 16px — loose spacing (section separation)
- `spaceXl` = 24px — major spacing (page-level separation)

Use space tokens for both gaps and padding to maintain consistent visual rhythm.

**Size tokens, not literal heights.** Font sizes are user-editable, so a hardcoded
control height clips its text once the font outgrows it. Omit `height` and let the
component derive it, or read the token when the container needs the number:

| Token | Used for |
|---|---|
| `sizeControlSm` | toggle, colour swatch, minimap button |
| `sizeControlMd` | input, dropdown option row, window close button |
| `sizeControlLg` | dropdown, primary button rows |
| `sizeRow` | settings rows, section dividers |
| `sizeNavRow` | settings nav items |
| `sizeTitleBar` | window title strip |
| `sizeIcon` | icons, resize grip, scroll thumb minimum |
| `sizeScrollbar` | scrollbar track and thumb width |

`Theme:GetControlHeight(sizeKey, fontKey)` returns the token floored against the font
metrics — use it for anything that holds text. Read the token directly for elements that
do not (`GetToken("sizeControlSm")`).

---

## Layout Properties

| Property | Values | Behavior |
|----------|--------|----------|
| `width` | `"fill"` | Stretch to container width (respects padding) |
| `width` | `number` | Fixed pixel width |
| `width` | omit | Use child's natural width |
| `height` | `"fill"` | Distribute available space (flow) or fill height |
| `height` | `number` | Fixed pixel height |
| `height` | omit | Use child's natural height |
| `align` | `"start"` | Cross-axis start: left (vertical) / top (horizontal). Default |
| `align` | `"center"` | Centre on the cross axis |
| `align` | `"end"` | Cross-axis end: right (vertical) / bottom (horizontal) |
| `align` | `"stretch"` | Fill the cross axis |

`align` may also be set on the container to apply to every child. On the **main**
axis, combine a `width="fill"` label with a fixed-width control to push the control
to the far edge — that is the canonical label-left / control-right row:

```lua
local row = SuuUI.Layout:CreateContainer({
  parent = parent, layout = "flow", dir = "horizontal",
  gap = T:GetToken("spaceSm"), align = "center", h = 28,
})
row:Add(label,  { width = "fill" })   -- eats the slack
row:Add(toggle, { width = 36, height = 18 })  -- lands on the right, vertically centred
```

**Container sizing:**

| Prop | Behaviour |
|------|-----------|
| `fill = true` | Mirrors the parent's size and tracks parent resizes |
| `host = frame` | Adopts an existing frame as the layout box; creates nothing |
| `w` / `h` | Explicit size |
| neither | Width defaults to the parent's width; height hugs content |

**Containers are always explicitly sized, never anchor-derived.** This matters: WoW does
not resolve anchor-only geometry for frames that have never been laid out, so a container
built inside a window that starts hidden would report width 0 and collapse every child.
`fill` therefore mirrors the parent's size and tracks its `OnSizeChanged`, rather than
using `SetAllPoints`. Containers also re-run layout on `OnShow`.

### Floating panels

Transient screen-level panels (dropdown panels, tooltips, popups) must use the shared
host instead of each creating their own screen-level container — otherwise every one
adds another resize handler to `UIParent` and they accumulate as pages rebuild:

```lua
local host = SuuUI.Layout:GetFloatingHost()   -- singleton, anchor layout
host:Add(panel, { anchor = { point = "TOPLEFT", relativeTo = button,
                             relativePoint = "BOTTOMLEFT", x = 0, y = -4 } })

-- On teardown: drop your panel, never destroy the shared host
host:Remove(panel)
```

A container with no `h` reports its content height through `SIZE_CHANGED`, so parents
and scroll frames resize themselves without anyone tracking offsets.

**Font strings re-measure.** Flow layout measures a font string child with
`GetStringHeight()` after assigning it a width, rather than trusting a height pinned
by an earlier pass. Text metrics depend on the `fontSize*` tokens, which change at
runtime, so omit `height` on text children and let the layout measure them.

**Hugging containers lay out twice.** A container with no `h` sets its height from
content, then re-runs its strategy so `align` / `valign` resolve against the settled
height.

**Passing children:** `Add()` accepts a raw frame, a component handle, or another
container. Handles are unwrapped internally, so `container:Add(btn)` and
`container:Add(btn:GetFrame())` are equivalent — prefer the handle so the container
can also listen to its signals.

---

## Component internals: host containers

A container normally creates its own frame. Pass `host` instead and it adopts an
existing frame as its layout box, creating nothing. This is how components lay out
their own parts without paying a frame per container, and it is why no component
needs `SetPoint`:

```lua
function SuuUI.Components.Button(props, parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(props.w or 100, props.h or 24)

    -- Internal layout runs through the engine, hosted on the button's own frame
    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box:Add(lbl, { align = "center", valign = "center" })   -- was lbl:SetPoint("CENTER")
    ...
end
```

Containers accept frames, textures, and font strings as children, so every visual
part of a component is positioned by a strategy. Adopting a frame chains onto any
existing `OnSizeChanged` rather than replacing it. Destroy host containers in the
component's `Destroy()`.

Translation table for the old raw calls:

| Raw call | Engine equivalent |
|---|---|
| `tex:SetAllPoints(f)` | `stack:Add(tex)` (stretch is the default) |
| `lbl:SetPoint("CENTER")` | `stack:Add(lbl, { align="center", valign="center" })` |
| `icon:SetPoint(TOPLEFT, p, TOPLEFT, 3, -3)` + BOTTOMRIGHT | `stack:Add(icon, { inset = 3 })` |
| `t:SetPoint("LEFT", f, "LEFT", 6, 0)` + `"RIGHT" … -16` | `stack:Add(t, { valign="center", inset={left=6, right=16} })` |
| `a:SetPoint("RIGHT", f, "RIGHT", -4, 0)` | `stack:Add(a, { align="end", valign="center", inset={right=4} })` |
| thumb at a computed offset | `anchor:SetChildAnchor(thumb, { point="LEFT", x=off, ... })` |
| a loop tracking `y = y - h - gap` | a vertical flow container |

## Layout Strategies

### Stack Layout
Overlays every child on the container box. This replaces `SetAllPoints`, centring,
edge-spanning, and inset placement.

```lua
local box = SuuUI.Layout:CreateContainer({ host = frame, layout = "stack" })

box:Add(background)                                      -- fills the box
box:Add(icon,  { inset = 3 })                            -- inset on all sides
box:Add(label, { align = "center", valign = "center" })  -- centred, natural size
box:Add(arrow, { align = "end", valign = "center", width = 8, inset = { right = 4 } })
box:Add(text,  { valign = "center", inset = { left = 6, right = 16 } })  -- spans edges
```

| Property | Values | Behaviour |
|----------|--------|-----------|
| `inset` | `number` or `{top,right,bottom,left}` | space from the container edges |
| `align` | `"start"｜"center"｜"end"｜"stretch"` | horizontal placement (default `stretch`) |
| `valign` | `"start"｜"center"｜"end"｜"stretch"` | vertical placement (default `stretch`) |
| `width` / `height` | `number` | explicit size when that axis is not stretched |

A non-stretched axis needs the child's natural size, and for a font string that comes
from `TextMetrics.Measure` against its current font — never from its rect. A region the
client has not laid out yet reports 0, and one sized by an earlier pass is stale as soon
as a `fontSize*` token changes. Either way the string gets a box smaller than its glyphs
and **the client clips rather than overflows**, which is invisible to every geometry
assertion. So when a component changes a font string's font, re-run the host container:

```lua
label:SetFont(T:GetToken("fontFamilyMain"), T:GetToken("fontSizeLg"), "")
box:Layout()   -- the box is sized from the font; nothing else re-measures it
```

A resize would re-layout on its own, but a font change on a token-sized element does not
resize anything, so there is no hook to ride. Assert it with `H.expectTextNotClipped`.

### Flow Layout
Arranges children in a single direction with optional flexible sizing.

```lua
local T = SuuUI.Theme

-- Vertical list with fill width
local list = SuuUI.Layout:CreateContainer({
  parent  = content,
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
list:Add(item1, { width = "fill", height = 32 })
list:Add(item2, { width = "fill", height = 32 })

-- Horizontal button row
local buttons = SuuUI.Layout:CreateContainer({
  parent = footer,
  layout = "flow",
  dir    = "horizontal",
  gap    = T:GetToken("spaceSm"),
})
buttons:Add(cancelBtn, { width = 80, height = 24 })
buttons:Add(okBtn, { width = 80, height = 24 })
```

### Anchor Layout
Absolute or fraction-driven placement. This is the tool for anything whose position
is computed: slider fills and thumbs, scrollbar thumbs, floating panels, tooltips.

```lua
local box = SuuUI.Layout:CreateContainer({ host = track, layout = "anchor" })

local anchor = { point = "LEFT", relativePoint = "LEFT", x = 0, y = 0, width = 8, height = 12 }
box:Add(thumb, { anchor = anchor })

-- Move it later: mutate the descriptor and re-apply through the container
anchor.x = pct * trackWidth
box:SetChildAnchor(thumb, anchor)
```

`relativeTo` accepts a frame, a component handle, `"parent"`, or `nil` (the container).
That is how a dropdown panel hangs off its button and a tooltip off its trigger.

**Animating position** goes through the same path. Pass the container and the base
descriptor; the animator drives the offset via `SetChildAnchor`:

```lua
SuuUI.Anim:New({
  container = knobBox, target = knob, anchor = knobAnchor,
  property = "x", from = 3, to = 20,
  duration = T:GetToken("animFast"), easing = "easeOut",
}):Play()
```

`property = "x"` or `"y"` **requires** `container` and `anchor`. Without them the
animation logs a debug warning and does nothing, by design — there is no raw
`SetPoint` fallback.

### Grid Layout
Arranges children in fixed-width columns.

```lua
local T = SuuUI.Theme

local grid = SuuUI.Layout:CreateContainer({
  parent  = content,
  layout  = "grid",
  cols    = 3,
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = T:GetToken("spaceSm"),
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
  },
})

-- Children auto-sized to fit grid cells
for _, item in ipairs(items) do
  grid:Add(item)
end
```

---

## Common Patterns

### ScrollFrame Content

```lua
local T = SuuUI.Theme

local scroll = SuuUI.Components.ScrollFrame({ w=300, h=400 }, parent)
local content = scroll:GetContent()

local container = SuuUI.Layout:CreateContainer({
  parent  = content,
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
container:GetFrame():SetAllPoints(content)

for _, row in ipairs(rows) do
  container:Add(row, { width = "fill" })
end

-- Resize content for scrolling
local _, totalHeight = container:GetContentSize()
content:SetHeight(totalHeight)
```

### Settings Page

```lua
local T = SuuUI.Theme

local container = SuuUI.Layout:CreateContainer({
  parent  = contentFrame,
  layout  = "flow",
  dir     = "vertical",
  gap     = T:GetToken("spaceXs"),
  padding = {
    top    = 0,
    right  = 0,
    bottom = T:GetToken("spaceXs"),
    left   = 0,
  },
})

for _, control in ipairs(controls) do
  container:Add(control, { width = "fill", height = controlHeight })
end
```

### Two-Column Form

```lua
local T = SuuUI.Theme

local form = SuuUI.Layout:CreateContainer({
  parent  = panel,
  layout  = "grid",
  cols    = 2,
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = T:GetToken("spaceSm"),
    right  = T:GetToken("spaceSm"),
    bottom = T:GetToken("spaceSm"),
    left   = T:GetToken("spaceSm"),
  },
})

form:Add(labelFrame)       -- left column
form:Add(inputFrame)       -- right column
form:Add(labelFrame2)      -- left column, next row
form:Add(inputFrame2)      -- right column, next row
```

---

## Forbidden Patterns

```lua
-- ❌ NEVER: Manual Y-offset tracking
local y = 0
for _, item in ipairs(items) do
  item:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
  y = y - item:GetHeight() - gap
end

-- ❌ NEVER: SetPoint chains
header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)

-- ❌ NEVER: Conditional positioning
if hasScrollbar then
  frame:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
end
-- ✅ Inset the viewport instead:
box:SetChildProps(viewport, needsBar and { inset = { right = 10 } } or nil)

-- ❌ NEVER: SetAllPoints, even inside a component
tex:SetAllPoints(frame)
-- ✅ stack:Add(tex)

-- ❌ NEVER: positioning a container from outside
page:GetFrame():SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
-- ✅ containers self-anchor; just pass parent (and w/fill if needed)
local page = SuuUI.Layout:CreateContainer({ parent = content, w = scroll:GetContentWidth() })

-- ❌ NEVER: reaching for a handle's SetPoint (it does not exist)
btn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
-- ✅ an anchor container places it
local host = SuuUI.Layout:CreateContainer({ host = Minimap, layout = "anchor" })
host:Add(btn, { anchor = { point="TOPRIGHT", relativePoint="TOPRIGHT", x=-2, y=-2,
                           width=20, height=20 } })
```

---

## Missing Feature? Discuss First!

If you need layout behavior that doesn't exist:

1. **Stop** — don't implement workarounds
2. **Document** — describe what you need
3. **Discuss** — propose a generic API
4. **Implement** — extend the layout system
5. **Spec it** — a new strategy or child property needs tests in `Tests/spec/` proving
   the geometry it produces, including the edge cases (zero size, negative space,
   conflicting properties). See `TESTING.md`.
6. **Document** — update guides for all plugins

### Known Limitations

- No wrapping in flow layouts
- No percentage-based sizing (`width = "50%"`)
- No min/max size constraints
- No per-child margin (only container padding)
- No z-index control within a container (use UIRoot layers instead)

Resolved: cross-axis alignment is supported via `align` on containers and children.

Bring the rest up if you need them!

---

## Container API Reference

```lua
container:Add(child, layoutProps)          -- frame, texture, fontstring, handle, or container
container:SetChildProps(child, props)      -- change a child's layout props, then re-layout
container:SetChildAnchor(child, desc)      -- anchor layout: move/resize one child
container:Remove(child)
container:Clear()                          -- remove and hide every child
container:Layout()                         -- auto-called on Add/Remove/resize
container:SetSize(w, h) / SetWidth / SetHeight
container:GetWidth() / GetHeight()
container:GetFrame()                       -- underlying WoW frame
container:GetChildren()
container:GetContentSize()                 -- (width, height) of all children
container:Show() / Hide() / IsShown()
container:Destroy()                        -- destroys children, drops connections
```

Note there is **no** `SetPoint` or `ClearAllPoints` on the container API. That is
intentional: a container is positioned by its parent container, or self-anchors to
its parent frame. Nothing else places it.

---

## Integration with Components

All SuuUI components return handles with a `GetFrame()` method:

```lua
local btn = SuuUI.Components.Button({label="Click Me"}, parent)
container:Add(btn)   -- omit width/height: the button hugs its label

local text = SuuUI.Components.Text({text="Label"}, parent)
container:Add(text:GetFrame(), { width = "fill" })
```

---

## Performance Notes

- Layout calculations only run when children are added/removed or container is resized
- No per-frame overhead
- Use frame pool for repeated elements
- Containers are lightweight — nest freely
