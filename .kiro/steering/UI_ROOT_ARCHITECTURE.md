# UI Root Architecture

## Overview

SuuUI implements a **single global UI root** system where ALL UI elements are children of one fullscreen container. This ensures consistent layout management and prevents the manual positioning issues that plagued the old architecture.

## Core Principle

**NEVER use manual `SetPoint` positioning except for:**
1. The UI root itself (anchored to UIParent)
2. Internal layout within individual components (like button label positioning)

**ALL other positioning MUST use containers.**

## Architecture Hierarchy

```
UIParent (WoW's base frame)
  └─ SuuUI_UIRoot (fullscreen frame, covers entire screen)
      └─ Root Container (anchor layout)
          ├─ Layer: background
          ├─ Layer: normal
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
- `layer`: One of "background", "normal", "dialog", "tooltip"
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

The UI root manages 4 distinct layers with different frame strata:

| Layer | Strata | Purpose |
|-------|--------|---------|
| `background` | LOW | Background elements (rarely used) |
| `normal` | MEDIUM | Standard windows and frames |
| `dialog` | HIGH | Modals and dialogs |
| `tooltip` | TOOLTIP | Tooltips (always on top) |

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
3. ✅ ALL element positioning uses containers
4. ✅ Containers can be nested
5. ❌ NO manual `SetPoint` for layout (except component internals)
6. ❌ NO direct children of UIParent (use UI root)
7. ❌ NO manual yOffset tracking
8. ❌ NO calculating positions in loops
