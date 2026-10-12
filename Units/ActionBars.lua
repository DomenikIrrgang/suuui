-- Units/ActionBars.lua
-- The action bars: the dock (step 1.5), bars 1-4 as one anchor panel, bottom
-- centre; and bars 5-8 (step 1.6a), each on its own. A built-in module
-- written against the public API only.
--
--   [ bar 3 ]  [ bar 2 (12)        ]  [ bar 4 ]
--   [ 6 x 2 ]  [ bar 1 (12, paged) ]  [ 6 x 2 ]
--   [============ XP or reputation ============]
--
-- The page bar 1 is on ("Cat Form", "Page 2") is in its buttons' tooltips,
-- not in a row of its own (the design has one under bar 1; it left a gap).
--
-- Buttons are action (20px), space-1 apart; the blocks sit space-4 apart:
-- 538 x 42 px of bars inside the panel's space-3 padding. Placement (2560x1440
-- reference): bottom centre, space-7 from the bottom edge.
--
-- The XP bar (or, at the level cap, your watched reputation) runs along the
-- dock's foot, space-2 under the bars; Blizzard's tracking bars are stood
-- down with it.
--
-- Bars 5-8 stand vertically at the right edge (bar 5 outermost, space-2
-- apart), each movable in edit mode with its own columns and key bindings.
-- The design starts them hidden; on the first load each one that holds
-- anything is shown instead, so nobody loses spells they placed there.
--
-- The stance/form bar sits space-2 above the dock's left outer edge and the
-- pet bar above its right one (step 1.6b), at 9/10 of the dock's button
-- size. The pet bar shows only while you have a pet.
--
-- Attaching (step 1.6c): bars 5-8, stance and pet can be attached to the
-- dock in edit mode (drop them on it, or "Attach to dock" in the toolbar).
-- An attached bar is part of the dock: dragging it moves the whole dock, and
-- it shows and fades with it, kept at an offset from its nearest edge. To
-- change its spot, Detach, move it, and attach it again. Stance and pet
-- start attached.
--
-- Blizzard's bars 1-8, stance and pet bars are stood down. Its main bar can't be hidden from addon code without
-- tainting Edit Mode, so it stays where it is, invisible and deaf to the
-- mouse; the others move under a hidden parent. They come back after a
-- reload, so this module turns off or on with a reload.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "actionbars",
    name = "Action bars",
    description = "Action bars 1 to 8: the dock (bars 1 to 4) and four bars of your own, with key bindings, cooldowns and range.",
    api = "0.8",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOM", x = 0, y = 28 },
        keys1 = true, keys2 = true, keys3 = true, keys4 = true,
        showEmpty = false,
        showXP = true,
        showStance = true, keysStance = true,
        showPet = true, keysPet = true,
        dockSize = 20, dockVisibility = "always",
        textSize = 9.5,
        count5 = 12, count6 = 12, count7 = 12, count8 = 12,
        size5 = 20, size6 = 20, size7 = 20, size8 = 20,
        gap5 = 2, gap6 = 2, gap7 = 2, gap8 = 2,
        vis5 = "always", vis6 = "always", vis7 = "always", vis8 = "always",
        -- Attached to the dock: moved with it, kept at an offset from its
        -- nearest edge. Stance and pet start attached above its outer edges.
        attach5 = false, attach6 = false, attach7 = false, attach8 = false,
        attachStance = true, attachPet = true,
        off5 = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = 4 },
        off6 = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = 4 },
        off7 = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = 4 },
        off8 = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = 4 },
        offStance = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = 4 },
        offPet = { point = "BOTTOMRIGHT", rel = "TOPRIGHT", x = 0, y = 4 },
        stancePosition = { point = "BOTTOM", x = -220, y = 120 },
        petPosition = { point = "BOTTOM", x = 220, y = 120 },
        -- bars 5-8: seeded from what they hold on the first load
        seeded = false,
        show5 = false, show6 = false, show7 = false, show8 = false,
        keys5 = true, keys6 = true, keys7 = true, keys8 = true,
        cols5 = 1, cols6 = 1, cols7 = 1, cols8 = 1,
        pos5 = { point = "RIGHT", x = -28, y = 0 },
        pos6 = { point = "RIGHT", x = -52, y = 0 },
        pos7 = { point = "RIGHT", x = -76, y = 0 },
        pos8 = { point = "RIGHT", x = -100, y = 0 },
    },
})

-- Blizzard's numbering: bar, first action slot, binding command, its frame.
local BARS = {
    { id = 1, slot = 1,  binding = "ACTIONBUTTON",          blizzard = "MainActionBar",       buttons = "ActionButton" },
    { id = 2, slot = 61, binding = "MULTIACTIONBAR1BUTTON", blizzard = "MultiBarBottomLeft",  buttons = "MultiBarBottomLeftButton" },
    { id = 3, slot = 49, binding = "MULTIACTIONBAR2BUTTON", blizzard = "MultiBarBottomRight", buttons = "MultiBarBottomRightButton" },
    { id = 4, slot = 25, binding = "MULTIACTIONBAR3BUTTON", blizzard = "MultiBarRight",       buttons = "MultiBarRightButton" },
    { id = 5, slot = 37,  binding = "MULTIACTIONBAR4BUTTON", blizzard = "MultiBarLeft", buttons = "MultiBarLeftButton", free = true },
    { id = 6, slot = 145, binding = "MULTIACTIONBAR5BUTTON", blizzard = "MultiBar5",    buttons = "MultiBar5Button",    free = true },
    { id = 7, slot = 157, binding = "MULTIACTIONBAR6BUTTON", blizzard = "MultiBar6",    buttons = "MultiBar6Button",    free = true },
    { id = 8, slot = 169, binding = "MULTIACTIONBAR7BUTTON", blizzard = "MultiBar7",    buttons = "MultiBar7Button",    free = true },
}

local COLUMNS = { 1, 2, 3, 4, 6, 12 }
local VISIBILITY = {
    { value = "always", label = "Always" },
    { value = "combat", label = "In combat" },
    { value = "mouseover", label = "Mouseover" },
}


--------------------------------------------------------------------------------
-- Blizzard's bars
--------------------------------------------------------------------------------

-- Mouse off, once. Never on a protected frame in combat: Blizzard re-shows
-- its main bar on every form change, and EnableMouse there is a blocked call
-- (it stays off from the first pass out of combat anyway).
local function noMouse(f)
    if not f or type(f.EnableMouse) ~= "function" then return end
    if f.IsMouseEnabled and not f:IsMouseEnabled() then return end
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
    f:EnableMouse(false)
    if f.EnableMouseClicks then f:EnableMouseClicks(false) end
    if f.EnableMouseMotion then f:EnableMouseMotion(false) end
end

-- Its buttons: no events, no mouse, and Blizzard's own pass hides them.
local function quietButtons(prefix)
    for i = 1, 12 do
        local b = _G[prefix .. i]
        if b then
            b:UnregisterAllEvents()
            noMouse(b)
            if b.SetAttributeNoHandler then b:SetAttributeNoHandler("statehidden", true) end
        end
    end
end

-- The main bar: invisible and click-through, never hidden (a Hide from
-- addon code taints Edit Mode's next combat show).
local function fadeMainBar(bar)
    local function silence(self)
        self:SetAlpha(0)
        noMouse(self)
        local pager = self.ActionBarPageNumber
        if pager then
            noMouse(pager)
            noMouse(pager.UpButton)
            noMouse(pager.DownButton)
        end
        -- Forever's end caps are Edit Mode systems with their own overlays.
        local caps = self.EndCaps
        if caps then
            for _, cap in ipairs({ caps.LeftEndCap, caps.RightEndCap }) do
                if cap and cap.Selection then cap.Selection:SetAlpha(0); noMouse(cap.Selection) end
            end
        end
        if self.Selection then self.Selection:SetAlpha(0); noMouse(self.Selection) end
    end
    silence(bar)
    hooksecurefunc(bar, "Show", silence)
end

local TRACKING = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MainMenuExpBar", "ReputationWatchBar" }

local function standDownBlizzard()
    if M:Get("showXP") then
        if StatusTrackingBarManager then StatusTrackingBarManager:UnregisterAllEvents() end
        for _, name in ipairs(TRACKING) do SuuUI.SuppressBlizzard(name) end
    end
    for _, extra in ipairs({ { "StanceBar", "StanceButton" }, { "PetActionBar", "PetActionButton" } }) do
        if _G[extra[1]] then
            SuuUI.SuppressBlizzard(extra[1], { noHide = true })
            quietButtons(extra[2])
        end
    end
    for _, def in ipairs(BARS) do
        local frame = _G[def.blizzard]
        if frame then
            if def.id == 1 then
                fadeMainBar(frame)
            else
                SuuUI.SuppressBlizzard(frame, { noHide = true })
            end
            quietButtons(def.buttons)
        end
    end
end

--------------------------------------------------------------------------------
-- The dock
--------------------------------------------------------------------------------

-- The page bar 1 is on: the stance or form's name, else "Page 1" to "Page 6".
local function pageName(page)
    if page >= 2 and page <= 6 then return ("Page %d"):format(page) end
    if page > 10 then return "" end
    local form = GetShapeshiftForm and GetShapeshiftForm()
    if form and form > 0 then
        local _, _, _, spellID = GetShapeshiftFormInfo(form)
        local name = spellID and C_Spell.GetSpellName(spellID)
        if name then return name end
    end
    return page == 1 and "Page 1" or ""
end

function M:Arrange()
    local d = self.dock
    local pad, gap, px, g = S["space-3"], S["space-4"], self:Get("dockSize"), S["space-1"]
    local middleW = 12 * px + 11 * g
    local sideW = 6 * px + 5 * g
    local bars2H = 2 * px + g
    local xpH = self.xpShown and (UI.Size("progress") + S["space-2"]) or 0
    local innerW = sideW * 2 + gap * 2 + middleW

    self:RunOutOfCombat("arrange", function()
        d:SetSize(pad * 2 + innerW, pad * 2 + bars2H + xpH)
        self.xp:SetWidth(innerW)
        self.xp:SetShown(self.xpShown)
        local foot = pad + xpH
        self.bars[3].header:ClearAllPoints()
        self.bars[3].header:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", pad, foot)
        self.bars[4].header:ClearAllPoints()
        self.bars[4].header:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -pad, foot)
        self.bars[1].header:ClearAllPoints()
        self.bars[1].header:SetPoint("BOTTOM", d, "BOTTOM", 0, foot)
        self.bars[2].header:ClearAllPoints()
        self.bars[2].header:SetPoint("BOTTOM", self.bars[1].header, "TOP", 0, S["space-1"])
    end)
end

-- Bars 5-8 on the first load: shown if they hold anything.
function M:Seed()
    if self:Get("seeded") then return end
    for _, def in ipairs(BARS) do
        if def.free then
            local any = false
            for i = 0, 11 do if HasAction(def.slot + i) then any = true break end end
            self:Set("show" .. def.id, any)
        end
    end
    self:Set("seeded", true)
end

function M:ApplyOptions()
    -- The dock: one button size for its four bars; stance and pet at 9/10 of it.
    local px = self:Get("dockSize")
    for id = 1, 4 do self.bars[id]:Layout(nil, nil, 12, px) end
    self.stance:SetButtonSize(math.floor(px * 0.9 + 0.5))
    self.pet:SetButtonSize(math.floor(px * 0.9 + 0.5))
    UI.SetVisibility(self.dock, self:Get("position").hidden and "hidden" or self:Get("dockVisibility"))
    for i, bar in ipairs(self.bars) do bar:SetHotkeysShown(self:Get("keys" .. i)) end
    for _, bar in ipairs(self.bars) do bar:SetShowEmpty(self:Get("showEmpty")) end
    UI.SetActionTextSize(self:Get("textSize"))
    self.pet:SetShowEmpty(self:Get("showEmpty"))
    for _, def in ipairs(BARS) do
        if def.free then
            local id = def.id
            local bar = self.bars[id]
            bar:Layout(self:Get("cols" .. id), self:Get("gap" .. id), self:Get("count" .. id), self:Get("size" .. id))
            local shown = self:Get("show" .. id) and not self:Get("pos" .. id).hidden
            bar:SetVisibility(shown and self:Get("vis" .. id) or "hidden")
        end
    end
    self.stance:SetEnabled(self:Get("showStance") and not self:Get("stancePosition").hidden)
    self.stance:SetHotkeysShown(self:Get("keysStance"))
    self.pet:SetEnabled(self:Get("showPet") and not self:Get("petPosition").hidden)
    self.pet:SetHotkeysShown(self:Get("keysPet"))
    for _, a in ipairs(self.attachable) do
        self:RunOutOfCombat("place:" .. a.key, function() self:Place(a) end)
    end
    SuuUI.EditMode.Refresh()
    self.xpShown = nil
    self:UpdateXP()
    self:Arrange()
end

function M:Build()
    local d = UI.Panel(SuuUI.Root, { anchor = true, name = "SuuUIActionDock", width = 100, height = 40 })
    self.dock = d
    self.bars = {}
    for i, def in ipairs(BARS) do
        self.bars[i] = UI.ActionBar(def.free and SuuUI.Root or d, {
            name = "SuuUIActionBar" .. def.id,
            label = "Bar " .. def.id,
            slot = def.slot,
            binding = def.binding,
            columns = def.free and self:Get("cols" .. def.id) or (def.id == 3 or def.id == 4) and 6 or 12,
            paging = def.id == 1 and UI.ActionBarPaging() or nil,
            onPage = def.id == 1 and function(bar, page)
                local note = pageName(page)
                for _, b in ipairs(bar.buttons) do b.tooltipNote = note ~= "" and ("Bar 1: " .. note) or nil end
            end or nil,
        })
    end


    -- XP (or reputation) along the foot; rested XP as a lighter run after it.
    self.xp = UI.StatusBar(d, { width = 100, height = "progress", fill = "progress-fill", track = "track", ghost = true })
    self.xp.ghost:SetStatusBarColor(UI.RGBA("progress-rested"))
    self.xp:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", S["space-3"], S["space-3"])
    self.xp:EnableMouse(true)
    self.xp:SetScript("OnEnter", function(bar) self:XPTooltip(bar) end)
    self.xp:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Stance and pet bars: attached above the dock's outer edges by default.
    self.stance = UI.StanceBar(d, { name = "SuuUIStanceBar", label = "Stance bar" })
    self.pet = UI.PetBar(d, { name = "SuuUIPetBar", label = "Pet bar" })

    d.suuManagedShow = true -- shown by its visibility setting
    self:RegisterMover(d, { key = "position", label = "Action bars" })

    -- Everything that can attach to the dock: bars 5-8, stance, pet.
    self.attachable = {}
    for _, def in ipairs(BARS) do
        if def.free then
            local id = def.id
            self.attachable[#self.attachable + 1] = { key = tostring(id), header = self.bars[id].header,
                pos = "pos" .. id, label = "Action bar " .. id,
                enabled = function() return self:Get("show" .. id) end }
        end
    end
    self.attachable[#self.attachable + 1] = { key = "Stance", header = self.stance.header,
        pos = "stancePosition", label = "Stance bar",
        enabled = function() return self:Get("showStance") and GetNumShapeshiftForms ~= nil and (GetNumShapeshiftForms() or 0) > 0 end }
    self.attachable[#self.attachable + 1] = { key = "Pet", header = self.pet.header,
        pos = "petPosition", label = "Pet bar", enabled = function() return self:Get("showPet") end }

    for _, a in ipairs(self.attachable) do
        a.header.suuManagedShow = true -- shown by its own settings
        self:RegisterMover(a.header, {
            key = a.pos, label = a.label, enabled = a.enabled,
            place = function() self:Place(a) end,
            dragFrame = function() return self:Get("attach" .. a.key) and self.dock or a.header end,
            onDrop = function(l, b, w, h) return self:Dropped(a, l, b, w, h) end,
            -- Reset: attached, it is part of the dock, so the dock goes back
            -- to its place; free, the bar goes back to its default (attached
            -- again for stance and pet).
            reset = function()
                if self:Get("attach" .. a.key) then
                    self:Reset("position")
                else
                    self:Reset(a.pos)
                    self:Reset("attach" .. a.key)
                    self:Reset("off" .. a.key)
                end
            end,
            action = {
                label = function() return self:Get("attach" .. a.key) and "Detach" or "Attach to dock" end,
                onClick = function() self:ToggleAttach(a) end,
            },
        })
    end
end

--------------------------------------------------------------------------------
-- Attaching to the dock
--------------------------------------------------------------------------------

-- Where (x, y) a point of a rectangle is.
local function pointAt(point, l, b, w, h)
    local x = point:find("LEFT") and l or point:find("RIGHT") and l + w or l + w / 2
    local y = point:find("BOTTOM") and b or point:find("TOP") and b + h or b + h / 2
    return x, y
end

-- A rectangle's offset from the dock's nearest edge: above it, the bar's
-- bottom hangs from the dock's top; below it, its top from the dock's bottom;
-- left, centre or right by the dock's thirds. So a bar above the dock stays
-- above it when the dock grows.
function M:DockOffset(l, b, w, h)
    local dl, db, dw, dh = SuuUI.EditMode.Rect(self.dock)
    local cx = l + w / 2
    local horiz = (cx < dl + dw / 3 and "LEFT") or (cx > dl + dw * 2 / 3 and "RIGHT") or ""
    local vp, vr = "", ""
    if b >= db + dh - 1 then vp, vr = "BOTTOM", "TOP"
    elseif b + h <= db + 1 then vp, vr = "TOP", "BOTTOM" end
    local point = (vp .. horiz ~= "") and (vp .. horiz) or "CENTER"
    local rel = (vr .. horiz ~= "") and (vr .. horiz) or "CENTER"
    local px, py = pointAt(point, l, b, w, h)
    local rx, ry = pointAt(rel, dl, db, dw, dh)
    return { point = point, rel = rel, x = math.floor(px - rx + 0.5), y = math.floor(py - ry + 0.5) }
end

-- Attached: hangs off the dock (and shows and fades with it). Detached: on
-- the screen at its own position.
function M:Place(a)
    local f = a.header
    f:ClearAllPoints()
    if self:Get("attach" .. a.key) then
        f:SetParent(self.dock)
        local o = self:Get("off" .. a.key)
        f:SetPoint(o.point, self.dock, o.rel, o.x, o.y)
    else
        f:SetParent(SuuUI.Root)
        local pos = self:Get(a.pos)
        f:SetPoint(pos.point or "CENTER", SuuUI.Root, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
end

-- Dragged (or nudged) in edit mode: an attached bar is part of the dock, so
-- the whole dock moves by as much, with everything attached to it. A free
-- bar dropped onto the dock (or within 12px of it) attaches there.
function M:Dropped(a, l, b, w, h)
    if self:Get("attach" .. a.key) then
        local cl, cb = SuuUI.EditMode.Rect(a.header)
        local dl, db, dw, dh = SuuUI.EditMode.Rect(self.dock)
        if not (cl and dl) then return true end
        local point, x, y = SuuUI.EditMode.AnchorFor(dl + (l - cl), db + (b - cb), dw, dh)
        local pos = self:Get("position")
        pos.point, pos.x, pos.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
        self:Set("position", pos)
        return true
    end
    local dl, db, dw, dh = SuuUI.EditMode.Rect(self.dock)
    local m = 12
    local touches = l < dl + dw + m and l + w > dl - m and b < db + dh + m and b + h > db - m
    if not touches then return false end
    self:Set("off" .. a.key, self:DockOffset(l, b, w, h))
    self:Set("attach" .. a.key, true)
    return true
end

function M:ToggleAttach(a)
    local l, b, w, h = SuuUI.EditMode.Rect(a.header)
    if not l then return end
    if self:Get("attach" .. a.key) then
        local point, x, y = SuuUI.EditMode.AnchorFor(l, b, w, h)
        local pos = self:Get(a.pos)
        pos.point, pos.x, pos.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
        self:Set(a.pos, pos)
        self:Set("attach" .. a.key, false)
    else
        self:Set("off" .. a.key, self:DockOffset(l, b, w, h))
        self:Set("attach" .. a.key, true)
    end
end

--------------------------------------------------------------------------------
-- XP and reputation
--------------------------------------------------------------------------------

local isSecret = issecretvalue or function() return false end

-- What the foot bar shows: XP below the level cap, else the watched faction.
local function progress()
    local cap = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL or 60
    local xpOff = IsXPUserDisabled and IsXPUserDisabled()
    if UnitLevel("player") < cap and not xpOff then
        return "xp", UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
    end
    local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if data and data.name and data.currentStanding and data.nextReactionThreshold and data.currentReactionThreshold then
        return "rep", data.currentStanding - data.currentReactionThreshold,
            data.nextReactionThreshold - data.currentReactionThreshold, 0, data.name
    end
    if GetWatchedFactionInfo then
        local name, _, low, high, value = GetWatchedFactionInfo()
        if name then return "rep", value - low, high - low, 0, name end
    end
end

function M:UpdateXP()
    local kind, cur, max, rested = progress()
    local shown = kind ~= nil and self:Get("showXP")
    if shown ~= self.xpShown then
        self.xpShown = shown
        self:Arrange()
    end
    if not kind then return end
    self.xp:SetMinMax(0, max)
    self.xp:SetValueNow(cur)
    if isSecret(cur) or isSecret(rested) then
        self.xp.ghost:SetValue(0)
    else
        self.xp.ghost:SetValue(math.min(max, cur + rested))
    end
end

function M:XPTooltip(owner)
    local kind, cur, max, rested, name = progress()
    if not kind or isSecret(cur) or isSecret(max) or max <= 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if kind == "xp" then
        GameTooltip:AddLine(("Level %d"):format(UnitLevel("player")), 1, 1, 1)
        GameTooltip:AddLine(("%s / %s XP (%d%%)"):format(BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max), math.floor(cur / max * 100)), 0.85, 0.85, 0.85)
        if rested > 0 then GameTooltip:AddLine(("Rested %s"):format(BreakUpLargeNumbers(rested)), 0.85, 0.85, 0.85) end
    else
        GameTooltip:AddLine(name, 1, 1, 1)
        GameTooltip:AddLine(("%s / %s"):format(BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max)), 0.85, 0.85, 0.85)
    end
    GameTooltip:Show()
end

local SECTION = {
    id = "actionbars", label = "Action bars", category = "Frames", order = 18,
    groups = {
        { title = "Key bindings", description = "Every bar shows its key bindings; the binding is always in the tooltip too.", rows = {
            { label = "Bind keys", control = "button", text = "Keybind mode",
              description = "Hover a button and press a key, a mouse button or the wheel to bind it. Delete clears. Also /suu keybind.",
              onClick = function() SuuUI.KeybindMode.Enter() end },
            { key = "textSize", label = "Text size", control = "slider", min = 9.5, max = 16, step = 0.5, live = false,
              format = function(v) return ("%gpx"):format(v) end,
              description = "Key bindings, counts and cooldown digits on every bar. 9.5px is the smallest the design allows." },
            { key = "keys1", label = "Bar 1", control = "toggle", description = "The bottom row of the dock. It follows your stance, form or stealth; its tooltips name the page it is on." },
            { key = "keys2", label = "Bar 2", control = "toggle", description = "The row above bar 1." },
            { key = "keys3", label = "Bar 3", control = "toggle", description = "The block left of the middle." },
            { key = "keys4", label = "Bar 4", control = "toggle", description = "The block right of the middle." },
        } },
        { title = "Dock", rows = {
            { key = "showEmpty", label = "Empty slots", control = "toggle",
              description = "Show slots with nothing in them. They always show while you drag a spell or item." },
            { key = "dockSize", label = "Button size", control = "slider", min = 16, max = 32, step = 1, unit = "px", live = false,
              description = "All four bars in the dock at once; the stance and pet bars follow at 9/10 of it. Waits for the end of combat." },
            { key = "dockVisibility", label = "Shows", control = "segmented", options = VISIBILITY,
              description = "Always, only in combat, or when the mouse is over it (or you drag a spell)." },
            { key = "showXP", label = "XP bar", control = "toggle",
              description = "Along the dock's foot: your XP with rested XP after it, or your watched reputation at the level cap. Blizzard's own comes back after a reload." },
        } },
    },
}

table.insert(SECTION.groups, 2, { title = "Stance and pet bars", rows = {
    { key = "showStance", label = "Stance and form bar", control = "toggle",
      description = "Above the dock's left block, for classes with stances, forms or stealth. Blizzard's own comes back after a reload." },
    { key = "keysStance", label = "Its key bindings", control = "toggle", description = "Show the stance bar's key bindings on its buttons." },
    { key = "showPet", label = "Pet bar", control = "toggle",
      description = "Above the dock's right block, while you have a pet. Right click an ability to switch its autocast." },
    { key = "keysPet", label = "Its key bindings", control = "toggle", description = "Show the pet bar's key bindings on its buttons." },
} })

-- One group for each of bars 5-8.
for id = 5, 8 do
    local options = {}
    for _, n in ipairs(COLUMNS) do options[#options + 1] = { value = n, label = tostring(n) } end
    SECTION.groups[#SECTION.groups + 1] = { title = "Bar " .. id, rows = {
        { key = "show" .. id, label = "Show", control = "toggle",
          description = id == 5 and "At the right edge by default; move it in edit mode." or "Next to the bar before it by default; move it in edit mode." },
        { key = "vis" .. id, label = "Shows", control = "segmented", options = VISIBILITY,
          description = "Always, only in combat, or when the mouse is over it (or you drag a spell)." },
        { key = "count" .. id, label = "Buttons", control = "stepper", min = 1, max = 12, step = 1,
          description = "How many of its 12 buttons show." },
        { key = "cols" .. id, label = "Columns", control = "segmented", options = options,
          description = "1 stands it upright, 12 lays it flat." },
        { key = "size" .. id, label = "Button size", control = "slider", min = 16, max = 32, step = 1, unit = "px", live = false,
          description = "Waits for the end of combat." },
        { key = "gap" .. id, label = "Spacing", control = "slider", min = 0, max = 12, step = 1, unit = "px", live = false,
          description = "Between its buttons." },
        { key = "keys" .. id, label = "Key bindings", control = "toggle", description = "Show its key bindings on the buttons." },
    } }
end

function M:OnEnable()
    local function start()
        standDownBlizzard()
        if not self.dock then self:Build() end
        self:ApplyOptions()
    end
    -- Secure buttons can only be made out of combat (a reload mid-fight waits).
    if InCombatLockdown() then self:RunOutOfCombat("build", start) else start() end
    self:RegisterSettings(SECTION)
    local keys = { "textSize", "showEmpty", "showXP", "showStance", "keysStance", "showPet", "keysPet", "dockSize", "dockVisibility", "position" }
    for id = 1, 8 do keys[#keys + 1] = "keys" .. id end
    for id = 5, 8 do
        keys[#keys + 1] = "show" .. id
        keys[#keys + 1] = "cols" .. id
        keys[#keys + 1] = "pos" .. id
        for _, k in ipairs({ "count", "size", "gap", "vis" }) do keys[#keys + 1] = k .. id end
    end
    for _, k in ipairs({ "5", "6", "7", "8", "Stance", "Pet" }) do
        keys[#keys + 1] = "attach" .. k
        keys[#keys + 1] = "off" .. k
    end
    keys[#keys + 1] = "stancePosition"
    keys[#keys + 1] = "petPosition"
    for _, key in ipairs(keys) do
        self:Watch(key, function() if self.dock then self:ApplyOptions() end end)
    end
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" }) do
        self:OnGameEvent(e, function() if self.dock then self:UpdateXP() end end)
    end
    -- Action slots are loaded by the time you enter the world.
    self:OnGameEvent("PLAYER_ENTERING_WORLD", function()
        if self.dock and not self:Get("seeded") then
            self:Seed()
            self:ApplyOptions()
        end
    end)
    if self:Get("showXP") then
        self:OnGameEvent("PLAYER_ENTERING_WORLD", function()
            for _, name in ipairs(TRACKING) do SuuUI.SuppressBlizzard(name) end
        end)
    end
end
