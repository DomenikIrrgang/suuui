# Port notes: units-bags

Files: `src/Units/Bags`, `MicroBags`, `Merchant`, `Mail`, `Loot` (all
`.wowlua`, strict). Only import: `SuuUI` from `/Core/API`.

## 1. VM suspicions

None (the VM wasn't run for these files).

## 2. Compiler/tooling issues

### GameTooltip's `SetInboxItem` and `SetSendMailItem` are declared with too few parameters

`crates/wowlua-api/data/shared.d.wowlua` (v0.9.1) has
`function SetInboxItem(index: any?)` and `function SetSendMailItem()`.
The game's mail code calls them as `SetInboxItem(mailIndex, attachmentIndex)`
and `SetSendMailItem(attachmentIndex)`, and SuuUI's mail window does too:

```wowlua
GameTooltip:SetInboxItem(1, 2)   -- E2006: too many arguments: expected 1, got 2
GameTooltip:SetSendMailItem(3)   -- E2006: too many arguments: expected 0, got 1
```

These two are in the shared (hand-written) declarations, not the client's
documentation, so they should be checked against the build's Blizzard UI
code (Blizzard_MailFrame) and fixed there. Workaround in `Mail.wowlua`:
`local tip: any = GameTooltip; tip:SetInboxItem(…)`, with a comment.

### A generic predicate leaves `T` unresolved

Already in `units-talents.md`; seen here with `plain<T>(v: T | Secret<T> | nil): v is T`
(repro in `scratch-units-bags/X`). These files use the non-generic predicate
the other Units use: `plain(v: unknown): v is string | number | boolean | table`.

## 3. Stdlib gaps

### `plain(v)` (present and not secret)

The same gap as `units-talents.md` and `units-character.md`: all five files
keep SuuUI's `plain`, now on `secret.isSecret` (same as the old
`issecretvalue or function() return false end`), typed as a predicate.
`secret.known(v, fallback)` would cover `plain(x) and x or y`, but not when
`x` can be `false` and `y` is truthy, and not the guards (`if plain(n) then`).

## 4. Port decisions

- **Hooks and timers through the stdlib.** `hooksecurefunc` → `hook` and
  `HookScript` on Blizzard's frames (MerchantFrame, MailFrame, OpenMailFrame,
  LootFrame, GroupLootContainer, BankFrame) → `hookScript`; `C_Timer.After`
  /`NewTimer` → `after`, `NewTicker` → `every`. Both still go through
  `hooksecurefunc`/`HookScript`/`C_Timer`, so they are still post-hooks; the
  one difference is that an error inside a hook or timer is now reported
  through `wowlua:errors` (xpcall) and doesn't propagate. For the bag hooks
  (`ToggleAllBags`, `OpenAllBags`, `CloseBag`, … in `Bags.wowlua`) that means
  an error in SuuUI's hook can no longer break the caller's chain (Esc
  closing bags). Worth a look in game: Esc with the bags open in combat
  (`/suu probe taint`), and using an item from the bags in combat.
- **Kept as they were (secure and taint paths):** the
  `ContainerFrameItemButtonTemplate` slot buttons under frames whose ID is
  the bag, the `SecureActionButtonTemplate` buy cell (`type1 = click` on the
  game's purchase button, placed only out of combat), every
  `InCombatLockdown` guard, the hidden parent for Blizzard's bag frames, the
  off-screen BankFrame/MerchantFrame/MailFrame/LootFrame, and
  `TooltipDataProcessor.AddTooltipPostCall`. HookScript calls on SuuUI's own
  frames (windows, scroll areas, edit boxes) stay `HookScript`.
- **`plain(v)` compares before it tests for secrecy** (`v ~= nil and not
  isSecret(v)`), in every Units file. If comparing a secret with nil errors
  in the client, the order is wrong (the stdlib's `known` tests secrecy
  first). Left as it was; worth a probe.
- **`Bags.wowlua` `SortTarget`: `special` mixes bag keys and array slots.**
  `special[s.bag] = list` and `special[#special + 1] = list` write the same
  table. With profession bags in bags 1-4 the bag number and the array index
  collide (bag 2's slots join bag 1's list, with bag 1's family), and with
  two special bags `#special` may land after a hole, so `ipairs` skips one.
  The reagent bag alone (bag 5) works. Left as it was.
- **Small rewrites strict mode needed, same behaviour:**
  - `Loot`: a roll's `remaining` is now in the table literal (it was set
    right after); `lines()` fills a local list that `LINES` points at;
    `UnitGUID("target")` read once into a local; the player's
    `SuuUI.FullName("player")` cast to `string` (never secret);
    `GetModule("notifications")` read once; `tonumber(n) or 0` in
    `copperOf` (`n` matched `%d+`).
  - `Mail`: `Suggestions(text)` keeps the typed text in a local `typed`
    (narrowing didn't reach the closures through the reassigned parameter).
  - `Bags`: `junkAt` returns `(number?, number?)` and `Junk` tests
    `price and count` (count is set whenever price is); `it.count <
    (it.maxStack or 1)` (maxStack is set there); `pcall(C_Container.SortBank
    :: any)` keeps the no-argument fallback (the client declares
    `bankType` as required).
- **Types:** rows, windows and slot buttons (frames with fields of their
  own, and everything `SuuUI.UI.*` returns) are `any`. Records are typed
  where the code builds them: Merchant's `Entry`/`Cost`, Loot's `LootItem`,
  `Roll`, `Choice`, Mail's `Header`/`SuggestRow`, Bags' rail entries,
  snapshots, counts and the sort's `SortItem`/`SortSlot`/`Move`.
- **Warnings left:** unused locals `me` (Bags `ShowResults`), `name` (Mail
  `DrawOpen`), `count` (Loot `StartRoll`), and `label` shadowing the
  module-level `label` in Bags `SortTip`: all in the code as it was.
