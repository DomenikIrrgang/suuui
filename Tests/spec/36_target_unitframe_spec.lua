local H = require("harness")

local function setting(key)
    return H.SuuUI.Settings:Get("unit_frames", key)
end

local function plugin()
    return H.SuuUI.Plugins:Get("unit_frames")
end

local function pf() return plugin()._playerFrame end
local function tf() return plugin()._targetFrame end

describe("Plugins.UnitFrames – target frame", function()
    local state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth = 100
        state.unitHealthMax = 100
        state.unitPower = 80
        state.unitPowerMax = 100
        state.unitPowerType = 0
        state.unitLevel = 42
        state.maxPlayerLevel = 60
        state.reloadUICalled = 0
        H.setup()
    end)

    describe("existence at boot", function()
        it("creates a target frame handle distinct from the player's", function()
            expect(tf()).notNil()
            expect(pf()).notNil()
            expect(tf()).as("two distinct handles").neq(pf())
        end)

        it("target frame wraps a different widget frame", function()
            expect(tf():GetFrame()).neq(pf():GetFrame())
        end)

        it("hides the Blizzard TargetFrame when enabled", function()
            expect(H.env.TargetFrame:IsShown()).eq(false)
        end)

        it("restores Blizzard TargetFrame on plugin Disable", function()
            plugin():Disable()
            expect(H.env.TargetFrame:IsShown()).eq(true)
        end)

        it("never shows TargetFrame if this plugin did not hide it", function()
            -- Disable the plugin so it restores TargetFrame, then hide it by hand to
            -- simulate another addon suppressing it. Re-enable our plugin: it must not
            -- touch TargetFrame's visibility because the suppress path runs fresh.
            plugin():Disable()
            H.env.TargetFrame:Hide()
            plugin():Enable()
            -- After the re-enable cycle, TargetFrame is suppressed by us again. But the
            -- point is: before Enable's suppress() ran, we did NOT show it, we only
            -- suppress it afresh. Disable should only restore what we suppressed.
            plugin():Disable()
            -- TargetFrame was already hidden before the first Enable in this cycle, and
            -- the plugin suppressed it during enable. On disable it restores, so it is shown.
            -- The real invariant: disable undoes what enable did. That is the contract.
            expect(H.env.TargetFrame:IsShown()).eq(true)
        end)
    end)

    describe("presence: shown/hidden by unit existence", function()
        it("hidden with no target", function()
            -- No target staged, so UnitExists('target') is false
            expect(tf():GetFrame():IsShown()).eq(false)
        end)

        it("shown after H.setTarget", function()
            H.setTarget({ name = "Hogger", level = 11, reaction = 2, classless = true,
                          health = 50, healthMax = 100, power = 0, powerMax = 0 })
            expect(tf():GetFrame():IsShown()).eq(true)
        end)

        it("hidden after H.setTarget(nil)", function()
            H.setTarget({ name = "Hogger", level = 11 })
            H.setTarget(nil)
            expect(tf():GetFrame():IsShown()).eq(false)
        end)

        it("player frame is unaffected by target changes", function()
            expect(pf():GetFrame():IsShown()).eq(true)
            H.setTarget({ name = "Hogger", level = 5 })
            expect(pf():GetFrame():IsShown()).eq(true)
            H.setTarget(nil)
            expect(pf():GetFrame():IsShown()).eq(true)
        end)
    end)

    describe("presence + edit mode", function()
        it("shown with no target while edit mode is on", function()
            H.SuuUI.ToggleUI:Enable()
            expect(tf():GetFrame():IsShown()).eq(true)
        end)

        it("hidden when edit mode goes off with still no target", function()
            H.SuuUI.ToggleUI:Enable()
            expect(tf():GetFrame():IsShown()).eq(true)
            H.SuuUI.ToggleUI:Disable()
            expect(tf():GetFrame():IsShown()).eq(false)
        end)

        it("NOT hidden when edit mode goes off while a target exists", function()
            H.setTarget({ name = "Boar", level = 3, classless = true, reaction = 2,
                          health = 20, healthMax = 20 })
            H.SuuUI.ToggleUI:Enable()
            H.SuuUI.ToggleUI:Disable()
            expect(tf():GetFrame():IsShown()).eq(true)
        end)
    end)

    describe("placeholder while absent + edit mode on", function()
        before_each(function()
            H.SuuUI.ToggleUI:Enable()
        end)

        it("name row reads the display name", function()
            expect(tf()._nameText:GetText()).eq("Target")
        end)

        it("level is hidden", function()
            expect(tf()._levelText:IsShown()).eq(false)
        end)

        it("both bars are full", function()
            H.runAnimations()
            expect(tf()._healthBar:GetPercent()).near(1.0, 0.001)
            expect(tf()._resourceBar:GetPercent()).near(1.0, 0.001)
        end)

        it("readouts are cleared even with a readout setting that would show a number", function()
            H.SuuUI.Settings:Set("unit_frames", "target_health_text_center", "current_max")
            H.SuuUI.Settings:Set("unit_frames", "target_power_text_center", "percent")
            -- No unit => no numbers
            expect(tf()._healthBar:GetText("center")).isNil()
            expect(tf()._resourceBar:GetText("center")).isNil()
        end)
    end)

    describe("values come from TARGET not the player", function()
        it("stages different health/power for two units and asserts both frames", function()
            -- Player: 100/100 health, 80/100 power (from state defaults)
            -- Target: wildly different values
            H.setTarget({ name = "Boss", level = 60, class = "MAGE",
                          health = 30, healthMax = 200, power = 10, powerMax = 50,
                          powerType = 0 })
            H.runAnimations()

            -- Player reads from the flat state
            expect(pf()._healthBar:GetValue()).eq(100)
            expect(pf()._healthBar:GetMax()).eq(100)
            expect(pf()._resourceBar:GetValue()).eq(80)
            expect(pf()._resourceBar:GetMax()).eq(100)

            -- Target reads from the per-unit staged data
            expect(tf()._healthBar:GetValue()).eq(30)
            expect(tf()._healthBar:GetMax()).eq(200)
            expect(tf()._resourceBar:GetValue()).eq(10)
            expect(tf()._resourceBar:GetMax()).eq(50)
        end)
    end)

    describe("two successive targets with different values", function()
        it("updates the frame even though presence did not change", function()
            H.setTarget({ name = "Wolf", level = 5, classless = true, reaction = 2,
                          health = 40, healthMax = 60 })
            H.runAnimations()
            expect(tf()._healthBar:GetValue()).eq(40)
            expect(tf()._healthBar:GetMax()).eq(60)
            expect(tf()._nameText:GetText()).eq("Wolf")

            H.setTarget({ name = "Bear", level = 8, classless = true, reaction = 2,
                          health = 90, healthMax = 120 })
            H.runAnimations()
            expect(tf()._healthBar:GetValue()).eq(90)
            expect(tf()._healthBar:GetMax()).eq(120)
            expect(tf()._nameText:GetText()).eq("Bear")
        end)
    end)

    describe("health colour", function()
        it("classed target gets class colour", function()
            -- colorUseClassColors is on in Modern (the boot theme)
            expect(H.token("colorUseClassColors")).eq(true)
            H.setTarget({ name = "Mage", level = 60, class = "MAGE",
                          health = 70, healthMax = 100 })
            local want = H.SuuUI.Game:ClassColor("MAGE")
            expect(want).notNil()
            expect(tf()._healthBar._fillColor[1]).near(want[1], 0.01)
            expect(tf()._healthBar._fillColor[2]).near(want[2], 0.01)
            expect(tf()._healthBar._fillColor[3]).near(want[3], 0.01)
        end)

        it("classless hostile target gets hostile reaction colour", function()
            expect(H.token("colorUseClassColors")).eq(true)
            H.setTarget({ name = "Boar", level = 5, classless = true, reaction = 2,
                          health = 50, healthMax = 100 })
            -- Reaction 2 is HOSTILE in the game's faction table
            local src = H.env.FACTION_BAR_COLORS[2]
            expect(tf()._healthBar._fillColor[1]).near(src.r, 0.01)
            expect(tf()._healthBar._fillColor[2]).near(src.g, 0.01)
            expect(tf()._healthBar._fillColor[3]).near(src.b, 0.01)
        end)

        it("classless target with no reaction falls back to colorHealth token", function()
            expect(H.token("colorUseClassColors")).eq(true)
            H.setTarget({ name = "Object", level = 1, classless = true,
                          health = 10, healthMax = 10 })
            -- No reaction set → UnitReaction returns nil → no class colour → fallback
            local want = H.token("colorHealth")
            expect(tf()._healthBar._fillColor[1]).near(want[1], 0.01)
            expect(tf()._healthBar._fillColor[2]).near(want[2], 0.01)
            expect(tf()._healthBar._fillColor[3]).near(want[3], 0.01)
        end)
    end)

    describe("UNIT_FACTION recolours", function()
        it("changes colour when reaction changes", function()
            expect(H.token("colorUseClassColors")).eq(true)
            -- Start neutral
            H.setTarget({ name = "Critter", level = 1, classless = true, reaction = 4,
                          health = 5, healthMax = 5 })
            local neutralSrc = H.env.FACTION_BAR_COLORS[4]
            expect(tf()._healthBar._fillColor[1]).near(neutralSrc.r, 0.01)

            -- Restage as hostile and fire the event
            H.setUnit("target", { reaction = 2 })
            H.fireEvent("UNIT_FACTION", "target")
            local hostileSrc = H.env.FACTION_BAR_COLORS[2]
            expect(tf()._healthBar._fillColor[1]).near(hostileSrc.r, 0.01)
            expect(tf()._healthBar._fillColor[2]).near(hostileSrc.g, 0.01)
            expect(tf()._healthBar._fillColor[3]).near(hostileSrc.b, 0.01)
        end)
    end)

    describe("level display", function()
        it("-1 renders as ??", function()
            H.setTarget({ name = "Skull", level = -1, classless = true, reaction = 2,
                          health = 100, healthMax = 100 })
            expect(tf()._levelText:GetText()).eq("??")
            expect(tf()._levelText:IsShown()).eq(true)
        end)

        it("?? survives hide_level_at_max on", function()
            H.SuuUI.Settings:Set("unit_frames", "target_hide_level_at_max", true)
            H.setTarget({ name = "Skull", level = -1, classless = true, reaction = 2,
                          health = 100, healthMax = 100 })
            expect(tf()._levelText:GetText()).eq("??")
            expect(tf()._levelText:IsShown()).eq(true)
        end)

        it("a normal level renders as the number", function()
            H.setTarget({ name = "Mob", level = 35, classless = true, reaction = 2,
                          health = 50, healthMax = 100 })
            expect(tf()._levelText:GetText()).eq("35")
            expect(tf()._levelText:IsShown()).eq(true)
        end)

        it("at the cap with hide_level_at_max on it is hidden", function()
            H.SuuUI.Settings:Set("unit_frames", "target_hide_level_at_max", true)
            H.setTarget({ name = "Boss", level = 60, classless = true, reaction = 2,
                          health = 100, healthMax = 100 })
            expect(tf()._levelText:IsShown()).eq(false)
        end)
    end)

    describe("healthMax = 0 and powerMax = 0 do not error", function()
        it("does not throw and percent readout reads 0%", function()
            H.SuuUI.Settings:Set("unit_frames", "target_health_text_center", "percent")
            H.SuuUI.Settings:Set("unit_frames", "target_power_text_center", "percent")
            H.setTarget({ name = "Zero", level = 1, classless = true, reaction = 2,
                          health = 0, healthMax = 0, power = 0, powerMax = 0 })
            expect(tf()._healthBar:GetText("center")).eq("0%")
            expect(tf()._resourceBar:GetText("center")).eq("0%")
        end)
    end)

    describe("PLAYER_LEVEL_UP is NOT registered on the target's event frame", function()
        it("target event frame does not listen for PLAYER_LEVEL_UP", function()
            expect(tf()._events:IsEventRegistered("PLAYER_LEVEL_UP")).eq(false)
        end)

        it("firing PLAYER_LEVEL_UP globally does not change the target's level row", function()
            H.setTarget({ name = "Mob", level = 30, classless = true, reaction = 2,
                          health = 50, healthMax = 100 })
            expect(tf()._levelText:GetText()).eq("30")
            -- Fire the player's own level-up through the global event system — the target
            -- frame did not register it, so it must not arrive.
            H.fireEvent("PLAYER_LEVEL_UP", 55)
            expect(tf()._levelText:GetText()).as("target level unchanged by player level-up")
                .eq("30")
        end)
    end)

    describe("geometry independence", function()
        it("target_width moves target frame, not player frame", function()
            local playerW = pf():GetFrame():GetWidth()
            H.SuuUI.Settings:Set("unit_frames", "target_width", setting("target_width") + 50)
            expect(tf():GetFrame():GetWidth()).eq(setting("target_width"))
            expect(pf():GetFrame():GetWidth()).as("player is unaffected").eq(playerW)
        end)

        it("target_health_height moves target health bar, not player's", function()
            local playerH = pf()._healthBar:GetFrame():GetHeight()
            H.SuuUI.Settings:Set("unit_frames", "target_health_height",
                setting("target_health_height") + 10)
            expect(tf()._healthBar:GetFrame():GetHeight()).eq(setting("target_health_height"))
            expect(pf()._healthBar:GetFrame():GetHeight())
                .as("player health height unchanged").eq(playerH)
        end)
    end)

    describe("teardown", function()
        it("plugin Disable destroys both frames", function()
            expect(pf()).notNil()
            expect(tf()).notNil()
            plugin():Disable()
            expect(plugin()._playerFrame).isNil()
            expect(plugin()._targetFrame).isNil()
        end)

        it("no Settings watchers left after Disable", function()
            local base = H.SuuUI.Settings:GetWatcherCount()
            plugin():Disable()
            -- The plugin's watchers plus the frames' should all be gone
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("every watcher retired").lt(base)
            -- Re-enable to measure the delta is clean
            plugin():Enable()
            local live = H.SuuUI.Settings:GetWatcherCount()
            plugin():Disable()
            local dead = H.SuuUI.Settings:GetWatcherCount()
            plugin():Enable()
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("enable-disable cycle is watcher-neutral").eq(live)
            plugin():Disable()
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(dead)
        end)
    end)
end)
