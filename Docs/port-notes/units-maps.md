# Port notes: units-maps

Files: `src/Units/FlightMap.wowlua`, `src/Units/WorldMap.wowlua`,
`src/Units/Campsite.wowlua` (wowlua 0.9.1, strict).

## 1. VM suspicions

(the VM wasn't run)

## 2. Compiler/tooling issues

### U1. `secret.isSecret` doesn't narrow inside SuuUI (it does in a fresh project)

```wowlua
import isSecret from "wowlua:secret"
local function aura(id: number): AuraData | false | nil
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or isSecret(a) then return false end
    return a   -- E2001 in SuuUI: `nil | AuraData | Secret<AuraData>` is not assignable
end
```

In a new project (`wowlua new --flavors camelot`, strict) the same file
checks clean. In SuuUI it fails, also with only `src/Core` and this file
left in the tree (no Units, no UI, no `libs` dependency); removing about ten
Core files (Anchors … Init) makes it pass again, but no single file does, and
importing the same stdlib modules from a scratch file doesn't reproduce it.
Not minimized further. `src/UI/ResourceBar.wowlua:193` shows the same error
(`not isSecret(n) and n`). The global `issecretvalue(v)` narrows correctly
in the same places. Workaround: these files call `issecretvalue` directly.

### U2. A generic predicate `v is V` doesn't infer `V` from `T | Secret<T>`

```wowlua
local function plainG<V>(v: V | Secret<V> | nil): v is V
    return not issecretvalue(v) and v ~= nil
end
local level = UnitLevel("player")              -- number | Secret<number>
local a: number = plainG(level) and level or 1 -- E2001: `1 | V` is not assignable to `number`
```

`V` stays unsubstituted (with a plain `number?` argument the true branch
works, but the false branch, `if not plainG(m) then return end`, also leaves
`V`). Workaround: a non-generic predicate,
`local function plain(v: unknown): v is string | number | boolean | table`,
which narrows both branches as wanted (used in FlightMap and WorldMap).

### U3. Narrowing is lost for a local set to nil before `break` in a loop

```wowlua
local out: number[]? = {}
for _, x in ipairs(xs) do
    if x < 0 then out = nil break end
    out[#out + 1] = x   -- E2005: `number[]?` may be `nil`
end
```

`out` can only be nil after the loop. Workaround: build into a non-optional
local and keep the optional one only as the result
(`FlightMap.wowlua`: `hopWay`'s `points`/`way`, `M:FlightRoute`'s `hops`/`run`).

### U4. `a and a ~= b and f(a)` includes `true`

```wowlua
local fixed = 1
local c = fixed and fixed ~= 2 and tostring(fixed)
if c then print(c:upper()) end  -- E2003: cannot index a value of type `true`
```

The comparison's `true` leaks into the result, though `and` only returns it
when it is the last operand. Workaround: an `if` (`FlightMap.wowlua`, `M:SetTitle`).

### U5. False "unused local" for a forward-declared local defined by `function name`

```wowlua
local tipBase
local function tipFor(g: number): number return tipBase(g) end
function tipBase(g: number): number return g + 1 end  -- W1003: unused local `tipBase`
```

The generated Lua is right (it assigns the local). Workaround:
`tipBase = function(...) ... end` (`WorldMap.wowlua`).

## 3. Stdlib gaps

- **`wowlua:secret` has no "readable and not nil" predicate.** SuuUI's map
  code tests nearly every API value with `plain(v)` (not secret and not nil)
  before comparing it; `secret.known(v, fallback)` needs a fallback and
  `isSecret` leaves the nil. A `secret.readable(v): v is …` (narrowing out
  `Secret` and `nil`) would replace each file's own `plain`. The files keep a
  local `plain` (U2 for why it isn't generic).

## 4. Port decisions

- **`issecretvalue` directly.** The old code fell back to
  `function() return false end` when the global was missing; the port calls
  the global (declared for camelot, and needed for narrowing, U1). On a client
  without it the call would error.
- **`plain` tests secrecy first** (`not issecretvalue(v) and v ~= nil`, was
  `v ~= nil and not isSecret(v)`): the same answer, without comparing a
  possible secret with nil.
- **Guards added where the types say a value may be secret and the old code
  indexed or compared it** (none of these was seen secret in game):
  Campsite's `aura()` treats a secret aura as unreadable (`false`, as in
  combat); `effectOf` returns no text for a secret tooltip; WorldMap's
  `fillText` reads a secret `UnitSex` as not female.
- **Timers and hooks through the stdlib** (`after`, `every`, `hook`,
  `hookScript`): same timing and post-hook behaviour, but an error in a
  callback is now reported by `wowlua:errors` instead of raised from the
  C_Timer/hooksecurefunc callback.
- **Data from the API.** `SuuUI.QuestStarts()`, `MapPlaces()`,
  `MapOverlays()`, `InstanceLevels()`, `FlightRoutes()`, `FlightPaths()`
  still return `any` from `src/Core/API.wowlua`. The files were checked a
  second time with those calls swapped for the typed `/Data/*` exports
  (`QuestStarts`, `MapPlaces`, …): clean, so they check either way.
- **Small rewrites for narrowing** (same behaviour): table reads by a
  variable key go through a local (`hopYards`, `hopWay`, `standing`,
  WorldMap's entrance levels and weapon masters, FlightMap's `QuestSteps`);
  ReadSession's `id` lookup and first path hop are split into statements;
  `M:Flown` casts its route to the placed shape after `route.points`.
- **Unused parameters** of `FlightMap`'s `M:InkMaster(pos, w, h)` became
  `_w, _h` (callers unchanged).
- **Bug left as it was:** `Campsite.wowlua`, `M:Alert`: every branch of the
  if/elseif/else returns, so the `BRIEF` timer after it never runs (W1005).
- Warnings left from the old code: `steps` shadowed in FlightMap's
  `FillSide`, `muted` (×3) and `S` shadowed in WorldMap.
