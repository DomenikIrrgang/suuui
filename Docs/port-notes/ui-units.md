# Port notes: ui-units

Files: `src/UI/UnitFrame`, `Auras`, `CastBar`, `ClassBars`, `ResourceBar`,
`RestedSign`, `WeaponEnchants` (all `.wowlua`, strict).

## 1. VM suspicions

None (the VM wasn't run for these files).

## 2. Compiler/tooling issues

### U1. An imported type predicate stops narrowing when the project has an import cycle

**Fixed** (2026-10-23): imported predicates narrow in SuuUI now; the local
copies (`plain`, `isSecret`, `str`, `num`, `call`) are gone in favour of
`wowlua:secret`, `wowlua:errors`' `try` and the stdlib's frame readers.

`secret.isSecret` (`v is Secret<unknown>`) narrows as expected in a small
project, but in SuuUI it doesn't narrow at all: `Core/Fault` and
`Core/Events` import each other, and any import cycle anywhere in the
project is enough, even one the checked file has nothing to do with. A
predicate function defined in the file itself still narrows. Minimal repro
(scratch project, strict):

```wowlua
-- src/A.wowlua
import * as b from "./B"
export function a(): number return b.b() end
-- src/B.wowlua
import * as a from "./A"
export function b(): number return 1 end
export function c(): number return a.a() end
-- src/main.wowlua
import * as secret from "wowlua:secret"
local function f(): number
    local hp = UnitHealth("player")
    if secret.isSecret(hp) then return 0 end
    return hp   -- E2001: `number | Secret<number>` is not assignable to `number`
end
```

Delete `B.wowlua`'s import of `./A` and the error goes away. The same
happens with `import isSecret from "wowlua:secret"`, and with a local alias
(`const isSecret = secret.isSecret`).

Workaround (UnitFrame, CastBar, ClassBars, WeaponEnchants): a local
predicate that calls the stdlib one:

```wowlua
local function isSecret(v: unknown): v is Secret<unknown> return secret.isSecret(v) end
```

`secret.known(v, fallback)` works in the cycle (its generic return type
holds). ResourceBar only needs `isSecret` as a yes/no answer, so it keeps
`const isSecret = secret.isSecret`.

### U2. `canaccessvalue` doesn't narrow

Spec §2.11 and the port conventions say `canaccessvalue(v)` narrows (the
complement of `issecretvalue`). In 0.9.1 it is declared
`declare function canaccessvalue(value: unknown): boolean` (decl/lua.d.wowlua:221),
so it narrows nothing:

```wowlua
local n = UnitPower("player", 4)
if canaccessvalue(n) then return n end   -- E2001 (in a function returning number)
```

The port doesn't use it; `issecretvalue` (declared as a predicate) works.

### U3. A method on a `setmetatable` table doesn't override the `__index` base's method

```wowlua
local Base = {}
function Base:Layout(count: number) print(count) end
local Derived = setmetatable({}, { __index = Base })
function Derived:Layout() print("own") end
function Derived:Refresh() self:Layout() end   -- E2007: missing argument `count`
```

The type of `self` inside `Derived`'s methods takes `Layout` from `Base`
even though `Derived` defines its own (before or after the call). The
call is right at run time (Lua finds `Derived.Layout` first).
Workaround in ClassBars: `local Totems: any = setmetatable({}, { __index = CB })`
(the totem bar's own `Layout()` replaces the class bars' `Layout(count)`).

## 3. Stdlib gaps

### `wowlua:aura`'s `container` and SuuUI's `auraContainer`

`aura.container(parent, opts)` wraps the same engine aura container as
`UI/Auras` (the filter string sorted, the flow setters with the old and new
names, release for reuse, a re-scan when the unit token points at someone
new). SuuUI's version keeps its own code because it needs what the stdlib's
doesn't have: `lazy` groups (added to the engine only once their count is
above 0, ~10 MB saved in a raid), per-group `index`/`gap` layout
(`SetGroupPlace`), `exclude` spell IDs, `SetGroupFilter`, `SetGroupSize`
(resizing the engine's existing buttons), the edit-mode `ShowPreview`,
returning nil when the client has no containers (the stdlib raises), the
initializer's button list, Fault reports and `extend.add("auracontainer", …)`.
The re-scan also goes through `/Core/Events` with the container as owner
(the stdlib keeps a watcher frame of its own). A stdlib container with
`lazy`, `layoutIndex`/`groupSpacing`, `excludeSpellIDs`, a live filter and
size, and a non-raising constructor would cover it.

### `wowlua:format` for numbers and times

UnitFrame's `shortNumber` ("8.5k", "12k", "1.2m"; a secret goes to
`AbbreviateNumbers`) and WeaponEnchants' `digits` ("42", "1:30", "5m", "1h")
and `longTime` ("1 h 5 min") have SuuUI's own lowercase/short formats.
`format.abbreviate` gives the client's "8.5K", and `format.short`/`duration`
give the client's localized words, so all three stay as they were.

### `wowlua:unit` in UnitFrame

UnitFrame reads its unit through `self.api` (the game's `_G`, or a stand-in
for previews: `unitStandIn`), so the stdlib's `unit.health`/`healthPercent`
can't replace those calls; it stays on the `A.Unit*` pattern.

### `wowlua:secure`'s `visibility` for the pet bar

The pet bar unregisters its state driver and shows itself in keybind mode
(and hides when disabled) inside one `combat.run` job. `secure.visibility`
only registers, so the bar keeps `RegisterStateDriver`/`UnregisterStateDriver`.

## 4. Port decisions

- **Mixins:** `ns.Mixins.UnitFrame/AuraContainer/CastBar = …` became
  `mixins.UnitFrame = …` (from `/Core/Init`). Method names on the mixins and
  on the returned objects are unchanged. `UF` is typed `any`: its methods
  pass `self` (the frame) to typed functions (`auraContainer(self, …)`,
  `deco:SetAllPoints(self)`), and the checker types `self` as the mixin
  table. The other mixins check fine as plain tables.
- **`ns.Interrupt`** became the exported data table `interrupt` (`spell`,
  `bars`, `usedAt`, `cooldown`) plus the functions `find`, `ready`,
  `remaining`, as the symbol map has it. The table no longer carries
  `Find`/`Ready`/`Remaining`; nothing outside CastBar used them.
- **Secret guards added where the checker saw a possible secret** (the old
  code would have raised on one, so nothing that worked changes):
  - `UnitClass("player")`'s class (ResourceBar's `usesPoints`/`Refresh`,
    CastBar's `find`/`isInterrupt`) reads through `secret.known(class, "")`:
    a secret class counts as no class instead of erroring on `==`/indexing.
    Your own class is never secret on Forever.
  - CastBar `ready()`: `if not cd or isSecret(cd) or isSecret(cd.isActive)`;
    a secret cooldown table is "unknown" (nil) instead of an error on indexing it.
  - ResourceBar: the combo points `n == nil` is `type(n) == "nil"`, and the
    count compared with the segments is `secret.known(n, 0)` (only used
    when `n` isn't secret, as before).
- **`amount`** in UnitFrame and ResourceBar is `secret.amount` (the same: a
  secret passes, nil becomes 0); the old comments stay on it.
  ClassBars' `known` is `secret.known` (the same).
- **Timers:** `C_Timer.NewTimer` (the health ghost), `C_Timer.NewTicker`
  (UnitFrame's poll, WeaponEnchants' scan) and `C_Timer.After` (WeaponEnchants'
  `later`, ClassBars' picker close and arrow hide) are now `after`/`every`
  from `wowlua:timer`: same timing; the handles still have `Cancel()`; an
  error in the callback is reported through `wowlua:errors` instead of going
  straight to the game's handler.
- `IsSpellKnown(id)` → `IsSpellKnown(id, false)` (CastBar): the declaration
  requires `isPet`; nil and false mean the same to the client.
- **Casts with no run-time effect:** `SIZES[opts.size or "md"] :: Size`
  (an unknown size still fails as before), `SLOTS[slot] :: Slot` in
  WeaponEnchants' scan (its keys come from `ORDER`), `(seen[slot] :: Seen).duration`
  (set when the enchant is first seen), ClassBars' `id :: number` for a
  spell action's ID and `GetSpellName(spellID :: number)`,
  `TOTEM_MULTI_CAST_SUMMON_SPELLS :: any`, and the aura formatter's
  breakpoints typed `NumericRuleFormatBreakpoint[]` (a literal union of four
  shapes didn't match the declaration).
- **Renamed locals** (shadowing the new imports/exports): CastBar's `Tick`
  `remaining` → `left` and `UpdateKick`'s `ready` → `isReady`; UnitFrame's
  `LayoutRow` local `metaText` → `metaValue` (it shadowed the function
  `metaText`); Auras' `expiringColor` uses `at` instead of reassigning its
  `seconds` parameter. `/UI/Text` is imported as `uiText` everywhere (CastBar
  and WeaponEnchants have locals named `text`), `/UI/Icon` as `iconModule`.
- Removed an unused local (`local size = self.size` in `UF:UpdateIdentity`).
- `ns.EditMode and ns.EditMode.IsActive()` (ResourceBar) and
  `ns.KeybindMode and ns.KeybindMode.IsActive()` (ClassBars) are now plain
  calls of the imported `isActive`; both only run after load.
- UnitFrame's `UI.GroupIndicators`' list was a local named `groupIndicators`,
  which is now the export's name: the local is `indicators` (and
  `defensives` for the defensives list).
