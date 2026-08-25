# SuuUI

Full World of Warcraft UI replacement for Classic Anniversary (TBC, interface `20504`).

SuuUI is a core addon plus a plugin system: the core ships a theme/token system, a layout
engine, an animation runner and a component library, and every piece of visible UI — first
party or third party — is built on top of it as a plugin. Everything visible is written from
scratch, with one deliberate exception: `Libs/` embeds LibStub, CallbackHandler-1.0,
LibDataBroker-1.1 and LibDBIcon-1.0 so the minimap button is discoverable by the button
collectors and broker displays players already run — ElvUI's button bar, MBB, SexyMap, Titan
Panel, Bazooka, ChocolateBar. That interop is the entire reason: a hand-rolled corner icon
cannot be dragged around the ring, hidden, or collected by any of them. The boundary is
narrow — no core, layout, component or settings-UI file needs those libraries, one bundled
plugin uses them, and LibStub version-arbitrates, so a newer copy already on the player's
machine wins and ours registers nothing.

**Status: early development, but the bottom of the screen is now SuuUI's.** The framework layers
(core, layout, components, settings UI) are in place and tested. On top of them:

- **Action bars.** Thirteen action bars plus a pet bar and a stance bar, all built on SuuUI's own
  secure buttons — Blizzard's action *system* stays the data source, its bars are hidden. Bar 1
  follows forms and stances, and **bars 9–13 reach the sixty action slots no Blizzard bar exposes**
  (slots 13–24 and 73–120), which is where a lot of players' abilities actually live.
- **Unit frames and cast bars** with buff/debuff bands, for the player and the target.
- **A full-width data bar** along the top, carrying a clock, framerate and latency readouts, an
  addon-button tray, the **micro menu** as one field per entry, and a **bag field** reading free
  slots.
- **Experience and reputation bars**, with readout slots, a rested "ghost" fill on the XP bar, and
  the client's own standing colours on the reputation bar.
- **Bar-to-bar docking.** Any bar can attach to any other on any of four edges, chains work, and
  the dropdown spans plugins — an experience bar can dock to an action bar.
- **Bags.** One flat searchable, sortable grid of every bag slot in place of Blizzard's five frames,
  a second live window at a banker with items moving both ways, a sell-greys button, and an
  **account-wide cache**: a dropdown browses any character's bags read-only, and every item tooltip
  in the game gains a line per other character holding it.

Those built-ins ship inside their plugins; the registries they go through are the same ones a
third-party plugin uses, so a widget from an addon that loads minutes later is picked up exactly
like one of ours.

Still to come: chat, minimap, nameplates, loot, and the rest of the gameplay surface. Tooltips are
reskinned already; what is missing there is a tooltip of SuuUI's own rather than the client's.

> **Blizzard's action bars are hidden by default.** If you want them back without turning SuuUI
> off, the switch is the first thing on the Action Bars settings page — "Hide Blizzard's Action
> Bars". Your existing keybindings keep working either way: bars 1–8 use Blizzard's own binding
> families, which act on the action *slot* rather than on the button.

## Install

Clone into your addons folder so the directory is named `SuuUI`:

```bash
cd "/path/to/World of Warcraft/_anniversary_/Interface/AddOns"
git clone git@github.com:DomenikIrrgang/suuui.git SuuUI
```

Open the settings window in game with `/suuui`, or with a left click on the minimap button;
right-clicking that button enters edit mode.

## Keybindings

Bars 1–8, the pet bar and the stance bar use **Blizzard's own binding families**, so whatever you
have bound already keeps working with Blizzard's bars hidden — those bindings act on the action
slot, not on the button that draws it.

Bars 9–13 cover slots Blizzard exposes no bar for, so there are no Blizzard bindings to inherit.
SuuUI declares sixty of its own, listed in the standard **Key Bindings** window under
**SuuUI Action Bars**, one section per bar. Bind them there as usual; the key is routed to the
matching button.

## What is in here

| Directory | Contents |
|---|---|
| `Libs/` | the only external code — LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0, embedded for minimap-button interop and loaded first |
| `Core/` | event bus, UI signals, attach points, the bar dock, data bar registry, profiles, settings registry, theme tokens, font registry, pixel grid, game facts, the account-wide item cache, plugin lifecycle, edit mode (moveable frames, snap grid, properties panel) |
| `Layout/` | window, container, and the four layout strategies (flow, grid, stack, anchor) |
| `Components/` | ~30 components — button, slider, dropdown, colour picker, scroll frame, modal, tooltip, collapsible accordion, data bar field, status bar, secure action button, action bar grid, stance button, flyout panel, … |
| `Animation/` | tween easings, animation runner, named presets |
| `SettingsUI/` | settings window that auto-builds a page from a plugin's schema, grouped into collapsible sections |
| `Themes/` | built-in read-only themes |
| `Plugins/` | bundled first-party plugins — action bars (thirteen bars plus pet and stance, with Blizzard's cluster suppressed); unit frames with buff/debuff bands, and cast bars, for the player and the target; the experience and reputation watch bars; the top data bar with its clock, framerate and latency readouts, micro menu, bag field and addon-button tray; the minimap button, a LibDataBroker launcher wearing LibDBIcon's stock ring art so other addons' collectors recognise it; the bag windows, their sell-greys loop and the account snapshot browser |
| `Media/` | the icon atlas and its generator |
| `Bindings.xml` | the sixty keybinding names SuuUI declares for the action slots Blizzard exposes no bar for |
| `Tests/` | test suite and a simulated WoW client (not shipped — absent from the `.toc`) |

## Development

Three rules shape the whole codebase, and the test suite enforces them:

- **Nothing positions itself.** `SetPoint` exists only inside the four layout strategies.
  Everything else is placed by a container.
- **Raw WoW UI API is confined to `Components/`, `Layout/` and `Core/UIRoot.lua`.** Plugin
  and page code composes components and containers.
- **UI talks to UI through signals**, not through Blizzard frame scripts.

Run the suite from the addon root:

```bash
lua Tests/run.lua                 # everything, sequentially
./Tests/parallel.sh               # the same suite across cores, much faster
lua Tests/run.lua --filter Slider # one suite or test name
```

The suite loads the real addon into a sandbox against a simulated client that solves the
actual anchor graph, so specs assert real pixel geometry rather than intent. It currently
runs 4803 specs across 72 files — all passing, eight skipped — with no test dependencies at all:
no busted, no luarocks. The embedded libraries in `Libs/` are shipped runtime code, not test
tooling; the suite loads them the same way the client does.

Where the simulated client cannot reach — a combat lockdown refusing a secure call, a macro
conditional the client alone resolves — the suite asserts the *structure* and the behaviour is
verified in game. `TESTING.md` lists those gaps explicitly rather than leaving them implied, and
non-trivial changes are additionally **mutation-checked**: broken on purpose to confirm a spec
actually fails.

Full contracts live in `.kiro/steering/`: `architecture.md` for the subsystem reference,
`LAYOUT_SYSTEM.md`, `UI_SIGNALS.md`, `WOW_API_ENCAPSULATION.md`, `coding-standards.md`,
`TESTING.md`, and `plugin-authoring.md` for writing a plugin.

## Writing a plugin

A plugin is any addon that registers with the core. It can live in `Plugins/` or be a
separate addon folder with `## Dependencies: SuuUI` in its `.toc`:

```lua
local plugin = SuuUI:CreatePlugin({
  id      = "my_plugin",
  name    = "My Plugin",
  version = "1.0",
  onInit  = function(p)
    SuuUI.Settings:Register("my_plugin", {
      { key = "enabled", label = "Enable", type = "toggle", default = true },
    })
  end,
  onEnable  = function(p) end,   -- hide/modify Blizzard frames
  onDisable = function(p) end,   -- restore them
})
```

The settings page is generated from that schema — a plugin writes no UI code for standard
settings. See `.kiro/steering/plugin-authoring.md`.

## License

MIT — see [LICENSE](LICENSE).
