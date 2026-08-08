local H = require("harness")

-- Occlusion coverage.
--
-- The harness delivers H.click straight to the widget you name, so a frame can be
-- completely buried under another and still pass a click test. That is the blind spot
-- that let the player frame draw over the settings window: every geometry and signal
-- assertion passed while the real client sent the click to the wrong frame. These specs
-- cover the hit-test helpers that close it, and then use them on the layer system itself.
describe("harness hit testing", function()
    local host

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
    end)

    local function panel(w, h, x, y, layer, parent)
        local f = H.env.CreateFrame("Frame", nil, parent or host)
        f:SetSize(w, h)
        f:EnableMouse(true)
        if layer then H.SuuUI.UIRoot:SetLayer(f, layer) end
        local box = H.SuuUI.Layout:CreateContainer({ host = parent or host, layout = "anchor" })
        box:Add(f, { anchor = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = x, y = -y } })
        return f
    end

    describe("topmostAt", function()
        it("returns the frame under the point", function()
            local f = panel(100, 50, 10, 10)
            local cx, cy = H.centerPoint(f)
            expect(H.topmostAt(cx, cy)).eq(f)
        end)

        it("returns nothing outside every frame", function()
            panel(20, 20, 0, 0)
            -- Far outside the 20x20 panel, and outside the 400x300 host
            expect(H.topmostAt(390, 290)).isNil()
        end)

        it("ignores frames that are not mouse-enabled", function()
            local f = panel(100, 50, 10, 10)
            f:EnableMouse(false)
            local cx, cy = H.centerPoint(f)
            expect(H.topmostAt(cx, cy)).neq(f)
        end)

        it("ignores hidden frames", function()
            local f = panel(100, 50, 10, 10)
            local cx, cy = H.centerPoint(f)
            f:Hide()
            expect(H.topmostAt(cx, cy)).neq(f)
        end)

        it("ignores a shown frame whose parent is hidden", function()
            local outer = panel(200, 120, 10, 10)
            local inner = panel(60, 40, 0, 0, nil, outer)
            local cx, cy = H.centerPoint(inner)
            expect(H.topmostAt(cx, cy)).eq(inner)
            outer:Hide()
            -- The child is still "shown" in its own right; the client hides the subtree.
            expect(inner:IsShown()).eq(true)
            expect(H.topmostAt(cx, cy)).neq(inner)
        end)
    end)

    describe("z-order resolution", function()
        it("prefers the higher strata regardless of creation order", function()
            local low  = panel(200, 200, 0, 0, "normal")
            local high = panel(200, 200, 0, 0, "dialog")
            local cx, cy = H.centerPoint(low)
            expect(H.topmostAt(cx, cy)).eq(high)
        end)

        it("prefers the higher frame level inside one strata", function()
            local under = panel(200, 200, 0, 0, "normal")
            local over  = panel(200, 200, 0, 0, "normal")
            H.SuuUI.UIRoot:RaiseAbove(over, under, 3)
            local cx, cy = H.centerPoint(under)
            expect(H.topmostAt(cx, cy)).eq(over)
        end)

        it("does not let a lower strata win on frame level alone", function()
            local high = panel(200, 200, 0, 0, "dialog")
            local low  = panel(200, 200, 0, 0, "normal")
            low:SetFrameLevel(high:GetFrameLevel() + 50)
            local cx, cy = H.centerPoint(high)
            expect(H.topmostAt(cx, cy)).eq(high)
        end)
    end)

    describe("expectClickable / expectOccludes", function()
        it("passes for an unobstructed frame", function()
            local f = panel(100, 50, 10, 10)
            H.expectClickable(f)
        end)

        it("fails when another frame covers it", function()
            local under = panel(200, 200, 0, 0, "normal")
            panel(200, 200, 0, 0, "dialog")
            expect(function() H.expectClickable(under) end).throws()
        end)

        it("fails for a frame that is not mouse-enabled", function()
            local f = panel(100, 50, 10, 10)
            f:EnableMouse(false)
            expect(function() H.expectClickable(f) end).throws()
        end)

        it("expectOccludes passes when the cover is really on top", function()
            local under = panel(200, 200, 0, 0, "normal")
            local over  = panel(200, 200, 0, 0, "dialog")
            H.expectOccludes(over, under)
        end)

        it("expectOccludes fails when the 'cover' is below", function()
            local under = panel(200, 200, 0, 0, "dialog")
            local over  = panel(200, 200, 0, 0, "normal")
            expect(function() H.expectOccludes(over, under) end).throws()
        end)

        it("a frame that only partly overlaps does not occlude the exposed part", function()
            local under = panel(200, 60, 0, 0, "normal")
            panel(60, 60, 0, 0, "dialog")   -- covers only the left third
            -- The right end of `under` is still reachable
            local b = H.box(under)
            H.expectHitTarget(under, b.right - 5, b.top + 30)
        end)
    end)

    -- The regression this whole helper exists for: a plugin's unit frame must never
    -- swallow clicks meant for the settings window that configures it.
    describe("the layer system holds under input", function()
        it("a window captures clicks over plugin content beneath it", function()
            local pluginFrame = panel(200, 100, 20, 20, "normal")
            local win = H.SuuUI.Layout:CreateWindow({
                id = "hit_test_win", title = "Settings", w = 300, h = 200, centered = true,
            })
            win:Show()
            local wf = win:GetFrame()
            wf:EnableMouse(true)

            -- Sanity: the window really is over the plugin frame in draw order
            H.expectDrawsAbove(wf, pluginFrame)

            -- And in input order, at a point they both cover
            local bw, bp = H.box(wf), H.box(pluginFrame)
            local x = math.max(bw.left, bp.left) + 5
            local y = math.max(bw.top, bp.top) + 5
            if x < math.min(bw.right, bp.right) and y < math.min(bw.bottom, bp.bottom) then
                H.expectHitTarget(wf, x, y)
            end
            win:Hide()
        end)

        it("an edit-mode overlay takes the click on the frame it decorates", function()
            local frame = panel(200, 100, 20, 20, "normal")
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            H.SuuUI.MoveableFrame:Apply(frame, {
                pluginId    = "hit_test_plugin",
                key         = "pos",
                displayName = "Hit Test",
                defaults    = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -20 },
            })
            local overlay = frame._suuui_moveable.overlay

            -- Edit mode on: the overlay is what the player grabs, not the frame
            H.SuuUI.Settings:Set("_layout", "edit_mode", true)
            H.expectOccludes(overlay, frame)

            -- Edit mode off: the overlay is hidden and the frame is clickable again
            H.SuuUI.Settings:Set("_layout", "edit_mode", false)
            expect(overlay:IsShown()).eq(false)
            H.expectClickable(frame)

            H.SuuUI.MoveableFrame:Remove(frame)
        end)
    end)
end)
