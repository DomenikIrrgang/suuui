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
move with it. Never assert a raw glyph count.

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
