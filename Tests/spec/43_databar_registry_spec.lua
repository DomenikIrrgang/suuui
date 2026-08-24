local H = require("harness")

-- Every field the registry actually reads is declared here, so a test about placement is
-- never also a test about a default it forgot to state.
local function mkdef(id, props)
    local d = { id = id, GetText = function() return id end }
    for k, v in pairs(props or {}) do d[k] = v end
    return d
end

local function ids(list)
    local out = {}
    for i = 1, #list do out[i] = list[i].id end
    return out
end

-- The shipped DataBar plugin registers databar.time at boot, so a spec about ordering
-- starts from a registry that is not empty. Clearing through the public API rather than
-- reaching into the module also exercises List()'s copy contract: unregistering while
-- iterating the returned array is only safe because it is not the live one.
local function clearWidgets(DB)
    for _, d in ipairs(DB:List()) do DB:UnregisterWidget(d.id) end
end

-- Lines the debug log gained after `from`. Boot and the shipped plugin both log, so a
-- search over the whole log would match something a test never caused.
local function logSince(from)
    local log, out = H.debugLog(), {}
    for i = from + 1, #log do out[#out + 1] = log[i] end
    return out
end

local function logHas(from, needle)
    for _, line in ipairs(logSince(from)) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

-- Two bar heights as the renderer derives one: a row of text plus its padding, tight and
-- generous. Stated through tokens so the spec follows a theme change instead of
-- contradicting it, and distinct from each other so a test can watch a real move.
local function barHeight()
    return H.lineHeight(H.token("fontSizeMd")) + H.token("spaceXs") * 2
end

local function tallBarHeight()
    return H.lineHeight(H.token("fontSizeMd")) + H.token("spaceLg") * 2
end

-- Boot leaves the shipped bar's own occupied height on the registry, and it is
-- token-derived like everything else here -- sizeRow, as it happens. So a test that wants
-- to observe a CHANGE has to start from a height it named itself: writing the value the
-- registry already holds is the documented no-op, and an assertion made after one passes
-- whether or not notification works at all.
local function startAt(DB, h)
    DB:SetOccupiedHeight(h)
    expect(DB:GetOccupiedHeight()).as("starting height established").eq(h)
    return h
end

describe("Core/DataBar", function()
    local DB
    before_each(function()
        H.setup({ debug = true })
        DB = H.SuuUI.DataBar
    end)

    ---------------------------------------------------------------------------
    -- 1. RegisterWidget validation
    ---------------------------------------------------------------------------

    describe("RegisterWidget validation", function()
        it("raises when the definition is not a table", function()
            expect(function() DB:RegisterWidget("not a table") end).throws("must be a table")
        end)

        it("raises when the definition is nil", function()
            expect(function() DB:RegisterWidget(nil) end).throws("must be a table")
        end)

        it("raises when id is missing", function()
            expect(function()
                DB:RegisterWidget({ GetText = function() return "" end })
            end).throws("non-empty string")
        end)

        it("raises when id is the empty string", function()
            expect(function() DB:RegisterWidget(mkdef("")) end).throws("non-empty string")
        end)

        it("raises when id is not a string", function()
            expect(function() DB:RegisterWidget(mkdef(42)) end).throws("non-empty string")
        end)

        it("raises when neither GetText nor Build is given", function()
            expect(function()
                DB:RegisterWidget({ id = "spec.textless" })
            end).throws("needs GetText or Build")
        end)

        it("accepts Build alone, so the requirement is a real either-or", function()
            expect(function()
                DB:RegisterWidget({ id = "spec.built", Build = function() end })
            end).notThrows()
            expect(DB:Has("spec.built")).as("a Build-only widget is registered").eq(true)
        end)

        it("raises on an unknown section", function()
            expect(function()
                DB:RegisterWidget(mkdef("spec.bad_section", { section = "middle" }))
            end).throws("unknown section")
        end)

        it("names the offending section in the message", function()
            expect(function()
                DB:RegisterWidget(mkdef("spec.bad_section2", { section = "middle" }))
            end).throws("middle")
        end)

        it("raises on a non-number order", function()
            expect(function()
                DB:RegisterWidget(mkdef("spec.bad_order", { order = "first" }))
            end).throws("order must be a number")
        end)

        it("a rejected definition is not registered", function()
            pcall(function()
                DB:RegisterWidget(mkdef("spec.rejected", { section = "middle" }))
            end)
            expect(DB:Has("spec.rejected")).as("nothing half-registered").eq(false)
        end)

        it("a rejected definition does not notify subscribers", function()
            local calls = 0
            DB:Subscribe(function() calls = calls + 1 end, "spec.reject_watch")
            expect(calls).as("immediate delivery only").eq(1)

            pcall(function() DB:RegisterWidget(mkdef("spec.rejected2", { section = "middle" })) end)
            expect(calls).as("a raise does not fire a rebuild").eq(1)
        end)

        it("accepts every declared section", function()
            for _, section in ipairs({ "left", "center", "right" }) do
                expect(function()
                    DB:RegisterWidget(mkdef("spec." .. section, { section = section }))
                end).as(section .. " is accepted").notThrows()
            end
            expect(#DB.SECTIONS).as("SECTIONS names exactly the accepted set").eq(3)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Defaults
    ---------------------------------------------------------------------------

    describe("defaults", function()
        it("section defaults to left", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.defaulted"))

            expect(ids(DB:ListSection("left")))
                .as("an unstated section lands in left").deepEq({ "spec.defaulted" })
            expect(#DB:ListSection("center")).eq(0)
            expect(#DB:ListSection("right")).eq(0)
        end)

        -- Order is only observable through placement, so the default is bracketed from both
        -- sides against an explicit 100. Each half alone would also pass for a default on
        -- the wrong side of 100; together they pin it to exactly 100.
        it("order defaults to no LESS than an explicit 100", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.zz_default"))
            DB:RegisterWidget(mkdef("spec.mm_explicit", { order = 100 }))

            expect(ids(DB:List()))
                .as("equal orders fall through to the id, so mm precedes zz")
                .deepEq({ "spec.mm_explicit", "spec.zz_default" })
        end)

        it("order defaults to no MORE than an explicit 100", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.aa_default"))
            DB:RegisterWidget(mkdef("spec.mm_explicit", { order = 100 }))

            expect(ids(DB:List()))
                .as("equal orders fall through to the id, so aa precedes mm")
                .deepEq({ "spec.aa_default", "spec.mm_explicit" })
        end)

        it("the default order sits between an explicit 99 and an explicit 101", function()
            clearWidgets(DB)
            -- Ids chosen so that alphabetical order contradicts the expected order: if the
            -- sort ignored `order` entirely this would come out reversed.
            DB:RegisterWidget(mkdef("spec.c_low", { order = 99 }))
            DB:RegisterWidget(mkdef("spec.b_default"))
            DB:RegisterWidget(mkdef("spec.a_high", { order = 101 }))

            expect(ids(DB:List())).deepEq({ "spec.c_low", "spec.b_default", "spec.a_high" })
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. List ordering
    ---------------------------------------------------------------------------

    describe("List ordering", function()
        it("sorts by section before order", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.r", { section = "right",  order = 1 }))
            DB:RegisterWidget(mkdef("spec.c", { section = "center", order = 500 }))
            DB:RegisterWidget(mkdef("spec.l", { section = "left",   order = 900 }))

            expect(ids(DB:List()))
                .as("screen order wins over order within a section")
                .deepEq({ "spec.l", "spec.c", "spec.r" })
        end)

        it("sorts by order within a section", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.a_third", { section = "left", order = 30 }))
            DB:RegisterWidget(mkdef("spec.b_first", { section = "left", order = 10 }))
            DB:RegisterWidget(mkdef("spec.c_second", { section = "left", order = 20 }))

            expect(ids(DB:List()))
                .deepEq({ "spec.b_first", "spec.c_second", "spec.a_third" })
        end)

        -- Deliberately more than a pair. With the id tiebreak gone the comparator is
        -- inconsistent for equal placements, so table.sort returns some permutation of
        -- whatever pairs() yielded -- and for two entries that permutation is ascending
        -- half the time, which is a test that passes by luck. Eight entries registered in
        -- descending order makes the catch reliable.
        local TIED = { "spec.h", "spec.g", "spec.f", "spec.e",
                       "spec.d", "spec.c", "spec.b", "spec.a" }
        local TIED_SORTED = { "spec.a", "spec.b", "spec.c", "spec.d",
                              "spec.e", "spec.f", "spec.g", "spec.h" }

        it("falls through to the id when section and order are equal", function()
            clearWidgets(DB)
            for _, id in ipairs(TIED) do
                DB:RegisterWidget(mkdef(id, { section = "center", order = 50 }))
            end

            expect(ids(DB:List()))
                .as("the id is the final key, so the order is ascending by id")
                .deepEq(TIED_SORTED)
        end)

        -- The id tiebreak is what makes the result total rather than partial. Without it
        -- widgets sharing a section and an order come out in table order, which is hash
        -- order: the same set registered the other way round can answer differently, and
        -- the bar would swap its fields on some logins.
        it("answers the same for the same set whichever way round it was registered", function()
            clearWidgets(DB)
            for _, id in ipairs(TIED) do
                DB:RegisterWidget(mkdef(id, { section = "center", order = 50 }))
            end
            local descending = ids(DB:List())

            clearWidgets(DB)
            for i = #TIED, 1, -1 do
                DB:RegisterWidget(mkdef(TIED[i], { section = "center", order = 50 }))
            end
            local ascending = ids(DB:List())

            expect(ascending).as("insertion order does not reach the result").deepEq(descending)
            expect(descending).deepEq(TIED_SORTED)
        end)

        it("is stable across repeated calls", function()
            clearWidgets(DB)
            for _, id in ipairs(TIED) do
                DB:RegisterWidget(mkdef(id, { section = "left", order = 100 }))
            end
            local first = ids(DB:List())
            expect(ids(DB:List())).deepEq(first)
            expect(ids(DB:List())).deepEq(first)
            expect(first).deepEq(TIED_SORTED)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. List returns a copy
    ---------------------------------------------------------------------------

    describe("List returns a copy", function()
        it("mutating the returned array does not reorder the bar", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.one",   { section = "left",  order = 10 }))
            DB:RegisterWidget(mkdef("spec.two",   { section = "left",  order = 20 }))
            DB:RegisterWidget(mkdef("spec.three", { section = "right", order = 10 }))

            local taken = DB:List()
            expect(ids(taken)).deepEq({ "spec.one", "spec.two", "spec.three" })

            -- Reverse it, drop an entry, and append a stranger: everything a caller who
            -- believed the array was theirs might do.
            local reversed = {}
            for i = #taken, 1, -1 do reversed[#reversed + 1] = taken[i] end
            for i = 1, #taken do taken[i] = reversed[i] end
            table.remove(taken, 1)
            taken[#taken + 1] = mkdef("spec.stranger")

            expect(ids(DB:List()))
                .as("a second List is unaffected by what was done to the first")
                .deepEq({ "spec.one", "spec.two", "spec.three" })
        end)

        it("hands out a different array each call", function()
            expect(DB:List()).as("not the internal array").neq(DB:List())
        end)

        it("clearing the returned array leaves the registry intact", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.kept"))

            local taken = DB:List()
            for i = #taken, 1, -1 do taken[i] = nil end

            expect(#DB:List()).as("the registry still holds it").eq(1)
            expect(DB:Has("spec.kept")).eq(true)
        end)

        it("ListSection also returns a copy", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.s1", { section = "right", order = 10 }))
            DB:RegisterWidget(mkdef("spec.s2", { section = "right", order = 20 }))

            local taken = DB:ListSection("right")
            table.remove(taken, 1)

            expect(ids(DB:ListSection("right"))).deepEq({ "spec.s1", "spec.s2" })
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. ListSection
    ---------------------------------------------------------------------------

    describe("ListSection", function()
        it("returns only that section, in order", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.l2", { section = "left",   order = 20 }))
            DB:RegisterWidget(mkdef("spec.l1", { section = "left",   order = 10 }))
            DB:RegisterWidget(mkdef("spec.c1", { section = "center", order = 10 }))
            DB:RegisterWidget(mkdef("spec.r1", { section = "right",  order = 10 }))

            expect(ids(DB:ListSection("left"))).deepEq({ "spec.l1", "spec.l2" })
            expect(ids(DB:ListSection("center"))).deepEq({ "spec.c1" })
            expect(ids(DB:ListSection("right"))).deepEq({ "spec.r1" })
        end)

        it("returns an empty array for a section nothing sits in", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.only", { section = "left" }))
            expect(#DB:ListSection("right")).eq(0)
        end)

        it("returns an empty array for a section that does not exist", function()
            expect(#DB:ListSection("middle")).as("no match, no raise").eq(0)
        end)

        it("the sections partition List", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.p1", { section = "left" }))
            DB:RegisterWidget(mkdef("spec.p2", { section = "center" }))
            DB:RegisterWidget(mkdef("spec.p3", { section = "right" }))
            DB:RegisterWidget(mkdef("spec.p4", { section = "left", order = 200 }))

            local total = 0
            for _, section in ipairs(DB.SECTIONS) do
                total = total + #DB:ListSection(section)
            end
            expect(total).as("every widget is in exactly one section").eq(#DB:List())
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. Has / GetWidget / UnregisterWidget
    ---------------------------------------------------------------------------

    describe("Has / GetWidget", function()
        it("Has is true for a registered id and false for an unknown one", function()
            DB:RegisterWidget(mkdef("spec.known"))
            expect(DB:Has("spec.known")).eq(true)
            expect(DB:Has("spec.unknown")).eq(false)
        end)

        it("GetWidget returns the definition that was registered", function()
            local d = mkdef("spec.get")
            DB:RegisterWidget(d)
            expect(DB:GetWidget("spec.get")).eq(d)
        end)

        it("GetWidget returns nil for an unknown id", function()
            expect(DB:GetWidget("spec.nope")).isNil()
        end)
    end)

    describe("UnregisterWidget", function()
        it("removes the widget from Has, GetWidget and List", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.doomed"))
            DB:RegisterWidget(mkdef("spec.survivor"))

            DB:UnregisterWidget("spec.doomed")

            expect(DB:Has("spec.doomed")).eq(false)
            expect(DB:GetWidget("spec.doomed")).isNil()
            expect(ids(DB:List())).deepEq({ "spec.survivor" })
        end)

        it("re-sorts what is left rather than leaving a hole", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.a", { section = "left",  order = 10 }))
            DB:RegisterWidget(mkdef("spec.b", { section = "left",  order = 20 }))
            DB:RegisterWidget(mkdef("spec.c", { section = "right", order = 10 }))

            DB:UnregisterWidget("spec.b")
            expect(ids(DB:List())).deepEq({ "spec.a", "spec.c" })
        end)

        it("unregistering an unknown id is a no-op and does not notify", function()
            local calls = 0
            DB:Subscribe(function() calls = calls + 1 end, "spec.noop")
            expect(calls).eq(1)

            DB:UnregisterWidget("spec.never_registered")
            expect(calls).as("no rebuild for a no-op").eq(1)
        end)

        it("a re-registered id comes back", function()
            DB:RegisterWidget(mkdef("spec.cycle"))
            DB:UnregisterWidget("spec.cycle")
            DB:RegisterWidget(mkdef("spec.cycle"))
            expect(DB:Has("spec.cycle")).eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. Subscribe / Unsubscribe
    ---------------------------------------------------------------------------

    describe("Subscribe", function()
        it("raises when cb is not a function", function()
            expect(function() DB:Subscribe("nope", "spec.owner") end)
                .throws("cb must be a function")
        end)

        it("raises when owner is missing", function()
            expect(function() DB:Subscribe(function() end, nil) end)
                .throws("owner must be a non-empty string")
        end)

        it("raises when owner is the empty string", function()
            expect(function() DB:Subscribe(function() end, "") end)
                .throws("owner must be a non-empty string")
        end)

        it("fires immediately exactly once at registration", function()
            local calls = 0
            DB:Subscribe(function() calls = calls + 1 end, "spec.immediate")
            expect(calls).as("once, before anything changed").eq(1)
        end)

        it("the immediate call carries no payload", function()
            local args = "unset"
            DB:Subscribe(function(...) args = select("#", ...) end, "spec.payload")
            expect(args).as("a subscriber re-reads the set instead of being handed it").eq(0)
        end)

        it("fires again on every register and unregister", function()
            local calls = 0
            DB:Subscribe(function() calls = calls + 1 end, "spec.counter")
            expect(calls).eq(1)

            DB:RegisterWidget(mkdef("spec.n1"))
            expect(calls).as("register").eq(2)

            DB:RegisterWidget(mkdef("spec.n2"))
            expect(calls).as("second register").eq(3)

            DB:UnregisterWidget("spec.n1")
            expect(calls).as("unregister").eq(4)

            DB:UnregisterWidget("spec.n2")
            expect(calls).as("second unregister").eq(5)
        end)

        it("a change notification carries no payload either", function()
            local count = "unset"
            DB:Subscribe(function(...) count = select("#", ...) end, "spec.payload2")
            count = "unset"
            DB:RegisterWidget(mkdef("spec.payload_trigger"))
            expect(count).eq(0)
        end)

        it("sees the new widget when it reads the set from inside the callback", function()
            local seen
            DB:Subscribe(function() seen = DB:Has("spec.visible") end, "spec.reader")
            DB:RegisterWidget(mkdef("spec.visible"))
            expect(seen).as("the registry is updated before subscribers run").eq(true)
        end)

        it("every subscriber is notified", function()
            local a, b, c = 0, 0, 0
            DB:Subscribe(function() a = a + 1 end, "spec.a")
            DB:Subscribe(function() b = b + 1 end, "spec.b")
            DB:Subscribe(function() c = c + 1 end, "spec.c")

            DB:RegisterWidget(mkdef("spec.broadcast"))
            expect(a).eq(2)
            expect(b).eq(2)
            expect(c).eq(2)
        end)
    end)

    describe("Unsubscribe", function()
        it("drops only that owner's subscriptions", function()
            local a, b = 0, 0
            DB:Subscribe(function() a = a + 1 end, "spec.keep")
            DB:Subscribe(function() b = b + 1 end, "spec.drop")

            DB:Unsubscribe("spec.drop")
            DB:RegisterWidget(mkdef("spec.after_unsub"))

            expect(a).as("the surviving owner still fires").eq(2)
            expect(b).as("the dropped owner does not").eq(1)
        end)

        it("returns how many it removed", function()
            DB:Subscribe(function() end, "spec.multi")
            DB:Subscribe(function() end, "spec.multi")
            expect(DB:Unsubscribe("spec.multi")).eq(2)
        end)

        it("returns 0 for an unknown owner", function()
            expect(DB:Unsubscribe("spec.never")).eq(0)
        end)

        it("returns 0 for a non-string owner", function()
            expect(DB:Unsubscribe(42)).eq(0)
            expect(DB:Unsubscribe(nil)).eq(0)
        end)

        it("GetSubscriberCount returns to its starting value", function()
            local before = DB:GetSubscriberCount()
            DB:Subscribe(function() end, "spec.leak")
            DB:Subscribe(function() end, "spec.leak")
            expect(DB:GetSubscriberCount()).as("both counted").eq(before + 2)

            DB:Unsubscribe("spec.leak")
            expect(DB:GetSubscriberCount()).as("no leak").eq(before)
        end)

        it("an unknown-owner Unsubscribe does not move the count", function()
            local before = DB:GetSubscriberCount()
            DB:Unsubscribe("spec.never")
            DB:Unsubscribe(42)
            expect(DB:GetSubscriberCount()).eq(before)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Mutation during dispatch
    --
    -- What the snapshot and the dead flag in notify() exist for. Walking the live list
    -- instead would shift the array under the loop index, so the subscriber AFTER the one
    -- that tore itself down would be skipped silently.
    ---------------------------------------------------------------------------

    describe("mutation during dispatch", function()
        it("a subscriber that unsubscribes ITSELF does not stop the ones after it", function()
            local order, armed = {}, false
            DB:Subscribe(function() order[#order + 1] = "first" end, "spec.first")
            DB:Subscribe(function()
                order[#order + 1] = "middle"
                if armed then DB:Unsubscribe("spec.middle") end
            end, "spec.middle")
            DB:Subscribe(function() order[#order + 1] = "third" end, "spec.third")

            order, armed = {}, true
            DB:RegisterWidget(mkdef("spec.dispatch"))

            expect(order).as("the whole dispatch completed").deepEq({ "first", "middle", "third" })
        end)

        it("the self-unsubscribed subscriber is gone from the next dispatch", function()
            local order, armed = {}, false
            DB:Subscribe(function() order[#order + 1] = "first" end, "spec.first")
            DB:Subscribe(function()
                order[#order + 1] = "middle"
                if armed then DB:Unsubscribe("spec.middle") end
            end, "spec.middle")
            DB:Subscribe(function() order[#order + 1] = "third" end, "spec.third")

            armed = true
            DB:RegisterWidget(mkdef("spec.dispatch1"))
            order = {}
            DB:RegisterWidget(mkdef("spec.dispatch2"))

            expect(order).as("middle really did unsubscribe").deepEq({ "first", "third" })
        end)

        it("self-unsubscribing mid-dispatch does not corrupt the count", function()
            local before = DB:GetSubscriberCount()
            local armed = false
            DB:Subscribe(function()
                if armed then DB:Unsubscribe("spec.selfish") end
            end, "spec.selfish")
            armed = true

            DB:RegisterWidget(mkdef("spec.count_check"))
            expect(DB:GetSubscriberCount()).as("exactly one subscription removed").eq(before)
        end)

        it("a subscriber killed by ANOTHER one mid-dispatch is not delivered to", function()
            local order, armed = {}, false
            DB:Subscribe(function()
                order[#order + 1] = "killer"
                if armed then DB:Unsubscribe("spec.victim") end
            end, "spec.killer")
            DB:Subscribe(function() order[#order + 1] = "victim" end, "spec.victim")
            DB:Subscribe(function() order[#order + 1] = "survivor" end, "spec.survivor")

            order, armed = {}, true
            DB:RegisterWidget(mkdef("spec.cross_kill"))

            expect(order)
                .as("the dead flag skips the victim and the survivor still runs")
                .deepEq({ "killer", "survivor" })
        end)

        it("a subscriber added mid-dispatch is not called in that pass", function()
            local lateCalls, armed = 0, false
            DB:Subscribe(function()
                if armed then
                    armed = false
                    DB:Subscribe(function() lateCalls = lateCalls + 1 end, "spec.late")
                end
            end, "spec.adder")

            armed = true
            DB:RegisterWidget(mkdef("spec.mid_add"))
            -- The one call it did get is Subscribe's own immediate delivery, not the
            -- in-flight snapshot.
            expect(lateCalls).as("immediate delivery only").eq(1)

            DB:RegisterWidget(mkdef("spec.mid_add2"))
            expect(lateCalls).as("and it joins from the next change onward").eq(2)
        end)

        it("a widget registered from inside a subscriber does not lose the dispatch", function()
            local seen, armed = {}, false
            DB:Subscribe(function()
                if armed then
                    armed = false
                    DB:RegisterWidget(mkdef("spec.nested"))
                end
            end, "spec.nester")
            DB:Subscribe(function() seen[#seen + 1] = #DB:List() end, "spec.observer")

            seen, armed = {}, true
            DB:RegisterWidget(mkdef("spec.outer"))

            expect(#seen).as("the observer ran for both the nested and the outer change").eq(2)
            expect(DB:Has("spec.nested")).eq(true)
            expect(DB:Has("spec.outer")).eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. A throwing subscriber
    ---------------------------------------------------------------------------

    describe("a throwing subscriber", function()
        it("does not stop the subscribers after it", function()
            local reached = false
            DB:Subscribe(function() error("spec_kaboom_widgets") end, "spec.thrower")
            DB:Subscribe(function() reached = true end, "spec.after_thrower")

            reached = false
            DB:RegisterWidget(mkdef("spec.throw_trigger"))
            expect(reached).as("the throw was contained").eq(true)
        end)

        it("does not make RegisterWidget raise", function()
            DB:Subscribe(function() error("spec_kaboom2") end, "spec.thrower2")
            expect(function() DB:RegisterWidget(mkdef("spec.throw_trigger2")) end).notThrows()
        end)

        it("does not make UnregisterWidget raise", function()
            DB:RegisterWidget(mkdef("spec.throw_target"))
            DB:Subscribe(function() error("spec_kaboom3") end, "spec.thrower3")
            expect(function() DB:UnregisterWidget("spec.throw_target") end).notThrows()
        end)

        it("logs the error through SuuUI.Debug, naming the owner", function()
            local from = #H.debugLog()
            DB:Subscribe(function() error("spec_kaboom_logged") end, "spec.logged_owner")
            DB:RegisterWidget(mkdef("spec.log_trigger"))

            expect(logHas(from, "spec_kaboom_logged")).as("the error text was logged").truthy()
            expect(logHas(from, "spec.logged_owner")).as("the owner was named").truthy()
        end)

        it("a throwing immediate delivery is contained and logged", function()
            local from = #H.debugLog()
            expect(function()
                DB:Subscribe(function() error("spec_immediate_kaboom") end, "spec.imm_thrower")
            end).as("Subscribe itself survives").notThrows()

            expect(logHas(from, "spec_immediate_kaboom")).truthy()
            expect(logHas(from, "immediate error")).as("named as the immediate path").truthy()
        end)

        it("a subscriber that threw is still subscribed afterwards", function()
            local calls = 0
            DB:Subscribe(function()
                calls = calls + 1
                error("spec_kaboom_repeat")
            end, "spec.repeat_thrower")
            expect(calls).eq(1)

            DB:RegisterWidget(mkdef("spec.repeat_trigger"))
            expect(calls).as("a throw is not a teardown").eq(2)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Replacing an existing id
    ---------------------------------------------------------------------------

    describe("replacing an existing id", function()
        it("logs through SuuUI.Debug rather than raising", function()
            local from = #H.debugLog()
            DB:RegisterWidget(mkdef("spec.dup"))

            expect(function() DB:RegisterWidget(mkdef("spec.dup")) end)
                .as("a plugin re-registering on re-enable must not take the client down")
                .notThrows()

            expect(logHas(from, "replacing existing widget spec.dup"))
                .as("the collision is reported").truthy()
        end)

        it("the later definition wins", function()
            DB:RegisterWidget(mkdef("spec.dup2", { section = "left" }))
            local second = mkdef("spec.dup2", { section = "right" })
            DB:RegisterWidget(second)

            expect(DB:GetWidget("spec.dup2")).eq(second)
            expect(ids(DB:ListSection("right"))).as("re-placed into the new section")
                .contains("spec.dup2")
            -- Asserts THIS widget left its old section, not that the section is globally empty. It
            -- used to assert emptiness, which held only while nothing shipped in `left` -- the micro
            -- menu now owns that section with fourteen entries, which is what it is for.
            local stillLeft = false
            for _, id in ipairs(ids(DB:ListSection("left"))) do
                if id == "spec.dup2" then stillLeft = true end
            end
            expect(stillLeft).as("gone from the old section").falsy()
        end)

        it("does not duplicate the entry in List", function()
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.dup3"))
            DB:RegisterWidget(mkdef("spec.dup3"))
            expect(ids(DB:List())).deepEq({ "spec.dup3" })
        end)

        it("re-registering the SAME table does not log a replacement", function()
            local d = mkdef("spec.same")
            DB:RegisterWidget(d)

            local from = #H.debugLog()
            DB:RegisterWidget(d)
            expect(logHas(from, "replacing existing widget spec.same"))
                .as("re-registering the identical definition is not a collision").falsy()
        end)

        it("re-registering the same table still notifies", function()
            local d = mkdef("spec.same2")
            DB:RegisterWidget(d)

            local calls = 0
            DB:Subscribe(function() calls = calls + 1 end, "spec.same_watch")
            calls = 0
            DB:RegisterWidget(d)
            expect(calls).as("a subscriber cannot know nothing changed").eq(1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 11. Occupied height
    ---------------------------------------------------------------------------

    describe("occupied height", function()
        it("reports what was set", function()
            local h = barHeight()
            DB:SetOccupiedHeight(h)
            expect(DB:GetOccupiedHeight()).eq(h)
        end)

        it("reports 0 once the bar is gone", function()
            startAt(DB, barHeight())
            DB:SetOccupiedHeight(0)
            expect(DB:GetOccupiedHeight()).as("no bar reads as 0, not as an error").eq(0)
        end)

        it("notifies watchers with the new height", function()
            startAt(DB, 0)

            local got = "unset"
            DB:WatchHeight(function(h) got = h end, "spec.height")
            expect(got).as("immediate delivery, from the height we started at").eq(0)

            local h = barHeight()
            DB:SetOccupiedHeight(h)
            expect(got).eq(h)
        end)

        it("does NOT notify when the value is unchanged", function()
            local h = startAt(DB, barHeight())

            local calls = 0
            DB:WatchHeight(function() calls = calls + 1 end, "spec.unchanged")
            expect(calls).as("immediate delivery").eq(1)

            DB:SetOccupiedHeight(h)
            expect(calls).as("nothing moved, so nothing relaid out").eq(1)

            DB:SetOccupiedHeight(tallBarHeight())
            expect(calls).as("but a real change does notify").eq(2)
        end)

        it("clamps a negative height to 0", function()
            startAt(DB, barHeight())
            DB:SetOccupiedHeight(-tallBarHeight())
            expect(DB:GetOccupiedHeight()).eq(0)
        end)

        it("notifies with the clamped 0, not the negative value", function()
            startAt(DB, barHeight())

            local got = "unset"
            DB:WatchHeight(function(h) got = h end, "spec.clamp")
            DB:SetOccupiedHeight(-tallBarHeight())
            expect(got).as("a consumer never sees a negative offset").eq(0)
        end)

        it("clamps a non-number height to 0", function()
            for _, bad in ipairs({ "28", true, {}, function() end }) do
                startAt(DB, barHeight())
                DB:SetOccupiedHeight(bad)
                expect(DB:GetOccupiedHeight())
                    .as(type(bad) .. " clamps to 0").eq(0)
            end
        end)

        it("clamps a nil height to 0", function()
            startAt(DB, barHeight())
            DB:SetOccupiedHeight(nil)
            expect(DB:GetOccupiedHeight()).eq(0)
        end)

        it("a clamp from an already-zero height does not notify", function()
            startAt(DB, 0)

            local calls = 0
            DB:WatchHeight(function() calls = calls + 1 end, "spec.zero_clamp")
            calls = 0

            DB:SetOccupiedHeight(-1)
            DB:SetOccupiedHeight("nonsense")
            DB:SetOccupiedHeight(nil)
            expect(calls).as("every one of those is still 0").eq(0)
        end)
    end)

    describe("WatchHeight / UnwatchHeight", function()
        it("raises when cb is not a function", function()
            expect(function() DB:WatchHeight("nope", "spec.owner") end)
                .throws("cb must be a function")
        end)

        it("raises when owner is missing", function()
            expect(function() DB:WatchHeight(function() end, nil) end)
                .throws("owner must be a non-empty string")
        end)

        it("raises when owner is the empty string", function()
            expect(function() DB:WatchHeight(function() end, "") end)
                .throws("owner must be a non-empty string")
        end)

        it("fires immediately with the current height", function()
            local h = startAt(DB, barHeight())

            local got, calls = "unset", 0
            DB:WatchHeight(function(v) got, calls = v, calls + 1 end, "spec.imm_height")

            expect(calls).as("once").eq(1)
            expect(got).as("the height as it stands, not nil").eq(h)
        end)

        it("fires immediately with 0 when there is no bar", function()
            startAt(DB, 0)
            local got = "unset"
            DB:WatchHeight(function(v) got = v end, "spec.imm_zero")
            expect(got).eq(0)
        end)

        it("fires on every change", function()
            startAt(DB, 0)

            local seen = {}
            DB:WatchHeight(function(v) seen[#seen + 1] = v end, "spec.seq")
            seen = {}

            local a, b = barHeight(), tallBarHeight()
            expect(a).as("the two heights must differ or this proves nothing").neq(b)
            DB:SetOccupiedHeight(a)
            DB:SetOccupiedHeight(b)
            DB:SetOccupiedHeight(0)

            expect(seen).deepEq({ a, b, 0 })
        end)

        it("drops only that owner's watchers", function()
            startAt(DB, 0)

            local a, b = 0, 0
            DB:WatchHeight(function() a = a + 1 end, "spec.h_keep")
            DB:WatchHeight(function() b = b + 1 end, "spec.h_drop")

            DB:UnwatchHeight("spec.h_drop")
            DB:SetOccupiedHeight(barHeight())

            expect(a).as("the surviving owner still fires").eq(2)
            expect(b).as("the dropped owner does not").eq(1)
        end)

        it("returns how many it removed", function()
            DB:WatchHeight(function() end, "spec.h_multi")
            DB:WatchHeight(function() end, "spec.h_multi")
            expect(DB:UnwatchHeight("spec.h_multi")).eq(2)
        end)

        it("returns 0 for an unknown owner", function()
            expect(DB:UnwatchHeight("spec.h_never")).eq(0)
        end)

        it("returns 0 for a non-string owner", function()
            expect(DB:UnwatchHeight(42)).eq(0)
            expect(DB:UnwatchHeight(nil)).eq(0)
        end)

        it("GetHeightWatcherCount returns to its starting value", function()
            local before = DB:GetHeightWatcherCount()
            DB:WatchHeight(function() end, "spec.h_leak")
            DB:WatchHeight(function() end, "spec.h_leak")
            expect(DB:GetHeightWatcherCount()).eq(before + 2)

            DB:UnwatchHeight("spec.h_leak")
            expect(DB:GetHeightWatcherCount()).as("no leak").eq(before)
        end)

        it("a watcher that unwatches ITSELF does not stop the ones after it", function()
            startAt(DB, 0)

            local order, armed = {}, false
            DB:WatchHeight(function() order[#order + 1] = "first" end, "spec.hf")
            DB:WatchHeight(function()
                order[#order + 1] = "middle"
                if armed then DB:UnwatchHeight("spec.hm") end
            end, "spec.hm")
            DB:WatchHeight(function() order[#order + 1] = "third" end, "spec.ht")

            order, armed = {}, true
            DB:SetOccupiedHeight(barHeight())

            expect(order).as("the whole dispatch completed").deepEq({ "first", "middle", "third" })
        end)

        it("the self-unwatched watcher is gone from the next change", function()
            startAt(DB, 0)

            local order, armed = {}, false
            DB:WatchHeight(function() order[#order + 1] = "first" end, "spec.hf")
            DB:WatchHeight(function()
                order[#order + 1] = "middle"
                if armed then DB:UnwatchHeight("spec.hm") end
            end, "spec.hm")
            DB:WatchHeight(function() order[#order + 1] = "third" end, "spec.ht")

            armed = true
            DB:SetOccupiedHeight(barHeight())
            order = {}
            DB:SetOccupiedHeight(tallBarHeight())

            expect(order).as("middle really did unwatch").deepEq({ "first", "third" })
        end)

        it("a throwing watcher does not stop the others and is logged", function()
            startAt(DB, 0)

            local from = #H.debugLog()
            local reached = false
            DB:WatchHeight(function() error("spec_height_kaboom") end, "spec.h_throw")
            DB:WatchHeight(function() reached = true end, "spec.h_after")

            reached = false
            expect(function() DB:SetOccupiedHeight(barHeight()) end).notThrows()
            expect(reached).as("the throw was contained").eq(true)
            expect(logHas(from, "spec_height_kaboom")).truthy()
        end)

        it("height watchers and widget subscribers are independent", function()
            startAt(DB, 0)

            local widgetCalls, heightCalls = 0, 0
            DB:Subscribe(function() widgetCalls = widgetCalls + 1 end, "spec.indep_w")
            DB:WatchHeight(function() heightCalls = heightCalls + 1 end, "spec.indep_h")
            widgetCalls, heightCalls = 0, 0

            DB:RegisterWidget(mkdef("spec.indep"))
            expect(widgetCalls).as("a registration is a widget-set change").eq(1)
            expect(heightCalls).as("and says nothing about the height").eq(0)

            DB:SetOccupiedHeight(barHeight())
            expect(heightCalls).eq(1)
            expect(widgetCalls).as("a height change is not a widget-set change").eq(1)
        end)

        it("Unsubscribe does not touch height watchers sharing the owner name", function()
            startAt(DB, 0)

            local heightCalls = 0
            DB:Subscribe(function() end, "spec.shared_owner")
            DB:WatchHeight(function() heightCalls = heightCalls + 1 end, "spec.shared_owner")

            expect(DB:Unsubscribe("spec.shared_owner")).eq(1)
            heightCalls = 0
            DB:SetOccupiedHeight(barHeight())
            expect(heightCalls).as("the two registries are separate").eq(1)
        end)

        it("UnwatchHeight does not touch widget subscribers sharing the owner name", function()
            local widgetCalls = 0
            DB:WatchHeight(function() end, "spec.shared_owner2")
            DB:Subscribe(function() widgetCalls = widgetCalls + 1 end, "spec.shared_owner2")

            expect(DB:UnwatchHeight("spec.shared_owner2")).eq(1)
            widgetCalls = 0
            DB:RegisterWidget(mkdef("spec.shared_trigger"))
            expect(widgetCalls).eq(1)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 12. Open questions, pinned per TESTING.md
    ---------------------------------------------------------------------------

    describe("open questions", function()
        it("clamps a NaN height to 0 like every other unusable input", function()
            -- NaN IS a number and `NaN < 0` is false, so it walked straight through a guard
            -- whose whole job was to stop exactly this. GetOccupiedHeight is a length every
            -- consumer adds to a y offset, so one NaN poisoned all of them.
            local nan = 0 / 0
            DB:SetOccupiedHeight(nan)
            local got = DB:GetOccupiedHeight()
            expect(got == got).as("not NaN any more").truthy()
            expect(got).as("clamped, not stored").eq(0)
        end)

        it("keeps the unchanged-value guard working after a NaN write", function()
            -- The second half of the same bug: because NaN ~= NaN, a stored NaN made
            -- `occupied == h` false for every later write INCLUDING an identical one, so the
            -- short circuit never fired again and every write relaid out the whole UI.
            local nan = 0 / 0
            DB:SetOccupiedHeight(nan)

            local calls = 0
            DB:WatchHeight(function() calls = calls + 1 end, "spec.nan_watch")
            calls = 0

            DB:SetOccupiedHeight(nan)
            DB:SetOccupiedHeight(nan)
            expect(calls).as("both writes clamp to the value already held, so neither notifies")
                .eq(0)
        end)

        it("cannot be reordered through a definition List handed out", function()
            -- List() copies the array, and the registry now sorts on an ordering SNAPSHOT
            -- taken at registration rather than on the live def -- so mutating a def's order
            -- has no effect until it re-registers. Copying the whole def instead would have
            -- broken GetWidget identity, which the replacement check and every plugin holding
            -- its own table depend on.
            clearWidgets(DB)
            DB:RegisterWidget(mkdef("spec.mut_a", { section = "left", order = 10 }))
            DB:RegisterWidget(mkdef("spec.mut_b", { section = "left", order = 20 }))
            expect(ids(DB:List())).deepEq({ "spec.mut_a", "spec.mut_b" })

            DB:List()[1].order = 999

            expect(ids(DB:List()))
                .as("the snapshot still governs, so nothing moved")
                .deepEq({ "spec.mut_a", "spec.mut_b" })

            -- And it still does not move at the next resort, which is where it used to.
            DB:RegisterWidget(mkdef("spec.mut_c", { section = "right" }))
            expect(ids(DB:List()))
                .as("an unrelated registration no longer reorders the earlier fields")
                .deepEq({ "spec.mut_a", "spec.mut_b", "spec.mut_c" })
        end)

        it("picks up a changed placement when the widget re-registers", function()
            -- The other half of the contract, and the reason the snapshot is not a cage:
            -- re-registering is how a plugin changes its own placement, and it has to take.
            clearWidgets(DB)
            local a = mkdef("spec.re_a", { section = "left", order = 10 })
            DB:RegisterWidget(a)
            DB:RegisterWidget(mkdef("spec.re_b", { section = "left", order = 20 }))
            expect(ids(DB:List())).deepEq({ "spec.re_a", "spec.re_b" })

            a.order = 999
            DB:RegisterWidget(a)
            expect(ids(DB:List()))
                .as("the snapshot is refreshed, so the widget moves")
                .deepEq({ "spec.re_b", "spec.re_a" })
            expect(DB:GetWidget("spec.re_a"))
                .as("and identity survives, which the replacement check relies on").eq(a)
        end)
    end)
end)

---------------------------------------------------------------------------------
-- SuuUI.Pixel.Convert
--
-- It exists for the DataBar boundary: GetOccupiedHeight is a length in the UI root's
-- units, and the frames it moves down (Blizzard's minimap, its buff frame) are anchored
-- to UIParent, which carries a different effective scale once the pixel grid is on.
---------------------------------------------------------------------------------

describe("Core/Pixel.Convert (the DataBar boundary)", function()
    local P

    -- 1080p puts a real, non-1 scale on the UI root: 768 units over 1080 pixels at
    -- multiplier 1. The default 1:1 grid would let a broken Convert pass as identity.
    local function scaled()
        H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
        P = H.SuuUI.Pixel
        return H.env.SuuUI_UIRoot, H.UIParent
    end

    before_each(function()
        H.setup()
        P = H.SuuUI.Pixel
    end)

    describe("the scales it converts between", function()
        it("the root and UIParent really do differ at 1080p", function()
            local root, ui = scaled()
            expect(root:GetEffectiveScale())
                .as("otherwise every ratio test below would pass as identity")
                .neq(ui:GetEffectiveScale())
        end)

        it("the root's scale is the grid rule: multiplier * 768 / physical height", function()
            local root = scaled()
            expect(root:GetEffectiveScale())
                .near(P.multiplier * 768 / H.state.physicalHeight, 1e-6)
        end)
    end)

    describe("identity when both frames share a space", function()
        it("returns the input when from and to are the same frame", function()
            local root = scaled()
            local v = H.token("sizeRow")
            expect(P.Convert(v, root, root)).as("under a real, non-1 scale").eq(v)
        end)

        it("returns the input when two different frames share a scale", function()
            local a = H.parent(100, 100)
            local b = H.parent(100, 100)
            expect(a:GetEffectiveScale()).eq(b:GetEffectiveScale())

            local v = H.lineHeight(H.token("fontSizeMd"))
            expect(P.Convert(v, a, b)).eq(v)
        end)

        it("everything inside the addon shares the root's space, so no conversion is needed",
            function()
                local root = scaled()
                local child = H.env.CreateFrame("Frame", nil, root)
                local v = H.token("sizeRow")
                expect(P.Convert(v, child, root))
                    .as("a frame under the root needs no conversion to talk to it").eq(v)
            end)
    end)

    describe("the ratio when they do not", function()
        it("scales a root length by exactly the effective-scale ratio", function()
            local root, ui = scaled()
            local v = H.token("sizeRow")
            local ratio = root:GetEffectiveScale() / ui:GetEffectiveScale()

            expect(P.Convert(v, root, ui)).near(v * ratio, 1e-9)
            expect(P.Convert(v, root, ui)).as("and it is genuinely a shrink").lt(v)
        end)

        it("converts the DataBar's occupied height into UIParent's units", function()
            local root, ui = scaled()
            local h = barHeight()
            H.SuuUI.DataBar:SetOccupiedHeight(h)

            local ours = H.SuuUI.DataBar:GetOccupiedHeight()
            expect(ours).eq(h)

            local theirs = P.Convert(ours, root, ui)
            expect(theirs).near(h * root:GetEffectiveScale() / ui:GetEffectiveScale(), 1e-9)
            expect(theirs).as("handing the raw number over would be wrong by the ratio").neq(ours)
        end)

        it("goes the other way by the reciprocal", function()
            local root, ui = scaled()
            local v = H.token("sizeRow")
            local ratio = ui:GetEffectiveScale() / root:GetEffectiveScale()

            expect(P.Convert(v, ui, root)).near(v * ratio, 1e-9)
            expect(P.Convert(v, ui, root)).as("and it is a growth this way").gt(v)
        end)

        it("round-trips", function()
            local root, ui = scaled()
            local v = H.token("sizeRow")
            expect(P.Convert(P.Convert(v, root, ui), ui, root)).near(v, 1e-9)
        end)

        it("is linear, so it can be applied to any length", function()
            local root, ui = scaled()
            local a = H.token("sizeRow")
            local b = H.token("spaceLg")
            expect(P.Convert(a + b, root, ui))
                .near(P.Convert(a, root, ui) + P.Convert(b, root, ui), 1e-9)
        end)

        it("preserves a negative length's sign", function()
            local root, ui = scaled()
            local v = H.token("sizeRow")
            expect(P.Convert(-v, root, ui)).near(-P.Convert(v, root, ui), 1e-9)
        end)
    end)

    describe("edge cases", function()
        it("returns 0 for 0", function()
            local root, ui = scaled()
            expect(P.Convert(0, root, ui)).eq(0)
        end)

        it("returns 0 for nil", function()
            local root, ui = scaled()
            expect(P.Convert(nil, root, ui)).as("no bar, no offset").eq(0)
        end)

        it("a nil `from` degrades to scale 1 rather than erroring", function()
            local _, ui = scaled()
            local v = H.token("sizeRow")
            expect(function() P.Convert(v, nil, ui) end).notThrows()
            expect(P.Convert(v, nil, ui)).near(v / ui:GetEffectiveScale(), 1e-9)
        end)

        it("a nil `to` degrades to scale 1 rather than erroring", function()
            local root = scaled()
            local v = H.token("sizeRow")
            expect(function() P.Convert(v, root, nil) end).notThrows()
            expect(P.Convert(v, root, nil)).near(v * root:GetEffectiveScale(), 1e-9)
        end)

        it("two nil frames are identity", function()
            scaled()
            local v = H.token("sizeRow")
            expect(P.Convert(v, nil, nil)).eq(v)
        end)

        it("a frame with no GetEffectiveScale degrades to 1 rather than erroring", function()
            local root = scaled()
            local notAFrame = {}
            expect(function() P.Convert(H.token("sizeRow"), root, notAFrame) end).notThrows()
            expect(P.Convert(H.token("sizeRow"), root, notAFrame))
                .near(H.token("sizeRow") * root:GetEffectiveScale(), 1e-9)
        end)

        it("a frame reporting a zero scale degrades to 1 rather than dividing by it", function()
            local root = scaled()
            local zeroScaled = { GetEffectiveScale = function() return 0 end }
            local v = H.token("sizeRow")

            local out = P.Convert(v, root, zeroScaled)
            expect(out).as("finite, not inf").near(v * root:GetEffectiveScale(), 1e-9)
            expect(out == out).as("and not NaN").truthy()
        end)

        it("a frame reporting a non-number scale degrades to 1", function()
            local root = scaled()
            local junk = { GetEffectiveScale = function() return "1.5" end }
            local v = H.token("sizeRow")
            expect(P.Convert(v, root, junk)).near(v * root:GetEffectiveScale(), 1e-9)
        end)
    end)
end)
