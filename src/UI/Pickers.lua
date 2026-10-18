-- UI/Pickers.lua
-- Small choice controls from the design system (0.9):
--
--   UI.AnchorPicker(parent, { value = "TOPRIGHT", onChange = fn(point) })
--       the 3×3 grid of diamonds: the chosen point a larger arcane diamond,
--       the rest small ink-muted ones (no offsets: AnchorPicker offsets={false})
--   UI.SwatchRow(parent, { options = { { value = "fel", label = "Green" }, … },
--                          value, onChange = fn(token) })
--       token colours only, the chosen one ringed in arcane; the name is the tooltip
--   UI.ToggleChips(parent, { options = { { value, label }, … }, value = { … },
--                            onChange = fn(values) })
--       on/off chips for choices that combine (the value is a list)
--
-- Each has :SetValue(v) and :SetDisabled(disabled) (opacity-disabled, no input).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local function setDisabled(self, disabled)
    self.disabled = disabled and true or false
    self:SetAlpha(self.disabled and T.opacity["opacity-disabled"] or 1)
end

--------------------------------------------------------------------------------
-- AnchorPicker (grid only)
--------------------------------------------------------------------------------

local POINT_NAMES = {
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Centre",
    RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
local GRID = { { "TOPLEFT", "TOP", "TOPRIGHT" }, { "LEFT", "CENTER", "RIGHT" }, { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
local CELL = 20

local AnchorPicker = {}

function AnchorPicker:SetValue(point)
    self.value = point
    for p, cell in pairs(self.cells) do
        local on = p == point
        cell.dot:SetSize(on and 10 or 6, on and 10 or 6)
        UI.Paint(cell.dot, on and "arcane" or "ink-muted")
    end
end
AnchorPicker.SetDisabled = setDisabled

function UI.AnchorPicker(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, AnchorPicker)
    f:SetSize(CELL * 3 + 8, CELL * 3 + 8)
    UI.Fill(f, "surface-sunk"):SetAllPoints()
    UI.Border(f, "gilt-line")
    f.cells, f.onChange = {}, opts.onChange
    for row, points in ipairs(GRID) do
        for col, point in ipairs(points) do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(CELL, CELL)
            b:SetPoint("TOPLEFT", 4 + (col - 1) * CELL, -4 - (row - 1) * CELL)
            b.dot = UI.Diamond(b, 6, "ink-muted")
            b.dot:SetPoint("CENTER")
            b:SetScript("OnClick", function()
                if f.disabled then return end
                f:SetValue(point)
                if f.onChange then f.onChange(point) end
            end)
            b:SetScript("OnEnter", function(self) UI.ShowTooltip(self, { title = POINT_NAMES[point] }) end)
            b:SetScript("OnLeave", function() UI.HideTooltip() end)
            f.cells[point] = b
        end
    end
    f:SetValue(opts.value or "TOPRIGHT")
    return f
end

--------------------------------------------------------------------------------
-- SwatchRow
--------------------------------------------------------------------------------

local SWATCH = 20

local SwatchRow = {}

function SwatchRow:SetValue(token)
    self.value = token
    for _, b in ipairs(self.swatches) do b.ring:SetShown(b.option.value == token) end
end
SwatchRow.SetDisabled = setDisabled

function UI.SwatchRow(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, SwatchRow)
    f.swatches, f.onChange = {}, opts.onChange
    local x = 0
    for _, option in ipairs(opts.options) do
        local b = CreateFrame("Button", nil, f)
        b.option = option
        b:SetSize(SWATCH, SWATCH)
        b:SetPoint("LEFT", x, 0)
        local fill = UI.Fill(b, option.value)
        fill:SetPoint("TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", -3, 3)
        UI.Border(b, "gilt-hairline", { inset = 2 })
        b.ring = CreateFrame("Frame", nil, b)
        b.ring:SetAllPoints()
        UI.Border(b.ring, "arcane", { width = 2 })
        b:SetScript("OnClick", function()
            if f.disabled then return end
            f:SetValue(option.value)
            if f.onChange then f.onChange(option.value) end
        end)
        b:SetScript("OnEnter", function(self) UI.ShowTooltip(self, { title = option.label }) end)
        b:SetScript("OnLeave", function() UI.HideTooltip() end)
        f.swatches[#f.swatches + 1] = b
        x = x + SWATCH + S["space-2"]
    end
    f:SetSize(math.max(1, x - S["space-2"]), SWATCH)
    f:SetValue(opts.value)
    return f
end

--------------------------------------------------------------------------------
-- ToggleChips
--------------------------------------------------------------------------------

local ToggleChips = {}

function ToggleChips:SetValue(values)
    local set = {}
    for _, v in ipairs(values or {}) do set[v] = true end
    self.set = set
    for _, b in ipairs(self.chips) do
        local on = set[b.option.value] and true or false
        b.bg:SetShown(on)
        b.edgeOn:SetShown(on)
        b.label:SetColor(on and "arcane" or "ink-muted")
    end
end

function ToggleChips:GetValue()
    local out = {}
    for _, b in ipairs(self.chips) do
        if self.set[b.option.value] then out[#out + 1] = b.option.value end
    end
    return out
end
ToggleChips.SetDisabled = setDisabled

function UI.ToggleChips(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, ToggleChips)
    f.chips, f.onChange, f.set = {}, opts.onChange, {}
    local x = 0
    for _, option in ipairs(opts.options) do
        local b = CreateFrame("Button", nil, f)
        b.option = option
        UI.Fill(b, "surface-sunk"):SetAllPoints()
        UI.Border(b, "gilt-line")
        b.bg = UI.Fill(b, "arcane-soft", "BACKGROUND", 1)
        b.bg:SetAllPoints()
        b.edgeOn = CreateFrame("Frame", nil, b)
        b.edgeOn:SetAllPoints()
        UI.Border(b.edgeOn, "arcane")
        b.label = UI.Text(b, "label", "ink-muted")
        b.label:SetPoint("CENTER")
        b.label:SetValue(option.label)
        b:SetSize(math.max(40, b.label:GetUnboundedStringWidth() + S["space-5"] * 2), 26)
        b:SetPoint("LEFT", x, 0)
        b:SetScript("OnClick", function()
            if f.disabled then return end
            f.set[option.value] = not f.set[option.value] or nil
            f:SetValue(f:GetValue())
            if f.onChange then f.onChange(f:GetValue()) end
        end)
        f.chips[#f.chips + 1] = b
        x = x + b:GetWidth() + S["space-2"]
    end
    f:SetSize(math.max(1, x - S["space-2"]), 26)
    f:SetValue(opts.value)
    return f
end
