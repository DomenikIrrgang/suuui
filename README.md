<p align="center">
  <img src="Docs/assets/suuui-banner.svg" alt="SuuUI — quiet until it matters" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/WoW%20Forever-interface%2016001-C9A75A?style=for-the-badge&labelColor=131116" alt="WoW Forever, interface 16001">
  <img src="https://img.shields.io/badge/version-0.1.5-3FD0FF?style=for-the-badge&labelColor=131116" alt="Version 0.1.5">
  <img src="https://img.shields.io/badge/status-in%20development-E6CC8A?style=for-the-badge&labelColor=131116" alt="Status: in development">
  <img src="https://img.shields.io/badge/Lua-5.1-F1EADB?style=for-the-badge&logo=lua&logoColor=F1EADB&labelColor=131116" alt="Lua 5.1">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-C9A75A?style=for-the-badge&labelColor=131116" alt="License: MIT"></a>
</p>

<p align="center">
  <b>A full interface replacement for World of Warcraft Forever.</b><br>
  One design system, every frame rebuilt from scratch, and nothing on screen that doesn't earn its place.
</p>

<p align="center">
  <a href="#-features">Features</a> ·
  <a href="#-installation">Installation</a> ·
  <a href="#-getting-started">Getting started</a> ·
  <a href="#-roadmap">Roadmap</a> ·
  <a href="#-for-developers">For developers</a>
</p>

---

## ✦ What is SuuUI?

SuuUI replaces the default interface of **WoW Forever** — the classic-era game running on the modern engine — with a single, consistent UI. Unit frames, group frames, nameplates, action bars, cooldowns, casts and auras all share one visual language: dark glass surfaces, gilt hairlines, ivory text, and **arcane blue reserved for what is ready or actionable right now**.

Its guiding idea is in the tagline: **quiet until it matters**. Frames stay calm and legible; colour, glow and motion appear only when something needs your attention — a cooldown coming ready, a dispellable debuff on your tank, a cast you can interrupt.

It is built for the realities of the modern client: values the game hides from addons in combat (*secret values*) are never read, only handed to the engine to draw. That keeps SuuUI working in combat, in dungeons and in raids, where many older approaches break.

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>◆ One design system</h3>
      Every colour, size, font and motion comes from shared design tokens. Nothing is styled ad hoc, so every part of the UI reads the same way.
    </td>
    <td width="33%" valign="top">
      <h3>◆ Modular</h3>
      Every feature is a module you can switch off, and Blizzard's own frame comes back. Plugins use the very same public API as the built-in modules.
    </td>
    <td width="33%" valign="top">
      <h3>◆ Combat-safe</h3>
      Designed around secret values and protected frames from day one: no taint, no errors in combat, nothing that breaks when you pull.
    </td>
  </tr>
</table>

---

## ✦ Features

### Frames
| | |
|---|---|
| **Unit frames** | Player, target, target of target, focus, pet and boss frames. Health text as percent, value, both or none; a gradual low-health tint; incoming heals and absorbs; debuff-type borders and badges; raid target markers; offline state; adjustable size. |
| **Party & raid frames** | Secure group frames for 5, 10, 20 and 40 players, with real-size previews right in the settings. Debuffs you can remove shown by type even in combat, aggro, range fading, class-coloured names and sorting by role. |
| **Buff indicators** | Healer indicators per class and spec: icons, squares, borders or fills in any corner, shown while up or while missing, scoped to your own group or the whole raid, per raid size. |
| **Nameplates** | Enemy plates with your debuffs, threat badges (solo and in groups), casts with spell icon, target and interrupt state, quest objective marks and raid markers. Styled friendly plates in the open world. |
| **Cast & swing bars** | Your cast bar with its target, target / focus / boss casts that show whether you can interrupt them, and a swing timer that follows your cast bar. |
| **Auras** | Your buffs and debuffs, and your auras on other frames, drawn by the engine so they stay correct in combat. |

### Combat
| | |
|---|---|
| **Action bars** | A dock for bars 1–4 plus bars 5–8, stance and pet bars, visibility rules (always, in combat, on mouseover), and a keybind mode: hover a button, press a key. |
| **Cooldown Manager** | SuuUI's own cooldown and aura tracker with ready-made presets for **every class and spec**. Shared slots (one icon for several spells, or the best spell you know), collections, reminders for missing buffs, effects shown on cooldown icons, sounds — and **conditions** on anything: group or raid, classes in your group, role, stance or form, combat, instance, target type and talents. |

### Everyday
| | |
|---|---|
| **Settings window** | Searchable, every change live, previews at real size, plain-language descriptions. |
| **Edit mode** | Move every SuuUI frame on a snap grid; reset one frame or all of them. |
| **Profiles** | Any number of profiles, switched automatically by your role, with import and export. |
| **Micro menu & bags** | Blizzard's micro menu and bag bar, placed in edit mode, with visibility and scale settings (SuuUI's own are on the roadmap). |

---

## ✦ Installation

> **Requirements:** the WoW Forever client (interface `16001`).

1. Download or clone this repository into your AddOns folder. The folder **must be named `SuuUI`**:
   ```sh
   cd "<World of Warcraft>/_classic_beta_/Interface/AddOns"
   git clone git@github.com:DomenikIrrgang/suuui.git SuuUI
   ```
2. Start the game (or type `/reload`) and make sure **SuuUI** is enabled in the AddOns list.
3. Type **`/suu`** to open the settings.

To update, pull the latest changes and `/reload`:
```sh
cd "<World of Warcraft>/_classic_beta_/Interface/AddOns/SuuUI" && git pull
```

---

## ✦ Getting started

| Command | What it does |
|---|---|
| `/suu` | Open or close the settings window |
| `/suu edit` | Edit mode: move SuuUI's frames on a snap grid |
| `/suu keybind` | Keybind mode: hover an action button and press a key |
| `/suu modules` | List every module (built in and from plugins) with its state |
| `/suu enable <id>` · `/suu disable <id>` | Turn a module on or off |
| `/suu profile` | Show profiles · `use`, `new`, `delete <name>` |
| `/suu get` · `/suu set` · `/suu reset` | Read, change or reset any setting from chat |
| `/suu errors` | List the errors SuuUI caught this session |
| `/suu version` | Show the SuuUI and client versions |
| `/suu help` | Every command |

**First steps:** open `/suu`, pick your preferences under **General → Appearance**, place your frames with **Edit layout**, and load your spec's preset in **Frames → Cooldown Manager**. Under **General → Profiles** you can set a profile per role (tank, healer, damage) — SuuUI switches when your role changes.

---

## ✦ Roadmap

SuuUI is built in small increments, each one confirmed in game before the next begins. The full plan lives in [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

| Phase | Content | State |
|---|---|---|
| **0 · Foundation** | Tokens and fonts, core services, module system and plugin API, primitives, settings window, edit mode | ✅ Done |
| **1 · Combat HUD** | Unit frames, cast bars and swing timer, auras, action bars, Cooldown Manager, party and raid frames, nameplates | ✅ Done |
| | Alerts, threat meter and pull warning · damage meter · encounter timeline and readiness | 🔷 Next |
| **2 · World & everyday play** | Minimap, chat, objective tracker, notifications, bags and bank, loot, tooltips | ◇ Planned |
| **3 · Blizzard windows** | Character, spellbook and talents, professions, social, guild and group finder, world map | ◇ Planned |
| **4 · Depth & release** | Density and accessibility presets, performance and taint pass, plugin developer kit, release | ◇ Planned |

---

## ✦ For developers

SuuUI is meant to be extended. Every built-in module is written against the same public API a plugin uses, so a plugin can do anything the core modules do.

- **Plugin API:** [`Docs/API.md`](Docs/API.md) — modules, settings and migrations, the settings window, edit mode, events, components (unit frames, cast bars, aura containers, …) and design tokens.
- **Example plugin:** [`Examples/SuuUI_HelloPlugin`](Examples/SuuUI_HelloPlugin) — a minimal module with its own settings section.
- **Diagnostics:** `/suu probe` checks which client APIs SuuUI relies on; further probes collect spell, talent, nameplate and group data from the live client.

<details>
<summary><b>Project layout</b></summary>

```
SuuUI/
├── Core/          tokens, fonts, events, settings & profiles, modules, roles, public API
├── UI/            components: unit frame, cast bar, action button, aura container, cooldown tracker, inputs, panels
├── SettingsUI/    the settings window and its sections
├── EditMode/      moving frames on a snap grid
├── Units/         the built-in modules (unit, party and raid frames, nameplates, action bars, Cooldown Manager, …)
├── Data/          generated data: Cooldown Manager presets, talents, the aura catalog
├── Diagnostics/   probes that read the live client
├── Media/         fonts and textures
├── tools/         generators for the presets and data (run with Lua from the addon folder)
├── Docs/          API documentation and README assets
└── Examples/      a sample plugin
```
</details>

<details>
<summary><b>Cooldown Manager presets</b></summary>

The presets are written as spell names in [`tools/presets/<CLASS>.lua`](tools/presets) and turned into spell IDs by `lua tools/gen_presets.lua`, using data read from the client itself (every rank, Forever's own spells, talent descriptions, trainer data and spell art). A name the client doesn't know stops the generator, a spell tracked twice is reported, so nothing unverified reaches the game.
</details>

---

## ✦ License

SuuUI is released under the [MIT License](LICENSE). The bundled typefaces keep their own license, the SIL Open Font License 1.1.

## ✦ Credits

- Typefaces: **[Figtree](https://github.com/erikdkennedy/figtree)** and **[Marcellus SC](https://fonts.google.com/specimen/Marcellus+SC)**, both under the SIL Open Font License (see [`Media/Fonts`](Media/Fonts)).
- Countdown voices: generated for SuuUI with [Piper](https://github.com/rhasspy/piper) from the voices *en_US-ljspeech-high* and *en_US-norman-medium* by Bryce Beattie, trained on public-domain recordings ([LJ Speech](https://keithito.com/LJ-Speech-Dataset/), [LibriVox](https://librivox.org)); see [`Media/Sounds/Countdown`](Media/Sounds/Countdown).
- Made for the **WoW Forever** community.

<p align="center">
  <br>
  <img src="Docs/assets/suuui-mark.svg" alt="" width="40">
  <br>
  <sub>World of Warcraft is a trademark of Blizzard Entertainment, Inc. SuuUI is a fan-made addon and is not affiliated with or endorsed by Blizzard Entertainment.</sub>
</p>
