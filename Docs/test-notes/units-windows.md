# Test notes: units-windows

Area: Windows, Nameplates, Tooltips, Minimap and Addons (`src/Units/`).
Written on wowlua 0.9.6 and fixes after it on `m9-coverage-stale-handle`
(decisions T245 and T246, see below).

Addons' tests came from the WIP checkpoint and pass as they were. The
others are new and run over the game's own frames in the engine: the
nameplates the engine shows for a unit (`unit:showNameplate()`), the
game's tooltips, the minimap, and Blizzard's windows loaded as their
addons load (spells, Legacy, professions, friends, Forever's social
window, guild, group finder, world map with its quest log, collections,
trainer).

## Test files

| Source | Test file | Tests | Lines |
|---|---|---|---|
| Addons | `Units/Addons.test.wowlua` (checkpoint) | 48 | 100% |
| Tooltips | `Units/Tooltips.test.wowlua` (new) | 11 | 99.4% |
| Minimap | `Units/Minimap.test.wowlua` (new) | 10 | 100% |
| Nameplates | `Units/Nameplates.test.wowlua` (new) | 17 | 99.6% |
| Windows | `Units/Windows.test.wowlua` (new) | 12 | 98.1% |

Not run: Nameplates' plate made when the pool is empty (20 are made
ahead) and its health colour without `C_CurveUtil`; Windows' trainer
categories (Forever's trainers have none: the recorded category is ""),
the game's fullscreen map chosen before SuuUI (`miniWorldMap` off at
login), and a rank that has no room beside the price.

## Bugs found

- **Fixed: the caster line on aura tooltips was never added.** Tooltips
  hooked the aura setters on the tooltip metatable, but the game copies
  them onto each tooltip (`GameTooltipDataMixin`), so the hook never ran.
  They're hooked on each tooltip now.

Nameplates, Windows and Minimap: none.

## VM / wowlua findings (new)

Fixed in wowlua (after 0.9.6):

- **T245: addons' tooltips were empty in a fight.** The game's tooltip
  setters check `C_RestrictedActions.CheckAllowProtectedFunctions(self)`;
  the engine refused every addon in combat whatever the object. It now
  refuses only on a protected object, as the recorded answers show.
- **T246: a test couldn't be listed in the group finder.** An addon's
  `CreateListing` is blocked, and stubbing `C_LFGList.HasActiveEntryInfo`
  ran Blizzard's listing panel on a listing that wasn't there (errors, a
  blocked search). `mock.postLFGListing(createData)` lists the player as
  the game's panel does, `mock.delistLFG()` takes it down. Windows' test
  uses it for the group finder's "My listing" tab.

Not fixed, noted:

- **A stubbed global runs Blizzard's code tainted.** Stubbing
  `UnitThreatSituation` or `GetRaidTargetIndex` made Blizzard's nameplate
  and unit frames compare secret health while tainted (errors), and the
  taint stayed in their fields for later tests. As in the client. The
  Nameplates test gives the plate its own API table (`f.api`, which the
  plates already read for the preview) instead.
- **The engine can't turn a unit hostile** (a duel): Nameplates' recheck
  stubs `UnitCanAttack` for it. A `unit:setReaction` (with
  `UNIT_FACTION`) would need a probe for the client's order of events.
- **Forever's spells window has no tab row**
  (`IsTabSystemAvailable` is false on Camelot), so SuuUI's text tabs on
  it never show; its title still follows the open page.
- **`mock.hover` doesn't move the cursor**: code that reads the cursor
  over a frame (the world map's coordinates) needs
  `mock.setCursorPosition` too.
- **The engine's threat was the player's alone** (`unit:setThreat` gave
  status 3): a tank's "Losing" (status 2) comes from the plate's API
  table here. Fixed in units-hud (decision T247: `mob:setThreat(value,
  who)`), which Threat's test uses.
