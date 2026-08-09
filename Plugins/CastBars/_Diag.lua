-- TEMPORARY DIAGNOSTIC — DELETE THIS FILE AND ITS .toc LINE WHEN THE ATTACH BUG IS FIXED.
--
-- Not shipped code and deliberately outside the addon's rules (raw frames, prints, no
-- components): its whole job is to report what the live client thinks about the attached
-- cast bar, because the simulated client resolves anchors the real one leaves unresolved
-- and 18 harness assertions pass while the bar draws nothing.
--
-- Reports twice: right after login settles, and again three seconds later. If the first
-- report is healthy and the second is not, something un-does the placement after the fact,
-- which no single snapshot could show.
local function num(v)
    if type(v) ~= "number" then return tostring(v) end
    return string.format("%.1f", v)
end

-- The anchor itself is the question GetTop cannot answer: a frame with no points was never
-- positioned, while a frame with points whose target has no rect resolves to nil anyway.
local function points(f)
    local n = f.GetNumPoints and f:GetNumPoints() or -1
    if n == 0 then return "POINTS=0 (never anchored)" end
    local p, rel, rp, x, y = f:GetPoint(1)
    local relName = rel and (rel.GetName and rel:GetName() or "<anon>") or "nil"
    return string.format("POINTS=%d p=%s rel=%s rp=%s x=%s y=%s",
        n, tostring(p), tostring(relName), tostring(rp), num(x), num(y))
end

local function line(label, f)
    if not f then print("SUUDIAG " .. label .. ": MISSING"); return end
    print(string.format("SUUDIAG %s: top=%s left=%s w=%s h=%s shown=%s vis=%s a=%s %s",
        label, num(f:GetTop()), num(f:GetLeft()), num(f:GetWidth()), num(f:GetHeight()),
        tostring(f:IsShown()), tostring(f:IsVisible()), num(f:GetAlpha()), points(f)))
end

local function report(tag)
    local cb = SuuUI.Plugins:Get("cast_bars")
    local uf = SuuUI.Plugins:Get("unit_frames")
    local ctl = cb and cb._controllers and cb._controllers.player
    local bar = ctl and ctl:GetBar()
    local pf  = uf and uf._playerFrame

    print("=== SUUDIAG " .. tag .. " ===")
    print("SUUDIAG mode=" .. tostring(ctl and ctl:GetMode())
        .. " bar=" .. tostring(bar ~= nil)
        .. " state=" .. tostring(bar and bar:GetState())
        .. " editMode=" .. tostring(SuuUI.ToggleUI:IsEditMode()))

    if pf then
        line("unitWrapper", pf:GetFrame())
        line("slotBelow", pf._slotBelow and pf._slotBelow:GetFrame())
        local kids = pf._slotBelow and pf._slotBelow:GetChildren()
        print("SUUDIAG slotBelow children=" .. tostring(kids and #kids or "nil"))
        -- Whether the child the slot is holding is the same frame the controller has. A
        -- mismatch means an earlier widget was left in the slot and the live one was never
        -- placed, which would look exactly like this.
        if kids and kids[1] and bar then
            print("SUUDIAG slotChild==barFrame: " .. tostring(kids[1] == bar:GetFrame()))
        end
    end

    if bar then
        line("barWrapper", bar:GetFrame())
        line("contentRow", bar._row and bar._row:GetFrame())
        line("statusBar", bar._bar and bar._bar:GetFrame())
        line("icon", bar._icon and bar._icon:GetFrame())
    end
    print("=== SUUDIAG " .. tag .. " end ===")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() report("T+1s") end)
        C_Timer.After(4, function() report("T+4s") end)
    else
        report("immediate")
    end
end)

SlashCmdList = SlashCmdList or {}
SLASH_SUUDIAG1 = "/suudiag"
SlashCmdList.SUUDIAG = function() report("manual") end
