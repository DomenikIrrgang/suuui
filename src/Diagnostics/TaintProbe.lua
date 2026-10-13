-- Diagnostics/TaintProbe.lua
-- "/suu probe taint": which of the values Blizzard's Escape path reads were
-- last written by addon code (issecurevariable), and by whom. A value an
-- addon wrote taints the Blizzard code that reads it; in combat, Escape then
-- may not close windows ("Interface action failed", found in game with the
-- spells window). Saved in SuuUIProbe.taint; also printed.

local _, ns = ...

local TP = {}
ns.TaintProbe = TP

-- the globals the Escape chain reads (ToggleGameMenu, CloseAllWindows,
-- CloseAllBags, CloseWindows, HideUIPanel, CloseSpecialWindows)
local GLOBALS = {
    "ToggleGameMenu", "CloseAllWindows", "CloseWindows", "CloseSpecialWindows", "HideUIPanel", "ShowUIPanel",
    "GetUIPanel", "UpdateUIPanelPositions", "GetUIPanelAttribute", "CanAutoSetGamePadCursorControl",
    "CloseAllBags", "OpenAllBags", "ToggleAllBags", "CloseBackpack", "OpenBackpack", "ToggleBackpack",
    "CloseBag", "OpenBag", "ToggleBag", "IsBagOpen", "ContainerFrame_UpdateAll",
    "FRAME_THAT_OPENED_BAGS", "NUM_TOTAL_BAG_FRAMES", "NUM_CONTAINER_FRAMES", "KEYRING_CONTAINER",
    "UISpecialFrames", "UIPanelWindows", "FramePositionDelegate", "GameMenuFrame", "GameMenuFrame_Show",
    "PlayerSpellsFrame", "CharacterFrame", "ContainerFrameContainer", "ContainerFrameCombinedBags",
    "EventRegistry", "ToggleFrame", "securecallfunction",
}

function TP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S"), combat = InCombatLockdown(), tainted = {} }
    SuuUIProbe.taint = out
    local function check(label, ok, by)
        if not ok then out.tainted[#out.tainted + 1] = label .. " (by " .. tostring(by) .. ")" end
    end
    for _, name in ipairs(GLOBALS) do
        check(name, issecurevariable(name))
    end
    -- every entry of UISpecialFrames
    for i in ipairs(UISpecialFrames or {}) do
        check("UISpecialFrames[" .. i .. "] = " .. tostring(UISpecialFrames[i]), issecurevariable(UISpecialFrames, i))
    end
    -- the fields of the spells window and the Blizzard frames on the path
    for _, fname in ipairs({ "PlayerSpellsFrame", "CharacterFrame", "GameMenuFrame", "FramePositionDelegate", "ContainerFrame1", "ContainerFrameCombinedBags" }) do
        local f = _G[fname]
        if type(f) == "table" then
            for k in pairs(f) do
                if type(k) == "string" then check(fname .. "." .. k, issecurevariable(f, k)) end
            end
        end
    end
    for i, line in ipairs(out.tainted) do
        if i <= 25 then ns.Print("Taint: " .. line) end
    end
    ns.Print(("Taint probe: %d values written by addon code. /reload to save."):format(#out.tainted))
end
