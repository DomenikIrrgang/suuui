-- Diagnostics/WeaponEnchantProbe.lua
-- "/suu probe weaponenchants" (asked 2026-10-19: temporary weapon enchants,
-- a shaman's imbues, poisons, stones and oils, shown nowhere by SuuUI today,
-- neither in the buff bar nor in the Cooldown Manager): what the client gives.
-- Forever's own buff frame reads them with C_Item.GetWeaponEnchantInfo(slot)
-- (Enum.WeaponSlot 0-2; a list of { hasEnchant, enchantType, timeLeft (ms),
-- charges, enchantID, enchantIconID }) on WEAPON_ENCHANT_CHANGED and
-- WEAPON_SLOT_CHANGED, and cancels with C_Spell.CancelItemTempEnchantment
-- (slot, enchantType), which has restrictions.
--   now:     both getters (the list and the old global) per weapon slot, the
--            weapon's link and icon, its tooltip's enchant lines (the green
--            "(30 min)" text) and colours; the game's buff frame and whether
--            it lists them
--   then (this session): every change with the cast just before it (the
--            imbue, poison or stone's spell: how an enchant maps to a spell),
--            the events with their timing, player auras named like the
--            enchant, samples 1 s and 5 s into each fight and after it
--   cancel:  a button that removes the main hand's enchant (says so first)
--   secure:  (2026-10-20) the same through an aura container's item-enchantment
--            button (the game's buff frame's way), right-click to cancel
-- Saved in SuuUIProbe.weaponenchants on /reload. Values the game hides read
-- SECRET.

local _, ns = ...

local WP = {}
ns.WeaponEnchantProbe = WP

local isSecret = issecretvalue or function() return false end

local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.weaponenchants = SuuUIProbe.weaponenchants or {}
    return SuuUIProbe.weaponenchants
end

local function push(list, line, cap)
    if #list < (cap or 60) then list[#list + 1] = line end
end

local t0 = GetTime()
local function stamp() return ("%.1fs"):format(GetTime() - t0) end

-- weapon slot (Enum.WeaponSlot), inventory slot
local SLOTS = {
    { name = "MainHand", ws = 0, inv = 16 },
    { name = "OffHand", ws = 1, inv = 17 },
    { name = "Ranged", ws = 2, inv = 18 },
}

local FIELDS = { "hasEnchant", "enchantType", "timeLeft", "charges", "enchantID", "enchantIconID" }

-- C_Item.GetWeaponEnchantInfo(slot): each enchant's fields, or why not
local function listInfo(ws)
    if not (C_Item and C_Item.GetWeaponEnchantInfo) then return "no C_Item.GetWeaponEnchantInfo", nil end
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
    if not ok then return "error: " .. tostring(list), nil end
    if isSecret(list) then return "SECRET (the list)", nil end
    if type(list) ~= "table" then return "returned " .. type(list), nil end
    local parts, first = {}, nil
    for i, e in pairs(list) do
        if isSecret(e) then
            parts[#parts + 1] = ("[%s] SECRET"):format(tostring(i))
        elseif type(e) == "table" then
            local f = {}
            for _, k in ipairs(FIELDS) do f[#f + 1] = k .. "=" .. show(e[k]) end
            parts[#parts + 1] = ("[%s] %s"):format(tostring(i), table.concat(f, ", "))
            if not first and not isSecret(e.hasEnchant) and e.hasEnchant then first = e end
        else
            parts[#parts + 1] = ("[%s] %s"):format(tostring(i), type(e))
        end
    end
    if #parts == 0 then return "empty list", nil end
    return table.concat(parts, " | "), first
end

-- the old global GetWeaponEnchantInfo(): all its returns
local function oldInfo()
    if type(GetWeaponEnchantInfo) ~= "function" then return "no global GetWeaponEnchantInfo" end
    local r = { pcall(GetWeaponEnchantInfo) }
    if not r[1] then return "error: " .. tostring(r[2]) end
    local parts = {}
    for i = 2, math.max(#r, 2) do parts[#parts + 1] = show(r[i]) end
    return table.concat(parts, ", ")
end

local function greenish(c)
    if type(c) ~= "table" or isSecret(c) then return false end
    local r, g, b = c.r, c.g, c.b
    if isSecret(r) or isSecret(g) or isSecret(b) then return false end
    return type(g) == "number" and g > 0.8 and (r or 1) < 0.3 and (b or 1) < 0.3
end

-- the tooltip's enchant lines: green, or with "(N min)" / "(N charges)"
local function tooltipLines(inv)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return { "no C_TooltipInfo.GetInventoryItem" } end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", inv)
    if not ok then return { "error: " .. tostring(data) } end
    if isSecret(data) then return { "SECRET (the data)" } end
    if type(data) ~= "table" or type(data.lines) ~= "table" then return { "no lines" } end
    local found = {}
    for i, l in ipairs(data.lines) do
        local text, c = l.leftText, l.leftColor
        if isSecret(text) then
            found[#found + 1] = ("line %d: SECRET"):format(i)
        elseif type(text) == "string" then
            local timed = text:find("%(%d+ [%a ]+%)") ~= nil
            if timed or greenish(c) then
                local color = "?"
                if type(c) == "table" and not isSecret(c) then
                    color = ("%s,%s,%s"):format(show(c.r), show(c.g), show(c.b))
                end
                found[#found + 1] = ("line %d: %s (colour %s%s)"):format(i, text, color, timed and ", timed" or "")
            end
        end
    end
    if #found == 0 then found[1] = ("%d lines, none green or timed"):format(#data.lines) end
    return found
end

-- "Windfury 1 (30 min)" -> "Windfury"
local function enchantName(lines)
    for _, l in ipairs(lines) do
        local text = l:match("^line %d+: (.-) %(colour")
        if text and text:find("%(%d+ [%a ]+%)") then
            local name = text:gsub("%s*%(.*%)%s*$", ""):gsub("%s+%d+$", "")
            if name ~= "" then return name end
        end
    end
end

local function blizzard()
    local b = {}
    local bf = _G.BuffFrame
    if bf then
        local shown = bf.IsShown and bf:IsShown()
        local alpha = bf.GetAlpha and bf:GetAlpha()
        local temp = 0
        if type(bf.auraInfo) == "table" then
            for _, a in pairs(bf.auraInfo) do
                if type(a) == "table" and a.auraType == "TempEnchant" then temp = temp + 1 end
            end
        end
        b.buffFrame = ("exists, shown %s, alpha %s, parent %s, TempEnchant entries in auraInfo %d"):format(show(shown),
            show(alpha), bf:GetParent() and (bf:GetParent():GetName() or "unnamed") or "none", temp)
    else
        b.buffFrame = "no BuffFrame"
    end
    local tf = _G.TemporaryEnchantFrame
    b.temporaryEnchantFrame = tf and ("exists, shown %s"):format(show(tf:IsShown())) or "no TemporaryEnchantFrame"
    if C_CVar and C_CVar.GetCVar then
        b.displayTemporaryEnchantIcon = show(C_CVar.GetCVar("displayTemporaryEnchantIcon"))
    end
    return b
end

local function api()
    local a = {}
    local function has(label, v) a[#a + 1] = label .. ": " .. type(v) end
    has("C_Item.GetWeaponEnchantInfo", C_Item and C_Item.GetWeaponEnchantInfo)
    has("GetWeaponEnchantInfo (global)", GetWeaponEnchantInfo)
    has("C_Spell.CancelItemTempEnchantment", C_Spell and C_Spell.CancelItemTempEnchantment)
    has("CancelItemTempEnchantment (global)", CancelItemTempEnchantment)
    has("C_TooltipInfo.GetInventoryItem", C_TooltipInfo and C_TooltipInfo.GetInventoryItem)
    has("Enum.WeaponSlot", Enum and Enum.WeaponSlot)
    has("Enum.ItemEnchantType", Enum and Enum.ItemEnchantType)
    return a
end

-- Everything about the weapons now.
local function snapshot(what)
    local s = { at = date("%H:%M:%S"), t = stamp(), what = what, combat = InCombatLockdown() and true or false,
                old = oldInfo(), slots = {} }
    local sig = {}
    for _, slot in ipairs(SLOTS) do
        local list, first = listInfo(slot.ws)
        local lines = tooltipLines(slot.inv)
        s.slots[slot.name] = {
            list = list,
            link = show(GetInventoryItemLink("player", slot.inv)),
            icon = show(GetInventoryItemTexture("player", slot.inv)),
            tooltip = lines,
            name = enchantName(lines),
        }
        sig[#sig + 1] = first and (show(first.enchantID) .. "/" .. show(first.enchantType)) or list
    end
    return s, table.concat(sig, ";")
end

--------------------------------------------------------------------------------
-- Listening: changes, the cast before each, events, auras, fights
--------------------------------------------------------------------------------

local casts = {}        -- the last few player casts { at, id, name, icon }
local lastSig
local knownNames = {}   -- enchant names from the tooltip
local seenAura = {}
local fights = 0

local function recentCasts(within)
    local list = {}
    for i = #casts, 1, -1 do
        local c = casts[i]
        if GetTime() - c.at <= within then
            list[#list + 1] = ("%s (spell %s, icon %s) %.1fs before"):format(c.name, c.id, c.icon, GetTime() - c.at)
        end
    end
    return #list > 0 and table.concat(list, " | ") or "none in " .. within .. " s"
end

local function checkChange(event)
    local s, sig = snapshot("after " .. event)
    if sig == lastSig then return end
    lastSig = sig
    for _, slot in pairs(s.slots) do
        if slot.name then knownNames[slot.name:lower()] = true end
    end
    s.castBefore = recentCasts(5)
    local o = out()
    o.changes = o.changes or {}
    push(o.changes, s, 30)
    local mh = s.slots.MainHand
    ns.Print(("Weapon enchant probe: a change (%s). Main hand: %s; cast before: %s."):format(event,
        mh.name or mh.list, s.castBefore))
end

local function scanAuras()
    if not next(knownNames) then return end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        local name = a.name
        if not isSecret(name) and type(name) == "string" then
            local low = name:lower()
            for n in pairs(knownNames) do
                if (low:find(n, 1, true) or n:find(low, 1, true)) and not seenAura[low] then
                    seenAura[low] = true
                    local o = out()
                    o.auras = o.auras or {}
                    push(o.auras, ("%s %s: spell %s, duration %s, expires %s (matches the enchant %q)"):format(stamp(), name,
                        show(a.spellId), show(a.duration), show(a.expirationTime), n), 20)
                end
            end
        end
    end
end

local function sample(what)
    local o = out()
    o.fights = o.fights or {}
    local s = snapshot(what)
    push(o.fights, s, 20)
end

local listening
local function listen()
    if listening then return end
    listening = CreateFrame("Frame")
    for _, e in ipairs({ "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED",
                         "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE" }) do
        pcall(listening.RegisterEvent, listening, e)
    end
    pcall(listening.RegisterUnitEvent, listening, "UNIT_INVENTORY_CHANGED", "player")
    pcall(listening.RegisterUnitEvent, listening, "UNIT_AURA", "player")
    pcall(listening.RegisterUnitEvent, listening, "UNIT_SPELLCAST_SUCCEEDED", "player")
    listening:SetScript("OnEvent", function(_, event, a, b, c)
        local o = out()
        o.events = o.events or { counts = {}, log = {} }
        o.events.counts[event] = (o.events.counts[event] or 0) + 1
        if event ~= "UNIT_AURA" then
            push(o.events.log, ("%s %s %s %s %s"):format(stamp(), event, show(a), show(b), show(c)), 150)
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local id = c
            local name = C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, id))
            local icon = C_Spell and C_Spell.GetSpellTexture and select(2, pcall(C_Spell.GetSpellTexture, id))
            casts[#casts + 1] = { at = GetTime(), id = show(id), name = show(name), icon = show(icon) }
            if #casts > 8 then table.remove(casts, 1) end
        elseif event == "WEAPON_ENCHANT_CHANGED" or event == "WEAPON_SLOT_CHANGED" or event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_EQUIPMENT_CHANGED" then
            -- a moment later as well: the enchant may land after the event
            checkChange(event)
            C_Timer.After(0.5, function() checkChange(event .. " +0.5 s") end)
        elseif event == "UNIT_AURA" then
            scanAuras()
        elseif event == "PLAYER_REGEN_DISABLED" then
            fights = fights + 1
            if fights <= 6 then
                local n = fights
                C_Timer.After(1, function() sample(("fight %d, 1 s in"):format(n)) end)
                C_Timer.After(5, function() sample(("fight %d, 5 s in"):format(n)) end)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if fights <= 6 then
                local n = fights
                C_Timer.After(0.5, function() sample(("fight %d, after it"):format(n)) end)
            end
        elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" or event == "UI_ERROR_MESSAGE" then
            o.blocked = o.blocked or {}
            push(o.blocked, ("%s %s %s %s"):format(stamp(), event, show(a), show(b)), 30)
        end
    end)
end

--------------------------------------------------------------------------------
-- Cancel: a button that removes the main hand's enchant
--------------------------------------------------------------------------------

local function cancel()
    local o = out()
    o.cancel = { armedAt = date("%H:%M:%S") }
    local b = WP.button or CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    WP.button = b
    b:SetSize(360, 30)
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    b:SetFrameStrata("DIALOG")
    b:SetText("Weapon enchant probe: remove the main hand's enchant")
    b:SetScript("OnClick", function(self)
        local r = o.cancel
        r.before = snapshot("before the cancel")
        local _, first = listInfo(0)
        local kind = first and not isSecret(first.enchantType) and first.enchantType or nil
        r.enchantType = show(kind)
        if C_Spell and C_Spell.CancelItemTempEnchantment then
            -- the enchant's own type, else Temporary (2) then Imbue (3)
            local tries = kind and { kind } or { 2, 3 }
            r.calls = {}
            for _, k in ipairs(tries) do
                local ok, err = pcall(C_Spell.CancelItemTempEnchantment, 0, k)
                r.calls[#r.calls + 1] = ("C_Spell.CancelItemTempEnchantment(0, %d): %s"):format(k,
                    ok and "ran" or ("error: " .. tostring(err)))
            end
        elseif type(CancelItemTempEnchantment) == "function" then
            local ok, err = pcall(CancelItemTempEnchantment, 1)
            r.calls = { "CancelItemTempEnchantment(1): " .. (ok and "ran" or ("error: " .. tostring(err))) }
        else
            r.calls = { "no cancel function" }
        end
        self:Hide()
        C_Timer.After(1, function()
            r.after = snapshot("1 s after the cancel")
            local mh = r.after.slots.MainHand
            ns.Print(("Weapon enchant probe: cancel %s; main hand now: %s. /reload to save it."):format(
                table.concat(r.calls, "; "), mh.list))
        end)
    end)
    b:Show()
    ns.Print("Weapon enchant probe: the button at the top of the screen REMOVES your main hand's temporary enchant (imbue, poison, stone or oil). Click it once if that's fine.")
end

--------------------------------------------------------------------------------
-- Secure: the game's own cancel (2026-10-20: the direct call is refused, and
-- the secure "cancelaura" action breaks on Forever: CANCELABLE_ITEMS is nil).
-- The game's buff frame cancels a weapon's enchant from an aura container's
-- item-enchantment button (AddItemEnchantment, SetCancelAuraButtons): one
-- such container here, with the main hand's enchant, right-click to cancel.
--------------------------------------------------------------------------------

local function secure()
    local o = out()
    local r = { armedAt = date("%H:%M:%S") }
    o.secure = r
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    r.before = snapshot("before the click")
    local function try(key, fn, ...)
        if type(fn) ~= "function" then r[key] = "missing" return end
        local ok, err = pcall(fn, ...)
        r[key] = ok and "ran" or ("error: " .. tostring(err))
        return ok, err
    end
    local c = WP.secureFrame
    if not c then
        local ok, made = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        r.container = ok and "made" or ("error: " .. tostring(made))
        if not ok then ns.Print("Weapon enchant probe: no aura container (" .. tostring(made) .. "). /reload to save it.") return end
        c = made
        WP.secureFrame = c
        c:SetSize(44, 44)
        c:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        c:SetFrameStrata("DIALOG")
        -- as the buff bar sets its containers up: a unit, a flow layout
        try("setUnit", c.SetUnit, c, "player")
        try("anchor", c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
        try("layout", c.SetItemEnchantmentLayout, c, { elementWidth = 40, elementHeight = 40 })
        local slot = AuraContainerItemEnchantmentSlot and AuraContainerItemEnchantmentSlot.MainHand or 0
        local ok2, button = pcall(c.AddItemEnchantment, c, slot, { hidePermanent = false })
        r.add = ok2 and show(button) or ("error: " .. tostring(button))
        try("enable", c.SetItemEnchantmentEnabled, c, slot, true)
        if ok2 and button then
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            try("setIcon", button.SetIcon, button, icon)
            try("setCancel", button.SetCancelAuraButtons, button, "RightButtonUp")
            local bg = c:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 0, 1, 0.25)
        end
        local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("BOTTOM", c, "TOP", 0, 6)
        label:SetText("Weapon enchant probe: right-click the icon to remove your main hand's enchant")
    end
    c:Show()
    -- what the button is a few seconds on (size, shown, its icon), and the
    -- main hand each second for a minute: the moment its enchant goes
    C_Timer.After(2, function()
        local button = c.GetItemEnchantmentFrame and select(2, pcall(c.GetItemEnchantmentFrame, c, 0))
        if type(button) == "table" and button.GetSize then
            local w, h = button:GetSize()
            r.button = ("shown %s visible %s size %s x %s"):format(show(button:IsShown()), show(button:IsVisible()), show(w), show(h))
        else
            r.button = show(button)
        end
    end)
    -- (the list holds the time left, which ticks: only whether there is one)
    local function has(snap) return (snap.slots.MainHand.list or ""):find("hasEnchant=true", 1, true) ~= nil end
    local first = has(r.before)
    local n = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        n = n + 1
        local now = snapshot("watching")
        if has(now) ~= first then
            r.after = now
            r.goneAfter = n .. " s"
            ticker:Cancel()
            ns.Print("Weapon enchant probe: your main hand's enchant changed (" .. now.slots.MainHand.list .. "). /reload to save it.")
        elseif n >= 60 then
            ticker:Cancel()
            r.after = now
            ns.Print("Weapon enchant probe: a minute passed, the enchant is still there. /reload to save it.")
        end
    end)
    ns.Print("Weapon enchant probe: right-click the icon at the top of the screen (a pink square shows where the container is); it REMOVES your main hand's temporary enchant. Watching for a minute.")
end

function WP.Command(rest)
    local o = out()
    listen()
    if InCombatLockdown() then
        o.refused = ("%s: asked in combat (%s)"):format(date("%H:%M:%S"), tostring(rest))
        ns.Print("Weapon enchant probe: not in combat; try again after the fight.")
        return
    end
    if (rest or ""):lower():match("^%s*secure") then
        secure()
        return
    end
    if (rest or ""):lower():match("^%s*cancel") then
        cancel()
        return
    end
    o.session = date("%Y-%m-%d %H:%M:%S")
    o.api = api()
    o.blizzard = blizzard()
    local s, sig = snapshot("now")
    o.now = s
    lastSig = sig
    for _, slot in pairs(s.slots) do
        if slot.name then knownNames[slot.name:lower()] = true end
    end
    scanAuras()
    local mh = s.slots.MainHand
    ns.Print(("Weapon enchant probe: recorded your weapons (main hand: %s). Now put an enchant on (an imbue, a poison, a stone or an oil), fight a few mobs, then /reload."):format(
        mh.name or mh.list))
end
