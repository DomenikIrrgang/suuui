-- Money: one spelling for the whole addon, and the coin colours it uses.
--
-- These two live together because they are one decision split across the token/fact boundary:
-- Core/Game says what gold LOOKS like (a client fact, like an item quality colour), Core/Readout says
-- how money is SPELLED (a presentation choice every surface has to make the same way). The bug that
-- prompted them was the second half: the tooltip and the inventory footer had each grown a formatter.
local H = require("harness.init")

describe("Core/Readout money", function()
    before_each(function() H.setup() end)

    local function R() return H.SuuUI.Readout end

    describe("splitting", function()
        it("splits copper into the three denominations", function()
            local g, s, c = R().MoneyParts(1234567)
            expect(g).eq(123)
            expect(s).eq(45)
            expect(c).eq(67)
        end)

        it("answers zeroes rather than nil for junk, so a caller cannot unpack nil", function()
            local g, s, c = R().MoneyParts(nil)
            expect(g).eq(0)
            expect(s).eq(0)
            expect(c).eq(0)
        end)
    end)

    describe("spelling", function()
        it("prints all three when all three are present", function()
            expect(R().Money(1234567)).eq("123g 45s 67c")
        end)

        -- The asymmetry the tooltip learned: a leading zero unit is noise, a trailing one is meaning.
        it("drops a LEADING zero denomination", function()
            expect(R().Money(4567)).as("no 0g").eq("45s 67c")
            expect(R().Money(67)).as("no 0g 0s").eq("67c")
        end)

        it("KEEPS a zero denomination once a larger one is present", function()
            -- "12g 88c" and "12g 88s" are different prices, so the letters cannot be inferred.
            expect(R().Money(120088)).as("the 0s has to stay").eq("12g 0s 88c")
        end)

        it("renders an empty purse as 0c rather than an empty string", function()
            expect(R().Money(0)).eq("0c")
        end)

        it("returns nil for junk and for a negative amount", function()
            expect(R().Money(nil)).eq(nil)
            expect(R().Money("x")).eq(nil)
            expect(R().Money(-5)).as("a negative purse is not a reading").eq(nil)
        end)
    end)

    describe("colouring", function()
        it("colours the UNIT LETTER and leaves the figure alone", function()
            local Game = H.SuuUI.Game
            local out = R().Money(1234567, { colored = true })
            expect(out:find(Game:CoinColorCode("GOLD") .. "g|r", 1, true))
                .as("the g carries the gold colour").truthy()
            expect(out:find(Game:CoinColorCode("SILVER") .. "s|r", 1, true))
                .as("the s carries the silver colour").truthy()
            expect(out:find(Game:CoinColorCode("COPPER") .. "c|r", 1, true))
                .as("the c carries the copper colour").truthy()
            -- The point of the change: the amount is the reading and stays in the caller's own
            -- colour. Colouring the whole segment painted the figure gold and buried it.
            expect(out:find("|cff%x%x%x%x%x%x%d"))
                .as("no escape opens directly onto a digit").eq(nil)
            expect(out:find("123", 1, true)).as("the figure is still there, plain").truthy()
        end)

        it("uses three DIFFERENT colours", function()
            local Game = H.SuuUI.Game
            local g, s, c = Game:CoinColorCode("GOLD"), Game:CoinColorCode("SILVER"),
                            Game:CoinColorCode("COPPER")
            expect(g ~= s and s ~= c and g ~= c).as("a shared colour would defeat the point").truthy()
        end)

        it("closes every escape it opens", function()
            local out = R().Money(1234567, { colored = true })
            local opens, closes = 0, 0
            for _ in out:gmatch("|cff") do opens = opens + 1 end
            for _ in out:gmatch("|r") do closes = closes + 1 end
            expect(opens).as("three denominations, three escapes").eq(3)
            expect(closes).as("an unclosed escape bleeds into the next line").eq(3)
        end)

        it("is uncoloured by default, so a caller opts in", function()
            expect(R().Money(1234567):find("|cff", 1, true))
                .as("no escape unless asked for").eq(nil)
        end)
    end)

    describe("density options", function()
        it("groups thousands only when asked", function()
            expect(R().Money(12844218)).as("dense by default").eq("1284g 42s 18c")
            expect(R().Money(12844218, { groupThousands = true })).eq("1,284g 42s 18c")
        end)

        it("spaces the unit letter only when asked", function()
            expect(R().Money(12844218, { spaceUnits = true })).eq("1284 g 42 s 18 c")
        end)

        it("matches the concept's footer spelling with all three on", function()
            local plain = R().Money(12844218, {
                colored = true, groupThousands = true, spaceUnits = true,
            }):gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", "")
            expect(plain).eq("1,284 g 42 s 18 c")
        end)

        -- The tooltip shares this function for vendor prices, where the dense form is right. If the
        -- defaults ever flip, a price line silently gains spaces and separators.
        it("leaves the tooltip's dense default untouched", function()
            expect(R().Money(120088)).eq("12g 0s 88c")
        end)
    end)

    describe("thousands grouping", function()
        it("groups from the right in threes", function()
            expect(R().GroupNumber(1)).eq("1")
            expect(R().GroupNumber(999)).eq("999")
            expect(R().GroupNumber(1000)).eq("1,000")
            expect(R().GroupNumber(1234567)).as("more than one group").eq("1,234,567")
        end)

        it("uses the client's own separator, so a locale is not overridden", function()
            H.env.LARGE_NUMBER_SEPERATOR = "."
            expect(R().GroupNumber(1234567)).as("German client").eq("1.234.567")
        end)
    end)
end)

describe("Core/Game coin colours", function()
    before_each(function() H.setup() end)

    it("answers a colour for each denomination", function()
        for _, kind in ipairs({ "GOLD", "SILVER", "COPPER" }) do
            local c = H.SuuUI.Game:CoinColor(kind)
            expect(type(c)).as(kind .. " has a colour").eq("table")
            expect(#c >= 3).as(kind .. " is a usable rgb").truthy()
        end
    end)

    it("is case-insensitive, since a caller may hold a lowercase key", function()
        expect(H.SuuUI.Game:CoinColor("gold")).eq(H.SuuUI.Game:CoinColor("GOLD"))
    end)

    it("returns nil for anything that is not a denomination", function()
        expect(H.SuuUI.Game:CoinColor("platinum")).eq(nil)
        expect(H.SuuUI.Game:CoinColor(nil)).eq(nil)
        expect(H.SuuUI.Game:CoinColorCode(nil)).eq(nil)
    end)

    -- Gold reads as yellow: red and green high, blue absent. Pinned as a PROPERTY rather than as the
    -- hex, so the assertion says what the colour has to MEAN and survives a nudge to the value.
    it("gives gold a yellow hue and copper a warmer one than silver", function()
        local Game = H.SuuUI.Game
        local gold, silver, copper = Game:CoinColor("GOLD"), Game:CoinColor("SILVER"),
                                     Game:CoinColor("COPPER")
        expect(gold[3] < gold[1] and gold[3] < gold[2]).as("gold is yellow, not blue").truthy()
        expect(silver[1]).as("silver is near-neutral").near(silver[2], 0.05)
        expect(copper[1] - copper[3]).as("copper is warmer than silver")
            .gt(silver[1] - silver[3])
    end)

    it("caches the escape code without recomputing it", function()
        local Game = H.SuuUI.Game
        expect(Game:CoinColorCode("GOLD")).eq(Game:CoinColorCode("GOLD"))
    end)

    -- The values were copied off ElvUI's install to be exactly Blizzard's; emitting a hex that is one
    -- step off would discard the only reason to copy them. Two decimals did exactly that (ffd600).
    it("emits exactly the source hexes it documents", function()
        local Game = H.SuuUI.Game
        expect(Game:CoinColorCode("GOLD")).eq("|cffffd700")
        expect(Game:CoinColorCode("SILVER")).eq("|cffc7c7cf")
        expect(Game:CoinColorCode("COPPER")).eq("|cffeda55f")
    end)
end)
