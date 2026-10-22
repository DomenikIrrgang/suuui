# Plan: classes for state and dependencies (testability)

Status: **proposed** (2026-10-20), not started. Written so another agent can
pick it up without the conversation it came from.

## Where the code is

This plan applies to the **wowlua port**, not to `main`:

- `main` still holds SuuUI in plain Lua.
- Branch **`wowlua-port`**: SuuUI ported to strict **wowlua** (0.9.1), every
  source a `.wowlua` module. Read its `CLAUDE.md`,
  `Docs/wowlua-port-conventions.md` and `Docs/wowlua-port-notes.md`.
- Branch **`wowlua-tests`** (based on `wowlua-port`): unit tests in progress.
  **Do this work on `wowlua-tests`** (or a branch off it). Read its
  `Docs/Testing.md` first, then `Docs/test-notes/*.md` (one per area) and
  `Docs/wowlua-0.9.1-report.md` (known compiler/VM issues and workarounds).

State of `wowlua-tests` when this was written: unit tests done and committed
for Core (all of it), the unit-frame components (UnitFrame, Auras, CastBar,
ClassBars, ResourceBar, RestedSign, WeaponEnchants) and the HUD components
(ActionBar, ActionButton, CooldownTracker, SwingTimer, ThreatMeter,
DamageMeter, Readiness, KeybindMode). Three more areas were being finished
(UI primitives, UI windows/skins, UI social windows); the rest
(`src/UI` world/professions and talents/settings/edit mode, and all of
`src/Units`) had not started. Check `git log` and `tests/unit/` for the
current state.

## Why

There is not a single `class` in the codebase: the port turned every
`ns.X` table into a module of functions with module-level state. Writing the
unit tests showed what that costs:

- **Shared state between tests.** A test file runs in one VM; Events,
  Fault, Settings, Extend, Combat and Services keep their state in
  module-level locals, so tests clean up by hand, and agents added
  test-only resets. Fault's error list and `mock.errors()` accumulate over a
  file, so one error fails every later `expectNoErrors()`.
- **Faking the world through globals.** `mock.fake("UnitHealth", …)`
  replaces a global, and in wowlua 0.9.1 the global **stays tainted after it
  is restored** (Blizzard's frames then error on secret values). Some
  components were already changed to take stand-in APIs as parameters
  (`opts.api`, `A = _G` defaults in UnitFrame, CastBar, ResourceBar…) to
  avoid it.
- **Swapping one collaborator.** `mock.module(ns, {…})` replaces a module's
  exports for the whole file and every importer.

Classes whose dependencies come in through the constructor fix all three:
each test builds fresh instances with fakes, nothing global is touched, and
the addon keeps one default instance wired to the real world.

## Design

1. **Dependencies are interfaces** (structural), so a fake is a plain table
   or a small class that satisfies them, and the strict checker verifies it.
   wowlua classes are nominal and sealed, so don't type a dependency as a
   class.
2. **Constructor injection with live defaults:**
   ```wowlua
   export interface CombatState function inCombat(): boolean end
   export interface Reporter function call(source: string, fn: (...any) -> ...any, ...: any): (boolean, ...any) end

   export class CombatQueue
       private waiting: { [any]: Job } = {}
       constructor(private combat: CombatState = liveCombat, private fault: Reporter = liveFault) end
       function run(key: any, fn: () -> (), source: string?) … end
       function pendingCount(): number … end
   end
   ```
3. **One default instance per module, behind the existing exports.** Every
   export keeps its name, signature and behaviour; it forwards to the default
   instance (`export function run(...) return queue:run(...) end`), so no
   other file has to change. New code and tests may use the class directly.
4. **Tests build their own instances**:
   `local q = CombatQueue.new(fakeCombat, fakeFault)`. Remove test-only
   resets once nothing needs them.
5. Keep the code style: comments kept and updated, camelCase functions,
   PascalCase classes and types, strict mode, no `--!nocheck`/`@nocheck`.

## Scope, in order

### Step 1 — verify widget classes against `SuuUI.Raw.Mixins` (do first, alone)

Components (`UI.Panel`, `UnitFrame`, `CastBar`, …) mix their methods onto
each frame, and `SuuUI.Raw.Mixins` exposes those method tables: the plugin
guide promises that **a plugin changing one when its file loads changes
every frame SuuUI builds afterwards** (`Docs/API.md`, `Docs/PluginGuide.md`).
wowlua widget classes (`class Panel extends Frame`, spec §3.2) flatten their
methods into one mixin at class finalization and raw-copy it onto each new
frame. Check in a scratch project with wowlua 0.9.1:

- Can that flattened mixin table be reached (to put it in `Raw.Mixins`), and
  does changing it after finalization reach frames constructed later?
- Do `Extend.hook`/`override` (they patch methods on each instance with
  `rawset`) still work on widget-class frames?

If both hold, components may become widget classes in a later step, with
`Raw.Mixins` pointing at the class mixins. If not, components stay as they
are (functions building frames) and only their dependencies get injected.
Write the result into `Docs/test-notes/classes.md`.

### Step 2 — Core state into classes

| Module | Becomes | Inject |
|--------|---------|--------|
| `src/Core/Events.wowlua` (bus on wowlua:events) | `EventBus` | the stdlib dispatcher, the reporter (Fault) |
| `src/Core/Combat.wowlua` | `CombatQueue` | combat state (`inCombat`, `defer`), reporter |
| `src/Core/Fault.wowlua` | `FaultLog` (+ timing) | chat print, the saved DB, clock (`debugprofilestop`, `collectgarbage`), taint scan |
| `src/Core/Extend.wowlua` | `ExtendRegistry` | reporter, the end-of-frame runner, the event bus |
| `src/Core/Services.wowlua` | `ServiceRegistry` | the event bus |
| `src/Core/Settings.wowlua` watchers/vetoes/migrations | `SettingsStore` (profiles stay as they are stored) | the saved DB, reporter, event bus, character key |
| `src/Core/Modules.wowlua` registry | `ModuleRegistry` | settings, event bus, combat queue, reporter, extend, services, the command registry |

**Module objects stay open tables** (`SuuUI.RegisterModule` returns them):
plugins and the built-in modules add fields and methods to them
(`M.frame = …`, `function M:Refresh()`), which a sealed class forbids. Only
the registry around them becomes a class.

Rewrite the Core unit tests (`tests/unit/Core/*.test.wowlua`) to use fresh
instances where that removes setup/cleanup; keep tests of the exported
functions too (they are what the rest of SuuUI uses).

### Step 3 — state inside feature modules and the library

Candidates (decide per file; only where state or world reads make tests
awkward): the bag sort planner (`src/Units/Bags*`), raid planner setups
(`src/Units/RaidPlanner*`), the notification stack, cooldown setups
(`src/Units/CooldownManager*`), ForeverLFG's store, parts and parser
(`libs/ForeverLFG/src`). Feature modules keep using only the public API
(`import SuuUI from "/Core/API"`) for SuuUI's own parts.

### Step 4 — update the testing docs

Add the pattern to `Docs/Testing.md` ("Design for testing": classes with
interface-typed dependencies, default instance behind the exports, fresh
instances in tests) so the remaining test areas use it.

## Hard constraints (unchanged from the port)

- What the player sees and when stays the same.
- Secure frames, protected calls, taint-sensitive hooks, combat guards and
  secret-value guards stay exactly as they are.
- The public API (`Docs/API.md`, the `SuuUI` global, module objects'
  methods) keeps every name and behaviour, including `Raw.Mixins` semantics.
- `SuuUIDB` / `SuuUIProbe` layouts, profile strings and addon messages
  unchanged.
- `tests/smoke` and `tests/compat` pass unchanged (they guard behaviour).

## How to work

- **At most 3 agents at once** on this machine (more crashed it); run tests
  one file at a time with `wowlua test -j 2 <filter>`, never the whole suite
  in parallel with other runs. A filtered `wowlua test` still type-checks
  every test file: one broken test file blocks everyone's runs.
- Coverage: `wowlua test -j 2 --coverage <filter>` (works because
  `tests/mocks/gc.wowlua` stops the GC; see report C40).
- Tests are strictly typed like the sources.
- **Public repository:** never write a real player's or character's name or
  GUID anywhere (tests, comments, notes); use placeholders ("Tamsin
  Ashford", "Player-0000-00000000"). Scan the staged diff for the recorded
  names before every commit.
- Gate: `wowlua check` (no errors), every test file passes, `smoke` and
  `compat` pass, before each commit. Commit per step; push the branch.
- Write wowlua VM/runner/compiler findings (with minimal repros) into
  `Docs/test-notes/<area>.md`; they feed `Docs/wowlua-test-findings.md`, the
  report for wowlua's maintainers.

## Done when

- Steps 1–4 are done and committed on `wowlua-tests`.
- Core's state lives in classes with interface-typed dependencies; the
  exports forward to default instances; the Core tests use fresh instances.
- The step 1 result is recorded, and components are either widget classes
  (if `Raw.Mixins` semantics hold) or documented as staying builders.
- All gates pass.

## Status

Done on `wowlua-classes` (2026-10-23): steps 1 to 4. The record, with the
wowlua findings and their fixes, is `Docs/test-notes/classes.md`.
