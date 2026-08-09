local H = require("harness")

-- The player frame's dimensions are plugin settings, not theme tokens: assert against the
-- live setting so the specs state the rule rather than a pixel count.
local function setting(key)
    return H.SuuUI.Settings:Get("unit_frames", key)
end

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

            -- Asserted through the reader, not the schema's shape: per-unit keys are
            -- declared inside their unit's tab, so scanning only the top level would
            -- report a working setting as missing.
            expect(H.SuuUI.Settings:Get("unit_frames", "enabled")).notNil()
            expect(H.SuuUI.Settings:Get("unit_frames", "player_enabled")).notNil()
        end)

        it("defaults enabled to true", function()
            expect(H.SuuUI.Settings:Get("unit_frames", "enabled")).eq(true)
        end)

        it("defaults player_enabled to true", function()
            expect(H.SuuUI.Settings:Get("unit_frames", "player_enabled")).eq(true)
        end)

        it("registers the frame dimensions with defaults", function()
            for _, key in ipairs({ "player_width", "player_health_height",
                                   "player_power_height" }) do
                expect(H.SuuUI.Settings:Get("unit_frames", key))
                    .as(key .. " resolves a default").notNil()
            end
        end)
    end)

    describe("Blizzard frame hiding", function()
        it("hides the Blizzard PlayerFrame when enabled", function()
            local blizFrame = H.env.PlayerFrame
            expect(blizFrame:IsShown()).eq(false)
        end)
    end)

    describe("player frame creation", function()
        it("creates a player frame with all structural sub-widgets", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            -- Not just non-nil: verify the full composition tree exists
            expect(pf._wrapper).notNil()
            expect(pf._root).notNil()
            expect(pf._infoRow).notNil()
            expect(pf._bars).notNil()
            expect(pf._healthBar).notNil()
            expect(pf._resourceBar).notNil()
            expect(pf._nameText).notNil()
            expect(pf._levelText).notNil()
            -- The bars container is a child of root
            expect(pf._bars:GetFrame():GetParent()).eq(pf._wrapper)
            expect(pf._infoRow:GetFrame():GetParent()).eq(pf._wrapper)
        end)

        it("player frame produces a correctly sized renderable widget", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local frame = pf:GetFrame()
            -- The frame is a real renderable widget with resolved geometry
            expect(frame:GetWidth()).gt(0)
            expect(frame:GetHeight()).gt(0)
            -- It is token-derived, not a magic number
            H.expectSize(frame, setting("player_width"), nil)
            local infoH = H.lineHeight(H.token("fontSizeLg"))
            H.expectSize(frame, nil,
                infoH + H.token("spaceXs")
                + setting("player_health_height") + H.token("spaceXxs")
                + setting("player_power_height"))
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
            H.expectSize(frame, setting("player_width"),
                infoH + H.token("spaceXs")
                + setting("player_health_height") + H.token("spaceXxs")
                + setting("player_power_height"))
        end)

        it("reports its intrinsic size, so the plugin needs no magic numbers", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local frame = plugin._playerFrame:GetFrame()
            local w, h = plugin._playerFrame:GetPreferredSize()
            H.expectSize(frame, w, h)
        end)

        it("takes its width from the unit frame size token", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            H.expectSize(pf:GetFrame(), setting("player_width"), nil)
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
            H.expectSize(pf._infoRow, setting("player_width"),
                H.lineHeight(H.token("fontSizeLg")))
        end)

        it("bar group sits below the info row, one info gap down", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local infoH = H.lineHeight(H.token("fontSizeLg"))
            H.expectOffset(pf._bars, pf._wrapper, 0, infoH + H.token("spaceXs"))
            H.expectSize(pf._bars, setting("player_width"),
                setting("player_health_height") + H.token("spaceXxs")
                + setting("player_power_height"))
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
            H.expectSize(pf._healthBar, setting("player_width"), setting("player_health_height"))
            H.expectSize(pf._resourceBar, setting("player_width"), setting("player_power_height"))
            expect(setting("player_health_height")).as("health is the taller bar")
                .gt(setting("player_power_height"))
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

        it("re-lays out when the health bar height setting changes", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local before = select(2, pf:GetPreferredSize())

            H.SuuUI.Settings:Set("unit_frames", "player_health_height",
                setting("player_health_height") + 12)

            H.expectSize(pf._healthBar, nil, setting("player_health_height"))
            H.expectSize(pf:GetFrame(), setting("player_width"), before + 12)
        end)

        it("re-lays out when the frame width setting changes", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            H.SuuUI.Settings:Set("unit_frames", "player_width", setting("player_width") + 40)
            H.expectSize(pf:GetFrame(), setting("player_width"), nil)
            H.expectSize(pf._healthBar, setting("player_width"), nil)
            H.expectSize(pf._resourceBar, setting("player_width"), nil)
        end)

        it("re-lays out when the resource bar height setting changes", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local before = select(2, pf:GetPreferredSize())
            H.SuuUI.Settings:Set("unit_frames", "player_power_height",
                setting("player_power_height") + 6)
            H.expectSize(pf._resourceBar, nil, setting("player_power_height"))
            H.expectSize(pf:GetFrame(), nil, before + 6)
        end)

        it("dimensions live in the plugin's settings, not the theme", function()
            local T = H.SuuUI.Theme
            -- A widget's own size is not design language: it must not be a theme token.
            expect(T:GetToken("sizeUnitFrameW")).isNil()
            expect(T:GetToken("sizeUnitHealthBar")).isNil()
            expect(T:GetToken("sizeUnitPowerBar")).isNil()
            expect(setting("player_width")).notNil()
            expect(setting("player_health_height")).notNil()
            expect(setting("player_power_height")).notNil()
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
            H.expectSize(pf._resourceBar, setting("player_width"), setting("player_power_height"))
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
            -- The bar ships with a fill transition, so assert where the fill settles.
            H.runAnimations()
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
        it("registers all required game events for player unit updates", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            local evFrame = pf._events
            expect(evFrame).notNil()
            -- The widget depends on these events; missing any means stale display data
            local required = {
                "UNIT_HEALTH",
                "UNIT_MAXHEALTH",
                "UNIT_POWER_UPDATE",
                "UNIT_MAXPOWER",
                "UNIT_DISPLAYPOWER",
                "PLAYER_ENTERING_WORLD",
                "PLAYER_LEVEL_UP",
                "UNIT_LEVEL",
            }
            for _, event in ipairs(required) do
                expect(evFrame:IsEventRegistered(event))
                    .as("must register " .. event).eq(true)
            end
        end)

        it("has an OnEvent script handler attached", function()
            local plugin = H.SuuUI.Plugins:Get("unit_frames")
            local pf = plugin._playerFrame
            expect(pf._events:GetScript("OnEvent")).notNil()
        end)
    end)

    describe("status bar fill composition (layout-engine placement)", function()
        -- These tests guard against a regression back to hand-anchored SetPoint fills.
        -- The fill is now a widthFraction child of a stack container on the track frame,
        -- and the texture is a stack child of the fill frame.

        it("health fill sits inside the track at 0%, 50%, and 100%", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local bar = pf._healthBar
            -- 0%
            bar:SetMax(100)
            bar:SetValue(0)
            -- The player frame's bars ship with a fill transition, so every assertion
            -- here is about where the fill settles, not where it is a frame later.
            H.runAnimations()
            -- fill hidden at 0%: test it's inside by checking fill frame width ≤ track width
            expect(bar._fillFrame:GetWidth()).as("0% fill width").eq(0)

            -- 50%
            bar:SetValue(50)
            H.runAnimations()
            H.expectInside(bar._fillFrame, bar)
            local trackBox = H.box(bar)
            local fillBox = H.box(bar._fillFrame)
            expect(fillBox.left).as("50% fill left-aligned with track").eq(trackBox.left)
            expect(fillBox.right).as("50% fill does not exceed track")
                .lt(trackBox.right + 0.5)

            -- 100%
            bar:SetValue(100)
            H.runAnimations()
            H.expectInside(bar._fillFrame, bar)
            local fullBox = H.box(bar._fillFrame)
            expect(fullBox.left).eq(trackBox.left)
            expect(math.abs(fullBox.right - trackBox.right)).as("100% fill reaches track edge")
                .lt(0.5)
        end)

        it("resource fill sits inside the track at 0%, 50%, and 100%", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local bar = pf._resourceBar
            bar:SetMax(100)

            bar:SetValue(0)
            H.runAnimations()
            expect(bar._fillFrame:GetWidth()).as("0% fill width").eq(0)

            bar:SetValue(50)
            H.runAnimations()
            H.expectInside(bar._fillFrame, bar)
            local trackBox = H.box(bar)
            local fillBox = H.box(bar._fillFrame)
            expect(fillBox.left).eq(trackBox.left)
            expect(fillBox.right).lt(trackBox.right + 0.5)

            bar:SetValue(100)
            H.runAnimations()
            H.expectInside(bar._fillFrame, bar)
            local fullBox = H.box(bar._fillFrame)
            expect(fullBox.left).eq(trackBox.left)
            expect(math.abs(fullBox.right - trackBox.right)).lt(0.5)
        end)

        it("fill spans the full height of its borderless track (inset is 0)", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            -- Both bars are created with border = false, so no inset
            for _, bar in ipairs({pf._healthBar, pf._resourceBar}) do
                bar:SetMax(100)
                bar:SetValue(75)
                local trackBox = H.box(bar)
                local fillBox = H.box(bar._fillFrame)
                expect(fillBox.top).as("fill top equals track top").eq(trackBox.top)
                expect(fillBox.bottom).as("fill bottom equals track bottom").eq(trackBox.bottom)
                expect(fillBox.height).as("fill height equals track height")
                    .eq(trackBox.height)
            end
        end)

        it("fill texture covers its fill frame exactly", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local bar = pf._healthBar
            bar:SetMax(100)
            bar:SetValue(60)
            local tex = bar._bar  -- the texture
            local fillFrame = bar._fillFrame
            -- Texture is a stack child of fillFrame, so it should match exactly
            H.expectInside(tex, fillFrame)
            local texBox = H.box(tex)
            local ffBox = H.box(fillFrame)
            expect(math.abs(texBox.left - ffBox.left)).lt(0.5)
            expect(math.abs(texBox.right - ffBox.right)).lt(0.5)
            expect(math.abs(texBox.top - ffBox.top)).lt(0.5)
            expect(math.abs(texBox.bottom - ffBox.bottom)).lt(0.5)
        end)

        it("resizing the track re-derives fill width from stored fraction (no SetValue needed)", function()
            -- Use a standalone StatusBar so we can control the track width directly,
            -- without the player frame's fixed-width token resetting it.
            local bar = H.SuuUI.Components.StatusBar({
                fillColor = {0.22, 0.78, 0.32, 1},
                bgColor   = {0, 0, 0, 0.35},
                border    = false,
            }, host)
            bar:GetFrame():SetSize(200, 20)
            bar:SetMax(100)
            bar:SetValue(50)

            -- Record current state: fill should be 50% of track
            local trackW1 = bar:GetFrame():GetWidth()
            local fillW1 = bar._fillFrame:GetWidth()
            expect(math.abs(fillW1 - trackW1 * 0.5)).as("fill is 50% of 200").lt(0.5)

            -- Resize the track directly — no SetValue call
            bar:GetFrame():SetWidth(300)

            -- The layout engine re-derives the fill from the stored fraction
            local trackW2 = bar:GetFrame():GetWidth()
            local fillW2 = bar._fillFrame:GetWidth()
            expect(trackW2).as("track accepted new width").eq(300)
            expect(math.abs(fillW2 - 300 * 0.5)).as("fill re-derives at new track width").lt(0.5)
            expect(fillW2).as("fill actually changed from old value").neq(fillW1)
        end)

        it("at 0% the fill is hidden, and becomes shown again above sub-pixel", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local bar = pf._healthBar
            bar:SetMax(100)

            -- Set to 0%
            bar:SetValue(0)
            H.runAnimations()
            expect(bar._fillFrame:IsShown()).as("hidden at 0%").eq(false)

            -- Set to a small but visible value
            bar:SetValue(5)
            H.runAnimations()
            expect(bar._fillFrame:IsShown()).as("shown above sub-pixel threshold").eq(true)

            -- Back to 0%
            bar:SetValue(0)
            H.runAnimations()
            expect(bar._fillFrame:IsShown()).as("hidden again at 0%").eq(false)
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
