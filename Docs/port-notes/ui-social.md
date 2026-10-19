# Port notes: ui-social

Files: `src/UI/GroupFinder.wowlua`, `GroupFinderListed.wowlua`,
`GroupFinderListing.wowlua`, `GroupFinderWho.wowlua`, `Guild.wowlua`,
`GuildControl.wowlua`, `Social.wowlua` (wowlua 0.9.1, strict).

## 1. VM suspicions

(VM not run.)

## 2. Compiler/tooling issues

### `export function x` silently replaces an unannotated local `x`; `f[k] = v` on a function value isn't an error

```wowlua
local items = {}

export function items(parent: Frame): Frame
    local f = CreateFrame("Frame", nil, parent)
    items[f] = true          -- indexes the function itself: no diagnostic
    return f
end
local function g(): number return 1 end
g[1] = true                  -- no diagnostic either
```

`wowlua check` (strict) accepts all of it: no shadowing/redeclaration warning
for the export over the local, and no error for an index assignment on a
function type. (With `local items: { [any]: boolean } = {}` the export is an
E2001, and `pairs(items)` after the function is an E2001 too, so the type
does change.) At run time `items[f] = true` would error ("attempt to index a
function value"). Found in `Social.wowlua`, where the weak sets of live pages
were named `contacts` and `raidGroups`, the same as the symbol map's export
names for `UI.Contacts` and `UI.RaidGroups`. Workaround: the sets are now
`contactPages` and `raidPages`.

## 3. Stdlib gaps

None. Used:

- `wowlua:hooks` `hook` / `hookScript` for every `hooksecurefunc` and every
  `HookScript` on a Blizzard frame in `GroupFinderListing` and
  `GuildControl`. `HookScript` on SuuUI's own frames (our buttons, scroll
  areas) stays a method call.
- `wowlua:timer` `after` for `C_Timer.After(0, …)` in
  `GroupFinderListing` (`L:Queue`).

## 4. Port decisions

- **ForeverLFG:** none of these seven files reach the library (no `ns.LFG`,
  no `SuuUI.LFG`). The Group Finder pages only take data through `SetData`
  and report through `on*` callbacks; `src/Units/GroupFinder` is what talks
  to ForeverLFG. No import needed.
- **Hooks are isolated now.** With `hook`/`hookScript`, an error in one of
  SuuUI's post-hooks on the game's group finder or guild control is reported
  (wowlua:errors `callIn`) instead of being raised into the Blizzard code
  that called the hooked function. Taint is unchanged (still
  `hooksecurefunc` / `HookScript` underneath).
- **Load-on-demand hooks in GroupFinderListing:** the six global functions of
  `Blizzard_GroupFinder_VanillaStyle` that were hooked by name are now
  `hook(_G, name, fn, { addon = "Blizzard_GroupFinder_VanillaStyle" })`
  (W8102 otherwise). `skinGroupFinderListing` only runs once
  `LFGListingFrame` exists (`src/Units/GroupFinder`), so `onAddonLoaded` finds
  the addon loaded and installs the hook at once, as before. The existing
  `if _G.X then` guards stay. The two hooks in the `for _, name in ipairs(…)`
  loop (`LFGListingPostButton_UpdateText`, `LFGListingBackButton_UpdateText`)
  keep `hook(name, fn)`: the names are dynamic, so the compiler doesn't warn,
  and they are guarded by `_G[name]`.
- **Import names:** namespace imports named after the file, except
  `uiText` (`/UI/Text`; `text` is a common local here, e.g. `B:SetData`'s
  `local text`) and `uiSelect` (`/UI/Select`; `select` is the Lua global).
- **GuildControl's `button()`:** its local `draw` function shadowed the
  `draw` import (`/UI/Draw`) and was called inside itself as `draw.paint`;
  renamed the local to `redraw`. `b.suuStyled` still holds it.
- **GuildControl `MEMBERS`:** `{ 5, "Promote" }` rows are `(number | string)[]`
  to the checker: `check(b, m[2] :: string)`.
- **Social `C:Draw`:** the `{ { "Online", online }, { "Offline", offline } }`
  pairs read back as `string | {}`: `ipairs(group[2] :: any)`.
- **Dead code removed (warnings, same behaviour):** the never-read `prev` in
  `GroupFinderListing` `L:LayoutTop`, and the unused loop variable `role` in
  `GroupFinderListed` `P:SetData` (`for k in ipairs(…)`).
- **Exported constructors take `parent: Frame`**; widget-building helpers take
  `any` where they receive the game's frames or SuuUI frames with fields of
  their own, and `d: any` for the `SetData` tables (public API data, no
  shape to check against).
- **Callbacks inside option tables** (`onChange`, `onTextChanged`) are
  annotated (`v: any`, `text: string`, `on: boolean`): E2050 while the
  widgets' option types weren't exported yet; harmless once they are.
- **Fields the game's frames get** (`GuildControl`: `ui.suuOwn`, `b.suuWhy`,
  `b.suuIconButton`, `new.suuPlus`, `o.suuFill`, …; `bg.suuArt` on our own
  textures): unchanged from the Lua, which writes them already. Not touched
  in the port; worth a look in a taint review, since `GroupFinderListing`
  explicitly avoids writing to the game's frames (`parts` table) while
  `GuildControl` does.
