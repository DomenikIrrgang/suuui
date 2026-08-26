# Tooltip Reskin

Restyles WoW's in-game tooltips to match SuuUI, and supplies the information colour the
client withholds. Covers `GameTooltip` and the three genuinely separate tooltip frames, the
unit health bar, tooltip placement, fonts, and a set of content lines.

Concept and the option set it came from: artifact `suuui-tooltip-reskin-concepts`.

**This is not `Components/Tooltip.lua`.** That component draws SuuUI's own hover tips — a
single centred font string, no props, no title/body split, no icon, no bar — and it is
unrelated to this work and not reusable for it. This plugin restyles *Blizzard's* frames.

---

## The structural fact this plan rests on

**There is essentially one tooltip, not nine.** On this client every "type" — item, spell,
buff, debuff, unit, vendor, world object, keybinding — is the same `GameTooltip` frame with a
different set of lines pushed into it. One restyle covers all of them.

Only three things are genuinely separate frames, and only one has different regions:

| Frame | Why it needs its own handling |
|---|---|
| `ShoppingTooltip1` / `ShoppingTooltip2` | real separate frames; comparison uses its own smaller font step |
| `ItemRefTooltip` | chat links; owns `ItemRefCloseButton`, which needs skinning by name |
| `EmbeddedItemTooltip` | **the only structurally different type** — an embedded icon plus a real `IconBorder`, which unlike `GameTooltip` is a genuine quality-colour target the client already provides |

**The client supplies almost no colour.** Blizzard colours the name line by item quality and
nothing else. There is no dispel colour on a debuff tooltip, no quality border, and
`GameTooltipStatusBar` arrives with no colour *and* no text. So this is a restyle **plus**
supplying the signal colour the client omits — which is why decision 2 below is the substance
of the design rather than decoration.

---

## Locked decisions

| # | Area | Choice |
|---|---|---|
| 1 | Frame treatment | **T4 signal border.** Flat `colorBg` panel; the 1px border takes the signal colour. Chosen over the recommended T3 (header band + rail). See "Why T4 costs an extra rule" below. |
| 2 | Signal source | **Per type, reusing rules that already exist** — see the table in Phase 3. Never invented per-tooltip. |
| 3 | Health bar | **H2 a real row inside the panel**, in space reserved with `SetPadding`. Chosen over H3 because T4's signal border must enclose the bar that it is colour-coding. Both `SetPadding` arities and `GetPadding` verified present in Phase 0 round 2. H3 stays the fallback if it clips in game. |
| 4 | Anchor | **A2 fixed moveable anchor**, default bottom-right, via the existing `MoveableFrame` + edit mode. Cursor-follow available as a setting. |
| 5 | Fonts | **F1 the three global Font *objects***, never a `GameTooltipTextLeftN` walk. |
| 6 | Content API | **Legacy `OnTooltipSet*` scripts.** `TooltipDataProcessor` is present on this client and must not be used. |
| 7 | Durability | **One `hooksecurefunc` on `SharedTooltip_SetBackdropStyle`**, plus one initial pass over the frame list. |

### Why T4 costs an extra rule that T3 did not

T4 puts the variable colour on all four sides of the border, which is a lot more colour than a
2px rail. Two consequences, both load-bearing:

- **Only colour at uncommon and above.** ElvUI's guard is `if quality and quality > 1 then`.
  Common is white and poor is grey; a white 1px border on a dark panel reads as a selected or
  focused state, and it would fire on the *majority* of tooltips a player sees — every reagent,
  every grey drop, every quest item. Below uncommon, keep `colorBorder`.
- **Reset on clear is now on the main path, not an edge case.** ElvUI sets a `qualityChanged`
  flag and restores the border in `OnTooltipCleared`; without it a coloured border leaks to the
  next tooltip. ElvUI ships `itemQuality` **off by default**, so that leak was rare for them.
  Here it is the default, so the reset is mandatory and needs its own spec.

The `colorBorderFocus` objection raised in the concept artifact was **weaker than stated** and
is not a reason to avoid T4: a tooltip is never focusable and never sits beside an input. The
one place it could have bitten was a proposal to use `colorAccent` for a stealable buff — that
proposal was wrong for an unrelated reason (see Phase 3) and is dropped, so no signal colour is
ever the accent.

---

## Phase 0 — verify the client before writing any code

Several facts in this plan are marked UNVERIFIED in the source investigation, and this client
has contradicted assumptions before. Each line is kept under ~250 characters because WoW's chat
edit box truncates past 255 and fails with a syntax error.

```lua
/run for _,n in ipairs({"GameTooltip","GameTooltipStatusBar","ItemRefTooltip","ItemRefCloseButton","ShoppingTooltip1","ShoppingTooltip2","EmbeddedItemTooltip"}) do print(n,_G[n] and "Y" or "-") end
/run for _,n in ipairs({"WorldMapTooltip","FriendsTooltip","GameTooltipText","GameTooltipHeaderText","GameTooltipTextSmall","GameTooltipTextLeft1","GameTooltipTextRight1"}) do print(n,_G[n] and "Y" or "-") end
/run print(SharedTooltip_SetBackdropStyle and "hook" or "-",GameTooltip.NineSlice and "nine" or "-",GameTooltip.SetPadding and "padS" or "-",GameTooltip.IsForbidden and "forbid" or "-",GameTooltip:GetNumPoints())
/run print(TooltipDataProcessor and "tdp" or "-",GameTooltip.GetSpell and "getSpell" or "-",GetSpellSubtext and (GetSpellSubtext(116) or "nil") or "-",GameTooltip.SetUnitBuffByAuraInstanceID and "byInst" or "-")
/run local l=GetInventoryItemLink("player",5) print(l and select(3,GetItemInfo(l)),l and select(4,GetItemInfo(l)),l and select(11,GetItemInfo(l)),ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[4].hex or "-")
/run print(GetItemCount(2589),GetItemCount(2589,true),UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") or "-",select(7,UnitAura("player",1,"HELPFUL")) or "nil",C_UnitAuras and "cua" or "-")
/run print(TOOLTIP_DEFAULT_COLOR and TOOLTIP_DEFAULT_COLOR.r or "-",TOOLTIP_DEFAULT_BACKGROUND_COLOR and TOOLTIP_DEFAULT_BACKGROUND_COLOR.r or "-",GameTooltip:GetAnchorType(),GetCVar("alwaysCompareItems"))
```

### What each probe decides

| Probe | Decides |
|---|---|
| 1 | The frame list for Phase 3. Any `-` is a **dead line in this spec**, not a frame to skin. |
| 2 | Whether F1 is possible at all. If the three Font objects are absent, fonts fall back to F2 and Phase 3 grows. |
| 3 | Whether the durability hook exists; whether `NineSlice` needs hiding; whether H2 was wrongly ruled out (`SetPadding`). |
| 4 | Confirms `TooltipDataProcessor` is present **and deliberately unused**; whether the rank line and the aura-instance setters exist. |
| 5 | Whether item level (field 4) and sell price (field 11) are real here, and the shape of the quality colour table. |
| 6 | Whether bank-count split, the role line, and the aura caster are real. |
| 7 | The default backdrop colours worth matching against, and whether comparison tooltips are on. |

**Record the results in this file before starting Phase 1.**

### Round 1 results — recorded 2026-08-24

| Probe | Result |
|---|---|
| 1 Frames | `GameTooltip` **Y** · `GameTooltipStatusBar` **Y** · `ItemRefTooltip` **Y** · `ItemRefCloseButton` **Y** · `ShoppingTooltip1` **Y** · `ShoppingTooltip2` **Y** · `EmbeddedItemTooltip` **Y** |
| 2 Fonts / more frames | `WorldMapTooltip` **Y** · `FriendsTooltip` **Y** · `GameTooltipText` **Y** · `GameTooltipHeaderText` **Y** · `GameTooltipTextSmall` **Y** · `GameTooltipTextLeft1` **Y** · `GameTooltipTextRight1` **Y** |
| 3 Backdrop | `SharedTooltip_SetBackdropStyle` **Y** · `NineSlice` **Y** · `SetPadding` **Y** · `IsForbidden` **Y** · `GetNumPoints()` = **1** |
| 4 Content API | `TooltipDataProcessor` **Y** · `GameTooltip:GetSpell` **Y** · `GetSpellSubtext(116)` = **"Rank 1"** · `SetUnitBuffByAuraInstanceID` **Y** |
| 5 Item | equipped chest: quality **2**, item level **25**, sell price **103** · `ITEM_QUALITY_COLORS[4].hex` **present** |
| 6 Counts / role / aura | `GetItemCount(2589)` = **14** · with bank = **114** · `UnitGroupRolesAssigned("player")` = **"DAMAGER"** · aura caster (7th return) = **"player"** · `C_UnitAuras` **Y** |
| 7 Defaults | `TOOLTIP_DEFAULT_COLOR.r` = **1** · `TOOLTIP_DEFAULT_BACKGROUND_COLOR.r` = **0.0902** · `GetAnchorType()` at rest = **`ANCHOR_NONE`** · `alwaysCompareItems` = **"0"** |

**Nothing in the frame list is absent, so there are no dead lines in this spec.** Unlike the
bottom-UI plan, every global named here is real on this client.

Five results change the plan:

- **`SetPadding` EXISTS, so H2 is back on the table.** It was rejected only because space could
  not be reserved at the bottom of the tooltip. It can be. See the amended decision 3 — and note
  T4 makes the case for H2 stronger than it was, because a bar placed *outside* the signal
  border is not enclosed by the colour that is describing it. Needs one arity probe first.
- **`NineSlice` EXISTS**, against the source investigation's guess of "likely absent". So the
  border is drawn by a NineSlice, not by a backdrop alone, and hiding it with `SetAlpha(0)` is
  **mandatory** rather than the guarded maybe it was written as. `SetBackdrop` alone would leave
  Blizzard's border visible under ours.
- **`TooltipDataProcessor` is confirmed present** — and stays deliberately unused, per decision 6.
  This is now measured on this client rather than inferred from ElvUI's flavour check.
- **`UnitGroupRolesAssigned` returns `"DAMAGER"`, not `"DPS"`.** The role line needs a display
  map (`TANK` / `HEALER` / `DAMAGER` / `NONE`), and `NONE` must render nothing rather than the
  word "None".
- **`alwaysCompareItems` is `"0"`**, so `ShoppingTooltip1/2` only appear on shift-hover. They are
  still real frames and still need skinning; they are just not on the default path, which means a
  spec is the only thing that will catch a regression there.

Two smaller notes:

- **`ITEM_QUALITY_COLORS[n].hex` is a colour escape**, which is why probe 5 printed nothing
  visible for it — the escape swallowed the rest of the line. `Game:ItemQualityColor` must read
  `.r` / `.g` / `.b` and return `{r,g,b,a}` like every other accessor in that file, never `.hex`.
- **`SetUnitBuffByAuraInstanceID` exists here**, though ElvUI feature-detects it and this plan
  does not need it. Recorded so nobody re-probes it.

### Round 2 results — recorded 2026-08-24

| Call | Result |
|---|---|
| `SetPadding(0, 24, 0, 0)` — four-arg | `pcall` **true** |
| `SetPadding(0, 24)` — two-arg | `pcall` **true** |
| `GetPadding` | **exists**; first return **0**, matching the `right = 0` that was set |
| `GetHeight()` after | **58.70**, then **86.88** on the second reading |

**Both signatures are accepted and `GetPadding` exists, so H2 is implementable and verifiable
rather than guessed.** The first return being 0 is consistent with the modern
`(right, bottom, left, top)` order — note the probe's `and`/`or` wrapper truncated the
multi-return to one value, so only `right` was visible.

**The two height readings are not comparable, and that is itself the implementation note.**
`GameTooltip` is shared: anything moused over between two manual `/run` commands reclaims the
owner and replaces the lines, so the second reading almost certainly describes a different
tooltip. Consequences for Phase 4:

- **Set padding to an absolute value on every show, never adjust it incrementally.** A tooltip
  whose padding is nudged relative to its current value drifts, because the previous show's
  padding may not be ours.
- **Never cache tooltip geometry across shows.** Read it back with `GetPadding` when it matters.
- **Do not read `GetHeight()` in the same frame as the lines were set.** Blizzard's layout has not
  run yet; that is what makes the 58.70 reading untrustworthy on its own.



---

## Phase 1 — harness first

This inverts the usual order deliberately. The harness models almost none of this, and the
lockdown gap already cost ten days of in-game debugging on work that had 2728 passing
assertions. Anything specced against today's model would be green and meaningless.

What is assertable today: line content, `SetOwner`, anchor type, and the recorded aura
`{unit, index, filter}`.

What must be added:

1. **`GameTooltipStatusBar` as a real StatusBar.** `metaFor.StatusBar` is currently a bare
   `FrameMeta` — `SetMinMaxValues`, `SetValue`, `SetStatusBarTexture` and `SetStatusBarColor`
   have **zero occurrences in the entire harness**. This is a real `StatusBar` type plus the
   global, parented to `GameTooltip`.
2. **Fire the tooltip scripts.** `OnTooltipSetItem`, `OnTooltipSetSpell`, `OnTooltipSetUnit`
   and `OnTooltipCleared` are stored by `SetScript` and **never fired by any harness path**.
   Drive them from the setters (`SetUnit`, `SetAction`, `SetBagItem`, `ClearLines`) so a spec
   cannot pass by invoking a hook by hand — the exact mistake that shipped a dead micro-menu
   button.
3. **`AddDoubleLine` must stop discarding the right-side colours.** It accepts
   `rr, rg, rb` and throws them away, so any assertion about a right-hand value's colour is
   vacuous.
4. **`SetPadding` / `GetPadding`**, only if probe 3 says they exist.
5. **Item and spell tooltip setters** — `SetHyperlink`, `SetInventoryItem`, `SetSpellBookItem`
   — enough to reach the item and spell paths.
6. **Font object model** — `GameTooltipText` / `HeaderText` / `TextSmall` as objects whose
   assignment is observable, or F1 is untestable and the spec can only assert F1 was *called*.

Do **not** add `GameTooltipTextLeftN` globals. `GetLine(i)` is the deliberate substitute and
the harness comment explains why; adding the globals would invite specs that assert against
per-line font strings the model does not really have.

Cover every addition in `Tests/spec/00_harness_spec.lua`. The harness is load-bearing: if it is
wrong, every spec built on it is wrong and green.

### Status: implemented

All seven items landed, plus two that only surfaced while doing it:

| Added | Where |
|---|---|
| `StatusBarMeta` — a real type, value **clamped** to range, `OnValueChanged` only on a real change | `Tests/harness/wow/frame.lua` |
| `GameTooltipStatusBar`, parented to `GameTooltip`, rebuilt per setup | `Tests/harness/wow/api.lua` |
| The four tooltip scripts **fire**, driven by the setters | `Tests/harness/wow/frame.lua` |
| `SetUnit` / `GetUnit` / `SetHyperlink` / `SetBagItem` / `SetInventoryItem` / `GetItem` / `SetSpellByID` / `SetSpellBookItem` / `GetSpell` | `Tests/harness/wow/frame.lua` |
| `AddDoubleLine` keeps `rr, rg, rb`; new `GetLineColor(i)` reads them back | `Tests/harness/wow/frame.lua` |
| `SetPadding` / `GetPadding`, both arities | `Tests/harness/wow/frame.lua` |
| `IsForbidden`, and a `NineSlice` child so hiding it is reachable | both |
| Font objects gained `SetFont` (**raising** on a bad asset), `SetTextColor`, shadow and justify verbs | `Tests/harness/wow/api.lua` |
| The four tooltip scripts added to the `SCRIPTABLE` whitelist | `Tests/harness/wow/widget.lua` |

Two of those were not in the original list and are worth recording:

- **The `SCRIPTABLE` whitelist rejected all four tooltip scripts.** `SetScript` asserts on an
  unknown handler name — a good guard that catches typos — so the scripts had to be declared
  before anything could subscribe. Worth knowing before adding any further client script.
- **Font objects had no `SetFont` at all**, only `GetFont`. F1 would have been untestable, which
  would have left a per-line walk looking like the only option. The setter raises on an
  unloadable asset for the same reason `FontString:SetFont` does.

Suite: **4204 passed, 0 failed, 5 skipped**. Twelve mutations run against the additions, **all
twelve caught**.

---

## Phase 2 — `Core/Game.lua` gains item-quality colours

`SuuUI.Game` has class, reaction, power, spell-school and dispel colours and **no quality
colours at all**. T4 depends on one entirely.

```lua
SuuUI.Game:ItemQualityColor(quality)   -- @return table|nil
```

Contract, matching every other accessor in the file:

- Prefer the live `ITEM_QUALITY_COLORS` global over an internal copy, cache per quality, and
  validate the cache against the source so a runtime retint is picked up without allocating per
  call — exactly as `ClassColor` does with `RAID_CLASS_COLORS`.
- **Return `nil` only for a quality this client does not name — NOT for `quality <= 1`.** This
  corrects an earlier draft of this spec, which folded the "uncommon and above" threshold into
  the accessor. That was wrong: the threshold is a **look decision belonging to whichever
  surface is drawing**, not a fact about the client. A tooltip border wants it; an item *name*
  in the planned inventory grid does not, because white is exactly what a common item's name
  should be. Folding it in would deny that caller a colour that genuinely exists. The `> 1`
  guard therefore lives in `Plugins/Tooltips/`.
- Read `.r` / `.g` / `.b` and return `{r,g,b,a}`, **never `.hex`** — that field is a `|cff…`
  colour escape, not a colour, and it silently swallows whatever it is concatenated into. It is
  what made the Phase 0 probe print nothing for its fourth value.
- It belongs in `Game.lua` and not in the theme for the reason stated in `coding-standards.md`:
  "epics are purple" is a fact about the client, not a design choice. A theme that could retint
  it would make the border lie about the game.

**Status: implemented.** `Core/Game.lua` now carries `ITEM_QUALITY`, `qualityCache` and
`M:ItemQualityColor(quality)`.

Update the `Game.lua` section of `architecture.md` (6d) in the same change, including the
`quality <= 1` decision and why it lives in the accessor.

---

## Phase 3 — the reskin: backdrop, border signal, fonts, anchor

New plugin `Plugins/Tooltips/`, id `tooltips`.

### Nothing here is protected, and no combat guard belongs anywhere in it

`GameTooltip` is not a protected frame and its backdrop is not a protected method. ElvUI
restyles it unconditionally with no taint comment, no combat guard and no protected-frame
handling anywhere in its tooltip path. **Do not add an `InCombatLockdown()` guard to the
styling path** — mutation testing would show it unreachable, and it would imply a constraint
that does not exist. The only protection concept to honour is `IsForbidden()`.

The one place combat *is* worth checking is content: skip expensive line work while
`InCombatLockdown()` is true, which is what ElvUI's second combat check does.

### The frame list

Skin the list from probe 1, and iterate it with **`next`, not `ipairs`**. A nil global leaves a
hole in the array part; `next` skips holes while `ipairs` stops dead at the first one — which
would silently drop every frame after it.

Exclude, at the top of the restyle function: `IsForbidden()`, anything embedded
(`isEmbedded or tt.IsEmbedded`), and SuuUI's own scan tooltip if one is ever added. Never skin
your own scanner.

**Hide the NineSlice — this is mandatory, not defensive.** Phase 0 confirmed `GameTooltip.NineSlice`
exists on this client, so Blizzard's border is drawn by a NineSlice rather than by a backdrop
alone. `SetBackdrop` on its own leaves that border visible underneath ours, which reads as a
double frame. `tt.NineSlice:SetAlpha(0)` — keep the `if tt.NineSlice then` guard anyway, since the
frame list includes frames that may not have one. Do the same for `Delimiter1` / `Delimiter2`
textures where present.

### Durability

```lua
hooksecurefunc('SharedTooltip_SetBackdropStyle', function(tt, _, isEmbedded) restyle(tt, isEmbedded) end)
```

The `(tt, _, isEmbedded)` signature matches Blizzard's own `SharedTooltip_SetBackdropStyle`, so
one function serves as both the hook handler and the direct call. This is the whole durability
mechanism: Blizzard re-stamps a tooltip's backdrop at moments unrelated to anything the player
did, and a one-shot pass in `onEnable` is silently reverted. It also covers tooltips that are
not in the list at all.

There is **no `OnShow` hook and no per-show restyle.** The backdrop is set once per restyle
event.

### The border signal

Per-show, in the type's own hook, then reset in `OnTooltipCleared`.

| Type | Signal | Source |
|---|---|---|
| Item, at **uncommon and above only** | quality | `Game:ItemQualityColor` (Phase 2, which returns nil below uncommon) |
| Unit | class, else reaction | `Theme:GetUnitColor` — its existing three-step chain, zero new logic |
| Debuff | dispel type, red when untyped | `AuraBand.KINDS`'s debuff rule verbatim: `DebuffTypeColor(dispel) or UntypedDebuffColor()` |
| Buff | **nil unless stealable**, then the dispel colour | `AuraBand.KINDS`'s buff rule verbatim: `if not stealable then return nil end; return DebuffTypeColor(dispel)` |
| Spell | none — keep `colorBorder` | see below |
| `EmbeddedItemTooltip` | quality, on `IconBorder` | the client's own quality-colour target |

**The buff and debuff rules are copied from `Plugins/UnitFrames/AuraBand.lua`, not re-derived.**
That file's comment block explains why they differ, and the reason is a bug that has already
been paid for once: the client reports a `dispelType` for HELPFUL auras too — Righteous Fury
comes back as `"Magic"` — so colouring a buff by dispel type rings half a paladin's blessings
in blue while meaning nothing. A buff's border answers "can I take this off them", and
`isStealable` is the client's own answer to that. Two copies of these rules would drift; factor
the two functions out of `AuraBand.lua` into something both can read rather than duplicating
them.

**Spell tooltips get no signal, and that is a decision rather than an omission.** School colour
is unavailable: this client has no spell→school API, so `Game:SchoolOf` only knows spells the
combat log has already reported. A border coloured for spells you have cast and grey for
everything else is worse than always grey.

### Fonts (F1)

Three assignments, once:

| Font object | Covers |
|---|---|
| `GameTooltipText` | body — every `GameTooltipTextLeftN` / `RightN` |
| `GameTooltipHeaderText` | line 1, its own size step |
| `GameTooltipTextSmall` | comparison tooltips |

**This is the one decision with a SuuUI-specific consequence.** SuuUI's font registry drives
`SetFont` per FontString, which makes an F2-style `GameTooltipTextLeftN` walk the tempting
shape — and it would mean re-walking on every show forever, because the client creates line
objects on demand. Going through the Font objects covers lines **that do not exist yet**.

Two things genuinely need per-object work because they do not inherit: money-frame texts (by
name, and only when `hasMoney`), and shopping-tooltip regions, discovered via `GetRegions()` +
`IsObjectType('FontString')` rather than by guessing names.

Resolve the face through `SuuUI.Fonts:Path` before it reaches the client — `SetFont` **raises**
on an invalid asset rather than returning false, and an unguarded probe has already unwound out
of a `PLAYER_LOGIN` handler once.

### Anchor (A2)

`hooksecurefunc('GameTooltip_SetDefaultAnchor', ...)`. Blizzard's function is never replaced;
the hook re-owns with `ANCHOR_NONE` and re-points.

Two guards to copy verbatim, both of which stop SuuUI fighting other addons:

- **Bail when `tt:GetAnchorType() ~= 'ANCHOR_NONE'`** — something already owns the anchor.
- **Only re-point when the current anchor is on a recognised-unclaimed whitelist** (nil,
  `UIParent`, our own mover). Anything else was placed deliberately by someone.

The mover is an ordinary `MoveableFrame` in the `tooltips` namespace, so it is profile-aware,
appears in the edit-mode element list and snaps to the grid for free. Flip the attach corner by
screen quadrant so a tooltip anchored bottom-right grows up-left rather than off-screen.

### Status: implemented, and CONFIRMED IN GAME 2026-08-24

Four files under `Plugins/Tooltips/` — `Skin.lua` (frame list, backdrop, NineSlice, fonts),
`Signal.lua` (the border signal), `Anchor.lua` (placement + mover), `Tooltips.lua` (plugin,
schema, hooks). Spec: `Tests/spec/51_tooltips_spec.lua`, 40 tests.

Three defects were found while building it, and only one of them by a test:

- **`Backdrop.Apply` RAISES on a frame not created with `BackdropTemplate`, and a
  `type(tt.SetBackdrop) ~= "function"` guard cannot see it** — the method exists and *then*
  raises. The throw landed inside `Plugin:Enable`'s `pcall`, so the player would have got no
  tooltips and no message. Fixed by mixing in `BackdropTemplateMixin` when absent (ElvUI's own
  move), `pcall`ing the apply, and gating the border tint on `Skin.IsSkinned` — a border colour
  is a property of a backdrop, so tinting an unskinned frame raises from inside a tooltip script.
  Caught by `35_attach_login_spec`'s "logs no failure on the way up".
- **The anchor arguments were reversed.** The TOOLTIP's own `point` attaches to the mover's
  INVERSE; written the other way a bottom-right mover grows the tooltip down and right, off the
  screen. Found by re-reading ElvUI's ordering, not by a test.
- **The harness's `GameTooltip` had no backdrop template**, which the real one does — so the
  reskin was being pushed down its "this frame cannot take a backdrop" branch in every spec.

Two mutations survived the first pass and both were **weak tests, not dead code**:

- *`next` vs `ipairs`* survived because the hole was staged in the MIDDLE of the frame list, so
  `ipairs` still reached everything before it. Worse, the harness modelled only `GameTooltip`, so
  there was nothing behind any hole to drop. Fixed by modelling the other eight tooltip frames
  (all measured present in Phase 0) and nilling the FRONT of the list.
- *Reversed anchor order* survived because the test asserted the `INVERSE` table's contents —
  intent, not result — which passes with the `SetPoint` arguments swapped. Fixed by reading the
  resolved anchor back off the frame.

Suite: **4244 passed, 0 failed, 6 skipped**. Eighteen mutations, all eighteen caught after the
two fixes.

---

## Phase 4 — the unit health bar (H2)

The bar becomes the tooltip's **last row, inside the panel**, enclosed by the signal border.
Reserve space with `SetPadding` and place `GameTooltipStatusBar` in it.

Why H2 rather than the concept's H3: **T4 is what decided it.** With a quality- or
class-coloured border, a bar sitting outside that border is not enclosed by the colour that is
describing the unit, so the two read as separate widgets. That argument did not exist when H3 was
picked, and Phase 0 removed the only objection to H2 by proving `SetPadding` is real.

Four safeguards, three of them straight out of the round-2 reading:

- **Set the padding to an absolute value on every show.** Never adjust it relative to its current
  value — the previous show's padding may not be ours, since `GameTooltip` is shared with every
  other addon and with Blizzard.
- **Never cache tooltip geometry across shows.** Read it back with `GetPadding` when it matters.
- **Do not read `GetHeight()` in the same frame the lines were set.** Blizzard's layout has not run
  yet.
- **Restore the padding to 0 in `OnTooltipCleared`**, for the same reason the quality border is
  reset there: a tooltip that keeps our reserved gap while showing someone else's content has a
  mystery hole at the bottom.

H3 — flush below, outside the border — stays the documented fallback. If H2 clips the last line in
game, switch and move on; it is a one-anchor change.

### Status: implemented, NOT yet confirmed in game

`Plugins/Tooltips/HealthBar.lua`. Suite **4262 passed, 0 failed**; 15 mutations, all caught after
two weak tests were strengthened (the DISABLED test never showed the bar first, and the harness
already parents the bar to the tooltip so the parenting assertion proved nothing).

### RESOLVED — the bar is SuuUI's own, swapped 2026-08-24

Phase 4 first drove **Blizzard's `GameTooltipStatusBar`**, which is what ElvUI does, and was
confirmed working in game that way. It was then swapped to **`Components.StatusBar`**.

**What the swap removed:** the `SetScript("OnValueChanged", nil)` destroy-then-rehook — the only
non-additive call in the entire plugin. It existed purely to stop Blizzard's own handler fighting
ours and making the bar flicker. Own the bar and there is nothing to fight, so the line is gone
rather than guarded.

**What it also fixed:** the first version had invented **k/M abbreviation that no other bar in the
addon uses**, so a tooltip read `7.6k / 15.2k` beside a unit frame printing `7620 / 15240`. The
readout now goes through `Core/Readout.lua`.

**What it cost, as predicted:**

- Blizzard's bar is **suppressed** with the guarded-`OnShow` pattern, because
  `GameTooltip_ShowStatusBar` keeps showing it — a one-shot `Hide` is undone on the next
  mouseover and the player sees two bars. The flag clears *before* the restoring show, since
  `HookScript` cannot be undone.
- The value is **driven from `UnitHealth`**, with a `UNIT_HEALTH` watcher armed only while a unit
  tooltip is open. Nothing announces that a tooltip closed, so the `Hide` hook disarms it.

**`BAR_TEXT` moved out of `Plugins/UnitFrames/UnitFrame.lua` into `Core/Readout.lua`.** That file's
own comment named the hazard — "a second copy is the thing that drifts" — and a second *consumer*
is the same hazard, with a plugin forbidden from reaching into another plugin for it. `UnitFrame`
now aliases the shared table and delegates its option builder; `Readout.Options()` returns a fresh
table per call, preserving the property that comment depended on.

Two placement details worth keeping:

- **The bar is a STACK child, not an anchor descriptor.** A tooltip resizes on every line it is
  handed, and an anchor would carry a width computed once at placement time and go stale
  immediately. Stack stretches across the box on every pass, so the bar tracks the tooltip's width
  for free.
- **It is `Add`ed exactly once**, with later shows going through `SetChildProps`. `Add` is a
  membership operation rather than an upsert, so a per-mouseover `Add` grows the child list
  without bound — the same trap `FlyoutPanel` documents.

Suite: **4273 passed, 0 failed, 6 skipped**. Nineteen mutations, all caught — the last one only
after `Core/Readout.lua` got its own block in `04_core_spec.lua`, because `500/1000` is 50% whether
the percentage floors or rounds and the floor is what stops a nearly-dead unit reading 100%.

**CONFIRMED IN GAME after the swap, 2026-08-24.**



Three details, each of which is a real defect if missed:

- **Destroy Blizzard's handler, then hook.** `SetScript('OnValueChanged', nil)` followed by
  `HookScript('OnValueChanged', ...)`. ElvUI's inline comment is "keeps the health bar from
  flickering" — a pure hook does not fix it. This is the **only** non-additive call in the
  entire design; everything else is a hook.
- **Wire the hide ourselves.** ElvUI's `GameTooltip_Hide` bar-hider is registered only inside
  its retail branch, so **it never runs on this client**. Without our own wiring the bar lingers
  after the tooltip goes.
- **Do not port `GameTooltipStatusBar_UpdateUnitHealth`.** It is retail-only and calls
  `UnitHealthPercent(unit, true, ScaleTo100)`, an 11.x API. The TBC path is the
  `OnValueChanged` handler reading `UnitHealth` / `UnitHealthMax`.

Colour it from the same signal as the border — `Theme:GetUnitColor` — with a neutral fallback,
and give it the readout text the client does not ship. Text is a `Components.Text` on an overlay
above the bar; format lives in the plugin, not the component, exactly as `UnitFrame.lua` owns
its own health formats.

`statusPosition` gets three values: `BOTTOM`, `TOP`, `DISABLED`. `DISABLED` must genuinely hide
rather than only zeroing alpha (ElvUI only zeroes it).

---

## Phase 5 — content lines

Default **on**:

| Line | Source |
|---|---|
| Item level | `select(4, GetItemInfo(link))` — the boring field, and **exact** here because TBC has no upgrade levels. Verified by TacoTip, which targets 20504. Not `GetDetailedItemLevelInfo`, not tooltip scraping. |
| Item count, bags + bank | Bank derives as total minus bags, so the split is free |
| Unit: guild + rank, level, class, difficulty colour | Class goes on the level line; blank the client's now-duplicate class line |
| Target-of-target, and "Targeted By" in a group | The group scan is **classic-exclusive** — ElvUI gates it `if E.Retail or not IsInGroup() then return end` |
| Health value text | Phase 4 |
| Role line | **Not** retail-only: `E.allowRoles` names TBC explicitly and ElvUI ships it enabled. Text, not an icon. **Measured: `UnitGroupRolesAssigned` returns `"DAMAGER"`, not `"DPS"`** — needs a display map for `TANK` / `HEALER` / `DAMAGER`, and `NONE` must render **nothing** rather than the word "None" |

Default **off**:

| Line | Note |
|---|---|
| IDs behind a modifier | One `SHOW/HIDE/SHIFT/CTRL/ALT` string per surface. **Must** be paired with a `MODIFIER_STATE_CHANGED` re-render, or the IDs only appear on the *next* mouseover |
| Sell price, always and stack-multiplied | `GetItemInfo` field 11. TBC already prints this at a vendor, so the feature is showing it everywhere. ElvUI's version is retail-wired and cannot be copied |
| Aura caster | 7th return of the aura data. Give it **its own toggle** — ElvUI welds it to the ID display, which is worse |
| Per-surface visibility | Four independent selectors: bags, unit frames, action bars, combat |
| Faction / PvP tag lines | Blizzard's own `PVP` / `Alliance` / `Horde` lines; default is to strip them |

**Do not ship** — all retail-only, and a toggle for a feature that never arrives reads as a
broken setting: mythic score, dungeon score, mount source, battle pet, spec icon, warband,
`healthBar.short`, ElvUI's `moneyLines` path.

**The trap to avoid copying:** ElvUI renders `inspectDataEnable` and `showMount` as live options
on TBC while their code paths exclude TBC. Two switches that do nothing. Gate every setting on
the same condition its code path is gated on.

Also note a reputation **standing** line (`Honored 7400/12000`) is **unimplemented anywhere on
disk** — ElvUI's faction colours are name tinting, not a standing line. If it is wanted it is
original work and needs its own probe, not a port.

### Status: implemented as 5a — APPEND-ONLY

`Plugins/Tooltips/Content.lua`. Suite **4297 passed, 0 failed, 6 skipped**; 18 mutations, all
caught after three off-state tests were added.

**The scope boundary is deliberate and worth stating: this module only ever APPENDS lines.**
Rewriting a line the client already wrote — recolouring the name by class, folding the creature
type onto the level line, stripping Blizzard's `PVP` and faction rows — needs
`GameTooltipTextLeft<N>`, and the harness models no per-line font strings on purpose (`TESTING.md`
says so, and adding them would invite specs asserting against a shape the model does not have). An
appended line is fully assertable through `GetLine`; a rewritten one would be in-game-only. The
signal border already carries class and reaction, which makes the name-line recolour the least
valuable of that set anyway.

Landed: item level, carry count with the bank split, sell price, target-of-target (coloured by
what that target *is*), the role line, and item/spell/NPC ids behind a modifier — with a
`MODIFIER_STATE_CHANGED` re-render, without which a gated line only appears on the *next*
mouseover and reads as a broken setting.

**Not built:** the "Targeted By" group scan, guild rank, and the line-rewriting set above. The
group scan is worth doing — it works here and not in retail — but needs party/raid unit staging
the harness does not have yet.

Three things the harness needed, all added: `GetItemCount` (whose `includeBank` returns the
**total**, so the bank's own figure is a subtraction — reading it as the bank directly prints the
whole stack as if it were all banked), `UnitGroupRolesAssigned`, and a `role` field on the unit
staging helper.

Two details that only showed up in the writing:

- **The client answers `"DAMAGER"`, not `"DPS"`.** Printing the raw value shows a word no player
  uses, and `"NONE"` — which is what a solo player reports — must render **nothing** rather than
  the word "None".
- **Money drops leading zero units but keeps a middle one.** `12g 0s 88c` looks like noise until
  you notice `12g 88c` and `12g 88s` are different prices and the letters are what disambiguate
  them.

---

## Settings schema sketch (plugin id `tooltips`)

```
enabled                                   toggle   default true

[section] Appearance
  quality_border                          toggle   default true    -- T4; off falls back to colorBorder
  backdrop_alpha                          slider   default from opacityPanel
  font_size / header_font_size            slider
  comparison_font_size                    slider

[section] Placement
  anchor_mode                             dropdown mover | cursor
  position                                position -- MoveableFrame
  x_offset / y_offset                     slider

[section] Health Bar
  health_position                         dropdown BOTTOM | TOP | DISABLED
  health_height                           slider   default 12
  health_text                             toggle   default true

[section] Content
  item_level / item_count_bags / item_count_bank
  sell_price / sell_price_stack
  unit_guild_rank / unit_target / unit_targeted_by / unit_role
  aura_caster
  show_ids                                dropdown SHOW | HIDE | SHIFT | CTRL | ALT

[section] Visibility
  hide_in_combat / hide_on_bags / hide_on_unitframes / hide_on_actionbars
```

Every key needs a `Settings:Watch` in the same edit — a schema key with no watcher is read only
at construction and appears to do nothing until a reload, which has already been reported twice
in this project. Prefer a live applier over a rebuild.

---

## What a spec can and cannot prove

Assertable once Phase 1 lands: the frame list, the border colour per type including the
`quality <= 1` boundary and the reset-on-clear, the anchor guards, line content, the health
bar's value and colour, and that the font objects were assigned.

**Not** assertable, and needing an in-game check:

- Whether Blizzard's own restyle actually fires the durability hook. The harness models no
  Blizzard-side re-anchoring or re-styling at all, so a spec that calls
  `SharedTooltip_SetBackdropStyle` itself is asserting against its own trigger. Same shape as
  the Edit Mode gap already recorded in `TESTING.md`.
- The health bar flicker that justifies the destroy-then-rehook.
- Whether the fonts visibly apply to lines created after init.

Mutation-check every non-trivial change per `TESTING.md`, and note in a comment where a
mutation could not be reached rather than reporting it as covered.

---

## Docs updated when this landed

- `architecture.md` — `Core/Game.lua` (6d) for `ItemQualityColor` and `DifficultyColor`;
  `Core/Readout.lua` in the directory tree; a Bundled Plugins entry for `tooltips`.
- `WOW_API_ENCAPSULATION.md` — "Restyling A Blizzard Tooltip", the **fourth** carve-out, stating
  that no combat guard applies so the next reader does not add one.
- `TESTING.md` — the new harness verbs, and the reversal of the rule that forbade modelling
  `GameTooltipTextLeft<N>`.

---

## Two diagnosis lessons from shipping it

Both cost multiple rounds and neither was a logic error.

**A GENEROUS harness is worse than a thin one.** `GetLine` is a convenience the harness provides for
specs; the real `GameTooltip` has no such method. Production called it and raised on the first
mouseover **with 4325 assertions green**, because the harness supplied exactly what the client
lacked. No behavioural assertion can catch that — in the harness the behaviour is correct. The guard
is now structural: `00_harness_spec.lua` reads the `.toc` and fails if any shipped file calls a
harness-only name.

**Print the gate's stored value before reading any code.** Two rounds of fixes went into the spell-id
feature while the setting was simply `HIDE`. Worse, changing the schema `default` to `SHOW` did not
help the reporter: `Settings:Get` falls back to the default only when **nothing is stored**, so a
default change fixes new profiles and silently leaves an existing one broken. The two fixes made
along the way were real — action buttons open their tooltip with `SetAction`, and a line appended
from a hooked setter needs `tt:Show()` — but neither was the reported symptom.
