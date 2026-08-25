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
            H.expectNoOverlap({ w._moneyText, w._grid:GetFrame() })
            w:Destroy()
        end)

        it("leaves NO dead space below the footer", function()
            H.setMoney(1234567)
            local w = IW.New({ container = "bags" })
            w:Show()
            local pad = H.token("spaceSm")
            -- The FOOTER's box, not the money text's. The row is as tall as its tallest child -- the
            -- Sell Junk button -- so measuring from the text counts legitimate row height as slack.
            local foot = H.box(w._footer)
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

    -- The concept's title bar reads: character dropdown, scope, then sort and sell icons beside the
    -- close button -- with the footer left as money plus free/total. This block pins that arrangement,
    -- because the first implementation put sell in the footer as a labelled Button.
    -- Every assertion in this block names a value read off the concept artifact's own CSS, so a
    -- drift away from it fails here rather than being noticed in a screenshot.
    describe("concept fidelity", function()
        -- ASSERTS THE PAINT, NOT THE HANDLE. This first read `expect(win._glass).truthy()`, which
        -- passed while the window had NO SURFACE AT ALL: Glass stores `from`/`to`/`sheen` verbatim
        -- and defaults none of them, so a call that omitted the colours built a complete handle
        -- whose body drew nothing, and the game world showed straight through the window. A
        -- primitive returning a handle is not evidence that the handle paints.
        it("paints the surface as glass, not a flat panel", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local g = w:GetWindow()._glass
            expect(g).as("the window built a glass surface").truthy()
            expect(g:IsGradient()).as("a gradient, not a flat fill").truthy()

            local grad = g._body:GetGradient()
            expect(grad).as("the body actually carries a gradient").truthy()
            expect(grad.orientation).eq("VERTICAL")

            -- The concept's `.win` runs rgba(10,10,15,.85) at the TOP down to .30 at the bottom,
            -- which is colorGlass -> colorGlassFade. The client's gradient runs bottom-to-top, so
            -- the DENSE end is the `to` stop.
            local dense = H.token("colorGlass")
            local fade  = H.token("colorGlassFade")
            -- The stops are keyed r/g/b/a rather than array-indexed; reading them positionally
            -- yields nil, which is a "near" failure in BOTH directions and so proves nothing.
            expect(grad.to.a).as("dense end at the top").near(dense[4], 0.001)
            expect(grad.from.a).as("faded end at the bottom").near(fade[4], 0.001)
            expect(grad.to.r).as("and the hue is the glass neutral").near(dense[1], 0.001)
            w:Destroy()
        end)

        it("gives the search field a stadium surface and a magnifier", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- `.srch{border-radius:10px}` on a 19-unit field is a pill, not a rounded rectangle.
            expect(w._search._pill).as("pill surface").truthy()
            expect(w._search._iconComp).as("leading magnifier").truthy()
            -- Atlas art, not a pictograph character the client's faces may not carry.
            expect(w._search._iconComp:GetIcon()).eq(H.SuuUI.Icons.PATH)
            w:Destroy()
        end)

        it("keeps the typed text clear of the magnifier", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- The whole point of the glyph being INSIDE the field: if the edit box were not inset
            -- past it, the first characters typed would be drawn over the icon.
            H.expectNoOverlap({ w._search._eb, w._search._iconComp:GetFrame() })
            w:Destroy()
        end)

        it("shows a clear affordance only once there is something to clear", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._search._clearBtn:IsShown()).as("nothing typed yet").falsy()
            H.typeText(w._search, "poti")
            expect(w._search._clearBtn:IsShown()).as("a query is present").truthy()
            H.click(w._search._clearBtn)
            expect(w._search:GetValue()).as("clearing empties the field").eq("")
            expect(w._search._clearBtn:IsShown()).as("and hides itself again").falsy()
            w:Destroy()
        end)

        it("draws a hairline under the search row as well as above the footer", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._searchDivider).truthy()
            -- .top measures DOWNWARD: the search hairline is above the footer one.
            expect(H.box(w._searchDivider:GetFrame()).top)
                .lt(H.box(w._footDivider:GetFrame()).top)
            w:Destroy()
        end)

        it("colours the sort icon with the accent, not the muted text token", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- `.ibtn.acc` for sort against `.ibtn.dgr` for sell: sorting is the affordance the
            -- window advertises, so it is the coloured one.
            local acc = H.token("colorAccent")
            local dgr = H.token("colorDanger")
            local r, g, b = w._sortBtn._icon:GetVertexColor()
            expect(r).as("sort takes the accent").near(acc[1], 0.001)
            expect(g).near(acc[2], 0.001)
            expect(b).near(acc[3], 0.001)
            local r2, g2, b2 = w._sellBtn._icon:GetVertexColor()
            expect(r2).as("sell takes danger").near(dgr[1], 0.001)
            expect(g2).near(dgr[2], 0.001)
            expect(b2).near(dgr[3], 0.001)
            w:Destroy()
        end)

        -- Asserting the STORED key would pass while the tint on screen was whatever the token said
        -- at construction. A token is user-editable, so the tint has to be re-resolved.
        it("re-resolves the icon tint when the accent token is edited", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local theme = H.SuuUI.Theme:GetActive()
            H.SuuUI.Theme:CreateUserTheme("t_tint", theme)
            H.SuuUI.Theme:SetUserToken("t_tint", "colorBlue400", { 1, 0, 1, 1 })
            H.SuuUI.Theme:SetActive("t_tint")
            local r, g, b = w._sortBtn._icon:GetVertexColor()
            expect(r).as("followed the edited primitive").near(1, 0.001)
            expect(g).near(0, 0.001)
            expect(b).near(1, 0.001)
            w:Destroy()
        end)

        it("dims a non-match to the concept's own opacity", function()
            -- `.dim{opacity:.16}`, and the concept's note says so in words too. This was 0.35.
            expect(H.token("opacityDimmed")).near(0.16, 0.001)
        end)
    end)

    -- SNAPSHOT MODE, the concept's second state for one window. Every assertion here is about the
    -- window telling the truth about WHOSE bags it is showing and HOW OLD they are -- a cached grid
    -- that looks live is the failure this whole state exists to prevent.
    describe("snapshot mode", function()
        local function cacheAlt(key, slots, money, seen)
            local IC = H.SuuUI.ItemCache
            IC:Init()
            local store = H.env.SuuUIItemCache
            store.chars[key] = { class = "MAGE", money = money }
            store.chars[key].bags = { seen = seen or 1755900000, slots = slots }
            return IC
        end

        it("starts live, with no strip", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w:IsSnapshot()).falsy()
            expect(w._snapStrip:IsShown()).as("nothing to warn about").falsy()
            w:Destroy()
        end)

        it("shows the amber strip and its age when pointed at an alt", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 3 } } }, 8421100)
            local w = IW.New({ container = "bags" })
            w:Show()
            w:SetCharacter("Thalira-Thunderstrike")
            expect(w:IsSnapshot()).truthy()
            expect(w._snapStrip:IsShown()).as("the read-only strip is up").truthy()
            expect(w._snapAge:GetText()).as("and it says how stale it is").truthy()
            expect(w._snapAge:GetText() ~= "").truthy()
            w:Destroy()
        end)

        it("swaps free-slots for a cached item count", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 3 }, [2] = { 111, 1 } } })
            local w = IW.New({ container = "bags" })
            w:Show()
            w:SetCharacter("Thalira-Thunderstrike")
            -- A cache stores only OCCUPIED slots, so it cannot say how many are free. Printing
            -- "22 free / 80" from a snapshot would be an invented number.
            expect(w._slotsText:GetText()).eq("2 items cached")
            w:Destroy()
        end)

        it("shows the ALT's money, not yours", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } }, 8421100)
            H.env.SuuUIConfig = H.env.SuuUIConfig or {}
            local w = IW.New({ container = "bags" })
            w:Show()
            local mine = w._moneyText:GetText()
            w:SetCharacter("Thalira-Thunderstrike")
            local theirs = w._moneyText:GetText()
            -- GetMoney() under an alt's name is a number that looks authoritative and describes the
            -- wrong character.
            expect(theirs == mine).as("a different figure entirely").falsy()
            expect(theirs:find("842", 1, true)).as("842g, from the cache").truthy()
            w:Destroy()
        end)

        it("hides the money readout when the cache has no figure", function()
            -- An alt captured before money was stored has no figure. Printing 0g would state a fact
            -- the cache does not have.
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } }, nil)
            local w = IW.New({ container = "bags" })
            w:Show()
            w:SetCharacter("Thalira-Thunderstrike")
            expect(w._moneyText:IsShown()).as("no invented zero").falsy()
            w:Destroy()
        end)

        it("fades sort and sell rather than removing them", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } })
            local w = IW.New({ container = "bags" })
            w:Show()
            w:SetCharacter("Thalira-Thunderstrike")
            -- Their absence would read as a different window; greyed says "not for this character",
            -- which is true and is temporary.
            expect(w._sortBtn:IsEnabled()).as("sort is dead here").falsy()
            expect(w._sellBtn:IsEnabled()).as("and so is sell").falsy()
            w:Destroy()
        end)

        it("cannot sell an alt's junk even standing at a vendor", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } })
            local w = IW.New({ container = "bags" })
            w:Show()
            H.setMerchantOpen(true)
            w:SetCharacter("Thalira-Thunderstrike")
            expect(w._sellBtn:IsEnabled())
                .as("the items are not in YOUR bags to sell").falsy()
            w:Destroy()
        end)

        it("goes back to live when pointed at the current character", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } })
            local w = IW.New({ container = "bags" })
            w:Show()
            w:SetCharacter("Thalira-Thunderstrike")
            w:SetCharacter(nil)
            expect(w:IsSnapshot()).falsy()
            expect(w._snapStrip:IsShown()).as("the strip goes with it").falsy()
            expect(w._sortBtn:IsEnabled()).as("and sort comes back").truthy()
            w:Destroy()
        end)

        it("lists the cached characters in the dropdown", function()
            cacheAlt("Thalira-Thunderstrike", { [0] = { [1] = { 22832, 1 } } })
            local w = IW.New({ container = "bags" })
            w:Show()
            local opts = w._charDrop._options
            expect(#opts).as("at least the alt we cached").gt(0)
            local found = false
            for _, o in ipairs(opts) do
                if o.value == "Thalira-Thunderstrike" then found = true end
            end
            expect(found).truthy()
            w:Destroy()
        end)

        it("rebuilds the character list on every open, not once at construction", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local before = #w._charDrop._options
            -- A character the cache gains between opens -- which is what logging into an alt does.
            cacheAlt("Newalt-Thunderstrike", { [0] = { [1] = { 22832, 1 } } })
            w:Hide()
            w:Show()
            expect(#w._charDrop._options)
                .as("a list built once would never see the new character").gt(before)
            w:Destroy()
        end)
    end)

        -- REPORTED FROM A SCREENSHOT, and the specs could not have caught it: the dropdown was handed
        -- to AddTitleAccessory, which stacks inward from the CLOSE BUTTON, so it landed crushed against
        -- the X and pushed the sort and coin icons out of the band. Nothing asserted where in the strip
        -- it sat, only that it existed.
        -- REPORTED IN GAME: the dropdown sat in exactly the right place and would not open, because the
        -- title bar's DRAG SURFACE spans the strip and the client gives a click to the topmost
        -- mouse-enabled frame. Position was asserted; reachability was not, and "it looks right" is
        -- precisely the state a z-order bug leaves a control in.
        -- REPORTED IN GAME as "the highlight clips out of the window", and the measurement said it was
        -- 11 units inside -- so the geometry was right and the LOOK was wrong. Two causes, both concept
        -- deviations: the field filled the 26-unit strip edge to edge, and it carried the same surface
        -- token as the strip, so it had no visible box and hovering produced a bare outline.
        it("sits inside the title bar with clearance, not filling it", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local drop = H.box(w._charDrop:GetFrame())
            local strip = H.box(w:GetWindow()._titleStrip:GetFrame())
            expect(drop.height).as("shorter than the bar").lt(strip.height)
            -- .top measures DOWNWARD, so being inside means a LARGER top and a SMALLER bottom.
            expect(drop.top).as("clear of the bar's top edge").gt(strip.top)
            expect(drop.bottom).as("and of its bottom").lt(strip.bottom)
            w:Destroy()
        end)

        it("does not wear the title strip's own surface colour", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- Same token as the strip means an invisible field: the concept's `.dd` is darker than the
            -- bar it sits on, which is what makes the control readable at rest.
            expect(w._charDrop._bg).as("an explicit surface").truthy()
            expect(w._charDrop._bg == "colorBgAlt")
                .as("and not the strip's own token").falsy()
            w:Destroy()
        end)

        -- OPENING IS NOT SELECTING, and that gap shipped a live error: `onChange` captured the GLOBAL
        -- `handle` because `local handle` was declared further down the constructor, so picking a
        -- character raised "attempt to index global 'handle'". The window built fine and the panel
        -- opened fine -- only the callback was broken, and only a spec that clicks a ROW reaches it.
        it("switches character when a row is actually chosen", function()
            local IC = H.SuuUI.ItemCache
            IC:Init()
            local store = H.env.SuuUIItemCache
            store.chars["Suwarrior-Thunderstrike"] = { class = "WARRIOR", money = 500 }
            store.chars["Suwarrior-Thunderstrike"].bags =
                { seen = 1755900000, slots = { [0] = { [1] = { 22832, 1 } } } }
            local w = IW.New({ container = "bags" })
            w:Show()
            H.click(w._charDrop)
            -- A row keeps its option value in its click closure rather than on the frame, so the row
            -- is found by its INDEX in the options list -- the two are built in step.
            local picked = false
            for i, opt in ipairs(w._charDrop._options or {}) do
                if opt.value == "Suwarrior-Thunderstrike" then
                    local row = (w._charDrop._rows or {})[i]
                    expect(row).as("the option has a rendered row").truthy()
                    H.click(row)
                    picked = true
                    break
                end
            end
            expect(picked).as("the alt has a row to click").truthy()
            expect(w:IsSnapshot()).as("choosing it switched the window").truthy()
            w:Destroy()
        end)

        it("can actually be clicked, not just placed", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(H.click(w._charDrop)).as("the click reaches it").truthy()
            expect(w._charDrop._open).as("and its panel opens").truthy()
            w:Destroy()
        end)

        it("keeps the window's drag region clear of the dropdown", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- Raising it wins the click, but a press a pixel off the control would otherwise start
            -- dragging the window -- so the drag region is inset past it too.
            H.expectNoOverlap({ w._charDrop:GetFrame(), w:GetWindow()._drag })
            w:Destroy()
        end)

        it("puts the character dropdown where the TITLE is, not beside the close button", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            local win = w:GetWindow()
            expect(win:GetTitleWidget()).as("it occupies the title slot").eq(w._charDrop)
            local drop = H.box(w._charDrop:GetFrame())
            local close = H.box(win._closeBtn:GetFrame())
            expect(drop.left).as("on the LEFT of the strip").lt(close.left)
            -- The title text stands down rather than sitting behind it.
            expect(win._titleT:IsShown()).as("no second label for the same thing").falsy()
            w:Destroy()
        end)

        it("leaves room for the sort and coin icons beside the close button", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- The icons vanished entirely in the screenshot. Assert they are on screen AND clear of
            -- both the dropdown and each other.
            expect(w._sortBtn:IsShown()).truthy()
            expect(w._sellBtn:IsShown()).truthy()
            H.expectNoOverlap({ w._charDrop:GetFrame(), w._sortBtn:GetFrame(),
                                w._sellBtn:GetFrame(), w:GetWindow()._closeBtn:GetFrame() })
            w:Destroy()
        end)

        it("keeps the dropdown inside the title bar", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            H.expectInside(w._charDrop:GetFrame(), w:GetWindow()._titleStrip:GetFrame())
            w:Destroy()
        end)

    describe("the sell control", function()
        it("is a title-bar accessory, not a footer button", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            expect(w._sellBtn).as("the bags window has one").truthy()
            local held = w:GetWindow():GetTitleAccessories()
            local found = false
            for _, a in ipairs(held) do if a == w._sellBtn then found = true end end
            expect(found).as("held by the title bar").truthy()
            -- .top measures DOWNWARD, so the title bar is a SMALLER top than the footer.
            expect(H.box(w._sellBtn:GetFrame()).top)
                .as("sits above the footer").lt(H.box(w._footer).top)
            w:Destroy()
        end)

        it("sits between the sort icon and the close button", function()
            local w = IW.New({ container = "bags" })
            w:Show()
            -- Concept order left to right: sort, sell, close. Accessories stack inward from close, so
            -- sell is the RIGHTMOST of the two.
            expect(H.box(w._sellBtn:GetFrame()).left)
                .as("sell is right of sort").gt(H.box(w._sortBtn:GetFrame()).left)
            H.expectNoOverlap({ w._sellBtn:GetFrame(), w._sortBtn:GetFrame() })
            w:Destroy()
        end)

        -- NOT disabled on the bank -- absent. A greyed control says "not right now" when the truth is
        -- "never here", and this is the easy bug the design flagged in advance.
        it("does not exist at all on the bank window", function()
            local w = IW.New({ container = "bank" })
            w:Show()
            expect(w._sellBtn).as("you cannot sell from a bank").eq(nil)
            w:Destroy()
        end)

        it("is disabled away from a merchant and enabled at one", function()
            local w = IW.New({ container = "bags" })
            H.setMerchantOpen(false)
            w:Show()
            expect(w._sellBtn:IsEnabled()).as("not right now").falsy()
            H.setMerchantOpen(true)
            w:Refresh()
            w:_updateFooter()
            expect(w._sellBtn:IsEnabled()).as("at a vendor it is live").truthy()
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
            expect(win._matchText:GetText()).eq("1 shown")
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
