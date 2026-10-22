# Handoff: SuuUI wowlua port and unit tests (state on 2026-10-20)

For the next agent. Everything needed to continue is in the repository and
in the files this one points to.

## The branches

| Branch | What | State |
|--------|------|-------|
| `main` | SuuUI in plain Lua (released line) + `Docs/plans/classes-for-testing.md` | untouched except that plan |
| `wowlua-port` | SuuUI fully ported to strict **wowlua** 0.9.1 | done; tested in game by the user ("everything seems to work"); not merged |
| **`wowlua-tests`** | based on `wowlua-port`: unit tests and refactors for testability | **in progress — continue here** |

Local worktrees: `~/repositories/suuui.worktrees/wowlua-port` and
`~/repositories/suuui.worktrees/wowlua-tests` (the main checkout
`~/repositories/suuui` is on `main`). Both branches are pushed to origin.
The installed game build (`_classic_beta_/Interface/AddOns/SuuUI`) is the
release build of `wowlua-port` at d5345f5.

## Read first

1. `CLAUDE.md` (building with wowlua, working rules, releasing).
2. `Docs/Testing.md` (test layout, what a unit test is here, tools, design
   for testing, strict typing in tests, coverage).
3. `Docs/handoff/test-agent-brief.md` (the exact brief test agents got).
4. `Docs/plans/classes-for-testing.md` (on `main`, also below): the next
   design step the user is considering.
5. `Docs/wowlua-port-conventions.md`, `Docs/wowlua-port-notes.md`
   (port decisions, open items, in-game checks).
6. `Docs/wowlua-0.9.1-report.md` (every wowlua compiler/VM/stdlib finding of
   the port, C1–C40, S1–S23, with repros and the workarounds in SuuUI).

## What the user asked, and decided

- Unit tests (no integration tests yet) for **Core, UI components (incl.
  SettingsUI, EditMode) and feature modules (src/Units)**, using `wowlua test`
  (`wowlua:test`, `wowlua:mock`). Not for Diagnostics, Data, the library or
  the examples.
- **Full redesign allowed where it makes testing better**, but what the
  player sees must not change (also secure/taint paths, public API, saved
  data, addon messages).
- **Aim for (near) full coverage.**
- **Tests strictly typed** like the sources (no `--!nocheck`/`--!basic`/
  `@nocheck`, annotated parameters, narrow `:: any` only).
- Branch `wowlua-tests` off `wowlua-port`, pushed.
- **At most 3 agents at once** (20 parallel test-running agents crashed the
  user's PC). Agents run tests one file at a time with `-j 2`.
- **Paused by the user:** no new agents until the user says so. Ask before
  resuming the queue.
- **`Docs/wowlua-test-findings.md`** (written after the first 7 areas; keep
  it up to date): one
  report with every wowlua finding from running the tests (VM suspicions,
  test runner/mock issues, compiler issues; repros), deduplicated, not
  repeating `Docs/wowlua-0.9.1-report.md` (reference it). Sources:
  `Docs/test-notes/*.md`. The user hands it to the agent working on wowlua.
- The user is considering classes with injected dependencies for testability
  (`Docs/plans/classes-for-testing.md`); it isn't decided whether that comes
  before the remaining test areas. Ask.

## Progress

Done, verified (each file passes alone with `-j 2`; `smoke` and `compat`
pass) and committed, with notes in `Docs/test-notes/<area>.md`:

| Area | Sources | Notes |
|------|---------|-------|
| core-a | src/Core: Util, DB, Services, Combat, Events, Init, Fault, Extend, Settings, Modules | 100% lines; no source changes |
| core-b | src/Core: API, Themes, ThemesBuiltin, Vision, VisionPresets, Fonts, Pixel, Root, Anchors, Blizzard, Motion, Roles, RolePresets, Serialize, Perf, Tokens | 100% lines; fixed SuuUI.UI.CooldownConditionMet missing, OpenRecipe fallback |
| ui-units | src/UI: UnitFrame, Auras, CastBar, ClassBars, ResourceBar, RestedSign, WeaponEnchants | 100% lines; stand-in APIs injected; fixed levelColor |
| ui-hud | src/UI: ActionBar, ActionButton, CooldownTracker, SwingTimer, ThreatMeter, DamageMeter, Readiness, KeybindMode | 100% lines; fixed shortKey("BACKSPACE"); 1 skipped bug (DamageMeter secret source list) |
| ui-primitives | src/UI: Draw, Text, Icon, Bar, Panel, Layout, Controls, Inputs, Select, Pickers, SettingRow, SettingsMatrix, TabMarker, Crest, LoadingMark, Stage, Visibility | 100% lines; no source changes |
| ui-windows | src/UI: Reskin, WindowSkin, Tooltip, ContextMenu, FilterMenu, Notification, Alert, Loot, LevelUp, MicroMenu | 100% lines; fixed Reskin hooks lost on Blizzard's pooled menu frames |
| ui-social | src/UI: GroupFinder, GroupFinderListed, GroupFinderListing, GroupFinderWho, Guild, GuildControl, Social | 100% lines; typed view data |

Done since (2026-10-20 to 2026-10-22), each with its notes in
`Docs/test-notes/<area>.md`: ui-world, ui-settings, units-chat,
units-cooldowns, units-bags, units-trade, units-character, units-maps,
units-talents, units-group, units-notices, units-social, units-windows. The checkpoint's work in them was finished or
replaced.

Not done (the queue), in this order:

| Area | Sources | Partial work in 68d8ab6 |
|------|---------|--------------------------|
| units-hud | src/Units: ActionBars, Auras, CastBars, UnitFrames, SwingTimer, Threat, Timeline, DamageMeter | none (never started) |

The tests need wowlua 0.9.6 or later and, until the next release, the
build of `m9-coverage-stale-handle`: Guild's needs T244 (a hidden edit
box lets go of the keyboard), Tooltips' T245 (tooltips in combat) and
Windows' T246 (`mock.postLFGListing`).

Then:

1. Run every test file one at a time (`for f in tests/**/*.test.wowlua; do
   wowlua test -j 2 <path>; done`), fix or `@skip` failures (with a reason),
   then `wowlua test -j 2 --coverage` for the totals and set
   `test.coverage.lines` (and branches) in `wowlua.json` to what's reached.
2. Grep the tests for `--!nocheck`, `--!basic`, `@nocheck`; review `:: any`.
3. Bring `Docs/wowlua-test-findings.md` up to date: it was written after
   the first 7 areas; add the new findings of the remaining areas (from
   their `Docs/test-notes/*.md`) in the same format, keeping the ids.
4. Update `CLAUDE.md` (tests now exist: `wowlua test`, layout, strict tests).
5. Commit, push `wowlua-tests`. Don't merge or push to `main` unless the
   user asks.

## Rules that bit before

- **Identity scan before every commit** (public repo): stage, then
  `python3 -I tools/idscan.py .`; every line must end in `: 0` (the "player
  links" line may show Lua patterns or test placeholders like "Bob": check
  with `git diff --cached | grep -o '|Hplayer:[^|:\]]*'`). `--where` prints
  file:line of name hits. Extra names live in
  `~/.config/suuui/idscan-names.txt` (local, never committed). A test once
  copied a real name out of a source comment; use placeholders ("Tamsin
  Ashford", "Brannoc Ironhand", "Player-0000-00000000").
- Commit only after the scan is clean (gate the commit on it; a scan that only
  prints doesn't stop anything).
- `git mv` keeps history; agents must not run other git commands.
- `wowlua test` with a filter still type-checks every test file: one broken
  test file blocks every run.
- `tests/mocks/gc.wowlua` (GC stopped in tests) works around the coverage
  crash (report C40); keep it until wowlua is fixed.
- Test profile `runtime-checks = "exports"` (wowlua.json): "all" fails on
  SuuUI's step-by-step frame building (report C39).
- Never push to `main`, never force-push; push branches only.

## Known open items outside the tests

- In-game checks of taint-sensitive paths after the port (list in
  `Docs/wowlua-port-notes.md`, "In game checks"), and of the Reskin menu-hook
  fix (ui-windows).
- The skipped bug in DamageMeter (secret `combatSources`), and the `plain(v)`
  nil-vs-secret order question (needs a probe in game).
- wowlua issues to report: `Docs/wowlua-0.9.1-report.md` (the port) and
  `Docs/wowlua-test-findings.md` (the tests; first 7 areas).
