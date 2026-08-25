-- One bag slot: the icon, the stack count, a quality-coloured edge and a cooldown sweep.
--
-- WHY THIS INHERITS A BLIZZARD TEMPLATE, like StanceButton and unlike everything else.
--
-- USING an item from addon code is BLOCKED on this client, and this has now been established TWICE
-- by different routes. First a probe -- `/run C_Container.UseContainerItem(0, 1)` returned true from
-- pcall, changed nothing, and raised `*** ForceTaint_Strong *** has been blocked from an action only
-- available to the Blizzard UI`. Then, after that probe was wrongly dismissed as invalid and the gate
-- below was removed, a REAL right-click in the bags raised the player-facing popup `SuuUI has been
-- blocked from an action only available to the Blizzard UI`.
--
-- SO A HARDWARE EVENT DOES NOT LAUNDER TAINT, which was the reasoning that retracted the first
-- result: the argument was that a chat-box `/run` is insecure by construction and says nothing about
-- a real click, and the flaw in it is that OUR OnClick is tainted code whatever triggered it. Calling
-- a Blizzard function from a tainted stack does not make the call trusted either. The retraction cost
-- a live error popup, and it is written down here because the reasoning was plausible and wrong.
--
-- What the other bag addons do instead, and what this cell does NOT do yet: ElvUI builds its cells
-- from `ContainerFrameItemButtonTemplate` and lets BLIZZARD'S OWN OnClick receive the click, so the
-- use happens on an untainted stack; MRT builds a `SecureActionButtonTemplate` purely to apply a
-- weapon oil. Either would make use and trade reachable. See the note on the right-click branch.
--
-- MOVING items is measured and NOT blocked: `PickupContainerItem` worked from the same tainted
-- context, cursor and all, and `SplitContainerItem` with it. Selling at a MERCHANT and transferring
-- at an OPEN BANK are also measured working, which is why the right-click branch attempts exactly
-- those two and skips everything else.
--
-- WE OWN THE CLICK, and this reverses what this header used to say. It read "NEVER SetScript OnClick
-- on this frame -- that handler IS the mechanism", which was reasoned from the secure action bar work
-- and is FALSE for this template. Measured in game 2026-08-25: our cells carry the template's OnClick,
-- OnDragStart and OnReceiveDrag, are mouse-enabled, and moved NOTHING -- not by click, not by drag.
-- Blizzard's handlers resolve their container from state ContainerFrame_Update installs, and it never
-- runs for a cell we created, so they return early in silence.
--
-- So movement is ours: PickupContainerItem both picks up and places (and SWAPS on an occupied slot),
-- SplitContainerItem splits, and right-click hands the slot to `UseContainerItem` with NO gate at
-- all -- the client decides whether that means sell, deposit, trade, attach or use.
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

--- Resolves a container function across BOTH shapes this client exposes it in.
--
-- This client is a hybrid: a modern backend wearing TBC's UI, so the same call is reachable as
-- `C_Container.<name>` and as a bare global `<name>`, and which one exists is not something to
-- assume. `_paintCooldown` already read `(C and C.GetContainerItemCooldown) or GetContainerItemCooldown`
-- -- but the three ACTION calls did not, so pickup, split and use each depended on `C_Container`
-- alone and would fail in silence on a build that only has the legacy globals.
--
-- A BARE global lookup through `_G[name]`, never a hardcoded `_G.name`: a chunk resolves bare names
-- through its own environment, which under test is the harness table, so reaching past it would make
-- the fallback branch untestable. The dynamic name is why the index form is used at all.
-- @param name string
-- @return function|nil
local function containerFn(name)
    local C = C_Container
    local fn = C and C[name]
    if type(fn) == "function" then return fn end
    fn = _G and _G[name]
    if type(fn) == "function" then return fn end
    return nil
end

-- Quality at or above which the edge takes the item's colour. Below it the cell keeps the neutral
-- icon border, because a WHITE edge on a dark cell reads as a selected state rather than as
-- information -- the same threshold Plugins/Tooltips/Signal.lua settled on for the same reason.
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
    -- EVERY QUALITY THE CLIENT NAMES, grey and white included. This carried a `>= 2` threshold copied
    -- from Plugins/Tooltips/Signal.lua, and the reasoning does not transfer: on a TOOLTIP a white edge
    -- reads as a selected state, because a tooltip has one border and no neighbours to compare it with.
    -- In a grid of eighty cells that all carry an edge, the colour is the only thing separating a grey
    -- from a common from an uncommon -- so suppressing two of the six made those two look unfinished,
    -- and the concept colours all of them (Q[0] grey, Q[1] white).
    --
    -- Game:ItemQualityColor already answers for all eight qualities and deliberately does NOT fold in a
    -- threshold, precisely so each surface can make this decision for itself. This is that decision.
    if q then
        local c = SuuUI.Game:ItemQualityColor(q)
        if c then
            self._iconComp:SetBorderColor(c)
            return
        end
    end
    if info then
        -- Occupied but the client does not name this quality: the neutral edge is the honest answer.
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
--- Lights or clears the search-match ring.
-- Separate from SetDimmed on purpose: dimming says "this is not what you asked for" and the ring
-- says "this is", and a cell in neither state (no active search) must show neither.
-- @param on boolean
function ItemSlotMeta:SetMatched(on)
    self._matched = on and true or false
    self:_paintMatch()
end

--- Whether the match ring is lit.
-- @return boolean
function ItemSlotMeta:IsMatched()
    return self._matched == true
end

function ItemSlotMeta:_paintMatch()
    if not self._matchRing then return end
    -- false resolves to a fully transparent edge rather than removing the backdrop, so the ring
    -- goes dark without any geometry changing.
    SuuUI.Backdrop.SetBorder(self._matchRing, self._matched and "colorAccent" or false)
end

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
    -- Apply() restates the whole backdrop table and colorAccent is user-editable, so the ring has
    -- to be re-lit here or a lit match sits on the previous theme's accent.
    self:_paintMatch()
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
    -- A SNAPSHOT CELL IS A DIFFERENT KIND OF CELL, and it is deliberately the SIMPLER one. It shows a
    -- cached reading of another character's bag, so there is no container behind it to act on and
    -- nothing for the client to do -- which means no Blizzard template at all.
    --
    -- WHY IT MUST NOT INHERIT THE TEMPLATE, even though that would cost less code. A cell's identity is
    -- its (bag, slot), and those are resolved against whoever is LOGGED IN -- so a template cell
    -- showing an alt's cached slot 1 would happily pick up, use or sell YOUR OWN item in bag 0 slot 1.
    -- Blocking that with EnableMouse(false) works, and it also kills the tooltip, which is most of the
    -- point of browsing an alt's bags. Two kinds of cell resolves both at once: the live one is
    -- hands-off and the client owns it, the snapshot one is inert and we own it.
    local snapshot = props.snapshot and true or false

    local template = props.bag == BANK_CONTAINER
        and "BankItemButtonGenericTemplate"
        or "ContainerFrameItemButtonTemplate"

    -- SECURE TEMPLATE TRIED TWICE AND ABANDONED, and the reason is worth keeping so nobody reaches for
    -- it a third time. Adding `SecureActionButtonTemplate` here REPLACES the container template's
    -- OnClick with the secure handler -- verified in game -- which throws away the only thing that
    -- performs a container interaction, in exchange for a handler whose `item` and `macro` types this
    -- client does not dispatch (four attribute payloads were tried and none fired).
    --
    -- No secure frame also means no combat lockdown, no deferred geometry and no attributes-once rule
    -- on this window, which is what the concept said in the first place.

    -- FRAME TYPE `ItemButton`, as ElvUI creates its cells -- these templates are declared as that type
    -- and the client's own mixin methods hang off it. Feature-detected rather than assumed: a client
    -- generation without the type would refuse the call outright, and a plain Button still applies the
    -- template's scripts (measured -- our cells had OnClick, OnDragStart and OnReceiveDrag), so the
    -- fallback degrades to what shipped before rather than to nothing.
    -- NO SECURE TEMPLATE, and this is the load-bearing line. Adding `SecureActionButtonTemplate`
    -- alongside the container one REPLACES the container template's OnClick with the secure handler --
    -- verified in game, where `GetScript("OnClick") == SecureActionButton_OnClick` came back true -- so
    -- the very handler that performs the whole interaction was being thrown away in exchange for one
    -- that needs attributes this client does not dispatch for the item or macro types.
    --
    -- ElvUI creates its slots from exactly this template and nothing else, on this exact client.
    local f
    if snapshot then
        -- No template, so no Blizzard art to clear and no handler to leave alone. A plain Button
        -- rather than a Frame because it still wants hover, for the tooltip.
        f = CreateFrame("Button", props.name, parent)
    else
        local ok
        ok, f = pcall(CreateFrame, "ItemButton", props.name, parent, template)
        if not ok or not f then
            f = CreateFrame("Button", props.name, parent, template)
        end
    end
    f:SetSize(props.size, props.size)
    -- The id IS the wiring for a LIVE cell -- the template's own handler reads the slot from it and
    -- the bag from the parent's -- and it is set before anything paints so the first Refresh reads the
    -- right slot rather than slot 0.
    --
    -- A snapshot cell deliberately gets NO id. There is no handler to feed, and an id would make the
    -- cell look addressable to any code that walked the grid looking for a container position.
    if not snapshot then f:SetID(props.slot) end

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
    -- Skipped entirely for a snapshot cell: with no template there is no Blizzard art, and the sweep's
    -- own precondition -- that every region on the frame at this point is Blizzard's -- would still
    -- hold but buy nothing.
    if not snapshot and type(f.GetRegions) == "function" then
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

    -- THE SEARCH-MATCH RING, lit only while the cell matches a query. The concept's `.cell.hit`
    -- gives a match an accent edge, and it can do that without losing the item's quality colour
    -- because a concept cell has TWO edges: a neutral one on the cell and the quality one on the
    -- art, inset a pixel. This cell has one, carrying quality -- so recolouring it would trade the
    -- quality colour away for the duration of every search.
    --
    -- So the ring is its own edge, one border-width INSIDE the quality edge rather than outside it,
    -- which is the one place there is room. Both colours stay readable and the resting appearance
    -- of the grid is untouched: an unlit ring is a transparent edge, not a drawn one. The ordering
    -- is inverted against the concept, which puts accent outside and quality inside -- see the note
    -- in the spec.
    local matchRing = CreateFrame("Frame", nil, f, "BackdropTemplate")
    -- The edge geometry is built here even though the colour is transparent: Apply always states
    -- edgeFile and edgeSize, so SetBorder can light it later without rebuilding the table.
    SuuUI.Backdrop.Apply(matchRing, { bg = false, border = false, inset = 0 })
    box:Add(matchRing, { align = "stretch", valign = "stretch",
                         inset = T:GetToken("borderWidth") or 1 })

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
        _matchRing  = matchRing,
        _overlay    = overlay,
        _overlayBox = overlayBox,
        _countText  = countText,
        _eid        = id,
        _info       = nil,
        _readOnly   = false,
        -- Which KIND of cell this is. A snapshot cell shows a cached reading of another character and
        -- has no container behind it, so it owns its tooltip and is inert by construction rather than
        -- by having its mouse taken away.
        _snapshot   = snapshot,
    }, ItemSlotMeta)

    -- WE DO NOT TOUCH THE CLICK PATH. The template's own OnClick performs the whole interaction --
    -- pickup, place, split, sell, deposit, mail, trade and USE -- and the one thing that must never
    -- happen is for our code to be anywhere near it.
    --
    -- THIS REVERSES TWO EARLIER INVARIANTS IN THIS FILE, both of which were reasoned from bad
    -- measurements, and the correction cost a whole session:
    --
    --   1. "The template's handlers are inert for our cells." Tested by handing the click back and
    --      watching nothing happen -- but that test predated the RegisterForClicks fix, so the click
    --      was never delivered. It was never inert.
    --   2. "So SuuUI owns movement, and USE is simply out of reach." Everything built on top of that --
    --      our own OnClick, a merchant/bank gate, a SecureActionButtonTemplate with `type2 = "item"`
    --      and then `type2 = "macro"` -- was solving a problem that did not exist, and the secure
    --      template actively made things worse by REPLACING the container template's OnClick with the
    --      secure one.
    --
    -- WHY WE MAY NOT EVEN ASSIGN BLIZZARD'S OWN FUNCTION: `f:SetScript("OnClick",
    -- ContainerFrameItemButton_OnClick)` puts OUR taint on the handler, so its protected calls are
    -- refused. Measured: doing exactly that from a /run raised the blocked-action popup, and the popup
    -- named `ForceTaint_Strong` -- the chat path's taint identity -- rather than SuuUI, which is what
    -- distinguished "the approach is wrong" from "the probe method taints it". The template has to
    -- install its own handler at CreateFrame time, from Blizzard's XML, with nothing of ours on it.
    --
    -- ELVUI IS THE PROOF, and it runs on this exact client: `B:ConstructContainerButton` creates the
    -- slot from the same container template, calls `SetID`, HOOKS OnEnter/OnLeave, and never calls
    -- SetScript("OnClick"), never calls RegisterForClicks, and never adds a secure template. So this
    -- file now does the same, and the concept's "nothing here is secure" note turns out to have been
    -- right the whole way through.
    --
    -- NO RegisterForClicks EITHER. Ours overrode the template's own registration, and the explicit
    -- two-string form silently dropped every right-click -- the third time that call has produced a
    -- control that looks perfect and does nothing. The template registers what its handler expects;
    -- there is nothing here for us to improve on.

    -- A SNAPSHOT CELL OWNS ITS TOOLTIP, because there is no template OnEnter to inherit one from. The
    -- live cell deliberately has no tooltip code at all -- the template's own OnEnter supplies it, and
    -- a second owner anchoring the same frame makes it flick -- so this is the one kind of cell where
    -- writing one is correct rather than duplication.
    --
    -- FROM THE CACHED LINK, not from the container: there is no container to ask. `SetHyperlink` is
    -- what makes a stored link render as the real item tooltip, which is the whole reason the cache
    -- stores links rather than ids alone.
    if snapshot then
        f:SetScript("OnEnter", function(self)
            S:Emit(handle, S.SIGNALS.MOUSE_ENTER)
            local link = handle._info and handle._info.hyperlink
            local tt = GameTooltip
            if not (link and tt and type(tt.SetHyperlink) == "function") then return end
            tt:SetOwner(self, "ANCHOR_RIGHT")
            tt:SetHyperlink(link)
            tt:Show()
        end)
        f:SetScript("OnLeave", function()
            S:Emit(handle, S.SIGNALS.MOUSE_LEAVE)
            local tt = GameTooltip
            if tt and type(tt.Hide) == "function" then tt:Hide() end
        end)
    else
        -- CLICKS AND DRAGS ARE OBSERVED, NEVER OWNED. HookScript runs after the template's handler and
        -- cannot displace it, which is the only safe way to emit a signal from a frame whose behaviour
        -- belongs to the client. Same reason OnEnter is hooked rather than set: the template's OnEnter
        -- is where the item tooltip comes from.
        f:HookScript("OnClick", function(_, button)
            S:Emit(handle, S.SIGNALS.CLICKED, button or "LeftButton")
        end)
        f:HookScript("OnEnter", function() S:Emit(handle, S.SIGNALS.MOUSE_ENTER) end)
        f:HookScript("OnLeave", function() S:Emit(handle, S.SIGNALS.MOUSE_LEAVE) end)
    end

    handle:Refresh()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
