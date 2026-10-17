-- Units/Macros.lua
-- SuuUI's own macro window (plan 3.7, design component MacroWindow,
-- direction A "Tabs", chosen 2026-10-17): General and this character's
-- macros as two tabs, each with how many are used; the list on the left
-- (icon, name, first line); the editor on the right: the icon to drag to a
-- bar, the name (16 letters), Change icon (a picker: every macro icon,
-- spells or items, a search over your spells and the items in your bags, a
-- drop zone for a spell, item or macro), the body (255 letters); New, Delete
-- and Save. The game forbids changing macros in combat: everything waits
-- then, and says why. MacroFrame isn't protected and the macro calls are
-- free out of combat (/suu probe windows, 2026-10-17); the game's window is
-- closed and this one opens instead (/macro, the game menu).
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "macros",
    name = "Macros",
    description = "SuuUI's macro window: general and character macros as tabs, an editor with the icon to drag, an icon picker with search.",
    api = "0.17",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local WIDTH, HEIGHT = 780, 580
local LIST_W = 270
local ROW_H = 44
local QUESTION = 134400 -- the "?" icon: the macro shows its first spell's
local MAX_GENERAL = MAX_ACCOUNT_MACROS or 120
local MAX_CHAR = MAX_CHARACTER_MACROS or 18
local NAME_MAX, BODY_MAX = 16, 255
local COMBAT = "Macros can't be changed in combat"
local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

-- The macros of a tab: { index, name, icon, body }.
function M:List(tab)
    local general, char = GetNumMacros()
    local list = {}
    local first, count = 1, general or 0
    if tab == "character" then first, count = MAX_GENERAL + 1, char or 0 end
    for i = first, first + count - 1 do
        local name, icon, body = GetMacroInfo(i)
        if name then list[#list + 1] = { index = i, name = name, icon = icon, body = body or "" } end
    end
    return list
end

function M:Counts()
    local general, char = GetNumMacros()
    return general or 0, char or 0
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:BuildRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.hover = UI.Fill(r, "surface-raised", "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.on = UI.Fill(r, "arcane-soft", "BACKGROUND", 1)
    r.on:SetAllPoints()
    r.edge = UI.Fill(r, "arcane", "ARTWORK")
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(2)
    r.icon = UI.Icon(r, "icon-lg")
    r.icon:SetPoint("LEFT", S["space-3"], 0)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", S["space-4"], -2)
    r.name:SetPoint("RIGHT", -S["space-3"], 0)
    r.first = UI.Text(r, "caption", "ink-faint")
    r.first:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.first:SetPoint("RIGHT", -S["space-3"], 0)
    r.first:SetWordWrap(false)
    r.name:SetWordWrap(false)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self) self.owner:Select(self.macro) end)
    r:SetScript("OnDragStart", function(self) if self.macro then PickupMacro(self.macro.index) end end)
    r.owner = self
    return r
end

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIMacroWindow", title = "Macros", width = WIDTH, height = HEIGHT,
        footer = true, onClose = function(win) win:Hide() end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w.scroll:Hide()
    w:HookScript("OnHide", function() self:ClosePicker() end)
    self.window = w
    local body = w.body

    -- the list: the two tabs, the count, the macros
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    local rule = UI.Fill(body, "gilt-faint", "ARTWORK")
    rule:SetPoint("TOPLEFT", left, "TOPRIGHT", S["space-5"], 0)
    rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", S["space-5"], 0)
    rule:SetWidth(1)
    local who = UnitName("player") or "Character"
    self.tabs = UI.Segmented(left, { options = { { value = "general", label = "General Macros" },
        { value = "character", label = who .. " Specific Macros" } }, value = "general", onChange = function(v)
            self.tab = v
            self.draft, self.chosen = nil, nil
            self:Refresh()
        end })
    self.tabs:SetPoint("TOPLEFT")
    -- the two tabs share the list's width (by their labels' widths; a long
    -- name gets the short labels)
    local function fit(labels)
        local inner = LIST_W - 6 - 2
        local text = 0
        for i, b in ipairs(self.tabs.buttons) do
            b.label:SetValue(labels[i])
            text = text + UI.MeasureText("label", labels[i])
        end
        local pad = (inner - text) / #self.tabs.buttons
        if pad < 2 * S["space-3"] then return false end
        local x = 3
        for i, b in ipairs(self.tabs.buttons) do
            b:SetWidth(UI.MeasureText("label", labels[i]) + pad)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -3)
            x = x + b:GetWidth() + 2
        end
        return true
    end
    if not fit({ "General Macros", who .. " Specific Macros" }) and not fit({ "General", who }) then
        fit({ "General", "Character" })
    end
    self.tabs:SetWidth(LIST_W)
    self.count = UI.Text(left, "caption", "ink-muted")
    self.count:SetPoint("TOPLEFT", self.tabs, "BOTTOMLEFT", 0, -S["space-3"])
    local BAR = S["space-3"]
    self.list = UI.ScrollArea(left, BAR)
    self.list:SetPoint("TOPLEFT", self.count, "BOTTOMLEFT", 0, -S["space-4"])
    self.list:SetPoint("BOTTOMRIGHT", -(BAR + 3), 0)
    self.list:HookScript("OnSizeChanged", function(scroll, width) scroll.child:SetWidth(width) end)
    self.none = UI.Text(left, "caption", "ink-muted")
    self.none:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -S["space-5"])
    self.none:SetValue("No macros here yet.")
    self.rows = {}

    -- the editor
    local edit = CreateFrame("Frame", nil, body)
    edit:SetPoint("TOPLEFT", left, "TOPRIGHT", S["space-6"] + 1, 0)
    edit:SetPoint("BOTTOMRIGHT")
    self.edit = edit
    -- in combat: an ember band on top
    local band = CreateFrame("Frame", nil, edit)
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(28)
    UI.Fill(band, "ember-soft"):SetAllPoints()
    UI.Border(band, "ember")
    band.text = UI.Text(band, "caption", "ember-text")
    band.text:SetPoint("LEFT", S["space-4"], 0)
    band.text:SetValue(COMBAT)
    band:Hide()
    self.band = band
    local id = CreateFrame("Frame", nil, edit)
    id:SetPoint("TOPLEFT")
    id:SetPoint("TOPRIGHT")
    id:SetHeight(70)
    self.idRow = id
    -- the icon: drag it to a bar
    local big = UI.ItemSlot(id, 52)
    big:SetPoint("TOPLEFT")
    big:RegisterForDrag("LeftButton")
    big:SetScript("OnDragStart", function()
        if self.chosen then PickupMacro(self.chosen.index) end
    end)
    big:SetScript("OnEnter", function(b)
        UI.ShowTooltip(b, { title = self.chosen and "Drag to a bar" or "Save it first", description = self.chosen and self.chosen.name or nil })
    end)
    big:SetScript("OnLeave", function() UI.HideTooltip() end)
    self.big = big
    local drag = UI.Text(id, "micro", "ink-muted")
    drag:SetPoint("TOP", big, "BOTTOM", 0, -S["space-2"])
    drag:SetValue("Drag to a bar")
    self.dragHint = drag
    local nameLabel = UI.Text(id, "caption", "ink-muted")
    nameLabel:SetPoint("TOPLEFT", big, "TOPRIGHT", S["space-5"], 0)
    nameLabel:SetValue("Name")
    self.nameCount = UI.Text(id, "numeric", "ink-muted")
    self.nameCount:SetPoint("TOPRIGHT", 0, 1)
    self.iconButton = UI.Button(id, { text = "Change icon", icon = "gem", onClick = function() self:TogglePicker() end })
    -- the field and Change icon on one line, under the label
    local fieldY = -(T.type.caption.lineHeight + S["space-2"])
    self.iconButton:SetPoint("TOPRIGHT", 0, fieldY)
    self.nameField = UI.TextField(id, { onTextChanged = function() self:DrawState() end, onChange = function() self:DrawState() end })
    self.nameField:SetPoint("TOPLEFT", big, "TOPRIGHT", S["space-5"], fieldY)
    self.nameField:SetPoint("RIGHT", self.iconButton, "LEFT", -S["space-4"], 0)
    self.nameField.edit:SetMaxLetters(NAME_MAX)
    -- the body
    local bodyLabel = UI.Text(edit, "caption", "ink-muted")
    bodyLabel:SetPoint("TOPLEFT", id, "BOTTOMLEFT", 0, -S["space-4"])
    bodyLabel:SetValue("Body")
    self.bodyCount = UI.Text(edit, "numeric", "ink-muted")
    self.bodyCount:SetPoint("TOPRIGHT", id, "BOTTOMRIGHT", 0, -S["space-4"] + 1)
    local well = CreateFrame("Frame", nil, edit)
    well:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 0, -S["space-2"])
    well:SetPoint("BOTTOMRIGHT")
    UI.Fill(well, "surface-sunk"):SetAllPoints()
    well.border = UI.Border(well, "gilt-line")
    local scroll = UI.ScrollArea(well, -S["space-3"])
    scroll:SetPoint("TOPLEFT", S["space-4"], -S["space-3"])
    scroll:SetPoint("BOTTOMRIGHT", -S["space-5"], S["space-3"])
    local e = CreateFrame("EditBox", nil, scroll.child)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(self.nameField.edit:GetFontObject())
    e:SetMaxLetters(BODY_MAX)
    e:SetPoint("TOPLEFT")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function() well.border:SetColor("arcane") end)
    e:SetScript("OnEditFocusLost", function() well.border:SetColor("gilt-line") end)
    e:SetScript("OnTextChanged", function(box)
        scroll.child:SetHeight(math.max(scroll:GetHeight(), box:GetHeight()))
        if box.lastText ~= box:GetText() then
            box.lastText = box:GetText()
            self:DrawState()
        end
    end)
    scroll:HookScript("OnSizeChanged", function(sc, width) sc.child:SetWidth(width); e:SetWidth(width) end)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() if not InCombatLockdown() then e:SetFocus() end end)
    self.body, self.well = e, well

    -- nothing at all yet
    local empty = CreateFrame("Frame", nil, body)
    empty:SetPoint("TOPLEFT", edit)
    empty:SetPoint("BOTTOMRIGHT", edit)
    empty.title = UI.Text(empty, "alert", "ink")
    empty.title:SetPoint("CENTER", 0, 40)
    empty.title:SetValue("No macros yet")
    empty.text = UI.Text(empty, "body", "ink-muted")
    empty.text:SetWordWrap(true)
    empty.text:SetJustifyH("CENTER")
    empty.text:SetFixedWidth(340)
    empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -S["space-4"])
    empty.text:SetValue("A macro is a button that runs a few lines: a cast with a target, a line in chat, several things at once. Make one, then drag its icon to a bar.")
    empty.new = UI.Button(empty, { text = "New macro", icon = "plus", variant = "primary", onClick = function() self:New() end })
    empty.new:SetPoint("TOP", empty.text, "BOTTOM", 0, -S["space-5"])
    empty:Hide()
    self.empty = empty

    -- the foot
    local foot = w.footer
    self.hint = UI.Text(foot, "caption", "ink-muted")
    self.hint:SetPoint("LEFT")
    self.save = UI.Button(foot, { text = "Save", variant = "primary", width = 90, onClick = function() self:Save() end })
    self.save:SetPoint("RIGHT")
    self.delete = UI.Button(foot, { text = "Delete", icon = "trash", onClick = function() self:Delete() end })
    self.delete:SetPoint("RIGHT", self.save, "LEFT", -S["space-4"], 0)
    self.new = UI.Button(foot, { text = "New", icon = "plus", onClick = function() self:New() end })
    self.new:SetPoint("RIGHT", self.delete, "LEFT", -S["space-4"], 0)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function M:Refresh()
    if not (self.window and self.window:IsShown()) then return end
    local tab = self.tab or "general"
    self.tabs:SetValue(tab)
    local list = self:List(tab)
    self.macros = list
    local general, char = self:Counts()
    local used, max = tab == "general" and general or char, tab == "general" and MAX_GENERAL or MAX_CHAR
    self.count:SetValue(("%d of %d used"):format(used, max))
    -- keep the chosen macro (by name: indexes shift when one is added or removed)
    if self.chosen then
        local found
        for _, m in ipairs(list) do if m.name == self.chosen.name then found = m end end
        self.chosen = found
    end
    if not self.chosen and not self.draft then self.chosen = list[1] end
    local c = self.list.child
    local y = 0
    for i, m in ipairs(list) do
        local r = self.rows[i] or self:BuildRow(c)
        self.rows[i] = r
        r.macro = m
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT")
        r.icon:SetArt(m.icon)
        r.name:SetValue(m.name)
        r.first:SetValue((m.body:match("^[^\n]*") or ""))
        local on = self.chosen and self.chosen.index == m.index and not self.draft
        r.on:SetShown(on and true or false)
        r.edge:SetShown(on and true or false)
        r:Show()
        y = y + ROW_H + 1
    end
    for i = #list + 1, #self.rows do self.rows[i]:Hide() end
    c:SetHeight(math.max(1, y))
    self.none:SetShown(#list == 0 and not self.draft)
    -- nothing at all: the empty page instead of the editor
    local nothing = general == 0 and char == 0 and not self.draft
    self.empty:SetShown(nothing)
    self.edit:SetShown(not nothing)
    self:Load(self.draft or self.chosen)
end

-- Puts a macro (or a new one) into the editor.
function M:Load(m)
    self.loaded = m
    self.icon = m and m.icon or QUESTION
    self.nameField:SetValue(m and m.name or "")
    self.body:SetText(m and m.body or "")
    self.body.lastText = self.body:GetText()
    self:DrawState()
end

function M:Dirty()
    local m = self.loaded
    if not m then return false end
    if self.draft then return true end
    return self.nameField:GetValue() ~= m.name or self.body:GetText() ~= m.body or self.icon ~= m.icon
end

-- What can be done now, and why not.
function M:DrawState()
    local combat = InCombatLockdown()
    local m = self.loaded
    self.band:SetShown(combat)
    self.idRow:ClearAllPoints()
    self.idRow:SetPoint("TOPLEFT", 0, combat and -(28 + S["space-4"]) or 0)
    self.idRow:SetPoint("RIGHT")
    self.big.skin:SetItem(m and { icon = self.icon } or nil)
    local name = self.nameField:GetValue() or ""
    self.nameCount:SetValue(("%d / %d"):format(#name, NAME_MAX))
    local len = #(self.body:GetText() or "")
    self.bodyCount:SetValue(("%d / %d"):format(len, BODY_MAX))
    self.bodyCount:SetColor(len > BODY_MAX - 15 and "ember-text" or "ink-muted")
    local editable = m ~= nil and not combat
    self.nameField:SetDisabled(not editable)
    self.body:EnableMouse(editable)
    if not editable then self.body:ClearFocus() end
    self.well:SetAlpha(editable and 1 or 0.5)
    self.iconButton:SetEnabledState(editable)
    self.iconButton.tooltip = combat and { title = COMBAT } or nil
    -- Save: something changed, and a name
    local dirty = self:Dirty()
    local why = combat and COMBAT or (not m and "Nothing to save") or (strtrim(name) == "" and "Give it a name first")
        or (not dirty and "Nothing changed") or nil
    self.save:SetEnabledState(why == nil)
    self.save.tooltip = why and { title = why } or nil
    -- New: room in this tab
    local general, char = self:Counts()
    local full = (self.tab or "general") == "general" and general >= MAX_GENERAL or (self.tab == "character" and char >= MAX_CHAR)
    local newWhy = combat and COMBAT or (full and "This tab is full") or (self.draft and "Save or discard the new one first") or nil
    self.new:SetEnabledState(newWhy == nil)
    self.new.tooltip = newWhy and { title = newWhy } or nil
    self.empty.new:SetEnabledState(not combat)
    local delWhy = combat and COMBAT or (not m and "Nothing to delete") or nil
    self.delete:SetEnabledState(delWhy == nil)
    self.delete.tooltip = delWhy and { title = delWhy } or nil
    self.delete:SetLabel(self.draft and "Discard" or "Delete")
    self.hint:SetValue(combat and COMBAT or (self.draft and "A new macro: name it and Save") or "Drag the icon to an action bar")
    self.hint:SetColor(combat and "ember-text" or "ink-muted")
    self.dragHint:SetShown(self.chosen ~= nil and not self.draft)
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function M:Select(m)
    if InCombatLockdown() then return end
    self.draft = nil
    self.chosen = m
    self:ClosePicker()
    self:Refresh()
end

function M:New()
    if InCombatLockdown() then return end
    self.draft = { name = "", icon = QUESTION, body = "" }
    self:ClosePicker()
    self:Refresh()
    self.nameField.edit:SetFocus()
end

function M:Save()
    if InCombatLockdown() or not self.loaded then return end
    local name = strtrim(self.nameField:GetValue() or "")
    if name == "" then return end
    local body = self.body:GetText() or ""
    if self.draft then
        local index = call(CreateMacro, name, self.icon or QUESTION, body, self.tab == "character")
        self.draft = nil
        self.chosen = index and { index = index, name = name } or nil
    else
        local index = call(EditMacro, self.loaded.index, name, self.icon or QUESTION, body)
        self.chosen = { index = index or self.loaded.index, name = name }
    end
    self:Refresh()
end

function M:Delete()
    if InCombatLockdown() or not self.loaded then return end
    if self.draft then
        self.draft = nil
        self:Refresh()
        return
    end
    local m = self.loaded
    UI.Confirm({ title = "Delete " .. m.name .. "?", text = "The macro is gone for good, and its buttons on your bars with it.",
        confirm = "Delete", onConfirm = function()
            if InCombatLockdown() then return end
            call(DeleteMacro, m.index)
            self.chosen = nil
            self:Refresh()
        end })
end

--------------------------------------------------------------------------------
-- The icon picker: a popover under the name; 8 columns, the wheel scrolls
--------------------------------------------------------------------------------

local COLS, VISIBLE_ROWS, CELL = 8, 6, 36

-- every macro icon, spells first, then items ("?" leads)
function M:AllIcons(kind)
    local list = { QUESTION }
    if kind ~= "items" then
        local spells = {}
        call(GetLooseMacroIcons, spells)
        call(GetMacroIcons, spells)
        for _, v in ipairs(spells) do list[#list + 1] = v end
    end
    if kind ~= "spells" then
        local items = {}
        call(GetLooseMacroItemIcons, items)
        call(GetMacroItemIcons, items)
        for _, v in ipairs(items) do list[#list + 1] = v end
    end
    return list
end

-- the icons of your spells and bag items whose name has what was typed
function M:SearchIcons(text, kind)
    text = text:lower()
    local list, seen = {}, {}
    local function add(icon)
        if icon and not seen[icon] then seen[icon] = true; list[#list + 1] = icon end
    end
    if kind ~= "items" then
        for i = 1, (call(C_SpellBook.GetNumSpellBookSkillLines) or 0) do
            local line = call(C_SpellBook.GetSpellBookSkillLineInfo, i)
            if line then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = call(C_SpellBook.GetSpellBookItemInfo, slot, BANK)
                    if info and info.itemType == SPELL and plain(info.name) and info.name:lower():find(text, 1, true) then
                        add(info.iconID)
                    end
                end
            end
        end
    end
    if kind ~= "spells" then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (call(C_Container.GetContainerNumSlots, bag) or 0) do
                local info = call(C_Container.GetContainerItemInfo, bag, slot)
                local name = info and info.itemID and call(C_Item.GetItemNameByID, info.itemID)
                if plain(name) and name:lower():find(text, 1, true) then add(info.iconFileID) end
            end
        end
    end
    return list
end

function M:BuildPicker()
    local p = CreateFrame("Frame", nil, self.edit)
    p:SetFrameLevel(self.edit:GetFrameLevel() + 30)
    p:SetSize(COLS * CELL + (COLS - 1) * S["space-3"] + 2 * S["space-5"], 0)
    p:EnableMouse(true)
    UI.Fill(p, "surface"):SetAllPoints()
    UI.Border(p, "gilt-line")
    UI.Shadow(p, "shadow-panel")
    local head = UI.Text(p, "header", "gilt-text")
    head:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    head:SetValue("Choose an icon")
    local y = S["space-5"] + T.type.header.lineHeight + S["space-3"]
    p.kind = UI.Select(p, { width = 120, value = "all", options = { { value = "all", label = "All icons" },
        { value = "spells", label = "Spells" }, { value = "items", label = "Items" } }, onChange = function(v)
            p.kindValue = v
            self:FillPicker(true)
        end })
    p.kind:SetPoint("TOPRIGHT", -S["space-5"], -y)
    p.search = UI.TextField(p, { placeholder = "Search your spells and items", onTextChanged = function() self:FillPicker(true) end })
    p.search:SetPoint("TOPLEFT", S["space-5"], -y)
    p.search:SetPoint("RIGHT", p.kind, "LEFT", -S["space-3"], 0)
    y = y + 30 + S["space-4"]
    p.grid = CreateFrame("Frame", nil, p)
    p.grid:SetPoint("TOPLEFT", S["space-5"], -y)
    p.grid:SetSize(COLS * CELL + (COLS - 1) * S["space-3"], VISIBLE_ROWS * CELL + (VISIBLE_ROWS - 1) * S["space-3"])
    p.grid:EnableMouseWheel(true)
    p.grid:SetScript("OnMouseWheel", function(_, delta)
        local rows = math.ceil(#(p.icons or {}) / COLS)
        p.offset = math.max(0, math.min(math.max(0, rows - VISIBLE_ROWS), (p.offset or 0) - delta))
        self:FillPicker()
    end)
    p.cells = {}
    for i = 1, COLS * VISIBLE_ROWS do
        local cell = UI.ItemSlot(p.grid, CELL)
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        cell:SetPoint("TOPLEFT", col * (CELL + S["space-3"]), -row * (CELL + S["space-3"]))
        cell.ring = UI.Border(cell, "arcane", { layer = "OVERLAY" })
        cell:SetScript("OnClick", function(c)
            p.picked = c.iconID
            self:FillPicker()
        end)
        cell:SetScript("OnDoubleClick", function(c)
            p.picked = c.iconID
            self:UseIcon()
        end)
        p.cells[i] = cell
    end
    y = y + p.grid:GetHeight() + S["space-3"]
    p.where = UI.Text(p, "caption", "ink-muted")
    p.where:SetPoint("TOPLEFT", S["space-5"], -y)
    y = y + T.type.caption.lineHeight + S["space-3"]
    -- the drop zone: a spell, an item or a macro dragged here gives its icon
    local drop = CreateFrame("Button", nil, p)
    drop:SetPoint("TOPLEFT", S["space-5"], -y)
    drop:SetPoint("RIGHT", -S["space-5"], 0)
    drop:SetHeight(40)
    UI.Fill(drop, "surface-sunk"):SetAllPoints()
    UI.Border(drop, "gilt-line")
    drop.text = UI.Text(drop, "caption", "ink-muted")
    drop.text:SetPoint("CENTER")
    drop.text:SetValue("Drag a spell, an item or another macro here")
    local function dropped()
        local kind, a, b, c = GetCursorInfo()
        local icon
        if kind == "spell" then
            local spellID = c or b
            icon = spellID and call(C_Spell.GetSpellTexture, spellID)
        elseif kind == "item" then
            icon = a and call(C_Item.GetItemIconByID, a)
        elseif kind == "macro" then
            local _, mi = GetMacroInfo(a)
            icon = mi
        end
        if icon then
            ClearCursor()
            p.picked = icon
            self:UseIcon()
        end
    end
    drop:SetScript("OnReceiveDrag", dropped)
    drop:SetScript("OnClick", dropped)
    y = y + 40 + S["space-4"]
    local note = UI.Text(p, "caption", "ink-muted")
    note:SetPoint("TOPLEFT", S["space-5"], -(y + 7))
    note:SetValue("\"?\" uses the first spell's icon")
    p.use = UI.Button(p, { text = "Use icon", variant = "primary", onClick = function() self:UseIcon() end })
    p.use:SetPoint("TOPRIGHT", -S["space-5"], -y)
    local cancel = UI.Button(p, { text = "Cancel", onClick = function() self:ClosePicker() end })
    cancel:SetPoint("RIGHT", p.use, "LEFT", -S["space-3"], 0)
    p:SetHeight(y + 30 + S["space-5"])
    p:Hide()
    self.picker = p
end

function M:FillPicker(reset)
    local p = self.picker
    local text = strtrim(p.search:GetValue() or "")
    if reset or not p.icons then
        p.icons = text ~= "" and self:SearchIcons(text, p.kindValue) or self:AllIcons(p.kindValue)
        p.offset = 0
    end
    local first = (p.offset or 0) * COLS
    for i, cell in ipairs(p.cells) do
        local icon = p.icons[first + i]
        cell.iconID = icon
        cell.skin:SetItem(icon and { icon = icon } or nil)
        cell:SetShown(icon ~= nil)
        cell.ring:SetShown(icon ~= nil and icon == p.picked)
    end
    local rows = math.ceil(#p.icons / COLS)
    if text ~= "" then
        p.where:SetValue(#p.icons == 0 and "None of your spells or items match" or ("%d of your spells and items"):format(#p.icons))
    else
        p.where:SetValue(rows > VISIBLE_ROWS and ("%d icons · rows %d–%d of %d (wheel to scroll)"):format(#p.icons, p.offset + 1,
            math.min(rows, p.offset + VISIBLE_ROWS), rows) or ("%d icons"):format(#p.icons))
    end
    p.use:SetEnabledState(p.picked ~= nil)
end

function M:TogglePicker()
    if self.picker and self.picker:IsShown() then return self:ClosePicker() end
    if InCombatLockdown() or not self.loaded then return end
    if not self.picker then self:BuildPicker() end
    local p = self.picker
    p.picked = self.icon
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", self.idRow, "TOPLEFT", 0, -64)
    p:Show()
    self:FillPicker(true)
end

function M:UseIcon()
    local p = self.picker
    if p and p.picked then self.icon = p.picked end
    self:ClosePicker()
    self:DrawState()
end

function M:ClosePicker()
    if self.picker then self.picker:Hide() end
end

--------------------------------------------------------------------------------
-- Opening: instead of the game's window
--------------------------------------------------------------------------------

function M:Toggle()
    if self.window:IsShown() then self.window:Hide() return end
    self.tab = self.tab or "general"
    self.window:Show()
    self:Refresh()
end

function M:HookGame()
    local f = _G.MacroFrame
    if not f or self.hooked then return end
    self.hooked = true
    f:HookScript("OnShow", function()
        if not self:IsEnabled() then return end
        HideUIPanel(f)
        if not self.window:IsShown() then self:Toggle() end
    end)
end

function M:OnEnable()
    if not self.window then self:Build() end
    self:HookGame()
    self:OnGameEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_MacroUI" then self:HookGame() end end)
    self:OnGameEvent("UPDATE_MACROS", function() self:Refresh() end)
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function()
        self:ClosePicker()
        if self.window:IsShown() then self:DrawState() end
    end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.window:IsShown() then self:DrawState() end
    end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
