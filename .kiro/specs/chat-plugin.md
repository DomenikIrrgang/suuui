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

Windows 4–10 being empty means our tabs owe nothing at all to Blizzard's window indices — we
neuter all ten and index conversations by our own keys.

**How the three windows map onto v1 tabs:** window 1 splits into General (everything except the
channel and whisper groups), Guild, Trade and the per-channel tabs (from `CHANNEL`), and one
conversation tab per whisper partner. Window 2's six groups join General. `VOICE_TEXT` is
dropped — it carries nothing on this client.

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
{ key="fade_channels",      label="Fade Channel Messages",  type="toggle",  default=true },
{ key="fade_after",         label="Fade After",             type="slider",  default=8, min=2, max=60, step=1,
  enabledIf="fade_channels" },

{ key="",                   label="Conversations",          type="section" },
{ key="whisper_tabs",       label="Whispers Get Own Tab",   type="toggle",  default=true },
{ key="whisper_in_general", label="Also Show In General",   type="toggle",  default=true,
  enabledIf="whisper_tabs" },
{ key="rail_expand_hover",  label="Expand Rail On Hover",   type="toggle",  default=true },
{ key="history_depth",      label="Remembered Messages",    type="slider",  default=100, min=0, max=500, step=10 },

{ key="",                   label="Internal",               type="section" },
{ key="position",           type="position" },
```

Notes: `show_timestamps` defaults **on**, unlike Blizzard's — the column was asked for, so it
should be there without hunting. `fade_channels` never applies to conversation tabs; that is not
a setting, it is the design rule. `history_depth = 0` disables persistence entirely.

`whisper_in_general` defaults **on**, which mirrors a whisper into General *as well as* its own
conversation tab — Blizzard's `popout_and_inline` behaviour. It is on because this client is
currently at `whisperMode = inline` (see §5), so the rail is unfamiliar and a whisper that only
appears somewhere the player is not yet looking is a missed whisper. Turn it off once the rail
has become where you look.

Deliberately absent from v1: search, chat logging to file, per-tab font overrides, keyword
alerts, spam filtering. All are in the LATER tier.

---

## 7. Phases

Every phase ends with `lua Tests/run.lua` green and each new behaviour mutation-verified. Phases
4 and 5 additionally end with an **in-game checkpoint**, because they are where the harness
cannot help.

**Phase 0 — Recon.** Dump the real client state; decide the two open questions in §9. Output is
values written into this document, no code.

**Phase 1 — Harness.** `ScrollingMessageFrame` as a real frame subtype in
`Tests/harness/wow/frame.lua` (`AddMessage`, `GetNumMessages`, `GetMessageInfo`, `SetMaxLines`,
`SetFading`, `SetTimeVisible`, `SetFadeDuration`, `SetInsertMode`, `SetHyperlinksEnabled`, the
scroll family, `AtBottom`), the chat globals in `api.lua`, `H.chat(event, ...)` to fire a
`CHAT_MSG_*` with a realistic payload, and `H.getSentMessages()` recording
`C_ChatInfo.SendChatMessage`. Covered in `00_harness_spec.lua`.

> **The harness is the biggest correctness risk in this plan, not the plugin.** Its documented
> failure mode is being *permissive*: it hands every frame every method, so a stub
> `ScrollingMessageFrame` would let a broken chat pass green exactly as the combat-lockdown and
> hidden-frame gaps did. So model the **refusals** too — `AddMessage` must not exist on a plain
> `Frame`, and a message frame with no font object must report zero visible lines.

**Phase 2 — Components.** `MessageLog`, `Chip`, `Avatar` + three specs. No plugin yet.

**Phase 3 — Formatting and routing.** `ChatFormat` and `ChatRouting` as pure modules with a
spec per event family. This is the largest single chunk of work in the plugin: it is
re-implementing what `ChatFrameUtil.MessageEventHandler` does across ~28 event types, and it is
the reason ElvUI restyles instead of replacing. Build it from the client's own GlobalStrings
(`CHAT_SAY_GET`, `CHAT_WHISPER_GET`, `CHAT_GUILD_GET`, …) rather than hand-written formats, so
locale support is free and the output matches what players already read.

**Phase 4 — Single-log MVP → in-game checkpoint.** One General tab, frameless, fading,
timestamps, the resting chip (display only, no typing yet), Blizzard frames neutered and
`DEFAULT_CHAT_FRAME` mirrored. First moment the thing is real. Verify: messages appear, links
hover and click, other addons' `print()` arrives, `/reload` does not double-register.

**Phase 5 — Input adoption → in-game checkpoint.** Reparent `ChatFrame1.editBox`, skin it, wire
the chip to the sticky channel, Tab cycling. **This is where the taint risk lands.** Verify in
game: `/cast`, `/target`, a macro, `/2 hello`, `/w name`, `/r`, shift-click an item from bags,
and Tab-complete a name — then check for `Interface action failed because of an AddOn`. Do not
feed `AddHistoryLine`; keep our own edit history in SavedVariables, as ElvUI does and for the
same stated reason.

**Phase 6 — Rail and channel tabs.** The `Avatar` rail, tab switching, per-tab routing, hover
expansion. One `MessageLog` per tab, acquired lazily through `SuuUI.Pool` on `"chat.log"`, shown
and hidden rather than re-rendered — tabs cannot share one frame because their fading differs.

**Phase 7 — Conversations.** Whisper tabs keyed by `name-realm`, unread counts, persistence and
rehydration, `/r` and the `REPLY`/`REPLY2` bindings, the pre-targeted chip.

**Phase 8 — Polish.** Jump-to-bottom with unread count, copy-a-line and copy-buffer via
`GetMessageInfo`, `MoveableFrame` + edit-mode registration, URL detection.

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
