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
        state.unitLevel = 42     -- below the cap, so the level is visible by default
        state.maxPlayerLevel = 60
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

        it("GetFrame returns the wrapper that holds the info row and the bars", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local topFrame = pf:GetFrame()
            expect(topFrame).eq(pf._wrapper)
            expect(topFrame).neq(pf._bars:GetFrame())
            expect(topFrame).neq(pf._infoRow:GetFrame())
        end)

        it("frame is sized to fit info row + gap + bar group", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local frame = pf:GetFrame()
            local infoH = H.lineHeight(H.token("fontSizeLg"))
            H.expectSize(frame, H.token("sizeUnitFrameW"),
                infoH + H.token("spaceXs")
                + H.token("sizeUnitHealthBar") + H.token("spaceXxs")
                + H.token("sizeUnitPowerBar"))
        end)

        it("reports its intrinsic size, so the plugin needs no magic numbers", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local frame = plugin._playerFrame:GetFrame()
            local w, h = plugin._playerFrame:GetPreferredSize()
            H.expectSize(frame, w, h)
        end)

        it("takes its width from the unit frame size token", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            H.expectSize(pf:GetFrame(), H.token("sizeUnitFrameW"), nil)
        end)
    end)

    describe("player frame layout", function()
        it("info row is parented to the wrapper", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local infoParent = pf._infoRow:GetFrame():GetParent()
            expect(infoParent).eq(pf._wrapper)
        end)

        it("bar group is parented to the wrapper", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._bars:GetFrame():GetParent()).eq(pf._wrapper)
        end)

        it("info row sits at the top of the wrapper", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            H.expectOffset(pf._infoRow, pf._wrapper, 0, 0)
            H.expectSize(pf._infoRow, H.token("sizeUnitFrameW"),
                H.lineHeight(H.token("fontSizeLg")))
        end)

        it("bar group sits below the info row, one info gap down", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local infoH = H.lineHeight(H.token("fontSizeLg"))
            H.expectOffset(pf._bars, pf._wrapper, 0, infoH + H.token("spaceXs"))
            H.expectSize(pf._bars, H.token("sizeUnitFrameW"),
                H.token("sizeUnitHealthBar") + H.token("spaceXxs")
                + H.token("sizeUnitPowerBar"))
        end)

        it("health and resource bars are parented to the bar group", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local barsFrame = pf._bars:GetFrame()
            expect(pf._healthBar:GetFrame():GetParent()).eq(barsFrame)
            expect(pf._resourceBar:GetFrame():GetParent()).eq(barsFrame)
        end)

        it("bars span the full frame width — no inset plate around them", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local wrapBox = H.box(pf._wrapper)
            local healthBox = H.box(pf._healthBar)
            expect(healthBox.left).eq(wrapBox.left)
            expect(healthBox.right).eq(wrapBox.right)
        end)

        it("bar heights come from the unit bar size tokens", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            H.expectSize(pf._healthBar, H.token("sizeUnitFrameW"), H.token("sizeUnitHealthBar"))
            H.expectSize(pf._resourceBar, H.token("sizeUnitFrameW"), H.token("sizeUnitPowerBar"))
            expect(H.token("sizeUnitHealthBar")).as("health is the taller bar")
                .gt(H.token("sizeUnitPowerBar"))
        end)

        it("resource bar sits directly under the health bar", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local hb, rb = H.box(pf._healthBar), H.box(pf._resourceBar)
            expect(rb.top).as("one bar gap below the health bar")
                .eq(hb.bottom + H.token("spaceXxs"))
        end)

        it("bars reach the bottom of the frame", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(H.box(pf._resourceBar).bottom).eq(H.box(pf._wrapper).bottom)
        end)

        it("re-derives the layout when a size token changes", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local T = H.SuuUI.Theme
            local before = select(2, pf:GetPreferredSize())

            -- A user theme is required: built-ins are read-only by design.
            T:CreateUserTheme("TokenProbe", T:GetActive())
            T:SetActive("TokenProbe")
            T:SetUserToken("TokenProbe", "sizeUnitHealthBar", H.token("sizeUnitHealthBar") + 12)

            H.expectSize(pf._healthBar, nil, H.token("sizeUnitHealthBar"))
            H.expectSize(pf:GetFrame(), H.token("sizeUnitFrameW"), before + 12)
        end)
    end)

    describe("minimal styling", function()
        it("has no backing plate frame behind the bars", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._bg).isNil()
        end)

        it("paints no background on the wrapper", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(H.backdropColor(pf._wrapper)).isNil()
        end)

        it("paints no background behind the name row", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(H.backdropColor(pf._infoRow)).isNil()
            expect(H.backdropColor(pf._bars)).isNil()
        end)

        it("uses a translucent track behind a bar fill, not the opaque panel colour", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local track = H.backdropColor(pf._healthBar)
            expect(track).notNil()
            expect(track[4]).as("track opacity comes from the token")
                .near(H.token("opacityBarTrack"), 0.001)
            expect(track[4]).lt(H.token("opacityPanel"))
        end)

        it("an empty resource bar still covers the bar's full box", function()
            state.unitPowerType = 1  -- rage, and a warrior starts at 0
            state.unitPower = 0
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._resourceBar:GetPercent()).eq(0)
            expect(pf._resourceBar._fillFrame:IsShown()).as("no fill at 0 rage").eq(false)
            -- The track is the bar frame itself, so the empty bar is still a full-width
            -- strip rather than a sliver that does not line up with the health bar.
            H.expectSize(pf._resourceBar, H.token("sizeUnitFrameW"), H.token("sizeUnitPowerBar"))
            expect(H.box(pf._resourceBar).left).eq(H.box(pf._healthBar).left)
            expect(H.box(pf._resourceBar).right).eq(H.box(pf._healthBar).right)
        end)

        it("a full bar's fill lines up with the empty bar's track", function()
            state.unitPowerType = 1
            state.unitPower = 0
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local emptyBox = H.box(pf._resourceBar)
            -- Same bar, now full: the fill must land on the track's own edges
            pf._resourceBar:SetValue(pf._resourceBar:GetMax())
            local fillBox = H.box(pf._resourceBar._fillFrame)
            expect(fillBox.left).eq(emptyBox.left)
            expect(fillBox.right).eq(emptyBox.right)
            expect(fillBox.top).eq(emptyBox.top)
            expect(fillBox.bottom).eq(emptyBox.bottom)
        end)

        it("draws no border around the bars", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(H.borderColor(pf._healthBar)[4]).eq(0)
            expect(H.borderColor(pf._resourceBar)[4]).eq(0)
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

        it("shows the level beside the name below max level", function()
            state.unitLevel = 42
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:GetText()).eq("42")
            expect(pf._levelText:IsShown()).eq(true)
        end)

        it("puts the level immediately right of the name, not at the far edge", function()
            state.unitLevel = 42
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local nameBox, levelBox = H.box(pf._nameText), H.box(pf._levelText)
            local gap = H.token("spaceXs")
            expect(levelBox.left).as("one gap right of the name").eq(nameBox.right + gap)
            expect(levelBox.right).as("nowhere near the frame's right edge")
                .lt(H.box(pf._wrapper).right - 10)
        end)

        it("starts the name at the left edge of the frame", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(H.box(pf._nameText).left).eq(H.box(pf._wrapper).left)
        end)

        it("sizes the name to its own text rather than leaving it pinned at zero", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            H.expectSize(pf._nameText, H.textWidth("Testchar", H.token("fontSizeLg")), nil)
            H.expectTextNotClipped(pf._nameText)
        end)

        it("hides the level at max level", function()
            state.unitLevel = 60
            state.maxPlayerLevel = 60
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:GetText()).eq("")
            expect(pf._levelText:IsShown()).eq(false)
        end)

        it("hides the level above max level too", function()
            state.unitLevel = 61
            state.maxPlayerLevel = 60
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:IsShown()).eq(false)
        end)

        it("shows the level again when the cap moves up", function()
            state.unitLevel = 60
            state.maxPlayerLevel = 70
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:GetText()).eq("60")
            expect(pf._levelText:IsShown()).eq(true)
        end)

        it("collapses the level to zero width once hidden", function()
            state.unitLevel = 60
            state.maxPlayerLevel = 60
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:GetWidth()).eq(0)
        end)

        it("re-measures the level after a level-up", function()
            state.unitLevel = 8
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local narrow = pf._levelText:GetWidth()

            state.unitLevel = 48
            pf:UpdateInfo()
            expect(pf._levelText:GetText()).eq("48")
            expect(pf._levelText:GetWidth()).as("two digits are wider than one").gt(narrow)
        end)

        it("hides the level when PLAYER_LEVEL_UP reaches the cap", function()
            state.unitLevel = 59
            state.maxPlayerLevel = 60
            H.setup()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            expect(pf._levelText:IsShown()).eq(true)

            -- The event carries the new level ahead of UnitLevel catching up
            pf._events:GetScript("OnEvent")(pf._events, "PLAYER_LEVEL_UP", 60)
            expect(pf._levelText:IsShown()).eq(false)
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
