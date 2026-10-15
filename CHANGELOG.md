# Changelog

## Unreleased

### New

- **World map** in SuuUI's look: a header with Continent › Zone, the map right under it, the quest log restyled beside it.
- **Map pins**: what's around you, on the map.
  - **Quests to pick up:** a "!" where each quest you can take now is given, in its difficulty colour by the original game's rule. A quest shows only when you can really take it: your level, race and class, the quests before it, its profession skill and reputation. Its card names the giver and their other quests. Repeatable quests are blue.
  - **Quests from items:** a "!" where the mobs or objects live that drop an item starting a quest.
  - **Hover a quest** and every pin of it is ringed while the rest fade. A quest giver who walks a route has the route drawn on the map ("Warcaller Gorlach walks round Orgrimmar").
  - **Dungeons and raids:** a slowly turning swirl at each entrance (raids with a second ring), with the recommended levels on its card, each wing's too (Scarlet Monastery's Graveyard 30–38 …). Battlegrounds with crossed swords.
  - **Places:** flight masters, campfires you found, innkeepers, repair, mailboxes, vendors, trainers (your class's, professions' drawn after the game's icons, weapon masters, riding), bankers, auctioneers and more.
  - **Rares** at every spot they spawn at: hover one and all its spots are ringed; a rare who walks has its route drawn. Treasure chests too.
  - **Unexplored areas** drawn tinted where the game would show them once explored.
  - **Holidays:** a holiday's quests and vendors show only while it's on, by the game's calendar; the Darkmoon Faire only at the site it's at.
  - **Map filters** in the header choose what shows, in groups (Quests, Places, Services, Trading, Trainers, Rares and treasures).
  - Pins of a kind close together merge with a count (a click zooms in). Zoomed all the way in, every pin sits on its exact spot, a little larger.
- `/suu probe calendar` and `/suu probe proficons` for checking what the game reports.

## 0.3.0-beta.1 (2026-10-15)

### New

- **Group Finder** (I): Forever's group finder rebuilt in SuuUI's look.
  - **Browse:** one list of groups and players looking for groups, from the game's group finder and from public chat (LookingForGroup, General, Trade, Say), with where each was seen and how long ago. Each group shows what it has (its members' roles, greyed) and what it still needs, your role highlighted, and its size ("3/5"). Filter by category, activity or text, or show only what fits your level and roles. Whatever concerns you comes first and is highlighted, for example a group for what you're listed for that needs your role, or one for a quest in your log. Whisper or invite right from the list. Opening the window searches the game's group finder; Refresh searches again.
  - **Chat in three languages:** English, Korean and Chinese posts are read, so groups posted in any of them join the list. SuuUI joins LookingForGroup for this and keeps it out of your chat windows.
  - **List yourself:** the game's own listing panel, in SuuUI's look.
  - **My listing:** while you're listed, your listing with Delist and Update, and an ad for chat written from your listing that you can edit and post with a click (LookingForGroup, General, Trade, Say or Yell).
  - **Who:** search who's online with the game's class, race and zone filters and its sort order; add a friend, whisper or invite.
  - **Notes:** a group for what you're listed for that needs your role, a new group for it, a player for your group, a group for a quest in your log or in your zone, friends and guild members looking, groups you whispered (posted again, full or gone), stale results (Refresh, Delist), your listing running out (Delist, Open listing) and ending. They wait while you fight or are in a dungeon. `/suu lfgnotes` shows one of each.
  - **Settings › Group Finder** (also the gear in the window's header): the chat channels read, joining LookingForGroup, how long chat posts stay, the languages read, your ad's channel, and each kind of note on or off with its options (sound, tool or chat, how sure, in combat, in instances).
- **Group invites that ask for your role** come as a notification card with the role choices on it.
- **Talents window:** your talents in a window of their own (N, or the micro menu), the three trees side by side with the game's own talent tooltips. Points are planned until you press Apply. A note tells you when you have talent points to spend.
- **Legacy window** in SuuUI's look:
  - your points, the three trees, and challenges by category, each with its full list;
  - the reward track along the window's foot.
  The micro menu marks the Legacy button, and a note appears, while you have Legacy points to spend.
- **Professions window:**
  - your professions at a glance, unlearned ones too;
  - unlearning, after typing UNLEARN to confirm;
  - dragging a profession's spells (Disenchant, Smelting) onto your bars;
  - recipe lists with grouped filters and sorting;
  - where a recipe you don't know yet is learned;
  - linking a profession or a recipe in chat.
- **Tracked recipes** in the objective tracker, under your quests. A click opens the recipe.
- **Social window:**
  - your friends, with your BattleTag and status at the top;
  - recent allies, with pins and notes;
  - friend requests, and ignoring players;
  - raid groups where you drag members from group to group;
  - your raid lockouts.
- **Friends and guild members coming online** (and going offline) as notes, with Whisper and Invite.
- **Guild window:**
  - guild chat with the message of the day on top;
  - a roster with a class column and each member's details;
  - guild and officer notes edited with one click;
  - promote, demote and remove;
  - the guild information and the guild log;
  - guild settings: ranks, permissions, bank tabs and the Discord link.
- **Right-click menus** in SuuUI's look. The game's dropdown menus, their submenus and popups are restyled while they show.

### Changed

- Notes now hide while an open window covers them. Requests (popups, loot rolls) stay on top.
- The Talents and Legacy windows open in the middle of the screen, side by side.
- Loot rolls, readiness and the timeline recognise players by their whole name, since Forever's characters have surnames.

### Fixed

- Opening Edit Mode with SuuUI's XP bar on no longer raises a Lua error (`StatusTrackingManager.lua:228`).
- After a `/reload` in combat, buffs, the Cooldown Manager and other modules that don't need secure frames now start at once, instead of waiting for the fight to end.
- The spellbook opened in combat shows SuuUI's page.
- Stance and pet buttons no longer cause an error when a cooldown sweep ends.
- The Character window no longer causes errors in combat.
- The spellbook no longer lists a stance twice (from a flyout).
- Popups hosted in the notification stack (the death popup) keep their buttons side by side.
- Add friend in a chat name's right-click menu sends a friend request; it did nothing, since Forever's classic friends list is switched off.

## 0.2.0-beta.2 (2026-10-13)

### Changed

- SuuUI is now on **Wago Addons** too. The addon itself is unchanged since 0.2.0-beta.1.

## 0.2.0-beta.1 (2026-10-13)

The first public beta of SuuUI: a full interface replacement for WoW Forever.

### New

- **Unit frames:** player, target, target of target, focus, pet and boss frames, with health text options, incoming heals and absorbs, debuff-type borders, raid markers, reaction colours and detachable resource bars.
- **Party and raid frames** for 5 to 40 players, with real-size previews in the settings, removable debuffs by type, aggro, range fading and role sorting; **buff indicators** per class and spec.
- **Nameplates** with your debuffs, threat, casts with interrupt state, quest objectives and raid markers.
- **Cast bars and a swing timer**, including interruptible casts of your target, focus and bosses.
- **Action bars** 1–8, stance and pet bars, visibility rules and a hover-and-press keybind mode.
- **Cooldown Manager** with ready-made presets for every class and spec, buff reminders, sounds and conditions.
- **Alerts** for threat and aggro, a **threat meter**, a **pull countdown**, a **damage meter**, an **encounter timeline** that can take boss timers from DBM or BigWigs, and a **readiness** check.
- **Chat** with tabs, message categories, a global panel, conversations and a cleaner input field.
- **Bags** with sorting, an all-characters search and selling junk at a vendor.
- **Spellbook** with cooldowns on its spells and the spells you can train, plus a **talent picker** and a **level-up card** that shows the new spells.
- **Character window**, **minimap**, **objective tracker**, **micro menu**, **loot rolls**, **tooltips** and **notifications** (repairs, full bags, ready checks, battlegrounds) in SuuUI's look, and alerts for Campfire's camp benefits.
- **Settings window** with search and live changes, **edit mode** on a snap grid, and **profiles** that switch by role, with import and export.
- **Plugins:** every module uses the same public API that plugins can use (`Docs/API.md`).
