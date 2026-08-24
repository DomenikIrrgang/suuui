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

**BUILT 2026-08-24.** `Media/generate_micro_icons.py` → `micro-icons.tga` (128×128 RGBA) plus a `.png`
for eyeballing. 14 glyphs, all four `verify()` checks passing: inside the cell margin, big enough to
read, roughly centred, and strictly monochrome so `SetVertexColor` decides the colour. Unused cells are
asserted EMPTY so a coord table pointing at one shows nothing rather than debris.

`verify()` earned its keep twice — it rejected `social` for bleeding 2px into its neighbour's cell, and
`keys` for being only 12px tall next to glyphs that fill theirs.

**Three glyphs took more than one attempt, and the reasons generalise to 32px art:**
- **spells** — an OPEN book does not survive 32 pixels. An outline plus a centre stroke read as a
  barrel; two leaning polygons read as a hexagonal gem, because `polygon(outline=...)` closes the shape
  and the outer edges join. It is a closed book with a vertical spine.
- **quests** — flush rolled ends made it a bordered rectangle with lines in it, which is what the
  spellbook is too. The rolls now overhang the body: the SILHOUETTE is what separates two glyphs, not
  the detail inside them.
- **bags** — a drawstring pouch read as a shield. A handle over a trapezoid body is unmistakable.

The generated Lua coord table is printed by the script; **glyph order is a contract**, mirrored by
index on the Lua side, so a glyph inserted in the middle silently re-points every entry after it.
Append only.

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

### Round 8 — 6a VERIFIED IN GAME on a warrior, recorded 2026-08-23

The stance bar works: eight auras on a paladin, three stances on a warrior, correct icons, correct
active form, working tooltip, clicking swaps stance. Four things went wrong first, and **none of them
were catchable by the 3,800-test suite as it stood** — each one is recorded because each cost a
round-trip and would cost another.

**1. `SetNormalTexture(nil)` is REFUSED on this client.**
```
bad argument #2 to '?' (Usage: self:SetNormalTexture(asset))
```
The setter wants an asset and has no "clear it" argument. To clear one of the template's textures,
take the Texture from the GETTER and hide it. The harness was permissive here and now raises exactly
as the client does, so the next component making this mistake fails in the suite.

**2. A construction error is SILENT.** `Core/Settings.lua` wraps every watcher callback in `pcall`
and routes the error to `SuuUI.Debug`, which only prints when `SuuUI._debug` is set. `buildBar` runs
inside that watcher, so the throw above produced **no bar and no message** — two rounds of wrong
diagnosis went into that silence before `SuuUI._debug = true` revealed it in one line. A plugin
failing to build is not a debug-level event; this is worth changing.

**3. The template ALREADY provides a tooltip.** Adding a second setter did not add anything — it
fought, and the tooltip flicked between the button and the screen corner on every hover, because two
owners were anchoring one frame. `StanceButton` therefore has **no tooltip code at all**, which is
the opposite of `ActionButton` and is pinned by a spec so the apparent omission is not "fixed".

**4. Hiding the template's art removes the ACTIVE-FORM visual.** `SetChecked(true)` was correct the
whole time and drew nothing, because the checked texture was hidden along with everything else. Which
stance you are in is this bar's primary information, so it now draws a hairline `colorAccent` ring —
deliberately not a brighter icon, since dimming is already spoken for by the uncastable state and two
states through one channel cannot be told apart.

**5. `PLAYER_ENTERING_WORLD` is required, not optional.** At build time `GetNumShapeshiftForms()` can
still answer 0, so the bar is created with no cells and hides itself. A WARRIOR is then stuck
forever: three stances are known from the start, so the client never fires "the set of forms changed".

#### Why the suite missed all five

Worth stating, because it is a property of the specs rather than bad luck:

- Every spec staged its forms **before** building the bar. That is the one ordering login never uses.
- The harness accepted `SetNormalTexture(nil)`; the client refuses it.
- The harness's template shipped **no art**, so "we cleared Blizzard's border" asserted against an
  already-nil value.
- After fixing the ring and the tooltip the suite still reported the same test count, which is what
  revealed that neither was covered at all.

`StanceButtonTemplate` itself is CONFIRMED to exist on this client — the error above came from
`SetNormalTexture`, which runs after `CreateFrame`, so the button was created successfully.

### Round 9 — the pet button mechanism, recorded 2026-08-23

**Probed:** `PetActionButton1:GetAttribute("type")` on a warlock **with an imp summoned** → **empty**.
Unambiguous, because the pet was out: Blizzard's pet buttons do not use the secure `type` attribute,
exactly like its stance buttons.

**But that is the wrong question**, and it nearly sent this phase down the harder path. Blizzard not
using the attribute says nothing about whether `SecureActionButtonTemplate` SUPPORTS it for us.
`LibActionButton-1.0` — bundled here as a sibling addon, and the library most bar addons use —
answers it from disk. Inside a live secure snippet:

```lua
self:SetAttribute("type", type)                          -- type can be "pet"
local action_field = (type == "pet") and "action" or type
self:SetAttribute(action_field, action)                  -- action = the pet slot index
```

and its pickup path maps `kind == "pet"` to `"petaction"`. None of it is version-guarded.

**So `type="pet"` + `action=<index>` works, and the pet bar builds its OWN buttons.** Consequences,
all of which make this simpler than the stance bar rather than harder:

- No reparenting of Blizzard's protected frames.
- Our own names, so Blizzard's `PetActionBar_Update` cannot fight our styling — the thing ElvUI has
  to re-apply on every event.
- **`PetActionBar` becomes suppressible**, unlike what the earlier draft of this section said.
- It is the SAME secure mechanism as an action slot: same template, same `action` attribute. So this
  is a `kind` on `ActionButton`, not a third component.

**Why a `kind` prop rather than a `PetButton.lua`:** the press-versus-release click gate
(`RegisterForClicks("AnyDown","AnyUp")` plus `useOnKeyDown` plus the `PostClick` phase check) is
subtle, was got wrong once already, and produced a button that looked perfect and did nothing.
It must exist in exactly ONE place. The stance bar could not share it — it has no secure attribute at
all — but pet can, so it does.

Still pet-specific: the autocast overlay (`autoCastAllowed` shows it, `autoCastEnabled` spins it), the
`isToken` `_G` resolution, no count, no macro text, no range, and `PetHasActionBar()` greying.

### Round 10 — autocast, and the second protected function, recorded 2026-08-23

**`TogglePetAutocast` is PROTECTED.** Calling it from a `PostClick` hook -- which genuinely does run
in a hardware-event context, in response to a real click -- produced the popup:

```
SuuUI has been blocked from an action only available to the Blizzard UI.
```

That is the SECOND protected function this phase assumed was callable, after `CastShapeshiftForm`.
The lesson is not about either function: **assume a client function that changes game state is
protected until proven otherwise**, and prefer a route where the CLIENT performs the action.

**The route that works is secure click forwarding.** `type2 = "click"` plus `clickbutton2` pointing at
Blizzard's own `PetActionButtonN`. The client presses that button itself, and ITS handler is trusted,
so it may call what ours may not. Evidence this is real on this client: Clique uses
`type1`/`type2`/`*clickbutton2` for click-casting, and ElvUI's bags use `clickbutton` for the purchase
tab. ElvUI's pet bar gets autocast for free by the same principle -- it only ever HookScripts
Blizzard's buttons, so their trusted OnClick survives.

`type2` also stops the right-click reaching the pet-cast path, so one click does one thing.

**A pet button registers ONE click phase, and that is load-bearing.** With `AnyDown` and `AnyUp` both
registered, one physical right-click runs the secure handler TWICE, forwards twice, and toggles
autocast straight back -- a right-click that visibly does nothing. The press-versus-release preference
exists to make CASTING feel responsive and has no meaning for a configuration click; Blizzard's own
pet buttons act on the release anyway.

**Consequence to watch: Blizzard's pet buttons must keep existing.** They are hidden along with
`PetActionBar`, which is fine, but they must not be destroyed or unparented -- the forward targets
them. If a hidden target turns out to refuse a forwarded click, the fallback is to suppress
`PetActionBar` by moving it off-screen rather than hiding it.

### 6c — possess: DEFERRED, not dropped. Decided 2026-08-24

Possess is real on this client and IS still wanted. It is deferred rather than declined, because
nothing about a replacement could be trusted today:

- **It cannot be verified.** A possess bar needs a Mind Control or Eyes of the Beast to appear, so
  every claim about it would be untested. Four rounds went into the pet bar's click path even though
  it WAS verifiable; the same work unverifiable is not a trade worth making.
- **There is no reference implementation.** `GetPossessInfo(slot)` exists per the client's own API
  stub, but nothing installed here calls it, so its returns are unknown.
- **ElvUI hides `PossessActionBar` and never replaces it.** Even a mature addon judged this not worth
  the risk.

So Blizzard's possess bar stays, working, until it can be tested. `Suppress.lua` deliberately does NOT
list it, and a spec asserts that -- otherwise a later "hide every remaining bottom-cluster frame"
sweep would silently cost a priest the ability to act while mind-controlling something.

**To pick this up:** get on a priest (Mind Control) or a hunter (Eyes of the Beast), possess something,
and probe before writing anything -- `IsPossessBarVisible()`, then `GetPossessInfo(1)` and `(2)` for
their real returns, and walk the parent chain from whatever button appears. Phase 0's frame names were
wrong three times; this one has never been read at all.

### Still open
- Whether druid form / rogue stealth drives `GetBonusBarOffset` or a page. The harness models the
  call; read it defensively at the call site.

---

## Phase 7 — the micro menu, DONE 2026-08-24

Built and verified in game. Fourteen glyphs in a 128×128 atlas, one data-bar field per entry in the
`left` section, Blizzard's strip suppressed.

**Per-entry toggles, not one switch.** ON by default: Character, Spellbook, Quests, Options, Help.
Available but off: Guild, Talents, Social, PvP, Group Finder, Map, Bags, Keys. Plus a **Show Labels**
toggle, on by default -- with labels off the glyph is the whole field and `DataField` hugs to icon plus
`spaceMd` either side.

- **Guild is off by default** because a dedicated guild widget is planned and will be on -- two things
  opening the same panel from one bar is one too many.
- **Collections is removed entirely**, not merely defaulted off: it does not exist on TBC, and a toggle
  for a button that is never coming reads as a broken setting. Its GLYPH stays in the atlas, because
  renumbering the sheet would silently re-point every coord after it.

### `frame:Click()` DOES NOT WORK on a micro button, and that cost a round

The obvious mechanism -- forward the field's click into Blizzard's own button -- silently does nothing.
Probed:

```
/dump CharacterMicroButton:GetScript("OnClick") ~= nil   -->  false
/dump CharacterMicroButton:IsEnabled()                   -->  true
```

There is **no OnClick script to fire**. The button is enabled and reachable; `Click()` simply has
nothing to invoke, because these buttons act through a mixin or mouse handlers. ElvUI never calls
`Click()` on one either -- it only reparents them and HookScripts their hover, which was the tell.

**Each entry therefore names the panel function it calls, and BOTH the button frame and that function
must exist before the entry renders.** Two conditions answering different questions: the frame says the
feature exists on this client, the function says we can trigger it. A wrong function name then costs a
MISSING glyph, never a dead one -- which matters because this cluster's names have been wrong three
times. The harness proves the rule by deliberately omitting `ToggleKeyRing`, so Keys is skipped even
when its toggle is on.

### Suppression: WHICH frame, and why it is safe here

`MicroMenuContainer` (with `MicroMenu` its child) is suppressed. **`MicroButtonAndBagsBar` is NOT** --
it carries the bag buttons as well, and Phase 9 owns those, so hiding it would cost the player their
bags for a whole phase.

Safe to hide at all *because* the replacement calls the panel APIs rather than forwarding clicks into
these buttons: nothing SuuUI draws depends on them being on screen. Had the fields forwarded clicks,
this would have been the pet bar's hidden-target problem again.

**After suppression, the seven off-by-default entries are only reachable by keybind or by switching
their toggle on.** That is the intended trade, not an oversight.

### Two coverage holes this phase exposed

- **A spec that called `def.OnClick()` directly proved nothing.** It skipped the field, the CLICKED
  signal and the bar's wiring, so it passed green while a real click did nothing. The specs now drive
  the rendered field's `OnMouseUp`, and one asserts we do NOT attempt `Click()`.
- **The harness created the micro buttons before their parent existed**, so they were parented to
  `UIParent` and hiding the container left them all visible. Caught by the suppression witness, and now
  guarded by an assert in the harness so the ordering mistake cannot recur silently.

### Round 11 — the bag container, probed 2026-08-24

```
/dump MicroButtonAndBagsBar ~= nil, BagsBar ~= nil, MainMenuBarBackpackButton:GetParent():GetName()
  [1] = true
  [2] = true
  [3] = "BagsBar"
```

**Both frames exist, and the bag buttons are under `BagsBar`.** This corrects a claim written during
Phase 7, which said `MicroButtonAndBagsBar` carries the bag buttons. It does not -- it is an ANCESTOR
of the container that does.

Leaving it unsuppressed is still correct, but for the cascade rather than its contents. **Phase 9's
suppression target is `BagsBar` plus `KeyRingButton`**, not `MicroButtonAndBagsBar`.

This is the same shape as `MainActionBar` versus `MainMenuBar`, which cost a round in Phase 4b: the
frame that exists is not always the frame that holds the buttons, and only walking the parent chain
from a button settles it.

**`ToggleKeyRing` does not exist on this client** -- the micro menu's Keys entry is skipped for that
reason, which its two-condition check surfaced. Phase 9 needs to find how the keyring opens here (worth
trying `ToggleBag(-2)`) or establish that a modern backend folds it into the bags entirely.

### Round 12 — the slot coverage gap, measured 2026-08-24

Reported from the game: abilities that exist on the character could not be found on any SuuUI bar.

```
/run for b=0,14 do local n=0 for i=b*12+1,b*12+12 do if HasAction(i) then n=n+1 end end if n>0 then print("slots "..(b*12+1).."-"..(b*12+12).." = "..n) end end
```

| slots | page | actions | covered by |
|---|---|---|---|
| 1-12 | 1 | 2 | Bar 1 |
| **13-24** | **2** | **11** | **nothing** |
| 25-36 | 3 | 12 | Bar 5 |
| 37-48 | 4 | 8 | Bar 4 |
| 49-60 | 5 | 9 | Bar 3 |
| 61-72 | 6 | 5 | Bar 2 |
| **73-84** | **7** | **4** | **nothing** |
| **85-96** | **8** | **6** | **nothing** |
| **97-108** | **9** | **5** | **nothing** |
| **109-120** | **10** | **1** | **nothing** |
| 145-156 | 13 | 9 | Bar 6 |

**27 of 72 abilities were unreachable.** SuuUI's eight bars mirror Blizzard's own Action Bar 1-8, and
Blizzard exposes no bar for pages 2 or 7-10 — so a UI that mirrors Blizzard cannot reach slots the client
nonetheless stores actions in, and that every serious bar addon exposes. ElvUI calls these its `bar2` and
`bar7`-`bar10`; its `bar13 = { page = 13, bindButtons = 'MULTIACTIONBAR5BUTTON' }` also **independently
confirms** SuuUI's bars 6-8 at 145/157/169, which Round 6 had left recorded as unmeasured.

**Fixed by adding bars 9-13** for pages 2, 7, 8, 9, 10 (page N is slots `(N-1)*12+1` upward). Numbered 9
upward rather than renumbered to match the pages: bars 1-8 already agree with the numbering the player
reads in Blizzard's own keybinding UI, and the ids are profile data **and** dock participant ids, so
renumbering would move every stored position and silently repoint every dock attachment.

**These bars needed SuuUI's first `Bindings.xml`.** A Blizzard binding family acts on the SLOT, which is
why suppressing Blizzard's bars never cost the player their keys — whatever is bound to `ACTIONBUTTON1`
fires `UseAction(1)` whether Blizzard's button is on screen or not. Pages 2 and 7-10 have no such family,
so SuuUI declares `SUUUIBAR9BUTTON1`..`SUUUIBAR13BUTTON12` (60 bindings) purely to give the player a name
to bind, and routes the chosen key to a **click on its own secure button** via `SetOverrideBindingClick`.
That is the only route an addon has to a protected `UseAction`; a Lua binding body calling it would be
refused.

**The keys are applied from the grid's own `CHILDREN_CHANGED` signal, not on an event guess.** A bar built
in combat has no buttons yet — `SetSlots` defers its geometry pass — so there is nothing to bind a key to,
and catching up on `PLAYER_REGEN_ENABLED` *raced the grid's own catch-up on that same event*. The signal
exists for precisely this case, so the keys follow the buttons whenever they appear. `UPDATE_BINDINGS`
re-claims after a rebind, deferred in combat like any other secure mutation.

**Four mutation survivors, all real test weaknesses rather than dead code:**
- the Blizzard-family guard could be deleted, because bar 1 is enabled by default and was already built
  before the test staged any keys — so there was nothing to claim either way. Fixed by firing
  `UPDATE_BINDINGS` after staging.
- clearing stale routes could be deleted, because asserting only the NEWEST route cannot tell "re-claimed"
  from "claimed twice". Fixed by asserting the route count is exactly one.
- the combat guard could be deleted, because the only combat test was a bar BUILT in combat, where the
  absent buttons hid the guard's effect. Fixed by adding a mid-fight REBIND, where the buttons exist.
- the `CHILDREN_CHANGED` subscription needed a clean mutation to test at all; the first attempt was
  malformed, so its GREEN meant nothing.

---

## Bag bar — Phase 9, BUILT 2026-08-24

Blizzard's six-button bag row is replaced by ONE data bar field reading `BAGS 27`. Clicking opens the
bags; the count carries a tone from the player's own thresholds.
**`Plugins/DataBar/BagsWidget.lua` — a BUILT-IN WIDGET, not a plugin.**

**It shipped as its own `bag_bar` plugin first, and that was wrong twice over.** The field creates no
frames at all — it is only a data bar entry — so a plugin wrapper bought nothing, and it put the settings
on their own page instead of with every other field's, which is where a player would not think to look.

**It also broke its own enable toggle, one-way.** The plugin registered the toggle's watcher under its
owner prefix and then called `UnwatchPrefix` on that same prefix from `onDisable` — destroying the watcher
that would switch it back on. Off worked; on never did, so the setting looked ignored. A built-in widget
cannot make that mistake: its toggle is an ordinary setting in the data bar's schema and the plugin
re-runs `Enable`, which rebuilds the watcher. The spec asserts the **round trip**, because the "off" half
passed the whole time.

**In the RIGHT section**, first at order 180 — ahead of addon buttons (190), latency (200) and fps (210),
so the gameplay reading takes the inner edge and the diagnostics keep the far right.

**The container API has the same two shapes reputation did**, and this is the second time on this client.
The modern backend moved these onto `C_Container`; ElvUI dereferences
`C_Container.GetContainerNumFreeSlots` at file scope with **no nil guard** and works here, so the
namespace is present and the bare globals may not be. Read through `C_Container` first, then the globals,
and `SuuUI.Fault` when neither exists — because a blank field and a full inventory are the same pixels,
and silence would be the worst possible misreading.

**Specialised bags are excluded, and in TBC that has teeth.** Quivers, ammo pouches and soul shard bags
report free slots that cannot hold loot. `GetContainerNumFreeSlots` returns the bag's type as its second
value; a type of 0 or absent means general-purpose, the same test ElvUI applies. Counting them would tell
a hunter with an empty quiver they have room for twenty more items.

**Tones are measured against FREE SLOTS, not a percentage.** Four slots left is the same problem with one
bag or five, while a percentage would call a nearly-full 100-slot inventory fine. The danger threshold is
refused above the warning one, or the warning band vanishes.

**A threshold change has to notify the renderer.** No bag event fires when a slider moves, so the widget
re-registers itself — which is the available refresh, since the registry has no per-widget refresh call and
`RegisterWidget` overwrites by id and notifies. Mutation testing is what forced this assertion: the tone
tests call `GetText` directly and re-read the settings every time, so deleting the watchers left them all
green. The spec now observes the registry's own subscription.

**Suppression is `BagsBar` plus `KeyRingButton`** — confirmed by Round 11's parent walk. NOT
`MicroButtonAndBagsBar`, which is the ancestor and would cascade.

### The framework bug this phase exposed: `plugin._def`

While it was still a plugin, the widget definition was held on the plugin handle as `p._def` so a settings
change could re-register it — and `_def` is **where Core/Plugin.lua stored the plugin's own definition**.
Assigning to it destroyed the table the lifecycle reads its hooks from, so `onDisable` was never called.

**It failed in total silence.** No error was thrown, because the hook was simply absent; and had one been
thrown, `Disable` pcalls it and logs through `Debug`, which prints nothing with debug off. Diagnosis took
four probes and only moved once debug was forced on and `type(p._def.onDisable)` came back `nil`.

Plugin definitions now live in a **private weak-keyed table in `Core/Plugin.lua`** that a plugin holds no
reference to, so the collision cannot recur. `18_integration_spec.lua` asserts it with a plugin that
performs the exact hostile act — mutation-checked by making the lifecycle read the handle's field again,
which the test catches. The fix outlived the plugin that prompted it, which is the point of making it.

## Watch bar docking — Phase 8c, BUILT 2026-08-24

The watch bars dock to action bars and to each other, in **both directions**, through the same service.

**The dock needed no functional change to accept them.** Probed against the live harness before designing
anything: `Dock.Attach(bar1, xpBar, "above")` already returned true and placed the bar. The dock only ever
asks a participant for `GetFrame`, `GetWidth`/`GetHeight`, a `_dockEdge` field and a `SIZE_CHANGED`
signal — a `StatusBar` handle has all of it, and nothing in `Reflow`, `Attach` or the cycle walk knew what
an action bar was. So `Plugins/ActionBars/Dock.lua` moved to **`Core/Dock.lua`** as `SuuUI.Dock`: a rename,
not a rewrite. `Paging` and `Suppress` stayed behind, because those genuinely are action-bar concerns.

**A participant registry, because the cycle guard cannot work per plugin.** A watch bar attached to bar 1
while bar 1 is attached to that watch bar is a real loop the client hard-errors on, and **neither plugin
can see it** — each holds one half of the graph. `Dock.RegisterParticipant` stores identity, the
AttachPoints name, and an `attachedTo()` closure that reads *that* plugin's settings, so `WouldCycleIds`
walks across plugins without knowing any plugin's key layout. Handle resolution stays with AttachPoints,
which already handles a target that does not exist yet or gets switched off underneath.

**Ids are profile data, so they are backward compatible by construction.** The action bars keep the plain
ids already written into profiles (`"1".."8"`, plus `"stance"`/`"pet"` — which is why they were never
coerced to numbers). Everything registering later namespaces: `"watch:xp"`, `"watch:rep"`.

**Dropdown options became a FUNCTION**, resolved when the settings panel is built. A fixed list cannot
work once the option set spans plugins, because whether the other plugin has registered depends on load
order. `SettingsUI/Controls/Dropdown.lua` resolves a function form, `pcall`ed so a bad provider costs one
empty dropdown rather than the whole settings page.

**Labels are NOT prefixed with the group, and the order needs an explicit tiebreaker.** Two rendering
faults found in game, both in the first version of `OptionsFor`:

- It prefixed the group once a second group existed, reasoning that "Experience" beside "Bar 3" reads as
  a bar named Experience. In a 140px dropdown that gave **eight consecutive rows of "Action Bars: Ba..."**
  — every entry truncated to the same string, which is far worse than the ambiguity it guarded against.
  The labels are unique on their own, and the spec now ASSERTS that uniqueness, so a future participant
  with a colliding label gets a better name instead of every label paying a prefix.
- **`table.sort` is not stable in Lua**, and the action bars carry no explicit `order`, so all eight tied
  on 0 and the list came out "Bar 4, Bar 6, Bar 5, Bar 2…". Registration sequence is recorded at
  registration and used as the final tiebreaker; the spec asserts the exact sequence, because "looks
  about right" is what let the jumble ship.

**The bug this phase produced, and it failed SILENTLY.** ActionBars built its target's attach point name
from its own prefix, so a watch-bar target became `actionbar.dock.watch:xp` — a point that never existed.
`Request`'s "not published yet" path looks identical to "will never exist", so an action bar simply never
docked to a watch bar and said nothing. Both plugins resolve through `Dock.PointFor` now. Found by an
end-to-end probe of all four directions, not by the suite.

**Combat deferral runs in both directions, deliberately without reasoning about which is safe.** An anchor
is the same dependency as parentage: if a watch bar is a dock for an action bar, moving it would move
protected buttons. The whole transition defers on `InCombatLockdown` and drains on
`PLAYER_REGEN_ENABLED` — added to this plugin's event list for that reason alone.

**Docked means not draggable.** While docked the dock owns the frame's point, so `MoveableFrame` comes off
and goes back on with the transition; leaving it on would let a drag fight the dock, with the winner
decided by whichever wrote last. A bar rebuilt while docked comes back non-draggable for the same reason.

Default is **free-floating** — no change for an existing profile.

## Watch bars — Phase 8, BUILT 2026-08-24

`Plugins/WatchBars/WatchBars.lua`, two instances of one shape, plus `StatusBar`'s new secondary fill.
Blizzard's `StatusTrackingBarManager` is suppressed.

**The two hide conditions are NOT the same shape**, and that is the part worth remembering:
- **Experience** hides at max level (the client reports a max of 0) OR when experience is switched off
  (`IsXPUserDisabled` -- a trial account). Two separate reasons for one outcome, and a bar checking only
  the level would still show for the second.
- **Reputation** hides when nothing is watched, and also when the standing's band has no span, which
  would otherwise divide by zero.

**Reputation is measured WITHIN the standing's band.** The client reports the band's own `min` and
`max`, so the bar's span is `max - min` and the value is offset into it. Using `value` against `max`
directly makes every standing above Neutral look nearly full -- 4500 of 6000 is 75%, but inside the
3000-6000 Revered band it is halfway.

**The ghost reaches from current progress**, `(value + rested) / max`, not from zero -- drawn from zero
it would claim banked progress the player has not earned. `GetXPExhaustion` returns **nil, not 0**, when
there is no bonus, and the difference is visible: a ghost of zero width still occupies the first pixel.
The rested READOUT is blank for both nil and 0, because "0" reads as "you have no rested experience
left", which is a different statement from "resting is not a factor".

### The colour defect, found in game — two bugs stacked, 2026-08-24

The bar shipped **white**, then shipped **blue**. Both got through a green suite, and both were caught
by looking at the game.

**1. White: the prop did not exist.** `StatusBar` takes `fillColor` as a **literal `{r,g,b,a}`**, and the
plugin passed a token KEY as `fill`. Wrong name and wrong type, silently ignored, so the bar kept its
white default. `border` was `showBorder` for the same reason. Neither setter validates, so nothing said
a word. The spec at `19_statusbar_spec.lua` **used the same phantom `fill` prop**, which is where the
plugin copied it from — its ghost tests ran against a white bar while their comments claimed blue.

**2. Blue: the colour meant something.** In WoW, **purple is experience and blue is RESTED**. Reaching
for `colorAccent` to fix the white bar produced a blue progress bar, which tells every player they have
a rested bonus — a **lie about game state**, not a palette preference. New tokens `colorXp`
(→ `colorPurple400`, added to both palettes) and `colorXpRested` (blue at 0.55 alpha) now carry it, and
`04_core_spec.lua` asserts **no theme may point `colorXp` at the accent**, checked across every theme
rather than only the active one.

**The ghost must be able to carry its own colour.** It previously always derived from the fill at
`opacityBarGhost`, defended in a comment as letting one primitive serve both watch bars. That reasoning
was wrong: **the reputation bar has no rested concept and never sets a secondary at all**, so there was
no second case, and derivation made rested a paler purple — reading as more progress. `SetSecondaryColor`
now overrides it, applied **as given** with no `opacityBarGhost` multiplied in.

**Two settings lessons.** The **schema default is what takes effect** — `Settings:Get` resolves through
it, so a fallback passed at the call site never runs once a key is declared, which is why flipping the
border off meant editing the schema. And **`StatusBar` stores colours as literals captured when set**, so
following a theme change is the *plugin's* job: re-resolve in `paint`, and test it by switching to a
theme whose token value genuinely differs. Re-emitting the change event on the same theme cannot tell a
bar that re-resolves from one that never does — that assertion passed while proving nothing, as did the
original ghost test comparing ghost against fill when **both were white**.

### The reputation bar was invisible — two causes, both silent, 2026-08-24

Reported from the game: a character with a faction tracked saw **no reputation bar at all**. Two separate
defects produced the same blank screen, and the suite could see neither.

**1. There are TWO reputation APIs and this backend may only have the new one.** The modern client
replaced positional `GetWatchedFactionInfo()` with **`C_Reputation.GetWatchedFactionData()`, which
returns a TABLE**. ElvUI carries a shim for exactly this on this client — and it dereferences
`C_Reputation.GetWatchedFactionData` **with no nil guard**, which is how we know `C_Reputation` exists
here. Its shim also gives the legacy order, which is **SIX** values, not five:

```
name, reaction, currentReactionThreshold, nextReactionThreshold, currentStanding, factionID
```

The old five-value read mapped onto that correctly by luck of ordering (`min` = the band's floor, `max` =
its ceiling, `value` = the raw total). But against the table form, `name` came back as the table itself —
truthy — with everything else nil, collapsing the span to zero and hiding the bar.

**2. Max standing collapses the band, and the bar hid on it.** At the top standing the client reports the
**same number** for the band's floor and its ceiling. The guard `if span <= 0 then return nil end` turned
that into a hidden bar, so an **Exalted faction looked identical to no faction at all**. ElvUI forces the
floor to 0 for the same reason and says so in its own comment: *"the min will match max when a rep is
maxed and cause the bar to be 0%"*. SuuUI now reports `capped` and draws full, and the `current / max`
and `remaining` readouts go blank rather than printing "1 / 1" and "0".

**A missing API is now a FAULT, not a hide.** "No API" and "no faction watched" produce an identical empty
screen but are completely different problems — conflating them is what let this sit unnoticed.
`SuuUI.Fault` fires on the first, which prints even with debug off.

**Three testing lessons, and the first is the sharpest.** The old spec **asserted the defect as intended
behaviour** — a test named "hides a band with no span rather than dividing by zero" did not merely miss
the bug, it locked it in. Second, the harness only ever modelled the legacy API, so no test could reach
the table path; `H.setRepApi("legacy"|"modern"|"none")` now switches which one exists, and `"none"`
genuinely REMOVES the global, because a stub that stays and returns nil is indistinguishable from an
unwatched faction. Third, that helper first mutated **`_G`** and appeared to work while changing nothing:
the addon's chunks resolve globals through the **harness env**, so a bare `C_Reputation` lookup is correct
in both worlds and an explicit `_G.` reaches past the table under test.

### Probe — which reputation API this client actually has

Still worth running, to record the fact rather than rely on handling both:

```
/run print("GWFI",type(GetWatchedFactionInfo),"C_Rep",type(C_Reputation),"GWFD",C_Reputation and type(C_Reputation.GetWatchedFactionData))
/run if GetWatchedFactionInfo then print("returns",select("#",GetWatchedFactionInfo())) print(GetWatchedFactionInfo()) end
/run local d=C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData() if d then for k,v in pairs(d) do print(k,tostring(v)) end else print("no table") end
```

**The standing colour is the CLIENT's**, through `Core/Game.lua`'s `ReactionColor`. Not a theme token:
the bands are a game fact a player knows by sight, and our own palette for them would be worse than
matching. This is also why `StatusBar`'s ghost derives its colour from the fill rather than owning a
token -- one primitive serves an accent-blue XP bar and a faction-coloured rep bar.

Readout slots are per bar and deliberately NOT the same set: `rested` has no meaning for a faction and
`faction` none for a level, and a slot that reads as broken half the time is worse than one fewer
option.

## Watch bars (original plan)

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
| 6 | Stance / pet | Stance + pet DONE and verified. Possess DEFERRED -- unverifiable without a possessing character |
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
