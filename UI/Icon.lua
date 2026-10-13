-- UI/Icon.lua
-- The icon every spell, aura, cooldown and item slot is drawn with: Blizzard's
-- art cropped 8% on each edge, on a surface-sunk well, with a 1px border in a
-- state token (gilt-hairline at rest).
--
--   local icon = UI.Icon(parent, "icon-lg")   -- a size token or px
--   icon:SetArt(texture)
--   icon:SetState("rest" | "ready" | "dim" | "active")
--       ready: arcane border and glow; dim: grey and darkened (on cooldown,
--       unusable, no data); active: ink border
--   icon:SetBorder("dispel-poison")   -- a token, overriding the state's border
--   icon:SetCount(n)                  -- stack count, bottom right, micro
--   icon:Pop()                        -- the ready pop

local _, ns = ...

local UI, Motion = ns.UI, ns.Motion

local CROP = 0.08

local Icon = {}

function Icon:SetArt(texture)
    self.art:SetTexture(texture)
end

local STATE_BORDER = { rest = "gilt-hairline", ready = "arcane", dim = "gilt-hairline", active = "ink" }

function Icon:SetState(state)
    state = STATE_BORDER[state] and state or "rest"
    self.state = state
    local dim = state == "dim"
    self.art:SetDesaturated(dim)
    self.art:SetVertexColor(dim and 0.5 or 1, dim and 0.5 or 1, dim and 0.5 or 1)
    self.border:SetColor(self.borderToken or STATE_BORDER[state])
    self:SetGlow(state == "ready" and "glow-arcane" or nil)
end

function Icon:SetBorder(token)
    self.borderToken = token
    self.border:SetColor(token or STATE_BORDER[self.state or "rest"])
end

-- A shadow token ("glow-arcane", "glow-ember", "glow-ward") or nil for none.
function Icon:SetGlow(token)
    if self.glowToken == token then return end
    self.glowToken = token
    if self.glow then self.glow:SetShown(false) end
    if token then
        self.glows = self.glows or {}
        self.glows[token] = self.glows[token] or UI.Shadow(self, token)
        self.glow = self.glows[token]
        self.glow:SetShown(true)
    else
        self.glow = nil
    end
end

function Icon:SetCount(n)
    if not self.count then
        self.count = UI.Text(self, "micro", "ink")
        self.count:SetShadowed(true)
        self.count:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    self.count:SetValue(n and n ~= 0 and n ~= 1 and tostring(n) or "")
end

function Icon:Pop()
    Motion.Pop(self)
end

function UI.Icon(parent, size)
    local px = UI.Size(size or "icon-md")
    local f = CreateFrame("Frame", nil, parent)
    Mixin(f, Icon)
    f:SetSize(px, px)
    f.well = UI.Fill(f, "surface-sunk")
    f.well:SetAllPoints()
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.art:SetPoint("TOPLEFT", 1, -1)
    f.art:SetPoint("BOTTOMRIGHT", -1, 1)
    f.art:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    f.border = UI.Border(f, "gilt-hairline", { layer = "OVERLAY" })
    f:SetState("rest")
    return f
end
