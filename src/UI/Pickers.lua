-- UI/Pickers.lua
-- Small choice controls from the design system (0.9):
--
--   UI.AnchorPicker(parent, { value = "TOPRIGHT", onChange = fn(point) })
--       the 3×3 grid of diamonds: the chosen point a larger arcane diamond,
--       the rest small ink-muted ones (no offsets: AnchorPicker offsets={false})
--   UI.AnchorButton(parent, { value = "BOTTOM", note, onChange = fn(point) }) (0.17)
--       the nine points in a 30px button; a click opens the grid under it
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
-- AnchorButton (0.17): a 30px button with the nine points in small, the
-- chosen one lit. Its tooltip names the point (opts.tooltip(point) -> data
-- says more); a click opens the AnchorPicker as a popover under it, with
-- opts.note under the grid. A pick, a click outside or :Close() closes it.
--   { value, note, tooltip, onChange = fn(point) }
-- :SetValue(point), :SetDisabled(disabled) (the tooltip still shows: say
-- why), :IsOpen(), :Close(), :PopoverHasMouse().
--------------------------------------------------------------------------------

local MINI = 8 -- between the small points

local AnchorButton = {}
local openButtons = setmetatable({}, { __mode = "k" })

function AnchorButton:SetValue(point)
    self.value = point
    for p, dot in pairs(self.dots) do
        local on = p == point
        dot:SetSize(on and 6 or 4, on and 6 or 4)
        UI.Paint(dot, on and "arcane" or "ink-faint")
    end
    if self.picker then self.picker:SetValue(point) end
    if self:IsVisible() and self:IsMouseOver() then UI.ShowTooltip(self, self:Tooltip()) end
end

function AnchorButton:SetDisabled(disabled)
    setDisabled(self, disabled)
    if self.disabled then self:Close() end
end

function AnchorButton:Tooltip()
    local data = self.tooltip and self.tooltip(self.value) or {}
    data.title = data.title or ("Anchor: " .. (POINT_NAMES[self.value] or self.value or ""))
    return data
end

function AnchorButton:IsOpen()
    return self.pop ~= nil and self.pop:IsShown()
end

function AnchorButton:PopoverHasMouse()
    return self:IsOpen() and self.pop:IsMouseOver()
end

function AnchorButton:Close()
    if self.pop then self.pop:Hide() end
    self.border:SetColor(self:IsMouseOver() and "gilt" or "gilt-line")
end

function AnchorButton:Open()
    if self.disabled then return end
    if not self.pop then
        local pop = UI.Panel(ns.Root, { solid = true, shadow = true })
        pop.body:SetScript("OnSizeChanged", nil)
        pop.body:Hide()
        pop:SetFrameStrata("FULLSCREEN_DIALOG")
        pop:SetToplevel(true)
        pop:SetClampedToScreen(true)
        pop:EnableMouse(true)
        local pad, w = S["space-5"], 196
        self.picker = UI.AnchorPicker(pop, { value = self.value, onChange = function(point)
            self:Close()
            self:SetValue(point)
            if self.onChange then self.onChange(point) end
        end })
        self.picker:SetPoint("TOPLEFT", pad, -pad)
        pop.note = UI.Text(pop, "caption", "ink-muted")
        pop.note:SetWordWrap(true)
        pop.note:SetJustifyH("LEFT")
        pop.note:SetFixedWidth(w - pad * 2)
        pop.note:SetPoint("TOPLEFT", self.picker, "BOTTOMLEFT", 0, -S["space-4"])
        pop:SetWidth(w)
        self.pop = pop
    end
    local pop = self.pop
    pop.note:SetValue(self.note or "")
    pop.note:SetShown(self.note ~= nil)
    pop:SetHeight(S["space-5"] * 2 + self.picker:GetHeight()
        + (self.note and S["space-4"] + pop.note:GetStringHeight() or 0))
    self.picker:SetValue(self.value)
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -S["space-1"])
    pop:Show()
    openButtons[self] = true
    self.border:SetColor("arcane")
end

function UI.AnchorButton(parent, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, AnchorButton)
    b:SetSize(30, 30)
    UI.Fill(b, "surface-raised"):SetAllPoints()
    b.border = UI.Border(b, "gilt-line")
    b.onChange, b.note, b.tooltip = opts.onChange, opts.note, opts.tooltip
    b.dots = {}
    for row, points in ipairs(GRID) do
        for col, point in ipairs(points) do
            local d = UI.Diamond(b, 4, "ink-faint")
            d:SetPoint("CENTER", (col - 2) * MINI, (2 - row) * MINI)
            b.dots[point] = d
        end
    end
    b:SetScript("OnClick", function(self)
        if self:IsOpen() then self:Close() else self:Open() end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.disabled and not self:IsOpen() then self.border:SetColor("gilt") end
        UI.ShowTooltip(self, self:Tooltip())
    end)
    b:SetScript("OnLeave", function(self)
        if not self:IsOpen() then self.border:SetColor("gilt-line") end
        UI.HideTooltip()
    end)
    b:HookScript("OnHide", function(self) self:Close() end)
    b:SetValue(opts.value or "CENTER")
    return b
end

-- A click outside an open popover and its button closes it.
ns.Events.OnGame("GLOBAL_MOUSE_DOWN", function()
    for b in pairs(openButtons) do
        if not b:IsOpen() then
            openButtons[b] = nil
        elseif not (b:IsMouseOver() or b.pop:IsMouseOver()) then
            b:Close()
            openButtons[b] = nil
        end
    end
end, "UI.AnchorButton")

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
