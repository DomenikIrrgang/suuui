-- Plugins/Inventory/Suppress: Blizzard's bag containers off the screen, and the B key routed to ours.
--
-- The assertions that earn their place here are the WITNESS CELLS and the ROUND TRIP. Hiding a
-- container is the means; a bag slot being off the screen is the end, and the action bar work already
-- shipped a version where every other signal reported success while twelve buttons sat in plain view.
-- And a plugin that cannot hand the default UI back is not finished, so Restore is tested as hard as
-- Apply.
local H = require("harness.init")

describe("Plugins/Inventory suppression", function()
    local S

    before_each(function()
        H.setup()
        S = H.SuuUI._Inventory.Suppress
        -- THE PLUGIN ALREADY APPLIED SUPPRESSION. Its onEnable watches `suppress_blizzard` with
        -- immediate = true and the default is on, so by the time a test runs, every container is
        -- hidden and every global is routed. That is the correct production behaviour -- it is
        -- asserted on its own below -- but it means a test measuring Apply or Restore has to start
        -- from a KNOWN baseline, or it captures our own replacement as "the client's original".
        -- Three tests failed exactly that way before this line existed.
        S.Restore()
        S.SetHandler(nil)
    end)

    after_each(function()
        -- Every test leaves the client as it found it: these are GLOBALS, and a leaked replacement
        -- would make the next spec file's bag calls land on a handler that no longer exists.
        if S then
            S.Restore()
            S.SetHandler(nil)
        end
    end)

    -- END TO END, through the plugin rather than the module. This is what makes the feature real: the
    -- module being correct proves nothing if nobody calls it. Note these deliberately do NOT reset the
    -- baseline first -- they measure the state the plugin's own enable pass left behind.
    describe("the plugin drives it", function()
        it("has already suppressed by the time login finishes", function()
            H.setup()
            local S2 = H.SuuUI._Inventory.Suppress
            expect(S2.IsSuppressed("ContainerFrame1"))
                .as("enable applied suppression with no further call").truthy()
            expect(S2.IsRouted("ToggleBackpack")).as("and routed the B key").truthy()
            expect(#S2.Verify()).as("no bag cell on screen").eq(0)
        end)

        -- THE PLUGIN'S OWN HANDLER, not one a spec installed. Every other routing test sets its own
        -- fake handler, which overrides the plugin's -- so replacing the plugin's Toggle with a no-op
        -- changed nothing anywhere and mutation testing caught it. This drives the real chain: the
        -- client's global -> the plugin's handler -> the window on screen.
        --
        -- Read through the window's GLOBAL FRAME NAME rather than a new accessor: the window is created
        -- with id "inventory_bags", and Layout/Window names its frame from that, so the name is already
        -- part of the addon's surface.
        it("actually opens the window when the client's toggle is called", function()
            H.setup()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1 })
            H.env.ToggleAllBags()
            local frame = H.env.SuuUI_win_inventory_bags
            expect(frame).as("the plugin's handler built the window").truthy()
            expect(frame:IsShown()).as("and put it on screen").truthy()
        end)

        it("closes it again on the client's close", function()
            H.setup()
            H.env.ToggleAllBags()
            expect(H.env.SuuUI_win_inventory_bags:IsShown()).truthy()
            H.env.CloseAllBags()
            -- Window:Hide is a FADE-OUT, so the frame is still shown mid-animation. Asserting straight
            -- after the call reads the fade's first frame and fails for a reason that has nothing to do
            -- with routing.
            H.runAnimations()
            expect(H.env.SuuUI_win_inventory_bags:IsShown()).as("close routes too").falsy()
        end)

        it("hands Blizzard's bags back when the setting is switched off", function()
            H.setup()
            local S2 = H.SuuUI._Inventory.Suppress
            H.SuuUI.Settings:Set("inventory", "suppress_blizzard", false)
            expect(S2.IsSuppressed("ContainerFrame1")).as("no longer claimed").falsy()
            expect(H.env.ContainerFrame1:IsShown()).as("and back on screen").truthy()
            expect(S2.IsRouted("ToggleBackpack")).as("B key handed back too").falsy()
        end)

        it("takes them again when it is switched back on", function()
            H.setup()
            local S2 = H.SuuUI._Inventory.Suppress
            H.SuuUI.Settings:Set("inventory", "suppress_blizzard", false)
            H.SuuUI.Settings:Set("inventory", "suppress_blizzard", true)
            expect(S2.IsSuppressed("ContainerFrame1")).truthy()
            expect(#S2.Verify()).eq(0)
        end)

        -- A plugin that cannot hand the default UI back is not finished, and onDisable runs with
        -- nothing behind it for a settings-driven disable as well as a reload.
        it("restores everything when the plugin is disabled", function()
            H.setup()
            local S2 = H.SuuUI._Inventory.Suppress
            H.SuuUI.Settings:Set("inventory", "enabled", false)
            expect(S2.IsSuppressed("ContainerFrame1")).as("containers handed back").falsy()
            expect(S2.IsRouted("ToggleAllBags")).as("globals handed back").falsy()
        end)
    end)

    describe("hiding the containers", function()
        it("hides every container frame that exists", function()
            H.env.ContainerFrame1:Show()
            S.Apply()
            expect(H.env.ContainerFrame1:IsShown()).as("backpack container is gone").falsy()
            expect(S.IsSuppressed("ContainerFrame1")).truthy()
            expect(S.IsSuppressed("BankFrame")).as("the bank goes too").truthy()
        end)

        -- THE ASSERTION THAT MATTERS. A container renamed out from under the list leaves these
        -- visible while IsSuppressed happily reports success.
        it("leaves NO witness cell on screen", function()
            H.env.OpenAllBags()
            S.Apply()
            local visible = S.Verify()
            expect(#visible)
                .as("bag cells still drawing: " .. table.concat(visible, ", ")).eq(0)
        end)

        -- THE POSITIVE CONTROL, and without it the test above is vacuous: an EMPTY witness list makes
        -- Verify() return nothing and every "#visible == 0" assertion pass trivially. Mutation testing
        -- caught exactly that. So prove Verify can SEE a cell before trusting it to report none.
        it("Verify detects a visible cell when nothing is suppressed", function()
            expect(#S.WITNESS_CELLS).as("there is something to witness with").gt(0)
            H.env.OpenAllBags()
            local visible = S.Verify()
            expect(#visible).as("an unsuppressed bag cell is reported").gt(0)
        end)

        it("re-hides a container that shows itself again", function()
            S.Apply()
            -- Blizzard's own code shows these on plenty of occasions -- looting, a vendor opening.
            -- Hide() alone does not survive that, which is why the hook exists.
            H.env.ContainerFrame1:Show()
            expect(H.env.ContainerFrame1:IsShown()).as("the guarded OnShow put it back").falsy()
        end)

        it("is idempotent, so a settings watcher can re-run it", function()
            S.Apply()
            local found = S.Apply()
            expect(#found > 0).truthy()
            S.Restore()
            expect(H.env.ContainerFrame1:IsShown())
                .as("one Restore is enough after two Applies").truthy()
        end)
    end)

    describe("routing the bag-opening functions", function()
        it("routes every global it found", function()
            S.Apply()
            for _, route in ipairs(S.ROUTES) do
                expect(S.IsRouted(route.name)).as(route.name .. " is routed").truthy()
            end
        end)

        it("opens OUR window instead of Blizzard's containers", function()
            local opened = 0
            S.SetHandler({ Open = function() opened = opened + 1 end })
            S.Apply()
            H.env.OpenAllBags()
            expect(opened).as("our handler ran").eq(1)
            expect(H.env.ContainerFrame1:IsShown())
                .as("and Blizzard's container did not open").falsy()
        end)

        it("routes the toggle the B key uses", function()
            local toggled = 0
            S.SetHandler({ Toggle = function() toggled = toggled + 1 end })
            S.Apply()
            -- ToggleBackpack is what the TOGGLEBACKPACK binding calls, so this IS the B key.
            H.env.ToggleBackpack()
            H.env.ToggleAllBags()
            expect(toggled).as("both toggles reach our window").eq(2)
        end)

        it("ignores the bag id, because the window is one combined grid", function()
            local opens = {}
            S.SetHandler({ Open = function() opens[#opens + 1] = true end })
            S.Apply()
            H.env.OpenBag(0)
            H.env.OpenBag(3)
            expect(#opens).as("every bag id opens the same window").eq(2)
        end)

        -- A replacement with nothing listening must not swallow the call: a dead B key is worse than
        -- Blizzard's bags opening.
        --
        -- DRIVEN THROUGH ToggleAllBags, and that choice is the whole test. The first version used
        -- OpenBackpack and asserted the container was hidden afterwards -- which is true whether the
        -- call fell through (Blizzard showed it, our hook hid it again) or was swallowed (nothing
        -- happened at all), so it passed with the fall-through deleted. ToggleAllBags's original
        -- RECORDS itself in the panel-toggle log, which is an effect suppression cannot erase.
        it("falls through to the client's own function when no handler is set", function()
            S.Apply()
            S.SetHandler(nil)
            local before = #H.getPanelToggles()
            H.env.ToggleAllBags()
            local after = H.getPanelToggles()
            expect(#after).as("the client's own function actually ran").eq(before + 1)
            expect(after[#after].name).eq("ToggleAllBags")
            expect(S.IsRouted("ToggleAllBags")).as("still routed, just unhandled").truthy()
        end)

        it("does NOT fall through once a handler is listening", function()
            local seen = 0
            S.SetHandler({ Toggle = function() seen = seen + 1 end })
            S.Apply()
            local before = #H.getPanelToggles()
            H.env.ToggleAllBags()
            expect(seen).as("our window handled it").eq(1)
            expect(#H.getPanelToggles())
                .as("and the client's own function did not also run").eq(before)
        end)

        it("survives a handler that throws, since these run from a keybinding", function()
            S.SetHandler({ Toggle = function() error("boom") end })
            S.Apply()
            expect(function() H.env.ToggleBackpack() end)
                .as("a throw on the B key must not surface as an action-blocked error").notThrows()
        end)
    end)

    describe("handing the default UI back", function()
        it("shows every container it hid", function()
            S.Apply()
            S.Restore()
            expect(H.env.ContainerFrame1:IsShown()).truthy()
            expect(S.IsSuppressed("ContainerFrame1")).falsy()
        end)

        -- The ordering rule: the flag is cleared BEFORE the Show, or the hook we cannot uninstall
        -- hides the frame again on the way out.
        it("clears the flag before showing, so the permanent hook does not undo it", function()
            S.Apply()
            S.Restore()
            expect(H.env.ContainerFrame1:IsShown()).as("stayed shown").truthy()
            -- And the hook is genuinely still installed, which is what makes the ordering matter.
            S.Apply()
            expect(H.env.ContainerFrame1:IsShown()).as("hook still live").falsy()
        end)

        it("puts the original functions back, not its own replacements", function()
            local before = {}
            for _, route in ipairs(S.ROUTES) do before[route.name] = H.env[route.name] end
            S.Apply()
            S.Restore()
            for _, route in ipairs(S.ROUTES) do
                expect(H.env[route.name])
                    .as(route.name .. " is the client's own again").eq(before[route.name])
                expect(S.IsRouted(route.name)).falsy()
            end
        end)

        -- A second Apply must not save its OWN replacement as "the original", which would make
        -- Restore a no-op that looks successful.
        it("still restores the real originals after two Applies", function()
            local original = H.env.ToggleBackpack
            S.Apply()
            S.Apply()
            S.Restore()
            expect(H.env.ToggleBackpack).eq(original)
        end)

        it("never shows a container it did not hide", function()
            H.env.ContainerFrame1:Hide()
            -- Never applied, so nothing was claimed; Restore must leave the player's own state alone.
            S.Restore()
            expect(H.env.ContainerFrame1:IsShown()).as("left as we found it").falsy()
        end)
    end)

    -- A bag container holds ContainerFrameItemButtonTemplate cells, which are NOT a secure template,
    -- so none of this is protected and there is deliberately no combat deferral. Pinned so a future
    -- reader does not add one by analogy with Plugins/ActionBars/Suppress.
    describe("combat", function()
        it("suppresses during combat without deferring", function()
            H.setCombat(true)
            H.resetBlockedActions()
            S.Apply()
            expect(#H.getBlockedActions()).as("the client refused nothing").eq(0)
            expect(H.env.ContainerFrame1:IsShown()).as("hidden immediately, not queued").falsy()
            H.setCombat(false)
        end)

        it("restores during combat too, so the escape hatch works mid-fight", function()
            S.Apply()
            H.setCombat(true)
            S.Restore()
            expect(H.env.ContainerFrame1:IsShown()).truthy()
            H.setCombat(false)
        end)
    end)
end)
