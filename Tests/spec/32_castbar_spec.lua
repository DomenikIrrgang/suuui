local H = require("harness")

-- Reads the live setting exactly as the widget does.
local function setting(key)
    return H.SuuUI.Settings:Get("cast_bars", key)
end

-- The bar under test is the player controller's live bar, attached to the unit frame by
-- default. These helpers keep every test from repeating the lookup chain.
local function ctl()
    return H.SuuUI.Plugins:Get("cast_bars")._controllers.player
end

local function bar()
    return ctl():GetBar()
end

describe("Plugins.CastBars – CastBar widget", function()
    local state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth    = 80
        state.unitHealthMax = 100
        state.unitPower     = 60
        state.unitPowerMax  = 100
        state.unitPowerType = 0
        state.unitLevel     = 42
        state.maxPlayerLevel = 60
        state.reloadUICalled = 0
        H.setup()
    end)

    ---------------------------------------------------------------------------
    -- 1. Idle state
    ---------------------------------------------------------------------------
    describe("idle state", function()
        it("wrapper is shown at full height while idle", function()
            local b = bar()
            expect(b:IsShown()).eq(true)
            H.expectSize(b, nil, setting("player_height"))
        end)

        it("content row is hidden while idle", function()
            local b = bar()
            expect(b._row:IsShown()).eq(false)
        end)

        it("reports state 'idle' and IsCasting false", function()
            local b = bar()
            expect(b:GetState()).eq("idle")
            expect(b:IsCasting()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. Cast start
    ---------------------------------------------------------------------------
    describe("cast start", function()
        it("shows content, sets name and icon, state is casting", function()
            local b = bar()
            H.startCast({ name = "Fireball", texture = "Interface\\Icons\\Spell_Fire_FlameBolt" })
            expect(b._row:IsShown()).eq(true)
            expect(b._nameText:GetText()).eq("Fireball")
            expect(b._icon:GetIcon()).eq("Interface\\Icons\\Spell_Fire_FlameBolt")
            expect(b:GetState()).eq("casting")
            expect(b:IsCasting()).eq(true)
        end)

        it("fill is near zero at the start of a fresh cast", function()
            local b = bar()
            H.startCast({ duration = 2.5 })
            expect(b._bar:GetPercent()).near(0, 0.05)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. Progress and time format
    ---------------------------------------------------------------------------
    describe("progress", function()
        it("ticking advances the fill toward elapsed/total", function()
            local b = bar()
            H.startCast({ duration = 2.0 })
            H.tick(1.0) -- half the duration
            local pct = b._bar:GetPercent()
            expect(pct).near(0.5, 0.05)
        end)

        it("format 'remaining' shows time left", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "remaining")
            local b = bar()
            H.startCast({ duration = 2.5 })
            H.tick(1.0)
            -- remaining = 2.5 - 1.0 = 1.5
            expect(b._timeText:GetText()).eq("1.5")
        end)

        it("format 'elapsed' shows time passed", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "elapsed")
            local b = bar()
            H.startCast({ duration = 2.5 })
            H.tick(1.0)
            expect(b._timeText:GetText()).eq("1.0")
        end)

        it("format 'both' shows elapsed / total", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "both")
            local b = bar()
            H.startCast({ duration = 2.5 })
            H.tick(1.0)
            expect(b._timeText:GetText()).eq("1.0 / 2.5")
        end)

        it("format 'percent' shows integer percentage", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "percent")
            local b = bar()
            H.startCast({ duration = 2.0 })
            H.tick(1.0)
            expect(b._timeText:GetText()).eq("50%")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. Geometry
    ---------------------------------------------------------------------------
    describe("geometry", function()
        it("icon is square with side == player_height", function()
            local b = bar()
            H.startCast({})
            local h = setting("player_height")
            H.expectSize(b._icon, h, h)
        end)

        it("icon is LEFT by default, bar to the right", function()
            local b = bar()
            H.startCast({})
            local children = b._row:GetChildren()
            -- first child is the icon frame
            expect(H.frameOf(children[1])).eq(b._icon:GetFrame())
        end)

        it("icon_position 'right' moves icon to the right", function()
            H.SuuUI.Settings:Set("cast_bars", "player_icon_position", "right")
            local b = bar()
            H.startCast({})
            local children = b._row:GetChildren()
            -- last child is the icon frame
            expect(H.frameOf(children[#children])).eq(b._icon:GetFrame())
        end)

        it("name and time are INSIDE the bar area", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", duration = 3.0 })
            H.tick(0.5)
            H.expectInside(b._nameText, b._barArea)
            H.expectInside(b._timeText, b._barArea)
        end)

        it("name and time do not overlap", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", duration = 3.0 })
            H.tick(0.5)
            H.expectNoOverlap({ b._nameText, b._timeText })
        end)

        it("name is inset from the left by spaceXs", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.1)
            local padX = H.token("spaceXs")
            local dx = H.offset(b._nameText, b._barArea)
            expect(dx).near(padX, 0.5)
        end)

        it("time is inset from the right by spaceXs", function()
            local b = bar()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "remaining")
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(1.0)
            local padX = H.token("spaceXs")
            local barBox = H.box(b._barArea)
            local timeBox = H.box(b._timeText)
            local rightInset = barBox.right - timeBox.right
            expect(rightInset).near(padX, 0.5)
        end)

        it("text row is vertically centred in the bar area", function()
            local b = bar()
            H.startCast({ name = "Pyroblast", duration = 4.0 })
            H.tick(0.1)
            H.expectCenteredV(b._textRow, b._barArea)
        end)

        it("long name and 'both' format do not clip", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "both")
            -- Widen the bar a lot so text fits
            H.SuuUI.Settings:Set("cast_bars", "player_width", 500)
            local b = bar()
            H.startCast({ name = "Greater Pyroblast of the Firelands", duration = 6.0 })
            H.tick(3.0)
            H.expectTextNotClipped(b._nameText:GetFrame())
            H.expectTextNotClipped(b._timeText:GetFrame())
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. Parts visibility
    ---------------------------------------------------------------------------
    describe("parts visibility", function()
        it("show_icon false hides the icon, bar spans full width", function()
            H.SuuUI.Settings:Set("cast_bars", "player_show_icon", false)
            local b = bar()
            H.startCast({})
            expect(b._icon:IsShown()).eq(false)
            -- The bar area should fill the row now (no icon to take space)
            local rowW = b._row:GetFrame():GetWidth()
            local barW = b._barArea:GetWidth()
            -- Flow skips a hidden child and its gap, so barArea should be ~rowW
            expect(barW).near(rowW, 1)
        end)

        it("show_name false hides the name text", function()
            H.SuuUI.Settings:Set("cast_bars", "player_show_name", false)
            local b = bar()
            H.startCast({})
            expect(b._nameText:IsShown()).eq(false)
        end)

        it("show_time false hides the time text", function()
            H.SuuUI.Settings:Set("cast_bars", "player_show_time", false)
            local b = bar()
            H.startCast({})
            expect(b._timeText:IsShown()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. Channel
    ---------------------------------------------------------------------------
    describe("channel", function()
        it("state is channeling and fill drains as you tick", function()
            local b = bar()
            H.startChannel({ name = "Blizzard", duration = 8.0 })
            expect(b:GetState()).eq("channeling")
            local initial = b._bar:GetPercent()
            expect(initial).near(1.0, 0.05)
            H.tick(4.0) -- half the channel
            local mid = b._bar:GetPercent()
            expect(mid).near(0.5, 0.1)
            expect(mid).lt(initial)
        end)

        it("channel falls back to player_channel_color while the school is unknown", function()
            local b = bar()
            H.startChannel({ name = "Blizzard", duration = 8.0 })
            local expected = setting("player_channel_color")
            local got = b._bar._fillColor
            for i = 1, 4 do
                expect(got[i]).near(expected[i], 0.001)
            end
        end)

        it("a regular cast falls back to player_cast_color while the school is unknown", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            local expected = setting("player_cast_color")
            local got = b._bar._fillColor
            for i = 1, 4 do
                expect(got[i]).near(expected[i], 0.001)
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6b. Spell school colouring
    --
    -- No client API maps a spell to its school, so the combat log is the only source and
    -- the bar has to cope with the school arriving after the cast already started. Both
    -- orders are covered: primed from the cache (most casts) and learned mid-flight (the
    -- first cast of a spell in a session).
    ---------------------------------------------------------------------------
    describe("spell school colouring", function()
        local FROST, FIRE = 0x10, 0x04

        local function expectColor(got, want, label)
            for i = 1, 4 do
                expect(got[i]).as(label or "colour").near(want[i], 0.001)
            end
        end

        local function schoolColor(mask)
            return H.SuuUI.Game:SchoolColor(mask)
        end

        it("colours a cast from the cache with no repaint needed", function()
            H.SuuUI.Game:LearnSchool(133, FROST)
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 133 })
            expectColor(b._bar._fillColor, schoolColor(FROST), "frost fill")
        end)

        it("recolours a cast already in flight when the log names its school", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 116, duration = 3.0 })
            expectColor(b._bar._fillColor, setting("player_cast_color"), "fallback first")

            H.combatLogSpell({ spellId = 116, school = FROST })
            expectColor(b._bar._fillColor, schoolColor(FROST), "recoloured mid-cast")
        end)

        it("recolouring mid-cast leaves the progress alone", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 116, duration = 4.0 })
            H.tick(2.0)
            local before = b._bar:GetPercent()
            H.combatLogSpell({ spellId = 116, school = FROST })
            expect(b._bar:GetPercent()).near(before, 0.001)
            expect(b:GetState()).eq("casting")
        end)

        it("recolours a channel in flight, which only ever produces tick lines", function()
            local b = bar()
            H.startChannel({ name = "Blizzard", spellId = 10, duration = 8.0 })
            expectColor(b._bar._fillColor, setting("player_channel_color"), "fallback first")

            H.combatLogSpell({ spellId = 10, school = FROST,
                               subevent = "SPELL_PERIODIC_DAMAGE" })
            expectColor(b._bar._fillColor, schoolColor(FROST), "channel recoloured")
        end)

        it("a channel still drains from full while school-coloured", function()
            H.SuuUI.Game:LearnSchool(10, FROST)
            local b = bar()
            H.startChannel({ name = "Blizzard", spellId = 10, duration = 8.0 })
            expect(b._bar:GetPercent()).near(1.0, 0.05)
            H.tick(4.0)
            expect(b._bar:GetPercent()).near(0.5, 0.1)
        end)

        it("ignores a log line for a different spell", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 116 })
            H.combatLogSpell({ spellId = 999, school = FIRE })
            expectColor(b._bar._fillColor, setting("player_cast_color"), "untouched")
        end)

        it("holds the school it first learned for the rest of the cast", function()
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 116, duration = 4.0 })
            H.combatLogSpell({ spellId = 116, school = FROST })
            -- A contradicting later line must not repaint: the guard that stops a raid's
            -- worth of lines rewriting the fill is what this asserts.
            H.combatLogSpell({ spellId = 116, school = FIRE })
            expectColor(b._bar._fillColor, schoolColor(FROST), "still frost")
        end)

        it("uses the fixed colours when the player turns school colouring off", function()
            H.SuuUI.Game:LearnSchool(133, FROST)
            H.SuuUI.Settings:Set("cast_bars", "player_school_color", false)
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 133 })
            expectColor(b._bar._fillColor, setting("player_cast_color"), "fixed cast colour")
        end)

        it("flipping the setting recolours a cast that is already running", function()
            H.SuuUI.Game:LearnSchool(133, FROST)
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 133, duration = 4.0 })
            expectColor(b._bar._fillColor, schoolColor(FROST), "school first")

            H.SuuUI.Settings:Set("cast_bars", "player_school_color", false)
            expectColor(b._bar._fillColor, setting("player_cast_color"), "now fixed")

            H.SuuUI.Settings:Set("cast_bars", "player_school_color", true)
            expectColor(b._bar._fillColor, schoolColor(FROST), "school again")
        end)

        it("an interrupt still wins over the school colour", function()
            H.SuuUI.Game:LearnSchool(133, FROST)
            local b = bar()
            H.startCast({ name = "Frostbolt", spellId = 133 })
            H.interruptCast()
            expectColor(b._bar._fillColor, H.token("colorDanger"), "danger")
        end)

        it("the edit-mode preview has no spell, so it uses the fixed colour", function()
            H.SuuUI.Game:LearnSchool(133, FROST)
            H.SuuUI.ToggleUI:Enable()
            local b = bar()
            expect(b:GetState()).eq("preview")
            expectColor(b._bar._fillColor, setting("player_cast_color"), "preview colour")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. Interrupt and fail
    ---------------------------------------------------------------------------
    describe("uninterruptible cue", function()
        local function shieldToken()
            return H.token("colorShield")
        end

        it("an interruptible cast draws no outline on the bar", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            expect(b._bar:IsBorderShown()).eq(false)
        end)

        it("an uninterruptible cast outlines the bar in the shield token", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            expect(b._bar:IsBorderShown()).as("the outline appears").eq(true)
            H.expectTokenColor(H.borderColor(b._bar), "colorShield")
        end)

        it("outlines the icon in the same token, and restores it afterwards", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            H.expectTokenColor(H.borderColor(b._icon), "colorShield")
            H.stopCast()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.expectTokenColor(H.borderColor(b._icon), "colorBorder")
        end)

        it("the outline is a shape change, not only a colour change", function()
            -- The whole reason for choosing an outline: it survives a player recolouring
            -- the fill, which a colour-only cue would not.
            local b = bar()
            H.SuuUI.Settings:Set("cast_bars", "player_cast_color", { 1, 1, 1, 1 })
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            expect(b._bar:IsBorderShown()).eq(true)
        end)

        it("an uninterruptible channel is marked too, reading the shifted payload slot", function()
            -- notInterruptible sits one position earlier for a channel, since a channel has
            -- no castID. Reading the cast's position would mark every channel.
            local b = bar()
            H.startChannel({ name = "Drain Life", duration = 3, notInterruptible = true })
            expect(b._bar:IsBorderShown()).eq(true)
        end)

        it("an interruptible channel is not marked", function()
            local b = bar()
            H.startChannel({ name = "Drain Life", duration = 3 })
            expect(b._bar:IsBorderShown()).eq(false)
        end)

        it("the outline drops when the cue setting is switched off, live", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            expect(b._bar:IsBorderShown()).eq(true)
            H.SuuUI.Settings:Set("cast_bars", "player_show_shield", false)
            expect(b._bar:IsBorderShown()).as("no reload needed").eq(false)
            H.SuuUI.Settings:Set("cast_bars", "player_show_shield", true)
            expect(b._bar:IsBorderShown()).eq(true)
        end)

        it("defaults to on", function()
            expect(H.SuuUI.Settings:Get("cast_bars", "player_show_shield")).eq(true)
        end)

        it("the outline insets the fill so it does not paint under the edge", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(1.25)
            local plain = H.box(b._bar._fillFrame).left - H.box(b._bar).left
            expect(plain).as("no border, so the fill starts at the very edge").near(0, 0.5)

            H.stopCast()
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            H.tick(1.25)
            local shielded = H.box(b._bar._fillFrame).left - H.box(b._bar).left
            local line = H.SuuUI.Pixel.Line(H.token("borderWidth"))
            expect(shielded).as("pushed in by exactly the border width").near(line, 0.5)
        end)

        it("the preview is never marked, having no interruptibility to report", function()
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(b:GetState()).eq("preview")
            expect(b._bar:IsBorderShown()).eq(false)
        end)

        it("an interrupted cast drops the outline with the cast", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5, notInterruptible = true })
            H.interruptCast()
            expect(b._bar:IsBorderShown()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7b. Interrupt attribution
    ---------------------------------------------------------------------------
    describe("interrupt attribution", function()
        it("names the interrupter in the readout slot", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.4)
            H.interruptCast({ by = "Kaelthas" })
            expect(b._nameText:GetText()).as("what was stopped").eq("Fireball")
            expect(b._timeText:GetText()).as("who stopped it").eq("Kaelthas")
        end)

        it("names the interrupter when the log line arrives AFTER the cast event", function()
            -- The client does not guarantee the order, so both have to work.
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.4)
            H.interruptCast({ by = "Kaelthas", logAfter = true })
            expect(b._timeText:GetText()).eq("Kaelthas")
        end)

        it("falls back to the localised word when nothing attributed the interrupt", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.interruptCast()
            expect(b._timeText:GetText()).eq("Interrupted")
        end)

        it("ignores a SPELL_INTERRUPT aimed at another unit", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.combatLogInterrupt({ unit = "target", by = "Somebody" })
            H.interruptCast()
            expect(b._timeText:GetText()).as("not our interrupt").eq("Interrupted")
        end)

        it("ignores combat log lines that are not interrupts", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.state.combatLogEvent = { H.state.clock or 0, "SPELL_DAMAGE", false,
                "GUID-src", "Somebody", 0, 0, H.env.UnitGUID("player"), "Testchar", 0, 0,
                133, "Fireball", 0 }
            H.state.combatLogEvent.n = #H.state.combatLogEvent
            H.fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
            H.state.combatLogEvent = nil
            H.interruptCast()
            expect(b._timeText:GetText()).eq("Interrupted")
        end)

        it("a new cast clears the name so a later interrupt cannot reuse it", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.interruptCast({ by = "Kaelthas" })
            expect(b._timeText:GetText()).eq("Kaelthas")

            -- Straight into another cast: the old name must not survive it.
            H.startCast({ name = "Frostbolt", duration = 2 })
            expect(b._nameText:GetText()).eq("Frostbolt")
            expect(b._timeText:GetText()).as("a live timer, not a stale name").neq("Kaelthas")

            H.interruptCast()
            expect(b._timeText:GetText()).as("unattributed again").eq("Interrupted")
        end)

        it("a stale name is not reused once the correlation window has passed", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 20 })
            H.combatLogInterrupt({ by = "Kaelthas" })
            H.tick(5)
            H.interruptCast()
            expect(b._timeText:GetText()).as("too old to belong to this").eq("Interrupted")
        end)

        it("a new cast right after an interrupt resets the whole state", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.4)
            H.interruptCast({ by = "Kaelthas" })
            expect(b:GetState()).eq("interrupted")

            H.startCast({ name = "Frostbolt", duration = 2 })
            expect(b:GetState()).eq("casting")
            expect(b._row:IsShown()).as("the fade was cancelled").eq(true)
            expect(b._row:GetFrame():GetAlpha()).eq(1)
            local cast = H.SuuUI.Settings:Get("cast_bars", "player_cast_color")
            for i = 1, 4 do
                expect(b._bar._fillColor[i]).as("back to the cast colour").near(cast[i], 0.001)
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7c. Interrupt and fail
    ---------------------------------------------------------------------------
    describe("interrupt and fail", function()        it("interrupt: spell name stays, outcome takes the readout slot, fill is danger", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.5)
            H.interruptCast()
            expect(b:GetState()).eq("interrupted")
            -- The spell that was stopped stays on the left; the outcome goes where the
            -- cast timer was, since a broken cast has no remaining time to report.
            expect(b._nameText:GetText()).eq("Fireball")
            expect(b._timeText:GetText()).as("unattributed, so the localised word").eq("Interrupted")
            -- Fill colour is the danger token
            local danger = H.token("colorDanger")
            local got = b._bar._fillColor
            for i = 1, 4 do
                expect(got[i]).near(danger[i], 0.001)
            end
            -- Bar left full (value = 1)
            expect(b._bar:GetPercent()).eq(1)
        end)

        it("interrupt fades out then hides content", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.5)
            H.interruptCast()
            H.runAnimations()
            expect(b._row:IsShown()).eq(false)
        end)

        it("interrupt resets state to idle after the fade completes", function()
            -- The fade's completion is part of the state machine: a query must never read
            -- a stale outcome once the bar is off screen.
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.5)
            H.interruptCast()
            expect(b:GetState()).as("the outcome is shown while it fades").eq("interrupted")
            H.runAnimations()
            expect(b:GetState()).eq("idle")
        end)

        it("fail: spell name stays, FAILED takes the readout slot, fill is danger", function()
            local b = bar()
            H.startCast({ name = "Polymorph", duration = 1.5 })
            H.tick(0.3)
            H.failCast()
            expect(b:GetState()).eq("failed")
            expect(b._nameText:GetText()).eq("Polymorph")
            expect(b._timeText:GetText()).eq("Failed")
            local danger = H.token("colorDanger")
            local got = b._bar._fillColor
            for i = 1, 4 do
                expect(got[i]).near(danger[i], 0.001)
            end
            expect(b._bar:GetPercent()).eq(1)
        end)

        it("fail fades out then returns to idle", function()
            local b = bar()
            H.startCast({ name = "Polymorph", duration = 1.5 })
            H.tick(0.3)
            H.failCast()
            H.runAnimations()
            expect(b._row:IsShown()).eq(false)
        end)

        it("fail resets state to idle after the fade completes", function()
            local b = bar()
            H.startCast({ name = "Polymorph", duration = 1.5 })
            H.tick(0.3)
            H.failCast()
            expect(b:GetState()).eq("failed")
            H.runAnimations()
            expect(b:GetState()).eq("idle")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Normal end
    ---------------------------------------------------------------------------
    describe("normal end", function()
        it("stopCast hides content and returns to idle", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.5)
            H.stopCast()
            expect(b._row:IsShown()).eq(false)
            expect(b:GetState()).eq("idle")
            expect(b:IsCasting()).eq(false)
        end)

        it("finishCast hides content and returns to idle", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(2.5)
            H.finishCast()
            expect(b._row:IsShown()).eq(false)
            expect(b:GetState()).eq("idle")
            expect(b:IsCasting()).eq(false)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Pushback (delayCast)
    ---------------------------------------------------------------------------
    describe("pushback", function()
        it("delayCast extends the total and remaining readout grows", function()
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "remaining")
            local b = bar()
            H.startCast({ duration = 2.5 })
            H.tick(1.0)
            -- Before pushback: remaining = 2.5 - 1.0 = 1.5
            local before = b._timeText:GetText()
            expect(before).eq("1.5")
            -- Push the cast out by 0.5s
            H.delayCast(0.5)
            -- Now remaining = (2.5 + 0.5) - 1.0 = 2.0
            -- The tween restarted, give it a tick to update the display
            H.tick(0.016)
            local after = b._timeText:GetText()
            expect(after).eq("2.0")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 10. Re-cast mid-cast (pre-emption)
    ---------------------------------------------------------------------------
    describe("re-cast mid-cast", function()
        it("pre-empts the old tween and tracks the new cast", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(1.0) -- half way through first cast
            -- Now start a new cast
            H.startCast({ name = "Frostbolt", duration = 2.0 })
            -- Only 1 tween should be running on the bar's owner
            expect(H.SuuUI.Anim:GetActiveCount(b)).eq(1)
            -- Name should reflect the new cast
            expect(b._nameText:GetText()).eq("Frostbolt")
            -- Fill should be near zero for the new cast
            expect(b._bar:GetPercent()).near(0, 0.05)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 11. Edit-mode preview
    ---------------------------------------------------------------------------
    describe("edit-mode preview", function()
        it("idle + edit mode shows the preview", function()
            local b = bar()
            expect(b._row:IsShown()).eq(false)
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(b._row:IsShown()).eq(true)
            expect(b:GetState()).eq("preview")
            expect(b._nameText:GetText()).eq("Player Cast Bar")
            -- Preview fraction is 0.6
            expect(b._bar:GetPercent()).near(0.6, 0.01)
        end)

        it("disabling edit mode hides the preview", function()
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(b._row:IsShown()).eq(true)
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(b._row:IsShown()).eq(false)
        end)

        it("disabling edit mode transitions state back to idle", function()
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(b:GetState()).eq("preview")
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(b:GetState()).eq("idle")
        end)

        it("an interrupt during edit mode returns to the preview once it has faded", function()
            -- The outcome is worth showing, but the bar the player is arranging must come
            -- back afterwards rather than disappearing for the rest of the session.
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.4)
            H.interruptCast()
            H.runAnimations()
            expect(b:GetState()).eq("preview")
            expect(b._row:IsShown()).as("visible again for dragging").eq(true)
            expect(b._row:GetFrame():GetAlpha()).as("the fade did not leave it transparent").eq(1)
        end)

        it("a real cast during edit mode wins", function()
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            expect(b:GetState()).eq("preview")
            H.startCast({ name = "Pyroblast", duration = 4.0 })
            expect(b:GetState()).eq("casting")
            expect(b._nameText:GetText()).eq("Pyroblast")
        end)

        it("ending the cast during edit mode returns to preview", function()
            local b = bar()
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            H.startCast({ name = "Pyroblast", duration = 4.0 })
            expect(b:GetState()).eq("casting")
            H.stopCast()
            -- Should go back to preview since edit mode is still on
            expect(b:GetState()).eq("preview")
            expect(b._row:IsShown()).eq(true)
            expect(b._nameText:GetText()).eq("Player Cast Bar")
        end)
    end)

    ---------------------------------------------------------------------------
    -- 12. Reactivity: settings and profile
    ---------------------------------------------------------------------------
    describe("reactivity", function()
        it("player_height resizes the wrapper and the square icon", function()
            local b = bar()
            local oldH = setting("player_height")
            local newH = oldH + 6
            H.SuuUI.Settings:Set("cast_bars", "player_height", newH)
            H.expectSize(b, nil, newH)
            -- Start a cast so the icon is visible and sized
            H.startCast({})
            H.expectSize(b._icon, newH, newH)
        end)

        it("settings changes arrive on a profile switch", function()
            local b = bar()
            local defaultH = setting("player_height")
            -- Create a new profile with a different height
            H.SuuUI.Profiles:Create("alt")
            H.SuuUI.Profiles:SetActive("alt")
            H.SuuUI.Settings:Set("cast_bars", "player_height", defaultH + 10)
            -- Switch back and forth
            H.SuuUI.Profiles:SetActive("Default")
            expect(setting("player_height")).eq(defaultH)
            H.expectSize(bar(), nil, defaultH)
            H.SuuUI.Profiles:SetActive("alt")
            H.expectSize(bar(), nil, defaultH + 10)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 13. Theme reaction
    ---------------------------------------------------------------------------
    describe("theme reaction", function()
        it("theme switch restyles and re-derives geometry", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            -- Switch to Modern theme
            H.SuuUI.Theme:SetActive("Modern")
            -- After theme change, bar still visible and geometry is consistent
            expect(b._row:IsShown()).eq(true)
            -- Icon is still square with side == height setting
            local h = setting("player_height")
            H.expectSize(b._icon, h, h)
            -- Text insets use the current token value
            local padX = H.token("spaceXs")
            local dx = H.offset(b._nameText, b._barArea)
            expect(dx).near(padX, 0.5)
        end)

        it("editing a space token re-derives text insets", function()
            local b = bar()
            H.startCast({ name = "Fireball", duration = 2.5 })
            H.tick(0.1)
            -- Create a user theme and edit its token
            H.SuuUI.Theme:CreateUserTheme("TestTheme", "Default")
            H.SuuUI.Theme:SetActive("TestTheme")
            H.SuuUI.Theme:SetUserToken("TestTheme", "spaceXs", 8)
            -- Re-fire theme changed so the widget re-derives
            H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "TestTheme")
            local padX = H.token("spaceXs")
            expect(padX).eq(8)
            local dx = H.offset(b._nameText, b._barArea)
            expect(dx).near(padX, 0.5)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 14. Teardown
    ---------------------------------------------------------------------------
    describe("teardown", function()
        it("Destroy drops all watchers (no leak)", function()
            local b = bar()
            local countBefore = H.SuuUI.Settings:GetWatcherCount()
            -- The bar has several watchers registered; destroy must remove them all.
            b:Destroy()
            local countAfter = H.SuuUI.Settings:GetWatcherCount()
            expect(countAfter).lt(countBefore)
            -- Verify no watcher leaks: a second theme change (which notifies remaining
            -- watchers) should not error.
            expect(function()
                H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Default")
            end).notThrows()
        end)

        it("signals are disconnected after Destroy", function()
            local b = bar()
            local spy = H.signalSpy(b, H.S.SIGNALS.SIZE_CHANGED)
            b:Destroy()
            -- Emitting after destroy should not fire the spy
            H.S:Emit(b, H.S.SIGNALS.SIZE_CHANGED, 100, 20)
            expect(spy.count).eq(0)
        end)

        it("a theme change after Destroy does not error", function()
            local b = bar()
            b:Destroy()
            expect(function()
                H.SuuUI.Events:Emit("SUUUI_THEME_CHANGED", "Default")
            end).notThrows()
        end)
    end)

    ---------------------------------------------------------------------------
    -- Construction seeds itself through its own watchers
    --
    -- The layout and format watchers carry { immediate = true }, which makes the
    -- callback the single place that establishes these values -- there is no
    -- separate seeding call in the constructor. Section 5b of architecture.md is
    -- explicit that the two together are duplication.
    --
    -- A bar built directly is what makes that testable. The plugin's own bar is
    -- relaid out again by ApplyTheme and by the attach, both of which run after
    -- construction during boot, so a bar that seeded nothing still measures
    -- correctly through the live plugin and hides the omission completely.
    ---------------------------------------------------------------------------
    describe("construction seeds itself (immediate watchers)", function()
        local function bareBar()
            return H.SuuUI._CastBars.CastBar:Create(H.parent(400, 80), {
                unit        = "player",
                pluginId    = "cast_bars",
                prefix      = "player_",
                displayName = "Player",
                attached    = false,
            })
        end

        it("the time format is established without a constructor call", function()
            -- _syncFormat resolves the time_format setting into _timeFmt. Nothing else
            -- sets it, so an unseeded bar carries nil here and its first readout during
            -- a cast has no formatter at all.
            local b = bareBar()
            expect(b._timeFmt).as("format resolved at construction").notNil()
            b:Destroy()
        end)

        it("the icon is squared to the height setting without a constructor call", function()
            -- Relayout derives the icon's width from the height setting -- a square icon
            -- is as wide as the bar is tall. An unseeded bar never states that width.
            local b = bareBar()
            expect(b._iconProps.width)
                .as("icon squared to the bar height").eq(setting("player_height"))
            b:Destroy()
        end)

        it("the part-visibility settings are honoured at construction", function()
            -- _syncParts is the one thing Relayout establishes that the constructor does
            -- not do inline, so it is what proves the layout watcher really seeds itself.
            -- A bar built while Show Icon is off must come up without an icon rather than
            -- waiting for the first cast to notice.
            H.SuuUI.Settings:Set("cast_bars", "player_show_icon", false)
            H.SuuUI.Settings:Set("cast_bars", "player_show_time", false)
            local b = bareBar()
            expect(b._icon:IsShown()).as("icon off at construction").eq(false)
            expect(b._timeText:IsShown()).as("time off at construction").eq(false)
            expect(b._nameText:IsShown()).as("name still on").eq(true)
            b:Destroy()
        end)

        it("a live format change still reaches the readout", function()
            -- The other half of the contract: immediate must not have replaced the
            -- reactive behaviour it was added alongside.
            local b = bareBar()
            local before = b._timeFmt
            H.SuuUI.Settings:Set("cast_bars", "player_time_format", "percent")
            expect(b._timeFmt ~= before).as("watcher still fires on a change").eq(true)
            b:Destroy()
        end)
    end)
end)
