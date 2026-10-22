# Test notes: units-chat

Area: the chat (`src/Units/Chat.wowlua` and its sibling modules
`src/Units/Chat/`: Lines, Search, Input, Tabs) and the command palette
(`src/Units/ChatCommands.wowlua` and `src/Units/ChatCommands/Match`).
Written on wowlua 0.9.4.

The sibling modules came from the WIP checkpoint 68d8ab6: the text work of
both modules moved out into pure functions (what they read of the world
comes in as arguments), with a test file each in `tests/unit/Units/Chat/`
and `tests/unit/Units/ChatCommands/`. Reviewed here against the code they
replaced: the same behaviour, line for line, except one fix (below). The
checkpoint's `tests/unit/Units/Chat.test.wowlua` was a probe (it failed by
design); it is replaced by the module's tests.

The emulated client runs Blizzard's chat frames (ten windows; General,
Global and Log docked), so the module is tested as it runs in game: lines
go in with `ChatFrame1:AddMessage`, chat events with `mock.fireEvent`
(every argument the client sends, Discord's info included), the tabs are
clicked, hovered and dragged, whisper windows open with Blizzard's
`FCF_OpenTemporaryWindow`. The palette is driven through its real input
path: an edit box told to it with EventRegistry's
`ChatFrame.OnEditBoxFocusGained`, the text read each frame.

What the engine doesn't model is faked in the test that needs it: the
client keeping chat windows' names and sizes (`SetChatWindowName`,
`SetChatWindowSize` with `GetChatWindowInfo` following them), the mouse
buttons held during a tab drag (`mock.fake("IsMouseButtonDown")`), a
line's sender GUID (`C_ChatInfo.GetChatLineSenderGUID`), friends and the
ignore list, another addon's command (`issecurevariable`), the context
menus and the confirm dialog (stubbed to capture their buttons).

## Test files

| Source | Test file | Tests |
|---|---|---|
| Chat | `Units/Chat.test.wowlua` | the panel's size and ChatFrame1 in it (combat, Blizzard's own placing, edit mode, a new scale, window events); lines copied in the design's form, the time, raw and secret lines, 500 at most, redrawn where scrolled; the mouse wheel; names' classes (the line's sender, chat events, none); links (the diamond's copy box, a name's menu and each of its buttons, items, a secret link), their tooltips; whispers kept (once, 300, by player and realm) and whisper windows (filled, chosen again, closed); the input's history (Enter, your own lines until Enter reaches SuuUI, Up and Down, combat, lockdown, recall off, the palette open); the tabs (order, a click, the combat log's bar, hover, unread, Blizzard's settings, fonts, names, a new and a closed window, a whisper window's own size, the kept order and its reset, dragging and its ends: Esc, a right click, letting go away, a click, reduced motion, a window closing mid-drag; edit mode's grips and hint); kept chat (saved at logout with classes, keeping off, loaded, restored dimmed above the divider and its rules, whisper windows with earlier whispers, cleared); the Search tab (by player, counts, where from, N more, Whisper, chips, a cut long line, your own lines); the idle fade; the Global tab (channels moved, a hidden LFG channel, combat, off, a Guild tab renamed, a new window, a client without AddChannel); the settings section (the windows editor, the tab order row, the idle delay); a theme change |
| Chat/Lines | `Units/Chat/Lines.test.wowlua` | (from the checkpoint) formatting, plain text, dimming, kept lines, the divider's rules, whisper lines |
| Chat/Search | `Units/Chat/Search.test.wowlua` | (from the checkpoint, one case added: a bare bar) matching, kinds, counts, the shown text, snippets, the match's span |
| Chat/Input | `Units/Chat/Input.test.wowlua` | (from the checkpoint) typed and sent lines, the list, protected commands, recall |
| Chat/Tabs | `Units/Chat/Tabs.test.wowlua` | (from the checkpoint) keys, order, the drop index, easing, dashes |
| ChatCommands | `Units/ChatCommands.test.wowlua` | a / alone; narrowing; chips and Shift-Tab; closest; a category without a match; emotes off; marking (Up, Down, hover) and putting in (Tab, a click); Tab off; a recalled line; after a command: target, party, guild, friends, guild members, friends, the ignored, channels to join and leave, /suu's commands and topics; when it steps aside; focus lost (and a press on the palette); its settings; its place; the catalog's rebuilds; turned off and on; another addon's command |
| ChatCommands/Match | `Units/ChatCommands/Match.test.wowlua` | (from the checkpoint) parsing, matching, closest, categories, the hints |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
all seven sources. One line is marked `-- wowlua: coverage ignore`: the
closing `})` of `M:FormatLine`'s multi-line tail call (see the findings).

## Refactors

The checkpoint's (reviewed, kept): Chat's text work in `Chat/Lines`,
`Chat/Search`, `Chat/Input`, `Chat/Tabs`; the palette's matching in
`ChatCommands/Match`. The modules call them with the world's answers.

## Bugs found

- **Fixed: the palette never offered /suu's commands and topics in the
  wowlua build.** It knew SuuUI's own command by the key `SUUUI`
  (`SLASH_SUUUI1` in the plain-Lua SuuUI); the port registers `/suu` with
  wowlua's `@slash`, under the key `WOWLUA_SUUUI_<n>`, so `/suu` had no
  description and nothing after it. It's known by its name now.
- **Fixed (in the checkpoint's refactor): the Search tab's cut lines could
  start at the wrong link.** `visible()` kept each shown byte's link with
  `links[#links + 1] = link`, which does nothing for a byte outside a link
  (nil), so every later entry moved up one. It's kept by the byte's index
  now. A long line whose match came after a link could be cut inside
  another link's text.

## VM / wowlua findings (new)

- **`IsMouseOver` ignores the cursor and its offsets**: the engine answers
  whether the hovered frame is the frame or one of its children. The
  client measures the cursor against the frame's rectangle, grown by the
  offsets (`tabs:IsMouseOver(12, -12, -24, 24)`, the chat's "let go near
  the row"). Tests set the hovered frame with `mock.hover`.
- **Chat windows' settings aren't kept**: `SetChatWindowName`,
  `SetChatWindowSize` and the other `SetChatWindow*` are no-ops, and
  `GetChatWindowInfo` keeps answering the recording. The client keeps
  them (`FCF_GetChatWindowInfo` reads them back).
- **A hidden edit box keeps the keyboard focus** (unverified against the
  client, which I believe drops it): the copy box hides itself on Escape
  and `GetCurrentKeyBoardFocus()` still returns its edit box.
- **`MockUnit` lacks `joinGroup` and `openTrade` in its declaration**: the
  engine has both (`units.rs`), the docs name them, a typed test can't
  call them without `:: any`.
- **Likely: the last line of a multi-line `return f(...)` is reported not
  run** when it holds only the closing brackets (`})`): the return after
  the tail call never runs and is counted on that line. Seen on Chat's
  `FormatLine`; the palette's `Parse`, the same shape with code on its
  last line, is covered.
- **`mock.fireEvent` checks a CHAT_MSG event's whole payload**, Discord's
  info table included: right, but every chat test needs a helper with
  eighteen arguments. A `mock.chatMessage(event, text, sender, opts)` would
  make chat tests read like the chat.

## Not tested, and why

Nothing in these seven files.
