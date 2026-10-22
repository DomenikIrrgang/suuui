# Port notes: units-hud

Files: `src/Units/ActionBars.wowlua`, `Auras.wowlua`, `CastBars.wowlua`,
`UnitFrames.wowlua`, `SwingTimer.wowlua`, `Threat.wowlua`, `Timeline.wowlua`,
`DamageMeter.wowlua` (wowlua 0.9.1, strict). Each imports only `SuuUI` from
`/Core/API` plus stdlib modules; none exports anything.

## 1. VM suspicions

(VM not run.)

## 2. Compiler/tooling issues

### An import cycle anywhere turns stdlib imports into `any` (same as units-cooldowns C-cd1)

Confirmed separately, with one addition: not only does `isSecret` stop
narrowing, every stdlib import reads as `any`, so calls to `after`, `every`,
`hook`… aren't checked either. Minimal repro (scratch project, strict):

```wowlua
-- a.wowlua
import b1 from "/b"
export function a1(): number return b1() end
-- b.wowlua (a lazy cycle: used only inside functions)
import a1 from "/a"
export function b1(): number return 1 end
export function b2(): number return a1() end
-- e.wowlua
import isSecret from "wowlua:secret"
local t: nil = isSecret                 -- accepted (should be E2001)
local _, class = UnitClass("player")
if not isSecret(class) and class == "ROGUE" then end   -- E2040
```

Without b.wowlua's import of `/a`, `t` gets E2001 (`(v: unknown) -> boolean`)
and the narrowing works. SuuUI's Core has such cycles (Events ↔ Fault), so
this won't go away when the port is done. An E1012 (missing export) does
not trigger it; an E1014 load-time cycle does too.

Workaround in `Threat.wowlua` and `UnitFrames.wowlua` (the two files that
narrow through it):

```wowlua
import isSecret as isSecretValue from "wowlua:secret"
local function isSecret(v: unknown): v is Secret<unknown> return isSecretValue(v) end
```

The other files don't narrow through a stdlib import (`readable`/`plain` in
Timeline and Threat are local predicates). To check them as they'll be
once this is fixed, the files were also checked with the stdlib's
signatures pasted in as local functions (`isSecret`, `after`, `every`): no
errors either way.

### `C_Spell.GetSpellCooldown` is typed `SpellCooldownInfo | Secret<SpellCooldownInfo>`

Threat reads `cd.isActive` / `cd.duration` and guards the fields (SuuUI's
probes found the table plain with secret fields, which is how the code
treats it). The declaration makes the whole table secret, so field access is
E2040. Workaround: `C_Spell.GetSpellCooldown(id) :: SpellCooldownInfo?`
(`running` in Threat). Worth checking whether the table itself can be
secret; if not, the declaration should be `SpellCooldownInfo?` with secret
fields.

### A cast can't drop a `Secret<…>` member to a narrower type

`(pct :: number?)` on `number | colorRGBA | Secret<number | colorRGBA>`
is E2015 ("cannot assert"); `cls :: string?` on `nil | string | Secret<string>`
is accepted. Probably the `colorRGBA` member: the message could say which
member doesn't fit.

## 3. Stdlib gaps

### `inCombat` (Threat, DamageMeter)

Both files define `inCombat()` as `InCombatLockdown() or
UI.Flag(UnitAffectingCombat("player"))`: in combat as soon as the player is
affecting combat, before lockdown starts. `wowlua:combat` `inCombat()` is
only `InCombatLockdown()`. Kept. An `inCombat({ affecting = true })` (or an
`affectingCombat()`) would cover it.

### OnUpdate drivers (Threat, DamageMeter)

Each has a hidden frame whose OnUpdate counts down a tick (0.2 s, 1 s) and
which is shown/hidden as the on/off switch; `driver:IsShown()` is read as
state. `every` would need a stoppable and restartable ticker with an
`isRunning()` (and the first tick a tick after starting, as now). Kept.

## 4. Port decisions

- Stdlib used: `wowlua:timer` `after` (Auras, Timeline, DamageMeter) for
  `C_Timer.After`, `every` (Timeline's pull ticker) for `C_Timer.NewTicker`;
  `wowlua:hooks` `hook` for `hooksecurefunc` (ActionBars' main bar `Show`,
  Timeline's DBM/LibCandyBar `SetAlpha` and `Start`); `wowlua:secret`
  `isSecret` for `issecretvalue or function() return false end` and
  `issecretvalue and issecretvalue(x)` (ActionBars, Auras, Threat,
  Timeline, UnitFrames). UnitFrames' direct `issecretvalue(x)` calls are
  kept as they were (the global narrows).
- **Secure paths:** ActionBars' `hook(bar, "Show", silence)` is still a
  `hooksecurefunc` post-hook on Blizzard's main bar; the difference is that
  an error in `silence` is now caught (xpcall) and reported instead of
  raising inside Blizzard's `Show` caller. Nothing else on a secure path
  changed: unit watches, `RunOutOfCombat`, the combat checks,
  `SetAttributeNoHandler`, `HookScript` on SuuUI's own unit frames (left as
  method calls) are as they were.
- Timeline: DBM's `DBT.CreateBar` replacement stays a replacement (not a
  hook). `DBM` and `BigWigsLoader` aren't declared globals: read as
  `_G.DBM` / `_G.BigWigsLoader` at each use (not cached in a local: they
  load after SuuUI). `SuuUIProbe` (the countdown log) is still written as
  the global, as Units only use the public API (`/Core/DB`'s `probe` is the
  same table).
- Casts on values used unguarded before (no comparison added or removed):
  `UnitClass("player")`'s class as `string?` (ActionBars `CLASS`,
  UnitFrames `comboClass` and the combo setting's `disabled`) and `string`
  (Threat `playerClass`, which indexes `THREAT_DROPS` with it);
  `UnitGUID("player") :: string?` (Timeline `OnCountdown`, DamageMeter's
  preview API); `SuuUI.FullName("player") :: string` for `Ambiguate`
  (Timeline `OnMessage`).
- Types added: `Row` (Threat's threat-table row; `name`/`percent`/`raw` are
  `any`, as they may be secret), `Attachable` (ActionBars' attachable
  bars). ActionBars' `progress()` returns `(string?, any, any, any, any)`
  (XP numbers may be secret; the callers guard them). Data tables with
  mixed rows are `any[][]` (Timeline `TEST`, DamageMeter `RECAP`).
- Comment in ActionBars updated: `UI/ActionBar.lua` → `UI/ActionBar.wowlua`.
- Warnings that were in the Lua already, left: unused `T` (SwingTimer,
  Threat, Timeline), unused `now` (Timeline `M:PreviewView`).
