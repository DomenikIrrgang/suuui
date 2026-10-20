# Test notes: ui-world

Area: the world and profession components in `src/UI/`: MapPin,
ObjectiveTracker, Professions, RaidPlanner, Inventory and Legacy. One test
file per source file in `tests/unit/UI/<File>.test.wowlua`, with the shared
helper `tests/unit/UI/WorldHelpers.wowlua` (the colour token and alpha Draw
keeps for a region, a border's token). Written on wowlua 0.9.4 (MapPin's
test and the helper came from the WIP checkpoint 68d8ab6 and were verified
here unchanged).

The components are driven as their modules drive them: built in a host,
fed their data (`SetQuests`, `SetOverview`, `SetCrafting`, `SetRecipe`,
`SetData`, `SetCategories`, `SetTrack`, `LayoutSlots`), and worked through
the user's input (`mock.click`, `mock.hover`, `mock.typeText`,
`mock.pressKey`, `mock.wheel`, `mock.setModifiers` for Shift-clicks,
`mock.script` for drags and presses). Callbacks are spies checked for their
arguments; what is drawn is checked with the widget matchers and the colour
token each region keeps; tooltips through `/UI/Tooltip` are stubbed,
GameTooltip's lines read with `toHaveLines`.

Drags in the raid planner: `mock.script(source, "OnDragStart")`, then
`mock.hover(target)` (so `IsMouseOver` holds), a frame for the ghost's
`OnUpdate` to light the target, then `OnDragStop`.

## Test files

| Source | Test file | Tests |
|---|---|---|
| MapPin | `MapPin.test.wowlua` | (from the checkpoint) the disc and its sizes, glyph and character, spin, rings, glow, outline, edges and split edges, the bar, a merged pin's count, a theme change |
| ObjectiveTracker | `ObjectiveTracker.test.wowlua` | the head (title, meta and its rule, toggle and its hover, the owner's own toggle), collapsed; a quest (title by difficulty or its own colour, objectives open and done, counts, complete, turn-in text, failed, an icon and count, the preview's item); zone headings and spacing; clicks and hover; the Recipes section (open, folded, its toggle, the quests folded); the window within maxHeight (gutter, thumb, hidden rows), scrolling (clamped, rounded, locked, the wheel), QuestTop, SetMaxHeight; frozen layouts |
| Professions | `Professions.test.wowlua` | the rail (icons, glyphs, the chosen tab, tooltips, fewer tabs); the overview (counts, cards, the empty slot, secondary rows wrapping, the design's width before layout), the skill bar's fill, untrained cards, spells (colours, hover, click, drag), card hover, open, drag and Unlearn; crafting's head; the list (heads, counts, difficulty colours, learned, the eye, selection, folding, flat lists, hover, select, Shift-click links); the recipe (product, quality, makes, reagents have/need, tools, source item and lines, cooldown, scroll back to the top); the foot (Track, Create, Create all, the quantity, why not); Link; search, filters, sort; a theme change |
| RaidPlanner | `RaidPlanner.test.wowlua` | drawing only while shown; the status; setups (loaded, changed, hover, click, menu) and the left's controls; the palette; a group (Add slot, buff chips by tone, wrapping, rows of four); slot cards by state (filled, provisional, open, conflict, away), their hover, tooltip and click; Add slot; raid-wide, open slots, players without a slot; the footer's buttons and reasons; renaming in place; dragging specs, roles, classes and players (the ghost, the target's light, drops on nothing); hidden mid-drag; the slot editor (every field, beside its card, changes, Remove, Done, the label kept while typed); the moves panel; a theme change |
| Inventory | `Inventory.test.wowlua` | the item slot (empty, by quality, dimmed, locked, hover, a template's button with its parts hidden); moneyText cases and colours; money; the panel (defaults and options, the sort button, LayoutSlots and sections, the foot's note, money and action, close); characters (picker, banner, found items, ten at most); SetColumns; a theme change |
| Legacy | `Legacy.test.wowlua` | the points (pending in arcane, character only); the challenge cards (rows, bars, All n, hover, no width yet); a category's list (panels two to a row or full width, the unnamed group, rows done / by count / by steps, opening steps and an achievement step in turn, a refresh keeping the scroll, the way back's press); the reward track (stops, reached, collected, the next reward, before it has a width, redrawn when sized); a theme change |

Coverage (`wowlua test -j 2 --coverage`, each file measured with its own
test file): every line of all six runs. One line is marked
`-- wowlua: coverage ignore`: Professions' skill bar without a caption
(every bar has one).

## Refactors

None.

## Bugs found

- **Fixed: the raid planner broke as soon as anyone had no slot.**
  `DrawRight` wrote the person's icon value into the row's `icon` field,
  which holds the row's icon widget, then drew that value as a widget
  ("attempt to index local 'f' (a nil value)"); the plain-Lua original on
  `main` has the same line, so the window errored in game whenever the
  "Without a slot" list wasn't empty. The value now goes into `personIcon`
  (the drag's ghost reads it there).

## VM / wowlua findings (new)

- **`IsModifiedClick("CHATLINK")` was always false** (wowlua 0.9.4):
  Blizzard's default for CHATLINK is `SHIFT-BUTTON1`, and the engine took
  the `BUTTON1` part for a key never held. Fixed in wowlua (the part is the
  button of the click running); Professions' Shift-click tests need it.
- **`toHaveBeenCalledWith` couldn't match a call that left an optional
  argument out** (E2007 in the test, and a nil passed would fail the count
  at run time) and **a filtered `wowlua test` loaded every test file**
  (ten minutes for one file on this laptop): both fixed in wowlua 0.9.4.

## Not tested, and why

Nothing in these six files.
