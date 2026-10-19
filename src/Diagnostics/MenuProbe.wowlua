-- Diagnostics/MenuProbe.lua
-- "/suu probe unitmenu": what a unit menu is made of (asked 2026-10-17: a
-- gap under SuuUI's restyled unit menu). Arms a one-time record of the next
-- unit menu that opens: the menu's edges, and each child (and scroll target
-- child) with its type, shown, top and bottom, its text and its regions.
-- Saved in SuuUIProbe.unitMenu on /reload.

local _, ns = ...

local MP = {}
ns.MenuProbe = MP

local function describe(f, menuTop)
    local t, b = f:GetTop(), f:GetBottom()
    local texts, regions = {}, {}
    for _, r in ipairs({ f:GetRegions() }) do
        local kind = r:GetObjectType()
        if kind == "FontString" then texts[#texts + 1] = tostring(r:GetText()) end
        regions[#regions + 1] = kind .. (r:IsShown() and "" or "(hidden)") .. ("a%.2f"):format(r:GetAlpha() or 0)
    end
    return ("%s shown=%s alpha=%.2f top=%s bottom=%s h=%s text=[%s] regions=%s kids=%d"):format(
        f:GetObjectType(), tostring(f:IsShown()), f:GetAlpha() or 0,
        t and ("%.0f"):format(menuTop - t) or "nil", b and ("%.0f"):format(menuTop - b) or "nil",
        f:GetHeight() and ("%.0f"):format(f:GetHeight()) or "nil",
        table.concat(texts, "|"), table.concat(regions, ","), select("#", f:GetChildren()))
end

function MP.Command()
    local mgr = _G.UnitPopupManager
    if not (mgr and mgr.OpenMenu) then ns.Print("Unit menu probe: no UnitPopupManager.") return end
    MP.armed = true
    if not MP.hooked then
        MP.hooked = true
        hooksecurefunc(mgr, "OpenMenu", function()
            if not MP.armed then return end
            MP.armed = false
            C_Timer.After(0.1, function()
                local manager = Menu and Menu.GetManager and Menu.GetManager()
                local menu = manager and manager:GetOpenMenu()
                SuuUIProbe = SuuUIProbe or {}
                local out = { at = date("%Y-%m-%d %H:%M:%S"), children = {}, target = {} }
                SuuUIProbe.unitMenu = out
                if not menu then out.menu = "none open" return end
                local top = menu:GetTop() or 0
                out.menu = ("top=0 bottom=%.0f h=%.0f w=%.0f scroll=%s"):format(top - (menu:GetBottom() or 0), menu:GetHeight() or 0,
                    menu:GetWidth() or 0, tostring(menu.ScrollBox and menu.ScrollBox:IsShown()))
                for _, c in ipairs({ menu:GetChildren() }) do out.children[#out.children + 1] = describe(c, top) end
                local target = menu.ScrollBox and menu.ScrollBox.ScrollTarget
                if target then
                    for _, c in ipairs({ target:GetChildren() }) do out.target[#out.target + 1] = describe(c, top) end
                end
                ns.Print("Unit menu probe: recorded. /reload to save it.")
            end)
        end)
    end
    ns.Print("Unit menu probe: right-click your own frame now, then /reload.")
end
