-- Shared row scaffolding for settings controls.
-- Composes containers and components only; no raw WoW UI API.
local C = SuuUI.Components

local M = {}

--- Creates a labelled settings row: label on the left, controls right-aligned.
-- The row hugs its content so it re-flows when font size tokens change.
-- Add trailing controls with row:Add(control, { width=..., height=... }).
-- @param parent frame    Frame the row is created inside
-- @param labelText string
-- @return table, table   Row container handle, label handle
function M.Labelled(parent, labelText)
    local T = SuuUI.Theme
    local pad = T:GetToken("spaceSm") or 8
    local vpad = T:GetToken("spaceXs") or 4

    local row = SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "horizontal",
        gap     = pad,
        align   = "center",
        padding = { top = vpad, right = pad, bottom = vpad, left = pad },
    })

    local label = C.Text({ text = labelText or "", size = "md", color = "text" }, row:GetFrame())
    row:Add(label, { width = "fill" })

    return row, label
end

--- Creates a full-width row that stacks its children vertically and hugs them.
-- @param parent frame
-- @return table  Row container handle
function M.Stacked(parent)
    local T = SuuUI.Theme
    local pad = T:GetToken("spaceSm") or 8

    return SuuUI.Layout:CreateContainer({
        parent  = parent,
        layout  = "flow",
        dir     = "vertical",
        gap     = T:GetToken("spaceXs") or 4,
        padding = { top = 0, right = pad, bottom = 0, left = pad },
    })
end

SuuUI._SettingsRow = M
