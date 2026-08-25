-- Core/ItemCache.lua: the account-wide record of which character holds what.
--
-- Two properties here are worth more than the rest and are the reason several of these tests
-- assert a NEGATIVE. The bank gate must refuse to capture while the bank is shut, because
-- capturing anyway overwrites a good snapshot with an empty one -- and "the bank is empty" and
-- "the bank is unreadable" look identical in the store. And the shared item table must only ever
-- FILL IN, because a live read can be thin and blanking a name that already worked is invisible
-- until a player opens an alt and sees a wall of nothing.
local H = require("harness.init")

describe("Core/ItemCache", function()
    local IC

    before_each(function()
        H.setup()
        IC = H.SuuUI.ItemCache
    end)

    describe("the store", function()
        it("exists after boot, stamped and shaped", function()
            local s = H.env.SuuUIItemCache
            expect(type(s)).as("SavedVariable seeded at ADDON_LOADED").eq("table")
            expect(s._version).eq(1)
            expect(type(s.items)).eq("table")
            expect(type(s.chars)).eq("table")
        end)

        it("does NOT wipe an existing store on Init", function()
            H.env.SuuUIItemCache.chars["Someone-Elsewhere"] = { class = "MAGE" }
            IC:Init()
            expect(H.env.SuuUIItemCache.chars["Someone-Elsewhere"]).as("survived").truthy()
        end)

        it("repairs a store missing its sub-tables rather than replacing it", function()
            H.env.SuuUIItemCache = { _version = 1 }
            IC:Init()
            expect(type(H.env.SuuUIItemCache.items)).eq("table")
            expect(type(H.env.SuuUIItemCache.chars)).eq("table")
        end)

        it("keys the character as Name-Realm", function()
            expect(IC:CurrentKey()).eq(H.env.UnitName("player") .. "-TestRealm")
        end)
    end)

    -- DATA LOSS, MEASURED IN GAME. A cached alt showed an empty grid and no gold, and the store held
    -- `money = 0` with zero slots -- while the record itself existed, so the character still appeared
    -- in the dropdown. The cause was the PLAYER_LOGOUT sweep reading a torn-down container API and
    -- writing that nothing over a good snapshot. The bank already had this rule; bags did not.
    describe("an unreadable capture never overwrites a good one", function()
        it("refuses when the containers report no slots at all", function()
            H.setBags({ [0] = { free = 2, slots = 4 } })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 5 })
            local IC = H.SuuUI.ItemCache
            IC:Init()
            expect(IC:Capture("bags")).as("a readable capture works").truthy()
            local before = IC:Get(IC:CurrentKey(), "bags")
            expect(before.slots[0][1]).truthy()

            -- Every container answering zero slots is the state at logout and early in a login. It
            -- cannot mean "empty bags": every character has a backpack.
            H.setBags({})
            expect(IC:Capture("bags")).as("refused").falsy()
            local after = IC:Get(IC:CurrentKey(), "bags")
            expect(after.slots[0] and after.slots[0][1])
                .as("the good snapshot survived").truthy()
            expect(after.seen).as("and its timestamp was not moved").eq(before.seen)
        end)

        it("still records a character whose bags are genuinely empty", function()
            -- The discriminator is the SLOT COUNT, not the item count. Refusing an empty-but-readable
            -- bag would leave a stale snapshot forever -- a player who sells everything would keep
            -- showing the items they no longer have.
            H.setBags({ [0] = { free = 4, slots = 4 } })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 5 })
            local IC = H.SuuUI.ItemCache
            IC:Init()
            IC:Capture("bags")
            H.clearBagItem(0, 1)
            expect(IC:Capture("bags")).as("readable, just empty").truthy()
            local rec = IC:Get(IC:CurrentKey(), "bags")
            expect(rec.slots[0]).as("the item is gone from the snapshot too").eq(nil)
        end)

        it("does not write money from an unreadable capture", function()
            H.setBags({ [0] = { free = 2, slots = 4 } })
            H.setBagItem(0, 1, { itemID = 22832 })
            H.env.SuuUIItemCache = nil
            local IC = H.SuuUI.ItemCache
            IC:Init()
            H.setMoney(123456)
            IC:Capture("bags")
            expect(IC:MoneyOf(IC:CurrentKey())).eq(123456)
            -- money = 0 with zero slots is the exact signature that was measured in game.
            H.setBags({})
            H.setMoney(0)
            IC:Capture("bags")
            expect(IC:MoneyOf(IC:CurrentKey()))
                .as("the real figure survived the unreadable read").eq(123456)
        end)
    end)

    describe("capturing bags", function()
        before_each(function()
            H.setBags({ [0] = { free = 14, slots = 16 } }, { silent = true })
            H.setBagItem(0, 1, { itemID = 22832, itemName = "Arcane Powder", stackCount = 12,
                                 hyperlink = "|cffffffff|Hitem:22832|h[Arcane Powder]|h|r",
                                 iconFileID = 134129, quality = 1 }, { silent = true })
            H.setBagItem(0, 3, { itemID = 21877, itemName = "Netherweave Cloth",
                                 stackCount = 20 }, { silent = true })
        end)

        it("writes {itemID, count} pairs per slot, not whole records", function()
            expect(IC:Capture("bags")).truthy()
            local rec = IC:Get(IC:CurrentKey(), "bags")
            expect(rec.slots[0][1][1]).as("item id").eq(22832)
            expect(rec.slots[0][1][2]).as("count").eq(12)
            expect(rec.slots[0][3][1]).eq(21877)
            expect(rec.slots[0][2]).as("empty slot is absent, not zeroed").eq(nil)
        end)

        it("fills the shared item table", function()
            IC:Capture("bags")
            local e = IC:ItemInfo(22832)
            expect(e.name).eq("Arcane Powder")
            expect(e.icon).eq(134129)
            expect(e.q).eq(1)
            expect(e.link).eq("|cffffffff|Hitem:22832|h[Arcane Powder]|h|r")
        end)

        it("only ever FILLS IN the item table -- a thin read cannot blank a name", function()
            IC:Capture("bags")
            expect(IC:ItemInfo(22832).name).eq("Arcane Powder")
            -- The same item seen again with nothing but an id, which is what a slot reads like
            -- before the client has resolved it.
            H.clearBagItem(0, 1, { silent = true })
            H.setBagItem(0, 5, { itemID = 22832 }, { silent = true })
            IC:Capture("bags")
            expect(IC:ItemInfo(22832).name).as("name survived the thin read").eq("Arcane Powder")
            expect(IC:ItemInfo(22832).icon).as("icon survived").eq(134129)
        end)

        it("stamps the capture time and the character's money", function()
            H.setMoney(12844218)
            IC:Capture("bags")
            expect(IC:SeenAt(IC:CurrentKey(), "bags")).eq(H.env.time())
            expect(H.env.SuuUIItemCache.chars[IC:CurrentKey()].money).eq(12844218)
        end)

        it("reads every bag the client reports, not just the backpack", function()
            H.setBags({ [0] = { slots = 16 }, [4] = { slots = 8 } }, { silent = true })
            H.setBagItem(4, 2, { itemID = 33470 }, { silent = true })
            IC:Capture("bags")
            local rec = IC:Get(IC:CurrentKey(), "bags")
            expect(rec.slots[4] and rec.slots[4][2][1]).as("bag 4 captured").eq(33470)
        end)

        it("refuses an unknown container name", function()
            expect(IC:Capture("pockets")).falsy()
        end)
    end)

    -- BOTH halves. A spec asserting only the open case would not notice the gate at all, and the
    -- gate is the thing standing between a good snapshot and an empty one.
    describe("capturing the bank is gated on the bank being open", function()
        before_each(function()
            H.setBags({ [-1] = { slots = 28 } }, { silent = true })
            H.setBagItem(-1, 1, { itemID = 22832, stackCount = 20 }, { silent = true })
        end)

        it("refuses while the bank is shut", function()
            expect(IC:IsBankOpen()).falsy()
            expect(IC:Capture("bank")).as("refused").falsy()
            expect(IC:Get(IC:CurrentKey(), "bank")).as("nothing written").eq(nil)
        end)

        it("captures when the bank opens, driven by the event alone", function()
            H.setBankOpen(true)
            expect(IC:IsBankOpen()).truthy()
            local rec = IC:Get(IC:CurrentKey(), "bank")
            expect(rec).as("the open event captured it").truthy()
            expect(rec.slots[-1][1][1]).eq(22832)
        end)

        it("does not overwrite a good snapshot once the bank closes", function()
            H.setBankOpen(true)
            H.setBankOpen(false)
            local rec = IC:Get(IC:CurrentKey(), "bank")
            expect(rec.slots[-1][1][1]).as("snapshot survived the close").eq(22832)
            -- And an explicit attempt while shut still refuses rather than clearing it.
            IC:Capture("bank")
            expect(IC:Get(IC:CurrentKey(), "bank").slots[-1][1][1]).eq(22832)
        end)

        it("keeps a separate seen stamp per container", function()
            -- Bags have to be READABLE for this to test anything: a capture with no slots at all is
            -- now refused, because that state means the container API is not answering rather than
            -- that the bags are empty.
            H.setBags({ [0] = { free = 4, slots = 16 } })
            IC:Capture("bags")
            local bagsAt = IC:SeenAt(IC:CurrentKey(), "bags")
            expect(bagsAt).truthy()
            expect(IC:SeenAt(IC:CurrentKey(), "bank")).as("bank not seen yet").eq(nil)
            H.setBankOpen(true)
            expect(IC:SeenAt(IC:CurrentKey(), "bank")).truthy()
            expect(IC:SeenAt(IC:CurrentKey(), "bags")).as("bags stamp untouched").eq(bagsAt)
        end)
    end)

    describe("BAG_UPDATE capture is debounced", function()
        it("does not capture on the event, and does after the delay", function()
            H.setBags({ [0] = { slots = 16 } }, { silent = true })
            H.setBagItem(0, 1, { itemID = 22832 })   -- fires BAG_UPDATE
            expect(IC:Get(IC:CurrentKey(), "bags")).as("not on the event itself").eq(nil)
            -- A tick BELOW the threshold is what makes this discriminating: without it, a debounce
            -- of zero passes too, because either way the capture waits for the next frame.
            H.tick(0.1)
            expect(IC:Get(IC:CurrentKey(), "bags")).as("not yet at 0.1s").eq(nil)
            H.tick(0.5)
            expect(IC:Get(IC:CurrentKey(), "bags")).as("captured after the debounce").truthy()
        end)

        it("coalesces a burst into one capture", function()
            H.setBags({ [0] = { slots = 16 } }, { silent = true })
            for slot = 1, 5 do H.setBagItem(0, slot, { itemID = 22832 }) end
            H.tick(0.5)
            local rec = IC:Get(IC:CurrentKey(), "bags")
            expect(rec).truthy()
            -- One capture, and it saw every staged slot: the burst was coalesced rather than
            -- each event walking the bags on its own.
            local n = 0
            for _ in pairs(rec.slots[0]) do n = n + 1 end
            expect(n).eq(5)
        end)

        it("stops ticking once it has captured", function()
            H.setBags({ [0] = { slots = 16 } }, { silent = true })
            H.setBagItem(0, 1, { itemID = 22832 })
            H.tick(0.5)
            local first = IC:SeenAt(IC:CurrentKey(), "bags")
            H.setClock(H.env.time() + 60)
            H.tick(0.5)
            expect(IC:SeenAt(IC:CurrentKey(), "bags")).as("no idle re-capture").eq(first)
        end)
    end)

    describe("queries across the account", function()
        before_each(function()
            H.setBags({ [0] = { slots = 16 } }, { silent = true })
            H.setBagItem(0, 1, { itemID = 22832, itemName = "Arcane Powder", stackCount = 12 },
                         { silent = true })
            IC:Capture("bags")
            -- A second character, written straight into the store: the read side has to work for
            -- an alt this session never played.
            H.env.SuuUIItemCache.chars["Thalira-TestRealm"] = {
                class = "MAGE",
                bags = { seen = 1, slots = { [0] = { [1] = { 22832, 14 } } } },
                bank = { seen = 2, slots = { [-1] = { [4] = { 22832, 20 } } } },
            }
        end)

        it("finds every holder and container", function()
            local hits = IC:Find(22832)
            expect(#hits).as("self bags, alt bags, alt bank").eq(3)
        end)

        it("totals across the account", function()
            expect(IC:Total(22832)).eq(12 + 14 + 20)
        end)

        it("answers nothing for an item nobody holds", function()
            expect(#IC:Find(99999)).eq(0)
            expect(IC:Total(99999)).eq(0)
        end)

        it("lists the current character first, even when an alt sorts before it", function()
            -- "Aldara" sorts before the harness's own "Testchar", so alphabetical order ALONE
            -- would put the alt first. Only the isCurrent tiebreaker produces the right answer,
            -- which is what makes this fixture discriminating rather than accidentally satisfied
            -- -- the previous version used only "Thalira", which sorts after "Testchar" anyway.
            H.env.SuuUIItemCache.chars["Aldara-TestRealm"] = { class = "DRUID" }
            local chars = IC:Characters()
            expect(#chars).eq(3)
            expect(chars[1].isCurrent).as("you come first").truthy()
            expect(chars[1].key).eq(IC:CurrentKey())
            expect(chars[2].name).as("then alphabetically").eq("Aldara")
            expect(chars[3].name).eq("Thalira")
        end)

        it("carries each character's name, realm and class", function()
            local chars = IC:Characters()
            expect(#chars).eq(2)
            expect(chars[2].name).eq("Thalira")
            expect(chars[2].realm).eq("TestRealm")
            expect(chars[2].class).eq("MAGE")
        end)

        it("forgets a character", function()
            expect(IC:Forget("Thalira-TestRealm")).truthy()
            expect(#IC:Characters()).eq(1)
            expect(IC:Total(22832)).as("their items went with them").eq(12)
            expect(IC:Forget("Nobody-Nowhere")).as("no-op for an absent key").falsy()
        end)
    end)

    -- An absent API must be a VISIBLE fault, not a silently empty cache: "the API is gone" and
    -- "this character owns nothing" render identically and only one of them is normal.
    describe("a missing container API faults rather than recording nothing", function()
        it("reports it and refuses", function()
            H.setBagApi("none")
            H.SuuUI.ClearFaults()
            expect(IC:Capture("bags")).as("refused").falsy()
            local found = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("container API", 1, true) then found = true end
            end
            expect(found).as("the fault was printed").truthy()
        end)

        it("still captures through the legacy positional shape", function()
            H.setBags({ [0] = { slots = 16 } }, { silent = true })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 7 }, { silent = true })
            H.setBagApi("legacy")
            expect(IC:Capture("bags")).truthy()
            local rec = IC:Get(IC:CurrentKey(), "bags")
            expect(rec.slots[0][1][1]).as("id through the bare global").eq(22832)
            expect(rec.slots[0][1][2]).as("count through the bare global").eq(7)
        end)
    end)
end)
