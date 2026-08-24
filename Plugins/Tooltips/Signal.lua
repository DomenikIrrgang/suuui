-- The signal border: the tooltip's edge takes a colour describing WHAT it is showing.
--
-- This is treatment T4 from the concept. The client supplies almost no colour of its own -- it
-- tints an item's NAME line by quality and nothing else -- so every colour here is sourced from
-- SuuUI.Game or from Theme:GetUnitColor rather than invented.
local type, next, pcall, select = type, next, pcall, select

local M = {}

local PLUGIN_ID = "tooltips"

-- Which frames currently carry a signal colour, so the reset touches exactly those. Keyed by
-- frame, exactly like the suppression and reposition patterns elsewhere in the addon.
local tinted = {}

M._tinted = tinted

--- Whether the signal border is switched on.
local function wanted()
    return SuuUI.Settings:Get(PLUGIN_ID, "signal_border") and true or false
end

--- Paints one frame's border and records that it is no longer the default.
--
-- Gated on the frame having actually been SKINNED. A border colour is a property of a backdrop,
-- so SetBackdropBorderColor on a frame that never got one raises rather than returning false --
-- and this runs from a tooltip script, where a throw is the client's frame, not ours.
local function tint(tt, color)
    if not color then return false end
    if not SuuUI._Tooltips.Skin.IsSkinned(tt) then return false end
    SuuUI.Backdrop.SetBorder(tt, color)
    tinted[tt] = true
    return true
end

--- Returns the border to the theme's default, if and only if THIS module tinted it.
--
-- Guarded on `tinted` for the same reason the Blizzard-suppression pattern is guarded: with the
-- feature off we never coloured anything, and resetting anyway would override whatever else set
-- that border. Without this the colour LEAKS to the next tooltip -- and because T4 is the
-- default rather than an off-by-default extra, that leak sits on the main path.
-- @return bool  whether a reset happened
function M.Reset(tt)
    if type(tt) ~= "table" or not tinted[tt] then return false end
    tinted[tt] = nil
    if not SuuUI._Tooltips.Skin.IsSkinned(tt) then return false end
    SuuUI.Backdrop.SetBorder(tt, "colorBorder")
    return true
end

---------------------------------------------------------------------------
-- Per-type signal
---------------------------------------------------------------------------

--- An item's quality colour, but only from UNCOMMON up.
--
-- The `> 1` threshold is the rule T4 needs and T3 did not, and it is ElvUI's too
-- (`if quality and quality > 1 then`). Common is white and Poor is grey: a white 1px edge on a
-- dark panel reads as a selected state, and it would fire on the MAJORITY of tooltips a player
-- sees -- every reagent, every grey drop, every quest item.
--
-- The threshold lives HERE and not in Game:ItemQualityColor on purpose. It is a look decision
-- owned by the surface that draws; an item name in a bag grid legitimately wants white.
-- @return table|nil  {r,g,b,a}
function M.ItemColor(link)
    if type(link) ~= "string" or link == "" then return nil end
    if type(GetItemInfo) ~= "function" then return nil end
    local ok, _, _, quality = pcall(GetItemInfo, link)
    if not ok or type(quality) ~= "number" or quality <= 1 then return nil end
    return SuuUI.Game:ItemQualityColor(quality)
end

--- A unit's colour: class when the theme says so, else its reaction, else the health token.
--
-- Theme:GetUnitColor already IS that three-step chain, so there is no colour logic here at all.
-- @return table|nil  {r,g,b,a}
function M.UnitColor(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    return SuuUI.Theme:GetUnitColor("colorHealth", unit)
end

--- An aura's colour, by kind.
--
-- Copied from Plugins/UnitFrames/AuraBand.lua's KINDS rules rather than re-derived, because the
-- two kinds genuinely disagree and getting it wrong has already cost a debugging round:
--
--   A DEBUFF's border answers "what removes this" -- the dispel type, then red when untyped,
--   which is the COMMON case since most debuffs in this game carry no type at all.
--
--   A BUFF's border answers "can I take this off them". It must NOT read the dispel type on its
--   own: the client reports one for helpful auras too (Righteous Fury comes back as "Magic"),
--   so a type-coloured buff tooltip rings half a paladin's blessings in blue while telling the
--   player nothing they can act on. isStealable is the client's own answer, computed against
--   YOUR class and THAT unit.
-- @param harmful bool
-- @param dispelType string|nil
-- @param stealable bool|nil
-- @return table|nil  {r,g,b,a}
function M.AuraColor(harmful, dispelType, stealable)
    if harmful then
        return SuuUI.Game:DebuffTypeColor(dispelType) or SuuUI.Game:UntypedDebuffColor()
    end
    if not stealable then return nil end
    return SuuUI.Game:DebuffTypeColor(dispelType)
end

---------------------------------------------------------------------------
-- Script handlers
---------------------------------------------------------------------------

--- OnTooltipSetItem: colour by quality.
function M.OnItem(tt)
    if not wanted() or type(tt) ~= "table" then return end
    if type(tt.GetItem) ~= "function" then return end
    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok then return end
    tint(tt, M.ItemColor(link))
end

--- OnTooltipSetUnit: colour by class, else reaction.
function M.OnUnit(tt)
    if not wanted() or type(tt) ~= "table" then return end
    if type(tt.GetUnit) ~= "function" then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not ok or not unit then return end
    tint(tt, M.UnitColor(unit))
end

--- OnTooltipSetSpell: deliberately NOTHING.
--
-- A spell gets no signal, and that is a decision rather than an omission: this client has no
-- spell-to-school API, so Game:SchoolOf only knows spells the combat log has already reported.
-- A border coloured for spells you have cast and grey for everything else is worse than always
-- grey. Present as a named no-op so nobody "fixes" it by wiring a school lookup.
function M.OnSpell() end

--- OnTooltipCleared: hand the border back.
function M.OnCleared(tt)
    M.Reset(tt)
end

--- Drops every recorded tint, for teardown.
function M.ResetAll()
    for tt in next, tinted do M.Reset(tt) end
end

SuuUI._Tooltips = SuuUI._Tooltips or {}
SuuUI._Tooltips.Signal = M
