# wowlua: findings from writing SuuUI's unit tests

A report for whoever works on wowlua next. It lists what writing and running
**unit tests** for SuuUI with `wowlua test` (`wowlua:test`, `wowlua:mock`,
the emulated client with `test.blizzard-ui`) turned up: emulator
differences from the game, test runner and mock issues, and compiler/checker
issues. Everything found while **porting** SuuUI is in
`Docs/wowlua-0.9.1-report.md` (C1–C40, S1–S23) and isn't repeated here,
except where noted.

Started on wowlua 0.9.1 after the first 7 areas and finished after all 21:
most of the first findings were fixed in 0.9.3 to 0.9.6, and later ones in
wowlua's branch `m9-coverage-stale-handle` (decisions T244 to T249, after
0.9.6). The triage gives each entry's status.

## Context

- **Project:** github.com/DomenikIrrgang/suuui, branch `wowlua-tests` (local
  worktree `~/repositories/suuui.worktrees/wowlua-tests`), installed
  wowlua **0.9.1**, flavor `camelot`, strict mode for sources and tests.
- **Scale:** the first 7 areas (all of `src/Core`, five of seven UI
  groups) gave 75 test files and about 1,400 tests when this report began;
  all 21 areas (every UI group and every feature module) are done now: 174
  test files under `tests/`.
- **Sources:** the per-area notes in `Docs/test-notes/*.md` (each finding
  there has its context and the workaround in SuuUI's tests). Every finding
  below was reproduced by the agent that reports it; several were met by
  more than one area independently.
- **Ground truth for "the game does X":** SuuUI's code comments record what
  was probed in the client; a few entries are marked *unverified* where
  neither a probe nor Blizzard's UI code settles it.

Already in the port report and met again here: **C40** (`--coverage`
panics with "stale handle"; SuuUI stops the GC in `tests/mocks/gc.wowlua`)
and **C39** (`runtime-checks = "all"`, the test profile's default, fails on
frames built step by step; SuuUI's test profile uses "exports").

## Triage

| Id | Kind | Priority | Status | Finding |
|----|------|----------|--------|---------|
| [R1](#r1) | runner | high | fixed 0.9.3, 0.9.4 | A filtered `wowlua test` type-checks every test file: one broken test file blocks every run |
| [R2](#r2) | mock | high | fixed 0.9.3 | `mock.fake` / `mock.stub` on `_G` leave the global tainted after restoring it |
| [R3](#r3) | mock | high | fixed (0.9.6: T239) | `mock.fireEvent` runs Blizzard's handlers tainted by the addon |
| [R4](#r4) | mock | high | fixed 0.9.3 | `mock.click` sends only the up click (secure buttons that act on key down do nothing) |
| [R5](#r5) | runner | medium | fixed 0.9.3 | `mock.errors()` (and anything kept per file) accumulates over the whole file |
| [R6](#r6) | mock | medium | fixed 0.9.3 | No way to leave a group (`mock.group` has no remove; `LeaveParty` does nothing) |
| [R7](#r7) | runner | medium | fixed 0.9.3 | Matchers error on secret values (`toHaveBeenCalledWith`, `rawequal`) |
| [R8](#r8) | runner | medium | fixed 0.9.3 | `expect(nil).never.toBeShown()` fails with an internal error |
| [R9](#r9) | mock | medium | fixed 0.9.3 | `every(1)` tick due exactly at the end of `mock.advanceTime(1)` sometimes skipped |
| [R10](#r10) | mock | low | fixed (`string?`) | `MockUnit:token()` returns a string, declared `string[]` |
| [R11](#r11) | mock | low | fixed 0.9.3 | `mock.player:setName` fires no `UNIT_NAME_UPDATE` |
| [R12](#r12) | mock | low | fixed 0.9.3 | `mock.stub` takes only a `table` (widgets and interface-typed objects need a cast) |
| [R13](#r13) | runner | low | fixed 0.9.3 | `wowlua test` takes one filter only; `wowlua check` doesn't check test files |
| [K1](#k1) | checker | medium | fixed 0.9.3 | `@cases` literals aren't typed by the test function's parameters (E8120) |
| [K2](#k2) | checker | low | fixed 0.9.3 | W1003 "unused" for a local only read by tests through `import internal` |
| [K3](#k3) | checker | low | fixed 0.9.3 (E2060) | `local a, b: any, any = …` silently declares a third local named `any` |
| [V1](#v1) | VM | high | fixed 0.9.3 | `OnSizeChanged` only runs for an explicit `SetSize`/`SetWidth`/`SetHeight` |
| [V2](#v2) | VM | high | fixed 0.9.3 | `SetAlphaFromBoolean` does nothing |
| [V3](#v3) | VM | medium | fixed (a frame later) | `EditBox:SetText` doesn't run `OnTextChanged` |
| [V4](#v4) | VM | medium | fixed 0.9.3 | `ScrollFrame:SetVerticalScroll` doesn't run `OnVerticalScroll` |
| [V5](#v5) | VM | medium | fixed 0.9.3 | `SetIgnoreParentScale(true)` has no effect |
| [V6](#v6) | VM | medium | fixed 0.9.3 | `Texture:GetAtlas()` keeps the old atlas after `SetTexture(file)` |
| [V7](#v7) | VM | medium | not a bug | `ADDON_ACTION_BLOCKED` for `UNKNOWN()` out of combat when showing a Blizzard frame |
| [V8](#v8) | VM | low | fixed 0.9.3 | `IsIgnoringParentAlpha()` stays false after `SetIgnoreParentAlpha(true)` |
| [V9](#v9) | VM | low | fixed 0.9.3 | The width of secret text reads as a plain number |
| [V10](#v10) | VM | low | open | A frame never anchored lays its children out against the screen |
| [V11](#v11) | VM | low | not a bug | *Unverified:* a Blizzard menu's submenu doesn't open on hover |
| [R14](#r14) | mock | medium | fixed after 0.9.6 (T264) | `mock.drag` runs no frame between `OnDragStart` and `OnDragStop` |
| [R15](#r15) | mock | low | fixed after 0.9.6 (T261) | No "any value" matcher for `toHaveBeenCalledWith` |
| [R16](#r16) | mock | low | open | Long event payloads have no defaults |
| [R17](#r17) | mock | medium | fixed 0.9.5 | `mock.defineItem(id, data)` without `opts` never loaded |
| [R18](#r18) | mock | high | fixed 0.9.5 (T228, T229) | A new `mock.defineAuctionHouse` kept the last house's state |
| [R19](#r19) | mock | high | fixed 0.9.6 (T230) | No way to change a Blizzard field without tainting it |
| [R20](#r20) | mock | medium | fixed 0.9.6 (T233) | `mock.slash` skipped Blizzard's own commands |
| [R21](#r21) | mock | low | fixed 0.9.6 | Mock declarations lacked fields and methods the engine has |
| [R22](#r22) | mock | medium | fixed after 0.9.6 (T246) | A test could not be listed in the group finder |
| [R23](#r23) | mock | low | fixed after 0.9.6 (T257) | `mock.hover` doesn't move the cursor |
| [K4](#k4) | checker | medium | done 0.9.6 (W2061) | `a and nil or b` is always `b` |
| [K5](#k5) | checker | medium | done after 0.9.6 (W2062, S40) | A value read past what a function gives |
| [K6](#k6) | checker | low | fixed after 0.9.6 (T259) | `GetCursorInfo` is declared without its results |
| [K7](#k7) | checker | low | fixed after 0.9.6 (T260) | The closing line of a multi-line `return f(...)` reads as not run |
| [V12](#v12) | VM | medium | fixed 0.9.4 | `IsModifiedClick("CHATLINK")` was always false |
| [V13](#v13) | VM | low | fixed after 0.9.6 (T257) | `IsMouseOver` ignores the cursor and its offsets |
| [V14](#v14) | VM | low | fixed after 0.9.6 (T263) | Chat windows' settings aren't kept |
| [V15](#v15) | VM | high | fixed after 0.9.6 (T244) | A hidden edit box kept the keyboard |
| [V16](#v16) | VM | medium | fixed after 0.9.6 (T256) | An item put onto a part stack of its kind isn't stacked |
| [V17](#v17) | VM | high | fixed 0.9.5 | The auction house: a stalled message queue, a shared item key table, no item level |
| [V18](#v18) | VM | medium | fixed 0.9.6 | Inspect, models, bindings and journals |
| [V19](#v19) | VM | high | fixed 0.9.6 (T237, T238) | UIParent's scale was 1; unknown atlases were 0 by 0 |
| [V20](#v20) | VM | high | fixed 0.9.6 (T239, T240) | A test's payload table tainted Blizzard's handlers; talents never opened |
| [V21](#v21) | VM | medium | fixed after 0.9.6 (T266) | A frame whose top is below its bottom has a negative height |
| [V22](#v22) | VM | medium | fixed 0.9.6 (T241, T242) | A test's group was an instance group; `UnitFullName("player")` had no realm |
| [V23](#v23) | VM | low | open (probe) | Moving a raid member tells the roster at once |
| [V24](#v24) | VM | low | open | No inspected talent groups |
| [V25](#v25) | VM | high | fixed 0.9.6 (T243) | An addon's `SecureHandlerClickTemplate` never ran `_onclick` |
| [V26](#v26) | VM | high | fixed after 0.9.6 (T245) | Addons' tooltips were empty in combat |
| [V27](#v27) | VM | high | fixed after 0.9.6 (T247) | Only the player could be on a threat list |
| [V28](#v28) | VM | medium | fixed after 0.9.6 (T248) | A spell learned from a trainer stayed unknown |
| [V29](#v29) | VM | low | fixed after 0.9.6 (T249) | A member logging out sent no `UNIT_CONNECTION` |
| [V30](#v30) | VM | low | open | A unit can't turn hostile (a duel) |
| [V31](#v31) | VM | low | open | No combo points |
| [V32](#v32) | VM | medium | fixed after 0.9.6 (T255) | An addon's encounter timeline event on Forever |
| [V33](#v33) | VM | high | fixed after 0.9.6 (T251) | A secret alpha read back plain |
| [V34](#v34) | VM | high | fixed after 0.9.6 (T252) | A protected frame could anchor to a region |
| [V35](#v35) | VM | high | fixed after 0.9.6 (T253) | An addon could pick up a spellbook spell in combat |
| [V36](#v36) | VM | high | fixed after 0.9.6 (T254) | A frame holding a protected frame wasn't protected |
| [V37](#v37) | VM | medium | fixed after 0.9.6 (T258) | `ClearPoint` did nothing |

## Test runner and mock issues

<a id="r1"></a>

### R1. A filtered run type-checks every test file

*Status: fixed 0.9.3, 0.9.4.*

`wowlua test unit/Core/Util` aborts ("aborting due to N previous errors",
0 files run) when **any** other test file has a type error. With several
people (or agents) writing tests at once, one half-written file blocks
everyone; the agents worked around it with private mirror copies of the tree.

```
tests/a.test.wowlua:  local x: number = "s"        -- a type error
tests/b.test.wowlua:  a passing test
$ wowlua test b       -- runs nothing: aborts on a.test.wowlua
```

Suggestion: compile only the selected test files (plus `tests/mocks/` and
the helpers they import), or report the broken file and run the rest.
(core-a, ui-hud, ui-primitives, ui-social)

<a id="r2"></a>

### R2. `mock.fake` leaves the global tainted after restoring it

*Status: fixed 0.9.3.*

The restore writes the original back from the test's (addon) code, so the
global stays tainted. Blizzard's code that reads it later runs tainted and
errors on secret values, e.g. `UnitFrame.lua:814: attempt to compare local
'maxValue' (a secret number value, while execution tainted by 'SuuUI')`, or
in TextStatusBar after a fake of `GetBindingKey`.

```wowlua
@test("a") local function a() mock.fake("GetNumGroupMembers", function(): number return 3 end) end
@test("b") local function b() expect("GetNumGroupMembers").toBeSecure() end  -- fails: tainted
```

Suggestion: restore with the engine's secure write (as the original was set),
so `issecurevariable` holds again. SuuUI's tests switched to stand-in APIs
passed as parameters because of this. (ui-units, ui-windows)

<a id="r3"></a>

### R3. `mock.fireEvent` runs Blizzard's handlers tainted by the addon

*Status: fixed (0.9.6: T239).*

`mock.fireEvent("GROUP_ROSTER_UPDATE")` from a test makes Blizzard's
CompactUnitFrame error: `CompactUnitFrame.lua:1049: attempt to perform
boolean test on local 'checkedRange' (a secret boolean value, while execution
tainted by 'SuuUI')`. The client delivers events untainted; the test file's
taint seems to carry into the dispatch.

```wowlua
mock.fireEvent("GROUP_ROSTER_UPDATE")
expectNoErrors()   -- fails with the CompactUnitFrame error
```

Suggestion: dispatch events from a secure context, as the engine does.
(core-b, ui-hud)

<a id="r4"></a>

### R4. `mock.click` sends only the up click

*Status: fixed 0.9.3.*

`mock.click(b)` calls `OnClick(button, down = false)`. In the client a
mouse click on a button registered for `AnyDown` and `AnyUp` gets OnClick
twice (down, then up); a `SecureActionButtonTemplate` button with the
`ActionButtonUseKeyDown` CVar on (this client's default) acts on the down
click. So `mock.click` does nothing on such buttons, where a real click acts.

```wowlua
local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
b:RegisterForClicks("AnyDown", "AnyUp")
b:SetAttribute("type", "click"); b:SetAttribute("clickbutton", CharacterMicroButton)
b:SetSize(20, 20); b:SetPoint("CENTER"); b:Show()
mock.click(b)                                    -- CharacterFrame stays hidden
mock.script(b, "OnClick", "LeftButton", true)    -- CharacterFrame shows
```

Suggestion: send down and up for the registered clicks, in the client's
order. (ui-windows)

<a id="r5"></a>

### R5. `mock.errors()` accumulates over the whole file

*Status: fixed 0.9.3.*

Tests of one file share one VM, and `mock.errors()` (like an addon's own
error log) keeps every error since the file started, so one test's error
fails every later "no errors" check. Tests compare counts before and after
instead. A per-test view (or a `mock.clearErrors()`) would help.
(ui-units, ui-primitives)

<a id="r6"></a>

### R6. No way to leave a group

*Status: fixed 0.9.3.*

There's `mock.group:add`, no remove, and `C_PartyInfo.LeaveParty()` changes
nothing, so a test that groups up leaves the rest of its file grouped.

```wowlua
mock.group:add(mock.spawnUnit({ name = "F", player = true }))
C_PartyInfo.LeaveParty(); mock.advanceTime(1)
expect(IsInGroup()).toBe(false)   -- fails: true
```

(ui-hud)

<a id="r7"></a>

### R7. Matchers error on secret values

*Status: fixed 0.9.3.*

`expect(spy).toHaveBeenCalledWith(x, mock.secret(true))` errors inside the
matcher ("attempt to compare … a secret boolean value"); `rawequal` on a
secret is refused too. Matchers could compare secrets by identity (or offer
`toHaveBeenCalledWithSecret`). Tests check `issecretvalue` of what was handed
on instead. (ui-units)

<a id="r8"></a>

### R8. `expect(nil).never.toBeShown()` fails with an internal error

*Status: fixed 0.9.3.*

```wowlua
@test("x") local function x() local t: { Frame } = {}; expect(t[1]).never.toBeShown() end
-- wowlua/std/test.lua:586: attempt to index upvalue 'value' (a nil value)
```

Expected a matcher message (the value is not a frame). (ui-hud)

<a id="r9"></a>

### R9. A tick due exactly at the end of `mock.advanceTime` is sometimes skipped

*Status: fixed 0.9.3.*

A `wowlua:timer` `every(1)` tick due exactly at the end of
`mock.advanceTime(1)` sometimes doesn't fire in that call, depending on the
virtual clock's value when the test starts (so on the tests before it in the
file); the same test passes alone and fails after another one. Floating-point
accumulation in the virtual clock is the likely cause. Repro: in a file whose
earlier tests advanced the clock by fractions, `every(1, fn)` then
`mock.advanceTime(1)` twice: `fn` can run once. (core-b)

<a id="r10"></a>

### R10. `MockUnit:token()` returns a string

*Status: fixed (`string?`).*

It returns e.g. `"raid2"`, but is declared `string[]`, so
`for _, t in ipairs(u:token())` errors. (ui-units)

<a id="r11"></a>

### R11. `mock.player:setName` fires no `UNIT_NAME_UPDATE`

*Status: fixed 0.9.3.*

The client fires it when a unit's name changes; the tests fire it
themselves. (ui-units)

<a id="r12"></a>

### R12. `mock.stub` takes only a `table`

*Status: fixed 0.9.3.*

Stubbing a method of a widget or of an interface-typed object needs a cast
(`mock.stub(b :: any, "SetText", …)`). Accepting any indexable value (or a
generic `T`) would keep strict tests cast-free. (ui-social)

<a id="r13"></a>

### R13. One filter per run; `wowlua check` skips test files

*Status: fixed 0.9.3.*

`wowlua test` takes a single filter, so several files can't be named in one
run. `wowlua check` doesn't type-check test files at all; only `wowlua test`
compiles them (`wowlua test <a filter matching nothing>` is the quickest
check). (core-b, ui-primitives)

<a id="r14"></a>

### R14. `mock.drag` runs no frame between `OnDragStart` and `OnDragStop`

*Status: fixed after 0.9.6 (T264): `mock.drag(frame, dx, dy, frames)` moves in steps with a frame after each, the cursor following. Edit Mode's tests still run the scripts by hand where they check the frame mid-drag.*

An `OnUpdate` set while dragging (edit mode's frames following the outline) never runs. Tests call the two scripts themselves and advance a frame between them; a drag over `n` frames would make it one call. (ui-settings)

<a id="r15"></a>

### R15. No "any value" matcher for `toHaveBeenCalledWith`

*Status: fixed after 0.9.6 (T261): `anything` and `ofType(kind)` from `wowlua:test`, in `toEqual` and `toHaveBeenCalledWith`.*

A call whose one argument is a fresh table or a frame can't be matched without checking each argument by hand. (units-character)

<a id="r16"></a>

### R16. Long event payloads have no defaults

*Status: open.*

`mock.fireEvent` checks a payload in full (right), so `CHAT_MSG_*` (18 values with Discord's info), `PLAYER_LEVEL_UP` (ten deltas), `CHAT_MSG_ADDON` and `START_PLAYER_COUNTDOWN` need every value written out. Defaults for trailing values, or helpers such as `mock.chatMessage(event, text, sender)`, would help. (units-chat, units-bags, units-hud)

<a id="r17"></a>

### R17. `mock.defineItem(id, data)` without `opts` never loaded

*Status: fixed 0.9.5.*

`GetItemInfo` answered nothing; it is cached by default now, as documented. (units-bags)

<a id="r18"></a>

### R18. A new `mock.defineAuctionHouse` kept the last house's state

*Status: fixed 0.9.5 (T228, T229).*

Purchases, browse results and the player's auctions stayed while auction IDs started again, so two auctions shared an ID. (units-trade)

<a id="r19"></a>

### R19. No way to change a Blizzard field without tainting it

*Status: fixed 0.9.6 (T230).*

An assignment from a test leaves Blizzard's field tainted for the rest of the file. `mock.setField(t, key, value)` sets one until the test ends and puts it back secure. (units-character)

<a id="r20"></a>

### R20. `mock.slash` skipped Blizzard's own commands

*Status: fixed 0.9.6 (T233).*

`/inspect` did nothing, silently; with Blizzard's chat loaded the line is typed and sent as the player does. (units-character)

<a id="r21"></a>

### R21. Mock declarations lacked fields and methods the engine has

*Status: fixed 0.9.6.*

`MockUnit` lacked `joinGroup`, `openTrade`, `setInspect` (T232), `HeldItem` its `durability` and `maxDurability`, so strict tests needed casts. (units-chat, units-character, units-notices)

<a id="r22"></a>

### R22. A test could not be listed in the group finder

*Status: fixed after 0.9.6 (T246).*

An addon's `CreateListing` is blocked, and stubbing `C_LFGList.HasActiveEntryInfo` ran Blizzard's listing panel on a listing that wasn't there. `mock.postLFGListing(createData)` and `mock.delistLFG()` do it as the game's panel does. (units-windows)

<a id="r23"></a>

### R23. `mock.hover` doesn't move the cursor

*Status: fixed after 0.9.6 (T257): `mock.hover` and `mock.click` put the cursor on the frame's middle (unless it is over it already); `mock.hover(nil)` takes it off every frame.*

Code that reads the cursor over a hovered frame (`GetNormalizedCursorPosition`, the world map's coordinates) needs `mock.setCursorPosition` too; `IsMouseOver` follows the hover alone (see V13). (units-windows)

## Compiler and checker issues

<a id="k1"></a>

### K1. `@cases` literals aren't typed by the test's parameters

*Status: fixed 0.9.3.*

A case's table is inferred on its own, so a string literal field is
`string`, and a parameter whose type has a literal union rejects it (E8120).
The same literal passed to an ordinary function taking `D` checks.

```wowlua
type D = { state: "idle" | "results" }
@test("x") @cases({ { { state = "idle" } } })
local function x(d: D) end
-- E8120: `{ state: string }` is not assignable to `{ state: "idle" | "results" }`
```

(ui-social)

<a id="k2"></a>

### K2. W1003 for a local only read through `import internal`

*Status: fixed 0.9.3.*

A module-level local that only test files read (`import internal reset from
"/UI/WeaponEnchants"`) is reported unused: the checker doesn't count test
files' internal imports as reads. (ui-units)

<a id="k3"></a>

### K3. `local a, b: any, any = …` declares a third local named `any`

*Status: fixed 0.9.3 (E2060).*

It declares three locals: `a`, `b` (typed `any`) and a third one named
`any`, with only the warning "unused local `any`". The intended form is
`local a: any, b: any = …`; the typo could be an error (a local named after
a type in an annotated declaration list). (ui-windows)

<a id="k4"></a>

### K4. `a and nil or b` is always `b`

*Status: done 0.9.6 (W2061).*

A new warning; it found two SuuUI bugs and one in wowlua's dev console. (units-maps)

<a id="k5"></a>

### K5. A value read past what a function gives

*Status: done after 0.9.6 (W2062, S40).*

Reading the 9th value of a `pcall` helper that returns 8 type-checked (`...any`) and was always nil (Raid Info's details, the junk's sell price). W2062 counts a local function's returns; global, cross-file and API functions are not covered yet. (units-social)

<a id="k6"></a>

### K6. `GetCursorInfo` is declared without its results

*Status: fixed after 0.9.6 (T259): declared `(string?, ...any)` on every flavor; the spellbook test reads it plainly.*

In every flavor's declarations; a strict test reads it through `any`. (units-talents)

<a id="k7"></a>

### K7. The closing line of a multi-line `return f(...)` reads as not run

*Status: fixed after 0.9.6 (T260): coverage leaves the dead return out; Chat's ignore comment is gone.*

The return after the tail call never runs and is counted on its last line when that line holds only `})`. (units-chat)

## Emulator (VM) suspicions

<a id="v1"></a>

### V1. `OnSizeChanged` only runs for an explicit `SetSize`/`SetWidth`/`SetHeight`

*Status: fixed 0.9.3.*

The client runs it whenever the frame's rect changes size, including a size
that follows its anchors (a `SetAllPoints` child of a resized frame, a
template's anchored part such as ColoredProgressBarTemplate's FillArea).

```wowlua
local holder = CreateFrame("Frame", nil, UIParent); holder:SetPoint("TOPLEFT"); holder:SetSize(100, 100)
local inner = CreateFrame("Frame", nil, holder)
local sizes: number[] = {}
inner:SetScript("OnSizeChanged", function(_f: Frame, w: number) sizes[#sizes + 1] = w end)
inner:SetAllPoints(); mock.advanceFrames(1)
holder:SetWidth(150); mock.advanceFrames(1)
expect(sizes).toEqual({ 100, 150 })   -- {} in the emulator
```

(ui-primitives, ui-social, ui-windows)

<a id="v2"></a>

### V2. `SetAlphaFromBoolean` does nothing

*Status: fixed 0.9.3.*

On frames and FontStrings the alpha stays as it was, for plain and secret
booleans. SuuUI relies on it in game (the cast bar's layers, "you" badges).

```wowlua
local f = CreateFrame("Frame"); f:SetAlphaFromBoolean(true, 0, 1)
expect(f:GetAlpha()).toBe(0)   -- emulator: 1
```

(ui-units, ui-hud)

<a id="v3"></a>

### V3. `EditBox:SetText` doesn't run `OnTextChanged`

*Status: fixed (a frame later).*

The client runs it with `userInput` false.

```wowlua
local e = CreateFrame("EditBox", nil, UIParent); e:SetSize(100, 20); e:SetAutoFocus(false)
local seen: any[] = {}
e:SetScript("OnTextChanged", function(_e: EditBox, userInput: boolean) seen[#seen + 1] = userInput end)
e:SetText("abc")
expect(seen).toEqual({ false })   -- {} in the emulator
```

(ui-primitives, ui-social)

<a id="v4"></a>

### V4. `ScrollFrame:SetVerticalScroll` doesn't run `OnVerticalScroll`

*Status: fixed 0.9.3.*

In the client it does (Blizzard's scroll templates rely on it).

```wowlua
local s = CreateFrame("ScrollFrame", nil, UIParent); s:SetSize(200, 100)
local c = CreateFrame("Frame", nil, s); c:SetSize(200, 400); s:SetScrollChild(c)
local runs = 0
s:HookScript("OnVerticalScroll", function() runs += 1 end)
s:SetVerticalScroll(50); mock.advanceFrames(1)
expect(runs).toBe(1)   -- 0 in the emulator
```

(ui-primitives)

<a id="v5"></a>

### V5. `SetIgnoreParentScale(true)` has no effect

*Status: fixed 0.9.3.*

```wowlua
local outer = CreateFrame("Frame", nil, UIParent); outer:SetScale(2)
local inner = CreateFrame("Frame", nil, outer); inner:SetIgnoreParentScale(true)
expect(inner:IsIgnoringParentScale()).toBe(true)   -- false
expect(inner:GetEffectiveScale()).toBe(1)          -- 2
```

SuuUI's screen root depends on it in game. (core-b)

<a id="v6"></a>

### V6. `Texture:GetAtlas()` keeps the old atlas after `SetTexture(file)`

*Status: fixed 0.9.3.*

In the client, setting a file clears the atlas; `Button:SetNormalTexture(file)`
after `SetNormalAtlas` behaves the same way in the emulator.

```wowlua
local t = CreateFrame("Frame"):CreateTexture()
t:SetAtlas("ui-hud-minus")
t:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
print(t:GetAtlas())   -- emulator: "ui-hud-minus"; client: nil
```

(ui-windows)

<a id="v7"></a>

### V7. `ADDON_ACTION_BLOCKED` for `UNKNOWN()` when showing a Blizzard frame out of combat

*Status: not a bug.* The refused call is SuuUI's own: the group finder's
`OnShow` hook searches (`foreverlfg`'s `Refresh`, `C_LFGList.Search`
through `pcall`), and the game lets an addon search only from the user's
click, key press or slash command; through `pcall` the event names
`UNKNOWN()`. Both are recorded in wowlua (`lfg.rs`). A test's plain
`Show()` has no click behind it; `mock.script`, a key press or a click
does. SuuUI's Fault log said "Blocked in combat" for every blocked call;
it says "Blocked" out of combat now.

Showing the group finder's parent frame from a test, out of combat, makes the
emulator fire `ADDON_ACTION_BLOCKED` naming `UNKNOWN()`. In the game an
insecure `Show()` is refused only in combat, and the event names the
function. Which call inside the frame's OnShow is refused is not
established.

```wowlua
mock.loadAddon("Blizzard_GroupFinder_VanillaStyle")
;(_G :: any).LFGParentFrame:Show()
-- SuuUI logs "Taint: Blocked in combat: UNKNOWN()" (it listens for ADDON_ACTION_BLOCKED)
```

(ui-social)

<a id="v8"></a>

### V8. `IsIgnoringParentAlpha()` stays false after `SetIgnoreParentAlpha(true)`

*Status: fixed 0.9.3.*

Likely the generic Set/Is rule of mocked widget methods missing it (the names
differ).

```wowlua
local f = CreateFrame("Frame"); f:SetIgnoreParentAlpha(true)
print(f:IsIgnoringParentAlpha())   -- emulator: false; client: true
```

(ui-windows)

<a id="v9"></a>

### V9. The width of secret text reads as a plain number

*Status: fixed 0.9.3.*

`fs:SetText(mock.secret("Hidden")); issecretvalue(fs:GetUnboundedStringWidth())`
is false; in the game it is secret. (ui-units)

<a id="v10"></a>

### V10. A frame never anchored lays its children out against the screen

*Status: open.*

A `SetAllPoints()` child of an unplaced 200 px button reports 1920 wide; in
the game a frame without anchors has no rect, nor do its children. (ui-units)

<a id="v11"></a>

### V11. *Unverified:* a Blizzard menu's submenu doesn't open on hover

*Status: not a bug.* The menu's hover timer is an `OnUpdate`, and
`mock.advanceTime` runs no frames: `mock.hover(row)` then
`mock.advanceFrames(30)` opens it (with `IsMouseOver` measuring the
cursor since T257). Reskin's test opens it that way now.

Neither `mock.hover(row)` nor `mock.script(row, "OnEnter")` with
`mock.advanceTime(0.5)` opened a submenu; `description:ForceOpenSubmenu()`
does. It may be the menu manager's mouse-event timer needing something the
mock doesn't send, so it isn't certain to be a gap. (ui-windows)

<a id="v12"></a>

### V12. `IsModifiedClick("CHATLINK")` was always false

*Status: fixed 0.9.4.*

Blizzard's default `SHIFT-BUTTON1` took `BUTTON1` for a key never held. (ui-world)

<a id="v13"></a>

### V13. `IsMouseOver` ignores the cursor and its offsets

*Status: fixed after 0.9.6 (T257): measured against the frame's rectangle and offsets. Three tests leaned on the old answer: two hovered frames that were never placed (the game can't put the mouse over those), and the map's status line read a reading left from the test before.*

The engine answers whether the hovered frame is the frame or a child; the client measures the cursor against the frame grown by the offsets (`tabs:IsMouseOver(12, -12, -24, 24)`). (units-chat)

<a id="v14"></a>

### V14. Chat windows' settings aren't kept

*Status: fixed after 0.9.6 (T263): the setters keep their values and `GetChatWindowInfo` answers them; the chat test's fake is gone.*

`SetChatWindowName`, `SetChatWindowSize` and the other `SetChatWindow*` are no-ops; `GetChatWindowInfo` keeps the recording. (units-chat)

<a id="v15"></a>

### V15. A hidden edit box kept the keyboard

*Status: fixed after 0.9.6 (T244).*

Later keys in a test went into it (a closed dialog's box swallowed `J`). The focus is dropped with `OnEditFocusLost` now. (units-chat, units-social)

<a id="v16"></a>

### V16. An item put onto a part stack of its kind isn't stacked

*Status: fixed after 0.9.6 (T256).*

The engine kept it on the cursor ("unverified, nothing"); the client stacks it (SuuUI's probe), and SuuUI's bag sort counts on it. It stacks now, in the order the probe recorded; a split part and what doesn't fit are modelled unverified (a probe is noted in wowlua). (units-bags)

<a id="v17"></a>

### V17. The auction house: a stalled message queue, a shared item key table, no item level

*Status: fixed 0.9.5.*

An answer with another message queued sent neither; `GetItemKeyFromItem` returned the data's own table; `C_Item.GetCurrentItemLevel` was nil for an item without `itemLevel`. (units-trade)

<a id="v18"></a>

### V18. Inspect, models, bindings and journals

*Status: fixed 0.9.6.*

An inspected player's gear had only its link (T231); `GetText` was missing; a model's `GetItemTransmogInfoList()` was empty; a key bound with `SetOverrideBindingClick` clicked twice (T234); the journals had no collections (T235). (units-character)

<a id="v19"></a>

### V19. UIParent's scale was 1; unknown atlases were 0 by 0

*Status: fixed 0.9.6 (T237, T238).*

Text under SuuUI's root measured too wide (the game's UIParent is 0.71 at 1920 by 1080); Blizzard's quest log divided by an unknown atlas's size. `C_QuestLog.GetQuestsOnMap` listed the recording's quests. (units-maps)

<a id="v20"></a>

### V20. A test's payload table tainted Blizzard's handlers; talents never opened

*Status: fixed 0.9.6 (T239, T240).*

`mock.fireUnitEvent("UNIT_AURA", "player", { isFullUpdate = true })` carried the test's taint; `CanPlayerUseTalentUI()` ignored the level. (units-talents)

<a id="v21"></a>

### V21. A frame whose top is below its bottom has a negative height

*Status: fixed after 0.9.6 (T266): probed in game (size 0, at the LEFT and BOTTOM points); the Legacy test no longer avoids reopening on the challenges.*

Blizzard's Legacy challenge list then asks for rows 8 to 6 and errors; the game's answer is unrecorded. (units-talents)

<a id="v22"></a>

### V22. A test's group was an instance group; `UnitFullName("player")` had no realm

*Status: fixed 0.9.6 (T241, T242).*

(units-group)

<a id="v23"></a>

### V23. Moving a raid member tells the roster at once

*Status: open (probe).*

The game told `GROUP_ROSTER_UPDATE` 0.4 to 0.7 s later (SuuUI's probe). (units-group)

<a id="v24"></a>

### V24. No inspected talent groups

*Status: open.*

An inspect gives the spec ID but not its talent groups' points (`C_Traits.GetGroupCurrencyInfo`). (units-group)

<a id="v25"></a>

### V25. An addon's `SecureHandlerClickTemplate` never ran `_onclick`

*Status: fixed 0.9.6 (T243).*

Blizzard's inline template handler carried the addon's taint and refused the frame. (units-notices)

<a id="v26"></a>

### V26. Addons' tooltips were empty in combat

*Status: fixed after 0.9.6 (T245).*

`C_RestrictedActions.CheckAllowProtectedFunctions` refused every addon in combat whatever the object; Blizzard's tooltip setters check it first. It refuses only on a protected object now. (units-windows)

<a id="v27"></a>

### V27. Only the player could be on a threat list

*Status: fixed after 0.9.6 (T247).*

Group threat had to be faked through the globals, which runs Blizzard's unit frames tainted. `mob:setThreat(value, who)` puts a member or pet on the list; statuses and percentages follow. (units-group, units-hud)

<a id="v28"></a>

### V28. A spell learned from a trainer stayed unknown

*Status: fixed after 0.9.6 (T248).*

`IsPlayerSpell` and `C_SpellBook.IsSpellKnown` say so now. (units-hud)

<a id="v29"></a>

### V29. A member logging out sent no `UNIT_CONNECTION`

*Status: fixed after 0.9.6 (T249).*

Only the roster update came; the event's order is unverified (a probe is noted). (units-hud)

<a id="v30"></a>

### V30. A unit can't turn hostile (a duel)

*Status: open.*

Nameplates' recheck stubs `UnitCanAttack`. A `unit:setReaction` with `UNIT_FACTION` would need a probe of the order. (units-windows)

<a id="v31"></a>

### V31. No combo points

*Status: open.*

`GetComboPoints` is always 0 (recorded so, out of combat); a rogue's points can't be given. (units-hud)

<a id="v32"></a>

### V32. An addon's encounter timeline event on Forever

*Status: fixed after 0.9.6 (T255).*

Forever's own timeline is off (`IsFeatureAvailable()` false, recorded), but SuuUI's pull countdown shows on it in game (seen by the user). The engine keeps an addon's script events now: added, paused, resumed, run out or cancelled, each told by the timeline's events. Timeline's test runs on them instead of a stand-in. (units-hud)

<a id="v33"></a>

### V33. A secret alpha read back plain

*Status: fixed after 0.9.6 (T251).*

Once a frame's alpha is set from a secret (UnitFrames' resting alpha through a health curve), the game answers its alpha secret from then on; the engine forgot it, so Motion's fade from it did arithmetic in tests but errored in game. Motion snaps from a secret alpha now, and Reskin leaves one alone. (units-hud, found in game)

<a id="v34"></a>

### V34. A protected frame could anchor to a region

*Status: fixed after 0.9.6 (T252).*

The game errors "Cannot anchor protected frames to regions" at login; the engine let the spellbook's secure overlays anchor to textures. They anchor to a pager frame now. (units-windows, found in game)

<a id="v35"></a>

### V35. An addon could pick up a spellbook spell in combat

*Status: fixed after 0.9.6 (T253).*

`PickupSpellBookItem` is blocked for addons in combat. The spellbook's icons drag through `SecureHandlerDragTemplate` now, as the game allows. (units-windows, found in game)

<a id="v36"></a>

### V36. A frame holding a protected frame wasn't protected

*Status: fixed after 0.9.6 (T254).*

A parent of a protected frame is protected too: a secure handle to it works in combat, and its own `Show`, `SetShown` and moves are refused there. The engine let Collections show and lay out its tabs in combat, which the game refuses; they wait for combat's end now. (units-windows)

<a id="v37"></a>

### V37. `ClearPoint` did nothing

*Status: fixed after 0.9.6 (T258).*

`Region:ClearPoint(point)` wasn't modelled, so Blizzard's dropdown menus that open upward near the screen's bottom (they flip one point) kept both points and came out upside down. Found by wowlua's own settings test once `IsMouseOver` measured the menu (V13).

## Not bugs (for test writers)

These match the game; the tests follow them:

- Colours and alphas are stored at 8 bits a channel (`SetAlpha(0.5)` reads
  back 128/255); sizes and points carry float noise (font size 13 reads
  12.999999). Compare with `toBeCloseTo`.
- `GetTexCoord` returns the four corners (8 values).
- `OnSizeChanged` after an explicit `SetWidth` arrives with the next frame.
- `mock.advanceTime` runs timers but no frames: animation groups and
  `OnUpdate` scripts only move with `mock.advanceFrames`.
- Secure paging through `RegisterStateDriver` and `_childupdate-page` works
  as in the game.
- A stubbed or faked global runs Blizzard's code that calls it tainted, as
  an addon's replacement does in the game: prefer the engine's own state
  (`mob:setThreat`, `mock.setPet`), a module's own API table, or stand-in
  tables the module reads from.
- The first Esc in a test skips SuuUI's welcome, as at a first login.
- `mock.click` leaves the pointer on the frame: `mock.hover(nil)` before
  hovering it again.
- A zero-delay timer set while `mock.advanceTime` runs comes due just after
  that advance; `GetScript` gives a script without its `HookScript` hooks;
  the emulated clock starts at midnight on 1 January.
- Forever's spells window has no tab row (`IsTabSystemAvailable` is false
  on Camelot), and your own health is secret to addons (`UnitHealth`).
- A party forms a moment after the invite: wait before `joinGroup` and
  before `C_PartyInfo.ConvertToRaid`.
