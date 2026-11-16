# core-ownership: what to check in game

The `core-ownership` branch (API 0.47) was checked with `wowlua check`, the
whole test suite and the release and readable builds. Nothing in it was run
in the game. These are the checks only the client can settle, most important
first. Each names what to do and what to see.

## Lifecycle

1. **Mouseover bindings off and on.** Bind a key and a Shift-click, move
   Target to Alt-Left. Settings › Modules: turn Mouseover bindings off.
   Hover a mob and a unit frame: the key does its normal job, Shift-click
   does nothing special, a plain left click targets on unit frames (Game
   menu › Options › Click bindings shows Target on Left again). Turn it on:
   everything is back.
2. **A unit frame hiding under the mouse.** Hover a party member's frame and
   have them leave the group, so the frame hides under the mouse. Press a
   mouseover key while pointing at the world: it does its normal job, and
   world mouseover casting works without first entering another unit frame.
   Repeat in combat.
3. **Loot rolls at a reload.** In a group, `/reload` while a roll is open:
   the roll tray shows the roll at once.
4. **A module off at login gives its CVars back.** Turn Nameplates off,
   `/reload`: the nameplate alpha and scale CVars and `nameplateShowEnemies`
   are the game's defaults again (coming from an earlier version) or your
   own values (set on this branch). `/suu probe cvars` in a dev build records
   them.
5. **Two characters and a shared CVar.** With Guild on, log in on a second
   character, turn Guild off there, `/reload`: `communitiesShowOffline` is
   what it was before SuuUI on the first character, and turning Guild off on
   the first character afterwards changes nothing further.
6. **A reload in combat** with the game menu or a gossip window open, then
   leave combat: the window is not left invisible, and Auras, Cast bars and
   Notifications (they start in combat) work at once.
7. **A plugin loaded after login** (`/run C_AddOns.LoadAddOn("…")`) that
   assigns `function M:OnEnable()` after `RegisterModule`: its `OnEnable`
   runs.
8. **Timeline with a boss mod**, "Hide their own display" on: `/reload`;
   the boss mod's warnings stay hidden. Turn Timeline off: its bar does not
   come back on the next timer, and the boss mod's option is what it was.

## Addon messages

9. **How Forever names group members in `CHAT_MSG_ADDON`**, also members
   from another realm. The pull countdown is accepted only from the raid's
   leader or an assistant, matched by that name; a sender who can't be
   matched is refused. Have an assistant start a pull: your countdown runs.
   Have a plain member try: nothing. Have someone outside the group whisper
   the message: nothing.
10. **Older clients.** With one client on 0.17.0 and one on this branch:
    marks, convergences, campfires, raid specs and readiness still arrive in
    both directions.
11. **Readiness** in a raid: the panel fills within a few seconds of joining,
    and stays current, with the panel's own setting off on some clients.

## Keyboard

12. **Menus in a fight.** Open a right-click menu, the map's filter menu and
    a dropdown; start a fight with each open: movement and ability keys work
    throughout, a click outside closes it, and Esc closes it again once the
    fight is over. Open each during a fight: the same.
13. **The welcome panel** on a new character when a fight starts before any
    key was pressed: keys and clicks reach the game.
14. **A question over a dialog** (for example a confirmation over the
    talents dialog): closing the question leaves the dialog's dimming.
15. **The filter menu's size** at a UI scale where SuuUI's root and UIParent
    differ: it matches the other popups.
16. Whether `SetPropagateKeyboardInput` is refused in lockdown. If it is not,
    `UI/Dismiss` can be simplified (its header says how).

## Lists and windows

17. **Guild roster, contacts and Who** with long lists: scrolling is smooth,
    a refresh keeps the scroll position and the selection, right-click menus
    and tooltips are as before.
18. **The guild roster in a fight** with the mouse on a row (the secure row
    layer): scrolling does not error, and the row's click works again after
    the fight.
19. **The auction house**: close it while "Scan all" waits or reads; open it
    again: the scan is over, the button is ready or shows its wait, and the
    prices are those of the last complete scan.
20. **Exit Game** from SuuUI's menu, answer No while a fight starts: a later
    question's OK button does not quit the game. The guild invite dialog
    open when a fight starts: its button does not invite a stale name.
21. **Merchant**: queue several purchases, change the filter or walk to
    another vendor while they run: nothing else is bought.

## Plugins

22. Both example plugins load and work (`SuuUI_HelloPlugin`,
    `SuuUI_LevelBadge`).
23. A plugin that sets a field named like a module method (for example
    `M.Get = …`) gets an error that names the field.

## Bug fixes of 2026-11-15

The `high-bugs` branch (auction house bids, Collect all, loot rolls,
notification cards, the group finder ad, the NPC dialogue with AutoQuests)
was checked with `wowlua check` and the tests of the files it changed; the
emulator can't answer for the game in several places
(`Docs/wowlua-test-findings.md`, V50 to V56).

24. **The bid probe** (a dev build: `wowlua dev` or `wowlua install`;
    probes are left out of release builds). At the auction house:
    `/suu probe ahbid <cheap item>` (one that isn't a commodity). It
    places a **real** bid and a **real** buyout. Then `/reload` and read
    `SuuUIProbe.ahBid`: whether `PlaceBid` from SuuUI's button was refused
    (BAG-32), and which events and payloads followed (is `BID_ADDED`'s ID
    the auction's?).
25. **The bid flow.** Search an item with several auctions that take
    bids. Select one, let the list refresh (search again), press Bid: a
    question asks first, and the bid lands on the auction you chose. Type an
    amount below the least bid, one at or above the buyout, and one above
    your money: each is refused with its reason. Have someone outbid or
    buy the auction while the question is open: confirming bids nothing and
    the row shows it as it is now. A bid the house turns down is not
    reported as placed. Start a fight with the house open, and close the
    house in a fight: Buy out and Bid work again after it (no hidden button
    left over the window). A commodity whose price changes while its
    question is open asks again with the new price.
26. **Collect all with a refused item.** Three mails: money, a unique item
    you already carry, and a stack of something else, the unique one in the
    middle. Collect all: it skips the unique item, takes the rest and says
    what was left and why. With full bags: items aren't asked for, money is
    still taken.
27. **COD after the inbox changed.** Open a COD mail, press its item, and
    before confirming, have a new mail arrive or delete another one; then
    confirm: the money paid is the amount shown, and only that mail's item
    arrives. Delete or return the COD mail from another window meanwhile:
    confirming takes nothing. Close the mailbox with the question open: it
    closes too.
28. **Two rolls of the same item** (a dungeon boss dropping two of one
    item, or two greens of the same name): Need on one, Greed on the other;
    each answer reaches its own roll, one being decided leaves the other in
    the tray.
29. **The raid's frame rate while votes come in.** A 25- or 40-player raid
    with several rolls open: the frame rate holds while the votes arrive,
    with the tray open and folded.
30. **A notification card used again.** Get a note with two buttons (a
    group invite: Accept and Decline), let it go, then get a one-button
    note (a friend coming online): no button of the invite is left on it,
    and its Whisper or Invite has the right icon or none.
31. **The group finder ad.** Edit the ad under My listing, then leave it
    for 15 seconds or more (listed): your text stays. "From my listing"
    writes it again from the listing.
32. **Three quests accepted for you from one NPC** with AutoQuests on and
    NPC dialogue's "hide the rest of the UI" on: no flash of the dialogue,
    the rest of the UI doesn't fade out and back, the minimap doesn't
    blink. Then the same NPC with Shift held: the dialogue shows as before.
    With a full quest log (the game refuses the accept), if the game leaves
    the quest's page open: it shows about a second later.
33. **The group finder probe.** `/suu probe lfg opens`, then open the Group
    Finder a few times (its key, the micro menu, out of and in a fight),
    `/suu probe lfg opens off`, `/reload`: `SuuUIProbe.lfg.opens` says, per
    opening, how it was opened and whether the search on opening was
    refused.

## Performance fixes of 2026-11-16

The `high-perf` branch (the restyled windows' text styles, the encounter
timeline, health and roster changes on the unit frames) was checked with
`wowlua check`, the whole test suite and the perf scenarios; none of it was
run in the game.

34. **Restyled windows keep their text styles.** Open the character
    window's reputation pane and scroll it top to bottom and back; switch to
    the skills pane and back; open the guild roster and scroll it. Then
    change the theme (Settings › General › Appearance › Theme) with each
    open. Titles and category heads stay in the header face and the theme's
    colour (they follow the theme change), numbers stay in the tabular face
    and line up in their columns, and small text stays small: after the
    first redraw, after a scroll, after a pane switch and after the theme
    change alike.
35. **The encounter timeline.** Start its test mode (Settings › Insights ›
    Timeline, "Show a test timeline") or `/suu pull 15`. The abilities ride
    smoothly toward now, without jumps; under 10 seconds the time shows
    tenths, under 5 it turns amber; one that runs out leaves at once and
    the others close up. Switch Timeline › Show to List while it
    runs: the same order and times. Change the theme while it runs: the
    colours follow, nothing stutters. Cancel the pull (`/suu pull 0`): it
    leaves the timeline at once, which hides when nothing is left on it.
36. **Raid frames: health.** In a raid (or the raid frames' test mode),
    watch frames take damage and heals: the health bar, the heal-prediction
    and absorb overlays (also a shield past full health), and the ghost bar
    that trails a hit by a moment and then eases down. Health text and
    colours stay right through death, a resurrect and someone going offline
    and back.
37. **Raid frames: roster changes, out of combat and in a fight.** People
    join and leave, someone goes offline and comes back, people are moved
    between raid groups, a role changes: each frame shows the right person,
    class colour, role marker, power line, auras and buff indicators after
    each change, also when several come at once (a raid forming), and also
    in a fight (the layout itself waits for the fight's end as before).
    Leave the raid into a party: the party frames are right again at once
    (names, health, auras, roles).
38. **Probe still owed: `UnitGUID` of raid members in combat.** Whether
    `UnitGUID("raidN")` is a secret value in combat on Forever. If it is,
    a roster change in a fight redraws every visible raid frame (once per
    burst), instead of only the ones showing someone new; the frames stay
    right, it only costs more. A probe (`/suu probe`) that reads it for a
    raid member in and out of combat settles it.
