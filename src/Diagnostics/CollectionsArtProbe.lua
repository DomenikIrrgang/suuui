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
    return ("%s>%s.%s %s,%s"):format(p, tostring(relName), tostring(rp), show(x and math.floor(x + 0.5)), show(y and math.floor(y + 0.5)))
end

local function textures(frame, path, lines, depth)
    if depth > 7 or #lines > 600 then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local atlas = r.GetAtlas and r:GetAtlas()
            local file = r:GetTexture()
            local w, h = r:GetSize()
            local layer, sub = r:GetDrawLayer()
            lines[#lines + 1] = ("%s.%s [%s %s] %s %sx%s a=%.2f %s %s"):format(path, keyOf(frame, r), tostring(layer), tostring(sub),
                atlas and ("atlas " .. atlas) or ("file " .. show(file)), show(w and math.floor(w)), show(h and math.floor(h)),
                r:GetAlpha() or 0, r:IsShown() and "shown" or "hidden", pointOf(r))
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
        local w, h = t:GetSize()
        tabs[#tabs + 1] = ("%d id=%s %s %sx%s %s checked=%s enabled=%s skinned=%s"):format(i, show(t:GetID()), t:IsShown() and "shown" or "hidden",
            show(math.floor(w)), show(math.floor(h)), pointOf(t), show(t.GetChecked and t:GetChecked()), show(t:IsEnabled()), show(t.suuSkin ~= nil))
    end
    o.tabs = tabs
    local own = {}
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:IsShown() and (r:GetAlpha() or 0) > 0 then
            own[#own + 1] = ("%s %s %s"):format(keyOf(f, r), tostring(r:GetAtlas() or r:GetTexture()), pointOf(r))
        end
    end
    o.window = own
    for _, name in ipairs(PANES) do
        local p = _G[name]
        if p and p:IsShown() then
            local lines = {}
            textures(p, name, lines, 0)
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
