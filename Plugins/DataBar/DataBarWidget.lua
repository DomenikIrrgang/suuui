-- The bar itself: three sections of fields, built from whatever Core/DataBar holds.
--
-- The bar owns every visual decision — the surface, the dividers, the hover rail, the font
-- step, one shared ticker — so a widget definition is data and a plugin writes no UI code.
-- That is the same division the settings schema draws, and for the same reason: eight plugins
-- each building their own field is eight different paddings.
local ipairs, pairs, type, pcall, tostring = ipairs, pairs, type, pcall, tostring

SuuUI._DataBar = SuuUI._DataBar or {}

local OWNER = "databar.bar"

local Bar = {}
Bar.__index = Bar

---------------------------------------------------------------------------
-- Shared ticker
---------------------------------------------------------------------------
-- One OnUpdate for every widget that refreshes on a clock, unregistered the moment none
-- does. A frame per widget would be a frame and a script per widget for the same work, and
-- the per-tick loop is index-based with the accumulator living on the record, so a tick
-- allocates nothing.
local ticker
local tickList = {}

local function onTick(_, dt)
    for i = 1, #tickList do
        local rec = tickList[i]
        rec.acc = rec.acc + dt
        if rec.acc >= rec.interval then
            rec.acc = 0
            rec.bar:_refresh(rec)
        end
    end
end

local function syncTicker()
    if #tickList > 0 then
        if not ticker then ticker = CreateFrame("Frame") end
        ticker:SetScript("OnUpdate", onTick)
    elseif ticker then
        ticker:SetScript("OnUpdate", nil)
    end
end

-- Drops one bar's records. Keyed by bar rather than cleared wholesale so a second bar — a
-- bottom bar later — does not stop the first one ticking when it is torn down.
local function dropTicks(bar)
    for i = #tickList, 1, -1 do
        if tickList[i].bar == bar then table.remove(tickList, i) end
    end
    syncTicker()
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

--- The bar's height in root units, derived from tokens so it follows the font steps.
-- @return number
function Bar:GetBarHeight()
    return SuuUI.Theme:GetControlHeight("sizeRow")
end

-- Each section is a horizontal flow, and flow hugs its content on the CROSS axis only —
-- width defaults to the parent's. A section left at that default would be full-bar-wide and
-- all three would sit on top of each other, so the width is stated from the content size.
-- Width hugging in the engine would remove this; it does not exist yet.
function Bar:_sizeSections()
    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        local group = self._groups[name]
        local gw = group:GetContentSize()
        group:SetWidth(gw or 0)
        -- Mutated in place and applied by one Layout pass, rather than a SetChildProps per
        -- section which would run a whole layout each time.
        self._groupProps[name].width = gw or 0
    end
    self._box:Layout()
end

-- Full width, pinned to the top edge. Stated to UIRoot rather than anchored here, so the bar
-- goes through the same placement path as everything else and never touches SetPoint.
function Bar:_place()
    local h = self:GetBarHeight()
    self._anchor.width  = self._root:GetWidth() or 0
    self._anchor.height = h
    SuuUI.UIRoot:UpdateElementAnchor(self._f, self._anchor)
    -- Published so anything that used to hug the top of the screen can move out of the way.
    SuuUI.DataBar:SetOccupiedHeight(h)
end

---------------------------------------------------------------------------
-- Fields
---------------------------------------------------------------------------

-- Refreshes one record from its definition. GetText is plugin code called on a ticker and on
-- game events, so it runs through pcall: an error there would otherwise stop the whole tick
-- loop and take every other widget's refresh with it.
function Bar:_refresh(rec)
    local def = rec.def
    if rec.custom then
        if type(def.Refresh) == "function" then
            local ok, err = pcall(def.Refresh, rec.field)
            if not ok then
                SuuUI.Debug("DataBar: widget " .. def.id .. " Refresh error: " .. tostring(err))
            end
        end
        return
    end
    -- Explicit locals, not a chained call: GetText may return a second value (the tone), and a
    -- multi-return expands only in the last argument position — passing it straight into
    -- SetText would silently hand the tone over as SetText's second argument.
    local ok, text, tone = pcall(def.GetText)
    if not ok then
        SuuUI.Debug("DataBar: widget " .. def.id .. " GetText error: " .. tostring(text))
        return
    end
    rec.field:SetText(type(text) == "string" and text or tostring(text or ""))
    rec.field:SetTone(type(tone) == "string" and tone or nil)
end

local function callHook(def, name, ...)
    local fn = def[name]
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        SuuUI.Debug("DataBar: widget " .. def.id .. " " .. name .. " error: " .. tostring(err))
    end
end

function Bar:_buildField(def, group)
    local S = SuuUI.UISignals
    local parent = group:GetFrame()
    local rec = { def = def, bar = self, acc = 0 }

    if type(def.Build) == "function" then
        local ok, handle = pcall(def.Build, parent)
        if not ok or not handle then
            SuuUI.Debug("DataBar: widget " .. def.id .. " Build failed: " .. tostring(handle))
            return nil
        end
        rec.field  = handle
        rec.custom = true
        group:Add(handle, { align = "stretch" })
    else
        -- A field only advertises a rail when the widget does something on hover or click.
        -- The rail is the "you can act on this" cue, so painting it on a pure readout would
        -- promise an interaction that is not there.
        local interactive = type(def.OnClick) == "function"
            or type(def.OnEnter) == "function"
        -- `icon` / `iconCoords` / `iconSize` are passed straight through from the widget def. A
        -- widget that wants a glyph instead of a prefix -- the micro menu is fourteen of them --
        -- states them once at registration; the field owns the placement and the hug.
        local field = SuuUI.Components.DataField({
            prefix     = def.prefix,
            rail       = interactive,
            h          = self:GetBarHeight(),
            icon       = def.icon,
            iconCoords = def.iconCoords,
            iconSize   = def.iconSize,
        }, parent)
        rec.field = field
        group:Add(field, { align = "stretch" })

        S:Connect(field, S.SIGNALS.CLICKED, function(btn)
            callHook(def, "OnClick", field, btn)
        end)
        S:Connect(field, S.SIGNALS.MOUSE_ENTER, function()
            callHook(def, "OnEnter", field)
        end)
        S:Connect(field, S.SIGNALS.MOUSE_LEAVE, function()
            callHook(def, "OnLeave", field)
        end)
        -- A field hugs its own text, so a value that changes width changes the section's
        -- width, which changes where the centre section sits. Nothing else would notice.
        S:Connect(field, S.SIGNALS.SIZE_CHANGED, function()
            self:_sizeSections()
        end)
        self:_refresh(rec)
    end

    return rec
end

function Bar:_clearFields()
    local S = SuuUI.UISignals
    dropTicks(self)

    for _, rec in ipairs(self._records) do
        -- The bar called OnEnter, so the bar owes OnLeave. Disconnecting first means no
        -- MOUSE_LEAVE ever reaches the widget, which leaves anything it opened on that hover —
        -- the latency readout's breakdown, the clock's — still on screen, anchored to a frame
        -- about to be hidden, and self-healing only on the next hover. Any widget toggle
        -- rebuilds the bar, so hovering a field and flipping a setting was enough to hit it.
        --
        -- Gated on the field actually being hovered, which is exactly the state that produced
        -- the unmatched OnEnter: no MOUSE_LEAVE fired, so _hovered is still true here.
        if not rec.custom and rec.field.IsHovered and rec.field:IsHovered() then
            callHook(rec.def, "OnLeave", rec.field)
        end
        S:DisconnectAll(rec.field)
        if rec.field.Destroy then rec.field:Destroy() end
    end
    for _, div in ipairs(self._dividers) do div:Destroy() end
    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        self._groups[name]:Clear()
    end

    for i = #self._records, 1, -1 do self._records[i] = nil end
    for i = #self._dividers, 1, -1 do self._dividers[i] = nil end
    for k in pairs(self._byEvent) do self._byEvent[k] = nil end
end

--- Rebuilds every field from the registry. Called on every register and unregister.
function Bar:Rebuild()
    self:_clearFields()

    local anyEarlier = false
    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        local defs  = SuuUI.DataBar:ListSection(name)
        local group = self._groups[name]
        local first = true

        for _, def in ipairs(defs) do
            -- A divider between adjacent fields, and one on the leading edge of a section
            -- that follows a populated one — which is what puts an edge either side of a
            -- lone centre field instead of leaving it floating.
            if not first or anyEarlier then
                local div = SuuUI.Components.Divider({ dir = "vertical" }, group:GetFrame())
                self._dividers[#self._dividers + 1] = div
                group:Add(div, { align = "stretch" })
            end

            local rec = self:_buildField(def, group)
            if rec then
                self._records[#self._records + 1] = rec
                first = false

                if type(def.update) == "number" and def.update > 0 then
                    rec.interval = def.update
                    tickList[#tickList + 1] = rec
                end
                for _, event in ipairs(def.events or {}) do
                    local list = self._byEvent[event]
                    if not list then list = {}; self._byEvent[event] = list end
                    list[#list + 1] = rec
                end
            end
        end

        if #defs > 0 and not first then anyEarlier = true end
    end

    -- Our own frame, so UnregisterAllEvents is the right call here: the one-way-door
    -- objection applies to Blizzard's frames, whose registrations nothing can enumerate.
    self._evt:UnregisterAllEvents()
    for event in pairs(self._byEvent) do
        pcall(self._evt.RegisterEvent, self._evt, event)
    end

    syncTicker()
    self:_sizeSections()
end

function Bar:_onEvent(event)
    local list = self._byEvent[event]
    if not list then return end
    for i = 1, #list do self:_refresh(list[i]) end
end

---------------------------------------------------------------------------
-- Theme and teardown
---------------------------------------------------------------------------

function Bar:ApplyTheme()
    local T = SuuUI.Theme
    -- Re-derives the plate's thickness from borderWidth and re-resolves all three glass
    -- colours, which is the only way a token edit reaches a surface built from textures —
    -- there is no backdrop here for Theme:ApplyToFrame to repaint.
    self._glass:Refresh()

    local c = T:GetToken("colorBorder")
    if c then self._edge:SetColorTexture(c[1], c[2], c[3], c[4]) end
    self._edgeProps.height = SuuUI.Pixel.Line(T:GetToken("borderWidth") or 1)

    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        self._groups[name]:SetGap(T:GetToken("spaceXxs") or 2)
    end

    -- Fields are their own theme listeners, but the bar's height comes from the same tokens
    -- and a taller row has to re-place the bar and re-publish its height.
    local h = self:GetBarHeight()
    for _, rec in ipairs(self._records) do
        if not rec.custom and rec.field.SetSize then
            rec.field:GetFrame():SetHeight(h)
        end
    end

    self._box:Layout()
    self:_place()
    self:_sizeSections()
end

function Bar:Destroy()
    SuuUI.DataBar:Unsubscribe(OWNER)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    -- The narrow form, deliberately. self._root is the UI ROOT CONTAINER — one object shared
    -- by the whole addon — so DisconnectAll here would silently drop every other subscriber
    -- tracking the root's size. Nothing else subscribes to it today, which is exactly why
    -- this would have stayed invisible until something did.
    if self._rootConn then
        SuuUI.UISignals:Disconnect(self._root, SuuUI.UISignals.SIGNALS.SIZE_CHANGED,
            self._rootConn)
        self._rootConn = nil
    end

    self:_clearFields()
    self._evt:UnregisterAllEvents()
    self._evt:SetScript("OnEvent", nil)

    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        self._groups[name]:Destroy()
    end
    -- Before the bar's own box: the plate's pieces are textures on this frame laid out by a
    -- container of Glass's own, so it owns that container's teardown and we own ours.
    self._glass:Destroy()
    self._box:Destroy()
    SuuUI.UIRoot:RemoveElement(self._f)
    self._f:Hide()

    -- Back to nothing occupying the top of the screen, which is what restores whatever
    -- moved down for us.
    SuuUI.DataBar:SetOccupiedHeight(0)
end

function Bar:GetFrame() return self._f end
function Bar:GetSection(name) return self._groups[name] end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- Creates the data bar and subscribes it to the widget registry.
-- @param parent frame  The UI root container's frame
-- @return table  Bar handle
function Bar:Create(parent)
    local T = SuuUI.Theme
    local S = SuuUI.UISignals
    local root = SuuUI.UIRoot:GetRootContainer()

    -- NO BackdropTemplate. The surface is a Glass plate, which is drawn from textures, and a
    -- backdrop under it would paint one flat opaque colour across the gradient and defeat the
    -- whole thing. Leaving the template on the frame would leave `Backdrop.Apply` available to
    -- whoever reads this next, which is exactly how the gradient would silently die.
    local f = CreateFrame("Frame", "SuuUI_data_bar_bar", parent)
    -- Deliberately no EnableMouse: the strip spans the screen, and a bar that swallowed
    -- clicks would make the top of the world unclickable. Each field enables its own.
    f:SetSize(root:GetWidth() or 100, T:GetControlHeight("sizeRow"))

    -- THE GLASS PLATE, and it is built HERE — before the box below adopts the frame. Glass lays
    -- its pieces out with a HOST CONTAINER of its own and installs its own OnSizeChanged, and a
    -- host container CHAINS onto whatever resize script is already installed. Built after the
    -- box, its hook would be the one chained FROM rather than TO and the plate would keep
    -- whatever size the bar had at construction — the documented trap in LAYOUT_SYSTEM.md, and
    -- the reason a 219-unit window once wore a 411x546 glass body. It also has to go on before
    -- any CHILD is added, so the gradient sits under the fields rather than over them.
    --
    -- ORIENTATION IS THE DEFAULT, and deliberately identical to Components/ActionBarGrid.lua:
    -- `from` is the DENSE end and it is the TOP, fading to `colorGlassFade` at the bottom. The
    -- chat wash is the inverted one (it swaps the pair, because a log fills upward); a bar
    -- pinned to the top of the screen wants its ink against that edge, dissolving downward into
    -- the world. Sharing the action bars' tokens is the POINT rather than a coupling to regret:
    -- the two plates are one treatment, so a retint must move both.
    --
    -- inset = 0 for the same reason the flat backdrop passed it: with `border = false` the inset
    -- would still default to the border width, leaving a one-pixel transparent gap around the
    -- whole strip that nothing draws into.
    local glass = SuuUI.Backdrop.Glass(f, {
        from = "colorGlass", to = "colorGlassFade", sheen = "colorGlassSheen",
        -- No border: a full-width strip framed on all four sides reads as a floating panel
        -- rather than as part of the screen edge. The bar keeps its own bottom hairline below,
        -- which a backdrop edge could not draw on one side either.
        border = false, inset = 0,
    })

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local self = setmetatable({
        _f          = f,
        _box        = box,
        _glass      = glass,
        _root       = root,
        _records    = {},
        _dividers   = {},
        _byEvent    = {},
        _groups     = {},
        _groupProps = {},
        _eid        = "databar_bar",
        _anchor     = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0 },
    }, Bar)

    local edge = f:CreateTexture(nil, "ARTWORK")
    local edgeProps = { valign = "end", height = SuuUI.Pixel.Line(T:GetToken("borderWidth") or 1) }
    box:Add(edge, edgeProps)
    self._edge, self._edgeProps = edge, edgeProps

    -- start / center / end on one stack box. A single flow cannot express "three groups, one
    -- at each end and one centred" — flow has no main-axis distribution — and three stack
    -- children each aligned to their own edge says it directly.
    local aligns = { left = "start", center = "center", right = "end" }
    for _, name in ipairs(SuuUI.DataBar.SECTIONS) do
        local group = SuuUI.Layout:CreateContainer({
            parent = f, layout = "flow", dir = "horizontal",
            gap = T:GetToken("spaceXxs") or 2, align = "center",
        })
        local props = { align = aligns[name], valign = "stretch", width = 0 }
        box:Add(group, props)
        self._groups[name]     = group
        self._groupProps[name] = props
    end

    self._evt = CreateFrame("Frame")
    self._evt:SetScript("OnEvent", function(_, event) self:_onEvent(event) end)

    -- Player-facing content, stated through the layer system so a settings window or a modal
    -- is guaranteed to draw over it.
    SuuUI.UIRoot:AddElement(f, "normal", self._anchor)

    -- The bar spans the screen, so it tracks the root container rather than being sized once.
    -- The id is kept: the root container is shared, so teardown must drop this one connection
    -- and not every subscriber of that object.
    self._rootConn = S:Connect(root, S.SIGNALS.SIZE_CHANGED, function() self:_place() end)

    self:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() self:ApplyTheme() end, self._eid)

    -- Subscribing builds the fields: the callback fires immediately with whatever is already
    -- registered, and again for every plugin that registers later. There is no separate
    -- initial build to keep in step with it.
    SuuUI.DataBar:Subscribe(function() self:Rebuild() end, OWNER)

    return self
end

SuuUI._DataBar.Bar = Bar
