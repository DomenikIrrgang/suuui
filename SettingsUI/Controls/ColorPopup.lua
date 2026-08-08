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

    -- The picker is a session singleton, so one built before UIRoot exists would be cached
    -- forever against the wrong parent AND outside the layer system — no strata, no anchor,
    -- positioned by nothing. There is no version of that worth keeping, so the invariant is
    -- stated instead of worked around. Unreachable in practice: the root is created at
    -- CORE_READY, long before a colour swatch can be clicked. AddElement below asserts on
    -- the same condition anyway; this only makes the reason legible.
    local root = SuuUI.UIRoot and SuuUI.UIRoot.GetRoot and SuuUI.UIRoot:GetRoot()
    assert(root, "SuuUI ColorPopup: UIRoot:Init() must run before the colour picker is opened")

    picker = C.ColorPicker({ value = {1, 1, 1, 1} }, root)
    picker:Hide()

    SuuUI.UIRoot:AddElement(picker:GetFrame(), "dialog", {
        point = "CENTER", x = 0, y = 0,
    })

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
    -- Unconditional: ensurePicker has already established that the root exists, so there is
    -- no second path here where the picker gets shown without being anchored.
    SuuUI.UIRoot:UpdateElementAnchor(p:GetFrame(), {
        point         = "TOPRIGHT",
        relativeTo    = swatch:GetFrame(),
        relativePoint = "BOTTOMRIGHT",
        x             = 0,
        y             = -gap,
    })

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

--- Closes the picker if it is currently attached to this swatch.
--
-- The picker is a singleton that outlives the controls it serves, and it is anchored to
-- the swatch that opened it while holding that swatch's handle and onChange closure. When
-- a settings page is torn down mid-edit — the player navigates away with the picker still
-- open — those become references to destroyed widgets that the next colour pick would
-- write into. A control calls this from its own teardown so the popup lets go first.
-- @param swatch table  The swatch being destroyed
function M.CloseFor(swatch)
    if swatch and activeSwatch == swatch then
        M.Close()
    end
end

--- Returns the swatch the picker is currently open for, or nil.
-- @return table|nil
function M.GetActiveSwatch()
    return activeSwatch
end

SuuUI._ColorPopup = M
