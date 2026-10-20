# Test notes: ui-units

Files: `src/UI/UnitFrame`, `Auras`, `CastBar`, `ClassBars`, `ResourceBar`,
`RestedSign`, `WeaponEnchants` (`.wowlua`), each with
`tests/unit/UI/<File>.test.wowlua`.

| File | Tests | Lines | Branches | Conditions |
|------|------:|------:|---------:|-----------:|
| UnitFrame | 60 (+1 skipped) | 100% | 87.4% (746/854) | 83.4% |
| Auras | 24 | 100% | 78.1% (236/302) | 73.3% |
| CastBar | 31 (+1 skipped) | 100% | 85.1% (325/382) | 78.1% |
| ClassBars | 28 | 100% | 81.3% (283/348) | 76.4% |
| ResourceBar | 12 | 100% | 87.2% (136/156) | 83.7% |
| RestedSign | 9 | 100% | 92.1% (35/38) | 85.0% |
| WeaponEnchants | 17 | 100% | 83.4% (242/290) | 78.8% |

The branches left are mostly the client-API checks (`Enum.X and Enum.X.Y`,
`C_X and C_X.Fn`, `TOTEM_… or { … }`) that only go one way on this client,
and `x or default` fallbacks whose callers always pass `x`. No
`coverage ignore` marks were added.

## How the tests reach the world

On this client health, power and casts are secret even out of combat, and
a `mock.fake` of a global leaves it tainted for the rest of the file (see
below), so Blizzard's own handlers then fail on secrets. So the drawing
logic runs on stand-ins passed in, and real mock units drive the events and
the secret paths:

- UnitFrame: `opts.api` / `unitStandIn` (existing) for health, power,
  identity and the row; real `mock.spawnUnit` targets, auras, a raid
  (`mock.group:add`) and combat for events, containers and secrets.
- ResourceBar, WeaponEnchants, ClassBars: a stand-in for the game's
  functions (see Refactors).
- Methods a test needs to stand in for are stubbed on the instance
  (`mock.stub(frame, "UpdateHealth")`), module exports on the namespace
  (`mock.stub(fault, "report")`, `mock.stub(motion, "reduced")`,
  `mock.stub(editMode, "isActive")`).

## Refactors (behaviour unchanged)

- **UnitFrame**: `levelColor(level)` now calls the internal
  `difficultyColor(level, getColor)` with the game's
  `GetQuestDifficultyColor`; `groupTier(count)` calls the internal
  `groupTierIn(count, A)` with `_G`; `inYourGroup(unit, A = _G)` and
  `shortNumber(v, abbreviate = AbbreviateNumbers)` take the game's
  functions as defaulted parameters. Same reads, same answers; the tests
  pass stand-ins instead of faking globals Blizzard's frames read.
- **Auras**: `loadEngine(addons = C_AddOns)`; `auraContainer(parent, unit,
  opts)` calls the internal `newContainer(parent, unit, opts, CreateFrame)`
  (the tests give a `create` that fails: the "no aura containers" path).
- **CastBar**: `isInterrupt(id, class?)` and `find(class?)` take the class
  (the player's by default, via a new local `playerClass()`); `ready()` is
  `readyFrom(C_Spell.GetSpellCooldown(spell))` (the cooldown logic split
  out); `spellTarget(unit, A = _G)`; two small methods on the bar,
  `bar:SpellTarget()` (what `UpdateTarget` asks) and `bar:KickReady()`
  (what `UpdateKick` asks, `ready()`), so tests can stand in for the
  game's answers. Additions only; every existing name and call stays.
- **ResourceBar**: `opts.api` (new, optional): where the bar reads
  `UnitClass`, `UnitPower*`, `UnitExists`, `UnitCanAttack`,
  `GetComboPoints`, `UnitAffectingCombat`; `_G` by default. `usesPoints(A)`.
- **WeaponEnchants**: the game's item, tooltip, inventory and spell reads go
  through a local `G` (a table whose `__index` is `_G`, so the same
  functions are read at the same time); a local `reset()` clears the
  seen-state (state, seen, spellFor, tipNames, lastArt, weapons, lastCast,
  the ticker) for tests. Nothing else uses it.
- **ClassBars**: the form, pet, totem, spell, binding-key, cursor and CVar
  reads go through a local `G` the same way. Secure calls
  (`SetOverrideBindingClick`, `RegisterStateDriver`, attributes,
  `InCombatLockdown`) stay direct.
- **RestedSign**: none.

## Bugs found

- **Fixed: `levelColor` gave yellow ("quest-difficult") for green and grey
  levels.** The game's fonts are named `QuestDifficulty_Standard`,
  `QuestDifficulty_Trivial`, …; the match looked for the word anywhere, so
  the prefix's "Difficult" matched first. It now matches the word at the
  end (`difficultyColor`), VeryDifficult still checked before Difficult.
  Test: `difficultyColor: each difficulty font's colour`.

## VM suspicions

1. **`SetAlphaFromBoolean` does nothing.** On frames and FontStrings the
   alpha stays as it was, for plain and secret booleans:
   ```wowlua
   local f = CreateFrame("Frame"); f:SetAlphaFromBoolean(true, 0, 1)
   expect(f:GetAlpha()).toBe(0)   -- VM: 1
   ```
   SuuUI relies on it in game for the cast bar's arcane layer and lock,
   "you" badges and the unit frame's "is it you". The tests check the calls
   (stubbed) instead; `@skip` test `SetAlphaFromBoolean sets the alpha the
   answer stands for` (CastBar).
2. **The width of secret text reads plain.**
   `fs:SetText(mock.secret("Hidden")); issecretvalue(fs:GetUnboundedStringWidth())`
   is false; in game it is secret (UI/Text's `measureText`, UnitFrame's
   `LayoutRow` handle it). `@skip` test in UnitFrame; the secret-name row
   test stubs the width.
3. Minor: a frame never anchored reports its children's rects against the
   screen (`SetAllPoints()` child of an unplaced 200px button: 1920 wide);
   in game they have no rect. The tests anchor their frames.

## Test runner / mock issues (wowlua 0.9.1)

1. **`mock.fake` (and `mock.stub` on `_G`) leaves the global tainted after
   it is restored**: the restore writes it back from the test's (addon)
   code. Blizzard's handlers that read it later run tainted and error on
   secret values (`UnitFrame.lua:814: attempt to compare local 'maxValue'
   (a secret number value, while execution tainted by 'SuuUI')`).
   ```wowlua
   @test("a") local function a() mock.fake("GetNumGroupMembers", function(): number return 3 end) end
   @test("b") local function b() expect("GetNumGroupMembers").toBeSecure() end  -- fails: SuuUI tainted it
   ```
   Hence the stand-ins above instead of fakes.
2. **`MockUnit:token()` returns a string** (`"raid2"`), though declared
   `string[]` (`for _, t in ipairs(u:token())` errors).
3. **Matchers can't take secrets**: `expect(spy).toHaveBeenCalledWith(x,
   mock.secret(true))` errors inside the matcher ("attempt to compare … a
   secret boolean value"); `rawequal` on a secret is refused too. The tests
   check `issecretvalue` of what was handed on.
4. **`mock.errors()` and `fault.entries()` accumulate for the whole file**:
   one test's error fails every later `expectNoErrors()` in the file. The
   tests that need it compare counts (`#errorsSoFar()` before and after).
5. **W1003 for a local only read through `import internal`**
   (`WeaponEnchants.reset`): the checker doesn't count test files' internal
   imports as reads.
6. `mock.player:setName` fires no `UNIT_NAME_UPDATE`; the test fires it.

## Not tested, and why

- What the engine draws inside aura containers (icons, timers, dispel
  colours): the engine's own; the tests check the initializer's styling and
  registrations, the containers' calls, and that buttons get made.
- The secure actions themselves (casting a form, a totem, pet autocast):
  the tests check the attributes and bindings, not the client's casting.
- The alpha the engine sets from booleans (VM suspicion 1).
