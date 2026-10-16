# Changelog

## Unreleased

### New

- **Merchant window** in SuuUI's look: the goods as one scrolling list (with a scrollbar) under a search and the game's filter that stay on top; a quantity to buy for each item (in items, bought in the merchant's stack sizes, capped at what's left and what you can afford; it starts at one purchase at every vendor); "You have N"; what you already know greyed with "✓ Known"; the item you sold last with Undo; Buy back; Repair all, repair one item, guild repair and Sell junk with what it brings; the merchant's currencies.
- **Mail window** in SuuUI's look (first version, to test): the whole inbox as one list with the open mail beside it (an auction invoice's lines, the attachments to take, money, cash on delivery to pay after a question), Collect all and Collect money (cash-on-delivery mails stay for you), Reply, Return, Delete; Send with attachments, money or cash on delivery and the postage, and suggestions in To (your characters on this realm and side, the people you mailed lately, and your guild: up to 30 members, online first, narrowed to the names that match as you type); Sent: the last 50 mails this character sent.
- `/suu probe ahscan` (at the auction house) checks whether the full scan works on Forever.

### Changed

- Party and raid frames: debuffs follow right after the defensives that show (party: beside the bar; raid: at the bar's right end) instead of waiting behind empty defensive slots.
- Party and raid frames show every debuff after the ones you can remove (Forbearance on you didn't show), not only the ones the game marks for raids.

### Fixed

- Invite to guild in the Guild window works (the game blocked it: it takes a guild invite only from a click, which the Invite button now is; Enter in the name field leaves the dialog open).
- The target frame shows another player's debuffs once (they showed twice, as their buffs did). With Target's debuffs on Everyone's they're one list.
- Party and raid frames show another player's debuffs once (they showed twice: the game hides who cast them). Your own frame keeps the ones you can remove first.

## 0.4.0-beta.5 (2026-10-16)

### New

- **Defensives** (Settings › Frames › Defensives): the buffs party and raid frames count as defensives, as a list you can change. The game doesn't tell which of another player's buffs are defensives (so any buff showed in those slots), so SuuUI goes by the list: Externals (Blessing of Protection, Power Word: Shield…) and Defensives (Shield Wall, Ice Block, Evasion…), each with every rank, Kind, Warded and on/off; add any spell by name or ID, or reset to SuuUI's list. It works in combat too.
- **Warded** on party and raid frames: while a spell on the list with Warded on is up (Shield Wall, Divine Shield, Blessing of Protection…), the frame shows the Warded badge and a pale gold border. It covers Aggro (the red glow stays); a debuff you can remove covers it.
- `/suu probe partyauras` lists what each aura filter gives, as the aura frames take it.
- **Plugin API 0.16** (`Docs/API.md`): the Defensives list for group frames (`SuuUI.UI.GroupDefensives`, `SetGroupDefensives`), Warded on unit frames, and aura groups' `exclude` and `harmfulEdge`.

### Changed

- **Buffs and debuffs apart:**
  - **Target:** one line above the frame, its buffs from the left edge and its debuffs from the right edge, yours first on each side. A side wraps upward once it fills half the frame.
  - **Focus:** the same, with its buffs (up to 4, anyone's) and your debuffs (up to 8).
  - **Party frames:** beside each bar, defensives, a gap, then debuffs (the ones you can remove first). Aura icons and Show buffs became Defensive icons (2) and Debuff icons (3); other buffs show through Buff indicators.
  - **Raid frames:** inside the bar's right end, defensives, a small gap, then debuffs at the very end. Aura icons became Defensive icons (1) and Debuff icons (2).
- Every debuff has a red edge (its type's colour when it has one): on the target and focus, your debuffs, bosses, party and raid frames and nameplates.

### Fixed

- The target frame shows a friendly target's buffs once (another player's buffs showed twice: the game hides who cast them). With Target's buffs on Everyone's they're one list; Only yours is as before.
- Party and raid frames show a buff once (another player's buffs showed in both the external and the defensive slot, whatever they were) and only real defensives there, by the Defensives list.

## 0.4.0-beta.4 (2026-10-16)

### Changed

- A Battle.net friend coming online on your realm and in your faction gets an Invite button on their note (also when their character arrives a moment after the note). The Social window invites them only then too, and says why not otherwise.
- The aggro alerts ("You have drawn aggro", "You're about to pull") show in a group only when someone there holds the mobs: a tank or a pet. Two damage dealers questing together get none. Settings › Threat meter › In the open world turns them off outside dungeons, raids and battlegrounds.

### Fixed

- Notes for friends, Battle.net friends and guild members coming online and going offline appear (none did; the game's own lines were hidden all the same).
- Inviting a Battle.net friend from the Social window or their online note works (it said the player couldn't be found).
- The spellbook no longer shows Elemental twice for shamans (and Shadow twice for priests), once empty with a question mark.

## 0.4.0-beta.3 (2026-10-16)

### Fixed

- Quest markers on the world map and in its quest log show on characters where the game's Quest objectives was off (newer characters had it off, so no quest showed where to go): SuuUI turns it on once per character; Map filters › Quests › Quest objectives switches it after that.

## 0.4.0-beta.2 (2026-10-16)

### New

- `/suu probe windows` for checking what the mail, merchant, trainer, auction house and collections windows report.

### Changed

- Money leaves out zero coins at the end: "38g 50s" instead of "38g 50s 0c".

### Fixed

- Skyborne characters see the quests they can pick up on the world map (none showed that is limited by race or faction).

## 0.4.0-beta.1 (2026-10-16)

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
  - **Your quests' markers** in SuuUI's look: in progress (three dots), ready to hand in ("?" in arcane, glowing), the next step on another map (a pointer, dashed edge); the one you follow larger and ringed; the quest log's markers in the same look. Clicks, tooltips and following stay the game's.
  - **Holidays:** a holiday's quests and vendors show only while it's on, by the game's calendar; the Darkmoon Faire only at the site it's at.
  - **Map filters** in the header choose what shows, in groups (Quests, Places, Services, Trading, Trainers, Rares and treasures). Quests also has the game's quest log options: Quest levels ("[15]" before a title) and Difficulty colours.
  - Pins of a kind close together merge with a count (a click zooms in). Zoomed all the way in, every pin sits on its exact spot, a little larger.
  - Settings › World map › Pin opacity makes the pins more see-through (100% by default).
- **Enlarged map:** the map opens enlarged in the middle of the screen (the maximize button, instead of the game's fullscreen; − makes it small, remembered), the quest log beside it as you left it and the world around it still seen and clickable. Settings › World map › Enlarged map sets its size (80% of the screen's height by default).
- **Map marks:** your own marks on the map. Ctrl+click the world map to place one, name it and give it one of eight symbols like the raid markers. A mark can show you the way (the game's navigation arrow) and be posted to your group: a chat line with the game's map pin link anyone can click, and SuuUI players get the mark itself on their map and minimap. Marks show on the minimap too, those further away on its edge pointing their way. Map filters › Marks.
- `/suu probe calendar`, `/suu probe proficons`, `/suu probe marks` and `/suu probe givers` (quest givers checked against the map) for checking what the game reports.
- **Plugin API 0.15** (`Docs/API.md`): map pins (`SuuUI.UI.MapPin`), the map's data (`SuuUI.QuestStarts`, `MapPlaces`, `MapOverlays`, `InstanceLevels`), your map marks (`SuuUI.GetModule("marks")`), `SkinWindow`'s `headExtra` and `rowMid`, and a disabled `UI.Button` showing its tooltip.

### Changed

- **New defaults** (settings you changed keep your values; those you never changed take the new ones):
  - action bar buttons 24px with larger key text, empty slots shown;
  - nameplates a little larger;
  - party and raid frames mark low health and fade to 25% out of range; raid frames 19px tall, 8px apart, with one aura;
  - the damage meter in class colours with 9 rows; threat in raw values, always shown; readiness off;
  - the spellbook lists spells still to train; Collections in the micro menu; the bag bar shows on mouseover;
  - edit mode snaps to a 4px grid; the beta's issue reporter is hidden; your group finder ad posts in General;
  - new places for the bags, tooltips, bag bar and action bar 5;
  - buff indicators per druid spec, and a missing Battle Shout for Protection warriors.
- The damaged-gear notes show an anvil instead of a hammer.

### Fixed

- Tooltip titles and subtitles longer than the tooltip wrap inside it instead of running past its edge.

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
