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

-- A mover whose frame is turned off (opts.enabled says so) stays out of edit
-- mode: hiding it there is for frames that are on.
local function enabled(m)
    return not m.enabled or m.enabled() and true or false
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
    local base = 3 + 60 + S["space-2"] + 60 + 3
    if m.action then
        toolbar.action:SetLabel(m.action.label())
        toolbar.action:Show()
        toolbar:SetWidth(base + S["space-2"] + 120)
    else
        toolbar.action:Hide()
        toolbar:SetWidth(base)
    end
    toolbar:ClearAllPoints()
    toolbar:SetPoint("BOTTOMRIGHT", m.overlay, "TOPRIGHT", 0, S["space-5"] + 6)
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

    o:SetScript("OnEnter", function(self) sync(self.mover) end)
    o:SetScript("OnLeave", function(self) sync(self.mover) end)
    o:SetScript("OnClick", function(self) select(self.mover) end)
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
        local point, x, y = anchorFor(l, b, w, h)
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

    -- made-up players in the group frames, at their real place and size
    local previewRow = CreateFrame("Frame", nil, p.body)
    previewRow:SetSize(226, T.type.label.lineHeight + S["space-2"] + 28)
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
    bar:SetSize(3 + 60 + S["space-2"] + 60 + 3, 36)
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
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            EditMode.Exit()
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
    if groupPreview > 0 then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", groupPreview) end
    return true
end

-- The group preview's size while edit mode is open: 0 (off), 5, 10, 20 or 40.
function EditMode.GroupPreview()
    return active and groupPreview or 0
end

function EditMode.SetGroupPreview(size)
    groupPreview = size or 0
    if overlay and overlay.panel and overlay.panel.previewPick then overlay.panel.previewPick:SetValue(groupPreview) end
    if active then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", groupPreview) end
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
    if groupPreview > 0 then Events.Emit("SUUUI_EDITMODE_GROUP_PREVIEW", 0) end
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

-- A click anywhere but on a mover, the toolbar or the panel deselects.
Events.OnGame("GLOBAL_MOUSE_DOWN", function()
    if not (active and selected) then return end
    if toolbar:IsMouseOver() or overlay.panel:IsMouseOver() then return end
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
Events.On("SUUUI_ROOT_SCALED", function() if active then drawGrid() end end, "EditMode")

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
