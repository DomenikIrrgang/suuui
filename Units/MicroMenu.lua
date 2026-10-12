-- Units/MicroMenu.lua
-- SuuUI's micro menu (step 2.1): top left, space-7 from the edges. Blizzard's
-- micro buttons in their order (each SuuUI button clicks its Blizzard one
-- through a secure button, so the game's own rules for each window apply,
-- in combat too), plus the design's World map and Bags. Which ones show is
-- a setting. An arcane diamond marks a button with something to act on
-- (unspent talent points). Blizzard's micro menu is hidden while this runs
-- (its buttons stay, unseen, for SuuUI's to click); turned off, it's back.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens

local M = SuuUI.RegisterModule({
    id = "micromenu",
    name = "Micro menu",
    description = "SuuUI's own micro menu: character, spellbook, talents, quests and the rest, top left.",
    api = "0.10",
    reloadToToggle = true,
    defaults = {
        position = { point = "TOPLEFT", x = 28, y = -28 },
        shows = "always",
        buttons = { "character", "professions", "spellbook", "talents", "legacy", "questlog", "guild",
                    "groupfinder", "worldmap", "bags", "menu" },
    },
})

-- Everything the menu can hold, in Blizzard's order (World map and Bags,
-- the design's, before the game menu). `click`: the Blizzard micro button.
local ITEMS = {
    { key = "character", glyph = "person", label = "Character", click = "CharacterMicroButton" },
    { key = "professions", glyph = "hammer", label = "Professions", click = "ProfessionMicroButton" },
    { key = "spellbook", glyph = "book", label = "Spellbook", click = "SpellbookMicroButton" },
    { key = "talents", glyph = "tree", label = "Talents", click = "TalentMicroButton" },
    { key = "legacy", glyph = "trophy", label = "Legacy", click = "LegacyMicroButton" },
    { key = "questlog", glyph = "scroll", label = "Quest log", click = "QuestLogMicroButton" },
    { key = "guild", glyph = "people", label = "Guild & Communities", click = "GuildMicroButton" },
    { key = "groupfinder", glyph = "search", label = "Group Finder", click = "LFDMicroButton" },
    { key = "collections", glyph = "gem", label = "Collections", click = "CollectionsMicroButton" },
    { key = "shop", glyph = "coin", label = "Shop", click = "StoreMicroButton" },
    { key = "worldmap", glyph = "map", label = "World map", onClick = function() ToggleWorldMap() end, bind = "TOGGLEWORLDMAP",
      open = function() return WorldMapFrame and WorldMapFrame:IsShown() end },
    { key = "bags", glyph = "bag", label = "Bags", onClick = function() ToggleAllBags() end, bind = "OPENALLBAGS",
      open = function()
          if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then return true end
          for i = 1, 6 do
              local f = _G["ContainerFrame" .. i]
              if f and f:IsShown() then return true end
          end
          return false
      end },
    -- the game menu's Blizzard button doesn't answer a secure click on
    -- Forever (EllesmereUI toggles the frame the same way)
    { key = "menu", glyph = "menu", label = "Game menu", onClick = function() ToggleFrame(GameMenuFrame) end,
      open = function() return GameMenuFrame and GameMenuFrame:IsShown() end },
}

-- The chosen items this client has (a Blizzard button that's missing: left out).
function M:Items()
    local chosen = {}
    for _, k in ipairs(self:Get("buttons")) do chosen[k] = true end
    local out = {}
    for _, item in ipairs(ITEMS) do
        if chosen[item.key] and (not item.click or _G[item.click]) then out[#out + 1] = item end
    end
    return out
end

function M:Layout()
    if not self.menu then return end
    if not self.menu:SetItems(self:Items()) then
        self.pendingLayout = true
        return
    end
    self.pendingLayout = nil
    self:UpdateAlerts()
end

-- Which windows are open: a Blizzard micro button is pushed while its window
-- shows; the others check their window. Looked at a few times a second
-- while the menu shows.
local function isOpen(item)
    if item.open then return item.open() and true or false end
    local b = item.click and _G[item.click]
    return b and b.GetButtonState and b:GetButtonState() == "PUSHED" or false
end

function M:UpdateActive()
    if not self.menu then return end
    for _, item in ipairs(ITEMS) do self.menu:SetActive(item.key, isOpen(item)) end
end

-- Something to act on: unspent talent points.
function M:UpdateAlerts()
    if not self.menu then return end
    local talents = C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints
    local ok, has = false, false
    if talents then ok, has = pcall(talents) end
    local unspent = ok and not (issecretvalue and issecretvalue(has)) and has == true
    self.menu:SetAlert("talents", unspent and "Talent points to spend" or nil)
end

function M:ApplyShows()
    if not self.menu then return end
    UI.SetVisibility(self.menu, self:Get("position").hidden and "hidden" or self:Get("shows"))
end

-- Blizzard's micro menu out of sight (its buttons stay, for SuuUI's to click).
function M:HideBlizzard()
    local container = MicroMenuContainer
    if container and not self.blizzardHidden then
        self.blizzardHidden = true
        SuuUI.SuppressBlizzard(container)
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function buttonChips(parent, onChange)
    local opts = {}
    for _, item in ipairs(ITEMS) do
        if not item.click or _G[item.click] then opts[#opts + 1] = { value = item.key, label = item.label } end
    end
    return UI.ToggleChips(parent, { options = opts, value = M:Get("buttons"), onChange = onChange })
end

function M:PreviewView(parent)
    if not self.preview then
        -- plain buttons (no clicks) for the settings' preview
        local items = {}
        for _, item in ipairs(ITEMS) do items[#items + 1] = { key = item.key, glyph = item.glyph, label = item.label, onClick = function() end } end
        self.previewItems = items
        self.preview = UI.MicroMenu(parent, {})
    end
    self.preview:SetParent(parent)
    local chosen = {}
    for _, k in ipairs(self:Get("buttons")) do chosen[k] = true end
    local list = {}
    for _, item in ipairs(self.previewItems) do if chosen[item.key] then list[#list + 1] = item end end
    self.preview:SetItems(list)
    self.preview:SetAlert("talents", "Talent points to spend")
    return self.preview
end

local SECTION = {
    id = "micromenu", label = "Micro menu", category = "Frames", order = 27, merge = "microbags",
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Micro menu", description = "SuuUI's own: each button opens the same window as Blizzard's. An arcane diamond marks something to act on. Move it in edit mode.", rows = {
            { key = "buttons", label = "Buttons", control = "custom", build = buttonChips, stacked = true, combat = true,
              description = "Which ones show, in Blizzard's order." },
            { key = "shows", label = "Shows", control = "segmented", options = UI.VISIBILITY_OPTIONS, combat = true,
              description = "Always, only in combat, or when the mouse is over it." },
        } },
    },
}

function M:OnEnable()
    if not self.menu then
        self.menu = UI.MicroMenu(SuuUI.Root, { name = "SuuUIMicroMenu" })
        self.menu:SetFrameStrata("MEDIUM")
        local wait = 0
        self.menu:HookScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.15
            self:UpdateActive()
        end)
    end
    self.menu.suuManagedShow = true
    self:HideBlizzard()
    self:Layout()
    self:RegisterMover(self.menu, { key = "position", label = "Micro menu" })
    self:RegisterSettings(SECTION)
    self:ApplyShows()
    self:Watch("buttons", function()
        self:Layout()
        if self.preview and self.preview:IsVisible() then self:PreviewView(self.preview:GetParent()) end
    end)
    for _, key in ipairs({ "shows", "position" }) do
        self:Watch(key, function() self:ApplyShows() end)
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() if self.pendingLayout then self:Layout() end end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:UpdateAlerts() end) end
    end
end

function M:OnDisable()
    if self.menu then self.menu:Hide() end
end
