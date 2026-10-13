# SuuUI: working notes for AI sessions

## Building with wowlua

SuuUI is built with [wowlua](https://github.com/DomenikIrrgang/wowlua) (`wowlua --version` ≥ 0.8).

- The addon's Lua and XML files live in `src/`. `wowlua.json` describes the addon (title, notes, saved variables, flavor `camelot` for WoW Forever) and **generates** `SuuUI.toc`; there is no TOC file in the repository. Change TOC fields in `wowlua.json`.
- **Load order** is `build.load-order` in `wowlua.json`. A new file goes into that list at the place it must load (files depend on each other through `ns`).
- `wowlua dev` builds and syncs the addon into `_classic_beta_/Interface/AddOns/SuuUI` on every change; `/reload` in game. `wowlua build --release` builds what gets published (`dist/release/SuuUI`): one bundled, minified `SuuUI.lua`.
- `dist/` is build output; never edit it.
- Release builds bundle every file into one. Code must not depend on its own file name: `debugstack` shows `SuuUI/SuuUI.lua` there (wowlua warns with W6001). `wowlua trace` maps in-game errors from a bundled build back to the source lines.

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
3. Write the changelog: add a section at the top of `CHANGELOG.md`, headed `## <version> (<YYYY-MM-DD>)` with the exact version. Write it for players, in plain language: group the entries under **New**, **Changed** and **Fixed** (leave out empty groups), one line per change a player or plugin author notices. Leave out internal refactors, probes and plan updates. `wowlua publish` uploads exactly this section.
4. Check it: `wowlua publish --dry-run` packages the release and shows what each site would receive, without uploading.
5. Commit (`Release <version>`), create the tag (`git tag -a v<version> -m "SuuUI <version>"`), and push both (`git push && git push origin v<version>`). Then watch the CI run until the upload succeeds.

The tag must match `package.version` (with or without the leading `v`), or `wowlua publish` stops (E4319).
