-- UI/ActionBar.lua
-- A bar of up to 12 action buttons: a secure header holding SuuUI's own
-- buttons, with paging, key bindings, drag and drop, and one shared event
-- dispatcher for every bar.
--
--   local bar = UI.ActionBar(parent, {
--       name = "SuuUIActionBar1", slot = 1, count = 12, columns = 12,
--       binding = "ACTIONBUTTON",     -- the game's binding command prefix
--       paging = UI.ActionBar.MAIN_PAGING,  -- bar 1 only
--   })
--   bar:SetHotkeysShown(true)
--   bar:Page()    -- the page bar 1 is on (1 when it doesn't page)
--
-- Blizzard's buttons are never used. Every key the game binds to one of the
-- bar's binding commands clicks the SuuUI button (SetOverrideBindingClick),
-- so second binds work too. Paging is a secure state driver: each button's
-- "action" attribute is rewritten in the restricted environment, never from
-- addon code. The art follows the same macro conditions on the Lua side
-- (SecureCmdOptionParse), so drawing never reaches into the secure pass.
-- Anything secure waits for the end of combat.

local _, ns = ...

local UI, T, Combat = ns.UI, ns.Tokens, ns.Combat
local S = T.space

local BUTTONS = 12
local isSecret = issecretvalue or function() return false end

local Bar = {}
local bars = {}          -- every bar made
local bySlot = {}        -- [slot] = { [button] = true }

--------------------------------------------------------------------------------
-- Paging (Forever)
--------------------------------------------------------------------------------

-- Forever pages bar 1 by the stance or form offset for every class (warrior
-- stances, druid forms, rogue stealth, Shadowform): page 6 + offset. Manual
-- pages (Shift+number) come first, as the engine resolves them.
local function mainPaging()
    local parts = {}
    if GetOverrideBarIndex then parts[#parts + 1] = "[overridebar] " .. GetOverrideBarIndex() end
    if GetVehicleBarIndex then parts[#parts + 1] = "[vehicleui][possessbar] " .. GetVehicleBarIndex() end
    for i = 2, 6 do parts[#parts + 1] = ("[bar:%d] %d"):format(i, i) end
    for i = 1, 4 do parts[#parts + 1] = ("[bonusbar:%d] %d"):format(i, 6 + i) end
    parts[#parts + 1] = "[bonusbar:5] 11"
    parts[#parts + 1] = "1"
    return table.concat(parts, "; ")
end

--------------------------------------------------------------------------------
-- Slots and range
--------------------------------------------------------------------------------

local rangeRefs = {}
local canRangeCheck = C_ActionBar and C_ActionBar.EnableActionRangeCheck

local function rangeOn(slot)
    rangeRefs[slot] = (rangeRefs[slot] or 0) + 1
    if rangeRefs[slot] == 1 and canRangeCheck then
        pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
    end
end

local function rangeOff(slot)
    local n = rangeRefs[slot]
    if not n then return end
    if n > 1 then rangeRefs[slot] = n - 1 return end
    rangeRefs[slot] = nil
    if canRangeCheck then pcall(C_ActionBar.EnableActionRangeCheck, slot, false) end
end

-- Enabling a range check sends no first state: read it once.
local function rangeNow(b)
    local r = b.slot and b.hasAction and IsActionInRange(b.slot)
    b:SetOutOfRange(not isSecret(r) and r == false)
end

local function onSlotChanged(b, old, new)
    if old then
        if bySlot[old] then bySlot[old][b] = nil end
        rangeOff(old)
    end
    if new then
        bySlot[new] = bySlot[new] or {}
        bySlot[new][b] = true
        rangeOn(new)
    end
end

local function eachButton(fn)
    for _, bar in ipairs(bars) do
        for _, b in ipairs(bar.buttons) do fn(b) end
    end
end

local function eachInSlot(slot, fn)
    for b in pairs(bySlot[slot] or {}) do fn(b) end
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

function Bar:Page()
    if not self.paging then return 1 end
    local p = SecureCmdOptionParse(self.paging)
    return tonumber(p) or 1
end

-- The art follows the page; the secure driver already moved the attribute.
function Bar:UpdatePage()
    local page = self:Page()
    if page == self.page then return end
    self.page = page
    for i, b in ipairs(self.buttons) do
        b:SetSlot(self.slot + (page - 1) * BUTTONS + i - 1)
        rangeNow(b)
    end
    if self.onPage then self.onPage(self, page) end
end

function Bar:SetHotkeysShown(shown)
    self.hotkeysShown = shown and true or false
    for _, b in ipairs(self.buttons) do b:SetHotkeyShown(self.hotkeysShown) end
end

function Bar:SetShowEmpty(shown)
    for _, b in ipairs(self.buttons) do
        b.showEmpty = shown and true or false
        b:UpdateEmpty()
    end
end

-- Every key bound to the bar's commands clicks its buttons. Out of combat.
function Bar:UpdateBindings()
    if not self.binding then return end
    Combat.Run("actionbar:bind:" .. self.name, function()
        ClearOverrideBindings(self.header)
        if self.hidden then return end
        for i, b in ipairs(self.buttons) do
            local keys = { GetBindingKey(self.binding .. i) }
            if i <= (self.count or #self.buttons) then
                for _, key in ipairs(keys) do
                    SetOverrideBindingClick(self.header, false, key, b:GetName(), "LeftButton")
                end
            end
            b:SetHotkey(UI.ShortKey(keys[1]))
        end
    end, "Action bars")
end

-- When the bar shows: "always", "combat", "mouseover" or "hidden". A hidden
-- bar also gives its keys back.
function Bar:SetVisibility(mode)
    self.hidden = mode == "hidden"
    UI.SetVisibility(self.header, mode)
    self:UpdateBindings()
end

function Bar:SetShown(shown)
    self:SetVisibility(shown and "always" or "hidden")
end

-- Drag lock follows the game's "Lock Action Bars" (Shift drags anyway).
function Bar:UpdateLock()
    Combat.Run("actionbar:lock:" .. self.name, function()
        local locked = GetCVarBool("lockActionBars") and true or false
        for _, b in ipairs(self.buttons) do b:SetAttribute("suu-locked", locked) end
    end, "Action bars")
end

-- Columns and rows, filled row by row from the top: `count` buttons of
-- `size` px, `gap` apart (space-1 by default). Out of combat.
function Bar:Layout(columns, gap, count, size)
    self.columns = columns or self.columns
    self.gap = gap or self.gap
    self.count = math.max(1, math.min(count or self.count or #self.buttons, #self.buttons))
    self.size = size or self.size or self.buttons[1]:GetWidth()
    local cols = math.min(self.columns, self.count)
    local rows = math.ceil(self.count / cols)
    local px, g = self.size, self.gap
    Combat.Run("actionbar:layout:" .. self.name, function()
        for i, b in ipairs(self.buttons) do
            b:Resize(px)
            local shown = i <= self.count
            b:SetShown(shown)
            if shown then
                local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.header, "TOPLEFT", c * (px + g), -r * (px + g))
            end
        end
        self.header:SetSize(cols * px + (cols - 1) * g, rows * px + (rows - 1) * g)
    end, "Action bars")
    self:UpdateBindings()
end

-- Secure snippets. The button's slot is base + (page - 1) * 12.
local PAGE_SNIPPET = [[
    self:SetAttribute("actionpage", tonumber(newstate) or 1)
    self:ChildUpdate("page", newstate)
]]
local CHILD_PAGE = [[ self:SetAttribute("action", %d + ((tonumber(message) or 1) - 1) * 12) ]]
local DRAG_START = [[
    if self:GetAttribute("suu-locked") and not IsModifiedClick("PICKUPACTION") then return false end
    return "action", self:GetAttribute("action")
]]
local RECEIVE_DRAG = [[ return "action", self:GetAttribute("action") ]]
-- Shift held over the button: the press is a pickup, not a cast.
local CLICK_PRE = [[
    if down and IsModifiedClick("PICKUPACTION") and self:IsUnderMouse() then return false end
]]

function UI.ActionBar(parent, opts)
    local bar = setmetatable({}, { __index = Bar })
    bar.name = opts.name
    bar.slot = opts.slot or 1
    bar.binding = opts.binding
    bar.paging = opts.paging
    bar.onPage = opts.onPage
    bar.columns = opts.columns or BUTTONS
    bar.gap = opts.gap or S["space-1"]

    local h = CreateFrame("Frame", opts.name, parent, "SecureHandlerStateTemplate")
    h:SetSize(1, 1)
    bar.header = h
    bar.buttons = {}

    for i = 1, math.min(opts.count or BUTTONS, BUTTONS) do
        local b = UI.ActionButton(h, opts.name .. "Button" .. i, opts.size)
        b.onSlotChanged = onSlotChanged
        if opts.binding then
            b.bindCommand = opts.binding .. i
            b.bindLabel = (opts.label or opts.name) .. " button " .. i
        end
        b:SetID(0)
        b:SetAttribute("type", "action")
        b:SetAttribute("action", bar.slot + i - 1)
        b:SetAttribute("checkselfcast", true)
        b:SetAttribute("checkfocuscast", true)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:RegisterForDrag("LeftButton")
        b:SetAttribute("_childupdate-page", CHILD_PAGE:format(bar.slot + i - 1))
        SecureHandlerWrapScript(b, "OnDragStart", h, DRAG_START)
        SecureHandlerWrapScript(b, "OnReceiveDrag", h, RECEIVE_DRAG)
        SecureHandlerWrapScript(b, "OnClick", h, CLICK_PRE)
        bar.buttons[i] = b
    end

    if bar.paging then
        h:SetAttribute("_onstate-page", PAGE_SNIPPET)
        RegisterStateDriver(h, "page", bar.paging)
    end

    bars[#bars + 1] = bar
    bar:Layout()
    bar:UpdateLock()
    bar:UpdateBindings()
    bar.page = nil
    if bar.paging then
        bar:UpdatePage()
    else
        bar.page = 1
        for i, b in ipairs(bar.buttons) do b:SetSlot(bar.slot + i - 1); rangeNow(b) end
    end
    return bar
end

UI.ActionBarPaging = mainPaging

--------------------------------------------------------------------------------
-- One dispatcher for every bar
--------------------------------------------------------------------------------

local GRID_CURSOR = { spell = true, item = true, macro = true, mount = true, petaction = true,
                      flyout = true, action = true, companion = true, equipmentset = true }

local function updateGrid()
    local kind = GetCursorInfo()
    local on = kind ~= nil and GRID_CURSOR[kind] or false
    eachButton(function(b) b:SetGrid(on) end)
end

local function updatePages()
    for _, bar in ipairs(bars) do bar:UpdatePage() end
end

-- Cooldown, usable and active state: one pass over the buttons per frame at
-- most. A cast fires SPELL_UPDATE_COOLDOWN and ACTIONBAR_UPDATE_COOLDOWN
-- (often several of each in one frame), and each pass reads every button's
-- cooldown as a new table from the game: 18 KB a pass, most of the action
-- bars' garbage (/suu probe garbage, 2026-10-18).
local PASSES = {
    cooldown = function(b) b:UpdateCooldown() end,
    usable = function(b) b:UpdateUsable() end,
    active = function(b) b:UpdateActive() end,
}
local due = {}
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    for kind, fn in pairs(PASSES) do
        if due[kind] then
            due[kind] = nil
            ns.Fault.Call("Action bars", eachButton, fn)
        end
    end
end)
local function later(kind)
    return function()
        due[kind] = true
        flusher:Show()
    end
end

local HANDLERS = {
    ACTIONBAR_SLOT_CHANGED = function(slot)
        if not slot or slot == 0 then eachButton(function(b) b:Update(); rangeNow(b) end)
        else eachInSlot(slot, function(b) b:Update(); rangeNow(b) end) end
    end,
    ACTIONBAR_UPDATE_COOLDOWN = later("cooldown"),
    SPELL_UPDATE_COOLDOWN = later("cooldown"),
    SPELL_UPDATE_CHARGES = function() eachButton(function(b) b:UpdateCount() end) end,
    BAG_UPDATE_DELAYED = function() eachButton(function(b) b:UpdateCount() end) end,
    ACTIONBAR_UPDATE_USABLE = later("usable"),
    SPELL_UPDATE_USABLE = later("usable"),
    ACTION_USABLE_CHANGED = later("usable"),
    ACTIONBAR_UPDATE_STATE = later("active"),
    PLAYER_ENTER_COMBAT = function() eachButton(function(b) b:UpdateActive() end) end,
    PLAYER_LEAVE_COMBAT = function() eachButton(function(b) b:UpdateActive() end) end,
    START_AUTOREPEAT_SPELL = function() eachButton(function(b) b:UpdateActive() end) end,
    STOP_AUTOREPEAT_SPELL = function() eachButton(function(b) b:UpdateActive() end) end,
    ACTION_RANGE_CHECK_UPDATE = function(slot, inRange, checksRange)
        local out = not isSecret(checksRange) and not isSecret(inRange) and checksRange and not inRange
        eachInSlot(slot, function(b) b:SetOutOfRange(out) end)
    end,
    PLAYER_TARGET_CHANGED = function() eachButton(rangeNow) end,
    UPDATE_BINDINGS = function() for _, bar in ipairs(bars) do bar:UpdateBindings() end end,
    CVAR_UPDATE = function(name)
        if name == "lockActionBars" or name == "LOCK_ACTIONBAR" then
            for _, bar in ipairs(bars) do bar:UpdateLock() end
        end
    end,
    CURSOR_CHANGED = updateGrid,
    ACTIONBAR_SHOWGRID = updateGrid,
    ACTIONBAR_HIDEGRID = updateGrid,
    UPDATE_MACROS = function() eachButton(function(b) b:Update() end) end,
    SPELL_UPDATE_ICON = function() eachButton(function(b) b:Update() end) end,
    PLAYER_ENTERING_WORLD = function() updatePages(); eachButton(function(b) b:Update(); rangeNow(b) end) end,
    -- Paging: the Lua side follows the same conditions as the secure driver.
    ACTIONBAR_PAGE_CHANGED = updatePages,
    UPDATE_BONUS_ACTIONBAR = updatePages,
    UPDATE_SHAPESHIFT_FORM = function() updatePages(); eachButton(function(b) b:UpdateUsable(); b:UpdateActive() end) end,
    UPDATE_SHAPESHIFT_FORMS = updatePages,
    UPDATE_OVERRIDE_ACTIONBAR = updatePages,
    UPDATE_VEHICLE_ACTIONBAR = updatePages,
    UPDATE_POSSESS_BAR = updatePages,
}

local dispatcher = CreateFrame("Frame")
for event in pairs(HANDLERS) do pcall(dispatcher.RegisterEvent, dispatcher, event) end
dispatcher:SetScript("OnEvent", function(_, event, ...)
    if #bars == 0 then return end
    ns.Fault.Call("Action bars", HANDLERS[event], ...)
end)

-- Without range events (older clients), poll the target's range.
if not canRangeCheck then
    local elapsed = 0
    dispatcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 or #bars == 0 then return end
        elapsed = 0
        eachButton(rangeNow)
    end)
end
