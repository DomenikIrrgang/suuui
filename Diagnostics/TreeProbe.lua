-- Diagnostics/TreeProbe.lua
-- "/suu probe tree <name|preset> [depth]": a Blizzard window taken apart for
-- reskinning (Phase 3): every child frame and region a few levels deep, with
-- its key, type, size, anchor, shown state, protection, its texture or atlas,
-- its text and font. Saved in SuuUIProbe.trees[name] on /reload (each run
-- replaces that name's entry).
--
--   /suu probe tree CharacterFrame 4   one frame by global name, or a path
--                                      (PaperDollFrame.EquipmentManagerPane)
--   /suu probe tree open               every window on screen now
--   /suu probe tree character          the Character window and its panes
--                                      (run it on each tab: a pane's rows
--                                      exist once it has been shown)

local _, ns = ...

local TP = {}
ns.TreeProbe = TP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "number" then return (v == math.floor(v)) and tostring(v) or ("%.1f"):format(v) end
    return tostring(v)
end

local PRESETS = {
    character = { "CharacterFrame", "PaperDollFrame", "PaperDollItemsFrame", "CharacterStatsPane", "PaperDollSidebarTabs",
                  "CharacterModelScene", "ReputationFrame", "SkillsFrame", "PVPRankFrame", "TokenFrame", "StatisticsFrame" },
}

local function ask(f, method, ...)
    if type(f[method]) ~= "function" then return nil end
    local res = { pcall(f[method], f, ...) }
    if res[1] then return unpack(res, 2) end
end

-- The key a parent holds this widget under ("CloseButton"), if any.
local function keyOf(f)
    local parent = ask(f, "GetParent")
    if parent then
        for k, v in pairs(parent) do
            if v == f and type(k) == "string" then return k end
        end
    end
end

local function anchor(f)
    local p, rel, rp, x, y = ask(f, "GetPoint", 1)
    if not p then return "-" end
    local relName = rel and (ask(rel, "GetName") or keyOf(rel) or "?") or "nil"
    return ("%s>%s.%s(%s,%s)"):format(show(p), show(relName), show(rp), show(x), show(y))
end

local function describe(f)
    local t = ask(f, "GetObjectType") or "?"
    local w, h = ask(f, "GetSize")
    local parts = { t, (ask(f, "GetName") or keyOf(f) or "-"), ("%sx%s"):format(show(w), show(h)), "shown=" .. show(ask(f, "IsShown")) }
    if ask(f, "IsProtected") then parts[#parts + 1] = "PROTECTED" end
    parts[#parts + 1] = "at " .. anchor(f)
    if t == "Texture" or t == "MaskTexture" then
        local atlas = ask(f, "GetAtlas")
        parts[#parts + 1] = atlas and ("atlas=" .. atlas) or ("tex=" .. show(ask(f, "GetTexture")))
        local layer, sub = ask(f, "GetDrawLayer")
        parts[#parts + 1] = "layer=" .. show(layer) .. ":" .. show(sub)
        local r, g, b, a = ask(f, "GetVertexColor")
        if r then parts[#parts + 1] = ("rgba=%s,%s,%s,%s"):format(show(r), show(g), show(b), show(a)) end
    elseif t == "FontString" then
        local text = ask(f, "GetText")
        parts[#parts + 1] = "text=" .. (isSecret(text) and "secret" or show(text):sub(1, 40))
        local file, size = ask(f, "GetFont")
        parts[#parts + 1] = "font=" .. show(file and file:match("[^\\/]+$")) .. " " .. show(size)
        local fo = ask(f, "GetFontObject")
        if fo then parts[#parts + 1] = "object=" .. show(ask(fo, "GetName")) end
    else
        local scripts = {}
        for _, s in ipairs({ "OnClick", "OnEnter", "OnShow" }) do
            if ask(f, "HasScript", s) and ask(f, "GetScript", s) then scripts[#scripts + 1] = s end
        end
        if #scripts > 0 then parts[#parts + 1] = "scripts=" .. table.concat(scripts, ",") end
        parts[#parts + 1] = "level=" .. show(ask(f, "GetFrameLevel"))
    end
    return table.concat(parts, " ")
end

-- Lines, indented by depth: the frame, its regions, then its children.
local function walk(f, depth, maxDepth, out, seen)
    if #out > 1500 or seen[f] then return end
    seen[f] = true
    out[#out + 1] = string.rep("  ", depth) .. describe(f)
    if depth >= maxDepth then return end
    for _, r in ipairs({ ask(f, "GetRegions") }) do
        if #out > 1500 then return end
        out[#out + 1] = string.rep("  ", depth + 1) .. "· " .. describe(r)
    end
    for _, c in ipairs({ ask(f, "GetChildren") }) do
        if not ask(c, "IsForbidden") then walk(c, depth + 1, maxDepth, out, seen) end
    end
end

function TP.Command(arg)
    local name, depth = (arg or ""):match("^(%S+)%s*(%d*)")
    if not name then
        ns.Print("Tree probe: /suu probe tree <frame name or preset> [depth]; presets: character")
        return
    end
    depth = tonumber(depth) or 4
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.trees = SuuUIProbe.trees or {}
    local names = PRESETS[name:lower()] or { name }
    -- "open": every named window on screen now (a top-level frame at least
    -- 300 by 250, not SuuUI's)
    if name:lower() == "open" then
        names = {}
        for _, c in ipairs({ UIParent:GetChildren() }) do
            local ok, n = pcall(function()
                if c:IsForbidden() or not c:IsVisible() then return nil end
                local fname = c:GetName()
                local w, h = c:GetSize()
                if fname and not fname:find("^SuuUI") and w >= 300 and h >= 250 then return fname end
            end)
            if ok and n then names[#names + 1] = n end
        end
        SuuUIProbe.trees = SuuUIProbe.trees or {}
        SuuUIProbe.trees._open = { date("%H:%M:%S") .. " " .. table.concat(names, ", ") }
    end
    local done = {}
    for _, n in ipairs(names) do
        -- a global name, or a path through keys ("PaperDollFrame.EquipmentManagerPane")
        local f = _G
        for part in n:gmatch("[^%.]+") do f = type(f) == "table" and f[part] or nil end
        if type(f) == "table" and f.GetObjectType then
            local out = { "at " .. date("%H:%M:%S") }
            walk(f, 0, depth, out, {})
            SuuUIProbe.trees[n] = out
            done[#done + 1] = ("%s (%d lines)"):format(n, #out - 1)
        else
            SuuUIProbe.trees[n] = { "missing" }
        end
    end
    ns.Print("Tree probe: " .. (#done > 0 and table.concat(done, ", ") or "nothing found") .. ". /reload to save.")
end
