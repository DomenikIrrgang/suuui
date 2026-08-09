local H = require("harness")

local PLUGIN_ID = "cast_bars"

local function setting(key)
    return H.SuuUI.Settings:Get(PLUGIN_ID, key)
end

local function ufSetting(key)
    return H.SuuUI.Settings:Get("unit_frames", key)
end

local function plugin()
    return H.SuuUI.Plugins:Get(PLUGIN_ID)
end

local function playerCtl()
    return plugin()._controllers and plugin()._controllers.player
end

local function playerFrame()
    return H.SuuUI.Plugins:Get("unit_frames")._playerFrame
end

-- The subtabs entry from the live schema.
local function subtabsEntry()
    for _, entry in ipairs(H.SuuUI.Settings:GetSchema(PLUGIN_ID)) do
        if entry.type == "subtabs" then return entry end
    end
end

local function playerTab()
    local st = subtabsEntry()
    if not st then return nil end
    for _, tab in ipairs(st.tabs) do
        if tab.id == "player" then return tab end
    end
end

-- Collects all keys declared anywhere in the schema tree, counting duplicates.
local function allKeys()
    local seen = {}
    local function walk(entries)
        for _, e in ipairs(entries) do
            if e.key and e.key ~= "" then
                seen[e.key] = (seen[e.key] or 0) + 1
            end
            if e.tabs then
                for _, t in ipairs(e.tabs) do walk(t.schema) end
            end
        end
    end
    walk(H.SuuUI.Settings:GetSchema(PLUGIN_ID))
    return seen
end

-- Builds the real cast_bars page, capturing controls by type.
local function buildPage(host)
    local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
    H.SuuUI._PageBuilder:Build(PLUGIN_ID, scroll)
    return scroll
end

-- Builds the page and captures every Dropdown handle.
local function buildCapturingDropdowns(host)
    local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
    local built = {}
    local realDD = H.SuuUI.Components.Dropdown
    H.SuuUI.Components.Dropdown = function(...)
        local d = realDD(...); built[#built + 1] = d; return d
    end
    H.SuuUI._PageBuilder:Build(PLUGIN_ID, scroll)
    H.SuuUI.Components.Dropdown = realDD
    return built, scroll
end

-- Builds the page and captures every Slider handle.
local function buildCapturingSliders(host)
    local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
    local built = {}
    local realS = H.SuuUI.Components.Slider
    H.SuuUI.Components.Slider = function(...)
        local s = realS(...); built[#built + 1] = s; return s
    end
    H.SuuUI._PageBuilder:Build(PLUGIN_ID, scroll)
    H.SuuUI.Components.Slider = realS
    return built, scroll
end

describe("Plugins.CastBars – settings", function()
    local host, state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth, state.unitHealthMax = 80, 100
        state.unitPower, state.unitPowerMax = 60, 100
        state.unitPowerType = 0
        state.unitLevel = 42
        state.maxPlayerLevel = 60
        state.reloadUICalled = 0
        H.setup()
        host = H.parent(1024, 768)
    end)

    describe("registration", function()
        it("plugin exists and is enabled", function()
            local p = plugin()
            expect(p).notNil()
            expect(p:IsEnabled()).eq(true)
        end)

        it("has id 'cast_bars'", function()
            local p = plugin()
            expect(p._id or p.id).eq("cast_bars")
        end)

        it("has name 'Cast Bars'", function()
            local p = plugin()
            expect(p._name or p.name).eq("Cast Bars")
        end)

        it("enabled by default", function()
            expect(setting("enabled")).eq(true)
        end)
    end)

    describe("schema", function()
        it("registers all expected keys with their defaults", function()
            expect(setting("enabled")).eq(true)
            expect(setting("player_position")).notNil()
            expect(setting("player_enabled")).eq(true)
            expect(setting("player_show_icon")).eq(true)
            expect(setting("player_show_name")).eq(true)
            expect(setting("player_show_time")).eq(true)
            expect(setting("player_show_shield")).as("the cue is on by default").eq(true)
            expect(setting("player_anchor")).eq("attached")
            expect(setting("player_attach_position")).eq("below")
            expect(setting("player_width")).eq(304)
            expect(setting("player_icon_position")).eq("left")
            expect(setting("player_time_format")).eq("remaining")
            expect(setting("player_height")).eq(22)
            expect(setting("player_cast_color")).deepEq({0.85, 0.63, 0.17, 1})
            expect(setting("player_channel_color")).deepEq({0.25, 0.55, 0.85, 1})
        end)

        it("declares every key exactly once", function()
            local seen = allKeys()
            local required = {
                "enabled", "player_position", "player_enabled",
                "player_show_icon", "player_show_name", "player_show_time",
                "player_show_shield",
                "player_anchor", "player_attach_position", "player_width",
                "player_icon_position", "player_time_format", "player_height",
                "player_cast_color", "player_channel_color",
            }
            for _, key in ipairs(required) do
                expect(seen[key]).as(key .. " declared exactly once").eq(1)
            end
        end)

        it("player_anchor dropdown has attached and detached options", function()
            local tab = playerTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "player_anchor" then
                    local vals = {}
                    for _, opt in ipairs(e.options) do vals[opt.value] = true end
                    expect(vals["attached"]).truthy()
                    expect(vals["detached"]).truthy()
                end
            end
        end)

        it("player_attach_position dropdown has above and below options", function()
            local tab = playerTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "player_attach_position" then
                    local vals = {}
                    for _, opt in ipairs(e.options) do vals[opt.value] = true end
                    expect(vals["above"]).truthy()
                    expect(vals["below"]).truthy()
                end
            end
        end)

        it("player_icon_position dropdown has left and right options", function()
            local tab = playerTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "player_icon_position" then
                    local vals = {}
                    for _, opt in ipairs(e.options) do vals[opt.value] = true end
                    expect(vals["left"]).truthy()
                    expect(vals["right"]).truthy()
                end
            end
        end)

        it("player_time_format dropdown has all four options", function()
            local tab = playerTab()
            for _, e in ipairs(tab.schema) do
                if e.key == "player_time_format" then
                    local vals = {}
                    for _, opt in ipairs(e.options) do vals[opt.value] = true end
                    expect(vals["remaining"]).truthy()
                    expect(vals["elapsed"]).truthy()
                    expect(vals["both"]).truthy()
                    expect(vals["percent"]).truthy()
                end
            end
        end)
    end)

    describe("ReloadGuard", function()
        it("registers a guard for enabled", function()
            expect(H.SuuUI.ReloadGuard:IsGuarded(PLUGIN_ID, "enabled")).eq(true)
        end)

        it("registers a guard for player_enabled", function()
            expect(H.SuuUI.ReloadGuard:IsGuarded(PLUGIN_ID, "player_enabled")).eq(true)
        end)

        it("reverts enabled change (guard intercepts)", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "enabled", false)
            expect(setting("enabled")).eq(true)
        end)

        it("reverts player_enabled change (guard intercepts)", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_enabled", false)
            expect(setting("player_enabled")).eq(true)
        end)
    end)

    describe("Blizzard cast bar suppression", function()
        -- The name changed with Edit Mode, so the plugin has to cover both. Looking for
        -- the older name alone is what shipped Blizzard's bar still drawing under ours,
        -- and it failed silently: the nil check just skipped.
        local NAMES = { "PlayerCastingBarFrame", "CastingBarFrame" }

        for _, name in ipairs(NAMES) do
            it(name .. " is hidden after boot", function()
                local cbf = H.env[name]
                expect(cbf).as(name .. " exists in the simulated client").notNil()
                expect(cbf:IsShown()).eq(false)
            end)

            it(name .. " has its events unregistered", function()
                local cbf = H.env[name]
                local count = 0
                if cbf._events then
                    for _ in pairs(cbf._events) do count = count + 1 end
                end
                expect(count).as("no registered events").eq(0)
            end)

            it(name .. " stays hidden when something shows it again", function()
                local cbf = H.env[name]
                -- An Edit Mode client re-shows a system frame when a layout is applied,
                -- which no amount of unregistering prevents.
                cbf:Show()
                expect(cbf:IsShown()).as("re-show is defeated").eq(false)
            end)
        end

        it("hides the legacy bar on a client that only has that name", function()
            H.setup({ castBarGlobals = { "CastingBarFrame" } })
            expect(H.env.PlayerCastingBarFrame).as("modern name absent").isNil()
            expect(H.env.CastingBarFrame:IsShown()).eq(false)
        end)

        it("hides the modern bar on a client that only has that name", function()
            H.setup({ castBarGlobals = { "PlayerCastingBarFrame" } })
            expect(H.env.CastingBarFrame).as("legacy name absent").isNil()
            expect(H.env.PlayerCastingBarFrame:IsShown()).eq(false)
        end)

        it("logs when no cast bar global exists at all", function()
            H.setup({ castBarGlobals = {}, debug = true })
            local found = false
            for _, msg in ipairs(state.debugLog) do
                if tostring(msg):find("no Blizzard player cast bar", 1, true) then
                    found = true
                end
            end
            expect(found).as("the miss is reported, not swallowed").eq(true)
        end)
    end)

    describe("attached mode (default)", function()
        it("controller exists and reports 'attached' mode", function()
            local ctl = playerCtl()
            expect(ctl).notNil()
            expect(ctl:GetMode()).eq("attached")
        end)

        it("bar exists", function()
            local ctl = playerCtl()
            expect(ctl:GetBar()).notNil()
        end)

        it("bar frame is a descendant of the player frame wrapper", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            local pfFrame = playerFrame():GetFrame()
            -- Walk up the parent chain
            local cur = barFrame:GetParent()
            local found = false
            while cur do
                if cur == pfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("bar is a descendant of player frame").truthy()
        end)

        it("bar sits below the resource bar by default", function()
            local ctl = playerCtl()
            local barBox = H.box(ctl:GetBar())
            local resourceBox = H.box(playerFrame()._resourceBar)
            expect(barBox).notNil()
            expect(resourceBox).notNil()
            expect(barBox.top).as("cast bar below resource bar").gt(resourceBox.bottom - 1)
        end)

        it("bar width equals the player frame width", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            local pfWidth = ufSetting("player_width")
            expect(barFrame:GetWidth()).as("attached bar matches player frame width").near(pfWidth, 1)
        end)

        it("changing unit_frames.player_width changes the bar width", function()
            H.SuuUI.Settings:Set("unit_frames", "player_width", 350)
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            expect(barFrame:GetWidth()).near(350, 1)
        end)
    end)

    describe("player frame grows for attached bar", function()
        it("frame height includes the bar band plus gap", function()
            local pf = playerFrame()
            local pfHeight = pf:GetFrame():GetHeight()
            local barHeight = setting("player_height")
            local gap = H.token("spaceXs")
            -- Without the bar, the frame would be shorter
            -- Detach to measure without it
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            local withoutBar = pf:GetFrame():GetHeight()
            expect(pfHeight).as("frame grows by bar height + gap").near(withoutBar + barHeight + gap, 1)
        end)

        it("frame shrinks when bar detaches", function()
            local pf = playerFrame()
            local attachedHeight = pf:GetFrame():GetHeight()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            local detachedHeight = pf:GetFrame():GetHeight()
            expect(detachedHeight).lt(attachedHeight)
        end)
    end)

    describe("player_attach_position", function()
        it("'below' puts bar below the resource bar", function()
            expect(setting("player_attach_position")).eq("below")
            local ctl = playerCtl()
            local barBox = H.box(ctl:GetBar())
            local resourceBox = H.box(playerFrame()._resourceBar)
            expect(barBox.top).gte(resourceBox.bottom - 1)
        end)

        it("'above' puts bar above the name row", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "above")
            local ctl = playerCtl()
            local barBox = H.box(ctl:GetBar())
            local nameBox = H.box(playerFrame()._nameText)
            -- The cast bar's bottom should be at or above the name row's top
            expect(barBox.bottom).as("cast bar above name row").lte(nameBox.top + 1)
        end)
    end)

    describe("REGRESSION: attaching does not move the unit frame itself", function()
        -- The frame grows around the bar, and growth lands on whichever edge its anchor
        -- does not pin — so with the default BOTTOMLEFT position a bar in the 'below' slot
        -- pushed the health and resource bars 26 units up the screen, and detaching pushed
        -- them back down. Only the cast bar is supposed to appear or move.
        --
        -- Measured on the bars rather than the wrapper: the wrapper's box legitimately
        -- changes, since that is where the band goes.
        local function corePositions()
            local pf = playerFrame()
            return {
                health   = H.box(pf._healthBar),
                resource = H.box(pf._resourceBar),
                name     = H.box(pf._nameText),
            }
        end

        local function expectCoreUnmoved(before, note)
            local after = corePositions()
            for part, box in pairs(before) do
                expect(after[part]).as(part .. " still present " .. note).notNil()
                expect(after[part].top).as(part .. ".top unmoved " .. note)
                    .near(box.top, 0.5)
                expect(after[part].left).as(part .. ".left unmoved " .. note)
                    .near(box.left, 0.5)
            end
        end

        it("keeps the bars still across attach, position swap, and detach", function()
            -- Start detached, so the baseline is the frame with no band at all.
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            H.runAnimations()
            local before = corePositions()
            expect(before.health).notNil()

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "below")
            H.runAnimations()
            expectCoreUnmoved(before, "after attaching below")

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "above")
            H.runAnimations()
            expectCoreUnmoved(before, "after moving the bar above")

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "below")
            H.runAnimations()
            expectCoreUnmoved(before, "after moving the bar back below")

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            H.runAnimations()
            expectCoreUnmoved(before, "after detaching")
        end)

        it("puts the band outside the bars, not over them", function()
            -- The other half of the invariant: the content staying still must be because
            -- the frame grew outward, not because the band landed on top of the bars.
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "below")
            H.runAnimations()
            local pf = playerFrame()
            H.expectNoOverlap(playerCtl():GetBar(), pf._resourceBar)
            expect(H.box(playerCtl():GetBar()).top)
                .as("band sits below the resource bar")
                .gte(H.box(pf._resourceBar).bottom - 0.5)

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "above")
            H.runAnimations()
            H.expectNoOverlap(playerCtl():GetBar(), pf._nameText)
            expect(H.box(playerCtl():GetBar()).bottom)
                .as("band sits above the name row")
                .lte(H.box(pf._nameText).top + 0.5)
        end)

        it("reports a core inset of zero when nothing is attached", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            H.runAnimations()
            local above, below = playerFrame():GetCoreInset()
            expect(above).as("no band above").eq(0)
            expect(below).as("no band below").eq(0)
        end)

        it("reports the attached band's height plus the row gap as the inset", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "below")
            H.runAnimations()
            local band = setting("player_height") + H.token("spaceXs")
            local above, below = playerFrame():GetCoreInset()
            expect(above).as("nothing above").eq(0)
            expect(below).as("band plus gap below").near(band, 1)

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_attach_position", "above")
            H.runAnimations()
            above, below = playerFrame():GetCoreInset()
            expect(above).as("band plus gap above").near(band, 1)
            expect(below).as("nothing below").eq(0)
        end)
    end)

    describe("detached mode", function()
        before_each(function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
        end)

        it("controller reports 'detached' mode", function()
            expect(playerCtl():GetMode()).eq("detached")
        end)

        it("bar is NOT a descendant of the player frame", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            local pfFrame = playerFrame():GetFrame()
            local cur = barFrame:GetParent()
            local found = false
            while cur do
                if cur == pfFrame then found = true; break end
                cur = cur.GetParent and cur:GetParent() or nil
            end
            expect(found).as("detached bar is not inside player frame").falsy()
        end)

        it("MoveableFrame is applied", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            expect(barFrame._suuui_moveable).as("frame has moveable data").notNil()
        end)

        it("frame is registered with ToggleUI", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            local all = H.SuuUI.ToggleUI:GetAll()
            local found = false
            for _, f in ipairs(all) do
                if f == barFrame then found = true; break end
            end
            expect(found).as("frame is in ToggleUI's registry").truthy()
        end)

        it("width follows cast_bars.player_width", function()
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            expect(barFrame:GetWidth()).near(setting("player_width"), 1)
        end)

        it("unit_frames.player_width no longer affects bar width", function()
            H.SuuUI.Settings:Set("unit_frames", "player_width", 350)
            local ctl = playerCtl()
            local barFrame = ctl:GetBar():GetFrame()
            -- Should still match cast_bars.player_width, not unit_frames
            expect(barFrame:GetWidth()).near(setting("player_width"), 1)
            expect(barFrame:GetWidth()).as("not following UF width").notNil()
        end)
    end)

    describe("re-attaching after detach", function()
        it("restores attached mode and frame grows back", function()
            local pf = playerFrame()
            local attachedH = pf:GetFrame():GetHeight()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            local detachedH = pf:GetFrame():GetHeight()
            expect(detachedH).lt(attachedH)
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            expect(playerCtl():GetMode()).eq("attached")
            expect(pf:GetFrame():GetHeight()).near(attachedH, 1)
        end)

        it("watcher and request counts are stable after round trips", function()
            local watchBefore = H.SuuUI.Settings:GetWatcherCount()
            local reqBefore = H.SuuUI.AttachPoints:GetRequestCount()
            for _ = 1, 3 do
                H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
                H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            end
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("no watcher leak after mode switches").eq(watchBefore)
            expect(H.SuuUI.AttachPoints:GetRequestCount())
                .as("no request leak after mode switches").eq(reqBefore)
        end)
    end)

    describe("colour mode (enabledIf { key, equals = false })", function()
        -- Builds the page and captures every ColorSwatch handle, which is what the Color
        -- control binds its dependency to.
        local function buildCapturingSwatches()
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
            local built = {}
            local real = H.SuuUI.Components.ColorSwatch
            H.SuuUI.Components.ColorSwatch = function(...)
                local s = real(...); built[#built + 1] = s; return s
            end
            H.SuuUI._PageBuilder:Build(PLUGIN_ID, scroll)
            H.SuuUI.Components.ColorSwatch = real
            return built, scroll
        end

        it("declares the school colour toggle, on by default", function()
            local tab = playerTab()
            local entry
            for _, e in ipairs(tab.schema) do
                if e.key == "player_school_color" then entry = e end
            end
            expect(entry).as("player_school_color declared").notNil()
            expect(entry.type).eq("toggle")
            expect(entry.default).eq(true)
            expect(setting("player_school_color")).eq(true)
        end)

        it("both colour pickers depend on the toggle being off", function()
            local tab = playerTab()
            local found = 0
            for _, e in ipairs(tab.schema) do
                if e.key == "player_cast_color" or e.key == "player_channel_color" then
                    found = found + 1
                    expect(type(e.enabledIf)).as(e.key .. " has a dependency").eq("table")
                    expect(e.enabledIf.key).eq("player_school_color")
                    expect(e.enabledIf.equals).as(e.key .. " equals false").eq(false)
                end
            end
            expect(found).as("both pickers carry it").eq(2)
        end)

        it("pickers are greyed while school colouring is on", function()
            local swatches = buildCapturingSwatches()
            expect(#swatches >= 2).as("two swatches built").eq(true)
            for _, s in ipairs(swatches) do
                expect(s._enabled).as("greyed under school colouring").eq(false)
            end
        end)

        it("turning school colouring off enables the pickers", function()
            local swatches = buildCapturingSwatches()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_school_color", false)
            for _, s in ipairs(swatches) do
                expect(s._enabled).as("live again in fixed mode").eq(true)
            end
        end)

        it("the greyed pickers keep their stored colours", function()
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_school_color", false)
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_cast_color", { 1, 0, 0, 1 })
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_school_color", true)
            local stored = setting("player_cast_color")
            expect(stored[1]).as("value survives greying").eq(1)
            expect(stored[2]).eq(0)
        end)
    end)

    describe("dependency greying (enabledIf { key, equals })", function()
        it("width slider is disabled while anchor is 'attached'", function()
            local sliders = buildCapturingSliders(host)
            -- Find the width slider: it should be the one whose value matches player_width
            local widthSlider
            for _, s in ipairs(sliders) do
                if s._value == setting("player_width") or s._value == 304 then
                    widthSlider = s
                    break
                end
            end
            expect(widthSlider).as("width slider found").notNil()
            expect(widthSlider._enabled).as("disabled while attached").eq(false)
        end)

        it("position dropdown is enabled while anchor is 'attached'", function()
            local dropdowns = buildCapturingDropdowns(host)
            -- Position dropdown has value "below" by default
            local posDD
            for _, d in ipairs(dropdowns) do
                if d._value == "below" then
                    posDD = d
                    break
                end
            end
            expect(posDD).as("position dropdown found").notNil()
            expect(posDD._enabled).as("enabled while attached").eq(true)
        end)

        it("setting anchor to 'detached' enables width and disables position", function()
            local sliders, scroll = buildCapturingSliders(host)
            local dropdowns = buildCapturingDropdowns(host)
            -- Find controls again after a fresh build
            local widthSlider
            for _, s in ipairs(sliders) do
                if s._value == setting("player_width") or s._value == 304 then
                    widthSlider = s
                    break
                end
            end
            local posDD
            for _, d in ipairs(dropdowns) do
                if d._value == "below" then
                    posDD = d
                    break
                end
            end

            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")

            if widthSlider then
                expect(widthSlider._enabled).as("width enabled when detached").eq(true)
            end
            if posDD then
                expect(posDD._enabled).as("position disabled when detached").eq(false)
            end
        end)

        it("disabled control shows opacityDisabled alpha", function()
            local sliders = buildCapturingSliders(host)
            local widthSlider
            for _, s in ipairs(sliders) do
                if s._value == setting("player_width") or s._value == 304 then
                    widthSlider = s
                    break
                end
            end
            expect(widthSlider).notNil()
            -- While disabled, the frame alpha should match opacityDisabled
            local expected = H.token("opacityDisabled")
            expect(widthSlider:GetFrame():GetAlpha()).near(expected, 0.01)
        end)

        it("stored value is NOT cleared while control is greyed", function()
            -- Set a custom width while detached
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "detached")
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_width", 250)
            expect(setting("player_width")).eq(250)
            -- Re-attach: width slider is greyed but value survives
            H.SuuUI.Settings:Set(PLUGIN_ID, "player_anchor", "attached")
            expect(setting("player_width")).as("value survives greying").eq(250)
        end)

        it("real disabled state: IsEnabled() is false and click is refused", function()
            local sliders = buildCapturingSliders(host)
            local widthSlider
            for _, s in ipairs(sliders) do
                if s._value == setting("player_width") or s._value == 304 then
                    widthSlider = s
                    break
                end
            end
            expect(widthSlider).notNil()
            expect(widthSlider:IsEnabled()).eq(false)
            expect(H.click(widthSlider)).as("click refused on disabled slider").falsy()
        end)
    end)

    describe("attach point lifecycle", function()
        it("disabling unit_frames revokes the point and tears bar down", function()
            expect(playerCtl():GetMode()).eq("attached")
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            -- The attach point is gone
            expect(H.SuuUI.AttachPoints:Has("unitframe.player")).eq(false)
            -- Controller mode is nil (orphan protection)
            expect(playerCtl():GetMode()).as("mode is nil when point revoked").isNil()
            expect(playerCtl():GetBar()).as("bar is torn down").isNil()
        end)

        it("re-enabling unit_frames restores the attached bar", function()
            H.SuuUI.Plugins:Get("unit_frames"):Disable()
            expect(playerCtl():GetMode()).isNil()
            H.SuuUI.Plugins:Get("unit_frames"):Enable()
            expect(H.SuuUI.AttachPoints:Has("unitframe.player")).eq(true)
            expect(playerCtl():GetMode()).eq("attached")
            expect(playerCtl():GetBar()).notNil()
        end)
    end)

    describe("player_enabled = false at boot", function()
        it("no controller is created when player_enabled starts false", function()
            -- Use boot = false, seed the setting, then boot
            H.setup({ boot = false })
            -- Seed the profile with player_enabled = false before boot
            H.SuuUI.Settings:Register(PLUGIN_ID, {
                { key = "player_enabled", label = "Enable Cast Bar", type = "toggle", default = false },
            })
            -- Now boot
            H.fireEvent("ADDON_LOADED", "SuuUI")
            H.fireEvent("PLAYER_LOGIN")
            -- The plugin should have no player controller
            local p = H.SuuUI.Plugins:Get(PLUGIN_ID)
            local controllers = p and p._controllers
            local ctl = controllers and controllers.player
            expect(ctl).as("no controller when player_enabled is false").isNil()
        end)
    end)
end)
