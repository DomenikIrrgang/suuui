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
| Your own cooldowns | Spell 29515 (Forever's global cooldown reference) is readable out of combat; 61304 doesn't exist here. **In dungeon combat, `startTime`, `duration` and `modRate` are secret, but `isActive` and `isEnabled` stay readable**, for the GCD and for action-bar slots alike. Each action's cooldown duration object is readable | Swipes and timers come from the duration objects (`SetCooldownFromDurationObject`). "Ready" is `not isActive` (readable), so the interrupt glyph, desaturate-until-ready and the Cooldown Manager's ready flash work as designed. Remaining seconds as text need a secret-safe formatter, as auras use |
| Swing timer | `C_SwingTimer` (2 functions), `Enum.PlayerSwingType`, `Blizzard_SwingTimer` loaded | As designed |
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
  - Interruptibility drawn through `SetAlphaFromBoolean`, with the lock glyph for casts that can't be interrupted.
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
  - **Decision for this step:** either SuuUI's own secure buttons or restyling Blizzard's Edit Mode bars. Prototype both on bar 1 and choose based on taint and paging behaviour on Forever. Own buttons are the default because the design needs grouping.
  - `ActionButton` (`action`, 20px): cooldown swipes from duration objects, range and usability, keybind text, macro names off, the `arcane` ready pop, and the dispel diamond.
  - Bar 1 pages by stance and form with Forever's paging strings, and names the page under the bar ("Defensive Stance").
  - The dock layout is 538 × 42 px. Every key bound to a button fires it, not only the first.
- **Boards:** Action bars.
- **Confirm:**
  - Warrior stance swaps, druid forms and rogue stealth all page bar 1.
  - Changing a theme or setting doesn't reset paging.
  - Dragging spells onto buttons works, and so do second keybinds.
  - No ADDON_ACTION_BLOCKED in combat.

### 1.6 Bars 5–8, stance, pet, grouping and keybind mode
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

### 1.7 Cooldown Manager
- **Build:**
  - Restyle Blizzard's CooldownViewer icons into `CooldownManager`:
    - tracked buffs on top, then a divider, then your debuffs on the target
    - the Essential row at `cdm-essential` and the Utility row at `icon-lg`
    - cooldowns desaturated until ready, then an arcane flash
    - the healer variant puts Utility at the right end of Essential
  - The settings section `CooldownLists` is saved and applied on reload, with a "Reload now" button. Never edit the manager's lists live.
- **Boards:** Cooldown Manager, Cooldown lists.
- **Confirm:**
  - The icons follow the centre stack.
  - A cooldown coming ready pops.
  - Changing the lists and reloading applies the change, and auras still read afterwards.

### 1.8 Party frames (5-player profiles)
- **Build:**
  - `GroupFrames` on SecureGroupHeaderTemplate, with profile selection by role and group size. Role comes from the assigned role, else from talents. The profile switches only out of combat.
  - Healer · 5: centred under the cast bar, with the low-health tint, state badges and dispels you can remove.
  - Tank and DPS · 5: bottom left above the chat, with four auras.
  - Ordering in the aura slot: dispellable debuff, then defensive or external, then shield, then your HoTs, then others' HoTs.
  - Your current target in the group shows as `selected`.
  - Hide Blizzard's party frames.
- **Boards:** Party frames, Group frame profiles (5); scenes Dungeon boss · Healer and Dungeon boss · DPS.
- **Confirm:**
  - In a dungeon as a healer, the grid sits between the player and target frames, with tops level.
  - A curse you can remove badges and borders the unit.
  - Swapping your spec's role between pulls switches the profile, and the profile never switches mid-fight.

### 1.9 Raid frames (10, 20 and 40)
- **Build:**
  - The remaining six profiles from `group-frames.md`:
    - healer rows of five, 20px tall at 40 players
    - side columns at `side-w`; four columns are exactly `chat-w`
    - 40 players in two bands
  - Badges at the right end of the bar, at most two inline icons, and the full aura list on hover.
  - Per-profile settings under Party & raid, using a Segmented to pick the role and size being edited.
- **Boards:** Group frame profiles; scenes Raid boss 20 · Healer, 20 · Tank, 40 · Healer, 40 · Tank.
- **Confirm:**
  - Test in a raid or with `/suu testgroup 20|40`, which builds fake headers out of combat. Fake data can't be secret, so check the real thing in a raid as well.
  - The 40-player healer grid clears the dock.

### 1.10 Nameplates
- **Build:**
  - Restyle Blizzard's nameplate unit frames into `Nameplate` (`nameplate-w`):
    - up to four of your debuffs above
    - the name in its reaction colour, with health % at the right
    - the `cast-plate` cast bar, carrying the interrupt state
    - threat borders and badges ("Aggro", "Losing") from `UnitThreatSituation`
    - your target in `ink` at full opacity, and the rest at `opacity-plate`
- **Boards:** Nameplates.
- **Confirm:**
  - Pull a pack as DPS: the mob on you shows "Aggro" in `danger`.
  - Tanking, a mob you are about to lose shows "Losing".
  - Plates still update inside a dungeon.

### 1.11 Alerts, threat meter and the pull warning
- **Build:**
  - The `Alert` system: centred, about 270px down, short-lived, and present only in combat.
  - `ThreatMeter` beside the damage-meter slot. It sorts by % on ordinary mobs and by state on bosses, and shows only in combat with a hostile target.
  - The "You're about to pull" alert, with your threat drop if it's ready.
- **Boards:** Threat meter, Alerts and badges.
- **Confirm:**
  - Overtaking the tank on a trash mob raises the alert.
  - On a boss, the rows are ordered by state with no errors from secret values.

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
- **Confirm:** the numbers match Blizzard's own meter for the same fight, and the threat meter is exactly as tall as the damage meter.

### 1.13 Encounter timeline and readiness
- **Build:**
  - `EncounterTimeline` at top centre (`timeline-w`): ability icons ride toward now, timers turn `amber` under 5s, with "Tank" and "Spread" badges. It hides when no data arrives, depending on the result of 0.1's probe.
  - `Readiness`: cooldowns shared through addon messages between pulls, with a Ready check button for the leader. It hides on pull and returns after `ENCOUNTER_END`.
- **Boards:** Encounter timeline, Insight · Readiness.
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
