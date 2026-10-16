-- Diagnostics/MountFrameProbe.lua
-- "/suu probe mountframe": where a mount's feet are in SuuUI's collections
-- stage (2026-10-17: the game centres each mount in its model frame by its
-- whole size, so some stand on the floor shadow and some float). It shows
-- ten mounts one after another in a model frame the stage's size and
-- records, once each has loaded, what the frame can say about it: which of
-- its methods there are (once), its box, camera, scale and position. The
-- panel shows each one for a screenshot. Saved in SuuUIProbe.mountFrame on
-- /reload.
--
-- "/suu probe mountframe place": the placement test. The same frame, a red
-- line 165px under its middle (where the stage wants every mount's feet),
-- and each mount moved by the game's own SetPosition (not the camera: the
-- camera route zoomed in and misplaced them) by what its camera says:
-- Next and Previous step through the mounts, each line says the numbers.
-- Screenshots show whether the feet meet the line.

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

-- how far below the frame's middle the model's origin shows (the stage's
-- formula, calibrated on a Swift Stormsaber: 165px in a 440 by 470 frame)
local FEET_K, W, WANT = 2.739, 440, 165
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function norm(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l == 0 then return nil end
    return { x / l, y / l, z / l }
end
local function feetBelow(P, T, lift)
    local f = norm(T[1] - P[1], T[2] - P[2], T[3] - P[3])
    if not f then return nil end
    local right = norm(f[2], -f[1], 0)
    if not right then return nil end
    local u = { right[2] * f[3] - right[3] * f[2], right[3] * f[1] - right[1] * f[3], right[1] * f[2] - right[2] * f[1] }
    if u[3] < 0 then u = { -u[1], -u[2], -u[3] } end
    local r = { -P[1], -P[2], lift - P[3] }
    local depth = dot(r, f)
    if depth <= 0 then return nil end
    return -FEET_K * W * dot(r, u) / depth
end

function MP.Place()
    local MJ = C_MountJournal
    local list = {}
    for _, id in ipairs(MJ.GetMountIDs() or {}) do
        local name, _, _, _, _, _, _, _, _, hidden = MJ.GetMountInfoByID(id)
        if name and not hidden then list[#list + 1] = { name = name, display = (MJ.GetMountInfoExtraByID(id)) } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local out = { at = date("%Y-%m-%d %H:%M:%S"), lines = {} }
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.mountPlace = out
    local p = MP.placePanel or UI.Panel(UIParent, { title = "Mount placement probe", width = 480, height = 600, solid = true })
    MP.placePanel = p
    p:SetFrameStrata("DIALOG")
    p:SetPoint("CENTER")
    local m = p.model or CreateFrame("PlayerModel", nil, p.body)
    p.model = m
    m:SetSize(440, 470)
    m:SetPoint("TOP")
    local line = p.line or UI.Fill(p.body, "ember", "OVERLAY")
    p.line = line
    line:SetHeight(1)
    line:SetPoint("LEFT", m, "CENTER", -220, -WANT)
    line:SetPoint("RIGHT", m, "CENTER", 220, -WANT)
    local label = p.label or UI.Text(p.body, "caption", "ink")
    p.label = label
    label:SetPoint("TOP", m, "BOTTOM", 0, -6)
    label:SetWidth(440)
    local i = 0
    local function show(step)
        i = (i + step - 1) % #list + 1
        local e = list[i]
        pcall(m.SetPosition, m, 0, 0, 0)
        m:SetScript("OnModelLoaded", function()
            C_Timer.After(0.1, function()
                local px, py, pz = m:GetCameraPosition()
                local tx, ty, tz = m:GetCameraTarget()
                local P, T = { px, py, pz }, { tx, ty, tz }
                local before = feetBelow(P, T, 0)
                -- the lift that brings the feet to the line (bisection)
                local lo, hi = -3, 3
                for _ = 1, 40 do
                    local mid = (lo + hi) / 2
                    local b = feetBelow(P, T, mid)
                    if not b then break end
                    if b > WANT then lo = mid else hi = mid end
                end
                local lift = (lo + hi) / 2
                pcall(m.SetPosition, m, 0, 0, lift)
                local text = ("%s: feet %.0f below the middle, lifted %.3f -> %.0f; position now %s"):format(e.name, before or -1,
                    lift, feetBelow(P, T, lift) or -1, tostring(select(3, m:GetPosition())))
                label:SetValue(text)
                out.lines[#out.lines + 1] = text
            end)
        end)
        pcall(m.SetDisplayInfo, m, e.display)
        pcall(m.SetFacing, m, 0.5)
    end
    if not p.next then
        p.prev = UI.Button(p.body, { text = "Previous", width = 110, onClick = function() show(-1) end })
        p.prev:SetPoint("BOTTOMLEFT")
        p.next = UI.Button(p.body, { text = "Next", width = 110, onClick = function() show(1) end })
        p.next:SetPoint("BOTTOMRIGHT")
    end
    p:Show()
    show(1)
    ns.Print("Mount placement probe: Next and Previous step through the mounts; the red line is where the feet should be.")
end

function MP.Command(rest)
    if rest == "place" then return MP.Place() end
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
