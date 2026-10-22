# Port notes: units-character

Files: `src/Units/Collections.wowlua`, `DressingRoom.wowlua`,
`CharacterWindow.wowlua`, `Inspect.wowlua`, `Durability.wowlua` (wowlua
0.9.1, strict, 2026-10-20).

## 1. VM suspicions

(the VM wasn't run for these files)

## 2. Compiler/tooling issues (0.9.1)

### `wowlua:*` imports read as `any` inside SuuUI (not reproduced in a scratch project)

In this worktree every stdlib import is typed `any`, while SuuUI's own
imports are typed. Checked by adding these lines to `Units/Durability`:

```wowlua
import after from "wowlua:timer"
import isSecret from "wowlua:secret"
import SuuUI from "/Core/API"
local zz: number = after          -- accepted
local zy: number = isSecret       -- accepted
local zx: number = SuuUI.FullName -- E2001, as it should be
```

In a fresh `wowlua new --flavors camelot` project (strict) the same
`local zy: number = isSecret` is an E2001 (`(v: unknown) -> boolean`), also
with a workspace library dependency that imports `wowlua:secret` too, and
with files that have parse errors, E1011 or E1012 next to it. So something in
this tree's current state turns them into `any`; probably the in-progress
errors elsewhere. Worth checking again once the tree is clean.

What it changes here: `isSecret(x)` doesn't narrow `T | Secret<T>`, so
`class and not isSecret(class) and class:lower()` is an E2040 in SuuUI and
fine in the scratch project. Workaround (works in both states): a cast after
the guard, `(class :: string):lower()` (`Inspect` `M:Draw`,
`CharacterWindow` `M:UpdateIdentity`). The cast stays correct once the
imports are typed again (it is then a no-op), so it doesn't need undoing.

### `canaccessvalue` in an `and` chain doesn't narrow

```wowlua
local _, class = UnitClass("target")
local a = class and not issecretvalue(class) and class:lower()  -- fine
local b = class and canaccessvalue(class) and class:lower()     -- E2040: `Secret<string>` may be a secret value
```

The conventions say both narrow; `issecretvalue` (and `wowlua:secret`'s
`isSecret`, in a project where it is typed) does in an `and` chain,
`canaccessvalue` doesn't. Not used in these files (they use `isSecret`).

## 3. Stdlib gaps

### A "plain value" predicate

All five files (and most Units) define `local function plain(v) return v ~=
nil and not isSecret(v) end` and then write `plain(x) and x and …`.
`secret.known(v, fallback)` needs a fallback and changes the shape of the
code; `isSecret` doesn't exclude `nil`. A `secret.usable(v): v is T` (not nil,
not secret) that narrows `T | Secret<T> | nil` to `T` would replace the
helper and the doubled `plain(x) and x`. Kept SuuUI's `plain` (now typed
`(v: any): boolean`).

### A quiet guarded call

The files' `call(fn, ...)`: `nil` when `fn` isn't a function, `pcall`'s
results on success, `nil` on an error, never reported (used on game APIs
that may be missing on Forever or error on bad IDs). `wowlua:errors`'
`call`/`callIn` report the error and return `ok` first, so they don't fit.
Kept SuuUI's helper (typed to return `any`s).

## 4. Port decisions

- **stdlib used:** `wowlua:timer` `after` for every `C_Timer.After` and
  `C_Timer.NewTimer` (Durability's alert timer, Collections' names timer;
  both still `:Cancel()`-able), `every` for Collections' one-second toy
  ticker; `wowlua:hooks` `hook` for every `hooksecurefunc`, `hookScript` for
  `HookScript` on Blizzard frames (CharacterFrame, PaperDollFrame, gear
  slots and their popouts, EquipmentFlyoutFrame, the gear set popup, the
  stats panes, the right pane toggle, the other tabs' panes, InspectFrame,
  DressUpFrame and its ModelScene.ControlFrame, CollectionsJournal);
  `HookScript` on SuuUI's own frames (windows, scroll areas, the secure
  action buttons) stays as it was. `wowlua:secret` `isSecret` replaces each
  file's `issecretvalue or function() return false end`.
  Observable differences: an error in one of these hooks or timers is now
  reported through `wowlua:errors` (`callIn`) instead of going straight to
  the game's error handler; `after(0, fn)` makes a `C_Timer.NewTimer`
  instead of `C_Timer.After` (same timing).
- **Inspect:** `hooksecurefunc("InspectFrame_Show", …)` is now
  `hook(_G, "InspectFrame_Show", fn, { addon = "Blizzard_InspectUI" })` (the
  compiler's W8102 suggestion). `HookInspect` only runs once `InspectFrame`
  exists, so the addon is loaded and the hook goes on at once, as before.
  `M:Asked(unit)` lost its parameter (it never used it; the hook passed the
  game's argument).
- **Secret guards added** (the strict checker requires them; each one only
  changes what happens with a secret, where the old code would have
  errored): `Inspect` `M:Draw` and `CharacterWindow` `M:UpdateIdentity`
  skip the class colour when `UnitClass`'s token is secret; `Inspect`'s
  `INSPECT_READY` handler skips the redraw when `UnitGUID` is secret instead
  of comparing it (it also calls `UnitGUID` before the window check now:
  harmless).
- **Casts:** `DressingRoom` `yours(s[1] :: number)` (the `SLOTS` rows mix a
  number and a string); `Collections` `def[1] :: string` (the control
  buttons' rows mix strings and functions). `Collections` `slotDef` returns
  an optional row: the two places that indexed it unchecked now `assert` it
  (`slotDef("CHESTSLOT")` and a slot button's own slot, both always found;
  the old code would have errored on `nil` too).
- **Types:** entries and CollectionSources rows are `{ [string]: any }`
  (`Entry`, `Source` in Collections); Durability's pieces got a `Piece`
  record. Frames that carry fields of their own (rows, cells, tiles, cards,
  the figure) are `any`.
- **Bugs noticed, left:** `Collections` `LayoutCells`, `LayoutTiles` and
  `LayoutShelf` compare the width (`w <= 0`) before testing `isSecret(w)`,
  so a secret width would error before the guard (the guard should come
  first). Pre-existing warnings left as they were: `CharacterWindow`'s
  unused `isWhite`, `prev`, `w` and the `shown` shadow; `Collections`'
  unused `MAX_SHOWN` and `file` (twice) and its shadows.
- **API names these files use** (all in `/Core/API` already):
  `SuuUI.Durability`, `CollectionSources`, `CollectionsShown`,
  `ToggleCollections`, `ShowAlert`, `HideAlert`, `ShowTalentsOf`,
  `FullName`, `GetModule`, `SuppressBlizzard`, `Root`, `EditMode`,
  `Motion.FadeIn`, `Fonts.Apply`, `UI.*`, `Tokens`. `Collections`' `data()`
  is typed `{ [string]: any }`: if `SuuUI.CollectionSources()` gets a
  narrower type later, that line may need a cast.
