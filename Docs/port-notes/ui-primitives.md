# Port notes: UI primitives

Files: `src/UI/{Draw,Text,Icon,Bar,Panel,Layout,Controls,Inputs,Select,Pickers,SettingRow,SettingsMatrix,TabMarker,Crest,LoadingMark,Stage,Visibility}.wowlua`.

## 1. VM suspicions

None (the VM was not run for these files).

## 2. Compiler/tooling issues (0.9.1)

### `cond and 1` is typed `number | boolean`, so narrowing leaves `number | true`

```wowlua
export function f(key: string): number
    local dir = (key == "UP" and 1) or (key == "DOWN" and -1)
    if not dir then return 0 end
    return dir * 2      -- E2001: arithmetic on a value of type `number | true`
end
```

`a and b` with a boolean `a` can only be `false` or `b`, so the type should be
`false | number`. Excluding the falsy members then gives `number`, as it does
for a parameter declared `number | false`. A cast of the initializer
(`local dir = (…) :: number | false`) doesn't help: the local keeps the
inferred type. Only an annotation works. Workaround in `Inputs.wowlua`
(NumberField's arrow keys): `local dir: number | false = …`.

### An array literal is not assignable to a record with a numeric indexer and an optional field

```wowlua
type Art = { [number]: any, jewel?: boolean }
local a: Art = { "x", 1, 2 }              -- E2001: `(1 | 2 | "x")[]` is not assignable
local b: Art = { "x", 1, 2, jewel = true } -- fine
```

`jewel` is optional, so the literal without it should fit (§2.2.4 lists
`{ [number]: V, n: number }` for tables used both ways). `any[] & { jewel?:
boolean }` fails the same way. Workaround in `Crest.wowlua` (the dragon art
table): `{ … } :: any` on the three entries without a jewel.

### Notes (by the spec, not bugs; patterns others will hit)

- A record type's `x: T?` field is required-but-nilable; `x?: T` is optional.
  Options tables (`{ layer = "OVERLAY" }` for `BorderOptions`) need `x?: T`,
  or a literal without the field doesn't fit (E2001).
- `opts = opts or {}` reassigns the parameter, so closures see it as `T?`
  (E2005 on `opts.onClick` inside a script handler). A default parameter
  (`opts: ButtonOptions = {}`) fixes it; used for `button` and `moneyInput`.
  (It differs from `or {}` only for `opts = false`.)
- Widget values are open (unknown fields read as `any`), and so are
  interfaces that extend a widget type: `export interface Panel extends Frame`
  plus a cast at creation (`CreateFrame("Frame", …) :: Panel`) types the
  frames and their fields without changing the code. A mixin table is typed
  the same way (`local Panel = {} :: Panel`), so `function Panel:Fit()` sees
  `self` as the frame. A `setmetatable` class (`Border`, `SoftEdge`,
  `TabMarker`, layouts) takes `(Border :: any).__index = Border` and
  `setmetatable({…}, Border :: any) :: Border`.

## 3. Stdlib gaps

### `wowlua:hooks` on hot widget setters

`Draw.wowlua`'s paint keeps a token colour with a region and lets it go when
the code sets the colour another way, through `hooksecurefunc(region,
"SetVertexColor" | "SetColorTexture" | "SetTextColor" | "SetStatusBarColor" |
…, letGo)` on every painted region. Those setters run in hot paths (bars,
unit frames), and the hooks fire on every call for the region's lifetime.
`hook(region, setter, fn)` wraps `fn` in `callIn`, which builds an argument
table, a closure and an `xpcall` on every call. Draw keeps `hooksecurefunc`
there. The stdlib could offer a lean form for hooks that can't fail
(`hook(t, name, fn, { isolate = false })`), or an isolation that only
allocates when an error happens. (Panel's `hook(modal, "Show", attach)` uses
the stdlib.)

### `secret.flag` vs `UI.Flag`

`Text.wowlua`'s `flag(v)` keeps its own body: `secret.flag(b)` returns
`b == true`, while SuuUI's turns any truthy value into `true` (callers pass
non-boolean game results). `isSecret` from `wowlua:secret` replaces the
`issecretvalue or function() return false end` fallbacks (same behaviour).

## 4. Port decisions

- **`ui` (was `ns.UI`)** is exported from Draw as an empty table. In the old
  code every UI file filled `ns.UI`; now each exports its own functions, so
  `SuuUI.Raw.UI` (unstable, documented as such) holds nothing unless the API
  port fills it. The API owner should decide.
- **Exported types** for what the builders return: `draw.Border`,
  `draw.SoftEdge`, `draw.Cross`, `text.Text`, `icon.Icon`, `bar.Bar`,
  `panel.Panel` / `WindowFrame` / `KeyChip` / `SectionHeader` / `ScrollArea`,
  `controls.SuuButton` (named so because `Button` is the widget type) /
  `StateBadge`, `inputs.Toggle` / `Checkbox` / `Segmented` / `Slider` /
  `Stepper` / `StepButton` / `TextField` / `NumberField` / `MoneyInput` /
  `Glyph`, `select.Select` / `SelectList` / `SelectOption`,
  `pickers.AnchorPicker` / `AnchorButton` / `SwatchRow` / `ToggleChips`,
  `settingRow.SettingRow` / `SettingsGroup`, `settingsMatrix.SettingsMatrix`,
  `tabMarker.TabMarker`, `crest.Crest` / `DragonArt`,
  `loadingMark.LoadingMark`, `stage.ModelStage`, `layout.Layout`, plus an
  `…Options` type per builder.
- `WindowFrame`'s `DrawTabs` and `SetTab` are declared as methods although
  they exist only on windows with tabs (as before).
- `TabMarker:Place` returns `(number?, any, any, any)`: it returns a single
  nil while the button isn't laid out, which the checker won't take for a
  four-number return.
- `paint(region: Region, …)`: StatusBar and EditBox are accepted (Frame
  extends Region in the declarations).
- Visibility calls `editMode.isActive()` and `keybindMode.isActive()` without
  the old `ns.EditMode and` guards: both modules always exist now.
- `C_Timer.After` / `NewTimer` became `after` from `wowlua:timer` (Bar's
  ghost hold, LoadingMark's loop start, TabMarker's retry, ScrollArea's
  settle, SettingRow's relayout). An error in the callback is now reported
  through `wowlua:errors` instead of the default handler.
- Parameters renamed where they would shadow an import or export: Draw's
  `size` → `px` (diamond, cross), `text` → `value` / `label` / `typed` /
  `query` in Text, Controls, Inputs, Panel (Confirm's `confirm()` → 
  `confirmIt()`), Select, SettingRow. No behaviour change.
- `Draw.shadow` with a token that has only inset layers errors on a nil
  index, as before (a cast keeps that path).
- Owner strings for events (`"UI.Panel"`, `"UI.Button"`, `"UI.Slider"`, …)
  are kept: they name the listener in fault reports.
- Not mine, seen while checking: `UI/RaidPlanner.wowlua` passes a value typed
  `{ [string]: any }` as `panel.panel`'s parent (E2001 there; `parent` is
  `Frame`).
