# Open probes: the `/suu probe all` session

The hand-over of the probe session that started on 2026-11-15 and was read
on 2026-11-19 from a copy of the owner's saved variables. It serves the
review (`Docs/review-2026-11-15.md`: an item's ID is the finding's ID where
there is one) and the in-game checklist (`Docs/plans/core-ownership-checks.md`).

On 2026-11-19: **9 items wait, 29 have recorded** (25 watchers and the 4
instant checks), and one item is by hand only (`UIW-7.width`). Two of the 29
recorded nothing useful (HUD-UF-15 failed, UIW-11 is ambiguous) and one
answer was misread in the review until now (BAG-11); see "Answered".

## Open

What `/suu probe all status` lists, with what to do for each. Do the
fights in the open world or a dungeon, as you like; nothing needs a raid.

| ID | Question | What to do in game | Already recorded | What it decides |
|---|---|---|---|---|
| X-6.1 | Does Tab in a chat edit box in a fight (SuuUI replaces `ChatEdit_CustomTabPressed`) leave addon-written values, and is anything blocked later in that fight? | In a fight, open the chat input and press Tab, then finish the fight. | Nothing. (The instant taint check lists `ChatEdit_CustomTabPressed` as written by SuuUI: the replacement itself, as expected.) | X-6.1 (medium). Clean: write the answer into the comment at `WrapTab` and keep the replacement. Blocked or new values: take Tab another way (an override binding on Tab while the palette shows, or the edit box's `OnTabPressed` post-hook). May become moot with the chat rebuilt as a reskin of the game's frames. |
| X-6.2 | Escape in a fight with a SuuUI window and a protected Blizzard window open: does the Blizzard window close, and is anything blocked? | In a fight, have a SuuUI window (settings or talents) and the spellbook open, then press Escape. | Nothing. | X-6.2 (low). Blocked: one Escape handler for every SuuUI window (`SecureEscape`, or `OnKeyDown` with keyboard propagation as NPC dialogue does) and no more `UISpecialFrames` entries. Clean: record it and keep them. |
| CHAT-12 | Does opening the chat settings from a SuuUI chat tab taint, out of combat and in a fight? | In a fight, right-click a SuuUI chat tab and open its chat settings. | Out of combat (2026-11-15): `CURRENT_CHAT_FRAME_ID` written by SuuUI, the settings shown, nothing else new, nothing blocked. | CHAT-12 (medium). Refused or blocked in a fight: open the settings by a secure click on the game's own tab menu entry, or wait for the fight's end (`RunOutOfCombat`). Clean: close it with X-6.3 as "written, no harm seen". |
| CHAR-28 | The Pet tab clicked out of combat, then the Character window's side panes switched in a fight: does that taint (`PaperDollFrame.currentSideBar`)? | With a pet out (a hunter or warlock), click the Character window's Pet tab out of combat. Later, in a fight, open the Character window and switch its side panes (Stats, Titles, Equipment sets, Pet). | Nothing. | CHAR-28 (medium). Clean: record it beside the comment in `CharacterWindow`. Tainted or errors: switch through the game's own buttons with secure click overlays (`PaperDollSidebarTab4` for the pet, `Tab1` back to the stats). |
| CHAT-19 | Is the loot frame an edit mode frame, does looting and then edit mode taint, and is a toast off screen while a roll is open? | Loot something, then open edit mode. Separately, get a toast (an achievement, a new mount or pet) while a loot roll is open. | `LootFrame` has `SetPointBase` (an edit mode system frame), `GroupLootContainer` has none; after looting (2026-11-16) nothing blocked and nothing of the loot frame's addon-written. | CHAT-19 (low). The first half already says: move `LootFrame` through its Base methods, as the chat does. Edit mode tainted: the same, urgently. Toast off screen: the off-screen helper for the roll container must let toasts through (or not move the container while a toast anchors to it). |
| CHAT-25 | Greed on all with two Bind on Pickup rolls: one confirmation at a time? A party invite while a roll's confirmation is up: is the invite's popup on screen? | Use Greed on all when two or more Bind on Pickup items are up. Separately, get a party invite while a Bind on Pickup confirmation is up, with Notifications' requests off. | Nothing. | CHAT-25 (medium). One at a time: Greed on all must ask for each in turn (today all but one time out as passes). The invite hidden: SuuUI must show or host it while a confirmation is hosted. |
| BAG-16 | After a commodity's price is quoted again, what does the purchase charge: the first quote or the last? | Buy a commodity whose price changes after the first quote (another buyer took the cheapest). The probe only watches. | 5 purchases (2026-11-16 to 19), each quoted once and charged that quote. The sample list is full; only a purchase quoted twice records now. | BAG-16 is fixed (`740e3d27`: a new quote asks again) and holds either way. The answer goes into the header of `AuctionHouse/ItemView`; nothing to build. |
| HUD-DM-2 | Does a shaman's spellbook know Call of the Ancestors at a full login's `PLAYER_LOGIN`, when the totem bar is built? | Log in fully (not `/reload`) on a shaman who has Call of the Ancestors. | Nothing. | HUD-DM-2 (medium). Not known yet: keep the wanted totem page apart from the page in use (the finding's fix). Known: withdraw it. |
| HUD-CD-5 | Which of `HARMFUL\|PLAYER` and `HARMFUL\|!PLAYER` do a target's debuffs pass, on a hostile player and on a mob? | Out of combat, target a mob with your own debuff and a group member's on it (one a group member still fights, or one still alive when your fight ends). The hostile player half cannot be done here (see "Cannot be probed here"). | On a mob (2026-11-19): see "Answered". Own debuffs were not in the sample; the mob case was replaced 2 times of 3, so one better read (yours and others' together) can still take its place. | HUD-CD-5 (medium). Own debuffs pass `PLAYER` and not `!PLAYER` on a mob: the "only yours" / "only others'" split works on NPC targets. The finding is about player targets, which stay unprobed: whether to set the `!PLAYER` groups to 0 on player targets anyway is the owner's call. This item keeps the session armed for good (its player case never comes); see "Follow-ups". |

## How the session works

- `/suu probe all` runs the 4 instant checks again, arms every watcher not
  yet recorded and says how many answered and what waits. It never forgets
  anything.
- `/suu probe all status`: one line per waiting item with what to do, and
  how far it got (the cases missing, the samples so far).
- `/suu probe all off` disarms (hooks stay installed, doing nothing, until
  a `/reload`).
- `/suu probe all reset` forgets **every** result and starts over. Never use
  it unless you mean that: there is no way to forget one item alone (see
  "Follow-ups").
- **Dev builds only.** The release and readable profiles leave
  `src/Diagnostics` out, so `wowlua install --release` has no probes:
  install with `wowlua install` (no `--release`) or run `wowlua dev`.
- Armed stays armed across `/reload`, logouts and characters: at each login
  the watchers not yet recorded arm again (the login watchers read then).
  Each records once (or its first few samples) and stops for good. When
  every armed item has recorded, it says so once and disarms itself.
- Results are in `SuuUIProbe.all` in the SavedVariables (`results`, by ID;
  `waiting`; `manual`). The game writes them at a `/reload` or logout, not
  before. `build` and `suuui` in that record are those of the last time
  `/suu probe all` was typed (here 2026-11-15, build 70888,
  0.17.0-dev+26b69c9), not of the build that recorded a later answer.
- The watchers only listen and read (`src/Diagnostics/Watch/Kit.wowlua` has
  their rules): no names stored, no game state changed, each under `pcall`.

## Answered

Every recorded item, oldest first. "Consequence" is what it means for the
review's finding; the review carries the same in the finding's `- probe`
line.

| ID | Recorded | Answer | Consequence |
|---|---|---|---|
| client | 2026-11-15 (instant) | Client 1.60.1 build 70888 (interface 16001), SuuUI 0.17.0-dev+26b69c9, API 0.47.0, when `/suu probe all` was last typed. | – |
| functions | 2026-11-15 (instant) | 32 of 35 functions the questions name exist; missing: `UnitAura`, `GetMouseFocus`, `GroupLootContainer.SetPointBase`. `LootFrame.SetPointBase` exists. | CHAT-19's question (b) answered: the loot frame is an edit mode frame, the roll container is not. |
| cvars | 2026-11-15 (instant) | 24 CVars SuuUI's modules write: 11 kept per character, 9 per account, 3 for the machine, 1 unknown. | Background for checks 4 and 5 of `core-ownership-checks.md`. |
| taint | 2026-11-15 (instant) | 9 values on the game's protected paths written by addon code: `ChatEdit_CustomTabPressed` (SuuUI's replacement), the slash command cache for commands typed (SuuUI's and another addon's), `ChatFrame1EditBox.autoCompleteParams`. | A baseline; X-6.1's replacement shows as expected. |
| KEYS-combat | 2026-11-15, in a fight | In combat lockdown, on the probe's own frame: `SetPropagateKeyboardInput` refused, `EnableKeyboard` allowed. | SET-1, UIP-5 and CHAT-1: UI/Dismiss's design is the one that works. Check 16 of the checklist answered. |
| CD-27.onleave | 2026-11-15 | `OnLeave` fires during `Hide()` when a frame hides under the mouse. | CD-27's stuck state can't arise; its fix stays as a safety net. |
| CD-24 | 2026-11-15 | `OnDragStop` fires when a frame hides mid-drag. | CD-24 withdrawn. |
| UIP-13 | 2026-11-15 | Before SuuUI registers: the reputation list has 1 callback, not owned by the frame itself; the Who page's filter dropdown has none. | UIP-13 stays open (unverified): the two registries read are clean. |
| CD-17 | 2026-11-15 | At a full login's `PLAYER_LOGIN` (and after two reloads) the active talent config is an ID. One character. | CD-17 withdrawn. |
| HUD-DM-1 | 2026-11-15, in fights | Your own damage meter source's `combatSpells` was never secret, in 2 fights. | HUD-DM-1 withdrawn. |
| UF-12 | 2026-11-15, in a fight | Re-anchoring the frame an aura container hangs on and `SetShown(false)` on a player-buff container: both allowed, on the probe's own container with no buttons shown. | UF-12 stays open (unverified): a container with buttons shown not tried. |
| UIW-11 | 2026-11-15, in a fight | Recorded "error" for SuuUI's bag slot button; Blizzard's first bag slot didn't exist. The watcher writes `ok and show(prot) or "error"`, which turns a `false` (not protected) into "error", so this most likely means "not protected", but a failed call reads the same. | Not settled. UIW-11 stays open (unverified). The watcher needs the and/or fixed and a re-run. |
| GRP-5 | 2026-11-15 | The world map closed out of combat, then opened in a fight: no new addon-written values, nothing blocked. No quest item used. | GRP-5 stays open (unverified) for the quest item. |
| UIW-7 | 2026-11-15 | After a listing was posted, 8 of the category buttons' fixed sizes were written by addon code; nothing else new; the post went through. | The write confirmed, no harm seen. The width after a resize is the by-hand item `UIW-7.width`. |
| GRP-9 | 2026-11-15 | After a search on SuuUI's Who page, a typed `/who` still printed to chat. | GRP-9 open (confirmed). |
| BAG-11 | 2026-11-15 | One macro with `#showtooltip` (an account macro): `GetMacroInfo` gave icon 3528279, neither the question mark (134400) nor its spell's icon (135907). | **Not a confirmation**, although the review recorded one: either that icon was chosen for the macro or a "?" resolves to something else. BAG-11 goes back to open (unverified). A re-run needs a macro made with "?" and `#showtooltip <a spell>`. |
| X-6.3 | 2026-11-15 | Chat settings opened from a SuuUI tab (out of combat): `CURRENT_CHAT_FRAME_ID` written by SuuUI; the next fight: nothing blocked, nothing new. | X-6.3 open: the write confirmed, no harm seen in one fight. |
| UF-25 | 2026-11-15, out of combat | 3 party members under crowd control (each aura typeless): the same aura passed `CROWD_CONTROL\|DISPELLABLE` and `CROWD_CONTROL\|!DISPELLABLE`, and also `HARMFUL\|DISPELLABLE`. The negation cannot split them. | UF-25 confirmed in game: a crowd control effect on another player shows in both of the frame's groups. Fix as the finding says (the `!DISPELLABLE` split only on your own frame). The watcher still fails silently in a fight (see "Follow-ups"). |
| COMM-senders | 2026-11-15 and 16 | `CHAT_MSG_ADDON` names a group member "Name Surname", equal to `GetUnitName(unit, true)`, never to plain `UnitName(unit)` (which gives the first name; the surname comes as its second return). The old record calls this case "a sender of another realm" because of that second return: there are no realms on Forever. | GRP-21 and GRP-26: the rank check of `src/Core/Comm.wowlua` compares the sender with `GetUnitName(unit, true)` first, so it finds the member and the pull countdown's "assist" rule works as designed. Check 9 of the checklist answered in its naming half. |
| HUD-4 | 2026-11-16, in a fight | A hunter with a ranged weapon, Auto Shot off: 12 melee swings, all `MainHand`, none `Ranged`. Shooting: 10 `Ranged`. | The case the finding feared does not happen for a hunter. HUD-4 narrowed: what is left is in the swing timer's code (the ranged row stays up to one shot after Auto Shot stops). A warrior with a bow not probed. |
| CHAR-27 | 2026-11-16, in a fight | Inside `PLAYER_LEVEL_UP` (level 1 to 2), `UnitLevel("player")` still gives the old level; the next frame gives the new one. | CHAR-27 confirmed (low): the open Spellbook renders with the old level. Fix: use the level the event carries. |
| MAIL-refusals | 2026-11-16 and 17 | 3 refusals while the mailbox was open: only `UI_ERROR_MESSAGE`, never `MAIL_FAILED` (`ERR_BANK_FULL` once; `ERR_INVALID_ATTACK_TARGET` and `ERR_TOO_FAR_TO_INTERACT` twice each, which are likely not take refusals: the watcher counts any red error while the mailbox is open). | BAG-2 (fixed) holds: Collect moves on by the error text and its backstop. The header of `Mail/Collect` says `MAIL_FAILED` arrives with the error, which the probe never saw (see "Follow-ups"). |
| CHAT-26 | 2026-11-16 to 18, in fights | 5 rolls (3 Bind on Pickup): the item's name was never missing and never secret at `START_LOOT_ROLL`. | CHAT-26 (fixed) holds; its fallback is not needed on this client but costs nothing. |
| GRP-4 | 2026-11-17, in fights | In 2 fights in a raid group of 5, every `GetRaidRosterInfo` field read was readable. | GRP-4 withdrawn (the harm needs secret values). Only a 5-member raid group; a full raid instance was not seen. |
| HUD-UF-3 | 2026-11-17, in fights | In 3 dungeon fights on a hostile NPC target (one classed `worldboss`), `UnitClassification` and `UnitIsBossMob` were never secret. (`UnitIsBossMob` is recorded as "error: false": the same and/or in the watcher; it returned false.) | HUD-UF-3 withdrawn. |
| HUD-UF-15 | 2026-11-17 | **The watcher failed**: at a dungeon fight's end it compared an engine aura button's `IsShown()`, a secret boolean to SuuUI's code, with `== true`. | Not answered, and done: it won't run again. HUD-UF-15 stays open (unverified). By the way it shows the engine's aura buttons answer `IsShown` with a secret at a fight's end. |
| ROLL-order | 2026-11-17 | 77 roll events over 3 rolls: the 3 `START_LOOT_ROLL` first; each vote line (`CHAT_MSG_LOOT`) followed by `LOOT_HISTORY_UPDATE_DROP`; `CANCEL_LOOT_ROLL` before that roll's "rolled" and "won" lines; `LOOT_ROLLS_COMPLETE` after the "won" line. The history's drop IDs (2, 4, 6) are not the roll IDs (1, 3, 5). | Reference for LootRolls; no finding. |
| LFG-opens | 2026-11-15 to 18 | 5 openings of the Group Finder, all by its key binding: SuuUI's search on opening was refused 0 times. | No finding. The comment above `SearchOnOpen` (`src/Units/GroupFinder.wowlua`) says such a search was refused on 2026-11-10, 11, 13 and 15; the fallback (search on the first click) stays harmless (see "Follow-ups"). |
| WHISPER-taint | 2026-11-19 | A whisper SuuUI started out of combat (a name clicked in SuuUI's chat) marked `ACTIVE_CHAT_EDIT_BOX`, `LAST_ACTIVE_CHAT_EDIT_BOX` and the edit box's `text` as written by SuuUI. A line sent in the following fight was **not** blocked, and `ACTIVE_CHAT_EDIT_BOX` read as the game's own again at that send. One observation (3 lines were sent in fights; the first one after the whisper answers). | The send block seen on 2026-11-15 needs more than this; most likely the name clicked in a fight (not probed). Nothing to fix now: the chat will be redone as a reskin of the game's frames. |

HUD-CD-5 is still waiting, but its mob half is in: on 2026-11-19, out of
combat, on a mob a group member fought: 1 to 4 debuffs per read, all from
other players by `sourceUnit` (readable); `HARMFUL|PLAYER` passed none of
them, `HARMFUL|!PLAYER` passed all, none passed both. So on a mob the
"mine / not mine" split holds for others' debuffs; your own were not in the
sample. Of 2,259 reads in fights, 2,212 raised "GetAuraDataByIndex():
Auras cannot be accessed when secret while tainted by 'SuuUI'", and none of the reads it kept came
from a fight: the rule `IMPLEMENTATION_PLAN.md` records, now seen by this
probe on the client too. 6 reads out of combat failed the same way
(probably at a fight's very end). The earlier version of this watcher read
only in fights and took the failed read for "no debuffs", so it could never
record.

## Cannot be probed here

- **HUD-CD-5's hostile player half.** The owner plays on a PvE ruleset: no
  hostile player can be targeted out of combat, and aura reads only work
  out of combat. The item will keep listing as waiting.
- **Anything about another realm.** WoW Forever has no realms, only
  rulesets. COMM-senders' old case "a sender of another realm" is a
  misnomer (the watcher now has one case, "a group member"). Findings that
  speak of realms (BAG-6 and X-10.1 "read across realms", GRP-3's and
  GRP-23's "same name from another realm") cannot be probed as written;
  restate them for rulesets before probing anything.
- **`UIW-7.width`** is by hand: whether the group finder's category cards
  keep the right width after the window is resized shows on screen only.
- **Answers recorded wrongly** (HUD-UF-15, UIW-11, BAG-11) cannot record
  again: they are done, and only `reset` forgets them (see "Follow-ups").

## Follow-ups from the answers

Code (none of it done here):

1. **CHAR-27**: the Spellbook's `PLAYER_LEVEL_UP` handler
   (`src/Units/Spellbook.wowlua`, the loop over `SPELLS_CHANGED` and
   `PLAYER_LEVEL_UP`) renders with `UnitLevel("player")`, which is still the
   old level there. Pass the event's level to the render.
2. **UF-25**: drop `!DISPELLABLE` from the crowd control group on other
   players' party and raid frames; keep the split on your own frame.
3. **HUD-4**: read `src/UI/SwingTimer.wowlua`: `UpdateRows` keys on
   `ranged.live` alone, so the ranged row stays up to one shot after Auto
   Shot stops. Next to the comment "Forever links the timers: a melee swing
   restarts Auto Shot too", note that no `Ranged` swing event comes with a
   melee swing while Auto Shot is off.
   Record the answer in `Docs/test-notes/ui-hud.md`, as the finding asks.
4. **CHAT-19**: move `LootFrame` through `SetPointBase` and its Base
   methods, as the chat does.
5. **`src/Core/Comm.wowlua`**: the rank check works (the sender equals
   `GetUnitName(unit, true)`, which `names()` compares first). Its comments
   still call the sender's form "unverified" and speak of other realms
   (the header's "rank" item, and `names()`): bring them in line.
6. **`src/Units/GroupFinder.wowlua`**: the comment above `SearchOnOpen`
   says a key binding opening's search was refused; 5 such openings were
   not refused (2026-11-15 to 18). Keep the fallback, change the comment.
7. **`src/Units/Mail/Collect.wowlua`**: its header says the game answers a
   refused take with `MAIL_FAILED` and the error text together; in 3
   refusals only the error text came. The run already copes; fix the
   header.
8. **BAG-32** (auction house): the probe of 2026-11-17 (`/suu probe ahbid`)
   saw a buyout through `C_AuctionHouse.PlaceBid` taken from SuuUI's own
   button, and `06ef3747` records that one placed from a confirmation
   dialog's OK was refused. Bid (Buy page), Bid again and the Bids tab's
   Buy out still place from `UI.Confirm`'s `onConfirm`. Give them Buy out's
   pattern (the price asked on the first click, placed within a second
   click on the button) or probe that path. A bid under the buyout was
   never tried (the auction in the probe took no bids). The header of
   `src/Units/AuctionHouse.wowlua` names two other addons, against the
   project's rule.
9. **Two errors from the owner's log of 2026-11-19** (a newer local dev
   build, not this branch; not investigated):
   - `src/UI/DamageMeter.wowlua:1035`, "bad argument #1 'src' to
     'DamageMeter:SourceRow' (DamageMeterCombatSourceSecret expected, got
     table)", three times around fights. On this branch line 1035 is the
     same: `SourceRow`'s `src` parameter, which a dev build checks against
     the declared shape of `DamageMeterCombatSourceSecret` (its required
     fields with plain types, for example `isLocalPlayer: boolean`,
     `classFilename: string`). The game's source table evidently doesn't fit
     that shape around a fight (a field missing or secret). It looks
     possible here in any dev build; release builds don't check. Likely the
     declaration, not the meter.
   - `src/Units/WorldMap/Quests.lua:274`, "attempt to compare a secret
     string value", once. On this branch, line 274 of
     `src/Units/WorldMap/Quests.wowlua` (`readCalendar`) is
     `e.calendarType == "HOLIDAY"`: a calendar event's type compared without
     a secret check. `readCalendar` runs when the map shows and on
     `CALENDAR_UPDATE_EVENT_LIST`, so a secret field there (in a fight, say)
     raises exactly this. Possible here.

The probe itself:

10. **Let HUD-CD-5 finish without its player case**, or mark that case by
    hand, so the session can end and disarm itself; today it keeps reading
    (about 2,400 reads so far) for a case that never comes.
11. **A way to forget one item** (`/suu probe all redo <id>`), so HUD-UF-15,
    UIW-11 and BAG-11 can record again without `reset`.
12. **Fix the three watchers**: HUD-UF-15 (`isShown == true` on a value
    that may be secret: check `isSecret` first), UIW-11 and HUD-UF-3
    (`ok and show(v) or "error"` turns `false` into "error"; the same
    and/or rule as everywhere). UF-25's watcher ignores `count()`'s
    `failed`, so in a fight it sees "no crowd control" instead of a failed
    read.
13. **Stamp each result with the build and SuuUI version** that recorded it;
    the record's `build` says only when `/suu probe all` was last typed.

## What testing the probe taught

- **A watcher must store why it skipped a read.** HUD-CD-5's first version
  dropped every read silently (no target, not attackable, a failed read
  counted as "no debuffs") and so recorded nothing for days with nothing
  to show why. The current one keeps the reads tried, each reason skipped
  and the last error, so a `/reload` always tells how far it got.
- **Aura reads fail in a fight.** Every addon read of auras raises in
  combat on Forever (`IMPLEMENTATION_PLAN.md` records it for the open world
  too; this probe saw 2,212 failures in fights, and none of the reads it
  kept came from a fight); a few
  failed right at a fight's end too. A watcher has to tell a failed read from an empty one (`count()`
  in `Watch/Auras.wowlua` has `failed` and `err` for that).
- **Reads must happen out of combat.** Aura reads, and anything else that
  is secret in a fight, answer only out of combat: on a target change, on
  `UNIT_AURA` out of combat, or after the fight has ended. The `todo` must
  say so, or the owner plays fights that cannot answer.
- **A function called through `pcall` has no name in the stack.** The game
  shows "in function <file:line>" for anything it calls from C (a `pcall`,
  a script handler, a secure hook's wrapper), so `ChatFrameUtil.SendTell`
  called through the stdlib's `pcall` never appears by name. Find the
  caller by file, not by function name.
- **A value that may be secret is never compared**, in a watcher too: the
  engine's aura buttons answer `IsShown()` with a secret, and the
  comparison ended HUD-UF-15's watcher.
- **`a and b or c` turns a `false` into `c`.** Two watchers recorded a
  readable `false` as "error".
- **An item whose case can't happen keeps the session armed for good**, and
  an item done with a bad answer can't record again. Both need a way out
  in the probe, not in the owner's play.
