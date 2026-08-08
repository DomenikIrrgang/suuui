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
        it("fires SUUUI_EDIT_MODE_CHANGED on toggle", function()
            local received = nil
            H.SuuUI.Events:On("SUUUI_EDIT_MODE_CHANGED", function(val)
                received = val
            end, "test_toggle")
            H.SuuUI.ToggleUI:Toggle()
            expect(received).eq(true)
        end)

        it("fires event with false when toggling off", function()
            H.SuuUI.ToggleUI:Enable()
            local received = nil
            H.SuuUI.Events:On("SUUUI_EDIT_MODE_CHANGED", function(val)
                received = val
            end, "test_toggle_off")
            H.SuuUI.ToggleUI:Toggle()
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
end)
