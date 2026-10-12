-- Units/BuffIndicators.lua
-- Buff indicators on party and raid frames: your heals over time and shields
-- (or anyone's buffs) as an icon, a coloured square, a border or a tint over
-- the health fill. The engine filters them by spell, so they work in combat.
-- A built-in module written against the public API only: it keeps a list
-- per class and spec (the talent tree with the most points, 0 unspecced) in
-- the profile, so one profile serves every character, and hands the active
-- spec's list to the group frames through SuuUI.UI.SetGroupIndicators;
-- turned off, the frames show none.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "indicators",
    name = "Buff indicators",
    description = "Your heals over time and shields on party and raid frames, in combat too.",
    api = "0.9",
    defaults = {
        -- lists[CLASS][spec] = { { name, ids, kind, point, size, color, source } … },
        -- spec "0"-"3"; a spec without one starts from its class's defaults
        lists = {},
    },
})

local _, CLASS = UnitClass("player")
local isSecret = issecretvalue or function() return false end

-- Each class's starting set, by name (every rank's IDs come from the
-- Cooldown Manager's presets). Classes without heals over time start empty.
local DEFAULTS = {
    PRIEST = {
        { name = "Renew", kind = "icon", point = "TOPRIGHT", size = 14 },
        { name = "Power Word: Shield", kind = "square", point = "TOPLEFT", size = 8, color = "ward" },
    },
    DRUID = {
        { name = "Rejuvenation", kind = "icon", point = "TOPRIGHT", size = 14 },
        { name = "Regrowth", kind = "square", point = "TOPLEFT", size = 8, color = "fel" },
    },
}

local KINDS = { { value = "icon", label = "Icon" }, { value = "square", label = "Square" },
                { value = "border", label = "Border" }, { value = "fill", label = "Bar colour" } }
local POINT_LABEL = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Centre",
                      RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }
local COLORS = { { value = "fel", label = "Green" }, { value = "arcane", label = "Blue" }, { value = "ward", label = "Pale gold" },
                 { value = "amber", label = "Amber" }, { value = "ember", label = "Red" }, { value = "gilt", label = "Gilt" },
                 { value = "ink", label = "White" } }

local SIZE_OPTIONS = { { value = "5", label = "Party" }, { value = "10", label = "10" },
                       { value = "20", label = "20" }, { value = "40", label = "40" } }

local MISSING_COLORS = { { value = "ember", label = "Red" }, { value = "amber", label = "Amber" },
                         { value = "ink-faint", label = "Grey" }, { value = "arcane", label = "Blue" } }

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- Every buff the Cooldown Manager's presets know for your class, by name.
local function knownBuffs()
    local byName = {}
    local presets = SuuUI.CooldownPresets and SuuUI.CooldownPresets() or {}
    for _, p in ipairs(presets) do
        for _, key in ipairs({ "buffs", "procs" }) do
            for _, e in ipairs(p.lists and p.lists[key] or {}) do
                if not e.group and e.name and e.ids then byName[e.name] = byName[e.name] or e.ids end
            end
        end
    end
    return byName
end

-- The spec whose list the frames use, and the one the editor shows.
local function specKey(spec) return tostring(spec or 0) end
function M:ActiveSpec() return (SuuUI.Spec()) end
function M:EditSpec() return self.editSpec or self:ActiveSpec() end

-- A spec's name from the presets' trees ("Holy"), or Unspecced.
local function specName(spec)
    if spec == 0 then return "Unspecced" end
    for _, p in ipairs(SuuUI.CooldownPresets and SuuUI.CooldownPresets() or {}) do
        if p.tree == spec then return (p.name:gsub("%s*%b()", "")) end
    end
    return "Tree " .. spec
end

-- Lists saved before specs (lists[CLASS] = { indicator, … }): every spec
-- starts from it.
local function migrated(byClass)
    if type(byClass) ~= "table" or byClass[1] == nil then return byClass end
    local out = {}
    for spec = 0, 3 do out[specKey(spec)] = copy(byClass) end
    return out
end

function M:List(spec)
    spec = spec or self:ActiveSpec()
    local byClass = migrated(self:Get("lists")[CLASS])
    if byClass and byClass[specKey(spec)] then return byClass[specKey(spec)] end
    -- first time for this spec: the class's defaults, with their spells
    local buffs, list = knownBuffs(), {}
    for _, d in ipairs(DEFAULTS[CLASS] or {}) do
        if buffs[d.name] then
            local e = copy(d)
            e.ids, e.source = copy(buffs[d.name]), "mine"
            list[#list + 1] = e
        end
    end
    return list
end

function M:SetList(list, spec)
    local all = copy(self:Get("lists"))
    all[CLASS] = migrated(all[CLASS]) or {}
    all[CLASS][specKey(spec or self:ActiveSpec())] = list
    self:Set("lists", all)
end

-- Edits go to the spec the editor shows.
local function mutate(fn)
    local spec = M:EditSpec()
    local list = copy(M:List(spec))
    fn(list)
    M:SetList(list, spec)
end

function M:Publish()
    self.publishPending = nil
    UI.SetGroupIndicators(self:List(self:ActiveSpec()))
end

--------------------------------------------------------------------------------
-- The editor: one block per indicator, then "+ Add"
--------------------------------------------------------------------------------

local WIDTH = 560
local ROW_H = 46

-- What a typed number finds: "Name · ID 123" (value "id:123").
local function spellLookup(query)
    local id = tonumber((query or ""):match("^%s*(%d+)%s*$"))
    local name = id and C_Spell.GetSpellName(id)
    if isSecret(name) or not name then return nil end
    return { { value = "id:" .. id, label = ("%s · ID %d"):format(name, id) } }
end

local KIND_LABEL, COLOR_LABEL, MISSING_LABEL = {}, {}, {}
for _, o in ipairs(KINDS) do KIND_LABEL[o.value] = o.label end
for _, o in ipairs(COLORS) do COLOR_LABEL[o.value] = o.label end
for _, o in ipairs(MISSING_COLORS) do MISSING_LABEL[o.value] = o.label:lower() end

local function placed(e) return e.kind == "icon" or e.kind == "square" or e.kind == nil end

-- The effective show mode (a bar colour has no "both").
local function showOf(e)
    local show = e.show or "up"
    if e.kind == "fill" and show == "both" then show = "up" end
    return show
end

-- One caption line, in the modal's order: "Square · Top left · 8px · Pale
-- gold · Up or missing (red) · My group · Party, 10".
local function summary(e)
    local parts = { KIND_LABEL[e.kind or "icon"] or "Icon" }
    if placed(e) then
        parts[#parts + 1] = POINT_LABEL[e.point or "TOPRIGHT"]
        parts[#parts + 1] = (e.size or 10) .. "px"
    end
    if e.kind ~= "icon" and e.kind ~= nil then parts[#parts + 1] = COLOR_LABEL[e.color or "fel"] or e.color end
    local show = showOf(e)
    local missing = (e.kind ~= "icon" and e.kind ~= nil) and (" (" .. (MISSING_LABEL[e.missingColor or "ember"] or "red") .. ")") or ""
    if show == "up" then parts[#parts + 1] = "While up"
    elseif show == "missing" then parts[#parts + 1] = "While missing" .. missing
    else parts[#parts + 1] = "Up or missing" .. missing end
    if (e.on or e.missingOn) == "group" then parts[#parts + 1] = "My group" end
    if e.source == "any" then parts[#parts + 1] = "Anyone's" end
    if e.sizes and next(e.sizes) then
        local on = {}
        for _, o in ipairs(SIZE_OPTIONS) do if e.sizes[o.value] then on[#on + 1] = o.label end end
        if #on < #SIZE_OPTIONS then parts[#parts + 1] = table.concat(on, ", ") end
    end
    return table.concat(parts, " · ")
end

--------------------------------------------------------------------------------
-- The Edit indicator modal: a live mini preview, then Look, When it shows
-- and Where in two columns. What doesn't apply stays, dimmed, with why.
--------------------------------------------------------------------------------

local EP_W, COL_W = 720, 320
local SHOW_NOTE = {
    up = "Shows while the aura is up. In combat too.",
    missing = "Shows while none of its spells is up. Out of combat only: in combat the game hides auras, so it hides.",
    both = "The missing look sits underneath; the live one covers it while the aura is up. In combat too.",
}
local SHOW_OPTIONS = { { value = "up", label = "While up" }, { value = "missing", label = "While missing" },
                       { value = "both", label = "Up or missing", reason = "Two tints would blend." } }

local editPanel

-- A change to the lists. While the Edit indicator modal is open, the live
-- party and raid frames wait for it to close (Done, or the settings window
-- closing hides it): each look (size, colour, position…) is an engine aura
-- container on every group frame, which the engine never frees, so the
-- steps on the way to a look mustn't each leave one behind. The previews
-- (this section's and the modal's) follow every step.
function M:ListsChanged()
    if editPanel and editPanel:IsShown() then
        self.publishPending = true
    else
        self:Publish()
    end
end

local function editEntry() return editPanel and (M:List(M:EditSpec()))[editPanel.index] end

local function editMutate(fn)
    local index = editPanel.index
    mutate(function(l) if l[index] then fn(l[index]) end end)
end

-- A field: its label (caption) over its control, a reason under it while
-- it doesn't apply. Returns the next y.
local function field(col, y, label, control, h)
    local t = UI.Text(col, "caption", "ink-muted")
    t:SetPoint("TOPLEFT", 0, -y)
    t:SetValue(label)
    control:SetPoint("TOPLEFT", 0, -(y + 18))
    local reason = UI.Text(col, "caption", "ink-faint")
    reason:SetPoint("TOPLEFT", 0, -(y + 18 + (h or 30) + 4))
    reason:SetWidth(COL_W)
    reason:SetWordWrap(true)
    control.reason = reason
    return y + 18 + (h or 30) + 4 + 16 + 8
end

local function setApplies(control, applies, why)
    if control.SetDisabled then control:SetDisabled(not applies) else control:SetAlpha(applies and 1 or T.opacity["opacity-disabled"]) end
    control.reason:SetValue(applies and (control.note or "") or (why or ""))
    control.reason:SetTextColor(UI.RGBA(applies and "ink-muted" or "ink-faint"))
end

local PREVIEW_PERSON = { name = "Ysolde", class = "PRIEST", role = "HEALER", health = 0.62, max = 3900, power = 0.7 }
local EDIT_STAND_IN = UI.UnitStandIn(function() return PREVIEW_PERSON end)

local function buildEditPanel()
    local p = UI.Panel(SuuUI.Root, { title = "Edit indicator", width = EP_W, height = 640, solid = true })
    UI.MakeModal(p)
    local body = p.body

    -- the live mini preview: this one indicator, up and missing
    local well = CreateFrame("Frame", nil, body)
    well:SetPoint("TOPLEFT")
    well:SetSize(EP_W - 40, 64)
    UI.Fill(well, "surface-sunk"):SetAllPoints()
    UI.Border(well, "gilt-faint")
    p.previews = {}
    for i, label in ipairs({ "Up", "Missing" }) do
        local holder = CreateFrame("Frame", nil, well)
        holder:SetSize(120, 46)
        local caption = UI.Text(holder, "caption", "ink-muted")
        caption:SetPoint("TOPLEFT")
        local f = UI.UnitFrame(holder, "indedit" .. i, { size = "sm", width = 120, height = 26, secure = false, api = EDIT_STAND_IN, power = false })
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:EnableMouse(false)
        f:SetPoint("TOPLEFT", 0, -18)
        holder.caption, holder.frame, holder.label = caption, f, label
        p.previews[i] = holder
    end

    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", 0, -(64 + 16))
    left:SetSize(COL_W, 420)
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", COL_W + 40, -(64 + 16))
    right:SetSize(COL_W, 420)

    -- Look
    UI.SectionHeader(left, "Look", nil, COL_W):SetPoint("TOPLEFT")
    local y = 30
    p.kind = UI.Segmented(left, { options = KINDS, onChange = function(v) editMutate(function(e) e.kind = v end) end })
    y = field(left, y, "Kind", p.kind)
    p.point = UI.AnchorPicker(left, { onChange = function(v) editMutate(function(e) e.point = v end) end })
    local yPos = y
    y = field(left, y, "Position", p.point, 68)
    p.size = UI.Stepper(left, { min = 6, max = 24, step = 1, unit = "px", onChange = function(v) editMutate(function(e) e.size = v end) end })
    p.sizeLabel = UI.Text(left, "caption", "ink-muted")
    p.sizeLabel:SetPoint("TOPLEFT", 100, -yPos)
    p.sizeLabel:SetValue("Size")
    p.size:SetPoint("TOPLEFT", 100, -(yPos + 18))
    p.size.reason = p.point.reason -- one reason line serves both
    p.color = UI.SwatchRow(left, { options = COLORS, onChange = function(v) editMutate(function(e) e.color = v end) end })
    field(left, y, "Colour", p.color, 20)

    -- When it shows
    UI.SectionHeader(right, "When it shows", nil, COL_W):SetPoint("TOPLEFT")
    y = 30
    p.show = UI.Segmented(right, { options = SHOW_OPTIONS, onChange = function(v) editMutate(function(e) e.show = v ~= "up" and v or nil end) end })
    y = field(right, y, "Show", p.show)
    p.missingColor = UI.SwatchRow(right, { options = MISSING_COLORS, onChange = function(v)
        editMutate(function(e) e.missingColor = v ~= "ember" and v or nil end) end })
    y = field(right, y, "Missing colour", p.missingColor, 20)

    -- Where
    local where = UI.SectionHeader(right, "Where", nil, COL_W)
    where:SetPoint("TOPLEFT", 0, -y)
    y = y + 30
    p.source = UI.Segmented(right, { options = { { value = "mine", label = "Yours" }, { value = "any", label = "Anyone's" } },
        onChange = function(v) editMutate(function(e) e.source = v end) end })
    y = field(right, y, "Whose", p.source)
    p.on = UI.Segmented(right, { options = { { value = "all", label = "Everyone" }, { value = "group", label = "My group" } },
        onChange = function(v) editMutate(function(e) e.on = v ~= "all" and v or nil; e.missingOn = nil end) end })
    p.on.note = "My group: only your own raid group (in a party, everyone), e.g. Battle Shout."
    y = field(right, y, "Show on", p.on)
    p.sizes = UI.ToggleChips(right, { options = SIZE_OPTIONS, onChange = function(values)
        editMutate(function(e)
            local set, n = {}, 0
            for _, t in ipairs(values) do set[t] = true; n = n + 1 end
            e.sizes = (n > 0 and n < #SIZE_OPTIONS) and set or nil
        end)
    end })
    p.sizes.note = "All on: every size. A party (or no group) is Party; a raid the smallest size it fits."
    field(right, y, "Group sizes", p.sizes, 26)

    -- foot
    p.reset = UI.Button(body, { text = "Reset", width = 90, onClick = function()
        editMutate(function(e)
            e.kind, e.point, e.size, e.color, e.source = "icon", "TOPRIGHT", 12, "fel", "mine"
            e.show, e.missingColor, e.missingOn, e.on, e.sizes = nil, nil, nil, nil, nil
        end)
    end })
    p.reset:SetPoint("BOTTOMLEFT", 0, 0)
    p.done = UI.Button(body, { text = "Done", variant = "primary", width = 90, onClick = function() p:Hide() end })
    p.done:SetPoint("BOTTOMRIGHT", 0, 0)
    -- closed: the edits made in it go to the live frames (ListsChanged)
    p:HookScript("OnHide", function() if M.publishPending then M:Publish() end end)
    return p
end

function M:RefreshEdit()
    local p = editPanel
    if not (p and p:IsShown()) then return end
    local e = editEntry()
    if not e then p:Hide(); return end
    local art = e.ids and e.ids[1] and C_Spell.GetSpellTexture(e.ids[1])
    p:SetTitle((art and ("|T%s:16:16:0:0|t "):format(art) or "") .. (e.name or "Indicator"))
    local show, kind = showOf(e), e.kind or "icon"

    -- the mini preview: Up and/or Missing
    local shown = {}
    if show ~= "missing" then shown[#shown + 1] = { p.previews[1], "up", "Up" } end
    if show ~= "up" then shown[#shown + 1] = { p.previews[2], "missing", show == "missing" and "Missing · out of combat" or "Missing" } end
    for _, h in ipairs(p.previews) do h:Hide() end
    local x = (EP_W - 40 - (#shown * 120 + (#shown - 1) * 40)) / 2
    for _, s in ipairs(shown) do
        local h, mode, label = s[1], s[2], s[3]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", h:GetParent(), "TOPLEFT", x, -9)
        h.caption:SetValue(label)
        local view = copy(e)
        view.show = mode
        h.frame:Refresh()
        h.frame:SetPreviewIndicators({ view })
        h:Show()
        x = x + 160
    end

    -- Look
    p.kind:SetValue(kind)
    p.point:SetValue(e.point or "TOPRIGHT")
    p.size:SetValue(e.size or 10)
    p.color:SetValue(e.color or "fel")
    p.point.note = kind == "icon" and "Its time shows from 16px." or ""
    local why = kind == "border" and "A border goes around the whole frame." or "A bar colour tints the whole health fill."
    setApplies(p.point, placed(e), why)
    p.size:SetDisabled(not placed(e))
    setApplies(p.color, kind ~= "icon", "An icon shows the spell's own art.")

    -- When it shows
    SHOW_OPTIONS[3].disabled = kind == "fill"
    p.show:SetValue(show)
    p.show.note = SHOW_NOTE[show]
    setApplies(p.show, true)
    p.missingColor:SetValue(e.missingColor or "ember")
    if show == "up" then
        setApplies(p.missingColor, false, "Only for While missing and Up or missing.")
    else
        setApplies(p.missingColor, kind ~= "icon", "An icon shows grey while it's missing.")
    end

    -- Where
    p.source:SetValue(e.source or "mine")
    setApplies(p.source, true)
    p.on:SetValue(e.on or e.missingOn or "all")
    setApplies(p.on, true)
    local sizes = {}
    for _, o in ipairs(SIZE_OPTIONS) do if not e.sizes or e.sizes[o.value] then sizes[#sizes + 1] = o.value end end
    p.sizes:SetValue(sizes)
    setApplies(p.sizes, true)
end

function M:OpenEdit(index)
    editPanel = editPanel or buildEditPanel()
    editPanel.index = index
    editPanel:Show()
    self:RefreshEdit()
end

--------------------------------------------------------------------------------
-- The list: compact rows in a well (grip, icon, name, summary, Edit, ×),
-- dragged by the grip to reorder (later ones draw over earlier ones)
--------------------------------------------------------------------------------

local function grip(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(10, 18)
    for row = 0, 2 do
        for col = 0, 1 do
            local dot = UI.Fill(g, "ink-faint", "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("TOPLEFT", 2 + col * 4, -3 - row * 5)
        end
    end
    g:EnableMouse(true)
    return g
end

local function buildRow(parent, editor)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(WIDTH - 12, ROW_H)
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.rule:SetHeight(1)
    r.grip = grip(r)
    r.grip:SetPoint("LEFT", 4, 0)
    r.grip:SetScript("OnMouseDown", function() editor:StartDrag(r) end)
    r.grip:SetScript("OnMouseUp", function() editor:StopDrag() end)
    r.icon = UI.Icon(r, 24)
    r.icon:SetPoint("LEFT", r.grip, "RIGHT", 8, 0)
    r.name = UI.Text(r, "label", "ink")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 2)
    r.summary = UI.Text(r, "caption", "ink-muted")
    r.summary:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.remove = UI.Button(r, { text = "×", width = 28, onClick = function() mutate(function(l) table.remove(l, r.index) end) end })
    r.remove:SetPoint("RIGHT", -6, 0)
    r.edit = UI.Button(r, { text = "Edit", width = 64, onClick = function() M:OpenEdit(r.index) end })
    r.edit:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.summary:SetPoint("RIGHT", r.edit, "LEFT", -10, 0)
    r.summary:SetWordWrap(false)
    return r
end

local function specOptions()
    local active, out = M:ActiveSpec(), {}
    for spec = 0, 3 do
        out[#out + 1] = { value = spec, label = specName(spec) .. (spec == active and " (active)" or "") }
    end
    return out
end

local function buildEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(WIDTH, 100)
    f.rows = {}
    -- which spec's list this shows (your active one by default)
    f.spec = UI.Select(f, { width = 220, options = specOptions(), onChange = function(v)
        M.editSpec = v
        if editPanel then editPanel:Hide() end
        f:Refresh()
        M:DrawPreview()
    end })
    f.spec:SetPoint("TOPLEFT")
    f.specNote = UI.Text(f, "caption", "ink-muted")
    f.specNote:SetPoint("LEFT", f.spec, "RIGHT", 12, 0)
    f.well = CreateFrame("Frame", nil, f)
    UI.Fill(f.well, "surface-sunk"):SetAllPoints()
    UI.Border(f.well, "gilt-faint")
    f.line = f:CreateTexture(nil, "OVERLAY")
    f.line:SetColorTexture(UI.RGBA("arcane"))
    f.line:SetHeight(2)
    f.line:Hide()
    f.add = UI.Select(f, { width = 300, placeholder = "+ Add… (name or spell ID)", lookup = spellLookup,
        onChange = function(v)
            if not v then return end
            local id = tonumber(tostring(v):match("^id:(%d+)$"))
            local e
            if id then
                e = { name = C_Spell.GetSpellName(id), ids = { id } }
            elseif f.buffs and f.buffs[v] then
                e = { name = v, ids = copy(f.buffs[v]) }
            end
            if e then
                e.kind, e.point, e.size, e.color, e.source = "icon", "TOPRIGHT", 12, "fel", "mine"
                mutate(function(l) table.insert(l, e) end)
            end
        end })
    f.hint = UI.Text(f, "caption", "ink-muted")
    f.hint:SetPoint("LEFT", f.add, "RIGHT", 12, 0)
    f.hint:SetValue("Drag to reorder: later ones draw over earlier ones.")
    f.empty = UI.Text(f.well, "caption", "ink-muted")
    f.empty:SetPoint("LEFT", 12, 0)
    f.empty:SetValue("No indicators for this spec yet. Add your heals over time and shields.")

    -- dragging by the grip: an arcane line marks where the row lands
    function f:DropIndex()
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local index = 1
        for _, r in ipairs(self.rows) do
            if r:IsShown() and cy < (r:GetTop() + r:GetBottom()) / 2 then index = index + 1 end
        end
        return index
    end
    function f:StartDrag(row)
        self.dragFrom = row.index
        row:SetAlpha(0.4)
        self.dragRow = row
        self:SetScript("OnUpdate", function()
            local to = self:DropIndex()
            self.dropTo = to
            local anchor = self.rows[to]
            self.line:ClearAllPoints()
            self.line:SetPoint("LEFT", self.well, "LEFT", 6, 0)
            self.line:SetPoint("RIGHT", self.well, "RIGHT", -6, 0)
            if anchor and anchor:IsShown() then
                self.line:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
            else
                local last = self.rows[self.count]
                self.line:SetPoint("TOP", last, "BOTTOM", 0, 0)
            end
            self.line:Show()
        end)
    end
    function f:StopDrag()
        self:SetScript("OnUpdate", nil)
        self.line:Hide()
        if self.dragRow then self.dragRow:SetAlpha(1) end
        local from, to = self.dragFrom, self.dropTo
        self.dragFrom, self.dropTo, self.dragRow = nil, nil, nil
        if not (from and to) then return end
        if to > from then to = to - 1 end
        if to == from then return end
        mutate(function(l)
            local e = table.remove(l, from)
            table.insert(l, math.min(to, #l + 1), e)
        end)
    end

    function f:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local spec = M:EditSpec()
        self.spec:SetOptions(specOptions())
        self.spec:SetValue(spec)
        self.specNote:SetValue(spec == M:ActiveSpec() and "Shown on your frames now." or "Shown when you switch to this spec.")
        local list = M:List(spec)
        self.count = #list
        local top = 30 + 12
        self.well:ClearAllPoints()
        self.well:SetPoint("TOPLEFT", 0, -top)
        local y = 6
        for i, e in ipairs(list) do
            local r = self.rows[i] or buildRow(self.well, self)
            self.rows[i] = r
            r.index = i
            r.icon:SetArt(e.ids and e.ids[1] and C_Spell.GetSpellTexture(e.ids[1]))
            r.name:SetValue(e.name or "?")
            r.summary:SetValue(summary(e))
            r.rule:SetShown(i < #list)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 6, -y)
            r:Show()
            y = y + ROW_H
        end
        self.empty:SetShown(#list == 0)
        local wellH = #list == 0 and 40 or (y + 6)
        self.well:SetSize(WIDTH, wellH)
        -- "+ Add": the presets' buffs not on the list yet
        self.buffs = knownBuffs()
        local present, options = {}, {}
        for _, e in ipairs(list) do present[e.name or ""] = true end
        for name in pairs(self.buffs) do
            if not present[name] then options[#options + 1] = { value = name, label = name } end
        end
        table.sort(options, function(a, b) return a.label < b.label end)
        self.add:SetOptions(options)
        self.add:SetValue(nil)
        self.add:ClearAllPoints()
        self.add:SetPoint("TOPLEFT", 0, -(top + wellH + 10))
        self.hint:SetShown(#list >= 2)
        self:SetHeight(top + wellH + 10 + 40)
        M:RefreshEdit()
    end
    M.editor = f
    f:Refresh()
    M:Watch("lists", function() f:Refresh() end)
    f:HookScript("OnShow", function() f:Refresh() end)
    f:HookScript("OnHide", function() if editPanel then editPanel:Hide() end end)
    return f
end

--------------------------------------------------------------------------------
-- The preview: three made-up people at the healer size, every indicator up
--------------------------------------------------------------------------------

local PEOPLE = {
    { name = "Brannoc", class = "WARRIOR", role = "TANK", health = 0.64, max = 8800, power = 0.4 },
    { name = "Ysolde", class = "PRIEST", role = "HEALER", health = 0.83, max = 3900, power = 0.7 },
    { name = "Kaelith", class = "MAGE", role = "DAMAGER", health = 0.42, max = 3600, power = 0.55 },
}
local STAND_IN = UI.UnitStandIn(function(unit)
    return PEOPLE[tonumber(unit:match("(%d)$")) or 1]
end)

function M:PreviewView(parent)
    if not self.previewView then
        local view = CreateFrame("Frame", nil, parent)
        view:SetSize(120, 3 * 26 + 2 * S["space-1"])
        self.previewView, self.previewFrames = view, {}
        for i = 1, #PEOPLE do
            local f = UI.UnitFrame(view, "indpreview" .. i, { size = "sm", width = 120, height = 26, secure = false, api = STAND_IN, power = false })
            f:SetScript("OnEnter", nil)
            f:SetScript("OnLeave", nil)
            f:EnableMouse(false)
            f:SetPoint("TOPLEFT", 0, -(i - 1) * (26 + S["space-1"]))
            self.previewFrames[i] = f
        end
    end
    self.previewView:SetParent(parent)
    self:DrawPreview()
    return self.previewView
end

function M:DrawPreview()
    if not self.previewFrames then return end
    local list = self:List(self:EditSpec())
    for _, f in ipairs(self.previewFrames) do
        f:Refresh()
        f:SetPreviewIndicators(list)
    end
end

local SECTION = {
    id = "indicators", label = "Buff indicators", category = "Frames", order = 18,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Indicators", description = "Your heals over time and shields on party and raid frames, in combat too: an icon, a coloured square, a border or a tint over the health. Saved per class and spec in this profile, so one profile serves all your characters. Edit one for its look, when it shows and where.", rows = {
            { label = "Indicators", control = "custom", build = buildEditor, stacked = true },
        } },
    },
}

function M:OnEnable()
    self:RegisterSettings(SECTION)
    self:Publish()
    self:Watch("lists", function() self:ListsChanged(); self:DrawPreview() end)
    -- another spec: its list goes on the frames, and the editor follows
    self:On("SUUUI_SPEC_CHANGED", function()
        self.editSpec = nil
        self:Publish()
        if self.editor then self.editor:Refresh() end
        self:DrawPreview()
    end)
end

function M:OnDisable()
    self.publishPending = nil
    UI.SetGroupIndicators({})
end
