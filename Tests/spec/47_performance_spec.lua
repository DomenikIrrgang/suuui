local H = require("harness")

-- The Performance plugin: a framerate readout and a latency readout, and the first plugin
-- that contributes to the data bar WITHOUT owning it. So this file asserts three layers —
-- the STRINGS and TONES the two widgets answer (which is the whole of their logic), the
-- FIELDS the bar builds from them (placement, prefix, rail, repaint cadence), and the
-- plugin's own lifecycle.
--
-- Readings and thresholds are asserted as numbers on purpose, and that is not the
-- hardcoded-pixel trap: the reading IS the claim ("at exactly the warn threshold the field
-- is already warning"), and every threshold below is READ BACK from the settings registry
-- rather than typed in, so moving a documented default moves the expectation with it. Every
-- PIXEL and COLOUR expectation is derived from tokens.

local PLUGIN_ID = "performance"
local BAR_ID    = "data_bar"
local FPS_ID    = "performance.fps"
local MS_ID     = "performance.latency"

-- The placeholder the widgets answer when the client tells them nothing. Copied from the
-- production files rather than spelled out, so it is the same code point (U+2014) and not a
-- hyphen that looks like one at this font size.
local DASH = "—"

local function fpsWidget()     return H.SuuUI._Performance.FpsWidget end
local function latencyWidget() return H.SuuUI._Performance.LatencyWidget end
local function plugin()        return H.SuuUI.Plugins:Get(PLUGIN_ID) end
local function def(id)         return H.SuuUI.DataBar:GetWidget(id) end

-- The bar belongs to the DataBar plugin, not to this one. That separation is the point of
-- the registry, and reaching for it through the other plugin is how this spec states it.
local function bar() return H.SuuUI.Plugins:Get(BAR_ID)._bar end

local function set(key, value) H.SuuUI.Settings:Set(PLUGIN_ID, key, value) end
local function get(key)        return H.SuuUI.Settings:Get(PLUGIN_ID, key) end

-- The bar's record for ONE widget id.
local function record(id)
    for _, rec in ipairs(bar()._records) do
        if rec.def.id == id then return rec end
    end
end

local function field(id)
    local rec = record(id)
    return rec and rec.field
end

-- How many fields the bar holds FOR ONE widget. Deliberately not #bar()._records: three
-- plugins contribute widgets to this bar now — the clock, the framerate and the latency — so
-- the bar's total says nothing about any one of them, and using it as a proxy is what broke
-- the clock's own spec the moment a second contributor existed.
local function recordCount(id)
    local n = 0
    for _, rec in ipairs(bar()._records) do
        if rec.def.id == id then n = n + 1 end
    end
    return n
end

-- What the widget answers right now, without going through the bar.
local function say(id) return def(id).GetText() end

-- Pushes the current reading onto the bar through the widget's OWN interval, so a test that
-- means "one refresh of the framerate" cannot accidentally refresh the latency as well.
local function tickFor(id) H.tick(def(id).update) end

-- The tone as it reached the FIELD, and the colour it actually painted. Both halves matter:
-- the stored tone is what the widget said, and the resolved token is what the player sees —
-- a field that stores "warning" and paints colorText is a field with no warning on it.
local function expectTone(id, tone, tokenKey)
    local f = field(id)
    if tone == nil then
        expect(f:GetTone()).as(id .. " tone").isNil()
    else
        expect(f:GetTone()).as(id .. " tone").eq(tone)
    end
    H.expectTokenColor(H.textColor(f._label), tokenKey)
end

-- What a field hugging `prefix value` must be: the composed string's own text box plus the
-- field's spaceMd inset either side. The prefix and the value share one font string with a
-- single space between them, and the colour escape around the prefix is stripped by the font
-- model exactly as the client ignores it when measuring.
local function fieldWidth(prefix, value)
    local str = (prefix and prefix ~= "") and (prefix .. " " .. value) or value
    return H.textBox(str, H.token("fontSizeMd")) + H.token("spaceMd") * 2
end

-- Captures the Tooltip the latency widget builds. It is created lazily on the first hover
-- and kept in a private upvalue, so wrapping the constructor is the only way a spec gets the
-- handle — the same capture pattern the clock's spec and the settings-page specs use.
local function captureTips()
    local built = {}
    local real = H.SuuUI.Components.Tooltip
    H.SuuUI.Components.Tooltip = function(...)
        local tip = real(...)
        built[#built + 1] = tip
        return tip
    end
    return built
end

local function tipText(tip) return tip._text:GetText() end

local function hoverLatency()
    local tips = captureTips()
    H.hover(field(MS_ID))
    return tips[1], tips
end

-- Every frame that currently holds an OnUpdate script.
--
-- The bar's ticker is a file-level local in DataBarWidget.lua, so a spec cannot count its
-- entries — but it CAN read the client's OnUpdate registrations, which is the fact worth
-- asserting anyway: "one frame for every ticking widget" is a claim about the client, not
-- about a table. The COUNT is read as a delta below, so an animation driver appearing or
-- disappearing cannot be mistaken for the ticker; the frames themselves are compared by
-- IDENTITY, which is what tells one reused ticker from a fresh one per rebuild — a
-- replacement ticker leaks the old frame without ever changing the count.
local function updateFrames()
    local list = {}
    for _, f in ipairs(H.state.frames) do
        if not f._destroyed and f._scripts and f._scripts.OnUpdate then
            list[#list + 1] = f
        end
    end
    return list
end

-- Counts how often a widget FORMATS, rather than what it answers.
--
-- The cache is a performance guarantee — the bar asks on a ticker and the widget must format
-- at most once per displayed value — and that is invisible from the string alone: a
-- formatter with no cache returns exactly the same text, and the field drops the unchanged
-- write, so every value assertion in this file (and every TEXT_CHANGED count) passes either
-- way. Counting the calls is the only assertion that can tell a cached widget from an
-- uncached one.
--
-- This instruments the real code path: the ticks still travel the bar's own OnUpdate.
-- `tostring` is a chunk-level local captured when the file loads, so the counter goes in
-- through the upvalue cell it was captured into, which every closure in that chunk shares.
-- It reports whether it attached, and each test asserts that first — an assertion that
-- silently stopped measuring would be worse than no assertion.
local function countFormats(getText)
    local counter, seen = { n = 0 }, {}
    local function patch(fn, depth)
        if depth > 4 or type(fn) ~= "function" or seen[fn] then return false end
        seen[fn] = true
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == "tostring" and type(value) == "function" then
                debug.setupvalue(fn, i, function(...)
                    counter.n = counter.n + 1
                    return value(...)
                end)
                return true
            end
            if type(value) == "function" and patch(value, depth + 1) then return true end
            i = i + 1
        end
        return false
    end
    counter.installed = patch(getText, 1)
    return counter
end

describe("Plugins.Performance – framerate and latency readouts", function()
    before_each(function() H.setup() end)

    -----------------------------------------------------------------------------
    describe("registration", function()
        it("registers both readouts on login", function()
            expect(H.SuuUI.DataBar:Has(FPS_ID)).as("the framerate is registered").eq(true)
            expect(H.SuuUI.DataBar:Has(MS_ID)).as("the latency is registered").eq(true)
        end)

        it("declares text widgets, not custom visuals", function()
            for _, id in ipairs({ FPS_ID, MS_ID }) do
                expect(type(def(id).GetText)).as(id .. " answers a string").eq("function")
                expect(def(id).Build).as(id .. " builds no frames of its own").isNil()
            end
        end)

        it("labels each readout with its own prefix", function()
            expect(def(FPS_ID).prefix).eq("FPS")
            expect(def(MS_ID).prefix).eq("MS")
            expect(field(FPS_ID):GetPrefix()).as("and the field carries it").eq("FPS")
            expect(field(MS_ID):GetPrefix()).eq("MS")
        end)

        it("puts both in the right section", function()
            expect(def(FPS_ID).section).eq("right")
            expect(def(MS_ID).section).eq("right")
            local right = H.SuuUI.DataBar:ListSection("right")
            expect(#right).as("the two performance readouts and nothing else").eq(2)
        end)

        it("gives the bar one field each", function()
            expect(recordCount(FPS_ID)).as("exactly one framerate field").eq(1)
            expect(recordCount(MS_ID)).as("exactly one latency field").eq(1)
        end)

        it("polls rather than listening, since nothing announces either reading", function()
            expect(def(FPS_ID).events).as("no game event announces a framerate").isNil()
            expect(def(MS_ID).events).as("no game event announces latency").isNil()
            expect(def(FPS_ID).update).as("the framerate refreshes every second").eq(1)
            expect(def(MS_ID).update).as("latency every five").eq(5)
            expect(record(FPS_ID).interval).as("and the ticker took those intervals").eq(1)
            expect(record(MS_ID).interval).eq(5)
        end)

        it("polls latency more slowly than the framerate", function()
            -- The relational claim behind the two numbers: the client only refreshes its
            -- network statistics every few seconds, so asking every second would be work
            -- with nothing to show for it.
            expect(def(MS_ID).update).gt(def(FPS_ID).update)
        end)

        it("stays inside the bar, with neither label clipped", function()
            for _, id in ipairs({ FPS_ID, MS_ID }) do
                H.expectInside(field(id), bar())
                H.expectTextNotClipped(field(id)._label)
            end
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the latency readout sits left of the framerate", function()
        it("declares the lower order", function()
            expect(def(MS_ID).order).lt(def(FPS_ID).order)
            expect(def(MS_ID).order).eq(200)
            expect(def(FPS_ID).order).eq(210)
        end)

        it("is listed first in the section", function()
            local right = H.SuuUI.DataBar:ListSection("right")
            expect(right[1].id).eq(MS_ID)
            expect(right[2].id).eq(FPS_ID)
        end)

        it("is actually drawn to the left of it", function()
            -- The order numbers are the intent; this is the consequence. A section that
            -- ignored `order`, or a flow that laid its children out right-to-left, would
            -- satisfy the two tests above and fail this one.
            local ms, fps = H.box(field(MS_ID)), H.box(field(FPS_ID))
            expect(ms.left).as("MS starts left of FPS").lt(fps.left)
            expect(ms.right).as("and ends before FPS begins").lte(fps.left)
            H.expectNoOverlap({ field(MS_ID), field(FPS_ID) })
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the framerate readout", function()
        it("renders the client's framerate as an integer", function()
            expect(H.env.GetFramerate()).as("the harness default").eq(60)
            expect(say(FPS_ID)).eq("60")
            expect(field(FPS_ID):GetText()).eq("60")
        end)

        it("floors a fractional reading rather than rounding it", function()
            H.setFramerate(59.9)
            expect(say(FPS_ID)).as("floored, so 59.9 is still 59").eq("59")
            H.setFramerate(59.1)
            expect(say(FPS_ID)).eq("59")
        end)

        it("hugs its own prefix and value", function()
            H.expectSize(field(FPS_ID), fieldWidth("FPS", "60"), H.controlHeight("sizeRow"))
        end)

        it("re-derives its width when the font token grows", function()
            local before = field(FPS_ID):GetWidth()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 26)
            H.T:SetActive("Big")
            expect(field(FPS_ID):GetWidth()).gt(before)
            H.expectSize(field(FPS_ID), fieldWidth("FPS", "60"), H.controlHeight("sizeRow"))
            H.expectTextNotClipped(field(FPS_ID)._label)
        end)

        -------------------------------------------------------------------------
        describe("thresholds", function()
            it("is a success above the warn threshold", function()
                local warn = get("fps_warn")
                H.setFramerate(warn + 1)
                tickFor(FPS_ID)
                expect(select(2, say(FPS_ID))).eq("success")
                expectTone(FPS_ID, "success", "colorSuccess")
            end)

            it("is a warning AT the warn threshold, not one frame below it", function()
                -- The code compares with <=, so the threshold value itself is already
                -- warning. Stated at exactly the boundary because that is the only reading
                -- that tells <= from <.
                local warn = get("fps_warn")
                H.setFramerate(warn)
                tickFor(FPS_ID)
                expect(select(2, say(FPS_ID))).eq("warning")
                expectTone(FPS_ID, "warning", "colorWarning")
            end)

            it("is still a warning one frame above the danger threshold", function()
                local danger = get("fps_danger")
                H.setFramerate(danger + 1)
                tickFor(FPS_ID)
                expectTone(FPS_ID, "warning", "colorWarning")
            end)

            it("is danger AT the danger threshold", function()
                local danger = get("fps_danger")
                H.setFramerate(danger)
                tickFor(FPS_ID)
                expect(select(2, say(FPS_ID))).eq("danger")
                expectTone(FPS_ID, "danger", "colorDanger")
            end)

            it("is danger below the danger threshold", function()
                H.setFramerate(get("fps_danger") - 5)
                tickFor(FPS_ID)
                expectTone(FPS_ID, "danger", "colorDanger")
            end)

            it("lets danger outrank warning, since both tests match a bad framerate", function()
                -- 20 fps is at or below BOTH defaults. Danger is checked first, so the worse
                -- of the two wins — which is the only ordering that makes sense and the one
                -- a reordered pair of ifs would break silently.
                H.setFramerate(20)
                expect(20 <= get("fps_warn")).as("the reading matches warn too").truthy()
                tickFor(FPS_ID)
                expectTone(FPS_ID, "danger", "colorDanger")
            end)

            it("repaints on the NEXT tick when a threshold slider moves, with the "
                .. "framerate frozen", function()
                -- This is what folding the tone into the cache key buys. The framerate does
                -- not move in this test at all: a cache keyed on the reading alone would
                -- hold "success" until the framerate happened to change, so a player
                -- dragging the slider would see nothing happen.
                expect(say(FPS_ID)).eq("60")
                expectTone(FPS_ID, "success", "colorSuccess")

                set("fps_warn", 70)
                expectTone(FPS_ID, "success", "colorSuccess")   -- a write does not repaint

                tickFor(FPS_ID)
                expect(H.env.GetFramerate()).as("the framerate never moved").eq(60)
                expect(field(FPS_ID):GetText()).as("nor did the string").eq("60")
                expectTone(FPS_ID, "warning", "colorWarning")
            end)

            it("repaints on a danger slider moving too", function()
                set("fps_danger", 70)
                tickFor(FPS_ID)
                expectTone(FPS_ID, "danger", "colorDanger")
            end)

            it("keeps the tone across a theme edit", function()
                -- ApplyTheme rebuilds the composed string and resets the handle's colour, so
                -- a field sitting in its warning state has to be re-tinted or it silently
                -- drops back to colorText.
                H.setFramerate(get("fps_danger"))
                tickFor(FPS_ID)
                H.T:CreateUserTheme("Edit", "Modern")
                H.T:SetActive("Edit")
                expectTone(FPS_ID, "danger", "colorDanger")
            end)
        end)

        -------------------------------------------------------------------------
        describe("the display cache", function()
            it("does not rewrite the field on every tick", function()
                local spy = H.signalSpy(field(FPS_ID), H.S.SIGNALS.TEXT_CHANGED)
                for _ = 1, 40 do tickFor(FPS_ID) end
                expect(spy.count).as("forty ticks at an unchanged framerate rewrite nothing")
                    .eq(0)

                H.setFramerate(41)
                spy:reset()
                for _ = 1, 4 do tickFor(FPS_ID) end
                expect(spy.count).as("a new framerate writes once, not once per tick").eq(1)
                expect(spy:arg(1)).eq("41")
                expect(field(FPS_ID):GetText()).eq("41")
            end)

            it("formats once per displayed integer, not once per tick", function()
                -- The claim the cache is FOR, and the only assertion here that can tell a
                -- cached widget from an uncached one: both answer the same strings, and the
                -- field drops an unchanged write either way.
                local counter = countFormats(def(FPS_ID).GetText)
                expect(counter.installed)
                    .as("the counter attached to the tostring the widget formats through")
                    .eq(true)

                counter.n = 0
                for _ = 1, 40 do tickFor(FPS_ID) end
                expect(counter.n).as("forty ticks at one framerate format nothing").eq(0)

                H.setFramerate(41)
                for _ = 1, 4 do tickFor(FPS_ID) end
                expect(counter.n).as("the new reading is formatted once, then cached").eq(1)
            end)

            it("does not re-format when only the fraction moves", function()
                local counter = countFormats(def(FPS_ID).GetText)
                expect(counter.installed).eq(true)
                counter.n = 0
                for i = 1, 9 do
                    H.setFramerate(60 + i / 10)   -- 60.1 … 60.9, all floor to 60
                    tickFor(FPS_ID)
                end
                expect(counter.n).as("the displayed integer never moved").eq(0)
                expect(field(FPS_ID):GetText()).eq("60")
            end)
        end)

        -------------------------------------------------------------------------
        describe("readings the client cannot give", function()
            it("renders the placeholder with no tone when GetFramerate is absent", function()
                H.env.GetFramerate = nil
                expect(function() say(FPS_ID) end)
                    .as("an absent global is guarded, not called").notThrows()
                local text, tone = say(FPS_ID)
                expect(text).eq(DASH)
                expect(tone).isNil()

                tickFor(FPS_ID)
                expect(field(FPS_ID):GetText()).eq(DASH)
                expectTone(FPS_ID, nil, "colorText")
            end)

            it("renders the placeholder for a NaN framerate", function()
                -- NaN IS a number and every comparison against it is false, so the range
                -- check alone lets it through — `v ~= v` is the only test that catches it.
                -- Without the guard this field reads "nan" and paints itself success,
                -- because NaN <= danger and NaN <= warn are both false.
                H.setFramerate(0 / 0)
                local text, tone = say(FPS_ID)
                expect(text).as("not the string 'nan'").eq(DASH)
                expect(tone).isNil()

                tickFor(FPS_ID)
                expect(field(FPS_ID):GetText()).eq(DASH)
                expectTone(FPS_ID, nil, "colorText")
            end)

            it("renders the placeholder for a negative framerate", function()
                H.setFramerate(-1)
                expect(say(FPS_ID)).eq(DASH)
            end)

            it("renders the placeholder when the client answers a non-number", function()
                H.env.GetFramerate = function() return "fast" end
                expect(function() say(FPS_ID) end).notThrows()
                expect(say(FPS_ID)).eq(DASH)
            end)

            it("recovers the reading when the client answers again", function()
                H.setFramerate(0 / 0)
                tickFor(FPS_ID)
                expect(field(FPS_ID):GetText()).eq(DASH)
                H.setFramerate(45)
                tickFor(FPS_ID)
                expect(field(FPS_ID):GetText()).as("back to a real reading").eq("45")
                expectTone(FPS_ID, "warning", "colorWarning")
            end)
        end)

        -------------------------------------------------------------------------
        describe("the fps_enabled toggle", function()
            it("is on by default", function()
                expect(get("fps_enabled")).eq(true)
            end)

            it("unregisters the widget and drops the field when switched off", function()
                set("fps_enabled", false)
                expect(H.SuuUI.DataBar:Has(FPS_ID)).as("gone from the registry").eq(false)
                expect(def(FPS_ID)).isNil()
                expect(recordCount(FPS_ID)).as("and gone from the bar").eq(0)
                expect(field(FPS_ID)).isNil()
                expect(H.SuuUI.DataBar:Has(MS_ID))
                    .as("its neighbour is untouched").eq(true)
                expect(recordCount(MS_ID)).eq(1)
            end)

            it("registers it again when switched back on", function()
                set("fps_enabled", false)
                set("fps_enabled", true)
                expect(H.SuuUI.DataBar:Has(FPS_ID)).eq(true)
                expect(recordCount(FPS_ID)).as("exactly one field, not two").eq(1)
                expect(field(FPS_ID):GetText()).eq("60")
            end)

            it("survives a round trip without stacking watchers", function()
                local before = H.SuuUI.Settings:GetWatcherCount()
                set("fps_enabled", false)
                set("fps_enabled", true)
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("the toggle is watched once, whatever it is set to").eq(before)
            end)

            it("drops the watcher on Disable and restores it on Enable", function()
                local before = H.SuuUI.Settings:GetWatcherCount()
                fpsWidget().Disable()
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("one watcher fewer").eq(before - 1)
                expect(H.SuuUI.DataBar:Has(FPS_ID)).eq(false)
                fpsWidget().Enable()
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("and back where it started").eq(before)
                expect(H.SuuUI.DataBar:Has(FPS_ID)).eq(true)
            end)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the latency readout", function()
        it("renders home latency when that is all the client measures", function()
            H.setNetStats(0, 0, 84, 0)
            expect(say(MS_ID)).eq("84")
            tickFor(MS_ID)
            expect(field(MS_ID):GetText()).eq("84")
        end)

        it("prefers world latency when the fourth return is present and non-zero", function()
            -- World latency is the trip to the game server, so it is the one that describes
            -- how the game feels; home is the login/chat server.
            H.setNetStats(0, 0, 84, 210)
            expect(say(MS_ID)).as("the world figure, not the home one").eq("210")
        end)

        it("falls back to home when world is 0, because 0 means 'not measured'", function()
            -- The distinction the widget exists to make: a zero world latency is the client
            -- saying it has no figure, not that the trip is instant, so rendering it would
            -- put an implausible 0 ms on the bar.
            H.setNetStats(0, 0, 84, 0)
            expect(say(MS_ID)).eq("84")
            expect(say(MS_ID)).neq("0")
        end)

        it("falls back to home on the older three-return client", function()
            -- `false`, not 0: an absent fourth return is a different fact from a present
            -- zero, and only one of the two can be produced by passing a number.
            H.setNetStats(0, 0, 96, false)
            expect(function() say(MS_ID) end)
                .as("the missing fourth return is coped with, not indexed").notThrows()
            expect(say(MS_ID)).eq("96")
        end)

        it("floors a fractional latency", function()
            H.setNetStats(0, 0, 0, 120.8)
            expect(say(MS_ID)).eq("120")
        end)

        it("renders the placeholder when GetNetStats is absent", function()
            H.env.GetNetStats = nil
            expect(function() say(MS_ID) end).notThrows()
            local text, tone = say(MS_ID)
            expect(text).eq(DASH)
            expect(tone).isNil()
            tickFor(MS_ID)
            expectTone(MS_ID, nil, "colorText")
        end)

        it("renders the placeholder for a NaN latency", function()
            H.setNetStats(0, 0, 0 / 0, 0 / 0)
            expect(say(MS_ID)).eq(DASH)
        end)

        it("hugs its own prefix and value", function()
            H.setNetStats(0, 0, 84, 0)
            tickFor(MS_ID)
            H.expectSize(field(MS_ID), fieldWidth("MS", "84"), H.controlHeight("sizeRow"))
            H.expectTextNotClipped(field(MS_ID)._label)
        end)

        -------------------------------------------------------------------------
        describe("inverted thresholds", function()
            it("is a success below the warn threshold", function()
                H.setNetStats(0, 0, get("ms_warn") - 1, 0)
                tickFor(MS_ID)
                expect(select(2, say(MS_ID))).eq("success")
                expectTone(MS_ID, "success", "colorSuccess")
            end)

            it("is a warning AT the warn threshold, since high is bad here", function()
                -- The framerate's comparison is <= and this one is >=. Asserted at exactly
                -- the boundary for the same reason, and the pair of them is what states that
                -- the two widgets deliberately disagree about which direction is worse.
                local warn = get("ms_warn")
                H.setNetStats(0, 0, warn, 0)
                tickFor(MS_ID)
                expect(select(2, say(MS_ID))).eq("warning")
                expectTone(MS_ID, "warning", "colorWarning")
            end)

            it("is still a warning one millisecond below danger", function()
                H.setNetStats(0, 0, get("ms_danger") - 1, 0)
                tickFor(MS_ID)
                expectTone(MS_ID, "warning", "colorWarning")
            end)

            it("is danger AT the danger threshold", function()
                H.setNetStats(0, 0, get("ms_danger"), 0)
                tickFor(MS_ID)
                expect(select(2, say(MS_ID))).eq("danger")
                expectTone(MS_ID, "danger", "colorDanger")
            end)

            it("takes its tone from the reading it DISPLAYS, not from home", function()
                -- A healthy home trip and a terrible world trip: the tone has to follow the
                -- number on the bar, or the field paints itself green while showing 900.
                H.setNetStats(0, 0, 20, 900)
                tickFor(MS_ID)
                expect(field(MS_ID):GetText()).eq("900")
                expectTone(MS_ID, "danger", "colorDanger")
            end)

            it("repaints on the NEXT tick when a threshold slider moves, with the "
                .. "latency frozen", function()
                H.setNetStats(0, 0, 100, 0)
                tickFor(MS_ID)
                expectTone(MS_ID, "success", "colorSuccess")

                set("ms_warn", 90)
                expectTone(MS_ID, "success", "colorSuccess")   -- a write does not repaint

                tickFor(MS_ID)
                expect(field(MS_ID):GetText()).as("the reading never moved").eq("100")
                expectTone(MS_ID, "warning", "colorWarning")
            end)
        end)

        -------------------------------------------------------------------------
        describe("the display cache", function()
            it("does not rewrite the field on every tick", function()
                H.setNetStats(0, 0, 84, 0)
                tickFor(MS_ID)
                local spy = H.signalSpy(field(MS_ID), H.S.SIGNALS.TEXT_CHANGED)
                for _ = 1, 8 do tickFor(MS_ID) end
                expect(spy.count).as("eight polls at an unchanged latency rewrite nothing")
                    .eq(0)

                H.setNetStats(0, 0, 85, 0)
                for _ = 1, 4 do tickFor(MS_ID) end
                expect(spy.count).as("a new reading writes once").eq(1)
                expect(field(MS_ID):GetText()).eq("85")
            end)

            it("formats once per displayed integer, not once per poll", function()
                local counter = countFormats(def(MS_ID).GetText)
                expect(counter.installed).eq(true)
                H.setNetStats(0, 0, 84, 0)
                tickFor(MS_ID)

                counter.n = 0
                for _ = 1, 8 do tickFor(MS_ID) end
                expect(counter.n).as("eight polls at one latency format nothing").eq(0)

                H.setNetStats(0, 0, 85, 0)
                for _ = 1, 4 do tickFor(MS_ID) end
                expect(counter.n).as("the new reading is formatted once, then cached").eq(1)
            end)
        end)

        -------------------------------------------------------------------------
        describe("the hover tooltip", function()
            it("breaks the reading down into home, world and traffic", function()
                H.setNetStats(12.5, 3.4, 80, 120)
                local tip = hoverLatency()
                expect(tip).as("a hover builds the tooltip").notNil()
                expect(tip:IsShown()).eq(true)

                local text = tipText(tip)
                expect(text).contains("Home   80 ms")
                expect(text).contains("World  120 ms")
                expect(text).contains("Traffic")
            end)

            it("is big enough for all three rows", function()
                -- The assertion whose absence let a truncated tooltip ship on the clock:
                -- placement and content were both right, and between them they covered
                -- everything except whether the tip could FIT what it had been handed.
                H.setNetStats(12.5, 3.4, 80, 120)
                local tip = hoverLatency()
                expect(tip._text:GetNumLines())
                    .as("home, world and traffic on separate rows").eq(3)
                H.expectTextNotClipped(tip._text)
                H.expectInside(tip._text, tip:GetFrame())
            end)

            it("drops the world row when the client does not measure it", function()
                H.setNetStats(12.5, 3.4, 80, 0)
                local tip = hoverLatency()
                local text = tipText(tip)
                expect(text).contains("Home   80 ms")
                expect(text:find("World", 1, true) == nil)
                    .as("no world row for an unmeasured trip").truthy()
                expect(tip._text:GetNumLines()).as("home and traffic only").eq(2)
                H.expectTextNotClipped(tip._text)
                H.expectInside(tip._text, tip:GetFrame())
            end)

            it("drops the world row on the older three-return client", function()
                H.setNetStats(12.5, 3.4, 96, false)
                local tip = hoverLatency()
                expect(tipText(tip)).contains("Home   96 ms")
                expect(tipText(tip):find("World", 1, true) == nil).truthy()
            end)

            it("says so when there is no network data at all", function()
                H.env.GetNetStats = nil
                local tip = hoverLatency()
                expect(tip).as("the tip is still built").notNil()
                expect(tip:IsShown()).eq(true)
                expect(tipText(tip)).eq("No network data")
                expect(tip._text:GetNumLines()).eq(1)
                H.expectTextNotClipped(tip._text)
                H.expectInside(tip._text, tip:GetFrame())
            end)

            it("draws on screen, below the field", function()
                -- The bar is flush against the screen's top edge, so a tip anchored ABOVE
                -- its trigger renders entirely off-screen. Tooltip flips below when the
                -- trigger leaves no room above; this asserts the flip actually happened for
                -- a trigger the bar owns.
                H.setNetStats(12.5, 3.4, 80, 120)
                local tip = hoverLatency()
                local tb, fb = H.box(tip), H.box(field(MS_ID))
                expect(tb.top).as("top of tip meets bottom of field, plus the token gap")
                    .eq(fb.bottom + H.token("spaceXs"))
                expect(tb.top).as("so the tip starts on screen").gt(0)
            end)

            it("is anchored to the field, not to the cursor", function()
                local tip = hoverLatency()
                expect(tip._anchor.relativeTo).eq(field(MS_ID):GetFrame())
            end)

            it("reuses one tooltip across hovers", function()
                local tips = captureTips()
                H.hover(field(MS_ID))
                H.unhover(field(MS_ID))
                H.hover(field(MS_ID))
                expect(#tips).as("built once, lazily, and kept").eq(1)
            end)

            it("hides on MOUSE_LEAVE", function()
                local tip = hoverLatency()
                expect(tip:IsShown()).eq(true)
                H.unhover(field(MS_ID))
                H.runAnimations()
                expect(tip:IsShown()).as("the fade-out finished and hid it").eq(false)
            end)

            it("follows a changed reading on the next hover", function()
                H.setNetStats(0, 0, 80, 0)
                local tip, tips = hoverLatency()
                expect(tipText(tip)).contains("Home   80 ms")
                H.unhover(field(MS_ID))
                H.setNetStats(0, 0, 300, 0)
                H.hover(field(MS_ID))
                expect(#tips).as("still the one tooltip").eq(1)
                expect(tipText(tip)).as("re-read on each hover, not cached").contains("Home   300 ms")
            end)

            it("the framerate field has no hover behaviour to trigger", function()
                expect(def(FPS_ID).OnEnter).isNil()
                expect(def(FPS_ID).OnLeave).isNil()
                local tips = captureTips()
                H.hover(field(FPS_ID))
                expect(#tips).as("hovering a pure readout builds nothing").eq(0)
            end)
        end)

        -------------------------------------------------------------------------
        describe("the ms_enabled toggle", function()
            it("is on by default", function()
                expect(get("ms_enabled")).eq(true)
            end)

            it("unregisters the widget and drops the field when switched off", function()
                set("ms_enabled", false)
                expect(H.SuuUI.DataBar:Has(MS_ID)).eq(false)
                expect(recordCount(MS_ID)).eq(0)
                expect(field(MS_ID)).isNil()
                expect(H.SuuUI.DataBar:Has(FPS_ID))
                    .as("its neighbour is untouched").eq(true)
            end)

            it("registers it again when switched back on", function()
                set("ms_enabled", false)
                set("ms_enabled", true)
                expect(H.SuuUI.DataBar:Has(MS_ID)).eq(true)
                expect(recordCount(MS_ID)).as("exactly one field, not two").eq(1)
            end)

            it("survives a round trip without stacking watchers", function()
                local before = H.SuuUI.Settings:GetWatcherCount()
                set("ms_enabled", false)
                set("ms_enabled", true)
                expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
            end)
        end)

        -------------------------------------------------------------------------
        describe("teardown", function()
            it("drops the watcher and gives it back on re-enable", function()
                local before = H.SuuUI.Settings:GetWatcherCount()
                latencyWidget().Disable()
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("one watcher fewer than before Disable").eq(before - 1)
                latencyWidget().Enable()
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("and back where it started").eq(before)
            end)

            it("unregisters the widget", function()
                latencyWidget().Disable()
                expect(H.SuuUI.DataBar:Has(MS_ID)).eq(false)
                expect(recordCount(MS_ID)).eq(0)
            end)

            it("destroys the tooltip", function()
                local tips = captureTips()
                H.hover(field(MS_ID))
                local tip = tips[1]
                expect(tip:IsShown()).eq(true)
                latencyWidget().Disable()
                expect(tip:IsShown()).as("Destroy hid it, with no fade to wait for").eq(false)

                latencyWidget().Enable()
                H.hover(field(MS_ID))
                expect(#tips).as("a fresh tooltip, not the destroyed one").eq(2)
                expect(tips[2]).neq(tip)
            end)

            it("Enable re-reads the stored value rather than forcing the widget on", function()
                local before = H.SuuUI.Settings:GetWatcherCount()
                set("ms_enabled", false)
                latencyWidget().Disable()
                expect(H.SuuUI.Settings:GetWatcherCount())
                    .as("Disable retires the watcher even with the widget already gone")
                    .eq(before - 1)
                latencyWidget().Enable()
                expect(H.SuuUI.DataBar:Has(MS_ID))
                    .as("the stored value is still off").eq(false)
                set("ms_enabled", true)
                expect(H.SuuUI.DataBar:Has(MS_ID)).eq(true)
            end)
        end)
    end)

    -----------------------------------------------------------------------------
    -- A field only advertises a rail when its widget declares OnClick or OnEnter, so the
    -- two readouts sitting side by side are the asymmetry in one screenshot: the latency
    -- field can be hovered for a breakdown and says so, the framerate cannot and does not.
    describe("the hover rail", function()
        it("is drawn on the latency field, which has something to show", function()
            H.hover(field(MS_ID))
            expect(field(MS_ID):IsHovered()).eq(true)
            expect(field(MS_ID)._railTex:IsShown())
                .as("the interaction cue is painted").eq(true)
        end)

        it("is NOT drawn on the framerate field, which is a pure readout", function()
            -- Painting it here would promise an interaction that is not there.
            H.hover(field(FPS_ID))
            expect(field(FPS_ID):IsHovered()).as("the hover itself landed").eq(true)
            expect(field(FPS_ID)._railTex:IsShown())
                .as("no rail on a field nothing happens on").eq(false)
        end)

        it("disappears again on MOUSE_LEAVE", function()
            H.hover(field(MS_ID))
            H.unhover(field(MS_ID))
            expect(field(MS_ID)._railTex:IsShown()).eq(false)
        end)

        it("stays inside the field it belongs to", function()
            H.hover(field(MS_ID))
            H.expectInside(field(MS_ID)._railTex, field(MS_ID))
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the shared ticker", function()
        it("holds both readouts on ONE OnUpdate frame", function()
            -- One frame and one script for every ticking widget. Counted as a delta: with
            -- three tickers registered, dropping two must not change the count (they were
            -- never on frames of their own), and dropping the last must remove exactly one
            -- (there was only ever the one).
            local withAll = #updateFrames()
            set("fps_enabled", false)
            set("ms_enabled", false)
            expect(#updateFrames())
                .as("the clock still ticks on the same frame").eq(withAll)

            H.SuuUI.Settings:Set(BAR_ID, "time_enabled", false)
            expect(#updateFrames())
                .as("with nothing left to tick the script is dropped").eq(withAll - 1)
        end)

        it("reuses that frame across a rebuild rather than making a fresh one", function()
            -- The count above cannot see this on its own: a ticker replaced on every rebuild
            -- leaves the old frame behind with its script cleared, so exactly one frame is
            -- ticking either way while the bar quietly leaks a frame per registration —
            -- and every widget toggle triggers a full rebuild. Identity is what states it.
            --
            -- Compared as a SET rather than by picking one frame out, so the assertion does
            -- not have to guess which OnUpdate frame belongs to the bar.
            local before = updateFrames()
            expect(#before).as("something is ticking to begin with").gte(1)

            set("fps_enabled", false)   -- any (un)registration rebuilds every field

            local after = updateFrames()
            expect(#after).as("the same number of frames tick afterwards").eq(#before)
            local seen = {}
            for _, f in ipairs(before) do seen[f] = true end
            for i, f in ipairs(after) do
                expect(seen[f])
                    .as("ticking frame " .. i .. " is the same object as before the rebuild")
                    .truthy()
            end
        end)

        it("keeps the two intervals apart", function()
            H.setFramerate(42)
            H.setNetStats(0, 0, 250, 0)
            expect(field(MS_ID):GetText()).as("the latency before anything ticks").eq("0")

            H.tick(1)
            expect(field(FPS_ID):GetText()).as("the 1s readout refreshed").eq("42")
            expect(field(MS_ID):GetText())
                .as("the 5s readout is untouched by a 1s tick").eq("0")

            for _ = 1, 3 do H.tick(1) end        -- 4s elapsed
            expect(field(MS_ID):GetText()).as("still short of five seconds").eq("0")

            H.tick(1)                            -- 5s elapsed
            expect(field(MS_ID):GetText()).as("and now it polls").eq("250")
        end)

        it("refreshes the framerate five times while latency refreshes once", function()
            local fpsSpy = H.signalSpy(field(FPS_ID), H.S.SIGNALS.TEXT_CHANGED)
            local msSpy  = H.signalSpy(field(MS_ID), H.S.SIGNALS.TEXT_CHANGED)
            for i = 1, 5 do
                H.setFramerate(50 + i)
                H.setNetStats(0, 0, 200 + i, 0)
                H.tick(1)
            end
            expect(fpsSpy.count).as("one write per second").eq(5)
            expect(msSpy.count).as("one write in five seconds").eq(1)
            expect(field(FPS_ID):GetText()).eq("55")
            expect(field(MS_ID):GetText()).eq("205")
        end)

        it("keeps ticking the framerate when latency is switched off", function()
            set("ms_enabled", false)
            H.setFramerate(33)
            H.tick(1)
            expect(field(FPS_ID):GetText())
                .as("dropping one record does not stop the loop").eq("33")
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the plugin", function()
        it("registers under its own id, not the data bar's", function()
            expect(plugin()).notNil()
            expect(plugin().id).eq(PLUGIN_ID)
            expect(plugin():IsEnabled()).eq(true)
        end)

        it("splices both widget slices into one schema, after its own key", function()
            local registered = H.SuuUI.Settings:GetSchema(PLUGIN_ID)
            expect(registered).notNil()
            expect(#registered).as("one plugin key plus two four-entry slices").eq(9)

            local seen, order = {}, {}
            for i, entry in ipairs(registered) do
                if entry.key and entry.key ~= "" then
                    seen[entry.key] = (seen[entry.key] or 0) + 1
                    order[entry.key] = i
                end
            end
            for _, key in ipairs({ "fps_enabled", "fps_warn", "fps_danger",
                                   "ms_enabled", "ms_warn", "ms_danger" }) do
                expect(seen[key]).as(key .. " registered exactly once").eq(1)
                expect(order[key]).as(key .. " follows the plugin's own key")
                    .gt(order["enabled"])
            end
            expect(order["fps_danger"])
                .as("the framerate slice comes before the latency slice")
                .lt(order["ms_enabled"])
        end)

        it("answers the documented defaults through the registry", function()
            expect(get("enabled")).eq(true)
            expect(get("fps_enabled")).eq(true)
            expect(get("fps_warn")).eq(50)
            expect(get("fps_danger")).eq(30)
            expect(get("ms_enabled")).eq(true)
            expect(get("ms_warn")).eq(150)
            expect(get("ms_danger")).eq(300)
        end)

        it("puts the keys under the plugin id, not the widget ids", function()
            expect(H.SuuUI.Settings:Get(FPS_ID, "fps_warn"))
                .as("a widget id is not a settings namespace").isNil()
            expect(H.SuuUI.Settings:Get(MS_ID, "ms_warn")).isNil()
            expect(H.SuuUI.Settings:Get(BAR_ID, "fps_warn"))
                .as("and a widget cannot reach the data bar's page").isNil()
        end)

        it("namespaces each widget's keys with its own prefix", function()
            -- Two widgets in one plugin share a settings namespace, so a widget's keys
            -- carry its own prefix or the second one to ship silently collides.
            for i = 2, #fpsWidget().Schema() do
                expect(fpsWidget().Schema()[i].key).as("fps key " .. i).matches("^fps_")
            end
            for i = 2, #latencyWidget().Schema() do
                expect(latencyWidget().Schema()[i].key).as("ms key " .. i).matches("^ms_")
            end
        end)

        it("lets each widget own its own section header", function()
            local fpsHead = fpsWidget().Schema()[1]
            expect(fpsHead.type).eq("section")
            expect(fpsHead.label).eq("Framerate")
            expect(fpsHead.key).as("a header holds no value").eq("")

            local msHead = latencyWidget().Schema()[1]
            expect(msHead.type).eq("section")
            expect(msHead.label).eq("Latency")
            expect(msHead.key).eq("")
        end)

        it("declares the framerate slice exactly as documented", function()
            local s = fpsWidget().Schema()
            expect(#s).eq(4)
            expect(s[2]).deepEq({
                key = "fps_enabled", label = "Show Framerate", type = "toggle",
                default = true,
            })
            expect(s[3]).deepEq({
                key = "fps_warn", label = "Warn Below", type = "slider", default = 50,
                min = 15, max = 120, step = 1, enabledIf = "fps_enabled",
            })
            expect(s[4]).deepEq({
                key = "fps_danger", label = "Danger Below", type = "slider", default = 30,
                min = 5, max = 100, step = 1, enabledIf = "fps_enabled",
            })
        end)

        it("declares the latency slice exactly as documented", function()
            local s = latencyWidget().Schema()
            expect(#s).eq(4)
            expect(s[2]).deepEq({
                key = "ms_enabled", label = "Show Latency", type = "toggle", default = true,
            })
            expect(s[3]).deepEq({
                key = "ms_warn", label = "Warn Above", type = "slider", default = 150,
                min = 50, max = 1000, step = 10, enabledIf = "ms_enabled",
            })
            expect(s[4]).deepEq({
                key = "ms_danger", label = "Danger Above", type = "slider", default = 300,
                min = 100, max = 2000, step = 10, enabledIf = "ms_enabled",
            })
        end)

        it("greys both thresholds out with their own widget's toggle", function()
            expect(fpsWidget().Schema()[3].enabledIf).eq("fps_enabled")
            expect(fpsWidget().Schema()[4].enabledIf).eq("fps_enabled")
            expect(latencyWidget().Schema()[3].enabledIf).eq("ms_enabled")
            expect(latencyWidget().Schema()[4].enabledIf).eq("ms_enabled")
        end)

        it("hands out a fresh slice each call", function()
            expect(fpsWidget().Schema()).neq(fpsWidget().Schema())
            local mine = fpsWidget().Schema()
            mine[2].default = false
            expect(get("fps_enabled"))
                .as("mutating a slice cannot reach the registry").eq(true)
        end)

        it("takes both readouts down with the enable toggle", function()
            set("enabled", false)
            expect(plugin():IsEnabled()).eq(false)
            expect(H.SuuUI.DataBar:Has(FPS_ID)).eq(false)
            expect(H.SuuUI.DataBar:Has(MS_ID)).eq(false)
            expect(recordCount(FPS_ID)).eq(0)
            expect(recordCount(MS_ID)).eq(0)
            expect(#bar():GetSection("right"):GetChildren())
                .as("the right section is empty").eq(0)
            expect(H.SuuUI.DataBar:Has("databar.time"))
                .as("the clock, which belongs to another plugin, is untouched").eq(true)
        end)

        it("brings both back when the toggle goes on again", function()
            set("enabled", false)
            set("enabled", true)
            expect(plugin():IsEnabled()).eq(true)
            expect(recordCount(FPS_ID)).as("one framerate field, not two").eq(1)
            expect(recordCount(MS_ID)).as("one latency field, not two").eq(1)
            expect(field(FPS_ID):GetText()).eq("60")
        end)

        it("leaves the registry and the watcher count clean across a round trip", function()
            local widgetsBefore  = #H.SuuUI.DataBar:List()
            local watchersBefore = H.SuuUI.Settings:GetWatcherCount()
            local subsBefore     = H.SuuUI.DataBar:GetSubscriberCount()

            plugin():Disable()
            expect(#H.SuuUI.DataBar:List())
                .as("both widgets left the registry").eq(widgetsBefore - 2)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("and both widget watchers with them").eq(watchersBefore - 2)

            plugin():Enable()
            expect(#H.SuuUI.DataBar:List()).eq(widgetsBefore)
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(watchersBefore)
            expect(H.SuuUI.DataBar:GetSubscriberCount())
                .as("a bar-widget plugin subscribes to nothing itself").eq(subsBefore)
        end)

        it("does not stack watchers across repeated round trips", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            for _ = 1, 3 do
                plugin():Disable()
                plugin():Enable()
            end
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
            expect(recordCount(FPS_ID)).eq(1)
            expect(recordCount(MS_ID)).eq(1)
        end)

        it("names the data bar nowhere, which is what the registry is for", function()
            -- The structural claim of the whole plugin: it registers widgets into Core and
            -- never reaches for the bar's plugin, frame or load order. Disabling the bar
            -- must therefore leave the performance widgets registered and answering.
            H.SuuUI.Plugins:Get(BAR_ID):Disable()
            expect(H.SuuUI.DataBar:Has(FPS_ID))
                .as("the widget outlives the renderer").eq(true)
            expect(H.SuuUI.DataBar:Has(MS_ID)).eq(true)
            expect(say(FPS_ID)).as("and still answers with no bar to draw it").eq("60")
        end)

        it("renders both readouts again when the bar comes back", function()
            H.SuuUI.Plugins:Get(BAR_ID):Disable()
            H.SuuUI.Plugins:Get(BAR_ID):Enable()
            expect(recordCount(FPS_ID)).eq(1)
            expect(recordCount(MS_ID)).eq(1)
            expect(field(FPS_ID):GetText()).eq("60")
        end)
    end)

    -----------------------------------------------------------------------------
    -- A tooltip must not outlive the trigger it is anchored to. It used to: Bar:_clearFields
    -- disconnected a field's signals and destroyed it, so no MOUSE_LEAVE ever reached
    -- LatencyWidget.OnLeave and the tip stayed visible over a frame the client had just
    -- hidden, self-healing only on the next hover because OnEnter re-anchors the cached tip.
    --
    -- The mechanism was DataBar-wide rather than specific to this plugin — the clock's tooltip
    -- has the same shape — so the fix is in the bar: _clearFields now calls the widget's own
    -- OnLeave hook for a field that is still hovered, before it disconnects anything. Calling
    -- the hook rather than emitting a synthetic MOUSE_LEAVE matters, because the bar called
    -- OnEnter itself and owes the matching OnLeave; emitting a mouse signal that describes no
    -- real mouse movement would be a different and less honest claim.
    describe("a rebuild while the tooltip is showing", function()
        it("hides the tooltip when the field it describes is destroyed", function()
            local tip = hoverLatency()
            expect(tip:IsShown()).as("showing before the rebuild").eq(true)
            -- Any registration or unregistration rebuilds every field on the bar.
            set("fps_enabled", false)
            expect(field(MS_ID)).as("the latency field was rebuilt").notNil()
            -- Animations are run before the assertion on purpose: HideTip fades rather than
            -- hiding, so IsShown() immediately after a rebuild cannot tell "nothing closed it"
            -- from "a fade-out has begun".
            H.runAnimations()
            expect(tip:IsShown())
                .as("a tooltip must not outlive the trigger it is anchored to")
                .eq(false)
        end)

        it("re-anchors the orphaned tip to the new field on the next hover", function()
            local tip, tips = hoverLatency()
            local oldFrame = field(MS_ID):GetFrame()
            set("fps_enabled", false)
            local newFrame = field(MS_ID):GetFrame()
            expect(newFrame).as("a genuinely new field").neq(oldFrame)

            H.hover(field(MS_ID))
            expect(#tips).as("the same tooltip object, reused").eq(1)
            expect(tip._anchor.relativeTo)
                .as("re-pointed at the field that exists now").eq(newFrame)
        end)

        -- Worth keeping from the investigation: fixing this in DataField:Destroy instead would
        -- change NOTHING, and that was measured rather than reasoned — _clearFields disconnects
        -- on the line BEFORE it destroys, so an emit from Destroy lands with no listeners. That
        -- ruled out the obvious location before anyone tried it.
    end)
end)
