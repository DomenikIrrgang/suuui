local H = require("harness")

local PLUGIN_ID = "cast_bars"

local function setting(key)
    return H.SuuUI.Settings:Get(PLUGIN_ID, key)
end

local function plugin()
    return H.SuuUI.Plugins:Get(PLUGIN_ID)
end

local function targetCtl()
    return plugin()._controllers and plugin()._controllers.target
end

local function playerCtl()
    return plugin()._controllers and plugin()._controllers.player
end

local function targetBar()
    local ctl = targetCtl()
    return ctl and ctl:GetBar()
end

local function playerBar()
    local ctl = playerCtl()
    return ctl and ctl:GetBar()
end

local function targetFrame()
    return H.SuuUI.Plugins:Get("unit_frames")._targetFrame
end

local function subtabsEntry()
    for _, entry in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN_ID)) do
        if entry.type == "subtabs" then return entry end
    end
end

local function targetTab()
    local st = subtabsEntry()
    if not st then return nil end
    for _, tab in ipairs(st.tabs) do
        if tab.id == "target" then return tab end
    end
end

describe("Plugins.CastBars – Target Cast Bar", function()
    before_each(function()
        local state = require("harness.wow.state")
        state.unitHealth    = 80
        state.unitHealthMax = 100
        state.unitPower     = 60
        state.unitPowerMax  = 100
        state.unitPowerType = 0
        state.unitLevel     = 42
        state.maxPlayerLevel = 60
        state.reloadUICalled = 0
        H.setup()
        -- The target frame shows only when UnitExists("target") is true, so stage a target
        -- to make the frame — and its attach slot — visible.
        H.setTarget({ name = "Boss", level = 60, reaction = 2 })
    end)

    ---------------------------------------------------------------------------
    -- 1. Controller existence and mode
    ---------------------------------------------------------------------------
    describe("controller at boot", function()
        it("target controller exists, distinct from player", function()
            local tc = targetCtl()
            local pc = playerCtl()
            expect(tc).as("target controller exists").notNil()
            expect(pc).as("player controller exists").notNil()
            expect(tc).as("distinct objects").neq(pc)
        end)

        it("target controller reports 'attached' mode", function()
            expect(targetCtl():GetMode()).eq("attached")
        end)

        it("target controller bar exists", function()
            expect(targetBar()).notNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Attaches to the TARGET frame, not the player
    ---------------------------------------------------------------------------
    describe("attach target", function()
        it("bar is a descendant of the target frame wrapper", function()
            local bar = targetBar()
            local tfFrame = targetFrame():GetFrame()
            local cur = bar:GetFrame():GetParent()
            local found = false
            while cur do
                if cur == tfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("target bar inside target frame subtree").truthy()
        end)

        it("bar is NOT inside the player frame subtree", function()
            local bar = targetBar()
            local pfFrame = H.SuuUI.Plugins:Get("unit_frames")._playerFrame:GetFrame()
            local cur = bar:GetFrame():GetParent()
            local found = false
            while cur do
                if cur == pfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("target bar not inside player frame").falsy()
        end)

        it("player frame slots do not contain the target bar", function()
            local pf = H.SuuUI.Plugins:Get("unit_frames")._playerFrame
            local barFrame = targetBar():GetFrame()
            -- Walk player frame's slots to verify no slot holds the target bar
            for _, slot in ipairs({ pf._slotAbove, pf._slotBelow }) do
                if slot then
                    for _, child in ipairs(slot:GetChildren()) do
                        local cf = H.frameOf(child)
                        expect(cf).as("player slot does not hold target bar").neq(barFrame)
                    end
                end
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. Unit isolation
    ---------------------------------------------------------------------------
    describe("unit isolation", function()
        it("a cast on 'player' drives the player bar and leaves the target idle", function()
            H.startCast({ unit = "player", name = "Fireball", duration = 2.5 })
            local pb = playerBar()
            local tb = targetBar()
            expect(pb._row:IsShown()).as("player bar content shown").eq(true)
            expect(pb._nameText:GetText()).as("player bar name").eq("Fireball")
            expect(tb._row:IsShown()).as("target bar content hidden").eq(false)
            expect(tb:IsCasting()).as("target bar not casting").eq(false)
        end)

        it("a cast on 'target' drives the target bar and leaves the player idle", function()
            H.startCast({ unit = "target", name = "Shadow Bolt", duration = 3.0 })
            local pb = playerBar()
            local tb = targetBar()
            expect(tb._row:IsShown()).as("target bar content shown").eq(true)
            expect(tb._nameText:GetText()).as("target bar name").eq("Shadow Bolt")
            expect(pb._row:IsShown()).as("player bar content hidden").eq(false)
            expect(pb:IsCasting()).as("player bar not casting").eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. PLAYER_TARGET_CHANGED clears a target cast in flight
    ---------------------------------------------------------------------------
    describe("PLAYER_TARGET_CHANGED clears cast", function()
        it("losing the target hides the bar and ends casting", function()
            H.startCast({ unit = "target", name = "Shadow Bolt", duration = 3.0 })
            local tb = targetBar()
            expect(tb._row:IsShown()).as("content shown before").eq(true)
            expect(tb:IsCasting()).eq(true)
            -- Losing the target is enough on its own: the client reports nothing about a
            -- unit that is not there, so UnitCastingInfo("target") goes nil with it and
            -- Refresh takes the same path a cast ending does.
            H.setTarget(nil)
            expect(tb._row:IsShown()).as("content hidden after losing target").eq(false)
            expect(tb:GetState()).eq("idle")
            expect(tb:IsCasting()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. Acquiring a target that IS casting picks it up
    ---------------------------------------------------------------------------
    describe("acquiring a casting target", function()
        it("picks up the in-flight cast on target acquisition", function()
            -- Clear target first
            H.setTarget(nil)
            local tb = targetBar()
            expect(tb:IsCasting()).eq(false)

            -- Stage a cast on "target" in the state, then acquire the target
            local state = require("harness.wow.state")
            local nowMS = (state.clock or 0) * 1000
            state.cast = {
                unit      = "target",
                name      = "Heal",
                texture   = "Interface\\Icons\\Spell_Holy_Heal",
                startTime = nowMS,
                endTime   = nowMS + 3000,
                castID    = "cast-target-1",
                spellId   = 2054,
                notInterruptible = false,
                isTradeSkill     = false,
            }
            -- Acquire a target: this fires PLAYER_TARGET_CHANGED, which the widget uses
            -- to Refresh()
            H.setTarget({ name = "Healer", level = 60, reaction = 2 })

            tb = targetBar()
            expect(tb:IsCasting()).as("picked up in-flight cast").eq(true)
            expect(tb._nameText:GetText()).eq("Heal")
            expect(tb._row:IsShown()).eq(true)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. TargetFrameSpellBar suppression
    --
    -- TargetFrameSpellBar is a CHILD of Blizzard's TargetFrame. The UnitFrames plugin
    -- hides TargetFrame, which means OnShow never fires for the spell bar's hook while
    -- both plugins are active — the parent is hidden, so Show() is a no-op for visibility
    -- scripts. To test the hook in isolation, these tests disable the UnitFrames plugin so
    -- TargetFrame stays shown (which is the scenario where the cast bars plugin's own
    -- suppression actually matters).
    ---------------------------------------------------------------------------
    describe("TargetFrameSpellBar suppression", function()
        before_each(function()
            -- Disable unit frames so Blizzard's TargetFrame is shown (restored), allowing
            -- the spell bar's OnShow hook to fire. Re-setup with target for the cast bars
            -- plugin to suppress it.
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            -- TargetFrame is now visible (restored by UF's onDisable).
        end)

        it("is hidden after boot (when cast bars enabled)", function()
            -- With UF disabled but cast bars still up, TargetFrameSpellBar is suppressed
            -- by the cast bars plugin directly.
            local bar = H.env.TargetFrameSpellBar
            expect(bar).as("TargetFrameSpellBar exists").notNil()
            expect(bar:IsShown()).eq(false)
        end)

        it("keeps its events so it can be handed back alive", function()
            local bar = H.env.TargetFrameSpellBar
            local count = 0
            if bar._events then
                for _ in pairs(bar._events) do count = count + 1 end
            end
            expect(count).as("events left where Blizzard put them").gt(0)
        end)

        it("stays hidden when something shows it again", function()
            local bar = H.env.TargetFrameSpellBar
            bar:Show()
            expect(bar:IsShown()).as("re-show is defeated").eq(false)
        end)

        it("stays hidden when its own event handler shows it", function()
            H.fireEvent("PLAYER_ENTERING_WORLD")
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("event-driven re-show is defeated").eq(false)
        end)

        it("is shown again when the cast bars plugin is disabled", function()
            H.SuuUI.Plugins:Get(PLUGIN_ID):Disable()
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("restored on disable").eq(true)
        end)

        it("stays shown after a disable, not re-hidden by the hook", function()
            H.SuuUI.Plugins:Get(PLUGIN_ID):Disable()
            H.env.TargetFrameSpellBar:Hide()
            H.env.TargetFrameSpellBar:Show()
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("hook inert once restored").eq(true)
            H.fireEvent("PLAYER_ENTERING_WORLD")
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("inert under event traffic").eq(true)
        end)

        it("is suppressed again on a re-enable", function()
            local p = H.SuuUI.Plugins:Get(PLUGIN_ID)
            p:Disable()
            p:Enable()
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("round-trip re-hides").eq(false)
            H.env.TargetFrameSpellBar:Show()
            expect(H.env.TargetFrameSpellBar:IsShown())
                .as("existing hook reused, not stacked").eq(false)
        end)

        it("does not show a bar it never hid", function()
            -- target_enabled off means nothing was suppressed
            H.setup({ boot = false })
            H.SuuUI.Settings:Register(PLUGIN_ID, {
                { key = "target_enabled", label = "Enable Cast Bar", type = "toggle", default = false },
            })
            H.fireEvent("ADDON_LOADED", "SuuUI")
            H.fireEvent("PLAYER_LOGIN")

            local bar = H.env.TargetFrameSpellBar
            bar:Hide()
            H.SuuUI.Plugins:Get(PLUGIN_ID):Disable()
            expect(bar:IsShown()).as("left as someone else set it").eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. Detached mode
    ---------------------------------------------------------------------------
    describe("detached mode", function()
        before_each(function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "target_anchor", "detached")
        end)

        it("controller reports 'detached' mode", function()
            expect(targetCtl():GetMode()).eq("detached")
        end)

        it("bar is NOT a descendant of the target frame", function()
            local bar = targetBar()
            local tfFrame = targetFrame():GetFrame()
            local cur = bar:GetFrame():GetParent()
            local found = false
            while cur do
                if cur == tfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("not inside target frame").falsy()
        end)

        it("width follows target_width setting", function()
            local bar = targetBar()
            expect(bar:GetFrame():GetWidth()).near(setting("target_width"), 1)
        end)

        it("changing target_width updates bar width", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "target_width", 250)
            local bar = targetBar()
            expect(bar:GetFrame():GetWidth()).near(250, 1)
        end)

        it("switching back to attached mode restores", function()
            expect(targetCtl():GetMode()).eq("detached")
            H.SuuUI.Settings:Set(PLUGIN_ID, "target_anchor", "attached")
            expect(targetCtl():GetMode()).eq("attached")
            -- Bar is inside target frame again
            local bar = targetBar()
            local tfFrame = targetFrame():GetFrame()
            local cur = bar:GetFrame():GetParent()
            local found = false
            while cur do
                if cur == tfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("back inside target frame").truthy()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Target tab schema
    ---------------------------------------------------------------------------
    describe("target tab schema", function()
        it("target tab exists with expected keys and defaults", function()
            local tab = targetTab()
            expect(tab).as("target tab exists").notNil()
            expect(setting("target_enabled")).eq(true)
            expect(setting("target_anchor")).eq("attached")
            expect(setting("target_attach_position")).eq("below")
            expect(setting("target_width")).eq(304)
            expect(setting("target_height")).eq(22)
            expect(setting("target_show_icon")).eq(true)
            expect(setting("target_show_name")).eq(true)
            expect(setting("target_show_time")).eq(true)
            expect(setting("target_show_shield")).eq(true)
            expect(setting("target_icon_position")).eq("left")
            expect(setting("target_time_format")).eq("remaining")
            expect(setting("target_school_color")).eq(true)
            expect(setting("target_cast_color")).deepEq({0.85, 0.63, 0.17, 1})
            expect(setting("target_channel_color")).deepEq({0.25, 0.55, 0.85, 1})
        end)

        it("target_width has enabledIf { key = target_anchor, equals = 'detached' }", function()
            local tab = targetTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "target_width" then
                    expect(type(e.enabledIf)).as("has dependency").eq("table")
                    expect(e.enabledIf.key).eq("target_anchor")
                    expect(e.enabledIf.equals).eq("detached")
                    return
                end
            end
            error("target_width not found in schema")
        end)

        it("target_attach_position has enabledIf { key = target_anchor, equals = 'attached' }", function()
            local tab = targetTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "target_attach_position" then
                    expect(type(e.enabledIf)).as("has dependency").eq("table")
                    expect(e.enabledIf.key).eq("target_anchor")
                    expect(e.enabledIf.equals).eq("attached")
                    return
                end
            end
            error("target_attach_position not found in schema")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Attach lifecycle: disabling unit_frames revokes the point
    ---------------------------------------------------------------------------
    describe("attach lifecycle", function()
        it("disabling unit_frames revokes unitframe.target and target bar detaches cleanly", function()
            expect(targetCtl():GetMode()).eq("attached")
            local reqBefore = H.SuuUI.AttachPoints:GetRequestCount()
            expect(function()
                H.SuuUI.Plugins:Get("unit_frames"):Disable()
            end).notThrows()
            -- Point gone
            expect(H.SuuUI.AttachPoints:Has("unitframe.target")).eq(false)
            -- Controller mode is nil
            expect(targetCtl():GetMode()).as("mode nil after revoke").isNil()
            expect(targetCtl():GetBar()).as("bar torn down").isNil()
        end)

        it("re-enabling unit_frames restores the attached bar", function()
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            expect(targetCtl():GetMode()).isNil()
            H.setTarget({ name = "Boss", level = 60, reaction = 2 })
            H.SuuUI.Plugins:Get("unit_frames"):Enable()
            expect(H.SuuUI.AttachPoints:Has("unitframe.target")).eq(true)
            expect(targetCtl():GetMode()).eq("attached")
            expect(targetCtl():GetBar()).notNil()
        end)

        it("no request leak after round-trips", function()
            local reqBefore = H.SuuUI.AttachPoints:GetRequestCount()
            for _ = 1, 3 do
                H.SuuUI.Settings:Set(PLUGIN_ID, "target_anchor", "detached")
                H.SuuUI.Settings:Set(PLUGIN_ID, "target_anchor", "attached")
            end
            expect(H.SuuUI.AttachPoints:GetRequestCount())
                .as("no request leak").eq(reqBefore)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Teardown: disabling CastBars plugin
    ---------------------------------------------------------------------------
    describe("teardown", function()
        it("disabling cast bars stops both controllers, no watchers or requests left behind", function()
            local watchBefore = H.SuuUI.Settings:GetWatcherCount()
            local reqBefore = H.SuuUI.AttachPoints:GetRequestCount()

            H.SuuUI.Plugins:Get(PLUGIN_ID):Disable()

            -- Controllers gone
            expect(plugin()._controllers).isNil()

            -- Watchers that were added by the CastBars plugin are gone
            local watchAfter = H.SuuUI.Settings:GetWatcherCount()
            expect(watchAfter).as("watchers dropped").lt(watchBefore)

            -- Requests from cast bars released
            local reqAfter = H.SuuUI.AttachPoints:GetRequestCount()
            expect(reqAfter).as("requests released").lt(reqBefore)

            -- No error from further events
            expect(function()
                H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Default")
                H.fireEvent("PLAYER_TARGET_CHANGED", "player")
            end).notThrows()
        end)
    end)
end)
