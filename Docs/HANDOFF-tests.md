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
| ui-hud | src/UI: ActionBar, ActionButton, CooldownTracker, SwingTimer, ThreatMeter, DamageMeter, Readiness, KeybindMode | 100% lines; fixed shortKey("BACKSPACE"); DamageMeter's secret source list fixed later |
| ui-primitives | src/UI: Draw, Text, Icon, Bar, Panel, Layout, Controls, Inputs, Select, Pickers, SettingRow, SettingsMatrix, TabMarker, Crest, LoadingMark, Stage, Visibility | 100% lines; no source changes |
| ui-windows | src/UI: Reskin, WindowSkin, Tooltip, ContextMenu, FilterMenu, Notification, Alert, Loot, LevelUp, MicroMenu | 100% lines; fixed Reskin hooks lost on Blizzard's pooled menu frames |
| ui-social | src/UI: GroupFinder, GroupFinderListed, GroupFinderListing, GroupFinderWho, Guild, GuildControl, Social | 100% lines; typed view data |

Done since (2026-10-20 to 2026-10-22), each with its notes in
`Docs/test-notes/<area>.md`: ui-world, ui-settings, units-chat,
units-cooldowns, units-bags, units-trade, units-character, units-maps,
units-talents, units-group, units-notices, units-social, units-windows,
units-hud. The checkpoint's work in them was finished or replaced. Every
area of the plan is done.

The tests need wowlua 0.9.6 or later and, until the next release, the
build of `m9-coverage-stale-handle`: Guild's needs T244 (a hidden edit
box lets go of the keyboard), Tooltips' T245 (tooltips in combat),
Windows' T246 (`mock.postLFGListing`), Threat's T247 (group threat lists)
and T248 (a trained spell known), Auras' T249 (`UNIT_CONNECTION`).

The final pass is done too (2026-10-22): every file passes on its own and
the whole suite in one run (3,590 tests in 174 files, none skipped: the six
skips that waited on wowlua's fixed VM issues run again, and the one
skipped bug, DamageMeter's secret source list, is fixed); `wowlua.json`
sets the coverage minimums a little under what the suite reaches (lines
88.1%, branches 64.0%, functions 84.6%, conditions 60.6%; they apply to a
run without filters only, wowlua T250); no test file opts out of checking
(`:: any` casts are stand-ins of Blizzard frames given extra fields);
`Docs/wowlua-test-findings.md` covers every area with each finding's
status; CLAUDE.md describes the tests. Nothing is merged to `main`.

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
- A test file that doesn't compile fails alone now (wowlua 0.9.3), and a
  filter loads only the files it matches (0.9.4).
- `tests/mocks/gc.wowlua` (GC stopped in tests) works around the coverage
  crash (report C40); keep it until wowlua is fixed.
- Test profile `runtime-checks = "exports"` (wowlua.json): "all" fails on
  SuuUI's step-by-step frame building (report C39).
- Never push to `main`, never force-push; push branches only.

## Known open items outside the tests

- In-game checks of taint-sensitive paths after the port (list in
  `Docs/wowlua-port-notes.md`, "In game checks"), and of the Reskin menu-hook
  fix (ui-windows).
- The `plain(v)` nil-vs-secret order question (needs a probe in game).
- Design questions from the tests: `autoQuestWatch` and "Track accepted
  quests" (units-notices).
- wowlua issues to report: `Docs/wowlua-0.9.1-report.md` (the port) and
  `Docs/wowlua-test-findings.md` (the tests; every area, with status).
