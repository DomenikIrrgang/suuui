-- Diagnostics/MicroProbe.lua
-- "/suu probe micro": what SuuUI's own micro menu and minimap (step 2.1) take
-- over. The micro menu's buttons in Blizzard's order (name, shown, tooltip,
-- art, whether it's flashing or has an alert), MICRO_BUTTONS, and the
-- minimap cluster's and the minimap's children by name; a few APIs the
-- minimap uses. Saved in SuuUIProbe.micro on /reload.

local _, ns = ...

local MiP = {}
ns.MicroProbe = MiP

local isSecret = issecretvalue or function() return false end

local function str(v)
    if isSecret(v) then return "secret" end
    if v == nil then return nil end
    return tostring(v):sub(1, 120)
end

local function children(frame)
    local out = {}
    if not frame or not frame.GetChildren then return out end
    for i, c in ipairs({ frame:GetChildren() }) do
        local ok, name = pcall(c.GetName, c)
        local okT, ot = pcall(c.GetObjectType, c)
        local okS, shown = pcall(c.IsShown, c)
        out[i] = ("%s (%s%s)"):format(ok and name or "?", okT and ot or "?", okS and (shown and ", shown" or ", hidden") or "")
    end
    return out
end

local function texInfo(tex)
    if not tex then return nil end
    local okA, atlas = pcall(tex.GetAtlas, tex)
    if okA and atlas then return "atlas " .. tostring(atlas) end
    local okT, file = pcall(tex.GetTexture, tex)
    return okT and ("file " .. tostring(file)) or nil
end

function MiP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%H:%M:%S") }
    -- the micro menu, in its layout order
    local menu = _G.MicroMenu
    out.microMenu = menu and "present" or "missing"
    out.buttons = {}
    local list = {}
    if menu and menu.GetLayoutChildren then
        local ok, kids = pcall(menu.GetLayoutChildren, menu)
        if ok and type(kids) == "table" then list = kids end
    end
    if #list == 0 and menu then list = { menu:GetChildren() } end
    for i, b in ipairs(list) do
        local okN, name = pcall(b.GetName, b)
        local e = { name = okN and name or "?" }
        e.shown = b.IsShown and b:IsShown() or false
        e.tooltip = str(b.tooltipText)
        e.newbie = str(b.newbieText)
        e.normal = b.GetNormalTexture and texInfo(b:GetNormalTexture()) or nil
        e.flash = b.Flash and b.Flash.IsShown and b.Flash:IsShown() or nil
        e.flashing = b.FlashBorder and b.FlashBorder.IsShown and b.FlashBorder:IsShown() or nil
        e.onClick = b.GetScript and (b:GetScript("OnClick") and "script" or "none") or nil
        e.protected = b.IsProtected and b:IsProtected() or nil
        out.buttons[i] = e
    end
    out.MICRO_BUTTONS = type(MICRO_BUTTONS) == "table" and MICRO_BUTTONS or "missing"
    -- the minimap's surroundings
    out.minimapCluster = children(_G.MinimapCluster)
    out.minimap = children(_G.Minimap)
    out.minimapParent = Minimap and Minimap:GetParent() and Minimap:GetParent():GetName() or "?"
    out.minimapSize = Minimap and ("%.0fx%.0f"):format(Minimap:GetSize()) or "?"
    out.apis = {}
    for _, n in ipairs({ "GetMinimapZoneText", "GetZonePVPInfo", "HasNewMail", "GetGameTime", "ToggleWorldMap",
                         "ToggleAllBags", "ToggleCharacter", "ToggleFriendsFrame", "ToggleQuestLog", "PlayerSpellsUtil",
                         "C_Minimap", "MiniMapTracking", "MinimapZoomIn", "TimeManagerClockButton", "GameTimeFrame",
                         "MiniMapMailFrame", "QueueStatusButton", "C_ClassTalents", "UnitCharacterPoints" }) do
        out.apis[n] = _G[n] ~= nil and type(_G[n]) or "missing"
    end
    if C_Minimap then
        local fns = {}
        for k in pairs(C_Minimap) do fns[#fns + 1] = k end
        table.sort(fns)
        out.C_Minimap = fns
    end
    if C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local ok, v = pcall(C_ClassTalents.HasUnspentTalentPoints)
        out.unspentTalents = ok and str(v) or "error"
    end
    if UnitCharacterPoints then out.characterPoints = str(UnitCharacterPoints("player")) end
    SuuUIProbe.micro = out
    ns.Print(("Micro probe: %d micro buttons, %d minimap cluster children. /reload to save."):format(#out.buttons, #out.minimapCluster))
end
