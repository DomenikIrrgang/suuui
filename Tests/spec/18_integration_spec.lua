-- End-to-end checks: open the real settings window, visit every page, and drive the
-- theme and profile managers. This is the guard that catches a component change
-- breaking something further up the stack.
local H = require("harness")

local function visibleLabels(rootFrame)
    local out = {}
    local function walk(frame)
        for _, region in ipairs(frame._regions) do
            if region._kind == "FontString" and region:IsVisible() and region:GetText() ~= "" then
                out[region:GetText()] = region
            end
        end
        for _, child in ipairs(frame._childFrames) do
            if child:IsVisible() then walk(child) end
        end
    end
    walk(rootFrame)
    return out
end

local function findNavItem(win, label)
    local found
    local function walk(frame)
        for _, region in ipairs(frame._regions) do
            if region._kind == "FontString" and region:GetText() == label then
                found = frame
            end
        end
        for _, child in ipairs(frame._childFrames) do walk(child) end
    end
    walk(win:GetFrame())
    return found
end

describe("Settings window integration", function()
    local win

    before_each(function()
        H.setup()
        H.env.SlashCmdList["SUUUI"]()
        win = H.Layout:GetWindow("settings")
    end)

    it("opens without error and shows the window", function()
        expect(win).notNil()
        expect(win:IsShown()).truthy()
    end)

    it("settles the whole window layout in a bounded number of passes", function()
        expect(H.state.settleIterations).as("no resize feedback loop").lte(20)
    end)

    it("selects the first nav entry on open", function()
        expect(visibleLabels(win:GetFrame())["Theme"]).notNil()
    end)

    it("keeps every direct child of the content area inside it", function()
        local content = win:GetContentFrame()
        for _, child in ipairs(content._childFrames) do
            if child:IsVisible() then H.expectInside(child, content) end
        end
    end)

    it("switches to the Profiles page when its nav row is clicked", function()
        local row = findNavItem(win, "Profiles")
        expect(row).notNil()
        H.click(row)
        local labels = visibleLabels(win:GetFrame())
        expect(labels["Profiles"]).notNil()
    end)

    it("visits every nav entry without error", function()
        for _, label in ipairs({ "Theme", "Profiles" }) do
            local row = findNavItem(win, label)
            expect(function() H.click(row) end).as(label).notThrows()
            H.runAnimations()
        end
    end)

    it("survives a font token change with the window open", function()
        expect(function()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 28)
            H.T:SetActive("Big")
        end).notThrows()
        local content = win:GetContentFrame()
        for _, child in ipairs(content._childFrames) do
            if child:IsVisible() then H.expectInside(child, content) end
        end
    end)

    it("survives a spacing token change with the window open", function()
        expect(function()
            H.T:CreateUserTheme("Roomy", "Modern")
            H.T:SetUserToken("Roomy", "spaceSm", 20)
            H.T:SetActive("Roomy")
        end).notThrows()
    end)

    it("survives a resize with the window open", function()
        expect(function() win:GetFrame():SetSize(600, 400) end).notThrows()
        local content = win:GetContentFrame()
        for _, child in ipairs(content._childFrames) do
            if child:IsVisible() then H.expectInside(child, content) end
        end
    end)

    it("gives nav rows the full panel width with no scrollbar gutter", function()
        local row = findNavItem(win, "Theme")
        local before = row:GetWidth()
        win:GetFrame():SetSize(900, 600)
        expect(row:GetWidth())
            .as("a short nav list must not reserve a gutter until it is resized")
            .eq(before)
    end)

    it("rebuilds the nav when a plugin registers", function()
        H.SuuUI:CreatePlugin({
            id = "late_plugin", name = "Late Plugin", version = "1.0",
            onInit = function()
                H.SuuUI.Settings:Register("late_plugin", {
                    { key = "on", label = "Enable", type = "toggle", default = true },
                })
            end,
        })
        H.SuuUI.Plugins:InitAll()
        H.SuuUI.Plugins:Get("late_plugin"):Enable()
        expect(findNavItem(win, "Late Plugin")).notNil()
    end)

    it("renders a late plugin's page from its schema", function()
        H.SuuUI:CreatePlugin({
            id = "late_plugin", name = "Late Plugin", version = "1.0",
            onInit = function()
                H.SuuUI.Settings:Register("late_plugin", {
                    { key = "on",   label = "Enable Feature", type = "toggle", default = true },
                    { key = "size", label = "Feature Size",   type = "slider", default = 10,
                      min = 1, max = 20, step = 1 },
                })
            end,
        })
        H.SuuUI.Plugins:InitAll()
        H.SuuUI.Plugins:Get("late_plugin"):Enable()
        H.click(findNavItem(win, "Late Plugin"))
        local labels = visibleLabels(win:GetFrame())
        expect(labels["Enable Feature"]).notNil()
        expect(labels["Feature Size"]).notNil()
    end)
end)

describe("Theme manager page", function()
    local win

    before_each(function()
        H.setup()
        H.env.SlashCmdList["SUUUI"]()
        win = H.Layout:GetWindow("settings")
    end)

    it("lists the built-in themes and the active one", function()
        local labels = visibleLabels(win:GetFrame())
        expect(labels["Modern"]).as("the active theme is shown").notNil()
    end)

    it("creates, edits and deletes a user theme without error", function()
        expect(function()
            H.T:CreateUserTheme("Spec", "Modern")
            H.T:SetActive("Spec")
            H.T:SetUserToken("Spec", "colorBlue400", { 0, 1, 0, 1 })
        end).notThrows()
        expect(H.token("colorAccent")).deepEq({ 0, 1, 0, 1 })

        expect(function() H.T:DeleteUserTheme("Spec") end).notThrows()
        expect(H.T:GetActive()).eq("Modern")
    end)

    it("refuses to delete a built-in theme and says so through a notice", function()
        local before = H.T:List()
        expect(function() H.T:DeleteUserTheme("Modern") end).throws("cannot delete built-in")
        expect(#H.T:List()).eq(#before)
    end)

    it("keeps the page usable after switching themes", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()
        local content = win:GetContentFrame()
        for _, child in ipairs(content._childFrames) do
            if child:IsVisible() then H.expectInside(child, content) end
        end
    end)

    -- The font row is a dropdown of every face the client and any media addon expose.
    -- Its control frame is the row sibling that takes mouse input, which is what a
    -- disabled dropdown stops doing.
    local function fontControl()
        local label = visibleLabels(win:GetFrame())["Font"]
        if not label then return nil end
        local row = label:GetParent()
        for _, child in ipairs(row._childFrames) do
            if child:IsVisible() and child:IsMouseEnabled() then return child end
        end
        return row._childFrames[1]
    end

    it("shows the active theme's font by name", function()
        expect(visibleLabels(win:GetFrame())["Font"]).as("the row is rendered").notNil()
        expect(visibleLabels(win:GetFrame())["Friz Quadrata TT"])
            .as("selected by name, not by file path").notNil()
    end)

    it("offers every font the registry knows", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()

        H.click(fontControl())
        H.runAnimations()
        -- The panel floats on the shared host, so it hangs off UIParent, not the window.
        local labels = visibleLabels(H.UIParent)
        for _, opt in ipairs(H.SuuUI.Fonts:Options()) do
            expect(labels[opt.label]).as(opt.label .. " is offered").notNil()
        end
    end)

    it("cannot be changed on a built-in theme", function()
        expect(H.T:IsBuiltin(H.T:GetActive())).truthy()
        expect(H.click(fontControl())).as("a disabled dropdown takes no input").falsy()
        H.runAnimations()
        expect(visibleLabels(H.UIParent)["Arial Narrow"]).as("no panel opened").isNil()
    end)

    it("can be changed on a user theme, and the change reaches the UI", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()

        local control = fontControl()
        expect(H.click(control)).as("editable now").truthy()
        H.runAnimations()

        local option = visibleLabels(H.UIParent)["Arial Narrow"]
        expect(option).as("the open panel lists it").notNil()
        H.click(option:GetParent())
        H.runAnimations()

        expect(H.T:GetTokenRaw("fontFamilyMain")).eq("Arial Narrow")
        expect(H.token("fontFamilyMain")).eq("Fonts/ARIALN.TTF")
        expect(visibleLabels(win:GetFrame())["Arial Narrow"]).as("row shows the choice").notNil()
    end)

    it("previews each option in the face it names", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()
        H.click(fontControl())
        H.runAnimations()

        local labels = visibleLabels(H.UIParent)
        for _, opt in ipairs(H.SuuUI.Fonts:Options()) do
            local region = labels[opt.label]
            expect(region).notNil()
            expect((region:GetFont())).as(opt.label .. " renders in itself")
                .eq(H.SuuUI.Fonts:Path(opt.value))
            H.expectTextNotClipped(region)
        end
    end)

    -- Add: the escape hatch for a font no discovery source can see, since WoW exposes no
    -- way to list files.
    local function addFontControl()
        local label = visibleLabels(win:GetFrame())["Font"]
        local row = label:GetParent()
        for _, child in ipairs(row._childFrames) do
            for _, region in ipairs(child._regions) do
                if region._kind == "FontString" and region:GetText() == "Add" then
                    return child
                end
            end
        end
    end

    -- The modal floats on UIParent, and the settings window behind it is full of visible
    -- edit boxes and an "Add" button of its own. Both lookups prune that subtree, or they
    -- find the page's controls instead of the dialog's.
    local function inModal(predicate)
        local found
        local function walk(frame)
            if found or frame == win:GetFrame() or not frame:IsVisible() then return end
            if predicate(frame) then found = frame; return end
            for _, child in ipairs(frame._childFrames) do walk(child) end
        end
        walk(H.UIParent)
        return found
    end

    local function modalInput()
        return inModal(function(f) return f._kind == "EditBox" end)
    end

    local function modalConfirm()
        return inModal(function(f)
            for _, region in ipairs(f._regions) do
                if region._kind == "FontString" and region:GetText() == "Add" then
                    return true
                end
            end
            return false
        end)
    end

    it("takes a custom font path and selects it", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()

        H.font.addFace("Interface/AddOns/MyMedia/fonts/Expressway.ttf")
        H.click(addFontControl())
        H.runAnimations()

        H.typeText({ _eb = modalInput() }, "Interface/AddOns/MyMedia/fonts/Expressway.ttf")
        H.click(modalConfirm())
        H.runAnimations()

        expect(H.SuuUI.Fonts:Has("Expressway")).as("registered").truthy()
        expect(H.T:GetTokenRaw("fontFamilyMain")).as("and selected").eq("Expressway")
        expect(H.token("fontFamilyMain"))
            .eq("Interface/AddOns/MyMedia/fonts/Expressway.ttf")
    end)

    it("warns instead of storing a path the client cannot load", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.runAnimations()

        H.click(addFontControl())
        H.runAnimations()
        H.typeText({ _eb = modalInput() }, "Interface/AddOns/Typo/fnots/mine.ttf")
        H.click(modalConfirm())
        H.runAnimations()

        expect(H.T:GetTokenRaw("fontFamilyMain")).as("token untouched")
            .eq("Friz Quadrata TT")
        expect(visibleLabels(H.UIParent)["Font Not Loaded"]).as("said so").notNil()
    end)

    it("cannot add a font on a built-in theme", function()
        expect(H.click(addFontControl())).falsy()
    end)

    it("keeps every visible label unclipped after a font change", function()
        H.T:CreateUserTheme("Spec", "Modern")
        H.T:SetActive("Spec")
        H.T:SetUserToken("Spec", "fontFamilyMain", "Morpheus")
        H.runAnimations()
        for _, region in pairs(visibleLabels(win:GetFrame())) do
            H.expectTextNotClipped(region)
        end
    end)
end)

describe("Profile manager page", function()
    local win

    before_each(function()
        H.setup()
        H.env.SlashCmdList["SUUUI"]()
        win = H.Layout:GetWindow("settings")
        H.click(findNavItem(win, "Profiles"))
    end)

    it("shows the active profile", function()
        expect(visibleLabels(win:GetFrame())["Default"]).notNil()
    end)

    it("creates and switches profiles without error", function()
        expect(function()
            H.SuuUI.Profiles:Create("Raid")
            H.SuuUI.Profiles:SetActive("Raid")
        end).notThrows()
        expect(H.SuuUI.Profiles:GetActiveName()).eq("Raid")
    end)

    it("keeps controls in step with a profile switch", function()
        H.SuuUI.Settings:Register("switch_spec",
            { { key = "flag", label = "Flag", type = "toggle", default = true } })
        H.SuuUI.Settings:Set("switch_spec", "flag", false)
        H.SuuUI.Profiles:Create("Raid")
        H.SuuUI.Profiles:SetActive("Raid")
        expect(H.SuuUI.Settings:Get("switch_spec", "flag")).falsy()
    end)

    it("survives deleting a non-active profile", function()
        H.SuuUI.Profiles:Create("Raid")
        expect(function() H.SuuUI.Profiles:Delete("Raid") end).notThrows()
        expect(H.SuuUI.Profiles:GetActiveName()).eq("Default")
    end)
end)

describe("Plugin lifecycle", function()
    before_each(function() H.setup() end)

    it("calls onInit on login", function()
        H.setup({ boot = false })
        local inits = 0
        H.SuuUI:CreatePlugin({ id = "lc", name = "LC", onInit = function() inits = inits + 1 end })
        H.SuuUI.Plugins:InitAll()
        expect(inits).eq(1)
    end)

    it("runs onInit exactly once per plugin, however often InitAll is called", function()
        H.setup({ boot = false })
        local inits = 0
        H.SuuUI:CreatePlugin({ id = "lc", name = "LC", onInit = function() inits = inits + 1 end })
        H.SuuUI.Plugins:InitAll()
        H.SuuUI.Plugins:InitAll()
        H.SuuUI.Plugins:InitAll()
        expect(inits).eq(1)
    end)

    it("reports whether a plugin has been initialised", function()
        H.setup({ boot = false })
        H.SuuUI:CreatePlugin({ id = "lc", name = "LC", onInit = function() end })
        expect(H.SuuUI.Plugins:IsInitialised("lc")).falsy()
        H.SuuUI.Plugins:InitAll()
        expect(H.SuuUI.Plugins:IsInitialised("lc")).truthy()
        expect(H.SuuUI.Plugins:IsInitialised("never_registered")).falsy()
    end)

    it("leaves an earlier plugin's schema registration intact across a re-init", function()
        H.setup({ debug = true })
        local reachedEnd = 0
        H.SuuUI:CreatePlugin({
            id = "early", name = "Early",
            onInit = function()
                H.SuuUI.Settings:Register("early", { { key = "v", type = "toggle", default = true } })
                reachedEnd = reachedEnd + 1
            end,
        })
        H.SuuUI.Plugins:InitAll()
        H.SuuUI.Plugins:InitAll()
        expect(reachedEnd).eq(1)
        for _, line in ipairs(H.debugLog()) do
            expect(line:find("onInit error")).as("no swallowed init failure").isNil()
        end
    end)

    it("initialises a plugin that registers after login, without a manual InitAll", function()
        -- An addon whose .toc loads after ours registers here. It must come up exactly
        -- like an early plugin.
        local inited, enabled = false, false
        local plugin = H.SuuUI:CreatePlugin({
            id = "late", name = "Late",
            onInit   = function() inited = true end,
            onEnable = function() enabled = true end,
        })
        expect(inited).as("brought up on registration").truthy()
        expect(enabled).truthy()
        expect(plugin:IsEnabled()).truthy()
        expect(H.SuuUI.Plugins:IsInitialised("late")).truthy()
    end)

    it("respects a stored enabled=false for a plugin that registers after login", function()
        H.SuuUI.Settings:Register("late", { { key = "enabled", type = "toggle", default = true } })
        H.SuuUI.Settings:Set("late", "enabled", false)
        local enabled = false
        local plugin = H.SuuUI:CreatePlugin({
            id = "late", name = "Late",
            onInit   = function() end,
            onEnable = function() enabled = true end,
        })
        expect(plugin:IsEnabled()).falsy()
        expect(enabled).falsy()
    end)

    it("does not re-init existing plugins when a late one registers", function()
        H.setup({ boot = false })
        local earlyInits = 0
        H.SuuUI:CreatePlugin({ id = "early", name = "Early",
                               onInit = function() earlyInits = earlyInits + 1 end })
        H.fireEvent("ADDON_LOADED", "SuuUI")
        H.fireEvent("PLAYER_LOGIN")
        expect(earlyInits).eq(1)

        H.SuuUI:CreatePlugin({ id = "late", name = "Late", onInit = function() end })
        expect(earlyInits).as("the late arrival leaves everyone else alone").eq(1)
    end)

    it("initialises a plugin registered from inside another plugin's onInit", function()
        H.setup({ boot = false })
        local nestedInited = false
        H.SuuUI:CreatePlugin({
            id = "outer", name = "Outer",
            onInit = function()
                H.SuuUI:CreatePlugin({
                    id = "nested", name = "Nested",
                    onInit = function() nestedInited = true end,
                })
            end,
        })
        H.SuuUI.Plugins:InitAll()
        expect(nestedInited).as("the same pass picks up the new registration").truthy()
    end)

    it("keeps onInit before any onEnable during the login pass", function()
        H.setup({ boot = false })
        local log = {}
        H.SuuUI:CreatePlugin({ id = "a", name = "A",
                               onInit = function() log[#log + 1] = "init-a" end,
                               onEnable = function() log[#log + 1] = "enable-a" end })
        H.SuuUI:CreatePlugin({ id = "b", name = "B",
                               onInit = function() log[#log + 1] = "init-b" end,
                               onEnable = function() log[#log + 1] = "enable-b" end })
        H.fireEvent("ADDON_LOADED", "SuuUI")
        H.fireEvent("PLAYER_LOGIN")
        expect(log).deepEq({ "init-a", "init-b", "enable-a", "enable-b" })
    end)

    it("enables and disables, firing the matching events", function()
        -- Registered before the login pass, so it is not auto-enabled on registration.
        H.setup({ boot = false })
        H.fireEvent("ADDON_LOADED", "SuuUI")
        local log = {}
        local plugin = H.SuuUI:CreatePlugin({
            id = "lc", name = "LC",
            onEnable  = function() log[#log + 1] = "enable" end,
            onDisable = function() log[#log + 1] = "disable" end,
        })
        H.SuuUI.Plugins:InitAll()
        local enabled  = H.eventSpy("SUUUI_PLUGIN_ENABLED")
        local disabled = H.eventSpy("SUUUI_PLUGIN_DISABLED")
        plugin:Enable()
        expect(plugin:IsEnabled()).truthy()
        plugin:Disable()
        expect(plugin:IsEnabled()).falsy()
        expect(log).deepEq({ "enable", "disable" })
        expect(enabled.count).eq(1)
        expect(disabled.count).eq(1)
    end)

    it("ignores a redundant Enable or Disable", function()
        H.setup({ boot = false })
        H.fireEvent("ADDON_LOADED", "SuuUI")
        local calls = 0
        local plugin = H.SuuUI:CreatePlugin({
            id = "lc", name = "LC", onEnable = function() calls = calls + 1 end,
        })
        H.SuuUI.Plugins:InitAll()
        plugin:Enable()
        plugin:Enable()
        expect(calls).eq(1)
    end)

    it("survives a throwing onInit without breaking the rest", function()
        H.setup({ boot = false })
        local other = 0
        H.SuuUI:CreatePlugin({ id = "bad", name = "Bad", onInit = function() error("boom") end })
        H.SuuUI:CreatePlugin({ id = "good", name = "Good", onInit = function() other = other + 1 end })
        expect(function() H.SuuUI.Plugins:InitAll() end).notThrows()
        expect(other).as("one bad plugin must not stop the others").eq(1)
    end)

    it("gives a plugin its own namespaced settings store", function()
        H.setup({ boot = false })
        H.fireEvent("ADDON_LOADED", "SuuUI")
        local plugin = H.SuuUI:CreatePlugin({
            id = "ns", name = "NS",
            onInit = function()
                H.SuuUI.Settings:Register("ns", { { key = "v", type = "slider", default = 3 } })
            end,
        })
        H.SuuUI.Plugins:InitAll()
        expect(plugin:GetSettings()).notNil()
        H.SuuUI.Settings:Set("ns", "v", 7)
        expect(H.SuuUI.Profiles:GetActive().plugins["ns"].v).eq(7)
    end)

    it("requires an id and a name", function()
        expect(function() H.SuuUI:CreatePlugin({ name = "No Id" }) end).throws()
        expect(function() H.SuuUI:CreatePlugin({ id = "no_name" }) end).throws()
    end)

    it("refuses a duplicate plugin id", function()
        H.SuuUI:CreatePlugin({ id = "dup", name = "Dup" })
        expect(function() H.SuuUI:CreatePlugin({ id = "dup", name = "Dup2" }) end).throws()
    end)

    it("writes the active profile name on logout", function()
        H.SuuUI.Profiles:Create("Raid")
        H.SuuUI.Profiles:SetActive("Raid")
        H.fireEvent("PLAYER_LOGOUT")
        expect(H.env.SuuUIConfig.activeProfile).eq("Raid")
    end)
end)
