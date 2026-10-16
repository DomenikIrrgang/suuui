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
--                onConfirm = fn, onCancel = fn,
--                input = { label, placeholder, value }, -- 0.13: a text to
--                -- enter, given to onConfirm(text); OK once there is some
--                typeToConfirm = "UNLEARN",  -- 0.13: a field under the text;
--                -- the confirm button only works once it says this word
--                -- (any case), Enter then confirms
--                enterConfirms = false })  -- 0.16: Enter in the field doesn't
--                -- confirm (the dialog stays; only the button does)
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

--------------------------------------------------------------------------------
-- UI.ScrollArea(parent[, bar]): a scrolling area, mouse wheel only, content in
-- area.child (size it to its content). With `bar`, a
-- thin scrollbar (Select's: a gilt-faint track, an ink-muted thumb for the
-- visible part) sits `bar` px right of the area, only while the content
-- overflows.
--------------------------------------------------------------------------------

local function updateBar(scroll)
    local track, thumb = scroll.track, scroll.thumb
    local viewH = scroll:GetHeight()
    local max = math.max(0, scroll.child:GetHeight() - viewH)
    local on = max >= 1 and viewH > 0
    track:SetShown(on)
    thumb:SetShown(on)
    if scroll.grip then scroll.grip:SetShown(on) end
    if not on then return end
    local thumbH = math.max(24, viewH * viewH / (viewH + max))
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(viewH - thumbH) * math.min(1, scroll:GetVerticalScroll() / max))
end

-- The bar takes the mouse: drag the thumb, or press the track and the thumb
-- jumps there and follows (only the wheel scrolled: found in game).
local function followCursor(scroll)
    local track, thumb = scroll.track, scroll.thumb
    local viewH = scroll:GetHeight()
    local max = math.max(0, scroll.child:GetHeight() - viewH)
    local range = viewH - thumb:GetHeight()
    local top = track:GetTop()
    if max <= 0 or range <= 0 or not top then return end
    local _, y = GetCursorPosition()
    y = y / track:GetEffectiveScale()
    local pos = (top - y) - (scroll.grab or 0)
    scroll:SetVerticalScroll(max * math.min(1, math.max(0, pos / range)))
end

local function makeGrip(scroll, parent)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetPoint("TOP", scroll.track, "TOP")
    grip:SetPoint("BOTTOM", scroll.track, "BOTTOM")
    grip:SetWidth(12)
    grip:SetFrameLevel(scroll:GetFrameLevel() + 5)
    grip:RegisterForClicks("AnyUp")
    grip:SetScript("OnMouseDown", function()
        local track, thumb = scroll.track, scroll.thumb
        local thumbTop = thumb:GetTop()
        if not thumbTop then return end
        local _, y = GetCursorPosition()
        y = y / track:GetEffectiveScale()
        local at = thumbTop - y
        -- on the thumb: keep the spot grabbed; on the track: its middle
        scroll.grab = (at >= 0 and at <= thumb:GetHeight()) and at or thumb:GetHeight() / 2
        scroll.dragging = true
        followCursor(scroll)
    end)
    grip:SetScript("OnMouseUp", function() scroll.dragging = false end)
    grip:SetScript("OnUpdate", function()
        if scroll.dragging then
            if not IsMouseButtonDown("LeftButton") then scroll.dragging = false return end
            followCursor(scroll)
        end
    end)
    grip:SetScript("OnEnter", function() scroll.thumb:SetColorTexture(UI.RGBA("ink")) end)
    grip:SetScript("OnLeave", function() scroll.thumb:SetColorTexture(UI.RGBA("ink-muted")) end)
    return grip
end

function UI.ScrollArea(parent, bar)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 48)))
    end)
    scroll.child = child
    if bar then
        -- on the parent: the scroll frame clips what it holds
        scroll.track = UI.Fill(parent, "gilt-faint", "ARTWORK")
        scroll.track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", bar, 0)
        scroll.track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", bar, 0)
        scroll.track:SetWidth(3)
        scroll.thumb = UI.Fill(parent, "ink-muted", "OVERLAY")
        scroll.thumb:SetWidth(3)
        scroll.grip = makeGrip(scroll, parent)
        local function update() updateBar(scroll) end
        scroll:SetScript("OnScrollRangeChanged", update)
        scroll:SetScript("OnVerticalScroll", update)
        scroll:SetScript("OnSizeChanged", update)
        child:SetScript("OnSizeChanged", update)
        update()
    end
    -- content that got shorter (or a taller area) pulls the scroll back, so
    -- no empty space stays at the bottom. A frame later: the sizes settle
    -- only after the change (a panel that shrinks with its content), and the
    -- game's own range is then the truth.
    local pending = false
    local function settle()
        pending = false
        local max = math.max(0, scroll:GetVerticalScrollRange())
        if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
        if scroll.track then updateBar(scroll) end
    end
    local function clamp()
        if pending then return end
        pending = true
        C_Timer.After(0, settle)
    end
    scroll:HookScript("OnScrollRangeChanged", clamp)
    scroll:HookScript("OnSizeChanged", clamp)
    child:HookScript("OnSizeChanged", clamp)
    return scroll
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
        local function confirm()
            local text = p.field:GetValue() or ""
            if p.word and text:upper() ~= p.word then return end
            if p.input and strtrim(text) == "" then return end
            local fn = p.onConfirm
            p.onCancel = nil
            p:Hide()
            if fn then fn(p.input and strtrim(text) or nil) end
        end
        p.ok = UI.Button(p, { text = "OK", variant = "primary", width = 110, onClick = confirm })
        p.ok:SetPoint("BOTTOMRIGHT", -20, 18)
        -- the word to type: its line and field as one group, centred across
        -- the panel and between the text and the buttons (asked for in game)
        p.slot = CreateFrame("Frame", nil, p)
        p.slot:SetPoint("TOP", p.text, "BOTTOM")
        p.slot:SetPoint("BOTTOM", p.ok, "TOP")
        p.slot:SetPoint("LEFT", p, "LEFT")
        p.slot:SetPoint("RIGHT", p, "RIGHT")
        p.group = CreateFrame("Frame", nil, p.slot)
        p.group:SetSize(200, T.type.caption.lineHeight + 6 + 30)
        p.group:SetPoint("CENTER")
        p.prompt = UI.Text(p.group, "caption", "ink-muted")
        p.prompt:SetPoint("TOP")
        p.field = UI.TextField(p.group, { width = 200, onTextChanged = function(text)
            if p.word then p.ok:SetEnabledState((text or ""):upper() == p.word) end
            if p.input then p.ok:SetEnabledState(strtrim(text or "") ~= "") end
        end })
        p.field:SetPoint("BOTTOM")
        p.field.edit:HookScript("OnEnterPressed", function(box)
            if p.enterConfirms == false then box:SetFocus() return end
            confirm()
        end)
        p.cancel = UI.Button(p, { text = "Cancel", width = 100, onClick = function() p:Hide() end })
        p.cancel:SetPoint("RIGHT", p.ok, "LEFT", -8, 0)
        p:HookScript("OnHide", function(self)
            self.field.edit:ClearFocus() -- never keep the keyboard once gone
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
    p.enterConfirms = opts.enterConfirms
    -- a word to type first, or something to enter (0.13: input = { label,
    -- placeholder }: onConfirm gets the text; OK once there is some)
    p.word = opts.typeToConfirm and opts.typeToConfirm:upper() or nil
    p.input = opts.input
    local field = p.word or p.input
    p.group:SetShown(field and true or false)
    p.field:SetValue(p.input and p.input.value or "")
    p.ok:SetEnabledState(not field or (p.input and (p.input.value or "") ~= "") or false)
    if p.word then p.prompt:SetValue(("Type %q to confirm."):format(p.word))
    elseif p.input then p.prompt:SetValue(p.input.label or "") end
    if p.field.placeholder then p.field.placeholder:SetValue(p.input and p.input.placeholder or "") end
    p:SetHeight(170 + (field and (p.group:GetHeight() + 12) or 0))
    p:Show()
    if field then p.field.edit:SetFocus() end
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
--       keybind = "P", width = 780, height = 560, footer = true,
--       tabs = { { key = "buy", label = "Merchant" }, … }, onTab = fn(key) })  -- 0.16
--   window.content  the scrolling content frame; window.footer when asked for
--   window:SetTab(key) (0.16): shows that tab as chosen and calls onTab
--
-- Tabs sit under the title as text tabs: header type in ink-muted, the
-- chosen one gilt-text over a gilt hairline with its jewel.
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

    local top = f:BodyTop()
    if opts.tabs then
        local TAB_H = 28
        f.tabRow = CreateFrame("Frame", nil, f)
        f.tabRow:SetPoint("TOPLEFT", S["space-5"], -top)
        f.tabRow:SetPoint("TOPRIGHT", -S["space-5"], -top)
        f.tabRow:SetHeight(TAB_H)
        f.tabButtons = {}
        local x = 0
        for _, t in ipairs(opts.tabs) do
            local b = CreateFrame("Button", nil, f.tabRow)
            b.key = t.key
            b.label = UI.Text(b, "header", "ink-muted")
            b.label:SetPoint("CENTER", 0, 2)
            b.label:SetValue(t.label)
            local w = UI.MeasureText("header", t.label) + 2 * S["space-4"]
            b:SetSize(w, TAB_H)
            b:SetPoint("LEFT", x, 0)
            x = x + w + S["space-2"]
            b.rule = UI.Hairline(b, "gilt-line", "both")
            b.rule:SetPoint("BOTTOMLEFT")
            b.rule:SetPoint("BOTTOMRIGHT")
            b.jewel = UI.Diamond(b, 5, "gilt")
            b.jewel:SetPoint("CENTER", b, "BOTTOM", 0, 0)
            b:SetScript("OnEnter", function(self) if f.tab ~= self.key then self.label:SetTextColor(UI.RGBA("ink")) end end)
            b:SetScript("OnLeave", function(self) if f.tab ~= self.key then self.label:SetTextColor(UI.RGBA("ink-muted")) end end)
            b:SetScript("OnClick", function(self) f:SetTab(self.key) end)
            f.tabButtons[#f.tabButtons + 1] = b
        end
        function f:SetTab(key)
            self.tab = key
            for _, b in ipairs(self.tabButtons) do
                local on = b.key == key
                b.label:SetTextColor(UI.RGBA(on and "gilt-text" or "ink-muted"))
                b.rule:SetShown(on)
                b.jewel:SetShown(on)
            end
            if opts.onTab then opts.onTab(key) end
        end
        top = top + TAB_H + S["space-4"]
    end

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
        -- the content ends space-4 above the footer's rule
        bottom = footH - S["space-5"] + S["space-4"]
    end

    -- The body becomes a scroll frame; content goes into window.content.
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", S["space-5"], -top)
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
