-- Addon Buttons plugin: takes the addon buttons off the minimap ring and puts them in a data
-- bar field whose hover panel is the roster.
--
-- Like Plugins/Performance, this contributes a widget to a bar it does not own and holds no
-- reference to the data_bar plugin, its frame or its load order. What it does own is the
-- borrowed frames: every button it adopts is handed back in onDisable, which is why the
-- collector keeps SetParent and SetPoint intact instead of replacing them with no-ops.
local ipairs, type = ipairs, type

local PLUGIN_ID = "addon_buttons"
local OWNER     = "addon_buttons"

local events
local warned

local function Collector()
    return SuuUI._AddonButtons.Collector
end

local function Widget()
    return SuuUI._AddonButtons.TrayWidget
end

-- Said once per session, and only when the conflict is real. Two collectors reparenting one
-- button take it in turns, so this feature stands down rather than fighting -- the collector
-- refuses to collect while MBB is loaded, and the field reads "—" until one of them is off.
local function warnAboutRival()
    if warned then return end
    local C = Collector()
    if not C or not C.RivalLoaded() then return end
    warned = true
    SuuUI.Components.Notice({
        title   = "Addon Buttons conflict",
        message = C.RIVAL_ADDON .. " is loaded and collects the same minimap buttons.\n\n"
               .. "Disable one of the two: either turn off " .. C.RIVAL_ADDON
               .. ", or switch off Show Addon Buttons on this page. SuuUI has left the "
               .. "buttons alone for now.",
        tone    = "warning",
    })
end

-- A sweep a moment later. Not every minimap button announces itself: a hand-rolled one is just
-- a frame somebody parented to the minimap, with no event and no callback behind it, and plenty
-- of addons build theirs a beat after the login pass. MBB does the same thing for the same
-- reason. Cheap, because an already-held button is skipped.
local function sweepSoon(delay)
    local timer = _G.C_Timer
    if not (timer and type(timer.After) == "function") then return end
    pcall(timer.After, delay, function()
        local C, W = Collector(), Widget()
        if C then C.Collect() end
        if W then W.Refresh() end
    end)
end

local function onEvent(_, event)
    local C, W = Collector(), Widget()
    if not C then return end

    if event == "PLAYER_ENTERING_WORLD" then
        C.Collect()
        warnAboutRival()
        -- LibDBIcon builds anything registered before PLAYER_LOGIN only afterwards, and its
        -- callback covers those. These two catch the buttons that announce nothing at all.
        sweepSoon(1)
        sweepSoon(5)
    elseif event == "ADDON_LOADED" then
        -- An addon that just finished loading is the likeliest moment for a new button.
        C.Collect()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- A button built from a secure template cannot be reparented in combat and the client
        -- refuses silently, so collection is deferred to here rather than attempted and lost.
        C.Collect()
    end

    if W then W.Refresh() end
end

local plugin = SuuUI:CreatePlugin({
    id      = "addon_buttons",
    name    = "Addon Buttons",
    version = "0.1",

    onInit = function(p)
        local schema = {
            { key = "enabled", label = "Enable Addon Buttons", type = "toggle", default = true },
        }
        for _, entry in ipairs(Widget().Schema()) do
            schema[#schema + 1] = entry
        end
        SuuUI.Settings:Register(PLUGIN_ID, schema)

        -- No `immediate`: Plugins:autoEnable applies the stored value during the login pass,
        -- and an immediate callback would run onEnable from inside the init pass.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")
    end,

    onEnable = function()
        local C, W = Collector(), Widget()
        W.Enable()

        -- A held button that moves, shows or hides itself changes the roster, and the panel
        -- may be open while it happens.
        C.SetChangeCallback(function() W.Refresh() end)

        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", onEvent)
        end
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("ADDON_LOADED")

        -- The library announces each button as it is created, which is what makes the count
        -- correct within a frame of the button existing rather than at the next sweep.
        C.Watch()
        C.Collect()
        warnAboutRival()
        sweepSoon(1)
    end,

    onDisable = function()
        local C, W = Collector(), Widget()
        if events then
            -- Our own frame, so UnregisterAllEvents is the right call: the one-way-door
            -- objection applies to Blizzard's frames, whose registrations nothing can read.
            events:UnregisterAllEvents()
        end
        C.SetChangeCallback(nil)
        C.Unwatch()
        W.Disable()
        -- The ring gets its buttons back. Not optional and not only a path to a reload: a
        -- Disable from a settings watcher runs with nothing behind it, and a button left
        -- parented into a destroyed panel is invisible for the rest of the session.
        C.Restore()
    end,
})

SuuUI._AddonButtons.plugin = plugin
