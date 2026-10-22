# Test notes: core-a

Area: `src/Core/Settings`, `Modules`, `Events`, `Fault`, `Combat`,
`Services`, `Extend`, `Init`, `DB`, `Util` (`.wowlua`). One test file per
source file in `tests/unit/Core/<File>.test.wowlua`.

## Files

| Source | Test file | Tests |
|--------|-----------|-------|
| `src/Core/Util.wowlua` | `tests/unit/Core/Util.test.wowlua` | 11 |
| `src/Core/DB.wowlua` | `tests/unit/Core/DB.test.wowlua` (manual lifecycle) | 2 |
| `src/Core/Services.wowlua` | `tests/unit/Core/Services.test.wowlua` | 4 |
| `src/Core/Combat.wowlua` | `tests/unit/Core/Combat.test.wowlua` | 7 |
| `src/Core/Events.wowlua` | `tests/unit/Core/Events.test.wowlua` | 14 |
| `src/Core/Init.wowlua` | `tests/unit/Core/Init.test.wowlua` | 11 |
| `src/Core/Fault.wowlua` | `tests/unit/Core/Fault.test.wowlua` | 17 |
| `src/Core/Extend.wowlua` | `tests/unit/Core/Extend.test.wowlua` | 20 |
| `src/Core/Settings.wowlua` | `tests/unit/Core/Settings.test.wowlua` (manual lifecycle) | 43 |
| `src/Core/Modules.wowlua` | `tests/unit/Core/Modules.test.wowlua` (manual lifecycle) | 40 |

Three files drive the lifecycle themselves (`config({ lifecycle = "manual" })`)
so the code before and at load can be tested. Their `@beforeAll` records what
the code does before load, logs in, and records the state at load; the tests
assert on those records, so any test also runs alone (a name filter such as
`wowlua test compat` selects single tests from these files too: checked).

- **DB**: the tables before `ADDON_LOADED` (locked), then `mock.login()` with
  a prepared `SuuUIDB`/`SuuUIProbe` (kept as given, globals are the bound
  tables, only `__version` added).
- **Settings**: before load: defaults readable, writes refused, every
  `/suu get|set|reset|profile` says "not loaded yet"; then login with a
  prepared `SuuUIDB` (a character mapping, a migration
  registered before load and run on every profile, a veto screening the
  current profile, a value of the wrong type, a non-table profile). Calling
  the internal `bind()` again covers a character mapped to a missing profile.
- **Modules**: modules registered at the file's top start at login like
  SuuUI's own; `@beforeAll` logs in *in combat* (combatSafe modules start at
  once, the others when combat ends, a `replaces` pair, an incompatible API).

## Coverage

`wowlua test -j 2 --coverage --reporter pretty,coverage-json unit/Core`
(2026-10-20, all of `tests/unit/Core`):

| File | Lines | Branches | Functions | Conditions |
|------|-------|----------|-----------|------------|
| Util | 20/20 | 14/14 | 5/5 | 4/4 |
| DB | 14/14 | 0/0 | 1/1 | 0/0 |
| Services | 19/19 | 6/8 | 3/3 | 0/0 |
| Combat | 24/24 | 7/8 | 3/3 | 0/0 |
| Events | 51/51 | 25/32 | 10/10 | 16/20 |
| Init | 57/57 | 21/28 | 6/6 | 8/10 |
| Fault | 124/124 | 67/78 | 16/16 | 24/30 |
| Extend | 184/184 | 79/86 | 25/25 | 21/24 |
| Settings | 520/520 | 395/422 | 58/58 | 177/200 |
| Modules | 271/271 | 169/190 | 60/60 | 86/100 |

Every line and function runs. The branches left are listed below (mostly
the failing side of `assert`s on typed parameters, defensive `or ""` /
`if t then` guards whose other side can't happen, and the not-loaded side of
`DB.loaded()` inside Fault, which only the DB file's pre-login phase could
reach).

## Refactors

None. Every branch of these files is reachable through their exports, the
module objects' methods, `/suu` commands, events, or `import internal` (the
pure helpers `parse`, `show`, `splitPath` and `bind` in Settings); splitting
them would have touched the foundation every other agent imports while they
worked, for no testability gain. No export, signature or behaviour changed.

## Bugs found

None.

## Behaviour pinned down worth knowing

- `Util.copy` (wowlua:table) keeps a table met twice as one table in the copy,
  cycles included; `Util.equal` is false for any secret, even itself.
- `Events`: a listener removed during a dispatch (by another listener or
  itself) isn't called from then on; one added during a dispatch first hears
  the next one.
- `Settings`: a watcher that rewrites its setting supersedes the outer
  notification: later watchers hear only the newest value and
  `SUUUI_SETTING_CHANGED` fires once.
- `Combat`: a second request for a waiting key keeps the first one's place and
  runs the latest function under the latest source; combat starting again
  mid-flush leaves the rest for the next end.

## Not covered, and why

- **Argument assertions with wrong types** (`Events.on`'s "callback must be a
  function", `Services.provide`'s, `Extend.each/hook/override/extendMenu`'s,
  `Settings.register/watch/migrate`'s, `Modules.register(5)`): the test
  profile's `runtime-checks = "exports"` rejects the call at the export's
  typed parameter first ("bad argument #2 'fn' to 'on' (… expected, got
  string)"), so the `assert` message only shows in builds without runtime
  checks. The tests check that the call raises; the asserts' message
  arguments stay unexercised. (Assertions on values the types allow, such as
  a nil owner, an empty unit list, an empty migration id, are tested with
  their messages.)
- `Init.listCommands`: the `continue` for a name in `order` without a command
  can't happen (`unregisterCommands` removes both together).
- `Settings` `setValues`: the branch where creating the profile fails is
  unreachable (a name `create` would refuse, `find` already returned).
- `Modules` `disable`: the `incompatible` guard is unreachable (`apply` and
  the commands return before it for an incompatible module).
- `Modules` `sourceAddon`: in the VM `debugstack()` lacks the
  `Interface/AddOns/<Addon>/` prefix (known, V1 in
  `Docs/wowlua-0.9.1-report.md`), so the test fakes `debugstack` with the
  game's form.
- `Fault`: the `DB.loaded()`-false sides (report, `/suu errors clear`,
  blocked actions before the SavedVariables load) aren't driven: Fault's test
  runs logged in.
- Defensive fallbacks that can't be false/nil: `Init` `msg or ""`, `word or
  ""`, `rest or ""` after a match that always captures; `Fault.firstLine`'s
  `or ""`; `Extend`'s `hk(kind)[method] or {}` in `rewrap`; `Settings.write`'s
  `if t` when resetting a key nothing stored (set returns earlier); `screen`'s
  `continue` for an id without a dot; `Modules`' `fields[m]` nil in the
  metatable and `STATE_TEXT[state] or state`.
- `DB`: writing the tables back at logout/reload (the client's side) isn't
  exercised; the tests check that the globals are the bound tables.

## VM suspicions

None new.

## wowlua compiler / test runner issues

- **A filtered run type-checks every test file.** `wowlua test unit/Core/Util`
  aborts ("aborting due to N previous errors", 0 files run) when any other
  test file in `tests/` has a type error, so one broken file blocks every
  agent's runs. Repro: two test files, `a.test.wowlua` with `local x: number
  = "s"`, `b.test.wowlua` passing; `wowlua test b` runs nothing. A filter
  could check only the files it selects (plus `tests/mocks` and helpers).
