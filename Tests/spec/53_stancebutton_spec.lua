-- Components/StanceButton.lua
--
-- The shapeshift bar: warrior stances, druid forms, rogue stealth, priest shadowform, PALADIN
-- AURAS. Not "stances" -- that is Blizzard's name for the API, not its scope, and a paladin's eight
-- auras are the widest case this has to size for.
--
-- The assertions that matter most here are about the TEMPLATE, because this is the one SuuUI button
-- that cannot own its own click path: a stance button carries no `type` attribute and
-- CastShapeshiftForm is blocked for addon code, both probed in game. So "clicking casts the form" is
-- the load-bearing spec, and it is asserted against the same recorded observable the client moves.

local H = require("harness")

describe("Components.StanceButton", function()
    local SuuUI

    before_each(function()
        H.setup()
        SuuUI = H.SuuUI
        -- Three forms, contiguous, form 2 active. Contiguity is a harness requirement because
        -- GetNumShapeshiftForms answers a count and consumers loop 1..count.
        H.setStanceForm(1, { spellID = 2457, texture = "battle" }, { silent = true })
        H.setStanceForm(2, { spellID = 71, texture = "defensive" }, { silent = true })
        H.setStanceForm(3, { spellID = 2458, texture = "berserker" }, { silent = true })
        H.setStanceForm(2, { isActive = true }, { silent = true })
    end)

    local function make(form, props)
        props = props or {}
        props.form = form
        props.size = props.size or 32
        return SuuUI.Components.StanceButton(props, H.env.UIParent)
    end

    describe("the template is the mechanism", function()
        it("casts the form its ID names when clicked", function()
            -- THE load-bearing assertion. There is no attribute to state and no castable function
            -- an addon may call, so the template's own OnClick reading GetID() is the entire
            -- casting path. If this breaks, the button looks perfect and does nothing -- which is
            -- exactly what ActionButton shipped once with press-versus-release.
            local b = make(3)
            H.click(b:GetFrame())
            expect(H.getCastStance()).eq(3)
        end)

        it("carries its form as the frame's ID, not as a field", function()
            local b = make(2)
            expect(b:GetFrame():GetID()).as("the ID IS the wiring").eq(2)
            expect(b:GetForm()).eq(2)
        end)

        it("is a CheckButton, because the active form reads as a checked state", function()
            local b = make(1)
            expect(b:GetFrame():GetObjectType()).eq("CheckButton")
            expect(b:GetFrame()._template).eq("StanceButtonTemplate")
        end)

        it("re-points to another form without a secure snippet", function()
            -- Unlike an action button's slot, the id is NOT a secure attribute, so Lua may move it
            -- directly. That difference is why there is no paging machinery here.
            local b = make(1)
            expect(b:GetFrame():GetChecked()).as("form 1 is not active").falsy()
            H.setStanceForm(3, { isActive = true }, { silent = true })
            b:SetForm(3)
            H.click(b:GetFrame())
            expect(H.getCastStance()).eq(3)
            -- Moving the id must REPAINT too. Without this only the cast is asserted, and a
            -- SetForm that repointed without repainting would keep the old form's art.
            expect(b:GetFrame():GetChecked()).as("repainted for its new form").truthy()
        end)

        it("asserts on a missing form or size rather than rendering a dead button", function()
            expect(function() SuuUI.Components.StanceButton({ size = 32 }, H.env.UIParent) end)
                .throws("form index")
            expect(function() SuuUI.Components.StanceButton({ form = 1 }, H.env.UIParent) end)
                .throws("size")
        end)
    end)

    describe("the template's own art is silenced", function()
        it("clears the icon, hotkey and cooldown the template ships", function()
            -- Ours draws on top. Safe only because Blizzard's StanceBar_Update walks
            -- StanceButton1..N BY NAME and cannot find a button named by our prefix -- otherwise
            -- every event would put this back.
            local b = make(1, { name = "SuuUITestStance1" })
            local f = b:GetFrame()
            expect(f.icon:IsShown()).as("template icon hidden").falsy()
            expect(f.HotKey:IsShown()).falsy()
            expect(f.cooldown:IsShown()).falsy()
        end)

        it("empties and hides the template's border and highlight textures", function()
            -- HIDDEN, not nil'd. The setters REFUSE nil on this client -- "bad argument #2 to '?'
            -- (Usage: self:SetNormalTexture(asset))" -- so clearing one means taking the Texture
            -- from the getter and hiding it. Passing nil raised during construction and took the
            -- whole bar down, silently, because the build runs inside a pcall'd Settings watcher.
            local f = make(1):GetFrame()
            local normal, hl = f:GetNormalTexture(), f:GetHighlightTexture()
            expect(normal).as("the object still exists").notNil()
            expect(normal:IsShown()).as("but draws nothing").falsy()
            expect(normal:GetTexture()).isNil()
            expect(hl:IsShown()).falsy()
        end)

        it("never passes nil to a texture setter, because the client refuses it", function()
            -- Pinned as a REQUIREMENT rather than left implicit: the harness now raises on a nil
            -- asset exactly as the client does, so a future "tidy-up" back to SetNormalTexture(nil)
            -- fails here instead of in game.
            local f = make(1):GetFrame()
            expect(function() f:SetNormalTexture(nil) end).throws("Usage: self:SetNormalTexture")
            expect(function() f:SetHighlightTexture(nil) end).throws("Usage")
        end)

        it("builds SuuUI's own icon with no border, so the plate owns the surface", function()
            local b = make(1)
            expect(b._iconComp).notNil()
            expect(b._iconComp._border).as("the grid's plate draws the surface").falsy()
        end)
    end)

    describe("painting", function()
        it("prefers the spell's texture over the form's own", function()
            -- ElvUI derives the icon from spellID and uses the form texture only as a fallback.
            -- Followed here, so the two agree on which art a form shows.
            H.setSpellTexture(2457, "Interface\\Icons\\FROM_SPELL")
            local b = make(1)
            expect(b._iconComp:GetIcon()).as("the spell's art won").eq("Interface\\Icons\\FROM_SPELL")
        end)

        it("falls back to the form's own texture when the spell has no art", function()
            -- Staged with no spell texture, so GetSpellTexture answers nil and the form's own
            -- texture return is used. Both halves are needed or the preference is unprovable.
            local b = make(2)
            expect(b._iconComp:GetIcon()).eq("defensive")
        end)

        it("paints nothing for a form beyond the count", function()
            -- A grid sized for eight auras on a class with three forms must not paint the surplus.
            local b = make(7)
            expect(b._iconComp:GetIcon()).isNil()
            expect(b:IsActive()).falsy()
        end)

        it("checks the button for the active form and only that one", function()
            local one, two = make(1), make(2)
            expect(two:GetFrame():GetChecked()).as("form 2 is active").truthy()
            expect(one:GetFrame():GetChecked()).falsy()
            expect(two:IsActive()).truthy()
            expect(one:IsActive()).falsy()
        end)

        it("moves the checked state when the active form changes", function()
            local one, two = make(1), make(2)
            H.setStanceForm(1, { isActive = true })
            expect(one:GetFrame():GetChecked()).as("the event repainted it").truthy()
            expect(two:GetFrame():GetChecked()).as("and cleared the old one").falsy()
        end)

        it("RINGS the active form, because SetChecked draws nothing here", function()
            -- The bar's primary information, and it shipped invisible. Construction hides every one
            -- of the template's textures INCLUDING its checked art, so SetChecked alone leaves every
            -- button looking identical -- which is what was reported in game.
            local two = make(2)
            H.expectTokenColor(H.borderColor(two._overlay), "colorAccent")
        end)

        it("leaves an inactive form unringed", function()
            local one = make(1)
            expect(H.borderColor(one._overlay)).deepEq({ 0, 0, 0, 0 })
        end)

        it("moves the ring when the active form changes", function()
            local one, two = make(1), make(2)
            H.expectTokenColor(H.borderColor(two._overlay), "colorAccent")
            H.setStanceForm(1, { isActive = true })
            H.expectTokenColor(H.borderColor(one._overlay), "colorAccent")
            expect(H.borderColor(two._overlay)).as("the old ring cleared").deepEq({ 0, 0, 0, 0 })
        end)

        it("does not use dimming for the active state, which uncastable already owns", function()
            -- Two states through one channel cannot be told apart. The active form is a ring; an
            -- uncastable form is desaturated and dimmed. An active AND uncastable form shows both.
            H.setStanceForm(3, { isCastable = false, isActive = true }, { silent = true })
            local three = make(3)
            H.expectTokenColor(H.borderColor(three._overlay), "colorAccent")
            expect(three._iconComp._icon:IsDesaturated()).truthy()
        end)

        it("re-resolves the ring colour on a theme change", function()
            local two = make(2)
            two:ApplyTheme()
            H.expectTokenColor(H.borderColor(two._overlay), "colorAccent")
        end)

        it("desaturates AND dims a form that cannot be cast", function()
            H.setStanceForm(3, { isCastable = false }, { silent = true })
            local b = make(3)
            expect(b:IsCastable()).falsy()
            expect(b._iconComp._icon:IsDesaturated()).truthy()
            expect(H.vertexColor(b._iconComp._icon)[4])
                .as("dimmed to the disabled opacity").lt(1)
        end)

        it("leaves a castable form at full colour", function()
            local b = make(1)
            expect(b._iconComp._icon:IsDesaturated()).falsy()
            expect(H.vertexColor(b._iconComp._icon)).deepEq({ 1, 1, 1, 1 })
        end)
    end)

    describe("cooldown", function()
        it("treats the numeric active flag as a number, not a truth value", function()
            -- The client sends 0 for "no cooldown running" and ElvUI tests `active ~= 0`. Testing
            -- truthiness would make 0 truthy in Lua and paint a permanent sweep over every form.
            -- A DURATION IS PRESENT here on purpose. With duration 0 the other half of the
            -- condition hides the bug, and a component testing truthiness would pass.
            H.setStanceForm(1, { cooldownStart = 500, cooldownDuration = 30, cooldownActive = 0 },
                { silent = true })
            local b = make(1)
            expect(b._cooldown._cdStart or 0).as("no sweep for active = 0").eq(0)
        end)

        it("paints a running cooldown", function()
            H.setStanceForm(1, { cooldownStart = 500, cooldownDuration = 30, cooldownActive = 1 },
                { silent = true })
            local b = make(1)
            expect(b._cooldown._cdStart).eq(500)
            expect(b._cooldown._cdDuration).eq(30)
        end)

        it("clears a finished cooldown rather than leaving the old sweep", function()
            H.setStanceForm(1, { cooldownStart = 500, cooldownDuration = 30, cooldownActive = 1 },
                { silent = true })
            local b = make(1)
            expect(b._cooldown._cdStart).eq(500)
            H.setStanceForm(1, { cooldownStart = 0, cooldownDuration = 0, cooldownActive = 0 })
            expect(b._cooldown._cdStart or 0).as("swipe cleared").eq(0)
        end)

        it("repaints on the cooldown event", function()
            local b = make(1)
            H.setStanceForm(1, { cooldownStart = 900, cooldownDuration = 12, cooldownActive = 1 },
                { silent = true })
            H.fireEvent("UPDATE_SHAPESHIFT_COOLDOWN")
            expect(b._cooldown._cdStart).eq(900)
        end)
    end)

    describe("hotkey", function()
        it("reads the SHAPESHIFTBUTTON family, which is not what the frame name suggests", function()
            -- Measured from ElvUI: the family is SHAPESHIFTBUTTON, not STANCEBUTTON. A wrong family
            -- shows no key at all while every other assertion passes.
            H.setBinding("SHAPESHIFTBUTTON2", "2")
            local b = make(2, { binding = "SHAPESHIFTBUTTON2" })
            expect(b._hotkeyText:IsShown()).truthy()
            expect(b._hotkeyText:GetText()).eq("2")
        end)

        it("abbreviates a long key the same way an action button does", function()
            -- Same abbreviator as an action button, so a stance hotkey reads identically to the
            -- one on the bar above it rather than spelling the modifier out.
            H.setBinding("SHAPESHIFTBUTTON1", "SHIFT-1")
            local b = make(1, { binding = "SHAPESHIFTBUTTON1" })
            expect(b._hotkeyText:GetText()).as("shortened, not raw").eq("S1")
        end)

        it("names its binding command through GetBinding, like an action button", function()
            local b = make(2, { binding = "SHAPESHIFTBUTTON2" })
            expect(b:GetBinding())
                .as("keybind mode walks a stance bar and an action bar through ONE accessor "
                    .. "rather than branching on the button kind")
                .eq("SHAPESHIFTBUTTON2")
            b:SetBinding("SHAPESHIFTBUTTON4")
            expect(b:GetBinding()).eq("SHAPESHIFTBUTTON4")
            expect(make(1, {}):GetBinding()).as("and nil when it carries none").isNil()
        end)

        it("hides when there is no binding, and when the readout is switched off", function()
            local b = make(1, { binding = "SHAPESHIFTBUTTON1" })
            expect(b._hotkeyText:IsShown()).as("nothing bound").falsy()
            H.setBinding("SHAPESHIFTBUTTON1", "1")
            b:SetShowHotkey(true)
            expect(b._hotkeyText:IsShown()).truthy()
            b:SetShowHotkey(false)
            expect(b._hotkeyText:IsShown()).falsy()
        end)

        it("repaints on UPDATE_BINDINGS", function()
            local b = make(1, { binding = "SHAPESHIFTBUTTON1" })
            H.setBinding("SHAPESHIFTBUTTON1", "5")
            H.fireEvent("UPDATE_BINDINGS")
            expect(b._hotkeyText:GetText()).eq("5")
        end)
    end)

    describe("events", function()
        it("repaints on BOTH shapeshift events, which are different things", function()
            -- PLURAL = the set of forms changed. SINGULAR = which one is active changed. A button
            -- that listens to only one is broken in a different way each time: it either never
            -- notices a new form or never notices a stance dance.
            local b = make(1)
            H.setStanceForm(1, { isActive = true }, { silent = true })
            H.fireEvent("UPDATE_SHAPESHIFT_FORM")
            expect(b:GetFrame():GetChecked()).as("singular repainted").truthy()

            H.setStanceForm(1, { isActive = false }, { silent = true })
            H.fireEvent("UPDATE_SHAPESHIFT_FORMS")
            expect(b:GetFrame():GetChecked()).as("plural repainted too").falsy()
        end)

        it("repaints on the usable event", function()
            local b = make(1)
            H.setStanceForm(1, { isCastable = false }, { silent = true })
            H.fireEvent("UPDATE_SHAPESHIFT_USABLE")
            expect(b._iconComp._icon:IsDesaturated()).truthy()
        end)

        it("shares ONE event frame across every button", function()
            local a, b, c = make(1), make(2), make(3)
            expect(SuuUI._StanceButtonInternals.liveCount()).eq(3)
            expect(SuuUI._StanceButtonInternals.eventFrame()).notNil()
            a:Destroy(); b:Destroy(); c:Destroy()
            expect(SuuUI._StanceButtonInternals.liveCount()).eq(0)
        end)

        it("stops listening once the last button goes", function()
            local b = make(1)
            local ef = SuuUI._StanceButtonInternals.eventFrame()
            b:Destroy()
            expect(ef:IsEventRegistered("UPDATE_SHAPESHIFT_FORM"))
                .as("six events left running for no one is a leak").falsy()
        end)
    end)

    describe("signals", function()
        it("emits CLICKED once per click", function()
            -- Once, not twice. The template registers its own click phases and PostClick can fire
            -- for both, so anything counting these would otherwise see a double.
            local n = 0
            local b = make(1)
            SuuUI.UISignals:Connect(b, SuuUI.UISignals.SIGNALS.CLICKED, function() n = n + 1 end)
            H.click(b:GetFrame())
            expect(n).eq(1)
        end)

        it("does NOT own the tooltip, because the template already does", function()
            -- Shipping our own setter alongside the template's made the tooltip flick between the
            -- button and the screen corner on every hover: two owners anchoring one frame. Pinned so
            -- a future "the stance bar has no tooltip code, that looks like an oversight" does not
            -- put it back.
            local b = make(1)
            b:GetFrame():_fire("OnEnter")
            expect(H.SuuUI.Components.StanceButton).notNil()
            expect(b._showTooltip).as("no tooltip method at all").isNil()
            expect(b._tooltipAnchor).isNil()
        end)

        it("emits mouse enter and leave", function()
            local seen = {}
            local b = make(1)
            SuuUI.UISignals:Connect(b, SuuUI.UISignals.SIGNALS.MOUSE_ENTER,
                function() seen.enter = true end)
            SuuUI.UISignals:Connect(b, SuuUI.UISignals.SIGNALS.MOUSE_LEAVE,
                function() seen.leave = true end)
            b:GetFrame():_fire("OnEnter")
            b:GetFrame():_fire("OnLeave")
            expect(seen.enter).truthy()
            expect(seen.leave).truthy()
        end)

        it("emits SIZE_CHANGED when resized", function()
            local w
            local b = make(1)
            SuuUI.UISignals:Connect(b, SuuUI.UISignals.SIGNALS.SIZE_CHANGED,
                function(_, nw) w = nw end)
            b:SetSize(48)
            expect(w).eq(48)
        end)
    end)

    describe("hosted in an ActionBarGrid through the factory seam", function()
        local function grid(slots)
            return SuuUI.Components.ActionBarGrid({
                slots = slots, buttonSize = 32, rows = 1,
                buttonFactory = function(p, parent)
                    return SuuUI.Components.StanceButton({
                        form = p.slot, size = p.size, binding = p.binding, name = p.name,
                    }, parent)
                end,
            }, H.env.UIParent)
        end

        it("puts form N in cell N", function()
            local g = grid({ 1, 2, 3 })
            local b = g:GetButtons()
            expect(#b).eq(3)
            expect(b[2]:GetForm()).eq(2)
            H.click(b[3]:GetFrame())
            expect(H.getCastStance()).eq(3)
        end)

        it("survives a re-apply, which is where a missing interface method would bite", function()
            -- The grid calls GetSlot, SetSize, SetBinding, SetShowHotkey, SetShowMacroText and
            -- SetShowCount on every existing button when a setting changes. A factory button
            -- missing one dies on the SECOND apply, not the first, so this asserts the second.
            local g = grid({ 1, 2, 3 })
            expect(function()
                g:SetButtonSize(40)
                g:SetShowHotkeys(false)
                g:SetSpacing(2)
            end).notThrows()
            expect(g:GetButtons()[1]:GetWidth()).as("the resize reached the button").eq(40)
        end)

        it("does NOT rebuild its buttons when only a setting changed", function()
            -- This is what GetSlot is for. A button whose identity accessor never matches makes the
            -- grid destroy and recreate every cell on every settings change -- invisible in the
            -- result, but it re-fires CHILDREN_CHANGED, and a subscriber re-states a frame
            -- reference per button on that signal.
            local g = grid({ 1, 2, 3 })
            local rebuilds = 0
            SuuUI.UISignals:Connect(g, SuuUI.UISignals.SIGNALS.CHILDREN_CHANGED,
                function() rebuilds = rebuilds + 1 end)
            g:SetButtonSize(40)
            g:SetSpacing(2)
            expect(rebuilds).as("no rebuild for a pure settings change").eq(0)
        end)

        it("shrinks and grows with the form count", function()
            -- A druid learning a form, or a class with fewer forms than the last one played.
            local g = grid({ 1, 2, 3 })
            g:SetSlots({ 1, 2 })
            expect(#g:GetButtons()).eq(2)
            g:SetSlots({ 1, 2, 3 })
            expect(#g:GetButtons()).eq(3)
            expect(g:GetButtons()[3]:GetForm()).eq(3)
        end)

        it("releases every button when the grid goes", function()
            local g = grid({ 1, 2, 3 })
            expect(SuuUI._StanceButtonInternals.liveCount()).eq(3)
            g:Destroy()
            expect(SuuUI._StanceButtonInternals.liveCount()).eq(0)
        end)
    end)

    describe("teardown", function()
        it("hides the frame but does NOT reparent it", function()
            -- SetParent(nil) on a frame built from a Blizzard template is the one step Suppress.lua
            -- also forbids: unnecessary, and refused in combat on a frame the client protects.
            local b = make(1)
            local f = b:GetFrame()
            b:Destroy()
            expect(f:IsShown()).falsy()
            expect(f:GetParent()).as("still parented").notNil()
        end)
    end)
end)
