local H = require("harness")

local function setting(key)
    return H.SuuUI.Settings:Get("unit_frames", key)
end

-- The subtabs entry from the live schema, so the specs state the structure rather than
-- assuming an index.
local function subtabsEntry()
    for _, entry in ipairs(H.SuuUI.Settings:GetSchema("unit_frames")) do
        if entry.type == "subtabs" then return entry end
    end
end

local function playerTab()
    local st = subtabsEntry()
    for _, tab in ipairs(st.tabs) do
        if tab.id == "player" then return tab end
    end
end

-- Section label -> keys declared under it, so a spec can assert grouping.
local function sectionsOf(tab)
    local out, current = {}, nil
    for _, e in ipairs(tab.schema) do
        if e.type == "section" then
            current = e.label
            out[#out + 1] = { label = current, keys = {} }
        elseif e.key and e.key ~= "" and #out > 0 then
            local keys = out[#out].keys
            keys[#keys + 1] = e.key
        end
    end
    return out
end

-- Builds the unit_frames page and hands back the captured subtabs control.
local function buildPage(host)
    local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
    local real, captured = H.SuuUI._SettingsControls["subtabs"], nil
    H.SuuUI._SettingsControls["subtabs"] = function(...)
        captured = real(...)
        return captured
    end
    H.SuuUI._PageBuilder:Build("unit_frames", scroll)
    H.SuuUI._SettingsControls["subtabs"] = real
    return captured, scroll
end

describe("Plugins.UnitFrames – settings tabs and visibility", function()
    local host, state

    before_each(function()
        state = require("harness.wow.state")
        state.unitHealth, state.unitHealthMax = 80, 100
        state.unitPower,  state.unitPowerMax  = 60, 100
        state.unitPowerType = 0
        state.unitLevel     = 42   -- below the cap, so the level is visible by default
        state.maxPlayerLevel = 60
        state.reloadUICalled = 0
        H.setup()
        host = H.parent(1024, 768)
    end)

    describe("schema structure", function()
        it("renders unit frames through a tab strip", function()
            expect(subtabsEntry()).as("a subtabs entry exists").notNil()
        end)

        it("has a Player tab", function()
            local tab = playerTab()
            expect(tab).notNil()
            expect(tab.label).eq("Player")
        end)

        it("groups the Player tab into General, Health Bar and Resource Bar", function()
            local sections = sectionsOf(playerTab())
            local labels = {}
            for i, s in ipairs(sections) do labels[i] = s.label end
            expect(labels).deepEq({ "General", "Health Bar", "Resource Bar" })
        end)

        it("puts the frame-wide settings under General, toggles first", function()
            local sections = sectionsOf(playerTab())
            expect(sections[1].keys).deepEq({
                "player_enabled", "player_show_name", "player_show_level",
                "player_hide_level_at_max", "player_width",
            })
        end)

        it("groups the toggles together, with the slider last", function()
            -- A slider between toggles breaks the block visually; order is the guarantee.
            local types = {}
            for _, e in ipairs(playerTab().schema) do
                if e.type == "section" then
                    if e.label ~= "General" then break end
                elseif e.key and e.key ~= "" and #types < 5 then
                    types[#types + 1] = e.type
                end
            end
            expect(types).deepEq({ "toggle", "toggle", "toggle", "toggle", "slider" })
        end)

        it("keeps width out of the Health Bar section", function()
            -- Width drives the name row and both bars, so filing it under one bar would
            -- promise something narrower than it does.
            local sections = sectionsOf(playerTab())
            expect(sections[2].keys).deepEq({ "player_health_height" })
        end)

        it("labels width as frame-wide", function()
            for _, e in ipairs(playerTab().schema) do
                if e.key == "player_width" then expect(e.label).eq("Frame Width") end
            end
        end)

        it("keeps the resource bar height editable", function()
            local sections = sectionsOf(playerTab())
            expect(sections[3].keys).as("resource height is still on the page")
                .deepEq({ "player_power_height" })
        end)

        it("declares every per-unit key exactly once", function()
            -- Two declarations of a key let its default and its slider range drift apart.
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
            walk(H.SuuUI.Settings:GetSchema("unit_frames"))
            for _, key in ipairs({ "player_show_name", "player_show_level", "player_width",
                                   "player_health_height", "player_power_height",
                                   "player_hide_level_at_max" }) do
                expect(seen[key]).as(key .. " is declared once").eq(1)
            end
        end)

        it("resolves defaults for keys declared inside a tab", function()
            -- Register only indexes what it walks; a nested declaration that is not walked
            -- reads as nil no matter what default it states.
            expect(setting("player_show_name")).eq(true)
            expect(setting("player_show_level")).eq(true)
            expect(setting("player_hide_level_at_max")).eq(true)
            expect(setting("player_width")).eq(304)
            expect(setting("player_health_height")).eq(39)
            expect(setting("player_power_height")).eq(22)
        end)

        it("exposes slider ranges from the tab declaration", function()
            for _, e in ipairs(playerTab().schema) do
                if e.type == "slider" then
                    expect(e.min).as(e.key .. " has a min").notNil()
                    expect(e.max).as(e.key .. " has a max").notNil()
                    expect(e.default).as(e.key .. " has a default").notNil()
                end
            end
        end)
    end)

    describe("tab strip rendering", function()
        it("builds one tab button per unit", function()
            local ctl = buildPage(host)
            expect(ctl).notNil()
            expect(#ctl:GetTabButtons()).eq(#subtabsEntry().tabs)
        end)

        it("opens the first tab by default", function()
            local ctl = buildPage(host)
            expect(ctl:GetActiveTab()).eq("player")
            expect(ctl:GetTabButtons()[1].nav:IsSelected()).eq(true)
        end)

        it("tabs hug their label instead of taking the full nav width", function()
            local ctl = buildPage(host)
            local nav = ctl:GetTabButtons()[1].nav
            -- 160 is NavItem's vertical-nav default: a tab strip that inherits it makes
            -- every tab as wide as the widest possible nav row.
            expect(nav:GetWidth()).as("tab hugs its label").lt(160)
            expect(nav:GetWidth()).as("tab is still wide enough to read").gt(0)
        end)

        it("the control reports the height of the open tab's rows", function()
            local ctl = buildPage(host)
            local pane = ctl:GetActivePane()
            expect(pane).notNil()
            expect(pane:GetHeight()).as("pane has resolved geometry").gt(0)
            expect(ctl:GetHeight())
                .as("control is tall enough for tab strip plus rows").gte(pane:GetHeight())
        end)
    end)

    describe("REGRESSION: subtab teardown", function()
        it("switching tabs does not leak settings watchers", function()
            H.SuuUI.Settings:Register("st_leak", {
                { key = "grp", type = "subtabs", tabs = {
                    { id = "one", label = "One", schema = {
                        { key = "a", label = "A", type = "toggle", default = false } } },
                    { id = "two", label = "Two", schema = {
                        { key = "b", label = "B", type = "slider", default = 3,
                          min = 0, max = 9 } } },
                }},
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            local real, ctl = H.SuuUI._SettingsControls["subtabs"], nil
            H.SuuUI._SettingsControls["subtabs"] = function(...)
                ctl = real(...); return ctl
            end
            H.SuuUI._PageBuilder:Build("st_leak", scroll)
            H.SuuUI._SettingsControls["subtabs"] = real

            local afterFirst = H.SuuUI.Settings:GetWatcherCount()
            for _ = 1, 5 do
                ctl:SetActiveTab("two")
                ctl:SetActiveTab("one")
            end
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("each switch retires the outgoing tab's watchers").eq(afterFirst)
        end)

        it("a destroyed tab's control no longer receives writes", function()
            H.SuuUI.Settings:Register("st_stale", {
                { key = "grp", type = "subtabs", tabs = {
                    { id = "one", label = "One", schema = {
                        { key = "a", label = "A", type = "toggle", default = false } } },
                    { id = "two", label = "Two", schema = {
                        { key = "b", label = "B", type = "toggle", default = false } } },
                }},
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            local real, ctl = H.SuuUI._SettingsControls["subtabs"], nil
            H.SuuUI._SettingsControls["subtabs"] = function(...)
                ctl = real(...); return ctl
            end
            H.SuuUI._PageBuilder:Build("st_stale", scroll)
            H.SuuUI._SettingsControls["subtabs"] = real

            ctl:SetActiveTab("two")
            -- Writing the hidden tab's key must reach nobody: its widget is gone.
            local before = H.SuuUI.Settings:GetWatcherCount()
            H.SuuUI.Settings:Set("st_stale", "a", true)
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("no watcher was resurrected by the write").eq(before)
        end)
    end)

    describe("REGRESSION: subtab height", function()
        it("the control grows when a taller tab is opened", function()
            local tall = {}
            for i = 1, 8 do
                tall[i] = { key = "t" .. i, label = "T" .. i, type = "toggle", default = false }
            end
            H.SuuUI.Settings:Register("st_h", {
                { key = "grp", type = "subtabs", tabs = {
                    { id = "short", label = "Short", schema = {
                        { key = "s1", label = "S1", type = "toggle", default = false } } },
                    { id = "tall", label = "Tall", schema = tall },
                }},
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            local real, ctl = H.SuuUI._SettingsControls["subtabs"], nil
            H.SuuUI._SettingsControls["subtabs"] = function(...)
                ctl = real(...); return ctl
            end
            H.SuuUI._PageBuilder:Build("st_h", scroll)
            H.SuuUI._SettingsControls["subtabs"] = real

            local shortH = ctl:GetHeight()
            ctl:SetActiveTab("tall")
            local tallH = ctl:GetHeight()

            expect(tallH).as("eight rows are taller than one").gt(shortH)
            -- A stale box is the bug: the rows render outside the height the page measured.
            expect(tallH).as("the control's box matches its content")
                .eq(select(2, ctl:GetContentSize()))
        end)

        it("the control shrinks again when a shorter tab is reopened", function()
            local tall = {}
            for i = 1, 8 do
                tall[i] = { key = "u" .. i, label = "U" .. i, type = "toggle", default = false }
            end
            H.SuuUI.Settings:Register("st_h2", {
                { key = "grp", type = "subtabs", tabs = {
                    { id = "short", label = "Short", schema = {
                        { key = "v1", label = "V1", type = "toggle", default = false } } },
                    { id = "tall", label = "Tall", schema = tall },
                }},
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            local real, ctl = H.SuuUI._SettingsControls["subtabs"], nil
            H.SuuUI._SettingsControls["subtabs"] = function(...)
                ctl = real(...); return ctl
            end
            H.SuuUI._PageBuilder:Build("st_h2", scroll)
            H.SuuUI._SettingsControls["subtabs"] = real

            local shortH = ctl:GetHeight()
            ctl:SetActiveTab("tall")
            ctl:SetActiveTab("short")
            expect(ctl:GetHeight()).eq(shortH)
        end)
    end)

    describe("show / hide name and level", function()
        local function pf()
            return H.SuuUI.Plugins:Get("unit_frames")._playerFrame
        end

        it("both are visible by default", function()
            expect(pf()._nameText:IsShown()).eq(true)
            expect(pf()._levelText:IsShown()).eq(true)
        end)

        it("hides the name when show_name is off", function()
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            expect(pf()._nameText:IsShown()).eq(false)
            expect(pf()._levelText:IsShown()).as("level is unaffected").eq(true)
        end)

        it("hides the level when show_level is off", function()
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            expect(pf()._levelText:IsShown()).eq(false)
            expect(pf()._nameText:IsShown()).as("name is unaffected").eq(true)
        end)

        it("restores each text when re-enabled", function()
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", true)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", true)
            expect(pf()._nameText:IsShown()).eq(true)
            expect(pf()._levelText:IsShown()).eq(true)
        end)

        it("keeps the level hidden at max level by default", function()
            state.unitLevel, state.maxPlayerLevel = 60, 60
            H.setup()
            expect(setting("player_show_level")).eq(true)
            expect(setting("player_hide_level_at_max")).eq(true)
            expect(pf()._levelText:IsShown()).eq(false)
        end)

        it("shows the level at max level when hide_at_max is off", function()
            state.unitLevel, state.maxPlayerLevel = 60, 60
            H.setup()
            H.SuuUI.Settings:Set("unit_frames", "player_hide_level_at_max", false)
            expect(pf()._levelText:IsShown()).eq(true)
            expect(pf()._levelText:GetText()).eq("60")
        end)

        it("hide_at_max does not affect a level below the cap", function()
            H.SuuUI.Settings:Set("unit_frames", "player_hide_level_at_max", true)
            expect(pf()._levelText:IsShown()).as("level 42 of 60 is still shown").eq(true)
        end)

        it("show_level off wins over hide_at_max off", function()
            H.SuuUI.Settings:Set("unit_frames", "player_hide_level_at_max", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            expect(pf()._levelText:IsShown()).eq(false)
        end)
    end)

    describe("hide-at-max control depends on show level", function()
        -- The ordinal of a key among the toggles the page builds, derived from the schema
        -- in the order PageBuilder walks it, so the spec never hardcodes a row number.
        local function toggleOrdinal(key)
            local n, found = 0, nil
            local function scan(entries)
                for _, e in ipairs(entries) do
                    if e.type == "toggle" then
                        n = n + 1
                        if e.key == key then found = n end
                    elseif e.type == "subtabs" then
                        scan(e.tabs[1].schema)
                    end
                end
            end
            scan(H.SuuUI.Settings:GetSchema("unit_frames"))
            return found
        end

        -- Builds the real unit_frames page, capturing every Toggle widget it creates.
        local function buildCapturingToggles()
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 700, h = 500 }, host)
            local built, real = {}, H.SuuUI.Components.Toggle
            H.SuuUI.Components.Toggle = function(...)
                local t = real(...); built[#built + 1] = t; return t
            end
            H.SuuUI._PageBuilder:Build("unit_frames", scroll)
            H.SuuUI.Components.Toggle = real
            return built
        end

        it("declares the dependency in the schema", function()
            for _, e in ipairs(playerTab().schema) do
                if e.key == "player_hide_level_at_max" then
                    expect(e.enabledIf).eq("player_show_level")
                end
            end
        end)

        it("is usable while Show Level is on", function()
            local built = buildCapturingToggles()
            local tog = built[toggleOrdinal("player_hide_level_at_max")]
            expect(tog).notNil()
            expect(tog._enabled).eq(true)
            expect(H.click(tog)).as("a usable toggle takes the mouse").truthy()
        end)

        it("is greyed out and unusable when Show Level is off", function()
            local built = buildCapturingToggles()
            local tog = built[toggleOrdinal("player_hide_level_at_max")]

            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)

            expect(tog._enabled).as("greyed the moment the dependency goes off").eq(false)
            expect(H.click(tog)).as("and it refuses the mouse").falsy()
        end)

        it("becomes usable again when Show Level comes back", function()
            local built = buildCapturingToggles()
            local tog = built[toggleOrdinal("player_hide_level_at_max")]
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", true)
            expect(tog._enabled).eq(true)
        end)

        it("Show Level itself stays usable", function()
            local built = buildCapturingToggles()
            local showLevel = built[toggleOrdinal("player_show_level")]
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            expect(showLevel._enabled)
                .as("the control you need to undo this must not grey itself").eq(true)
        end)

        it("the stored value survives being greyed out", function()
            buildCapturingToggles()
            H.SuuUI.Settings:Set("unit_frames", "player_hide_level_at_max", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            expect(setting("player_hide_level_at_max"))
                .as("greying a control must not clear what it holds").eq(false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", true)
            expect(setting("player_hide_level_at_max")).eq(false)
        end)
    end)

    describe("Dependency binder", function()
        it("greys bound handles when the dependency goes false", function()
            H.SuuUI.Settings:Register("dep_t", {
                { key = "master", label = "Master", type = "toggle", default = true },
                { key = "child",  label = "Child",  type = "toggle", default = true,
                  enabledIf = "master" },
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            H.SuuUI._PageBuilder:Build("dep_t", scroll)

            local built = {}
            local realToggle = H.SuuUI.Components.Toggle
            -- Rebuild with a capturing factory so the spec holds the widget handles.
            H.SuuUI.Components.Toggle = function(...)
                local t = realToggle(...)
                built[#built + 1] = t
                return t
            end
            H.SuuUI._PageBuilder:Build("dep_t", scroll)
            H.SuuUI.Components.Toggle = realToggle

            local master, child = built[1], built[2]
            expect(child._enabled).as("enabled while master is on").eq(true)

            H.SuuUI.Settings:Set("dep_t", "master", false)
            expect(child._enabled).as("greyed when master goes off").eq(false)
            expect(master._enabled).as("the master itself stays usable").eq(true)

            H.SuuUI.Settings:Set("dep_t", "master", true)
            expect(child._enabled).as("usable again when master returns").eq(true)
        end)

        it("a greyed control refuses the mouse", function()
            H.SuuUI.Settings:Register("dep_click", {
                { key = "master", label = "Master", type = "toggle", default = true },
                { key = "child",  label = "Child",  type = "toggle", default = false,
                  enabledIf = "master" },
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            local built = {}
            local realToggle = H.SuuUI.Components.Toggle
            H.SuuUI.Components.Toggle = function(...)
                local t = realToggle(...); built[#built + 1] = t; return t
            end
            H.SuuUI._PageBuilder:Build("dep_click", scroll)
            H.SuuUI.Components.Toggle = realToggle

            local child = built[2]
            H.SuuUI.Settings:Set("dep_click", "master", false)
            expect(H.click(child)).as("a greyed toggle is not mouse-enabled").falsy()
            expect(H.SuuUI.Settings:Get("dep_click", "child"))
                .as("and the click changed nothing").eq(false)
        end)

        it("the dependency watcher is retired with the control", function()
            H.SuuUI.Settings:Register("dep_leak", {
                { key = "master", label = "Master", type = "toggle", default = true },
                { key = "child",  label = "Child",  type = "toggle", default = true,
                  enabledIf = "master" },
            })
            local scroll = H.SuuUI.Components.ScrollFrame({ w = 500, h = 400 }, host)
            H.SuuUI._PageBuilder:Build("dep_leak", scroll)
            local afterFirst = H.SuuUI.Settings:GetWatcherCount()
            for _ = 1, 5 do H.SuuUI._PageBuilder:Build("dep_leak", scroll) end
            expect(H.SuuUI.Settings:GetWatcherCount())
                .as("a rebuild drops the dependency watcher too").eq(afterFirst)
        end)
    end)

    describe("layout when the info row is hidden", function()
        local function pf()
            return H.SuuUI.Plugins:Get("unit_frames")._playerFrame
        end

        it("bars stay put while either text is visible", function()
            local before = H.box(pf()._healthBar).top
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            expect(H.box(pf()._healthBar).top)
                .as("the row still holds the level, so nothing moves").eq(before)
        end)

        it("bars move to the top of the frame when both texts are hidden", function()
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            local frame = pf()
            -- Geometry, not arithmetic: the health bar must actually sit at the frame's top.
            H.expectOffset(frame._healthBar, frame:GetFrame(), 0, 0)
        end)

        it("frame height drops by the info row and its gap", function()
            local frame = pf()
            local fullH = frame:GetFrame():GetHeight()
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            local infoH = H.lineHeight(H.token("fontSizeLg"))
            H.expectSize(frame:GetFrame(), setting("player_width"),
                         fullH - infoH - H.token("spaceXs"))
        end)

        it("bars keep their own heights when the info row collapses", function()
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            local frame = pf()
            H.expectSize(frame._healthBar,   nil, setting("player_health_height"))
            H.expectSize(frame._resourceBar, nil, setting("player_power_height"))
        end)

        it("restores the original geometry when a text comes back", function()
            local frame = pf()
            local fullH  = frame:GetFrame():GetHeight()
            local barTop = H.box(frame._healthBar).top
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_level", false)
            H.SuuUI.Settings:Set("unit_frames", "player_show_name", true)
            H.expectSize(frame:GetFrame(), nil, fullH)
            expect(H.box(frame._healthBar).top).eq(barTop)
        end)
    end)
end)
