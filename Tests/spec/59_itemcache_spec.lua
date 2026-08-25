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

    -- THE OTHER HALF OF THE CACHE. GetItemInfo answers nil for an item this client has never seen, so
    -- a character captured on a fresh login stores ids and counts with no name, icon or quality --
    -- which the grid draws as the concept's `?` cells. The client answers later via
    -- GET_ITEM_INFO_RECEIVED, and this is what turns that answer into a permanently better cache
    -- rather than a repaint that is lost on the next login.
    describe("filling in an item the client resolves later", function()
        it("writes the resolved fields into the shared item table", function()
            H.env.SuuUIItemCache.items[22832] = { }
            H.setItemInfo(22832, { name = "Arcane Powder", quality = 1, texture = "icon-ap" })
            expect(IC:Resolve(22832)).as("it learned something").truthy()
            local e = IC:ItemInfo(22832)
            expect(e.name).eq("Arcane Powder")
            expect(e.q).eq(1)
            expect(e.icon).eq("icon-ap")
        end)

        -- A HARVESTER IS THE FAILURE MODE HERE. The event fires for every item the client resolves for
        -- ANY reason -- a tooltip, a chat link, an auction search, an inspect -- so acting on all of
        -- them would grow the account-wide table without bound with items no character owns, in a file
        -- that is already the biggest thing this feature writes.
        it("refuses an id no character holds", function()
            H.setItemInfo(19019, { name = "Thunderfury", quality = 5 })
            expect(IC:Resolve(19019)).as("not ours, not stored").falsy()
            expect(IC:ItemInfo(19019)).as("and nothing was created").falsy()
        end)

        it("does nothing for an id the client still cannot name", function()
            H.env.SuuUIItemCache.items[12345] = { }
            H.clearItems()
            expect(IC:Resolve(12345)).falsy()
            expect(IC:ItemInfo(12345).name).as("left unresolved, not blanked").falsy()
        end)

        it("never blanks a field it already had", function()
            H.env.SuuUIItemCache.items[22832] = { name = "Arcane Powder", icon = "good", q = 1 }
            -- A resolve that answers thinly must not undo a capture that answered fully; upsertItem
            -- only ever fills in, and this is the path that would have exposed it otherwise.
            H.setItemInfo(22832, { name = "Arcane Powder" })
            IC:Resolve(22832)
            expect(IC:ItemInfo(22832).icon).as("icon survived").eq("good")
        end)

        -- COALESCED ON PURPOSE. This event fires once PER ITEM, so a fresh login browsing an alt with
        -- 58 unresolved stacks fires 58 times in a few frames. One announcement after the burst
        -- settles is one re-sort instead of 58.
        it("announces once for a burst, not once per item", function()
            for _, id in ipairs({ 22832, 21877, 22833 }) do
                H.env.SuuUIItemCache.items[id] = { }
                H.setItemInfo(id, { name = "Item " .. id, quality = 1, texture = "i" })
            end
            local fired = 0
            H.SuuUI.Events:On("SUUUI_ITEMS_RESOLVED", function() fired = fired + 1 end, "spec")
            for _, id in ipairs({ 22832, 21877, 22833 }) do
                H.fireEvent("GET_ITEM_INFO_RECEIVED", id)
            end
            expect(fired).as("nothing announced yet -- still debouncing").eq(0)
            H.tick(1.0)
            expect(fired).as("exactly one announcement for the burst").eq(1)
            expect(IC:ItemInfo(21877).name).as("and all three were written").eq("Item 21877")
        end)

        it("announces nothing when the burst taught it nothing", function()
            local fired = 0
            H.SuuUI.Events:On("SUUUI_ITEMS_RESOLVED", function() fired = fired + 1 end, "spec")
            -- Items nobody holds: the common case by volume, and it must not wake a single view.
            H.fireEvent("GET_ITEM_INFO_RECEIVED", 19019)
            H.tick(1.0)
            expect(fired).eq(0)
        end)
    end)

    -- THE NAME IS NEVER RETURNED BY THE CONTAINER API. GetContainerItemInfo answers icon, count,
    -- quality, link and id -- and no name -- so a capture stored none, and a cached character could not
    -- be SEARCHED at all: the filter matched zero items whatever you typed, silently, while your own
    -- live bags searched fine because a live cell reads the client directly.
    --
    -- Every existing search spec staged the name with cacheItem() straight into the item table, which
    -- is a thing capture cannot do -- so the specs asserted against a state production never reached.
    -- That is the failure mode worth remembering here: a spec that stages what the real path cannot
    -- produce tests the staging.
    describe("the item name comes out of the link", function()
        it("extracts the bracketed name", function()
            expect(IC.NameFromLink("|cffffffff|Hitem:22832|h[Arcane Powder]|h|r")).eq("Arcane Powder")
        end)

        it("answers nil rather than an empty string for junk", function()
            expect(IC.NameFromLink(nil)).eq(nil)
            expect(IC.NameFromLink("")).eq(nil)
            expect(IC.NameFromLink("[]")).as("empty brackets are not a name").eq(nil)
            expect(IC.NameFromLink(22832)).as("a number is not a link").eq(nil)
        end)

        it("stores a name on capture, with GetItemInfo answering nothing", function()
            H.setBags({ [0] = { free = 6, slots = 8 } })
            -- Exactly what the client hands over for an item it has never cached: a full container read
            -- and no GetItemInfo entry at all.
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 12, quality = 1,
                                 iconFileID = "icon-ap",
                                 hyperlink = "|cffffffff|Hitem:22832|h[Arcane Powder]|h|r" })
            H.clearItems()
            IC:Capture("bags")
            expect(IC:ItemInfo(22832).name).as("searchable without any event").eq("Arcane Powder")
        end)

        it("never overwrites a real name with a parsed one", function()
            -- A name that was properly resolved once must survive a later capture whose link text
            -- disagrees, for the same reason upsertItem only ever fills in: a live read can be thin,
            -- and blanking or rewriting a name that already worked is invisible until a player opens an
            -- alt and cannot find anything.
            H.env.SuuUIItemCache.items[22832] = { name = "Arcane Powder" }
            H.setBags({ [0] = { free = 6, slots = 8 } })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 1, quality = 1,
                                 iconFileID = "i",
                                 hyperlink = "|Hitem:22832|h[Wrong Name]|h" })
            IC:Capture("bags")
            expect(IC:ItemInfo(22832).name).as("the stored name wins").eq("Arcane Powder")
        end)
    end)

    -- THE FIND MEMO. Find walks characters x containers x bags x slots -- around 2,500 iterations for
    -- ten alts -- and it is now on a HOVER path: the tooltip's account section calls it per item, so
    -- moving the cursor across an 80-cell grid calls it 80 times. Memoised by id, and the invalidation
    -- is the whole risk: a stale memo tells a player an item is on a character who no longer has it,
    -- which is worse than the walk being slow.
    describe("the Find memo", function()
        local function holdings(id, count)
            H.setBags({ [0] = { free = 6, slots = 8 } })
            H.setBagItem(0, 1, { itemID = id, stackCount = count, quality = 1,
                                 iconFileID = "i",
                                 hyperlink = "|Hitem:" .. id .. "|h[Thing]|h" })
            IC:Capture("bags")
        end

        it("is invalidated by a capture, so a moved item is not reported twice", function()
            holdings(22832, 5)
            expect(IC:Total(22832)).eq(5)
            -- The item is gone from the bags now. Without invalidation the memo keeps answering 5 --
            -- a tooltip claiming a character holds something they spent.
            H.clearBagItem(0, 1)
            IC:Capture("bags")
            expect(IC:Total(22832)).as("the memo did not outlive the change").eq(0)
        end)

        it("is invalidated by Forget", function()
            holdings(22832, 5)
            expect(IC:Total(22832)).eq(5)
            IC:Forget(IC:CurrentKey())
            expect(IC:Total(22832)).as("a forgotten character holds nothing").eq(0)
        end)

        it("hands out a COPY, never the memo itself", function()
            holdings(22832, 5)
            -- THE FIRST CALL IS NOT THE TEST. That one builds the answer and returns its own fresh
            -- table whether or not the memo hands out copies, so mutating it proves nothing -- the
            -- copy-out only happens on a memo HIT. The second call is the one that reads the memo.
            IC:Find(22832)
            local fromMemo = IC:Find(22832)
            expect(#fromMemo).eq(1)
            -- Same reasoning as Container:GetPadding returning a copy: the memo is what the NEXT caller
            -- reads, so one consumer's edit must not become another's answer. The tooltip section
            -- merges hits per character into its own table, and a consumer that sorted or trimmed the
            -- result in place would corrupt every later hover.
            fromMemo[1] = nil
            local third = IC:Find(22832)
            expect(#third).as("the next caller still gets the real answer").eq(1)
            expect(third[1].count).eq(5)
        end)

        it("still answers correctly for an id nobody holds", function()
            holdings(22832, 5)
            expect(#IC:Find(19019)).eq(0)
            expect(IC:Total(19019)).eq(0)
        end)
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
