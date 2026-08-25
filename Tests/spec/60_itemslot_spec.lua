-- Components/ItemSlot.lua: one bag slot on ContainerFrameItemButtonTemplate.
--
-- The assertions that matter most here are the ones about the TEMPLATE, because every way of
-- getting it wrong fails silently in game: replacing OnClick leaves a cell that sizes, highlights
-- and reports as shown while doing nothing, and reading the bag off the wrong place makes a click
-- act on a different bag -- which destroys an item rather than misdrawing one.
local H = require("harness.init")

describe("Components/ItemSlot", function()
    local root

    before_each(function()
        H.setup()
        root = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
        H.setBags({ [0] = { slots = 16, free = 14 } }, { silent = true })
    end)

    -- A per-bag holder, exactly as the grid will build it: the template reads the bag off the
    -- PARENT's id, so a cell has to live under one of these. Placed through the root container so
    -- it has a real rect -- a cell under an unplaced parent resolves no geometry at all.
    local function holder(bag)
        local f = H.env.CreateFrame("Frame", nil, root)
        f:SetID(bag)
        H.SuuUI.UIRoot:GetRootContainer():Add(f, { anchor = {
            point = "TOPLEFT", relativeTo = root, relativePoint = "TOPLEFT",
            x = 0, y = 0, width = 400, height = 400,
        } })
        return f, H.SuuUI.Layout:CreateContainer({
            host = f, layout = "flow", dir = "horizontal", wrap = true,
        })
    end

    local function cell(bag, slot, size)
        size = size or 34
        local hf, box = holder(bag)
        local c = H.C.ItemSlot({ slot = slot, size = size, bag = bag }, hf)
        box:Add(c, { width = size, height = size })
        return c
    end

    local function stage(bag, slot, props)
        H.setBagItem(bag, slot, props, { silent = true })
    end

    describe("construction", function()
        it("needs a slot, a size and a bag", function()
            local hf = holder(0)
            expect(function() H.C.ItemSlot({ size = 34, bag = 0 }, hf) end).throws()
            expect(function() H.C.ItemSlot({ slot = 1, bag = 0 }, hf) end).throws()
            expect(function() H.C.ItemSlot({ slot = 1, size = 34 }, hf) end)
                .as("bag cannot be inferred: an un-ID'd frame reports 0, same as the backpack")
                .throws()
        end)

        it("refuses a parent that was never given an id", function()
            local plain = H.env.CreateFrame("Frame", nil, root)
            expect(function() H.C.ItemSlot({ slot = 1, size = 34, bag = 3 }, plain) end)
                .as("id 0 does not match bag 3").throws()
        end)

        it("refuses a bag that disagrees with the parent's id", function()
            local hf = holder(0)
            expect(function() H.C.ItemSlot({ slot = 1, size = 34, bag = 3 }, hf) end)
                .as("a mis-parented cell would act on the wrong bag").throws()
        end)

        it("reads the bag from the parent and the slot from itself", function()
            local c = cell(4, 7)
            expect(c:GetBag()).as("from the parent's id").eq(4)
            expect(c:GetSlot()).as("from its own id").eq(7)
        end)

        it("is square at the given size", function()
            local c = cell(0, 1, 40)
            H.expectSize(c, 40, 40)
        end)
    end)

    describe("painting a slot", function()
        it("shows nothing for an empty slot", function()
            local c = cell(0, 1)
            expect(c:HasItem()).falsy()
            expect(c:GetItem()).eq(nil)
            expect(c._countText:IsShown()).as("no count on an empty cell").falsy()
        end)

        it("reads the client on construction", function()
            stage(0, 1, { itemID = 22832, iconFileID = 134129, stackCount = 12, quality = 1 })
            local c = cell(0, 1)
            expect(c:HasItem()).truthy()
            expect(c:GetItem().itemID).eq(22832)
        end)

        it("shows a stack count only above one", function()
            stage(0, 1, { itemID = 22832, stackCount = 12 })
            local c = cell(0, 1)
            expect(c._countText:IsShown()).truthy()
            expect(c._countText:GetText()).eq("12")

            stage(0, 2, { itemID = 22832, stackCount = 1 })
            local single = cell(0, 2)
            -- The client reports 1 for a single item, so a "1" on every occupied slot is noise.
            expect(single._countText:IsShown()).as("no 1s").falsy()
        end)

        it("keeps the count inside the cell and out of the way", function()
            stage(0, 1, { itemID = 22832, stackCount = 20 })
            local c = cell(0, 1)
            H.expectInside(c._countText, c:GetFrame())
        end)

        it("empties on SetItem(nil)", function()
            stage(0, 1, { itemID = 22832, stackCount = 5 })
            local c = cell(0, 1)
            c:SetItem(nil)
            expect(c:HasItem()).falsy()
            expect(c._countText:IsShown()).falsy()
        end)

        it("re-reads the client on Refresh", function()
            local c = cell(0, 1)
            expect(c:HasItem()).falsy()
            stage(0, 1, { itemID = 22832 })
            c:Refresh()
            expect(c:HasItem()).as("picked up the new item").truthy()
        end)

        it("dims a LOCKED slot, so a second move cannot be queued onto it", function()
            stage(0, 1, { itemID = 22832 })
            local c = cell(0, 1)
            expect(c._iconComp._artAlpha).as("not dimmed while free").eq(nil)
            stage(0, 1, { isLocked = true })
            c:Refresh()
            expect(c._iconComp._artAlpha).as("dimmed while the move is in flight")
                .eq(H.token("opacityDisabled"))
        end)
    end)

    describe("the quality edge", function()
        it("takes the item's colour at uncommon and above", function()
            stage(0, 1, { itemID = 22832, quality = 3 })
            local c = cell(0, 1)
            local want = H.SuuUI.Game:ItemQualityColor(3)
            expect(want).as("the client names a rare colour").truthy()
            expect(c._iconComp._borderColor).as("edge took the quality colour").eq(want)
        end)

        it("stays neutral below uncommon", function()
            -- A WHITE edge on a dark cell reads as a selected state rather than as information,
            -- which is why common and poor keep the neutral icon border instead.
            stage(0, 1, { itemID = 22832, quality = 1 })
            local c = cell(0, 1)
            expect(c._iconComp._borderColor).as("no quality colour on a common item").eq(nil)
        end)

        it("distinguishes qualities rather than colouring everything the same", function()
            stage(0, 1, { itemID = 111, quality = 3 })
            stage(0, 2, { itemID = 222, quality = 4 })
            local rare, epic = cell(0, 1), cell(0, 2)
            expect(rare._iconComp._borderColor).truthy()
            expect(epic._iconComp._borderColor).truthy()
            -- Two colours that are both wrong in the same way would satisfy a "has a border" test,
            -- so assert they DIFFER and that each matches the client's own value.
            expect(rare._iconComp._borderColor == epic._iconComp._borderColor)
                .as("rare and epic are not the same colour").falsy()
            expect(epic._iconComp._borderColor).eq(H.SuuUI.Game:ItemQualityColor(4))
        end)

        it("recedes to a DIMMED border when the item goes", function()
            stage(0, 1, { itemID = 22832, quality = 4 })
            local c = cell(0, 1)
            expect(c._iconComp._borderColor).as("epic edge while occupied").truthy()
            c:SetItem(nil)
            local edge = c._iconComp._borderColor
            local base = H.token("colorBorder")
            expect(type(edge)).as("an empty slot keeps an edge, just quieter").eq("table")
            expect(edge[1]).as("same hue as the border").near(base[1], 0.001)
            expect(edge[4]).as("at reduced alpha").lt(base[4] or 1)
        end)

        -- The distinction is the point: 40 empty slots drawing as hard an edge as the items is what
        -- makes a flat grid read as a spreadsheet rather than as an inventory.
        it("gives an occupied slot MORE edge weight than an empty one", function()
            stage(0, 1, { itemID = 111, quality = 1 })
            local occupied = cell(0, 1)
            local empty = cell(0, 2)
            -- nil is Icon's own default, i.e. full-weight colorBorder.
            expect(occupied._iconComp._borderColor).as("full weight").eq(nil)
            expect(empty._iconComp._borderColor).as("dimmed").truthy()
        end)
    end)

    -- The template contract. Each of these fails SILENTLY when broken, which is why they are
    -- asserted through a real click rather than by reading the code.
    -- The regression that shipped a blue lattice over every cell in game. The old code silenced a
    -- HAND-WRITTEN list of region names, and the real template carries regions no name of ours
    -- reaches -- so this asserts by ENUMERATION, which is the only shape that can catch the next
    -- region a client generation adds. Naming the fields here instead would re-introduce the bug.
    describe("the template's own art", function()
        it("leaves NO visible Blizzard texture on the cell, including unnamed ones", function()
            local c = cell(0, 1)
            local visible = {}
            for _, region in ipairs({ c:GetFrame():GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "Texture"
                   and region:IsShown() and (region:GetAlpha() or 1) > 0
                   and region:GetTexture() then
                    visible[#visible + 1] = tostring(region:GetTexture())
                end
            end
            expect(#visible)
                .as("Blizzard art still drawing over the cell: " .. table.concat(visible, ", "))
                .eq(0)
        end)

        -- Our own visuals live in child frames, so the sweep must not have reached them. Without
        -- this, "silence everything" would pass by blanking the cell entirely.
        it("keeps our own icon and readouts, which are not regions of the cell", function()
            stage(0, 1, { itemID = 4306, stackCount = 12, quality = 2 })
            local c = cell(0, 1)
            expect(c._iconComp:GetFrame():IsShown()).as("our icon survived the sweep").truthy()
            expect(c._countText:GetText()).as("our count survived the sweep").eq("12")
        end)
    end)

    -- THE BANK IS A DIFFERENT TEMPLATE FAMILY, and missing this shipped a bank window that opened and
    -- could not move anything. ElvUI branches on exactly this on this client:
    --   inherit = (bagID == BANK_CONTAINER) and 'BankItemButtonGenericTemplate'
    --                                        or 'ContainerFrameItemButtonTemplate'
    -- Phase 0 had measured it ("BankFrameItem1 is a real table; bank cells have their own template
    -- family") and this component ignored it.
    describe("the template depends on the container", function()
        it("builds a BAG cell on the container template", function()
            local c = cell(0, 1)
            expect(c:GetFrame()._template).eq("ContainerFrameItemButtonTemplate")
        end)

        it("builds the BANK's own container on the bank template", function()
            local c = cell(-1, 1)
            expect(c:GetFrame()._template).eq("BankItemButtonGenericTemplate")
        end)

        -- Bank BAGS are ordinary containers. Getting this wrong the other way would put bank-bag cells
        -- on a handler that hardcodes the bank container, so every click would act on slot N of the
        -- bank's own grid instead -- which moves the WRONG item rather than none.
        it("builds a BANK BAG on the container template, not the bank one", function()
            local c = cell(6, 1)
            expect(c:GetFrame()._template).eq("ContainerFrameItemButtonTemplate")
        end)

        it("creates the cell as an ItemButton, the type these templates are declared as", function()
            expect(cell(0, 1):GetFrame():GetObjectType()).eq("ItemButton")
        end)

        -- The harness dropped every OnClick on an ItemButton because its click gate named Button and
        -- CheckButton literally. H.click still returned TRUE -- a truthy return means the input was
        -- delivered, never that a handler ran -- so this asserts the OBSERVABLE, not the return.
        it("delivers clicks to a bank cell, not just to a bag cell", function()
            H.setBankOpen(true)
            H.setBagItem(-1, 1, { itemID = 4306, stackCount = 1 })
            local c = cell(-1, 1)
            H.click(c)
            expect(H.env.CursorHasItem()).as("a bank cell's click reaches our handler").truthy()
        end)
    end)

    -- WE OWN THE MOVEMENT. This block used to assert the TEMPLATE did it, on the strength of the
    -- secure action bar's rule -- and that premise was measured false in game: the cell carried the
    -- template's OnClick, OnDragStart and OnReceiveDrag, was mouse-enabled, and moved nothing.
    describe("moving items", function()
        it("picks the stack up on a plain click", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            expect(H.click(c)).as("input was delivered").truthy()
            expect(H.env.CursorHasItem()).as("the stack is on the cursor").truthy()
            expect(select(2, H.env.GetCursorInfo())).eq(22832)
        end)

        -- Pickup and place are ONE call, and placing onto an occupied slot SWAPS. A cell written on an
        -- overwrite assumption destroys an item on every rearrange, which is why the swap is asserted.
        it("places on a loaded cursor, and swaps rather than overwriting", function()
            stage(0, 1, { itemID = 111 })
            stage(0, 2, { itemID = 222 })
            local target = cell(0, 2)
            H.env.C_Container.PickupContainerItem(0, 1)
            expect(H.env.CursorHasItem()).truthy()
            H.click(target)
            expect(H.env.C_Container.GetContainerItemInfo(0, 2).itemID).eq(111)
            expect(select(2, H.env.GetCursorInfo())).as("previous occupant returned").eq(222)
        end)

        -- Drag is the half of the report that could never have worked: with no RegisterForDrag a frame
        -- never receives OnDragStart at all.
        it("picks up on a DRAG, not only on a click", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            c:GetFrame():_fire("OnDragStart", "LeftButton")
            expect(H.env.CursorHasItem()).as("drag picks the stack up").truthy()
        end)

        it("places on a drag released over it", function()
            stage(0, 1, { itemID = 111 })
            stage(0, 2, { itemID = 222 })
            H.env.C_Container.PickupContainerItem(0, 1)
            cell(0, 2):GetFrame():_fire("OnReceiveDrag", "LeftButton")
            expect(H.env.C_Container.GetContainerItemInfo(0, 2).itemID).eq(111)
        end)

        it("splits a stack on shift-click", function()
            stage(0, 1, { itemID = 2589, stackCount = 10 })
            local c = cell(0, 1)
            H.mods({ shift = true })
            H.click(c)
            H.mods({})
            expect(H.env.CursorHasItem()).as("half the stack is on the cursor").truthy()
        end)

        it("does not split a single item, it picks it up", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.mods({ shift = true })
            H.click(c)
            H.mods({})
            expect(H.env.CursorHasItem()).truthy()
        end)

        it("refuses every path while read-only", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            c:SetReadOnly(true)
            H.click(c)
            expect(H.env.CursorHasItem()).as("a cached alt's grid cannot be moved").falsy()
            c:GetFrame():_fire("OnDragStart", "LeftButton")
            expect(H.env.CursorHasItem()).as("drag is refused too").falsy()
        end)

        it("emits CLICKED and still performs the action", function()
            stage(0, 1, { itemID = 22832 })
            local c = cell(0, 1)
            local spy = H.signalSpy(c, H.S.SIGNALS.CLICKED)
            H.click(c)
            expect(spy.count).as("observed").eq(1)
            expect(H.env.CursorHasItem()).as("and the action still ran").truthy()
        end)
    end)

    -- USE is genuinely protected away from a merchant, so right-click is a SELL where that is
    -- permitted and a no-op elsewhere -- rather than a call that costs the player a taint error.
    describe("right click", function()
        it("sells at a merchant", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.setMerchantOpen(true)
            H.resetUsedContainerItems()
            H.click(c, "RightButton")
            expect(#H.getUsedContainerItems()).as("sold").eq(1)
        end)

        it("transfers at an open bank, which is the client's own shortcut", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.setMerchantOpen(false)
            H.setBankOpen(true)
            H.resetUsedContainerItems()
            H.resetBlockedActions()
            H.click(c, "RightButton")
            expect(#H.getUsedContainerItems()).as("transferred").eq(1)
            expect(#H.getBlockedActions()).as("permitted, not refused").eq(0)
        end)

        -- The bank test must NOT be BankFrame:IsShown(): suppression leaves that frame shown on
        -- purpose, because hiding it calls CloseBankFrame(). So a cell reading the frame's visibility
        -- would think it was at a teller permanently.
        it("does not treat the suppressed bank FRAME as being at a bank", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.setMerchantOpen(false)
            H.setBankOpen(false)
            H.env.BankFrame:Show()   -- shown but the session is closed, exactly as suppression leaves it
            H.resetUsedContainerItems()
            H.click(c, "RightButton")
            expect(#H.getUsedContainerItems()).as("a shown frame is not an open bank").eq(0)
        end)

        it("does nothing away from a merchant, rather than being refused", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.setMerchantOpen(false)
            H.resetUsedContainerItems()
            H.resetBlockedActions()
            H.click(c, "RightButton")
            expect(#H.getUsedContainerItems()).eq(0)
            expect(#H.getBlockedActions()).as("no taint error spent on the player").eq(0)
        end)
    end)

    describe("signals", function()
        it("emits MOUSE_ENTER and MOUSE_LEAVE", function()
            local c = cell(0, 1)
            local enter = H.signalSpy(c, H.S.SIGNALS.MOUSE_ENTER)
            local leave = H.signalSpy(c, H.S.SIGNALS.MOUSE_LEAVE)
            c:GetFrame():_fire("OnEnter")
            c:GetFrame():_fire("OnLeave")
            expect(enter.count).eq(1)
            expect(leave.count).eq(1)
        end)

        it("emits SIZE_CHANGED when a layout resizes it, not only from SetSize", function()
            local c = cell(0, 1)
            local spy = H.signalSpy(c, H.S.SIGNALS.SIZE_CHANGED)
            c:GetFrame():SetSize(48, 48)
            expect(spy.count).gt(0)
        end)

        it("does NOT emit CLICKED from SetItem", function()
            stage(0, 1, { itemID = 22832 })
            local c = cell(0, 1)
            local spy = H.signalSpy(c, H.S.SIGNALS.CLICKED)
            c:SetItem(nil)
            c:Refresh()
            expect(spy.count).as("setters are silent").eq(0)
        end)
    end)

    describe("read-only", function()
        it("drops mouse input", function()
            local c = cell(0, 1)
            expect(c:IsReadOnly()).falsy()
            c:SetReadOnly(true)
            expect(c:IsReadOnly()).truthy()
            expect(c:GetFrame():IsMouseEnabled()).as("inert").falsy()
        end)

        it("comes back live", function()
            local c = cell(0, 1)
            c:SetReadOnly(true)
            c:SetReadOnly(false)
            expect(c:GetFrame():IsMouseEnabled()).truthy()
        end)

        -- Dropping mouse input is REFUSED on a protected frame in combat, so it is recorded and
        -- applied by the owner afterwards rather than attempted and lost.
        it("defers a change made in combat, and applies it on the way out", function()
            local c = cell(0, 1)
            H.setCombat(true)
            c:SetReadOnly(true)
            expect(c:IsReadOnly()).as("not applied yet").falsy()
            expect(c:IsReadOnlyDeferred()).truthy()
            H.setCombat(false)
            expect(c:ApplyPending()).truthy()
            expect(c:IsReadOnly()).truthy()
            expect(c:GetFrame():IsMouseEnabled()).falsy()
        end)

        it("has nothing to apply when no change was deferred", function()
            local c = cell(0, 1)
            expect(c:ApplyPending()).falsy()
        end)
    end)

    describe("theme and teardown", function()
        it("re-resolves the edge on a theme change", function()
            stage(0, 1, { itemID = 22832, quality = 1 })
            local c = cell(0, 1)
            expect(function() H.SuuUI.Theme:SetActive("Default") end).notThrows()
            expect(c:HasItem()).as("still painted").truthy()
        end)

        it("Destroy hides it and drops its subscriptions", function()
            local c = cell(0, 1)
            local before = H.SuuUI.Settings:GetWatcherCount()
            c:Destroy()
            expect(c:IsShown()).falsy()
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
        end)
    end)
end)
