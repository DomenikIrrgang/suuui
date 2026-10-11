-- UI/Text.lua
-- Text in a design text style and token colour.
--
--   local t = UI.Text(parent, "label", "ink")
--   t:SetValue(value)    secret values go straight to the engine; readable
--                        ones are compared first, so an unchanged text costs nothing
--   t:SetStyle("caption"), t:SetColor("ink-muted"), t:SetShadowed(true)
--   t:SetVisible(shown)  Show/Hide that tells the layout only when it changes
--
-- A text whose value may be secret can't be measured in code: give it a
-- fixed width (t:SetFixedWidth(w)) when it sits in a layout.

local _, ns = ...

local UI = ns.UI
local isSecret = issecretvalue or function() return false end

local Text = {}

function Text:SetStyle(style)
    ns.Fonts.Apply(self, style)
    self.style = style
    self:Changed()
end

function Text:SetColor(r, g, b, a)
    if type(r) == "string" then r, g, b, a = UI.RGBA(r, g) end
    self:SetTextColor(r, g, b, a)
end

function Text:SetValue(v)
    if isSecret(v) then
        self.value = nil
        self:SetText(v)
        self:Changed()
        return
    end
    if v == self.value then return end
    self.value = v
    self:SetText(v)
    self:Changed()
end

-- The shadow every label straight on the world carries (0 1px 2px black, 90%).
function Text:SetShadowed(on)
    if on then
        self:SetShadowColor(0, 0, 0, 0.9)
        self:SetShadowOffset(0, -1)
    else
        self:SetShadowOffset(0, 0)
    end
end

function Text:SetFixedWidth(w)
    self.fixedWidth = w
    self:SetWidth(w)
    self:Changed()
end

function Text:SetVisible(shown)
    shown = shown and true or false
    if shown == self:IsShown() then return end
    self:SetShown(shown)
    self:Changed()
end

function Text:Changed()
    if self.layout then self.layout:Invalidate() end
end

function UI.Text(parent, style, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Mixin(fs, Text)
    fs:SetWordWrap(false)
    fs:SetStyle(style or "body")
    fs:SetColor(color or "ink")
    return fs
end
