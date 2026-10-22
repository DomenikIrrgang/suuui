# Test notes: units-character

Area: Collections, DressingRoom, CharacterWindow, Inspect and Durability
(`src/Units/`).
Written on wowlua 0.9.5 and the fixes after it (see the findings below;
they ship in 0.9.6).

Durability's test came from the WIP checkpoint and passes as it was.
CharacterWindow's is rewritten to drive the game's own character window as
the player does (its key, its tabs); Inspect's, DressingRoom's and
Collections' are new.

Inspect runs on the engine's inspect: another player spawned with their
gear (`setInspect`), targeted, and `/inspect` typed into the chat. The
dressing room runs on Blizzard's own `DressUpFrame`, its actor stubbed
(the engine's model scene has no actor). Collections gives the account its
mounts, toys and appearances with the engine's `mock.setMounts`,
`mock.setToys` and `mock.setAppearances` (decision T235): the journals,
their filters and events are the engine's.

## Test files

| Source | Test file | Tests |
|---|---|---|
| CharacterWindow | `Units/CharacterWindow.test.wowlua` | (rewritten) the header and the mode tabs, the identity line and a level up, a gear slot's quality edge and redraw, the popout arrows, the item flyout, the new-set popup, the stat rows and their colours, the stats pane without a view, Stats / Sets / Titles, the right pane's toggle, the other tabs and the titles, the window's addon loading after SuuUI |
| Durability | `Units/Durability.test.wowlua` | (from the checkpoint) |
| Inspect | `Units/Inspect.test.wowlua` | the identity line, the chip's difference, the rank, the guild line, why View Talents is off; opening at once while the gear is read, the game's frame out of sight; their gear (item, quality, level, an empty slot, the item level); Compare with mine; too far away, no item level; PvP and the guild; a slot's tooltip and click; View in Dressing Room, View Talents; turning and zooming the model; closing both ways; a new target, no answer, another player's answer; redraws; off |
| DressingRoom | `Units/DressingRoom.test.wowlua` | the outfits by name, why Save is off, the count; the game's dressing room opening SuuUI's over it; the pieces; what you wear from your item's link; a piece's tooltip, link and ×; choosing, saving and changing an outfit; Save as new (name, icon, refused, full); Delete and Link; Reset and Undress; a mount's and a pet's preview; a burst of changes drawn once; off |
| Collections | `Units/Collections.test.wowlua` | a source as a line and as a card (every kind); the mounts' order and sources; the day first seen, the last collected; the toys' order and names to come; the weapon kinds and each slot's counts; a slot's appearances; search and filters; the stage's action and a toy's Use; Mounts (the strip, the card, the count, the foot); a cell's tooltip; paging; the model loading; turning and zooming; Summon, Dismiss, combat; the favourite star; Toys and their cooldowns; Appearances (the doll, the slots, the tiles, trying on); opening (SuuUI's toggle, the game's key, the game's journal); the game's news; off |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
all five sources.

## Bugs found

- **Fixed: the character window's item flyout errored** (both builds).
  SuuUI hid the regions of the flyout's highlight, but Blizzard's
  highlight is a texture, with no regions; the skin stopped there, so the
  flyout kept Blizzard's look. The highlight itself is hidden now.

## VM / wowlua findings (new)

All fixed in wowlua (decisions T230 to T234, shipping in 0.9.6); the
tests run on the fixed engine without workarounds.

- **`wowlua test --coverage` crashed: "internal compiler error: stale
  handle"** when code it counts was collected during the run (a Blizzard
  frame's script replaced). The collector didn't keep the counted
  functions alive.
- **No way to change a Blizzard field without tainting it.** A test that
  took a frame away with an assignment left Blizzard's field tainted, and
  the game's code errored later in the file. `mock.setField(t, key,
  value)` sets one until the test ends and puts it back secure (T230).
- **An inspected player's gear had only its link**:
  `GetInventoryItemID`, `GetInventoryItemTexture` and
  `GetInventoryItemQuality` answered nothing for them (T231).
- **`mock.spawnUnit`'s `healthMax` and `powerMax` were ignored**, though
  declared, and the types lacked some unit fields and methods the engine
  reads (`factionGroup`, `setInspect`, ...), so strict tests couldn't use
  them (T232).
- **`GetText` was missing.** Blizzard's inspect frame reads the gender's
  form of a global string with it.
- **`mock.slash` skipped Blizzard's commands** (`/inspect` did nothing,
  silently): the game keeps them in its own lists. With Blizzard's chat
  loaded the line is typed into the chat and sent, as the player does
  (T233).
- **A model's `GetItemTransmogInfoList()` was empty**, and Blizzard's
  dressing room errored on the main hand's entry; it has every slot now.
- **A key bound with `SetOverrideBindingClick` clicked twice** (on the
  press and the release), so SuuUI's Collections key opened and closed
  the window at once. A button clicks only for the clicks it registered
  (T234).
- **The journals had no collections**: the wardrobe, toy box and mount
  journal answered their recorded empty state. A world profile and
  `mock.setMounts`, `mock.setToys`, `mock.setAppearances` give them the
  account's now (T235).
- **Fixed later (T261)**: there was no "any value" matcher for
  `toHaveBeenCalledWith`; `anything` and `ofType(kind)` from `wowlua:test`
  are those now.
- **Not findings, for the next areas**: `mock.click` leaves the pointer on
  the frame, so `mock.hover(nil)` before hovering it again; change
  Blizzard's fields with `mock.setField`, never an assignment.

## Not tested, and why

Nothing in these five files.
