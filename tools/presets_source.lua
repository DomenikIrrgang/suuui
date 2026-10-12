-- tools/presets_source.lua
-- The Cooldown Manager presets (plan step 1.7c), written as spell names. Not
-- loaded by the game: tools/gen_presets.lua turns every name into all the
-- spell IDs that carry exactly that name in Forever's client (the spell scan,
-- tools/data/forever_spells.tsv), so every rank is in and nothing is guessed.
-- A name the client doesn't have stops the generator.
--
-- Lists per preset:
--   essential, utility   cooldowns (the tracker uses the ranks you know)
--   buffs                buffs on you (from anyone unless mine = true)
--   debuffs              your debuffs on the target (always yours)
--   procs                proc auras on you
-- An entry is a name, or { "Name", mine = true } for an aura only you cast,
-- or a group: { group = "Seal", source = "mine"|"others"|"any", max = 1..4,
-- icon = "Member name", members = { "Name", ... } } (one slot for several).
-- Group names are plural ("Seals"), so they read as groups next to spells.
-- tree: the talent tree a preset belongs to (1-3, left to right as Forever
-- lays them out); 0 is Unspecced, for characters with no talent points. The
-- first preset of a tree is that spec's starting setup.
--
-- Names are Forever's, which differ from vanilla's in places: Curse of Doom
-- and Curse of Agony are "Bane of Doom" and "Bane of Agony", the trap effects are named like their traps, Faerie Fire
-- (Feral) is "Faerie Fire", Demonic Sacrifice's buffs are "Burning Shadow" and
-- "Touch of Fire". Blessing of Sanctuary, Elemental Mastery and Curse of
-- Shadow aren't in Forever's client at all. Trainers don't teach Gift of the
-- Wild, Prayer of Fortitude, Arcane Brilliance, Inferno, Fire Nova Totem (Fire
-- Nova is a spell), Lightwell, Desperate Prayer or Tranquilizing Shot, and Sanctity Aura isn't a
-- talent (checked against /suu probe class data in tools/data).
-- Forever's own class spells (IDs above a million) aren't in vanilla's lists:
-- Seal of Fury (Protection) so far; more turn up in characters' spellbooks.

local function mine(name) return { name, mine = true } end

-- Paladin groups: one slot for your seal, your blessing on yourself, your
-- judgement, and other paladins' judgements.
local SEALS = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Wisdom", "Seal of Light", "Seal of Justice", "Seal of Command", "Seal of Fury" }
local BLESSINGS = { "Blessing of Might", "Greater Blessing of Might", "Blessing of Wisdom", "Greater Blessing of Wisdom",
    "Blessing of Kings", "Greater Blessing of Kings", "Blessing of Salvation", "Greater Blessing of Salvation",
    "Blessing of Light", "Greater Blessing of Light" }
-- the judgements that stay on the target (Righteousness and Command only
-- deal damage). Judgement of Fury, Forever's taunt from Seal of Fury, is in
-- the Taunts group instead.
local JUDGEMENTS = { "Judgement of the Crusader", "Judgement of Wisdom", "Judgement of Light", "Judgement of Justice" }
local function seal(icon) return { group = "Seals", source = "mine", max = 1, icon = icon, members = SEALS } end
local function blessing(icon) return { group = "Blessings", source = "mine", max = 1, icon = icon, members = BLESSINGS } end
local MY_JUDGEMENT = { group = "My Judgements", source = "mine", max = 1, icon = "Judgement of the Crusader", members = JUDGEMENTS }
-- Tanks: the taunt on your target, whoever cast it (another tank's too; a
-- hunter pet's Growl counts as well). A Forever paladin taunts with
-- Judgement of Fury (Seal of Fury's judgement); Hand of Reckoning exists in
-- the client but no Forever paladin learns it.
local TAUNTS = { group = "Taunts", source = "any", max = 2, icon = "Taunt",
    members = { "Taunt", "Growl", "Mocking Blow", "Challenging Shout", "Challenging Roar", "Judgement of Fury" } }
-- Mages: one armor at a time, so one slot (Molten Armor isn't in Forever).
local function armors(icon) return { group = "Armors", source = "mine", max = 1, icon = icon,
    members = { "Frost Armor", "Ice Armor", "Mage Armor" } } end
local OTHERS_JUDGEMENTS = { group = "Others' Judgements", source = "others", max = 3, icon = "Judgement of Wisdom", members = JUDGEMENTS }

return {
    -- From Forever's own class data (trainer + talents, 2026-10-11): new
    -- talent Spearing Strike (Arms); Victory Rush is trained (its IDs came from
    -- /suu probe spells find, tools/data/found.tsv); possible procs
    -- from new passives (Bloodthrill, Raging Blows, Bastion) are tracked as
    -- procs, which show only while up. Taunt isn't on the trainer list (known
    -- already at level 10).
    WARRIOR = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Bloodrage", "Overpower", "Execute", "Victory Rush", "Thunder Clap" },
          utility = { "Charge", "Intercept", "Berserker Rage", "Pummel", "Shield Bash", "Disarm" },
          buffs = { "Battle Shout", "Bloodrage" },
          debuffs = { "Rend", "Thunder Clap", "Demoralizing Shout", "Hamstring", "Sunder Armor" },
          procs = { "Enrage" } },
        { id = "arms", name = "Arms", tree = 1,
          essential = { "Mortal Strike", "Overpower", "Spearing Strike", "Sweeping Strikes", "Whirlwind", "Victory Rush", "Bloodrage" },
          utility = { "Charge", "Intercept", "Pummel", "Berserker Rage", "Intimidating Shout", "Recklessness", "Retaliation", "Thunder Clap" },
          buffs = { "Battle Shout", "Sweeping Strikes", "Recklessness", "Retaliation", "Berserker Rage", "Bloodrage" },
          debuffs = { "Rend", "Mortal Strike", "Sunder Armor", "Hamstring", "Thunder Clap", "Demoralizing Shout", "Deep Wounds" },
          procs = { "Bloodthrill" } },
        { id = "fury", name = "Fury", tree = 2,
          essential = { "Bloodthirst", "Whirlwind", "Death Wish", "Victory Rush", "Bloodrage" },
          utility = { "Pummel", "Intercept", "Berserker Rage", "Recklessness", "Intimidating Shout", "Piercing Howl", "Charge" },
          buffs = { "Battle Shout", "Death Wish", "Recklessness", "Berserker Rage", "Bloodrage" },
          debuffs = { "Sunder Armor", "Rend", "Demoralizing Shout", "Hamstring", "Piercing Howl", "Deep Wounds" },
          procs = { "Flurry", "Enrage", "Raging Blows" } },
        { id = "protection", name = "Protection", tree = 3,
          essential = { "Shield Slam", "Revenge", "Shield Block", "Taunt", "Concussion Blow", "Bloodrage" },
          utility = { "Charge", "Shield Wall", "Last Stand", "Challenging Shout", "Shield Bash", "Mocking Blow", "Disarm", "Berserker Rage", "Intercept", "Victory Rush" },
          buffs = { "Battle Shout", "Shield Block", "Last Stand", "Shield Wall", "Bloodrage" },
          debuffs = { TAUNTS, "Sunder Armor", "Rend", "Thunder Clap", "Demoralizing Shout", "Concussion Blow", "Disarm" },
          procs = { "Bastion", "Enrage" } },
    },

    -- From Forever's own class data (trainer + talents, 2026-10-11): new
    -- talents Light's Vigil and Voice of Truth (Holy), Swift Judgement and
    -- Templar's Bulwark (Protection); Holy Strike is trained. Their buffs are
    -- tracked as procs (shown only while up) until their aura names are seen.
    PALADIN = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Judgement", "Hammer of Justice", "Consecration", "Holy Strike" },
          utility = { "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Protection", "Blessing of Freedom", "Exorcism" },
          buffs = { seal("Seal of Righteousness"), blessing("Blessing of Might"), "Devotion Aura", "Divine Protection", "Divine Shield", "Blessing of Freedom", "Blessing of Protection" },
          debuffs = { MY_JUDGEMENT, "Hammer of Justice" },
          procs = {} },
        { id = "holy", name = "Holy", tree = 1,
          essential = { "Holy Shock", "Divine Favor", "Light's Vigil", "Lay on Hands", "Divine Shield" },
          utility = { "Voice of Truth", "Hammer of Justice", "Blessing of Protection", "Blessing of Freedom", "Divine Intervention", "Consecration", "Hammer of Wrath", "Exorcism", "Holy Wrath", "Turn Undead" },
          buffs = { seal("Seal of Wisdom"), blessing("Blessing of Wisdom"), "Divine Favor", "Divine Shield", "Divine Protection", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice", "Concentration Aura", "Devotion Aura" },
          debuffs = { MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Hammer of Justice" },
          procs = { "Light's Vigil", "Voice of Truth" } },
        { id = "protection", name = "Protection", tree = 2,
          essential = { "Holy Shield", "Holy Strike", "Consecration", "Judgement", "Swift Judgement", "Templar's Bulwark", "Hammer of Justice" },
          utility = { "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Protection", "Blessing of Freedom", "Hammer of Wrath", "Holy Wrath", "Exorcism" },
          buffs = { seal("Seal of Fury"), blessing("Blessing of Kings"), "Holy Shield", "Righteous Fury", "Devotion Aura", "Divine Protection", "Divine Shield", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice" },
          debuffs = { TAUNTS, MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Hammer of Justice" },
          procs = { "Redoubt", "Templar's Bulwark", "Swift Judgement" } },
        { id = "retribution", name = "Retribution", tree = 3,
          essential = { "Judgement", "Holy Strike", "Consecration", "Exorcism", "Hammer of Wrath", "Repentance" },
          utility = { "Hammer of Justice", "Divine Shield", "Divine Protection", "Lay on Hands", "Blessing of Freedom", "Blessing of Protection", "Holy Wrath" },
          buffs = { seal("Seal of Command"), blessing("Blessing of Might"), "Retribution Aura", "Divine Shield", "Divine Protection", "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice" },
          debuffs = { MY_JUDGEMENT, OTHERS_JUDGEMENTS, "Repentance", "Hammer of Justice" },
          procs = { "Vengeance", "Vindication" } },
    },

    -- From Forever's own class data (trainer + talents, 2026-10-11): Aimed
    -- Shot is trained, not a talent; new: Sniper Shot (Marksmanship talent and
    -- trained ranks), Summon Hawk (Beast Mastery), Strider Kick (Survival);
    -- Wyvern Sting doesn't exist. Tranquilizing Shot comes from a book.
    HUNTER = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Arcane Shot", "Multi-Shot", "Raptor Strike", "Mongoose Bite", "Aimed Shot" },
          utility = { "Concussive Shot", "Feign Death", "Freezing Trap", "Immolation Trap", "Disengage", "Rapid Fire" },
          buffs = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah" },
          debuffs = { "Hunter's Mark", "Serpent Sting", "Wing Clip", "Concussive Shot" },
          procs = {} },
        { id = "beastmastery", name = "Beast Mastery", tree = 1,
          essential = { "Bestial Wrath", "Intimidation", "Rapid Fire", "Aimed Shot", "Multi-Shot", "Arcane Shot" },
          utility = { "Summon Hawk", "Concussive Shot", "Feign Death", "Freezing Trap", "Frost Trap", "Immolation Trap", "Explosive Trap", "Scare Beast", "Disengage" },
          buffs = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast", "Trueshot Aura", "Rapid Fire" },
          debuffs = { "Hunter's Mark", "Serpent Sting", "Scorpid Sting", "Viper Sting", "Concussive Shot", "Wing Clip", "Freezing Trap", "Intimidation" },
          procs = { "Quick Shots", "Focused Fire" } },
        { id = "marksmanship", name = "Marksmanship", tree = 2,
          essential = { "Aimed Shot", "Sniper Shot", "Multi-Shot", "Arcane Shot", "Rapid Fire" },
          utility = { "Scatter Shot", "Concussive Shot", "Feign Death", "Freezing Trap", "Distracting Shot", "Flare", "Disengage" },
          buffs = { "Trueshot Aura", "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Rapid Fire" },
          debuffs = { "Hunter's Mark", "Serpent Sting", "Scorpid Sting", "Viper Sting", "Scatter Shot", "Concussive Shot" },
          procs = { "Quick Shots", "Rapid Killing", "Careful Aim" } },
        { id = "survival", name = "Survival", tree = 3,
          essential = { "Mongoose Bite", "Raptor Strike", "Counterattack", "Strider Kick", "Multi-Shot", "Arcane Shot" },
          utility = { "Deterrence", "Disengage", "Feign Death", "Freezing Trap", "Immolation Trap", "Explosive Trap", "Frost Trap", "Rapid Fire" },
          buffs = { "Aspect of the Monkey", "Aspect of the Hawk", "Deterrence", "Rapid Fire" },
          debuffs = { "Wing Clip", "Serpent Sting", "Hunter's Mark", "Counterattack", "Immolation Trap", "Explosive Trap", "Expose Prey", "Lacerating Strikes" },
          procs = { "Predator's Edge" } },
    },

    ROGUE = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Kick", "Gouge", "Kidney Shot", "Riposte" },
          utility = { "Sprint", "Evasion", "Vanish", "Blind", "Feint" },
          buffs = { "Slice and Dice", "Sprint", "Evasion", "Stealth" },
          debuffs = { "Rupture", "Garrote", "Expose Armor", "Gouge", "Kidney Shot", "Cheap Shot" },
          procs = {} },
        { id = "assassination", name = "Assassination", tree = 1,
          essential = { "Cold Blood", "Kidney Shot", "Kick", "Gouge", "Vanish" },
          utility = { "Sprint", "Evasion", "Blind", "Feint", "Distract", "Preparation" },
          buffs = { "Slice and Dice", "Venom", "Cold Blood", "Sprint", "Evasion", "Stealth" },
          debuffs = { "Rupture", "Garrote", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison", "Expose Armor", "Kidney Shot", "Cheap Shot", "Gouge" },
          procs = { "Remorseless" } },
        { id = "combat", name = "Combat", tree = 2,
          essential = { "Blade Flurry", "Adrenaline Rush", "Riposte", "Kick", "Gouge" },
          utility = { "Sprint", "Evasion", "Vanish", "Blind", "Kidney Shot", "Feint" },
          buffs = { "Slice and Dice", "Blade Flurry", "Adrenaline Rush", "Evasion", "Sprint" },
          debuffs = { "Rupture", "Expose Armor", "Crippling Poison", "Wound Poison", "Deadly Poison", "Kidney Shot", "Gouge", "Riposte" },
          procs = {} },
        { id = "subtlety", name = "Subtlety", tree = 3,
          essential = { "Preparation", "Premeditation", "Ghostly Strike", "Kick", "Vanish" },
          utility = { "Sprint", "Evasion", "Blind", "Gouge", "Kidney Shot", "Distract" },
          buffs = { "Slice and Dice", "Ghostly Strike", "Stealth", "Evasion", "Sprint" },
          debuffs = { "Hemorrhage", "Rupture", "Garrote", "Expose Armor", "Sap", "Cheap Shot", "Kidney Shot", "Blind" },
          procs = { "Thousand Cuts", "Cutthroat" } },
    },

    PRIEST = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Power Word: Shield", "Mind Blast", "Psychic Scream", "Fade" },
          utility = { "Fear Ward" },
          buffs = { "Power Word: Fortitude", "Inner Fire", "Power Word: Shield", "Renew", "Fade" },
          debuffs = { "Shadow Word: Pain", "Mind Flay" },
          procs = {} },
        { id = "discipline", name = "Discipline", tree = 1,
          essential = { "Penance", "Power Infusion", "Inner Focus", "Power Word: Shield" },
          utility = { "Psychic Scream", "Fade", "Fear Ward" },
          buffs = { "Power Word: Fortitude", "Divine Spirit", "Inner Fire", "Power Word: Shield", "Power Infusion", "Inner Focus", "Fear Ward", "Shadow Protection", "Fade" },
          debuffs = { "Shadow Word: Pain" },
          procs = { "Focused Casting" } },
        { id = "holy", name = "Holy", tree = 2,
          essential = { "Prayer of Mending", "Power Word: Shield", "Fear Ward" },
          utility = { "Psychic Scream", "Fade" },
          buffs = { "Inner Fire", "Power Word: Fortitude", "Divine Spirit", "Fear Ward", "Renew", "Prayer of Mending", "Fade" },
          debuffs = { "Shadow Word: Pain" },
          procs = {} },
        { id = "shadow", name = "Shadow", tree = 3,
          essential = { "Mind Blast", "Silence", "Psychic Scream", "Fade" },
          utility = { "Inner Focus", "Power Word: Shield", "Devouring Plague", "Fear Ward" },
          buffs = { "Shadowform", "Inner Fire", "Power Word: Fortitude", "Shadow Protection", "Power Word: Shield", "Fade" },
          debuffs = { "Shadow Word: Pain", "Vampiric Embrace", "Mind Flay", "Devouring Plague", "Shadow Vulnerability", "Silence", "Psychic Scream", "Blackout" },
          procs = { "Shadow Weaving", "Spirit Tap" } },
    },

    SHAMAN = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Earth Shock", "Flame Shock", "Frost Shock", "Chain Lightning", "Fire Nova" },
          utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation" },
          buffs = { "Lightning Shield" },
          debuffs = { "Flame Shock", "Frost Shock", "Earthbind" },
          procs = {} },
        { id = "elemental", name = "Elemental", tree = 1,
          essential = { "Lava Burst", "Earth Shock", "Flame Shock", "Frost Shock", "Chain Lightning", "Fire Nova" },
          utility = { "Grounding Totem", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation", "Astral Recall" },
          buffs = { "Lightning Shield" },
          debuffs = { "Flame Shock", "Frost Shock", "Earthbind" },
          procs = { "Clearcasting" } },
        { id = "enhancement", name = "Enhancement", tree = 2,
          essential = { "Stormstrike", "Rage of the Farseer", "Earth Shock", "Flame Shock", "Frost Shock" },
          utility = { "Grounding Totem", "Fire Nova", "Stoneclaw Totem", "Earthbind Totem", "Totemic Recall", "Reincarnation" },
          buffs = { "Lightning Shield", "Rage of the Farseer" },
          debuffs = { "Stormstrike", "Flame Shock", "Frost Shock", "Earthbind" },
          procs = { "Maelstrom Weapon", "Flurry", "Elemental Devastation" } },
        { id = "restoration", name = "Restoration", tree = 3,
          essential = { "Riptide", "Nature's Swiftness", "Mana Tide Totem", "Earth Shock" },
          utility = { "Grounding Totem", "Tremor Totem", "Earthbind Totem", "Reincarnation", "Purge" },
          buffs = { "Water Shield", "Lightning Shield", "Nature's Swiftness", "Mana Spring", "Mana Tide Totem" },
          debuffs = { "Flame Shock", "Frost Shock" },
          procs = { "Clearcasting" } },
    },

    -- From Forever's own class data (trainer + talents, 2026-10-11): Arcane
    -- Blast (Arcane) and Ice Lance (Frost) are new talents, also trained; Ice
    -- Block is a Frost talent; Frostfire Bolt is trained; new proc talents
    -- Missile Barrage, Heating Up, Fingers of Frost.
    MAGE = {
        { id = "unspecced", name = "Unspecced", tree = 0,
       
          essential = { "Fire Blast", "Frost Nova", "Cone of Cold", "Counterspell" },
          utility = { "Blink", "Evocation", "Fire Ward", "Frost Ward" },
          buffs = { armors("Frost Armor"), "Arcane Intellect", "Mana Shield" },
          debuffs = { "Polymorph", "Frost Nova", "Frostbolt", "Fireball" },
          { "Clearcasting" } },
        { id = "arcane", name = "Arcane", tree = 1,
       
          essential = { "Arcane Power", "Presence of Mind", "Evocation", "Counterspell" },
          utility = { "Blink", "Frost Nova", "Cone of Cold", "Fire Blast", "Fire Ward", "Frost Ward" },
          buffs = { armors("Mage Armor"), "Arcane Intellect", "Arcane Power", "Presence of Mind", "Mana Shield", "Evocation" },
          debuffs = { "Polymorph", "Counterspell - Silenced", "Frost Nova" },
          { "Clearcasting", "Missile Barrage", "Arcane Blast" } },
        { id = "fire", name = "Fire", tree = 2,
       
          essential = { "Fire Blast", "Combustion", "Blast Wave", "Counterspell" },
          utility = { "Blink", "Frost Nova", "Cone of Cold", "Evocation", "Fire Ward" },
          buffs = { armors("Mage Armor"), "Combustion", "Arcane Intellect", "Fire Ward" },
          debuffs = { "Ignite", "Fire Vulnerability", "Pyroblast", "Fireball", "Blast Wave", "Frostfire Bolt", "Polymorph" },
          { "Clearcasting", "Heating Up" } },
        { id = "frost", name = "Frost", tree = 3,
       
          essential = { "Frost Nova", "Cone of Cold", "Ice Barrier", "Cold Snap", "Ice Block", "Counterspell" },
          utility = { "Blink", "Evocation", "Fire Blast", "Frost Ward", "Fire Ward" },
          buffs = { armors("Ice Armor"), "Ice Barrier", "Arcane Intellect", "Frost Ward", "Ice Block" },
          debuffs = { "Frostbolt", "Frost Nova", "Cone of Cold", "Winter's Chill", "Frostbite", "Chilled", "Frostfire Bolt", "Polymorph" },
          { "Clearcasting", "Fingers of Frost" } },
    },

    WARLOCK = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Death Coil", "Shadow Ward", "Howl of Terror" },
          utility = {},
          buffs = { "Demon Skin", "Demon Armor", "Shadow Ward" },
          debuffs = { "Corruption", "Bane of Agony", "Immolate", "Fear", "Curse of Weakness" },
          procs = { "Shadow Trance" } },
        { id = "affliction", name = "Affliction", tree = 1,
          essential = { "Amplify Curse", "Death Coil", "Howl of Terror", "Shadow Ward" },
          utility = { "Fel Domination", "Bane of Doom" },
          buffs = { "Demon Armor", "Demon Skin", "Shadow Ward", "Amplify Curse" },
          debuffs = { "Corruption", "Bane of Agony", "Wrack", "Siphon Life", "Curse of Exhaustion", "Curse of Weakness", "Curse of Tongues", "Curse of the Elements", "Curse of Recklessness", "Bane of Doom", "Drain Life", "Drain Soul", "Fear", "Death Coil", "Immolate" },
          procs = { "Shadow Trance" } },
        { id = "demonology", name = "Demonology", tree = 2,
          essential = { "Fel Domination", "Death Coil", "Shadow Ward" },
          utility = { "Howl of Terror", "Bane of Doom" },
          buffs = { "Demon Armor", "Soul Link", "Shadow Ward", "Touch of Fire", "Burning Shadow", "Fel Stamina", "Fel Energy" },
          debuffs = { "Corruption", "Bane of Agony", "Immolate", "Fear", "Death Coil", "Banish" },
          procs = { "Shadow Trance" } },
        { id = "destruction", name = "Destruction", tree = 3,
          essential = { "Conflagrate", "Shadowburn", "Death Coil", "Shadow Ward" },
          utility = { "Howl of Terror", "Bane of Havoc", "Fel Domination" },
          buffs = { "Demon Armor", "Shadow Ward" },
          debuffs = { "Immolate", "Bane of Havoc", "Corruption", "Curse of the Elements", "Shadow Vulnerability", "Shadowburn" },
          procs = { "Shadow Trance" } },
    },

    -- From Forever's own class data (trainer + talents, 2026-10-11): new
    -- talents Berserk, Primal Bite, Shifting Power (Feral) and Wild Growth
    -- (Restoration); Lacerate is trained; Tiger's Fury doesn't exist.
    DRUID = {
        { id = "unspecced", name = "Unspecced", tree = 0,
          essential = { "Barkskin", "Innervate", "Nature's Grasp", "Bash" },
          utility = { "Rebirth", "Tranquility", "Dash", "Faerie Fire" },
          buffs = { "Mark of the Wild", "Thorns", "Barkskin", "Innervate", "Omen of Clarity" },
          debuffs = { "Moonfire", "Faerie Fire", "Entangling Roots", "Demoralizing Roar" },
          procs = { "Clearcasting" } },
        { id = "balance", name = "Balance", tree = 1,
          essential = { "Hurricane", "Innervate", "Barkskin", "Nature's Grasp" },
          utility = { "Rebirth", "Tranquility", "Dash", "Faerie Fire" },
          buffs = { "Mark of the Wild", "Thorns", "Omen of Clarity", "Moonkin Form", "Barkskin", "Nature's Grasp", "Innervate" },
          debuffs = { "Moonfire", "Insect Swarm", "Faerie Fire", "Entangling Roots", "Hibernate" },
          procs = { "Clearcasting" } },
        { id = "feralcat", name = "Feral (cat)", tree = 2,
          essential = { "Berserk", "Primal Bite", "Faerie Fire", "Cower", "Dash" },
          utility = { "Shifting Power", "Barkskin", "Innervate", "Rebirth", "Prowl" },
          buffs = { "Berserk", "Dash", "Prowl", "Mark of the Wild", "Thorns", "Omen of Clarity" },
          debuffs = { "Rake", "Rip", "Faerie Fire", "Pounce Bleed", "Pounce" },
          procs = { "Clearcasting", "Shifting Power" } },
        { id = "feralbear", name = "Feral (bear)", tree = 2,
          essential = { "Growl", "Feral Charge", "Bash", "Enrage", "Berserk" },
          utility = { "Challenging Roar", "Frenzied Regeneration", "Shifting Power", "Barkskin", "Innervate", "Rebirth", "Faerie Fire" },
          buffs = { "Frenzied Regeneration", "Enrage", "Berserk", "Barkskin", "Mark of the Wild", "Thorns", "Omen of Clarity" },
          debuffs = { TAUNTS, "Demoralizing Roar", "Faerie Fire", "Lacerate", "Bash" },
          procs = { "Clearcasting", "Shifting Power" } },
        { id = "restoration", name = "Restoration", tree = 3,
          essential = { "Swiftmend", "Wild Growth", "Nature's Swiftness", "Innervate", "Tranquility" },
          utility = { "Rebirth", "Barkskin", "Nature's Grasp" },
          buffs = { "Mark of the Wild", "Thorns", "Innervate", "Nature's Swiftness", "Barkskin", "Rejuvenation", "Regrowth", "Wild Growth", "Omen of Clarity" },
          debuffs = { "Entangling Roots", "Faerie Fire" },
          procs = { "Clearcasting" } },
    },
}
