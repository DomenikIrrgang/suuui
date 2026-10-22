# Test notes: ui-primitives

Area: SuuUI's components in `src/UI/` that everything else (and plugins,
through `SuuUI.UI`) is built from: Draw, Text, Icon, Bar, Panel, Layout,
Controls, Inputs, Select, Pickers, SettingRow, SettingsMatrix, TabMarker,
Crest, LoadingMark, Stage, Visibility. One test file per source file in
`tests/unit/UI/<File>.test.wowlua`, plus a shared helper,
`tests/unit/UI/PrimitivesHelpers.wowlua` (the paint Draw keeps for a region,
colour comparisons within 1/255, changing and restoring colour tokens, a
region's points as tables, the theme message, reduced motion on/off).

Each component is built in `newParent()`, driven through its builder, its
methods and the user's input (`mock.click`, `mock.hover`, `mock.typeText`,
`mock.pressKey`, `mock.slide`, `mock.wheel`, `mock.script` for scripts the
mock has no gesture for), and checked through what it shows (widget
matchers, the token Draw keeps for each region) and its callbacks (spies).
Tooltips are replaced with spies (`mock.module` on `/UI/Tooltip`) where a
component shows one, so the tests check what it asks the tooltip to say.

## Test files

| Source | Test file | Tests |
|---|---|---|
| Draw | `Draw.test.wowlua` | rgba (alpha, unknown token), size (px, size and space tokens, unknown), paint's kinds (text, EditBox, bar, vertex), repaint following a token change, letting go per setter (SetTextColor, SetVertexColor, SetStatusBarColor, SetTexture, SetAtlas, SetColorTexture), paintFill, paintGradient (both ends, repaint), bind (now, each repaint, painting inside it isn't a let-go, an erroring fn), a failing paint keeps nothing, repaint isolating a failure (error handler faked) and walking a copy, fill, border (layout in physical pixels, width/inset/layer, SetColor by token, table, r,g,b,a, SetShown), SUUUI_ROOT_SCALED relayout of borders and hairlines, hairlines (solid, out, both), diamond, softEdge (nine-slice, level, blur and offset, colours incl. a kept table), shadow (layer, offset, unknown and inset-only tokens), cross |
| Text | `Text.test.wowlua` | defaults, style/colour/layer, SetStyle, SetColor (token or raw), SetValue (only on change, numbers, secrets never compared), SetShadowed, SetFixedWidth, SetVisible, Changed without a layout, flag (cases, secret), measureText, the theme change invalidating layouts |
| Icon | `Icon.test.wowlua` | build (size, well, cropped art, border), sizes, SetArt, each state's border/glow/art, unknown state, SetBorder override and clearing, glows made once and swapped, SetCount cases, Pop (and reduced motion) |
| Bar | `Bar.test.wowlua` | defaults, options (sizes, track, border false or token), fill/deep, SetFill, the ghost's build, SetMinMax, values with and without a ghost, the ghost's 150 ms hold and latest target, SetValueNow cancelling it, secret values |
| Panel | `Panel.test.wowlua` | close button, key chip, panels (fit to body, solid/shadow/name, fixed width/height, anchor rings and ornaments, titled head, right-side chain of close/key/meta, close vs onClose), theme relayout and its wait for the end of combat, scrollArea (wheel, settling a frame later, scrollbar, track press and drag with a faked cursor, thumb grab, nothing to scroll), makeModal (shade, Esc, other keys, shade click, two modals), confirm (OK, Cancel/Esc/shade, cancel = false, replacing an open one, typeToConfirm with Enter, enterConfirms = false, input with trimming and value), sectionHeader, windowFrame (strata, close, Esc via UISpecialFrames, content scroll and width, footer, tabs: layout, SetTab, clicks, hover, disabled by value or function with its cover and tooltip, theme relayout, reduced motion) |
| Layout | `Layout.test.wowlua` | vertical and horizontal stacks, padding forms, alignment (start, center, end, stretch, horizontal), a fixed cross size, autoSize false, gapBefore, hidden children, child resize, hooked once, ignoring the layout's own echo and secret sizes, GetLayoutSize, texts (natural and fixed width), a secret text size, Remove/Clear, nested layouts in one flush, ApplyNow, a protected container in combat (and an unprotected one), grids (cells, defaults, fewer than columns, empty) |
| Controls | `Controls.test.wowlua` | button variants, sizing to the label, hover, tooltip, disabled (dimmed, no click, still says why, no press), clicks, press offset, fixed width vs SetLabel, icons (shift, width, change, remove), OnShow and theme remeasure; StateBadge tones, neutral fallbacks, width, the fade on first show only, reduced motion, theme remeasure |
| Inputs | `Inputs.test.wowlua` | glyphs and the check; Toggle (off/on, click with the knob's slide, reduced motion, hover, disabled); Checkbox (build, sizes, click, hover, disabled); Segmented (build, click, disabled option and control, hover and the disabled option's tooltip); Slider (build, label/unit/format, drag with step snapping, no step, live = false, SetValue, disabled, theme height); Stepper (Clamp cases incl. float noise, build with/without unit, nudging, typing + Enter, focus lost, Escape, disabled, hover, the edit box redrawn on show); TextField (build, typing, Enter, focus lost, Escape, SetValue, disabled); NumberField (build, filtered typing and onTyping, the edge's tone, Enter clamping, Escape/Cancel, arrows with Shift, Tab, click focus, non-numbers, disabled); MoneyInput (build, SetCopper/GetCopper cases, nil/first value/Clear, the 99 cap, typing, disabled) |
| Select | `Select.test.wowlua` | closed field, placeholder, summary, multiple summaries (none, All, names, "3 of 6", headings not counted), copies, SetOptions, hover and disabled; open list (rows, check, notes, catcher), picking, disabled options and their tooltip, headings, icons/diamonds/fonts, list width and minListWidth; several (toggle, Select all, Clear); search (focus, filtering, Enter, no match, `search` text, headings with matches, false, "always"), lookup, wheel scrolling and its scrollbar, foot links, closing (catcher, another select, hide, disable, never opened), bare fields |
| Pickers | `Pickers.test.wowlua` | AnchorPicker (build, click, disabled, tooltips); AnchorButton (build, open/close, note, pick, tooltip incl. opts.tooltip variants, leaving while open, GLOBAL_MOUSE_DOWN outside, hide, disabled); SwatchRow (build, click, tooltip, disabled); ToggleChips (build, sizes, order, click, SetValue(nil), disabled) |
| SettingRow | `SettingRow.test.wowlua` | row build, inline and stacked controls, description width, SetDescription, modified, disabled with/without reason and with a control lacking SetDisabled, the reset arrow (hover, tooltip, click), Relayout now and next frame, width and control resizes; SettingsGroup build, description, AddRow, SetMeta, Relayout |
| SettingsMatrix | `SettingsMatrix.test.wowlua` | layout of header, rows and centred cells, an empty value, SetValue, the master column greying a row and disabling its cells, copies in and out, Set, clicks on checkbox cells, a pick in a select cell, a column title's tooltip |
| TabMarker | `TabMarker.test.wowlua` | build, first placement, gliding (mid-way and at the end), at once with reduced motion or a hidden row, hover glide and back, hovering the chosen or a hidden tab, tracking once, hiding, markLeft/markWidth, a button laid out a frame later, Place with a scaled button, rule = false / rule token / level / jewel, vertical, box, the easing curve (`import internal ease`) |
| Crest | `Crest.test.wowlua` | defaults, every classification's look in both variants (part counts), metals and jewels, looks made once and swapped, secret classification, the wing's plain fallback (`CreateColor` faked to fail), dragonArt cases (secret classification and boss flag), placeDragon (size, point, hidden for nil/false), the rare elite's breast jewel (made once, scale, hidden by another art) |
| LoadingMark | `LoadingMark.test.wowlua` | sizes with and without wings, Start (assembly, loop 0.8 s in), Stop (before and after the loop), restart, reduced motion |
| Stage | `Stage.test.wowlua` | the art and its points, floor and shade options, CentreOn (and the caller's controls), Tint at 9 % / 8 % following a token change |
| Visibility | `Visibility.test.wowlua` | VISIBILITY_OPTIONS, always/nil, hidden, combat (state driver in and out of combat), mouseover (fade on hover, same mode keeps it), `also` frames (and a hidden one), dragging, an invisible frame, leaving mouseover, a change in combat waiting, edit mode and keybind mode showing every managed frame (`mock.module` on their `isActive`) |

Coverage (`wowlua test --coverage`, each file measured by its own test
file): every line of every file runs; see the table at the end.

## Refactors

None. Every component was already reachable through its builder and
methods, and the few file-level pieces worth checking alone were read with
`import internal` (Draw's `paints`, TabMarker's `ease`, Select's `catcher`,
Panel's `shade`). No source file in this area was changed.

## Bugs found

None in the components. Behaviours the tests pin down that looked odd at
first but follow the code's intent:

- TextField: Escape only drops the focus; what was typed stays and is
  committed by the focus loss (`onChange` runs). The Stepper and
  NumberField put the value back on Escape instead.
- AnchorButton: a disabled button doesn't light its edge on hover but still
  shows its tooltip (to say why).
- Select's `checkW` has the same value on both branches (harmless).

## VM suspicions (wowlua 0.9.1 emulator)

1. **`ScrollFrame:SetVerticalScroll` doesn't run `OnVerticalScroll`.** In
   the client it does (Blizzard's scroll templates rely on it); SuuUI's
   scrollArea moves its thumb from there. Repro (`Panel.test.wowlua`,
   skipped probe "VM probe: SetVerticalScroll runs OnVerticalScroll"):
   ```wowlua
   local s = CreateFrame("ScrollFrame", nil, UIParent); s:SetSize(200, 100)
   local c = CreateFrame("Frame", nil, s); c:SetSize(200, 400); s:SetScrollChild(c)
   local runs = 0
   s:HookScript("OnVerticalScroll", function() runs += 1 end)
   s:SetVerticalScroll(50); mock.advanceFrames(1)
   expect(runs).toBe(1)   -- 0 in the emulator
   ```
   The scrollbar test runs the script itself (`mock.script(s,
   "OnVerticalScroll", 300)`) as the client would.
2. **`OnSizeChanged` runs only for an explicit `SetSize`/`SetWidth`/
   `SetHeight`, not for a size that follows anchors** (a `SetAllPoints`
   child of a frame that is resized, or whose anchors resolve). The client
   runs it whenever the frame's rect changes size. WindowFrame's content
   width follows its scroll frame's OnSizeChanged. Repro (skipped probe "VM
   probe: a frame sized by its anchors gets OnSizeChanged"):
   ```wowlua
   local holder = CreateFrame("Frame", nil, UIParent); holder:SetPoint("TOPLEFT"); holder:SetSize(100, 100)
   local inner = CreateFrame("Frame", nil, holder)
   local sizes: number[] = {}
   inner:SetScript("OnSizeChanged", function(_f: Frame, w: number) sizes[#sizes + 1] = w end)
   inner:SetAllPoints(); mock.advanceFrames(1)
   holder:SetWidth(150); mock.advanceFrames(1)
   expect(sizes).toEqual({ 100, 150 })   -- {} in the emulator
   ```
   The content test runs the script itself.
3. **`EditBox:SetText` doesn't run `OnTextChanged`.** The client runs it
   with `userInput` false. TextField and NumberField handle that call (the
   "not focused" side of their OnTextChanged), which the emulator never
   reaches. Repro (`Inputs.test.wowlua`, skipped probe "VM probe: SetText
   runs OnTextChanged without user input"):
   ```wowlua
   local e = CreateFrame("EditBox", nil, UIParent); e:SetSize(100, 20); e:SetAutoFocus(false)
   local seen: any[] = {}
   e:SetScript("OnTextChanged", function(_e: EditBox, userInput: boolean) seen[#seen + 1] = userInput end)
   e:SetText("abc")
   expect(seen).toEqual({ false })   -- {} in the emulator
   ```

Not suspicions (the client does the same, the tests follow it): colours and
alphas are kept at 8 bits a channel (0.5 reads back 128/255), sizes and
points read back with float noise (compared with `toBeCloseTo`),
`GetTexCoord` returns the four corners (8 values), and OnSizeChanged after
`SetWidth` comes with the next frame.

## Test runner / checker notes

- `mock.errors()` accumulates for the whole file (already in
  `ui-units.md`, 4): Draw's test of repaint's error reporting fakes
  `geterrorhandler` instead, so later tests' `expectNoErrors()` hold.
- `wowlua check` doesn't check test files; only `wowlua test` compiles them
  (`wowlua test <a filter matching nothing>` is a quick way to check them,
  a few seconds while the tree has errors). One test file's error stops
  every test run in the tree.

## Not tested, and why

- What the client draws: the soft-edge texture's look, gradients' pixels,
  the font's metrics (sizes come from the emulator's measuring; the tests
  compare against `measureText` or the regions' own readings, not against
  pixel values).
- The scrollbar's drag reads the real cursor (`GetCursorPosition`,
  `IsMouseButtonDown`): faked in the tests.
- The mouseover poll's dragging check reads `GetCursorInfo`: faked.

## Coverage

Each file measured by its own test file (`wowlua test -j 2 --coverage
--reporter coverage-json unit/UI/<File>.test`), 2026-10-20:

| Source | Tests | Lines | Branches | Conditions | Functions |
|---|---|---|---|---|---|
| Draw | 30 | 276/276 | 80/80 | 20/20 | 30/30 |
| Text | 18 | 72/72 | 32/34 | 6/8 | 11/11 |
| Icon | 16 | 63/63 | 46/52 | 28/34 | 7/7 |
| Bar | 10 | 64/64 | 41/44 | 18/20 | 7/7 |
| Panel | 41 (+2 skipped probes) | 500/500 | 222/244 | 110/126 | 59/59 |
| Layout | 32 | 183/183 | 144/152 | 86/94 | 20/20 |
| Controls | 29 | 120/120 | 80/90 | 39/48 | 14/14 |
| Inputs | 69 (+1 skipped probe) | 561/561 | 305/346 | 160/196 | 84/84 |
| Select | 34 | 432/432 | 270/294 | 152/168 | 31/31 |
| Pickers | 20 | 248/248 | 115/128 | 57/70 | 29/29 |
| SettingRow | 17 | 192/192 | 97/108 | 45/56 | 19/19 |
| SettingsMatrix | 9 | 114/114 | 37/42 | 16/20 | 9/9 |
| TabMarker | 16 | 149/149 | 94/100 | 45/50 | 17/17 |
| Crest | 16 | 115/115 | 81/88 | 37/44 | 10/10 |
| LoadingMark | 6 | 108/108 | 48/58 | 27/36 | 6/6 |
| Stage | 4 | 84/84 | 25/30 | 17/22 | 6/6 |
| Visibility | 12 | 66/66 | 41/42 | 15/16 | 6/6 |

The branches left are, nearly all, outcomes the code can't produce:

- the middle of `cond and X or Y` where X is always truthy (a token name, a
  number): the "X is falsy" arm counts as a branch (most of them);
- guards on fields that are always set (`scroll.grip` with a bar,
  `list.search`, `cell.control`, `p.field.placeholder`, `opts` in
  windowFrame, a glyph stroke's thickness, `self.EnableMouse`);
- `settings.ready()` false (Inputs, LoadingMark): only before the settings
  load, never after login;
- `Enum.StatusBarInterpolation` missing (Bar): another client;
- TextField/NumberField's OnTextChanged without focus (VM suspicion 3);
- TabMarker: a row or hovered button with no rect, a mark whose `from`
  size is unset.
