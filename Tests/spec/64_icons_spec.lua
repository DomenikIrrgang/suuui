-- Core/Icons: the shared UI glyph registry.
--
-- It exists so a SECOND consumer of the atlas does not have to reach into the first one's coord
-- table. The micro menu keeps its own table inside Plugins/DataBar, which is fine while it is the
-- only consumer; the inventory's sort button is the second, and a plugin reading another plugin's
-- internals is the one thing plugins may never do.
local H = require("harness.init")

describe("Core/Icons", function()
    before_each(function() H.setup() end)

    local function I() return H.SuuUI.Icons end

    it("publishes the sheet path", function()
        expect(type(I().PATH)).eq("string")
        expect(I().PATH:find("ui%-icons")).as("names the generated sheet").truthy()
    end)

    it("answers a path and coords for a known glyph", function()
        local path, coords = I():Get("sort")
        expect(path).eq(I().PATH)
        expect(type(coords)).eq("table")
        expect(#coords).as("left, right, top, bottom").eq(4)
    end)

    it("returns nil for an unknown glyph rather than a stand-in", function()
        -- A stand-in would render the WRONG glyph, which is far harder to notice than none at all.
        local path, coords = I():Get("definitely_not_a_glyph")
        expect(path).eq(nil)
        expect(coords).eq(nil)
        expect(I():Get(nil)).eq(nil)
    end)

    -- A caller that mutated the stored table would silently re-point the glyph for every OTHER
    -- consumer, with nothing to say so. Same rule as Container:GetPadding and DataBar:List.
    it("hands out a COPY of the coords, not the live table", function()
        local _, a = I():Get("sort")
        a[1] = 0.99
        local _, b = I():Get("sort")
        expect(b[1]).as("the registry is unchanged").neq(0.99)
    end)

    it("reports what it has", function()
        expect(I():Has("sort")).truthy()
        expect(I():Has("account")).truthy()
        expect(I():Has("nope")).falsy()
        expect(I():Has(nil)).falsy()
    end)

    it("lists every glyph", function()
        local names = {}
        for _, n in ipairs(I():List()) do names[n] = true end
        expect(names.sort).truthy()
        expect(names.account).truthy()
    end)

    -- The coords must actually differ, or two buttons draw the same picture. This is the assertion
    -- that catches a copy-paste in the table the generator prints.
    --
    -- EVERY PAIR, not just one. It used to compare sort against account alone, which is what its own
    -- comment already claimed to be doing -- and a mutation pointing a third glyph at sort's cell
    -- survived it, because nothing looked at the third glyph. A pairwise walk cannot be outgrown by
    -- the sheet: the generator's GLYPHS list is append-only and each new cell is checked against
    -- every earlier one for free.
    it("gives each glyph a distinct region of the sheet", function()
        local names = I():List()
        for i = 1, #names do
            for j = i + 1, #names do
                local _, a = I():Get(names[i])
                local _, b = I():Get(names[j])
                local same = a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
                expect(same)
                    .as(names[i] .. " and " .. names[j] .. " point at one cell").falsy()
            end
        end
        expect(#names).as("a one-glyph sheet would pass the walk vacuously").gte(2)
    end)

    it("keeps every coord a 0..1 fraction", function()
        for _, name in ipairs(I():List()) do
            local _, c = I():Get(name)
            for i = 1, 4 do
                expect(c[i] >= 0 and c[i] <= 1).as(name .. " coord " .. i .. " in range").truthy()
            end
            expect(c[2] > c[1]).as(name .. " has width").truthy()
            expect(c[4] > c[3]).as(name .. " has height").truthy()
        end
    end)
end)
