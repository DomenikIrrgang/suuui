# Port notes: units-notices

Files: `src/Units/Notifications.wowlua`, `NpcDialogue.wowlua`,
`ObjectiveTracker.wowlua`, `Alerts.wowlua`, `DeathRecap.wowlua`,
`Support.wowlua` (wowlua 0.9.1, strict, 2026-10-20).

## 1. VM suspicions

(the VM wasn't run for these files)

## 2. Compiler/tooling issues (0.9.1)

### `f() and t` with `f(): boolean` is typed `boolean | T`, not `false | T`

So a truthiness test keeps `true` and indexing then fails.

```wowlua
local function f(): boolean return math.random() > 0.5 end
local t = { x = 1 }
local y = f() and t
if y then print(y.x) end   -- E2003: cannot index a value of type `true`
```

It hits SuuUI's common `plain(v) and v and Api(v)` pattern (`plain` is a
boolean helper, not a predicate). Workarounds: an `if` that assigns
(`ObjectiveTracker` `hereNames`: `local info = nil; if plain(map) and map
then info = C_Map.GetMapInfo(map) end`), or an annotated local with
`… or nil` (`Notifications` `TestPresence`: `local single: Person? =
#people == 1 and people[1] or nil`; same truthiness as the old `false`).

### Declarations: `issecrettable` takes `function`

`issecrettable` is declared `(table: function) -> boolean`:

```wowlua
local ok, events = pcall(C_DeathRecap.GetRecapEvents, 1)
local s = ok and issecrettable(events)   -- E2001: `DeathRecapEventInfo[]` is not assignable to `function`
```

Workaround (`DeathRecap`): `issecrettable(events :: any)`.

### Declarations: quest functions declared without their index argument

`SelectActiveQuest(i)`, `SelectAvailableQuest(i)` and
`GetQuestLogCompletionText(logIndex)` are declared with no parameters (E2006
"expected 0, got 1"). Blizzard's own quest frame code passes the index.
Workaround: `(SelectActiveQuest :: any)(i)` (`NpcDialogue`), and
`(GetQuestLogCompletionText :: any)(logIndex)` (`ObjectiveTracker`).
Unverified against the client which form Forever takes: the calls pass
exactly what they passed before.

### Declarations: `InviteUnit`, `ChatFrame_SendBNetTell` undeclared; `tabCost` a string

`InviteUnit` and `ChatFrame_SendBNetTell` are "not a declared global" (both
are fallbacks after the newer `C_PartyInfo.InviteUnit` and
`ChatFrameUtil.SendBNetTell`): read as `_G.InviteUnit` and
`_G.ChatFrame_SendBNetTell` (`Notifications`). The bank tab's
`FetchNextPurchasableBankTabData(...).tabCost` is declared `string?`, where
the code (and the popup's money frame) treat it as copper: the
`CONFIRM_BUY_BANK_TAB` cost function returns `any`.

## 3. Stdlib gaps

None that changed code. `wowlua:hooks` fit everywhere it was used; see the
port decision on Notifications below for where it wasn't used on purpose.

## 4. Port decisions

- **Notifications keeps its hooks as they were**: `hooksecurefunc("StaticPopup_Show", …)`,
  the popups' `HookScript("OnHide")`, the hooks on Blizzard's popup buttons
  (`SetWidth`, `SetSize`, `Enable`, `SetChecked` …) and the request windows'
  `OnShow`/`OnHide` stay plain `hooksecurefunc`/`HookScript` (taint-sensitive
  hosting of Blizzard's popups; no stdlib wrapper in between). Only its
  `C_Timer.After` calls became `timer.after` (imported as `* as timer`: a
  local `after` in `M:Attach` would shadow a named import).
- `wowlua:hooks` replaced the hooks in NpcDialogue (GossipFrame, QuestFrame
  and the quest panels), DeathRecap (`OpenDeathRecapUI`) and Support
  (`HelpFrame` OnShow). They still post-hook; errors now go to the stdlib's
  reporter through `xpcall` instead of straight to the error handler, and a
  hook's return value is dropped (none of these return one).
- Timers: `C_Timer.After` → `after`, `C_Timer.NewTimer` → `after`,
  `C_Timer.NewTicker` → `every` (Alerts' hover hold; the handle's `Cancel`
  is used as before).
- **Secret-typed values compared as before, through a cast**:
  `Notifications` `SystemLine` compares a name with
  `(SuuUI.FullName("player") :: any)`, and `TestPresence` keeps the player's
  full name as `any` (`SuuUI.FullName` is typed `string | Secret<string>`;
  the player's own name is the old code's comparison and concatenation,
  unchanged). `NpcDialogue` `DrawSpeaker` compares `(guid :: any) ~=
  self.speakerGUID` after the existing `not plain(guid) or` guard (`plain`
  is a boolean helper, so it doesn't narrow). No guard was added or removed.
  `Notifications` `classColor`/`classIcon` take `any` (a class file from
  `UnitClass` is typed secret).
- `M:Hook()` in NpcDialogue replaces the module object's `Hook(kind, method,
  fn)` (the public `M:Hook` for SuuUI's components) on this module, as it did
  in Lua; the checker accepts it. Renaming it would be cleaner, but a method
  name stays as it is in this port.
- Data shapes that are built up field by field are `{ [string]: any }`
  aliases: `Quest` (ObjectiveTracker), `Answer`/`Card` (NpcDialogue),
  `Note`/`Host`/`Person` (Notifications).
- DeathRecap: the school's name is read inside the `readable(last.amount)`
  branch (into a local, as before only when the amount reads), so the
  checker sees a `string` to concatenate.
- ObjectiveTracker: `splitObjective` returns `(string?, string?)` (the match
  captures are optional; when the count matched, the text did too); the
  unused fourth value of `GetQuestLogSpecialItemCooldown` (`enable`) is no
  longer bound. `ITEM` (`UI.Size("icon-md")`) is an unused local from
  before the port (warning W1003); left as it was.
- `firstName` (Notifications) casts its match to `string`: a name without
  a first word would have errored on the concatenation before too.
