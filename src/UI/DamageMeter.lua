-- UI/DamageMeter.lua
-- One damage meter window (design board "Damage meter"): Blizzard's own meter
-- data (C_DamageMeter) in SuuUI's look. A glass panel `meter-w` wide: a head
-- with the meter type and the fight (bare selects), the fight's time and a
-- menu; then `rows` rows `meter-row` tall, the bar being the row.
--
--   local w = UI.DamageMeter(parent, { rows = 8, onView = fn(type, session),
--       onNewWindow = fn, onClose = fn (extra windows), onReset = fn, onSettings = fn,
--       api = C_DamageMeter stand-in, recapApi = C_DeathRecap stand-in })  -- 0.10: previews
--   w:SetView(type, session)   -- "damage" … "deaths"; "current" | "overall" | a sessionID
--   w:SetOptions({ numbers, barColor, marker, nameColor, pinYou })
--   w:SetCanAddWindow(on)
--   w:SetMaxRows(n)            -- the height in rows, live
--   w:Refresh()                -- read the data again (the module drives it)
--
-- Secret values (combat): names, amounts and GUIDs are secret, the class,
-- spec icon and "is it you" are not. Rows keep the engine's order (it ranks
-- them), fills and numbers go to the engine untested (StatusBar values,
-- AbbreviateNumbers into SetText), your own name comes from UnitName. A row
-- opens its spell breakdown when its GUID is readable (yours always, through
-- UnitGUID; the others' after combat): the breakdown call refuses a secret
-- GUID. Shares need a division, so they arrive when combat ends. Deaths open
-- their recap (C_DeathRecap).

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local isSecret = issecretvalue or function() return false end
local function readable(v) return not isSecret(v) and type(v) == "number" end
local function plainString(v) return not isSecret(v) and type(v) == "string" and v ~= "" end

-- The design's types, in Blizzard's order (Absorbs left out, as Forever's menu does)
local TYPES = {
    { heading = "Damage" },
    { value = "damage", label = "Damage done", enum = "DamageDone" },
    { value = "dps", label = "DPS", enum = "Dps" },
    { value = "damageTaken", label = "Damage taken", enum = "DamageTaken" },
    { value = "avoidable", label = "Avoidable damage taken", enum = "AvoidableDamageTaken" },
    { value = "enemyDamageTaken", label = "Enemy damage taken", enum = "EnemyDamageTaken" },
    { heading = "Healing" },
    { value = "healing", label = "Healing done", enum = "HealingDone" },
    { value = "hps", label = "HPS", enum = "Hps" },
    { heading = "Actions" },
    { value = "interrupts", label = "Interrupts", enum = "Interrupts" },
    { value = "dispels", label = "Dispels", enum = "Dispels" },
    { value = "deaths", label = "Deaths", enum = "Deaths" },
}
local BY_VALUE = {}
for _, t in ipairs(TYPES) do if t.value then BY_VALUE[t.value] = t end end
local PER_SECOND = { dps = true, hps = true } -- per second leads, the total in brackets
local COUNTS = { interrupts = true, dispels = true }
local NO_PIN = { deaths = true, enemyDamageTaken = true }
local ENEMIES = { enemyDamageTaken = true }

local MAIN_W, PAREN_W, SHARE_W = 40, 48, 30
local HEAD = 32

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------

local function group3(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- 8,412 · 48.2k · 482k · 1.21M · 12.4M; a secret number through the engine.
local function abbr(v)
    if isSecret(v) then return AbbreviateNumbers(v) end
    v = tonumber(v) or 0
    local a = math.abs(v)
    if a < 10000 then return group3(math.floor(v + 0.5)) end
    if a < 1e6 then
        return (a < 1e5 and ("%.1fk"):format(v / 1e3) or ("%dk"):format(math.floor(v / 1e3 + 0.5)))
    end
    return (a < 1e7 and ("%.2fM"):format(v / 1e6) or ("%.1fM"):format(v / 1e6))
end

local function count(v)
    if isSecret(v) then return AbbreviateNumbers(v) end
    return group3(math.floor((tonumber(v) or 0) + 0.5))
end

local function clock(s)
    if not readable(s) then return "" end
    s = math.max(0, math.floor(s + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function since(s)
    if not readable(s) then return "" end
    s = math.max(0, math.floor(s + 0.5))
    local m = math.floor(s / 60)
    return m > 0 and ("%dm %ds"):format(m, s % 60) or ("%ds"):format(s)
end

-- A name without its realm; a secret one as it is.
local function shortName(name)
    if isSecret(name) then
        local ok, short = pcall(Ambiguate, name, "short")
        return ok and short or name
    end
    if type(name) ~= "string" then return "" end
    return Ambiguate and Ambiguate(name, "short") or name:match("^[^%-]+") or name
end

--------------------------------------------------------------------------------
-- Small art: the "more" dots and the back arrow
--------------------------------------------------------------------------------

local function dots(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(13, 13)
    for i = -1, 1 do
        local t = f:CreateTexture(nil, "ARTWORK")
        UI.PaintFill(t, color)
        t:SetSize(2, 2)
        t:SetPoint("CENTER", i * 4, 0)
    end
    return f
end

local function backArrow(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(13, 13)
    for _, a in ipairs({ 45, -45 }) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE)
        UI.Paint(t, color)
        t:SetSize(6, 1.5)
        t:SetRotation(math.rad(a))
        t:SetPoint("CENTER", -1, a > 0 and 2 or -2)
    end
    return f
end

-- A 24px square header button: transparent, a gilt-line edge on hover.
local function headButton(parent, art, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.edge = UI.Border(b, "gilt-line")
    b.edge:SetShown(false)
    b.hover = UI.Fill(b, "surface-raised", "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.art = art(b, "ink-muted")
    b.art:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        self.edge:SetShown(true); self.hover:Show()
        if tip then UI.ShowTooltip(self, { title = tip }) end
    end)
    b:SetScript("OnLeave", function(self)
        self.edge:SetShown(false); self.hover:Hide()
        UI.HideTooltip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

--------------------------------------------------------------------------------
-- The menu behind "more"
--------------------------------------------------------------------------------

local function buildMenu(w)
    local m = CreateFrame("Frame", nil, w)
    m:SetFrameStrata("DIALOG")
    m:SetWidth(200)
    UI.Fill(m, "surface", "BACKGROUND"):SetAllPoints()
    UI.Border(m, "gilt-line")
    UI.Shadow(m, "shadow-panel")
    m.items = {}
    m:Hide()
    m:SetScript("OnHide", function() if w.catcher then w.catcher:Hide() end end)
    w.catcher = CreateFrame("Button", nil, UIParent)
    w.catcher:SetAllPoints(UIParent)
    w.catcher:SetFrameStrata("DIALOG")
    w.catcher:SetFrameLevel(1)
    w.catcher:Hide()
    w.catcher:RegisterForClicks("AnyDown")
    w.catcher:SetScript("OnClick", function() m:Hide() end)
    m:SetFrameLevel(w.catcher:GetFrameLevel() + 5)
    return m
end

local function openMenu(w)
    local m = w.menu
    for _, it in ipairs(m.items) do it:Hide() end
    local list = {
        { label = "New window", disabled = not w.canAdd, onClick = w.opts.onNewWindow },
        { label = "Reset all fights", onClick = w.opts.onReset },
    }
    if w.opts.onClose then list[#list + 1] = { label = "Close this window", onClick = w.opts.onClose } end
    list[#list + 1] = { divider = true }
    list[#list + 1] = { label = "Settings", onClick = w.opts.onSettings }
    local y = S["space-2"]
    for i, o in ipairs(list) do
        local it = m.items[i]
        if not it then
            it = CreateFrame("Button", nil, m)
            it:SetHeight(26)
            it.hover = UI.Fill(it, "surface-raised", "BACKGROUND")
            it.hover:SetAllPoints()
            it.hover:Hide()
            it.label = UI.Text(it, "body", "ink")
            it.label:SetPoint("LEFT", S["space-4"], 0)
            it.line = it:CreateTexture(nil, "ARTWORK")
            UI.PaintFill(it.line, "gilt-faint")
            it.line:SetHeight(1)
            it.line:SetPoint("LEFT", S["space-2"], 0)
            it.line:SetPoint("RIGHT", -S["space-2"], 0)
            it:SetScript("OnEnter", function(self) if self.enabled then self.hover:Show() end end)
            it:SetScript("OnLeave", function(self) self.hover:Hide() end)
            it:SetScript("OnClick", function(self)
                if not self.enabled then return end
                m:Hide()
                if self.action then self.action() end
            end)
            m.items[i] = it
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 1, -y)
        it:SetPoint("TOPRIGHT", -1, -y)
        it.line:SetShown(o.divider and true or false)
        it.label:SetVisible(not o.divider)
        it:SetHeight(o.divider and (S["space-2"] * 2 + 1) or 26)
        it.label:SetValue(o.label or "")
        it.label:SetColor(o.disabled and "ink-faint" or "ink")
        it.enabled = not (o.divider or o.disabled)
        it.action = o.onClick
        it:Show()
        y = y + it:GetHeight()
    end
    m:SetHeight(y + S["space-2"])
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", w.more, "BOTTOMRIGHT", 0, -S["space-1"])
    w.catcher:Show()
    m:Show()
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function mix(token, share)
    local r, g, b = UI.RGBA(token)
    local sr, sg, sb = UI.RGBA("surface-sunk")
    return r * share + sr * (1 - share), g * share + sg * (1 - share), b * share + sb * (1 - share)
end

-- The bar's fill, as the row last asked for it (tex.fill: a class token,
-- "low", or nil for unit-fill), from the tokens each time (UI.Bind: again
-- after a theme change).
local function drawFill(tex)
    local r1, g1, b1, r2, g2, b2
    local kind = tex.fill
    if kind == "low" then
        r1, g1, b1 = UI.RGBA("unit-fill-low-deep")
        r2, g2, b2 = UI.RGBA("unit-fill-low")
    elseif kind then
        r2, g2, b2 = mix(kind, 0.55)
        r1, g1, b1 = r2 * 0.75, g2 * 0.75, b2 * 0.75
    else
        r1, g1, b1 = mix("unit-fill-deep", 0.7)
        r2, g2, b2 = mix("unit-fill", 0.7)
    end
    tex:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
end

local function setFill(row, kind)
    local tex = row.bar:GetStatusBarTexture()
    tex.fill = kind
    UI.Bind(tex, drawFill)
end

local function buildRow(w, i)
    local h = UI.Size("meter-row")
    local r = CreateFrame("Button", nil, w.body)
    r:SetSize(w.innerW, h)
    r:RegisterForClicks("LeftButtonUp")
    UI.Fill(r, "surface-sunk", "BACKGROUND"):SetAllPoints()
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetAllPoints()
    r.bar:SetStatusBarTexture(WHITE)
    r.bar:SetMinMaxValues(0, 1)
    setFill(r, nil)
    r.edge = UI.Border(r.bar, "gilt-hairline", { layer = "OVERLAY" })
    r.glow = UI.Shadow(r, "glow-ember")
    r.glow:SetShown(false)
    local o = CreateFrame("Frame", nil, r)
    o:SetAllPoints()
    o:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.rank = UI.Text(o, "micro", "ink")
    r.rank:SetJustifyH("RIGHT")
    r.icon = o:CreateTexture(nil, "OVERLAY")
    r.diamond = UI.Diamond(o, 5, "gilt")
    r.name = UI.Text(o, "unit-name-sm", "ink")
    r.name:SetShadowed(true)
    r.name:SetWordWrap(false)
    r.name:SetJustifyH("LEFT")
    r.sub = UI.Text(o, "caption", "ink")
    r.sub:SetShadowed(true)
    r.sub:SetWordWrap(false)
    r.sub:SetJustifyH("LEFT")
    r.share = UI.Text(o, "caption", "ink")
    r.share:SetShadowed(true)
    r.share:SetFixedWidth(SHARE_W)
    r.share:SetJustifyH("RIGHT")
    r.paren = UI.Text(o, "caption", "ink")
    r.paren:SetShadowed(true)
    r.paren:SetFixedWidth(PAREN_W)
    r.paren:SetJustifyH("RIGHT")
    r.main = UI.Text(o, "numeric", "ink")
    r.main:SetShadowed(true)
    r.main:SetFixedWidth(MAIN_W)
    r.main:SetJustifyH("RIGHT")
    r.hover = r:CreateTexture(nil, "HIGHLIGHT")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(1, 1, 1, 0.04)
    r:SetScript("OnClick", function(self) if self.open then self.open() end end)
    r:SetScript("OnEnter", function(self)
        if self.open then self.edge:SetColor("gilt") end
        if self.tip then UI.ShowTooltip(self, { description = self.tip }) end
    end)
    r:SetScript("OnLeave", function(self)
        self.edge:SetColor(self.edgeColor or "gilt-hairline")
        UI.HideTooltip()
    end)
    w.rows[i] = r
    return r
end

-- One row. d: { rank, rankWide, mark = "class"|"diamond"|"spell"|nil, class,
-- spellID, name, nameColor, sub, main, paren, share, fill, fillMax, fillLow,
-- fillClass, you, danger, plain, open, tip, heal }
local function setRow(r, d)
    local x = S["space-2"]
    r.rank:SetVisible(d.rank ~= nil)
    if d.rank ~= nil then
        r.rank:SetValue(d.rank)
        r.rank:SetColor(d.plain and "ink-muted" or "ink")
        r.rank:SetWidth(d.rankWide and 30 or 12)
        r.rank:ClearAllPoints()
        r.rank:SetPoint("LEFT", x, 0)
        x = x + (d.rankWide and 30 or 12) + S["space-3"]
    end
    r.icon:Hide()
    r.diamond:Hide()
    if d.mark == "class" and d.class then
        local atlas = GetClassAtlas and GetClassAtlas(d.class)
        if atlas then
            r.icon:SetAtlas(atlas)
        elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.class] then
            r.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[d.class]))
        end
        r.icon:SetSize(16, 16)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", x - 2, 0)
        r.icon:Show()
        x = x + 14 + S["space-3"] - S["space-1"]
    elseif d.mark == "diamond" and d.class and T.color["class-" .. d.class:lower()] then
        UI.Paint(r.diamond, "class-" .. d.class:lower())
        r.diamond:ClearAllPoints()
        r.diamond:SetPoint("CENTER", r, "LEFT", x + 3, 0)
        r.diamond:Show()
        x = x + 7 + S["space-3"] - S["space-1"]
    elseif d.mark == "spell" then
        local ok, tex = pcall(C_Spell.GetSpellTexture, d.spellID)
        r.icon:SetTexture(ok and tex or 134400)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.icon:SetSize(14, 14)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", x, 0)
        r.icon:Show()
        x = x + 14 + S["space-3"]
    end
    -- the right end (fixed widths: secret numbers can't be measured): share,
    -- paren, main, from the right edge in
    local right = nil
    local function place(t, show)
        t:SetVisible(show)
        if not show then return end
        t:ClearAllPoints()
        if right then t:SetPoint("RIGHT", right, "LEFT", -S["space-2"], 0) else t:SetPoint("RIGHT", -S["space-3"], 0) end
        right = t
    end
    place(r.share, d.share ~= nil)
    if d.share ~= nil then r.share:SetValue(d.share) end
    place(r.paren, d.paren ~= nil)
    if d.paren ~= nil then
        r.paren:SetFormattedText("(%s)", d.paren)
        r.paren.value = nil
    end
    place(r.main, d.main ~= nil)
    if d.main ~= nil then
        r.main:SetText(d.main)
        r.main.value = nil
        r.main:SetColor(d.heal and "fel" or "ink")
    end
    -- the name, then the sub line (a killing blow, a pet) filling the gap
    r.name:SetStyle(d.textName and "label" or "unit-name-sm")
    r.name:SetText(d.name or "")
    r.name.value = nil
    r.name:SetColor(d.nameColor or "ink")
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", x, 0)
    local hasSub = d.sub ~= nil and (isSecret(d.sub) or d.sub ~= "")
    if hasSub then
        r.name:SetWidth(math.floor((r:GetWidth() - x) * 0.4))
        r.sub:SetText(d.sub)
        r.sub.value = nil
        r.sub:ClearAllPoints()
        r.sub:SetPoint("LEFT", r.name, "RIGHT", S["space-3"], 0)
        if right then r.sub:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0) else r.sub:SetPoint("RIGHT", -S["space-3"], 0) end
        r.sub:Show()
    else
        r.sub:Hide()
        if right then r.name:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0) else r.name:SetPoint("RIGHT", -S["space-3"], 0) end
    end
    -- the bar
    if d.fill ~= nil then
        r.bar:SetMinMaxValues(0, d.fillMax or 1)
        r.bar:SetValue(d.fill)
        r.bar:GetStatusBarTexture():Show()
    else
        r.bar:SetMinMaxValues(0, 1)
        r.bar:SetValue(0)
    end
    setFill(r, d.fillClass and ("class-" .. d.fillClass:lower()) or d.fillLow and "low" or nil)
    r.edgeColor = d.danger and "ember" or (d.you and "ink") or "gilt-hairline"
    r.edge:SetColor(r.edgeColor)
    r.glow:SetShown(d.danger and true or false)
    r.open, r.tip = d.open, d.tip
    r:Show()
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local Meter = {}
ns.Mixins.DamageMeter = Meter

local function sessionArg(session)
    local ST = Enum.DamageMeterSessionType
    if type(session) == "number" then return nil, session end
    return session == "overall" and ST.Overall or ST.Current, nil
end

local function fetch(DM, session, typeValue)
    local t = BY_VALUE[typeValue]
    if not (DM and t and Enum.DamageMeterType) then return nil end
    local meterType = Enum.DamageMeterType[t.enum]
    local st, id = sessionArg(session)
    local ok, s
    if id then ok, s = pcall(DM.GetCombatSessionFromID, id, meterType)
    else ok, s = pcall(DM.GetCombatSessionFromType, st, meterType) end
    return ok and s or nil
end

local function fetchSource(DM, session, typeValue, guid, creatureID)
    local t = BY_VALUE[typeValue]
    local meterType = Enum.DamageMeterType[t.enum]
    local st, id = sessionArg(session)
    local ok, s
    if id then ok, s = pcall(DM.GetCombatSessionSourceFromID, id, meterType, guid, creatureID)
    else ok, s = pcall(DM.GetCombatSessionSourceFromType, st, meterType, guid, creatureID) end
    return ok and s or nil
end

local function inCombat() return InCombatLockdown() or UI.Flag(UnitAffectingCombat("player")) end

-- The fight select's options: Current (its time), Overall, the past fights
-- newest first.
function Meter:SessionOptions()
    local opts = {
        { value = "current", label = "Current", note = clock(self.api.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)) },
        { value = "overall", label = "Overall" },
    }
    local ok, list = pcall(self.api.GetAvailableCombatSessions)
    if ok and type(list) == "table" and #list > 0 then
        opts[#opts + 1] = { heading = "Past fights" }
        for i = #list, math.max(1, #list - 19), -1 do
            local s = list[i]
            local name = plainString(s.name) and s.name or "Combat"
            opts[#opts + 1] = { value = s.sessionID, label = name, note = clock(s.durationSeconds), duration = s.durationSeconds }
        end
    end
    return opts
end

function Meter:SetView(typeValue, session)
    self.type = BY_VALUE[typeValue] and typeValue or "damage"
    self.session = session or "current"
    self.drill = nil
    self.typeSelect:SetValue(self.type)
    self:Refresh()
end

function Meter:SetOptions(o)
    for k, v in pairs(o) do self.view[k] = v end
    self:Refresh()
end

function Meter:SetCanAddWindow(on) self.canAdd = on and true or false end

-- The rows the window keeps its height for (the Rows setting), live.
function Meter:SetMaxRows(n)
    self.maxRows = math.max(4, n or 8)
    local h, gap = UI.Size("meter-row"), S["space-1"]
    self:SetHeight(HEAD + 1 + S["space-3"] * 2 + self.maxRows * h + (self.maxRows - 1) * gap)
    self:Refresh()
end

-- The row data of one source in the list.
function Meter:SourceRow(src, i, top, total, fight)
    local v = self.view
    local typeValue = self.type
    local enemies, deaths = ENEMIES[typeValue], typeValue == "deaths"
    local you = not isSecret(src.isLocalPlayer) and src.isLocalPlayer == true
    local class = plainString(src.classFilename) and src.classFilename or nil
    local d = { rank = i, you = you and not enemies, plain = deaths }
    d.name = you and UnitName("player") or shortName(src.name)
    if enemies or not class then
        d.nameColor = "reaction-hostile"
    elseif v.nameColor ~= "ink" and v.barColor ~= "class" then
        d.nameColor = "class-" .. class:lower()
    end
    if not enemies then
        d.class = class
        d.mark = v.marker == "icon" and "class" or (v.marker == "diamond" and "diamond") or nil
    end
    if deaths then
        d.main = since(src.deathTimeSeconds)
        local recap = src.deathRecapID
        if readable(recap) and recap > 0 and self.recapApi then
            d.open = function() self.drill = { kind = "recap", src = src, row = d }; self:Refresh() end
        end
        return d
    end
    local ps = PER_SECOND[typeValue]
    local main = ps and src.amountPerSecond or src.totalAmount
    d.fill, d.fillMax = main, top
    d.fillClass = v.barColor == "class" and not enemies and class or nil
    if COUNTS[typeValue] then
        d.main = count(main)
    else
        d.main = abbr(main)
        if v.numbers ~= "minimal" then d.paren = abbr(ps and src.totalAmount or src.amountPerSecond) end
    end
    if v.numbers == "complete" and not fight and readable(src.totalAmount) and readable(total) and total > 0 then
        d.share = ("%d%%"):format(math.floor(src.totalAmount / total * 100 + 0.5))
    end
    -- its breakdown: yours always, others' while their GUID is readable
    local guid = you and UnitGUID("player") or src.sourceGUID
    local creature = src.sourceCreatureID
    local openable = (you or plainString(guid)) and (enemies and readable(creature) or not enemies)
    if openable then
        d.open = function()
            self.drill = { kind = "spells", guid = guid, creature = (not isSecret(creature)) and creature or nil, row = d }
            self:Refresh()
        end
    else
        d.tip = "Details of other players are secret in combat."
    end
    return d
end

function Meter:ShowEmpty(text)
    for _, r in ipairs(self.rows) do r:Hide() end
    self.pinLine:Hide()
    self.note:SetVisible(false)
    self.empty:SetValue(text)
    self.empty:SetVisible(true)
end

function Meter:RefreshList()
    local v = self.view
    local typeValue = self.type
    local s = fetch(self.api, self.session, typeValue)
    local sources = s and s.combatSources
    local deaths = typeValue == "deaths"
    if not sources or (not isSecret(sources) and #sources == 0) then
        self:ShowEmpty(typeValue == "avoidable" and "No avoidable damage taken." or deaths and "No deaths. Well played."
            or "Nothing yet. The meter fills as the fight goes on.")
        return
    end
    self.empty:SetVisible(false)
    self.note:SetVisible(false)
    local list = {}
    for i = 1, #sources do list[i] = sources[i] end
    -- deaths come newest first: in the order they happened instead
    if deaths then
        local rev = {}
        for i = #list, 1, -1 do rev[#rev + 1] = list[i] end
        list = rev
    end
    local ps = PER_SECOND[typeValue]
    local top = deaths and 1 or (ps and list[1].amountPerSecond or list[1].totalAmount)
    if readable(top) and top <= 0 then top = 1 end
    local fight = inCombat()
    local max = self.maxRows
    local youAt
    for i, src in ipairs(list) do
        if not isSecret(src.isLocalPlayer) and src.isLocalPlayer == true then youAt = i end
    end
    local pin = youAt and youAt > max and v.pinYou ~= false and not NO_PIN[typeValue]
    local h, gap = UI.Size("meter-row"), S["space-1"]
    for i = 1, max do
        local index = (pin and i == max) and youAt or i
        local src = list[index]
        local r = self.rows[i] or buildRow(self, i)
        if src then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.body, "TOPLEFT", S["space-3"], -S["space-3"] - (i - 1) * (h + gap))
            setRow(r, self:SourceRow(src, index, top, s.totalAmount, fight))
        else
            r:Hide()
        end
    end
    for i = max + 1, #self.rows do self.rows[i]:Hide() end
    self.pinLine:SetShown(pin and true or false)
    if pin then
        self.pinLine:ClearAllPoints()
        self.pinLine:SetPoint("BOTTOMLEFT", self.rows[max], "TOPLEFT", 0, gap / 2)
        self.pinLine:SetPoint("BOTTOMRIGHT", self.rows[max], "TOPRIGHT", 0, gap / 2)
    end
end

-- A source's spells.
function Meter:RefreshSpells()
    local drill = self.drill
    local typeValue = self.type
    local data = fetchSource(self.api, self.session, typeValue, drill.guid, drill.creature)
    local spells = data and data.combatSpells
    self.pinLine:Hide()
    self.note:SetVisible(false)
    if not spells or (not isSecret(spells) and #spells == 0) then
        self:ShowEmpty("No spells to show.")
        return
    end
    self.empty:SetVisible(false)
    local ps = PER_SECOND[typeValue]
    local top = ps and spells[1].amountPerSecond or spells[1].totalAmount
    if readable(top) and top <= 0 then top = 1 end
    local total = data.totalAmount
    local fight = inCombat()
    local h, gap = UI.Size("meter-row"), S["space-1"]
    for i = 1, self.maxRows do
        local sp = spells[i]
        local r = self.rows[i] or buildRow(self, i)
        if sp then
            local main = ps and sp.amountPerSecond or sp.totalAmount
            local d = { rank = i, mark = "spell", spellID = sp.spellID, textName = true, fill = main, fillMax = top }
            local okName, name = pcall(C_Spell.GetSpellName, sp.spellID)
            d.name = okName and name or "Unknown"
            if not isSecret(sp.spellID) and sp.spellID == 6603 then d.name = "Melee" end
            if plainString(sp.creatureName) then d.sub = sp.creatureName end
            if COUNTS[typeValue] then
                d.main = count(main)
            else
                d.main = abbr(main)
                if self.view.numbers ~= "minimal" then d.paren = abbr(ps and sp.totalAmount or sp.amountPerSecond) end
            end
            if self.view.numbers == "complete" and not fight and readable(sp.totalAmount) and readable(total) and total > 0 then
                d.share = ("%d%%"):format(math.floor(sp.totalAmount / total * 100 + 0.5))
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.body, "TOPLEFT", S["space-3"], -S["space-3"] - (i - 1) * (h + gap))
            setRow(r, d)
        else
            r:Hide()
        end
    end
    -- the head's total: the row's own value
    self.total:SetText(drill.row.main or "")
    self.total.value = nil
end

-- A death's last moments: oldest first, health after each hit as the bar.
function Meter:RefreshRecap()
    local src = self.drill.src
    local id = src.deathRecapID
    local ok, events = pcall(self.recapApi.GetRecapEvents, id)
    self.pinLine:Hide()
    if ok and issecrettable and issecrettable(events) then
        self:ShowEmpty("The recap is secret until combat ends.")
        return
    end
    if not ok or type(events) ~= "table" or #events == 0 then
        self:ShowEmpty("No recap for this death.")
        return
    end
    self.empty:SetVisible(false)
    local okMax, maxHP = pcall(self.recapApi.GetRecapMaxHealth, id)
    if not okMax then maxHP = nil end
    -- newest first: the last rows, oldest first
    local list = {}
    for i = #events, 1, -1 do list[#list + 1] = events[i] end
    local slots = self.maxRows - 1
    local first = math.max(1, #list - slots + 1)
    local last = list[#list]
    local deathAt = last and last.timestamp
    local h, gap = UI.Size("meter-row"), S["space-1"]
    local n = 0
    for i = first, #list do
        n = n + 1
        local ev = list[i]
        local r = self.rows[n] or buildRow(self, n)
        local kind = plainString(ev.event) and ev.event or ""
        local heal = kind == "SPELL_HEAL" or kind == "SPELL_PERIODIC_HEAL"
        -- a heal: its name and amount in the healing colour
        local d = { rankWide = true, mark = "spell", spellID = ev.spellId, textName = true, heal = heal,
                    nameColor = heal and "fel" or nil }
        if readable(deathAt) and readable(ev.timestamp) then
            local ago = deathAt - ev.timestamp
            d.rank = ago < 0.05 and "0s" or ("-%.1fs"):format(ago)
        end
        if kind == "SWING_DAMAGE" then
            d.name = "Melee"
        elseif isSecret(ev.spellName) or plainString(ev.spellName) then
            d.name = ev.spellName
        else
            d.name = "Unknown"
        end
        if readable(ev.amount) then
            d.main = (heal and "+" or "-") .. group3(math.floor(ev.amount + 0.5))
        elseif isSecret(ev.amount) then
            d.main = AbbreviateNumbers(ev.amount)
        end
        if maxHP and ev.currentHP ~= nil then
            d.fill, d.fillMax = ev.currentHP, maxHP
            if readable(ev.currentHP) and readable(maxHP) and maxHP > 0 then d.fillLow = ev.currentHP / maxHP < 0.35 end
        end
        d.danger = i == #list
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.body, "TOPLEFT", S["space-3"], -S["space-3"] - (n - 1) * (h + gap))
        setRow(r, d)
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    -- the note in the last slot: the killing blow and when
    local text = "Bars show health after each hit."
    if last and readable(last.overkill) and last.overkill > 0 then
        local by = (plainString(last.event) and last.event == "SWING_DAMAGE") and "Melee"
            or (plainString(last.spellName) and last.spellName) or "?"
        text = ("Killed by %s, %s overkill."):format(by, group3(last.overkill))
    end
    self.note:SetValue(text)
    self.note:SetVisible(true)
end

function Meter:RefreshHead()
    local drill = self.drill
    self.typeSelect:SetShown(not drill)
    self.sessionSelect:SetShown(not drill)
    self.time:SetShown(not drill)
    self.back:SetShown(drill and true or false)
    self.who:SetShown(drill and true or false)
    self.what:SetShown(drill and true or false)
    self.total:SetShown(drill and drill.kind == "spells" or false)
    if drill then
        local row = drill.row
        self.who:SetText(row.name or "")
        self.who.value = nil
        self.who:SetColor(row.nameColor or "ink")
        self.what:SetValue(drill.kind == "recap" and "Death recap" or BY_VALUE[self.type].label)
        return
    end
    -- the fight select (past fights change) and the time
    local opts = self:SessionOptions()
    -- only when the fights changed: this runs every second in combat, and
    -- rebuilding an open list dropped the hover on its rows
    local sig = {}
    for _, o in ipairs(opts) do sig[#sig + 1] = tostring(o.value) .. "=" .. tostring(o.label) end
    sig = table.concat(sig, "|")
    local list = self.sessionSelect.list
    if sig ~= self.sessionSig or not (list and list:IsShown()) then
        self.sessionSig = sig
        self.sessionSelect:SetOptions(opts)
        self.sessionSelect:SetValue(self.session)
    end
    local time = ""
    if self.session == "current" then
        time = opts[1].note or ""
    elseif type(self.session) == "number" then
        for _, o in ipairs(opts) do if o.value == self.session then time = o.note or "" end end
    end
    self.time:SetValue(time)
end

function Meter:Refresh()
    if not self.api then return end
    -- a past fight that's gone: back to Current
    if type(self.session) == "number" then
        local found = false
        local ok, list = pcall(self.api.GetAvailableCombatSessions)
        if ok and type(list) == "table" then
            for _, s in ipairs(list) do if s.sessionID == self.session then found = true end end
        end
        if not found then self.session = "current" end
    end
    self:RefreshHead()
    if self.drill and self.drill.kind == "spells" then
        self:RefreshSpells()
    elseif self.drill and self.drill.kind == "recap" then
        self:RefreshRecap()
    else
        self:RefreshList()
    end
end

function UI.DamageMeter(parent, opts)
    opts = opts or {}
    local w = CreateFrame("Frame", nil, parent)
    Mixin(w, Meter)
    w.opts = opts
    w.api, w.recapApi = opts.api or C_DamageMeter, opts.recapApi or C_DeathRecap
    w.view = { numbers = "compact", barColor = "neutral", marker = "icon", nameColor = "class", pinYou = true }
    w.maxRows = math.max(4, opts.rows or 8)
    w.type, w.session = "damage", "current"
    local width = UI.Size("meter-w")
    local h, gap = UI.Size("meter-row"), S["space-1"]
    local bodyH = S["space-3"] * 2 + w.maxRows * h + (w.maxRows - 1) * gap
    w:SetSize(width, HEAD + 1 + bodyH)
    w.innerW = width - S["space-3"] * 2
    UI.Fill(w, "surface-glass", "BACKGROUND"):SetAllPoints()
    UI.Border(w, "gilt-line")
    UI.Shadow(w, "shadow-panel")
    -- head
    local head = CreateFrame("Frame", nil, w)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD)
    w.head = head
    w.typeSelect = UI.Select(head, { bare = true, width = math.floor(width * 0.55), textStyle = "header", textColor = "gilt-text",
        options = TYPES, value = "damage", minListWidth = 220, maxRows = 14, search = false,
        onChange = function(v)
            w.type = v
            w.drill = nil
            w:Refresh()
            if opts.onView then opts.onView(w.type, w.session) end
        end })
    w.typeSelect:SetPoint("LEFT", S["space-2"], 0)
    w.sessionSelect = UI.Select(head, { bare = true, width = 96, textStyle = "caption", textColor = "ink",
        options = {}, value = "current", minListWidth = 220, maxRows = 12, search = false,
        onChange = function(v)
            w.session = v
            w.drill = nil
            w:Refresh()
            if opts.onView then opts.onView(w.type, w.session) end
        end })
    w.sessionSelect:SetPoint("LEFT", w.typeSelect, "RIGHT", 0, 0)
    w.menu = buildMenu(w)
    w.more = headButton(head, dots, function() if w.menu:IsShown() then w.menu:Hide() else openMenu(w) end end, "Meter options")
    w.more:SetPoint("RIGHT", -S["space-2"], 0)
    w.time = UI.Text(head, "numeric", "ink-muted")
    w.time:SetPoint("RIGHT", w.more, "LEFT", -S["space-2"], 0)
    -- the drill head: back, who, what, total
    w.back = headButton(head, backArrow, function() w.drill = nil; w:Refresh() end, "Back")
    w.back:SetPoint("LEFT", S["space-2"], 0)
    w.who = UI.Text(head, "unit-name-sm", "ink")
    w.who:SetShadowed(true)
    w.who:SetPoint("LEFT", w.back, "RIGHT", S["space-2"], 0)
    w.who:SetWidth(90)
    w.who:SetWordWrap(false)
    w.who:SetJustifyH("LEFT")
    w.what = UI.Text(head, "caption", "ink-muted")
    w.what:SetPoint("LEFT", w.who, "RIGHT", S["space-2"], 0)
    w.total = UI.Text(head, "numeric", "ink")
    w.total:SetFixedWidth(MAIN_W + 10)
    w.total:SetJustifyH("RIGHT")
    w.total:SetPoint("RIGHT", -S["space-3"], 0)
    local rule = w:CreateTexture(nil, "BORDER")
    UI.PaintFill(rule, "gilt-faint")
    rule:SetPoint("TOPLEFT", 1, -HEAD)
    rule:SetPoint("TOPRIGHT", -1, -HEAD)
    rule:SetHeight(1)
    -- body
    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", 0, -HEAD - 1)
    w.body:SetPoint("BOTTOMRIGHT")
    w.rows = {}
    w.pinLine = w.body:CreateTexture(nil, "ARTWORK")
    UI.PaintFill(w.pinLine, "gilt-line")
    w.pinLine:SetHeight(1)
    w.pinLine:Hide()
    w.note = UI.Text(w.body, "caption", "ink-muted")
    w.note:SetPoint("BOTTOMLEFT", S["space-3"], S["space-3"])
    w.note:SetPoint("BOTTOMRIGHT", -S["space-3"], S["space-3"])
    w.note:SetJustifyH("LEFT")
    w.note:SetWordWrap(false)
    w.note:SetVisible(false)
    w.empty = UI.Text(w.body, "caption", "ink-muted")
    w.empty:SetPoint("LEFT", S["space-5"], 0)
    w.empty:SetPoint("RIGHT", -S["space-5"], 0)
    w.empty:SetJustifyH("CENTER")
    w.empty:SetWordWrap(true)
    w.empty:SetVisible(false)
    w:SetScript("OnHide", function() w.menu:Hide() end)
    ns.Extend.Add("meter", w, { meter = "damage" })
    return w
end

UI.DAMAGE_METER_TYPES = TYPES
