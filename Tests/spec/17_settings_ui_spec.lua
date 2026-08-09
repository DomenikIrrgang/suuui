local H = require("harness")

-- Walks a frame tree collecting every visible widget matching a predicate. Settings
-- controls return anonymous containers, so tests locate their parts by shape rather
-- than by name. Hidden widgets are skipped: a destroyed row is still parented to the
-- content frame, but it is not on screen and must not count as rendered.
local function collect(rootFrame, predicate)
    local found = {}
    local function walk(frame)
        for _, region in ipairs(frame._regions) do
            if region:IsVisible() and predicate(region) then found[#found + 1] = region end
        end
        for _, child in ipairs(frame._childFrames) do
            if child:IsVisible() then
                if predicate(child) then found[#found + 1] = child end
                walk(child)
            end
        end
    end
    walk(rootFrame)
    return found
end

-- The page container and every settings row are all frames parented to the scroll
-- content; the page/row relationship lives in the layout engine, not the frame tree.
local function pageParts(content)
    local pageFrame, rows = nil, {}
    for _, child in ipairs(content._childFrames) do
        if child:IsVisible() then
            if not pageFrame then pageFrame = child else rows[#rows + 1] = child end
        end
    end
    return pageFrame, rows
end

local function labels(rootFrame)
    local out = {}
    for _, fs in ipairs(collect(rootFrame, function(w)
        return w._kind == "FontString" and w:GetText() ~= ""
    end)) do
        out[fs:GetText()] = fs
    end
    return out
end

describe("SettingsUI.Row", function()
    local host
    before_each(function()
        H.setup()
        host = H.parent(400, 200)
    end)

    describe("Labelled", function()
        it("puts the label on the left, filling the slack", function()
            local row, label = H.SuuUI._SettingsRow.Labelled(host, "Show Border")
            local toggle = H.C.Toggle({}, row:GetFrame())
            row:Add(toggle)
            local pad = H.token("spaceSm")
            H.expectOffset(label, row, pad, nil)
            expect(label:GetWidth())
                .as("label eats the space the control does not use")
                .eq(400 - pad * 2 - toggle:GetWidth() - pad)
        end)

        it("pushes the trailing control to the right inset", function()
            local row = H.SuuUI._SettingsRow.Labelled(host, "Show Border")
            local toggle = H.C.Toggle({}, row:GetFrame())
            row:Add(toggle)
            local rb, tb = H.box(row), H.box(toggle)
            expect(tb.right).eq(rb.right - H.token("spaceSm"))
        end)

        it("centres the control against the label on the cross axis", function()
            local row, label = H.SuuUI._SettingsRow.Labelled(host, "Show Border")
            local toggle = H.C.Toggle({}, row:GetFrame())
            row:Add(toggle)
            H.expectCenteredV(toggle, row)
            H.expectCenteredV(label, row)
        end)

        it("hugs its content height, including vertical padding", function()
            local row = H.SuuUI._SettingsRow.Labelled(host, "Show Border")
            local toggle = H.C.Toggle({}, row:GetFrame())
            row:Add(toggle)
            local vpad = H.token("spaceXs")
            expect(row:GetHeight()).eq(toggle:GetHeight() + vpad * 2)
        end)

        it("grows with the font token rather than clipping the label", function()
            local row, label = H.SuuUI._SettingsRow.Labelled(host, "Show Border")
            row:Add(H.C.Toggle({}, row:GetFrame()))
            local before = row:GetHeight()

            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 32)
            H.T:SetActive("Big")

            expect(row:GetHeight()).gt(before)
            expect(row:GetHeight()).gte(label:GetHeight())
            H.expectInside(label, row)
        end)

        it("keeps the label and control from colliding at a narrow width", function()
            local row, label = H.SuuUI._SettingsRow.Labelled(host, "A rather long setting label")
            local toggle = H.C.Toggle({}, row:GetFrame())
            row:Add(toggle)
            row:SetWidth(120)
            H.expectNoOverlap({ label, toggle })
            H.expectInside(toggle, row)
        end)

        it("tolerates a missing label", function()
            local row, label = H.SuuUI._SettingsRow.Labelled(host, nil)
            expect(label:GetText()).eq("")
            expect(function() row:Layout() end).notThrows()
        end)
    end)

    describe("Stacked", function()
        it("stacks children full width inside horizontal padding", function()
            local row = H.SuuUI._SettingsRow.Stacked(host)
            local a = H.C.Frame({ w = 10, h = 20 }, row:GetFrame())
            local b = H.C.Frame({ w = 10, h = 30 }, row:GetFrame())
            row:Add(a, { width = "fill", height = 20 })
            row:Add(b, { width = "fill", height = 30 })
            local pad = H.token("spaceSm")
            H.expectSize(a, 400 - pad * 2, 20)
            H.expectStackedVertically({ a, b }, H.token("spaceXs"))
        end)

        it("hugs its content height with no vertical padding", function()
            local row = H.SuuUI._SettingsRow.Stacked(host)
            local a = H.C.Frame({ w = 10, h = 24 }, row:GetFrame())
            row:Add(a, { width = "fill", height = 24 })
            expect(row:GetHeight()).eq(24)
        end)
    end)
end)

describe("SettingsUI.PageBuilder", function()
    local host, scroll

    local schema = {
        { key = "enabled",  label = "Enable",   type = "toggle",   default = true },
        { key = "",         label = "Appearance", type = "section" },
        { key = "size",     label = "Size",     type = "slider",   default = 14, min = 8, max = 32, step = 1 },
        { key = "style",    label = "Style",    type = "dropdown", default = "solid",
          options = { { value = "solid", label = "Solid" }, { value = "flat", label = "Flat" } } },
        { key = "tint",     label = "Tint",     type = "color",    default = { 1, 0, 0, 1 } },
        { key = "caption",  label = "Caption",  type = "text",     default = "hello" },
        { key = "bind",     label = "Keybind",  type = "keybind",  default = "" },
    }

    before_each(function()
        H.setup()
        host = H.parent(500, 400)
        scroll = H.mount(H.C.ScrollFrame({ w = 400, h = 300 }, host))
        H.SuuUI.Settings:Register("page_spec", schema)
    end)

    local function build()
        H.SuuUI._PageBuilder:Build("page_spec", scroll)
        return scroll:GetContent()
    end

    it("renders one row per schema entry", function()
        local _, rows = pageParts(build())
        expect(#rows).eq(#schema)
    end)

    it("renders a control for every schema type", function()
        local found = labels(build())
        for _, entry in ipairs(schema) do
            expect(found[entry.label]).as("row for " .. entry.label).notNil()
        end
    end)

    it("fits the page to the scroll frame's usable width", function()
        local page = pageParts(build())
        expect(page:GetWidth()).eq(scroll:GetContentWidth())
    end)

    it("stacks rows without overlapping, all inside the page", function()
        local page, rows = pageParts(build())
        H.expectNoOverlap(rows)
        for _, row in ipairs(rows) do H.expectInside(row, page) end
    end)

    it("separates rows by the spaceXs gap, in schema order", function()
        local _, rows = pageParts(build())
        H.expectStackedVertically(rows, H.token("spaceXs"))
    end)

    it("reports the page height to the scroll frame", function()
        local page = pageParts(build())
        expect(scroll:GetContent():GetHeight()).eq(math.max(page:GetHeight(), 300))
    end)

    it("raises a scrollbar once the page outgrows a short viewport", function()
        scroll = H.mount(H.C.ScrollFrame({ w = 400, h = 80 }, host))
        H.SuuUI._PageBuilder:Build("page_spec", scroll)
        expect(scroll._track:IsShown()).truthy()
        local page = pageParts(scroll:GetContent())
        expect(page:GetWidth()).as("the page narrows to leave the bar room")
            .eq(scroll:GetContentWidth())
    end)

    it("tears down the previous page before building a new one", function()
        local content = build()
        local first = pageParts(content)
        H.SuuUI.Settings:Register("page_spec2",
            { { key = "a", label = "Only", type = "toggle", default = true } })
        H.SuuUI._PageBuilder:Build("page_spec2", scroll)
        expect(first:IsShown()).as("the old page is destroyed, not stacked behind").falsy()
        local found = labels(content)
        expect(found["Only"]).notNil()
        expect(found["Enable"]).as("no orphaned rows left on screen").isNil()
        local _, rows = pageParts(content)
        expect(#rows).eq(1)
    end)

    it("does nothing for an unregistered plugin", function()
        local content = scroll:GetContent()
        expect(function() H.SuuUI._PageBuilder:Build("no_such_plugin", scroll) end).notThrows()
        expect(#content._childFrames).eq(0)
    end)

    it("logs and skips an unknown control type", function()
        H.setup({ debug = true })
        host = H.parent(500, 400)
        scroll = H.mount(H.C.ScrollFrame({ w = 400, h = 300 }, host))
        H.SuuUI.Settings:Register("odd_spec", {
            { key = "a", label = "Known", type = "toggle", default = true },
            { key = "b", label = "Weird", type = "hologram" },
        })
        H.SuuUI._PageBuilder:Build("odd_spec", scroll)
        local _, rows = pageParts(scroll:GetContent())
        expect(#rows).as("only the known row rendered").eq(1)
        local logged = false
        for _, line in ipairs(H.debugLog()) do
            if line:find("no control for type") then logged = true end
        end
        expect(logged).truthy()
    end)

    it("re-flows the page when the scroll frame is resized", function()
        build()
        scroll:SetSize(250, 300)
        local page, rows = pageParts(scroll:GetContent())
        expect(page:GetWidth()).eq(scroll:GetContentWidth())
        for _, row in ipairs(rows) do H.expectInside(row, page) end
    end)

    it("re-flows the page when a font token grows", function()
        build()
        local page = pageParts(scroll:GetContent())
        local before = page:GetHeight()
        H.T:CreateUserTheme("Big", "Modern")
        H.T:SetUserToken("Big", "fontSizeMd", 30)
        H.T:SetActive("Big")
        expect(page:GetHeight()).as("taller rows mean a taller page").gt(before)
        local _, rows = pageParts(scroll:GetContent())
        H.expectNoOverlap(rows)
    end)
end)

describe("SettingsUI controls", function()
    local host, row

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
    end)

    local function build(type_, entry)
        H.SuuUI.Settings:Register("ctrl_spec", { entry })
        row = H.SuuUI._SettingsControls[type_](entry, "ctrl_spec", host)
        return row
    end

    describe("toggle", function()
        local entry = { key = "flag", label = "Enable", type = "toggle", default = true }

        it("shows the stored value", function()
            build("toggle", entry)
            local toggles = collect(row:GetFrame(), function(w)
                return w._kind == "Frame" and math.abs(w:GetWidth() - H.token("sizeToggleW")) < 0.5
            end)
            expect(#toggles).gte(1)
        end)

        it("writes the setting when clicked", function()
            build("toggle", entry)
            local tog
            for _, child in ipairs(row:GetChildren()) do
                if child._childFrames and #child._childFrames > 0 then tog = child end
            end
            expect(tog).notNil()
            H.click(tog)
            expect(H.SuuUI.Settings:Get("ctrl_spec", "flag")).falsy()
        end)

        it("re-reads the setting when the profile changes", function()
            build("toggle", entry)
            H.SuuUI.Settings:Set("ctrl_spec", "flag", false)
            H.SuuUI.Profiles:Create("Other")
            H.SuuUI.Profiles:SetActive("Other")
            expect(H.SuuUI.Settings:Get("ctrl_spec", "flag")).falsy()
        end)
    end)

    describe("slider", function()
        local entry = { key = "size", label = "Size", type = "slider",
                        default = 14, min = 8, max = 32, step = 1 }

        it("seeds the slider from the stored value and range", function()
            build("slider", entry)
            local sliders = collect(row:GetFrame(), function(w)
                return w._kind == "FontString" and w:GetText() == "14"
            end)
            expect(#sliders).as("the value readout shows the stored value").gte(1)
        end)

        it("spans the row width", function()
            build("slider", entry)
            local pad = H.token("spaceSm")
            expect(row:GetChildren()[1]:GetWidth()).eq(400 - pad * 2)
        end)
    end)

    describe("text", function()
        local entry = { key = "caption", label = "Caption", type = "text", default = "hello" }

        it("seeds the input from the stored value", function()
            build("text", entry)
            local boxes = collect(row:GetFrame(), function(w) return w._kind == "EditBox" end)
            expect(#boxes).eq(1)
            expect(boxes[1]:GetText()).eq("hello")
        end)

        it("writes the setting as the user types", function()
            build("text", entry)
            local eb = collect(row:GetFrame(), function(w) return w._kind == "EditBox" end)[1]
            H.typeText({ _eb = eb }, "typed value")
            expect(H.SuuUI.Settings:Get("ctrl_spec", "caption")).eq("typed value")
        end)

        it("does not write back when the profile reload sets the value", function()
            build("text", entry)
            H.SuuUI.Settings:Set("ctrl_spec", "caption", "stored")
            local spy = H.eventSpy("SUUUI_SETTING_CHANGED")
            H.SuuUI.Events:Emit("SUUUI_PROFILE_LOADED", "Default")
            expect(spy.count).as("SetValue is silent, so no echo back into settings").eq(0)
        end)

        it("keeps the input at a fixed 140 width beside the label", function()
            build("text", entry)
            local inputFrame
            for _, child in ipairs(row:GetChildren()) do
                if math.abs(child:GetWidth() - 140) < 0.5 then inputFrame = child end
            end
            expect(inputFrame).notNil()
            expect(inputFrame:GetHeight()).as("height comes from the tokens")
                .eq(H.controlHeight("sizeControlMd"))
        end)
    end)

    describe("section", function()
        local entry = { key = "", label = "Appearance", type = "section" }

        it("renders a labelled divider at row height", function()
            H.SuuUI.Settings:Register("ctrl_spec", { entry })
            row = H.SuuUI._SettingsControls["section"](entry, host)
            local found = labels(row:GetFrame())
            expect(found["Appearance"]).notNil()
            expect(row:GetChildren()[1]:GetHeight()).eq(H.controlHeight("sizeRow"))
        end)

        it("spans the row width", function()
            H.SuuUI.Settings:Register("ctrl_spec", { entry })
            row = H.SuuUI._SettingsControls["section"](entry, host)
            local pad = H.token("spaceSm")
            expect(row:GetChildren()[1]:GetWidth()).eq(400 - pad * 2)
        end)
    end)

    describe("dropdown", function()
        local entry = { key = "style", label = "Style", type = "dropdown", default = "solid",
                        options = { { value = "solid", label = "Solid" },
                                    { value = "flat",  label = "Flat" } } }

        it("shows the label of the stored value", function()
            build("dropdown", entry)
            local found = labels(row:GetFrame())
            expect(found["Solid"]).notNil()
        end)
    end)

    describe("keybind", function()
        local entry = { key = "bind", label = "Keybind", type = "keybind", default = "" }

        it("shows the unbound placeholder", function()
            build("keybind", entry)
            local found = labels(row:GetFrame())
            expect(found["Not Bound"]).notNil()
        end)
    end)

    describe("color", function()
        local entry = { key = "tint", label = "Tint", type = "color", default = { 1, 0, 0, 1 } }

        it("shows a swatch filled with the stored colour", function()
            build("color", entry)
            local swatches = collect(row:GetFrame(), function(w)
                if w._kind ~= "Texture" then return false end
                local r, g, b = w:GetColorTexture()
                return r == 1 and g == 0 and b == 0
            end)
            expect(#swatches).gte(1)
        end)
    end)

    -- Until these were wired, _SettingsDeps.Bind was called from exactly one builder
    -- (toggle), so an enabledIf on any other control type was accepted by the schema and
    -- then silently ignored. One case per builder, so dropping any single Bind call fails.
    describe("enabledIf dependency wiring", function()
        -- type -> the component factory whose handle the row hands to Bind
        local factoryFor = {
            slider   = "Slider",
            dropdown = "Dropdown",
            text     = "Input",
            color    = "ColorSwatch",
            keybind  = "KeyCapture",
        }

        local function buildDependent(type_, extra)
            local plugin = "dep_" .. type_
            local entry = { key = "child", label = "Child", type = type_, enabledIf = "master" }
            for k, v in pairs(extra or {}) do entry[k] = v end
            H.SuuUI.Settings:Register(plugin, {
                { key = "master", label = "Master", type = "toggle", default = true },
                entry,
            })

            -- Wrap the factory so the spec holds the handle the builder created; the row
            -- itself is an anonymous container and does not expose its control.
            local name = factoryFor[type_]
            local real, captured = H.SuuUI.Components[name], nil
            H.SuuUI.Components[name] = function(...)
                captured = real(...)
                return captured
            end
            local builtRow = H.SuuUI._SettingsControls[type_](entry, plugin, host)
            H.SuuUI.Components[name] = real

            expect(captured).as(name .. " handle captured").notNil()
            return captured, plugin, builtRow
        end

        for _, type_ in ipairs({ "slider", "dropdown", "text", "color", "keybind" }) do
            it("greys a " .. type_ .. " whose dependency goes false", function()
                local ctrl, plugin = buildDependent(type_,
                    type_ == "slider" and { min = 0, max = 10, step = 1, default = 5 } or nil)

                expect(ctrl:IsEnabled()).as("live while master is on").truthy()

                H.SuuUI.Settings:Set(plugin, "master", false)
                expect(ctrl:IsEnabled()).as("greyed when master goes off").falsy()
                expect(ctrl:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))

                H.SuuUI.Settings:Set(plugin, "master", true)
                expect(ctrl:IsEnabled()).as("live again").truthy()
                expect(ctrl:GetFrame():GetAlpha()).eq(1)
            end)
        end

        -- The label is a sibling in the row, not a child of the control, so the fade on
        -- the control cannot reach it. It has to be passed to Bind explicitly.
        it("greys the row label alongside the control", function()
            H.SuuUI.Settings:Register("dep_label", {
                { key = "master", label = "Master", type = "toggle", default = true },
                { key = "child", label = "Child", type = "dropdown", enabledIf = "master",
                  options = { "a", "b" } },
            })

            local realText, texts = H.SuuUI.Components.Text, {}
            H.SuuUI.Components.Text = function(...)
                local t = realText(...)
                texts[#texts + 1] = t
                return t
            end
            H.SuuUI._SettingsControls["dropdown"](
                { key = "child", label = "Child", type = "dropdown", enabledIf = "master",
                  options = { "a", "b" } }, "dep_label", host)
            H.SuuUI.Components.Text = realText

            -- Row.Labelled creates the row label first, before the control's own text.
            local label = texts[1]
            expect(label).notNil()
            expect(label:IsEnabled()).as("live while master is on").truthy()

            H.SuuUI.Settings:Set("dep_label", "master", false)
            expect(label:IsEnabled()).as("label greys with the control").falsy()
        end)
    end)

    it("registers a builder for every schema type the docs list", function()
        for _, type_ in ipairs({ "toggle", "slider", "dropdown", "color", "text",
                                 "keybind", "section", "profile_manager", "theme_manager" }) do
            expect(type(H.SuuUI._SettingsControls[type_])).as(type_).eq("function")
        end
    end)
end)

describe("ThemeManager toggle token control", function()
    local host, scroll, capturedToggle

    -- Wraps C.Toggle so we can capture the handle the theme manager creates
    local function buildCapturingToggle()
        local realToggle = H.C.Toggle
        capturedToggle = nil
        H.C.Toggle = function(...)
            capturedToggle = realToggle(...)
            return capturedToggle
        end
        H.SuuUI.Settings:Register("_tmgr_tog", {
            { key = "_theme_mgr", type = "theme_manager" },
        })
        H.SuuUI._PageBuilder:Build("_tmgr_tog", scroll)
        H.C.Toggle = realToggle
        return capturedToggle
    end

    before_each(function()
        H.setup()
        host = H.parent(500, 600)
        scroll = H.mount(H.C.ScrollFrame({ w = 460, h = 500 }, host))
    end)

    it("renders a toggle row with the correct label", function()
        buildCapturingToggle()
        local content = scroll:GetContent()
        local found = {}
        local function walk(frame)
            for _, region in ipairs(frame._regions) do
                if region:IsVisible() and region._kind == "FontString" and region:GetText() ~= "" then
                    found[region:GetText()] = region
                end
            end
            for _, child in ipairs(frame._childFrames) do
                if child:IsVisible() then walk(child) end
            end
        end
        walk(content)
        expect(found["Use Class Colours"]).as("the toggle row label exists").notNil()
    end)

    it("the toggle has resolvable on-screen geometry", function()
        local tog = buildCapturingToggle()
        expect(tog).notNil()
        local b = H.box(tog)
        expect(b).as("toggle has a resolved box").notNil()
        expect(b.width).gt(0)
        expect(b.height).gt(0)
    end)

    it("seeds the toggle from the active theme's token value", function()
        -- Default theme has colorUseClassColors = false
        H.SuuUI.Theme:SetActive("Default")
        local tog = buildCapturingToggle()
        expect(tog:GetValue()).as("Default theme: token is false").eq(false)
    end)

    it("seeds the toggle as true when Modern theme is active", function()
        H.SuuUI.Theme:SetActive("Modern")
        local tog = buildCapturingToggle()
        expect(tog:GetValue()).as("Modern theme: token is true").eq(true)
    end)

    describe("disabled on built-in themes", function()
        it("is disabled while Default (built-in) is active", function()
            H.SuuUI.Theme:SetActive("Default")
            local tog = buildCapturingToggle()
            expect(tog:IsEnabled()).as("disabled on Default").falsy()
            expect(tog:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("is disabled while Modern (built-in) is active", function()
            H.SuuUI.Theme:SetActive("Modern")
            local tog = buildCapturingToggle()
            expect(tog:IsEnabled()).as("disabled on Modern").falsy()
            expect(tog:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("refuses mouse input while a built-in theme is active", function()
            H.SuuUI.Theme:SetActive("Default")
            local tog = buildCapturingToggle()
            expect(H.click(tog)).as("click returns false on built-in").falsy()
        end)

        it("stays inert on forceClick while built-in", function()
            H.SuuUI.Theme:SetActive("Default")
            local tog = buildCapturingToggle()
            local spy = H.signalSpy(tog, H.S.SIGNALS.VALUE_CHANGED)
            H.forceClick(tog)
            expect(spy.count).as("no value change emitted").eq(0)
            expect(tog:GetValue()).eq(false)
        end)
    end)

    describe("enabled on user themes", function()
        before_each(function()
            H.SuuUI.Theme:CreateUserTheme("Test", "Default")
            H.SuuUI.Theme:SetActive("Test")
        end)

        it("is enabled on a user theme", function()
            local tog = buildCapturingToggle()
            expect(tog:IsEnabled()).as("enabled on user theme").truthy()
            expect(tog:GetFrame():GetAlpha()).eq(1)
        end)

        it("clicking writes the token value", function()
            local tog = buildCapturingToggle()
            -- Default base has colorUseClassColors = false
            expect(H.SuuUI.Theme:GetToken("colorUseClassColors")).eq(false)
            H.click(tog)
            expect(H.SuuUI.Theme:GetToken("colorUseClassColors"))
                .as("token flipped to true")
                .eq(true)
        end)

        it("round-trips: flipping twice restores the original", function()
            local tog = buildCapturingToggle()
            local original = H.SuuUI.Theme:GetToken("colorUseClassColors")
            H.click(tog)
            H.click(tog)
            expect(H.SuuUI.Theme:GetToken("colorUseClassColors"))
                .as("back to original after two clicks")
                .eq(original)
        end)

        it("emits VALUE_CHANGED on user interaction", function()
            local tog = buildCapturingToggle()
            local spy = H.signalSpy(tog, H.S.SIGNALS.VALUE_CHANGED)
            H.click(tog)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq(true)
            expect(spy:arg(2)).eq(false)
        end)
    end)

    describe("refresh on theme switch", function()
        it("updates the toggle when the active theme changes", function()
            H.SuuUI.Theme:CreateUserTheme("Test", "Default")
            H.SuuUI.Theme:SetActive("Test")
            local tog = buildCapturingToggle()
            -- Test inherits Default's false
            expect(tog:GetValue()).eq(false)

            -- Switch to Modern (true)
            H.SuuUI.Theme:SetActive("Modern")
            expect(tog:GetValue()).as("refreshed to Modern's value").eq(true)
        end)

        it("refresh does not emit VALUE_CHANGED (setters are silent)", function()
            H.SuuUI.Theme:CreateUserTheme("Test", "Default")
            H.SuuUI.Theme:SetActive("Test")
            local tog = buildCapturingToggle()
            local spy = H.signalSpy(tog, H.S.SIGNALS.VALUE_CHANGED)

            H.SuuUI.Theme:SetActive("Modern")
            expect(spy.count).as("SetValue is silent by contract").eq(0)
        end)

        it("becomes disabled when switching from user to built-in", function()
            H.SuuUI.Theme:CreateUserTheme("Test", "Default")
            H.SuuUI.Theme:SetActive("Test")
            local tog = buildCapturingToggle()
            expect(tog:IsEnabled()).truthy()

            H.SuuUI.Theme:SetActive("Default")
            expect(tog:IsEnabled()).as("disabled after switch to built-in").falsy()
            expect(tog:GetFrame():GetAlpha()).eq(H.token("opacityDisabled"))
        end)

        it("becomes enabled when switching from built-in to user", function()
            H.SuuUI.Theme:SetActive("Default")
            local tog = buildCapturingToggle()
            expect(tog:IsEnabled()).falsy()

            H.SuuUI.Theme:CreateUserTheme("Test2", "Default")
            H.SuuUI.Theme:SetActive("Test2")
            expect(tog:IsEnabled()).as("enabled after switch to user theme").truthy()
            expect(tog:GetFrame():GetAlpha()).eq(1)
        end)
    end)
end)
