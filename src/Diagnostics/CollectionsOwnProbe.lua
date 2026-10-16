-- Diagnostics/CollectionsOwnProbe.lua
-- "/suu probe collown": can SuuUI build its own collections window (asked
-- 2026-10-16: an own window instead of the restyle)? Recorded at once:
--   mounts       how many, how many yours, three samples with their extra
--                info (the model's display ID, source)
--   pets, toys, heirlooms   counts and a sample each
--   appearances  every category: its name, how many appearances, how many
--                yours, a sample with its sources; what you wear per slot
-- and a panel of SuuUI's own buttons for what needs a click or your eyes:
--   Summon       your first usable mount through C_MountJournal.SummonByID
--                (again: Dismiss), from SuuUI's button
--   Toy          your first toy through a secure button of SuuUI's (type toy)
--   two models   a mount's model in a PlayerModel (Next: the next mount) and
--                you in a DressUpModel trying on an appearance (Next too)
-- What the game answers (a blocked action, the cast) is printed and saved.
-- Saved in SuuUIProbe.collectionsOwn on /reload.

local _, ns = ...

local CP = {}
ns.CollectionsOwnProbe = CP

local UI = ns.UI
local isSecret = issecretvalue or function() return false end

local function show(v, depth)
    depth = depth or 0
    if isSecret(v) then return "secret" end
    if type(v) == "table" then
        if depth > 1 then return "{…}" end
        local parts = {}
        for k, x in pairs(v) do
            if type(x) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1) end
            if #parts > 30 then break end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

-- every result of a call, or why it failed
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 160) end
    local parts = {}
    for i = 2, select("#", unpack(res)) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, " | ")
end

local function raw(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
end

local out
local function line(section, text)
    out[section] = out[section] or {}
    table.insert(out[section], text)
end

local function note(text)
    line("clicks", date("%H:%M:%S") .. " " .. text)
    ns.Print("Collections probe: " .. text)
end

--------------------------------------------------------------------------------
-- The data
--------------------------------------------------------------------------------

local function mounts()
    local MJ = C_MountJournal
    if not MJ then line("mounts", "C_MountJournal missing") return end
    local ids = raw(MJ.GetMountIDs) or {}
    local yours, usable = 0, nil
    for _, id in ipairs(ids) do
        local name, spellID, icon, active, isUsable, sourceType, fav, faction, factionID, hide, collected = raw(MJ.GetMountInfoByID, id)
        if collected then
            yours = yours + 1
            if isUsable and not usable then usable = id end
        end
    end
    line("mounts", ("%d mounts, %d yours, first usable %s; GetNumMounts %s"):format(#ids, yours, tostring(usable), call(MJ.GetNumMounts)))
    for i = 1, math.min(3, #ids) do
        line("mounts", "info " .. call(MJ.GetMountInfoByID, ids[i]))
        line("mounts", "extra " .. call(MJ.GetMountInfoExtraByID, ids[i]))
    end
    CP.mountIDs, CP.usableMount = ids, usable
end

local function pets()
    local PJ = C_PetJournal
    if not PJ then line("pets", "C_PetJournal missing") return end
    line("pets", "GetNumPets " .. call(PJ.GetNumPets))
    line("pets", "first " .. call(PJ.GetPetInfoByIndex, 1))
    line("pets", "summoned " .. call(PJ.GetSummonedPetGUID))
end

local function toys()
    local TB = C_ToyBox
    if not TB then line("toys", "C_ToyBox missing") return end
    line("toys", ("GetNumToys %s, filtered %s, learned displayed %s"):format(call(TB.GetNumToys), call(TB.GetNumFilteredToys),
        call(TB.GetNumLearnedDisplayedToys)))
    local first
    for i = 1, (raw(TB.GetNumFilteredToys) or 0) do
        local itemID = raw(TB.GetToyFromIndex, i)
        if itemID and raw(PlayerHasToy, itemID) and not first then first = itemID end
        if i <= 3 then line("toys", ("%d: %s info %s has %s"):format(i, show(itemID), call(TB.GetToyInfo, itemID), call(PlayerHasToy, itemID))) end
    end
    line("toys", "first of yours " .. tostring(first))
    CP.toy = first
end

local function heirlooms()
    local H = C_Heirloom
    if not H then line("heirlooms", "C_Heirloom missing") return end
    line("heirlooms", ("GetNumHeirlooms %s, known %s"):format(call(H.GetNumHeirlooms), call(H.GetNumKnownHeirlooms)))
end

local SLOTS = { "HEADSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "SHIRTSLOT", "TABARDSLOT", "WRISTSLOT", "HANDSSLOT",
                "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT" }

local function appearances()
    local TC = C_TransmogCollection
    if not TC then line("appearances", "C_TransmogCollection missing") return end
    line("appearances", ("class filter %s, collected shown %s, uncollected shown %s"):format(call(TC.GetClassFilter),
        call(TC.GetCollectedShown), call(TC.GetUncollectedShown)))
    local sample
    for cat = 1, 40 do
        local name = raw(TC.GetCategoryInfo, cat)
        if name then
            local list = raw(TC.GetCategoryAppearances, cat) or {}
            local yours = 0
            for _, a in ipairs(list) do if a.isCollected then yours = yours + 1 end end
            line("appearances", ("%d %s: %d appearances, %d yours, total %s collected %s"):format(cat, tostring(name), #list, yours,
                call(TC.GetCategoryTotal, cat), call(TC.GetCategoryCollectedCount, cat)))
            if not sample and list[1] then
                sample = list[1]
                line("appearances", "  sample " .. show(sample))
                local sources = raw(TC.GetAppearanceSources, sample.visualID) or {}
                line("appearances", ("  %d sources, first %s"):format(#sources, show(sources[1])))
                if sources[1] and sources[1].sourceID then
                    line("appearances", "  source info " .. call(TC.GetSourceInfo, sources[1].sourceID))
                    CP.source = sources[1].sourceID
                end
            end
        end
    end
    -- what you wear: each slot's item and its appearance
    for _, slot in ipairs(SLOTS) do
        local id = raw(GetInventorySlotInfo, slot)
        local itemID = id and raw(GetInventoryItemID, "player", id)
        if itemID then
            line("worn", ("%s item %s appearance %s"):format(slot, tostring(itemID), call(TC.GetItemInfo, itemID)))
        end
    end
end

--------------------------------------------------------------------------------
-- The panel: SuuUI's own buttons and two models
--------------------------------------------------------------------------------

local function build()
    local p = UI.Panel(UIParent, { title = "Collections probe", width = 470, height = 330, solid = true })
    p:SetFrameStrata("DIALOG")
    p:SetPoint("CENTER", 0, 60)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if UI.CloseButton then
        local c = UI.CloseButton(p, function() p:Hide() end)
        if c then c:SetPoint("TOPRIGHT", -8, -8) end
    end
    -- a mount's model
    local m = CreateFrame("PlayerModel", nil, p.body)
    m:SetSize(200, 200)
    m:SetPoint("TOPLEFT")
    local mi = 0
    local mountName = UI.Text(p.body, "caption", "ink-muted")
    mountName:SetPoint("TOP", m, "BOTTOM", 0, -4)
    local function nextMount()
        local ids = CP.mountIDs or {}
        if #ids == 0 then mountName:SetValue("no mounts") return end
        mi = mi % #ids + 1
        local name = raw(C_MountJournal.GetMountInfoByID, ids[mi])
        local display = raw(C_MountJournal.GetMountInfoExtraByID, ids[mi])
        local ok, err = pcall(m.SetDisplayInfo, m, display or 0)
        mountName:SetValue(("%s (display %s)%s"):format(tostring(name), tostring(display), ok and "" or (" error " .. tostring(err))))
    end
    local nm = UI.Button(p.body, { text = "Next mount", width = 110, onClick = nextMount })
    nm:SetPoint("TOP", mountName, "BOTTOM", 0, -6)
    -- you, trying on an appearance
    local d = CreateFrame("DressUpModel", nil, p.body)
    d:SetSize(200, 200)
    d:SetPoint("TOPRIGHT")
    local tryText = UI.Text(p.body, "caption", "ink-muted")
    tryText:SetPoint("TOP", d, "BOTTOM", 0, -4)
    local function tryOn()
        local ok = pcall(d.SetUnit, d, "player")
        local src = CP.source
        local ok2, err = true, nil
        if src then ok2, err = pcall(d.TryOn, d, src) end
        tryText:SetValue(("you %s, try on source %s %s"):format(ok and "shown" or "error", tostring(src), ok2 and "ok" or ("error " .. tostring(err))))
    end
    local tb = UI.Button(p.body, { text = "Try on", width = 110, onClick = tryOn })
    tb:SetPoint("TOP", tryText, "BOTTOM", 0, -6)
    -- Summon / Dismiss from SuuUI's own button
    local sum = UI.Button(p.body, { text = "Summon test", width = 130, onClick = function()
        local id = CP.usableMount
        if not id then note("no usable mount of yours on this character") return end
        if IsMounted and IsMounted() then
            note("Dismiss: " .. call(C_MountJournal.Dismiss))
        else
            note("SummonByID(" .. id .. "): " .. call(C_MountJournal.SummonByID, id))
        end
    end })
    sum:SetPoint("BOTTOMLEFT")
    -- a toy through SuuUI's own secure button
    local toy = CreateFrame("Button", "SuuUICollectionsProbeToy", p.body, "SecureActionButtonTemplate")
    toy:SetSize(130, 30)
    toy:SetPoint("BOTTOMRIGHT")
    toy:RegisterForClicks("AnyUp", "AnyDown")
    UI.Fill(toy, "surface-raised"):SetAllPoints()
    UI.Border(toy, "gilt-line")
    local tt = UI.Text(toy, "label", "ink")
    tt:SetPoint("CENTER")
    tt:SetValue("Toy test")
    p.toy, p.mountModel, p.dress, p.nextMount, p.tryOn = toy, m, d, nextMount, tryOn
    return p
end

function CP.Command()
    out = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.collectionsOwn = out
    for _, step in ipairs({ mounts, pets, toys, heirlooms, appearances }) do
        local ok, err = pcall(step)
        if not ok then line("errors", tostring(err)) end
    end
    CP.panel = CP.panel or build()
    CP.panel:Show()
    CP.panel.nextMount()
    CP.panel.tryOn()
    -- the toy button: set up out of combat
    if CP.toy and not InCombatLockdown() then
        CP.panel.toy:SetAttribute("type", "toy")
        CP.panel.toy:SetAttribute("toy", CP.toy)
        note("toy button ready for item " .. CP.toy)
    elseif not CP.toy then
        note("no toy of yours on this character: the toy test can't run here")
    end
    if not CP.listening then
        CP.listening = true
        local f = CreateFrame("Frame")
        for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UNIT_SPELLCAST_SUCCEEDED", "UI_ERROR_MESSAGE",
                             "COMPANION_UPDATE", "NEW_MOUNT_ADDED" }) do
            pcall(f.RegisterEvent, f, e)
        end
        f:SetScript("OnEvent", function(_, e, a, b, c)
            if e == "UNIT_SPELLCAST_SUCCEEDED" and a ~= "player" then return end
            note(("%s %s %s %s"):format(e, show(a), show(b), show(c)))
        end)
    end
    ns.Print("Collections probe: data recorded. Try Summon test and Toy test if you can, look at both models (Next mount, Try on), then /reload.")
end
