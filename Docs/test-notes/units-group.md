# Test notes: units-group

Area: RaidPlanner, RaidFrames, PartyFrames, Readiness and Marks
(`src/Units/`). Written on wowlua 0.9.5 and the fixes after it (see the
findings below; they ship in 0.9.6).

Readiness' test came from the WIP checkpoint and passes as it was. The
others are new and run on the engine's group (`mock.group:add` with a
raid and subgroups, roles, range, online, threat): Blizzard's secure group
headers make the raid frames' buttons, the engine's raid answers the raid
planner's roster and moves its members (Arrange groups), and the marks go
to the group as addon messages.

## Test files

| Source | Test file | Tests |
|---|---|---|
| RaidPlanner | `Units/RaidPlanner.test.wowlua` | setups (new, saved, changed, unique names, duplicated, renamed, loaded, deleted, discarded, save as new, from the raid); as text (export, import, odd characters, wrong text); slots (five a group, changed, a spec's role, removed, a spec or a player dropped); the roster; filling (pickiest first, exact over provisional, two fit one slot, review mode, by role); pinned, swapped, let go; specs from addon messages (heard, asked, shared, combat); specs a day old; coverage (raid-wide, blessings, talents not known, ask, per group: doubled, missing, an open slot's); the window's data (setups, cards, open slots, status, combat, saved ago); Arrange groups (the reasons, moves, a swap into a full group); inspecting (one at a time, the talent groups' points, icons, retry, given up, no tree); your own icons; the menus; the window and its callbacks; settings (presets, Custom, a family's boxes); the migration; stopped |
| RaidFrames | `Units/RaidFrames.test.wowlua` | not in a raid, solo by the setting; a header per group; columns, rows and sizes; sorted by role; the shorter bar past 20; power by role; aggro and your target; range and offline; the settings; the preview and edit mode's; indicators and defensives; auras read again; migrations; a button styled late; stopped |
| PartyFrames | `Units/PartyFrames.test.wowlua` | solo; a party and a raid; the layout's directions and sizes; power by role; aggro (not a tank's); your target; range and offline; auras' side and counts; the preview and edit mode's; indicators and defensives; auras read again; your target in combat; migrations; stopped |
| Readiness | `Units/Readiness.test.wowlua` | (from the checkpoint, passes) |
| Marks | `Units/Marks.test.wowlua` | marks made, changed and removed (the most kept); other maps; the way (waypoint, navigation); posted and shared back; the minimap; the card; Ctrl+click; the game's own pin; a /reload while following |

Coverage (`wowlua test -j 2 --coverage`, each file alone): Readiness every
line; RaidPlanner, RaidFrames, PartyFrames and Marks 99.3-99.5%. Not run:

- RaidFrames and PartyFrames: the plain branches of the range check. The
  engine's `UnitInRange` is secret, as the game's is in Midnight, so only
  the secret branch runs.
- RaidPlanner: an item used by melee (no item in the catalog is), a
  hundredth "New setup" name, and waiting while Blizzard's inspect window
  is open.
- Marks: the card's Post button's click, a card placed below another, and
  the world map loading after Marks.

## Bugs found

- **Fixed: the raid planner never shared or asked for specs in the game.**
  It checked `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`
  first, which Forever's client answers `true` out of combat and alone (the
  full probe), so every message was held back. It checks the chat lockdown
  now (`InChatMessagingLockdown`, as Chat does); a send the game blocks
  just fails. wowlua's PROBES.md item 11 asks for an in-game check.
- **Fixed: the minimap's marks stayed after Marks stopped, and came back
  only at the next change after it started**: the module counts as on
  during OnDisable and as off during OnEnable, so the change each told
  drew the minimap the wrong way. The layer is shown or hidden after.

## VM / wowlua findings (new)

Fixed in wowlua (decisions T241, T242; shipping in 0.9.6):

- **`IsInGroup(LE_PARTY_CATEGORY_INSTANCE)` was true in a group the test
  made**, so Marks posted to `INSTANCE_CHAT` and the engine refused it.
  The engine's groups are home groups now.
- **`UnitFullName("player")` gave no realm**, so Marks didn't know its own
  messages coming back (`Name-Realm`). It gives the realm now.

Not fixed, noted:

- **Moving a raid member** (`SetRaidSubgroup`): the engine fires
  `GROUP_ROSTER_UPDATE` at once; SuuUI's probe saw it 0.4-0.7 s later
  (PROBES.md item 12). The planner's Arrange groups waits for it either
  way.
- **Threat only for the player**: the engine kept the player's threat, so
  aggro is tested on your own frame. Fixed later (decision T247:
  `mob:setThreat(value, who)`).
- **No inspected talent groups**: the engine answers an inspect's spec ID,
  but not its talent groups' points (`C_Traits.GetGroupCurrencyInfo`); the
  planner's test fakes those. Forever's spec IDs are one per class, so
  only the points tell a tree.
