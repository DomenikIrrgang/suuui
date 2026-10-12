-- UI/ActionButton.lua
-- One action slot on a bar: SuuUI's own secure button (no Blizzard button
-- template), drawn as the design's ActionButton.
--
--   local b = UI.ActionButton(header, "SuuUIActionBar1Button1", "action")
--   b:SetSlot(slot)       -- which action slot the art shows (Lua side)
--   b:SetHotkey("S1")     -- the key binding text ("" for none)
--
-- The secure side (the "action" attribute, paging, clicks, drag and drop) is
-- set up by UI.ActionBar; this file only draws. The art lives on a plain
-- child frame (the face), so nothing here touches the protected button.
--
-- States, from the design:
--   ready        full colour on surface-raised, gilt-hairline border
--   casting /    ink border and a 1px ink ring 3px inside (a stance, form,
--   active       aura or auto attack that is on)
--   cooldown     desaturated, the sweep from a duration object, whole
--                seconds then minutes in micro; coming off cooldown pops
--   outOfRange   an ember veil over the art, the key in ember-text
--   unusable     desaturated at opacity-disabled
-- Hover brightens the border to gilt; a press moves the face 1px down.
-- Cooldown timing is secret in combat: the sweep and digits come from the
-- engine's duration object, and only isActive (readable) is ever tested.

local _, ns = ...

local UI, T, Motion = ns.UI, ns.Tokens, ns.Motion
local S = T.space

local CROP = 0.08
local isSecret = issecretvalue or function() return false end

-- A value addon code can read, or the fallback when it is secret or missing.
local function known(v, fallback)
    if isSecret(v) or v == nil then return fallback end
    return v
end

local AB = {}

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function AB:SetHotkey(text)
    self.hotkeyText = text or ""
    self.hotkey:SetText(self.hotkeyText)
    self:UpdateHotkey()
end

function AB:SetHotkeyShown(shown)
    self.hotkeyShown = shown and true or false
    self:UpdateHotkey()
end

function AB:UpdateHotkey()
    local show = self.hotkeyShown and self.hotkeyText ~= "" and self.hasAction
    self.hotkey:SetShown(show and true or false)
    self.hotkey:SetTextColor(UI.RGBA(self.outOfRange and "ember-text" or "ink-muted"))
end

-- The border: a state's colour, gilt while hovered, the hairline at rest.
function AB:UpdateBorder()
    local token = "gilt-hairline"
    if self.active then token = "ink"
    elseif self.hover then token = "gilt" end
    self.border:SetColor(token)
end

function AB:SetSlot(slot)
    if self.slot == slot then return end
    local old = self.slot
    self.slot = slot
    if self.onSlotChanged then self.onSlotChanged(self, old, slot) end
    -- A new slot starts without the old one's cooldown: a paging bar 1 would
    -- otherwise pop "ready" on every page whose slot isn't cooling down.
    self.coolingDown = false
    Motion.AlphaTo(self.flash, 0, 0)
    self:Update()
end

function AB:Update()
    local slot = self.slot
    self.hasAction = slot ~= nil and HasAction(slot) or false
    if self.hasAction then
        self.art:SetTexture(GetActionTexture(slot))
        self.art:Show()
    else
        self.art:Hide()
        self.cooldown:Clear()
        self.coolingDown = false
        self.outOfRange = false
    end
    self:UpdateCount()
    self:UpdateCooldown()
    self:UpdateUsable()
    self:UpdateActive()
    self:UpdateHotkey()
    self:UpdateEmpty()
end

-- An empty slot shows only while you drag something (or with showEmpty).
function AB:SetGrid(on)
    self.grid = on and true or false
    self:UpdateEmpty()
end

function AB:UpdateEmpty()
    local alpha = 1
    if not self.hasAction then
        alpha = (self.grid or self.showEmpty) and 1 or 0
    elseif self.unusable then
        alpha = T.opacity["opacity-disabled"]
    end
    self.face:SetAlpha(alpha)
end

function AB:UpdateCount()
    -- The display count may be secret: it goes to SetText untouched.
    local text = self.hasAction and C_ActionBar and C_ActionBar.GetActionDisplayCount
        and C_ActionBar.GetActionDisplayCount(self.slot) or ""
    self.count:SetText(text)
end

-- Draws a cooldown from any source: whether it runs, whether it is only the
-- global cooldown, and the engine's duration object (secret-safe).
function AB:ShowCooldown(active, gcd, duration)
    if active then
        if duration then self.cooldown:SetCooldownFromDurationObject(duration) end
        -- The global cooldown sweeps but shows no digits and keeps the colour.
        self.cooldown:SetHideCountdownNumbers(gcd and true or false)
    else
        self.cooldown:Clear()
    end
    local real = active and not gcd
    if self.coolingDown and not active then
        -- Off cooldown: the ready pop and an arcane flash on the border.
        Motion.Pop(self.face)
        self.flash:SetAlpha(1)
        Motion.AlphaTo(self.flash, 0, T.duration["dur-slow"])
    end
    self.coolingDown = real and true or false
    self:UpdateArt()
end

function AB:UpdateCooldown()
    if not self.hasAction then return end
    local slot = self.slot
    local info = C_ActionBar.GetActionCooldown and C_ActionBar.GetActionCooldown(slot)
    local active = info and known(info.isActive, false) or false
    local gcd = info and known(info.isOnGCD, false) or false
    local d = active and C_ActionBar.GetActionCooldownDuration and C_ActionBar.GetActionCooldownDuration(slot)
    self:ShowCooldown(active, gcd, d or nil)
end

-- A spell's cooldown (stance and pet buttons).
function AB:ShowSpellCooldown(spellID)
    local info = spellID and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    local active = info and known(info.isActive, false) or false
    local gcd = info and known(info.isOnGCD, false) or false
    local d = active and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
    self:ShowCooldown(active, gcd, d or nil)
end

function AB:ShowUsable(unusable)
    self.unusable = unusable and true or false
    self:UpdateArt()
    self:UpdateEmpty()
end

function AB:ShowActive(on)
    self.active = on and true or false
    self.ring:SetShown(self.active)
    self:UpdateBorder()
end

-- A new button size (out of combat: the button is secure).
function AB:Resize(px)
    if self:GetWidth() == px then return end
    self:SetSize(px, px)
    if self.dashes then
        for _, t in ipairs(self.dashes) do t:Hide() end
        self.dashes = nil
        if self.autocastOn then self:ShowAutocast(true) end
    end
end

-- Pet abilities the pet uses by itself: a dashed ink ring inside the border.
function AB:ShowAutocast(on)
    self.autocastOn = on and true or false
    if not self.dashes then
        if not on then return end
        self.dashes = {}
        local inset, dash, step = 2, 2, 4
        local size = self:GetWidth() - inset * 2
        local function add(horizontal, offset, edge)
            for pos = 0, size - dash, step do
                local t = self.over:CreateTexture(nil, "OVERLAY", nil, 2)
                t:SetColorTexture(UI.RGBA("ink"))
                if horizontal then
                    t:SetSize(dash, 1)
                    t:SetPoint(edge, self, edge == "TOPLEFT" and "TOPLEFT" or "BOTTOMLEFT", inset + pos, offset)
                else
                    t:SetSize(1, dash)
                    t:SetPoint(edge, self, edge == "TOPLEFT" and "TOPLEFT" or "TOPRIGHT", offset, -(inset + pos))
                end
                self.dashes[#self.dashes + 1] = t
            end
        end
        add(true, -inset, "TOPLEFT")
        add(true, inset, "BOTTOMLEFT")
        add(false, inset, "TOPLEFT")
        add(false, -inset, "TOPRIGHT")
    end
    for _, t in ipairs(self.dashes) do t:SetShown(on and true or false) end
end

function AB:ShowTooltip()
    GameTooltip:SetAction(self.slot)
end

function AB:UpdateUsable()
    if not self.hasAction then
        self.unusable = false
        return self:UpdateEmpty()
    end
    local usable, noMana
    if C_ActionBar and C_ActionBar.IsUsableAction then
        usable, noMana = C_ActionBar.IsUsableAction(self.slot)
    else
        usable, noMana = IsUsableAction(self.slot)
    end
    -- Unknown reads as usable: never dim a spell on a value we can't see.
    self:ShowUsable(not known(usable, true) or known(noMana, false))
end

function AB:UpdateActive()
    local on = false
    if self.hasAction then
        on = UI.Flag(IsCurrentAction(self.slot)) or UI.Flag(IsAutoRepeatAction(self.slot))
    end
    self:ShowActive(on)
end

function AB:SetOutOfRange(out)
    out = (out and self.hasAction) and true or false
    if self.outOfRange == out then return end
    self.outOfRange = out
    self.veil:SetShown(out)
    self:UpdateArt()
    self:UpdateHotkey()
end

function AB:UpdateArt()
    local desat = 0
    if self.coolingDown or self.unusable then desat = 1
    elseif self.outOfRange then desat = 0.6 end
    self.art:SetDesaturation(desat)
    local v = self.coolingDown and 0.7 or 1
    self.art:SetVertexColor(v, v, v)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- Short key names, so a binding fits a 20px button: S1, C2, A3, M4, WU.
local KEY_SHORT = {
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "⌘" },
    { "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" }, { "MIDDLEMOUSE", "M3" },
    { "BUTTON", "M" }, { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" },
    { "NUMPADMULTIPLY", "N*" }, { "NUMPADDIVIDE", "N/" }, { "NUMPADDECIMAL", "N." },
    { "NUMPAD", "N" }, { "SPACE", "Sp" }, { "BACKSPACE", "Bs" }, { "CAPSLOCK", "Cp" },
    { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" }, { "INSERT", "Ins" }, { "DELETE", "Del" },
    { "HOME", "Hm" }, { "END", "End" }, { "ESCAPE", "Esc" }, { "ENTER", "Ent" }, { "TAB", "Tab" },
}

function UI.ShortKey(key)
    if not key or key == "" then return "" end
    for _, r in ipairs(KEY_SHORT) do key = key:gsub(r[1], r[2]) end
    return key
end

-- The text on buttons (key binding, count, cooldown digits): micro by
-- default, never smaller (micro is the floor), with a thin dark outline so
-- it reads on any icon art (as the aura digits do).
local MICRO = T.type["micro"]
local digitFonts = {}

local function digitFont(px)
    local key = math.floor(px * 10 + 0.5)
    if not digitFonts[key] then
        local name = "SuuUIActionDigits" .. key
        CreateFont(name):SetFont(MICRO.file, px, "OUTLINE")
        digitFonts[key] = name
    end
    return digitFonts[key]
end

function AB:SetTextSize(px)
    px = math.max(MICRO.size, px or MICRO.size)
    if self.textSize == px then return end
    self.textSize = px
    self.hotkey:SetFont(MICRO.file, px, "OUTLINE")
    self.count:SetFont(MICRO.file, px, "OUTLINE")
    if self.cooldown.SetCountdownFont then pcall(self.cooldown.SetCountdownFont, self.cooldown, digitFont(px)) end
end

-- Every SuuUI action button at once.
function UI.SetActionTextSize(px)
    UI.actionTextSize = px
    for _, b in ipairs(UI.actionButtons) do b:SetTextSize(px) end
end

-- Every action button made, for keybind mode (each bar sets b.bindCommand,
-- the game's binding command, and b.bindLabel, a name people read).
UI.actionButtons = {}

function UI.ActionButton(parent, name, size)
    local px = UI.Size(size or "action")
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    Mixin(b, AB)
    UI.actionButtons[#UI.actionButtons + 1] = b
    b:SetSize(px, px)
    b.hotkeyText, b.hotkeyShown = "", true

    -- Everything visible sits on the face, a plain child frame.
    local face = CreateFrame("Frame", nil, b)
    face:SetAllPoints()
    b.face = face
    UI.Fill(face, "surface-raised"):SetAllPoints()
    b.art = face:CreateTexture(nil, "ARTWORK")
    b.art:SetPoint("TOPLEFT", 1, -1)
    b.art:SetPoint("BOTTOMRIGHT", -1, 1)
    b.art:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)

    b.veil = face:CreateTexture(nil, "ARTWORK", nil, 2)
    b.veil:SetAllPoints(b.art)
    b.veil:SetColorTexture(UI.RGBA("ember", 0.4))
    b.veil:Hide()

    b.cooldown = CreateFrame("Cooldown", nil, face, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.art)
    b.cooldown:SetDrawEdge(false)
    b.cooldown:SetDrawBling(false)
    b.cooldown:SetSwipeColor(0, 0, 0, 0.7)
    b.cooldown:SetHideCountdownNumbers(false)
    if b.cooldown.SetCountdownFont then pcall(b.cooldown.SetCountdownFont, b.cooldown, "SuuUIFont_micro") end
    b.cooldown:HookScript("OnCooldownDone", function() b:UpdateCooldown() end)

    -- Text, rings and the border over the sweep.
    local over = CreateFrame("Frame", nil, face)
    b.over = over
    over:SetAllPoints()
    over:SetFrameLevel(b.cooldown:GetFrameLevel() + 2)
    b.border = UI.Border(over, "gilt-hairline", { layer = "OVERLAY" })
    b.ring = UI.Border(over, "ink", { inset = 3, layer = "OVERLAY" })
    b.ring:SetShown(false)
    b.flash = over:CreateTexture(nil, "OVERLAY", nil, 3)
    b.flash:SetAllPoints()
    b.flash:SetColorTexture(UI.RGBA("arcane", 0.35))
    b.flash:SetAlpha(0)

    b.hotkey = over:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(b.hotkey, "micro")
    b.hotkey:SetShadowColor(0, 0, 0, 1)
    b.hotkey:SetShadowOffset(0, -1)
    b.hotkey:SetPoint("TOPLEFT", 2, 0)
    b.hotkey:SetJustifyH("LEFT")

    b.count = over:CreateFontString(nil, "OVERLAY")
    ns.Fonts.Apply(b.count, "micro")
    b.count:SetShadowColor(0, 0, 0, 1)
    b.count:SetShadowOffset(0, -1)
    b.count:SetPoint("BOTTOMRIGHT", -1, 0)
    b.count:SetJustifyH("RIGHT")

    -- Hover, press and the game's tooltip for the slot.
    b:HookScript("OnEnter", function(self)
        self.hover = true
        self:UpdateBorder()
        if self.hasAction and not (GameTooltip:IsForbidden()) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            self:ShowTooltip()
            -- A note from the bar, e.g. the page bar 1 is on.
            if self.tooltipNote then GameTooltip:AddLine(self.tooltipNote, UI.RGBA("ink-muted")) end
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function(self)
        self.hover = false
        self:UpdateBorder()
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    b:HookScript("OnMouseDown", function(self) self.face:SetPoint("TOPLEFT", 0, -1); self.face:SetPoint("BOTTOMRIGHT", 0, -1) end)
    b:HookScript("OnMouseUp", function(self) self.face:SetAllPoints() end)

    b:SetTextSize(UI.actionTextSize)
    b:SetGrid(false)
    return b
end
