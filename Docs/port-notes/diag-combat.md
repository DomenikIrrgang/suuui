# Port notes: diag-combat

Files (`git mv` from `.lua`, all in `src/Diagnostics/`): TalentBuildProbe,
TalentProbe, TreeProbe, SpellbookProbe, WeaponEnchantProbe, TotemProbe,
PowerProbe, PartyAuraProbe, PlateProbe, MeterProbe, TimelineProbe,
TrackProbe, SkysightProbe, LegacyProbe, TaxiProbe (`.wowlua`). Strict mode,
no errors. Four warnings remain, and the Lua code already had all of them
(see section 4).

## 1. VM suspicions

None. I didn't run the VM for these files.

## 2. Compiler/tooling issues

I found nothing new. Two known issues came up:

- **An imported `isSecret` doesn't narrow** (ui-units U1). These spots call
  `pcall` with `C_UnitAuras.GetAuraDataByIndex` and index the result after
  `if not ok or isSecret(a)`: TrackProbe `readAuras` and `aurasReadable`,
  WeaponEnchantProbe `scanAuras` and PartyAuraProbe. For the checker the
  result was still `Secret<AuraData>`. A copy of TrackProbe in a scratch
  project without import cycles narrows fine, which matches U1. The
  workaround here is to cast the pcall'd function (`pcall(X :: any, …)`). The
  same cast is on `GetAuraDataByAuraInstanceID`, `UnitCastingInfo`,
  `GetTotemDuration`, `C_Item.GetWeaponEnchantInfo`,
  `C_TooltipInfo.GetInventoryItem` and `C_DamageMeter.GetAvailableCombatSessions`.
  The probes read those results knowing they may be secret.
- **`pairs(Enum.X or {})`** gives E2001 (diag-core). I used `pairs((Enum.X :: any) or {})`.

## 3. Stdlib gaps

None that made me keep SuuUI's code. These files now use:

- `wowlua:secret` `isSecret` for `issecretvalue or function() return false end`
  in every file.
- `wowlua:timer` `after` for every `C_Timer.After`, and `every` for every
  `C_Timer.NewTicker`. The tickers are TrackProbe's panel tick,
  WeaponEnchantProbe's secure watch (it now cancels through the ticker
  passed in, not an outer local) and TaxiProbe's flight samples. An error
  inside a callback is now reported. Before, it went straight to the game's
  error handler.
- `wowlua:hooks` `hook`:
  - SpellbookProbe uses it for `hooksecurefunc(book, "SetSpells", …)`.
  - TalentBuildProbe uses it for `hooksecurefunc("StaticPopup_Show", …)`.
  - SpellbookProbe's `HookScript` calls on SuuUI's own spellbook cells stay
    as they were.

## 4. Port decisions

- **Exports.** Only the functions from the symbol map are exported
  (`command`, `sample`, `plan`, `capture`, `buttons`, `choose`, `export`,
  `save`, `switch`, `trainer`, `pickup`, `cast`). The probe tables
  themselves (`talentBuildProbe`, …) aren't, following the conventions for
  tables of functions. Probe.wowlua only calls `command`. Every `command`
  takes `(arg: string?)` or `(_rest: string?)`, because Probe passes the
  rest of the line to all of them.
- **State that lived on the probe table** is now module-local and not
  exported. Nothing outside the file read it:
  - TotemProbe `TP.panel` → `panel`.
  - WeaponEnchantProbe `WP.button` / `WP.secureFrame` → `cancelButton` /
    `secureFrame`.
  - SpellbookProbe `SP.castNote` / `SP.castHooked` → `castNote` (a no-op
    until the recorder is armed; nothing calls it before then) /
    `castHooked`.
- **SavedVariables.**
  - `SuuUIProbe = SuuUIProbe or {}` is gone, and `SuuUIProbe.x` became
    `DB.probe.x`. Probes run from commands after login, and nothing
    touches DB at load time.
  - TotemProbe's `SuuUIDB and SuuUIDB.blocked` → `DB.db.blocked`.
  - What each probe records keeps the same keys and shape.
- **ApiDocs guards dropped.** Meter, Timeline and Taxi checked `if
  ns.ApiDocs and ns.ApiDocs.Dump`. That was always true, and it's a
  static import now (`apiDocs.dump`, `apiDocs.flags`).
- **Events owners.** Plate, Meter and Timeline registered their fight
  listeners with the probe table as owner. Each now uses a module-local
  `OWNER = {}`, so Fault's source name stays `tostring(table)` as before.
  TrackProbe keeps its `"TrackProbe"` string, and its glow listener is still
  registered at load inside a pcall.
- **Own event frames kept.** These probes keep their own `CreateFrame`
  listeners and don't move to Core/Events:
  - They register in `pcall` events this client may not have.
    `Events.onGame` would raise an error there instead.
  - Some are transient watchers they unregister later (ADDON_ACTION_BLOCKED
    and similar, the trainer watch).
  - Core/Events would also run every event through `fault.call`.
- **Undeclared globals read through `_G`:** `NamePlateDriverFrame`
  (PlateProbe), `GetNumTalentGroups`, `GetTalentResetCost` and
  `GetTalentWipeCost` (TalentProbe, TalentBuildProbe).
- **Possibly-secret class values.** Three `UnitClass` results are typed
  `any` and compared as before: `local _, class: any` (Power, Track,
  Totem) and `local _, _, myClassID: any` (TalentBuildProbe). A secret
  class would raise an error just as it did in Lua.
- **Module upvalues that closures read again later stay `any`:**
  TaxiProbe `land` and TalentBuildProbe `step`. A later test replaces them,
  and the callbacks must read the current one, as before. Typing them
  optional would have forced a local copy, which would change which test
  gets written to.
  - The `Button?`/`Frame?` upvalues read inside callbacks are cast where
    they're used (`landButton`, `trainerFrame`, TrackProbe `statusText` and
    `verdictText`).
- **Small state changes:**
  - TrackProbe `rows` starts as `{}`, not nil. `tick` reads it only once
    the panel exists.
  - PowerProbe `start` starts at 0, not nil. It's set before the listener
    exists.
  - MeterProbe and TimelineProbe build their event-count tables as locals
    and then publish them to the module upvalues, so the OnEvent closure
    sees non-optional tables. These are the same table objects.
- **Renamed local:** in TalentBuildProbe's trainer watch, `after` became
  `state` (it shadowed the timer import).
- **Warnings left as they were in the Lua code:**
  - SkysightProbe: `a` shadows `a` at line 154.
  - TalentBuildProbe: `ok` shadows `ok` at lines 608 and 631.
  - TotemProbe: unused `castable` at line 90.
