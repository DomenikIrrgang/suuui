-- The inventory plugin. Phase 5: one window over the player's live bags, opened by a slash
-- command. Blizzard's own bags are NOT suppressed yet -- that is Phase 6 -- deliberately, so this
-- window can be compared side by side with the default UI before it replaces it.
local type = type

local PLUGIN_ID = "inventory"
local W = SuuUI._InventoryWindow
local S = SuuUI._Inventory and SuuUI._Inventory.Suppress

local plugin
local bagsWindow
local bankWindow
-- Whether the player is AT a teller, as an intent flag. Not derived from the window, because a fading
-- window still reports itself shown -- see pairWindows.
local bankOpen = false
-- Watches the bank frame. A plugin may register game events directly -- that is data, not UI.
local events

-- Every setting that changes the GRID's shape, and the applier for each. Kept as a table so a new
-- one is a row here rather than another watcher block -- and so nothing can be added to the schema
-- without a visible place for its watcher, which is the gap that once shipped a width slider that
-- did nothing until a reload.
local SHAPE = {
    columns   = function(g, v) g:SetColumns(v) end,
    cell_size = function(g, v) g:SetCellSize(v) end,
    sort_mode = function(g, v) g:SetSortMode(v) end,
}

local function window()
    if not bagsWindow then
        bagsWindow = W.New({ container = "bags" })
    end
    return bagsWindow
end

-- CENTRES THE SEAM between the two windows, not each window and not the pair's bounding box. Each is
-- offset by half its own width plus half the gap, which puts the gap itself exactly at screen centre
-- and leaves the arrangement lopsided by (bagsW - bankW) / 2 whenever the widths differ -- which they
-- do, since the bank holds 35 slots to the bags' 20-odd. That is the right choice rather than a
-- rounding error: the seam is where the player's eye and cursor work, because every drag crosses it.
--
-- Recomputed on every open rather than stored, which is what a CENTRED window already does -- it
-- discards its drags and re-centres, so there is no saved position here to fight. The widths are read
-- from the windows themselves because the two genuinely differ: the bank holds 35 slots to the bags'
-- 20-odd, so a fixed offset would leave a gap on one side and an overlap on the other.
local function pairWindows()
    local bagsUp = bagsWindow and bagsWindow:IsShown()
    -- THE BANK'S STATE COMES FROM INTENT, NOT FROM IsShown(). Window:Hide is a FADE-OUT, so a window
    -- that is closing still reports itself shown for the whole animation -- and this runs immediately
    -- after that Hide. Reading visibility here left the bags offset to one side with nothing beside
    -- them, which looks like the window drifted. Animated visibility is never a sound input to a
    -- layout decision; the flag says what we ASKED for, which is what the layout should follow.
    local bankUp = bankOpen and bankWindow ~= nil
    -- EACH WINDOW IS TOLD WHETHER IT IS PAIRED, which is what swaps the Bags/Bank switch for a muted
    -- BAGS / BANK tag: with both windows on screen there is nothing left to switch, and a live control
    -- whose container is fixed is how you ship something that appears to do nothing. Told from here
    -- because this function already owns the answer.
    local paired = bagsUp and bankUp
    if bagsWindow and bagsWindow.SetPaired then bagsWindow:SetPaired(paired) end
    if bankWindow and bankWindow.SetPaired then bankWindow:SetPaired(paired) end
    if not (bagsUp and bankUp) then
        if bagsUp then bagsWindow:GetWindow():Center() end
        if bankUp then bankWindow:GetWindow():Center() end
        return
    end

    local gap = SuuUI.Theme:GetToken("spaceMd") or 12
    local bagsW = bagsWindow:GetWindow():GetWidth() or 0
    local bankW = bankWindow:GetWindow():GetWidth() or 0
    -- Bank on the LEFT by default: the bags are what the player drags FROM most of the time, and the
    -- sort control sits in the bags window's title bar, so keeping the bags on the right puts that
    -- control on the outer edge and stops the two title bars being adjacent. `bank_side` exists because
    -- that is a preference rather than a fact -- a left-handed layout, or a player whose other addons
    -- live on the right, wants the opposite.
    --
    -- Read here rather than cached, and each window is offset by the OTHER one's half-width plus the
    -- gap: the two are not the same width (the bank has more slots) so a single fixed offset would
    -- leave a gap on one side and an overlap on the other.
    local bankLeft = SuuUI.Settings:Get(PLUGIN_ID, "bank_side") ~= "right"
    if bankLeft then
        bankWindow:GetWindow():Center(-((bankW + gap) / 2))
        bagsWindow:GetWindow():Center((bagsW + gap) / 2)
    else
        bankWindow:GetWindow():Center((bankW + gap) / 2)
        bagsWindow:GetWindow():Center(-((bagsW + gap) / 2))
    end
end

--- Opens the inventory window, building it on first use.
function SuuUI.Inventory_Open()
    window():Show()
end

--- Toggles it.
function SuuUI.Inventory_Toggle()
    window():Toggle()
end

--- The live window handle for a container, or nil if it has not been built yet.
--
-- A real seam rather than a debugging hook: the account ledger and the tooltip section both need to
-- reach the open windows in later phases, and a probe needing it is how the gap was noticed. Named
-- rather than exposing the locals, so nothing outside can reassign them.
-- @param which string  "bags" | "bank"
-- @return table|nil
function SuuUI.Inventory_GetWindow(which)
    if which == "bank" then return bankWindow end
    return bagsWindow
end

--- Closes it.
--
-- Deliberately does NOT build the window first: CloseBackpack / CloseAllBags are called by the client
-- on plenty of occasions the player never sees -- entering combat, a loot window closing, a vendor
-- shutting -- and building a whole window in order to hide it would create it during login.
function SuuUI.Inventory_Close()
    if bagsWindow then bagsWindow:Hide() end
end

-- THE BANK SESSION.
--
-- Two LIVE windows while the player stands at a banker, because moving an item between bank and bags
-- means dragging from one grid to the other -- and a single window that switched scope could only ever
-- move things one way at a time. This is the hard requirement the design was built around.
--
-- The MOVEMENT ITSELF NEEDS NO CODE AT ALL, and that is the payoff of building cells on
-- ContainerFrameItemButtonTemplate: pickup, place, split and swap all live in the template's own
-- OnClick, which is trusted, so a drag from a bank cell to a bag cell is the client's own mechanism
-- running between two of our frames. Measured in Phase 0 -- PickupContainerItem works from tainted
-- Lua, which is why the cells could be ours in the first place.
--
-- The bank window is HIDDEN rather than destroyed when the bank closes. Rebuilding it every visit
-- would throw away 35 cells and rebuild them on the next teller, and a cell cannot be re-pointed at a
-- different bag anyway -- its bag comes from its parent, stated once at construction.
local function bankSession(open)
    bankOpen = open and true or false
    if open then
        if not bankWindow then
            bankWindow = W.New({ container = "bank" })
        end
        -- The bags come up WITH the bank, unasked: the whole point of the session is moving things
        -- between the two, and a player who has to press B as well would find half the feature.
        window():Show()
        bankWindow:Show()
        pairWindows()
        return
    end
    if bankWindow then bankWindow:Hide() end
    -- The bags window goes back to being centred on its own, or it stays offset to one side with
    -- nothing beside it -- which reads as the window having drifted. Runs AFTER bankOpen is cleared,
    -- which is what lets pairWindows see a single window rather than a fading pair.
    pairWindows()
end

local function teardown()
    if bagsWindow then
        bagsWindow:Destroy()
        bagsWindow = nil
    end
    if bankWindow then
        bankWindow:Destroy()
        bankWindow = nil
    end
    -- UnregisterEvent by name, never UnregisterAllEvents: this frame is ours, but the habit is the one
    -- that matters -- and the frame is kept for a re-enable rather than leaked and rebuilt.
    if events then
        events:UnregisterEvent("BANKFRAME_OPENED")
        events:UnregisterEvent("BANKFRAME_CLOSED")
    end
end

plugin = SuuUI:CreatePlugin({
    id      = "inventory",
    name    = "Inventory",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register(PLUGIN_ID, {
            { key = "enabled", label = "Enable Inventory", type = "toggle", default = true },
            -- TOP LEVEL, OUTSIDE ANY SECTION, deliberately. A player whose bags are misbehaving
            -- needs Blizzard's own back without hunting through a collapsed group and without
            -- disabling the whole plugin -- the same escape-hatch rule the action bars' suppression
            -- toggle follows.
            { key = "suppress_blizzard", label = "Replace Blizzard's Bags", type = "toggle",
              default = true },
            { key = "", label = "Layout", type = "section" },
            { key = "columns", label = "Columns", type = "slider",
              default = 10, min = 6, max = 20, step = 1 },
            { key = "cell_size", label = "Cell Size", type = "slider",
              default = 34, min = 24, max = 48, step = 1 },
            { key = "sort_mode", label = "Sort By", type = "dropdown",
              default = "quality", options = W.SORT_OPTIONS },
            -- TWO ENTRIES FROM THE PLAN'S TABLE ARE DELIBERATELY ABSENT, and their absence is the
            -- decision rather than an oversight.
            --
            -- `grouping` was to ship "as a stub returning flat in v1" -- a dropdown with one working
            -- option and no effect. That is precisely the failure the theme rule names: a control that
            -- silently does nothing is worse than an absent one, because the player reads it as broken
            -- rather than as unbuilt. It arrives with the feature.
            --
            -- `account_badges` (T2 corner badges) contradicts this plan's own §1, which REJECTS them:
            -- they read as a second stack count and collide with the real one. A toggle for a rejected
            -- feature is a control that either does nothing or turns on something we decided against.
            { key = "", label = "Bank", type = "section" },
            -- The DEFAULT IS LEFT, not the plan table's `right`, because left is what ships today and
            -- has a stated reason: the bags are what a player drags FROM, and the sort control sits in
            -- the bags window's title bar, so bags-on-the-right keeps that control on the outer edge and
            -- the two title bars apart. Defaulting to `right` would silently move both windows for
            -- anyone already using them, to no benefit.
            { key = "bank_side", label = "Bank Window Side", type = "dropdown", default = "left",
              options = {
                  { value = "left",  label = "Left of the bags" },
                  { value = "right", label = "Right of the bags" },
              } },
            { key = "", label = "Selling", type = "section" },
            -- ON BY DEFAULT AND MEANT TO STAY THAT WAY. Selling greys is irreversible once the vendor's
            -- twelve buyback slots overflow, a flat grid has no junk section to inspect first, and a
            -- grey can be a quest item or a vendor-recipe carrier. Off means one click sells.
            { key = "sell_confirm", label = "Confirm Before Selling", type = "toggle",
              default = true },
            -- NO `enabledIf = "sell_confirm"` HERE, which is the trap worth naming: the interval paces
            -- the sale itself, so it applies whether or not a dialog preceded it. Gating it on the
            -- confirmation would grey out the one control that still matters when the confirmation is
            -- off -- which is exactly when a player is selling fastest.
            { key = "sell_interval", label = "Seconds Between Sales", type = "slider",
              default = 0.2, min = 0.1, max = 1.0, step = 0.05 },
        })

        -- No `immediate` on the plugin's own enable watcher: Plugins:autoEnable already applies the
        -- stored value during the login pass, and an immediate callback would run onEnable from
        -- inside the init pass -- before other plugins' onInit had run.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, PLUGIN_ID)
    end,

    onEnable = function()
        -- LIVE APPLIERS rather than a rebuild. Rebuilding the window would drop its stored position
        -- and its registrations, so changing the column count would move the window as a side
        -- effect -- which is how the watch bars' width slider misbehaved.
        for key, apply in pairs(SHAPE) do
            SuuUI.Settings:Watch(PLUGIN_ID, key, function(value)
                if bagsWindow and value ~= nil then apply(bagsWindow:GetGrid(), value) end
            end, PLUGIN_ID .. ".shape")
        end

        -- The handler is set BEFORE suppression is applied. Apply installs the replacements, and a
        -- replacement with nothing listening falls through to Blizzard's own function -- so setting it
        -- second would leave a window between the two where the B key opened the frames we had just
        -- hidden, and the guarded OnShow would hide them again mid-open.
        S.SetHandler({
            Toggle = function() SuuUI.Inventory_Toggle() end,
            Open   = function() SuuUI.Inventory_Open() end,
            Close  = function() SuuUI.Inventory_Close() end,
        })

        -- Driven THROUGH the setting rather than called once, so switching it off restores Blizzard's
        -- bags immediately and exercises the same Restore path onDisable uses. `immediate` is right
        -- here, unlike on the plugin's own `enabled` key: this watcher runs inside onEnable, which is
        -- already past the init pass.
        -- RE-PAIRS THE OPEN WINDOWS, rather than waiting for the next visit to a banker. Same
        -- live-applier rule the column and cell-size sliders follow: a setting whose effect appears only
        -- after the surface is rebuilt reads as a setting that did not take. No `immediate` -- pairing
        -- runs on open anyway, and firing it during onInit would place windows that do not exist yet.
        SuuUI.Settings:Watch(PLUGIN_ID, "bank_side", function()
            pairWindows()
        end, PLUGIN_ID .. ".bankside")

        -- THE SELL INTERVAL IS APPLIED THROUGH A WATCHER, not read at each sale, because Sell owns the
        -- clamp: a hand-edited SavedVariable reaching 0 would turn the ticker into a per-frame sell loop.
        -- Immediate, so the stored value is in force before the first sale rather than after the first
        -- change -- the same reason every bound widget passes it.
        SuuUI.Settings:Watch(PLUGIN_ID, "sell_interval", function(value)
            local Sell = SuuUI._Inventory and SuuUI._Inventory.Sell
            if Sell and Sell.SetInterval then Sell.SetInterval(value) end
        end, PLUGIN_ID .. ".sell", { immediate = true })

        SuuUI.Settings:Watch(PLUGIN_ID, "suppress_blizzard", function(on)
            if on then S.Apply() else S.Restore() end
        end, PLUGIN_ID .. ".suppress", { immediate = true })

        -- THE BANK SESSION'S TRIGGER. These two events are the only way to know the player is at a
        -- teller: bank slots are not readable away from one -- measured, a shut bank reports 28 slots
        -- and zero free, which is only consistent with no data -- so the window cannot exist
        -- meaningfully outside this window of time.
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", function(_, event)
                bankSession(event == "BANKFRAME_OPENED")
            end)
        end
        events:RegisterEvent("BANKFRAME_OPENED")
        events:RegisterEvent("BANKFRAME_CLOSED")
    end,

    onDisable = function()
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".shape")
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".sell")
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".bankside")
        SuuUI.Settings:Unwatch(PLUGIN_ID .. ".suppress")
        -- Restore BEFORE dropping the handler, and unconditionally: a plugin that cannot hand the
        -- default UI back is not finished, and this runs for a settings-driven Disable as well as for
        -- a reload, with nothing behind it either way.
        S.Restore()
        S.SetHandler(nil)
        teardown()
    end,
})

-- Its OWN slash command rather than a `bags` case inside /suuui. That handler belongs to
-- SettingsWindow, and adding plugin knowledge to it would couple the two -- the same reason the
-- minimap button got a public API seam instead of calling SlashCmdList["SUUUI"]().
--
-- TEMPORARY: Phase 6 routes the B key here by replacing the client's own bag toggles, at which point
-- this stays only as a way in that does not depend on a keybind.
SLASH_SUUUIBAGS1 = "/sbags"
SLASH_SUUUIBAGS2 = "/suuuibags"
SlashCmdList["SUUUIBAGS"] = function()
    SuuUI.Inventory_Toggle()
end

SuuUI._InventoryPlugin = plugin
