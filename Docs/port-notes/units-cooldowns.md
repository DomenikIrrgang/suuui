# Port notes: units-cooldowns

Files: `src/Units/CooldownManager.wowlua`, `Defensives.wowlua`,
`BuffIndicators.wowlua` (wowlua 0.9.1, strict, 2026-10-20). All three check
with no errors; one warning left (below).

## 1. VM suspicions

(the VM wasn't run for these files)

## 2. Compiler/tooling issues (0.9.1)

### C-cd1. Any import cycle in the project stops stdlib type predicates from narrowing

With an import cycle anywhere in the project (even between two modules the
user never imports), `isSecret` from `wowlua:secret` no longer narrows, in
every module, whether imported by name or as `secret.isSecret`. A predicate
declared in a project module still narrows. Without the cycle all of it
checks.

```wowlua
-- A.wowlua
import * as b from "./B"
export function fa(): number return 1 end
export function ga(): number return b.fb() end
-- B.wowlua
import * as a from "./A"
export function fb(): number return a.fa() end
-- main.wowlua
import isSecret from "wowlua:secret"
local c = UnitName("player")
if not isSecret(c) and c then print(c:lower()) end
-- E2040: `Secret<string>` may be a secret value (only while A <-> B exists)
```

Repro: `scratch-units-cooldowns/X`. SuuUI has such cycles (Core/Events <->
Core/Fault, and the lazy ones the conventions allow), so in SuuUI the
stdlib's `isSecret` never narrows. Workaround in CooldownManager, which
needs it to narrow aura data from `C_UnitAuras.GetAuraDataByIndex`:

```wowlua
local function isSecret(v: unknown): v is Secret<unknown> return secret.isSecret(v) end
```

(Defensives and BuffIndicators use `secret.isSecret` directly: they never
rely on it narrowing.)

## 3. Stdlib gaps

### `wowlua:table` `copy` keeps shared tables shared

All three files keep SuuUI's own deep `copy` (CooldownManager also
`deepCopy`): it copies a table that appears twice as two tables, and keeps
keys as they are. `wowlua:table`'s `copy` keeps shared and cyclic
references shared and deep-copies keys. The lists can share tables (a new
entry's `ids` is the table "+ Add" built for that name), and the copy goes
into the saved setups, so the port keeps SuuUI's. A `copy(t, { shared =
false })` (or a `tree` copy) would fit. `same` in CooldownManager does use
`wowlua:table`'s `equal` (identical for non-secret data, which saved lists
are).

## 4. Port decisions

- **`CLASS`** (CooldownManager, BuffIndicators) is
  `secret.known(classFile, "")`, as Core/Roles does: the player's class is
  never secret, so nothing changes.
- **`C_Timer.After`** -> `after` from `wowlua:timer` (CooldownManager's three:
  "Seen recently" scans and the spec check after talent events). An error
  in them is now reported through wowlua:errors.
- **Saved data stays `any`**: entries, lists, setups, conditions and the UI
  components' objects (SuuUI.UI.* reads as any) are `any`; the entry paths
  are a `Path` type (`{ key, i, j?, m? }`). Defensives' preview people are a
  record type `Person`.
- **Narrowing guards added without changing behaviour**: `spellLookup`
  (all three) returns nil before the name lookup when the query isn't a
  number (it returned nil after it before); `treePoints` and
  `readLiveTalents` stop when there is no active config (the loops were
  empty then); `moveEntry` checks the two indexes it already relied on;
  `entryFor`'s `id` is `... or nil` instead of `false`.
- **`specPreset`** takes `number?`: `M:Setup(nil)` matched no tree and fell
  back to the first preset, and still does (not `spec or 0`, which would
  pick the Unspecced preset).
- Optional record fields need `name?: T`; `name: T?` is a required field
  that may hold nil, so a literal without it doesn't fit (Defensives'
  preview people).
- Left as it was: `buildConditionRow(parent)` shadows `buildEditor`'s
  `parent` (W1004, from the original). One unused callback parameter
  (`path` in `candidates`' walk) was dropped.
