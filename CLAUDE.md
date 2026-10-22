# SuuUI: working notes for AI sessions

## Building with wowlua

SuuUI is built with [wowlua](https://github.com/DomenikIrrgang/wowlua) (`wowlua --version` ≥ 0.9.0).

- The addon's sources live in `src/`, written in **wowlua** (`.wowlua` files, strict mode for every file: `check.mode` in `wowlua.json`). Every file is a module: it imports what it uses (`import * as events from "/Core/Events"`, stdlib modules as `"wowlua:timer"` …) and exports what it defines (camelCase functions; types and classes PascalCase). There is no `local _, ns = ...` namespace any more. `Docs/wowlua-port-conventions.md` has the rules, Core's exports and the strict-mode patterns.
- `wowlua.json` describes the addon (title, notes, saved variables, flavor `camelot` for WoW Forever) and **generates** `SuuUI.toc`; there is no TOC file in the repository. Change TOC fields in `wowlua.json`. The repository is a workspace: the root package is SuuUI, `libs/ForeverLFG` is the group finder library (a wowlua library package SuuUI depends on), and `Examples/*` are example plugins.
- **Load order** follows the imports (and wowlua's usage analysis); `wowlua toc` shows the order it chose. Imports used only inside functions may form cycles; a cycle with a use while a file loads is an error.
- **Use the standard library** where it does the same thing (wowlua:events, timer, hooks, combat, saved, serialize, secret, table…). SuuUI keeps its own layer where a stdlib module would change behaviour (owners on the event bus, errors reported per module, keyed combat work, profiles); `Docs/wowlua-port-notes.md` lists those gaps.
- `wowlua check` checks the sources without building. `wowlua test` runs `tests/` in wowlua's emulated client with Blizzard's UI (`test.blizzard-ui`): `tests/unit` has a test file for every source file, at the same path (`src/Units/Threat.wowlua` → `tests/unit/Units/Threat.test.wowlua`); `tests/smoke` loads SuuUI, runs every `/suu` command, turns every module off and on and opens the windows; `tests/compat` loads old saved settings. `wowlua test <part of a path>` runs the files that match; `--coverage` prints the lines a file's tests never ran. The emulator is not the game: where it seems to differ, note it in `Docs/wowlua-port-notes.md`. `wowlua install --release` builds once and installs into `_classic_beta_/Interface/AddOns/SuuUI` (use it after every change; then `/reload` in game). `wowlua dev` builds and syncs on every change, with wowlua's in-game profiling tools. `wowlua build --release` builds what gets published (`dist/release/SuuUI`): one bundled, minified `SuuUI.lua`.
- The game's `Interface/AddOns/SuuUI` folder is build output too: never edit it; edit `src/`.
- `dist/` is build output; never edit it.
- Release builds bundle every file into one. Code must not depend on its own file name: `debugstack` shows `SuuUI/SuuUI.lua` there (wowlua warns with W6001). `wowlua trace` maps in-game errors from a bundled build back to the source lines.
- Generated files (`src/Core/Tokens.wowlua`, `src/Data/*`) come from the scripts in `tools/`; change the generator and regenerate, never the output.

## Working on SuuUI

- **Modules and the public API.** Every feature is a module (`SuuUI.RegisterModule`) that can be turned off. Modules (`src/Units`) use only the public API: `import SuuUI from "/Core/API"`, then `SuuUI.*` and `SuuUI.UI.*`, exported in `src/Core/API.wowlua`. A UI function that a module calls but that isn't exported there is nil in game ("attempt to call a nil value"). Document each new export in `Docs/API.md` under the API version it arrives in; additions since the last release go into the version in `src/Core/Modules.lua` (`API_VERSION`).
- **Tests:** a change comes with its test, in the source file's test file (strict, like the sources). Check it with `wowlua check` and `wowlua test`, then in game. Tests end with `expectNoErrors()` (`tests/helpers.wowlua`: the game's errors and what SuuUI's Fault caught); a module's internals are reached with `import internal`. Use the emulated game's own state (`mock.spawnUnit`, `mock.group`, `mob:setThreat`, `mock.setPet`, profiles in `tests/profiles`) before stubbing: a stubbed or faked global runs Blizzard's code that calls it tainted, and `mock.setField` (not an assignment) changes a Blizzard field. Placeholder names only (the identity scan, `tools/idscan.py`, runs before every commit). What testing found per area is in `Docs/test-notes/`, and wowlua's side of it in `Docs/wowlua-test-findings.md`.
- **Probes first.** WoW Forever blocks some things that other clients allow (secret values, restricted functions). `/suu probe <topic>` (`src/Diagnostics`) records what the client allows into `SuuUIProbe` in the SavedVariables (written on `/reload`). Probe before designing anything the game may block. For taint, use `/suu probe taint`, never `/console taintLog` (on Forever it breaks Blizzard frames and writes nothing).
- **Blizzard's own UI code for Forever** is mirrored at [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), branch `forever`. Its `Blizzard_APIDocumentationGenerated` marks restricted functions (`HasRestrictions`).
- **Design docs:** `IMPLEMENTATION_PLAN.md` (the build plan, with what was probed and confirmed per step) and `Docs/ForeverLFG.md` (the group finder library).

## Builds per site

- **CurseForge** (and Wago or WoWInterface, when added) must get **readable** code: the `readable` profile, bundled but never minified and without optimizations. Addon sites do not accept minified code; never give their targets a minifying level.
- **GitHub Releases** carry SuuUI's own builds for the website: the `release` profile, always fully optimized (`max`, every optimization on).

## Versions

SuuUI follows [semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **MAJOR**: changes players or plugin authors must act on: the public API (`Docs/API.md`) changes incompatibly, or saved settings are reset or dropped without a migration.
- **MINOR**: new features, modules or settings, backwards compatible.
- **PATCH**: fixes only.
- **Pre-releases** add `-alpha.N` or `-beta.N` (`0.2.0-beta.1`). They publish as alpha or beta files; a version without a suffix publishes as a release.

While SuuUI is below 1.0, breaking changes bump MINOR instead of MAJOR.

## Releasing

A tag `v<version>` on `main` publishes that version: CI (`.github/workflows/ci.yml`) builds it and runs `wowlua publish`, which uploads to CurseForge with the changelog section of that version.

Before setting a tag:

1. Find the previous release tag (`git describe --tags --abbrev=0`) and read every change since it (`git log <tag>..HEAD`, plus the diffs where a subject is unclear).
2. Choose the next version by the rules above, and set it as `package.version` in `wowlua.json`.
3. Write the changelog: add a section at the top of `CHANGELOG.md`, headed `## <version> (<YYYY-MM-DD>)` with the exact version. If an `## Unreleased` section is there (kept up to date between releases), it becomes this section: rename it and check it against the log. Write it for players, in plain language: group the entries under **New**, **Changed** and **Fixed** (leave out empty groups), one line per change a player or plugin author notices. Leave out internal refactors, probes and plan updates. `wowlua publish` uploads exactly this section.
4. Check it: `wowlua publish --dry-run` packages the release and shows what each site would receive, without uploading.
5. Commit (`Release <version>`), create the tag (`git tag -a v<version> -m "SuuUI <version>"`), and push both (`git push && git push origin v<version>`). Then watch the CI run until the upload succeeds.

The tag must match `package.version` (with or without the leading `v`), or `wowlua publish` stops (E4319).
