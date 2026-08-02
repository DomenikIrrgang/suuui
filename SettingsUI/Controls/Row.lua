-- Shared row scaffolding for settings controls.
-- Composes containers and components only; no raw WoW UI API.
local C = SuuUI.Components

local M = {}

--- Creates a labelled settings row: label on the left, controls right-aligned.
-- Add trailing controls with row:Add(control, { width=..., height=... }).
-- @param parent frame    Frame the row is created inside
-- @param labelText string
-- @param height number   Row height (default 28)
-- @return table, table   Row container handle, label handle
function M.Labelled(parent, labelText, height)
    local T = SuuUI.Theme
    local pad = T:GetToken("spaceMd") or 8

    local row = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "horizontal",
        gap     = pad,
        align   = "center",
        h       = height or 28,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })

    local label = C.Text({ text = labelText or "", size = "md", color = "text" }, row:GetFrame())
    row:Add(label, { width = "fill" })

    return row, label
end

--- Creates a full-width row that stacks its children vertically.
-- @param parent frame
-- @param height number  Row height
-- @return table  Row container handle
function M.Stacked(parent, height)
    local T = SuuUI.Theme
    local pad = T:GetToken("spaceMd") or 8

    return SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = T:GetToken("spaceSm") or 4,
        h       = height,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })
end

SuuUI._SettingsRow = M
