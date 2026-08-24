-- Plugins/DataBar/BagsWidget.lua
--
-- Blizzard's six-button bag row, replaced by one data bar field reading "BAGS 27".
--
-- The assertions that matter are the TWO API SHAPES and the SPECIALISED BAG exclusion. The first is the
-- trap the reputation bar fell into on this same client -- a modern backend moved the container calls
-- onto C_Container and may not carry the bare globals. The second is a TBC fact with teeth: a quiver's
-- free slots cannot hold loot, so counting them tells a hunter they have room when they have none.

local H = require("harness")

describe("DataBar.BagsWidget", function()
    local PLUGIN = "data_bar"
    local B, S

    -- A backpack and one bag, plus a quiver that must not be counted.
    local BAGS = {
        [0] = { free = 4, slots = 16 },
        [1] = { free = 8, slots = 16 },
        [2] = { free = 0, slots = 20, bagType = 2 },
    }

    before_each(function()
        H.setup()
        B = H.SuuUI._BagBar
        S = H.SuuUI.Settings
    end)

    describe("registration", function()
        it("registers one field in the bar's right section", function()
            expect(H.SuuUI.DataBar:Has("databar.bags")).truthy()
            local def = H.SuuUI.DataBar:GetWidget("databar.bags")
            expect(def.section).eq("right")
            expect(def.prefix).as("the reading needs saying what it is").eq("BAGS")
        end)

        it("sits ahead of the diagnostics in that section", function()
            -- The right section already holds addon buttons (190), latency (200) and fps (210). Bags is
            -- a gameplay reading rather than a diagnostic, so it takes the inner edge and leaves the
            -- far right to the numbers a player only glances at when something feels wrong.
            local ordered = {}
            for _, def in ipairs(H.SuuUI.DataBar:ListSection("right")) do
                ordered[#ordered + 1] = def.id
            end
            expect(ordered[1]).as("first in the section").eq("databar.bags")
        end)

        it("refreshes on the DELAYED bag event, not the per-container one", function()
            -- BAG_UPDATE fires once PER CONTAINER, so one loot would rebuild the string five times.
            local def = H.SuuUI.DataBar:GetWidget("databar.bags")
            local events = {}
            for _, e in ipairs(def.events) do events[e] = true end
            expect(events["BAG_UPDATE_DELAYED"]).truthy()
            expect(events["BAG_UPDATE"]).as("the chatty one is not used").falsy()
            -- Nothing else announces the bags a character logs in with.
            expect(events["PLAYER_ENTERING_WORLD"]).truthy()
        end)

        it("drops its field when the toggle goes off, and RESTORES it when it comes back", function()
            -- THE WIRING BUG, AND THE REASON THIS IS A WIDGET. As its own `bag_bar` plugin, the field
            -- registered its enable watcher under its owner prefix and then called UnwatchPrefix on that
            -- same prefix from onDisable -- destroying the watcher that would switch it back on. Off
            -- worked; on never did. A one-way toggle looks like the setting is ignored.
            --
            -- A built-in widget cannot make that mistake: the data bar re-runs Enable, so the watcher is
            -- rebuilt. The round trip is asserted rather than just the "off" half, because the off half
            -- passed the whole time.
            S:Set(PLUGIN, "bags_enabled", false)
            expect(H.SuuUI.DataBar:Has("databar.bags")).as("gone").falsy()
            S:Set(PLUGIN, "bags_enabled", true)
            expect(H.SuuUI.DataBar:Has("databar.bags")).as("and back").truthy()
        end)

        it("puts its settings on the DATA BAR's page, not a page of its own", function()
            -- Every other field's settings live here. A separate plugin put these on a separate page,
            -- which is where the player would not think to look for a data bar field.
            local keys = {}
            local function scan(entries)
                for _, e in ipairs(entries or {}) do
                    if type(e.key) == "string" then keys[e.key] = true end
                    if e.type == "subtabs" then
                        for _, tab in ipairs(e.tabs or {}) do scan(tab.schema) end
                    end
                end
            end
            scan(H.SuuUI.Settings:GetSchema("data_bar"))
            for _, k in ipairs({ "bags_enabled", "bags_show_total", "bags_warn_at", "bags_danger_at" }) do
                expect(keys[k]).as(k .. " is on the data bar page").truthy()
            end
        end)

        it("is not a plugin of its own any more", function()
            expect(H.SuuUI.Plugins:Get("bag_bar")).as("no stray bag_bar plugin").isNil()
        end)
    end)

    describe("reading the bags", function()
        it("sums free and total across the backpack and bag slots", function()
            H.setBags(BAGS)
            local free, total = B.readBags()
            expect(free).eq(12)
            expect(total).eq(32)
        end)

        it("EXCLUDES a specialised bag, whose free slots cannot hold loot", function()
            -- The quiver in BAGS has 20 slots. Counted, the total would be 52 -- and a hunter with an
            -- empty quiver would be told they have room for twenty more items. bagType 0 (or absent)
            -- means general-purpose, which is the same test ElvUI applies.
            H.setBags(BAGS)
            local _, total = B.readBags()
            expect(total).as("the quiver's 20 slots are not counted").eq(32)

            H.setBags({ [0] = { free = 1, slots = 16 }, [1] = { free = 30, slots = 30, bagType = 4 } })
            expect(select(1, B.readBags())).as("nor its free slots").eq(1)
        end)

        it("reads the MODERN C_Container API when that is what the client has", function()
            -- The reputation bug in one line: this client may carry only the namespaced form. ElvUI
            -- dereferences C_Container.GetContainerNumFreeSlots at file scope with no nil guard and
            -- works here, so the namespace is present.
            H.setBagApi("modern")
            H.setBags(BAGS)
            local free, total = B.readBags()
            expect(free).eq(12)
            expect(total).eq(32)
        end)

        it("reads the LEGACY globals when those are what the client has", function()
            H.setBagApi("legacy")
            H.setBags(BAGS)
            expect(select(1, B.readBags())).eq(12)
        end)

        it("FAULTS when neither API exists, instead of reading as an empty inventory", function()
            -- A blank field and a full inventory are the same pixels. Silence here would look like a
            -- character with no free slots, which is the worst possible misreading.
            H.setBagApi("none")
            H.setBags(BAGS)
            expect(B.readBags()).isNil()
            local text = B.GetText()
            expect(text).as("nothing invented").eq("")
            local found = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("container API", 1, true) then found = true end
            end
            expect(found).as("and it said so").truthy()
        end)
    end)

    describe("what the field says", function()
        it("shows the free count alone by default", function()
            H.setBags(BAGS)
            expect(B.GetText()).eq("12")
        end)

        it("shows free over total when asked", function()
            H.setBags(BAGS)
            S:Set(PLUGIN, "bags_show_total", true)
            expect(B.GetText()).eq("12 / 32")
        end)
    end)

    describe("tone thresholds", function()
        -- Tones, not colours: the widget says what the reading MEANS and the theme decides how that
        -- looks, so a retint cannot leave this field the wrong hue.
        it("is untoned with room to spare", function()
            H.setBags({ [0] = { free = 20, slots = 20 } })
            expect(select(2, B.GetText())).isNil()
        end)

        it("warns at the warning threshold", function()
            H.setBags({ [0] = { free = 5, slots = 20 } })
            expect(select(2, B.GetText())).eq("warning")
        end)

        it("goes danger when full", function()
            H.setBags({ [0] = { free = 0, slots = 20 } })
            expect(select(2, B.GetText())).eq("danger")
        end)

        it("measures FREE SLOTS, not a percentage", function()
            -- Four slots left is the same problem with one bag or five, while a percentage would call a
            -- nearly-full 100-slot inventory perfectly fine.
            H.setBags({ [0] = { free = 4, slots = 100 } })
            expect(select(2, B.GetText())).as("4 of 100 still warns").eq("warning")
        end)

        it("NOTIFIES THE RENDERER when a threshold changes", function()
            -- The tone tests above call GetText directly, which re-reads the settings every time -- so
            -- they pass whether or not anything tells the bar to repaint. Mutation testing caught that:
            -- deleting the threshold watchers left them all green.
            --
            -- No bag event fires when a slider moves, so without this the field keeps its old tone until
            -- the player next picks something up. Observed through the registry's own subscription,
            -- which is what the renderer uses.
            H.setBags({ [0] = { free = 10, slots = 40 } })
            local notifies = 0
            H.SuuUI.DataBar:Subscribe(function() notifies = notifies + 1 end, "spec.bags.repaint")
            S:Set(PLUGIN, "bags_warn_at", 12)
            expect(notifies > 0).as("the bar was told to re-read").truthy()

            notifies = 0
            S:Set(PLUGIN, "bags_show_total", true)
            expect(notifies > 0).as("and again for the display change").truthy()
            H.SuuUI.DataBar:Unsubscribe("spec.bags.repaint")
        end)

        it("honours the player's own thresholds", function()
            H.setBags({ [0] = { free = 10, slots = 40 } })
            expect(select(2, B.GetText())).as("fine by default").isNil()
            S:Set(PLUGIN, "bags_warn_at", 12)
            expect(select(2, B.GetText())).as("warns once the bar is raised").eq("warning")
        end)

        it("REFUSES a danger threshold above the warning one", function()
            -- Otherwise the warning band vanishes and the field jumps from fine straight to danger,
            -- which is a state the player cannot configure their way out of by accident.
            S:Set(PLUGIN, "bags_warn_at", 5)
            S:Set(PLUGIN, "bags_danger_at", 10)
            expect(S:Get(PLUGIN, "bags_danger_at")).as("never stored").eq(0)
        end)
    end)

    describe("clicking", function()
        it("opens the bags through the client's own toggle", function()
            H.setBags(BAGS)
            B.OnClick(nil, "LeftButton")
            local toggles = H.getPanelToggles()
            expect(#toggles > 0).as("something was called").truthy()
            expect(toggles[#toggles].name).eq("ToggleAllBags")
        end)
    end)

    describe("suppression", function()
        it("targets BagsBar, NOT its ancestor MicroButtonAndBagsBar", function()
            -- Established by walking the parent chain from MainMenuBarBackpackButton, which answered
            -- "BagsBar". Hiding the ancestor would cascade to everything beneath it -- the same shape as
            -- MainActionBar versus MainMenuBar, which cost a round in Phase 4b.
            local names = {}
            for _, g in ipairs(H.SuuUI._ActionBars.Suppress.TARGETS) do
                if g.id == "bags" then
                    for _, n in ipairs(g.names) do names[n] = true end
                end
            end
            expect(names["BagsBar"]).as("the frame that holds the buttons").truthy()
            expect(names["KeyRingButton"]).truthy()
            expect(names["MicroButtonAndBagsBar"]).as("the ancestor is left alone").falsy()
        end)
    end)
end)
