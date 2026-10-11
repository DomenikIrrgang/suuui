-- Diagnostics/TokenSheet.lua
-- /suu tokens: every colour and text style from the tokens, drawn in game, to
-- compare against the design system's Color and Typography pages. Hover a
-- swatch for its usage note.
--
-- Laid out by hand with a y cursor; the layout engine arrives in step 0.5.

local _, ns = ...

local T = ns.Tokens
local Fonts = ns.Fonts
local C = T.color

local WIDTH, PAD = 900, 20
local CONTENT_W = WIDTH - PAD * 2 - 24 -- room for the scroll bar
local COLUMNS, ROW_H, SWATCH = 4, 34, 24

-- Colour groups for the sheet, matched by name prefix in this order.
local GROUPS = {
    { "Surfaces", { "^surface", "^track$", "^world$" } },
    { "Gilt", { "^gilt" } },
    { "Ink", { "^ink" } },
    { "Unit bars", { "^unit%-fill", "^ghost$" } },
    { "Signals", { "^arcane", "^ember", "^amber$", "^fel", "^ward", "^dispel%-", "^on%-signal$" } },
    { "Power", { "^mana$", "^rage$", "^energy$", "^focus$" } },
    { "Progress", { "^progress" } },
    { "Class", { "^class%-" } },
    { "Item quality", { "^quality%-" } },
    { "Reaction", { "^reaction%-" } },
    { "Chat", { "^chat%-" } },
    { "Quest difficulty", { "^quest%-" } },
    { "Reputation", { "^rep%-" } },
    { "Coins", { "^coin%-" } },
}

local function groupOf(name)
    for i, group in ipairs(GROUPS) do
        for _, pattern in ipairs(group[2]) do
            if name:find(pattern) then return i end
        end
    end
    return #GROUPS + 1
end

local function text(parent, style, color, value)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Fonts.Apply(fs, style)
    fs:SetTextColor(unpack(C[color]))
    fs:SetText(value)
    return fs
end

-- A 1px outline in a token colour around `frame`.
local function outline(frame, color)
    local c = C[color]
    local function edge(a1, a2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(c))
        t:SetPoint(a1)
        t:SetPoint(a2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function showUsage(self)
    local note = T.usage[self.token]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.token, 1, 1, 1)
    if note then GameTooltip:AddLine(note, nil, nil, nil, true) end
    GameTooltip:Show()
end

local function hideUsage()
    GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

local function heading(content, y, label)
    local fs = text(content, "header", "gilt-text", label)
    fs:SetPoint("TOPLEFT", 0, -y)
    local rule = content:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(unpack(C["gilt-line"]))
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, -(y + 22))
    rule:SetPoint("TOPRIGHT", 0, -(y + 22))
    return y + 34
end

local function swatch(content, name, x, y)
    local c = C[name]
    local cell = CreateFrame("Frame", nil, content)
    cell:SetSize(CONTENT_W / COLUMNS - 8, ROW_H)
    cell:SetPoint("TOPLEFT", x, -y)
    cell:EnableMouse(true)
    cell.token = name
    cell:SetScript("OnEnter", showUsage)
    cell:SetScript("OnLeave", hideUsage)

    local chip = CreateFrame("Frame", nil, cell)
    chip:SetSize(SWATCH, SWATCH)
    chip:SetPoint("LEFT")
    local fill = chip:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(unpack(c))
    outline(chip, "gilt-hairline")

    local label = text(cell, "label", "ink", name)
    label:SetPoint("TOPLEFT", chip, "TOPRIGHT", 8, 1)
    local alpha = c[4] < 1 and (" · %d%%"):format(c[4] * 100 + 0.5) or ""
    local meta = text(cell, "caption", "ink-muted", "#" .. c.hex .. alpha)
    meta:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
end

local function colorSection(content, y)
    y = heading(content, y, "Colour")
    local buckets = {}
    for _, name in ipairs(T.order.color) do
        local g = groupOf(name)
        buckets[g] = buckets[g] or {}
        table.insert(buckets[g], name)
    end
    local colW = CONTENT_W / COLUMNS
    for g = 1, #GROUPS + 1 do
        local names = buckets[g]
        if names then
            local sub = text(content, "caption", "ink-muted", GROUPS[g] and GROUPS[g][1] or "Other")
            sub:SetPoint("TOPLEFT", 0, -y)
            y = y + 18
            for i, name in ipairs(names) do
                local col = (i - 1) % COLUMNS
                local row = math.floor((i - 1) / COLUMNS)
                swatch(content, name, col * colW, y + row * ROW_H)
            end
            y = y + math.ceil(#names / COLUMNS) * ROW_H + 10
        end
    end
    return y
end

local FAMILY_NAMES = { display = "Marcellus SC", sans = "Figtree" }

local function typeSection(content, y)
    y = heading(content, y + 8, "Type")
    for _, name in ipairs(T.order.type) do
        local s = T.type[name]
        local label = text(content, "label", "ink", name)
        label:SetPoint("TOPLEFT", 0, -y)
        local meta = text(content, "caption", "ink-muted", ("%s %s/%s · %d%s"):format(
            FAMILY_NAMES[s.family] or s.family, s.size, s.lineHeight, s.weight, s.tabular and " · tabular" or ""))
        meta:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)

        local sample = text(content, name, "ink", s.sample)
        sample:SetPoint("TOPLEFT", 220, -y)
        sample:SetPoint("RIGHT", content, "RIGHT")
        y = y + math.max(34, s.lineHeight + 14)
    end

    -- Tabular figures: right-aligned numbers of different digits must line up.
    local check = text(content, "caption", "ink-muted", "Tabular check: the columns below line up only if digits share one width")
    check:SetPoint("TOPLEFT", 0, -(y + 4))
    y = y + 24
    for i, style in ipairs({ "numeric", "micro" }) do
        for row, value in ipairs({ "1,111.1s", "8,888.8s", "4,407.0s" }) do
            local fs = text(content, style, "ink", value)
            fs:SetJustifyH("RIGHT")
            fs:SetWidth(90)
            fs:SetPoint("TOPLEFT", 220 + (i - 1) * 120, -(y + (row - 1) * 18))
        end
    end
    return y + 3 * 18 + 10
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local window

local function build()
    local f = CreateFrame("Frame", "SuuUITokenSheet", UIParent)
    f:SetSize(WIDTH, 700)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(C.surface))
    outline(f, "gilt-hairline")

    local title = text(f, "header", "gilt-text", "SuuUI tokens")
    title:SetPoint("TOPLEFT", PAD, -16)
    local meta = text(f, "caption", "ink-muted", ("Design tokens v%d · %d colours · %d text styles · hover a swatch for its usage")
        :format(T.version, #T.order.color, #T.order.type))
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -60)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 24, PAD)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(CONTENT_W)
    scroll:SetScrollChild(content)

    local y = colorSection(content, 0)
    y = typeSection(content, y)
    content:SetHeight(y)

    tinsert(UISpecialFrames, "SuuUITokenSheet")
    return f
end

-- Opened by the diagnostics module's /suu tokens.
ns.TokenSheet = {}

function ns.TokenSheet.Toggle()
    window = window or build()
    window:SetShown(not window:IsShown())
end

function ns.TokenSheet.Hide()
    if window then window:Hide() end
end
