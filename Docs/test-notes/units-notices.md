# Test notes: units-notices

Area: Notifications, NpcDialogue, ObjectiveTracker, Alerts, DeathRecap,
Support (`src/Units/`). Written on wowlua 0.9.5 and the fixes after it
(they ship in 0.9.6).

## State

| Source | Test file | Tests | Lines |
|---|---|---|---|
| ObjectiveTracker | `Units/ObjectiveTracker.test.wowlua` (replaces the checkpoint's probe) | 15 | 100% |
| NpcDialogue | `Units/NpcDialogue.test.wowlua` (new) | 13 | 99.7% |
| Notifications | `Units/Notifications.test.wowlua` (new) | 25 | 98.2% |
| Alerts | `Units/Alerts.test.wowlua` (checkpoint, passes as it was) | 23 | 100% |
| DeathRecap | `Units/DeathRecap.test.wowlua` (checkpoint, passes as it was) | 25 | 100% |
| Support | `Units/Support.test.wowlua` (checkpoint, passes as it was) | 16 | 100% |

Notifications' lines not run: a bank tab's price when the popup shows none (it always
shows one in the engine), the Battle.net toast's own hide (the frame isn't
there when the hook is made), a card that scrolled out of the stack while
its popup shows, and the button art's hover while hidden. `smoke` and
`compat` pass.

## Bugs found

- **Fixed: in a boss fight the tracker's quest items never hid.**
  Blizzard's state driver gives the state "1" as the number 1
  (SecureStateDriver.lua: `tonumber(newValue) or newValue`); the snippet
  compared it with the string "1".
- **Fixed: notes stayed shown through a fight, and a note's secure macro
  button was put back over it.** `PLAYER_REGEN_DISABLED` comes before the
  lockdown, so the redraw at that moment still drew as out of combat (and
  the secure button then couldn't be hidden until the fight ended). The
  module draws as in combat from the event on.

## VM / wowlua findings (new)

Fixed in wowlua (decision T243 and a declaration):

- **A `SecureHandlerClickTemplate` button of an addon's never ran its
  `_onclick` on a click**: Blizzard's inline template handler carried the
  addon's taint, and Blizzard's code refused the frame ("Invalid 'self'
  frame handle"). This is what the tracker's head toggle uses.
- **`mock` had no way to give worn gear durability in a strict test**:
  `HeldItem` lacked `durability` and `maxDurability`, which the engine
  reads.

Noted (wowlua's PROBES.md item 13): the game watches and focuses a quest
as you accept it (recorded), so SuuUI's "Track accepted quests" off may do
nothing in game unless the `autoQuestWatch` CVar is off too. A question for
the design: should the setting follow the CVar?
