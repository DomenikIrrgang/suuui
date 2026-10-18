-- Units/Trainer.lua
-- SuuUI's own trainer window (plan 3.6, design component TrainerWindow):
-- the game's ClassTrainerFrame stays open (it holds the conversation) but out
-- of sight, and this window shows the trainer's services from the game's
-- data: the profession's rank, Filters (Available, Unavailable, Used) and
-- Categorize, the services under their categories, money and Train. Train
-- is the game's BuyTrainerService; learning a profession asks first, as the
-- game does. Asked for in game (2026-10-16): the design, not the game's
-- layout restyled.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "trainer",
    name = "Trainer",
    description = "SuuUI's trainer window: the services under their categories, filters, the profession's rank, money and Train.",
    api = "0.16",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local WIDTH, HEIGHT = 380, 560
local ROW_H, HEAD_H = 47, 28
local TYPES = { { value = "available", label = "Available" }, { value = "unavailable", label = "Unavailable" }, { value = "used", label = "Used" } }

local function tint(token, text) return "|cff" .. T.color[token].hex .. text .. "|r" end

local function isPetTrainer()
    return C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
end
local function canCategorize() return not isPetTrainer() end

--------------------------------------------------------------------------------
-- The services
--------------------------------------------------------------------------------

-- One service as a row shows it.
local function service(i)
    local name, kind, texture, reqLevel, rankText, category = call(GetTrainerServiceInfo, i)
    if not name then return nil end
    local unit = isPetTrainer() and "pet" or "player"
    local parts = {}
    if rankText and rankText ~= "" then parts[#parts + 1] = "(" .. rankText .. ")" end
    if kind ~= "used" then
        if reqLevel and reqLevel > 1 and (UnitLevel(unit) or 0) < reqLevel then parts[#parts + 1] = "Requires level " .. reqLevel end
        local skill, rank = call(GetTrainerServiceSkillReq, i)
        if skill then parts[#parts + 1] = ("Requires %s %s"):format(skill, rank or "") end
        for k = 1, (call(GetTrainerServiceNumAbilityReq, i) or 0) do
            local ability, has = call(GetTrainerServiceAbilityReq, i, k)
            if ability and not has then parts[#parts + 1] = "Requires " .. ability end
        end
    end
    local cost, isProfession = call(GetTrainerServiceCost, i)
    return { index = i, name = name, kind = kind or "available", texture = texture, sub = table.concat(parts, " · "),
             category = category ~= "" and category or nil, cost = cost or 0, profession = isProfession }
end

-- Whether a service can be learned now, and why not.
local function learnable(e)
    if not e then return false, nil end
    if e.kind == "used" then return false, "You know this." end
    if e.kind ~= "available" then return false, e.sub ~= "" and e.sub or "You can't learn this yet." end
    if isPetTrainer() then
        local total, used = call(C_PetInfo.GetPetTrainingPoints)
        if e.cost > ((total or 0) - (used or 0)) then return false, "Your pet doesn't have the training points." end
    elseif e.cost > (GetMoney() or 0) then
        return false, "You can't afford it."
    end
    return true
end

function M:Train()
    local e = self.selected and service(self.selected)
    if not learnable(e) then return end
    if e.profession and IsTradeskillTrainer and IsTradeskillTrainer() then
        local line = call(GetTrainerServiceSkillLine, e.index) or e.name
        UI.Confirm({ title = "Learn " .. line .. "?", text = ("You'll have %s as a profession."):format(line), confirm = "Learn",
            onConfirm = function() BuyTrainerService(e.index) end })
        return
    end
    BuyTrainerService(e.index)
end

-- An amount of money as SuuUI writes it: "1g 20s 5c", each in its coin's
-- colour (the game's coin icons sat above the line in the question).
local function coins(copper)
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    local function add(n, unit, token) out[#out + 1] = ("|cff%s%d%s|r"):format(T.color[token].hex, n, unit) end
    if g > 0 then add(g, "g", "coin-gold") end
    if sv > 0 then add(sv, "s", "coin-silver") end
    if c > 0 or #out == 0 then add(c, "c", "coin-copper") end
    return table.concat(out, " ")
end

-- Your professions' names (a trainer's service names its skill line).
local function yourProfessions()
    local out = {}
    for _, index in pairs({ GetProfessions and GetProfessions() }) do
        local name = index and call(GetProfessionInfo, index)
        if name then out[name] = true end
    end
    return out
end

-- Everything you can learn now and afford together (asked 2026-10-18): the
-- cheapest first while the money lasts. Never a profession you don't have
-- yet (that one asks, one at a time); a profession trainer marks its own
-- ranks and recipes as the profession too, and those count (found in game:
-- leaving every marked one out left nothing at a profession trainer).
function M:TrainAllList()
    local list, money = {}, GetMoney() or 0
    if isPetTrainer() then
        local total, used = call(C_PetInfo.GetPetTrainingPoints)
        money = (total or 0) - (used or 0)
    end
    local mine = yourProfessions()
    for i = 1, (call(GetNumTrainerServices) or 0) do
        local e = service(i)
        if e and e.kind == "available" and learnable(e) then
            local line = e.profession and call(GetTrainerServiceSkillLine, i)
            if not e.profession or (line and mine[line]) then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return a.cost < b.cost end)
    local out, total = {}, 0
    for _, e in ipairs(list) do
        if total + e.cost <= money then
            out[#out + 1] = e
            total = total + e.cost
        end
    end
    return out, total
end

-- Learns them one at a time: the trainer's list changes after each one, so
-- the next is looked up again once it has.
function M:TrainAll()
    local steps = 0
    local function next()
        steps = steps + 1
        if steps > 60 or not (self.window and self.window:IsShown()) then return end
        local list = self:TrainAllList()
        local e = list[1]
        if not e then return end
        BuyTrainerService(e.index)
        C_Timer.After(0.35, next)
    end
    next()
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function buildHead(parent, owner)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(HEAD_H)
    h.chev = h:CreateTexture(nil, "ARTWORK")
    h.chev:SetSize(12, 12)
    h.chev:SetPoint("LEFT", S["space-2"], 0)
    h.chev:SetVertexColor(UI.RGBA("ink-muted"))
    h.name = UI.Text(h, "header", "gilt-text")
    h.name:SetPoint("LEFT", h.chev, "RIGHT", S["space-3"], 0)
    h.count = UI.Text(h, "caption", "ink-muted")
    h.count:SetPoint("LEFT", h.name, "RIGHT", S["space-3"], 0)
    h.rule = UI.Fill(h, "gilt-faint", "ARTWORK")
    h.rule:SetPoint("BOTTOMLEFT")
    h.rule:SetPoint("BOTTOMRIGHT")
    h.rule:SetHeight(1)
    h:SetScript("OnClick", function(self)
        owner.collapsed[self.category] = not owner.collapsed[self.category] or nil
        owner:Refresh()
    end)
    h:SetScript("OnEnter", function(self) self.name:SetColor("ink") end)
    h:SetScript("OnLeave", function(self) self.name:SetColor("gilt-text") end)
    return h
end

local function buildRow(parent, owner)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.sel = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.sel:SetAllPoints()
    r.hover = UI.Fill(r, "surface-raised", "BACKGROUND", 1)
    r.hover:SetAllPoints()
    r.hover:SetAlpha(0.6)
    r.hover:Hide()
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetPoint("BOTTOMLEFT", S["space-2"], 0)
    r.rule:SetPoint("BOTTOMRIGHT", -S["space-2"], 0)
    r.rule:SetHeight(1)
    r.icon = UI.Icon(r, "icon-lg")
    r.icon:SetPoint("LEFT", S["space-3"], 0)
    r.money = UI.Money(r)
    r.money:SetPoint("TOPRIGHT", -S["space-4"], -S["space-4"])
    r.tp = UI.Text(r, "caption", "ink-muted")
    r.tp:SetPoint("TOPRIGHT", r.money, "BOTTOMRIGHT", 0, -3)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", S["space-4"], 0)
    r.name:SetPoint("RIGHT", r.money, "LEFT", -S["space-4"], 0)
    r.name:SetWordWrap(false)
    r.sub = UI.Text(r, "caption", "ink-muted")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", -S["space-4"], 0)
    r.sub:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self.hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetTrainerService(self.index)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        owner.selected = self.index
        call(SelectTrainerService, self.index)
        owner:Refresh()
    end)
    r:SetScript("OnDoubleClick", function(self)
        owner.selected = self.index
        owner:Train()
    end)
    return r
end

function M:DrawRow(r, e)
    r.index = e.index
    r.icon:SetArt(e.texture)
    r.icon.art:SetDesaturated(e.kind == "unavailable")
    r.name:SetValue(e.name)
    r.sub:SetValue(e.sub)
    r.sub:SetColor(e.kind == "unavailable" and "ember-text" or "ink-muted")
    local pet = isPetTrainer()
    if e.kind ~= "used" and e.cost > 0 and not pet then
        r.money:SetCopper(e.cost)
        r.money.text:SetTextColor(UI.RGBA((GetMoney() or 0) >= e.cost and "ink" or "ember-text"))
        r.money:Show()
    else
        r.money:Hide()
    end
    r.tp:SetShown(pet and e.cost > 0)
    if pet then r.tp:SetValue(e.cost .. " TP") end
    r:SetAlpha(e.kind == "used" and T.opacity["opacity-disabled"] or 1)
    r.sel:SetShown(self.selected == e.index)
end

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUITrainerWindow", title = "Trainer", width = WIDTH, height = HEIGHT,
        footer = true, onClose = function(win) win:Hide() end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w:HookScript("OnHide", function() if self.open then call(CloseTrainer) end end)
    w.scroll:Hide()
    self.window = w
    local body = w.body
    -- the profession's rank (profession trainers)
    local rank = CreateFrame("Frame", nil, body)
    rank:SetPoint("TOPLEFT")
    rank:SetPoint("TOPRIGHT")
    rank:SetHeight(20)
    rank.label = UI.Text(rank, "label", "ink")
    rank.label:SetPoint("LEFT")
    rank.n = UI.Text(rank, "caption", "ink-muted")
    rank.n:SetPoint("RIGHT")
    rank.track = CreateFrame("Frame", nil, rank)
    rank.track:SetHeight(10)
    rank.track:SetPoint("LEFT", rank.label, "RIGHT", S["space-4"], 0)
    rank.track:SetPoint("RIGHT", rank.n, "LEFT", -S["space-4"], 0)
    UI.Fill(rank.track, "track"):SetAllPoints()
    UI.Border(rank.track, "gilt-hairline")
    rank.fill = UI.Fill(rank.track, "progress-fill", "ARTWORK")
    rank.fill:SetPoint("TOPLEFT", 1, -1)
    rank.fill:SetPoint("BOTTOMLEFT", 1, 1)
    self.rank = rank
    -- the tools: Filters, Categorize, a pet's training points
    local tools = CreateFrame("Frame", nil, body)
    tools:SetHeight(30)
    self.tools = tools
    self.filters = UI.FilterMenu(tools, {
        groups = { { key = "show", label = "Show", kind = "many", options = TYPES } },
        defaults = { show = { "available", "unavailable" } }, placeholder = "Filters", width = 130,
        onChange = function(value)
            local on = {}
            for _, v in ipairs(value.show or {}) do on[v] = true end
            for _, t in ipairs(TYPES) do call(SetTrainerServiceTypeFilter, t.value, on[t.value] and true or false) end
        end })
    self.filters:SetPoint("LEFT")
    self.categorize = UI.Checkbox(tools, { label = "Categorize", onChange = function(on)
        if C_Trainer and C_Trainer.SetCategorizeTrainerUI then C_Trainer.SetCategorizeTrainerUI(on and true or false) end
        self:Refresh()
    end })
    self.categorize:SetPoint("LEFT", self.filters, "RIGHT", S["space-5"], 0)
    self.points = UI.Text(tools, "caption", "ink-muted")
    self.points:SetPoint("RIGHT")
    -- the list
    local BAR = S["space-3"]
    self.list = UI.ScrollArea(body, BAR)
    self.list:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -S["space-4"])
    self.list:SetPoint("BOTTOMRIGHT", -(BAR + 3), 0)
    self.list:HookScript("OnSizeChanged", function(sc, width) sc.child:SetWidth(width) end)
    self.heads, self.rows, self.collapsed = {}, {}, {}
    self.empty = UI.Text(self.list.child, "body", "ink-muted")
    self.empty:SetPoint("TOPLEFT", 0, -S["space-4"])
    -- the foot: your money, Train
    self.money = UI.Money(w.footer)
    self.money:SetPoint("LEFT")
    self.train = UI.Button(w.footer, { text = "Train", variant = "primary", width = 110, onClick = function() self:Train() end })
    self.train:SetPoint("RIGHT")
    self.trainAll = UI.Button(w.footer, { text = "Train all", width = 110, onClick = self:Guard(function()
        local list, total = self:TrainAllList()
        if #list == 0 then return end
        local cost = isPetTrainer() and (total .. " training points") or coins(total)
        UI.Confirm({ title = "Train all?", text = ("Learn %d %s for %s."):format(#list, #list == 1 and "skill" or "skills", cost),
            confirm = "Train all", onConfirm = function() self:TrainAll() end })
    end) })
    self.trainAll:SetPoint("RIGHT", self.train, "LEFT", -S["space-3"], 0)
end

-- The NPC's title under its name ("Warrior Trainer"), from its tooltip.
local function npcTitle()
    local data = C_TooltipInfo and call(C_TooltipInfo.GetUnit, "npc")
    local line = data and data.lines and data.lines[2]
    local text = line and line.leftText
    if type(text) == "string" and not isSecret(text) and not text:find("^Level") then return text end
end

function M:Refresh()
    local w = self.window
    if not (w and w:IsShown() and self.open) then return end
    local name = UnitName("npc")
    w:SetTitle(type(name) == "string" and not isSecret(name) and name or "Trainer", npcTitle())
    -- the rank row
    local rank, maxRank = call(GetTrainerTradeskillRankValues)
    local hasRank = rank and rank > 0 and maxRank and maxRank > 0
    self.rank:SetShown(hasRank and true or false)
    if hasRank then
        local stepIndex = call(GetTrainerServiceStepIndex)
        self.rank.label:SetValue(call(GetTrainerServiceSkillLine, stepIndex or 1) or "Rank")
        self.rank.n:SetValue(rank .. " / " .. maxRank)
        local width = math.max(1, self.rank.track:GetWidth() - 2)
        self.rank.fill:SetWidth(math.max(1, width * math.min(1, rank / maxRank)))
    end
    self.tools:ClearAllPoints()
    self.tools:SetPoint("TOPLEFT", 0, hasRank and -(20 + S["space-4"]) or 0)
    self.tools:SetPoint("RIGHT")
    -- the tools
    local shown = {}
    for _, t in ipairs(TYPES) do if call(GetTrainerServiceTypeFilter, t.value) then shown[#shown + 1] = t.value end end
    self.filters:SetValue({ show = shown })
    local categorize = canCategorize() and C_Trainer and C_Trainer.GetCategorizeTrainerUI and C_Trainer.GetCategorizeTrainerUI()
    self.categorize:SetShown(canCategorize())
    self.categorize:SetValue(categorize and true or false)
    local pet = isPetTrainer()
    self.points:SetShown(pet)
    if pet then
        local total, used = call(C_PetInfo.GetPetTrainingPoints)
        self.points:SetValue("Training points: " .. ((total or 0) - (used or 0)))
    end
    -- the services: the profession's next rank first, then by category. The
    -- game gives a class trainer's spells none: their spellbook line instead
    -- (SuuUI's trainer data, as the spellbook groups them)
    -- (a spell the data doesn't know by name, new or renamed on Forever:
    -- by its icon, which a renamed spell keeps)
    local schoolOf, schoolOfIcon = {}, {}
    if not pet and not (IsTradeskillTrainer and IsTradeskillTrainer()) then
        for _, sp in ipairs(SuuUI.TrainerSpells and SuuUI.TrainerSpells() or {}) do
            if sp.name and sp.school then schoolOf[sp.name] = sp.school end
            if sp.icon and sp.school then schoolOfIcon[sp.icon] = schoolOfIcon[sp.icon] or sp.school end
        end
    end
    local list, groups, byName = {}, {}, {}
    local step = call(GetTrainerServiceStepIndex)
    for i = 1, (call(GetNumTrainerServices) or 0) do
        local e = service(i)
        if e then
            e.category = e.category or schoolOf[e.name] or (e.texture and schoolOfIcon[e.texture])
            if i == step then
                table.insert(list, 1, e)
            elseif categorize and e.category then
                local g = byName[e.category]
                if not g then
                    g = { name = e.category, rows = {} }
                    byName[e.category] = g
                    groups[#groups + 1] = g
                end
                g.rows[#g.rows + 1] = e
            else
                list[#list + 1] = e
            end
        end
    end
    table.sort(groups, function(a, b) return a.name < b.name end)
    -- uncategorized first (as the game does), then each category
    local c = self.list.child
    local y, nh, nr = 0, 0, 0
    local function row(e)
        nr = nr + 1
        local r = self.rows[nr] or buildRow(c, self)
        self.rows[nr] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", c, "RIGHT")
        self:DrawRow(r, e)
        r:Show()
        y = y + ROW_H
    end
    for _, e in ipairs(list) do row(e) end
    for _, g in ipairs(groups) do
        nh = nh + 1
        local h = self.heads[nh] or buildHead(c, self)
        self.heads[nh] = h
        h.category = g.name
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetPoint("RIGHT", c, "RIGHT")
        local folded = self.collapsed[g.name]
        h.chev:SetTexture("Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\" .. (folded and "chevronRight" or "chevronDown") .. ".tga")
        h.name:SetValue(g.name)
        h.count:SetValue(tostring(#g.rows))
        h:Show()
        y = y + HEAD_H
        if not folded then for _, e in ipairs(g.rows) do row(e) end end
    end
    for i = nh + 1, #self.heads do self.heads[i]:Hide() end
    for i = nr + 1, #self.rows do self.rows[i]:Hide() end
    self.empty:SetShown(nr == 0 and nh == 0)
    self.empty:SetValue("Nothing to show with these filters.")
    c:SetHeight(math.max(1, y))
    -- the foot
    self.money:SetCopper(GetMoney() or 0)
    local ok, why = learnable(self.selected and service(self.selected))
    self.train:SetEnabledState(ok and true or false)
    self.train.tooltip = (not ok) and { title = "Train", description = self.selected and why or "Choose what to learn." } or nil
    local all = self:TrainAllList()
    self.trainAll:SetEnabledState(#all > 0)
    local names = {}
    for i = 1, math.min(6, #all) do names[i] = all[i].name end
    self.trainAll.tooltip = { title = "Train all",
        description = #all > 0 and (table.concat(names, ", ") .. (#all > 6 and (" and " .. (#all - 6) .. " more") or ""))
            or "Nothing you can learn and afford right now." }
end

function M:QueueRefresh()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(0.05, function()
        self.refreshPending = nil
        self:Refresh()
    end)
end

-- The game's frame out of sight: see-through and off screen, still shown,
-- and back off screen whenever the game places it again.
function M:Away(frame)
    if not frame or self.away then return end
    self.away = true
    local placing = false
    local function away()
        if not self:IsEnabled() then return end
        placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(frame, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
    frame:HookScript("OnShow", function() C_Timer.After(0, away) end)
end

-- "/suu trainall": at an open trainer, each service and whether Train all
-- takes it, and why not (it did nothing at a blacksmithing trainer,
-- 2026-10-18).
function M:ExplainTrainAll()
    local mine = yourProfessions()
    local names = {}
    for n in pairs(mine) do names[#names + 1] = n end
    self:Print(("%d services; your professions: %s; money %s"):format(call(GetNumTrainerServices) or 0,
        table.concat(names, ", "), tostring(GetMoney())))
    for i = 1, math.min(25, call(GetNumTrainerServices) or 0) do
        local e = service(i)
        if e then
            local ok, why = learnable(e)
            local line = call(GetTrainerServiceSkillLine, i)
            self:Print(("%d %s: kind=%s cost=%s profession=%s line=%s learnable=%s %s"):format(i, tostring(e.name), tostring(e.kind),
                tostring(e.cost), tostring(e.profession), tostring(line), tostring(ok), why or ""))
        end
    end
    local list, total = self:TrainAllList()
    self:Print(("Train all would learn %d for %s."):format(#list, tostring(total)))
end

function M:OnEnable()
    self:RegisterCommand("trainall", "At a trainer: what Train all would learn, and why it leaves something out.", function()
        self:ExplainTrainAll()
    end)
    if not self.window then self:Build() end
    self:OnGameEvent("TRAINER_SHOW", function()
        self.open = true
        self.selected = nil
        C_Timer.After(0, function() self:Away(_G.ClassTrainerFrame) end)
        self.window:Show()
        self.list:SetVerticalScroll(0)
        self:Refresh()
    end)
    self:OnGameEvent("TRAINER_CLOSED", function()
        self.open = false
        self.window:Hide()
    end)
    for _, e in ipairs({ "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE", "PLAYER_MONEY", "UNIT_PET_TRAINING_POINTS",
                         "SKILL_LINES_CHANGED" }) do
        self:OnGameEvent(e, function() self:QueueRefresh() end)
    end
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
