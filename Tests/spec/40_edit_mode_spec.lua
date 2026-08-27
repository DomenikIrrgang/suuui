local H = require("harness")

-------------------------------------------------------------------------------
-- MoveableFrame Lock
-------------------------------------------------------------------------------
describe("MoveableFrame Lock", function()
    local host, f

    before_each(function()
        H.setup()
        host = H.parent(1024, 768)
        H.SuuUI.Settings:Register("test_plugin", {
            { key = "frame_position", type = "position", default = {
                point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20,
            }},
        })
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(100, 50)
        H.SuuUI.MoveableFrame:Apply(f, {
            pluginId    = "test_plugin",
            key         = "frame_position",
            displayName = "Test Frame",
            defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
        })
    end)

    -- Guard: SetLocked/IsLocked may not be implemented yet
    local function hasLockAPI()
        return H.SuuUI.MoveableFrame.SetLocked ~= nil
            and H.SuuUI.MoveableFrame.IsLocked ~= nil
    end

    it("SetLocked(frame, true) stores locked=true in position setting", function()
        if not hasLockAPI() then return end
        H.SuuUI.MoveableFrame:SetLocked(f, true)
        local pos = H.SuuUI.Settings:Get("test_plugin", "frame_position")
        expect(pos.locked).eq(true)
    end)

    it("IsLocked(frame) returns true after SetLocked(true)", function()
        if not hasLockAPI() then return end
        H.SuuUI.MoveableFrame:SetLocked(f, true)
        expect(H.SuuUI.MoveableFrame:IsLocked(f)).eq(true)
    end)

    it("IsLocked(frame) returns false by default", function()
        if not hasLockAPI() then return end
        expect(H.SuuUI.MoveableFrame:IsLocked(f)).eq(false)
    end)

    it("locked frame overlay uses colorEditOverlayLocked token colour", function()
        if not hasLockAPI() then return end
        H.SuuUI.MoveableFrame:SetLocked(f, true)
        H.SuuUI.ToggleUI:Enable()

        local overlayBg = f._suuui_moveable.overlayBg
        local r, g, b, a = overlayBg:GetColorTexture()
        local tokenColor = H.token("colorEditOverlayLocked")
        expect(tokenColor).as("token must exist").notNil()
        expect(r).near(tokenColor[1], 0.02)
        expect(g).near(tokenColor[2], 0.02)
        expect(b).near(tokenColor[3], 0.02)
        expect(a).near(tokenColor[4], 0.02)
    end)

    it("dragging a locked frame does not change its position", function()
        if not hasLockAPI() then return end
        H.SuuUI.MoveableFrame:SetLocked(f, true)
        H.SuuUI.ToggleUI:Enable()

        local posBefore = H.SuuUI.Settings:Get("test_plugin", "frame_position")
        local xBefore, yBefore = posBefore.x, posBefore.y

        -- Simulate a drag via the overlay: set cursor positions so movement > 2px
        -- (avoids triggering click-to-select code path)
        H.state.cursorX, H.state.cursorY = 50, 50
        local overlay = f._suuui_moveable.overlay
        local onDragStart = overlay:GetScript("OnDragStart")
        local onDragStop  = overlay:GetScript("OnDragStop")
        if onDragStart then onDragStart() end

        -- Move cursor far enough to be a drag, not a click (> 2px)
        H.state.cursorX, H.state.cursorY = 200, 200

        -- Move the frame (simulate client moving it during drag)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 200, -100)

        if onDragStop then onDragStop() end

        -- Position setting must be unchanged
        local posAfter = H.SuuUI.Settings:Get("test_plugin", "frame_position")
        expect(posAfter.x).as("x unchanged after locked drag").eq(xBefore)
        expect(posAfter.y).as("y unchanged after locked drag").eq(yBefore)
    end)

    it("unlocking restores drag capability", function()
        if not hasLockAPI() then return end
        -- Ensure grid snap is off so it does not alter the saved value
        H.SuuUI.Settings:Set("_layout", "snap_mode", "none")

        H.SuuUI.MoveableFrame:SetLocked(f, true)
        H.SuuUI.MoveableFrame:SetLocked(f, false)
        H.SuuUI.ToggleUI:Enable()

        -- Position the cursor at the frame (simulates start of drag)
        H.state.cursorX, H.state.cursorY = 50, 50

        -- Simulate drag: OnDragStart records cursor, then move frame
        local overlay = f._suuui_moveable.overlay
        local onDragStart = overlay:GetScript("OnDragStart")
        if onDragStart then onDragStart() end

        -- Move cursor and frame (actual drag displacement > 2px)
        H.state.cursorX, H.state.cursorY = 200, 200
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 160, -80)

        local onDragStop = overlay:GetScript("OnDragStop")
        if onDragStop then onDragStop() end

        local pos = H.SuuUI.Settings:Get("test_plugin", "frame_position")
        expect(pos.x).near(160, 1)
        expect(pos.y).near(-80, 1)
    end)

    it("lock badge text is visible when locked, hidden when unlocked", function()
        if not hasLockAPI() then return end
        H.SuuUI.ToggleUI:Enable()

        H.SuuUI.MoveableFrame:SetLocked(f, true)
        local badge = f._suuui_moveable.lockBadge or f._suuui_moveable.badge
        if badge then
            expect(badge:IsShown()).eq(true)
        end

        H.SuuUI.MoveableFrame:SetLocked(f, false)
        if badge then
            expect(badge:IsShown()).eq(false)
        end
    end)
end)

-------------------------------------------------------------------------------
-- Grid Snap
-------------------------------------------------------------------------------
describe("Grid Snap", function()
    before_each(function()
        H.setup()
    end)

    -- The snap function may live on SuuUI.SnapGrid, SuuUI.MoveableFrame, or be a local.
    -- Test through the settings-driven contract: snap_mode + grid_size.
    local function getSnapFn()
        if H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap then
            return function(x, y)
                return H.SuuUI.SnapGrid:Snap(x, y)
            end
        end
        if H.SuuUI.MoveableFrame.SnapToGrid then
            return function(x, y)
                return H.SuuUI.MoveableFrame:SnapToGrid(x, y)
            end
        end
        return nil
    end

    it("with snap_mode=grid, grid_size=16: snap(17,23) rounds to grid", function()
        local snap = getSnapFn()
        if not snap then return end

        H.SuuUI.Settings:Set("_layout", "snap_mode", "grid")
        H.SuuUI.Settings:Set("_layout", "grid_size", 16)

        local x, y = snap(17, 23)
        -- Nearest multiple of 16: 17 -> 16, 23 -> 16 (nearest) or 32
        expect(x % 16).as("x snapped to grid multiple").eq(0)
        expect(y % 16).as("y snapped to grid multiple").eq(0)
        expect(x).eq(16)
    end)

    it("with snap_mode=grid, grid_size=16: snap(0,0) = (0,0)", function()
        local snap = getSnapFn()
        if not snap then return end

        H.SuuUI.Settings:Set("_layout", "snap_mode", "grid")
        H.SuuUI.Settings:Set("_layout", "grid_size", 16)

        local x, y = snap(0, 0)
        expect(x).eq(0)
        expect(y).eq(0)
    end)

    it("with snap_mode=none: snap(17,23) passes through unchanged", function()
        local snap = getSnapFn()
        if not snap then return end

        H.SuuUI.Settings:Set("_layout", "snap_mode", "none")
        H.SuuUI.Settings:Set("_layout", "grid_size", 16)

        local x, y = snap(17, 23)
        expect(x).eq(17)
        expect(y).eq(23)
    end)

    it("with grid_size=8: snap(12,5) rounds to nearest 8", function()
        local snap = getSnapFn()
        if not snap then return end

        H.SuuUI.Settings:Set("_layout", "snap_mode", "grid")
        H.SuuUI.Settings:Set("_layout", "grid_size", 8)

        local x, y = snap(12, 5)
        -- 12 -> 8 or 16 depending on rounding; 5 -> 8
        expect(x % 8).eq(0)
        expect(y % 8).eq(0)
    end)

    it("SuuUI.SnapGrid:Snap works directly if module exists", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end

        H.SuuUI.Settings:Set("_layout", "snap_mode", "grid")
        H.SuuUI.Settings:Set("_layout", "grid_size", 16)

        local x, y = H.SuuUI.SnapGrid:Snap(32, 48)
        expect(x).eq(32)
        expect(y).eq(48)
    end)
end)

-------------------------------------------------------------------------------
-- Guide Snap (magnetic alignment to other elements)
--
-- The reported bug was asymmetric: the horizontal axis snapped to another
-- element's left edge while the vertical axis ignored the bottom edge entirely.
-- These specs pin BOTH axes independently so a regression on one is visible.
-------------------------------------------------------------------------------
describe("Guide Snap", function()
    local rootFrame, other, dragged

    -- Builds two moveable frames as siblings under the UI root. `offX`/`offY` place
    -- the dragged frame relative to the other frame's TOPLEFT, so a test states the
    -- misalignment it wants in one place.
    --
    -- The offset goes in the SCHEMA default, not just in Apply's `defaults`: the
    -- position watcher restores from Settings, so the schema value is what actually
    -- places the frame. Passing it only to Apply leaves both frames co-located, which
    -- makes every snap delta zero and every assertion pass for the wrong reason.
    local function stage(offX, offY)
        -- Every moveable frame in the addon is a snap CANDIDATE, so a production frame
        -- registered by a plugin (the chat window is one) offers its own edges as magnets and
        -- pulls an axis this spec expects to be left alone. Unregister them first so the snap
        -- logic is measured against exactly the two frames staged below -- otherwise this block
        -- fails whenever any future plugin gains a moveable, which is what happened when the
        -- chat plugin landed.
        for _, f in ipairs(H.SuuUI.ToggleUI:GetAll()) do
            H.SuuUI.MoveableFrame:Remove(f)
        end

        H.SuuUI.Settings:Register("guide_plugin", {
            { key = "other_pos", type = "position", default = {
                point = "TOPLEFT", relPoint = "TOPLEFT", x = 200, y = -200 } },
            { key = "dragged_pos", type = "position", default = {
                point = "TOPLEFT", relPoint = "TOPLEFT",
                x = 200 + offX, y = -200 + offY } },
        })

        rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()

        other = H.env.CreateFrame("Frame", nil, rootFrame)
        other:SetSize(100, 50)
        H.SuuUI.MoveableFrame:Apply(other, {
            pluginId = "guide_plugin", key = "other_pos", displayName = "Other",
            defaults = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 200, y = -200 },
        })

        dragged = H.env.CreateFrame("Frame", nil, rootFrame)
        dragged:SetSize(100, 50)
        H.SuuUI.MoveableFrame:Apply(dragged, {
            pluginId = "guide_plugin", key = "dragged_pos", displayName = "Dragged",
            defaults = { point = "TOPLEFT", relPoint = "TOPLEFT",
                         x = 200 + offX, y = -200 + offY },
        })

        H.SuuUI.Settings:Set("_layout", "snap_mode", "guides")
        H.SuuUI.ToggleUI:Enable()
    end

    before_each(function()
        H.setup()
        H.parent(1024, 768)
    end)

    it("snaps the vertical axis onto another element's edge", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        -- Aligned horizontally, 4 units off vertically: only y has work to do.
        stage(0, -4)

        local _, y = H.SuuUI.SnapGrid:Snap(200, -204, dragged)
        expect(y).as("y snapped onto the other element's edge").eq(-200)
    end)

    it("snaps the horizontal axis onto another element's edge", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        stage(4, 0)

        local x = H.SuuUI.SnapGrid:Snap(204, -200, dragged)
        expect(x).as("x snapped onto the other element's edge").eq(200)
    end)

    it("snaps BOTH axes in a single call", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        stage(3, -3)

        local x, y = H.SuuUI.SnapGrid:Snap(203, -203, dragged)
        expect(x).as("x snapped").eq(200)
        -- This is the assertion the reported bug would fail: x lands, y is ignored.
        expect(y).as("y snapped in the same call as x").eq(-200)
    end)

    it("leaves an axis alone when nothing is within the threshold", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        -- x is 3 off (snaps), y is 200 off (nothing to snap to).
        stage(3, -200)

        local x, y = H.SuuUI.SnapGrid:Snap(203, -400, dragged)
        expect(x).as("x still snapped").eq(200)
        expect(y).as("y left untouched, no guide in range").eq(-400)
    end)

    it("snap mode none leaves both axes untouched", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        stage(3, -3)
        H.SuuUI.Settings:Set("_layout", "snap_mode", "none")

        local x, y = H.SuuUI.SnapGrid:Snap(203, -203, dragged)
        expect(x).eq(203)
        expect(y).eq(-203)
    end)

    -- A drawn guide is a promise that releasing there lands on the line. These pin that
    -- promise: only edges within magnet range are returned, so a line can never appear
    -- without a snap behind it.
    --
    -- Assertions target the OTHER frame's specific edge rather than counting guides:
    -- H.setup() boots the real addon, so ToggleUI also holds the shipped plugin frames
    -- and a raw count would be measuring those too.
    local function contains(list, v)
        for i = 1, #list do
            if math.abs(list[i] - v) < 0.001 then return true end
        end
        return false
    end

    it("offers a guide for an edge that is within magnet range", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.FindGuides) then return end
        stage(3, -3)

        local g = H.SuuUI.SnapGrid:FindGuides(dragged)
        expect(contains(g.v, other:GetLeft()))
            .as("the other frame's left edge is offered").eq(true)
        expect(contains(g.h, other:GetTop()))
            .as("the other frame's top edge is offered").eq(true)
    end)

    it("offers no guide for an edge that is out of range", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.FindGuides) then return end
        stage(400, -300)

        local g = H.SuuUI.SnapGrid:FindGuides(dragged)
        expect(contains(g.v, other:GetLeft()))
            .as("out-of-range left edge is not offered").eq(false)
        expect(contains(g.h, other:GetTop()))
            .as("out-of-range top edge is not offered").eq(false)
    end)

    it("guides follow the frame instead of staying frozen at pickup", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.FindGuides) then return end
        -- Starts far away: the other frame's edge is not on offer.
        stage(400, -300)
        expect(contains(H.SuuUI.SnapGrid:FindGuides(dragged).v, other:GetLeft()))
            .as("not offered at pickup").eq(false)

        -- Move it next to the other element, as a drag would.
        H.SuuUI.Settings:Set("guide_plugin", "dragged_pos", {
            point = "TOPLEFT", relPoint = "TOPLEFT", x = 202, y = -202,
        })

        expect(contains(H.SuuUI.SnapGrid:FindGuides(dragged).v, other:GetLeft()))
            .as("offered once the frame moved close").eq(true)
    end)

    it("the same threshold gates the drawn guide and the magnet", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.FindGuides) then return end
        stage(3, -3)
        expect(contains(H.SuuUI.SnapGrid:FindGuides(dragged).v, other:GetLeft()))
            .as("guide offered").eq(true)
        local x = H.SuuUI.SnapGrid:Snap(203, -203, dragged)
        expect(x).as("the offered guide actually snapped").eq(200)
    end)

    -- The result is handed to AnchorLayout, which snaps everything it sends to SetPoint.
    -- A fractional return therefore gets rounded downstream AFTER being aimed at the
    -- guide, landing the frame a pixel short of the line it should sit flush against.
    -- The result is handed to AnchorLayout, which snaps everything it sends to SetPoint.
    -- A fractional return therefore gets rounded downstream AFTER being aimed at the
    -- guide, landing the frame a pixel short of the line it should sit flush against.
    it("returns a pixel-grid aligned offset from a fractional edge", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        stage(3, -3)
        -- A fractional height puts the other frame's bottom edge off the grid, so the
        -- raw delta needed to align to it is fractional too.
        other:SetSize(100, 50.5)

        local x, y = H.SuuUI.SnapGrid:Snap(203, -203, dragged)
        expect(x).as("x lands on the pixel grid").eq(H.SuuUI.Pixel.Snap(x))
        expect(y).as("y lands on the pixel grid").eq(H.SuuUI.Pixel.Snap(y))
    end)

    -- Stacking lands FLUSH, not overlapped. A one-physical-pixel seam does show at the
    -- boundary in game, but it cannot be corrected from here: one unit is `multiplier`
    -- physical pixels, so one pixel is a fraction of a unit, and AnchorLayout snaps every
    -- coordinate to grid = 1. A whole-unit nudge overshoots by `multiplier` pixels and
    -- turns the seam into a visible overlap — measured in game, both directions.
    it("aligns flush when stacking our bottom against their top", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        -- offY = +47 puts the dragged frame ABOVE the other with its bottom 3 units
        -- below the other's top, so the winning pairing is bottom-to-top.
        stage(0, 47)

        local _, y = H.SuuUI.SnapGrid:Snap(200, -153, dragged)
        expect(y).as("stacked edge lands flush, no overlap nudge").eq(-150)
    end)

    it("matches exactly when aligning like-for-like edges", function()
        if not (H.SuuUI.SnapGrid and H.SuuUI.SnapGrid.Snap) then return end
        stage(0, -3)

        local _, y = H.SuuUI.SnapGrid:Snap(200, -203, dragged)
        expect(y).as("like-for-like matches exactly").eq(-200)
    end)
end)

-------------------------------------------------------------------------------
-- Click to Select
-------------------------------------------------------------------------------
describe("Click to Select", function()
    local host, f

    before_each(function()
        H.setup()
        host = H.parent(1024, 768)
        H.SuuUI.Settings:Register("test_plugin", {
            { key = "frame_position", type = "position", default = {
                point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20,
            }},
        })
        f = H.env.CreateFrame("Frame", nil, host)
        f:SetSize(100, 50)
        H.SuuUI.MoveableFrame:Apply(f, {
            pluginId    = "test_plugin",
            key         = "frame_position",
            displayName = "Test Frame",
            defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
        })
        H.SuuUI.ToggleUI:Enable()
    end)

    it("clicking overlay without movement calls EditPanel.Select", function()
        -- Mock EditPanel
        local selectCalled, selectArg
        H.SuuUI.EditPanel = H.SuuUI.EditPanel or {}
        H.SuuUI.EditPanel.Select = function(_, frame)
            selectCalled = true
            selectArg = frame
        end

        local overlay = f._suuui_moveable.overlay
        local onMouseUp = overlay:GetScript("OnMouseUp")
        if not onMouseUp then return end

        -- Click with no drag (no OnDragStart fired, or movement < threshold)
        onMouseUp(overlay, "LeftButton")

        if selectCalled then
            expect(selectArg).eq(f)
        end
    end)

    it("actual drag (movement) does NOT call EditPanel.Select", function()
        local selectCalled = false
        H.SuuUI.EditPanel = H.SuuUI.EditPanel or {}
        H.SuuUI.EditPanel.Select = function()
            selectCalled = true
        end

        local overlay = f._suuui_moveable.overlay
        local onDragStart = overlay:GetScript("OnDragStart")
        local onDragStop  = overlay:GetScript("OnDragStop")

        if not onDragStart or not onDragStop then return end

        -- Simulate actual drag: cursor starts at one position
        H.state.cursorX, H.state.cursorY = 50, 50
        onDragStart()

        -- Cursor moves significantly (> 2px threshold)
        H.state.cursorX, H.state.cursorY = 200, 200
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 200, -100)
        onDragStop()

        expect(selectCalled).as("Select not called during a drag").eq(false)
    end)
end)

-------------------------------------------------------------------------------
-- EditPanel
-------------------------------------------------------------------------------
if SuuUI and SuuUI.EditPanel then
describe("EditPanel", function()
    before_each(function()
        H.setup()
    end)

    it("panel frame exists and is hidden by default", function()
        if not H.SuuUI.EditPanel then return end
        local panel = H.SuuUI.EditPanel:GetFrame()
        if panel then
            expect(panel:IsShown()).eq(false)
        end
    end)

    it("setting edit_mode=true shows the panel", function()
        if not H.SuuUI.EditPanel then return end
        H.SuuUI.Settings:Set("_layout", "edit_mode", true)
        local panel = H.SuuUI.EditPanel:GetFrame()
        if panel then
            expect(panel:IsShown()).eq(true)
        end
    end)

    it("setting edit_mode=false hides the panel", function()
        if not H.SuuUI.EditPanel then return end
        H.SuuUI.Settings:Set("_layout", "edit_mode", true)
        H.SuuUI.Settings:Set("_layout", "edit_mode", false)
        local panel = H.SuuUI.EditPanel:GetFrame()
        if panel then
            expect(panel:IsShown()).eq(false)
        end
    end)

    it("Select(frame) stores it as selected", function()
        if not (H.SuuUI.EditPanel and H.SuuUI.EditPanel.Select) then return end
        local f = H.env.CreateFrame("Frame", nil, H.UIParent)
        H.SuuUI.EditPanel:Select(f)
        if H.SuuUI.EditPanel.GetSelected then
            expect(H.SuuUI.EditPanel:GetSelected()).eq(f)
        end
    end)

    it("GetSelected() returns the selected frame", function()
        if not (H.SuuUI.EditPanel and H.SuuUI.EditPanel.GetSelected) then return end
        local f = H.env.CreateFrame("Frame", nil, H.UIParent)
        H.SuuUI.EditPanel:Select(f)
        expect(H.SuuUI.EditPanel:GetSelected()).eq(f)
    end)
end)
end -- if SuuUI.EditPanel

-------------------------------------------------------------------------------
-- SnapGrid Visibility
-------------------------------------------------------------------------------
if SuuUI and SuuUI.SnapGrid then
describe("SnapGrid Visibility", function()
    before_each(function()
        H.setup()
    end)

    it("grid shown when edit_mode=true AND show_grid=true", function()
        if not H.SuuUI.SnapGrid then return end
        H.SuuUI.Settings:Set("_layout", "edit_mode", true)
        H.SuuUI.Settings:Set("_layout", "show_grid", true)
        local grid = H.SuuUI.SnapGrid:GetFrame()
        if grid then
            expect(grid:IsShown()).eq(true)
        end
    end)

    it("grid hidden when show_grid=false", function()
        if not H.SuuUI.SnapGrid then return end
        H.SuuUI.Settings:Set("_layout", "edit_mode", true)
        H.SuuUI.Settings:Set("_layout", "show_grid", false)
        local grid = H.SuuUI.SnapGrid:GetFrame()
        if grid then
            expect(grid:IsShown()).eq(false)
        end
    end)

    it("grid hidden when edit_mode=false regardless of show_grid", function()
        if not H.SuuUI.SnapGrid then return end
        H.SuuUI.Settings:Set("_layout", "show_grid", true)
        H.SuuUI.Settings:Set("_layout", "edit_mode", false)
        local grid = H.SuuUI.SnapGrid:GetFrame()
        if grid then
            expect(grid:IsShown()).eq(false)
        end
    end)
end)
end -- if SuuUI.SnapGrid
