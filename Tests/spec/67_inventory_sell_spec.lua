-- Plugins/Inventory/Sell: grey items to a vendor, one per tick.
--
-- The assertions that earn their place are the ONES THAT PROTECT ITEMS. Selling is irreversible once
-- the vendor's twelve buyback slots overflow, and UseContainerItem means something different away from
-- a merchant -- it USES the item -- so "refuses to run without a merchant" is a safety property rather
-- than tidiness.
local H = require("harness.init")

describe("Plugins/Inventory selling junk", function()
    local Sell

    local function junk(bag, slot, itemID, count, opts)
        opts = opts or {}
        local link = "|cff9d9d9d|Hitem:" .. itemID .. "|h[Junk " .. itemID .. "]|h|r"
        H.setBagItem(bag, slot, {
            itemID = itemID, stackCount = count or 1, quality = 0,
            itemName = "Junk " .. itemID, hyperlink = link,
            hasNoValue = opts.hasNoValue or false,
            isLocked = opts.isLocked or false,
        })
        if not opts.noPrice then
            H.setItemInfo(link, { name = "Junk " .. itemID, quality = 0,
                                  sellPrice = opts.price or 100 })
        end
    end

    before_each(function()
        H.setup()
        Sell = H.SuuUI._Inventory.Sell
        Sell.Stop()
        H.setBags({ [0] = { slots = 8, free = 4 } })
    end)

    describe("scanning", function()
        it("finds grey items and totals their value", function()
            junk(0, 1, 111, 1, { price = 250 })
            junk(0, 2, 222, 3, { price = 100 })
            local list, total, unknown = Sell.Scan({ 0 })
            expect(#list).eq(2)
            expect(total).as("price times stack count").eq(250 + 300)
            expect(unknown).falsy()
        end)

        -- A grey the vendor will not take cannot be sold at all. Queuing it would make the run appear
        -- to stall on an item that will never leave the bag.
        it("skips a grey with no sell value", function()
            junk(0, 1, 111, 1, { hasNoValue = true })
            expect(#Sell.Scan({ 0 })).eq(0)
        end)

        it("skips a locked slot, since a move is already in flight", function()
            junk(0, 1, 111, 1, { isLocked = true })
            expect(#Sell.Scan({ 0 })).eq(0)
        end)

        it("ignores anything above grey", function()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1,
                                 itemName = "Silk Cloth" })
            H.setBagItem(0, 2, { itemID = 22832, stackCount = 1, quality = 4,
                                 itemName = "Epic" })
            expect(#Sell.Scan({ 0 })).as("only Poor is junk").eq(0)
        end)

        -- A total that is silently short is worse than a hedged one, so an uncached price is REPORTED
        -- rather than counted as zero.
        it("reports an unknown price instead of under-counting", function()
            junk(0, 1, 111, 1, { noPrice = true })
            local list, total, unknown = Sell.Scan({ 0 })
            expect(#list).as("still sellable").eq(1)
            expect(total).eq(0)
            expect(unknown).as("so the caller can say 'at least'").truthy()
        end)
    end)

    describe("the merchant gate", function()
        it("refuses to start without a merchant", function()
            junk(0, 1, 111)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(false)
            expect(Sell.Start(list)).as("refused").falsy()
            expect(Sell.IsRunning()).falsy()
        end)

        it("starts at a merchant", function()
            junk(0, 1, 111)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            expect(Sell.Start(list)).truthy()
            expect(Sell.IsRunning()).truthy()
            Sell.Stop()
        end)

        it("refuses an empty list", function()
            H.setMerchantOpen(true)
            expect(Sell.Start({})).falsy()
        end)
    end)

    describe("draining the queue", function()
        it("sells one item per tick, not all in one frame", function()
            junk(0, 1, 111)
            junk(0, 2, 222)
            junk(0, 3, 333)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            H.resetUsedContainerItems()
            Sell.Start(list)

            H.tick(0.25)
            expect(#H.getUsedContainerItems()).as("one after the first tick").eq(1)
            H.tick(0.25)
            expect(#H.getUsedContainerItems()).as("two after the second").eq(2)
            H.tick(0.25)
            expect(#H.getUsedContainerItems()).eq(3)
        end)

        it("does not sell before the interval elapses", function()
            junk(0, 1, 111)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            H.resetUsedContainerItems()
            Sell.Start(list)
            H.tick(0.05)
            expect(#H.getUsedContainerItems()).as("throttled, not immediate").eq(0)
        end)

        it("stops and unregisters its ticker when the queue drains", function()
            junk(0, 1, 111)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            Sell.Start(list)
            H.tick(0.25)
            H.tick(0.25)
            expect(Sell.IsRunning()).as("no idle OnUpdate left behind").falsy()
        end)

        it("calls back when it finishes", function()
            junk(0, 1, 111)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            local done = 0
            Sell.Start(list, function() done = done + 1 end)
            H.tick(0.25)
            H.tick(0.25)
            expect(done).eq(1)
        end)

        -- THE SAFETY PROPERTY. Re-checked every tick rather than once at the start: the player can walk
        -- away mid-sale, and from that moment the same call would try to USE each remaining grey.
        it("stops the moment the merchant closes", function()
            for i = 1, 4 do junk(0, i, 100 + i) end
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            H.resetUsedContainerItems()
            Sell.Start(list)
            H.tick(0.25)
            expect(#H.getUsedContainerItems()).eq(1)

            H.setMerchantOpen(false)
            H.tick(0.25)
            H.tick(0.25)
            expect(#H.getUsedContainerItems()).as("nothing sold after walking away").eq(1)
            expect(Sell.IsRunning()).as("and the loop stopped itself").falsy()
            expect(#H.getBlockedActions()).as("no refused call was attempted").eq(0)
        end)

        it("refuses to start a second sale while one is running", function()
            junk(0, 1, 111)
            junk(0, 2, 222)
            local list = Sell.Scan({ 0 })
            H.setMerchantOpen(true)
            Sell.Start(list)
            expect(Sell.Start(list)).as("one sale at a time").falsy()
            Sell.Stop()
        end)
    end)
end)
