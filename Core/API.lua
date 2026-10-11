-- Core/API.lua
-- The public API: the global SuuUI. Built-in modules and plugin addons use
-- only what is published here (documented in Docs/API.md). Anything a module
-- needs from the core is added here, never reached for in the private
-- namespace. Loads after the rest of Core.

local _, ns = ...

local API = ns.API
local Modules = ns.Modules

API.API_VERSION = ns.API_VERSION
API.version = ns.version

-- Modules
API.RegisterModule = Modules.Register
API.APIAtLeast = Modules.APIAtLeast

function API.GetModule(id)
    return Modules.Get(id)
end

-- A snapshot of every module: { id, name, description, state, source, builtIn, error }.
function API.ListModules()
    local out = {}
    for _, m in ipairs(Modules.All()) do
        out[#out + 1] = {
            id = m.id, name = m.name, description = m.description, state = m.state,
            source = m.source, builtIn = m.builtIn, error = m.error, pendingReload = m.pendingReload,
        }
    end
    return out
end

-- Design tokens (read only: never change them) and text styles
API.Tokens = ns.Tokens
API.Fonts = {
    Get = ns.Fonts.Get,
    Apply = ns.Fonts.Apply,
}

-- Physical pixels
API.Pixel = {
    Size = ns.Pixel.Size,
    Snap = ns.Pixel.Snap,
    PerfectScale = ns.Pixel.PerfectScale,
}

-- Blizzard frames
API.SuppressBlizzard = ns.SuppressBlizzard
API.RestoreBlizzard = ns.RestoreBlizzard

-- 0.2: the screen root, components, layouts and motion

-- Every SuuUI frame on the screen lives under SuuUI.Root. One unit there is
-- one design pixel (a physical pixel times ui.scale), so design sizes and
-- offsets from the screen's edges or centre are used as they are.
API.Root = ns.Root

local UI = ns.UI
API.UI = {
    -- components
    Panel = UI.Panel,
    SectionHeader = UI.SectionHeader,
    WindowFrame = UI.WindowFrame,
    Button = UI.Button,
    CloseButton = UI.CloseButton,
    KeyChip = UI.KeyChip,
    StateBadge = UI.StateBadge,
    Icon = UI.Icon,
    StatusBar = UI.StatusBar,
    Text = UI.Text,
    -- the tooltip
    ShowTooltip = UI.ShowTooltip,
    HideTooltip = UI.HideTooltip,
    AttachTooltip = UI.AttachTooltip,
    TooltipFrame = UI.TooltipFrame,
    -- drawing
    Fill = UI.Fill,
    Border = UI.Border,
    Hairline = UI.Hairline,
    Diamond = UI.Diamond,
    Shadow = UI.Shadow,
    SoftEdge = UI.SoftEdge,
    Cross = UI.Cross,
    RGBA = UI.RGBA,
    Size = UI.Size,
}

API.Layout = {
    Stack = ns.Layout.Stack,
    Grid = ns.Layout.Grid,
}

API.Motion = {
    FadeIn = ns.Motion.FadeIn,
    Enter = ns.Motion.Enter,
    Pop = ns.Motion.Pop,
    Stop = ns.Motion.Stop,
}

-- 0.3: settings controls and the settings window

API.UI.Toggle = UI.Toggle
API.UI.Checkbox = UI.Checkbox
API.UI.Segmented = UI.Segmented
API.UI.Select = UI.Select
API.UI.Slider = UI.Slider
API.UI.Stepper = UI.Stepper
API.UI.TextField = UI.TextField
API.UI.SettingRow = UI.SettingRow
API.UI.SettingsGroup = UI.SettingsGroup

-- A settings section that is always there (a module uses module:RegisterSettings,
-- whose section goes away with the module). See SettingsUI/Registry.lua.
function API.RegisterSettings(def)
    return ns.SettingsRegistry.Register(def)
end

-- Opens the settings window, at a section if given.
function API.OpenSettings(sectionId)
    ns.SettingsWindow.Open(sectionId)
end

-- 0.4: edit mode

-- An edit-mode handle for a frame whose position lives in a settings table
-- (opts.namespace, opts.key); modules use module:RegisterMover instead.
function API.RegisterMover(frame, opts)
    return ns.EditMode.Register(frame, opts)
end

API.EditMode = {
    Enter = ns.EditMode.Enter,
    Exit = ns.EditMode.Exit,
    Toggle = ns.EditMode.Toggle,
    IsActive = ns.EditMode.IsActive,
}
