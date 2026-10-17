-- SettingsUI/Window.lua
-- SuuUI's settings window: every section, searchable, live, with profiles.
--
-- Header: the lockup, "Settings", search, the profile picker, close.
-- Body: the section list, the open section's groups, and the live preview
-- column. Footer: Import, Export, Reset section, a note, Done.
-- Every change applies as it is made; there is no Apply button.

local _, ns = ...

local UI, Layout, T, Motion = ns.UI, ns.Layout, ns.Tokens, ns.Motion
local Settings, Profiles, Registry, Events = ns.Settings, ns.Profiles, ns.SettingsRegistry, ns.Events
local S = T.space

local W = {}
ns.SettingsWindow = W

local WIDTH, HEIGHT = 1160, 740
local NAV_W = T.size["settings-nav"]
local PREVIEW_W = 320
local HEAD_H = S["space-5"] + 30 + S["space-5"]
local FOOT_H = S["space-4"] * 2 + 30
-- The content column: narrower beside a live preview, otherwise wider, but
-- capped so a row's label and its control stay within one glance.
local CONTENT_W = WIDTH - NAV_W - PREVIEW_W - S["space-6"] * 2
local WIDE_W = math.min(WIDTH - NAV_W - S["space-6"] * 2, 720)

local frame
local pages = {}      -- section id -> page
local current         -- the open section's id
local query = ""      -- the search text, lower case

-- A scrolling area (UI.ScrollArea): mouse wheel, content in area.child, an
-- optional thin scrollbar.
local scrollArea = UI.ScrollArea

--------------------------------------------------------------------------------
-- Rows bound to settings
--------------------------------------------------------------------------------

local function describe(d)
    if type(d) == "function" then return d() end
    return d
end

-- A row's description; a row with `combat = true` (a change that waits for
-- the end of combat) says so in the same words everywhere.
local COMBAT_NOTE = "Waits for the end of combat."

local function rowDescription(def)
    local d = describe(def.description)
    if not def.combat then return d end
    if d == nil or d == "" then return COMBAT_NOTE end
    return d .. " " .. COMBAT_NOTE
end

local function buildControl(parent, def, onChange)
    local c = def.control
    if c == "toggle" then return UI.Toggle(parent, { onChange = onChange }) end
    if c == "checkbox" then return UI.Checkbox(parent, { label = def.checkLabel, onChange = onChange }) end
    if c == "segmented" then return UI.Segmented(parent, { options = describe(def.options), onChange = onChange }) end
    if c == "select" then
        return UI.Select(parent, { options = describe(def.options), multiple = def.multiple, width = def.width,
            placeholder = def.placeholder, maxShown = def.maxShown, onChange = onChange })
    end
    if c == "slider" then
        return UI.Slider(parent, { min = def.min, max = def.max, step = def.step, unit = def.unit,
            format = def.format, width = def.width, live = def.live, onChange = onChange })
    end
    if c == "stepper" then
        return UI.Stepper(parent, { min = def.min, max = def.max, step = def.step, unit = def.unit, onChange = onChange })
    end
    if c == "text" then
        return UI.TextField(parent, { width = def.width or 220, placeholder = def.placeholder, onChange = onChange })
    end
    if c == "button" then
        return UI.Button(parent, { text = def.text, variant = def.variant, onClick = def.onClick })
    end
    -- a custom control: build(parent, onChange, def); with a key (or get) it is
    -- bound like the others (onChange writes, SetValue shows the setting)
    if c == "custom" then return def.build(parent, onChange, def) end
end

-- A SettingRow whose control reads and writes one setting (or def.get/def.set),
-- in the namespace of the section the row comes from (a merged section's own).
local function bindRow(page, def, section)
    local namespace = def.namespace or section.namespace
    local valued = def.control and def.control ~= "button"
        and (def.control ~= "custom" or def.key ~= nil or def.get ~= nil)
    local get = def.get or (def.key and function() return Settings.Get(namespace, def.key) end)
    local set = def.set or (def.key and function(v) return Settings.Set(namespace, def.key, v) end)
    local isDefault = def.isDefault or (def.key and function() return Settings.IsDefault(namespace, def.key) end)
    local reset = def.reset or (def.key and function() Settings.Reset(namespace, def.key) end)

    -- The row refreshes itself after every set and reset: a refused value goes
    -- back, and rows whose get/set bypass Settings hear no SUUUI_SETTING_CHANGED.
    local row
    local ctl = buildControl(page.frame, def, function(v)
        if not set then return end
        local ok, reason = set(v)
        if ok == false then
            ns.Print(("%s wasn't changed: %s"):format(def.label, reason or "refused"))
        end
        row.refresh()
    end)
    local doReset = reset and function()
        reset()
        row.refresh()
    end
    row = UI.SettingRow(page.frame, {
        label = def.label, description = rowDescription(def), control = ctl,
        stacked = def.stacked, width = page.width, onReset = doReset,
    })
    row.def, row.doReset, row.namespace = def, doReset, namespace
    row.isModified = function() return isDefault ~= nil and not isDefault() end
    row.refresh = function()
        if valued and get and ctl.SetValue then ctl:SetValue(get()) end
        if type(def.options) == "function" and ctl.SetOptions then ctl:SetOptions(def.options()) end
        if type(def.description) == "function" then row:SetDescription(rowDescription(def)) end
        local disabled, reason = false, nil
        if def.disabled then disabled, reason = def.disabled() end
        row:SetDisabled(disabled, reason)
        row:SetModified(reset ~= nil and row.isModified())
    end
    row.refresh()
    return row
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local Page = {}

-- `section`: the section the group comes from, when it was merged in from
-- another (its rows use that section's namespace).
function Page:AddGroup(def, section)
    local g = UI.SettingsGroup(self.frame, { title = def.title, description = def.description, width = self.width })
    g.def, g.section = def, section or self.section
    g.boundRows = {} -- not g.rows: that is the group's own row frame
    for _, rdef in ipairs(def.rows or {}) do
        local row = bindRow(self, rdef, g.section)
        g:AddRow(row)
        g.boundRows[#g.boundRows + 1] = row
        self.rows[#self.rows + 1] = row
    end
    self.groups[#self.groups + 1] = g
    self.stack:Add(g)
    return g
end

-- Drops every group, for sections that rebuild themselves (the module list).
function Page:Clear()
    for _, g in ipairs(self.groups) do
        self.stack:Remove(g)
        g:Hide()
    end
    wipe(self.groups)
    wipe(self.rows)
end

function Page:Refresh()
    local changed = 0
    for _, g in ipairs(self.groups) do
        local n = 0
        for _, row in ipairs(g.boundRows) do
            row.refresh()
            if row.isModified() then n = n + 1 end
        end
        g:SetMeta(n > 0 and (n == 1 and "1 changed" or n .. " changed") or "")
        changed = changed + n
    end
    self.changed = changed
end

-- Shows the rows matching `q` (everything when q is empty); returns the count.
-- A match on the section's label (or a merged group's own section's label) or
-- a group's title or description shows all the rows under it.
function Page:Filter(q)
    local total = 0
    local sectionHit = q == "" or (self.section.label or ""):lower():find(q, 1, true)
    for _, g in ipairs(self.groups) do
        local groupHit = sectionHit or (g.section.label or ""):lower():find(q, 1, true)
            or (g.def.title or ""):lower():find(q, 1, true)
            or (tostring(describe(g.def.description) or "")):lower():find(q, 1, true)
        local shown = 0
        for _, row in ipairs(g.boundRows) do
            local d = row.def
            local hit = groupHit or (d.label or ""):lower():find(q, 1, true)
                or (tostring(rowDescription(d) or "")):lower():find(q, 1, true)
            row:SetShown(hit and true or false)
            if hit then shown = shown + 1 end
        end
        g:SetShown(shown > 0)
        total = total + shown
    end
    return total
end

local function buildPage(section)
    local width = section.preview and CONTENT_W or WIDE_W
    local f = CreateFrame("Frame", nil, frame.content.child)
    f:SetWidth(width)
    local page = setmetatable({ section = section, frame = f, groups = {}, rows = {}, width = width }, { __index = Page })
    page.stack = Layout.Stack(f, { gap = S["space-7"], autoSize = "height" })
    page.title = UI.SectionHeader(f, section.label, nil, width)
    page.title:Hide()
    page.stack:Add(page.title)
    for _, g in ipairs(section.groups or {}) do page:AddGroup(g) end
    if section.build then section.build(page) end
    -- then the groups of the sections merged into this one
    local merged = {}
    for _, m in ipairs(Registry.Merged(section.id)) do
        merged[#merged + 1] = m.id
        for _, g in ipairs(m.groups or {}) do page:AddGroup(g, m) end
    end
    page.merged = table.concat(merged, ",")
    page:Refresh()
    f:Hide()
    frame.pagesStack:Add(f)
    return page
end

local function getPage(section)
    pages[section.id] = pages[section.id] or buildPage(section)
    return pages[section.id]
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local function navButton(i)
    local nav = frame.nav.child
    frame.navButtons[i] = frame.navButtons[i] or (function()
        local b = CreateFrame("Button", nil, nav)
        b:SetSize(NAV_W - S["space-4"] * 2, 30)
        b.bg = UI.Fill(b, "surface-raised")
        b.bg:SetAllPoints()
        b.mark = UI.Diamond(b, 5, "gilt")
        b.mark:SetPoint("CENTER", b, "LEFT", 7, 0)
        b.dot = UI.Diamond(b, 5, "ink")
        b.dot:SetPoint("CENTER", b, "RIGHT", -S["space-4"] - 2.5, 0)
        b.label = UI.Text(b, "label", "ink-muted")
        b.label:SetPoint("LEFT", S["space-5"] + 4, 0)
        b.heading = UI.Text(b, "caption", "ink-muted")
        b.heading:SetPoint("BOTTOMLEFT", S["space-4"], S["space-2"])
        b:SetScript("OnEnter", function(self)
            if self.section and self.section.id ~= current then self.label:SetColor("ink"); self.bg:Show() end
        end)
        b:SetScript("OnLeave", function() W.RefreshNav() end)
        b:SetScript("OnClick", function(self) if self.section then W.Show(self.section.id) end end)
        return b
    end)()
    return frame.navButtons[i]
end

function W.RefreshNav()
    if not frame then return end
    for _, b in ipairs(frame.navButtons) do
        if b.section then
            local on = b.section.id == current and query == ""
            b.bg:SetShown(on)
            b.mark:SetShown(on)
            b.label:SetColor(on and "gilt-text" or "ink-muted")
            local page = pages[b.section.id]
            b.dot:SetShown(page ~= nil and (page.changed or 0) > 0)
        end
    end
end

local function buildNav()
    for _, b in ipairs(frame.navButtons) do b:Hide() end
    local y, i, lastCategory = S["space-5"], 0, nil
    for _, section in ipairs(Registry.List()) do
        if section.category ~= lastCategory then
            i = i + 1
            local h = navButton(i)
            h.section = nil
            h:SetHeight(lastCategory and 38 or 22)
            h.bg:Hide(); h.mark:Hide(); h.dot:Hide(); h.label:SetValue("")
            h.heading:SetValue(section.category)
            h:EnableMouse(false)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", S["space-4"], -y)
            h:Show()
            y = y + h:GetHeight()
            lastCategory = section.category
        end
        i = i + 1
        local b = navButton(i)
        b.section = section
        b:SetHeight(30)
        b.heading:SetValue("")
        b.label:SetValue(section.label)
        b:EnableMouse(true)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", S["space-4"], -y)
        b:Show()
        y = y + 31
    end
    frame.nav.child:SetSize(NAV_W, y + S["space-5"])
    W.RefreshNav()
end

--------------------------------------------------------------------------------
-- Showing sections, searching, the preview
--------------------------------------------------------------------------------

-- The preview column shows only for a section that has a preview; otherwise
-- the content takes its space.
local function showPreview(section)
    local p = frame.preview
    if p.view then p.view:Hide(); p.view = nil end
    local has = section and section.preview ~= nil and query == ""
    p:SetShown(has)
    frame.content:SetPoint("BOTTOMRIGHT", -((has and PREVIEW_W or 0) + S["space-6"]), FOOT_H)
    p.title:SetValue(section and section.previewTitle or "Live preview")
    if has then
        local view = section.preview(p.area)
        view:SetScale(1)
        view:Show()
        p.view, p.section = view, section
        if not view.suuNoteHooked then
            view.suuNoteHooked = true
            view:HookScript("OnSizeChanged", function(v)
                if frame.preview.view == v then W.PlacePreview(); W.PreviewNote() end
            end)
        end
        W.PlacePreview()
        W.PreviewNote()
    end
end

-- The view at its real size: centred in the column, or (wider or taller than
-- the column) from its left or top edge, so its start shows and only its far
-- end clips.
function W.PlacePreview()
    local p = frame.preview
    local view = p.view
    if not view then return end
    view:ClearAllPoints()
    local wide = view:GetWidth() > p.area:GetWidth()
    local tall = view:GetHeight() > p.area:GetHeight()
    local point = (tall and "TOP" or "") .. (wide and "LEFT" or "")
    if point == "" then point = "CENTER" end
    view:SetPoint(point, p.area, point)
end

-- The section's note under its preview (previewNote, a string or function).
function W.PreviewNote()
    local p = frame.preview
    local note = p.section and describe(p.section.previewNote)
    p.note:SetValue(note or "")
end

-- Reset section asks twice: the first click arms it for a few seconds.
local resetTimer

local function disarmReset()
    if resetTimer then resetTimer:Cancel(); resetTimer = nil end
    frame.resetSection:SetLabel("Reset section")
end

local function applyView()
    local any = false
    if query ~= "" then
        -- results in the nav's order, not the order the pages were built in
        for _, section in ipairs(Registry.List()) do
            local page = pages[section.id]
            if page then
                frame.pagesStack:Remove(page.frame)
                frame.pagesStack:Add(page.frame)
            end
        end
    end
    for id, page in pairs(pages) do
        if query == "" then
            page:Filter("")
            page.title:Hide()
            page.frame:SetShown(id == current)
        else
            local hits = page:Filter(query)
            page.title:SetShown(hits > 0)
            page.frame:SetShown(hits > 0)
            any = any or hits > 0
        end
    end
    frame.empty:SetShown(query ~= "" and not any)
    frame.content:SetVerticalScroll(0)
    -- it resets the open section, which a search doesn't show on its own
    disarmReset()
    frame.resetSection:SetEnabledState(query == "")
    W.RefreshNav()
end

function W.Show(id)
    local section = Registry.Get(id or "")
    -- a merged section opens the page it shows on
    section = section and (Registry.MergedInto(section) or section) or Registry.List()[1]
    if not section then return end
    current = section.id
    getPage(section)
    frame.search.edit:ClearFocus()
    if query ~= "" then
        query = ""
        frame.search:SetValue("")
    end
    showPreview(section)
    applyView()
end

function W.Search(text)
    query = strtrim(text or ""):lower()
    if query ~= "" then
        -- every page, to search it; one that fails to build is reported and
        -- left out instead of stopping the search
        for _, section in ipairs(Registry.List()) do
            if not pages[section.id] then ns.Fault.Call("Settings: " .. tostring(section.label), getPage, section) end
        end
    end
    showPreview(Registry.Get(current or ""))
    applyView()
end

-- Refreshes come in bursts (a profile switch changes many settings, and
-- runtime writes happen in combat): mark the pages dirty and refresh once,
-- on the next frame, and only while the window is shown (OnShow catches up).
local dirty, queued = false, false

local function refreshNow()
    dirty = false
    for _, page in pairs(pages) do page:Refresh() end
    W.RefreshNav()
end

function W.RefreshAll()
    if not frame then return end
    dirty = true
    if queued or not frame:IsShown() then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if dirty and frame:IsShown() then refreshNow() end
    end)
end

--------------------------------------------------------------------------------
-- Import and export
--------------------------------------------------------------------------------

local dialog

local function buildDialog()
    local d = UI.Panel(ns.Root, { name = "SuuUIProfileDialog", title = "Export profile", closable = true,
        width = 560, height = 330, solid = true })
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetPoint("CENTER")
    d:EnableMouse(true)
    tinsert(UISpecialFrames, "SuuUIProfileDialog")

    d.hint = UI.Text(d.body, "caption", "ink-muted")
    d.hint:SetPoint("TOPLEFT")

    local box = CreateFrame("Frame", nil, d.body)
    box:SetPoint("TOPLEFT", 0, -20)
    box:SetPoint("RIGHT")
    box:SetHeight(170)
    UI.Fill(box, "surface-sunk"):SetAllPoints()
    UI.Border(box, "gilt-line")
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", S["space-4"], -S["space-3"])
    scroll:SetPoint("BOTTOMRIGHT", -26, S["space-3"])
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ns.Fonts.Get("caption"))
    edit:SetWidth(490)
    edit:SetScript("OnEscapePressed", function() d:Hide() end)
    scroll:SetScrollChild(edit)
    d.edit = edit

    d.name = UI.TextField(d.body, { width = 260, placeholder = "Name for the new profile" })
    d.name:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -S["space-4"])
    d.action = UI.Button(d.body, { text = "Import", variant = "primary", onClick = function() W.DoImport() end })
    d.action:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -S["space-4"])
    d.status = UI.Text(d.body, "caption", "ember-text")
    d.status:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -S["space-3"])
    return d
end

function W.Export()
    dialog = dialog or buildDialog()
    local data = Profiles.Export()
    dialog:SetTitle("Export profile", data.name)
    dialog.hint:SetValue("Ctrl+A, Ctrl+C copies it. Paste it into Import on another character.")
    dialog.edit:SetText(ns.Serialize.Encode({ v = 1, name = data.name, data = data.data }))
    dialog.name:Hide()
    dialog.action:Hide()
    dialog.status:SetValue("")
    dialog:Show()
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
end

function W.Import()
    dialog = dialog or buildDialog()
    dialog:SetTitle("Import profile", "")
    dialog.hint:SetValue("Paste a profile string. It becomes a new profile and this character switches to it.")
    dialog.edit:SetText("")
    dialog.name:SetValue("")
    dialog.name:Show()
    dialog.action:Show()
    dialog.status:SetValue("")
    dialog:Show()
    dialog.edit:SetFocus()
end

function W.DoImport()
    local value, err = ns.Serialize.Decode(dialog.edit:GetText())
    if type(value) ~= "table" or type(value.data) ~= "table" then
        dialog.status:SetValue(err or "This isn't a SuuUI profile string.")
        return
    end
    local name = strtrim(dialog.name:GetValue() or "")
    if name == "" then name = (value.name or "Imported") .. " (imported)" end
    local ok, why = Profiles.Import(name, value.data)
    if not ok then
        dialog.status:SetValue(why or "That didn't work.")
        return
    end
    dialog:Hide()
    ns.Print(("Imported %s and switched to it."):format(name))
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function profileOptions()
    local options = {}
    for _, name in ipairs(Profiles.List()) do options[#options + 1] = { value = name, label = name } end
    return options
end

local function build()
    local f = UI.Panel(ns.Root, { name = "SuuUISettings", width = WIDTH, height = HEIGHT, ornament = true })
    f.body:Hide()
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER")
    f:Hide()
    f:SetScript("OnShow", function(self)
        Motion.Enter(self, T.duration["dur-fast"])
        if dirty then refreshNow() end
    end)
    tinsert(UISpecialFrames, "SuuUISettings")
    frame = f

    -- Header: the jewel and wordmark, "Settings", search, profile, close.
    local jewel = UI.Diamond(f, 14, "gilt")
    jewel:SetPoint("CENTER", f, "TOPLEFT", S["space-5"] + 10, -(S["space-5"] + 15))
    local gem = UI.Diamond(f, 7, "arcane")
    gem:SetPoint("CENTER", jewel, "CENTER")
    local word = UI.Text(f, "unit-name-lg", "ink")
    word:SetValue("SuuUI")
    word:SetPoint("LEFT", jewel, "CENTER", 16, 0)
    local title = UI.Text(f, "header", "ink-muted")
    title:SetValue("Settings")
    title:SetPoint("LEFT", word, "RIGHT", S["space-5"], 0)

    f.close = UI.CloseButton(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -S["space-5"], -(S["space-5"] + 4))
    f.profile = UI.Select(f, { width = 190, options = profileOptions(), value = Profiles.Current(),
        onChange = function(name)
            local ok, err = Profiles.Use(name)
            if not ok then
                ns.Print(err)
                f.profile:SetValue(Profiles.Current())
            end
        end })
    f.profile:SetPoint("RIGHT", f.close, "LEFT", -S["space-5"], 0)
    -- through the error catcher: an error here was silent before
    f.search = UI.TextField(f, { width = 280, placeholder = "Search settings",
        onTextChanged = function(text) ns.Fault.Call("Settings search", W.Search, text) end })
    f.search:SetPoint("RIGHT", f.profile, "LEFT", -S["space-5"], 0)

    -- Body: nav | content | preview
    local top, bottom = HEAD_H, FOOT_H
    f.nav = scrollArea(f)
    f.nav:SetPoint("TOPLEFT", 0, -top)
    f.nav:SetPoint("BOTTOMLEFT", 0, bottom)
    f.nav:SetWidth(NAV_W)
    f.navButtons = {}
    local navRule = UI.Fill(f, "gilt-faint", "ARTWORK")
    navRule:SetPoint("TOPLEFT", NAV_W, -top)
    navRule:SetPoint("BOTTOMLEFT", NAV_W, bottom)
    navRule:SetWidth(ns.Pixel.Size(f))

    local preview = CreateFrame("Frame", nil, f)
    preview:SetPoint("TOPRIGHT", -1, -top)
    preview:SetPoint("BOTTOMRIGHT", -1, bottom)
    preview:SetWidth(PREVIEW_W)
    UI.Fill(preview, "surface-sunk"):SetAllPoints()
    local previewRule = UI.Fill(preview, "gilt-faint", "ARTWORK")
    previewRule:SetPoint("TOPLEFT")
    previewRule:SetPoint("BOTTOMLEFT")
    previewRule:SetWidth(ns.Pixel.Size(f))
    preview.title = UI.Text(preview, "caption", "ink-muted")
    preview.title:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    preview.note = UI.Text(preview, "caption", "ink-muted")
    preview.note:SetPoint("BOTTOMLEFT", S["space-5"], S["space-5"])
    -- where a section's view sits: under the title, above the note, clipped
    preview.area = CreateFrame("Frame", nil, preview)
    preview.area:SetPoint("TOPLEFT", preview.title, "BOTTOMLEFT", 0, -S["space-4"])
    preview.area:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -S["space-5"], S["space-5"] * 2 + 12)
    preview.area:SetClipsChildren(true)
    f.preview = preview

    f.content = scrollArea(f, S["space-3"])
    f.content:SetPoint("TOPLEFT", NAV_W + S["space-6"], -(top + S["space-5"]))
    f.content:SetPoint("BOTTOMRIGHT", -(PREVIEW_W + S["space-6"]), bottom)
    f.content.child:SetWidth(WIDE_W)
    f.pagesStack = Layout.Stack(f.content.child, { gap = S["space-7"], autoSize = "height", padding = { 0, 0, 0, S["space-6"] } })
    f.empty = UI.Text(f.content.child, "body", "ink-muted")
    f.empty:SetValue("No setting matches that search.")
    f.empty:SetPoint("TOPLEFT")
    f.empty:Hide()

    -- Footer
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", S["space-5"], 0)
    foot:SetPoint("BOTTOMRIGHT", -S["space-5"], 0)
    foot:SetHeight(FOOT_H)
    local footRule = UI.Hairline(f, "gilt-faint")
    footRule:SetPoint("BOTTOMLEFT", 0, FOOT_H)
    footRule:SetPoint("BOTTOMRIGHT", 0, FOOT_H)
    local import = UI.Button(foot, { text = "Import", onClick = W.Import })
    import:SetPoint("LEFT")
    local export = UI.Button(foot, { text = "Export", onClick = W.Export })
    export:SetPoint("LEFT", import, "RIGHT", S["space-3"], 0)
    local resetSection = UI.Button(foot, { text = "Reset section", onClick = function(self)
        local page = pages[current]
        if not page or query ~= "" then return end
        if not resetTimer then
            self:SetLabel("Click again to reset")
            resetTimer = C_Timer.NewTimer(3, function() resetTimer = nil; disarmReset() end)
            return
        end
        disarmReset()
        for _, row in ipairs(page.rows) do
            -- turning modules on and off is not a setting to reset
            local moduleToggle = row.def.key == "enabled" and ns.Modules.Get(row.namespace or "")
            if row.doReset and row.isModified() and not moduleToggle then row.doReset() end
        end
    end })
    resetSection:SetPoint("LEFT", export, "RIGHT", S["space-3"], 0)
    f.resetSection = resetSection
    local done = UI.Button(foot, { text = "Done", variant = "primary", onClick = function() f:Hide() end })
    done:SetPoint("RIGHT")
    local note = UI.Text(foot, "caption", "ink-muted")
    note:SetValue("Changes apply as you make them.")
    note:SetPoint("RIGHT", done, "LEFT", -S["space-5"], 0)

    -- Live: every settings change refreshes the rows and the nav.
    Events.On("SUUUI_SETTING_CHANGED", function() W.RefreshAll() end, "SettingsWindow")
    -- Profiles switched, created, deleted or mapped to roles: the header's
    -- picker and the Profiles page's lists follow.
    local function profilesChanged()
        f.profile:SetOptions(profileOptions())
        f.profile:SetValue(Profiles.Current())
        W.RefreshAll()
    end
    for _, e in ipairs({ "SUUUI_PROFILE_CHANGED", "SUUUI_PROFILES_CHANGED", "SUUUI_ROLE_PROFILES_CHANGED",
                         "SUUUI_ROLE_CHANGED" }) do
        Events.On(e, profilesChanged, "SettingsWindow")
    end
    -- A page goes when its section does, when its section is merged into
    -- another now, and when the sections merged into it changed (it's built
    -- again, with them).
    local function listed(id)
        local s = Registry.Get(id)
        return s ~= nil and Registry.MergedInto(s) == nil
    end
    local function mergedIds(id)
        local ids = {}
        for _, m in ipairs(Registry.Merged(id)) do ids[#ids + 1] = m.id end
        return table.concat(ids, ",")
    end
    Events.On("SUUUI_SETTINGS_SECTIONS_CHANGED", function()
        for id, page in pairs(pages) do
            if not listed(id) or page.section ~= Registry.Get(id) or page.merged ~= mergedIds(id) then
                frame.pagesStack:Remove(page.frame)
                page.frame:Hide()
                pages[id] = nil
            end
        end
        buildNav()
        if not listed(current or "") then
            -- (a merged section opens the page it now shows on)
            W.Show(current)
        else
            getPage(Registry.Get(current))
            if query ~= "" then
                for _, section in ipairs(Registry.List()) do getPage(section) end
            end
            applyView()
        end
    end, "SettingsWindow")
    for _, e in ipairs({ "SUUUI_MODULE_ENABLED", "SUUUI_MODULE_DISABLED", "SUUUI_MODULE_ERRORED" }) do
        Events.On(e, function() W.RefreshAll() end, "SettingsWindow")
    end

    buildNav()
    return f
end

function W.Open(id)
    if not frame then build() end
    frame.profile:SetOptions(profileOptions())
    frame.profile:SetValue(Profiles.Current())
    frame:Show()
    W.Show(id or current)
end

function W.Toggle()
    if frame and frame:IsShown() then frame:Hide() else W.Open() end
end

function W.Close()
    if frame then frame:Hide() end
end
