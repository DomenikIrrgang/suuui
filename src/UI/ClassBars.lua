-- UI/ClassBars.lua
-- The stance/form bar and the pet bar: rows of action-sm (18px) buttons drawn
-- like ActionButton, fed from the shapeshift and pet action APIs instead of
-- action slots.
--
--   local stance = UI.StanceBar(parent, { name = "SuuUIStanceBar" })
--   local pet = UI.PetBar(parent, { name = "SuuUIPetBar" })
--   bar:SetHotkeysShown(on); bar:SetEnabled(on); bar.header
--
-- Stance buttons cast their form by name; the row holds as many buttons as
-- you have forms (relaid out of combat when you learn one). The pet bar shows
-- itself while you have a pet and no vehicle (a secure state driver, so it
-- works in combat), and in keybind mode; right click toggles autocast
-- (/petautocasttoggle), shown as a dashed ink ring. Keys bound to the game's stance and pet commands
-- click these buttons. Anything secure waits for the end of combat.

local _, ns = ...

local UI, T, Combat, Events = ns.UI, ns.Tokens, ns.Combat, ns.Events
local S = T.space

local SLOTS = 10
local isSecret = issecretvalue or function() return false end

local function known(v, fallback)
    if isSecret(v) or v == nil then return fallback end
    return v
end

local CB = {}

function CB:SetHotkeysShown(shown)
    self.hotkeysShown = shown and true or false
    for _, b in ipairs(self.buttons) do b:SetHotkeyShown(self.hotkeysShown) end
end

function CB:UpdateBindings()
    Combat.Run("classbar:bind:" .. self.name, function()
        ClearOverrideBindings(self.header)
        for i, b in ipairs(self.buttons) do
            local keys = { GetBindingKey(self.binding .. i) }
            if self.enabled then
                for _, key in ipairs(keys) do
                    SetOverrideBindingClick(self.header, false, key, b:GetName(), "LeftButton")
                end
            end
            b:SetHotkey(UI.ShortKey(keys[1]))
        end
    end, "Action bars")
end

-- The buttons' size (follows the dock's). Out of combat.
function CB:SetButtonSize(px)
    self.size = px
    self:Layout(self.count or SLOTS)
end

-- One row, buttons space-1 apart; `count` of them shown.
function CB:Layout(count)
    Combat.Run("classbar:layout:" .. self.name, function()
        local px, gap = self.size or self.buttons[1]:GetWidth(), S["space-1"]
        for i, b in ipairs(self.buttons) do
            b:Resize(px)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", (i - 1) * (px + gap), 0)
            b:SetShown(i <= count)
        end
        local n = math.max(count, 1)
        self.header:SetSize(n * px + (n - 1) * gap, px)
        self.count = count
        if self.onLayout then self.onLayout(self) end
    end, "Action bars")
end

function CB:UpdateAll()
    for _, b in ipairs(self.buttons) do b:Update() end
end

-- Empty slots: with the setting, or while you drag something that fits.
function CB:SetShowEmpty(shown)
    for _, b in ipairs(self.buttons) do
        b.showEmpty = shown and true or false
        b:UpdateEmpty()
    end
end

local function makeBar(parent, opts, binding)
    local bar = setmetatable({}, { __index = CB })
    bar.name, bar.binding, bar.enabled = opts.name, binding, true
    bar.onLayout = opts.onLayout
    bar.header = CreateFrame("Frame", opts.name, parent, "SecureHandlerStateTemplate")
    bar.header:SetSize(1, 1)
    bar.buttons = {}
    for i = 1, SLOTS do
        local b = UI.ActionButton(bar.header, opts.name .. "Button" .. i, "action-sm")
        b.index = i
        b.bindCommand = binding .. i
        b.bindLabel = (opts.label or opts.name) .. " button " .. i
        b:SetID(0)
        b:RegisterForClicks("AnyUp", "AnyDown")
        bar.buttons[i] = b
    end
    return bar
end

--------------------------------------------------------------------------------
-- Stance / form bar
--------------------------------------------------------------------------------

local function stanceUpdate(b)
    local icon, active, castable, spellID = GetShapeshiftFormInfo(b.index)
    b.hasAction = icon ~= nil
    b.spellID = spellID
    if b.hasAction then
        b.art:SetTexture(icon)
        b.art:Show()
        b:ShowSpellCooldown(spellID)
        b:ShowUsable(not known(castable, true))
        b:ShowActive(UI.Flag(active))
    else
        b.art:Hide()
        b.cooldown:Clear()
        b:ShowActive(false)
        b:ShowUsable(false)
    end
    b.count:SetText("")
    b:UpdateHotkey()
    b:UpdateEmpty()
end

local function stanceTooltip(b)
    GameTooltip:SetShapeshift(b.index)
end

local Stance = setmetatable({}, { __index = CB })

-- Which spell each button casts, and how many buttons: out of combat.
function Stance:UpdateForms()
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    Combat.Run("classbar:forms:" .. self.name, function()
        for i, b in ipairs(self.buttons) do
            local spellID = i <= n and select(4, GetShapeshiftFormInfo(i))
            local name = spellID and C_Spell.GetSpellName(spellID)
            b:SetAttribute("type", name and "spell" or nil)
            b:SetAttribute("spell", name)
        end
        self.header:SetShown(self.enabled and n > 0)
    end, "Action bars")
    self:Layout(n)
    self:UpdateAll()
end

function Stance:SetEnabled(on)
    self.enabled = on and true or false
    self:UpdateForms()
    self:UpdateBindings()
end

function UI.StanceBar(parent, opts)
    local bar = makeBar(parent, opts, "SHAPESHIFTBUTTON")
    setmetatable(bar, { __index = Stance })
    for _, b in ipairs(bar.buttons) do
        b.Update = stanceUpdate
        b.ShowTooltip = stanceTooltip
    end
    local function forms() bar:UpdateForms() end
    local function all() bar:UpdateAll() end
    Events.OnGame("UPDATE_SHAPESHIFT_FORMS", forms, bar)
    Events.OnGame("PLAYER_ENTERING_WORLD", forms, bar)
    Events.OnGame("SPELLS_CHANGED", forms, bar)
    for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN",
                         "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN" }) do
        Events.OnGame(e, all, bar)
    end
    Events.OnGame("UPDATE_BINDINGS", function() bar:UpdateBindings() end, bar)
    bar:UpdateForms()
    bar:UpdateBindings()
    return bar
end

--------------------------------------------------------------------------------
-- Pet bar
--------------------------------------------------------------------------------

local function petUpdate(b)
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID, checksRange, inRange = GetPetActionInfo(b.index)
    b.hasAction = name ~= nil
    b.petName, b.autoCastAllowed = name, autoCastAllowed
    if b.hasAction then
        b.art:SetTexture(isToken and _G[texture] or texture)
        b.art:Show()
        if spellID then
            b:ShowSpellCooldown(spellID)
        else
            local start, duration = GetPetActionCooldown(b.index)
            local live = not isSecret(duration) and not isSecret(start) and duration and duration > 0
            if live then
                b.petDuration = b.petDuration or C_DurationUtil.CreateDuration()
                b.petDuration:SetTimeFromStart(start, duration)
            end
            b:ShowCooldown(live and true or false, false, live and b.petDuration or nil)
        end
        b:ShowUsable(GetPetActionSlotUsable and not known(GetPetActionSlotUsable(b.index), true) or false)
        b:ShowActive(UI.Flag(isActive))
        b:ShowAutocast(UI.Flag(autoCastEnabled))
        b:SetOutOfRange(UI.Flag(checksRange) and not known(inRange, true))
    else
        b.art:Hide()
        b.cooldown:Clear()
        b:ShowActive(false)
        b:ShowAutocast(false)
        b:ShowUsable(false)
        b:SetOutOfRange(false)
    end
    b.count:SetText("")
    b:UpdateHotkey()
    b:UpdateEmpty()
end

local function petTooltip(b)
    GameTooltip:SetPetAction(b.index)
end

local Pet = setmetatable({}, { __index = CB })

-- Right click toggles autocast where the ability allows it. Out of combat.
function Pet:UpdateAutocastClicks()
    Combat.Run("classbar:autocast:" .. self.name, function()
        for _, b in ipairs(self.buttons) do
            local allowed = b.petName and UI.Flag(b.autoCastAllowed)
            b:SetAttribute("type2", allowed and "macro" or "pet")
            b:SetAttribute("macrotext2", allowed and ("/petautocasttoggle " .. b.petName) or nil)
        end
    end, "Action bars")
end

local PET_VISIBILITY = "[@pet,exists,nopossessbar,novehicleui] show; hide"

-- Shown by its state driver; keybind mode shows it even without a pet, so
-- its keys can be bound (the driver comes back when the mode ends). Out of
-- combat.
function Pet:UpdateShown()
    Combat.Run("classbar:shown:" .. self.name, function()
        local binding = ns.KeybindMode and ns.KeybindMode.IsActive()
        UnregisterStateDriver(self.header, "visibility")
        if not self.enabled then
            self.header:Hide()
        elseif binding then
            self.header:Show()
        else
            RegisterStateDriver(self.header, "visibility", PET_VISIBILITY)
        end
    end, "Action bars")
end

function Pet:SetEnabled(on)
    self.enabled = on and true or false
    self:UpdateShown()
    self:UpdateBindings()
end

local PET_DRAG = [[
    if self:GetAttribute("suu-locked") and not IsModifiedClick("PICKUPACTION") then return false end
    return "petaction", self:GetAttribute("action")
]]
local PET_RECEIVE = [[ return "petaction", self:GetAttribute("action") ]]

function UI.PetBar(parent, opts)
    local bar = makeBar(parent, opts, "BONUSACTIONBUTTON")
    setmetatable(bar, { __index = Pet })
    for i, b in ipairs(bar.buttons) do
        b.Update = petUpdate
        b.ShowTooltip = petTooltip
        b:SetAttribute("type", "pet")
        b:SetAttribute("action", i)
        b:RegisterForDrag("LeftButton")
        SecureHandlerWrapScript(b, "OnDragStart", bar.header, PET_DRAG)
        SecureHandlerWrapScript(b, "OnReceiveDrag", bar.header, PET_RECEIVE)
    end
    bar:Layout(SLOTS)
    local function lock()
        Combat.Run("classbar:lock:" .. bar.name, function()
            local locked = GetCVarBool("lockActionBars") and true or false
            for _, b in ipairs(bar.buttons) do b:SetAttribute("suu-locked", locked) end
        end, "Action bars")
    end
    lock()
    Events.OnGame("CVAR_UPDATE", lock, bar)
    -- A pet ability on the cursor shows the empty slots it can go to.
    Events.OnGame("CURSOR_CHANGED", function()
        local on = GetCursorInfo() == "petaction"
        for _, b in ipairs(bar.buttons) do b:SetGrid(on) end
    end, bar)

    local function all()
        bar:UpdateAll()
        bar:UpdateAutocastClicks()
    end
    for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
                         "PLAYER_FARSIGHT_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD", "PET_BAR_UPDATE_USABLE" }) do
        Events.OnGame(e, all, bar)
    end
    Events.OnGame("PET_BAR_UPDATE_COOLDOWN", function() bar:UpdateAll() end, bar)
    Events.OnUnit("UNIT_PET", "player", all, bar)
    Events.OnUnit("UNIT_FLAGS", "pet", all, bar)
    Events.OnUnit("UNIT_AURA", "pet", all, bar)
    Events.OnGame("UPDATE_BINDINGS", function() bar:UpdateBindings() end, bar)
    Events.On("SUUUI_KEYBINDMODE_CHANGED", function() bar:UpdateShown() end, bar)
    bar:SetEnabled(true)
    all()
    return bar
end

--------------------------------------------------------------------------------
-- Totem bar (1.6d; the design's "Totem bar options", direction B)
--------------------------------------------------------------------------------
-- A shaman's totems in the stance bar's place: the four elements (earth,
-- fire, water, air) as action-sm buttons that cast the totem the game's own
-- totem bar holds for each, a thin strip above them with each totem's time
-- left and its drain, and after a hairline Call of the Elements and Totemic
-- Recall once learned (Recall faint while no totem is down; asked
-- 2026-10-18: its own button at the right end). An element with no totem
-- yet is dashed with its glyph. Probed 2026-10-18:
--   * left click: the game's slot action (132 + slot on page 1), cast by a
--     secure "action" button, in combat too; right click: "destroytotem"
--   * the strip runs from GetTotemDuration's duration object (in combat the
--     totem's values are secret, but the object comes, nil when empty):
--     the drain through SetTimerDuration, the time through a text binding
--   * sets (asked 2026-10-18): Call of the Elements, of the Ancestors and of
--     the Spirits each drop their own four (the game's pages 1-3: slot
--     actions 132 + (page - 1) * 4 + slot); the arrow under the Call button
--     lists the sets you know, out of combat, and the four buttons, their
--     lists and the Call button follow the chosen one
--   * choosing a slot's totem: secure "multispell" buttons in a list over
--     the slot, opened by the arrow that shows under it on hover (out of
--     combat)
--   * the slots' actions have no texture: the icon is the spell's
-- The game has no key bindings for its totem buttons on this client.
--
--   local totems = UI.TotemBar(parent, { name = "SuuUITotemBar", page = 1, onPage = fn(page) })
--   totems:SetButtonSize(px); totems:SetEnabled(on); totems:SetPage(page); totems.header

local GLYPH = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STRIP_H = 12
local EXPIRE = 3

local ELEMENTS = {
    { slot = EARTH_TOTEM_SLOT or 2, glyph = "rock", word = "Earth" },
    { slot = FIRE_TOTEM_SLOT or 1, glyph = "sun", word = "Fire" },
    { slot = WATER_TOTEM_SLOT or 3, glyph = "drop", word = "Water" },
    { slot = AIR_TOTEM_SLOT or 4, glyph = "wave", word = "Air" },
}
local RECALL = (TOTEM_MULTI_CAST_RECALL_SPELLS and TOTEM_MULTI_CAST_RECALL_SPELLS[1]) or 36936
-- the summon spells, one per set: Call of the Elements, Ancestors, Spirits
local SUMMONS = TOTEM_MULTI_CAST_SUMMON_SPELLS or { 66842, 66843, 66844 }

local DIR = Enum.StatusBarTimerDirection or {}
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local function knows(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, yes = pcall(C_SpellBook.IsSpellInSpellBook, spellID, Enum.SpellBookSpellBank.Player, false)
        if ok then return yes and true or false end
    end
    return IsPlayerSpell and IsPlayerSpell(spellID) or false
end

-- The totems you know for an element (the game's list for its slot).
local function elementSpells(slot)
    local ok, list = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
    return ok and list or {}
end

-- The game's action for an element's slot in a set (its bar's page).
local function slotAction(slot, page)
    return 132 + ((page or 1) - 1) * 4 + slot
end

-- The spell an element's slot holds in a set (readable in combat too).
local function slotSpell(slot, page)
    local kind, id = GetActionInfo(slotAction(slot, page))
    if kind == "spell" and id and not isSecret(id) then return id end
end

local Totems = setmetatable({}, { __index = CB })

-- The empty look (dashes, the faint glyph) while the slot holds nothing; by
-- alpha, so it changes in combat too.
local function showEmpty(b)
    local on = not b.hasAction
    b.empty:SetAlpha(on and 1 or 0)
    for _, t in ipairs(b.dashes or {}) do
        UI.PaintFill(t, "gilt-faint")
        t:SetAlpha(on and 1 or 0)
    end
end

local function totemUpdate(b)
    local spellID = slotSpell(b.element.slot, b.bar.page)
    b.spellID = spellID
    b.hasAction = spellID ~= nil
    b.known = #elementSpells(b.element.slot) > 0
    if spellID then
        b.art:SetTexture(C_Spell.GetSpellTexture(spellID))
        b.art:Show()
        b:ShowSpellCooldown(spellID)
        local usable, noMana = C_Spell.IsSpellUsable(spellID)
        b:ShowUsable(not (known(usable, true) and not known(noMana, false)))
    else
        b.art:Hide()
        b.cooldown:Clear()
        b:ShowUsable(false)
    end
    showEmpty(b)
    b:ShowActive(b.picking and true or false)
    b.count:SetText("")
    b:UpdateHotkey()
    b:UpdateEmpty()
end

local function totemTooltip(b)
    if b.spellID then GameTooltip:SetSpellByID(b.spellID) end
    if b.known then
        GameTooltip:AddLine("Right click: dismiss it. The arrow: choose another.", UI.RGBA("ink-muted"))
    end
end

-- An element's empty look: dashed, its glyph faint (the design's).
local function emptyLook(b, element)
    local e = CreateFrame("Frame", nil, b.face)
    e:SetAllPoints()
    UI.Fill(e, "surface-sunk", "BACKGROUND", 1):SetAllPoints()
    e.glyph = e:CreateTexture(nil, "ARTWORK")
    e.glyph:SetTexture(GLYPH .. element.glyph .. ".tga")
    UI.Paint(e.glyph, "ink-faint")
    e.glyph:SetPoint("CENTER")
    b.empty = e
    -- the dashes: the pet bar's autocast ring, in gilt-faint (showEmpty)
    b:ShowAutocast(true)
end

-- The strip over an element: its time and drain while its totem is down.
local function stripSegment(bar, b)
    local s = CreateFrame("Frame", nil, bar.header)
    s:SetHeight(STRIP_H)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("BOTTOMLEFT")
    s.track:SetPoint("BOTTOMRIGHT")
    s.track:SetHeight(2)
    UI.PaintFill(s.track, "track")
    s.drain = CreateFrame("StatusBar", nil, s)
    s.drain:SetPoint("BOTTOMLEFT")
    s.drain:SetPoint("BOTTOMRIGHT")
    s.drain:SetHeight(2)
    s.drain:SetStatusBarTexture(WHITE)
    UI.Paint(s.drain, "ink")
    s.drain:SetMinMaxValues(0, 1)
    s.drain:Hide()
    s.text = s:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(s.text, "micro")
    s.text:SetShadowColor(0, 0, 0, 1)
    s.text:SetShadowOffset(0, -1)
    s.text:SetPoint("TOP", 0, 0)
    s.text:SetJustifyH("CENTER")
    s.binding = UI.DurationTextBinding(s.text, EXPIRE)
    b.segment = s
    return s
end

-- Whether the totem down in a slot is the one its button casts (asked
-- 2026-10-18: a totem chosen in its place hides the old one's time). Out of
-- combat the slot's spell answers (GetTotemInfo, by ID or by name: a rank
-- may differ); in combat it is secret, so the answer is kept, and a totem
-- that goes down just after its button or Call was clicked is the chosen one.
local function totemIsChosen(b)
    local slot = b.element.slot
    local ok, have, _, _, _, _, _, spellID = pcall(GetTotemInfo, slot)
    if not ok or isSecret(have) or isSecret(spellID) then
        if b.castAt and GetTime() - b.castAt < 1 then b.chosen = true end
        return b.chosen ~= false
    end
    b.castAt = nil
    if not have then
        b.chosen = nil
        return true
    end
    local chosen = slotSpell(slot, b.bar.page)
    b.chosen = not chosen or spellID == chosen
        or (C_Spell.GetSpellName(spellID) or 1) == (C_Spell.GetSpellName(chosen) or 2)
    return b.chosen
end

-- Every element's time and drain (only for the totem its button casts), and
-- Recall faint while nothing is down. The duration object comes in combat
-- too (its values secret); none: empty.
function Totems:UpdateTimers()
    local any = false
    for _, b in ipairs(self.buttons) do
        local s = b.segment
        local ok, d = pcall(GetTotemDuration, b.element.slot)
        if ok and d then any = true end
        if ok and d and totemIsChosen(b) then
            pcall(s.drain.SetTimerDuration, s.drain, d, IMMEDIATE, DIR.RemainingTime)
            s.drain:Show()
            if s.binding then
                pcall(s.binding.SetDuration, s.binding, d)
                pcall(s.binding.SetEnabled, s.binding, true)
            end
            s.text:Show()
        else
            s.drain:Hide()
            if s.binding then pcall(s.binding.SetEnabled, s.binding, false) end
            s.text:SetText("")
            s.text:Hide()
        end
    end
    -- Recall: faint while no totem is down (an alpha: in combat too)
    if self.recall then self.recall:ShowUsable(not any) end
end

-- Which totem each button casts and what the bar holds: out of combat.
function Totems:Refresh()
    Combat.Run("classbar:totems:" .. self.name, function()
        local anyKnown = false
        -- the set: the chosen one while you know its summon spell, else the first
        if self.page ~= 1 and not knows(SUMMONS[self.page]) then self.page = 1 end
        for _, b in ipairs(self.buttons) do
            local slot = b.element.slot
            b:SetAttribute("type1", "action")
            b:SetAttribute("action", slotAction(slot, self.page))
            b:SetAttribute("type2", "destroytotem")
            b:SetAttribute("totem-slot", slot)
            if #elementSpells(slot) > 0 then anyKnown = true end
        end
        local summon = SUMMONS[self.page]
        self.hasCall = knows(summon)
        self.knownSets = 0
        for _, id in ipairs(SUMMONS) do if knows(id) then self.knownSets = self.knownSets + 1 end end
        self.call:SetAttribute("type", self.hasCall and "spell" or nil)
        self.call:SetAttribute("spell", self.hasCall and summon or nil)
        self.call.spellID = self.hasCall and summon or nil
        self.hasRecall = knows(RECALL)
        self.recall:SetAttribute("type", self.hasRecall and "spell" or nil)
        self.recall:SetAttribute("spell", self.hasRecall and RECALL or nil)
        self.header:SetShown(self.enabled and anyKnown)
        self.anyKnown = anyKnown
        self:Layout()
    end, "Action bars")
    self:UpdateAll()
end

function Totems:UpdateAll()
    for _, b in ipairs(self.buttons) do b:Update() end
    local c = self.call
    if c.spellID then
        c.hasAction = true
        c.art:SetTexture(C_Spell.GetSpellTexture(c.spellID))
        c.art:Show()
        c:ShowSpellCooldown(c.spellID)
    else
        c.hasAction = false
    end
    c:UpdateEmpty()
    local r = self.recall
    r.hasAction = self.hasRecall and true or false
    if r.hasAction then
        r.art:SetTexture(C_Spell.GetSpellTexture(RECALL))
        r.art:Show()
        r:ShowSpellCooldown(RECALL)
    end
    r:UpdateEmpty()
    self:UpdateTimers()
end

-- The row and the strip over it (Call of the Elements after a hairline),
-- Call and Recall after a hairline.
function Totems:Layout()
    Combat.Run("classbar:totemlayout:" .. self.name, function()
        local px, gap = self.size or 18, S["space-2"]
        local rowY = 0
        local stripY = px + S["space-1"]
        for i, b in ipairs(self.buttons) do
            b:Resize(px)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", (i - 1) * (px + gap), rowY)
            b.empty.glyph:SetSize(math.floor(px * 0.55), math.floor(px * 0.55))
            -- Resize draws the dashes again at a new size (in ink): gilt-faint
            showEmpty(b)
            local s = b.segment
            s:ClearAllPoints()
            s:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", (i - 1) * (px + gap), stripY)
            s:SetWidth(px)
        end
        local rowEnd = #self.buttons * (px + gap) - gap
        self.rule:ClearAllPoints()
        self.rule:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", rowEnd + 2, math.floor((px - 12) / 2))
        self.rule:SetShown(self.hasCall or self.hasRecall)
        -- after the hairline: Call, then Recall, each only once learned
        local x = rowEnd + 5
        for _, extra in ipairs({ { self.call, self.hasCall }, { self.recall, self.hasRecall } }) do
            local b, shown = extra[1], extra[2] and true or false
            b:Resize(px)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self.header, "BOTTOMLEFT", x, rowY)
            b:SetShown(shown)
            if shown then x = x + px + gap end
        end
        local width = (self.hasCall or self.hasRecall) and (x - gap) or rowEnd
        self.header:SetSize(width, stripY + STRIP_H)
        if self.onLayout then self.onLayout(self) end
    end, "Action bars")
end

function Totems:SetButtonSize(px)
    self.size = px
    self:Layout()
end

function Totems:SetEnabled(on)
    self.enabled = on and true or false
    self:Refresh()
end

-- The list of an element's totems, over its slot: one secure "multispell"
-- row each (the game's own way of choosing), the chosen one ticked. Out of
-- combat only: it closes when a fight starts.
function Totems:OpenPicker(b)
    if InCombatLockdown() then return end
    local p = self.picker
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetFrameStrata("DIALOG")
        p:SetSize(136, 40)
        UI.Fill(p, "surface-glass", "BACKGROUND"):SetAllPoints()
        UI.Border(p, "gilt-line")
        p.title = UI.Text(p, "micro", "gilt-text")
        p.title:SetPoint("TOPLEFT", 8, -6)
        p.rows = {}
        -- a click anywhere else closes it
        p.catcher = CreateFrame("Button", nil, UIParent)
        p.catcher:SetFrameStrata("DIALOG")
        p.catcher:SetAllPoints(UIParent)
        p.catcher:RegisterForClicks("AnyUp")
        p.catcher:SetScript("OnClick", function() self:ClosePicker() end)
        p.catcher:Hide()
        p:SetFrameLevel(p.catcher:GetFrameLevel() + 5)
        p:Hide()
        self.picker = p
    end
    local slot = b.element.slot
    local chosen = slotSpell(slot, self.page)
    local spells = elementSpells(slot)
    p.title:SetValue((b.element.word .. " totems"):upper())
    local y = -6 - 12 - 4
    for i, id in ipairs(spells) do
        local r = p.rows[i]
        if not r then
            r = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")
            r:RegisterForClicks("AnyUp", "AnyDown")
            r:SetHeight(20)
            r.hover = UI.Fill(r, "surface-raised", "BACKGROUND")
            r.hover:SetAllPoints()
            r.hover:Hide()
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(14, 14)
            r.icon:SetPoint("LEFT", 4, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.label = UI.Text(r, "caption", "ink")
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.check = r:CreateTexture(nil, "ARTWORK")
            r.check:SetTexture(GLYPH .. "check.tga")
            UI.Paint(r.check, "gilt-text")
            r.check:SetSize(10, 10)
            r.check:SetPoint("RIGHT", -6, 0)
            r:SetScript("OnEnter", function(row) row.hover:Show() end)
            r:SetScript("OnLeave", function(row) row.hover:Hide() end)
            r:HookScript("PostClick", function()
                C_Timer.After(0, function() self:ClosePicker(); self:UpdateAll() end)
            end)
            p.rows[i] = r
        end
        r:SetAttribute("type", "multispell")
        r:SetAttribute("action", slotAction(slot, self.page))
        r:SetAttribute("spell", id)
        r.icon:SetTexture(C_Spell.GetSpellTexture(id))
        r.label:SetValue(C_Spell.GetSpellName(id) or "")
        r.check:SetShown(id == chosen)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, y)
        r:SetPoint("TOPRIGHT", -4, y)
        r:Show()
        y = y - 21
    end
    for i = #spells + 1, #p.rows do p.rows[i]:Hide() end
    p:SetHeight(-y + 4)
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, STRIP_H + S["space-1"] + 6)
    for _, other in ipairs(self.buttons) do other.picking = other == b end
    p.catcher:Show()
    p:Show()
    self:UpdateAll()
end

function Totems:ClosePicker()
    local p = self.picker
    if not p or InCombatLockdown() then return end
    p:Hide()
    p.catcher:Hide()
    for _, b in ipairs(self.buttons) do b.picking = false end
    self:UpdateAll()
end

-- The set the bar works on (1-3: Call of the Elements, Ancestors,
-- Spirits). Out of combat.
function Totems:SetPage(page)
    if InCombatLockdown() then return end
    self.page = page
    if self.onPage then self.onPage(page) end
    self:Refresh()
end

-- The list of your sets over the Call button: each summon spell you know,
-- its four chosen totems after it, the one in use ticked. Out of combat.
function Totems:OpenSets()
    if InCombatLockdown() then return end
    local p = self.sets
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetFrameStrata("DIALOG")
        UI.Fill(p, "surface-glass", "BACKGROUND"):SetAllPoints()
        UI.Border(p, "gilt-line")
        p.title = UI.Text(p, "micro", "gilt-text")
        p.title:SetPoint("TOPLEFT", 8, -6)
        p.title:SetValue("TOTEM SETS")
        p.rows = {}
        p.catcher = CreateFrame("Button", nil, UIParent)
        p.catcher:SetFrameStrata("DIALOG")
        p.catcher:SetAllPoints(UIParent)
        p.catcher:RegisterForClicks("AnyUp")
        p.catcher:SetScript("OnClick", function() p:Hide(); p.catcher:Hide() end)
        p.catcher:Hide()
        p:SetFrameLevel(p.catcher:GetFrameLevel() + 5)
        p:Hide()
        self.sets = p
    end
    local y, n = -6 - 12 - 4, 0
    for page, id in ipairs(SUMMONS) do
        if knows(id) then
            n = n + 1
            local r = p.rows[n]
            if not r then
                r = CreateFrame("Button", nil, p)
                r:SetHeight(22)
                r.hover = UI.Fill(r, "surface-raised", "BACKGROUND")
                r.hover:SetAllPoints()
                r.hover:Hide()
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(16, 16)
                r.icon:SetPoint("LEFT", 4, 0)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.label = UI.Text(r, "caption", "ink")
                r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.totems = {}
                for k = 1, 4 do
                    local t = r:CreateTexture(nil, "ARTWORK")
                    t:SetSize(12, 12)
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    r.totems[k] = t
                end
                r.check = r:CreateTexture(nil, "ARTWORK")
                r.check:SetTexture(GLYPH .. "check.tga")
                UI.Paint(r.check, "gilt-text")
                r.check:SetSize(10, 10)
                r.check:SetPoint("RIGHT", -6, 0)
                r:SetScript("OnEnter", function(row) row.hover:Show() end)
                r:SetScript("OnLeave", function(row) row.hover:Hide() end)
                r:SetScript("OnClick", function(row)
                    p:Hide()
                    p.catcher:Hide()
                    self:SetPage(row.page)
                end)
                p.rows[n] = r
            end
            r.page = page
            r.icon:SetTexture(C_Spell.GetSpellTexture(id))
            r.label:SetValue(C_Spell.GetSpellName(id) or "")
            -- its four totems, earth to air, before the tick
            local x = -22
            for k = #ELEMENTS, 1, -1 do
                local t = r.totems[k]
                local sid = slotSpell(ELEMENTS[k].slot, page)
                t:ClearAllPoints()
                t:SetPoint("RIGHT", x, 0)
                t:SetTexture(sid and C_Spell.GetSpellTexture(sid) or nil)
                t:SetShown(sid ~= nil)
                x = x - 14
            end
            r.check:SetShown(page == self.page)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, y)
            r:SetPoint("TOPRIGHT", -4, y)
            r:Show()
            y = y - 23
        end
    end
    for i = n + 1, #p.rows do p.rows[i]:Hide() end
    p:SetSize(240, -y + 4)
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", self.call, "TOPLEFT", 0, STRIP_H + S["space-1"] + 6)
    p.catcher:Show()
    p:Show()
end

-- The arrow on a hovered button, under its bottom edge: opens its list
-- (an element's totems while it has more than one; the Call button's sets
-- while you know more than one). Out of combat.
local function pickArrow(b, open, wanted)
    -- under the button: above it the strip shows the time (asked in game:
    -- the timer covered the arrow while a totem was down)
    local a = CreateFrame("Button", nil, b)
    a:SetSize(14, 8)
    a:SetPoint("TOP", b, "BOTTOM", 0, 3)
    a:SetFrameStrata("HIGH")
    a.bg = UI.Fill(a, "surface-glass", "BACKGROUND")
    a.bg:SetAllPoints()
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetTexture(GLYPH .. "chevronUp.tga")
    UI.Paint(a.icon, "gilt-text")
    a.icon:SetSize(10, 10)
    a.icon:SetPoint("CENTER")
    a:SetScript("OnClick", open)
    a:SetScript("OnEnter", function() a.over = true end)
    a:SetScript("OnLeave", function()
        a.over = false
        C_Timer.After(0.3, function() if not (a.over or b:IsMouseOver()) then a:Hide() end end)
    end)
    a:Hide()
    b:HookScript("OnEnter", function()
        if not InCombatLockdown() and wanted() then a:Show() end
    end)
    b:HookScript("OnLeave", function()
        C_Timer.After(0.3, function() if not (a.over or b:IsMouseOver()) then a:Hide() end end)
    end)
    b.arrow = a
end

function UI.TotemBar(parent, opts)
    local bar = setmetatable({}, { __index = Totems })
    bar.name, bar.enabled = opts.name, true
    bar.page, bar.onPage = opts.page or 1, opts.onPage
    bar.binding = "MULTICASTACTIONBUTTON"
    bar.onLayout = opts.onLayout
    bar.header = CreateFrame("Frame", opts.name, parent, "SecureHandlerStateTemplate")
    bar.header:SetSize(1, 1)
    bar.buttons = {}
    for i, element in ipairs(ELEMENTS) do
        local b = UI.ActionButton(bar.header, opts.name .. "Button" .. i, "action-sm")
        b:SetID(0)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b.element = element
        b.showEmpty = true
        b.bindLabel = (opts.label or opts.name) .. ": " .. element.word
        emptyLook(b, element)
        b.Update = totemUpdate
        b.ShowTooltip = totemTooltip
        stripSegment(bar, b)
        b.bar = bar
        pickArrow(b, function() bar:OpenPicker(b) end, function() return #elementSpells(element.slot) > 1 end)
        b:HookScript("OnClick", function(_, button) if button == "LeftButton" then b.castAt = GetTime() end end)
        bar.buttons[i] = b
    end
    -- Call of the Elements, after a hairline
    bar.rule = bar.header:CreateTexture(nil, "ARTWORK")
    bar.rule:SetSize(1, 12)
    UI.PaintFill(bar.rule, "gilt-hairline")
    bar.call = UI.ActionButton(bar.header, opts.name .. "Call", "action-sm")
    bar.call:SetID(0)
    bar.call:RegisterForClicks("AnyUp", "AnyDown")
    bar.call.showEmpty = false
    bar.call.Update = function() end
    bar.call.ShowTooltip = function(c)
        if c.spellID then GameTooltip:SetSpellByID(c.spellID) end
        if (bar.knownSets or 0) > 1 then GameTooltip:AddLine("The arrow: another set of totems.", UI.RGBA("ink-muted")) end
    end
    pickArrow(bar.call, function() bar:OpenSets() end, function() return (bar.knownSets or 0) > 1 end)
    bar.call:HookScript("OnClick", function()
        for _, b in ipairs(bar.buttons) do b.castAt = GetTime() end
    end)
    -- Totemic Recall: the last button, on the right of Call
    bar.recall = UI.ActionButton(bar.header, opts.name .. "Recall", "action-sm")
    bar.recall:SetID(0)
    bar.recall:RegisterForClicks("AnyUp", "AnyDown")
    bar.recall.showEmpty = false
    bar.recall.Update = function() end
    bar.recall.ShowTooltip = function() GameTooltip:SetSpellByID(RECALL) end

    local function refresh() bar:Refresh() end
    local function all() bar:UpdateAll() end
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UPDATE_MULTI_CAST_ACTIONBAR", "LEARNED_SPELL_IN_SKILL_LINE" }) do
        pcall(Events.OnGame, e, refresh, bar)
    end
    for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN" }) do
        Events.OnGame(e, all, bar)
    end
    Events.OnGame("PLAYER_TOTEM_UPDATE", function() bar:UpdateTimers() end, bar)
    -- out of a fight the slots' totems can be read again
    Events.OnGame("PLAYER_REGEN_ENABLED", function() bar:UpdateTimers() end, bar)
    -- a fight closes the list while it still may (the start of combat
    -- allows it)
    Events.OnGame("PLAYER_REGEN_DISABLED", function()
        bar:ClosePicker()
        if bar.sets and bar.sets:IsShown() then bar.sets:Hide(); bar.sets.catcher:Hide() end
    end, bar)
    bar:Refresh()
    ns.Extend.Add("actionbar", bar, { name = opts.name, totems = true })
    return bar
end
