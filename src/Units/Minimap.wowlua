-- Units/Minimap.lua
-- The minimap (step 2.1, design board "Minimap"): top right, 28px from the
-- edges. The zone (header, gilt) and subzone (caption, ink) above; the map
-- itself, round, `minimap` across, in a 1px gilt ring with the inset-anchor
-- band and a panel shadow, two gilt diamonds at its corners and the north
-- marker on top; on the ring the SuuUI Jewel lower left (settings), the mail
-- marker upper left while mail waits, zoom lower right; the clock below.
-- A built-in module written against the public API only.
--
-- The game's Minimap is moved into SuuUI's frame (one frame later, out of
-- combat: moving it while a panel opens taints map pins) and kept there;
-- MinimapCluster stays shown but invisible with its mouse off (Edit Mode
-- keeps working), its art hidden. MinimapBackdrop stays: encounter addons
-- read your facing from its compass texture, which is hidden, not its frame.
-- Left click pings as always; right click opens the tracking menu; the mouse
-- wheel zooms (an overlay passes the clicks through). Turned off: a /reload
-- hands it all back.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "minimap",
    name = "Minimap",
    description = "SuuUI's round minimap with the zone, the clock, mail, zoom and the SuuUI button.",
    api = "0.10",
    reloadToToggle = true,
    defaults = {
        -- the frame's top: the zone lines above it end 28px from the screen's top
        position = { point = "TOPRIGHT", x = -28, y = -65 },
        size = 176,
        zone = true,
        clock = true,
        wheelZoom = true,
    },
})

local TEX = "Interface\\AddOns\\SuuUI\\Media\\Textures\\"
local GLYPHS = TEX .. "Glyphs\\"
local ROUND_MASK = 186178
local isSecret = issecretvalue or function() return false end
local function readable(v) return not isSecret(v) and type(v) == "number" end
-- the zone lines (zone, subzone, the instance line) end this far above the
-- disc: the north marker's 8px over the ring, plus space-3
local ZONE_GAP = 8 + S["space-3"]

--------------------------------------------------------------------------------
-- Round buttons and decorations (shared by the real map and the preview)
--------------------------------------------------------------------------------

local function circleTex(parent, file, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    t:SetTexture(TEX .. file)
    UI.Paint(t, color)
    return t
end

-- A round button: surface, a gilt-line edge (gilt on hover), a glyph.
local function roundButton(parent, size, glyph, glyphSize)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.fill = circleTex(b, "CircleFill.tga", "surface", "BACKGROUND")
    b.fill:SetAllPoints()
    b.edge = circleTex(b, "CircleEdge.tga", "gilt-line", "BORDER")
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(glyphSize, glyphSize)
    b.icon:SetPoint("CENTER")
    if glyph then
        b.icon:SetTexture(GLYPHS .. glyph .. ".tga")
        UI.Paint(b.icon, "ink")
    end
    b:SetScript("OnEnter", function(self)
        UI.Paint(self.edge, "gilt")
        if self.tip then UI.ShowTooltip(self, self.tip()) end
    end)
    b:SetScript("OnLeave", function(self)
        UI.Paint(self.edge, "gilt-line")
        UI.HideTooltip()
    end)
    return b
end

-- The "N": 9.5 px in header's face (again when a theme changes it).
local function northFace(text)
    text:SetFont(SuuUI.Fonts.Get("header"):GetFont(), 9.5, "")
end

-- The ring, ornaments, north marker and the ring's buttons around `disc`.
local function decorate(disc, handlers)
    local d = {}
    local over = CreateFrame("Frame", nil, disc)
    over:SetAllPoints()
    over:SetFrameLevel(disc:GetFrameLevel() + 20)
    d.over = over
    -- the panel shadow under the disc (round)
    d.shadow = circleTex(disc, "CircleSoft.tga", "surface", "BACKGROUND", -8)
    d.shadow:SetVertexColor(0, 0, 0, 0.45)
    d.shadow:SetPoint("TOPLEFT", -22, 22 - 12)
    d.shadow:SetPoint("BOTTOMRIGHT", 22, -22 - 12)
    -- inset-anchor: the dark band inside, a faint gilt line inside that; the gilt ring outside
    d.band = circleTex(over, "CircleBand.tga", "surface", "OVERLAY", 1)
    d.band:SetVertexColor(0, 0, 0, 0.55)
    d.band:SetAllPoints()
    d.inner = circleTex(over, "CircleEdge.tga", "gilt-faint", "OVERLAY", 2)
    d.inner:SetPoint("TOPLEFT", 4, -4)
    d.inner:SetPoint("BOTTOMRIGHT", -4, 4)
    d.ring = circleTex(over, "CircleEdge.tga", "gilt-line", "OVERLAY", 3)
    d.ring:SetAllPoints()
    -- two gilt diamonds at the disc's square corners, 22px in
    d.ornTL = UI.Diamond(over, 7, "gilt")
    d.ornTL:SetPoint("CENTER", over, "TOPLEFT", 22, -22)
    d.ornBR = UI.Diamond(over, 7, "gilt")
    d.ornBR:SetPoint("CENTER", over, "BOTTOMRIGHT", -22, 22)
    -- the north marker: a 16px surface disc with a gilt ring and "N"
    local north = CreateFrame("Frame", nil, over)
    north:SetSize(16, 16)
    north:SetPoint("CENTER", over, "TOP", 0, 0)
    north:SetFrameLevel(over:GetFrameLevel() + 2)
    circleTex(north, "CircleFill.tga", "surface", "BACKGROUND"):SetAllPoints()
    circleTex(north, "CircleEdge.tga", "gilt", "BORDER"):SetAllPoints()
    north.text = UI.Text(north, "micro", "gilt-text")
    northFace(north.text)
    north.text:SetPoint("CENTER", 0.5, 0)
    north.text:SetValue("N")
    d.north = north
    -- the Jewel: lower left on the ring
    d.jewel = roundButton(over, 24, nil, 16)
    d.jewel.icon:SetTexture(TEX .. "Mark.tga")
    d.jewel:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", -4, 26)
    d.jewel:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    d.jewel:SetScript("OnClick", handlers.jewel)
    d.jewel.tip = function() return { title = "SuuUI", lines = { { "Click", "Settings (open or close)" }, { "Right-click", "Edit layout" } } } end
    -- mail: upper left while it waits
    d.mail = roundButton(over, 24, "mail", 14)
    d.mail:SetPoint("TOPLEFT", over, "TOPLEFT", -4, -26)
    d.mail.tip = handlers.mailTip
    d.mail:Hide()
    -- zoom: lower right
    d.zoomIn = roundButton(over, 22, "plus", 12)
    d.zoomOut = roundButton(over, 22, "minus", 12)
    d.zoomOut:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 6, 6)
    d.zoomIn:SetPoint("BOTTOM", d.zoomOut, "TOP", 0, S["space-2"])
    d.zoomIn:SetScript("OnClick", function() handlers.zoom(1) end)
    d.zoomOut:SetScript("OnClick", function() handlers.zoom(-1) end)
    return d
end

-- The whole block: zone above, the disc, the clock below.
local function buildBlock(parent, name, handlers)
    local f = CreateFrame("Frame", name, parent)
    f.zone = UI.Text(f, "header", "gilt-text")
    f.zone:SetShadowed(true)
    f.zone:SetJustifyH("CENTER")
    f.zone:SetWordWrap(false)
    f.sub = UI.Text(f, "caption", "ink")
    f.sub:SetShadowed(true)
    f.sub:SetJustifyH("CENTER")
    f.sub:SetWordWrap(false)
    -- inside an instance: "Dungeon · 5 players" (the kind in ink, the rest muted)
    f.instance = UI.Text(f, "caption", "ink-muted")
    f.instance:SetShadowed(true)
    f.instance:SetJustifyH("CENTER")
    f.instance:SetWordWrap(false)
    f.disc = CreateFrame("Frame", nil, f)
    f.time = UI.Text(f, "caption", "ink")
    f.time:SetShadowed(true)
    f.time:SetPoint("TOP", f.disc, "BOTTOM", 0, -S["space-3"])
    -- the clock opens the game's clock; right click, the calendar
    f.timeButton = CreateFrame("Button", nil, f)
    f.timeButton:SetAllPoints(f.time)
    f.timeButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.timeButton:SetScript("OnClick", handlers.clock)
    f.deco = decorate(f.disc, handlers)
    return f
end

-- The zone lines stack upward from the disc (the map never moves when a
-- line comes or goes): the instance line lowest, the subzone, the zone.
local function stackZone(f)
    local below = nil
    for _, line in ipairs({ f.instance, f.sub, f.zone }) do
        line:ClearAllPoints()
        if line:IsShown() and line.value and line.value ~= "" then
            if below then line:SetPoint("BOTTOM", below, "TOP", 0, 0)
            else line:SetPoint("BOTTOM", f.disc, "TOP", 0, ZONE_GAP) end
            below = line
        else
            line:SetPoint("BOTTOM", f.disc, "TOP", 0, ZONE_GAP)
        end
    end
end

local function layoutBlock(f, size, zone, clock)
    f.disc:SetSize(size, size)
    for _, line in ipairs({ f.zone, f.sub, f.instance }) do
        line:SetWidth(size + 40)
        line:SetVisible(zone)
    end
    f.time:SetVisible(clock)
    f.timeButton:SetShown(clock)
    f.disc:ClearAllPoints()
    -- the placed frame is the map and the clock (8px on top for the north
    -- marker); the zone lines hang above it, so neither an empty line nor a
    -- new one moves the map
    local top = 8
    f.disc:SetPoint("TOP", 0, -top)
    f:SetSize(size, top + size + (clock and (S["space-3"] + T.type.caption.lineHeight) or 0))
    stackZone(f)
end

--------------------------------------------------------------------------------
-- Live parts: zone, clock, mail, zoom
--------------------------------------------------------------------------------

function M:UpdateZone()
    if not self.block then return end
    local zone, sub = GetZoneText(), GetSubZoneText()
    if isSecret(zone) or isSecret(sub) then return end
    self.block.zone:SetValue(zone or "")
    self.block.sub:SetValue((sub and sub ~= "" and sub ~= zone) and sub or "")
    stackZone(self.block)
end

function M:UpdateClock()
    if not self.block or not self:Get("clock") then return end
    local h, m
    if C_CVar.GetCVarBool("timeMgrUseLocalTime") then
        local t = date("*t")
        h, m = t.hour, t.min
    else
        h, m = GetGameTime()
    end
    if C_CVar.GetCVarBool("timeMgrUseMilitaryTime") then
        self.block.time:SetValue(("%02d:%02d"):format(h, m))
    else
        local suffix = h >= 12 and "PM" or "AM"
        self.block.time:SetValue(("%d:%02d %s"):format((h - 1) % 12 + 1, m, suffix))
    end
end

function M:UpdateMail()
    if not self.block then return end
    local ok, has = pcall(HasNewMail)
    local mail = ok and not isSecret(has) and has and true or false
    self.block.deco.mail:SetShown(mail)
end

local function mailTip()
    local lines = {}
    if GetLatestThreeSenders then
        local senders = { GetLatestThreeSenders() }
        for _, s in ipairs(senders) do
            if not isSecret(s) and s then lines[#lines + 1] = { s } end
        end
    end
    return { title = "New mail", subtitle = #lines > 0 and "From" or nil, lines = lines }
end

function M:Zoom(delta)
    local zoom, max = Minimap:GetZoom(), Minimap:GetZoomLevels() - 1
    zoom = math.max(0, math.min(max, zoom + delta))
    Minimap:SetZoom(zoom)
end

--------------------------------------------------------------------------------
-- Taking over the game's minimap
--------------------------------------------------------------------------------

local hidden = CreateFrame("Frame")
hidden:Hide()

local function alphaOff(f)
    if not f then return end
    f:SetAlpha(0)
    if f.EnableMouse then f:EnableMouse(false) end
end

function M:StripBlizzard()
    for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture",
                            "TimeManagerClockButton", "MinimapZoneTextButton", "MinimapZoneText" }) do
        local f = _G[name]
        if f and f.Hide then f:Hide() end
    end
    alphaOff(MinimapCompassTextureUnderlay)
    local cluster = MinimapCluster
    if cluster then
        alphaOff(cluster)
        alphaOff(cluster.Selection)
        if cluster.ZoneTextButton then cluster.ZoneTextButton:Hide() end
        if cluster.Tracking then
            alphaOff(cluster.Tracking)
            alphaOff(cluster.Tracking.Button)
        end
        if cluster.IndicatorFrame then
            alphaOff(cluster.IndicatorFrame.MailFrame)
            alphaOff(cluster.IndicatorFrame.CraftingOrderFrame)
        end
    end
    alphaOff(GameTimeFrame)
    -- the group finder's eye can live in the (invisible) cluster: it stays seen
    if QueueStatusButton and QueueStatusButton.SetIgnoreParentAlpha then QueueStatusButton:SetIgnoreParentAlpha(true) end
    -- Blizzard's zoom buttons: ours instead
    for _, b in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut, _G.MinimapZoomIn, _G.MinimapZoomOut }) do
        if b then b:SetParent(hidden) end
    end
end

-- Into SuuUI's disc, round, at the set size.
function M:PlaceMinimap()
    if InCombatLockdown() then self.pendingPlace = true return end
    self.pendingPlace = nil
    local size = self:Get("size")
    local disc = self.block.disc
    self.placing = true
    if Minimap:GetParent() ~= disc then Minimap:SetParent(disc) end
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", disc, "CENTER")
    Minimap:SetScale(1)
    Minimap:SetSize(size, size)
    Minimap:SetMaskTexture(ROUND_MASK)
    if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(1) end
    if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(1) end
    Minimap:SetFrameLevel(disc:GetFrameLevel() + 1)
    self.placing = nil
    self:StripBlizzard()
    -- a zoom nudge redraws the render at the new size
    local zoom = Minimap:GetZoom()
    Minimap:SetZoom(zoom > 0 and 0 or 1)
    Minimap:SetZoom(zoom)
end

-- Inside a dungeon or raid, a line under the zone: "Dungeon · 5 players",
-- "Raid · 20 players" (Forever has no heroic modes: the kind and the size
-- are what there is to say). Blizzard's difficulty badge stays in the
-- invisible cluster.
local function instanceLine(kind, size)
    local inkHex = T.color["ink"].hex
    return ("|cff%s%s|r · %s players"):format(inkHex, kind, size)
end

function M:UpdateDifficulty()
    local f = self.block
    if not f then return end
    local _, kind, _, _, maxPlayers = GetInstanceInfo()
    local inside = not isSecret(kind) and (kind == "party" or kind == "raid")
    if inside then
        local size = readable(maxPlayers) and maxPlayers > 0 and tostring(maxPlayers) or "?"
        f.instance:SetValue(instanceLine(kind == "raid" and "Raid" or "Dungeon", size))
    else
        f.instance:SetValue("")
    end
    stackZone(f)
end

function M:Guard()
    if self.guarded then return end
    self.guarded = true
    hooksecurefunc(Minimap, "SetParent", function()
        if self.placing or not self:IsEnabled() or not self.block then return end
        if Minimap:GetParent() ~= self.block.disc then
            C_Timer.After(0, function() if self:IsEnabled() then self:PlaceMinimap() end end)
        end
    end)
end

-- Clicks: left pings (passed through), right opens tracking, the wheel zooms.
function M:Overlay()
    local o = CreateFrame("Frame", nil, self.block.disc)
    o:SetAllPoints()
    o:SetFrameLevel(self.block.disc:GetFrameLevel() + 15)
    o:EnableMouse(true)
    -- left clicks (pings) and hovering pass through to the map; these two
    -- are refused in combat, even on SuuUI's own frame (found in game after
    -- a reload in combat): then they wait for its end
    local function passThrough()
        if o.SetPassThroughButtons then o:SetPassThroughButtons("LeftButton") end
        if o.SetPropagateMouseMotion then o:SetPropagateMouseMotion(true) end
    end
    if InCombatLockdown() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(frame)
            frame:UnregisterAllEvents()
            passThrough()
        end)
    else
        passThrough()
    end
    o:EnableMouseWheel(self:Get("wheelZoom"))
    Minimap:EnableMouseWheel(false)
    o:SetScript("OnMouseWheel", function(_, delta) self:Zoom(delta > 0 and 1 or -1) end)
    o:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        local tracking = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
        if tracking and tracking.OpenMenu then
            tracking:ClearAllPoints()
            tracking:SetPoint("CENTER", o, "CENTER")
            tracking:OpenMenu()
        end
    end)
    self.overlay = o
end

--------------------------------------------------------------------------------
-- Settings and the preview
--------------------------------------------------------------------------------

local function noop() end

function M:PreviewView(parent)
    if not self.preview then
        local f = buildBlock(parent, nil, { jewel = noop, zoom = noop, clock = noop, mailTip = mailTip })
        -- a stand-in map: the world's dark, a few roads
        local map = f.disc:CreateTexture(nil, "BACKGROUND", nil, 1)
        map:SetTexture(TEX .. "CircleFill.tga")
        map:SetVertexColor(0.11, 0.14, 0.12, 1)
        map:SetAllPoints()
        local you = f.deco.over:CreateTexture(nil, "OVERLAY", nil, 4)
        you:SetTexture("Interface\\Minimap\\MinimapArrow")
        you:SetSize(24, 24)
        you:SetPoint("CENTER")
        f.zone:SetValue("Wailing Caverns")
        f.sub:SetValue("")
        f.time:SetValue("21:40")
        f.deco.mail:Show()
        f.instance:SetValue(instanceLine("Dungeon", "5"))
        self.preview = f
    end
    self.preview:SetParent(parent)
    layoutBlock(self.preview, self:Get("size"), self:Get("zone"), self:Get("clock"))
    return self.preview
end

local SECTION = {
    id = "minimap", label = "Minimap", category = "World", order = 10,
    preview = function(parent) return M:PreviewView(parent) end,
    groups = {
        { title = "Minimap", description = "Left click pings, right click picks what the map tracks, the wheel zooms. The SuuUI button on the ring opens these settings (right click: edit layout).", rows = {
            { key = "size", label = "Size", control = "slider", min = 140, max = 260, step = 2, unit = "px", combat = true,
              description = "The map's diameter; the design's is 176." },
            { key = "zone", label = "Zone name", control = "toggle", description = "The zone and the subzone above the map." },
            { key = "clock", label = "Clock", control = "toggle", description = "The time below the map (the game's clock settings: server or local, 24 hours). Click: the clock; right click: the calendar." },
            { key = "wheelZoom", label = "Zoom with the wheel", control = "toggle" },
        } },
    },
}

function M:Relayout()
    layoutBlock(self.block, self:Get("size"), self:Get("zone"), self:Get("clock"))
    self:PlaceMinimap()
    self:UpdateZone()
    self:UpdateClock()
end

-- A theme changed: the "N"'s face, the instance line's colour code, the
-- clock's line height (the block holds the map: after combat).
function M:ApplyTheme()
    if self.preview then
        northFace(self.preview.deco.north.text)
        self.preview.instance:SetValue(instanceLine("Dungeon", "5"))
        if self.preview:IsVisible() then self:PreviewView(self.preview:GetParent()) end
    end
    if not self.block then return end
    northFace(self.block.deco.north.text)
    self:UpdateDifficulty()
    if InCombatLockdown() then self.pendingTheme = true return end
    self.pendingTheme = nil
    layoutBlock(self.block, self:Get("size"), self:Get("zone"), self:Get("clock"))
end

function M:OnEnable()
    if not Minimap then return end
    if not self.block then
        local handlers = {
            jewel = function(_, button)
                if button == "RightButton" then SuuUI.EditMode.Enter() else SuuUI.ToggleSettings() end
            end,
            zoom = function(delta) self:Zoom(delta) end,
            clock = function(_, button)
                if button == "RightButton" then
                    if ToggleCalendar then ToggleCalendar() end
                else
                    if not (TimeManagerFrame) then C_AddOns.LoadAddOn("Blizzard_TimeManager") end
                    if ToggleTimeManager then ToggleTimeManager() end
                end
            end,
            mailTip = mailTip,
        }
        self.block = buildBlock(SuuUI.Root, "SuuUIMinimap", handlers)
        self.block:SetFrameStrata("LOW")
        layoutBlock(self.block, self:Get("size"), self:Get("zone"), self:Get("clock"))
    end
    -- the game's clock code (GameTimeFrame, the calendar) loaded
    if not C_AddOns.IsAddOnLoaded("Blizzard_TimeManager") then pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager") end
    -- LibDBIcon and others place their buttons by this
    GetMinimapShape = function() return "ROUND" end
    self:RegisterMover(self.block, { key = "position", label = "Minimap" })
    self:RegisterSettings(SECTION)
    -- one frame later: moving it during a panel opening taints map pins
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:PlaceMinimap()
        self:Guard()
        if not self.overlay then self:Overlay() end
    end)
    self:UpdateZone()
    self:UpdateClock()
    self:UpdateMail()
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        self:OnGameEvent(e, function() self:UpdateZone() end)
    end
    for _, e in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
        self:OnGameEvent(e, function() self:UpdateMail() end)
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingTheme then self:ApplyTheme() end
        if self.pendingPlace then self:PlaceMinimap() end
    end)
    self:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED", "GROUP_ROSTER_UPDATE" }) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:UpdateDifficulty() end) end
    end
    self:UpdateDifficulty()
    self:OnGameEvent("CVAR_UPDATE", function() self:UpdateClock() end)
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(10, function() if self:IsEnabled() then self:UpdateClock() end end)
    end
    for _, key in ipairs({ "size", "zone", "clock" }) do
        self:Watch(key, function()
            self:Relayout()
            if self.preview and self.preview:IsVisible() then self:PreviewView(self.preview:GetParent()) end
        end)
    end
    self:Watch("wheelZoom", function() if self.overlay then self.overlay:EnableMouseWheel(self:Get("wheelZoom")) end end)
end
