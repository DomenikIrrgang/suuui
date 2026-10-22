# Test notes: units-maps

Area: FlightMap (with FlightMap/Route), WorldMap (with WorldMap/Arrange,
Overlays, Quests, Tips) and Campsite (`src/Units/`).
Written on wowlua 0.9.5 and the fixes after it (see the findings below;
they ship in 0.9.6).

Campsite's test came from the WIP checkpoint and passes as it was. The
flight map's is new (the checkpoint's was a spike): it runs on the
engine's flight master, Orgrimmar's, as the client recorded a Horde
paladin's taxi map (his gossip, the nodes and their slots, the hops, the
Crossroads' flight time), the nodes' places on Kalimdor the client's. The
world map's runs on Blizzard's map with small stand-ins for SuuUI's
generated quest and place data (so each kind of pin is known exactly);
one test reads the real data. The pure helpers (Route, Arrange, Overlays,
Quests, Tips) have tests of their own.

## Test files

| Source | Test file | Tests |
|---|---|---|
| FlightMap | `Units/FlightMap.test.wowlua` | at the master: the world map on the continent, the game's map unseen; the destinations (sorted, stops, estimated times, junk and distant nodes); the pins and their tags; a hovered destination's route and tooltip; a click flies (the map closes, the flight bar, the time learned, the speed moved); a timed flight; Confirm before flying and the bar's Fly; the map closed at the master; the setting off; Land at; the route on the map in flight; a reload in the air; stale flights; the flight bar's setting and edit mode; the settings; no nodes yet; the panel beside a closed quest log; a pin hovered and clicked; quests near a destination; a timed flight with a stop; a flight with no estimate (the sweep, Reduce motion); stops named after a reload; the 24-hour clock; the route by time; Forget and a theme; off and on |
| FlightMap/Route | `Units/FlightMap/Route.test.wowlua` | clock, coins, names, junk nodes, hop and path lengths, a hop's waypoints fitted, dashes, nearest point, share along, stop shares, flight times, the texts, the nearest master |
| WorldMap | `Units/WorldMap.test.wowlua` | the filters' defaults; an earlier layout carried over; the game's quest settings; OpenWith; quests to pick up (givers, colours, the group's bar, a walking giver, repeatable, too high); quests from items; entrances; services by the filters, your class's trainer only, a holiday's vendor; every filter on (repair, trainers, the weapon master's weapons, rares, a walking rare, treasures); flight masters found or not; campfires, marks, convergences; QuestsFor; the pins merged, in tiers, at the opacity; a quest's pin hovered (rings, faded, the walk, Shift); a rare's spots; clicks (zoom, a mark's card); at the flight master; the flight masters noted; a group tag told late or at once; the game's quest pins and their looks; the unexplored areas; what refreshes; the preview; Skyborne's group; off and on; the real data |
| WorldMap/Arrange | `Units/WorldMap/Arrange.test.wowlua` | merging, fixed groups, joining, spreading, drawing order, zoomed all the way in |
| WorldMap/Overlays | `Units/WorldMap/Overlays.test.wowlua` | tiles, rows, explored and missing ones left out |
| WorldMap/Quests | `Units/WorldMap/Quests.test.wowlua` | a quest pin's look, grey level and difficulty, masks, the log and turned in, skills, standing (both APIs), holidays, a quest's name, every rule of what you can pick up |
| WorldMap/Tips | `Units/WorldMap/Tips.test.wowlua` | the placeholders, a pin's quests, one pin's card, a merged pin's list, many, Shift's objectives |
| Campsite | `Units/Campsite.test.wowlua` | (from the checkpoint) |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line but
the modules' wait for Blizzard's world map to load (FlightMap 1619-1622,
WorldMap 1413-1416): the map is loaded before SuuUI in every test, as in
the game.

## Bugs found

- **Fixed: a world map quest tooltip's first objective had a gap under a
  subtitle** (`gap = tip.subtitle and nil or GAP` always gives the gap).
- **Fixed: the Convergences' blessing read as "none" in combat** instead
  of "can't be read" (`InCombatLockdown() and false or nil` is always
  nil). Found here by wowlua's new W2061; Convergences is units-talents'.
- **Fixed: a DamageMeter test helper's `api = false`** (the same pattern;
  no test used it).

## VM / wowlua findings (new)

All fixed in wowlua (decisions T237, T238, S39; shipping in 0.9.6); the
tests run on the fixed engine without workarounds.

- **Text measured too wide under SuuUI's root.** UIParent's scale was 1
  in the engine (0.71 in the game at 1920 by 1080), so a frame that
  ignores its parent's scale at the screen's scale, as SuuUI's root does,
  measured its text at a larger pixel size. UIParent has the screen's
  scale now; `mock.drag` and `mock.sizeBy` take screen units.
- **A new warning, W2061: `a and nil or b` is always `b`.** It found the
  two SuuUI bugs above and one in wowlua's own dev console.
- **Blizzard's quest log errored ("Division by zero")**: the engine sized
  an atlas it had not recorded 0 by 0. It now knows every atlas of the
  client from the client's own tables.
- **`C_QuestLog.GetQuestsOnMap` listed the recording character's quests**
  in every test (no title, not in the log); it lists the log's now.
- **Not findings, for the next areas**: `mock.advanceTime` moves the clock
  without frames, so a module's `after(0)` waits for `mock.advanceFrames`;
  the engine's flight master is a full recording to reuse
  (`defineTaxi` with the scenario's nodes).

## Not tested, and why

- The game's early landing (`TaxiRequestEarlyLanding`) is stubbed: the
  engine has no recording of one (wowlua's PROBES.md lists it).
- The modules' wait for Blizzard's world map to load (see Coverage).
