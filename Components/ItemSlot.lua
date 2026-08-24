-- One bag slot: the icon, the stack count, a quality-coloured edge and a cooldown sweep.
--
-- WHY THIS INHERITS A BLIZZARD TEMPLATE, like StanceButton and unlike everything else.
--
-- USING an item from addon code is BLOCKED on this client. Measured 2026-08-24: calling
-- `C_Container.UseContainerItem(0, 1)` from tainted Lua returned true from pcall, left the stack
-- count unchanged, did not fire the item, and raised `*** ForceTaint_Strong *** has been blocked
-- from an action only available to the Blizzard UI`. Two installed addons corroborate the shape --
-- MRT builds a SecureActionButtonTemplate just to apply a weapon oil, and ElvUI creates its bag
-- cells from this very template rather than a plain Button.
--
-- MOVING items is a different story and is NOT blocked: `PickupContainerItem` was measured working
-- from the same tainted context, cursor and all. So the template is needed for USE, not for drag --
-- but since it supplies both, and pickup/place/split/use all live in its one OnClick, taking it
-- gives the whole interaction set for free.
--
-- NEVER SetScript("OnClick") ON THIS FRAME. That handler IS the mechanism. Replacing it yields a
-- cell that sizes, highlights, tooltips and reports as shown while doing nothing at all -- the
-- exact failure ActionButton shipped once with press-versus-release. Observe through PostClick.
--
-- BAG AND SLOT ARE POSITIONAL, and that is the property that makes this safe in combat. The slot is
-- this frame's own id; the BAG is its PARENT's id, which is how Blizzard's own containers are built
-- (ContainerFrame1 holds ContainerFrame1Item1..N). So both are stated once at construction and
-- NEVER re-pointed as contents change -- no SetAttribute churn, nothing the client can refuse
-- mid-fight. A cell that re-pointed itself when an item moved would fail exactly during combat,
-- which is when bags change most.
--
-- The parent's id is therefore part of this component's contract, and it is ASSERTED rather than
-- trusted: a cell parented to the wrong holder would quietly act on the wrong bag, which is an item
-- destroyed rather than a visual glitch.
--
-- THE CELL IS A RENDERER, NOT AN OBSERVER. It registers no events. Eighty cells each watching
-- BAG_UPDATE would be eighty dispatches for one change, so the grid that owns the container set
-- owns the event frame and calls Refresh. Same division ActionButton and its grid already use.
local CreateFrame, type, select = CreateFrame, type, select

local S = SuuUI.UISignals
local T = SuuUI.Theme

-- Quality at or above which the edge takes the item's colour. Below it the cell keeps the neutral
-- icon border, because a WHITE edge on a dark cell reads as a selected state rather than as
-- information -- the same threshold Plugins/Tooltips/Signal.lua settled on for the same reason.
local QUALITY_EDGE_FROM = 2

local ItemSlotMeta = {}
ItemSlotMeta.__index = ItemSlotMeta

-- Hides one of the template's own regions without caring what kind it is.
local function silence(region)
    if not region then return end
    if type(region.SetTexture) == "function" then region:SetTexture(nil) end
    if type(region.SetText) == "function" then region:SetText("") end
    if type(region.Hide) == "function" then region:Hide() end
end

--- The bag this cell belongs to, read from the PARENT's id -- the same place the template's own
--- handler reads it, so the two cannot disagree.
-- @return number|nil
function ItemSlotMeta:GetBag()
    local parent = self._f:GetParent()
    return parent and type(parent.GetID) == "function" and parent:GetID() or nil
end

--- The slot within that bag, read from this frame's id.
-- @return number
function ItemSlotMeta:GetSlot()
    return self._f:GetID()
end

--- Whether this cell currently holds anything.
-- @return bool
function ItemSlotMeta:HasItem()
    return self._info ~= nil
end

--- What this cell is showing, as the client's own table shape, or nil for an empty slot.
-- @return table|nil
function ItemSlotMeta:GetItem()
    return self._info
end

function ItemSlotMeta:_paintEdge()
    local info = self._info
    local q = info and info.quality
    -- Game facts, not theme tokens: an item's quality colour is what the client says it is, and the
    -- player already reads those five colours everywhere else in the game.
    if q and q >= QUALITY_EDGE_FROM then
        local c = SuuUI.Game:ItemQualityColor(q)
        if c then
            self._iconComp:SetBorderColor(c)
            return
        end
    end
    self._iconComp:SetBorderColor(nil)
end

function ItemSlotMeta:_paintCount()
    local info = self._info
    local n = info and info.stackCount or 0
    -- Only above one, exactly as AuraIcon does for stacks: the client reports 1 for a single item
    -- and a "1" on every occupied slot is noise rather than information.
    if n > 1 then
        self._countText:SetText(tostring(n))
        self._countText:Show()
    else
        self._countText:SetText("")
        self._countText:Hide()
    end
end

function ItemSlotMeta:_paintCooldown()
    local info = self._info
    if not (info and self._cooldown) then
        if self._cooldown then self._cooldown:SetCooldown(0, 0) end
        return
    end
    local bag, slot = self:GetBag(), self:GetSlot()
    local C = C_Container
    local get = (C and C.GetContainerItemCooldown) or GetContainerItemCooldown
    if type(get) ~= "function" or not bag then
        self._cooldown:SetCooldown(0, 0)
        return
    end
    local start, duration, enable = get(bag, slot)
    -- `enable` is a NUMBER here as it is on the action bars, and 0 means no cooldown. Testing
    -- truthiness would paint a permanent sweep over every item, since 0 is truthy in Lua.
    if start and duration and duration > 0 and (enable == nil or enable ~= 0) then
        self._cooldown:SetCooldown(start, duration)
    else
        self._cooldown:SetCooldown(0, 0)
    end
end

function ItemSlotMeta:_paintArt()
    local info = self._info
    -- Cleared rather than hidden, for the same reason ActionButton clears: hiding a region inside a
    -- frame the client considers protected is refused in combat, and an item appearing or vanishing
    -- mid-fight is the ordinary case.
    self._iconComp:SetIcon(info and info.iconFileID or nil)
    -- A LOCKED slot is one whose move is in flight. Dimming it is what stops a player queueing a
    -- second move onto a slot the server has not settled yet.
    local locked = info and info.isLocked
    self._iconComp:SetArtTint(nil, locked and (T:GetToken("opacityDisabled") or 0.4) or nil)
end

--- Paints this cell from a container info table, or empties it with nil.
--
-- Takes the table rather than reading the client itself, so the grid can read each slot once and
-- hand the result down -- eighty cells each calling GetContainerItemInfo would be eighty reads for
-- one pass.
-- @param info table|nil
function ItemSlotMeta:SetItem(info)
    self._info = info or nil
    self:_paintArt()
    self:_paintCount()
    self:_paintEdge()
    self:_paintCooldown()
end

--- Re-reads this slot from the client and repaints.
function ItemSlotMeta:Refresh()
    local bag, slot = self:GetBag(), self:GetSlot()
    if not (bag and slot) then return self:SetItem(nil) end
    local C = C_Container
    if C and type(C.GetContainerItemInfo) == "function" then
        return self:SetItem(C.GetContainerItemInfo(bag, slot))
    end
    local get = GetContainerItemInfo
    if type(get) ~= "function" then return self:SetItem(nil) end
    -- The legacy positional shape, normalised so the painters have ONE shape to read. Order from
    -- the shims three installed addons ship on this client.
    local icon, count, locked, quality, readable, lootable, link, filtered, noValue, id, bound =
        get(bag, slot)
    if not id and not link then return self:SetItem(nil) end
    self:SetItem({
        iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
        isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
        hasNoValue = noValue, itemID = id, isBound = bound,
    })
end

--- Whether this cell is a read-only view -- another character's bags, or your own cached bank.
-- @return bool
function ItemSlotMeta:IsReadOnly()
    return self._readOnly == true
end

--- Whether a read-only change is waiting for combat to end.
-- @return bool
function ItemSlotMeta:IsReadOnlyDeferred()
    return self._pendingReadOnly ~= nil
end

--- Makes this cell inert, or live again.
--
-- Dropping mouse input is a call the client REFUSES on a protected frame in combat, and this frame
-- is protected by construction. So a change during a fight is recorded and applied by the owner on
-- PLAYER_REGEN_ENABLED through ApplyPending -- attempting it and losing would cost the player an
-- "Interface action failed" line for a call we already knew would fail.
-- @param on bool
function ItemSlotMeta:SetReadOnly(on)
    on = on and true or false
    if self._readOnly == on then
        self._pendingReadOnly = nil
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self._pendingReadOnly = on
        return
    end
    self._pendingReadOnly = nil
    self._readOnly = on
    self._f:EnableMouse(not on)
end

--- Applies whatever SetReadOnly could not do during combat. Called by the owner on
--- PLAYER_REGEN_ENABLED.
-- @return bool  whether anything was applied
function ItemSlotMeta:ApplyPending()
    local want = self._pendingReadOnly
    if want == nil then return false end
    self._pendingReadOnly = nil
    if self._readOnly == want then return false end
    self._readOnly = want
    self._f:EnableMouse(not want)
    return true
end

--- @param w number
--- @param h number|nil  defaults to w
function ItemSlotMeta:SetSize(w, h)
    self._f:SetSize(w, h or w)
    self._box:Layout()
end

function ItemSlotMeta:ApplyTheme()
    if self._iconComp and self._iconComp.ApplyTheme then self._iconComp:ApplyTheme() end
    if self._countText and self._countText.ApplyTheme then self._countText:ApplyTheme() end
    -- Re-resolve the edge: a quality colour comes from SuuUI.Game, but the NEUTRAL fallback is a
    -- token, so a theme change has to re-run this or an empty cell keeps the old theme's edge.
    self:_paintEdge()
end

function ItemSlotMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._countText then self._countText:Destroy() end
    if self._iconComp then self._iconComp:Destroy() end
    if self._overlayBox then self._overlayBox:Destroy() end
    if self._box then self._box:Destroy() end
    -- Hidden, NOT reparented to nil. SetParent(nil) on a frame built from a Blizzard template is
    -- refused on a protected frame in combat, and it buys nothing here.
    self._f:Hide()
end

SuuUI.Components.InstallBase(ItemSlotMeta, "_f")

--- Creates one bag slot.
--
-- @param props table  { slot, size, bag, name }
--   slot: 1-based slot within the bag. Required.
--   size: side of the square cell. Required -- a cell's size is a plugin setting, so the component
--         must not invent a theme token for it.
--   bag:  the bag id. REQUIRED, and asserted to match the parent's GetID(). It cannot be inferred
--         from the parent alone, because a frame with no SetID reports id 0 -- which is exactly
--         what the BACKPACK reports, so "nobody set an id" and "this is the backpack" are the same
--         reading. Making the caller state it turns that ambiguity into a checkable claim.
-- @param parent frame  MUST carry the bag id as its own GetID(), because that is where the
--   template's own click handler reads it.
-- @return table  ItemSlot handle
function SuuUI.Components.ItemSlot(props, parent)
    props = props or {}
    assert(type(props.slot) == "number", "SuuUI: ItemSlot needs a slot")
    assert(type(props.size) == "number", "SuuUI: ItemSlot needs a size")
    assert(type(props.bag) == "number", "SuuUI: ItemSlot needs a bag id")
    assert(parent and type(parent.GetID) == "function",
        "SuuUI: ItemSlot's parent must carry the bag id as its GetID()")
    -- The two sources of the bag id must agree. A cell parented to the wrong holder would act on
    -- the wrong bag through the template's own handler, which destroys an item rather than
    -- misdrawing one -- so this is asserted rather than reconciled.
    local parentBag = parent:GetID()
    assert(props.bag == parentBag,
        "SuuUI: ItemSlot bag " .. tostring(props.bag) ..
        " does not match its parent's id " .. tostring(parentBag))

    local f = CreateFrame("Button", props.name, parent, "ContainerFrameItemButtonTemplate")
    f:SetSize(props.size, props.size)
    -- The id IS the wiring, and it is set before anything paints so the first Refresh reads the
    -- right slot rather than slot 0.
    f:SetID(props.slot)

    -- Everything the template draws, silenced in favour of ours.
    silence(f.icon)
    silence(f.Count)
    silence(f.IconBorder)
    if f.Cooldown and type(f.Cooldown.Hide) == "function" then f.Cooldown:Hide() end
    -- HIDE THE TEXTURE OBJECTS -- do NOT pass nil to the setters. `SetNormalTexture(nil)` is
    -- REFUSED on this client ("bad argument #2 to '?' (Usage: self:SetNormalTexture(asset))"), and
    -- that throw during construction is what left the stance bar invisible with no error, because
    -- the exception was pcall'd into a debug-only log.
    for _, getter in ipairs({
        "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
    }) do
        if type(f[getter]) == "function" then
            local tex = f[getter](f)
            if type(tex) == "table" then
                if type(tex.SetTexture) == "function" then tex:SetTexture(nil) end
                if type(tex.Hide) == "function" then tex:Hide() end
            end
        end
    end

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    local box = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })

    -- A border here, unlike ActionButton: on an action bar the plate owns the surface, but on a bag
    -- cell the edge carries the item's QUALITY, which is the single most scannable thing in a wall
    -- of eighty icons. trim crops the bevel Blizzard bakes into its own icon files so ours is the
    -- only edge visible.
    local iconComp = SuuUI.Components.Icon({ icon = nil, border = true, trim = true }, f)
    iconComp._fade = false
    box:Add(iconComp, { align = "stretch", valign = "stretch" })

    local iconFrame = iconComp:GetFrame()
    local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cooldown:SetHideCountdownNumbers(true)
    -- Inset by the border width so the sweep does not cover the quality edge -- the same fix the
    -- aura icons needed, where a full-bleed cooldown swallowed the dispel ring.
    box:Add(cooldown, { inset = T:GetToken("borderWidth") or 1 })

    -- A FontString on the root frame would draw BEHIND the cooldown, because a child frame draws
    -- above its parent's layers. RaiseAbove is the only sanctioned z-order mechanism outside
    -- Core/UIRoot.lua.
    local overlay = CreateFrame("Frame", nil, f)
    box:Add(overlay, { align = "stretch", valign = "stretch" })
    SuuUI.UIRoot:RaiseAbove(overlay, iconFrame, 2)
    local overlayBox = SuuUI.Layout:CreateContainer({ host = overlay, layout = "stack" })

    local padXs = T:GetToken("spaceXxs") or 2
    local countText = SuuUI.Components.Text({
        text = "", size = "sm", color = "text", justify = "RIGHT", wrap = false,
    }, overlay)
    countText._fade = false
    overlayBox:Add(countText, {
        align = "end", valign = "end", inset = { right = padXs, bottom = padXs },
    })
    countText:Hide()

    local id = "itemslot_" .. tostring(f)
    handle = setmetatable({
        _f          = f,
        _box        = box,
        _iconComp   = iconComp,
        _cooldown   = cooldown,
        _overlay    = overlay,
        _overlayBox = overlayBox,
        _countText  = countText,
        _eid        = id,
        _info       = nil,
        _readOnly   = false,
    }, ItemSlotMeta)

    -- HookScript throughout, never SetScript: the template's own handlers ARE the mechanism, and
    -- its OnEnter is where the item tooltip comes from. No tooltip code here for the same reason
    -- StanceButton has none -- a second owner anchoring the same frame makes it flick.
    f:HookScript("PostClick", function(_, button)
        S:Emit(handle, S.SIGNALS.CLICKED, button or "LeftButton")
    end)
    f:HookScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:HookScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle:Refresh()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
