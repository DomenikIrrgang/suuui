
local PLUGIN_ID = "unit_frames"

local function setting(key)
    return H.SuuUI.Settings:Get(PLUGIN_ID, key)
end

local function set(key, value)
    H.SuuUI.Settings:Set(PLUGIN_ID, key, value)
end

local function plugin()
    return H.SuuUI.Plugins:Get(PLUGIN_ID)
end

local function pf() return plugin()._playerFrame end
local function tf() return plugin()._targetFrame end

-- Which mode the bar is in is a question about its PARENT, so it is asked of the frame
-- chain rather than of the handle's own bookkeeping: a mode flag that disagreed with where
-- the frame actually sits is exactly the bug worth catching.
local function descendsFrom(frame, ancestor)
    local cur = frame and frame:GetParent()
    while cur do
        if cur == ancestor then return true end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

local function inlined(widget)
    return descendsFrom(widget._resourceBar:GetFrame(), widget:GetFrame())
end

describe("Plugins.UnitFrames – detachable resource bar", function()
    before_each(function()
        local state = require("harness.wow.state")
        state.unitHealth    = 100
        state.unitHealthMax = 100
        state.unitPower     = 80
        state.unitPowerMax  = 100
        state.unitPowerType = 0
        state.unitLevel     = 42
        state.maxPlayerLevel = 60
        H.setup()
    end)

    describe("inline by default", function()
        it("defaults to attached", function()
            expect(setting("player_power_anchor")).eq("attached")
        end)

        it("builds the bar inside the frame", function()
            expect(pf()._resourceBar).notNil()
            expect(inlined(pf())).as("resource bar is part of the frame").truthy()
        end)

        it("has no detached wrapper while inline", function()
            expect(pf()._resourceWrapper).isNil()
        end)

        it("sits below the health bar", function()
            local health   = H.box(pf()._healthBar)
            local resource = H.box(pf()._resourceBar)
            expect(health).notNil()
            expect(resource).notNil()
            expect(resource.top).as("resource below health").gt(health.bottom - 1)
        end)

        it("takes the frame's width, not the detached slider's", function()
            expect(pf()._resourceBar:GetWidth()).near(setting("player_width"), 1)
        end)

        it("ignores the detached width slider while inline", function()
            set("player_power_width", 150)
            expect(pf()._resourceBar:GetWidth())
                .as("an inline bar still fills the frame").near(setting("player_width"), 1)
        end)

        it("follows the frame width slider", function()
            set("player_width", 350)
            expect(pf()._resourceBar:GetWidth()).near(350, 1)
        end)
    end)

    describe("detaching", function()
        it("takes the bar out of the frame", function()
            set("player_power_anchor", "detached")
            expect(pf()._resourceBar).as("still a bar").notNil()
            expect(inlined(pf())).as("no longer inside the frame").falsy()
        end)

        it("parents the bar under the UI root instead", function()
            set("player_power_anchor", "detached")
            local root = H.SuuUI.UIRoot:GetRootContainer():GetFrame()
            expect(descendsFrom(pf()._resourceBar:GetFrame(), root)).truthy()
        end)

        it("owns its own width", function()
            set("player_power_width", 200)
            set("player_power_anchor", "detached")
            expect(pf()._resourceWrapper:GetWidth()).near(200, 1)
        end)

        it("keeps its height setting", function()
            set("player_power_anchor", "detached")
            expect(pf()._resourceWrapper:GetHeight()).near(setting("player_power_height"), 1)
        end)

        it("resizes when the width slider moves", function()
            set("player_power_anchor", "detached")
            set("player_power_width", 260)
            expect(pf()._resourceWrapper:GetWidth()).near(260, 1)
        end)

        it("resizes when the height slider moves", function()
            set("player_power_anchor", "detached")
            set("player_power_height", 30)
            expect(pf()._resourceWrapper:GetHeight()).near(30, 1)
        end)

        it("becomes moveable under its own position key", function()
            set("player_power_anchor", "detached")
            local data = pf()._resourceWrapper._suuui_moveable
            expect(data).as("detached bar is draggable").notNil()
            expect(data.key).eq("player_power_position")
        end)

        it("does not share the frame's position key", function()
            set("player_power_anchor", "detached")
            expect(pf()._resourceWrapper._suuui_moveable.key)
                .as("its own key, so dragging one does not move the other")
                .neq("player_position")
        end)

        it("shrinks the frame by the bar and its gap", function()
            local attached = pf():GetFrame():GetHeight()
            set("player_power_anchor", "detached")
            local detached = pf():GetFrame():GetHeight()
            expect(attached).as("frame loses the bar band and the gap above it")
                .near(detached + setting("player_power_height") + H.token("spaceXxs"), 1)
        end)

        it("leaves the health bar filling the frame width", function()
            set("player_power_anchor", "detached")
            expect(pf()._healthBar:GetWidth()).near(setting("player_width"), 1)
        end)
    end)

    describe("values and readouts survive the move", function()
        it("carries a readout chosen before detaching", function()
            set("player_power_text_center", "current_max")
            set("player_power_anchor", "detached")
            expect(pf()._resourceBar:GetText("center"))
                .as("the rebuilt bar re-reads its readout settings").eq("80 / 100")
        end)

        it("carries the readout font step", function()
            set("player_power_text_size", "lg")
            set("player_power_anchor", "detached")
            expect(pf()._resourceBar:GetTextSize()).eq("lg")
        end)

        it("accepts a readout change while detached", function()
            set("player_power_anchor", "detached")
            set("player_power_text_center", "percent")
            expect(pf()._resourceBar:GetText("center")).eq("80%")
        end)

        it("shows the current value immediately after detaching", function()
            set("player_power_anchor", "detached")
            H.runAnimations()
            expect(pf()._resourceBar:GetDisplayPercent())
                .as("adopted outright, not swept up from empty").near(0.8, 0.01)
        end)

        it("still follows power events while detached", function()
            set("player_power_anchor", "detached")
            H.setUnit("player", { power = 25, powerMax = 100 })
            H.fireEvent("UNIT_POWER_UPDATE", "player")
            H.runAnimations()
            expect(pf()._resourceBar:GetPercent()).near(0.25, 0.01)
        end)

        it("still recolours on a power type change while detached", function()
            set("player_power_anchor", "detached")
            H.setUnit("player", { powerType = 3 })
            H.fireEvent("UNIT_DISPLAYPOWER", "player")
            local energy = H.SuuUI.Game:PowerColor(3)
            local fill = pf()._resourceBar._fillColor
            expect(fill).notNil()
            expect(fill[1]).near(energy[1], 0.01)
            expect(fill[2]).near(energy[2], 0.01)
            expect(fill[3]).near(energy[3], 0.01)
        end)
    end)

    describe("re-inlining", function()
        it("puts the bar back inside the frame", function()
            set("player_power_anchor", "detached")
            set("player_power_anchor", "attached")
            expect(inlined(pf())).truthy()
        end)

        it("puts it back UNDER the health bar, not above it", function()
            set("player_power_anchor", "detached")
            set("player_power_anchor", "attached")
            local health   = H.box(pf()._healthBar)
            local resource = H.box(pf()._resourceBar)
            expect(resource.top).as("insertion order restored").gt(health.bottom - 1)
        end)

        it("restores the frame height", function()
            local before = pf():GetFrame():GetHeight()
            set("player_power_anchor", "detached")
            set("player_power_anchor", "attached")
            expect(pf():GetFrame():GetHeight()).near(before, 1)
        end)

        it("drops the detached wrapper", function()
            set("player_power_anchor", "detached")
            local wrapper = pf()._resourceWrapper
            set("player_power_anchor", "attached")
            expect(pf()._resourceWrapper).isNil()
            expect(wrapper._suuui_moveable).as("no longer draggable").isNil()
            expect(wrapper:IsShown()).eq(false)
        end)

        it("goes back to filling the frame width", function()
            set("player_power_width", 150)
            set("player_power_anchor", "detached")
            set("player_power_anchor", "attached")
            expect(pf()._resourceBar:GetWidth()).near(setting("player_width"), 1)
        end)
    end)

    describe("a mode that has not changed is left alone", function()
        it("writing the same anchor value does not rebuild the bar", function()
            local bar = pf()._resourceBar
            set("player_power_anchor", "attached")
            expect(pf()._resourceBar).as("same handle: no needless rebuild").eq(bar)
        end)
    end)

    describe("watchers and teardown", function()
        it("a detach and re-inline round trip leaks no watchers", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("player_power_anchor", "detached")
            set("player_power_anchor", "attached")
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("rebuilding the bar is watcher-neutral").eq(before)
        end)

        it("releases a detached bar on plugin disable", function()
            set("player_power_anchor", "detached")
            local wrapper = pf()._resourceWrapper
            plugin():Disable()
            expect(wrapper._suuui_moveable)
                .as("no draggable ghost left on screen").isNil()
            expect(wrapper:IsShown()).eq(false)
        end)

        it("leaves no watchers behind after a disable while detached", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("player_power_anchor", "detached")
            plugin():Disable()
            expect(H.SuuUI.Settings:GetWatcherCount()).lte(before)
        end)
    end)

    describe("presence reaches a detached bar", function()
        it("a detached target bar is hidden with no target", function()
            set("target_power_anchor", "detached")
            expect(tf():GetFrame():IsShown()).as("no target, no frame").eq(false)
            expect(tf()._resourceWrapper:IsShown())
                .as("the bar is outside the wrapper, so it needs hiding of its own")
                .eq(false)
        end)

        it("a detached target bar appears with a target", function()
            set("target_power_anchor", "detached")
            H.setTarget({ name = "Hogger", level = 11, classless = true, reaction = 2,
                          health = 50, healthMax = 100, power = 40, powerMax = 100 })
            expect(tf()._resourceWrapper:IsShown()).eq(true)
        end)

        it("a detached target bar appears in edit mode with no target", function()
            set("target_power_anchor", "detached")
            H.SuuUI.ToggleUI:Enable()
            expect(tf()._resourceWrapper:IsShown())
                .as("has to be findable to be dragged").eq(true)
        end)

        it("hides again when the target is lost", function()
            set("target_power_anchor", "detached")
            H.setTarget({ name = "Boar", level = 3, classless = true, reaction = 2,
                          health = 20, healthMax = 20 })
            H.setTarget(nil)
            expect(tf()._resourceWrapper:IsShown()).eq(false)
        end)

        it("the player's detached bar is always shown", function()
            set("player_power_anchor", "detached")
            expect(pf()._resourceWrapper:IsShown())
                .as("the player unit always exists").eq(true)
        end)
    end)

    describe("the two units are independent", function()
        it("detaching the player's bar leaves the target's inline", function()
            set("player_power_anchor", "detached")
            expect(inlined(tf())).as("target untouched").truthy()
        end)

        it("detaching the target's bar leaves the player's inline", function()
            set("target_power_anchor", "detached")
            expect(inlined(pf())).truthy()
        end)
    end)
end)
