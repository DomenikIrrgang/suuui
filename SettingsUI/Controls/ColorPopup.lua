-- Single shared colour picker popup for every colour control in the settings UI.
-- Anchored declaratively through UIRoot; no cursor maths, no strata juggling here.
local C = SuuUI.Components
local S = SuuUI.UISignals

local M = {}

local picker          = nil
local activeHandler   = nil
local activeSwatch    = nil

local function ensurePicker()
    if picker then return picker end

    local root = SuuUI.UIRoot and SuuUI.UIRoot:GetRoot()
    picker = C.ColorPicker({ value = {1, 1, 1, 1} }, root or UIParent)
    picker:Hide()

    if root then
        SuuUI.UIRoot:AddElement(picker:GetFrame(), "dialog", {
            point = "CENTER", x = 0, y = 0,
        })
    end

    S:Connect(picker, C.COLORPICKER_SIGNALS.COLOR_PICKED, function(r, g, b, a)
        if activeSwatch then activeSwatch:SetValue(r, g, b, a) end
        if activeHandler then activeHandler(r, g, b, a) end
    end)

    S:Connect(picker, C.COLORPICKER_SIGNALS.REQUEST_CLOSE, function()
        M.Close()
    end)

    return picker
end

--- Opens the shared picker anchored beneath a swatch.
-- @param swatch table    ColorSwatch handle the picker hangs from
-- @param value table     Initial colour { r, g, b, a }
-- @param onChange function  Called with (r, g, b, a) on every change
function M.Open(swatch, value, onChange)
    local p = ensurePicker()

    if p:IsShown() and activeSwatch == swatch then
        M.Close()
        return
    end

    activeSwatch  = swatch
    activeHandler = onChange
    p:SetValue(value[1], value[2], value[3], value[4] or 1)

    local gap = SuuUI.Theme:GetToken("spaceXs") or 4
    if SuuUI.UIRoot and SuuUI.UIRoot:GetRoot() then
        SuuUI.UIRoot:UpdateElementAnchor(p:GetFrame(), {
            point         = "TOPRIGHT",
            relativeTo    = swatch:GetFrame(),
            relativePoint = "BOTTOMRIGHT",
            x             = 0,
            y             = -gap,
        })
    end

    p:Show()
    SuuUI.Anim.Presets.FadeIn(p:GetFrame(), SuuUI.Theme:GetToken("animFast"))
end

--- Closes the shared picker.
function M.Close()
    if picker and picker:IsShown() then
        picker:Hide()
    end
    activeSwatch  = nil
    activeHandler = nil
end

SuuUI._ColorPopup = M
