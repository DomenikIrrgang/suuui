-- Static tooltip skinning: the backdrop, Blizzard's own border, and the fonts.
--
-- Everything here is a HOOK or a call on a Blizzard frame. That is the sanctioned carve-out
-- (WOW_API_ENCAPSULATION.md, "Repositioning A Blizzard Frame"): a tooltip is not our UI, it
-- cannot be adopted into one of our containers without tainting it, so the layout engine has
-- no way to reach it at all.
--
-- NOTHING HERE NEEDS A COMBAT GUARD. GameTooltip is not a protected frame and its backdrop is
-- not a protected method -- ElvUI restyles tooltips unconditionally with no taint comment and
-- no InCombatLockdown check anywhere in its tooltip path. Do not add one: it would imply a
-- constraint that does not exist, and mutation testing would show it unreachable.
local type, next, pcall = type, next, pcall

local M = {}

-- Which frames get skinned. MEASURED on this client (interface 20504): every name below
-- resolved, so there are no dead entries -- but the list is still resolved at runtime rather
-- than assumed, because a client generation that renames one should lose that frame instead
-- of erroring.
--
-- Iterated with `next`, NEVER ipairs. A nil global leaves a hole in the array part, and ipairs
-- stops dead at the first hole -- silently dropping every frame after it. `next` skips holes.
local function tooltipFrames()
    return {
        _G.GameTooltip,
        _G.ItemRefTooltip,
        _G.ItemRefShoppingTooltip1,
        _G.ItemRefShoppingTooltip2,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
        _G.EmbeddedItemTooltip,
        _G.WorldMapTooltip,
        _G.FriendsTooltip,
        -- Not ours, but it is a tooltip on our own minimap button, and leaving it in
        -- Blizzard's skin next to a reskinned one reads as a bug.
        _G.LibDBIconTooltip,
    }
end

M.tooltipFrames = tooltipFrames

--- The background colour, with the plugin's alpha override applied.
--
-- colorBg already carries opacityPanel, so the setting REPLACES that alpha rather than
-- multiplying it -- a tooltip sits over the game world and the player wants one number to
-- turn, not a product of two.
local function bgColor()
    local c = SuuUI.Theme:GetToken("colorBg")
    local a = SuuUI.Settings:Get("tooltips", "backdrop_alpha")
    if type(c) == "table" and type(a) == "number" then
        return { c[1], c[2], c[3], a }
    end
    return "colorBg"
end

M.bgColor = bgColor

-- Which frames this module has successfully given a SuuUI surface to. Signal.lua reads it:
-- colouring the border of a frame we never skinned would call SetBackdropBorderColor on a
-- frame that has no backdrop, which RAISES rather than returning false.
local skinned = {}

M.skinned = skinned

--- Whether this frame currently carries SuuUI's surface.
function M.IsSkinned(tt) return skinned[tt] == true end

--- Applies SuuUI's surface to one tooltip frame.
--
-- The signature matches Blizzard's own SharedTooltip_SetBackdropStyle(tooltip, style, embedded)
-- so this function can be used directly as the hook handler for it.
-- @param tt frame
-- @param _ any    Blizzard's `style` argument, unused
-- @param isEmbedded bool
-- @return bool  whether the frame was skinned
function M.Style(tt, _, isEmbedded)
    if type(tt) ~= "table" then return false end
    -- An embedded tooltip is drawn INSIDE another one, so giving it its own surface puts a
    -- second panel and a second border inside the first.
    if isEmbedded or tt.IsEmbedded then return false end
    if type(tt.IsForbidden) == "function" and tt:IsForbidden() then return false end

    -- Blizzard's tooltips ARE backdrop frames here, but not every frame in the list is
    -- guaranteed to be on every client generation -- and SetBackdrop on a frame that was not
    -- created for one RAISES rather than returning false, so "the method exists" is not a
    -- sufficient test. ElvUI solves this by mixing the template in when it is missing; the same
    -- move, then skip the frame if it still cannot take one.
    if type(tt.SetBackdrop) ~= "function"
       and type(_G.Mixin) == "function" and type(_G.BackdropTemplateMixin) == "table" then
        pcall(_G.Mixin, tt, _G.BackdropTemplateMixin)
    end
    if type(tt.SetBackdrop) ~= "function" then return false end

    -- Blizzard's border on this client is a NINESLICE, measured present in Phase 0 against an
    -- earlier guess that it was absent. SetBackdrop alone leaves it drawing underneath ours and
    -- the player sees a double frame, so hiding it is mandatory rather than defensive.
    if tt.NineSlice and type(tt.NineSlice.SetAlpha) == "function" then
        tt.NineSlice:SetAlpha(0)
    end
    -- The separator textures a comparison tooltip draws between sections.
    for _, name in next, { "Delimiter1", "Delimiter2" } do
        local d = tt[name]
        if d and type(d.SetTexture) == "function" then d:SetTexture(nil) end
    end

    -- Through pcall for the same reason the mixin above exists: a frame that turns out not to
    -- accept a backdrop must cost a debug line, not a broken login. This runs during the
    -- PLAYER_LOGIN pass.
    local ok, err = pcall(SuuUI.Backdrop.Apply, tt, { bg = bgColor(), border = "colorBorder" })
    if not ok then
        skinned[tt] = nil
        SuuUI.Debug("tooltips: backdrop refused on "
            .. ((type(tt.GetName) == "function" and tt:GetName()) or "?")
            .. ": " .. tostring(err))
        return false
    end

    skinned[tt] = true
    return true
end

--- Re-skins every frame in the list. Cheap, and safe to call repeatedly.
-- @return number  how many frames were skinned
function M.StyleAll()
    local n = 0
    for _, tt in next, tooltipFrames() do
        if M.Style(tt) then n = n + 1 end
    end
    return n
end

--- Forgets what was skinned, for teardown.
function M.Forget()
    for tt in next, skinned do skinned[tt] = nil end
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------

-- The three Font OBJECTS every tooltip FontString inherits from. Assigning these covers
-- tooltip lines THAT DO NOT EXIST YET, which is the whole reason to do it this way: the client
-- creates line objects on demand, so a GameTooltipTextLeft1..N walk would have to be redone on
-- every show, forever. SuuUI's font registry drives SetFont per FontString elsewhere, which is
-- what makes that walk the tempting shape here -- resist it.
local FONT_OBJECTS = {
    { global = "GameTooltipText",       sizeKey = "font_size" },
    { global = "GameTooltipHeaderText", sizeKey = "header_font_size" },
    { global = "GameTooltipTextSmall",  sizeKey = "comparison_font_size" },
}

M.FONT_OBJECTS = FONT_OBJECTS

--- Sets one font object's face and size.
--
-- Through pcall because SetFont RAISES on an asset the client cannot load rather than
-- returning false, and an unguarded call has already unwound out of a PLAYER_LOGIN handler
-- once in this codebase. The path is resolved through Fonts:Path first, which is what makes a
-- theme naming a face by NAME (rather than by path) work at all.
local function setFont(obj, path, size)
    if type(obj) ~= "table" or type(obj.SetFont) ~= "function" then return false end
    if type(path) ~= "string" or type(size) ~= "number" then return false end
    local ok = pcall(obj.SetFont, obj, path, size, "")
    if not ok then SuuUI.Debug("tooltips: SetFont refused " .. tostring(path)) end
    return ok
end

--- Applies the theme's face and the plugin's sizes to all three font objects.
-- @return number  how many were set
function M.ApplyFonts()
    local T    = SuuUI.Theme
    local path = SuuUI.Fonts:Path(T:GetTokenRaw("fontFamilyMain") or T:GetToken("fontFamilyMain"))
    local n = 0
    for _, spec in next, FONT_OBJECTS do
        local size = SuuUI.Settings:Get("tooltips", spec.sizeKey)
        if setFont(_G[spec.global], path, size) then n = n + 1 end
    end
    return n
end

SuuUI._Tooltips = SuuUI._Tooltips or {}
SuuUI._Tooltips.Skin = M
