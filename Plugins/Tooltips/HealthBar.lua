-- The unit health bar: SuuUI's OWN StatusBar, inside the tooltip panel.
--
-- This replaces a first version that drove Blizzard's GameTooltipStatusBar, which is what ElvUI
-- does. The deciding argument for owning it is one line that no longer exists: driving Blizzard's
-- bar required `SetScript("OnValueChanged", nil)` followed by a re-hook -- the only
-- non-additive call in the whole plugin -- purely to stop its own handler fighting ours and
-- making the bar flicker. Own the bar and there is nothing to fight.
--
-- Two more things came free. The readout goes through Components.StatusBar's three text slots
-- using Core/Readout.lua's shared formats, so a tooltip and a unit frame spell the same numbers
-- the same way -- the first version had invented k/M abbreviation no other bar in the addon uses.
-- And the bar follows the theme, the pixel grid and the fill transition without any code here.
--
-- The price is stated plainly: Blizzard's bar has to be SUPPRESSED, because the client keeps
-- showing it, and the value has to be driven from UnitHealth rather than arriving for free.
local type, math, pcall, next, pairs = type, math, pcall, next, pairs

local M = {}

local PLUGIN_ID = "tooltips"

local function gap()  return SuuUI.Theme:GetToken("spaceXs") or 4 end
local function edge() return SuuUI.Theme:GetToken("borderWidth") or 1 end

local widget        -- our StatusBar handle
local host          -- the stack container placing it inside the tooltip
local placed        -- whether the bar has been ADDED to that container yet
local unitShown     -- which unit the open tooltip describes
local events        -- the UNIT_HEALTH watcher, live only while a unit tooltip is open
local reserved = {} -- tooltips currently carrying OUR reserved padding

-- What THIS module is suppressing, and what it has hooked. Keyed by frame, exactly like the
-- Blizzard-suppression pattern in plugin-authoring.md -- HookScript cannot be undone, so the
-- hook asks the flag on every show instead of assuming it should always hide.
local suppressed, hooked = {}, {}

M._reserved   = reserved
M._suppressed = suppressed

local function height()
    local h = SuuUI.Settings:Get(PLUGIN_ID, "health_height")
    return type(h) == "number" and h > 0 and h or 12
end

local function position()
    local p = SuuUI.Settings:Get(PLUGIN_ID, "health_position")
    if p == "TOP" or p == "DISABLED" then return p end
    return "BOTTOM"
end

M.position = position
M.height   = height

function M.GetWidget() return widget end

--- The container placing the bar. Exposed so a spec can count its children: "added once" is
--- otherwise unassertable, and Add being a membership operation rather than an upsert means a
--- per-mouseover Add would grow that list without bound.
function M.GetHost() return host end

---------------------------------------------------------------------------
-- Suppressing Blizzard's bar
---------------------------------------------------------------------------

--- Hides the client's own tooltip health bar and keeps it hidden.
--
-- Necessary rather than tidy: GameTooltip_ShowStatusBar shows that bar whenever the client has a
-- unit's health to display, so a one-shot Hide is undone on the next mouseover and the player
-- sees two bars.
--
-- The guarded OnShow hook is the sanctioned shape -- never UnregisterAllEvents, which nothing in
-- the API can undo, so onDisable could never hand the frame back alive.
local function suppressBlizzardBar()
    local b = _G.GameTooltipStatusBar
    if not b then return false end
    suppressed[b] = true
    if not hooked[b] and type(b.HookScript) == "function" then
        hooked[b] = true
        b:HookScript("OnShow", function(self)
            if suppressed[self] then self:Hide() end
        end)
    end
    b:Hide()
    return true
end

--- Hands Blizzard's bar back.
--
-- The flag is cleared BEFORE the Show, because the hook is permanent: in the other order it
-- hides the frame straight back on the way out and onDisable silently restores nothing.
local function restoreBlizzardBar()
    local b = _G.GameTooltipStatusBar
    if not b or not suppressed[b] then return false end
    suppressed[b] = nil
    return true
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------

local function ensureWidget(tt)
    if widget then return widget end
    if type(tt) ~= "table" then return nil end

    widget = SuuUI.Components.StatusBar({
        h          = height(),
        max        = 1,
        value      = 0,
        border     = false,
        -- Instant, deliberately. A tooltip is open for a moment and a bar still sliding toward
        -- its value when the tooltip closes has told the player nothing -- the smoothing that
        -- suits a unit frame is wrong for something this short-lived.
        transition = "instant",
        textSize   = "sm",
    }, tt)

    -- Raised above the tooltip's own text, or the bar draws behind the lines it sits beside.
    SuuUI.UIRoot:RaiseAbove(widget:GetFrame(), tt, 1)

    host = SuuUI.Layout:CreateContainer({ host = tt, layout = "stack" })
    return widget
end

---------------------------------------------------------------------------
-- The readout
---------------------------------------------------------------------------

--- Writes the three slots from the shared formats.
--
-- One mode drives all three today: the tooltip has one bar, and three independently configured
-- readouts on it would be three dropdowns for a strip of text a player looks at for a second.
-- The centre slot is the one that reads naturally on a short bar.
function M.UpdateText()
    if not widget then return end
    local show = SuuUI.Settings:Get(PLUGIN_ID, "health_text")
    local mode = show and SuuUI.Settings:Get(PLUGIN_ID, "health_text_mode") or "none"

    local cur, max = 0, 0
    if unitShown and type(UnitHealth) == "function" then
        cur = UnitHealth(unitShown) or 0
        max = (type(UnitHealthMax) == "function" and UnitHealthMax(unitShown)) or 0
    end

    -- A dead unit reads DEAD rather than "0 / 15240", which is a statement about the unit and
    -- not about its numbers -- so it bypasses the shared formats deliberately.
    local text
    if unitShown and cur <= 0 and max > 0 then
        text = _G.DEAD or "Dead"
    else
        text = SuuUI.Readout.Format(mode, cur, max)
    end

    for _, slot in next, SuuUI.Readout.SLOTS do
        widget:SetText(slot, slot == "center" and text or nil)
    end
end

--- Pushes the unit's current health into the bar.
function M.Refresh()
    if not widget or not unitShown then return end
    local max = (type(UnitHealthMax) == "function" and UnitHealthMax(unitShown)) or 0
    local cur = (type(UnitHealth) == "function" and UnitHealth(unitShown)) or 0
    widget:SetMax(max > 0 and max or 1)
    widget:SetValue(cur)
    M.UpdateText()
end

---------------------------------------------------------------------------
-- Live updates
---------------------------------------------------------------------------

-- Registered only while a unit tooltip is open, and dropped when it closes. Nothing announces
-- that a tooltip went away, so this is the one place the module keeps an event frame -- and it
-- stays idle the rest of the time rather than dispatching for every unit in the world.
local function ensureEvents()
    if events then return events end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, _, unit)
        if unit and unit ~= unitShown then return end
        M.Refresh()
    end)
    return events
end

local function watchUnit(on)
    local f = ensureEvents()
    if on then
        -- pcall per event: one absent on a client generation must not take the bar down.
        for _, e in next, { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT" } do
            pcall(f.RegisterEvent, f, e)
        end
    else
        pcall(f.UnregisterAllEvents, f)
    end
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------

--- Reserves space for the bar and places it inside the tooltip.
--
-- Padding is stated ABSOLUTELY, never adjusted relative to its current value: GameTooltip is
-- shared with Blizzard and every other addon, so the padding already on it may not be ours.
-- @return bool  whether the bar was placed
function M.Apply(tt, unit)
    if type(tt) ~= "table" then return false end
    if not SuuUI.Settings:Get(PLUGIN_ID, "enabled") then return false end

    if position() == "DISABLED" then
        if widget then widget:Hide() end
        unitShown = nil
        watchUnit(false)
        M.Release(tt)
        return false
    end

    suppressBlizzardBar()

    local w = ensureWidget(tt)
    if not w then return false end

    unitShown = unit

    local h, g, ins = height(), gap(), edge()

    if type(tt.SetPadding) == "function" then
        if position() == "TOP" then
            pcall(tt.SetPadding, tt, 0, 0, 0, h + g)
        else
            pcall(tt.SetPadding, tt, 0, h + g, 0, 0)
        end
        reserved[tt] = true
    end

    -- Placed by a STACK container, not an anchor one and not SetPoint. A tooltip resizes on
    -- every line it is handed, and stack stretches its child across the box on each pass -- so
    -- the bar tracks the tooltip's width for free. An anchor descriptor would carry a width
    -- computed once at Apply time and go stale the moment the next line arrived.
    --
    -- Re-added only ONCE: Add is a membership operation rather than an upsert, so calling it per
    -- mouseover would grow the container's child list without bound. Later shows update the props.
    local props = {
        valign = position() == "TOP" and "start" or "end",
        align  = "stretch",
        height = h,
        inset  = ins + g,
    }
    if placed then
        host:SetChildProps(w, props)
    else
        host:Add(w, props)
        placed = true
    end

    -- The colour the client does not supply: class when the theme says so, else the unit's
    -- reaction, else the Health token. Theme:GetUnitColor IS that chain.
    local c = SuuUI.Theme:GetUnitColor("colorHealth", unit)
    if c then w:SetFillColor(c) end

    w:Show()
    watchUnit(true)
    M.Refresh()
    return true
end

--- Hands the reserved space back.
--
-- Guarded on `reserved` for the same reason the signal border's reset is: with the feature off we
-- reserved nothing, and clearing anyway would stamp on padding somebody else set. A tooltip left
-- carrying our gap while showing someone else's content has a mystery hole at the bottom.
-- @return bool  whether anything was released
function M.Release(tt)
    if type(tt) ~= "table" or not reserved[tt] then return false end
    reserved[tt] = nil
    if type(tt.SetPadding) == "function" then
        pcall(tt.SetPadding, tt, 0, 0, 0, 0)
    end
    return true
end

--- Called when the tooltip goes away.
function M.OnHide(tt)
    if widget then widget:Hide() end
    unitShown = nil
    watchUnit(false)
    M.Release(tt)
end

--- Called from OnTooltipCleared.
function M.OnCleared(tt)
    M.OnHide(tt)
end

--- Restyles the bar after a theme change.
function M.ApplyTheme()
    if not widget then return end
    widget:ApplyTheme()
    if unitShown then
        local c = SuuUI.Theme:GetUnitColor("colorHealth", unitShown)
        if c then widget:SetFillColor(c) end
    end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

--- Installs the tooltip-hide hook. Once, and never undone.
--
-- On Hide directly rather than OnHide, which is the hook ElvUI's own comment recommends. Nothing
-- else tells us a tooltip closed, and without it the bar lingers over the world.
function M.Install()
    local tt = _G.GameTooltip
    if not tt or hooked[tt] then return false end
    hooked[tt] = true
    if type(_G.hooksecurefunc) == "function" then
        pcall(_G.hooksecurefunc, tt, "Hide", function(self) M.OnHide(self) end)
    end
    return true
end

--- Drops everything droppable and hands Blizzard's bar back.
function M.Teardown()
    unitShown = nil
    watchUnit(false)
    for tt in pairs(reserved) do M.Release(tt) end
    if widget then widget:Destroy() widget = nil end
    if host then host:Destroy() host = nil end
    placed = nil
    restoreBlizzardBar()
end

SuuUI._Tooltips = SuuUI._Tooltips or {}
SuuUI._Tooltips.HealthBar = M
