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
--                       borderWidth = number|nil }
function M.Apply(frame, opts)
    opts = opts or {}
    local bw = opts.borderWidth or SuuUI.Theme:GetToken("borderWidth") or 1
    frame:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = bw,
        insets   = { left = bw, right = bw, top = bw, bottom = bw },
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
