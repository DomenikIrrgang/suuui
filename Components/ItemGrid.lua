-- A flat combined grid of bag slots: every slot from every container in one wall of cells.
--
-- WHY WRAPPING FLOW AND NOT GridLayout. GridLayout derives its column width from the CONTAINER's
-- width, which is right for a settings form and wrong for fixed square cells -- a narrower window
-- would silently squash the icons. A wrapping horizontal flow with a fixed cell size breaks onto a
-- new line when the next cell would overflow, so the grid's own width decides the column count and
-- every cell stays exactly the size the player asked for.
--
-- WHY THERE IS NO Pool. Cells cannot be recycled across bags: a cell's bag comes from its PARENT's
-- id, so reusing one in a different bag means reparenting a frame built from a secure template --
-- refused in combat, and looting mid-fight is when bags change most. So cells are created per
-- (bag, slot) and kept, and a change to the container SET destroys and rebuilds them. That is also
-- why CHILDREN_CHANGED exists: the rebuild can itself be deferred to the end of a fight, and
-- nothing else can tell a holder of cell references when they went stale.
--
-- SORTING IS DISPLAY-ONLY. Re-ordering changes which position a cell is laid out in; it never moves
-- an item. So it is instant, cannot fail, cannot be interrupted and works in combat -- and it is
-- what makes a wall of eighty icons navigable. Physical sorting (actually swapping items) is a
-- separate feature; see .kiro/specs/inventory.md section 8.
--
-- A BAG UPDATE REPAINTS BUT DOES NOT RE-SORT. Re-sorting whenever the client reports a change would
-- move items out from under the player's cursor as they loot. Order changes only when something asks
-- for it.
local CreateFrame, ipairs, pairs, type, tsort = CreateFrame, ipairs, pairs, type, table.sort
local strlower, strfind, ceil = string.lower, string.find, math.ceil

local S = SuuUI.UISignals
local T = SuuUI.Theme

local GridMeta = {}
GridMeta.__index = GridMeta

SuuUI.Components.ITEMGRID_SIGNALS = SuuUI.Components.ITEMGRID_SIGNALS or {
    CHILDREN_CHANGED = "itemgrid.children_changed",  -- Args: none. Cell references are now stale.
}
local GRID_SIGNALS = SuuUI.Components.ITEMGRID_SIGNALS

-- Ordering by quality DESCENDING then name is the default because it is what makes a flat grid
-- readable without headers: epics cluster, potions cluster, greys fall to the end. It is also the
-- order the later `grouping` setting would insert section headers into, which is why that feature
-- is one extra pass rather than a second layout.
-- EVERY mode puts occupied slots before empty ones, whatever else it orders by. An empty slot has
-- no name and no quality, so leaving it to the mode's own comparison sorts the empties to the FRONT
-- under name order -- an empty string sorts before every real name -- which reads as a broken grid.
local function occupiedFirst(cmp)
    return function(a, b)
        local emptyA, emptyB = a.info == nil, b.info == nil
        if emptyA ~= emptyB then return emptyB end
        return cmp(a, b)
    end
end

local function byPosition(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local SORTS = {
    quality = occupiedFirst(function(a, b)
        local qa, qb = a.info and a.info.quality or -1, b.info and b.info.quality or -1
        if qa ~= qb then return qa > qb end
        local na, nb = a.info and a.info.itemName or "", b.info and b.info.itemName or ""
        if na ~= nb then return na < nb end
        return byPosition(a, b)
    end),
    name = occupiedFirst(function(a, b)
        local na, nb = a.info and a.info.itemName or "", b.info and b.info.itemName or ""
        if na ~= nb then return na < nb end
        return byPosition(a, b)
    end),
    -- The client's own order: container then slot. The escape hatch for a player who navigates by
    -- muscle memory rather than by looking. Empty slots stay in place here rather than being pushed
    -- to the end, because "the client's order" is the whole point of this mode.
    slot = byPosition,
}

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function numSlots(bag)
    local C = C_Container
    if C and type(C.GetContainerNumSlots) == "function" then return C.GetContainerNumSlots(bag) end
    if type(GetContainerNumSlots) == "function" then return GetContainerNumSlots(bag) end
    return 0
end

--- One character's cached container record, or nil.
--
-- The snapshot counterpart to numSlots + GetContainerItemInfo: everything a snapshot grid knows comes
-- from here, and it answers nil rather than an empty table for a character the cache has never seen,
-- so "no record" and "a record of an empty bag" stay distinguishable.
local function cachedRecord(key, which)
    local IC = SuuUI.ItemCache
    if not (key and which and IC and type(IC.Get) == "function") then return nil end
    return IC:Get(key, which)
end

--- A cached slot expressed in the SAME SHAPE the live client returns.
--
-- The cache stores only `{ itemID, count }` per slot -- deliberately, since a link per slot per
-- character is tens of KB -- so the rest is filled in from the account-wide item table. Returning the
-- client's own field names is what lets ItemSlot paint a snapshot with the identical code path: a
-- second painting path would drift from the live one the first time either changed.
--
-- An item the cache has an id for but no INFO yet is a real state, not an error: GetItemInfo answers
-- nil until GET_ITEM_INFO_RECEIVED fires. Such a slot comes back with an itemID and nothing else,
-- which is what the concept draws as a `?` cell.
local function cachedInfo(entry)
    if type(entry) ~= "table" then return nil end
    local id = entry[1] or entry.itemID
    if not id then return nil end
    local IC = SuuUI.ItemCache
    local meta = IC and type(IC.ItemInfo) == "function" and IC:ItemInfo(id) or nil
    return {
        itemID     = id,
        stackCount = entry[2] or entry.count or 1,
        iconFileID = meta and meta.icon or nil,
        quality    = meta and meta.q or nil,
        hyperlink  = meta and meta.link or nil,
        itemName   = meta and meta.name or nil,
    }
end

--- Points this grid at a character's CACHED contents, or back at the live client.
--
-- @param key string|nil  character key, or nil for the live client
-- @param which string|nil  "bags" | "bank"; required with a key
--
-- REBUILDS EVERY CELL, and that is not laziness. A cell's kind is fixed at construction -- a live cell
-- inherits a Blizzard container template whose handler acts on whoever is logged in, a snapshot cell
-- has no template at all -- so re-pointing an existing cell would leave an alt's cached slot 1 wired to
-- YOUR bag 0 slot 1. Destroying is the only way to change kind, and switching character is a
-- deliberate user action rather than something on a hot path.
function GridMeta:SetCharacter(key, which)
    local snapshot = key ~= nil
    if self._snapshot == snapshot and self._characterKey == key and self._which == which then
        return false
    end
    self._snapshot     = snapshot
    self._characterKey = key
    self._which        = which
    -- The grid's own teardown and rebuild path, rather than a hand-rolled loop: _destroyCells also
    -- clears the entry list and the cell container, and _apply("rebuild") is what defers geometry when
    -- the call lands in combat.
    self:_destroyCells()
    self:_apply("rebuild")
    return true
end

--- Whether this grid is showing a cached snapshot rather than the live client.
-- @return bool
function GridMeta:IsSnapshot() return self._snapshot == true end

--- The character key this grid is showing, or nil when it is live.
-- @return string|nil
function GridMeta:GetCharacter() return self._characterKey end

--- When the shown container was last read, as a unix time, or nil.
--
-- Only ever answers for a snapshot: a live grid IS the current reading, so a timestamp on it would
-- invite a caller to render "seen just now", which is a freshness claim about something that needs no
-- freshness claim.
-- @return number|nil
function GridMeta:SeenAt()
    if not self._snapshot then return nil end
    local rec = cachedRecord(self._characterKey, self._which)
    return rec and rec.seen or nil
end

--- The bag ids this grid shows, in order.
-- @return table
function GridMeta:GetContainers()
    local out = {}
    for i, id in ipairs(self._containers) do out[i] = id end
    return out
end

--- Whether a geometry change is waiting for combat to end.
-- @return bool
function GridMeta:IsDeferred()
    return self._pending ~= nil
end

--- How many slots are occupied, free and total.
-- @return number used
-- @return number free
-- @return number total
function GridMeta:GetCounts()
    local used, total = 0, 0
    for _, e in ipairs(self._entries) do
        total = total + 1
        if e.info then used = used + 1 end
    end
    return used, total - used, total
end

-- One invisible holder per bag, whose ONLY job is to carry the bag id: a cell reads its bag from
-- its parent's GetID(), because that is where the Blizzard template's own click handler reads it.
-- Stretched over the grid so it has a real rect -- a cell parented to a frame with no rect resolves
-- no geometry, which is the failure mode LAYOUT_SYSTEM.md calls out.
function GridMeta:_holder(bag)
    local h = self._holders[bag]
    if h then return h end
    h = CreateFrame("Frame", nil, self._f)
    h:SetID(bag)
    self._holderBox:Add(h, { align = "stretch", valign = "stretch" })
    self._holders[bag] = h
    return h
end

function GridMeta:_destroyCells()
    for _, perBag in pairs(self._cells) do
        for _, c in pairs(perBag) do c:Destroy() end
    end
    self._cells = {}
    self._entries = {}
    self._cellBox:Clear()
end

-- Builds the cell for one slot, creating it on first use.
function GridMeta:_cell(bag, slot)
    local perBag = self._cells[bag]
    if not perBag then perBag = {} self._cells[bag] = perBag end
    local c = perBag[slot]
    if c then return c end
    c = SuuUI.Components.ItemSlot({
        bag = bag, slot = slot, size = self._cellSize,
        -- The KIND is fixed at construction, because a snapshot cell has no template and a live one
        -- does. That is why SetCharacter destroys the cells rather than re-pointing them.
        snapshot = self._snapshot or nil,
        name = self._namePrefix and (self._namePrefix .. bag .. "Item" .. slot) or nil,
    }, self:_holder(bag))
    if self._readOnly then c:SetReadOnly(true) end
    perBag[slot] = c
    return c
end

-- Re-reads every slot the containers report and rebuilds the entry list. Does NOT re-order.
function GridMeta:_readEntries()
    local seen = {}
    -- A SNAPSHOT READS THE CACHE, and it reads the SLOT COUNT from there too. Asking the client how
    -- many slots bag 3 has would answer for whoever is logged in, so an alt with a 20-slot bag would
    -- render against your own 16 -- four items silently missing, with nothing on screen to say so.
    local snap = self._snapshot and cachedRecord(self._characterKey, self._which) or nil
    local snapSlots = snap and snap.slots or nil
    for _, bag in ipairs(self._containers) do
        local n
        if self._snapshot then
            n = 0
            local perBag = snapSlots and snapSlots[bag]
            if perBag then
                -- The cache stores only occupied slots, so the count is the highest index present.
                for slot in pairs(perBag) do if slot > n then n = slot end end
            end
        else
            n = numSlots(bag) or 0
        end
        seen[bag] = n
        for slot = 1, n do
            local c = self:_cell(bag, slot)
            if self._snapshot then
                c:SetItem(cachedInfo(snapSlots and snapSlots[bag] and snapSlots[bag][slot]))
            else
                c:Refresh()
            end
        end
    end
    -- Drop cells for slots that no longer exist -- a smaller bag was equipped.
    for bag, perBag in pairs(self._cells) do
        local keep = seen[bag]
        for slot, c in pairs(perBag) do
            if not keep or slot > keep then
                c:Destroy()
                perBag[slot] = nil
            end
        end
    end
    -- PRESERVE the current order. Rebuilding in container order would silently undo the sort on
    -- every repaint, so looting would shuffle the grid under the player's cursor -- which is the
    -- exact behaviour the "repaint without re-sorting" rule exists to prevent. Existing entries
    -- keep their positions; genuinely new slots are appended.
    local entries, have = {}, {}
    for _, e in ipairs(self._entries) do
        local cell = self._cells[e.bag] and self._cells[e.bag][e.slot]
        if cell then
            e.cell, e.info = cell, cell:GetItem()
            entries[#entries + 1] = e
            have[e.bag .. ":" .. e.slot] = true
        end
    end
    for _, bag in ipairs(self._containers) do
        for slot = 1, (seen[bag] or 0) do
            if not have[bag .. ":" .. slot] then
                local cell = self._cells[bag] and self._cells[bag][slot]
                if cell then
                    entries[#entries + 1] =
                        { bag = bag, slot = slot, cell = cell, info = cell:GetItem() }
                end
            end
        end
    end
    local grew = #entries ~= #self._entries
    self._entries = entries
    return grew
end

-- Places the cells in the current entry order. Container:Add is MEMBERSHIP, not upsert, so each
-- cell is removed before being re-added -- adding twice would grow the child list without bound.
function GridMeta:_place()
    local box = self._cellBox
    for _, e in ipairs(self._entries) do box:Remove(e.cell) end
    for _, e in ipairs(self._entries) do
        box:Add(e.cell, { width = self._cellSize, height = self._cellSize })
        e.cell:Show()
    end
    self:_resize()
end

function GridMeta:_resize()
    local cols = self._cols
    local gap  = self._spacing
    local pad  = self._padding
    local w = cols * self._cellSize + (cols - 1) * gap + pad * 2
    local rows = ceil(#self._entries / cols)
    if rows < 1 then rows = 1 end
    local h = rows * self._cellSize + (rows - 1) * gap + pad * 2
    self._f:SetSize(w, h)
end

-- Every geometry pass funnels through here, so the combat guard exists in ONE place. A grid holds
-- protected cells by construction, so the client refuses SetSize on the grid and SetPoint on each
-- cell while InCombatLockdown() -- and a bag gaining a slot mid-fight is ordinary, not exotic.
function GridMeta:_apply(what)
    if inCombat() then
        self._pending = self._pending or {}
        self._pending[what] = true
        return false
    end
    self._pending = nil
    if what == "rebuild" then
        -- The container swap happens HERE, not when SetContainers was called. Destroying the cells
        -- up front would leave the grid empty for the rest of the fight, showing nothing instead of
        -- showing the previous set until it can rebuild.
        if self._nextContainers then
            self._containers = self._nextContainers
            self._nextContainers = nil
            self:_destroyCells()
        end
        self:_readEntries()
        self:Sort()
        S:Emit(self, GRID_SIGNALS.CHILDREN_CHANGED)
    else
        self:_place()
    end
    return true
end

--- Re-reads every slot and repaints, WITHOUT re-ordering.
--
-- Order is deliberately left alone: re-sorting on every BAG_UPDATE would move items out from under
-- the player's cursor while they loot.
function GridMeta:Refresh()
    local grew = self:_readEntries()
    self:_applyFilter()
    -- A slot count that changed needs placement, and placement is geometry -- so it goes through
    -- the combat guard rather than being done inline.
    if grew then self:_apply("place") end
end

--- Points the grid at a different set of containers.
--
-- Destroys and rebuilds every cell, because a cell's bag is fixed by its parent and cannot be
-- re-pointed. Emits CHILDREN_CHANGED once the rebuild lands, which may be after combat ends -- and
-- until then the grid keeps showing the set it already had.
-- @param ids table  ordered bag ids
function GridMeta:SetContainers(ids)
    local next_ = {}
    for i, id in ipairs(ids or {}) do next_[i] = id end
    self._nextContainers = next_
    self:_apply("rebuild")
end

--- Re-orders the grid by the current sort mode.
function GridMeta:Sort()
    local cmp = SORTS[self._sortMode] or SORTS.quality
    tsort(self._entries, cmp)
    self:_place()
    self:_applyFilter()
end

--- @param mode string  "quality" | "name" | "slot"
function GridMeta:SetSortMode(mode)
    if not SORTS[mode] then return false end
    if self._sortMode == mode then return false end
    self._sortMode = mode
    self:Sort()
    return true
end

--- @return string
function GridMeta:GetSortMode() return self._sortMode end

function GridMeta:_applyFilter()
    local q = self._filter
    for _, e in ipairs(self._entries) do
        if not q or q == "" then
            e.cell:SetDimmed(false)
            -- Neither state with no query. A ring left lit from the previous search would go on
            -- marking cells as matching a filter that is no longer there.
            e.cell:SetMatched(false)
        else
            local name = e.info and e.info.itemName
            -- An UNRESOLVED item has no name to match, so it is dimmed rather than counted as a
            -- miss: claiming it does not match would be a claim we cannot support.
            local hit = name and strfind(strlower(name), q, 1, true) ~= nil
            e.cell:SetDimmed(not hit)
            -- TWO cues, not one. The concept dims what does not match AND rings what does; dimming
            -- alone leaves the eye to pick the bright cells out of eighty, which is the work the
            -- ring removes.
            e.cell:SetMatched(hit and true or false)
        end
    end
end

--- Dims every cell that does not match, leaving the layout untouched.
-- @param text string|nil
function GridMeta:SetFilter(text)
    self._filter = (text and text ~= "") and strlower(text) or nil
    self:_applyFilter()
end

--- @return string|nil
function GridMeta:GetFilter() return self._filter end

--- How many cells currently match the filter. Counts only cells with a name to match.
-- @return number
function GridMeta:CountMatches()
    if not self._filter then
        local used = self:GetCounts()
        return used
    end
    local n = 0
    for _, e in ipairs(self._entries) do
        if not e.cell:IsDimmed() and e.info then n = n + 1 end
    end
    return n
end

--- Makes every cell inert, or live again.
-- @param on bool
function GridMeta:SetReadOnly(on)
    self._readOnly = on and true or false
    for _, e in ipairs(self._entries) do e.cell:SetReadOnly(self._readOnly) end
end

--- @return bool
function GridMeta:IsReadOnly() return self._readOnly end

--- @param n number  columns
function GridMeta:SetColumns(n)
    if type(n) ~= "number" or n < 1 or n == self._cols then return end
    self._cols = n
    self:_apply("place")
end

--- @param n number  cell side
function GridMeta:SetCellSize(n)
    if type(n) ~= "number" or n < 1 or n == self._cellSize then return end
    self._cellSize = n
    for _, e in ipairs(self._entries) do e.cell:SetSize(n, n) end
    self:_apply("place")
end

function GridMeta:ApplyTheme()
    for _, e in ipairs(self._entries) do
        if e.cell.ApplyTheme then e.cell:ApplyTheme() end
    end
end

function GridMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._events then
        self._events:UnregisterAllEvents()
        self._events:SetScript("OnEvent", nil)
    end
    self:_destroyCells()
    if self._cellBox then self._cellBox:Destroy() end
    if self._holderBox then self._holderBox:Destroy() end
    self._f:Hide()
end

SuuUI.Components.InstallBase(GridMeta, "_f")

--- Creates a flat combined grid of bag slots.
--
-- @param props table  { containers, cols, cellSize, spacing, padding, sortMode, readOnly,
--                       namePrefix }
--   containers: ordered bag ids. Required.
--   cols:       columns. Required -- it decides the grid's width, which is what wrapping uses.
--   cellSize:   cell side. Required; a cell's size is a plugin setting, not a theme token.
-- @param parent frame
-- @return table  ItemGrid handle
function SuuUI.Components.ItemGrid(props, parent)
    props = props or {}
    assert(type(props.containers) == "table", "SuuUI: ItemGrid needs a containers list")
    assert(type(props.cols) == "number" and props.cols >= 1, "SuuUI: ItemGrid needs cols")
    assert(type(props.cellSize) == "number", "SuuUI: ItemGrid needs a cellSize")

    local f = CreateFrame("Frame", props.name, parent)

    local handle
    f:SetScript("OnSizeChanged", function(_, w, h)
        if not handle then return end
        S:Emit(handle, S.SIGNALS.SIZE_CHANGED, w, h)
    end)

    -- TWO containers on one host, as ActionBarGrid does: the holders are stretched over the whole
    -- grid while the cells wrap. No frame is in both, so there is no shared layout-props table --
    -- which is the trap that once pinned every docked bar to the top of the screen.
    local holderBox = SuuUI.Layout:CreateContainer({ host = f, layout = "stack" })
    local spacing = props.spacing or T:GetToken("spaceXxs") or 2
    local padding = props.padding or 0
    local cellBox = SuuUI.Layout:CreateContainer({
        host = f, layout = "flow", dir = "horizontal", wrap = true,
        gap = spacing, lineGap = spacing,
        padding = { top = padding, right = padding, bottom = padding, left = padding },
    })

    local id = "itemgrid_" .. tostring(f)
    handle = setmetatable({
        _f          = f,
        _holderBox  = holderBox,
        _cellBox    = cellBox,
        _holders    = {},
        _cells      = {},
        _entries    = {},
        _containers = {},
        _cols       = props.cols,
        _cellSize   = props.cellSize,
        _spacing    = spacing,
        _padding    = padding,
        _sortMode   = SORTS[props.sortMode] and props.sortMode or "quality",
        _readOnly   = props.readOnly and true or false,
        -- The SOURCE. nil character means the live client; a key means that character's cached record,
        -- and `which` names the container inside it. Both are construction-time defaults that
        -- SetCharacter then owns.
        _snapshot     = props.character ~= nil,
        _characterKey = props.character,
        _which        = props.which,
        _namePrefix = props.namePrefix,
        _filter     = nil,
        _eid        = id,
    }, GridMeta)

    -- ONE event frame for the whole grid rather than one per cell: eighty cells watching BAG_UPDATE
    -- would be eighty dispatches for one change.
    local events = CreateFrame("Frame")
    handle._events = events
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Catch up on whatever combat refused, cells included.
            for _, e in ipairs(handle._entries) do e.cell:ApplyPending() end
            local pending = handle._pending
            handle._pending = nil
            if pending then
                handle:_apply(pending.rebuild and "rebuild" or "place")
            end
        else
            handle:Refresh()
        end
    end)
    for _, e in ipairs({ "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
                         "PLAYERBANKSLOTS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        -- pcall'd for the same reason the action bars do it: an event this client does not know
        -- must not take the grid down at construction.
        pcall(events.RegisterEvent, events, e)
    end

    handle:SetContainers(props.containers)
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end
