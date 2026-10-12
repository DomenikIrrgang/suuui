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
            { label = "Automatic scale", control = "toggle", combat = true,
              description = "100% up to 1440p, larger on taller screens.",
              get = scaleIsAuto,
              set = function(on) return Settings.Set("ui", "scale", on and 0 or ns.UserScale()) end,
              isDefault = scaleIsAuto,
              reset = function() Settings.Reset("ui", "scale") end },
            { label = "Scale", control = "slider", min = 0.5, max = 2, step = 0.05, live = false, combat = true,
              description = "Every SuuUI frame at once, when you let go of the slider.",
              format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
              get = function() return ns.UserScale() end,
              set = function(v) return Settings.Set("ui", "scale", v) end,
              isDefault = scaleIsAuto,
              reset = function() Settings.Reset("ui", "scale") end,
              disabled = function() return scaleIsAuto(), "Turn automatic scale off first." end },
        } },
        { title = "Layout", rows = {
            { label = "Move frames", control = "button", text = "Edit layout",
              description = "Drag SuuUI's frames on a snap grid. Closes by itself when combat starts.",
              onClick = function()
                  if ns.EditMode.Enter() then ns.SettingsWindow.Toggle() end
              end },
        } },
    },
})

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

Registry.Register({
    id = "motion", label = "Motion", category = "General", order = 20, namespace = "ui",
    groups = {
        { title = "Animations", rows = {
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

-- A Select of other profiles and a button that acts on the chosen one. With
-- `confirm`, the first click arms the button for a few seconds.
local function pickAndAct(parent, label, act, confirm)
    local f = CreateFrame("Frame", nil, parent)
    local choice, timer
    f.select = UI.Select(f, { width = 190, placeholder = "Choose a profile", options = otherProfiles(),
        onChange = function(v) choice = v end })
    f.select:SetPoint("LEFT")
    local function disarm()
        if timer then timer:Cancel(); timer = nil end
        f.button:SetLabel(label)
    end
    -- the list follows profiles switched, created and deleted elsewhere
    local function refresh()
        local options = otherProfiles()
        f.select:SetOptions(options)
        local still = false
        for _, o in ipairs(options) do if o.value == choice then still = true end end
        if not still then
            choice = nil
            f.select:SetValue(nil)
            disarm()
        end
    end
    f.button = UI.Button(f, { text = label, onClick = function(b)
        if not choice then return end
        if confirm and not timer then
            b:SetLabel("Click again")
            timer = C_Timer.NewTimer(3, function() timer = nil; disarm() end)
            return
        end
        disarm()
        local ok, err = act(choice)
        if not ok then ns.Print(err) end
        choice = nil
        f.select:SetValue(nil)
        refresh()
    end })
    f.button:SetPoint("LEFT", f.select, "RIGHT", S["space-3"], 0)
    f:SetSize(190 + S["space-3"] + f.button:GetWidth(), 30)
    ns.Events.On("SUUUI_PROFILE_CHANGED", refresh, f)
    ns.Events.On("SUUUI_PROFILES_CHANGED", refresh, f)
    return f
end

local function newProfile(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.name = UI.TextField(f, { width = 190, placeholder = "Name" })
    f.name:SetPoint("LEFT")
    local function create()
        local name = strtrim(f.name:GetValue() or "")
        local ok, err = Profiles.Create(name)
        if ok then ok, err = Profiles.Use(name) end
        if not ok then ns.Print(err) else f.name:SetValue("") end
    end
    -- Enter in the name field creates it too
    f.name.edit:SetScript("OnEnterPressed", function(e)
        create()
        e:ClearFocus()
    end)
    f.button = UI.Button(f, { text = "Create", onClick = create })
    f.button:SetPoint("LEFT", f.name, "RIGHT", S["space-3"], 0)
    f:SetSize(190 + S["space-3"] + f.button:GetWidth(), 30)
    return f
end

-- One role's profile: "Don't switch" or a profile.
local function roleRow(role, label)
    return { label = label, control = "select", width = 220,
        options = function()
            local options = { { value = "none", label = "Don't switch" } }
            for _, o in ipairs(allProfiles()) do options[#options + 1] = o end
            return options
        end,
        description = ("When you're a %s, use this profile."):format(ns.Roles.LABEL[role]),
        get = function() return Profiles.RoleProfile(role) or "none" end,
        set = function(v) return Profiles.SetRoleProfile(role, v ~= "none" and v or nil) end }
end

local function resetAll(parent)
    local timer
    local b = UI.Button(parent, { text = "Reset everything", onClick = function(self)
        if not timer then
            self:SetLabel("Click again to reset")
            timer = C_Timer.NewTimer(3, function() timer = nil; self:SetLabel("Reset everything") end)
            return
        end
        timer:Cancel()
        timer = nil
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
        { title = "By role", description = "SuuUI can switch profiles with your role: set up a profile for each, and everything follows when you change spec or get a role in a group, out of combat.", rows = {
            { label = "Your role", control = "select", width = 220,
              options = function()
                  local now = ns.Roles.LABEL[(select(1, ns.Roles.Current()))]
                  local auto = Profiles.ChosenRole() == "auto" and (" (now " .. now .. ")") or ""
                  return { { value = "auto", label = "Automatic" .. auto },
                           { value = "TANK", label = "Tank" }, { value = "HEALER", label = "Healer" }, { value = "DAMAGER", label = "DPS" } }
              end,
              description = "Automatic: the role a group gives you (role check, group finder), else the talent tree with the most points. A profile you pick by hand stays until your role changes.",
              get = function() return Profiles.ChosenRole() end,
              set = function(v) return Profiles.SetChosenRole(v) end },
            roleRow("TANK", "Tank profile"),
            roleRow("HEALER", "Healer profile"),
            roleRow("DAMAGER", "DPS profile"),
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
            local retry = m.state == "errored" and m.reloadToToggle and Settings.Get(m.id, "enabled")
            if m.pendingReload and not retry then state = state .. ", " .. (m.enabledAtLoad and "off" or "on") .. " after a reload" end
            if retry then
                state = state .. ": " .. (m.error or "") .. ". It tries again after a reload"
            elseif m.state == "errored" then
                state = state .. ": " .. (m.error or "") .. ". Turn it off and on to try again"
            end
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
