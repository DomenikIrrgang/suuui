-- UI/ThreatMeter.lua
-- The threat meter (design board "Threat meter"): a glass panel `meter-w`
-- wide, "Threat" and "on <target>" in its head, then rows `meter-row` tall.
-- It always keeps the height of `rows` rows (the damage meter's, beside it).
--
--   local m = UI.ThreatMeter(parent, { rows = 8 })
--   m:SetTarget(name)               -- may be secret (an enemy in a dungeon)
--   m:SetRows(list, opts)
--   m:SetMaxRows(n)                 -- 0.10: the height in rows, live
--
-- list: { { name, class, role, status, percent, raw, you }, ... } in group
-- order. role "TANK", "HEALER", "DAMAGER", "PET" or nil; status 0-3
-- (UnitThreatSituation; nil while unknown); percent the scaled % (0-100,
-- 100 pulls aggro) and raw the threat value, either possibly secret (nil:
-- unknown). opts:
--   show     "group" | "tanks" (tanks, pets and you) | "self"
--   byState  rows go by threat state, then group order (when the client
--            won't let the % be compared: a secret %), with a note in the
--            last slot; otherwise by % and ranked
--   marker   "role" | "class" | "none": what leads the name
--   raw      the threat number before the %
--   nameColor "class" | "ink"
-- Your row is outlined in ink; past the visible rows it takes the last slot.
--
-- States (only from the status, so they work on bosses too): a tank or pet
-- at 2 "Losing" (amber); anyone else at 2-3 "Aggro" (ember, glowing), at 1
-- "Pulling" (amber). A tank or pet holding the mob reads "Tanking".

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local isSecret = issecretvalue or function() return false end

local ROLE_ICON = {
    TANK = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleTank.tga",
    HEALER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleHealer.tga",
    DAMAGER = "Interface\\AddOns\\SuuUI\\Media\\Textures\\RoleDamage.tga",
}
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function holder(role) return role == "TANK" or role == "PET" end
-- a readable number (a secret one is never compared)
local function readable(v) return not isSecret(v) and type(v) == "number" end
local PCT_W, RAW_W = 34, 38

-- The state a row shows: tone and word, or nil.
local function stateOf(r)
    local s = r.status
    if isSecret(s) or type(s) ~= "number" then return nil end
    if holder(r.role) then return s == 2 and "warning" or nil, s == 2 and "Losing" or nil end
    if s >= 2 then return "danger", "Aggro" end
    if s == 1 then return "warning", "Pulling" end
end

-- a 70/30 mix of a token and surface-sunk (the design's colour-mix)
local function mix(token)
    local r, g, b = UI.RGBA(token)
    local sr, sg, sb = UI.RGBA("surface-sunk")
    return r * 0.7 + sr * 0.3, g * 0.7 + sg * 0.3, b * 0.7 + sb * 0.3
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local Row = {}

function Row:Set(r, rank, opts)
    local tone, word = stateOf(r)
    -- the edge: your row ink; a state's colour over it
    self.edge:SetColor(tone == "danger" and "ember" or tone == "warning" and "amber" or r.you and "ink" or "gilt-hairline")
    self.glow:SetShown(tone == "danger")
    -- the fill: the scaled %, straight to the engine (a secret one too)
    local pct = r.percent
    local known = isSecret(pct) or type(pct) == "number"
    if known then self.bar:SetValue(pct) else self.bar:SetValue(0) end
    -- rank (by % only)
    local x = S["space-2"]
    if rank then
        self.rank:SetValue(rank)
        self.rank:SetVisible(true)
        self.rank:ClearAllPoints()
        self.rank:SetPoint("LEFT", x, 0)
        x = x + 12 + S["space-3"]
    else
        self.rank:SetVisible(false)
    end
    -- the mark before the name
    self.mark:Hide()
    local marker = opts.marker or "role"
    if marker == "role" and ROLE_ICON[r.role] then
        self.mark:SetTexture(ROLE_ICON[r.role])
        self.mark:SetTexCoord(0, 1, 0, 1)
        self.mark:SetSize(11, 11)
    elseif marker == "class" and r.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[r.class] then
        self.mark:SetTexture(CLASS_ICONS)
        self.mark:SetTexCoord(unpack(CLASS_ICON_TCOORDS[r.class]))
        self.mark:SetSize(16, 16)
    else
        marker = nil
    end
    if marker then
        self.mark:ClearAllPoints()
        self.mark:SetPoint("LEFT", x, 0)
        self.mark:Show()
        x = x + self.mark:GetWidth() + S["space-3"] - (marker == "role" and 0 or S["space-1"])
    end
    self.name:SetValue(r.name or "")
    local classColor = opts.nameColor ~= "ink" and r.class and T.color["class-" .. r.class:lower()]
    self.name:SetColor(classColor and ("class-" .. r.class:lower()) or "ink")
    -- the right end (fixed widths: a secret % can't be measured): the %,
    -- the raw threat before it, then the badge or "Tanking", then the name
    if known then
        self.pct:SetFormattedText("%.0f%%", pct)
        self.pct.value = nil
    else
        self.pct:SetValue("")
    end
    local raw = r.raw
    local right = self.pct
    if opts.raw and readable(raw) then
        -- threat values come at 100x; a secret one can't be divided, so it's left out
        self.raw:SetValue(AbbreviateNumbers and AbbreviateNumbers(raw / 100) or tostring(math.floor(raw / 100)))
        self.raw:SetVisible(true)
        right = self.raw
    else
        self.raw:SetVisible(false)
    end
    local holds = readable(r.status) and r.status >= 2 and not word and holder(r.role)
    self.sub:SetValue(holds and (r.role == "PET" and "Pet tanking" or "Tanking") or "")
    self.sub:ClearAllPoints()
    self.sub:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0)
    self.badge:ClearAllPoints()
    self.badge:SetPoint("RIGHT", right, "LEFT", -S["space-3"], 0)
    self.badge:SetShown(word ~= nil)
    if word then self.badge:SetState(tone, word) end
    local nameEnd = word and self.badge or (holds and self.sub) or right
    self.name:ClearAllPoints()
    self.name:SetPoint("LEFT", x, 0)
    self.name:SetPoint("RIGHT", nameEnd, "LEFT", -S["space-3"], 0)
    self.name:SetJustifyH("LEFT")
    self:Show()
end

local function buildRow(m)
    local h = UI.Size("meter-row")
    local f = CreateFrame("Frame", nil, m.body)
    Mixin(f, Row)
    f:SetSize(m.innerW, h)
    UI.Fill(f, "surface-sunk", "BACKGROUND"):SetAllPoints()
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetAllPoints()
    f.bar:SetStatusBarTexture(WHITE)
    f.bar:SetMinMaxValues(0, 100)
    local r1, g1, b1 = mix("unit-fill-deep")
    local r2, g2, b2 = mix("unit-fill")
    f.bar:GetStatusBarTexture():SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
    f.edge = UI.Border(f.bar, "gilt-hairline", { layer = "OVERLAY" })
    f.glow = UI.Shadow(f, "glow-ember")
    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints()
    o:SetFrameLevel(f.bar:GetFrameLevel() + 2)
    f.rank = UI.Text(o, "caption", "ink")
    f.rank:SetWidth(12)
    f.rank:SetJustifyH("RIGHT")
    f.mark = o:CreateTexture(nil, "OVERLAY")
    f.name = UI.Text(o, "label", "ink")
    f.name:SetShadowed(true)
    f.name:SetWordWrap(false)
    f.pct = UI.Text(o, "numeric", "ink")
    f.pct:SetShadowed(true)
    f.pct:SetFixedWidth(PCT_W)
    f.pct:SetJustifyH("RIGHT")
    f.pct:SetPoint("RIGHT", -S["space-3"], 0)
    f.raw = UI.Text(o, "caption", "ink")
    f.raw:SetShadowed(true)
    f.raw:SetFixedWidth(RAW_W)
    f.raw:SetJustifyH("RIGHT")
    f.raw:SetPoint("RIGHT", f.pct, "LEFT", -S["space-2"], 0)
    f.badge = UI.StateBadge(o, "danger", "Aggro")
    f.sub = UI.Text(o, "caption", "ink")
    f.sub:SetShadowed(true)
    return f
end

--------------------------------------------------------------------------------
-- The meter
--------------------------------------------------------------------------------

local Meter = {}
ns.Mixins.ThreatMeter = Meter

function Meter:SetTarget(name)
    if name == nil then
        self.target:SetValue("")
        return
    end
    self.target:SetFormattedText("on %s", name)
    self.target.value = nil
end

-- The rows the meter keeps its height for (the damage meter's), live.
function Meter:SetMaxRows(n)
    self.maxRows = math.max(2, n or 8)
    local h, gap = UI.Size("meter-row"), S["space-1"]
    self:SetHeight(32 + 1 + S["space-3"] * 2 + self.maxRows * h + (self.maxRows - 1) * gap)
    for i = self.maxRows + 1, #self.rows do self.rows[i]:Hide() end
end

local STATUS_RANK = function(r) return readable(r.status) and r.status or -1 end

function Meter:SetRows(list, opts)
    opts = opts or {}
    local show = opts.show or "group"
    local rows = {}
    for i, r in ipairs(list or {}) do
        if show == "group" or r.you or (show == "tanks" and holder(r.role)) then
            rows[#rows + 1] = { r = r, i = i }
        end
    end
    local byState = opts.byState
    table.sort(rows, function(a, b)
        if byState then
            local sa, sb = STATUS_RANK(a.r), STATUS_RANK(b.r)
            if sa ~= sb then return sa > sb end
        else
            local pa = readable(a.r.percent) and a.r.percent or -1
            local pb = readable(b.r.percent) and b.r.percent or -1
            if pa ~= pb then return pa > pb end
        end
        return a.i < b.i
    end)
    local max = self.maxRows
    local note = byState and show ~= "self" and #rows > 0
    local slots = note and max - 1 or max
    local n = math.min(slots, #rows)
    local youAt
    for i, x in ipairs(rows) do if x.r.you then youAt = i end end
    local pin = youAt and youAt > n
    local h, gap = UI.Size("meter-row"), S["space-1"]
    local ranked = not byState and show ~= "self"
    for i = 1, max do
        local x = rows[i]
        if pin and i == n then x = rows[youAt] end
        local row = self.rows[i]
        if x and i <= n then
            if not row then
                row = buildRow(self)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.body, "TOPLEFT", S["space-3"], -S["space-3"] - (i - 1) * (h + gap))
            local rank = ranked and (pin and i == n and youAt or i) or nil
            row:Set(x.r, rank, opts)
        elseif row then
            row:Hide()
        end
    end
    -- your pinned row sits under a dashed line (here: a gilt-line hairline)
    self.pinLine:SetShown(pin and true or false)
    if pin then
        self.pinLine:ClearAllPoints()
        self.pinLine:SetPoint("BOTTOMLEFT", self.rows[n], "TOPLEFT", 0, gap / 2)
        self.pinLine:SetPoint("BOTTOMRIGHT", self.rows[n], "TOPRIGHT", 0, gap / 2)
    end
    self.note:SetVisible(note and true or false)
    self.empty:SetVisible(#rows == 0)
end

function UI.ThreatMeter(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Meter)
    f.maxRows = math.max(2, opts.rows or 8)
    local w = UI.Size("meter-w")
    local h, gap = UI.Size("meter-row"), S["space-1"]
    local head = 32
    local bodyH = S["space-3"] * 2 + f.maxRows * h + (f.maxRows - 1) * gap
    f:SetSize(w, head + 1 + bodyH)
    f.innerW = w - S["space-3"] * 2
    -- the glass panel
    UI.Fill(f, "surface-glass", "BACKGROUND"):SetAllPoints()
    UI.Border(f, "gilt-line")
    UI.Shadow(f, "shadow-panel")
    -- head: "Threat", and "on <target>" at the right
    f.title = UI.Text(f, "header", "gilt-text")
    f.title:SetPoint("LEFT", f, "TOPLEFT", S["space-3"] + S["space-1"], -head / 2)
    f.title:SetValue("Threat")
    f.target = UI.Text(f, "caption", "ink-muted")
    f.target:SetPoint("RIGHT", f, "TOPRIGHT", -S["space-2"] - S["space-2"], -head / 2)
    f.target:SetJustifyH("RIGHT")
    f.target:SetWordWrap(false)
    -- a secret name can't be measured: the target gets the head's free width
    f.target:SetWidth(w - 90)
    local rule = f:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(UI.RGBA("gilt-faint"))
    rule:SetPoint("TOPLEFT", 1, -head)
    rule:SetPoint("TOPRIGHT", -1, -head)
    rule:SetHeight(1)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 0, -head - 1)
    f.body:SetPoint("BOTTOMRIGHT")
    f.rows = {}
    f.pinLine = f.body:CreateTexture(nil, "ARTWORK")
    f.pinLine:SetColorTexture(UI.RGBA("gilt-line"))
    f.pinLine:SetHeight(1)
    f.pinLine:Hide()
    f.note = UI.Text(f.body, "caption", "ink-muted")
    f.note:SetPoint("BOTTOMLEFT", S["space-3"], S["space-3"])
    f.note:SetHeight(h)
    f.note:SetValue("Boss: by threat state, then group")
    f.note:SetVisible(false)
    f.empty = UI.Text(f.body, "caption", "ink-muted")
    f.empty:SetPoint("LEFT", S["space-5"], 0)
    f.empty:SetPoint("RIGHT", -S["space-5"], 0)
    f.empty:SetJustifyH("CENTER")
    f.empty:SetWordWrap(true)
    f.empty:SetValue("No threat on your target yet.")
    f:SetTarget(nil)
    f:SetRows({}, {})
    ns.Extend.Add("meter", f, { meter = "threat" })
    return f
end
