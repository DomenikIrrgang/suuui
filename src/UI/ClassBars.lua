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
