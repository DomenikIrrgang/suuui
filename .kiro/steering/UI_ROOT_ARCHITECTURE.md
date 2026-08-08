# UI Root Architecture

## Overview

SuuUI implements a **single global UI root** system where ALL UI elements are children of one fullscreen container. This ensures consistent layout management and prevents the manual positioning issues that plagued the old architecture.

## Core Principle

**ALL positioning goes through the layout engine. `SetPoint` appears only in the four
layout strategies** (`Layout/FlowLayout.lua`, `GridLayout.lua`, `StackLayout.lua`,
`AnchorLayout.lua`).

Component internals are no exception: a component lays out its own parts with a host
container (`CreateContainer{ host = f, layout = "stack" }`). `SetPoint` is not exposed
on component handles, containers, or windows.

The only sanctioned raw anchors, each documented in code:
1. `Core/UIRoot.lua` anchoring the root to `UIParent`
2. `Layout/Container.lua` self-anchoring its own frame to its parent
3. `Core/Pool.lua` clearing points when releasing a recycled frame

The root is also the **only frame in the addon that carries a scale**. `Core/Pixel.lua`
drives it so one unit is a whole number of physical pixels — see "Pixel Grid" in
`architecture.md`. Two things follow for anything under the root:

- Its effective scale is **not** `UIParent`'s. Read the cursor with
  `SuuUI.Pixel.CursorIn(frame)`, never `GetCursorPosition() / UIParent:GetEffectiveScale()`.
- **Never use `GetScreenWidth`/`GetScreenHeight` as a reference point.** They are in
  `UIParent`'s units; a frame under the root reports its own rect in the root's. Measure
  against `UIRoot:GetRootContainer():GetFrame()` instead, which shares your space. Mixing
  the two is wrong on the vertical axis only, so it looks half-correct.
- Never call `SetScale` yourself. A second scale in the chain puts units back between
  pixels, which is exactly what the root scale exists to prevent.

## Architecture Hierarchy

```
UIParent (WoW's base frame)
  └─ SuuUI_UIRoot (fullscreen frame, covers entire screen)
      └─ Root Container (anchor layout)
          ├─ Layer: background
          ├─ Layer: normal
          │   └─ Plugin content (unit frames, bars — inherits this rung from the root)
          ├─ Layer: window
          │   └─ Settings Window
          │       └─ Window Container (vertical flow)
          │           ├─ Title Bar
          │           └─ Content
          │               └─ ScrollFrame
          │                   └─ PageBuilder Container (vertical flow)
          │                       ├─ Profile Manager
          │                       │   └─ Root Container (vertical flow)
          │                       │       ├─ Current Row (horizontal flow)
          │                       │       ├─ Dropdown
          │                       │       ├─ Button Row (horizontal flow)
          │                       │       └─ Reset Button
          │                       └─ Theme Manager
          │                           └─ Root Container (vertical flow)
          │                               ├─ Current Row (horizontal flow)
          │                               ├─ Dropdown
          │                               ├─ Button Row (horizontal flow)
          │                               ├─ Info Text
          │                               └─ Token Editor Container (vertical flow)
          │                                   └─ Token Rows (horizontal flow each)
          ├─ Layer: dialog
          │   └─ Modals
          └─ Layer: tooltip
              └─ Tooltips
```

## UI Root API

### Initialization
```lua
SuuUI.UIRoot:Init()  -- Called during ADDON_LOADED
```

### Adding Elements
```lua
SuuUI.UIRoot:AddElement(frame, layer, anchorDesc)
```

**Parameters:**
- `frame`: The WoW frame to add
- `layer`: One of "background", "normal", "window", "dialog", "tooltip"
- `anchorDesc`: Anchor descriptor table
  ```lua
  {
    point = "TOPLEFT",      -- Anchor point
    x = 0,                  -- X offset
    y = 0,                  -- Y offset
    width = 400,            -- Optional width
    height = 300,           -- Optional height
  }
  ```

### Removing Elements
```lua
SuuUI.UIRoot:RemoveElement(frame)
```

### Updating Position
```lua
SuuUI.UIRoot:UpdateElementAnchor(frame, newAnchorDesc)
```

## Layers

The UI root owns the z-order. It is the **only** file in the addon that calls
`SetFrameStrata`: everything else names a layer and lets the root translate. That keeps one
ladder to reason about, and keeps components independent of the client's strata vocabulary.

| Layer | Strata | Purpose |
|-------|--------|---------|
| `background` | LOW | Background elements (rarely used) |
| `normal` | MEDIUM | Plugin content — unit frames, bars, anything the player plays with. The root's own strata, so a frame parented to the root inherits this rung without asking |
| `window` | HIGH | SuuUI windows (settings, and anything else from `CreateWindow`) |
| `dialog` | DIALOG | Modals and popups opened *from* a window (`Modal`, the colour picker) |
| `tooltip` | TOOLTIP | Tooltips and dropdown panels (always on top) |

A window must outrank plugin content by **layer**, not by frame level. Level is only the
tie-break inside a rung, and a frame nested one level deeper than the window wins that
tie-break: a plugin frame on the root container is a child of the container, which is a
child of the root, so it sits a level above a window parented to the root and draws over
it. That is exactly the bug that put the player frame on top of the settings window.

### Assigning a layer

```lua
-- Positioned by the root: layer + anchor in one call
SuuUI.UIRoot:AddElement(frame, "window", { point = "CENTER", x = 0, y = 0 })

-- Layer only, for frames that place themselves (a draggable plugin frame, a modal
-- filling its parent, a dropdown panel anchored to its field)
SuuUI.UIRoot:SetLayer(frame, "normal")
SuuUI.UIRoot:GetLayer(frame)          --> "normal"
SuuUI.UIRoot:GetLayerStrata("dialog") --> "DIALOG"  (readable before Init)

-- Decoration that belongs TO a frame: same rung, higher level. Never a higher layer —
-- an edit-mode overlay promoted to `dialog` would cover the window that toggles it.
SuuUI.UIRoot:RaiseAbove(overlay, frame, 5)
```

## Window Integration

Windows automatically register with UIRoot during PLAYER_LOGIN:

```lua
local win = SuuUI.Layout:CreateWindow({
  id    = "settings",
  title = "SuuUI Settings",
  w     = 780,
  h     = 520,
  layer = "normal",  -- optional, defaults to "normal"
})
```

Windows are:
1. Created as children of UIRoot
2. Positioned using anchor layout
3. Draggable (position saved per-character)
4. Automatically managed by the root container

## Container Requirements

Every UI element with children MUST use a container for layout:

### ✅ CORRECT: Container-based layout
```lua
local rootContainer = SuuUI.Layout:CreateContainer({
  parent  = frame,
  layout  = "flow",
  dir     = "vertical",
  gap     = 8,
  padding = {top=0, right=0, bottom=0, left=0},
})
rootContainer:GetFrame():SetAllPoints(frame)

rootContainer:Add(child1, { width = "fill", height = 24 })
rootContainer:Add(child2, { width = "fill", height = 32 })
```

### ❌ WRONG: Manual positioning
```lua
child1:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
child2:SetPoint("TOPLEFT", child1, "BOTTOMLEFT", 0, -8)
```

## Layout Strategies

### Flow Layout
Best for: Lists, forms, vertical/horizontal sequences
```lua
{
  layout = "flow",
  dir    = "vertical",  -- or "horizontal"
  gap    = 8,
}
```

### Grid Layout
Best for: Fixed-column layouts, settings grids
```lua
{
  layout = "grid",
  cols   = 2,
  gap    = 8,
}
```

### Anchor Layout
Best for: Absolute positioning (UI root only)
```lua
{
  layout = "anchor",
}
-- Children need anchor descriptors
```

## Migration Guide

### Old Pattern (Manual)
```lua
local yOffset = 0
row1:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
yOffset = yOffset - 24 - gap
row2:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
```

### New Pattern (Container)
```lua
local container = SuuUI.Layout:CreateContainer({
  parent = parent,
  layout = "flow",
  dir    = "vertical",
  gap    = gap,
})
container:GetFrame():SetAllPoints(parent)
container:Add(row1, { width = "fill", height = 24 })
container:Add(row2, { width = "fill", height = 24 })
```

## Benefits

1. **Automatic Height Calculation**: No more scroll issues
2. **Responsive Layout**: Elements adapt to container size
3. **Maintainable**: Add/remove elements without recalculating positions
4. **Consistent**: All UI uses the same layout patterns
5. **Hierarchical**: Clear parent-child relationships
6. **Debuggable**: Easy to trace layout issues through container hierarchy

## Rules Summary

1. ✅ ONE UI root for entire addon
2. ✅ ALL windows are children of UI root
3. ✅ ALL positioning uses containers — including inside components
4. ✅ Containers can be nested, and can adopt an existing frame via `host`
5. ✅ Raw WoW UI API only in `Components/`, `Layout/`, `Core/UIRoot.lua`
   (see `WOW_API_ENCAPSULATION.md`)
6. ✅ Elements communicate via `SuuUI.UISignals` (see `UI_SIGNALS.md`)
7. ✅ Missing a layout algorithm or property? Implement it in the engine
8. ✅ Every component and layout strategy has a spec in `Tests/spec/` asserting the real
   geometry it produces (see `TESTING.md`)
9. ❌ NO `SetPoint`/`SetAllPoints` outside the four layout strategies
10. ❌ NO `SetPoint` on any public handle — it is not exposed
11. ❌ NO direct children of UIParent (use UI root)
12. ❌ NO manual yOffset tracking
13. ❌ NO calculating positions in loops
14. ❌ NO `CreateFrame`/`CreateTexture`/`SetBackdrop` in page or plugin UI code
15. ❌ NO Blizzard frame scripts (`OnSizeChanged`, `OnClick`, `OnMouseWheel`) for UI wiring
