-- A rows-by-columns grid of ActionButtons on one glass plate.
--
-- Owns the A2 look and nothing else: it is handed a list of action slots and renders them.
-- Which slots those are, and where the bar sits, belong to Plugins/ActionBars.
--
-- EVERY GEOMETRY CHANGE IS DEFERRED OUT OF COMBAT, and that is not caution -- it is the only
-- thing that works. A grid contains protected buttons by construction, so the client refuses
-- SetSize on the grid AND SetPoint on each button while InCombatLockdown() is true, silently,
-- with "Interface action failed because of an AddOn" in the player's chat. A layout pass in
-- combat therefore does not half-work; it does nothing and complains. So a settings change
-- arriving mid-fight sets a flag, returns, and catches up on PLAYER_REGEN_ENABLED.
-- Plugins/UnitFrames/UnitFrame.lua (_syncClickArea) is the reference for the shape.
--
-- The plate takes NO mouse input. Buttons enable their own; a plate that swallowed clicks
-- would make the gaps between buttons unclickable in the world behind them.
local pairs, next, ipairs, type = pairs, next, ipairs, type
local ceil, max = math.ceil, math.max
local S = SuuUI.UISignals

---------------------------------------------------------------------------
-- Shared combat watcher
---------------------------------------------------------------------------
-- One frame for every grid in the addon, registered only while at least one exists. There
-- are at most a handful of bars, but a grid that outlived its event frame would silently stop
-- catching up after a fight -- and the failure would look like "my bar ignores the setting".

local live = {}
local regen

local function onRegen()
    for grid in pairs(live) do
        if grid._deferred then grid:_apply() end
    end
end

local function syncRegenWatcher()
    if next(live) ~= nil then
        if not regen then
            regen = CreateFrame("Frame")
            regen:SetScript("OnEvent", onRegen)
        end
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif regen then
        regen:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------
-- Component
---------------------------------------------------------------------------

local GridMeta = {}
GridMeta.__index = GridMeta

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- Columns needed to show every slot in the requested number of rows. Derived rather than
-- configured: a player picks "12 buttons in 2 rows", not "6 columns", and letting both be
-- set independently allows a grid that cannot hold its own buttons.
function GridMeta:_columns()
    local n = #self._slots
    if n == 0 then return 1 end
    local rows = max(1, self._rows or 1)
    return max(1, ceil(n / rows))
end

function GridMeta:_rowCount()
    local n = #self._slots
    if n == 0 then return 1 end
    return max(1, ceil(n / self:_columns()))
end

-- Builds buttons until there is one per slot, and destroys any surplus.
--
-- A slot change destroys and recreates rather than re-pointing, because re-pointing means
-- SetAttribute on a protected frame -- refused in combat, and forbidden by the component's
-- own contract, which states attributes once at construction.
function GridMeta:_syncButtons()
    local buttons = self._buttons
    local want = #self._slots
    -- Tracked so CHILDREN_CHANGED fires only when the set REALLY moved. A subscriber re-reads
    -- every button on it -- secure paging re-states a frame reference per button -- so firing on
    -- a no-op re-apply would make every unrelated setting change pay for it.
    local rebuilt = false

    for i = #buttons, want + 1, -1 do
        self._gridBox:Remove(buttons[i])
        buttons[i]:Destroy()
        buttons[i] = nil
        rebuilt = true
    end

    for i = 1, want do
        local slot = self._slots[i]
        local existing = buttons[i]
        if existing and existing:GetSlot() ~= slot then
            self._gridBox:Remove(existing)
            existing:Destroy()
            existing = nil
            buttons[i] = nil
        end
        if not existing then
            local b = self._buttonFactory({
                slot          = slot,
                size          = self._buttonSize,
                binding       = self._bindings and self._bindings[i] or nil,
                showHotkey    = self._showHotkey,
                showMacroText = self._showMacroText,
                showCount     = self._showCount,
                showCooldownText = self._showCooldownText,
                name          = self._namePrefix and (self._namePrefix .. i) or nil,
            }, self._f)
            buttons[i] = b
            self._gridBox:Add(b, { height = self._buttonSize })
            rebuilt = true
        else
            -- GridLayout sets a cell's WIDTH from the container and READS the child's own
            -- height, so a size change has to reach the button itself -- the child prop alone
            -- would leave it at its construction height and the grid a row too short.
            existing:SetSize(self._buttonSize, self._buttonSize)
            existing:SetBinding(self._bindings and self._bindings[i] or nil)
            existing:SetShowHotkey(self._showHotkey)
            existing:SetShowMacroText(self._showMacroText)
            existing:SetShowCount(self._showCount)
            existing:SetShowCooldownText(self._showCooldownText)
            self._gridBox:SetChildProps(existing, { height = self._buttonSize })
        end
    end

    self._rebuilt = rebuilt
end

-- Hairline dividers between cells, drawn only for a SEAMLESS grid.
--
-- With spacing above zero the plate already shows through between the cells, and a divider
-- inside that gap would be a second separator inside the first. At spacing zero the cells
-- touch, and the divider is the only thing telling them apart -- which is the A2 look.
function GridMeta:_syncDividers()
    local wanted = 0
    local cols, rows = self:_columns(), self:_rowCount()
    if self._spacing == 0 then wanted = (cols - 1) + (rows - 1) end
    if wanted < 0 then wanted = 0 end

    local lines = self._dividers
    for i = #lines, wanted + 1, -1 do
        self._divBox:Remove(lines[i])
        lines[i]:Hide()
        lines[i] = nil
    end
    for i = #lines + 1, wanted do
        -- OVERLAY so the line sits above every layer the glass plate drew. The buttons are
        -- child FRAMES and draw above all of it regardless, which is why a divider never
        -- covers an icon.
        local tex = self._divHost:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        lines[i] = tex
        self._divBox:Add(tex)
    end

    if wanted == 0 then return end

    -- Raised on every sync, not once at construction: a rebuild destroys and recreates the buttons,
    -- and the new ones may land at a different level. RaiseAbove is the only sanctioned z-order
    -- mechanism outside Core/UIRoot.lua.
    local first = self._buttons[1]
    if first and self._divHost then
        SuuUI.UIRoot:RaiseAbove(self._divHost, first:GetFrame(), 1)
    end

    local hair = SuuUI.Pixel.Line(0)
    local pad  = self._padding
    local size = self._buttonSize
    local innerW = cols * size
    local innerH = rows * size
    local c = SuuUI.Theme:GetToken("colorBorder") or { 0, 0, 0, 1 }
    local i = 0

    -- `y` IS NEGATIVE BECAUSE IT FOLLOWS SetPoint, WHERE POSITIVE IS UP.
    --
    -- The offsets here are measured DOWN from the plate's top edge, so each one has to be negated.
    -- Getting this wrong is not subtle once seen but it is easy to miss in review: a positive `y`
    -- lifted every vertical divider 2 * padding, so they peeked out above the plate and stopped
    -- short of the bottom row, and it pushed the horizontal dividers clean OFF the plate -- they
    -- drew in empty space above the bar while the bar itself had none.
    for col = 1, cols - 1 do
        i = i + 1
        lines[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        self._divBox:SetChildAnchor(lines[i], {
            x = pad + col * size, y = -pad, width = hair, height = innerH,
        })
    end
    for row = 1, rows - 1 do
        i = i + 1
        lines[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        self._divBox:SetChildAnchor(lines[i], {
            x = pad, y = -(pad + row * size), width = innerW, height = hair,
        })
    end
end

--- Re-derives the whole grid: size, columns, buttons, dividers.
--
-- Refused outright in combat rather than attempted. A refused call costs the player a chat
-- error for something we already knew would not land, and the deferred flag is what makes it
-- arrive the moment the fight ends.
function GridMeta:_apply()
    if inCombat() then
        self._deferred = true
        return
    end
    self._deferred = nil

    local cols, rows = self:_columns(), self:_rowCount()
    local size, gap, pad = self._buttonSize, self._spacing, self._padding

    self._gridBox:SetColumns(cols)
    self._gridBox:SetGap(gap)
    self._gridBox:SetPadding({ left = pad, right = pad, top = pad, bottom = pad })

    -- The frame's width is what GridLayout divides into columns, so it is set to exactly the
    -- span the buttons need -- then each cell comes out at buttonSize rather than at whatever
    -- share of a wider box the layout would otherwise hand out.
    local w = pad * 2 + cols * size + gap * (cols - 1)
    local h = pad * 2 + rows * size + gap * (rows - 1)
    self._f:SetSize(w, h)

    self:_syncButtons()
    self:_syncDividers()
    self._gridBox:Layout()
    self._divBox:Layout()

    -- Emitted LAST, after the layout has settled, so a subscriber reading a button's geometry
    -- gets the finished rect rather than a half-applied one. A deferred apply reaches here on
    -- PLAYER_REGEN_ENABLED, which is the case that makes the signal necessary at all: nothing
    -- else tells a holder of button references when the fight-delayed rebuild finally happened.
    if self._rebuilt then
        self._rebuilt = false
        S:Emit(self, S.SIGNALS.CHILDREN_CHANGED)
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Replaces the slots this grid renders, and optionally their binding commands.
-- @param slots table  array of action slot numbers
-- @param bindings table|nil  parallel array of binding command names
function GridMeta:SetSlots(slots, bindings)
    self._slots = slots or {}
    self._bindings = bindings
    self:_apply()
end

--- The slots currently rendered, as a copy.
-- @return table
function GridMeta:GetSlots()
    local out = {}
    for i, s in ipairs(self._slots) do out[i] = s end
    return out
end

--- Sets how many rows the buttons are spread across. Columns follow from the slot count.
-- @param rows number
function GridMeta:SetRows(rows)
    local n = max(1, rows or 1)
    if n == self._rows then return end
    self._rows = n
    self:_apply()
end

--- Sets the side of each square button. A plugin setting, never a theme token.
-- @param size number
function GridMeta:SetButtonSize(size)
    if not size or size == self._buttonSize then return end
    self._buttonSize = size
    self:_apply()
end

--- Sets the gap between cells. Zero is the seamless look, and the only one with dividers.
-- @param spacing number
function GridMeta:SetSpacing(spacing)
    local n = spacing or 0
    if n < 0 then n = 0 end
    if n == self._spacing then return end
    self._spacing = n
    self:_apply()
end

--- Shows or hides the hotkey readout on every button.
-- @param show bool
function GridMeta:SetShowHotkeys(show)
    self._showHotkey = show ~= false
    for _, b in ipairs(self._buttons) do b:SetShowHotkey(self._showHotkey) end
end

--- Shows or hides the macro name readout on every button.
-- @param show bool
function GridMeta:SetShowMacroText(show)
    self._showMacroText = show ~= false
    for _, b in ipairs(self._buttons) do b:SetShowMacroText(self._showMacroText) end
end

--- Shows or hides the stack count readout on every button.
-- @param show bool
function GridMeta:SetShowCount(show)
    self._showCount = show ~= false
    for _, b in ipairs(self._buttons) do b:SetShowCount(self._showCount) end
end

--- Shows or hides the remaining-cooldown number on every button.
-- @param show bool
function GridMeta:SetShowCooldownText(show)
    self._showCooldownText = show ~= false
    for _, b in ipairs(self._buttons) do b:SetShowCooldownText(self._showCooldownText) end
end

--- The buttons, in slot order. Live handles, not a copy of their state.
-- @return table
function GridMeta:GetButtons()
    return self._buttons
end

--- Whether a geometry change is waiting for the fight to end.
--
-- Exposed because it is otherwise invisible: the grid looks correct, it is simply showing the
-- previous setting, and a spec has to be able to tell "deferred" from "ignored".
-- @return bool
function GridMeta:IsDeferred()
    return self._deferred == true
end

--- Re-reads every button's action, without touching geometry.
--- Safe in combat: reading an action and repainting a texture are not protected.
function GridMeta:Refresh()
    for _, b in ipairs(self._buttons) do b:Refresh() end
end

function GridMeta:ApplyTheme()
    self._plate:Refresh()
    -- Padding follows a spacing token, so a theme edit changes the grid's size. Guarded like
    -- any other geometry change: a theme edit mid-fight defers with everything else.
    self._padding = SuuUI.Theme:GetToken(self._paddingToken) or self._padding
    self:_apply()
end

function GridMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    live[self] = nil
    syncRegenWatcher()
    for i = #self._buttons, 1, -1 do
        self._buttons[i]:Destroy()
        self._buttons[i] = nil
    end
    self._plate:Destroy()
    self._divBox:Destroy()
    self._gridBox:Destroy()
    self._f:Hide()
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, Show, Hide.
SuuUI.Components.InstallBase(GridMeta, "_f")

-- No SetEnabled, for the reason ActionButton has none: the only real disabling is dropping
-- mouse input on the buttons, which the client refuses on a protected frame in combat.

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Creates a grid of action buttons on a glass plate.
--
-- Emits SIZE_CHANGED. It has no click of its own -- the buttons emit theirs, and the owner
-- reads them off the handles in GetButtons().
--
-- @param props table  { slots, bindings, rows, buttonSize, spacing, padding,
--                       showHotkeys, showMacroText, showCount, showCooldownText,
--                       namePrefix, buttonFactory }
--   slots:         array of action slot numbers. Required, may be empty.
--   buttonSize:    side of each square button. Required -- a PLUGIN SETTING, not a token.
--   bindings:      parallel array of binding commands, e.g. { "ACTIONBUTTON1", ... }
--   rows:          rows to spread the slots across (default 1); columns follow
--   spacing:       gap between cells (default 0, the seamless look with dividers)
--   padding:       plate margin around the buttons; omit to follow the spaceXs token, which
--                  is what makes the glass visible at all -- at zero padding a seamless grid
--                  covers its own plate completely
--   namePrefix:    optional global name prefix for the buttons, so /framestack and
--                  click-casting addons can name them
--   buttonFactory: how a cell's button is built; defaults to ActionButton. The stance bar
--                  passes its own, because its buttons must inherit Blizzard's
--                  StanceButtonTemplate rather than SecureActionButtonTemplate
-- @param parent frame
-- @return table  ActionBarGrid handle
function SuuUI.Components.ActionBarGrid(props, parent)
    props = props or {}
    assert(type(props.slots) == "table", "SuuUI: ActionBarGrid needs a slots array")
    assert(type(props.buttonSize) == "number", "SuuUI: ActionBarGrid needs a buttonSize")

    local PADDING_TOKEN = "spaceXs"

    local f = CreateFrame("Frame", nil, parent)
    -- Deliberately no EnableMouse: see the header. The plate must not swallow a click aimed
    -- at the world in the gap between two buttons.

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- The plate: one translucent gradient with a lit top edge, covering the whole box. inset 0
    -- because there is no border to stay clear of, and a plate a pixel short on every side
    -- would leave the buttons overhanging it.
    local plate = SuuUI.Backdrop.Glass(f, {
        from = "colorGlass", to = "colorGlassFade", sheen = "colorGlassSheen",
        border = false, inset = 0,
    })

    -- Two containers on one host, with disjoint children: the grid places the buttons, the
    -- anchor box places the dividers at computed offsets, which no flow or grid strategy can
    -- express because a divider sits BETWEEN cells rather than in one.
    local gridBox = SuuUI.Layout:CreateContainer({
        host = f, layout = "grid", cols = 1, gap = 0,
    })
    -- The dividers live on their OWN frame, raised above the buttons -- not as textures on the
    -- plate. A texture on a parent frame can never draw above a child FRAME, and every button is
    -- one, so a hairline sitting exactly on a cell boundary was covered by the button beside it.
    --
    -- That is why the dividers looked "not fully visible": before the y sign was fixed they were
    -- positioned outside the plate, and the only part a player could see was the part sticking out
    -- where no button covered it. Correcting the position made them vanish entirely, which is the
    -- honest result of drawing them underneath.
    local divHost = CreateFrame("Frame", nil, f)
    divHost:SetAllPoints(f)
    local divBox = SuuUI.Layout:CreateContainer({ host = divHost, layout = "anchor" })

    local id = "actionbargrid_" .. tostring(f)
    handle = setmetatable({
        _f             = f,
        _plate         = plate,
        _gridBox       = gridBox,
        _divBox        = divBox,
        _divHost       = divHost,
        _buttons       = {},
        _dividers      = {},
        _slots         = props.slots,
        _bindings      = props.bindings,
        _rows          = max(1, props.rows or 1),
        _buttonSize    = props.buttonSize,
        _spacing       = props.spacing or 0,
        _paddingToken  = PADDING_TOKEN,
        _padding       = props.padding or SuuUI.Theme:GetToken(PADDING_TOKEN) or 4,
        _showHotkey    = props.showHotkeys ~= false,
        _showMacroText = props.showMacroText ~= false,
        _showCount     = props.showCount ~= false,
        _showCooldownText = props.showCooldownText ~= false,
        _namePrefix    = props.namePrefix,
        -- How a cell's button is built. Defaults to ActionButton, which is what bars 1-8 want.
        -- The seam exists because the STANCE bar cannot use ActionButton at all: its buttons
        -- must inherit Blizzard's StanceButtonTemplate, since a stance button carries no `type`
        -- attribute and CastShapeshiftForm is blocked for addon code (both probed in game). The
        -- plate, the grid, the dividers, the padding, the resize deferral and the theme wiring
        -- are identical either way, so only the button construction is parameterised.
        _buttonFactory = props.buttonFactory or SuuUI.Components.ActionButton,
        _eid           = id,
    }, GridMeta)

    live[handle] = true
    syncRegenWatcher()

    handle:_apply()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end

-- Test seam. The live set and the shared watcher are module-local, so a spec cannot otherwise
-- assert that the PLAYER_REGEN_ENABLED registration really does drop with the last grid.
SuuUI._ActionBarGridInternals = {
    liveCount = function()
        local n = 0
        for _ in pairs(live) do n = n + 1 end
        return n
    end,
    regenFrame = function() return regen end,
}
