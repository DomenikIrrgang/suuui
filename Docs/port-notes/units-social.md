# Port notes: units-social

Files: `src/Units/GroupFinder.wowlua`, `Guild.wowlua`, `Social.wowlua`,
`GameMenu.wowlua`, `MicroMenu.wowlua` (wowlua 0.9.1, strict, 2026-10-20).

## 1. VM suspicions

(the VM wasn't run for these files)

## 2. Compiler/tooling issues (0.9.1)

### C-a. One import cycle anywhere types every `wowlua:*` import as `any`

This is the cause of what `units-character.md` saw ("`wowlua:*` imports read
as `any` inside SuuUI, not reproduced in a scratch project"). A cycle between
any two files of the package is enough. It needn't touch the file that
imports the stdlib. SuuUI has cycles on purpose (`Core/Init` ↔ `Core/Fault`,
API ↔ UI modules; the conventions allow lazy ones). Repro (fresh `wowlua new
--flavors camelot X`, strict):

```wowlua
-- src/C/A.wowlua
import * as b from "./B"
export function fa(): number return 1 end
export function ga(): number return b.fb() end
-- src/C/B.wowlua
import * as a from "./A"
export function fb(): number return 2 end
export function gb(): number return a.fa() end
-- src/main.wowlua
import isSecret from "wowlua:secret"
import after from "wowlua:timer"
local zy: number = isSecret   -- accepted with C/A+C/B present, E2001 without
local zz: number = after      -- the same
```

What it breaks: `isSecret`'s predicate (`v is Secret<unknown>`) is lost, so
`if not isSecret(class) then T[class] end` is an E2040 in SuuUI and fine
without the cycle. Bisected in a copy of this worktree: only `Core/Fault` +
`Core/Init` (which import each other) plus a probe file reproduce it. The
global `issecretvalue` still narrows. It also means every stdlib call in
SuuUI is unchecked right now.
Workaround here: where a possibly secret value had to be narrowed I used
`secret.known(v, fallback)` (a value, not a predicate, so it doesn't depend
on the predicate's type). `GroupFinder` `M:AdFromListing` (`class`), `Social`
`M:RaidMembers` (`UnitGroupRolesAssigned`), `GameMenu` `M:Draw` (`realm`).

### C-b. `canaccessvalue` doesn't narrow at all, not even in an `if`

```wowlua
local T: { [string]: string } = {}
local function f(v: string | Secret<string>): any
    if canaccessvalue(v) then return T[v] end   -- E2040: `string | Secret<string>` may be a secret value
end
```

This happens without any cycle too. The spec (02-types §2.2.8 table) says
the true branch removes `Secret<…>`. `units-character.md` saw it only in an
`and` chain. It happens in a plain `if` as well. Not used in these files.

## 3. Stdlib gaps

- **Guarded call and `plain`:** the same as `units-character.md` (SuuUI's
  `call(fn, ...)` and `plain(v)` kept in `Guild` and `Social`, now typed).
  `plain` now uses `wowlua:secret`'s `isSecret` instead of the
  `issecretvalue or function() return false end` fallback. That is the
  same test.
- **GameMenu keeps `C_Timer` and `hooksecurefunc`/`HookScript`:** not a
  gap in the stdlib. It was a choice for this file. The Escape menu is
  taint-sensitive, and the task said to keep it exactly. `wowlua:timer`
  and `wowlua:hooks` would only add the `xpcall` isolation, so they would
  probably be fine here. Worth switching once someone can check
  `/suu probe gamemenu` in game.

## 4. Port decisions

- **Stdlib used:** `wowlua:timer` (`after`; `every` for GroupFinder's 15 s
  ticker), `wowlua:hooks` (`hook` for every `hooksecurefunc`; `hookScript`
  for `HookScript` on Blizzard frames: SocialUIFrame and its lists,
  CommunitiesFrame, its MemberList, the guild text edit dialog,
  LFGParentFrame, LFGListingFrame, LFGBrowseFrame, LFGWhoListFrame),
  `wowlua:secret` (`isSecret`, `known`) in GroupFinder, Guild, Social,
  MicroMenu. `HookScript` on SuuUI's own frames (secure covers, panels,
  the MOTD banner, the micro menu) stays the method. Callbacks now run
  isolated, so an error is reported and not thrown. Otherwise the timing
  and the arguments are the same.
- **`MicroMenu` `legacyToSpend`:** `q = ok2 and info and info[1] and
  info[1].quantity` became `… or nil`. Before, a failed `pcall` returned
  `false`, and `legacy > 0` then errored in `UpdateAlerts`. Now it returns
  0. This is the only behaviour change: it is on an error path, and strict
  typing forced it. Please check it in review.
- **`GroupFinder` `M:PostAd`:** `send(text, "CHANNEL", nil, id :: any)`. The
  declarations type `SendChatMessage`'s target as `string?`, but the channel
  number has always been passed (the game takes it).
- **`Guild` `M:Members`:** `Ambiguate(me :: string, "short")`.
  `SuuUI.FullName` is typed optional. The cast keeps the old behaviour: it
  would error on nil, as before.
- **Secret guards added, none removed:** in `GroupFinder` (party roles and
  your class in the ad text), `Social` (raid roles) and `GameMenu` (realm),
  values the declarations type as possibly secret now go through
  `secret.known`. When the value isn't secret, nothing changes. When it is
  secret, the code now falls back where it would have errored before.
- **Undeclared globals** read through `_G.` (`InviteUnit`,
  `ChatFrame_SendBNetTell`, `BNSetAFK`, `BNSetDND`, `ConvertToRaid`), and
  `C_BattleNet` members the declarations lack (`SetFriendNote`,
  `RemoveFriend`, `SendFriendInvite`) through `local bn: any = C_BattleNet`.
  Same lookups at run time.
- **Removed:** GameMenu's unused `call` helper (dead code, never
  referenced).
- **Left as they were (pre-existing warnings):** Guild `noteBlock`'s unused
  `officer` parameter and GroupFinder `M:OnContacted`'s local `ago`
  shadowing the file's `ago`. GroupFinder's unused `card` parameter is now
  `_card: any`.
- **Row and entry types** are `{ [string]: any }` aliases (`Row`, `Member`,
  `Entry`): the UI components and `SuuUI.LFG` take them untyped. `Entry`
  can become ForeverLFG's own type once `SuuUI.LFG` is typed through the
  library package.
