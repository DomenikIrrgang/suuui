
-- A cold login with an attached cast bar, replayed from a real saved profile.
--
-- The existing attached-mode specs build the bar from schema defaults on an already-booted
-- client, which is the path a settings change takes. This one replays the path a LOGIN
-- takes, against non-default sizes, because a bar that is correct when re-attached by hand
-- and wrong after /reload can only differ in what was ready at the moment it attached.

local PLUGIN_ID = "cast_bars"

-- The player's own profile, trimmed to what decides layout. Non-default sizes throughout:
-- a bar that inherits a stale width or height reports a DEFAULT here, not a wrong number,
-- which is what makes the failure legible.
local BAR_H    = 40
local FRAME_W  = 336
local HEALTH_H = 60
local POWER_H  = 31

local function seedProfile()
    -- Named "Default" so the character fallback selects it: an unlinked character loads
    -- Default, and seeding a differently-named profile would silently test schema defaults
    -- instead of a real save.
    H.env.SuuUIProfiles = {
        profiles = {
            Default = {
                plugins = {
                    cast_bars = {
                        player_enabled         = true,
                        player_anchor          = "attached",
                        player_attach_position = "below",
                        player_height          = BAR_H,
                        player_show_icon       = true,
                        player_show_name       = true,
                        player_show_time       = true,
                        player_time_format     = "both",
                    },
                    unit_frames = {
                        enabled                 = true,
                        player_enabled          = true,
                        player_width            = FRAME_W,
                        player_health_height    = HEALTH_H,
                        player_power_height     = POWER_H,
                        player_show_name        = true,
                        player_show_level       = true,
                        player_hide_level_at_max = false,
                    },
                    _layout = { edit_mode = false },
                },
            },
        },
        charMap = {},
    }
end

local function boot()
    -- debug = true so anything a pcall swallowed shows up: plugin callbacks, attach-point
    -- notifications and coreInset providers all run guarded and log through SuuUI.Debug,
    -- which is OFF in a real client — so a login-time exception is otherwise invisible.
    H.setup({ boot = false, debug = true })
    seedProfile()
    H.fireEvent("ADDON_LOADED", "SuuUI")
    H.fireEvent("PLAYER_LOGIN")
end

local function ctl()
    local p = H.SuuUI.Plugins:Get(PLUGIN_ID)
    return p and p._controllers and p._controllers.player
end

describe("Plugins.CastBars – attached bar after a cold login", function()
    before_each(function()
        local state = require("harness.wow.state")
        state.unitHealth, state.unitHealthMax = 80, 100
        state.unitPower,  state.unitPowerMax  = 60, 100
        state.unitPowerType = 0
        state.unitLevel, state.maxPlayerLevel = 42, 60
        boot()
    end)

    it("logs no failure on the way up", function()
        -- A silent failure is the failure mode this whole spec exists to catch: onInit,
        -- onEnable, attach-point notifications and the coreInset provider are all pcall'd,
        -- so a throw during login leaves no trace in a real client.
        --
        -- Only failure lines count. Debug mode is chatty by design ("UI Root initialized"),
        -- and asserting an empty log would make this test fail for every new trace line
        -- anyone adds — which is how a useful assertion turns into one people delete.
        local bad = {}
        for _, line in ipairs(H.debugLog() or {}) do
            local text = tostring(line)
            if text:lower():find("fail") or text:lower():find("error") then
                bad[#bad + 1] = text
            end
        end
        expect(#bad).as("swallowed: " .. table.concat(bad, " | ")).eq(0)
    end)

    it("builds a bar and attaches it", function()
        expect(ctl()).as("controller exists").notNil()
        expect(ctl():GetMode()).as("attached").eq("attached")
        expect(ctl():GetBar()).notNil()
    end)

    it("the bar is as wide as the unit frame, not zero and not the default", function()
        local bar = ctl():GetBar()
        expect(bar:GetWidth()).as("bar width tracks the frame").near(FRAME_W, 1)
    end)

    it("the bar keeps the height the profile asked for", function()
        expect(ctl():GetBar():GetHeight()).near(BAR_H, 1)
    end)

    it("has a real on-screen box", function()
        local box = H.box(ctl():GetBar():GetFrame())
        expect(box).as("resolvable geometry").notNil()
        expect(box.width).as("on-screen width").near(FRAME_W, 1)
        expect(box.height).as("on-screen height").near(BAR_H, 1)
    end)

    it("the content is full width once a cast starts", function()
        local bar = ctl():GetBar()
        H.startCast({ name = "Fireball", duration = 2.5 })
        expect(bar._row:IsShown()).as("content shown").eq(true)
        local row = H.box(bar._row:GetFrame())
        expect(row).notNil()
        expect(row.width).as("content row width").near(FRAME_W, 1)
        expect(row.height).as("content row height").near(BAR_H, 1)
    end)

    -- The assertion that matches what the client reports. A frame reports its SET size
    -- whether or not it has an anchor, so every size assertion above passes for a frame
    -- that has nowhere to be — and the client simply does not draw it. GetTop() is nil
    -- exactly then, which is what the live bar reported: state preview, row shown, 335x40,
    -- fill 175 wide, and no position.
    it("the bar has a resolved position, not just a size", function()
        local f = ctl():GetBar():GetFrame()
        expect(f:GetTop()).as("bar frame GetTop()").notNil()
        expect(f:GetLeft()).as("bar frame GetLeft()").notNil()
    end)

    it("the slot holding it has a resolved position too", function()
        local p = H.SuuUI.Plugins:Get("unit_frames")
        local slot = p._playerFrame._slotBelow
        expect(slot:IsShown()).as("slot shown").eq(true)
        expect(slot:GetFrame():GetTop()).as("slot frame GetTop()").notNil()
    end)

    it("the bar sits below the unit frame's bars, inside the frame", function()
        local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
        H.expectInside(ctl():GetBar():GetFrame(), pf:GetFrame())
    end)

    it("the content is opaque once a cast starts", function()
        local bar = ctl():GetBar()
        H.startCast({ name = "Fireball", duration = 2.5 })
        expect(bar._row:GetFrame():GetAlpha()).as("content row alpha").near(1, 0.001)
        expect(bar:GetFrame():GetAlpha()).as("wrapper alpha").near(1, 0.001)
    end)

    -- The invariant behind the whole bug, asserted directly because the simulated client
    -- cannot show the consequence: it resolves an anchor chain the real one leaves
    -- unresolved, so a child anchored to a hidden frame looks perfectly placed here and
    -- draws nothing in game. Assert the ORDER instead — the slot must already have a rect
    -- when the child is anchored to it.
    it("shows the slot before adding the child", function()
        local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
        -- slotAbove is still empty and hidden after a login that attached below.
        local slot = pf._slotAbove
        expect(slot:IsShown()).as("slot starts hidden").eq(false)

        local shownAtAdd
        local realAdd = slot.Add
        slot.Add = function(self_, ...)
            shownAtAdd = self_:IsShown()
            return realAdd(self_, ...)
        end

        local probe = H.C.Frame({ w = 100, h = 10 }, pf:GetFrame())
        pf:AttachChild(probe, { position = "above" })
        slot.Add = realAdd

        expect(shownAtAdd).as("slot visible when the child was anchored to it").eq(true)
        expect(slot:IsShown()).as("still shown afterwards").eq(true)
    end)

    it("the fill has width once a cast starts", function()
        local bar = ctl():GetBar()
        H.startCast({ name = "Fireball", duration = 4.0 })
        H.tick(2.0)
        local track = H.box(bar._bar:GetFrame())
        expect(track).notNil()
        expect(track.width > 0).as("bar track has width").eq(true)
    end)

    ---------------------------------------------------------------------------
    -- Edit-mode preview inside the reserved band.
    --
    -- This is what the player actually looks at when arranging frames, and it is the one
    -- state that shows the bar without a spell: band reserved but empty means the content
    -- row was never given a box, which every assertion above would still pass.
    ---------------------------------------------------------------------------
    describe("edit-mode preview", function()
        local function preview()
            H.SuuUI.ToggleUI:Enable()
            return ctl():GetBar()
        end

        it("enters preview state with its content shown", function()
            local bar = preview()
            expect(bar:GetState()).eq("preview")
            expect(bar._row:IsShown()).as("content row shown").eq(true)
        end)

        it("the content row fills the reserved band", function()
            local bar = preview()
            local row = H.box(bar._row:GetFrame())
            expect(row).as("row has resolvable geometry").notNil()
            expect(row.width).as("row width").near(FRAME_W, 2)
            expect(row.height).as("row height").near(BAR_H, 2)
        end)

        it("the row sits inside the bar's own box, not over the bars above it", function()
            local bar = preview()
            H.expectInside(bar._row:GetFrame(), bar:GetFrame())
        end)

        it("the icon is visible and square", function()
            local bar = preview()
            expect(bar._icon:IsShown()).as("icon shown").eq(true)
            local icon = H.box(bar._icon:GetFrame())
            expect(icon).notNil()
            expect(icon.width > 0).as("icon has width").eq(true)
            expect(icon.width).as("square").near(icon.height, 2)
            H.expectInside(bar._icon:GetFrame(), bar:GetFrame())
        end)

        it("the preview fill has real width", function()
            local bar = preview()
            expect(bar._bar:GetPercent()).as("preview fraction").near(0.6, 0.01)
            local fill = H.box(bar._bar._fillFrame)
            expect(fill).as("fill has geometry").notNil()
            expect(fill.width > 0).as("fill has width").eq(true)
            H.expectInside(bar._bar._fillFrame, bar:GetFrame())
        end)

        it("the preview is opaque", function()
            -- The measurement no size or visibility assertion can make. A row at alpha 0
            -- reports the right state, the right box, a shown icon and IsVisible() true,
            -- and draws absolutely nothing — which is exactly the symptom in game.
            local bar = preview()
            expect(bar:GetFrame():GetAlpha()).as("wrapper alpha").near(1, 0.001)
            expect(bar._row:GetFrame():GetAlpha()).as("content row alpha").near(1, 0.001)
            expect(bar._bar:GetFrame():GetAlpha()).as("bar alpha").near(1, 0.001)
            expect(bar._icon:GetFrame():GetAlpha()).as("icon alpha").near(1, 0.001)
        end)

        it("the name reads the unit's display name and is not clipped", function()
            local bar = preview()
            expect(bar._nameText:GetText()).eq("Player Cast Bar")
            H.expectTextNotClipped(bar._nameText:GetFrame())
        end)
    end)
end)
