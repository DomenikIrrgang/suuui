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

SuuUI._DataBar = SuuUI._DataBar or {}

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.addon_buttons"
local OWNER     = "databar.addon_buttons"

local M = { ID = WIDGET_ID }

local panel
local anchorField
local lastCount, lastText, lastTone

local function Collector()
    return SuuUI._DataBar.ButtonCollector
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

-- Set while a FORWARDED click is running, with any rebuild it asks for held over until it
-- returns.
--
-- This is the freeze. `forward` hands control to the clicked addon's own handler, and a great
-- many minimap-button handlers touch their own button -- Show it, Hide it, re-anchor it. Every
-- one of those is hooked by the collector, which reads it as "the roster changed" and answers
-- with a full rebuild: SetParent onto a different row, ClearAllPoints, SetPoint, and its strata
-- pins released and re-stated. All of that ran on the very frame whose OnClick was still on the
-- stack, from inside that handler, once per touch. Measured ordering before this guard existed:
--     click:enter | notify | SetRows | notify | SetRows | click:leave
--
-- Neither existing guard covers it, and neither could: `notifying` and `building` both stop
-- re-entry from OUR OWN cascade, whereas this call went out to foreign code and came back
-- through the front door. Hence a third flag on the one path that leaves the addon.
local clicking = false
local pendingRebuild = false

local function forward(entry, button)
    local frame = entry and entry.frame
    if not frame then return end
    clicking = true
    pendingRebuild = false
    pcall(frame.Click, frame, button)
    clicking = false
    -- Coalesced: however many times the handler touched its button, the roster settles once,
    -- after the click has finished rather than underneath it.
    if pendingRebuild then
        pendingRebuild = false
        M.Refresh()
    end
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

    -- The roster must not run off the bottom of the screen; past this cap it continues in a
    -- second column beside the first. Computed here rather than inside the panel, because it
    -- depends on where the panel hangs -- directly under the bar -- which only this caller
    -- knows. Re-stated on every open, so a resolution change is picked up for free.
    local root  = SuuUI.UIRoot:GetRootContainer()
    local avail = (root and root:GetHeight() or 0)
                - SuuUI.DataBar:GetOccupiedHeight()
                - (SuuUI.Theme:GetToken("spaceLg") or 16)
    p:SetMaxHeight(avail)

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
    -- A forwarded click is foreign code holding a reference to a button we are about to
    -- reparent. Note it and settle once the click returns; see `clicking` above.
    if clicking then
        pendingRebuild = true
        return
    end
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
    -- Ahead of latency (200) and the framerate (210), so the right section reads
    -- addons | latency | fps from left to right. A section places its fields in ascending
    -- order, so a lower number is further left.
    order   = 190,
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
---
--- The toggle governs COLLECTION, not just the field. Unregistering the field alone was the
--- shipped bug: the buttons stayed collected with nothing on screen showing them -- off the
--- ring, inside a panel that could no longer be reached -- so the player's icons simply
--- vanished. Whether the tray is on is therefore one fact with one owner, this watcher.
function M.Enable()
    SuuUI.Settings:Watch(PLUGIN_ID, "tray_enabled", function(on)
        local C = Collector()
        if on then
            SuuUI.DataBar:RegisterWidget(def)
            -- Picking the ring back up is not optional on this branch: the off-branch handed
            -- every button back, so without this the field returns reading 0 until something
            -- else happens to sweep.
            if C then
                C.Watch()
                C.Collect()
            end
        else
            SuuUI.DataBar:UnregisterWidget(WIDGET_ID)
            -- Closed before the buttons leave, so the panel is not holding frames it is about
            -- to lose.
            if panel then panel:Close() end
            if C then
                C.Unwatch()
                C.Restore()
            end
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

SuuUI._DataBar.TrayWidget = M
