-- MessageLog: the SuuUI wrapper around the client's ScrollingMessageFrame.
local H = require("harness")

describe("MessageLog", function()
    before_each(function() H.setup() end)

    local function make(props)
        return H.mount(H.C.MessageLog(props or {}, H.parent(420, 140)))
    end

    describe("construction", function()
        it("wraps a real ScrollingMessageFrame", function()
            local log = make()
            expect(log._log).notNil()
            expect(log._log:GetObjectType()).eq("ScrollingMessageFrame")
        end)

        it("sizes from props", function()
            local log = make({ w = 300, h = 90 })
            H.expectSize(log, 300, 90)
        end)

        it("sets a font at construction, so the log can draw at all", function()
            local log = make()
            log:AddMessage("hello")
            expect(#H.getChatLines(log._log))
                .as("a log with no font is present, sized, reports its messages and renders "
                    .. "nothing -- silent in game").eq(1)
        end)

        it("justifies LEFT, because a bare message frame centres every line", function()
            -- Found by looking at the game: a single line sat 135 units right of the chip below
            -- it, which is half the slack in a 460-wide frame. A message log is a column of text
            -- with a left edge, so this is stated rather than offered as a prop.
            local log = make()
            expect(log._log:GetJustifyH()).eq("LEFT")
        end)

        it("draws a text shadow, which is what makes a frameless log legible", function()
            -- Not decoration: the log sits straight over the game world, so a glyph on pale terrain
            -- has nothing separating it from the background. The concept specifies a text-shadow on
            -- every chat line for exactly this reason.
            local log = make()
            local r, g, b, a = log._log:GetShadowColor()
            local ink = H.token("colorGray950")
            expect(r).near(ink[1], 0.02)
            expect(g).near(ink[2], 0.02)
            expect(b).near(ink[3], 0.02)
            expect(a).as("from opacityTextShadow").near(H.token("opacityTextShadow"), 0.01)
            local x, y = log._log:GetShadowOffset()
            expect(x).eq(H.SuuUI.Pixel.Line(1))
            expect(y).as("cast downward").eq(-H.SuuUI.Pixel.Line(1))
        end)

        it("keeps the shadow after a font-size change", function()
            -- Applied through the font path, so a size change must not drop it.
            local log = make()
            log:SetFontSize("lg")
            local _, _, _, a = log._log:GetShadowColor()
            expect(a).near(H.token("opacityTextShadow"), 0.01)
        end)

        it("enables hyperlinks, or every item link is dead to the click", function()
            local log = make()
            expect(log._log:GetHyperlinksEnabled()).eq(true)
        end)

        it("raises the default line cap above Blizzard's 128", function()
            local log = make()
            expect(log:GetMaxLines()).gt(128)
        end)

        it("takes an explicit cap", function()
            expect(make({ maxLines = 40 }):GetMaxLines()).eq(40)
        end)

        it("separates rows by the spacing token, not flush like a bare frame", function()
            -- A bare ScrollingMessageFrame stacks lines flush, which is what made the log read as a
            -- wall of text against the concept's separated rows.
            local log = make()
            expect(log._log:GetSpacing()).eq(H.token("spaceXxs"))
        end)

        it("re-derives the row gap when the spacing token changes", function()
            -- Token-derived, so it belongs on the theme path rather than being cached at construction.
            local log = make()
            H.T:CreateUserTheme("Roomy", "Default")
            H.T:SetUserToken("Roomy", "spaceXxs", 6)
            H.T:SetActive("Roomy")
            expect(log._log:GetSpacing()).as("re-read on the theme path").eq(6)
        end)

        it("insets the log by the border width on both chrome states", function()
            -- The inset is constant so text does not shift by a pixel when chrome fades in.
            local bare    = make({ chrome = false })
            local chromed = make({ chrome = true })
            -- Border width PLUS the concept's inner padding, which is why its text does not run
            -- against the glass edge. The load-bearing part is unchanged and is what this asserts:
            -- both chrome states inset by the SAME amount, so nothing shifts when chrome fades in.
            local want = H.token("borderWidth") + H.token("spaceSm")
            expect(H.box(bare._log).left - H.box(bare).left).near(want, 0.51)
            expect(H.box(chromed._log).left - H.box(chromed).left).near(want, 0.51)
        end)
    end)

    describe("messages", function()
        it("stores and reads back text, colour and lineID", function()
            local log = make()
            log:AddMessage("Thalvyn: hi", 0.25, 1, 0.25, 91)
            expect(log:GetNumMessages()).eq(1)
            local text, r, g, b, id = log:GetMessageInfo(1)
            expect(text).eq("Thalvyn: hi")
            expect(g).near(1, 0.0001)
            expect(id).as("lineID is what a player link's context menu resolves against").eq(91)
        end)

        it("keeps per-message colour, so one log holds two channels", function()
            local log = make()
            log:AddMessage("guild", 0.25, 1, 0.25)
            log:AddMessage("whisper", 1, 0.5, 1)
            local _, r1 = log:GetMessageInfo(1)
            local _, r2 = log:GetMessageInfo(2)
            expect(r1).near(0.25, 0.0001)
            expect(r2).near(1, 0.0001)
        end)

        it("Clear empties it", function()
            local log = make()
            log:AddMessage("a")
            log:Clear()
            expect(log:GetNumMessages()).eq(0)
        end)

        it("tolerates a nil message rather than raising inside an event handler", function()
            local log = make()
            expect(function() log:AddMessage(nil) end).notThrows()
            expect(log:GetNumMessages()).eq(1)
        end)
    end)

    describe("fading", function()
        it("is off unless asked for", function()
            expect(make():IsFading()).eq(false)
        end)

        it("takes the three values together", function()
            local log = make({ fading = true, timeVisible = 8, fadeDuration = 3 })
            expect(log:IsFading()).eq(true)
            expect(log._log:GetTimeVisible()).eq(8)
            expect(log._log:GetFadeDuration()).eq(3)
        end)

        it("differs per log, which is the channels-fade/conversations-persist rule", function()
            local channel      = make({ fading = true, timeVisible = 8 })
            local conversation = make({ fading = false })
            expect(channel:IsFading()).eq(true)
            expect(conversation:IsFading())
                .as("a conversation is history, not a firehose").eq(false)
        end)

        it("SetFading leaves the timings alone when they are not restated", function()
            local log = make({ fading = true, timeVisible = 8, fadeDuration = 3 })
            log:SetFading(false)
            expect(log._log:GetTimeVisible())
                .as("switching fading off must not forget how it was tuned").eq(8)
        end)
    end)

    describe("scrolling", function()
        local function fill(log, n)
            for i = 1, (n or 6) do log:AddMessage("m" .. i) end
        end

        it("starts live", function()
            local log = make()
            fill(log)
            expect(log:AtBottom()).eq(true)
        end)

        it("emits SCROLL_CHANGED on every scroll", function()
            local log = make()
            fill(log)
            local spy = H.signalSpy(log, H.S.SIGNALS.SCROLL_CHANGED)
            log:ScrollUp()
            expect(spy.count).eq(1)
            log:ScrollToBottom()
            expect(spy.count).eq(2)
        end)

        it("emits AT_BOTTOM_CHANGED only on a real edge", function()
            local log = make()
            fill(log)
            local spy = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.AT_BOTTOM_CHANGED)
            log:ScrollUp()
            expect(spy.count).as("left the bottom").eq(1)
            expect(spy:arg(1)).eq(false)
            log:ScrollUp()
            expect(spy.count).as("still away from the bottom -- not an edge").eq(1)
            log:ScrollToBottom()
            expect(spy.count).eq(2)
            expect(spy:arg(1)).eq(true)
        end)

        it("a new message does not yank a scrolled reader down", function()
            local log = make()
            fill(log)
            log:ScrollUp()
            log:AddMessage("arrived")
            expect(log:AtBottom())
                .as("this is exactly what a jump-to-bottom affordance reports").eq(false)
        end)

        it("a new message while live keeps it live and emits nothing", function()
            local log = make()
            fill(log)
            local spy = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.AT_BOTTOM_CHANGED)
            log:AddMessage("arrived")
            expect(log:AtBottom()).eq(true)
            expect(spy.count).as("no edge, so no signal on every single message").eq(0)
        end)

        it("Clear returns a scrolled reader to the bottom and says so", function()
            local log = make()
            fill(log)
            log:ScrollUp()
            local spy = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.AT_BOTTOM_CHANGED)
            log:Clear()
            expect(log:AtBottom()).eq(true)
            expect(spy.count).eq(1)
        end)
    end)

    describe("input the client must be able to deliver", function()
        it("takes the MOUSE, or no link can ever be hit-tested", function()
            -- Shipped missing. `SetHyperlinksEnabled(true)` alone only asks the client to hit-test
            -- links; the click never reaches a Frame subtype that takes no mouse input, so every
            -- link rendered perfectly and was dead. Asserted on the frame rather than through a
            -- click, because a click helper that does not gate on this cannot tell the difference.
            local log = make()
            expect(log._log:IsMouseEnabled()).eq(true)
        end)

        it("takes the WHEEL, or its own scroll methods are unreachable", function()
            -- Also shipped missing: ScrollUp/ScrollDown/PageUp/ScrollToTop/ScrollToBottom all
            -- existed and nothing could deliver a gesture, so the buffer was write-only.
            local log = make()
            expect(log._log:IsMouseWheelEnabled()).eq(true)
        end)

        it("scrolls on a wheel notch and reports leaving the bottom", function()
            local log = make()
            for i = 1, 40 do log:AddMessage("line " .. i) end
            local spy = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.AT_BOTTOM_CHANGED)
            expect(log:AtBottom()).as("a fresh log sits at the newest line").eq(true)
            expect(H.scroll(log._log, 1)).as("delivered").eq(true)
            expect(log:AtBottom()).as("a notch up leaves the bottom").eq(false)
            expect(spy.count).as("and says so exactly once").eq(1)
            expect(spy:arg(1)).eq(false)
        end)

        it("shift plus wheel jumps to an end rather than paging, as Blizzard's chat does", function()
            local log = make()
            for i = 1, 40 do log:AddMessage("line " .. i) end
            H.scroll(log._log, 1)
            H.scroll(log._log, 1)
            expect(log:AtBottom()).eq(false)
            H.env.IsShiftKeyDown = function() return true end
            H.scroll(log._log, -1)
            expect(log:AtBottom()).as("one shift-notch down returns to the newest line").eq(true)
        end)
    end)

    describe("hyperlinks", function()
        it("translates a client hyperlink click into a signal", function()
            local log = make()
            local spy = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.HYPERLINK_CLICK)
            expect(H.clickHyperlink(log._log, "item:19019", "[Thunderfury]", "LeftButton")).eq(true)
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("item:19019")
            expect(spy:arg(2)).eq("[Thunderfury]")
            expect(spy:arg(3)).eq("LeftButton")
        end)

        it("emits enter and leave", function()
            local log = make()
            local enter = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.HYPERLINK_ENTER)
            local leave = H.signalSpy(log, H.C.MESSAGELOG_SIGNALS.HYPERLINK_LEAVE)
            log._log:GetScript("OnHyperlinkEnter")(log._log, "item:1")
            log._log:GetScript("OnHyperlinkLeave")(log._log)
            expect(enter.count).eq(1)
            expect(enter:arg(1)).eq("item:1")
            expect(leave.count).eq(1)
        end)
    end)

    describe("the legibility wash", function()
        -- Domenik's report: white text over snow or water is genuinely hard to read with the text
        -- shadow alone, which is what the frameless concept shipped. Every log now carries a
        -- bottom-weighted wash, and it is NOT the chrome -- see the `chrome` block below.
        local function stop(c)
            local r, g, b, a = c:GetRGBA()
            return { r, g, b, a }
        end

        it("draws on every log, chromed or not", function()
            -- Unconditional, because legibility is not a per-panel look decision: General, Global,
            -- Guild, Log and a conversation all sit over the same game world.
            for _, chromed in ipairs({ true, false }) do
                local log = make({ chrome = chromed })
                expect(log:IsWashGradient())
                    .as("chrome=" .. tostring(chromed) .. " still gets the wash").truthy()
            end
        end)

        it("puts the DENSE end at the BOTTOM, where the newest lines are", function()
            -- THE load-bearing assertion, and the reason the from/to arguments look inverted in the
            -- constructor. A ScrollingMessageFrame fills upward, so the ink has to be at the bottom;
            -- Glass's own convention is that `from` is the dense end AND the top, so the tokens are
            -- passed the other way round. Get this backwards and the wash is heaviest across the
            -- empty top of a sparse log while the text sits on the transparent end.
            --
            -- SetGradient's FIRST colour is the minimum, i.e. the bottom -- which the harness records
            -- as `grad.from`.
            local log = make({})
            local grad = log._wash._body:GetGradient()
            expect(grad).as("a real gradient, not the flat fallback").truthy()
            H.expectTokenColor(stop(grad.from), "colorChatWash")
            H.expectTokenColor(stop(grad.to), "colorChatWashFade")
        end)

        it("carries no sheen, because a lit edge would land on the thin end", function()
            -- Glass's sheen is a highlight along the TOP. On a bottom-weighted wash the top is the
            -- nearly-transparent end, so a sheen there draws a bright line on the game world rather
            -- than an edge on a surface.
            expect(make({})._wash._sheen).eq(false)
        end)

        it("re-resolves its colours when the wash token is edited", function()
            -- Was `fireEvent("SUUUI_THEME_CHANGED")` plus `expect(IsWashGradient()).truthy()`, which
            -- a mutation deleting `_wash:Refresh()` from ApplyTheme SURVIVED -- re-emitting on the
            -- same theme cannot distinguish a surface that re-resolves from one that never does.
            --
            -- `Refresh` is what calls Glass's `SetColors`, so without it a player dragging the Chat
            -- Wash Opacity slider in the theme editor would see nothing until the next reload. The
            -- assertion is the PAINTED bottom stop moving, which is the only thing that proves it.
            local log = make({})
            local before = stop(log._wash._body:GetGradient().from)[4]
            H.T:CreateUserTheme("Washy", "Modern")
            H.T:SetUserToken("Washy", "opacityChatWash", 0.20)
            H.T:SetActive("Washy")
            local after = stop(log._wash._body:GetGradient().from)[4]
            expect(before).as("the shipped dense end").gt(0.4)
            expect(after).as("follows the edited token").near(0.20, 0.001)
        end)

        it("is released on Destroy", function()
            local log = make({})
            log:Destroy()
            expect(log._wash).as("the Glass handle owns textures and a resize hook").eq(nil)
        end)
    end)

    describe("chrome", function()
        it("is frameless at rest -- no border and no backdrop fill", function()
            local log = make({ chrome = false })
            expect(log:HasChrome()).eq(false)
            local _, _, _, ba = log._f:GetBackdropBorderColor()
            expect(ba).near(0, 0.001)
        end)

        it("keeps the backdrop's FILL transparent either way", function()
            -- The surface is the wash. A solid colorBg on top of it would be two surfaces, and at
            -- opacityPanel (0.97) the wash underneath would be invisible -- so `chrome` was narrowed
            -- to the hairline alone rather than owning the fill as well.
            for _, chromed in ipairs({ true, false }) do
                local _, _, _, a = make({ chrome = chromed })._f:GetBackdropColor()
                expect(a).as("chrome=" .. tostring(chromed)).near(0, 0.001)
            end
        end)

        it("paints a hairline when chrome is on", function()
            local log = make({ chrome = true })
            expect(log:HasChrome()).eq(true)
            local _, _, _, ba = log._f:GetBackdropBorderColor()
            expect(ba).gt(0)
        end)

        it("flips at runtime, because the concept fades chrome in on hover", function()
            local log = make({ chrome = false })
            log:SetChrome(true)
            local _, _, _, ba = log._f:GetBackdropBorderColor()
            expect(ba).gt(0)
            log:SetChrome(false)
            local _, _, _, ba2 = log._f:GetBackdropBorderColor()
            expect(ba2).near(0, 0.001)
        end)
    end)

    describe("token-driven sizing", function()
        it("takes its font step from a token key, not a pixel size", function()
            local log = make({ size = "lg" })
            local _, size = log._log:GetFont()
            expect(size).eq(H.token("fontSizeLg"))
        end)

        it("follows a live edit of that token", function()
            local log = make({ size = "md" })
            -- Built-in themes are read-only, so a live edit goes through a user theme.
            H.T:CreateUserTheme("Big", "Modern")
            H.T:SetUserToken("Big", "fontSizeMd", 21)
            H.T:SetActive("Big")
            local _, size = log._log:GetFont()
            expect(size).as("a plugin exposing the step as a setting still follows the theme")
                .eq(21)
        end)

        it("SetFontSize moves it and reports the key back", function()
            local log = make({ size = "sm" })
            log:SetFontSize("xl")
            expect(log:GetFontSize()).eq("xl")
            local _, size = log._log:GetFont()
            expect(size).eq(H.token("fontSizeXl"))
        end)

        it("degrades an unknown key rather than raising inside an event handler", function()
            local log = make()
            expect(function() log:SetFontSize("enormous") end).notThrows()
        end)

        it("keeps the chrome state across a theme change", function()
            local log = make({ chrome = true })
            H.fireEvent("SUUUI_THEME_CHANGED")
            local _, _, _, ba = log._f:GetBackdropBorderColor()
            expect(ba).as("a theme change must not drop the chrome").gt(0)
        end)
    end)

    describe("layout integration", function()
        it("reacts to being resized by its parent, not just by SetSize", function()
            local host = H.parent(400, 200)
            local col = H.SuuUI.Layout:CreateContainer({
                parent = host, layout = "flow", dir = "vertical",
            })
            local log = H.C.MessageLog({}, host)
            col:Add(log, { width = "fill", height = 100 })
            local spy = H.signalSpy(log, H.S.SIGNALS.SIZE_CHANGED)
            col:SetSize(300, 200)
            expect(spy.count).gt(0)
            H.expectSize(log, 300, nil)
        end)
    end)

    describe("teardown", function()
        it("hides, disconnects and drops the theme subscription", function()
            local log = make()
            local spy = H.signalSpy(log, H.S.SIGNALS.SCROLL_CHANGED)
            log:Destroy()
            expect(log:IsShown()).eq(false)
            log:AddMessage("after")
            expect(spy.count).eq(0)
            expect(function() H.fireEvent("SUUUI_THEME_CHANGED") end).notThrows()
        end)
    end)

    describe("deliberate omissions", function()
        it("has no SetEnabled", function()
            expect(make().SetEnabled)
                .as("a stub would make Dependency.Bind's guard pass while nothing was inert, and "
                    .. "the one real disabling -- dropping mouse -- would kill hyperlinks")
                .eq(nil)
        end)
    end)
end)
