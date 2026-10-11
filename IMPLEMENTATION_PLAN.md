# SuuUI for WoW Forever: implementation plan

Target client: WoW Forever beta 1.60.1 (`## Interface: 16001`, game type `camelot`). It runs the 12.1 (Midnight) engine with vanilla content, so the secret-values restrictions apply.

Sources of truth:
- **Design system:** https://claude.ai/artifact/NcdJv21GMnN9gaQ5mF1oSw. It holds the brand book (`README.md`), `tokens.json`, `group-frames.md` and 70 component specs.
- **Design canvas:** https://claude.ai/artifact/2Esuzrf8QLJVm2WWGcDYfF. It has three pages: Components, Scenes and Windows and settings, 64 boards in all.
- **API reference:** EllesmereUI in this AddOns folder already runs on Forever. Read it for working examples of `issecretvalue`, `C_CurveUtil.CreateColorCurve`, `SetAlphaFromBoolean`, `C_SwingTimer`, `C_DamageMeter`, the CooldownViewer frames and `EditModeManagerFrame`.

---

## Architecture

SuuUI is written from scratch for this client. The design system is the only input besides the client's own API.

| Layer | What it is |
|---|---|
| Tokens | `Core/Tokens.lua`, generated from the design system's `tokens.json`. It is the only place colours, sizes and durations come from |
| Core services | Event bus, settings with per-character profiles, combat queue, Blizzard-frame suppression, pixel scale, error reporting |
| Primitives | Text, Panel, Icon, StatusBar, Button, glows and animation presets, laid out by an engine that invalidates and then flushes once per frame |
| Components | One Lua component per design-system component (`UnitFrame`, `AuraIcon`, `ActionButton`, …), with the same names and props |
| Modules | One per HUD area or window. Each has its own Enabled toggle, settings section and edit-mode handle |
| Tests | An offline harness with 12.1 API stubs and secret-value simulation, run under Lua 5.1 |

### Rules for every increment (definition of done)

1. **The game stays playable.** Each feature is a module with an Enabled toggle. Until a module exists, or while it's off, Blizzard's own frame is left untouched. Suppress Blizzard frames by reparenting them to a hidden frame, never with an `OnShow → Hide` hook.
2. **It loads cleanly.** No Lua errors with `/console scriptErrors 1`. `luac5.1 -p` passes on every shipped file. The test suite runs green under real Lua 5.1.
3. **It's combat-safe.** Nothing protected moves in lockdown: route those changes through the core combat queue. Run a `/console taintLog 1` session on anything secure.
4. **It respects secret values.** Never compare or do maths on a value that might be secret. Use curve objects, `SetAlphaFromBoolean` and duration objects. Where the client hides data, hide the slot.
5. **It's performant by construction.** Show and Hide are idempotent. Events use `RegisterUnitEvent`. Each widget caches the last value it painted. Views that are hidden are marked stale and refresh on Show. Lists are reconciled by key, never rebuilt.
6. **It's configurable.** Each module adds its own section to the settings window. Changes apply live and the module has an edit-mode handle.
7. **It matches the design.** Compare the result with its canvas board(s) side by side at 2560×1440 with UI scale 1, and note any deviations.
8. **It ends in a commit.** Commit with the increment number, then do the in-game confirmation below.

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

### 0.3 Core services and test harness
- **Build:**
  - An EventBus that dispatches over a snapshot, so listeners can be added or removed safely during an emit.
  - Settings and Profile (SavedVariables with per-character profiles). Watchers can veto a write before it's stored, a nested write supersedes the outer one, and table defaults are copied, never handed out.
  - Add a core **combat queue** (deduplicated, flushed on `PLAYER_REGEN_ENABLED`) and a **SuppressBlizzard(frame)** helper that reparents.
  - Add `Pixel` (perfect scale, rescaled only on uiScale changes and deferred while in combat) and `Fault` for errors players should see.
  - An offline test harness: a TOC loader, frame and anchor simulation, and 12.1 API stubs including `issecretvalue` and secret-value behaviour. It runs under Lua 5.1.5, with a pre-commit `luac5.1 -p` check.
- **Confirm:** a setting changed through `/suu set` survives `/reload` and appears under the right profile. Switching profiles works. An error deliberately thrown in a test plugin shows as one player-visible line instead of breaking the load.

### 0.4 Primitives and layout engine
- **Build:**
  - Primitives:
    - Text, with idempotent Show/Hide and cached metrics.
    - Panel (`surface`, `surface-glass`) with the gilt hairline and corner diamonds.
    - The `inset-anchor` double gilt frame.
    - Icon (8% crop, 1px state border, desaturated state).
    - StatusBar that accepts secret values, colours through a curve, and draws a ghost segment.
    - Button, Tooltip shell, and the glow effects (`glow-arcane`, `glow-ember`, `glow-ward`).
  - A layout engine that uses `Invalidate()` plus a per-frame flush, with stack, grid and anchor strategies.
  - Anchoring by cluster: positions are expressed from an edge or the centre, using the 2560×1440 reference.
  - Animation presets from the Motion table, including the reduced-motion switch.
  - **`/suu gallery`** shows all of them.
- **Boards:** Alerts and badges (StateBadge), Window frame (shell only), and the Panel, Button, ProgressBar and SectionHeader component pages.
- **Confirm:** the gallery matches the component previews. Dragging a resizable gallery panel stays smooth, and the debug counter shows SetPoint calls per frame staying flat.

### 0.5 Settings window and edit mode
- **Build:**
  - `SettingsWindow` with nav sections and search.
  - Every control: Toggle, Checkbox, Segmented, Select (single and multiple), Slider, Stepper, ColorPicker, KeybindField, AnchorPicker, ListEditor and FilterMenu.
  - `SettingRow` and `SettingsGroup`, with the changed-row diamond, a reset arrow and a disabled-with-reason state.
  - Profiles with Import/Export.
  - Edit mode: EditModeFrame handles on a snap grid, mutually exclusive with keybind mode and closed on `PLAYER_REGEN_DISABLED`.
  - Opened from `/suu` and the game menu. The minimap Jewel comes in 2.1.
- **Boards:** Settings window, Settings controls, Select and filter menus, Setting rows and groups, Edit mode.
- **Confirm:**
  - Every control works and changes apply instantly.
  - Reset works per row, per section and for everything.
  - An exported profile string, imported on a second character, reproduces the settings.
  - Entering combat closes edit mode cleanly.

> At the end of Phase 0 nothing on the HUD has changed yet, but every later module plugs into tokens, settings, edit mode and the combat queue.

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

### 1.3 Cast bars and swing timer
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
  - `AuraIcon` driven by `C_UnitAuras` and duration objects, with drain lines, stack counts, the expiry blink under 3s and the dispel-type border.
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
  - Frame-count and SetPoint budgets added to the test suite.
  - An in-game `/suu perf` command showing CPU and memory per module.
  - A full `taintLog` raid session.
  - A check that SavedVariables stay bounded.
- **Confirm:** a 40-player raid fight shows no blocked actions and stays within budget.

### 4.3 Release
- **Build:** a first-run splash using the emblem, a default layout per role, the addon-list icon, the README, a CurseForge or Wago package, and a changelog.

---

## Order at a glance

| # | Increment | Depends on |
|---|---|---|
| 0.1–0.5 | Scaffold, tokens, core, primitives, settings and edit mode | — |
| 1.1–1.4 | Player and target frames, other unit frames, cast bars and swing timer, auras | 0.x |
| 1.5–1.7 | Action bars and the Cooldown Manager | 0.x |
| 1.8–1.10 | Party, raid and nameplates | 1.1, 1.4 |
| 1.11–1.13 | Alerts, meters, timeline and readiness | 1.1 |
| 2.1–2.8 | Minimap, chat, tracker, notifications, bags, loot, tooltips and campsite | 0.x (2.6 uses 2.4) |
| 3.1–3.6 | The Blizzard windows | 0.4 (shell) |
| 4.x | Presets, performance and release | everything |

Phases 2 and 3 don't depend on Phase 1. If a different part of the UI should come first, they can be reordered.
