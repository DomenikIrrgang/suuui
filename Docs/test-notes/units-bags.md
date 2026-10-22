# Test notes: units-bags

Area: Bags (`src/Units/Bags.wowlua` and its sibling modules
`src/Units/Bags/`: Sort, Characters), MicroBags, Merchant, Mail and Loot
(`src/Units/`). Written on wowlua 0.9.4.

The sibling modules came from the WIP checkpoint 68d8ab6 (the sort's
planning and the saved characters' data as pure functions), with a test
file each in `tests/unit/Units/Bags/`; they pass as they were, except one
expectation in Characters' test (below). The old regression test
`tests/units/bagsort.test.wowlua` (two special bags in a sort's plan) is
folded into `Units/Bags.test.wowlua`, and `tests/units/` is gone.

The windows are tested on the emulated client's own systems where it has
them: bags filled with `mock.setBag`, the bank with `mock.defineBank` and a
banker, a vendor with `mock.openMerchant` (selling, buying back), a
mailbox with `mock.defineMailbox` (letters with items, money, COD, an
invoice), a party and a raid formed by invites. The test items are
`mock.defineItem`s with `{ cached = true }` (see the findings). What the
engine has no world for is stubbed in the test that needs it: the loot
window's slots and group loot rolls (the engine has no group loot), a bank
tab's bag, extended costs, the guild bank's repair, the tooltip of a
bank slot; notifications and the confirm dialog are captured.

## Test files

| Source | Test file | Tests |
|---|---|---|
| Bags | `Units/Bags.test.wowlua` | which bags; opening and closing with Blizzard's calls (toggle, a bag closing, the close button, opened for a window and closed with it, open before); the slots (items, free counts, a bag shrinking, the reagent bag's and keyring's sections, updates, locks, cooldowns); the bag rail (cells, tooltips, lighting, putting a bag in, picking it up, the setting and the header's toggle); the bank (beside the bags, Blizzard's frame off screen and back, its rail, the buy cell's cost and reasons, a bank slot's bag, closing, the setting off, tabs without the game's list); another character's bags and bank (read only, the tooltip, links); the search and All characters; item counts; selling junk; sorting (waves, the game's sort, combat, an item in hand or picked up mid-sort, the window closing, a refused move, the bank's refused move and the game's bank sort); Forget a character; the preview; Blizzard's frames kept hidden; money and gear saved; the old two-special-bags regression |
| Bags/Sort | `Units/Bags/Sort.test.wowlua` | (from the checkpoint) the plans: stacks, targets, waves, wave states |
| Bags/Characters | `Units/Bags/Characters.test.wowlua` | (from the checkpoint, one expectation fixed) labels, order, banners, results, counts, the foot |
| MicroBags | `Units/MicroBags.test.wowlua` | with SuuUI's own micro menu and bags: Blizzard's bag bar put away and kept away; without them: both in holders at Blizzard's size × Scale, again on a new scale, back when Blizzard moves them, left where the game takes them, Shows, the Scale format |
| Merchant | `Units/Merchant.test.wowlua` | opening and closing with the vendor; the goods (quality, price, stack, left, you have, can't use, known); quantities (purchases, items, capped by stock or money, kept per vendor); buying in chunks, stopping with the vendor; asking first (dear, other costs); search, filter, empty; buy back and the last sold; repair all, one, the guild's; sell junk; the worn gear line; currencies; tooltips and links; refreshes; off |
| Mail | `Units/Mail.test.wowlua` | opening and closing; the inbox (sender, unread, days, money, items, COD, empty, more waiting); the open mail (text, invoices, attachments, money, COD, Reply, Delete, Return); auto loot; Collect all and Collect money (COD and GM skipped, full bags, a pending command); sending (what it needs, money, COD, success, failure, a cancelled confirmation, the 30 s timeout, attachments, the counter); To's suggestions (your characters, recent, the guild with last online, typed matches; arrows, Enter, Tab, hover, click, leaving); Sent; /suu mailsuggest; a level up; a theme; off |
| Loot | `Units/Loot.test.wowlua` | the window's items and money; beside the cursor or at its place; whose loot; auto loot; taking, linking, a slot cleared, closing; tooltips; Blizzard's frame off screen; the preview; the game's formats as patterns; a roll's card (bind, time, Disenchant, can't need and why); choosing; the loot lines (votes, changing a vote, yours, numbers, the winner, you won, all passed, a line without the history link); who's still choosing (party, raid, and more); the item tooltip; the test rolls; without Notifications; rolls running after a reload |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
all seven sources.

## Refactors

- Bags: the bag rails' "locked" bank slot (its tooltip, glyph and checks)
  and the hiding of a buy cell on a rail without one are gone: the rail
  never lists a locked slot (the buy cell stands for them) and only the
  bank's rail has a buy cell, so neither could run.

## Bugs found

- **Fixed: loot rolls never showed in the notification stack** (the wowlua
  build). Loot set them up in its OnEnable only if the Notifications module
  was on, and the modules turn on in the order they load: Loot first. So
  Blizzard's roll frames kept showing and nothing else did. The rolls are
  set up once Notifications turns on (`SUUUI_MODULE_ENABLED`).
- **Fixed: no vote, roll number or winner was ever read from the loot
  lines** (both builds). This client's lines start with a link to the
  loot history (`|HlootHistory:%d|h[Loot]|h: %s has selected Need for:
  %s`), so the first capture was the history's number, not the player.
  The link is taken off the formats and the lines (numbered arguments,
  `%2$s`, counted one lower then).
- **Fixed: "You passed on", "Everyone passed on" and "You won" were read as
  someone's vote or win** (both builds): they fit "%s passed on: %s" and
  "%s won: %s", which came first. The specific lines come first now.
- **Fixed: bags opened SuuUI's way (or open before a vendor or the mail)
  closed with that window** (both builds). Blizzard's `CloseAllBags(frame)`
  closes the bags it opened for the window one by one, and those inner
  calls closed SuuUI's window too; and its `OpenAllBags(frame)` opens the
  backpack first, so the window opening them was never noted. Whether the
  window was open, and who opened it, is now read at the first call of the
  moment.
- **Fixed (a test): Bags/Characters' order expectation.** Characters sort
  by name, a nameless one by its key, byte by byte ("Bryn" before "a-R");
  the checkpoint's test expected otherwise.

## VM / wowlua findings (new)

- **`mock.defineItem(id, data)` without `opts` never loads** (fixed in wowlua 0.9.5: cached by default, as documented): `GetItemInfo`
  returns nothing, then and seconds later; with `{ cached = true }` it
  answers at once. The docs say `opts.cached = false` makes it load later,
  which reads as cached by default.
- **Fixed in wowlua (T256): an item put onto a part stack of its own
  kind wasn't stacked.** The engine kept it on the cursor; the client
  stacks it (SuuUI's `/suu probe bagsort`, 2026-10-19), and SuuUI's sort
  counts on it. The engine stacks it now, in the probe's recorded order;
  the sort tests put part stacks together, in the bags and the bank, and
  the bank's fallback is tested through the game's error message.
- **Many events' payloads are checked in full** (`CHAT_MSG_LOOT` with its
  Discord info, `PLAYER_LEVEL_UP` with ten deltas, `GUILD_ROSTER_UPDATE`,
  `ITEM_LOCK_CHANGED`): right, but a test that only needs the event names
  every argument. Defaults for the trailing ones would help.
- **Not findings, for the next areas**: a party forms (you leading) a moment
  after the invite, so a test waits before `joinGroup` and before
  `C_PartyInfo.ConvertToRaid`; a `mock.click` leaves the pointer on the
  frame, so a `mock.hover` of the same frame right after runs no `OnEnter`
  (`mock.hover(nil)` first); stubbing `IsInRaid` or the group size reaches
  Blizzard's own unit frames (secret values, tainted): form a real group.

## Not tested, and why

Nothing in these seven files.
