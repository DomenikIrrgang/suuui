-- Diagnostics/NpcPortraitProbe.lua
-- "/suu probe npcportrait": can SuuUI's NPC dialogue show the person you
-- talk to as a live 3D portrait (asked 2026-10-17: gossip more like an RPG
-- dialogue)? While the probe is on, each NPC you talk to (gossip or a quest
-- dialog) shows in a panel: a PlayerModel set to the "npc" unit, head and
-- shoulders (portrait zoom) or the whole body, and its talk and idle
-- animations. It records what the model and unit say (the model file,
-- whether it has the talk animations, the NPC's title line from its
-- tooltip). Screenshots show how each NPC frames. Saved in
-- SuuUIProbe.npcPortrait on /reload.

local _, ns = ...

local NP = {}
ns.NpcPortraitProbe = NP

local UI = ns.UI

-- the game's animation IDs: stand, talk, exclamation, question, bow, point
local ANIMS = { { 0, "Idle" }, { 60, "Talk" }, { 64, "Exclaim" }, { 65, "Question" }, { 66, "Bow" }, { 84, "Point" } }

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 100) end
    local parts = {}
    for i = 2, math.max(2, #res) do parts[#parts + 1] = tostring(res[i]) end
    return table.concat(parts, ", ")
end

function NP.Command()
    SuuUIProbe = SuuUIProbe or {}
    local out = { at = date("%Y-%m-%d %H:%M:%S"), npcs = {} }
    SuuUIProbe.npcPortrait = out
    local p = NP.panel or UI.Panel(UIParent, { title = "NPC portrait", width = 420, height = 520, solid = true })
    NP.panel = p
    p:SetFrameStrata("DIALOG")
    p:ClearAllPoints()
    p:SetPoint("LEFT", 40, 0)
    local m = p.model or CreateFrame("PlayerModel", nil, p.body)
    p.model = m
    m:SetSize(380, 380)
    m:SetPoint("TOP")
    local label = p.label or UI.Text(p.body, "caption", "ink")
    p.label = label
    label:SetPoint("TOP", m, "BOTTOM", 0, -6)
    label:SetWidth(380)
    local entry
    local function show(zoom)
        p.zoom = zoom
        call(m.SetPortraitZoom, m, zoom)
        if entry then entry["zoom " .. zoom] = "shown" end
    end
    local function talkTo(event)
        if not UnitExists("npc") then return end
        local e = { event = event, name = UnitName("npc"), at = date("%H:%M:%S") }
        entry = e
        out.npcs[#out.npcs + 1] = e
        m:SetScript("OnModelLoaded", function()
            e.file = call(m.GetModelFileID, m)
            e.display = call(m.GetDisplayInfo, m)
            for _, a in ipairs(ANIMS) do e["has " .. a[2]] = call(m.HasAnimation, m, a[1]) end
            show(p.zoom or 1)
            call(m.SetAnimation, m, 60)
        end)
        e.setUnit = call(m.SetUnit, m, "npc")
        -- the title line under the name (Innkeeper, Warrior Trainer)
        local info = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit("npc")
        local lines = {}
        for i, line in ipairs(info and info.lines or {}) do
            if i <= 4 then lines[#lines + 1] = tostring(line.leftText) end
        end
        e.tooltip = table.concat(lines, " / ")
        e.reaction = call(UnitReaction, "npc", "player")
        e.creature = call(UnitCreatureType, "npc")
        label:SetValue(("%s (%s): %s"):format(tostring(e.name), event, e.tooltip))
        p:Show()
    end
    if not p.buttons then
        p.buttons = true
        local prev
        for _, a in ipairs(ANIMS) do
            local b = UI.Button(p.body, { text = a[2], width = 60, onClick = function()
                if entry then entry["played " .. a[2]] = call(m.SetAnimation, m, a[1]) end
            end })
            b:SetPoint("BOTTOMLEFT", prev or p.body, prev and "BOTTOMRIGHT" or "BOTTOMLEFT", prev and 4 or 0, 0)
            prev = b
        end
        local head = UI.Button(p.body, { text = "Head", width = 90, onClick = function() show(1) end })
        head:SetPoint("BOTTOMLEFT", p.body, "BOTTOMLEFT", 0, 30)
        local half = UI.Button(p.body, { text = "Half", width = 90, onClick = function() show(0.6) end })
        half:SetPoint("LEFT", head, "RIGHT", 4, 0)
        local body = UI.Button(p.body, { text = "Body", width = 90, onClick = function() show(0) end })
        body:SetPoint("LEFT", half, "RIGHT", 4, 0)
        local ev = CreateFrame("Frame", nil, p)
        for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
            ev:RegisterEvent(e)
        end
        ev:SetScript("OnEvent", function(_, event) talkTo(event) end)
    end
    p:Show()
    talkTo("now")
    ns.Print("NPC portrait: talk to a few NPCs (a trainer, a vendor, a quest giver, one tall or small)."
        .. " For each, try Head, Half and Body and the animations; screenshots, then /reload.")
end
