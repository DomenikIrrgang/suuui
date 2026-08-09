
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

        it("UnitClassColor returns nil for non-string unit", function()
            expect(Game():UnitClassColor(nil)).isNil()
            expect(Game():UnitClassColor(123)).isNil()
            expect(Game():UnitClassColor(true)).isNil()
        end)
    end)
end)
