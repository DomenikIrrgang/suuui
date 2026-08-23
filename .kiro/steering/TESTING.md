# SuuUI Testing

## Mandatory Rule

**Every component, layout strategy, and core subsystem must have a spec, and no change
ships until the suite passes.** A component without a spec file is not finished.

The suite is not a smoke test. It runs the real addon against a simulated WoW client
that solves the actual anchor graph, so a spec asserts **real pixel geometry** — where
a label sits, whether a thumb stays inside its track, whether a row overlaps its
neighbour. That is the whole point: the layout engine's job is placement, so placement
is what gets verified.

```bash
lua Tests/run.lua                          # everything
lua Tests/run.lua --filter Button          # one suite or test name
lua Tests/run.lua Tests/spec/11_button_spec.lua -v
lua Tests/run.lua --trace                  # tracebacks on failure
```

Exit code is non-zero on failure. No external dependencies — no busted, no luarocks.

---

## Layout

```
Tests/
├── run.lua                     runner and CLI
├── harness/
│   ├── framework.lua           describe / it / xit / before_each / expect
│   ├── addon.lua               loads every .toc file into a fresh sandbox
│   ├── init.lua                the H.* API — full reference in its header comment
│   ├── expect_layout.lua       geometry assertions
│   └── wow/                    the simulated client
└── spec/
    └── NN_<area>_spec.lua
```

Specs are numbered so the run order reads bottom-up: harness, layout strategies,
container, core, then components, then integration. One spec file per component or
closely related pair.

Two specs exist to protect the rest:

- `00_harness_spec.lua` verifies the simulated client itself — the anchor solver, resize
  notification, text metrics, input routing. If it fails, every other spec is unreliable
  and possibly green for the wrong reason.
- `99_doc_examples_spec.lua` runs the code examples printed in these steering docs, so
  the guidance cannot rot away from the API. Change an example here, update it there.

---

## What a Component Spec Must Cover

Not a suggestion list. If a section does not apply, the component probably does not do
that thing; if it does apply and is untested, the spec is incomplete.

1. **Construction and defaults** — every prop, including omitted ones. Defaults come
   from theme tokens, so assert against the token, never a literal.
2. **Geometry** — size on both axes, internal part placement, and that parts stay inside
   the component. Use `H.expectInside` / `H.expectNoOverlap` liberally; they catch the
   failures users actually see.
3. **Token-driven sizing** — grow `fontSizeMd` and a `size*` token and assert the
   component re-derives rather than clipping. This is where most real bugs live, because
   font tokens are user-editable.
4. **Layout integration** — add it to a container and assert it reacts to being resized
   by the parent, which never goes through the handle's `SetSize`.
5. **Every signal it emits** — payload and count. Setters are silent by contract, so
   assert that too: `SetValue` must not emit `VALUE_CHANGED`.
6. **Enabled and disabled** — both that the client stops routing input (`H.click`
   returns false) and that the component's own internal guard holds (`H.forceClick`).
7. **Theme reaction** — switch theme or edit a token and assert restyling, including any
   re-measure that changes its size.
8. **Edge cases** — empty text, missing props, nil values, zero and negative sizes,
   values outside a range, an empty options list.
9. **Teardown** — `Destroy()` hides, disconnects signals, unsubscribes from the event
   bus, and unregisters any `OnUpdate`.

---

## Two Rules That Make Geometry Assertions Work

**Mount anything you assert positions inside.** Components never position themselves; a
container does. A component built in a test and never added to one has no anchors, so
every position inside it is unresolvable and `H.box` returns nil.

```lua
-- ❌ positions inside this are unresolvable
local nav = H.C.NavItem({ label = "General" }, host)
H.expectCenteredV(nav._label, nav:GetFrame())

-- ✅ mounted through an anchor container, exactly as real code places it
local nav = H.mount(H.C.NavItem({ label = "General" }, host))
H.expectCenteredV(nav._label, nav:GetFrame())

-- ✅ or add it to the container the test is really about
col:Add(nav, { width = "fill", height = H.token("sizeNavRow") })
```

**Derive expected numbers from tokens and measured text.** A hardcoded pixel value
passes under one theme and lies under every other, and it does not explain itself.

```lua
-- ❌ what is 33, and why?
H.expectSize(btn, 33, 27)

-- ✅ states the rule the component follows
local size = H.token("fontSizeMd")
local padX = H.token("spaceSm") + H.token("borderWidth")
local padY = H.token("spaceXs") + H.token("borderWidth")
H.expectSize(btn, H.textWidth("OK", size) + 2 + padX * 2,
                  H.lineHeight(size) + padY * 2)
```

`H.textWidth`, `H.textHeight` and `H.lineHeight` use the harness font model, so they
move with it. `H.textBox` is the width the layout engine actually **reserves** for a
string — `H.textWidth` plus the one-pixel render allowance `TextMetrics.Box` adds. Assert
against `H.textBox` wherever a font string's own box is sized from its text (a
`width = "auto"` child, a centred `Divider` label, a hugging `NavItem` tab) and against
`H.textWidth` only where a component adds slack of its own on top of the metric. A box at
the bare metric **is a clip** — the simulated client reports it as one, exactly as the real
one truncates it — so `.eq(H.textWidth(...))` on a font string's own width is an assertion
that the label is one pixel short. Never assert a raw glyph count.

**Each measuring helper takes an optional font path**, because faces have different glyph
advances and line heights in the model just as they do in the client. Pass it whenever the
face under test is not the default, or a swap will measure identically before and after
and the test passes whether or not the swap happened:

```lua
expect(H.textWidth("hello", 12, "Fonts/ARIALN.TTF")).lt(H.textWidth("hello", 12))
```

### Two coordinate spaces

The simulated client models both spaces the real one has, because conflating them is a
live bug class:

| Space | What is in it | Vertical range |
|---|---|---|
| **Screen** | `H.box`, `H.offset`, `GetCursorPosition`, every `expect*` geometry helper | `0 .. 768` |
| **Region units** | a widget's own `GetLeft` / `GetTop` / `GetWidth`, its `SetPoint` offsets, its `SetWidth` | screen ÷ its effective scale |

They coincide while nothing carries a scale, which is most of the suite. The pixel grid
puts one on the UI root, so anything under it reports a **different screen height** than
`GetScreenHeight()` does — 1080 against 768 at 1080p. Code that mixes the two is wrong on
the vertical axis only, and looks perfect horizontally.

So: compare a widget against another widget in screen space (`H.box`, `H.offset`), and
compare a widget against its own reported numbers in region units. Do not mix a `H.box`
value with a `GetWidth()` value under a scale.

```lua
-- ❌ tb is screen space, the drag handler works in the track's units
local tb = H.box(s._track)
H.cursor(tb.left + tb.width * 0.75, tb.top, s._track)

-- ✅ the track's own ruler, which is what its handler compares against
local track = s._track
H.cursor(track:GetLeft() + track:GetWidth() * 0.75, track:GetTop(), track)
```

**The default client is a 1:1 pixel grid**, so snapped geometry is integral and every
assertion reads naturally. That also means it hides scale bugs: pass
`H.setup({ physicalHeight = 1080 })` to get a real scale on the root, and add
`H.SuuUI.Pixel:SetEnabled(false)` on top to get a *fractional* grid where nothing lands on
an integer. Both configurations are worth a spec for anything that computes a position or
reads the cursor — a mis-scaled hit test is invisible at 1:1.

**Unit data is per unit token.** `UnitHealth`, `UnitName`, `UnitClass`, `UnitLevel` and the
power family read a per-unit override first (`H.setUnit("target", { health = 40 })`) and fall
back to the flat `state.unitX` value, so a spec about one unit never has to name one while a
spec about two can give them different answers. `UnitExists` is true for `"player"` and false
for anything not staged, which makes "no target" the state a target frame's spec gets for
free. `H.setTarget(props｜nil)` stages or clears `"target"` **and** fires
`PLAYER_TARGET_CHANGED`, because the state moving without the announcement is a situation the
client never produces — and a frame that only reads on the event would look correct in a spec
that skipped it. `UnitReaction(unit, other)` answers for the FIRST unit only, reproducing the
client's asymmetry rather than hiding it: a caller that swaps the arguments gets nil.

**A staged unit is a creature until a spec says `isPlayer = true`.** `UnitClass` answers for
a creature in the real client — almost always `"WARRIOR"` — so the harness answers the same
way, and `UnitIsPlayer` is the only thing that tells a mob from a player. A spec painting
another *player* must therefore stage it (`H.setTarget({ class = "MAGE", isPlayer = true })`);
one painting a mob stages neither and gets the misleading class the client really reports.
`classless = true` is the narrower case of a unit the client reports **no** class for, so it
is the wrong tool for modelling a mob — reaching for it is what let a bug ship where every
creature rendered in warrior tan while the reaction fallback looked fully covered.

**Auras are staged per unit, and staging them fires the event.** The same shape as
`H.setUnit` / `H.setTarget`, for the same reason: state moving without the announcement is a
situation the client never produces, so a reader that only repaints on `UNIT_AURA` would look
correct in a spec that skipped it.

```lua
H.setAuras(unit, lists, opts)   -- lists = { helpful = {…}, harmful = {…} }; fires UNIT_AURA
H.clearAuras(unit, opts)        -- drops every aura on the unit; fires UNIT_AURA
H.getCancelBuff()               -- { unit, index } from the last CancelUnitBuff, or nil
H.resetCancelBuff()             -- clears that record
H.getTooltipState()             -- { owner, anchor, aura = { unit, index, filter } }, or nil
H.resetTooltipState()           -- clears that record
H.GameTooltip                   -- the stub frame itself, for IsShown()
```

`opts = { silent = true }` on either setter suppresses the event, which is what you want when
the spec is *about* a reader that ignores it. An entry declares only the fields that matter
and the rest are filled from defaults; an unknown field name raises rather than being silently
dropped, so a typo is a failure and not a passing test asserting nothing:

```lua
H.setAuras("player", {
  helpful = { { name = "Blessing", icon = "x", duration = 300,
                expirationTime = H.env.GetTime() + 120 } },
  harmful = { { name = "Curse of Agony", debuffType = "Curse" } },
})
```

Two traps sit in this corner of the harness, both found the hard way:

**`H.box(...).top` measures downward from the screen top**, so it grows as a frame moves *down*
the screen — the opposite of the client's own bottom-up `GetTop()`. A band **above** the frame
therefore has the **smaller** `top`, and one further above has a smaller one still; a band
below has a larger one. Reading it as a bottom-up coordinate inverts every comparison while the
assertion still looks reasonable, which is what makes it expensive. State the direction in the
message so the next reader cannot misread it:

```lua
-- ✅ "above" means closer to the screen top, which is a smaller .top
expect(H.box(band).top).as("the band sits above the frame").lt(H.box(frame).top)
```

**The cast bar attaches below the player frame by default**, so a player-frame `GetCoreInset`
spec never starts from `(0, 0)` — `anchor` defaults to `"attached"` and `attach_position` to
`"below"`, which means the below inset already carries a bar and its gap before your band
exists. Assert the **delta** across the change you are testing, not the absolute:

```lua
-- ❌ fails for a reason that has nothing to do with auras
local _, below = frame:GetCoreInset()
expect(below).eq(bandHeight + gap)

-- ✅ what the band contributed, whatever else is already down there
local _, before = frame:GetCoreInset()
H.setAuras("player", { harmful = { { name = "Curse" } } })
local _, after = frame:GetCoreInset()
expect(after - before).eq(bandHeight + gap)
```

**Bar transitions default to `instant`** (`H.setup()` calls
`Transitions:SetDefault("instant")` unless you pass `barTransitions = true`). The shipped
default is `"smooth"`, which means a value written by `SetValue` arrives over several
frames, so a spec asserting a fill width straight afterwards would measure a value still in
transit — non-deterministic and dependent on tick count. The simple configuration by
default, the real one where the spec is about it:

```lua
H.setup({ barTransitions = true })
```

When a spec wants the value where an animated fill **settles** rather than its intermediate
state, call `H.runAnimations()` after the write — it advances the clock far enough for
every queued animation (including chained sequences) to complete. Specs for the real
`PlayerFrame` plugin must use it because that plugin names its strategies explicitly and
overrides the test default.

**The wall clock is a separate clock from `GetTime()`, and mixing them up is the trap.**
`GetTime()` is **uptime**: seconds since the UI loaded, starting at 0, and it is what `H.tick`
advances. `time()` is the **epoch**, and it is what a clock widget reads. The two are entirely
independent here — ticking the animation clock for a second does not move the wall clock by a
second, or at all — so a spec about elapsed time drives `H.tick` and a spec about what a clock
*says* drives `H.setClock`.

```lua
H.setClock(when)              -- epoch seconds, or { year, month, day, hour, min, sec } in UTC
H.setRealmTime(hour, minute)  -- what GetGameTime() reports; nil, nil returns it to the wall clock
```

Three properties of the model are deliberate:

- **`date()` is modelled rather than delegated, and it forces UTC.** Handing the format string
  straight to `os.date` would make "what does the clock say" depend on the timezone of the
  machine running the suite, so the same assertion would pass in Berlin and fail in CI.
  `H.setClock`'s table form computes days since the epoch itself for the same reason —
  `os.time` interprets a table in local time and would reintroduce exactly the dependency the
  helper exists to remove.
- **The default is fixed at 2026-08-22 14:32:07 UTC**, which reads as `"14:32"`, and it is
  reset by every `H.setup()`. So an unconfigured clock widget renders the same string in every
  run and on every machine, and a spec only calls `H.setClock` when the instant is what it is
  testing — a midnight rollover, a 12-hour `%I` with its leading zero stripped.
- **`GetGameTime()` defaults to agreeing with the wall clock**, derived from the same instant,
  because a realm that agrees with the player is the ordinary case. Stage a divergence with
  `H.setRealmTime` only where the divergence is the point — it is the whole reason a clock
  widget shows both — and note the state resets between tests, so a staged realm clock cannot
  leak into the next spec's assertions.

**Framerate and latency are staged as state, because nothing announces them.** No event fires
when either moves, which is why a widget reading them declares an `update` interval rather than
an `events` list — and it is why a spec has nothing to fire: stage the reading, advance the
bar's ticker with `H.tick`, and assert what the field says.

```lua
H.setFramerate(fps)                    -- what GetFramerate() reports; default 60
H.setNetStats(down, up, home, world)   -- what GetNetStats() reports; all four default to 0
```

Both reset on every `H.setup()`, for the same reason the unit state does: a spec staging a bad
framerate or a laggy connection would otherwise leave the next file's readout sitting in its
warning colour and passing for the wrong reason.

**`world = false` models the OLDER three-return client, and `world = 0` does not.**
`GetNetStats` has two shapes across client generations — three values carrying a single latency
in the third slot, or four splitting home from world — so a reader has to survive both, and the
two staged states are different facts:

| Staged | Client shape | What a reader sees |
|---|---|---|
| `world = nil` (default) | four returns | a world latency of 0, i.e. present but **not measured** |
| `world = 250` | four returns | a measured world latency |
| `world = false` | three returns | no fourth value at all |

So `H.setNetStats(0, 0, 90, false)` is the assertion that a reader falls back to home latency
because the client never offered a world one, while `H.setNetStats(0, 0, 90, 0)` asserts it
treats a zero *reading* as unmeasured and falls back anyway. Reaching for 0 to model the old
client tests neither: the fourth return is still there, so the branch that has to cope with its
absence is never entered.

### Action slots

```lua
H.setAction(slot, props, opts)   -- merges into the slot; fires ACTIONBAR_SLOT_CHANGED
H.clearAction(slot, opts)        -- empties it, so HasAction answers false
H.setActionBarPage(page, opts)   -- fires ACTIONBAR_PAGE_CHANGED
H.setBinding(command, key)       -- what GetBindingKey answers
H.setActionBarLocked(locked)     -- writes the LOCK_ACTIONBAR global, "0"/"1"
H.getPickedUpAction()            -- what the cursor carries after PickupAction
H.getOverrideBindings()          -- every SetOverrideBindingClick, in call order
H.getStateDriver(frame, state)   -- the conditional string a frame registered
H.getUsedAction()                -- { slot, button } from the last secure action click
H.resetUsedAction()
```

The shape was **measured in game**, not assumed: 12 buttons across 6 pages, and pages 3–6 are
the same slots the four multibars own. So a paged bar 1 and a fixed bar 3 can legitimately
address one slot at once, and a slot→button map is the wrong data structure — it has to be
slot→**buttons**.

**An empty slot is the absence of a record, not a record of zeroes.** `HasAction` has to be
able to say no, and a button reading an all-zero record would draw an icon for nothing. Two
fields are therefore meaningfully `nil` and are *not* defaulted:

| Call | Empty slot | Why it matters |
|---|---|---|
| `GetActionText` | `nil` | a spell has no macro name, so this cannot be used to test occupancy |
| `IsActionInRange` | `nil` | `nil` means range is not a question (a self buff); `false` means out of range, and a button must paint those differently |
| `GetActionCooldown` | `0, 0, 0` | **not** `nil` — the client returns zeroes, and a `Cooldown` frame handed `nil` errors instead of clearing |

`setAction` **merges**, so a spec can put a spell in a slot and then start its cooldown without
restating the spell, and it rejects an unknown field rather than ignoring it. Every store
resets on `H.setup()`.

**Drag swaps, it does not overwrite.** The cursor carries a slot's *contents*, so
`PlaceAction` onto an occupied slot hands the previous occupant back to the cursor. A button
that assumed overwrite would destroy an action every time a player rearranged a bar.

**A button receives `LeftButtonUp` and nothing else until it calls `RegisterForClicks`.** An
action button wanting right-click has to say so, or its secondary action silently does nothing
— in game and here. That is pinned in `00_harness_spec.lua`.

**`RegisterStateDriver` is a RECORDER, never an evaluator.** A driver string is a macro
conditional, and resolving one locally would mean the harness guessing what the client decides
— after which a spec asserts against the guess rather than against the client. Assert the
string; check the consequence in game. This is the only paging mechanism that works in combat,
so there is nothing else a local spec could prove about it.

**`SetAttribute` is still NOT gated by the lockdown model.** Only the eight geometry and
visibility setters are (see *Combat lockdown* below), so "attributes are stated once, at
construction" is a **structural** assertion only — a spec can prove where the call sits, not
that the client would refuse it later. Do not read a green run as proof that a mid-combat
`SetAttribute` is safe.

Cursor coordinates belong to a space, so name it: `H.cursor(x, y, frame)` treats `x, y` as
being in that frame's coordinate space. Omitting the frame means `UIParent`, which is only
the same thing while nothing in the chain has a scale.

`H.font.faces` is also the set of faces the client will load. **`SetFont` raises for
anything else**, as the live client does (`Invalid font asset`), so code that probes font
paths has to protect the call — modelling that as a `false` return once hid an error that
unwound out of the `PLAYER_LOGIN` handler. `H.addFont(name, path)` adds a loadable face
plus a client font object that reports it, the way a locale client or a media addon does;
faces reset on every `H.setup()`.

**Assert text is not clipped wherever a font string is sized.** The client clips a font
string to its box instead of overflowing it, so a label pinned to a stale or unmeasured
size draws a half glyph while its position, size and colour all still assert clean. That
failure mode is only visible through `H.expectTextNotClipped(fontString)`.

### Clipping: what a widget was assigned vs what draws

`SetClipsChildren(true)` makes a frame a **window**: the client scissors its whole descendant
subtree to that frame's rect, so a child taller than the window draws only the band that
overlaps it. A shrinking window over a full-height body is how an `Accordion` collapses, and
with no clip its rows draw straight over whatever sits below it.

| Helper | Answers |
|---|---|
| `H.clipsChildren(f)` | does this frame clip what is inside it — the client's `DoesClipChildren()` |
| `H.clipAncestor(f)` | the nearest ancestor clipping it, or nil when nothing does |
| `H.visibleBox(f)` | its box intersected with every clipping ancestor; nil when none of it draws |
| `H.isClipped(f)` | whether any part of it falls outside a clipping ancestor |

All four take a raw frame, a texture or font string, a component handle or a container, so a
spec asks about whatever it already holds. A region answers `false` to `clipsChildren` rather
than raising — it has no children of its own to clip.

Three things about them are load-bearing:

**`H.box` still reports the rect a widget was ASSIGNED; `H.visibleBox` reports what would
actually be drawn.** The solver deliberately does not clip and must not start: dozens of specs
measure deliberately-hidden or deliberately-zero-sized children — `StackLayout` sizes a progress
fill at 0% exactly that way — so teaching `H.box` about clipping would break them wholesale. Ask
`H.box` what a widget was given and `H.visibleBox` what survives. An overflowing child therefore
reports the *larger* `bottom`, and that is the assertion to write; `H.expectInside` is the wrong
tool, because it asserts containment and the point of the spec is that the body is not contained.

**`clipAncestor` is exclusive of the widget itself**, because that is the client's rule:
`SetClipsChildren` clips a frame's descendants and never its own rect. So the window that clips a
body is not clipped by its own clip — `H.clipAncestor(window)` is nil and `H.isClipped(window)`
is false while `H.clipsChildren(window)` is true. `clipsChildren` asks "does this clip what is
inside it", `clipAncestor` asks "what clips this"; reading one as the other is how a spec ends up
asserting the window itself has been cut away.

**Clipping follows parentage, not the anchor chain** — a frame merely *anchored* to a window is
not inside it and is not clipped by it, the same distinction the hidden-frame gap below turns on.
Nested windows compose on both axes: the visible box is the intersection of every clip up the
parent chain, and a non-clipping frame in between is stepped over rather than ending the walk.

`Tests/spec/00_harness_spec.lua`'s `frame clipping` block is the worked example of all four.

---

## Forbidden in Specs

```lua
-- ❌ asserting intent instead of result: this passes even if the child is off-screen
container:Add(child, { width = "fill" })
expect(child._layoutProps.width).eq("fill")
-- ✅ assert the geometry that property produced
H.expectSize(child, container:GetWidth(), nil)

-- ❌ reaching into a component to fake an interaction
btn:GetFrame():GetScript("OnMouseUp")()
-- ✅ deliver input the way the client does, so mouse-enabled and visible are honoured
H.click(btn)

-- ❌ polling an animation with a magic number of ticks
for i = 1, 37 do H.tick(0.016) end
-- ✅ run until everything queued, including chained sequences, has finished
H.runAnimations()

-- ❌ leaving state for the next test
-- ✅ H.setup() in before_each: a fresh addon in a fresh client every test
```

---

## When the Harness Cannot Express Something

Same rule as the layout engine: **extend the harness, do not skip the test.**

1. **Stop** — do not weaken the assertion into something meaningless.
2. **Name the gap** — what client behaviour is missing? A widget method, a script, an
   input path, a text metric?
3. **Implement it** in `Tests/harness/wow/` next to the behaviour it belongs with —
   widget methods in `widget.lua`, frame subtypes in `frame.lua`, regions in
   `regions.lua`, globals in `api.lua`, text metrics in `font.lua`.
4. **Cover it** in `Tests/spec/00_harness_spec.lua`. The harness is load-bearing: if it
   is wrong, every spec built on it is wrong and green.
5. **Document it** here if it changes how specs are written.

---

## Embedded Libraries Run For Real

`Libs/` loads in the suite exactly as it does in game, and that needed **no change to the
loader**: `addon.lua`'s `readToc` takes any `.toc` line ending in `.lua`, so a vendored file is
an addon file and nothing about it is special. The cost landed entirely in the simulated
client — six additions, because third-party code reaches for parts of the API SuuUI itself
never touches.

Four of them were simply absent:

- **`Tests/harness/wow/animation.lua` — AnimationGroups.** Nothing in SuuUI uses them: the
  addon runs its own shared-`OnUpdate` animator by design, so the group API existed nowhere at
  all and LibDBIcon's `CreateAnimationGroup` for its button fade killed the load outright. It
  is deliberately a **configuration recorder that does not tick** — it stores what was asked
  for and whether the group is playing, and `H.tick` drives SuuUI's animator rather than this,
  so a spec must never read a mid-flight value here and believe it. The one real effect
  modelled is the client's `SetToFinalAlpha` contract: on `Finish`, an Alpha animation's end
  value is left on the target instead of reverting. Model what a caller can observe and model
  nothing beyond it, so nothing invites an assertion the model cannot honour.
- **`GameTooltip` became a real frame type.** It used to be a plain `Frame` with tooltip verbs
  bolted onto the singleton, which cost two things: `CreateFrame("GameTooltip", …)` was refused
  (*does not simulate type GameTooltip*), so embedded code that builds its own tooltip could
  not load, and the singleton had no `AddLine`, so tooltip **content** was unreadable. It is
  now derived from `GameTooltipMeta` in `wow/frame.lua` like any other subtype: a second
  instance is possible, and `NumLines()` / `GetLine(i)` answer — so a spec can assert what a
  tooltip *says*, not only what it was pointed at.
- **WoW's Lua stdlib global aliases.** `strmatch`, `strfind`, `strsub`, `strlower`, `strupper`,
  `format`, `gsub`, `tinsert`, `sort` and the rest. The client predefines them, so their
  absence was an inaccuracy rather than a choice — and because a sandbox read falls through to
  the real `_G`, where these do not exist either, nothing was ever going to supply them.
  LibStub reaches for `strmatch` on its first line of work.
- **`math.atan2`, aliased to `math.atan`.** Lua 5.1 had it, 5.3 removed it, and it survives on
  a build carrying the compat flag — which is precisely why this looked fine locally and would
  have died on a stricter Lua. LibDBIcon's drag handler reads it, so the symptom would have
  been a minimap button that cannot be dragged, for a reason nothing in SuuUI is responsible
  for.

The other two additions were **present and wrong**, which is the more interesting pair; both
are written up in "Known Gaps" below as newly-closed instances of the pattern this file already
documents.

### Why the real libraries and not stubs

Hand-modelling the four libraries would have been less work and would have proved nothing. A
stub encodes *our* assumptions about a library rather than the library's behaviour, so a spec
asserting "the button registers and hides" passes against the model by construction — it
asserts that the stub does what we wrote the stub to do, and it would keep passing while the
real library failed on the client. The six defects above are the argument for the harder path:
every one of them is a place our assumption about the client differed from the client, and only
real library code walking those paths surfaced any of them.

The honest cost is that the suite now depends on the **vendored version**: bumping a library
can turn it red. That is the point rather than a regression — a bump that changes behaviour we
rely on should be visible here before a player finds it — but it does mean a lib update is a
change to test, not a file copy. What must not happen is patching `Libs/` to make the suite
green again; that trades a red test for a merge conflict forever (see
`WOW_API_ENCAPSULATION.md`, "Embedded Third-Party Libraries Are Exempt").

---

## Known Gaps in the Simulated Client

The harness is faithful enough that specs assert real pixel geometry, but it is not the
client. Where it differs, write the assertion that survives the difference.

**A hidden frame has a rect here and none in the client.** The solver resolves an anchor
chain through a hidden frame; the real client returns nil from `GetTop()` / `GetLeft()` for a
hidden frame and for anything anchored to one. A child anchored to a hidden container
therefore looks perfectly placed in every spec and draws nothing in game — it still reports
the size it was assigned, still says `IsShown()` and `IsVisible()`, and 18 assertions about
its size, alpha, state and content pass. That is exactly how the first attached cast bar
shipped invisible.

So for anything that anchors a child to a frame it is **not parented to** — an attach point
is the case in this codebase — assert the *invariant* rather than the consequence:

```lua
-- ❌ passes whether or not the child will ever draw in game
H.expectSize(child, 336, 40)

-- ✅ the rule the client actually enforces: the anchor target must have a rect already
expect(shownAtAdd).as("slot visible when the child was anchored to it").eq(true)
```

`Tests/spec/35_attach_login_spec.lua` carries the worked example. Closing the gap properly
means teaching the solver that a hidden frame has no rect, which would change what `H.box`
returns for every deliberately-hidden child in the suite (`StackLayout` sizes a progress fill
at 0% exactly that way) — worth doing, but not as a drive-by.

**Combat lockdown is modelled by frame identity, not by taint.** `InCombatLockdown()`,
`frame:IsProtected()` and the geometry refusal are all real now: while in combat, `SetSize` /
`SetWidth` / `SetHeight` / `SetPoint` / `SetAllPoints` / `ClearAllPoints` / `Show` / `Hide` return
having changed nothing on any frame that is protected **or that holds a protected descendant**,
and every refusal is recorded in `H.getBlockedActions()`. Drive it with
`H.setCombat(true｜false)`, which fires `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` on a real
transition only, and ask `H.hasProtectedDescendant(frameOrHandle)` for the exact question the
refusal asks.

What is missing is *why* the client refuses. The real decision is **taint**: an execution path
that has touched insecure code is what gets refused, so the identical call succeeds from a
Blizzard path and fails from an addon's. The harness refuses on the frame alone, so it cannot
express that difference — and it does not yet gate every call the live client refuses on a
protected frame in combat, `SetParent`, `SetScale` and `SetAttribute` among them. `SetAttribute`
matters in particular: it is why a secure click surface cannot be re-pointed at a different unit
mid-fight, which is why `UnitClickArea` states its attributes once at construction.
`UnitAffectingCombat` is not modelled at all and is **not** a synonym for `InCombatLockdown()` —
lockdown outlasts the player's own combat flag, so code reading the wrong one is still invisible
here. The refusal is also silent: no `Interface action failed because of an AddOn` line exists to
assert against. And `PLAYER_REGEN_ENABLED` fires synchronously inside `H.setCombat(false)` rather
than a beat after combat drops, so a spec cannot tell work that was genuinely deferred to the
event from work that merely ran on the way out.

This gap is why a real bug survived **2728 passing assertions for ten days**. `UnitClickArea` was
parented to the unit frame's wrapper; that wrapper resizes mid-combat by design (an aura band
gaining a row, a cast bar attaching), so every one of those resizes was refused and the band was
carved out of a box frozen at its pre-combat height, pushing the frame's own bars down by the
band's height. In game, `GetPreferredSize` returned 227 against a `GetHeight` of 188, with
`InCombatLockdown()` true on every mismatch and false on every match.

So assert **both** halves. The structural invariant states the design rule and holds even where
the model is thin; the behavioural one proves the client would actually allow the write:

```lua
-- The rule: a frame that resizes must not contain a protected one.
expect(H.hasProtectedDescendant(w:GetFrame()))
    .as("the secure surface must not sit inside the frame that resizes").falsy()

-- The consequence: in combat, the growth is not refused.
H.setCombat(true)
H.resetBlockedActions()
H.setAuras("target", { harmful = { { name = "D", icon = "i" } } })
expect(#H.getBlockedActions()).as("nothing was refused").eq(0)
```

`Tests/spec/41_unit_click_area_spec.lua` carries the worked example of both.

**Clipping is modelled as geometry and nothing else.** The helpers above answer where the
scissor rect falls and stop there. A clipped-away child still routes input, still reports
`IsShown()` and `IsVisible()`, and still contributes its full height to everything the layout
strategies compute — flow skips a child for being *hidden*, never for being invisible behind a
clip. The real client's clipping also interacts with draw layers and with a scroll frame's own
scissoring in ways none of this reproduces. So a spec may assert that a row is cut off; it may
not conclude from that that the row is unreachable, that its container shrank, or that nothing
below it can be clicked.

It exists because `SetClipsChildren` was a **write-only stub**: the harness stored the flag and
nothing could read it back, so "the rows do not spill during the reveal" passed whether clipping
was on or off — the same shape as the two gaps above, a model thin in exactly the direction the
assertion was pointing. `DoesClipChildren()` now answers, and the helpers are built on that
getter, so an assertion written through them can tell the two states apart.

**Aura filters are matched whole, not tokenised.** `UnitAura` reads the harmful list only for
the exact string `"HARMFUL"`; nil means `"HELPFUL"` as in the live client, and **everything
else falls through to the helpful list**. So `"HARMFUL|RAID"` silently returns buffs. The
client accepts pipe-separated sub-filters (`PLAYER`, `RAID`, `CANCELABLE`, …) and nothing here
parses them, so a reader that starts using one needs `resolveAura` in `api.lua` extended
first — a spec written against a compound filter today passes while asserting the wrong list.

**`GameTooltip` records what it was pointed at and renders nothing.** The stub stores the
owner, the anchor and the `{ unit, index, filter }` of the aura it was asked to describe, which
is enough to assert that a mouseover reached the right aura by the right method. It produces no
text lines and fires no tooltip scripts (`OnTooltipSetSpell`, `OnTooltipCleared`), so anything
asserting tooltip *content* needs it extended. Assert the aura **index** rather than the icon's
position for the same reason the code indexes by it: they agree only while nothing is filtered.

**`Cooldown:GetCooldownTimes()` always returns 0 as its third value.** The live client returns
1 while a cooldown is running; the stub returns `start, duration, 0`. Irrelevant to a swipe,
which is driven entirely by start and duration — but a caller that gates behaviour on that
`enable` flag would read "off" in every spec and "on" in game, so extend the stub before
writing one.

**Edit Mode re-anchoring is not modelled.** `EditModeManagerFrame` exists on the live client and
re-anchors the frames it manages — on login, on a layout change, whenever
`UIParent_ManageFramePositions` runs — which is why moving a Blizzard frame needs a
`hooksecurefunc` re-assert rather than a one-shot `SetPoint` (see "Repositioning A Blizzard
Frame" in `WOW_API_ENCAPSULATION.md`). Nothing in the harness ever re-anchors anything, so
**no spec can prove that re-assert fires in game.** A spec that installs the hook and then calls
`SetPoint` itself is asserting against its own trigger, not against the client's.

That is the same shape as the lockdown gap above, so treat it the same way: assert what *is*
observable and do not read a green run as coverage. The observable parts are that the original
anchor is stored before the frame is touched and restored exactly on teardown, that the flag is
cleared before the restoring placement (drive the hook by hand and assert the frame did not move
again), and that repeated re-asserts do not accumulate — the offset is derived from the stored
original `y`, so calling the re-assert path five times must leave the frame where one call put
it. What stays unprovable here is the trigger.

### Two of these gaps are now closed, and both were found by real library code

Embedding third-party libraries walked paths no SuuUI file walks, and two of them landed in
exactly the blind spot the gaps above describe: **the harness models geometry faithfully and the
client's API *surface* loosely**, so a frame stayed present, sized and plausible while the
behaviour underneath it was wrong. Neither produced a red test. That is what makes them worth
writing down rather than quietly fixing.

**`WOW_PROJECT_ID` and `WOW_PROJECT_MAINLINE` were both undefined.** A library branching on
`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` to select retail behaviour was therefore comparing
`nil == nil`, which is **true** — so the suite would have exercised the retail path while the
game takes the Classic one. In a harness whose entire claim is geometry that is not academic:
LibDBIcon's branches choose art *sizes*, a 50×50 border against 53×53, with different background
and icon dimensions and a different anchor point, so an assertion would have measured a ring
that does not exist on this client. The sharper edge is that a spec written deliberately to pin
the **Classic** branch would have **passed for entirely the wrong reason**, and gone on passing.
Both globals plus the rest of the family are now declared, and `WOW_PROJECT_ID` is
`WOW_PROJECT_BURNING_CRUSADE_CLASSIC` — SuuUI targets TBC Anniversary, interface 20504.

**A `Button` was not mouse-enabled by default, and `RegisterForClicks` was matched
case-sensitively.** In the client a `Button` takes mouse input without anyone calling
`EnableMouse`, and `"anyUp"`, `"AnyUp"` and `"ANYUP"` are one registration. Third-party code
relies on both — LibDBIcon's button calls `RegisterForClicks("anyUp")` and never touches
`EnableMouse` — so **every click from such a button was silently dropped by the harness's own
input routing while working perfectly in game.** The frame was present, sized, visible and
correctly registered throughout.

The two halves differ in how much they hid, which is worth knowing when you go looking for the
next one of these. The missing default at least left a readable discrepancy:
`IsMouseEnabled()` answered `false`, so `H.click` refused the click and returned `false`, and
anyone who thought to ask got a straight answer. The case-sensitive match left nothing at all:
the button *was* mouse-enabled, so `H.click` ran the whole gesture, fired `OnMouseDown` and
`OnMouseUp`, **returned `true`** — and never fired `OnClick`. A truthy return from `H.click`
means the input was delivered, not that a handler ran, and there was no third reading to
distinguish them. `IsMouseEnabled` now falls back to a per-subtype default (`Button`,
`CheckButton` and `EditBox` accept the mouse; a plain `Frame` does not) and the click matcher
lower-cases both sides before comparing.

The lesson is the one every gap here keeps restating: **a model that is thin in exactly the
direction an assertion points cannot fail.** Both of these were found by making real foreign
code run, not by re-reading the harness — which is the argument for doing that rather than
stubbing.

---

## Pinning an Open Question

When a test reveals behaviour that is arguably wrong but the correct answer needs a
decision, do not delete the test and do not leave the suite red. Pin both sides:

```lua
it("returns 2 at t=0 for spring, as written today", function()
    -- Pins current behaviour so a change to it is visible in the diff.
    expect(SuuUI.Tween.Ease(0, "spring")).near(2, 0.0001)
end)

xit("starts spring at 0 like every other easing", function()
    -- The invariant we believe should hold, skipped pending a decision. Explain the
    -- options here so whoever picks this up does not have to re-derive them.
end)
```

`xit` reports as skipped, keeps the run green, and leaves the question in the codebase
instead of in someone's memory.

---

## Definition of Done

A change to `Components/`, `Layout/`, `Core/` or `SettingsUI/` is done when:

- [ ] `lua Tests/run.lua` passes with no failures
- [ ] New behaviour has a spec that would fail without the change
- [ ] Changed behaviour has its existing spec updated, not deleted
- [ ] Geometry assertions derive from tokens, not literals
- [ ] Anything left undecided is pinned with a passing test plus an `xit`
