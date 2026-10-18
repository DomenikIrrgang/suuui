-- Diagnostics/DragonProbe.lua
-- "/suu probe dragon" (asked 2026-10-18: the optional elite dragon, design
-- "Elite dragon (with crest B)" A, Blizzard's own art): whether Forever has
-- the dragon atlases its target frame uses (Camelot TargetFrameUtils) and
-- their sizes, the classic target frame's dragon textures, and what your
-- target is (classification, boss mob). Saved in SuuUIProbe.dragon on
-- /reload.

local _, ns = ...

local DP = {}
ns.DragonProbe = DP

local isSecret = issecretvalue or function() return false end
local function show(v) return isSecret(v) and "SECRET" or tostring(v) end

local ATLASES = {
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged",
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged",
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver",
    "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare",
}
local FILES = {
    "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
    "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
}

function DP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S"), atlases = {}, files = {} }
    for _, a in ipairs(ATLASES) do
        local ok, info = pcall(C_Texture.GetAtlasInfo, a)
        out.atlases[a] = ok and info and ("%sx%s file=%s"):format(tostring(info.width), tostring(info.height), tostring(info.file or info.filename)) or "missing"
    end
    -- a file texture: does it load (a texture's file path after setting it)
    local t = UIParent:CreateTexture()
    for _, f in ipairs(FILES) do
        local ok = pcall(t.SetTexture, t, f)
        out.files[f] = ok and tostring(t:GetTexture()) or "error"
    end
    t:Hide()
    if UnitExists("target") then
        out.target = ("%s: classification %s, boss mob %s"):format(show(UnitName("target")),
            show(UnitClassification("target")), UnitIsBossMob and show(UnitIsBossMob("target")) or "n/a")
    end
    SuuUIProbe.dragon = out
    ns.Print("Dragon probe: recorded the dragon art and your target. /reload to save it.")
end
