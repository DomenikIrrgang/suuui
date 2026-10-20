# Test notes: core-b

Area: `src/Core/` API, Themes, ThemesBuiltin, Vision, VisionPresets, Fonts,
Pixel, Root, Anchors, Blizzard, Motion, Roles, RolePresets, Serialize, Perf,
Tokens. One test file per source file in `tests/unit/Core/<File>.test.wowlua`.

## Test files

| Source | Test file | Tests |
|---|---|---|
| API | `tests/unit/Core/API.test.wowlua` | every name Docs/API.md documents (184 `SuuUI.*` paths and the UI components it lists), Raw.UI covering SuuUI.UI, the API's own functions (services on/off/partial, alerts allowed out of combat and replayed on SUUUI_SERVICE_CHANGED, OpenRecipe's fallback, ProfessionOpener, FullName, AddFriend's paths, data accessors, role presets, colour vision, AccountData) |
| Themes | `Themes.test.wowlua` | register's checks and defaults, apply: colours with hex and alpha, fonts, a missing theme, worked-out colours (by class, erroring, not a table, unknown tokens), colour vision on top, repaint |
| ThemesBuiltin | `ThemesBuiltin.test.wowlua` | every built-in theme, hex parsing, no signal/game colour changed, class accent's 7:1 text for all nine classes and the 50-step cap, toned class hue, the sRGB/OKLab maths (via `import internal`), each theme applies cleanly |
| Vision | `Vision.test.wowlua` | modes, available (incl. no or empty presets), apply in place keeping alpha/hex, unknown modes, glows following (focus ring's inner layer kept), syncGlows with a missing glow or a layer without colour |
| VisionPresets | `VisionPresets.test.wowlua` | both presets name the same 20 design tokens, values in range and matching their hex, own alphas |
| Fonts | `Fonts.test.wowlua` | one Font per style (name, face, size, spacing, justify, ink), unknown style error, apply, refresh, refresh skipping a gone style |
| Pixel | `Pixel.test.wowlua` | screenHeight, perfectScale, size, snap, SUUUI_PIXEL_CHANGED only on a real change (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED, CVAR_UPDATE for the scale CVars only), `/suu pixel` |
| Root | `Root.test.wowlua` | the root frame, ui defaults, the scale veto, automatic scale per screen height, userScale (incl. settings not ready), rescale on settings and screen changes, combat deferral to the latest value, the issue reporter hidden/shown/re-hidden and on its addon's load |
| Anchors | `Anchors.test.wowlua` | publish/get/unpublish and SUUUI_ANCHOR_CHANGED only on change |
| Blizzard | `Blizzard.test.wowlua` | suppress by frame and name, children by path, keepParent, noHide, reparent back after the game moves it, protected frames in combat (named and unnamed), Edit Mode open, restore/isSuppressed |
| Motion | `Motion.test.wowlua` | reduced, fadeIn/enter/pop groups and their settings, reuse, reduced motion, stop, alphaTo's driver (ease, same target, retarget, immediate cases, cancel) |
| Roles | `Roles.test.wowlua` | spec from C_Traits (thirds, far-off nodes, rank fields, secret ranks, ties, errors), current (chosen, assigned, secret, talents per class, no API), profile switching after the 0.5 s settle, hand-picked profile kept, forced checks, combat deferral, spec/role messages, the level-10 wait, listen with C_EventUtils |
| RolePresets | `RolePresets.test.wowlua` | names and layouts, exists (exact name only), apply (stored values, defaults dropped, re-apply, profile in use), refusals (combat, role), plugins' per-role values, a store failure |
| Serialize | `Serialize.test.wowlua` | base64 both ways (padding, whitespace, every byte, broken text), fletcher16 known values, the current strings round trip/trim/refusals, the real SUU1 string from `tests/compat/legacyString.wowlua`, every SUU1 parser branch and message (types, nesting depth 20, checksum, short, extra data) |
| Perf | `Perf.test.wowlua` | report (sorting, top 12 in chat, allocations, memory, the game's profiler share, a dev build's profiler/monitor), `/suu perf` start/report/stop, the memory sampler (rises, collections, gaps), restart after timing was turned off elsewhere |
| Tokens | `Tokens.test.wowlua` | shape only (generated): families and their order lists, colours in range matching their hex, the map marks, numbers, easings, shadows, text styles, usage notes, the vision presets slot |

## Coverage

Each source file measured with its own test file alone (`wowlua test
--coverage --reporter coverage-json unit/Core/<File>.test`):

| File | Lines | Branches | Conditions |
|---|---|---|---|
| API | 734/734 | 201/210 | 164/170 |
| Themes | 72/72 | 43/44 | 17/18 |
| ThemesBuiltin | 150/150 | 26/30 | 12/16 |
| Vision | 43/43 | 28/28 | 10/10 |
| VisionPresets | 48/48 | 0/0 | 0/0 |
| Fonts | 27/27 | 4/4 | 0/0 |
| Pixel | 33/33 | 10/10 | 8/8 |
| Root | 52/52 | 24/26 | 12/14 |
| Anchors | 11/11 | 2/2 | 0/0 |
| Blizzard | 52/52 | 47/48 | 30/30 |
| Motion | 100/100 | 37/38 | 15/16 |
| Roles | 94/94 | 93/100 | 77/82 |
| RolePresets | 70/70 | 30/30 | 12/12 |
| Serialize | 92/92 | 88/92 | 43/46 |
| Perf | 116/116 | 124/132 | 92/100 |
| Tokens | 361/361 | 0/0 | 0/0 |

After these runs two cases were added for the last reachable branches (API:
AddFriend with an unreadable legacy flag, line 777; Perf: a monitor with
events, line 127); both pass, coverage not measured again.

Every branch left is one no input can take:

- `a and b or c` where `b` is never falsy: `ok and t or {}`,
  `x and true or false`, `s == 0 and autoScale() or s`, `c and { … } or nil`,
  `startKB and (" (" .. …) or ""`, `mode ~= "normal" and mode or nil`,
  ThemesBuiltin's `c <= x and c / 12.92 or …` (a number is never falsy),
  Serialize's `(a or 0)` / `s:byte(i) or 0` / `b and B64:sub(…) or "="`'s
  middle, Roles' `secret.known(x, 0) or 0`, `LABEL[current()] or "?"`,
  Perf's `risenKB or 0` (always set while the sampler runs), API's
  `parent ~= 0 and parent or line`'s middle.
- Data that is always there in this build: `cooldownPresets or {}`,
  `trainerSpells or {}`, `trainerSpellIDs or {}` (API).
- `Blizzard.suppress`'s `if not hooked[frame]`: `suppressed[frame]` already
  stops a second pass, so `hooked` is never true there.
- `Roles.current`'s `roles and roles[tree]` with `roles` nil: the class is
  read once at load (`CLASS`); the test character's class has a tree-role
  table, so a class without one (a mage) isn't reachable in this VM run.

## Refactors

None of the code needed restructuring to be tested: the logic was already in
functions reachable through exports or `import internal`. Two type-only
changes (C15 pattern: `x: T?` is a required field, so callers couldn't leave
the field out):

- `Blizzard.SuppressOptions`: `{ children?: string[], keepParent?: boolean, noHide?: boolean }`
  (was `children: string[]?, …`). No run-time change; every caller passed a
  partial table or none.
- `Themes.ThemeFonts`: `{ [string]: { file?: string, size?: number, lineHeight?: number } }`.
  No run-time change.
- A pre-existing checker warning was cleaned in passing: `API.AddFriend`'s
  local `legacy` shadowed the `/UI/Legacy` import (W1004); renamed
  `legacyOn`, no run-time change.

## Bugs found (fixed)

1. **`SuuUI.UI.CooldownConditionMet` was missing.** Docs/API.md documents it
   (and the Cooldown Manager's `when` refers to it), but it was only in
   `SuuUI.Raw.UI` (the unported Lua had the same gap). Added to `API.UI`
   (an addition; nothing else changes). Test: `API.test` "every documented
   name is there".
2. **`SuuUI.OpenRecipe`'s fallback never used the recipe's parent skill
   line.** `local line, _, parent = C_TradeSkillUI and … and
   C_TradeSkillUI.GetTradeSkillLineForRecipe(id)` keeps only the call's first
   value (`a and f()` truncates), so `parent` was always nil and a recipe of
   a sub-line (Classic Cooking under Cooking) opened its own line instead of
   the profession. Now the call stands on its own line after an existence
   check (the same shape as Units/Professions and Units/ObjectiveTracker).
   Only reached while the professions module is off. Test: `API.test`
   "OpenRecipe without SuuUI's window opens the recipe's profession".

## VM suspicions

1. **`SetIgnoreParentScale(true)` has no effect.** `IsIgnoringParentScale()`
   stays false and the effective scale still multiplies the parent's. In
   the game SuuUIRoot ignores UIParent's scale (that is what the root is
   for). Repro (any test file):
   ```wowlua
   local outer = CreateFrame("Frame", nil, UIParent)
   outer:SetScale(2)
   local inner = CreateFrame("Frame", nil, outer)
   inner:SetIgnoreParentScale(true)
   expect(inner:IsIgnoringParentScale()).toBe(true)   -- false
   expect(inner:GetEffectiveScale()).toBe(1)          -- 2
   ```
   `Root.test` "the root ignores UIParent's scale" is `@skip` for it.
2. **`mock.fireEvent("GROUP_ROSTER_UPDATE")` from a test runs Blizzard's
   handlers tainted by SuuUI.** Blizzard's CompactUnitFrame then errors
   (`CompactUnitFrame.lua:1049: attempt to perform boolean test on local
   'checkedRange' (a secret boolean value, while execution tainted by
   'SuuUI')`). The client fires events untainted; a test's fireEvent
   seemingly carries the test file's (the addon's) taint into the dispatch.
   Repro: `mock.fireEvent("GROUP_ROSTER_UPDATE")` then `expectNoErrors()`
   in any test file. The Roles tests use TRAIT_CONFIG_UPDATED instead.

## wowlua test runner notes

- `wowlua test` takes one filter, so several files can't be named in one run.
- A test run needs the whole tree to compile: while other agents' files were
  mid-edit nothing ran. I tested in a mirror of the worktree (others' unit
  tests left out, the last compiling `src/` with my files on top); the final
  runs are in the worktree itself.
- `mock.advanceTime` runs timers but no frames: animation groups and
  `OnUpdate` scripts only move with `mock.advanceFrames`.
- A `wowlua:timer` `every(1)` tick due exactly at the end of
  `mock.advanceTime(1)` sometimes doesn't fire in that call, depending on
  the clock's value when the test starts (so on the tests before it in the
  file): `Perf.test`'s sampler tests passed alone and failed after another
  test. Floating-point accumulation in the virtual clock is the likely
  cause. The tests now advance 1.05 s per tick. Repro: in a file whose
  earlier tests advanced the clock by fractions, `every(1, fn)` then
  `mock.advanceTime(1)` twice: `fn` can run once.
- Client value fidelity seen (matches the game, noted for test writers):
  font sizes come back as floats (13 reads 12.999999), alpha in 1/255 steps.

## Not tested

- The `Roles` branch for a class without a tree-role table (see Coverage).

- `Pixel`'s and `Root`'s `@onLogin` bodies run at login, before any test; their
  effects are checked (the root's scale, the reporter hidden) but not the call.
- `Roles`' `SUUUI_SETTINGS_READY` registration runs at login; the events it
  registers are exercised, and `listen` is tested directly.
