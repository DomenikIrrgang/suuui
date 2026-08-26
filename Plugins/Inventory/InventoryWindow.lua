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
    -- Labelled "Quality + Type", not "Type", because quality is still the PRIMARY key -- a rare trade
    -- good outranks an uncommon weapon and category only groups within a band. A label reading "Type"
    -- would promise all weapons together regardless of quality, which is a different ordering.
    { value = "quality_type", label = "Quality + Type" },
    { value = "name",    label = "Name" },
    { value = "slot",    label = "Bag order" },
}

-- Which end of the grid the sorted run packs against. `end` is what ElvUI does in its shipped
-- defaults, which is the reason this is offered rather than fixed: it also reverses the order inside
-- each mode, so the two produce the same grid rather than merely a similar one. Labelled by where the
-- ITEMS end up, not where the free slots do -- that is the half a player is looking at.
M.SORT_POSITIONS = {
    { value = "start", label = "Start of Bags" },
    { value = "end",   label = "End of Bags" },
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

    local function sell()
        Sell.Start(list, function()
            if self._grid then self:Refresh() end
            self:_updateFooter()
        end)
    end

    -- SKIPPING THE DIALOG IS A REAL CHOICE, not a shortcut we talked the player out of. Someone who
    -- clears greys after every run has already read this dialog fifty times, and a confirmation that is
    -- always accepted trains the reflex that makes the one dangerous case slip through. The setting
    -- defaults ON and the schema says why.
    --
    -- The count and the value still reach them, in chat rather than in a modal: with no dialog, that
    -- line is the only record of what just went, and "sold 14 greys for 3g 22s" is what a player checks
    -- when they realise something is missing.
    if get("sell_confirm") == false then
        SuuUI.Fault(("SuuUI: selling %d grey item%s for %s.")
            :format(#list, #list == 1 and "" or "s", worth))
        sell()
        return
    end

    C.Modal({
        title          = "Sell Junk",
        message        = ("Sell %d grey item%s for %s?\n\nThe vendor keeps only 12 buyback slots.")
                            :format(#list, #list == 1 and "" or "s", worth),
        confirmText    = "Sell",
        confirmVariant = "danger",
        onConfirm      = sell,
    }):Show()
end

--- Enables the sell button only where selling is possible.
function WindowMeta:_syncSell()
    if not self._sellBtn then return end
    -- A SNAPSHOT CAN NEVER SELL, whatever the merchant says: the items are another character's and are
    -- not in your bags to sell. Checked first, so standing at a vendor while browsing an alt does not
    -- offer to sell their junk.
    if self:IsSnapshot() then
        self._sellBtn:SetEnabled(false)
        return
    end
    local Sell = SuuUI._Inventory and SuuUI._Inventory.Sell
    self._sellBtn:SetEnabled(Sell and Sell.AtMerchant() and not Sell.IsRunning() or false)
end

--- Rebuilds the character dropdown's options from the cache.
--
-- THE DROPDOWN IS WHERE THE TITLE WAS, which is the concept's own arrangement: a window showing one
-- character's bags does not need a word saying "Inventory" as well as the name of the character whose
-- bags they are. Its options come from ItemCache:Characters(), already ordered current-character first,
-- then the current realm, then everyone else -- so the ordering is not restated here.
--
-- CLASS-COLOURED, and the colour is a GAME FACT rather than a theme token: `Game:ClassColor` prefers
-- the client's own CUSTOM_CLASS_COLORS / RAID_CLASS_COLORS, so SuuUI agrees with the rest of the
-- player's UI including a retinting addon. A character whose class the cache never recorded takes the
-- plain text colour rather than a guess.
function WindowMeta:_rebuildCharacters()
    local dd = self._charDrop
    if not dd then return end
    local IC = SuuUI.ItemCache
    local list = (IC and type(IC.Characters) == "function") and IC:Characters() or {}
    local options, current = {}, nil
    for _, c in ipairs(list) do
        local label = c.name
        local col = c.class and SuuUI.Game:ClassColor(c.class) or nil
        if col then
            label = string.format("|cff%02x%02x%02x%s|r",
                math.floor(col[1] * 255 + 0.5), math.floor(col[2] * 255 + 0.5),
                math.floor(col[3] * 255 + 0.5), c.name)
        end
        -- CROSS-REALM IS SHOWN BUT NEVER IMPLIED TO BE REACHABLE. "Do I have this on my other realm"
        -- is worth answering, so the realm is named on anything that is not the current one -- and
        -- nothing in this window offers to move an item, so naming it cannot promise a transfer.
        if not c.isCurrent and c.realm and c.realm ~= self._realm then
            label = label .. " |cff808594(" .. c.realm .. ")|r"
        end
        options[#options + 1] = { value = c.key, label = label }
        if c.isCurrent then current = c.key end
    end
    dd:SetOptions(options)
    dd:SetValue(self._characterKey or current or nil)
end

--- Points this window at a character's cached contents, or back at the live client.
--
-- ONE RULE DECIDES LIVE VS SNAPSHOT, and it is the concept's: your own bags are always live, your own
-- bank is live only while the bank frame is open, and any other character is always a snapshot. This
-- function is only told WHICH character; the rule is applied here so a caller cannot get it wrong, and
-- so the odd combination the concept calls out -- pointing the BANK window at an alt while standing at
-- a banker -- correctly becomes a read-only snapshot rather than a special case.
-- @param key string|nil  character key, or nil for the current character
function WindowMeta:SetCharacter(key)
    local IC = SuuUI.ItemCache
    local currentKey = (IC and type(IC.CurrentKey) == "function") and IC:CurrentKey() or nil
    local isSelf = (key == nil) or (key == currentKey)
    local live = isSelf and (self._which == "bags"
        or (IC and type(IC.IsBankOpen) == "function" and IC:IsBankOpen()))

    self._characterKey = (not isSelf) and key or nil
    -- NOT `live and nil or key`. That idiom cannot express nil: `x and nil` is falsy, so the `or`
    -- branch always runs and a live window was handed a character key -- which made "go back to my own
    -- bags" silently stay on the alt.
    if live then
        self._grid:SetCharacter(nil)
    else
        self._grid:SetCharacter(key or currentKey, self._which)
    end
    self:_applySnapshotState(not live)
    self:_rebuildCharacters()
    self:_updateFooter()
    self:_updateMatchCount()
    -- The strip adds a row and a snapshot's grid can be a different size, so the window re-fits.
    self:_fit()
end

--- Switches which container this window shows: "bags" or "bank".
--
-- THE AWAY-FROM-A-BANKER HALF OF THE FEATURE. One window can show one container, so without this the
-- bank is unreachable unless you are standing at a banker -- which is exactly when you least need to
-- look it up. Your own bank away from the frame is a read-only snapshot, by the same single rule
-- SetCharacter applies: live only when it is you AND the container is reachable.
--
-- Delegates to SetCharacter rather than duplicating that rule. Changing container changes a cell's KIND
-- (a live bags cell carries the Blizzard template; a snapshot bank cell carries none), and SetCharacter
-- already owns the destroy-and-rebuild that a kind change requires.
-- @param which string  "bags" | "bank"
-- @return bool  whether anything changed
function WindowMeta:SetScope(which)
    if which ~= "bags" and which ~= "bank" then return false end
    if self._which == which then return false end
    self._which = which
    self._grid:SetContainers(M.containerIds(which))
    -- Re-derives live-vs-snapshot for the NEW container against whoever is selected. Passing the stored
    -- key rather than nil matters: switching scope must not silently jump back to your own character.
    self:SetCharacter(self._characterKey)
    if self._scopeSeg then self._scopeSeg:SetValue(which) end
    return true
end

--- Which container this window is showing.
-- @return string
function WindowMeta:GetScope() return self._which end

--- Shows the muted BAGS / BANK tag instead of the switch, for a live bank session.
--
-- The concept hides the segment once both windows are up: there is nothing left to switch, and leaving a
-- live control whose container is fixed is how you ship something that appears to do nothing.
-- @param paired bool
function WindowMeta:SetPaired(paired)
    self._paired = paired and true or false
    if self._scopeSeg then
        if self._paired then self._scopeSeg:Hide() else self._scopeSeg:Show() end
    end
    if self._scopeTag then
        if self._paired then
            self._scopeTag:SetText(self._which == "bank" and "BANK" or "BAGS")
            self._scopeTag:Show()
        else
            self._scopeTag:Hide()
        end
    end
end

--- Whether this window is showing a cached snapshot.
-- @return bool
function WindowMeta:IsSnapshot() return self._grid:IsSnapshot() end

-- Shows or hides the read-only chrome. Separate from SetCharacter so the bank session can re-run it
-- when the bank CLOSES underneath a window that was live a moment ago.
function WindowMeta:_applySnapshotState(snapshot)
    if self._snapStrip then
        if snapshot then self._snapStrip:Show() else self._snapStrip:Hide() end
    end
    if self._snapAge and snapshot then
        self._snapAge:SetText(SuuUI.Readout.Age(self._grid:SeenAt()))
    end

    -- "THIS CHARACTER HAS NEVER BEEN TO A BANK", said outright. A bank is only readable while its frame
    -- is open, so a character who has not stood at a banker since the cache existed has no bank record
    -- at all -- and Readout.Age already spells that `never` in the strip. The strip is not enough on its
    -- own: what the player is looking at is an empty grid, which is indistinguishable from a bank that
    -- IS empty and from a bug. Both readings are wrong, and only one sentence separates them.
    --
    -- Keyed on SeenAt being absent rather than on the item count, exactly as Capture's own guard is: a
    -- character can genuinely have an empty bank, and that case must keep saying nothing.
    if self._emptyNote then
        local never = snapshot and self._grid:SeenAt() == nil
        if never then
            local who = self._characterKey and self._characterKey:match("^(.-)%-") or nil
            local text
            if self._which == "bank" then
                -- Named as the ACTION the player would have to take, since that is the only way this
                -- data can ever exist: a bank is readable only while its frame is open.
                text = who and (who .. " has not visited a bank yet.")
                    or ("You have not visited a bank on this character yet.\n"
                        .. "Stand at a banker once and it will be cached here.")
            else
                text = who and (who .. "'s bags have not been cached yet.")
                    or "These bags have not been cached yet."
            end
            self._emptyNote:SetText(text)
            self._emptyNote:Show()
        else
            self._emptyNote:Hide()
        end
    end
    -- FADED, NOT HIDDEN. The concept dims sort and sell to opacityDisabled on a snapshot rather than
    -- removing them: their absence would read as a different window, while a greyed control says "not
    -- for this character" -- which is the truth, and is temporary the moment the dropdown moves back.
    if self._sortBtn then self._sortBtn:SetEnabled(not snapshot) end
    self._grid:SetReadOnly(snapshot)
end

function WindowMeta:_updateFooter()
    local used, free, total = self._grid:GetCounts()
    -- Concept spelling: "1,284 g 42 s 18 c" -- the figure in the footer's own text colour and only
    -- the UNIT LETTER in its coin colour, grouped and spaced. This is the readout where money is the
    -- subject, so it opts into all three; a vendor price in a tooltip stays dense and uncoloured.
    --
    -- A SNAPSHOT READS THE CACHED MONEY, not GetMoney(), which would show YOUR gold under an alt's
    -- name -- a number that looks authoritative and is about the wrong character.
    local copper
    if self:IsSnapshot() then
        local IC = SuuUI.ItemCache
        copper = (IC and type(IC.MoneyOf) == "function")
            and IC:MoneyOf(self._grid:GetCharacter()) or nil
    else
        copper = GetMoney and GetMoney() or 0
    end
    if copper then
        self._moneyText:SetText(SuuUI.Readout.Money(copper, {
            colored = true, groupThousands = true, spaceUnits = true,
        }))
        self._moneyText:Show()
    else
        -- Nothing cached rather than zero: an alt captured before money was stored has no figure, and
        -- printing "0g" would state a fact the cache does not have.
        self._moneyText:SetText("")
        self._moneyText:Hide()
    end
    -- FREE SLOTS, FROM THE SNAPSHOT TOO, now that capture records each container's capacity. It used to
    -- read "N items cached" here on the honest grounds that the cache stored only OCCUPIED slots, so a
    -- free count would have been invented -- that reasoning was right and is simply no longer true.
    --
    -- Still gated on the grid knowing its capacity, because a record captured before sizes were stored
    -- genuinely cannot say: it renders up to its highest occupied index, so its empty middle slots are
    -- unknown rather than free. Those records keep the old readout until that character is captured
    -- again, which is the difference between a stale number and a wrong one.
    if self:IsSnapshot() and not self._grid:HasCapacity() then
        self._slotsText:SetText(used .. " items cached")
    else
        self._slotsText:SetText(free .. " free / " .. total)
    end
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
    -- sizeTitleBar and squeezed the footer off the bottom.
    --
    -- MEASURED ONCE AND CACHED, and that is the fix for a real feedback loop. Deriving the chrome as
    -- window-minus-content on EVERY fit reads two numbers that are only consistent once the client has
    -- resized the content frame to match the last SetSize -- and it does that a frame later. Fit again
    -- before then and `ch` is stale-small while `wh` is current, so the delta comes out inflated and the
    -- window grows; the next fit inflates it again. Reported in game after switching character: the
    -- window came up far too tall and stayed that way until it was closed and reopened, which is the
    -- one thing that let the two readings settle.
    --
    -- The delta is a property of the CHROME -- title bar plus borders -- so it does not change with
    -- content, and re-measuring it per fit bought nothing. It is re-measured on a theme change, where
    -- sizeTitleBar or borderWidth may have moved, because ApplyTheme re-fits.
    local chromeW, chromeH = self._chromeW, self._chromeH
    if not (chromeW and chromeH) then
        local cw, ch = self._win:GetContentSize()
        local ww, wh = self._win:GetWidth() or 0, self._win:GetHeight() or 0
        if type(cw) == "number" and cw > 0 and type(ch) == "number" and ch > 0
            and wh > ch and ww >= cw then
            chromeW, chromeH = ww - cw, wh - ch
            self._chromeW, self._chromeH = chromeW, chromeH
        else
            -- Before the window has ever been laid out there is nothing to subtract, so the token it
            -- would otherwise have measured stands in. NOT cached: the real measurement is better and
            -- the next fit should still take it.
            chromeW, chromeH = 0, T:GetToken("sizeTitleBar") or 26
        end
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
--
-- Through AutoSort rather than Sort, so `auto_sort` can switch it off. With it off the grid opens in
-- container order and stays there until the title-bar button is pressed, which is the point -- but it
-- also means the first open looks a lot like the first-paint defect described above. It is not the
-- same thing: that bug sorted at the wrong MOMENT, while this is not sorting at all because it was
-- asked not to.
function WindowMeta:Show()
    self._win:Show()
    -- REBUILT ON EVERY OPEN, not once at construction. The cache gains a character the first time you
    -- log into one, so a list built at login would be missing whoever you played since -- and the
    -- window is built once per session while the cache keeps growing under it.
    self:_rebuildCharacters()
    self:Refresh()
    self._grid:AutoSort()
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
    -- The event bus fires listeners newest-first, so a child handle's own subscription may not have run
    -- yet -- these are applied explicitly or the strip measures the old font.
    -- The wash derives from colorWarning at a user-editable alpha, so it re-resolves here -- and so
    -- does the band's HEIGHT, which is a one-line control height and therefore moves with the font.
    if self._snapPlate then
        self._snapPlate:ApplyTheme()
        self._snapPlate:GetFrame():SetHeight(T:GetControlHeight("sizeControlSm", "sm"))
    end
    if self._scopeSeg then self._scopeSeg:ApplyTheme() end
    if self._scopeTag then self._scopeTag:ApplyTheme() end
    if self._emptyNote then self._emptyNote:ApplyTheme() end
    -- DROP THE CACHED CHROME. It is measured once and reused because re-deriving it per fit fed back
    -- into itself, but sizeTitleBar and borderWidth are user-editable -- so a theme change is exactly
    -- when the delta has to be taken again.
    self._chromeW, self._chromeH = nil, nil
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
    if self._charDrop then
        if self._win.SetTitleWidget then self._win:SetTitleWidget(nil) end
        self._charDrop:Destroy()
    end
    if self._snapLabel then self._snapLabel:Destroy() end
    if self._snapAge then self._snapAge:Destroy() end
    if self._snapStrip then self._snapStrip:Destroy() end
    if self._snapPlate then self._snapPlate:Destroy() end
    if self._scopeSeg then self._scopeSeg:Destroy() end
    if self._scopeTag then self._scopeTag:Destroy() end
    if self._emptyNote then self._emptyNote:Destroy() end
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
            -- A TIGHTER INSET, not a bigger button -- see the sort button below for why.
            padding = T:GetToken("spaceXxs"),
        }, content)
    end

    -- THE CHARACTER DROPDOWN GOES WHERE THE TITLE WAS, which is the concept's arrangement: the name of
    -- the character whose bags these are IS the title, so a separate word saying "Inventory" beside it
    -- is a second label for the same thing.
    --
    -- Parented to the content frame and then handed to the window, exactly as the icons are:
    -- AddTitleAccessory reparents it into the title strip and raises it above the drag surface, which
    -- something merely anchored there would sit underneath and never receive a click.
    -- FORWARD-DECLARED, because the closures below capture it. A Lua closure only captures a local
    -- that is already in scope where the closure is CREATED -- so with `local handle` further down,
    -- `onChange` captured the GLOBAL `handle`, which is nil, and selecting a character raised
    -- "attempt to index global 'handle'". The window built fine and only the callback was broken,
    -- which is why nothing at construction time complained.
    local handle

    local charDrop = C.Dropdown({
        options = {}, w = 110,
        -- SIZED AND SURFACED FOR A TITLE STRIP, both from the concept and both reported in game as
        -- looking wrong. `.dd` is 18 units tall in a 26-unit bar, so it sits INSIDE the strip with
        -- visible clearance rather than filling it edge to edge; and its surface is DARKER than the
        -- strip, which is what gives the field a box of its own. Left on the default colorBgAlt -- the
        -- same token the strip uses -- the field is invisible until hovered, and then it reads as a
        -- bright outline floating on the title bar rather than a control lighting up.
        h  = T:GetControlHeight("sizeControlSm", "sm"),
        bg = "colorBg",
        -- Named for the frame-naming convention, and because a title-bar control that misbehaves is
        -- one an in-game probe needs to be able to reach: "SuuUI_" .. pluginId .. "_" .. role.
        name = "SuuUI_inventory_" .. which .. "_character",
        onChange = function(value) handle:SetCharacter(value) end,
    }, content)

    -- THE AMBER STRIP, between the title bar and the search row, shown only on a snapshot. Its colour
    -- is the WARNING intent rather than a colour of its own: "this is not live" is exactly the "blocked
    -- but expected" tone the intent tokens exist for, so a retint moves it with every other warning.
    --
    -- THE WHOLE LINE IS WASHED, not just the text. The concept's `.snapbar` carries a warning-tinted
    -- background and warning-coloured text, and only the text was built -- which made the single most
    -- important statement in the window (you are looking at cached data and cannot change it) a couple
    -- of small amber words that read as a caption.
    --
    -- A Components.Frame HOSTS the layout rather than the container painting itself, because a
    -- container's frame is a plain CreateFrame("Frame") with NO BackdropTemplate -- SetBackdrop on one
    -- would fail in game while passing the suite, since the harness models the method unconditionally.
    --
    -- `w` AND `h` ARE BOTH REQUIRED HERE, and each was learned by the strip being invisible in game
    -- while the suite stayed green. CreateContainer's `host` branch adopts a frame and sizes NOTHING --
    -- only the self-created branch calls SetWidth and SetPoint, and its comment says why: the client
    -- does not resolve anchor-derived geometry for a frame it has never laid out, so it reports 0 and
    -- collapses every child. Measured in game after the width was fixed: `true 530 0`, i.e. shown and
    -- 530 wide with ZERO HEIGHT, because a hug sets the height of a frame the container CREATED and
    -- there is nothing in the host path that does the same.
    --
    -- The height is a one-line control height rather than a measurement, which is honest about what
    -- this band is: a single fixed row of small text. Re-asserted in ApplyTheme, because both tokens
    -- behind it are user-editable.
    local snapPlate = C.Frame({
        bg = "colorWarningSubtle", border = false,
        w = (content.GetWidth and content:GetWidth() or 0) - pad * 2,
        h = T:GetControlHeight("sizeControlSm", "sm"),
    }, content)
    local snapStrip = SuuUI.Layout:CreateContainer({
        host = snapPlate:GetFrame(), layout = "flow", dir = "horizontal",
        gap = gap, align = "center",
        padding = { top = 2, right = pad, bottom = 2, left = pad },
    })
    local snapLabel = C.Text({
        text = "SNAPSHOT - read only", size = "sm", color = "warning", wrap = false,
    }, snapStrip:GetFrame())
    -- The age sits at the far right in muted text, so the strip reads as one statement: what this is,
    -- and how old it is.
    local snapAge = C.Text({ text = "", size = "sm", color = "muted", justify = "RIGHT",
                             wrap = false }, snapStrip:GetFrame())
    snapStrip:Add(snapLabel, { width = "fill" })
    snapStrip:Add(snapAge, { width = "auto" })
    snapStrip:Hide()

    -- THE BAGS / BANK SWITCH, the concept's `.seg`, and the whole point of the away-from-a-banker mode:
    -- one window can only show one container, so this is what makes the bank reachable at all when you
    -- are nowhere near a banker. Bank slots are unreadable away from the frame, so that side is a
    -- read-only snapshot of whatever the cache last saw -- which the amber strip already announces.
    --
    -- It is hidden during a bank SESSION rather than left live: with both windows on screen there is
    -- nothing left to switch, and a control whose two states look identical is how you get a control
    -- that appears to do nothing. A muted BAGS / BANK tag names each window instead.
    local scopeSeg = C.SegmentedControl({
        name    = "SuuUI_inventory_" .. (props.container or "bags") .. "_scope",
        options = { { value = "bags", label = "Bags" }, { value = "bank", label = "Bank" } },
        value   = props.container or "bags",
    }, content)

    -- The muted tag that replaces it during a bank session, at the concept's letter-spaced weight.
    local scopeTag = C.Text({
        text = "", size = "sm", color = "muted", justify = "LEFT", wrap = false,
    }, content)
    scopeTag:Hide()

    -- The message for a container that has never been captured. Centred and muted: it is an explanation
    -- rather than a warning -- nothing is wrong, the data has simply never existed.
    local emptyNote = C.Text({
        text = "", size = "sm", color = "muted", justify = "CENTER", wrap = true,
    }, content)
    emptyNote:Hide()

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
        -- A TIGHTER INSET, NOT A BIGGER BUTTON. IconButton insets its glyph by `padding` on every
        -- side, so the art is the box minus twice that -- and the box is the title-bar accessory
        -- size, shared with the close button and capped by the strip height. Growing the box would
        -- reflow the whole band and leave these two odd against the X; shrinking the inset grows
        -- only the art. `spaceXxs` rather than a literal, so the glyph tracks the spacing scale.
        padding   = T:GetToken("spaceXxs"),
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
        sortPosition = get("sort_position") or "start",
        autoSort   = get("auto_sort") ~= false,
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

    col:Add(snapStrip, { width = "fill" })
    col:Add(searchRow, { width = "fill" })
    col:Add(searchDivider, { width = "fill" })
    -- The PLATE goes in, not the grid: the grid is inside it. Still no width prop -- the grid's width
    -- is AUTHORITATIVE (columns times cell size) and the window is sized from it, so stretching either
    -- one would make the two define each other. That produced a 16px window once.
    col:Add(plate)
    -- THE "NEVER BEEN TO A BANK" ROW, between the grid and the footer and hidden almost always. A bank
    -- is only readable while its frame is open, so a character who has not stood at a banker since the
    -- cache existed has NO bank record at all -- and the grid for that state is legitimately empty.
    --
    -- An empty lattice is the wrong answer to give a player who just asked to see a bank: it looks
    -- identical to a bank that IS empty, and to a bug. Flow layout skips a hidden child entirely, so
    -- this row costs nothing while it is not needed.
    col:Add(emptyNote, { width = "fill" })
    col:Add(footDivider, { width = "fill" })
    col:Add(footer, { width = "fill" })

    local id = "inventorywindow_" .. which
    handle = setmetatable({
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
        _charDrop  = charDrop,
        _snapStrip = snapStrip,
        _snapPlate = snapPlate,
        _scopeSeg  = scopeSeg,
        _scopeTag  = scopeTag,
        _emptyNote = emptyNote,
        _snapLabel = snapLabel,
        _snapAge   = snapAge,
        _which     = which,
        _realm     = (GetRealmName and GetRealmName()) or "?",
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

    -- The switch drives the window's container. Connected to the SIGNAL rather than read back on a
    -- timer, and SetValue stays silent, so the window syncing the segment (a bank session opening
    -- underneath it) cannot loop back into a scope change.
    S:Connect(scopeSeg, S.SIGNALS.VALUE_CHANGED, function(value)
        handle:SetScope(value)
    end)

    -- Into the title bar, which reparents it and raises it above the drag surface. Done AFTER the
    -- handle exists, because the click needs a handle to cycle.
    if sellBtn then win:AddTitleAccessory(sellBtn) end
    win:AddTitleAccessory(sortBtn)
    -- THE TITLE SLOT, not an accessory. Accessories stack inward from the close button, so the dropdown
    -- landed crushed against the X and pushed the sort and coin icons out of the band entirely --
    -- reported from a screenshot. The concept puts the character name where the TITLE is.
    --
    -- BOTH CONTROLS GO IN TOGETHER, in one horizontal container, because the concept's title bar carries
    -- the character dropdown AND the Bags/Bank segment side by side on the left. The slot takes one
    -- handle, and a container IS frame-like -- GetFrame, GetWidth, GetHeight -- so it satisfies the slot
    -- without a second API. Sized explicitly rather than left to hug: the slot captures the widget's
    -- width BEFORE adding it, so a container that had not settled its own width would be pinned at
    -- whatever it reported first.
    local titleGap = T:GetToken("spaceXs") or 4
    local titleBar = SuuUI.Layout:CreateContainer({
        parent = win:GetFrame(), layout = "flow", dir = "horizontal",
        gap = titleGap, align = "center",
        w = (charDrop:GetWidth() or 0) + titleGap + (scopeSeg:GetWidth() or 0),
        h = math.max(charDrop:GetHeight() or 0, scopeSeg:GetHeight() or 0),
    })
    titleBar:Add(charDrop, { width = charDrop:GetWidth() })
    titleBar:Add(scopeSeg, { width = scopeSeg:GetWidth() })
    win:SetTitleWidget(titleBar)

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
