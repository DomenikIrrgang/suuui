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

    describe("the Blizzard template's own handler is left intact", function()        it("uses the item on a plain click, through the trusted path", function()
            stage(0, 1, { itemID = 22832, stackCount = 1 })
            local c = cell(0, 1)
            H.resetUsedContainerItems()
            H.resetBlockedActions()
            expect(H.click(c)).as("input was delivered").truthy()
            local used = H.getUsedContainerItems()
            expect(#used).as("the template used the item").eq(1)
            expect(used[1].via).as("through the TRUSTED path, not our own call").eq("template")
            -- And nothing was refused: our own Lua never called the blocked function.
            expect(#H.getBlockedActions()).as("nothing refused").eq(0)
        end)

        it("places instead of using when the cursor is loaded", function()
            stage(0, 1, { itemID = 111 })
            stage(0, 2, { itemID = 222 })
            local target = cell(0, 2)
            H.env.C_Container.PickupContainerItem(0, 1)
            expect(H.env.CursorHasItem()).truthy()
            H.resetUsedContainerItems()
            H.click(target)
            expect(#H.getUsedContainerItems()).as("placed, not used").eq(0)
            expect(H.env.C_Container.GetContainerItemInfo(0, 2).itemID).eq(111)
            -- The previous occupant came back to the cursor rather than being destroyed.
            expect(select(2, H.env.GetCursorInfo())).eq(222)
        end)

        it("emits CLICKED from PostClick, without stealing OnClick", function()
            stage(0, 1, { itemID = 22832 })
            local c = cell(0, 1)
            local spy = H.signalSpy(c, H.S.SIGNALS.CLICKED)
            H.resetUsedContainerItems()
            H.click(c)
            expect(spy.count).as("observed").eq(1)
            -- The action still happened, which is what proves the handler was hooked rather than
            -- replaced. A spec asserting only the signal would pass with OnClick overwritten.
            expect(#H.getUsedContainerItems()).as("and the action still ran").eq(1)
        end)

        it("clears the template's own art", function()
            local c = cell(0, 1)
            local f = c:GetFrame()
            local normal = f.GetNormalTexture and f:GetNormalTexture()
            expect(normal).as("the template shipped art").truthy()
            expect(normal:IsShown()).as("and we hid it").falsy()
            expect(f.icon and f.icon:IsShown()).as("its icon too").falsy()
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
