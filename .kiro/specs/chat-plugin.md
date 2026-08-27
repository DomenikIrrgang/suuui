# Chat Plugin — v1 Plan

Design: **Glass Conversations** (artifact `suuui-chat-glass-conversations`, v3). Frameless log
floating over the world, per-conversation whisper tabs on a persistent avatar rail, one row
shape everywhere, optional timestamp column, and a resting chip naming the channel Enter will
open.

Status: **not started.** Nothing in this document is implemented.

---

## 1. The seam

Everything in this plan follows from one line: **the output is ours, the input is Blizzard's.**

Four independent constraints put it there, and none of them is a preference:

| Constraint | Consequence |
|---|---|
| `hash_SecureCmdList` is a **file-local** table with no global handle | `/cast`, `/target`, `/click`, `/use`, `/focus`, `/equip`, `/castsequence` are unreachable from any edit box we own |
| Link insertion goes to `ACTIVE_CHAT_EDIT_BOX`, set only by Blizzard's `ActivateChat` | shift-clicking an item in bags would silently tooltip instead of inserting |
| `SendChatMessage` is hardware-event gated for `SAY`/`YELL`/`CHANNEL` outdoors | a real keypress in Blizzard's box satisfies it; anything automated needs ChatThrottleLib |
| Replacing `AddMessage` on a Blizzard frame taints; suppress-and-reinject via message filters loses player-name clicking | this pair is why LS: Glass was retired — **neither technique is available to us** |

So:

- **Output** — our own `ScrollingMessageFrame`s, one per tab, fed by our own `CHAT_MSG_*`
  registrations. Wrapped as a component, exactly as `Components/Input.lua` wraps `EditBox`.
- **Input** — Blizzard's `ChatFrame1.editBox`, reparented and restyled into our input bar,
  keeping its own `ParseText` / `SendText`. That buys secure commands, `/w` targeting,
  autocomplete, `ACTIVE_CHAT_EDIT_BOX`, and hardware-event legitimacy for free.
- **Blizzard's frames** stay alive and neutered — not hidden-and-forgotten. They keep
  receiving, and we **mirror `DEFAULT_CHAT_FRAME:AddMessage`** so every other addon's
  `print()` lands in our General tab instead of vanishing.

Modern names, not the deprecation shims: `ChatFrameUtil` and `C_ChatInfo.SendChatMessage` both
exist on this client (Anniversary runs the refactored `Blizzard_ChatFrameBase`).

---

## 2. New components

Three, each with a spec in `Tests/spec/` before the plugin uses it.

### `Components/MessageLog.lua`

Wraps the native `ScrollingMessageFrame`. This is the whole reason the design is affordable:
word-wrap, max-lines, timed fading, scrolling and per-line hyperlink hit-testing are the
client's, not ours.

```lua
local log = SuuUI.Components.MessageLog({
    maxLines = 512, fading = true, timeVisible = 8, fadeDuration = 3,
    size = "md",            -- fontSize* token key, not a pixel size
}, parent)

log:AddMessage(text, r, g, b, lineID)
log:Clear()  log:SetMaxLines(n)  log:SetFontSize("md")
log:SetFading(on, timeVisible, fadeDuration)
log:ScrollUp() / ScrollDown() / ScrollToTop() / ScrollToBottom() / PageUp() / PageDown()
log:AtBottom()  log:GetNumMessages()  log:GetMessageInfo(i)
```

Signals: `SCROLL_CHANGED` (scrollY), `SIZE_CHANGED`, plus
`MESSAGELOG_SIGNALS.HYPERLINK_CLICK` (link, text, button), `HYPERLINK_ENTER` (link),
`HYPERLINK_LEAVE`, `AT_BOTTOM_CHANGED` (isAtBottom — drives the jump-to-bottom affordance).

Four things it must get right:

- **`SetFontSize` takes a token key**, so a user editing `fontSizeMd` moves the log with every
  other control. The same rule `StatusBar:SetTextSize` follows.
- **No `SetEnabled`.** It is display-only and takes no mouse beyond hyperlinks, so it joins
  `StatusBar` and `UnitClickArea` in deliberately having none rather than shipping a stub that
  makes `Dependency.Bind`'s `if target.SetEnabled` guard pass while nothing greys.
- **It never formats anything.** Callers hand it a finished string. What a message *means*
  belongs to whoever owns it — same division `StatusBar`'s text slots draw.
- **The frame is created with an explicit `SetFontObject` before the first `AddMessage`**; a
  message frame with no font object silently renders nothing.

### `Components/Avatar.lua`

A circular class-coloured initial with an optional count badge — the rail's atom.
`Backdrop.Circle` for the disc, `Components.Text` for the glyph, `Backdrop.Pill` for the badge.

```lua
SuuUI.Components.Avatar({ label = "Sylvaine", color = {r,g,b,a}, count = 2, size = 18 }, parent)
-- API: SetLabel, SetColor, SetCount(n|nil), SetActive(bool), GetCount
```

`count = 0` and `count = nil` both hide the badge (the `AuraIcon` `> 1` precedent: a client that
reports 0 must not paint a "0"). `size` follows `sizeControlSm` when omitted.

### `Components/Chip.lua`

The small uppercase pill used for the resting channel indicator, the in-field channel label, and
the channel tag on a row. `Backdrop.Pill` + `Components.Text`.

```lua
SuuUI.Components.Chip({ text = "GUILD", color = {r,g,b,a}, variant = "filled" }, parent)
-- API: SetText, SetColor, SetVariant
```

`color` accepts a literal `{r,g,b,a}` as well as a token key, because a channel's colour comes
from `ChatTypeInfo` — a **game fact**, not a theme decision — and must agree with the player's
own colour settings.

**No Core additions are needed.** Notable in itself: `AttachPoints`, `Pool`, `MoveableFrame`,
`Settings:Watch`, `Fonts` and `Pixel` cover this feature as they stand.

---

## 3. Plugin files

Appended to `SuuUI.toc` after `Plugins/MinimapButton/MinimapButton.lua`:

```
Plugins/Chat/ChatFormat.lua      -- CHAT_MSG_* payload -> display string. Pure functions.
Plugins/Chat/ChatRouting.lua     -- group tables, group->event expansion, tab routing. Pure.
Plugins/Chat/Conversation.lua    -- one tab: owns a MessageLog, unread count, persistence
Plugins/Chat/ChatRail.lua        -- the avatar rail (a vertical flow of Avatars)
Plugins/Chat/ChatInput.lua       -- adopts Blizzard's edit box; owns the channel chip
Plugins/Chat/BlizzardChat.lua    -- neutering + DEFAULT_CHAT_FRAME mirroring
Plugins/Chat/Chat.lua            -- plugin lifecycle, schema, window, wiring
```

`ChatFormat` and `ChatRouting` are deliberately **pure and UI-free** so they can be specced
exhaustively without a frame in sight. They are also the largest piece of work in the plugin —
see §7.

---

## 4. Data model

**A conversation is keyed by a normalised `name-realm`, lowercased.** This one decision fixes
three documented Blizzard failures at once: temp whisper frames are forced to ID 11+ and do not
survive a session, the same person opens two tabs as `Name` and `Name - Servername`, and layout
is re-derived on every login.

```lua
-- plugin:GetProfile()
{
  conversations = {
    ["sylvaine-goldensands"] = {
      name = "Sylvaine", realm = "Goldensands", class = "PALADIN",
      pinned = false, lastSeen = 1756890000,
      history = { { t = 1756889880, msg = "…", r=1,g=1,b=1, out = false }, … },
    },
  },
  tabOrder = { "general", "guild", "trade", "sylvaine-goldensands" },
  activeTab = "general",
}
```

Rules:

- **The client persists no message text at all** (`HistoryKeeper` maps senders to IDs, nothing
  more), so scrollback is entirely ours. Dump on `PLAYER_LOGOUT`, re-`AddMessage` on load.
- **History depth is capped per conversation** (default 100 lines) and channels persist *no*
  history — a firehose is not worth a SavedVariables write. Only conversations rehydrate, which
  is the same channels-fade / conversations-persist rule the design already states.
- Rehydrated lines are re-added **dimmed and with a session divider**, so restored history is
  never mistaken for live traffic.
- `class` is cached on the conversation so the avatar has a colour before the player is in range
  to ask about (`Game:ClassColor` returns nil for an unknown class — a real answer, and the
  cached value is the fallback).

---

## 4b. The data model — records, streams, panels

Replaces the "format an event into a string and push it into one frame" shape of 4a, which could
not satisfy either of the two requirements added on 2026-08-27: several panels showing configurable
subsets of the traffic, and per-channel / per-whisper history that survives a login.

A formatted string cannot **be in two panels at once**, cannot **survive a panel being
re-pointed** (the sender, channel and type were consumed at format time), cannot **be filtered**
(matching a sender would mean parsing back out of presentation), and cannot **persist** (it bakes
in the player's timestamp format, tag setting and the client's locale). So:

| Layer | File | Role |
|---|---|---|
| RECORD | `ChatStore.Record` | the structured facts the client gave us. No presentation at all |
| STREAM | `ChatStore` | the retention unit — one channel or one conversation, capped PER STREAM |
| PANEL | `ChatPanels` | a VIEW with a filter. Owns no messages |

Formatting is a pure function of (record, panel options) applied on the way to the screen and
never stored, which is what lets one record render differently in two panels and re-render
correctly after a settings change.

**The cap is per stream, not global** — a busy Trade channel must not be able to evict a whisper,
which is exactly what Blizzard's one-buffer-per-frame does. Default 50, `history_depth`.

**An event fans out to EVERY panel that accepts it.** `BuildEventMap`'s first-tab-wins is gone;
`Route` returns a list. Its real purpose — determinism, since `CHAT_MSG_AFK` sits in two
`ChatTypeGroup`s and Blizzard inverts that map with `pairs` — is preserved by ordered arrays plus
de-duplication by panel id.

**Registration is the union of the panels' groups**, so a group no panel wants is never subscribed.
Whisper groups are always registered regardless, because a conversation panel does not exist until
someone whispers you.

**Filters are a small closed vocabulary, not a stored predicate**: a Lua function cannot go into
SavedVariables and a filter the player edits has to be inspectable by the settings UI. Every clause
ANDs and an ABSENT clause matches everything, so adding a dimension is one optional field plus one
clause in `Accept` — and every stored panel is unaffected because it does not carry the field.
`groups`, `streams` and `senders` exist today.

**Persistence is written but not yet wired to SavedVariables** (deferred at the user's instruction).
`Serialise` / `Restore` round-trip records, mark restored ones so a renderer can dim them, and
resume the sequence counter.

### What mutation testing found here

- **Restored history lost its interleaving.** `Restore` walks stream by stream, so re-adding
  through `Add` renumbered sequences from 1 and a saved session came back as all-of-guild then
  all-of-say. Fixed by splitting `_insert` out of `Add` so a restored record keeps its saved
  sequence. Carrying the counter over had looked like dead code *because* the records it was meant
  to sort after were being renumbered underneath it.
- **`while #s > depth` never terminates for a negative depth** — `#s` bottoms out at 0 and
  `0 > -1` stays true. Both callers now reject a non-positive depth and `trim` keeps a floor of 0
  as a second barrier. This spun a mutation run for 67 minutes with no output, because the runner
  had no per-run timeout; it now counts a hang as a caught mutation.
- Two survivors were weak assertions rather than bugs: the de-dup is keyed by panel **id**, so a
  panel listing one group twice never exercised it (a duplicate id in the stored list does), and a
  whisper's routing needed an assertion that it actually RENDERS, since no shipped panel lists
  `WHISPER` and the group path returns no panels at all.

---

## 5. Routing

**The group is the unit, never the raw event.** `ChatTypeGroup[group]` expands to the events; a
tab subscribes to groups and the plugin registers the union.

Three landmines in Blizzard's own implementation to design around rather than inherit:

- `ChatFrame_AddSingleMessageType` never persists — it registers the event and writes nothing,
  so it dies silently on reload. We persist our own routing table, so this cannot bite us.
- `ChatFrame_RemoveMessageGroup` assigns `nil` mid-array instead of `tremove`, punching holes.
- `ChatTypeGroupInverted` is built with `pairs()` while `CHAT_MSG_AFK` sits in **two** groups,
  making its mapping non-deterministic across logins. Our event→tab map must be built from an
  explicitly ordered list, not from `pairs` over a table.

### Measured defaults (Phase 0 — done)

`GetChatWindowMessages` on this client. Windows 4–10 are empty:

| # | Groups |
|---|---|
| 1 | `SYSTEM SYSTEM_NOMENU SAY EMOTE YELL WHISPER PARTY PARTY_LEADER RAID RAID_LEADER RAID_WARNING GUILD OFFICER MONSTER_SAY MONSTER_YELL MONSTER_EMOTE MONSTER_WHISPER MONSTER_BOSS_EMOTE MONSTER_BOSS_WHISPER ERRORS AFK DND IGNORED BG_HORDE BG_ALLIANCE BG_NEUTRAL COMBAT_FACTION_CHANGE SKILL LOOT MONEY CHANNEL ACHIEVEMENT GUILD_ACHIEVEMENT BN_WHISPER BN_WHISPER_INFORM BN_CONVERSATION BN_INLINE_TOAST_ALERT CURRENCY BN_WHISPER_PLAYER_OFFLINE PET_BATTLE_INFO INSTANCE_CHAT INSTANCE_CHAT_LEADER GUILD_ITEM_LOOTED COMBAT_HONOR_GAIN PING` |
| 2 | `OPENING TRADESKILLS PET_INFO COMBAT_XP_GAIN COMBAT_HONOR_GAIN COMBAT_MISC_INFO` |
| 3 | `VOICE_TEXT` |

Three corrections to what this document assumed before the dump:

- **Window 2 carries real `CHAT_MSG_*` traffic** — XP gain, honour gain, tradeskills, pet info,
  misc. The earlier claim that it is *only* the `Blizzard_CombatLog` addon on
  `COMBAT_LOG_EVENT` was wrong: that addon attaches there, but these six groups route to it as
  well. So neutering window 2 without re-routing them **loses XP and honour messages entirely**.
  v1 folds all six into General; separating them again is a job for the per-tab routing editor.
- **The declared group list is longer than this client's event surface.** `ACHIEVEMENT`,
  `GUILD_ACHIEVEMENT`, `BN_CONVERSATION`, `BN_INLINE_TOAST_ALERT`, `CURRENCY`,
  `PET_BATTLE_INFO`, `INSTANCE_CHAT`, `INSTANCE_CHAT_LEADER`, `GUILD_ITEM_LOOTED` and `PING` are
  all declared because Anniversary runs the modern chat code, and several will never fire here.
  Routing must therefore expand `ChatTypeGroup[group]` from the client's own tables and tolerate
  a group whose events never arrive — never a hardcoded list of our own.
- **Whispers are inline by default**: `WHISPER` and `BN_WHISPER` both sit in window 1, so this
  client is at `whisperMode = inline`. Giving a whisper its own tab is therefore a *change* to
  what the player sees today, which is what `whisper_in_general` in §6 exists to soften.

**How the three windows map onto v1 tabs — RULED 2026-08-27.** General is the *conversational*
tab, not the everything tab: **party, party leader, raid, raid leader, raid warning, say, yell,
emote**, plus **whispers** when they are not being sent to their own panel. Guild and officer are
their own tab. Each joined channel (Trade, LFG, the numbered ones) is its own tab.

**General carries BOTH channel signals, not one or the other**: a short uppercase tag chip *and*
the message's own `ChatTypeInfo` colour. The tag column is shown only in tabs that mix channels —
General and nothing else, since a Guild tab would print `GLD` on every line — and it sits between
the timestamp and the name. This restores the four-up concept's chip, which v3 dropped when the
row shape was unified; the rail keeps carrying urgency.

**The Log tab — RULED 2026-08-27, on by default.** Loot, money, XP, honour, skill, faction
change, system, errors, tradeskills, opening, pet info and the BG system groups. None of them is
conversation, so by the General ruling's own logic they do not belong there — and separating them
is the direct answer to the loudest complaint about Blizzard's chat, that its default output is
unreadable because everything shares one stream. Window 2's six groups land here rather than in
General, which supersedes the earlier note that folded them into General.

**Where whispers appear is a THREE-WAY option, not a pair of toggles** (ruled 2026-08-27):
General only, their own panel only, or both — `whisper_mode` in §6, defaulting to **both**. A
dropdown rather than two booleans because two booleans have four states and one of them is
nonsense: no panel and not in General means whispers silently vanish. The three map onto
Blizzard's own `whisperMode` CVar (`inline` / `popout` / `popout_and_inline`), so honouring the
player's existing client setting as the initial value is possible later.

Windows 4–10 being empty means our tabs owe nothing at all to Blizzard's window indices — we
neuter all ten and index conversations by our own keys.

**ElvUI is never enabled alongside SuuUI** (ruled 2026-08-27), so its chat module is not a
consideration for the in-game checkpoints. This is the opposite of the inventory feature, where
its bag module had to be switched off first.

---

## 5b. Message composition — read off ElvUI, not inferred

`ChatFormat` is built on the client's own GlobalStrings, and the exact shape was recovered from
ElvUI's `Chat.lua` (~2191 and ~2398) rather than from memory. The global name is **built
dynamically**: `_G['CHAT_' .. chatType .. '_GET']`.

Four branches, and each is a real case rather than a defensive one:

| Case | Composition |
|---|---|
| normal | `format(header .. "%s", senderLink, message)` — the GlobalString's own `%s` takes the SENDER, the message is appended as a second `%s` |
| special (boss monster, pet battle) | `format(header .. message, senderLink)` — the message goes INSIDE the format string, because these globalstrings carry their own formatting |
| different language | `format(header .. "[%s] %s", senderLink, language, message)` |
| `TEXT_EMOTE` | the message ALREADY contains the sender's name, so the name is `gsub`'d into a link rather than prefixed |

**A channel message's `[Trade]` prefix is NOT part of the GlobalString** — it is prepended
separately as `'|Hchannel:channel:' .. index .. '|h[' .. name .. ']|h ' .. body`.

### The tag column is a SUBSTITUTION, not an addition

This is the consequence worth knowing before implementing the ruling in §5, and it was not
obvious from the concept. `CHAT_GUILD_GET`, `CHAT_PARTY_GET`, `CHAT_RAID_GET` and `CHAT_OFFICER_GET`
**already contain a bracketed channel name** — `|Hchannel:Guild|h[Guild]|h %s: `. So emitting the
GlobalString verbatim *and* a `GLD` chip prints the channel twice on every line.

So the tag column replaces that bracket rather than sitting beside it: `ChatFormat` strips the
`|Hchannel:(.-)|h%[(.-)%]|h` prefix and returns the tag as a separate value for the row to render.
ElvUI solves the same problem with a `ShortChannel` gsub on exactly that pattern, which is the
precedent for the pattern being safe to match.

Two consequences: the strip must **keep the `|Hchannel:` link target** (clicking a channel name is
a real action), and a numbered channel's `[2. Trade]` becomes the tag `2` or `TRD` rather than
being deleted — the number is the thing players type, so it cannot be lost.

### Harness note

The GlobalStrings are added to `api.lua` **shape-accurate rather than verbatim**: what the addon's
logic depends on is the number and order of format specifiers, not the English wording, and the
real client supplies the localized text. A spec asserts against the harness's own value, so a
composition bug is still caught — but do NOT read a passing spec as proof the English reads right
in game. That is a Phase 4 eyeball.

---

## 5c. Four defects the first screenshot found

`08:31 SAY Sulisande-Thunderstrike says: [Common] test` — one line in game, four separate faults,
none of which the suite could have caught as written. Fixed 2026-08-27, 10/10 mutations caught.

- **The tag duplicated the globalstring's VERB.** §5b established that the tag REPLACES the
  `[Guild]` bracket; the same is true of the verb. `CHAT_SAY_GET` is `"%s says: "`, which reads
  `SAY Thalvyn says: test` beside a tag column. So `Body` gained a `plain` mode, passed by `Line`
  whenever it is drawing a tag, that composes `Name: message` instead. The globalstring path
  survives for every type with NO tag — a boss emote, a system line, a channel notice — where its
  phrasing IS the content rather than a label. A real narrowing of "build it from GlobalStrings":
  they are right for Blizzard's tagless layout and wrong for a tagged one.
- **The player's own language printed on every line.** The client sends a language on every chat
  event, and Blizzard gates the display on it being DIFFERENT. Now gated on
  `GetDefaultLanguage()` — which the harness lacked entirely, so the bug was unreachable by any
  spec. It is added.
- **The realm suffix printed on every line.** `ShortName` strips it when it matches
  `GetRealmName()` and keeps it when it does not, since a different realm is the information. The
  LINK keeps the full name, because that is what a whisper and a context menu resolve against;
  only the displayed text is shortened, and a spec asserts the link separately.
- **The resting chip read as a button.** Say's `ChatTypeInfo` colour is pure WHITE, so a filled
  chip renders a light grey pill. Switched to `outline` — ring plus coloured text, no wash.

**Still open from that screenshot:** the sender's name is not class-coloured. The class arrives as
the event's GUID (`GetPlayerInfoByGUID`), so it needs a client call plus a harness model — its own
small phase rather than a drive-by.

---

## 6. Settings schema

On plugin id `chat`, one page, grouped into accordion sections by the existing `section` type.

```lua
{ key="enabled",            label="Enable Chat",            type="toggle",  default=true },

{ key="",                   label="Appearance",             type="section" },
{ key="show_timestamps",    label="Show Timestamps",        type="toggle",  default=true },
{ key="timestamp_format",   label="Timestamp Format",       type="dropdown", default="24h",
  enabledIf="show_timestamps", options={ {value="24h",label="14:32"},
  {value="12h",label="2:32 PM"}, {value="24hs",label="14:32:07"} } },
{ key="show_channel_rail",  label="Channel Colour Rail",    type="toggle",  default=true },
{ key="font_size",          label="Text Size",              type="dropdown", default="md",
  options={ {value="sm",label="Small"}, {value="md",label="Medium"},
  {value="lg",label="Large"} } },
{ key="width",              label="Width",                  type="slider",  default=460, min=240, max=900, step=10 },
{ key="height",             label="Height",                 type="slider",  default=180, min=80,  max=600, step=10 },

{ key="",                   label="Fading",                 type="section" },
{ key="fade_channels",      label="Fade Channel Messages",  type="toggle",  default=false },
{ key="fade_after",         label="Fade After",             type="slider",  default=8, min=2, max=60, step=1,
  enabledIf="fade_channels" },

{ key="",                   label="Conversations",          type="section" },
{ key="whisper_mode",       label="Whispers Appear In",      type="dropdown", default="both",
  options={ {value="general", label="General Only"},
            {value="panel",   label="Their Own Panel Only"},
            {value="both",    label="Both"} } },
{ key="rail_expand_hover",  label="Expand Rail On Hover",   type="toggle",  default=true },
{ key="history_depth",      label="Remembered Messages",    type="slider",  default=50, min=0, max=500, step=10 },

{ key="",                   label="Internal",               type="section" },
{ key="position",           type="position" },
```

Notes: `show_timestamps` defaults **on**, unlike Blizzard's — the column was asked for, so it
should be there without hunting. `fade_channels` never applies to conversation tabs; that is not
a setting, it is the design rule. `history_depth = 0` disables persistence entirely.

`whisper_mode` defaults to **both**, which puts a whisper in its conversation tab *as well as*
General — Blizzard's `popout_and_inline` behaviour. It is the default because this client sits at
`whisperMode = inline` (see §5), so the rail is unfamiliar and a whisper that only appears
somewhere the player is not yet looking is a missed whisper. `panel` gives the strict either/or
reading and `general` keeps the old behaviour exactly.

Deliberately absent from v1: search, chat logging to file, per-tab font overrides, keyword
alerts, spam filtering. All are in the LATER tier.

---

## 6b. Phase 6 — the rail and per-panel logs (DONE, in game unverified)

The window is now the concept's `[rail][column]`. Read off the artifact rather than recalled, which
corrected three things memory had wrong:

- **The rail is ONE list**, not two surfaces: channel rows, a hairline `.sep`, then one row per
  conversation. Switching from Guild to a whisper is therefore the same gesture.
- **A conversation gets CHROME; a channel is frameless.** The concept applies `.chrome` only in the
  conversation pane — a channel is a firehose you glance at, a conversation is history you read, so
  only the latter earns a panel. `MessageLog` already had the prop.
- **Inactive avatars ARE dimmed** (`.rw.dim .av { opacity:.5 }`), which settles §7b's second open
  question in the concept's favour. Shipped as `opacityRailIdle` (0.50) in both themes.

One log per panel, acquired lazily through `SuuUI.Pool` on `"chat.log"` and shown/hidden on switch
rather than re-rendered, because fading differs per panel and re-running `SetFading` on a shared log
would restart every line's timer. A conversation panel is created on the FIRST whisper, so it needs
no stored configuration to exist.

**The tag is now decided per panel**, which is the property the per-panel render buys: one record
can produce two correct strings. A panel that can hold only ONE group draws no tag, because it would
be the same word on every line and the panel itself already says it. A conversation falls under that
same rule rather than a guard of its own — it filters by stream and carries no groups, so the count
is 0; a separate `panel.conversation` check was here and mutation testing proved it unreachable.

**A message can never land nowhere.** Every routed id can fail to resolve, so `_render` falls back
to the first panel — a silently dropped line is worse than one in the wrong place, which is at least
visible and correctable.

### Departure to flag

**The concept's per-row left border cannot be drawn.** Each row in the mockup carries a 2px
`border-left` in the channel's colour (`.m { border-left: 2px solid var(--tr) }`), and a
`ScrollingMessageFrame` renders text and nothing else — there is no per-line region to paint. The
channel's identity is carried by the line's own `ChatTypeInfo` colour and by the tag instead. The
alternative is a frame per row, which was rejected in §1 because it forfeits word-wrap, timed
fading, scrolling and hyperlink hit-testing all at once.

### What mutation testing found

15 mutations, 8 survivors on the first pass. Six were weak specs; the two that remained were
**wrong comments rather than wrong code**, which is the more dangerous shape:

- `SetActivePanel`'s same-id early-out does NOT prevent a scroll jump — re-showing an already-shown
  log leaves its scroll alone. It is an optimisation, and it becomes correctness only once a switch
  restores per-panel scroll (pinned as an `xit`).
- `_ensureConversation` before `_route` is not required either: `WhisperPanels` names an id without
  checking it exists, and `_render` resolves ids at render time. What matters is only that it runs
  before `_render`.

### Corrected after the first in-game look

The rail shipped with three faults, all found by comparing the screenshot against the artifact
rather than against the code:

- **Labels were always on.** The concept's resting rail is discs only and "widens to names on
  hover"; always-on names also overflowed the rail cell, which was sized for a disc. The label is
  now always CREATED but hidden — flow skips a hidden child, so hiding it collapses the row — and
  `Avatar:SetShowLabel` toggles it at runtime, which a construction-time branch could not.
- **The 2px active marker (`.mk`) was missing entirely.** The active cue was disc opacity alone.
  It is now part of `Avatar`, transparent at rest and `colorAccent` on the active row, and its
  column is reserved even when inactive so a row does not shift sideways by 2 units on becoming
  active.
- **Hover expansion is armed from a ROW's `MOUSE_ENTER` and collapsed through `HoverAway`**, not
  `OnLeave`. The client moves focus to a child as the cursor enters one, so a row's own `OnLeave`
  fires while the cursor is still inside the rail — it would collapse the rail from under the
  cursor at the moment it reached the name it was aiming for. The expanded width is measured from
  the WIDEST name so the log's left edge does not shift as the cursor moves down the list.

The rail's width is stated rather than hugged, because container hugging is height-only — a
container with no explicit `w` takes its parent's width, which would have made the rail as wide as
the whole window.

**Three further mutation survivors were relative assertions**: comparing collapsed against expanded,
or active against inactive, cannot see a column missing from BOTH. Each now asserts an absolute
width against `Pixel.Line(2) + spaceXs + sizeControlSm`. The widest-name scan likewise survived
because the shipped names hide it — "General" is both first and longest — so the spec stages a list
whose widest name is last.

### The expanded rail OVERLAYS the log, and every line has a shadow

Two more corrections from the second in-game look, and the first is a decision the concept does not
settle outright.

**Expanding no longer resizes the rail's layout cell.** The rail and the log column are flow
siblings, so growing the rail pushed the column — measured in game at ~70 units, which means
hovering to read a name would re-wrap every line of chat and slide the resting chip sideways. The
concept's `.win` is a flex row, so a literal reading implies exactly that push; but the mockup only
ever draws the expanded rail as a static pane, so the transition is unspecified. Reflowing the whole
log on a hover is a functional cost rather than a style choice, so the names now overflow the rail
and overlay the log's left edge. Rows are added at their NATURAL width for this — a `"fill"` child
is clamped to the rail's cell, so an expanded name was shown and then clipped at 24 units.

**Every chat line, rail label and chip now carries a text shadow**, which the concept specifies and
this build had missed entirely (`.m span, .m b`, `.lbl` and `.ch` all have one). It is not
decoration: a frameless log draws straight over the game world, so a glyph on pale terrain has
nothing separating it from the background — and it is also what makes the overlaying rail label
readable against the chat text underneath it. Shipped as `opacityTextShadow` (0.90) derived onto
`colorGray950`, opt-in on `Components.Text` because text inside a panel already has a surface behind
it. Neither `FontString` nor `ScrollingMessageFrame` modelled shadows in the harness, so nothing
could have told a shadowed log from an unshadowed one; both now do.

## 6c. Phase 5 — the adopted edit box (DONE; taint cleared in game, routing still unverified)

`Plugins/Chat/ChatInput.lua`. Blizzard's box, reparented onto our window and skinned. It creates no
EditBox, and a spec asserts that structurally.

**This is a correctness fix, not a convenience.** The client parents `ChatFrame1EditBox` to
`ChatFrame1`, and 4b's suppression parks that frame on a permanently hidden holder — so with
suppression on and the box unadopted, pressing Enter opens an input the player **cannot see**. They
can still type and send; they cannot read what they are typing. The harness modelled no edit box at
all, so nothing could have shown this: it now models the box AS A CHILD of the chat frame, and a spec
asserts `IsShown()` and `IsVisible()` disagree once the frame is parked.

The two walls that make a custom box permanently worse, both recorded rather than re-derived:
`hash_SecureCmdList` is file-local with no global handle, so a box parsing its own input loses
`/cast`, `/target`, `/click`, `/use`, `/castsequence`, `/focus`, `/equip` and `/startattack`; and a
shift-clicked link is inserted only into `ACTIVE_CHAT_EDIT_BOX`, which only Blizzard's `ActivateChat`
sets. So `Open` goes through the client's own activation, preferring the modern `ChatFrameUtil` name
with the bare `ChatEdit_*` global as the fallback.

**The chip is now real.** Phase 4a returned a literal `"Say"` because `ChatTypeInfo.sticky` looked
like the source and is not — it means "this type MAY be remembered", and six types carry it, so
scanning returned whichever came first in an arbitrary iteration order. The channel is read off the
box instead, a whisper's chip names the PERSON rather than the word "Whisper", and the open field's
border takes the same colour so "where is this going" never leaves the screen. It follows Tab, which
changes the channel without closing the box — `OnTextChanged` is the only script that fires then.

`Watch` HOOKS and never sets: the box's own `OnShow`/`OnHide` drive Blizzard's history and
sticky-channel bookkeeping. That one is asserted **structurally** rather than behaviourally, because
the hook is installed once at login before any spec can arrange the state, and the `OnTextChanged`
hook reports on the same callback — so a `SetScript` mutation on `OnShow` is masked. Teardown hands
the box back BEFORE our wrapper hides, or the player has no visible input in either chat.

### Still to verify in game

**THE TAINT RISK IS CLEARED (2026-08-27).** `/use` on a Hearthstone, typed into the adopted box,
worked — and `/use` is protected, so the adoption did not taint the box's own command parsing. That
was the largest unverified risk in the plugin and the reason Phase 5 was gated behind an in-game
checkpoint. Shift-clicking an item from bags into the open box also inserts the link, so the
`ACTIVE_CHAT_EDIT_BOX` path survived the reparenting as well. Both were the arguments for keeping
Blizzard's box as an invisible engine rather than building our own EditBox; both now hold in
practice, not just in principle.

**Clicking a link IN the log needed TWO fixes, and neither works without the other.** The symptom
read as an unimplemented feature and was not one:

- **`Components/MessageLog.lua` never called `EnableMouse(true)`.** A `ScrollingMessageFrame` is a
  Frame subtype and takes no mouse input until told to, so the click never reached the frame to be
  hit-tested and `SetHyperlinksEnabled(true)` alone could do nothing. The file's own comment about
  "the hyperlink hit-testing that is the whole reason it takes the mouse" asserted a state the code
  never established. It passed every spec because a spec that invokes `OnHyperlinkClick` by hand
  skips exactly the delivery the missing line was responsible for — the same shape as the harness's
  case-sensitive `RegisterForClicks` gap, where `H.click` returned true and no handler ran.
- **The plugin never consumed the signals.** `MessageLog` emitted `HYPERLINK_CLICK` / `ENTER` /
  `LEAVE` and `ChatFormat.PlayerLink` already built links carrying the `lineID` that `SetItemRef`
  needs, but nothing connected them — the identical gap as `ActionButton`'s tooltip, where the
  component emitted and the owner never wired it. Now connected in the **pool factory**, which runs
  once per physical log, so a pooled log cannot accumulate a duplicate connection on every
  re-acquire; the handlers capture no plugin state, because the factory outlives the plugin.

`SetItemRef` is what makes an item link open its tooltip frame, a player link open the whisper menu
and a quest link open its panel — none of it protected, so no combat guard belongs on that path.

**Harness gap this exposes:** `IsMouseEnabled` IS modelled, so "the log takes the mouse" is
assertable and should be pinned the moment tests resume. `SetItemRef` is NOT modelled, so the
click-to-`SetItemRef` wiring needs a recorder in `Tests/harness/wow/api.lua` before it can be
covered — until then that half is verified in game only.

Remaining, in the order a failure is most likely:

1. `/2 hello`, `/w <name> hi`, then `/r hi again` — channel and whisper routing through the box,
   including whether `/r` finds the right target. Untested; `/use` clearing taint says nothing about
   whether OUR routing sends the line to the right stream.
2. Tab-complete a NAME in the box. Tab-cycling the channel is confirmed (the chip and border follow),
   but name completion is a different code path in the client.
3. Watch for `Interface action failed because of an AddOn` during ordinary play. `/use` working is
   strong evidence and not proof: taint can be introduced by a path that only runs later.

**CONFIRMED IN GAME 2026-08-27: the chip names the channel.** Three separate defects had to be
fixed for one symptom — a chip reading a bare `1` — and each would have survived the other two
being fixed, so all three are recorded:

- **The chip rendered the channel NUMBER.** `ChatType()` returns the `channelTarget` attribute,
  which is the number, and `_refreshChip` did `label = tostring(target)`. Nothing resolved it.
  `GetChannelName(target)` answers the **INDEX first and the name second** — ElvUI destructures it
  as `chanIndex` and tests `== 0` — so reading the first return as a name yields the number back
  and looks like the bug being fixed. Index 0 is "not joined": there is no name to be had, so the
  number is left standing rather than blanked.
- **A numbered channel's colour lives at `ChatTypeInfo["CHANNEL"..index]`, not at
  `ChatTypeInfo.CHANNEL`.** Reading the plain type painted every numbered channel the same generic
  colour, which defeats the chip's whole job of carrying channel identity. Resolved from the SAME
  reading as the name, so the label and the colour cannot disagree about which channel is open.
- **The header hook never notified the plugin.** `ChatEdit_UpdateHeader` is what fires when the
  channel changes — Tab and `/1` both land there — and `onHeaderUpdated` suppressed the header and
  re-placed the box while leaving the chip alone. So the label fix ALONE would still have gone
  stale on the first Tab. `M.OnHeader(cb)` closes it, and `Restore` clears the callback because the
  hook itself cannot be uninstalled.

A zone channel's qualifier is dropped by `ChatFormat.ChannelLabel` (`General - Elwynn Forest` reads
`General`), splitting on Blizzard's own ` - ` separator rather than any hyphen, since a custom
channel may legitimately contain one.

Also fixed in the same pass: the caret's inset is now restated after the chip re-measures, and the
old `inset > 66% of the row -> snap to 33%` clamp is gone. That clamp moved the text LEFT, i.e.
underneath the very chip it was avoiding, so a long whisper target overlapped what was being typed;
the cap is now "leave `MIN_INPUT` for typing".

**These four changes have NO test coverage** — they landed while the suite was on hold, verified by
`luac -p` and the undeclared-global sweep only. `ChannelLabel`, the `CHANNEL<index>` colour key and
the `OnHeader` notify each need a spec, and the harness models no `GetChannelName` yet.

---

## 7. Phases

Every phase ends with `lua Tests/run.lua` green and each new behaviour mutation-verified. Phases
4 and 5 additionally end with an **in-game checkpoint**, because they are where the harness
cannot help.

**Phase 0 — Recon. DONE.** Measured defaults recorded in §5.

**Phase 1 — Harness. DONE.** Suite 5104 → 5144, 12/12 mutations caught.
`ScrollingMessageFrame` is a real subtype in `Tests/harness/wow/frame.lua` (AddMessage,
GetNumMessages, GetMessageInfo, the cap, fading, insert mode, hyperlinks, the scroll family,
AtBottom, the font pair) and in `widget.lua`'s `INHERITS`. `api.lua` gained `ChatTypeInfo`,
`ChatTypeGroup`, `GetChatWindowMessages` carrying the measured defaults, `NUM_CHAT_WINDOWS`, and
`C_ChatInfo.SendChatMessage` with the bare global as its shim. `H.chat`, `H.getSentMessages`,
`H.resetSentMessages`, `H.setChatWindowMessages`, `H.getChatLines` and `H.clickHyperlink` are on
`H`; `OnHyperlinkEnter`/`OnHyperlinkLeave` were added to the scriptable-name allowlist.

Both refusals from the plan are modelled and each is pinned by a mutation: `AddMessage` exists
only on the log meta so a plain `Frame` raises, and a log with no font draws nothing while still
reporting its messages. `_hasFont` is registered in `00_harness_spec`'s `HARNESS_ONLY` list so it
cannot become a second `GetLine`.

What the harness still **cannot** prove, so do not read a green run as covering it: the
hardware-event gate on `SAY`/`YELL`/`CHANNEL` is not modelled at all, so a recorded send is not
evidence the client would have allowed it.

**Phase 2 — Components. DONE.** Suite 5144 → 5217 (79 files), 17/17 mutations caught.
`Components/MessageLog.lua` (208 lines, 34 specs), `Components/Chip.lua` (134) and
`Components/Avatar.lua` (204) — the latter two share `Tests/spec/61_chip_avatar_spec.lua`
(39 specs). All three are in the `.toc`.

Two primitives were extended rather than bypassed, which is the rule when a primitive lacks the
shape you need:
- **`Components/Text.lua` now accepts a LITERAL `{r,g,b,a}` in `SetColor`** as well as a token
  key. Required because a chat channel's colour comes from `ChatTypeInfo` — a game fact — and
  painting it from a token would make SuuUI disagree with the rest of the player's UI. The key
  path is untouched.
- **Two new tokens, `opacityChipFill` and `opacityChipBorder`**, in both themes and the theme
  editor. Their own pair rather than sharing the `opacityAccentSubtle` / `opacityWarningWash`
  family, because a chip is tinted by a game fact rather than by an intent token.

Nothing in Phase 2 renders in game yet — no plugin instantiates any of it.

**Phase 3 — Formatting and routing. DONE.** Suite 5217 → 5274 (80 files), 23/23 mutations caught.
`Plugins/Chat/ChatFormat.lua` (182 lines) and `Plugins/Chat/ChatRouting.lua` (147), both pure —
no frames, no components, no settings reads — with `Tests/spec/62_chatformat_routing_spec.lua`
(57 specs). The GlobalStrings are in the harness, shape-accurate per 5b. Both files are in the
`.toc` but nothing instantiates them, so nothing renders.

`ChatFormat` exposes `Body`, `StripChannelPrefix`, `PlayerLink`, `Timestamp`, `Tag` and `Line`.
`ChatRouting` exposes `TABS`, `TAB_GROUPS`, `EventsFor`, `EventsForTab`, `BuildEventMap`,
`WhisperTargets` and `ConversationKey`.

Three things mutation testing changed rather than merely confirmed:
- **A real ordering bug**: the `TEXT_EMOTE` branch sat *below* the globalstring lookup, so it fell
  through to the unknown-type fallback and printed the sender's name twice. Caught by the spec on
  its first run.
- **Two fixtures could not discriminate.** A special-type message needs a literal `%%` in it,
  because that is the only thing that separates "message appended to the format string" from
  "message passed as an argument". And proving `BuildEventMap`'s first-tab-wins rule needs a
  staged cross-tab overlap — determinism alone passes under always-overwrite, which is
  deterministic too, just wrong.
- **One survivor was genuine redundancy**: `StripChannelPrefix` held an anchored match *and* an
  anchored gsub, and the match already gated the gsub, so the second anchor could never matter.
  Collapsed to one `find` — two copies of one pattern are a drift risk, not insurance.

**Phase 4 — Single-log MVP → in-game checkpoint.** NEXT, and the first thing that renders.
**SPLIT into 4a and 4b** (decided 2026-08-27, unattended), because suppression is the one part of
this plugin that can break the player's chat on next login and the harness structurally cannot
verify it — the same reason the inventory feature opened by slash command with no suppression, so
the new window could be compared against Blizzard's side by side.

- **4a — additive. DONE.** Suite 5274 → 5305 (81 files), 14/14 mutations caught.
  `Plugins/Chat/Chat.lua` (219 lines) plus `Tests/spec/63_chat_plugin_spec.lua` (31 specs). The
  plugin, its full schema, one frameless log fed by `ChatFormat` + `ChatRouting`, the resting
  channel chip, and a moveable wrapper. Blizzard's chat is untouched. **This renders — it is the
  first thing to look at in game.**

  Two decisions the build forced, both departures from what this document said before:

  - **4a puts EVERY tab's traffic in the ONE log.** A General-only log shows no guild and no
    trade chat at all, since Guild is its own tab under the ruling, which makes a poor thing to
    judge the concept against. The event map is still built and asserted, so the routing is proven
    before Phase 6 depends on it; Phase 6 splits the one log across the rail.
  - **The chip states the default channel and does NOT read the sticky flags.** `sticky = 1` in
    `ChatTypeInfo` means "this type may be remembered", not "you last spoke here" — say, party,
    raid, guild, officer and whisper all carry it — so reading it returns whichever type is
    checked first: arbitrary dressed as authoritative. Real tracking lives on the edit box, which
    Phase 5 adopts. Until then the chip is honest rather than clever.

  One unrelated fragility fixed on the way: four `40_edit_mode_spec` guide-snap tests assumed a
  known set of registered moveable frames, so the chat window's own registration pulled an axis
  they expected untouched. They now clear the moveable registry before staging their two frames,
  which makes them robust against every future plugin rather than just this one.

- **4b — suppression. DONE.** Suite 5307 → 5335 (82 files), 16/16 mutations caught.
  `Plugins/Chat/BlizzardChat.lua` (155 lines) plus `Tests/spec/64_chat_suppress_spec.lua`
  (28 specs). `hide_blizzard` is a top-level toggle defaulting on, outside every section.

  **Much smaller and safer than the action bars' equivalent, for two reasons worth stating.** Chat
  frames hold no secure templates, so nothing here is refused in combat — the action bars had to
  unregister `ActionBarController` precisely because `Hide()` loses a race the client wins during a
  fight, and there is no such race here. And **we WANT Blizzard's frames alive and receiving**,
  because the mirror reads off them, so unregistering anything would break the thing this file
  exists to preserve. Nothing is one-way, so **no ReloadGuard** — the escape hatch is one toggle.

  Suppression is therefore purely visual: reparent onto a permanently hidden anonymous holder. A
  child of a hidden parent renders nothing whatever its own shown flag says, so there is no
  re-show to fight. `IsShown()` and `IsVisible()` disagree on purpose, and a spec asserts that.

  **The mirror is a HOOK, never a replacement.** Replacing `AddMessage` on a Blizzard chat frame
  taints 10/10 times and is what retired LS: Glass; the filter-only alternative loses left and
  right click on player names. The discriminator between chat and addon output is the **chat-type
  id**: Blizzard's handler calls `AddMessage(text, r, g, b, info.id)` while `print()` arrives as
  `AddMessage(text)` with nothing after it, so a call with no id is the only kind mirrored —
  otherwise every chat line would double, since our own `CHAT_MSG` registration already formatted
  it. The hook cannot be uninstalled, so it is disarmed by clearing its callback.

  Three defects mutation testing found, one of them a real design flaw:
  - **`originals` was recorded once and never refreshed**, so toggling suppression off and on after
    another addon had moved a frame would restore it to where it lived at login, not where it lives
    now. Re-recorded on every genuine park; deliberately not on a re-park, because that would
    capture the hidden holder itself and make the chat unrecoverable. Both halves are pinned.
  - Two guards were unreachable and were deleted rather than left as untestable defence: `park`'s
    already-parked early return (removing it also makes Suppress **self-healing** against another
    addon stealing a frame) and `unpark`'s flag check (`Restore` iterates that very table).

  **The harness gained Blizzard's chat frames** — `ChatFrame1..10` as real `ScrollingMessageFrame`s
  with their tabs, `GeneralDockManager`, `ChatFrameMenuButton`, `DEFAULT_CHAT_FRAME` — and
  `print()` now routes through the default frame as the client's does, so the mirror is tested
  through the real path rather than by calling `AddMessage` by hand.

**CONFIRMED IN GAME 2026-08-27.** The window renders and messages arrive ("ah yes, a line
appears"). The first report was "I only see one chip saying say", which is the CORRECT empty state
and worth recording as such: a frameless log with no background, no border and no scrollback import
draws literally nothing until a message arrives, so on a quiet login the chip is the only visible
pixel. Two assertions were added rather than sending a probe — the log has a real height, and it
sits above the chip — because that symptom is the same shape as the `530x0` host-container bug this
project has already shipped once.

**It deliberately does NOT seed from Blizzard's scrollback.** Their buffered lines are already
composed with their own `[Guild]` brackets and no tag column, so the first lines after a `/reload`
would look different from every line after them, which undermines the tag column itself.
Empty-on-reload is the accepted cost until history persistence lands in Phase 8.

Still unverified at 4a and needing an eye: chip and tag SIZING (both `fontSizeSm`, 11, against the
mockup's implied ~8px), whether the default 460×180 at bottom-left overlaps the action bars, and
whether the timestamp column keeps names aligned across rows.

**Phase 5 — Input adoption → in-game checkpoint.** Reparent `ChatFrame1.editBox`, skin it, wire
the chip to the sticky channel, Tab cycling. **This is where the taint risk lands.** Verify in
game: `/cast`, `/target`, a macro, `/2 hello`, `/w name`, `/r`, shift-click an item from bags,
and Tab-complete a name — then check for `Interface action failed because of an AddOn`. Do not
feed `AddHistoryLine`; keep our own edit history in SavedVariables, as ElvUI does and for the
same stated reason.

**Phase 6 — Rail and channel tabs.** The `Avatar` rail, tab switching, per-tab routing, hover
expansion. One `MessageLog` per tab, acquired lazily through `SuuUI.Pool` on `"chat.log"`, shown
and hidden rather than re-rendered — tabs cannot share one frame because their fading differs.

**Phase 7 — Conversations. PARTLY DONE (2026-08-27), untested.** Whisper tabs keyed by
`name-realm` and created on first receipt (Phase 6), **history persistence and rehydration**, and
**unread counts** have landed. `/r` and the `REPLY`/`REPLY2` bindings and the pre-targeted chip
remain.

**Persistence.** `SuuUIChatHistory`, per-character — chat is per-character, and the blob is bulky
enough that it does not belong in `SuuUIConfig` alongside small config. The store is built with
`ChatStore.Restore(SuuUIChatHistory)` rather than `NewStore`, so a fresh install and a returning
player are ONE path; the blob's own depth is discarded in favour of the SETTING, so lowering the
slider between sessions trims on the next login. Written at `PLAYER_LOGOUT` only.

Replay reuses the live `_render`, so a restored line is composed identically to a new one, and it
deliberately does NOT go through `_store:Add` — `Restore` has already populated the store, and
re-adding would renumber every sequence and destroy exactly the interleaving that restoring by
sequence exists to preserve. Routing is **re-derived** rather than read from the record's saved
`panels`, because the panel set and `whisper_mode` can both have changed since the write.

**Fading changed model, and the default is now OFF.** Per-line fading cannot express "already
faded": the client starts a line's fade clock when the line is ADDED, so replayed history is
`fade_after` seconds from fading however old the messages are — and then all of it fades out
together, which reads as the UI breaking. `MessageLog` therefore gained whole-buffer
`SetFaded(bool)` (frame alpha) alongside per-line fading, and restored history is left fully faded
when fading is on. Hovering the log reveals it, which also calls **`ResetAllFadeTimes()`** — without
that a revealed line vanishes again on the next frame, its own clock having expired long ago. That
call was read off ElvUI, which makes it immediately before its own frame fade-in.

Two consequences that would each be a bug on their own: a **live** message clears the fade, or the
first line after a reload lands in an alpha-0 buffer and is invisible until the player happens to
hover; and hover does **not** re-fade on leave, because per-line fading expires the lines again on
its own clock and re-hiding them the instant the cursor left would lose the text mid-read.

**Unread counts.** `Avatar` already drew the badge and nothing had ever set it — the same unwired
component as the hyperlinks and the tooltip before it. The active panel never counts, since a badge
over the tab you are reading can only say "you have read this"; the count is cleared for the panel
being opened ONLY, so the badge means "waiting for you" rather than "since you last switched tabs";
and a rebuilt rail row is seeded from the tracked table, because the rail rebuilds whenever a
conversation appears and a rebuild that reset every badge would discard what it exists to advertise.
Replay is guarded, or every badge would read 50 on login.

**`AT_BOTTOM_CHANGED` is still unconsumed.** That is the fourth signal `MessageLog` emits and the
data source for Phase 8's jump-to-bottom, which is not built — so it is an unbuilt feature rather
than dead wiring, unlike the three above.

**CONFIRMED IN GAME 2026-08-27: the rail and its unread badges.** Three rounds of screenshots, and
the first two were spent adjusting sizes when the bug was never a size:

- **The disc was pinned to `sizeControlSm` (18) with an 11px glyph**, which made the channel
  unidentifiable at a glance. It is now a plugin SETTING (`rail_size`, default 30, "Channel Icon
  Size") per the token-or-setting split — one widget's own dimension, not design language — and the
  glyph steps sm → md → lg → xl with the diameter, since pinning it at `sm` meant growing the disc
  bought no legibility at all. The rail's own width reads the same setting or a larger disc is
  clipped by a rail sized for the old constant, and the slider REBUILDS the rail because the size is
  baked into each `Avatar` at construction.
- **The badge was sized from the DISC and that is wrong in both directions.** At 45% of an 18-unit
  disc it eclipsed the initial entirely — a panel became unidentifiable exactly when it had something
  to tell you — and at 45% of 30 it was too short for its own digit. What a badge must fit is its
  TEXT; where it sits relative to the disc is the anchor's job. It now derives from
  `TextMetrics.Box` on the count and widens for a multi-digit value, which the `Pill` it was already
  built from supports and a forced square never could.
- **The real fault, and the one that took three rounds: a missing `box:Layout()` after `SetText`.**
  `Components/Text` emits `SIZE_CHANGED` on a HEIGHT change only — it owns its height and lets the
  layout assign its width — so a count going from `""` to `"2"` changed the width with no signal
  behind it, the container never re-flowed, and the glyph kept the zero-width box it had been laid
  out with while empty. That is why the number drew BESIDE the badge rather than in it, and why two
  rounds of resizing could not fix it. `Components/Divider.lua` already carried the same call for
  the same reason. `SetInitial` had the identical latent bug, invisible only because construction
  lays out after setting the initial.

Two things this leaves behind. A **height floor must come from the LINE HEIGHT, never the point
size** — `GetFontSize("sm")` is 11 while an 11px line occupies about 13, and a box at exactly the
metric is a CLIP in this client. And `SuuUI.Chat_GetWindow()` now exists so an in-game probe reads
the component's own state rather than a frame located by guessing a global name.

**Assertable today and worth pinning the moment tests resume:** `H.expectTextNotClipped` exists for
precisely this defect and would have caught it on the first round, `IsMouseEnabled` covers the
hyperlink `EnableMouse`, and `H.box`/`H.expectInside` cover the badge sitting on its disc.

### Numbered channel traffic was being LOST

**A group no panel claims is a group the player never receives.** `ChatPanels.Events` builds the
event list from the panels' own `groups`, and no default panel claimed `CHANNEL` — so
`CHAT_MSG_CHANNEL` was never registered, and with Blizzard's chat suppressed every `/1`, `/2 Trade`
and custom-channel line was silently dropped. Found by writing the spec that fires it, after noticing
that `CHAT_MSG_CHANNEL` appeared in no spec at all; the probe read `registered: false, of 38 events`.

Fixed by adding `CHANNEL` to **General's** groups. A channel is people TALKING, so it belongs with
conversation under the same rule that keeps loot and XP in the Log — and this is the floor rather
than the design: it stops messages being lost, and nothing about it prevents a joined channel from
also getting its own panel.

**OPEN QUESTION, pinned as an `xit` rather than guessed:** the ruling was that joined channels "can
have their own panels", which reads as CONFIGURED — but whispers auto-create theirs on first receipt,
so the two mechanisms are inconsistent as they stand. Whether a busy Trade channel should earn its
own rail row, and whether that is opt-in or automatic, is Domenik's call.

**The generalisable hazard:** a panel's `groups` list is not just a routing filter, it is the
SUBSCRIPTION. Removing a group from every panel silently unsubscribes the event, so the failure is
total and invisible rather than a misrouted line. The spec now asserts the registered event list, not
only where a line lands — an unregistered event cannot even be staged into a failure.

**Phase 8 — Polish. PARTLY DONE (2026-08-27), untested.** Jump-to-bottom has landed, and building it
exposed that **the log could not be scrolled at all**: `MessageLog` shipped `ScrollUp` / `ScrollDown`
/ `PageUp` / `ScrollToTop` / `ScrollToBottom` and **nothing ever delivered a gesture** — no
`EnableMouseWheel`, no `OnMouseWheel`, anywhere. The buffer was effectively write-only, so the
history the store persists was in there and unreachable, and jump-to-bottom would have been an
affordance for a state the player could not enter. That is the FOURTH instance of the same pattern
in this plugin after the hyperlink click, the ActionButton tooltip and the unread badge: a component
exposing capability that no owner ever wired.

The wheel lives in the COMPONENT — a wheel script in plugin code is forbidden outright
(`UI_SIGNALS.md`), and a log whose scroll methods nothing can reach is not a scrollable log, the same
argument that puts the hover reveal there. Shift jumps to an end rather than paging, matching
Blizzard's own chat because that is muscle memory rather than a preference.

Jump-to-bottom itself consumes `AT_BOTTOM_CHANGED`, the last signal `MessageLog` emitted that nothing
read. It is a stack child of the log box so it OVERLAYS the corner rather than taking a row — a log
that shrank when the button appeared would reflow its text every time you scrolled up. Its count is
the lines that arrived on the ACTIVE panel while it was scrolled away: a panel you are not looking at
already has its rail badge, and this answers the different question of "you are reading history and
the conversation has moved on". Reaching the bottom clears it, rather than the click doing so, so
scrolling down by hand and pressing the button end in the same state. The label is ASCII `v` for the
reason `Accordion`'s chevron is: the client's faces do not reliably carry the geometric arrows.

The signal is connected in the POOL FACTORY and reaches the plugin through `SuuUI.Chat_GetWindow()`
rather than a captured `self`, because the factory is registered once per session and outlives any
one plugin instance — a captured plugin would go stale across a disable/enable cycle while the
closure kept it alive.

**`/r` and the reply bindings need NO code.** Nothing in the plugin handles them because Blizzard's
own binding drives the edit box we adopted, and suppression only reparents `ChatFrame1` rather than
unregistering its events, so the reply path stays intact.

**The reply KEY is deprioritised: Domenik does not use it (2026-08-27).** So the `REPLY`/`REPLY2`
binding is off the verification list and off the build list — do not spend a round on it. `/r` typed
as TEXT is a different question and still matters, because that goes through the box's own parser
and then through our routing.

**Harness gap:** `EnableMouseWheel` and `OnMouseWheel` delivery are not modelled, so the wheel is
verifiable in game only until a recorder is added. Remaining in Phase 8: copy-a-line and copy-buffer
via `GetMessageInfo`, and URL detection.

### The scroll getter, and a harness that invented a method

**CONFIRMED IN GAME 2026-08-27: the wheel scrolls, and jump-to-bottom appears and clears.**

**MEASURED on this client: the getter is `GetScrollOffset`, and `GetCurrentScroll` does not exist.**
The component called the latter, so the first wheel turn raised `attempt to call a nil value` 29
times — and the reason the suite had nothing to say about it is that
`Tests/harness/wow/frame.lua` **modelled the method under the invented name**. Seven assertions in
`00_harness_spec.lua`'s scroll block passed against an API the client does not have.

Corrected by renaming the harness method and its seven call sites, deliberately **without** aliasing
both spellings: modelling a method the client lacks is precisely what let this ship, so a permissive
model is the bug and not the fix. The production guard was likewise collapsed to the one measured
name once the other branch became unreachable in both game and suite.

The rest of the surface was swept in the same probe and is sound: `AtBottom`, all six scroll methods,
`AddMessage`, `Clear`, `GetMaxLines`, `SetMaxLines`, `GetNumMessages`, `GetMessageInfo`, `GetFading`,
`SetFading`, `SetTimeVisible`, `SetFadeDuration`, `ResetAllFadeTimes`, `SetInsertMode`, `SetJustifyH`,
`SetHyperlinksEnabled` and `EnableMouseWheel` all exist. `GetNumMessages` and `GetMessageInfo`
mattering most, since Phase 8's copy-buffer is built on them and would have failed the same way.

**The generalisable lesson, and it is the third time this shape has cost this project a round:** when
a spec passes and the feature fails in game, suspect that the HARNESS models something the client
does not. Audit the client methods a component calls against a live probe rather than against the
harness, because the harness is where the optimistic assumption lives.

---

## 7b. Concept fidelity — three open questions for the first render

The mockup was HTML at small scale, so three of its values have no direct WoW equivalent. Each
is resolved conservatively below and each wants an eye at the Phase 4 checkpoint.

| Mockup | Shipped | Why, and the fix if it looks wrong |
|---|---|---|
| chip text ~8–10px, uppercase, 0.5px letterspacing | `fontSizeSm` (11), caller's own case, no letterspacing | The concept's own design system states 11/13/15/18, so the mockup's 8px was a preview artefact. **WoW has no `text-transform` or letter-spacing at all** — the caller passes the literal string. If chips read heavy, the fix is an `fontSizeXs` token |
| inactive rail avatars dimmed to 50% | class disc always full strength; active state rides the LABEL colour (muted → text) | The concept's own label rule says exactly this, and it uses existing tokens. A dimmed class colour also reads as a *different class*. If the rail needs more separation, an `opacityRailIdle` token is the fix |
| chip fill 12% / ring 40% | `opacityChipFill` 0.12 / `opacityChipBorder` 0.40 (Modern: 0.14 / 0.45) | Taken from the concept directly and made themeable |


---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Message formatting is larger than it looks (~28 event types) | Phase 3 is isolated and pure; drive it from GlobalStrings, not hand-written formats. If it overruns, v1 can ship fewer routed groups — it cannot ship them formatted wrongly |
| Taint from edit-box adoption | Reuse rather than replace; hook, never overwrite; keep state in side tables, never as new keys on Blizzard chat frame tables; our own edit history |
| Harness passes a broken chat | Model refusals as well as capabilities (Phase 1); assert structure, not just geometry |
| Player-name right-click degrades | Preserve the original `lineID` in the link and pass a real Blizzard chat frame as `SetItemRef`'s 4th argument — dropping either is the usual cause |
| `fontFamilyMain` is Friz Quadrata, a serif | None of this reads "modern" in it. Register a sans face via `Fonts:Register` as part of the feature, not after |
| Fifth embedded library (`LibChatAnims`) | Decide in Phase 0. By `architecture.md`'s own bar it is arguably not interop, so the default answer is no — revisit only if tab-flash taint is observed in Phase 5 |

---

## 9. Open questions

1. ~~The real per-window routing defaults.~~ **Answered** — measured in §5. Phase 0 recon is
   complete and nothing is blocking.
2. **Combat log.** Revised by the dump: window 2 is not purely the combat-log addon, it carries
   six real `CHAT_MSG_*` groups. v1 folds those into General and neuters window 2 with the rest;
   the `COMBAT_LOG_EVENT` combat log itself is still out of scope.
3. **`LibChatAnims`.** Recommendation: no, pending Phase 5 evidence.
4. **Rail side.** Left in the current design; right is one anchor change if preferred.
