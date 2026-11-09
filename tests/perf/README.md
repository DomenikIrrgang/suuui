# Performance scenarios

Gameplay played in wowlua's emulated client, measured frame by frame, so a
change can be compared with what SuuUI cost before it. They are not part of
`wowlua test`: every test here is behind the `perf` feature
(`@if(features.perf)`), so a normal run skips these files without loading
them.

| Scenario | What it plays |
|----------|---------------|
| `idle` | Ten seconds with nothing happening, after the login's warm-ups |
| `solo` | A level 59 warrior kills three mobs: auto attack, a rotation, kills, loot, the level up |
| `pull` | Twelve mobs with nameplates, threat, target switches, debuffs, deaths; again; then thirty at once |
| `party` | A dungeon boss with four others: heals, incoming heals, shields, dispels, boss casts |
| `raid` | Forty players: aura churn, damage and heals, a wipe, the mass resurrect |
| `pet` | A hunter's pet fighting: the pet frame and bar, happiness, its experience |
| `travel` | Running through zones with ten quests in the log, mounting |
| `loot` | The bags open, a burst of kills and loot (bag updates), the bags closed |
| `chat` | Trade, general, guild, say, whispers and system lines, twelve a second |
| `windows` | The world map, character, spellbook, talents, collections and settings, opened twice |
| `memory` | The size of SuuUI's data tables (QuestStarts, CollectionSources, …) |

## Run

```console
$ python3 -I tools/perf.py run            # every scenario (a few minutes)
$ python3 -I tools/perf.py run pull raid  # some of them
```

It runs `wowlua test --features perf -u --profile-out dist/perf/profiles
tests/perf/…` (two files at a time; `PERF_JOBS=1` for one), then writes
`dist/perf/results.json` and prints, per scenario and phase:

- **instr/f, p95, worst**: Lua instructions SuuUI ran per frame (its own
  code, and the game's functions it called): the mean, the 95th percentile
  and the worst frame, with the events behind the worst frame. The worst
  frame is what a stutter is made of.
- **KB/f, KB p95, KB max**: what SuuUI allocated per frame, the garbage the
  game's collector has to clear later.
- **all/f**: every addon's and Blizzard's UI's instructions per frame.
- the memory each scenario recorded (the whole emulated client's, after a
  full collection) and the size of the data tables.

Instruction and byte counts are exact: the same code gives the same numbers
on every machine and every run. Host times (`suu_ms_*` in the JSON) depend on
the machine and are never compared. The emulator is not the game: the
numbers say where SuuUI's work and garbage go and whether a change made them
smaller, not how many milliseconds a frame takes in WoW. For that, record in
the game with `wowlua dev`'s dev window and `wowlua prof report`.

## Compare

`run` compares with `tests/perf/baseline.json` when it is there: each metric,
the baseline's value, the new one and the change (`better` or `WORSE` past
2%). By hand:

```console
$ python3 -I tools/perf.py compare                     # the last run with the baseline
$ python3 -I tools/perf.py compare old.json new.json   # any two results
```

A run of some scenarios compares only those. The baseline names the wowlua
version it was made with: another version's emulator or Blizzard UI may
change the numbers by itself.

## Where the time goes

```console
$ python3 -I tools/perf.py top pull "big pull: thirty"
$ python3 -I tools/perf.py top windows --frame 97
$ python3 -I tools/perf.py top pull "second wave" --event "event PLAYER_TARGET_CHANGED"
```

lists, per frame of a phase (or for one frame, or one event), the events and
scripts with SuuUI's entry points, SuuUI's functions (with what they call,
and on their own) and the game's functions SuuUI called, by instructions and
by garbage. The profiles in `dist/perf/profiles` also open on
[speedscope.app](https://www.speedscope.app).

## Update the baseline

After a change that made SuuUI faster (and was accepted), run every scenario
and make that run the baseline, in the same commit as the change:

```console
$ python3 -I tools/perf.py run
$ python3 -I tools/perf.py baseline
```

Also after a wowlua update, on its own commit, so a later comparison shows
SuuUI's changes and not the emulator's.

## Write a scenario

A file `tests/perf/<name>.test.wowlua`, every test behind
`@if(features.perf)`, with `config({ profile = "perf" })` (a level 60
warrior with bars, bags and gear: `tests/profiles/perf.json`). Its tests run
in order in one client. A test whose name starts with `setup` prepares and
isn't measured; every other one is a phase. Drive a phase with
`perf.run(frames, function(n) … end)` (`util.wowlua`): the function runs
inside each frame, so what it fires lands in that frame. Keep a file's frames
under 600 (the profiler keeps the newest 600), use `perf.random(seed)` for
choices, and `perf.record(name, { kb = … })` for a memory figure.
