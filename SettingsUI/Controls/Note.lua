-- A read-only line of prose on a settings page.
--
-- Every other control here edits a value. This one says something -- which the schema had no way to
-- express: `text` is an INPUT, and a section header is a heading rather than a sentence. It exists
-- because some settings need a fact stated next to them that a label cannot carry, and the first such
-- case is a warning that says WHY a bar should be left alone rather than merely that it should.
--
-- No key, no watcher, no data binding. `entry.key` is ignored if present, so a note can sit in a schema
-- array beside real settings without the settings store ever seeing it.
local function Build(entry, pluginId, parent)
    local row = SuuUI._SettingsRow.Stacked(parent)

    local text = SuuUI.Components.Text({
        text = entry.label or "",
        -- Muted by default. A `tone` of "warning" or "danger" resolves to the theme's own token, so a
        -- note that matters looks like every other warning in the UI rather than inventing a colour.
        color = (entry.tone == "warning" and "colorWarning")
            or (entry.tone == "danger" and "colorDanger")
            or "colorTextMuted",
        size = "sm",
        -- Wrapped, because a note is a sentence and the page is narrower than most of them.
        wrap = true,
        w = 300,
    }, row:GetFrame())

    row:Add(text, { width = "fill" })
    return row
end

if not SuuUI._SettingsControls then SuuUI._SettingsControls = {} end
SuuUI._SettingsControls["note"] = Build
