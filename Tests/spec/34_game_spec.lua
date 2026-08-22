
-- Core/Game.lua — facts about the client that the UI paints with.
--
-- Two things are load-bearing here and neither is obvious from reading the module. The
-- combat log is the ONLY source of a spell's school in this client, so a parsing mistake
-- silently caches a wrong colour against a real spell id; and LearnFromCombatLog has to
-- keep reporting a school it already knows, because two cast bars read the same line and
-- whichever ran second would otherwise never hear about its own spell.

local Game = function() return H.SuuUI.Game end

-- Feeds one combat log payload through LearnFromCombatLog the way a live handler does:
-- during the event and never outside it, which is the only time the client answers.
local function readLine(payload)
    payload.n = #payload
    H.state.combatLogEvent = payload
    local id, mask = Game():LearnFromCombatLog()
    H.state.combatLogEvent = nil
    return id, mask
end

local function spellLine(subevent, spellId, school)
    return { 0, subevent, false, "GUID-caster", "Caster", 0, 0,
             "GUID-victim", "Victim", 0, 0, spellId, "Some Spell", school }
end

describe("Core.Game", function()
    before_each(function()
        H.setup()
    end)

    ---------------------------------------------------------------------------
    -- 1. Power colours
    ---------------------------------------------------------------------------
    describe("power colours", function()
        it("returns a four-component colour per power type", function()
            for powerType = 0, 6 do
                local c = Game():PowerColor(powerType)
                expect(type(c)).eq("table")
                expect(#c).as("power " .. powerType).eq(4)
            end
        end)

        it("mana and rage are different colours", function()
            local mana, rage = Game():PowerColor(0), Game():PowerColor(1)
            expect(mana[1] == rage[1] and mana[2] == rage[2] and mana[3] == rage[3])
                .eq(false)
        end)

        it("falls back to mana for a power type this client does not name", function()
            expect(Game():PowerColor(99)).eq(Game():PowerColor(0))
            expect(Game():PowerColor(nil)).eq(Game():PowerColor(0))
        end)

        it("hands out the same table every call, so nothing allocates per paint", function()
            expect(Game():PowerColor(3)).eq(Game():PowerColor(3))
        end)
    end)

    ---------------------------------------------------------------------------
    -- 2. School colours
    ---------------------------------------------------------------------------
    describe("school colours", function()
        it("names the seven school bits", function()
            local S = Game().SCHOOL
            expect(S.PHYSICAL).eq(0x01)
            expect(S.HOLY).eq(0x02)
            expect(S.FIRE).eq(0x04)
            expect(S.NATURE).eq(0x08)
            expect(S.FROST).eq(0x10)
            expect(S.SHADOW).eq(0x20)
            expect(S.ARCANE).eq(0x40)
        end)

        it("gives every pure school its own colour", function()
            local seen = {}
            for _, mask in ipairs({ 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40 }) do
                local c = Game():SchoolColor(mask)
                expect(type(c)).as("mask " .. mask).eq("table")
                expect(#c).eq(4)
                local key = string.format("%.2f/%.2f/%.2f", c[1], c[2], c[3])
                expect(seen[key]).as("mask " .. mask .. " duplicates another school").isNil()
                seen[key] = mask
            end
        end)

        it("names the two mixed masks the client itself names", function()
            expect(type(Game():SchoolColor(0x7E))).eq("table")  -- Magic
            expect(type(Game():SchoolColor(0x7F))).eq("table")  -- Chaos
        end)

        it("blends a multi-school mask from its parts", function()
            local fire  = Game():SchoolColor(0x04)
            local frost = Game():SchoolColor(0x10)
            local mixed = Game():SchoolColor(0x14)
            for i = 1, 3 do
                expect(mixed[i]).near((fire[i] + frost[i]) / 2, 0.0001)
            end
            expect(mixed[4]).eq(1)
        end)

        it("a blend is neither of its parts, so the mix is visible as a mix", function()
            local fire  = Game():SchoolColor(0x04)
            local mixed = Game():SchoolColor(0x14)
            expect(mixed[1] == fire[1] and mixed[2] == fire[2] and mixed[3] == fire[3])
                .eq(false)
        end)

        it("memoises a blend rather than allocating per call", function()
            expect(Game():SchoolColor(0x14)).eq(Game():SchoolColor(0x14))
        end)

        it("returns nil for a mask that says nothing, so callers can fall back", function()
            expect(Game():SchoolColor(nil)).isNil()
            expect(Game():SchoolColor(0)).isNil()
            expect(Game():SchoolColor(-4)).isNil()
            expect(Game():SchoolColor("fire")).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 3. The learned cache
    ---------------------------------------------------------------------------
    describe("learned schools", function()
        it("knows nothing until something reports a school", function()
            expect(Game():SchoolOf(133)).isNil()
        end)

        it("reads back what was learned", function()
            Game():LearnSchool(133, 0x04)
            expect(Game():SchoolOf(133)).eq(0x04)
        end)

        it("reports whether the learn changed anything", function()
            expect(Game():LearnSchool(133, 0x04)).eq(true)
            expect(Game():LearnSchool(133, 0x04)).as("same school again").eq(false)
            expect(Game():LearnSchool(133, 0x10)).as("corrected").eq(true)
        end)

        it("refuses a mask of zero rather than caching 'no school'", function()
            expect(Game():LearnSchool(133, 0)).eq(false)
            expect(Game():SchoolOf(133)).isNil()
        end)

        it("refuses non-numeric ids and masks", function()
            expect(Game():LearnSchool("133", 0x04)).eq(false)
            expect(Game():LearnSchool(133, "fire")).eq(false)
            expect(Game():SchoolOf("133")).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 4. Reading the combat log
    ---------------------------------------------------------------------------
    describe("LearnFromCombatLog", function()
        it("learns from a cast line", function()
            local id, mask = readLine(spellLine("SPELL_CAST_START", 133, 0x04))
            expect(id).eq(133)
            expect(mask).eq(0x04)
            expect(Game():SchoolOf(133)).eq(0x04)
        end)

        it("learns from a damage tick, which is all a channel ever produces", function()
            readLine(spellLine("SPELL_PERIODIC_DAMAGE", 10, 0x10))
            expect(Game():SchoolOf(10)).eq(0x10)
        end)

        it("learns from a ranged line", function()
            readLine(spellLine("RANGE_DAMAGE", 75, 0x01))
            expect(Game():SchoolOf(75)).eq(0x01)
        end)

        it("reports a school it already knew, so a second reader still hears it", function()
            readLine(spellLine("SPELL_CAST_START", 133, 0x04))
            local id, mask = readLine(spellLine("SPELL_DAMAGE", 133, 0x04))
            expect(id).as("second handler on the same spell").eq(133)
            expect(mask).eq(0x04)
        end)

        it("ignores a swing line, whose slot 12 is a damage number", function()
            local id = readLine({ 0, "SWING_DAMAGE", false, "GUID-caster", "Caster", 0, 0,
                                  "GUID-victim", "Victim", 0, 0, 4200, -1, 1 })
            expect(id).isNil()
            expect(Game():SchoolOf(4200)).isNil()
        end)

        it("ignores SPELL_ABSORBED, whose slot 12 can be a GUID", function()
            local id = readLine(spellLine("SPELL_ABSORBED", 133, 0x04))
            expect(id).isNil()
            expect(Game():SchoolOf(133)).isNil()
        end)

        it("ignores an environmental line", function()
            local id = readLine({ 0, "ENVIRONMENTAL_DAMAGE", false, nil, nil, 0, 0,
                                  "GUID-victim", "Victim", 0, 0, "FALLING", 500, 1 })
            expect(id).isNil()
        end)

        it("ignores a line reporting no school", function()
            local id = readLine(spellLine("SPELL_CAST_START", 133, 0))
            expect(id).isNil()
            expect(Game():SchoolOf(133)).isNil()
        end)

        it("returns nothing outside a combat log event", function()
            expect(Game():LearnFromCombatLog()).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 5. Class colours
    ---------------------------------------------------------------------------
    describe("class colours", function()
        it("returns a four-component colour for a known class", function()
            local rcc = H.env.RAID_CLASS_COLORS
            local c = Game():ClassColor("WARRIOR")
            expect(type(c)).eq("table")
            expect(#c).eq(4)
            expect(c[1]).eq(rcc.WARRIOR.r)
            expect(c[2]).eq(rcc.WARRIOR.g)
            expect(c[3]).eq(rcc.WARRIOR.b)
            expect(c[4]).eq(1)
        end)

        it("prefers the client RAID_CLASS_COLORS over the internal fallback", function()
            H.env.RAID_CLASS_COLORS.MAGE = { r = 0.99, g = 0.11, b = 0.22 }
            local c = Game():ClassColor("MAGE")
            expect(c[1]).eq(0.99)
            expect(c[2]).eq(0.11)
            expect(c[3]).eq(0.22)
            expect(c[4]).eq(1)
        end)

        it("CUSTOM_CLASS_COLORS wins over RAID_CLASS_COLORS when both present", function()
            H.env.CUSTOM_CLASS_COLORS = {
                DRUID = { r = 0.10, g = 0.20, b = 0.30 },
            }
            local c = Game():ClassColor("DRUID")
            expect(c[1]).eq(0.10)
            expect(c[2]).eq(0.20)
            expect(c[3]).eq(0.30)
            expect(c[4]).eq(1)
            H.env.CUSTOM_CLASS_COLORS = nil
        end)

        it("picks up runtime mutations to the source (cache validation)", function()
            local c1 = Game():ClassColor("HUNTER")
            expect(c1[1]).eq(H.env.RAID_CLASS_COLORS.HUNTER.r)
            -- Mutate the live source
            H.env.RAID_CLASS_COLORS.HUNTER = { r = 0.01, g = 0.02, b = 0.03 }
            local c2 = Game():ClassColor("HUNTER")
            expect(c2[1]).eq(0.01)
            expect(c2[2]).eq(0.02)
            expect(c2[3]).eq(0.03)
        end)

        it("repeated reads with an unchanged source return the same table identity", function()
            local a = Game():ClassColor("PALADIN")
            local b = Game():ClassColor("PALADIN")
            expect(a).eq(b)
        end)

        it("returns nil for unknown, non-string and empty-string inputs", function()
            expect(Game():ClassColor("BARD")).isNil()
            expect(Game():ClassColor("")).isNil()
            expect(Game():ClassColor(nil)).isNil()
            expect(Game():ClassColor(42)).isNil()
            expect(Game():ClassColor(true)).isNil()
        end)

        it("resolves from the internal fallback when neither client global is present", function()
            H.env.RAID_CLASS_COLORS = nil
            H.env.CUSTOM_CLASS_COLORS = nil
            local c = Game():ClassColor("WARRIOR")
            expect(type(c)).eq("table")
            expect(#c).eq(4)
            -- Pin the actual fallback values, not merely "a colour": asserting c[1] > 0
            -- would pass even if the internal table had drifted to the wrong hue, which is
            -- the only thing this branch exists to provide.
            expect(c[1]).near(0.78, 0.005)
            expect(c[2]).near(0.61, 0.005)
            expect(c[3]).near(0.43, 0.005)
            expect(c[4]).eq(1)
        end)

        it("UnitClassColor matches ClassColor for the harness class", function()
            local byClass = Game():ClassColor("WARRIOR")
            local byUnit  = Game():UnitClassColor("player")
            expect(byUnit[1]).eq(byClass[1])
            expect(byUnit[2]).eq(byClass[2])
            expect(byUnit[3]).eq(byClass[3])
            expect(byUnit[4]).eq(byClass[4])
        end)

        it("UnitClassColor returns nil for a classless unit", function()
            H.state.unitClassless = true
            expect(Game():UnitClassColor("player")).isNil()
        end)

        it("UnitClassColor returns nil for a creature the client calls a warrior", function()
            -- The bug this guards: a mob is not classless. The client answers UnitClass for
            -- a creature and almost always says WARRIOR, so trusting it painted a neutral
            -- Vale Moth in warrior tan. Deliberately no `classless` here — that is the
            -- narrower totem case and would test the wrong door.
            H.setUnit("target", { name = "Vale Moth", reaction = 4 })
            expect(H.env.UnitIsPlayer("target"))
                .as("a staged unit is a creature unless the spec says otherwise").eq(false)
            local _, classFile = H.env.UnitClass("target")
            expect(classFile).as("the client still reports a class for it").eq("WARRIOR")
            expect(Game():UnitClassColor("target")).isNil()
        end)

        it("UnitClassColor still answers for a player target", function()
            H.setUnit("target", { name = "Someone", class = "MAGE", isPlayer = true })
            local c = Game():UnitClassColor("target")
            expect(c).notNil()
            expect(c).deepEq(Game():ClassColor("MAGE"))
        end)

        it("UnitClassColor returns nil for non-string unit", function()
            expect(Game():UnitClassColor(nil)).isNil()
            expect(Game():UnitClassColor(123)).isNil()
            expect(Game():UnitClassColor(true)).isNil()
        end)
    end)

    ---------------------------------------------------------------------------
    -- 6. Reaction colours
    ---------------------------------------------------------------------------
    describe("reaction colours", function()
        it("names the three band rows", function()
            local R = Game().REACTION
            expect(R.HOSTILE).eq(2)
            expect(R.NEUTRAL).eq(4)
            expect(R.FRIENDLY).eq(5)
        end)

        it("returns a four-component colour for each band, matching FACTION_BAR_COLORS", function()
            local fbc = H.env.FACTION_BAR_COLORS
            local R = Game().REACTION
            for _, row in ipairs({ R.HOSTILE, R.NEUTRAL, R.FRIENDLY }) do
                local c = Game():ReactionColor(row)
                expect(type(c)).as("band " .. row).eq("table")
                expect(#c).eq(4)
                expect(c[1]).as("r for band " .. row).eq(fbc[row].r)
                expect(c[2]).as("g for band " .. row).eq(fbc[row].g)
                expect(c[3]).as("b for band " .. row).eq(fbc[row].b)
                expect(c[4]).eq(1)
            end
        end)

        it("collapses standings 1..3 onto HOSTILE", function()
            local fbc = H.env.FACTION_BAR_COLORS
            local hostileRow = Game().REACTION.HOSTILE
            for standing = 1, 3 do
                local c = Game():ReactionColor(standing)
                expect(c[1]).as("standing " .. standing .. " r").eq(fbc[hostileRow].r)
                expect(c[2]).as("standing " .. standing .. " g").eq(fbc[hostileRow].g)
                expect(c[3]).as("standing " .. standing .. " b").eq(fbc[hostileRow].b)
            end
        end)

        it("collapses standing 4 onto NEUTRAL", function()
            local fbc = H.env.FACTION_BAR_COLORS
            local neutralRow = Game().REACTION.NEUTRAL
            local c = Game():ReactionColor(4)
            expect(c[1]).eq(fbc[neutralRow].r)
            expect(c[2]).eq(fbc[neutralRow].g)
            expect(c[3]).eq(fbc[neutralRow].b)
        end)

        it("collapses standings 5..8 onto FRIENDLY", function()
            local fbc = H.env.FACTION_BAR_COLORS
            local friendlyRow = Game().REACTION.FRIENDLY
            for standing = 5, 8 do
                local c = Game():ReactionColor(standing)
                expect(c[1]).as("standing " .. standing .. " r").eq(fbc[friendlyRow].r)
                expect(c[2]).as("standing " .. standing .. " g").eq(fbc[friendlyRow].g)
                expect(c[3]).as("standing " .. standing .. " b").eq(fbc[friendlyRow].b)
            end
        end)

        it("returns nil for nil, non-number, 0, 9, and negatives", function()
            expect(Game():ReactionColor(nil)).isNil()
            expect(Game():ReactionColor("hostile")).isNil()
            expect(Game():ReactionColor(true)).isNil()
            expect(Game():ReactionColor(0)).isNil()
            expect(Game():ReactionColor(9)).isNil()
            expect(Game():ReactionColor(-1)).isNil()
        end)

        it("prefers the live FACTION_BAR_COLORS and picks up a runtime retint", function()
            -- First call at the current source
            local c1 = Game():ReactionColor(Game().REACTION.HOSTILE)
            local fbc = H.env.FACTION_BAR_COLORS
            expect(c1[1]).eq(fbc[2].r)
            -- Retint the live global
            fbc[2] = { r = 0.11, g = 0.22, b = 0.33 }
            local c2 = Game():ReactionColor(Game().REACTION.HOSTILE)
            expect(c2[1]).eq(0.11)
            expect(c2[2]).eq(0.22)
            expect(c2[3]).eq(0.33)
            expect(c2[4]).eq(1)
        end)

        it("falls back to a usable internal copy when FACTION_BAR_COLORS is absent", function()
            H.env.FACTION_BAR_COLORS = nil
            for standing = 1, 8 do
                local c = Game():ReactionColor(standing)
                expect(type(c)).as("standing " .. standing).eq("table")
                expect(#c).eq(4)
                for i = 1, 3 do
                    expect(type(c[i])).as("channel " .. i).eq("number")
                    expect(c[i] >= 0 and c[i] <= 1).truthy()
                end
                expect(c[4]).eq(1)
            end
        end)

        it("two consecutive calls for the same band return the same table (no allocation)", function()
            local a = Game():ReactionColor(2)
            local b = Game():ReactionColor(2)
            expect(a).eq(b)
        end)

        it("different standings in the same band share identity", function()
            local a = Game():ReactionColor(1)
            local b = Game():ReactionColor(3)
            expect(a).eq(b)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 7. UnitReactionColor
    ---------------------------------------------------------------------------
    describe("UnitReactionColor", function()
        it("returns the staged reaction colour for a staged unit", function()
            H.setUnit("target", { reaction = 2 })
            local c = Game():UnitReactionColor("target")
            local expected = Game():ReactionColor(2)
            expect(c).notNil()
            expect(c).eq(expected)
        end)

        it("returns nil for an unstaged unit", function()
            expect(Game():UnitReactionColor("target")).isNil()
        end)

        it("returns nil for non-string arguments", function()
            expect(Game():UnitReactionColor(nil)).isNil()
            expect(Game():UnitReactionColor(123)).isNil()
            expect(Game():UnitReactionColor(true)).isNil()
        end)

        it("asks with the unit FIRST — target's reaction is readable, player's is not", function()
            -- UnitReaction(unit, other) reports the first's reaction toward the second.
            -- Stage a reaction on target only.
            H.setUnit("target", { reaction = 5 })
            -- UnitReactionColor("target") calls UnitReaction("target", "player") -> 5
            expect(Game():UnitReactionColor("target")).notNil()
            -- UnitReactionColor("player") calls UnitReaction("player", "player") -> nil
            -- because player has no staged per-unit reaction
            expect(Game():UnitReactionColor("player")).isNil()
        end)

        it("reflects the correct band for each standing", function()
            for standing = 1, 8 do
                H.setUnit("target", { reaction = standing })
                local c = Game():UnitReactionColor("target")
                expect(c).as("standing " .. standing).eq(Game():ReactionColor(standing))
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- 8. Theme:GetUnitColor integration (class vs reaction vs token)
    ---------------------------------------------------------------------------
    describe("GetUnitColor with reactions", function()
        it("class takes precedence over reaction for a PLAYER with both", function()
            -- Modern ships colorUseClassColors = true.
            -- A hostile enemy player has a reaction too, and their class still wins — which
            -- is why this rule exists at all. `isPlayer` is load-bearing: without it the
            -- unit is a creature and reaction is the correct answer (see the mirror below).
            H.setUnit("target", { class = "MAGE", reaction = 2, isPlayer = true })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local classColor = Game():ClassColor("MAGE")
            local reactionColor = Game():ReactionColor(2)
            expect(classColor).notNil()
            expect(reactionColor).notNil()
            expect(result).deepEq(classColor)
            -- Must NOT be the reaction colour
            local isReaction = (result[1] == reactionColor[1]
                            and result[2] == reactionColor[2]
                            and result[3] == reactionColor[3])
            expect(isReaction).as("class must win over reaction").eq(false)
        end)

        it("reaction takes precedence for a CREATURE the client reports a class for", function()
            -- The mirror, and the shipped bug: a creature carries a class field, so "both
            -- are present" describes every mob in the game. Reaction is the only meaningful
            -- answer for one.
            H.setUnit("target", { class = "MAGE", reaction = 2 })
            local result = H.T:GetUnitColor("colorHealth", "target")
            expect(result).deepEq(Game():ReactionColor(2))
        end)

        it("classless unit with reaction gets the reaction colour", function()
            -- Modern: colorUseClassColors = true
            H.setUnit("target", { classless = true, reaction = 4 })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local reactionColor = Game():ReactionColor(4)
            expect(result).deepEq(reactionColor)
        end)

        it("classless unit with no reaction falls back to the token", function()
            -- Modern: colorUseClassColors = true, no reaction staged
            H.setUnit("target", { classless = true })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local tokenColor = H.token("colorHealth")
            expect(result).deepEq(tokenColor)
        end)

        it("with colorUseClassColors OFF, classed unit gets the token", function()
            H.T:SetActive("Default")
            H.setUnit("target", { class = "MAGE", reaction = 2 })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local tokenColor = H.T:GetToken("colorHealth")
            expect(result).deepEq(tokenColor)
        end)

        it("with colorUseClassColors OFF, classless unit with reaction gets the token", function()
            H.T:SetActive("Default")
            H.setUnit("target", { classless = true, reaction = 5 })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local tokenColor = H.T:GetToken("colorHealth")
            expect(result).deepEq(tokenColor)
        end)

        it("with colorUseClassColors OFF, classless unit without reaction gets the token", function()
            H.T:SetActive("Default")
            H.setUnit("target", { classless = true })
            local result = H.T:GetUnitColor("colorHealth", "target")
            local tokenColor = H.T:GetToken("colorHealth")
            expect(result).deepEq(tokenColor)
        end)

        it("switching the flag via SetUserToken toggles reaction colouring", function()
            -- Start from a user theme based on Modern (colorUseClassColors = true)
            H.T:CreateUserTheme("ReactionTest", "Modern")
            H.T:SetActive("ReactionTest")
            H.setUnit("target", { classless = true, reaction = 2 })

            -- Flag on: reaction colour
            local reactionColor = Game():ReactionColor(2)
            expect(H.T:GetUnitColor("colorHealth", "target")).deepEq(reactionColor)

            -- Turn off: token
            H.T:SetUserToken("ReactionTest", "colorUseClassColors", false)
            local tokenColor = H.T:GetToken("colorHealth")
            expect(H.T:GetUnitColor("colorHealth", "target")).deepEq(tokenColor)

            -- Turn back on: reaction again
            H.T:SetUserToken("ReactionTest", "colorUseClassColors", true)
            expect(H.T:GetUnitColor("colorHealth", "target")).deepEq(reactionColor)
        end)
    end)

    ---------------------------------------------------------------------------
    -- 9. Debuff dispel-type colours
    --
    -- Same three-layer shape as ClassColor and ReactionColor: the client's live global
    -- first (so SuuUI agrees with an addon that has retinted debuff borders), an internal
    -- copy for the login moment before the global exists, and nil for a question that has
    -- no answer. nil is the interesting one — a debuff with no dispel type has no dispel
    -- identity, and inventing a colour for it would give the player a cue meaning nothing.
    ---------------------------------------------------------------------------
    describe("untyped debuff colour", function()
        it("reads the client's own none row", function()
            expect(H.SuuUI.Game:UntypedDebuffColor())
                .deepEq({ H.env.DebuffTypeColor.none.r, H.env.DebuffTypeColor.none.g,
                          H.env.DebuffTypeColor.none.b, 1 })
        end)

        it("is red, and distinct from every dispel type", function()
            local none = H.SuuUI.Game:UntypedDebuffColor()
            expect(none[1]).as("red channel dominates").gt(0.5)
            local function same(a, b)
                return a ~= nil and b ~= nil
                   and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
            end
            for _, t in ipairs({ "Magic", "Curse", "Disease", "Poison" }) do
                expect(same(none, H.SuuUI.Game:DebuffTypeColor(t)))
                    .as(t .. " must not collide with untyped").falsy()
            end
        end)

        it("never returns nil, unlike DebuffTypeColor", function()
            -- A debuff display always has something to paint; "no type" is an answer here
            -- rather than an absence to fall back from.
            expect(H.SuuUI.Game:DebuffTypeColor(nil)).isNil()
            expect(H.SuuUI.Game:UntypedDebuffColor()).notNil()
        end)

        it("follows a live retint of the global", function()
            H.env.DebuffTypeColor.none = { r = 0.10, g = 0.20, b = 0.30 }
            expect(H.SuuUI.Game:UntypedDebuffColor()).deepEq({ 0.10, 0.20, 0.30, 1 })
        end)

        it("falls back to its own copy when the global is unusable", function()
            H.env.DebuffTypeColor = nil
            local c = H.SuuUI.Game:UntypedDebuffColor()
            expect(c).notNil()
            expect(c[1]).gt(0.5)
        end)
    end)

    describe("debuff type colours", function()
        local TYPES = { "Magic", "Curse", "Disease", "Poison" }

        it("answers for each of the four dispel types the client names", function()
            local dtc = H.env.DebuffTypeColor
            for _, kind in ipairs(TYPES) do
                local c = Game():DebuffTypeColor(kind)
                expect(type(c)).as(kind).eq("table")
                expect(#c).as(kind .. " component count").eq(4)
                expect(c[1]).as(kind .. " r").eq(dtc[kind].r)
                expect(c[2]).as(kind .. " g").eq(dtc[kind].g)
                expect(c[3]).as(kind .. " b").eq(dtc[kind].b)
                expect(c[4]).as(kind .. " a").eq(1)
            end
        end)

        it("gives every dispel type its own colour, so a border means one thing", function()
            local seen = {}
            for _, kind in ipairs(TYPES) do
                local c = Game():DebuffTypeColor(kind)
                local key = string.format("%.2f/%.2f/%.2f", c[1], c[2], c[3])
                expect(seen[key]).as(kind .. " duplicates " .. tostring(seen[key])).isNil()
                seen[key] = kind
            end
        end)

        it("returns nil for nil, so the caller falls back to its own border", function()
            expect(Game():DebuffTypeColor(nil)).isNil()
        end)

        it("returns nil for \"none\" even though the client's global names it", function()
            -- The live DebuffTypeColor table carries a "none" row (a red), which is why the
            -- guard has to run BEFORE the lookup: reaching the global would paint every
            -- undispellable debuff red instead of leaving it on the theme's border.
            expect(H.env.DebuffTypeColor.none).as("the client really does have this row").notNil()
            expect(Game():DebuffTypeColor("none")).isNil()
        end)

        it("returns nil for an empty string and for a type this client does not name", function()
            expect(Game():DebuffTypeColor("")).isNil()
            expect(Game():DebuffTypeColor("Bleed")).isNil()
            expect(Game():DebuffTypeColor("magic")).as("the client's keys are capitalised").isNil()
        end)

        it("returns nil for non-string arguments", function()
            expect(Game():DebuffTypeColor(42)).isNil()
            expect(Game():DebuffTypeColor(true)).isNil()
            expect(Game():DebuffTypeColor({ r = 1, g = 0, b = 0 })).isNil()
        end)

        it("prefers the live global and picks up a runtime retint (cache validation)", function()
            -- The path that rots: a cached array handed back after the source moved would
            -- leave SuuUI painting last session's colour for the rest of the session.
            local c1 = Game():DebuffTypeColor("Magic")
            expect(c1[1]).eq(H.env.DebuffTypeColor.Magic.r)

            H.env.DebuffTypeColor.Magic = { r = 0.11, g = 0.22, b = 0.33 }
            local c2 = Game():DebuffTypeColor("Magic")
            expect(c2[1]).eq(0.11)
            expect(c2[2]).eq(0.22)
            expect(c2[3]).eq(0.33)
            expect(c2[4]).eq(1)
        end)

        it("revalidates per type, so retinting one leaves the others alone", function()
            local curseBefore = Game():DebuffTypeColor("Curse")
            H.env.DebuffTypeColor.Poison = { r = 0.05, g = 0.05, b = 0.05 }
            expect(Game():DebuffTypeColor("Poison")[1]).eq(0.05)
            expect(Game():DebuffTypeColor("Curse")).deepEq(curseBefore)
        end)

        it("hands out the same table every call, so nothing allocates per paint", function()
            expect(Game():DebuffTypeColor("Disease")).eq(Game():DebuffTypeColor("Disease"))
        end)

        it("falls back to the internal copy when the global is absent", function()
            H.env.DebuffTypeColor = nil
            -- Pin the actual values rather than merely "a colour": asserting a table came
            -- back would pass even if the internal copy had drifted to the wrong hue, which
            -- is the only thing this branch exists to provide.
            expect(Game():DebuffTypeColor("Magic")).deepEq({ 0.20, 0.60, 1.00, 1 })
            expect(Game():DebuffTypeColor("Curse")).deepEq({ 0.60, 0.00, 1.00, 1 })
            expect(Game():DebuffTypeColor("Disease")).deepEq({ 0.60, 0.40, 0.00, 1 })
            expect(Game():DebuffTypeColor("Poison")).deepEq({ 0.00, 0.60, 0.00, 1 })
            expect(Game():DebuffTypeColor("none")).as("still no answer").isNil()
        end)

        it("falls back when the global is present but the row is unusable", function()
            H.env.DebuffTypeColor = {
                Magic   = "blue",                          -- not a table
                Curse   = { r = "purple", g = 0, b = 1 },  -- r is not a number
                Disease = {},                              -- no channels at all
            }
            expect(Game():DebuffTypeColor("Magic")).deepEq({ 0.20, 0.60, 1.00, 1 })
            expect(Game():DebuffTypeColor("Curse")).deepEq({ 0.60, 0.00, 1.00, 1 })
            expect(Game():DebuffTypeColor("Disease")).deepEq({ 0.60, 0.40, 0.00, 1 })
            expect(Game():DebuffTypeColor("Poison"))
                .as("a row the shortened global omits entirely")
                .deepEq({ 0.00, 0.60, 0.00, 1 })
        end)

        it("survives the global being replaced by something that is not a table", function()
            H.env.DebuffTypeColor = "not a table"
            expect(Game():DebuffTypeColor("Poison")).deepEq({ 0.00, 0.60, 0.00, 1 })
            expect(Game():DebuffTypeColor("Bleed")).isNil()
        end)
    end)
end)
