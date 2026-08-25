-- Components/SegmentedControl.lua: two or three mutually exclusive segments in one bordered strip.
--
-- The properties worth asserting are the ones that make it a CONTROL rather than a row of buttons: one
-- outer border with dividers only BETWEEN segments, the selected segment washed with the accent, and a
-- setter that stays silent so external state syncing cannot loop back on itself.
local H = require("harness.init")

describe("Components.SegmentedControl", function()
    local host

    local OPTS = {
        { value = "bags", label = "Bags" },
        { value = "bank", label = "Bank" },
    }

    before_each(function()
        H.setup()
        host = H.parent(300, 60)
    end)

    local function seg(props)
        local p = { options = OPTS }
        for k, v in pairs(props or {}) do p[k] = v end
        return H.mount(H.C.SegmentedControl(p, host))
    end

    describe("construction", function()
        it("selects the first option when none is given", function()
            -- A control with nothing selected has no state to show, and a strip of two muted segments
            -- reads as disabled rather than as awaiting a choice.
            expect(seg():GetValue()).eq("bags")
        end)

        it("honours an explicit value", function()
            expect(seg({ value = "bank" }):GetValue()).eq("bank")
        end)

        it("builds one segment per option", function()
            local s = seg()
            expect(#s._segs).eq(2)
            expect(s._segs[1].text:GetText()).eq("Bags")
            expect(s._segs[2].text:GetText()).eq("Bank")
        end)

        it("takes its height from the control token, floored by the font", function()
            expect(seg():GetHeight())
                .near(H.SuuUI.Theme:GetControlHeight("sizeControlSm", "sm"), 1)
        end)
    end)

    describe("geometry", function()
        it("is as wide as its labels plus padding and the dividers", function()
            local s = seg()
            local size = H.SuuUI.Theme:GetFontSize("sm")
            local padX = H.token("spaceSm")
            local line = H.token("borderWidth")
            local want = H.textBox("Bags", size) + padX * 2
                       + H.textBox("Bank", size) + padX * 2
                       + line          -- one divider, between the two
                       + line * 2      -- the strip's own border
            expect(s:GetWidth()).near(want, 2)
        end)

        it("keeps every segment inside the strip", function()
            local s = seg()
            for _, part in ipairs(s._segs) do H.expectInside(part.f, s:GetFrame()) end
        end)

        it("does not overlap its segments", function()
            local s = seg()
            H.expectNoOverlap({ s._segs[1].f, s._segs[2].f })
        end)

        it("draws no divider after the LAST segment", function()
            -- The strip owns the outer border, so a trailing divider would draw a second line on top of
            -- it -- visible as a double edge at the right end.
            local s = seg()
            expect(s._segs[1].divider:IsShown()).as("between the two").truthy()
            expect(s._segs[2].divider:IsShown()).as("not after the last").falsy()
        end)

        it("does not clip its labels", function()
            local s = seg()
            for _, part in ipairs(s._segs) do
                H.expectTextNotClipped(part.text:GetFrame())
            end
        end)
    end)

    describe("selection", function()
        it("washes the selected segment with the accent and mutes the rest", function()
            local s = seg({ value = "bags" })
            -- Asserted on the PAINT rather than on the stored value: a handle that remembers a
            -- selection it never drew is the failure this catches.
            expect(s._segs[1].text._color).eq("accent")
            expect(s._segs[2].text._color).eq("muted")
            -- AND ON THE BACKGROUND, which the text colour alone does not cover: dropping the wash
            -- entirely survived a mutation run against the colour assertions above, because two accent
            -- letters on nothing still read as "selected" to a test and not to an eye.
            H.expectTokenColor({ s._segs[1].f:GetBackdropColor() }, "colorAccentSubtle")
        end)

        it("repaints when the value changes", function()
            local s = seg({ value = "bags" })
            s:SetValue("bank")
            expect(s._segs[1].text._color).eq("muted")
            expect(s._segs[2].text._color).eq("accent")
        end)

        it("emits VALUE_CHANGED on a click, with both values", function()
            local s = seg({ value = "bags" })
            local spy = H.signalSpy(s, H.S.SIGNALS.VALUE_CHANGED)
            H.click(s._segs[2].f)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("bank")
            expect(spy:arg(2)).as("the old value comes with it").eq("bags")
            expect(s:GetValue()).eq("bank")
        end)

        it("is SILENT on SetValue", function()
            -- The setter contract: only user interaction emits, which is what keeps external state
            -- syncing from looping back into whatever wrote the value.
            local s = seg({ value = "bags" })
            local spy = H.signalSpy(s, H.S.SIGNALS.VALUE_CHANGED)
            s:SetValue("bank")
            expect(spy.count).eq(0)
        end)

        it("emits nothing when the selected segment is clicked again", function()
            local s = seg({ value = "bags" })
            local spy = H.signalSpy(s, H.S.SIGNALS.VALUE_CHANGED)
            H.click(s._segs[1].f)
            expect(spy.count).as("nothing changed, so nothing is announced").eq(0)
        end)
    end)

    describe("SetOptions", function()
        it("rebuilds the segments", function()
            local s = seg()
            s:SetOptions({ { value = "a", label = "A" }, { value = "b", label = "B" },
                           { value = "c", label = "C" } })
            expect(#s._segs).eq(3)
        end)

        it("keeps a value that is still on offer", function()
            local s = seg({ value = "bank" })
            s:SetOptions(OPTS)
            expect(s:GetValue()).as("a rebuild of the same choice must not move it").eq("bank")
        end)

        it("falls back to the first option when the value is gone", function()
            local s = seg({ value = "bank" })
            s:SetOptions({ { value = "x", label = "X" } })
            expect(s:GetValue()).eq("x")
        end)
    end)

    describe("disabled", function()
        it("fades to the disabled opacity", function()
            local s = seg()
            s:SetEnabled(false)
            expect(s:GetFrame():GetAlpha()).near(H.token("opacityDisabled"), 0.001)
        end)

        it("refuses a click", function()
            local s = seg({ value = "bags" })
            s:SetEnabled(false)
            local spy = H.signalSpy(s, H.S.SIGNALS.VALUE_CHANGED)
            -- BOTH HALVES, per the spec checklist. H.click proves the CLIENT stops routing input, and
            -- forceClick proves the component's own guard holds -- without the second, deleting that
            -- guard survives, because the dropped mouse hides it.
            H.click(s._segs[2].f)
            expect(spy.count).as("the client refused it").eq(0)
            H.forceClick(s._segs[2].f)
            expect(spy.count).as("and the handler refuses it too").eq(0)
            expect(s:GetValue()).eq("bags")
        end)

        it("stays faded across a theme change", function()
            -- opacityDisabled is user-editable, so ApplyTheme has to re-assert the fade or a token edit
            -- never reaches a control that is already sitting disabled.
            local s = seg()
            s:SetEnabled(false)
            s:ApplyTheme()
            expect(s:GetFrame():GetAlpha()).near(H.token("opacityDisabled"), 0.001)
        end)
    end)

    describe("theme reaction", function()
        it("re-fits when the font token grows", function()
            local s = seg()
            local before = s:GetWidth()
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeSm", H.token("fontSizeSm") + 8)
            H.T:SetActive("Big")
            expect(s:GetWidth()).as("wider labels need a wider strip").gt(before)
        end)

        it("keeps the selection painted after a restyle", function()
            local s = seg({ value = "bank" })
            s:ApplyTheme()
            expect(s._segs[2].text._color).eq("accent")
        end)
    end)

    describe("teardown", function()
        it("hides and disconnects", function()
            local s = seg()
            local spy = H.signalSpy(s, H.S.SIGNALS.VALUE_CHANGED)
            s:Destroy()
            expect(s:GetFrame():IsShown()).falsy()
            expect(spy.count).eq(0)
        end)
    end)
end)
