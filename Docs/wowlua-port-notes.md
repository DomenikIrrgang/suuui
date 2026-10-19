# wowlua port notes

Notes from porting SuuUI to wowlua 0.9.1 (branch `wowlua-port`, 2026-10-20),
for review together. This file merges the per-area notes in
`Docs/port-notes/*.md` (one per porting agent; they keep the full detail).
Four kinds:

1. **VM suspicions**: where the emulated client (`wowlua test`) seems to
   behave differently from the game.
2. **Compiler and tooling issues** in 0.9.1, with the workaround the port uses.
3. **Standard library gaps**: where a stdlib module nearly fit, what SuuUI
   keeps on top of it, and what the stdlib could offer instead.
4. **Port decisions to review**: behaviour changes, bugs seen and left, things
   to check in game, typing follow-ups.

Each entry names the area notes it came from (`ui-units` is
`Docs/port-notes/ui-units.md`, and so on). The Core entries in sections 3
and 4 come from the comments in `src/Core/*.wowlua`, `wowlua.json` and the
0.9.1 stdlib sources; no area notes file covers Core.

## What was checked

- `wowlua check`: no errors in SuuUI, `foreverlfg` and both example plugins
  (52 warnings, almost all in the code before the port: unused locals,
  shadowing). Every file is strict; none uses `--!nocheck` or `@nocheck`.
- `wowlua test` (the emulated client with Blizzard's UI), all passing:
  `tests/smoke` (login with all 57 modules on, every `/suu` command, every
  module off and on, every settings section, the windows through the API and
  through Blizzard's key bindings, every on/off setting flipped and back, a
  fight with a target and a group) and `tests/compat` (SuuUIDB as the unported
  SuuUI wrote it, its second profile, an SUU1 profile string it exported,
  new strings round-tripping, settings across `/reload`). The smoke
  scenarios also pass on the unported code (run from a separate checkout), so
  they don't hide differences in what the VM can show.
- `wowlua build --release` and `wowlua package`: the bundled `SuuUI.lua` and
  the CurseForge and GitHub zips build.
- Generators: where their inputs are local, regenerating gives byte-identical
  data files (Docs/port-notes/data.md); Tokens are identical to before.
- ForeverLFG's parser: the same results as the unported one on sample chat
  lines (in the VM and through `tools/lfg_parse.lua`).
- Not checked: the game itself. The in-game list below is what to try first.

## Read first

1. [C4](#c4): **any import cycle in the project types every `wowlua:*` import
   as `any`**, and stdlib type predicates (`secret.isSecret`) stop narrowing.
   SuuUI has run-time import cycles (Core/Init ↔ Core/Fault, Core/Events ↔
   Core/Fault, …), so every stdlib call in SuuUI is currently unchecked.
2. [C5](#c5): **`canaccessvalue` doesn't narrow**: it is declared as returning
   `boolean`, contrary to spec §2.2.8. Use `issecretvalue`.
3. [S2](#s2): **the stdlib allocates per call**: wowlua:events builds a
   snapshot per dispatch plus an args table and a closure per handler, and
   wowlua:hooks / wowlua:timer wrap every call in `callIn` (args table,
   closure, `xpcall`). SuuUI's Core/Events now sits on wowlua:events; the hot
   hooks (Draw's colour setters, nameplates' `SetAlpha`) stayed raw
   `hooksecurefunc` because of it.
4. [D-Core1](#d-core1): **profile export strings are now wowlua:serialize
   (`!SUU:2!…`)**. Old `SUU1:` strings still import, but a string exported by
   this build can't be imported by an older SuuUI release.
5. [D-Core2](#d-core2): **the `test` profile sets `runtime-checks` to
   `"exports"`**: `"all"` (the test default) also checks `::` assertions, and
   the casts of half-built frames (`CreateFrame(…) :: Panel`) would fail.
6. [D-X1](#d-x1): **hook and timer errors are now isolated and reported**
   instead of raised into the caller, in almost every file (`hook`,
   `hookScript`, `after`, `every`).
7. [In game](#in-game-checks): the taint-sensitive paths to try before release
   (Escape with bags open in combat, item use from bags in combat, the game
   menu, the action bar event dispatcher, nameplates).

## 1. VM suspicions

Only Data and ForeverLFG ran their code in `wowlua test` (both without
suspicions: Data's presets, trainer lists and spot reads matched; ForeverLFG's
parser parity and runtime smoke tests passed). The other areas didn't run the
VM.

### V1. `debugstack()` paths lack the `Interface/AddOns/<Addon>/` prefix

In `wowlua test`, a stack line reads `tests/smoke/x.test.wowlua:5: in function 'fn'`
(addon files likewise `src/Core/Modules.lua:…`). In the game the chunk names
are `Interface/AddOns/SuuUI/…` (bundled: `Interface/AddOns/SuuUI/SuuUI.lua`).
SuuUI's `RegisterModule` works out which addon registered a module from that
path (`AddOns[/\\]([^/\\]+)[/\\]`), so in the VM every module's source is `?`
and `builtIn` is false (`/suu modules` lists them as "- ?" instead of
"built in"). Seen on the unported code too (baseline), so not a port bug.

Repro: `expect(debugstack(1, 3, 0)).toEqual("")` in any test file.

## 2. Compiler and tooling issues

C1–C3 are the original entries. Entries marked *pattern* are by the spec, not
bugs, but every agent tripped over them.

### C1. `export const x: T = { … }` exports the literal's type, not `T`

Importers see the table literal's inferred (sealed) type, so optional fields
of `T` are missing for them.

```wowlua
-- T.wowlua
export type Tok = { version: number, vision?: { [string]: number } }
export const a: Tok = { version = 2 }
-- U.wowlua
import a from "./T"
a.vision = {}        -- E2051: cannot add the field `vision` to a sealed table
```

Workaround: `export const a = { version = 2 } :: Tok` (or export a typed local).
Used in `src/Core/Tokens.wowlua` (generated by `tools/gen_tokens.py`).

**Also a plain (non-exported) `const`** (ui-hud): the annotation is ignored
there too. With a map of functions, the value type becomes the first function
in the literal:

```wowlua
const H: { [string]: (...any) -> () } = { A = function() end }
for _, h in pairs(H) do h(1) end   -- E2006: too many arguments: expected 0, got 1
local L: { [string]: (...any) -> () } = { A = function() end }
for _, h in pairs(L) do h(1) end   -- fine (and L.A is optional, as a map read should be)
```

**Prefer `export local x: T = { … }` for data** (data): `{ … } :: T` is an
assertion (spec §1.4.3), so it leaves the literal unchecked (a `"bad"` string
in a `number[][]` passes). `export local x: T = { … }` checks every entry
(E2001 at the entry), and importers see `T` with its optional fields. Every
data module and every annotated table in the ui-hud files use the `local`
form.

From: main, ui-hud, data.

### C2. A `table.sort` comparator with a wider parameter type fails to check

The element type is inferred as the union of the list's element type and the
comparator's parameter types, and arrays are invariant in strict mode:

```wowlua
local rows: { name: string, ms: number }[] = {}
table.sort(rows, function(a: { ms: number }, b: { ms: number }): boolean return a.ms > b.ms end)
-- E2001: `{ name: string, ms: number }[]` is not assignable to
--        `({ name: string, ms: number } | { ms: number } | { ms: number })[]`
```

The comparator only reads `ms`, so it should be accepted (parameters are
contravariant). Workaround: name the row type and use it for the comparator.

From: main.

### C3. `table` is not assignable to `{ [string]: any }`

```wowlua
local t: table = {}
local m: { [string]: any } = t   -- E2001
```

`type(x) == "table"` narrows an `any` to `table`, so data read from
SavedVariables that is checked this way then needs a cast to be used as a
map. §2.6 allows `table` → `{ [any]: any }` only. Workaround: `x :: { [string]: any }`.

**The same from a typed namespace or enum** (diag-core, diag-world,
diag-combat): `pairs(C_Trainer or {})` and `pairs(Enum.SpellBookItemType or {})`
give E2001, and `pairs(Enum.BagSlotFlags)` does even without `or {}`.
`(C_Trainer or {}) :: { [any]: any }` gives E2015 ("cannot assert"). What
works is a cast through `any` first: `((C_Trainer :: any) or {}) :: { [any]: any }`
or `pairs((Enum.BagIndex :: any) or {})`. Used in the Diagnostics probes
(BagProbe, BagSortProbe, TooltipProbe, the trainer probes).

From: main, diag-core, diag-world, diag-combat.

<a id="c4"></a>

### C4. Any import cycle in the project types every `wowlua:*` import as `any`

A cycle between any two modules of the package is enough; it needn't touch
the file that imports the stdlib. Then every stdlib import reads as `any`:
calls to `after`, `every`, `hook`, … aren't checked, and `isSecret`'s
predicate (`v is Secret<unknown>`) is lost, whether imported by name, as
`secret.isSecret`, or through a local alias (`const isSecret = secret.isSecret`).
A predicate declared in the file itself still narrows, and so does the global
`issecretvalue`. `secret.known(v, fallback)` still works (its generic return
type holds). A lazy cycle (imports used only inside functions) and an E1014
load-time cycle both trigger it; an E1012 (missing export) doesn't.

```wowlua
-- src/C/A.wowlua
import * as b from "./B"
export function fa(): number return 1 end
export function ga(): number return b.fb() end
-- src/C/B.wowlua
import * as a from "./A"
export function fb(): number return 2 end
export function gb(): number return a.fa() end
-- src/main.wowlua
import isSecret from "wowlua:secret"
import after from "wowlua:timer"
local zy: number = isSecret   -- accepted with C/A+C/B present, E2001 without
local zz: number = after      -- the same
local c = UnitName("player")
if not isSecret(c) and c then print(c:lower()) end
-- E2040: `Secret<string>` may be a secret value (only while A <-> B exists)
```

SuuUI has such cycles on purpose (Core/Init ↔ Core/Fault, Core/Events ↔
Core/Fault, Core/Init ↔ Core/Modules, API ↔ UI modules, API → UI/Legacy →
API; the conventions allow lazy ones). Bisected in a copy of the worktree:
Core/Fault + Core/Init plus one probe file reproduce it. So this won't go away
when the port is done, and every stdlib call in SuuUI is unchecked until the
compiler is fixed.

Workarounds, by file:

- A local predicate that calls the stdlib one (becomes
  `import isSecret from "wowlua:secret"` once fixed):
  ```wowlua
  import * as secret from "wowlua:secret"
  local function isSecret(v: unknown): v is Secret<unknown> return secret.isSecret(v) end
  ```
  UI/UnitFrame, CastBar, ClassBars, WeaponEnchants; Units/CooldownManager,
  RaidPlanner, RaidFrames, PartyFrames, Readiness, Marks, Threat, UnitFrames.
- The global `issecretvalue` where narrowing is needed: Units/FlightMap,
  WorldMap, Campsite; the ui-hud files.
- `secret.known(v, fallback)` (a value, not a predicate): Units/GroupFinder
  `M:AdFromListing`, Social `M:RaidMembers`, GameMenu `M:Draw`.
- A cast after the guard, `(class :: string):lower()`: Units/Inspect `M:Draw`,
  CharacterWindow `M:UpdateIdentity` (a no-op once fixed).
- `pcall(X :: any, …)` on the API call: Diagnostics TrackProbe,
  WeaponEnchantProbe, PartyAuraProbe and other aura/cast reads.

Files that use the stdlib's `isSecret` directly and so get no narrowing from
it (they don't rely on it): UI/SwingTimer, Text, ThreatMeter, ActionBar; Units/Minimap,
ChatCommands, Inspect, Defensives, BuffIndicators, ResourceBar. units-hud also
checked its files with the stdlib's signatures pasted in as local functions:
no errors either way.

From: ui-units (U1), units-cooldowns (C-cd1), units-group, units-hud,
units-social (C-a), units-character, units-maps (U1), ui-hud, diag-combat.

<a id="c5"></a>

### C5. `canaccessvalue` doesn't narrow

Spec 02-types §2.2.8 (and §2.11, and the port conventions) say the true
branch of `canaccessvalue(v)` removes `Secret<…>`. In 0.9.1 it is declared
`declare function canaccessvalue(value: unknown): boolean`
(`decl/lua.d.wowlua:221`), so it narrows nothing, with or without import
cycles, in an `if` and in an `and` chain:

```wowlua
local T: { [string]: string } = {}
local function f(v: string | Secret<string>): any
    if canaccessvalue(v) then return T[v] end   -- E2040: `string | Secret<string>` may be a secret value
end
local _, class = UnitClass("target")
local b = class and canaccessvalue(class) and class:lower()   -- E2040
```

Workaround: the port doesn't use it; `issecretvalue` (declared as a predicate)
works.

From: ui-units (U2), units-character, units-social (C-b), ui-hud.

### C6. Values imported from a wowlua library package are `any`

§10.5.1 says "the consumer sees its exported types". Exported types do come
through; exported values don't, and neither does a `typeof(value)` alias
across the package.

```wowlua
-- library mylib, src/Core.wowlua
export function hello(n: number): number return n + 1 end
-- the addon (depends on mylib by path)
import hello from "mylib/Core"
local s: string = hello(1)   -- no error (from the addon's own ./Foo: E2001)
```

Workaround: ForeverLFG exports an explicit `ForeverLFG` record type (no
`typeof`), and consumers cast or annotate with it: `API.LFG = lfg :: ForeverLFG`
(`src/Core/API.wowlua`), `local LFG: ForeverLFG = lfg` (Diagnostics/LfgProbe).

From: foreverlfg, diag-social.

### C7. Fields added after a table literal are untyped for importers

```wowlua
export const chat = { joined = false }
function chat.Hide(n: number): number return n end
-- importer: `local s: string = chat.Hide(1)` and even `chat.Nope()` pass
```

Workaround: declare the API type and cast an incomplete literal,
`export const chat = {} :: ChatApi`, then `function chat.Hide() … end` (the
assignments are checked against the type). Used for ForeverLFG's `catalogue`,
`chat`, `store`, `tool`, `parser`, `lang` and `lfg`.

From: foreverlfg.

### C8. E5001 instead of the upvalue fallback of spec §5.5

Modules §5.5 says that when a function would need more than 60 upvalues, the
compiler reads the extra imports through their module tables. 0.9.1 fails with
E5001 instead, for namespace and named imports alike:

```wowlua
-- src/m/M1.wowlua … src/m/M62.wowlua: export function command() end
import * as m1 from "/m/M1"   -- … up to m62
export function run(sub: string)
    if sub == "1" then m1.command() return end
    -- … one line per module, up to 62
end
-- error[E5001]: Lua 5.1 limit exceeded: function at line 63 has more than 60 upvalues
```

Workaround (`Diagnostics/Probe.wowlua`): the `if sub == …` chain over ~70
probe modules became a table `TOPIC_COMMANDS` of one small function per
topic, each capturing one module.

From: diag-core.

### C9. Hook warnings ignore an existence check (W8102, W8040)

`hook("Name", fn)` on a load-on-demand function warns (W8102) even inside
`if _G.Name then`, where the addon has already loaded:

```wowlua
import hook from "wowlua:hooks"
export function arm()
    if _G.CollectionsJournal_UpdateSelectedTab then
        hook("CollectionsJournal_UpdateSelectedTab", function() end)
    end
end
-- warning[W8102]: … hook it with
-- `hook(_G, "CollectionsJournal_UpdateSelectedTab", fn, { addon = "Blizzard_Collections" })`
```

Likewise W8040 for a method the declared type lacks (here because
`ChatFrame1` is declared `Frame`, see C36):

```wowlua
if ChatFrame1.ApplySystemAnchor then
    hook(ChatFrame1, "ApplySystemAnchor", function() print("x") end)
end
-- warning[W8040]: `Frame` has no `ApplySystemAnchor` to hook; …
```

Workarounds differ by area (see D-X2): the suggested `{ addon = … }` form
(Diagnostics/CollectionsArtProbe, UI/GroupFinderListing, Units/Inspect);
`hook(_G, "Name", fn)` without the option, which also silences it
(Units/Windows); `hook(ChatFrame1 :: any, …)` (Units/Chat). Dynamic names
(`for _, name in ipairs(…)`) don't warn.

From: diag-world, ui-social, units-character, units-windows, units-chat.

### C10. `cond and x` with a boolean `cond` keeps `true` in its type

`a and b` with a boolean `a` can only be `false` or `b`, but 0.9.1 types it
`boolean | b`, so a truthiness test leaves `true` behind. A comparison in the
middle of a chain leaks `true` too.

```wowlua
local function f(): boolean return math.random() > 0.5 end
local t = { x = 1 }
local y = f() and t
if y then print(y.x) end   -- E2003: cannot index a value of type `true`

export function g(key: string): number
    local dir = (key == "UP" and 1) or (key == "DOWN" and -1)
    if not dir then return 0 end
    return dir * 2      -- E2001: arithmetic on a value of type `number | true`
end

local fixed = 1
local c = fixed and fixed ~= 2 and tostring(fixed)
if c then print(c:upper()) end  -- E2003: cannot index a value of type `true`
```

A cast of the initializer doesn't help; only an annotation does. It hits
SuuUI's common `plain(v) and v and Api(v)` pattern. Workarounds: an annotated
local (`local dir: number | false = …`, UI/Inputs NumberField;
`local single: Person? = … or nil`, Units/Notifications `TestPresence`); an
`if` that assigns (Units/ObjectiveTracker `hereNames`, FlightMap `M:SetTitle`);
`… or nil` (Units/Nameplates `questObjective`).

From: ui-primitives, units-notices, units-windows, units-maps (U4).

### C11. `pcall` widens a `false` return to `boolean`

```wowlua
local function q(n: number): string | false
    if n > 1 then return "x" end
    return false
end
local ok, r2 = pcall(q, 2)
if ok and r2 then print(r2 .. "!") end     -- E2001: cannot concatenate `string | true`
```

Called directly, `r` narrows to `string`. Workaround (Units/Nameplates
`questText`): `if ok and r then result = r :: string end`.

From: units-windows.

### C12. A generic predicate `v is V` doesn't infer `V`

```wowlua
local function plain<V>(v: V | Secret<V> | nil): v is V
    return (v :: any) ~= nil
end
local map = C_Map.GetBestMapForUnit("player")   -- number?
if not plain(map) then return end
C_Map.GetPlayerMapPosition(map, "player")       -- E2001: `V` is not assignable to `number`
local level = UnitLevel("player")               -- number | Secret<number>
local a: number = plain(level) and level or 1   -- E2001: `1 | V` is not assignable to `number`
```

The areas disagree on when: units-talents saw it only for argument types
without a `Secret` member (`nil | number | Secret<number>` narrowed fine);
units-maps saw it with `number | Secret<number>` too, and in the false branch.
Workaround everywhere: a non-generic predicate,
`local function plain(v: unknown): v is string | number | boolean | table`.

From: units-talents, units-maps (U2), units-bags.

### C13. Narrowing is lost inside loops

An annotated local narrowed by an assignment reads as declared inside a
following loop, and a local set to nil before `break` is optional inside the
loop body:

```wowlua
export function h(s: string?): number
    local n: number? = nil
    if s then
        n = 0
        for _ = 1, 3 do n = n + 1 end   -- E2001: arithmetic on a value of type `number?`
    end
    return n or 1
end

local out: number[]? = {}
for _, x in ipairs(xs) do
    if x < 0 then out = nil break end
    out[#out + 1] = x   -- E2005: `number[]?` may be `nil`
end
```

Workaround: count or build into fresh non-optional locals and assign the
optional one after the loop (UI/Alert `Alert:Fit`; Units/FlightMap `hopWay`,
`M:FlightRoute`).

From: ui-windows, units-maps (U3).

### C14. *Pattern:* closures see a reassigned local or parameter as declared

`opts = opts or {}` reassigns the parameter, so closures see it as `T?` (E2005
on `opts.onClick` inside a script handler). Fixes used: a default parameter
(`opts: ButtonOptions = {}`; differs from `or {}` only for `opts = false`;
UI/Controls `button`, Inputs `moneyInput`), or copying into a fresh local
first (UI/TalentTree and other ui-settings files, Units/Mail `Suggestions`,
Units/Talents and Legacy). Module upvalues that later code replaces and
closures must re-read stay `any` or are cast at use (Diagnostics TaxiProbe
`land`, TalentBuildProbe `step`).

From: ui-primitives, ui-settings, units-bags, units-talents, diag-combat.

### C15. *Pattern:* `x: T?` is a required field; `x?: T` is optional

In a record type, `name: T?` must be present (it may hold nil), so a literal
without it doesn't fit (spec §2.2.4):

```wowlua
local function f(opts: { layer: DrawLayer?, sublevel: number? }?) end
f({ layer = "BACKGROUND" })
-- E2001: `{ layer: "BACKGROUND" }` is not assignable to
--        `{ layer: nil | "BACKGROUND" | …, sublevel: number? }?`
```

Use `x?: T` for options tables and records built without every field
(UI/Draw `BorderOptions`, ObjectiveTracker `Entry`, Professions `RecipeRow`/
`Category`, AuctionHouse `Offer`, Defensives' preview `Person`). Two
suggestions from the agents: the error could name the missing field and hint
at `?:` (units-trade), or `x: T?` could accept an absent key as Luau does
(ui-windows).

From: ui-primitives, ui-windows, ui-world, units-trade, units-cooldowns.

### C16. A field with a bracketed key can't be optional

```wowlua
type D = { kind: string, ["not"]?: boolean }   -- E0101: ':' expected near '?:'
type A = { kind: string, ["not"]: boolean? }
local a: A = { kind = "x" }                    -- E2001: `{ kind: "x" }` is not assignable
```

`?:` only parses after a plain name, so a key that is a reserved word can't be
optional. Workaround: `PresetCondition` has a `[string]: any` indexer in place
of the field (`src/Data/Presets/init.wowlua`), which loses the typo check
(E2003) on conditions.

From: data (D1).

### C17. A list literal doesn't fit a record with a numeric indexer and optional fields

```wowlua
type By = { [number]: any, talent?: boolean, what?: string }
local x: By = { "MAGE" }                        -- E2001: `"MAGE"[]` is not assignable
local w: By = { "DRUID", 2, talent = true }     -- fine
type Art = { [number]: any, jewel?: boolean }
local a: Art = { "x", 1, 2 }                    -- E2001 (`any[] & { jewel?: boolean }` fails the same way)
```

A literal that is only a list is typed as an array first, and the array isn't
assignable to the record although every named field is optional (§2.2.4 lists
`{ [number]: V, n: number }` for tables used both ways). Workarounds:
`{ [string | number]: any }` for the raid planner's `by` entries
(`RaidProvider`, Data/RaidPlanner); `{ … } :: any` on the dragon art entries
without a jewel (UI/Crest).

From: data (D2), ui-primitives.

### C18. A method on a `setmetatable` table doesn't override the `__index` base's

```wowlua
local Base = {}
function Base:Layout(count: number) print(count) end
local Derived = setmetatable({}, { __index = Base })
function Derived:Layout() print("own") end
function Derived:Refresh() self:Layout() end   -- E2007: missing argument `count`
```

Lua finds `Derived.Layout` first at run time. Workaround (UI/ClassBars):
`local Totems: any = setmetatable({}, { __index = CB })`.

Related *pattern* (ui-primitives, ui-units): frames with fields of their own
are typed with an interface extending the widget type plus a cast at creation
(`CreateFrame("Frame", …) :: Panel`); a mixin table as `local Panel = {} :: Panel`;
a `setmetatable` class with `(Border :: any).__index = Border` and
`setmetatable({…}, Border :: any) :: Border`. UnitFrame's mixin `UF` is `any`
because its methods pass `self` (the frame) to typed functions and the checker
types `self` as the mixin table.

From: ui-units (U3), ui-primitives.

### C19. `export function x` silently replaces a local `x`; indexing a function value isn't an error

```wowlua
local items = {}
export function items(parent: Frame): Frame
    local f = CreateFrame("Frame", nil, parent)
    items[f] = true          -- indexes the function itself: no diagnostic
    return f
end
local function g(): number return 1 end
g[1] = true                  -- no diagnostic either
```

No redeclaration warning for the export over the local, and no error for an
index assignment on a function type; at run time `items[f] = true` errors.
Found in UI/Social, where weak sets of live pages had the export names
`contacts` and `raidGroups`. Workaround: renamed to `contactPages`/`raidPages`.

From: ui-social.

### C20. A cast can't drop a `Secret<…>` member

`(pct :: number?)` on `number | colorRGBA | Secret<number | colorRGBA>` is
E2015 ("cannot assert"), while `cls :: string?` on `nil | string | Secret<string>`
is accepted (probably the `colorRGBA` member; the message could say which
member doesn't fit). units-group saw `string | Secret<string>` refused as
`string?` (E2015) and cast the realm to `string` instead (Readiness, Marks).

From: units-hud, units-group.

### C21. False "unused local" for a forward-declared local defined by `function name`

```wowlua
local tipBase
local function tipFor(g: number): number return tipBase(g) end
function tipBase(g: number): number return g + 1 end  -- W1003: unused local `tipBase`
```

The generated Lua is right. Workaround: `tipBase = function(...) ... end`
(Units/WorldMap).

From: units-maps (U5).

### C22. *Pattern:* a multi-return function can't `return nil` alone

A function typed `(number?, number, number, number)` must write every value.
This forced `EditMode.Rect` to return four nils (see D-UI-settings) and
`TabMarker:Place` to be typed `(number?, any, any, any)`.

From: ui-settings, ui-primitives.

### C23. W4306 for a library package without a license

A library member without a license file or header gets W4306 ("embedded
library without a recognizable license file or header") in the consumer's
check. `"license": "MIT"` in the library's `package` silences it
(libs/ForeverLFG).

From: foreverlfg.

### C24. Hard-to-read diagnostics

- Through `pcall`, a missing argument is reported as an unassignable function
  type (`pcall(JoinChannelByName, "LookingForGroup")` → E2001 on
  `(channelName: string, …, hasVoice: boolean) -> …`), not as the missing
  argument (diag-social).
- E2001 for a missing required field doesn't name the field (units-trade, C15).
- E2015 doesn't say which union member can't be asserted (units-hud, C20).

### WoW API declarations

Wrong, missing or too strict declarations, by API. The calls in SuuUI pass
what they passed before; each cast is a workaround, not a fix. Most were not
verified against the client's documentation in this session.

### C25. `C_AuctionHouse` money is typed `string` (`WOWMONEY`)

The game returns and takes copper numbers.

```wowlua
local _, _, _, _, _, _, _, _, _, buyout = C_AuctionHouse.GetReplicateItemInfo(0)
if buyout > 0 then end                       -- E2001: cannot compare `string` with `0`
```

Affected: `GetReplicateItemInfo` returns 8–11, `GetCancelCost`; the prices of
`PostCommodity`, `PostItem`, `ConfirmPostItem` (`CalculateCommodityDeposit`
reads `number?`, so it's per field). Workarounds: `pcall(AH.GetReplicateItemInfo :: any, k)`
(Units/AuctionHouse `M:ReadScan`), `(C_AuctionHouse :: any).PostItem…`
(Diagnostics/AhPostProbe).

From: units-trade, diag-world.

### C26. `GameTooltip:SetInboxItem` / `SetSendMailItem` take too few parameters

Declared `SetInboxItem(index: any?)` and `SetSendMailItem()` in
`crates/wowlua-api/data/shared.d.wowlua` (hand-written); the game calls
`SetInboxItem(mailIndex, attachmentIndex)` and `SetSendMailItem(attachmentIndex)`
(E2006). Check against Blizzard_MailFrame. Workaround (Units/Mail):
`local tip: any = GameTooltip`.

From: units-bags.

### C27. `Minimap:GetZoom()` / `GetZoomLevels()` have no returns

`local z: number = Minimap:GetZoom()` → "`nil` is not assignable to `number`".
Workaround (Units/Minimap `M:Zoom`, `M:PlaceMinimap`): `Minimap:GetZoom() :: any`.

From: units-windows.

### C28. `C_NamePlate.SetNamePlateSize(width, height)` takes `string`s

The game takes numbers (`SetNamePlateSize(140, 30)` → E2001). Workaround
(Units/Nameplates `M:ApplyGameSettings`): `pcall(C_NamePlate.SetNamePlateSize :: any, …)`.

From: units-windows.

### C29. `issecrettable` takes a `function`

Declared `(table: function) -> boolean`, so
`issecrettable(events)` on `DeathRecapEventInfo[]` is E2001. Workaround
(Units/DeathRecap): `issecrettable(events :: any)`.

From: units-notices.

### C30. Quest functions lack their index parameter

`SelectActiveQuest(i)`, `SelectAvailableQuest(i)` and
`GetQuestLogCompletionText(logIndex)` are declared without parameters (E2006);
Blizzard's quest frame code passes the index. Workaround:
`(SelectActiveQuest :: any)(i)` (Units/NpcDialogue),
`(GetQuestLogCompletionText :: any)(logIndex)` (Units/ObjectiveTracker).
Unverified which form Forever takes.

From: units-notices.

### C31. `JoinChannelByName`'s `hasVoice` is required

`password` and `frameID` are optional but `hasVoice` isn't, so the
one-argument call SuuUI (and as far as known the game's chat code) makes is
E2007. If the client docs give `hasVoice` a default, it should be optional.
Workaround (Diagnostics/LfgProbe `join`, `timerJoin`):
`pcall(JoinChannelByName :: any, "LookingForGroup")`. See also C24.

From: diag-social.

### C32. Other parameters declared required or with the wrong type

- `SetTrainerServiceTypeFilter(type: string, enable: boolean, exclusive: boolean)`:
  SuuUI passes `1`/`0` and no `exclusive`; `pcall(SetTrainerServiceTypeFilter :: any, k, 1)`
  (Units/Professions `M:RecordTrainer`). (units-trade)
- `SendChatMessage`'s target is `string?`, but a channel number has always been
  passed: `id :: any` (Units/GroupFinder `M:PostAd`). (units-social)
- `IsSpellKnown` requires `isPet`: `IsSpellKnown(id, false)` (UI/CastBar).
  (ui-units)
- `C_Container.SortBank` requires `bankType`: `pcall(C_Container.SortBank :: any)`
  keeps the no-argument fallback (Units/Bags). (units-bags)
- `NumericRuleFormatBreakpoint`: a literal union of four shapes didn't match the
  declaration; the aura formatter's breakpoints are annotated with the type
  (UI/Auras). (ui-units)

### C33. Wrong or missing fields

- `FetchNextPurchasableBankTabData(...).tabCost` is `string?`; the code and the
  popup's money frame treat it as copper. The `CONFIRM_BUY_BANK_TAB` cost
  function returns `any` (Units/Notifications). (units-notices)
- `TraitCondInfo` has no `tooltipText` (E2003); the condition is read untyped
  (UI/TalentTree `traitTooltip`). Either the declaration lacks it or the
  client's struct does, and the "spend N more points" line never shows: check
  `C_Traits.GetConditionInfo` in the client docs or with a probe. (ui-settings)

### C34. Whole tables typed as possibly secret

`C_Spell.GetSpellCooldown` and `C_ActionBar.GetActionCooldown` return
`SpellCooldownInfo | Secret<SpellCooldownInfo>`; `C_UnitAuras.GetAuraDataByIndex`
and `GetPlayerAuraBySpellID` return `AuraData | Secret<AuraData>`. SuuUI's
probes found these tables plain with secret fields, so field access is E2040
on code that is right for the client. Workarounds: `:: SpellCooldownInfo?`
(Units/Threat `running`); a `cooldownFlags(info)` helper that answers
false/false for a secret table (UI/ActionButton, CooldownTracker); aura locals
typed `any` (Units/Tooltips, Convergences, Diagnostics/CampProbe); guards
added (UI/CastBar, Units/Readiness, Campsite). If the tables can't be secret,
the declarations should be `T?` with secret fields.

From: units-hud, ui-hud, units-windows, units-talents, ui-units, units-group,
units-maps, diag-world.

### C35. `ChatFrame1` is declared `Frame`, without the chat frame mixin

Lacks `ApplySystemAnchor` and the other mixin methods (see C9).
Workaround (Units/Chat): `ChatFrame1 :: any`.

From: units-chat.

### C36. Namespace members missing

- `C_TradeSkillUI.GetRecipeNumItemsProduced`, `GetRecipeTools`
  (Diagnostics/ProfessionProbe). (diag-world)
- `C_BattleNet.SetFriendNote`, `RemoveFriend`, `SendFriendInvite`, read through
  `local bn: any = C_BattleNet` (Units/Social). (units-social)

### C37. Undeclared globals (read through `_G`)

| Global | Where | From |
|---|---|---|
| `InviteUnit` (fallback behind `C_PartyInfo.InviteUnit`) | Units/Chat, RaidPlanner, Notifications, Social, GroupFinder, Guild | units-chat, units-group, units-notices, units-social |
| `ChatFrame_SendBNetTell` (fallback behind `ChatFrameUtil.SendBNetTell`) | Units/Notifications, Social | units-notices, units-social |
| `BNSetAFK`, `BNSetDND`, `ConvertToRaid` | Units/Social | units-social |
| `LE_PARTY_CATEGORY_INSTANCE` | Units/Marks, Convergences | units-group, units-talents |
| `ItemLocation` (FrameXML's `ItemLocationMixin` global) | Units/AuctionHouse `sellable()` | units-trade |
| `AbandonSkill` (behind `C_SkillInfo.AbandonSkill`) | Units/Professions | (source) |
| `NamePlateDriverFrame` | Diagnostics/PlateProbe | diag-combat |
| `GetNumTalentGroups`, `GetTalentResetCost`, `GetTalentWipeCost` | Diagnostics/TalentProbe, TalentBuildProbe | diag-combat |
| `GetLootMethod`, `GetQuestGreenRange` | Diagnostics/LootProbe, QuestProbe | diag-world |
| `DBM`, `BigWigsLoader` (third-party, load after SuuUI) | Units/Timeline | units-hud |

`TOTEM_MULTI_CAST_SUMMON_SPELLS` is cast to `any` (UI/ClassBars, ui-units).

### Checked and fine

- Methods and exports named `export` / `import` work (`export function export()`,
  `{ onClick = import }`), build output included (ui-settings).
- Check time with the big data literals: a scratch project checks in ~0.15 s
  empty and ~0.23 s with all of `src/Data` (34k lines); typed and untyped
  literals take the same time. The release build's note on QuestStarts
  (`dedupe-strings`, `cache-globals`, `inline` left out for the file to stay
  under a Lua 5.1 limit) is informational (data).

### C38. `wowlua publish --dry-run` waited without output

Run in this worktree without a terminal (a background job), it packaged both
zips into `dist/packages/` and then sat at 0% CPU for over ten minutes with no
further output until killed. Not investigated: it may wait for the OS
credential store (macOS keychain prompt) while looking up the publish
tokens. `wowlua package` packages without it.

### C39. The test profile's `runtime-checks = "all"` and half-built frames

`wowlua test` uses runtime-checks "all", which checks every `::` assertion and
every annotated parameter at run time. SuuUI builds frames step by step
(`local f = CreateFrame(…) :: Panel`, then the methods are mixed in), so the
assertion fails before the frame is complete, and so does any function taking
a `Panel` while it is half built. Mixin tables and frame constructors were
rewritten as `local f: Panel = CreateFrame(…) :: any` (no assertion, same
static type), and `wowlua.json` sets `profiles.test.runtime-checks` to
"exports", like a dev build. Exported functions' parameters are still checked
in tests, which is what a dev build in the game checks too. Worth deciding
whether wowlua should offer a cast that is never checked at run time, or skip
`::` checks of interface types against tables still being built.

## 3. Standard library gaps

### S1. wowlua:events: SuuUI's bus shape

SuuUI keeps `Core/Events` on top of wowlua:events, which does the registering
and dispatching. The layer adds what wowlua:events lacks:

- the handler gets the event or message name first (`fn(name, ...)`);
- an owner is required, and removal is by name and owner (`off(name, owner)`),
  not only by subscription or owner;
- unit lists longer than two (`RegisterUnitEvent` takes at most two, so one
  registration per pair);
- errors reported per owner through Fault (by the owner's name);
- a listener removed during a dispatch is skipped from then on (wowlua:events
  dispatches from a snapshot and would still call it);
- allocation-free dispatch: `fault.call` allocates nothing on success, but
  wowlua:events allocates per dispatch and handler (S2), so SuuUI's every event
  callback now pays both.

The stdlib would need: name-first handlers (or an option), `off(name, owner)`,
`onUnit` with any number of units, an error context per owner, cancelled
handlers skipped mid-dispatch, and a dispatch that doesn't allocate.

Source: `src/Core/Events.wowlua`, `src/Core/Fault.wowlua`.

<a id="s2"></a>

### S2. Per-call allocations in wowlua:events, hooks and timer

In the 0.9.1 stdlib, `events.wowlua` dispatches from `{ unpack(list) }` and
calls each handler through `callIn({ component = context }, h.fn, ...)`;
`errors.wowlua`'s `callIn` packs `{ ... }` and builds a closure for `xpcall` on
every call. wowlua:hooks and wowlua:timer run every callback through `callIn`.

Where SuuUI kept raw code because of it:

- UI/Draw's `paint`: `hooksecurefunc(region, "SetVertexColor" | "SetColorTexture"
  | "SetTextColor" | "SetStatusBarColor" | …, letGo)` on every painted region;
  those setters run in hot paths (bars, unit frames) for the region's lifetime
  (ui-primitives).
- Units/Nameplates: `SetAlpha` on every hidden Blizzard nameplate UnitFrame,
  which fires on every fade (units-windows; commented in the code).

Measured in the VM (2000 dispatches each, collector stopped; bytes per event,
unported → ported; both include the mock's own allocations, so the difference
is what counts): UNIT_HEALTH 1984 → 3328, UNIT_POWER_UPDATE 21832 → 23848,
UNIT_AURA 23408 → 26496, SPELL_UPDATE_COOLDOWN 196592 → 199784,
ACTIONBAR_UPDATE_COOLDOWN 423232 → 424600: about 1.3 to 3 KB more garbage per
event. The VM's memory accounting is not the game's; `/suu perf` in game shows
the real figure.

Where it is now paid: every SuuUI event (Core/Events), and the `SetPoint` hooks
on tab buttons and windows in UI/WindowSkin, which run often while Blizzard
lays out (ui-windows: "small but new garbage").

The stdlib could offer a lean form for hooks that can't fail
(`hook(t, name, fn, { isolate = false })`), isolation that only allocates when
an error happens, or passing the arguments to `xpcall` directly where the
client's `xpcall` takes them (not probed).

From: ui-primitives, units-windows, ui-windows; stdlib source checked.

### S3. wowlua:events: re-pointing a unit subscription

Each nameplate keeps its own event frame with `RegisterUnitEvent(e, f.unit)`,
re-registered when the pooled plate gets another unit. Neither `M:OnUnitEvent`
(the module's lifetime) nor `wowlua:events` `onUnit` (a fixed unit list,
unsubscribed by `off`) can re-point a subscription. Kept the frame
(Units/Nameplates).

From: units-windows.

### S4. wowlua:errors: per-owner attribution, no context for `onError`

Errors in the stdlib's own callbacks that SuuUI hands it (timers, hooks,
deferred combat work) go to the game's error handler as wowlua:errors reports
them. `errors.onError(fn)` passes only the message (`fn(msg)`), and the
`component` context is appended only in debug builds, so Fault records them all
under "SuuUI" instead of the module that owns the callback. The stdlib would
need the context (owner/source) passed to `onError`, or an owner per `hook` /
`after` / `every` call.

Source: `src/Core/Fault.wowlua`; stdlib `errors.wowlua`.

### S5. wowlua:errors: a quiet guarded call

SuuUI's `call(fn, ...)`: nil when `fn` isn't a function, `pcall`'s results on
success, nil on an error, never reported (for game APIs that may be missing on
Forever or error on bad IDs). `call`/`callIn` report and return `ok` first.
Kept (Units/Collections, DressingRoom, CharacterWindow, Inspect, Durability,
Guild, Social, AuctionHouse), typed to return `any`s.

From: units-character, units-social, units-trade.

### S6. wowlua:combat: keyed work with replacement

Core/Combat keys the combat queue: the first request for a key takes the place
in the queue, the latest one's function runs (moving a bar twice in a fight
moves it once, to the last place). wowlua:combat's queue does the waiting;
the keys are SuuUI's. The stdlib would need `defer(key, fn)` with replacement.

Source: `src/Core/Combat.wowlua`.

### S7. wowlua:combat: `inCombat` counting `UnitAffectingCombat`

Units/Threat and DamageMeter define `inCombat()` as `InCombatLockdown() or
UI.Flag(UnitAffectingCombat("player"))` (in combat before lockdown starts).
`wowlua:combat` `inCombat()` is only `InCombatLockdown()`. Kept. An
`inCombat({ affecting = true })` or `affectingCombat()` would cover it.

From: units-hud.

### S8. wowlua:saved: SuuUI's profile model

`Core/DB` binds `SuuUIDB` and `SuuUIProbe` through wowlua:saved (no defaults,
no stripping). The profiles are SuuUI's own: a per-character profile map in the
same SavedVariable ("Name - Realm" unless switched), sparse values (only what
differs from the defaults, so a changed default reaches every profile),
vetoes, watchers, and per-module migrations stored with the profile.
wowlua:saved's profile model keeps a profile per character in a second
SavedVariable and whole values per profile, and SuuUIDB's shape must stay.

Source: `src/Core/DB.wowlua`, `src/Core/Settings.wowlua`.

### S9. wowlua:slash: SuuUI's command registry

`/suu` is one `@slash("/suu", "/suuui")` handler over SuuUI's registry:
modules add and remove subcommands at run time (`registerCommand(cmd, help,
fn, owner, args)`, `unregisterCommands(owner)`), "/suu help" lists them in
registration order, and `args` (a list or a function) feeds the chat's
command palette. The stdlib's `router(defs)` takes a fixed table of commands.
It would need owners, unregistering, dynamic registration and argument
palettes.

Source: `src/Core/Init.wowlua`.

### S10. wowlua:log: prefix format and a run-time debug toggle

SuuUI prints with its own prefix (`|cff9fd3c7SuuUI|r `) and debug lines as
`|cffa39b8b[debug]|r`, switched at run time by the `core.debug` setting
(`/suu set core.debug on`). wowlua:log writes `|cff33ff99<Addon>|r
|cff<colour>[level]|r`, sends only warn and above to chat by default, and
removes calls below the profile's log level at compile time, so a run-time
toggle can't bring debug lines back in a release build. The stdlib would need
a configurable prefix/colour and a level that can be lowered at run time.

Source: `src/Core/Init.wowlua`, `src/Core/Settings.wowlua`; stdlib `log.wowlua`.

### S11. wowlua:table: `copy` keeps shared tables shared; `keys` sorts one type

SuuUI's deep copy copies a table that appears twice as two tables and keeps
keys as they are; `wowlua:table`'s `copy` keeps shared and cyclic references
shared and deep-copies keys. Units/CooldownManager, Defensives, BuffIndicators
keep their own `copy` (lists can share tables, and the copy goes into saved
setups). A `copy(t, { shared = false })` would fit. (`equal` is used.) Core/Util
also keeps its own sorted `keys`: wowlua:table's sorts only keys of one type,
and plugin data may mix them.

From: units-cooldowns; `src/Core/Util.wowlua`.

### S12. wowlua:format: SuuUI's money, number and time texts

- Money: SuuUI writes "1g 20s 5c" with digits in ink and each unit in its
  coin colour (or all in ember-text when you can't afford it), plus a plain
  copy for measuring (UI/Spellbook `coinText`, Units/Trainer and AuctionHouse
  `coins`; AuctionHouse shows `0s` between gold and copper). `format.money`
  gives coin icons or the client's words. Needs a colour per part and a plain
  copy.
- Thousands: AuctionHouse always writes "48,183" (floored); `format.number`
  uses the locale's separator. Needs `number(n, { separator = "," })`.
- Short numbers and times: UnitFrame's `shortNumber` ("8.5k", "1.2m"),
  WeaponEnchants' `digits` ("1:30", "5m") and `longTime` ("1 h 5 min") are
  lowercase/short; `format.abbreviate` gives "8.5K" and `short`/`duration` the
  client's localized words.

wowlua:color's `colorize` was adopted for Money and Legacy (same text; see
D-UI-world for the one difference).

From: ui-settings, units-trade, ui-units, ui-world.

### S13. wowlua:pool: index-stable reuse

UI/RaidPlanner's `pool(list, i, make)` returns the i-th frame (made when
missing) and `hideFrom(list, n + 1)` hides the rest, so row i is always the
same frame. `wowlua:pool` hands out any free frame. Needs `pool:at(i)` and
`pool:trim(n)`.

From: ui-world.

### S14. wowlua:aura: `container`

UI/Auras keeps its own container. It needs `lazy` groups (added to the engine
only once their count is above 0, ~10 MB saved in a raid), per-group
`index`/`gap` (`SetGroupPlace`), `exclude` spell IDs, `SetGroupFilter`,
`SetGroupSize` (resizing existing buttons), the edit-mode `ShowPreview`, nil
when the client has no containers (the stdlib raises), the initializer's
button list, Fault reports, `extend.add("auracontainer", …)`, and the re-scan
through Core/Events with the container as owner.

From: ui-units.

### S15. wowlua:tooltip: knowing whether the post-call is in use

UI/Tooltip `spellTooltip` keeps its own `TooltipDataProcessor` post-call. It
needs to know whether the data system's post-call exists (to add its lines
directly otherwise), doesn't want the `OnTooltipSetSpell` script fallback, and
decides `pending.added` from forbidden tooltips the stdlib skips. Needs an
`available()` (or a return value from `hook`) and an option without the
script fallback.

From: ui-windows.

### S16. wowlua:secure: snippet-driven drivers, visibility with unregistering

- UI/ActionBar registers bar 1's paging with `RegisterStateDriver(header,
  "page", cond)` and an `_onstate-page` snippet. `secure.state` would defer
  the registration to the end of combat and add a Lua `OnAttributeChanged`
  callback, neither wanted. Needs `secure.driver(frame, name, cond)` that only
  registers (now when possible). (ui-hud)
- The pet bar unregisters its state driver and shows itself in keybind mode
  inside one `combat.run` job; `secure.visibility` only registers. (ui-units)

### S17. wowlua:secret: `flag` semantics

`secret.flag(b)` returns `b == true`; SuuUI's `flag` (UI/Text) turns any truthy
value into `true` (callers pass non-boolean game results). Kept SuuUI's body.

From: ui-primitives.

### S18. wowlua:secret: a "present and readable" predicate

Almost every Units file has `plain(v)`: not nil and not secret, used as a
guard (`if plain(x) and x > 0`), as `plain(v) and v or fallback`, and before a
call. `secret.known(v, fallback)` covers only the last form for non-boolean
values; `isSecret` leaves the nil. The port keeps `plain`, typed as a
non-generic predicate (C12). A `secret.readable(v)` / `secret.usable(v)` that
narrows `T | Secret<T> | nil` to `T` would replace it.

From: units-talents, units-maps, units-bags, units-character, units-social,
units-chat, units-windows.

### S19. wowlua:timer: `every` can't stop and restart

Units/Threat and DamageMeter drive ticks from a hidden frame's OnUpdate,
shown/hidden as the switch, with `driver:IsShown()` read as state. `every`
would need stop, restart, `isRunning()`, and the first tick one interval after
starting. Kept.

From: units-hud.

### S20. wowlua:timer: coalescing a set of kinds on the next frame

UI/ActionBar coalesces the cooldown / usable / active passes per kind into one
pass on the next frame (a cast fires several of each event in one frame).
`nextFrame(fn)` runs every call, and `@nextFrame` coalesces one function with
the last call's arguments, not a set of kinds flushed together. Kept SuuUI's
flusher frame.

From: ui-hud.

### S21. wowlua:callbacks: removal by function

ForeverLFG's public `LFG.On` returns the function and `LFG.Off(event, fn)`
removes by handler, with errors through `geterrorhandler()` per listener.
`wowlua:callbacks` removes by subscription or owner. Needs `off(name, fn)`.
SuuUI keeps the library's small bus.

From: foreverlfg.

### S22. wowlua:locale: several parser languages at once

ForeverLFG's Lang modules are parser keyword data per chat language: several
are active at once, chosen by preference, client, settings and each line's
script. `wowlua:locale` is for one client language's UI strings. They stay
data modules.

From: foreverlfg.

### S23. wowlua:unit: reading through a stand-in

UI/UnitFrame reads its unit through `self.api` (the game's `_G`, or
`unitStandIn` for previews), so `unit.health` / `healthPercent` can't replace
those calls.

From: ui-units.

## 4. Port decisions to review

### Found by the VM tests and fixed during integration

- An accessor in Core/Extend that called itself (a regex slip in the port),
  stack overflow on every module's first instance.
- `Tokens.wowlua` lost the eight `mark-*` colours: they had been added by hand
  to the old generated `Tokens.lua` (5d12037) and were not in
  `Design/tokens.json`. They are now an `EXTRA_COLORS` list in
  `tools/gen_tokens.py`; every token is identical to before. Worth moving
  them into the design system's tokens.
- `placeDragon` typed its art as optional, but callers pass `false` (no art);
  a dev build's runtime check would have errored on every unit frame.
- Constructor casts (C39).


### Cross-cutting

<a id="d-x1"></a>

- **D-X1. Hook and timer errors are now isolated.** `hooksecurefunc` →
  `hook`, `HookScript` on Blizzard frames → `hookScript`, `C_Timer.After` /
  `NewTimer` → `after`, `NewTicker` → `every`, in nearly every file. An error
  in the callback is reported through wowlua:errors (`callIn`) and recorded by
  Fault as "SuuUI" (S4), instead of raising into the Blizzard code that ran the
  hook or going straight to the game's handler. They are still post-hooks
  over `hooksecurefunc` / `HookScript` / `C_Timer`, so taint is unchanged.
  Also: `after(0, fn)` makes a `C_Timer.NewTimer` instead of `C_Timer.After`
  (same timing), and a hook's return value is dropped (none returned one).
  `HookScript` on SuuUI's own frames stays a method call. (all areas)
- **D-X2. Load-on-demand hooks are written two ways.** With the W8102 form
  `hook(_G, name, fn, { addon = … })` in Diagnostics/CollectionsArtProbe,
  UI/GroupFinderListing (six functions of `Blizzard_GroupFinder_VanillaStyle`)
  and Units/Inspect (`InspectFrame_Show`); there the addon is already loaded
  and the hook goes on at once. Units/Windows uses `hook(_G, "Name", fn)`
  without the option (`ClassTrainerFrame_*`, `CollectionsJournal_UpdateSelectedTab`),
  because the option would change when they're installed. Worth making
  consistent. (diag-world, ui-social, units-character, units-windows)
- **D-X3. Secret guards added where the checker saw a possible secret**; the
  old code would have raised on a secret there, so nothing that worked changes
  (UnitClass tokens through `secret.known(class, "")`, cooldown and aura
  tables, `UnitGUID`, `UnitSex`, roles, realm). Your own name, class and GUID
  are cast instead (never secret on Forever). (ui-units, ui-hud, units-*)
- **D-X4. `plain(v)` test order is inconsistent.** units-bags kept
  `v ~= nil and not isSecret(v)` (compares before testing secrecy) in every
  file it touched; Units/Chat, Tooltips, Addons, FlightMap, WorldMap swapped it
  to secrecy first. If comparing a secret with nil errors in the client, the
  first order is wrong: worth a probe. (units-bags, units-windows, units-maps)
- **D-X5. `SuuUIProbe = SuuUIProbe or {}` is gone**: probes write
  `DB.probe.<same key>` and read `DB.db` for `SuuUIDB`, same keys and shape;
  nothing touches DB at load. Exception: Units/Timeline still writes the global
  `SuuUIProbe` (Units use only the public API; same table). (diag-*, ui-settings,
  units-hud)
- **D-X6. `ns.X` existence guards dropped** (`ns.EditMode and …`,
  `ns.ApiDocs and ns.ApiDocs.Dump`, `UI.CloseButton and …`, ForeverLFG's
  `LFG.Lang and …`): the modules are static imports now. (many)
- **D-X7. Event owners that were file tables are now strings or module-local
  tables** (ClassData, SpellData: `"ClassData"`, `"SpellData"`; Plate, Meter,
  Timeline probes: a local `OWNER = {}`, so Fault still names it
  `tostring(table)`). Other owner strings are unchanged. (diag-core, diag-combat)
- **D-X8. Tables of functions became module exports** (KeybindMode, Probe,
  TokenSheet, Gallery, the probes, `ns.WindowRow`, `ns.Interrupt`); state that
  lived on them is now module-local. `import * as x` gives the old shape.
- **D-X9. Pre-existing warnings were left** (unused locals, shadows) in many
  files; listed in each area's notes.

### Core

<a id="d-core1"></a>

- **D-Core1. Profile strings use wowlua:serialize.** `encode` writes
  `!SUU:2!…` (compact, compressed, checksummed, printable); `decode` reads
  those and the old `SUU1:` strings (read-only parser, never runs code). A
  string exported by this build can't be imported by an older SuuUI release.
  The SUU1 pieces (`base64`, `fletcher16`) stay for other share texts (talent
  builds). (`src/Core/Serialize.wowlua`, ui-settings)

<a id="d-core2"></a>

- **D-Core2. The `test` profile sets `"runtime-checks": "exports"`**
  (`wowlua.json`). The test default `"all"` also checks every `::` assertion
  with a checkable type, and the casts of half-built frames
  (`CreateFrame(…) :: Panel`, see C18) would fail. `"exports"` checks exported
  functions, public methods, `@global` functions and event/slash/hook handlers.
- **D-Core3. `SuuUI.Raw.ns` is now the addon table**, which holds the wowlua
  runtime (`__wowlua`); the modules are no longer fields of it. `Raw.UI` is
  `rawUI`, built in API.wowlua with every component under its old name (182,
  generated from the symbol map); `Raw.Mixins` is Core/Init's `mixins`. Draw's
  leftover `ui` export (the old `ns.UI`, an empty table) is unused and can go.
  Docs/API.md and Docs/PluginGuide.md describe the new `Raw.ns`.
  (`src/Core/API.wowlua`)
- **D-Core4. The `/suu` command's `SlashCmdList` key is now `WOWLUA_SUUUI_1`**
  (was `SUUUI`); `/suu` and `/suuui` work as before. Anything that called
  `SlashCmdList.SUUUI` directly breaks. (`src/Core/Init.wowlua`)
- **D-Core5. SavedVariables through wowlua:saved** add a `__version` key to
  `SuuUIDB` and `SuuUIProbe`; neither defaults nor stripping are used, so the
  rest is written back as SuuUI left it. Touching `DB.db`/`DB.probe` before
  they load raises an error. (`src/Core/DB.wowlua`)
- **D-Core6. Core/Events now dispatches through wowlua:events**, so every
  SuuUI listener pays the stdlib's per-handler allocations (S2) on top of
  `fault.call`. An event the client doesn't know never fires (wowlua:events
  checks `C_EventUtils.IsEventValid`), where `pcall(RegisterEvent)` used to be
  the guard. (`src/Core/Events.wowlua`, ui-hud)
- **D-Core7. `SuuUI.LFG`** is `lfg :: ForeverLFG` from the `foreverlfg`
  package (C6). (foreverlfg)

### UI

- **ActionBar's event dispatcher is on Core/Events** (`onGame`, owner
  "Action bars") instead of its own frame with `pcall(RegisterEvent)`: errors
  reported as "Action bars", handlers still get the payload without the event
  name. The range poll has its own `poller` frame. Insecure code; nothing
  secure changed. Check in game. (ui-hud)
- **Tooltip lines' wrap flag** (KeybindMode, ActionButton): `AddLine(text,
  UI.RGBA(token))` passed alpha as `wrap`, so every line wrapped. The port
  passes `r, g, b, true`: the same look, probably not intended. (ui-hud)
- **Secret tests before truthiness** in a few ui-hud places: a secret now
  counts as unknown where it used to raise (readTalents ran in a pcall, so it
  was "no talents read"). `C_Spell.GetSpellTexture`'s extra returns still land
  in `SetTexture`'s further arguments, as before. (ui-hud)
- **`UI.actionTextSize`** is a module local in ActionButton (was visible on
  the raw UI table). (ui-hud)
- **KeybindMode** is no longer a table (`enter`, `exit`, `toggle`,
  `isActive`); `isActive()` still returns nil before the first enter. (ui-hud)
- <a id="d-ui-settings"></a>**`EditMode.Rect` (public `SuuUI.EditMode.Rect`)**
  returns `nil, nil, nil, nil` for a frame with no rectangle instead of a
  single nil; only `select("#", Rect(f))` sees it. (ui-settings)
- **Edit mode's `layout.gridSize` veto** returns `nil, nil` explicitly on
  accept; "Show the welcome again" calls `SuuUI.ShowWelcome()`; Theme options
  use `themes.all()`; LayoutCheck writes `DB.probe.layoutCheck`. (ui-settings)
- **Window `export`** casts `profiles.export()` to `settings.Exported`
  (a nil would have errored before too). (ui-settings)
- **Bug left: Sections `moduleRow`** walks `{ m.description, … }` with
  `ipairs`, so a module without a description shows an empty row (no "Built
  in", no state, no error). Fix: drop nils first. (ui-settings)
- **Check: TalentTree `traitTooltip`** (C33). (ui-settings)
- **Hooks on Blizzard's group finder, guild control and windows** go through
  wowlua:hooks; the SetPoint hooks on tab buttons and windows now allocate per
  call (S2). WindowSkin's per-window `PLAYER_REGEN_ENABLED` frames are
  `events.onGame` with owners `"UI.SkinWindow"` / `"UI.WindowRow"`. (ui-social,
  ui-windows)
- **Taint review: GuildControl writes fields on the game's frames**
  (`ui.suuOwn`, `b.suuWhy`, `b.suuIconButton`, `new.suuPlus`, `o.suuFill`),
  unchanged from the Lua, while GroupFinderListing avoids that. (ui-social)
- **`ns.WindowRow`** is exports `add`, `layout`, `queue` plus the state table
  `windowRow`; `UI.WINDOW_HEAD_H` is `export const`. Tooltip `addExtra` takes
  the lines as a parameter; `skinTooltip` returns `nil` explicitly;
  `Alert:SetTone` reads `TONES[tone] or assert(TONES.danger)`. (ui-windows)
- <a id="d-ui-world"></a>**`LEGACY_CARD_H` / `LEGACY_TRACK_H`** were mutable
  `ns.UI` fields a theme change rewrote. They're exported as the heights at
  load; `/Core/API` copies them into `SuuUI.UI`, and the theme handler updates
  those public copies; Legacy uses a local `trackH`. Units/Legacy reads
  `SuuUI.UI`, so nothing should change. This adds a run-time cycle API →
  Legacy → API. (ui-world)
- **`colorize` errors on a malformed hex** (Money, Legacy), where the old code
  built a broken escape; every token hex is 6 lowercase digits today. (ui-world)
- **Inventory's secure bag slots keep raw `HookScript`** (OnEnter/OnLeave) on
  Blizzard's bag buttons; secure handling unchanged. (ui-world)
- **Draw keeps `hooksecurefunc`** on the colour setters (S2). `Draw.shadow`
  with an inset-only token errors on a nil index, as before. (ui-primitives)
- **Exported builder types** (`panel.Panel`, `controls.SuuButton`, … plus an
  `…Options` type per builder); `WindowFrame`'s `DrawTabs`/`SetTab` are
  declared although only tabbed windows have them. (ui-primitives)
- **`ns.Mixins.*` → `mixins.*`** (UnitFrame, AuraContainer, CastBar,
  WindowChrome, MicroMenu, Notification); `ns.Interrupt` → `interrupt` plus
  `find`, `ready`, `remaining` (the table no longer has `Find`/`Ready`/
  `Remaining`; only CastBar used them). (ui-units, ui-windows)
- **Seen, not fixed:** UI/RaidPlanner passes a `{ [string]: any }` as
  `panel.panel`'s parent (E2001 at the time; `parent` is `Frame`). (ui-primitives)

### Units

- **Bags: check in game** Escape with the bags open in combat and using an
  item from the bags in combat (`/suu probe taint`): the bag hooks
  (`ToggleAllBags`, `OpenAllBags`, `CloseBag`, …) now isolate errors, so an
  error can no longer break the caller's chain. Secure and taint paths are
  unchanged (slot buttons, the buy cell, `InCombatLockdown` guards, hidden
  parents, `TooltipDataProcessor`). (units-bags)
- **Bug left: Bags `SortTarget`**: `special` mixes bag keys and array slots,
  so profession bags in bags 1–4 collide with array indexes and two special
  bags can leave a hole `ipairs` skips. The reagent bag alone works.
  (units-bags)
- **GameMenu keeps `C_Timer` and raw `hooksecurefunc`/`HookScript`**
  (taint-sensitive Escape menu, kept exactly). Probably fine to switch; check
  `/suu probe gamemenu` in game first. (units-social)
- **Notifications keeps raw hooks** on `StaticPopup_Show`, the popups and
  their buttons, and the request windows (taint-sensitive popup hosting). Only
  its timers moved to `timer.after`. (units-notices)
- **MicroMenu `legacyToSpend`**: `… and info[1].quantity` became `… or nil`.
  A failed `pcall` used to return `false` and `legacy > 0` errored in
  `UpdateAlerts`; now it's 0. The only behaviour change on that path; please
  review. (units-social)
- **Nameplates keep `hooksecurefunc` on `SetAlpha`** (S2) and per-plate event
  frames (S3). Check in game. (units-windows)
- **Minimap `M:Overlay`** uses `defer(passThrough)` from wowlua:combat instead
  of a one-shot `PLAYER_REGEN_ENABLED` frame; its order relative to SuuUI's
  other `PLAYER_REGEN_ENABLED` handlers may differ. `GetMinimapShape` is
  written as `_G.GetMinimapShape`. (units-windows)
- **Tooltips read auras as `any`** (C34): a secret aura table would raise in
  `AddSource` (inside `M:Guard`); not changed. (units-windows)
- **Maps call the global `issecretvalue` directly** (C4); on a client without
  it the call would error (the old fallback returned false). (units-maps)
- **Bug left: Campsite `M:Alert`**: every branch returns, so the `BRIEF` timer
  after it never runs (W1005). (units-maps)
- **Bug left: Collections `LayoutCells` / `LayoutTiles` / `LayoutShelf`**
  compare `w <= 0` before `isSecret(w)`. (units-character)
- **Inspect**: `M:Asked(unit)` lost its unused parameter; the
  `INSPECT_READY` handler skips the redraw for a secret `UnitGUID` and calls
  `UnitGUID` before the window check. Collections asserts `slotDef(…)`
  (always found). (units-character)
- **ChatCommands still replaces `ChatEdit_CustomTabPressed`** (only its return
  value can take Tab); `CURRENT_CHAT_FRAME_ID` is written the same way.
  (units-chat)
- **ActionBars' `hook(bar, "Show", silence)`** on Blizzard's main bar now
  catches errors in `silence`. Timeline's DBM `DBT.CreateBar` replacement stays
  a replacement. (units-hud)
- **NpcDialogue's `M:Hook()`** replaces the module object's public
  `Hook(kind, method, fn)` on this module, as in Lua; renaming would be
  cleaner. (units-notices)
- **CooldownManager**: `spellLookup` returns nil before the name lookup for a
  non-number query; `specPreset(nil)` still falls back to the first preset.
  (units-cooldowns)
- **Bug-ish left: AuctionHouse `M:OnEnable`** starts a 30 s ticker each run
  and never cancels it (runs once per session: reloadToToggle). (units-trade)
- **Secure group frames, spellbook buttons and talent bindings are
  unchanged** (headers, `INIT`, state drivers, unit watches, `InCombatLockdown`
  guards). (units-group, units-talents)
- **Typing follow-up: Units/GroupFinder's `Entry`** (and Social's `Row`,
  `Member`) are `{ [string]: any }` aliases; they can become ForeverLFG's
  `Entry` / `Listing` types (`import type … from "foreverlfg"`). UI/GroupFinder*
  can use the same type-only imports. (units-social, foreverlfg)
- **Typing follow-up: API data getters** (`SuuUI.QuestStarts()`,
  `MapPlaces()`, `CollectionSources()`, …) still return `any` from
  `src/Core/API.wowlua`; the maps files also check with the typed `/Data/*`
  exports. Collections' `data()` may need a cast once typed.
  (units-maps, units-character)

### Diagnostics

- **Probe dispatch is a table** (`TOPIC_COMMANDS`, C8). Seven modules
  (MarkProbe, QuestProbe, BagProbe, BagSortProbe, TooltipProbe, TaxiProbe,
  TalentBuildProbe) weren't ported when it was written; their lines follow the
  old signatures, so check each matches the ported `command`. (diag-core)
- **Probe `check()`** ends with `return false, "?"` for an unknown item kind
  (was nil; no item reaches it). (diag-core)
- **MemoryProbe's "namespace" section** walks the addon table (without
  `__wowlua`) and each module's exports from `ns.__wowlua.modules`, a runtime
  internal present in dev and release 0.9.1; names are module IDs now.
  (diag-core)
- **Probes keep their own event frames** where they `pcall` RegisterEvent for
  events Forever may lack or unregister on their own timing; the bag probes are
  kept exactly. (diag-combat, diag-world)
- **TokenSheet** wraps by-name colour/style reads in `assert(...)` (an unknown
  name errored in `unpack(nil)` before). IconProbe and HoverTipProbe lost
  their existence checks. (diag-core)
- **WindowsProbe**: `show(C_AddOns.IsAddOnLoaded(a))` passed the second return
  as `depth`; now `show((…))`, same output. Without EventUtil the probe would
  now still hook load-on-demand windows later. (diag-social)
- **Bug left: MountFeetProbe / MountFrameProbe `place`** make their buttons on
  the first run only, so a second run's Up/Down/Next/… act on the first run's
  state. (diag-world)
- **PresetSpellIDs** matches `tools/gen_presets.lua`'s output byte for byte.
  (diag-core, data)

### Data

- **Every data module is `export local <name>: <Type> = { … }`** (C1); mixed
  tuple rows are `any[]`, enum-like strings stay `string`. (data)
- **Only your class's presets and trainer lists are built, as before**:
  `Presets/init` and `Trainer/init` pick the class at load and export
  `cooldownPresets`, `trainerSpells`, `trainerSpellIDs` (nil for a class
  without a file). The class files' exports differ from the symbol map's.
  A behaviour field the generator starts writing fails E2003 until added to
  `PresetEntry`. (data)
- **Generators** write `.wowlua` and run from the repository root;
  `gen_trainer.lua` reads the class file's `spells()` literal;
  `gen_recipe_sources.py` no longer overcounts by 2. `lua tools/gen_presets.lua`
  overwrites `src/Diagnostics/PresetSpellIDs.wowlua`. (data)
- **Verification**: QuestStarts, MapPlaces, FlightRoutes, FlightPaths,
  Presets, AuraCatalog, Talents, Defensives regenerated byte-identical;
  MapOverlays, InstanceLevels, Trainer from rebuilt inputs; RecipeSources
  differs only in the header; CollectionSources only had its header converted
  (inputs not available). (data)
- **D1 cost**: preset conditions lost the typo check (C16). (data)

### ForeverLFG

- **Now a library package** `libs/ForeverLFG` (`foreverlfg`, MIT); the root
  `wowlua.json` is a workspace root with a path dependency. Exported types:
  `ForeverLFG`, `Config`, `Listener`, `Part`, `Activity`, `ChatSource`,
  `Interest`, `ParseResult`, `LangModule`, `Entry`, `Filter`, `ToolSource`,
  `Listing`. (foreverlfg)
- **Part order**: parts used to register at load in TOC order; the computed
  load order puts Interest first, so `init` adds Chat, Interest, Tool in the
  old order (stopped in reverse). (foreverlfg)
- **Lang files are registered by `init`** (`lang.Register(code, def)`): a
  library module that only registers itself would be tree-shaken. (foreverlfg)
- **The soft use of SuuUI** (whether a post is your own) stays a guarded read
  of `_G.SuuUI`; the alternative was a setter SuuUI must remember to call.
  (foreverlfg)
- **Each part's event frame → `wowlua:events` `on(…, OWNER)` / `offAll`.**
  Interest's `pcall(RegisterEvent)` is gone; an unknown event never fires.
  Errors in callbacks go through wowlua:errors; Chat still pcalls `Read`.
  `os.time()` is read through `_G`; `unpack or table.unpack` is `unpack`.
  (foreverlfg)
- **Stale**: `tools/lfg_parse.lua` loads the old `.lua` files and no longer
  runs (the parity test is a starting point for a `wowlua test`);
  `Docs/ForeverLFG.md` and `Docs/wowlua-port-symbols.md` name the old
  location. (foreverlfg)

### Examples

No area notes cover `Examples/` (SuuUI_HelloPlugin, SuuUI_LevelBadge); they
are workspace members (`wowlua.json` `workspace.members`). Nothing recorded to
review.

### In game checks

<a id="in-game-checks"></a>

Taint-sensitive paths and open questions to try on Forever (with
`/suu probe taint`, never `/console taintLog`):

- Escape with the bags open in combat; using an item from the bags in combat
  (Units/Bags).
- The game menu: `/suu probe gamemenu` (Units/GameMenu, before switching it to
  the stdlib).
- The action bars' event dispatcher on Core/Events (UI/ActionBar).
- Nameplates (`SetAlpha` hook, per-plate unit events).
- Whether comparing a secret with nil errors (D-X4).
- `C_Traits.GetConditionInfo`'s `tooltipText` (C33); whether
  `GetSpellCooldown`'s table itself can be secret (C34); the quest functions'
  index argument (C30); `JoinChannelByName`'s `hasVoice` (C31).
