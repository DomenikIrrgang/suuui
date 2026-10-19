# Porting SuuUI to wowlua: conventions

Every source file becomes a strict `.wowlua` module. Read this whole file
before porting a file. The language and stdlib reference for wowlua **0.9.1**
(the installed compiler) is in the wowlua repository at tag `v0.9.1`
(`git -C ~/repositories/wowlua show v0.9.1:spec/...`; an extracted copy is in
`$SPEC`, given in your task). Never read the wowlua repo's working tree: it is
ahead of 0.9.1.

## Goal and limits

- **Behaviour stays the same.** Same frames, texts, colours, timings, taint
  behaviour, saved data. This is a port, not a redesign. Don't fix bugs you
  notice; write them into your notes file (below) instead.
- **Compatibility that must hold:** `SuuUIDB` layout, the public `SuuUI.*`
  API (`Docs/API.md`), profile export/import strings, `SuuUIProbe` layout,
  addon-message wire formats (other players run older SuuUI versions).
- **Strict mode** for every file (the manifest sets `check.mode = "strict"`).
  Zero errors. No `--!nocheck`, no `@nocheck`. Local `:: any` casts are fine
  where the value really is dynamic (Blizzard tables, saved data, frames with
  fields of their own).
- **Naming:** module-level functions and exports are camelCase
  (`UI.Panel` → `panel`, `Settings.Get` → `get`). Classes, enums and types are
  PascalCase. ALL_CAPS constants stay. **Methods on frames and objects keep
  their names** (`f:SetKey`, `bar:SetValueText`, `M:OnGameEvent`): plugins and
  `Extend.Hook(kind, "Method")` call them by name. Public API names
  (`SuuUI.RegisterModule`, `SuuUI.UI.Panel`, module methods) never change.
- **Comments:** keep every comment (they record probes and decisions). Update
  the header line (`-- UI/Panel.wowlua`) and names in comments that refer to
  code you renamed. Match the surrounding comment density and style.

## Mechanics

1. `git mv src/X/File.lua src/X/File.wowlua` (history follows). Never any
   other git command: no add, commit, stash, checkout, reset.
2. Remove `local _, ns = ...`. Import what the file uses instead; export what
   it defines.
3. Check with `wowlua check 2>&1 | grep -A6 'src/X/File'` from the worktree
   root. Other agents port other files at the same time, so errors in files
   that aren't yours are not yours to fix; an error caused by a name another
   file doesn't export yet is expected until that file is ported (use the
   names from the symbol map, below, and they line up).
4. Only edit your own files (and your notes file). If you need something
   from a file that isn't yours, use the map's name and note it.

## Modules and names

- **Imports:** a namespace import named after the file, camelCase:
  `import * as draw from "/UI/Draw"` → `draw.fill(...)`, or named imports
  when short and unambiguous: `import tokens as T from "/Core/Tokens"`.
  Paths from the source root (`/UI/Draw`), case-sensitive.
- **What each name becomes:** `Docs/wowlua-port-symbols.md` lists every
  `ns.*` definition outside Core with its module and export name. Export
  exactly those names. Core is below.
- **Tables published as `ns.X` whose fields are functions** (`ns.Layout = {
  Stack = …, Grid = … }`, `local Bags = {}; ns.Bags = Bags`): export each
  function (`stack`, `grid`); no export of the table itself. **Data tables**
  (`ns.QuestStarts`, `ns.Tokens`): export the table under the map's name.
- **Cycles:** imports that are only used inside functions that run later may
  form cycles (the compiler binds them lazily). A cycle with a use while the
  file loads is an error: move that use into a function or `@onLogin`.
- **`ns.Mixins.X = Y`** → `import mixins from "/Core/Init"`, `mixins.X = Y`.
- **Globals:** a global SuuUI must create (a named frame, a binding global,
  `SuuUI` itself) keeps its name; frames named in `CreateFrame` are fine.
  Other writes to `_G` need `_G.name = …` or `@global`.

### Core's exports (ported already)

| Old | New |
|-----|-----|
| `ns.name`, `ns.version`, `ns.Mixins` | `/Core/Init`: `name`, `version`, `mixins` |
| `ns.Print(...)` | `/Core/Init`: `print(...)` (the global print is `_G.print`) |
| `ns.RegisterCommand(name, help, fn, owner, args)`, `ns.Commands()`, `ns.UnregisterCommands(owner)` | `/Core/Init`: `registerCommand`, `listCommands`, `unregisterCommands` |
| `ns.API_VERSION` | `/Core/Modules`: `API_VERSION` |
| `ns.Events.On/Emit/OnGame/OnUnit/Off/OffAll` | `/Core/Events`: `on`, `emit`, `onGame`, `onUnit`, `off`, `offAll` (handler is `fn(name, ...)`; owner required) |
| `ns.Fault.Call/Report/List/Timing/SetTiming` | `/Core/Fault`: `call`, `report`, `entries`, `timingState`, `setTiming` |
| `ns.Combat.Run(key, fn, source)`, `.Pending()` | `/Core/Combat`: `run`, `pendingCount` |
| `ns.Settings.*` | `/Core/Settings`: `register`, `ready`, `get`, `peek`, `isDefault`, `list`, `watch`, `veto`, `unwatch`, `set`, `reset`, `migrate`, `charData`, `allCharData`, `getCharKey` (was `CharKey`), `account`, `setAccount`, `forgetCharData`; new: `has(ns, key?)`, `defaultOf(ns, key)` |
| `ns.Profiles.X` | `/Core/Settings`: `profiles.x` (`profiles.current()`, `.list()`, `.find`, `.use`, `.create`, `.delete`, `.copyFrom`, `.setValues`, `.roleProfile`, `.setRoleProfile`, `.chosenRole`, `.setChosenRole`, `.lastRole`, `.setLastRole`, `.export`, `.import`) |
| `ns.Debug(...)` | `/Core/Settings`: `debug(...)` |
| `ns.Util.Copy/Equal/SortedKeys/OwnerName` | `/Core/Util`: `copy`, `equal`, `sortedKeys`, `ownerName` |
| `ns.Tokens` (`T`) | `/Core/Tokens`: `tokens` (typed; `import tokens as T from "/Core/Tokens"`); types `Color`, `TextStyle`, … |
| `ns.Fonts.Get/Refresh/Apply` | `/Core/Fonts`: `get`, `refresh`, `apply` |
| `ns.Pixel.ScreenHeight/PerfectScale/Size/Snap` | `/Core/Pixel`: `screenHeight`, `perfectScale`, `size`, `snap` |
| `ns.Root`, `ns.UserScale()` | `/Core/Root`: `root`, `userScale()` |
| `ns.Anchors.Publish/Get` | `/Core/Anchors`: `publish`, `get` |
| `ns.SuppressBlizzard/IsSuppressed/RestoreBlizzard` | `/Core/Blizzard`: `suppress`, `isSuppressed`, `restore` |
| `ns.Motion.Reduced/Stop/FadeIn/Enter/AlphaTo/Pop` | `/Core/Motion`: `reduced`, `stop`, `fadeIn`, `enter`, `alphaTo`, `pop` |
| `ns.Roles.LABEL/Spec/Current` | `/Core/Roles`: `LABEL`, `spec`, `current` |
| `ns.RolePresets.ROLES/NAME/LAYOUT/Exists/Apply` | `/Core/RolePresets`: `ROLES`, `NAME`, `LAYOUT`, `exists`, `apply` |
| `ns.Vision.MODES/LABEL/HINT/Available/Applied/SyncGlows/Apply` | `/Core/Vision`: `MODES`, `LABEL`, `HINT`, `available`, `appliedMode`, `syncGlows`, `apply` |
| `ns.Themes.DEFAULT/Register/List/Get/Applied/Apply` | `/Core/Themes`: `DEFAULT`, `register`, `all`, `get`, `appliedTheme`, `apply` |
| `ns.Extend.KINDS/Add/Tag/Info/Instances/Each/Hook/Override/ExtendMenu/ApplyMenu/AddTo/Additions/Unregister` | `/Core/Extend`: `KINDS`, `add`, `tag`, `info`, `list` (was `Instances`), `each`, `hook`, `override`, `extendMenu`, `applyMenu`, `addTo`, `additions`, `unregister` |
| `ns.Services.Provide/Get/Unregister` | `/Core/Services`: `provide`, `get`, `unregister` |
| `ns.Modules.Register/Get/All/Find/APIAtLeast` | `/Core/Modules`: `register`, `get`, `all`, `find`, `apiAtLeast`; type `Module` |
| `ns.Serialize.Encode/Decode/Base64/FromBase64/Fletcher16` | `/Core/Serialize`: `encode`, `decode`, `base64`, `fromBase64`, `fletcher16` |
| `ns.Perf.Report` | `/Core/Perf`: `report` |
| `SuuUIDB`, `SuuUIProbe` (globals) | `/Core/DB`: `db`, `probe` (bound by wowlua:saved; locked until ADDON_LOADED, check `DB.loaded()` before touching them at load time) |
| `SuuUI` (the public API global) | `/Core/API`: `SuuUI` (typed; still also the global) |

**Feature modules (`src/Units`, plugins' style)** use only the public API:
`import SuuUI from "/Core/API"` and keep their code as written against
`SuuUI.*` and the module object's methods (`M:Get`, `M:OnGameEvent`, …).

## Standard library: use it where it fits

Use a stdlib module where it does the same thing; keep SuuUI's code where the
stdlib would change something observable (text, timing, taint, combat
behaviour, saved shape, wire format) and **write a gap note** (below).

| Instead of | Use |
|------------|-----|
| `C_Timer.After(s, fn)` | `import after from "wowlua:timer"`: `after(s, fn)` (returns a handle; errors reported) |
| `C_Timer.NewTimer`, `C_Timer.NewTicker` | `after`, `every(s, fn, n?)` |
| `hooksecurefunc(...)` | `import hook from "wowlua:hooks"`: `hook(name, fn)`, `hook(table, "Method", fn)`; `opts.addon` for load-on-demand targets |
| `frame:HookScript` on a Blizzard frame | `hookScript(frame, "OnShow", fn)` from `wowlua:hooks` |
| your own `CreateFrame` + `RegisterEvent` + `OnEvent` | `/Core/Events` (`onGame`, owner) or, in feature modules, `M:OnGameEvent`; for a fixed handler at file level `@event("NAME")` from `wowlua:events` is fine |
| `ADDON_LOADED` for another addon | `onAddonLoaded(name, fn)` from `wowlua:lifecycle` |
| `PLAYER_LOGIN` once | `@onLogin` from `wowlua:lifecycle` |
| deep copy / equality / keys | `/Core/Util` (wraps `wowlua:table`) or `wowlua:table` directly |
| `InCombatLockdown()` checks | fine as they are; `inCombat()` from `wowlua:combat` where it reads better |
| `RegisterStateDriver(f, "visibility", …)` | `secure.visibility(f, cond)` from `wowlua:secure` **only** where deferring the call to after combat matches what the code did |
| `issecretvalue(v)` guards | `wowlua:secret`: `secret.known(v, fallback)`, `secret.flag(b)`, `secret.amount(v)`; or `canaccessvalue(v)` / `issecretvalue(v)` (both narrow) |
| table/frame pools | `wowlua:pool` when its release semantics match |
| item / spell info with loading | `wowlua:item`, `wowlua:spell` when the result is the same |
| money, durations, numbers | `wowlua:format` **only** where the output text is identical |
| colour escapes | `wowlua:color` (`colorize`, `wrap`, `strip`, `hex`) where identical |

`print` from `wowlua:log` adds its own prefix: don't use it; SuuUI's
`/Core/Init` `print` keeps SuuUI's look.

## Strict-mode patterns (found while porting Core)

- **Map reads are optional:** `t[k]` on `{ [K]: V }` is `V?`. Read into a
  local and test it, or `assert(...)` when it can't be nil; a record type
  (fields) reads non-optional.
- **Narrowing doesn't follow variable keys:** `if d[k] then d[k].x end` still
  errors; `local v = d[k]; if v then v.x end`.
- **`type(x) == "table"` gives `table`**, which isn't assignable to
  `{ [string]: any }`: cast (`x :: { [string]: any }`).
- **Secret values:** Unit*/Get* APIs that may return secrets are typed
  `T | Secret<T>`. Comparing, indexing or doing arithmetic on them is an
  error: narrow with `canaccessvalue`/`issecretvalue`, or `secret.known`.
  Passing them to widget setters that accept secrets is fine.
- **`s:byte(i)`, `tonumber(x)`, `string.match` captures are optional**: `or 0`.
- **Empty table literals with an element type:** annotate the local
  (`local list: Hook[] = map[id] or {}`).
- **`table.sort` comparators:** annotate the parameters with the list's exact
  element type (a named type), not a narrower record.
- **`export const x: T = { … }` exports the literal's type** (compiler issue):
  write `export const x = { … } :: T` instead.
- **Frames with fields of their own** (`f.text = …`, `function f:SetKey()`):
  allowed on widget values as they are. For a table you build up, declare a
  type (`type Row = { … }`) or use `{ [string]: any }`.
- **Parameters need types** (callbacks passed directly to a call don't).
- Unused locals/parameters are warnings; fix the ones you introduce.

## Notes you write

Write what you find into **`Docs/port-notes/<your-area>.md`** (create it; one
file per agent so nobody edits the same file), in three sections:

1. **VM suspicions** (if you ran the VM) — what the emulator did vs what the
   game would do, with a repro.
2. **Compiler/tooling issues** in 0.9.1 — a minimal repro, the error, and
   your workaround in the code. Check `Docs/wowlua-port-notes.md` first; don't
   repeat what's there.
3. **Stdlib gaps** — where a stdlib nearly fit: what SuuUI keeps, and the
   feature the stdlib would need (one paragraph each).
4. **Port decisions** — anything a reviewer should look at: a behaviour you
   weren't sure stayed the same, a bug you noticed and left, a cast you
   needed for a reason that isn't obvious.
