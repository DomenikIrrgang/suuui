-- UI/Select.lua
-- One choice (or several) from a list too long or wordy for Segmented.
--
--   UI.Select(parent, {
--       options = { { value = "a", label = "Alpha", note = "…", disabled = true, reason = "…" },
--                   { heading = "Group title" }, … },
--       value = "a", onChange = fn(value), width = 190, placeholder = "Choose",
--       multiple = false,   -- the value is then a list; Select all / Clear at the top
--       maxShown = 2,       -- multiple: past this many, the field reads "3 of 6"
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
            if not o.heading and o.value == self.value then return o.label end
        end
        return self.placeholder or ""
    end
    local chosen, total = {}, 0
    for _, o in ipairs(self.options) do
        if not o.heading then
            total = total + 1
            if contains(self.value, o.value) then chosen[#chosen + 1] = o.label end
        end
    end
    if #chosen == 0 then return "None" end
    if #chosen == total then return "All" end
    if #chosen > (self.maxShown or 2) then return ("%d of %d"):format(#chosen, total) end
    return table.concat(chosen, ", ")
end

function Select:SetValue(v)
    self.value = self.multiple and { unpack(v or {}) } or v
    self.text:SetValue(self:Summary())
    if self.list and self.list:IsShown() then self:Refresh() end
end

function Select:SetOptions(options)
    self.options = options or {}
    self:SetValue(self.value)
end

function Select:SetDisabled(disabled)
    self.disabled = disabled and true or false
    self:SetAlpha(self.disabled and T.opacity["opacity-disabled"] or 1)
    if self.disabled then self:Close() end
end

function Select:Close()
    if self.list then self.list:Hide() end
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
        r.note = UI.Text(r, "caption", "ink-muted")
        r.note:SetPoint("RIGHT", -S["space-4"], 0)
        r.check = UI.Check(r, 14, "arcane")
        r.check:SetPoint("RIGHT", -S["space-4"], 0)
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

function Select:Refresh()
    local list = self.list
    for _, r in ipairs(list.rows) do r:Hide() end
    local y = S["space-2"]
    local width = math.max(self:GetWidth(), self.minListWidth or 0)
    if self.multiple then
        list.bulk:SetPoint("TOPLEFT", S["space-2"] + S["space-4"], -y - 4)
        list.bulk:Show()
        y = y + 26
    else
        list.bulk:Hide()
    end
    for i, o in ipairs(self.options) do
        local r = row(self, i)
        r.option = o
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", S["space-2"], -y)
        r:SetPoint("RIGHT", list, "RIGHT", -S["space-2"], 0)
        r.label:ClearAllPoints()
        if o.heading then
            r:SetHeight(22)
            r.label:SetStyle("caption")
            r.label:SetColor("ink-muted")
            r.label:SetPoint("LEFT", S["space-4"], -2)
            r.label:SetValue(o.heading)
            r.box:Hide()
            r.check:Hide()
            r.note:SetValue("")
            y = y + 22
        else
            local on = self.multiple and contains(self.value, o.value) or (not self.multiple and o.value == self.value)
            r:SetHeight(ROW_H)
            r.label:SetStyle("body")
            r.label:SetColor(o.disabled and "ink-faint" or (on and "ink" or "ink-muted"))
            r.label:SetValue(o.label)
            if self.multiple then
                r.box:Show()
                r.box:SetValue(on)
                r.label:SetPoint("LEFT", r.box, "RIGHT", S["space-3"], 0)
                r.check:Hide()
            else
                r.box:Hide()
                r.label:SetPoint("LEFT", S["space-4"], 0)
                r.check:SetShown(on)
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
        self.list = list
    end
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -S["space-1"])
    self:Refresh()
    self.list:Show()
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
    f.multiple, f.maxShown, f.placeholder = opts.multiple, opts.maxShown, opts.placeholder
    f.minListWidth = opts.minListWidth
    f.onChange = opts.onChange
    f.options = opts.options or {}
    f:SetScript("OnClick", function(self)
        if self.list and self.list:IsShown() then self:Close() else self:Open() end
    end)
    f:SetScript("OnEnter", function(self) self.border:SetColor("gilt") end)
    f:SetScript("OnLeave", function(self) self.border:SetColor("gilt-line") end)
    f:SetScript("OnHide", function(self) self:Close() end)
    f:SetValue(opts.value)
    return f
end
