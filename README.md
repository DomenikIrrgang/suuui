# SuuUI

Full World of Warcraft UI replacement for Classic Anniversary (TBC, interface `20504`).

SuuUI is a core addon plus a plugin system: the core ships a theme/token system, a layout
engine, an animation runner and a component library, and every piece of visible UI — first
party or third party — is built on top of it as a plugin. No external libraries; everything
is written from scratch.

**Status: early development.** The framework layers (core, layout, components, settings UI)
are in place and tested. The gameplay plugins have started: unit frames, cast bars, and
buff/debuff bands cover the player and the target, suppressing Blizzard's own, and a
full-width data bar along the top of the screen carries fields any plugin can register a
widget into — a clock is the one built in so far. Everything else is still to come.

## Install

Clone into your addons folder so the directory is named `SuuUI`:

```bash
cd "/path/to/World of Warcraft/_anniversary_/Interface/AddOns"
git clone git@github.com:DomenikIrrgang/suuui.git SuuUI
```

Open the settings window in game with `/suuui`.

## What is in here

| Directory | Contents |
|---|---|
| `Core/` | event bus, UI signals, attach points, data bar registry, profiles, settings registry, theme tokens, font registry, pixel grid, game facts, plugin lifecycle, edit mode (moveable frames, snap grid, properties panel) |
| `Layout/` | window, container, and the four layout strategies (flow, grid, stack, anchor) |
| `Components/` | ~25 components — button, slider, dropdown, colour picker, scroll frame, modal, tooltip, collapsible accordion, data bar field, … |
| `Animation/` | tween easings, animation runner, named presets |
| `SettingsUI/` | settings window that auto-builds a page from a plugin's schema, grouped into collapsible sections |
| `Themes/` | built-in read-only themes |
| `Plugins/` | bundled first-party plugins — unit frames with buff/debuff bands, and cast bars, for the player and the target; the top data bar and its clock |
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
lua Tests/run.lua                 # everything
lua Tests/run.lua --filter Slider # one suite or test name
```

The suite loads the real addon into a sandbox against a simulated client that solves the
actual anchor graph, so specs assert real pixel geometry rather than intent. It currently
runs 2674 assertions with no external dependencies — no busted, no luarocks.

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
