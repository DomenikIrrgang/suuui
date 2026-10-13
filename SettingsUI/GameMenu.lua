-- SettingsUI/GameMenu.lua
-- A "SuuUI settings" button under the game menu (Esc). It hangs below the menu
-- rather than among Blizzard's buttons, so the menu's own layout and its
-- protected buttons are never touched. Hidden in combat.

local _, ns = ...

local UI = ns.UI

local button

local function ensure()
    if button or not GameMenuFrame then return end
    button = UI.Button(GameMenuFrame, { text = "SuuUI settings", width = 200, onClick = function()
        HideUIPanel(GameMenuFrame)
        ns.SettingsWindow.Open()
    end })
    button:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -8)
end

if GameMenuFrame then
    GameMenuFrame:HookScript("OnShow", function()
        ensure()
        button:SetShown(not InCombatLockdown())
    end)
end
