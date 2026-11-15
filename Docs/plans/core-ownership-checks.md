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
