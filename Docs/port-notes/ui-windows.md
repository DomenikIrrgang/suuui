# Port notes: ui-windows

Files: `src/UI/Reskin`, `WindowSkin`, `Tooltip`, `ContextMenu`, `FilterMenu`,
`Notification`, `Alert`, `Loot`, `LevelUp`, `MicroMenu` (all `.wowlua`,
strict).

## 1. VM suspicions

None (the VM was not run for these files).

## 2. Compiler/tooling issues

### A field typed `x: T?` must be present in a table literal

Already noted in `units-trade.md` and `ui-world.md`; seen here through
`/UI/Draw`'s `BorderOptions` (since changed to `?:` there). Repro (strict):

```wowlua
local function f(opts: { layer: DrawLayer?, sublevel: number? }?) end
f({ layer = "BACKGROUND" })
-- E2001: `{ layer: "BACKGROUND" }` is not assignable to
--        `{ layer: nil | "BACKGROUND" | …, sublevel: number? }?`
```

In Lua an absent key and a nil value are the same; `x: T?` accepting an
absent key (as Luau does) would avoid this. Workaround: declare `x?: T`.

### Narrowing an annotated local doesn't survive a loop

```wowlua
export function h(s: string?): number
    local n: number? = nil
    if s then
        n = 0
        for _ = 1, 3 do n = n + 1 end   -- E2001: arithmetic on a value of type `number?`
    end
    return n or 1
end
```

`n = 0` narrows `n` to `number` (the same code without the loop, `n = 0;
n = n + 1`, checks), and every assignment in the loop keeps it a number,
but inside the loop body it reads as declared. Workaround in `Alert:Fit`: count into fresh
locals inside the branch and assign the optional ones after the loop.

## 3. Stdlib gaps

### `wowlua:tooltip` for `spellTooltip`

`spellTooltip` adds SuuUI's lines to the game's spell tooltip in a
`TooltipDataProcessor` post-call (Spell) and also right away when there is
no post-call or it didn't run. `wowlua:tooltip`'s `hook("Spell", fn)` nearly
fits, but: it falls back to `OnTooltipSetSpell` script hooks on clients
without the data system (SuuUI then adds the lines itself, once), it skips
forbidden tooltips before the handler (SuuUI's handler doesn't run for
them either way, but it decides `pending.added` from that), and SuuUI needs
to know whether the post-call exists (`hooked == "post"`) to decide whether
to add the lines directly. Kept SuuUI's own post-call. The stdlib would
need an `available()` (or a return value from `hook`) saying whether the
data system's post-call is in use, and an option not to install the
script fallback.

## 4. Port decisions

- **Hooks on Blizzard's frames** go through `wowlua:hooks`: every
  `hooksecurefunc(obj, "Method", fn)` is `hook(obj, "Method", fn)` and every
  `HookScript` on a Blizzard frame is `hookScript(frame, "Script", fn)`
  (Reskin: scrollbars, status/fill bars, dropdowns, menu rows, icon/check/
  panel/collapse buttons, edit boxes, dialogs, popups; WindowSkin: tab
  buttons, their selected textures, the close button, the window's
  OnShow/OnSizeChanged/OnHide and SetPoint; Tooltip:
  `SharedTooltip_SetBackdropStyle`, `GameTooltip` OnHide). They stay
  post-hooks; nothing of Blizzard's is replaced. Differences: the handler
  runs through `callIn` (xpcall), so an error is reported by wowlua:errors
  instead of being raised into the hooked Blizzard call, and each call
  packs its arguments into a table (`{ ... }` in `callIn`). The SetPoint
  hooks on tab buttons and windows run often while Blizzard lays out; the
  extra closure and table per call are small but new garbage.
- `HookScript` on SuuUI's own frames stays a method call (MicroMenu's
  buttons, FilterMenu's field, Notification's links, `attachTooltip`).
  Notification's `hooksecurefunc(b.label, "SetValue", fit)` (a SuuUI Text)
  became `hook(...)` too.
- **Timers:** `C_Timer.After(0, fn)` and the tooltip's
  `C_Timer.NewTimer(INTENT, fn)` are `after(...)` from `wowlua:timer`
  (`C_Timer.NewTimer` underneath, errors reported). `intent:Cancel()` works
  on the handle as before.
- **WindowSkin's event frames:** the per-window `PLAYER_REGEN_ENABLED`
  frame (protected windows) and the row's `rowWait` frame are
  `events.onGame("PLAYER_REGEN_ENABLED", fn, owner)` now, owners
  `"UI.SkinWindow"` and `"UI.WindowRow"`. Same event, one dispatcher;
  errors go to Fault under that owner.
- **`ns.WindowRow`:** the functions are module exports `add`, `layout`,
  `queue`; the state table (`list`, `seq`, `placing`, `queued`) is exported
  as `windowRow` (only WindowSkin used it). `UI.WINDOW_HEAD_H` is
  `export const WINDOW_HEAD_H`.
- **`ns.Mixins.*`** (WindowChrome, MicroMenu, Notification) are set on
  `mixins` from `/Core/Init`. Method tables are `{ [string]: any }` and the
  frames they go on `any` (they carry fields of their own).
- **Renamed locals only to avoid shadowing an import** (no behaviour
  change): Alert `text` → `readable`; WindowSkin `text` → `label` (two
  places); Notification `text` → `line`/`label`, `x` → `bx` in the inner
  button and badge loops (they shadowed the outer `x`; same values);
  Notification `SetIcon(icon)`'s parameter → `def` with `local icon`;
  LevelUp `coins(copper)` → `coins(amount)` with `local copper`; MicroMenu
  `SetActive(key, on)` and Notification `SetNotesHidden(on)` → a parameter
  plus `local on`; Tooltip/ContextMenu `/Core/Root`'s `root` imported as
  `suuRoot` (ContextMenuFrom has a local `root`). Reskin's local
  `draw()` functions are `redraw()` (the `/UI/Draw` namespace is `draw`);
  the fields stay `suuCheck.draw`, `suuButton.draw`, `suuCollapse.draw`.
- **Tooltip `spellTooltip`:** `addExtra(tooltip)` read the module's
  `pending.lines`; it takes the lines as a parameter now (always the
  pending entry's lines, as before). The post-call reads `pending` into a
  local first (narrowing).
- `skinTooltip` returns `nil` explicitly when already skinned (was a bare
  `return`); callers that ignore the result see no change.
- `Alert:SetTone` reads `TONES[tone] or assert(TONES.danger)` (the danger
  tone always exists).
- Event owners are unchanged (`"UI.Alert"`, `"UI.TooltipFrame"`,
  `"UI.FilterMenu"`, `"UI.LevelUp"`, `"MicroMenu"`, `"UI.Notification"`,
  `"UI.SkinWindow"`, `"UI.ReskinFillBar"`; `EventRegistry`'s
  `"SuuUI.Reskin"`).
