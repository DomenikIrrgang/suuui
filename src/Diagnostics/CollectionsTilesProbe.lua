-- Diagnostics/CollectionsTilesProbe.lua
-- "/suu probe colltiles": the open questions for SuuUI's own collections
-- window (2026-10-16, while its design is drawn):
--   toys       can every toy be listed, yours or not? (the game's filter
--              hides the ones you lack: shown for a moment, then put back)
--   flags      what the game marks: new appearances, mounts needing their
--              fanfare, favourites (mounts, toys, appearances)
--   cameras    the camera the game frames an appearance with
--              (GetAppearanceCameraID) and a mount with (its display's)
--   scene      a mount in a ModelScene framed by the mount's own scene ID
--              (the 6th value of GetMountInfoExtraByID), as the game does
--   tiles      a page of 18 appearance previews in a panel, framed by those
--              cameras: how long they take to build and what the frame rate
--              does while they show
-- Printed and saved in SuuUIProbe.collectionsTiles on /reload; the panel
-- stays for a screenshot.

local _, ns = ...

local CP = {}
ns.CollectionsTilesProbe = CP

local UI = ns.UI
local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "secret" end
    if type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            if type(x) ~= "function" and type(x) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

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
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
end

local out
local function line(section, text)
    out[section] = out[section] or {}
    table.insert(out[section], text)
end

-- Every toy: the filter shows the ones you lack too, for this read only.
local function toys()
    local TB = C_ToyBox
    if not TB then line("toys", "C_ToyBox missing") return end
    local was = { collected = raw(TB.GetCollectedShown), uncollected = raw(TB.GetUncollectedShown), unusable = raw(TB.GetUnusableShown) }
    line("toys", "filters before " .. show(was) .. ", filtered " .. call(TB.GetNumFilteredToys))
    pcall(TB.SetCollectedShown, true)
    pcall(TB.SetUncollectedShown, true)
    pcall(TB.SetUnusableShown, true)
    pcall(TB.SetAllSourceTypeFilters, true)
    pcall(TB.SetFilterString, "")
    pcall(TB.ForceToyRefilter)
    local n = raw(TB.GetNumFilteredToys) or 0
    line("toys", "filtered with everything shown: " .. n)
    for i = 1, math.min(n, 25) do
        local itemID = raw(TB.GetToyFromIndex, i)
        line("toys", ("%d: %s info %s has %s fav %s"):format(i, show(itemID), call(TB.GetToyInfo, itemID), call(PlayerHasToy, itemID),
            call(TB.GetIsFavorite, itemID)))
    end
    -- put the game's filters back as they were
    if was.collected ~= nil then pcall(TB.SetCollectedShown, was.collected) end
    if was.uncollected ~= nil then pcall(TB.SetUncollectedShown, was.uncollected) end
    if was.unusable ~= nil then pcall(TB.SetUnusableShown, was.unusable) end
    pcall(TB.ForceToyRefilter)
    line("toys", "filters after " .. show({ collected = raw(TB.GetCollectedShown), uncollected = raw(TB.GetUncollectedShown),
        unusable = raw(TB.GetUnusableShown) }))
end

local function flags()
    local MJ, TC = C_MountJournal, C_TransmogCollection
    line("flags", "mounts needing fanfare " .. call(MJ and MJ.GetNumMountsNeedingFanfare))
    local ids = raw(MJ and MJ.GetMountIDs) or {}
    if ids[1] then
        line("flags", "first mount: needs fanfare " .. call(MJ.NeedsFanfare, ids[1]) .. ", favourite " .. call(MJ.GetIsFavorite, 1))
        line("flags", "mount camera via display " .. call(MJ.GetMountInfoExtraByID, ids[1]))
        line("flags", "all displays " .. call(MJ.GetMountAllCreatureDisplayInfoByID, ids[1]))
    end
    line("flags", "latest appearance " .. call(TC and TC.GetLatestAppearance))
    line("flags", "appearance favourites " .. call(TC and TC.HasFavorites))
    line("flags", "pet favourites " .. call(C_PetJournal and C_PetJournal.HasFavoritePets))
    line("flags", "toy favourites " .. call(C_ToyBox and C_ToyBox.HasFavorites))
end

-- Up to 18 of your appearances in one slot (chest, else any armor slot).
local function appearancesToShow()
    local TC = C_TransmogCollection
    local list = {}
    for _, cat in ipairs({ 4, 10, 8, 11, 3, 7, 9, 2 }) do
        for _, a in ipairs(raw(TC.GetCategoryAppearances, cat) or {}) do
            if a.isCollected then
                local sources = raw(TC.GetAppearanceSources, a.visualID) or {}
                local src = sources[1] and sources[1].sourceID
                if src then list[#list + 1] = { cat = cat, visual = a.visualID, source = src, new = raw(TC.IsNewAppearance, a.visualID),
                    fav = raw(TC.GetIsAppearanceFavorite, a.visualID), camera = raw(TC.GetAppearanceCameraID, a.visualID) } end
            end
            if #list >= 18 then break end
        end
        if #list >= 18 then break end
    end
    return list
end

local function tiles()
    local list = appearancesToShow()
    line("tiles", #list .. " appearances of yours to show")
    for i = 1, math.min(4, #list) do line("tiles", show(list[i])) end
    local p = CP.panel or UI.Panel(UIParent, { title = "Collections tiles probe", width = 6 * 92 + 40, height = 3 * 120 + 90 + 230, solid = true })
    CP.panel = p
    p:SetFrameStrata("DIALOG")
    p:SetPoint("CENTER", 0, 40)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if not p.closeButton and UI.CloseButton then
        p.closeButton = UI.CloseButton(p, function() p:Hide() end)
        if p.closeButton then p.closeButton:SetPoint("TOPRIGHT", -8, -8) end
    end
    p.tiles = p.tiles or {}
    local fpsBefore = GetFramerate()
    local t0 = debugprofilestop()
    for i, a in ipairs(list) do
        local m = p.tiles[i]
        if not m then
            m = CreateFrame("DressUpModel", nil, p.body)
            m:SetSize(88, 116)
            m:SetPoint("TOPLEFT", ((i - 1) % 6) * 92, -math.floor((i - 1) / 6) * 120)
            UI.Fill(m, "surface-sunk", "BACKGROUND"):SetAllPoints()
            p.tiles[i] = m
        end
        pcall(m.SetUnit, m, "player")
        pcall(m.Undress, m)
        local camOK = a.camera and m.ApplyUICamera and pcall(m.ApplyUICamera, m, a.camera)
        a.camOK = camOK and true or false
        pcall(m.TryOn, m, a.source)
        m:Show()
    end
    local built = debugprofilestop() - t0
    line("tiles", ("built %d previews in %.1f ms; frame rate before %.0f"):format(#list, built, fpsBefore))
    line("tiles", ("ApplyUICamera there: %s; cameras used %s"):format(tostring(p.tiles[1] and p.tiles[1].ApplyUICamera ~= nil),
        tostring(list[1] and list[1].camOK)))
    -- a mount in a ModelScene, framed by its own scene
    local ids = raw(C_MountJournal.GetMountIDs) or {}
    local id = ids[1]
    if id and not p.scene then
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, p.body, "ModelSceneMixinTemplate")
        line("scene", "ModelScene with ModelSceneMixinTemplate: " .. (ok and "made" or ("error " .. tostring(scene))))
        if ok then
            scene:SetSize(300, 210)
            scene:SetPoint("BOTTOM", 0, 0)
            UI.Fill(scene, "surface-sunk", "BACKGROUND"):SetAllPoints()
            p.scene = scene
        end
    end
    if id and p.scene then
        local display, _, _, isSelf, _, sceneID = raw(C_MountJournal.GetMountInfoExtraByID, id)
        local name = raw(C_MountJournal.GetMountInfoByID, id)
        line("scene", ("mount %s display %s scene %s self %s"):format(tostring(name), tostring(display), tostring(sceneID), tostring(isSelf)))
        line("scene", "TransitionToModelSceneID " .. call(p.scene.TransitionToModelSceneID, p.scene, sceneID,
            CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true))
        local actor = raw(p.scene.GetActorByTag, p.scene, "unwrapped")
        line("scene", "actor 'unwrapped' " .. tostring(actor ~= nil))
        if actor then
            line("scene", "SetModelByCreatureDisplayID " .. call(actor.SetModelByCreatureDisplayID, actor, display))
            if isSelf then pcall(actor.SetAnimation, actor, 618) end
        end
    end
    p:Show()
    -- the frame rate while they show
    C_Timer.After(3, function()
        line("tiles", ("frame rate with them showing %.0f"):format(GetFramerate()))
        ns.Print(("Collections tiles probe: frame rate %.0f before, %.0f with %d previews. /reload to save."):format(fpsBefore, GetFramerate(), #list))
    end)
end

function CP.Command()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_Collections") end
    out = { at = date("%Y-%m-%d %H:%M:%S") }
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.collectionsTiles = out
    for _, step in ipairs({ toys, flags, tiles }) do
        local ok, err = pcall(step)
        if not ok then line("errors", tostring(err)) end
    end
    ns.Print("Collections tiles probe: recorded; the panel shows 18 previews. Take a screenshot; the frame rate comes in 3 seconds.")
end
