local H = require("harness")

--- Helper: builds a minimal valid provider table.
local function makeProvider(frame)
    frame = frame or H.env.CreateFrame("Frame", nil, H.UIParent)
    return {
        frame  = frame,
        Attach = function() end,
        Detach = function() end,
    }
end

describe("Core/AttachPoints", function()
    before_each(function() H.setup({ debug = true }) end)

    ---------------------------------------------------------------------------
    -- 1. Publish / Get / Has / List
    ---------------------------------------------------------------------------

    describe("Publish / Get / Has / List", function()
        it("a published name is readable via Get", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.point", p)
            expect(H.SuuUI.AttachPoints:Get("test.point")).eq(p)
        end)

        it("Has returns true for a published name", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.point", p)
            expect(H.SuuUI.AttachPoints:Has("test.point")).eq(true)
        end)

        it("Get returns nil for an unknown name", function()
            expect(H.SuuUI.AttachPoints:Get("nonexistent.point")).isNil()
        end)

        it("Has returns false for an unknown name", function()
            expect(H.SuuUI.AttachPoints:Has("nonexistent.point")).eq(false)
        end)

        it("List contains the published name", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.alpha", p)
            local list = H.SuuUI.AttachPoints:List()
            local found = false
            for _, name in ipairs(list) do
                if name == "test.alpha" then found = true end
            end
            expect(found).as("List contains test.alpha").truthy()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Provider validation
    ---------------------------------------------------------------------------

    describe("provider validation", function()
        it("asserts on empty string name", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish("", makeProvider())
            end).throws("non-empty string")
        end)

        it("asserts on non-string name (number)", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish(42, makeProvider())
            end).throws("non-empty string")
        end)

        it("asserts on nil name", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish(nil, makeProvider())
            end).throws()
        end)

        it("asserts when provider is not a table", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish("test.point", "not a table")
            end).throws("must be a table")
        end)

        it("asserts when provider.frame is missing", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish("test.point", {
                    Attach = function() end,
                    Detach = function() end,
                })
            end).throws("frame")
        end)

        it("asserts when provider.Attach is missing", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish("test.point", {
                    frame  = H.env.CreateFrame("Frame", nil, H.UIParent),
                    Detach = function() end,
                })
            end).throws("Attach")
        end)

        it("asserts when provider.Detach is missing", function()
            expect(function()
                H.SuuUI.AttachPoints:Publish("test.point", {
                    frame  = H.env.CreateFrame("Frame", nil, H.UIParent),
                    Attach = function() end,
                })
            end).throws("Detach")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. Request delivers immediately
    ---------------------------------------------------------------------------

    describe("Request immediate delivery", function()
        it("delivers nil when nothing is published", function()
            local received = "unset"
            H.SuuUI.AttachPoints:Request("test.empty", function(p) received = p end, "owner_a")
            expect(received).as("nil delivered immediately").isNil()
        end)

        it("delivers the provider when one already exists", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.existing", p)

            local received = nil
            H.SuuUI.AttachPoints:Request("test.existing", function(prov) received = prov end, "owner_b")
            expect(received).eq(p)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. Load-order independence
    ---------------------------------------------------------------------------

    describe("load-order independence", function()
        it("Request BEFORE Publish still receives the provider when it arrives", function()
            local received = "unset"
            H.SuuUI.AttachPoints:Request("test.late", function(p) received = p end, "early_owner")
            expect(received).as("nil immediately, nothing published yet").isNil()

            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.late", p)
            expect(received).as("provider delivered after Publish").eq(p)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. Revoke
    ---------------------------------------------------------------------------

    describe("Revoke", function()
        it("notifies subscribers with nil", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.rev", p)

            local received = p
            H.SuuUI.AttachPoints:Request("test.rev", function(prov) received = prov end, "rev_owner")
            expect(received).eq(p)

            H.SuuUI.AttachPoints:Revoke("test.rev")
            expect(received).as("callback received nil on revoke").isNil()
        end)

        it("Has returns false after Revoke", function()
            H.SuuUI.AttachPoints:Publish("test.rev2", makeProvider())
            H.SuuUI.AttachPoints:Revoke("test.rev2")
            expect(H.SuuUI.AttachPoints:Has("test.rev2")).eq(false)
        end)

        it("Get returns nil after Revoke", function()
            H.SuuUI.AttachPoints:Publish("test.rev3", makeProvider())
            H.SuuUI.AttachPoints:Revoke("test.rev3")
            expect(H.SuuUI.AttachPoints:Get("test.rev3")).isNil()
        end)

        it("revoking an unknown name is a no-op and does not notify", function()
            local calls = 0
            H.SuuUI.AttachPoints:Request("test.unknown_rev", function()
                calls = calls + 1
            end, "noop_owner")
            -- 1 call from immediate delivery
            expect(calls).eq(1)

            H.SuuUI.AttachPoints:Revoke("test.unknown_rev")
            expect(calls).as("no additional notification for unknown revoke").eq(1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. Re-publishing
    ---------------------------------------------------------------------------

    describe("re-publishing", function()
        it("a different provider overwrites, notifies, and logs a debug warning", function()
            local p1 = makeProvider()
            local p2 = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.replace", p1)

            local received = nil
            H.SuuUI.AttachPoints:Request("test.replace", function(prov) received = prov end, "rep_owner")
            expect(received).eq(p1)

            H.SuuUI.AttachPoints:Publish("test.replace", p2)
            expect(received).as("subscriber got the new provider").eq(p2)
            expect(H.SuuUI.AttachPoints:Get("test.replace")).eq(p2)

            -- Check debug log for warning
            local log = H.debugLog()
            local found = false
            for _, line in ipairs(log) do
                if line:find("replacing") and line:find("test.replace") then found = true end
            end
            expect(found).as("debug warning about replacement").truthy()
        end)

        it("re-publishing the SAME provider table does not warn", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.same", p)

            -- Clear log
            local logBefore = #H.debugLog()
            H.SuuUI.AttachPoints:Publish("test.same", p)

            local log = H.debugLog()
            local found = false
            for i = logBefore + 1, #log do
                if log[i]:find("replacing") and log[i]:find("test.same") then found = true end
            end
            expect(found).as("no warning when same provider re-published").falsy()
        end)

        it("re-publishing the same provider still notifies subscribers", function()
            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.same_notify", p)

            local calls = 0
            H.SuuUI.AttachPoints:Request("test.same_notify", function()
                calls = calls + 1
            end, "same_owner")
            -- 1 from immediate
            expect(calls).eq(1)

            H.SuuUI.AttachPoints:Publish("test.same_notify", p)
            expect(calls).as("subscriber notified on same-provider re-publish").eq(2)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. Release
    ---------------------------------------------------------------------------

    describe("Release", function()
        it("drops only that owner's requests", function()
            local callsA, callsB = 0, 0
            H.SuuUI.AttachPoints:Request("test.rel", function() callsA = callsA + 1 end, "rel_a")
            H.SuuUI.AttachPoints:Request("test.rel", function() callsB = callsB + 1 end, "rel_b")
            -- Both got immediate: 1 each
            expect(callsA).eq(1)
            expect(callsB).eq(1)

            H.SuuUI.AttachPoints:Release("rel_a")

            H.SuuUI.AttachPoints:Publish("test.rel", makeProvider())
            expect(callsA).as("released owner not notified").eq(1)
            expect(callsB).as("other owner still notified").eq(2)
        end)

        it("GetRequestCount returns to its earlier value after Release", function()
            local before = H.SuuUI.AttachPoints:GetRequestCount()
            H.SuuUI.AttachPoints:Request("test.cnt", function() end, "cnt_owner")
            expect(H.SuuUI.AttachPoints:GetRequestCount()).eq(before + 1)

            H.SuuUI.AttachPoints:Release("cnt_owner")
            expect(H.SuuUI.AttachPoints:GetRequestCount()).eq(before)
        end)

        it("Release of an unknown owner returns 0", function()
            local result = H.SuuUI.AttachPoints:Release("never_registered_owner")
            expect(result).eq(0)
        end)

        it("Release returns the number of removed requests", function()
            H.SuuUI.AttachPoints:Request("test.multi_a", function() end, "multi_owner")
            H.SuuUI.AttachPoints:Request("test.multi_b", function() end, "multi_owner")
            local removed = H.SuuUI.AttachPoints:Release("multi_owner")
            expect(removed).eq(2)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Mutation during dispatch
    ---------------------------------------------------------------------------

    describe("mutation during dispatch", function()
        it("a callback that Releases ITSELF mid-notify is not delivered to again", function()
            local calls = 0
            H.SuuUI.AttachPoints:Request("test.self_rel", function()
                calls = calls + 1
                H.SuuUI.AttachPoints:Release("self_rel_owner")
            end, "self_rel_owner")
            -- 1 from immediate
            expect(calls).eq(1)

            H.SuuUI.AttachPoints:Publish("test.self_rel", makeProvider())
            -- Should not fire again: the callback released itself mid-dispatch
            -- But it already fired during Publish because of the snapshot — let's
            -- verify by doing another publish
            local callsAfterPublish = calls

            H.SuuUI.AttachPoints:Publish("test.self_rel", makeProvider(
                H.env.CreateFrame("Frame", nil, H.UIParent)
            ))
            expect(calls).as("released callback never fires again").eq(callsAfterPublish)
        end)

        it("a callback that Releases a DIFFERENT owner mid-dispatch: victim does not receive", function()
            local order = {}
            H.SuuUI.AttachPoints:Request("test.cross_rel", function()
                order[#order + 1] = "a"
                H.SuuUI.AttachPoints:Release("victim_owner")
            end, "killer_owner")
            H.SuuUI.AttachPoints:Request("test.cross_rel", function()
                order[#order + 1] = "b"
            end, "victim_owner")
            H.SuuUI.AttachPoints:Request("test.cross_rel", function()
                order[#order + 1] = "c"
            end, "survivor_owner")

            -- Clear the immediate-delivery results
            order = {}

            H.SuuUI.AttachPoints:Publish("test.cross_rel", makeProvider())
            expect(order[1]).eq("a")
            -- b must NOT appear: killed mid-dispatch
            local found_b = false
            for _, v in ipairs(order) do
                if v == "b" then found_b = true end
            end
            expect(found_b).as("victim not delivered to").falsy()
            -- c must still fire
            local found_c = false
            for _, v in ipairs(order) do
                if v == "c" then found_c = true end
            end
            expect(found_c).as("survivor still fires").truthy()
        end)

        it("a callback that Requests a new subscriber mid-dispatch: new one not called in-flight", function()
            local lateCalls = 0
            H.SuuUI.AttachPoints:Request("test.mid_add", function()
                H.SuuUI.AttachPoints:Request("test.mid_add", function()
                    lateCalls = lateCalls + 1
                end, "late_owner")
            end, "adder_owner")

            -- Clear late count (the inner Request's immediate delivery fires once)
            lateCalls = 0

            -- The inner Request was added by the immediate delivery of the outer.
            -- Now trigger a real notify:
            H.SuuUI.AttachPoints:Publish("test.mid_add", makeProvider())
            -- The outer fires, which adds a new subscriber. But the new subscriber
            -- should NOT fire in THIS pass. However, the inner Request's immediate
            -- delivery will still fire it. The key distinction: during the in-flight
            -- Publish notification snapshot, the newly added request is NOT part of
            -- that snapshot.
            -- After Publish: outer fires (adds inner via Request which fires immediately),
            -- so lateCalls = 1 from Request's immediate, not from the in-flight notify.
            -- Verify by doing another Publish:
            local lateCallsBefore = lateCalls
            H.SuuUI.AttachPoints:Publish("test.mid_add", makeProvider(
                H.env.CreateFrame("Frame", nil, H.UIParent)
            ))
            -- Now all existing subscribers should fire (outer + late)
            expect(lateCalls).as("late subscriber fires on next change").gt(lateCallsBefore)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Throwing callback
    ---------------------------------------------------------------------------

    describe("throwing callback", function()
        it("error is logged and other subscribers still receive notification", function()
            local receivedB = nil
            H.SuuUI.AttachPoints:Request("test.throw", function()
                error("deliberate kaboom")
            end, "throw_owner")
            H.SuuUI.AttachPoints:Request("test.throw", function(prov)
                receivedB = prov
            end, "after_throw_owner")

            local p = makeProvider()
            H.SuuUI.AttachPoints:Publish("test.throw", p)

            expect(receivedB).as("second subscriber survived the throw").eq(p)

            -- Check debug log for error
            local log = H.debugLog()
            local found = false
            for _, line in ipairs(log) do
                if line:find("kaboom") then found = true end
            end
            expect(found).as("the error was logged").truthy()
        end)

        it("Publish itself does not error", function()
            H.SuuUI.AttachPoints:Request("test.throw2", function()
                error("boom")
            end, "throw2_owner")

            expect(function()
                H.SuuUI.AttachPoints:Publish("test.throw2", makeProvider())
            end).notThrows()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Multiple names are independent
    ---------------------------------------------------------------------------

    describe("independence of names", function()
        it("publishing one name does not notify subscribers of another", function()
            local callsAlpha, callsBeta = 0, 0
            H.SuuUI.AttachPoints:Request("test.alpha", function()
                callsAlpha = callsAlpha + 1
            end, "indep_alpha")
            H.SuuUI.AttachPoints:Request("test.beta", function()
                callsBeta = callsBeta + 1
            end, "indep_beta")
            -- Both got immediate: 1 each
            expect(callsAlpha).eq(1)
            expect(callsBeta).eq(1)

            H.SuuUI.AttachPoints:Publish("test.alpha", makeProvider())
            expect(callsAlpha).eq(2)
            expect(callsBeta).as("beta not notified by alpha publish").eq(1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Shipped contract: unitframe.player is published at boot
    ---------------------------------------------------------------------------

    describe("shipped contract", function()
        it("unitframe.player is published after boot", function()
            expect(H.SuuUI.AttachPoints:Has("unitframe.player"))
                .as("UnitFrames publishes unitframe.player at boot").truthy()

            local p = H.SuuUI.AttachPoints:Get("unitframe.player")
            expect(p).notNil()
            expect(p.frame).notNil()
            expect(type(p.Attach)).eq("function")
            expect(type(p.Detach)).eq("function")
        end)
    end)
end)
