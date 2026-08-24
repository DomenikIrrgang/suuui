-- Core/Dock.lua
--
-- Bar-to-bar docking, tested DIRECTLY rather than through a plugin.
--
-- It used to be `Plugins/ActionBars/Dock.lua` and was only ever covered inside
-- `52_actionbars_spec.lua`. That was adequate while action bars were its only participant and became
-- a real gap the moment the watch bars joined: a service tested only through one consumer breaks
-- confusingly when a second arrives, and `TESTING.md` claims every core subsystem has a spec.
--
-- THE PARTICIPANT HERE IS A FAKE, and that is the point of this file. The dock's whole claim is that
-- it asks a participant for exactly three things -- `GetFrame`, `GetWidth`/`GetHeight`, and a
-- `SIZE_CHANGED` signal -- and knows nothing about action bars. A spec that docks real bars cannot
-- prove that; a spec that docks a nine-line table can.

local H = require("harness")

describe("Core.Dock", function()
    local D, S, SIG, host

    before_each(function()
        H.setup()
        D    = H.SuuUI.Dock
        S    = H.SuuUI.UISignals
        SIG  = S.SIGNALS.SIZE_CHANGED
        host = H.parent(600, 500)
    end)

    -- The MINIMAL participant: nothing but the contract. No slots, no buttons, no plugin.
    local function participant(w, h)
        local f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(w or 100, h or 40)
        local handle = { _f = f }
        function handle:GetFrame()  return self._f end
        function handle:GetWidth()  return self._f:GetWidth() end
        function handle:GetHeight() return self._f:GetHeight() end
        -- Resizing is what a real bar does when it gains a row; the signal is how the dock hears.
        function handle:Resize(nw, nh)
            self._f:SetSize(nw, nh)
            S:Emit(self, SIG, nw, nh)
        end
        return handle
    end

    local function anchorOf(p)
        local point, rel, relPoint, x, y = p:GetFrame():GetPoint(1)
        return { point = point, relativeTo = rel, relativePoint = relPoint, x = x or 0, y = y or 0 }
    end

    describe("the participant contract", function()
        it("docks anything with GetFrame, a span and a SIZE_CHANGED signal", function()
            -- No plugin, no action slots, no ActionBarGrid. If this passes, the service is generic --
            -- which is the property that let the experience and reputation bars dock without the dock
            -- changing at all.
            local dock, child = participant(), participant()
            expect(D.Attach(dock, child, { edge = "above" })).as("accepted").truthy()
            expect(D.ParentOf(child)).eq(dock)
            expect(D.EdgeOf(child)).eq("above")
        end)

        it("offers exactly four edges", function()
            expect(D.EDGES).deepEq({ "above", "below", "left", "right" })
        end)

        it("defaults to the above edge when none is given", function()
            local dock, child = participant(), participant()
            D.Attach(dock, child)
            expect(D.EdgeOf(child)).eq("above")
        end)
    end)

    describe("placement", function()
        it("anchors each edge on the opposing point, so the child sits outside the dock", function()
            local pairs_ = {
                above = { point = "BOTTOM", relativePoint = "TOP" },
                below = { point = "TOP",    relativePoint = "BOTTOM" },
                left  = { point = "RIGHT",  relativePoint = "LEFT" },
                right = { point = "LEFT",   relativePoint = "RIGHT" },
            }
            for edge, want in pairs(pairs_) do
                H.setup()
                D, S, SIG = H.SuuUI.Dock, H.SuuUI.UISignals, H.SuuUI.UISignals.SIGNALS.SIZE_CHANGED
                host = H.parent(600, 500)
                local dock, child = participant(), participant()
                D.Attach(dock, child, { edge = edge })
                local a = anchorOf(child)
                expect(a.point).as(edge .. " point").eq(want.point)
                expect(a.relativePoint).as(edge .. " relativePoint").eq(want.relativePoint)
            end
        end)

        it("names relativeTo EXPLICITLY in the DESCRIPTOR, not just in the result", function()
            -- Load-bearing, not tidy. Layout props live on the FRAME, so a frame belonging to two
            -- containers has ONE props table -- and an anchor with no relativeTo resolves against
            -- whichever container applies it. The root container re-applied this very descriptor with
            -- itself as the relative frame and pinned every docked bar to the top of the screen.
            --
            -- ASSERTED ON THE DESCRIPTOR rather than on the resolved anchor, and mutation testing is
            -- why: with the dock's box hosted on the dock's own frame, an omitted relativeTo resolves
            -- to that same frame anyway, so the resolved anchor is identical either way. The bug needs
            -- a SECOND container to show itself, which the descriptor check catches without one.
            local dock, child = participant(), participant()
            D.Attach(dock, child, { edge = "above" })
            local props = child:GetFrame()._layoutProps
            expect(props).as("the frame carries layout props").notNil()
            expect(props.anchor).as("and an anchor descriptor").notNil()
            expect(props.anchor.relativeTo).as("with relativeTo NAMED").eq(dock:GetFrame())
            expect(anchorOf(child).relativeTo).as("and it resolves there too").eq(dock:GetFrame())
        end)

        it("stacks a second child past the first's SPAN, not on top of it", function()
            local dock = participant()
            local a, b = participant(100, 40), participant(100, 40)
            D.Attach(dock, a, { edge = "above", order = 1 })
            D.Attach(dock, b, { edge = "above", order = 2 })
            local ya, yb = anchorOf(a).y, anchorOf(b).y
            expect(ya > 0).as("above is a POSITIVE y offset").truthy()
            -- The second clears the first: its own height plus two gaps.
            expect(yb > ya + 39).as("b sits past a's 40px height (got " .. yb .. " vs " .. ya .. ")")
                .truthy()
        end)

        it("counts the negative direction for below and left", function()
            local dock = participant()
            local below, left = participant(), participant()
            D.Attach(dock, below, { edge = "below" })
            D.Attach(dock, left, { edge = "left" })
            expect(anchorOf(below).y < 0).as("below grows down").truthy()
            expect(anchorOf(left).x < 0).as("left grows left").truthy()
        end)

        it("stacks each edge INDEPENDENTLY", function()
            -- Two children on different edges must not push each other; only same-edge siblings do.
            local dock = participant()
            local up, down = participant(100, 40), participant(100, 40)
            D.Attach(dock, up, { edge = "above" })
            D.Attach(dock, down, { edge = "below" })
            expect(math.abs(anchorOf(up).y)).as("the same first-child offset on both edges")
                .eq(math.abs(anchorOf(down).y))
        end)
    end)

    describe("reflow on a size change", function()
        it("restacks when a child RESIZES, which nothing else would notice", function()
            -- Attach and Detach are the only other reflow triggers and neither fires for a resize, so
            -- without the signal a bar gaining a row would overlap its neighbour.
            local dock = participant()
            local a, b = participant(100, 40), participant(100, 40)
            D.Attach(dock, a, { edge = "above", order = 1 })
            D.Attach(dock, b, { edge = "above", order = 2 })
            local before = anchorOf(b).y
            a:Resize(100, 80)
            expect(anchorOf(b).y > before).as("b moved out of a's way").truthy()
        end)

        it("stops listening once a child is detached", function()
            local dock, child = participant(), participant()
            D.Attach(dock, child)
            expect(S:HasConnections(child, SIG)).as("subscribed while attached").truthy()
            D.Detach(dock, child)
            expect(S:HasConnections(child, SIG)).as("and not after").falsy()
        end)
    end)

    describe("cycles", function()
        it("refuses a direct loop", function()
            local a, b = participant(), participant()
            D.Attach(a, b)
            expect(D.Attach(b, a)).as("refused").falsy()
            expect(D.ParentOf(a)).as("and nothing was half-applied").isNil()
        end)

        it("refuses a self-attach, which is a loop of length zero", function()
            local a = participant()
            expect(D.Attach(a, a)).falsy()
        end)

        it("refuses a loop through a CHAIN", function()
            local a, b, c = participant(), participant(), participant()
            D.Attach(a, b)
            D.Attach(b, c)
            expect(D.WouldCycle(c, a)).as("a onto c would close a -> b -> c").truthy()
            expect(D.Attach(c, a)).falsy()
        end)

        it("allows a legal chain", function()
            local a, b, c = participant(), participant(), participant()
            expect(D.Attach(a, b)).truthy()
            expect(D.Attach(b, c)).truthy()
            expect(D.ParentOf(c)).eq(b)
            expect(D.ParentOf(b)).eq(a)
        end)
    end)

    describe("release", function()
        it("detaches the dock from ITS OWN parent even with nothing attached to it", function()
            -- THE BUG THIS ONCE HAD. A bar with nothing attached to it has no record in the dock, so
            -- an early return skipped this entirely and left the bar anchored to a parent that had
            -- just been destroyed -- a stack with a hole in it, reflowing around a dead frame.
            local parent, lonely = participant(), participant()
            D.Attach(parent, lonely)
            expect(D.Children(lonely)).as("nothing is attached TO it").deepEq({})
            D.Release(lonely)
            expect(D.ParentOf(lonely)).as("released from its own parent anyway").isNil()
        end)

        it("drops the children attached to it", function()
            local dock, child = participant(), participant()
            D.Attach(dock, child)
            D.Release(dock)
            expect(D.ParentOf(child)).isNil()
        end)
    end)

    describe("the participant registry", function()
        local function register(id, spec)
            spec = spec or {}
            spec.label = spec.label or id
            spec.group = spec.group or "Test"
            spec.point = spec.point or ("test.dock." .. id)
            D.RegisterParticipant(id, spec)
        end

        it("resolves a participant's attach point by id", function()
            -- The seam that made cross-plugin docking work: building the name from a caller's own
            -- prefix is what made an action bar silently fail to dock to a watch bar.
            register("thing", { point = "some.dock.thing" })
            expect(D.PointFor("thing")).eq("some.dock.thing")
            expect(D.PointFor("nonexistent")).isNil()
        end)

        it("offers every participant EXCEPT the one being configured", function()
            register("a") register("b")
            local values = {}
            for _, o in ipairs(D.OptionsFor("a")) do values[o.value] = true end
            expect(values["detached"]).as("Free is offered").truthy()
            expect(values["b"]).truthy()
            expect(values["a"]).as("never itself").falsy()
        end)

        it("puts Free first, because it is the default", function()
            register("a")
            expect(D.OptionsFor("a")[1].value).eq("detached")
        end)

        it("walks the STORED graph across participants", function()
            -- A validator runs BEFORE the value is stored, so the live dock graph does not know about
            -- the choice yet -- and the loop can run through another plugin entirely. `attachedTo`
            -- reads each participant's OWN settings, which is the only reason this can span plugins.
            local target = {}
            register("x", { attachedTo = function() return target.x end })
            register("y", { attachedTo = function() return target.y end })
            expect(D.WouldCycleIds("x", "y")).as("nothing stored yet").falsy()
            target.y = "x"
            expect(D.WouldCycleIds("x", "y")).as("y already points at x").truthy()
        end)

        it("does not spin on a graph that already contains a loop", function()
            -- A hand-edited profile, or one written by a version predating the guard. Bounded as well
            -- as identity-checked.
            register("p", { attachedTo = function() return "q" end })
            register("q", { attachedTo = function() return "p" end })
            expect(D.WouldCycleIds("unrelated", "p")).as("returns rather than hanging").truthy()
        end)

        it("forgets a participant on request", function()
            register("gone")
            D.UnregisterParticipant("gone")
            expect(D.PointFor("gone")).isNil()
            local listed = false
            for _, e in ipairs(D.Participants()) do
                if e.id == "gone" then listed = true end
            end
            expect(listed).as("not listed").falsy()
        end)

        it("falls back to REGISTRATION ORDER when nothing else distinguishes them", function()
            -- table.sort is NOT stable in Lua. Every action bar ties on the same sort key, and without
            -- a registration-sequence tiebreaker the dropdown listed them 4, 6, 5, 2, 3, 7, 1, 8.
            --
            -- ASSERTED AS THE EXACT SEQUENCE, not as "the same answer twice", and mutation testing is
            -- why: a comparator that always returns false is still deterministic for one input inside
            -- one process, so comparing repeated calls passed while the ordering was gone.
            local order = { "one", "two", "three", "four", "five", "six", "seven", "eight" }
            for _, id in ipairs(order) do
                register(id, { group = "Same", sort = 0 })
            end
            local got = {}
            for _, e in ipairs(D.Participants()) do
                if e.spec.group == "Same" then got[#got + 1] = e.id end
            end
            expect(got).as("registration order, exactly").deepEq(order)
        end)

        it("groups before it sorts", function()
            register("z_early", { group = "AAA", sort = 99 })
            register("a_late", { group = "ZZZ", sort = 1 })
            local ids = {}
            for _, e in ipairs(D.Participants()) do ids[#ids + 1] = e.id end
            local iEarly, iLate
            for i, id in ipairs(ids) do
                if id == "z_early" then iEarly = i end
                if id == "a_late" then iLate = i end
            end
            expect(iEarly < iLate).as("group AAA precedes group ZZZ regardless of sort").truthy()
        end)
    end)
end)
