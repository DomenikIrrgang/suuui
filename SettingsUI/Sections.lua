-- SettingsUI/Sections.lua
-- The General sections SuuUI owns itself: Appearance, Motion, Profiles and
-- Modules. Module sections are registered by their modules.

local _, ns = ...

local UI, T, Settings, Profiles, Registry, Modules = ns.UI, ns.Tokens, ns.Settings, ns.Profiles, ns.SettingsRegistry, ns.Modules
local S = T.space

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

local function scaleIsAuto() return Settings.Get("ui", "scale") == 0 end

Registry.Register({
    id = "appearance", label = "Appearance", category = "General", order = 10, namespace = "ui",
    groups = {
        { title = "Scale", description = "SuuUI draws one design pixel as one pixel of your screen, so frames keep their size on every resolution and only the space between them changes.",
          rows = {
            { label = "Automatic scale", control = "toggle",
              description = "1 up to 1440p, larger on taller screens.",
              get = scaleIsAuto,
              set = function(on) return Settings.Set("ui", "scale", on and 0 or ns.UserScale()) end,
              isDefault = scaleIsAuto,
              reset = function() Settings.Reset("ui", "scale") end },
            { label = "Scale", control = "slider", min = 0.5, max = 2, step = 0.05, live = false,
              description = "Every SuuUI frame at once, when you let go of the slider. Waits for the end of combat.",
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
              get = function() return ns.UserScale() end,
              set = function(v) return Settings.Set("ui", "scale", v) end,
              isDefault = scaleIsAuto,
              reset = function() Settings.Reset("ui", "scale") end,
              disabled = function() return scaleIsAuto(), "Turn automatic scale off first." end },
        } },
    },
})

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

Registry.Register({
    id = "motion", label = "Motion", category = "General", order = 20, namespace = "ui",
    groups = {
        { title = "Motion", rows = {
            { key = "reducedMotion", label = "Reduce motion", control = "toggle",
              description = "Drops decorative motion: fades, pops and slides. Every value still updates at once." },
        } },
    },
})

--------------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------------

local function otherProfiles()
    local options = {}
    for _, name in ipairs(Profiles.List()) do
        if name ~= Profiles.Current() then options[#options + 1] = { value = name, label = name } end
    end
    return options
end

local function allProfiles()
    local options = {}
    for _, name in ipairs(Profiles.List()) do options[#options + 1] = { value = name, label = name } end
    return options
end

-- A Select of other profiles and a button that acts on the chosen one.
local function pickAndAct(parent, label, act, confirm)
    local f = CreateFrame("Frame", nil, parent)
    local choice
    f.select = UI.Select(f, { width = 190, placeholder = "Choose a profile", options = otherProfiles(),
        onChange = function(v) choice = v end })
    f.select:SetPoint("LEFT")
    local armed
    f.button = UI.Button(f, { text = label, onClick = function(b)
        if not choice then return end
        if confirm and not armed then
            armed = true
            b:SetLabel("Click again")
            C_Timer.After(3, function() armed = false; b:SetLabel(label) end)
            return
        end
        armed = false
        b:SetLabel(label)
        local ok, err = act(choice)
        if not ok then ns.Print(err) end
        choice = nil
        f.select:SetOptions(otherProfiles())
        f.select:SetValue(nil)
    end })
    f.button:SetPoint("LEFT", f.select, "RIGHT", S["space-3"], 0)
    f:SetSize(190 + S["space-3"] + f.button:GetWidth(), 30)
    ns.Events.On("SUUUI_PROFILE_CHANGED", function() f.select:SetOptions(otherProfiles()) end, f)
    return f
end

local function newProfile(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.name = UI.TextField(f, { width = 190, placeholder = "Name" })
    f.name:SetPoint("LEFT")
    f.button = UI.Button(f, { text = "Create", onClick = function()
        local name = strtrim(f.name:GetValue() or "")
        local ok, err = Profiles.Create(name)
        if ok then ok, err = Profiles.Use(name) end
        if not ok then ns.Print(err) else f.name:SetValue("") end
    end })
    f.button:SetPoint("LEFT", f.name, "RIGHT", S["space-3"], 0)
    f:SetSize(190 + S["space-3"] + f.button:GetWidth(), 30)
    return f
end

local function resetAll(parent)
    local armed
    local b = UI.Button(parent, { text = "Reset everything", onClick = function(self)
        if not armed then
            armed = true
            self:SetLabel("Click again to reset")
            C_Timer.After(3, function() armed = false; self:SetLabel("Reset everything") end)
            return
        end
        armed = false
        self:SetLabel("Reset everything")
        Settings.Reset()
        ns.Print("Every setting in " .. Profiles.Current() .. " is back to its default.")
    end })
    return b
end

Registry.Register({
    id = "profiles", label = "Profiles", category = "General", order = 40,
    groups = {
        { title = "This character", rows = {
            { label = "Profile", control = "select", width = 220, options = allProfiles,
              description = "Each character uses its own profile unless you pick another.",
              get = function() return Profiles.Current() end,
              set = function(name) return Profiles.Use(name) end },
            { label = "New profile", control = "custom", build = newProfile,
              description = "Starts as a copy of the profile you use now, and switches to it." },
            { label = "Copy settings from", control = "custom",
              build = function(p) return pickAndAct(p, "Copy", Profiles.CopyFrom, true) end,
              description = "Replaces this profile's settings with another profile's." },
            { label = "Delete a profile", control = "custom",
              build = function(p) return pickAndAct(p, "Delete", Profiles.Delete, true) end,
              description = "Characters using it go back to their own profile." },
        } },
        { title = "Share", rows = {
            { label = "Export", control = "button", text = "Export profile", onClick = function() ns.SettingsWindow.Export() end,
              description = "A text string with this profile's settings, to paste on another character or share." },
            { label = "Import", control = "button", text = "Import profile", onClick = function() ns.SettingsWindow.Import() end,
              description = "Paste a profile string; it becomes a new profile." },
        } },
        { title = "Start over", rows = {
            { label = "Reset every setting", control = "custom", build = resetAll,
              description = "Puts every setting in this profile back to its default." },
        } },
    },
})

--------------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------------

local STATE = {
    enabled = "On", disabled = "Off", errored = "Errored", incompatible = "Can't load", registered = "Waiting for login",
}

local function moduleRow(m)
    return {
        label = m.name, control = "toggle", namespace = m.id, key = "enabled",
        description = function()
            local parts = { m.description, m.builtIn and "Built in" or ("From " .. m.source) }
            local state = STATE[m.state] or m.state
            if m.pendingReload then state = state .. ", " .. (m.enabledAtLoad and "off" or "on") .. " after a reload" end
            if m.state == "errored" then state = state .. ": " .. (m.error or "") .. ". Turn it off and on to try again" end
            parts[#parts + 1] = state
            local out = {}
            for _, p in ipairs(parts) do if p and p ~= "" then out[#out + 1] = p end end
            return table.concat(out, " · ")
        end,
        disabled = function()
            if m.state == "incompatible" then return true, m.name .. " " .. (m.error or "can't load") .. "." end
            return false
        end,
    }
end

local function buildModules(page)
    page:Clear()
    local builtIn, plugins = {}, {}
    for _, m in ipairs(Modules.All()) do
        table.insert(m.builtIn and builtIn or plugins, moduleRow(m))
    end
    page:AddGroup({ title = "Built in", description = "A module that is off is never loaded: no frames, no events, and Blizzard's own frame stays.", rows = builtIn })
    if #plugins > 0 then
        page:AddGroup({ title = "Plugins", description = "Addons that extend SuuUI. Each one can be turned off here without touching the others.", rows = plugins })
    end
    page:AddGroup({ title = "Developer", rows = {
        { label = "Debug lines in chat", control = "toggle", namespace = "core", key = "debug",
          description = "SuuUI's own debug output. Leave it off unless you are tracking a problem down." },
    } })
    page:Refresh()
end

Registry.Register({
    id = "modules", label = "Modules", category = "General", order = 50,
    build = function(page)
        buildModules(page)
        ns.Events.On("SUUUI_MODULE_REGISTERED", function() buildModules(page) end, page)
    end,
})
