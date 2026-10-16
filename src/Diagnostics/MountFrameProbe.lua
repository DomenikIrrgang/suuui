-- Diagnostics/MountFrameProbe.lua
-- "/suu probe mountframe": where a mount's feet are in SuuUI's collections
-- stage (2026-10-17: the game centres each mount in its model frame by its
-- whole size, so some stand on the floor shadow and some float). It shows
-- ten mounts one after another in a model frame the stage's size and
-- records, once each has loaded, what the frame can say about it: which of
-- its methods there are (once), its box, camera, scale and position. The
-- panel shows each one for a screenshot. Saved in SuuUIProbe.mountFrame on
-- /reload.

local _, ns = ...

local MP = {}
ns.MountFrameProbe = MP

local UI = ns.UI
local isSecret = issecretvalue or function() return false end

local function show(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if isSecret(v) then parts[#parts + 1] = "secret"
        elseif type(v) == "number" then parts[#parts + 1] = ("%.3f"):format(v)
        else parts[#parts + 1] = tostring(v) end
    end
    return table.concat(parts, ", ")
end

local function ask(m, method)
    local f = m[method]
    if type(f) ~= "function" then return "missing" end
    local res = { pcall(f, m) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 80) end
    return show(select(2, unpack(res)))
end

local QUESTIONS = { "GetActiveBoundingBox", "GetModelScale", "GetPosition", "GetCameraPosition", "GetCameraTarget",
                    "GetCameraDistance", "GetCameraFacing", "GetCameraRoll", "GetFacing", "GetPitch", "GetModelFileID",
                    "GetCamDistanceScale", "GetWorldScale", "GetViewInsets" }

function MP.Command()
    local MJ = C_MountJournal
    local list = {}
    for _, id in ipairs(MJ and MJ.GetMountIDs() or {}) do
        local name, _, _, _, _, _, _, _, _, hidden = MJ.GetMountInfoByID(id)
        if name and not hidden and #list < 10 then
            local display = MJ.GetMountInfoExtraByID(id)
            list[#list + 1] = { name = name, display = display }
        end
    end
    local out = { at = date("%Y-%m-%d %H:%M:%S"), mounts = {} }
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.mountFrame = out
    local p = MP.panel or UI.Panel(UIParent, { title = "Mount frame probe", width = 480, height = 540, solid = true })
    MP.panel = p
    p:SetFrameStrata("DIALOG")
    p:SetPoint("CENTER")
    local m = p.model or CreateFrame("PlayerModel", nil, p.body)
    p.model = m
    m:SetSize(440, 470)
    m:SetPoint("TOP")
    local floor = p.floor or UI.Fill(p.body, "ember", "OVERLAY")
    p.floor = floor
    floor:SetHeight(1)
    floor:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 0, 0)
    floor:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    p:Show()
    -- which methods the frame has (by name)
    local names = {}
    local mt = getmetatable(m)
    local index = mt and mt.__index
    if type(index) == "table" then
        for k in pairs(index) do
            local lk = k:lower()
            if lk:find("box") or lk:find("bound") or lk:find("camera") or lk:find("position") or lk:find("scale")
                or lk:find("center") or lk:find("transform") or lk:find("project") or lk:find("inset") then
                names[#names + 1] = k
            end
        end
    end
    table.sort(names)
    out.methods = table.concat(names, " ")
    local i = 0
    local function nextMount()
        i = i + 1
        local e = list[i]
        if not e then
            ns.Print("Mount frame probe: done; /reload to save.")
            return
        end
        local done = false
        local function record(why)
            if done then return end
            done = true
            local r = { name = e.name, display = e.display, why = why }
            for _, q in ipairs(QUESTIONS) do r[q] = ask(m, q) end
            out.mounts[#out.mounts + 1] = r
            C_Timer.After(1.2, nextMount)
        end
        m:SetScript("OnModelLoaded", function() C_Timer.After(0.2, function() record("loaded") end) end)
        pcall(m.SetDisplayInfo, m, e.display)
        pcall(m.SetFacing, m, 0)
        C_Timer.After(2.5, function() record("timeout") end)
    end
    ns.Print("Mount frame probe: showing ten mounts, about 30 seconds.")
    nextMount()
end
