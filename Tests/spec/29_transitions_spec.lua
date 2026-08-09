local H = require("harness")

describe("Animation.Transitions", function()
    local Tr

    before_each(function()
        H.setup({ barTransitions = true })
        Tr = H.SuuUI.Anim.Transitions
    end)

    ---------------------------------------------------------------------------
    -- 1. Registry: Register / Has / Get / List / SetDefault / GetDefault
    ---------------------------------------------------------------------------
    describe("Registry", function()
        it("ships with instant, smooth, and rate registered", function()
            expect(Tr:Has("instant")).truthy()
            expect(Tr:Has("smooth")).truthy()
            expect(Tr:Has("rate")).truthy()
        end)

        it("Get returns the normalised strategy for a registered name", function()
            local s = Tr:Get("smooth")
            expect(s).notNil()
            expect(type(s.Apply)).eq("function")
            expect(type(s.Attach)).eq("function")
            expect(type(s.Cancel)).eq("function")
            expect(type(s.Detach)).eq("function")
            expect(s.name).eq("smooth")
        end)

        it("Get returns nil for an unregistered name", function()
            expect(Tr:Get("nonexistent")).isNil()
        end)

        it("Has returns false for unregistered names", function()
            expect(Tr:Has("bogus")).eq(false)
        end)

        it("Register adds a custom strategy", function()
            Tr:Register("test_strat", { Apply = function() end })
            expect(Tr:Has("test_strat")).truthy()
            expect(Tr:Get("test_strat").name).eq("test_strat")
        end)

        it("Register asserts on a non-string name", function()
            expect(function()
                Tr:Register(123, { Apply = function() end })
            end).throws()
        end)

        it("Register asserts on an empty string name", function()
            expect(function()
                Tr:Register("", { Apply = function() end })
            end).throws()
        end)

        it("Register asserts when strategy lacks Apply", function()
            expect(function()
                Tr:Register("broken", { Cancel = function() end })
            end).throws()
        end)

        it("List returns sorted names", function()
            local list = Tr:List()
            for i = 2, #list do
                expect(list[i - 1] <= list[i]).as(
                    list[i - 1] .. " <= " .. list[i]).truthy()
            end
            -- Must contain the built-ins
            local found = {}
            for _, name in ipairs(list) do found[name] = true end
            expect(found["instant"]).truthy()
            expect(found["smooth"]).truthy()
            expect(found["rate"]).truthy()
        end)

        it("GetDefault returns smooth when barTransitions is true", function()
            expect(Tr:GetDefault()).eq("smooth")
        end)

        it("SetDefault changes the default", function()
            Tr:SetDefault("rate")
            expect(Tr:GetDefault()).eq("rate")
        end)

        it("SetDefault asserts on unknown name", function()
            expect(function()
                Tr:SetDefault("totally_fake")
            end).throws()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Resolve
    ---------------------------------------------------------------------------
    describe("Resolve", function()
        it("nil resolves to the default strategy", function()
            local s = Tr:Resolve(nil)
            expect(s).eq(Tr:Get(Tr:GetDefault()))
        end)

        it("a registered name resolves to that strategy", function()
            local s = Tr:Resolve("rate")
            expect(s).eq(Tr:Get("rate"))
        end)

        it("an unknown name falls back to default AND logs a warning", function()
            H.setup({ barTransitions = true, debug = true })
            Tr = H.SuuUI.Anim.Transitions
            local s = Tr:Resolve("bogus_name")
            expect(s).eq(Tr:Get(Tr:GetDefault()))
            local logged = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("bogus_name") and line:find("unknown") then
                    logged = true
                end
            end
            expect(logged).as("warning logged for unknown strategy").truthy()
        end)

        it("an inline table is normalised with no-op hooks", function()
            local inline = { Apply = function(ctx, from, to) ctx:Set(to) end }
            local resolved = Tr:Resolve(inline)
            expect(type(resolved.Attach)).eq("function")
            expect(type(resolved.Cancel)).eq("function")
            expect(type(resolved.Detach)).eq("function")
            expect(resolved.Apply).notNil()
        end)

        it("Resolve does NOT mutate the caller's inline table", function()
            local inline = { Apply = function(ctx, from, to) ctx:Set(to) end }
            Tr:Resolve(inline)
            expect(inline.Attach).as("caller table not mutated").isNil()
            expect(inline.Cancel).isNil()
            expect(inline.Detach).isNil()
        end)

        it("Resolve returns a copy, not the original inline table", function()
            local inline = { Apply = function(ctx, from, to) ctx:Set(to) end }
            local a = Tr:Resolve(inline)
            local b = Tr:Resolve(inline)
            -- Each Resolve must produce a separate table
            expect(a).as("each resolve is a fresh copy").notNil()
            -- Both must function equivalently but be distinct normalise calls
            expect(type(a.Apply)).eq("function")
            expect(type(b.Apply)).eq("function")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. StatusBar integration helpers
    ---------------------------------------------------------------------------
    describe("StatusBar integration", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("GetTransition returns the active strategy name", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                                        transition = "rate" }, host)
            H.mount(bar)
            expect(bar:GetTransition()).eq("rate")
        end)

        it("SetTransition switches the active strategy", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100 }, host)
            H.mount(bar)
            bar:SetTransition("instant")
            expect(bar:GetTransition()).eq("instant")
        end)

        it("SetTransition via prop at construction", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            expect(bar:GetTransition()).eq("smooth")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. instant: painted fraction equals target with zero animation ticks
    ---------------------------------------------------------------------------
    describe("instant strategy", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("GetDisplayPercent equals GetPercent immediately after SetValue", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                                        transition = "instant" }, host)
            H.mount(bar)
            bar:SetValue(60)
            expect(bar:GetDisplayPercent()).eq(bar:GetPercent())
            expect(bar:GetDisplayPercent()).eq(0.6)
        end)

        it("is not transitioning after SetValue", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                                        transition = "instant" }, host)
            H.mount(bar)
            bar:SetValue(80)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("fills correctly without any tick", function()
            local bar = H.C.StatusBar({ w = 100, h = 16, value = 0, max = 100,
                                        transition = "instant", border = false }, host)
            H.mount(bar)
            bar:SetValue(50)
            local expectedW = H.SuuUI.Pixel.Floor(100 * 0.5)
            expect(bar._fillFrame:GetWidth()).near(expectedW, 1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. smooth: mid-flight and settled
    ---------------------------------------------------------------------------
    describe("smooth strategy", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("mid-flight display is between old and new values", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(100)
            -- Tick a fraction of the duration
            local dur = H.token("animBarFill")
            H.tick(dur * 0.3)
            local disp = bar:GetDisplayPercent()
            expect(disp).as("display should be above 0").gt(0)
            expect(disp).as("display should be below 1").lt(1)
            expect(bar:IsTransitioning()).eq(true)
        end)

        it("settles exactly on target after full animation", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(75)
            H.runAnimations()
            expect(bar:GetDisplayPercent()).eq(bar:GetPercent())
            expect(bar:GetDisplayPercent()).eq(0.75)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("FILL_SETTLED fires when display catches up", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            local spy = H.signalSpy(bar, H.SuuUI.Components.STATUSBAR_SIGNALS.FILL_SETTLED)
            bar:SetValue(50)
            H.runAnimations()
            expect(spy.count).as("settled fires once").eq(1)
            expect(spy:arg(1)).eq(0.5)
        end)

        it("SetTransitionDuration overrides the animBarFill token", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetTransitionDuration(1.0)
            bar:SetValue(100)
            -- After animBarFill time, it should NOT be settled because duration is 1s
            H.tick(H.token("animBarFill"))
            expect(bar:IsTransitioning()).as("still transitioning at token duration").eq(true)
            -- After 1s total it settles
            H.tick(1.0)
            expect(bar:GetDisplayPercent()).eq(1.0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. smooth retarget mid-flight: no jump
    ---------------------------------------------------------------------------
    describe("smooth retarget mid-flight", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("does not jump on retarget — starts from current painted value", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(100)
            local dur = H.token("animBarFill")
            H.tick(dur * 0.4)
            local midFlight = bar:GetDisplayPercent()
            expect(midFlight).gt(0)
            expect(midFlight).lt(1)

            -- Retarget to 50%
            bar:SetValue(50)
            -- Immediately after retarget, display must be the same as mid-flight
            -- (no jump)
            expect(bar:GetDisplayPercent()).eq(midFlight)

            -- After settling, must reach the new target
            H.runAnimations()
            expect(bar:GetDisplayPercent()).eq(0.5)
        end)

        it("converges to the last target regardless of retargets", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(H.token("animBarFill") * 0.2)
            bar:SetValue(30)
            H.tick(H.token("animBarFill") * 0.2)
            bar:SetValue(90)
            H.runAnimations()
            expect(bar:GetDisplayPercent()).eq(0.9)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. rate: duration scales with distance
    ---------------------------------------------------------------------------
    describe("rate strategy", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("small delta settles faster than large delta", function()
            local barSmall = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                             transition = "rate" }, host)
            local barLarge = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                             transition = "rate" }, host)
            H.mount(barSmall)
            H.mount(barLarge)

            barSmall:SetValue(5)  -- 5% move
            barLarge:SetValue(90) -- 90% move

            -- Tick enough for the small delta to finish but not enough for the large
            local dur = H.token("animBarFill")
            local smallDur = dur * 0.05  -- rate scales linearly by distance
            H.tick(smallDur + 0.016)     -- one extra frame for safety

            -- Small should be settled
            expect(barSmall:GetDisplayPercent()).eq(barSmall:GetPercent())
            -- Large should still be transitioning
            expect(barLarge:IsTransitioning()).eq(true)
        end)

        it("repeated rapid retargets still converge", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "rate" }, host)
            H.mount(bar)
            -- Simulate rapid energy ticks
            for v = 1, 20 do
                bar:SetValue(v * 5)
                H.tick(0.016) -- one frame between each
            end
            -- Let it settle
            H.runAnimations()
            expect(bar:GetDisplayPercent()).eq(bar:GetPercent())
            expect(bar:GetPercent()).eq(1.0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Custom inline strategy: ctx API
    ---------------------------------------------------------------------------
    describe("custom inline strategy ctx API", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("Apply receives correct from and to", function()
            local captured = {}
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        captured.from = from
                        captured.to = to
                        ctx:Set(to) -- instant for simplicity
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(60)
            expect(captured.from).eq(0)
            expect(captured.to).eq(0.6)
        end)

        it("ctx:Set moves the fill", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        ctx:Set(to * 0.5) -- paint half the target
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(100)
            expect(bar:GetDisplayPercent()).eq(0.5)
        end)

        it("ctx:Get returns the painted value", function()
            local got
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 50, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        got = ctx:Get()
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(80)
            expect(got).eq(0.5) -- painted value before we moved it
        end)

        it("ctx:Target returns the logical target", function()
            local target
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        target = ctx:Target()
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(70)
            expect(target).eq(0.7)
        end)

        it("ctx:Duration returns the resolved duration", function()
            local dur
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transitionDuration = 0.42,
                transition = {
                    Apply = function(ctx, from, to)
                        dur = ctx:Duration()
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(50)
            expect(dur).eq(0.42)
        end)

        it("ctx:Duration falls back to the animBarFill token", function()
            local dur
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        dur = ctx:Duration()
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(50)
            expect(dur).eq(H.token("animBarFill"))
        end)

        it("ctx.state persists across Apply calls", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        ctx.state.calls = (ctx.state.calls or 0) + 1
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(30)
            bar:SetValue(60)
            bar:SetValue(90)
            expect(bar._tctx.state.calls).eq(3)
        end)

        it("ctx.state is a FRESH table after SetTransition switch", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                transition = {
                    Apply = function(ctx, from, to)
                        ctx.state.marker = "old"
                        ctx:Set(to)
                    end,
                },
            }, host)
            H.mount(bar)
            bar:SetValue(50)
            expect(bar._tctx.state.marker).eq("old")

            bar:SetTransition("instant")
            expect(bar._tctx.state.marker).as("fresh state after switch").isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Lifecycle hooks
    ---------------------------------------------------------------------------
    describe("lifecycle hooks", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("Attach fires on adopt", function()
            local attached = false
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                transition = {
                    Apply = function(ctx, _, to) ctx:Set(to) end,
                    Attach = function() attached = true end,
                },
            }, host)
            H.mount(bar)
            expect(attached).truthy()
        end)

        it("Detach and Cancel fire on strategy switch", function()
            local log = {}
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                transition = {
                    Apply = function(ctx, _, to) ctx:Set(to) end,
                    Cancel = function() log[#log + 1] = "cancel" end,
                    Detach = function() log[#log + 1] = "detach" end,
                },
            }, host)
            H.mount(bar)
            bar:SetTransition("instant")
            -- Cancel fires before Detach
            expect(log[1]).eq("cancel")
            expect(log[2]).eq("detach")
        end)

        it("Cancel fires on Destroy", function()
            local cancelled = false
            local detached = false
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                transition = {
                    Apply = function(ctx, _, to) ctx:Set(to) end,
                    Cancel = function() cancelled = true end,
                    Detach = function() detached = true end,
                },
            }, host)
            H.mount(bar)
            bar:Destroy()
            expect(cancelled).truthy()
            expect(detached).truthy()
        end)

        it("hooks fire in correct order: Attach on new, Cancel+Detach on old, Attach on new", function()
            local log = {}
            local function makeStrat(name)
                return {
                    Apply = function(ctx, _, to) ctx:Set(to) end,
                    Attach = function() log[#log + 1] = name .. ":attach" end,
                    Cancel = function() log[#log + 1] = name .. ":cancel" end,
                    Detach = function() log[#log + 1] = name .. ":detach" end,
                }
            end
            Tr:Register("spy_a", makeStrat("A"))
            Tr:Register("spy_b", makeStrat("B"))
            local bar = H.C.StatusBar({ w = 200, h = 16, max = 100,
                                        transition = "spy_a" }, host)
            H.mount(bar)
            expect(log[1]).eq("A:attach")

            bar:SetTransition("spy_b")
            expect(log[2]).eq("A:cancel")
            expect(log[3]).eq("A:detach")
            expect(log[4]).eq("B:attach")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Two bars with same strategy do not share state
    ---------------------------------------------------------------------------
    describe("isolation between bars", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("two bars with smooth do not share ctx.state", function()
            local bar1 = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                         transition = "smooth" }, host)
            local bar2 = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                         transition = "smooth" }, host)
            H.mount(bar1)
            H.mount(bar2)
            expect(bar1._tctx.state).as("states are distinct tables").notNil()
            expect(bar2._tctx.state).notNil()
            -- They must be different table references
            bar1._tctx.state.tag = "bar1"
            expect(bar2._tctx.state.tag).isNil()
        end)

        it("animating one bar does not move the other", function()
            local bar1 = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                         transition = "smooth" }, host)
            local bar2 = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                         transition = "smooth" }, host)
            H.mount(bar1)
            H.mount(bar2)
            bar1:SetValue(100)
            H.tick(H.token("animBarFill") * 0.5)
            -- bar2 must still be at 0
            expect(bar2:GetDisplayPercent()).eq(0)
            expect(bar2:IsTransitioning()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 11. Teardown
    ---------------------------------------------------------------------------
    describe("teardown", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("Destroy leaves no leaked animations", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(H.token("animBarFill") * 0.3)
            -- Mid-transition: there should be an animation active on this owner
            expect(H.SuuUI.Anim:GetActiveCount(bar)).gt(0)
            bar:Destroy()
            expect(H.SuuUI.Anim:GetActiveCount(bar)).eq(0)
        end)

        it("further ticks after Destroy do not error", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(H.token("animBarFill") * 0.2)
            bar:Destroy()
            expect(function()
                H.tick(0.5)
                H.tick(0.5)
            end).notThrows()
        end)

        it("global active count returns to zero after Destroy", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(50)
            H.tick(0.01)
            bar:Destroy()
            -- Run remaining animations
            H.runAnimations()
            expect(H.SuuUI.Anim:GetActiveCount()).eq(0)
        end)
    end)

    ---------------------------------------------------------------------------
    -- SnapToTarget
    ---------------------------------------------------------------------------
    describe("SnapToTarget", function()
        local host
        before_each(function()
            host = H.parent(400, 300)
        end)

        it("immediately paints the target, cancelling any in-flight transition", function()
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host)
            H.mount(bar)
            bar:SetValue(80)
            H.tick(H.token("animBarFill") * 0.3)
            expect(bar:IsTransitioning()).eq(true)
            bar:SnapToTarget()
            expect(bar:GetDisplayPercent()).eq(0.8)
            expect(bar:IsTransitioning()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- H.setup default: barTransitions = false forces instant
    ---------------------------------------------------------------------------
    describe("harness default instant", function()
        it("H.setup() without barTransitions sets default to instant", function()
            H.setup() -- no barTransitions
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100 },
                                       H.parent(400, 300))
            H.mount(bar)
            bar:SetValue(60)
            -- Must be instant, no transition
            expect(bar:GetDisplayPercent()).eq(0.6)
            expect(bar:IsTransitioning()).eq(false)
        end)

        it("explicit transition prop overrides the harness default", function()
            H.setup() -- default instant
            local host2 = H.parent(400, 300)
            local bar = H.C.StatusBar({ w = 200, h = 16, value = 0, max = 100,
                                        transition = "smooth" }, host2)
            H.mount(bar)
            bar:SetValue(60)
            -- Smooth is explicitly named, so it should be transitioning
            expect(bar:IsTransitioning()).eq(true)
            H.runAnimations()
            expect(bar:GetDisplayPercent()).eq(0.6)
        end)
    end)
end)
