local H = require("harness")

-- The addon-button collector: what it picks up off the minimap ring, what it refuses, and that
-- it gives everything back.
--
-- The first block is the important one. It pins the defect that FROZE THE CLIENT on the first
-- mouseover, and the mechanism is worth stating because nothing about it is visible in the
-- code: every adopted button gets a permanent SetPoint hook so an addon re-anchoring its own
-- button cannot tear it out of the roster -- but rebuilding the roster ALSO re-anchors that
-- button, so the hook fires, the notification rebuilds, the rebuild re-anchors, and round it
-- goes. Measured here before the fix: one external move produced 196 nested notifications
-- before Lua's stack gave out. In the client there is no stack to give out; it simply stops
-- responding.
--
-- The `applying` flag cannot cover this and should not have to: it is raised only while the
-- collector itself is collecting or restoring, whereas the rebuild happens in the panel.
--
-- The collector and the tray are BUILT-INS of the data bar rather than a plugin of their own,
-- so there is no `addon_buttons` plugin to enable or disable: the settings live under
-- `data_bar`, the collector's events ride the bar's event frame, and Watch/Unwatch/Restore are
-- driven from the bar's own onEnable/onDisable. That is why the ring is handed back by
-- switching the DATA BAR off, and why the tray's `tray_enabled` toggle is a separate question.

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.addon_buttons"

local function C() return H.SuuUI._DataBar.ButtonCollector end
local function root() return H.SuuUI.UIRoot:GetRootContainer():GetFrame() end
local function ring() return H.env.Minimap or root() end

local function button(name, parent)
    local f = H.env.CreateFrame("Button", name, parent or ring())
    f:SetSize(31, 31)
    return f
end

describe("Plugins.DataBar – the addon-button collector", function()
    before_each(function()
        H.setup()
    end)

    -----------------------------------------------------------------------------
    describe("the notification cascade", function()
        it("notifies once for one external move, not once per re-anchor", function()
            local btn = button("ProbeAddonMinimapButton")
            C().Collect()
            expect(C().IsManaged(btn)).as("the button was adopted").eq(true)

            local calls = 0
            C().SetChangeCallback(function()
                calls = calls + 1
                -- Exactly what rebuilding the roster does: re-place the adopted button.
                btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 0, 0)
            end)

            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 1, 1)
            expect(calls).as("one external move means one rebuild, not a cascade").eq(1)

            C().SetChangeCallback(nil)
            C().Restore()
        end)

        it("still notifies on the NEXT move, so the guard is not a latch", function()
            local btn = button("ProbeTwoMinimapButton")
            C().Collect()

            local calls = 0
            C().SetChangeCallback(function() calls = calls + 1 end)
            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 1, 1)
            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 2, 2)
            expect(calls).as("the guard clears when the notification returns").eq(2)

            C().SetChangeCallback(nil)
            C().Restore()
        end)

        it("survives a throwing callback without leaving the guard raised", function()
            local btn = button("ProbeThreeMinimapButton")
            C().Collect()

            C().SetChangeCallback(function() error("boom") end)
            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 1, 1)

            -- The hook runs from inside somebody else's SetPoint, so the error is contained.
            -- What matters here is that the flag came back down.
            local calls = 0
            C().SetChangeCallback(function() calls = calls + 1 end)
            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 2, 2)
            expect(calls).as("a throwing callback did not latch the guard").eq(1)

            C().SetChangeCallback(nil)
            C().Restore()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("what it picks up", function()
        it("adopts a frame whose name looks like an addon's minimap button", function()
            local btn = button("SomeAddonMinimapButton")
            C().Collect()
            expect(C().IsManaged(btn)).eq(true)
            C().Restore()
        end)

        it("counts it, and reports it with a cleaned-up display name", function()
            button("GathererMinimapButton")
            C().Collect()
            local entries = C().GetEntries()
            local found
            for _, e in ipairs(entries) do
                if e.key == "GathererMinimapButton" then found = e end
            end
            expect(found).as("the button is in the roster").notNil()
            expect(found.label).as("the boilerplate that identified it comes back off")
                .eq("Gatherer")
            C().Restore()
        end)

        it("refuses a map pin, which is a minimap child that looks just like a button",
        function()
            -- Without this the roster fills with the hundreds of nodes Questie and HandyNotes
            -- park on the ring, and the real buttons are lost among them.
            local pin = button("QuestieMinimapFrame")
            C().Collect()
            expect(C().IsManaged(pin)).as("a pin is not a button").eq(false)
            C().Restore()
        end)

        it("refuses a generated name ending in a digit", function()
            local pin = button("SomeAddonMinimapIcon12")
            C().Collect()
            expect(C().IsManaged(pin)).as("a trailing number is a generated pin").eq(false)
            C().Restore()
        end)

        it("ignores a frame that is not on the ring at all", function()
            local stray = button("StrayMinimapButton", root())
            C().Collect()
            expect(C().IsManaged(stray)).eq(false)
            C().Restore()
        end)

        it("leaves out a button its owner has hidden", function()
            local btn = button("HiddenAddonMinimapButton")
            C().Collect()
            local before = C().Count()
            btn:Hide()
            expect(C().Count())
                .as("a named row with nothing in it reads as a broken icon").eq(before - 1)
            C().Restore()
        end)

        it("is idempotent: collecting twice adopts nothing twice", function()
            button("RepeatAddonMinimapButton")
            C().Collect()
            local first = C().Count()
            C().Collect()
            expect(C().Count()).as("already-held buttons are skipped").eq(first)
            C().Restore()
        end)

        it("orders the roster totally, so it cannot shuffle between logins", function()
            button("ZebraMinimapButton")
            button("AlphaMinimapButton")
            C().Collect()
            local entries = C().GetEntries()
            local names = {}
            for _, e in ipairs(entries) do names[#names + 1] = e.label end
            -- Sorted by label, and by key when labels tie, so the order never depends on the
            -- client's child order.
            for i = 2, #names do
                expect(names[i - 1] <= names[i]).as("sorted by name").eq(true)
            end
            C().Restore()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("leaving the ring", function()
        it("reparents off the minimap at collect time, not on first hover", function()
            local btn = button("EagerAddonMinimapButton")
            expect(btn:GetParent()).as("starts on the ring").eq(ring())

            C().Collect()
            -- The panel is what puts a button into a row, and the panel is only built on the
            -- first hover -- so with nowhere else to park a collected button it stayed visible
            -- on the ring until the player hovered the field. That is what shipped.
            expect(btn:GetParent() ~= ring())
                .as("off the ring as soon as it is collected").eq(true)

            C().Restore()
            expect(btn:GetParent()).as("and back on it after a restore").eq(ring())
        end)

        it("parks it somewhere that is not drawn", function()
            local btn = button("ParkedAddonMinimapButton")
            C().Collect()
            expect(btn:GetParent():IsShown())
                .as("the holding frame is hidden, so a parked button draws nowhere").eq(false)
            C().Restore()
        end)

        it("puts the strata pin back exactly as it was found", function()
            local btn = button("PinnedAddonMinimapButton")
            btn:SetFrameStrata("MEDIUM")
            btn:SetFrameLevel(8)
            btn:SetFixedFrameStrata(true)
            btn:SetFixedFrameLevel(true)

            C().Collect()
            C().Restore()

            expect(btn:GetFrameStrata()).as("original strata").eq("MEDIUM")
            expect(btn:GetFrameLevel()).as("original level").eq(8)
            expect(btn:IsFixedFrameStrata()).as("and the pin is re-applied").eq(true)
            expect(btn:IsFixedFrameLevel()).eq(true)
        end)

        it("reports the icon column from the size found on the ring", function()
            button("SizedAddonMinimapButton")
            C().Collect()
            local _, maxSize = C().GetEntries()
            expect(maxSize).as("the button's own 31px size, not a shrunken one").eq(31)
            C().Restore()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("giving them back", function()
        it("restores the original parent and anchor", function()
            local btn = button("RestoreMeMinimapButton")
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", ring(), "CENTER", 7, -3)
            local parentBefore = btn:GetParent()

            C().Collect()
            expect(C().IsManaged(btn)).eq(true)
            -- Something else takes it over, as the panel does.
            btn:SetParent(root())

            C().Restore()
            expect(C().IsManaged(btn)).as("no longer held").eq(false)
            expect(btn:GetParent()).as("back on the ring").eq(parentBefore)
            local point, _, relPoint, x, y = btn:GetPoint(1)
            expect(point).eq("CENTER")
            expect(relPoint).eq("CENTER")
            expect(x).eq(7)
            expect(y).eq(-3)
        end)

        it("empties the roster", function()
            button("GoneMinimapButton")
            C().Collect()
            expect(C().Count()).gte(1)
            C().Restore()
            expect(C().Count()).as("nothing is held after a restore").eq(0)
        end)

        it("stops notifying once a button has been handed back", function()
            local btn = button("QuietMinimapButton")
            C().Collect()
            C().Restore()

            local calls = 0
            C().SetChangeCallback(function() calls = calls + 1 end)
            btn:SetPoint("TOPLEFT", root(), "TOPLEFT", 4, 4)
            -- The hook is permanent and cannot be uninstalled, which is exactly why it asks
            -- `managed` on every call instead of assuming it should always act.
            expect(calls).as("a released button's hook is inert").eq(0)
            C().SetChangeCallback(nil)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the data bar field", function()
        it("registers into the right section with the ADDONS prefix", function()
            local def = H.SuuUI.DataBar:GetWidget(WIDGET_ID)
            expect(def).as("the tray widget is registered").notNil()
            expect(def.prefix).eq("ADDONS")
            expect(def.section).eq("right")
        end)

        it("refreshes on ADDON_LOADED and polls for what no game event announces", function()
            local def = H.SuuUI.DataBar:GetWidget(WIDGET_ID)
            -- ADDON_LOADED is the one game event that coincides with a button appearing. The
            -- other half arrives on LibDBIcon's own callback, which the bar cannot subscribe
            -- to, so a short poll covers it.
            local seen = {}
            for _, e in ipairs(def.events or {}) do seen[e] = true end
            expect(seen["ADDON_LOADED"]).as("re-reads when an addon finishes loading").eq(true)
            expect(def.update).as("and polls for the library callback").eq(1)
        end)

        it("adopts a button the instant LibDBIcon creates it, with no sweep", function()
            -- The lateness bug. LibDBIcon gates createButton on lib.loggedIn and queues
            -- anything registered earlier in lib.notCreated, so the login sweep finds nothing
            -- and the field read 0 until something else happened to sweep again.
            local lib = H.env.LibStub and H.env.LibStub("LibDBIcon-1.0", true)
            expect(lib).as("the embedded library is loaded").notNil()

            -- Deliberately NOT parented to the ring, so this can only be the callback path.
            local btn = button("LateAddonMinimapButton", root())
            lib.callbacks:Fire("LibDBIcon_IconCreated", btn, "LateAddon")

            expect(C().IsManaged(btn))
                .as("adopted without any call to Collect").eq(true)

            local entries = C().GetEntries()
            local found
            for _, e in ipairs(entries) do
                if e.frame == btn then found = e end
            end
            expect(found).notNil()
            expect(found.label).as("named from the library's registration").eq("LateAddon")
            C().Restore()
        end)

        it("reads as the number of buttons held", function()
            button("CountedMinimapButton")
            C().Collect()
            local def = H.SuuUI.DataBar:GetWidget(WIDGET_ID)
            local text = def.GetText()
            expect(text).eq(tostring(C().Count()))
            C().Restore()
        end)

        it("collects SuuUI's own launcher too, so nothing is left on the ring", function()
            -- Asked for explicitly: the ring empties completely, our own button included. It
            -- arrives through the LibDBIcon callback like any other, so no special case exists
            -- for it -- which is also why 48_minimap_button_spec.lua has to switch the tray
            -- off (data_bar / tray_enabled) to assert the launcher's own ring behaviour.
            local own = H.SuuUI._MinimapButton and H.SuuUI._MinimapButton.GetButton()
            expect(own).as("the launcher's button exists after login").notNil()
            expect(C().IsManaged(own)).as("and the tray has taken it").eq(true)
        end)

        it("goes away with its own toggle", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", false)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(false)
            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", true)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(true)
        end)

        it("hands the ring back when the field is switched off", function()
            -- This was shipped broken and is the resolution of the xit that pinned it:
            -- `tray_enabled` governs COLLECTION, not just the field. A player who turns "Show
            -- Addon Buttons" off has asked for the buttons not to be in the bar; what they got
            -- was buttons in no bar AND off the minimap, which reads as icons that vanished.
            --
            -- Resolved by giving the toggle's own watcher the whole job -- register plus Watch
            -- and Collect on the way on, unregister plus Unwatch and Restore on the way off --
            -- and by gating the bar's event-driven Collect on the FIELD being registered rather
            -- than on a second read of the setting. The field's presence IS the fact, so the
            -- two cannot drift apart.
            local btn = button("FieldOnlyMinimapButton")
            C().Collect()
            expect(C().IsManaged(btn)).as("collected while the field is on").eq(true)

            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", false)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).as("the field is gone").eq(false)
            expect(C().IsManaged(btn)).as("and the button is no longer held").eq(false)
            expect(btn:GetParent()).as("back on the ring, not stranded").eq(ring())

            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", true)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).as("the field returns").eq(true)
            expect(C().IsManaged(btn))
                .as("and switching it on picks the ring up again rather than waiting for a "
                    .. "sweep").eq(true)

            C().Restore()
        end)

        it("does not collect while the field is switched off", function()
            -- The mirror-image bug the gate exists to prevent, and the reason the fix is not
            -- just "restore on the off-branch": with the tray off, an event that would normally
            -- sweep must not quietly take buttons off the ring for a tray that is not showing.
            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", false)
            local btn = button("LateWhileOffMinimapButton")
            H.fireEvent("ADDON_LOADED", "SomeAddon")
            expect(C().IsManaged(btn))
                .as("nothing is collected while the tray is off").eq(false)
            expect(btn:GetParent()).as("still on the ring").eq(ring())

            H.SuuUI.Settings:Set(PLUGIN_ID, "tray_enabled", true)
            C().Restore()
        end)

        it("hands the ring back when the data bar is disabled", function()
            -- There is no addon_buttons plugin to switch off any more: the bar's onDisable is
            -- what calls Collector.Restore(), so this is the path that genuinely undoes the
            -- collection. Not merely a route to a reload -- a Disable from a settings watcher
            -- runs with nothing behind it, and a button left parented into a destroyed panel
            -- is invisible for the rest of the session.
            local btn = button("DisableMeMinimapButton")
            C().Collect()
            expect(C().IsManaged(btn)).eq(true)

            H.SuuUI.Settings:Set(PLUGIN_ID, "enabled", false)
            expect(H.SuuUI.Plugins:Get(PLUGIN_ID):IsEnabled())
                .as("the watcher carried the setting into a real disable").eq(false)
            expect(C().IsManaged(btn))
                .as("disabling the bar restores the buttons").eq(false)
            expect(btn:GetParent()).as("and the ring has it back").eq(ring())
            expect(C().Count()).as("the roster is empty").eq(0)

            H.SuuUI.Settings:Set(PLUGIN_ID, "enabled", true)
        end)
    end)
end)
