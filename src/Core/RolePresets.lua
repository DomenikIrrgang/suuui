-- Core/RolePresets.lua
-- Role presets (plan 4.1, asked 2026-10-17): a ready-made layout for each
-- role from the design's role boards (Dungeon DPS, Dungeon Healer, Raid 20
-- and 40 Tank and Healer), each its own profile (SuuTank, SuuHeal, SuuDps)
-- that takes its role's place under Profiles › By role, so the HUD follows
-- your role. One layout per role serves dungeons and raids: the party frames
-- show in a party, the raid frames in a raid, each placed for the role.
--   Tank and DPS: the design's default HUD (the group above the chat, you and
--     your target either side of the centre, the cast bar and swing timer
--     between, the threat meter beside the damage meter).
--   Healer: the group in the middle, between your frame and your target's,
--     tops level and growing down (the party as one row, the raid's groups as
--     rows, icons inside the bars); you and your target further out; the cast
--     bar and Cooldown Manager above the group; no threat meter or swing timer.
-- A preset sets the layout only: the profile starts as a copy of the one you
-- use, so everything else you chose comes along. Applying it again puts the
-- layout back. Positions are design pixels from the screen's bottom centre,
-- from the 2560 × 1440 boards; edit mode keeps their anchors on every size.

local _, ns = ...

local Profiles, Settings, Events = ns.Profiles, ns.Settings, ns.Events

local RolePresets = {}
ns.RolePresets = RolePresets

RolePresets.ROLES = { "TANK", "HEALER", "DAMAGER" }
RolePresets.NAME = { TANK = "SuuTank", HEALER = "SuuHeal", DAMAGER = "SuuDps" }

local function at(point, x, y, hidden)
    return { point = point, x = x, y = y, hidden = hidden or nil }
end

-- Every setting a preset decides; one a preset leaves out is its default.
local KEYS = {
    { "unitframes", "playerPosition" }, { "unitframes", "targetPosition" }, { "unitframes", "totPosition" },
    { "unitframes", "focusPosition" }, { "unitframes", "petPosition" },
    { "castbars", "playerPosition" }, { "cooldowns", "position" }, { "swingtimer", "position" }, { "threat", "position" },
    { "party", "position" }, { "party", "direction" }, { "party", "width" }, { "party", "height" }, { "party", "gap" },
    { "party", "auraSide" }, { "party", "buffIcons" }, { "party", "debuffIcons" }, { "party", "healthText" },
    { "raid", "position" }, { "raid", "arrangement" }, { "raid", "width" }, { "raid", "height" },
    { "raid", "heightLarge" }, { "raid", "gap" }, { "raid", "groupGap" },
}

-- The healer layout (boards Dungeon Healer, Raid 20 and 40 Healer): the
-- group's top edge 332 above the bottom, 608 wide (5 × 120 + 4 × 2).
local HEALER = {
    unitframes = {
        playerPosition = at("BOTTOM", -474, 300),
        targetPosition = at("BOTTOM", 474, 300),
        totPosition = at("BOTTOM", 706, 304),
        petPosition = at("BOTTOM", -424, 260),
    },
    castbars = { playerPosition = at("BOTTOM", 0, 340) },
    cooldowns = { position = at("BOTTOM", 0, 370) },
    swingtimer = { position = at("BOTTOM", 0, 271, true) },
    threat = { position = at("BOTTOMRIGHT", -292, 28, true) },
    party = {
        position = at("BOTTOM", 0, 332 - 26),
        direction = "right", width = 120, height = 26, gap = 2,
        auraSide = "inside", buffIcons = 1, debuffIcons = 2, healthText = "none",
    },
    raid = {
        -- the holder is as tall as eight rows at 26 (20 players): its top at 332
        position = at("BOTTOM", 0, 332 - (8 * 26 + 7 * 4)),
        arrangement = "rows", width = 120, height = 26, heightLarge = 20, gap = 2, groupGap = 4,
    },
}

RolePresets.LAYOUT = { TANK = {}, HEALER = HEALER, DAMAGER = {} }

function RolePresets.Exists(role)
    local name = RolePresets.NAME[role]
    local found = name and Profiles.Find(name)
    return found ~= nil and found:lower() == name:lower()
end

-- Creates or resets a role's profile with its layout and puts it in its
-- role's place. Out of combat (the HUD's frames move).
function RolePresets.Apply(role)
    if InCombatLockdown() then return false, "After the fight." end
    local name, layout = RolePresets.NAME[role], RolePresets.LAYOUT[role]
    if not name then return false, "No such role." end
    local entries = {}
    for _, k in ipairs(KEYS) do
        local values = layout[k[1]]
        entries[#entries + 1] = { k[1], k[2], values and values[k[2]] or nil }
    end
    local ok, err = Profiles.SetValues(name, entries)
    if not ok then return false, err end
    Profiles.SetRoleProfile(role, err)
    return true
end
