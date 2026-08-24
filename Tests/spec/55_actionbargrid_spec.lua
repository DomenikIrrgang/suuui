-- Components/ActionBarGrid.lua
--
-- Rows x columns of buttons on one glass plate, tested DIRECTLY rather than through the action bars
-- plugin.
--
-- It was only ever covered inside `52_actionbars_spec.lua`, which is a gap against `TESTING.md`'s own
-- claim that every component has a spec -- and a real one, because the grid's contract is what lets
-- it host something that is not an action button at all.
--
-- THE BUTTON FACTORY HERE IS A STUB, and that is the point. The grid's claim is that it owns the
-- plate, the layout, the dividers, the padding and the resize, and knows nothing about action slots.
-- A spec that builds real ActionButtons cannot show that; one that hands it a ten-line table can.

local H = require("harness")

describe("Components.ActionBarGrid", function()
    local C, S, host

    before_each(function()
        H.setup()
        C    = H.SuuUI.Components
        S    = H.SuuUI.UISignals
        host = H.parent(600, 400)
    end)

    -- A cell that satisfies the grid's button interface and nothing more. Every method the grid calls
    -- is recorded, so a spec can assert what the grid asked for rather than what a real button did.
    local function stubFactory(log)
        return function(props, parent)
            local f = H.env.CreateFrame("Frame", props.name, parent)
            f:SetSize(props.size or 32, props.size or 32)
            local b = { _f = f, props = props, calls = {} }
            function b:GetFrame() return self._f end
            function b:GetSlot() return self.props.slot end
            function b:SetSize(s) self._f:SetSize(s, s) self.calls.SetSize = s end
            function b:SetBinding(v) self.calls.SetBinding = v end
            function b:SetShowHotkey(v) self.calls.SetShowHotkey = v end
            function b:SetShowMacroText(v) self.calls.SetShowMacroText = v end
            function b:SetShowCount(v) self.calls.SetShowCount = v end
            function b:Refresh() self.calls.Refresh = (self.calls.Refresh or 0) + 1 end
            function b:ApplyTheme() end
            function b:Destroy() self.destroyed = true end
            log[#log + 1] = b
            return b
        end
    end

    local function grid(props, log)
        props = props or {}
        props.slots = props.slots or { 1, 2, 3, 4 }
        props.buttonSize = props.buttonSize or 32
        props.buttonFactory = props.buttonFactory or stubFactory(log or {})
        return C.ActionBarGrid(props, host)
    end

    describe("the props it refuses to guess", function()
        it("requires a slots array", function()
            local ok = pcall(function() C.ActionBarGrid({ buttonSize = 32 }, host) end)
            expect(ok).as("raised rather than defaulting").falsy()
        end)

        it("requires a buttonSize", function()
            local ok = pcall(function() C.ActionBarGrid({ slots = { 1 } }, host) end)
            expect(ok).falsy()
        end)
    end)

    describe("the button factory seam", function()
        it("builds every cell through the factory it was given", function()
            -- This is what lets the stance bar exist: a form cell cannot be an ActionButton, because
            -- CastShapeshiftForm is protected and a stance button carries no `type` attribute.
            local log = {}
            grid({ slots = { 5, 6, 7 } }, log)
            expect(#log).as("one call per slot").eq(3)
            expect(log[1].props.slot).eq(5)
            expect(log[3].props.slot).eq(7)
        end)

        it("defaults to ActionButton when none is given", function()
            local g = C.ActionBarGrid({ slots = { 1 }, buttonSize = 32 }, host)
            local b = g:GetButtons()[1]
            expect(b).notNil()
            -- A real ActionButton reads its slot from the secure attribute rather than a field.
            expect(b:GetFrame():GetAttribute("action")).as("a real secure button").eq(1)
            g:Destroy()
        end)

        it("passes the cell its size, binding and readout flags", function()
            local log = {}
            grid({ slots = { 1 }, buttonSize = 40, bindings = { "KEY1" },
                   showHotkeys = false }, log)
            expect(log[1].props.size).eq(40)
            expect(log[1].props.binding).eq("KEY1")
            expect(log[1].props.showHotkey).as("passed through as the singular prop").eq(false)
        end)

        it("names the buttons when given a prefix, because bindings resolve by name", function()
            -- SetOverrideBindingClick takes a button NAME, so a grid whose buttons are anonymous
            -- cannot have its keys routed at all.
            local log = {}
            grid({ slots = { 1, 2 }, namePrefix = "TestBar1Button" }, log)
            expect(log[1].props.name).eq("TestBar1Button1")
            expect(log[2].props.name).eq("TestBar1Button2")
        end)
    end)

    describe("layout", function()
        it("lays a single row out left to right", function()
            local log = {}
            local g = grid({ slots = { 1, 2, 3 } }, log)
            local x1 = select(4, log[1]:GetFrame():GetPoint(1)) or 0
            local x3 = select(4, log[3]:GetFrame():GetPoint(1)) or 0
            expect(x1 < x3).as("index 1 is leftmost").truthy()
            g:Destroy()
        end)

        it("wraps into rows, and the row count is what was asked for", function()
            local log = {}
            local g = grid({ slots = { 1, 2, 3, 4, 5, 6 }, rows = 2 }, log)
            local y1 = select(5, log[1]:GetFrame():GetPoint(1)) or 0
            local yLast = select(5, log[6]:GetFrame():GetPoint(1)) or 0
            expect(y1 ~= yLast).as("not all on one line").truthy()
            g:Destroy()
        end)

        it("clamps rows to at least one", function()
            local g = grid({ rows = 0 })
            expect(#g:GetButtons()).as("still built").eq(4)
            g:Destroy()
        end)

        it("grows when the button size grows", function()
            local g = grid({ buttonSize = 32 })
            local before = g:GetFrame():GetWidth()
            g:SetButtonSize(48)
            expect(g:GetFrame():GetWidth() > before).truthy()
            g:Destroy()
        end)
    end)

    describe("the plate", function()
        it("takes NO mouse input", function()
            -- A plate that swallowed clicks would make the gaps between buttons unclickable in the
            -- world behind them -- the bar would become a wall.
            local g = grid()
            expect(g:GetFrame():IsMouseEnabled()).falsy()
            g:Destroy()
        end)

        it("draws hairline dividers ONLY for a seamless grid", function()
            -- Dividers are what make a spacing of 0 read as a grid of cells rather than one slab. With
            -- real spacing the gap already separates the buttons and a divider would sit in open air.
            local seamless = grid({ spacing = 0 })
            expect(#seamless._dividers > 0).as("seamless gets dividers").truthy()
            seamless:Destroy()

            local spaced = grid({ spacing = 4 })
            expect(#spaced._dividers).as("spaced gets none").eq(0)
            spaced:Destroy()
        end)
    end)

    describe("rebuilding", function()
        it("emits CHILDREN_CHANGED when the button SET really moves", function()
            -- Secure paging and keybinding routing both hold references to these buttons, and a
            -- rebuild destroys and recreates them. This signal is the only thing that tells a holder
            -- its references went stale -- and the rebuild can be deferred to the end of a fight, so
            -- nothing else could.
            local g = grid({ slots = { 1, 2 } })
            local fired = 0
            S:Connect(g, S.SIGNALS.CHILDREN_CHANGED, function() fired = fired + 1 end)
            g:SetSlots({ 1, 2, 3, 4 })
            expect(fired > 0).as("the set grew").truthy()
            g:Destroy()
        end)

        it("destroys the buttons it replaces", function()
            local log = {}
            local g = grid({ slots = { 1, 2, 3 } }, log)
            local first = log[1]
            g:SetSlots({ 9 })
            expect(#g:GetButtons()).eq(1)
            expect(first.destroyed).as("the old cell was destroyed, not orphaned").truthy()
            g:Destroy()
        end)

        it("reports the slots it is currently showing", function()
            local g = grid({ slots = { 4, 5, 6 } })
            expect(g:GetSlots()).deepEq({ 4, 5, 6 })
            g:Destroy()
        end)
    end)

    describe("combat", function()
        it("DEFERS a geometry change and says so", function()
            -- A grid contains protected buttons by construction, so the client refuses SetSize on the
            -- grid AND SetPoint on each button while InCombatLockdown() -- and refuses them silently.
            local g = grid({ buttonSize = 32 })
            local before = g:GetFrame():GetWidth()
            H.setCombat(true)
            g:SetButtonSize(64)
            expect(g:GetFrame():GetWidth()).as("nothing moved mid-fight").eq(before)
            expect(g:IsDeferred()).as("and it knows it is behind").truthy()
            H.setCombat(false)
            g:Destroy()
        end)

        it("catches up when the fight ends", function()
            local g = grid({ buttonSize = 32 })
            local before = g:GetFrame():GetWidth()
            H.setCombat(true)
            g:SetButtonSize(64)
            H.setCombat(false)
            H.fireEvent("PLAYER_REGEN_ENABLED")
            expect(g:GetFrame():GetWidth() > before).as("applied on the way out").truthy()
            expect(g:IsDeferred()).as("and no longer behind").falsy()
            g:Destroy()
        end)
    end)

    describe("teardown", function()
        it("destroys every cell it built", function()
            local log = {}
            local g = grid({ slots = { 1, 2, 3 } }, log)
            g:Destroy()
            for i, b in ipairs(log) do
                expect(b.destroyed).as("cell " .. i .. " destroyed").truthy()
            end
        end)
    end)
end)
