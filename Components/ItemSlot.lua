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
-- WE OWN THE CLICK, and this reverses what this header used to say. It read "NEVER SetScript OnClick
-- on this frame -- that handler IS the mechanism", which was reasoned from the secure action bar work
-- and is FALSE for this template. Measured in game 2026-08-25: our cells carry the template's OnClick,
-- OnDragStart and OnReceiveDrag, are mouse-enabled, and moved NOTHING -- not by click, not by drag.
-- Blizzard's handlers resolve their container from state ContainerFrame_Update installs, and it never
-- runs for a cell we created, so they return early in silence.
--
-- So movement is ours: PickupContainerItem both picks up and places (and SWAPS on an occupied slot),
-- SplitContainerItem splits, and all of it was measured working from tainted Lua in Phase 0. The one
-- thing still out of reach is USING an item, which is genuinely protected -- right-click therefore
-- sells at a merchant, where the same call is permitted, and does nothing elsewhere rather than
-- spending a taint error on the player.
--
-- The template is still worth inheriting for its ART REGIONS and its own OnEnter tooltip, which needs
-- no container resolution and does work.
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

-- The bank's own container id. Read from the client rather than written as -1: Enum.BagIndex.Bank was
-- MEASURED as -1 on this build, but a literal here would silently point at the wrong container on a
-- generation that moved it, and this id selects the cell's TEMPLATE -- so a wrong value is a cell whose
-- handler acts on the wrong container, which loses an item rather than misdrawing one.
--
-- The second term reads the CLIENT's own BANK_CONTAINER global: a local's initialiser is evaluated
-- before the local comes into scope, so the bare name there is still the global. Bare rather than
-- _G.BANK_CONTAINER so the harness can stage it.
local BANK_CONTAINER = (Enum and Enum.BagIndex and Enum.BagIndex.Bank)
    or (type(BANK_CONTAINER) == "number" and BANK_CONTAINER)
    or -1

-- How much of the border an EMPTY slot keeps. Low enough that a half-empty bag reads as mostly
-- background rather than as a grid, high enough that the slot is still findable when you go to drop
-- something into it -- which is the one time an empty cell matters.
local EMPTY_EDGE_ALPHA = 0.35

local ItemSlotMeta = {}
ItemSlotMeta.__index = ItemSlotMeta

-- Hides one of the template's own regions without caring what kind it is.
--
-- SetAlpha(0) as well as Hide, and the two are not redundant. Hiding a region inside a button the
-- client treats as protected is a call it can refuse, and a refusal here is silent -- whereas alpha
-- is never refused, so the region is invisible either way. Alpha also covers a texture set through
-- SetAtlas, which SetTexture(nil) does not reliably clear on every client generation.
--
-- DELIBERATELY NO SetVertexColor RESET. These textures are tinted for item quality -- a leftover
-- tint is what made the artefact blue rather than white -- so resetting it looks like the fix and is
-- not: clearing the TEXTURE removes the tint with it, and mutation testing confirmed a vertex reset
-- here changes nothing any consumer can observe. Do not re-add it.
local function silence(region)
    if not region then return end
    if type(region.SetTexture) == "function" then region:SetTexture(nil) end
    if type(region.SetText) == "function" then region:SetText("") end
    if type(region.SetAlpha) == "function" then region:SetAlpha(0) end
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
    if info then
        -- An occupied slot below the quality threshold takes the standard neutral edge.
        self._iconComp:SetBorderColor(nil)
        return
    end
    -- AN EMPTY SLOT RECEDES. Giving it the same edge weight as an item means the empty tail of a
    -- bag -- often half of it -- draws as hard a lattice as the things you are looking for, which is
    -- what makes a flat grid read as a spreadsheet. Derived from colorBorder at reduced alpha rather
    -- than a surface token, so it is visibly the SAME edge, quieter, and it tracks a theme edit
    -- because this runs from ApplyTheme.
    local base = T:GetToken("colorBorder")
    if type(base) == "table" then
        local dim = self._dimEdge
        if not dim then
            dim = {}
            self._dimEdge = dim
        end
        dim[1], dim[2], dim[3] = base[1], base[2], base[3]
        dim[4] = (base[4] or 1) * EMPTY_EDGE_ALPHA
        -- Reference-compared by Icon's setter, so the reused table would early-return. Clear it
        -- first, which also means a theme change re-applies rather than being swallowed.
        self._iconComp:SetBorderColor(nil)
        self._iconComp:SetBorderColor(dim)
    else
        self._iconComp:SetBorderColor(nil)
    end
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

--- Whether this cell is dimmed as a search non-match.
-- @return bool
function ItemSlotMeta:IsDimmed()
    return self._dimmed == true
end

--- Dims this cell, or restores it.
--
-- A search non-match is DIMMED rather than removed from the layout, so the grid does not reflow under
-- the player's cursor while they type -- and so a slot keeps its position, which is the whole point of
-- a positional grid.
--
-- NO EARLY RETURN on an unchanged value, deliberately. The previous version returned early when the
-- flag already matched, and that is how the defect below survived: the template reset the alpha, the
-- flag still said "dimmed", and every later call short-circuited before re-applying it. Re-asserting
-- two SetAlpha calls per cell is cheaper than a state that lies about what is on screen.
-- @param on bool
function ItemSlotMeta:SetDimmed(on)
    on = on and true or false
    self._dimmed = on
    local a = on and (T:GetToken("opacityDimmed") or 0.35) or 1
    -- FADES OUR OWN CHILDREN, NEVER THE TEMPLATE'S BUTTON FRAME. Measured in game 2026-08-25:
    -- f:SetAlpha(0.3) followed immediately by f:GetAlpha() returned 1 -- the frame does not hold an
    -- alpha at all, because the template ships animation groups (the new-item glow and flash) that own
    -- it. So the search dim set a flag, reported itself dimmed, and changed nothing on screen.
    --
    -- The Icon and the readout overlay are frames WE created and nothing else writes, so they hold it.
    -- Fading both rather than just the art, or a dimmed cell would keep a full-strength stack count
    -- floating over faded art.
    if self._iconComp then self._iconComp:GetFrame():SetAlpha(a) end
    if self._overlay then self._overlay:SetAlpha(a) end
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

    -- THE TEMPLATE DEPENDS ON THE CONTAINER, and getting this wrong is why the bank window opened but
    -- could not move anything. ElvUI branches on exactly this line (Bags.lua) on this same client:
    --
    --   inherit = (bagID == BANK_CONTAINER) and 'BankItemButtonGenericTemplate'
    --                                        or 'ContainerFrameItemButtonTemplate'
    --
    -- The bank's OWN 28-slot container (-1) is a different template family from a bag -- which Phase 0
    -- measured and recorded ("BankFrameItem1 is a real table; bank cells have their own template
    -- family") and which this file then ignored, building every cell on the bag template. The bank
    -- BAGS (5..11) are ordinary containers and keep the bag template, so the branch is on the single
    -- container id rather than on "is this the bank window".
    --
    -- The two handlers differ in where they get the container: the bag one reads the PARENT's id,
    -- while the bank generic one hardcodes BANK_CONTAINER and reads only the slot from GetID(). So the
    -- holder's id is load-bearing for one and ignored by the other, which is why matching the
    -- reference matters more than reasoning about it.
    local template = props.bag == BANK_CONTAINER
        and "BankItemButtonGenericTemplate"
        or "ContainerFrameItemButtonTemplate"

    -- FRAME TYPE `ItemButton`, as ElvUI creates its cells -- these templates are declared as that type
    -- and the client's own mixin methods hang off it. Feature-detected rather than assumed: a client
    -- generation without the type would refuse the call outright, and a plain Button still applies the
    -- template's scripts (measured -- our cells had OnClick, OnDragStart and OnReceiveDrag), so the
    -- fallback degrades to what shipped before rather than to nothing.
    local ok, f = pcall(CreateFrame, "ItemButton", props.name, parent, template)
    if not ok or not f then
        f = CreateFrame("Button", props.name, parent, template)
    end
    f:SetSize(props.size, props.size)
    -- The id IS the wiring, and it is set before anything paints so the first Refresh reads the
    -- right slot rather than slot 0.
    f:SetID(props.slot)

    -- EVERYTHING THE TEMPLATE DRAWS, SILENCED IN FAVOUR OF OURS -- ENUMERATED, NOT NAMED.
    --
    -- This was a hand-written list of the regions I knew about (`icon`, `Count`, `IconBorder`) plus
    -- the four texture getters, and it shipped a blue lattice over every cell. Measured on this
    -- client: after that list ran, the cell still had THREE visible textures -- fileID 969828 twice
    -- and 902180 once. 969828 is `Interface\Common\WhiteIconFrame`, a white square OUTLINE the
    -- template carries to be vertex-tinted for item quality, and it ships at a FIXED 37x37 rather
    -- than anchored to the button. That fixed size is why the artefact looked like a border at all:
    -- at a cell near 37 units the outline lands exactly on the cell's edge, and growing the cell
    -- past 37 makes it visibly pull inward and "disappear" -- which is how the bug was finally
    -- identified, since no border of ours could behave that way.
    --
    -- So a name list is the wrong shape here. StanceButtonTemplate got away with one because its art
    -- is three known textures; a container button's region set differs between client generations,
    -- and any name I do not know about draws over our cell at full opacity. Enumerate instead: at
    -- this point in construction NONE of our own visuals exist yet -- the Icon, the Cooldown, the
    -- overlay and its readouts are all created further down, in their own child frames -- so every
    -- region on this frame is Blizzard's by definition and the sweep cannot blank anything of ours.
    -- KEEP IT THAT WAY: creating one of our regions above this line would silence it.
    if type(f.GetRegions) == "function" then
        for _, region in ipairs({ f:GetRegions() }) do
            silence(region)
        end
    end
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
    local iconComp = SuuUI.Components.Icon({ icon = nil, border = true, trim = true, rounded = true }, f)
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

    -- WE OWN THE INTERACTION. This file used to say "NEVER SetScript OnClick, the template's handler
    -- IS the mechanism" -- and that premise was MEASURED FALSE in game: with the cell mouse-enabled and
    -- carrying the template's OnClick, OnDragStart and OnReceiveDrag (all four probed true), neither a
    -- click nor a drag moved anything. Blizzard's handlers resolve their container through state that
    -- ContainerFrame_Update installs, and that function never runs for a cell we built, so they return
    -- early and silently.
    --
    -- Doing it ourselves is SAFE rather than a gamble, because Phase 0 measured the two calls it needs:
    -- PickupContainerItem works from tainted Lua (cursor carried item 27860), and UseContainerItem is
    -- refused away from a merchant but WORKS at one. So movement is ours and only USE is out of reach.
    --
    -- RegisterForClicks and RegisterForDrag are BOTH required and neither is inherited usefully here: a
    -- Button fires for left-up alone until told otherwise, and a frame with no drag registration never
    -- receives OnDragStart at all -- which is exactly the half of the report that said drag did nothing.
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")

    -- Pickup and place are ONE call in this API: PickupContainerItem on a loaded cursor PLACES, and
    -- placing onto an occupied slot SWAPS, handing the previous occupant back. That is why there is no
    -- separate place path and why a cell written on an overwrite assumption would destroy an item.
    local function pickupOrPlace()
        local C = C_Container
        if not (C and type(C.PickupContainerItem) == "function") then return end
        local bag = handle:GetBag()
        if bag == nil then return end
        C.PickupContainerItem(bag, props.slot)
    end

    f:SetScript("OnClick", function(_, button)
        if handle._readOnly then return end
        local C = C_Container
        local bag = handle:GetBag()
        if bag == nil then return end

        if button == "RightButton" then
            -- UseContainerItem MEANS THREE DIFFERENT THINGS depending on where you are, and only one of
            -- them is refused. At a merchant it SELLS; at an open bank it TRANSFERS between bank and
            -- bags, which is the shortcut players already have in their fingers; anywhere else it USES
            -- the item, and that is the one the client blocks for tainted code (measured: pcall true,
            -- nothing happened, ForceTaint_Strong). So it is attempted exactly where it is known to
            -- work, and skipped otherwise rather than spending a taint error on the player.
            --
            -- THE BANK TEST IS NOT BankFrame:IsShown(). Suppression deliberately leaves that frame
            -- SHOWN -- hiding it calls CloseBankFrame() and ends the session -- so its visibility no
            -- longer says anything about being at a teller. ItemCache tracks the real session from
            -- BANKFRAME_OPENED / CLOSED, and it is in Core precisely so a component may read it.
            local atMerchant = MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
            local atBank = SuuUI.ItemCache and SuuUI.ItemCache.IsBankOpen
                and SuuUI.ItemCache:IsBankOpen()
            if (atMerchant or atBank) and type(C.UseContainerItem) == "function" then
                C.UseContainerItem(bag, props.slot)
            end
            S:Emit(handle, S.SIGNALS.CLICKED, button)
            return
        end

        if IsShiftKeyDown and IsShiftKeyDown() and not CursorHasItem()
            and type(C.SplitContainerItem) == "function" then
            local info = handle._info
            local count = info and info.stackCount or 1
            if count > 1 then
                C.SplitContainerItem(bag, props.slot, math.floor(count / 2))
                S:Emit(handle, S.SIGNALS.CLICKED, button or "LeftButton")
                return
            end
        end

        pickupOrPlace()
        S:Emit(handle, S.SIGNALS.CLICKED, button or "LeftButton")
    end)

    -- Drag is the same pickup, and the same place. A player who presses and drags gets OnDragStart;
    -- one who releases over another cell gets that cell's OnReceiveDrag.
    f:SetScript("OnDragStart", function()
        if handle._readOnly then return end
        pickupOrPlace()
    end)
    f:SetScript("OnReceiveDrag", function()
        if handle._readOnly then return end
        pickupOrPlace()
    end)

    -- OnEnter/OnLeave stay HOOKED: the template's own OnEnter is where the item tooltip comes from, and
    -- that half DOES work -- it needs no container resolution, only the frame. No tooltip code here for
    -- the same reason StanceButton has none: a second owner anchoring the same frame makes it flick.
    f:HookScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
    f:HookScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)

    handle:Refresh()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
