# Test notes: ui-windows

Area: `src/UI/Reskin`, `WindowSkin`, `Tooltip`, `ContextMenu`, `FilterMenu`,
`Notification`, `Alert`, `Loot`, `LevelUp` and `MicroMenu` (`.wowlua`). Each
source file has one test file, `tests/unit/UI/<File>.test.wowlua`.
`tests/unit/UI/WindowsHelpers.wowlua` provides two helpers:

- `tokenOf(region)`: the colour token Draw keeps for a region, read with
  `import internal paints from "/UI/Draw"`.
- `themeChanged()`: emits `SUUUI_THEME_CHANGED`.

Reskin and WindowSkin are tested on Blizzard's own frames from the loaded
UI. The templates used are MinimalScrollBar, ColoredProgressBarTemplate,
WowStyle1DropdownTemplate, UIPanelButtonTemplate, InputBoxTemplate,
SearchBoxTemplate, UICheckButtonTemplate, SelectorButtonTemplate,
WowScrollBoxList, CharacterFrameSidePaneTemplate (its ScrollingFont),
BasicFrameTemplate, ButtonFrameTemplate and PanelTabButtonTemplate. The tests
also use the game's menus (`MenuUtil.CreateContextMenu`, a dropdown's
`SetupMenu`), StaticPopup, CharacterFrame and CharacterMicroButton. Where a
piece hooks a Blizzard method, the tests check that Blizzard's own call still
does its work: the hooks stay post-hooks.

## Files and coverage

Each source file was measured with `wowlua test -j 2 --coverage`, run on its
own test file.

| Source | Tests | Lines | Branches | Functions | Conditions |
|--------|------:|------:|---------:|----------:|-----------:|
| Alert | 16 | 90/90 | 38/44 | 6/7 | 16/20 |
| Loot | 13 | 84/84 | 27/28 | 9/9 | 5/6 |
| LevelUp | 26 | 176/176 | 94/114 | 15/15 | 59/78 |
| MicroMenu | 20 | 171/171 | 64/72 | 17/17 | 29/36 |
| Tooltip | 25 | 197/197 | 111/126 | 20/20 | 57/70 |
| ContextMenu | 17 | 132/132 | 42/44 | 14/14 | 3/4 |
| FilterMenu | 27 | 303/303 | 141/150 | 28/28 | 57/66 |
| Notification | 45 | 607/607 | 357/396 | 39/39 | 211/248 |
| WindowSkin | 35 | 339/339 | 224/258 | 39/39 | 139/170 |
| Reskin | 48 | 833/833 | 644/834 | 85/86 | 398/544 |

Every line runs. Alert's and Reskin's missing function is the `isSecret`
fallback for a client without `issecretvalue`. It is now marked
`-- wowlua: coverage ignore`, which these numbers were measured before. The
branches still open fall into a few kinds:

- **Unreachable sides of the `x and true or false` / `a and b or c` idiom.**
- **Guards for clients and frames that don't exist here.** Reskin's
  `ask(...)` checks and `bar.SetStatusBarTexture and …`-style checks for
  frames that have every method are one example. `TooltipDataProcessor and …`
  and `GetMouseFoci and … or GetMouseFocus` are others.
- **Structural cases.** For example, `opts and opts.name` always has `opts`,
  and a chosen menu row always has its indicator. Reskin's `menuRow` has
  `else mark:SetPoint("LEFT", row, …)` for a chosen row without an
  indicator, which cannot happen, because a row is chosen only by its
  indicator texture.

## Refactors

- **Tooltip: the spell post-call is now `spellPostCall(tooltip, data)`**, a
  file-level local. Before, it was an anonymous function inside
  `hookSpellTips`, and the tests reach it with `import internal`.
  `TooltipDataProcessor.AddTooltipPostCall` receives this function instead of
  the closure, which had captured nothing else. Behaviour is unchanged.
- **WindowSkin: `fitTabs(tabs, room) -> (short, gap)`.** This is the tab
  row's choice between full labels space-5 apart, full labels space-4 apart
  and the short labels. It moved out of `Chrome:LayoutTabs` into a
  file-level local, with the same computation, and `LayoutTabs` calls it.
- **Reskin: `lastingHookScript(frame, script, fn)`.** See the first bug
  under Bugs.

No exports were removed or changed. No new exports were added.

## Bugs found (fixed)

1. **Reskin: the game's pooled menu frames lost SuuUI's script hooks.**
   Blizzard sets the scripts on its menu frames each time it reuses them. On
   each row it lays out it calls `SetScript("OnEnter"/"OnLeave", …)`
   (`Menu.lua` `InitializeFrame`). On each menu it opens it calls
   `SetScript("OnHide", …)` (`Menu.lua`, the proxy's scripts after the pool's
   `SetToDefaults`). `SetScript` drops the hooks on that script, in the
   client and in the emulated client alike. Reskin hooked rows only once
   (`hooked[row]`) and menus only once (on their first restyle). The
   consequences were:
   - The arcane-soft hover band showed only on a row's first menu.
   - The `OnHide` that undoes the look never ran again. SuuUI's colours and
     hidden art then stayed on the game's shared menu frames when they were
     reused by other menus.

   The fix is a hook that goes on again right after the game sets the script:
   `lastingHookScript` hooks the frame's `SetScript`. This is still a
   post-hook, with no taint, and it is used for the rows' OnEnter/OnLeave, the
   menus' OnHide and the popups' OnHide. StaticPopup sets a popup's OnHide
   while it waits on events. The fix is checked in "reskinMenu: a context
   menu as glass…", which opens and closes a menu first and then checks the
   second menu's hover band and its undo.

No bugs were left with a skipped test.

## VM suspicions (emulated client)

1. **`Texture:GetAtlas()` still returns the old atlas after `SetTexture(file)`**,
   and `Button:SetNormalTexture(file)` behaves the same after
   `SetNormalAtlas`. In the client, setting a file clears the atlas. As a
   result, Reskin's `reskinCollapseButton`, which reads `GetAtlas()` first,
   would show the old state's glyph in the VM. The test sets its states in an
   order that avoids this.
   ```wowlua
   local t = CreateFrame("Frame"):CreateTexture()
   t:SetAtlas("ui-hud-minus")
   t:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
   print(t:GetAtlas())   -- VM: "ui-hud-minus"; client: nil
   ```
2. **`IsIgnoringParentAlpha()` answers false after `SetIgnoreParentAlpha(true)`.**
   The likely cause is the generic Set/Is rule, because the names differ.
   The Tooltip test doesn't check it.
   ```wowlua
   local f = CreateFrame("Frame"); f:SetIgnoreParentAlpha(true)
   print(f:IsIgnoringParentAlpha())   -- VM: false; client: true
   ```
3. **No OnSizeChanged for a frame resized through its anchors.**
   ColoredProgressBarTemplate's FillArea is anchored inside the bar, and
   `bar:SetWidth(12)` changes `FillArea:GetWidth()` to 0 but sends it no
   OnSizeChanged, even after frames. This is the same issue as in
   `ui-primitives.md` #2. The Reskin test sends the script itself
   (`mock.script(bar.FillArea, "OnSizeChanged", w, h)`).
4. **Unverified: a menu's submenu didn't open on hover.** Neither
   `mock.hover(row)` nor `mock.script(row, "OnEnter")` with
   `mock.advanceTime(0.5)` opened it. `description:ForceOpenSubmenu()`
   does. This may be the menu manager's mouse-event timer needing something
   the mock doesn't send, so it is not certain to be a VM gap. The test uses
   ForceOpenSubmenu.

## Runner / mock findings

1. **`mock.click` sends only the up click.** It calls `OnClick(button,
   down = false)`. In the client, a mouse click on a button registered for
   `AnyDown` and `AnyUp` gets OnClick twice, down then up. A
   SecureActionButtonTemplate button with `ActionButtonUseKeyDown = 1`, which
   is this client's default, acts on the down click. So `mock.click` on
   SuuUI's micro menu buttons does nothing, while a real click opens the
   window. The workaround is `mock.script(button, "OnClick", "LeftButton",
   true)`.
   ```wowlua
   local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
   b:RegisterForClicks("AnyDown", "AnyUp")
   b:SetAttribute("type", "click"); b:SetAttribute("clickbutton", CharacterMicroButton)
   b:SetSize(20, 20); b:SetPoint("CENTER"); b:Show()
   mock.click(b)                 -- CharacterFrame stays hidden
   mock.script(b, "OnClick", "LeftButton", true)   -- CharacterFrame shows
   ```
2. **A `mock.fake` of a global the Blizzard UI calls taints Blizzard.** This
   is the same issue as in `ui-units.md` #1. With
   `mock.fake("GetBindingKey", …)` in one test, a later test's untainted
   click that opened CharacterFrame failed with "attempt to compare … (a
   secret number value, while execution tainted by 'SuuUI')" in
   TextStatusBar. The WindowSkin test uses real `SetBinding` calls instead.
3. **The checker:** `local a, b: any, any = …` declares a third local named
   `any`, with only an "unused local `any`" warning. This is a typo in my
   own code, but the syntax could be rejected.
   (`local a: any, b: any = …` is the correct form.)

## Not tested, and why

- **Taint in the real client.** The emulated client's taint model covers
  the secure micro-menu click and the hooks. What the real game blocks is
  beyond what these tests show.
- **The `TooltipDataProcessor`-less fallback in `hookSpellTips`** (a client
  without the post-call API). The path where the post-call didn't run is
  tested with a spell the client has no data for.
- **Strict typing:** the components return `any` from their factories. They
  are `Mixin`ed frames without exported interfaces, so the tests hold them
  as `any`. Giving them interfaces would change the types that their many
  importers check against, which is outside this area.
