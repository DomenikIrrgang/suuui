# Port notes: ui-hud

Files: `src/UI/ActionBar`, `ActionButton`, `CooldownTracker`, `SwingTimer`,
`ThreatMeter`, `DamageMeter`, `Readiness`, `KeybindMode` (all `.wowlua` now).

## 1. VM suspicions

(The VM wasn't run for these files.)

## 2. Compiler/tooling issues (0.9.1)

### H1. A plain `const x: T = { … }` takes the literal's type, not `T`

C1 (`Docs/wowlua-port-notes.md`) is not only about exports: a module-local
`const` with an annotation ignores the annotation as well. With a map of
functions, the value type becomes the first function in the literal:

```wowlua
const H: { [string]: (...any) -> () } = { A = function() end }
for _, h in pairs(H) do h(1) end   -- E2006: too many arguments: expected 0, got 1
local L: { [string]: (...any) -> () } = { A = function() end }
for _, h in pairs(L) do h(1) end   -- fine (and L.A is optional, as a map read should be)
```

Repro: `scratch-ui-hud/X` (fresh `wowlua new`, strict). Workaround: every
annotated table in these files is `local X: T = { … }` (the annotation is
checked, and map reads are optional as they should be); the exported list
is `export local actionButtons: any[] = {}` (as `data.md` D3).

### Narrowing (already written up by others)

- `canaccessvalue` doesn't narrow: see `ui-units.md` U2 / `units-social.md`.
- `wowlua:secret`'s `isSecret` doesn't narrow inside SuuUI (any import
  cycle in the project switches it off): `units-cooldowns.md` C-cd1. These
  files keep `isSecret` (from `wowlua:secret`) where no narrowing is needed
  and use the global `issecretvalue` where it is (a class as a map key,
  `C_Spell.GetSpellName`, trait spell IDs, aura data).

## 3. Stdlib gaps

### wowlua:secure for bar 1's paging (ActionBar)

`actionBar` registers its paging with `RegisterStateDriver(header, "page",
cond)` when the bar is made, and the header's `_onstate-page` snippet
rewrites each button's `action` attribute in the restricted environment.
`secure.state(frame, name, cond, fn)` would defer the registration to the
end of combat and add a Lua `OnAttributeChanged` hook calling `fn`; the bar
neither wants a Lua callback (the art follows the same conditions through
`SecureCmdOptionParse` on the events) nor the deferral. Kept as written,
with `SecureHandlerWrapScript`, the attributes and every `combat.run` guard.
The stdlib would need a `secure.driver(frame, name, cond)` that only
registers (now when possible), for snippet-driven states.

### wowlua:timer `nextFrame` for the action bars' passes

The cooldown / usable / active passes are coalesced per kind into one pass
on the next frame (a hidden frame's OnUpdate and a `due` set: a cast fires
several of each event in one frame). `nextFrame(fn)` runs every call
(no coalescing without the decorator), and `@nextFrame` coalesces one
function with the last call's arguments, not a set of kinds flushed
together. Kept SuuUI's flusher frame.

## 4. Port decisions

- **Tooltip lines' wrap flag (KeybindMode, ActionButton):**
  `GameTooltip:AddLine(text, UI.RGBA(token))` passed the colour's alpha as
  AddLine's fifth argument, `wrap`. `draw.rgba` always returns a number
  there, so every such line wrapped. Strict mode rejects a number for
  `wrap`; the port passes `r, g, b, true`, which is what happened before.
  (Probably not intended, but kept: same look.)
- **The action bars' event dispatcher (ActionBar)** now goes through
  Core/Events (`onGame`, owner "Action bars") instead of its own frame with
  `pcall(RegisterEvent)`: an event the client lacks never fires (wowlua:events
  checks `C_EventUtils.IsEventValid`), errors are reported as "Action bars",
  and handlers still get the payload without the event name and do nothing
  while no bar exists. The range poll for clients without range events has a
  frame of its own (`poller`). The dispatcher is insecure code; nothing secure
  changed.
- **`UI.actionTextSize`** was a field on `ns.UI`; it is now a module local
  in ActionButton (`setActionTextSize` sets it, buttons made later read it).
  Nothing else read it, but it was visible through the raw UI table.
- **Cooldown reads typed as possibly secret as a whole:**
  `C_ActionBar.GetActionCooldown` / `C_Spell.GetSpellCooldown` are typed
  `SpellCooldownInfo | Secret<SpellCooldownInfo>`. A helper
  `cooldownFlags(info)` (ActionButton, CooldownTracker) returns
  isActive/isOnGCD, false/false for a secret table. The original indexed the
  table directly; in game the table isn't secret (only its fields can be),
  so the result is the same. The API typing may be wider than the client.
- **Secret tests now come before truthiness tests** in a few places
  (`not issecretvalue(x) and x` where the original had `x and not
  isSecret(x)`, and `class == "ROGUE"` now checks for a secret first): the
  same result for readable values; a secret one now counts as unknown where
  the original would have raised an error testing it (readTalents runs in a
  pcall, so before it was "no talents read").
- **`C_Spell.GetSpellTexture`'s extra returns:** `iconFor`/`slotArt`
  (CooldownTracker) return `...any`, so `art:SetTexture(slotArt(…))` still
  gets every value the API returns, as before (the extra ones land in
  SetTexture's further arguments; left as it was).
- **Renamed locals, no behaviour change:** CooldownTracker's helpers `look`
  → `lookUp` and `has` → `listHas` (locals of the same names shadowed them);
  a `T` local (`Enum.UnitAuraSoundTrigger`) → `TRIGGER` (shadowed the tokens
  import); Layout's inner `place`/`rowWidth` parameters `cells`/`gap` →
  `row`/`spacing`, `hairline`'s `y` → `atY`; an unused `opts` in
  `TR:UpdateMissing` removed. KeybindMode imports `panel` as `uiPanel` and
  `button` as `uiButton` (a local `panel` and a click handler's `button`
  parameter keep their names). DamageMeter imports `select` as `uiSelect`.
- **KeybindMode** is no longer a table: its functions are the module's
  exports (`enter`, `exit`, `toggle`, `isActive`); `import * as keybindMode`
  gives the old shape. `isActive()` still returns nil before the first
  enter. The `ns.EditMode and …` / `ns.SettingsWindow and …` existence
  guards are gone (the modules are imports now).
- **wowlua:timer `after`** replaces `C_Timer.After` (ActionButton's GCD
  recheck and sweep-end recheck, CooldownTracker's reminder refresh and the
  half-second static-condition look): same delays, errors now reported.
- Our own frames keep `:HookScript` (the cooldown's `OnCooldownDone`, the
  buttons' hover and press hooks); `hookScript` is for Blizzard's frames.
