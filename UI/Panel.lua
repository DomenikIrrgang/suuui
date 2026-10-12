-- UI/Panel.lua
-- Containers: Panel, SectionHeader and WindowFrame, plus the close button and
-- key chip their headers use. Sizes and colours follow the design system's
-- Panel, SectionHeader and WindowFrame specs.

local _, ns = ...

local UI, T, Motion = ns.UI, ns.Tokens, ns.Motion
local S = T.space

--------------------------------------------------------------------------------
-- Close button and key chip
--------------------------------------------------------------------------------

-- A 22px square close button: ink-muted cross, a gilt-line border on hover.
function UI.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local border = UI.Border(b, "gilt-line")
    border:SetShown(false)
    local cross = UI.Cross(b, 10, "ink-muted")
    cross:SetPoint("CENTER")
    b:SetScript("OnEnter", function() border:SetShown(true); cross:SetColor("ink") end)
    b:SetScript("OnLeave", function() border:SetShown(false); cross:SetColor("ink-muted") end)
    b:SetScript("OnClick", function() if onClick then onClick(b) end end)
    return b
end

-- The kbd chip: a key in micro on surface-raised, at least 20px square.
function UI.KeyChip(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    UI.Fill(f, "surface-raised"):SetAllPoints()
    UI.Border(f, "gilt-line")
    f.text = UI.Text(f, "micro", "ink")
    f.text:SetPoint("CENTER", 0, 0)
    function f:SetKey(k)
        self.text:SetValue(k)
        self:SetSize(math.max(20, self.text:GetUnboundedStringWidth() + S["space-2"] * 2), 20)
    end
    f:SetKey(key or "")
    return f
end

--------------------------------------------------------------------------------
-- Panel
--
--   UI.Panel(parent, {
--       title = "Loot", meta = "Ember Hound",   -- optional header
--       closable = true, onClose = fn,
--       anchor = true,        -- the double gilt frame and two diamonds (screen anchors only)
--       solid = false,        -- surface instead of surface-glass
--       shadow = true,
--       width = 240, height = nil,  -- a missing size follows the body
--   })
--
-- Put content in panel.body. Without a fixed size the panel fits its body,
-- so give the body a layout (or a size).
--------------------------------------------------------------------------------

local HEAD_H = S["space-5"] + T.type.header.lineHeight -- top padding + title line

local Panel = {}

function Panel:SetTitle(title, meta)
    if self.title then self.title:SetValue(title or "") end
    if self.meta then self.meta:SetValue(meta or "") end
end

-- The offset of the body's top edge from the panel's top edge.
function Panel:BodyTop()
    if self.title then return HEAD_H + S["space-4"] + 1 + S["space-4"] end
    return S["space-4"]
end

function Panel:Fit()
    if self.fixedWidth and self.fixedHeight then return end
    local w, h = self.body:GetSize()
    if not self.fixedWidth then self:SetWidth(w + S["space-5"] * 2) end
    if not self.fixedHeight then self:SetHeight(self:BodyTop() + h + S["space-5"]) end
end

local function buildHead(f, opts)
    f.title = UI.Text(f, "header", "gilt-text")
    f.title:SetPoint("TOPLEFT", S["space-5"], -S["space-5"])
    f.title:SetValue(opts.title)

    -- Right of the title, right to left: close, key chip, meta, all centred
    -- on the title's line.
    local lineY = -(S["space-5"] + T.type.header.lineHeight / 2)
    local prev
    local function chain(region, gap)
        if prev then
            region:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
        else
            region:SetPoint("RIGHT", f, "TOPRIGHT", -S["space-5"], lineY)
        end
        prev = region
    end
    if opts.closable then
        f.close = UI.CloseButton(f, function() if opts.onClose then opts.onClose(f) else f:Hide() end end)
        chain(f.close)
    end
    if opts.keybind then
        f.key = UI.KeyChip(f, opts.keybind)
        chain(f.key, S["space-4"])
    end
    f.meta = UI.Text(f, "caption", "ink-muted")
    chain(f.meta, opts.keybind and S["space-3"] or S["space-4"])
    f.meta:SetValue(opts.meta or "")

    -- The divider: a gilt-line hairline fading at both ends, with its jewel.
    f.divider = UI.Hairline(f, "gilt-line", "both")
    f.divider:SetPoint("TOPLEFT", S["space-5"], -(HEAD_H + S["space-4"]))
    f.divider:SetPoint("TOPRIGHT", -S["space-5"], -(HEAD_H + S["space-4"]))
    f.jewel = UI.Diamond(f, 6, "gilt")
    f.jewel:SetPoint("CENTER", f.divider, "CENTER", 0, 0)
end

function UI.Panel(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", opts.name, parent)
    Mixin(f, Panel)
    f.bg = UI.Fill(f, opts.solid and "surface" or "surface-glass")
    f.bg:SetAllPoints()
    f.border = UI.Border(f, "gilt-line")
    if opts.shadow ~= false then f.shadow = UI.Shadow(f, "shadow-panel") end

    if opts.anchor then
        -- inset-anchor: a 3px dark ring inside the border, then a faint gilt line.
        local rings = T.shadow["inset-anchor"]
        f.ring = UI.Border(f, rings[1].color, { width = rings[1].spread, inset = 1 })
        f.ring2 = UI.Border(f, rings[2].color, { width = 1, inset = 1 + rings[1].spread })
        f.ornTL = UI.Diamond(f, 7, "gilt")
        f.ornTL:SetPoint("CENTER", f, "TOPLEFT", 0, 0)
        f.ornBR = UI.Diamond(f, 7, "gilt")
        f.ornBR:SetPoint("CENTER", f, "BOTTOMRIGHT", 0, 0)
    elseif opts.ornament then
        f.ornTL = UI.Diamond(f, 7, "gilt")
        f.ornTL:SetPoint("CENTER", f, "TOPLEFT", 0, 0)
    end

    if opts.title then buildHead(f, opts) end

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", S["space-5"], -f:BodyTop())
    f.body:SetSize(1, 1)

    f.fixedWidth, f.fixedHeight = opts.width, opts.height
    if opts.width then
        f:SetWidth(opts.width)
        f.body:SetPoint("TOPRIGHT", -S["space-5"], -f:BodyTop())
    end
    if opts.height then
        f:SetHeight(opts.height)
        f.body:SetPoint("BOTTOMLEFT", S["space-5"], S["space-5"])
    end
    f.body:SetScript("OnSizeChanged", function() f:Fit() end)
    f:Fit()
    return f
end

--------------------------------------------------------------------------------
-- Modal: a panel in the middle of the screen over a dark shade. The game
-- can't blur the interface, so the background is dimmed instead; it takes
-- every click, and a click on it, Esc or the panel's own buttons close.
--
--   UI.MakeModal(panel)             -- panel:Show()/Hide() bring the shade
--   UI.Confirm({ title, text, confirm = "Replace", cancel = "Cancel",
--                onConfirm = fn, onCancel = fn })
--------------------------------------------------------------------------------

-- One shade for every modal, made up front: full screen, on the DIALOG layer
-- under the modal, taking every click.
local shade = CreateFrame("Button", nil, ns.Root)
shade:SetAllPoints(ns.Root)
shade:SetFrameStrata("DIALOG")
shade:EnableMouse(true)
shade:RegisterForClicks("AnyUp")
do
    local t = shade:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0, 0, 0, 0.8)
end
shade:Hide()
shade:SetScript("OnClick", function(self) if self.owner then self.owner:Hide() end end)

local function attach(panel)
    if not panel:IsShown() then return end
    shade.owner = panel
    shade:SetFrameLevel(1)
    panel:SetFrameLevel(math.max(panel:GetFrameLevel(), 10))
    shade:SetAlpha(1)
    shade:Show()
    panel:Raise()
end

function UI.MakeModal(panel)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", ns.Root, "CENTER", 0, 40)
    -- Esc closes it (other keys pass on to the game)
    panel:EnableKeyboard(true)
    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- the shade comes with the panel, however it is shown
    panel:HookScript("OnShow", function(self)
        attach(self)
        Motion.Enter(self, T.duration["dur-fast"])
    end)
    hooksecurefunc(panel, "Show", attach)
    panel:HookScript("OnHide", function(self)
        if shade.owner == self then
            shade:Hide()
            shade.owner = nil
        end
    end)
    -- a new frame is already shown: start hidden so the first Show counts
    panel:Hide()
    return panel
end

local confirmPanel

function UI.Confirm(opts)
    if not confirmPanel then
        local p = UI.Panel(ns.Root, { title = " ", width = 400, height = 170, solid = true })
        p.text = UI.Text(p.body, "body", "ink")
        p.text:SetWordWrap(true)
        p.text:SetJustifyH("LEFT")
        p.text:SetFixedWidth(360)
        p.text:SetPoint("TOPLEFT")
        p.ok = UI.Button(p, { text = "OK", variant = "primary", width = 110, onClick = function()
            local fn = p.onConfirm
            p.onCancel = nil
            p:Hide()
            if fn then fn() end
        end })
        p.ok:SetPoint("BOTTOMRIGHT", -20, 18)
        p.cancel = UI.Button(p, { text = "Cancel", width = 100, onClick = function() p:Hide() end })
        p.cancel:SetPoint("RIGHT", p.ok, "LEFT", -8, 0)
        p:HookScript("OnHide", function(self)
            local fn = self.onCancel
            self.onCancel, self.onConfirm = nil, nil
            if fn then fn() end
        end)
        UI.MakeModal(p)
        confirmPanel = p
    end
    local p = confirmPanel
    p:SetTitle(opts.title or "Are you sure?")
    p.text:SetValue(opts.text or "")
    p.ok:SetLabel(opts.confirm or "OK")
    p.cancel:SetLabel(opts.cancel or "Cancel")
    p:Hide() -- an older question still open is cancelled first
    p.onConfirm, p.onCancel = opts.onConfirm, opts.onCancel
    p:Show()
    return p
end

--------------------------------------------------------------------------------
-- SectionHeader: a label floating on the world, a gilt hairline fading out,
-- and an optional meta caption. Give it a width.
--------------------------------------------------------------------------------

function UI.SectionHeader(parent, label, meta, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 380, T.type.header.lineHeight)
    f.label = UI.Text(f, "header", "gilt-text")
    f.label:SetShadowed(true)
    f.label:SetPoint("LEFT")
    f.meta = UI.Text(f, "caption", "ink-muted")
    f.meta:SetShadowed(true)
    f.meta:SetPoint("RIGHT")
    f.rule = UI.Hairline(f, "gilt-line", "out")
    function f:SetLabel(l, m)
        self.label:SetValue(l or "")
        self.meta:SetValue(m or "")
        self.rule:ClearAllPoints()
        self.rule:SetPoint("LEFT", self.label, "RIGHT", S["space-4"], 0)
        if m and m ~= "" then
            self.rule:SetPoint("RIGHT", self.meta, "LEFT", -S["space-4"], 0)
        else
            self.rule:SetPoint("RIGHT", self, "RIGHT")
        end
    end
    f:SetLabel(label, meta)
    return f
end

--------------------------------------------------------------------------------
-- WindowFrame: the shell of every full window. A Panel with the jewel at the
-- top left, title, optional key chip and close; a fixed size whose body
-- scrolls with the mouse wheel when the content is taller; an optional footer
-- row above a gilt-faint rule. Escape closes it (it needs a `name` for that).
--
--   UI.WindowFrame(parent, { name = "SuuUIGallery", title = "Gallery", meta = "…",
--       keybind = "P", width = 780, height = 560, footer = true })
--   window.content  the scrolling content frame; window.footer when asked for
--------------------------------------------------------------------------------

function UI.WindowFrame(parent, opts)
    local f = UI.Panel(parent, {
        name = opts.name, title = opts.title, meta = opts.meta, keybind = opts.keybind,
        closable = true, onClose = opts.onClose, ornament = true, solid = false,
        width = opts.width, height = opts.height,
    })
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", function(self) Motion.Enter(self, T.duration["dur-fast"]) end)

    local bottom = 0
    if opts.footer then
        local footH = 30 + S["space-4"] * 2
        f.footer = CreateFrame("Frame", nil, f)
        f.footer:SetPoint("BOTTOMLEFT", S["space-5"], 0)
        f.footer:SetPoint("BOTTOMRIGHT", -S["space-5"], 0)
        f.footer:SetHeight(footH)
        local rule = UI.Hairline(f, "gilt-faint")
        rule:SetPoint("BOTTOMLEFT", 0, footH)
        rule:SetPoint("BOTTOMRIGHT", 0, footH)
        bottom = footH - S["space-5"]
    end

    -- The body becomes a scroll frame; content goes into window.content.
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", S["space-5"], -f:BodyTop())
    f.body:SetPoint("BOTTOMRIGHT", -S["space-5"], S["space-5"] + bottom)
    f.body:SetScript("OnSizeChanged", nil)
    local scroll = CreateFrame("ScrollFrame", nil, f.body)
    scroll:SetAllPoints()
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(1, 1)
    scroll:SetScrollChild(f.content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, f.content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
    end)
    scroll:SetScript("OnSizeChanged", function(self, w) f.content:SetWidth(w) end)
    f.scroll = scroll

    if opts.name then tinsert(UISpecialFrames, opts.name) end
    return f
end
