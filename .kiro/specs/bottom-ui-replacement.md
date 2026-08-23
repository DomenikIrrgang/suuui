# Bottom UI Replacement

Replaces everything Blizzard draws along the bottom edge: action bars and their art, the
micro menu, the bag bar, the experience bar and the reputation watch bar, plus the
stance/pet/possess bars that live in the same cluster.

Concept and the option set it came from: artifact `suuui-bottom-ui-replacement-concept`.

---

## Locked decisions

| # | Area | Choice |
|---|---|---|
| 1 | Button style | **A2 seamless grid, on a glass plate.** No per-button border. One translucent gradient plate with hairline `colorBorder` dividers between cells. |
| 2 | Arrangement | **B3 hybrid dock.** Bar 1 publishes attach points; every other bar, the XP bar and the rep bar carry an `Attach To` dropdown (dock / detached with own position + width). |
| 3 | Button engine | **E2 own secure buttons.** New `Components/ActionButton.lua` on `SecureActionButtonTemplate`; Blizzard's action *system* stays the data source. |
| 4 | Micro menu | **C2 glyph + short label**, with a `micro_show_labels` toggle that drops the labels and collapses it to glyph-only (C1). Each entry is its own field in the bar's `left` section. |
| 5 | Icon art | **I2 custom TGA atlas** in `Media/`, authored the way `Media/generate_logo.py` authors the logo. |
| 6 | XP bar | **X3 `StatusBar` with readout slots** (left/center/right dropdowns) plus a rested ghost fill. |
| 7 | Reputation bar | **R1 its own bar, identical in style and code path to the XP bar.** |
| 8 | Bag bar | **G1 one data bar field** — free slots, click toggles bags, tone by threshold. |
| 9 | Stance / pet / possess | **S1 own moveable bars** in the same style, auto-hidden when empty. |

---

## Phase 0 — verify the client before writing any code

This is an Anniversary client and it has already contradicted assumptions once
(`EditModeManagerFrame` exists, `TemporaryEnchantFrame` does not). **Every global named in
this spec is a hypothesis until these run.** Each line is kept under ~250 characters
because WoW's chat edit box truncates past 255 and fails with a syntax error.

```lua
/run for _,n in ipairs({"MainMenuBar","MainMenuBarArtFrame","MultiBarBottomLeft","MultiBarBottomRight","MultiBarLeft","MultiBarRight"}) do print(n,_G[n] and "Y" or "-") end
/run for _,n in ipairs({"MainMenuBarLeftEndCap","MainMenuBarRightEndCap","MainMenuExpBar","ExhaustionTick","ReputationWatchBar","MainMenuBarMaxLevelBar"}) do print(n,_G[n] and "Y" or "-") end
/run for _,n in ipairs({"StanceBarFrame","ShapeshiftBarFrame","PetActionBarFrame","PossessBarFrame","KeyRingButton","MainMenuBarBackpackButton"}) do print(n,_G[n] and "Y" or "-") end
/run print(#(MICRO_BUTTONS or {}),table.concat(MICRO_BUTTONS or {},","))
/run local t=UIParent:CreateTexture() print(t.SetGradient and "grad" or "-",t.SetGradientAlpha and "gradA" or "-",MainMenuBar and MainMenuBar:GetNumPoints())
/run print(NUM_ACTIONBAR_BUTTONS,NUM_ACTIONBAR_PAGES,GetActionBarPage(),HasAction(1),GetActionInfo(1))
```

### Round 1 results — recorded 2026-08-23

| Probe | Result |
|---|---|
| Bars | `MainMenuBar` **Y** · `MainMenuBarArtFrame` **Y** · `MultiBarBottomLeft` **Y** · `MultiBarBottomRight` **Y** · `MultiBarLeft` **Y** · `MultiBarRight` **Y** |
| Art / watch bars | `MainMenuBarLeftEndCap` **Y** · `MainMenuBarRightEndCap` **Y** · `MainMenuBarMaxLevelBar` **Y** · `MainMenuExpBar` **absent** · `ExhaustionTick` **absent** · `ReputationWatchBar` **absent** |
| Class bars / bags | `KeyRingButton` **Y** · `MainMenuBarBackpackButton` **Y** · `StanceBarFrame` **absent** · `ShapeshiftBarFrame` **absent** · `PetActionBarFrame` **absent** · `PossessBarFrame` **absent** |
| Micro list | `#MICRO_BUTTONS` = **0** |
| Gradient / anchors | `SetGradient` **present**, `SetGradientAlpha` **absent** · `MainMenuBar:GetNumPoints()` = **1** |
| Action API | `NUM_ACTIONBAR_BUTTONS` = **12** · `NUM_ACTIONBAR_PAGES` = **6** · `GetActionBarPage()` = **1** · `HasAction(1)` = **true** · `GetActionInfo(1)` = `"spell", 143, "spell"` |

**Four of the six contradicted this plan, which is why Phase 0 exists.** This client is a
hybrid: it carries the Classic bar-art names (`MainMenuBarArtFrame`, `MainMenuBarMaxLevelBar`,
`KeyRingButton`) but *not* the Classic watch-bar or class-bar names — consistent with
`EditModeManagerFrame` being present. Treat every "absent" above as **a dead line in this
spec**, not as a frame to hide.

Settled by round 1:

- **The glass gradient works, in the modern form only.** `SetGradient` is present and
  `SetGradientAlpha` is gone, so `Backdrop.Glass` uses
  `SetGradient(orientation, CreateColor(…), CreateColor(…))`. Keep the flat-fill fallback in
  the code for a client without it, but this client does not take that path.
- **The action API is all there.** 12 buttons across 6 pages, and `GetActionInfo` returns
  `(type, id, subType)`. `ActionButton` needs no shape probing.
- **`MainMenuBar` has exactly one anchor point**, so the store-original-and-restore requirement
  under Suppression is satisfiable.

### Round 2 results — Phase 0 COMPLETE

| Probe | Result |
|---|---|
| Watch bars | `StatusTrackingBarManager` **Y** · `MainStatusTrackingBarContainer` **Y** · `SecondaryStatusTrackingBarContainer` **Y** · `ReputationStatusBar` **absent** · `ExhaustionLevelFillBar` **absent** |
| Class bars | `StanceBar` **Y** · `PetActionBar` **Y** · `PossessActionBar` **Y** · `OverrideActionBar` **Y** · `MainMenuBarVehicleLeaveButton` **Y** · `MultiCastActionBarFrame` **absent** |
| Micro buttons | **12 present**: Character, Spellbook, Talent, QuestLog, Socials, Guild, LFG, PVP, WorldMap, MainMenu, Help, Collections. `LFDMicroButton` **absent** |
| Containers / colour | `MicroMenu` **Y** · `MicroButtonAndBagsBar` **Y** · `CreateColor` **Y** · `type(MICRO_BUTTONS)` = **nil** · `UnitLevel("player")` = **11** |

Four things this settles, and each removes a branch from the design:

- **The XP and reputation bars are the modern status-tracking system, and the player is level
  11** — so `MainMenuExpBar` being absent is the frame tree, not a max-level artifact. The
  client owns one `StatusTrackingBarManager` with **two** containers and swaps XP / rep / honor
  between them. Suppression targets the manager, which is also the frame that re-shows itself on
  a level or reputation change, so the guarded-`OnShow` hook goes there.
- **R1 is validated by the client's own architecture.** Two SuuUI bars is not a departure from
  what the client does; it is the same two containers, always both visible instead of swapped.
- **`MICRO_BUTTONS` is `nil`, not empty**, and `MicroMenu` / `MicroButtonAndBagsBar` exist. So
  the micro menu is the modern container architecture: enumerate the 12 confirmed globals by
  name rather than reading a list global that does not exist on this client.
- **`CreateColor` is present**, closing the gradient question completely:
  `SetGradient(orientation, CreateColor(…), CreateColor(…))` is the form to write.

`MultiCastActionBarFrame` absent is correct rather than surprising — that is the WotLK shaman
totem bar and this is TBC. `OverrideActionBar` and `MainMenuBarVehicleLeaveButton` existing means
the vehicle/override path is real on this client and belongs in the S1 possess work.

**One glyph is missing from the drafted set.** `CollectionsMicroButton` has no glyph in the
concept's 13. It needs one — a paw print reads instantly at 16 units in a single-weight stroke
and matches the rest of the set. See **Icon atlas** below for the corrected count.

Still to verify, but at its call site in Phase 8 rather than as another probe round:
`GetWatchedFactionInfo` changed shape across client generations (a multi-return classically, a
table in 11.0). Read it defensively and branch on the shape.

### Round 3 results — the action slot mapping, recorded 2026-08-23

The plan originally named no slot mapping at all, which made every bar past bar 1 unwritable.
Probe: `for _,n in ipairs({"ActionButton1","MultiBarBottomLeftButton1",…}) do local b=_G[n]
print(n, b and b.action or "-") end`

| Bar | Button 1's `action` | Block |
|---|---|---|
| `ActionButton1` (`MainMenuBar`) | **1** | 1–12, **paged** |
| `MultiBarRightButton1` | **25** | 25–36 |
| `MultiBarLeftButton1` | **37** | 37–48 |
| `MultiBarBottomRightButton1` | **49** | 49–60 |
| `MultiBarBottomLeftButton1` | **61** | 61–72 |

This is the classic-era layout, and it carries **one consequence the plan had not stated: bar
1's six pages overlap the other four bars' fixed blocks.** With `NUM_ACTIONBAR_PAGES = 6`,
pages 1–6 are slots 1–12, 13–24, 25–36, 37–48, 49–60, 61–72 — so paging bar 1 to page 3 shows
exactly the slots `MultiBarRight` owns. Three design consequences:

- **Only bar 1 takes a state driver.** Bars 2–5 are fixed to their block and need no
  `_onstate-page` snippet, which removes four secure headers from Phase 5.
- **Two SuuUI buttons may legitimately address one slot**, so `ACTIONBAR_SLOT_CHANGED` must
  repaint *every* button watching that slot, not the first one found. A slot→buttons multimap,
  not a slot→button map.
- **Slots 13–24 (page 2) have no dedicated bar**, reachable only by paging bar 1. That matches
  Blizzard and is not a gap to fill.

Unverified and deliberately deferred to its call site in Phase 6: whether druid form / rogue
stealth swaps drive `bonusbar` (slots 73+) or a page. Read `GetBonusBarOffset` defensively
there rather than adding another probe round now.

### Round 4 result — the micro menu's parentage, recorded 2026-08-23

Asked because Phase 4b hides `MainMenuBar`, and if the micro menu were a child of it the player
would lose the character pane, the spellbook and the bags until Phase 7 — survivable via Esc, C
and B, but not something to discover after the fact.

```
/run local m=MicroMenu or MicroButtonAndBagsBar print(m and m:GetName(), m and m:GetParent() and m:GetParent():GetName())
```

→ `MicroMenu MicroMenuContainer`

- **The micro menu is NOT under `MainMenuBar`.** Hiding the bar cluster leaves it alone, so
  Phase 4b suppresses the bars without collateral damage. Confirmed rather than assumed.
- **`MicroMenuContainer` exists and is new information** — it appears in neither Phase 0 round.
  It is the frame Phase 7 has to suppress, and `MicroMenu` is its child, so the candidate list
  for that phase is `{ "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }` with the
  container first. The harness models this parentage now, so a Phase 7 spec that hides the
  container gets the real cascade rather than a guess.

### Round 5 result — the binding command families, recorded 2026-08-23

Asked because a bar reads its hotkey text from the client's binding command, and a wrong family
shows the WRONG KEY on a working button — a defect that survives every local test, because the
harness only knows what the addon told it.

```
/run for _,n in ipairs({"ActionButton1","MultiBarBottomLeftButton1",…}) do local b=_G[n] print(n,b and b.buttonType) end
```

| Frame | `buttonType` | Slot block |
|---|---|---|
| `ActionButton1` | **nil** | 1–12 |
| `MultiBarBottomLeftButton1` | `MULTIACTIONBAR1BUTTON` | 61–72 |
| `MultiBarBottomRightButton1` | `MULTIACTIONBAR2BUTTON` | 49–60 |
| `MultiBarLeftButton1` | **`MULTIACTIONBAR4BUTTON`** | 37–48 |
| `MultiBarRightButton1` | **`MULTIACTIONBAR3BUTTON`** | 25–36 |

**The numbering does not follow the frame names in the order it looks like it should.**
`MultiBarLeft` is MULTIACTIONBAR**4** and `MultiBarRight` is MULTIACTIONBAR**3** — the reverse of
the obvious pairing, and the obvious pairing is what Phase 5a shipped until this probe ran. The
measured table is now pinned by a spec so a later tidy-up cannot renumber it back.

`ActionButton1.buttonType` being nil is expected rather than missing: the main bar is the DEFAULT
family, so its buttons set no override. `ACTIONBUTTON1` is the client's own binding name for it,
and it is the only entry in the table resting on the documented name rather than on a reading.

### Round 6 result — there are EIGHT bars, and the buttons are not where Phase 0 thought

Two findings that between them invalidated the suppression list and the bar table.

**1. The buttons live in `MainActionBar`, not `MainMenuBar`.** Walking up from the button:

```
/run local f=ActionButton1 while f do print(f:GetName() or "?", tostring(f:IsShown())) f=f:GetParent() end
```
→ `ActionButton1` → `MainActionBarButtonContainer1` → `MainActionBar` → `UIParent`

Both `MainMenuBar` and `MainActionBar` exist on this client. Phase 0 probed for the first, found
it, and the plan took it for the bar — but it only carries the art. Suppression removed the
gryphons and left all twelve buttons on screen, while `IsSuppressed("MainMenuBar")` reported
success. **Existing is not the same as holding the buttons**, and only the parent chain settles it.

Two consequences beyond adding a name. Candidate lists must hide EVERY name that exists rather
than the first: these two coexist, so first-match-wins hid one and left the other. And suppression
now ends with a `Verify()` self-check that asks the WITNESS BUTTONS directly — hiding a container
is the means, a button off the screen is the end, and nothing was checking the end.

**2. This client has EIGHT bars, not five.**

```
/run for _,n in ipairs({"MultiBar5","MultiBar6","MultiBar7"}) do print(n,_G[n] and "Y" or "-") end print(NUM_ACTIONBAR_PAGES,tostring(HasAction(73)),tostring(HasAction(120)))
```
→ `MultiBar5 Y` · `MultiBar6 Y` · `MultiBar7 Y` · pages **6** · `HasAction(73)` **false**

`MultiBar5`, `MultiBar6` and `MultiBar7` all exist, and Blizzard's own options list them, so they
are real bars a player can enable. Phase 0 probed the five bars TBC is known for and stopped.
They are now suppressed and in the witness list.

**`HasAction(73)` being false bounds nothing** — it means slot 73 is EMPTY, not absent. So the slot
blocks and binding families for bars 6–8 are still **UNMEASURED**, and the harness deliberately
leaves their buttons' `action` attribute unset so no spec can assert a guess. Measure with the
Round 3 / Round 5 probe shape before adding them to the plugin's bar table:

```
/run for _,n in ipairs({"MultiBar5Button1","MultiBar6Button1","MultiBar7Button1"}) do local b=_G[n] print(n,b and b.action,b and b.buttonType) end
```

**Also still unassigned: slots 13–24**, which is page 2 of the paged bar and the one block with no
frame of its own. SuuUI draws its own buttons, so it can expose that block as a bar the client never
offered.

---

### Round 7 — read from ElvUI's source, not the client, recorded 2026-08-23

Phase 6's frame names were the fourth item on a list that had already been wrong three times, so
this round did not probe. It read **ElvUI**, which is bundled here and demonstrably correct on this
client — the same route that produced the Round 6 bar mapping. Four parallel read-only passes over
`AddOns/ElvUI`; no in-game step needed for most of it.

**The single finding that retro-explains every earlier surprise: this client has EDIT MODE.**

`Game/Shared/General/Core.lua:76`
```lua
E.hasEditMode = E.Retail or E.TBC or E.Wrath or E.Mists
```
`Game/TBC/Skins/EditorManager.lua:68` reads `_G.EditModeManagerFrame`, and it is loaded on TBC.

So this Anniversary build is a **modern-backend client wearing a TBC version number**, not the 2021
2.5.4. That is why `MainActionBar` coexists with `MainMenuBar`, why bars 6–8 exist, and why the
modern container names are the live ones. Every frame-name surprise in Rounds 1–6 has this one
cause. ElvUI selects names off exactly this flag:

```lua
MainActionBar = E.hasEditMode or nil,
[E.hasEditMode and 'StanceBar'   or 'StanceBarFrame']   = true,
[E.hasEditMode and 'PetActionBar' or 'PetActionBarFrame'] = true,
[E.hasEditMode and 'PossessActionBar' or 'PossessBarFrame'] = true
```

**The live names on this client are therefore `StanceBar`, `PetActionBar`, `PossessActionBar`** —
the `*Frame` spellings are ElvUI's Classic-Era branch and are dead here. That matches Round 2 and
contradicts Round 1, which is now explained rather than merely overruled.

**Which of these bars are real, from ElvUI's per-expansion visibility ladder** (`Defaults/Profile.lua:3158`).
The authors differentiated TBC from Classic on precisely this axis, which makes it the strongest
evidence in the tree:

| Conditional | Retail | Wrath | TBC | Classic | Conclusion |
|---|---|---|---|---|---|
| `vehicleui` | ✓ | ✓ | **✗** | ✗ | vehicles are NOT a TBC mechanic |
| `nopossessbar` | ✓ | ✓ | **✓** | ✗ | **possess IS real on TBC** |
| `nooverridebar` | ✓ | ✓ | ✓ | ✓ | indiscriminate — proves nothing |

**But `MainMenuBarVehicleLeaveButton` still EXISTS**, and this is the trap. ElvUI's
`CreateVehicleLeave()` is called unguarded at `ActionBars.lua:2043` and immediately does
`holder:Size(button:GetSize())` — a hard error on nil. ElvUI works here, so the frame is real. The
modern backend ships the button where the mechanic does not exist. Do not conclude "no vehicles" ⇒
"no frame"; Round 2's measurement was right.

`OverrideActionBar` is **UNCERTAIN** — every reference is either flavour-guarded away from TBC or
nil-safe, so ElvUI loading proves nothing. Gate anything override-related on an EXISTENCE check
rather than a flavour check.

**Data APIs, with return orders taken from ElvUI's destructuring sites rather than assumed:**

| Call | Returns |
|---|---|
| `GetShapeshiftFormInfo(i)` | `texture, isActive, isCastable, spellID` |
| `GetShapeshiftFormCooldown(i)` | `start, duration, active` — `active` is a **number**, tested as `active and active ~= 0` |
| `GetNumShapeshiftForms()` | count; forms are contiguous from 1 |
| `GetShapeshiftForm()` | active index, `0` for none |
| `GetPetActionInfo(i)` | `name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID` |
| `GetPetActionCooldown(i)` | `start, duration` |

**`isToken` is the detail that would have shipped a bug.** When true, `name` and `texture` are the
**names of globals**, not a display name and a texture path — the consumer must resolve them through
`_G`. Missing it draws blank icons on exactly the pet actions that are tokens (Attack, Follow, Stay).

**Binding families are counter-intuitive and are not what the frame names suggest:**

| Bar | Family |
|---|---|
| Stance | `SHAPESHIFTBUTTON1..N` — **not** `STANCEBUTTON` |
| Pet | `BONUSACTIONBUTTON1..N` — **not** `PETACTIONBUTTON` |

**Hiding rules.** The stance bar has **no class or spec check anywhere** — it is purely
`GetNumShapeshiftForms() == 0`, so a mage is a count of zero. The pet bar hides on the macro
conditional `[pet,nooverridebar,nopossessbar] show; hide`, never on a Lua `UnitExists` check. Pet
present-but-unusable is a **separate** mechanism that greys icons rather than hiding anything
(`PetHasActionBar()`), and collapsing the two gets one case wrong.

#### The open question this round could NOT close

**ElvUI does not build stance or pet buttons at all — it adopts Blizzard's and reskins them.** Zero
`SetAttribute` calls, zero `RegisterForClicks`, no LibActionButton involvement (which is not even
bundled inside ElvUI — it is a sibling addon folder). The entire working stance button is:

```lua
button = CreateFrame('CheckButton', name, bar, 'StanceButtonTemplate')
button:SetID(i)
```

So **the secure attribute set SuuUI needs to build its own stance/pet buttons is not recoverable
from disk** — it lives in Blizzard's templates, inside CASC, and there is no FrameXML dump on this
machine. It has to be read off the live frames.

Bind the button to a global once, then ask one short question per line — a long `/run` is awkward to
paste and the edit box caps at 255 characters:

```
/run B=StanceButton1
/dump B:GetAttribute("type")
```

**PROBED 2026-08-23: `StanceButton1:GetAttribute("type")` is EMPTY.** A real reading, not an error —
the same session answered `GetNumShapeshiftForms()` with `8`, so the bar was populated and `B` was
valid. Blizzard's stance button is **not** driven by the standard `SecureActionButtonTemplate`
`type`/`action` mechanism at all, so there is no attribute set for SuuUI to state. That closes the
question in the direction of the template, and is why the phase is built the way it is below.

`CastShapeshiftForm(1)` from a `/run` ran without a Lua error and had no visible effect. **PROBED
AGAIN 2026-08-23, bracketed, and the verdict is definitive: it is BLOCKED for tainted code.**
`GetShapeshiftForm()` read `7`, then `CastShapeshiftForm(3)`, then `GetShapeshiftForm()` read `7`
again — no error, no change, no action-blocked message. A silent no-op.

`/run` executes as TAINTED code, exactly like an addon's own handler, so this rules out SuuUI driving
a stance change from a plain `OnClick`. The template is not a convenience here, it is the only path.
Note the failure shape: **no error and no message, just nothing** — which is why this had to be
tested by reading the form back rather than by watching for a complaint.

`GetShapeshiftFormInfo`'s return order remains **unverified against the live client** and rests on
ElvUI's destructuring alone. `B:GetRegisteredClicks()` was not readable (the global had been cleared
by then), so stance press-versus-release is also unmeasured.

`8` forms was measured on a **PALADIN**, and the number is correct: on this client the shapeshift bar
carries **paladin AURAS** — Devotion, Retribution, Concentration, Shadow Resistance, Frost
Resistance, Fire Resistance, Crusader, Sanctity. Exactly eight.

**This bar is not "stances". It is whatever class mechanic the client hangs on the shapeshift API** —
warrior stances, druid forms, rogue stealth, priest shadowform, paladin auras. Naming it the stance
bar follows Blizzard's and ElvUI's terminology, not its actual scope. Two consequences: the count
must be READ and never assumed from a class (a paladin's 8 is as real as a warrior's 3), and the bar
matters for far more classes than the plan's "druid form swap" acceptance line implies.

`B:GetScript("OnClick") ~= nil` → **true**. Blizzard's stance button drives casting through a plain
SCRIPT, which is consistent with `type` being empty: there is no secure attribute path here at all.

The earlier `CastShapeshiftForm(1)` no-op is explained by the same finding — form 1 on a paladin is
Devotion Aura, which was almost certainly already active, so the call was a legitimate no-op rather
than a blocked one.

---

## The glass plate

"Glassy" is `Themes/` work, not a per-plugin literal. Reference is concept 02 of the chat
mockups: `linear-gradient(to bottom, rgba(12,14,18,.85), transparent)` over the world, with a
text shadow for legibility.

**WoW has no blur.** There is no `backdrop-filter` equivalent, so frosted glass is not
reachable and must not be promised. What reads as glass on this client is three things
together: a translucent dark fill, a vertical gradient, and a one-pixel lighter sheen along
the top edge.

New primitive, alongside `Apply` / `Pill` / `Circle` in `Components/Backdrop.lua`:

```lua
SuuUI.Backdrop.Glass(frame, { from, to, sheen, border, borderWidth, inset })
-- returns { SetColors, Refresh, Destroy }
```

- Two stacked textures: the gradient body, and a `Pixel.Line`-thick sheen at the top.
- `inset = 0` semantics identical to `Apply` — a borderless surface must cover its whole box.
- Where the gradient API is absent, draw the body as a flat fill at the midpoint alpha.

New tokens, added to **`Themes/Default.lua`, `Themes/Modern.lua` AND
`SettingsUI/Controls/ThemeTokens.lua`** (a token nothing exposes is a control that silently
does nothing):

| Token | Form | Meaning |
|---|---|---|
| `opacityGlass` | primitive | alpha at the plate's dense edge (~0.80 Default, ~0.85 Modern) |
| `opacityGlassFade` | primitive | alpha at its open edge (~0.30) |
| `opacityGlassSheen` | primitive | the top hairline's alpha (~0.10) |
| `colorGlass` | derivation | `colorGray950` @ `opacityGlass` |
| `colorGlassFade` | derivation | `colorGray950` @ `opacityGlassFade` |
| `colorGlassSheen` | derivation | `colorGray100` @ `opacityGlassSheen` |

Do **not** reuse `colorBarTrack`. It is a bar's empty track, and sharing it would mean a
retint of every health bar's background silently retints every action bar plate.

The plate takes **no mouse input**. Buttons enable their own; a plate that swallowed clicks
would make the gaps between buttons unclickable in the world.

---

## Combat lockdown — the constraint that shapes everything

A frame built from a secure template is protected, protection propagates **down** to
descendants and the refusal propagates **up**: while `InCombatLockdown()` is true the client
silently refuses `SetSize` / `SetWidth` / `SetHeight` / `SetPoint` / `Show` / `Hide` on any
frame whose subtree holds a protected one, and the player gets `Interface action failed
because of an AddOn`. This cost ten days on `UnitClickArea`; see "Protected Actions Go Through
A Secure Component" in `WOW_API_ENCAPSULATION.md`.

Rules for every bar in this feature:

1. **Geometry settles out of combat only.** Any settings change that resizes a bar checks
   `InCombatLockdown()`, sets a deferred flag, returns, and catches up on
   `PLAYER_REGEN_ENABLED`. Do not attempt the call and lose — a refused call costs the player
   a chat error you already knew was coming. `UnitFrame:_syncClickArea` is the reference.
2. **The dock grows away from the buttons.** A B3 dock that resized *around* its children
   would be refused mid-combat exactly when a bar shows or hides. Attached children extend the
   dock's bounding box outward, and the dock reports `coreInset` so `MoveableFrame` keeps the
   player's stored position meaning "where my buttons are".
3. **Nothing non-protected that resizes at runtime may contain a button.** Wrappers, dividers
   and the glass plate are siblings of the button grid or its ancestors — never a parent that
   itself resizes in combat.
4. **Attributes are stated once, at construction.** `SetAttribute` on a protected frame is
   refused in combat, which is why paging goes through a secure state driver instead of Lua.

---

## New components

### `Components/ActionButton.lua`

`SecureActionButtonTemplate`, attributes `type="action"` and `action=<slot>` set at
construction. The template's own handler performs the click; **never
`SetScript("OnClick")`** — observe through `PostClick` and emit `CLICKED`.

| Concern | Route |
|---|---|
| Icon / macro name / count | `GetActionTexture`, `GetActionText`, `GetActionCount` |
| Cooldown swipe | `GetActionCooldown` into a Blizzard `Cooldown` frame — same sanctioned exception `AuraIcon` already takes |
| Usable / out of mana | `IsUsableAction` |
| Out of range | `IsActionInRange`, on one **shared throttled ticker** for every button (never a per-button `OnUpdate`) |
| Current / auto-repeat | `IsCurrentAction`, `IsAutoRepeatAction` |
| Empty slot | `HasAction` |
| Drag and drop | `RegisterForDrag("LeftButton")`, `OnDragStart` → `PickupAction`, `OnReceiveDrag` → `PlaceAction`; respect `LOCK_ACTIONBAR` |
| Hotkey text | `GetBindingKey("ACTIONBUTTON<n>")`, refreshed on `UPDATE_BINDINGS` |

Events: `ACTIONBAR_SLOT_CHANGED`, `ACTIONBAR_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_USABLE`,
`ACTIONBAR_UPDATE_STATE`, `ACTIONBAR_PAGE_CHANGED`, `SPELL_UPDATE_COOLDOWN`,
`UPDATE_SHAPESHIFT_FORM`, `UPDATE_BINDINGS`, `PLAYER_ENTERING_WORLD`. Register the **union**
on one frame and dispatch to the buttons that care, as `DataBarWidget` does — not one event
frame per button.

Emits `CLICKED`, `MOUSE_ENTER`, `MOUSE_LEAVE`, `SIZE_CHANGED`. Deliberately **no**
`SetEnabled`: disabling means dropping mouse input, which the client can refuse on a
protected frame, and a `SetEnabled` that cannot be honoured when it matters is worse than
none — same reasoning as `StatusBar` and `UnitClickArea`.

### `Components/ActionBarGrid.lua`

Rows × columns of `ActionButton`s over one `Backdrop.Glass` plate, with hairline dividers
between cells. Owns the A2 look; owns no action slots (the plugin assigns them). Geometry
changes route through the lockdown guard in rule 1.

### Paging

A `SecureHandlerStateTemplate` header per bar plus `RegisterStateDriver(header, "page", …)`
with an `_onstate-page` snippet that rewrites its children's `action` attributes. This is the
only paging mechanism that works in combat, and stances/forms/stealth are by definition
in-combat transitions. Warrior stances, druid forms and rogue stealth all drive it.

### `DataField` gains an optional `icon`

C2 is an icon plus a short label. `DataField` today is deliberately **one font string** — the
prefix and value share it so the two cannot sit on different baselines. An icon is a texture
placed by the stack container, so it introduces no baseline problem, and extending the
existing field keeps the rail, the hover fill, the hug and the tone in one place.

- New props: `icon` (texture path), `iconCoords` (atlas `SetTexCoord`), `iconSize`.
- `SetIcon` / `SetIconShown`. With the label empty the field hugs to icon + `spaceMd` either side.
- **Coordination hazard:** `Components/DataField.lua` and its spec `Tests/spec/44_datafield_spec.lua`
  are currently modified in the working tree by the addon-buttons work. Rebase on whatever
  landed before touching either, and do not edit them while another agent is mid-mutation.

---

## Plugins

| Plugin id | Owns |
|---|---|
| `action_bars` | the bars, the dock attach points, the stance/pet/possess bars, Blizzard suppression for the whole cluster |
| `micro_menu` | one registered DataBar widget per micro button, the labels toggle, the atlas |
| `watch_bars` | the XP bar and the reputation bar (one plugin, one code path, two instances) |
| `bag_bar` | the `BAGS n` DataBar field |

### Suppression

Hidden with the **guarded-`OnShow` hook** from `plugin-authoring.md` ("A frame that re-shows
itself") and restored in `onDisable`. Never `UnregisterAllEvents` (nothing can enumerate a
frame's registrations, so `onDisable` could never hand it back). Never `SetParent(nil)`.
Clear the suppression flag **before** the restoring `Show()`.

`MainMenuBar` is layout-managed on this client, so suppression and any reposition need the
`hooksecurefunc` re-assert pattern `Plugins/DataBar/DataBar.lua` already uses, consulting a
`managed` table on every call because the hook cannot be uninstalled.

**Resolve every frame by a CANDIDATE LIST, never by a literal name.** The Phase 0 results above
are a snapshot of one client build, and the Classic clients have historically been given the
modern APIs in stages — this build is already mid-migration, which is exactly why it answers to
`MainMenuBarArtFrame` *and* `StatusTrackingBarManager` in the same breath. A patch that
backports one more subsystem renames a frame out from under a literal, and the failure is
silent: the suppression simply stops hiding something. So each entry is an ordered list of names
and the first one that exists wins:

```lua
-- Ordered modern-first, classic-second. An entry that resolves to nothing is skipped with a
-- SuuUI.Debug line rather than raising -- an absent frame is a client generation, not a bug.
local TARGETS = {
    exp_bar    = { "StatusTrackingBarManager", "MainMenuExpBar" },
    rep_bar    = { "ReputationWatchBar" },
    stance_bar = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" },
    pet_bar    = { "PetActionBar", "PetActionBarFrame" },
    possess    = { "PossessActionBar", "PossessBarFrame" },
}
```

Confirmed on the build measured in Phase 0:

| Group | Resolves to here |
|---|---|
| Bar art | `MainMenuBarArtFrame`, `MainMenuBarLeftEndCap`, `MainMenuBarRightEndCap`, `MainMenuBarMaxLevelBar` |
| Action bars | `MainMenuBar`, `MultiBarBottomLeft`, `MultiBarBottomRight`, `MultiBarLeft`, `MultiBarRight` |
| Micro menu | `MicroMenu`, `MicroButtonAndBagsBar`, and the 12 named `*MicroButton` globals |
| Bags | `MainMenuBarBackpackButton`, `CharacterBag0..3Slot`, `KeyRingButton` |
| XP / rep | `StatusTrackingBarManager` + its two containers (**not** `MainMenuExpBar`) |
| Class bars | `StanceBar`, `PetActionBar`, `PossessActionBar`, `OverrideActionBar`, `MainMenuBarVehicleLeaveButton` |

**Re-run the Phase 0 probes after any client patch** and diff the answers against the tables
above before trusting this section.

### Micro menu ordering

Each entry is its own widget in `section = "left"`, at `order` 10, 20, 30 … so a later reorder
UI has room. **The `left` section is currently empty**, so the micro menu owns it outright and
collides with nothing — measured in the tree, not assumed. The existing built-ins all live
elsewhere, and all four now sit in `Plugins/DataBar/` after the built-in widget fold:

| Widget | File | Section | Order |
|---|---|---|---|
| Clock | `Plugins/DataBar/TimeWidget.lua` | `center` | 100 |
| Addon buttons | `Plugins/DataBar/AddonButtonsWidget.lua` | `right` | 190 |
| Latency | `Plugins/DataBar/LatencyWidget.lua` | `right` | 200 |
| Framerate | `Plugins/DataBar/FpsWidget.lua` | `right` | 210 |

### Settings, per the schema conventions

Sections become accordions and grouping is derived from order, so entries before the first
`section` stay always-visible — that is where each plugin's `enabled` toggle belongs. Bar
dimensions are **plugin settings** with a schema `default`, not theme tokens; spacing, font
steps and the glass tokens are theme tokens. Positions are `type="position"`.

`action_bars` uses `subtabs`, one tab per bar (`Bar 1`…`Bar N`, `Stance`, `Pet`, `Possess`),
each key declared **once** inside its tab. Per bar: `enabled`, `attach` (dock/detached),
`buttons`, `rows`, `button_size`, `spacing`, `width` (dead while docked, via `enabledIf`),
`show_hotkeys`, `show_macro_text`, `show_count`, `position`.

---

## Icon atlas

Follow `Media/generate_logo.py` exactly: geometry defined by numbers in the script, rendered
with Pillow, and a `verify()` that asserts the rendered pixels rather than trusting a comment
claiming precision.

- `Media/generate_micro_icons.py` → `Media/micro-icons.tga`, uncompressed 32-bit, power-of-two
  (a 4×4 grid of 32×32 glyphs in a 128×128 sheet).
- Monochrome white-on-transparent, drawn with `SetVertexColor` so the glyph follows
  `colorTextMuted` at rest and `colorAccent` on hover — the tint is what keeps the art
  theme-aware.
- Glyph order fixed in the script and mirrored as a Lua coord table. **14 glyphs**, which still
  fits the 4×4 sheet: Char, Spells, Talents, Quests, Social, Guild, PvP, LFG, Map, Menu, Help,
  **Collections**, plus Bags and Keys for section 8. Collections was missing from the concept's
  13 and is drawn as a paw print.
- **One glyph per micro button that exists, not per button that might.** `LFDMicroButton` is
  absent on this build and `MICRO_BUTTONS` is `nil`, so the Lua side maps the 12 confirmed
  globals to coords and any button a later client adds falls back to a text-only field until a
  glyph is drawn for it.
- Neither the `.tga` nor the `.py` goes in the `.toc` — the `.toc` takes `.lua` only.

---

## Stance, pet and possess bars — Phase 6

Live frame names on this client, per Round 7: **`StanceBar`**, **`PetActionBar`**,
**`PossessActionBar`**. Vehicles are not a mechanic here, but
`MainMenuBarVehicleLeaveButton` exists anyway — there is nothing to replace, so Phase 6 leaves it
alone rather than building a bar for a mechanic the client does not have. `OverrideActionBar` is
gated on an **existence check**, never a flavour check.

### The count must not vary — this is the constraint that shapes the phase

A stance swap and a pet summon are **in-combat events by their nature**: a warrior swaps stance
mid-fight, a hunter's pet dies and is revived mid-fight. `ActionBarGrid._apply()` refuses in combat
and catches up on `PLAYER_REGEN_ENABLED`, which is correct for bars 1–8 — a player does not resize a
bar mid-pull — and **wrong here**, because it would leave the bar showing the previous form's buttons
until the fight ended.

Creating a frame and calling `SetPoint` are both protected, so a bar whose button count changes
cannot do it in combat at all. The resolution, which is what ElvUI does and is proven on this client:

- **Build the maximum set once**, out of combat. `NUM_STANCE_SLOTS` (10) and
  `NUM_PET_ACTION_SLOTS` (10) are array bounds, not what a class has.
- **Surplus buttons are scaled to `0.00001` with alpha 0 — never `Hide()`n.** Hiding a secure button
  is refused in combat; scaling is not.
- **The container is shown and hidden by `RegisterStateDriver`**, inside the secure environment. The
  pet bar's conditional on this client is `[pet,nooverridebar,nopossessbar] show; hide`.
- The stance bar's hide condition is **`GetNumShapeshiftForms() == 0`** and nothing else. No class
  check, no spec check — a mage is a count of zero.

`Paging.lua` already owns exactly this mechanism (`SecureHandlerStateTemplate` + a driver + a
snippet reading frame refs), so this is a second consumer of a proven pattern rather than new risk.

### Button construction — SETTLED by the Round 7 probe

`StanceButton1` has **no `type` attribute** (probed). So there is no secure attribute set to state,
and `SecureActionButtonTemplate` — which every `ActionButton` in Phases 1–5 uses — has nothing to
work with here. The two bars therefore differ, and the difference is not arbitrary:

**Stance: create our OWN buttons from `StanceButtonTemplate`.** This is what ElvUI does, and it is
NOT the same as adopting Blizzard's bar:

```lua
button = CreateFrame('CheckButton', ourName, ourBar, 'StanceButtonTemplate')
button:SetID(i)
```

SuuUI creates the frame, owns its parent, position, size and place in the glass plate. Only the click
plumbing is borrowed — precisely the part that is unrecoverable from disk. The template also supplies
`.icon`, `.cooldown`, `.checked` and `.HotKey` as child references, which is what makes restyling to
match bars 1–8 tractable.

**Because we create our own, `StanceBar` CAN still be suppressed.** Blizzard's buttons stay inside
the hidden container; ours are separate frames. An earlier draft of this section said suppression had
to leave the frame alone — that was wrong, and it only applies to the pet bar.

**Pet: ADOPT Blizzard's `PetActionButton1..N`** and reparent them into our container. There is no
`PetActionButtonTemplate` route that gives a fresh button its slot the way `SetID` does for stance, so
this is the one place SuuUI reskins rather than builds. **`PetActionBar` must therefore NOT be
suppressed** — its buttons are the ones we are using, and hiding the parent would take them with it.
Reparenting them out is what removes them from Blizzard's bar.

**Autocast is a visual no existing component provides**: `autoCastAllowed` shows the overlay,
`autoCastEnabled` spins it, via the overlay's own `:ShowAutoCastEnabled(bool)` on this client. The
`AutoCastShine_*` globals are the dead Classic branch.

Do NOT invent a secure attribute for either bar. A wrong frame name cost three rounds; a wrong secure
attribute costs a bar that silently does nothing when clicked, which is exactly the failure Phase 3's
press-versus-release bug already produced once.

### What is already in place

- The harness models the full surface: `GetNumShapeshiftForms`, `GetShapeshiftForm`,
  `GetShapeshiftFormInfo`, `GetShapeshiftFormCooldown`, `CastShapeshiftForm`, `GetBonusBarOffset`,
  `GetPetActionInfo`, `GetPetActionCooldown`, `GetPetActionSlotUsable`, `PetHasActionBar`,
  `IsPetAttackAction`, `TogglePetAutocast`, plus `H.setStanceForm` / `H.setPetAction` staging. See
  TESTING.md for the four traps it deliberately does not soften.
- `ActionButton` already registers `UPDATE_SHAPESHIFT_FORM` and full-refreshes on it.
- `Suppress.lua` reserves these frames. `StanceBar` and `PossessActionBar` **can** be suppressed,
  because our stance buttons are our own frames. `PetActionBar` **cannot** — we reparent its buttons
  out, and hiding the parent would take them with it.

### Still open

- **The pet autocast overlay is a visual no existing component provides.** `autoCastAllowed` shows
  it, `autoCastEnabled` spins it. On this client ElvUI drives it via the overlay's own
  `:ShowAutoCastEnabled(bool)`; the `AutoCastShine_*` globals are the dead Classic branch.
- Whether druid form / rogue stealth drives `GetBonusBarOffset` or a page. The harness models the
  call; read it defensively at the call site.
- Possess is real but hard to test — it needs a Mind Control or Eyes of the Beast.

---

## Watch bars

One widget, two instances. Rested XP and the reputation standing are the only differences
that reach the component.

- **`StatusBar` gains a secondary fill.** Rested XP is a second fractional child behind the
  main fill. Extend the primitive rather than stacking two bars — a stacked pair would need
  its own alignment, resize and theme plumbing kept in step with the first.
- **Reputation colour is a game fact and already exists.** `Core/Game.lua`'s `ReactionColor`
  maps standing 1–8 onto the client's own bands. Do not add a colour token for it, and do not
  copy the table into the plugin.
- Readout slots reuse the unit frames' dropdown pattern: none / current-max / percent /
  remaining / rested. Rep adds faction name and standing.
- Both hide when they have nothing to say (max level, no watched faction), which is a
  visibility change flow layout already handles by skipping hidden children.

---

## Testing

`lua Tests/run.lua` from the addon root. No change ships until it passes, and new behaviour
needs a spec that would **fail without the change** — mutate the fix back and confirm the new
assertion goes red. Geometry assertions derive from `H.token(...)` and the text helpers, never
from pixel literals.

### The lockdown assertions are the ones that matter, and they are already expressible

The harness models lockdown by frame identity: `H.setCombat`, `H.getBlockedActions`,
`H.hasProtectedDescendant`. Assert **both** halves for every bar:

```lua
-- The rule: a frame that resizes must not contain a protected one.
expect(H.hasProtectedDescendant(dock:GetFrame()))
    .as("the dock must not contain the secure buttons").falsy()

-- The consequence: a mid-combat settings change is not refused.
H.setCombat(true)
H.resetBlockedActions()
SuuUI.Settings:Set("action_bars", "bar1_button_size", 34)
expect(#H.getBlockedActions()).as("nothing was refused").eq(0)
```

### Harness gaps to close first

Extend `Tests/harness/wow/`, cover the addition in `Tests/spec/00_harness_spec.lua`, and
document it in `TESTING.md`. The harness models geometry faithfully and the API *surface*
loosely, so a gap in the direction an assertion points cannot fail — that has burned this
project repeatedly.

| Missing | Where | Note |
|---|---|---|
| The action API (`GetActionInfo`, `HasAction`, `GetActionTexture`, `GetActionCooldown`, `IsUsableAction`, `IsActionInRange`, `GetActionCount`) | `wow/api.lua` | plus `H.setAction(slot, {…})` / `H.clearAction(slot)` staging that fires `ACTIONBAR_SLOT_CHANGED`, the same "state moves and the event fires" contract `H.setAuras` has |
| `SecureHandlerStateTemplate`, `RegisterStateDriver` | `wow/frame.lua` | a **recorder**, not an evaluator. Record the driver string and let a spec assert it; do not fake macro-condition evaluation, or a spec will assert against the model's own guess |
| `SetOverrideBindingClick`, `GetBindingKey` | `wow/api.lua` | enough to assert hotkey text and that binding happens out of combat |
| `Texture:SetGradient` | `wow/regions.lua` | record the two colours so a spec can assert the glass plate's gradient, and model the absent case so the flat fallback is reachable |

Also unprovable and to be stated rather than assumed green: `SetAttribute` is not gated by
the lockdown model, so "attributes are stated once" is a structural assertion only; and no
Edit Mode re-anchoring is modelled, so nothing here can prove the `hooksecurefunc` re-assert
actually fires in game — assert instead that the original anchor is stored before the frame is
touched, restored exactly on teardown, and that repeated re-asserts do not accumulate.

---

## Phases

Each phase ends green with its own specs and is independently verifiable in game.

| # | Phase | Acceptance |
|---|---|---|
| 0 | Probes | **DONE 2026-08-23** — results recorded above. Re-run after any client patch |
| 1 | `Backdrop.Glass` + tokens | Plate renders in both themes, degrades to flat fill with no gradient API, tokens appear in the theme editor |
| 2 | Harness action API + state-driver recorder | `00_harness_spec.lua` covers each addition |
| 3 | `ActionButton` | Icon, cooldown, count, hotkey, usable and range states; drag in and out; `PostClick` emits; not `SetScript("OnClick")` |
| 4 | `ActionBarGrid` + `action_bars` bar 1, Blizzard cluster suppressed | Bottom cluster and gryphons gone, bar 1 functional, restored exactly on disable |
| 5 | Bars 2..N + the B3 dock | `Attach To` moves a bar between dock and free; `coreInset` keeps the stored position meaning the buttons; the lockdown pair above passes |
| 6 | Stance / pet / possess | Druid form swap, hunter pet, mind control exit all work; auto-hidden when empty |
| 7 | Atlas + `DataField` icon + `micro_menu` | Every micro button opens its panel; labels toggle collapses to glyph-only; unglyphed buttons fall back to text |
| 8 | `watch_bars` | XP with rested ghost fill and readouts; rep bar identical, faction-coloured from `Game.ReactionColor`; both hide when silent |
| 9 | `bag_bar` | Free-slot count with settings-driven tone thresholds; click opens bags |
| 10 | Docs | `architecture.md` (components, plugins, new tokens), `plugin-authoring.md` (secure bars), `WOW_API_ENCAPSULATION.md` (the state-driver carve-out), `TESTING.md` (harness additions), `README.md` |

Phase 4 is the first one worth a `/reload`: it is where Blizzard's art disappears and where a
suppression mistake is visible immediately.

---

## Tree state at the time of writing

Verified on disk 2026-08-23, after the built-in widget fold landed. **The in-flight work this
plan originally warned about is done and committed**, so the earlier list of uncommitted
collisions no longer applies:

- `Plugins/Performance/` and `Plugins/AddonButtons/` **no longer exist.** `FpsWidget.lua`,
  `LatencyWidget.lua`, `ButtonCollector.lua` and `AddonButtonsWidget.lua` all live in
  `Plugins/DataBar/` and register under the `data_bar` plugin id. Any path in an older draft
  pointing at those two folders is dead.
- `Components/FlyoutPanel.lua` exists and is the hover-list component the addon-button tray
  uses. The micro menu does **not** need it — its entries are individual fields, not a roster.
- `Libs/` is vendored and loaded from the `.toc`; the harness loads it the same way the client
  does.

The one coordination hazard that remains is the shared-primitive extension: `DataField` gaining
an `icon`, and `StatusBar` gaining a secondary fill. Both files have specs
(`Tests/spec/44_datafield_spec.lua`, the StatusBar spec) that other work has been editing, so
re-read the tree and `git status --short --untracked-files=all` before touching either.

**Do not stage files you did not change.**
