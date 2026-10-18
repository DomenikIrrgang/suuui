-- Units/DeathRecap.lua
-- SuuUI's own death recap (asked 2026-10-18, design "Death recap", option
-- A "List under a health line"): the hits that killed you, from the game's
-- recap (C_DeathRecap): the killing blow on top, a small health line falling
-- to zero across the last seconds, then every hit, oldest first, ending on
-- the killing blow in ember. It opens wherever the game opens its own (the
-- death request's Recap, a death link in chat): OpenDeathRecapUI is hooked,
-- Blizzard's frame closed again, this window shown in its place.
-- The game lists hits only: health that rises between two hits was healing.
-- An event's fields aren't documented on Forever: the ones Blizzard's own
-- recap reads (/suu probe deathrecap records what a death gives).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "deathrecap",
    name = "Death recap",
    description = "SuuUI's death recap: the hits that killed you, with your health falling to zero, from the death request's Recap.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function readable(v) return type(v) == "number" and not isSecret(v) end
local function text(v) return type(v) == "string" and not isSecret(v) and v ~= "" end

local WIDTH, HEIGHT = 440, 470
local LINE_H = 44
local ROW_H = 34
local ICON = 20
local TIME_W = 44
local HEALTH_W = 64
local AMOUNT_W = 84
local SCHOOL = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }
local ENVIRONMENT = { DROWNING = "spell_shadow_demonbreath", FALLING = "ability_rogue_quickrecovery", FIRE = "spell_fire_fire",
                      LAVA = "spell_fire_fire", SLIME = "inv_misc_slime_01", FATIGUE = "ability_creature_cursed_05" }

-- "1,956"
local function group3(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- An event's spell: its name, icon and whether it is a melee swing.
local function spellOf(e)
    local kind = text(e.event) and e.event or ""
    if kind == "SWING_DAMAGE" then
        local swing = Constants and Constants.DeathRecapConsts and Constants.DeathRecapConsts.SWING_DAMAGE_SPELL_ID
        return "Melee", swing and C_Spell.GetSpellTexture(swing) or "Interface\\Icons\\INV_Sword_04"
    end
    if kind == "ENVIRONMENTAL_DAMAGE" and text(e.environmentalType) then
        local env = e.environmentalType:upper()
        local name = _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. env] or env:lower():gsub("^%l", string.upper)
        return name, "Interface\\Icons\\" .. (ENVIRONMENT[env] or "ability_creature_cursed_05")
    end
    local icon = readable(e.spellId) and C_Spell.GetSpellTexture(e.spellId) or nil
    return text(e.spellName) and e.spellName or "Unknown", icon
end

-- What else a hit says, after its caster: absorbed, resisted, blocked.
local function extras(e)
    local out = {}
    for _, k in ipairs({ "absorbed", "resisted", "blocked" }) do
        if readable(e[k]) and e[k] > 0 then out[#out + 1] = group3(e[k]) .. " " .. k end
    end
    return out
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIDeathRecap", title = "Death recap", width = WIDTH, height = HEIGHT,
        onClose = function(win) win:Hide() end })
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    w:Hide()
    self.window = w
    local c = w.content
    local inner = WIDTH - S["space-5"] * 2

    -- the killing blow
    local head = CreateFrame("Frame", nil, c)
    head:SetPoint("TOPLEFT")
    head:SetSize(inner, T.type.caption.lineHeight + T.type.label.lineHeight + T.type.caption.lineHeight)
    head.kicker = UI.Text(head, "caption", "ink-muted")
    head.kicker:SetPoint("TOPLEFT")
    head.kicker:SetValue("Killed by")
    head.spell = UI.Text(head, "label", "ember-text")
    head.spell:SetPoint("TOPLEFT", head.kicker, "BOTTOMLEFT", 0, 0)
    head.by = UI.Text(head, "label", "ink-muted")
    head.by:SetPoint("LEFT", head.spell, "RIGHT", S["space-2"], 0)
    head.detail = UI.Text(head, "caption", "ink-muted")
    head.detail:SetPoint("TOPLEFT", head.spell, "BOTTOMLEFT", 0, 0)
    head.health = UI.Text(head, "caption", "ink")
    head.health:SetPoint("TOPRIGHT")
    head.span = UI.Text(head, "caption", "ink-muted")
    head.span:SetPoint("TOPRIGHT", head.health, "BOTTOMRIGHT", 0, 0)
    self.head = head

    -- the health line: health after each hit until the next, on a track
    local line = CreateFrame("Frame", nil, c)
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -S["space-4"])
    line:SetSize(inner, LINE_H)
    UI.Fill(line, "track"):SetAllPoints()
    UI.Border(line, "gilt-hairline")
    line.steps, line.marks, line.ticks = {}, {}, {}
    self.line = line

    self.rows = {}
    self.note = UI.Text(c, "caption", "ink-muted")
    self.note:SetFixedWidth(inner)
    self.note:SetWordWrap(true)
    self.empty = UI.Text(c, "body", "ink-muted")
    self.empty:SetPoint("TOPLEFT", 0, 0)
    self.empty:SetFixedWidth(inner)
    self.empty:SetWordWrap(true)
end

local function row(self, i)
    local r = self.rows[i]
    if r then return r end
    local c = self.window.content
    r = CreateFrame("Frame", nil, c)
    r:SetSize(WIDTH - S["space-5"] * 2, ROW_H)
    r.rule = UI.Fill(r, "gilt-faint")
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.time = UI.Text(r, "caption", "ink-muted")
    r.time:SetPoint("LEFT", 0, 0)
    r.icon = UI.Icon(r, ICON)
    r.icon:SetPoint("LEFT", TIME_W, 0)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", S["space-3"], 2)
    r.name:SetWordWrap(false)
    r.by = UI.Text(r, "caption", "ink-muted")
    r.by:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, 0)
    r.by:SetWordWrap(false)
    -- health after it: the number over a short bar
    r.hp = UI.Text(r, "numeric", "ink")
    r.hp:SetPoint("TOPRIGHT", 0, -3)
    r.hpTrack = UI.Fill(r, "track")
    r.hpTrack:SetSize(HEALTH_W - S["space-3"], 3)
    r.hpTrack:SetPoint("TOPRIGHT", r.hp, "BOTTOMRIGHT", 0, -2)
    r.hpFill = UI.Fill(r, "unit-fill", "ARTWORK")
    r.hpFill:SetHeight(3)
    r.hpFill:SetPoint("LEFT", r.hpTrack, "LEFT")
    -- the amount, and critical or overkill under it
    r.amount = UI.Text(r, "numeric", "ink")
    r.amount:SetPoint("TOPRIGHT", -HEALTH_W, -3)
    r.flag = UI.Text(r, "caption", "ink-muted")
    r.flag:SetPoint("TOPRIGHT", r.amount, "BOTTOMRIGHT", 0, 0)
    local nameW = (WIDTH - S["space-5"] * 2) - TIME_W - ICON - S["space-3"] - AMOUNT_W - HEALTH_W
    r.name:SetWidth(nameW)
    r.by:SetWidth(nameW)
    -- the spell's own tooltip; a melee swing or a fall, a short one of ours
    r:EnableMouse(true)
    r:SetScript("OnEnter", function()
        if r.spellID then return UI.SpellTooltip(r, r.spellID) end
        UI.ShowTooltip(r, { title = r.name:GetText(), subtitle = r.by:GetText() ~= "" and r.by:GetText() or nil })
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide(); UI.HideTooltip() end)
    self.rows[i] = r
    return r
end

-- Drops the health line's steps and marks before drawing it again.
local function clearLine(line)
    for _, t in ipairs(line.steps) do t:Hide() end
    for _, t in ipairs(line.marks) do t:Hide() end
end

local function piece(list, i, make)
    list[i] = list[i] or make()
    list[i]:Show()
    return list[i]
end

-- The recap of `id` (nil: your last death).
function M:ShowRecap(id)
    if not self.window then self:Build() end
    local w = self.window
    local api = C_DeathRecap
    local ok, events = pcall(api.GetRecapEvents, id)
    for _, r in ipairs(self.rows) do r:Hide() end
    clearLine(self.line)
    local secret = ok and issecrettable and issecrettable(events)
    if secret or not ok or type(events) ~= "table" or #events == 0 then
        self.head:Hide()
        self.line:Hide()
        self.note:Hide()
        self.empty:SetValue(secret and "The recap is secret until combat ends." or "No recap for this death. The game recorded no hits for it.")
        self.empty:Show()
        w.content:SetHeight(T.type.body.lineHeight * 2)
        w:Show()
        return
    end
    self.empty:Hide()
    self.head:Show()
    self.line:Show()
    local okMax, maxHP = pcall(api.GetRecapMaxHealth, id)
    if not (okMax and readable(maxHP) and maxHP > 0) then maxHP = nil end

    -- newest first: the hits oldest first, and the time each came before death
    local list, deathAt = {}, nil
    for i = #events, 1, -1 do list[#list + 1] = events[i] end
    for _, e in ipairs(list) do
        if readable(e.timestamp) and (not deathAt or e.timestamp > deathAt) then deathAt = e.timestamp end
    end
    local function before(e) return deathAt and readable(e.timestamp) and (deathAt - e.timestamp) or nil end
    local first, last = list[1], list[#list]

    -- health after each hit (probe deathrecap: currentHP is the health
    -- before it, and hits in the same moment share one reading, so a
    -- reading the same as the hit before's goes on from that hit's)
    local after, running = {}, nil
    for i, e in ipairs(list) do
        local prev = list[i - 1]
        if readable(e.currentHP) and not (prev and readable(prev.currentHP) and prev.currentHP == e.currentHP and running) then
            running = e.currentHP
        end
        if running and readable(e.amount) then running = math.max(0, running - e.amount) end
        after[i] = running
    end
    local startHP = readable(first.currentHP) and first.currentHP or maxHP

    -- the head: the killing blow, its school, critical, overkill
    local h = self.head
    local name = spellOf(last)
    h.spell:SetValue(name)
    h.by:SetValue(text(last.sourceName) and not last.hideCaster and ("· " .. last.sourceName) or "")
    local bits = {}
    if readable(last.amount) then bits[#bits + 1] = group3(last.amount) .. (SCHOOL[last.school] and (" " .. SCHOOL[last.school]) or "") end
    if last.critical == true then bits[#bits + 1] = "critical" end
    if readable(last.overkill) and last.overkill > 0 then bits[#bits + 1] = group3(last.overkill) .. " overkill" end
    h.detail:SetValue(table.concat(bits, " · "))
    local span = before(first)
    h.health:SetValue(startHP and (group3(startHP) .. " health to 0") or "")
    h.span:SetValue(("%s%d hit%s"):format(span and ("in %.1f s, "):format(span) or "", #list, #list == 1 and "" or "s"))

    -- the health line: from the first hit to death, health after each hit
    -- until the next (the start: the health before the first)
    local line = self.line
    local lineW = line:GetWidth() - 2
    local healed = 0
    if maxHP and span and span > 0 then
        local function x(t) return 1 + (1 - t / span) * lineW end
        local n = 0
        local function step(fromT, toT, hp)
            if not readable(hp) then return end
            n = n + 1
            local s = piece(line.steps, n, function() return UI.Fill(line, "unit-fill", "ARTWORK") end)
            s:SetColorTexture(UI.RGBA(hp / maxHP < 0.35 and "unit-fill-low" or "unit-fill"))
            s:ClearAllPoints()
            local left, right = x(fromT), x(toT)
            s:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", left, 1)
            s:SetSize(math.max(1, right - left), math.max(0.01, (LINE_H - 2) * math.max(0, hp) / maxHP))
            if hp <= 0 then s:Hide() end
        end
        -- before the first hit, a sliver at full
        step(span, span * 0.98, startHP or maxHP)
        for i, e in ipairs(list) do
            local t = before(e) or 0
            local nextT = list[i + 1] and before(list[i + 1]) or 0
            step(t, nextT, after[i])
            -- health that rose before the next hit: healing
            local nxt = list[i + 1]
            if nxt and after[i] and readable(nxt.currentHP) and nxt.currentHP ~= e.currentHP then
                local rise = nxt.currentHP - after[i]
                if rise > 0.5 then healed = healed + rise end
            end
        end
        -- the time marks: every two seconds back from death
        for k = 0, math.floor(span / 2) do
            local m = piece(line.marks, k + 1, function()
                local f = UI.Text(line, "caption", "ink-faint")
                return f
            end)
            m:ClearAllPoints()
            m:SetPoint("TOP", line, "BOTTOMLEFT", x(k * 2), -2)
            m:SetValue(k == 0 and "0 s" or ("−%d s"):format(k * 2))
        end
    end

    -- the hits, oldest first; the killing blow last, in ember
    local y = line:GetHeight() + S["space-6"] + h:GetHeight() + S["space-4"]
    for i, e in ipairs(list) do
        local r = row(self, i)
        local spell, icon = spellOf(e)
        local killing = i == #list
        local t = before(e)
        r.time:SetValue(t and (t < 0.05 and "0 s" or ("−%.1f s"):format(t)) or "")
        r.icon:SetArt(icon or 134400)
        r.name:SetValue(spell)
        r.spellID = readable(e.spellId) and e.spellId > 0 and e.event ~= "SWING_DAMAGE" and e.spellId or nil
        r.name:SetColor(killing and "ember-text" or "ink")
        local by = {}
        if text(e.sourceName) and not e.hideCaster then by[1] = e.sourceName end
        for _, x in ipairs(extras(e)) do by[#by + 1] = x end
        r.by:SetValue(table.concat(by, " · "))
        r.amount:SetValue(readable(e.amount) and ("−" .. group3(e.amount)) or "")
        r.amount:SetColor(killing and "ember-text" or "ink")
        local flag = {}
        if e.critical == true then flag[#flag + 1] = "critical" end
        if readable(e.overkill) and e.overkill > 0 then flag[#flag + 1] = group3(e.overkill) .. " overkill" end
        r.flag:SetValue(table.concat(flag, " · "))
        local hp = after[i]
        r.hp:SetValue(hp and group3(hp) or "")
        if hp and maxHP then
            r.hpFill:SetColorTexture(UI.RGBA(hp / maxHP < 0.35 and "unit-fill-low" or "unit-fill"))
            r.hpFill:SetWidth(math.max(0.01, (HEALTH_W - S["space-3"]) * hp / maxHP))
            r.hpFill:SetShown(hp > 0)
        else
            r.hpFill:Hide()
        end
        r.rule:SetShown(not killing)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", w.content, "TOPLEFT", 0, -y)
        r:Show()
        y = y + ROW_H
    end

    -- the note: hits only; how much was healed between them
    local note = "Hits only: health that rises between hits was healing"
    note = note .. (healed > 0 and (" (+" .. group3(healed) .. " here).") or ".")
    self.note:SetValue(note)
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", w.content, "TOPLEFT", 0, -(y + S["space-4"]))
    self.note:Show()
    w.content:SetHeight(y + S["space-4"] + T.type.caption.lineHeight * 2)
    w:Show()
end

function M:Toggle(id)
    if self.window and self.window:IsShown() and self.shownID == (id or false) then
        self.window:Hide()
        return
    end
    self.shownID = id or false
    self:ShowRecap(id)
end

function M:OnEnable()
    -- the game opens its recap through OpenDeathRecapUI (the death request's
    -- Recap, a death link in chat): this one instead
    if not self.hooked and type(OpenDeathRecapUI) == "function" then
        self.hooked = true
        hooksecurefunc("OpenDeathRecapUI", function(id)
            if not self:IsEnabled() then return end
            local f = _G.DeathRecapFrame
            if f and f:IsShown() then HideUIPanel(f) end
            self:Toggle(id)
        end)
    end
    self:RegisterCommand("recap", "Shows the recap of your last death.", function() self:Toggle(nil) end)
end
