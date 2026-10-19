# Port notes: diag-social

Files (all `src/Diagnostics/`, wowlua 0.9.1, strict, zero diagnostics):
`SocialProbe`, `LfgProbe`, `GroupProbe`, `RaidProbe`, `ChatPaletteProbe`,
`ChatProbe`, `PopupProbe`, `GameMenuProbe`, `SupportProbe`, `MicroProbe`,
`MinimapProbe`, `MapPinsProbe`, `CalendarProbe`, `NpcPortraitProbe`,
`WindowsProbe`.

## 1. VM suspicions

(VM not run.)

## 2. Compiler/tooling issues

### `JoinChannelByName`'s `hasVoice` is required in the typings; through `pcall` the error names the wrong thing

```wowlua
export function f()
    JoinChannelByName("LookingForGroup")                    -- E2007: missing argument `hasVoice` of type `boolean`
    local ok = pcall(JoinChannelByName, "LookingForGroup")  -- E2001: `(channelName: string, password: string?,
    return ok                                               --   frameID: number?, hasVoice: boolean) -> (number, string?)`
end                                                         --   is not assignable to `("LookingForGroup") -> (number, string?)`
```

`password` and `frameID` are optional but `hasVoice` is not, so the
one-argument call SuuUI (and, as far as I know, the game's own chat code)
makes doesn't check. Not verified against the client's API documentation
in this session: if the docs give `hasVoice` a default, the typing should
mark it optional. Also the `pcall` form reports an unassignable function
type rather than the missing argument, which is hard to read. Workaround in
`LfgProbe` (`join`, `timerJoin`): `pcall(JoinChannelByName :: any, "LookingForGroup")`.

## 3. Stdlib gaps

None. Used:

- `wowlua:secret` `isSecret` for every `issecretvalue or function() return false end`
  (and the `issecretvalue and issecretvalue(x)` guards in `SocialProbe` and
  `WindowsProbe`): the same answer, nil-safe on clients without secrets.
- `wowlua:timer` `after` for every `C_Timer.After`; `every(0.25, fn, 240)`
  for `ChatPaletteProbe`'s `C_Timer.NewTicker` (the handle is cancelled the
  same way).
- `wowlua:hooks` `hook` for `hooksecurefunc` (`PopupProbe`: StaticPopup_Show
  and _Hide; `SocialProbe`: the friend-adding functions), `hookScript` for
  `HookScript` on Blizzard frames (`ChatPaletteProbe`: the chat inputs'
  OnKeyDown / OnArrowPressed; `LfgProbe`: LFGParentFrame OnShow;
  `WindowsProbe`: the windows' OnShow). `SupportProbe`'s `HookScript` on its
  own panel stays a method call.
- `wowlua:lifecycle` `onAddonLoaded` for `WindowsProbe`'s
  `EventUtil.ContinueOnAddOnLoaded` (same: now if loaded, else on its
  ADDON_LOADED), and `@onLogin` for `LfgProbe`'s PLAYER_LOGIN frame that
  resumes the chat recorder.

## 4. Port decisions

- **Exports** follow the symbol map (`command`, `sample`, `snapshot`, ...).
  `command` keeps each probe's own signature: no parameter where the old
  `X.Command()` took none (`chat`, `micro`, `calendar`, `mappins`,
  `npcportrait`, `support`, `gamemenu`); Probe.wowlua already calls them so.
- **`SocialProbe.showsBlizzardSocial()`** returns a module-local flag that
  `friendSystem()` sets, where it set `ns.SocialBlizzard = true`.
- **`LfgProbe` reaches ForeverLFG** through the workspace package:
  `import lfg as foreverLFG from "foreverlfg"` plus
  `import type ForeverLFG from "foreverlfg"`, annotated where used
  (`local LFG: ForeverLFG = foreverLFG`), as `libs/ForeverLFG/src/init.wowlua`'s
  header says (0.9.1 types another package's values as any).
  `Docs/port-notes/foreverlfg.md` didn't exist yet when this was written;
  check it agrees once it does.
- **State that lived on the module tables** (`GP.panel`, `LP.button`,
  `LP.openArmed`, `SP.notesButton`, `WP.journalHooked`, `WP.shownHooked`, ...)
  is now module-local. Nothing outside the files read it.
- **`SuuUIProbe = SuuUIProbe or {}` lines are gone**; every probe writes
  `DB.probe.<same key>` with the same layout. `GameMenuProbe`'s
  `SuuUIDB and SuuUIDB.errors or {}` is `DB.db.errors or {}` (DB is always
  bound once a command runs).
- **Guards dropped because imports always exist:** `RaidProbe`'s
  `if ns.ApiDocs and ns.ApiDocs.Dump`, `SocialProbe`'s
  `ns.Modules and ns.Modules.Get`. `WindowsProbe`'s
  `EventUtil and EventUtil.ContinueOnAddOnLoaded` guard went with the switch
  to `onAddonLoaded` (which always works); on a client without EventUtil the
  probe would now still hook the load-on-demand windows later.
- **Hooks are isolated now:** an error in one of these probes' post-hooks is
  reported instead of raised into the Blizzard code that ran the hook. Taint
  is unchanged (still hooksecurefunc / HookScript underneath).
- **`ChatPaletteProbe` writes `_G.ChatEdit_CustomTabPressed`** (wrap and put
  back) exactly as before: that global write is the test.
- **Renames to avoid shadowing** (no behaviour change): `LfgProbe`'s chat
  event handler `record` → `recordLine` (the export is `record`), a local
  `after` → `listed`, `names` → `localeNames`, `note(text, show)` →
  `note(text, loud)`; `SocialProbe`'s module `listener` →
  `presenceListener`, `menu`'s `dump(label, menu)` → `dump(label, m)`.
- **Bug noticed and left (harmless):** `WindowsProbe.static()` called
  `show(C_AddOns.IsAddOnLoaded(a))`; `IsAddOnLoaded` returns two values, so
  the second landed in `show`'s `depth`. It only matters for tables, so the
  output is the same; strict mode flagged it and the call is now
  `show((C_AddOns.IsAddOnLoaded(a)))`.
- **Casts for secrets:** `RaidProbe` compares `(me :: any) == true` and
  `(target :: any) == guid` after its own `plain()` checks (which aren't type
  guards); `SocialProbe` passes `SuuUI.FullName("player") :: any` and a
  roster name `:: any` to `Ambiguate`, as the old code did with whatever came.
