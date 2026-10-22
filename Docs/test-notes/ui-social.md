# Test notes: ui-social

Area: the Group Finder, Guild and Social windows' views in `src/UI/`:
GroupFinder (Browse), GroupFinderListed (My listing), GroupFinderListing
(the game's List yourself panel, restyled), GroupFinderWho, Guild (Roster,
Info, Log, the message of the day banner), GuildControl (the game's guild
control window, laid out) and Social (Contacts, Raid, lists of people).
One test file per source file in `tests/unit/UI/<File>.test.wowlua`, plus a
shared helper, `tests/unit/UI/SocialHelpers.wowlua` (the token Draw keeps
for a region and its alpha, the theme message, hosts that are hidden after
each test).

The views are driven the way their modules drive them: built in a host,
fed with `SetData`, and worked through the user's input (`mock.click`,
`mock.hover`, `mock.typeText`, `mock.pressKey`, `mock.script` where the
mock has no gesture: double clicks, drags, OnSizeChanged). Callbacks are
spies, checked for their arguments; what is drawn is checked with the
widget matchers and the colour token each region keeps. Tooltips that go
through `/UI/Tooltip` are stubbed (`mock.stub` on the module's namespace)
so the tests check what the tooltip is asked to say; GameTooltip's lines
are read directly.

The two skins of the game's frames (GroupFinderListing, GuildControl) run
against the real Blizzard addons (`mock.loadAddon("Blizzard_GroupFinder_
VanillaStyle")`, `"Blizzard_GuildControlUI"`), with the game's state faked
per test (`GuildControlGetNumRanks`, `C_Discord.*`, the bank tab
functions, `LFGListingFrame`'s selection methods). Rows of the activity
tree are made from the game's own `LFGListingActivityRowTemplate`.

## Test files

| Source | Test file | Tests |
|---|---|---|
| GroupFinder | `GroupFinder.test.wowlua` | toolText cases; barWidths (room for all, Search first, the selects by share, the age last, everything at its least); the bar showing its data and defaults, a search being typed left alone, the tool's age and stale Refresh (primary, not while searching), the bar's widths on a resize, every bar control's onFilter (checkbox, search, the three selects through their open lists), Refresh quiet/primary; the sections (counts, collapsed, onToggle), the first search's skeleton rows and note, the empty state with Clear filters and Refresh, Draw before data, a list resize; a group's row and a player's row (lead, level chip, sprout, reason, leader colour, post, count, slots, roles label, badges, Invite), the post cases, the count needing both numbers, every role icon kind (offered, a member's, roleless, needed and yours, open, fewer next time), hover tooltips (post, slots), Whisper/Invite |
| GroupFinderListed | `GroupFinderListed.test.wowlua` | the listing's facts and roles, what's left out when unknown (and activities without a category), the ad (channel, text, Post label, last posted, count), over the limit and blank, typing (onText, focus edge, data not replacing what's typed, Escape), every button's callback (Update, Delist, From my listing, Post with channel and text, the channel select), a resize and a theme change |
| GroupFinderListing | `GroupFinderListing.test.wowlua` | skinned once (and without a panel), a role toggle's looks (on, off, hover, disabled, covered), New player friendly, your role in a group (OnShow, the game's update, another icon), the top solo and in a group, the category cards (glyphs, lines, hover, kept parts, hidden/narrow), step 2 (Playstyle required, the tree, Custom), the details' placeholder and count and focus edge, the scroll box kept in the tree, a heading row (all/some/none, chevron, "n chosen", totals), an activity row (quest colours, level range, PostClick redraw), the game's row setup, locked, the foot (widths, primary looks), Queue (once, while shown, theme), the game's redraws and shows |
| GroupFinderWho | `GroupFinderWho.test.wowlua` | countText cases, columns, the idle page, results (cells, class colours, fewer rows), nothing found, choosing and the foot's callbacks, new results dropping the choice, the foot without callbacks or a choice, the right-click menu, hover, Search and Enter, Filter, a resize |
| Guild | `Guild.test.wowlua` | columnsFor; the roster empty, members (class colours, faded offline, last online, badges, class icons, the old class texture), the headings (sort colour, click, hover), the selected member and the foot (enabled, reasons, callbacks, guild invite), a disabled button's tooltip and Remove's ember, clicks/right clicks/double clicks, row hover (onRowEnter/Leave, officer note tooltip), search and Show offline, a resize; Info (text, empty, Edit, ranks, layout, resize); Log (lines, empty, resize); the message of the day (none, text and Edit and height, too narrow, the cut-short tooltip, resize); a theme change |
| GuildControl | `GuildControl.test.wowlua` | sentence cases; the window in its host (head row, unknown page, busy); Guild ranks (labels, icon buttons and reasons, New rank, ten ranks, unreadable count); icon buttons (dimmed, reason tooltip, hover); Rank permissions (checkboxes, officer powers, card edge, authenticator); Bank tabs (table head, an owned tab, the tab to buy next/first, the purchase button's looks); Discord (not linked card, linked card, Unlink); a theme change; a rank dropdown without a label; a window with the game's other frame parts |
| Social | `Social.test.wowlua` | Contacts: the top (BattleTag, status dot, count), friends grouped online/offline, a friend's row (character, Battle.net, offline, badges, notes), Whisper/Invite with their reasons and tooltip, row clicks (select, menu, double-click whisper), the ignored view (Unignore, Ignore a player), the view and status controls, a resize and a theme change; Raid: not in a raid (Convert), the groups and slots, the head's buttons and reasons, the head's layout (tightening, the count below), the groups' layout, a slot's tooltip and click, dragging (move, swap, onto itself or nowhere, the ghost), drag guards (lead, empty slot, combat, no data), a theme change; PeopleList: rows, buttons and actions, empty, a right click, a resize and a theme change |

Coverage (`wowlua test -j 2 --coverage`, each file measured with its own
test file):

| Source | Lines | Branches | Functions | Conditions |
|---|---|---|---|---|
| GroupFinder | 480/480 (100 %) | 237/272 (87.1 %) | 32/32 | 149/182 |
| GroupFinderListed | 239/239 (100 %) | 97/112 (86.6 %) | 19/19 | 65/76 |
| GroupFinderListing | 556/556 (100 %) | 274/418 (65.6 %) | 55/55 | 172/250 |
| GroupFinderWho | 224/224 (100 %) | 89/102 (87.3 %) | 22/22 | 55/66 |
| Guild | 440/440 (100 %) | 273/318 (85.8 %) | 41/41 | 177/218 |
| GuildControl | 678/678 (100 %) | 300/456 (65.8 %) | 33/33 | 154/232 |
| Social | 643/643 (100 %) | 442/518 (85.3 %) | 62/62 | 274/342 |

Every line and function runs. The branches left:

- **The middle of `a and B or C`** with a constant `B` (`mine and "arcane"
  or "ink-faint"`, `x and true or false`): the "B is falsy" outcome counts
  as a branch and can't happen. Most of the gaps in the five views.
- **The game's parts that this build has** (GroupFinderListing,
  GuildControl): `if lr.Checkbox then`, `if c.EditBox then`,
  `_G[base .. "…"] or …` and the like guard frames the game might rename;
  in the camelot build every one is there, so the "missing" side never
  runs. That is why those two files sit at ~65 %. Marking them `coverage
  ignore` would hide whole lines that do run, so they are left as they are.

## Refactors

Behaviour unchanged in every case; `tests/smoke` and `tests/compat` pass.

- **Types for every view.** Each file now exports the types of its data
  and of the objects it builds (`GroupFinderBrowse` with `BrowseData`,
  `BrowseRow`, `BrowseFilter`; `GroupFinderListed` with `ListedData`;
  `GroupFinderWho` with `WhoData`, `WhoResult`; `GuildRoster`, `GuildInfo`,
  `GuildLog`, `GuildMotdBanner` with their data; `GuildControl`;
  `ListingSkin`; `Contacts`, `RaidGroups`, `PeopleList` with theirs, and
  the row and part interfaces). The builders return them instead of an
  untyped frame, and the method tables are typed as the interface (the
  pattern `Controls.wowlua` uses). This made the strict tests possible
  without `any`, and the checker now checks the views' own code. What the
  checker asked for along the way, each the same at run time:
  - optional fields read once into a local before use (`local d = r.data;
    if d then … end`) instead of reading `r.data` twice;
  - `ROLE_TEX[x]` read into a local before `SetTexture`;
  - Guild's `SetTexCoord(unpack(coords))` spelled out as the four values;
  - Social's footer reasons as an `if selected … else … end` instead of
    one `and/or` chain (same values in every case);
  - GroupFinderWho's foot actions take a getter for the callback instead
    of indexing the page by a string;
  - `GuildMotdBanner`'s tooltip reads `d.text or ""`.
  The callers (`src/Units/GroupFinder`, `Guild`, `Social`) reach the views
  through `SuuUI.UI`, typed `{ [string]: any }`, so nothing changed for
  them; `wowlua check` reports nothing new anywhere.
- **GroupFinder:** the tool's age text (`toolText(tool)`) and the bar's
  width sharing (`barWidths(width, fixed, fresh)`) moved out of `SetData` /
  `LayoutBar` into file-level functions, tested alone with `import
  internal`. `LayoutBar` calls `barWidths` with the same inputs.
- **GroupFinderWho:** the count text moved into `countText(d)`.
- **Social:** `RaidMember.index` and `.group` are required in the type: the
  page indexes its groups by `group` (a member without one errored, "table
  index is nil", before and after), and the Social module always sets both.

## Bugs found

None fixed, none skipped.

## VM suspicions

Two are already in `ui-primitives.md` and were met here too (the tests run
the script as the game would, with a comment pointing there):
`OnSizeChanged` only for an explicit `SetSize`/`SetWidth` (a page anchored
to a resized parent never relays its list), and `EditBox:SetText` without
`OnTextChanged` (GroupFinderListing's details count).

New:

1. **`ADDON_ACTION_BLOCKED` for `UNKNOWN()` out of combat.** Showing the
   group finder's parent frame from a test, out of combat, makes SuuUI's
   Fault log `Taint: Blocked in combat: UNKNOWN()` (it hears
   `ADDON_ACTION_BLOCKED`). In the game an insecure `Show()` of a frame is
   only refused in combat, and the event names the function. Unverified
   which call inside the frame's OnShow the emulator refuses. Repro:
   ```wowlua
   @test("probe") local function probe()
       mock.loadAddon("Blizzard_GroupFinder_VanillaStyle")
       ;(_G :: any).LFGParentFrame:Show()
       expectNoErrors()   -- fails: "Taint: Blocked in combat: UNKNOWN()"
   end
   ```
   The tests run the hooked OnShow scripts with `mock.script` instead.
   *Later: not a bug.* It is SuuUI's own search on open, which the game
   allows only from the user's click or key press (recorded in wowlua);
   through `pcall` the event names `UNKNOWN()`. SuuUI's log now says
   "Blocked" for a call refused out of combat.
2. (Not a suspicion, for the next reader) `GetAlpha()` after `SetAlpha(0.5)`
   reads 0.50196 (a byte): the tests compare alphas with `toBeCloseTo`.

## wowlua compiler / runner issues

1. **`@cases` literals aren't typed by the parameter** (new, not in the
   0.9.1 report). A case's table is inferred on its own, so a string
   literal field is `string`, and a parameter whose type has a literal
   union for it rejects the case (E8120):
   ```wowlua
   type D = { state: "idle" | "results" }
   @test("x") @cases({ { { state = "idle" } } })
   local function x(d: D) end   -- E8120: `{ state: string }` is not assignable to `{ state: "idle" | "results" }`
   ```
   The same literal passed to a function taking `D` checks. GroupFinderWho's
   `WhoData.state` is `string` (with the three values in a comment) for this.
2. A filtered run (`wowlua test unit/UI/Guild`) still type-checks every
   test file, so another agent's broken test file stops it (known to the
   coordinator; waited and retried).
3. `mock.stub(t, key, fn)` takes a `table`, so stubbing a method of a
   widget or of an interface-typed object needs a cast (`b.message :: any`).

## Not tested

- What only the real client shows: the game's own art hidden under the
  skins (the tests check alphas and tokens, not pixels), and the dropdown
  menus of the game's frames (Page, Rank, the Discord server and channel):
  opening them needs the game's menu system with real data.
- GroupFinderListing's category cards are the game's template filled by
  the test (the emulator's `C_LFGList` has no categories); the instance
  lock warning icon's art (a saved instance) isn't set up.
- GuildControl's Bank page with eight tabs (the game's maximum) and the
  Discord flow's channel list (only "no channels" is set up).
