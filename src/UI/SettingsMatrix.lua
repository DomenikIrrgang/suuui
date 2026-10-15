-- UI/SettingsMatrix.lua
-- Settings that repeat per row as one grid (design component
-- SettingsMatrix): rows down, options across. A sunk box in a gilt-faint
-- edge; a 28px header of caption ink-muted column names, centred; 36px rows
-- on gilt-faint rules: the row's name in label (its description under it in
-- caption), then a checkbox per cell, a small select, or "—" in ink-faint
-- where the option doesn't apply. The `master` column is the row's on/off:
-- off greys the name and disables its other cells, which keep their values.
--
--   local m = UI.SettingsMatrix(parent, {
--       width = 640,
--       columns = { { key = "on", label = "On", width = 34, master = true },
--                   { key = "conf", label = "Confidence", width = 78, kind = "select",
--                     options = { { value = 70, label = "70%" } }, title = "…" } },
--       rows = { { key = "role", label = "Your role is needed", description = "…" } },
--       onChange = fn(value),
--   })
--   m:SetValue({ role = { on = true, conf = 70 }, ... })  -- a cell with no value: "—"
--   m:GetValue()

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local HEAD_H = 28
local ROW_H = 36
local GAP = S["space-3"]

local Matrix = {}

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

function Matrix:SetValue(value)
    self.value = copy(value)
    for _, row in ipairs(self.rowFrames) do
        local vals = self.value[row.def.key] or {}
        local on = true
        for _, col in ipairs(self.columns) do
            if col.master then on = vals[col.key] and true or false end
        end
        row.name:SetColor(on and "ink" or "ink-faint")
        for _, col in ipairs(self.columns) do
            local cell = row.cells[col.key]
            local v = vals[col.key]
            cell.none:SetShown(v == nil)
            if cell.control then
                cell.control:SetShown(v ~= nil)
                if v ~= nil then cell.control:SetValue(v) end
                if cell.control.SetDisabled then cell.control:SetDisabled(not col.master and not on) end
            end
        end
    end
end

function Matrix:GetValue() return copy(self.value) end

function Matrix:Set(rowKey, colKey, v)
    self.value[rowKey] = self.value[rowKey] or {}
    self.value[rowKey][colKey] = v
    self:SetValue(self.value)
    if self.onChange then self.onChange(self:GetValue()) end
end

function UI.SettingsMatrix(parent, opts)
    local m = CreateFrame("Frame", nil, parent)
    Mixin(m, Matrix)
    m.columns, m.onChange, m.rowFrames, m.value = opts.columns, opts.onChange, {}, {}
    local width = opts.width or 640
    UI.Fill(m, "surface-sunk"):SetAllPoints()
    UI.Border(m, "gilt-faint")
    -- the columns from the right, each centred in its width
    local x = width - S["space-4"]
    local colX = {}
    for i = #m.columns, 1, -1 do
        local col = m.columns[i]
        x = x - col.width
        colX[col.key] = x
        x = x - GAP
    end
    local nameW = x - S["space-4"]
    for _, col in ipairs(m.columns) do
        local h = UI.Text(m, "caption", "ink-muted")
        h:SetWidth(col.width + GAP)
        h:SetJustifyH("CENTER")
        h:SetWordWrap(false)
        h:SetPoint("CENTER", m, "TOPLEFT", colX[col.key] + col.width / 2, -HEAD_H / 2)
        h:SetValue(col.label)
        if col.title then
            local hit = CreateFrame("Frame", nil, m)
            hit:SetAllPoints(h)
            hit:SetScript("OnEnter", function(self) UI.ShowTooltip(self, { title = col.label, description = col.title }) end)
            hit:SetScript("OnLeave", function() UI.HideTooltip() end)
        end
    end
    local y = HEAD_H
    for _, def in ipairs(opts.rows) do
        local row = CreateFrame("Frame", nil, m)
        row.def = def
        row:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
        row:SetSize(width, ROW_H)
        local rule = UI.Fill(row, "gilt-faint", "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", S["space-4"], 0)
        rule:SetPoint("TOPRIGHT", -S["space-4"], 0)
        row.name = UI.Text(row, "label", "ink")
        row.name:SetWidth(nameW)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.name:SetValue(def.label)
        if def.description then
            row.name:SetPoint("BOTTOMLEFT", row, "LEFT", S["space-4"], 1)
            row.desc = UI.Text(row, "caption", "ink-muted")
            row.desc:SetPoint("TOPLEFT", row, "LEFT", S["space-4"], -1)
            row.desc:SetWidth(nameW)
            row.desc:SetJustifyH("LEFT")
            row.desc:SetWordWrap(false)
            row.desc:SetValue(def.description)
        else
            row.name:SetPoint("LEFT", S["space-4"], 0)
        end
        row.cells = {}
        for _, col in ipairs(m.columns) do
            local cell = {}
            local cx = colX[col.key] + col.width / 2
            cell.none = UI.Text(row, "body", "ink-faint")
            cell.none:SetPoint("CENTER", row, "LEFT", cx, 0)
            cell.none:SetValue("—")
            if col.kind == "select" then
                cell.control = UI.Select(row, { width = col.width, options = col.options,
                    onChange = function(v) m:Set(def.key, col.key, v) end })
                cell.control:SetHeight(24)
            else
                cell.control = UI.Checkbox(row, { onChange = function(on) m:Set(def.key, col.key, on) end })
            end
            cell.control:SetPoint("CENTER", row, "LEFT", cx, 0)
            row.cells[col.key] = cell
        end
        m.rowFrames[#m.rowFrames + 1] = row
        y = y + ROW_H
    end
    m:SetSize(width, y + S["space-2"])
    return m
end
