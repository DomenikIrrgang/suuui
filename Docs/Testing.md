# Testing SuuUI

SuuUI's tests run in wowlua's emulated client (`wowlua test`): a Lua 5.1 VM
with WoW's API, taint and secret values, and Blizzard's own UI code
(`test.blizzard-ui` in `wowlua.json`). The language and library reference is
wowlua's spec, chapter Tooling §16.1 (`wowlua:test`, `wowlua:mock`).

```
tests/
├── helpers.wowlua        errorsSoFar(), expectNoErrors(), newParent()
├── unit/<Dir>/<File>.test.wowlua   one per source file: src/<Dir>/<File>.wowlua
├── smoke/                the whole addon: login, every command, module, window
├── compat/               saved data and profile strings of older versions
└── profiles/             world profiles (tests/profiles/<name>.json)
```

`wowlua test` runs everything, `wowlua test unit/Core` one folder,
`wowlua test Settings` every file or test whose path or name has it.

## What a unit test is here

Every test file loads the whole addon and logs in (the runner can't load one
module alone), so "unit" means: the test drives **one module's exports** (or
one module object's methods) and checks **their** results, with the rest of
the world held still or faked. It never relies on another module's behaviour
to pass. One test file per source file, named after it.

- **Pure logic** (parsing, sorting, maths, formatting, state machines): call
  it with inputs, check outputs. Most of a module's code should be reachable
  this way (see Design below).
- **Components** (`src/UI`): build one in `newParent()`, drive it through its
  methods and through input (`mock.click`, `mock.hover`, `mock.typeText`,
  `mock.wheel`, `mock.slide`), check what it shows with the widget matchers
  (`toBeShown`, `toBeVisible`, `toHaveText`, `toHaveSize`, `toBeAnchoredTo`)
  and its callbacks with spies. Snapshots (`toMatchSnapshot`) only for a
  layout that is the point of the test; prefer direct assertions.
- **Feature modules** (`src/Units`): get the module with
  `SuuUI.GetModule(id)` (or import the parts it is made of), set the world
  up with `wowlua:mock` (units, bags, merchants, auras, combat, CVars,
  `mock.defineItem`/`defineSpell`), call its methods or fire the events it
  listens to, check its state and what it drew.
- **Settings**: change one with `settings.set(ns, key, value)` (watchers
  run), put it back in an `@afterEach` (`settings.reset(ns, key)`), or use
  `config({ profile = … })` for a whole saved state.

## Tools

| Need | Use |
|------|-----|
| A module's file-level locals | `import internal name from "/Units/Bags"` (test files only) |
| Replace a module's export for its users | `mock.module(ns, { fn = … })` with `import * as ns from "/X"` (reset per file) |
| Replace a WoW API function | `mock.fake("UnitHealth", function(unit) … end)` (restored after each test) |
| Replace a table field | `mock.stub(table, "key", fn)` |
| Record calls | `local s = mock.spy(); …; expect(s).toHaveBeenCalledWith(…)` |
| Time and frames | `mock.advanceTime(s)`, `mock.advanceFrames(n)`, `mock.waitFor(event)` |
| Combat, secrets | `mock.player:enterCombat()`, `mock.secret(v)` |
| Errors | `expectNoErrors()` from `tests/helpers`; `mock.errors()` alone misses what Fault catches |
| Several cases | `@cases({ { in, out }, … })` |

**Strict typing:** test files are checked in strict mode like `src/` (the
manifest's `check.mode`). No `--!nocheck`, `--!basic` or `@nocheck`; every
parameter of a named function is annotated; locals that start empty are
typed; module objects, components and data get their real exported types.
`:: any` only for genuinely dynamic values (a stand-in API, a field the
declarations lack), kept local and narrow.

Tests in one file share one VM: undo what a test changes (settings,
fakes are undone for you, frames you built: hide them) or give each test
what it needs in `@beforeEach`.

## Design for testing

Code is shaped so its logic can be tested without the frames around it:

- **Logic out of frame code.** A calculation inside an `OnEvent` handler or a
  draw function moves into a function of its own (a module-level function,
  exported or read with `import internal`), or, when a feature has a lot of
  it, into a sibling module (`src/Units/Bags/Sort.wowlua` beside
  `src/Units/Bags.wowlua`). The frame code calls it.
- **The world through parameters where it helps.** A function that reads the
  clock, a CVar or a unit can take the value as a parameter (with the live
  read as its default) instead of reading it inside, when faking it
  otherwise takes more than one `mock.fake`.
- **Classes where state lives, their dependencies as interfaces.** State
  lives in a class whose collaborators come in through its constructor as
  parameter properties, typed by interfaces, with the live ones as defaults:

  ```wowlua
  export interface CombatState
      function inCombat(): boolean
      function defer(@deferred fn: () -> ())   -- runs later: the load-order check knows
  end

  export class CombatQueue
      constructor(private combat: CombatState = GameCombat.new(),
                  private reporter: fault.Reporter = fault.log) end
      function run(key: any, fn: () -> (), source: string?) … end
  end

  export const queue = CombatQueue.new()          -- SuuUI's own
  export function run(key: any, fn: () -> (), source: string?) queue:run(key, fn, source) end
  ```

  The module's functions forward to its default instance, so callers don't
  change. A test builds an instance of its own over fakes and touches
  nothing global: `CombatQueue.new(FakeCombat.new(), FakeReporter.new())`.
  The shared fakes are in `tests/fakes.wowlua` (FakeReporter, FakeDispatcher,
  FakeCombat, FakeNotifier, FakeNextFrame); Core's FaultLog, EventBus,
  CombatQueue, ServiceRegistry, ExtendRegistry, SettingsStore (bound to saved
  data the test makes) and ModuleRegistry, and ForeverLFG's EntryStore, are
  built this way, each with "of its own" tests.
- **Components are widget classes.** `class Panel extends Frame`, `class
  WindowFrame extends Panel`, `class Text extends FontString`: fields
  declared and typed, methods on each frame as before, `Raw.Mixins` holding
  the classes. A frame the game makes (a secure header's unit button, a font
  string a frame creates) becomes an instance with `Class.adopt(frame, …)`.
  Handlers are `@script` methods or closures; a closure inside a method that
  needs the frame it's on names it (`function(row) … end`): its own `self`
  would hide the instance (wowlua warns, W1004).
- **Enums for fixed sets of strings.** `ModuleState`, `Kind`, `Role`,
  `MatchReason`…: compare against `Role.Tank`, and turn a string from the
  game into one with `reflect.enumFrom(Role, raw)` (nil when it isn't one).
  Tests compare against the members too (`expect(m.state).toBe(State.Enabled)`).
- **Never changed by it:** what the player sees and when, combat and taint
  behaviour (secure frames, protected calls, hooks), the public API
  (`Docs/API.md`), saved data, addon messages. `tests/smoke` and
  `tests/compat` must pass unchanged.

## Coverage

`wowlua test --coverage` measures lines, branches, functions and conditions
of `src/` (reports with `--reporter html`). The aim is all of it covered;
code that can only run in the real client (a probe of a client quirk, a
branch for a client without an API) gets `-- wowlua: coverage ignore` with a
reason on the same line.
