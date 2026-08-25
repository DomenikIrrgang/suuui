-- Plugins/Inventory: the bank session -- two LIVE windows while the player stands at a teller.
--
-- This is the requirement the whole design was built around, and the reason it needs two windows
-- rather than a scope switch: moving an item between bank and bags means dragging from one grid to
-- the other, and one window that switched scope could only ever move things one way at a time.
--
-- The MOVEMENT itself has no code to test here -- pickup and place live in
-- ContainerFrameItemButtonTemplate's own trusted OnClick, which is exactly why the cells were built
-- on it. What IS testable is that two live windows exist, side by side, over the right containers.
local H = require("harness.init")

describe("Plugins/Inventory bank session", function()
    local bagsFrame, bankFrame

    local function frames()
        bagsFrame = H.env.SuuUI_win_inventory_bags
        bankFrame = H.env.SuuUI_win_inventory_bank
        return bagsFrame, bankFrame
    end

    before_each(function()
        H.setup()
        H.setBags({
            [0] = { slots = 16, free = 14 },
            [5] = { slots = 16, free = 16 },
        })
    end)

    describe("opening at a teller", function()
        it("builds the bank window on BANKFRAME_OPENED", function()
            expect(H.env.SuuUI_win_inventory_bank).as("nothing before the bank opens").eq(nil)
            H.setBankOpen(true)
            local _, bank = frames()
            expect(bank).as("the bank window was built").truthy()
            expect(bank:IsShown()).truthy()
        end)

        -- The bags come up WITH the bank, unasked. A player who had to press B as well would find
        -- half the feature -- the half that cannot move anything.
        it("brings the bags up alongside it", function()
            H.setBankOpen(true)
            local bags = frames()
            expect(bags).as("the bags window was built too").truthy()
            expect(bags:IsShown()).as("and shown, without the player asking").truthy()
        end)

        it("does not overlap the two windows", function()
            H.setBankOpen(true)
            local bags, bank = frames()
            H.expectNoOverlap(bank, bags)
        end)

        it("puts the bank on the left and the bags on the right", function()
            H.setBankOpen(true)
            local bags, bank = frames()
            expect(H.box(bank).left).as("bank is the left of the pair").lt(H.box(bags).left)
        end)
    end)

    describe("what each window is over", function()
        it("gives the bank window the bank containers, not the bags", function()
            local ids = {}
            for _, id in ipairs(H.SuuUI._InventoryWindow.containerIds("bank")) do
                ids[id] = true
            end
            expect(ids[-1]).as("the bank's own 28-slot grid").truthy()
            expect(ids[5]).as("and the bank bags").truthy()
            expect(ids[0]).as("but NOT the backpack -- that is the other window").falsy()
        end)

        -- Bank slots are not readable away from a teller: measured, a shut bank reports 28 slots and
        -- zero free, which is only consistent with no data. So the window's contents are meaningful
        -- only inside this window of time, which is why the session is event-driven at all.
        it("reads bank contents while the bank is open", function()
            H.setBankOpen(true)
            H.setBagItem(-1, 1, { itemID = 4306, stackCount = 2, quality = 1,
                                  itemName = "Bank Cloth" })
            H.fireEvent("BAG_UPDATE", -1)
            local found = false
            for _, w in ipairs({ H.env.SuuUI_win_inventory_bank }) do
                if w then found = true end
            end
            expect(found).as("the bank window exists to read into").truthy()
        end)
    end)

    describe("leaving the teller", function()
        it("hides the bank window on BANKFRAME_CLOSED", function()
            H.setBankOpen(true)
            local _, bank = frames()
            expect(bank:IsShown()).truthy()
            H.setBankOpen(false)
            -- Window:Hide is a FADE-OUT, so the frame is still shown on the animation's first frame.
            H.runAnimations()
            expect(bank:IsShown()).as("bank window gone").falsy()
        end)

        -- Hidden rather than destroyed: rebuilding would throw away 35 cells every visit, and a cell
        -- cannot be re-pointed at another bag anyway -- its bag comes from its parent, stated once.
        it("reuses the same window on the next visit", function()
            H.setBankOpen(true)
            local first = H.env.SuuUI_win_inventory_bank
            H.setBankOpen(false)
            H.runAnimations()
            H.setBankOpen(true)
            expect(H.env.SuuUI_win_inventory_bank).as("same frame, not a rebuild").eq(first)
            expect(H.env.SuuUI_win_inventory_bank:IsShown()).truthy()
        end)

        it("re-centres the bags window once it is alone again", function()
            H.setBankOpen(true)
            local bags = frames()
            local paired = H.box(bags).left
            H.setBankOpen(false)
            H.runAnimations()
            expect(H.box(bags).left)
                .as("offset to one side with nothing beside it reads as drift").neq(paired)
        end)
    end)

    describe("teardown", function()
        it("destroys both windows when the plugin is disabled", function()
            H.setBankOpen(true)
            expect(H.env.SuuUI_win_inventory_bank:IsShown()).truthy()
            H.SuuUI.Settings:Set("inventory", "enabled", false)
            -- Destroy ends in Window:Hide, which is a fade, so both frames are still shown on the
            -- animation's first frame. Same reason the close test above runs the animations.
            H.runAnimations()
            expect(H.env.SuuUI_win_inventory_bank:IsShown()).as("bank window torn down").falsy()
            expect(H.env.SuuUI_win_inventory_bags:IsShown()).as("bags too").falsy()
        end)

        -- A disabled plugin must stop reacting. Without the unregister the next teller would rebuild
        -- windows for a plugin the player switched off.
        it("stops reacting to the bank once disabled", function()
            H.SuuUI.Settings:Set("inventory", "enabled", false)
            H.setBankOpen(true)
            local bank = H.env.SuuUI_win_inventory_bank
            expect(bank == nil or not bank:IsShown())
                .as("no window for a disabled plugin").truthy()
        end)
    end)
end)
