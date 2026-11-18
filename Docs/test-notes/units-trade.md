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
| Ledger/Matcher | `Units/Ledger/Matcher.test.wowlua` | several changes in flight to the oldest of their amount, other amounts, a direction only after the exact ones, a change before its expectation, Other after a moment, an expectation dropped in time |
| Ledger/Recorder | `Units/Ledger/Recorder.test.wowlua` | the game's formats; vendors (two sales in flight, a purchase, buyback, repairs, not the guild's), the mail (a sale with its invoice, a player's money, a COD, an expired auction, the money waiting, money sent with postage), trade, looted coin (one row per zone, the line before or after the money), a quest and Other merged, training, travel, the auction house (a post's deposit, a commodity bought, a buyout named by its notice, a bid, a cancel) |
| Ledger/TransactionsPage | `Units/Ledger/TransactionsPage.test.wowlua` | by day with each day's net, the totals, the time, Kinds and Money, the search, the characters chosen, a row's item tooltip and page, the texts without an item, 2,000 rows drawn only in sight |

The engine runs the vendor (purchases, buyback, repairs; `mock.sell` for a
sale's answer), the mailbox (`TakeInboxMoney`, `TakeInboxItem`,
`SendMail` with postage), the trainer, the flight master and the auction
house (a post's deposit, a commodity's purchase). What it lacks is played
by the test: a bag slot's `/use` at a vendor sells nothing (V60: the
hook's handler is called, then `mock.sell`), a trade has no money and never
completes (V61), a COD take pays nothing (V51), a single auction's bid or
buyout does nothing (V48: the hook's handler, the house's events and the
money). `AUCTION_HOUSE_SHOW_NOTIFICATION` with a kind that takes a name
(sold, won, outbid, expired) makes Blizzard's own handler fail without the
name (`ChatFrameUtil.GetAuctionHouseNotificationText`): the game always
names those, so the Sold note's test fires the formatted one.
