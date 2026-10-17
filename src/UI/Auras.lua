-- UI/Auras.lua
-- Auras through the engine's aura containers. In combat addon code can't read
-- auras at all ("Auras cannot be accessed when secret"), so SuuUI never does:
-- it declares a container with filter groups, the engine fills it with
-- buttons and drives each one's icon, duration, stacks and dispel colour, and
-- SuuUI only styles the buttons, once, when the engine creates them.
--
--   local c = UI.AuraContainer(parent, "player", {
--       size = "icon-lg",          -- icon size token or px
--       spacing = 4,
--       anchor = "TOPRIGHT",       -- the corner the icons start from
--       growth = { "LEFT", "DOWN" },
--       lineWidth = 520,           -- px before wrapping to the next line (nil: never)
--       groups = {
--           { key = "debuffs", filter = { "HARMFUL", "PLAYER" }, max = 16,
--             dispel = true,       -- the dispel-type border on typed debuffs
--             cancel = false,      -- right click cancels (your own buffs)
--             drain = "fel",       -- the duration bar's colour (ink by default)
--             include = { 6673, 5242 },    -- only these spell IDs (the engine
--                                          -- matches them, so it works in combat)
--             exclude = { 871 },           -- 0.16: never these spell IDs
--             index = 2, gap = 4,          -- 0.16: its place among the groups and the
--                                          -- space before it (when icons precede it)
--             harmfulEdge = true,          -- 0.16: the ember edge on debuffs (a
--                                          -- typed one's dispel border covers it)
--             -- per-group looks (the Cooldown Manager's per-entry behaviour):
--             border = "gilt",             -- edge token (gilt-hairline by default)
--             glow = "glow-arcane",        -- a shadow token around the icon
--             digits = false, stacks = false,
--             expiring = 5,                -- seconds: digits amber below (default 3)
--             size = "icon-md",            -- this group's icon size (default: the container's)
--             dispelTypes = { "Curse" },   -- 0.9: only debuffs of these types (instead of include)
--             initialize = fn(button) },   -- 0.9: build the button yourself (default: the AuraIcon)
--       },
--   })
--   c:SetUnit(unit), c:SetGroupMax(key, n), c:SetGroupSpells(key, ids, exclude),
--   c:SetGroupPlace(key, index, gap)   -- 0.16: a group's order and the space before it
--   c:SetFlow(anchor, growth), c:SetLineWidth(px)   -- 0.9: both after creation too
--   c:Release()                  -- 0.9: parked for reuse (no unit, hidden,
--                                -- deaf) until the next SetUnit
--   c:SetGroupSize(key, size)    -- 0.9: a group's icon size, live (out of combat:
--                                -- in combat the engine's buttons refuse the resize)
--   c:ShowPreview(items), c:HidePreview()   -- 0.17: made-up icons ({ { icon,
--                                -- border = token } }) laid out as the engine
--                                -- would, the engine's own out of sight (edit
--                                -- mode's "With buffs and debuffs")
--
-- Every call into the engine is pcall-guarded: an error inside one aborts the
-- engine's whole button batch, and these APIs were still moving in the beta.
-- Styling happens only in the initializer: once the engine marks a button
-- secret (in combat), addon writes to it are refused.

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local WHITE = "Interface\\Buttons\\WHITE8X8"
local dispelCandidates -- below, with the spell lists
local CROP = 0.08
local EXPIRING = 3 -- seconds: the duration digits turn amber below this

local function loadEngine()
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
end

-- The engine batches parsing by exact filter string: base polarity first,
-- then the other tokens sorted, so equal filters share one scan.
local function filterString(tokens)
    local base, rest = nil, {}
    for _, t in ipairs(tokens) do
        if t == "HELPFUL" or t == "HARMFUL" then base = t else rest[#rest + 1] = t end
    end
    table.sort(rest)
    if base and #rest > 0 then return base .. "|" .. table.concat(rest, "|") end
    return base or table.concat(rest, "|")
end

--------------------------------------------------------------------------------
-- Duration text: the design's time format, evaluated by the engine against
-- the (possibly secret) remaining time. Whole seconds under a minute, m:ss
-- under ten minutes, then minutes, then hours.
--------------------------------------------------------------------------------

local formatter
local colorCurves = {}

local function durationFormatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then return nil end
    local Up, Down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
    local f = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(f.SetBreakpoints, f, {
        { threshold = 0, format = "%d", step = 1, rounding = Up },
        { threshold = 60, format = "%d:%02d", step = 1, rounding = Up, components = { { div = 60 }, { mod = 60 } } },
        { threshold = 600, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
    })
    if ok then formatter = f end
    return formatter or nil
end

-- amber below `seconds` (EXPIRING by default), ink above: a step curve over
-- the remaining time
local function expiringColor(seconds)
    seconds = seconds or EXPIRING
    if colorCurves[seconds] ~= nil then return colorCurves[seconds] or nil end
    colorCurves[seconds] = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local c = C_CurveUtil.CreateColorCurve()
    c:SetType(Enum.LuaCurveType.Step)
    c:AddPoint(0, CreateColor(UI.RGBA("amber")))
    c:AddPoint(seconds, CreateColor(UI.RGBA("ink")))
    colorCurves[seconds] = c
    return c
end

local function durationOptions(seconds)
    local opts = { textFormatter = durationFormatter() }
    local curve = expiringColor(seconds)
    if curve then
        local prop = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
        if prop == nil then prop = 0 end
        opts.textColor = { curve = curve, property = prop }
    end
    return opts
end

-- Registers the duration text, dropping options step by step if the engine
-- refuses them (never let it throw).
local function setDurationText(button, fs, seconds)
    local opts = durationOptions(seconds)
    if pcall(button.SetDurationText, button, fs, opts) then return end
    opts.textColor = nil
    if pcall(button.SetDurationText, button, fs, opts) then return end
    pcall(button.SetDurationText, button, fs, {})
end

--------------------------------------------------------------------------------
-- The button: the design's AuraIcon
--------------------------------------------------------------------------------

local DISPEL_STYLE = Enum.CustomAuraButtonDispelTypeTextureStyle
    and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

local function makeInitializer(group, size, owner)
    return function(button)
        -- the group's size now (SetGroupSize may have changed it)
        size = owner.sizes[group.key] or size
        -- The engine's layout only anchors its buttons; their size is ours to
        -- set, and an unsized button renders nothing.
        pcall(button.SetSize, button, size, size)

        -- Regions first, styled, and only then registered with the button:
        -- each registration makes the engine draw at once, and an unstyled
        -- FontString has no font yet.
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
        local well = button:CreateTexture(nil, "BACKGROUND")
        well:SetAllPoints()
        well:SetColorTexture(UI.RGBA("surface-sunk"))

        local over = CreateFrame("Frame", nil, button)
        over:SetAllPoints()
        over:EnableMouse(false)
        over:SetFrameLevel(button:GetFrameLevel() + 2)
        UI.Border(over, group.border or (group.harmfulEdge and "ember" or "gilt-hairline"))
        if group.glow then UI.Shadow(button, group.glow) end

        -- The dispel border: white edges the engine shows and tints per
        -- debuff type; hidden until it does.
        local edges = {}
        if group.dispel and DISPEL_STYLE ~= nil and (button.AddDispelTypeTexture or button.SetAuraBorder) then
            local holder = CreateFrame("Frame", nil, button)
            holder:SetAllPoints()
            holder:EnableMouse(false)
            holder:SetFrameLevel(button:GetFrameLevel() + 3)
            local b = UI.Border(holder, "ink")
            for _, t in ipairs(b.parts) do
                t:SetColorTexture(1, 1, 1, 1)
                t:Hide()
                edges[#edges + 1] = t
            end
        end

        -- The duration bar inside the bottom edge: 3px from icon-lg up, 2px
        -- below, over the digits' dark fade so it reads on bright art; it drains right
        -- to left. ink by default, fel for HoTs (group.drain). The engine
        -- drives it, so it works in combat; it has no colour curve, so only
        -- the digits turn amber near the end.
        local barH = size >= 30 and 3 or 2
        local drain = CreateFrame("StatusBar", nil, button)
        drain:SetPoint("BOTTOMLEFT", 1, 1)
        drain:SetPoint("BOTTOMRIGHT", -1, 1)
        drain:SetHeight(barH)
        drain:SetStatusBarTexture(WHITE)
        drain:SetStatusBarColor(UI.RGBA(group.drain or "ink"))
        -- above the text layer: the digits' dark fade would dim it otherwise
        drain:SetFrameLevel(button:GetFrameLevel() + 6)
        -- No track behind it: the engine leaves the bar empty on permanent
        -- auras (Devotion Aura), and a track would show there as an empty
        -- strip. The digits' dark fade gives the fill its contrast.

        local text = CreateFrame("Frame", nil, button)
        text:SetAllPoints()
        text:EnableMouse(false)
        text:SetFrameLevel(button:GetFrameLevel() + 5)
        -- The design gives the digits a heavy glow (0 0 4px black); WoW draws
        -- only a 1px shadow, so a soft dark fade sits behind the bottom of
        -- the icon instead, and large icons get the bigger numeric digits.
        local scrim = text:CreateTexture(nil, "BACKGROUND")
        scrim:SetPoint("BOTTOMLEFT", 1, 1)
        scrim:SetPoint("BOTTOMRIGHT", -1, 1)
        scrim:SetHeight(math.floor(size * 0.6))
        scrim:SetColorTexture(1, 1, 1, 1)
        scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.8), CreateColor(0, 0, 0, 0))
        -- kept, so SetGroupSize can resize the buttons the engine already made
        owner.buttons[#owner.buttons + 1] = { button = button, key = group.key, scrim = scrim }
        local duration = text:CreateFontString(nil, "OVERLAY")
        ns.Fonts.Apply(duration, size >= 30 and "numeric" or "micro")
        duration:SetShadowColor(0, 0, 0, 1)
        duration:SetShadowOffset(0, -1)
        -- the digits sit just above the bar
        duration:SetPoint("BOTTOM", 0, 1 + barH + (size >= 30 and 1 or 0))
        local stacks = text:CreateFontString(nil, "OVERLAY")
        ns.Fonts.Apply(stacks, "micro")
        stacks:SetShadowColor(0, 0, 0, 1)
        stacks:SetShadowOffset(0, -1)
        stacks:SetPoint("TOPRIGHT", -2, -1)
        -- A thin outline as well, so the digits read on any icon art.
        for _, fs in ipairs({ duration, stacks }) do
            local path, height = fs:GetFont()
            if path then fs:SetFont(path, height, "OUTLINE") end
        end

        -- Clicks only where they do something (cancelling your own buff):
        -- a click-alive icon would swallow clicks meant for what is under it.
        if group.cancel then
            pcall(button.SetCancelAuraButtons, button, "RightButtonUp")
        else
            pcall(button.SetMouseClickEnabled, button, false)
        end

        pcall(button.SetIcon, button, icon)
        if group.stacks ~= false then pcall(button.SetApplicationCount, button, stacks, {}) else stacks:Hide() end
        if group.digits ~= false then setDurationText(button, duration, group.expiring) else duration:Hide(); scrim:Hide() end
        if button.SetDurationBar then
            local opts = {}
            if Enum.StatusBarInterpolation then opts.interpolation = Enum.StatusBarInterpolation.Immediate end
            if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
            pcall(button.SetDurationBar, button, drain, opts)
        else
            drain:Hide()
        end
        if #edges > 0 then
            local add = button.AddDispelTypeTexture or button.SetAuraBorder
            local opts = { style = DISPEL_STYLE, showWhenHarmful = true, showWhenHelpful = false }
            for _, t in ipairs(edges) do
                if not pcall(add, button, t, opts) then break end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The container
--------------------------------------------------------------------------------

local AC = {}

local FLOW = AnchorUtil and AnchorUtil.FlowDirection or {}

local function call(container, names, ...)
    for _, name in ipairs(names) do
        local f = container[name]
        if f then return pcall(f, container, ...) end
    end
    return false
end

local listen -- below, with the re-scan events

-- The unit goes last, after the groups (it decides which events the
-- container listens to), followed by a full re-scan. A released container
-- comes back with it: shown, and listening for its unit again.
function AC:SetUnit(unit)
    self.unit = unit
    pcall(self.container.SetUnit, self.container, unit)
    if self.released then
        self.released = nil
        listen(self, unit)
        self.container:Show()
    end
    self:Refresh()
end

-- 0.9: parks a container nothing uses any more. Engine containers can never
-- be freed, so whoever rebuilds keeps them for reuse instead: released, one
-- has no unit, is hidden and stops listening for its re-scan event. SetUnit
-- brings it back.
function AC:Release()
    if self.released then return end
    self:SetUnit("none")
    if self.rescan then
        ns.Events.Off(self.rescan, self)
        self.rescan = nil
    end
    self.container:Hide()
    self.released = true
end

-- A full re-scan. A container doesn't notice when its unit token points at a
-- new unit (another target, focus or boss): re-scan on those changes.
function AC:Refresh()
    pcall(self.container.UpdateAllAuras, self.container)
end

local RESCAN = {
    target = "PLAYER_TARGET_CHANGED",
    focus = "PLAYER_FOCUS_CHANGED",
}

-- Re-scans whenever the unit's token may point at someone new.
listen = function(self, unit)
    local event = RESCAN[unit] or (unit:find("^boss") and "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        or ((unit:find("^party") or unit:find("^raid")) and "GROUP_ROSTER_UPDATE")
    if event then
        ns.Events.OnGame(event, function() self:Refresh() end, self)
        self.rescan = event
    end
end

-- The corner the icons start from and the way they grow, after creation.
function AC:SetFlow(anchor, growth)
    self.flow = { anchor = anchor or "TOPLEFT", growth = growth or { "RIGHT", "DOWN" } }
    local c = self.container
    call(c, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, anchor or "TOPLEFT")
    local g = growth or { "RIGHT", "DOWN" }
    local h = FLOW[g[1] == "LEFT" and "Left" or "Right"]
    local v = FLOW[g[2] == "UP" and "Up" or "Down"]
    if h and v then call(c, { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" }, h, v) end
    self:Refresh()
end

-- A group's icon size, live: the engine's layout, then the buttons it
-- already made (theirs is ours to set). New buttons take it when made.
-- A group's whole layout as the engine takes it: its icon size, the
-- spacing, and its place (SetGroupPlace).
local function groupLayout(self, key, px)
    local place = self.places[key] or {}
    return { elementWidth = px, elementHeight = px, elementSpacing = self.spacing, lineSpacing = self.spacing,
        layoutIndex = place.index, groupSpacing = place.gap }
end

function AC:SetGroupSize(key, size)
    local px = UI.Size(size)
    if self.sizes[key] == px then return end
    self.sizes[key] = px
    pcall(self.container.SetAuraGroupLayout, self.container, key, groupLayout(self, key, px))
    for _, b in ipairs(self.buttons) do
        if b.key == key then
            pcall(b.button.SetSize, b.button, px, px)
            pcall(b.scrim.SetHeight, b.scrim, math.floor(px * 0.6))
        end
    end
    self:Refresh()
end

-- 0.16: where a group sits among the container's groups (index: lower
-- first; nil: in the order they were added) and the extra space before it
-- (gap px, only when something is already placed and it has icons), live.
function AC:SetGroupPlace(key, index, gap)
    local place = self.places[key]
    if place and place.index == index and place.gap == gap then return end
    self.places[key] = { index = index, gap = gap }
    pcall(self.container.SetAuraGroupLayout, self.container, key, groupLayout(self, key, self.sizes[key]))
    self:Refresh()
end

-- 0.9: px before the icons wrap to the next line (nil: never), after creation.
function AC:SetLineWidth(px)
    self.lineWidth = px
    call(self.container, { "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth" }, px)
    self:Refresh()
end

function AC:SetGroupMax(key, n)
    pcall(self.container.SetAuraGroupMaxFrameCount, self.container, key, n)
end

-- Spell lists as the engine takes them: { includeSpellIDs = { [id] = true },
-- excludeSpellIDs = { … } } (an empty include list lets nothing through).
local function idSet(ids)
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    return set
end
local function candidates(ids, exclude)
    if not ids and not exclude then return nil end
    return { includeSpellIDs = ids and idSet(ids) or nil, excludeSpellIDs = exclude and idSet(exclude) or nil }
end

-- Only debuffs of these types: { includeDispelTypes = { Curse = true } }.
-- The engine matches them, in combat too.
dispelCandidates = function(types)
    local set = {}
    for _, t in ipairs(types) do set[t] = true end
    return { includeDispelTypes = set }
end

-- Only these spell IDs in group `key` (nil: no spell list), and never those
-- in `exclude` (0.16).
function AC:SetGroupSpells(key, ids, exclude)
    return pcall(self.container.SetAuraGroupCandidateFilters, self.container, key, candidates(ids, exclude) or {})
end

-- 0.17: made-up icons in the container's place, laid out as the engine lays
-- out its own (the corner, the growth, the line width, the first group's
-- size); the engine's icons out of sight meanwhile.
function AC:ShowPreview(items)
    local c = self.container
    local pv = self.preview
    if not pv then
        pv = CreateFrame("Frame", nil, c:GetParent())
        pv:SetSize(1, 1)
        pv.icons = {}
        self.preview = pv
    end
    local flow = self.flow or { anchor = self.opts.anchor or "TOPLEFT", growth = self.opts.growth or { "RIGHT", "DOWN" } }
    local anchor = flow.anchor
    pv:SetParent(c:GetParent())
    pv:SetFrameLevel(c:GetFrameLevel() + 2)
    pv:ClearAllPoints()
    pv:SetPoint(anchor, c, anchor)
    local first = self.opts.groups[1]
    local size = (first and self.sizes[first.key]) or UI.Size(self.opts.size or "icon-md")
    local sp = self.spacing
    local line = self.lineWidth or self.opts.lineWidth
    local perLine = line and math.max(1, math.floor((line + sp) / (size + sp))) or #items
    local hx = flow.growth[1] == "LEFT" and -1 or 1
    local vy = flow.growth[2] == "UP" and 1 or -1
    for i, it in ipairs(items) do
        local icon = pv.icons[i]
        if not icon then
            icon = UI.Icon(pv, size)
            pv.icons[i] = icon
        end
        local col, row = (i - 1) % perLine, math.floor((i - 1) / perLine)
        icon:SetSize(size, size)
        icon:SetArt(it.icon)
        icon:SetBorder(it.border or "gilt-hairline")
        icon:ClearAllPoints()
        icon:SetPoint(anchor, pv, anchor, hx * col * (size + sp), vy * row * (size + sp))
        icon:Show()
    end
    for i = #items + 1, #pv.icons do pv.icons[i]:Hide() end
    pv:Show()
    c:SetAlpha(0)
end

function AC:HidePreview()
    if self.preview then self.preview:Hide() end
    self.container:SetAlpha(1)
end

function UI.AuraContainer(parent, unit, opts)
    loadEngine()
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok then
        ns.Fault.Report("Auras", "the client has no aura containers: " .. tostring(container))
        return nil
    end
    local self = setmetatable({ container = container, opts = opts, sizes = {}, buttons = {}, places = {} }, { __index = AC })
    -- a renderable rect from the start: the engine lays out from an OnUpdate
    container:SetSize(1, 1)

    local size = UI.Size(opts.size or "icon-md")
    call(container, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, opts.anchor or "TOPLEFT")
    local g = opts.growth or { "RIGHT", "DOWN" }
    local h = FLOW[g[1] == "LEFT" and "Left" or "Right"]
    local v = FLOW[g[2] == "UP" and "Up" or "Down"]
    if h and v then call(container, { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" }, h, v) end
    call(container, { "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth" }, opts.lineWidth)

    local spacing = opts.spacing or S["space-2"]
    self.spacing = spacing
    for _, group in ipairs(opts.groups) do
        local gsize = group.size and UI.Size(group.size) or size
        self.sizes[group.key] = gsize
        self.places[group.key] = { index = group.index, gap = group.gap }
        local added = pcall(container.AddAuraGroup, container, group.key, filterString(group.filter), {
            maxFrameCount = group.max or 16,
            candidateFilters = group.dispelTypes and dispelCandidates(group.dispelTypes) or candidates(group.include, group.exclude),
            initializeFrame = group.initialize or makeInitializer(group, gsize, self),
            layout = { elementWidth = gsize, elementHeight = gsize, elementSpacing = spacing, lineSpacing = spacing,
                layoutIndex = group.index, groupSpacing = group.gap },
        })
        if not added then ns.Fault.Report("Auras", "couldn't add the aura group " .. group.key) end
    end
    self:SetUnit(unit)
    listen(self, unit)
    return self
end
