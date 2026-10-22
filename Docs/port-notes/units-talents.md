# Port notes: units-talents

Files: `src/Units/Talents.wowlua`, `Spellbook.wowlua`, `Legacy.wowlua`,
`Convergences.wowlua`, `Welcome.wowlua` (wowlua 0.9.1, strict, 2026-10-20).
All five check with no errors and no warnings.

## 1. VM suspicions

(the VM wasn't run for these files)

## 2. Compiler/tooling issues (0.9.1)

### A generic type predicate leaves `V` unresolved when the argument has no `Secret` member

```wowlua
local function plain<V>(v: V | Secret<V> | nil): v is V
    return (v :: any) ~= nil
end
local map = C_Map.GetBestMapForUnit("player")   -- number?
if not plain(map) then return end
C_Map.GetPlayerMapPosition(map, "player")       -- E2001: `V` is not assignable to `number`
```

With an argument typed `nil | number | Secret<number>` (`UnitRace`'s third
value) the same predicate narrows to `number` as expected; only a type
without a `Secret<…>` member leaves `V` itself in the narrowed type.
Repro: `scratch-units-talents/X`. Workaround: a non-generic predicate
(below).

## 3. Stdlib gaps

### `wowlua:secret` has no "readable and present" predicate

Every one of these files has SuuUI's `plain(v)`: not nil and not secret,
used as a guard (`if plain(x) and x > 0`), as `plain(v) and v or fallback`,
and before a call (`plain(id) and id and Api(id)`). `secret.known(v,
fallback)` covers only the third form for non-boolean values, and
`secret.isSecret` narrows the secret away but not the nil. The port keeps
`plain` and declares it as a predicate so strict mode narrows through it:

```wowlua
local function plain(v: unknown): v is (string | number | boolean | table)
    return v ~= nil and not isSecret(v)
end
```

(Talents, Legacy, Convergences.) The stdlib could offer exactly this
(`secret.plain(v)` / `secret.readable(v)`), narrowing `T | Secret<T> | nil`
to `T`.

## 4. Port decisions

- **Timers and hooks** go through the stdlib: `C_Timer.After` and
  `C_Timer.NewTimer` → `after` (the handle still has `Cancel`, used by the
  Spellbook's `levelTimer`/`sayTimer`); `hooksecurefunc(obj, "M", fn)` →
  `hook(obj, "M", fn)`; `HookScript` on Blizzard's frames (PlayerSpellsFrame
  tabs, LegacySystemFrame and its pages, CharacterFrame) → `hookScript`.
  `HookScript` on SuuUI's own frames (the Talents window, `UI.TalentTree`,
  `UI.Spellbook`, `UI.LevelUp`, a text field's edit box) is unchanged. The
  one difference: an error inside these callbacks is now reported through
  wowlua:errors (`callIn`) instead of reaching the game's handler.
- **Secure handling unchanged.** The Spellbook's secure spell buttons still
  get `type`/`spell` attributes only in `Render`, which returns (and waits
  for `PLAYER_REGEN_ENABLED`) in combat; every `InCombatLockdown` guard,
  the protected window resizes (`Shorten`/`Size`/`Restore`) and the Talents
  override binding (`BindKeys`) are as they were.
- **Casts on your own identity** (never secret; strict mode can't know):
  Talents' `CLASS` (`UnitClass("player")`) and `charKey()`'s return
  (`UnitGUID`/`UnitName` fallback) are cast to `string`; Convergences'
  `fromMe` casts `UnitFullName("player")`'s name and realm to `string`;
  Spellbook passes `UnitClass`'s classID as `classID :: number` to
  `GetSpecializationInfoForClassID` (inside the existing `pcall`). No guard
  was added: behaviour is exactly as before, including the (impossible)
  secret case.
- **`a: any` in Convergences' `blessing()`**: the aura from
  `GetPlayerAuraBySpellID` is typed `AuraData | Secret<AuraData>`; the code
  reads `a.expirationTime`/`a.duration` only after its own `plain` guards on
  those fields, so the local is `any` (as it was in Lua).
- **`_G.LE_PARTY_CATEGORY_INSTANCE`** (Convergences): the global isn't
  declared for camelot; read through `_G`, same value.
- **Text styles by name** (Welcome): `T.type[style]` with a run-time name
  goes through `styleOf(style)` (`(T.type :: any)[style]`); `LINE`'s
  metatable is cast to `{ caption, label, body: number }`. `hex(token)` in
  Legacy/Spellbook reads `(T.color :: any)[token]` the same way.
- **Welcome's summary** concatenates `SuuUI.RolePresetName(r.id)` (typed
  `string?`): cast to `string`, as before it would error on nil.
- **Small cleanups with no runtime effect**: Spellbook's unused `plain` local
  removed; Legacy's second `local S = T.space` inside `M:Page` (shadowing the
  identical file-level one) removed; parameters that were reassigned and
  then captured by closures got a fresh local (`stepsOf`'s `depth`,
  `coins`/`coinText`'s `copper`, `LevelGained`'s `level`) so the narrowing
  holds. Legacy's `closeness` reads `(tonumber(b) or 0)` / `(tonumber(a) or
  0) / (tonumber(b) or 1)`: the captures are `%d+`, never nil.
- Most Blizzard/SuuUI data parameters (nodes, trees, builds, spots, pages)
  are `any`: they are SavedVariables records and component frames with
  fields of their own; numbers, strings and callbacks are typed.
