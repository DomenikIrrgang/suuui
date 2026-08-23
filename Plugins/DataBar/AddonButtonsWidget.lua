-- The data bar's addon-button tray: a field reading "ADDONS 14", whose hover panel is the
-- roster of every addon button that used to sit on the minimap ring.
--
-- The panel shows the REAL buttons rather than pictures of them. That is the whole design: a
-- minimap button's click behaviour belongs to the addon that made it -- some open a config,
-- some toggle a window, some are secure frames the client will not let us click at all -- so
-- the only version that always matches is the button itself, adopted into the row. Nothing
-- here simulates a click except as a convenience on the row's empty space, and that path is
-- offered only for a button the client would actually allow it on.
local ipairs, type, tostring = ipairs, type, tostring

SuuUI._AddonButtons = SuuUI._AddonButtons or {}

local PLUGIN_ID = "addon_buttons"
local WIDGET_ID = "addon_buttons.tray"
local OWNER     = "addon_buttons.tray"

local M = { ID = WIDGET_ID }

local panel
local anchorField
local lastCount, lastText, lastTone

local function Collector()
    return SuuUI._AddonButtons.Collector
end

---------------------------------------------------------------------------
-- The field's reading
---------------------------------------------------------------------------

-- Cached on the count AND the tone, so the field is only rewritten when what it says changes.
-- The count itself is read without allocating -- this runs on the bar's shared ticker.
local function currentText()
    local C = Collector()
    if not C then return "—", "warning" end
    if C.RivalLoaded() then return "—", "warning" end

    local n = C.Count()
    if n ~= lastCount or lastTone ~= nil then
        lastCount, lastTone = n, nil
        lastText = tostring(n)
    end
    return lastText, nil
end

---------------------------------------------------------------------------
-- Click forwarding
---------------------------------------------------------------------------

-- A frame built from a secure template is one the client refuses to let addon code click, and
-- it refuses silently. The SECOND return of IsProtected is the one to read: UIParent is
-- explicitly protected, so the first return is true for essentially every frame in the UI and
-- says nothing about whether this one is secure.
local function isSecure(frame)
    if type(frame.IsProtected) ~= "function" then return false end
    local ok, _, explicit = pcall(frame.IsProtected, frame)
    return (ok and explicit) and true or false
end

-- Whether the row's empty space can usefully be made clickable. The adopted button always
-- handles its own clicks natively; this is only about widening the target to the whole row,
-- and it is withheld where it could not work -- a row that highlighted and did nothing would
-- promise an interaction that is not there.
local function canForward(frame)
    if not frame or type(frame.Click) ~= "function" then return false end
    if type(frame.IsObjectType) ~= "function" or not frame:IsObjectType("Button") then
        return false
    end
    return not isSecure(frame)
end

local function forward(entry, button)
    local frame = entry and entry.frame
    if not frame then return end
    pcall(frame.Click, frame, button)
end

---------------------------------------------------------------------------
-- The roster panel
---------------------------------------------------------------------------

local function ensurePanel(field)
    if panel then return panel end
    panel = SuuUI.Components.FlyoutPanel({
        anchorTo = field:GetFrame(),
        -- The field sits in the bar's right section, so a left-aligned panel would hang off
        -- the screen edge.
        align    = "right",
    }, SuuUI.UIRoot:GetRootContainer():GetFrame())
    return panel
end

-- A one-row roster used for the two states that have no buttons to show. A panel that opened
-- empty would be a bare box with no explanation in it.
local function messageRow(text)
    return { { key = "_message", label = text } }
end

local function openPanelInner(field)
    local C = Collector()
    local p = ensurePanel(field)
    anchorField = field

    if not C then
        p:SetRows(messageRow("Collector unavailable"))
        p:Open()
        return
    end

    if C.RivalLoaded() then
        p:SetRows(messageRow(C.RIVAL_ADDON .. " is active — disable it or this widget"))
        p:Open()
        return
    end

    -- Re-run on every open, which is what picks up a button from an addon that finished
    -- loading after login. Already-held buttons are skipped, so this is close to free.
    C.Collect()

    local entries, maxSize = C.GetEntries()
    if #entries == 0 then
        p:SetRows(messageRow("No addon buttons found"))
        p:Open()
        return
    end

    for _, entry in ipairs(entries) do
        if canForward(entry.frame) then entry.onClick = forward end
    end

    -- Natural size rather than a scaled-down one: these buttons carry stock ring art, and
    -- scaling foreign art to a fraction resamples it into a smear at exactly the size it is
    -- being drawn. Crisp and slightly larger beats small and blurred.
    p:SetIconSize(maxSize > 0 and maxSize or nil)
    p:SetRows(entries)
    p:Open()
end

-- Belt and braces against the recursion the collector's notify guard already breaks. Building
-- the roster lays out frames whose SetPoint is hooked, and a hook that reaches back here must
-- find the door shut rather than rely on the other guard still being on the stack.
local building = false

local function openPanel(field)
    if building then return end
    building = true
    local ok, err = pcall(openPanelInner, field)
    building = false
    if not ok then
        SuuUI.Debug("addon_buttons: opening the roster failed: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
-- The widget definition
---------------------------------------------------------------------------

local def = {
    id      = WIDGET_ID,
    label   = "Addon Buttons",
    prefix  = "ADDONS",
    section = "right",
    order   = 220,
    -- ADDON_LOADED is the one GAME event that coincides with buttons appearing, so the field
    -- re-reads on it. The rest of the time the count changes on LibDBIcon's own
    -- LibDBIcon_IconCreated callback, which the bar cannot subscribe to -- it registers game
    -- events only -- so a short poll is the available mechanism for that half. Count() is a
    -- loop over a handful of frames and allocates nothing, so 1s costs effectively nothing.
    --
    -- The principled alternative is a DataBar:RefreshWidget(id) call letting a plugin say "my
    -- value moved" on its own schedule; that is a Core addition, not a widget one.
    events  = { "ADDON_LOADED" },
    update  = 1,
    GetText = function() return currentText() end,

    OnEnter = function(field) openPanel(field) end,

    -- Deliberately empty. The panel closes when the cursor leaves the PANEL, not when it
    -- leaves the field -- closing here would shut it during the one movement that matters,
    -- the reach from the field down onto a row. Components/ClickAway.lua's HoverAway owns the
    -- close and treats the field and the panel as one region.
    OnLeave = function() end,

    -- A click toggles it, so the roster can be dismissed without moving the cursor away.
    OnClick = function(field)
        if panel and panel:IsOpen() then
            panel:Close()
        else
            openPanel(field)
        end
    end,
}

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

--- The widget's settings, rendered on the Addon Buttons page.
-- @return table
function M.Schema()
    return {
        { key = "", label = "Addon Buttons", type = "section" },
        { key = "tray_enabled", label = "Show Addon Buttons", type = "toggle", default = true },
    }
end

--- Registers the widget and keeps it in step with its enable toggle.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "tray_enabled", function(on)
        if on then
            SuuUI.DataBar:RegisterWidget(def)
        else
            SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
        end
    end, OWNER, { immediate = true })
end

--- Drops the widget, its watcher and its panel.
function M.Disable()
    SuuUI.Settings:Unwatch(OWNER)
    SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
    if panel then
        panel:Destroy()
        panel = nil
    end
    anchorField = nil
    lastCount, lastText, lastTone = nil, nil, nil
end

--- Re-reads the roster into an open panel. Called when a held button moves, shows or hides
--- itself, and after combat ends. A closed panel needs nothing: it rebuilds on the next open.
function M.Refresh()
    if panel and panel:IsOpen() and anchorField then
        openPanel(anchorField)
    end
end

SuuUI._AddonButtons.TrayWidget = M
