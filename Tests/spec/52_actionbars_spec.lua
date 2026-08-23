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

    local function bar()
        return H.SuuUI.Plugins:Get(PLUGIN)._bar
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

    it("hides NOTHING of Blizzard's this phase", function()
        -- Phase 4a is additive on purpose: if suppression landed and the secure button path
        -- did not, the player would be mid-session with no action bars at all.
        for _, name in ipairs({ "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft",
                                "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight" }) do
            local f = H.env[name]
            if f then
                expect(f:IsShown()).as(name .. " is untouched").truthy()
            end
        end
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
