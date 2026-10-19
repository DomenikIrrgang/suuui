# Port notes: diag-world

Files: `src/Diagnostics/` AhDataProbe, AhPostProbe, AhScanProbe, BagProbe,
BagSortProbe, BankSlotsProbe, CampProbe, CharacterProbe, CollectionsArtProbe,
CollectionsOwnProbe, CollectionsTilesProbe, DurabilityProbe, GiverProbe,
LootProbe, MapProbe, MountFeetProbe, MountFrameProbe, ProfIconProbe,
ProfessionProbe, QuestGroupProbe, QuestProbe, TooltipProbe.

## 1. VM suspicions

None. The VM was not run for these files.

## 2. Compiler/tooling issues (0.9.1)

### W8102 ignores a check that the load-on-demand function exists

`hook("Name", fn)` on a function from a load-on-demand addon warns even when
the code checks first that the function exists, so the hook runs only when
the addon has already loaded:

```wowlua
import hook from "wowlua:hooks"
export function arm()
    if _G.CollectionsJournal_UpdateSelectedTab then
        hook("CollectionsJournal_UpdateSelectedTab", function() end)
    end
end
-- warning[W8102]: `CollectionsJournal_UpdateSelectedTab` exists only once the
-- load-on-demand addon `Blizzard_Collections` has loaded; hook it with
-- `hook(_G, "CollectionsJournal_UpdateSelectedTab", fn, { addon = "Blizzard_Collections" })`
```

Repro project: `/Users/domenikirrgang/.claude/jobs/19c8952e/tmp/scratch-diag-world/X`.
Workaround in CollectionsArtProbe: the form the warning suggests. Inside the
check, `onAddonLoaded` sees that the addon has loaded and hooks right away,
the same as before.

### `pairs(Enum.X or {})`

Same as "`typeof <namespace> | {}` cannot be asserted to a map" in
`diag-core.md`. `pairs(Enum.BagSlotFlags)` gives E2001 even without the
`or {}`. Workaround: `pairs((Enum.BagIndex :: any) or {})`. Used in BagProbe,
BagSortProbe and TooltipProbe.

## 3. Stdlib gaps

None that made SuuUI keep its own code. Where these files now use the stdlib:

- `wowlua:secret` `isSecret` instead of `issecretvalue or function() return false end`
  (it does the same).
- `wowlua:timer` `after`/`every` instead of `C_Timer.After`/`NewTicker`
  (everywhere except the bag probes, which had no timers). Errors raised
  inside a timer are now reported by the stdlib.
- `wowlua:hooks` `hook`/`hookScript` for Blizzard functions and frames in
  CharacterProbe (the Character window's functions, `CharacterFrame`
  OnShow/OnHide), CollectionsArtProbe and TooltipProbe. These now also catch
  errors raised inside the hook.

## 4. Port decisions

- **Exports.** Each file exports the functions in the symbol map: `command`
  everywhere, plus `sample`, `record`, `check`, `post`/`cancel`, `place`, and
  MapProbe's `snapshot`/`areas`/`log`/`zones`. The file tables
  (`ahDataProbe`, `bagProbe`, …) are tables of functions, so they are not
  exported. `command` takes `rest`/`arg` where the old `Command` did, and
  nothing where it took nothing. This matches the calls in
  `Probe.wowlua`'s `TOPIC_COMMANDS`.
- **SuuUIProbe / SuuUIDB** became `DB.probe` / `DB.db` (BankSlotsProbe reads
  `DB.db.blocked`). The `SuuUIProbe = SuuUIProbe or {}` lines are gone. The
  keys and the shape of what each probe records are unchanged. No file
  touches `DB` while it loads. BagSortProbe makes its event and driver frames
  at load time, as before, but they reach the DB only from a command.
- **The bag probes are kept exactly.** BagProbe keeps `hooksecurefunc` on the
  bag functions and `HookScript` on its template-made item button.
  BagSortProbe keeps its event frame and coroutine driver. Only types,
  imports and `DB.probe` changed. The `HookScript("PostClick")` on SuuUI's
  own secure buttons (BankSlotsProbe's purchase clicker, QuestProbe's item
  button) also stays as it was.
- **Event frames.** Probes that register events (often with
  `pcall(f.RegisterEvent, …)` for events Forever may not have, or
  `RegisterUnitEvent`, and unregistering on their own timing) keep their own
  frames. They are not moved to `/Core/Events`, so their event handling stays
  the same.
- **State that lived on the file tables** became module locals:
  - AhPost: `AP.loc/panel/listening`
  - AhScan: `AP.waiting/frame`
  - BankSlots: `BP.panel`
  - CollectionsArt: `CP.hooked/untilTime`
  - CollectionsOwn: `CP.mountIDs/usableMount/toy/source/panel/listening`
  - CollectionsTiles: `CP.panel`
  - Giver: `GP.frame/on`
  - Map: `MP.tri1/tri2` → `triangles[key]`
  - MountFeet: `FP.panel`
  - MountFrame: `MP.panel/placePanel`
  - ProfIcon: `PIP.frame`

  Panels that hold fields of their own have a small interface extending
  `Panel` (`SlotsPanel`, `OwnPanel`, `TilesPanel`, `FeetPanel`, `PlacePanel`,
  `FramePanel`).
- **`UI.CloseButton and UI.CloseButton(…)`** checks are gone in AhPost,
  CollectionsOwn and CollectionsTiles. `closeButton` is imported, so it
  always exists. DurabilityProbe likewise calls `apiDocs.dump`/`apiDocs.flags`
  without the `ns.ApiDocs and ns.ApiDocs.Dump` check.
- **Public API kept** where the probe used it: GiverProbe and MapProbe still
  go through `SuuUI.QuestStarts()` and `SuuUI.GetModule(…)`, the module
  typed `any` for its own methods (`QuestsFor`, `layer`, `Get`).
  QuestGroupProbe imports `questStarts` from `/Data/QuestStarts` in place of
  `ns.QuestStarts or {}`.
- **Casts for gaps in the typings** (the calls are unchanged):
  - `(C_AuctionHouse :: any).PostCommodity/PostItem/ConfirmPostItem`: the
    typings want the prices as strings, and the probe passes numbers as
    before.
  - `(C_TradeSkillUI :: any).GetRecipeNumItemsProduced/GetRecipeTools`: not
    in the typings.
  - `_G.GetLootMethod` and `_G.GetQuestGreenRange`: not declared.
  - CampProbe's aura data as `any`: it is typed `Secret<AuraData>`, and the
    probe checks secrecy itself, field by field, as before.
  - GiverProbe's GUID and NPC name cast to `string` after its own
    `plain(...)` check. That check doesn't narrow.
  - BagSortProbe's slot contents cast to `Content` where the step has
    just picked a full slot.
  - Locals that are nil only before the probe has sampled cast with `::`
    instead of a new nil check, so nothing new runs: LootProbe's and
    TooltipProbe's `store` in the log handlers, MountFeetProbe's `current`
    when the model loads.
- **DurabilityProbe** `moneyWentDown`: the `tonumber(...)` calls moved
  into two locals so the comparison type-checks. The result is the same
  (`"nil"` or `"true"`/`"false"`).
- **Renames for shadowing and unused warnings** (local names only):
  - TooltipProbe's local `sample(tooltip, data)` → `sampleTooltip`
  - BagProbe's local `sample` → `snap`
  - MountFrameProbe's inner `show(step)` → `showMount`
  - MapProbe's `areas` local → `explored`
  - BagSortProbe's `pairsFor` `out` → `found`
  - CollectionsTilesProbe's `sources` and `tiles` locals → `found` and
    `previews`
  - GiverProbe's inner loop `q` → `e`
  - `text` from `/UI/Text` imported as `uiText` where a parameter is named
    `text`
  - unused return slots prefixed with `_`
- **Bug noticed, left as it was:** MountFeetProbe and MountFrameProbe's `place`
  test make their buttons only on the first run. The buttons keep that run's closures (its mount list, nudge,
  `place`/`showMount`, the saved table). Running the command a second time
  in a session starts a new list, but Up, Down, Next, Skip, Previous and
  Wider still act on the first run's state.
