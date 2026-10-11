-- EditMode/EditMode.lua
-- SuuUI's edit mode: every frame that registers a mover can be dragged on a
-- snap grid, nudged with the arrow keys, hidden and reset. It runs beside the
-- game's own Edit Mode and closes itself when combat starts.
--
--   module:RegisterMover(frame, { key = "position", label = "Hello" })
--
-- The position is a setting in the module's namespace (so it is saved per
-- profile), declared with its default in the module's defaults:
--   defaults = { position = { point = "CENTER", x = 0, y = 200 } }
-- `point` is one of the nine screen anchors and x, y the offset of the
-- frame's same point from it, in design pixels. A dropped frame takes the
-- anchor of the screen third its centre is in, so layouts keep their shape
-- on every resolution. position.hidden hides the frame.

local _, ns = ...

local UI, T, Settings, Events, Combat, Layout = ns.UI, ns.Tokens, ns.Settings, ns.Events, ns.Combat, ns.Layout
local S = T.space

local EditMode = {}
ns.EditMode = EditMode

Settings.Register("layout", {
    snap = true,
    gridSize = 16,
})

local movers = {}   -- list of mover records
local active = false
local selected
local overlay       -- the full-screen edit layer: grid, movers, panel

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function root() return ns.Root end

-- Places `frame` at `pos` (after combat if it is protected).
local function place(m)
    local pos = Settings.Get(m.namespace, m.key)
    Combat.Run("mover:" .. m.namespace .. "." .. m.key, function()
        m.frame:ClearAllPoints()
        m.frame:SetPoint(pos.point or "CENTER", root(), pos.point or "CENTER", pos.x or 0, pos.y or 0)
        m.frame:SetShown(not pos.hidden)
    end, m.label)
end

-- The frame's rectangle in root units.
local function rect(frame)
    local s = frame:GetEffectiveScale() / root():GetEffectiveScale()
    local l, b, w, h = frame:GetRect()
    if not l then return nil end
    return l * s, b * s, w * s, h * s
end

-- The anchor for a rectangle: the screen third its centre falls in, and the
-- offset of the rectangle's same point from the screen's.
local function anchorFor(l, b, w, h)
    local W, H = root():GetWidth(), root():GetHeight()
    local cx, cy = l + w / 2, b + h / 2
    local horiz = (cx < W / 3 and "LEFT") or (cx > W * 2 / 3 and "RIGHT") or ""
    local vert = (cy < H / 3 and "BOTTOM") or (cy > H * 2 / 3 and "TOP") or ""
    local point = vert .. horiz
    if point == "" then point = "CENTER" end
    local fx = (horiz == "LEFT" and l) or (horiz == "RIGHT" and l + w) or cx
    local fy = (vert == "BOTTOM" and b) or (vert == "TOP" and b + h) or cy
    local rx = (horiz == "LEFT" and 0) or (horiz == "RIGHT" and W) or W / 2
    local ry = (vert == "BOTTOM" and 0) or (vert == "TOP" and H) or H / 2
    return point, fx - rx, fy - ry
end

local function snap(v)
    if not Settings.Get("layout", "snap") then return math.floor(v + 0.5) end
    local g = Settings.Get("layout", "gridSize")
    return math.floor(v / g + 0.5) * g
end

local function save(m, point, x, y)
    local pos = Settings.Get(m.namespace, m.key)
    pos.point, pos.x, pos.y = point, x, y
    Settings.Set(m.namespace, m.key, pos)
end

--------------------------------------------------------------------------------
-- Mover overlays
--------------------------------------------------------------------------------

local function sync(m)
    local o = m.overlay
    if not o then return end
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
    o.tagBg:SetColorTexture(UI.RGBA(hidden and "ink-faint" or "arcane"))
    o.tag:SetValue(m.label .. (hidden and " (hidden)" or ""))
    o.tagFrame:SetWidth(o.tag:GetUnboundedStringWidth() + 10)
    local on = selected == m
    o.edge:SetColor("arcane", (on or o:IsMouseOver()) and 1 or 0.6)
    o.glow:SetShown(on)
end

local toolbar

local function select(m)
    local was = selected
    selected = m
    if was then sync(was) end
    if not m then
        if toolbar then toolbar:Hide() end
        return
    end
    sync(m)
    local hidden = Settings.Get(m.namespace, m.key).hidden
    toolbar.hide:SetLabel(hidden and "Show" or "Hide")
    toolbar:ClearAllPoints()
    toolbar:SetPoint("BOTTOMRIGHT", m.overlay, "TOPRIGHT", 0, S["space-5"] + 6)
    toolbar:Show()
end

local function buildOverlay(m)
    local o = CreateFrame("Button", nil, overlay)
    o:SetFrameLevel(overlay:GetFrameLevel() + 10)
    o:SetMovable(true)
    o:SetClampedToScreen(true)
    o:RegisterForDrag("LeftButton")
    o.wash = o:CreateTexture(nil, "BACKGROUND")
    o.wash:SetAllPoints()
    o.wash:SetColorTexture(UI.RGBA("arcane", 0.06))
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
    o.size = UI.Text(o, "micro", "ink-muted")
    o.size:SetShadowed(true)
    o.size:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 0, -3)

    o:SetScript("OnEnter", function() sync(m) end)
    o:SetScript("OnLeave", function() sync(m) end)
    o:SetScript("OnClick", function() select(m) end)
    o:SetScript("OnDragStart", function(self)
        select(m)
        self:StartMoving()
        -- The real frame follows while dragging, unless it is protected.
        self:SetScript("OnUpdate", function()
            if m.frame:IsProtected() then return end
            local l, b = self:GetLeft(), self:GetBottom()
            m.frame:ClearAllPoints()
            m.frame:SetPoint("BOTTOMLEFT", root(), "BOTTOMLEFT", l, b)
        end)
    end)
    o:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        local point, x, y = anchorFor(self:GetLeft(), self:GetBottom(), self:GetWidth(), self:GetHeight())
        save(m, point, snap(x), snap(y))
    end)
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
        t:SetColorTexture(UI.RGBA("arcane", alpha))
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

    local buttons = CreateFrame("Frame", nil, p.body)
    local bs = Layout.Stack(buttons, { direction = "horizontal", gap = S["space-4"] })
    bs:Add(UI.Button(buttons, { text = "Reset all", onClick = function()
        for _, m in ipairs(movers) do Settings.Reset(m.namespace, m.key) end
    end }))
    bs:Add(UI.Button(buttons, { text = "Done", variant = "primary", onClick = function() EditMode.Exit() end }))
    stack:Add(buttons)

    local hint = UI.Text(p.body, "caption", "ink-muted")
    hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    hint:SetFixedWidth(226)
    hint:SetValue("Drag a frame to move it. Arrow keys nudge the selected one, Shift for 10px.")
    stack:Add(hint)
    return p
end

local function buildToolbar()
    local bar = UI.Panel(overlay, { solid = true, shadow = true })
    bar.body:SetScript("OnSizeChanged", nil)
    bar.body:Hide()
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar.hide = UI.Button(bar, { text = "Hide", width = 60, onClick = function()
        local m = selected
        if not m then return end
        local pos = Settings.Get(m.namespace, m.key)
        pos.hidden = not pos.hidden or nil
        Settings.Set(m.namespace, m.key, pos)
        select(m)
    end })
    bar.hide:SetPoint("LEFT", 3, 0)
    bar.reset = UI.Button(bar, { text = "Reset", width = 60, onClick = function()
        if selected then Settings.Reset(selected.namespace, selected.key) end
    end })
    bar.reset:SetPoint("LEFT", bar.hide, "RIGHT", S["space-2"], 0)
    bar:SetSize(3 + 60 + S["space-2"] + 60 + 3, 36)
    return bar
end

local function buildLayer()
    overlay = CreateFrame("Frame", "SuuUIEditMode", root())
    overlay:SetAllPoints(root())
    overlay:SetFrameStrata("FULLSCREEN")
    overlay:EnableMouse(true)
    overlay:EnableKeyboard(true)
    overlay:Hide()
    overlay.wash = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.wash:SetAllPoints()
    overlay.wash:SetColorTexture(0, 0, 0, 0.25)
    overlay:SetScript("OnKeyDown", function(self, key)
        local nudge = ({ UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } })[key]
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            EditMode.Exit()
        elseif nudge and selected then
            self:SetPropagateKeyboardInput(false)
            local step = IsShiftKeyDown() and 10 or 1
            local pos = Settings.Get(selected.namespace, selected.key)
            save(selected, pos.point or "CENTER", (pos.x or 0) + nudge[1] * step, (pos.y or 0) + nudge[2] * step)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- A click on empty space deselects.
    overlay:SetScript("OnMouseDown", function() select(nil) end)
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
        m.overlay:Show()
        sync(m)
    end
    select(nil)
    Events.Emit("SUUUI_EDITMODE_CHANGED", true)
    return true
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
end

function EditMode.Toggle()
    if active then EditMode.Exit() else EditMode.Enter() end
end

Events.OnGame("PLAYER_REGEN_DISABLED", function()
    if active then
        EditMode.Exit()
        ns.Print("Edit mode closed: combat started.")
    end
end, "EditMode")

Settings.Watch("layout", "gridSize", function() if active then drawGrid() end end, "EditMode")
Events.On("SUUUI_ROOT_SCALED", function() if active then drawGrid() end end, "EditMode")

--------------------------------------------------------------------------------
-- Registering movers
--------------------------------------------------------------------------------

-- `namespace.key` must be a registered setting holding a position table.
function EditMode.Register(frame, opts, owner)
    local m = {
        frame = frame, namespace = opts.namespace, key = opts.key or "position",
        label = opts.label or frame:GetName() or "Frame", owner = owner,
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
        m.overlay:Show()
        C_Timer.After(0, function() sync(m) end)
    end
    return m
end

function EditMode.Unregister(owner)
    for i = #movers, 1, -1 do
        local m = movers[i]
        if m.owner == owner then
            Settings.Unwatch(m)
            if m.overlay then m.overlay:Hide() end
            if selected == m then select(nil) end
            table.remove(movers, i)
        end
    end
end

ns.RegisterCommand("edit", "Move SuuUI's frames: edit mode with a snap grid.", EditMode.Toggle)
