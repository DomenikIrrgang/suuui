local S = SuuUI.UISignals

local DivMeta = {}
DivMeta.__index = DivMeta

function DivMeta:SetEnabled()   end

function DivMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._labelText then self._labelText:Destroy() end
    self._box:Destroy()
end

--- Sets the divider's label text.
-- @param text string
function DivMeta:SetText(text)
    if self._labelText then
        self._labelText:SetText(text)
        -- This label is centred, so its width is its own rather than assigned by the
        -- layout, and Text only emits SIZE_CHANGED when its *height* changes. New text
        -- of the same height is therefore invisible to the box: re-run it by hand or the
        -- client keeps the previous string's width and clips. Adding the handle instead
        -- of the region would not help here, for the same reason.
        self._box:Layout()
        S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
    end
end

function DivMeta:ApplyTheme()
    local c = SuuUI.Theme:GetToken("colorBorder")
    if c then self._line:SetColorTexture(c[1], c[2], c[3], c[4]) end
    if self._labelText then
        -- Applied here rather than left to Text's own subscription: the bus fires
        -- listeners newest-first, so the divider would otherwise lay out against the
        -- previous font. The centred label owns its width, so re-run the box by hand.
        self._labelText:ApplyTheme()
        self._box:Layout()
    end
end

-- Fills in GetWidth, GetHeight, IsShown, GetFrame, SetSize, Show, Hide.
SuuUI.Components.InstallBase(DivMeta, "_f")

--- Creates a horizontal or vertical divider line.
-- Emits SIZE_CHANGED, VISIBILITY_CHANGED, TEXT_CHANGED.
-- @param props table  { dir, label, w, h }  dir: "horizontal"|"vertical"
-- @param parent frame
-- @return table  Divider handle
function SuuUI.Components.Divider(props, parent)
    local vertical = props.dir == "vertical"
    local thickness = SuuUI.Theme:GetToken("borderWidth") or 1
    local w = props.w or (vertical and thickness or 200)
    local h = props.h or (vertical and 20 or thickness)

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)

    -- Registered before the host container adopts the frame so the container chains
    -- onto this hook. A parent layout resizes the frame directly, never via SetSize.
    local handle
    f:SetScript("OnSizeChanged", function(_, w2, h2)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w2, h2)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- The line spans one axis and is centred on the other
    local line = f:CreateTexture(nil, "ARTWORK")
    if vertical then
        box:Add(line, { align = "center", width = thickness })
    else
        box:Add(line, { valign = "center", height = thickness })
    end

    -- Text owns the font and colour tokens and re-measures on a token change, which a
    -- hand-rolled font string does not.
    local labelText
    if props.label and props.label ~= "" then
        labelText = SuuUI.Components.Text({ text = props.label, size = "sm",
                                            color = "muted", justify = "CENTER" }, f)
        box:Add(labelText:GetFrame(), { align = "center", valign = "center" })
    end

    local id = "div_" .. tostring(f)
    handle = setmetatable({
        _f     = f,
        _line  = line,
        -- _label stays the font string so callers and specs reach the same region.
        _label = labelText and labelText:GetFrame() or nil,
        _labelText = labelText,
        _box   = box,
        _eid   = id,
    }, DivMeta)
    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
