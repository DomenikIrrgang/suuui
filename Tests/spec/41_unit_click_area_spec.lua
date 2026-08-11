local H = require("harness")

-- The unit context menu, and the click surface that opens it.
--
-- Both of the actions here are PROTECTED, so neither is a callback the addon could write:
-- the surface states secure attributes and the CLIENT performs the action. That is what
-- these specs assert — not that a handler ran, but that the client was asked for the right
-- action on the right unit, which is the only thing observable and the only thing that
-- matters in game.
describe("Components.UnitClickArea", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
    end)

    -- The real arrangement: a frame with geometry, and the surface stretched over all of it
    -- by a stack container hosted on that frame.
    local function surface(unit, w, h)
        local f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w or 200, h or 60)
        local place = H.SuuUI.Layout:CreateContainer({ host = host, layout = "anchor" })
        place:Add(f, { anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 20, y = -20 } })
        local area = H.C.UnitClickArea({ unit = unit or "player" }, f)
        local box = H.SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
        box:Add(area)
        return area, f, box
    end

    describe("construction", function()
        it("reports the unit it was built for", function()
            local area = surface("target")
            expect(area:GetUnit()).eq("target")
        end)

        it("refuses to be built without a unit", function()
            expect(function() H.C.UnitClickArea({}, host) end).throws()
        end)

        it("takes mouse input", function()
            local area = surface()
            expect(area:GetFrame():IsMouseEnabled()).eq(true)
        end)

        it("stretches over the frame it covers", function()
            local area, f = surface("player", 240, 80)
            H.expectBox(area, H.box(f))
        end)
    end)

    describe("clicking", function()
        it("targets the unit on left click", function()
            local area = surface("target")
            expect(H.click(area)).eq(true)
            expect(H.targetedUnit()).as("the client was asked to target").eq("target")
            expect(H.unitMenu()).as("no menu on a left click").isNil()
        end)

        it("opens the unit's context menu on right click", function()
            local area = surface("target")
            expect(H.click(area, "RightButton")).eq(true)
            local menu = H.unitMenu()
            expect(menu).notNil()
            expect(menu.unit).as("the menu is the clicked unit's").eq("target")
            expect(H.targetedUnit()).as("a right click does not retarget").isNil()
        end)

        it("opens the menu for the player on the player's surface", function()
            local area = surface("player")
            H.click(area, "RightButton")
            expect(H.unitMenu().unit).eq("player")
        end)

        it("does nothing on a button it states no action for", function()
            local area = surface("player")
            H.click(area, "MiddleButton")
            expect(H.targetedUnit()).isNil()
            expect(H.unitMenu()).as("no third action is stated").isNil()
        end)

        it("acts again on a second click", function()
            local area = surface("player")
            H.click(area, "RightButton")
            H.clearUnitActions()
            H.click(area, "RightButton")
            expect(H.unitMenu().unit).eq("player")
        end)

        it("delivers nothing while hidden", function()
            local area = surface("player")
            area:Hide()
            expect(H.click(area, "RightButton")).as("a hidden surface takes no click").eq(false)
            expect(H.unitMenu()).isNil()
        end)
    end)

    describe("signals", function()
        it("emits CLICKED with the button name, after the action", function()
            local area = surface("player")
            local spy = H.signalSpy(area, H.S.SIGNALS.CLICKED)
            H.click(area, "RightButton")
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("RightButton")
            expect(H.unitMenu()).as("the action still happened").notNil()
        end)

        -- PostClick, not OnMouseUp: the signal has to describe a click the CLIENT has
        -- already acted on, and it has to be a hook the secure template offers — reaching
        -- for OnClick instead would replace the handler that performs the action.
        it("emits CLICKED only once the client has acted", function()
            local area = surface("player")
            local seen
            H.S:Connect(area, H.S.SIGNALS.CLICKED, function()
                seen = H.unitMenu()
            end)
            H.click(area, "RightButton")
            expect(seen).as("the menu was already open when CLICKED fired").notNil()
            expect(seen.unit).eq("player")
        end)

        it("emits CLICKED for a left click too", function()
            local area = surface("player")
            local spy = H.signalSpy(area, H.S.SIGNALS.CLICKED)
            H.click(area)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("LeftButton")
        end)

        it("emits MOUSE_ENTER and MOUSE_LEAVE", function()
            local area = surface("player")
            local enter = H.signalSpy(area, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(area, H.S.SIGNALS.MOUSE_LEAVE)
            H.hover(area)
            expect(enter.count).eq(1)
            H.unhover(area)
            expect(leave.count).eq(1)
        end)

        it("emits SIZE_CHANGED when the layout resizes it", function()
            local area, f = surface("player", 200, 60)
            local spy = H.signalSpy(area, H.S.SIGNALS.SIZE_CHANGED)
            f:SetSize(300, 90)
            expect(spy.count).gte(1)
            H.expectBox(area, H.box(f))
        end)
    end)

    describe("teardown", function()
        it("Destroy hides the surface", function()
            local area = surface("player")
            area:Destroy()
            expect(area:GetFrame():IsShown()).eq(false)
        end)

        it("a destroyed surface takes no click", function()
            local area = surface("player")
            area:Destroy()
            expect(H.click(area, "RightButton")).eq(false)
            expect(H.unitMenu()).isNil()
        end)

        it("signals are silent after Destroy", function()
            local area, f = surface("player")
            local spy = H.signalSpy(area, H.S.SIGNALS.SIZE_CHANGED)
            area:Destroy()
            spy:reset()
            f:SetSize(320, 100)
            expect(spy.count).as("no signal after destroy").eq(0)
        end)
    end)
end)

-- The plugin wiring: which unit each frame's surface acts on, and how it shares the frame
-- with edit mode.
describe("Plugins.UnitFrames right-click menu", function()
    local host, state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth = 80
        state.unitHealthMax = 100
        state.unitPower = 60
        state.unitPowerMax = 100
        state.unitPowerType = 0
        state.unitLevel = 42
        state.maxPlayerLevel = 60
        H.setup()
        host = H.parent(1024, 768)
    end)

    local function widgetFor(id)
        local plugin = H.SuuUI.Plugins:Get("unit_frames")
        return plugin["_" .. id .. "Frame"]
    end

    it("gives the player frame a click surface bound to the player", function()
        local w = widgetFor("player")
        expect(w._clickArea).notNil()
        expect(w._clickArea:GetUnit()).eq("player")
    end)

    it("opens the player's menu on a right click anywhere on the frame", function()
        local w = widgetFor("player")
        H.click(w._clickArea, "RightButton")
        expect(H.unitMenu().unit).eq("player")
    end)

    it("targets the player on a left click", function()
        local w = widgetFor("player")
        H.click(w._clickArea)
        expect(H.targetedUnit()).eq("player")
    end)

    it("binds the target frame's surface to the target", function()
        H.setTarget({ name = "Wolf", health = 50, healthMax = 100 })
        local w = widgetFor("target")
        expect(w._clickArea:GetUnit()).eq("target")
        H.click(w._clickArea, "RightButton")
        expect(H.unitMenu().unit).eq("target")
    end)

    it("covers the whole frame, attach bands included", function()
        local w = widgetFor("player")
        H.expectBox(w._clickArea, H.box(w:GetFrame()))
    end)

    it("is the frame's topmost surface in normal play", function()
        local w = widgetFor("player")
        local cx, cy = H.centerPoint(w:GetFrame())
        expect(H.topmostAt(cx, cy)).as("a click reaches the unit surface")
            .eq(w._clickArea:GetFrame())
    end)

    it("yields to the drag overlay in edit mode", function()
        local w = widgetFor("player")
        H.SuuUI.ToggleUI:Enable()
        local cx, cy = H.centerPoint(w:GetFrame())
        local overlay = w:GetFrame()._suuui_moveable.overlay
        expect(H.topmostAt(cx, cy)).as("positioning the frame must not target the unit")
            .eq(overlay)
    end)

    it("takes the click surface down with the frame", function()
        local w = widgetFor("player")
        local f = w._clickArea:GetFrame()
        H.SuuUI.Plugins:Get("unit_frames"):Disable()
        expect(f:IsShown()).as("a disabled plugin leaves no live click surface").eq(false)
        expect(H.click(f, "RightButton")).as("and it answers no click").eq(false)
        expect(H.unitMenu()).isNil()
    end)
end)
