# ForeverLFG: design

ForeverLFG is a library inside SuuUI. It collects groups and players looking for groups from two sources, the game's group finder ("the tool") and the public chat channels, and turns both into one list. It has no UI of its own. It offers a public API and events, and SuuUI's Group Finder module and notifications are built on top of it like any plugin would be.

Status: **approved** on 2026-10-14. Everything under "What the game allows" was probed in game that day (`/suu probe lfg`, `/suu probe social`).

What is built:
- **The library**, all of it, except the parts marked **Not built yet**.
- **The Group Finder's Browse page**, the first of five stages; the rest are in `IMPLEMENTATION_PLAN.md`, step 3.4.

Points still open are marked **Open** and listed at the end.

## What the game allows (probed)

### The tool (C_LFGList, the vanilla-style group finder)

| | Result |
|---|---|
| Categories | **Dungeons** (29 activities, including Forever's own: Excavation Site: Wetlands, Ruins of Lordaeron, City of Dalaran, Hall of Thanes), **Quests & Zones** (40 activities, one per zone, in the groups Kalimdor and Eastern Kingdoms), **Custom** (1). There's no raid category at level 22. Raids will appear at higher levels, so the library reads categories and activities at run time and never hard-codes them. |
| Activities | `GetAvailableActivityGroups(category)`, then `GetAvailableActivities(category, group)`. Each has a name, a suggested maximum level and a size (5 for dungeons, 10 for Upper Blackrock Spire, 0 for zones). |
| Search | Works from a click or a key press (a typed command counts). **Blocked from a timer** (`ADDON_ACTION_BLOCKED`), so the library can't refresh the tool by itself. |
| Results | `GetSearchResultInfo`: activity IDs, leader name (sometimes missing), number of members, age, comment, name, delisted, new player friendly, play style. `GetSearchResultMemberCounts`: tanks, healers and damage still needed, and the members by the role each chose (TANK, HEALER, DAMAGER, NOROLE). The ones still needed are a 1 tank / 1 healer / 3 damage template less the members who chose them, never capped by the free spots; the game doesn't enforce roles (a group of four damage dealers still needs a tank and a healer). Results include single players looking for a group (1 member). They are secret during "chat messaging lockdown" (game docs). **Open:** when that lockdown applies. |
| Your listing | `GetActiveEntryInfo` (activities, comment, new player friendly, play style, voice) and `GetLFGRoles` (leader, tank, healer, damage) can be read. |
| Create or update a listing | **Blocked** from addon code, even from a click. Listing yourself goes through the game's own listing panel, which SuuUI restyles and lays out (your clicks on its controls save, like the guild Settings tab). |
| Delist | `RemoveListing` works from a click. |
| Joining a group | There's no sign-up on Forever (`ApplyToGroup` exists but doesn't work there). The tool offers **Invite** (`C_PartyInfo.InviteUnit`) only for single players, and otherwise you whisper the leader. |

### Chat

| | Result |
|---|---|
| Channels on the server | General, LocalDefense, **LookingForGroup**, Trade, Services, TradeLocal (in cities), plus addon channels (BigfootWorldChannel, MeetingStone) and ChromieTime. |
| LookingForGroup | You aren't in it by default. Joining works from a timer (at login), but the game then adds it to a chat window, so the library takes it off every window each time it joins. SuuUI's chat Global tab must skip it too. |
| Messages | `CHAT_MSG_CHANNEL`, `CHAT_MSG_SAY` and `CHAT_MSG_YELL` reach addons with readable text, author and channel, also inside a dungeon and **in combat there** (15 of 15 lines readable in Ragefire Chasm, one during a fight). Raids not yet seen. |
| Who posts | On an English shard, LookingForGroup carries English, **Korean** and **Chinese** posts ("심연 나락 가실힐러님 모셔요~", "濕地-1補"). Leaders repost every minute or two; replies like "." and "NO" are noise. |
| Language preference | `C_AccountServices.RequestPreferredPlaySettings()`, then `GetPreferredPlaySettings()` after `PREFERRED_PLAY_SETTINGS_UPDATED`: locale ID 1. `GetPreferredLocales()` names them: 1 English, 12 LatAm Spanish, 14 Brazilian Portuguese (this region). Datacenters: NA-West, NA-East, AU. The tool's language filter knows enUS, koKR, zhCN, zhTW, deDE, frFR, esES, esMX, ptBR, itIT, ruRU (default enUS). |
| Sending | `SendChatMessage` to public channels only works from a click. |

## Where it lives

`src/Libs/ForeverLFG/`, loaded before the modules, published as `SuuUI.LFG` (documented in `Docs/API.md`):

| File | |
|---|---|
| `LFG.lua` | Settings, events, start and stop |
| `Catalogue.lua` | The activities: a language-free table (keys, kinds, the tool's IDs, sizes), the tool's names and levels at run time |
| `Parser.lua` | One chat line to what it asks for; pure Lua, no game API |
| `Lang/enUS.lua` | English words (more languages as modules) |
| `Store.lua` | The merged list, expiry |
| `Chat.lua` | The chat source; joining LookingForGroup and keeping it off the chat windows |
| `Tool.lua` | The tool source; refresh, staleness, your listing, delist, invite, whisper |
| `Interest.lua` | What you're after, languages, matching, groups you contacted |

`tools/lfg_parse.lua` replays recorded chat (or lines given to it) through the same parser outside the game: `lua tools/lfg_parse.lua <SuuUI.lua SavedVariables>`.

- **Library (no UI):** sources, parser, catalogue, merged list, matching, events.
- **SuuUI module `groupfinder`:** the Group Finder window, the restyled listing panel and the notifications. It uses only `SuuUI.LFG` and the public UI API.

## The data model

### Activity

What a group can be for. The catalogue is built from the tool's activities plus SuuUI's own data.

```
Activity {
  key           -- "dungeon:wc", "zone:westfall", "raid:mc", "boss:azuregos", "custom", "tool:<id>"
  kind          -- "dungeon" | "raid" | "zone" | "boss" | "custom" | "other"
  name          -- the tool's name in the client's language ("Wailing Caverns"), read at run time
  toolActivity  -- the tool's activity ID (796), or nil (raids and bosses the tool doesn't offer yet)
  category      -- the tool's category (2, 116, 120), toolGroup its activity group
  level         -- { min, max } suggested (the tool's, else the hand-made list's)
  size          -- 5, 10, 40, or nil
  parts         -- an umbrella's activities: "dungeon:sm" is the four Scarlet Monastery wings
}
```

The table in `Catalogue.lua` knows no language: keys, kinds, the tool's IDs (the same in every client language) and sizes. What players type for an activity besides its name ("wc", "vc", "dm") comes from the language modules. An activity the tool offers that isn't in the table (raids at higher levels, new content) joins as `tool:<id>` with the tool's name.

Quests aren't activities: an entry carries the quest IDs it's for in `quests`.

- **Sources of the catalogue:**
  - the tool: whatever categories it offers at run time (dungeons, zones, custom; raids at higher levels);
  - quests: from quest links (exact ID; the title from the game, `C_QuestLog.GetTitleForQuestID`) and from your quest log (titles, zones, levels). SuuUI has no quest database, so a typed quest name is recognised only when it's in your log;
  - a hand-made list: raids, world bosses and the umbrellas (Scarlet Monastery, Stratholme, Dire Maul, the four dragons). **Not built yet:** named elites, group areas and world events.
- Raids and world bosses are in it from the start, from the hand-made list, so chat can name them. Raids from the tool join them once it offers them.

### Entry

One group or player looking. The same leader seen in the tool and in chat is **one** entry with two sources.

```
Entry {
  key           -- the leader's whole name ("Suther Stargazer"), the merge key
  intent        -- "group" (a group looking for players, LFM) | "player" (a player looking for a group, LFG)
  activities    -- { Activity key, ... } (none when unknown)
  quests        -- { quest ID, ... }
  roles = {
    needed      -- { tank = n | true, healer = ..., damage = ... }  (groups)
    offered     -- { tank = true, ... }                             (players)
    has         -- { tank = n, healer, damage, none = n }           (a group's members by the role each chose; tool only)
  }
  classes       -- { WARRIOR = true, ... } asked for by class
  need          -- how many more players, when known
  members       -- { have, max } when known
  level         -- { min, max } when stated ("40+")
  leader        -- { name, class, level, guid } (what's known)
  text          -- the tool's comment or the chat message, as written
  confidence    -- 0..1 (1 from the tool; chat: how sure the parser is)
  you           -- your own listing or post
  sources = {
    tool        -- { resultID, category, age, seenAt, delisted, newPlayerFriendly, playstyle, comment, ... } or nil
    chat        -- { channel, text, lastPost, posts, ... } or nil
  }
  firstSeen, lastSeen
}
```

A tool result's leader name often arrives a moment after the search (found in game). Until then the result is stored as `tool:<resultID>`. Once the name comes, the entry is renamed, or merged into that leader's chat entry (`EntryRemoved(entry, "merged")` for the old one).

- **Expiry:**
  - **Tool entries** last until the next search no longer has them, or they're delisted.
  - **Chat entries** expire 5 minutes after their last post by default (a setting). Posting again refreshes them.
- **Merge:** the same `key` from both sources becomes one entry. The tool's data (roles, members) wins and the chat text is kept alongside. If the same leader posts different activities, they're added to the entry.

### What you're after (the "interest")

```
Interest {
  listed      -- your own listing: activities, roles (from the tool)
  roles       -- your roles (GetLFGRoles), or chosen in SuuUI
  quests      -- quests in your quest log (IDs)
  level, zone -- yours
  watches     -- activities you asked to be told about (without listing)
}
```

### Match

A rule decides whether an entry concerns you: entry × interest → matched or not, plus the reasons.

- A group needs a role you play, for an activity you're listed for or watching.
- A group (or a player) for a quest in your quest log.
- A group in your zone for open-world content near your level.
- Which matches notify is up to you (see Notifications); all of them sort and highlight in the list.

## The chat parser

From one message to an entry (or nothing):

1. **Clean up:** lower case, collapse spaces and repeated letters. Pull out links first: a quest link gives the quest ID for certain; an item link is kept as text.
2. **Rule out noise:**
   - trade (WTS, WTB, selling, buying, prices with "g");
   - guild recruiting (recruit, `<Guild>`, "join us");
   - boosts and services;
   - questions (a single "?").
3. **Intent:**
   - LFM, LF1M, LF2M, "need", "looking for more", "lf tank": a group;
   - LFG, "lf group", "looking for group", "lf dungeon": a player.
4. **Activity:** match words and abbreviations against the catalogue (longest match first: "sm cath" before "sm"). Quest links give the quest; typed quest names are matched against the quests in your log only. Zone names.
5. **Roles and size:**
   - tank/heal/healer/dps/damage and their slang;
   - class names ("need priest" means a healer, "need warrior" a tank for dungeons);
   - "LF2M" means 2 more; "4/5" means 1 open.
6. **Level:** "40+", "lvl 35-40".
7. **Confidence** from how many parts matched. Below a threshold, the line is dropped or kept only as "maybe".

### Languages

The parser itself knows no language: every word it looks for comes from a **language module**.

- **A module per language** (`Lang/enUS.lua`, `Lang/koKR.lua`, ...) supplies:
  - intent words (LFM, LFG, "need", "suche", "구해요", ...);
  - role and class words;
  - noise words (trade, recruiting, boosts);
  - number words;
  - activity aliases (abbreviations and nicknames).
  Activity, zone and quest **names** come from the game itself in the client's language, so modules only add what players type besides them.
- **Built so far:** English (`Lang/enUS.lua`). Korean and Chinese posts are dropped until their modules exist.
- **Which modules are used:**
  - your Forever language preference (`C_AccountServices`, above) and the client's own language: always;
  - **by script:** a message written in another script (Hangul, Chinese characters, Cyrillic) is read with that language's module when SuuUI has one, whatever your preference (an English shard carries Korean and Chinese posts);
  - Latin-script languages besides yours (German, Spanish, ...) only when switched on in the settings, since their words overlap with English.
  Every module ships with SuuUI and registers itself; only the chosen ones are used.
- English is written first; Korean and Chinese follow (both seen on the server), then others as players ask.

The recorder (`/suu probe lfg record`) collects real lines to tune this. A small offline script in `tools/` replays recorded lines through the parser and prints what it made of each, so rules can be checked against real chat without being in game.

## Your own ad

The Group Finder offers to post your listing as an ad to LookingForGroup (or another channel you pick), written in your language from your listing (activity, roles needed or offered), and editable before it goes. The game only lets public chat messages be sent from your click, so posting is always a click, never automatic or repeated by itself.

## Notifications

Built in the Group Finder module (stage 2, 2026-10-15; to confirm in game). Every kind can be switched on or off, and each has its own options (sound, only from the tool or also from chat, the least parser confidence for chat, in combat, in instances); until the settings page (stage 4) they run on the defaults drawn on "Settings · Group Finder · Notifications" (all on but World boss or event). A kind that isn't shown in combat or in instances waits until you're out (the latest five). The same entry never notifies twice within 5 minutes; an entry with several reasons makes one note, for the most telling (role, player, quest, friends, activity, zone, boss). `/suu lfgnotes` shows one of each from made-up groups.

| Notification | When |
|---|---|
| **Your role is needed** | A group for an activity you're listed for or watching needs a role you play. |
| **New group for your activity** | A new group for an activity you're listed for or watching, whatever it needs. |
| **A player for your group** | You lead a group (listed or advertising) and a player looking for that activity offers a role you still need. |
| **Quest group** | A group or player for a quest in your quest log. |
| **In your zone** | A group in your current zone for open-world content (group quests, elites) near your level. |
| **World boss or event** | A group forming for a world boss or world event. |
| **Friends and guild** | A friend or guild member lists themselves or advertises. |
| **Results are stale** | You're listed or watching and the tool's results are older than a set time: **Refresh** and **Delist** buttons. |
| **Your listing runs out soon** | Your listing is close to its end (the tool gives its time left): **Open listing** and **Delist**. Open listing is a secure click on the game's Group Finder button and its listing tab (the listing panel opened from addon code would refuse to list), so out of combat only. |
| **You were delisted** | Your listing ended or was removed, but not when you took it down yourself. |
| **A group you contacted** | A group whose leader you whispered fills up, is delisted, or posts again still needing your role. |

Whispering a leader opens an empty whisper (no ready-made text).

## Freshness of the tool

The tool can only be searched from your click or key press, so:

- **When it searches:**
  - the Refresh button searches (built);
  - opening the Group Finder searches, since that's your click (**not built yet**).
- **When it's stale:** while you're listed or watching something, the results go stale after a few minutes. The library then fires **`ToolStale`**, and the notification offers **Refresh** and **Delist** (both work from that click).
- **Chat is live:** chat entries keep arriving and matching without any refresh.

## Events

```
SuuUI.LFG.On(event, fn)

EntryAdded(entry)              a new group or player
EntryUpdated(entry)            roles, members, text or sources changed
EntryRefreshed(entry)          posted again, unchanged (only fresher)
EntryRemoved(entry, reason)    "expired", "delisted", "gone" (left the search results), "merged", "stopped"
Match(entry, reasons)          an entry concerns you, for reasons it didn't before
Contacted(entry, what)         a group you whispered: "full", "gone", "reposted"
ToolSearched(category, count)  a search came back
ToolSearchFailed(category)
ToolStale(category, age)       results for what you're listed for or watch are older than the threshold
ListingChanged(listing|nil)    your own listing was made, changed or removed
ListingExpiring(secondsLeft)   your listing runs out soon
Delisted()                     your listing ended or was removed
```

## API

```
SuuUI.LFG.Start() / Stop()     -- nothing runs before Start (the Group Finder module calls it)
SuuUI.LFG.Configure(t)         -- SuuUI.LFG.config holds the defaults
SuuUI.LFG.Entries(filter)      -- the merged list; filter = { intent, kinds, activities, sources, minConfidence, search, notYou }
SuuUI.LFG.Entry(key)
SuuUI.LFG.Catalogue            -- .Get(key), .Name(key), .All(kind), .Expand(key), .ForTool(activityID)
SuuUI.LFG.Interest()           -- what the library thinks you're after
SuuUI.LFG.Watch(key, on) / Watches()
SuuUI.LFG.MatchReasons(entry)  -- "role", "activity", "player", "quest", "zone", "boss", "friend"
SuuUI.LFG.ContactedAt(key)     -- when you whispered that leader (SuuUI.LFG.Now()), or nil
SuuUI.LFG.Social(name)         -- "friend", "guild" or nil
SuuUI.LFG.Refresh(category)    -- only from a click or key press (the game's rule); 2, 116, 120
SuuUI.LFG.ToolAge(category)    -- seconds since that category's last search
SuuUI.LFG.Listing() / Delist() -- your listing; delisting only from a click
SuuUI.LFG.Whisper(entry)       -- opens an empty whisper to the leader
SuuUI.LFG.CanInvite(entry)     -- single players looking (the tool's rule)
SuuUI.LFG.Invite(entry)
SuuUI.LFG.Languages()          -- the language modules in use
SuuUI.LFG.Parser.Parse(text, { languages }) -- the parser on its own (tools/lfg_parse.lua)
SuuUI.LFG.Lang.Register(code, def)          -- a language module
SuuUI.LFG.IsHiddenChannel(name) -- LookingForGroup, which SuuUI's chat skips
```

`Docs/API.md` has the same with each function's details.

Listing yourself isn't in the library's API, because addon code can't do it. The Group Finder module hosts the game's listing panel instead.

## Settings (in the settings window)

**Not built yet** (stage 4). Until then, the library runs on its defaults (`SuuUI.LFG.config`).

- Channels to read: LookingForGroup, General, Trade, Services, Say, Yell.
- Join LookingForGroup, and keep it out of chat (on by default).
- Chat entries expire after N minutes.
- Notifications: each kind on or off, with its options (above).
- Languages: extra language modules besides your preference and your client's.
- Your ad: the channel it goes to.

## Open questions

1. **Chat volume:** the beta's channels are quiet; the parser is tuned on recorded lines as they come in (the recorder keeps running).
2. **Raids:** whether chat text stays readable in raid combat (not seen yet).
3. **A lost chat post:** in the first live run, a real LookingForGroup post ("LAST SPOT WC -- 1 TANK /w me") made no entry, though replaying it offline parses it. `/suu probe lfg entries` now counts what happens to each chat line (seen, secret, channel off, nothing found, low confidence, entries, errors) and keeps the last error; the next run in game will show where it went.
4. **Before List yourself and Who are built:** the play style and voice chat option lists, Who's filter and columns, and the level ranges of Forever's own dungeons are still to be probed.
5. **When search results turn secret** ("chat messaging lockdown"): not seen yet.
