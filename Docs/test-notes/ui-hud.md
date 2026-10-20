# Test notes: ui-hud

Area: `src/UI/ActionBar`, `ActionButton`, `CooldownTracker`, `SwingTimer`,
`ThreatMeter`, `DamageMeter`, `Readiness`, `KeybindMode` (`.wowlua`). There is
one test file per source file in `tests/unit/UI/<File>.test.wowlua`, plus
`tests/unit/UI/HudHelpers.wowlua`, which provides `tokenOf(region)` and
`borderToken(border)`: the colour token Draw last painted a region with,
read through `import internal paints from "/UI/Draw"`.

## Files and coverage

The coverage below is from `wowlua test --coverage`, with each source file
measured by its own test file.

| Source | Tests | Lines | Branches | Functions | Conditions |
|--------|------:|------:|---------:|----------:|-----------:|
| ActionBar | 22 | 257/257 | 117/124 | 61/61 | 52/58 |
| ActionButton | 51 | 324/324 | 187/210 | 36/36 | 109/130 |
| CooldownTracker | 57 | 1083/1083 | 919/1094 | 116/116 | 578/708 |
| SwingTimer | 15 | 256/256 | 147/164 | 24/24 | 89/106 |
| ThreatMeter | 22 | 248/248 | 193/216 | 13/13 | 143/166 |
| DamageMeter | 33 (+1 skipped) | 717/717 | 497/614 | 53/53 | 333/426 |
| Readiness | 13 | 115/115 | 40/44 | 9/9 | 13/16 |
| KeybindMode | 15 | 186/186 | 84/96 | 26/26 | 31/42 |

Every line runs. The branches that are still not covered fall into four
kinds:

- **Unreachable sides of the `x and true or false` / `a and b or c` idiom.**
  `b` is never falsy, so the `or` side of those branches can never run.
- **Clients without an API** (`C_ActionBar and …`, `GetClassAtlas and …`,
  `IsMetaKeyDown and …`) and one-sided checks for secret values in compound
  conditions. The DamageMeter's secret amounts, totals and GUIDs are the bulk
  of its gap.
- **Structural cases.** For example, a live ranged row always has its
  `endsAt` and `length`, and `opts and opts.name` always has `opts`.
- `-- wowlua: coverage ignore` marks only real-client branches: the range
  poll for clients without range events in ActionBar, and `IMMEDIATE`
  without `Enum.StatusBarInterpolation` in SwingTimer.

## Refactors

None of these changes what the player sees, any secure attribute, snippet,
protected call, combat guard or secret guard, or a public name.

- **Exported types for every component.** These are `ActionBar`,
  `ActionButton`, `CooldownTracker` (with `TrackerCell`,
  `TrackerSeparators`, `TrackerBuilt`, `LiveGroup`), `SwingTimer` (with
  `SwingRow`, `SwingWindow`, `SwingQueued`), `ThreatMeter` (with
  `ThreatRow`, `ThreatEntry`, `ThreatOptions`), `DamageMeter` (with
  `DamageRow`, `MeterMenu`, `MeterMenuItem`, `MeterHeadButton`, `MeterView`,
  `MeterDrill`, `MeterRowData`) and `Readiness` (with `ReadinessRow`).
  - Each mixin table is typed with its interface, so the method bodies are
    now checked strictly.
  - The constructors still return `any`. Other agents' files, ClassBars
    above all, add their own fields to action buttons and bars, so changing
    the return types would change the signatures of exports they use.
  - The tests annotate with the exported types.
  - Strict checking brought only narrow `::` assertions where an invariant
    holds (`self.slot :: number` after `hasAction`, `self.drill ::
    MeterDrill` in the drill views) and `unpack(CLASS_ICON_TCOORDS[c])`
    written out as its four values.
- **SwingTimer** has named rows: `t.mainHand`, `t.offHand`, `t.ranged` and
  `t.window`, beside the `t.rows` map by `Enum.PlayerSwingType`, which is
  still the same rows.
  - `SetTexture((C_Spell.GetSpellTexture(id)))` now passes only the texture.
    Before, the second return went into the wrap-mode parameter.
  - `delayed` is coerced to a boolean. That saves one redundant repaint with
    the same colours.
- **KeybindMode**'s six scattered upvalues (`active`, `target`, `panel`,
  `status`, `highlight`, `catcher`) are now one `state` table.
  - `import internal` registers a module's locals with their values at the
    end of loading (spec §16.1.3.1). The frames were built lazily and
    reassigned, so tests could never see them; the table is read live.
  - The exports (`isActive`, `enter`, `exit`, `toggle`) are unchanged.
- **ActionBar**'s range poll for older clients moved out of its `OnUpdate`
  closure into `pollRange(dt)`. The poller frame is still made only without
  `C_ActionBar.EnableActionRangeCheck`, so the client is unaffected, and the
  function can now be tested.
- **ActionBar `Layout`**: `count` and `size` go through locals for the type
  checker. The deferred closure still reads `self.count` when it runs, as
  before.
- **DamageMeter `SessionOptions`** returns `SelectOption[]`. The unused
  `duration` field of past fights is gone; nothing read it.
- **CooldownTracker**: the spare lists and `rowH` go through locals. They
  give the same values.

## Bugs

- **Fixed: `shortKey("BACKSPACE")` returned `"BACKSp"`.** The `SPACE` rule
  ran first and ate the end of the key, so the `BACKSPACE` rule never
  matched. The rules now list `BACKSPACE` before `SPACE`. A Backspace binding
  now shows `Bs` on the button, as intended. The test is in
  `ActionButton.test.wowlua`, under the `shortKey` cases.
- **Skipped: DamageMeter with a secret `combatSources` table.**
  - The test is `@skip("bug: …")` "a secret source list".
  - `RefreshList` guards with `not isSecret(sources) and #sources == 0`, so a
    secret list passes the empty check. It then takes `#sources` and errors:
    "attempt to get length of local 'sources' (a secret table value)".
  - The guard shows the author expected a secret list. Whether the client
    ever returns one, and what the meter should then show, is open, so the
    code is left alone.

## VM suspicions

Two are already reported by other areas:

- `SetAlphaFromBoolean` stores its arguments but never sets the alpha
  (ui-units #1). The CooldownTracker's debuff-slot test stubs it and checks
  the boolean.
- A game event fired with `mock.fireEvent`, such as `GROUP_ROSTER_UPDATE`,
  runs Blizzard's handlers as tainted by SuuUI, and Blizzard's UnitFrame then
  errors on a secret `maxValue` (core-b). The CooldownTracker's static-
  condition test uses `SUUUI_ROLE_CHANGED` instead.

Nothing new in the engine behaved differently from what the code's comments
record. The secure paging (a `RegisterStateDriver` page change rewriting each
button's `action` through `_childupdate-page`) works as in the game.

## Test-runner and mock issues (new)

1. **`expect(nil).never.toBeShown()` fails with an internal error** instead
   of a matcher message: `wowlua/std/test.lua:586: attempt to index upvalue
   'value' (a nil value)`.

   ```wowlua
   @test("x") local function x() local t: { Frame } = {}; expect(t[1]).never.toBeShown() end
   ```

   I expected it to fail saying the value is not a frame (or nil).
2. **No way to leave a group in the mock.** There is `mock.group:add`, but no
   remove, and `C_PartyInfo.LeaveParty()` changes nothing (`IsInGroup()`
   stays true). A test that groups up leaves every later test in its file
   grouped. CooldownTracker's group and classes tests fake `IsInGroup`,
   `IsInRaid`, `UnitClass` and `UnitIsUnit` instead.

   ```wowlua
   mock.group:add(mock.spawnUnit({ name = "F", player = true }))
   C_PartyInfo.LeaveParty(); mock.advanceTime(1)
   expect(IsInGroup()).toBe(false)   -- fails: true
   ```
3. **One badly typed test file anywhere stops every test run.** `wowlua test`
   compiles all test files even with a filter, so a type error in another
   agent's half-written test file stops every run. To keep testing I ran my
   files in a scratch mirror of the tree under `/tmp`, with only my test
   files. Each was then verified in the worktree itself.

## Not tested, and why

- **Clicks on the secure buttons that cast.** Pressing a bound key on an
  action button would cast in the client. The tests check the override
  bindings (`SetOverrideBindingClick`, faked to record), the attributes, and
  the secure snippets' result (paging), not a cast.
- **The drag and drop snippets (`DRAG_START`, `RECEIVE_DRAG`, `CLICK_PRE`).**
  They are only read as attributes; the restricted environment's
  pickup-action path isn't driven.
- **Effects and aura containers in combat with real auras.** The engine's
  aura containers are exercised for build, reuse and max changes
  (`SetAuraGroupMaxFrameCount`), but not for what they draw.
- **The DamageMeter against the real `C_DamageMeter`.** The window takes a
  stand-in API (its `api`/`recapApi` options, made for previews), and all
  tests use one.
