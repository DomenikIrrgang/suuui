-- UI/Auras.lua
-- Auras through the engine's aura containers. In combat addon code can't read
-- auras at all ("Auras cannot be accessed when secret"), so SuuUI never does:
-- it declares a container with filter groups, the engine fills it with
-- buttons and drives each one's icon, duration, stacks and dispel colour, and
-- SuuUI only styles the buttons, once, when the engine creates them.
--
--   local c = UI.AuraContainer(parent, "player", {
--       size = "icon-lg",          -- icon size token or px
--       spacing = 4,
--       anchor = "TOPRIGHT",       -- the corner the icons start from
--       growth = { "LEFT", "DOWN" },
--       lineWidth = 520,           -- px before wrapping to the next line (nil: never)
--       groups = {
--           { key = "debuffs", filter = { "HARMFUL", "PLAYER" }, max = 16,
--             dispel = true,       -- the dispel-type border on typed debuffs
--             cancel = false,      -- right click cancels (your own buffs)
--             drain = "ink-muted" },
--       },
--   })
--   c:SetUnit(unit), c:SetGroupMax(key, n)
--
-- Every call into the engine is pcall-guarded: an error inside one aborts the
-- engine's whole button batch, and these APIs were still moving in the beta.
-- Styling happens only in the initializer: once the engine marks a button
-- secret (in combat), addon writes to it are refused.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CROP = 0.08
local EXPIRING = 3 -- seconds: the duration digits turn amber below this

local function loadEngine()
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
end

-- The engine batches parsing by exact filter string: base polarity first,
-- then the other tokens sorted, so equal filters share one scan.
local function filterString(tokens)
    local base, rest = nil, {}
    for _, t in ipairs(tokens) do
        if t == "HELPFUL" or t == "HARMFUL" then base = t else rest[#rest + 1] = t end
    end
    table.sort(rest)
    if base and #rest > 0 then return base .. "|" .. table.concat(rest, "|") end
    return base or table.concat(rest, "|")
end

--------------------------------------------------------------------------------
-- Duration text: the design's time format, evaluated by the engine against
-- the (possibly secret) remaining time. Whole seconds under a minute, m:ss
-- under ten minutes, then minutes, then hours.
--------------------------------------------------------------------------------

local formatter, colorCurve

local function durationFormatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then return nil end
    local Up, Down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
    local f = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(f.SetBreakpoints, f, {
        { threshold = 0, format = "%d", step = 1, rounding = Up },
        { threshold = 60, format = "%d:%02d", step = 1, rounding = Up, components = { { div = 60 }, { mod = 60 } } },
        { threshold = 600, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
    })
    if ok then formatter = f end
    return formatter or nil
end

-- amber below EXPIRING seconds, ink above (a step curve over the remaining time)
local function expiringColor()
    if colorCurve ~= nil then return colorCurve or nil end
    colorCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local c = C_CurveUtil.CreateColorCurve()
    c:SetType(Enum.LuaCurveType.Step)
    c:AddPoint(0, CreateColor(UI.RGBA("amber")))
    c:AddPoint(EXPIRING, CreateColor(UI.RGBA("ink")))
    colorCurve = c
    return c
end

local function durationOptions()
    local opts = { textFormatter = durationFormatter() }
    local curve = expiringColor()
    if curve then
        local prop = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
        if prop == nil then prop = 0 end
        opts.textColor = { curve = curve, property = prop }
    end
    return opts
end

-- Registers the duration text, dropping options step by step if the engine
-- refuses them (never let it throw).
local function setDurationText(button, fs)
    local opts = durationOptions()
    if pcall(button.SetDurationText, button, fs, opts) then return end
    opts.textColor = nil
    if pcall(button.SetDurationText, button, fs, opts) then return end
    pcall(button.SetDurationText, button, fs, {})
end

--------------------------------------------------------------------------------
-- The button: the design's AuraIcon
--------------------------------------------------------------------------------

local DISPEL_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
    and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

local function makeInitializer(group, size)
    return function(button)
        -- Regions first, styled, and only then registered with the button:
        -- each registration makes the engine draw at once, and an unstyled
        -- FontString has no font yet.
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
        local well = button:CreateTexture(nil, "BACKGROUND")
        well:SetAllPoints()
        well:SetColorTexture(UI.RGBA("surface-sunk"))

        local over = CreateFrame("Frame", nil, button)
        over:SetAllPoints()
        over:EnableMouse(false)
        over:SetFrameLevel(button:GetFrameLevel() + 2)
        UI.Border(over, "gilt-hairline")

        -- The dispel border: white edges the engine shows and tints per
        -- debuff type; hidden until it does.
        local edges = {}
        if group.dispel and DISPEL_STYLE ~= nil and (button.AddDispelTypeTexture or button.SetAuraBorder) then
            local holder = CreateFrame("Frame", nil, button)
            holder:SetAllPoints()
            holder:EnableMouse(false)
            holder:SetFrameLevel(button:GetFrameLevel() + 3)
            local b = UI.Border(holder, "ink")
            for _, t in ipairs(b.parts) do
                t:SetColorTexture(1, 1, 1, 1)
                t:Hide()
                edges[#edges + 1] = t
            end
        end

        -- The drain line along the bottom, and the text over everything.
        local drain = CreateFrame("StatusBar", nil, button)
        drain:SetPoint("BOTTOMLEFT", 1, 1)
        drain:SetPoint("BOTTOMRIGHT", -1, 1)
        drain:SetHeight(2)
        drain:SetStatusBarTexture(WHITE)
        drain:SetStatusBarColor(UI.RGBA(group.drain or "ink-muted"))
        drain:SetFrameLevel(button:GetFrameLevel() + 4)

        local text = CreateFrame("Frame", nil, button)
        text:SetAllPoints()
        text:EnableMouse(false)
        text:SetFrameLevel(button:GetFrameLevel() + 5)
        local duration = text:CreateFontString(nil, "OVERLAY")
        ns.Fonts.Apply(duration, "micro")
        duration:SetShadowColor(0, 0, 0, 1)
        duration:SetShadowOffset(0, -1)
        duration:SetPoint("BOTTOM", 0, size <= 16 and 2 or 4)
        local stacks = text:CreateFontString(nil, "OVERLAY")
        ns.Fonts.Apply(stacks, "micro")
        stacks:SetShadowColor(0, 0, 0, 1)
        stacks:SetShadowOffset(0, -1)
        stacks:SetPoint("TOPRIGHT", -2, -1)

        -- Clicks only where they do something (cancelling your own buff):
        -- a click-alive icon would swallow clicks meant for what is under it.
        if group.cancel then
            pcall(button.SetCancelAuraButtons, button, "RightButtonUp")
        else
            pcall(button.SetMouseClickEnabled, button, false)
        end

        pcall(button.SetIcon, button, icon)
        pcall(button.SetApplicationCount, button, stacks, {})
        setDurationText(button, duration)
        if button.SetDurationBar then
            local opts = {}
            if Enum.StatusBarInterpolation then opts.interpolation = Enum.StatusBarInterpolation.Immediate end
            if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
            pcall(button.SetDurationBar, button, drain, opts)
        else
            drain:Hide()
        end
        if #edges > 0 then
            local add = button.AddDispelTypeTexture or button.SetAuraBorder
            local opts = { style = DISPEL_STYLE, showWhenHarmful = true, showWhenHelpful = false }
            for _, t in ipairs(edges) do
                if not pcall(add, button, t, opts) then break end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The container
--------------------------------------------------------------------------------

local AC = {}

local FLOW = AnchorUtil and AnchorUtil.FlowDirection or {}

local function call(container, names, ...)
    for _, name in ipairs(names) do
        local f = container[name]
        if f then return pcall(f, container, ...) end
    end
    return false
end

function AC:SetUnit(unit)
    if unit == self.unit then return end
    self.unit = unit
    pcall(self.container.SetUnit, self.container, unit)
end

function AC:SetGroupMax(key, n)
    pcall(self.container.SetAuraGroupMaxFrameCount, self.container, key, n)
end

function UI.AuraContainer(parent, unit, opts)
    loadEngine()
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok then
        ns.Fault.Report("Auras", "the client has no aura containers: " .. tostring(container))
        return nil
    end
    local self = setmetatable({ container = container, opts = opts }, { __index = AC })
    -- a renderable rect from the start: the engine lays out from an OnUpdate
    container:SetSize(1, 1)

    local size = UI.Size(opts.size or "icon-md")
    call(container, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, opts.anchor or "TOPLEFT")
    local g = opts.growth or { "RIGHT", "DOWN" }
    local h = FLOW[g[1] == "LEFT" and "Left" or "Right"]
    local v = FLOW[g[2] == "UP" and "Up" or "Down"]
    if h and v then call(container, { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" }, h, v) end
    call(container, { "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth" }, opts.lineWidth)

    local spacing = opts.spacing or S["space-2"]
    for _, group in ipairs(opts.groups) do
        local added = pcall(container.AddAuraGroup, container, group.key, filterString(group.filter), {
            maxFrameCount = group.max or 16,
            initializeFrame = makeInitializer(group, size),
            layout = { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing },
        })
        if not added then ns.Fault.Report("Auras", "couldn't add the aura group " .. group.key) end
    end
    self:SetUnit(unit)
    return self
end
