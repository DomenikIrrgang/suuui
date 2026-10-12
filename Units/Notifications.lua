-- Units/Notifications.lua
-- Notifications (step 2.4): a stack at the top left under the micro menu.
-- Requests are Blizzard's own popups (party invite, resurrection, summon,
-- duel, trade, release spirit, delete item, logout, battleground entry …)
-- shown as SuuUI cards; notes come from SuuUI.Notify (timed, sticky, or
-- until something happens). At most five show (the rest behind "+N more"),
-- requests first; in combat only requests and conditions.
-- A built-in module written against the public API only.
--
-- Hosting: SuuUI never answers a popup itself. Calling Blizzard's popup code
-- from an addon would make the popup system SuuUI's, and the game would
-- then refuse the answers it keeps for Blizzard (deleting an item, entering
-- a battleground, cancelling a logout: probed 2026-10-13). Instead the
-- popup goes off screen and its own buttons (and its "type DELETE" box) are
-- placed on the card and drawn in SuuUI's look: every click is Blizzard's
-- (a logout cancelled from a moved popup worked). Nothing is written on
-- Blizzard's frames but points, sizes, alphas and fonts, and all of it goes
-- back when the popup closes. Popups SuuUI doesn't know stay Blizzard's.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "notifications",
    name = "Notifications",
    description = "Requests (invites, resurrection, summons, duels, trades, deleting items, logging out) and notes as SuuUI cards at the top left.",
    api = "0.11",
    reloadToToggle = true,
    defaults = {
        -- under the micro menu (28px down, 36px tall), space-5 clear
        position = { point = "TOPLEFT", x = 28, y = -76 },
        max = 5,
        requests = true,   -- Blizzard's popups as cards
    },
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local ACTION_H = 26
local OFF_SCREEN = 200

-- The popups SuuUI shows as cards: caption, glyph, tone, which button is the
-- main answer (primary) or the dangerous one, the item it's about.
local KINDS = {
    PARTY_INVITE = { category = "Party invite", glyph = "people", primary = 1 },
    GROUP_INVITE_CONFIRMATION = { category = "Group invite", glyph = "people", primary = 1 },
    RESURRECT = { category = "Resurrection", glyph = "plus", primary = 1 },
    RESURRECT_NO_SICKNESS = { category = "Resurrection", glyph = "plus", primary = 1 },
    RESURRECT_NO_TIMER = { category = "Resurrection", glyph = "plus", primary = 1 },
    CONFIRM_SUMMON = { category = "Summon", glyph = "map", primary = 1 },
    CONFIRM_SUMMON_SCENARIO = { category = "Summon", glyph = "map", primary = 1 },
    CONFIRM_SUMMON_STARTING_AREA = { category = "Summon", glyph = "map", primary = 1 },
    DUEL_REQUESTED = { category = "Duel", glyph = "sword", primary = 1 },
    DUEL_OUTOFBOUNDS = { category = "Duel", glyph = "sword", tone = "warning" },
    TRADE = { category = "Trade", glyph = "coin", primary = 1 },
    DEATH = { category = "You died", glyph = "skull", tone = "warning", primary = 1 },
    RECOVER_CORPSE = { category = "Your corpse", glyph = "skull", primary = 1 },
    RECOVER_CORPSE_INSTANCE = { category = "Your corpse", glyph = "skull" },
    AREA_SPIRIT_HEAL = { category = "Spirit healer", glyph = "skull", primary = 1 },
    XP_LOSS = { category = "Spirit healer", glyph = "skull", tone = "warning" },
    DELETE_ITEM = { category = "Delete item", glyph = "trash", tone = "danger", danger = 1, item = true },
    DELETE_GOOD_ITEM = { category = "Delete item", glyph = "trash", tone = "danger", danger = 1, item = true, confirm = true },
    DELETE_QUEST_ITEM = { category = "Delete quest item", glyph = "trash", tone = "danger", danger = 1, item = true },
    DELETE_GOOD_QUEST_ITEM = { category = "Delete quest item", glyph = "trash", tone = "danger", danger = 1, item = true, confirm = true },
    CAMP = { category = "Logging out", glyph = "door" },
    QUIT = { category = "Quitting", glyph = "door", danger = 1 },
    CONFIRM_BATTLEFIELD_ENTRY = { category = "Battleground", glyph = "flag", primary = 1 },
    BFMGR_INVITED_TO_ENTER = { category = "Battleground", glyph = "flag", primary = 1 },
    INSTANCE_LOCK = { category = "Instance lock", glyph = "hourglass", tone = "warning", primary = 1 },
    INSTANCE_BOOT = { category = "Leaving the instance", glyph = "door", tone = "danger" },
    LOOT_BIND = { category = "Binds when picked up", glyph = "gem", primary = 1 },
    EQUIP_BIND = { category = "Binds when equipped", glyph = "gem", primary = 1 },
    USE_BIND = { category = "Binds when used", glyph = "gem", primary = 1 },
    CONFIRM_LOOT_ROLL = { category = "Loot roll", glyph = "gem", primary = 1 },
    ABANDON_QUEST = { category = "Abandon quest", glyph = "scroll", tone = "danger", danger = 1 },
    QUEST_ACCEPT = { category = "Quest", glyph = "scroll", primary = 1 },
    CONFIRM_TALENT_WIPE = { category = "Talents", glyph = "tree", tone = "warning" },
}

--------------------------------------------------------------------------------
-- Notes (SuuUI.Notify)
--------------------------------------------------------------------------------

local nextNote = 0

-- def: { id?, kind = "timed"|"sticky"|"until", category, title, body, icon,
-- tone, duration (timed, default 8), ["until"] (the text), actions } → id
function M:Notify(def)
    if type(def) ~= "table" then return nil end
    nextNote = nextNote + 1
    local id = def.id or ("note:" .. nextNote)
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    d.id = id
    d.kind = d.kind or "timed"
    if d.kind == "timed" then
        d.duration = d.duration or 8
        d.endsAt = GetTime() + d.duration
        d.remaining = d.duration
    end
    d.onClose = function() self:Dismiss(id) end
    -- the same id again: replaced in place
    if not self.notes[id] then self.noteOrder[#self.noteOrder + 1] = id end
    self.notes[id] = d
    self:Rebuild()
    return id
end

function M:Dismiss(id)
    if not self.notes[id] then return end
    self.notes[id] = nil
    for i, x in ipairs(self.noteOrder) do
        if x == id then table.remove(self.noteOrder, i) break end
    end
    self:Rebuild()
end

function M:DismissAll()
    for id, d in pairs(self.notes) do
        if d.kind == "sticky" then self:Dismiss(id) end
    end
end

--------------------------------------------------------------------------------
-- Hosting Blizzard's popups
--------------------------------------------------------------------------------

local function buttonsOf(dialog)
    local out = {}
    local bc = dialog.ButtonContainer
    for i = 1, 4 do
        local b = (bc and bc["Button" .. i]) or _G[dialog:GetName() .. "Button" .. i]
        if b and b:IsShown() then out[#out + 1] = { button = b, index = i } end
    end
    return out
end

local function savePoints(f)
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    return pts
end

local function restorePoints(f, pts)
    f:ClearAllPoints()
    for _, p in ipairs(pts or {}) do f:SetPoint(unpack(p)) end
end

-- What we change on a Blizzard button or edit box, and how it was.
function M:Remember(h, f)
    h.saved = h.saved or {}
    if h.saved[f] then return h.saved[f] end
    local s = { points = savePoints(f), width = f:GetWidth(), height = f:GetHeight(), alphas = {} }
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" then s.alphas[r] = r:GetAlpha() end
    end
    local fs = f.GetFontString and f:GetFontString()
    if fs then s.font, s.fs, s.color = fs:GetFontObject(), fs, { fs:GetTextColor() } end
    if f.GetFontObject and f:GetObjectType() == "EditBox" then s.font = f:GetFontObject() end
    h.saved[f] = s
    return s
end

function M:Undo(h)
    for f, s in pairs(h.saved or {}) do
        restorePoints(f, s.points)
        f:SetSize(s.width, s.height)
        for r, a in pairs(s.alphas) do r:SetAlpha(a) end
        if s.fs and s.font then s.fs:SetFontObject(s.font) end
        if s.fs and s.color then s.fs:SetTextColor(unpack(s.color)) end
        if f:GetObjectType() == "EditBox" and s.font then f:SetFontObject(s.font) end
        local art = self.arts[f]
        if art then art:Hide() end
    end
    h.saved = nil
end

-- SuuUI's look behind a Blizzard button: quiet (surface-raised, gilt-line),
-- primary (arcane) or danger (ember edge); hover brightens the edge.
function M:ArtFor(b)
    local art = self.arts[b]
    if art then return art end
    art = CreateFrame("Frame", nil, self.stack)
    art.fill = UI.Fill(art, "surface-raised", "BACKGROUND")
    art.fill:SetAllPoints()
    art.edge = UI.Border(art, "gilt-line")
    art.glow = UI.Shadow(art, "glow-arcane")
    art.glow:SetShown(false)
    self.arts[b] = art
    b:HookScript("OnEnter", function()
        if not art:IsShown() then return end
        if art.variant == "primary" then art.glow:SetShown(true) else art.edge:SetColor(art.variant == "danger" and "ember" or "gilt") end
    end)
    b:HookScript("OnLeave", function()
        if not art:IsShown() then return end
        art.glow:SetShown(false)
        art.edge:SetColor(art.variant == "primary" and "arcane" or art.variant == "danger" and "ember" or "gilt-line")
    end)
    return art
end

function M:StyleButton(h, b, variant)
    local s = self:Remember(h, b)
    for r in pairs(s.alphas) do r:SetAlpha(0) end
    local fs = b:GetFontString()
    if fs then
        fs:SetFontObject(SuuUI.Fonts.Get("label"))
        fs:SetTextColor(UI.RGBA(variant == "primary" and "on-signal" or variant == "danger" and "ember-text" or "ink"))
    end
    local w = math.max(64, math.ceil((fs and fs:GetUnboundedStringWidth() or 40) + S["space-4"] * 2))
    b:SetSize(w, ACTION_H)
    local art = self:ArtFor(b)
    art.variant = variant
    art:SetFrameStrata(b:GetFrameStrata())
    art:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    art:ClearAllPoints()
    art:SetAllPoints(b)
    art.fill:SetColorTexture(UI.RGBA(variant == "primary" and "arcane" or "surface-raised"))
    art.edge:SetColor(variant == "primary" and "arcane" or variant == "danger" and "ember" or "gilt-line")
    art.glow:SetShown(false)
    art:Show()
    return w
end

function M:StyleEditBox(h, eb, box)
    local s = self:Remember(h, eb)
    for r in pairs(s.alphas) do r:SetAlpha(0) end
    eb:SetFontObject(SuuUI.Fonts.Get("body"))
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", box, "TOPLEFT", S["space-4"], 0)
    eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S["space-4"], 0)
end

-- The card's data for a hosted popup.
function M:CardData(h)
    local dialog, kind = h.dialog, h.kind
    local text = dialog.Text and dialog.Text:GetText()
    local d = {
        id = h.id, kind = "action", tone = kind.tone, category = kind.category,
        title = plain(text) and text or "", icon = { glyph = kind.glyph },
        host = { buttons = #buttonsOf(dialog) },
    }
    local info = StaticPopupDialogs and StaticPopupDialogs[h.which]
    local timeout = info and info.timeout
    if plain(timeout) and type(timeout) == "number" and timeout > 0 and plain(dialog.timeleft) and dialog.timeleft then
        d.duration, d.remaining = timeout, dialog.timeleft
    end
    if kind.item then
        local what, _, link = GetCursorInfo()
        if what == "item" and plain(link) and link then
            local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
            local qualities = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }
            d.item = { icon = icon, label = name or link, quality = qualities[quality or 1] or "common" }
        end
    end
    if kind.confirm and dialog.EditBox and dialog.EditBox:IsShown() then
        d.confirmText = (DELETE_ITEM_CONFIRM_STRING or "DELETE")
    end
    return d
end

-- The popup's own buttons and edit box onto its card.
function M:Attach(h)
    local card = self.stack:CardFor(h.id)
    if not card then
        -- not among the shown cards: its parts back in the (off screen) popup
        self:Undo(h)
        h.card = nil
        return
    end
    h.card = card
    local kind = h.kind
    local x = 0
    local list = buttonsOf(h.dialog)
    for k = #list, 1, -1 do
        local b, index = list[k].button, list[k].index
        local variant = (index == kind.primary and "primary") or (index == kind.danger and "danger") or "quiet"
        local w = self:StyleButton(h, b, variant)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", card.actionsRow, "RIGHT", -x, 0)
        x = x + w + S["space-3"]
    end
    local eb = h.dialog.EditBox
    if card.data and card.data.confirmText and eb then self:StyleEditBox(h, eb, card.confirmBox) end
end

function M:Host(dialog, which)
    if not self:Get("requests") then return end
    local kind = KINDS[which]
    if not kind then return end
    local h = self.hosts[dialog]
    if h and h.which ~= which then self:Undo(h) end
    if not h then
        h = { dialog = dialog, order = GetTime() }
        self.hosts[dialog] = h
        if not self.hookedHide[dialog] then
            self.hookedHide[dialog] = true
            dialog:HookScript("OnHide", function() self:Release(dialog) end)
        end
    end
    h.which, h.kind = which, kind
    h.id = "popup:" .. (dialog:GetName() or tostring(dialog))
    -- the popup itself out of sight (its parts come onto the card); kept on
    -- screen by its clamp otherwise
    if h.clamped == nil then h.clamped = dialog:IsClampedToScreen() and true or false end
    dialog:SetClampedToScreen(false)
    dialog:ClearAllPoints()
    dialog:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -OFF_SCREEN, OFF_SCREEN)
    h.data = self:CardData(h)
    self:Rebuild()
end

function M:Release(dialog)
    local h = self.hosts[dialog]
    if not h then return end
    self:Undo(h)
    if h.clamped ~= nil then dialog:SetClampedToScreen(h.clamped) end
    self.hosts[dialog] = nil
    self:Rebuild()
end

--------------------------------------------------------------------------------
-- The stack
--------------------------------------------------------------------------------

function M:Items()
    local items = {}
    local hosts = {}
    for _, h in pairs(self.hosts) do hosts[#hosts + 1] = h end
    table.sort(hosts, function(a, b) return a.order < b.order end)
    for _, h in ipairs(hosts) do items[#items + 1] = h.data end
    for _, id in ipairs(self.noteOrder) do items[#items + 1] = self.notes[id] end
    return items
end

function M:Rebuild()
    if not self.stack then return end
    self.stack:SetItems(self:Items(), InCombatLockdown())
    for _, h in pairs(self.hosts) do self:Attach(h) end
end

-- A few times a second: counting titles (logging out in 12 s), time left,
-- timed notes going, hosted parts kept on their cards (Blizzard lays its
-- popups out again now and then), popups anchored to a hosted one put back
-- on screen.
function M:Tick()
    local now = GetTime()
    local changed = false
    for id, d in pairs(self.notes) do
        if d.kind == "timed" and d.endsAt then
            d.remaining = d.endsAt - now
            if d.remaining <= 0 then
                self.notes[id] = nil
                for i, x in ipairs(self.noteOrder) do if x == id then table.remove(self.noteOrder, i) break end end
                changed = true
            else
                local card = self.stack:CardFor(id)
                if card then card:SetRemaining(d.remaining) end
            end
        end
    end
    if changed then self:Rebuild() end
    for dialog, h in pairs(self.hosts) do
        local card = h.card
        if card then
            local text = dialog.Text and dialog.Text:GetText()
            if plain(text) and text ~= h.data.title then
                h.data.title = text
                card:SetTitle(text)
            end
            if h.data.duration and plain(dialog.timeleft) and dialog.timeleft then card:SetRemaining(dialog.timeleft) end
            local point, rel = dialog:GetPoint(1)
            if point ~= "BOTTOMRIGHT" or rel ~= UIParent then
                dialog:ClearAllPoints()
                dialog:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -OFF_SCREEN, OFF_SCREEN)
            end
            local list = buttonsOf(dialog)
            local first = list[#list] and list[#list].button
            if first then
                local _, brel = first:GetPoint(1)
                if brel ~= card.actionsRow then self:Attach(h) end
            end
            -- disabled until typed (delete): Blizzard's own rule, shown dim
            for _, x in ipairs(list) do
                local art = self.arts[x.button]
                if art then art:SetAlpha(x.button:IsEnabled() and 1 or T.opacity["opacity-disabled"]) end
            end
        end
    end
    -- a popup Blizzard anchored under a hosted one would be off screen too
    for i = 1, 4 do
        local d = _G["StaticPopup" .. i]
        if d and d:IsShown() and not self.hosts[d] then
            local _, rel = d:GetPoint(1)
            if rel and self.hosts[rel] then
                d:ClearAllPoints()
                d:SetPoint("TOP", UIParent, "TOP", 0, -135)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local PREVIEW = {
    { id = "p1", kind = "action", category = "Party invite", title = "Ysolde invites you to a group.", icon = { glyph = "people" },
      duration = 60, remaining = 42, actions = { { label = "Accept", variant = "primary" }, { label = "Decline" } } },
    { id = "p2", kind = "action", tone = "danger", category = "Delete item", title = "Do you want to destroy Ember Pelt?",
      icon = { glyph = "trash" }, item = { icon = 134075, label = "Ember Pelt", quality = "uncommon" }, confirmText = "DELETE",
      actions = { { label = "Yes", variant = "danger" }, { label = "No" } } },
    { id = "p3", kind = "until", category = "Durability", title = "Your gear is badly damaged", icon = { glyph = "hammer" },
      tone = "warning", ["until"] = "Goes when you repair" },
    { id = "p4", kind = "timed", category = "Bags", title = "Your bags are full", icon = { glyph = "bag" }, duration = 8, remaining = 5 },
}

function M:PreviewView(parent)
    if not self.preview then
        self.preview = UI.NotificationStack(parent, { max = 5 })
        self.preview:SetItems(PREVIEW, false)
    end
    self.preview:SetParent(parent)
    return self.preview
end

local SECTION = {
    id = "notifications", label = "Notifications", category = "General", order = 30,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Notifications", description = "Requests and notes at the top left, under the micro menu: requests first, then what waits on something, then notes. In combat only requests and conditions show. Move them in edit mode.", rows = {
            { key = "requests", label = "Blizzard's popups as cards", control = "toggle",
              description = "Invites, resurrection, summons, duels, trades, release spirit, deleting items, logging out, battleground entry: Blizzard's own buttons on SuuUI's cards, so every answer is still Blizzard's. Off: Blizzard's popups as they are." },
            { key = "max", label = "Shown at once", control = "slider", min = 3, max = 8, step = 1,
              description = "The rest wait behind \"+N more\"." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    self.notes = self.notes or {}
    self.noteOrder = self.noteOrder or {}
    self.hosts = self.hosts or {}
    self.hookedHide = self.hookedHide or {}
    self.arts = self.arts or {}
    if not self.frame then
        self.frame = CreateFrame("Frame", "SuuUINotifications", SuuUI.Root)
        self.frame:SetFrameStrata("HIGH")
        self.frame:SetSize(T.size["notice-w"], 200)
        self.stack = UI.NotificationStack(self.frame, { max = self:Get("max") })
        self.stack:SetPoint("TOPLEFT")
        self.stack.onExpand = function() self:Rebuild() end
        self.stack.onClearAll = function() self:DismissAll() end
        local wait = 0
        self.frame:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.1
            self:Tick()
        end)
    end
    self:RegisterMover(self.frame, { key = "position", label = "Notifications" })
    self:RegisterSettings(SECTION)
    self:Watch("max", function(v) self.stack.max = v; self:Rebuild() end)
    self:Watch("requests", function(on)
        if not on then for dialog in pairs(self.hosts) do self:Release(dialog) end end
    end)
    if StaticPopup_Show and not self.hooked then
        self.hooked = true
        hooksecurefunc("StaticPopup_Show", function(which, _, _, data)
            if not self:IsEnabled() then return end
            local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which, data)
            if dialog then self:Host(dialog, which) end
        end)
    end
    -- in combat notes wait; out of it they come back
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function() self:Rebuild() end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function() self:Rebuild() end)
    self:RegisterCommand("notify", "test: shows one notification of each kind", function()
        self:Notify({ kind = "timed", category = "Test", title = "A timed note", body = "It goes by itself after 8 seconds.", icon = { glyph = "bell" } })
        self:Notify({ kind = "sticky", category = "Test", title = "A sticky note", body = "It stays until you close it.", icon = { glyph = "mail" } })
        self:Notify({ kind = "until", category = "Test", title = "A condition", ["until"] = "Goes when the test ends", icon = { glyph = "hourglass" }, tone = "warning" })
    end)
end

function M:OnDisable()
    for dialog in pairs(self.hosts or {}) do self:Release(dialog) end
    if self.frame then self.frame:Hide() end
end
