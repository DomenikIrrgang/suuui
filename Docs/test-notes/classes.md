# Classes, interfaces and enums (branch wowlua-classes)

SuuUI moved its state into classes with interface-typed dependencies, its
components into widget classes, and its fixed string sets into enums
(`Docs/plans/classes-for-testing.md`). This records what was checked, what
became what, and what it turned up in wowlua (with the fixes, on wowlua's
branch `suuui-classes`).

## Step 1: widget classes and `Raw.Mixins`

`Raw.Mixins` promises plugins that a method changed on a component's table
when their file loads reaches every frame SuuUI builds afterwards. wowlua
0.9.7 flattened a widget class's methods into a mixin once, when the class
was defined, so a later change missed new frames. Fixed in wowlua (T268):
construction flattens the class chain as it is then. With that, a widget
class keeps `Raw.Mixins` semantics: `Raw.Mixins.Panel` is the class, and a
method changed on it reaches the panels, windows and bags built later.
`Extend`'s per-instance hooks (`rawset` on the frame) work on widget-class
frames unchanged.

## What became what

Core (each with tests "of its own" over `tests/fakes.wowlua`):

| Module | Class | Dependencies |
|--------|-------|--------------|
| Fault | FaultLog (Reporter) | FaultOutput, Meter |
| Events | EventBus (Notifier) | Dispatcher, Reporter |
| Combat | CombatQueue | CombatState, Reporter |
| Services | ServiceRegistry | Notifier |
| Extend | ExtendRegistry; enums Kind, List | Reporter, NextFrame, Notifier |
| Settings | SettingsStore, bound to saved data | Reporter, Notifier |
| Modules | ModuleRegistry; enum ModuleState | ModuleSettings, Runner, CombatState, Reporter, Notifier, release |
| Roles | enums Role, RoleSource | |

UI: every component that mixed a method table into a frame is a widget
class: Panel, WindowFrame (extends Panel) and its TabButton, Inventory and
Readiness, LootWindow, Alert, LevelUpCard, TooltipFrame (Panels),
RaidPlanner (a WindowFrame), UnitFrame (header buttons adopted), Text
(extends FontString, built with `Text.adopt`), Bar, the seven inputs, Select,
Icon, CastBar, ActionButton, the trackers and meters, and the rest. Objects
around a frame they don't own are plain classes: WindowChrome, UnitAuras,
ActionBar, SettingsPage, GuildControl, ListingSkin. The class bars are a
hierarchy: abstract ClassBar with StanceBar, PetBar and TotemBar.

ForeverLFG: EntryStore (Emit, clock, CatalogueApi, Config), with
`LFG.Store` kept as the published dot-call table over it; enums MatchReason
and ContactNews.

Plugin API 0.19: `Raw.Mixins` holds the classes (`WindowFrame` and
`ClassBar` added).

## Found in SuuUI on the way

- The slider's interface was named `Slider` and shadowed WoW's `Slider`: its
  own native slider field was typed as the component.
- Eight `return assert(x, "message")` in functions returning one value
  returned the message too (wowlua now types `assert` as Lua's).
- Interfaces claimed fields that only one variant has (the timeline's track
  parts, the group finder listing's activity parts, a filter menu's
  `changed` diamond): the classes type them as they are.

## Found in wowlua (fixed on `suuui-classes`)

Each with spec text, a decision and tests:

| Decision | What |
|----------|------|
| T268 | Widget classes flatten their methods at construction (`Raw.Mixins` semantics) |
| L35 | Parameter properties; `readonly` assignable only in its own constructor |
| T269 | Load order follows class methods and `@deferred` interface parameters |
| T270 | Load order follows constructions (`X.new()` at load reads the constructor's defaults) |
| L36 | `ClassOf<T>` binds `T`; `wowlua:reflect` typed as documented; expected types bind only where they fit |
| L37 | A parameter default reading itself or a later parameter is E1004 (it read the outer name in the checker, the parameter at run time) |
| L38 | `assert` returns every argument |
| L39 | A cast also compares the value's type without `nil` |
| L40 | Overloads take a last argument's several values; `GetTexture` gives file IDs |
| T271 | W1004 for a closure's `self` hiding a class method's `self` |
| L41 | A call on a field keeps the field's narrowing |
| L42 | `C.adopt(frame, …)` builds a widget class on an existing frame |
| L43 | Widget classes on regions (FontString, Texture, Line, MaskTexture) |
| — | E2052 names the call a field is assigned after, and follows `if`/`else` branches and `do` blocks |

Not changed (noted):

- `t[k]` isn't narrowed by `if t[k] then` (only static field paths); SuuUI
  reads it into a local.
- A module type named like a WoW type shadows it without a warning.
- A native method call on `self` (`self:GetFrameLevel()`) forgets the
  narrowing of `self`'s fields, as any call receiving `self` does; right in
  general, since `self:Show()` runs `OnShow`.
- `(a) -> ()?` reads as an optional function where `(a) -> R?` returns an
  optional `R`; SuuUI writes `((a) -> ())?`.
