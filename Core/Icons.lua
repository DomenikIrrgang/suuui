-- The shared UI glyph registry: a NAME to a texture path plus its coordinates on the sheet.
--
-- WHY THIS IS IN CORE. The micro menu's sheet is consumed by a coord table inside
-- Plugins/DataBar, which is correct for a sheet only that plugin uses. The moment a SECOND
-- plugin wants a glyph, that table becomes something one plugin has to reach into another
-- plugin for -- the one thing plugins may never do. So the general-purpose sheet is published
-- here instead, and every consumer asks Core.
--
-- The answer exists whether or not any plugin is loaded, which is the same argument
-- Core/DataBar.lua and Core/ItemCache.lua are here for.
--
-- COORDINATES ARE A CONTRACT WITH THE GENERATOR. Media/generate_ui_icons.py prints this exact
-- table and its GLYPHS list is append-only, because an insertion in the middle silently
-- re-points every entry after it. Regenerate, then paste -- do not hand-edit a fraction.
local type, pairs = type, pairs

local M = {}

--- The sheet every glyph below lives on.
M.PATH = "Interface\\AddOns\\SuuUI\\Media\\ui-icons"

-- left, right, top, bottom as 0..1 fractions, in the order SetTexCoord takes them.
local GLYPHS = {
    sort    = { 0.00000, 0.25000, 0.00000, 0.25000 },
    account = { 0.25000, 0.50000, 0.00000, 0.25000 },
    coin    = { 0.50000, 0.75000, 0.00000, 0.25000 },
    search  = { 0.75000, 1.00000, 0.00000, 0.25000 },
    chevron = { 0.00000, 0.25000, 0.25000, 0.50000 },
    keybind = { 0.25000, 0.50000, 0.25000, 0.50000 },
    copy    = { 0.50000, 0.75000, 0.25000, 0.50000 },
}

--- The sheet's pixel size. Needed because an INLINE texture escape takes sheet PIXELS where
--- SetTexCoord takes 0..1 fractions, so a consumer embedding a glyph in text has to convert.
M.SHEET = 128

--- Whether a glyph name is on the sheet.
-- @param name string
-- @return bool
function M:Has(name)
    return type(name) == "string" and GLYPHS[name] ~= nil
end

--- A glyph's texture path and coordinates.
--
-- Returns the path and a COPY of the coords, not the stored table: a caller that mutated the
-- internal one would silently re-point the glyph for every other consumer, and nothing would
-- say so. Same reason Container:GetPadding and DataBar:List hand out copies.
--
-- nil for an unknown name rather than a stand-in, so a typo shows as a missing icon at the call
-- site instead of as the wrong glyph -- which is much harder to notice.
-- @param name string
-- @return string|nil path, table|nil coords  { left, right, top, bottom }
function M:Get(name)
    local c = type(name) == "string" and GLYPHS[name] or nil
    if not c then return nil, nil end
    return M.PATH, { c[1], c[2], c[3], c[4] }
end

--- A glyph as an INLINE TEXTURE escape, for embedding in a string the client renders.
---
--- The one way to put an icon inside a chat line: a ScrollingMessageFrame renders text and gives no
--- per-line frame to parent anything to, so an icon there has to BE part of the string. Wrap the
--- result in a hyperlink and it becomes clickable, which is how a per-line affordance is possible at
--- all.
---
--- Coordinates are converted to sheet PIXELS, because `|T…|t` takes pixels where `SetTexCoord` takes
--- fractions -- handing it fractions draws the sheet's top-left pixel stretched over the whole glyph,
--- which looks like a solid block rather than an icon.
-- @param name string
-- @param size number|nil  edge in text units; defaults to 14
-- @return string|nil  nil for an unknown glyph, so a typo shows as absent rather than as a block
function M:Escape(name, size)
    local path, c = M:Get(name)
    if not path then return nil end
    local s = tonumber(size) or 14
    local sheet = M.SHEET
    return "|T" .. path .. ":" .. s .. ":" .. s .. ":0:0:" .. sheet .. ":" .. sheet
        .. ":" .. (c[1] * sheet) .. ":" .. (c[2] * sheet)
        .. ":" .. (c[3] * sheet) .. ":" .. (c[4] * sheet) .. "|t"
end

--- Every glyph name on the sheet, unordered.
-- @return table
function M:List()
    local out = {}
    for name in pairs(GLYPHS) do out[#out + 1] = name end
    return out
end

SuuUI.Icons = M
