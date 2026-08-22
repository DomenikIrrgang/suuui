-- The data bar's renderer: three sections, dividers, one shared ticker, one subscription.
--
-- Geometry first, because the bar is placement: which end of the screen a section sits at,
-- whether the centre one is centred rather than merely somewhere in the middle, and whether a
-- value that changes width takes its section with it.
--
-- The bar is reached through the PLUGIN HANDLE, the way the unit-frame specs reach their
-- frames, rather than built with Bar:Create. The bar the player gets is the one data_bar
-- creates at login -- already subscribed to the registry, already publishing its height,
-- already tracking the root container -- and most of what is asserted here is that wiring. A
-- second bar built in a test would also share the module-level ticker list with the live one,
-- so "the OnUpdate is unregistered when nothing wants one" could not be stated at all.
--
-- The built-in clock is unregistered in boot(). It occupies the centre section with
-- update = 0.5, so leaving it in place would add a field to every section count and an entry
-- to every ticker count this file makes, and the placement specs would be measuring the clock
-- instead of the widgets they stage.
local PLUGIN_ID = "data_bar"
local CLOCK_ID  = "databar.time"

local function DB()  return H.SuuUI.DataBar end
local function bar() return H.SuuUI.Plugins:Get(PLUGIN_ID)._bar end

local function section(name)  return bar():GetSection(name) end
local function barFrame()     return bar():GetFrame() end
local function rootBox()      return H.box(H.SuuUI.UIRoot:GetRootContainer()) end
local function barHeight()    return H.controlHeight("sizeRow") end
local function sectionGap()   return H.token("spaceXxs") end

-- A fresh client with every contributed widget out of the way. Debug is a parameter because
-- SuuUI.Debug is a no-op until it is switched on, and one spec here is about what the bar logs.
--
-- Clears EVERY registered widget rather than naming the clock. Other plugins contribute to this
-- bar — Performance registers a framerate and a latency field — so naming them one at a time
-- would break this file each time one is added, which is exactly what happened. This spec is
-- about the RENDERER, so it stages the widgets it wants and starts from nothing. List() returns
-- a copy, which is what makes it safe to iterate while unregistering.
local function boot(opts)
    H.setup(opts)
    for _, def in ipairs(DB():List()) do DB():UnregisterWidget(def.id) end
end

-- Registers a readout. `text` may be a function, so a spec can move the value underneath it
-- and then prove that a refresh reached the screen.
local function stage(id, sec, text, extra)
    local def = {
        id      = id,
        section = sec,
        GetText = type(text) == "function" and text or function() return text end,
    }
    for k, v in pairs(extra or {}) do def[k] = v end
    DB():RegisterWidget(def)
    return def
end

local function recordOf(id)
    for _, rec in ipairs(bar()._records) do
        if rec.def.id == id then return rec end
    end
end

local function fieldOf(id)
    local rec = recordOf(id)
    return rec and rec.field
end

-- What a field is actually SHOWING, read off the font string. The handle's stored value would
-- answer even if the string never reached the client, and a refresh that does not reach the
-- screen is not a refresh. None of these widgets declares a prefix, so the composed string is
-- the value.
local function shown(id)
    local f = fieldOf(id)
    return f and f._label:GetText()
end

-- The bar's dividers ordered by where they actually are, so a spec can name "the one on the
-- centre section's leading edge" by position rather than by insertion index.
local function dividers()
    local out = {}
    for _, d in ipairs(bar()._dividers) do out[#out + 1] = d end
    table.sort(out, function(a, b) return H.box(a).left < H.box(b).left end)
    return out
end

-- The shared ticker is a bare, unnamed, unparented frame the renderer creates lazily, so
-- nothing on the Bar handle reaches it -- and the rule is that its script is ABSENT when idle,
-- not merely that its list is empty. Counting the frames the client would call OnUpdate on is
-- the same evidence the client acts on, and a delta identifies the one that just appeared.
local function onUpdateFrames()
    local st = require("harness.wow.state")
    local out = {}
    for i = 1, #st.frames do
        local f = st.frames[i]
        if f.GetScript and f:GetScript("OnUpdate") then out[#out + 1] = f end
    end
    return out
end

local function appeared(before)
    local seen = {}
    for _, f in ipairs(before) do seen[f] = true end
    local out = {}
    for _, f in ipairs(onUpdateFrames()) do
        if not seen[f] then out[#out + 1] = f end
    end
    return out
end

-- The width a field hugs to: its own text box plus the padding DataField lays the label out
-- with, snapped onto the grid. The face and size come off the live font string, so a theme
-- swap measures with the face actually in force rather than with the default one.
local function fieldWidth(id, text)
    local path, size = H.fontOf(fieldOf(id)._label)
    return H.SuuUI.Pixel.Ceil(H.textBox(text, size, path) + H.token("spaceMd") * 2)
end

local function layerHolds(frame)
    for _, el in ipairs(H.SuuUI.UIRoot:GetLayerElements("normal")) do
        if el == frame then return true end
    end
    return false
end

describe("Plugins.DataBar – the bar", function()
    before_each(function() boot() end)

    describe("the strip", function()
        it("exists as soon as the plugin is enabled", function()
            expect(H.SuuUI.Plugins:Get(PLUGIN_ID):IsEnabled()).eq(true)
            expect(bar()).notNil()
            expect(layerHolds(barFrame()))
                .as("stated to the layer system rather than given a raw strata").truthy()
        end)

        it("spans the full width of the root container", function()
            local r = rootBox()
            H.expectSize(barFrame(), H.SuuUI.UIRoot:GetRootContainer():GetWidth(), nil)
            H.expectBox(barFrame(), { left = r.left, right = r.right })
        end)

        it("sits on the top edge of the root", function()
            -- .top measures DOWNWARD from the screen top, so "on the top edge" is the same
            -- .top as the root's, and anything lower would report a larger one.
            expect(H.box(barFrame()).top).eq(rootBox().top)
        end)

        it("is one sizeRow tall", function()
            H.expectSize(barFrame(), nil, barHeight())
        end)

        it("publishes exactly its own height as the occupied height", function()
            expect(DB():GetOccupiedHeight()).eq(barHeight())
            expect(DB():GetOccupiedHeight()).eq(H.box(barFrame()).height)
        end)

        it("re-places itself when the root container resizes", function()
            -- The screen is what moves in game, and the root is SetAllPoints to it, so its
            -- own SetSize is a no-op: the size is anchor-derived. Resizing UIParent is
            -- therefore the only driver that actually reaches the root container's
            -- SIZE_CHANGED, which is what the bar subscribes to. Height left alone, since
            -- H.box converts through the screen height.
            local was = H.box(barFrame()).width
            H.UIParent:SetSize(was - 200, H.UIParent:GetHeight())

            local now = H.SuuUI.UIRoot:GetRootContainer():GetWidth()
            expect(now).as("the root really did shrink").lt(was)
            H.expectSize(barFrame(), now, barHeight())
            H.expectBox(barFrame(), { left = rootBox().left, right = rootBox().right })
        end)
    end)

    describe("section placement", function()
        before_each(function()
            stage("db.left", "left", "LEFT")
            stage("db.centre", "center", "MID")
            stage("db.right", "right", "RIGHT")
        end)

        it("starts the left section on the bar's left edge", function()
            expect(H.box(section("left")).left).eq(H.box(barFrame()).left)
            expect(H.box(fieldOf("db.left")).left)
                .as("and nothing is placed before its first field").eq(H.box(barFrame()).left)
        end)

        it("ends the right section on the bar's right edge", function()
            expect(H.box(section("right")).right).eq(H.box(barFrame()).right)
            expect(H.box(fieldOf("db.right")).right).eq(H.box(barFrame()).right)
        end)

        it("centres the centre section on the bar", function()
            local g, b = section("center"), barFrame()
            -- A full-width group would satisfy a centring check trivially, so state that it
            -- is a narrow box sitting between the other two first.
            expect(H.box(g).left).as("the centre group starts inside the bar").gt(H.box(b).left)
            expect(H.box(g).right).as("and ends inside it").lt(H.box(b).right)
            H.expectCenteredH(g, b)
        end)

        it("keeps the three sections apart and inside the bar", function()
            for _, name in ipairs({ "left", "center", "right" }) do
                H.expectInside(section(name), barFrame())
            end
            H.expectNoOverlap(section("left"), section("center"))
            H.expectNoOverlap(section("center"), section("right"))
        end)

        it("stretches every section to the full bar height", function()
            for _, name in ipairs({ "left", "center", "right" }) do
                H.expectSize(section(name), nil, barHeight())
            end
            H.expectSize(fieldOf("db.centre"), nil, barHeight())
        end)

        it("hugs each section to its own content", function()
            -- The centre and right sections each carry a LEADING divider here, because a
            -- populated section precedes them, so their content is divider + gap + field.
            -- Stating that is the point: a section hugging only its field would mean the
            -- edge was never laid out.
            local edge = H.SuuUI.Pixel.Line(H.token("borderWidth")) + sectionGap()
            H.expectSize(section("left"), fieldWidth("db.left", "LEFT"), nil)
            H.expectSize(section("center"), edge + fieldWidth("db.centre", "MID"), nil)
            H.expectSize(section("right"), edge + fieldWidth("db.right", "RIGHT"), nil)
            H.expectTextNotClipped(fieldOf("db.centre")._label)
        end)
    end)

    describe("the Subscribe contract", function()
        it("grows a field for a widget registered after the bar exists", function()
            expect(#bar()._records).as("the bar starts empty once the clock is gone").eq(0)

            -- RegisterWidget and nothing else: no Rebuild call anywhere in this test. The
            -- subscription is the only thing that can put the field on the bar.
            stage("db.late", "left", "42g")

            local field = fieldOf("db.late")
            expect(field).as("registering alone produced a field").notNil()
            expect(shown("db.late")).eq("42g")
            H.expectInside(field, section("left"))
            H.expectSize(field, nil, barHeight())
        end)

        it("puts a widget in the section it declares", function()
            stage("db.r", "right", "R")
            H.expectInside(fieldOf("db.r"), section("right"))
            expect(H.box(fieldOf("db.r")).right).eq(H.box(barFrame()).right)
        end)

        it("drops the field again when the widget is unregistered", function()
            stage("db.gone", "left", "bye")
            local field = fieldOf("db.gone")
            local wide = H.box(section("left")).width
            expect(wide).gt(0)

            DB():UnregisterWidget("db.gone")

            expect(recordOf("db.gone")).as("the record is gone").isNil()
            expect(field:IsShown()).as("and the field itself is torn down").falsy()
            H.expectSize(section("left"), 0, nil)
        end)

        it("orders fields within a section by the declared order", function()
            stage("db.second", "left", "SECOND", { order = 20 })
            stage("db.first", "left", "FIRST", { order = 10 })
            H.expectRowHorizontally(
                { fieldOf("db.first"), dividers()[1], fieldOf("db.second") }, sectionGap())
        end)
    end)

    describe("dividers", function()
        it("puts one between adjacent fields and none before the first", function()
            stage("db.a", "left", "AAA", { order = 10 })
            stage("db.b", "left", "BBB", { order = 20 })

            local divs = dividers()
            expect(#divs).as("one divider for one adjacency").eq(1)
            H.expectRowHorizontally({ fieldOf("db.a"), divs[1], fieldOf("db.b") }, sectionGap())
            expect(H.box(fieldOf("db.a")).left)
                .as("the first field of the first populated section starts the bar")
                .eq(H.box(barFrame()).left)
            H.expectSize(divs[1],
                H.SuuUI.Pixel.Line(H.token("borderWidth")), barHeight())
        end)

        it("puts none in front of a lone first section", function()
            stage("db.only", "left", "ONLY")
            expect(#bar()._dividers).as("nothing precedes the very first field").eq(0)
            expect(H.box(fieldOf("db.only")).left).eq(H.box(section("left")).left)
        end)

        it("puts none in front of a lone centre field either, when it is first", function()
            -- The centre section is the FIRST POPULATED one here, not the first section, so
            -- the leading divider is about what came before rather than about which section.
            stage("db.mid", "center", "MID")
            expect(#bar()._dividers).eq(0)
            expect(H.box(fieldOf("db.mid")).left).eq(H.box(section("center")).left)
        end)

        it("puts a leading divider on a section that follows a populated one", function()
            stage("db.l", "left", "L")
            stage("db.mid", "center", "MID")

            local divs = dividers()
            expect(#divs).as("one leading divider, on the centre section").eq(1)
            expect(H.box(divs[1]).left).eq(H.box(section("center")).left)
            H.expectRowHorizontally({ divs[1], fieldOf("db.mid") }, sectionGap())
        end)

        it("gives a lone centre field an edge either side", function()
            stage("db.l", "left", "L")
            stage("db.mid", "center", "MID")
            stage("db.r", "right", "R")

            local divs = dividers()
            expect(#divs).as("a leading divider on the centre and on the right").eq(2)
            local mid = H.box(fieldOf("db.mid"))
            expect(H.box(divs[1]).right).as("an edge to its left").lte(mid.left)
            expect(H.box(divs[2]).left).as("and an edge to its right").gte(mid.right)
        end)
    end)

    describe("the hover rail", function()
        it("advertises one on a widget that handles a click", function()
            stage("db.click", "left", "1g", { OnClick = function() end })
            local field = fieldOf("db.click")
            expect(H.hover(field)).as("the field takes mouse input").truthy()
            expect(field._railTex:IsShown()).truthy()
            H.expectInside(field._railTex, field:GetFrame())
        end)

        it("advertises one on a widget that handles a hover", function()
            stage("db.enter", "left", "1g", { OnEnter = function() end })
            local field = fieldOf("db.enter")
            H.hover(field)
            expect(field._railTex:IsShown()).truthy()
        end)

        it("does not advertise one on a pure readout", function()
            stage("db.readout", "left", "1g")
            local field = fieldOf("db.readout")
            expect(H.hover(field)).as("it is still a mouse-enabled frame").truthy()
            expect(field._railTex:IsShown())
                .as("a readout must not promise an interaction it does not have").falsy()
        end)

        it("hides the rail again on the way out", function()
            stage("db.click", "left", "1g", { OnClick = function() end })
            local field = fieldOf("db.click")
            H.hover(field)
            H.unhover(field)
            expect(field._railTex:IsShown()).falsy()
        end)
    end)

    describe("a widget whose GetText throws", function()
        it("logs it and leaves the others refreshing", function()
            -- SuuUI.Debug is a no-op unless debug is on, so this spec boots its own client.
            boot({ debug = true })
            local vals = { a = "A1", c = "C1" }
            stage("db.a", "left", function() return vals.a end,
                { order = 10, events = { "DB_REFRESH" } })
            stage("db.boom", "left", nil,
                { order = 20, events = { "DB_REFRESH" },
                  GetText = function() error("boom") end })
            stage("db.c", "left", function() return vals.c end,
                { order = 30, events = { "DB_REFRESH" } })

            expect(shown("db.a")).as("built before the thrower").eq("A1")
            expect(shown("db.c")).as("and built after it").eq("C1")
            expect(shown("db.boom")).as("the thrower shows nothing").eq("")

            -- The fan-out loop, not just the build loop: the middle record throws while the
            -- list is being walked and the third still has to arrive on screen.
            vals.a, vals.c = "A2", "C2"
            H.fireEvent("DB_REFRESH")
            expect(shown("db.a")).eq("A2")
            expect(shown("db.c"))
                .as("a thrower in the middle of the list does not stop the walk").eq("C2")

            local logged = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("db.boom", 1, true) and line:find("GetText error", 1, true) then
                    logged = true
                end
            end
            expect(logged).as("the failure went through SuuUI.Debug").truthy()
        end)
    end)

    describe("the events fan-out", function()
        it("refreshes only the widgets that declared the event", function()
            local vals = { a = "A1", b = "B1" }
            stage("db.a", "left", function() return vals.a end,
                { order = 10, events = { "DB_ONE" } })
            stage("db.b", "left", function() return vals.b end, { order = 20 })

            vals.a, vals.b = "A2", "B2"
            H.fireEvent("DB_ONE")

            expect(shown("db.a")).eq("A2")
            expect(shown("db.b"))
                .as("a widget that declared no event is left alone").eq("B1")
        end)

        it("registers only the events its widgets currently ask for", function()
            local vals = { a = "A1" }
            stage("db.a", "left", function() return vals.a end, { events = { "DB_ONE" } })
            local evt = bar()._evt
            expect(evt:IsEventRegistered("DB_ONE")).truthy()
            expect(evt:IsEventRegistered("DB_TWO"))
                .as("no widget named this one").falsy()

            vals.a = "A2"
            H.fireEvent("DB_TWO")
            expect(shown("db.a")).as("an unrelated event changes nothing").eq("A1")

            DB():UnregisterWidget("db.a")
            expect(evt:IsEventRegistered("DB_ONE"))
                .as("the registration goes when the widget does").falsy()
        end)
    end)

    describe("the shared ticker", function()
        it("refreshes after the declared interval and not before", function()
            local interval = 0.5
            local vals = { v = "T1" }
            stage("db.tick", "left", function() return vals.v end, { update = interval })

            vals.v = "T2"
            H.tick(interval * 0.6)
            expect(shown("db.tick")).as("short of the interval, nothing happens").eq("T1")
            H.tick(interval * 0.6)
            expect(shown("db.tick")).as("past it, the value arrives").eq("T2")
        end)

        it("uses one OnUpdate for two ticking widgets", function()
            local before = onUpdateFrames()
            stage("db.t1", "left", "1", { update = 0.5, order = 10 })
            expect(#appeared(before)).as("the ticker appeared").eq(1)
            stage("db.t2", "left", "2", { update = 0.5, order = 20 })
            expect(#appeared(before)).as("and a second widget adds no second frame").eq(1)
        end)

        it("unregisters its OnUpdate once no widget declares an update", function()
            local before = onUpdateFrames()
            stage("db.tick", "left", "T", { update = 0.5 })

            local new = appeared(before)
            expect(#new).as("exactly one new OnUpdate frame -- the shared ticker").eq(1)
            local ticker = new[1]

            DB():UnregisterWidget("db.tick")
            expect(ticker:GetScript("OnUpdate"))
                .as("idle means the script is gone, not merely an empty list").isNil()
        end)

        it("keeps ticking the widgets that remain", function()
            local vals = { a = "A1" }
            stage("db.a", "left", function() return vals.a end, { update = 0.5, order = 10 })
            stage("db.b", "left", "B", { update = 0.5, order = 20 })

            DB():UnregisterWidget("db.b")
            vals.a = "A2"
            H.tick(0.6)
            expect(shown("db.a")).eq("A2")
        end)
    end)

    describe("a value that changes width", function()
        it("re-sizes its section and moves the centre section with it", function()
            local vals = { v = "12g" }
            stage("db.money", "center", function() return vals.v end,
                { events = { "DB_MONEY" } })

            local group = section("center")
            local path, size = H.fontOf(fieldOf("db.money")._label)
            expect(size).as("the field is at the md font step").eq(H.token("fontSizeMd"))

            local short = fieldWidth("db.money", vals.v)
            H.expectSize(group, short, nil)
            H.expectCenteredH(group, barFrame())
            local shortLeft = H.box(group).left

            vals.v = "1,234,567g"
            H.fireEvent("DB_MONEY")

            local long = fieldWidth("db.money", vals.v)
            expect(long).as("the new value really is wider").gt(short)
            H.expectSize(fieldOf("db.money"), long, nil)
            H.expectSize(group, long, nil)
            H.expectCenteredH(group, barFrame())
            expect(H.box(group).left)
                .as("a centred box of a new width starts further left").lt(shortLeft)
            H.expectTextNotClipped(fieldOf("db.money")._label)
        end)

        it("keeps the sections apart while one of them grows", function()
            local vals = { v = "S" }
            stage("db.l", "left", "L")
            stage("db.mid", "center", function() return vals.v end,
                { events = { "DB_MONEY" } })
            stage("db.r", "right", "R")

            vals.v = "a much longer centre value"
            H.fireEvent("DB_MONEY")

            H.expectNoOverlap(section("left"), section("center"))
            H.expectNoOverlap(section("center"), section("right"))
            H.expectInside(section("center"), barFrame())
        end)
    end)

    describe("the Build escape hatch", function()
        it("adds the widget's own handle instead of a field", function()
            local built
            DB():RegisterWidget({
                id = "db.custom", section = "left",
                Build = function(parent)
                    built = H.C.Text({ text = "custom", size = "md" }, parent)
                    return built
                end,
            })

            expect(built).as("Build was called with the section's frame").notNil()
            local rec = recordOf("db.custom")
            expect(rec.field).as("the handle is what the bar holds").eq(built)
            H.expectInside(built, section("left"))
            H.expectSize(section("left"), built:GetWidth(), nil)
        end)

        it("calls its Refresh hook when its event fires", function()
            local updates = 0
            DB():RegisterWidget({
                id = "db.custom", section = "left", events = { "DB_CUSTOM" },
                Build = function(parent)
                    return H.C.Text({ text = "custom", size = "md" }, parent)
                end,
                -- Refresh, not Update: the interval is `update` and a hook differing from it
                -- by case alone was a footgun worth removing before anything depended on it.
                Refresh = function(handle)
                    updates = updates + 1
                    handle:SetText("updated " .. updates)
                end,
            })

            H.fireEvent("DB_CUSTOM")
            expect(updates).as("the event reached the custom widget").eq(1)
            expect(recordOf("db.custom").field:GetFrame():GetText()).eq("updated 1")
        end)

        it("logs and skips a Build that fails", function()
            boot({ debug = true })
            DB():RegisterWidget({
                id = "db.bad", section = "left",
                Build = function() error("no frame for you") end,
            })
            expect(recordOf("db.bad")).as("no record for a failed build").isNil()

            local logged = false
            for _, line in ipairs(H.debugLog()) do
                if line:find("db.bad", 1, true) and line:find("Build failed", 1, true) then
                    logged = true
                end
            end
            expect(logged).truthy()
        end)
    end)

    describe("theme reaction", function()
        it("re-derives its height and re-publishes it", function()
            stage("db.a", "left", "A")
            local was = barHeight()
            expect(DB():GetOccupiedHeight()).eq(was)

            local grown = H.token("fontSizeMd") * 3
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetActive("Big")
            H.T:SetUserToken("Big", "fontSizeMd", grown)

            local now = barHeight()
            expect(now).as("the token edit really moved the row height").gt(was)
            H.expectSize(barFrame(), nil, now)
            expect(DB():GetOccupiedHeight())
                .as("the published height follows the bar's own").eq(now)
            H.expectSize(fieldOf("db.a"), nil, now)
        end)

        it("keeps the sections placed after a token edit", function()
            stage("db.l", "left", "L")
            stage("db.mid", "center", "MID")
            stage("db.r", "right", "R")

            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetActive("Big")
            H.T:SetUserToken("Big", "fontSizeMd", H.token("fontSizeMd") * 2)

            expect(H.box(section("left")).left).eq(H.box(barFrame()).left)
            expect(H.box(section("right")).right).eq(H.box(barFrame()).right)
            H.expectCenteredH(section("center"), barFrame())
        end)
    end)

    describe("teardown", function()
        it("unsubscribes from the registry", function()
            stage("db.a", "left", "A")
            local b = bar()
            local withBar = DB():GetSubscriberCount()

            b:Destroy()

            expect(DB():GetSubscriberCount())
                .as("back to what it was before the bar subscribed").eq(withBar - 1)
            -- Not merely uncounted: a later registration must not reach the dead bar.
            DB():RegisterWidget({ id = "db.after", GetText = function() return "x" end })
            expect(#b._records).as("no field rebuilt into a torn-down bar").eq(0)
        end)

        it("drops its ticker entries", function()
            local before = onUpdateFrames()
            stage("db.tick", "left", "T", { update = 0.5 })
            local new = appeared(before)
            expect(#new).eq(1)

            bar():Destroy()
            expect(new[1]:GetScript("OnUpdate"))
                .as("the shared ticker has nothing left to drive").isNil()
        end)

        it("stops answering the events it registered", function()
            local vals = { a = "A1" }
            stage("db.a", "left", function() return vals.a end, { events = { "DB_ONE" } })
            local field = fieldOf("db.a")
            expect(bar()._evt:IsEventRegistered("DB_ONE"))
                .as("the bar took the event while it was alive").truthy()

            bar():Destroy()
            vals.a = "A2"
            H.fireEvent("DB_ONE")

            expect(bar()._evt:IsEventRegistered("DB_ONE"))
                .as("the registration is dropped, not just the routing table").falsy()
            expect(field._label:GetText())
                .as("a destroyed bar refreshes nothing").eq("A1")
        end)

        it("removes its element from the UI root", function()
            local f = barFrame()
            expect(layerHolds(f)).truthy()

            bar():Destroy()

            expect(layerHolds(f)).as("off the normal layer").falsy()
            expect(f:IsShown()).as("and off the screen").falsy()
        end)

        it("sets the occupied height back to 0", function()
            expect(DB():GetOccupiedHeight()).gt(0)
            bar():Destroy()
            expect(DB():GetOccupiedHeight())
                .as("nothing is at the top of the screen any more").eq(0)
        end)

        it("comes back cleanly on a disable and re-enable", function()
            local p = H.SuuUI.Plugins:Get(PLUGIN_ID)
            local subs = DB():GetSubscriberCount()

            p:Disable()
            expect(DB():GetOccupiedHeight()).eq(0)
            expect(DB():GetSubscriberCount()).eq(subs - 1)

            p:Enable()
            expect(DB():GetSubscriberCount())
                .as("one subscription per bar, not one per enable").eq(subs)
            expect(DB():GetOccupiedHeight()).eq(barHeight())
            H.expectSize(barFrame(), H.SuuUI.UIRoot:GetRootContainer():GetWidth(), barHeight())
        end)

        it("leaves an unrelated root-container subscriber connected", function()
            -- self._root is the UI ROOT CONTAINER, one object shared by the whole addon, so
            -- DisconnectAll on it dropped every OTHER subscriber tracking the root's size.
            -- Nothing else subscribed to it at the time, which is exactly why this would have
            -- stayed invisible until something did. The bar keeps its connection id now and
            -- disconnects precisely that one.
            local rootC = H.SuuUI.UIRoot:GetRootContainer()
            local spy = H.signalSpy(rootC, H.S.SIGNALS.SIZE_CHANGED)
            local w, h = H.UIParent:GetWidth(), H.UIParent:GetHeight()

            H.UIParent:SetSize(w - 100, h)
            expect(spy.count).as("an unrelated subscriber hears the root while the bar lives")
                .gt(0)

            spy:reset()
            bar():Destroy()
            H.UIParent:SetSize(w - 200, h)
            expect(spy.count).as("and still hears it after the bar is gone").gt(0)
        end)

        xit("leaves an unrelated root-container subscriber connected", function()
            -- The invariant we believe should hold, skipped pending a decision.
            --
            -- Connect returns a connection id and DataBarWidget.lua:367 discards it, so the
            -- narrow call (UISignals:Disconnect(root, SIZE_CHANGED, id)) is available and
            -- unused. Nothing else subscribes to the root container TODAY, so this is latent
            -- rather than live -- but the file's own comments anticipate a second bar, and
            -- Components/Modal.lua and Components/Accordion.lua already use the same
            -- Connect-to-a-container pattern on their own roots, so a future consumer of the
            -- UI root's size would be broken by a data bar being switched off.
            --
            -- Two ways out: keep the id from Connect and Disconnect exactly it, or give the
            -- bar its own signal object and let UIRoot re-broadcast. The first is a
            -- three-line change; the second decides how root-size tracking should work for
            -- everyone, which is why this is pinned rather than fixed here.
        end)
    end)
end)
