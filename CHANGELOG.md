# Changelog

## Unreleased

### Changed

- Pink Cat: the paws and hearts in the background of the windows and panels (the settings and the others) are fainter and further apart, so they repeat less often.
- Pink Cat: the paws and toe beans in the health, power, cast, nameplate, XP and meter bars, and the little paws behind the bars, are fainter.

## 0.12.0 (2026-11-13)

### New

- **Stranglethorn themes**: two new themes in Settings › General › Appearance › Theme, the jungle over your UI. **Stranglethorn Ruins** is mossy troll stone: carved stone behind every window's title, stonework with spirals and zigzags in the windows' background, carved edges and spiral corners, vines with red berries over the top of every window, the chat and the player and target frames, a ring of vines round the minimap, fireflies drifting up, and ember accents. **Stranglethorn Canopy** is deep emerald under the leaves: leaves behind the titles, faint monstera leaves in the background, vines with hibiscus and orchids, a scarlet macaw perched on the minimap, orchid jewels and teal accents. Both draw every icon as a leafy vine (the talents tree as a palm, the bags as a woven basket), put a vine or a leaf's ribs in the health, power and cast bars, and use the game's carved Morpheus font for titles. Leaves sway and fireflies drift; with Reduce motion on they keep still.
- For theme authors (API 0.40): a theme's `dress` hangs art on the frames themselves, past their edges where it likes: pieces at a point, along an edge or over the whole frame, in front or behind, swaying gently; art behind a window's title; motes drifting up over the frame. It reaches the windows, the minimap, the player and target frames and the chat. A theme's fonts can also be the game's own (`Fonts\\MORPHEUS.TTF` and the others).

### Fixed

- Themes: with a theme that has patterned bars (such as Pink Cat), nameplates and unit frames showing another player's or a mob's health no longer flood the chat with "bad argument #1 to 'SetShown'" errors, for example when you switch themes.

## 0.11.0 (2026-11-12)

### New

- **Pink Cat theme**: a new theme in Settings › General › Appearance › Theme. Pink and lilac on deep plum with cream text, as easy to read as SuuUI's own look; 30 of the icons you see most (the micro menu, bags, close, settings, search, map pins, chat, mail, notifications, locks and more) drawn as cats, soft paw prints in the health and cast bars, toe beans in the power lines, XP and meter bars (they keep their shape on bars of any length, with simpler paws on the thin nameplate bars), tiny paws on mobs tagged by someone else, hearts on absorb shields and in ticked boxes, cat role icons (an eared shield, a heart, claw marks), claw marks for the combat sign, and a little more room between things. Its windows are cat-themed too: paw prints and hearts in the background of the windows, panels, tooltips and notifications (the bags and the character window stay plain, so their slots are easy to see), little paws behind the bars, stitched edges, paw prints on the corners, hearts on the dividers, under the chosen tab and as the toggles' and sliders' knobs, and a row of tiny paws under each window's title. Mana, rage, energy and focus keep their own colours.
- For theme authors (API 0.37): themes now reach much more of the UI than the unit frames. `glyphs` replaces any of SuuUI's icons by name (window icons, buttons, bags, map pins, the micro menu, menus, professions, notifications and the rest; the names are in `SuuUI.Tokens.glyph`), new texture tokens cover every other bar (XP and reputation, the swing timer, the meters, the totem and weapon-enchant drains, the tooltip's health bar), the round discs and rings of the map pins, minimap and micro menu, the checkbox tick and the settings' reset and lock icons, and the new `shade` colour tints every dark overlay. Role icons in the threat meter, raid groups, group finder and Defensives use the theme's role textures, and text drawn at its own size (big numbers, the NPC dialogue, titles, the minimap's N) follows the theme's text sizes. All of it changes at once when you pick the theme; SuuUI's own look is unchanged.
- For theme authors (API 0.38): `space` sets the spacing tokens (`space-1` to `space-7`) and `sizes` the size tokens (icons, item slots, the unit frames, the minimap, notifications, the settings' nav…), for a denser or roomier UI: each up to four times SuuUI's own (sizes down to a quarter, spacing down to none). Picking the theme lays the windows, unit frames, nameplates, action bar dock, bags, chat, tooltips, minimap, notifications, settings, auction house, objective tracker and micro menu out again at once; frames that can't move in a fight follow when it ends. Sizes you set yourself (the player and target frames, the minimap) stay yours. `radius` is accepted too, for themes to come: SuuUI's corners stay square. SuuUI's own look is unchanged.
- For theme authors (API 0.39): a theme's `textures` now reaches the windows: `surface-pattern` puts a pattern in the background of every window, panel, tooltip and notification (`SuuUI.UI.Panel`'s `plain` leaves it off) and `track-pattern` behind the bars, `border` draws the windows' edges (dotted or stitched), `corner`, `jewel` and `mark` replace the gilt diamonds on corners, dividers and tabs and the small marks on toggles, sliders and names, `divider` draws the line under a window's title, and `plate-health-bar` and `plate-cast-bar` give the thin nameplate bars art of their own. A bar's art can repeat along the bar instead of stretching: give it as `{ file = path, height = px }` and each copy is drawn at the bar's height, keeping its shape on bars of any length. Left out, each stays SuuUI's own look.

### Changed

- Chat: the chat text and its tabs now use the theme's fonts (your chat font size stays as you set it). Chat colours stay the game's: set them in the game's chat settings. For theme authors (API 0.36): a theme's chat-* colours are left out, with a warning in the chat.

### Fixed

- Themes now recolour everything they should: the glows (aggro, ready buttons, alerts, warded frames and the rest) follow a theme's colours, and switching colour vision back to Normal brings the usual glows back without a /reload; the rings inside the player frame and the action bar dock, the model backgrounds in Collections, the dressing room and the NPC portrait, the red tint on items you can't use at a vendor and the dimmed screen behind the welcome now take the theme's colours too.
- Tooltips: a tooltip opening in SuuUI's place at the bottom right now always sits above the damage and threat meters instead of covering their header when the meters have grown into its place.
- Settings: a live preview wider than its column (a wide player frame, or a theme with more room) is now scaled down to fit instead of being cut off at its left edge.

## 0.10.1 (2026-11-12)

### New

- **NPC reaction colours**: a new setting under Settings › General › Appearance › Theme shows NPCs' health on the target, target of target, focus, boss and pet frames and on nameplates in their reaction's colour: hostile red, neutral yellow, friendly green. It is off by default; when on, it wins over the theme's health colour and changes along with the NPC (a mob turning hostile, a new target). Players keep the Health colour setting, and a mob tagged by someone else keeps its tagged look.
- For theme authors (API 0.35): a theme can replace the textures of the unit frames and nameplates with `textures`: the health, power and cast bar fill, the absorb shield's hatch, the tagged mob's stripes, the glows, role icons, raid markers, the cast lock and the combat sign (the names are in `SuuUI.Tokens.texture`). Picking the theme changes them at once, on every frame and nameplate. `SuuUI.UI.Skin` and `SuuUI.UI.SkinBar` make your own frames follow it too.

### Changed

- Tagged mobs: a mob someone else has tagged (you get nothing from it) now shows a cool slate-blue health bar with diagonal stripes on its nameplate and on your target, target of target and focus frames, instead of plain grey. Its name and level keep their usual colours, and the stripes go as soon as the tag does.
- Quest rewards: when an NPC offers you a choice of rewards, a gold coin now marks the one that sells for the most at a vendor, instead of the Upgrade mark.
- Notifications: every notification has an x to close it, except the game's requests you answer on the card (invites, resurrection, summons...). Closing a reminder (gear to repair, full bags, points to spend) keeps it away until it clears and comes back.

### Fixed

- Nameplates: less stutter when mobs come into view, mostly when you dismount or pull a group (since 0.9.0).
- Nameplates: borders on plates and their debuff icons stay a full pixel at every UI scale; since 0.9.0 they could be drawn too thin to show.
- Nameplates: an error about a forbidden object could show during a fight.
- Auction house: your recent searches are kept again (none showed under the search box), and items you Shift-click to search for are kept with them.

## 0.9.0 (2026-11-12)

### New

- **Auction house search history**: click into the search box and your last 5 searches show under it, newest first, each with the icon of the first item it found. Click one to search it again, or the x on it to take it off the list; type to narrow the list down. Only searches that found something are kept, and each character keeps its own.

### Fixed

- Auction house: Buy now on a stackable item (ore, herbs) sometimes did nothing after you had chosen a piece of gear and gone back before its purchase finished, or without buying it. Buy now works again.
- Vendors: items above your level (shown in red) can be bought again, as in the game's own vendor window.
- Nameplates: debuff icons keep all their borders again; most of them went missing at some UI scales.
- Levels show grey only when a mob gives you no experience. Mobs a few levels below you that still give experience showed grey too.

## 0.8.0 (2026-11-12)

### New

- **Combat sign**: crossed swords show on the left of your player frame while you're in combat. They pop in once when the fight starts and fade away when it ends. Settings › Unit frames › Combat turns the sign off, or just the pop (with Reduce motion on, it never pops).
- **Mana cost preview**: while you cast a spell, the mana (or rage, or energy) it will use shows as a faded band at the end of your resource bar and player frame, so you see what you'll have left once the cast lands. It goes away when the cast ends, is interrupted or fails, and works in combat too. Instant spells show nothing.
- Resource bar: mana, rage or energy you lose now leaves a white trail, as damage does on the health bars. The bar shows your new amount at once; the part you just lost stays white for a moment, then drains away. With Reduce motion on, the bar just drops.
- **Hide quests on the map**: right-click a quest giver's "!" pin on the world map and choose "Hide this quest". All of its pins go away at once, on every map. If a pin holds several quests, you pick which one to hide. Hidden quests are saved per character and listed under Map filters › Hidden quests: untick one to see it again, or press Show all.
- Threat meter: show it only in a group or only in an instance (dungeon or raid), like the damage meter. The damage meter can now also show only in an instance.
- Professions: the Filter menu has a required level range, like the auction house's. Type a minimum, a maximum or both to see only the recipes whose item needs a level in that range; leave a box empty for no limit. Recipes that make no item (enchants) always show, and an item with no level requirement counts as level 0.
- For plugin authors (API 0.34): `SuuUI.UI.CombatBadge(unitFrame)` puts the combat sign on a unit frame; the resource bar's `cost` option and a unit frame's `powerCost` option show your cast's cost on their power bar (on by default); the Professions body's filters carry the level range as `level` (`{ min, max }`, also in `SuuUI.UI.PROFESSION_FILTER_DEFAULTS`); a group in `SuuUI.UI.FilterMenu` can have an `action`, a button under its choices.

### Changed

- Micro menu: buttons the game has turned off (such as Legacy before you unlock it) are greyed out like in the game's own menu, and their tooltip says why.
- Windows in the middle of the screen (professions, talents, Legacy) now open higher when they would cover your cast bar.

## 0.7.0 (2026-11-11)

### New

- Bags: currencies you mark "Show on Backpack" in the Currency tab now show at the bottom of the bags window, next to your gold. Hover one to see its tooltip, or click it to open the Currency tab.
- For plugin authors (API 0.33): `inv:SetCurrencies(list)` shows currencies in an inventory's foot, and `SuuUI.Pixel.Relayout(frame)` lays out a frame's 1-pixel lines again after it moves under a parent of another scale.

### Changed

- Bags: the keyring now shows by default, as its own section after your bags, with only the slots that hold a key (no empty ones). To hide it, turn off Settings › Bags › Keyring.
- Bags: the reagent bag's free slots now show once, in its section's header, instead of also at the bottom of the window.

### Fixed

- Setting a raid marker from a unit's right-click menu in combat no longer fails with "Interface action failed because of an AddOn".
- Entering combat no longer stutters for a moment after your spells change (a level up, a new spell, a talent): the spellbook now redraws shortly after the change instead of at the start of your next fight.
- Pulling a group of mobs no longer stutters as their nameplates appear: the nameplates' debuff icons are now prepared ahead, out of combat.
- Nameplates: the borders of the health bar, the cast bar and the debuff icons no longer disappear at some camera angles. They're now one screen pixel thick at any UI scale.
- Quest log: every quest now shows its eye, full while tracked and faint while not, so you can click it to track an untracked quest.
- Quest tracker: the − button folds the quests away again. Before, it turned into a + but the quests stayed.
- Macros: the icon picker now shows the icons of icon packs (such as Clean Icons – Mechagnome Edition) instead of empty squares.
- Reputation and skill bars: the colour now fills the bar to both ends, with no gap at the left or right.
- Guild window: switching tabs no longer makes the tabs flicker and jump.
- Micro menu: opening and closing the shop no longer shows the game's own art on the game menu button.
- Buff indicators: an indicator's Colour is now greyed out with "While missing", since it only colours the indicator while the buff is up. The Show description no longer runs into Missing colour.

## 0.6.40 (2026-11-11)

### Fixed

- Chat: clicking an item link in combat no longer prints "Interface action failed because of an AddOn".
- Cooldown Manager: some spells, such as Consecration, now check the mana cost and range of the highest rank you know instead of Rank 1, and their rows show that rank.

## 0.6.39 (2026-11-11)

### New

- **Loot roll tray**: group loot rolls now have their own tray at the top middle of the screen instead of sitting in the notifications (move it in edit mode). Each roll is a row with the item, the time left (a bar runs along the row and turns amber in the last 10 seconds) and Need, Greed and Pass with how many players chose each. Under it you see who chose what and who is still choosing; hover the row to see every name in a big raid. If you can't pick a choice, it tells you why. Bind on Pickup items ask you to confirm right in their row. Pass on all and Greed on all (it asks once) answer every roll you haven't answered yet, the winner of each roll shows for 5 seconds, and the tray folds into a one-line tab. If you had turned off "Rolls in the notification stack", the tray starts turned off too: turn on the Loot rolls module to use it. Settings › Loot › Loot rolls; `/suu lootroll` shows test rolls.
- For plugin authors (API 0.32): `SuuUI.UI.LootRollTray`, the roll tray as a component, and a second argument for settings migrations, `profile`, to move a setting to another module.

### Changed

- World map and collections: Questie's latest Forever data for quest givers, dungeon entrances, town services, rares, treasure chests, and where mounts, toys and appearances come from.
- Professions, world map, flight times and collections: game data from WoW Forever 1.60.1.70888, and more places recipes come from (drops and containers) from Questie's latest data.

### Fixed

- Cooldown Manager: shared slots such as Divine Shield (paladins) and Feral Charge (druids) showed the wrong spell after 0.6.38, for example Divine Protection's icon on Divine Shield. Your lists are repaired.
- Spellbook: Plate Mail no longer says "Train now" after you've trained it.
- World map: hovering the title (Continent › Zone) no longer causes a Lua error.

## 0.6.38 (2026-11-10)

### Changed

- Cooldown Manager: Travel Form now counts as caster form, so a druid's caster spells (Innervate, Hurricane, Rebirth, heals) keep showing while you travel.

### Fixed

- Cooldown Manager: Balance druids' Eclipse now shows in the procs when it's up. Before, SuuUI didn't know the game's Eclipse buff. Your saved lists get it too.

## 0.6.37 (2026-11-10)

### Fixed

- Auction house: the items in your reagent bag now show in the Sell list, and the merchant window's Sell junk button sells the junk in your reagent bag too.
- Collections: you can drag a mount, pet or toy you own from the Mounts, Pets or Toys tab onto an action bar, as in the game's own collections window.
- Mouseover bindings: a spell bound for friends only or enemies only to a click with Shift, Ctrl or Alt now casts when you click a unit frame. Before, the click did nothing (for example Purify on Ctrl + Left click).
- Mouseover bindings: when you move the unit frames' Target or Menu click to another click (Spellbook › Bindings, the Target and Menu rows), the new click now works, also with Shift, Ctrl, Alt or Cmd. SuuUI now keeps the game's own click bindings in step with yours; your other click bindings in the game stay as they were.

## 0.6.36 (2026-11-10)

### New

- Mouseover bindings: you can move the unit frames' Target and Menu clicks to another mouse button, with or without Shift, Ctrl, Alt or Cmd. Find them in Spellbook › Bindings, the Target and Menu rows at the top; each talent tree keeps its own, and Default puts the game's click back. This frees plain Left and Right click to cast spells on unit frames. Clicking units in the world works as before.
- Mouseover bindings: when you bind a spell to the click that Target or Menu uses, SuuUI offers to move Target or Menu to another click first.
- Mouseover bindings: Cmd clicks now work on unit frames too.
- Mouseover bindings: on a Mac where Cmd + Left click counts as a right click (the game's Mac option "Use Command + Left Click as Right Click"), the binding boxes say so and offer to turn that option off, so Cmd + Left click can be bound.

## 0.6.35 (2026-11-10)

### New

- Auction house: the categories open into the same subcategories as in the game's own auction house, down to an armour type's slots (Armor › Plate › Head), and the list scrolls when it is long.
- Auction house: the Filter menu has a Required level range, a lowest and a highest level, to find only items for those levels. Press Enter in it to search.
- Auction house: click a column's header (Name, Item level, Available, Lowest price) to sort the results by it; click it again to reverse the order.
- For plugin authors (API 0.31): FilterMenu's `range` groups (a minimum and a maximum), its `onSubmit`, and `SuuUI.UI.FilterRange(choice)`.

### Fixed

- The quest log's zone headers stay white after you hover them, instead of turning grey until the log is opened again.

## 0.6.34 (2026-11-10)

### New

- Cooldown Manager: a Racials collection at the end of Utility in every class's presets, with every race's racials (Perception, Will to Survive, Stoneform, Shadowmeld, Elune's Light, Escape Artist, Eureka!, Blood Fury, Shatter Curse, Will of the Forsaken, Cannibalize, War Stomp, Berserking, Rapid Regeneration, Walk on Air, Read Leyline, Skysight). Only your own race's show, with their cooldowns, and their buffs (Berserking, Blood Fury, Stoneform…) cover the icon while they're up. Your saved lists get it too, at the end of Utility; Cultivation starts switched off.
- Cooldown Manager: a collection now works in Essential and Utility too (+ Collection there): each spell in it shows once you know it.

### Fixed

- Cooldown Manager settings: the switch between your spell lists and your aura lists (Cooldowns / Auras, under Lists) shows again; it left an empty gap there.
- Auction house: the lowest buyout is right for items listed several times at one price, in Buy and in Sell (32 auctions at 20s each showed as 62c, and Sell suggested a third of the real price). A wrong price SuuUI already remembered is corrected the next time you search the item or use Scan all.

## 0.6.33 (2026-11-10)

### New

- Aura indicators can be limited to roles: each indicator has Tank, Healer and Damage chips beside its group sizes. Someone without a role counts as Damage.
- For plugin authors (API 0.30): a buff indicator's `roles`, `SuuUI.UI.INDICATOR_ROLES`, `SuuUI.UI.IndicatorsForRole(list, role)` and a unit frame's `UpdateIndicatorRole()`.

### Fixed

- Hunters: Beast Training no longer lists the abilities your pet already knows (they show only with the Used filter on, dimmed, and can't be trained).
- Hunters: Train at Beast Training now trains every time; it sometimes did nothing until a /reload. The trainer window also keeps your choice on the same ability when the list changes after training.
- Aura indicators' + Add now offers every spell in your spellbook (Wild Growth, Prayer of Mending, Riptide, Blessing of Sanctuary, Soulstone…) and a paladin's auras and blessings, each with its icon as in the Cooldown Manager.

## 0.6.32 (2026-11-10)

### Fixed

- Your debuffs show on enemy nameplates again (they stopped showing in 0.6.30).
- Clicking a player's name in chat starts a whisper to them again, as in the game's own chat. Shift-click still puts the name into chat.
- Pinging over SuuUI's unit frames (player, target, target of target, focus, pet, boss, party and raid) pings that unit instead of going through to the world behind them.

## 0.6.31 (2026-11-10)

### Fixed

- The world map's quest details are readable again: their text was drawn dark on SuuUI's dark background since 0.6.30.

## 0.6.30 (2026-11-10)

### New

- For plugin authors (API 0.29): `SuuUI.UI.SecureUnitFrames()` lists SuuUI's secure unit frames, the ones a click binding goes on; the objective tracker draws only the quests whose rows change, with `t:QuestKey(quest)` and `t:Invalidate()`.

### Changed

- The first time in a session you open the world map, the collections or a profession, their quest pins and sources show a moment after the window does.

### Fixed

- **Much less stutter**: crowds of nameplates (cities, busy starting zones, big pulls, turning your camera in a crowd), the start and end of a fight, switching targets, looting and questing no longer make the game hitch, and neither does a raid's roster changing mid-fight.
- Windows open faster: the bags, the world map and its quest log, and glancing at the map while running cost far less, and the spellbook and guild window do no work while they're closed.
- The first time you open the collections in a session, the game no longer freezes for a few seconds.
- Typing `/` in chat no longer freezes the game for a moment.
- A big guild or many Battle.net friends logging in and out no longer cause a hitch each time.
- About 9 MB less memory after logging in, far less garbage while you play (a cause of random hitches), and almost no work while nothing happens.
- Warriors, rogues and hunters no longer get the "debuffs you can remove" icons on friendly nameplates, which they can't use.

## 0.6.29 (2026-11-09)

### New

- The character window's stats start with a Gear category: your average item level (hover it for the average over all the items you carry) and, with Durability on, your gear's durability. It scrolls with the other stats instead of sitting under them.

### Fixed

- The mail window closes when you walk away from the mailbox.

## 0.6.28 (2026-11-09)

### New

- **Upgrade spell ranks**: when you learn a new rank of a spell, it replaces the rank you had before on all your bars, forms and stances included, and a chat line says what changed. Lower ranks you placed on purpose stay and macros aren't touched. On by default; turn it off under Action bars → Spells.

## 0.6.27 (2026-11-09)

### Fixed

- Keybind mode: the Done button shows the first time you open it too.
- The spellbook no longer lists a talent's trainer ranks as coming up when you haven't taken the talent, and numbers them from Rank 2 when you have (Light's Vigil showed "Rank 1, Level 50").

## 0.6.26 (2026-11-08)

### New

- Auction house: Shift-click an item while the auction house is open to search for it on the Buy tab: an item link in chat, an item in your bags, or a recipe's product or reagent in the Professions window. While you're typing in the chat line, Shift-click still puts the link into your message. Plugins can search the same way (API 0.28).

### Changed

- Game data updated to WoW Forever 1.60.1.70862 and QuestieDB's latest database: quest chains and names on the world map (the priest's Dark Sacrifice quests), more places recipes and appearances come from with the trainers that teach them, and the Cooldown Manager presets know the build's new spell IDs.

### Fixed

- Spellbook: right-clicking a pet spell turns its autocast on or off, in combat too, instead of giving a "Forbidden" error. It works through the pet bar: a pet spell that isn't on the pet bar says in its tooltip to right-click it there.
- World map: a quest's money reward lines up again, shown as SuuUI's money (25s) in the numbers' font like the XP beside it; its coin sat above the amount.
- Raid planner: Salvation and Blessing of Light are gone (WoW Forever doesn't have them); paladins count for Kings and Might or Wisdom.

## 0.6.25 (2026-11-08)

### Fixed

- Character window, Pet tab: the pet's model stays in a fight instead of turning into your character as you draw your weapons.
- Pet bar: right-clicking an ability turns its autocast on and off again, in combat too.
- Spellbook: your pet's spells were missing. They have a Pet school under your class's now, while you have a pet: a click casts them (in combat too), drag puts them on a bar, right click turns their autocast on or off; the ones that cast on their own show Autocast on.

## 0.6.24 (2026-11-08)

### New

- The Character window has a Pet tab next to Character while you have a pet: your pet's model, stats and experience in SuuUI's look, with its name, level, family, loyalty and (for a hunter's pet) its mood in the line at the top. It replaces the game's Pet button beside Stats, Sets and Titles.

### Changed

- The game menu's SuuUI settings entry shows SuuUI's own mark, the icon from the addon list, instead of a plain diamond.

### Fixed

- Unit frames: a shield (absorb) shows as even stripes after the health again, instead of stripes that stretch into lines across the bar.

## 0.6.23 (2026-11-08)

### New

- **Aura filters**: Settings › Frames › Aura filters lets you hide spells you don't need to see, or show only the ones you do, with block and allow lists you put on party, raid, your own, target, focus, boss frames and nameplates (buffs and debuffs separately). Party and raid debuffs now leave out SuuUI's Noise debuffs (Forbearance and Weakened Soul unless you're a paladin or priest, Resurrection Sickness, Recently Bandaged, Ghost, Deserter, Recently Dropped Flag, Boosted Rest) where the game allows it; you can take that off, copy SuuUI's lists to change them, or make your own. Plugins can bring lists too (API 0.27).

### Changed

- Party and raid frames show only debuffs that have a type (Magic, Curse, Poison, Disease) and crowd control, yours too and in combat too, so typeless ones like Forbearance, Weakened Soul and Boosted Rest stay off. Set "Debuffs" to "Every debuff" in the party and raid frame settings to bring every debuff back; your debuff row by the minimap keeps all of yours.

### Fixed

- Party and raid frames in the healer setup (icons inside the bar, raid frames in rows): Warded, Aggro and the debuff-type badges sit on the frame's top edge at the right, next to the icons, instead of in the middle over the name, and the name runs under the icon slots: its whole length shows while they are empty.

## 0.6.22 (2026-11-07)

### New

- **Class-coloured health**: Settings › General › Appearance › Health colour shows players' health in their class colour, toned, on every unit frame and nameplate (NPCs keep the theme's colour). Themes can turn it on too (`health = "class"`, API 0.26); the setting wins over the theme.
- XP bar: a "Rested colours" option (Settings › Action bars, off by default) shows your XP in the game's own colours, blue while you have rested XP and purple without.

## 0.6.21 (2026-11-07)

### New

- **Pet happiness**: three diamonds on the pet frame's top edge show your hunter pet's mood: one ember when unhappy, two amber when content, three green when happy. Settings › Unit frames turns them off.

## 0.6.20 (2026-11-07)

### New

- An NPC's tooltip lists the quests it gives that you can pick up now, in their difficulty's colour with their level, as the world map's quest pins show them.

### Fixed

- Character window: opening it straight on Reputation (U) after a reload no longer shows your name, level and class above the list; they belong to the Character tab.
- Collections in combat: switching to or from the Toys tab changes the page too, not only the tab.
- Collections in combat: Toys opened for the first time in a fight says "Your toys show once this fight is over." instead of showing an empty page.
- Collections: the Appearances tiles show their models again after you visit another tab and come back.
- Settings: the minimap preview's clock shows the time now, as the game's clock settings show it (24-hour or AM/PM, local or realm time), and follows a change to those settings while it's open.
- Character window: a skill's, faction's or the PvP rank's description uses the room its pane has instead of scrolling in a small box; the scroll bar shows only when the text doesn't fit.
- Combo points sit on the target frame's top edge at its left end, where the target's debuffs no longer cover them.

## 0.6.19 (2026-11-07)

### New

- Bags: drag an item onto another slot to move it (press, move, let go), as well as click and click.

### Fixed

- Group Finder: the Whisper and Invite buttons on a player's row show their icons again, and so does the search mark when nothing matches.
- Bags: sorting no longer stops at a profession bag the game won't fill ("Only Skinning can be placed in that."): a bag in the reagent slot that only takes its own kind is read as such, and a bag the game refuses an item for is left as it is from then on while the rest gets sorted.

## 0.6.18 (2026-11-07)

### Changed

- Spellbook: the head shows only what the spells left to train cost; hover it for how many there are here and in all schools. The counts ran into the Bind button.
- The game's Click Casting (Esc > Options > Keybindings) now opens the Spellbook on its Bindings tab, SuuUI's click casting, while SuuUI's mouseover bindings are on. Before, it opened the game's window and the Spellbook on whatever tab it was on last.
- The game's Quick Keybind Mode (Esc > Options > Keybindings) now opens SuuUI's keybind mode while SuuUI's action bars are on: hover a button and press a key, as with `/suu keybind`. Closing it takes you back to the Options. The game's own mode only knew the game's bars, so keys pressed over SuuUI's buttons did nothing.

### Fixed

- Character window: opening it straight on Reputation (U) after a reload no longer shows a black box over the list.
- Spellbook: the Bind button no longer shows on the Bindings tab, which has its own Bind spells.
- The Game menu button on SuuUI's micro menu opens the game menu in combat too ("Interface action failed because of an AddOn"), as Esc does.
- Action bars: moving a spell while it was out of range no longer leaves its button tinted red until a reload.

## 0.6.17 (2026-11-07)

### Fixed

- Collections: while your account is logged in more than once, the game locks your pet journal and takes no favourites; the star on the Pets tab is now greyed out and says so, instead of seeming to do nothing. A mount the game takes no favourite for gets the same greyed-out star, as in the game's own Mounts tab.

## 0.6.16 (2026-11-07)

### Fixed

- Collections in combat: the Collections button on SuuUI's micro menu opens the window again, as its key does, and Escape closes it, without "Blocked in combat" errors.
- Group finder: results the game hands over partly hidden no longer stop the list with an error (`bad argument #1 to 'ipairs'`); what can be read still shows.
- Bags: sorting no longer tries to put items into a profession bag that can't hold them (a leatherworking bag in the reagent slot, for instance), which the game refused with an error. A profession bag in the reagent slot now gets only its own kind.

## 0.6.15 (2026-11-07)

### New

- **Pets in the collections**: the Pets tab shows every companion pet of WoW Forever, yours first (favourites first), each kind once with how many you have. Choose one to see it on the stage with where it comes from and what it is; Summon or Dismiss it, star it as a favourite, or summon a random favourite. Shift-click a pet to link it in chat. A pet you got as a gift comes wrapped, as mounts and toys do: open it on the stage; the tab and the micro menu count the gifts waiting.

### Fixed

- The game's own alerts over its micro menu ("You have unopened items in your collection" and the like) no longer pop up while SuuUI's micro menu is on: they pointed at the game's hidden buttons, and SuuUI's menu counts the gifts itself.

## 0.6.13 (2026-11-06)

### New

- A mob tagged by someone else has a grey health bar on the target, target of target and focus frames and on its nameplate, so you can see at once it won't give you anything. It turns back as soon as the tag goes, for instance when the player who tagged it dies.

## 0.6.12 (2026-11-06)

### New

- `/rl` reloads the interface, the same as `/reload`.

### Fixed

- World map: opening it in combat after visiting a flight master works again ("Blocked: SetPassThroughButtons"). The flight master's map is now a window of its own that looks the same as before (SuuUI's world map look and size, the routes, times and destinations), so SuuUI no longer changes the world map. In the air the world map opens where you are, as the game opens it; your route shows on whichever map you look at.
- Character window: a skill's details (a weapon skill's chances to hit and crit), a faction's and the PvP rank's fit their pane again instead of running past the window's bottom.
- Bags: the Bags/Bank switch, All characters and the Bags toggle show the first time you open your bags after a reload, not only from the second time.
- Collections: a toy's description no longer runs into its source line and Use button; the cards are a little taller for two lines, and a longer text ends in "…" (hover the card for all of it).
- World map: opening it in a fight no longer shows "Blocked in combat": SuuUI's map pins made during a fight let right-clicks through to the map once it ends.
- World map: the quest log's search box shows "Search Quest Log" after its magnifier instead of under it.

## 0.6.11 (2026-11-06)

### Fixed

- Mouseover bindings: a key with only a friend's spell (or only an enemy's) keeps its usual job over the other kind of unit. With Holy Light on friends on 2, 2 still pressed action button 2 over an enemy instead of doing nothing.

## 0.6.10 (2026-11-06)

### New

- **Mouseover bindings**: bind spells to keys, clicks and the mouse wheel in the Spellbook, and they cast on the unit under the mouse: on SuuUI's unit frames (player, target, target of target, focus, pet, party, raid, boss) and on units in the world, nameplates too. Away from units a key keeps its usual job. Press Bind in the Spellbook's head (or type `/suu bind`), hover a spell and press a key, click or turn the wheel; Delete clears the spell, Esc or Done closes. Right-click a spell to bind it with more choices: the highest rank you know (it moves up as you learn one) or this rank only, unit frames, the world or both, and anyone, friends or enemies, so one key can heal a friend and hit an enemy. Each spell shows its bindings after its rank. The Bindings tab under the schools lists them all, and copies them from another talent tree: each tree keeps its own. SuuUI asks before a key takes over another spell's and before binding Left or Right click on unit frames, and won't bind a key that moves you. Shift, Ctrl, Alt and Cmd combine; unit frames take Shift, Ctrl and Alt clicks (a Cmd click works in the world). In combat your bindings still cast; changes wait for its end.

## 0.6.9 (2026-11-06)

### Fixed

- Loot rolls: a roll's card stays after you've chosen, showing the others' choices, and goes as soon as the roll is decided (the winner, everyone passed, or all of a loot's rolls done), with its result. Choosing made it stay for good.
- Auction house: buying out a single auction (gear, recipes) works again ("Blocked: UNKNOWN()"). The game takes a buyout only from its own auction house, so SuuUI's window now goes through it: open the item and choose the auction in SuuUI's window, press Buy out, and the game's own confirmation asks. Only the first auctions of an item (the ones the game lists) can be bought out this way.
- Talents and talent builds: a tree's next row opens only with points spent in that tree, not with points spent in the others; until then its talents say how many points the tree needs.

## 0.6.8 (2026-11-05)

### New

- Bags: a quiver, an ammo pouch, a soul bag or a profession bag (herb, enchanting, engineering, mining, gem, leatherworking) shows as a section of its own after your other bags, as the reagent bag and the keyring do ("Quiver · 16 · 4 free"). Their slots no longer count as free space in your bags (the Bags button, the window's foot), as they only take their own kind.

### Fixed

- Loot rolls: a roll's card goes once the roll is decided (who won, or everyone passed), or a moment after its time is up, instead of staying after you've rolled.
- Hunters: training your pet at Beast Training works again ("Forbidden: BuyTrainerService()"). Train there goes through the game's own Train button; Train all isn't offered for pets.

## 0.6.7 (2026-11-05)

### New

- **Quests accepted and turned in for you**: talking to an NPC, SuuUI accepts the quests it offers and turns in the ones you've done, one after another, each told in chat. Left to you: grey quests (and, with General › Quests › Leave quests below you, those a set number of levels below you), PvP quests and a turn-in with a reward to choose; and unless you turn them on there: daily and repeatable quests, quests others share, turn-ins that take gold or items. Hold Shift as you talk to an NPC to do it yourself. Accept and turn in each have their own switch.

## 0.6.6 (2026-11-05)

### New

- World map: a campfire's tooltip says how long until it goes out, and a fire that goes out leaves the map while it's open.
- Plugins: the `campfires` service's fires say when they go out (`out`); API 0.22.

### Fixed

- Flight map: on the enlarged world map the flight masters' pins, flight times, the destinations list and the Fly bar are their usual size again, as on the normal map.
- Bags: Disenchant, an enchant, a sharpening stone or a lockpick put on an item in your bags by clicking it works again ("Forbidden: UseContainerItem()").

## 0.6.5 (2026-11-05)

### New

- **Shared campfires**: the campfires you walk up to go to your group (party, raid or finder group) and your guild, and theirs show on your world map, the tooltip naming who found it. A shared fire goes out 10 minutes after someone last passed it. Campfire settings › Sharing turns sending and showing off, each on its own.
- **Gifts in the collections**: a mount or toy you're given or buy comes wrapped, as in the game's own journal. It shows as a gift until you open it: the wrapped present on the mount stage (click it or Unwrap) or on the toy's card (click it). The Mounts and Toys tabs and the Collections button on the micro menu count the gifts waiting, and a notification tells you when one arrives, its Open showing it.
- Plugins: the `campfires` service's fires carry who found them (`by`) and `SUUUI_CAMPFIRES_CHANGED` fires when one is passed; `SUUUI_GIFTS_CHANGED` tells the gifts waiting, and a window can show a count on a tab (`SetTabCount`); API 0.21.

### Fixed

- Campfires on the world map go out: a fire you passed shows for 10 minutes after you last passed it, then it's gone.
- World map quests: priests no longer see Desperate Prayer offered where only dwarves get it (human priests have Divine Grace), and once you've done Divine Grace or Confounding Flash at one trainer, the other trainers' copies no longer show.
- World map: on the enlarged map a quest's Abandon, Share and Track buttons sit under its details again, not over the middle of the map.

## 0.6.4 (2026-11-05)

### Fixed

- Guild settings: changing a rank's permissions is no longer refused ("Forbidden: GuildControlSetRank()"). SuuUI's look on the game's dropdown menus and popups no longer hooks the game's shared menu and popup frames, which made a choice that does something protected (a guild rank, and the like in other menus and popups) count as SuuUI's.

## 0.6.3 (2026-11-05)

### New

- Plugins: a notification's action can click one of the game's buttons the secure way (`click`, `skipClick`), a map pin can be drawn with a crisp one-pixel edge (`pin:Crisp()`) and a window's chrome can follow a scaled window (`SetBody`); API 0.20.

### Changed

- Clicking a quest in the objective tracker opens the world map with its quest log, that quest selected and focused (it opened the quest's page before); in combat the click focuses the quest. Its menu's "Open in quest log" is now "Select in quest log".
- Clicking a group of pins on the world map no longer zooms in to them.
- The world map's title goes up a level outside combat; in combat, right-click the map.

### Fixed

- Opening the world map in combat no longer fails with "Interface action failed because of an AddOn" (SuuUI blocked from `SetPassThroughButtons`). SuuUI's World map button, the map's filters, the Damaged gear note's Show repairers and the objective tracker now open and redraw the map the game's own way, and the windowed map keeps the game's own size (it looks as before). The enlarged map looks as before too, but is the window scaled up with its header, quest log and SuuUI's pins kept at their usual size; only a few of the game's own map icons are a little bigger. If a block still happens, `/suu errors` now shows what touched the map.
- A notification's button no longer runs its action twice per click.
- The quest icons in the world map's quest log have a crisp, even ring (it was thinner than a pixel and broke up).
- Tooltips show their whole gilt edge again: with SuuUI's scale different from the game's, the top and right lines were missing.
- Talking to an NPC hides the minimap with the rest of the interface: your arrow, its icons and quest areas no longer stay on screen.

## 0.6.2 (2026-11-05)

### Fixed

- The rested sign on the player frame no longer causes an error ("Unit frames hit an error … SetFromAlpha") when you leave a rest area; it disappears at once where it can't fade out.
- Using an item from the bags with a right click is no longer blocked after a while of playing ("SuuUI has been blocked from an action only available to the Blizzard UI"), outside combat. If it still happens, SuuUI's error log (`/suu errors`) now also names what touched the chat's and the bags' code, so the cause can be found.

## 0.6.1 (2026-11-05)

### Fixed

- The chat input's text sits in the middle of its field again. With SuuUI's own scale different from the game's, the typed text and the cursor hung low, against the field's bottom edge.
- Symbols SuuUI's fonts can't draw no longer show as empty boxes: quest rewards' Upgrade and Inspect's item level difference get SuuUI's arrows, Online in the chat command list and the guild list in Mail a green dot, Known at a merchant a check, a Cmd key binding on an action button shows M, and the Auction House says "No favourites yet." when you have none.

## 0.6.0 (2026-11-05)

### Changed

- The flight map and the flight times follow WoW Forever's latest update (build 1.60.1.70707): the flight from Undercity to Kargath takes the game's new way, and the map's routes, area overlays and dungeon levels come from that build.
- The Cooldown Manager's talent conditions know WoW Forever's reworked talents (build 1.60.1.70707 with its server's changes): the paladin's Shieldsworn, Oath of Light, Boundless Light, Stoicism and Turn Evil, the druid's Lacerate, Predatory Discipline and Bloom, the priest's Holy Binding and Dark Inspiration, the mage's Arcane Wrath, the shaman's Elemental Mastery and the warlock's Grim Reach; talents the game removed are gone from them.
- The Cooldown Manager's class presets follow WoW Forever's ability changes since they were made:
  - Paladin: the blessing reminder no longer counts Blessing of Salvation or Light (gone from the game). Holy loses Voice of Truth and tracks Light's Vigil as a cooldown (allies only now). Protection tracks Swift Judgement as the second judgement it now is, and shows Shieldsworn's spell block. Retribution's echoes cover every seal (Unsealed Wrath) and add Turn Undead with Turn Evil.
  - Druid: Feral loses Berserk.
  - Mage: Arcane gets Arcane Wrath, and Frost gets Ice Lance (an 8 sec cooldown now).
  - Priest: Shadow Weaving shows on the target (where it now stacks), and Shadow shows Dark Inspiration.
  - Shaman: Elemental gets Elemental Mastery.
  - Hunter: Explosive Trap's burn is found again under its new name.
- WoW Forever's update to build 1.60.1.70755:
  - The flight map: the route between Powderfuse Port and Farholde Keep (Riverglades) is gone, as in the game.
  - The world map's quest givers, dungeon entrances, town services, rares and treasure chests follow QuestieDB's latest WoW Forever data, and the collections window's item sources with them (the Al'Aketh on Zephras Isle show as hostile).
  - The Cooldown Manager's talent conditions know the reworked rogue tree (Venom, Boot Knife, Flash of Steel, Composure, Blood Splatter, Death Mark; Murder, Cutthroat, Thousand Cuts and Improved Distract gone), the warrior's Reckless Swings and the shaman's Call of Thunder (Lava Burst gone), and the renamed talents (Lightning Mastery, Coup de Grace, Efficient Strikes, Quick Getaway, Accelerant, Precision, Improved Fire Blast, Unsealed Wrath, Trial by Fire, Improved Whirlwind) with their new cooldowns and texts.
  - The Cooldown Manager's presets: Elemental tracks Lightning Mastery (Elemental Mastery's new name) and no longer Lava Burst; Subtlety no longer watches Thousand Cuts or Cutthroat.
  - The spellbook's trainer lists no longer offer what the game stopped teaching (the paladin's Blessing of Light, Greater Blessing of Light, Salvation and Mass Salvation; the priest's Binding Heal; the shaman's Lava Burst and Totemic Projection; the mage's Frost Blast), and list Primal Bite from level 40 and Righteous Fury from level 10.

## 0.6.0-beta.1 (2026-10-25)

### New

- The spellbook: in a fight, switch between schools and pages; your spells now cast when you let go of the mouse, so pressing one to drag it to a bar no longer casts it; and dragging a spell to a bar works in a fight too.
- Plugin API 0.18: `SuuUI.UI.SecurePlacement`, a protected window opened in combat at its tab's size and place.
- Plugin API 0.19: SuuUI's components are classes, and `SuuUI.Raw.Mixins` holds them (with `WindowFrame` and `ClassBar` added). Changing a method on one when your plugin loads still reaches every frame SuuUI builds afterwards, those of the classes built on it included (a change to `Panel` reaches windows and the bags).
- Unit frames: while you rest in an inn or a city, a small "z Z Z" drifts up from your frame's top-right corner (a full moon once your rested XP is full), and hovering your frame shows your rested XP and what it means. Settings › Unit frames › Rested: show it also while carrying rested XP, keep it still, hide it in combat or at max level. The Unit frames settings now preview your frame.

### Changed

- Social: a friend last online a year ago or more says so in years ("1 year ago", where it counted months).
- Plugin API 0.19: a `Select` with `multiple` reports the chosen list through `onChangeAll(values)` and keeps it in `select.values`; `onChange` and `select.value` are for one value.
- Plugin API 0.19: an aura container's `ShowPreview(items, place)` takes the place with named fields: `{ point =, relativeTo =, relativePoint =, x =, y = }`.
- Plugin API 0.19: `RegisterMover`'s option `managedShow = true` says your module shows and hides the frame itself; edit mode then leaves its visibility alone. It replaces `frame.suuManagedShow = true`, which edit mode no longer reads. `RegisterMover`'s options are typed (`MoverOptions` from `/EditMode/EditMode`).
- Plugin API 0.19: `SuuUI.UI.UnitStandIn(person)` needs each person's `health`, and its `UnitCreatureFamily` answers `""` for no family.
- Plugin API 0.19: two new services, `marks` (your map marks, for the world map) and `worldmap` (its Marks filters and the pin showing a mark); the world map and the marks module now talk only through them.
- Plugin API 0.19: three more services, `convergences`, `campfires` and `flightmap`, and the `worldmap` service's `Refresh()` and `OpenWith(group, item)`: the world map, the flight map, the Convergences, the campsite and the notifications now talk only through them.
- Plugin API 0.19: `SuuUI.RecipeSources(recipeID)` is typed: a `RecipeSource[]?` (its layout in Data/RecipeSources), where it was untyped.
- Plugin API 0.19: `SuuUI.RaidCatalog()` names its providers' fields: `by = { { class = "DRUID", tree = 2, talent = true } }`, where they were a list (`{ "DRUID", 2, talent = true }`).
- Plugin API 0.19: a settings section is typed (`SettingsSection` from `/Core/Modules`, its groups and rows in SettingsUI/Registry): a wowlua plugin's section is checked as you write it. A row's `set` takes the value as `unknown` (check it before you use it), a custom control's `build(parent, onChange, def)` returns its frame, and `disabled` may return nothing.
- Plugin API 0.19: `chrome:SetTabs` takes any frame as a tab's `button` (the Character window's mode tabs are frames on some clients); the Social pages' `onMenu` and `onMember` get the frame clicked as a `Frame`, and their rows may carry the owner's own fields (`bnetID`, `gameAccountID`, `inviteName`, `guid`, `unit`, …).
- Plugin API 0.19: a module from `SuuUI.GetModule(id)` has all of a module's methods typed for a wowlua plugin (`:Setting(key)`, `:Guard(fn)`, `:RunOutOfCombat`, `:RegisterMover`, …); a method a module adds itself reads as `unknown` until you check it (`type(m.PreviewView) == "function"`).
- Plugin API 0.19: `SuuUI.ListModules()` is typed for a wowlua plugin: a `ModuleSummary[]` (`id`, `name`, `description`, `state`, `source`, `builtIn`, `error`, `pendingReload`, `replaces`, `replacedBy`), where it was untyped.
- Plugin API 0.19: a wowlua plugin sees SuuUI typed (it was `any`): `M:Get(key)` has each default's type, `M:Each`, `M:Hook`, `M:Override` and `SuuUI.Instances` give each kind's class (`"unitframe"` a `UnitFrame`, …), and SuuUI's types can be imported (`import type UnitFrame from "suuui/UI/UnitFrame"`). The examples show it.
- Plugin API 0.19: ForeverLFG (`SuuUI.LFG`) is typed in wowlua: `On(event, fn)` checks the event's name and types the listener's arguments (`Match` gets the entry and its `MatchReason[]`, `Contacted` a `ContactNews`, …), from the types `LfgEvents`, `LfgEvent`, `MatchReason` and `ContactNews`.

### Fixed

- The spells window opened in a fight at Blizzard's size and place, its header against the top of the screen: it now opens where and as large as out of combat, also when a fight is the first time you open it.
- Unit frames: out of combat they dimmed even while you were hurt; they now dim only at full health (the change is immediate instead of a fade).
- Your buffs no longer run under the encounter timeline when they grow left (the default).
- The damage meter no longer errors when the game hides a fight's list; it says the list is secret until combat ends.
- Tooltips: the caster line on aura tooltips shows again.
- Social: Raid Info shows each lockout's difficulty, size and progress again.
- Merchant: Sell junk shows the real price instead of 0c.
- Guild: Remove removes the member again; editing the message of the day or the guild info says when the game's own box isn't available instead of failing.
- Game menu: Reload UI, Log Out, Exit Game and Edit Mode are blocked from the moment a fight starts.
- Notes stay hidden during a fight; the objective tracker's quest items hide in boss fights.
- Loot rolls show in the notifications again, with votes, roll numbers and the winner; "You passed on" and "You won" lines are read right.
- Bags opened SuuUI's way stay open when a merchant or the mailbox closes.
- The character window's item flyout no longer errors.
- Guild: opening the guild window in a fight no longer causes "Interface action failed because of an AddOn"; the message of the day shows as it was before the fight.
- Professions: the professions window opened for the first time in a fight now has SuuUI's look too.
- Collections: Shift-P opens and closes the Collections window in a fight too, and its close button works there; before, nothing happened in combat.
- `/suu errors` says "Blocked" for an action the game refused out of combat (one that needs your click or key press), instead of "Blocked in combat".
- Cooldown Manager: the Defensives editor saves your changes; the Timer and Stacks switches can be turned off.
- Raid planner: specs are shared and asked for in game, and a setup no longer breaks when someone has no slot.
- Marks: the minimap's marks go away when the Marks module stops.
- World map: no gap under a quest tooltip's first objective; the Convergences blessing reads right in combat.
- Talents: a new or imported build shows to plan right away, and Start playing turns off when a fight begins.
- Auction house: "Bought." and "Posted" stay on screen, a bid no longer carries over to the next auction, Scan all's results draw properly, Post comes back after the game refuses a post, and "1 seller" reads right.

## 0.5.0-beta.7 (2026-10-20)

### New

- Chat: drag a tab along the tab row to give it a new place (Search stays last); Esc or letting go away from the row puts it back. The order is kept for each character. Settings › Chat › Windows: drag anytime or only in edit mode (where the tabs show grips), and Reset for the starting order.
- Chat: a command palette. Typing a / lists the commands that start with it over the chat, by category (All, Chat, Group, Emotes, SuuUI, Addons), with what each does and where it comes from; a / alone lists them all. After /invite or /inspect it offers your target, group, guild and friends, after /join channels, after /suu probe its topics. Up and Down mark a row and Tab puts it in; Enter still sends what you typed. Settings › Chat › Command palette.
- Edit mode: right-click a frame to open its settings (edit mode closes, the Settings window opens at that frame's section).
- Edit mode: type a frame's exact position in the toolbar over it: its anchor (one of nine screen points), X and Y. Enter with a frame selected starts typing; Tab goes between X and Y, the arrow keys step 1 px (Shift: 10). An anchor you pick stays when you drag the frame; Reset brings the automatic one back. The Edit mode panel can be dragged out of the way (double-click it to put it back).
- **Durability** (Settings › General › Durability; each part can be turned off): SuuUI's own armour figure at the minimap's lower left in place of the game's, a damaged piece in amber and a broken one in ember, the lowest percent or Broken under it, the pieces when you hover it (move it in edit mode; it shows only while something is worn, or always if you like).
- Durability: the lowest piece's percent on the micro menu's Character button (ember 0% once something breaks), and the worn pieces in its tooltip.
- Durability: in the character window, a thin bar along each gear slot's foot with the percent on worn pieces (a broken one dimmed), and a Durability block under the stats (lowest, damaged, average). A broken piece's tooltip says it gives no stats until repaired.
- Durability: at a merchant who repairs, a line over the merchant window's foot names what is worn, and Repair all turns primary.
- **Raid planner** (Social › Raid › Plan, or `/suu raid`): save raid layouts as setups of slots (a class or anyone, a spec, a role, a label, in one of the eight groups), for 40, 20 or 10 players, saved for your whole account. Load one and the people in your raid fill their slots by themselves whenever the raid changes; drag a player onto a slot to keep them there, drag a spec from the palette onto a slot to make it ask for that. Open slots and players without a slot are listed, and Arrange groups moves everyone into their slot's group (leader or assistant, out of combat). Each player shows their spec's icon (their class's until the spec is known). Coverage shows the raid-wide buffs (Windfury, Strength of Earth and Grace of Air Totems among them, and Salvation besides each paladin's Blessing), boss debuffs, dispels and rescues your raid has, each on its own row with how many and who brings them (Mark of the Wild apart from Arcane Intellect), and each group's party-wide buffs (missing ones, and doubled ones that waste a slot). Specs come from an inspect, one player at a time, or from raid members' own SuuUI. Settings › Raid planner chooses what's tracked (Everything, The essentials, or your own list, one box each) and how slots fill. When Arrange groups can't run, its tooltip says why (not in a raid, not leading, in combat, no slots, or everyone already in their slot's group). Setups can be shared as text.
- Durability: the Damaged gear note names the worn pieces and has a Show repairers button (the world map with its Repair pins on). One alert when a piece breaks in combat.
- Durability: Repair at merchants (off by default): SuuUI repairs everything by itself at a merchant who repairs, from the guild bank first if you choose, and says in chat what it paid.
- **Flight map**: at a flight master SuuUI's world map becomes the flight map (no window of its own): every flight master on the continent, the ones you haven't found faint, the routes between the ones you have, drawn the way the flights really go, and each destination's flight time beside it; the side panel lists the destinations. Hover one to see its route, stops, cost and time; click it to fly there (or turn on Confirm before flying in Settings › Flight map: a click chooses it, then Fly in the bar). Closing the map closes the flight master. Settings › Flight map; with the module off, the game's own flight map.
- Flight map: every flight is timed, so a route shows its real time once you've flown it (until then an estimate from the route's length, marked ~). Open the map while flying to see your route: the part flown solid, the rest dashed, the time left at your destination. With the map closed, a flight bar at the top of the screen shows the flight: your destination and the time left, a diamond for each stop (gilt once passed), the next stop and when you land, and Land at to come down at the next stop instead of flying on (Settings › Flight map › Flight timer on screen; move it in edit mode).
- **Resource bar** (Settings › Cooldown Manager › Resource bar): your mana, rage or energy under the Cooldown Manager's icons, as wide as your cast bar, so bar, cast bar and swing timer make one column. Rogues and druids in cat form get their combo points on the target as five segments over it (all arcane at five), druids in bear or cat form a thin mana line under it. The number is the amount or a percent (or hidden), the bar turns amber under 25% mana or energy, and out of combat it fades to 60% (or shows, or hides in its place). It moves with the Cooldown Manager in edit mode.
- **Convergences of Elements** (Skyborne): SuuUI learns each tornado where your Skysight gives the long Elemental Blessing and shows them on the world map (Map filters › Skyborne) and on the minimap when you're near, glowing while you don't have the blessing; hover one for the blessing's time left and who found it. They're saved for all your characters and shared with your group and guild (Settings › Convergences of Elements, with Share all); one on Zephra's Isle is known from the start.
- **Bag sorting** (Settings › Bags › Sort): Sort now uses SuuUI's own order: by type (the best quality first and conjured items last; within a quality by kind of item, gear by slot, then item level and sell price), by quality, by item level or by name, with part stacks put together and the reagent and profession bags filled with what fits them; or the game's own sort. The items gather at the end of your bags (the order mirrored, the first item in the last slot) or the start. The bank's Sort uses the same order. While it sorts, the window waits under the loading mark; combat, picking up an item or closing the window stops it.
- **Weapon enchants**: your imbues, poisons, stones and oils now show. In your buff row they come first, each with an MH or OH tag, its time, charges and draining bar (the digits turn amber and blink in the last minute), then a gilt line, then your buffs (Settings › Auras › Weapon enchants). In the Cooldown Manager, add "Main-hand enchant" or "Off-hand enchant" to Buffs on you: it shows whatever is on that weapon, and with nothing on it the slot warns with the ember edge, out of combat only unless you choose otherwise (Behaviour: weapon, when missing, warn only out of combat). The shaman and rogue presets include them. Their tooltip says what's on which weapon and how long it lasts; the game doesn't let SuuUI remove one.
- **Talent builds** (Talents window): save builds for any class, kept for your whole account, each an order of points so it knows which talent comes at which level. The picker above the trees lists them (your class first, with a search) with New build, Import and Copy. Pick one to plan it on its class's trees: a click adds the next point, a right click takes it back, and the order list beside the trees shows each point's level; drag a line to move it (SuuUI says why when the rows or arrows don't allow it). Use build follows it on this character (each talent group its own): what fits is planned for you to apply, and if talents you learned aren't in it SuuUI asks first and plans the whole build right after a trainer's reset. The build's next talent wears a fel ring, and the talent point note names it. Share a build as text (one chat line) or the game's talent string, and import either.
- Plugin API 0.17: `SuuUI.UI.WeaponEnchant`, `WeaponEnchantable`, `WeaponEnchantSpell`, `WeaponEnchantIcon` and `SUUUI_WEAPON_ENCHANTS_CHANGED`.
- Plugin API 0.17: the convergences module and `SUUUI_CONVERGENCES_CHANGED`, `glow` on `UI.MapPin`, `SetGroups` on `UI.FilterMenu`.
- Plugin API 0.17: `inv.sort.tip` on `UI.Inventory`, the sort button's tooltip.
- Plugin API 0.17: `SuuUI.UI.ResourceBar`, and the Cooldown Manager's `SetFooter` for a frame under its rows.
- Plugin API 0.17: `SuuUI.FlightRoutes()`, how far each of Forever's flight routes flies, and `SuuUI.FlightPaths()`, the way each one flies.
- Plugin API 0.17: `SuuUI.Durability()` and `SUUUI_DURABILITY_CHANGED`, your gear's wear as the Durability module reads it; the micro menu's `m:SetLines(key, lines)` for a button's tooltip.

### Changed

- Nameplates: health drops as on the unit frames, a pale ghost of the lost health trailing the bar and easing down.
- World map: the game's little city houses are gone (SuuUI's own pins show the towns' services), and your arrow is SuuUI's.
- Rage is a clearer red on the unit frames and the resource bar.
- Cooldown Manager presets: buffs that last 3 minutes or less or get used up by charges (the shaman's Lightning and Water Shield, Battle Shout, Inner Fire) are fixed slots that warn while missing and show their time and stacks while up (they were reminders). Your saved setups follow.
- Tabs everywhere (every window's tabs, the chat tabs, the Settings list, the Professions rail, the Spellbook's schools): the chosen tab's underline and jewel glide to a tab you pick, and the jewel follows the pointer along the tabs, as on suuui.dev; in switches (Stats / Sets / Titles, Bags / Bank, the settings' choices…) the chosen option's fill glides to the one you pick. At once with reduced motion.

### Fixed

- Chat: a tab's name sits centred over its underline.
- Cooldown Manager: the shaman's Shields slot shows a shield you know, with the icon of the rank you cast (it showed the wrong one).
- Tooltips: a long hint wraps instead of running past the edge, and the convergence tooltip has room between its rows.
- Campsite: no "Campfire nearby" alert while you fly over one.
- Windows: the character window (and the other reskinned game windows) comes to the front when it opens or you click it; at a merchant it opened behind the merchant's window, out of the repair cursor's reach.
- Edit mode: the toolbar of a frame at the screen's top edge shows under the frame instead of off screen.
- World map: flight masters you haven't found show as such (faint, "not found yet"); they all looked found before. SuuUI notes which ones each character has found whenever a flight master's map opens, so until a character has opened one on a continent, that continent's read "not checked yet".

## 0.5.0-beta.6 (2026-10-19)

### New

- **Death recap**: Recap on the death request (or a death link in chat, or `/suu recap`) opens SuuUI's own: the killing blow on top, your health falling to zero across the last seconds, then every hit with its time, caster, amount and your health after it; the killing blow in ember. Hover a hit for its spell's tooltip.
- **Rare and elite crest** on the target and focus frames (on the top edge over the right end) and beside nameplates: a gilt diamond with fading wings for elites, silver for rares, silver with a gilt jewel for rare elites, longer wings and three jewels for world bosses.
- **Elite dragon** (Settings › Unit frames › Elite dragon, off by default): the game's own dragon around the target and focus frames' right end, gold for elites, winged silver for rares (with the crest's gilt jewel on its breast for a rare elite), winged gold for bosses, in place of the crest; friendly and neutral NPCs too. Nameplates have their own switch (Settings › Nameplates › Elite dragon): a small dragon round the bar's right end.
- **Themes** (Settings › General › Appearance › Theme, applied at once, no reload): High contrast (gilt edges, or ink edges), Class accent (your class colour in place of gilt, as it is or toned), Darker and OLED black, and five from Azeroth's raids: Black Temple, Molten Core, Naxxramas, Karazhan and Sunwell. Ready, danger, quest and class colours stay the same in every theme.
- Chat: click a line's class diamond to copy the whole line (time, channel, name and message).
- Chat keeps its history across logouts and reloads: each tab shows the lines it had (dimmed, above an "Earlier · logged out 2 h ago" divider), and whisper windows open with your earlier conversation. Settings › Chat › Kept chat turns it off or clears it.
- Chat: a Search tab looks through everything kept (every tab and your whispers) for a name or a word, lists the matches by player, and opens a whisper window with any of them.
- World map: group quests (elite, dungeon and raid) get the group bar under their pin before you take them, not only once they're in your log, Forever's own new quests too: the game's tag (it takes a few seconds to load; the pins update when it has), with Questie's corrections where the game's is wrong.
- World map: more vendors get a vendor pin, among them the mount sellers (Horse Breeder, Kodo Mounts, Raptor Handler and the others), Chromie and the commendation officers.
- World map: a weapon master's tooltip says which weapons they teach (Classic's lists; tell us if one teaches otherwise on Forever).
- Cast bars: the spell's target in its class colour, and the "you" badge in the target's place when the spell is aimed at you, in combat too (the game hides who it is; SuuUI hands it to the bar without reading it).

### Changed

- World map: a tooltip for several things on one spot (two weapon masters, a giver's quests with Shift) leaves a gap under the title and before each entry, so it's clear which lines belong together; the map's tooltips can be a bit wider.
- Colour vision (Settings › General › Appearance) applies at once, without a reload.
- Plugin API 0.17: colours that follow the theme (`UI.Paint`, `PaintFill`, `PaintGradient`, `Bind`, the message `SUUUI_THEME_CHANGED`); a tooltip line's `gap`; a theme's `colors` can be a function of your class, and its fonts can set a line height.

### Fixed

- World map: with Shift, each quest's objective sits under that quest, not in a list after all of them.

## 0.5.0-beta.5 (2026-10-18)

### New

- World map: hold Shift over a quest pin to see what its quests ask of you (their objectives, from the quest data), added under what the tooltip already says. Quest tooltips are a bit wider.
- Plugin API 0.17: `SuuUI.UI.RefreshTooltip(owner)`, a tooltip's `maxWidth`, and the quests' objectives in `SuuUI.QuestStarts().objectives`.

### Changed

- Micro menu: Collections has a horse head for its icon.
- Micro menu: the free bag slots on the Bags button sit in a small badge on its corner, larger and easier to read (an ember badge when none are free). Settings › Micro menu › Free bag slots turns it off.
- Chat: a right click on a tab opens Blizzard's chat settings for that window (whisper tabs still close with a right click).
- Plugin API 0.17: `SetCount` on the micro menu takes the badge's fill colour too.
- World map: quest data refreshed (QuestieDB, 2026-10-18): more of Forever's own quest chains in order, so their later quests no longer show before the earlier ones are done.

### Fixed

- Reputation: a faction's bar sometimes showed only a sliver though its figures were right (3,210 / 6,000 as a sliver); the bars fill to their value again.
- Skills: the bars (professions, secondary and weapon skills) were empty; they fill to the skill's level again.
- Skills and Reputation: the description beside the list no longer hides its first line.

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
