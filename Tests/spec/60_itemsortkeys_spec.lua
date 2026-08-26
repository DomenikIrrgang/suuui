-- Components/ItemSortKeys -- the `quality_type` ordering rule.
--
-- Seven keys deep, so the assertions that matter are the ones proving each key is REACHED and that
-- the one above it wins when they disagree. A test that only checks the final sequence of a bag full
-- of items cannot tell which key produced it, and would pass with any two keys swapped.
local H = require("harness.init")

describe("Components/ItemSortKeys", function()
    local SK

    -- Item classes, by the client's own numbers. Named here so the assertions read as intent rather
    -- than as magic numbers, and so a renumbered enum fails in one place.
    local CONSUMABLE, WEAPON, ARMOR, TRADEGOODS, QUEST = 0, 2, 4, 7, 12

    before_each(function()
        H.setup()
        SK = H.SuuUI.ItemSortKeys
        H.setBags({ [0] = { slots = 12, free = 0 } }, { silent = true })
    end)

    -- One entry in ItemGrid's own shape. Built by hand rather than through a grid, because these
    -- tests are about the comparator and a grid would drag bag staging and layout in with it.
    local function entry(bag, slot, info)
        return { bag = bag, slot = slot, info = info }
    end

    local function item(id, props)
        props = props or {}
        H.setItemInfo(id, {
            name       = props.name or ("Item " .. id),
            quality    = props.quality or 1,
            itemLevel  = props.itemLevel or 1,
            sellPrice  = props.sellPrice or 0,
            equipSlot  = props.equipSlot or "",
            classID    = props.classID or 15,
            subclassID = props.subclassID or 0,
        })
        return {
            itemID = id, itemName = props.name or ("Item " .. id),
            quality = props.quality or 1, stackCount = props.stackCount or 1,
        }
    end

    describe("quality outranks category", function()
        -- THE HEADLINE, and the one thing most likely to be got wrong: category is NOT the primary
        -- key. A rare trade good beats an uncommon weapon.
        it("puts a rarer trade good above a commoner weapon", function()
            local rareGood = entry(0, 1, item(101, { quality = 3, classID = TRADEGOODS }))
            local greenWep = entry(0, 2, item(102, { quality = 2, classID = WEAPON,
                                                    equipSlot = "INVTYPE_WEAPON" }))
            expect(SK.Compare(rareGood, greenWep)).as("quality first").truthy()
            expect(SK.Compare(greenWep, rareGood)).falsy()
        end)

        it("falls to category only when quality ties", function()
            local consum = entry(0, 1, item(103, { quality = 2, classID = CONSUMABLE }))
            local quest  = entry(0, 2, item(104, { quality = 2, classID = QUEST }))
            expect(SK.Compare(consum, quest)).as("class 0 before class 12").truthy()
            expect(SK.Compare(quest, consum)).falsy()
        end)
    end)

    describe("conjured items are demoted below poor", function()
        -- 5350 is Conjured Water. The point of the demotion is that a mage's water does not sit in
        -- the middle of the bag at common quality, so the comparison that matters is against a GREY.
        it("ranks conjured water below a grey", function()
            local water = entry(0, 1, item(5350, { quality = 1, classID = CONSUMABLE }))
            local grey  = entry(0, 2, item(105, { quality = 0, classID = TRADEGOODS }))
            expect(SK.IsConjured(5350)).truthy()
            expect(SK.Compare(grey, water)).as("even a grey outranks conjured").truthy()
            expect(SK.Compare(water, grey)).falsy()
        end)

        it("sorts below an unknown quality, so the two ranks cannot collide", function()
            -- -99 rather than -1 exists precisely so "deliberately demoted" and "not learned yet" stay
            -- distinguishable. An item of unknown quality reads -1, so conjured is the lower of the
            -- two -- which is the right way round: the demotion is a decision we have made, while an
            -- unknown quality is a state we expect to leave.
            local water   = entry(0, 1, item(5350, { quality = 1 }))
            local unknown = entry(0, 2, { itemID = 106, itemName = "?" })
            expect(SK.Compare(unknown, water)).as("unknown outranks demoted").truthy()
            expect(SK.Compare(water, unknown)).falsy()
        end)

        it("leaves a non-conjured id alone", function()
            expect(SK.IsConjured(105)).falsy()
            expect(SK.IsConjured(nil)).falsy()
        end)
    end)

    describe("gear orders by where it is worn", function()
        it("puts a helm before boots", function()
            local helm  = entry(0, 1, item(201, { quality = 3, classID = ARMOR,
                                                 equipSlot = "INVTYPE_HEAD" }))
            local boots = entry(0, 2, item(202, { quality = 3, classID = ARMOR,
                                                 equipSlot = "INVTYPE_FEET" }))
            expect(SK.Compare(helm, boots)).as("head 1 before feet 8").truthy()
            expect(SK.Compare(boots, helm)).falsy()
        end)

        -- The equip-slot branch REPLACES the subclass key for gear, which is the decision worth
        -- pinning: cloth and plate of the same slot interleave rather than clustering by armour type.
        it("ignores subclass for gear, so armour types interleave", function()
            local cloth = entry(0, 1, item(203, { quality = 3, classID = ARMOR, subclassID = 1,
                                                 equipSlot = "INVTYPE_HEAD", itemLevel = 60 }))
            local plate = entry(0, 2, item(204, { quality = 3, classID = ARMOR, subclassID = 4,
                                                 equipSlot = "INVTYPE_HEAD", itemLevel = 70 }))
            -- Plate has the LOWER subclass ordering claim (4 > 1) but the HIGHER item level, so if
            -- subclass were consulted cloth would lead. It does not, so item level decides.
            expect(SK.Compare(plate, cloth)).as("same slot, so item level decides").truthy()
        end)

        it("leads the class with an equip slot it does not name", function()
            local odd  = entry(0, 1, item(205, { quality = 3, classID = ARMOR,
                                                equipSlot = "INVTYPE_SOMETHING_NEW" }))
            local helm = entry(0, 2, item(206, { quality = 3, classID = ARMOR,
                                                equipSlot = "INVTYPE_HEAD" }))
            expect(SK.Compare(odd, helm)).as("unnamed slots order at -1").truthy()
        end)
    end)

    describe("non-gear orders by subclass", function()
        it("splits two consumables by subclass", function()
            local potion = entry(0, 1, item(301, { quality = 1, classID = CONSUMABLE,
                                                  subclassID = 1 }))
            local food   = entry(0, 2, item(302, { quality = 1, classID = CONSUMABLE,
                                                  subclassID = 5 }))
            expect(SK.Compare(potion, food)).truthy()
            expect(SK.Compare(food, potion)).falsy()
        end)
    end)

    describe("the grade keys break a full tie", function()
        it("puts the higher item level first", function()
            local a = entry(0, 1, item(401, { quality = 3, classID = TRADEGOODS, itemLevel = 60 }))
            local b = entry(0, 2, item(402, { quality = 3, classID = TRADEGOODS, itemLevel = 70 }))
            expect(SK.Compare(b, a)).as("item level DESCENDS").truthy()
        end)

        it("falls to the higher sell price when item levels tie", function()
            local cheap = entry(0, 1, item(403, { quality = 3, classID = TRADEGOODS,
                                                 itemLevel = 60, sellPrice = 10 }))
            local dear  = entry(0, 2, item(404, { quality = 3, classID = TRADEGOODS,
                                                 itemLevel = 60, sellPrice = 500 }))
            expect(SK.Compare(dear, cheap)).as("price DESCENDS").truthy()
        end)

        it("falls to the name when level and price tie", function()
            local zed = entry(0, 1, item(405, { quality = 3, classID = TRADEGOODS, name = "Zinc" }))
            local ay  = entry(0, 2, item(406, { quality = 3, classID = TRADEGOODS, name = "Argent" }))
            expect(SK.Compare(ay, zed)).as("name ASCENDS").truthy()
        end)

        -- table.sort is not stable in Lua, so without this backstop two items alike on every key
        -- would swap places between logins for no visible reason.
        it("falls to container and slot as a total-order backstop", function()
            local first  = entry(0, 3, item(407, { quality = 3, name = "Same" }))
            local second = entry(0, 7, item(408, { quality = 3, name = "Same" }))
            expect(SK.Compare(first, second)).as("earlier slot leads").truthy()
            expect(SK.Compare(second, first)).falsy()
            local otherBag = entry(1, 1, item(409, { quality = 3, name = "Same" }))
            expect(SK.Compare(first, otherBag)).as("earlier container leads").truthy()
        end)
    end)

    describe("the same item id", function()
        it("leads with the smaller stack", function()
            -- Kept faithful on purpose: ElvUI merges partial stacks before sorting so this branch
            -- almost never shows there, while SuuUI moves nothing so it fires constantly.
            local big   = entry(0, 1, item(501, { quality = 1, stackCount = 20 }))
            local small = entry(0, 2, item(501, { quality = 1, stackCount = 7 }))
            expect(SK.Compare(small, big)).as("7 before 20").truthy()
            expect(SK.Compare(big, small)).falsy()
        end)

        it("falls to slot when the stacks match", function()
            local a = entry(0, 2, item(502, { quality = 1, stackCount = 5 }))
            local b = entry(0, 9, item(502, { quality = 1, stackCount = 5 }))
            expect(SK.Compare(a, b)).truthy()
        end)
    end)

    describe("an item the client has not cached", function()
        -- The state that matters for a snapshot of another character, and the reason CLASS_UNKNOWN is
        -- HIGH rather than low: the item waits at the end of its own quality band, so resolving moves
        -- it a few cells instead of across the grid.
        it("orders at the end of its own quality band, not the end of the grid", function()
            local known = entry(0, 1, item(601, { quality = 3, classID = QUEST }))
            -- 602 is simply never staged, which is what "the client has not cached it" is. An earlier
            -- version of this called H.clearItems() here instead, which wiped 601 as well -- so BOTH
            -- sides read CLASS_UNKNOWN, the comparison fell through to the name key, and the assertion
            -- passed with the fallback set to any value at all. Two values wrong in the same way prove
            -- nothing, and the surviving mutation is what said so.
            local uncached = entry(0, 2, { itemID = 602, itemName = "Mystery", quality = 3 })
            -- Quest is class 12, the highest real class in this fixture, and the uncached item still
            -- loses to it -- so the fallback is above every class rather than beside one.
            expect(SK.Compare(known, uncached)).as("class 99 trails class 12").truthy()
            expect(SK.Compare(uncached, known)).falsy()
            -- But it still beats an item of LOWER quality, which is what "end of its own band" means.
            local greyKnown = entry(0, 3, { itemID = 603, itemName = "Grey", quality = 0 })
            expect(SK.Compare(uncached, greyKnown)).as("quality still decides first").truthy()
        end)

        it("reads the account cache when the client cannot answer", function()
            -- An alt's item: the client has never cached it, but a capture stored its class. Without
            -- this fallback every item in a snapshot would order at CLASS_UNKNOWN.
            H.setBagItem(0, 1, { itemID = 701, stackCount = 1, quality = 3, iconFileID = "i",
                                 hyperlink = "|cffffffff|Hitem:701|h[Alt Sword]|h|r" },
                         { silent = true })
            H.setItemInfo(701, { name = "Alt Sword", quality = 3, classID = WEAPON,
                                 equipSlot = "INVTYPE_WEAPON", itemLevel = 70 })
            H.SuuUI.ItemCache:Capture("bags")
            expect(H.SuuUI.ItemCache:ItemInfo(701).cls).as("the capture stored the class").eq(WEAPON)

            -- Now the client forgets it, exactly as it has for an item only an alt owns.
            H.clearItems()
            expect(select(1, SK.Meta(701))).as("resolved from the cache").eq(WEAPON)
        end)

        it("does not memoise a miss", function()
            H.clearItems()
            expect(SK.Meta(801)).as("nothing known yet").eq(nil)
            H.setItemInfo(801, { classID = WEAPON })
            expect(select(1, SK.Meta(801))).as("and it learns once told").eq(WEAPON)
        end)

        it("answers nil for no id at all", function()
            expect(SK.Meta(nil)).eq(nil)
        end)

        -- A HARNESS GUARD rather than a production one, and it is here because a stale memo would make
        -- some FUTURE spec pass against a state the client is not in. Memoising is sound in game --
        -- an item's class never changes -- but `H.clearItems` exists precisely to declare an item
        -- uncached again, so the memo has to go with it.
        it("forgets what it learned when the client forgets the item", function()
            H.setItemInfo(902, { classID = WEAPON })
            expect(select(1, SK.Meta(902))).as("learned and memoised").eq(WEAPON)
            H.clearItems()
            expect(SK.Meta(902)).as("and unlearned with the client's own cache").eq(nil)
        end)
    end)
end)
