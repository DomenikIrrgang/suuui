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
        H.SuuUI.Settings:Set("action_bars", "enabled", false)
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
                H.SuuUI.Settings:Set("action_bars", "enabled", false)
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
            H.expectNoOverlap(b._countText, b._macroText)
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
