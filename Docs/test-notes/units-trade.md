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
| Professions | `Units/Professions.test.wowlua` | (rewritten) the recipes (categories, filters, search, five sorts), the chosen recipe (reagents, tools, cooldown, why not), where an unlearned one is learned (every kind of source, recorded trainers), the overview (professions, spells, tracking, drags, the opener macro, unlearning, empty slots, secondary ones), the rail, opening a recipe, tracking, creating, links, Blizzard's pages off screen, trainers recorded |
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
| Ledger/Matcher | `Units/Ledger/Matcher.test.wowlua` | several changes in flight to the oldest of their amount, other amounts, a direction only after the exact ones, a change before its expectation, Other after a moment, an expectation dropped in time or when its call failed |
| Ledger/Recorder | `Units/Ledger/Recorder.test.wowlua` | the game's formats; vendors (two sales in flight, a purchase, buyback, repairs, not the guild's), sales from the buyback list (its new entries: appended, rolled when full, one bought back; a sale the hook never saw one Vendor row, a right-click's still one; the entry and its money either way round 1.5 s apart; buying back only the Buyback row; 14 sales rolling the list each booked once), the mail (a sale with its invoice, a player's money, a COD, an expired auction, the money waiting, money sent with postage), trade, looted coin (one row per zone, the line before or after the money), a quest and Other merged, training, travel, the auction house (a post's deposit, a commodity bought, a buyout named by its notice, a bid, a cancel); as the second probe saw them: a letter with 1 copper charged the postage alone (-31), a send the server refused (`MAIL_FAILED`) expecting nothing, coin looted alone from the window (its line after the money not counted again) and a group's share by its line, a free cancel with nothing left waiting, an expired and a cancelled auction's letters taken with `AutoLootMailItem` |
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
