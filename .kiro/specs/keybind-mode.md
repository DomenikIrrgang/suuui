# Keybind Mode — v1 Plan

A hover-to-bind mode for the action bars. Turn it on, hover any action button, press a key
combination and it binds. `ESC` on a button clears every key bound to it. A small panel carries
`Save` and `Discard`, because edits apply **live** and are only persisted when saved.

Visual reference: artifact `suuui-keybind-mode-concept`. **That artifact is the spec for the
visuals** — wash colours, the key chip, the multi-bind dot, the tooltip, the panel copy and the
state sequence all come from it. Anything that cannot be built as drawn is a question for Domenik,
not an implementer's judgement call.

Chosen commit model: **C — live apply, Save/Discard panel.** Models A (press = persisted) and B
(press then click to confirm) were rejected; B would have cost mouse-button and mousewheel binds
outright, since left-click would have become the commit gesture.

---

## 0. Client facts — MEASURED IN GAME 2026-08-26

Read off the live client, not inferred. Re-run after any client patch.

| Fact | Measured value | What it forces |
|---|---|---|
| `SetBinding(key, command)` | returns `true` | the write path is one call, no secure template |
| **`SetBinding` fires `UPDATE_BINDINGS` SYNCHRONOUSLY** | `>> UPDATE_BINDINGS fired` printed **before** `ret true` | **the whole propagation story is free.** `ActionBars.lua:991` already re-runs `applyOwnBindings` for every bar on that event, and `ActionButton:_paintHotkey` already repaints from it. The mode writes a binding and does nothing else — no re-route code, no label refresh, no per-bar bookkeeping |
| `GetBindingKey(command)` | **VARARGS** — `after 1 CTRL-F9` | a command can hold several keys. The chip shows the FIRST; the tooltip lists ALL; `ESC` must iterate ALL. Beware reading it: in a non-final `print` argument Lua truncates it to one value, which is what made probe 7 unable to answer its own question |
| `SetBinding(key)`, command omitted | unbinds, returns `true` | this is the `ESC` clear mechanism |
| **`LoadBindings(GetCurrentBindingSet())`** | **reverted a live `SetBinding`** — `after discard 1` | **Discard needs no snapshot table.** The saved binding set on disk *is* the snapshot, exactly as ElvUI relies on. Corollary: Discard also reverts anything changed outside the mode and never saved |
| **`SaveBindings(1)`** | **persists across `/reload`** — `after reload: 1\|CTRL-ALT-SHIFT-P` | Save is one call and it is durable |
| `GetCurrentBindingSet()` | **`1`** = account-wide | binds are account-wide by default on this character. The panel's per-character checkbox is `LoadBindings(2)` + `SaveBindings(2)`, matching `AB:ChangeBindingProfile` |
| **`SetBinding` in combat** | returns **`false`**, does **not** error, and the client prints **`Interface action failed because of an AddOn`** | **gate on `InCombatLockdown()` before calling.** A `pcall` wrapper is useless here — there is no error to catch, and the attempt itself throws a scary message at the player. Measured: `setbind true false` |
| `SaveBindings` in combat | did not error — `savebind true` | **auto-saving on combat start is legal**, so the mode saves instead of silently discarding the way ElvUI does |
| `IsMetaKeyDown` / `GetBindingAction` / `LoadBindings` / `SaveBindings` / `GetCurrentBindingSet` | all `function` | the conflict warning is implementable: `GetBindingAction(keyString)` names the current owner |
| **`SetPropagateKeyboardInput(true)` on a plain Frame** | **`OnKeyUp` NEVER FIRES** — the probe printed `press keys NOW` then `off`, no key lines | **exclusive capture (`false`) is the only mode that works**, which is what `Components/KeyCapture.lua` already uses. Forces the design below: the capture frame is the PER-HOVER overlay, keyboard-enabled on `OnEnter` and released on `OnLeave` — never a mode-wide listener, which would swallow chat and movement for as long as the mode is open |
| `SuuUIBarstanceButton1` | **nil** on this character; `SuuUIBarpetButton1` is a `table` | a bar can be absent. Iterate what exists; never assume 15 bars |
| button frame names | `"SuuUIBar" .. def.id .. "Button" .. i`, id concatenated raw | so the class bars are literally `SuuUIBarpetButton1` / `SuuUIBarstanceButton1`, lowercase |
| `GetBindingKey("ACTIONBUTTON1")` | `1` | bar 1's `ACTIONBUTTON` family is **validated by daily play, not by probe** — CTRL-F9 is unpressable on this macOS keyboard, so the behavioural test was skipped. Blizzard's bars are parked with their event frames silenced, so `1` firing the bar-1 ability can only be SuuUI's override resolving. Treat as confirmed |

### Facts inherited from the ActionBars work, restated because this feature depends on them

- SuuUI **never writes** a binding today. It reads `GetBindingKey(prefix..i)` and re-routes with
  `SetOverrideBindingClick(gridFrame, false, key, buttonName, "LeftButton")` (`ActionBars.lua:387`).
- An override **beats** the base binding, which is why interception needs no migration of the
  player's saved keys — and why a stale override makes a key do **nothing** rather than degrade.
- `applyOwnBindings` already defers in combat into `p._pendingBindings`, drained on
  `PLAYER_REGEN_ENABLED` (`ActionBars.lua:366-373`, `:997`).
- Bars 9–13 declare their own names in `Bindings.xml` (`SUUUIBAR9BUTTON1`…), so they are bindable
  through `SetBinding` like any Blizzard family. Pet is `BONUSACTIONBUTTON`, stance is
  `SHAPESHIFTBUTTON` (**not** `STANCEBUTTON`).

---

## 1. Decisions locked

| Decision | Ruling | Why |
|---|---|---|
| Commit model | **C** — live apply, `Save` / `Discard` | Domenik, 2026-08-26 |
| Where keys live | **Blizzard's binding set** (`SetBinding` + `SaveBindings`) | rides the existing `UPDATE_BINDINGS` re-route for free, stays visible in Blizzard's Key Bindings UI, survives SuuUI being disabled. Cost accepted: binds follow the account/character set, not the SuuUI profile |
| Scope | action bars **1–13 + pet + stance** | all are `ActionBarGrid` buttons with real binding prefixes. Stance costs nothing extra even where the class has none |
| Micro menu, bags, inventory slots | **OUT of v1** | they are DataBar *fields*, not buttons, so they carry no binding names. Including them means inventing a binding family — a separate feature |
| Conflict handling | **warn before stealing** | approved by Domenik. ElvUI steals silently and its own gap analysis calls that its worst hole |
| Entry points | `/suuui keybind` **and** a button on the ActionBars settings page | edit mode lives in `Core/` and legitimately extends `/suuui`; this mode is ActionBars' own, but its entry belongs with the other mode switch. Both, deliberately |
| Edit mode | **mutually exclusive** | `MoveableFrame`'s overlay sits at host+5 with mouse enabled. Two stacked overlays on one frame is not a state either was designed for |
| Combat | **pause, do not close** | `SetBinding` is refused; auto-save first, then resume where the player left off |

---

## 2. Architecture

New file `Plugins/ActionBars/Keybind.lua`. One module, no new plugin.

**State.** A transient setting is the single source of truth, copying `Core/ToggleUI.lua` exactly:
`Settings("_layout", "keybind_mode")`, transient, no shadow variable, every consumer subscribes with
`Settings:Watch(..., { immediate = true })`. That is what lets the slash command, the settings
button and the panel's close box disagree about nothing.

**Mutual exclusion.** A watcher on each key clears the other. Entering keybind mode calls
`ToggleUI:Disable()`; entering edit mode sets `keybind_mode` false.

**The overlay.** One per button, created lazily, parented to `btn:GetFrame()` and raised with
`SuuUI.UIRoot:RaiseAbove(overlay, btn:GetFrame(), 4)` → the button's own overlay (hotkey, count,
current-bar) is at host+4, so 4 puts us at host+5, above its text. Stay in `MEDIUM` strata so
`GameTooltip` (strata `TOOLTIP`) still renders above us.

**Re-attach.** `ActionBarGrid._syncButtons` **destroys and recreates** buttons on a slot or size
change, so overlays must be rebuilt on the grid's `CHILDREN_CHANGED` — the same signal
`applyOwnBindings` already hangs off (`ActionBars.lua:601`).

**Capture.** The overlay itself is the keyboard catcher: `EnableKeyboard(true)` +
`SetPropagateKeyboardInput(false)` on `OnEnter`, `EnableKeyboard(false)` on `OnLeave`. Reuse
`Components/KeyCapture.lua`'s ignore list and **extend it**: bare `LSHIFT/RSHIFT/LCTRL/RCTRL/LALT/
RALT/UNKNOWN`, plus **any key name containing `META` or `COMMAND`**. A pattern rather than exact
tokens, because the macOS Cmd token was never captured (see Phase 0's open item) and a bare Cmd
must never become a binding. ElvUI's list has this same hole.

**Write.** `InCombatLockdown()` gate → `GetBindingAction(keyString)` conflict check → confirm if
owned → `SetBinding(keyString, command)` → done. Nothing else: `UPDATE_BINDINGS` does the rest.

**Two API additions.** `ActionButton` and `StanceButton` have `SetBinding` but no reader; add
`GetBinding()` returning the command string. No overlay accessor is needed — the keybind overlay
parents to the button frame, not to the private `_overlay`.

---

## 3. Phases

### Phase 1 — harness surface
Model `SetBinding`, `GetBindingKey` (as varargs), `SetBinding(key)` unbind form, `LoadBindings`,
`SaveBindings`, `GetCurrentBindingSet`, `GetBindingAction`, and a settable combat state.

**The harness must model `SetBinding` EMITTING `UPDATE_BINDINGS` itself.** Without that, the spec
"one `SetBinding` re-routes every bar" asserts something that was already true and cannot go red.
Same lesson as modelling `ActionBarController`'s re-show before writing the suppression witness.

Model the combat refusal as **return `false`**, not as an error — a harness that raises would let a
`pcall` wrapper look correct.

### Phase 2 — `GetBinding()` on `ActionButton` and `StanceButton`
Trivial accessor, its own phase so the mutation run pins it.

### Phase 3 — mode state and entry points
The transient setting, `Settings:Watch` plumbing, `/suuui keybind`, the ActionBars settings button,
and mutual exclusion with edit mode in both directions.

Spec the exclusion as a **pair** of assertions in one test, so narrowing it to one direction turns
the test red rather than quietly allowing stacked overlays.

### Phase 4 — the per-button overlay (concept-faithful)
Wash, 1px ring, the full-length key chip, the top-left multi-bind dot, the tooltip listing every
binding. Colours from the concept: accent `colorAccent` @ `.20` armed, `colorWarning` @ `.18`
pending, `colorSuccess` @ `.18` committed, `colorDanger` @ `.18` cleared, `colorAccent` @ `.08`
eligible-but-not-hovered.

The chip shows the **unabbreviated** key, deliberately: `abbreviateKey` renders `SHIFT-1` as `S1`,
which is right for a learned hotkey and useless when confirming what just bound.

### Phase 5 — capture, conflict, write, clear
Key capture with the extended ignore list, `GetBindingAction` pre-check and the confirm step,
`SetBinding`, and `ESC` iterating **every** key from `GetBindingKey`.

The clear path needs its own spec asserting a **multi-key** button ends with none left — a
single-key fixture passes whether or not the loop iterates.

### Phase 6 — the panel
`Layout:CreateWindow` per `Core/EditPanel.lua`: lazily built, draggable, close box exits the mode.
Hint copy, changed/bound counters, the per-character checkbox, `Save`, `Discard`, `Clear all`.

`Discard` is `LoadBindings(GetCurrentBindingSet())`. The per-character checkbox must refuse to flip
with unsaved changes pending, or it silently discards them.

### Phase 7 — combat
`PLAYER_REGEN_DISABLED` → auto-save, flatten every overlay to the dark wash, panel reads
`Paused — in combat`. `PLAYER_REGEN_ENABLED` → resume in place. The mode does **not** close.

### Phase 8 — docs
Steering files, plus a spec file of this module's own following the `Dock` / `ActionBarGrid`
precedent.

---

## 4. What the suite cannot check — in-game only, BY CONSTRUCTION

The harness **records** override bindings and state drivers and never **evaluates** them. So:

- **"the bound key actually fires the right action"** is an in-game check. A key that does nothing
  points at the click PHASE, not the binding — the invariant that has produced "looks perfect, does
  nothing" twice in this project.
- **"`SetBinding` really fires `UPDATE_BINDINGS` on the live client"** is measured in Phase 0 and
  modelled in Phase 1; the model is a restatement of the measurement, not evidence for it.
- The macOS **Cmd token** was never captured — the probe used the propagate mode that fires
  nothing. Mitigated by the `META`/`COMMAND` substring rule rather than left open.

Do not report a binding or paging change as verified because the suite is green.
