# Bottom UI Replacement

Replaces everything Blizzard draws along the bottom edge: action bars and their art, the
micro menu, the bag bar, the experience bar and the reputation watch bar, plus the
stance/pet/possess bars that live in the same cluster.

Concept and the option set it came from: artifact `suuui-bottom-ui-replacement-concept`.

---

## Locked decisions

| # | Area | Choice |
|---|---|---|
| 1 | Button style | **A2 seamless grid, on a glass plate.** No per-button border. One translucent gradient plate with hairline `colorBorder` dividers between cells. |
| 2 | Arrangement | **B3 hybrid dock.** Bar 1 publishes attach points; every other bar, the XP bar and the rep bar carry an `Attach To` dropdown (dock / detached with own position + width). |
| 3 | Button engine | **E2 own secure buttons.** New `Components/ActionButton.lua` on `SecureActionButtonTemplate`; Blizzard's action *system* stays the data source. |
| 4 | Micro menu | **C2 glyph + short label**, with a `micro_show_labels` toggle that drops the labels and collapses it to glyph-only (C1). Each entry is its own field in the bar's `left` section. |
| 5 | Icon art | **I2 custom TGA atlas** in `Media/`, authored the way `Media/generate_logo.py` authors the logo. |
| 6 | XP bar | **X3 `StatusBar` with readout slots** (left/center/right dropdowns) plus a rested ghost fill. |
| 7 | Reputation bar | **R1 its own bar, identical in style and code path to the XP bar.** |
| 8 | Bag bar | **G1 one data bar field** — free slots, click toggles bags, tone by threshold. |
| 9 | Stance / pet / possess | **S1 own moveable bars** in the same style, auto-hidden when empty. |

---

## Phase 0 — verify the client before writing any code

This is an Anniversary client and it has already contradicted assumptions once
(`EditModeManagerFrame` exists, `TemporaryEnchantFrame` does not). **Every global named in
this spec is a hypothesis until these run.** Each line is kept under ~250 characters
because WoW's chat edit box truncates past 255 and fails with a syntax error.

```lua
/run for _,n in ipairs({"MainMenuBar","MainMenuBarArtFrame","MultiBarBottomLeft","MultiBarBottomRight","MultiBarLeft","MultiBarRight"}) do print(n,_G[n] and "Y" or "-") end
/run for _,n in ipairs({"MainMenuBarLeftEndCap","MainMenuBarRightEndCap","MainMenuExpBar","ExhaustionTick","ReputationWatchBar","MainMenuBarMaxLevelBar"}) do print(n,_G[n] and "Y" or "-") end
/run for _,n in ipairs({"StanceBarFrame","ShapeshiftBarFrame","PetActionBarFrame","PossessBarFrame","KeyRingButton","MainMenuBarBackpackButton"}) do print(n,_G[n] and "Y" or "-") end
/run print(#(MICRO_BUTTONS or {}),table.concat(MICRO_BUTTONS or {},","))
/run local t=UIParent:CreateTexture() print(t.SetGradient and "grad" or "-",t.SetGradientAlpha and "gradA" or "-",MainMenuBar and MainMenuBar:GetNumPoints())
/run print(NUM_ACTIONBAR_BUTTONS,NUM_ACTIONBAR_PAGES,GetActionBarPage(),HasAction(1),GetActionInfo(1))
```

Record the answers in this file before proceeding. Two of them change the design rather
than merely confirming it:

- **`MICRO_BUTTONS` is the canonical micro list.** The atlas covers the 13 glyphs drafted in
  the concept; any button the probe reports that has no glyph falls back to a text-only field
  rather than shipping a wrong icon.
- **`SetGradient` vs `SetGradientAlpha`.** The signature changed across client generations
  (`SetGradientAlpha` was removed in 10.0). Feature-detect and fall back to a flat translucent
  fill — the same degradation `Backdrop.Pill` makes where there is no mask API: a worse look,
  not a broken widget.

---

## The glass plate

"Glassy" is `Themes/` work, not a per-plugin literal. Reference is concept 02 of the chat
mockups: `linear-gradient(to bottom, rgba(12,14,18,.85), transparent)` over the world, with a
text shadow for legibility.

**WoW has no blur.** There is no `backdrop-filter` equivalent, so frosted glass is not
reachable and must not be promised. What reads as glass on this client is three things
together: a translucent dark fill, a vertical gradient, and a one-pixel lighter sheen along
the top edge.

New primitive, alongside `Apply` / `Pill` / `Circle` in `Components/Backdrop.lua`:

```lua
SuuUI.Backdrop.Glass(frame, { from, to, sheen, border, borderWidth, inset })
-- returns { SetColors, Refresh, Destroy }
```

- Two stacked textures: the gradient body, and a `Pixel.Line`-thick sheen at the top.
- `inset = 0` semantics identical to `Apply` — a borderless surface must cover its whole box.
- Where the gradient API is absent, draw the body as a flat fill at the midpoint alpha.

New tokens, added to **`Themes/Default.lua`, `Themes/Modern.lua` AND
`SettingsUI/Controls/ThemeTokens.lua`** (a token nothing exposes is a control that silently
does nothing):

| Token | Form | Meaning |
|---|---|---|
| `opacityGlass` | primitive | alpha at the plate's dense edge (~0.80 Default, ~0.85 Modern) |
| `opacityGlassFade` | primitive | alpha at its open edge (~0.30) |
| `opacityGlassSheen` | primitive | the top hairline's alpha (~0.10) |
| `colorGlass` | derivation | `colorGray950` @ `opacityGlass` |
| `colorGlassFade` | derivation | `colorGray950` @ `opacityGlassFade` |
| `colorGlassSheen` | derivation | `colorGray100` @ `opacityGlassSheen` |

Do **not** reuse `colorBarTrack`. It is a bar's empty track, and sharing it would mean a
retint of every health bar's background silently retints every action bar plate.

The plate takes **no mouse input**. Buttons enable their own; a plate that swallowed clicks
would make the gaps between buttons unclickable in the world.

---

## Combat lockdown — the constraint that shapes everything

A frame built from a secure template is protected, protection propagates **down** to
descendants and the refusal propagates **up**: while `InCombatLockdown()` is true the client
silently refuses `SetSize` / `SetWidth` / `SetHeight` / `SetPoint` / `Show` / `Hide` on any
frame whose subtree holds a protected one, and the player gets `Interface action failed
because of an AddOn`. This cost ten days on `UnitClickArea`; see "Protected Actions Go Through
A Secure Component" in `WOW_API_ENCAPSULATION.md`.

Rules for every bar in this feature:

1. **Geometry settles out of combat only.** Any settings change that resizes a bar checks
   `InCombatLockdown()`, sets a deferred flag, returns, and catches up on
   `PLAYER_REGEN_ENABLED`. Do not attempt the call and lose — a refused call costs the player
   a chat error you already knew was coming. `UnitFrame:_syncClickArea` is the reference.
2. **The dock grows away from the buttons.** A B3 dock that resized *around* its children
   would be refused mid-combat exactly when a bar shows or hides. Attached children extend the
   dock's bounding box outward, and the dock reports `coreInset` so `MoveableFrame` keeps the
   player's stored position meaning "where my buttons are".
3. **Nothing non-protected that resizes at runtime may contain a button.** Wrappers, dividers
   and the glass plate are siblings of the button grid or its ancestors — never a parent that
   itself resizes in combat.
4. **Attributes are stated once, at construction.** `SetAttribute` on a protected frame is
   refused in combat, which is why paging goes through a secure state driver instead of Lua.

---

## New components

### `Components/ActionButton.lua`

`SecureActionButtonTemplate`, attributes `type="action"` and `action=<slot>` set at
construction. The template's own handler performs the click; **never
`SetScript("OnClick")`** — observe through `PostClick` and emit `CLICKED`.

| Concern | Route |
|---|---|
| Icon / macro name / count | `GetActionTexture`, `GetActionText`, `GetActionCount` |
| Cooldown swipe | `GetActionCooldown` into a Blizzard `Cooldown` frame — same sanctioned exception `AuraIcon` already takes |
| Usable / out of mana | `IsUsableAction` |
| Out of range | `IsActionInRange`, on one **shared throttled ticker** for every button (never a per-button `OnUpdate`) |
| Current / auto-repeat | `IsCurrentAction`, `IsAutoRepeatAction` |
| Empty slot | `HasAction` |
| Drag and drop | `RegisterForDrag("LeftButton")`, `OnDragStart` → `PickupAction`, `OnReceiveDrag` → `PlaceAction`; respect `LOCK_ACTIONBAR` |
| Hotkey text | `GetBindingKey("ACTIONBUTTON<n>")`, refreshed on `UPDATE_BINDINGS` |

Events: `ACTIONBAR_SLOT_CHANGED`, `ACTIONBAR_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_USABLE`,
`ACTIONBAR_UPDATE_STATE`, `ACTIONBAR_PAGE_CHANGED`, `SPELL_UPDATE_COOLDOWN`,
`UPDATE_SHAPESHIFT_FORM`, `UPDATE_BINDINGS`, `PLAYER_ENTERING_WORLD`. Register the **union**
on one frame and dispatch to the buttons that care, as `DataBarWidget` does — not one event
frame per button.

Emits `CLICKED`, `MOUSE_ENTER`, `MOUSE_LEAVE`, `SIZE_CHANGED`. Deliberately **no**
`SetEnabled`: disabling means dropping mouse input, which the client can refuse on a
protected frame, and a `SetEnabled` that cannot be honoured when it matters is worse than
none — same reasoning as `StatusBar` and `UnitClickArea`.

### `Components/ActionBarGrid.lua`

Rows × columns of `ActionButton`s over one `Backdrop.Glass` plate, with hairline dividers
between cells. Owns the A2 look; owns no action slots (the plugin assigns them). Geometry
changes route through the lockdown guard in rule 1.

### Paging

A `SecureHandlerStateTemplate` header per bar plus `RegisterStateDriver(header, "page", …)`
with an `_onstate-page` snippet that rewrites its children's `action` attributes. This is the
only paging mechanism that works in combat, and stances/forms/stealth are by definition
in-combat transitions. Warrior stances, druid forms and rogue stealth all drive it.

### `DataField` gains an optional `icon`

C2 is an icon plus a short label. `DataField` today is deliberately **one font string** — the
prefix and value share it so the two cannot sit on different baselines. An icon is a texture
placed by the stack container, so it introduces no baseline problem, and extending the
existing field keeps the rail, the hover fill, the hug and the tone in one place.

- New props: `icon` (texture path), `iconCoords` (atlas `SetTexCoord`), `iconSize`.
- `SetIcon` / `SetIconShown`. With the label empty the field hugs to icon + `spaceMd` either side.
- **Coordination hazard:** `Components/DataField.lua` and its spec `Tests/spec/44_datafield_spec.lua`
  are currently modified in the working tree by the addon-buttons work. Rebase on whatever
  landed before touching either, and do not edit them while another agent is mid-mutation.

---

## Plugins

| Plugin id | Owns |
|---|---|
| `action_bars` | the bars, the dock attach points, the stance/pet/possess bars, Blizzard suppression for the whole cluster |
| `micro_menu` | one registered DataBar widget per micro button, the labels toggle, the atlas |
| `watch_bars` | the XP bar and the reputation bar (one plugin, one code path, two instances) |
| `bag_bar` | the `BAGS n` DataBar field |

### Suppression

Hidden with the **guarded-`OnShow` hook** from `plugin-authoring.md` ("A frame that re-shows
itself") and restored in `onDisable`. Never `UnregisterAllEvents` (nothing can enumerate a
frame's registrations, so `onDisable` could never hand it back). Never `SetParent(nil)`.
Clear the suppression flag **before** the restoring `Show()`.

`MainMenuBar` is layout-managed on this client, so suppression and any reposition need the
`hooksecurefunc` re-assert pattern `Plugins/DataBar/DataBar.lua` already uses, consulting a
`managed` table on every call because the hook cannot be uninstalled.

### Micro menu ordering

Each entry is its own widget in `section = "left"`, at `order` 10, 20, 30 … so a later
reorder UI has room and the clock, FPS and latency fields keep their existing positions.
**Read the current orders out of `TimeWidget.lua`, `FpsWidget.lua` and `LatencyWidget.lua`
first** rather than assuming.

### Settings, per the schema conventions

Sections become accordions and grouping is derived from order, so entries before the first
`section` stay always-visible — that is where each plugin's `enabled` toggle belongs. Bar
dimensions are **plugin settings** with a schema `default`, not theme tokens; spacing, font
steps and the glass tokens are theme tokens. Positions are `type="position"`.

`action_bars` uses `subtabs`, one tab per bar (`Bar 1`…`Bar N`, `Stance`, `Pet`, `Possess`),
each key declared **once** inside its tab. Per bar: `enabled`, `attach` (dock/detached),
`buttons`, `rows`, `button_size`, `spacing`, `width` (dead while docked, via `enabledIf`),
`show_hotkeys`, `show_macro_text`, `show_count`, `position`.

---

## Icon atlas

Follow `Media/generate_logo.py` exactly: geometry defined by numbers in the script, rendered
with Pillow, and a `verify()` that asserts the rendered pixels rather than trusting a comment
claiming precision.

- `Media/generate_micro_icons.py` → `Media/micro-icons.tga`, uncompressed 32-bit, power-of-two
  (a 4×4 grid of 32×32 glyphs in a 128×128 sheet).
- Monochrome white-on-transparent, drawn with `SetVertexColor` so the glyph follows
  `colorTextMuted` at rest and `colorAccent` on hover — the tint is what keeps the art
  theme-aware.
- Glyph order fixed in the script and mirrored as a Lua coord table; the 13 drafted glyphs are
  Char, Spells, Talents, Quests, Social, Guild, PvP, LFG, Map, Menu, Help, Bags, Keys.
- Neither the `.tga` nor the `.py` goes in the `.toc` — the `.toc` takes `.lua` only.

---

## Watch bars

One widget, two instances. Rested XP and the reputation standing are the only differences
that reach the component.

- **`StatusBar` gains a secondary fill.** Rested XP is a second fractional child behind the
  main fill. Extend the primitive rather than stacking two bars — a stacked pair would need
  its own alignment, resize and theme plumbing kept in step with the first.
- **Reputation colour is a game fact and already exists.** `Core/Game.lua`'s `ReactionColor`
  maps standing 1–8 onto the client's own bands. Do not add a colour token for it, and do not
  copy the table into the plugin.
- Readout slots reuse the unit frames' dropdown pattern: none / current-max / percent /
  remaining / rested. Rep adds faction name and standing.
- Both hide when they have nothing to say (max level, no watched faction), which is a
  visibility change flow layout already handles by skipping hidden children.

---

## Testing

`lua Tests/run.lua` from the addon root. No change ships until it passes, and new behaviour
needs a spec that would **fail without the change** — mutate the fix back and confirm the new
assertion goes red. Geometry assertions derive from `H.token(...)` and the text helpers, never
from pixel literals.

### The lockdown assertions are the ones that matter, and they are already expressible

The harness models lockdown by frame identity: `H.setCombat`, `H.getBlockedActions`,
`H.hasProtectedDescendant`. Assert **both** halves for every bar:

```lua
-- The rule: a frame that resizes must not contain a protected one.
expect(H.hasProtectedDescendant(dock:GetFrame()))
    .as("the dock must not contain the secure buttons").falsy()

-- The consequence: a mid-combat settings change is not refused.
H.setCombat(true)
H.resetBlockedActions()
SuuUI.Settings:Set("action_bars", "bar1_button_size", 34)
expect(#H.getBlockedActions()).as("nothing was refused").eq(0)
```

### Harness gaps to close first

Extend `Tests/harness/wow/`, cover the addition in `Tests/spec/00_harness_spec.lua`, and
document it in `TESTING.md`. The harness models geometry faithfully and the API *surface*
loosely, so a gap in the direction an assertion points cannot fail — that has burned this
project repeatedly.

| Missing | Where | Note |
|---|---|---|
| The action API (`GetActionInfo`, `HasAction`, `GetActionTexture`, `GetActionCooldown`, `IsUsableAction`, `IsActionInRange`, `GetActionCount`) | `wow/api.lua` | plus `H.setAction(slot, {…})` / `H.clearAction(slot)` staging that fires `ACTIONBAR_SLOT_CHANGED`, the same "state moves and the event fires" contract `H.setAuras` has |
| `SecureHandlerStateTemplate`, `RegisterStateDriver` | `wow/frame.lua` | a **recorder**, not an evaluator. Record the driver string and let a spec assert it; do not fake macro-condition evaluation, or a spec will assert against the model's own guess |
| `SetOverrideBindingClick`, `GetBindingKey` | `wow/api.lua` | enough to assert hotkey text and that binding happens out of combat |
| `Texture:SetGradient` | `wow/regions.lua` | record the two colours so a spec can assert the glass plate's gradient, and model the absent case so the flat fallback is reachable |

Also unprovable and to be stated rather than assumed green: `SetAttribute` is not gated by
the lockdown model, so "attributes are stated once" is a structural assertion only; and no
Edit Mode re-anchoring is modelled, so nothing here can prove the `hooksecurefunc` re-assert
actually fires in game — assert instead that the original anchor is stored before the frame is
touched, restored exactly on teardown, and that repeated re-asserts do not accumulate.

---

## Phases

Each phase ends green with its own specs and is independently verifiable in game.

| # | Phase | Acceptance |
|---|---|---|
| 0 | Probes | Every global in this file confirmed or corrected here |
| 1 | `Backdrop.Glass` + tokens | Plate renders in both themes, degrades to flat fill with no gradient API, tokens appear in the theme editor |
| 2 | Harness action API + state-driver recorder | `00_harness_spec.lua` covers each addition |
| 3 | `ActionButton` | Icon, cooldown, count, hotkey, usable and range states; drag in and out; `PostClick` emits; not `SetScript("OnClick")` |
| 4 | `ActionBarGrid` + `action_bars` bar 1, Blizzard cluster suppressed | Bottom cluster and gryphons gone, bar 1 functional, restored exactly on disable |
| 5 | Bars 2..N + the B3 dock | `Attach To` moves a bar between dock and free; `coreInset` keeps the stored position meaning the buttons; the lockdown pair above passes |
| 6 | Stance / pet / possess | Druid form swap, hunter pet, mind control exit all work; auto-hidden when empty |
| 7 | Atlas + `DataField` icon + `micro_menu` | Every micro button opens its panel; labels toggle collapses to glyph-only; unglyphed buttons fall back to text |
| 8 | `watch_bars` | XP with rested ghost fill and readouts; rep bar identical, faction-coloured from `Game.ReactionColor`; both hide when silent |
| 9 | `bag_bar` | Free-slot count with settings-driven tone thresholds; click opens bags |
| 10 | Docs | `architecture.md` (components, plugins, new tokens), `plugin-authoring.md` (secure bars), `WOW_API_ENCAPSULATION.md` (the state-driver carve-out), `TESTING.md` (harness additions), `README.md` |

Phase 4 is the first one worth a `/reload`: it is where Blizzard's art disappears and where a
suppression mistake is visible immediately.

---

## In-flight work to rebase on

Uncommitted at the time of writing, and this feature touches several of the same files:

- `Components/FlyoutPanel.lua`, `Plugins/AddonButtons/*` (new) — the addon-button tray
- `Components/DataField.lua`, `Components/ClickAway.lua`, `Core/DataBar.lua`,
  `Plugins/DataBar/*`, `Plugins/Performance/*`, `Plugins/MinimapButton/*` (modified)
- `Libs/` and the harness additions that came with the minimap button

Read the tree before starting. **Do not stage files you did not change.**
