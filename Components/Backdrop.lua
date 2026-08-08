local type = type

local WHITE = "Interface\\Buttons\\WHITE8x8"

local M = {}

-- A colour argument is a token key, a literal {r,g,b,a}, or false/nil meaning
-- fully transparent. Several components deliberately want no bg or no border, and
-- that has to be a real 0,0,0,0 rather than "leave whatever was there".
local function resolveColor(value)
    local c = value
    if type(c) == "string" then c = SuuUI.Theme:GetToken(c) end
    if type(c) ~= "table" then return 0, 0, 0, 0 end
    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] == nil and 1 or c[4]
end

--- Applies the standard bg+border backdrop, resolving theme tokens.
-- @param frame frame  must be a BackdropTemplate frame
-- @param opts table   { bg = tokenKey|color|false, border = tokenKey|color|false,
--                       borderWidth = number|nil, inset = number|nil }
--   inset: how far the background sits inside the frame. Defaults to the border width so
--          a bordered surface does not paint under its own edge. Pass 0 for a borderless
--          surface that has to cover its whole box — otherwise its background is a pixel
--          smaller on every side than the frame, and anything drawn flush to the frame
--          (a bar fill) no longer lines up with it.
function M.Apply(frame, opts)
    opts = opts or {}
    -- Snapped to the pixel grid, with the grid step as the floor. A 1-unit border spans
    -- 1.4 pixels at 1080p on the default scale, which the rasteriser resolves as a grey
    -- smear rather than a line; Line() makes it exactly one pixel and never zero.
    local bw = SuuUI.Pixel.Line(opts.borderWidth or SuuUI.Theme:GetToken("borderWidth") or 1)
    local inset = opts.inset or bw
    frame:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = bw,
        insets   = { left = inset, right = inset, top = inset, bottom = inset },
    })
    M.SetBg(frame, opts.bg)
    M.SetBorder(frame, opts.border)
end

--- Sets only the background colour, leaving the backdrop table intact.
-- @param frame frame
-- @param tokenKeyOrColor string|table|false
function M.SetBg(frame, tokenKeyOrColor)
    frame:SetBackdropColor(resolveColor(tokenKeyOrColor))
end

--- Sets only the border colour, leaving the backdrop table intact.
-- @param frame frame
-- @param tokenKeyOrColor string|table|false
function M.SetBorder(frame, tokenKeyOrColor)
    frame:SetBackdropBorderColor(resolveColor(tokenKeyOrColor))
end

SuuUI.Backdrop = M
