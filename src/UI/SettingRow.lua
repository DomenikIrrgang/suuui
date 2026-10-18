-- UI/SettingRow.lua
-- SettingRow: one setting, with what it does, its control, and a way back to
-- the default. SettingsGroup: a titled block of rows.
--
--   local row = UI.SettingRow(parent, { label, description, control = ctl, stacked = false,
--                                       onReset = fn, width = 600 })
--   row:SetModified(changed)            an ink diamond before the label, the reset arrow
--   row:SetDisabled(disabled, reason)   label to ink-muted, control dimmed, a lock and the reason
--
--   local group = UI.SettingsGroup(parent, { title, meta, description, width })
--   group:AddRow(row); group:SetMeta("2 changed")

local _, ns = ...

local UI, T, Layout = ns.UI, ns.Tokens, ns.Layout
local S = T.space

local RESET_ICON = "Interface\\Buttons\\UI-RefreshButton"
local LOCK_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
local RESET_COL = 24

--------------------------------------------------------------------------------
-- SettingRow
--------------------------------------------------------------------------------

local Row = {}

-- Lays the row out now, and once more on the next frame: WoW wraps text at
-- the next render, so a description's wrapped height is only right then.
function Row:Relayout()
    self:Arrange()
    if not self.relayoutQueued then
        self.relayoutQueued = true
        C_Timer.After(0, function()
            self.relayoutQueued = false
            self:Arrange()
        end)
    end
end

function Row:Arrange()
    local width = self:GetWidth()
    local ctl = self.control
    local ctlW, ctlH = 0, 0
    if ctl then ctlW, ctlH = ctl:GetWidth(), ctl:GetHeight() end
    local textW = width - RESET_COL - S["space-5"] - (self.stacked and 0 or (ctlW + S["space-5"]))

    local x = self.modified and (5 + S["space-3"]) or 0
    self.dot:SetShown(self.modified and not self.disabled)

    local textH = self.label:GetStringHeight()
    if self.desc:IsShown() then
        self.desc:SetFixedWidth(textW)
        textH = textH + 1 + self.desc:GetStringHeight()
    end
    if self.why:IsShown() then
        self.whyText:SetWidth(textW - 15)
        textH = textH + 2 + math.max(11, self.whyText:GetStringHeight())
    end

    local height
    if self.stacked then
        height = S["space-4"] + textH + (ctl and (S["space-3"] + ctlH) or 0) + S["space-4"]
    else
        height = math.max(textH, ctlH) + S["space-4"] * 2
    end
    local top = self.stacked and S["space-4"] or (height - textH) / 2

    self.label:ClearAllPoints()
    self.label:SetPoint("TOPLEFT", x, -top)
    self.dot:ClearAllPoints()
    self.dot:SetPoint("CENTER", self, "TOPLEFT", 2.5, -top - self.label:GetStringHeight() / 2)
    self.desc:ClearAllPoints()
    self.desc:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", -x, -1)
    self.why:ClearAllPoints()
    self.why:SetPoint("TOPLEFT", self.desc:IsShown() and self.desc or self.label, "BOTTOMLEFT", self.desc:IsShown() and 0 or -x, -2)

    if ctl then
        ctl:ClearAllPoints()
        if self.stacked then
            ctl:SetPoint("TOPLEFT", 0, -(S["space-4"] + textH + S["space-3"]))
        else
            ctl:SetPoint("RIGHT", self, "RIGHT", -(RESET_COL + S["space-5"]), 0)
        end
    end
    self:SetHeight(height)
end

function Row:SetDescription(text)
    if text == self.descValue then return end
    self.descValue = text
    self.desc:SetValue(text or "")
    self.desc:SetShown(text ~= nil and text ~= "")
    self:Relayout()
end

function Row:SetModified(modified)
    self.modified = modified and true or false
    local canReset = self.modified and not self.disabled
    self.reset:SetAlpha(canReset and 1 or 0)
    self.reset:EnableMouse(canReset)
    self:Relayout()
end

function Row:SetDisabled(disabled, reason)
    self.disabled = disabled and true or false
    self.label:SetColor(self.disabled and "ink-muted" or "ink")
    if self.control and self.control.SetDisabled then self.control:SetDisabled(self.disabled) end
    self.why:SetShown(self.disabled and reason ~= nil)
    self.whyText:SetValue(reason or "")
    self:SetModified(self.modified)
end

function UI.SettingRow(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Row)
    f:SetWidth(opts.width or 600)
    f.stacked = opts.stacked

    f.rule = UI.Hairline(f, "gilt-faint")
    f.rule:SetPoint("TOPLEFT")
    f.rule:SetPoint("TOPRIGHT")

    f.dot = UI.Diamond(f, 5, "ink")
    f.label = UI.Text(f, "label", "ink")
    f.label:SetValue(opts.label or "")
    f.desc = UI.Text(f, "caption", "ink-muted")
    f.desc:SetWordWrap(true)
    f.desc:SetJustifyH("LEFT")
    f.desc:SetValue(opts.description or "")
    f.desc:SetShown(opts.description ~= nil and opts.description ~= "")

    f.why = CreateFrame("Frame", nil, f)
    f.why:SetSize(1, 12)
    local lock = f.why:CreateTexture(nil, "ARTWORK")
    lock:SetTexture(LOCK_ICON)
    lock:SetDesaturated(true)
    UI.Paint(lock, "ink-muted")
    lock:SetSize(11, 11)
    lock:SetPoint("TOPLEFT", 0, -1)
    f.whyText = UI.Text(f.why, "caption", "ink-muted")
    f.whyText:SetWordWrap(true)
    f.whyText:SetJustifyH("LEFT")
    f.whyText:SetPoint("TOPLEFT", lock, "TOPRIGHT", S["space-2"], 1)
    f.why:Hide()

    local reset = CreateFrame("Button", nil, f)
    reset:SetSize(22, 22)
    reset:SetPoint("RIGHT", -1, 0)
    reset.edge = UI.Border(reset, "gilt-line")
    reset.edge:SetShown(false)
    reset.icon = reset:CreateTexture(nil, "ARTWORK")
    reset.icon:SetTexture(RESET_ICON)
    reset.icon:SetDesaturated(true)
    UI.Paint(reset.icon, "ink-muted")
    reset.icon:SetSize(14, 14)
    reset.icon:SetPoint("CENTER")
    reset:SetScript("OnEnter", function(b)
        b.edge:SetShown(true)
        UI.Paint(b.icon, "ink")
        UI.ShowTooltip(b, { title = "Reset to default" })
    end)
    reset:SetScript("OnLeave", function(b)
        b.edge:SetShown(false)
        UI.Paint(b.icon, "ink-muted")
        UI.HideTooltip()
    end)
    reset:SetScript("OnClick", function() if opts.onReset then opts.onReset() end end)
    f.reset = reset

    if opts.control then
        f.control = opts.control
        f.control:SetParent(f)
        f.control:HookScript("OnSizeChanged", function() f:Relayout() end)
    end
    f:SetScript("OnSizeChanged", function(self, w)
        if w ~= self.lastWidth then
            self.lastWidth = w
            self:Relayout()
        end
    end)
    f:SetModified(false)
    return f
end

--------------------------------------------------------------------------------
-- SettingsGroup
--------------------------------------------------------------------------------

local Group = {}

function Group:AddRow(row)
    row:SetWidth(self:GetWidth())
    self.stack:Add(row)
    return row
end

function Group:SetMeta(text)
    self.meta:SetValue(text or "")
end

function Group:Relayout()
    self:Arrange()
    if not self.relayoutQueued then
        self.relayoutQueued = true
        C_Timer.After(0, function()
            self.relayoutQueued = false
            self:Arrange()
        end)
    end
end

function Group:Arrange()
    local headH = self.title:GetStringHeight()
    if self.desc:IsShown() then
        self.desc:SetFixedWidth(self:GetWidth())
        headH = headH + S["space-1"] + self.desc:GetStringHeight()
    end
    self.rows:ClearAllPoints()
    self.rows:SetPoint("TOPLEFT", 0, -(headH + S["space-4"]))
    self:SetHeight(headH + S["space-4"] + self.rows:GetHeight())
end

function UI.SettingsGroup(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Group)
    f:SetWidth(opts.width or 600)
    f.title = UI.Text(f, "header", "gilt-text")
    f.title:SetPoint("TOPLEFT")
    f.title:SetValue(opts.title or "")
    f.meta = UI.Text(f, "caption", "ink-muted")
    f.meta:SetPoint("TOPRIGHT")
    f.meta:SetValue(opts.meta or "")
    f.desc = UI.Text(f, "caption", "ink-muted")
    f.desc:SetWordWrap(true)
    f.desc:SetJustifyH("LEFT")
    f.desc:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -S["space-1"])
    f.desc:SetValue(opts.description or "")
    f.desc:SetShown(opts.description ~= nil)

    f.rows = CreateFrame("Frame", nil, f)
    f.rows:SetWidth(f:GetWidth())
    f.stack = Layout.Stack(f.rows, { autoSize = "height" })
    f.rows:SetScript("OnSizeChanged", function() f:Relayout() end)
    f:Relayout()
    return f
end
