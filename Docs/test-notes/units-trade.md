# Test notes: units-trade

Area: AuctionHouse, Professions, Trainer and Macros (`src/Units/`).
Written on wowlua 0.9.4.

Trainer's and Macros' tests came from the WIP checkpoint 68d8ab6 and pass
as they were, every line covered. Professions' test (the checkpoint's
probe) is rewritten; AuctionHouse's is new.

Professions runs on the emulated client's open trade skill
(`mock.player:openTradeSkill(2018, "Blacksmithing")`, its real recipes).
The test character has no professions, so the overview stubs
`GetProfessions`, `GetProfessionInfo`, the spell book's entries, the
minimap's tracking and `GetTradeSkillDisplayName` (the engine answers
"Unknown"); the trainers SuuUI records stub the trainer's calls.
The engine records no Enchanting window (`openTradeSkill(7411,
"Enchanting")`: "no recorded window of ENCHANTING"), so the list's short
enchant names run on Blacksmithing's list with Enchanting's skill line and
one recipe renamed (stubbed `GetBaseProfessionInfo`, `GetRecipeInfo`).

The auction house runs on the engine's house (`mock.defineAuctionHouse`
and an auctioneer): opening and closing, browse searches, a commodity's
search and purchase, an item's search, posting an item, your auctions and
cancelling one. The engine has no bids, Scan all (`ReplicateItems`),
favourites or a commodity's post; the tests that need them stub those
calls, and capture the confirm dialog.

## Test files

| Source | Test file | Tests |
|---|---|---|
| AuctionHouse | `Units/AuctionHouse.test.wowlua` | opening and closing with the auctioneer, the game's frame out of sight (and back out when placed again); the foot's notes, money, a theme; the game's categories (the token's left out, subcategories, choosing and unchoosing, hover); a search: the results (item level, quality, Yours, what's offered, the lowest price), nothing found, more results, the filters, a search that doesn't go out, favourites, a result's tooltip; a commodity's offers (sellers, Yours, names not known yet), what most sell it for remembered, the foot (a quantity's price from the cheapest up, Max, why not), Buy now (the final price, a changed price, cancelled, the game's no, the game's answers); an item's auctions (the bid column, buyout or none, time left), choosing one, Bid with its least bid, Buy out asking first, the game's no, the slot's tooltip; Scan all (the mark, the progress three ways, reading a slice a frame, the result, the 15-minute wait, the last scan's time, no answer, refused); the tooltip block (lowest buyout, what most sell it for, offered, the stack, each setting); Sell: your items, a commodity (unit price 1c under what most sell it for, the quantity, the deposit, every reason Post is off), posting (confirmation, remembered, filled in next time, the game's no), asking before a cheap post, gear asked by its item ID alone, a bid-only post, nobody selling it, no answer and the retry, a dropped query, another item's answer, your own the cheapest, the item from a drag, a click, the bags' right-click, refused, gone; Auctions: yours (time left in hours or minutes, sold, a bid, cancelling and its cost, the house saying no), your bids (highest or outbid said once, your bid shown and forgotten when over, Bid again, Buy out, why not), the tabs; the settings' dependent rows; off |
| Professions | `Units/Professions.test.wowlua` | (rewritten) the recipes (categories, filters, search, five sorts), the chosen recipe (reagents, tools, cooldown, why not), where an unlearned one is learned (every kind of source, recorded trainers), the overview (professions, spells, tracking, drags, the opener macro, unlearning, empty slots, secondary ones), the rail, opening a recipe, tracking, creating, links, Blizzard's pages off screen, trainers recorded; enchanting's recipes listed without "Enchant " (search, the page, the tooltip and the setting) |
| Professions/RecipeLabel | `Units/Professions/RecipeLabel.test.wowlua` | the list's label: "Enchant " dropped for Enchanting only, names without it left as they are |
| Trainer | `Units/Trainer.test.wowlua` | (from the checkpoint) services, Train and Train all, rows and headings, the game's frame out of sight; the choice found again by name and rank when the list moves; Beast Training: a choice is the secure click on the game's own row (the game's list kept tall enough for a row of every service, a choice below its seventh row), Train the secure click on the game's Train, trained again and again wherever the choice sits, a free ability with no training points, Train off with its reason (combat, no game row, the choice not taken, the game's Train off), the secure button over a row kept inside the list and let go of at a fight's start, no TRAINER_DESCRIPTION_UPDATE needed, the game's rows and choice not tainted (the emulator's taint, at its class trainer), reopened and after a class trainer, what the pet knows counted Used (hidden with Used off) |
| Macros | `Units/Macros.test.wowlua` | (from the checkpoint) the tabs and list, the editor (New, Save, Delete, combat), the icon picker, the game's window replaced |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
all four sources.

## Refactors

- AuctionHouse: an unused local (the sell item's link, read and never
  used) is gone.

## Bugs found

- **Fixed: "Bought." and "Posted: …" vanished at once** (both builds).
  Every search results event cleared the foot's note, and the house
  searches again right after a purchase or a post, so the confirmation
  was gone within half a second. Only a note for what was asked
  ("Searching…", "Asking for the offers…") is cleared by results now.
- **Fixed: a bid typed for one auction stayed for the next** (both
  builds). Choosing another auction kept the amount if it was above that
  one's least bid, so Bid could place a bid meant for a different auction.
  Choosing another auction (or another of your bids) starts at its least
  bid.
- **Fixed: Scan all left the results drawn under the scanning mark**
  (both builds). The click drew the scan's parts only; the results stayed
  until something else redrew the page. The whole page is drawn now.
- **Fixed: Post stayed off after the game refused a post** (both builds):
  the post was forgotten but the form not drawn again.
- **Fixed: "1 sellers"** (both builds), for a commodity offer from one
  seller before the house tells the names: "1 seller".

## VM / wowlua findings (new)

All four fixed in wowlua 0.9.5 (decisions T228, T229); the tests run on
the fixed engine without workarounds.

- **The auction house's message queue stalled** (`auction.rs`, `done()`).
  An answer with another message queued neither sent it nor made the
  system ready, though its doc said the next one is sent; nothing more
  was answered until the house closed. It showed at once here because the
  game's own browse list asked for more results as the house opened (next
  finding), so SuuUI's search behind it never came back.
- **A new `mock.defineAuctionHouse` kept the last house's state**: what
  was bought (a commodity's first offer stayed short), the browse results
  (not all told, so the game's list asked for more at the next open), and
  the player's auctions, while `nextAuctionID` started again, so two
  auctions shared an ID and cancelling one removed both. A house defined
  with none open is a fresh one now.
- **`GetItemKeyFromItem` returned the house data's own key table** (the
  browse row's, when there is one): SuuUI zeroes a gear key's item level
  before its sell search, which changed the data's row. It is a new table
  at each call now, as in the client.
- **`C_Item.GetCurrentItemLevel` was nil for an item defined without
  `itemLevel`**, and the game's sell frame errored on it; the client has a
  level for every item. `mock.defineItem` gives level 1 now.
- **Not a finding**: the game's browse list, shown off screen, asks for
  more results itself as they come (as in the client), so SuuUI's More
  results button is tested with `HasFullBrowseResults` stubbed.
- **Not findings, for the next areas**: a zero-delay timer (`after(0)`)
  set while `mock.advanceTime` runs comes due just after that advance, so
  a test advances once more to see it (the house opens within the
  second); `GetScript` gives a script without its `HookScript` hooks, so
  run an edit box's Enter with `mock.script`; the emulated clock starts
  at midnight on 1 January, so "today" needs an hour's advance first.

## Not tested, and why

Nothing in these four files.

## The Ledger's transactions (2026-11-18, wowlua 0.13.15)

| Source | Test file | Tests |
|---|---|---|
| Ledger/Books | `Units/Ledger/Books.test.wowlua` | a row kept and read back (every field, a player's name, any characters), changed in place, a year kept and pruned, characters merged, the totals, where it came from and went (a sale after the cut, its deposit back against Deposits lost), an item's sales; a busy year's size (19,089 rows: 17 bytes a row, 317 KB) |
| Ledger/Matcher | `Units/Ledger/Matcher.test.wowlua` | several changes in flight to the oldest of their amount, other amounts, a direction only after the exact ones, a change before its expectation, Other after a moment, an expectation dropped in time or when its call failed; a group's share as a sum (2026-11-19: the line after two or three changes, between them, its rest taken by later changes no bigger than it, never a change an exact expectation takes nor money out, its rest dropped in time) |
| Ledger/Recorder | `Units/Ledger/Recorder.test.wowlua` | the game's formats; vendors (two sales in flight, a purchase, buyback, repairs, not the guild's), sales from the buyback list (its new entries: appended, rolled when full, one bought back; a sale the hook never saw one Vendor row, a right-click's still one; the entry and its money either way round 1.5 s apart; buying back only the Buyback row; 14 sales rolling the list each booked once), the mail (a sale with its invoice, a player's money, a COD, an expired auction, the money waiting, money sent with postage), trade, looted coin (one row per zone, the line before or after the money), a quest and Other merged, training, travel, the auction house (a post's deposit, a commodity bought, a buyout named by its notice, a bid, a cancel); as the second probe saw them: a letter with 1 copper charged the postage alone (-31), a send the server refused (`MAIL_FAILED`) expecting nothing, coin looted alone from the window (its line after the money not counted again) and a group's share by its line, a dungeon's shares as the 2026-11-19 probe saw them (one line for several changes, before, between or after them, a quest's reward between not taken), a free cancel with nothing left waiting, an expired and a cancelled auction's letters taken with `AutoLootMailItem` |
| Ledger/TransactionsPage | `Units/Ledger/TransactionsPage.test.wowlua` | by day with each day's net, the totals, the time, Kinds and Money, the search, the characters chosen, a row's item tooltip and page, the texts without an item, 2,000 rows drawn only in sight |

The engine runs the vendor (purchases, buyback, repairs; `mock.sell` for a
sale's answer), the mailbox (`TakeInboxMoney`, `TakeInboxItem`,
`SendMail` with postage), the trainer, the flight master and the auction
house (a post's deposit, a commodity's purchase). What it lacks is played
by the test: a bag slot's `/use` at a vendor sells nothing (V60: the
hook's handler is called, then `mock.sell`), a trade has no money and never
completes (V61), the postage leaves out the money attached and no send
fails (V62), a loot window has no coin (V63: the slot functions faked), a COD take pays nothing (V51), a single auction's bid or
buyout does nothing (V48: the hook's handler, the house's events and the
money). `AUCTION_HOUSE_SHOW_NOTIFICATION` with a kind that takes a name
(sold, won, outbid, expired) makes Blizzard's own handler fail without the
name (`ChatFrameUtil.GetAuctionHouseNotificationText`): the game always
names those, so the Sold note's test fires the formatted one.

## The Ledger opening without a freeze (2026-11-19, wowlua 0.13.15)

| Source | Test file | Tests |
|---|---|---|
| Ledger/PriceIndex | `Units/Ledger/PriceIndex.test.wowlua` | a pass a slice a frame, ready and told once, the deals furthest under first; few items at once; kept between asks (the same summaries, nothing worked out again); a look works out its item at once and logs it; a new day redoes everything, a deal setting the deal parts (the summaries kept); an item with no look left dropped from the deals; a vendor price known later |
| Ledger/Pack | `Units/Ledger/Pack.test.wowlua` | the last days' lows read from the front only (the lowest of a day, later days skipped, the kept days, the buffer cleared) |
| Ledger | `Units/Ledger.test.wowlua` | a Scan all's slices (`SCAN_SLICE` a frame) and its own deals (`ScanDeals`); the prune keeps the summaries, an item with no look left goes from the index and the deals |
| Ledger/PricesPage | `Units/Ledger/PricesPage.test.wowlua` | the loading mark while the rows are built; the rows kept between opens, a search's look changing only its row, each order made once; a deal setting and a new day build them again behind the mark; You sold waits for a year of transactions |
| Ledger/OverviewPage | `Units/Ledger/OverviewPage.test.wowlua` | the deals' loading mark while the index works (as after a /reload), then the top ones, at once on the next open |
| Ledger/BookStore | `Units/Ledger/BookStore.test.wowlua` | 200 days of two characters read and merged a slice a frame (told when done), a week at once; merged by time, then character; the lists kept until a change, then only the changed day again; an item's rows and the items sold kept |
| Ledger/TransactionsPage | `Units/Ledger/TransactionsPage.test.wowlua` | 150 days of 25 rows: All behind the loading mark, a new row making only its day's lines, the search's text a slice a frame then at once |
| Ledger/ItemPage, Ledger/Window | `Units/Ledger/ItemPage.test.wowlua`, `Units/Ledger/Window.test.wowlua` | your sales waiting for the year read ("Reading your transactions…"); the module off while rows are built, on again: built and shown |

How it was measured: a throwaway test (not committed) filled the store
with 7,000 items (one to six weeks of looks, one to four a day, names for
nine in ten) and six characters with a year of books (one with 55 rows a
day), then ran each step inside a frame and read each frame's cost from
`wowlua test --profile-out` (`<file>.frames.json`: per frame the
instructions, the estimated native weight and the emulator's wall time).
`debugprofilestop()` and `os.clock` give nothing inside a test (the
emulated clock stands still within a frame), so the profile's frames are
the only clock. Units below are those instructions plus native weight
(M = million), with the emulator's milliseconds (the dev build, with its
argument checks).

| Step | Before (one frame) | After (the worst frame) |
|---|---|---|
| Overview, summaries not worked out (after a scan, a /reload, a new day) | 77.6 M, 1,038 ms | 1.0 M a slice over 36 frames, the mark meanwhile |
| Prices, first open | 11.5 M, 214 ms | 1.0 M a slice; the first draw (rows made) 1.65 M |
| Prices, opened again | 3.5 M (sorted again) | 1.0 M (only redrawn) |
| A search's look while Prices shows | 10.3 M (every row again) | 0.85 M (its row) |
| Sort by name | 5.0 M | 0.44 M |
| Scan all, each frame | 9.0 M (800 items) | 1.2–1.3 M (200 items) |
| You sold (a year of books) | 20.5 M | 1.34 M (read 20 days a frame first) |
| Transactions, All (26,000 rows) | 10.7 M | 1.46 M first, 0.88 M after a new row |
| An item's page | 6.2 M | 1.23 M |

The emulator's speed is not the game's; in game each slice also stops
after 4 ms (`debugprofilestop`), so the slices stay small whatever the
machine. Before, the summaries' decode of all 60 days of every item was
most of it (`Pack.readNumber` with its argument checks: an exported
function is checked on every call in dev builds; the hot reads call a
local one now).

## One price store (2026-11-19, wowlua 0.13.15)

The auction house's looks are kept once per ruleset in the price store
(`Core/Prices`, `SuuUIPrices`); the Ledger and the auction house module
read it. `tests/unit/Core/Prices/PricesHelpers.wowlua` puts looks and
scans into it for the tests of both modules (`look`, `scan`, `wipe`), and
`LedgerHelpers` has `see` (a look as the auction house tells one: kept,
then the Ledger's watches see it), `scanAll` and `scanRead` (a Scan all
kept and read by the Ledger to its end, and the frame after for what it
told).

| Source | Test file | Tests |
|---|---|---|
| Core/Prices | `Core/Prices.test.wowlua` | a look kept and told, read back (latest, usual price, daily lows, every look, rulesets, items); when a look was; names packed, kept, read (the client's cache not kept), pruned; Scan all's looks a slice a frame, told once, a second scan finishing the first; the prune (once a day, a slice a frame, the names, told per ruleset); the API (only SuuUI's own modules write; the calendar; the number format); the migration (merging, a seen entry newer or not, everything moved and gone, run again, stopped half way, seen only); kept across a /reload; the saved size before and after |
| Core/Prices/Days, Pack, Store | `Core/Prices/*.test.wowlua` | moved from the Ledger; when a period starts (`timeOf`); the median and the usual price (from Ledger/Stats) |
| Ledger/Days | `Units/Ledger/Days.test.wowlua` | the Ledger's calendar is the store's |
| Ledger | `Units/Ledger.test.wowlua` | the looks read from the store (none kept in SuuUILedger); Scan all read once the store has it; the store's prune followed (and with the Ledger off); the auction house module off: what is kept still shown; off and on: the looks kept meanwhile read |
| Ledger/PriceIndex | `Units/Ledger/PriceIndex.test.wowlua` | the items a scan worked out skipped (ready at once when that's all of them) |
| AuctionHouse/Prices | `Units/AuctionHouse/Prices.test.wowlua` | a look kept in the store, the period's lowest; one per ruleset whoever scanned, posted prices per character; the Ledger off: kept, read, the tooltip block without the usual price; on again, the history read |
| compat | `compat/pricesFromLedger.test.wowlua`, `compat/pricesSeenOnly.test.wowlua` | old saved data (`prices-ledger.json`: the Ledger's prices and names, two characters' seen; `prices-seen-only.json`: only seen, three characters, two rulesets) moved in at load, and nothing changed by a second load |

How the size was measured: the test builds one ruleset's 7,000 items with
60 days of looks (one or two a day), their names, and three characters'
`seen` of every item (as their last Scan all left it), counts the bytes a
SavedVariables file holds for each (tabs, keys, values), runs the
migration and counts again: before 7,670 KB (the Ledger's prices
4,887 KB, names 259 KB, `seen` 2,524 KB, 841 KB a character), after
5,146 KB. One character's `seen` in game was 567 KB for 6,907 items (84
bytes an item; the test's entries carry every field, 123 bytes).

The profiles' JSON keeps table keys as strings (`"991201"`), where WoW
writes numbers; the migration reads both.

## The auction house idle with results shown (2026-11-19, wowlua 0.13.15)

Reported in game (0.21.0-dev+9568d10): the frame rate fell sharply while a
search's results only showed. wowlua's in-game profiler (57 s, 3,036
frames) had `AuctionHouseModule:Refresh > drawResults` 109 times while
idle, 106 of them over the frame's budget (the slowest 573 ms): every
row's look told to the price store, the Ledger's marks worked out per
row, every row drawn (14,500 row draws), 900 MB of garbage.

**The loop:** `drawResults` told each row's look to the price store
(`Seen`). An item on several rows (gear at several item levels, an item
with suffixes: common in a search) told its looks in turn; the store keeps
one look a period and the newer look's count wins, so each row's look
changed what the row before left, on every draw. Each change:
`SUUUI_PRICE_CHANGED` → the Ledger (`PriceChanged`, `Changed("prices")`)
→ `SUUUI_LEDGER_CHANGED("prices")` the next frame → the auction house's
handler (the marks follow the usual prices) → `QueueRefresh` → the draw
0.05 s later → the looks told again. With the Ledger off nothing listened:
no loop (and before 9568d109 the looks went into a plain table with no
message).

**Reproduced** (a test, `--profile-out`, 80 results of 40 items at two
item levels each, frames of 1/60 s): with the Ledger on a draw every 4th
frame for as long as the results showed (30 draws in 120 frames, 80
`SUUUI_PRICE_CHANGED` each), SuuUI's cost 217,000 a frame on average
(instructions plus the client's estimated native cost; 870,000 in each
draw's frame) against 2,000 when idle; the same with the price store
nearly empty or holding 5,000 items. Without repeated items, a commodity's
view, or the Ledger off: no loop.

**Fixed:**
- Drawing never writes: the results' looks are told when the house sends
  them (`AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`/`_ADDED`, Buy's
  `tellBrowseLooks`): one look an item (the lowest price of its rows, the
  units of them all), only what differs from what was told since the
  house last sent results; a name that comes later (its key's info) is
  kept by itself (`KeyArrived`).
- The results draw only the rows in sight (and two around them); scrolling
  hands the rows from line to line. Columns and the Ledger's marks
  (`DealMarks`) are worked out once a draw, not a row; the rows' click and
  hover made once.
- `ITEM_KEY_ITEM_INFO_RECEIVED` draws again only while the last draw
  showed a key without its info (Common's `keysMissing`; the game's own
  hidden frame asks for keys too).
- The Ledger's price index checks the day and the deal settings once a
  frame (and again after a deal setting changed), and `Deal` reads the
  settings the index read: no settings lookups a row.
- UI: `Money` with the same amount draws nothing (its text was built
  again on every call); an item slot draws its border and well only when
  what it shows changed; a scroll area's thumb runs an `OnUpdate` only
  while it is dragged (it ran on every frame for every shown table).

**Before and after** (the same harness; SuuUI's cost a frame, idle over
120 frames, and the frame of one draw the money's change asks for):

| Case | Idle before | Idle after | A draw before | A draw after |
|---|---|---|---|---|
| 80 rows, items on two rows, 5,000 items stored | 217,000 (a draw every 4th frame) | 1,900 | 866,000 | 63,000 |
| the same, store nearly empty | 217,000 | 1,900 | 862,000 | 63,000 |
| 520 rows (40 items, 13 levels each) | 1,322,000 (5.3 M each draw, 97 ms in the emulator) | 2,600 | 5,296,000 | 63,000 |
| 40 rows, one each | 2,200 | 2,200 | 379,000 | 66,000 |
| a commodity's view | 2,600 | 2,600 | 32,000 | 28,000 |
| 80 rows, the Ledger off | 1,200 | 1,200 | 535,000 | 57,000 |

Tests (`Units/AuctionHouse/Buy.test.wowlua`): results shown and idle for
120 frames with an item on two rows: one look (lowest price, units
together), no `SUUUI_PRICE_CHANGED`, no `Refresh`; a redraw tells nothing,
new results do. A key's info: drawn again only while a row waits for it,
its name kept. 60 results: only the rows in sight made and drawn, the
list as tall as all of them, scrolling to the end draws the last.

**Looked at as well** (the same harness, 5,000 items in the store): the
Ledger window idle on Overview, Prices, Transactions and Gold: no redraw,
about 2,000 a frame; its names queue asks 30 names a beat (0.2 s), each
item at most four times, then stops (5,000 unknown items: about two
minutes). The tooltip block reads the latest look and the usual price
(the index checks once a frame). Not fixed: `UI/CooldownTracker`'s driver
runs an `OnUpdate` every frame while the tracker is started, to look for
dirty cells (a few hundred instructions; making it wake on demand needs
the cells to tell the tracker).

## What it's worth, and what your characters hold (2026-11-19, wowlua 0.13.16)

The Gold tab's "What it's worth" values each character's bags, bank, mail
and auctions (`Core/Holdings`, `SuuUI.Holdings`) at its ruleset's usual
prices (`Ledger/Worth`). The places are the emulator's own where it has
them: bags and the bank from `mock.setBag` and `mock.defineBank` (a slot's
`bound = true` is the client's `isBound`), the inbox from
`mock.defineMailbox`, your auctions from the house's own post and cancel.
Other characters' bags and mail are written into SuuUIDB the way that
character would have saved them, then told (`savedBags:Told`).

| Source | Test file | Tests |
|---|---|---|
| Core/Holdings | `Core/Holdings.test.wowlua` | a reader given and read, nil for a character never read; a later one replaces it; only the place's module tells a change; released with its module (each place told); the API; the module lifecycle test counts places (`helpers.holdings` has `places`) |
| Bags/Characters | `Units/Bags/Characters.test.wowlua` | a saved bags as a holding (soulbound, when, live); the same items; the mail in the counts and in All characters (by its kept name; none without a name or a reader) |
| Bags/Saved | `Units/Bags/Saved.test.wowlua` | tooltips: "Bags 3 · Mail 2", the total with the mail, an expired letter gone, none with the mail module off; All characters lists the mail; bags and bank as holdings (soulbound, yours live, told only when they change; the bank each visit) |
| Mail/Inbox, Mail | `Units/Mail/Inbox.test.wowlua`, `Units/Mail.test.wowlua` | the inbox kept (money, COD, expiry, items; more than shown); read back without expired letters; kept on a visit and after Collect all, told; off: not read, kept, back when on |
| AuctionHouse/Auctions | `Units/AuctionHouse/Auctions.test.wowlua` | kept as the house opens and after a post (any tab), gone after a cancel; sold left out; ends by seconds or the band's longest; ended ones gone |
| Ledger/Worth | `Units/Ledger/Worth.test.wowlua` | usual price × count; soulbound, unseen, quest items and the hearthstone left out and counted; per ruleset; the mail's money less COD, never under 0; the places together; kept and dropped (a place, a look of an item held or not, a Scan all, a new day); at size (10 characters × 4 places × 400 kinds) a slice a frame, told once; work dropped when its place changes midway |
| Ledger/GoldPage | `Units/Ledger/GoldPage.test.wowlua` | the rows, "—" with how to count, "as of", "N not counted yet", one character, a ruleset at its prices, all of it, the note's count; following your bags and a price; the mail module off; the loading mark at 1,200 items; the note not cut off (whole, inside the page, the longest too) |
| Ledger/Worth (items) | `Units/Ledger/Worth.test.wowlua` | a place's items when asked: in item order, the price each or why (soulbound apart, never seen, quest item, hearthstone); items and money add up to the worth; the money's part under a dear COD; a result without items worked out again with them, prices kept; a job queued without items queued again with them, told once |
| Ledger/ItemsPage | `Units/Ledger/ItemsPage.test.wowlua` | the fifth tab; a row per place, Value first; the count and total equal to What it's worth (all, one character, a ruleset); a row's cells, the mail's money, the tooltip's places and "as of"; left out (the foot, Show, muted, why, dashes; All); per item ("2 places", the sums, the average Each over two rulesets, the tooltip); each column's sort and reversed, the orders kept; the place (one, more than one), Category, Quality, the search; the empty states (never read, nobody counted, the Mail and Bags modules off); the Gold rows opening their place; a row's item page at its ruleset and Back with the filters kept (Prices' Back unchanged); 1,500 kinds: Worth's and the rows' slices (never more than 600 rows a frame), kept, only your bags made again on their change, a price change its ruleset's places, nothing running after; the module off mid-way and on again |

Found: an item the emulator defines without an icon is never saved in the
bags' copies (the snapshot keeps a slot only with an icon, as the game
always gives one); the Ledger's test items got icons. A query to the
house while it answers another is dropped (the emulator's record), so
`askOwned` waits for `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`.
