local H = require("harness")

local function child(parent, w, h)
    local f = H.env.CreateFrame("Frame", nil, parent)
    f:SetSize(w or 50, h or 20)
    return f
end

describe("FlowLayout", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(200, 300)
    end)

    local function container(props)
        props.parent = props.parent or host
        return H.Layout:CreateContainer(props)
    end

    describe("vertical direction", function()
        it("stacks children top to bottom separated by the gap", function()
            local c = container({ layout = "flow", dir = "vertical", gap = 6, h = 300 })
            local a, b, d = child(host), child(host), child(host)
            c:Add(a, { width = "fill", height = 20 })
            c:Add(b, { width = "fill", height = 30 })
            c:Add(d, { width = "fill", height = 20 })
            H.expectStackedVertically({ a, b, d }, 6)
        end)

        it("applies padding on all four sides", function()
            local c = container({
                layout = "flow", dir = "vertical", gap = 0, h = 300,
                padding = { top = 7, right = 5, bottom = 9, left = 3 },
            })
            local a = child(host)
            c:Add(a, { width = "fill", height = 20 })
            H.expectOffset(a, c, 3, 7)
            -- fill respects both horizontal insets
            H.expectSize(a, 200 - 3 - 5, 20)
        end)

        it("gives width='fill' the full inner width regardless of natural size", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300,
                                  padding = { left = 10, right = 10 } })
            local a = child(host, 12, 20)
            c:Add(a, { width = "fill", height = 20 })
            H.expectSize(a, 180, 20)
        end)

        it("keeps a fixed numeric width", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local a = child(host, 999, 20)
            c:Add(a, { width = 40, height = 20 })
            H.expectSize(a, 40, 20)
        end)

        it("uses the child's natural width when width is omitted", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local a = child(host, 37, 20)
            c:Add(a, { height = 20 })
            H.expectSize(a, 37, 20)
        end)

        it("splits leftover height between height='fill' children", function()
            local c = container({ layout = "flow", dir = "vertical", gap = 10, h = 200 })
            local fixed = child(host)
            local f1, f2 = child(host), child(host)
            c:Add(fixed, { width = "fill", height = 40 })
            c:Add(f1, { width = "fill", height = "fill" })
            c:Add(f2, { width = "fill", height = "fill" })
            -- 200 total - 40 fixed - 2 gaps of 10 = 140, halved
            H.expectSize(f1, nil, 70)
            H.expectSize(f2, nil, 70)
        end)

        it("clamps fill height to zero rather than negative when space is short", function()
            local c = container({ layout = "flow", dir = "vertical", gap = 0, h = 30 })
            local fixed = child(host)
            local f1 = child(host)
            c:Add(fixed, { width = "fill", height = 100 })
            c:Add(f1, { width = "fill", height = "fill" })
            expect(f1:GetHeight()).gte(0)
            expect(f1:GetHeight()).eq(0)
        end)

        it("aligns a narrow child to the cross axis start by default", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local a = child(host, 40, 20)
            c:Add(a, { height = 20 })
            H.expectOffset(a, c, 0, 0)
        end)

        it("centres a narrow child with align='center'", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local a = child(host, 40, 20)
            c:Add(a, { height = 20, align = "center" })
            H.expectOffset(a, c, (200 - 40) / 2, 0)
        end)

        it("pushes a narrow child to the right with align='end'", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local a = child(host, 40, 20)
            c:Add(a, { height = 20, align = "end" })
            H.expectOffset(a, c, 200 - 40, 0)
        end)

        it("treats align='stretch' as a full-width child", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300,
                                  padding = { left = 8, right = 8 } })
            local a = child(host, 10, 20)
            c:Add(a, { height = 20, align = "stretch" })
            H.expectSize(a, 200 - 16, 20)
        end)

        it("honours a container-level align for every child", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300, align = "center" })
            local a, b = child(host, 40, 20), child(host, 80, 20)
            c:Add(a, { height = 20 })
            c:Add(b, { height = 20 })
            H.expectCenteredH(a, c)
            H.expectCenteredH(b, c)
        end)

        it("lets a child align override the container align", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300, align = "center" })
            local a = child(host, 40, 20)
            c:Add(a, { height = 20, align = "start" })
            H.expectOffset(a, c, 0, nil)
        end)
    end)

    describe("horizontal direction", function()
        it("lays children left to right separated by the gap", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 8, h = 40 })
            local a, b = child(host, 30, 20), child(host, 50, 20)
            c:Add(a, { width = 30, height = 20 })
            c:Add(b, { width = 50, height = 20 })
            H.expectRowHorizontally({ a, b }, 8)
        end)

        it("gives width='fill' the leftover main-axis space", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 10, h = 40 })
            local label = child(host)
            local ctrl  = child(host)
            c:Add(label, { width = "fill", height = 20 })
            c:Add(ctrl, { width = 36, height = 20 })
            -- 200 - 36 fixed - 10 gap
            H.expectSize(label, 154, 20)
        end)

        it("puts the fixed control at the far edge in a label-left row", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 8, h = 28,
                                  padding = { left = 4, right = 4 } })
            local label = child(host)
            local ctrl  = child(host)
            c:Add(label, { width = "fill" })
            c:Add(ctrl, { width = 36, height = 18 })
            local cbox, ctrlBox = H.box(c), H.box(ctrl)
            expect(ctrlBox.right).as("control lands on the right inset").eq(cbox.right - 4)
        end)

        it("splits leftover width evenly between two fill children", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 20, h = 40 })
            local a, b = child(host), child(host)
            c:Add(a, { width = "fill", height = 10 })
            c:Add(b, { width = "fill", height = 10 })
            H.expectSize(a, 90, nil)
            H.expectSize(b, 90, nil)
        end)

        it("stretches children to the container height with height='fill'", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 60 })
            local a = child(host, 20, 5)
            c:Add(a, { width = 20, height = "fill" })
            H.expectSize(a, 20, 60)
        end)

        it("centres a short child vertically with align='center'", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 60, align = "center" })
            local a = child(host, 20, 20)
            c:Add(a, { width = 20, height = 20 })
            H.expectCenteredV(a, c)
        end)

        it("aligns a short child to the bottom with align='end'", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 60 })
            local a = child(host, 20, 20)
            c:Add(a, { width = 20, height = 20, align = "end" })
            H.expectOffset(a, c, 0, 40)
        end)
    end)

    describe("width='auto' (content hug)", function()
        local function label(parent, text, size)
            local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", size or 12, "")
            fs:SetWordWrap(false)
            fs:SetText(text)
            return fs
        end

        it("sizes a font string to its own text rather than the container", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 20 })
            local fs = label(host, "Testchar")
            c:Add(fs, { width = "auto", height = 14 })
            H.expectSize(fs, H.textBox("Testchar", 12), 14)
        end)

        it("packs a second auto child directly beside the first", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 20 })
            local name  = label(host, "Testchar")
            local level = label(host, "42")
            c:Add(name,  { width = "auto", height = 14 })
            c:Add(level, { width = "auto", height = 14 })
            local nameBox, levelBox = H.box(name), H.box(level)
            expect(levelBox.left).as("level sits one gap right of the name").eq(nameBox.right + 4)
        end)

        it("re-measures after the text changes, instead of keeping the pinned width", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 20 })
            -- Laid out while empty: the naive reading pins width 0 forever.
            local fs = label(host, "")
            c:Add(fs, { width = "auto", height = 14 })
            expect(fs:GetWidth()).eq(0)

            fs:SetText("Testchar")
            c:Layout()
            H.expectSize(fs, H.textBox("Testchar", 12), 14)
        end)

        it("collapses to zero width when the text is cleared", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 20 })
            local fs = label(host, "42")
            c:Add(fs, { width = "auto", height = 14 })
            expect(fs:GetWidth()).gt(0)

            fs:SetText("")
            c:Layout()
            expect(fs:GetWidth()).eq(0)
        end)

        it("leaves the fill child the space the auto child did not take", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 6, h = 20 })
            local fs   = label(host, "Testchar")
            local rest = child(host)
            c:Add(fs,   { width = "auto", height = 14 })
            c:Add(rest, { width = "fill", height = 14 })
            H.expectSize(rest, 200 - H.textBox("Testchar", 12) - 6, 14)
        end)

        it("falls back to a plain frame's own width", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 20 })
            local f = child(host, 37, 14)
            c:Add(f, { width = "auto", height = 14 })
            H.expectSize(f, 37, 14)
        end)

        it("reports the measured width through GetContentSize", function()
            local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 20 })
            local name  = label(host, "Testchar")
            local level = label(host, "42")
            c:Add(name,  { width = "auto", height = 14 })
            c:Add(level, { width = "auto", height = 14 })
            local w = c:GetContentSize()
            expect(w).eq(H.textBox("Testchar", 12) + 4 + H.textBox("42", 12))
        end)
    end)

    describe("font string children", function()
        it("measures text height after assigning the width, so text re-flows", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("one two three four five six seven eight nine ten eleven twelve")
            c:Add(fs, { width = "fill" })
            local wideHeight = fs:GetHeight()

            c:SetWidth(60)
            expect(fs:GetHeight()).as("narrower container wraps to more lines").gt(wideHeight)
        end)

        it("re-measures when the font size grows", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 11, "")
            fs:SetText("hello world")
            c:Add(fs, { width = "fill" })
            local small = fs:GetHeight()
            fs:SetFont("Fonts/FRIZQT__.TTF", 22, "")
            c:Layout()
            expect(fs:GetHeight()).gt(small)
        end)

        it("does not shrink a text child on repeated layout passes", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("a stable label")
            c:Add(fs, { width = "fill" })
            local first = fs:GetHeight()
            for _ = 1, 5 do c:Layout() end
            expect(fs:GetHeight()).eq(first)
        end)

        -- The live client reports nothing for a font string it has not laid out yet, and
        -- the settings page is built while its window has never been shown. The harness
        -- always answers from its font model, so the only way to state this invariant is
        -- to make the client report nothing on purpose. Falling through to the region's
        -- own rect is what shipped every settings-row label at zero height, drawing
        -- nothing at all while every assertion about it passed.
        local function muteClientHeight(fs)
            fs.GetStringHeight = function() return 0 end
        end

        it("measures a label the client reports no height for, instead of pinning zero", function()
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
            fs:SetText("Show Spell Name")
            muteClientHeight(fs)

            c:Add(fs, { width = "fill" })
            expect(fs:GetHeight()).as("a label with no height never draws").gt(0)
            expect(fs:GetHeight()).eq(H.lineHeight(12))
        end)

        it("still measures it in a horizontal row, where settings labels live", function()
            local c = container({ layout = "flow", dir = "horizontal", h = 40, align = "center" })
            local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetFont("Fonts/FRIZQT__.TTF", 13, "")
            fs:SetText("Show Name")
            muteClientHeight(fs)
            local ctrl = child(host, 36, 18)

            c:Add(fs, { width = "fill" })
            c:Add(ctrl, { width = 36, height = 18 })
            expect(fs:GetHeight()).eq(H.lineHeight(13))
            H.expectTextNotClipped(fs)
        end)

        it("leaves a non-text child on its own rect", function()
            -- The fallback is for font strings only: a plain frame's rect IS its size.
            local c = container({ layout = "flow", dir = "vertical", h = 300 })
            local f = child(host, 50, 27)
            c:Add(f, { width = "fill" })
            expect(f:GetHeight()).eq(27)
        end)
    end)

    describe("edge cases", function()
        it("does nothing with no children", function()
            local c = container({ layout = "flow", dir = "vertical", gap = 8 })
            expect(function() c:Layout() end).notThrows()
            expect(#c:GetChildren()).eq(0)
        end)

        it("places a single child with no gap contribution", function()
            local c = container({ layout = "flow", dir = "vertical", gap = 50, h = 100 })
            local a = child(host)
            c:Add(a, { width = "fill", height = 20 })
            H.expectOffset(a, c, 0, 0)
        end)

        it("survives a zero-width container without negative sizes", function()
            local c = container({ layout = "flow", dir = "vertical", w = 0, h = 100 })
            local a = child(host)
            c:Add(a, { width = "fill", height = 10 })
            expect(a:GetWidth()).gte(0)
        end)

        it("keeps children inside the padded box", function()
            local c = container({
                layout = "flow", dir = "vertical", gap = 4, h = 300,
                padding = { top = 10, right = 10, bottom = 10, left = 10 },
            })
            local items = {}
            for i = 1, 4 do
                items[i] = child(host)
                c:Add(items[i], { width = "fill", height = 20 })
            end
            for _, item in ipairs(items) do H.expectInside(item, c) end
            H.expectNoOverlap(items)
        end)
    end)
end)

describe("FlowLayout wrapping (horizontal)", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(200, 300)
    end)

    local function child(parent, w, h)
        local f = H.env.CreateFrame("Frame", nil, parent)
        f:SetSize(w or 50, h or 20)
        return f
    end

    local function container(props)
        props.parent = props.parent or host
        return H.Layout:CreateContainer(props)
    end

    it("places all children on one line when they fit", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 40, wrap = true })
        local a = child(host, 40, 20)
        local b = child(host, 60, 20)
        local d = child(host, 50, 20)
        c:Add(a, { width = 40, height = 20 })
        c:Add(b, { width = 60, height = 20 })
        c:Add(d, { width = 50, height = 20 })
        -- 40 + 4 + 60 + 4 + 50 = 158 <= 200 content width: no wrap
        H.expectRowHorizontally({ a, b, d }, 4)
    end)

    it("does NOT wrap when a child lands exactly on the content width boundary", function()
        -- Break rule: cursor + childWidth <= contentWidth stays on the line
        local c = container({ layout = "flow", dir = "horizontal", gap = 0, h = 40, wrap = true })
        local a = child(host, 100, 20)
        local b = child(host, 100, 20)
        c:Add(a, { width = 100, height = 20 })
        c:Add(b, { width = 100, height = 20 })
        -- 100 + 100 = 200 exactly = content width -> stays on same line
        local aBox, bBox = H.box(a), H.box(b)
        expect(aBox.top).as("both on same line").eq(bBox.top)
        expect(bBox.left).as("b directly after a").eq(aBox.right)
    end)

    it("wraps a child that overflows by one pixel", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 0, h = 80, wrap = true })
        local a = child(host, 101, 20)
        local b = child(host, 100, 20)
        c:Add(a, { width = 101, height = 20 })
        c:Add(b, { width = 100, height = 20 })
        -- 101 + 100 = 201 > 200 -> b wraps to line 2
        local aBox, bBox = H.box(a), H.box(b)
        expect(bBox.top).as("b on a new line below a").eq(aBox.bottom)
    end)

    it("arranges three lines with distinct line heights", function()
        -- container width 200, gap 4
        -- Line 1: 80+4+80 = 164 (fits), heights 20 and 30 -> lineH = 30
        -- Line 2: 80+4+80 = 164 (fits), heights 25 and 15 -> lineH = 25
        -- Line 3: 80, height 10 -> lineH = 10
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true })
        local a = child(host, 80, 20)
        local b = child(host, 80, 30)
        local d = child(host, 80, 25)
        local e = child(host, 80, 15)
        local f = child(host, 80, 10)
        c:Add(a, { width = 80, height = 20 })
        c:Add(b, { width = 80, height = 30 })
        c:Add(d, { width = 80, height = 25 })
        c:Add(e, { width = 80, height = 15 })
        c:Add(f, { width = 80, height = 10 })
        -- Line breaks: 80+4+80=164<=200, 164+4+80=248>200 -> d wraps
        -- d+e: 80+4+80=164<=200, 164+4+80=248>200 -> f wraps
        local aBox = H.box(a)
        local bBox = H.box(b)
        local dBox = H.box(d)
        local eBox = H.box(e)
        local fBox = H.box(f)
        -- Line 1 starts at top
        expect(aBox.top).eq(bBox.top)
        -- Line 1 height = 30 (tallest)
        expect(dBox.top).as("line 2 starts after line 1 height + lineGap(=gap=4)").eq(aBox.top + 30 + 4)
        -- Line 2 height = 25
        expect(fBox.top).as("line 3 starts after line 2").eq(dBox.top + 25 + 4)
    end)

    it("resolves per-line cross-axis align against that line's height", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true, align = "center" })
        -- Line 1: a(80x20) b(80x40) -> lineH = 40, a centred at +10
        -- Line 2: d(80x10) -> lineH = 10, d centred at +0
        local a = child(host, 80, 20)
        local b = child(host, 80, 40)
        local d = child(host, 80, 10)
        c:Add(a, { width = 80, height = 20 })
        c:Add(b, { width = 80, height = 40 })
        c:Add(d, { width = 80, height = 10 })
        -- 80+4+80=164<=200, 164+4+80=248>200 -> d wraps
        local aBox, bBox, dBox = H.box(a), H.box(b), H.box(d)
        -- a centred in line of height 40: offset (40-20)/2 = 10
        expect(aBox.top - bBox.top).as("a offset from line top").eq(10)
        -- d is alone on its line, lineH = 10, so centred = 0 offset
        expect(dBox.top).eq(bBox.top + 40 + 4) -- line2 starts here
    end)

    it("gives a child wider than the container its own line", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true })
        local a = child(host, 50, 20)
        local big = child(host, 300, 25)
        local b = child(host, 50, 15)
        c:Add(a, { width = 50, height = 20 })
        c:Add(big, { width = 300, height = 25 })
        c:Add(b, { width = 50, height = 15 })
        -- a fits alone, big overflows on same line -> wraps to line 2
        -- big is alone (wider than container), b wraps to line 3
        local aBox, bigBox, bBox = H.box(a), H.box(big), H.box(b)
        expect(bigBox.top).as("big starts on line 2").eq(aBox.top + 20 + 4)
        expect(bBox.top).as("b starts on line 3").eq(bigBox.top + 25 + 4)
    end)

    it("uses lineGap between lines when distinct from gap", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, lineGap = 12, h = 200, wrap = true })
        -- Each child is 120 wide: 120+4+120=244>200 -> each on own line
        local a = child(host, 120, 20)
        local b = child(host, 120, 30)
        local d = child(host, 120, 15)
        c:Add(a, { width = 120, height = 20 })
        c:Add(b, { width = 120, height = 30 })
        c:Add(d, { width = 120, height = 15 })
        local aBox, bBox, dBox = H.box(a), H.box(b), H.box(d)
        expect(bBox.top).as("lineGap between line 1 and 2").eq(aBox.top + 20 + 12)
        expect(dBox.top).as("lineGap between line 2 and 3").eq(bBox.top + 30 + 12)
    end)

    it("stacks lines bottom-up with lineOrder='reverse'", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 100, wrap = true, lineOrder = "reverse" })
        -- Each child 120 wide -> each wraps to own line. Container height 100.
        local a = child(host, 120, 20)
        local b = child(host, 120, 15)
        local d = child(host, 120, 10)
        c:Add(a, { width = 120, height = 20 })
        c:Add(b, { width = 120, height = 15 })
        c:Add(d, { width = 120, height = 10 })
        local aBox, bBox, dBox = H.box(a), H.box(b), H.box(d)
        -- Reversed: line 1 at bottom, line 2 above, line 3 topmost
        -- Container is 100 tall. Lines: 20+15+10=45, lineGaps=4*2=8. Total=53.
        -- Line 1 (a) bottom = container bottom = top + 100
        expect(aBox.bottom).as("line 1 pinned to container bottom").eq(H.box(c).bottom)
        -- Line 2 (b) above line 1 with lineGap
        expect(bBox.bottom).as("line 2 above line 1").eq(aBox.top - 4)
        -- Line 3 (d) above line 2 with lineGap
        expect(dBox.bottom).as("line 3 above line 2").eq(bBox.top - 4)
    end)

    it("skips a hidden child and closes its gap and slot on the line", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 40, wrap = true })
        local a = child(host, 80, 20)
        local b = child(host, 80, 20)
        local d = child(host, 80, 20)
        c:Add(a, { width = 80, height = 20 })
        c:Add(b, { width = 80, height = 20 })
        c:Add(d, { width = 80, height = 20 })
        -- 80+4+80=164<=200, 164+4+80=248>200 -> normally d wraps
        -- Hide b: 80+4+80=164<=200 -> all on one line
        b:Hide()
        c:Layout()
        local aBox, dBox = H.box(a), H.box(d)
        expect(aBox.top).as("a and d on same line").eq(dBox.top)
        expect(dBox.left).as("d directly after a with gap").eq(aBox.right + 4)
    end)

    it("reports correct content height from a hugging container", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, wrap = true })
        -- No h -> hugging. Width 200.
        -- Each 120 wide -> one per line. Heights 20, 15, 10.
        local a = child(host, 120, 20)
        local b = child(host, 120, 15)
        local d = child(host, 120, 10)
        c:Add(a, { width = 120, height = 20 })
        c:Add(b, { width = 120, height = 15 })
        c:Add(d, { width = 120, height = 10 })
        -- Content height = 20 + 4 + 15 + 4 + 10 = 53
        local _, contentH = c:GetContentSize()
        expect(contentH).as("hugging height = sum of lines + lineGaps").eq(53)
        expect(c:GetHeight()).as("container hugs to content height").eq(53)
    end)

    it("re-flows to a different line count when the container is resized", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true })
        local items = {}
        for i = 1, 5 do
            items[i] = child(host, 50, 20)
            c:Add(items[i], { width = 50, height = 20 })
        end
        -- At width 200: 50+4+50+4+50+4+50 = 216 > 200 -> wraps after 3rd (50+4+50+4+50=162<=200, +4+50=216>200)
        -- Actually: 50+4+50=104, 104+4+50=158, 158+4+50=216>200 so 4th wraps
        -- Let's check: 3 on line 1 (50+4+50+4+50=162<=200), 4th starts cursor at 162+4+50=216>200 -> 4th wraps
        -- Line1: items 1-3, Line2: items 4-5
        local box3, box4 = H.box(items[3]), H.box(items[4])
        expect(box4.top).as("item 4 on line 2").gt(box3.top)

        -- Widen to 300: all 5 fit (50*5 + 4*4 = 266 <= 300)
        c:SetWidth(300)
        local box1, box5 = H.box(items[1]), H.box(items[5])
        expect(box1.top).as("all on one line after resize").eq(box5.top)
    end)

    it("treats width='fill' as natural width in a wrapping row", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 0, h = 40, wrap = true })
        local a = child(host, 80, 20)
        local b = child(host, 60, 20)
        c:Add(a, { width = "fill", height = 20 })
        c:Add(b, { width = 60, height = 20 })
        -- fill -> natural width 80 in wrap mode
        H.expectSize(a, 80, 20)
        -- 80 + 60 = 140 <= 200 -> same line
        local aBox, bBox = H.box(a), H.box(b)
        expect(aBox.top).eq(bBox.top)
    end)

    it("treats height='fill' as natural height in a wrapping row", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 0, h = 100, wrap = true })
        local a = child(host, 80, 25)
        c:Add(a, { width = 80, height = "fill" })
        -- fill height in wrap -> natural height
        H.expectSize(a, 80, 25)
    end)

    it("ignores wrap on a vertical container", function()
        local c = container({ layout = "flow", dir = "vertical", gap = 4, h = 200, wrap = true })
        local a = child(host, 50, 80)
        local b = child(host, 50, 80)
        local d = child(host, 50, 80)
        c:Add(a, { width = "fill", height = 80 })
        c:Add(b, { width = "fill", height = 80 })
        c:Add(d, { width = "fill", height = 80 })
        -- Vertical ignores wrap, stacks normally
        H.expectStackedVertically({ a, b, d }, 4)
    end)

    it("uses gap within a line between children", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 10, lineGap = 20, h = 100, wrap = true })
        local a = child(host, 60, 20)
        local b = child(host, 60, 20)
        -- 60+10+60=130<=200 -> same line
        c:Add(a, { width = 60, height = 20 })
        c:Add(b, { width = 60, height = 20 })
        local aBox, bBox = H.box(a), H.box(b)
        expect(bBox.left - aBox.right).as("gap=10 between children on a line").eq(10)
    end)

    it("respects padding in a wrapping container", function()
        local c = container({
            layout = "flow", dir = "horizontal", gap = 0, h = 100, wrap = true,
            padding = { top = 5, right = 10, bottom = 7, left = 3 },
        })
        -- Content width = 200 - 3 - 10 = 187
        local a = child(host, 100, 20)
        local b = child(host, 100, 20)
        c:Add(a, { width = 100, height = 20 })
        c:Add(b, { width = 100, height = 20 })
        -- 100+100=200>187 -> b wraps
        local aBox, bBox, cBox = H.box(a), H.box(b), H.box(c)
        expect(aBox.left - cBox.left).as("left padding").eq(3)
        expect(aBox.top - cBox.top).as("top padding").eq(5)
        expect(bBox.top).as("b on line 2").eq(aBox.top + 20)
        expect(bBox.left - cBox.left).as("line 2 also starts at left padding").eq(3)
    end)

    it("align='end' pushes child to bottom of its line", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true })
        local a = child(host, 80, 15)
        local b = child(host, 80, 30)
        c:Add(a, { width = 80, height = 15, align = "end" })
        c:Add(b, { width = 80, height = 30 })
        -- lineH = 30, a aligned to end = offset 30-15=15
        local aBox, bBox = H.box(a), H.box(b)
        expect(aBox.top - bBox.top).as("a offset by 15 from line top").eq(15)
        expect(aBox.bottom).as("a bottom equals b bottom (line bottom)").eq(bBox.bottom)
    end)

    it("align='stretch' fills child to line height", function()
        local c = container({ layout = "flow", dir = "horizontal", gap = 4, h = 200, wrap = true })
        local a = child(host, 80, 10)
        local b = child(host, 80, 30)
        c:Add(a, { width = 80, align = "stretch" })
        c:Add(b, { width = 80, height = 30 })
        -- lineH = 30, stretch -> a height = 30
        H.expectSize(a, 80, 30)
    end)
end)
