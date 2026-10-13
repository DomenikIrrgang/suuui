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

-- 0.9: your role ("TANK", "HEALER", "DAMAGER") and where it came from
-- ("chosen", "assigned", "talents"); your spec (talent tree 1-3, 0 unspecced)
function API.Role() return ns.Roles.Current() end
function API.Spec() return ns.Roles.Spec() end
-- Blizzard frames
API.SuppressBlizzard = ns.SuppressBlizzard
API.RestoreBlizzard = ns.RestoreBlizzard
API.IsSuppressed = ns.IsSuppressed

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
-- 0.10: opens the settings window, or closes it while it's open
function API.ToggleSettings()
    ns.SettingsWindow.Toggle()
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
    Refresh = ns.EditMode.Refresh, -- 0.8: re-reads each mover's `enabled`
    Rect = ns.EditMode.Rect,           -- 0.8: a frame's rectangle in root units
    AnchorFor = ns.EditMode.AnchorFor, -- 0.8: the screen anchor for a rectangle
}

-- 0.5: unit frames

API.UI.UnitFrame = UI.UnitFrame
API.UI.AnchorPicker = UI.AnchorPicker -- 0.9: the 3×3 point grid (no offsets)
API.UI.SwatchRow = UI.SwatchRow       -- 0.9: token colour swatches
API.UI.ToggleChips = UI.ToggleChips   -- 0.9: on/off chips for choices that combine
API.UI.INDICATOR_POINTS = UI.INDICATOR_POINTS -- 0.9: where an indicator can sit on a unit frame
API.UI.GroupIndicators = UI.GroupIndicators   -- 0.9: the buff indicators group frames show, and a version
API.UI.GROUP_TIERS = UI.GROUP_TIERS           -- 0.9: "5", "10", "20", "40"
API.UI.GroupTier = UI.GroupTier               -- 0.9: the current group's size tier (or for a count)
API.UI.IndicatorsFor = UI.IndicatorsFor       -- 0.9: the indicators of a list active at a tier
API.UI.SetGroupIndicators = UI.SetGroupIndicators -- 0.9: set them (the Buff indicators module); emits SUUUI_INDICATORS_CHANGED
API.UI.UnitStandIn = UI.UnitStandIn -- 0.9: Unit* stand-ins for previews: UnitStandIn(person) -> api for UnitFrame opts.api
API.UI.RaidMarker = UI.RaidMarker -- 0.9: RaidMarker(parent, size[, layer]) -> a hidden raid target marker texture
API.UI.ShowRaidMarker = UI.ShowRaidMarker -- 0.9: ShowRaidMarker(texture, unit[, api]): that unit's marker, or hidden
API.UI.DEBUFF_TYPES = UI.DEBUFF_TYPES -- 0.9: { "Magic", "Curse", "Poison", "Disease" }, drawn top first
API.UI.UnitFrameCurveValue = UI.UnitFrameCurveValue -- 0.9: what a unit frame curve gives for a 0-1 fraction (preview stand-ins)
API.UI.Flag = UI.Flag               -- a possibly secret boolean as a plain one (secret reads as false)
API.UI.MeasureText = UI.MeasureText -- text width, safe where anchors make geometry secret
API.Motion.AlphaTo = ns.Motion.AlphaTo

-- 0.6: anchors and cast bars

-- Modules publish their frames under a name (player, target, targettarget,
-- focus, pet, boss1 ... boss5); others attach to them. Message:
-- SUUUI_ANCHOR_CHANGED (name, frame).
API.PublishAnchor = ns.Anchors.Publish
API.GetAnchor = ns.Anchors.Get

API.UI.CastBar = UI.CastBar
API.UI.SwingTimer = UI.SwingTimer

-- 0.7: auras (engine aura containers, styled as the design's AuraIcon)
API.UI.AuraContainer = UI.AuraContainer

-- 0.8: action bars (SuuUI's own secure buttons; see UI/ActionBar.lua)
API.UI.ActionButton = UI.ActionButton
API.UI.ActionBar = UI.ActionBar
API.UI.ActionBarPaging = UI.ActionBarPaging -- bar 1's paging conditions on Forever
API.UI.ShortKey = UI.ShortKey               -- "SHIFT-1" -> "S1"
API.UI.StanceBar = UI.StanceBar
API.UI.CooldownTracker = UI.CooldownTracker
API.UI.TrackerSound = UI.TrackerSound -- "chime", "ping", "proc", "warning" or a sound kit ID
API.UI.MakeModal = UI.MakeModal -- a panel centred over a dimmed screen
API.UI.ScrollArea = UI.ScrollArea -- 0.9: ScrollArea(parent[, bar]) -> a mouse-wheel scroll frame, content in .child, a thin bar `bar` px right of it while it overflows
API.UI.Confirm = UI.Confirm     -- { title, text, confirm, cancel, onConfirm, onCancel }
-- The Cooldown Manager presets of your class (only your class's data loads):
-- { { id, name, lists = { essential, utility, buffs, debuffs, procs } }, ... },
-- each entry { name, ids = { every ID with that name in the client }, mine }.
function API.CooldownPresets() return ns.CooldownPresets or {} end
-- 0.9: every talent of a class (all nine classes', generated from the class
-- data): { { id = spellID, name, tree = 1-3 }, ... }, nil for an unknown class
function API.ClassTalents(class) return ns.ClassTalents and ns.ClassTalents[class] end
-- 0.9: every aura any class's presets track: { [name] = { classes = "Priest",
-- ids = { ... } } } (Data/AuraCatalog.lua, generated)
function API.AuraCatalog() return ns.AuraCatalog or {} end
API.UI.SetActionTextSize = UI.SetActionTextSize -- px, never below micro (9.5)
API.UI.SetVisibility = UI.SetVisibility -- "always" | "combat" | "mouseover" | "hidden"
API.UI.VISIBILITY_OPTIONS = UI.VISIBILITY_OPTIONS -- 0.9: the {value,label} choices "always","combat","mouseover"

-- Keybind mode: hover a button, press a key. Message: SUUUI_KEYBINDMODE_CHANGED (active).
API.KeybindMode = {
    Enter = ns.KeybindMode.Enter,
    Exit = ns.KeybindMode.Exit,
    Toggle = ns.KeybindMode.Toggle,
    IsActive = ns.KeybindMode.IsActive,
}
API.UI.PetBar = UI.PetBar

-- 0.10: alerts, the threat meter

API.UI.Alert = UI.Alert             -- Alert(parent) -> a:SetAlert(tone, title, detail[, ...])
API.UI.ThreatMeter = UI.ThreatMeter -- ThreatMeter(parent, { rows }) -> m:SetTarget(name), m:SetRows(list, opts), m:SetMaxRows(n)
API.UI.DamageMeter = UI.DamageMeter -- DamageMeter(parent, opts): one window on C_DamageMeter (see UI/DamageMeter.lua)
API.UI.EncounterTimeline = UI.EncounterTimeline -- EncounterTimeline(parent, { variant, window, soonAt }) -> t:SetEvents(list), t:SetVariant(v), t:SetMeta(text)
API.UI.Readiness = UI.Readiness -- Readiness(parent, { onReadyCheck }) -> r:SetRows(list), r:SetActionShown(on)
API.UI.MicroMenu = UI.MicroMenu -- MicroMenu(parent, { name }) -> m:SetItems({ { key, glyph, label, click | onClick } }), m:SetAlert(key, text)
API.UI.DAMAGE_METER_TYPES = UI.DAMAGE_METER_TYPES -- the type select's options, Blizzard's order

-- 0.11: the objective tracker
API.UI.ObjectiveTracker = UI.ObjectiveTracker -- ObjectiveTracker(parent, { width, maxHeight, toggle }) -> t:SetQuests(list, freeze), t:SetCollapsed(on), t:SetMeta(text), t:QuestTop(questID)
API.UI.TRACKER_HEAD_H = UI.TRACKER_HEAD_H -- the tracker head's height (its toggle's size)
-- 0.11: notifications
API.UI.Notification = UI.Notification -- Notification(parent) -> n:SetData(d), n:SetRemaining(s), n:SetTitle(text)
API.UI.NotificationStack = UI.NotificationStack -- NotificationStack(parent, { max }) -> s:SetItems(list, inCombat), s:CardFor(id)
-- 0.11: bags
API.UI.SkinItemSlot = UI.SkinItemSlot -- SkinItemSlot(button) -> skin:SetItem({ icon, count, quality, dim, locked } or nil)
API.UI.ItemSlot = UI.ItemSlot   -- ItemSlot(parent[, size]) -> a plain slot (b.skin)
API.UI.Money = UI.Money         -- Money(parent) -> m:SetCopper(n)
API.UI.Inventory = UI.Inventory -- Inventory(parent, { title, columns, name, sortTip, characters }) -> inv:LayoutSlots(buttons), inv:SetMeta(t), inv:SetNote(t), inv:SetMoney(c); inv.search, inv.sort, inv.grid, inv.onClose
API.UI.LootWindow = UI.LootWindow -- LootWindow(parent, { name }) -> lw:SetSource(t), lw:SetItems(list), lw:FirstSlotOffset(); lw.onClick, lw.onEnter, lw.onLeave, lw.onClose
API.UI.SkinTooltip = UI.SkinTooltip -- SkinTooltip(tooltip): SuuUI's art on one of Blizzard's tooltips (its NineSlice hidden)
API.UI.Campsite = UI.Campsite -- Campsite(parent) -> c:SetData({ phase, remaining, progress, benefits, cooldowns }), c:SetTimes(remaining, progress, cooldownTimes)
-- A note in the notification stack (the Notifications module; nothing while
-- it's off): { id?, kind = "timed"|"sticky"|"until", category, title, body,
-- icon = { glyph | texture }, tone, duration, ["until"], actions } -> id
function API.Notify(def)
    local m = Modules.Get("notifications")
    if m and m:IsEnabled() then return m:Notify(def) end
end
function API.DismissNotification(id)
    local m = Modules.Get("notifications")
    if m and m:IsEnabled() then m:Dismiss(id) end
end
-- One alert at a time, centred, in combat only (the Alerts module; nothing
-- while it's off). The same key updates its alert in place; HideAlert(key)
-- takes it away. detail: text, or a format whose arguments may be secret.
function API.ShowAlert(key, tone, title, detail, ...)
    local m = Modules.Get("alerts")
    if m and m:IsEnabled() then m:Show(key, tone, title, detail, ...) end
end
-- A key whose alerts may also show out of combat (a pull countdown).
function API.AllowAlertOutOfCombat(key)
    local m = Modules.Get("alerts")
    if m then m:AllowOutOfCombat(key) end
end
function API.HideAlert(key)
    local m = Modules.Get("alerts")
    if m and m:IsEnabled() then m:Hide(key) end
end
