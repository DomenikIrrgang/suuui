# Port notes: Data (src/Data and its generators in tools/)

## 1. VM suspicions

None. A scratch addon with a copy of `src/Data` built with SuuUI's profiles
and ran in `wowlua test`. The presets and trainer lists for the VM's class
were built, and spot reads of QuestStarts, RaidPlanner and Talents
matched the data.

## 2. Compiler and tooling issues (0.9.1)

### D1. A field with a bracketed key can't be optional

```wowlua
type D = { kind: string, ["not"]?: boolean }   -- E0101: ':' expected near '?:'
type A = { kind: string, ["not"]: boolean? }
local a: A = { kind = "x" }                    -- E2001: `{ kind: "x" }` is not assignable
```

`name: T?` is a required field that may hold nil, and `?:` only parses after
a plain name. So there's no way to write an optional field whose key is a
reserved word. The presets' conditions carry `["not"] = true`. Workaround:
`PresetCondition` has a `[string]: any` indexer in place of the field
(`src/Data/Presets/init.wowlua`). That loses the typo check (E2003) on
conditions.

### D2. A plain list literal isn't accepted for a record with a numeric indexer and optional fields

```wowlua
type By = { [number]: any, talent?: boolean, what?: string }
local x: By = { "MAGE" }                        -- E2001: `"MAGE"[]` is not assignable to `{ talent?: boolean, what?: string, [number]: any }`
local w: By[] = { { "DRUID", 2, talent = true }, { "MAGE" } }   -- E2001 likewise
```

`{ "DRUID", 2, talent = true }` alone is accepted. A literal that is only a
list is typed as an array first, and the array isn't assignable to the
record, although every named field is optional. Workaround: the raid
planner's `by` entries are `{ [string | number]: any }` (`RaidProvider`
in `src/Data/RaidPlanner.wowlua`).

### D3. (convention) `{ … } :: T` doesn't check a data literal; `export local x: T = { … }` does

The conventions suggest `export const x = { … } :: T` as the C1 workaround.
For data that leaves the whole literal unchecked: `::` is an assertion
(spec §1.4.3), so a `"bad"` string in a `number[][]` passes silently.
`export local x: T = { … }` checks every entry against `T` (E2001 at the
entry). Importers also see `T` with its optional fields (C1 doesn't happen
with `export local`; checked with the C1 repro). Every data module uses
`export local x: T = { … }`.

### Check time with the big literals

There was nothing to work around. A scratch project checks in about 0.15 s
empty and about 0.23 s with all of `src/Data` (34k lines) imported (it
varies 0.20-0.35 s between runs). Typed literals and the same literals
without a type took the same time within that noise. The release build
prints a note for QuestStarts: "`dedupe-strings`, `cache-globals` and
`inline` are left out for this file: with them it would exceed a Lua 5.1
limit". That's informational, and the build succeeds.

## 3. Stdlib gaps

None. The only stdlib use is `wowlua:secret` (`secret.known`) for the
player's class in the two index modules, as in `Core/Roles.wowlua`.

## 4. Port decisions

- **Types.** Each data module exports one type for its table (named like
  the table, PascalCase) and the table as
  `export local <mapName>: <Type> = { … }`. For generated files the
  generator writes the types. Tuple-like rows that mix kinds are typed
  `any[]`: QuestStarts `quests[id]` and `entrances`, MapPlaces `npcs[id]`
  and `treasures`, an InstanceLevels row (`{ min, max, { wing, min, max },
  … }`). Their positions are documented in the header comments. Lists of
  one kind are typed exactly (`number[][]` for map pins, `number[]` for
  ids). Strings that work like enums (`kind`, `missing`, `source`, …) are
  `string`, not literal unions: consumers copy presets into the player's
  saved lists and compare them with strings from settings.
- **Only your class's presets and trainer lists are built, as before.** Each
  `Presets/<CLASS>.wowlua` exports `build(): CooldownPreset[]`. Each
  `Trainer/<CLASS>.wowlua` exports `spells(): TrainerSpell[]` and
  `spellIDs(): TrainerSpellIDs`, with the data as the returned literal (the
  data lines themselves are unchanged). `Presets/init.wowlua` and
  `Trainer/init.wowlua` pick the player's class at load (`UnitClass`, as the
  old files did) and call only that class's functions. They export
  `cooldownPresets: CooldownPreset[]?` and
  `trainerSpells: TrainerSpell[]?`, `trainerSpellIDs: TrainerSpellIDs?`
  (nil for a class without a file, as the `ns.*` fields were). Memory stays
  as before: the other classes' tables are never built. The class files'
  exports differ from the symbol map's entries for them (which listed
  `cooldownPresets` / `trainerSpells` per class file). Consumers import
  from the index:
  `import cooldownPresets from "/Data/Presets"`,
  `import trainerSpells, trainerSpellIDs from "/Data/Trainer"`.
  The family's types (`CooldownPreset`, `PresetEntry`, …, `TrainerSpell`,
  `TrainerSpellIDs`) live in the index. The class files reach them with
  `import type`, which makes no load-order cycle. The preset types are
  written by hand from what `tools/gen_presets.lua` emits. A behaviour field
  the generator starts writing makes the class file fail E2003 until it is
  added to `PresetEntry`.
- **RaidPlanner** (hand-written): `local I` became `const I`. The types are
  `RaidClass`, `RaidFamily`, `RaidItem`, `RaidProvider` and `RaidCatalog`.
- **Generators**:
  - All of them now write `.wowlua` paths and the new headers.
  - `gen_presets.lua` now runs from the repository root and writes
    `src/...`. It said "from the addon folder", but it reads `tools/...` and
    wrote `Data/...` relative to the same directory, so after the move to
    `src/` it only worked with a `Data/` beside `tools/`.
  - `gen_presets.lua` also writes `src/Diagnostics/PresetSpellIDs.wowlua`.
    That file isn't this area's, and I didn't run the generator on it.
    Its new head is
    `-- Diagnostics/PresetSpellIDs.wowlua`, the two generated comment lines,
    a blank line, then `export local presetSpellIDs: number[] = {`. The
    numbers are unchanged. Running `lua tools/gen_presets.lua` overwrites
    whatever the Diagnostics port wrote there.
  - `gen_trainer.lua` now runs from the repository root. It reads the
    existing class file by matching its `spells()` literal (from
    `return {` to `\n} end`) and loading that as Lua. The old `loadfile`
    of the module no longer works.
  - `gen_recipe_sources.py` printed its recipe count 2 too high (header
    lines miscounted). It now counts from the header's real length, since
    the header changed anyway.
- **How each file was checked against its generator:**
  - Regenerated byte-identical from local inputs:
    - QuestStarts and MapPlaces, from the QuestieDB cache in `$TMPDIR` (same
      commit and pull request as the file).
    - FlightRoutes and FlightPaths, from the cached wago CSVs.
    - Presets, AuraCatalog and Talents, from `tools/data` and
      `tools/presets`. This ran in a scratch copy so that
      `src/Diagnostics` stayed untouched.
    - Defensives, from `tools/data`.
    - In every case the old generator first reproduced the old `.lua`
      exactly.
  - Inputs not available locally:
    - MapOverlays and InstanceLevels: I rebuilt their CSVs from the data.
      The old generator reproduces the old file from them, and the new one
      writes the converted file byte for byte.
    - Trainer: I built a SavedVariables file from the data. Old and new
      generators reproduce old and new files, including a run with a
      level-0 spell that goes through the merge with the file.
    - RecipeSources (needs `ItemSparse.csv`): the old and new generators
      on the same inputs differ by exactly the header change.
    - CollectionSources (needs the QuestieDB extract and DB2 CSVs): only
      the header was converted, mirroring the generator's change.
