# Changelog

## Unreleased

### Changed

- Micro menu: Collections has a horse head for its icon.
- Micro menu: the free bag slots on the Bags button sit in a small badge on its corner, larger and easier to read (an ember badge when none are free). Settings › Micro menu › Free bag slots turns it off.
- Chat: a right click on a tab opens Blizzard's chat settings for that window (whisper tabs still close with a right click).
- Plugin API 0.17: `SetCount` on the micro menu takes the badge's fill colour too.

### Fixed

- Reputation: a faction's bar sometimes showed only a sliver though its figures were right (3,210 / 6,000 as a sliver); the bars fill to their value again.
- Skills: the bars (professions, secondary and weapon skills) were empty; they fill to the skill's level again, in blue.

## 0.5.0-beta.4 (2026-10-18)

### Changed

- Totem bar: Totemic Recall is its own button at the right end, after Call of the Elements, shown once you know it and faded while no totem is down (it was a small cross that showed only with a totem down).
- Totem bar: a slot's time left shows only for the totem its button casts. Choose another totem for the slot while the old one is still down and the old one's time goes away; it comes back when you put the new one down.

## 0.5.0-beta.3 (2026-10-18)

### New

- **Welcome** (the first time you log in with SuuUI, once per account): three short steps to pick your role layout (Tank, Healer, DPS or keep yours: SuuTank, SuuHeal or SuuDps for this character), colour vision, and where settings, edit mode, keybind mode and the modules are. Skip changes nothing. `/suu welcome` or Settings › General › Welcome shows it again.
- SuuUI's emblem as its icon in the game's AddOns list.
- The micro menu's Bags button shows how many bag slots are free (in ember when none are).
- A quest you accept goes on the objective tracker at once (Settings › Objective tracker › Track accepted quests).
- Trainer: **Train all** learns everything you can learn and afford in one go (after a question with the total; a new profession still asks on its own).
- Nameplates: a switch to turn all nameplates off, enemies' and friends' (Settings › Nameplates).
- Chat: players' names in their class colour (Settings › Chat › Names in class colour).
- Levels in their difficulty colours (grey, green, yellow, orange, red, as the game rates them): after the name on the target, focus and boss frames, on unit tooltips' level line, and on nameplates before the name (after a quest mark; "25+" for elites, "??" for bosses; Settings › Nameplates › Level).
- World map (to test): quest givers' "!" in gilt with a ring in the quest's difficulty colour, split into arcs for a giver with several quests (easiest to hardest), and a small bar under a group quest (where the game marks it as one; an arcane bar under a group quest to turn in).
- Nameplates for friendly NPCs (guards, vendors, quest givers) in the open world, in SuuUI's look (Settings › Nameplates › Friendly NPCs).
- Plugin API 0.17: `SuuUI.ApplyRolePreset`, `RolePresetName`, `ColorVision`, `SetColorVision`, `ColorVisionModes`, `ColorVisionColor`, `AccountData` (a module's table for the whole account), `ShowWelcome`, a micro menu button's count (`SetCount`), `SuuUI.UI.LevelColor(level)`, and map pins' `outline`, `arcs` and `bar`.

### Changed

- The game's own level-up toast no longer shows while SuuUI's level-up card is on.
- The level-up card fades out when it goes, instead of vanishing.
- Exit Game in the game menu asks first.
- Someone who is both in your guild (or a friend) and your Battle.net friend gets one online or offline card, the Battle.net one, instead of two.
- A spell the game puts on your bars by itself (one you just learned) no longer flies to where Blizzard's hidden bars would be: SuuUI's button that holds it pops and flashes instead.

### Fixed

- Inviting a Battle.net friend no longer fails for "another realm": on Forever realms are rulesets, so only the game and side are checked.
- No threat warnings or Aggro badges for enemy players' pets and totems, anywhere (seen in a battleground and the open world): only NPCs have threat.

## 0.5.0-beta.2 (2026-10-18)

### New

- **Totem bar** for shamans (to test), in the stance bar's place: your earth, fire, water and air totems as buttons that cast the totem chosen for each, in combat too, with a thin strip above them showing each totem's time left and drain (amber near the end). Right click dismisses a totem; the arrow on a hovered totem opens the list of that element's totems to choose another. Totemic Recall sits at the strip's end while a totem is down, Call of the Elements after the four once learned, Ghost Wolf on the right. With more than one summon spell (Call of the Elements, of the Ancestors, of the Spirits) the arrow under the Call button switches between their sets, each with its own four totems (remembered per character). An element with no totem yet is dashed. Settings › Action bars › Totem bar; the game's own totem bar comes back after a reload when it's off.
- Plugin API 0.17: `SuuUI.UI.TotemBar` and `SuuUI.UI.DurationTextBinding` (a text line the game keeps showing a duration's time left, in combat too).

### Changed

- Action bars 5–8 start hidden on a new character, as the design has them, even when the game put things on them (a new character's bar 5 showed with its starting items). Turn them on under Settings › Action bars.
- The game's "Your inventory is full" notice (items it couldn't give you, such as the authenticator's bag bonus) comes as a notification card too.

## 0.5.0-beta.1 (2026-10-18)

### New

- **Merchant window** in SuuUI's look: the goods as one scrolling list (with a scrollbar) under a search and the game's filter that stay on top; a quantity to buy for each item (in items, bought in the merchant's stack sizes, capped at what's left and what you can afford; it starts at one purchase at every vendor); "You have N"; what you already know greyed with "✓ Known"; the item you sold last with Undo; Buy back; Repair all, repair one item, guild repair and Sell junk with what it brings; the merchant's currencies.
- **Mail window** in SuuUI's look (first version, to test): the whole inbox as one list with the open mail beside it (an auction invoice's lines, the attachments to take, money, cash on delivery to pay after a question), Collect all and Collect money (cash-on-delivery mails stay for you), Reply, Return, Delete; Send with attachments, money or cash on delivery and the postage, and suggestions in To (your characters on this realm and side, the people you mailed lately, and your guild: up to 30 members, online first, narrowed to the names that match as you type); Sent: the last 50 mails this character sent.
- **Trainer window** in SuuUI's look: the trainer's name and title; a profession's rank; Filters (Available, Unavailable, Used) and Categorize; the services under category headings you can fold (with their count; a class trainer's under your spellbook's lines, which the game doesn't give), each with its rank and what it still requires (red while you can't learn it) and its price (red while you can't afford it), what you know dimmed; your money and Train (a double click trains too; learning a profession asks first). A pet trainer shows training points.
- **Auction house window** in SuuUI's look (first step, to test): Buy with your favourites, a search with filters (usable only, rarity) and the game's categories; the results with item level, how many and the lowest price; an item's auctions (buyout, time left, a bid where there is one) with Buy out; a commodity's offers (price per unit, how many, the seller or how many sellers) with a quantity, what it costs, and the game's final price to confirm. Sell: the item (drop it, right-click it in your bags, or pick it from your items), its price filled in 1c under what it goes for now (the same as your own cheapest offer; your last price when nobody sells it; never over a price you typed), the price you last posted at and the lowest buyout seen, quantity, starting bid and buyout (a unit price for what sells by the unit), duration, deposit and total, and Post, which says why when it can't; your items each with the lowest buyout seen. The lowest buyouts come from your searches and from **Scan all** (in Buy's search bar: every auction read once, about 48,000 in 20 seconds; the game allows it every 15 minutes, the button says when again; while it runs, the SuuUI emblem animates where the results are, over "Scanning auctions" and its progress), and show in item tooltips everywhere as a small block: the lowest buyout, what most sell it for, how many are offered (in how many auctions), and on a stack in your bags its price, each switchable in Settings › Auction house › Item tooltips. A cheap few (a few items offered far under the rest) don't set the price: it goes under the rest instead, and Post asks first when your price is that far under (Settings › Auction house: on/off, how far under, how few; 25% and 10% to start). Auctions: your auctions (time left, bid or "no bids", buyout, sold ones marked) with Cancel auction (what it costs, when more than the deposit), and your bids (Highest bid or Outbid, a note when you're outbid, your bid, buyout) with Bid and Buy out.
- **SuuUI's own Collections window** (first step, to test: Mounts): every mount this character can see on a model stage, framed the way the game frames it (turn, zoom, drag, wheel), the chosen one's card with where it comes from (vendors, drops, quests, containers, from SuuUI's own data: the game gives no source for mounts), the favourite star and Summon or Dismiss (SuuUI's own secure button); the strip below with every mount, the ones you lack dimmed, favourites marked, the ones collected this week marked new, a hover with each one's source; search, Collected / Not collected, Favourites and Recent (the day SuuUI saw it first); the foot with your count and what you collected last. Toys as a shelf (none has a 3D model): all 20 of Forever's toys as cards, each with what it does, where it comes from or Ready in…, its cooldown, the star and its own Use (SuuUI's secure button); the ones you lack dimmed; hovering a card shows all of it. The foot counts both. Appearances: you in the middle of the stage with the 14 slots around you (yours of all under each, the arcane glow on the chosen one), the class and the weapon kind to choose; the strip shows the slot's appearances as framed 3D tiles of you wearing just that piece (yours, Worn marked, the ones you lack dimmed, each with where it comes from), the chosen one tried on you with its card, the star and Undress. The micro menu's Collections button and the Collections key open it. While the module is off, the game's window keeps SuuUI's look:
- **Collections window** in SuuUI's look (to test): the game's own window restyled in place (Summon and the toys stay the game's buttons), its collections as text tabs along the top like SuuUI's other windows (Mounts, Pets, Toys, Heirlooms, Appearances), the game's stone, corners and shadows gone. A collection you have nothing of yet (the game hides its tab) stays as a greyed tab that can't be clicked; its tooltip says why, and it turns normal once there is something.
- **SuuUI's own Inspect window** (first version, to test): the player's name in their class colour, level, race, class and guild; their gear on the Character window's paper doll with each item's level (hover for the item, shift-click to link it); their model (drag to turn, wheel to zoom); beside it the item level, Player vs. Player (rank, rank points, honorable kills) and the guild. Compare with mine marks each slot ▲ or ▼ by how far it is above or below yours. View in Dressing Room, and View Talents (their talents read only in SuuUI's Talents window; Forever's own inspect has none). It opens at once and waits for their gear.
- **SuuUI's own Macros window** (first version, to test): General and this character's macros as two tabs with how many are used; the list (icon, name, first line; drag a row to a bar); the editor with the icon to drag to a bar, the name (16 letters) and the body (255 letters) with their counts; Change icon opens a picker (all icons, spells or items, 8 to a row, the wheel scrolls; a search over your spells and the items in your bags; drop a spell, an item or a macro on it to take its icon); New, Delete (asks first) and Save (says why when it can't). In combat everything waits, with the reason. `/macro` and the game menu open it.
- **SuuUI's own game menu** (Esc, to test): a compact panel over a dimmed screen: Return to Game, then Game (Options, Edit Mode, Macros, AddOns, SuuUI settings), Help (Support) and Session (Reload UI, Log Out, Exit Game), with your name, realm, frame rate and latency at the foot. Options and Edit Mode open the game's own; Esc opens and closes it as before.
- **SuuUI's own AddOns window** (first version, to test): this character's addons or all characters', a search, Enable all and Disable all (SuuUI stays on); memory, the addons' share of the CPU, the busiest addon and how many are on; Load out of date addons; every addon with its toggle, SuuUI's emblem on SuuUI and its plugins, its title in its own colours, version, memory and status (Loaded, Load on demand, Disabled, Not loaded, Missing dependency, Out of date); a suite's modules under it, folded with its arrow; a click opens an addon's notes, author, memory and what it needs (a missing one in red). What changed says "Enables on reload" or "Disables on reload"; the foot counts the changes, and Reload to apply saves them (Cancel or closing keeps everything as it was).
- **SuuUI's own Dressing Room** (first version, to test): ctrl-click any item and it opens; the doll on the model stage (drag to turn, wheel to zoom), the pieces it wears in a column (icon, name in its quality colour, slot; × takes one off; what you tried on marked, shift-click to link), your saved outfits with Save, Delete and Link, and Reset, Undress and Close. A mount preview shows the mount with its card and Open in Collections.
- **SuuUI's NPC dialogue** (first version, to test; the "Cinematic bar"): talking to an NPC becomes a compact scene at the bottom of the screen. Their live 3D portrait stands on the bar with their name and role in its corner; what they say types in while they talk (Space or a click shows it all); your answers are numbered pills below (1–9), their quests marked ! and ?, Goodbye last. Quests speak the same way: the text, what they ask on one line, the rewards as one-line cards (an upgrade marked) with money and XP beside them, Accept and Decline; progress with your counts; the reward to choose, then Complete quest. Enter accepts or completes, Esc leaves. While you talk the rest of the UI fades out and comes back when the conversation ends, or at once when a fight starts (Settings → NPC dialogue → Hide the rest of the UI).
- **SuuUI's own Support window** (first version, to test): the game's support pages in SuuUI's window with Back, Forward, Reload and Knowledge base, the loading mark while a page loads, and "Support is unavailable right now" with Retry when the browser can't reach it. (On the beta the support site itself answers 403, in the game's own window too.)
- **Role presets** (Settings › General › Profiles › Role presets, to test): ready-made layouts from SuuUI's designs as their own profiles, SuuTank, SuuHeal and SuuDps, each put in its role's place under By role so the HUD follows your role; one layout per role for dungeons and raids. Tank and DPS: the group above the chat, you and your target either side of the centre. Healer: the group in the middle between your frame and your target's (the party as one row, the raid's groups as rows), the cast bar and Cooldown Manager above it, no threat meter or swing timer. Each starts as a copy of your profile with the layout set; applying one again puts its layout back.
- Party frames: aura icons can sit **inside** the bar at its right end (for frames in a row); the raid frames' rows keep their top edge whatever the raid's size.
- Edit mode: **Group preview** fills the party frames (5) or the raid frames (10, 20, 40 players) with made-up players at their real place and size while edit mode is open, to set up a layout without a group. **Buffs and debuffs on every frame** fills them all with made-up auras (defensives and every debuff type), and your buffs and debuffs and the target's, focus's and bosses' too, to see how the icons sit and how many fit.
- `/suu layoutcheck`: where your layout lands at 1080p, 1440p, 4K and 3440 × 1440 (worked out from your frames' places, no switching needed): frames that leave the screen or overlap.
- **Colour vision** (Settings › General › Appearance, for every character, after a reload): Red-green (protanopia, deuteranopia) and Blue-yellow (tritanopia) presets for SuuUI's signal colours (danger, low health, healing, warnings, the dispel types, friend and foe), each checked so the colours that must differ stay apart for that vision. Shapes, badges and labels stay as they are.
- **Bag slots** beside the bags window (to test): your backpack, bags and reagent bag in a rail on the window's side; drag a bag onto a slot to change it, hover one to see its slots. At a banker the bank's bag slots get their own rail with a buy cell for the next slot and its cost (the game's own confirmation asks), and your bags' rail moves to the window's right. A Bags toggle in the window's header shows or hides them. With SuuUI's bags on, Blizzard's floating bag bar is gone. The reagent bag's slots sit in a section of their own under your bags ("Reagents · 36 · 12 free"), the keyring's after them.
- Your buffs fit beside the encounter timeline: on narrower screens (1080p) a row holds as many as there is room for before the timeline and the rest wrap to the next row.
- `/suu perf`: how much time each SuuUI module takes (its events, settings, timers) and how much memory it allocates (what becomes garbage), SuuUI's allocations as a whole (frame scripts too) and its memory; start it, play a while, run it again for the report.
- **Unit menus** in SuuUI's look: the game's right-click menu on you, your target, group members and players in the world, and its submenus (Settings › Tooltips › Unit menus); its choices stay the game's.
- **Plugin API 0.17** (`Docs/API.md`): `SuuUI.UI.MoneyInput`, `WindowFrame` tabs, `SkinWindow` tabs that can be disabled, `Confirm`'s `enterConfirms`, aura groups' `index`/`gap` and `SetGroupPlace`, and `SuuUI.UI.LoadingMark` (the SuuUI emblem for long waits), `IsTooltipSkinned`, `WINDOW_HEAD_H`, `SuuUI.CollectionSources()`, `SuuUI.ToggleCollections()` and `CollectionsShown()`, `SuuUI.ShowTalentsOf(unit)`, `SuuUI.UI.ModelStage`, `SuuUI.Motion.Reduced()`, `SuuUI.EditMode.GroupPreview()`, `Inventory:LayoutSlots` sections, disabled tabs on `WindowFrame` too, `SetGroupFilter` on aura containers, `M:Peek(key)` (a setting read without a copy), and plugins reaching into SuuUI's own UI: `M:Each(kind, fn)` (every unit frame, nameplate, cast bar, action button, window… now and later), `M:Hook` and `M:Override` on their methods, `SuuUI.Instances`, services (`M:Provide`, `SuuUI.Service`) and modules that replace a built-in one (`replaces`), entries in SuuUI's right-click menus, micro menu buttons, game menu entries, notification cards for more of the game's popups and a plugin's settings in the role presets, themes (`SuuUI.RegisterTheme`: colours and type, picked under Settings › General › Appearance › Theme, after a reload), and `SuuUI.Raw` (everything else, unstable). A plugin guide (`Docs/PluginGuide.md`) and a second example, `Examples/SuuUI_LevelBadge` (a level badge on SuuUI's unit frames). A module's own fields (`id`, `name`, `state`…) can no longer be overwritten by mistake.

### Changed

- Quest and recipe data refreshed from QuestieDB's latest Forever data (2026-10-17): 43 new quests on the world map, the library's book turn-ins in Stormwind and the Undercity among them (128 new quest-giver spots); 12 recipes gain dungeon-boss drops (Deadmines, Shadowfang Keep, Ragefire Chasm, Blackfathom Deeps, Wailing Caverns, Razorfen Kraul…); 56 blacksmithing recipes name Karn Stonehoof in Thunder Bluff as their trainer, with the skill they really need there (recorded in game). Map places are unchanged.
- Party and raid frames: debuffs follow right after the defensives that show (party: beside the bar; raid: at the bar's right end) instead of waiting behind empty defensive slots.
- Party and raid frames show every debuff after the ones you can remove (Forbearance on you didn't show), not only the ones the game marks for raids.
- Nameplates are smoother where many players gather: plates are made ahead, a few at a time, and quest marks are read only when your objectives change, never for players.
- SuuUI makes far less garbage (memory thrown away and collected later): the objective tracker no longer redraws on every item cooldown (each potion or trinket), only its quest items' cooldowns change; the action buttons read their cooldowns, usability and state once a frame instead of once per game event; the Cooldown Manager no longer copies every class's lists to read its own.
- Raid and party frames use far less memory: the game makes ten hidden aura icons for every icon group a frame has, whatever it shows, and a raid frame had four groups (1,600 hidden icons for a raid, made even when you're solo). A group is now made only once it can show something, and a raid frame's debuffs share one group for whoever it shows: two groups per frame.
- Trainer data from the 2026-10-16 beta patch: for mages Arcane Wrath and Frost Blast are new, Arcane Blast and Ice Lance changed; for paladins Salvation and Mass Salvation replace Blessing of Salvation and Greater Blessing of Salvation, Seal of Fury's last rank comes at 26, and many spells' values changed; for shamans Lava Burst comes at 40, Fire Nova hits for less and Mana Tide Totem is taught by the trainer; for druids Shred comes at 20; for warriors Victory Rush hits for less (and the druid's, warrior's and hunter's first ranks, missing so far, are in); for priests Holy Fire's rank at 42 changed (the spellbook lists the new ones to train, the trainer groups them, each rank with its own spell ID).

### Fixed

- Talents: "View Talents" on an inspected player shows their talents, read only ("Viewing Name's talents"), not your own.
- The world map no longer errors on a quest giver offering quests QuestieDB has no name for yet: the game's own title is shown, else the quest's number.
- Tooltips SuuUI doesn't know by name (an addon's own, the aura buttons') now get SuuUI's look: the check whether one already had it wasn't reachable by the Tooltips module, so the step quietly did nothing.
- Text fields react to typing at once (the merchant's quantity note, money amounts, the auction house): some only did after Enter.
- The game's dropdown menus in SuuUI's look no longer leave a gap under their last row.
- Restyled progress bars (a profession trainer's rank) have their fill and track the same height.
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
