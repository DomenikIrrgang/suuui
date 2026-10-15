-- UI/Select.lua
-- One choice (or several) from a list too long or wordy for Segmented.
--
--   UI.Select(parent, {
--       options = { { value = "a", label = "Alpha", note = "…", disabled = true, reason = "…",
--                     icon = <texture or file ID> },   -- 0.9: an icon left of the label
--                   -- 0.13: summary = "Sort: Skill", what the closed field
--                   -- shows for it (the list keeps the label)
--                   { heading = "Group title" }, … },
--       value = "a", onChange = fn(value), width = 190, placeholder = "Choose",
--       multiple = false,   -- the value is then a list; Select all / Clear at the top
--                           -- (none chosen: the placeholder, else "None")
--       maxShown = 2,       -- multiple: past this many, the field reads "3 of 6"
--       maxRows = 10,       -- rows the open list shows; longer lists scroll
--                           -- (mouse wheel, a thin scrollbar on the right)
--       search = true,      -- a search field at the top once the list is longer
--                           -- than maxRows (false: never); Enter picks the first match
--       lookup = fn(query), -- extra options for what was typed, shown first
--                           -- (e.g. a spell found by its ID); implies a search field
--       bare = true,        -- 0.10: no field until hovered (a panel header's
--                           -- select): text in textStyle/textColor, 24px tall,
--                           -- as wide as the chosen label (up to `width`)
--       textStyle = "header", textColor = "gilt-text",
--   })
--   select:SetOptions(options), select:SetValue(v), select:SetDisabled(disabled)
--
-- Closed: a gilt-line field on surface-sunk with the value and a chevron.
-- Open: a surface list under the field; the chosen option in ink with an
-- arcane check. A click anywhere else closes it.

local _, ns = ...

local UI, T, Motion = ns.UI, ns.Tokens, ns.Motion
local S = T.space

local ROW_H = 28
local MAX_ROWS = 10
local SEARCH_H = 30

--------------------------------------------------------------------------------
-- One list at a time, plus a screen-wide catcher that closes it.
--------------------------------------------------------------------------------

local openList
local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("FULLSCREEN_DIALOG")
catcher:Hide()
catcher:RegisterForClicks("AnyDown")
catcher:SetScript("OnClick", function() if openList then openList:Close() end end)

local Select = {}

local function contains(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

function Select:Summary()
    if not self.multiple then
        for _, o in ipairs(self.options) do
            if not o.heading and o.value == self.value then return o.summary or o.label end
        end
        if self.lookedUp and self.lookedUp.value == self.value then return self.lookedUp.label end
        return self.placeholder or ""
    end
    local chosen, total = {}, 0
    for _, o in ipairs(self.options) do
        if not o.heading then
            total = total + 1
            if contains(self.value, o.value) then chosen[#chosen + 1] = o.label end
        end
    end
    if #chosen == 0 then return self.placeholder or "None" end
    if #chosen == total then return "All" end
    if #chosen > (self.maxShown or 2) then return ("%d of %d"):format(#chosen, total) end
    return table.concat(chosen, ", ")
end

function Select:SetValue(v)
    self.value = self.multiple and { unpack(v or {}) } or v
    local summary = self:Summary()
    self.text:SetValue(summary)
    -- the placeholder in ink-muted (nothing chosen)
    local empty = self.multiple and #self.value == 0 or (not self.multiple and self.value == nil)
    if not self.bare then self.text:SetColor(empty and self.placeholder and "ink-muted" or "ink") end
    -- bare: as wide as its label, chevron included
    if self.bare then
        local w = UI.MeasureText(self.textStyle, summary) + S["space-2"] * 2 + S["space-1"] + 12
        self:SetWidth(math.min(self.maxWidth, math.ceil(w)))
    end
    if self.list and self.list:IsShown() then self:Refresh() end
end

function Select:SetOptions(options)
    self.options = options or {}
    self:SetValue(self.value)
end

function Select:SetDisabled(disabled)
    self.disabled = disabled and true or false
    self:SetAlpha(self.disabled and T.opacity["opacity-disabled"] or 1)
    self.border:SetColor((not self.disabled and self:IsMouseOver()) and "gilt" or "gilt-line")
    if self.disabled then self:Close() end
end

function Select:Close()
    if self.list then
        if self.list.search then self.list.search.edit:ClearFocus() end
        self.list:Hide()
    end
    if openList == self then
        openList = nil
        catcher:Hide()
    end
end

local function choose(self, o)
    if o.heading or o.disabled then return end
    if self.multiple then
        local v = { unpack(self.value or {}) }
        if contains(v, o.value) then
            for i = #v, 1, -1 do if v[i] == o.value then table.remove(v, i) end end
        else
            v[#v + 1] = o.value
        end
        self:SetValue(v)
        if self.onChange then self.onChange({ unpack(self.value) }) end
    else
        self:Close()
        self.lookedUp = o
        if o.value ~= self.value then
            self:SetValue(o.value)
            if self.onChange then self.onChange(o.value) end
        end
    end
end

local function row(self, i)
    local list = self.list
    list.rows[i] = list.rows[i] or (function()
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(ROW_H)
        r.hover = UI.Fill(r, "surface-raised")
        r.hover:SetAllPoints()
        r.hover:Hide()
        r.box = UI.Checkbox(r, { size = 14 })
        r.box:SetPoint("LEFT", S["space-4"], 0)
        r.box:EnableMouse(false)
        r.label = UI.Text(r, "body", "ink")
        -- an option's icon (spells, talents) left of its label
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.icon:Hide()
        r.note = UI.Text(r, "caption", "ink-muted")
        r.note:SetPoint("RIGHT", -S["space-4"], 0)
        r.check = UI.Check(r, 14, "arcane")
        r.check:SetPoint("RIGHT", -S["space-4"], 0)
        -- a heading's rule (above every heading but the first)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetColorTexture(UI.RGBA("gilt-faint"))
        r.rule:SetHeight(1)
        r.rule:SetPoint("TOPLEFT", S["space-2"], -S["space-1"])
        r.rule:SetPoint("TOPRIGHT", -S["space-2"], -S["space-1"])
        r.rule:Hide()
        r:SetScript("OnEnter", function(b)
            if not (b.option.heading or b.option.disabled) then b.hover:Show() end
            if b.option.disabled and b.option.reason then
                UI.ShowTooltip(b, { title = b.option.label, description = b.option.reason })
            end
        end)
        r:SetScript("OnLeave", function(b) b.hover:Hide(); UI.HideTooltip() end)
        r:SetScript("OnClick", function(b) choose(self, b.option) end)
        return r
    end)()
    return list.rows[i]
end

-- The options the search leaves (headings only when something under them
-- matches).
function Select:View()
    local q = (self.query or ""):lower()
    if q == "" then return self.options end
    local out, heading = {}, nil
    if self.lookup then
        for _, o in ipairs(self.lookup(self.query) or {}) do out[#out + 1] = o end
    end
    for _, o in ipairs(self.options) do
        if o.heading then
            heading = o
        elseif tostring(o.label or ""):lower():find(q, 1, true) then
            if heading then out[#out + 1] = heading; heading = nil end
            out[#out + 1] = o
        end
    end
    return out
end

function Select:Refresh()
    local list = self.list
    for _, r in ipairs(list.rows) do r:Hide() end
    local y = S["space-2"]
    -- as wide as the longest entry needs (a narrow field can open a wide list)
    local width = math.max(self:GetWidth(), self.minListWidth or 0)
    local check = (self.multiple and 14 + S["space-3"]) or (14 + S["space-3"])
    for _, o in ipairs(self.options) do
        local text = o.heading or o.label
        if text then
            local w = UI.MeasureText(o.heading and "header" or "body", tostring(text))
            local note = o.note and (UI.MeasureText("caption", tostring(o.note)) + S["space-3"]) or 0
            width = math.max(width, S["space-2"] * 2 + S["space-4"] * 2 + w + note + check + 8)
        end
    end
    local maxRows = self.maxRows or MAX_ROWS
    local searching = self.search ~= false and (#self.options > maxRows or self.lookup ~= nil)
    list.search:SetShown(searching)
    if searching then
        list.search:ClearAllPoints()
        list.search:SetPoint("TOPLEFT", S["space-2"], -y)
        list.search:SetPoint("RIGHT", list, "RIGHT", -S["space-2"], 0)
        y = y + SEARCH_H + S["space-2"]
    end
    if self.multiple then
        list.bulk:SetPoint("TOPLEFT", S["space-2"] + S["space-4"], -y - 4)
        list.bulk:Show()
        y = y + 26
    else
        list.bulk:Hide()
    end
    local view = self:View()
    self.view = view
    local maxOffset = math.max(0, #view - maxRows)
    self.offset = math.max(0, math.min(self.offset or 0, maxOffset))
    local scrolling = maxOffset > 0
    local rowsTop = y
    for i = 1, math.min(maxRows, #view) do
        local o = view[self.offset + i]
        local r = row(self, i)
        r.option = o
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", S["space-2"], -y)
        r:SetPoint("RIGHT", list, "RIGHT", -(S["space-2"] + (scrolling and 8 or 0)), 0)
        r.label:ClearAllPoints()
        if o.heading then
            -- a category: the header face in gilt, a rule above it (not
            -- the first), set apart from the options under it
            local first = i == 1
            local hh = first and 22 or 30
            r:SetHeight(hh)
            r.label:SetStyle("header")
            r.label:SetColor("gilt-text")
            r.label:SetPoint("BOTTOMLEFT", S["space-4"], S["space-1"])
            r.label:SetValue(o.heading)
            r.rule:SetShown(not first)
            r.box:Hide()
            r.check:Hide()
            r.icon:Hide()
            r.note:SetValue("")
            y = y + hh
        else
            r.rule:Hide()
            local on = self.multiple and contains(self.value, o.value) or (not self.multiple and o.value == self.value)
            r:SetHeight(ROW_H)
            r.label:SetStyle("body")
            -- every option in ink (the design's); the check marks the chosen one
            r.label:SetColor(o.disabled and "ink-faint" or "ink")
            r.label:SetValue(o.label)
            r.icon:ClearAllPoints()
            local lead
            if self.multiple then
                r.box:Show()
                r.box:SetValue(on)
                r.check:Hide()
                r.icon:SetPoint("LEFT", r.box, "RIGHT", S["space-3"], 0)
                lead = { r.box, S["space-3"] }
            else
                r.box:Hide()
                r.check:SetShown(on)
                r.icon:SetPoint("LEFT", S["space-4"], 0)
            end
            if o.icon then
                r.icon:SetTexture(o.icon)
                r.icon:SetDesaturated(o.disabled and true or false)
                r.icon:Show()
                r.label:SetPoint("LEFT", r.icon, "RIGHT", S["space-2"], 0)
            else
                r.icon:Hide()
                if lead then r.label:SetPoint("LEFT", lead[1], "RIGHT", lead[2], 0)
                else r.label:SetPoint("LEFT", S["space-4"], 0) end
            end
            if o.font then r.label:SetFontObject(ns.Fonts.Get(o.font)) end
            r.note:SetValue(o.note or "")
            if o.note and not self.multiple and on then
                r.note:ClearAllPoints()
                r.note:SetPoint("RIGHT", r.check, "LEFT", -S["space-3"], 0)
            else
                r.note:ClearAllPoints()
                r.note:SetPoint("RIGHT", -S["space-4"], 0)
            end
            y = y + ROW_H
        end
        r:Show()
    end
    -- the scrollbar: a thin track with a thumb for the visible part
    list.track:SetShown(scrolling)
    list.thumb:SetShown(scrolling)
    if scrolling then
        local trackH = y - rowsTop
        list.track:ClearAllPoints()
        list.track:SetPoint("TOPRIGHT", list, "TOPRIGHT", -S["space-2"] - 2, -rowsTop)
        list.track:SetSize(3, trackH)
        local thumbH = math.max(16, trackH * maxRows / #view)
        list.thumb:ClearAllPoints()
        list.thumb:SetPoint("TOP", list.track, "TOP", 0, -(trackH - thumbH) * self.offset / maxOffset)
        list.thumb:SetSize(3, thumbH)
    end
    if #view == 0 then
        local r = row(self, 1)
        r.option = { heading = "No match" }
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", S["space-2"], -y)
        r:SetPoint("RIGHT", list, "RIGHT", -S["space-2"], 0)
        r:SetHeight(22)
        r.label:ClearAllPoints()
        r.label:SetStyle("caption")
        r.label:SetColor("ink-muted")
        r.label:SetPoint("LEFT", S["space-4"], -2)
        r.label:SetValue("No match")
        r.box:Hide(); r.check:Hide(); r.icon:Hide(); r.rule:Hide(); r.note:SetValue("")
        r:Show()
        y = y + 22
    end
    list:SetSize(width, y + S["space-2"])
end

function Select:Open()
    if self.disabled then return end
    if openList and openList ~= self then openList:Close() end
    if not self.list then
        local list = UI.Panel(ns.Root, { solid = true })
        list.body:SetScript("OnSizeChanged", nil)
        list.body:Hide()
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetToplevel(true)
        list:SetClampedToScreen(true)
        list.rows = {}
        local bulk = CreateFrame("Frame", nil, list)
        bulk:SetSize(200, 18)
        local all = CreateFrame("Button", nil, bulk)
        all.text = UI.Text(all, "caption", "ink-muted")
        all.text:SetValue("Select all")
        all.text:SetPoint("LEFT")
        all:SetSize(all.text:GetUnboundedStringWidth(), 18)
        all:SetPoint("LEFT")
        local none = CreateFrame("Button", nil, bulk)
        none.text = UI.Text(none, "caption", "ink-muted")
        none.text:SetValue("Clear")
        none.text:SetPoint("LEFT")
        none:SetSize(none.text:GetUnboundedStringWidth(), 18)
        none:SetPoint("LEFT", all, "RIGHT", S["space-5"], 0)
        for _, b in ipairs({ all, none }) do
            b:SetScript("OnEnter", function(x) x.text:SetColor("ink") end)
            b:SetScript("OnLeave", function(x) x.text:SetColor("ink-muted") end)
        end
        all:SetScript("OnClick", function()
            local v = {}
            for _, o in ipairs(self.options) do
                if not (o.heading or o.disabled) then v[#v + 1] = o.value end
            end
            self:SetValue(v)
            if self.onChange then self.onChange({ unpack(v) }) end
        end)
        none:SetScript("OnClick", function()
            self:SetValue({})
            if self.onChange then self.onChange({}) end
        end)
        list.bulk = bulk

        -- search (long lists) and the scrollbar
        list.search = UI.TextField(list, { width = 100, placeholder = "Search", onTextChanged = function(text)
            self.query, self.offset = text, 0
            self:Refresh()
        end })
        list.search.edit:SetScript("OnEnterPressed", function(e)
            for _, o in ipairs(self.view or {}) do
                if not (o.heading or o.disabled) then choose(self, o); break end
            end
            e:ClearFocus()
        end)
        list.track = list:CreateTexture(nil, "ARTWORK")
        list.track:SetColorTexture(UI.RGBA("gilt-faint"))
        list.thumb = list:CreateTexture(nil, "OVERLAY")
        list.thumb:SetColorTexture(UI.RGBA("ink-muted"))
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(_, delta)
            self.offset = (self.offset or 0) - delta * 3
            self:Refresh()
        end)
        self.list = list
    end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -S["space-1"])
    self.query, self.offset = "", 0
    self.list.search:SetValue("")
    self:Refresh()
    self.list:Show()
    if self.list.search:IsShown() then self.list.search.edit:SetFocus() end
    Motion.Enter(self.list, T.duration["dur-fast"])
    openList = self
    catcher:SetFrameLevel(math.max(0, self.list:GetFrameLevel() - 1))
    catcher:Show()
end

function UI.Select(parent, opts)
    local f = CreateFrame("Button", nil, parent)
    Mixin(f, Select)
    f:SetSize(opts.width or 190, 30)
    f.bg = UI.Fill(f, "surface-sunk")
    f.bg:SetAllPoints()
    f.border = UI.Border(f, "gilt-line")
    f.chevron = UI.Chevron(f, "ink-muted")
    f.chevron:SetPoint("RIGHT", -S["space-4"], 0)
    f.text = UI.Text(f, "body", "ink")
    f.text:SetPoint("LEFT", S["space-4"], 0)
    f.text:SetPoint("RIGHT", f.chevron, "LEFT", -S["space-3"], 0)
    f.text:SetWordWrap(false) -- one line, cut short in a narrow field
    f.multiple, f.maxShown, f.placeholder = opts.multiple, opts.maxShown, opts.placeholder
    f.minListWidth = opts.minListWidth
    f.maxRows, f.search, f.lookup = opts.maxRows, opts.search, opts.lookup
    f.onChange = opts.onChange
    f.options = opts.options or {}
    f:SetScript("OnClick", function(self)
        if self.list and self.list:IsShown() then self:Close() else self:Open() end
    end)
    f:SetScript("OnEnter", function(self)
        if self.disabled then return end
        self.border:SetColor("gilt")
        if self.bare then self.border:SetShown(true) end
    end)
    f:SetScript("OnLeave", function(self)
        self.border:SetColor("gilt-line")
        if self.bare then self.border:SetShown(false) end
    end)
    if opts.bare then
        f.bare, f.maxWidth = true, opts.width or 190
        f.textStyle = opts.textStyle or "body"
        f:SetHeight(24)
        f.bg:Hide()
        f.border:SetShown(false)
        f.text:SetStyle(f.textStyle)
        f.text:SetColor(opts.textColor or "ink")
        f.text:SetWordWrap(false)
        f.text:ClearAllPoints()
        f.text:SetPoint("LEFT", S["space-2"], 0)
        f.text:SetPoint("RIGHT", f.chevron, "LEFT", -S["space-1"], 0)
        f.chevron:ClearAllPoints()
        f.chevron:SetPoint("RIGHT", -S["space-2"], 0)
        f.minListWidth = opts.minListWidth or 200
    end
    f:SetScript("OnHide", function(self) self:Close() end)
    f:SetValue(opts.value)
    return f
end
