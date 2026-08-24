-- The lines this plugin ADDS to a tooltip.
--
-- Scope note, and it is a real boundary rather than laziness: this module only ever APPENDS.
-- Rewriting a line the client already wrote -- recolouring the name by class, folding the
-- creature type onto the level line, stripping Blizzard's PVP and faction rows -- needs
-- GameTooltipTextLeft<N>, and the harness deliberately models no per-line font strings
-- (TESTING.md says so, and adding them would invite specs asserting against a shape the model
-- does not really have). An appended line is fully assertable through GetLine; a rewritten one
-- would be in-game-only. The signal border already carries class and reaction, so the name-line
-- recolour is the least valuable of them anyway.
--
-- Every value here is READ, never cached: a tooltip is rebuilt on every mouseover, so there is
-- nothing to invalidate and a cache would only be a way to show stale numbers.
local type, tostring, string, math, next = type, tostring, string, math, next

local M = {}

local PLUGIN_ID = "tooltips"

local function get(key) return SuuUI.Settings:Get(PLUGIN_ID, key) end

--- Whether the modifier gating IDs is satisfied.
--
-- One string per surface, and "SHOW" short-circuits -- the shape ElvUI uses, and it is nicer
-- than a boolean plus a separate key because "always" and "while shift is held" are the same
-- kind of answer.
function M.ModifierDown(mode)
    if mode == "SHOW" then return true end
    -- The "HIDE" half of this is REDUNDANT and mutation testing proved it: an unrecognised mode
    -- falls through to the final `return false` anyway, so removing it changes no answer. Kept
    -- because it names the mode the settings dropdown actually offers, and a reader tracing
    -- "HIDE" through this function should find it rather than infer it from a fallthrough.
    if mode == "HIDE" or type(mode) ~= "string" then return false end
    if mode == "SHIFT" then return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() end
    if mode == "CTRL"  then return type(IsControlKeyDown) == "function" and IsControlKeyDown() end
    if mode == "ALT"   then return type(IsAltKeyDown) == "function" and IsAltKeyDown() end
    return false
end

local function idsWanted() return M.ModifierDown(get("show_ids")) end

--- Muted RGB, for a line that is metadata rather than content.
local function mutedRGB()
    local c = SuuUI.Theme:GetToken("colorTextMuted") or { 0.5, 0.5, 0.5, 1 }
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- What the tooltip is currently showing
---------------------------------------------------------------------------

-- Remembering this is what makes the modifier gate work at all. A gated line is APPENDED while
-- the client builds the tooltip, so pressing the modifier afterwards changes nothing until the
-- tooltip is rebuilt -- and only a UNIT tooltip can be rebuilt from the tooltip itself, through
-- GetUnit. A spell or an aura cannot: the tooltip does not remember what it was pointed at.
--
-- So the source is recorded here as the client sets it, and Redraw re-drives that same call.
-- Without this, `show_ids = SHIFT` silently never worked for spells or auras -- which is exactly
-- what was reported from the game.
local last = {}

M._last = last

local function remember(kind, a, b, c)
    last.kind, last.a, last.b, last.c = kind, a, b, c
end

M.Remember = remember

--- Re-drives whatever the tooltip is showing, so a modifier press takes effect immediately.
-- @return bool  whether anything was re-driven
function M.Redraw(tt)
    tt = tt or _G.GameTooltip
    if type(tt) ~= "table" or not last.kind then return false end
    local k = last.kind
    local ok
    if k == "unit" and type(tt.SetUnit) == "function" then
        ok = pcall(tt.SetUnit, tt, last.a)
    elseif k == "action" and type(tt.SetAction) == "function" then
        ok = pcall(tt.SetAction, tt, last.a)
    elseif k == "aura" then
        local fn = tt[last.c == "HARMFUL" and "SetUnitDebuff" or "SetUnitBuff"]
        if type(fn) == "function" then ok = pcall(fn, tt, last.a, last.b) end
    elseif k == "item" and type(tt.SetHyperlink) == "function" then
        ok = pcall(tt.SetHyperlink, tt, last.a)
    end
    if not ok then return false end
    -- Re-show so the tooltip resizes around the line that just appeared or vanished.
    if type(tt.Show) == "function" then pcall(tt.Show, tt) end
    return true
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------

--- Formats copper as gold/silver/copper, dropping the units that would read as zero.
--
-- Delegates to Core/Readout, which is where money is spelled for the whole addon: this function and
-- the inventory footer had each grown their own copy, which is the divergence Readout exists to
-- prevent. The rule it applies is the one learned HERE and pinned by this plugin's spec -- leading
-- zero units are dropped as noise, trailing ones are KEPT because "12g 88c" and "12g 88s" are
-- different prices.
--
-- The nil-on-nothing contract stays local rather than moving into Readout: a PRICE of zero is not a
-- price and the caller omits the line, whereas a PURSE of zero is a real reading that has to render
-- as "0c". Same number, two meanings, so the caller decides which it is.
--
-- Uncoloured on purpose. A vendor price sits in a tooltip line whose colour already carries meaning,
-- and three coin colours inside it would fight the line's own; the inventory footer asks for
-- `colored` because there the money IS the readout.
function M.FormatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then return nil end
    return SuuUI.Readout.Money(copper)
end

---------------------------------------------------------------------------
-- Item lines
---------------------------------------------------------------------------

--- Appends this plugin's item lines.
-- @return number  how many lines were added
function M.OnItem(tt)
    if type(tt) ~= "table" or type(tt.AddDoubleLine) ~= "function" then return 0 end
    if not get("enabled") then return 0 end
    if type(tt.GetItem) ~= "function" then return 0 end

    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok or type(link) ~= "string" then return 0 end
    remember("item", link)
    if type(GetItemInfo) ~= "function" then return 0 end

    local ok2, _, _, _, itemLevel, _, _, _, _, _, _, sellPrice = pcall(GetItemInfo, link)
    if not ok2 then return 0 end

    local mr, mg, mb = mutedRGB()
    local added = 0

    -- Item level from GetItemInfo's fourth field, which is EXACT on this client: TBC has no
    -- upgrade levels, so there is nothing for GetDetailedItemLevelInfo to add and nothing to
    -- scrape out of the tooltip's own text.
    if get("item_level") and type(itemLevel) == "number" and itemLevel > 1 then
        tt:AddDoubleLine("Item Level", tostring(itemLevel), mr, mg, mb, mr, mg, mb)
        added = added + 1
    end

    if get("item_count") and type(GetItemCount) == "function" then
        local bags  = GetItemCount(link) or 0
        local total = GetItemCount(link, true) or 0
        -- includeBank returns the TOTAL, so the bank's own figure is the difference. Getting
        -- this backwards prints the whole stack as if it were all in the bank.
        local bank  = math.max(total - bags, 0)
        if bags > 0 or bank > 0 then
            local txt = tostring(bags)
            if get("item_count_bank") and bank > 0 then
                txt = txt .. " (bank " .. bank .. ")"
            end
            tt:AddDoubleLine("Carrying", txt, mr, mg, mb, mr, mg, mb)
            added = added + 1
        end
    end

    if get("sell_price") then
        local money = M.FormatMoney(sellPrice)
        if money then
            tt:AddDoubleLine("Sells for", money, mr, mg, mb, mr, mg, mb)
            added = added + 1
        end
    end

    if idsWanted() then
        local id = link:match("item:(%d+)")
        if id then
            tt:AddDoubleLine("Item ID", id, mr, mg, mb, mr, mg, mb)
            added = added + 1
        end
    end

    return added
end

---------------------------------------------------------------------------
-- Unit lines
---------------------------------------------------------------------------

--- The role a unit is assigned, as a display word.
--
-- MEASURED: the client answers "DAMAGER", not "DPS", so printing the raw value shows a word no
-- player uses. "NONE" must render NOTHING rather than the word "None" -- a solo player has no
-- role, and a line saying so is a line about nothing.
function M.RoleText(unit)
    if type(UnitGroupRolesAssigned) ~= "function" then return nil end
    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" then return "Tank" end
    if role == "HEALER" then return "Healer" end
    if role == "DAMAGER" then return "Damage" end
    return nil
end

--- Appends this plugin's unit lines.
-- @return number  how many lines were added
function M.OnUnit(tt)
    if type(tt) ~= "table" or type(tt.AddDoubleLine) ~= "function" then return 0 end
    if not get("enabled") then return 0 end
    if type(tt.GetUnit) ~= "function" then return 0 end

    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not ok or type(unit) ~= "string" then return 0 end
    remember("unit", unit)

    local mr, mg, mb = mutedRGB()
    local added = 0

    -- Recolour before appending: FindLevelLine scans by pattern, and our own added lines never
    -- match it, but doing this first keeps the scan over Blizzard's lines alone.
    M.ColorLevelLine(tt)

    if get("guild_rank") and type(GetGuildInfo) == "function" then
        local ok2, guild, rank = pcall(GetGuildInfo, unit)
        if ok2 and type(guild) == "string" and guild ~= "" then
            -- The client already prints <Guild> on its own line; what it does NOT print is the
            -- player's rank in it, so only the rank is added. Appending the guild name again
            -- would duplicate a line the tooltip already has.
            if type(rank) == "string" and rank ~= "" then
                local c = SuuUI.Theme:GetToken("colorAccent") or { 0.3, 0.6, 1, 1 }
                tt:AddDoubleLine("Guild Rank", rank, mr, mg, mb, c[1], c[2], c[3])
                added = added + 1
            end
        end
    end

    if get("unit_target") and type(UnitName) == "function" then
        -- The unit's own target, which the client never puts on a tooltip.
        local tname = UnitName(unit .. "target")
        if tname and tname ~= "" then
            -- Coloured by what that unit IS, through the same chain the border uses.
            local c = SuuUI.Theme:GetUnitColor("colorHealth", unit .. "target")
            tt:AddDoubleLine("Target", tname, mr, mg, mb,
                c and c[1] or mr, c and c[2] or mg, c and c[3] or mb)
            added = added + 1
        end
    end

    if get("unit_role") then
        local role = M.RoleText(unit)
        if role then
            tt:AddDoubleLine("Role", role, mr, mg, mb, mr, mg, mb)
            added = added + 1
        end
    end

    if idsWanted() and type(UnitGUID) == "function" then
        local guid = UnitGUID(unit)
        -- An NPC id is parsed out of the GUID; a player has none, which is why this is not
        -- offered unconditionally.
        local npc = type(guid) == "string" and guid:match("Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        if npc then
            tt:AddDoubleLine("NPC ID", npc, mr, mg, mb, mr, mg, mb)
            added = added + 1
        end
    end

    return added
end

---------------------------------------------------------------------------
-- Spell lines
---------------------------------------------------------------------------

--- Appends the spell id, when the modifier allows it.
-- @return number
function M.OnSpell(tt)
    if type(tt) ~= "table" or type(tt.AddDoubleLine) ~= "function" then return 0 end
    if not get("enabled") or not idsWanted() then return 0 end
    if type(tt.GetSpell) ~= "function" then return 0 end
    local ok, _, id = pcall(tt.GetSpell, tt)
    if not ok or not id then return 0 end
    local mr, mg, mb = mutedRGB()
    tt:AddDoubleLine("Spell ID", tostring(id), mr, mg, mb, mr, mg, mb)
    return 1
end

---------------------------------------------------------------------------
-- Rewriting a line the client wrote
---------------------------------------------------------------------------

-- Everything above APPENDS. This section does not, and it is the one place the module reaches
-- for GameTooltipTextLeft<N> -- because the level line is Blizzard's text and its font string is
-- the only handle on it. There is no append that achieves the same thing: a second, coloured
-- level line would leave the client's uncoloured one sitting above it.
--
-- Kept to exactly this: find the level line, recolour it. No re-wording, no re-ordering.

--- The font string carrying one line's left-hand text, or nil.
--
-- Read off the TOOLTIP ITSELF (`tt.TextLeft2`), not from the `GameTooltipTextLeft<i>` globals and
-- NOT from a `GetLine` method -- because `GetLine` DOES NOT EXIST on the real GameTooltip. It is a
-- convenience the test harness provides for specs, and calling it from here raised "attempt to
-- call a nil value" on the first mouseover in game while the whole suite stayed green. The
-- instance fields are what the client actually ships, and unlike the globals they are correct for
-- any tooltip instance rather than only the shared one.
local function lineFS(tt, i)
    local fs = tt["TextLeft" .. i]
    if fs and type(fs.GetText) == "function" then return fs end
    return nil
end

M.lineFS = lineFS

--- The index of the line carrying the unit's level, or nil.
--
-- Found by PATTERN rather than by position. The level line is line 2 for a mob and line 3 for a
-- guilded player, and it moves again for anything carrying a title -- so a fixed index colours
-- the guild name on some units and nothing at all on others.
--
-- LEVEL1/LEVEL2 are the client's own format strings ("Level %d" / "Level %d %s"), which is what
-- makes this locale-safe: hardcoding the English word would silently colour nothing on a
-- German client.
function M.FindLevelLine(tt)
    if type(tt) ~= "table" or type(tt.NumLines) ~= "function" then return nil end
    local word = _G.LEVEL or "Level"
    -- Strip the format specifiers to get the bare word the line starts with.
    word = tostring(word):gsub("%%%a", ""):gsub("[%s%-]+$", "")
    if word == "" then return nil end
    for i = 2, tt:NumLines() do
        local fs = lineFS(tt, i)
        local text = fs and fs:GetText()
        if type(text) == "string" and text:find(word, 1, true) then
            local lvl = text:match("(%d+)")
            -- ?? is the client's "cannot tell", and it has no digits -- so a boss still matches
            -- the word and is handed to DifficultyColor as an unknown rather than skipped.
            --
            -- The -1 is the client's own sentinel for that. Mutation testing shows any value
            -- outside the yellow band gives the same colour here, because DifficultyColor sends
            -- both "<= 0" and "far above" to deadly -- so this is an EQUIVALENT mutant rather
            -- than uncovered code. -1 stays because it is the value the client uses, and a
            -- reader tracing it should find that rather than an arbitrary large number.
            return i, lvl and tonumber(lvl) or -1
        end
    end
    return nil
end

--- A |cffRRGGBB escape from a {r,g,b} colour.
--
-- Built here rather than through Theme:GetColorCode because a difficulty colour comes from
-- SuuUI.Game, not from a theme token -- it is a fact about the client, so there is no token key
-- to hand over.
local function escape(c)
    if type(c) ~= "table" then return nil end
    return string.format("|cff%02x%02x%02x",
        math.floor((c[1] or 0) * 255 + 0.5),
        math.floor((c[2] or 0) * 255 + 0.5),
        math.floor((c[3] or 0) * 255 + 0.5))
end

M.Escape = escape

--- Colours the LEVEL NUMBER by how dangerous the unit is: grey, green, yellow, orange, red.
--
-- Only the number, not the line. SetTextColor cannot express that -- it takes the whole font
-- string -- so the digits are wrapped in an inline |cff escape and the font string's own colour is
-- left alone. Same technique DataField uses to colour its prefix separately from its value.
--
-- The `?` case is wrapped too: a boss's level line reads "Level ??", and the ?? is the part that
-- carries the meaning there, so leaving it uncoloured would be the one unit where the feature
-- silently does nothing.
-- @return bool  whether a line was recoloured
function M.ColorLevelLine(tt)
    if not get("enabled") or not get("level_difficulty") then return false end
    local i, level = M.FindLevelLine(tt)
    if not i then return false end
    local fs = lineFS(tt, i)
    if not fs or type(fs.SetText) ~= "function" then return false end
    local text = fs:GetText()
    if type(text) ~= "string" or text == "" then return false end
    -- Already wrapped. The client rebuilds the tooltip on every show, so this only guards the
    -- case where one show drives this twice -- a MODIFIER_STATE_CHANGED re-render, for instance.
    if text:find("|cff", 1, true) then return false end

    local esc = escape(SuuUI.Game:DifficultyColor(level))
    if not esc then return false end

    -- The digits, or the ?? a boss reports. Anchored to the first run of either so a creature
    -- type containing a digit cannot be recoloured instead.
    local wrapped, n = text:gsub("(%d+)", esc .. "%1|r", 1)
    if n == 0 then
        wrapped, n = text:gsub("(%?+)", esc .. "%1|r", 1)
    end
    if n == 0 then return false end

    fs:SetText(wrapped)
    return true
end

---------------------------------------------------------------------------
-- Aura lines
---------------------------------------------------------------------------

--- Whether the tooltip already carries a line with this label.
--
-- Belt and braces, and it earned its place: an action-button tooltip showed the spell id TWICE,
-- because `SetAction` fires `OnTooltipSetSpell` as well as being hooked directly, so two paths
-- appended the same line. Rather than reason about which scripts fire for which setter -- a
-- question this codebase has now got wrong in both directions -- no label is ever added twice.
local function hasLabel(tt, label)
    if type(tt.NumLines) ~= "function" then return false end
    for i = 1, tt:NumLines() do
        local fs = lineFS(tt, i)
        if fs and fs:GetText() == label then return true end
    end
    return false
end

M.hasLabel = hasLabel

--- Appends one label/value line, unless that label is already on the tooltip.
local function addLine(tt, label, value, valueColor)
    if hasLabel(tt, label) then return 0 end
    local mr, mg, mb = mutedRGB()
    local c = valueColor
    tt:AddDoubleLine(label, value, mr, mg, mb,
        c and c[1] or mr, c and c[2] or mg, c and c[3] or mb)
    return 1
end

M.addLine = addLine

--- Re-sizes the tooltip around a line that was just appended.
--
-- Load-bearing for anything appended from a HOOKED SETTER rather than from a content script.
-- `SetUnitBuff` / `SetUnitAura` SHOW the tooltip themselves, so by the time our hook runs the box
-- is already built and measured -- an added line then sits OUTSIDE it and is simply invisible. A
-- content script (OnTooltipSetItem / SetUnit) runs before the client shows the tooltip, so those
-- paths need nothing.
--
-- Only when already shown: calling Show on a tooltip nobody has anchored would put an empty box
-- on screen.
local function resize(tt)
    if type(tt.IsShown) == "function" and tt:IsShown() and type(tt.Show) == "function" then
        pcall(tt.Show, tt)
    end
end

M.resize = resize

--- Who applied an aura, as a display name, or nil when the client will not say.
--
-- The source is a UNIT TOKEN ("player", "party3", "target"), not a name -- so it has to be resolved
-- through UnitName. It is frequently **nil**: an environmental debuff has no caster, and neither
-- does one from a unit the client is no longer tracking. That renders NOTHING rather than
-- "Unknown", which would put a useless line on a large share of auras.
-- @param source string|nil  The unit token from slot 7 of UnitAura
-- @return string|nil name, table|nil colour
function M.CasterText(source)
    if type(source) ~= "string" then return nil end
    if type(UnitName) ~= "function" then return nil end
    -- No separate empty-string guard: UnitName("") answers nothing, so the name check below
    -- already covers it. Mutation testing showed the two conditions indistinguishable, and one
    -- condition is better than two that cannot be told apart.
    local name = UnitName(source)
    if type(name) ~= "string" or name == "" then return nil end
    return name, SuuUI.Theme:GetUnitColor("colorHealth", source)
end

--- Appends an aura's caster and its spell id.
--
-- The two are INDEPENDENT, unlike ElvUI, which puts the caster on the id's own line as its
-- right-hand value. That is tidier but couples them: a player who wants to know who buffed them
-- then has to switch ids on as well, and ids are the noisier of the two. Separate lines, separate
-- toggles.
--
-- The spell id is read from the aura DATA rather than from the tooltip, because the tooltip does
-- not carry it -- slot 10 on this client, confirmed against two installed addons that read it
-- positionally (Gladdy and Questie) rather than from memory of the retail signature. The caster is
-- slot 7, confirmed by an in-game probe.
-- @param unit string
-- @param index number
-- @param filter string
-- @return number  how many lines were added
function M.OnAura(tt, unit, index, filter)
    if type(tt) ~= "table" or type(tt.AddDoubleLine) ~= "function" then return 0 end
    remember("aura", unit, index, filter)
    if not get("enabled") then return 0 end
    if type(UnitAura) ~= "function" or type(unit) ~= "string" then return 0 end

    local ok, source, spellId = pcall(function()
        local _, _, _, _, _, _, src, _, _, id = UnitAura(unit, index, filter)
        return src, id
    end)
    if not ok then return 0 end

    local added = 0

    if get("aura_caster") then
        local name, colour = M.CasterText(source)
        if name then added = added + addLine(tt, "Cast by", name, colour) end
    end

    if idsWanted() and type(spellId) == "number" then
        added = added + addLine(tt, "Spell ID", tostring(spellId))
    end

    if added > 0 then resize(tt) end
    return added
end

---------------------------------------------------------------------------
-- Action slots
---------------------------------------------------------------------------

--- Records that the tooltip is showing an action slot.
--
-- It adds NO LINE. `SetAction` fires `OnTooltipSetSpell` (and `OnTooltipSetItem` for an item
-- action) and `GetSpell` answers for the slot, so `OnSpell` already covers the id -- measured, and
-- adding it here too is what put the id on screen twice.
--
-- The function stays because the RECORD is load-bearing and nothing else can produce it: only a
-- unit tooltip can be rebuilt from the tooltip itself, so without this a modifier press over an
-- action button has nothing to re-drive.
-- @return number  always 0
function M.OnAction(tt, slot)
    if type(tt) ~= "table" then return 0 end
    remember("action", slot)
    return 0
end

SuuUI._Tooltips = SuuUI._Tooltips or {}
SuuUI._Tooltips.Content = M
