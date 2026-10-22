# Port notes: units-group

Units/RaidPlanner, Units/RaidFrames, Units/PartyFrames, Units/Readiness,
Units/Marks (wowlua 0.9.1, strict).

## 1. VM suspicions

(the VM was not run for these files)

## 2. Compiler/tooling issues

### An import cycle anywhere in the project stops imported type predicates from narrowing

`import isSecret from "wowlua:secret"` (or `secret.isSecret` through a
namespace import) narrows `v` in a project without import cycles. Add any
cycle, even between two files unrelated to the one checked, and the imported
predicate narrows nothing: neither branch drops `Secret<…>`. A predicate
declared in the same file still narrows. SuuUI has such cycles
(`/Core/Init` ↔ `/Core/Modules`, among others), so in this project every
imported predicate is a plain boolean for the checker.

Repro (`wowlua new --flavors camelot X`, `"check": { "mode": "strict" }`):

```wowlua
-- src/A.wowlua
import y from "./B"
export const x = 1
print(y)

-- src/B.wowlua
import x from "./A"
export const y = 2
export function f() print(x) end

-- src/main.wowlua
import isSecret from "wowlua:secret"
import * as secret from "wowlua:secret"

local function sec(v: unknown): v is Secret<unknown> return isSecret(v) end
local function f(): (string | Secret<string>)? return (UnitName("x")) end
local name = f()
if not isSecret(name) then local zz1: number = name end        -- E2001: `nil | string | Secret<string>` …
if not secret.isSecret(name) then local zz2: number = name end -- E2001: `nil | string | Secret<string>` …
if not sec(name) then local zz3: number = name end             -- E2001: `string?` … (narrowed)
```

Delete A and B and all three report `string?` (narrowed), as they should.
(The `number` targets are only there to print the narrowed type.)

Workaround in all five files: wowlua:secret's test wrapped as a predicate of
the file's own, where the old `local isSecret = issecretvalue or …` stood:

```wowlua
import * as secret from "wowlua:secret"
local function isSecret(v: unknown): v is Secret<unknown> return secret.isSecret(v) end
```

Once the compiler is fixed, this becomes `import isSecret from "wowlua:secret"`.
Other files that import `isSecret` directly (UI/SwingTimer, UI/Text,
UI/ThreatMeter, UI/ActionBar, Units/Minimap, Units/ChatCommands,
Units/Inspect when I looked) get no narrowing from it.

## 3. Stdlib gaps

None. `wowlua:secret` (isSecret), `wowlua:timer` (`after` for C_Timer.After
and NewTimer, `every` for NewTicker) and `wowlua:hooks` (`hook`,
`hookScript`) fit as they are. Both Blizzard-frame hooks are in Marks: the
waypoint provider's `RefreshAllData`, and the world map's `OnHide`. HookScript
calls on SuuUI's own frames are unchanged: the preview views, the raid
planner window and its checkboxes, and the secure raid buttons'
`OnAttributeChanged`.

## 4. Port decisions

- **Secure group frames are unchanged.** The header templates and
  attributes, `INIT` (restricted code), `RegisterStateDriver`,
  `RegisterUnitWatch` and the `InCombatLockdown` guards are as they were,
  inside the same `RunOutOfCombat` calls. Only parameter annotations
  changed around them.
- **Timers through wowlua:timer** run their function under the stdlib's error
  isolation (`callIn`), so an error is reported, not raised from the timer.
  `self.indicatorTimer:Cancel()` and `self.rangeTicker:Cancel()` work on its
  handles as before.
- **Readiness `ReadOwn`**: `C_Spell.GetSpellCooldown` is typed as possibly a
  secret table, so the check is now `cd and not isSecret(cd) and readable(…)`.
  This runs out of combat only, and a secret table would have raised an error
  on `cd.startTime` before, so nothing a player sees changes. `readable` is a
  predicate now (`v is number`).
- **Your own name and class are never secret.** Casts with a comment:
  Readiness `playerClass()` / `playerName()` (a small helper for
  `Ambiguate(SuuUI.FullName("player"), "short")`, used twice as before), and
  Marks `OnMessage` (`UnitFullName("player")` read into locals cast to
  `string`). No comparisons were added. The realm is cast to `string` and not
  `string?` because 0.9.1 refuses `string | Secret<string>` as `string?`
  (E2015). The `realm and …` check that guards against nil is still there.
- **`plain(v)`** (Marks, RaidPlanner) is a predicate `v is Readable` (string,
  number, boolean, table, function), the same as units-chat's. The body is
  unchanged.
- **Undeclared on camelot:** `LE_PARTY_CATEGORY_INSTANCE` (Marks) and
  `InviteUnit` (RaidPlanner, the fallback behind `C_PartyInfo.InviteUnit`)
  are read through `_G`.
- **RaidFrames `person`** reads `people[i]` into a local before filling it
  (a map read is optional in strict mode). The result is the same.
- **Marks `symbolButton(card, i, symbol)`** lost its unused `i`.
- **Readiness**: the unused `T` local was removed.
- **RaidPlanner `unesc`**: `tonumber(h, 16) or 0`. The pattern only matches
  two hex digits, so the `or 0` never applies.
- Data from saved variables, the catalog and SuuUI.UI frames is typed `any`
  (setups, slots, roster entries, unit frames, the planner window). Records
  are declared where the file builds the table itself: `AuraGroup`
  (Party/RaidFrames), `Mark` (Marks), `Member` (Readiness).
- These warnings were already there and are left as they are: RaidPlanner's
  unused `SIZES`, and the `key` and `on` parameters that shadow the local
  functions `key()` and `on()`.
