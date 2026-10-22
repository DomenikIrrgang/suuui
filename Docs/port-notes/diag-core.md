# Port notes: diag-core

Files: `src/Diagnostics/` Probe, Diagnostics, ApiDocs, TokenSheet, Gallery,
ClassData, SpellData, PresetSpellIDs, TaintProbe, GarbageProbe, MemoryProbe,
FlickerProbe, IconProbe, DragonProbe, HoldProbe, MenuProbe, ToyModelProbe,
UnlearnProbe, CastTargetProbe, DeathRecapProbe, HoverTipProbe.

## 1. VM suspicions

None. The VM was not run for these files.

## 2. Compiler/tooling issues (0.9.1)

### E5001 instead of the upvalue fallback the spec describes

Modules §5.5 says that when a function would need more than 60 upvalues, the
compiler reads the extra imports through their module tables. In 0.9.1 the
check fails with E5001 instead, for namespace imports and named imports alike:

```wowlua
-- src/m/M1.wowlua … src/m/M62.wowlua: export function command() end
import * as m1 from "/m/M1"   -- … up to m62
export function run(sub: string)
    if sub == "1" then m1.command() return end
    -- … one line per module, up to 62
end
-- error[E5001]: Lua 5.1 limit exceeded: function at line 63 has more than 60 upvalues
```

(The same happens with `import command as c1 from "/m/M1"` … `c62()`.)
Repro project: `/Users/domenikirrgang/.claude/jobs/19c8952e/tmp/scratch-diag-core/X`.

Workaround in `Probe.wowlua`: `/suu probe` sends each of its 72 topics to one of
about 70 probe modules. The `if sub == …` chain became a table
`TOPIC_COMMANDS` holding one small function per topic. Each function captures
one module, so the modules are still only read when the command runs.

### `typeof <namespace> | {}` cannot be asserted to a map

`pairs(C_Trainer or {})` and `pairs(Enum.SpellBookItemType or {})` give E2001.
`(C_Trainer or {}) :: { [any]: any }` gives E2015 ("cannot assert"). What
works is a cast through `any` first: `((C_Trainer :: any) or {}) :: { [any]: any }`.
This is the same problem as C3 in `Docs/wowlua-port-notes.md`, reached from a
typed global namespace or enum instead of `type(x) == "table"`.

## 3. Stdlib gaps

None that made SuuUI keep its own code. Where these files now use the stdlib:

- `wowlua:secret` `isSecret` instead of `issecretvalue or function() return false end`
  (it does the same).
- `wowlua:timer` `after`/`every` instead of `C_Timer.After`/`NewTicker`. The
  stdlib reports errors raised inside a timer, where before they went
  straight to the error handler.
- `wowlua:hooks` `hook`/`hookScript` in the Hold, Menu and Flicker probes, which
  also catch errors raised inside the hook.
- `wowlua:lifecycle` `@onLogin` in SpellData, to resume recording after a
  reload (this was `Events.OnGame("PLAYER_LOGIN", …, "SpellData")`).

## 4. Port decisions

- **Probe exports.** The symbol map lists only `ns.Probe → probe`, and the same
  goes for TokenSheet and Gallery: the generator missed the fields these
  files add after `ns.X = {}`. These are tables of functions, so each function
  is exported on its own: Probe `command`, `hide`, `TOPICS`; TokenSheet and
  Gallery `toggle`, `hide`. Only `Diagnostics.wowlua` imports them.
- **Probe topics.** Each topic's command is called with the arguments its
  module's `command` takes now: `rest` for those that take one, nothing for
  those that take none. Calling with or without `rest` makes no difference
  at run time. Seven modules are not ported yet (MarkProbe, QuestProbe,
  BagProbe, BagSortProbe, TooltipProbe, TaxiProbe, TalentBuildProbe). Their
  calls follow the old `Command(arg)` / `Command()` signatures. If one is
  ported with a different signature, its line in `TOPIC_COMMANDS` needs to
  change to match.
- **Probe `check()`** must now return something on every path. It ends with
  `return false, "?"` for an item of no known kind. No item in `SECTIONS` is
  like that, so the line never runs. Before the port this case returned nil.
- **SuuUIProbe** is `DB.probe` everywhere. `SuuUIProbe = SuuUIProbe or {}` and
  the `if SuuUIProbe then` guards are gone, since `DB.probe` always exists
  after ADDON_LOADED and every probe runs from a command after login.
  SpellData's resume runs in `@onLogin`, which is also after load. The keys and
  the shape of the saved data are unchanged.
- **MemoryProbe's walk of `ns`.** Before the port the addon table held every
  `ns.X`. Now it holds almost nothing except the wowlua runtime under
  `__wowlua`. The "namespace" section (`out.ns`, `out.nsKB`) now walks:
  - the addon table's own tables, without `__wowlua`;
  - each module's export table from the runtime's registry
    (`ns.__wowlua.modules`, keyed by module ID such as `Data/QuestStarts`).

  The saved shape is the same: a list of "name N KB" strings and a total. The
  names are now module IDs, where they used to be `ns` keys. The registry is
  an internal of the runtime. It exists in both the dev and the release
  builds of 0.9.1.
- **IconProbe** no longer checks whether the list is missing ("no spell list
  …"), because the imported list always exists.
- **HoverTipProbe** calls `isTooltipSkinned` from `/UI/Tooltip` directly. Before,
  it went through `ns.UI.IsTooltipSkinned and …`, which printed "nil" when the
  function was missing. The function always exists now.
- **Event owners.** ClassData and SpellData registered their handlers with
  their file tables (`CD`, `SD`) as the owner. Those tables are gone, so the
  owners are now the strings `"ClassData"` and `"SpellData"`.
  `events.offAll("SpellData")` stops recording as before. The resume on login
  is no longer an event handler, so `offAll` never removes it, which was also
  true before.
- **State that lived on the file tables** became module locals:
  `CT.fs/host/frame`, `HP.hooked/note/state`, `MP.armed/hooked`, `TP.panel`.
- **TokenSheet** reads colours and text styles by name through casts of
  `T.color` / `T.type` to maps, and wraps those reads in `assert(...)`. An
  unknown name raised an error in `unpack(nil)` before, and raises one in
  `assert` now.
- **PresetSpellIDs** is in the exact form `tools/gen_presets.lua` writes. I
  ran the generator in a scratch copy and its output was byte-identical to
  the ported file. The worktree's Data files were not touched.
