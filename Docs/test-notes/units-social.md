# Test notes: units-social

Area: GroupFinder, Guild, Social, GameMenu and MicroMenu (`src/Units/`).
Written on wowlua 0.9.6 and a fix after it (decision T244, see below).

GroupFinder's tests came from the WIP checkpoint and pass as they were.
The others are new and run over the game's own windows in the engine:
Forever's social window (`O`, its tabs clicked), Blizzard's Communities
window (`J`) on a guild the test makes (`mock.joinGuild` with ranks and
placeholder members), the game menu on Esc. The engine has no friends,
Battle.net friends, ignores, recent allies, friend requests or saved
lockouts: those tests stub the game's calls as the client answers them.

## Test files

| Source | Test file | Tests | Lines |
|---|---|---|---|
| GroupFinder | `Units/GroupFinder.test.wowlua`, `Units/GroupFinder/Logic.test.wowlua` (checkpoint) | 78 | 100% |
| GameMenu | `Units/GameMenu.test.wowlua` (new) | 11 | 99.6% |
| MicroMenu | `Units/MicroMenu.test.wowlua` (new) | 12 | 100% |
| Social | `Units/Social.test.wowlua` (new) | 12 | 99.2% |
| Guild | `Units/Guild.test.wowlua` (new) | 12 | 93.8% |

Not run: the game menu's Edit Mode "Not available right now"; Social's
class from `GetClassInfo` when `C_CreatureInfo` has none, and Ignore's
confirmation; Guild's note editing through Blizzard's own member rows
(it needs members with GUIDs in Blizzard's hidden list) and the roster
row's double click.

## Bugs found

- **Fixed: Raid Info never showed a lockout's difficulty, size or
  progress.** Social's call helper passed on at most 8 values;
  `GetSavedInstanceInfo` gives 12, the details being the last ones.
- **Fixed: the merchant's Sell junk always said 0c.** The same helper in
  Merchant cut off `GetItemInfo`'s sell price (its 11th value). The
  other modules' helpers were checked: none reads past its cap.
- **Fixed: the game menu let you use Reload UI, Log Out, Exit Game and
  Edit Mode in a fight that had just begun.** `PLAYER_REGEN_DISABLED`
  comes before the lockdown (as in Notifications); the menu treats you as
  fighting from the event on.
- **Fixed: Guild's Remove never removed anyone.** Its secure cover takes
  the press and the release, and both ran its two-step: one click armed
  it and disarmed it again. It acts on the release now, as the row cover
  in the same file already did.
- **Fixed: Guild's own dialog for the message of the day and the guild
  information could never save.** It used `SetMOTD` and `SetInfoText`,
  which the game forbids to addons (blocked, "Interface action failed").
  When Blizzard's own box can't be reached, it now says so instead.

## VM / wowlua findings (new)

Fixed in wowlua (decision T244, after 0.9.6):

- **A hidden edit box kept the keyboard.** Hiding a focused edit box (or
  its parent) didn't take its focus away, so later keys in a test went
  into it: Guild's test typed into the closed invite dialog, and `J` never
  reached the game. As in the client, the focus is dropped with
  `OnEditFocusLost`.

Not fixed, noted:

- **The first Esc in a test skips SuuUI's welcome**, as in the game at a
  first login: a test of the game menu presses Esc once more (or closes
  the welcome first).
- **A call helper's cap was invisible to the checker.** `call(...)`
  returns `...any`, so reading its 11th result through a helper that
  returns 8 type-checked. wowlua's W2062 (decision S40, after 0.9.6)
  counts a local function's returns and warns on a read past them; on
  SuuUI before the fix it caught both bugs.
