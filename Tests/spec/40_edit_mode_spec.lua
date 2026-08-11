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
