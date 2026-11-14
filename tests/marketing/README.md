# Store screenshots

The pictures on SuuUI's CurseForge and Wago pages, made in wowlua's emulated
client: each scene sets up a moment of play with the mock API (a level 60
character in her gear, a party or a raid of made-up players, a fight, chat,
windows opened as a player opens them) and takes a screenshot with the 3D
world of your WoW Forever installation behind the UI. They are not part of
`wowlua test`: every test here is behind the `marketing` feature
(`@if(features.marketing)`), so a normal run skips these files.

| Image | Scene | What it shows |
|-------|-------|---------------|
| `01-hud-combat` | `hud.test.wowlua` | Elowyn (mage) and her party against a wolf pack in the Hinterlands: unit frames, Cooldown Manager, a Frostbolt on the cast bar, nameplates, threat and damage meters |
| `02-raid-healer` | `raid.test.wowlua` | Aubrielle (priest) healing a raid of forty against Ysondre, healer layout, her Renews and shields as indicators |
| `03-party-healer` | `party.test.wowlua` | Aubrielle's party against a Doomguard Commander in the Blasted Lands, healer layout |
| `04-character` … `09-settings` | `windows.test.wowlua` | In Goldshire: the character window (Gear category), bags, spellbook, world map with the quest log, collections, settings |
| `10-chat-palette` … `12-guild` | `social.test.wowlua` | The command palette over the chat, the group finder with groups from the LookingForGroup channel, the guild roster |

`hud.test.wowlua` also takes `hud-quiet` (after the fight, at sunset in
Stranglethorn), not on the pages for now. Every name is made up.

## Make them

You need WoW Forever installed (the world, the textures, fonts and models
come from it, as do the spells' and items' names and icons: `--game-data`).
Run the scenes one at a time, then the caption bars, then put them together:

```console
$ wowlua test --features marketing --game-data --world tests/marketing/hud.test.wowlua
$ wowlua test --features marketing --game-data --world tests/marketing/raid.test.wowlua
$ wowlua test --features marketing --game-data --world tests/marketing/party.test.wowlua
$ wowlua test --features marketing --game-data --world tests/marketing/windows.test.wowlua
$ wowlua test --features marketing --game-data --world tests/marketing/social.test.wowlua
$ wowlua test --features marketing --game-data tests/marketing/caption.test.wowlua
$ python3 -I tools/marketing_caption.py ~/Desktop/SuuUI-screenshots
```

Each scene writes its screenshots to `dist/screenshots/<file>/` (1920 by
1080, `tests/profiles/marketing-*.json`). `tools/marketing_caption.py`
writes, into the folder given (`dist/marketing` without one):

- `NN-name.png`: the scene with its caption bar under it (1920 by 1218);
- `clean/NN-name.png`: the scene alone;
- `captions.txt`: each image's headline and line, for the stores' image
  descriptions.

## Change them

- The order, the file names and the captions: `captions.wowlua` (the script
  reads it too).
- The caption bar's look: `caption.test.wowlua`, in SuuUI's tokens
  (`Design/tokens.json`): the surface ground, a gilt hairline with the
  divider jewel, the mark and the name in Marcellus SC, the headline in
  gilt-text and the line in ink-muted, both Figtree.
- The people, gear, bars and spellbooks: `scene.wowlua`, `mage.wowlua`,
  `priest.wowlua`. Units stand in the world by `scene.spot(ahead, left)`
  from the player; creatures and the group show the bodies of the display
  IDs given (the group's are the Northshire trainers' of wowlua's
  `northshire` profile).

## What the emulator draws differently

- In Winterspring (Kalimdor) the units placed didn't show in the 3D world,
  in the Eastern Kingdoms they do: every scene is there. A unit needs a
  `displayID` to have a body; `npcID` alone gives none.
- Marcellus SC leaves a gap after some letters (`HE ALE R`), and Figtree
  after a capital M and before an apostrophe's s: the captions' headlines
  are set in Figtree and avoid those, and the bar's "SuuUI" is two strings.
- The character window's side tabs: the chosen tab's marker covers its
  label at the same frame level; the scene lifts the tabs over it.
- Blizzard's raid manager tab shows at the left edge in any group; the
  scenes hide it (`scene.tidy`).
- The spellbook is the client's recorded one, so `scene.spellbook` gives
  the client's answers for each school; the collections' model shows after
  SuuUI's two seconds without the game's answer.
