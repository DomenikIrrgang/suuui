local H = require("harness")

-- The built-in clock, the one widget the DataBar plugin ships and the reference for what a
-- widget definition looks like. It builds no frames, so this spec asserts three things: the
-- STRING it answers (which is the whole of its logic), the FIELD the bar builds from it
-- (geometry, prefix, repaint cadence), and its lifecycle through the enable toggle.
--
-- Time strings are asserted as literals on purpose, and that is not the hardcoded-pixel
-- trap: the string IS the claim ("a 12-hour clock does not print a leading zero"), and it is
-- stated against a clock this spec pins itself with H.setClock. Every PIXEL expectation
-- below is derived from tokens.

local PLUGIN_ID = "data_bar"
local WIDGET_ID = "databar.time"

-- The harness wall clock's default instant, in UTC parts: 2026-08-22 14:32:07. date() is
-- forced to UTC by the harness so these hold on any machine's timezone — see the
-- "wall clock and realm clock" block in Tests/spec/00_harness_spec.lua.
local DEFAULT_EPOCH = 1787409127

local function widget() return H.SuuUI._DataBar.TimeWidget end
local function def() return H.SuuUI.DataBar:GetWidget(WIDGET_ID) end
local function text() return def().GetText() end
local function plugin() return H.SuuUI.Plugins:Get(PLUGIN_ID) end
local function bar() return plugin()._bar end
local function set(key, value) H.SuuUI.Settings:Set(PLUGIN_ID, key, value) end
local function get(key) return H.SuuUI.Settings:Get(PLUGIN_ID, key) end

-- The bar's record for the clock, which is where its field lives.
local function record()
    for _, rec in ipairs(bar()._records) do
        if rec.def.id == WIDGET_ID then return rec end
    end
end

local function field()
    local rec = record()
    return rec and rec.field
end

-- Captures the Tooltip the widget builds. It is created lazily on the first hover and kept
-- in a private upvalue, so wrapping the constructor is the only way a spec gets the handle —
-- the same capture pattern the settings-page specs use for Dropdown and Slider.
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

-- The tip's text, read off the font string the component actually renders.
local function tipText(tip) return tip._text:GetText() end

-- Hovers the clock field and returns the tooltip that showed.
local function hoverClock()
    local tips = captureTips()
    H.hover(field())
    return tips[1], tips
end

-- What a field hugging `str` must be: its own text box plus the field's own padding, a
-- spaceMd inset either side. Derived so a spacing or font token edit moves the expectation.
local function fieldWidth(str)
    return H.textBox(str, H.token("fontSizeMd")) + H.token("spaceMd") * 2
end

-- Counts how often the widget FORMATS, rather than what it answers.
--
-- The cache is a performance guarantee — the bar asks twice a second and the widget must
-- format at most once per display quantum — and that is invisible from the string alone: a
-- formatter with no cache at all returns exactly the same text, and the field drops the
-- unchanged write, so every value assertion in this file passes either way. Counting the
-- calls is the only way to state it.
--
-- This instruments the real code path rather than faking one: the ticks below still travel
-- the bar's own OnUpdate. `date` is a chunk-level local captured when the file loads, so the
-- counter goes in through the upvalue cell it was captured into, which every closure in that
-- chunk shares. It reports whether it attached, and the test asserts that first — an
-- assertion that silently stopped measuring would be worse than no assertion.
local function countFormats()
    local counter, seen = { n = 0 }, {}
    local function patch(fn, depth)
        if depth > 4 or type(fn) ~= "function" or seen[fn] then return false end
        seen[fn] = true
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == "date" and type(value) == "function" then
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
    counter.installed = patch(def().GetText, 1)
    return counter
end

describe("Plugins.DataBar – Clock widget", function()
    before_each(function() H.setup() end)

    -----------------------------------------------------------------------------
    describe("registration", function()
        it("registers itself on login", function()
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).as("the clock is registered").eq(true)
        end)

        it("declares a text widget, not custom visuals", function()
            expect(type(def().GetText)).as("answers a string").eq("function")
            expect(def().Build).as("builds no frames of its own").isNil()
        end)

        it("sits in the centre section", function()
            expect(def().section).eq("center")
            expect(H.SuuUI.DataBar:ListSection("center")[1].id).eq(WIDGET_ID)
        end)

        it("asks for a sub-second ticker, since nothing announces a passing second", function()
            expect(def().update).as("refresh interval in seconds").gt(0)
            expect(def().update).as("fast enough that a seconds display does not stutter").lte(1)
            expect(def().events).as("no game event can announce the time").isNil()
        end)

        it("gives the bar exactly one field, showing the clock", function()
            expect(#bar()._records).eq(1)
            expect(record().def.id).eq(WIDGET_ID)
            expect(field():GetText()).eq("14:32")
        end)

        it("is the ticker's only entry, at the interval it declared", function()
            expect(record().interval).eq(def().update)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("24-hour format (the default)", function()
        it("renders the wall clock as HH:MM", function()
            expect(get("time_format")).as("24-hour is the default").eq("24")
            expect(text()).eq("14:32")
        end)

        it("keeps the leading zero on a single-digit hour", function()
            -- The contrast case for the 12-hour strip below: a 24-hour clock is zero-padded,
            -- so a strip applied to both formats would show "8:05" here.
            H.setClock({ year = 2026, month = 8, day = 22, hour = 8, min = 5, sec = 0 })
            expect(text()).eq("08:05")
        end)

        it("renders midnight as 00:xx", function()
            H.setClock({ year = 2026, month = 1, day = 1, hour = 0, min = 5, sec = 0 })
            expect(text()).eq("00:05")
        end)

        it("renders noon as 12:00", function()
            H.setClock({ year = 2026, month = 8, day = 22, hour = 12, min = 0, sec = 0 })
            expect(text()).eq("12:00")
        end)
    end)

    -----------------------------------------------------------------------------
    describe("12-hour format", function()
        before_each(function() set("time_format", "12") end)

        it("renders 2:32 PM with no leading zero", function()
            expect(text()).eq("2:32 PM")
            -- Stated separately because %I is zero-padded and a leading zero on a 12-hour
            -- clock reads as a 24-hour one — the exact string the strip exists to prevent.
            expect(text()).as("a padded hour would read as a 24-hour clock").neq("02:32 PM")
        end)

        it("strips the zero from a single-digit morning hour", function()
            H.setClock({ year = 2026, month = 8, day = 22, hour = 9, min = 5, sec = 0 })
            expect(text()).eq("9:05 AM")
        end)

        it("leaves a two-digit hour alone", function()
            H.setClock({ year = 2026, month = 8, day = 22, hour = 10, min = 5, sec = 0 })
            expect(text()).eq("10:05 AM")
        end)

        it("renders midnight as 12:05 AM, not 00:05", function()
            H.setClock({ year = 2026, month = 1, day = 1, hour = 0, min = 5, sec = 0 })
            expect(text()).eq("12:05 AM")
        end)

        it("renders noon as 12:00 PM", function()
            H.setClock({ year = 2026, month = 8, day = 22, hour = 12, min = 0, sec = 0 })
            expect(text()).eq("12:00 PM")
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the seconds setting", function()
        it("is off by default", function()
            expect(get("time_seconds")).eq(false)
        end)

        it("adds the seconds to a 24-hour clock", function()
            set("time_seconds", true)
            expect(text()).eq("14:32:07")
        end)

        it("adds the seconds to a 12-hour clock, still unpadded", function()
            set("time_format", "12")
            set("time_seconds", true)
            expect(text()).eq("2:32:07 PM")
            expect(text()).neq("02:32:07 PM")
        end)

        it("widens the field to the longer string without clipping it", function()
            local before = field():GetWidth()
            set("time_seconds", true)
            H.tick(def().update)
            expect(field():GetText()).eq("14:32:07")
            H.expectSize(field(), fieldWidth("14:32:07"), H.controlHeight("sizeRow"))
            expect(field():GetWidth()).as("a longer readout needs a wider field").gt(before)
            H.expectTextNotClipped(field()._label)
        end)
    end)

    -----------------------------------------------------------------------------
    -- The cache. The bar asks twice a second so a seconds display stays smooth, but the
    -- string changes at most once a second and usually once a minute, so the widget compares
    -- a key before formatting anything.
    describe("the display cache", function()
        it("answers the same string within the display quantum", function()
            local first = text()
            H.setClock(DEFAULT_EPOCH + 20)   -- 14:32:27, still the same minute
            expect(text()).as("nothing on screen has changed").eq(first)
            expect(text()).eq("14:32")
        end)

        it("answers a new string across a minute boundary", function()
            expect(text()).eq("14:32")
            H.setClock(DEFAULT_EPOCH + 60)
            expect(text()).eq("14:33")
        end)

        it("follows the second when seconds are shown", function()
            set("time_seconds", true)
            expect(text()).eq("14:32:07")
            H.setClock(DEFAULT_EPOCH + 1)
            expect(text()).as("the quantum follows the setting").eq("14:32:08")
        end)

        it("repaints on a format change without waiting for the next minute", function()
            -- The clock is mid-minute (sec = 07) and never moves in this test, so a cache
            -- keyed on the clock alone would hold "14:32" until 14:33 — which is what folding
            -- both settings into the key prevents.
            expect(text()).eq("14:32")
            set("time_format", "12")
            expect(text()).as("no clock movement, new string").eq("2:32 PM")
            set("time_format", "24")
            expect(text()).as("and back again").eq("14:32")
        end)

        it("repaints on a seconds change without waiting for the next minute", function()
            expect(text()).eq("14:32")
            set("time_seconds", true)
            expect(text()).eq("14:32:07")
        end)

        it("reaches the bar on the next tick, not at the next minute boundary", function()
            expect(field():GetText()).eq("14:32")
            set("time_format", "12")
            expect(field():GetText()).as("a setting write does not repaint on its own").eq("14:32")
            H.tick(def().update)
            expect(field():GetText()).as("the next tick carries it, mid-minute").eq("2:32 PM")
        end)

        it("does not rewrite the field on every tick", function()
            -- What the cache is FOR. Twenty seconds of ticks inside one minute must leave the
            -- field's value untouched; crossing the boundary must write it exactly once.
            local spy = H.signalSpy(field(), H.S.SIGNALS.TEXT_CHANGED)
            for _ = 1, 40 do H.tick(def().update) end
            expect(spy.count).as("40 ticks inside one minute rewrite nothing").eq(0)

            H.setClock(DEFAULT_EPOCH + 60)
            spy:reset()
            for _ = 1, 4 do H.tick(def().update) end
            expect(spy.count).as("crossing the minute writes once, not once per tick").eq(1)
            expect(spy:arg(1)).eq("14:33")
            expect(field():GetText()).eq("14:33")
        end)

        it("formats once per display quantum, not once per tick", function()
            -- The claim the cache is FOR, and the only assertion in this file that can tell a
            -- cached widget from an uncached one: both answer the same strings.
            local counter = countFormats()
            expect(counter.installed)
                .as("the counter attached to the date() the widget formats through").eq(true)

            counter.n = 0
            -- Forty ticks across forty seconds of ONE minute. The wall clock really moves —
            -- a frozen clock would pass whether or not the key is quantised to the minute —
            -- and with seconds off nothing on screen changes, so nothing should be formatted.
            for i = 1, 40 do
                H.setClock(DEFAULT_EPOCH + i)   -- 14:32:08 … 14:32:47
                H.tick(def().update)
            end
            expect(counter.n).as("forty seconds inside one minute format nothing").eq(0)

            H.setClock(DEFAULT_EPOCH + 53)      -- 14:33:00
            for _ = 1, 4 do H.tick(def().update) end
            expect(counter.n).as("the new minute is formatted once, then cached").eq(1)
        end)

        it("formats once per second when seconds are shown", function()
            set("time_seconds", true)
            local counter = countFormats()
            counter.n = 0
            for _ = 1, 6 do H.tick(def().update) end
            expect(counter.n).as("a frozen second still formats only once").eq(1)

            H.setClock(DEFAULT_EPOCH + 1)
            for _ = 1, 6 do H.tick(def().update) end
            expect(counter.n).as("and the next second exactly once more").eq(2)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the enable toggle", function()
        it("is on by default", function()
            expect(get("time_enabled")).eq(true)
        end)

        it("unregisters the widget and drops the field when switched off", function()
            set("time_enabled", false)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).as("gone from the registry").eq(false)
            expect(H.SuuUI.DataBar:GetWidget(WIDGET_ID)).isNil()
            expect(#bar()._records).as("and gone from the bar").eq(0)
            expect(#bar():GetSection("center"):GetChildren())
                .as("the centre section is empty").eq(0)
        end)

        it("registers it again when switched back on", function()
            set("time_enabled", false)
            set("time_enabled", true)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(true)
            expect(#bar()._records).as("exactly one field, not two").eq(1)
            expect(field():GetText()).eq("14:32")
        end)

        it("survives a round trip without stacking watchers", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("time_enabled", false)
            set("time_enabled", true)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("the toggle is watched once, whatever it is set to").eq(before)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("no prefix", function()
        it("declares none", function()
            -- "14:32" is self-evident; a muted "TIME" in front of it would be noise, and the
            -- widget contract makes the prefix optional for exactly this case.
            expect(def().prefix).as("the definition declares no prefix").isNil()
        end)

        it("builds a field with an empty prefix", function()
            expect(field():GetPrefix()).eq("")
        end)

        it("is exactly as wide as its own value plus the field's padding", function()
            -- The measurable consequence: a prefix would add its own text and a separating
            -- space, so this width is the assertion that nothing precedes the value.
            H.expectSize(field(), fieldWidth("14:32"), H.controlHeight("sizeRow"))
        end)

        it("stays inside the bar", function()
            H.expectInside(field(), bar())
            H.expectTextNotClipped(field()._label)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("token-driven sizing", function()
        it("re-derives its width when the font token grows", function()
            local before = field():GetWidth()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 26)
            H.T:SetActive("Big")
            expect(field():GetWidth()).gt(before)
            H.expectSize(field(), fieldWidth("14:32"), H.controlHeight("sizeRow"))
            H.expectTextNotClipped(field()._label)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the hover tooltip", function()
        it("shows local and realm time", function()
            local tip = hoverClock()
            expect(tip).as("a hover builds the tooltip").notNil()
            expect(tip:IsShown()).eq(true)
            expect(tipText(tip)).eq("Local  14:32\nRealm  14:32")
        end)

        it("carries the realm clock when it diverges from the player's", function()
            -- The divergence is the whole reason the hover exists: local time is already on
            -- the bar, so the tip carries the one a player cannot read off it.
            H.setRealmTime(3, 7)
            local tip = hoverClock()
            expect(tipText(tip)).eq("Local  14:32\nRealm  03:07")
        end)

        it("renders realm time in the player's chosen format", function()
            set("time_format", "12")
            H.setRealmTime(15, 7)
            local tip = hoverClock()
            expect(tipText(tip)).eq("Local  2:32 PM\nRealm  3:07 PM")
        end)

        it("renders realm midnight as 12:00 AM on a 12-hour clock", function()
            set("time_format", "12")
            H.setRealmTime(0, 0)
            local tip = hoverClock()
            expect(tipText(tip)).contains("Realm  12:00 AM")
        end)

        it("follows the seconds setting", function()
            set("time_seconds", true)
            local tip = hoverClock()
            expect(tipText(tip)).contains("Local  14:32:07")
        end)

        it("shows local time only when the realm clock is unavailable", function()
            H.env.GetGameTime = function() return nil end
            local tip = hoverClock()
            expect(tip:IsShown()).eq(true)
            expect(tipText(tip)).as("no realm line at all").eq("Local  14:32")
        end)

        it("reuses one tooltip across hovers", function()
            local tips = captureTips()
            H.hover(field())
            H.unhover(field())
            H.hover(field())
            expect(#tips).as("built once, lazily, and kept").eq(1)
        end)

        it("hides on MOUSE_LEAVE", function()
            local tip = hoverClock()
            expect(tip:IsShown()).eq(true)
            H.unhover(field())
            H.runAnimations()
            expect(tip:IsShown()).as("the fade-out finished and hid it").eq(false)
        end)

        it("is anchored to the field, not to the cursor", function()
            local tip = hoverClock()
            expect(tip._anchor.relativeTo).eq(field():GetFrame())
        end)

        -- BUG, pinned. The bar is placed at the screen's TOPLEFT (DataBarWidget.lua:336) and
        -- Tooltip:ShowTip anchors a tip's BOTTOM to its trigger's TOP (Tooltip.lua:60-61), so
        -- handing the field over as the anchor frame (TimeWidget.lua:99) puts the whole tip
        -- ABOVE the top of the screen, where the client draws none of it. Every other Tooltip
        -- consumer sits inside a window somewhere in the middle of the screen, which is why
        -- this is the first trigger flush against an edge.
        it("draws the tooltip on screen, below the field", function()
            -- The bar sits flush against the screen's top edge, so a tip anchored ABOVE the
            -- clock's field rendered entirely off-screen: the field's box has top = 0 and the
            -- tip landed at top = -42, so hovering the clock showed the player nothing.
            -- Tooltip flips below when the trigger leaves no room above, which fixes it for
            -- every edge-anchored trigger rather than only this one.
            local tip = hoverClock()
            local tb, fb = H.box(tip), H.box(field())
            expect(tb.top).as("top of tip meets bottom of field, plus the token gap")
                .eq(fb.bottom + H.token("spaceXs"))
            expect(tb.top).as("so the tip starts on screen").gt(0)
        end)

        it("is big enough for both rows", function()
            -- The assertion whose absence let a truncated tooltip ship. The placement was
            -- right and the text content was right, and between them they covered everything
            -- except whether the tip could actually FIT what it had been handed -- so it
            -- rendered "Local  22:17..." on one row and every test still passed.
            local tip = hoverClock()
            expect(tip._text:GetNumLines()).as("local and realm on separate rows").eq(2)
            H.expectTextNotClipped(tip._text)
            H.expectInside(tip._text, tip:GetFrame())
        end)

        -- The widget guards what GetGameTime RETURNS and, now, that it EXISTS. Called
        -- unconditionally, an absent global raised inside the bar's pcall and the whole OnEnter
        -- was lost — so the player got no tooltip at all rather than the local time it could
        -- still show. Every live client defines it, so this is robustness rather than a shipped
        -- failure, but the failure mode was disproportionate to the cause.
        it("degrades to local time when GetGameTime does not exist", function()
            H.setup({ debug = true })
            H.env.GetGameTime = nil
            local tip = hoverClock()
            expect(tip).as("the tip is built").notNil()
            expect(tip:IsShown()).as("and shown, with the realm line simply absent").eq(true)

            local text = tip._text:GetText() or ""
            expect(text:find("14:32", 1, true) ~= nil)
                .as("local time is still there").truthy()
            expect(text:find("Realm", 1, true) == nil)
                .as("and no realm line").truthy()
        end)
    end)

    -----------------------------------------------------------------------------
    describe("the settings schema", function()
        local function slice() return widget().Schema() end

        it("opens with its own section header", function()
            local entry = slice()[1]
            expect(entry.type).eq("section")
            expect(entry.label).as("the widget owns its section header").eq("Clock")
            expect(entry.key).as("a header holds no value").eq("")
        end)

        it("declares three settings with the documented defaults", function()
            local entries = slice()
            expect(#entries).eq(4)
            expect(entries[2]).deepEq({
                key = "time_enabled", label = "Show Clock", type = "toggle", default = true,
            })
            expect(entries[3].key).eq("time_format")
            expect(entries[3].type).eq("dropdown")
            expect(entries[3].default).eq("24")
            expect(entries[4]).deepEq({
                key = "time_seconds", label = "Show Seconds", type = "toggle", default = false,
            })
        end)

        it("offers exactly the two clock formats, 24-hour first", function()
            local options = slice()[3].options
            expect(#options).eq(2)
            expect(options[1].value).eq("24")
            expect(options[2].value).eq("12")
            expect(options[1].label).contains("14:32")
            expect(options[2].label).contains("2:32 PM")
        end)

        it("namespaces every key inside the plugin", function()
            -- Two widgets in one plugin share a settings namespace, so a widget's keys carry
            -- its own prefix or the second one to ship silently collides.
            for i = 2, #slice() do
                expect(slice()[i].key).as("key " .. i).matches("^time_")
            end
        end)

        it("is spliced into the plugin's schema once, after the plugin's own keys", function()
            local registered = H.SuuUI.Settings:GetSchema(PLUGIN_ID)
            local seen, order = {}, {}
            for i, entry in ipairs(registered) do
                if entry.key and entry.key ~= "" then
                    seen[entry.key] = (seen[entry.key] or 0) + 1
                    order[entry.key] = i
                end
            end
            for _, key in ipairs({ "time_enabled", "time_format", "time_seconds" }) do
                expect(seen[key]).as(key .. " registered exactly once").eq(1)
                expect(order[key]).as(key .. " follows the plugin's own settings")
                    .gt(order["move_blizzard"])
            end
            expect(order["time_enabled"]).lt(order["time_format"])
            expect(order["time_format"]).lt(order["time_seconds"])
        end)

        it("answers those defaults through the registry, under the plugin's id", function()
            expect(get("time_enabled")).eq(true)
            expect(get("time_format")).eq("24")
            expect(get("time_seconds")).eq(false)
            expect(H.SuuUI.Settings:Get("databar.time", "time_format"))
                .as("the keys belong to the plugin, not to the widget id").isNil()
        end)

        it("hands out a fresh slice each call", function()
            expect(slice()).neq(slice())
            local mine = slice()
            mine[2].default = false
            expect(get("time_enabled")).as("mutating a slice cannot reach the registry").eq(true)
        end)
    end)

    -----------------------------------------------------------------------------
    describe("teardown", function()
        it("drops the settings watcher", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            widget().Disable()
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("one watcher fewer than before Disable").eq(before - 1)
            widget().Enable()
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("and back where it started on re-enable").eq(before)
        end)

        it("unregisters the widget", function()
            widget().Disable()
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(false)
            expect(#bar()._records).eq(0)
        end)

        it("destroys the tooltip", function()
            local tips = captureTips()
            H.hover(field())
            local tip = tips[1]
            expect(tip:IsShown()).eq(true)
            widget().Disable()
            expect(tip:IsShown()).as("Destroy hid it, with no fade to wait for").eq(false)

            widget().Enable()
            H.hover(field())
            expect(#tips).as("a fresh tooltip, not the destroyed one").eq(2)
            expect(tips[2]).neq(tip)
        end)

        it("stops answering after the toggle goes off, then answers again", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            set("time_enabled", false)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(false)
            widget().Disable()
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("Disable still retires the watcher when the widget is already gone")
                .eq(before - 1)
            widget().Enable()
            expect(H.SuuUI.DataBar:Has(WIDGET_ID))
                .as("Enable re-reads the stored value, which is still off").eq(false)
            set("time_enabled", true)
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(true)
        end)

        it("goes away with the plugin", function()
            local before = H.SuuUI.Settings:GetWatcherCount()
            plugin():Disable()
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).as("the plugin takes its widget").eq(false)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("and its watcher").lt(before)
            expect(H.SuuUI.DataBar:GetOccupiedHeight())
                .as("nothing occupies the top of the screen any more").eq(0)

            plugin():Enable()
            expect(H.SuuUI.DataBar:Has(WIDGET_ID)).eq(true)
            expect(H.SuuUI.Settings:GetWatcherCount()).eq(before)
            expect(field():GetText()).eq("14:32")
        end)
    end)
end)
