-- Minimap button: opens the settings window, and enters edit mode on a right click.
--
-- Its own plugin rather than a few lines inside SettingsWindow.lua, because a launcher is
-- not part of the settings window -- it is one way IN to it, and the window should not own
-- something that outlives it on screen. It also means the button has its own settings page
-- and can be switched off without touching anything else.
--
-- The button itself is LibDBIcon's, not ours, and that is the whole point. A hand-rolled
-- icon glued to the minimap corner is invisible to every button collector the player already
-- runs (ElvUI's button bar, MBB, SexyMap) and cannot be dragged around the ring or hidden by
-- them. Registering a LibDataBroker launcher gets that interop for free, and additionally
-- makes SuuUI appear in any LDB display (Titan Panel, Bazooka, ChocolateBar). Stock ring art
-- is deliberate: a themed button would stop looking like the addon button players expect.
local type = type

local PLUGIN_ID = "minimap_button"
local OWNER     = "minimap_button"

-- The name LibDBIcon and every collector addon will know this button by. Not the plugin id:
-- this string is shown to the player by other addons' UIs, so it is the addon's name.
local ICON_NAME = "SuuUI"

-- Our own mark, rendered by Media/generate_logo.py. A texture path is an asset reference
-- rather than a design decision, so it is a literal and not a token. TGA because the client
-- takes uncompressed TGA and 64x64 because texture dimensions must be a power of two.
local ICON_TEXTURE = "Interface\\AddOns\\SuuUI\\Media\\logo.tga"

local dataObject, registered

--- The LibDBIcon position/visibility store. It lives in the plugin's own profile table
--- rather than behind Settings:Get because LibDBIcon MUTATES IT IN PLACE while the player
--- drags the button (`self.db.minimapPos = pos` on every tick of the drag). A value handed
--- out by Settings:Get would be written straight past the store -- and Settings:Set on a
--- table mutated in place is a no-op, because the equality check compares it against
--- itself. plugin:GetProfile() is the sanctioned route for exactly this: plugin-private
--- data that something else owns the shape of. Being a profile sub-table, it is
--- profile-aware and reaches SavedVariables on logout without a write path of our own.
local function iconDB(p)
    local profile = p:GetProfile()
    profile.icon = profile.icon or {}
    return profile.icon
end

local function libIcon()
    if type(_G.LibStub) ~= "table" then return nil end
    local ok, lib = pcall(_G.LibStub, "LibDBIcon-1.0", true)
    return ok and lib or nil
end

local function buildDataObject()
    if dataObject then return dataObject end
    if type(_G.LibStub) ~= "table" then return nil end
    local ok, ldb = pcall(_G.LibStub, "LibDataBroker-1.1", true)
    if not ok or not ldb then return nil end

    dataObject = ldb:NewDataObject(ICON_NAME, {
        type = "launcher",
        icon = ICON_TEXTURE,

        OnClick = function(_, button)
            if button == "RightButton" then
                SuuUI.ToggleUI:Toggle()
            else
                SuuUI.SettingsWindow.Toggle()
            end
        end,

        -- LibDBIcon hands over its own tooltip, already owned and cleared. Colours come from
        -- the theme so the hint lines follow a retint like every other muted label.
        OnTooltipShow = function(tooltip)
            if not tooltip or not tooltip.AddLine then return end
            local T = SuuUI.Theme
            local muted = T:GetToken("colorTextMuted") or { 0.5, 0.5, 0.5, 1 }
            local text  = T:GetToken("colorText") or { 1, 1, 1, 1 }
            tooltip:AddLine("SuuUI", text[1], text[2], text[3])
            tooltip:AddLine("Left-click: settings", muted[1], muted[2], muted[3])
            tooltip:AddLine("Right-click: edit mode", muted[1], muted[2], muted[3])
        end,
    })
    return dataObject
end

local plugin = SuuUI:CreatePlugin({
    id      = "minimap_button",
    name    = "Minimap Button",
    version = "0.1",

    onInit = function(p)
        SuuUI.Settings:Register(PLUGIN_ID, {
            { key = "enabled", label = "Show Minimap Button", type = "toggle", default = true },
            { key = "locked",  label = "Lock Position",       type = "toggle", default = false },
        })

        -- No `immediate`: Plugins:autoEnable applies the stored value during the login pass,
        -- and an immediate callback would run onEnable from inside the init pass.
        SuuUI.Settings:Watch(PLUGIN_ID, "enabled", function(on)
            if on then p:Enable() else p:Disable() end
        end, OWNER .. ".enabled")

        SuuUI.Settings:Watch(PLUGIN_ID, "locked", function(locked)
            local lib = libIcon()
            if not lib or not lib:IsRegistered(ICON_NAME) then return end
            if locked then lib:Lock(ICON_NAME) else lib:Unlock(ICON_NAME) end
        end, OWNER .. ".locked", { immediate = true })
    end,

    onEnable = function(p)
        local lib = libIcon()
        local obj = buildDataObject()
        if not lib or not obj then
            SuuUI.Debug("minimap_button: LibDBIcon-1.0 unavailable, no button created")
            return
        end

        local db = iconDB(p)
        -- Visibility has ONE source of truth, the `enabled` setting. LibDBIcon keeps its own
        -- `hide` mirror and reads it at register time, so it is seeded from the setting here
        -- rather than persisted independently -- two stored copies of one fact drift.
        db.hide   = false
        db.lock   = SuuUI.Settings:Get(PLUGIN_ID, "locked") and true or false

        if not registered then
            lib:Register(ICON_NAME, obj, db)
            registered = true
        end
        lib:Show(ICON_NAME)
    end,

    onDisable = function()
        local lib = libIcon()
        if not lib or not lib:IsRegistered(ICON_NAME) then return end
        -- LibDBIcon exposes no unregister, so Hide IS the teardown. The button object stays
        -- alive and re-Shows on the next enable, which is why `registered` is not cleared.
        lib:Hide(ICON_NAME)
    end,
})

SuuUI._MinimapButton = {
    ICON_NAME = ICON_NAME,
    plugin    = plugin,
    --- The live LibDBIcon button, or nil before it is created. Specs assert against this.
    GetButton = function()
        local lib = libIcon()
        return lib and lib:GetMinimapButton(ICON_NAME) or nil
    end,
}
