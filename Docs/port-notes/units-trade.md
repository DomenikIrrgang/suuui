# Port notes: units-trade

Files: `src/Units/AuctionHouse.wowlua`, `src/Units/Professions.wowlua`,
`src/Units/Trainer.wowlua`, `src/Units/Macros.wowlua` (wowlua 0.9.1, strict).
All four import only `SuuUI` from `/Core/API`; no exports.

## 1. VM suspicions

(VM not run.)

## 2. Compiler/tooling issues

### Money fields of C_AuctionHouse are declared `string` (Blizzard's `WOWMONEY`)

The 0.9.1 declarations type Blizzard's `WOWMONEY` as `string`; the game
returns numbers (copper). Comparing or doing arithmetic on them is an error:

```wowlua
local _, _, _, _, _, _, _, _, _, buyout = C_AuctionHouse.GetReplicateItemInfo(0)
if buyout > 0 then end                       -- E2001: cannot compare `string` with `0`
local c: nil = C_AuctionHouse.GetCancelCost(1)  -- reads `string`
```

`GetReplicateItemInfo` returns 8–11 (minBid, minIncrement, buyoutPrice,
bidAmount) and `GetCancelCost` read `string`; `CalculateCommodityDeposit`
reads `number?`, so it's per field. Workaround in `AuctionHouse.wowlua`
(`M:ReadScan`): `pcall(AH.GetReplicateItemInfo :: any, k)`. The other money
reads go through the file's `call` helper (returns `...any`), so they don't
hit it.

### `ItemLocation` is not a declared global

`ItemLocation:CreateFromBagAndSlot(bag, slot)` → E1001 (FrameXML's
`ItemLocationMixin` global). Workaround: `_G.ItemLocation:…`
(`AuctionHouse.wowlua`, `sellable()`).

### `SetTrainerServiceTypeFilter` declared `(type: string, enable: boolean, exclusive: boolean)`

SuuUI passes `1`/`0` for `enable` and no `exclusive` (the client accepts
both). `pcall(SetTrainerServiceTypeFilter, k, 1)` is an E2001. Workaround:
`pcall(SetTrainerServiceTypeFilter :: any, k, 1)` (`Professions.wowlua`,
`M:RecordTrainer`), keeping what is passed.

### (Pattern, not a bug) `field: T?` is a required field

`type C = { name: string?, n: number }` makes `{ n = 1 }` an E2001 ("`{ n: 1 }`
is not assignable to `{ name: string?, n: number }`"): the field must be
present (§2, `label?: string` is the optional one). The message doesn't say
which field is missing; worth a hint ("missing field `name`; use `name?:`").
Used `?:` in `Professions.wowlua` (`RecipeRow`, `Category`) and
`AuctionHouse.wowlua` (`Offer`).

## 3. Stdlib gaps

### Money text (`coins` in Trainer and AuctionHouse)

`wowlua:format` `money` gives coin icons (`GetMoneyString`) or the client's
words ("12 Gold 5 Silver"). SuuUI writes "1g 20s 5c" with each unit (or the
whole amount) in its theme token's colour, and the two files differ on
details (AuctionHouse shows `0s` between gold and copper). Kept. A
`money(copper, { units = { g = colorFn, … } })` style option would cover it.

### Thousands (`thousands` in AuctionHouse)

`format.number` uses the locale's separator; SuuUI's scan caption always
writes "48,183" (and floors first). Kept; `number(n, { separator = "," })`
would fit.

## 4. Port decisions

- `C_Timer.After` → `after`, `C_Timer.NewTicker` → `every` (wowlua:timer);
  `hooksecurefunc` → `hook`, `HookScript` on Blizzard frames (MacroFrame,
  ProfessionsFrame and its pages, the hidden AuctionHouseFrame /
  ClassTrainerFrame) → `hookScript` (wowlua:hooks). Same timing; an error in
  a callback is now reported by `callIn` instead of reaching the global
  error handler. `HookScript` on SuuUI's own frames stays a method call.
- `ADDON_LOADED` for `Blizzard_MacroUI` (Macros) and Professions' `Build` on
  every `ADDON_LOADED` stay `M:OnGameEvent` (tied to the module's lifetime),
  not `onAddonLoaded`.
- Casts on possibly-secret values that the code already used unguarded (no
  new comparisons added, behaviour unchanged):
  - AuctionHouse `M:DrawAuctions`: `UnitGUID("player") :: string?`, compared
    with a bid's `bidder` as before (outbid detection). If the player's own
    GUID can read secret, that comparison would error (as it would have
    before the port).
  - Professions `M:RecordTrainer`: `strsplit("-", guid :: string)` on
    `UnitGUID("npc")`, unguarded as before.
- Professions `M:Source`: `(faction :: string):find(...)`: a vendor entry
  without a faction part would error, as before (the shipped data always
  has it).
- Macros: `GetMacroInfo(a :: any)` for the cursor's macro index (typed
  nullable from `GetCursorInfo`).
- Professions `M:PickupOpener`: `GetMacroBody(i)` read once into a local
  instead of twice (needed for the narrowing; same result).
- Professions `M:Recipes`: the category sort casts `order`/`name` to
  non-nil (every category has both there; only the flat list made after has
  none). The flat list's table is now made before the `#all > 0` test (no
  observable difference).
- Unchanged warnings that were in the Lua already: unused `tint`
  (Trainer), unused `link` (AuctionHouse `M:DrawSell`), `mine` shadowed in
  Professions `M:Source`. Left as they are.
- Bug-ish, left: AuctionHouse `M:OnEnable` starts a 30 s ticker
  (`every(30, …)`) each time it runs and never cancels it; the module is
  reloadToToggle, so it runs once per session.
