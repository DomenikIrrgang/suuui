# Inventory Plugin — v1 Plan

A combined inventory window: one flat grid of every bag slot, searchable, sortable, with a
sell-grey-items button, a character dropdown for browsing any alt's bags or bank from
anywhere, and a second live window at a banker for moving items between bank and bags.

Visual reference: artifacts `suuui-inventory-concepts` (the four layout directions that were
compared) and `suuui-inventory-character-browser` (the chosen S1 design in both modes). Slugs
resolve in any future session — do not re-derive the look from this file alone.

---

## 0. Client facts — MEASURED IN GAME 2026-08-24

Everything in this section was read off the live client, not inferred. Re-run these after any
client patch; this is a snapshot of ONE build, exactly as the bottom-UI plan's Phase 0 is.

| Fact | Measured value | What it forces |
|---|---|---|
| `C_Container` | `table` | present |
| bare `GetContainerNumSlots` / `GetContainerItemInfo` / `UseContainerItem` / `PickupContainerItem` / `SplitContainerItem` | **all nil** | **`C_Container.X` is the ONLY path.** No dual-shape resolver, no `C_Container.X or X` fallback. This contradicts what RXPGuides and Gargul hedge for — they support both because they ship to several clients, not because this one has both |
| `C_Container.GetContainerItemInfo(bag, slot)` | a **TABLE** | field access, never positional. Measured field set: `hasLoot, hasNoValue, hyperlink, iconFileID, isBound, isFiltered, isLocked, isReadable, itemID, itemName, quality, stackCount` |
| `itemName` in that table | present | **the live grid needs no `GetItemInfo` at all** to render or search a name. `GET_ITEM_INFO_RECEIVED` only matters for the cached alt view |
| `NUM_BAG_SLOTS` | `4` | bags are `0..4` (backpack + 4) |
| `NUM_BANKBAGSLOTS` | `7` | bank bags are `5..11` |
| `NUM_BANKGENERIC_SLOTS` | `28` | the bank's own grid |
| `Enum.BagIndex.Bank` | `-1` | |
| `Enum.BagIndex.Keyring` | `-2` | out of scope for v1 |
| `C_MerchantFrame.SellAllJunkItems` | **nil** | no one-shot junk sell. A throttled per-item loop is required |
| `UseItemByName` | `function` | exists, but the action underneath is protected — see below |
| **`C_Container.UseContainerItem` from tainted Lua, away from a merchant** | **BLOCKED** | `pcall` returned `true`, the stack count did not change, no Hearthstone teleport, and the client raised `*** ForceTaint_Strong *** has been blocked from an action only available to the Blizzard UI`. **Using an item needs a secure/Blizzard template** |
| **`C_Container.UseContainerItem` from tainted Lua, AT a merchant** | **WORKS** | Measured 2026-08-25: the item left the bag. Same function, two meanings — *use* away from a vendor (protected), *sell* at one (not). Phase 8's sell loop is plain Lua. See the note below on why a synchronous count read cannot confirm it |
| **`C_Container.PickupContainerItem` from tainted Lua** | **WORKS** | `pcall` true and `GetCursorInfo()` returned `item 27860 [Purified Draenic Water]`. Moving items is unprotected, so a physical sort engine is possible |
| `GetCursorInfo()` shape | `"item", itemID, itemLink` | |
| `CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate")` | **succeeds** (returned a frame) | the recommended cell base is instantiable here |
| `ContainerFrame1Item1` | exists | Classic naming. `ContainerFrameItemButton1` is a RETAIL name and is nil — do not probe for it |
| `BankFrameItem1` | `table` | bank cells have their own template family (`BankItemButtonGenericTemplate`) |
| bank container `-1` with its frame CLOSED | `slots 28`, `items 0`, `free 0` | **contents are not readable while closed.** An empty-but-readable bank would report `free 28`; reporting zero free against 28 slots is only consistent with no data |
| `ToggleAllBags` | exists; ElvUI secure-hooks it | already noted in `Plugins/DataBar/BagsWidget.lua` |
| **`BankFrame`'s `OnHide`** | **calls `CloseBankFrame()`** | measured 2026-08-25 by shipping the bug. Suppressing that frame the way a bag container is suppressed CLOSES THE BANK: it then reads 28 slots / 0 free and nothing can be moved into it, including a direct `C_Container.PickupContainerItem(-1, 1)` with a loaded cursor. It is therefore NEUTERED (alpha 0, mouse off, `ClearAllPoints`) and left SHOWN. ElvUI's `DisableFrame` nils `OnHide` before it ever hides this frame |
| **bank cell template** | `BankItemButtonGenericTemplate` for container **-1** only | bank BAGS (5..11) are ordinary containers and take `ContainerFrameItemButtonTemplate`. ElvUI branches on exactly this. The two handlers differ in where they get the container: the bag one reads the PARENT's id, the bank generic one hardcodes the bank |
| **`ItemButton` frame type** | **absent** | ElvUI creates its cells with `CreateFrame('ItemButton', ...)`, so it exists on ITS client generation but not this one. The call must be feature-detected; a plain `Button` still applies the template |
| ~~**the template's own OnClick / OnDragStart**~~ | ~~present but INERT for our cells~~ | **RETRACTED 2026-08-25 — this row was WRONG and everything built on it was wrong.** The test that produced it ran while `RegisterForClicks("LeftButtonUp", "RightButtonUp")` was in place, which delivers NO right-click on this client, so the handler was never reached. It is not inert: it performs pickup, place, split, sell, deposit, mail, trade **and use**. See the four rows below |
| ~~**`UseContainerItem`, three meanings**~~ | ~~sell / transfer / use~~ | Still true of OUR OWN call — permitted at a merchant and at an open bank, refused elsewhere with a popup — but **no longer relevant**, because the cell makes no such call. The template does it, untainted, in every situation |
| **`RegisterForClicks("LeftButtonUp", "RightButtonUp")`** | **delivers NO right-click** | `"AnyUp"` does. Third time this call has produced "a control that looks perfect and does nothing" in this project. On a bag cell, do not call it **at all**: the template registers what its own handler expects, and ours overrode it |
| **`SecureActionButtonTemplate` alongside a container template** | **REPLACES the container's OnClick** | Verified: `GetScript("OnClick") == SecureActionButton_OnClick` came back true. So adding it throws away the one handler that performs a container interaction. Its `item` and `macro` types then did not dispatch here across four attribute payloads (bag/slot, hyperlink, name, macrotext) |
| **`SetScript("OnClick", ContainerFrameItemButton_OnClick)` from addon code** | **taints the handler** | The protected call inside is then refused. The template must install its own handler at `CreateFrame` time from Blizzard's XML, with nothing of ours on it. **ElvUI is the reference**: `B:ConstructContainerButton` creates the slot, calls `SetID`, HOOKS OnEnter/OnLeave, and never touches OnClick, RegisterForClicks or a secure template |
| **the blocked-action popup names its taint SOURCE** | `SuuUI has been blocked …` vs `*** ForceTaint_Strong ***` | A genuine diagnostic, and the thing that finally separated "the approach is wrong" from "the probe method taints it": the first means OUR code made the call, the second means the `/run` chat path did. A mechanism cannot be validated by a `/run` that assigns a script |
| **MRT as a reference for secure item buttons** | **retail-only, do not use** | Its `type = "item"` code names item 171285 (Shadowcore Oil) and spell 318038, both Shadowlands, so that branch never runs here. Check a reference addon's FLAVOUR — guards and the expansion its item ids come from — before copying anything out of it |
| **a composite surface does NOT track its frame unless the ordering is right** | measured: a 219-unit window wearing a 411x546 glass body | `Backdrop.Glass` / `Panel` / `Pill` are textures laid out by a HOST container, and a host container chains onto whatever `OnSizeChanged` is already installed. Building the surface BEFORE the frame's own `SetScript("OnSizeChanged")` means that script REPLACES the surface's hook, and the surface silently keeps its original size. Cost three rounds here in two places — `Layout/Window.lua` + Glass, and `Components/Frame.lua` + Panel — because **the frame's own numbers are correct the whole time**. When a frame renders at the wrong size, measure the PAINT |
| **`PLAYER_LOGOUT` cannot read the bags** | measured: `money = 0`, zero slots | The sweep wrote that over a good snapshot, so a cached alt rendered as an empty grid with no gold while still appearing in the dropdown. `Capture` now refuses any read reporting **no slots at all** — the discriminator is the SLOT count, not the item count, because a character can genuinely have empty bags but every character has a backpack. `PLAYER_ENTERING_WORLD` was added as a trigger, since without it a character who logs in and straight out records nothing |
| **read-only must not mean `EnableMouse(false)` on a snapshot cell** | reported in game | It kills the hover the cell's own tooltip runs on, and browsing an alt's bags without tooltips is close to useless. A snapshot cell needs no input guard at all: it carries no Blizzard template, so it is inert by CONSTRUCTION. Only a live cell drops its mouse when read-only |
| **the container API returns NO ITEM NAME** | measured with a real capture: icon, quality and link all present, `name` nil, `CountMatches()` 0 | `GetContainerItemInfo` answers icon, count, quality, link and id. So a capture stored no name and **a cached character could not be searched at all** — the filter matched zero items whatever you typed, silently, while your own live bags searched fine. The name is inside the link (`[Arcane Powder]`), so `ItemCache.NameFromLink` parses it and needs neither `GetItemInfo` nor an event. Derived at READ time as well as at capture, so already-cached alts gain search without being logged in again |
| ~~**the concept's `?` cells: an ID-only cache renders blank cells on a fresh login**~~ | **RETRACTED — the premise does not hold on this client** | The concept's cache card reasons from an id-only store. But the container API hands over icon, quality AND link per slot, so a captured item always has its art, and with `NameFromLink` it always has a name too. `pending` therefore requires a record with no link and no icon whatsoever. **Confirmed in game on a cold client, immediately after a full restart: no `?` cell ever appeared.** Whether to keep `IsPending` as a defensive path or delete it as unreachable is OPEN — parked 2026-08-25, pinned as an `xit` in `61_itemgrid_spec` |
| **a spec that stages what the production path cannot produce tests the staging** | every snapshot search spec passed while search was broken in game | They wrote the name into the item table with `cacheItem()`, which capture has no way of doing. The fix is not more assertions but a different SOURCE: drive the real capture from staged CLIENT state and assert on what it leaves behind |
| **confirmed in game 2026-08-25, so nothing here needs re-testing** | one pass over the window's chrome plus a tooltip hover | The title-bar sort and coin glyphs, the pill search field and its clear button, the search-match ring at `opacity .16`, grey and white (`Q[0]` / `Q[1]`) quality borders, the account section naming another character and its `Account total`, cached money, snapshot tooltips, and the `ActionButton` count/macro readout fix. Phases 1–11 are all now confirmed on the live client rather than only in the suite |
| **`SetAlpha` on a cell frame** | **does not hold** | `SetAlpha(0.3)` then `GetAlpha()` returned 1 -- the template's animation groups own that frame's alpha. Anything fading a cell must fade OUR OWN children (the Icon, the readout overlay) |

### The fact that was NOT measured until Phase 8 was due — now ANSWERED

**Selling to a vendor via `UseContainerItem` while a merchant frame is open: WORKS.**
Measured in game 2026-08-25 with a common-quality item (`Flint and Tinder`) in bag 0 slot 1 at a
vendor: `pcall` returned `true` and the item left the bag. So the sell loop is a plain Lua loop and
Phase 8 needs no secure template.

**The distinction that reconciles this with the BLOCKED row above is the merchant, not the item.**
One function means two things: away from a vendor `UseContainerItem` *uses* the item, which is
protected; at a vendor it *sells*, which is not. Quality is irrelevant to either — a grey is easier
to test with only because it is worthless, and the sell-greys button restricts itself to quality 0
as a FEATURE decision, not because the API would refuse anything else.

**The probe that produced this was itself flawed, and the flaw is worth keeping.** It read
`stackCount` back in a second `/run` and printed `after 1` — the item still present — which reads
as a silent no-op and is exactly the signature of the blocked case. It is not: `UseContainerItem`
sends a request and the slot only clears when the SERVER confirms, so a synchronous count read
cannot observe a successful sale. Anything verifying an item movement must wait for
`BAG_UPDATE` / `ITEM_UNLOCKED` rather than reading the count on the next line.

For a re-measurement after a client patch, use a probe that says whether the merchant was even
open, since a closed one silently changes what the call means:

```
/run local C=C_Container print(MerchantFrame and MerchantFrame:IsShown(), pcall(C.UseContainerItem,0,1))
```

---

## 1. Locked decisions

1. **Flat combined grid (A1).** One grid of every slot from every bag, as if you owned one
   80-slot bag. No category headers.
2. **Grouping is a later setting, not a second layout.** The grid is sorted quality-descending
   then by name, which already clusters epics, potions and greys. A later `grouping` setting
   inserts `Accordion` headers into that same order — one extra pass over the same cell pool.
3. **Glass plate.** `Backdrop.Glass` with `from = "colorGlass"` (dense, top) → `to =
   "colorGlassFade"` (open, bottom) plus the `colorGlassSheen` top hairline. Cells stay opaque
   at `colorBgAlt` 0.92 so a quality border reads over grass. The footer gets its own denser
   strip because the plate's open edge lands exactly where the gold readout goes.
4. **S1 chrome.** Character `Dropdown` where the title would be, a two-way **Bags / Bank**
   segment beside it, actions on the right, and search on its **own full-width row** below.
5. **No "All" scope.** Bags means all five bag containers merged; Bank means the bank plus its
   seven bag slots merged. The cross-container question is answered by search reporting both
   counts, not by a third merged grid.
6. **Two live windows at a banker.** `BANKFRAME_OPENED` shows a second instance; items move
   between them. The scope segment hides while both are up and a muted `BAGS` / `BANK` tag
   names each window.
7. **Account knowledge: T1 + T3.** A tooltip section on every item tooltip in the game, plus a
   ledger tab for items you are not currently holding. **T2 corner badges are rejected** — they
   read as a second stack count and collide with the real one.
8. **Display-only sort in v1.** Physical sort is now proven possible (pickup works) but ElvUI's
   equivalent is a 1094-line move-list engine with lock verification and retries. Deferred, not
   ruled out.
9. **Cells inherit `ContainerFrameItemButtonTemplate`**, because using an item is protected.
   Precedent: `Components/StanceButton.lua` on `StanceButtonTemplate`.

---

## 2. What already exists

Almost nothing here is new machinery. Read these before writing anything.

| Need | Existing |
|---|---|
| Window chrome, drag, resize bounds | `Layout/Window.lua` (`GetContentFrame`, `GetContentSize`, `minW`/`minH` via `SetResizeBounds`) |
| The grid | `Layout/GridLayout.lua`, or wrapping `FlowLayout` — see §3 |
| Cell recycling | `Core/Pool.lua` (`Register` / `Acquire` / `Release` / `ReleaseAll`), ids prefixed `inventory.` |
| Search field | `Components/Input.lua` + `INPUT_SIGNALS.SUBMITTED`, plus `TEXT_CHANGED` for live filtering |
| Character picker | `Components/Dropdown.lua`, `options` may be a **function** resolved at build time |
| Scope segment | no component exists — see §3 |
| Confirm dialog | `Components/Modal.lua` with `confirmVariant = "danger"` |
| Glass plate | `SuuUI.Backdrop.Glass` |
| Position memory | `Core/MoveableFrame.lua`, one `position` key per window |
| Combat deferral | the pattern in `UnitFrame:_syncClickArea` and `ActionBarGrid._apply` |
| Blizzard template precedent | `Components/StanceButton.lua` — inherit, clear the template's art through each getter, compose our own visuals |
| Entry points | `Plugins/DataBar/BagsWidget.lua` (the `BAGS n` field) and `MicroMenuWidget.lua`'s `bags` entry, both currently calling `ToggleAllBags()` |
| Tooltip lines | `Plugins/Tooltips/Content.lua` — read lines via `tt.TextLeft<i>`, **never** a harness-only `GetLine` |
| Number formats | `Core/Readout.lua`. Do not invent a second k/M abbreviation |

---

## 3. New components

### `Components/ItemSlot.lua`

One bag cell. **A `Button` created from `ContainerFrameItemButtonTemplate`**, with our own
visuals composed over it and the template's art cleared.

Props: `bag`, `slot` (both required), `size`. API: `SetItem(info)`, `GetBag`, `GetSlot`,
`SetReadOnly(bool)`, `Refresh`. Emits `CLICKED`, `MOUSE_ENTER`, `MOUSE_LEAVE`, `SIZE_CHANGED`.

Five things this must get right, each of which fails silently:

- **The template's own OnClick does the work.** Never `SetScript("OnClick")`. Observe through
  `PostClick`, exactly as `UnitClickArea` and `ActionButton` do. That handler is what makes
  use, pickup, place, split and the at-a-bank deposit shortcut work at all.
- **Bag and slot are POSITIONAL and stated once.** `SetID(slot)` plus a parent whose `GetID()`
  is the bag — the template reads both. Nothing is ever re-pointed as contents change, so there
  is no `SetAttribute` churn and no mid-combat re-point to be refused. This is the discipline
  `Components/ActionButton.lua` arrived at the hard way.
- **Clear the art through each getter, never `SetNormalTexture(nil)`** — that call is refused
  outright on this client (measured during the action bar work). Fetch the Texture, empty it,
  hide *that*.
- **The cell is protected**, so it must not sit inside a frame that resizes at runtime unless
  that resize is combat-guarded. See §4.
- **Read-only mode drops mouse input**, which is refused on a protected frame in combat — so
  `SetReadOnly` is combat-guarded and deferred like any other protected mutation.

Quality border colour comes from `Game:ItemQualityColor(info.quality)` at **uncommon and
above** only, matching what `Plugins/Tooltips/Signal.lua` already decided: a white edge on a
dark cell reads as a selected state.

### `Components/ItemGrid.lua`

A pooled flat grid of `ItemSlot`s. Props: `containers` (an ordered list of bag ids), `cols`,
`cellSize`, `spacing`. API: `SetContainers`, `SetFilter(text)`, `SetSortMode`, `SetReadOnly`,
`Refresh`, `GetCounts`. Emits `SIZE_CHANGED`, `CHILDREN_CHANGED`.

- **Use wrapping `FlowLayout`, not `GridLayout`.** `GridLayout` derives column width from the
  container width, which is wrong for fixed square cells; a wrapping horizontal flow with a
  fixed cell size and `spaceXxs` gap gives exactly the intended geometry and already exists.
- **Filtering dims, it does not remove.** A non-matching cell drops to `opacityDisabled`-ish
  rather than being pulled from the layout, so the grid does not reflow under the cursor while
  the player types. This also keeps slot positions meaningful.
- **Every geometry change defers out of combat**, because the grid contains protected cells.
  Same shape as `ActionBarGrid`, including an `IsDeferred()` accessor.
- `CHILDREN_CHANGED` exists because the grid destroys and recreates cells when the container
  set changes, and that rebuild can itself be deferred — nothing else can tell a holder of cell
  references when they went stale.

### `Components/SegmentedControl.lua`

Two or three mutually exclusive labelled segments in one bordered strip. Props: `options`,
`value`. API: `SetValue`, `GetValue`, `SetOptions`. Emits `VALUE_CHANGED` (silent on `SetValue`,
per the setter contract).

Small, but it does not exist, and inlining it in the plugin would be the raw-frames violation
`WOW_API_ENCAPSULATION.md` forbids. It is reusable immediately — the settings UI has several
two-state choices currently rendered as dropdowns.

---

## 4. Plugin files

```
Core/ItemCache.lua         -- the account-wide cache: capture, queries, SuuUIItemCache

Plugins/Inventory/
├── Inventory.lua          -- plugin: lifecycle, settings, suppression, the open/close hooks
├── InventoryWindow.lua    -- ONE window, parameterised by { character, container }
├── SellGreys.lua          -- the confirm modal and the throttled loop
├── Sort.lua               -- display sort orders
└── AccountLedger.lua      -- the T3 tab
```

**The cache is a CORE service, not a plugin file.** Two plugins consume it — the inventory
window and the tooltip's account section — and a plugin may never call into another plugin. It
is the same argument that put `Core/DataBar.lua` and `Core/Dock.lua` there: the answer has to
exist whether or not the window that writes it is loaded, enabled, or came up first, and
disabling the inventory plugin must not silently stop the tooltip lines updating. An earlier
draft of this plan listed it under `Plugins/Inventory/`, which was wrong.

`InventoryWindow` is instantiated **twice at most**: the bags window and, during a bank
session, the bank window. It is the same renderer for live bags, a live bank and any snapshot —
so a fix to the grid fixes all three. That is the central structural decision of this plan.

**The protected-cell parentage rule.** The grid holds protected cells, so the frame that
resizes when the grid reflows must be combat-guarded. The window's own frame resizes when the
grid does, which means `InventoryWindow` defers its resize exactly as `ActionBarGrid` defers
its layout. Unlike the unit frames there is no foreign child to carve out, so the surface does
not need to live beside the window — but the deferral is not optional, and a bag gaining a slot
(a new bag equipped) in combat is a real trigger.

---

## 5. Data model — `SuuUIItemCache`

A **third** account-wide SavedVariable. `SuuUI.toc` currently declares only:

```
## SavedVariables: SuuUIProfiles
## SavedVariablesPerCharacter: SuuUIConfig
```

Add `SuuUIItemCache` to the account-wide line. It is not a preference, so it does not belong in
a profile: a profile switch must not change what your alts are holding.

```lua
SuuUIItemCache = {
  _version = 1,
  items = {                          -- account-wide, shared by every reader
    [22832] = { link = "|cff...|Hitem:22832...|h[Arcane Powder]|h|r",
                icon = 134129, q = 1, name = "Arcane Powder",
                -- THE FIVE ORDERING FIELDS, added for the `quality_type` sort: class, subclass,
                -- equip slot, item level, sell price. The container API reports NONE of them, so
                -- they come from `GetItemInfo` at upsert time, once per item id ever (guarded on
                -- `cls == nil`, since a class of 0 and a price of 0 are both real answers). They
                -- live here rather than being read live at sort time because a SNAPSHOT of an alt
                -- needs them and the client has no reason to have cached an item only an alt owns.
                --
                -- They top up on their OWN path, not through the record upsert: widening
                -- `Resolve`'s completeness test to include them was tried and it sent otherwise
                -- complete entries back through the full upsert, where a thin resolve overwrote a
                -- good icon. An entry from a SavedVariable written before these existed is
                -- backfilled on the next resolve or capture.
                cls = 7, sub = 12, eq = "", ilvl = 20, price = 55 },
  },
  chars = {
    ["Sulisande-Thunderstrike"] = {
      class = "PRIEST", money = 12844218,
      -- `seen` sits BESIDE `slots` rather than inside it: mixing one string key into an
      -- otherwise integer-keyed table invites an ipairs bug at every read site. `sizes` is
      -- there for the same reason and carries each container's CAPACITY, which cannot be
      -- recovered later: `slots` is sparse, so a bank holding three items in its first three
      -- slots is indistinguishable from a three-slot bank, and asking the client answers for
      -- whoever is logged in. Without it a cached container could only show its USED slots.
      bags = { seen = 1755900000, sizes = { [0] = 16, [1] = 16 },
               slots = { [0] = { [1] = {22832, 12} }, [1] = { … } } },
      bank = { seen = 1755730000, sizes = { [-1] = 28, [5] = 16 },
               slots = { [-1] = { [1] = {22832, 20} }, [5] = { … } } },
    },
  },
}
```

Sell price and max stack are deliberately **not** cached. The sell feature needs a live price at
the moment it sells, and the ledger does not show value in v1 — so caching them would be two
fields kept fresh for no reader.

- **Two tables, not one.** ~250 slots per character; a 60-byte link per slot per character is
  ~25 KB each and grows with every alt. An account-wide `items` table keyed by itemID plus
  per-character `{itemID, count}` pairs lands ten alts in tens of KB, and that item table is
  shared by the tooltip, the search index and the ledger for free.
- **Store the link AND the icon AND the name**, not just the id. `GetItemInfo` returns nil for
  an item the client has never seen and fires `GET_ITEM_INFO_RECEIVED` later — 22 installed
  addons handle that event, including TBC-specific code in
  `ChonkyCharacterSheet/Modules/TBC.lua:2110`. An id-only cache renders a wall of blank cells
  the first time you open an alt after logging in. Unresolved entries sort to the END and slide
  into place when the event arrives, rather than reshuffling the whole grid.
- **`seen` is per character AND per container.** Bags refresh whenever that character plays;
  the bank only when they visit one. Hour-old bags beside three-week-old bank data is the
  normal case, so one timestamp per character would be a lie. The window reports the age of the
  container it is actually showing.
- **`_version` is stamped** so a renamed key in a later build can be migrated on read, matching
  how `Core/Theme.lua` stamps `_tokenVersion`.

### Capture

| Container | When |
|---|---|
| bags | debounced `BAG_UPDATE` (coalesce a burst into one sweep), plus a full sweep at `PLAYER_LOGOUT` |
| bank | inside `BANKFRAME_OPENED` → `BANKFRAME_CLOSED`, which is the only window in which those slots are readable |

The bank session **is** the capture moment, so there is no separate capture pass and the
freshness stamp is simply "when you last stood there".

---

## 6. Live vs snapshot — one rule

**A container is live only when it is YOUR character AND currently reachable.** Your bags:
always. Your bank: only while the bank frame is open. Any other character, either container:
never.

That single rule covers every combination with no special cases, including pointing the *bank*
window at an alt while standing at a banker — which correctly becomes read-only while your own
bags beside it stay live.

A snapshot must LOOK inert, because there is no API that reaches another character's inventory
and no amount of clicking will ever work:

- an amber strip naming the container and its age (`bank seen 3 weeks ago`)
- sort and sell faded to `opacityDisabled`
- cells in read-only mode: no hover ring, no mouse
- the footer reads `N items cached` instead of `N free / M`

**Search stays live on a snapshot.** Searching a cached alt's bank from the middle of nowhere is
the single most useful thing in this feature.

**The bank window carries no sell button at all** — not a disabled one. You cannot sell from a
bank, and a greyed button says "not right now" when the truth is "never here". Sort does belong.

---

## 7. Opening, and suppressing Blizzard's bags

`ToggleAllBags` exists on this client and ElvUI secure-hooks it (already noted in
`BagsWidget.lua`). The bag-opening globals live in FrameXML and are replaceable Lua:
`ToggleBackpack`, `OpenBackpack`, `CloseBackpack`, `ToggleBag`, `OpenBag`, `CloseBag`,
`ToggleAllBags`, `OpenAllBags`, `CloseAllBags`.

- Resolve each by **existence check**, replace only what exists, and **restore the original on
  `onDisable`** — keep the originals in a table keyed by name. A plugin that cannot hand the
  default UI back is not finished.
- Suppress `ContainerFrame1..13` and `BankFrame` with the established **guarded-`OnShow`**
  pattern from `plugin-authoring.md`: a `suppressed` table, a permanent `HookScript` that
  consults it, and the flag cleared **before** the restoring `Show()`. Never
  `UnregisterAllEvents`, never `SetParent(nil)`.
- Route the existing entry points to the window once it exists: `BagsWidget`'s field click and
  `MicroMenuWidget`'s `bags` entry both currently call `ToggleAllBags()`, which will land on our
  replacement automatically — verify that rather than adding a second path.
- **Verify with witness cells, not with the container's `IsShown()`.** Hiding a container is the
  means; a bag cell being off the screen is the end. That distinction cost a diagnosis round in
  the action bar work (`MainMenuBar` vs `MainActionBar`).

---

## 8. Sell greys, and sort

### Sell greys

Blocked on the vendor probe in §0. Assuming selling is allowed:

1. Scan every bag slot for `quality == 0` **and** `hasNoValue ~= true` — a grey with no sell
   price cannot be sold and must be skipped, never counted as a failure.
2. Show a `Modal` with `confirmVariant = "danger"` naming **how many**, the **total value**, and
   the item names. With a flat grid there is no JUNK section to inspect, so the modal is the
   only place the player sees what is going, and selling is irreversible once buyback overflows
   12 slots.
3. On confirm, drain the list one item per tick from a shared `OnUpdate` at 0.2s (ElvUI's
   measured interval; expose 0.1–1.0s later if it proves flaky). One ticker, registered only
   while a sale is in flight.
4. Refuse to start unless `MerchantFrame:IsShown()`.

### Sort

**Display-only in v1**: the grid's render order changes, the real bags do not. Instant, cannot
fail, cannot be interrupted, works in combat, and it is what makes a flat 80-cell wall
navigable. Modes: quality desc then name (default), name, item level, and the container order
the client reports.

**Physical sort is deferred but no longer blocked** — `PickupContainerItem` is measured working.
When it lands it needs ElvUI's shape: a move list, one swap per tick, `isLocked` verification
before each step, and a hard stop in combat. Budget it as its own phase, not a flag on this one.

---

## 9. Settings schema (`inventory`)

Entries before the first `section` stay always-visible; everything after belongs to the
preceding section (`plugin-authoring.md`).

| Key | Type | Default | Notes |
|---|---|---|---|
| `enabled` | toggle | true | no `immediate` on its own watcher — `autoEnable` already applies the stored value |
| `suppress_blizzard` | toggle | true | its own top-level toggle, outside any group, so a player whose bags misbehave can get the default UI back without disabling the plugin |
| — | section | | **Layout** |
| `columns` | slider | 10 | 6–20 |
| `cell_size` | slider | 34 | 24–48 |
| `grouping` | dropdown | `flat` | `flat` ｜ `category` — the deferred grouping option, shipped as a stub returning `flat` in v1 |
| `sort_mode` | dropdown | `quality` | `quality` ｜ `quality_type` ｜ `name` ｜ `slot`. `quality_type` is the deep ordering — quality, then item class, then equip slot for gear or subclass for everything else, then item level, sell price and name, with conjured items demoted below poor. Modelled branch-for-branch on ElvUI's bag sorter but **named for what it produces**, not for the addon: the rule lives in `Components/ItemSortKeys.lua` with the provenance as a comment. Labelled "Quality + Type" rather than "Type" because quality is still the PRIMARY key — a rare trade good outranks an uncommon weapon and category only groups within a band |
| `sort_position` | dropdown | `start` | `start` ｜ `end` — which end of the grid the sorted run packs against. `end` is a **full reversal** of whichever comparator the mode resolved to, matching ElvUI's `sortInverted` (which is `true` in ElvUI's shipped defaults, though its install wizard sets it back to `false`). So in `end` quality runs ascending and names run Z→A; the gentler reading — empties relocated, items still best-first — was rejected because it would leave the two addons disagreeing side by side, which is the only reason to offer the setting. The wrapper is derived from the `SORTS` table rather than listed per mode, so `slot` inverts too and a fourth mode is covered for free |
| — | section | | **Bank** |
| `bank_side` | dropdown | `right` | which side the second window defaults to |
| — | section | | **Account** |
| `tooltip_counts` | toggle | true | the T1 tooltip section |
| `tooltip_show_zero` | toggle | false | list characters holding none |
| `account_badges` | toggle | false | T2, off by default and deliberately available |
| — | section | | **Selling** |
| `sell_confirm` | toggle | true | off means one click sells; keep the default on |
| `sell_interval` | slider | 0.2 | 0.1–1.0, `enabledIf = "sell_confirm"` is **wrong** here — it applies always |
| `position` / `bank_position` | position | — | written by `MoveableFrame`, no control |

Every key needs a `Settings:Watch` in the same edit, and prefer a **live applier** over a
rebuild: rebuilding drops the `MoveableFrame` registration and resets the stored position, so a
column-count change would move the window as a side effect.

---

## 10. Harness work

`Tests/harness/` has a PARTIAL container surface already, added by the bags data-bar widget
after this plan's first draft — so re-read it before extending rather than trusting this list.
What exists today: `state.bags` (indexed by bag id from 0, each `{ free, slots, bagType }`),
`H.setBags`, `H.setBagApi` with three modes, `GetContainerNumFreeSlots`, `GetContainerNumSlots`,
`env.NUM_BAG_SLOTS`, plus `state.items` / `H.setItemInfo` / `GetItemCount` from the tooltips
work.

**And it carries a defect that must be fixed first: `state.bagApi` defaults to `"legacy"`**,
which models a client with the bare globals and no `C_Container` — the exact opposite of what
§0 measured. Every existing bags spec therefore runs against a client shape that does not
exist. Flip the default to `"modern"`, keep all three modes (they are still the right way to
prove a reader survives either shape), and fix whatever specs assumed legacy. This is the same
class as the `GetLine` leak: a harness generous in the wrong direction cannot fail.

Follow the established `H.setAction` / `H.setAuras` conventions: staging **fires the event**,
`opts = { silent = true }` suppresses it, and an **unknown field name raises** rather than being
dropped.

| Addition | Size | Notes |
|---|---|---|
| flip `bagApi` default to `"modern"` | small | do this before anything else reads a container |
| `C_Container.GetContainerItemInfo` returning the measured table | medium | field set exactly as §0 lists it; nil for an empty slot, never a record of zeroes |
| `H.setBagItem(bag, slot, props, opts)` / `H.clearBagItem` | medium | merges; fires `BAG_UPDATE` |
| `H.setBankItem(bag, slot, props, opts)` | small | plus `H.setBankOpen(bool)` firing `BANKFRAME_OPENED`/`CLOSED` |
| bank readability gate | small | `GetContainerItemInfo(-1, n)` answers **nil** while the bank is closed, and slot/free counts answer 0 — model the measured behaviour, not the convenient one |
| `ContainerFrameItemButtonTemplate` as a frame subtype | medium | must model that its OnClick performs the action, and that `SetNormalTexture(nil)` is **refused** |
| `H.setMerchantOpen(bool)` + a sell recorder | medium | record `UseContainerItem` calls; **do not enact** a sale, for the same reason `RegisterStateDriver` is a recorder |
| `H.getCursorItem()` / cursor model | small | `PickupContainerItem` puts `{itemID, link}` on the cursor; placing onto an occupied slot **swaps** |
| item info store | small | `GetItemInfo`, `GetItemQualityColor`, `C_Item.GetItemSpell`, plus a `GET_ITEM_INFO_RECEIVED` path with items deliberately **absent** at first |
| SavedVariables round trip | large | there is currently no way for a spec to assert data survives a reload. Needed for the cache; scope it as its own phase if it grows |

**What the harness cannot prove**, to be stated in `TESTING.md` alongside the existing gaps:
that using an item is refused (the lockdown model gates eight geometry setters, not
`UseContainerItem`), and that replacing a FrameXML global does not taint. Both are in-game
checks.

---

## 11. Phases

| # | Deliverable | Visible in game? |
|---|---|---|
| 0 | The vendor-sell probe in §0 | — |
| 1 | Harness surface: `C_Container`, bags, bank gate, item info, cursor | **No** — `Tests/` is not in the `.toc` |
| 2 | `Core/ItemCache.lua` + the `SuuUIItemCache` SavedVariable + capture hooks | **No** |
| 3 | `Components/ItemSlot.lua` on the Blizzard template, art cleared, our visuals | **No** — nothing instantiates it yet |
| 4 | `Components/ItemGrid.lua` + `Components/SegmentedControl.lua` | **No** |
| 5 | `InventoryWindow.lua`: chrome, search row, footer. **Bags only, live, own character** | **YES — first pixel.** Open it from a slash command; do not suppress anything yet |
| 6 | Suppression + the bag-opening replacements, so `B` opens ours | **YES** |
| 7 | Bank session: the second instance on `BANKFRAME_OPENED`, item movement both ways | **YES** |
| 8 | Sell greys: confirm modal + throttled loop | **YES** |
| 9 | Display sort + the sort control | **YES** |
| 10 | Snapshot mode: character dropdown, read-only state, amber strip, `GET_ITEM_INFO_RECEIVED` fill-in | **YES** |
| 11 | T1 tooltip account section | **YES** |
| 12 | T3 account ledger tab | **YES** |
| 13 | Settings schema, `architecture.md`, `plugin-authoring.md`, `TESTING.md` | **No** |

State at the end of every phase whether there is anything to look at, and when there is, name
exactly what to click and what the WRONG result would look like — a green suite on invisible
work reads as "this should be working".

---

## 12. Risks and open questions

- **The vendor-sell probe (§0) gates Phase 8.** Do not write the loop first.
- **`SplitContainerItem` is untested.** Pickup works, so it very likely does too, but shift-click
  is a separate call — probe it when Phase 7 lands rather than assuming.
- **Replacing FrameXML globals may taint.** ElvUI secure-*hooks* `ToggleAllBags` rather than
  replacing it, which may be deliberate. If a replacement taints, hook instead and hide
  Blizzard's frame from the hook.
- **ElvUI is enabled on the test character** (its durability readout is on screen). Its bag
  module will fight ours for the same Blizzard frames — disable ElvUI's bags before the first
  in-game check, or the diagnosis is worthless.
- **The keyring (`-2`) is out of scope.** It is a container with its own rules and no v1 caller.
- **Bank bags 5..11 have per-bag slot counts** that must be read, not assumed; a player with
  fewer than seven bank bags has containers reporting 0 slots.
- **Cross-realm alts appear in the dropdown**, grouped by realm with the current one first.
  Nothing may imply items can move between them.
