# Port notes: ui-world

Files: `src/UI/ObjectiveTracker`, `MapPin`, `Professions`, `RaidPlanner`,
`Inventory`, `Legacy` (all `.wowlua`, strict).

## 1. VM suspicions

None (the VM wasn't run for these files).

## 2. Compiler/tooling issues

None new. One thing that is by design but easy to trip over: in a record
type, `id: any?` (or `id: number?`) is a field that must be present (it may
hold nil), so `{ zone = z }` isn't assignable to
`{ zone: string?, id: number? }`. An optional field is `id?: any`
(spec §2.2.4, table types). `ObjectiveTracker`'s `Entry`
uses that form.

## 3. Stdlib gaps

### `wowlua:pool` and RaidPlanner's `pool(list, i, make)`

RaidPlanner reuses frames by index: `pool(list, i, make)` returns the i-th
frame (made when it's missing) and shows it, then `hideFrom(list, n + 1)` hides
the rest. Frames stay in their slots, so row i is always the same frame
(its anchors and state carry over between draws). `wowlua:pool`'s
acquire/release hands out whichever free frame it has, so the code stays as it
was. If the stdlib had an indexed form (`pool:at(i)` plus `pool:trim(n)`), it
would fit.

## 4. Port decisions

- **LEGACY_CARD_H / LEGACY_TRACK_H** were mutable `ns.UI` fields that a
  theme change rewrote. Exported bindings can't change, so they're exported as
  the heights at load (`/Core/API` copies them into `SuuUI.UI` at load, as
  before). The theme handler still updates the public copies
  (`SuuUI.UI.LEGACY_CARD_H/_TRACK_H`), and Legacy uses a local `trackH`
  internally. The only other readers (`Units/Legacy`) go through `SuuUI.UI`,
  so nothing should change. Legacy imports `SuuUI` from `/Core/API` for this.
  The import is only used in the handler, so the cycle API → Legacy → API is
  run-time only.
- **`/UI/Text` and `/UI/Icon` are imported as `uiText` and `uiIcon`**, not as
  `text`/`icon`. These files have many parameters named `text` and `icon`, and
  two of them would have shadowed the module: RaidPlanner's
  `P:StartDrag(what, text, …)` and the chip's `b:SetText(text)` call
  `measureText` with that parameter in scope.
- **Inventory's secure bag slots:** `skinItemSlot` keeps the raw
  `b:HookScript("OnEnter"/"OnLeave")` on Blizzard's bag buttons, as the
  task asked: secure handling unchanged. `wowlua:hooks`' `hookScript` would
  also be a post-hook, but it wraps the handler in `xpcall`. Nothing is
  written on the button (the skin's state stays in its own table, as before).
  Other `HookScript`s are on SuuUI's own frames and stay as they are.
- `hooksecurefunc(b, "SetEnabled", …)` on Inventory's own sort button became
  `hook(b, "SetEnabled", …)` (`wowlua:hooks`): now an error in it is reported
  instead of thrown.
- RaidPlanner's `C_Timer.After(0, …)` (rename field focus lost) is now
  `after(0, …)` (`wowlua:timer`, `C_Timer.NewTimer`): same timing.
- **Colour escapes** in Money (`"|cff" .. hex .. unit .. "|r"`) and Legacy
  (pending points, a step's count) now use `colorize` from `wowlua:color`.
  The text is identical because every token `hex` is 6 lowercase digits
  (Tokens, the `Themes` hex(), VisionPresets). One difference: `colorize`
  errors on a malformed hex, where the old code built a broken escape.
- Event owners are unchanged (`"UI.Inventory"`, `"UI.Legacy"`,
  `"UI.Professions"`, `"UI.RaidPlanner"`, `"MapPin"`).
- Removed Inventory's unused `local PAD` (W1003; it was never read).
- Frames that get fields and methods of their own are typed `any`, and so
  are the method tables (`Tracker`, `Skin`, `Money`, `Inv`, `Points`,
  `Challenges`, `Track`, `P`: `{ [string]: any }`).
