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
