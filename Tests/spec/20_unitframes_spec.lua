local H = require("harness")

describe("Plugins.UnitFrames", function()
    local host, state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth = 80
        state.unitHealthMax = 100
        state.unitPower = 60
        state.unitPowerMax = 100
        state.unitPowerType = 0  -- Mana
        state.reloadUICalled = 0
        H.setup()
        host = H.parent(1024, 768)
    end)

    describe("plugin registration", function()
        it("registers the unit_frames plugin", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            expect(plugin).notNil()
            expect(plugin.id).eq("unit_frames")
            expect(plugin.name).eq("Unit Frames")
        end)

        it("is enabled by default after boot", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            expect(plugin:IsEnabled()).eq(true)
        end)
    end)

    describe("settings schema", function()
        it("registers settings schema with required keys", function()
            local schema = H.SuuUI.Settings:GetSchema("unit_frames")
            expect(schema).notNil()
            expect(#schema).gt(0)

            local found_enabled = false
            local found_player = false
            for _, entry in ipairs(schema) do
                if entry.key == "enabled" then found_enabled = true end
                if entry.key == "player_enabled" then found_player = true end
            end
            expect(found_enabled).eq(true)
            expect(found_player).eq(true)
        end)

        it("defaults enabled to true", function()
            expect(H.SuuUI.Settings:Get("unit_frames", "enabled")).eq(true)
        end)

        it("defaults player_enabled to true", function()
            expect(H.SuuUI.Settings:Get("unit_frames", "player_enabled")).eq(true)
        end)
    end)

    describe("Blizzard frame hiding", function()
        it("hides the Blizzard PlayerFrame when enabled", function()
            local blizFrame = H.env.PlayerFrame
            expect(blizFrame:IsShown()).eq(false)
        end)
    end)

    describe("player frame creation", function()
        it("creates a player frame when enabled", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            expect(plugin._playerFrame).notNil()
        end)

        it("player frame has a valid frame", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            expect(plugin._playerFrame:GetFrame()).notNil()
        end)
    end)

    describe("health bar", function()
        it("displays current health value", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._healthBar:GetValue()).eq(80)
            expect(pf._healthBar:GetMax()).eq(100)
        end)

        it("shows correct health percentage", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._healthBar:GetPercent()).near(0.8, 0.001)
        end)

        it("uses green health colour", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._healthBar._fillColor[1]).near(0.22, 0.01)
            expect(pf._healthBar._fillColor[2]).near(0.78, 0.01)
            expect(pf._healthBar._fillColor[3]).near(0.32, 0.01)
        end)
    end)

    describe("resource bar", function()
        it("displays current power value", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._resourceBar:GetValue()).eq(60)
            expect(pf._resourceBar:GetMax()).eq(100)
        end)

        it("uses mana colour for power type 0", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._resourceBar._fillColor[1]).near(0.00, 0.01)
            expect(pf._resourceBar._fillColor[2]).near(0.44, 0.01)
            expect(pf._resourceBar._fillColor[3]).near(0.87, 0.01)
        end)

        it("uses rage colour for power type 1", function()
            state.unitPowerType = 1
            H.setup()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._resourceBar._fillColor[1]).near(0.77, 0.01)
            expect(pf._resourceBar._fillColor[2]).near(0.12, 0.01)
            expect(pf._resourceBar._fillColor[3]).near(0.23, 0.01)
        end)

        it("uses energy colour for power type 3", function()
            state.unitPowerType = 3
            H.setup()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._resourceBar._fillColor[1]).near(1.00, 0.01)
            expect(pf._resourceBar._fillColor[2]).near(0.96, 0.01)
            expect(pf._resourceBar._fillColor[3]).near(0.41, 0.01)
        end)
    end)

    describe("info display", function()
        it("shows the player name", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._nameText:GetText()).eq("Testchar")
        end)

        it("shows the player level", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._levelText:GetText()).eq("60")
        end)
    end)

    describe("reload guard", function()
        it("registers reload guard for enabled setting", function()
            expect(H.SuuUI.ReloadGuard:IsGuarded("unit_frames", "enabled")).eq(true)
        end)

        it("registers reload guard for player_enabled setting", function()
            expect(H.SuuUI.ReloadGuard:IsGuarded("unit_frames", "player_enabled")).eq(true)
        end)

        it("reverts the setting when changed (before modal confirm)", function()
            -- Changing enabled from true to false should be reverted by the guard
            H.SuuUI.Settings:Set("unit_frames", "player_enabled", false)
            -- Guard reverts it back to true
            expect(H.SuuUI.Settings:Get("unit_frames", "player_enabled")).eq(true)
        end)

        it("plugin stays enabled when setting change is guarded", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            H.SuuUI.Settings:Set("unit_frames", "enabled", false)
            -- Guard reverts — plugin still enabled
            expect(plugin:IsEnabled()).eq(true)
            expect(H.SuuUI.Settings:Get("unit_frames", "enabled")).eq(true)
        end)
    end)

    describe("event handling", function()
        it("creates event frame for updates", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._events).notNil()
        end)
    end)
end)

describe("Core.ReloadGuard", function()
    local state

    before_each(function()
        state = require("harness.wow.state")
        state.reloadUICalled = 0
        H.setup()
    end)

    describe("registration", function()
        it("registers a guard for a plugin setting", function()
            H.SuuUI.ReloadGuard:Register("test_plugin", "my_setting", {
                title   = "Test Reload",
                message = "Needs reload.",
            })
            expect(H.SuuUI.ReloadGuard:IsGuarded("test_plugin", "my_setting")).eq(true)
        end)

        it("returns false for unguarded settings", function()
            expect(H.SuuUI.ReloadGuard:IsGuarded("nonexistent", "nope")).falsy()
        end)

        it("unregisters a guard", function()
            H.SuuUI.ReloadGuard:Register("test_plugin", "rm_me", {})
            H.SuuUI.ReloadGuard:Unregister("test_plugin", "rm_me")
            expect(H.SuuUI.ReloadGuard:IsGuarded("test_plugin", "rm_me")).eq(false)
        end)
    end)

    describe("setting interception", function()
        it("reverts a guarded setting change immediately", function()
            -- Register a schema and guard for a test plugin
            H.SuuUI.Settings:Register("guard_test", {
                { key = "feature", label = "Feature", type = "toggle", default = true },
            })
            H.SuuUI.ReloadGuard:Register("guard_test", "feature", {
                message = "Needs reload.",
            })

            -- Change the setting
            H.SuuUI.Settings:Set("guard_test", "feature", false)
            -- Should be reverted
            expect(H.SuuUI.Settings:Get("guard_test", "feature")).eq(true)
        end)

        it("does not revert unguarded settings", function()
            H.SuuUI.Settings:Register("guard_test2", {
                { key = "safe", label = "Safe", type = "toggle", default = true },
            })

            H.SuuUI.Settings:Set("guard_test2", "safe", false)
            expect(H.SuuUI.Settings:Get("guard_test2", "safe")).eq(false)
        end)
    end)
end)
