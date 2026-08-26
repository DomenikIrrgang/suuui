-- Components.ActionButton
--
-- The load-bearing assertions here are not the readouts -- they are the four things the
-- component's own header calls out, because each of them fails SILENTLY in game:
--
--   * OnClick must still be the template's, or every button stops working while continuing
--     to size, take the mouse and report as shown.
--   * The slot must be read from the ATTRIBUTE, not a cached field, or a paged bar draws the
--     spell it had before the player changed stance.
--   * Two buttons may address ONE slot (bar 1 page 3 is MultiBarRight's block), so a slot
--     change has to repaint both.
--   * LOCK_ACTIONBAR is the string "0", which is TRUTHY in Lua.
local H = require("harness")

describe("Components.ActionButton", function()
    local host

    local SIZE = 32

    local function build(props)
        props = props or {}
        if props.slot == nil then props.slot = 1 end
        if props.size == nil then props.size = SIZE end
        local b = H.C.ActionButton(props, host)
        -- Anchored explicitly: a component built for a test and never added to a container
        -- has no anchors, so every position inside it is unresolvable.
        local f = b:GetFrame()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        return b
    end

    before_each(function()
        H.setup()
        -- The ActionBars plugin builds twelve buttons at login, so every shared-index and
        -- live-count assertion below would be measuring those too. Switched off here so these
        -- specs describe the component alone; the plugin has its own file.
        H.SuuUI.Plugins:Get("action_bars"):Disable()
        host = H.parent(400, 200)
    end)

    describe("the secure contract", function()
        it("is built from a secure template, so it is protected", function()
            local b = build()
            expect(b:GetFrame():IsProtected()).truthy()
        end)

        it("states type and action as attributes at construction", function()
            local b = build({ slot = 7 })
            local f = b:GetFrame()
            expect(f:GetAttribute("type")).eq("action")
            expect(f:GetAttribute("action")).eq(7)
        end)

        it("leaves OnClick to the template rather than replacing it", function()
            -- The failure this pins is silent: a component that set its own OnClick would
            -- still size, still take the mouse, still report as shown, and never fire an
            -- action. The observable is that the client's handler still runs.
            local b = build({ slot = 7 })
            H.setAction(7, { type = "spell", id = 143 }, { silent = true })
            H.click(b:GetFrame())
            local used = H.getUsedAction()
            expect(used).as("the client's own handler ran").notNil()
            expect(used.slot).eq(7)
        end)

        it("registers for more than left-up, or right-click actions never arrive", function()
            local b = build({ slot = 3 })
            b:GetFrame():SetAttribute("action2", 55)
            H.click(b:GetFrame(), "RightButton")
            expect(H.getUsedAction()).as("a right click reached the client").notNil()
        end)

        it("registers for BOTH press and release, or the client's handler bails", function()
            -- THE BUG THIS PINS, and it shipped. The secure handler compares the `down` flag it is
            -- given against `useOnKeyDown` and returns early when they disagree. Registered for
            -- AnyUp alone on a client that acts on the PRESS, the button had a correct template,
            -- correct attributes, a working tooltip and working drag -- and did nothing at all.
            -- Only reading Blizzard's own button (it carries an OnMouseDown handler) found it.
            local b = build({ slot = 3 })
            local clicks = b:GetFrame()._clickButtons or {}
            local joined = table.concat(clicks, ",")
            expect(joined:find("AnyDown")).as("press registered: " .. joined).notNil()
            expect(joined:find("AnyUp")).as("release registered: " .. joined).notNil()
        end)

        it("acts on the RELEASE when the client is set that way", function()
            H.setAction(3, { type = "spell", id = 143 }, { silent = true })
            local b = build({ slot = 3 })
            expect(b:GetFrame():GetAttribute("useOnKeyDown")).falsy()
            H.clickDown(b:GetFrame())
            expect(H.getUsedAction()).as("the press alone is discarded").isNil()
            H.clickUp(b:GetFrame())
            expect(H.getUsedAction()).as("the release acts").notNil()
        end)

        it("acts on the PRESS when the client is set that way", function()
            -- Read from the client's own CVar so the button agrees with every other action button
            -- on screen. Staged BEFORE construction, because attributes are stated once.
            H.setCVarBool("ActionButtonUseKeyDown", true)
            H.setAction(3, { type = "spell", id = 143 }, { silent = true })
            local b = build({ slot = 3 })
            expect(b:GetFrame():GetAttribute("useOnKeyDown")).truthy()
            H.clickUp(b:GetFrame())
            expect(H.getUsedAction()).as("the release alone is discarded now").isNil()
            H.clickDown(b:GetFrame())
            expect(H.getUsedAction()).as("the press acts").notNil()
        end)

        it("performs exactly ONE action per physical click, either way round", function()
            -- The reason registering both events is safe rather than double-firing. H.click fires a
            -- whole click -- press then release -- and the handler discards whichever half
            -- disagrees with useOnKeyDown, so precisely one gets through.
            for _, keyDown in ipairs({ false, true }) do
                H.setup()
                H.SuuUI.Plugins:Get("action_bars"):Disable()
                host = H.parent(400, 200)
                H.setCVarBool("ActionButtonUseKeyDown", keyDown)
                H.setAction(3, { type = "spell", id = 143 }, { silent = true })
                local b = build({ slot = 3 })
                local spy = H.signalSpy(b, H.S.SIGNALS.CLICKED)
                H.click(b:GetFrame())
                expect(spy.count)
                    .as("one CLICKED with useOnKeyDown=" .. tostring(keyDown)).eq(1)
                expect(H.getUsedAction()).as("and the action fired").notNil()
            end
        end)

        it("emits CLICKED through PostClick, without owning the click", function()
            local b = build({ slot = 1 })
            local spy = H.signalSpy(b, H.S.SIGNALS.CLICKED)
            H.click(b:GetFrame())
            expect(spy.count).eq(1)
            expect(spy:arg(1)).eq("LeftButton")
            expect(H.getUsedAction()).as("and the action still fired").notNil()
        end)

        it("exposes no way to re-point a live button", function()
            -- SetAttribute is refused on a protected frame in combat, so a setter that
            -- re-pointed the slot would be a setter that fails exactly when a player is
            -- fighting. Paging is the secure state driver's job instead.
            local b = build()
            expect(b.SetSlot).isNil()
            expect(b.SetAction).isNil()
        end)

        it("has no SetEnabled, for the same reason UnitClickArea has none", function()
            -- Disabling means dropping mouse input, which the client refuses on a protected
            -- frame in combat. Dependency.Bind's `if target.SetEnabled` guard would pass
            -- while nothing was actually inert.
            local b = build()
            expect(b.SetEnabled).isNil()
        end)
    end)

    describe("reading its slot from the attribute", function()
        it("follows the attribute when a secure snippet re-points it", function()
            -- THE subtle one. Bar 1 pages through six blocks of twelve and the snippet
            -- rewrites `action` inside the secure environment, where Lua never sees the
            -- write. A cached slot would keep drawing the old spell.
            local b = build({ slot = 1 })
            H.setAction(1, { texture = "Interface\\Icons\\A" }, { silent = true })
            H.setAction(61, { texture = "Interface\\Icons\\B" }, { silent = true })
            expect(b:GetSlot()).eq(1)

            b:GetFrame():SetAttribute("action", 61)
            b:Refresh()

            expect(b:GetSlot()).as("read from the attribute").eq(61)
            expect(b._iconComp:GetIcon()).eq("Interface\\Icons\\B")
        end)

        it("re-indexes itself so events for the new slot reach it", function()
            local b = build({ slot = 1 })
            b:GetFrame():SetAttribute("action", 61)
            b:Refresh()
            local internals = H.SuuUI._ActionButtonInternals
            expect(internals.slotWatchers(61)).as("watching the new slot").eq(1)
            expect(internals.slotWatchers(1)).as("and not the old one").eq(0)
        end)
    end)

    describe("the icon", function()
        it("shows the slot's texture", function()
            H.setAction(1, { texture = "Interface\\Icons\\Spell_Fire_FireBolt" }, { silent = true })
            local b = build({ slot = 1 })
            expect(b._iconComp:GetIcon()).eq("Interface\\Icons\\Spell_Fire_FireBolt")
        end)

        it("clears the texture for an empty slot rather than hiding a frame", function()
            -- Hiding a frame inside a protected button is refused in combat, and an action
            -- disappearing mid-fight is the ordinary case, so the hide would fire exactly when
            -- it cannot land. A texture with no file draws nothing and costs no protected call.
            local b = build({ slot = 1 })
            expect(b:HasAction()).falsy()
            expect(b._iconComp:GetIcon()).as("no art").isNil()
            -- Still mouse-enabled: dragging an action ONTO an empty slot is the whole point.
            expect(b:GetFrame():IsMouseEnabled()).as("still takes the mouse").truthy()
        end)

        it("costs no refused call when an action appears during combat", function()
            local b = build({ slot = 4 })
            H.setCombat(true)
            H.resetBlockedActions()
            H.setAction(4, { texture = "Interface\\Icons\\B" })
            expect(#H.getBlockedActions()).as("nothing protected was touched").eq(0)
            expect(b._iconComp:GetIcon()).eq("Interface\\Icons\\B")
        end)

        it("picks the art up when the slot is filled afterwards", function()
            local b = build({ slot = 4 })
            expect(b._iconComp:GetIcon()).isNil()
            H.setAction(4, { texture = "Interface\\Icons\\B" })
            expect(b._iconComp:GetIcon()).as("the event repainted it").eq("Interface\\Icons\\B")
        end)

        it("draws no border of its own", function()
            -- A2 is one glass plate under the whole grid with hairline dividers between
            -- cells; a per-button border would draw a second edge inside the first.
            local b = build()
            expect(b._iconComp._border).falsy()
        end)
    end)

    describe("the cooldown", function()
        it("starts the swipe from the slot's cooldown", function()
            H.setAction(1, {
                texture = "i", cooldownStart = 100, cooldownDuration = 30, cooldownEnable = 1,
            }, { silent = true })
            local b = build({ slot = 1 })
            local start, duration = b._cooldown:GetCooldownTimes()
            expect(duration).as("the swipe is running").gt(0)
        end)

        it("clears the swipe when the cooldown is disabled", function()
            H.setAction(1, {
                texture = "i", cooldownStart = 100, cooldownDuration = 30, cooldownEnable = 0,
            }, { silent = true })
            local b = build({ slot = 1 })
            local _, duration = b._cooldown:GetCooldownTimes()
            expect(duration).as("enable 0 means no swipe").eq(0)
        end)

        it("insets the swipe by the border width, off the cell edge", function()
            -- A child frame draws above every layer of its parent, so a full-bleed cooldown
            -- would paint over the grid's hairline divider at the cell edge.
            local b = build()
            local bw = H.SuuUI.Pixel.Line(H.token("borderWidth") or 1)
            expect(b._cdProps.inset).eq(bw)
            H.expectInside(b._cooldown, b:GetFrame())
        end)
    end)

    describe("the readouts", function()
        it("shows a stack count above one, and nothing at one", function()
            H.setAction(1, { texture = "i", count = 1 }, { silent = true })
            local b = build({ slot = 1 })
            expect(b._countText:IsShown()).as("a single charge is noise").falsy()
            H.setAction(1, { count = 12 })
            expect(b._countText:IsShown()).truthy()
            expect(b._countText:GetText()).eq("12")
        end)

        it("shows a macro's name but never invents one for a spell", function()
            H.setAction(1, { type = "spell", texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            expect(b._macroText:IsShown()).falsy()
            H.setAction(1, { type = "macro", text = "Pull" })
            expect(b._macroText:GetText()).eq("Pull")
            expect(b._macroText:IsShown()).truthy()
        end)

        it("shows the bound key for its binding command", function()
            H.setBinding("ACTIONBUTTON3", "3")
            H.setAction(1, { texture = "i" }, { silent = true })
            local b = build({ slot = 1, binding = "ACTIONBUTTON3" })
            expect(b._hotkeyText:IsShown()).truthy()
            expect(b._hotkeyText:GetText()).eq("3")
        end)

        it("stays blank when its command is unbound", function()
            local b = build({ slot = 1, binding = "ACTIONBUTTON3" })
            expect(b._hotkeyText:IsShown()).falsy()
        end)

        it("re-reads the key on UPDATE_BINDINGS", function()
            local b = build({ slot = 1, binding = "ACTIONBUTTON3" })
            H.setBinding("ACTIONBUTTON3", "F")
            H.fireEvent("UPDATE_BINDINGS")
            expect(b._hotkeyText:GetText()).eq("F")
        end)

        it("abbreviates a modifier binding so it fits the corner of a cell", function()
            local shorten = H.SuuUI._ActionButtonInternals.abbreviateKey
            expect(shorten("SHIFT-1")).eq("S1")
            expect(shorten("CTRL-BUTTON4")).eq("CM4")
            expect(shorten("MOUSEWHEELUP")).eq("WU")
            expect(shorten(nil)).isNil()
        end)

        it("hides each readout when its setting says so", function()
            H.setBinding("ACTIONBUTTON1", "1")
            H.setAction(1, { type = "macro", text = "Pull", count = 5, texture = "i" },
                { silent = true })
            local b = build({ slot = 1, binding = "ACTIONBUTTON1" })
            expect(b._countText:IsShown()).truthy()
            b:SetShowCount(false)
            b:SetShowMacroText(false)
            b:SetShowHotkey(false)
            expect(b._countText:IsShown()).falsy()
            expect(b._macroText:IsShown()).falsy()
            expect(b._hotkeyText:IsShown()).falsy()
        end)

        it("keeps the count and the macro name out of each other's corner", function()
            H.setAction(1, { type = "macro", text = "Pull", count = 5, texture = "i" },
                { silent = true })
            local b = build({ slot = 1 })
            -- The collision AuraIcon shipped once, when a count and a duration shared the
            -- bottom-right corner.
            H.expectNoOverlap({ b._countText, b._macroText })
        end)
    end)

    describe("usable and range states", function()
        it("leaves a usable action untinted", function()
            H.setAction(1, { texture = "i", usable = true }, { silent = true })
            local b = build({ slot = 1 })
            expect(H.vertexColor(b._iconComp._icon)).deepEq({ 1, 1, 1, 1 })
            expect(b._iconComp._icon:IsDesaturated()).falsy()
        end)

        it("desaturates AND dims an action that cannot be used at all", function()
            H.setAction(1, { texture = "i", usable = false }, { silent = true })
            local b = build({ slot = 1 })
            expect(b._iconComp._icon:IsDesaturated()).truthy()
            expect(H.vertexColor(b._iconComp._icon)[4])
                .as("dimmed to the disabled opacity").near(H.token("opacityDisabled"), 0.001)
        end)

        it("desaturates but does NOT dim when only the resource is short", function()
            -- Two distinct states without inventing a colour token. Blizzard tints this
            -- blue; matching that exactly would need a new palette entry.
            H.setAction(1, { texture = "i", usable = true, notEnoughMana = true },
                { silent = true })
            local b = build({ slot = 1 })
            expect(b._iconComp._icon:IsDesaturated()).truthy()
            expect(H.vertexColor(b._iconComp._icon)[4]).as("not dimmed").eq(1)
        end)

        it("tints out of range with the danger colour", function()
            H.setAction(1, { texture = "i", inRange = false }, { silent = true })
            local b = build({ slot = 1 })
            expect(b:IsOutOfRange()).truthy()
            H.expectTokenColor(H.vertexColor(b._iconComp._icon), "colorDanger")
        end)

        it("does NOT paint a self-cast as out of range", function()
            -- IsActionInRange answers nil when range is not a question. Treating that as
            -- out of range would put a red tint on every self buff on the bar.
            H.setAction(1, { texture = "i", inRange = nil }, { silent = true })
            local b = build({ slot = 1 })
            expect(b:IsOutOfRange()).falsy()
            expect(H.vertexColor(b._iconComp._icon)).deepEq({ 1, 1, 1, 1 })
        end)

        it("prefers the range tint over the resource state", function()
            -- Out of range AND unaffordable: walking closer is the next action a player
            -- takes, so that is the reading the button gives.
            H.setAction(1, { texture = "i", usable = false, inRange = false },
                { silent = true })
            local b = build({ slot = 1 })
            H.expectTokenColor(H.vertexColor(b._iconComp._icon), "colorDanger")
            expect(b._iconComp._icon:IsDesaturated()).as("range wins outright").falsy()
        end)

        it("re-reads usability on ACTIONBAR_UPDATE_USABLE", function()
            H.setAction(1, { texture = "i", usable = true }, { silent = true })
            local b = build({ slot = 1 })
            H.setAction(1, { usable = false }, { silent = true })
            H.fireEvent("ACTIONBAR_UPDATE_USABLE")
            expect(b._iconComp._icon:IsDesaturated()).truthy()
        end)

        it("picks range up from the shared ticker, which nothing announces", function()
            H.setAction(1, { texture = "i", inRange = true }, { silent = true })
            local b = build({ slot = 1 })
            expect(b:IsOutOfRange()).falsy()
            H.setAction(1, { inRange = false }, { silent = true })
            -- No event fires when a target walks away, so only the poll can catch it.
            H.tick(H.SuuUI._ActionButtonInternals.rangeThrottle + 0.01)
            expect(b:IsOutOfRange()).as("the ticker caught it").truthy()
        end)
    end)

    describe("the tooltip", function()
        -- Owned by the component rather than left to its owner, and that was learned the hard
        -- way: phase 4a emitted MOUSE_ENTER and left the wiring to callers, so an action bar with
        -- no tooltips at all reached the game. The slot is the whole answer -- SetAction builds
        -- name, cost, range and cast time from it -- so there is nothing for an owner to supply.
        it("points the client's tooltip at the slot on hover", function()
            H.setAction(7, { texture = "i", id = 143 }, { silent = true })
            local b = build({ slot = 7 })
            H.hover(b:GetFrame())
            expect(H.getTooltipState().action).as("pointed at slot 7").eq(7)
            expect(H.env.GameTooltip:GetOwner()).eq(b:GetFrame())
            expect(H.env.GameTooltip:IsShown()).truthy()
        end)

        it("hides it again on leave", function()
            H.setAction(7, { texture = "i" }, { silent = true })
            local b = build({ slot = 7 })
            H.hover(b:GetFrame())
            H.unhover(b:GetFrame())
            expect(H.env.GameTooltip:IsShown()).falsy()
        end)

        it("says nothing about an empty slot", function()
            -- SetAction on an empty slot shows an empty frame rather than nothing at all.
            local b = build({ slot = 7 })
            H.hover(b:GetFrame())
            local t = H.getTooltipState()
            expect(t and t.action).isNil()
            expect(H.env.GameTooltip:IsShown()).falsy()
        end)

        it("follows the slot when a secure snippet re-points the button", function()
            H.setAction(61, { texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            b:GetFrame():SetAttribute("action", 61)
            b:Refresh()
            H.hover(b:GetFrame())
            expect(H.getTooltipState().action).eq(61)
        end)

        it("does not hide a tooltip that now belongs to something else", function()
            -- The player moved onto another frame in the same frame update; hiding here would
            -- take that frame's tooltip away from under it.
            H.setAction(7, { texture = "i" }, { silent = true })
            local b = build({ slot = 7 })
            H.hover(b:GetFrame())
            local other = H.env.CreateFrame("Frame", nil, H.env.UIParent)
            H.env.GameTooltip:SetOwner(other, "ANCHOR_RIGHT")
            H.env.GameTooltip:Show()
            H.unhover(b:GetFrame())
            expect(H.env.GameTooltip:IsShown()).as("left alone").truthy()
        end)

        it("can be turned off", function()
            H.setAction(7, { texture = "i" }, { silent = true })
            local b = build({ slot = 7, tooltip = false })
            H.hover(b:GetFrame())
            local t = H.getTooltipState()
            expect(t and t.action).isNil()
        end)
    end)

    describe("current and auto-repeat", function()
        it("reads both, and deliberately renders neither yet", function()
            -- The "this is active" treatment belongs on the grid's glass plate, which does
            -- not exist until ActionBarGrid. Reading it now keeps the event wiring honest.
            H.setAction(1, { texture = "i", current = true, autoRepeat = true },
                { silent = true })
            local b = build({ slot = 1 })
            expect(b:IsCurrent()).truthy()
            expect(b:IsAutoRepeat()).truthy()
        end)

        it("re-reads them on ACTIONBAR_UPDATE_STATE", function()
            H.setAction(1, { texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            expect(b:IsCurrent()).falsy()
            H.setAction(1, { current = true }, { silent = true })
            H.fireEvent("ACTIONBAR_UPDATE_STATE")
            expect(b:IsCurrent()).truthy()
        end)
    end)

    describe("drag and drop", function()
        it("picks the action up onto the cursor", function()
            H.setAction(1, { type = "spell", id = 143, texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            b:GetFrame():GetScript("OnDragStart")(b:GetFrame(), "LeftButton")
            expect(H.getPickedUpAction()).notNil()
            expect(H.getPickedUpAction().id).eq(143)
            expect(b:HasAction()).as("and the slot emptied").falsy()
        end)

        it("places what the cursor holds", function()
            H.setAction(2, { type = "spell", id = 99, texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            H.env.PickupAction(2)
            b:GetFrame():GetScript("OnReceiveDrag")(b:GetFrame())
            local _, id = H.env.GetActionInfo(1)
            expect(id).eq(99)
        end)

        it("refuses to drag while the bars are LOCKED", function()
            -- LOCK_ACTIONBAR is a CVar-backed plain global, so it is the STRING "0" or "1"
            -- -- and "0" is truthy in Lua. A component testing it for truthiness would
            -- treat unlocked bars as locked and never drag at all.
            H.setAction(1, { type = "spell", id = 143, texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            H.setActionBarLocked(true)
            b:GetFrame():GetScript("OnDragStart")(b:GetFrame(), "LeftButton")
            expect(H.getPickedUpAction()).as("nothing was picked up").isNil()
            expect(b:HasAction()).as("and the slot still holds it").truthy()
        end)

        it("drags when the bars are unlocked, which is the default", function()
            expect(H.env.LOCK_ACTIONBAR).as("the string, not a boolean").eq("0")
            H.setAction(1, { type = "spell", id = 143, texture = "i" }, { silent = true })
            local b = build({ slot = 1 })
            b:GetFrame():GetScript("OnDragStart")(b:GetFrame(), "LeftButton")
            expect(H.getPickedUpAction()).notNil()
        end)
    end)

    describe("two buttons on one slot", function()
        it("repaints BOTH when the slot changes", function()
            -- Measured, not hypothetical: bar 1's page 3 is exactly MultiBarRight's block, so
            -- a paged bar 1 and a fixed bar 3 legitimately address one slot at once. A
            -- slot -> single button map would repaint whichever was found first and leave the
            -- other showing a stale spell.
            local a = build({ slot = 25 })
            local b = H.C.ActionButton({ slot = 25, size = SIZE }, host)
            b:GetFrame():SetPoint("TOPLEFT", host, "TOPLEFT", SIZE, 0)

            expect(H.SuuUI._ActionButtonInternals.slotWatchers(25)).eq(2)
            H.setAction(25, { texture = "Interface\\Icons\\Shared" })
            expect(a._iconComp:GetIcon()).eq("Interface\\Icons\\Shared")
            expect(b._iconComp:GetIcon()).as("the second one too").eq("Interface\\Icons\\Shared")
            b:Destroy()
        end)
    end)

    describe("the shared infrastructure", function()
        it("uses one event frame for every button, not one each", function()
            local first = build({ slot = 1 })
            local frame = H.SuuUI._ActionButtonInternals.eventFrame()
            local second = H.C.ActionButton({ slot = 2, size = SIZE }, host)
            expect(H.SuuUI._ActionButtonInternals.eventFrame())
                .as("the same frame").eq(frame)
            expect(H.SuuUI._ActionButtonInternals.liveCount()).eq(2)
            second:Destroy()
        end)

        it("runs one range ticker, and stops it when the last button goes", function()
            local b = build({ slot = 1 })
            expect(H.SuuUI._ActionButtonInternals.hasTicker()).truthy()
            b:Destroy()
            expect(H.SuuUI._ActionButtonInternals.hasTicker())
                .as("no OnUpdate left running for nobody").falsy()
            expect(H.SuuUI._ActionButtonInternals.liveCount()).eq(0)
        end)

        it("stops dispatching to a destroyed button", function()
            local b = build({ slot = 1 })
            b:Destroy()
            expect(H.SuuUI._ActionButtonInternals.slotWatchers(1)).eq(0)
            -- Would raise on a dropped handle if it were still indexed.
            expect(function() H.setAction(1, { texture = "i" }) end).notThrows()
        end)

        it("re-indexes every button on a page change before repainting", function()
            local b = build({ slot = 1 })
            H.setAction(37, { texture = "Interface\\Icons\\Paged" }, { silent = true })
            -- What the secure snippet does, from outside the secure environment.
            b:GetFrame():SetAttribute("action", 37)
            H.setActionBarPage(4)
            expect(b:GetSlot()).eq(37)
            expect(b._iconComp:GetIcon()).eq("Interface\\Icons\\Paged")
            expect(H.SuuUI._ActionButtonInternals.slotWatchers(37)).eq(1)
        end)
    end)

    -- The remaining cooldown as a NUMBER on the button.
    --
    -- The load-bearing case here is the global cooldown, and it needs TWO assertions rather than
    -- one. "No number is drawn" alone cannot distinguish the design -- a button filtered out before
    -- it ever joins the ticker -- from a button sitting on the ticker ten times a second deciding to
    -- draw nothing. Only the membership count separates them, which is why the internals expose it.
    describe("the cooldown countdown", function()
        local function internals() return H.SuuUI._ActionButtonInternals end

        -- The clock starts at 0, so a cooldown staged from 0 has its whole duration left.
        local function cooling(duration, opts)
            opts = opts or {}
            H.setAction(1, {
                cooldownStart    = opts.start or 0,
                cooldownDuration = duration,
            }, { silent = true })
            return build()
        end

        -- One throttle period, so the shared ticker actually fires.
        local function tickOnce()
            H.tick(internals().rangeThrottle + 0.001)
        end

        it("draws the remaining time for an ability with a real cooldown", function()
            local b = cooling(6)
            expect(b._cooldownText:IsShown()).as("a real cooldown carries a number").truthy()
            expect(b._cooldownText:GetText()).eq(H.SuuUI.Readout.Duration(6))
        end)

        it("spells it through the SHARED formatter, not one of its own", function()
            -- The whole reason Readout.Duration exists: an aura band and a cooling button sit
            -- inches apart and must not disagree about how to say "45 seconds".
            local b = cooling(45)
            expect(b._cooldownText:GetText()).eq("45s")
            expect(b._cooldownText:GetText()).eq(H.SuuUI.Readout.Duration(45))
        end)

        it("draws NO number for a cooldown that is only the global cooldown", function()
            local b = cooling(internals().gcdMaxDuration)
            expect(b._cooldownText:IsShown())
                .as("the GCD is what a player asked NOT to see counted").falsy()
        end)

        it("keeps a GCD off the ticker entirely rather than walking it to draw nothing", function()
            local b = cooling(internals().gcdMaxDuration)
            expect(internals().onCooldownCount())
                .as("filtered before it joins, not after").eq(0)
            -- And the discriminating half: a real cooldown DOES join, so the count above is a
            -- statement about the filter rather than about the set never being used.
            H.setAction(1, { cooldownDuration = 6 }, { silent = true })
            b:Refresh()
            expect(internals().onCooldownCount()).eq(1)
        end)

        it("still sweeps for the GCD -- the swipe and the number disagree on purpose", function()
            local b = cooling(internals().gcdMaxDuration)
            expect(b._cooldown._cdDuration)
                .as("a bar-wide sweep is how 'briefly unavailable' reads").eq(1.5)
            expect(b._cooldownText:IsShown()).falsy()
        end)

        it("counts down on the shared ticker", function()
            local b = cooling(30)
            expect(b._cooldownText:GetText()).eq("30s")
            -- One tick, not two: H.tick advances the clock AND runs the OnUpdate, so a second
            -- call would move the clock again and the expected string with it.
            H.tick(5)
            expect(b._cooldownText:GetText()).eq("25s")
        end)

        it("switches to tenths below one second, FLOORED rather than rounded", function()
            local b = cooling(6)
            H.tick(5.75)
            -- 0.25s left. Rounding would print "0.3s" and claim time that has already gone.
            expect(b._cooldownText:GetText()).eq("0.2s")
        end)

        it("clears the number AND retires the button when the cooldown expires", function()
            local b = cooling(6)
            expect(internals().onCooldownCount()).eq(1)
            H.tick(6)
            tickOnce()
            expect(b._cooldownText:IsShown()).as("nothing left to count").falsy()
            -- The client announces a cooldown STARTING and not reliably its finishing, so if the
            -- expiry did not retire the button nothing else ever would.
            expect(internals().onCooldownCount())
                .as("expired buttons leave the walked set").eq(0)
        end)

        it("draws nothing for an empty slot", function()
            H.clearAction(1, { silent = true })
            local b = build()
            expect(b._cooldownText:IsShown()).falsy()
            expect(internals().onCooldownCount()).eq(0)
        end)

        it("draws nothing when the client reports the cooldown as not running", function()
            H.setAction(1, {
                cooldownStart = 0, cooldownDuration = 6, cooldownEnable = 0,
            }, { silent = true })
            local b = build()
            expect(b._cooldownText:IsShown()).falsy()
            expect(internals().onCooldownCount()).eq(0)
        end)

        describe("the toggle", function()
            it("is on by default", function()
                expect(build()._showCooldownText).truthy()
            end)

            it("draws nothing when the prop is off", function()
                H.setAction(1, { cooldownDuration = 6 }, { silent = true })
                local b = build({ showCooldownText = false })
                expect(b._cooldownText:IsShown()).falsy()
            end)

            it("shows the number again when switched on MID-cooldown", function()
                -- Why the window is tracked while the readout is off: switching it back on has to
                -- show what is running now, not stay blank until some later cooldown starts.
                H.setAction(1, { cooldownDuration = 30 }, { silent = true })
                local b = build({ showCooldownText = false })
                expect(b._cooldownText:IsShown()).falsy()
                expect(internals().onCooldownCount())
                    .as("tracked even with nothing drawn").eq(1)
                b:SetShowCooldownText(true)
                expect(b._cooldownText:IsShown()).as("the window was still being tracked").truthy()
                expect(b._cooldownText:GetText()).eq("30s")
            end)

            it("retires an expired cooldown even while the readout is off", function()
                -- This is what the toggle check being AFTER the expiry branch buys, and it is the
                -- only observable difference: nothing is drawn either way, but a button whose
                -- cooldown has finished must stop being walked. A mutation moving the check to the
                -- top of _paintCooldownText survived until this assertion existed.
                H.setAction(1, { cooldownDuration = 6 }, { silent = true })
                build({ showCooldownText = false })
                expect(internals().onCooldownCount()).eq(1)
                H.tick(6)
                expect(internals().onCooldownCount())
                    .as("expired, so it leaves the set regardless of the readout").eq(0)
            end)

            it("hides the number without stopping the countdown underneath", function()
                H.setAction(1, { cooldownDuration = 30 }, { silent = true })
                local b = build()
                b:SetShowCooldownText(false)
                H.tick(5)
                b:SetShowCooldownText(true)
                expect(b._cooldownText:GetText())
                    .as("it resumes at the real remaining time").eq("25s")
            end)
        end)

        describe("where it sits", function()
            -- Full 2D test. H.box's `top` measures DOWN from the screen top, so a frame lower on
            -- screen has the LARGER top -- reading it as a bottom-up coordinate inverts this.
            local function overlaps(a, b)
                return a.right > b.left and a.left < b.right
                   and a.bottom > b.top and a.top < b.bottom
            end

            it("is centred on the button and inside it", function()
                local b = cooling(30)
                local f = b:GetFrame()
                H.expectCenteredV(b._cooldownText:GetFrame(), f)
                H.expectInside(b._cooldownText:GetFrame(), f)
            end)

            it("is not clipped by the button", function()
                local b = cooling(30)
                H.expectTextNotClipped(b._cooldownText:GetFrame())
            end)

            -- PINNED, NOT FIXED. At the default 32-unit button a centred number overlaps BOTH
            -- right-hand corner readouts by about two units. This is the same tension AuraIcon's
            -- own spec pins: the readouts take fontSizeSm, whose line height does not scale with
            -- the button, so a centred one and a cornered one cannot be disjoint inside a small
            -- box. Both cases are reachable in ordinary play -- a stack of potions on a cooldown
            -- is the count case, and every bound button is the hotkey case -- so this records
            -- today's geometry rather than leaving someone to rediscover it.
            it("CAN collide with the corner readouts at the default button size", function()
                H.setAction(1, { cooldownDuration = 18, count = 5 }, { silent = true })
                H.setBinding("ACTIONBUTTON1", "Q")
                local b = build({ size = 32, binding = "ACTIONBUTTON1" })
                local cd = H.box(b._cooldownText:GetFrame())
                expect(overlaps(cd, H.box(b._countText:GetFrame())))
                    .as("count, bottom-right; see the xit below").truthy()
                expect(overlaps(cd, H.box(b._hotkeyText:GetFrame())))
                    .as("hotkey, top-right; see the xit below").truthy()
            end)

            it("is clear of both corners once the button is large enough", function()
                -- Which is also the player-facing answer today: the Button Size slider resolves
                -- it, because the corners move apart while the font does not grow with them.
                H.setAction(1, { cooldownDuration = 18, count = 5 }, { silent = true })
                H.setBinding("ACTIONBUTTON1", "Q")
                local b = build({ size = 48, binding = "ACTIONBUTTON1" })
                H.expectNoOverlap({
                    b._cooldownText:GetFrame(),
                    b._countText:GetFrame(),
                    b._hotkeyText:GetFrame(),
                })
            end)

            xit("keeps the number clear of the corner readouts at every button size", function()
                -- Undecided, and each route costs something real:
                --   * Inset the number's edges by the corner readouts' widths, the way
                --     _reserveCountColumn already does for the macro name. Cheapest, but it makes
                --     a "centred" readout visibly off-centre on exactly the buttons that carry a
                --     stack or a bound key -- which is most of them.
                --   * Hide the corner readouts while a number is showing. Loses information a
                --     player uses, and the hotkey is the one they can least afford to lose.
                --   * Size the readouts from the BUTTON rather than from fontSizeSm, so all three
                --     shrink together. Correct-looking, but it takes the readouts off the theme's
                --     font-size tokens, which every other text in the addon follows.
                -- Wants Domenik's call on which cost is acceptable.
            end)
        end)

        it("leaves the walked set on teardown", function()
            local b = cooling(6)
            expect(internals().onCooldownCount()).eq(1)
            b:Destroy()
            expect(internals().onCooldownCount())
                .as("a destroyed handle must not be walked by the ticker").eq(0)
        end)
    end)

    describe("teardown", function()
        it("drops its theme subscription", function()
            local b = build()
            b:Destroy()
            expect(function() H.T:SetActive("Default") end).notThrows()
        end)

        it("leaves its attributes alone", function()
            -- Clearing an attribute on a protected frame is one more call the client can
            -- refuse, and the frame is about to be dropped anyway.
            local b = build({ slot = 9 })
            local f = b:GetFrame()
            b:Destroy()
            expect(f:GetAttribute("action")).eq(9)
        end)
    end)
end)

-- kind = "pet".
--
-- A pet button is the SAME secure mechanism as an action slot -- `SecureActionButtonTemplate` with
-- `type="pet"` and the slot index in the `action` attribute, which is what LibActionButton does
-- inside a live secure snippet on this client. That shared mechanism is the whole reason pet is a
-- `kind` here rather than a component of its own: the press-versus-release gate was got wrong once
-- and produced a button that looked perfect and did nothing, so it exists in exactly one place.
--
-- These specs were written after a mutation pass: the provider had been smoke-tested by hand and had
-- NO spec coverage at all, so eleven separate faults in it went undetected.
describe("Components.ActionButton kind=pet", function()
    local host
    local SIZE = 32

    local function pet(slot, props)
        props = props or {}
        props.kind = "pet"
        props.slot = slot or 1
        props.size = props.size or SIZE
        local b = H.C.ActionButton(props, host)
        b:GetFrame():SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        return b
    end

    before_each(function()
        H.setup()
        H.SuuUI.Plugins:Get("action_bars"):Disable()
        host = H.parent(400, 200)
        H.setPetActionBar(true, { silent = true })
        H.setPetAction(1, { name = "Attack", texture = "tex1", isActive = true }, { silent = true })
        H.setPetAction(2, { name = "Firebolt", texture = "tex2",
            autoCastAllowed = true, autoCastEnabled = true }, { silent = true })
    end)

    describe("the secure mechanism", function()
        it("states type=pet with the slot in the SAME action attribute", function()
            -- Same attribute name as an action slot, which is why _slotNow needs no branch and why
            -- the paging machinery keeps working untouched.
            local b = pet(2)
            expect(b:GetFrame():GetAttribute("type")).eq("pet")
            expect(b:GetFrame():GetAttribute("action")).eq(2)
        end)

        it("refuses an unknown kind rather than silently building an action button", function()
            expect(function() H.C.ActionButton({ kind = "banana", slot = 1, size = 32 }, host) end)
                .throws("unknown kind")
        end)

        it("does NOT register drag, because a pet slot is not the player's to rearrange", function()
            -- LibActionButton excludes pet from its drag path for the same reason.
            expect(pet(1):GetFrame()._dragButtons).isNil()
            expect(H.C.ActionButton({ slot = 1, size = SIZE }, host):GetFrame()._dragButtons)
                .as("an action button still drags").notNil()
        end)

        it("answers HasAction from the pet data, not the action slots", function()
            -- The public accessor, which was reading the action global while every painter went
            -- through the provider -- caught by a smoke test, not by a spec.
            expect(pet(1):HasAction()).truthy()
            expect(pet(9):HasAction()).as("slot 9 is unstaged").falsy()
        end)
    end)

    describe("the isToken trap", function()
        it("resolves name and texture through _G when isToken is set", function()
            -- With isToken true the client hands back the NAMES OF GLOBALS, not a path and a label.
            -- Missing this draws blank icons on exactly the commands that are tokens -- Attack,
            -- Follow, Stay -- which is the most commonly missed detail in a pet bar.
            H.env.SUUUI_TEST_PET_TEX = "Interface\\Icons\\RESOLVED"
            H.setPetAction(3, { name = "SUUUI_TEST_PET_NAME", texture = "SUUUI_TEST_PET_TEX",
                isToken = true }, { silent = true })
            expect(pet(3)._iconComp:GetIcon()).eq("Interface\\Icons\\RESOLVED")
        end)

        it("uses the texture directly when isToken is not set", function()
            expect(pet(1)._iconComp:GetIcon()).eq("tex1")
        end)
    end)

    describe("usability", function()
        it("greys EVERY icon when the pet's bar is unusable at all", function()
            -- Two mechanisms that must not be collapsed: a pet whose bar is unusable greys
            -- everything, while a single unusable slot greys only itself.
            local b = pet(1)
            expect(b._usable).truthy()
            H.setPetActionBar(false)
            expect(b._usable).as("the whole bar went unusable").falsy()
        end)

        it("greys one slot when only that slot is unusable", function()
            H.setPetAction(1, { usable = false })
            expect(pet(1)._usable).falsy()
            expect(pet(2)._usable).as("its neighbour is fine").truthy()
        end)
    end)

    describe("current action", function()
        it("shows an active command as current", function()
            expect(pet(1):IsCurrent()).truthy()
        end)

        it("EXCLUDES Follow, which the client reports active almost always", function()
            -- Otherwise that button is permanently lit and stops meaning anything.
            H.setPetAction(4, { name = "PET_ACTION_FOLLOW", texture = "t", isActive = true },
                { silent = true })
            expect(pet(4):IsCurrent()).falsy()
        end)

        it("never reports auto-repeat, which is an action-slot concept", function()
            expect(pet(1):IsAutoRepeat()).falsy()
        end)
    end)

    describe("the active state -- a pet's MODE", function()
        -- Passive, Defensive and Aggressive are reported as the slot being ACTIVE. The component
        -- always tracked that and never DREW it, so a player could not tell which mode their pet was
        -- in -- reported in game after the bar was otherwise working.

        it("marks the active mode and only that one", function()
            H.setPetAction(6, { name = "PET_MODE_PASSIVE", texture = "t", isToken = true },
                { silent = true })
            H.setPetAction(7, { name = "PET_MODE_DEFENSIVE", texture = "t", isToken = true,
                isActive = true }, { silent = true })
            local passive, defensive = pet(6), pet(7)
            expect(defensive._currentBar:IsShown()).as("defensive is on").truthy()
            expect(passive._currentBar:IsShown()).falsy()
        end)

        it("moves the mark when the mode changes", function()
            H.setPetAction(6, { name = "PET_MODE_PASSIVE", texture = "t", isToken = true },
                { silent = true })
            H.setPetAction(7, { name = "PET_MODE_DEFENSIVE", texture = "t", isToken = true,
                isActive = true }, { silent = true })
            local passive, defensive = pet(6), pet(7)
            H.setPetAction(7, { isActive = false }, { silent = true })
            H.setPetAction(6, { isActive = true })
            expect(passive._currentBar:IsShown()).as("switched to passive").truthy()
            expect(defensive._currentBar:IsShown()).as("and cleared defensive").falsy()
        end)

        it("draws it in the accent colour", function()
            H.setPetAction(6, { name = "PET_MODE_PASSIVE", texture = "t", isToken = true,
                isActive = true }, { silent = true })
            local r, g, b = pet(6)._currentBar:GetColorTexture()
            local c = H.token("colorAccent")
            expect({ r, g, b }).deepEq({ c[1], c[2], c[3] })
        end)

        it("uses a DIFFERENT channel from autocast, so both can be read at once", function()
            -- The overlay border is the autocast ring; the bar is the active state. Two states through
            -- one channel could not be told apart, which is the whole reason this is an edge bar.
            H.setPetAction(6, { name = "Firebolt", texture = "t", isActive = true,
                autoCastAllowed = true, autoCastEnabled = true }, { silent = true })
            local b = pet(6)
            expect(b._currentBar:IsShown()).as("active").truthy()
            -- DIFFERENT COLOURS, not just different shapes: gold for autocast, accent for the active
            -- state. A player could not tell them apart when both were accent.
            H.expectTokenColor(H.borderColor(b._overlay), "colorWarning")
            local r, g, bl = b._currentBar:GetColorTexture()
            local acc = H.token("colorAccent")
            expect({ r, g, bl }).as("the mode bar stays accent").deepEq({ acc[1], acc[2], acc[3] })
        end)

        it("does NOT mark Follow, which the client reports active almost always", function()
            H.setPetAction(6, { name = "PET_ACTION_FOLLOW", texture = "t", isToken = true,
                isActive = true }, { silent = true })
            expect(pet(6)._currentBar:IsShown()).falsy()
        end)

        it("clears the mark when the slot empties", function()
            -- The early return in _readState has to repaint too, or a marked button keeps its bar
            -- after the command behind it goes away.
            H.setPetAction(6, { name = "Growl", texture = "t", isActive = true }, { silent = true })
            local b = pet(6)
            expect(b._currentBar:IsShown()).truthy()
            H.clearPetAction(6)
            expect(b._currentBar:IsShown()).as("no stale mark on an empty slot").falsy()
        end)

        it("has a real height, or it draws nothing at all", function()
            -- A zero-height texture is shown and invisible, which is the failure mode that looks like
            -- "the indicator does not work" while every state assertion passes.
            H.setPetAction(6, { name = "Growl", texture = "t", isActive = true }, { silent = true })
            expect(pet(6)._currentBar:GetHeight()).gt(0)
        end)

        it("re-resolves its colour on a theme change", function()
            H.setPetAction(6, { name = "Growl", texture = "t", isActive = true }, { silent = true })
            local b = pet(6)
            -- Cleared behind the component's back, so only ApplyTheme can put it right.
            b._currentBar:SetColorTexture(0, 0, 0, 0)
            b:ApplyTheme()
            local r, g, bl = b._currentBar:GetColorTexture()
            local c = H.token("colorAccent")
            expect({ r, g, bl }).deepEq({ c[1], c[2], c[3] })
        end)

        it("marks a channelling ACTION slot too, since it is the same state", function()
            -- Same mechanism on bars 1-8: a channelled spell or a live aura. One code path.
            local a = H.C.ActionButton({ slot = 1, size = SIZE }, host)
            a:GetFrame():SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            expect(a._currentBar:IsShown()).falsy()
            H.setAction(1, { id = 5, current = true }, { silent = true })
            a:Refresh()
            expect(a._currentBar:IsShown()).truthy()
        end)
    end)

    describe("cooldown", function()
        it("paints a pet cooldown even though the client sends only two values", function()
            -- GetPetActionCooldown returns start and duration; the provider supplies the third
            -- so the shared painter's enable check reads as running.
            H.setPetAction(1, { cooldownStart = 500, cooldownDuration = 30 }, { silent = true })
            local b = pet(1)
            expect(b._cooldown._cdStart).eq(500)
            expect(b._cooldown._cdDuration).eq(30)
        end)

        it("counts a pet ability's cooldown down as a number too", function()
            -- The kind seam earns its keep here: the countdown is written once, on the shared
            -- provider path, so a pet command gets it without a line of pet-specific code.
            H.setPetAction(1, { cooldownStart = 0, cooldownDuration = 20 }, { silent = true })
            local b = pet(1)
            expect(b._cooldownText:IsShown()).truthy()
            expect(b._cooldownText:GetText()).eq("20s")
        end)

        it("draws no number for a pet ability sitting on the global cooldown", function()
            H.setPetAction(1, { cooldownStart = 0, cooldownDuration = 1.5 }, { silent = true })
            local b = pet(1)
            expect(b._cooldownText:IsShown()).falsy()
        end)
    end)


    describe("autocast", function()
        it("rings a command that IS autocasting", function()
            H.expectTokenColor(H.borderColor(pet(2)._overlay), "colorWarning")
        end)

        it("does NOT ring one that merely COULD autocast", function()
            -- autoCastAllowed is true of most commands and would light half the bar. What a player
            -- needs to see is which ones actually are.
            H.setPetAction(5, { name = "Bite", texture = "t", autoCastAllowed = true },
                { silent = true })
            expect(H.borderColor(pet(5)._overlay)).deepEq({ 0, 0, 0, 0 })
        end)

        it("clears the ring when autocast is switched off", function()
            local b = pet(2)
            H.expectTokenColor(H.borderColor(b._overlay), "colorWarning")
            H.env.TogglePetAutocast(2)
            expect(H.borderColor(b._overlay)).deepEq({ 0, 0, 0, 0 })
        end)

        it("TOGGLES on right-click, by FORWARDING into Blizzard's own button", function()
            -- `TogglePetAutocast` is PROTECTED. Calling it from a PostClick hook -- which does run in
            -- a hardware-event context -- raised "SuuUI has been blocked from an action only
            -- available to the Blizzard UI" in game. The only legitimate route is to let the CLIENT
            -- press Blizzard's own pet button, whose handler is trusted: `type2 = "click"` plus
            -- `clickbutton2`. Same mechanism Clique uses for click-casting.
            local b = pet(5)
            H.setPetAction(5, { name = "Bite", texture = "t", autoCastAllowed = true })
            expect(b:GetFrame():GetAttribute("type2")).eq("click")
            expect(b:GetFrame():GetAttribute("clickbutton2"))
                .as("points at Blizzard's own button").eq(H.env.PetActionButton5)

            local function enabled()
                local _, _, _, _, _, e = H.env.GetPetActionInfo(5)
                return e
            end
            expect(enabled()).falsy()
            H.click(b:GetFrame(), "RightButton")
            expect(enabled()).as("switched on").truthy()
            H.expectTokenColor(H.borderColor(b._overlay), "colorWarning")
            H.click(b:GetFrame(), "RightButton")
            expect(enabled()).as("and back off").falsy()
        end)

        it("toggles ONCE per physical right-click, not twice", function()
            -- The bug this cost a round to find. With both click phases registered, one physical
            -- click runs the secure handler TWICE, forwards twice, and toggles straight back -- a
            -- right-click that visibly does nothing. A pet button registers ONE phase.
            local b = pet(5)
            H.setPetAction(5, { name = "Bite", texture = "t", autoCastAllowed = true })
            H.click(b:GetFrame(), "RightButton")
            expect(H.getPetAutocastToggles()).as("exactly one toggle").len(1)
        end)

        it("registers one click phase for pet and two for an action slot", function()
            expect(pet(1):GetFrame()._clickButtons).len(1)
            local a = H.C.ActionButton({ slot = 1, size = SIZE }, host)
            expect(a:GetFrame()._clickButtons).as("an action button still honours the CVar").len(2)
        end)

        it("STATES the release phase, so registration and useOnKeyDown agree", function()
            -- THE INVARIANT THIS COMPONENT HAS NOW BROKEN TWICE.
            --
            -- Phase 3: registered AnyUp only while useOnKeyDown came from the CVar, which said "act
            --          on the press" -- so every action button looked perfect and did nothing.
            -- Phase 6: the identical mistake on pet buttons. Both mouse buttons stopped working.
            --
            -- A one-phase button must STATE the phase it registered rather than read a preference it
            -- cannot honour.
            expect(pet(1):GetFrame():GetAttribute("useOnKeyDown"))
                .as("release, matching AnyUp").falsy()
        end)

        it("works on BOTH mouse buttons whichever way the client's CVar is set", function()
            -- The regression test proper. With the CVar on, the client wants the press; a pet button
            -- registers only the release, so it must not be reading that CVar.
            for _, keyDown in ipairs({ true, false }) do
                H.setup()
                H.setCVarBool("ActionButtonUseKeyDown", keyDown)
                H.SuuUI.Plugins:Get("action_bars"):Disable()
                host = H.parent(400, 200)
                H.setPetActionBar(true, { silent = true })
                H.setPetAction(1, { name = "Firebolt", texture = "t", autoCastAllowed = true },
                    { silent = true })
                local b = pet(1)

                H.click(b:GetFrame(), "LeftButton")
                expect(H.getUsedPetAction())
                    .as("left-click cast, CVar keyDown=" .. tostring(keyDown)).notNil()

                H.click(b:GetFrame(), "RightButton")
                expect(H.getPetAutocastToggles())
                    .as("right-click toggled exactly once, CVar keyDown=" .. tostring(keyDown)).len(1)
            end
        end)

        it("does NOT reach the pet-cast path on a right-click", function()
            -- type2 overrides the type for button 2, so one click does one thing rather than both
            -- toggling autocast and ordering the pet about.
            local b = pet(2)
            H.click(b:GetFrame(), "RightButton")
            expect(H.getUsedPetAction()).as("no cast on right-click").isNil()
            H.click(b:GetFrame(), "LeftButton")
            expect(H.getUsedPetAction().slot).as("but left-click casts").eq(2)
        end)

        it("leaves the forward unset when Blizzard's button is absent", function()
            -- A client that does not ship PetActionButtonN must not take the bar down; the cast still
            -- works and only the autocast toggle is unavailable.
            H.env.PetActionButton7 = nil
            local b = pet(7)
            expect(b:GetFrame():GetAttribute("type2")).isNil()
        end)

        it("leaves an action button with no ring at all", function()
            local a = H.C.ActionButton({ slot = 1, size = SIZE }, host)
            expect(H.borderColor(a._overlay)).deepEq({ 0, 0, 0, 0 })
        end)
    end)

    describe("events", function()
        it("repaints on PET_BAR_UPDATE", function()
            local b = pet(1)
            H.setPetAction(1, { texture = "changed" })
            expect(b._iconComp:GetIcon()).eq("changed")
        end)

        it("filters UNIT_PET on player and UNIT_FLAGS on pet, not the reverse", function()
            -- Getting these the wrong way round silently kills every update. The client sends
            -- UNIT_PET for "player" and UNIT_FLAGS for "pet".
            local b = pet(1)
            H.setPetAction(1, { texture = "a" }, { silent = true })
            H.fireEvent("UNIT_PET", "pet")
            expect(b._iconComp:GetIcon()).as("wrong unit, ignored").eq("tex1")
            H.fireEvent("UNIT_PET", "player")
            expect(b._iconComp:GetIcon()).as("right unit, repainted").eq("a")

            H.setPetAction(1, { texture = "b" }, { silent = true })
            H.fireEvent("UNIT_FLAGS", "player")
            expect(b._iconComp:GetIcon()).as("wrong unit, ignored").eq("a")
            H.fireEvent("UNIT_FLAGS", "pet")
            expect(b._iconComp:GetIcon()).as("right unit, repainted").eq("b")
        end)

        it("does NOT repaint action buttons on a pet event", function()
            -- One shared event frame is right; refreshing all ninety-six action buttons every time a
            -- hunter's pet does anything is not.
            local a = H.C.ActionButton({ slot = 1, size = SIZE }, host)
            H.setAction(1, { texture = "Interface\\Icons\\ORIGINAL" }, { silent = true })
            a:Refresh()
            H.setAction(1, { texture = "Interface\\Icons\\CHANGED" }, { silent = true })
            H.fireEvent("PET_BAR_UPDATE")
            expect(a._iconComp:GetIcon())
                .as("the action button was left alone").eq("Interface\\Icons\\ORIGINAL")
        end)
    end)
end)
