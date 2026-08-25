-- The inventory window: one flat combined grid of every bag slot, a search row and a footer.
--
-- ONE WINDOW COMPONENT, INSTANTIATED MORE THAN ONCE LATER. This is written from the start as
-- `{ character, container }` rather than as "the bags window", because the bank session shows two of
-- these side by side and a snapshot of an alt is the same renderer again. Phase 5 only ever builds
-- the live-bags case; the parameters exist so the later phases add callers rather than a second
-- widget.
--
-- WHAT IS DELIBERATELY NOT HERE YET, and why. No character dropdown: it would list exactly one
-- character and switch nothing. No Bags/Bank segment: the Bank half would show an empty grid,
-- because bank slots are not readable away from a banker. No sell button: selling needs the vendor
-- probe answered first. A control that renders and does nothing is the worst of the three states a
-- control can be in -- worse than absent -- so each arrives with the feature it drives.
local type, ipairs, floor = type, ipairs, math.floor

local S = SuuUI.UISignals
local T = SuuUI.Theme
local C = SuuUI.Components

local PLUGIN_ID = "inventory"

local M = {}
local WindowMeta = {}
WindowMeta.__index = WindowMeta

-- Sort options, shared with the settings page so the two cannot disagree about what exists.
M.SORT_OPTIONS = {
    { value = "quality", label = "Quality" },
    { value = "name",    label = "Name" },
    { value = "slot",    label = "Bag order" },
}

local function get(key)
    return SuuUI.Settings:Get(PLUGIN_ID, key)
end

--- The bag ids a container name covers, read from the client rather than hardcoded.
--
-- Measured 4 bag slots and 7 bank bags on this build, but a backport that adds one would silently
-- drop a whole container from the grid if these were literals.
-- @param which string  "bags" | "bank"
-- @return table
function M.containerIds(which)
    if which == "bank" then
        local first = (NUM_BAG_SLOTS or 4) + 1
        local n = NUM_BANKBAGSLOTS or 7
        local out = { -1 }
        for i = first, first + n - 1 do out[#out + 1] = i end
        return out
    end
    local out = {}
    for i = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = i end
    return out
end

--- Re-sorts the grid using the mode configured in settings.
--
-- It does NOT choose or change the mode. `sort_mode` is a settings dropdown with a live applier, so
-- the settings page already owns which order the grid is in -- a button that cycled it was a second
-- owner of one value, and the two could disagree about what the player had chosen. This is a plain
-- "sort now": the useful action after looting, since Refresh deliberately repaints WITHOUT re-sorting
-- so cells cannot move under the cursor mid-loot.
--
-- No Settings:Set, so nothing is written and no watcher cascade runs.
function WindowMeta:SortNow()
    self._grid:Sort()
end

--- Scans for junk and asks before selling any of it.
--
-- The confirmation is not politeness. Selling is IRREVERSIBLE once the vendor's twelve buyback slots
-- overflow, a flat grid has no junk section to inspect first, and a grey can be a quest item or a
-- vendor-recipe carrier -- so the modal naming the count and the value is the only place the player sees
-- what is about to go.
function WindowMeta:SellJunk()
    local Sell = SuuUI._Inventory and SuuUI._Inventory.Sell
    if not Sell then return end
    if not Sell.AtMerchant() then return end

    local list, total, unknown = Sell.Scan(M.containerIds(self._which))
    if #list == 0 then
        C.Notice({ title = "Nothing to sell", message = "No grey items a vendor will take.",
                   tone = "warning" })
        return
    end

    -- "at least" when any price is unknown, rather than quietly under-reporting: GetItemInfo may not
    -- have cached a price this session, and a total that is silently short is worse than a hedged one.
    local value = SuuUI.Readout.Money(total, { groupThousands = true, spaceUnits = true })
    local worth = unknown and ("at least " .. (value or "0c")) or (value or "0c")
    C.Modal({
        title          = "Sell Junk",
        message        = ("Sell %d grey item%s for %s?\n\nThe vendor keeps only 12 buyback slots.")
                            :format(#list, #list == 1 and "" or "s", worth),
        confirmText    = "Sell",
        confirmVariant = "danger",
        onConfirm      = function()
            Sell.Start(list, function()
                if self._grid then self:Refresh() end
                self:_updateFooter()
            end)
        end,
    }):Show()
end

--- Enables the sell button only where selling is possible.
function WindowMeta:_syncSell()
    if not self._sellBtn then return end
    local Sell = SuuUI._Inventory and SuuUI._Inventory.Sell
    self._sellBtn:SetEnabled(Sell and Sell.AtMerchant() and not Sell.IsRunning() or false)
end

function WindowMeta:_updateFooter()
    local used, free, total = self._grid:GetCounts()
    -- Concept spelling: "1,284 g 42 s 18 c" -- the figure in the footer's own text colour and only
    -- the UNIT LETTER in its coin colour, grouped and spaced. This is the readout where money is the
    -- subject, so it opts into all three; a vendor price in a tooltip stays dense and uncoloured.
    self._moneyText:SetText(SuuUI.Readout.Money(GetMoney and GetMoney() or 0, {
        colored = true, groupThousands = true, spaceUnits = true,
    }))
    self._slotsText:SetText(free .. " free / " .. total)
    self:_syncSell()
    self._used = used
end

function WindowMeta:_updateMatchCount()
    local q = self._grid:GetFilter()
    if not q then
        self._matchText:SetText("")
        self._matchText:Hide()
        return
    end
    self._matchText:SetText(self._grid:CountMatches() .. " shown")
    self._matchText:Show()
end

--- Re-reads the containers and repaints. Does not re-order, for the reason the grid does not.
function WindowMeta:Refresh()
    self._grid:Refresh()
    self:_updateFooter()
    self:_updateMatchCount()
end

--- Resizes the window to whatever the grid now needs.
--
-- The GRID is the thing whose size is decided by settings (columns times cell size), so the window
-- follows it rather than the other way round -- a window with its own width would either clip the
-- last column or leave a gutter whenever either setting changed.
function WindowMeta:_fit()
    local gw, gh = self._grid:GetWidth(), self._grid:GetHeight()
    local pad = T:GetToken("spaceSm") or 8

    -- THE PLATE IS SIZED FROM THE GRID, not hugged to it. A host container adopts the frame it is
    -- given, and that frame -- a styled Frame component -- already carries a size, so the container
    -- treats it as explicit and never shrinks to its content: the plate stayed at the Frame's default
    -- height and the window came out 95 units tall with the cells hanging out of the bottom. The
    -- grid's own size is authoritative anyway, so deriving from it is both correct and cheaper than
    -- a hug. This is container API, not a raw SetPoint.
    if self._plateBox then
        self._plateBox:SetSize(gw + pad * 2, gh + pad * 2)
    end

    -- Re-layout BEFORE measuring, so the column's content size reflects the plate we just sized
    -- rather than the size it had on the previous pass. Relying on the resize signal instead would
    -- read one pass stale on the first fit, which is the pass that decides the opening size.
    self._col:Layout()

    -- MEASURE THE COLUMN, DO NOT RE-DERIVE IT. This used to sum the grid plus GetControlHeight for
    -- the search row and the footer -- and both of those rows HUG their content, so a token height
    -- over-reserved them by around thirteen units between them. A vertical flow packs from the top,
    -- so the surplus landed BELOW the footer as dead space: the window was too tall and the footer sat
    -- too high inside it. Asking the container what it actually laid out cannot drift from what is on
    -- screen, which is the same reason the tooltip reads real line objects rather than re-deriving
    -- them. GetContentSize includes the column's padding, so nothing is added for it here.
    local _, contentH = self._col:GetContentSize()

    -- ...but SetSize sizes the WINDOW, and a window is its content PLUS its chrome -- the title bar
    -- most of it. Passing a content height straight through left the content area short by exactly
    -- sizeTitleBar and squeezed the footer off the bottom, which is the other half of this bug. The
    -- chrome is MEASURED as window-minus-content rather than adding the token, so it stays correct if
    -- the title bar's height changes or a border is added. GetContentSize can report 0 before the
    -- window has ever been laid out, which would make the delta the whole window and double the size,
    -- so that case falls back to the token it would otherwise have measured.
    local cw, ch = self._win:GetContentSize()
    local ww, wh = self._win:GetWidth() or 0, self._win:GetHeight() or 0
    local chromeW, chromeH
    if type(cw) == "number" and cw > 0 and type(ch) == "number" and ch > 0 then
        chromeW, chromeH = ww - cw, wh - ch
    else
        chromeW, chromeH = 0, T:GetToken("sizeTitleBar") or 26
    end

    -- The grid now sits inside the plate, so the window has to carry the plate's inset as well as the
    -- column's padding, or the plate's border cuts into the last column.
    self._win:SetSize(gw + pad * 4 + chromeW, contentH + chromeH)
end

--- @return table  the underlying SuuUI window handle
function WindowMeta:GetWindow() return self._win end

--- @return table  the ItemGrid handle
function WindowMeta:GetGrid() return self._grid end

-- SORT ON OPEN, and only on open. ItemGrid:Refresh deliberately repaints WITHOUT re-sorting, so that
-- looting cannot shuffle cells out from under the player's cursor -- but that rule cut both ways: the
-- first paint sorted while every cell was still empty, and since a repaint preserves the existing
-- order, the grid kept raw bag order for the rest of the session. That is what left the items in two
-- blocks with empty rows stranded between them: the two bags that happened to be empty sat in the
-- middle of the container order and nothing ever packed past them.
--
-- Opening the window is the one moment a re-sort is unambiguously safe -- there is no cursor mid-drag
-- and no loot in flight -- which is also why every bag addon sorts on open rather than on update.
function WindowMeta:Show()
    self._win:Show()
    self:Refresh()
    self._grid:Sort()
    self:_fit()
    self:_updateFooter()
end
function WindowMeta:Hide() self._win:Hide() end
function WindowMeta:IsShown() return self._win:IsShown() end

function WindowMeta:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

function WindowMeta:ApplyTheme()
    if self._grid then self._grid:ApplyTheme() end
    self:_fit()
end

function WindowMeta:Destroy()
    S:DisconnectAll(self)
    SuuUI.Events:Off("SUUUI_THEME_CHANGED", self._eid)
    if self._grid then self._grid:Destroy() end
    if self._search then self._search:Destroy() end
    if self._sortDrop then self._sortDrop:Destroy() end
    if self._matchText then self._matchText:Destroy() end
    if self._moneyText then self._moneyText:Destroy() end
    if self._slotsText then self._slotsText:Destroy() end
    if self._sellBtn then
        if self._win.RemoveTitleAccessory then self._win:RemoveTitleAccessory(self._sellBtn) end
        self._sellBtn:Destroy()
    end
    -- Removed from the title bar BEFORE it is destroyed: the window recomputes its title and drag
    -- gutters from the accessory list, and one holding a destroyed handle would keep reserving space
    -- for a button that is gone.
    if self._sortBtn then
        if self._win.RemoveTitleAccessory then self._win:RemoveTitleAccessory(self._sortBtn) end
        self._sortBtn:Destroy()
    end
    if self._searchDivider then self._searchDivider:Destroy() end
    if self._footDivider then self._footDivider:Destroy() end
    if self._plateBox then self._plateBox:Destroy() end
    if self._plate then self._plate:Destroy() end
    if self._win then self._win:Hide() end
end

--- Builds one inventory window.
--
-- @param props table  { container, title }
--   container: "bags" | "bank". Defaults to "bags".
-- @return table  handle
function M.New(props)
    props = props or {}
    local which = props.container == "bank" and "bank" or "bags"

    local win = SuuUI.Layout:CreateWindow({
        id        = "inventory_" .. which,
        title     = props.title or (which == "bank" and "Bank" or "Inventory"),
        w         = 400,
        h         = 300,
        resizable = false,
        centered  = true,
        -- GLASS, which is what the concept specifies for this surface: its `.win` is a vertical
        -- gradient from 85% down to 30% opacity with a 10%-white inset highlight along the top
        -- edge, which is Backdrop.Glass exactly -- `colorGlass` / `colorGlassFade` /
        -- `colorGlassSheen` already carry those three values. A flat `colorBg` panel was standing
        -- in for it.
        glass     = true,
    })

    local content = win:GetContentFrame()
    local pad = T:GetToken("spaceSm") or 8
    local gap = T:GetToken("spaceXs") or 4

    local col = SuuUI.Layout:CreateContainer({
        parent  = content,
        layout  = "flow",
        dir     = "vertical",
        gap     = gap,
        fill    = true,
        padding = { top = pad, right = pad, bottom = pad, left = pad },
    })

    -- SEARCH GETS ITS OWN ROW rather than a slot in the title bar. The title bar will carry the
    -- character dropdown and the scope switch in later phases, and a search field squeezed in beside
    -- them is about 90px wide -- which truncates the moment a real item name is typed. Its own band
    -- also means it does not move when the window changes state.
    local searchRow = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = gap, align = "center",
    })

    -- PLACEHOLDER INSIDE THE FIELD, as the concept draws it. This was a label sitting OUTSIDE the
    -- box because Input had no placeholder; it does now, and the hint is deliberately not the edit
    -- box's text, so the search filter never sees it as a query.
    --
    -- A PILL WITH A LEADING MAGNIFIER, which is the concept's `.srch` exactly: `border-radius:10px`
    -- on a 19-unit field is a stadium, not a rounded rectangle, and the glyph sits inside the field
    -- rather than beside it. The magnifier is atlas art from Media/ui-icons.tga rather than the
    -- pictograph character, because this client's faces do not all carry one and a face missing it
    -- draws a box -- the same reason Dropdown and Accordion spend ASCII on their arrows. That art
    -- did not exist when this row was first built, which is why the field was square and bare.
    local searchPath, searchCoords = SuuUI.Icons:Get("search")
    local search = C.Input({
        placeholder = "Search items...",
        pill        = true,
        icon        = searchPath,
        iconCoords  = searchCoords,
        clearable   = true,
    }, searchRow:GetFrame())
    -- SORT LIVES IN THE TITLE BAR, as an icon, which is what the concept draws -- and it is why the
    -- search field there is full width instead of sharing its row with a 110px dropdown.
    --
    -- It CYCLES rather than opening a menu. A menu is the better control for a long list; this list is
    -- three entries, and a menu would cost a second click plus a panel to dismiss. The objection to
    -- cycling is real though -- a mode you cannot see is a mode you cannot trust -- so the active mode
    -- is NAMED in the footer. That is the trade, not an oversight.
    --
    -- Parented to the content frame and then handed to the window: AddTitleAccessory reparents it into
    -- the title strip and raises it above the drag surface, which a button merely anchored there would
    -- sit underneath and never receive a click.
    -- SELL JUNK IS A TITLE-BAR ICON IN THE DANGER COLOUR, which is what the concept draws: the title
    -- bar carries the sort and sell icons beside the close button, and the footer stays money plus
    -- free/total. It was a footer Button first, which put a labelled control where the concept has a
    -- clean readout row.
    --
    -- ON THE BAGS WINDOW ONLY. The bank window has none at all rather than a disabled one: you can
    -- never sell from a bank, and a greyed control says "not right now" when the truth is "never here".
    -- Away from a merchant, though, "not right now" IS the truth -- so on the bags window it is present
    -- and DISABLED, which is the distinction those two cases turn on.
    local sellBtn
    if which == "bags" then
        local coinPath, coinCoords = SuuUI.Icons:Get("coin")
        sellBtn = C.IconButton({
            icon = coinPath, coords = coinCoords, iconColor = "colorDanger",
            scalePop = false,   -- a strip accessory must not scale, or it slides
        }, content)
    end

    local sortPath, sortCoords = SuuUI.Icons:Get("sort")
    local sortBtn = C.IconButton({
        icon      = sortPath,
        coords    = sortCoords,
        -- ACCENT, which is what the concept gives the sort icon (`.ibtn.acc`) against the sell
        -- icon's danger and the close button's muted. Sorting is the affordance the window
        -- advertises, so it is the one control that is coloured rather than quiet.
        iconColor = "colorAccent",
        -- NO PRESS POP. Reported in game: the button slid out to the right when clicked. A title-bar
        -- accessory is held at a token inset from the strip's right edge, and SetScale reinterprets
        -- that offset in the frame's own scaled space -- so the pop moves it sideways instead of
        -- growing it in place. Button's own prop comment names this exact case: "for chrome in a
        -- strip it would overflow".
        scalePop  = false,
    }, content)
    local matchText = C.Text({ text = "", size = "sm", color = "accent", wrap = false },
                             searchRow:GetFrame())

    searchRow:Add(search, { width = "fill" })
    searchRow:Add(matchText, { width = "auto" })

    local grid = C.ItemGrid({
        containers = M.containerIds(which),
        cols       = get("columns") or 10,
        cellSize   = get("cell_size") or 34,
        spacing    = T:GetToken("spaceXxs") or 2,
        sortMode   = get("sort_mode") or "quality",
        namePrefix = "SuuUI_inventory_" .. which .. "_",
    }, content)

    -- THE GRID SITS ON ITS OWN PLATE. In the concept the cells are on a distinct inset surface with
    -- its own edge, not floating on the window background -- which is what gives the window three
    -- readable bands (search / items / totals) instead of one field of icons. A styled Frame supplies
    -- the surface and a host container supplies the inset, so no geometry is stated here.
    local plateFrame = C.Frame({ variant = "bgAlt", rounded = true }, content)
    local plate = SuuUI.Layout:CreateContainer({
        host   = plateFrame:GetFrame(),
        layout = "flow",
        dir    = "vertical",
        padding = { top = pad, right = pad, bottom = pad, left = pad },
    })
    -- NO width prop, for the same reason the grid itself has none: the grid's width is authoritative
    -- and the window is sized from it, so the plate hugs the grid rather than the reverse.
    plate:Add(grid)

    -- THREE HAIRLINES, which is what the concept draws: under the title bar (the window's own
    -- chrome), under the search row, and above the footer. The search one was missing, so the field
    -- and the grid ran together as one band.
    local searchDivider = C.Divider({}, content)
    local footDivider = C.Divider({}, content)

    local footer = SuuUI.Layout:CreateContainer({
        parent = content, layout = "flow", dir = "horizontal",
        gap = gap, align = "center",
    })
    local moneyText = C.Text({ text = "", size = "sm", color = "text", wrap = false },
                             footer:GetFrame())
    local slotsText = C.Text({ text = "", size = "sm", color = "muted", justify = "RIGHT",
                               wrap = false }, footer:GetFrame())
    footer:Add(moneyText, { width = "fill" })
    footer:Add(slotsText, { width = "auto" })

    col:Add(searchRow, { width = "fill" })
    col:Add(searchDivider, { width = "fill" })
    -- The PLATE goes in, not the grid: the grid is inside it. Still no width prop -- the grid's width
    -- is AUTHORITATIVE (columns times cell size) and the window is sized from it, so stretching either
    -- one would make the two define each other. That produced a 16px window once.
    col:Add(plate)
    col:Add(footDivider, { width = "fill" })
    col:Add(footer, { width = "fill" })

    local id = "inventorywindow_" .. which
    local handle = setmetatable({
        _win       = win,
        _col       = col,
        _plate     = plateFrame,
        _plateBox  = plate,
        _footDivider = footDivider,
        _searchDivider = searchDivider,
        _grid      = grid,
        _search    = search,
        _sortBtn   = sortBtn,
        _matchText = matchText,
        _moneyText = moneyText,
        _footer    = footer,
        _slotsText = slotsText,
        _sellBtn   = sellBtn,
        _which     = which,
        _eid       = id,
    }, WindowMeta)

    -- Live filtering, on TEXT_CHANGED rather than SUBMITTED: a bag search that only applies on
    -- Enter makes you commit to a guess before seeing whether it matched.
    S:Connect(search, S.SIGNALS.TEXT_CHANGED, function(text)
        grid:SetFilter(text)
        handle:_updateMatchCount()
    end)

    S:Connect(sortBtn, S.SIGNALS.CLICKED, function()
        handle:SortNow()
    end)

    if sellBtn then
        S:Connect(sellBtn, S.SIGNALS.CLICKED, function() handle:SellJunk() end)
    end

    -- Into the title bar, which reparents it and raises it above the drag surface. Done AFTER the
    -- handle exists, because the click needs a handle to cycle.
    if sellBtn then win:AddTitleAccessory(sellBtn) end
    win:AddTitleAccessory(sortBtn)

    -- The window follows the grid: a settings change moves the grid's size, and the window has to
    -- re-fit or it clips the last column.
    S:Connect(grid, S.SIGNALS.SIZE_CHANGED, function()
        handle:_fit()
        handle:_updateFooter()
    end)

    handle:_fit()
    handle:Refresh()
    win:Hide()
    SuuUI.Events:On("SUUUI_THEME_CHANGED", function() handle:ApplyTheme() end, id)
    return handle
end

SuuUI._InventoryWindow = M
