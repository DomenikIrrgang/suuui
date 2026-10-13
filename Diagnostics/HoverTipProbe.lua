-- Diagnostics/HoverTipProbe.lua
-- "/suu probe hovertip": three seconds later (time to hover something),
-- every tooltip-type frame on screen: its name, whether SuuUI skinned it,
-- its NineSlice's alpha and shown state, its scale, parent and owner. Prints
-- in chat and saves to SuuUIProbe.hoverTip.

local _, ns = ...

local HP = {}
ns.HoverTipProbe = HP

local isSecret = issecretvalue or function() return false end
local function show(v) if isSecret(v) then return "secret" end return tostring(v) end

local function describe(f)
    local name = f:GetName() or f:GetDebugName() or "?"
    local ns9 = f.NineSlice
    local owner = "?"
    pcall(function()
        local o = f:GetOwner()
        owner = o and (o:GetName() or o:GetDebugName() or "unnamed") or "nil"
    end)
    local parent = f:GetParent()
    return ("%s (%s) skinned=%s nineSlice=%s alpha=%s scale=%.2f parent=%s owner=%s strata=%s"):format(
        name, f:GetObjectType(), show(ns.UI.IsTooltipSkinned and ns.UI.IsTooltipSkinned(f)),
        ns9 and (ns9:IsShown() and "shown" or "hidden") or "none", ns9 and ("%.2f"):format(ns9:GetAlpha()) or "-",
        f:GetScale(), parent and (parent:GetName() or parent:GetDebugName() or "unnamed") or "nil", owner, show(f:GetFrameStrata()))
end

function HP.Command()
    ns.Print("Hover tooltip probe: hover a buff now; in 3 seconds SuuUI lists the tooltips on screen.")
    C_Timer.After(3, function()
        SuuUIProbe = SuuUIProbe or {}
        local out = { at = date("%H:%M:%S") }
        SuuUIProbe.hoverTip = out
        local f = EnumerateFrames()
        while f do
            local ok, text = pcall(function()
                if f:IsForbidden() then return nil end
                if not f:IsVisible() then return nil end
                local t = f:GetObjectType()
                if t ~= "GameTooltip" and not (f.NineSlice and f:GetFrameStrata() == "TOOLTIP") then return nil end
                return describe(f)
            end)
            if ok and text then
                out[#out + 1] = text
                ns.Print(text)
            end
            f = EnumerateFrames(f)
        end
        if #out == 0 then ns.Print("Hover tooltip probe: no tooltip on screen.") end
    end)
end
