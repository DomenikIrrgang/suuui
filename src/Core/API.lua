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
API.UI.Confirm = UI.Confirm     -- { title, text, confirm, cancel, onConfirm, onCancel, typeToConfirm }
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
-- 0.12: SuuUI's Talents window (the talents module): open or close it, and
-- whether it is open. False when that module is off.
function API.ToggleTalents()
    local m = Modules.Get("talents")
    if m and m:IsEnabled() and m.Toggle then m:Toggle(); return true end
    return false
end
-- 0.13: a recipe opened: in SuuUI's Professions window (the professions
-- module, which then selects it), else the game's own window.
function API.OpenRecipe(recipeID)
    local m = Modules.Get("professions")
    if m and m:IsEnabled() and m.OpenRecipe then return m:OpenRecipe(recipeID) end
    -- C_TradeSkillUI.OpenRecipe is protected (blocked from an addon): the
    -- recipe's profession opened instead
    local line, _, parent = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe
        and C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
    local skillLine = (parent and parent ~= 0) and parent or line
    if skillLine and C_TradeSkillUI.OpenTradeSkill then pcall(C_TradeSkillUI.OpenTradeSkill, skillLine) end
end
-- 0.13: the spell that opens a profession's window (Smelting for Mining,
-- Tanning for Skinning's camp recipes), by its skill line; nil if you
-- don't have it. Opening a profession from an addon is protected: cast
-- this from a secure button instead.
function API.ProfessionOpener(skillLine)
    if not (GetProfessions and C_SpellBook and C_TradeSkillUI) then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for _, index in pairs({ GetProfessions() }) do
        local _, _, _, _, numSpells, offset, line = GetProfessionInfo(index)
        if line == skillLine then
            for k = 1, (numSpells or 0) do
                local info = C_SpellBook.GetSpellBookItemInfo((offset or 0) + k, bank)
                if info and info.spellID and not info.isPassive
                    and C_TradeSkillUI.CanTradeSkillShowCraftingUI(info.spellID) then
                    return info.spellID
                end
            end
        end
    end
end
-- 0.13: the recipe to choose once its profession's window opens (the
-- professions module; opened by casting ProfessionOpener's spell).
function API.ExpectRecipe(recipeID)
    local m = Modules.Get("professions")
    if m and m:IsEnabled() then m.pendingRecipe = recipeID end
end
-- 0.13: the recipe SuuUI's Professions window shows right now, or nil.
function API.ShownRecipe()
    local m = Modules.Get("professions")
    local view = m and m:IsEnabled() and m.view
    if not (view and view:IsVisible() and m.mode == "crafting" and view.craftData) then return nil end
    return view.craftData.selected
end
-- 0.13: a unit's whole name. Forever's characters have a surname, and
-- its UnitName returns the two parts where other clients give name and
-- realm ("Suther", "Stargazer": probed 2026-10-14); GetUnitName(unit, true)
-- gives "Suther Stargazer" (with "-Realm" for another realm), the form
-- whispers, invites, the roster and chat use.
function API.FullName(unit)
    local name = GetUnitName and GetUnitName(unit or "player", true)
    if name and name ~= "" then return name end
    return (UnitName(unit or "player"))
end
-- A diagnostic asked the Social window's SuuUI pages to step aside.
function API.ProbeShowsBlizzardSocial() return ns.SocialBlizzard and true or false end
function API.TalentsShown()
    local m = Modules.Get("talents")
    return (m and m:IsEnabled() and m.window and m.window:IsShown()) and true or false
end
-- 0.12: open or close the bags without Blizzard's bag functions (called
-- from an addon they taint Esc in combat): SuuUI's bags when that module is
-- on; else Blizzard's (ToggleAllBags).
function API.ToggleBags()
    local m = Modules.Get("bags")
    if m and m:IsEnabled() and m.Toggle then return m:Toggle() end
    ToggleAllBags()
end
-- 0.11: bags
API.UI.SkinItemSlot = UI.SkinItemSlot -- SkinItemSlot(button) -> skin:SetItem({ icon, count, quality, dim, locked } or nil)
API.UI.ItemSlot = UI.ItemSlot   -- ItemSlot(parent[, size]) -> a plain slot (b.skin)
API.UI.Money = UI.Money         -- Money(parent) -> m:SetCopper(n)
API.UI.Inventory = UI.Inventory -- Inventory(parent, { title, columns, name, sortTip, characters }) -> inv:LayoutSlots(buttons), inv:SetMeta(t), inv:SetNote(t), inv:SetMoney(c); inv.search, inv.sort, inv.grid, inv.onClose
API.UI.LootWindow = UI.LootWindow -- LootWindow(parent, { name }) -> lw:SetSource(t), lw:SetItems(list), lw:FirstSlotOffset(); lw.onClick, lw.onEnter, lw.onLeave, lw.onClose
API.UI.SpellTooltip = UI.SpellTooltip -- SpellTooltip(owner, spellID, extra[, anchor]): the game's spell tooltip with `extra` line(s) under it, kept through the game's redraws
API.UI.SkinTooltip = UI.SkinTooltip -- SkinTooltip(tooltip): SuuUI's art on one of Blizzard's tooltips (its NineSlice hidden)
API.UI.SkinWindow = UI.SkinWindow -- SkinWindow(frame, { title, icon, binding, close, hide, topInset }) -> chrome:SetTabs(list), chrome:LayoutTabs(), chrome:UpdateTabs()
API.UI.IsCoveredByWindow = UI.IsCoveredByWindow -- IsCoveredByWindow(frame): an open window in SuuUI's look covers part of it (0.12)
API.UI.CenterWindow = UI.CenterWindow -- CenterWindow(frame, on): a skinned window in the middle of the screen instead of the row under the micro menu (0.12)
API.UI.Spellbook = UI.Spellbook -- Spellbook(parent, { rows }) -> SetSchools, SetHead, SetSwitches, SetSpells, SetPage; cells[i].button (secure); onSchool, onPage, onSwitch, onEnter, onLeave, onDragStart
API.UI.TalentTree = UI.TalentTree -- TalentTree(parent) -> SetSpecs(list, viewing), SetData({ name, available, pending, editable, hint, trees = { { name, points, nodes, links } } }); onClick, onRemove, onEnter, onLeave, onApply, onUndo, onSpec, onActivate
API.UI.TALENT_TREE_W = UI.TALENT_TREE_W -- the width the Talents page's three trees need
API.UI.TraitTooltip = UI.TraitTooltip -- TraitTooltip(owner, configID, nodeID, { name, treeName, conditions, canSpend, pending, needs, blocked }): the game's talent tooltip
API.UI.LegacyPoints = UI.LegacyPoints -- LegacyPoints(parent[, { account = false }]) -> SetPoints({ earned, total, spent, cap, pending, character })
API.UI.LegacyChallenges = UI.LegacyChallenges -- LegacyChallenges(parent) -> SetCategories(list), Open(i), Close()
API.UI.Professions = UI.Professions -- Professions(parent) -> SetTabs(list, selected), SetOverview({ primary, secondary }), SetCrafting({ name, rank, skill, max, categories, selected }), SetRecipe(r); onTab, onOpen, onSelect, onRecipeEnter, onSearch, onFilters, onTrack, onCreate, onCreateAll
API.UI.PROFESSION_FILTER_DEFAULTS = UI.PROFESSION_FILTER_DEFAULTS -- the recipe list's filters at rest: { show = "learned", difficulty = {}, quality = {}, other = {} }
API.UI.ContextMenu = UI.ContextMenu -- ContextMenu(owner, { title, items = { { label, onClick, disabled } | { separator = true } } }): a right-click menu at the cursor, in the tooltip's look
API.UI.ContextMenuFrom = UI.ContextMenuFrom -- ContextMenuFrom(owner, fn(owner, root)): the same, described like MenuUtil's (root:CreateTitle, CreateButton, CreateDivider)
API.UI.CloseContextMenu = UI.CloseContextMenu
API.UI.Contacts = UI.Contacts -- Contacts(parent) -> SetData({ view, status, online, total, friends, ignored, selected }); onView, onStatus, onSelect, onWhisper, onInvite, onAdd, onIgnore, onUnignore, onMenu
API.UI.RaidGroups = UI.RaidGroups -- RaidGroups(parent) -> SetData({ inRaid, inParty, canLead, reason, size, members }); onReadyCheck, onRoleCheck, onRaidInfo, onConvert, onMove, onSwap, onMember
API.UI.PeopleList = UI.PeopleList -- PeopleList(parent) -> SetData({ title, empty, rows = { { key, name, color, glyph, online, detail, note, pinned, actions } } }); onMenu(row, owner)
API.UI.GuildRoster = UI.GuildRoster -- GuildRoster(parent) -> SetData({ online, total, showOffline, sort, members, selected, actions }); onSearch, onShowOffline, onSort, onSelect, onAction(name, member), onMenu
API.UI.GuildInfo = UI.GuildInfo -- GuildInfo(parent) -> SetData({ info, canEditInfo, ranks }); onEdit("info")
API.UI.GuildLog = UI.GuildLog -- GuildLog(parent) -> SetData({ lines = { { text, when } } })
API.UI.GuildControl = UI.GuildControl -- GuildControl(host, GuildControlUI) -> Layout(): the game's guild control laid out in host
API.UI.GuildMotdBanner = UI.GuildMotdBanner -- GuildMotdBanner(parent) -> SetData({ text, canEdit }), Height(); onEdit
API.UI.GroupFinderBrowse = UI.GroupFinderBrowse -- GroupFinderBrowse(parent) -> SetData({ groups, players, tool, ... }); onRefresh, onFilter, onWhisper, onInvite, onToggle
-- ForeverLFG: the game's group finder and public chat as one list of groups
-- and players looking (Docs/ForeverLFG.md); idle until SuuUI.LFG.Start()
API.LFG = ns.LFG
API.UI.FilterMenu = UI.FilterMenu -- FilterMenu(parent, { groups = { { key, label, kind = "one" | "many" | "toggles", options = { { value, label, color } } } }, defaults, value, placeholder, width, onChange }) -> SetValue, GetValue, Count, Close
API.UI.PROFESSIONS_W = UI.PROFESSIONS_W
API.UI.PROFESSIONS_H = UI.PROFESSIONS_H
API.UI.LegacyTrack = UI.LegacyTrack -- LegacyTrack(parent) -> SetTrack({ earned, total, max, next, stops }): the reward track strip
API.UI.LEGACY_TRACK_H = UI.LEGACY_TRACK_H
API.UI.LEGACY_CARD_H = UI.LEGACY_CARD_H
API.UI.LevelUp = UI.LevelUp -- LevelUp(parent) -> c:SetLevelUp({ title, detail, spells = { { icon, name, rank, isNew, note, text, meta } }, more, cost })
API.UI.Reskin = UI.Reskin -- Reskin(frame): Blizzard's rows, category bars, bars, check buttons and scrollbars in it in SuuUI's look (again whenever called)
API.UI.ReskinScrollBox = UI.ReskinScrollBox
API.UI.ReskinStatusBar = UI.ReskinStatusBar
API.UI.ReskinCheckButton = UI.ReskinCheckButton
API.UI.ReskinScrollBar = UI.ReskinScrollBar
API.UI.ReskinButton = UI.ReskinButton
API.UI.ReskinEditBox = UI.ReskinEditBox
API.UI.ReskinDropdown = UI.ReskinDropdown
API.UI.ReskinIconButton = UI.ReskinIconButton
API.UI.ReskinFillBar = UI.ReskinFillBar
API.UI.ReskinDialog = UI.ReskinDialog -- ReskinDialog(frame): one of Blizzard's small dialogs (a text editor) as a SuuUI panel
API.UI.ReskinMenu = UI.ReskinMenu -- ReskinMenu(menu): an open Blizzard menu in the context menu's look until it closes
API.UI.ReskinPopup = UI.ReskinPopup -- ReskinPopup(dialog): one of the game's shared popups in SuuUI's look until it hides
API.UI.ReskinCollapseButton = UI.ReskinCollapseButton
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
-- 0.12: the level-up card (UI.LevelUp) in the alert's place, tone info:
-- def = { title, detail, spells = { { icon, name, rank, isNew, note, text, meta } }, more,
-- cost (copper) }. HideAlert(key) takes it away.
function API.ShowLevelUp(key, def)
    local m = Modules.Get("alerts")
    if m and m:IsEnabled() then m:ShowLevelUp(key, def) end
end
function API.HideAlert(key)
    local m = Modules.Get("alerts")
    if m and m:IsEnabled() then m:Hide(key) end
end

-- 0.12: what your class trainer teaches (Data/Trainer, from the class
-- probes): { name, level, cost (copper), school, icon, text } for your class.
function API.TrainerSpells()
    return ns.TrainerSpells or {}
end
-- 0.12: every spell ID this client has for each of those names (players'
-- ranks and others alike: { [name] = { id, ... } }); pick a rank by
-- C_Spell.GetSpellLevelLearned.
-- Where a profession recipe is learned (Data/RecipeSources.lua, made by
-- tools/gen_recipe_sources.py): a list of { t = "t" } (trainer), { t = "a" }
-- (automatic) or { t = "i", i = itemID, v, d, dn, o, q, c } (a recipe item:
-- sold by, dropped by and how many, found in, quest rewards, inside), or nil
-- when it isn't known.
function API.RecipeSources(recipeID)
    return ns.RecipeSources and ns.RecipeSources[recipeID]
end

function API.TrainerSpellIDs()
    return ns.TrainerSpellIDs or {}
end
