-- Units/Welcome.lua
-- The first-run welcome (design board "First-run splash", direction B, Three
-- steps): once per account, at the first login with SuuUI, a panel over the
-- dimmed world asks two things and shows where things are, one step at a
-- time: 1 Role (Tank, Healer, DPS or Keep my layout), 2 Colours (colour
-- vision, each choice drawing its own signal colours), 3 Where things are
-- (the commands, Settings › Modules, the choices summed up). Back and Next
-- between steps, Skip on every one.
-- Start playing applies both: the role's preset profile (SuuTank, SuuHeal,
-- SuuDps), which this character switches to, and colour vision for the
-- account. Colour vision takes a reload, which addon code can't do on
-- Forever: then a secure /reload button lies over Start playing (as the game
-- menu's Reload UI does), placed out of combat. Skip changes nothing. Both
-- mark it seen for the account; Settings › General and /suu welcome open it
-- again.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "welcome",
    name = "Welcome",
    description = "The first-run welcome: your role layout, colour vision and where things are, once per account.",
    api = "0.17",
    defaults = {},
})

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local CIRCLE = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleFill.tga"
local SOFT = "Interface\\AddOns\\SuuUI\\Media\\Textures\\CircleSoft.tga"

-- The board's measures: a 440 px panel whose body is 640 tall, padded
-- 10 / 6 / 2 inside the panel's own padding; 16 between the parts.
local PANEL_W, BODY_H = 440, 640
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 10, 6, 2
local GAP = 16
local INNER_W = PANEL_W - 2 * S["space-5"] - 2 * PAD_SIDE -- 404
local LINE = { caption = T.type.caption.lineHeight, label = T.type.label.lineHeight, body = T.type.body.lineHeight }

local ROLES = {
    { id = "TANK", glyph = "shield", label = "Tank",
      text = "Threat meter beside the damage meter, swing timer under your cast bar." },
    { id = "HEALER", glyph = "plus", label = "Healer",
      text = "Your group in the middle, between your frame and your target’s." },
    { id = "DAMAGER", glyph = "sword", label = "DPS",
      text = "You and your target either side of the centre, your group above the chat." },
    { id = "keep", glyph = "pushpin", label = "Keep my layout", meta = "No change",
      text = "Nothing moves: SuuUI’s default layout stays as it is." },
}

local VISION_TEXT = { normal = "The colours as designed", redgreen = "Protanopia, deuteranopia", blueyellow = "Tritanopia" }

-- The six signals each colour choice draws in its own preset.
local SIGNALS = {
    { "ember", "Danger" }, { "unit-fill-low", "Low health" }, { "fel", "Healing" },
    { "amber", "Warning" }, { "dispel-magic", "Magic" }, { "dispel-poison", "Poison" },
}

local STEPS = { "1 · Role", "2 · Colours", "3 · Where things are" }

local function glyph(parent, name, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(GLYPHS .. name .. ".tga")
    t:SetSize(size, size)
    t:SetVertexColor(UI.RGBA(color))
    return t
end

local function circle(parent, size, color, sublevel)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
    t:SetTexture(CIRCLE)
    t:SetSize(size, size)
    t:SetVertexColor(UI.RGBA(color))
    return t
end

-- Caption text that wraps at `width`, 14 px a line as in the design.
local function wrapped(parent, style, color, width)
    local fs = UI.Text(parent, style, color)
    fs:SetWordWrap(true)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWidth(width)
    fs:SetSpacing(T.type[style].lineHeight - T.type[style].size)
    return fs
end

-- The height a wrapped text takes in design lines.
local function linesHeight(fs, style)
    local n = math.max(1, fs:GetNumLines() or 1)
    return n * T.type[style].lineHeight
end

-- A text set in its design line: `top` is the line box's top in `parent`.
local function placeLine(fs, parent, x, top, style)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", parent, "TOPLEFT", x, -(top + T.type[style].lineHeight / 2))
end

--------------------------------------------------------------------------------
-- A choice tile: a radio, the choice and what it does; arcane once chosen.
--------------------------------------------------------------------------------

local Tile = {}

function Tile:SetSelected(on)
    self.selected = on
    self.bg:SetColorTexture(UI.RGBA(on and "arcane-soft" or "surface-raised"))
    self.border:SetColor(on and "arcane" or "gilt-line")
    self.inner:SetShown(on)
    self.ring:SetVertexColor(UI.RGBA(on and "arcane" or "gilt-line"))
    self.hole:SetVertexColor(UI.RGBA(on and "arcane-soft" or "surface-raised"))
    self.dot:SetShown(on)
    if self.icon then self.icon:SetVertexColor(UI.RGBA(on and "arcane" or "ink-muted")) end
    if self.meta then self.meta:SetColor(on and "arcane" or "ink-faint") end
end

local function newTile(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    Mixin(b, Tile)
    b:SetWidth(INNER_W)
    b.bg = UI.Fill(b, "surface-raised")
    b.bg:SetAllPoints()
    b.border = UI.Border(b, "gilt-line")
    -- the chosen tile's border is two lines: its own and an inset one
    b.inner = UI.Border(b, "arcane", { inset = 1 })
    b.inner:SetShown(false)
    b.ring = circle(b, 12, "gilt-line", 1)
    b.hole = circle(b, 10, "surface-raised", 2)
    b.hole:SetPoint("CENTER", b.ring)
    b.dot = circle(b, 6, "arcane", 3)
    b.dot:SetPoint("CENTER", b.ring)
    b:SetScript("OnEnter", function(self) if not self.selected then self.border:SetColor("gilt") end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.border:SetColor("gilt-line") end end)
    b:SetScript("OnClick", function(self) onClick(self) end)
    return b
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function M:BuildHead(box)
    -- the emblem, still
    self.mark = UI.LoadingMark(box, { size = 30 })
    self.mark:SetPoint("TOP", 0, 0)
    self.mark:Show()
    local y = self.mark:GetHeight() + S["space-3"] + 2
    -- the title: the display face at 21 px on a 26 px line
    local title = UI.Text(box, "alert", "ink")
    title:SetFont(T.type.alert.file, 21, "")
    title:SetPoint("CENTER", box, "TOP", 0, -(y + 13))
    title:SetValue("Welcome to SuuUI")
    y = y + 26 + S["space-3"]
    local sub = UI.Text(box, "caption", "ink-muted")
    sub:SetPoint("CENTER", box, "TOP", 0, -(y + LINE.caption / 2))
    sub:SetValue("Quiet until it matters. Three short steps.")
    y = y + LINE.caption + GAP

    -- the step dots: done in gilt, this one arcane with its glow, the rest outlined
    local row = CreateFrame("Frame", nil, box)
    row:SetHeight(LINE.caption)
    row:SetPoint("TOP", 0, -y)
    self.dots = {}
    local x = 0
    for i, text in ipairs(STEPS) do
        if i > 1 then
            local line = UI.Fill(row, "gilt-line", "ARTWORK")
            line:SetSize(20, 1)
            line:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + 20 + S["space-4"]
        end
        local d = {}
        d.glow = row:CreateTexture(nil, "BACKGROUND")
        d.glow:SetTexture(SOFT)
        d.glow:SetSize(22, 22)
        d.glow:SetVertexColor(UI.RGBA("arcane-glow"))
        d.glow:SetPoint("CENTER", row, "LEFT", x + 4, 0)
        d.edge = UI.Diamond(row, 8, "gilt-line", "ARTWORK", 1)
        d.edge:SetPoint("CENTER", row, "LEFT", x + 4, 0)
        -- an outline: the panel's ground inside a 1 px edge
        d.hole = UI.Diamond(row, 6, "surface", "ARTWORK", 2)
        d.hole:SetPoint("CENTER", d.edge)
        d.fill = UI.Diamond(row, 8, "arcane", "ARTWORK", 3)
        d.fill:SetPoint("CENTER", d.edge)
        d.text = UI.Text(row, "caption", "ink-faint")
        d.text:SetPoint("LEFT", row, "LEFT", x + 8 + 7, 0)
        d.text:SetValue(text)
        x = x + 8 + 7 + UI.MeasureText("caption", text) + S["space-4"]
        self.dots[i] = d
    end
    row:SetWidth(x - S["space-4"])
    return y + LINE.caption + GAP
end

function M:DrawDots()
    for i, d in ipairs(self.dots) do
        local now, done = i == self.step, i < self.step
        d.glow:SetShown(now)
        d.fill:SetShown(now or done)
        d.fill:SetVertexColor(UI.RGBA(now and "arcane" or "gilt"))
        d.edge:SetShown(not (now or done))
        d.hole:SetShown(not (now or done))
        d.text:SetColor(now and "ink" or (done and "ink-muted" or "ink-faint"))
    end
end

-- Step 1: the role tiles.
function M:BuildRole(page)
    page.header = UI.SectionHeader(page, "Your role layout", "this character", INNER_W)
    page.tiles = {}
    for _, r in ipairs(ROLES) do
        local b = newTile(page, function(tile) self.role = tile.value; self:DrawChoices() end)
        b.value = r.id
        b.icon = glyph(b, r.glyph, 18, "ink-muted")
        b.label = UI.Text(b, "label", "ink")
        b.label:SetValue(r.label)
        b.meta = UI.Text(b, "caption", "ink-faint")
        b.meta:SetPoint("BOTTOMLEFT", b.label, "BOTTOMRIGHT", S["space-4"], 0)
        b.meta:SetValue(r.meta or SuuUI.RolePresetName(r.id) or "")
        b.text = wrapped(b, "caption", "ink-muted", INNER_W - 66 - S["space-5"])
        b.text:SetValue(r.text)
        page.tiles[#page.tiles + 1] = b
    end
    page.note = wrapped(page, "caption", "ink-muted", INNER_W)
    page.note:SetValue("For dungeons and raids alike. Settings › Profiles changes it later.")
end

function M:LayoutRole(page)
    page.header:SetPoint("TOPLEFT", 0, 0)
    local y = T.type.header.lineHeight + S["space-5"]
    for _, b in ipairs(page.tiles) do
        -- 9 / 12 padding; radio, glyph and text 12 apart
        b.ring:ClearAllPoints()
        b.ring:SetPoint("LEFT", S["space-5"], 0)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("LEFT", S["space-5"] + 12 + S["space-5"], 0)
        placeLine(b.label, b, 66, 9, "label")
        b.text:ClearAllPoints()
        b.text:SetPoint("TOPLEFT", 66, -(9 + LINE.label + 2 + (LINE.caption - T.type.caption.size) / 2))
        local h = 9 + LINE.label + 2 + linesHeight(b.text, "caption") + 9
        b:SetHeight(h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        y = y + h + S["space-3"]
    end
    y = y - S["space-3"] + S["space-5"]
    page.note:ClearAllPoints()
    page.note:SetPoint("TOPLEFT", 0, -(y + (LINE.caption - T.type.caption.size) / 2))
end

-- Step 2: the colour vision tiles, each with its six signals.
function M:BuildColours(page)
    page.header = UI.SectionHeader(page, "Colour vision", "every character", INNER_W)
    page.tiles = {}
    for _, mode in ipairs(SuuUI.ColorVisionModes()) do
        local b = newTile(page, function(tile) self.vision = tile.value; self:DrawChoices() end)
        b.value = mode.id
        b.label = UI.Text(b, "label", "ink")
        b.label:SetValue(mode.label)
        b.hint = UI.Text(b, "caption", "ink-muted")
        b.hint:SetPoint("LEFT", b.label, "RIGHT", S["space-5"], 0)
        b.hint:SetValue(VISION_TEXT[mode.id] or mode.hint or "")
        b.signals = {}
        for _, s in ipairs(SIGNALS) do
            local swatch = b:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(16, 6)
            swatch:SetColorTexture(SuuUI.ColorVisionColor(mode.id, s[1]))
            local text = UI.Text(b, "caption", "ink-muted")
            text:SetValue(s[2])
            b.signals[#b.signals + 1] = { swatch = swatch, text = text, width = 16 + 5 + UI.MeasureText("caption", s[2]) }
        end
        page.tiles[#page.tiles + 1] = b
    end
    page.note = wrapped(page, "caption", "ink-muted", INNER_W)
    page.note:SetValue("Only the signal colours change; shapes, badges and labels stay. Takes effect after a reload.")
end

function M:LayoutColours(page)
    page.header:SetPoint("TOPLEFT", 0, 0)
    local y = T.type.header.lineHeight + S["space-5"]
    for _, b in ipairs(page.tiles) do
        -- 10 / 12 padding: the choice on one line, the signals under it
        -- from the text's edge, wrapping 6 / 10 apart
        b.ring:ClearAllPoints()
        b.ring:SetPoint("CENTER", b, "TOPLEFT", S["space-5"] + 6, -(10 + LINE.label / 2))
        placeLine(b.label, b, S["space-5"] + 12 + S["space-5"], 10, "label")
        local left, maxW = S["space-5"] + 24, INNER_W - 2 * S["space-5"] - 24
        local x, top = 0, 10 + LINE.label + S["space-4"]
        for _, s in ipairs(b.signals) do
            if x > 0 and x + s.width > maxW then
                x = 0
                top = top + LINE.caption + S["space-3"]
            end
            s.swatch:ClearAllPoints()
            s.swatch:SetPoint("LEFT", b, "TOPLEFT", left + x, -(top + LINE.caption / 2))
            placeLine(s.text, b, left + x + 16 + 5, top, "caption")
            x = x + s.width + 10
        end
        local h = top + LINE.caption + 10
        b:SetHeight(h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        y = y + h + S["space-3"]
    end
    y = y - S["space-3"] + S["space-5"]
    page.note:ClearAllPoints()
    page.note:SetPoint("TOPLEFT", 0, -(y + (LINE.caption - T.type.caption.size) / 2))
end

-- Step 3: where things are, the choices summed up, the reload said first.
local PLACES = {
    { key = "/suu", label = "Settings", text = "or Esc › SuuUI settings" },
    { key = "/suu edit", label = "Move frames", text = "or Esc › Edit Mode" },
    { key = "/suu keybind", label = "Bind keys", text = "hover a button, press a key" },
    { glyph = "layers", label = "Turn a feature off", text = "Settings › Modules: every feature is a module; plugins add their own" },
}
local KEY_COL = 104

function M:BuildPlaces(page)
    page.header = UI.SectionHeader(page, "Where things are", nil, INNER_W)
    page.rows = {}
    for _, p in ipairs(PLACES) do
        local r = {}
        if p.key then
            r.key = UI.KeyChip(page, p.key)
            r.key:SetWidth(UI.MeasureText("micro", p.key) + 2 * S["space-3"])
        else
            r.glyph = glyph(page, p.glyph, 16, "gilt-text")
        end
        r.label = UI.Text(page, "label", "ink")
        r.label:SetValue(p.label)
        r.text = wrapped(page, "caption", "ink-muted", INNER_W - KEY_COL - 10)
        r.text:SetValue(p.text)
        page.rows[#page.rows + 1] = r
    end

    -- your choices, on surface-sunk
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(INNER_W, 10 + LINE.caption + S["space-3"] + LINE.body + S["space-3"] + LINE.body + 10)
    UI.Fill(box, "surface-sunk"):SetAllPoints()
    UI.Border(box, "gilt-faint")
    local head = UI.Text(box, "caption", "ink-faint")
    placeLine(head, box, S["space-5"], 10, "caption")
    head:SetValue("Your choices")
    page.choices = {}
    for i = 1, 2 do
        local top = 10 + LINE.caption + S["space-3"] + (i - 1) * (LINE.body + S["space-3"])
        local c = {}
        c.glyph = glyph(box, "plus", 14, "arcane")
        c.glyph:SetPoint("LEFT", box, "TOPLEFT", S["space-5"], -(top + LINE.body / 2))
        c.text = UI.Text(box, "body", "ink")
        placeLine(c.text, box, S["space-5"] + 14 + S["space-4"], top, "body")
        c.meta = UI.Text(box, "caption", "ink-muted")
        c.meta:SetPoint("LEFT", c.text, "RIGHT", S["space-4"], 0)
        page.choices[i] = c
    end
    page.box = box

    -- the reload, said before the click
    page.reload = CreateFrame("Frame", nil, page)
    page.reload:SetSize(INNER_W, LINE.caption)
    local icon = glyph(page.reload, "reset", 14, "amber")
    icon:SetPoint("LEFT")
    local text = UI.Text(page.reload, "caption", "ink")
    text:SetPoint("LEFT", icon, "RIGHT", S["space-3"], 0)
    text:SetValue("Start playing reloads the interface once, for the new colours.")
end

function M:LayoutPlaces(page)
    page.header:SetPoint("TOPLEFT", 0, 0)
    local y = T.type.header.lineHeight + S["space-5"]
    for _, r in ipairs(page.rows) do
        -- the key on the label's line (baseline to baseline, near enough)
        if r.key then
            r.key:ClearAllPoints()
            r.key:SetPoint("LEFT", page, "TOPLEFT", 0, -(y + LINE.label / 2))
        else
            r.glyph:ClearAllPoints()
            r.glyph:SetPoint("LEFT", page, "TOPLEFT", 0, -(y + LINE.label / 2))
        end
        placeLine(r.label, page, KEY_COL + 10, y, "label")
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT", KEY_COL + 10, -(y + LINE.label + 1 + (LINE.caption - T.type.caption.size) / 2))
        y = y + LINE.label + 1 + linesHeight(r.text, "caption") + 10
    end
    y = y - 10 + S["space-5"]
    page.box:ClearAllPoints()
    page.box:SetPoint("TOPLEFT", 0, -y)
    y = y + page.box:GetHeight() + S["space-5"]
    page.reload:ClearAllPoints()
    page.reload:SetPoint("TOPLEFT", 0, -y)
end

function M:DrawSummary(page)
    local role, vision = page.choices[1], page.choices[2]
    if self.role == "keep" then
        role.glyph:SetTexture(GLYPHS .. "pushpin.tga")
        role.text:SetValue("Your layout as it is")
        role.meta:SetValue("no change")
    else
        for _, r in ipairs(ROLES) do
            if r.id == self.role then
                role.glyph:SetTexture(GLYPHS .. r.glyph .. ".tga")
                role.text:SetValue(r.label .. " layout")
                role.meta:SetValue(SuuUI.RolePresetName(r.id) .. ", this character")
            end
        end
    end
    vision.glyph:SetTexture(GLYPHS .. "eye.tga")
    local label = self.vision
    for _, mode in ipairs(SuuUI.ColorVisionModes()) do
        if mode.id == self.vision then label = mode.label end
    end
    vision.text:SetValue(label .. " colours")
    vision.meta:SetValue("every character")
    page.reload:SetShown(self:NeedsReload())
end

function M:Build()
    -- the dimmed world under it, taking every click
    local dim = CreateFrame("Frame", nil, SuuUI.Root)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("DIALOG")
    dim:EnableMouse(true)
    local shade = dim:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(8 / 255, 7 / 255, 10 / 255, 0.45)
    dim:Hide()
    self.dim = dim

    local p = UI.Panel(dim, { anchor = true, width = PANEL_W })
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    p:SetFrameLevel(dim:GetFrameLevel() + 5)
    p.body:SetHeight(BODY_H)
    p:Fit()
    self.panel = p

    -- Esc skips, like Skip; other keys go on to the game
    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(frame, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            frame:SetPropagateKeyboardInput(false)
            self:Close()
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    local box = CreateFrame("Frame", nil, p.body)
    box:SetPoint("TOPLEFT", PAD_SIDE, -PAD_TOP)
    box:SetPoint("BOTTOMRIGHT", -PAD_SIDE, PAD_BOTTOM)
    local top = self:BuildHead(box)

    -- the foot: Skip on the left; Back and Next (or Start playing) on the right
    self.skip = UI.Button(box, { text = "Skip", onClick = function() self:Close() end })
    self.skip:SetPoint("BOTTOMLEFT")
    self.next = UI.Button(box, { text = "Next", variant = "primary", onClick = function() self:Go(self.step + 1) end })
    self.next:SetPoint("BOTTOMRIGHT")
    self.play = UI.Button(box, { text = "Start playing", variant = "primary", onClick = function() self:Start() end })
    self.play:SetPoint("BOTTOMRIGHT")
    self.back = UI.Button(box, { text = "Back", icon = "chevronLeft", onClick = function() self:Go(self.step - 1) end })
    self.back:SetPoint("BOTTOMRIGHT", self.next, "BOTTOMLEFT", -S["space-4"], 0)
    local footTop = 30 + GAP
    local rule = UI.Hairline(box, "gilt-line", "both")
    rule:SetPoint("BOTTOMLEFT", 0, footTop)
    rule:SetPoint("BOTTOMRIGHT", 0, footTop)
    local jewel = UI.Diamond(box, 6, "gilt")
    jewel:SetPoint("CENTER", rule, "CENTER", 0, 0)

    -- the steps, between the dots and the rule
    self.pages = {}
    for i, build in ipairs({ self.BuildRole, self.BuildColours, self.BuildPlaces }) do
        local page = CreateFrame("Frame", nil, box)
        page:SetPoint("TOPLEFT", 0, -top)
        page:SetPoint("BOTTOMRIGHT", 0, footTop + 1 + GAP)
        build(self, page)
        page:Hide()
        self.pages[i] = page
    end
    self.layouts = { self.LayoutRole, self.LayoutColours, self.LayoutPlaces }
end

--------------------------------------------------------------------------------
-- Showing and choosing
--------------------------------------------------------------------------------

function M:NeedsReload()
    local _, applied = SuuUI.ColorVision()
    return self.vision ~= applied
end

function M:DrawChoices()
    for _, b in ipairs(self.pages[1].tiles) do b:SetSelected(b.value == self.role) end
    for _, b in ipairs(self.pages[2].tiles) do b:SetSelected(b.value == self.vision) end
end

function M:Go(step)
    self.step = math.max(1, math.min(3, step))
    for i, page in ipairs(self.pages) do
        page:SetShown(i == self.step)
        -- laid out on show: wrapped text measures once its font is in
        if i == self.step then self.layouts[i](self, page) end
    end
    self:DrawDots()
    self.back:SetShown(self.step > 1)
    self.next:SetShown(self.step < 3)
    self.play:SetShown(self.step == 3)
    self.back:ClearAllPoints()
    self.back:SetPoint("BOTTOMRIGHT", self.step == 3 and self.play or self.next, "BOTTOMLEFT", -S["space-4"], 0)
    if self.step == 3 then
        self:DrawSummary(self.pages[3])
        self.play:SetIcon(self:NeedsReload() and "reset" or nil)
    end
    self:DrawStart()
    self:PlaceSecure()
end

-- Start playing waits for the end of a fight: the layout moves secure frames.
function M:DrawStart()
    local fighting = InCombatLockdown()
    self.play:SetEnabledState(not fighting)
    self.play.tooltip = fighting and { title = "Start playing", description = "After the fight." } or nil
end

function M:Show()
    if not self.panel then self:Build() end
    -- nothing chosen: your layout stays, the colours you have
    self.role = "keep"
    self.vision = (SuuUI.ColorVision())
    self.applying = nil
    self:DrawChoices()
    self.dim:Show()
    SuuUI.Motion.Enter(self.panel, T.duration["dur-base"])
    self:Go(1)
end

function M:MarkSeen()
    SuuUI.AccountData("welcome").seen = true
end

function M:Close()
    if not (self.dim and self.dim:IsShown()) then return end
    self:MarkSeen()
    self.dim:Hide()
    self:PlaceSecure()
end

-- The choices made real: the role's preset (this character switches to it)
-- and the account's colour vision. False when the preset couldn't be made.
function M:Apply()
    if self.role ~= "keep" then
        local ok, err = SuuUI.ApplyRolePreset(self.role, true)
        if not ok then
            self:Print(("%s: %s"):format(SuuUI.RolePresetName(self.role) or self.role, tostring(err)))
            return false
        end
    end
    SuuUI.SetColorVision(self.vision)
    self:MarkSeen()
    return true
end

-- Without a reload; with one, the secure button over it runs instead.
function M:Start()
    if InCombatLockdown() then return end
    if self:Apply() then self:Close() end
end

-- The secure /reload button over Start playing: there on step 3 while the
-- colours change, out of combat (a secure frame can't be placed in one).
function M:PlaceSecure()
    if InCombatLockdown() then return end
    local on = self.dim and self.dim:IsShown() and self.step == 3 and self:NeedsReload()
    if not on then
        if self.over then self.over:Hide() end
        return
    end
    local over = self.over
    if not over then
        over = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        over:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        over:SetAttribute("type1", "macro")
        over:SetAttribute("macrotext1", "/reload")
        over:SetScript("OnEnter", function() self.play:GetScript("OnEnter")(self.play) end)
        over:SetScript("OnLeave", function() self.play:GetScript("OnLeave")(self.play) end)
        -- the choices are saved before the reload (saved variables are
        -- written as it happens); once, though the click comes down and up
        over:SetScript("PreClick", function()
            if self.applying then return end
            self.applying = true
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            self:Apply()
        end)
        self.over = over
    end
    over:ClearAllPoints()
    over:SetFrameStrata("DIALOG")
    over:SetFrameLevel(self.panel:GetFrameLevel() + 20)
    over:SetAllPoints(self.play)
    over:Show()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:OnEnable()
    self:Provide("welcome", { Show = function() self:Show() end })
    self:RegisterCommand("welcome", "Show the first-run welcome again: role layout, colour vision, where things are.",
        function() self:Show() end)
    -- before combat locks secure frames: the reload button goes, Start
    -- playing waits; after it, both come back
    self:OnGameEvent("PLAYER_REGEN_DISABLED", function()
        if self.over then self.over:Hide() end
        if self.dim and self.dim:IsShown() then self:DrawStart() end
    end)
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.dim and self.dim:IsShown() then
            self:DrawStart()
            self:PlaceSecure()
        end
    end)
    -- once per account, at the first login with SuuUI: a moment after the
    -- world is in, and out of combat
    if not SuuUI.AccountData("welcome").seen then
        C_Timer.After(2, function()
            if not self:IsEnabled() or SuuUI.AccountData("welcome").seen then return end
            self:RunOutOfCombat("first", function()
                if self:IsEnabled() and not (self.dim and self.dim:IsShown()) then self:Show() end
            end)
        end)
    end
end

function M:OnDisable()
    if self.dim then self.dim:Hide() end
    self:PlaceSecure()
end
