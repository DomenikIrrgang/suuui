local H = require("harness")

--------------------------------------------------------------------------------
-- PART A: EventBus dispatch safety
--------------------------------------------------------------------------------

describe("EventBus dispatch safety", function()
    before_each(function() H.setup() end)

    it("Off mid-dispatch: first listener removes another, all remaining fire once", function()
        -- The heart of the bug: listener A removes listener B during dispatch. Before the
        -- snapshot fix, removing B shifted indices and either double-fired C or skipped it.
        local counters = { a = 0, b = 0, c = 0 }
        H.SuuUI.Events:On("MID_OFF", function()
            counters.a = counters.a + 1
            H.SuuUI.Events:Off("MID_OFF", "owner_b")
        end, "owner_a")
        H.SuuUI.Events:On("MID_OFF", function()
            counters.b = counters.b + 1
        end, "owner_b")
        H.SuuUI.Events:On("MID_OFF", function()
            counters.c = counters.c + 1
        end, "owner_c")

        H.SuuUI.Events:Emit("MID_OFF")

        expect(counters.a).as("first listener fires once").eq(1)
        expect(counters.b).as("removed listener does not fire").eq(0)
        expect(counters.c).as("remaining listener fires once").eq(1)
    end)

    it("self-removal mid-dispatch: the others still fire exactly once", function()
        local counters = { self = 0, other1 = 0, other2 = 0 }
        H.SuuUI.Events:On("SELF_OFF", function()
            counters.self = counters.self + 1
            H.SuuUI.Events:Off("SELF_OFF", "self_owner")
        end, "self_owner")
        H.SuuUI.Events:On("SELF_OFF", function()
            counters.other1 = counters.other1 + 1
        end, "other1")
        H.SuuUI.Events:On("SELF_OFF", function()
            counters.other2 = counters.other2 + 1
        end, "other2")

        H.SuuUI.Events:Emit("SELF_OFF")

        expect(counters.self).as("self-removing listener fires once").eq(1)
        expect(counters.other1).as("sibling 1 fires once").eq(1)
        expect(counters.other2).as("sibling 2 fires once").eq(1)
    end)

    it("OffAll mid-dispatch does not break in-flight emit", function()
        local counters = { nuker = 0, sibling = 0 }
        H.SuuUI.Events:On("NUKE_ALL", function()
            counters.nuker = counters.nuker + 1
            H.SuuUI.Events:OffAll("owner_sibling")
        end, "owner_nuker")
        H.SuuUI.Events:On("NUKE_ALL", function()
            counters.sibling = counters.sibling + 1
        end, "owner_sibling")

        expect(function() H.SuuUI.Events:Emit("NUKE_ALL") end).notThrows()
        expect(counters.nuker).as("the one that called OffAll fires").eq(1)
        expect(counters.sibling).as("OffAll victim is dead-flagged, not fired").eq(0)
    end)

    it("Once fires exactly once and does not disturb siblings", function()
        local once_count, normal_count = 0, 0
        H.SuuUI.Events:Once("ONCE_TEST", function()
            once_count = once_count + 1
        end, "once_owner")
        H.SuuUI.Events:On("ONCE_TEST", function()
            normal_count = normal_count + 1
        end, "normal_owner")

        H.SuuUI.Events:Emit("ONCE_TEST")
        H.SuuUI.Events:Emit("ONCE_TEST")

        expect(once_count).as("Once fires on first emit only").eq(1)
        expect(normal_count).as("normal listener fires both times").eq(2)
    end)

    it("a throwing callback does not stop the remaining listeners", function()
        local after_throw = 0
        H.SuuUI.Events:On("THROW_TEST", function() error("kaboom") end, "thrower")
        H.SuuUI.Events:On("THROW_TEST", function() after_throw = after_throw + 1 end, "survivor")

        expect(function() H.SuuUI.Events:Emit("THROW_TEST") end).notThrows()
        expect(after_throw).eq(1)
    end)

    it("re-entrant emit does not infinitely recurse or double-deliver the outer pass", function()
        local outer_count, inner_count = 0, 0
        local depth = 0
        H.SuuUI.Events:On("REENTRANT", function()
            outer_count = outer_count + 1
            if depth == 0 then
                depth = 1
                H.SuuUI.Events:Emit("REENTRANT")
            end
        end, "re_owner")

        -- Track inner emission via a second listener
        H.SuuUI.Events:On("REENTRANT", function()
            inner_count = inner_count + 1
        end, "counter_owner")

        H.SuuUI.Events:Emit("REENTRANT")

        -- The outer emit fires both listeners once. The inner re-entrant emit (triggered
        -- by the first listener) fires both listeners once more. Total: 2 each.
        expect(outer_count).as("first listener: outer + inner").eq(2)
        expect(inner_count).as("second listener: outer + inner").eq(2)
    end)

    it("Off for an owner with several listeners on one event removes all of them", function()
        local counts = { a = 0, b = 0, c = 0 }
        H.SuuUI.Events:On("MULTI_OFF", function() counts.a = counts.a + 1 end, "bulk")
        H.SuuUI.Events:On("MULTI_OFF", function() counts.b = counts.b + 1 end, "bulk")
        H.SuuUI.Events:On("MULTI_OFF", function() counts.c = counts.c + 1 end, "bulk")

        H.SuuUI.Events:Off("MULTI_OFF", "bulk")
        H.SuuUI.Events:Emit("MULTI_OFF")

        expect(counts.a + counts.b + counts.c).as("all callbacks for owner removed").eq(0)
    end)
end)

--------------------------------------------------------------------------------
-- PART B: Pool recycling reset
--------------------------------------------------------------------------------

describe("Pool recycling reset", function()
    before_each(function() H.setup() end)

    local function registerWidget()
        H.SuuUI.Pool:Register("spec.widget", function(parent)
            local f = H.env.CreateFrame("Frame", nil, parent)
            f:SetSize(80, 20)
            return f
        end)
    end

    it("clears all scripts on release so a recycled frame has no stale handlers", function()
        registerWidget()
        local host = H.parent(200, 200)
        local f = H.SuuUI.Pool:Acquire("spec.widget", host)

        -- Simulate previous owner attaching scripts
        local scripts = { "OnEnter", "OnLeave", "OnMouseUp", "OnUpdate", "OnSizeChanged" }
        for _, s in ipairs(scripts) do
            if f:HasScript(s) then f:SetScript(s, function() end) end
        end

        H.SuuUI.Pool:Release("spec.widget", f)
        local recycled = H.SuuUI.Pool:Acquire("spec.widget", host)

        expect(recycled).as("same frame recycled").eq(f)
        for _, s in ipairs(scripts) do
            if recycled:HasScript(s) then
                expect(recycled:GetScript(s)).as(s .. " must be nil after reset").isNil()
            end
        end
    end)

    it("resets alpha and scale to 1, clears _layoutProps and _anchor, hidden while pooled", function()
        registerWidget()
        local host = H.parent(200, 200)
        local f = H.SuuUI.Pool:Acquire("spec.widget", host)

        f:SetAlpha(0.3)
        f:SetScale(2.5)
        f._layoutProps = { width = "fill" }
        f._anchor = { point = "TOPLEFT" }
        f:SetPoint("CENTER", host, "CENTER", 0, 0)

        H.SuuUI.Pool:Release("spec.widget", f)

        expect(f:IsShown()).as("hidden while pooled").falsy()
        expect(f:GetNumPoints()).as("no anchors while pooled").eq(0)
        expect(f:GetAlpha()).as("alpha reset to 1").eq(1)
        expect(f:GetScale()).as("scale reset to 1").eq(1)
        expect(f._layoutProps).as("_layoutProps cleared").isNil()
        expect(f._anchor).as("_anchor cleared").isNil()
    end)

    it("UISignals connections are gone after release", function()
        registerWidget()
        local host = H.parent(200, 200)
        local f = H.SuuUI.Pool:Acquire("spec.widget", host)

        local fired = false
        H.SuuUI.UISignals:Connect(f, "VALUE_CHANGED", function() fired = true end)

        H.SuuUI.Pool:Release("spec.widget", f)

        -- Emit on the now-pooled frame: the old listener must not fire
        H.SuuUI.UISignals:Emit(f, "VALUE_CHANGED", 1, 0)
        expect(fired).as("signal listener removed on release").falsy()
    end)

    it("ReleaseAll resets every active frame the same way and they return to the pool", function()
        registerWidget()
        local host = H.parent(200, 200)
        local frames = {}
        for i = 1, 3 do
            local f = H.SuuUI.Pool:Acquire("spec.widget", host)
            f:SetAlpha(0.5)
            f:SetScale(3)
            if f:HasScript("OnUpdate") then f:SetScript("OnUpdate", function() end) end
            frames[i] = f
        end

        H.SuuUI.Pool:ReleaseAll("spec.widget")

        for _, f in ipairs(frames) do
            expect(f:IsShown()).as("hidden after ReleaseAll").falsy()
            expect(f:GetAlpha()).as("alpha reset").eq(1)
            expect(f:GetScale()).as("scale reset").eq(1)
            if f:HasScript("OnUpdate") then
                expect(f:GetScript("OnUpdate")).as("OnUpdate nil after ReleaseAll").isNil()
            end
        end

        -- They return to the pool
        local reacquired = H.SuuUI.Pool:Acquire("spec.widget", host)
        local wasOurs = false
        for _, f in ipairs(frames) do
            if f == reacquired then wasOurs = true end
        end
        expect(wasOurs).as("released frames are recycled from pool").truthy()
    end)

    it("Acquire reuses a pooled frame (identity) and re-parents it", function()
        registerWidget()
        local a = H.parent(100, 100)
        local b = H.parent(100, 100)

        local f = H.SuuUI.Pool:Acquire("spec.widget", a)
        H.SuuUI.Pool:Release("spec.widget", f)

        local recycled = H.SuuUI.Pool:Acquire("spec.widget", b)
        expect(recycled).as("same frame object reused").eq(f)
        expect(recycled:GetParent()).as("re-parented to new host").eq(b)
    end)

    it("releasing a frame not tracked by the pool is a no-op", function()
        registerWidget()
        local stranger = H.parent(10, 10)
        expect(function() H.SuuUI.Pool:Release("spec.widget", stranger) end).notThrows()
    end)

    it("acquiring an unregistered typeId asserts", function()
        expect(function() H.SuuUI.Pool:Acquire("spec.never_registered", H.UIParent) end)
            .throws("unregistered typeId")
    end)
end)
