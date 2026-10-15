-- UI/GroupFinderListing.lua
-- The Group Finder's List yourself page (design component GroupFinder,
-- "List yourself"): the game's own listing panel (LFGListingFrame, from
-- Blizzard's secure group finder addon) restyled and laid out in place.
-- Every control stays the game's (addon code can't list you); only looks
-- and places change. What the game keeps on its frames is read, never
-- written: SuuUI's parts live in tables of their own.
--   Top: the role toggles (round, a checkbox on the corner, the role under
--        it); in a group your role, the role dropdown and Role Check; past
--        a rule, New player friendly. A gilt-faint rule under it all.
--   Step 1: "Step 1 of 2 · What are you listing for?" and the categories
--        as cards (glyph, name, a line).
--   Step 2: on the left Playstyle (required: amber until chosen) and Show
--        All Level Ranges over the activities in a sunk tree (chevrons,
--        checkboxes, "4 chosen", level ranges, the lock warning); on the
--        right More details about your group with its count, Voice Chat.
--        Custom: the details across the page.
--   Locked (in a group, not its leader): the game's text in a sunk panel
--        under a lock.
--   Foot: Back (Unlist once listed), List Self (primary; Update once listed).
--
--   UI.SkinGroupFinderListing(LFGListingFrame)

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local TEX = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = TEX .. "Glyphs\\"
local ROLE_TEX = { TANK = TEX .. "RoleTank.tga", HEALER = TEX .. "RoleHealer.tga", DAMAGER = TEX .. "RoleDamage.tga" }
local ROLE_WORD = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }

-- the page inside the window (as the Browse page): 20px in, 24px under the
-- tab rule, 16px above the foot
local SIDE, TOP, BOTTOM = 20, 44, 16
local TOGGLE = 36
local TOP_H = TOGGLE + S["space-2"] + 14          -- a toggle with its word
local RULE_Y = TOP + TOP_H + S["space-4"]         -- the rule under the top
local FOOT_H = 26
local FOOT_RULE = BOTTOM + FOOT_H + S["space-4"]  -- the rule over the foot
local BODY_TOP = RULE_Y + S["space-4"]
local BODY_BOTTOM = FOOT_RULE + S["space-4"]

-- the categories' cards (the game's category IDs on Forever)
local CARDS = {
    [2] = { glyph = "door", text = "Instances for five. Pick every one you’d go to." },
    [116] = { glyph = "scroll", text = "Group quests and elites, one activity per zone." },
    [120] = { glyph = "chat", text = "Anything else, in your own words." },
}

local parts = setmetatable({}, { __mode = "k" })

local function ask(r, method, ...)
    if not r or type(r[method]) ~= "function" then return nil end
    local ok, a, b = pcall(r[method], r, ...)
    if ok then return a, b end
end

local function hideArt(b, keep)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
                           "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = ask(b, get)
        if t then t:SetAlpha(0) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and not (keep and keep[r]) then r:SetAlpha(0) end
    end
end

local function circle(parent, file, color, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(TEX .. file)
    t:SetVertexColor(UI.RGBA(color))
    t:SetAllPoints()
    return t
end

local function glyph(parent, name, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(GLYPHS .. name .. ".tga")
    t:SetSize(size, size)
    t:SetVertexColor(UI.RGBA(color))
    return t
end

local function font(fs, style, color)
    if not fs then return end
    ns.Fonts.Apply(fs, style)
    if color then fs:SetTextColor(UI.RGBA(color)) end
    fs:SetShadowOffset(0, 0)
end

-- A small frame for an edge (a texture's frame level can't rise above its own).
local function edgeOver(parent, color, level)
    local h = CreateFrame("Frame", nil, parent)
    h:SetAllPoints()
    h:EnableMouse(false)
    h:SetFrameLevel(parent:GetFrameLevel() + (level or 2))
    return UI.Border(h, color), h
end

--------------------------------------------------------------------------------
-- The round toggles (RoleToggle): a role's checkbox button, or your role
--------------------------------------------------------------------------------

-- A 14px box over the game's check button, which keeps the click.
local function cornerBox(check, owner)
    hideArt(check)
    check:SetSize(14, 14)
    check:ClearAllPoints()
    check:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 3, -3)
    check:SetFrameLevel(owner:GetFrameLevel() + 4)
    local box = {}
    box.fill = UI.Fill(check, "surface-sunk", "BACKGROUND", 7)
    box.fill:SetAllPoints()
    box.edge = edgeOver(check, "gilt-line")
    box.tick = glyph(check, "check", 10, "on-signal", "OVERLAY")
    box.tick:SetPoint("CENTER")
    return box
end

-- The round icon, its edge, the glyph and the word under it.
local function roundIcon(b, texture, word, glyphSize)
    hideArt(b)
    for _, key in ipairs({ "Background", "cover" }) do if b[key] then b[key]:SetAlpha(0) end end
    b:SetSize(TOGGLE, TOGGLE)
    local p = {}
    p.fill = circle(b, "CircleFill.tga", "surface-sunk", "BACKGROUND", 7)
    -- the band: the thin edge texture broke into dots at 36px (found in game)
    p.edge = circle(b, "CircleBand.tga", "gilt-line", "BORDER", 7)
    p.glyph = b:CreateTexture(nil, "ARTWORK", nil, 7)
    p.glyph:SetTexture(texture)
    p.glyph:SetSize(glyphSize or 18, glyphSize or 18)
    p.glyph:SetPoint("CENTER")
    p.word = UI.Text(b, "caption", "ink-muted")
    p.word:SetPoint("TOP", b, "BOTTOM", 0, -S["space-2"])
    p.word:SetWordWrap(false)
    p.word:SetValue(word)
    return p
end

local function toggle(b, texture, word, glyphSize)
    if parts[b] then return parts[b] end
    local p = roundIcon(b, texture, word, glyphSize)
    local check = b.CheckButton
    p.box = cornerBox(check, b)
    function p.draw()
        local on = ask(check, "GetChecked") and true or false
        local usable = ask(check, "IsEnabled") ~= false and not (b.cover and b.cover:IsShown())
        p.edge:SetVertexColor(UI.RGBA(on and "arcane" or (p.hover and "gilt" or "gilt-line")))
        p.fill:SetVertexColor(UI.RGBA(on and "surface-raised" or "surface-sunk"))
        p.glyph:SetVertexColor(UI.RGBA(on and "ink" or "ink-faint"))
        p.word:SetColor(on and "ink" or "ink-muted")
        p.box.fill:SetColorTexture(UI.RGBA(on and "arcane" or "surface-sunk"))
        p.box.edge:SetColor(on and "arcane" or "gilt-line")
        p.box.tick:SetShown(on)
        b:SetAlpha(usable and 1 or T.opacity["opacity-disabled"])
    end
    hooksecurefunc(check, "SetChecked", p.draw)
    hooksecurefunc(check, "SetEnabled", p.draw)
    check:HookScript("OnClick", p.draw)
    check:HookScript("OnShow", p.draw)
    b:HookScript("OnShow", p.draw)
    b:HookScript("OnEnter", function() p.hover = true; p.draw() end)
    b:HookScript("OnLeave", function() p.hover = false; p.draw() end)
    parts[b] = p
    p.draw()
    return p
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

-- The game's panel button as SuuUI's primary: arcane, on-signal label.
local function primaryButton(b)
    if parts[b] then return end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do if b[key] then b[key]:SetAlpha(0) end end
    hideArt(b)
    local bg = UI.Fill(b, "arcane", "BACKGROUND", 7)
    bg:SetAllPoints()
    local glow = UI.Shadow(b, "glow-arcane")
    glow:SetShown(false)
    local p = {}
    function p.draw()
        b:SetAlpha(ask(b, "IsEnabled") == false and T.opacity["opacity-disabled"] or 1)
        font(ask(b, "GetFontString"), "label", "on-signal")
    end
    b:HookScript("OnEnter", function() if ask(b, "IsEnabled") then glow:SetShown(true) end end)
    b:HookScript("OnLeave", function() glow:SetShown(false) end)
    hooksecurefunc(b, "SetEnabled", p.draw)
    parts[b] = p
    p.draw()
end

-- As wide as its label (the game changes it: Back / Unlist, List Self / Update).
local function fitButton(b)
    local fs = ask(b, "GetFontString")
    local w = fs and fs:GetUnboundedStringWidth() or 60
    b:SetSize(math.max(72, math.ceil(w) + S["space-5"] * 2), FOOT_H)
end

--------------------------------------------------------------------------------
-- The activity tree's rows (the game's ScrollBox rows, set up again on
-- every redraw: restyled after each)
--------------------------------------------------------------------------------

local function rowParts(row)
    local p = parts[row]
    if p then return p end
    p = {}
    local check = row.CheckButton
    hideArt(check)
    p.box = CreateFrame("Frame", nil, check)
    p.box:SetSize(16, 16)
    p.box:SetPoint("CENTER")
    p.box:EnableMouse(false)
    p.fill = UI.Fill(p.box, "surface-sunk")
    p.fill:SetAllPoints()
    p.edge = UI.Border(p.box, "gilt-line")
    p.tick = glyph(p.box, "check", 12, "on-signal", "OVERLAY")
    p.tick:SetPoint("CENTER")
    p.mixed = glyph(p.box, "minus", 12, "on-signal", "OVERLAY")
    p.mixed:SetPoint("CENTER")
    local ec = row.ExpandOrCollapseButton
    hideArt(ec)
    p.chevron = glyph(ec, "chevronDown", 12, "ink-muted", "OVERLAY")
    p.chevron:SetPoint("CENTER")
    p.count = UI.Text(row, "caption", "ink-faint")
    p.count:SetPoint("RIGHT", row, "RIGHT", -S["space-4"], 0)
    if row.InstanceLockWarningIcon then
        for _, r in ipairs({ row.InstanceLockWarningIcon:GetRegions() }) do r:SetAlpha(0) end
        p.lock = glyph(row.InstanceLockWarningIcon, "lock", 12, "amber", "OVERLAY")
        p.lock:SetPoint("CENTER")
    end
    -- after a click, the row's own box: the game redraws only the group's
    -- heading and relies on the check button's own tick, which is hidden
    -- (found in game). PostClick, since the game sets OnClick on each setup.
    check:HookScript("PostClick", function()
        if p.redraw then p.redraw() end
    end)
    parts[row] = p
    return p
end

local function drawBox(p, state)
    p.fill:SetColorTexture(UI.RGBA(state and "arcane" or "surface-sunk"))
    p.edge:SetColor(state and "arcane" or "gilt-line")
    p.tick:SetShown(state == "all")
    p.mixed:SetShown(state == "some")
end

local function skinGroupRow(row, data, collapsed)
    if not (row and data and row.CheckButton) then return end
    local p = rowParts(row)
    p.redraw = nil -- the game sets the heading up again after its clicks
    local f = _G.LFGListingFrame
    local all = f and ask(f, "AreAllActivitiesForActivityGroupSelected", data.activityGroupID)
    local any = f and ask(f, "IsAnyActivityForActivityGroupSelected", data.activityGroupID)
    drawBox(p, all and "all" or (any and "some") or nil)
    p.chevron:SetTexture(GLYPHS .. (collapsed and "chevronRight" or "chevronDown") .. ".tga")
    font(row.NameButton and row.NameButton.Name, "header", "gilt-text")
    if row.NameButton and row.NameButton.Name then row.NameButton:SetWidth(row.NameButton.Name:GetUnboundedStringWidth()) end
    -- how many are chosen ("4 chosen"), else how many there are
    local node = ask(row, "GetElementData")
    local chosen, total = 0, 0
    for _, child in ipairs(node and node.nodes or {}) do
        local d = ask(child, "GetData")
        if d and d.activityID then
            total = total + 1
            if f and ask(f, "IsActivitySelected", d.activityID) then chosen = chosen + 1 end
        end
    end
    p.count:SetValue(chosen > 0 and (chosen .. " chosen") or (total > 0 and tostring(total) or ""))
    p.count:Show()
end

local function skinActivityRow(row, data)
    if not (row and data and row.CheckButton) then return end
    local p = rowParts(row)
    local f = _G.LFGListingFrame
    p.redraw = function() drawBox(p, f and ask(f, "IsActivitySelected", data.activityID) and "all" or nil) end
    p.redraw()
    p.count:Hide()
    -- the game's difficulty colours, in SuuUI's quest colours
    local lvl = UnitLevel("player")
    local color = "ink"
    if data.maxLevel and data.maxLevel ~= 0 and data.maxLevel < lvl then color = "quest-trivial"
    elseif data.minLevel and data.minLevel ~= 0 and data.minLevel > lvl then color = "quest-difficult" end
    local name = row.NameButton and row.NameButton.Name
    font(name, "body", color)
    if name then row.NameButton:SetWidth(name:GetUnboundedStringWidth()) end
    -- "20 - 30" in caption ink-muted, at the right
    font(row.Level, "caption", "ink-muted")
    local text = row.Level and row.Level:GetText()
    if type(text) == "string" then row.Level:SetText((text:gsub("[()]", ""))) end
    if row.Level then
        row.Level:SetJustifyH("RIGHT")
        row.Level:ClearAllPoints()
        row.Level:SetPoint("RIGHT", row, "RIGHT", -S["space-4"], 0)
    end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local L = {}

function L:LayoutTop()
    local f = self.frame
    local solo = f.SoloRoleButtons
    local group = f.GroupRoleButtons
    local inGroup = group and group:IsShown()
    local slot = 60
    local x
    if solo then
        solo:ClearAllPoints()
        solo:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -TOP)
        solo:SetSize(slot * 3, TOP_H)
        local prev
        for i, key in ipairs({ "Tank", "Healer", "DPS" }) do
            local b = solo[key]
            if b then
                b:ClearAllPoints()
                b:SetPoint("TOP", solo, "TOPLEFT", slot * (i - 0.5), 0)
                prev = b
            end
        end
    end
    if group then
        group:ClearAllPoints()
        group:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -TOP)
        local icon, dd, poll = group.RoleIcon, group.RoleDropdown, group.RolePollButton
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOP", group, "TOPLEFT", slot / 2, 0)
        end
        if dd then
            dd:ClearAllPoints()
            dd:SetSize(120, 30)
            dd:SetPoint("LEFT", group, "TOPLEFT", slot + S["space-4"], -TOGGLE / 2)
        end
        if poll then
            fitButton(poll)
            poll:ClearAllPoints()
            poll:SetPoint("LEFT", dd or group, "RIGHT", S["space-5"], 0)
        end
        local w = slot + S["space-4"] + 120 + S["space-5"] + (poll and poll:GetWidth() or 0)
        group:SetSize(w, TOP_H)
    end
    -- New player friendly past a rule, after whichever role row shows
    x = (inGroup and group:GetWidth() or slot * 3) + S["space-6"]
    self.npfRule:ClearAllPoints()
    self.npfRule:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE + x, -TOP)
    self.npfRule:SetSize(1, TOP_H)
    local npf = f.NewPlayerFriendlyButton
    if npf then
        npf:ClearAllPoints()
        npf:SetPoint("TOP", f, "TOPLEFT", SIDE + x + 1 + S["space-6"] + 55, -TOP)
    end
end

function L:LayoutCategories()
    local view = self.frame.CategoryView
    if not (view and view:IsShown()) then return end
    local shown = {}
    for _, b in ipairs(view.CategoryButtons or {}) do if b:IsShown() then shown[#shown + 1] = b end end
    local gap = S["space-5"]
    local width = view:GetWidth()
    if not width or width < 10 then return end
    local cw = math.floor((width - gap * (#shown - 1)) / math.max(1, #shown))
    for i, b in ipairs(shown) do
        local p = parts[b]
        if not p then
            p = {}
            for _, key in ipairs({ "Icon", "Cover" }) do if b[key] then b[key]:SetAlpha(0) end end
            hideArt(b)
            p.fill = UI.Fill(b, "surface-sunk", "BACKGROUND", 7)
            p.fill:SetAllPoints()
            p.edge = edgeOver(b, "gilt-line")
            p.glyph = glyph(b, "flag", 22, "gilt-text", "OVERLAY")
            p.glyph:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
            p.line = UI.Text(b, "caption", "ink-muted")
            p.line:SetJustifyH("LEFT")
            p.line:SetWordWrap(true)
            b:HookScript("OnEnter", function() p.edge:SetColor("gilt"); p.fill:SetColorTexture(UI.RGBA("surface-raised")) end)
            b:HookScript("OnLeave", function() p.edge:SetColor("gilt-line"); p.fill:SetColorTexture(UI.RGBA("surface-sunk")) end)
            -- a ResizeLayoutFrame: its own size, not its children's
            b.fixedWidth, b.fixedHeight = cw, 132
            parts[b] = p
        end
        local card = CARDS[b.categoryID] or {}
        p.glyph:SetTexture(GLYPHS .. (card.glyph or "flag") .. ".tga")
        p.line:SetValue(card.text or "")
        b:ClearAllPoints()
        b:SetSize(cw, 132)
        b:SetPoint("TOPLEFT", view, "TOPLEFT", (i - 1) * (cw + gap), -(14 + S["space-4"]))
        local label = b.Label or ask(b, "GetFontString")
        if label then
            font(label, "header", "gilt-text")
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", p.glyph, "BOTTOMLEFT", 0, -S["space-3"])
            p.line:ClearAllPoints()
            p.line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -S["space-3"])
            p.line:SetWidth(cw - S["space-5"] * 2)
        end
    end
end

function L:LayoutActivities()
    local f = self.frame
    local av = f.ActivityView
    if not av then return end
    local width = f:GetWidth() - SIDE * 2
    local custom = av.ScrollBox and not av.ScrollBox:IsShown()
    local left = custom and width or math.floor((width - S["space-6"]) * 0.56)
    local rightX = custom and 0 or (left + S["space-6"])
    local rightW = width - rightX
    -- Playstyle (required by the game in every category) and Show All Level Ranges
    local missing = av.PlayStyleDropdown and not av.generalPlaystyle
    self.psLabel:SetValue("Playstyle |cff" .. T.color[missing and "amber" or "ink-muted"].hex .. "· required|r")
    self.psLabel:ClearAllPoints()
    self.psLabel:SetPoint("TOPLEFT", av, "TOPLEFT", 0, 0)
    local dd = av.PlayStyleDropdown
    if dd then
        dd:ClearAllPoints()
        dd:SetSize(200, 30)
        dd:SetPoint("TOPLEFT", av, "TOPLEFT", 0, -(14 + S["space-1"]))
        if self.psMissing then self.psMissing:SetShown(missing and true or false) end
    end
    local lr = av.LevelRangesCheckbox
    if lr and lr.Text and lr.Checkbox then
        lr.Text:ClearAllPoints()
        lr.Text:SetPoint("RIGHT", av, "TOPLEFT", left, -(14 + S["space-1"] + 15))
        lr.Checkbox:ClearAllPoints()
        lr.Checkbox:SetPoint("RIGHT", lr.Text, "LEFT", -S["space-2"], 0)
        lr:SetShown(not custom)
    end
    -- under the Playstyle / Voice Chat row and room for the details' label
    -- (it overlapped Voice Chat), so the tree and the field start level
    local treeTop = 14 + S["space-1"] + 30 + S["space-4"] + 14 + S["space-1"]
    self.tree:ClearAllPoints()
    self.tree:SetPoint("TOPLEFT", av, "TOPLEFT", 0, -treeTop)
    self.tree:SetPoint("BOTTOMLEFT", av, "BOTTOMLEFT", 0, 0)
    self.tree:SetWidth(left)
    self.tree:SetShown(not custom)
    self:PlaceScrollBox()
    -- Voice Chat in the Playstyle row (asked for in game): at the right
    -- column's start, or at the page's right in Custom
    local vlabel, vdd = av.VoiceChatLabel, av.VoiceChatDropdown
    if vlabel and vdd then
        local vx = custom and (width - 200) or rightX
        vlabel:ClearAllPoints()
        vlabel:SetPoint("TOPLEFT", av, "TOPLEFT", vx, 0)
        vlabel:SetJustifyH("LEFT")
        vdd:ClearAllPoints()
        vdd:SetSize(200, 30)
        vdd:SetPoint("TOPLEFT", av, "TOPLEFT", vx, -(14 + S["space-1"]))
    end
    -- the details: a sunk field from the activity tree's top to its foot
    -- (asked for in game), its label over it with the count at the right;
    -- in Custom (no tree) across the page from the same top
    local detailsTop = treeTop - (14 + S["space-1"])
    self.detailsLabel:ClearAllPoints()
    self.detailsLabel:SetPoint("TOPLEFT", av, "TOPLEFT", rightX, -detailsTop)
    self.detailsLabel:SetValue("More details about your group" .. (custom and "" or
        (" |cff" .. T.color["ink-faint"].hex .. "· optional|r")))
    self.field:ClearAllPoints()
    self.field:SetPoint("TOPLEFT", av, "TOPLEFT", rightX, -treeTop)
    self.field:SetPoint("BOTTOMLEFT", av, "BOTTOMLEFT", rightX, 0)
    self.field:SetWidth(rightW)
    local c = av.Comment
    -- the placeholder: the label says what the field is (the game's
    -- authenticator note stays as it is)
    local instr = c and c.EditBox and c.EditBox.Instructions
    local said = instr and instr:GetText()
    if said and (said == _G.DESCRIPTION_OF_YOUR_GROUP or said == _G.DESCRIPTION_OF_YOUR_GROUP_MANDATORY) then
        instr:SetText(custom and "What you’re after, for a Custom listing" or "Route, quests, gear check: anything people should know")
    end
    if c then
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", self.field, "TOPLEFT", S["space-4"], -S["space-3"])
        c:SetPoint("BOTTOMRIGHT", self.field, "BOTTOMRIGHT", -S["space-4"] - 12, S["space-3"])
        if c.EditBox then c.EditBox:SetWidth(rightW - S["space-4"] * 2 - 16) end
    end
    self.count:ClearAllPoints()
    self.count:SetPoint("BOTTOMRIGHT", self.field, "TOPRIGHT", 0, S["space-1"])
    self:UpdateCount()
end

-- The game anchors its list again whenever its scrollbar comes or goes:
-- inside the sunk tree, every time.
function L:PlaceScrollBox()
    local box = self.frame.ActivityView and self.frame.ActivityView.ScrollBox
    if not box or self.placing then return end
    self.placing = true
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", self.tree, "TOPLEFT", 1, -S["space-2"])
    box:SetPoint("BOTTOMRIGHT", self.tree, "BOTTOMRIGHT", -14, S["space-2"])
    self.placing = false
    local bar = self.frame.ActivityView.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", self.tree, "TOPRIGHT", -10, -S["space-3"])
        bar:SetPoint("BOTTOMLEFT", self.tree, "BOTTOMRIGHT", -10, S["space-3"])
    end
end

function L:UpdateCount()
    local e = self.frame.ActivityView and self.frame.ActivityView.Comment and self.frame.ActivityView.Comment.EditBox
    local text = e and ask(e, "GetText")
    local n = type(text) == "string" and (strlenutf8 and strlenutf8(text) or #text) or 0
    self.count:SetValue(n .. " / 255")
end

function L:LayoutLocked()
    local lv = self.frame.LockedView
    if not (lv and lv:IsShown()) then return end
    UI.Reskin(lv)
    if lv.ErrorText then
        font(lv.ErrorText, "label", "ink")
        lv.ErrorText:ClearAllPoints()
        lv.ErrorText:SetPoint("TOP", self.lockGlyph, "BOTTOM", 0, -S["space-3"])
        lv.ErrorText:SetWidth(lv:GetWidth() - S["space-6"] * 2)
        lv.ErrorText:SetJustifyH("CENTER")
    end
    if lv.ActivityText then font(lv.ActivityText, "caption", "ink-muted") end
end

function L:LayoutFoot()
    local f = self.frame
    for _, b in ipairs({ f.BackButton, f.PostButton }) do fitButton(b) end
    f.BackButton:ClearAllPoints()
    f.BackButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SIDE, BOTTOM)
    f.PostButton:ClearAllPoints()
    f.PostButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, BOTTOM)
end

function L:Layout()
    self:LayoutTop()
    self:LayoutCategories()
    self:LayoutActivities()
    self:LayoutLocked()
    self:LayoutFoot()
end

-- Again after the game's next redraw (a frame later, once it has drawn).
function L:Queue()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, function()
        self.queued = false
        if self.frame:IsShown() then self:Layout() end
    end)
end

local skinned

function UI.SkinGroupFinderListing(f)
    if not f or skinned then return skinned end
    local s = setmetatable({ frame = f }, { __index = L })
    skinned = s

    -- the rules under the top and over the foot, and between the roles and New player friendly
    s.topRule = UI.Fill(f, "gilt-faint", "ARTWORK")
    s.topRule:SetHeight(1)
    s.topRule:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -RULE_Y)
    s.topRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, -RULE_Y)
    s.footRule = UI.Fill(f, "gilt-faint", "ARTWORK")
    s.footRule:SetHeight(1)
    s.footRule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SIDE, FOOT_RULE)
    s.footRule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, FOOT_RULE)
    s.npfRule = UI.Fill(f, "gilt-faint", "ARTWORK")

    -- the top: the role toggles, your role in a group, New player friendly
    local solo = f.SoloRoleButtons
    for key, role in pairs({ Tank = "TANK", Healer = "HEALER", DPS = "DAMAGER" }) do
        if solo and solo[key] and solo[key].CheckButton then toggle(solo[key], ROLE_TEX[role], ROLE_WORD[role]) end
    end
    local group = f.GroupRoleButtons
    if group then
        if group.RoleIcon then
            local icon = group.RoleIcon
            local p = roundIcon(icon, ROLE_TEX.DAMAGER, "")
            p.edge:SetVertexColor(UI.RGBA("arcane"))
            p.fill:SetVertexColor(UI.RGBA("surface-raised"))
            p.glyph:SetVertexColor(UI.RGBA("ink"))
            p.word:SetColor("ink")
            local function update()
                local role = icon.roleID
                p.glyph:SetTexture(ROLE_TEX[role] or ROLE_TEX.DAMAGER)
                p.word:SetValue(ROLE_WORD[role] or "")
                -- the game sets its own art again
                local n = ask(icon, "GetNormalTexture")
                if n then n:SetAlpha(0) end
            end
            hooksecurefunc("LFGListingRoleIcon_UpdateRoleTexture", function(b) if b == icon then update() end end)
            icon:HookScript("OnShow", update)
            update()
            parts[icon] = p
        end
        if group.RoleDropdown then UI.ReskinDropdown(group.RoleDropdown) end
        if group.RolePollButton then UI.ReskinButton(group.RolePollButton) end
        group:HookScript("OnShow", function() s:Queue() end)
        group:HookScript("OnHide", function() s:Queue() end)
    end
    local npf = f.NewPlayerFriendlyButton
    if npf and npf.CheckButton then
        toggle(npf, GLYPHS .. "leaf.tga", _G.LFG_LIST_NEW_PLAYER_FRIENDLY or "New player friendly", 16)
    end

    -- step 1: the hint over the cards
    local view = f.CategoryView
    if view then
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -(RULE_Y + S["space-5"]))
        view:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, BODY_BOTTOM)
        s.hint = UI.Text(view, "caption", "ink-muted")
        s.hint:SetPoint("TOPLEFT")
        s.hint:SetValue("Step 1 of 2 · What are you listing for?")
        view:HookScript("OnShow", function() s:Queue() end)
        if _G.LFGListingCategorySelection_UpdateCategoryButtons then
            hooksecurefunc("LFGListingCategorySelection_UpdateCategoryButtons", function() s:Queue() end)
        end
    end

    -- step 2
    local av = f.ActivityView
    if av then
        av:ClearAllPoints()
        av:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -BODY_TOP)
        av:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, BODY_BOTTOM)
        for _, key in ipairs({ "BarTop", "BarMiddle" }) do if av[key] then av[key]:SetAlpha(0) end end
        for _, t in ipairs(av.BarComponents or {}) do t:SetAlpha(0) end
        s.psLabel = UI.Text(av, "caption", "ink-muted")
        if av.PlayStyleDropdown then
            UI.ReskinDropdown(av.PlayStyleDropdown)
            -- amber until a play style is chosen
            local _, holder = edgeOver(av.PlayStyleDropdown, "amber", 3)
            s.psMissing = holder
        end
        local lr = av.LevelRangesCheckbox
        if lr then
            if lr.Checkbox then UI.ReskinCheckButton(lr.Checkbox) end
            font(lr.Text, "body", "ink")
        end
        s.tree = CreateFrame("Frame", nil, av)
        s.tree:SetFrameLevel(math.max(0, (av.ScrollBox and av.ScrollBox:GetFrameLevel() or av:GetFrameLevel() + 1) - 1))
        UI.Fill(s.tree, "surface-sunk"):SetAllPoints()
        UI.Border(s.tree, "gilt-faint")
        if av.ScrollBox then
            hooksecurefunc(av.ScrollBox, "SetPoint", function() s:PlaceScrollBox() end)
        end
        if av.ScrollBar then UI.ReskinScrollBar(av.ScrollBar) end
        -- the details
        s.detailsLabel = UI.Text(av, "caption", "ink-muted")
        s.field = CreateFrame("Frame", nil, av)
        UI.Fill(s.field, "surface-sunk"):SetAllPoints()
        local edge = UI.Border(s.field, "gilt-line")
        s.count = UI.Text(av, "caption", "ink-faint")
        local c = av.Comment
        if c then
            s.field:SetFrameLevel(math.max(0, c:GetFrameLevel() - 1))
            for _, r in ipairs({ c:GetRegions() }) do
                if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
            end
            if c.ScrollBar then UI.ReskinScrollBar(c.ScrollBar) end
            local e = c.EditBox
            if e then
                e:SetFontObject(ns.Fonts.Get("body"))
                e:SetTextColor(UI.RGBA("ink"))
                font(e.Instructions, "body", "ink-muted")
                e:HookScript("OnTextChanged", function() s:UpdateCount() end)
                e:HookScript("OnEditFocusGained", function() edge:SetColor("arcane") end)
                e:HookScript("OnEditFocusLost", function() edge:SetColor("gilt-line") end)
            end
        end
        if av.VoiceChatDropdown then UI.ReskinDropdown(av.VoiceChatDropdown) end
        font(av.VoiceChatLabel, "caption", "ink-muted")
        -- the game places its parts again on show; after it
        av:HookScript("OnShow", function() s:LayoutActivities(); s:Queue() end)
        hooksecurefunc("LFGListingActivityView_OnPlayStyleSelectedInternal", function() s:LayoutActivities() end)
    end
    -- the tree's rows, each time the game sets one up
    hooksecurefunc("LFGListingActivityView_InitActivityGroupButton", skinGroupRow)
    hooksecurefunc("LFGListingActivityView_InitActivityButton", skinActivityRow)

    -- locked: the game's text in a sunk panel under a lock
    local lv = f.LockedView
    if lv then
        lv:ClearAllPoints()
        lv:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -(RULE_Y + S["space-5"]))
        lv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, BOTTOM)
        local bg = UI.Fill(lv, "surface-sunk", "BACKGROUND", -8)
        bg:SetAllPoints()
        UI.Border(lv, "gilt-faint")
        s.lockGlyph = glyph(lv, "lock", 24, "ink-faint")
        s.lockGlyph:SetPoint("TOP", lv, "TOP", 0, -S["space-6"] * 2)
        lv:HookScript("OnShow", function() s:Queue() end)
        if _G.LFGListingLockedView_RefreshContent then
            hooksecurefunc("LFGListingLockedView_RefreshContent", function() s:Queue() end)
        end
    end

    -- the foot
    UI.ReskinButton(f.BackButton)
    primaryButton(f.PostButton)
    for _, name in ipairs({ "LFGListingPostButton_UpdateText", "LFGListingBackButton_UpdateText" }) do
        if _G[name] then hooksecurefunc(name, function() s:LayoutFoot() end) end
    end
    hooksecurefunc(f, "UpdatePostButtonEnableState", function()
        if parts[f.PostButton] then parts[f.PostButton].draw() end
        s:LayoutActivities()
    end)
    hooksecurefunc(f, "UpdateFrameView", function() s:Queue() end)
    f:HookScript("OnShow", function() s:Layout(); s:Queue() end)
    if f:IsShown() then s:Layout() end
    return s
end
