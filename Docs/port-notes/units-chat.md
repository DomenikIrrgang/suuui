# Port notes: units-chat

Files: `src/Units/Chat.wowlua`, `src/Units/ChatCommands.wowlua` (from the
`.lua` files, `git mv`). Strict mode, no errors; three warnings in Chat that
the Lua code already had (below).

## 1. VM suspicions

None (the VM was not run for these files).

## 2. Compiler/tooling issues

### W8040 on a hook guarded by an existence check of the method

`ChatFrame1` is declared as `Frame`, without the chat frame mixin's
methods. Reading `ChatFrame1.ApplySystemAnchor` in a condition is accepted,
but `hook()` inside that branch still warns that the target has no such
method:

```wowlua
import hook from "wowlua:hooks"
if ChatFrame1.ApplySystemAnchor then
    hook(ChatFrame1, "ApplySystemAnchor", function() print("x") end)
end
-- warning[W8040]: `Frame` has no `ApplySystemAnchor` to hook; the hook fails where it is installed
```

Two gaps: the chat frames' declared type lacks their mixin's methods
(`ApplySystemAnchor`), and the `if t.method then` check does not narrow for W8040. Workaround in
Chat.wowlua: `hook(ChatFrame1 :: any, "ApplySystemAnchor", …)`.

## 3. Stdlib gaps

None found. Used: `wowlua:secret` `isSecret` (both files, for the old
`issecretvalue or function() return false end`), `wowlua:timer` `after` (all
twelve `C_Timer.After` in Chat), `wowlua:hooks` `hook` (the post-hooks on the
chat windows' `Clear`/`AddMessage` and `ChatFrame1:ApplySystemAnchor`) and
`hookScript` (the scroll-to-bottom button's OnShow, the edit boxes'
OnKeyDown/OnArrowPressed in both files). Hooks and timers now run through
the stdlib's error isolation (`callIn`): an error in them is reported
instead of reaching the game's handler; nothing else changes. HookScript on
SuuUI's own frames (the palette's scroll area, the Windows editor) stays as
it was.

## 4. Port decisions

- **`plain(v)`** is typed as a predicate `v is Readable` (string, number,
  boolean, table, function), so `plain(x) and …` narrows away `Secret<…>`
  and nil for the checker. Same body as before.
- **ChatCommands `M:Names`**: the player's own name from `SuuUI.FullName`
  (typed possibly secret) is only compared when it is readable. Before, a
  secret name would have raised an error in `fits`; the player's own name is
  never secret in practice, so nothing observable changes.
- **`ChatEdit_CustomTabPressed`** (ChatCommands `wrapTab`) is still replaced,
  not post-hooked: the game calls it through securecall for addons' Tab
  completion and only its return value (true skips the game's own) can take
  Tab. Kept exactly; the checker accepts the write to the declared global.
  `CURRENT_CHAT_FRAME_ID` (Chat `OpenChatSettings`) is written the same way.
- **`InviteUnit`** is undeclared on camelot: read as `_G.InviteUnit` (it was
  only the fallback behind `C_PartyInfo.InviteUnit`).
- **`pcall(UnitClass :: any, name)`** in `classOf`: `name` may be nil there
  and the call is inside pcall on purpose (as before).
- **Casts where the value is always present**: `q.item`, `q.prefix`,
  `q.sub`, `sub.args` in ChatCommands `DrawArgs` (args mode always has
  them); `snippet`'s arguments in Chat `ShowRow` (set whenever `x2` is);
  `hexRGB` and `dimByte` read `tonumber(…) or 0` (the strings were matched
  as hex/decimal digits first); `matchSpan` returns nil unless both ends of
  the match are found (find gives both or neither); `M:Parse` checks both
  captures of patterns that always match together.
- **Local types**: `Item`, `Match`, `Row`, `Group`, `Query`, `Entry`,
  `SubCommand` (ChatCommands); `Line`, `Whisper`, `Saved`, `KeptEntry`,
  `Found`, `Classes` (Chat). Chat frames, mirrors, tab buttons and the
  search page are `any` (Blizzard frames and frames with fields of their
  own). `Color` is a local copy of Tokens' type (`number[] & { hex }`) for
  `T.color[token]` read by a variable token, so the Unit doesn't import
  Core's types.
- **Renamed local**: `after` in `M:FormatLine` is now `rest` (it shadowed
  the timer import).
- **Warnings left as they were in the Lua code** (Chat): unused `h` in
  `M:LogRect` (GetHeight read and unused), unused `id` in `M:SkinFrame`
  (`cf:GetID()` read and unused), unused parameter `cf` of
  `M:MirrorFrame`. Removing them is harmless but wasn't part of the port.
