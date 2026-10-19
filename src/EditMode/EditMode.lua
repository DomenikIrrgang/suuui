-- EditMode/EditMode.lua
-- SuuUI's edit mode: every frame that registers a mover can be dragged on a
-- snap grid, nudged with the arrow keys, placed by number (its anchor, X and
-- Y in the toolbar over it), hidden and reset. It runs beside the game's own
-- Edit Mode and closes itself when combat starts.
--
--   module:RegisterMover(frame, { key = "position", label = "Hello" })
--
-- The position is a setting in the module's namespace (so it is saved per
-- profile), declared with its default in the module's defaults:
--   defaults = { position = { point = "CENTER", x = 0, y = 200 } }
-- `point` is one of the nine screen anchors and x, y the offset of the
-- frame's same point from it, in design pixels. A dropped frame takes the
-- anchor of the screen third its centre is in, so layouts keep their shape
-- on every resolution. An anchor picked in the toolbar stays
-- (position.pinned): a drag then changes only x and y, and Reset brings the
-- automatic anchor back. position.hidden hides the frame.
-- The panel's Group preview (0.17) fills the party or raid frames with
-- made-up players at their real place and size while edit mode is open:
-- EditMode.GroupPreview() is 0 (off), 5, 10, 20 or 40, and
-- SUUUI_EDITMODE_GROUP_PREVIEW(size) tells the group frames when it changes.

local _, ns = ...

local UI, T, Settings, Events, Combat, Layout = ns.UI, ns.Tokens, ns.Settings, ns.Events, ns.Combat, ns.Layout
local S = T.space

local EditMode = {}
ns.EditMode = EditMode

Settings.Register("layout", {
    snap = true,
    gridSize = 4,
})

-- The grid divides by its size: 0 or less would put frames nowhere.
Settings.Veto("layout", "gridSize", function(v)
    if v < 4 or v > 32 then return false, "the grid size is between 4 and 32 px" end
end, "EditMode")

local movers = {}   -- list of mover records
local active = false
local selected
local overlay       -- the full-screen edit layer: grid, movers, panel
local groupPreview = 0 -- the group preview chosen this session (0: off)
local groupPreviewAuras = false -- every made-up player with buffs and debuffs

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function root() return ns.Root end

-- Places `frame` at `pos` (after combat if it is protected). A mover with
-- opts.place positions its frame itself (a bar attached to the dock).
local function place(m)
    local pos = Settings.Get(m.namespace, m.key)
    Combat.Run("mover:" .. m.namespace .. "." .. m.key, function()
        if m.customPlace then
            m.customPlace()
        else
            m.frame:ClearAllPoints()
            m.frame:SetPoint(pos.point or "CENTER", root(), pos.point or "CENTER", pos.x or 0, pos.y or 0)
        end
        -- A frame whose visibility its module manages (a unit frame that shows
        -- only while its unit exists) reads position.hidden itself.
        if not m.frame.suuManagedShow then m.frame:SetShown(not pos.hidden) end
    end, m.label)
end

-- The frame's rectangle in root units.
local function rect(frame)
    local s = frame:GetEffectiveScale() / root():GetEffectiveScale()
    local l, b, w, h = frame:GetRect()
    if not l then return nil end
    return l * s, b * s, w * s, h * s
end

-- Where a point sits across and up a rectangle: 0 left or bottom, 1 right
-- or top, 0.5 the middle.
local function fractions(point)
    return (point:find("LEFT") and 0) or (point:find("RIGHT") and 1) or 0.5,
        (point:find("BOTTOM") and 0) or (point:find("TOP") and 1) or 0.5
end

-- The anchor for a rectangle: `point` when given (one picked by hand), else
-- the screen third its centre falls in; and the offset of the rectangle's
-- same point from the screen's.
local function anchorFor(l, b, w, h, point)
    local W, H = root():GetWidth(), root():GetHeight()
    if not point then
        local cx, cy = l + w / 2, b + h / 2
        local horiz = (cx < W / 3 and "LEFT") or (cx > W * 2 / 3 and "RIGHT") or ""
        local vert = (cy < H / 3 and "BOTTOM") or (cy > H * 2 / 3 and "TOP") or ""
        point = vert .. horiz
        if point == "" then point = "CENTER" end
    end
    local fx, fy = fractions(point)
    return point, l + w * fx - W * fx, b + h * fy - H * fy
end

-- The offsets from `point` that keep a w × h frame on the screen.
local function range(point, w, h)
    local fx, fy = fractions(point)
    local function span(f, size, full)
        local lo, hi = f * (size - full), (1 - f) * (full - size)
        if lo > hi then lo, hi = hi, lo end -- a frame larger than the screen
        lo = math.ceil(lo)
        return lo, math.max(lo, math.floor(hi))
    end
    local x0, x1 = span(fx, w, root():GetWidth())
    local y0, y1 = span(fy, h, root():GetHeight())
    return x0, x1, y0, y1
end

local function snap(v)
    if not Settings.Get("layout", "snap") then return math.floor(v + 0.5) end
    local g = Settings.Get("layout", "gridSize")
    return math.floor(v / g + 0.5) * g
end

-- `pinned`: the anchor was picked by hand, so drags keep it.
local function save(m, point, x, y, pinned)
    local pos = Settings.Get(m.namespace, m.key)
    pos.point, pos.x, pos.y = point, x, y
    if pinned then pos.pinned = true end
    Settings.Set(m.namespace, m.key, pos)
end

--------------------------------------------------------------------------------
-- Mover overlays
--------------------------------------------------------------------------------

-- A mover whose frame is turned off (opts.enabled says so) stays out of edit
-- mode: hiding it there is for frames that are on.
local function enabled(m)
    return not m.enabled or m.enabled() and true or false
end

-- The settings section a frame's right-click opens (nil: none).
local function settingsSection(m)
    return m and m.owner and ns.SettingsRegistry.ForOwner(m.owner, m.namespace)
end

-- A frame placed by another (a bar attached to the dock): a drag moves that
-- one, and its own numbers can't be typed.
local function placedByAnother(m)
    return m.dragFrame ~= nil and m.dragFrame() ~= m.frame
end

local toolbar
local KEYS_H = 26

-- Over the frame, or under it when there is no room above (a frame at the
-- screen's top edge); the line of keys on the side away from the frame.
local function placeToolbar(m, top)
    local gap = S["space-5"] + 6
    local below = root():GetHeight() - top < gap + toolbar:GetHeight() + S["space-2"] + KEYS_H
    local keys = toolbar.keys
    toolbar:ClearAllPoints()
    keys:ClearAllPoints()
    if below then
        toolbar:SetPoint("TOPRIGHT", m.overlay, "BOTTOMRIGHT", 0, -gap)
        keys:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -S["space-2"])
    else
        toolbar:SetPoint("BOTTOMRIGHT", m.overlay, "TOPRIGHT", 0, gap)
        keys:SetPoint("BOTTOMRIGHT", toolbar, "TOPRIGHT", 0, S["space-2"])
    end
end

-- The toolbar's anchor, X and Y: the saved position, or where a frame
-- placed by another is (greyed). A field being typed in keeps its text.
local function showPosition(m)
    local locked = placedByAnother(m)
    local pos = Settings.Get(m.namespace, m.key)
    local point, x, y = pos.point or "CENTER", pos.x or 0, pos.y or 0
    local l, b, w, h = rect(m.frame)
    if locked and l then point, x, y = anchorFor(l, b, w, h) end
    local bar = toolbar
    bar.anchor:SetValue(point)
    bar.anchor:SetDisabled(locked)
    for _, f in ipairs({ bar.x, bar.y }) do f:SetDisabled(locked) end
    if l then
        local x0, x1, y0, y1 = range(point, w, h)
        bar.x:SetRange(x0, x1)
        bar.y:SetRange(y0, y1)
    end
    if not bar.x:HasFocus() then bar.x:SetValue(math.floor(x + 0.5)) end
    if not bar.y:HasFocus() then bar.y:SetValue(math.floor(y + 0.5)) end
end

local function sync(m)
    local o = m.overlay
    if not o or not enabled(m) then return end
    local l, b, w, h = rect(m.frame)
    if not l then
        -- A frame that was never shown has no rectangle yet: show it to place it.
        m.frame:Show()
        l, b, w, h = rect(m.frame)
        if not l then return end
    end
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", root(), "BOTTOMLEFT", l, b)
    o:SetSize(w, h)
    o.size:SetValue(("%d × %d"):format(w + 0.5, h + 0.5))
    local hidden = Settings.Get(m.namespace, m.key).hidden
    o:SetAlpha(hidden and T.opacity["opacity-disabled"] or 1)
    UI.PaintFill(o.tagBg, hidden and "ink-faint" or "arcane")
    o.tag:SetValue(m.label .. (hidden and " (hidden)" or ""))
    local on = selected == m
    -- the selected frame's tag says what its right-click does
    o.tagHint:SetShown(on and settingsSection(m) ~= nil)
    o.tagFrame:SetWidth(o.tag:GetUnboundedStringWidth() + 10
        + (o.tagHint:IsShown() and o.tagHint:GetUnboundedStringWidth() or 0))
    o.edge:SetColor("arcane", (on or o:IsMouseOver()) and 1 or 0.6)
    o.glow:SetShown(on)
    if on and toolbar then
        showPosition(m)
        placeToolbar(m, b + h)
    end
end

local function select(m)
    local was = selected
    -- what's typed for another frame (or as edit mode closes) is dropped
    if toolbar and was ~= m then
        toolbar.x:Cancel()
        toolbar.y:Cancel()
        toolbar.anchor:Close()
    end
    selected = m
    if was then sync(was) end
    if not m then
        if toolbar then toolbar:Hide() end
        return
    end
    local hidden = Settings.Get(m.namespace, m.key).hidden
    toolbar.hide:SetLabel(hidden and "Show" or "Hide")
    if m.action then
        toolbar.action:SetLabel(m.action.label())
        toolbar.action:Show()
        toolbar:SetWidth(toolbar.baseWidth + S["space-2"] + 120)
    else
        toolbar.action:Hide()
        toolbar:SetWidth(toolbar.baseWidth)
    end
    sync(m)
    toolbar:Show()
end

-- Overlays are kept per frame, so a module turned off and on again gets its
-- old overlay back instead of a new one. o.mover is the frame's current mover.
local overlays = {}

local function buildOverlay(m)
    local o = overlays[m.frame]
    if o then
        o.mover, m.overlay = m, o
        return
    end
    o = CreateFrame("Button", nil, overlay)
    o:SetFrameLevel(overlay:GetFrameLevel() + 10)
    o:SetMovable(true)
    o:SetClampedToScreen(true)
    o:RegisterForDrag("LeftButton")
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o.wash = o:CreateTexture(nil, "BACKGROUND")
    o.wash:SetAllPoints()
    UI.PaintFill(o.wash, "arcane", 0.06)
    o.edge = UI.Border(o, "arcane")
    o.glow = UI.Shadow(o, "glow-arcane")
    o.glow:SetShown(false)

    o.tagFrame = CreateFrame("Frame", nil, o)
    o.tagFrame:SetHeight(T.type.caption.lineHeight + 2)
    o.tagFrame:SetPoint("TOPLEFT", 6, 9)
    o.tagBg = UI.Fill(o.tagFrame, "arcane")
    o.tagBg:SetAllPoints()
    o.tag = UI.Text(o.tagFrame, "caption", "on-signal")
    o.tag:SetPoint("LEFT", 5, 0)
    o.tagHint = UI.Text(o.tagFrame, "caption", "on-signal")
    o.tagHint:SetAlpha(0.72)
    o.tagHint:SetPoint("LEFT", o.tag, "RIGHT")
    o.tagHint:SetValue(" · right-click: settings")
    o.size = UI.Text(o, "micro", "ink-muted")
    o.size:SetShadowed(true)
    o.size:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 0, -3)

    o:SetScript("OnEnter", function(self) sync(self.mover) end)
    o:SetScript("OnLeave", function(self) sync(self.mover) end)
    o:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return EditMode.OpenSettings(self.mover) end
        select(self.mover)
    end)
    o:SetScript("OnDragStart", function(self)
        local m = self.mover
        select(m)
        -- The frame a drag moves: the mover's own, or the one it is part of
        -- (opts.dragFrame: a bar attached to the dock moves the dock).
        local lead = m.dragFrame and m.dragFrame() or m.frame
        local sl, sb = rect(lead)
        local ol, ob = self:GetLeft(), self:GetBottom()
        self:StartMoving()
        -- The real frames follow while dragging (edit mode is never open in
        -- combat, so protected frames may move too), and every other mover's
        -- outline keeps up with them.
        self:SetScript("OnUpdate", function()
            if InCombatLockdown() or not sl then return end
            local dx, dy = self:GetLeft() - ol, self:GetBottom() - ob
            lead:ClearAllPoints()
            lead:SetPoint("BOTTOMLEFT", root(), "BOTTOMLEFT", sl + dx, sb + dy)
            for _, other in ipairs(movers) do
                if other ~= m and other.overlay and other.overlay:IsShown() then sync(other) end
            end
        end)
    end)
    o:SetScript("OnDragStop", function(self)
        local m = self.mover
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        local l, b, w, h = self:GetLeft(), self:GetBottom(), self:GetWidth(), self:GetHeight()
        -- opts.onDrop can take the drop over (and returns true when it did).
        if m.onDrop and m.onDrop(snap(l), snap(b), w, h) then
            C_Timer.After(0, function() if active then sync(m) end end)
            return
        end
        local pos = Settings.Get(m.namespace, m.key)
        local point, x, y = anchorFor(l, b, w, h, pos.pinned and pos.point or nil)
        save(m, point, snap(x), snap(y))
        -- A drop that snaps back to the saved position changes no setting, so
        -- nothing else puts the frame and the outlines back on the grid.
        place(m)
        C_Timer.After(0, function()
            if not active then return end
            for _, other in ipairs(movers) do
                if other.overlay and other.overlay:IsShown() then sync(other) end
            end
        end)
    end)
    o.mover = m
    overlays[m.frame] = o
    m.overlay = o
end

--------------------------------------------------------------------------------
-- The grid and the panel
--------------------------------------------------------------------------------

local gridLines = {}

local function drawGrid()
    local g = Settings.Get("layout", "gridSize")
    local W, H = root():GetWidth(), root():GetHeight()
    for _, t in ipairs(gridLines) do t:Hide() end
    local i = 0
    local function line(vertical, pos, alpha)
        i = i + 1
        local t = gridLines[i] or overlay:CreateTexture(nil, "BACKGROUND", nil, 1)
        gridLines[i] = t
        UI.PaintFill(t, "arcane", alpha)
        t:ClearAllPoints()
        local px = ns.Pixel.Size(overlay)
        if vertical then
            t:SetPoint("TOPLEFT", overlay, "TOPLEFT", pos, 0)
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", pos, 0)
            t:SetWidth(px)
        else
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, pos)
            t:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, pos)
            t:SetHeight(px)
        end
        t:Show()
    end
    -- Lines run out from the centre, so centred frames sit on the grid.
    for x = W / 2 % g, W, g do line(true, x, 0.07) end
    for y = H / 2 % g, H, g do line(false, y, 0.07) end
    line(true, W / 2, 0.25)
    line(false, H / 2, 0.25)
end

local function buildPanel()
    local p = UI.Panel(overlay, { title = "Edit mode", width = 250 })
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetPoint("LEFT", root(), "LEFT", S["space-7"], 0)
    p:EnableMouse(true)
    local stack = Layout.Stack(p.body, { gap = S["space-4"], autoSize = "height" })

    local snapRow = CreateFrame("Frame", nil, p.body)
    snapRow:SetSize(226, 20)
    local snapToggle = UI.Toggle(snapRow, { value = Settings.Get("layout", "snap"),
        onChange = function(v) Settings.Set("layout", "snap", v) end })
    snapToggle:SetPoint("LEFT")
    local snapLabel = UI.Text(snapRow, "label", "ink")
    snapLabel:SetValue("Snap to grid")
    snapLabel:SetPoint("LEFT", snapToggle, "RIGHT", S["space-4"], 0)
    stack:Add(snapRow)

    local size = UI.Slider(p.body, { label = "Grid size", min = 4, max = 32, step = 4, unit = "px", width = 226,
        value = Settings.Get("layout", "gridSize"),
        onChange = function(v) Settings.Set("layout", "gridSize", v) end })
    stack:Add(size)

    -- made-up players in the group frames, at their real place and size
    local previewRow = CreateFrame("Frame", nil, p.body)
    previewRow:SetSize(226, T.type.label.lineHeight + S["space-2"] + 28)
    p.previewRow, p.stack = previewRow, stack
    local previewLabel = UI.Text(previewRow, "label", "ink")
    previewLabel:SetValue("Group preview (players)")
    previewLabel:SetPoint("TOPLEFT")
    local previewPick = UI.Segmented(previewRow, {
        -- players in the group: 5 the party, more the raid (fits the 226 body)
        options = { { value = 0, label = "Off" }, { value = 5, label = "5" }, { value = 10, label = "10" },
                    { value = 20, label = "20" }, { value = 40, label = "40" } },
        value = groupPreview,
        onChange = function(v) EditMode.SetGroupPreview(v) end })
    previewPick:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -S["space-2"])
    p.previewPick = previewPick
    stack:Add(previewRow)
    -- everyone with defensives and every dispel type, to see the icons fit
    local aurasRow = CreateFrame("Frame", nil, p.body)
    aurasRow:SetSize(226, 20)
    local aurasToggle = UI.Toggle(aurasRow, { value = groupPreviewAuras,
        onChange = function(v) EditMode.SetGroupPreview(groupPreview, v) end })
    aurasToggle:SetPoint("LEFT")
    local aurasLabel = UI.Text(aurasRow, "label", "ink")
    aurasLabel:SetValue("Buffs and debuffs on every frame")
    aurasLabel:SetPoint("LEFT", aurasToggle, "RIGHT", S["space-4"], 0)
    p.previewAuras = aurasToggle
    stack:Add(aurasRow)

    local buttons = CreateFrame("Frame", nil, p.body)
    local bs = Layout.Stack(buttons, { direction = "horizontal", gap = S["space-4"] })
    bs:Add(UI.Button(buttons, { text = "Reset all", onClick = function()
        -- each mover's own reset (opts.reset), as the toolbar's Reset does
        for _, m in ipairs(movers) do
            if m.onReset then m.onReset() else Settings.Reset(m.namespace, m.key) end
        end
    end }))
    bs:Add(UI.Button(buttons, { text = "Done", variant = "primary", onClick = function() EditMode.Exit() end }))
    stack:Add(buttons)

    local hint = UI.Text(p.body, "caption", "ink-muted")
    hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    hint:SetFixedWidth(226)
    hint:SetValue("Drag a frame to move it, or type its place in the toolbar over it. Arrow keys nudge the selected one, Shift for 10px. Right-click a frame for its settings.")
    stack:Add(hint)
    return p
end

-- The line of keys beside the toolbar while X or Y has focus, or what Enter
-- does with a value past the screen's edge.
local function buildKeys(bar)
    local keys = CreateFrame("Frame", nil, bar)
    keys:SetHeight(KEYS_H)
    keys:SetClampedToScreen(true)
    keys:Hide()
    UI.Fill(keys, "surface"):SetAllPoints()
    UI.Border(keys, "gilt-line")
    keys.parts = {}
    for _, p in ipairs({ { "Enter", "applies" }, { "Tab", "Y" }, { "Esc", "cancels" }, { "↑ ↓", "1 px, Shift 10" } }) do
        local text = UI.Text(keys, "micro", "ink-muted")
        text:SetValue(p[2])
        keys.parts[#keys.parts + 1] = { key = p[1], chip = UI.KeyChip(keys, p[1]), text = text }
    end
    keys.warning = UI.Text(keys, "micro", "amber")
    keys.warning:SetPoint("LEFT", S["space-3"], 0)
    keys.warning:Hide()

    function keys:Layout()
        local x = S["space-3"]
        for i, p in ipairs(self.parts) do
            p.chip:SetKey(p.key) -- measured again (a theme changes the text size)
            p.chip:SetPoint("LEFT", x, 0)
            x = x + p.chip:GetWidth() + S["space-2"]
            p.text:SetPoint("LEFT", x, 0)
            x = x + p.text:GetUnboundedStringWidth() + (i < #self.parts and S["space-3"] or 0)
        end
        if self.warning:IsShown() then x = S["space-3"] + self.warning:GetUnboundedStringWidth() end
        self:SetWidth(x + S["space-3"])
    end
    -- nil: the keys; text: the warning instead
    function keys:Warn(text)
        self.warning:SetValue(text or "")
        self.warning:SetShown(text ~= nil)
        for _, p in ipairs(self.parts) do
            p.chip:SetShown(text == nil)
            p.text:SetShown(text == nil)
        end
        self:Layout()
    end
    -- shown for a field: Tab goes to `nextLetter`
    function keys:For(nextLetter)
        self.parts[2].text:SetValue(nextLetter)
        self:Warn(nil)
        self:Show()
    end
    return keys
end

local function buildToolbar()
    local bar = UI.Panel(overlay, { solid = true, shadow = true })
    bar.body:SetScript("OnSizeChanged", nil)
    bar.body:Hide()
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetClampedToScreen(true) -- a frame at the screen's left or right edge
    bar.keys = buildKeys(bar)

    -- The anchor: a new one leaves the frame where it is (X and Y converted)
    -- and stays when the frame is dragged.
    bar.anchor = UI.AnchorButton(bar, {
        note = "The frame stays where it is; X and Y now measure from this point.",
        tooltip = function()
            if selected and placedByAnother(selected) then
                return { description = "It moves with the frame it's attached to. Detach it to place it by number." }
            end
            if selected and Settings.Get(selected.namespace, selected.key).pinned then
                return { description = "The screen point X and Y measure from, picked by you: it stays when you drag the frame. Reset brings the automatic one back." }
            end
            return { description = "The screen point X and Y measure from, the screen third the frame is in. Click to pick one that stays." }
        end,
        onChange = function(point)
            local m = selected
            local l, b, w, h
            if m then l, b, w, h = rect(m.frame) end
            if not l or placedByAnother(m) then return end
            local _, x, y = anchorFor(l, b, w, h, point)
            save(m, point, math.floor(x + 0.5), math.floor(y + 0.5), true)
        end })
    bar.anchor:SetPoint("LEFT", 3, 0)

    -- X and Y: typed values skip the snap grid and keep the frame on screen.
    local function field(letter, other)
        local f
        f = UI.NumberField(bar, { letter = letter,
            onChange = function(v)
                local m = selected
                if not m or placedByAnother(m) then return end
                local pos = Settings.Get(m.namespace, m.key)
                local x, y = pos.x or 0, pos.y or 0
                if letter == "X" then x = v else y = v end
                save(m, pos.point or "CENTER", x, y)
            end,
            onFocus = function(on)
                if on then
                    bar.anchor:Close()
                    bar.keys:For(other)
                else
                    bar.keys:Hide()
                end
            end,
            onTab = function() bar[other:lower()]:Focus() end,
            onTyping = function(n)
                local kept = n and f:Clamp(n)
                bar.keys:Warn(kept and kept ~= n and ("Off screen past %d: Enter keeps it at %d."):format(kept, kept) or nil)
            end })
        return f
    end
    bar.x = field("X", "Y")
    bar.x:SetPoint("LEFT", bar.anchor, "RIGHT", S["space-2"], 0)
    bar.y = field("Y", "X")
    bar.y:SetPoint("LEFT", bar.x, "RIGHT", S["space-2"], 0)
    bar.rule = UI.Fill(bar, "gilt-line", "ARTWORK")
    bar.rule:SetSize(ns.Pixel.Size(bar), 20)
    bar.rule:SetPoint("LEFT", bar.y, "RIGHT", S["space-3"], 0)

    bar.hide = UI.Button(bar, { text = "Hide", width = 60, onClick = function()
        local m = selected
        if not m then return end
        local pos = Settings.Get(m.namespace, m.key)
        pos.hidden = not pos.hidden or nil
        Settings.Set(m.namespace, m.key, pos)
        select(m)
    end })
    bar.hide:SetPoint("LEFT", bar.y, "RIGHT", S["space-3"] * 2 + 1, 0)
    bar.reset = UI.Button(bar, { text = "Reset", width = 60, onClick = function()
        if not selected then return end
        if selected.onReset then selected.onReset() else Settings.Reset(selected.namespace, selected.key) end
    end })
    bar.reset:SetPoint("LEFT", bar.hide, "RIGHT", S["space-2"], 0)
    -- A mover's own action (opts.action), e.g. "Attach to dock".
    bar.action = UI.Button(bar, { text = "", width = 120, onClick = function()
        local m = selected
        if m and m.action then
            m.action.onClick()
            C_Timer.After(0, function() if active and selected == m then select(m) end end)
        end
    end })
    bar.action:SetPoint("LEFT", bar.reset, "RIGHT", S["space-2"], 0)
    bar.baseWidth = 3 + 30 + S["space-2"] + bar.x:GetWidth() + S["space-2"] + bar.y:GetWidth()
        + S["space-3"] * 2 + 1 + 60 + S["space-2"] + 60 + 3
    bar:SetSize(bar.baseWidth, 36)
    return bar
end

local function buildLayer()
    overlay = CreateFrame("Frame", "SuuUIEditMode", root())
    overlay:SetAllPoints(root())
    overlay:SetFrameStrata("FULLSCREEN")
    -- The layer itself never takes the mouse, so the camera and the world
    -- stay usable; only the movers, the toolbar and the panel do.
    overlay:EnableMouse(false)
    overlay:EnableKeyboard(true)
    overlay:Hide()
    overlay.wash = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.wash:SetAllPoints()
    overlay.wash:SetColorTexture(0, 0, 0, 0.25)
    overlay:SetScript("OnKeyDown", function(self, key)
        local nudge = ({ UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } })[key]
        if toolbar.x:HasFocus() or toolbar.y:HasFocus() then
            self:SetPropagateKeyboardInput(true) -- the field's own keys
        elseif key == "ESCAPE" and toolbar.anchor:IsOpen() then
            self:SetPropagateKeyboardInput(false)
            toolbar.anchor:Close()
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            EditMode.Exit()
        elseif key == "ENTER" and selected and not placedByAnother(selected) then
            -- Enter starts typing the selected frame's X (once this key is
            -- done, so the field doesn't take it as its own Enter)
            self:SetPropagateKeyboardInput(false)
            C_Timer.After(0, function() if active and selected then toolbar.x:Focus() end end)
        elseif nudge and selected then
            self:SetPropagateKeyboardInput(false)
            local step = IsShiftKeyDown() and 10 or 1
            local m = selected
            local l, b, w, h = rect(m.frame)
            if m.onDrop and l and m.onDrop(l + nudge[1] * step, b + nudge[2] * step, w, h) then
                C_Timer.After(0, function() if active then sync(m) end end)
            else
                local pos = Settings.Get(m.namespace, m.key)
                save(m, pos.point or "CENTER", (pos.x or 0) + nudge[1] * step, (pos.y or 0) + nudge[2] * step)
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    overlay.panel = buildPanel()
    toolbar = buildToolbar()
    toolbar:Hide()
end

--------------------------------------------------------------------------------
-- Entering and leaving
--------------------------------------------------------------------------------

function EditMode.IsActive()
    return active
end

function EditMode.Enter()
    if active then return true end
    if InCombatLockdown() then
        ns.Print("Edit mode opens out of combat.")
        return false
    end
    if not overlay then buildLayer() end
    active = true
    overlay:Show()
    drawGrid()
    for _, m in ipairs(movers) do
        if not m.overlay then buildOverlay(m) end
        m.overlay:SetShown(enabled(m))
        sync(m)
    end
    select(nil)
    Events.Emit("SUUUI_EDITMODE_CHANGED", true)
    if groupPreview > 0 or groupPreviewAuras then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", groupPreview, groupPreviewAuras) end
    return true
end

-- The group preview while edit mode is open: its size, 0 (off), 5, 10, 20
-- or 40, and whether every made-up player carries buffs and debuffs.
function EditMode.GroupPreview()
    return active and groupPreview or 0, groupPreviewAuras
end

function EditMode.SetGroupPreview(size, auras)
    groupPreview = size or 0
    if auras ~= nil then groupPreviewAuras = auras and true or false end
    local panel = overlay and overlay.panel
    if panel and panel.previewPick then panel.previewPick:SetValue(groupPreview) end
    if panel and panel.previewAuras then panel.previewAuras:SetValue(groupPreviewAuras) end
    if active then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", groupPreview, groupPreviewAuras) end
end

function EditMode.Exit()
    if not active then return end
    active = false
    select(nil)
    overlay:Hide()
    for _, m in ipairs(movers) do
        if m.overlay then
            m.overlay:SetScript("OnUpdate", nil)
            m.overlay:StopMovingOrSizing()
        end
        place(m)
    end
    Events.Emit("SUUUI_EDITMODE_CHANGED", false)
    if groupPreview > 0 or groupPreviewAuras then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", 0, false) end
end

-- A frame's settings (its right-click): edit mode closes and the Settings
-- window opens at its module's section.
function EditMode.OpenSettings(m)
    local section = settingsSection(m)
    if not section then
        ns.Print(("%s has no settings of its own."):format(m and m.label or "This frame"))
        return
    end
    EditMode.Exit()
    ns.SettingsWindow.Open(section.id)
end

function EditMode.Toggle()
    if active then EditMode.Exit() else EditMode.Enter() end
end

-- Re-reads every mover's `enabled` (a module calls it when one changes).
function EditMode.Refresh()
    if not active then return end
    for _, m in ipairs(movers) do
        if m.overlay then
            local on = enabled(m)
            m.overlay:SetShown(on)
            if not on and selected == m then select(nil) end
            if on then C_Timer.After(0, function() if active then sync(m) end end) end
        end
    end
end

-- A click anywhere but on a mover, the toolbar or the panel deselects. A
-- click away from a field being typed in applies it first.
Events.OnGame("GLOBAL_MOUSE_DOWN", function()
    if not (active and selected) then return end
    for _, f in ipairs({ toolbar.x, toolbar.y }) do
        if f:HasFocus() and not f:IsMouseOver() then f.edit:ClearFocus() end
    end
    if toolbar:IsMouseOver() or toolbar.anchor:PopoverHasMouse() or overlay.panel:IsMouseOver() then return end
    for _, m in ipairs(movers) do
        if m.overlay and m.overlay:IsShown() and m.overlay:IsMouseOver() then return end
    end
    select(nil)
end, "EditMode")

Events.OnGame("PLAYER_REGEN_DISABLED", function()
    if active then
        EditMode.Exit()
        ns.Print("Edit mode closed: combat started.")
    end
end, "EditMode")

Settings.Watch("layout", "gridSize", function() if active then drawGrid() end end, "EditMode")
Events.On("SUUUI_ROOT_SCALED", function()
    if toolbar then toolbar.rule:SetWidth(ns.Pixel.Size(toolbar)) end
    if active then drawGrid() end
end, "EditMode")
-- a theme change: what is sized by a text style's line height (colours
-- follow by themselves)
Events.On("SUUUI_THEME_CHANGED", function()
    for _, o in pairs(overlays) do o.tagFrame:SetHeight(T.type.caption.lineHeight + 2) end
    if toolbar then toolbar.keys:Layout() end
    local p = overlay and overlay.panel
    if p then
        p.previewRow:SetHeight(T.type.label.lineHeight + S["space-2"] + 28)
        p.stack:Invalidate()
    end
    if active then
        for _, m in ipairs(movers) do if m.overlay and m.overlay:IsShown() then sync(m) end end
    end
end, "EditMode")

--------------------------------------------------------------------------------
-- Registering movers
--------------------------------------------------------------------------------

-- `namespace.key` must be a registered setting holding a position table.
function EditMode.Register(frame, opts, owner)
    local m = {
        frame = frame, namespace = opts.namespace, key = opts.key or "position",
        label = opts.label or frame:GetName() or "Frame", owner = owner,
        enabled = opts.enabled,
        customPlace = opts.place, onDrop = opts.onDrop, action = opts.action, onReset = opts.reset,
        dragFrame = opts.dragFrame,
    }
    assert(type(Settings.Get(m.namespace, m.key)) == "table",
        "SuuUI RegisterMover: " .. m.namespace .. "." .. m.key .. " must be a position table in the defaults")
    movers[#movers + 1] = m
    Settings.Watch(m.namespace, m.key, function()
        place(m)
        if active then
            -- Let the frame settle at its new place before the overlay follows.
            C_Timer.After(0, function() if active then sync(m) end end)
        end
    end, m)
    place(m)
    if active then
        buildOverlay(m)
        m.overlay:SetShown(enabled(m))
        C_Timer.After(0, function() sync(m) end)
    end
    return m
end

-- Every registered mover, for the layout check (LayoutCheck.lua): its frame,
-- namespace and key, label, enabled() and whether it places itself.
function EditMode.Movers()
    local out = {}
    for _, m in ipairs(movers) do
        out[#out + 1] = { frame = m.frame, namespace = m.namespace, key = m.key, label = m.label,
            enabled = enabled(m), custom = m.customPlace ~= nil }
    end
    return out
end

-- For movers that place themselves: a frame's rectangle in root units, and
-- the screen anchor edit mode would save for a rectangle.
EditMode.Rect = rect
EditMode.AnchorFor = anchorFor

function EditMode.Unregister(owner)
    for i = #movers, 1, -1 do
        local m = movers[i]
        if m.owner == owner then
            Settings.Unwatch(m)
            if m.overlay then
                m.overlay:SetScript("OnUpdate", nil)
                m.overlay:StopMovingOrSizing()
                m.overlay:Hide()
            end
            if selected == m then select(nil) end
            table.remove(movers, i)
        end
    end
end

ns.RegisterCommand("edit", "Move SuuUI's frames: edit mode with a snap grid.", EditMode.Toggle)
