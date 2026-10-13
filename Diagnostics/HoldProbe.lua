-- Diagnostics/HoldProbe.lua
-- "/suu probe hold": why the level-up card stays (found in game: it never
-- went once held past its time). From now until /reload, every Hide and
-- StopHolding on the Alerts module, with the alert showing and the card's
-- state, and every 0.2 s while the card shows: hovered, the mouse foci,
-- mouselook, IsMouseOver, the hold ticker. Saved in SuuUIProbe.hold.

local _, ns = ...

local HP = {}
ns.HoldProbe = HP

local function name(f)
    if not f then return "nil" end
    local ok, n = pcall(function() return f:GetDebugName() end)
    if ok and n then return n end
    ok, n = pcall(function() return f:GetName() end)
    return (ok and n) or tostring(f)
end

function HP.Command()
    local m = ns.Modules.Get("alerts")
    if not m or not m.card then ns.Print("Hold probe: the Alerts module isn't up.") return end
    SuuUIProbe = SuuUIProbe or {}
    local log = {}
    SuuUIProbe.hold = { at = date("%H:%M:%S"), log = log }
    local t0 = GetTime()
    local function note(s)
        if #log < 400 then log[#log + 1] = ("%.1f %s"):format(GetTime() - t0, s) end
    end
    local function state()
        local card = m.card
        local foci = {}
        local list = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        for _, f in ipairs(list) do foci[#foci + 1] = name(f) end
        local okH, hovered = pcall(card.IsHovered, card)
        return ("current=%s shown=%s visible=%s frameShown=%s hovered=%s over=%s look=%s holding=%s under=%s foci=[%s]"):format(
            tostring(m.current), tostring(card:IsShown()), tostring(card:IsVisible()), tostring(m.frame:IsShown()),
            okH and tostring(hovered) or ("ERR " .. tostring(hovered)), tostring(card:IsMouseOver()),
            tostring(IsMouselooking and IsMouselooking()), tostring(m.holding ~= nil),
            tostring(m.under and m.under.key), table.concat(foci, ", "))
    end
    if not HP.hooked then
        HP.hooked = true
        hooksecurefunc(m, "Hide", function(_, key, now) if HP.note then HP.note(("Hide(%s, %s) -> %s"):format(tostring(key), tostring(now), HP.state())) end end)
        hooksecurefunc(m, "StopHolding", function() if HP.note then HP.note("StopHolding -> " .. HP.state()) end end)
        hooksecurefunc(m, "ShowLevelUp", function(_, key) if HP.note then HP.note(("ShowLevelUp(%s) -> %s"):format(tostring(key), HP.state())) end end)
        local ticker = CreateFrame("Frame")
        local acc = 0
        ticker:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.2 or not HP.note or not m.card:IsShown() then return end
            acc = 0
            HP.note("tick " .. HP.state())
        end)
    end
    HP.note, HP.state = note, state
    note("armed " .. state())
    ns.Print("Hold probe: on. /suu levelup 20, hover past its time, move off, wait 5 s, then /reload.")
end
