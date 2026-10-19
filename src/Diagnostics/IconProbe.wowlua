-- Diagnostics/IconProbe.lua
-- "/suu probe icons": the art (icon file ID) of every spell ID the Cooldown
-- Manager presets use, every class's (Diagnostics/PresetSpellIDs.lua, written
-- by tools/gen_presets.lua). The generator then gives every preset entry the
-- art most of its ranks share: a name's lowest ID is often an NPC version
-- with other art (Seal of Wisdom). Saved in SuuUIProbe.icons on /reload.
--
--   /suu probe icons      read them now (a moment, out of combat)

local _, ns = ...

local IP = {}
ns.IconProbe = IP

local isSecret = issecretvalue or function() return false end

function IP.Command()
    local ids = ns.PresetSpellIDs
    if not ids then
        ns.Print("Icon probe: no spell list (Diagnostics/PresetSpellIDs.lua).")
        return
    end
    if InCombatLockdown() then
        ns.Print("Icon probe: out of combat, please.")
        return
    end
    local icons, n = {}, 0
    for _, id in ipairs(ids) do
        local ok, file = pcall(C_Spell.GetSpellTexture, id)
        if ok and file ~= nil and not isSecret(file) then
            icons[id] = file
            n = n + 1
        end
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.icons = { at = date("%Y-%m-%d %H:%M"), icons = icons }
    ns.Print(("Icon probe: the art of %d of %d spells read. /reload to save."):format(n, #ids))
end
