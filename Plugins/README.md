# Bundled Plugins

Each sub-folder here is a first-party plugin bundled with SuuUI.
Plugins loaded from this folder must still follow the plugin authoring contract —
they register via `SuuUI:CreatePlugin(...)` just like any external addon.

Add each plugin's entry file to SuuUI.toc under the "Bundled Plugins" section.

## Planned plugins (not yet implemented)

- UnitFrames/   -- player, target, focus, party, raid frames
- ActionBars/   -- action bar replacement
- Minimap/      -- minimap reskin and repositioning
- ChatFrames/   -- chat window replacement
- Nameplates/   -- nameplate replacement
- CastBar/      -- cast bar replacement
- Buffs/        -- buff/debuff frame replacement
