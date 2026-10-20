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
| Trainer | `Units/Trainer.test.wowlua` | (from the checkpoint) services, Train and Train all, rows and headings, the game's frame out of sight |
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

- **The auction house's message queue stalls** (`auction.rs`, `done()`).
  An answer with another message queued neither sends it nor makes the
  system ready, though its doc says the next one is sent; nothing more is
  answered until the house closes. It shows at once here because the
  game's own browse list asks for more results as the house opens (next
  finding): SuuUI's search behind it never comes back. The tests stub
  `HasFullBrowseResults`, so the game's list doesn't ask.
- **A new `mock.defineAuctionHouse` keeps the last house's state**: what
  was bought (a commodity's first offer stays short), the browse
  results (not all told, so the game's list asks for more at the next
  open), and the player's auctions, while `nextAuctionID` starts again,
  so two auctions share an ID and cancelling one removes both. The tests
  give each house its own IDs and buy a commodity no other test uses.
  Probably a house should start clean when defined, or at least the IDs
  continue.
- **`GetItemKeyFromItem` returns the house data's own key table** (the
  browse row's, when there is one): SuuUI zeroes a gear key's item level
  before its sell search, which changes the data's row. The client gives
  a new table each call.
- **`C_Item.GetCurrentItemLevel` is nil for an item defined without
  `itemLevel`**, and the game's sell frame errors on it; the client has a
  level for every item. The test items give one.
- **Not findings, for the next areas**: a zero-delay timer (`after(0)`)
  set while `mock.advanceTime` runs comes due just after that advance, so
  a test advances once more to see it (the house opens within the
  second); `GetScript` gives a script without its `HookScript` hooks, so
  run an edit box's Enter with `mock.script`; the emulated clock starts
  at midnight on 1 January, so "today" needs an hour's advance first.

## Not tested, and why

Nothing in these four files.
