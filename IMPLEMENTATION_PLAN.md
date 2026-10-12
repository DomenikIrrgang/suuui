# SuuUI for WoW Forever: implementation plan

Target client: WoW Forever beta 1.60.1 (`## Interface: 16001`, game type `camelot`). It runs the 12.1 (Midnight) engine with vanilla content, so the secret-values restrictions apply.

Sources of truth:
- **Design system:** https://claude.ai/artifact/NcdJv21GMnN9gaQ5mF1oSw. It holds the brand book (`README.md`), `tokens.json`, `group-frames.md` and 70 component specs.
- **Design canvas:** https://claude.ai/artifact/2Esuzrf8QLJVm2WWGcDYfF. It has three pages: Components, Scenes and Windows and settings, 64 boards in all.
- **API reference:** EllesmereUI in this AddOns folder already runs on Forever. Read it for working examples of `issecretvalue`, `C_CurveUtil.CreateColorCurve`, `SetAlphaFromBoolean`, `C_SwingTimer`, `C_DamageMeter`, the CooldownViewer frames and `EditModeManagerFrame`.

---

## Client facts (from `/suu probe`)

These come from probe runs on 2026-10-11, build 1.60.1.70338: solo in the open world (Tirisfal Glades), and solo in a dungeon (Wailing Caverns) both between pulls and fighting trash. They replace the design's "unconfirmed on Forever" notes. Still to probe: a boss encounter, a group, and a raid.

| Topic | Finding | What it means for the build |
|---|---|---|
| **Health and power** | **Secret even out of combat**, solo in the open world, for the player and nameplates alike. `UnitHealthPercent` is secret too | The design's table says "full" out of combat; on Forever it isn't. Treat health and power as secret **everywhere**: fills through `StatusBar`, the low-health fill and tint through colour curves, % text through secret-safe formatting. Fading to `opacity-ooc` "with everyone full" can't compare health, so it has to come from combat state, or from a curve if alpha can take one (to verify in 1.1) |
| **Percentages** | `UnitHealthPercent`/`UnitPowerPercent` with `CurveConstants.ScaleTo100` return 0–100, readable out of combat but **secret in dungeon combat** (probe, 1.60.1; EllesmereUI's note that they are always clean doesn't hold here). Colour and step curves (`C_CurveUtil.CreateColorCurve`/`CreateCurve`) passed to the same functions are evaluated by the engine; StatusBars take secret current and maximum values directly. Your own max health is readable even in combat | Health and power bars take the raw (secret) values; the % text goes to `SetFormattedText` as display only; the low-health fill and low-mana amber are second bars whose alpha comes from a step curve; the out-of-combat fade falls back to combat state when health is secret. No Lua comparison of a hidden value anywhere |
| **Secret-value rules** (learned in 1.1–1.2) | In combat: unit yes/no queries (`UnitIsUnit`, `UnitIsPlayer`, …) can return **secret booleans**, and any truth test (`if`, `and`, `or`, `not`) on one errors; arithmetic or comparison on a secret number errors; and a region **anchored after a region with secret content** (text after an enemy's name) reports its own geometry as secret too | Show things from secret booleans with `SetAlphaFromBoolean`; read yes/no through `UI.Flag` (secret reads as false); never write `v or 0` on a possibly secret `v` (`amount()`); measure text with `UI.MeasureText` (an unanchored FontString), never read sizes back from regions in an anchor chain behind secret text. Errors land in `SuuUIDB.errors` with their stacks |
| Unit identity | Your own name, class, level and role are always readable. **In dungeon combat an enemy's name, class and role are secret**; its level, classification, reaction, dead state and power type stay readable | Names go straight to `FontString:SetText`, which takes secret values. Never truncate, measure or compare a name in code: let the FontString clip it. Class colour on enemy names in combat needs a secret-safe path or falls back to reaction colour |
| Secret-value tools | All present: `issecretvalue`, `canaccessvalue`, `issecrettable`, colour curves, `EvaluateColorValueFromBoolean`, duration objects, `SetAlphaFromBoolean`, `SetVertexColorFromBoolean`, `StatusBar:SetTimerDuration`, `Cooldown:SetCooldownFromDurationObject` | The design's restricted-API patterns are all available |
| Heal prediction, absorbs, auras | Calculator, absorbs, `C_UnitAuras` (including `GetAuraDuration`) and `GetAuraDispelTypeColor` all present. Auras read fine out of combat; **`GetAuraDataByIndex` raises an error in dungeon combat** for the player, the target and nameplates | Auras can't be read by index in combat. Every other read fails too (see the next row) |
| Casts, threat | `UnitCastingDuration`/`UnitChannelDuration`, `UnitThreatSituation`, `UnitDetailedThreatSituation` present. Threat is **readable in dungeon combat** on the target and nameplates | Threat borders, badges and the threat meter as designed. Cast bars as designed; interrupt state still depends on the cooldown question above |
| **Auras in combat** | Every read of auras by addon code (`GetAuraDataByIndex`, `GetAuraSlots`, `GetUnitAuras`) **errors in dungeon combat**: "Auras cannot be accessed when secret while tainted". It applies to you, your target and nameplates. Out of combat it works. The 12.1 engine instead offers **aura containers**: `CreateFrame("AuraContainer", …, "CustomAuraContainerTemplate")`, filled by the engine from filter groups (`AddAuraGroup`) such as `RAID`, `RAID_IN_COMBAT`, `RAID_PLAYER_DISPELLABLE`, `CROWD_CONTROL`, `BIG_DEFENSIVE`, `EXTERNAL_DEFENSIVE` and `CANCELABLE`, with engine-side duration text (`SetDurationText` plus `C_StringUtil` numeric formatters) and dispel-type borders. EllesmereUI's `EllesmereUI_AuraKit.lua` is a working example; its notes show the container API was renamed between beta builds | Every aura display (step 1.4, unit frames, group frames, nameplates) is an engine aura container that SuuUI **styles**: `AuraIcon` becomes a skin for the engine's aura buttons, never a widget fed with aura data. The design's aura-slot order (dispellable, then defensive or external, then shield, then your HoTs, then others' HoTs) maps onto ordered, mutually exclusive filter groups. Which spell an aura is stays unknowable in combat, as the design already says. Keep all container calls in one core wrapper, because the API is still moving |
| **Aura spell lists** (1.7a probe, 2026-10-11) | Engine aura containers with `candidateFilters = { includeSpellIDs = { [id] = true } }` **filter in dungeon combat**: on the player (`HELPFUL`: "only Mark of the Wild" hid Thorns) and on an enemy target (`HARMFUL\|PLAYER`: "only Moonfire" hid Entangling Roots), while every addon aura read errored. Auras are hidden in **any** combat, the open world too. The engine's aura buttons are forbidden even out of combat (not even `IsShown`), and the container isn't sized to them, so addon code can't count them | SuuUI's own tracker (1.7) is possible: tracked buffs, debuffs and aura procs as spell-listed containers. Never touch the engine's buttons outside the initializer. Still open: reactive procs (`IsSpellUsable` in combat: needs a warrior, rogue or melee hunter), the proc-glow event (none fired), a boss fight as confirmation |
| **Aura filter words** (probe 2026-10-11) | `AuraUtil.AuraFilters`: HELPFUL, HARMFUL, PLAYER, RAID, CANCELABLE, `!CANCELABLE`, DISPELLABLE, RAID_PLAYER_DISPELLABLE, RAID_IN_COMBAT, IMPORTANT, BIG_DEFENSIVE, EXTERNAL_DEFENSIVE, CROWD_CONTROL, INCLUDE_NAME_PLATE_ONLY, MAW. **Negation works**: `AuraUtil.AuraFilterNegationPrefix` is `!`; `HARMFUL\|!PLAYER` and `HELPFUL\|!PLAYER` are valid and an aura container accepts them (it rejects unknown words). Containers also offer `AddItemEnchantment` (weapon enchants), `AddAuraSlot`, sort methods (Default, Expiration, Name, BigDefensive, UnitFrameDebuff, ImportantOnly…). `C_UnitAuras.AddAuraSound` (triggers Added, ApplicationsIncreased, Removed) plays sounds engine-side | "Not mine" groups work: Others' Judgements showed another paladin's judgements in game (2026-10-12). Weapon enchants (1.4 follow-up) and proc sounds become possible |
| Your own cooldowns | Spell 29515 (Forever's global cooldown reference) is readable out of combat; 61304 doesn't exist here. **In dungeon combat, `startTime`, `duration` and `modRate` are secret, but `isActive` and `isEnabled` stay readable**, for the GCD and for action-bar slots alike. Each action's cooldown duration object is readable | Swipes and timers come from the duration objects (`SetCooldownFromDurationObject`). "Ready" is `not isActive` (readable), so the interrupt glyph, desaturate-until-ready and the Cooldown Manager's ready flash work as designed. Remaining seconds as text need a secret-safe formatter, as auras use |
| Unit values, solo (`/suu probe group`, 2026-10-12) | **Health is secret even out of combat**; `AbbreviateNumbers(secret health)` returns a secret string (so "8.5k" works via `SetFormattedText`). `UnitInRange` is secret (both returns) in and out of combat. `UnitThreatSituation` stays **readable in combat** (3 on you while tanking). `UnitIsUnit(unit, "target")` readable in combat. `UnitGroupRolesAssigned` readable ("NONE" solo). **Every aura read fails in combat while tainted**, instance IDs included (`GetUnitAuraInstanceIDs`, `GetAuraDataByIndex`): "Auras cannot be accessed when secret while tainted" | Range fades go through `SetAlphaFromBoolean`; aggro badges work in combat; debuff-type badges from Lua stay out-of-combat only (in combat only engine containers can show a debuff type). Party units still to probe in a group |
| Nameplates (`/suu probe plates`, 2026-10-12, open world and a dungeon) | Every nameplate API SuuUI needs exists (GetNamePlateForUnit/GetNamePlates, SetNamePlateSize, C_NamePlateManager.SetNamePlateHitTestInsets, NamePlateType/StackType enums, NamePlateDriverFrame.OnNamePlateAdded, plate:SetStackingBoundsFrame, UnitCastingDuration/UnitChannelDuration, EvaluateColorValueFromBoolean). **Enemy plates and Blizzard's UnitFrame on them are not forbidden, in a dungeon too, in and out of combat.** Health secret always; **enemy names secret in a dungeon** (even out of combat; readable for players in the open world); reaction and "is it your target" readable; `UnitThreatSituation("player", plate)` readable in combat (3 while you tank it, nil without threat). No other nameplate addon loaded (EllesmereUINameplates off). Casts not yet seen (no caster) | Plates are buildable as planned: names go to the text as they are (never measured), threat badges from Lua, target from Lua; casts to confirm on a caster |
| Aura containers in combat (2026-10-12) | `SetAuraGroupMaxFrameCount` (to 0 and back) works **in combat**: a packed ("hide when missing") Cooldown Manager buff with a stance condition follows stance switches mid-fight | Live conditions (stance, combat, target) work on every kind of entry, in combat too |
| Damage meter (`/suu probe meter`, 2026-10-12, open world solo, hunter) | The documentation matches EllesmereUI's use (see 1.12's reference); sources also carry `classification`, `sourceDisplayType`, `factionGroup`, spells `overkillAmount`, `isAvoidable`, `isDeadly`. **In combat** every session's `totalAmount`, `maxAmount`, `durationSeconds` and each source's `name`, `sourceGUID`, `totalAmount`, `amountPerSecond`, `deathTimeSeconds`, `sourceDisplayType` are secret; `classFilename`, `specIconID`, `isLocalPlayer`, `deathRecapID`, `classification` readable. `GetAvailableCombatSessions()` (11 fights, named after the mob, with durations) and `GetSessionDurationSeconds(Current)` stay **readable in combat**. A secret GUID as the breakdown's argument is refused ("Secret values …"). **After combat** all readable; names carry the realm ("Suleria Stargazer"); a hunter's pet is no source of its own: its damage is in the owner's breakdown (`creatureName` = the pet). `DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID)` fires constantly in combat (88 in one fight), `DAMAGE_METER_CURRENT_SESSION_UPDATED` once. Blizzard's frames: `DamageMeter` (hidden here), `DamageMeterSessionWindow1` (shown) | The meter as designed: rows from the engine's order, fills and numbers from secret values through the engine, the time from the readable duration, your breakdown in combat through `UnitGUID("player")`, others' after combat |
| Encounter timeline (`/suu probe timeline demo`, 2026-10-12, open world solo) | `C_EncounterTimeline.IsFeatureAvailable()` and `IsFeatureEnabled()` are **false**; `AddEditModeEvents()` adds nothing (returns 0); 5 tracks exist with zero durations; `Blizzard_EncounterTimeline` not loaded. **`AddScriptEvent({ spellID, iconFileID, duration, overrideName })` works anyway**: `ENCOUNTER_TIMELINE_EVENT_ADDED` fires with the full info (id, source Script, spellName = the override, spellID, iconFileID, duration, severity, icons mask, isApproximate), and `GetEventTimeRemaining`, `GetEventTimeElapsed`, `GetEventState` (Active), `GetEventTimer` (a duration object), `GetEventColor` and `GetEventTrack` (Indeterminate) all answer, readable. Docs: event info `{ id, source, spellName, spellID, iconFileID, duration, maxQueueDuration, icons (EncounterEventIconmask: TankAlert, HealerAlert, DamageAlert, Deadly, Dispel, Enrage), severity, isApproximate }`, events ENCOUNTER_TIMELINE_EVENT_ADDED/REMOVED/STATE_CHANGED/HIGHLIGHT/… Whether a Forever boss sends Encounter events: still to probe on a boss | Boss data probably doesn't arrive (to confirm); SuuUI's own timers (a pull countdown, readiness) can ride the timeline as script events |
| Sound files (2026-10-12) | **Forever resolves no sound file paths**: `PlaySoundFile("Sound\\Interface\\RaidWarning.ogg")` returns nil and plays nothing. File IDs play (567409 ready check, 567416 map ping, 567458 alarm, 567397 raid warning). `C_UnitAuras.AddAuraSound(trigger, { unitToken, spellID, soundFileID, outputChannel })` takes `soundFileID` or `soundFileName`, not sound kits, and plays in game (Righteous Fury appear/drop, confirmed) | Sounds are file IDs everywhere; sound kits (`PlaySound`) only as a fallback for previews and cooldown sounds |
| Swing timer | `C_SwingTimer` (2 functions), `Enum.PlayerSwingType`, `Blizzard_SwingTimer` loaded. **Auto Shot keeps its stand-still cast** (2026-10-11, hunter): moving in the last half second holds the shot until you stop. Blizzard's own swing timer doesn't show by default | As designed; the Auto Shot window stays on (it switches itself off only if a client fires shots while moving) |
| Cooldown Manager | `C_CooldownViewer`, all four viewer frames, `Blizzard_CooldownViewer` loaded | As designed |
| Damage meter | `C_DamageMeter` (8 functions), 11 meter types, 3 session types | As designed |
| **Encounter timeline** | **Exists**: `C_EncounterTimeline` (34 functions); `Blizzard_EncounterTimeline` loads on demand | Step 1.13's timeline is buildable, no longer a maybe |
| **Action bars** | **8 bars**: `MainActionBar` plus `MultiBarBottomLeft`, `BottomRight`, `Right`, `Left`, `MultiBar5`–`7`. No `MultiBar8`, no `MainMenuBar`. `StanceBar`, `PetActionBar`, Edit Mode bar enum with 11 values | Bars 1–8 as designed; bar 1 is `MainActionBar` |
| Edit Mode | `C_EditMode`, `EditModeManagerFrame` | Native, as designed |
| Group sync | Addon messages present, plus `InChatMessagingLockdown` and `AreOutgoingAddonChatMessagesRestricted`. In dungeon combat (trash, not a boss) **outgoing addon messages are restricted** (`true`) while chat messaging lockdown is `false` | Readiness sends only while `AreOutgoingAddonChatMessagesRestricted()` is false, and queues otherwise. It is blocked during any dungeon fight, not only during an encounter |
| Specializations | `GetSpecialization` is **absent**; `C_SpecializationInfo`, `C_ClassTalents`, `C_Traits` present | Read the spec through `C_SpecializationInfo` |
| Spellbook and talents | `Blizzard_PlayerSpells` loads on demand; no `SpellBookFrame`, no `Blizzard_TalentUI` | Spellbook and talents are retail's combined `PlayerSpellsFrame` (step 3.2) |
| Legacy | Blizzard UI exists: `LegacyMicroButton`, `LegacyChallengeViewedUtil`, and more (full list in the saved probe data) | Step 3.2 restyles Blizzard's Legacy window |
| Campfires | No camping API or frame | As the design expected: auras and item cooldowns only |
| Quests and map | `C_QuestLog.GetQuestsOnMap`, `C_QuestLine`, `C_TaskQuest`, `C_SuperTrack`, retail's `ObjectiveTrackerFrame` | Quest pins can use the game's own data |
| Professions, Group Finder, social, bags, tooltips | `C_TradeSkillUI`, `C_ProfSpecs`, `C_LFGList`, `C_FriendList`, `C_Club`, `C_Container`, `C_Bank`, `TooltipDataProcessor`, `C_TooltipInfo` | Retail APIs throughout |
| Game type | `C_GameRules` and `Enum.GameMode` exist | Detect Forever through these if the TOC gate ever isn't enough |
| Your screen | 1920×1080, UI scale 0.71, `useUiScale` off | The design is drawn for 2560×1440. Decided in 0.5: one design pixel is one physical pixel, so sizes stay as designed and only the gaps between clusters shrink |

---

## Architecture

SuuUI is written from scratch for this client. The design system is the only input besides the client's own API.

| Layer | What it is |
|---|---|
| Tokens | `Core/Tokens.lua`, generated from the design system's `tokens.json`. It is the only place colours, sizes and durations come from |
| Core services | Event bus, settings with per-character profiles, combat queue, Blizzard-frame suppression, pixel scale, error reporting |
| Primitives | Text, Panel, Icon, StatusBar, Button, glows and animation presets, laid out by an engine that invalidates and then flushes once per frame |
| Components | One Lua component per design-system component (`UnitFrame`, `AuraIcon`, `ActionButton`, …), with the same names and props |
| Module system | A registry that loads, enables and disables modules, and the versioned **public API** they are written against |
| Modules | One per HUD area or window, built-in or from a plugin addon. Each has its own Enabled toggle, settings section and edit-mode handle |
| Tests | Not yet. A test harness is being built separately and will be brought into the project later; until then every step is confirmed in game |

### Pluggable by design

Every feature can be switched off entirely, and other addons can extend SuuUI.

- **Every feature is a module.** Unit frames, action bars, chat, bags and every other feature are each one module. The core itself only holds the services, primitives, components and the settings window.
- **A disabled module costs nothing.** It is never initialised: no frames, no events, no settings section. Blizzard's own frame for that feature stays exactly as it was. Turning a module on or off takes effect at once. The exception is a module that replaced a protected Blizzard frame, such as the action bars: it switches on the next reload, and the settings window offers Reload now.
- **Built-in modules use the public API.** They are written as if they were plugins, so a plugin addon can do anything a built-in module can.
- **Plugin addons** declare `## Dependencies: SuuUI` and register through `SuuUI.RegisterModule`. A plugin can:
  - add a module with its own settings section, edit-mode handle and profile data
  - use the tokens, fonts and every component (`UnitFrame`, `AuraIcon`, `Panel`, …), so it looks native
  - listen to SuuUI's messages, such as a module enabled, a profile changed or the group profile switched
  - extend another module through its published extension points, for example adding an element to every unit frame, a row type to the damage meter or a notification kind
  - anchor to another module's frames by a published anchor name (`"player"`, `"dock"`, `"chat"`), never by reaching into its internals
- **The API is versioned.** `SuuUI.API_VERSION` follows semantic versioning, and a plugin can require a minimum version. A plugin that fails to load or errors shows one line in the settings window's module list; it never breaks SuuUI or another plugin.
- **One list of modules.** A Modules page in the settings window lists every module, built-in and plugin, with its toggle, its state and where it came from.

### Rules for every increment (definition of done)

1. **The game stays playable.** Each feature is a module with an Enabled toggle. Until a module exists, or while it's off, Blizzard's own frame is left untouched. Suppress Blizzard frames by reparenting them to a hidden frame, never with an `OnShow → Hide` hook.
2. **It goes through the public API.** A module uses only the public API, and it reaches other modules only through their published anchors, messages and extension points. Anything new a module needs from the core is added to the public API and documented there, so plugins can use it too.
3. **It loads cleanly.** No Lua errors with `/console scriptErrors 1`. Every changed file passes a quick `luac -p` syntax check (no automated tests until the separate harness is brought in).
4. **It's combat-safe.** Nothing protected moves in lockdown: route those changes through the core combat queue. Run a `/console taintLog 1` session on anything secure.
5. **It respects secret values.** Never compare or do maths on a value that might be secret. Use curve objects, `SetAlphaFromBoolean` and duration objects. Where the client hides data, hide the slot.
6. **It's performant by construction.** Show and Hide are idempotent. Events use `RegisterUnitEvent`. Each widget caches the last value it painted. Views that are hidden are marked stale and refresh on Show. Lists are reconciled by key, never rebuilt.
7. **It's configurable.** Each module adds its own section to the settings window. Changes apply live and the module has an edit-mode handle.
8. **It matches the design.** Compare the result with its canvas board(s) side by side at 2560×1440 with UI scale 1, and note any deviations.
9. **It ends in a commit.** Commit with the increment number, then do the in-game confirmation below.

Every step below gives what's built, the boards it implements, how to confirm it in game, and the Forever unknowns to verify first.

---

## Phase 0: Foundation

### 0.1 Scaffold and API probe
- **Build:**
  - `git init`, `SuuUI.toc` (`16001`, `AllowLoadGameType: camelot`), `Core/Init.lua` and the slash commands `/suu` and `/suuui`.
  - A **`/suu probe`** report that prints, for each API the design depends on, whether it exists on this client. Covered: `C_DamageMeter`, the encounter timeline API, `C_SwingTimer`, CooldownViewer frames, `C_CurveUtil`, `SetAlphaFromBoolean`, `UnitGetDetailedHeal/AbsorbPrediction` (heal prediction calculator), the dispel-type colour APIs, `UnitThreatSituation`/`UnitDetailedThreatSituation`, the `C_UnitAuras` duration objects, `C_LootHistory`, `C_LFGList`, the quest map pin APIs, the Legacy and Professions APIs, and the number of Edit Mode action bars.
- **Confirm:** the addon is listed and enabled. `/suu` prints its version, and `/suu probe` prints a table you can paste back. That table settles every "unconfirmed on Forever" note in the design.

### 0.2 Tokens and fonts
- **Build:**
  - `tools/gen-tokens.py` turns the design system's `tokens.json` into `Core/Tokens.lua`: colours as 0–1 RGBA, sizes, spacing, durations, easing mapped to AnimationGroup smoothing, and type styles.
  - Ship the Figtree and Marcellus SC TTFs from Google Fonts in `Media/Fonts/`, with their OFL texts beside them.
  - `/suu tokens` opens a token sheet showing every colour swatch and every type style.
- **Boards:** the design system's foundations (Color, Typography).
- **Confirm:** the swatches match the design-system page and both faces render. `micro` (9.5px) is still legible at your UI scale.

### 0.3 Core services
- **Build:**
  - An EventBus that dispatches over a snapshot, so listeners can be added or removed safely during an emit.
  - Settings and Profile (SavedVariables with per-character profiles). Watchers can veto a write before it's stored, a nested write supersedes the outer one, and table defaults are copied, never handed out.
  - Add a core **combat queue** (deduplicated, flushed on `PLAYER_REGEN_ENABLED`) and a **SuppressBlizzard(frame)** helper that reparents.
  - Add `Pixel` (perfect scale, rescaled only on uiScale changes and deferred while in combat) and `Fault` for errors players should see.
- **Confirm:** a setting changed through `/suu set` survives `/reload` and appears under the right profile. Switching profiles works. An error deliberately thrown in a test plugin shows as one player-visible line instead of breaking the load.

### 0.4 Module system and plugin API
- **Build:**
  - The module registry: `SuuUI.RegisterModule{ id, name, description, defaults, OnInitialize, OnEnable, OnDisable, reloadToToggle }`. Enabled state is saved per profile. A disabled module is never initialised.
  - The first version of the public API on the `SuuUI` global, documented in `Docs/API.md`: `API_VERSION`, `RegisterModule`, `GetModule`, `ListModules`; per module `Get`/`Set`/`Reset`/`Watch`/`Veto` for its settings, `On`/`Off`/`Emit`, `OnGameEvent`/`OnUnitEvent`, `RunOutOfCombat`, `RegisterCommand`; plus `Tokens`, `Fonts`, `Pixel` and `SuppressBlizzard`/`RestoreBlizzard`. Later steps add components, anchors and extension points to it.
  - Isolation: each plugin's callbacks run under `pcall`, and a failure goes to `Fault` and marks that module as errored.
  - `/suu modules` lists every module with its state and source; `/suu enable <id>` and `/suu disable <id>` toggle one until the settings window exists.
  - `Examples/SuuUI_HelloPlugin`, a small plugin addon kept in the repository. Copy it into AddOns to test with; it is not shipped.
  - The probe from 0.1 becomes the first built-in module (`diagnostics`).
- **Confirm:**
  - With the example plugin copied in, `/suu modules` lists it next to `diagnostics`.
  - `/suu disable hello` removes it at once, and it stays off after `/reload`.
  - Breaking the example on purpose (an error in `OnEnable`) marks it as errored, and SuuUI and the other modules keep working.
  - Deleting `SuuUI` while the example plugin is installed shows the client's normal "missing dependency" message, with nothing else broken.

### 0.5 Primitives and layout engine
- **Build:**
  - Primitives:
    - Text, with idempotent Show/Hide and cached metrics.
    - Panel (`surface`, `surface-glass`) with the gilt hairline and corner diamonds.
    - The `inset-anchor` double gilt frame.
    - Icon (8% crop, 1px state border, desaturated state).
    - StatusBar that accepts secret values, colours through a curve, and draws a ghost segment.
    - Button, Tooltip shell, and the glow effects (`glow-arcane`, `glow-ember`, `glow-ward`).
  - A layout engine that uses `Invalidate()` plus a per-frame flush, with stack, grid and anchor strategies.
  - Anchoring by cluster: positions are expressed from an edge or the centre, using the 2560×1440 reference. **Decided:** `SuuUI.Root` runs at pixel-perfect scale, so one design pixel is one physical pixel; on other resolutions the frames keep their size and only the gaps between clusters change. `ui.scale` multiplies it (automatic: 1 up to 1440p, larger above).
  - Animation presets from the Motion table, including the reduced-motion switch.
  - Tokens, fonts, primitives and the layout engine are added to the public API.
  - **`/suu gallery`** shows all of them.
- **Boards:** Alerts and badges (StateBadge), Window frame (shell only), and the Panel, Button, ProgressBar and SectionHeader component pages.
- **Confirm:** the gallery matches the component previews. Dragging a resizable gallery panel stays smooth, and the debug counter shows SetPoint calls per frame staying flat.

### 0.6 Settings window
- **Build:**
  - `SettingsWindow` with nav sections and search, opened with `/suu` (no arguments) and from the game menu. The minimap Jewel comes in 2.1.
  - `SettingRow` and `SettingsGroup`: each row says what it does; a changed row shows an `ink` diamond and a reset arrow; sections count their changes; a disabled row dims and says why.
  - The controls the existing settings need: Toggle, Checkbox, Segmented, Select (single and multiple), Slider and Stepper. The rest arrive with the first step that uses them: KeybindField (1.6), AnchorPicker (1.4), ListEditor (1.7), ColorPicker and FilterMenu (where a setting first needs them).
  - The **Modules** page: every built-in and plugin module with its toggle, its state (on, off, errored, needs reload) and its source. Each enabled module's settings section appears in the nav, so a plugin's section sits beside the built-in ones.
  - The **General** sections: Appearance (`ui.scale`), Motion (`ui.reducedMotion`) and Profiles (switch, copy, delete, reset, and Import/Export as a text string).
  - The public API gains `RegisterSettings`: a section built from a schema with the controls above.
- **Boards:** Settings window, Settings controls, Select and filter menus, Setting rows and groups.
- **Confirm:**
  - Every control works and changes apply instantly; there is no Apply button.
  - Reset works per row, per section and for everything.
  - An exported profile string, imported on a second character, reproduces the settings.
  - The example plugin's section works exactly like a built-in one, and turning the plugin off on the Modules page removes it.

### 0.7 Edit mode
- **Build:**
  - Edit mode: `EditModeFrame` handles on a snap grid for every SuuUI frame that registers one; positions saved per profile, as offsets from the frame's screen anchor.
  - Mutually exclusive with keybind mode (1.6), and closed on `PLAYER_REGEN_DISABLED`.
  - The public API gains `RegisterMover` (an edit-mode handle).
- **Boards:** Edit mode.
- **Confirm:**
  - The gallery's test frame and the example plugin's frame move, snap and stay where they were left after `/reload`.
  - Entering combat closes edit mode cleanly.

> At the end of Phase 0 nothing on the HUD has changed yet, but every later module plugs into tokens, settings, edit mode and the combat queue through the same public API a plugin addon uses.

---

## Phase 1: The combat HUD

### 1.1 Player and target frames
- **Build:**
  - `UnitFrame` `lg` on SecureUnitButtonTemplate:
    - health through a curve (low fill below 35%), with the ghost segment
    - power line, with the low-power switch to `amber`
    - incoming heals and absorbs
    - name in class colour, with the role icon or class diamond
    - meta text (level and classification), the state badge and health %
  - The player frame gets the `anchor` gilt frame and the "you" badge.
  - States: the warded, danger and dispel borders, and the dead and ghost states.
  - Combat-reactive: frames rest at `opacity-ooc` and come up over `dur-slow`.
  - Suppress Blizzard's PlayerFrame and TargetFrame by reparenting.
  - Place both frames by the tank/DPS and healer cockpit rules.
  - Publish the first extension points: unit frame elements (a plugin can add its own text, icon or bar to every unit frame) and the `"player"` and `"target"` anchors.
  - **Combo points** (not in the design): Forever draws them on Blizzard's TargetFrame, which this step stands down, so SuuUI draws five diamonds over the target frame (ink per point, all arcane at five) for rogues and cat-form druids.
  - Until 1.2–1.4, standing down TargetFrame also hides the target's cast bar, its auras and the target of target. Turning the module off (Modules page, then reload) brings Blizzard's frames back.
- **Boards:** Player frame, Target frame; scenes Dungeon boss · DPS.
- **Confirm:**
  - Targeting and click-casting work, and with no target, world clicks are not swallowed.
  - Taking damage shows the ghost drain.
  - The frames fade out of combat and come back when combat starts.
  - Health below 35% switches the fill, including inside a dungeon, where the value is secret.
  - Right-click opens the unit menu.

### 1.2 Target of target, focus, pet and boss frames
- **Build:** ToT (`sm` × `bar-tot`), focus (`md`, placed in the high column), the pet frame (`md`, with focus or mana power), and boss frames 1–5 with their auras on the left, right-aligned against the tracker slot.
- **Boards:** Focus and target of target, Pet frame and pet bar (frame only), Boss frames.
- **Confirm:**
  - Focus a mob with `/focus`.
  - A hunter or warlock pet shows with its power.
  - Boss frames appear on a dungeon boss and fade out cleanly after the kill.

### 1.3 Cast bars (1.3a) and swing timer (1.3b)

Split in two increments: 1.3a cast bars (its own module, attached to the unit frames through published anchors), 1.3b the swing timer.

- **Build:**
  - Cast bars for the player (centre stack), target, focus and boss.
  - Interruptibility drawn through `SetAlphaFromBoolean`, with the lock glyph for casts that can't be interrupted; a friendly unit's cast stays neutral (re-read at each cast start, so a duel turns it arcane).
  - Your interrupt's state at the cast's right end: the `arcane` stop glyph when ready, otherwise its seconds.
  - `SwingTimer` driven by `C_SwingTimer`: main hand, off hand, ranged, the hatched Auto Shot window, `amber` while moving, and the queued on-next-swing spell.
  - Hide Blizzard's cast bar and Forever's swing timer frames.
- **Boards:** Cast bars, Swing timer.
- **Confirm:**
  - A warrior's Heroic Strike shows queued at the end of the bar.
  - A hunter's bar turns `amber` when moving during Auto Shot.
  - An interruptible enemy cast shows your Kick or Pummel readiness.
  - Inside an encounter, the bars still run (from duration objects).

### 1.4 Auras
- **Build:**
  - A core aura-container wrapper (public API) over the engine's `CustomAuraContainerTemplate`: filter groups, layout, the duration-text formatter and button styling all go through it, because addon code can't read auras in combat (see *Client facts*).
  - `AuraIcon` as a skin for the engine's aura buttons: the 8% crop, drain lines, stack counts, the expiry blink under 3s where the engine exposes it, and the dispel-type border.
  - Placement:
    - player buffs top right, growing left
    - player debuffs above the player frame
    - your debuffs on the target, above it
  - Cancel-aura on right-click, using the secure path.
  - Hide Blizzard's BuffFrame and DebuffFrame.
- **Boards:** Auras and cooldowns, Player frame (debuff rows).
- **Confirm:**
  - Buffs sort and time correctly.
  - A poison on you shows the poison border and badge.
  - Right-clicking a buff cancels it out of combat, and in combat it fails gracefully (the game's own rule).

### 1.5 Action bar dock (bars 1–4)
- **Build:**
  - **Decided: SuuUI's own buttons** on plain `SecureActionButtonTemplate` (no Blizzard button template, so nothing joins Blizzard's button event lists). Paging is a secure state driver rewriting each button's `action`; the art follows the same conditions through `SecureCmdOptionParse`, never from inside the secure pass. Every key bound to a slot's binding command clicks our button (`SetOverrideBindingClick`). Blizzard's bars 2–4 move under a hidden parent without `Hide()`; its main bar stays in place at alpha 0 with the mouse off (an addon `Hide()` taints Edit Mode's next combat show). Bars 5–8, stance and pet stay Blizzard's until 1.6.
  - Key bindings show on every bar by default, bar 1 included, with a switch per bar.
  - `ActionButton` (`action`, 20px): cooldown swipes from duration objects, range and usability, keybind text, macro names off, the `arcane` ready pop, and the dispel diamond.
  - Bar 1 pages by stance and form with Forever's paging strings. Its buttons' tooltips name the page ("Bar 1: Cat Form"); the design's row under bar 1 was dropped at the user's request (it left a gap above the XP bar).
  - The dock layout is 538 × 42 px. Every key bound to a button fires it, not only the first.
- **Boards:** Action bars.
- **Confirm:**
  - Warrior stance swaps, druid forms and rogue stealth all page bar 1.
  - Changing a theme or setting doesn't reset paging.
  - Dragging spells onto buttons works, and so do second keybinds.
  - No ADDON_ACTION_BLOCKED in combat.

### 1.6 Bars 5–8, stance, pet, grouping and keybind mode
Split into three confirmable parts: **1.6a** bars 5–8 with per-bar show, columns and key bindings (seeded shown when a bar holds anything on the first load; Blizzard's bars 5–8 stood down); **1.6b** the stance/form bar and the pet bar; **1.6c** keybind mode, the remaining per-bar options (button count, size, spacing, visibility, text size with a thin outline), and grouping. Grouping became **attach to dock** at the user's choice: bars 5–8, stance and pet attach to the dock (drop onto it or the toolbar's Attach), move live with it as one, Reset on an attached bar resets the dock, Detach frees it. Full any-bar grouping was dropped. The XP bar along the dock's foot moved forward into 1.5.
- **Build:**
  - Bars 5–8, hidden by default.
  - The stance, form and totem bar above the dock's left block, and the pet bar above its right block.
  - Per-bar options: rows, button count, size, padding, visibility, and key bindings shown or hidden.
  - Grouping in edit mode: drop one bar onto another to group them, and Ungroup to split them.
  - Keybind mode: hover a button and press a key.
  - The XP and reputation `ProgressBar` along the dock's foot.
- **Boards:** Action bars, Stance and totem bars, Pet frame and pet bar, Micro menu and XP (XP part).
- **Confirm:**
  - Group bar 5 onto the dock, move the group and reload: the arrangement is kept.
  - Rebind a key in keybind mode.
  - Calling a pet in combat shows the pet bar without any blocked action.

### 1.7 Cooldown Manager (SuuUI's own)
Decided: SuuUI's own tracker, not a restyle of Blizzard's CooldownViewer (restyling it means living inside its taint rules: never write its frames, never hide its pool frames, lists only editable in Blizzard's panel). Nothing here touches Blizzard's viewer or needs its CVar.
- **1.7a Probe** (a dungeon fight is enough; one boss fight later as confirmation). **Done for spell lists**: they filter in dungeon combat on the player and on an enemy target (see Client facts). Reactive procs and the proc-glow event still open:
  - an engine aura container on the player with a spell list (`candidateFilters = { includeSpellIDs }`, `HELPFUL|PLAYER`), and one on the target (`HARMFUL|PLAYER`) — do the lists filter in combat, on the player and on an enemy?
  - reactive procs (Overpower, Revenge, Riposte): is `C_Spell.IsSpellUsable` readable in combat, and does `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` fire with a readable spell ID?
  - the brief "any buff" degradation while boarding a vehicle.
  - an appear animation on aura buttons: may an `OnShow` hooked in the container's initializer play an animation on SuuUI's own child texture in combat (the buttons are forbidden to addon code)?
- **1.7b Tracker and list editor:**
  - rows from the design: tracked buffs and debuffs as icons on top (aura containers with spell lists, a dim placeholder under each fixed slot for "not up"), then Essential and Utility cooldowns (the action buttons' method: `C_Spell` cooldown state plus duration objects, greyed until ready, the arcane pop).
  - procs: aura procs as tracked buffs; reactive procs from the probe's answer.
  - "effect running" (Recklessness): an aura container for the spell's buff laid over its cooldown icon. Built 2026-10-12 as a per-entry Behaviour option (off, buff on you, your debuff on the target; the effect is the spell itself or any aura by name or ID). Confirmed in game.
  - "Seen recently" in "+ Add": cooldowns you cast and auras on you and your target (out of combat), the last 12 per class, listed first. Confirmed in game.
  - **per-entry behaviour** (a Behaviour panel on every entry):
    - cooldowns (state readable in combat, so everything): when ready (normal, glow, pop, pulse, sound), on cooldown (grey, dim, hide), show (always, only when ready, only on cooldown), when unusable (dim, hide), reactive "use now", border colour.
    - auras (styled once per slot in the group's initializer): while up (border colour, glow, size, digits, stacks, amber near the end), when missing (hide, grey, grey with a warning edge or a pulse, kept inside the icon's square so the live icon covers it), appear animation only if the probe allows it. Never a sound or alert on an aura change in combat: SuuUI can't see it.
  - settings: the design's Cooldown lists (lists per category, drag between them, ranks folded under the highest), changes apply live (no reload rule). Add by spellbook drag, by name or ID, or from a record mode that lists auras seen on you and your target out of combat.
- **1.7c Presets** (data done 2026-10-11: 30 presets for all nine classes in `tools/presets_source.lua`, generated into `Data/Presets/<CLASS>.lua` by `tools/gen_presets.lua` against the client spell scan `tools/data/forever_spells.tsv`; not in the TOC until the tracker loads them. Forever renames some spells (Bane of Doom, the trap effects, Faerie Fire for the feral version) and lacks others (Blessing of Sanctuary, Elemental Mastery, Curse of Shadow); check each class in play): every preset of the player's class is listed (one per talent tree, plus role splits such as Feral cat/bear); the player loads one and edits it freely, Reset returns to the loaded preset. Presets carry every rank's spell ID: cooldowns resolve ranks from the spellbook by name; buff, debuff and proc aura IDs come from a curated table verified on Forever's client (not retail or classic sites). Order: druid and hunter first (the user's characters, so they can be checked), then the other classes. Lists share through the existing Import/Export strings.
- **Boards:** Cooldown Manager, Cooldown lists.
- **Confirm:** the probe's answers; tracked buffs, debuffs and procs show in dungeon combat; cooldowns grey and pop; editing a list applies at once; loading a preset fills the lists for the class.

### 1.8 Party frames (5-player)
Decided (2026-10-12): **roles pick profiles, not layouts.** The party frames have one set of settings per profile; SuuUI switches profiles by role (General > Profiles > By role: a profile per Tank, Healer and DPS, or "Don't switch"). The role is the one chosen for the character, else the group's assigned role, else the talent tree with the most points (Core/Roles.lua; Feral counts as DPS, bear tanks choose Tank). It switches out of combat only, when the role changes; a profile picked by hand stays until then. The design's healer and side profiles become what a healer or a tank/DPS profile is set to.
- **1.8a Built** (Units/PartyFrames.lua, not yet confirmed in game):
  - You and party1-4 as unit frames (RegisterUnitWatch; shown in a party, hidden solo and in a raid). Direction up, down or across; width, height, gap; show yourself.
  - Power line for tanks and healers (healing classes without roles), everyone or none; health text (percent, value, both); the gradual low-health tint (the empty part of the bar warms to ember from 70% down, strongest at 10%: a linear curve the engine evaluates); incoming heals and absorbs.
  - Auras beside the bar (0-6, left or right), engine containers in order: debuffs you can remove (dispel edge), externals, big defensives, raid debuffs (`!RAID_PLAYER_DISPELLABLE`, no doubles). No buffs: `HELPFUL|PLAYER|RAID` brought Mark of the Wild and other long buffs (2026-10-12); buffs come only through buff indicators.
  - States: Aggro (threat, readable in combat) as the danger badge; debuff types as **slots** (EllesmereUI's technique): per type a one-aura container with `includeDispelTypes`, whose button carries the type's border and badge over the whole frame, shown by the engine, so it works in combat (two sets: every type / only removable, one shown); your target as an arcane border; out of range fades the frame (alpha from a possibly secret boolean). "Show when solo" shows your own frame for testing. The slots live in the shared unit frame (`f:SetDispelBadges`); the player frame has them too (Unit frames > Debuffs on you, every type by default). One badge spot at the row's end: a debuff type's badge covers Aggro (healers must see a curse on the tank); the ember glow still shows aggro. Confirmed in game 2026-10-12 (poison and aggro, solo).
  - Preview in the settings window's preview column (the design's live preview, at real size and centred; no scale-to-fit): a made-up party drawn by the same unit frames from stand-in data (UnitFrame `opts.api`), with a tank, a healer with a magic debuff and your target border, a mage with aggro at low health, a rogue out of range with poison; it follows every setting live. Blizzard's PartyFrame and CompactPartyFrame are stood down.
- **1.8b Probe in a group** (`/suu probe group`, ready; samples on command and 1s/4s into each fight; solo it already covers you and your target, including AbbreviateNumbers on a secret health) (dungeon combat): UnitInRange, UnitThreatSituation and UnitGroupRolesAssigned on party units (secret or readable?); GetUnitAuraInstanceIDs and GetAuraDispelTypeColor in combat (a dispel border and badge in combat); whether Forever's groups assign roles at all.
- **Boards:** Party frames, Group frame profiles (5); scenes Dungeon boss · Healer and Dungeon boss · DPS.
- **Confirm:**
  - The frames show in a party with the right people, and click-targeting works.
  - A curse you can remove badges and borders the unit (out of combat), and its icon shows in combat.
  - With a Healer and a DPS profile mapped, changing spec between pulls switches the profile, and it never switches mid-fight.

### 1.9 Raid frames (10, 20 and 40)
Decided (2026-10-12): like the party frames, **one layout per profile**; roles pick profiles. The design's six raid profiles become two arrangements a profile is set to.
- **1.9a Built** (Units/RaidFrames.lua; confirmed solo 2026-10-12: the headers make and style their buttons, "Show when solo" shows yours, click-targeting, debuff badge, edit-mode mover and the 10/20/40 preview all work; a real raid still to check):
  - A SecureGroupHeaderTemplate per raid group (1-8), buttons from SecureUnitButtonTemplate; the restricted initialConfigFunction sizes them, sets the click actions and calls SuuUI's styling (header:CallMethod). All forty are made out of combat at once (startingIndex -4 trick), since aura containers can't be made in combat. Each button is SuuUI's unit frame (`opts.frame`); the header sets the unit, `OnAttributeChanged` re-points the frame, its aura icons and its debuff-type slots.
  - Groups as **columns** (each a column of five, wrapping into bands: "columns side by side", 4 = the design's two bands at 40) or **rows** (each a row of five, group 1 on top: the healer layout). Width, height, a separate height from 21 players (heal-h-40), gap, gap between groups. Shown in a raid; "Show when solo" shows your own frame to try them.
  - Inside the bar: role icon, name, power line (tanks and healers), health text (none by default, or percent/value), gradual low-health tint, incoming heals and absorbs, 0-3 aura icons inside the bar's right end, clipped to that many in total (removable debuffs, externals, defensives, raid debuffs; no buffs, as on the party frames; the row stops before them).
  - States: debuff-type slots (badge and border, in combat), Aggro (a debuff covers it), your target's arcane border, out of range fades (secret-safe).
  - Preview in the settings column: a made-up raid of 10, 20 or 40 (the design's roster), every state shown. Blizzard's CompactRaidFrameContainer is stood down.
- **1.9b Still open:** the full aura list on hover; the raid lead's readiness panel; sorting by role.
- **1.9c Buff indicators** (Units/BuffIndicators.lua, built and confirmed solo in game 2026-10-12, editor included): EllesmereUI's Buff Manager idea. Per class and spec (talent tree with the most points, 0 unspecced; SUUUI_SPEC_CHANGED switches the list), in the profile so one profile serves every character; the editor has a spec picker: indicators of spells (every rank, from the Cooldown Manager presets or by spell ID), each an icon (with its time from 16px), a coloured square at one of nine points, a border, or a tint over the health fill; yours or anyone's; active at chosen group sizes (Party, 10, 20, 40: `UI.GroupTier`, switched out of combat when the group crosses a size); show while up (engine, in combat), while missing (out of combat only, read by Lua; hidden in combat), or up or missing (a grey icon or the missing colour under the live look, which covers it; in combat; not for bar colour). Show on: everyone, or only your own raid group (e.g. Battle Shout), for every show mode: other units' live containers are hidden out of combat, their missing looks too (subgroup from GetRaidRosterInfo, re-read on roster changes; field `on`, older lists `missingOn`). Engine containers filtered by spell carry the look (built when the engine makes the button), so they work in combat on party and raid frames. Defaults: priest Renew + Power Word: Shield, druid Rejuvenation + Regrowth. Containers are kept per look and reused (the engine never frees them); edits apply to the live frames once a second, out of combat. Previews: the section's own (three people), and the party and raid previews. Editor (designed 2026-10-12): a compact list in a well (grip to reorder = drawing order, icon, name, one-line summary, Edit, ×) under the spec picker, and the Edit indicator modal (live mini preview Up/Missing; Look: Kind, Position on the AnchorPicker grid, Size, Colour swatches; When it shows: Show with its note, Missing colour; Where: Whose, Show on, Group sizes as ToggleChips; what doesn't apply stays dimmed with the reason). New controls UI.AnchorPicker, UI.SwatchRow, UI.ToggleChips (UI/Pickers.lua).
- **Boards:** Group frame profiles; scenes Raid boss 20 · Healer, 20 · Tank, 40 · Healer, 40 · Tank.
- **Confirm:**
  - Solo with "Show when solo": your frame shows, clicks target, the edit-mode mover places the grid.
  - In a raid: the right people in the right groups; joining and leaving re-sorts; crossing 20 players switches the bar height out of combat.
  - The 40-player healer grid clears the dock.

### 1.10 Nameplates
- **1.10a Probe** (`/suu probe plates`, ready 2026-10-12): forbidden plates and Blizzard unit frames, readable vs secret values per plate (health, name, threat on you, target, casts), the nameplate APIs/enums/CVars, and other loaded nameplate addons. EllesmereUINameplates (same client) already shows the technique: own frames parented to Blizzard's plate on NAME_PLATE_UNIT_ADDED (earliest: hook NamePlateDriverFrame.OnNamePlateAdded), Blizzard's UnitFrame at alpha 0 (not reparented: it breaks click selection) with its children moved to a hidden frame and its events unregistered; never write keys onto Blizzard plate frames (weak tables); health straight to StatusBars; casts via UnitCastingDuration + SetTimerDuration, interruptible via SetAlphaFromBoolean; debuffs via aura containers `HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY`; UnitThreatSituation readable on plates; CVars and C_NamePlate.SetNamePlateSize only out of combat; friendly plates in instances are protected (GetNamePlateForUnit returns nil).
- **Build:**
  - Restyle Blizzard's nameplate unit frames into `Nameplate` (`nameplate-w`):
    - up to four of your debuffs above
    - the name in its reaction colour, with health % at the right
    - the `cast-plate` cast bar, carrying the interrupt state
    - threat borders and badges ("Aggro", "Losing") from `UnitThreatSituation`
    - your target in `ink` at full opacity, and the rest at `opacity-plate`
- **1.10b Built** (Units/Nameplates.lua, 2026-10-12, confirmed in game solo: plates, target border, dimming, debuffs, solo Aggro, casts with icon and target, size settings, friendly plates in the open world, quest objectives; threat as a tank in a group still to see): pooled SuuUI plates (12 made ahead, out of combat) parented to Blizzard's plate on NAME_PLATE_UNIT_ADDED for attackable units (re-checked 0.2s later: an enemy can read as not attackable at first); Blizzard's UnitFrame at alpha 0 (a SetAlpha hook keeps it there) with its AurasFrame moved to a hidden frame, restored for friendly units; weak tables only. Up to four of your debuffs (aura container HARMFUL|PLAYER), name (fixed width, reaction colour; secret names cut by the engine), state badge and health % (micro), the 10px bar with the low-health fill, the cast (UI.CastBar size "plate": 8px bar, spell line led by the spell's 13px icon, the lock inside the bar's left end (bar height, 8px at least) on casts you can't interrupt, your interrupt's state and time; under it "› name" of the spell's target in its class colour, from UnitSpellTargetName/UnitSpellTargetClass as EllesmereUI does, secret values passed through untested, setting Cast target). Threat: non-tank Aggro at status 2-3; tank (in a group) Losing at 2, Aggro at 0-1; solo everyone reads as a non-tank, so Aggro shows on what attacks you. Target ink border; with a target the rest at opacity-plate. CVars: plate alpha and scale fixed at 1 (SuuUI dims itself), SetNamePlateSize to the plate, out of combat. Settings: width, health bar height (4-24, default 10), debuffs 0-4, debuff size (12-28, default 16; resized out of combat, as the engine's buttons refuse it in combat: AuraContainer:SetGroupSize via SetAuraGroupLayout), cast bars, your interrupt on plate casts (default on; CastBar:SetKickShown), cast bar height (4-20, default 8; CastBar:SetBarHeight), health %, threat badges, quest objectives (enemy plates: a gilt 8px diamond and the count in micro gilt-text, "3/8" / "45%" / mark only for a single mob, left of the name; from C_TooltipInfo.GetUnit structured QuestTitle/QuestObjective lines, own quest log only via C_QuestLog.IsOnQuest, every value checked for secrecy, cached per plate, re-read on QUEST_LOG_UPDATE; quest givers' !/? have no API on Forever: `/suu probe api giver questoffer unitquest` found none), dim others, friendly plates only in the open world (default on: SuuUI sets nameplateShowFriendlyPlayers, or nameplateShowFriends on older clients, to 1 outside, 0 in dungeons and raids, out of combat; turning it off sets 1 once and hands the setting back to the game); SuuUI's look on friendly plates in the open world (off in dungeons, raids, battlegrounds and arenas) (default on: name in class colour for players, reaction-friendly for NPCs, the bar and health %, target border, the debuffs you can remove (aura group HARMFUL|RAID_PLAYER_DISPELLABLE with the type's border, max = the debuff count; the enemy group "mine" at 0), a neutral cast (CastBar:SetNeutral: no arcane layer, lock or interrupt); no threat (they don't attack you); Blizzard's inside instances, where the game locks them); your own plate (personal resource display) stays Blizzard's; turning the module off restores every hidden Blizzard plate; preview of the design's four plates.
- **Boards:** Nameplates.
- **Confirm:**
  - Pull a pack as DPS: the mob on you shows "Aggro" in `danger`.
  - Tanking, a mob you are about to lose shows "Losing".
  - Plates still update inside a dungeon.

### 1.10c Review round (2026-10-12)
- **Batch 1, bugs (confirmed in game):** sliders off the mouse wheel, steppers snap to their step, profile lists and role profiles kept in step, Cooldown Manager containers reused (AuraContainer:Release), buff-indicator edits published when the edit panel closes, target of target follows, own plate stays Blizzard's, friendly casts neutral, every possibly secret value checked before it is compared.
- **Batch 2, consistent settings (confirmed in game):** settings migrations (`module:Migrate`), the `combat = true` row flag, one Health text control (Percent / Value / Both / None) and one Debuff badges control everywhere, shared labels.
- **Batch 3, new settings and layout (confirmed in game; raid markers also on nameplates):** merged sections (`merge`), Cast & swing bars in one section (cast width the swing timer follows, "Show the target", swing Off / In combat / Always), General > Keybinds (one switch, bars as chips), Micro menu & bags section (Shows, Scale), nameplate groups Size / Casts / On the plate, unit frame width and height, offline state and raid markers on unit and group frames, class-coloured names and role sort on raid, your buffs' size / per row / growth, a scrollbar for the settings content, custom setting rows bound like the others.

### 1.11 Alerts, threat meter and the pull warning
- **Build:**
  - The `Alert` system: centred, about 270px down, short-lived, and present only in combat.
  - `ThreatMeter` beside the damage-meter slot. It sorts by % on ordinary mobs and by state on bosses, and shows only in combat with a hostile target.
  - The "You're about to pull" alert, with your threat drop if it's ready.
- **Boards:** Threat meter, Alerts and badges.
- **Confirm:**
  - Overtaking the tank on a trash mob raises the alert.
  - On a boss, the rows are ordered by state with no errors from secret values.
- **Built (2026-10-12; confirmed in game solo: alerts, test alerts, meter with Show Off / In combat / Always; the pull warning and boss ordering still need a group):**
  - `UI.Alert` and the Alerts module (Insights › Alerts): one alert at a time, top centre 320px down (the design's 270 moved 50px lower, 2026-10-12), in combat only, cleared when combat ends; the same key updates in place, a more urgent one isn't replaced; a sound on danger (setting); "Show test alerts" shows the three tones out of combat; the preview shows them at real size. Public API `SuuUI.ShowAlert(key, tone, title, detail, ...)` / `SuuUI.HideAlert(key)` (0.10); a detail is a format whose arguments may be secret.
  - `UI.ThreatMeter` and the Threat meter module (Insights › Damage & threat): bottom right (right edge 292px in, 28px up, the damage meter's place to its right), always 8 rows, in combat with a hostile target. Rows from `UnitDetailedThreatSituation` for you, your pet and the group (pets as "PET"); states only from `UnitThreatSituation`; by % and ranked while every % is readable, otherwise by state then group order with the boss note; your row pinned in the last slot when it's below; settings Show (Off / In combat / Always: out of combat, or without a hostile target, it shows empty), Who (Group / Tanks and me / Just me), Before the name (Role icon / Class icon / None), Raw threat (readable values only), Warn me before I pull.
  - The warning: "You're about to pull" (warning) at status 1 while someone else holds the mob (in a group or with a pet), "You have drawn aggro" (danger) at 2-3 unless you're the tank, setting When I draw aggro: Off / In a group / In a group or with my pet (default; solo only while your pet is on the mob's threat table); the detail names the target, the holder and your threat drop if it's ready (Feign Death, Feint/Vanish, Fade, Ice Block, Cower, Divine Shield; "ready" from the cooldown's readable `isActive`).

### 1.12 Damage meter
- **Build:**
  - Restyle `C_DamageMeter` into `DamageMeter`:
    - choose the type and the fight (Current, Overall, past fights)
    - rows drawn as they arrive, ranked, never sorted or summed in combat
    - the share % appears after combat
    - your row stays in view
    - click a player for spell breakdowns or a death recap
    - up to three stacked windows
  - Move its Edit Mode options into the settings section Damage & threat.
- **Boards:** Damage meter, Settings · Damage & threat.
- **Reference (EllesmereUIDamageMeters on this client, read 2026-10-12; to be checked by `/suu probe meter`):**
  - Calls: `GetCombatSessionFromType(sessionType, meterType)` / `FromID(sessionID, meterType)` → `{ combatSources = { { name, classFilename, specIconID, totalAmount, amountPerSecond, isLocalPlayer, sourceGUID, sourceCreatureID, deathRecapID, deathTimeSeconds } } }` (it never reads `maxAmount`/`totalAmount` of the session); `GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID, sourceCreatureID)` / `FromID` → `{ combatSpells = { { spellID, totalAmount, creatureName, combatSpellDetails } } }`; `GetAvailableCombatSessions()` → `{ { sessionID, name, durationSeconds } }` oldest first; `GetSessionDurationSeconds(sessionType)`; `ResetAllCombatSessions()`; `C_DeathRecap.GetRecapEvents(recapID)` (newest first: `spellId`, `spellName`, `event`, `amount`, `overkill`, `currentHP`, `timestamp`) and `GetRecapMaxHealth(recapID)`.
  - In combat: `name`, `sourceGUID`, `deathTimeSeconds`, spell `spellID` secret; `classFilename`, `specIconID`, `isLocalPlayer`, `deathRecapID` readable; amounts possibly secret. The engine ranks sources and spells (no sorting); deaths come newest first. Bars: `SetMinMaxValues(0, sources[1].totalAmount)` + `SetValue(totalAmount)`, secrets passed whole; numbers via `AbbreviateNumbers` (accepts secrets) to `SetText`/`SetFormattedText`; shares only when readable. Your own name from `UnitName("player")`, your breakdown via `UnitGUID("player")` (getters refuse secret GUID arguments); `RAID_CLASS_COLORS[secret]` and secret table keys throw.
  - Events: `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED` (continuous in combat), `DAMAGE_METER_RESET`; a ~1s ticker in combat, event-driven out of it; re-read 0.5s after combat ends (declassification lags; `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)`, `ADDON_RESTRICTION_STATE_CHANGED`). Blizzard's meter: CVar `damageMeterEnabled` 0 (restore on disable).
- **Confirm:** the numbers match Blizzard's own meter for the same fight, and the threat meter is exactly as tall as the damage meter.
- **Built (2026-10-12; confirmed in game solo: meter, types, fights, breakdown, settings, preview on made-up data; the numbers match Blizzard's meter):** `UI.DamageMeter` (one window on `C_DamageMeter`: bare type and fight selects in the head (`UI.Select` got `bare`), the fight's time, a menu with New window / Reset all fights / Close this window / Settings; rows in the engine's order with rank, class icon / diamond / none, name without realm (yours from `UnitName`), value per Numbers (Minimal; Compact adds the per-second or, on DPS/HPS, the total in brackets; Complete adds the share after combat), class-coloured bars on request, your row pinned; your row opens your spells any time, others' after combat (a secret GUID is refused); deaths in the order they happened, opening the recap from `C_DeathRecap` with health after each hit) and the Damage meter module (Insights › Damage & threat, the threat meter's settings merged below: Show Always / In a group / In combat / Hidden, Numbers, Rows 4-15 (the threat meter follows), Bars, Before the name, Names, Keep my row in view, Windows 1-3 stacked upward with their own type and fight kept; Blizzard's meter off through `damageMeterEnabled`, handed back when the module stops; 1s ticker in combat, events out of combat, re-reads 0.5s and 1.5s after combat; preview: the threat meter and your live meter).

### 1.13 Encounter timeline and readiness
- **Build:**
  - `EncounterTimeline` at top centre (`timeline-w`): ability icons ride toward now, timers turn `amber` under 5s, with "Tank" and "Spread" badges. It hides when no data arrives, depending on the result of 0.1's probe.
  - `Readiness`: cooldowns shared through addon messages between pulls, with a Ready check button for the leader. It hides on pull and returns after `ENCOUNTER_END`.
- **Boards:** Encounter timeline, Insight · Readiness.
- **Decided (2026-10-12):** Forever has Blizzard's encounter timeline feature off, but script events work, so the timeline is built as designed and shows whatever the game's timeline holds: boss abilities if they ever come, SuuUI's own timers (the pull countdown first). Readiness as designed.
- **Built, boss mods as a source (2026-10-12, not yet confirmed in game):** Insights › Timeline › Boss timers, From: SuuUI (the game's timeline and SuuUI's timers) plus DBM and/or BigWigs when loaded (a chosen one that's gone at login falls back to SuuUI). DBM: `DBM:RegisterCallback` `DBM_TimerBegin (id, text, seconds, icon, type, spellID, colorId, …)`, `DBM_TimerStop/Pause/Resume/Update`; badges from colorId 4 (Kick) and 5 (Tank). BigWigs: `BigWigsLoader.RegisterMessage(owner, …)` `BigWigs_StartBar (module, key, text, seconds, icon, isApprox, …)`, `BigWigs_StopBar/StopBars/PauseBar/ResumeBar (module, text)`. With a boss mod as the source the game's timeline contributes only script events (SuuUI's pull), and the boss mod's own pull bar is skipped. Both support Forever (TOC 16001; DBM detects `WOW_PROJECT_CAMELOT`); whether their boss timers fire on Forever (combat log access) is to be seen.
- **Built, readiness (2026-10-12, not yet confirmed in game):** `UI.Readiness` and the Readiness module (Insights › Readiness: Show In a dungeon or raid / In any group / Always / Off; top right 300px down): your own big cooldowns read out of combat (Rebirth, Innervate, Tranquility; Mana Tide Totem, Reincarnation; Shield Wall, Last Stand, Challenging Shout; Lay on Hands, Divine Intervention, Blessing of Protection; Power Infusion; Evocation, Ice Block), shared as `RDY\t<id>:<seconds>,…` on prefix `SuuUI` (on cooldown changes, a 2s debounce; on roster changes with an `RDYQ` asking the others; a 30s heartbeat), the others' kept and counting down; rows ready first; Ready check (`DoReadyCheck`) for the leader or an assistant; hidden in combat and from ENCOUNTER_START to ENCOUNTER_END; `/suu ready` prints who shared and the last send result (outgoing addon messages read as restricted in the solo probe: to check in a group).
- **Built, timeline (2026-10-12, not yet confirmed in game):** `UI.EncounterTimeline` (track and list) and the Encounter timeline module (Insights › Timeline: Show Timeline / List / Off, a test button, the pull countdown's length and a start button; top centre 28px down, hidden while empty; events read from `C_EncounterTimeline` (Active or Paused, readable time), badges from the icon mask (Tank, Lethal, Healer, Dispel, Enrage; the bit layout unverified)). The pull countdown: `/suu pull [seconds]` (default 10, 0 cancels), a "Pull" script event plus "Pull in N" and "Pull!" alerts (allowed out of combat; setting Alert: Whole countdown / Last 10 seconds / Off), started through Blizzard's own countdown (`C_PartyInfo.DoCountdown`; `START_PLAYER_COUNTDOWN`/`CANCEL_PLAYER_COUNTDOWN`), the way current DBM and BigWigs do it (read from their sources, 2026-10-12: neither sends a pull message of its own any more), so countdowns from SuuUI, DBM, BigWigs or `/countdown` all show, and SuuUI's shows in theirs; Blizzard's TimerTracker numbers kept away while SuuUI's alert counts (as BigWigs does); on a client without `DoCountdown`, SuuUI's own message (prefix `SuuUI`, `PULL\t<n>`) from the leader or an assistant (anyone in a party); combat cancels it. Forever has it: `START_PLAYER_COUNTDOWN(initiatedByGuid, timeRemaining, totalTime, ?, initiatedByName)` fires once, inside the `DoCountdown` call (2026-10-12).
- **Confirm:** two SuuUI clients in a group see each other's major cooldowns before a pull. The timeline shows on a boss, or stays hidden if Forever sends nothing.

> At the end of Phase 1, the scene boards Dungeon (Healer and DPS) and Raid 20 and 40 (Healer and Tank) should match a screenshot taken in game.

---

## Phase 2: World, chat and everyday play

### 2.1 Minimap, micro menu and the Jewel
- **Build:**
  - `Minimap`: round, with the gilt ring, the north marker, your arrow, group members as diamonds, the zone name above and the clock below. The ring carries the mail marker, the zoom control, and the SuuUI Jewel button that opens settings.
  - `MicroMenu` at the top left, with an `arcane` diamond on a button when there's something to act on, such as an unspent talent point.
- **Boards:** Minimap, Micro menu and XP.
- **Confirm:** clicking a minimap ping, tracking and zoom all work. Every micro button opens its window, including in combat where the client allows it.

### 2.2 Chat
- **Build:**
  - `ChatFrame` wrapping Blizzard's ScrollingMessageFrame and edit box. Don't reimplement either.
  - `chat-w` wide at the bottom left. While idle, the ground fades over `dur-slow`.
  - Chat-channel colours, quality-coloured links and the class diamond.
  - Other addons' message filters keep working.
  - Secret payloads during encounters display as-is.
- **Boards:** Chat.
- **Confirm:**
  - Whispers, channels, `/played` and level-up messages read correctly.
  - Questie-style link filters still apply.
  - Turning chat off and on keeps the input working.

### 2.3 Objective tracker
- **Build:**
  - The tracker on the world under the minimap. Quest titles take their difficulty colour, and a finished quest shows "Ready to turn in".
  - `QuestItemButton` in the margin left of the title (secure), with the in-area ring and the cooldown sweep.
  - It collapses to its header during an encounter.
- **Boards:** Objective tracker.
- **Confirm:** using a quest item from the tracker works in combat, and the tracker collapses on a boss pull.

### 2.4 Notifications
- **Build:**
  - `Notification` and `NotificationStack` at the top left under the micro menu.
  - **Requests** replace StaticPopups: invites, resurrection, summon, duel, trade, battleground entry, logout, release spirit, and delete item (type DELETE). Where the client reserves an answer for Blizzard's own button, host that button inside the notification.
  - **Until**, **sticky** and **timed** notices.
  - The order is fixed, at most five show, and only requests and conditions show in combat.
- **Boards:** Notifications, Notification stack, Settings · Notifications.
- **Confirm:** walk through every popup kind (accept a party invite, decline a duel, release spirit, delete a green item). Nothing is left stranded if SuuUI errors, because Blizzard's popup is the fallback.

### 2.5 Bags, bank and the item cache
- **Build:**
  - `Inventory`, a merged and sorted grid with search and sort.
  - The `ItemSlot` quality border, `Money`, and the "18 free of 80" count.
  - `BagsWindow`: a character picker, Bags and Bank, read-only dated copies, and "All characters" search.
  - At a banker, the bank and bags open side by side.
  - The item cache is pruned at logout, and "Forget character" is available.
  - Updates are coalesced on `BAG_UPDATE_DELAYED`, and the windows are skipped while hidden.
- **Boards:** Bags, Bank, Bags window; scene At the bank.
- **Confirm:**
  - Selling, splitting, dragging into the bank and using items all work.
  - Another character's bags open from anywhere, marked with their age.
  - Sell Junk sells only grey items, re-checking each slot before it sells.

### 2.6 Loot and loot rolls
- **Build:**
  - `LootWindow` beside the cursor.
  - `LootRoll` as request notifications: Need, Greed or Pass, vote counts with names on hover, and a drain line that turns `amber` under 10s. The result follows as a timed note.
- **Boards:** Loot window and loot rolls.
- **Confirm:** solo looting and auto-loot work, and a group roll shows its votes.

### 2.7 Tooltips
- **Build:**
  - Restyle Blizzard's tooltips with `TooltipDataProcessor` (the 12.1 way): `surface` with a gilt hairline, item names in their quality colour, and the unit's reaction or class.
  - The hover aura list for raid units.
- **Boards:** Tooltips.
- **Confirm:** items, spells, units and the compare tooltips all look right, with no taint when hovering action buttons in combat.

### 2.8 Campsite strip
- **Build:**
  - `Campsite` under your buffs while a fire is near. It reads from your auras and your item cooldowns.
  - Fires you pass are remembered for the map.
- **Boards:** Campfire strip.
- **Confirm:** walking up to a campfire shows the strip, and it leaves once you're out of range.

> At the end of Phase 2, the scenes At the bank and Busiest real moment match a screenshot taken in game.

---

## Phase 3: Blizzard windows, reskinned

Each step restyles Blizzard's own frames inside the `WindowFrame` shell. Keybinds, tabs and secure actions keep working, and nothing is touched in combat.

### 3.1 Window shell, Character and its tabs
- **Build:**
  - The shared `WindowFrame` skinning helper: the Jewel, the `header` title, the `kbd` chip, close, tabs at the top, and the panel-position rules.
  - Character (C) with `CharacterSheet` and `StatList`; then Reputation (U), Currency, Player vs. Player (H), Skills and Statistics.
- **Boards:** Character, Reputation, Currency, Player vs. Player, Statistics, Window frame.
- **Confirm:** equipping, equipment sets and the HD/SD model toggle work, and the watched reputation drives the XP bar.

### 3.2 Spellbook, Talents and Legacy
- **Build:**
  - `Spellbook`, including unlearned spells with their trainer cost.
  - `TalentTree` and `TalentNode`: planned points in `arcane` until Apply, Undo, and dual-spec tabs.
  - `LegacyTalents`: Tree, Challenges and Reward track.
- **Boards:** Spellbook, Talents, Talent nodes, Legacy · Tree, Legacy · Challenges, Legacy · Reward track.
- **Confirm:** dragging a spell to a bar works. Planning and applying talents works, and switching specs works.

### 3.3 Professions
- **Build:**
  - `ProfessionsWindow` at 720 × 600: the overview, plus a crafting page with recipe search and filters, the schematic, Create and Create all.
- **Boards:** Professions · Overview, Professions · Alchemy.
- **Confirm:** crafting one item, crafting all and tracking a recipe all work.

### 3.4 Social, Guild and Group Finder
- **Build:** `SocialWindow` (Friends and Raid), `GuildWindow` (Chat, Roster and Info) and `GroupFinder` (Browse and List).
- **Boards:** Group Finder; the SocialWindow and GuildWindow component pages.
- **Confirm:** the following all work:
  - whisper a friend
  - list yourself in the finder
  - invite a player who is listed alone
  - edit a guild note as your rank allows

### 3.5 World map and map pins
- **Build:**
  - `WorldMap` with the quest log on the right.
  - `MapPin` types: pick-up, turn-in, objective areas, places and group members.
  - `FilterMenu` with a reset dot.
  - Your own marks, saved per character and postable to party chat.
  - Coordinates in the status line.
  - Campfires found in 2.8.
- **Boards:** World map, Map pins.
- **Confirm:**
  - Clicking a quest highlights its pins.
  - Adding, naming, deleting and posting a mark works.
  - Marks also show on the minimap.

### 3.6 Remaining windows
- **Build:** the quest log, mail, merchant, trainer, auction house and collections, all in the shell, built from `ItemSlot` rows, `Money`, `TextField` and `Select`.
- **Confirm:** you can buy, sell, buy back, mail an item, and post and buy an auction.

---

## Phase 4: Configuration depth and hardening

### 4.1 Density and accessibility presets
- **Build:**
  - Density presets: Minimal, Standard and Raid lead.
  - Colour-blind presets that swap the signal set.
  - A reduced-motion toggle.
  - A UI-scale check at 1080p, 1440p and 4K, to confirm each cluster keeps its anchor.
- **Confirm:** switching presets resizes the HUD together in one step, with no reload and no taint.

### 4.2 Performance and taint pass
- **Build:**
  - Frame-count and SetPoint budgets, checked with `/suu perf`.
  - An in-game `/suu perf` command showing CPU and memory per module.
  - A full `taintLog` raid session.
  - A check that SavedVariables stay bounded.
- **Confirm:** a 40-player raid fight shows no blocked actions and stays within budget.

### 4.3 Plugin developer kit
- **Build:**
  - A reference for the public API: every function, message, anchor name and extension point, with the version that introduced it.
  - A plugin guide built around `Examples/SuuUI_HelloPlugin`, plus a second, fuller example that adds an element to every unit frame.
  - Once the test harness is in the project: a test that fails when a public function changes signature without an `API_VERSION` bump.
- **Confirm:** someone who hasn't seen the code can follow the guide and get a plugin with a settings section and a movable frame running.

### 4.4 Release
- **Build:** a first-run splash using the emblem, a default layout per role, the addon-list icon, the README, a CurseForge or Wago package, and a changelog.

---

## Order at a glance

| # | Increment | Depends on |
|---|---|---|
| 0.1–0.7 | Scaffold, tokens, core, module system and plugin API, primitives, settings window, edit mode | — |
| 1.1–1.4 | Player and target frames, other unit frames, cast bars and swing timer, auras | 0.x |
| 1.5–1.7 | Action bars and the Cooldown Manager | 0.x |
| 1.8–1.10 | Party, raid and nameplates | 1.1, 1.4 |
| 1.11–1.13 | Alerts, meters, timeline and readiness | 1.1 |
| 2.1–2.8 | Minimap, chat, tracker, notifications, bags, loot, tooltips and campsite | 0.x (2.6 uses 2.4) |
| 3.1–3.6 | The Blizzard windows | 0.5 (shell) |
| 4.x | Presets, performance and release | everything |

Phases 2 and 3 don't depend on Phase 1. If a different part of the UI should come first, they can be reordered.
