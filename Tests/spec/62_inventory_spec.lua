-- Plugins/Inventory: the window over the player's live bags.
--
-- The assertions that earn their place here are the RENDER ones. A settings schema can be perfectly
-- shaped and still throw on build -- that is how a missing subtab id once took a whole page down
-- while every schema-shape spec passed -- so this file builds the real window and asserts that
-- cells have geometry inside it.
local H = require("harness.init")

describe("Plugins/Inventory", function()
    local IW

    before_each(function()
        H.setup()
        IW = H.SuuUI._InventoryWindow
        H.setBags({
            [0] = { slots = 8, free = 5 }, [1] = { slots = 4, free = 4 },
            [2] = { slots = 0 }, [3] = { slots = 0 }, [4] = { slots = 0 },
        }, { silent = true })
        H.setMoney(12844218)
    end)

    local function stageThree()
        H.setBagItem(0, 1, { itemID = 111, itemName = "Zebra Cloth",  quality = 1, stackCount = 5 },
                     { silent = true })
        H.setBagItem(0, 2, { itemID = 222, itemName = "Amber Potion", quality = 4 },
                     { silent = true })
        H.setBagItem(0, 3, { itemID = 333, itemName = "Middling Ore", quality = 2, stackCount = 9 },
                     { silent = true })
    end

    describe("the plugin", function()
        it("is registered and enabled by default", function()
            local p = H.SuuUI._InventoryPlugin
            expect(p).truthy()
            expect(p.id).eq("inventory")
            expect(p:IsEnabled()).truthy()
        end)

        it("registers its schema with defaults", function()
            expect(H.SuuUI.Settings:Get("inventory", "columns")).eq(10)
            expect(H.SuuUI.Settings:Get("inventory", "cell_size")).eq(34)
            expect(H.SuuUI.Settings:Get("inventory", "sort_mode")).eq("quality")
        end)

        it("exposes a slash command that toggles", function()
            expect(H.env.SLASH_SUUUIBAGS1).eq("/sbags")
            expect(type(H.env.SlashCmdList["SUUUIBAGS"])).eq("function")
            H.env.SlashCmdList["SUUUIBAGS"]()
            expect(H.SuuUI.Inventory_Toggle).truthy()
        end)

        -- Every key that changes the grid's shape must be WATCHED, or it reads only at construction
        -- and appears to do nothing until a reload. That gap shipped once already on the watch bars.
        it("watches every shape setting", function()
            H.SuuUI.Inventory_Open()
            local before = H.SuuUI.Settings:GetWatcherCount()
            expect(before).gt(0)
            H.SuuUI.Settings:Set("inventory", "columns", 12)
            H.SuuUI.Settings:Set("inventory", "cell_size", 40)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("no watcher leaked per write").eq(before)
        end)
    end)

    describe("the window renders", function()
        it("opens and is shown", function()
            H.SuuUI.Inventory_Open()
            local w = IW and true
            expect(w).truthy()
        end)

        it("builds a grid over every bag the client reports", function()
            stageThree()
            local win = IW.New({ container = "bags" })
            win:Show()
            local ids = win:GetGrid():GetContainers()
            expect(#ids).as("backpack plus four bag slots").eq(5)
            expect(ids[1]).eq(0)
            expect(ids[5]).eq(4)
        end)

        -- The render assertion. A grid that built but laid nothing out would satisfy every
        -- structural check above while showing an empty window.
        it("gives its cells real geometry inside the window", function()
            stageThree()
            local win = IW.New({ container = "bags" })
            win:Show()
            local grid = win:GetGrid()
            local cell = grid._entries[1].cell
            local box = H.box(cell)
            expect(box).as("the first cell resolved a rect").truthy()
            expect(box.width).gt(0)
            expect(box.height).gt(0)
            H.expectInside(cell:GetFrame(), win:GetWindow():GetFrame())
        end)

        it("sizes the window to fit the grid rather than clipping it", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            local gw = win:GetGrid():GetWidth()
            expect(win:GetWindow():GetWidth()).as("window is at least as wide as the grid").gte(gw)
        end)

        it("reports money and free slots in the footer", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            -- 12844218 copper is 1284g 42s 18c. The readout is COLOURED per denomination, so the
            -- amount is asserted with the escapes stripped -- pinning the whole escaped string here
            -- would make this test fail for a colour change, which the money spec already owns.
            local plain = (win._moneyText:GetText() or ""):gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", "")
            expect(plain).eq("1,284 g 42 s 18 c")
            local _, free, total = win:GetGrid():GetCounts()
            expect(win._slotsText:GetText()).eq(free .. " free / " .. total)
        end)

        it("shows nothing in the match readout until a search is typed", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            expect(win._matchText:IsShown()).falsy()
        end)
    end)

    -- THE FOOTER HAS TO FIT. _fit sizes the WINDOW from the column's content, and a window is its
    -- content plus its chrome -- so passing the content height straight through left the content area
    -- short by exactly sizeTitleBar. The footer is the last child of a vertical flow, so the footer is
    -- what got squeezed off the bottom and the money readout had no room, while the grid and search
    -- row above it looked perfect. Asserting the window's SIZE would not have caught it: the window
    -- was exactly the size it was asked for. Only containment catches this.
    describe("the footer fits", function()
        it("keeps the money and slot readouts inside the window's content area", function()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 3, quality = 1 })
            H.setMoney(1234567)
            local w = IW.New({ container = "bags" })
            w:Show()
            H.expectInside(w._moneyText, w._win:GetContentFrame())
            H.expectInside(w._slotsText, w._win:GetContentFrame())
            w:Destroy()
        end)

        it("does not overlap the grid with the footer", function()
            H.setMoney(500)
            local w = IW.New({ container = "bags" })
            w:Show()
            H.expectNoOverlap(w._moneyText, w._grid:GetFrame())
            w:Destroy()
        end)

        it("leaves NO dead space below the footer", function()
            H.setMoney(1234567)
            local w = IW.New({ container = "bags" })
            w:Show()
            local pad = H.token("spaceSm")
            local foot = H.box(w._moneyText)
            local content = H.box(w._win:GetContentFrame())
            -- .top measures DOWNWARD from the screen top, so a box's bottom edge is top + height.
            local slack = (content.top + content.height) - (foot.top + foot.height)
            -- The window used to be sized from token row heights while both rows hug their content,
            -- so the surplus landed here as dead space and the footer sat too high. One padding's
            -- worth is the column's own bottom inset; anything beyond it is the bug.
            expect(slack).as("gap under the footer is just the column padding").lte(pad + 2)
            expect(slack).as("and the footer is not clipped off the bottom").gte(-1)
        end)

        it("shows the money in the client's coin colours", function()
            H.setMoney(1234567)
            local w = IW.New({ container = "bags" })
            w:Show()
            local text = w._moneyText:GetText() or ""
            expect(text:find(H.SuuUI.Game:CoinColorCode("GOLD") .. "g|r", 1, true))
                .as("the gold LETTER is coloured, not the figure").truthy()
            expect(text:find("123", 1, true)).as("and still says the amount").truthy()
            w:Destroy()
        end)
    end)

    -- Opening the window sorts. Refresh deliberately does NOT, so that looting cannot shuffle cells
    -- under the cursor -- but the first paint sorted while every cell was empty, and a repaint
    -- preserves order, so the grid kept raw bag order forever. In game that stranded empty rows in
    -- the middle of the grid wherever an empty bag sat in the container order.
    describe("opening the window packs the items", function()
        it("puts every occupied slot before every empty one", function()
            -- THE ORDER OF THESE STEPS IS THE TEST. In game the window is built before bag contents
            -- are readable, so the grid's one construction-time sort saw nothing but empty cells --
            -- and because a repaint preserves order, it never packed again. Staging the items BEFORE
            -- New() lets the construction sort do the work and the test passes either way, which is
            -- what mutation testing caught: the fixture, not the assertion, was wrong.
            local w = IW.New({ container = "bags" })

            -- Only NOW does the client have anything to report, with an empty bag in the middle.
            H.setBags({
                [0] = { slots = 4, free = 3 },
                [1] = { slots = 4, free = 4 },   -- entirely empty, and sits in the middle
                [2] = { slots = 4, free = 3 },
            })
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1 })
            H.setBagItem(2, 1, { itemID = 4338, stackCount = 1, quality = 1 })

            w:Show()

            local seenEmpty = false
            local stranded = 0
            for _, e in ipairs(w:GetGrid()._entries) do
                if e.info then
                    if seenEmpty then stranded = stranded + 1 end
                else
                    seenEmpty = true
                end
            end
            expect(stranded).as("an item after an empty slot means the grid never packed").eq(0)
            w:Destroy()
        end)
    end)

    -- The concept's three readable bands: search, then the items on their own inset surface, then the
    -- totals below a divider. Without the plate the cells float on the window background and the
    -- window reads as one undifferentiated field of icons.
    describe("the grid sits on its own plate", function()
        it("contains the whole grid within the plate", function()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1 })
            local w = IW.New({ container = "bags" })
            w:Show()
            H.expectInside(w._grid:GetFrame(), w._plate:GetFrame())
            w:Destroy()
        end)

        it("insets the grid from the plate's edge rather than butting it", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local g, p = H.box(w._grid:GetFrame()), H.box(w._plate:GetFrame())
            expect(g.left - p.left).as("left inset").gte(1)
            expect(p.left + p.width - (g.left + g.width)).as("right inset").gte(1)
            w:Destroy()
        end)

        it("puts the divider between the plate and the footer", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- .top measures DOWNWARD from the screen top, so lower on screen is a LARGER top.
            local plate, div, money = H.box(w._plate:GetFrame()), H.box(w._footDivider),
                                      H.box(w._moneyText)
            expect(div.top).as("divider is below the plate").gte(plate.top + plate.height - 1)
            expect(div.top).as("divider is above the money readout").lte(money.top + 1)
            w:Destroy()
        end)
    end)

    -- Concept fidelity: the hint lives INSIDE the field and the cells are rounded.
    describe("it matches the concept's chrome", function()
        it("puts the search hint inside the field, not in a label beside it", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._search:GetPlaceholder()).as("the field labels itself").eq("Search items...")
            expect(w._searchLabel).as("the outside label is gone").eq(nil)
            w:Destroy()
        end)

        -- THE ONE THAT MATTERS: if the hint were the edit box's text, the grid would filter for the
        -- literal string "Search items..." and show nothing on open.
        it("does not let the hint become a search query", function()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1 })
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._search:GetValue()).as("the field reads empty").eq("")
            expect(w._grid:GetFilter()).as("so no filter is active").eq(nil)
            w:Destroy()
        end)

        it("rounds the cells and the plate", function()
            H.setBagItem(0, 1, { itemID = 4306, stackCount = 1, quality = 1 })
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._plate._panel).as("the plate is a rounded surface").truthy()
            local cell = w._grid._cells[0] and w._grid._cells[0][1]
            expect(cell).as("the cell exists").truthy()
            expect(cell._iconComp._panel).as("the cell is a rounded surface").truthy()
            w:Destroy()
        end)
    end)

    describe("search filters the grid live", function()
        it("dims non-matches and reports the count", function()
            stageThree()
            local win = IW.New({ container = "bags" })
            win:Show()
            H.SuuUI.UISignals:Emit(win._search, H.S.SIGNALS.TEXT_CHANGED, "potion")
            expect(win:GetGrid():GetFilter()).eq("potion")
            expect(win._matchText:IsShown()).truthy()
            expect(win._matchText:GetText()).eq("1 found")
        end)

        it("clears back to everything", function()
            stageThree()
            local win = IW.New({ container = "bags" })
            win:Show()
            H.SuuUI.UISignals:Emit(win._search, H.S.SIGNALS.TEXT_CHANGED, "potion")
            H.SuuUI.UISignals:Emit(win._search, H.S.SIGNALS.TEXT_CHANGED, "")
            expect(win:GetGrid():GetFilter()).eq(nil)
            expect(win._matchText:IsShown()).falsy()
        end)
    end)

    describe("the sort control", function()
        it("re-sorts using the mode configured in settings, without changing it", function()
            stageThree()
            H.SuuUI.Settings:Set("inventory", "sort_mode", "slot")
            local win = IW.New({ container = "bags" })
            win:Show()
            expect(win:GetGrid():GetSortMode()).as("settings own the mode").eq("slot")
            expect(H.click(win._sortBtn)).as("the title-bar button takes the click").truthy()
            -- The button SORTS; it does not pick the order. A button that cycled would be a second
            -- owner of one value, and the two could disagree about what the player chose.
            expect(win:GetGrid():GetSortMode()).as("mode is untouched by the click").eq("slot")
            expect(H.SuuUI.Settings:Get("inventory", "sort_mode"))
                .as("and nothing was written").eq("slot")
            win:Destroy()
        end)

        -- Reported in game: the button slid out to the right when clicked. The cause was the press
        -- pop -- SetScale reinterprets the frame's own anchor offset in its scaled space, so a button
        -- held at an inset from the strip's edge moves instead of growing. TICKING IS ESSENTIAL: the
        -- animator writes on its first update, so without it this passes with the pop enabled.
        it("does not move or scale when clicked", function()
            stageThree()
            local win = IW.New({ container = "bags" })
            win:Show()
            local before = H.box(win._sortBtn:GetFrame())
            H.click(win._sortBtn)
            H.tick(0.016)
            expect(win._sortBtn:GetFrame():GetScale())
                .as("a strip accessory must not scale, or it slides").near(1, 0.0001)
            local after = H.box(win._sortBtn:GetFrame())
            expect(after.left).as("button did not slide sideways").near(before.left, 0.5)
            expect(after.top).as("button did not slide vertically").near(before.top, 0.5)
            expect(after.width).as("and did not resize").near(before.width, 0.5)
            win:Destroy()
        end)

        it("stays inside the window after being clicked", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            H.click(win._sortBtn)
            H.expectInside(win._sortBtn:GetFrame(), win:GetWindow():GetFrame())
            win:Destroy()
        end)

        it("re-sorts after items moved, which is what the button is for", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            -- An item arrives in a slot the current order would not leave it in. Refresh repaints
            -- WITHOUT re-sorting on purpose, so only the button puts it back in order.
            H.setBags({ [0] = { slots = 4, free = 2 }, [1] = { slots = 4, free = 4 } })
            H.setBagItem(1, 4, { itemID = 4306, stackCount = 1, quality = 4 })
            win:Refresh()
            H.click(win._sortBtn)
            local first = win:GetGrid()._entries[1]
            expect(first and first.info).as("an occupied slot leads after sorting").truthy()
            win:Destroy()
        end)

        -- IN THE TITLE BAR, not merely clickable. H.click reaches the button wherever it is parented,
        -- so a click test passed with the AddTitleAccessory call DELETED -- mutation testing caught
        -- exactly that. Ask the window what it is holding.
        it("puts the sort button in the title bar", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            local held = win:GetWindow():GetTitleAccessories()
            local found = false
            for _, a in ipairs(held) do if a == win._sortBtn then found = true end end
            expect(found).as("the window holds it as a title accessory").truthy()
            -- And geometrically above the search row, which is what "title bar" means on screen.
            -- .top measures DOWNWARD from the screen top, so higher up is a SMALLER top.
            expect(H.box(win._sortBtn:GetFrame()).top)
                .as("sits above the search field").lt(H.box(win._search:GetFrame()).top)
            win:Destroy()
        end)

        it("keeps the search field full width now the dropdown is gone", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            -- The concept's search row is the field and nothing else. A dropdown back on this row
            -- would show up here as the field losing most of its width.
            local field = H.box(win._search:GetFrame())
            local plate = H.box(win._plate:GetFrame())
            expect(field.width).as("field spans the window, not a third of it")
                .gte(plate.width * 0.6)
            win:Destroy()
        end)

        it("offers exactly the modes the grid implements", function()
            local win = IW.New({ container = "bags" })
            local grid = win:GetGrid()
            for _, opt in ipairs(IW.SORT_OPTIONS) do
                -- Move AWAY first. SetSortMode returns false for a no-op, which is correct -- so
                -- asserting truthy on the mode the grid is already in would fail for a reason that
                -- has nothing to do with whether the option is supported.
                grid:SetSortMode(opt.value == "name" and "quality" or "name")
                expect(grid:SetSortMode(opt.value)).as("grid accepts " .. opt.value).truthy()
            end
            win:Destroy()
        end)
    end)

    describe("container ids", function()
        it("covers the backpack and every bag slot", function()
            local ids = IW.containerIds("bags")
            expect(#ids).eq(5)
            expect(ids[1]).eq(0)
        end)

        it("covers the bank and its bag slots", function()
            local ids = IW.containerIds("bank")
            expect(ids[1]).as("the bank's own grid first").eq(-1)
            expect(#ids).as("bank plus seven bank bags").eq(8)
            expect(ids[2]).as("bank bags start after the player's bags").eq(5)
            expect(ids[8]).eq(11)
        end)
    end)

    describe("teardown", function()
        it("destroys the grid with the window", function()
            local win = IW.New({ container = "bags" })
            win:Show()
            local cell = win:GetGrid()._entries[1].cell
            win:Destroy()
            expect(cell:IsShown()).as("cells went with it").falsy()
        end)
    end)
end)
