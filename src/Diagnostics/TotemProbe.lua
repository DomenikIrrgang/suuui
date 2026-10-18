-- Diagnostics/TotemProbe.lua
-- "/suu probe totems" (on a shaman, asked 2026-10-18: a totem bar in the
-- stance bar's place, the design's TotemBar: earth, fire, water, air, each
-- slot its totem with time left and a drain, or empty). What the client
-- gives: each slot's totem (GetTotemInfo, GetTotemTimeLeft, GetTotemDuration,
-- GetTotemCannotDismiss), which of those are secret in combat (run it again
-- in a fight), how often PLAYER_TOTEM_UPDATE fires, the game's own totem
-- frames (TotemFrame, the multi-cast bar) and the stance bar's forms (Ghost
-- Wolf). "/suu probe totems destroy" tries DestroyTotem on the first slot
-- with a totem (a right click to dismiss), "check" saves what happened.
-- Saved in SuuUIProbe.totems on /reload.

local _, ns = ...

local TP = {}
ns.TotemProbe = TP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "SECRET" end
    if type(v) == "table" or type(v) == "userdata" then return type(v) end
    return tostring(v)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]):sub(1, 120) end
    local parts = {}
    for i = 2, math.max(2, #res) do parts[#parts + 1] = show(res[i]) end
    return table.concat(parts, ", ")
end

local function frameInfo(name)
    local f = _G[name]
    if not f then return "missing" end
    return ("%s shown=%s visible=%s protected=%s"):format(f:GetObjectType(), tostring(f:IsShown()), tostring(f:IsVisible()), tostring(f:IsProtected()))
end

-- The totem event, counted from the first run on.
local events = { count = 0, slots = {} }
local listener, started

local function record()
    local out = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false }
    local _, class = UnitClass("player")
    out.class, out.level = class, UnitLevel("player")
    out.numSlots = call(GetNumTotemSlots)
    out.maxTotems = tostring(MAX_TOTEMS)
    out.slotConstants = ("earth=%s fire=%s water=%s air=%s"):format(tostring(EARTH_TOTEM_SLOT), tostring(FIRE_TOTEM_SLOT),
        tostring(WATER_TOTEM_SLOT), tostring(AIR_TOTEM_SLOT))
    out.priorities = SHAMAN_TOTEM_PRIORITIES and table.concat(SHAMAN_TOTEM_PRIORITIES, ",") or "missing"
    out.slots = {}
    for slot = 1, 4 do
        local s = {}
        s.info = call(GetTotemInfo, slot)
        s.timeLeft = call(GetTotemTimeLeft, slot)
        s.cannotDismiss = call(GetTotemCannotDismiss, slot)
        local ok, d = pcall(GetTotemDuration, slot)
        s.duration = ok and (d and (type(d) .. (isSecret(d) and " SECRET" or "")) or "nil") or ("error " .. tostring(d):sub(1, 80))
        if ok and d and not isSecret(d) and (type(d) == "table" or type(d) == "userdata") then
            -- what a duration object answers (the cooldown sweep and the drain take it)
            s.durationRemaining = call(d.GetRemainingDuration, d)
            s.durationTotal = call(d.GetTotalDuration, d)
        end
        out.slots[slot] = s
    end
    out.frames = {}
    for _, name in ipairs({ "TotemFrame", "MultiCastActionBarFrame", "MultiCastSlotButton1", "MultiCastSummonSpellButton",
                            "StanceBar", "StanceButton1" }) do
        out.frames[name] = frameInfo(name)
    end
    out.hasMultiCastBar = call(HasMultiCastActionBar)
    out.multiCastActive = tostring(MultiCastActionBarFrame and MultiCastActionBarFrame.numActiveSlots)
    out.multiCastSpells = {}
    for slot = 1, 4 do
        local ok, n = pcall(function() return select("#", GetMultiCastTotemSpells(slot)) end)
        out.multiCastSpells[slot] = ok and n or "error"
    end
    out.forms = call(GetNumShapeshiftForms)
    for i = 1, 10 do
        local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, i)
        if not ok or not icon then break end
        out["form" .. i] = ("spell=%s active=%s %s"):format(show(spellID), show(active),
            spellID and not isSecret(spellID) and (C_Spell.GetSpellName(spellID) or "") or "")
    end
    out.tooltipSetTotem = GameTooltip.SetTotem and "present" or "missing"
    -- the game's slot buttons: which action slots they cast
    out.actions = {}
    for i = 1, 12 do
        local b = _G["MultiCastActionButton" .. i]
        if b then
            local ok, action = pcall(b.CalculateAction, b)
            local slot = ok and action or nil
            out.actions[i] = ("id=%s action=%s shown=%s has=%s info=%s"):format(tostring(b:GetID()), show(slot), tostring(b:IsShown()),
                slot and call(HasAction, slot) or "-", slot and call(GetActionInfo, slot) or "-")
        end
    end
    out.summonSpells = TOTEM_MULTI_CAST_SUMMON_SPELLS and table.concat(TOTEM_MULTI_CAST_SUMMON_SPELLS, ",") or "missing"
    out.recallSpells = TOTEM_MULTI_CAST_RECALL_SPELLS and table.concat(TOTEM_MULTI_CAST_RECALL_SPELLS, ",") or "missing"
    out.summonKnown = MultiCastSummonSpellButton and tostring(MultiCastSummonSpellButton.spellId) or "missing"
    out.recallKnown = MultiCastRecallSpellButton and tostring(MultiCastRecallSpellButton.spellId) or "missing"
    out.slotSpells = {}
    for slot = 1, 4 do
        local ok, list = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
        out.slotSpells[slot] = ok and table.concat(list, ",") or "error"
    end
    out.events = { count = events.count, slots = events.slots }
    return out
end

function TP.Command(rest)
    SuuUIProbe = SuuUIProbe or {}
    local all = SuuUIProbe.totems or {}
    SuuUIProbe.totems = all
    started = started or date("%H:%M:%S")
    if not listener then
        listener = CreateFrame("Frame")
        listener:RegisterEvent("PLAYER_TOTEM_UPDATE")
        listener:SetScript("OnEvent", function(_, _, slot)
            events.count = events.count + 1
            local key = tostring(isSecret(slot) and "secret" or slot)
            events.slots[key] = (events.slots[key] or 0) + 1
        end)
    end
    if rest == "buttons" then
        TP.Buttons()
        return
    end
    if rest == "choose" then
        TP.Choose(all)
        return
    end
    if rest == "destroy" then
        all.destroy = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false }
        for slot = 1, 4 do
            local ok, have = pcall(GetTotemInfo, slot)
            if ok and have and not isSecret(have) then
                all.destroy.slot = slot
                all.destroy.result = call(DestroyTotem, slot)
                break
            end
        end
        all.destroy.slot = all.destroy.slot or "no totem down"
        ns.Print("Totem probe: tried to dismiss a totem. Did it go? Then /suu probe totems check and /reload.")
        return
    end
    if rest == "check" then
        all.check = record()
        all.check.blocked = {}
        local since = started or "00:00:00"
        for _, e in ipairs(SuuUIDB and SuuUIDB.blocked or {}) do
            if e.time and e.time >= date("%Y-%m-%d ") .. since then
                all.check.blocked[#all.check.blocked + 1] = tostring(e.time) .. " " .. tostring(e.event) .. " " .. tostring(e.func)
            end
        end
        ns.Print("Totem probe: checked. /reload to save it.")
        return
    end
    local out = record()
    all[out.combat and "inCombat" or "outOfCombat"] = out
    ns.Print(("Totem probe: recorded %s (%s, %d totem events so far). Drop totems and run it again, once in a fight; /reload to save.")
        :format(out.combat and "in combat" or "out of combat", tostring(out.class), events.count))
end

-- "/suu probe totems buttons": SuuUI's own secure buttons for the game's
-- totem slots (the first page's four action slots) and the summon and recall
-- spells. Click them out of combat and in a fight: does the totem go down?
function TP.Buttons()
    if InCombatLockdown() then ns.Print("Totem probe: out of combat, to place the buttons.") return end
    local UI = ns.UI
    local p = TP.panel or UI.Panel(UIParent, { title = "Totem probe", width = 260, height = 120, solid = true })
    TP.panel = p
    p:SetFrameStrata("DIALOG")
    p:ClearAllPoints()
    p:SetPoint("LEFT", 40, 0)
    p.buttons = p.buttons or {}
    local defs = {}
    for i = 1, 4 do
        local b = _G["MultiCastActionButton" .. i]
        local ok, action = pcall(b and b.CalculateAction or function() end, b)
        if ok and action then defs[#defs + 1] = { kind = "action", value = action, label = "Slot " .. i } end
    end
    local summon = MultiCastSummonSpellButton and MultiCastSummonSpellButton.spellId
    local recall = MultiCastRecallSpellButton and MultiCastRecallSpellButton.spellId
    if summon then defs[#defs + 1] = { kind = "spell", value = summon, label = "Call" } end
    if recall then defs[#defs + 1] = { kind = "spell", value = recall, label = "Recall" } end
    for i, d in ipairs(defs) do
        local b = p.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, p.body, "SecureActionButtonTemplate")
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetSize(36, 36)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.label = UI.Text(b, "micro", "ink")
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
            p.buttons[i] = b
        end
        b:SetPoint("TOPLEFT", (i - 1) * 40, 0)
        b:SetAttribute("type", d.kind)
        b:SetAttribute(d.kind, d.value)
        b.icon:SetTexture(d.kind == "action" and GetActionTexture(d.value) or C_Spell.GetSpellTexture(d.value) or 134400)
        b.label:SetValue(d.label)
        b:Show()
    end
    p:Show()
    ns.Print(("Totem probe: %d buttons (%s). Click them, out of combat and in a fight."):format(#defs,
        #defs > 0 and "slots, then Call/Recall when known" or "the game's bar has no slots yet"))
end

-- "/suu probe totems choose": puts another totem of the same element in the
-- first slot (SetMultiCastSpell, what the game's flyout calls), then puts
-- the old one back a second later. Works out of combat? In a fight?
function TP.Choose(all)
    local b = _G.MultiCastActionButton1
    local ok, action = pcall(b and b.CalculateAction or function() end, b)
    local c = { at = date("%H:%M:%S"), combat = InCombatLockdown() and true or false }
    all.choose = c
    if not (ok and action) then c.result = "no slot action" ns.Print("Totem probe: no slot to choose for.") return end
    local _, _, before = GetActionInfo(action)
    c.action, c.before = action, tostring(before)
    -- the slot's element: the action's own totem slot from the game's button
    local slot = b.slotButton and b.slotButton:GetID()
    local spells = slot and { GetMultiCastTotemSpells(slot) } or {}
    local other
    for _, id in ipairs(spells) do if id ~= before then other = id break end end
    c.slot, c.other = tostring(slot), tostring(other)
    if not other then c.result = "only one totem known for that element" ns.Print("Totem probe: you know one totem of that element; nothing to swap to.") return end
    c.set = call(SetMultiCastSpell, action, other)
    local _, _, now = GetActionInfo(action)
    c.after = tostring(now)
    C_Timer.After(1, function()
        c.restore = call(SetMultiCastSpell, action, before)
        local _, _, back = GetActionInfo(action)
        c.restored = tostring(back)
    end)
    ns.Print("Totem probe: swapped the first slot's totem and puts it back in a second. Watch the game's bar, then /suu probe totems check and /reload.")
end
