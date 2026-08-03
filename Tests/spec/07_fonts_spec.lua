local H = require("harness")

describe("Core.Fonts", function()
    local SuuUI, F

    before_each(function()
        SuuUI = H.setup()
        F = SuuUI.Fonts
    end)

    local function names()
        local out = {}
        for _, entry in ipairs(F:List()) do out[entry.name] = entry.path end
        return out
    end

    describe("discovery", function()
        it("lists the client's own faces under their shared-media names", function()
            local found = names()
            expect(found["Friz Quadrata TT"]).eq("Fonts/FRIZQT__.TTF")
            expect(found["Arial Narrow"]).eq("Fonts/ARIALN.TTF")
            expect(found["Morpheus"]).eq("Fonts/MORPHEUS.TTF")
            expect(found["Skurri"]).eq("Fonts/skurri.TTF")
        end)

        it("harvests a face that only a font object reports", function()
            -- The path comes off the font object, not from GetFonts, which returns
            -- object names. A locale client ships faces no curated list can know.
            H.addFont("LocaleBodyFont", "Fonts/2002.TTF")
            F:Refresh()
            expect(names()["2002"]).eq("Fonts/2002.TTF")
        end)

        it("keeps one entry per face across slash style and case", function()
            F:Register("Duplicate Friz", "Fonts\\FRIZQT__.ttf")
            local count = 0
            for _, entry in ipairs(F:List()) do
                if H.font.normalise(entry.path) == "fonts/frizqt__.ttf" then
                    count = count + 1
                end
            end
            expect(count).as("same file, one entry").eq(1)
        end)

        it("rejects a path the client cannot load", function()
            expect(F:Register("Ghost", "Interface/AddOns/Nope/missing.ttf")).falsy()
            expect(F:Has("Ghost")).falsy()
        end)

        it("rejects an empty name or path", function()
            expect(F:Register("", "Fonts/2002.TTF")).falsy()
            expect(F:Register("Nameless", "")).falsy()
            expect(F:Register(nil, nil)).falsy()
        end)

        it("keeps the first name registered for a face", function()
            H.font.addFace("Fonts/custom.ttf")
            expect(F:Register("First Name", "Fonts/custom.ttf")).truthy()
            expect(F:Register("Second Name", "Fonts/custom.ttf")).falsy()
            expect(F:Name("Fonts/custom.ttf")).eq("First Name")
        end)

        it("sorts the list by name, case-insensitively", function()
            H.font.addFace("Fonts/aaa.ttf")
            F:Register("aardvark", "Fonts/aaa.ttf")
            local list = F:List()
            for i = 2, #list do
                expect(list[i - 1].name:lower() <= list[i].name:lower())
                    .as(list[i - 1].name .. " before " .. list[i].name).truthy()
            end
        end)

        it("reads LibSharedMedia-3.0 when the player has it", function()
            H.font.addFace("Interface/AddOns/SharedMedia/fonts/PTSans.ttf")
            H.env.LibStub = function(name, silent)
                if name ~= "LibSharedMedia-3.0" then return nil end
                return {
                    HashTable = function()
                        return { ["PT Sans Narrow"] =
                            "Interface/AddOns/SharedMedia/fonts/PTSans.ttf" }
                    end,
                }
            end
            F:Refresh()
            expect(names()["PT Sans Narrow"])
                .eq("Interface/AddOns/SharedMedia/fonts/PTSans.ttf")
        end)

        it("works with no LibSharedMedia and no GetFonts", function()
            H.env.LibStub  = nil
            H.env.GetFonts = nil
            F:Refresh()
            expect(names()["Friz Quadrata TT"]).as("curated faces still there")
                .eq("Fonts/FRIZQT__.TTF")
        end)

        it("survives a GetFonts that throws", function()
            H.env.GetFonts = function() error("client blew up") end
            expect(function() F:Refresh() end).notThrows()
            expect(F:Has("Friz Quadrata TT")).truthy()
        end)
    end)

    describe("resolution", function()
        it("resolves a name to its path", function()
            expect(F:Path("Arial Narrow")).eq("Fonts/ARIALN.TTF")
        end)

        it("passes a known path straight through", function()
            expect(F:Path("Fonts/ARIALN.TTF")).eq("Fonts/ARIALN.TTF")
            expect(F:Path("Fonts\\arialn.ttf")).as("normalised match")
                .eq("Fonts/ARIALN.TTF")
        end)

        it("honours an unregistered path the client can still load", function()
            H.font.addFace("Interface/AddOns/Mine/fonts/mine.ttf")
            expect(F:Path("Interface/AddOns/Mine/fonts/mine.ttf"))
                .eq("Interface/AddOns/Mine/fonts/mine.ttf")
            expect(F:Name("Interface/AddOns/Mine/fonts/mine.ttf"))
                .as("and remembers it").eq("mine")
        end)

        it("falls back for a name whose addon is gone", function()
            expect(F:Path("Some Font From A Deleted Addon")).eq(F.FALLBACK)
        end)

        it("falls back for nil and empty values", function()
            expect(F:Path(nil)).eq(F.FALLBACK)
            expect(F:Path("")).eq(F.FALLBACK)
            expect(F:Path(42)).eq(F.FALLBACK)
        end)

        it("always resolves to something the client can load", function()
            expect(H.font.hasFace(F:Path("nonsense"))).truthy()
        end)

        it("returns a display name for a name or a path, nil for neither", function()
            expect(F:Name("Arial Narrow")).eq("Arial Narrow")
            expect(F:Name("Fonts/ARIALN.TTF")).eq("Arial Narrow")
            expect(F:Name("Fonts/never-existed.ttf")).isNil()
            expect(F:Name(nil)).isNil()
        end)

        it("adds a font by path alone, naming it after the file", function()
            H.font.addFace("Interface/AddOns/MyMedia/fonts/Expressway.ttf")
            expect(F:Add("Interface/AddOns/MyMedia/fonts/Expressway.ttf")).eq("Expressway")
            expect(F:Path("Expressway"))
                .eq("Interface/AddOns/MyMedia/fonts/Expressway.ttf")
        end)

        it("returns the existing name when the path is already known", function()
            expect(F:Add("Fonts/ARIALN.TTF")).eq("Arial Narrow")
        end)

        it("refuses to add a path the client cannot load", function()
            expect(F:Add("Interface/AddOns/Typo/fnots/mine.ttf")).isNil()
        end)

        it("falls back to the full path when the filename is taken", function()
            H.font.addFace("Interface/AddOns/A/fonts/shared.ttf")
            H.font.addFace("Interface/AddOns/B/fonts/shared.ttf")
            expect(F:Add("Interface/AddOns/A/fonts/shared.ttf")).eq("shared")
            expect(F:Add("Interface/AddOns/B/fonts/shared.ttf"))
                .as("unambiguous, and still tells the user which file")
                .eq("Interface/AddOns/B/fonts/shared.ttf")
        end)

        it("shapes options for a dropdown", function()
            local options = F:Options()
            expect(#options).eq(#F:List())
            for _, opt in ipairs(options) do
                expect(opt.value).eq(opt.label)
                expect(F:Has(opt.value)).truthy()
            end
        end)
    end)

    describe("Refresh", function()
        it("fires SUUUI_FONTS_CHANGED when the set grows", function()
            F:List()
            local spy = H.eventSpy("SUUUI_FONTS_CHANGED")
            H.addFont("LateMediaFont", "Fonts/late.ttf")
            F:Refresh()
            expect(spy.count).eq(1)
        end)

        it("stays quiet when nothing changed", function()
            F:List()
            local spy = H.eventSpy("SUUUI_FONTS_CHANGED")
            F:Refresh()
            expect(spy.count).eq(0)
        end)

        it("keeps a font a plugin registered", function()
            -- A plugin registers in onInit, which runs before the login rescan. A rescan
            -- rebuilds from the sources, so without a replay it would drop the font.
            H.font.addFace("Interface/AddOns/MyPlugin/fonts/mine.ttf")
            F:Register("Plugin Face", "Interface/AddOns/MyPlugin/fonts/mine.ttf")
            F:Refresh()
            expect(F:Has("Plugin Face")).truthy()
            expect(F:Path("Plugin Face")).eq("Interface/AddOns/MyPlugin/fonts/mine.ttf")
        end)

        it("survives a plugin font whose file disappeared", function()
            H.font.addFace("Interface/AddOns/Gone/fonts/gone.ttf")
            F:Register("Gone Face", "Interface/AddOns/Gone/fonts/gone.ttf")
            H.font.faces[H.font.normalise("Interface/AddOns/Gone/fonts/gone.ttf")] = nil
            F:Refresh()
            expect(F:Has("Gone Face")).as("dropped, not resurrected as a bad path").falsy()
            expect(F:Path("Gone Face")).eq(F.FALLBACK)
        end)
    end)
end)

describe("Theme font token", function()
    local SuuUI, T

    before_each(function()
        SuuUI = H.setup()
        T = SuuUI.Theme
    end)

    local function userTheme()
        T:CreateUserTheme("Custom", "Modern")
        T:SetActive("Custom")
        return "Custom"
    end

    it("hands consumers a path, not the stored name", function()
        expect(T:GetToken("fontFamilyMain")).eq("Fonts/FRIZQT__.TTF")
        expect(H.font.hasFace(T:GetToken("fontFamilyMain"))).truthy()
    end)

    it("resolves a stored font name to its path", function()
        local theme = userTheme()
        T:SetUserToken(theme, "fontFamilyMain", "Arial Narrow")
        expect(T:GetToken("fontFamilyMain")).eq("Fonts/ARIALN.TTF")
    end)

    it("keeps the stored name available for the editor", function()
        local theme = userTheme()
        T:SetUserToken(theme, "fontFamilyMain", "Morpheus")
        expect(T:GetTokenRaw("fontFamilyMain")).as("what was saved").eq("Morpheus")
        expect(T:GetToken("fontFamilyMain")).as("what components use")
            .eq("Fonts/MORPHEUS.TTF")
    end)

    it("falls back to a loadable face when the stored name is gone", function()
        local theme = userTheme()
        T:SetUserToken(theme, "fontFamilyMain", "Font From An Uninstalled Addon")
        expect(T:GetToken("fontFamilyMain")).eq(SuuUI.Fonts.FALLBACK)
        expect(H.font.hasFace(T:GetToken("fontFamilyMain"))).truthy()
    end)

    it("re-resolves and restyles when a media addon registers the font later", function()
        local theme = userTheme()
        T:SetUserToken(theme, "fontFamilyMain", "Expressway")
        expect(T:GetToken("fontFamilyMain")).as("not there yet")
            .eq(SuuUI.Fonts.FALLBACK)

        local spy = H.eventSpy("SUUUI_THEME_CHANGED")
        H.font.addFace("Interface/AddOns/Media/Expressway.ttf")
        SuuUI.Fonts:Register("Expressway", "Interface/AddOns/Media/Expressway.ttf")
        SuuUI.Events:Emit("SUUUI_FONTS_CHANGED")

        expect(T:GetToken("fontFamilyMain")).eq("Interface/AddOns/Media/Expressway.ttf")
        expect(spy.count).as("components must restyle").eq(1)
    end)

    it("does not restyle when a font registration changes nothing", function()
        local spy = H.eventSpy("SUUUI_THEME_CHANGED")
        SuuUI.Events:Emit("SUUUI_FONTS_CHANGED")
        expect(spy.count).eq(0)
    end)
end)

describe("Theme font propagation", function()
    local SuuUI, T, host

    before_each(function()
        SuuUI = H.setup()
        T = SuuUI.Theme
        host = H.parent(400, 300)
        T:CreateUserTheme("Custom", "Modern")
        T:SetActive("Custom")
    end)

    local function useFace(name)
        T:SetUserToken("Custom", "fontFamilyMain", name)
    end

    it("reaches a Text handle", function()
        local text = H.C.Text({ text = "Hello" }, host)
        useFace("Arial Narrow")
        expect((H.fontOf(text))).eq("Fonts/ARIALN.TTF")
    end)

    it("reaches a Button label and re-fits it", function()
        local btn = H.mount(H.C.Button({ label = "Settings" }, host))
        local wide = btn:GetWidth()
        useFace("Arial Narrow")

        expect((H.fontOf(btn._label))).eq("Fonts/ARIALN.TTF")
        expect(btn:GetWidth()).as("a narrower face means a narrower button").lt(wide)
        H.expectTextNotClipped(btn._label)
    end)

    it("grows a Button for a wider face without clipping its label", function()
        local btn = H.mount(H.C.Button({ label = "Settings" }, host))
        local before = btn:GetWidth()
        useFace("Morpheus")

        expect(btn:GetWidth()).gt(before)
        H.expectTextNotClipped(btn._label)
    end)

    it("reaches an Input", function()
        local input = H.mount(H.C.Input({ value = "text" }, host))
        useFace("Arial Narrow")
        expect((H.fontOf(input._eb))).eq("Fonts/ARIALN.TTF")
    end)

    it("re-measures a Dropdown's arrow column so it never truncates", function()
        local dd = H.mount(H.C.Dropdown({
            options = { { value = 1, label = "One" } }, value = 1, w = 200,
        }, host))
        useFace("Morpheus")
        H.expectTextNotClipped(dd._arrow)
        H.expectTextNotClipped(dd._selText)
        H.expectInside(dd._arrow, dd:GetFrame())
    end)

    it("re-flows a row when the face changes the text height", function()
        local col = H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "vertical", w = 300,
        })
        local text = H.C.Text({ text = "Hello" }, col:GetFrame())
        col:Add(text, { width = "fill" })
        local short = text:GetHeight()

        useFace("Morpheus")
        expect(text:GetHeight()).as("taller face, taller line").gt(short)
        H.expectTextNotClipped(text:GetFrame())
    end)

    it("emits SIZE_CHANGED from a Text a layout had pinned", function()
        -- A layout-assigned height is measured at the face in force at the time, so a
        -- face swap has to report the new height or the container keeps the old one.
        local col = H.Layout:CreateContainer({
            parent = host, layout = "flow", dir = "vertical", w = 300,
        })
        local text = H.C.Text({ text = "Hello" }, col:GetFrame())
        col:Add(text, { width = "fill", height = H.lineHeight(H.token("fontSizeMd")) })

        local spy = H.signalSpy(text, H.S.SIGNALS.SIZE_CHANGED)
        useFace("Morpheus")
        expect(spy.count).gte(1)
        expect(spy:arg(2)).as("reports the taller line")
            .gte(H.lineHeight(H.token("fontSizeMd"), "Fonts/MORPHEUS.TTF"))
    end)

    it("renders every face the dropdown offers without clipping", function()
        local text = H.mount(H.C.Text({ text = "Sample" }, host))
        for _, opt in ipairs(SuuUI.Fonts:Options()) do
            useFace(opt.value)
            expect((H.fontOf(text))).as(opt.label .. " applied")
                .eq(SuuUI.Fonts:Path(opt.value))
            H.expectTextNotClipped(text:GetFrame())
        end
    end)
end)
