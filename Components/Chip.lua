-- A small rounded label: the resting channel indicator, the label inside the input field, and a
-- per-row channel tag. Composed from Backdrop.Pill and Components.Text -- a backdrop's corners
-- are square by construction, so a rounded surface has to go through the Pill primitive.
--
-- Its colour is a LITERAL as often as a token, because a channel's colour comes from
-- ChatTypeInfo -- a game fact, not a theme decision. A retint of the theme must not make SuuUI
-- disagree with the rest of the player's UI about what guild chat looks like.
local S = SuuUI.UISignals

local ChipMeta = {}
ChipMeta.__index = ChipMeta

--- Sets the label. Case is the CALLER's choice: WoW has no text-transform, so a chip that wanted
--- to shout would have to be handed a shouting string.
function ChipMeta:SetText(text)
    text = text or ""
    if text == self._text then return end
    self._text = text
    self._label:SetText(text)
    self:_autosize()
    S:Emit(self, S.SIGNALS.TEXT_CHANGED, text)
end

function ChipMeta:GetText() return self._text end

--- @param color table|string  a literal {r,g,b,a} or a token key
function ChipMeta:SetColor(color)
    self._color = color
    self:_paint()
end

local function resolve(color)
    if type(color) == "string" then return SuuUI.Theme:GetToken(color) end
    if type(color) == "table" then return color end
    return SuuUI.Theme:GetToken("colorText")
end

-- The surface is a NEUTRAL dark panel; only the RING and the TEXT carry the channel's colour.
--
-- A channel-tinted wash was the first build, straight off the mockup, and it fails for two
-- reasons the mockup could not show. Say's ChatTypeInfo colour is pure WHITE, so a wash of it
-- renders a light grey pill that reads as a BUTTON rather than a label -- measured from a
-- screenshot. And the mockup assumed a dark log panel behind the chip, which the frameless design
-- removed: over snow or daylight a pale wash has nothing to sit against.
--
-- A dark surface is legible over any world, and the channel still gets TWO signals -- ring and
-- label -- so nothing is lost by not tinting the fill.
--
-- There is deliberately no `outline` variant. `Backdrop.Pill` fakes its ring by drawing a SOLID
-- border-coloured pill on BACKGROUND and covering the middle with the bg on BORDER, so a
-- transparent bg does not hollow the ring out -- it reveals the whole border pill as a solid
-- shape. `outline` therefore rendered as its own opposite: the densest chip available. Its spec
-- passed throughout, because it asserted the fill layer's ALPHA rather than what the player sees.
-- SQUARE, not rounded. The chip was built on `Backdrop.Pill` and the concept shows no border radius
-- at all -- confirmed against the mockup after seeing it in game. A square surface is also the
-- simpler primitive here: `Apply` paints a real border, where `Pill` fakes its ring by drawing a
-- solid border-coloured pill and covering the middle, which is why a transparent fill could not
-- hollow it out.
function ChipMeta:_paint()
    local T = SuuUI.Theme
    local c = resolve(self._color) or { 1, 1, 1, 1 }
    local ring = T:GetToken("opacityChipBorder") or 0.40
    local B = SuuUI.Backdrop
    B.SetBg(self._f, "colorBg")
    B.SetBorder(self._f, { c[1], c[2], c[3], ring })
    -- A LITERAL colour, not a token key: a channel's colour is a game fact from ChatTypeInfo.
    self._labelText:SetColor({ c[1], c[2], c[3], 1 })
end

function ChipMeta:_autosize()
    if not self._autoSize then return end
    local T = SuuUI.Theme
    local padX = T:GetToken("spaceXs") or 4
    local w = SuuUI.TextMetrics.Box(self._text, SuuUI.Fonts:Path(T:GetToken("fontFamilyMain")),
        T:GetFontSize(self._sizeKey))
    local h = T:GetControlHeight("sizeControlSm", self._sizeKey)
    local target = SuuUI.Pixel.Ceil(w + padX * 2)
    if math.abs((self._f:GetWidth() or 0) - target) > 0.5
        or math.abs((self._f:GetHeight() or 0) - h) > 0.5 then
        self._f:SetSize(target, h)
    end
end

function ChipMeta:ApplyTheme()
    self._labelText:ApplyTheme()
    self:_paint()
    self:_autosize()
end

function ChipMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    self._labelText:Destroy()
    self._box:Destroy()
    self._f:Hide()
end

function ChipMeta:SetSize(w, h)
    self._autoSize = false
    self._f:SetSize(w, h)
end

SuuUI.Components.InstallBase(ChipMeta, "_f")

--- Creates a small rounded label.
-- Emits TEXT_CHANGED (text) and SIZE_CHANGED (w, h).
-- @param props table   { text, color, size }
-- @param parent frame
-- @return table  Chip handle
function SuuUI.Components.Chip(props, parent)
    props = props or {}
    local T = SuuUI.Theme

    -- A BackdropTemplate frame, because the surface IS a backdrop now: the chip is square, so the
    -- Pill primitive it used to need is gone along with the plain-Frame requirement that came with it.
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    SuuUI.Backdrop.Apply(f, { bg = "colorBg", border = "colorBorder" })

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box  = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    local sizeKey = props.size or "sm"
    local labelText = SuuUI.Components.Text({
        -- shadow: the chip sits over the game world behind only a translucent pill, which the
        -- concept's own `.ch` acknowledges with a text-shadow.
        text = props.text or "", size = sizeKey, justify = "CENTER", shadow = true,
    }, f)
    box:Add(labelText, { align = "center", valign = "center" })

    local id = "chip_" .. tostring(f)
    handle = setmetatable({
        _f = f, _box = box, _eid = id,
        _label = labelText:GetFrame(), _labelText = labelText,
        _text = props.text or "",
        _color = props.color,
        _sizeKey = sizeKey,
        _autoSize = true,
    }, ChipMeta)

    handle:ApplyTheme()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
