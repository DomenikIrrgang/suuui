-- Diagnostics/CastTargetProbe.lua
-- "/suu probe casttarget" (asked 2026-10-18: cast bars should name a spell's
-- target in its class colour and show the You badge when it's you; neither
-- showed). The next casts of your target (up to five) record what the
-- client gives: UnitSpellTargetName and UnitSpellTargetClass (secret or
-- not), PlayerIsSpellTarget, and whether a class colour from a secret class
-- reaches a text (GetClassColor, GetRGB into SetTextColor; a colour code by
-- GenerateHexColor), and whether SetAlphaFromBoolean takes the "is it you"
-- answer. Saved in SuuUIProbe.castTarget on /reload.

local _, ns = ...

local CT = {}
ns.CastTargetProbe = CT

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

local function try(fn, ...)
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 100) end
    local out = {}
    for i = 2, math.max(2, #res) do out[#out + 1] = show(res[i]) end
    return table.concat(out, ", ")
end

local function record(unit, out)
    local r = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false, unit = unit }
    local okN, name = pcall(UnitSpellTargetName, unit)
    local okC, class = pcall(UnitSpellTargetClass, unit)
    r.shouldDisplay = try(UnitShouldDisplaySpellTargetName, unit)
    r.name = okN and show(name) or "error"
    r.class = okC and show(class) or "error"
    r.playerIsTarget = try(PlayerIsSpellTarget, unit)
    -- the colour, as far as a secret class lets it go
    local fs = CT.fs or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    CT.fs = fs
    local okColor, c = pcall(C_ClassColor.GetClassColor, class)
    r.getClassColor = okColor and (c and "colour" or "nil") or ("error " .. tostring(c):sub(1, 80))
    if okColor and c then
        r.setTextColor = try(function() fs:SetTextColor(c:GetRGB()) end)
        r.hex = try(c.GenerateHexColor, c)
        r.formatted = try(function() fs:SetFormattedText("%s › |c%s%s|r", "Spell", c:GenerateHexColor(), name) end)
    end
    -- the You badge: the boolean into SetAlphaFromBoolean on a frame
    local host = CT.host or CreateFrame("Frame", nil, UIParent)
    CT.host = host
    local okY, isYou = pcall(PlayerIsSpellTarget, unit)
    r.alphaFromBoolean = okY and try(host.SetAlphaFromBoolean, host, isYou, 1, 0) or "no answer"
    out[#out + 1] = r
end

function CT.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = {}
    SuuUIProbe.castTarget = out
    local f = CT.frame or CreateFrame("Frame")
    CT.frame = f
    f:UnregisterAllEvents()
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    f:SetScript("OnEvent", function(self, _, unit)
        record(unit, out)
        if #out >= 5 then
            self:UnregisterAllEvents()
            ns.Print("Cast target probe: five casts recorded. /reload to save them.")
        end
    end)
    ns.Print("Cast target probe: target a mob that casts (at you, and at someone else if you can); its next five casts are recorded. Then /reload.")
end
