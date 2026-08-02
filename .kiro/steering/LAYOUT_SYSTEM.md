# SuuUI Layout System - Quick Reference

## Mandatory Rule

**ALWAYS use Container-based layouts. NEVER manually position UI with SetPoint.**

---

## Basic Container Usage

```lua
local T = SuuUI.Theme

local container = SuuUI.Layout:CreateContainer({
  parent  = parentFrame,
  layout  = "flow",           -- "flow" | "grid" | "anchor"
  dir     = "vertical",       -- "vertical" | "horizontal" (flow only)
  gap     = T:GetToken("spaceSm"),  -- spacing between children (4px)
  padding = {                 -- space from container edges
    top    = T:GetToken("spaceMd"),  -- 8px
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
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
- `spaceSm` = 4px  — tight spacing (list gaps, compact UIs)
- `spaceMd` = 8px  — standard spacing (most containers)
- `spaceLg` = 16px — loose spacing (section separation)
- `spaceXl` = 24px — major spacing (page-level separation)

Use space tokens for both gaps and padding to maintain consistent visual rhythm.

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

---

## Layout Strategies

### Flow Layout
Arranges children in a single direction with optional flexible sizing.

```lua
local T = SuuUI.Theme

-- Vertical list with fill width
local list = SuuUI.Layout:CreateContainer({
  parent  = content,
  layout  = "flow",
  dir     = "vertical",
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = T:GetToken("spaceMd"),
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
  },
})
list:Add(item1, { width = "fill", height = 32 })
list:Add(item2, { width = "fill", height = 32 })

-- Horizontal button row
local buttons = SuuUI.Layout:CreateContainer({
  parent = footer,
  layout = "flow",
  dir    = "horizontal",
  gap    = T:GetToken("spaceMd"),
})
buttons:Add(cancelBtn, { width = 80, height = 24 })
buttons:Add(okBtn, { width = 80, height = 24 })
```

### Grid Layout
Arranges children in fixed-width columns.

```lua
local T = SuuUI.Theme

local grid = SuuUI.Layout:CreateContainer({
  parent  = content,
  layout  = "grid",
  cols    = 3,
  gap     = T:GetToken("spaceMd"),
  padding = {
    top    = T:GetToken("spaceMd"),
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
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
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = T:GetToken("spaceMd"),
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
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
  gap     = T:GetToken("spaceSm"),
  padding = {
    top    = 0,
    right  = 0,
    bottom = T:GetToken("spaceSm"),
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
  gap     = T:GetToken("spaceMd"),
  padding = {
    top    = T:GetToken("spaceMd"),
    right  = T:GetToken("spaceMd"),
    bottom = T:GetToken("spaceMd"),
    left   = T:GetToken("spaceMd"),
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
```

---

## Missing Feature? Discuss First!

If you need layout behavior that doesn't exist:

1. **Stop** — don't implement workarounds
2. **Document** — describe what you need
3. **Discuss** — propose a generic API
4. **Implement** — extend the layout system
5. **Document** — update guides for all plugins

### Known Limitations

- No alignment control (left/center/right, top/middle/bottom)
- No wrapping in flow layouts
- No percentage-based sizing (`width = "50%"`)
- No min/max size constraints
- No per-child margin (only container padding)
- No z-index control

Bring these up if you need them!

---

## Container API Reference

```lua
container:Add(frame, layoutProps)    -- Add child with optional sizing
container:Remove(frame)              -- Remove child
container:Layout()                   -- Recalculate (auto-called on Add/Remove)
container:SetSize(w, h)              -- Resize container
container:GetFrame()                 -- Get underlying WoW frame
container:GetContentSize()           -- Returns (width, height) of all children
```

---

## Integration with Components

All SuuUI components return handles with a `GetFrame()` method:

```lua
local btn = SuuUI.Components.Button({label="Click Me"}, parent)
container:Add(btn:GetFrame(), { width = 100, height = 24 })

local text = SuuUI.Components.Text({text="Label"}, parent)
container:Add(text:GetFrame(), { width = "fill" })
```

---

## Performance Notes

- Layout calculations only run when children are added/removed or container is resized
- No per-frame overhead
- Use frame pool for repeated elements
- Containers are lightweight — nest freely
