# Port notes: ForeverLFG (library package)

ForeverLFG moved from `src/Libs/ForeverLFG/*.lua` to its own wowlua
**library** package, `libs/ForeverLFG/` (package name `foreverlfg`, kind
`library`, `wowlua ^0.9`, flavor camelot, strict, license MIT). The root
`wowlua.json` (SuuUI) is now also a workspace root: it gained
`"workspace": { "members": ["libs/*"] }` and
`"dependencies": { "foreverlfg": { "path": "libs/ForeverLFG" } }`, and
nothing else changed. `wowlua.lock` gained the path package (`used-by:
suuui`). `wowlua check -p foreverlfg` passes with no errors and no warnings.
`wowlua check` at the root checks the library after SuuUI, so it shows up
there only once SuuUI itself checks cleanly.

```
libs/ForeverLFG/wowlua.json
libs/ForeverLFG/src/init.wowlua       main module ("foreverlfg"): the public table, Lang registration, parts
libs/ForeverLFG/src/LFG.wowlua        config, events, start/stop, the public table `lfg` and its type ForeverLFG
libs/ForeverLFG/src/Catalogue.wowlua  Chat.wowlua  Interest.wowlua  Parser.wowlua  Store.wowlua  Tool.wowlua
libs/ForeverLFG/src/Lang/enUS.wowlua  koKR.wowlua  zhCN.wowlua   (data modules)
```

## How SuuUI uses it

**`src/Core/API.wowlua`** rebuilds `SuuUI.LFG` like this:

```wowlua
import lfg from "foreverlfg"
import type ForeverLFG from "foreverlfg"
...
API.LFG = lfg :: ForeverLFG
```

Replace `API.LFG = ns.LFG` with that. The cast is needed because 0.9.1 types
values imported from another package as `any` (see compiler issue 1 below).
The exported *type* does come through, so `:: ForeverLFG`, or a field typed
`LFG: ForeverLFG` in SuuUI's API type, gives every consumer of `SuuUI.LFG`
full types.

**Other SuuUI files:**
- **Feature modules** (`src/Units/GroupFinder.wowlua`, `src/Units/Chat.wowlua`)
  keep using `SuuUI.LFG` from `/Core/API`, as the conventions require.
- **Internal files that used `ns.LFG`** (`src/Diagnostics/LfgProbe.wowlua`)
  use `import lfg from "foreverlfg"` and `import type ForeverLFG from
  "foreverlfg"`, then `local LFG: ForeverLFG = lfg`. LfgProbe already does
  this.
- **UI files** (`src/UI/GroupFinder*.wowlua`) never touched `ns.LFG`. Their
  data comes from the Group Finder module. If they want the library's
  shapes, they can use type-only imports:
  `import type Entry, Listing, Activity, Interest from "foreverlfg"`. A
  type-only import creates no load-order edge and doesn't pull the library
  into the build by itself.
- Every module can also be imported on its own: `"foreverlfg/Store"`,
  `"foreverlfg/Chat"`, and so on. The library can't import anything from
  SuuUI.

**Symbol map:** the `ns.LFG.*` entries keep their export names. The paths
changed from `/Libs/ForeverLFG/X` to `foreverlfg/X`. `ns.LFG` → `lfg` is
exported from both `"foreverlfg"` (main) and `"foreverlfg/LFG"`.

Exported types (from `"foreverlfg"`): `ForeverLFG`, `Config`, `Listener`,
`Part`, `Activity`, `ChatSource`, `Interest`, `ParseResult`, `LangModule`,
`Entry`, `Filter`, `ToolSource`, `Listing`.

## 1. VM suspicions

None. In a scratch workspace with a copy of the library, two `wowlua test`
tests passed in the VM:
- **Parser parity.** 33 chat lines were parsed by the original Lua files
  (from git HEAD, run with the system `lua`) and by the ported parser. The
  serialized results were identical. The lines covered English, Korean and
  Chinese (picked by script), noise, quest links, counts, levels and
  umbrellas.
- **Runtime smoke test.** Configure with an `OnConfigure` hook, `running`,
  Start (3 parts), `Chat.Read` into the Store, `Entries`, `Catalogue.Name`,
  `IsHiddenChannel`, `Store.Clear`, Stop, and the events in order.

## 2. Compiler/tooling issues (0.9.1)

1. **Values imported from a wowlua library are `any` in the consumer.**
   §10.5.1 says "the consumer sees its exported types". Exported types do
   come through. Exported values don't, and neither does a `typeof(value)`
   type alias across the package. Repro: a workspace with a library `mylib`
   whose `src/Core.wowlua` has
   `export function hello(n: number): number return n + 1 end`, and an
   addon that depends on it by path. In the addon,
   `import hello from "mylib/Core"; local s: string = hello(1)` reports no
   error. The same function imported from the addon's own `./Foo` reports
   E2001. `export type Api = typeof(api)` in the library is `any`-like in
   the addon. An explicit record type works. Workaround: the library
   exports an explicit `ForeverLFG` type (no `typeof`), and consumers cast
   or annotate with it.
2. **Fields added after a table literal are untyped for importers.**
   `export const chat = { joined = false }` followed by
   `function chat.Hide(n: number): number … end`: an importer's
   `local s: string = chat.Hide(1)` and even `chat.Nope()` pass without an
   error. Workaround, used for `catalogue`, `chat`, `store`, `tool`,
   `parser`, `lang` and `lfg`: declare the API type and cast an incomplete
   literal, `export const chat = {} :: ChatApi`, then define
   `function chat.Hide()`. The cast accepts the missing fields; the
   assignments are checked against the type.
3. **License warning (tooling):** a library member without a license file
   or header gets W4306 ("embedded library without a recognizable license
   file or header") in the consumer's check. `"license": "MIT"` in the
   library's `package` (the repository's LICENSE is MIT) silences it.

## 3. Stdlib gaps

- **`LFG.On` / `Off` / `Fire` vs `wowlua:callbacks`.** The registry's `on`
  returns a Subscription and removes by subscription or owner. ForeverLFG's
  public API removes by handler (`LFG.Off(event, fn)`) and `On` returns the
  function. Its errors go through `geterrorhandler()` per listener. A
  registry with `off(name, fn)` would fit. SuuUI keeps its own small bus.
- **Lang modules vs `wowlua:locale`.** `wowlua:locale` is for one client
  language's UI strings. These files are parser keyword data per *chat*
  language: several are active at once, chosen by the player's preference,
  the client, extra settings, and the script of each line. That's not the
  client's locale, so they stay plain data modules.

## 4. Port decisions

- **The public table.** `LFG.wowlua` creates `lfg` (typed `ForeverLFG`) with
  `version`, `config`, `parts`, `running`, its own functions and the
  `OnConfigure` hook slot. `init.wowlua` adds the other files' fields
  (Catalogue, Chat, IsHiddenChannel, Interest, ... Whisper). So
  `SuuUI.LFG.running` and the `LFG.OnConfigure` hook still live on the
  public table, as before. The other files import what they need by name:
  `fire`, `now`, `config`, `catalogue`, `store`, `entry`, `listing`,
  `watches`, `languages`, `parser`, `lang`. Public names are unchanged:
  PascalCase fields on `lfg`, `Catalogue.Get`, `Chat.stats`,
  `Lang.Register`, `Parser.Parse`, and so on.
- **Part order.** The parts (Chat, Interest, Tool) used to register
  themselves at load, in TOC order. The computed load order now puts
  Interest before Chat, because Chat and Tool read Interest's
  `languages`/`watches` inside their Start. Each file now exports `part`,
  and `init` adds them in the old order: Chat, Interest, Tool (stopped in
  reverse). `LFG.AddPart` stays public for others.
- **Lang files** export their table (`export const enUS = { … } ::
  LangModule`), and `init` registers them with `lang.Register(code, def)`.
  A library's modules are tree-shaken by imports, so a file that only
  registered itself would be dropped from SuuUI's build.
- **The soft use of SuuUI** (Chat: whether a post is your own) stays a
  guarded read of the global:
  `local host = (_G :: any).SuuUI; return host and host.FullName and
  host.FullName("player")`. This keeps behaviour identical without any call
  from SuuUI's side, and the library still loads without SuuUI. The
  alternative was a setter SuuUI's API module would have to call: one more
  cross-file step, and the "your own post" flag would silently go wrong if
  it were missed.
- **No SavedVariables** in the library. Wire formats are untouched: it sends
  nothing, and chat parsing is unchanged (verified above).
- **Stdlib swaps:**
  - Each part's own `CreateFrame` + `RegisterEvent` + `OnEvent` →
    `wowlua:events` `on(event, fn, OWNER)`, and `offAll(OWNER)` on Stop.
    Interest used to `pcall` RegisterEvent: an event the client doesn't know
    now just never fires, which comes to the same.
  - `C_Timer.After` → `after` (`wowlua:timer`).
  - `C_Timer.NewTicker(10, tick)` → `every(10, tick)`.
  - Errors in those callbacks now go through `wowlua:errors`. Chat's
    handler still pcalls `Read` and counts errors as before.
- **Offline fallbacks:**
  - `os.time()` (WoW has no `os`) is read as `(_G :: any).os.time()`, so
    it behaves the same in game (GetTime wins) and offline.
  - `unpack or table.unpack` is now plain `unpack` (WoW's Lua 5.1).
- **Load-order guards** that the imports make unnecessary were dropped:
  `LFG.Lang and …` and `LFG.Languages and …` in `Catalogue.Name`,
  `LFG.Parser and …` in `ReadTool`, `LFG.Listing and …` in `Interest`, and
  `LFG.Watches and …` in Tool.
- **Renamed locals** (name clashes with exports):
  - Store's map: `entries` → `byKey`.
  - Interest's: `social` → `socials`.
  - Tool's `store()` → `put()`.
  - In `MatchReasons`, the parameter `interest` → `given`.
- **Casts** are mostly `C_LFGList`, `C_QuestLog`, `C_AccountServices`,
  `C_BattleNet` and `_G` as `any`. They are pcall-wrapped dynamic reads, as
  before.
- **Not mine, now stale:**
  - `tools/lfg_parse.lua` loads `src/Libs/ForeverLFG/Parser.lua` and
    `Lang/*.lua` with `loadfile`. Those files moved and are wowlua now, so
    the tool no longer runs. A `wowlua test` in the library could replace
    it; the parity test above is a starting point.
  - `Docs/ForeverLFG.md` ("Where it lives": `src/Libs/ForeverLFG/`,
    `Lang/enUS.lua`) and `Docs/wowlua-port-symbols.md` (paths) name the old
    location.
