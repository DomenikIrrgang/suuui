-- Data/RaidPlanner.lua
-- What each class and spec brings to a raid, for the raid planner's coverage
-- (Settings › Raid planner; design "Raid planner", the intro and section 5).
-- Written by hand from Forever's trainers and talents (tools/data/class_*.tsv,
-- scanned 2026-10-12) and the client's spell scan (tools/data/forever_spells.tsv):
-- each `spell` is an ID this client has, for its icon and tooltip.
--
--   classes   the nine, in the palette's order: file, name, their trees left
--             to right (specs, short), each tree's role, the role a player
--             of the class most likely has before their spec is known
--             (`likely`), which trees fight in melee, and each tree's icon
--             (`icons`: the classic talent tabs' art, until the game's own
--             is seen in a talent tree)
--   families  the settings' groups, in order: key, title, scope ("raid":
--             counted once for the whole raid; "party": per group of five)
--   items     what can be tracked: key, label, short (chips and merged
--             rows), family, spell, by = { { class, tree, talent } } (a
--             tree with talent = true: only that spec, "if specced"; a tree
--             without: that spec only), note (the settings' small print),
--             essential (in the "The essentials" preset), and:
--               line     raid-wide items sharing a line share a row
--               users    party-wide: who in a group uses it ("melee",
--                        "hunter", "healer"); missing is flagged only where
--                        someone does
--               single   party-wide: a second one in a group is wasted
--               count    "blessings": one Blessing per paladin, 3 at most
--               ask      can't be known (from books, not trainers): shown
--                        as "ask", never counted
--
-- On Forever: Battle Shout, Moonkin Aura and Leader of the Pack reach the
-- whole raid; Windfury, Strength of Earth and Grace of Air Totems, the
-- resistance auras and totems and Aspect of the Wild reach party and raid
-- members within 30 yards (raid-wide, in range); Salvation (Mass Salvation
-- at 60) isn't a Blessing: a paladin gives it besides their one Blessing;
-- Blessing of Kings, Divine Spirit and Innervate are baseline; Improved
-- Scorch, Winter's Chill, Shadow Weaving and Improved Shadow Bolt are the
-- caster's own; no Bloodlust or Heroism. Tranquilizing Shot and the group
-- versions of Fortitude, Intellect and Mark aren't taught by trainers.

local _, ns = ...

local I = "Interface\\Icons\\"

ns.RaidCatalog = {
    classes = {
        { file = "WARRIOR", name = "Warrior", specs = { "Arms", "Fury", "Protection" }, short = { "Arms", "Fury", "Prot" },
          roles = { "DAMAGER", "DAMAGER", "TANK" }, likely = "DAMAGER", melee = { true, true, true },
          icons = { I .. "Ability_Rogue_Eviscerate", I .. "Ability_Warrior_InnerRage", I .. "INV_Shield_06" } },
        { file = "PALADIN", name = "Paladin", specs = { "Holy", "Protection", "Retribution" }, short = { "Holy", "Prot", "Ret" },
          roles = { "HEALER", "TANK", "DAMAGER" }, likely = "HEALER", melee = { false, true, true },
          icons = { I .. "Spell_Holy_HolyBolt", I .. "Spell_Holy_DevotionAura", I .. "Spell_Holy_AuraOfLight" } },
        { file = "HUNTER", name = "Hunter", specs = { "Beast Mastery", "Marksmanship", "Survival" }, short = { "BM", "MM", "SV" },
          roles = { "DAMAGER", "DAMAGER", "DAMAGER" }, likely = "DAMAGER", melee = { false, false, false },
          icons = { I .. "Ability_Hunter_BeastTaming", I .. "Ability_Marksmanship", I .. "Ability_Hunter_SwiftStrike" } },
        { file = "ROGUE", name = "Rogue", specs = { "Assassination", "Combat", "Subtlety" }, short = { "Assn", "Combat", "Sub" },
          roles = { "DAMAGER", "DAMAGER", "DAMAGER" }, likely = "DAMAGER", melee = { true, true, true },
          icons = { I .. "Ability_Rogue_Eviscerate", I .. "Ability_BackStab", I .. "Ability_Stealth" } },
        { file = "PRIEST", name = "Priest", specs = { "Discipline", "Holy", "Shadow" }, short = { "Disc", "Holy", "Shadow" },
          roles = { "HEALER", "HEALER", "DAMAGER" }, likely = "HEALER", melee = { false, false, false },
          icons = { I .. "Spell_Holy_WordFortitude", I .. "Spell_Holy_HolyBolt", I .. "Spell_Shadow_ShadowWordPain" } },
        { file = "SHAMAN", name = "Shaman", specs = { "Elemental", "Enhancement", "Restoration" }, short = { "Ele", "Enh", "Resto" },
          roles = { "DAMAGER", "DAMAGER", "HEALER" }, likely = "HEALER", melee = { false, true, false },
          icons = { I .. "Spell_Nature_Lightning", I .. "Spell_Nature_LightningShield", I .. "Spell_Nature_MagicImmunity" } },
        { file = "MAGE", name = "Mage", specs = { "Arcane", "Fire", "Frost" }, short = { "Arcane", "Fire", "Frost" },
          roles = { "DAMAGER", "DAMAGER", "DAMAGER" }, likely = "DAMAGER", melee = { false, false, false },
          icons = { I .. "Spell_Holy_MagicalSentry", I .. "Spell_Fire_FireBolt02", I .. "Spell_Frost_FrostBolt02" } },
        { file = "WARLOCK", name = "Warlock", specs = { "Affliction", "Demonology", "Destruction" }, short = { "Affl", "Demo", "Destr" },
          roles = { "DAMAGER", "DAMAGER", "DAMAGER" }, likely = "DAMAGER", melee = { false, false, false },
          icons = { I .. "Spell_Shadow_DeathCoil", I .. "Spell_Shadow_Metamorphosis", I .. "Spell_Shadow_RainOfFire" } },
        { file = "DRUID", name = "Druid", specs = { "Balance", "Feral Combat", "Restoration" }, short = { "Balance", "Feral", "Resto" },
          roles = { "DAMAGER", "DAMAGER", "HEALER" }, likely = "HEALER", melee = { false, true, false },
          icons = { I .. "Spell_Nature_StarFall", I .. "Ability_Racial_BearForm", I .. "Spell_Nature_HealingTouch" } },
    },

    families = {
        { key = "raid", title = "Raid-wide buffs", scope = "raid",
          description = "Reach the whole raid; counted once. Blessings count per paladin: one each (Kings, Might or Wisdom, Light); Salvation comes besides." },
        { key = "party", title = "Party-wide buffs", scope = "party",
          description = "Reach one group of five; counted per group. Missing is flagged only in groups that use it: hunters for Trueshot, healers for Mana Spring and Mana Tide." },
        { key = "boss", title = "Debuffs on the boss", scope = "raid" },
        { key = "dispel", title = "Dispels", scope = "raid" },
        { key = "rescue", title = "Rescue and mana", scope = "raid" },
        { key = "control", title = "Control", scope = "raid" },
    },

    items = {
        -- raid-wide buffs
        { key = "fortitude", label = "Power Word: Fortitude", short = "Fortitude", family = "raid", spell = 1243,
          by = { { "PRIEST" } }, line = "priest", essential = true },
        { key = "spirit", label = "Divine Spirit", short = "Divine Spirit", family = "raid", spell = 14752,
          by = { { "PRIEST" } }, line = "priest", note = "baseline" },
        { key = "mark", label = "Mark of the Wild", short = "Mark", family = "raid", spell = 1126,
          by = { { "DRUID" } }, line = "mark", essential = true },
        { key = "intellect", label = "Arcane Intellect", short = "Intellect", family = "raid", spell = 1459,
          by = { { "MAGE" } }, line = "mark", essential = true },
        { key = "blessings", label = "Blessings", short = "Blessings", family = "raid", spell = 20217,
          by = { { "PALADIN" } }, count = "blessings", note = "per paladin", essential = true,
          detail = "Kings, Might or Wisdom, Light" },
        { key = "salvation", label = "Salvation", short = "Salvation", family = "raid", spell = 1038,
          by = { { "PALADIN" } }, essential = true },
        { key = "shadowProtection", label = "Shadow Protection", short = "Shadow Protection", family = "raid", spell = 976,
          by = { { "PRIEST" } } },
        { key = "battleShout", label = "Battle Shout", short = "Battle Shout", family = "raid", spell = 6673,
          by = { { "WARRIOR" } }, line = "shouts", essential = true },
        { key = "leaderOfThePack", label = "Leader of the Pack", short = "Pack", family = "raid", spell = 17007,
          by = { { "DRUID", 2, talent = true } }, line = "shouts", note = "Feral" },
        { key = "moonkin", label = "Moonkin Aura", short = "Moonkin", family = "raid", spell = 24858,
          by = { { "DRUID", 1, talent = true } }, line = "shouts", note = "Balance" },
        { key = "windfury", label = "Windfury Totem", short = "Windfury", family = "raid", spell = 8512,
          by = { { "SHAMAN" } }, line = "totems", note = "30 yd", essential = true },
        { key = "earth", label = "Strength of Earth, Grace of Air", short = "Strength of Earth", family = "raid", spell = 8075,
          by = { { "SHAMAN" } }, line = "totems", note = "30 yd" },
        { key = "resistance", label = "Resistance auras and totems", short = "Resistances", family = "raid", spell = 19876,
          by = { { "PALADIN" }, { "SHAMAN" }, { "HUNTER" } }, note = "30 yd",
          detail = "paladins' and shamans' resistances, Aspect of the Wild; in range" },

        -- party-wide buffs
        { key = "manaSpring", label = "Mana Spring Totem", short = "Mana Spring", family = "party", spell = 5675,
          by = { { "SHAMAN" } }, users = "healer" },
        { key = "manaTide", label = "Mana Tide Totem", short = "Mana Tide", family = "party", spell = 16190,
          by = { { "SHAMAN", 3, talent = true } }, users = "healer", note = "Resto", essential = true },
        { key = "tremor", label = "Tremor Totem", short = "Tremor", family = "party", spell = 8143,
          by = { { "SHAMAN" } } },
        { key = "trueshot", label = "Trueshot Aura", short = "Trueshot Aura", family = "party", spell = 1299346,
          by = { { "HUNTER", 2, talent = true } }, users = "hunter", single = true, note = "MM", essential = true },
        { key = "paladinAura", label = "Paladin auras", short = "Paladin aura", family = "party", spell = 465,
          by = { { "PALADIN" } }, detail = "Devotion, Retribution or Concentration Aura" },
        { key = "bloodPact", label = "Blood Pact", short = "Blood Pact", family = "party", spell = 6307,
          by = { { "WARLOCK" } }, single = true, note = "Imp", detail = "the warlock's imp" },
        { key = "vampiricEmbrace", label = "Vampiric Embrace", short = "Vampiric Embrace", family = "party", spell = 15286,
          by = { { "PRIEST", 3, talent = true } }, note = "Shadow" },
        { key = "groupHeals", label = "Group heals", short = "Group heals", family = "party", spell = 596,
          by = { { "PRIEST" }, { "DRUID", 3, talent = true } }, note = "Prayer, Wild Growth",
          detail = "Prayer of Healing, Wild Growth" },

        -- debuffs on the boss
        { key = "sunder", label = "Sunder Armor", short = "Sunder", family = "boss", spell = 7386,
          by = { { "WARRIOR" } }, line = "armor", essential = true },
        { key = "expose", label = "Expose Armor", short = "Expose Armor", family = "boss", spell = 8647,
          by = { { "ROGUE" } }, line = "armor" },
        { key = "faerieFire", label = "Faerie Fire", short = "Faerie Fire", family = "boss", spell = 770,
          by = { { "DRUID" } }, line = "armor", essential = true },
        { key = "recklessness", label = "Curse of Recklessness", short = "Recklessness", family = "boss", spell = 704,
          by = { { "WARLOCK" } }, line = "curses", essential = true },
        { key = "elements", label = "Curse of the Elements", short = "Elements", family = "boss", spell = 11723,
          by = { { "WARLOCK" } }, line = "curses", essential = true },
        { key = "judgements", label = "Judgements", short = "Judgements", family = "boss", spell = 20271,
          by = { { "PALADIN" } } },
        { key = "huntersMark", label = "Hunter's Mark", short = "Hunter's Mark", family = "boss", spell = 1130,
          by = { { "HUNTER" } } },
        { key = "demoralize", label = "Demoralizing Shout, Roar", short = "Demoralizing", family = "boss", spell = 1160,
          by = { { "WARRIOR" }, { "DRUID" } }, line = "weaken" },
        { key = "thunderClap", label = "Thunder Clap", short = "Thunder Clap", family = "boss", spell = 6343,
          by = { { "WARRIOR" } }, line = "weaken" },

        -- dispels
        { key = "dispelMagic", label = "Magic", short = "Magic", family = "dispel", spell = 527,
          by = { { "PRIEST" }, { "PALADIN" } }, line = "dispels", essential = true },
        { key = "dispelCurse", label = "Curse", short = "Decurse", family = "dispel", spell = 2782,
          by = { { "MAGE" }, { "DRUID" } }, line = "dispels", essential = true },
        { key = "dispelPoison", label = "Poison", short = "Poison", family = "dispel", spell = 2893,
          by = { { "DRUID" }, { "SHAMAN" }, { "PALADIN" } }, line = "cures" },
        { key = "dispelDisease", label = "Disease", short = "Disease", family = "dispel", spell = 528,
          by = { { "PRIEST" }, { "SHAMAN" }, { "PALADIN" } }, line = "cures" },

        -- rescue and mana
        { key = "rebirth", label = "Rebirth", short = "Rebirth", family = "rescue", spell = 20484,
          by = { { "DRUID" } }, line = "rescue", essential = true },
        { key = "soulstone", label = "Soulstone", short = "Soulstone", family = "rescue", spell = 693,
          by = { { "WARLOCK" } }, line = "rescue", essential = true },
        { key = "innervate", label = "Innervate", short = "Innervate", family = "rescue", spell = 29166,
          by = { { "DRUID" } }, line = "mana", note = "baseline", essential = true },
        { key = "powerInfusion", label = "Power Infusion", short = "Power Infusion", family = "rescue", spell = 10060,
          by = { { "PRIEST", 1, talent = true } }, line = "mana", note = "Disc" },
        { key = "fearWard", label = "Fear Ward", short = "Fear Ward", family = "rescue", spell = 6346,
          by = { { "PRIEST" } } },
        { key = "tranquilizingShot", label = "Tranquilizing Shot", short = "Tranquilizing Shot", family = "rescue", spell = 19801,
          by = { { "HUNTER" } }, ask = true, note = "ask" },

        -- control
        { key = "interrupts", label = "Interrupts", short = "Interrupts", family = "control", spell = 1766,
          by = { { "WARRIOR" }, { "ROGUE" }, { "MAGE" }, { "SHAMAN" } },
          detail = "Pummel and Shield Bash, Kick, Counterspell, Earth Shock" },
        { key = "crowdControl", label = "Crowd control by type", short = "Crowd control", family = "control", spell = 118,
          by = { { "MAGE", what = "Polymorph" }, { "PRIEST", what = "Shackle" }, { "WARLOCK", what = "Banish, Fear" },
                 { "DRUID", what = "Hibernate" }, { "HUNTER", what = "Freezing Trap" }, { "ROGUE", what = "Sap" } } },
    },
}
