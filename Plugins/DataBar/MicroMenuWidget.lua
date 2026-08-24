-- The micro menu, moved into the data bar: one field per entry in the `left` section.
--
-- WHY ONE WIDGET PER ENTRY rather than one widget holding fourteen icons. The bar already knows how
-- to lay out, divide, hover and hug a field, and a widget is the unit it understands -- so fourteen
-- widgets get all of that for free, and a later reorder UI has somewhere to write. The `order` values
-- are spaced by ten for exactly that reason.
--
-- THE `left` SECTION IS EMPTY, measured rather than assumed, so the micro menu owns it outright and
-- collides with nothing. Every existing built-in widget is in `center` or `right`.
--
-- RESOLUTION IS BY CANDIDATE LIST, NEVER A LITERAL. This client is a hybrid: Phase 0 found
-- `MICRO_BUTTONS` is nil, so nothing enumerates the strip for us, and `LFDMicroButton` is absent
-- while `LFGMicroButton` is present. An entry whose candidates are all missing is SKIPPED -- it must
-- not render a field that does nothing. That rule was earned: frame names in this cluster have been
-- wrong three times.
--
-- CLICKING CALLS THE PANEL API. The obvious route -- forward the click into Blizzard's own button
-- with `frame:Click()` -- SILENTLY DOES NOTHING on this client, and that was measured, not guessed:
--
--     /dump CharacterMicroButton:GetScript("OnClick") ~= nil   -->  false
--
-- There is no OnClick script to fire. These buttons act through a mixin or mouse handlers instead, so
-- `Click()` is a no-op. ElvUI never calls it either -- it only ever reparents them and HookScripts
-- their hover, which is the tell.
--
-- Each entry therefore names the function that opens its panel, and BOTH the button frame and that
-- function must exist before the entry renders. Two checks rather than one because they answer
-- different questions: the frame says the feature exists on this client, the function says we can
-- actually trigger it. A wrong function name then costs a MISSING glyph, never a dead one -- which is
-- the failure mode this cluster has earned, its frame names having been wrong three times.
local ipairs, type = ipairs, type

local ATLAS = "Interface\\AddOns\\SuuUI\\Media\\micro-icons"

-- ATLAS COORDINATES, mirroring Media/generate_micro_icons.py's GLYPHS list BY INDEX. The generator
-- prints this table; regenerate and re-paste rather than editing a number here, because the order is
-- a contract on that side too -- a glyph inserted mid-list re-points every entry after it.
local COORDS = {
    char        = { 0.00000, 0.25000, 0.00000, 0.25000 },
    spells      = { 0.25000, 0.50000, 0.00000, 0.25000 },
    talents     = { 0.50000, 0.75000, 0.00000, 0.25000 },
    quests      = { 0.75000, 1.00000, 0.00000, 0.25000 },
    social      = { 0.00000, 0.25000, 0.25000, 0.50000 },
    guild       = { 0.25000, 0.50000, 0.25000, 0.50000 },
    pvp         = { 0.50000, 0.75000, 0.25000, 0.50000 },
    lfg         = { 0.75000, 1.00000, 0.25000, 0.50000 },
    map         = { 0.00000, 0.25000, 0.50000, 0.75000 },
    menu        = { 0.25000, 0.50000, 0.50000, 0.75000 },
    help        = { 0.50000, 0.75000, 0.50000, 0.75000 },
    collections = { 0.75000, 1.00000, 0.50000, 0.75000 },
    bags        = { 0.00000, 0.25000, 0.75000, 1.00000 },
    keys        = { 0.25000, 0.50000, 0.75000, 1.00000 },
}

-- ENTRY ORDER IS THE DISPLAY ORDER, and the six shown by default come first so the strip reads the
-- way it was asked for: character, spellbook, quests, guild, options, help. The rest follow and are
-- OFF by default -- available to anyone who wants them, absent for everyone who does not.
--
-- `default` is per entry rather than one switch for the strip. Fourteen glyphs is more menu than most
-- players use, and which six matter is a preference, not something this file should decide for them.
--
-- NO COLLECTIONS ENTRY. Collections does not exist on TBC, so the candidate would never resolve --
-- but a name that cannot resolve is indistinguishable from one that is merely absent today, and
-- leaving it in would keep offering a toggle for a button that is never coming. Its glyph is still in
-- the atlas: renumbering that sheet would silently re-point every coord after it, and the generator's
-- order is a contract for exactly that reason.
--
-- `candidates` is ordered most-likely-first and every name is tried; the first that EXISTS wins.
local ENTRIES = {
    { glyph = "char",    label = "Character",    default = true,
      candidates = { "CharacterMicroButton" },
      requires = "ToggleCharacter",
      action = function() ToggleCharacter("PaperDollFrame") end },
    { glyph = "spells",  label = "Spellbook",    default = true,
      candidates = { "SpellbookMicroButton", "ProfessionMicroButton" },
      requires = "ToggleSpellBook",
      action = function() ToggleSpellBook(BOOKTYPE_SPELL or "spell") end },
    { glyph = "quests",  label = "Quests",       default = true,
      candidates = { "QuestLogMicroButton" },
      requires = "ToggleQuestLog",
      action = function() ToggleQuestLog() end },
    -- The game menu. Labelled Options rather than Menu because that is what a player calls it.
    { glyph = "menu",    label = "Options",      default = true,
      candidates = { "MainMenuMicroButton" },
      requires = "ToggleGameMenu",
      action = function() ToggleGameMenu() end },
    { glyph = "help",    label = "Help",         default = true,
      candidates = { "HelpMicroButton" },
      requires = "ToggleHelpFrame",
      action = function() ToggleHelpFrame() end },

    -- Available, off by default.
    --
    -- Guild is here rather than in the default set because a dedicated guild widget is planned and
    -- will be on by default -- two things opening the same panel from the same bar would be one too
    -- many. The toggle stays, so anyone who prefers the glyph can have it.
    { glyph = "guild",   label = "Guild",        default = false,
      candidates = { "GuildMicroButton" },
      requires = "ToggleGuildFrame",
      action = function() ToggleGuildFrame() end },
    { glyph = "talents", label = "Talents",      default = false,
      candidates = { "TalentMicroButton", "PlayerSpellsMicroButton" },
      requires = "ToggleTalentFrame",
      action = function() ToggleTalentFrame() end },
    { glyph = "social",  label = "Social",       default = false,
      candidates = { "SocialsMicroButton" },
      requires = "ToggleFriendsFrame",
      action = function() ToggleFriendsFrame() end },
    { glyph = "pvp",     label = "PvP",          default = false,
      candidates = { "PVPMicroButton" },
      requires = "TogglePVPFrame",
      action = function() TogglePVPFrame() end },
    -- LFG on this client, LFD on others. Both listed because the pair differ by one letter and only
    -- one of them exists here -- exactly the case a literal would get wrong.
    { glyph = "lfg",     label = "Group Finder", default = false,
      candidates = { "LFGMicroButton", "LFDMicroButton" },
      requires = "ToggleLFGParentFrame",
      action = function() ToggleLFGParentFrame() end },
    { glyph = "map",     label = "Map",          default = false,
      candidates = { "WorldMapMicroButton" },
      requires = "ToggleWorldMap",
      action = function() ToggleWorldMap() end },
    { glyph = "bags",    label = "Bags",         default = false,
      candidates = { "MainMenuBarBackpackButton" },
      requires = "ToggleAllBags",
      action = function() ToggleAllBags() end },
    { glyph = "keys",    label = "Keys",         default = false,
      candidates = { "KeyRingButton" },
      requires = "ToggleKeyRing",
      action = function() ToggleKeyRing() end },
}

local PLUGIN_ID = "data_bar"
local OWNER     = "databar.micromenu"

--- The settings key for one entry's visibility.
local function key(entry)
    return "micro_show_" .. entry.glyph
end

local LABELS_KEY = "micro_show_labels"

--- Whether each entry draws its name beside the glyph.
local function labelsOn()
    return SuuUI.Settings:Get(PLUGIN_ID, LABELS_KEY) ~= false
end

local M = {}

-- The tooltip is shared across every entry: fourteen of them each owning one would be fourteen
-- frames alive to show at most one tip.
local tooltip

--- The first candidate that exists, or nil when none do.
-- @param entry table
-- @return frame|nil, string|nil
local function resolve(entry)
    for _, name in ipairs(entry.candidates) do
        local f = _G[name]
        if f then return f, name end
    end
    return nil, nil
end

--- Whether an entry can both be resolved AND acted on.
--
-- TWO conditions. The button FRAME existing says the feature is present on this client; the panel
-- FUNCTION existing says we can trigger it. A field that cannot act is worse than no field -- it looks
-- like a working control and silently does nothing, which is precisely the bug this replaced.
local function usable(entry)
    if resolve(entry) == nil then return false end
    return type(_G[entry.requires]) == "function"
end

local registered = {}
-- The widget definition per id, kept so a labels change can re-register the ones currently on.
local defs = {}

--- The settings this widget contributes to the Data Bar page: one toggle per entry.
--
-- ONLY entries whose button actually resolves get a toggle. A switch for something this client does
-- not have is a promise the UI cannot keep, and it would read as a broken setting rather than an
-- absent feature.
function M.Schema()
    local out = {
        { key = "", label = "Micro Menu", type = "section" },
        -- Before the per-entry toggles: it changes how ALL of them look, so it reads as the heading
        -- for the block rather than one more item in it.
        { key = LABELS_KEY, label = "Show Labels", type = "toggle", default = true },
    }
    for _, entry in ipairs(ENTRIES) do
        if usable(entry) then
            out[#out + 1] = {
                key = key(entry), label = entry.label, type = "toggle", default = entry.default,
            }
        end
    end
    return out
end

function M.Enable()
    if not SuuUI.DataBar then return end

    -- ORDER IS ASSIGNED FROM THE ENTRY TABLE, not from how many are currently on. A player toggling
    -- Guild off and on again gets it back between Quests and Options rather than on the end of the
    -- strip -- position is a property of the entry, not of the order it was switched on.
    local order = 10
    for _, entry in ipairs(ENTRIES) do
        local myOrder = order
        order = order + 10
        -- SKIPPED, not rendered dead. An entry with no button behind it would be a glyph the player
        -- can click that does nothing at all.
        if usable(entry) then
            local id = "micro_" .. entry.glyph
            local def = {
                id      = id,
                section = "left",
                -- With labels off the glyph IS the readout, and DataField hugs to the icon plus
                -- spaceMd either side. With them on it hugs to icon, gap, text.
                GetText = function()
                    return labelsOn() and entry.label or ""
                end,
                icon       = ATLAS,
                iconCoords = COORDS[entry.glyph],

                OnClick = function()
                    -- Guarded again at call time, not just at registration: a client can drop a
                    -- global between login and the click, and an error here would surface as a Lua
                    -- error popup rather than a button that quietly did nothing.
                    if type(_G[entry.requires]) == "function" then
                        entry.action()
                    end
                end,

                OnEnter = function(field)
                    -- ONLY when the label is not already on screen. A tooltip that repeats a visible
                    -- label is noise, and it covers the bar to tell the player something they can
                    -- already read.
                    if labelsOn() then return end
                    if not tooltip then
                        tooltip = SuuUI.Components.Tooltip({},
                            SuuUI.UIRoot:GetRootContainer():GetFrame())
                    end
                    tooltip:ShowTip(entry.label, field:GetFrame())
                end,
                OnLeave = function()
                    if tooltip then tooltip:HideTip() end
                end,
            }
            def.order = myOrder

            SuuUI.Settings:Watch(PLUGIN_ID, key(entry), function(on)
                if on then
                    SuuUI.DataBar:RegisterWidget(def)
                    registered[id] = true
                else
                    SuuUI.DataBar:UnregisterWidget(id)
                    registered[id] = nil
                end
            end, OWNER .. "." .. entry.glyph, { immediate = true })
            defs[id] = def
        end
    end

    -- REBUILT rather than re-texted. Turning labels on changes each field's WIDTH, not just its
    -- string -- so the field has to be constructed again with the icon-plus-label hug, and the
    -- section re-flowed around it. Re-registering an existing id replaces it in place, which is
    -- exactly what the registry's replace path is for.
    SuuUI.Settings:Watch(PLUGIN_ID, LABELS_KEY, function()
        for id, def in pairs(defs) do
            if registered[id] then
                SuuUI.DataBar:UnregisterWidget(id)
                SuuUI.DataBar:RegisterWidget(def)
            end
        end
    end, OWNER .. ".labels")
end

--- Drops every field this widget registered, and the shared tooltip.
function M.Disable()
    SuuUI.Settings:UnwatchPrefix(OWNER)
    for id in pairs(registered) do
        SuuUI.DataBar:UnregisterWidget(id)
    end
    registered = {}
    if tooltip then
        tooltip:Destroy()
        tooltip = nil
    end
end

--- Which entries resolved, as a list of ids. Test seam and a diagnostic: a player missing a button
--- wants to know whether it was skipped or never existed.
-- @return table
function M.Registered()
    local out = {}
    for _, entry in ipairs(ENTRIES) do
        local id = "micro_" .. entry.glyph
        if registered[id] then out[#out + 1] = id end
    end
    return out
end

M.ENTRIES = ENTRIES
M.COORDS = COORDS
M.ATLAS = ATLAS

SuuUI._DataBar = SuuUI._DataBar or {}
SuuUI._DataBar.MicroMenu = M
