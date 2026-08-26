-- Components/ItemGrid.lua: the flat combined grid.
--
-- The load-bearing assertions here are about ORDER and about what does NOT happen: a bag update
-- must repaint without re-sorting (or items move out from under the player's cursor while they
-- loot), and a filter must dim without relayout (or the grid reflows while they type).
local H = require("harness.init")

describe("Components/ItemGrid", function()
    local root, CELL = nil, 34

    before_each(function()
        H.setup()
        root = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
        H.setBags({ [0] = { slots = 8, free = 5 }, [1] = { slots = 4, free = 4 } },
                  { silent = true })
    end)

    local function grid(props)
        props = props or {}
        local g = H.C.ItemGrid({
            containers = props.containers or { 0 },
            cols       = props.cols or 4,
            cellSize   = props.cellSize or CELL,
            spacing    = props.spacing or 2,
            sortMode   = props.sortMode,
            readOnly   = props.readOnly,
            character  = props.character,
            which      = props.which,
        }, root)
        H.SuuUI.UIRoot:GetRootContainer():Add(g, { anchor = {
            point = "TOPLEFT", relativeTo = root, relativePoint = "TOPLEFT", x = 0, y = 0,
        } })
        return g
    end

    local function stage(bag, slot, props)
        H.setBagItem(bag, slot, props, { silent = true })
    end

    -- The names are chosen so the alphabetical tiebreak is unambiguous and so quality order and
    -- name order DISAGREE -- otherwise a sort test cannot tell the two modes apart.
    local function stageThree()
        stage(0, 1, { itemID = 111, itemName = "Zebra Cloth",  quality = 1, stackCount = 5 })
        stage(0, 2, { itemID = 222, itemName = "Amber Potion", quality = 4, stackCount = 1 })
        stage(0, 3, { itemID = 333, itemName = "Middling Ore", quality = 2, stackCount = 9 })
    end

    describe("construction", function()
        it("needs containers, cols and a cell size", function()
            expect(function() H.C.ItemGrid({ cols = 4, cellSize = 34 }, root) end).throws()
            expect(function() H.C.ItemGrid({ containers = { 0 }, cellSize = 34 }, root) end).throws()
            expect(function() H.C.ItemGrid({ containers = { 0 }, cols = 4 }, root) end).throws()
        end)

        it("builds one cell per slot the client reports", function()
            local g = grid({ containers = { 0, 1 } })
            local _, _, total = g:GetCounts()
            expect(total).as("8 in bag 0 plus 4 in bag 1").eq(12)
        end)

        it("reports used and free from the real contents", function()
            stageThree()
            local g = grid()
            local used, free, total = g:GetCounts()
            expect(used).eq(3)
            expect(total).eq(8)
            expect(free).eq(5)
        end)

        it("sizes itself from cols, cell size and spacing", function()
            local g = grid({ cols = 4, cellSize = 34, spacing = 2 })
            -- 8 slots over 4 columns is 2 rows.
            H.expectSize(g, 4 * 34 + 3 * 2, 2 * 34 + 1 * 2)
        end)

        it("grows a row when the slot count needs one", function()
            H.setBags({ [0] = { slots = 9 } }, { silent = true })
            local g = grid({ cols = 4 })
            local _, h = H.box(g).width, H.box(g).height
            expect(h).as("9 slots over 4 columns is 3 rows").eq(3 * CELL + 2 * 2)
        end)
    end)

    describe("cells are wired to the right bag", function()
        it("gives each cell the bag its holder carries", function()
            local g = grid({ containers = { 0, 1 } })
            local bags = {}
            for _, e in ipairs(g._entries) do bags[e.cell:GetBag()] = true end
            expect(bags[0]).truthy()
            expect(bags[1]).truthy()
        end)

        it("keeps slot numbers within each bag", function()
            local g = grid({ containers = { 0, 1 } })
            for _, e in ipairs(g._entries) do
                expect(e.cell:GetSlot()).eq(e.slot)
                expect(e.cell:GetBag()).eq(e.bag)
            end
        end)
    end)

    describe("sorting is display-only", function()
        it("orders by quality descending then name by default", function()
            stageThree()
            local g = grid()
            expect(g:GetSortMode()).eq("quality")
            expect(g._entries[1].info.itemName).as("epic first").eq("Amber Potion")
            expect(g._entries[2].info.itemName).as("then uncommon").eq("Middling Ore")
            expect(g._entries[3].info.itemName).as("then common").eq("Zebra Cloth")
        end)

        it("puts empty slots last", function()
            stageThree()
            local g = grid()
            expect(g._entries[4].info).as("the tail is empty").eq(nil)
            expect(g._entries[8].info).eq(nil)
        end)

        it("orders by name when asked, which DISAGREES with quality order", function()
            stageThree()
            local g = grid()
            expect(g:SetSortMode("name")).truthy()
            expect(g._entries[1].info.itemName).eq("Amber Potion")
            expect(g._entries[2].info.itemName).as("name order, not quality").eq("Middling Ore")
            expect(g._entries[3].info.itemName).eq("Zebra Cloth")
        end)

        it("orders by container and slot for the client's own order", function()
            stageThree()
            local g = grid()
            g:SetSortMode("slot")
            expect(g._entries[1].slot).eq(1)
            expect(g._entries[1].info.itemName).as("slot 1 regardless of quality")
                .eq("Zebra Cloth")
        end)

        it("refuses an unknown mode and keeps the current one", function()
            local g = grid()
            expect(g:SetSortMode("bogus")).falsy()
            expect(g:GetSortMode()).eq("quality")
        end)

        it("moves no items -- the slots are untouched", function()
            stageThree()
            local g = grid()
            g:SetSortMode("name")
            -- The cell that was showing slot 1 still IS slot 1; only its position changed.
            local info = H.env.C_Container.GetContainerItemInfo(0, 1)
            expect(info.itemName).as("slot 1 still holds what it held").eq("Zebra Cloth")
        end)

        -- Container:Add is MEMBERSHIP, not upsert, so re-placing without removing first grows the
        -- child list on every sort. The geometry looks identical -- a cell can only be in one place
        -- -- so the COUNT is the only thing that can catch it.
        it("does not accumulate children when re-sorted", function()
            stageThree()
            local g = grid()
            local n = #g._cellBox:GetChildren()
            expect(n).gt(0)
            g:SetSortMode("name")
            g:SetSortMode("slot")
            g:Sort()
            expect(#g._cellBox:GetChildren()).as("Add is membership, not upsert").eq(n)
        end)
    end)

    -- The negative that matters: order must survive a repaint, or looting shuffles the grid under
    -- the player's cursor.
    describe("a bag update repaints without re-sorting", function()
        it("keeps the order when contents change", function()
            stageThree()
            local g = grid()
            local firstBefore = g._entries[1].slot
            -- A new epic lands in a later slot. If Refresh re-sorted, it would jump to the front.
            stage(0, 5, { itemID = 444, itemName = "Aaa Blade", quality = 4 })
            g:Refresh()
            expect(g._entries[1].slot).as("order unchanged").eq(firstBefore)
            local last
            for _, e in ipairs(g._entries) do if e.slot == 5 then last = e end end
            expect(last.info.itemName).as("but the new item is painted").eq("Aaa Blade")
        end)

        it("re-sorts only when asked", function()
            stageThree()
            local g = grid()
            stage(0, 5, { itemID = 444, itemName = "Aaa Blade", quality = 4 })
            g:Refresh()
            g:Sort()
            expect(g._entries[1].info.itemName).as("now it moves").eq("Aaa Blade")
        end)
    end)

    describe("the filter dims rather than removing", function()
        it("dims non-matches and leaves matches alone", function()
            stageThree()
            local g = grid()
            g:SetFilter("potion")
            for _, e in ipairs(g._entries) do
                local name = e.info and e.info.itemName
                if name == "Amber Potion" then
                    expect(e.cell:IsDimmed()).as("the match stays bright").falsy()
                else
                    expect(e.cell:IsDimmed()).as("everything else recedes").truthy()
                end
            end
        end)

        it("does not change the layout", function()
            stageThree()
            local g = grid()
            local before = H.box(g._entries[1].cell)
            g:SetFilter("potion")
            local after = H.box(g._entries[1].cell)
            expect(after.left).as("no reflow while typing").eq(before.left)
            expect(after.top).eq(before.top)
        end)

        it("is case-insensitive and matches a substring", function()
            stageThree()
            local g = grid()
            g:SetFilter("AMB")
            expect(g:CountMatches()).eq(1)
        end)

        it("clears back to everything", function()
            stageThree()
            local g = grid()
            g:SetFilter("potion")
            g:SetFilter(nil)
            for _, e in ipairs(g._entries) do
                expect(e.cell:IsDimmed()).as("all bright again").falsy()
            end
        end)

        it("dims an item whose name has not resolved rather than calling it a miss", function()
            -- No itemName: the client has not resolved it yet. Claiming it does not match would be
            -- a claim we cannot support, so it dims.
            stage(0, 1, { itemID = 999 })
            local g = grid()
            g:SetFilter("anything")
            expect(g._entries[1].cell:IsDimmed()).truthy()
        end)

        -- THE OTHER HALF OF THE CUE, and it was untested until a mutation said so: replacing the
        -- grid's SetMatched(hit) with SetMatched(false) left this whole file green, because the ring
        -- was only ever asserted at the ItemSlot level. Dimming and ringing are wired in the same
        -- loop and both need covering here.
        it("rings the matches while it dims the rest", function()
            stageThree()
            local g = grid()
            g:SetFilter("amber")
            local acc = H.token("colorAccent")
            local lit, unlit = 0, 0
            for _, e in ipairs(g._entries) do
                local _, _, _, a = e.cell._matchRing:GetBackdropBorderColor()
                if a > 0.5 then
                    lit = lit + 1
                    expect(e.cell:IsDimmed()).as("a ringed cell is never also dimmed").falsy()
                    local r = e.cell._matchRing:GetBackdropBorderColor()
                    expect(r).as("and the ring is the accent").near(acc[1], 0.001)
                else
                    unlit = unlit + 1
                end
            end
            expect(lit).as("something was ringed").gt(0)
            expect(unlit).as("and something was not").gt(0)
        end)

        it("puts every ring out when the filter is cleared", function()
            stageThree()
            local g = grid()
            g:SetFilter("amber")
            g:SetFilter(nil)
            for _, e in ipairs(g._entries) do
                local _, _, _, a = e.cell._matchRing:GetBackdropBorderColor()
                expect(a).as("a ring left lit would mark a filter that is gone").near(0, 0.001)
            end
        end)

        -- THE FLAG IS NOT THE EFFECT. Every dim assertion in this file checked IsDimmed(), which is a
        -- boolean the component sets on itself -- so all of them would pass with nothing visibly
        -- dimming, and that is exactly what was reported in game: the match count correct, no cell
        -- changing. Assert the ALPHA, which is what a player actually sees.
        it("actually changes the cell's alpha, not just its flag", function()
            stageThree()
            local g = grid()
            g:SetFilter("amber")
            local dimmed, bright
            for _, e in ipairs(g._entries) do
                if e.cell:IsDimmed() then dimmed = dimmed or e.cell
                else bright = bright or e.cell end
            end
            expect(dimmed).as("something was dimmed").truthy()
            expect(bright).as("and something was not").truthy()
            -- OUR OWN CHILDREN, not the cell frame. Measured in game: the template's button frame does
            -- not hold an alpha -- SetAlpha(0.3) then GetAlpha() returned 1, because the template's
            -- animation groups own it -- so asserting the frame would assert the thing that cannot work.
            expect(dimmed._iconComp:GetFrame():GetAlpha())
                .as("a dimmed cell's art is visibly faded").lt(1)
            expect(dimmed._overlay:GetAlpha())
                .as("and its readouts fade with it, or the count floats at full strength").lt(1)
            expect(bright._iconComp:GetFrame():GetAlpha())
                .as("a matching cell is full strength").near(1, 0.001)
            expect(dimmed:GetFrame():GetAlpha())
                .as("the template's own frame is deliberately left alone").near(1, 0.001)
        end)

        -- The flag and the pixels must not be able to disagree. SetDimmed re-applies unconditionally
        -- because an early return on an unchanged flag is exactly how the in-game defect hid: the
        -- template reset the alpha and every later call short-circuited before restoring it.
        it("re-applies the fade even when the flag has not changed", function()
            stageThree()
            local g = grid()
            g:SetFilter("amber")
            local c
            for _, e in ipairs(g._entries) do if e.cell:IsDimmed() then c = e.cell break end end
            expect(c).truthy()
            -- Something else stomps the alpha, exactly as the template's animation did.
            c._iconComp:GetFrame():SetAlpha(1)
            g:SetFilter("amber")
            expect(c._iconComp:GetFrame():GetAlpha())
                .as("re-asserted rather than skipped").lt(1)
        end)

        it("returns every cell to full alpha when the filter is cleared", function()
            stageThree()
            local g = grid()
            g:SetFilter("amber")
            g:SetFilter(nil)
            for _, e in ipairs(g._entries) do
                expect(e.cell._iconComp:GetFrame():GetAlpha()).as("all bright again").near(1, 0.001)
                expect(e.cell._overlay:GetAlpha()).as("readouts too").near(1, 0.001)
            end
        end)

        it("survives a re-sort", function()
            stageThree()
            local g = grid()
            g:SetFilter("potion")
            g:SetSortMode("name")
            local bright = 0
            for _, e in ipairs(g._entries) do
                if not e.cell:IsDimmed() then bright = bright + 1 end
            end
            expect(bright).as("the filter was re-applied after the re-order").eq(1)
        end)
    end)

    describe("containers can change", function()
        it("rebuilds and emits CHILDREN_CHANGED", function()
            local g = grid({ containers = { 0 } })
            local spy = H.signalSpy(g, H.C.ITEMGRID_SIGNALS.CHILDREN_CHANGED)
            g:SetContainers({ 0, 1 })
            expect(spy.count).as("holders of cell references were told").eq(1)
            local _, _, total = g:GetCounts()
            expect(total).eq(12)
        end)

        it("drops cells for slots a smaller bag no longer has", function()
            local g = grid({ containers = { 0 } })
            expect(select(3, g:GetCounts())).eq(8)
            H.setBags({ [0] = { slots = 4 } }, { silent = true })
            g:Refresh()
            expect(select(3, g:GetCounts())).as("four slots went away").eq(4)
        end)
    end)

    -- A grid holds protected cells, so geometry is refused in combat -- and a bag gaining a slot
    -- mid-fight is ordinary rather than exotic.
    describe("geometry defers in combat", function()
        it("records the change and applies it on the way out", function()
            local g = grid({ containers = { 0 } })
            H.setCombat(true)
            g:SetContainers({ 0, 1 })
            expect(g:IsDeferred()).as("refused for now").truthy()
            expect(select(3, g:GetCounts())).as("still the old set").eq(8)
            H.setCombat(false)
            expect(g:IsDeferred()).falsy()
            expect(select(3, g:GetCounts())).as("caught up").eq(12)
        end)

        it("does not defer a filter, which touches no geometry", function()
            stageThree()
            local g = grid()
            H.setCombat(true)
            g:SetFilter("potion")
            expect(g:CountMatches()).as("filtering works in combat").eq(1)
            expect(g:IsDeferred()).falsy()
        end)
    end)

    describe("read-only", function()
        it("makes every cell inert", function()
            stageThree()
            local g = grid()
            g:SetReadOnly(true)
            expect(g:IsReadOnly()).truthy()
            for _, e in ipairs(g._entries) do
                expect(e.cell:GetFrame():IsMouseEnabled()).falsy()
            end
        end)

        it("applies to cells built later", function()
            local g = grid({ containers = { 0 }, readOnly = true })
            for _, e in ipairs(g._entries) do
                expect(e.cell:IsReadOnly()).truthy()
            end
        end)
    end)

    describe("a snapshot source", function()
        -- Writes a character record straight into the cache's store, which is what a real capture on
        -- that character would have left behind.
        local function cacheChar(key, which, slots, seen)
            local IC = H.SuuUI.ItemCache
            IC:Init()
            local store = H.env.SuuUIItemCache
            store.chars[key] = store.chars[key] or { class = "MAGE" }
            store.chars[key][which] = { seen = seen or 1755900000, slots = slots }
            return IC
        end

        local function cacheItem(id, info)
            H.env.SuuUIItemCache.items[id] = info
        end

        -- UNRESOLVED ITEMS, which are the ordinary state on a fresh login rather than an edge case: the
        -- cache stores ids and counts, and GetItemInfo answers nil for anything this client has not seen
        -- yet. Three separate behaviours hang off that, and each fails differently.
        -- THE BUG THIS SET EXISTS FOR, asserted end to end through the REAL capture path rather than by
        -- writing the name into the item table by hand. Searching a cached character matched zero items
        -- whatever you typed, because the container API returns no name and nothing derived one. Every
        -- other search spec here stages the name directly, which is why they all passed.
        it("can be SEARCHED after a real capture, with no item info staged", function()
            H.setBags({ [0] = { free = 6, slots = 8 } })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 12, quality = 1,
                                 iconFileID = "icon-ap",
                                 hyperlink = "|cffffffff|Hitem:22832|h[Arcane Powder]|h|r" })
            H.setBagItem(0, 2, { itemID = 21877, stackCount = 5, quality = 1,
                                 iconFileID = "icon-nw",
                                 hyperlink = "|cffffffff|Hitem:21877|h[Netherweave Cloth]|h|r" })
            H.clearItems()   -- the client has never cached either item
            local IC = H.SuuUI.ItemCache
            IC:Init()
            IC:Capture("bags")

            local g = grid({ containers = { 0 }, character = IC:CurrentKey(), which = "bags" })
            g:SetFilter("arcane")
            expect(g:CountMatches()).as("the search finds it by name").eq(1)
            g:SetFilter("cloth")
            expect(g:CountMatches()).as("and finds the other one").eq(1)
            g:SetFilter("zzz")
            expect(g:CountMatches()).as("and still says no when it means no").eq(0)
        end)

        -- OPEN QUESTION, deliberately left undecided rather than quietly resolved. The specs above pin
        -- what the code does TODAY; this names the invariant nobody has agreed to yet.
        --
        -- The concept draws unresolved items as `?` cells, and its premise is an ID-ONLY cache: "an
        -- ID-only cache renders a wall of blank cells the first time you open an alt on a fresh login".
        -- That premise does not hold on this client. GetContainerItemInfo returns the icon, quality and
        -- link straight from the CONTAINER rather than from the item cache, so a captured item always
        -- has its art -- and now its name too, parsed from the link -- which means `pending` requires a
        -- record with no link and no icon at all. Confirmed in game: no `?` cell ever appeared, on a
        -- cold client, immediately after a restart.
        --
        -- So the options are: keep IsPending as a defensive path (a hand-edited or truncated record
        -- renders honestly instead of as a blank cell, and it costs one field), or delete it under
        -- TESTING.md's "if the code is genuinely unreachable, delete it". Deleting also removes the one
        -- thing that would make a future partial-capture bug visible rather than silent, which is the
        -- argument for keeping it. Not decided; raised with Domenik 2026-08-25 and parked.
        xit("decides whether a ? cell is reachable on this client at all", function()
            -- Whichever way this goes, the assertion belongs here: either a constructed case that
            -- genuinely produces a pending cell in production, or the absence of IsPending entirely.
        end)

        -- FREE SLOTS IN A SNAPSHOT, which the grid could not show while the cache stored only occupied
        -- slots. Reported in game: an alt's bank rendered as a tight block of items with nowhere visibly
        -- left to put anything.
        it("renders a cached container at its stored capacity", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } })
            local store = H.env.SuuUIItemCache
            store.chars["Thalira-Thunderstrike"].bags.sizes = { [0] = 16 }
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local used, free, total = g:GetCounts()
            expect(total).as("the whole bag, not just what is in it").eq(16)
            expect(used).eq(1)
            expect(free).eq(15)
            expect(g:HasCapacity()).truthy()
        end)

        it("shows an EMPTY cached bag at full size", function()
            -- The case the sparse slot table cannot express: a bag holding nothing has no slot entries at
            -- all, so without the stored size it renders as absent.
            cacheChar("Thalira-Thunderstrike", "bags", {})
            local store = H.env.SuuUIItemCache
            store.chars["Thalira-Thunderstrike"].bags.sizes = { [0] = 16 }
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local _, free, total = g:GetCounts()
            expect(total).eq(16)
            expect(free).eq(16)
        end)

        -- A RECORD WITHOUT SIZES MUST NOT PRETEND. It renders up to its highest occupied index, so its
        -- empty middle slots are UNKNOWN rather than free -- and reporting them as free would invent a
        -- number, which is precisely what the old footer wording existed to avoid.
        it("falls back to the highest occupied slot for a record with no sizes", function()
            cacheChar("Thalira-Thunderstrike", "bags",
                      { [0] = { [1] = { 22832, 1 }, [5] = { 21877, 1 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local used, _, total = g:GetCounts()
            expect(total).as("up to the last thing it knows about").eq(5)
            expect(used).eq(2)
            expect(g:HasCapacity()).as("and it says it cannot answer for capacity").falsy()
        end)

        it("reports capacity as known while live", function()
            H.setBags({ [0] = { free = 4, slots = 8 } })
            local g = grid({ containers = { 0 } })
            expect(g:HasCapacity()).as("the client answers for your own bags").truthy()
        end)

        it("marks a cached item pending when the client cannot name it", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 12 } } })
            -- Deliberately NOT cacheItem'd: no entry in the shared item table at all.
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local cell = g._entries[1].cell
            expect(cell:IsPending()).as("drawn as the concept's ? cell").truthy()
        end)

        it("does NOT mark an item pending merely for having no icon", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 12 } } })
            -- A known item with a name but no icon is resolved, just thin. Inferring pending from a
            -- missing icon would put a `?` on it and claim the client knows nothing about it.
            cacheItem(22832, { name = "Arcane Powder", q = 1 })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            expect(g._entries[1].cell:IsPending()).falsy()
        end)

        -- THE ORDERING RULE THE CONCEPT STATES: unresolved items "sort to the end and slide into place
        -- rather than reshuffling the grid". Without it an unnamed item sorts on an empty name, which
        -- under name order is the FRONT -- so resolving it makes it jump the length of the grid and
        -- shove everything else along.
        it("sorts unresolved items to the end of the occupied run", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = {
                [1] = { 111, 1 },   -- unresolved
                [2] = { 222, 1 },   -- a grey: the LOWEST quality, so it loses to everything but pending
            } })
            cacheItem(222, { name = "Broken Fang", q = 0, icon = "i" })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            g:SetSortMode("quality")
            g:Sort()
            local first, second = g._entries[1].cell, g._entries[2].cell
            expect(first:IsPending()).as("the resolved grey comes first").falsy()
            expect(second:IsPending()).as("the unresolved item is parked at the end").truthy()
        end)

        it("keeps pending items ahead of empty slots", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [2] = { 111, 1 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            g:SetSortMode("quality")
            g:Sort()
            -- A pending cell is still an ITEM. Past the free-slot tail it would read as one stranded
            -- beyond the end of the bag.
            expect(g._entries[1].cell:IsPending()).as("before the empties, not after").truthy()
        end)

        -- THE FILL-IN. Without this a cached alt keeps its `?` cells until the window is closed and
        -- reopened -- and "reopen it" should never be how a player fixes anything.
        it("resolves its cells when the cache announces new item info", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 12 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            expect(g._entries[1].cell:IsPending()).as("unresolved to begin with").truthy()
            -- What the client answering GET_ITEM_INFO_RECEIVED leaves behind, plus the announcement
            -- the cache coalesces onto it.
            cacheItem(22832, { name = "Arcane Powder", q = 1, icon = "icon-ap" })
            H.SuuUI.Events:Emit("SUUUI_ITEMS_RESOLVED")
            expect(g._entries[1].cell:IsPending()).as("filled in, no reopen needed").falsy()
            expect(g._entries[1].cell:GetItem().itemName).eq("Arcane Powder")
        end)

        it("ignores the announcement while live", function()
            H.setBags({ [0] = { free = 4, slots = 8 } })
            H.setBagItem(0, 1, { itemID = 22832, stackCount = 12 })
            local g = grid({ containers = { 0 } })
            local shown = g._entries[1].cell:GetItem()
            expect(shown and shown.itemID).as("staged item is on screen").eq(22832)

            -- Staged SILENTLY, so nothing but a re-read could pick it up. A live cell reads the client
            -- directly and the client knows what is in your own bags by definition, so this
            -- announcement is not news to a live grid -- and acting on it would re-read and RE-SORT
            -- the player's bags because of an item resolution somewhere else entirely.
            --
            -- Asserted this way because the obvious version proved nothing: a re-sort does not change
            -- the sort MODE, so comparing GetSortMode across the emit passed whether the guard was
            -- there or not. Mutation testing caught that, not review.
            H.setBagItem(0, 1, { itemID = 21877, stackCount = 5 }, { silent = true })
            H.SuuUI.Events:Emit("SUUUI_ITEMS_RESOLVED")
            local after = g._entries[1].cell:GetItem()
            expect(after and after.itemID).as("no re-read happened").eq(22832)
        end)

        it("reads the slot COUNT from the cache, not from the live client", function()
            -- THE TRAP THIS EXISTS FOR. Asking the client how many slots bag 3 has answers for whoever
            -- is logged in, so an alt's 20-slot bag rendered against your own 16 would silently drop
            -- four items -- with nothing on screen to say anything was missing.
            H.setBags({ [0] = { free = 0, slots = 4 } })
            cacheChar("Thalira-Thunderstrike", "bags", {
                [0] = { [1] = { 111, 1 }, [2] = { 222, 1 }, [7] = { 333, 1 } },
            })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            -- Seven, from the highest cached index -- not four, which is what this character has.
            expect(#g._entries).as("the alt's own slot count").eq(7)
        end)

        it("fills a cell from the account-wide item table", function()
            cacheItem(22832, { icon = 134129, q = 3, link = "|Hitem:22832|h[Arcane]|h",
                               name = "Arcane Powder" })
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 12 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local c = g._entries[1].cell
            expect(c._iconComp:GetIcon()).as("icon from the shared item table").eq(134129)
            expect(c._countText:GetText()).as("count from the slot record").eq("12")
            expect(c._iconComp._borderColor)
                .as("quality edge, painted by the same code as a live cell")
                .eq(H.SuuUI.Game:ItemQualityColor(3))
        end)

        it("renders a slot whose item is not resolved yet, rather than dropping it", function()
            -- GetItemInfo answers nil until GET_ITEM_INFO_RECEIVED fires, so an id with no info is a
            -- real state on a fresh login. The concept draws it as a `?` cell; what must not happen is
            -- the slot vanishing, which would make the grid reflow when the name arrives.
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 99999, 2 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local c = g._entries[1].cell
            expect(c:GetItem()).as("the slot is occupied").truthy()
            expect(c:GetItem().itemID).eq(99999)
            expect(c:GetItem().hyperlink).as("but nothing is known about it yet").eq(nil)
        end)

        it("builds snapshot-kind cells, which cannot reach the client", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            local c = g._entries[1].cell
            expect(c:GetFrame()._template).as("no container template").eq(nil)
            H.resetUsedContainerItems()
            H.click(c, "RightButton")
            expect(#H.getUsedContainerItems())
                .as("an alt's cached cell must never act on YOUR bags").eq(0)
        end)

        it("reports when the container was last read", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } }, 1755730000)
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            expect(g:SeenAt()).eq(1755730000)
        end)

        it("has no timestamp while live, because it IS the current reading", function()
            H.setBags({ [0] = { free = 4, slots = 8 } })
            local g = grid({ containers = { 0 } })
            expect(g:IsSnapshot()).falsy()
            expect(g:SeenAt()).as("a freshness claim would be meaningless here").eq(nil)
        end)

        it("REBUILDS its cells when the character changes, never re-points them", function()
            H.setBags({ [0] = { free = 4, slots = 8 } })
            local g = grid({ containers = { 0 } })
            local liveCell = g._entries[1].cell
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } })
            expect(g:SetCharacter("Thalira-Thunderstrike", "bags")).truthy()
            local snapCell = g._entries[1].cell
            -- The kind is fixed at construction, so re-pointing would leave an alt's slot wired to a
            -- template handler that acts on the logged-in character.
            expect(snapCell == liveCell).as("a different cell object entirely").falsy()
            expect(snapCell:GetFrame()._template).as("and the new one is template-free").eq(nil)
        end)

        it("goes back to live when the character is cleared", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } })
            H.setBags({ [0] = { free = 4, slots = 8 } })
            local g = grid({ containers = { 0 }, character = "Thalira-Thunderstrike",
                             which = "bags" })
            expect(g:IsSnapshot()).truthy()
            g:SetCharacter(nil)
            expect(g:IsSnapshot()).falsy()
            expect(g._entries[1].cell:GetFrame()._template)
                .as("a live cell carries the container template again").truthy()
        end)

        it("drops a repeated SetCharacter rather than rebuilding for nothing", function()
            cacheChar("Thalira-Thunderstrike", "bags", { [0] = { [1] = { 22832, 1 } } })
            local g = grid({ containers = { 0 } })
            expect(g:SetCharacter("Thalira-Thunderstrike", "bags")).truthy()
            expect(g:SetCharacter("Thalira-Thunderstrike", "bags"))
                .as("a rebuild destroys every cell, so an unchanged call must not").falsy()
        end)
    end)

    describe("teardown", function()
        it("destroys its cells and unregisters its events", function()
            local g = grid()
            local cell = g._entries[1].cell
            g:Destroy()
            expect(g:IsShown()).falsy()
            expect(cell:IsShown()).as("cells went with it").falsy()
        end)
    end)
end)
