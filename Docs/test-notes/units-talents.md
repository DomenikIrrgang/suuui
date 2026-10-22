# Test notes: units-talents

Area: Talents, Spellbook, Legacy, Convergences and Welcome (`src/Units/`).
Written on wowlua 0.9.5 and the fixes after it (see the findings below;
they ship in 0.9.6).

Talents' and Convergences' tests came from the WIP checkpoint and were
finished here. Talents runs on a stand-in for the game's talent API
(`TraitWorld.wowlua`: three small trees whose every answer the test sets):
the module also views other classes' loadouts, refunds planned ranks and
reads both spec groups, which the engine has no recording of. Blizzard's
own spells window with SuuUI's page in its Talents tab runs on the engine's
recorded warrior instead (`TalentsTab.test.wowlua`): Blizzard's talent
frame underneath reads the same trees. Spellbook, Legacy and Welcome are
new: the spellbook and the Legacy are the engine's (the default warrior's
spellbook, its Legacy config, trees, achievements and renown rewards).

## Test files

| Source | Test file | Tests |
|---|---|---|
| Talents | `Units/Talents.test.wowlua` | (from the checkpoint, finished) the pure pieces, pages, Fill and Render, builds (add, delete, active, picker, plan, order), using a build (fit, stage, apply, conflicts and resets), sharing (SuuUI's text, the game's string, choices), the window and its page, events |
| Talents | `Units/TalentsTab.test.wowlua` | Blizzard's spells window: SuuUI's page with its Talents tab, the tab kept off screen |
| Spellbook | `Units/Spellbook.test.wowlua` | the schools; a school's learned spells; what's still to train; the training line; the Spellbook tab and the window's size; schools, switches, pages; a learned spell's tooltip, click and drag; one to train; combat; cooldowns; the count and cost to train; the level-up card, a level gained, `/suu levelup`, the preview; the game's level-up toast; a flyout's spells; SuuUI's own tooltip; Blizzard's spells off screen; nothing left; redraws |
| Legacy | `Units/Legacy.test.wowlua` | the points; the trees; the window and Blizzard's pages off screen; the challenges' page (categories, order, tooltips, steps, counts); the reward track (stops, next, tooltips, an item still loading); the reward page going to the tree; a talent's tooltip and combat; redraws; no pages; planning a point (plan, undo, apply) |
| Convergences | `Units/Convergences.test.wowlua` | (from the checkpoint, finished) |
| Welcome | `Units/Welcome.test.wowlua` | the first login; the steps; the choices and the summary; Start playing; a preset that can't be made; combat; `/suu welcome`, the service, a theme, off |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
Talents, Spellbook, Convergences and Welcome; Legacy all but three lines of
challenge progress the recorded achievements don't reach.

## Bugs found

- **Fixed: the spells window's Talents page errored** ("attempt to index
  local 'nextTalent'"): off SuuUI's own window `nextTalent` was `false`, and
  `nextTalent ~= nil` let it through.
- **Fixed: a new or imported build wasn't shown to plan when the Talents
  window was closed**: opening the window switched the view back to the
  active build after the new one was set.
- **Fixed: Start playing stayed enabled when a fight began** on the
  welcome's last step: combat's event comes before the lockdown.
- **Fixed: the Convergences' blessing read as "none" in combat** instead of
  "can't be read" (found with wowlua's W2061; see units-maps).

## VM / wowlua findings (new)

Fixed in wowlua (decisions T239, T240; shipping in 0.9.6):

- **A test's payload table tainted Blizzard's handlers**: `mock.fireUnitEvent("UNIT_AURA", "player", { isFullUpdate = true })`
  left the test's taint in the table's fields, and Blizzard's buff frame
  refused the secret auras in combat. The engine passes plain tables as
  the client's, untainted.
- **Talents never opened in a test**: `CanPlayerUseTalentUI()` was the
  profile's level-1 answer at any level; it follows the level now (5).

Not fixed, noted (wowlua's PROBES.md lists what needs recording):

- **A frame whose top is below its bottom** had a negative height in the
  engine; Blizzard's Legacy challenge list then asked for rows 8 to 6 and
  errored. Probed later: the game gives 0 (wowlua T266); the test no
  longer avoids reopening the window on the challenges.
- **`C_Traits.RefundRank`, other classes' view loadouts and both spec
  groups' configs** have no recording: Talents keeps its stand-in.
- **`GetCursorInfo` is declared without its results** (in every flavor's
  declarations): a strict test reads it through `any`.

## Not tested, and why

- Legacy's progress of a single-step challenge already started, and a
  finished challenge with several steps: the recorded warrior has none.
