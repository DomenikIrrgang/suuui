-- Diagnostics/FlickerProbe.lua
-- "/suu probe flicker [frame]": what happens to a window while it opens
-- (default PlayerSpellsFrame). From now until /reload: every SetPoint,
-- ClearAllPoints, SetSize/Width/Height, SetScale, SetAlpha, Show and Hide on
-- it with the frame number and who called (the stack's first lines), and
-- for the first 15 frames after each show its left, bottom, size, scale and
-- alpha. Saved in SuuUIProbe.flicker.

local _, ns = ...

local FP = {}
ns.FlickerProbe = FP

local frameNo = 0
local counter = CreateFrame("Frame")
counter:SetScript("OnUpdate", function() frameNo = frameNo + 1 end)

local function fmt(v)
    if type(v) == "number" then return ("%.1f"):format(v) end
    if type(v) == "table" and v.GetName then return v:GetName() or "frame" end
    return tostring(v)
end

local function caller()
    local stack = debugstack(3, 3, 0) or ""
    local lines = {}
    for line in stack:gmatch("[^\n]+") do
        lines[#lines + 1] = line:gsub("^.*AddOns/", ""):gsub("^%[string \"(.-)\"%]", "%1"):sub(1, 90)
        if #lines >= 2 then break end
    end
    return table.concat(lines, " < ")
end

local hooked = {}

function FP.Command(arg)
    local name = (arg and arg ~= "") and arg or "PlayerSpellsFrame"
    local f = _G[name]
    if not f then ns.Print("Flicker probe: no frame " .. name .. " (open it once first).") return end
    SuuUIProbe = SuuUIProbe or {}
    local log = {}
    SuuUIProbe.flicker = { frame = name, at = date("%H:%M:%S"), log = log }
    local function note(s)
        if #log < 600 then log[#log + 1] = ("#%d %s"):format(frameNo, s) end
    end
    if not hooked[f] then
        hooked[f] = true
        for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight", "SetScale", "SetAlpha", "Show", "Hide" }) do
            if f[m] then
                hooksecurefunc(f, m, function(_, a, b, c, d, e)
                    note(("%s(%s, %s, %s, %s, %s) by %s"):format(m, fmt(a), fmt(b), fmt(c), fmt(d), fmt(e), caller()))
                end)
            end
        end
        local sampling = 0
        local sampler = CreateFrame("Frame")
        sampler:SetScript("OnUpdate", function()
            if sampling <= 0 then return end
            sampling = sampling - 1
            note(("sample left=%s bottom=%s w=%s h=%s scale=%s alpha=%s shown=%s"):format(fmt(f:GetLeft()), fmt(f:GetBottom()),
                fmt(f:GetWidth()), fmt(f:GetHeight()), fmt(f:GetEffectiveScale()), fmt(f:GetEffectiveAlpha()), tostring(f:IsVisible())))
        end)
        f:HookScript("OnShow", function()
            note("OnShow")
            sampling = 15
        end)
        f:HookScript("OnHide", function() note("OnHide") end)
    end
    ns.Print("Flicker probe: watching " .. name .. ". Open and close it a couple of times, then /reload.")
end
