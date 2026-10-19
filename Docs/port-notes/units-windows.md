# Port notes: units-windows

Files: `src/Units/Windows.wowlua`, `src/Units/Nameplates.wowlua`,
`src/Units/Tooltips.wowlua`, `src/Units/Minimap.wowlua`,
`src/Units/Addons.wowlua` (from the `.lua` files, `git mv`). Strict mode, no
errors and no warnings in these five files.

## 1. VM suspicions

None (the VM was not run for these files).

## 2. Compiler/tooling issues

### `cond and x` with a boolean `cond` is typed `true | x`

The falsy result of `a and b` is `a`'s falsy part (`false`), but 0.9.1 keeps
`true` in the union, so a truthy test leaves `true` behind:

```wowlua
local function f(text: unknown, ok: boolean): string?
    local a = ok and ("x"):match("(%d)")
    if a then return a .. "%" end          -- E2001: cannot concatenate `string | true`
    return nil
end
```

Workaround (Nameplates `questObjective`): `… and text:match(…) or nil` (a
false condition gave `false` before, `nil` now; the value is only tested).

### `pcall` widens a `false` return to `boolean`

```wowlua
local function q(n: number): string | false
    if n > 1 then return "x" end
    return false
end
local r = q(2)
if r then print(r .. "!") end              -- fine: r is string
local ok, r2 = pcall(q, 2)
if ok and r2 then print(r2 .. "!") end     -- E2001: cannot concatenate `string | true`
```

Workaround (Nameplates `questText`): `if ok and r then result = r :: string end`
(the same values as `result = ok and r or false`).

### Declarations

- `Minimap:GetZoom()` and `Minimap:GetZoomLevels()` are declared without
  returns (`local z: number = Minimap:GetZoom()` → "`nil` is not assignable
  to `number`"). Workaround (Minimap `M:Zoom`, `M:PlaceMinimap`):
  `Minimap:GetZoom() :: any` into a `number` local.
- `C_NamePlate.SetNamePlateSize(width, height)` is declared with `string`
  parameters (`SetNamePlateSize(140, 30)` → E2001); the game takes numbers.
  Workaround (Nameplates `M:ApplyGameSettings`):
  `pcall(C_NamePlate.SetNamePlateSize :: any, …)`.

## 3. Stdlib gaps

### `wowlua:hooks` on a hot hook

Nameplates hooks `SetAlpha` on every Blizzard nameplate UnitFrame it hides,
to put the alpha back to 0. That hook runs on every alpha change of every
plate (the game fades plates often). `hook` from `wowlua:hooks` wraps the
handler in `callIn`, which packs the arguments into a table and builds a
closure for `xpcall` on every call, so it stays `hooksecurefunc` (commented
in the code). The stdlib would fit with an option for hot hooks that skips
the per-call allocation (e.g. `{ isolate = false }`, or passing the
arguments to `xpcall` directly where the client's xpcall takes them;
not probed).

### Per-plate unit events

Each nameplate keeps its own event frame with `RegisterUnitEvent(e,
f.unit)`, re-registered when the pooled plate gets another unit. Neither
`M:OnUnitEvent` (the module's lifetime) nor `wowlua:events` `onUnit`
(a fixed unit list per subscription, unsubscribed by `off`) has a
"re-point this subscription at another unit" call; the frame stays.

## 4. Port decisions

- **Secret helpers.** `local isSecret = issecretvalue or function() return
  false end` became `import isSecret from "wowlua:secret"` in all five files
  (the same: false where the client has no secrets). `plain(v)` (Tooltips,
  Addons) is a predicate `v is string | number | boolean | table`, and its
  two tests are swapped to `not isSecret(v) and v ~= nil` (comparing a
  possibly secret value is an error to the checker; the result is the same).
  Minimap's `readable(v)` is `v is number`. Every secrecy guard is kept; none
  added.
- **Hooks and timers** through the stdlib: `hooksecurefunc` → `hook`,
  `HookScript` on Blizzard's frames → `hookScript` (Windows: all 29, on the
  windows, tabs, map, quest log and trainer; Tooltips: GameTooltip
  OnHide/OnTooltipCleared; Addons: AddonList OnShow), `C_Timer.After` /
  `NewTimer` → `after`, `NewTicker` → `every` (Minimap's clock, Addons'
  perf ticker). Handlers now run through `callIn`: an error is reported by
  wowlua:errors instead of being raised into Blizzard's call. They're still
  post-hooks; nothing of Blizzard's is replaced and nothing new is written
  on Blizzard's frames. Addons' `HookScript`s on SuuUI's own window and
  scroll area stay method calls.
- **Load-on-demand hooks** (Windows: `ClassTrainerFrame_InitServiceButton`,
  `…_InitCategoryButton`, `ClassTrainerFrame_Update`,
  `CollectionsJournal_UpdateSelectedTab`) are written `hook(_G, "Name", fn)`
  (the same as `hooksecurefunc("Name", fn)`): W8102 suggests
  `{ addon = … }`, but they are already installed only after an existence
  check, when the addon has loaded; the option would change when they're
  installed.
- **Minimap `M:Overlay`**: the one-shot PLAYER_REGEN_ENABLED frame that set
  the overlay's pass-through after combat is `defer(passThrough)` from
  `wowlua:combat` (runs now out of combat, at the fight's end otherwise).
  It now runs from wowlua:combat's own PLAYER_REGEN_ENABLED listener, so its
  order relative to SuuUI's other PLAYER_REGEN_ENABLED handlers may differ.
- **`GetMinimapShape`** (for LibDBIcon and others) is written as
  `_G.GetMinimapShape = …` (a global SuuUI must create).
- **Auras as `any`** (Tooltips `AddAuraLines`, `AddSource`): 0.9.1 types
  `C_UnitAuras.GetAuraDataByIndex`'s result as `AuraData | Secret<AuraData>`.
  The code read `a.name`, `a.sourceUnit` … without testing `a` itself for
  secrecy (only its fields); kept that way through `a: any`. If the game
  ever returns a secret aura table there, `a.name` raises (in `AddSource`
  inside `M:Guard`; `AddAuraLines` runs out of combat only). Not changed.
- **Preview data as maps**: Nameplates' `PEOPLE` (records of different
  shapes) is `{ [string]: any }[]`. `C_ClassColor.GetClassColor(...)` in
  the preview is cast to `ColorMixin` (the preview names real classes).
- **Small renames** for warnings the Lua already had: Windows' `label(b)`
  → `tabLabel(b)` (three locals named `label` shadowed it); Nameplates'
  inner `boss` → `isBoss`; Tooltips' `after` capture → `rest` (it would
  shadow the imported `after`); Tooltips' local `hook` helper →
  `hookSetter`.
- **Addons**: `M:DrawRow` computes `memory(e.memory)` once into a local
  (it was called twice; same text). `#e.children` is behind
  `suite and e.children` (suite already implied it). `bare(text)` keeps its
  two results (the last gsub's), typed `(string, number)`.
- Callbacks into `SuuUI.UI` components (`onChange`, `onClose`, `preview`)
  have their parameters typed by hand (`SuuUI.UI.*` reads as `any`).
