# wowlua 0.9.1: findings from writing SuuUI's unit tests

A report for whoever works on wowlua next. It lists what writing and running
**unit tests** for SuuUI with `wowlua test` (`wowlua:test`, `wowlua:mock`,
the emulated client with `test.blizzard-ui`) turned up: emulator
differences from the game, test runner and mock issues, and compiler/checker
issues. Everything found while **porting** SuuUI is in
`Docs/wowlua-0.9.1-report.md` (C1–C40, S1–S23) and isn't repeated here,
except where noted.

## Context

- **Project:** github.com/DomenikIrrgang/suuui, branch `wowlua-tests` (local
  worktree `~/repositories/suuui.worktrees/wowlua-tests`), installed
  wowlua **0.9.1**, flavor `camelot`, strict mode for sources and tests.
- **Scale when this was written:** 7 of 19 test areas done (all of
  `src/Core`, five of seven UI groups): 75 unit test files under
  `tests/unit/` (one per source file), about 1,400 tests, every line of
  those 75 source files covered. The remaining areas (two UI groups, all feature modules) will
  add to this report.
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

| Id | Kind | Priority | Finding |
|----|------|----------|---------|
| [R1](#r1) | runner | high | A filtered `wowlua test` type-checks every test file: one broken test file blocks every run |
| [R2](#r2) | mock | high | `mock.fake` / `mock.stub` on `_G` leave the global tainted after restoring it |
| [R3](#r3) | mock | high | `mock.fireEvent` runs Blizzard's handlers tainted by the addon |
| [R4](#r4) | mock | high | `mock.click` sends only the up click (secure buttons that act on key down do nothing) |
| [R5](#r5) | runner | medium | `mock.errors()` (and anything kept per file) accumulates over the whole file |
| [R6](#r6) | mock | medium | No way to leave a group (`mock.group` has no remove; `LeaveParty` does nothing) |
| [R7](#r7) | runner | medium | Matchers error on secret values (`toHaveBeenCalledWith`, `rawequal`) |
| [R8](#r8) | runner | medium | `expect(nil).never.toBeShown()` fails with an internal error |
| [R9](#r9) | mock | medium | `every(1)` tick due exactly at the end of `mock.advanceTime(1)` sometimes skipped |
| [R10](#r10) | mock | low | `MockUnit:token()` returns a string, declared `string[]` |
| [R11](#r11) | mock | low | `mock.player:setName` fires no `UNIT_NAME_UPDATE` |
| [R12](#r12) | mock | low | `mock.stub` takes only a `table` (widgets and interface-typed objects need a cast) |
| [R13](#r13) | runner | low | `wowlua test` takes one filter only; `wowlua check` doesn't check test files |
| [K1](#k1) | checker | medium | `@cases` literals aren't typed by the test function's parameters (E8120) |
| [K2](#k2) | checker | low | W1003 "unused" for a local only read by tests through `import internal` |
| [K3](#k3) | checker | low | `local a, b: any, any = …` silently declares a third local named `any` |
| [V1](#v1) | VM | high | `OnSizeChanged` only runs for an explicit `SetSize`/`SetWidth`/`SetHeight` |
| [V2](#v2) | VM | high | `SetAlphaFromBoolean` does nothing |
| [V3](#v3) | VM | medium | `EditBox:SetText` doesn't run `OnTextChanged` |
| [V4](#v4) | VM | medium | `ScrollFrame:SetVerticalScroll` doesn't run `OnVerticalScroll` |
| [V5](#v5) | VM | medium | `SetIgnoreParentScale(true)` has no effect |
| [V6](#v6) | VM | medium | `Texture:GetAtlas()` keeps the old atlas after `SetTexture(file)` |
| [V7](#v7) | VM | medium | `ADDON_ACTION_BLOCKED` for `UNKNOWN()` out of combat when showing a Blizzard frame |
| [V8](#v8) | VM | low | `IsIgnoringParentAlpha()` stays false after `SetIgnoreParentAlpha(true)` |
| [V9](#v9) | VM | low | The width of secret text reads as a plain number |
| [V10](#v10) | VM | low | A frame never anchored lays its children out against the screen |
| [V11](#v11) | VM | low | *Unverified:* a Blizzard menu's submenu doesn't open on hover |

## Test runner and mock issues

<a id="r1"></a>

### R1. A filtered run type-checks every test file

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

Tests of one file share one VM, and `mock.errors()` (like an addon's own
error log) keeps every error since the file started, so one test's error
fails every later "no errors" check. Tests compare counts before and after
instead. A per-test view (or a `mock.clearErrors()`) would help.
(ui-units, ui-primitives)

<a id="r6"></a>

### R6. No way to leave a group

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

`expect(spy).toHaveBeenCalledWith(x, mock.secret(true))` errors inside the
matcher ("attempt to compare … a secret boolean value"); `rawequal` on a
secret is refused too. Matchers could compare secrets by identity (or offer
`toHaveBeenCalledWithSecret`). Tests check `issecretvalue` of what was handed
on instead. (ui-units)

<a id="r8"></a>

### R8. `expect(nil).never.toBeShown()` fails with an internal error

```wowlua
@test("x") local function x() local t: { Frame } = {}; expect(t[1]).never.toBeShown() end
-- wowlua/std/test.lua:586: attempt to index upvalue 'value' (a nil value)
```

Expected a matcher message (the value is not a frame). (ui-hud)

<a id="r9"></a>

### R9. A tick due exactly at the end of `mock.advanceTime` is sometimes skipped

A `wowlua:timer` `every(1)` tick due exactly at the end of
`mock.advanceTime(1)` sometimes doesn't fire in that call, depending on the
virtual clock's value when the test starts (so on the tests before it in the
file); the same test passes alone and fails after another one. Floating-point
accumulation in the virtual clock is the likely cause. Repro: in a file whose
earlier tests advanced the clock by fractions, `every(1, fn)` then
`mock.advanceTime(1)` twice: `fn` can run once. (core-b)

<a id="r10"></a>

### R10. `MockUnit:token()` returns a string

It returns e.g. `"raid2"`, but is declared `string[]`, so
`for _, t in ipairs(u:token())` errors. (ui-units)

<a id="r11"></a>

### R11. `mock.player:setName` fires no `UNIT_NAME_UPDATE`

The client fires it when a unit's name changes; the tests fire it
themselves. (ui-units)

<a id="r12"></a>

### R12. `mock.stub` takes only a `table`

Stubbing a method of a widget or of an interface-typed object needs a cast
(`mock.stub(b :: any, "SetText", …)`). Accepting any indexable value (or a
generic `T`) would keep strict tests cast-free. (ui-social)

<a id="r13"></a>

### R13. One filter per run; `wowlua check` skips test files

`wowlua test` takes a single filter, so several files can't be named in one
run. `wowlua check` doesn't type-check test files at all; only `wowlua test`
compiles them (`wowlua test <a filter matching nothing>` is the quickest
check). (core-b, ui-primitives)

## Compiler and checker issues

<a id="k1"></a>

### K1. `@cases` literals aren't typed by the test's parameters

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

A module-level local that only test files read (`import internal reset from
"/UI/WeaponEnchants"`) is reported unused: the checker doesn't count test
files' internal imports as reads. (ui-units)

<a id="k3"></a>

### K3. `local a, b: any, any = …` declares a third local named `any`

It declares three locals: `a`, `b` (typed `any`) and a third one named
`any`, with only the warning "unused local `any`". The intended form is
`local a: any, b: any = …`; the typo could be an error (a local named after
a type in an annotated declaration list). (ui-windows)

## Emulator (VM) suspicions

<a id="v1"></a>

### V1. `OnSizeChanged` only runs for an explicit `SetSize`/`SetWidth`/`SetHeight`

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

On frames and FontStrings the alpha stays as it was, for plain and secret
booleans. SuuUI relies on it in game (the cast bar's layers, "you" badges).

```wowlua
local f = CreateFrame("Frame"); f:SetAlphaFromBoolean(true, 0, 1)
expect(f:GetAlpha()).toBe(0)   -- emulator: 1
```

(ui-units, ui-hud)

<a id="v3"></a>

### V3. `EditBox:SetText` doesn't run `OnTextChanged`

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

```wowlua
local outer = CreateFrame("Frame", nil, UIParent); outer:SetScale(2)
local inner = CreateFrame("Frame", nil, outer); inner:SetIgnoreParentScale(true)
expect(inner:IsIgnoringParentScale()).toBe(true)   -- false
expect(inner:GetEffectiveScale()).toBe(1)          -- 2
```

SuuUI's screen root depends on it in game. (core-b)

<a id="v6"></a>

### V6. `Texture:GetAtlas()` keeps the old atlas after `SetTexture(file)`

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

Likely the generic Set/Is rule of mocked widget methods missing it (the names
differ).

```wowlua
local f = CreateFrame("Frame"); f:SetIgnoreParentAlpha(true)
print(f:IsIgnoringParentAlpha())   -- emulator: false; client: true
```

(ui-windows)

<a id="v9"></a>

### V9. The width of secret text reads as a plain number

`fs:SetText(mock.secret("Hidden")); issecretvalue(fs:GetUnboundedStringWidth())`
is false; in the game it is secret. (ui-units)

<a id="v10"></a>

### V10. A frame never anchored lays its children out against the screen

A `SetAllPoints()` child of an unplaced 200 px button reports 1920 wide; in
the game a frame without anchors has no rect, nor do its children. (ui-units)

<a id="v11"></a>

### V11. *Unverified:* a Blizzard menu's submenu doesn't open on hover

Neither `mock.hover(row)` nor `mock.script(row, "OnEnter")` with
`mock.advanceTime(0.5)` opened a submenu; `description:ForceOpenSubmenu()`
does. It may be the menu manager's mouse-event timer needing something the
mock doesn't send, so it isn't certain to be a gap. (ui-windows)

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
