# SuuUI Signal System

## Mandatory Rule

**NEVER use Blizzard frame scripts for UI communication. ALWAYS use UISignals.**

Blizzard scripts (`OnSizeChanged`, `OnMouseWheel`, `OnShow`, `OnHide`, `OnValueChanged`, ...)
must never be used to notify other parts of our UI that something happened. They are an
implementation detail that stays *inside* a component. Cross-element communication goes
through `SuuUI.UISignals`, modelled on Godot's signal system.

Game events (`COMBAT_LOG_EVENT`, `UNIT_HEALTH`, `PLAYER_ENTERING_WORLD`, ...) are data,
not UI, and still use `SuuUI.Events` / `RegisterEvent`. That distinction matters:

| Kind | Mechanism |
|---|---|
| UI element told another UI element something | `SuuUI.UISignals` |
| Addon-wide state change (theme, profile, setting) | `SuuUI.Events` |
| WoW game data | `frame:RegisterEvent` inside a plugin |

---

## API

```lua
local S = SuuUI.UISignals

--- Connect a callback. Returns a connection id.
local id = S:Connect(obj, S.SIGNALS.SIZE_CHANGED, function(w, h) ... end)

--- Disconnect one callback.
S:Disconnect(obj, S.SIGNALS.SIZE_CHANGED, id)

--- Disconnect every callback for one signal, or for the whole object.
S:DisconnectAll(obj, S.SIGNALS.SIZE_CHANGED)
S:DisconnectAll(obj)

--- Emit from inside the owning component.
S:Emit(obj, S.SIGNALS.SIZE_CHANGED, width, height)

--- Cheap check before doing expensive work.
if S:HasConnections(obj, S.SIGNALS.SIZE_CHANGED) then ... end
```

`obj` is the component handle or container — whatever the consumer already holds a
reference to. The registry uses **weak keys**, so objects are garbage collected
normally and stale connections disappear with them. Callbacks are invoked through
`pcall`; a throwing callback logs via `SuuUI.Debug` and never breaks the emitter.

---

## Standard Signals

Every component may emit these. Payloads are fixed — do not change them per component.

| Signal | Constant | Payload |
|---|---|---|
| `size_changed` | `SIGNALS.SIZE_CHANGED` | `width, height` |
| `position_changed` | `SIGNALS.POSITION_CHANGED` | `x, y` |
| `visibility_changed` | `SIGNALS.VISIBILITY_CHANGED` | `isVisible` |
| `mouse_enter` | `SIGNALS.MOUSE_ENTER` | — |
| `mouse_leave` | `SIGNALS.MOUSE_LEAVE` | — |
| `clicked` | `SIGNALS.CLICKED` | `button` |
| `value_changed` | `SIGNALS.VALUE_CHANGED` | `newValue, oldValue` |
| `text_changed` | `SIGNALS.TEXT_CHANGED` | `newText` |
| `scroll_changed` | `SIGNALS.SCROLL_CHANGED` | `scrollY` |
| `content_resized` | `SIGNALS.CONTENT_RESIZED` | `contentHeight` |
| `enabled_changed` | `SIGNALS.ENABLED_CHANGED` | `isEnabled` |
| `focused` | `SIGNALS.FOCUSED` | — |
| `unfocused` | `SIGNALS.UNFOCUSED` | — |

### Component-Specific Signals

A component may define extra signals. Namespace them with the component name and
document the payload next to the definition:

```lua
-- Components/ColorPicker.lua
M.SIGNALS_COLORPICKER = {
  COLOR_PICKED   = "colorpicker.color_picked",   -- Args: r, g, b, a
  REQUEST_CLOSE  = "colorpicker.request_close",  -- Args: none
}
```

Rules for custom signals:
1. Prefix with the component or plugin id.
2. Document the payload in a comment on the same line.
3. Never reuse a standard signal name with a different payload.

---

## Component Author Contract

Every component you write must:

1. **Emit** the standard signals that apply to it. A component that can resize emits
   `SIZE_CHANGED`; one with a value emits `VALUE_CHANGED`; one that can be toggled
   emits `VISIBILITY_CHANGED`.
2. **Translate** Blizzard scripts into signals internally — the Blizzard script never
   escapes the component file.
3. **Clean up** in `Destroy()` with `SuuUI.UISignals:DisconnectAll(self)`.

```lua
-- ✅ CORRECT: Blizzard script converted to a signal inside the component
local function CreateToggle(props, parent)
  local self = setmetatable({}, ToggleMeta)
  -- ...
  hit:SetScript("OnMouseUp", function()
    local old = self._value
    self._value = not old
    self:_render()
    SuuUI.UISignals:Emit(self, SuuUI.UISignals.SIGNALS.VALUE_CHANGED, self._value, old)
  end)
  return self
end

function ToggleMeta:Destroy()
  SuuUI.UISignals:DisconnectAll(self)
  SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
end
```

```lua
-- ❌ FORBIDDEN: consumer reaching into the frame to attach a Blizzard script
local toggle = SuuUI.Components.Toggle({}, parent)
toggle:GetFrame():SetScript("OnMouseUp", function() ... end)  -- NO

-- ✅ REQUIRED
SuuUI.UISignals:Connect(toggle, SuuUI.UISignals.SIGNALS.VALUE_CHANGED, function(new, old)
  ...
end)
```

---

## Consumer Contract

1. Connect after you have the handle, disconnect when you drop it.
2. Keep the connection id if you will ever need to remove that single callback.
3. Never poll a component's state in `OnUpdate` when a signal exists for it.
4. Never assume emit order between sibling components.

```lua
local scroll = SuuUI.Components.ScrollFrame({ w=300, h=400 }, parent)
local container = SuuUI.Layout:CreateContainer({ ... })

-- Container tells the scroll frame how tall its content is
SuuUI.UISignals:Connect(container, SuuUI.UISignals.SIGNALS.SIZE_CHANGED, function(w, h)
  SuuUI.UISignals:Emit(scroll, SuuUI.UISignals.SIGNALS.CONTENT_RESIZED, h)
end)
```

---

## Forbidden Patterns

```lua
-- ❌ Blizzard layout script used for UI wiring
frame:SetScript("OnSizeChanged", function(_, w, h) relayoutMyList(w, h) end)

-- ❌ Blizzard scroll script in UI construction code
frame:SetScript("OnMouseWheel", function(_, delta) ... end)

-- ❌ Polling instead of listening
myFrame:SetScript("OnUpdate", function()
  if container:GetHeight() ~= lastHeight then ... end
end)

-- ❌ Direct call into another component to tell it something changed
otherComponent:RefreshBecauseIChanged()
```

Each of these has a signal equivalent. Use it.

---

## Adding a New Standard Signal

If a signal you need is genuinely universal:

1. **Stop** — do not attach a Blizzard script as a workaround.
2. **Document** the signal name and exact payload.
3. **Discuss** whether it belongs in `M.SIGNALS` or as a component-specific signal.
4. **Implement** in `Core/UISignals.lua` with an inline payload comment.
5. **Emit** it from every component where it applies.
6. **Update** this file and `architecture.md`.
