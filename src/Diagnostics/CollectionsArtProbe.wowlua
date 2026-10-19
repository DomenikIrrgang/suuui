-- Diagnostics/CollectionsArtProbe.lua
-- "/suu probe collart" (with Collections open): what the collections window
-- draws, for its restyle (3.6; asked 2026-10-16 after the first try showed
-- the game's stone, corners and one side tab). It records now, then for two
-- minutes each pane as you switch to it:
--   tabs   each side tab: shown, size, place, checked, enabled
--   <pane> every texture under the shown pane (and the window itself): its
--          path of keys, layer, atlas or file, size, alpha, shown
-- Saved in SuuUIProbe.collectionsArt on /reload.

local _, ns = ...

local CP = {}
ns.CollectionsArtProbe = CP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "secret" end
    return tostring(v)
end
-- a size or offset, rounded; geometry can be secret on Forever
local function num(v)
    if isSecret(v) then return "secret" end
    if type(v) ~= "number" then return tostring(v) end
    return tostring(math.floor(v + 0.5))
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.collectionsArt = SuuUIProbe.collectionsArt or {}
    return SuuUIProbe.collectionsArt
end

-- The key a child sits under in its parent (MountJournal.LeftInset), else its name.
local function keyOf(parent, child)
    if parent then
        for k, v in pairs(parent) do
            if v == child and type(k) == "string" then return k end
        end
    end
    return child:GetName() or ("<" .. child:GetObjectType() .. ">")
end

local function pointOf(r)
    local ok, p, rel, rp, x, y = pcall(r.GetPoint, r, 1)
    if not ok or not p then return "-" end
    local relName = rel and (rel.GetName and rel:GetName() or "?") or "nil"
    return ("%s>%s.%s %s,%s"):format(show(p), show(relName), show(rp), num(x), num(y))
end

local function textures(frame, path, lines, depth)
    if depth > 7 or #lines > 600 then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            -- each on its own: one that can't be read is a line saying why
            local ok, line = pcall(function()
                local atlas = r.GetAtlas and r:GetAtlas()
                local file = r:GetTexture()
                local w, h = r:GetSize()
                local layer, sub = r:GetDrawLayer()
                return ("%s.%s [%s %s] %s %sx%s a=%s %s %s"):format(path, keyOf(frame, r), show(layer), show(sub),
                    atlas and ("atlas " .. show(atlas)) or ("file " .. show(file)), num(w), num(h),
                    show(r:GetAlpha()), r:IsShown() and "shown" or "hidden", pointOf(r))
            end)
            lines[#lines + 1] = ok and line or (path .. ".? error " .. tostring(line))
        end
    end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c:IsShown() then textures(c, path .. "." .. keyOf(frame, c), lines, depth + 1) end
    end
end

local PANES = { "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame" }

function CP.Record()
    local f = _G.CollectionsJournal
    if not (f and f:IsShown()) then return end
    local o = out()
    o.at = date("%Y-%m-%d %H:%M:%S")
    local tabs = {}
    for i, t in ipairs(f.TabContainer and f.TabContainer.Tabs or {}) do
        local ok, line = pcall(function()
            local w, h = t:GetSize()
            return ("%d id=%s %s %sx%s %s checked=%s enabled=%s skinned=%s type=%s"):format(i, show(t:GetID()), t:IsShown() and "shown" or "hidden",
                num(w), num(h), pointOf(t), show(t.GetChecked and t:GetChecked()), show(t.IsEnabled and t:IsEnabled()), show(t.suuSkin ~= nil), t:GetObjectType())
        end)
        tabs[#tabs + 1] = ok and line or (i .. " error " .. tostring(line))
    end
    o.tabs = tabs
    local own = {}
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:IsShown() and (r:GetAlpha() or 0) > 0 then
            local ok, line = pcall(function() return ("%s %s %s"):format(keyOf(f, r), show(r:GetAtlas() or r:GetTexture()), pointOf(r)) end)
            own[#own + 1] = ok and line or ("error " .. tostring(line))
        end
    end
    o.window = own
    for _, name in ipairs(PANES) do
        local p = _G[name]
        if p and p:IsShown() then
            local lines = {}
            local ok, err = pcall(textures, p, name, lines, 0)
            if not ok then lines[#lines + 1] = "stopped: " .. tostring(err) end
            o[name] = lines
            ns.Print(("Collections art probe: %s, %d textures."):format(name, #lines))
        end
    end
end

function CP.Command()
    local f = _G.CollectionsJournal
    if not (f and f:IsShown()) then
        ns.Print("Collections art probe: open Collections first.")
        return
    end
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.collectionsArt = {}
    CP.Record()
    if not CP.hooked and _G.CollectionsJournal_UpdateSelectedTab then
        CP.hooked = true
        hooksecurefunc("CollectionsJournal_UpdateSelectedTab", function()
            if CP.untilTime and GetTime() < CP.untilTime then C_Timer.After(0.2, CP.Record) end
        end)
    end
    CP.untilTime = GetTime() + 120
    ns.Print("Collections art probe: recorded; click through every tab within two minutes, then /reload.")
end
