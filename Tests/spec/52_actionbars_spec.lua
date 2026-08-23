-- Components.ActionBarGrid and Plugins.ActionBars (phase 4a: bar 1, nothing suppressed)
--
-- The pair that matters is the lockdown pair. A grid contains protected buttons by
-- construction, so hasProtectedDescendant is TRUE for it -- that is correct, not a defect. The
-- assertion is the CONSEQUENCE: a settings change arriving mid-fight must be refused by US,
-- with a deferred flag, rather than attempted and refused by the CLIENT, which costs the
-- player a chat error for a call we already knew would not land.
local H = require("harness")

describe("Components.ActionBarGrid", function()
    local host

    local function build(props)
        props = props or {}
        if props.slots == nil then props.slots = { 1, 2, 3, 4 } end
        if props.buttonSize == nil then props.buttonSize = 32 end
        local g = H.C.ActionBarGrid(props, host)
        g:GetFrame():SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        return g
    end

    local function pad()
        return H.token("spaceXs") or 4
    end

    before_each(function()
        H.setup()
        -- The ActionBars plugin builds its own bar at login, so the component's live-count and
        -- shared-watcher assertions would be measuring two grids. Switched off here so these
        -- specs describe the component alone; the plugin has its own block below.
        H.SuuUI.Settings:Set("action_bars", "enabled", false)
        host = H.parent(600, 300)
    end)

    describe("geometry", function()
        it("sizes itself from the button size, not the other way round", function()
            -- GridLayout divides the container width into columns, so the frame width has to
            -- be exactly the span the buttons need or each cell comes out at whatever share of
            -- a wider box the layout hands out.
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32, spacing = 0 })
            H.expectSize(g, pad() * 2 + 4 * 32, pad() * 2 + 32)
        end)

        it("gives every button exactly the requested size", function()
            local g = build({ slots = { 1, 2, 3 }, buttonSize = 40, spacing = 0 })
            for _, b in ipairs(g:GetButtons()) do
                H.expectSize(b, 40, 40)
            end
        end)

        it("counts spacing into its own width", function()
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32, spacing = 4 })
            H.expectSize(g, pad() * 2 + 4 * 32 + 3 * 4, pad() * 2 + 32)
        end)

        it("derives columns from the slot count and the row count", function()
            local g = build({ slots = { 1, 2, 3, 4, 5, 6 }, buttonSize = 32, rows = 2,
                              spacing = 0 })
            -- Six slots in two rows is three columns; a player picks buttons and rows, never
            -- columns, so a grid that cannot hold its own buttons is unreachable.
            H.expectSize(g, pad() * 2 + 3 * 32, pad() * 2 + 2 * 32)
        end)

        it("lays the buttons out in rows, left to right", function()
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32, rows = 2, spacing = 0 })
            local b = g:GetButtons()
            local one, two, three = H.box(b[1]), H.box(b[2]), H.box(b[3])
            expect(two.left).as("second sits beside the first").eq(one.right)
            expect(two.top).as("and on the same row").eq(one.top)
            expect(three.left).as("third wraps to the next row").eq(one.left)
            expect(three.top).as("below the first").eq(one.bottom)
        end)

        it("keeps the buttons inside the plate", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32 })
            for _, b in ipairs(g:GetButtons()) do
                H.expectInside(b, g:GetFrame())
            end
        end)

        it("pads the plate so the glass is actually visible", function()
            -- At zero padding a seamless grid covers its own plate completely, and the whole
            -- A2 look is the plate.
            local g = build({ slots = { 1 }, buttonSize = 32, spacing = 0 })
            local fb, bb = H.box(g:GetFrame()), H.box(g:GetButtons()[1])
            expect(bb.left - fb.left).as("plate shows past the buttons").eq(pad())
            expect(bb.top - fb.top).eq(pad())
        end)

        it("re-sizes when the button size setting changes", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32, spacing = 0 })
            g:SetButtonSize(48)
            H.expectSize(g, pad() * 2 + 2 * 48, pad() * 2 + 48)
            H.expectSize(g:GetButtons()[1], 48, 48)
        end)
    end)

    describe("the glass plate", function()
        it("covers the whole box, with no border", function()
            local g = build()
            H.expectBox(g._plate._body, H.box(g:GetFrame()))
            for _, e in ipairs(g._plate._edges) do
                expect(H.vertexColor(e)).as("no border on the plate").deepEq({ 0, 0, 0, 0 })
            end
        end)

        it("takes the glass tokens and a real gradient", function()
            local g = build()
            expect(g._plate:IsGradient()).truthy()
            local grad = g._plate._body:GetGradient()
            H.expectTokenColor({ grad.to:GetRGBA() }, "colorGlass")
        end)

        it("takes NO mouse input, so a gap does not swallow a click at the world", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32, spacing = 6 })
            expect(g:GetFrame():IsMouseEnabled()).falsy()
        end)
    end)

    describe("the dividers", function()
        it("draws one between each pair of seamless cells", function()
            local g = build({ slots = { 1, 2, 3 }, buttonSize = 32, rows = 1, spacing = 0 })
            expect(#g._dividers).as("two gaps between three cells").eq(2)
        end)

        it("adds a horizontal one per row seam", function()
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32, rows = 2, spacing = 0 })
            -- 2 columns, 2 rows: one vertical seam and one horizontal.
            expect(#g._dividers).eq(2)
        end)

        it("draws none once the cells are separated by spacing", function()
            -- The plate already shows through the gap; a divider inside it would be a second
            -- separator inside the first.
            local g = build({ slots = { 1, 2, 3 }, buttonSize = 32, spacing = 4 })
            expect(#g._dividers).eq(0)
        end)

        it("is a hairline on the seam, spanning the button area", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32, rows = 1, spacing = 0 })
            local d = g._dividers[1]
            expect(d:GetWidth()).eq(H.SuuUI.Pixel.Line(0))
            expect(d:GetHeight()).as("spans the row").eq(32)
            local fb = H.box(g:GetFrame())
            expect(H.box(d).left).as("on the seam between the cells").eq(fb.left + pad() + 32)
        end)

        it("takes the border colour and draws above the plate", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32, spacing = 0 })
            H.expectTokenColor(H.vertexColor(g._dividers[1]), "colorBorder")
            expect(g._dividers[1]:GetDrawLayer()).eq("OVERLAY")
        end)

        it("drops the dividers when spacing is turned up", function()
            local g = build({ slots = { 1, 2, 3 }, buttonSize = 32, spacing = 0 })
            expect(#g._dividers).eq(2)
            g:SetSpacing(4)
            expect(#g._dividers).eq(0)
        end)
    end)

    describe("combat lockdown", function()
        it("contains the protected buttons, which is why every change is guarded", function()
            -- Stated rather than assumed away: this is TRUE for a grid and that is correct. A
            -- grid without its buttons inside it would not be a grid.
            local g = build()
            expect(H.hasProtectedDescendant(g:GetFrame())).truthy()
        end)

        it("refuses nothing mid-fight, because it does not try", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32 })
            H.setCombat(true)
            H.resetBlockedActions()

            g:SetButtonSize(48)

            expect(#H.getBlockedActions()).as("nothing was refused by the client").eq(0)
            expect(g:IsDeferred()).as("it deferred instead").truthy()
            H.expectSize(g:GetButtons()[1], 32, 32)
        end)

        it("catches up the moment the fight ends", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32 })
            H.setCombat(true)
            g:SetButtonSize(48)
            expect(g:IsDeferred()).truthy()

            H.setCombat(false)

            expect(g:IsDeferred()).as("the flag cleared").falsy()
            H.expectSize(g:GetButtons()[1], 48, 48)
            H.expectSize(g, pad() * 2 + 2 * 48, pad() * 2 + 48)
        end)

        it("defers a row change too, not only a resize", function()
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32, spacing = 0 })
            H.setCombat(true)
            H.resetBlockedActions()
            g:SetRows(2)
            expect(#H.getBlockedActions()).eq(0)
            expect(g:IsDeferred()).truthy()
            H.setCombat(false)
            H.expectSize(g, pad() * 2 + 2 * 32, pad() * 2 + 2 * 32)
        end)

        it("applies a readout toggle immediately, even in combat", function()
            -- A font string showing or hiding is not protected, so deferring it would be
            -- pointless caution the player would experience as a setting that does nothing.
            H.setBinding("ACTIONBUTTON1", "1")
            H.setAction(1, { texture = "i" }, { silent = true })
            local g = build({ slots = { 1 }, buttonSize = 32,
                              bindings = { "ACTIONBUTTON1" } })
            expect(g:GetButtons()[1]._hotkeyText:IsShown()).truthy()
            H.setCombat(true)
            H.resetBlockedActions()
            g:SetShowHotkeys(false)
            expect(g:GetButtons()[1]._hotkeyText:IsShown()).falsy()
            expect(#H.getBlockedActions()).eq(0)
        end)

        it("refreshes actions in combat, which is not protected either", function()
            local g = build({ slots = { 1 }, buttonSize = 32 })
            H.setCombat(true)
            H.resetBlockedActions()
            H.setAction(1, { texture = "Interface\\Icons\\Live" })
            expect(g:GetButtons()[1]._iconComp:GetIcon()).eq("Interface\\Icons\\Live")
            expect(#H.getBlockedActions()).eq(0)
        end)
    end)

    describe("slots and bindings", function()
        it("hands each button its slot and its binding command", function()
            H.setBinding("ACTIONBUTTON2", "2")
            local g = build({ slots = { 1, 2 }, buttonSize = 32,
                              bindings = { "ACTIONBUTTON1", "ACTIONBUTTON2" } })
            expect(g:GetButtons()[2]:GetSlot()).eq(2)
            expect(g:GetButtons()[2]._hotkeyText:GetText()).eq("2")
        end)

        it("rebuilds when the slot list shrinks", function()
            local g = build({ slots = { 1, 2, 3, 4 }, buttonSize = 32 })
            expect(#g:GetButtons()).eq(4)
            g:SetSlots({ 1, 2 })
            expect(#g:GetButtons()).eq(2)
            H.expectSize(g, pad() * 2 + 2 * 32, pad() * 2 + 32)
        end)

        it("recreates rather than re-points a button whose slot changed", function()
            -- Re-pointing means SetAttribute on a protected frame, which the client refuses in
            -- combat and which the component's own contract forbids.
            local g = build({ slots = { 1 }, buttonSize = 32 })
            local before = g:GetButtons()[1]
            g:SetSlots({ 61 })
            local after = g:GetButtons()[1]
            expect(after:GetSlot()).eq(61)
            expect(after == before).as("a different button object").falsy()
        end)

        it("reports its slots as a copy, not the live array", function()
            local g = build({ slots = { 1, 2 }, buttonSize = 32 })
            local got = g:GetSlots()
            got[1] = 99
            expect(g:GetSlots()[1]).as("the grid kept its own").eq(1)
        end)
    end)

    describe("teardown", function()
        it("destroys its buttons and stops the shared watcher", function()
            local g = build()
            expect(H.SuuUI._ActionBarGridInternals.liveCount()).eq(1)
            g:Destroy()
            expect(H.SuuUI._ActionBarGridInternals.liveCount()).eq(0)
            expect(H.SuuUI._ActionButtonInternals.liveCount())
                .as("its buttons went with it").eq(0)
        end)

        it("survives a theme change after being destroyed", function()
            local g = build()
            g:Destroy()
            expect(function() H.T:SetActive("Default") end).notThrows()
        end)
    end)
end)

describe("Plugins.ActionBars", function()
    local PLUGIN = "action_bars"

    before_each(function()
        H.setup()
    end)

    local function bar(id)
        return H.SuuUI.Plugins:Get(PLUGIN)._bars[id or 1]
    end

    it("builds bar 1 on login", function()
        expect(bar()).notNil()
        expect(#bar():GetButtons()).eq(12)
    end)

    it("points bar 1 at slots 1..12, the paged main bar", function()
        local buttons = bar():GetButtons()
        expect(buttons[1]:GetSlot()).eq(1)
        expect(buttons[12]:GetSlot()).eq(12)
    end)

    it("binds each button to its ACTIONBUTTON command", function()
        H.setBinding("ACTIONBUTTON5", "5")
        H.fireEvent("UPDATE_BINDINGS")
        expect(bar():GetButtons()[5]._hotkeyText:GetText()).eq("5")
    end)

    it("gets the BUTTONS off the screen, not just their containers", function()
        -- The end, not the means. This module shipped a version where every container it named was
        -- hidden, IsSuppressed reported success for all of them, and all twelve buttons were still
        -- on screen -- because the buttons live in MainActionBar and the list only knew
        -- MainMenuBar. Verify() asks the buttons directly.
        expect(H.SuuUI._ActionBars.Suppress.Verify())
            .as("buttons still visible: " ..
                table.concat(H.SuuUI._ActionBars.Suppress.Verify(), ", ")).len(0)
        for _, name in ipairs(H.SuuUI._ActionBars.Suppress.WITNESS_BUTTONS) do
            local b = H.env[name]
            if b then
                expect(b:IsVisible()).as(name .. " is off screen").falsy()
            end
        end
    end)

    it("hides EVERY name in a candidate list, not just the first", function()
        -- MainActionBar and MainMenuBar coexist on this client -- one holds the buttons, the other
        -- the art -- so first-match-wins hid one and left the other. A rename list is unaffected,
        -- since only one of its names ever exists.
        local S = H.SuuUI._ActionBars.Suppress
        expect(S.IsSuppressed("MainActionBar")).as("the button container").truthy()
        expect(S.IsSuppressed("MainMenuBar")).as("AND the art frame").truthy()
    end)

    it("hides Blizzard's bottom cluster", function()
        local S = H.SuuUI._ActionBars.Suppress
        for _, name in ipairs({ "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
                                "MultiBarLeft", "MultiBarRight", "MainMenuBarArtFrame",
                                "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" }) do
            if H.env[name] then
                expect(H.env[name]:IsShown()).as(name .. " is hidden").falsy()
                expect(S.IsSuppressed(name)).as(name .. " is claimed").truthy()
            end
        end
    end)

    it("leaves alone everything a later phase replaces", function()
        -- Hiding these now would take away function the player still needs: the micro menu is
        -- Phase 7, the bags Phase 9, the watch bars Phase 8, the class bars Phase 6.
        for _, name in ipairs({ "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar",
                                "StatusTrackingBarManager", "StanceBar", "PetActionBar",
                                "MainMenuBarBackpackButton" }) do
            local f = H.env[name]
            if f then
                expect(H.SuuUI._ActionBars.Suppress.IsSuppressed(name))
                    .as(name .. " is not this phase's business").falsy()
            end
        end
    end)

    it("does not take the micro menu down with MainMenuBar", function()
        -- MEASURED, not assumed: MicroMenu's parent is MicroMenuContainer, so hiding the bar
        -- cluster spares it. Had it been a child of MainMenuBar this phase would have cost the
        -- player their character pane, spellbook and bags until Phase 7 -- so the parentage is
        -- pinned here rather than left as a fact someone once checked.
        expect(H.env.MicroMenu:GetParent()).eq(H.env.MicroMenuContainer)
        expect(H.env.MainMenuBar:IsShown()).as("the bar is hidden").falsy()
        expect(H.env.MicroMenu:IsShown()).as("the micro menu is not").truthy()
    end)

    it("registers the bar as a moveable element", function()
        expect(bar():GetFrame()._suuui_moveable).notNil()
    end)

    it("stores its position under a position entry with no control", function()
        local entry
        for _, e in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN)) do
            if e.key == "bar1_position" then entry = e end
        end
        expect(entry).notNil()
        expect(entry.type).eq("position")
    end)

    it("keeps the enable toggle out in front of every section", function()
        local schema = H.SuuUI.Settings:GetSchema(PLUGIN)
        local sawSection = false
        for _, e in ipairs(schema) do
            if e.type == "section" then sawSection = true end
            if e.key == "enabled" then
                expect(sawSection).as("enabled sits before any group").falsy()
            end
        end
    end)

    it("applies the button count setting", function()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 6)
        expect(#bar():GetButtons()).eq(6)
    end)

    it("applies the button size setting", function()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_button_size", 44)
        H.expectSize(bar():GetButtons()[1], 44, 44)
    end)

    it("defers a size change made in combat, then applies it", function()
        H.setCombat(true)
        H.resetBlockedActions()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_button_size", 44)
        expect(#H.getBlockedActions()).as("nothing refused").eq(0)
        expect(bar():IsDeferred()).truthy()
        H.setCombat(false)
        H.expectSize(bar():GetButtons()[1], 44, 44)
    end)

    it("takes the bar down and puts it back on the bar toggle", function()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", false)
        expect(bar()).isNil()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", true)
        expect(bar()).notNil()
        expect(#bar():GetButtons()).eq(12)
    end)

    it("drops the bar and its watchers when the plugin is disabled", function()
        H.SuuUI.Settings:Set(PLUGIN, "enabled", false)
        expect(bar()).isNil()
        -- No watcher left to act on a stale handle.
        expect(function() H.SuuUI.Settings:Set(PLUGIN, "bar1_button_size", 50) end).notThrows()
    end)
end)

describe("Plugins.ActionBars: suppression", function()
    local PLUGIN = "action_bars"
    local S

    before_each(function()
        H.setup()
        S = H.SuuUI._ActionBars.Suppress
    end)

    local function bar(name)
        return H.env[name]
    end

    describe("the guarded OnShow hook", function()
        it("re-hides a frame that shows itself again", function()
            -- MainMenuBar is layout-managed on this client, so it re-shows on a login, a layout
            -- change, and whenever UIParent_ManageFramePositions runs. A one-shot Hide is
            -- therefore reverted, which is the whole reason the hook exists.
            local f = bar("MainMenuBar")
            expect(f:IsShown()).falsy()
            f:Show()
            expect(f:IsShown()).as("the hook put it back").falsy()
        end)

        it("stops re-hiding once suppression is released", function()
            -- HookScript cannot be undone, so the hook asks `suppressed` on every call rather
            -- than assuming. Without that, onDisable could never hand the frame back.
            local f = bar("MainMenuBar")
            S.Restore()
            expect(f:IsShown()).as("restored").truthy()
            f:Hide()
            f:Show()
            expect(f:IsShown()).as("the hook is inert now").truthy()
        end)

        it("undoes any number of Applies with one Restore", function()
            -- Not "installs no second hook": two hooks would both consult `suppressed` and both
            -- decline, so a duplicate is unobservable from outside and asserting it would be
            -- asserting nothing. What a player can actually tell is this.
            S.Apply()
            S.Apply()
            local f = bar("MainMenuBar")
            S.Restore()
            expect(f:IsShown()).as("one Restore is enough").truthy()
        end)

        it("is why the deferral exists: the BUTTON container is protected, the art is not", function()
            -- Pins the asymmetry the whole combat path is built on, and the measured tree moved it:
            -- MainActionBar holds the client's own secure buttons, so hiding IT is refused
            -- mid-fight, while MainMenuBar carries only art and is not protected at all. The
            -- deferral covers both anyway -- see doHide -- because half a cluster vanishing mid-
            -- fight reads as a bug.
            expect(H.hasProtectedDescendant(bar("MainActionBar")))
                .as("the button container holds Blizzard's secure buttons").truthy()
            expect(H.hasProtectedDescendant(bar("MainMenuBar")))
                .as("the art frame holds none").falsy()
            expect(bar("MainMenuBarArtFrame"):IsProtected())
                .as("and the art has no secure ancestor either").falsy()
        end)
    end)

    describe("combat", function()
        it("does not attempt a hide it knows will be refused", function()
            -- Hiding a Blizzard action bar is PROTECTED: MainMenuBar holds ActionButton1..12,
            -- which are secure, so the refusal propagates up to the bar. Attempting it costs
            -- the player a chat error for a call we already knew would not land.
            S.Restore()
            H.setCombat(true)
            H.resetBlockedActions()

            S.Apply()

            expect(#H.getBlockedActions()).as("nothing was refused").eq(0)
            expect(S.IsDeferred()).as("it deferred instead").truthy()
            expect(bar("MainMenuBar"):IsShown()).as("still visible for now").truthy()
        end)

        it("completes the hide when the fight ends", function()
            S.Restore()
            H.setCombat(true)
            S.Apply()
            H.setCombat(false)
            expect(S.IsDeferred()).falsy()
            expect(bar("MainMenuBar"):IsShown()).falsy()
        end)

        it("defers the RESTORE too, which is the escape hatch", function()
            -- Show() is refused on the way back out for exactly the same reason Hide() is. A
            -- player disabling this mid-fight must still get their bars back afterwards rather
            -- than being left with neither.
            H.setCombat(true)
            H.resetBlockedActions()

            S.Restore()

            expect(#H.getBlockedActions()).eq(0)
            expect(S.IsDeferred()).truthy()
            H.setCombat(false)
            expect(bar("MainMenuBar"):IsShown()).as("handed back after the fight").truthy()
        end)

        it("does not re-hide a frame released while the hide was still pending", function()
            S.Restore()
            H.setCombat(true)
            S.Apply()          -- queued
            S.Restore()        -- released before the queue drained
            H.setCombat(false)
            expect(bar("MainMenuBar"):IsShown())
                .as("a released frame stays visible").truthy()
        end)

        it("lets the LAST instruction win when suppression is re-enabled mid-fight", function()
            -- The reachable half of the pair above. Apply cancels a pending restore just as
            -- Restore cancels a pending hide, so whichever the player asked for last is what
            -- they get when the fight ends -- rather than an order-of-drain lottery.
            H.setCombat(true)
            S.Restore()        -- queues a restore
            S.Apply()          -- cancels it and queues a hide instead
            H.setCombat(false)
            expect(bar("MainMenuBar"):IsShown())
                .as("the later Apply won").falsy()
        end)
    end)

    describe("the toggle", function()
        it("hands Blizzard's bars back immediately when switched off", function()
            H.SuuUI.Settings:Set(PLUGIN, "hide_blizzard", false)
            expect(bar("MainMenuBar"):IsShown()).truthy()
            expect(S.IsSuppressed("MainMenuBar")).falsy()
        end)

        it("takes them away again when switched back on", function()
            H.SuuUI.Settings:Set(PLUGIN, "hide_blizzard", false)
            H.SuuUI.Settings:Set(PLUGIN, "hide_blizzard", true)
            expect(bar("MainMenuBar"):IsShown()).falsy()
        end)

        it("leaves SuuUI's own bar up when suppression is off", function()
            -- The point of a separate toggle: both bars on screen at once is a legitimate
            -- state, and it is what a player debugging their own setup wants.
            H.SuuUI.Settings:Set(PLUGIN, "hide_blizzard", false)
            expect(H.SuuUI.Plugins:Get(PLUGIN)._bars[1]).notNil()
        end)

        it("sits before any section, so it is findable", function()
            local schema = H.SuuUI.Settings:GetSchema(PLUGIN)
            local sawSection = false
            for _, e in ipairs(schema) do
                if e.type == "section" then sawSection = true end
                if e.key == "hide_blizzard" then
                    expect(sawSection).as("the escape hatch is not inside a group").falsy()
                end
            end
        end)
    end)

    describe("disabling the plugin", function()
        it("hands Blizzard's cluster back", function()
            H.SuuUI.Settings:Set(PLUGIN, "enabled", false)
            expect(bar("MainMenuBar"):IsShown()).truthy()
            expect(bar("MultiBarBottomLeft"):IsShown()).truthy()
        end)

        it("never leaves the player with neither bar", function()
            H.SuuUI.Settings:Set(PLUGIN, "enabled", false)
            expect(H.SuuUI.Plugins:Get(PLUGIN)._bars[1]).as("ours is gone").isNil()
            expect(bar("MainMenuBar"):IsShown()).as("so theirs must be back").truthy()
        end)
    end)

    describe("resolution", function()
        it("resolves targets by candidate list, skipping what this client lacks", function()
            -- The Phase 0 results are a snapshot of ONE build, and this client is already
            -- mid-migration. A patch that renames a frame must degrade to "not hidden", never
            -- to an error.
            local found = S.Apply()
            expect(#found).as("something resolved").gt(0)
            for _, entry in ipairs(S.TARGETS) do
                expect(type(entry.names)).as(entry.id .. " has a candidate list").eq("table")
                expect(#entry.names).gte(1)
            end
        end)

        it("does not raise for a target no client has", function()
            local original = S.TARGETS[1].names
            S.TARGETS[1].names = { "SuuUINoSuchFrameAnywhere" }
            expect(function() S.Apply() end).notThrows()
            S.TARGETS[1].names = original
        end)
    end)
end)

describe("Plugins.ActionBars: every bar", function()
    local PLUGIN = "action_bars"

    before_each(function() H.setup() end)

    local function bars()
        return H.SuuUI.Plugins:Get(PLUGIN)._bars
    end

    local function enable(id)
        H.SuuUI.Settings:Set(PLUGIN, "bar" .. id .. "_enabled", true)
        return bars()[id]
    end

    it("points every bar at the slot block MEASURED in game", function()
        -- Round 3 of the Phase 0 probes, not a guess: ActionButton1.action was 1,
        -- MultiBarBottomLeftButton1 was 61, BottomRight 49, Left 37, Right 25.
        local expected = { [1] = 1, [2] = 61, [3] = 49, [4] = 37, [5] = 25 }
        for id, first in pairs(expected) do
            local grid = enable(id)
            expect(grid).as("bar " .. id .. " exists").notNil()
            expect(grid:GetButtons()[1]:GetSlot()).as("bar " .. id .. " starts at " .. first)
                .eq(first)
            expect(grid:GetButtons()[12]:GetSlot()).eq(first + 11)
        end
    end)

    it("ships with bars 1 and 2 on, every other one off", function()
        -- Eight bars at first login is ninety-six buttons nobody asked for. Blizzard itself shows two.
        expect(bars()[1]).as("bar 1 on").notNil()
        expect(bars()[2]).as("bar 2 on").notNil()
        for _, def in ipairs(H.SuuUI._ActionBars.BARS) do
            if def.id > 2 then
                expect(bars()[def.id]).as("bar " .. def.id .. " off").isNil()
            end
        end
    end)

    it("pairs every bar's slot block with the binding family MEASURED for it", function()
        -- Both halves came from in-game probes, and the binding half caught a real error: the
        -- numbering does NOT follow the frame names in the order it looks like it should.
        -- MultiBarLeft is MULTIACTIONBAR4 and MultiBarRight is MULTIACTIONBAR3, which is the
        -- reverse of the obvious guess -- and the guess shipped until Blizzard's own buttonType
        -- field was read. Pinned as a table so a "tidy-up" cannot quietly renumber them.
        local measured = {
            [1] = { first = 1,   prefix = "ACTIONBUTTON" },            -- MainActionBar
            [2] = { first = 61,  prefix = "MULTIACTIONBAR1BUTTON" },   -- MultiBarBottomLeft
            [3] = { first = 49,  prefix = "MULTIACTIONBAR2BUTTON" },   -- MultiBarBottomRight
            [4] = { first = 37,  prefix = "MULTIACTIONBAR4BUTTON" },   -- MultiBarLeft  -> 4, not 3
            [5] = { first = 25,  prefix = "MULTIACTIONBAR3BUTTON" },   -- MultiBarRight -> 3, not 4
            -- Here the numbering DOES follow the frame name, which is why every pairing above and
            -- below was read off Blizzard's own buttonType rather than inferred from a rule.
            [6] = { first = 145, prefix = "MULTIACTIONBAR5BUTTON" },   -- MultiBar5
            [7] = { first = 157, prefix = "MULTIACTIONBAR6BUTTON" },   -- MultiBar6
            [8] = { first = 169, prefix = "MULTIACTIONBAR7BUTTON" },   -- MultiBar7
        }
        for _, def in ipairs(H.SuuUI._ActionBars.BARS) do
            local want = measured[def.id]
            expect(want).as("bar " .. def.id .. " is a known bar").notNil()
            expect(def.first).as("bar " .. def.id .. " slot block").eq(want.first)
            expect(def.bindingPrefix).as("bar " .. def.id .. " binding family").eq(want.prefix)
        end
    end)

    it("gives each bar its own binding command family", function()
        H.setBinding("ACTIONBUTTON1", "1")
        H.setBinding("MULTIACTIONBAR1BUTTON1", "F1")
        H.fireEvent("UPDATE_BINDINGS")
        expect(bars()[1]:GetButtons()[1]._hotkeyText:GetText()).eq("1")
        expect(bars()[2]:GetButtons()[1]._hotkeyText:GetText()).eq("F1")
    end)

    it("reads bar 4 and bar 5's hotkeys from the swapped families", function()
        H.setBinding("MULTIACTIONBAR4BUTTON1", "L")
        H.setBinding("MULTIACTIONBAR3BUTTON1", "R")
        enable(4)
        enable(5)
        H.fireEvent("UPDATE_BINDINGS")
        expect(bars()[4]:GetButtons()[1]._hotkeyText:GetText()).as("bar 4 is family 4").eq("L")
        expect(bars()[5]:GetButtons()[1]._hotkeyText:GetText()).as("bar 5 is family 3").eq("R")
    end)

    it("positions each bar independently", function()
        local one, two = bars()[1]:GetFrame(), bars()[2]:GetFrame()
        expect(one._suuui_moveable).notNil()
        expect(two._suuui_moveable).notNil()
        expect(one._suuui_moveable.key).eq("bar1_position")
        expect(two._suuui_moveable.key).eq("bar2_position")
        expect(H.box(one).top == H.box(two).top)
            .as("and they do not sit on top of each other").falsy()
    end)

    it("stands bars 4 and 5 up as a single column", function()
        local four = enable(4)
        expect(four:GetButtons()[1]).notNil()
        local a, b = H.box(four:GetButtons()[1]), H.box(four:GetButtons()[2])
        expect(a.left).as("same column").eq(b.left)
        expect(b.top).as("stacked downward").eq(a.bottom)
    end)

    it("sizes each bar independently of the others", function()
        H.SuuUI.Settings:Set(PLUGIN, "bar2_button_size", 44)
        H.expectSize(bars()[2]:GetButtons()[1], 44, 44)
        H.expectSize(bars()[1]:GetButtons()[1], 32, 32)
    end)

    it("takes one bar down without touching the others", function()
        H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", false)
        expect(bars()[1]).isNil()
        expect(bars()[2]).as("bar 2 is unaffected").notNil()
    end)

    describe("the schema", function()
        local function schema()
            return H.SuuUI.Settings:GetSchema(PLUGIN)
        end

        it("gives every bar its own tab", function()
            -- Counted off the bar table, not a literal: this spec said 5 until the client turned out
            -- to have 8, and a hardcoded count in a spec is a second place to forget.
            local bars = H.SuuUI._ActionBars.BARS
            local subtabs
            for _, e in ipairs(schema()) do
                if e.type == "subtabs" then subtabs = e end
            end
            expect(subtabs).notNil()
            expect(#subtabs.tabs).eq(#bars)
            expect(subtabs.tabs[1].label).eq("Bar 1")
            expect(subtabs.tabs[#bars].label).eq("Bar " .. bars[#bars].id)
        end)

        it("declares every key exactly ONCE", function()
            -- Settings:Register indexes by key, so a key appearing twice would have one control
            -- writing another's value -- and with five near-identical tabs built from one
            -- template, a missing bar id in a key is exactly the typo that produces it.
            local seen, dupes = {}, {}
            local function visit(entries)
                for _, e in ipairs(entries) do
                    if e.type == "subtabs" then
                        for _, tab in ipairs(e.tabs) do visit(tab.schema) end
                    elseif e.key and e.key ~= "" then
                        if seen[e.key] then dupes[#dupes + 1] = e.key end
                        seen[e.key] = true
                    end
                end
            end
            visit(schema())
            expect(dupes).as("duplicate keys: " .. table.concat(dupes, ", ")).len(0)
        end)

        it("carries a position entry per bar, with no control", function()
            local found = 0
            for _, e in ipairs(schema()) do
                if e.type == "position" then found = found + 1 end
            end
            expect(found).eq(#H.SuuUI._ActionBars.BARS)
        end)
    end)
end)

describe("Plugins.ActionBars: secure paging", function()
    local PLUGIN = "action_bars"
    local P

    before_each(function()
        H.setup()
        P = H.SuuUI._ActionBars.Paging
    end)

    local function grid(id)
        return H.SuuUI.Plugins:Get(PLUGIN)._bars[id or 1]
    end

    it("drives ONLY bar 1, because only bar 1's slots move", function()
        -- Round 3 again: the four multibars are fixed to their block, so a driver on them would
        -- be a secure header doing nothing. That finding removed four of them from this phase.
        expect(P.HeaderFor(grid(1))).as("bar 1 is paged").notNil()
        H.SuuUI.Settings:Set(PLUGIN, "bar3_enabled", true)
        expect(P.HeaderFor(grid(3))).as("bar 3 is not").isNil()
    end)

    it("registers a state driver on a secure header", function()
        local header = P.HeaderFor(grid(1))
        expect(header:IsProtected()).as("built from a Secure template").truthy()
        expect(H.getStateDriver(header, "page")).eq(P.DRIVER)
    end)

    it("orders the driver highest page first, or it never leaves page 1", function()
        -- A macro conditional list is FIRST-MATCH-WINS. Written low-to-high, [bar:1] would match
        -- before anything else was tested and the bar would be stuck -- which looks identical to
        -- paging never having been wired up.
        local sixth = string.find(P.DRIVER, "%[bar:6%]")
        local second = string.find(P.DRIVER, "%[bar:2%]")
        expect(sixth).notNil()
        expect(second).notNil()
        expect(sixth).as("page 6 is tested before page 2").lt(second)
        expect(P.DRIVER:sub(-2)).as("and 1 is the fallthrough").eq(";1")
    end)

    it("hands the snippet everything it needs as attributes and refs", function()
        -- A snippet is a string the client compiles, so it captures no upvalue and can see
        -- nothing from the Lua side except what was set out of combat.
        local header = P.HeaderFor(grid(1))
        expect(header:GetAttribute("_onstate-page")).eq(P.SNIPPET)
        expect(header:GetAttribute("pageSize")).eq(12)
        expect(header:GetAttribute("buttonCount")).eq(12)
        for i = 1, 12 do
            expect(header:GetFrameRef("button" .. i))
                .as("ref for button " .. i).notNil()
        end
    end)

    it("references the ACTUAL buttons, not stale ones", function()
        local header = P.HeaderFor(grid(1))
        expect(header:GetFrameRef("button1")).eq(grid(1):GetButtons()[1]:GetFrame())
    end)

    it("re-states its refs when the bar is rebuilt", function()
        -- Shrinking REUSES the buttons whose slots did not move, so button 1 is deliberately the
        -- same frame -- what has to follow is the COUNT, which is what bounds the snippet's loop.
        local header = P.HeaderFor(grid(1))
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 6)
        expect(header:GetAttribute("buttonCount")).as("count followed").eq(6)
        for i = 1, 6 do
            expect(header:GetFrameRef("button" .. i))
                .as("ref " .. i .. " is the current button")
                .eq(grid(1):GetButtons()[i]:GetFrame())
        end
    end)

    it("re-states its refs when a bar GROWS, which creates new frames", function()
        local header = P.HeaderFor(grid(1))
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 4)
        local shrunk = header:GetFrameRef("button4")
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 12)
        expect(header:GetAttribute("buttonCount")).eq(12)
        expect(header:GetFrameRef("button12")).as("the new tail is referenced")
            .eq(grid(1):GetButtons()[12]:GetFrame())
        expect(shrunk).notNil()
    end)

    it("bounds the snippet by buttonCount, NOT by the ref set", function()
        -- Shrinking leaves refs 5..12 pointing at destroyed frames. They are inert because the
        -- snippet loops to buttonCount, and clearing them would mean SetFrameRef(name, nil),
        -- whose behaviour on this client is unverified. The count is the contract; this pins that
        -- the snippet actually reads it rather than iterating whatever refs happen to exist.
        local header = P.HeaderFor(grid(1))
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 4)
        expect(header:GetAttribute("buttonCount")).eq(4)
        expect(P.SNIPPET:find("buttonCount")).as("the snippet reads the count").notNil()
        expect(P.SNIPPET:find("for i = 1, count do")).as("and loops to it").notNil()
    end)

    it("re-states its refs after a rebuild DEFERRED by combat", function()
        -- The case CHILDREN_CHANGED exists for. Watching the setting would fire while the old
        -- buttons were still on screen; only the grid knows when the fight-delayed rebuild
        -- actually happened.
        local header = P.HeaderFor(grid(1))
        H.setCombat(true)
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 4)
        expect(header:GetAttribute("buttonCount")).as("nothing rebuilt yet").eq(12)

        H.setCombat(false)

        expect(header:GetAttribute("buttonCount")).as("caught up after the fight").eq(4)
        expect(header:GetFrameRef("button1")).eq(grid(1):GetButtons()[1]:GetFrame())
    end)

    it("announces a rebuild ONLY when the button set actually moved", function()
        -- Counted, not inferred from the refs: re-syncing writes the SAME frame for a button that
        -- was reused, so comparing a ref before and after cannot tell a spurious re-sync from no
        -- re-sync at all. Mutation testing is what exposed that -- the earlier version of this
        -- test passed with the guard removed.
        local g = grid(1)
        local spy = H.signalSpy(g, H.S.SIGNALS.CHILDREN_CHANGED)
        H.SuuUI.Settings:Set(PLUGIN, "bar1_spacing", 4)
        expect(spy.count).as("spacing rebuilt nothing").eq(0)
        H.SuuUI.Settings:Set(PLUGIN, "bar1_button_size", 40)
        expect(spy.count).as("nor did a resize -- buttons are reused").eq(0)
        H.SuuUI.Settings:Set(PLUGIN, "bar1_buttons", 6)
        expect(spy.count).as("a count change did").eq(1)
    end)

    it("releases the driver and the subscription on detach", function()
        local g = grid(1)
        local header = P.HeaderFor(g)
        local SIG = H.S.SIGNALS.CHILDREN_CHANGED
        -- Asserted directly, because the callback's own `if h then` guard makes a LEAKED
        -- subscription behave identically to a released one -- it just holds a closure forever.
        -- HasConnections returns a real boolean, so this cannot fall for a zero-is-truthy count.
        expect(H.SuuUI.UISignals:HasConnections(g, SIG)).as("subscribed while attached").truthy()

        P.Detach(g)

        expect(P.HeaderFor(g)).isNil()
        expect(H.getStateDriver(header, "page")).isNil()
        expect(H.SuuUI.UISignals:HasConnections(g, SIG))
            .as("and unsubscribed after").falsy()
        expect(function() g:SetSlots({ 1, 2 }) end).notThrows()
    end)

    it("goes away with the bar", function()
        local g = grid(1)
        H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", false)
        expect(P.HeaderFor(g)).isNil()
    end)
end)

describe("Plugins.ActionBars: bar-to-bar docking", function()
    local PLUGIN = "action_bars"
    local D

    before_each(function()
        H.setup()
        D = H.SuuUI._ActionBars.Dock
    end)

    local function bars()
        return H.SuuUI.Plugins:Get(PLUGIN)._bars
    end

    local function enable(id)
        H.SuuUI.Settings:Set(PLUGIN, "bar" .. id .. "_enabled", true)
        return bars()[id]
    end

    -- Attaches bar `id` to bar `toId` on `edge`. Enables both first: bars 3 to 8 ship OFF, so setting
    -- attach alone would leave nothing to dock and every assertion below would describe a bar that
    -- does not exist.
    local function attach(id, toId, edge)
        enable(id)
        if toId then enable(toId) end
        if edge then H.SuuUI.Settings:Set(PLUGIN, "bar" .. id .. "_attach_edge", edge) end
        H.SuuUI.Settings:Set(PLUGIN, "bar" .. id .. "_attach",
            toId and tostring(toId) or "detached")
        return bars()[id]
    end

    local function gap()
        return H.token("spaceXxs") or 2
    end

    describe("any bar can be a dock", function()
        it("publishes an attach point per bar, not one for bar 1", function()
            -- Published regardless of whether anything is attached, because Request fires immediately
            -- with whatever is there: a bar waiting on one that does not exist yet is then not a
            -- special case.
            expect(H.SuuUI.AttachPoints:Has("actionbar.dock.1")).truthy()
            expect(H.SuuUI.AttachPoints:Has("actionbar.dock.2")).truthy()
            enable(5)
            expect(H.SuuUI.AttachPoints:Has("actionbar.dock.5")).truthy()
            expect(H.SuuUI.AttachPoints:Get("actionbar.dock.2").frame)
                .eq(bars()[2]:GetFrame())
        end)

        it("attaches one bar to another that is not bar 1", function()
            -- The whole point of the generalisation: bars 4 and 5 are vertical columns on the right
            -- edge, and grouping THEM is the obvious thing to want.
            local four = attach(4, 5, "left")
            expect(D.ParentOf(four)).eq(bars()[5])
            expect(D.Children(bars()[5])).len(1)
            expect(D.Children(bars()[1])).as("bar 1 is not involved").len(0)
        end)

        it("lets bar 1 attach to another bar too", function()
            -- Bar 1 used to be the only dock and could not itself attach. It is just a bar now.
            local one = attach(1, 2, "below")
            expect(D.ParentOf(one)).eq(bars()[2])
        end)

        it("moves a bar between docks rather than giving it two parents", function()
            local three = attach(3, 1)
            expect(D.Children(bars()[1])).len(1)
            attach(3, 2)
            expect(D.ParentOf(three)).eq(bars()[2])
            expect(D.Children(bars()[1])).as("left the first dock").len(0)
            expect(D.Children(bars()[2])).len(1)
        end)
    end)

    describe("edges", function()
        -- H.box measures DOWNWARD, so a smaller bottom/top is higher up the screen.
        it("stacks above", function()
            local child = attach(2, 1, "above")
            expect(H.box(child).bottom).eq(H.box(bars()[1]).top - gap())
        end)

        it("stacks below", function()
            local child = attach(2, 1, "below")
            expect(H.box(child).top).eq(H.box(bars()[1]).bottom + gap())
        end)

        it("stacks left", function()
            local child = attach(2, 1, "left")
            expect(H.box(child).right).eq(H.box(bars()[1]).left - gap())
        end)

        it("stacks right", function()
            local child = attach(2, 1, "right")
            expect(H.box(child).left).eq(H.box(bars()[1]).right + gap())
        end)

        it("moves a bar to the other edge when the setting changes", function()
            local child = attach(2, 1, "above")
            expect(H.box(child).bottom).eq(H.box(bars()[1]).top - gap())
            H.SuuUI.Settings:Set(PLUGIN, "bar2_attach_edge", "below")
            expect(H.box(child).top).eq(H.box(bars()[1]).bottom + gap())
        end)

        it("stacks each edge independently", function()
            -- Two bars on one edge queue behind each other; a bar on a different edge starts fresh.
            attach(2, 1, "above")
            attach(3, 1, "above")
            attach(4, 1, "below")
            expect(H.box(bars()[3]).bottom).as("bar 3 queues above bar 2")
                .eq(H.box(bars()[2]).top - gap())
            expect(H.box(bars()[4]).top).as("bar 4 starts fresh below bar 1")
                .eq(H.box(bars()[1]).bottom + gap())
        end)

        it("leaves a gap rather than butting the plates together", function()
            -- Each bar carries its own glass plate with its own gradient, so flush plates show a seam
            -- where one's fade meets the next one's dense edge.
            local child = attach(2, 1, "above")
            expect(H.box(bars()[1]).top - H.box(child).bottom).eq(gap())
        end)
    end)

    describe("chains", function()
        it("carries a whole chain when the root moves", function()
            -- Nothing is recomputed for this: an anchor is a live relationship, so bar 1 moving moves
            -- bar 2, which moves bar 3. That is why chains needed no extra machinery.
            attach(2, 1, "above")
            attach(3, 2, "above")
            local before = H.box(bars()[3]).bottom
            H.SuuUI.Settings:Set(PLUGIN, "bar1_position",
                { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 300 })
            expect(H.box(bars()[3]).bottom).as("the tail followed the root upward").lt(before)
            expect(H.box(bars()[3]).bottom).eq(H.box(bars()[2]).top - gap())
        end)

        it("re-stacks a chain when a bar in the middle changes height", function()
            attach(2, 1, "above")
            attach(3, 2, "above")
            local before = H.box(bars()[3]).bottom
            H.SuuUI.Settings:Set(PLUGIN, "bar2_rows", 2)
            expect(H.box(bars()[3]).bottom).as("bar 3 moved for bar 2's second row").lt(before)
        end)

        it("re-stacks TWO bars on ONE edge when the first changes height", function()
            -- The case the SIZE_CHANGED subscription actually exists for, and the chain test above
            -- does NOT cover it: in a chain each bar is anchored to the one below it, so a live anchor
            -- carries the change for free. Two bars on the same edge of the same dock both anchor to
            -- the DOCK, so the second one's offset is computed from the first one's span -- and only a
            -- reflow recomputes that. Mutation testing found this hole.
            attach(2, 1, "above")
            attach(3, 1, "above")
            local before = H.box(bars()[3]).bottom
            H.SuuUI.Settings:Set(PLUGIN, "bar2_rows", 2)
            expect(H.box(bars()[3]).bottom).as("bar 3 made room for bar 2's second row").lt(before)
            expect(H.box(bars()[3]).bottom).eq(H.box(bars()[2]).top - gap())
        end)
    end)

    describe("cycles", function()
        it("REJECTS a two-bar loop at the settings layer", function()
            -- A circular anchor is not a cosmetic fault: the client raises a hard error and leaves the
            -- frame unplaced. Rejected before the value is stored, so the dropdown can never show a
            -- state that is not in effect.
            attach(2, 1)
            enable(1)
            H.SuuUI.Settings:Set(PLUGIN, "bar1_attach", "2")
            expect(H.SuuUI.Settings:Get(PLUGIN, "bar1_attach"))
                .as("the write was refused").eq("detached")
            expect(D.ParentOf(bars()[1])).isNil()
        end)

        it("REJECTS a longer loop", function()
            attach(2, 1)
            attach(3, 2)
            H.SuuUI.Settings:Set(PLUGIN, "bar1_attach", "3")
            expect(H.SuuUI.Settings:Get(PLUGIN, "bar1_attach")).eq("detached")
        end)

        it("REJECTS a bar attaching to itself", function()
            H.SuuUI.Settings:Set(PLUGIN, "bar2_attach", "2")
            expect(H.SuuUI.Settings:Get(PLUGIN, "bar2_attach")).eq("detached")
        end)

        it("refuses one in the dock too, as a backstop for an old profile", function()
            -- The validator guards new writes; a profile written before it existed could still carry
            -- a loop, so Attach checks as well rather than trusting its caller.
            local one, two = bars()[1], enable(2)
            expect(D.Attach(one, two, {})).truthy()
            expect(D.Attach(two, one, {})).as("the loop is refused").falsy()
            expect(D.ParentOf(one)).isNil()
        end)

        it("still allows a legitimate re-parent that is not a loop", function()
            attach(3, 2)
            attach(2, 1)
            expect(D.ParentOf(bars()[3])).eq(bars()[2])
            expect(D.ParentOf(bars()[2])).eq(bars()[1])
        end)
    end)

    describe("position ownership", function()
        it("takes the moveable frame AWAY from an attached bar", function()
            -- Not a nicety. MoveableFrame installs a watcher on the stored position that re-anchors
            -- the frame whenever that value changes, so leaving it in place gives the frame TWO
            -- owners -- the dock on every reflow, the watcher on every profile load -- and the winner
            -- is whichever fired last.
            local child = attach(2, 1)
            expect(child:GetFrame()._suuui_moveable).isNil()
        end)

        it("gives it back when the bar goes free again", function()
            local child = attach(2, 1)
            expect(child:GetFrame()._suuui_moveable).isNil()
            attach(2, nil)
            expect(child:GetFrame()._suuui_moveable).as("owns its position again").notNil()
            expect(D.ParentOf(child)).isNil()
        end)

        it("detaches from whichever bar it was on, not from bar 1", function()
            -- Deliberately NOT bar 1: the detach path asks the dock module for the recorded parent,
            -- and a test that always attached to bar 1 could not tell that from a hardcoded lookup.
            -- Mutation testing found exactly that hole.
            local four = attach(4, 5, "left")
            expect(D.ParentOf(four)).eq(bars()[5])
            attach(4, nil)
            expect(D.ParentOf(four)).as("actually detached").isNil()
            expect(D.Children(bars()[5])).as("and left bar 5's stack").len(0)
            expect(four:GetFrame()._suuui_moveable).as("owns its position again").notNil()
        end)
    end)

    describe("combat", function()
        it("refuses nothing mid-fight, because it does not try", function()
            -- An ANCHOR is the same dependency as parentage, and handing the position over is worse
            -- still: MoveableFrame:Remove clears the frame's points. So the WHOLE transition defers.
            --
            -- Both bars are BUILT before combat starts, deliberately: creating a bar mid-fight is
            -- refused on its own account and would drown this signal.
            enable(2)
            H.setCombat(true)
            H.resetBlockedActions()

            H.SuuUI.Settings:Set(PLUGIN, "bar2_attach", "1")

            expect(#H.getBlockedActions()).as("nothing was refused").eq(0)
            expect(D.Children(bars()[1])).as("not attached yet").len(0)
            expect(bars()[2]:GetFrame()._suuui_moveable)
                .as("and it still owns its own position").notNil()
        end)

        it("catches up when the fight ends", function()
            enable(2)
            H.setCombat(true)
            H.SuuUI.Settings:Set(PLUGIN, "bar2_attach", "1")
            H.setCombat(false)
            expect(D.Children(bars()[1])).as("attached now").len(1)
            expect(bars()[2]:GetFrame()._suuui_moveable).isNil()
            expect(H.box(bars()[2]).bottom).eq(H.box(bars()[1]).top - gap())
        end)
    end)

    describe("teardown", function()
        it("revokes the point when a bar is switched off", function()
            enable(3)
            expect(H.SuuUI.AttachPoints:Has("actionbar.dock.3")).truthy()
            H.SuuUI.Settings:Set(PLUGIN, "bar3_enabled", false)
            expect(H.SuuUI.AttachPoints:Has("actionbar.dock.3")).falsy()
        end)

        it("frees the bars attached to a dock that goes away", function()
            local child = attach(2, 1)
            H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", false)
            expect(D.ParentOf(child)).as("no longer pointing at a dead frame").isNil()
            expect(function() H.SuuUI.Settings:Set(PLUGIN, "bar2_rows", 2) end).notThrows()
        end)

        it("takes a dock out of its OWN parent when released", function()
            -- A dock can be docked. Releasing bar 2 has to leave bar 1's stack as well as freeing
            -- bar 3.
            attach(2, 1)
            attach(3, 2)
            H.SuuUI.Settings:Set(PLUGIN, "bar2_enabled", false)
            expect(D.Children(bars()[1])).as("left bar 1's stack").len(0)
            expect(D.ParentOf(bars()[3])).isNil()
        end)

        it("re-attaches when the dock comes back", function()
            attach(2, 1)
            H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", false)
            H.SuuUI.Settings:Set(PLUGIN, "bar1_enabled", true)
            expect(D.Children(bars()[1])).as("the request was still standing").len(1)
        end)

        it("drops the request when an attached bar is switched off", function()
            attach(2, 1)
            H.SuuUI.Settings:Set(PLUGIN, "bar2_enabled", false)
            expect(D.Children(bars()[1])).len(0)
        end)
    end)

    it("offers every bar but itself as a target", function()
        local bars_ = H.SuuUI._ActionBars.BARS
        for _, e in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN)) do
            if e.type == "subtabs" then
                for i, tab in ipairs(e.tabs) do
                    for _, entry in ipairs(tab.schema) do
                        if entry.key == "bar" .. bars_[i].id .. "_attach" then
                            -- Free plus every other bar.
                            expect(#entry.options).as("tab " .. i .. " options").eq(#bars_)
                            for _, opt in ipairs(entry.options) do
                                expect(opt.value == tostring(bars_[i].id))
                                    .as("cannot target itself").falsy()
                            end
                        end
                    end
                end
            end
        end
    end)
end)
