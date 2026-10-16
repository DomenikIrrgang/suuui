-- Diagnostics/GameMenuProbe.lua
-- "/suu probe gamemenu": can SuuUI's own game menu open what the game's does
-- (asked 2026-10-17: the game menu becomes SuuUI's own window)? The game's
-- buttons run Blizzard's code (SettingsPanel:Open, ShowUIPanel(EditModeManagerFrame),
-- ShowMacroFrame, ShowUIPanel(AddonList), ToggleHelpFrame); from SuuUI's
-- buttons the same calls run as addon code, and Options and Edit Mode then
-- may save nothing or be blocked. A small panel has one button per entry,
-- each making the call as SuuUI's menu would. Use each one (change a key
-- binding and a setting in Options, move a frame and save in Edit Mode),
-- then Check: it records the errors and blocked calls since, and which
-- fields of SettingsPanel and EditModeManagerFrame addon code wrote. Saved
-- in SuuUIProbe.gameMenu on /reload.

local _, ns = ...

local GP = {}
ns.GameMenuProbe = GP

local UI = ns.UI

local function taintedFields(fname)
    local f, list = _G[fname], {}
    if type(f) ~= "table" then return "missing" end
    for k in pairs(f) do
        if type(k) == "string" then
            local ok, by = issecurevariable(f, k)
            if not ok then list[#list + 1] = k .. " (by " .. tostring(by) .. ")" end
        end
    end
    table.sort(list)
    return #list == 0 and "none" or table.concat(list, ", ")
end

local ENTRIES = {
    { key = "options", text = "Options", call = function() SettingsPanel:Open() end },
    { key = "editmode", text = "Edit Mode", call = function() ShowUIPanel(EditModeManagerFrame) end },
    { key = "macros", text = "Macros", call = function() ShowMacroFrame() end },
    { key = "addons", text = "AddOns", call = function() ShowUIPanel(AddonList) end },
    { key = "support", text = "Support", call = function() ToggleHelpFrame() end },
}

function GP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%Y-%m-%d %H:%M:%S"), calls = {}, start = {
        settings = taintedFields("SettingsPanel"), editMode = taintedFields("EditModeManagerFrame"),
    } }
    SuuUIProbe.gameMenu = out
    local p = GP.panel or UI.Panel(UIParent, { title = "Game menu probe", width = 240, height = 330, solid = true })
    GP.panel = p
    p:SetFrameStrata("DIALOG")
    p:ClearAllPoints()
    p:SetPoint("LEFT", 40, 0)
    if not p.buttons then
        p.buttons = {}
        local prev
        for _, e in ipairs(ENTRIES) do
            local b = UI.Button(p.body, { text = e.text, width = 200, onClick = function()
                local ok, err = pcall(e.call)
                local line = #out.calls + 1
                out.calls[line] = ("%s %s: %s, combat %s"):format(date("%H:%M:%S"), e.key,
                    ok and "ok" or ("error " .. tostring(err)), tostring(InCombatLockdown()))
                -- what addon code wrote by opening it, a moment after
                C_Timer.After(1, function()
                    out.calls[line] = out.calls[line] .. "; written by addon code: SettingsPanel " .. taintedFields("SettingsPanel")
                        .. "; EditModeManagerFrame " .. taintedFields("EditModeManagerFrame")
                end)
            end })
            b:SetPoint("TOP", prev or p.body, prev and "BOTTOM" or "TOP", 0, prev and -8 or 0)
            prev = b
        end
        local check = UI.Button(p.body, { text = "Check", variant = "primary", width = 200, onClick = function()
            local errors, blocked = SuuUIDB and SuuUIDB.errors or {}, SuuUIDB and SuuUIDB.blocked or {}
            local result = { at = date("%H:%M:%S"), errors = {}, blocked = {},
                settings = taintedFields("SettingsPanel"), editMode = taintedFields("EditModeManagerFrame") }
            -- both lists keep their last 30, so new entries are told by their time
            for _, e in ipairs(errors) do
                if type(e) == "table" and tostring(e.time) >= out.at then
                    result.errors[#result.errors + 1] = tostring(e.source) .. ": " .. tostring(e.message)
                end
            end
            for _, e in ipairs(blocked) do
                if type(e) == "table" and tostring(e.time) >= out.at then
                    result.blocked[#result.blocked + 1] = ("%s %s %s"):format(tostring(e.event), tostring(e.addon), tostring(e.func))
                end
            end
            out.check = result
            ns.Print(("Game menu probe: %d errors, %d blocked since the start; written by addon code: SettingsPanel %s, EditModeManagerFrame %s. /reload to save.")
                :format(#result.errors, #result.blocked, result.settings, result.editMode))
        end })
        check:SetPoint("BOTTOM", p.body, "BOTTOM", 0, 0)
    end
    p:Show()
    ns.Print("Game menu probe: open each entry from this panel. In Options change a key binding and a setting, then close it;"
        .. " in Edit Mode move a frame, save and exit. Then Check, and /reload.")
end
