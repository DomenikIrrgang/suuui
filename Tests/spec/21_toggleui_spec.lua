local H = require("harness")

describe("Core.ToggleUI", function()
    before_each(function()
        H.setup()
    end)

    describe("state management", function()
        it("starts in locked mode (edit mode off)", function()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("toggles edit mode on", function()
            H.SuuUI.ToggleUI:Toggle()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)

        it("toggles edit mode off again", function()
            H.SuuUI.ToggleUI:Toggle()
            H.SuuUI.ToggleUI:Toggle()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("Enable() activates edit mode", function()
            H.SuuUI.ToggleUI:Enable()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)

        it("Disable() deactivates edit mode", function()
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.ToggleUI:Disable()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("Enable() is idempotent", function()
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.ToggleUI:Enable()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)

        it("Disable() is idempotent", function()
            H.SuuUI.ToggleUI:Disable()
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)
    end)

    describe("events", function()
        it("fires SUUUI_SETTING_CHANGED on toggle", function()
            local received = nil
            H.SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pid, key, val)
                if pid == "_layout" and key == "edit_mode" then
                    received = val
                end
            end, "test_toggle")
            H.SuuUI.ToggleUI:Toggle()
            expect(received).eq(true)
        end)

        it("fires SUUUI_SETTING_CHANGED with false when toggling off", function()
            H.SuuUI.ToggleUI:Enable()
            local received = nil
            H.SuuUI.Events:On("SUUUI_SETTING_CHANGED", function(pid, key, val)
                if pid == "_layout" and key == "edit_mode" then
                    received = val
                end
            end, "test_toggle_off")
            H.SuuUI.ToggleUI:Toggle()
            expect(received).eq(false)
        end)

        it("notifies watchers on toggle", function()
            local received = nil
            H.SuuUI.Settings:Watch("_layout", "edit_mode", function(val)
                received = val
            end, "test_watcher")
            H.SuuUI.ToggleUI:Toggle()
            expect(received).eq(true)
        end)

        it("notifies watchers with false when disabling", function()
            H.SuuUI.ToggleUI:Enable()
            local received = nil
            H.SuuUI.Settings:Watch("_layout", "edit_mode", function(val)
                received = val
            end, "test_watcher_off")
            H.SuuUI.ToggleUI:Disable()
            expect(received).eq(false)
        end)
    end)

    describe("registry", function()
        it("tracks registered frames", function()
            local countBefore = #H.SuuUI.ToggleUI:GetAll()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            H.SuuUI.ToggleUI:Register(f)
            expect(#H.SuuUI.ToggleUI:GetAll()).eq(countBefore + 1)
        end)

        it("unregisters frames", function()
            local countBefore = #H.SuuUI.ToggleUI:GetAll()
            local f = H.env.CreateFrame("Frame", nil, H.UIParent)
            H.SuuUI.ToggleUI:Register(f)
            H.SuuUI.ToggleUI:Unregister(f)
            expect(#H.SuuUI.ToggleUI:GetAll()).eq(countBefore)
        end)
    end)

    describe("slash command", function()
        it("/suuui toggle activates edit mode", function()
            H.env.SlashCmdList["SUUUI"]("toggle")
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)

        it("/suuui lock disables edit mode", function()
            H.SuuUI.ToggleUI:Enable()
            H.env.SlashCmdList["SUUUI"]("lock")
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("/suuui unlock enables edit mode", function()
            H.env.SlashCmdList["SUUUI"]("unlock")
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)
    end)

    describe("settings sync", function()
        it("registers _layout schema with edit_mode setting", function()
            local schema = H.SuuUI.Settings:GetSchema("_layout")
            expect(schema).notNil()
            local found = false
            for _, entry in ipairs(schema) do
                if entry.key == "edit_mode" then found = true end
            end
            expect(found).eq(true)
        end)

        it("edit_mode defaults to false", function()
            expect(H.SuuUI.Settings:Get("_layout", "edit_mode")).eq(false)
        end)

        it("setting edit_mode to true activates edit mode", function()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(true)
        end)

        it("setting edit_mode to false deactivates edit mode", function()
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(H.SuuUI.ToggleUI:IsEditMode()).eq(false)
        end)

        it("toggling via API updates the setting", function()
            H.SuuUI.ToggleUI:Enable()
            expect(H.SuuUI.Settings:Get("_layout", "edit_mode")).eq(true)
        end)

        it("disabling via API updates the setting", function()
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.ToggleUI:Disable()
            expect(H.SuuUI.Settings:Get("_layout", "edit_mode")).eq(false)
        end)
    end)
end)

describe("Core.MoveableFrame", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(1024, 768)
        -- Disable grid snap so position tests are not rounded to grid boundaries
        H.SuuUI.Settings:Set("_layout", "snap_mode", "none")
        H.SuuUI.Settings:Register("test_plugin", {
            { key = "frame_position", type = "position", default = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 } },
        })
    end)

    describe("Apply", function()
        it("registers the frame with ToggleUI", function()
            local countBefore = #H.SuuUI.ToggleUI:GetAll()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            expect(#H.SuuUI.ToggleUI:GetAll()).eq(countBefore + 1)
        end)

        it("sets the frame as movable", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            expect(f:IsMovable()).eq(true)
        end)

        it("restores default position on apply", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            local point, _, relPoint, x, y = f:GetPoint()
            expect(point).eq("TOPLEFT")
            expect(relPoint).eq("TOPLEFT")
            expect(x).eq(10)
            expect(y).eq(-20)
        end)

        it("restores saved position from settings", function()
            -- Pre-save a position
            H.SuuUI.Settings:Set("test_plugin", "frame_position", {
                point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -30, y = 40,
            })
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            local point, _, relPoint, x, y = f:GetPoint()
            expect(point).eq("BOTTOMRIGHT")
            expect(relPoint).eq("BOTTOMRIGHT")
            expect(x).eq(-30)
            expect(y).eq(40)
        end)

        it("creates an overlay that is hidden by default", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            expect(f._suuui_moveable.overlay:IsShown()).eq(false)
        end)
    end)

    describe("edit mode overlay", function()
        it("shows overlay when edit mode is enabled", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.ToggleUI:Enable()
            expect(f._suuui_moveable.overlay:IsShown()).eq(true)
        end)

        it("hides overlay when edit mode is disabled", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.ToggleUI:Disable()
            expect(f._suuui_moveable.overlay:IsShown()).eq(false)
        end)

        it("keeps the overlay on the frame's layer, just above it", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.UIRoot:SetLayer(f, "normal")
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            local overlay = f._suuui_moveable.overlay
            expect(overlay:GetFrameStrata()).eq(f:GetFrameStrata())
            H.expectDrawsAbove(overlay, f)
        end)

        it("does not let the overlay cover the window that toggles edit mode", function()
            local f = H.env.CreateFrame("Frame", nil,
                H.SuuUI.UIRoot:GetRootContainer():GetFrame())
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            local win = H.Layout:CreateWindow({ id = "spec_editmode_win" })
            H.SuuUI.ToggleUI:Enable()
            H.expectDrawsAbove(win:GetFrame(), f._suuui_moveable.overlay)
        end)
    end)

    describe("ResetPosition", function()
        it("resets to defaults", function()
            H.SuuUI.Settings:Set("test_plugin", "frame_position", {
                point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -100, y = -50,
            })
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.MoveableFrame:ResetPosition(f)
            local point, _, relPoint, x, y = f:GetPoint()
            expect(point).eq("TOPLEFT")
            expect(relPoint).eq("TOPLEFT")
            expect(x).eq(10)
            expect(y).eq(-20)
        end)

        it("updates settings to default value", function()
            H.SuuUI.Settings:Set("test_plugin", "frame_position", {
                point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -100, y = -50,
            })
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.MoveableFrame:ResetPosition(f)
            local pos = H.SuuUI.Settings:Get("test_plugin", "frame_position")
            expect(pos.point).eq("TOPLEFT")
            expect(pos.x).eq(10)
        end)
    end)

    describe("Remove", function()
        it("unregisters from ToggleUI", function()
            local countBefore = #H.SuuUI.ToggleUI:GetAll()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.MoveableFrame:Remove(f)
            expect(#H.SuuUI.ToggleUI:GetAll()).eq(countBefore)
        end)

        it("clears moveable data from frame", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.MoveableFrame:Remove(f)
            expect(f._suuui_moveable).isNil()
        end)
    end)

    describe("profile switch", function()
        it("restores position on profile change", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            -- Create and switch to a new profile with different position
            H.SuuUI.Profiles:Create("Alt")
            H.SuuUI.Profiles:SetActive("Alt")
            H.SuuUI.Settings:Set("test_plugin", "frame_position", {
                point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 50, y = 50,
            })
            -- Simulate profile load event
            H.SuuUI.Events:Emit("SUUUI_PROFILE_LOADED", "Alt")
            local point, _, relPoint, x, y = f:GetPoint()
            expect(point).eq("BOTTOMLEFT")
            expect(x).eq(50)
            expect(y).eq(50)
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: anchor-relative-to-parent fix (not UIParent)
    ---------------------------------------------------------------------------
    describe("REGRESSION: RestorePosition anchors to parent, not UIParent", function()
        it("restored frame is anchored relative to its parent, not UIParent", function()
            local rootContainer = H.SuuUI.UIRoot:GetRootContainer()
            local rootFrame = rootContainer:GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local _, relativeTo = f:GetPoint(1)
            -- The frame must NOT be anchored to UIParent — it should be anchored
            -- to the root container frame (or another frame in the root's tree)
            expect(relativeTo).as("must not anchor to UIParent").neq(H.UIParent)
        end)

        it("placement is correct under a non-1 pixel multiplier", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            host = H.parent(1024, 768)

            local rootContainer = H.SuuUI.UIRoot:GetRootContainer()
            local rootFrame = rootContainer:GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.Settings:Register("test_plugin", {
                { key = "frame_position", type = "position", default = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -60 } },
            })

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -60 },
            })

            -- The frame should resolve to the saved offsets in the root's unit space.
            -- Under a non-1 pixel multiplier the root carries a scale, so if placement
            -- went through UIParent the offsets would be in a different space and the
            -- on-screen position would be wrong.
            local point, relativeTo, relPoint, x, y = f:GetPoint(1)
            expect(point).eq("TOPLEFT")
            expect(relPoint).eq("TOPLEFT")
            expect(x).near(40, 1)
            expect(y).near(-60, 1)
            -- Crucially, the relativeTo must be in the root tree, not UIParent
            expect(relativeTo).neq(H.UIParent)
        end)

        it("saved position from settings resolves correctly under scale", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            host = H.parent(1024, 768)

            H.SuuUI.Settings:Register("test_plugin", {
                { key = "frame_position", type = "position", default = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 } },
            })
            H.SuuUI.Settings:Set("test_plugin", "frame_position", {
                point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -50, y = -30,
            })

            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local point, relativeTo, relPoint, x, y = f:GetPoint(1)
            expect(point).eq("TOPRIGHT")
            expect(relPoint).eq("TOPRIGHT")
            expect(x).near(-50, 1)
            expect(y).near(-30, 1)
            expect(relativeTo).as("anchored inside root tree").neq(H.UIParent)
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: Apply registers with UIRoot, no double-register
    ---------------------------------------------------------------------------
    describe("REGRESSION: Apply registers frame as UIRoot element", function()
        it("registers the frame as a UIRoot element when root exists", function()
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            -- _suuui_anchor is set by UIRoot:AddElement
            expect(f._suuui_anchor).notNil()
        end)

        it("does not double-register on a second Apply", function()
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            -- Count elements in the normal layer before second Apply
            local normalBefore = #H.SuuUI.UIRoot:GetLayerElements("normal")

            -- Remove and re-apply — simulate plugin re-init
            H.SuuUI.MoveableFrame:Remove(f)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            -- Should have same number — one entry, not two
            expect(#H.SuuUI.UIRoot:GetLayerElements("normal")).eq(normalBefore)
        end)

        it("skips UIRoot registration when _suuui_anchor already set", function()
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            -- Pre-set _suuui_anchor to simulate already registered
            f._suuui_anchor = { point = "CENTER", x = 0, y = 0 }
            local normalBefore = #H.SuuUI.UIRoot:GetLayerElements("normal")

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            -- Should NOT have added a new element
            expect(#H.SuuUI.UIRoot:GetLayerElements("normal")).eq(normalBefore)
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: overlay/backdrop/label placed by stack containers
    ---------------------------------------------------------------------------
    describe("REGRESSION: overlay geometry via containers", function()
        local function applyMounted()
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(200, 80)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "My Frame",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 0, y = 0 },
            })
            H.SuuUI.ToggleUI:Enable()
            return f
        end

        it("overlay covers the frame exactly", function()
            local f = applyMounted()
            local overlay = f._suuui_moveable.overlay
            local fBox = H.box(f)
            local oBox = H.box(overlay)
            expect(oBox).notNil()
            expect(oBox.left).near(fBox.left, 1)
            expect(oBox.top).near(fBox.top, 1)
            expect(oBox.width).near(fBox.width, 1)
            expect(oBox.height).near(fBox.height, 1)
        end)

        it("backdrop texture covers the overlay", function()
            local f = applyMounted()
            local overlay = f._suuui_moveable.overlay
            local overlayBg = f._suuui_moveable.overlayBg
            H.expectInside(overlayBg, overlay)
        end)

        it("label is centred in the overlay", function()
            local f = applyMounted()
            local overlay = f._suuui_moveable.overlay
            local label = f._suuui_moveable.label
            H.expectCenteredH(label, overlay)
            H.expectCenteredV(label, overlay)
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: label uses Text component, overlay uses theme token
    ---------------------------------------------------------------------------
    describe("REGRESSION: label is Text component, overlay uses colorEditOverlay token", function()
        it("label shows the displayName", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Player Frame",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local label = f._suuui_moveable.label
            -- Text component wraps a font string; GetText retrieves the display text
            expect(label:GetText()).eq("Player Frame")
        end)

        it("overlay tint uses the colorEditOverlay theme token", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local overlayBg = f._suuui_moveable.overlayBg
            local r, g, b, a = overlayBg:GetColorTexture()
            local tokenColor = H.token("colorEditOverlay") or { 0, 0.6, 1, 0.2 }
            expect(r).near(tokenColor[1], 0.01)
            expect(g).near(tokenColor[2], 0.01)
            expect(b).near(tokenColor[3], 0.01)
            expect(a).near(tokenColor[4], 0.01)
        end)

        it("overlay is repainted when the theme changes", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local overlayBg = f._suuui_moveable.overlayBg

            -- Read color before theme change
            local rBefore, gBefore, bBefore, aBefore = overlayBg:GetColorTexture()

            -- Emit theme change — the overlay should repaint from the token
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")

            local rAfter, gAfter, bAfter, aAfter = overlayBg:GetColorTexture()
            -- The color should still equal the token (which may or may not have changed
            -- depending on the theme, but the handler ran)
            local tokenColor = H.token("colorEditOverlay") or { 0, 0.6, 1, 0.2 }
            expect(rAfter).near(tokenColor[1], 0.01)
            expect(gAfter).near(tokenColor[2], 0.01)
            expect(bAfter).near(tokenColor[3], 0.01)
            expect(aAfter).near(tokenColor[4], 0.01)
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: Remove destroys containers, drops listener, clears placeBox
    ---------------------------------------------------------------------------
    describe("REGRESSION: Remove cleanup", function()
        it("theme change after Remove does not repaint anything", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local overlayBg = f._suuui_moveable.overlayBg
            H.SuuUI.MoveableFrame:Remove(f)

            -- Paint a sentinel colour to detect if the handler fires
            overlayBg:SetColorTexture(0.99, 0.99, 0.99, 0.99)
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")

            -- The sentinel should remain untouched — the listener was removed
            local r, g, b, a = overlayBg:GetColorTexture()
            expect(r).near(0.99, 0.01)
            expect(g).near(0.99, 0.01)
            expect(b).near(0.99, 0.01)
            expect(a).near(0.99, 0.01)
        end)

        it("clears _suuui_placeBox on Remove", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.MoveableFrame:Remove(f)
            expect(f._suuui_placeBox).isNil()
        end)

        it("destroys the overlayBox and contentBox containers", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            local overlayBox = f._suuui_moveable.overlayBox
            local contentBox = f._suuui_moveable.contentBox
            H.SuuUI.MoveableFrame:Remove(f)

            -- After Destroy, these containers should be marked destroyed
            expect(overlayBox._destroyed).eq(true)
            expect(contentBox._destroyed).eq(true)
        end)

        it("drops the SUUUI_THEME_CHANGED listener by owner", function()
            local f = H.env.CreateFrame("Frame", nil, host)
            f:SetSize(100, 50)
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })

            -- Track that the listener fires before Remove
            local fired = 0
            local origBg = f._suuui_moveable.overlayBg
            -- Capture reference before remove
            H.SuuUI.MoveableFrame:Remove(f)

            -- Register a new spy to see if the old listener owner still works
            local spyFired = false
            H.SuuUI.Events:On("SUUUI_THEME_CHANGED", function()
                spyFired = true
            end, "moveable_theme_test_plugin_frame_position")
            -- The fact that we can register with the same owner proves Off removed
            -- the old one (otherwise the old handler would have been called above)
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Modern")
            expect(spyFired).eq(true)
            -- Clean up
            H.SuuUI.Events:Off("SUUUI_THEME_CHANGED", "moveable_theme_test_plugin_frame_position")
        end)
    end)

    ---------------------------------------------------------------------------
    -- REGRESSION: OnDragStop restates anchor so root re-layout doesn't snap back
    ---------------------------------------------------------------------------
    describe("REGRESSION: OnDragStop restates anchor for root stability", function()
        it("frame stays in place after a root re-layout following drag", function()
            local rootContainer = H.SuuUI.UIRoot:GetRootContainer()
            local rootFrame = rootContainer:GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.ToggleUI:Enable()

            -- Simulate a drag: the client moves the frame to a new position, then
            -- fires OnDragStop. We emulate by clearing anchors and setting the new pos.
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 200, -100)

            -- Fire the drag stop handler (which saves position and restates anchor)
            local overlay = f._suuui_moveable.overlay
            overlay:GetScript("OnDragStop")()

            -- Record position after drag
            local boxAfterDrag = H.box(f)
            expect(boxAfterDrag).notNil()

            -- Force a root re-layout (the bug was that re-layout snapped it back)
            rootContainer:Layout()

            -- The frame must stay where the drag left it
            local boxAfterLayout = H.box(f)
            expect(boxAfterLayout.left).as("horizontal stable after relayout")
                .near(boxAfterDrag.left, 1)
            expect(boxAfterLayout.top).as("vertical stable after relayout")
                .near(boxAfterDrag.top, 1)
        end)

        it("drag saves the new position to settings", function()
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.ToggleUI:Enable()

            -- Simulate drag to new position
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 150, -75)

            local overlay = f._suuui_moveable.overlay
            overlay:GetScript("OnDragStop")()

            -- Settings should reflect the drag
            local pos = H.SuuUI.Settings:Get("test_plugin", "frame_position")
            expect(pos.point).eq("TOPLEFT")
            expect(pos.x).near(150, 1)
            expect(pos.y).near(-75, 1)
        end)

        it("drag under non-1 scale still anchors correctly after relayout", function()
            H.setup({ physicalWidth = 1920, physicalHeight = 1080 })
            host = H.parent(1024, 768)

            H.SuuUI.Settings:Register("test_plugin", {
                { key = "frame_position", type = "position", default = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 } },
            })

            local rootContainer = H.SuuUI.UIRoot:GetRootContainer()
            local rootFrame = rootContainer:GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)

            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 },
            })
            H.SuuUI.ToggleUI:Enable()

            -- Simulate drag
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 300, -200)

            local overlay = f._suuui_moveable.overlay
            overlay:GetScript("OnDragStop")()

            local boxAfterDrag = H.box(f)
            expect(boxAfterDrag).notNil()

            -- Force relayout
            rootContainer:Layout()

            local boxAfterLayout = H.box(f)
            expect(boxAfterLayout.left).as("stable horizontal under scale")
                .near(boxAfterDrag.left, 1)
            expect(boxAfterLayout.top).as("stable vertical under scale")
                .near(boxAfterDrag.top, 1)
        end)
    end)

    describe("REGRESSION: coreInset keeps content still while the frame grows", function()
        -- A frame that publishes an attach point grows around children it does not own.
        -- Growth lands on whichever edge the anchor does NOT pin, so a band appearing on
        -- the pinned edge displaces the frame's own content by that band's height. This is
        -- the bug that moved the player unit frame's bars whenever a cast bar attached
        -- below them, detached, or swapped between the above and below slot.
        --
        -- The frame is modelled directly rather than through the plugins: what is under
        -- test is the placement rule, and a bare frame states it without a unit frame's
        -- other height inputs in the way.
        local BAND = 26   -- a band plus its row gap, in units

        -- Builds a moveable frame whose reported core inset is whatever the returned
        -- setter says, so a test can grow a band without a second plugin.
        --
        -- The position is WRITTEN to settings, not merely passed as `defaults`: a stored
        -- value wins over the opt, and this key has a registered schema default of
        -- TOPLEFT/-20. Relying on `defaults` alone silently ran every case below against a
        -- TOPLEFT anchor, so the BOTTOM and CENTER branches were never reached.
        local function moveable(point, y, coreH)
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            local above, below = 0, 0
            f:SetSize(100, coreH)
            H.SuuUI.Settings:Set("test_plugin", "frame_position",
                { point = point, relPoint = point, x = 10, y = y })
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = point, relPoint = point, x = 10, y = y },
                coreInset   = function() return above, below end,
            })
            expect(select(1, f:GetPoint())).as("anchor point under test is in force").eq(point)
            -- Grows the frame the way an attach slot does: the band is INSIDE the frame,
            -- so the frame gets taller and reports the inset that band creates.
            local function setBands(a, b)
                above, below = a, b
                f:SetHeight(coreH + a + b)
                H.SuuUI.MoveableFrame:RefreshAnchor(f)
            end
            return f, setBands
        end

        -- Where the frame's own content sits, given the bands around it: the core is the
        -- slice of the frame's box left over after the insets.
        local function coreTop(f, above)
            local b = H.box(f)
            return b and (b.top + above) or nil
        end

        it("BOTTOM anchor: a band below does not move the content", function()
            local f, setBands = moveable("BOTTOMLEFT", 60, 50)
            local before = coreTop(f, 0)
            expect(before).notNil()

            setBands(0, BAND)
            expect(coreTop(f, 0)).as("content still after attaching below").near(before, 0.5)

            setBands(BAND, 0)
            expect(coreTop(f, BAND)).as("content still after moving the band above")
                .near(before, 0.5)

            setBands(0, 0)
            expect(coreTop(f, 0)).as("content still after detaching").near(before, 0.5)
        end)

        it("TOP anchor: a band above does not move the content", function()
            -- The mirror case, and the one the BOTTOM-anchored frame hid: with the top edge
            -- pinned, growth goes downward, so it is the ABOVE band that would displace the
            -- content. A fix that only shifted for one edge passes the test above and fails
            -- this one.
            local f, setBands = moveable("TOPLEFT", -60, 50)
            local before = coreTop(f, 0)

            setBands(BAND, 0)
            expect(coreTop(f, BAND)).as("content still after attaching above").near(before, 0.5)

            setBands(0, BAND)
            expect(coreTop(f, 0)).as("content still after moving the band below")
                .near(before, 0.5)
        end)

        it("CENTER anchor: the content stays centred on its own box", function()
            local f, setBands = moveable("CENTER", 0, 50)
            local before = coreTop(f, 0)

            setBands(0, BAND)
            expect(coreTop(f, 0)).as("content still after attaching below").near(before, 0.5)

            setBands(BAND, 0)
            expect(coreTop(f, BAND)).as("content still after moving the band above")
                .near(before, 0.5)
        end)

        it("stores the content position, not the bounding box, so a drag cannot creep", function()
            -- The compensation is applied on read and removed on write. If only one half
            -- existed, every drag would bake the inset in again and the frame would walk
            -- one band height per drag.
            local f, setBands = moveable("BOTTOMLEFT", 60, 50)
            setBands(0, BAND)
            H.SuuUI.ToggleUI:Enable()

            local overlay = f._suuui_moveable.overlay
            local firstBox
            for i = 1, 3 do
                overlay:GetScript("OnDragStop")()
                H.SuuUI.UIRoot:GetRootContainer():Layout()
                local b = H.box(f)
                firstBox = firstBox or b
                expect(b.top).as("no vertical creep on drag " .. i).near(firstBox.top, 0.5)
                expect(H.SuuUI.Settings:Get("test_plugin", "frame_position").y)
                    .as("stored y is the content's, unchanged by drag " .. i).near(60, 0.5)
            end
        end)

        it("leaves a frame without a coreInset provider untouched", function()
            -- The detached cast bar and every other moveable frame take this path, so the
            -- default must be a genuine no-op rather than a zero that still re-anchors.
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)
            H.SuuUI.Settings:Set("test_plugin", "frame_position",
                { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 10, y = 60 })
            H.SuuUI.MoveableFrame:Apply(f, {
                pluginId    = "test_plugin",
                key         = "frame_position",
                displayName = "Test",
                defaults    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 10, y = 60 },
            })
            local _, _, _, _, y = f:GetPoint()
            expect(y).as("offset passes through unshifted").near(60, 0.5)
        end)

        it("survives a provider that errors instead of unwinding into the layout", function()
            -- The provider belongs to a plugin and runs on every placement pass, so a
            -- throwing one must degrade to no compensation rather than take the frame's
            -- position — or the client's frame — with it.
            local rootFrame = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            local f = H.env.CreateFrame("Frame", nil, rootFrame)
            f:SetSize(100, 50)
            H.SuuUI.Settings:Set("test_plugin", "frame_position",
                { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 10, y = 60 })
            expect(function()
                H.SuuUI.MoveableFrame:Apply(f, {
                    pluginId    = "test_plugin",
                    key         = "frame_position",
                    displayName = "Test",
                    defaults    = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 10, y = 60 },
                    coreInset   = function() error("plugin bug") end,
                })
            end).notThrows()
            local _, _, _, _, y = f:GetPoint()
            expect(y).as("falls back to no compensation").near(60, 0.5)
        end)
    end)
end)
