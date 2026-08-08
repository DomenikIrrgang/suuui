local H = require("harness")

describe("Animation.Tween", function()
    before_each(function()
        H.setup()
    end)

    describe("Ease boundaries", function()
        local easings = { "linear", "easeIn", "easeOut", "easeInOut", "spring" }

        it("returns 0 at t=0 for every easing", function()
            for _, name in ipairs(easings) do
                expect(H.SuuUI.Tween.Ease(0, name)).as(name .. " at t=0").eq(0)
            end
        end)

        it("returns 1 at t=1 for every easing", function()
            for _, name in ipairs(easings) do
                expect(H.SuuUI.Tween.Ease(1, name)).as(name .. " at t=1").eq(1)
            end
        end)

        it("stays within [0, 1] for non-overshooting easings", function()
            local noOvershoot = { "linear", "easeIn", "easeOut", "easeInOut" }
            for _, name in ipairs(noOvershoot) do
                for i = 0, 100 do
                    local t = i / 100
                    local v = H.SuuUI.Tween.Ease(t, name)
                    expect(v).as(name .. " at t=" .. t).gte(0)
                    expect(v).as(name .. " at t=" .. t).lte(1)
                end
            end
        end)

        it("spring deliberately overshoots above 1 mid-curve", function()
            local maxVal = 0
            for i = 1, 99 do
                local t = i / 100
                local v = H.SuuUI.Tween.Ease(t, "spring")
                if v > maxVal then maxVal = v end
            end
            expect(maxVal).as("spring peak").gt(1)
        end)

        it("spring stays within sane bounds (below 1.11)", function()
            for i = 0, 100 do
                local t = i / 100
                local v = H.SuuUI.Tween.Ease(t, "spring")
                expect(v).as("spring at t=" .. t).lte(1.11)
                expect(v).as("spring at t=" .. t).gte(-0.1)
            end
        end)
    end)

    describe("unknown easing fallback", function()
        it("falls back to linear for unknown easing names", function()
            local v = H.SuuUI.Tween.Ease(0.5, "nonexistent_easing")
            expect(v).as("fallback to linear at t=0.5").eq(0.5)
        end)

        it("falls back to linear for nil easing", function()
            local v = H.SuuUI.Tween.Ease(0.5, nil)
            expect(v).as("fallback to linear at t=0.5 with nil").eq(0.5)
        end)
    end)
end)

describe("Animation.Animator", function()
    local host, target

    before_each(function()
        H.setup()
        host = H.parent(400, 300)
        target = H.env.CreateFrame("Frame", nil, host)
        target:SetSize(100, 50)
        target:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    end)

    describe("handle construction and defaults", function()
        it("creates a handle with default property alpha", function()
            local a = H.SuuUI.Anim:New({ target = target })
            expect(a.property).eq("alpha")
        end)

        it("defaults from=0, to=1, duration=0.25, easing=easeOut", function()
            local a = H.SuuUI.Anim:New({ target = target })
            expect(a.from).eq(0)
            expect(a.to).eq(1)
            expect(a.duration).eq(0.25)
            expect(a.easing).eq("easeOut")
        end)

        it("respects explicit def fields", function()
            local cb = function() end
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "width",
                from     = 10,
                to       = 200,
                duration = 0.5,
                easing   = "easeIn",
                onDone   = cb,
            })
            expect(a.property).eq("width")
            expect(a.from).eq(10)
            expect(a.to).eq(200)
            expect(a.duration).eq(0.5)
            expect(a.easing).eq("easeIn")
            expect(a.onDone).eq(cb)
        end)

        it("starts in non-playing state", function()
            local a = H.SuuUI.Anim:New({ target = target })
            expect(a:IsPlaying()).eq(false)
        end)
    end)

    describe("Play / Stop / IsPlaying / Reverse", function()
        it("Play sets IsPlaying to true", function()
            local a = H.SuuUI.Anim:New({ target = target, duration = 1 })
            a:Play()
            expect(a:IsPlaying()).eq(true)
        end)

        it("Stop sets IsPlaying to false", function()
            local a = H.SuuUI.Anim:New({ target = target, duration = 1 })
            a:Play()
            a:Stop()
            expect(a:IsPlaying()).eq(false)
        end)

        it("Play is idempotent when already playing", function()
            local a = H.SuuUI.Anim:New({ target = target, from = 0, to = 1, duration = 1 })
            a:Play()
            H.tick(0.5)
            a:Play() -- should not restart elapsed
            expect(a:IsPlaying()).eq(true)
        end)

        it("Reverse swaps from and to then plays", function()
            local a = H.SuuUI.Anim:New({ target = target, from = 0, to = 1, duration = 0.5 })
            a:Reverse()
            expect(a.from).eq(1)
            expect(a.to).eq(0)
            expect(a:IsPlaying()).eq(true)
        end)

        it("animation completes after duration elapses", function()
            local done = false
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.2,
                onDone   = function() done = true end,
            })
            a:Play()
            H.tick(0.3)
            expect(a:IsPlaying()).eq(false)
            expect(done).eq(true)
        end)

        it("target reaches the 'to' value on completion", function()
            target:SetAlpha(0)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 0.75,
                duration = 0.1,
                easing   = "linear",
            })
            a:Play()
            H.tick(0.2)
            expect(target:GetAlpha()).near(0.75, 0.01)
        end)

        it("Stop does not fire onDone", function()
            local done = false
            local a = H.SuuUI.Anim:New({
                target   = target,
                duration = 1,
                onDone   = function() done = true end,
            })
            a:Play()
            H.tick(0.1)
            a:Stop()
            H.tick(2)
            expect(done).eq(false)
        end)
    end)

    describe("regression: duration=0 resolves instantly (no NaN)", function()
        it("jumps to the to value in a single tick", function()
            target:SetAlpha(0)
            local done = false
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 0.8,
                duration = 0,
                easing   = "linear",
                onDone   = function() done = true end,
            })
            a:Play()
            H.tick(0.016)
            expect(target:GetAlpha()).near(0.8, 0.01)
            expect(done).eq(true)
            expect(a:IsPlaying()).eq(false)
        end)

        it("negative duration also resolves instantly", function()
            target:SetAlpha(0)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = -1,
                easing   = "easeOut",
            })
            a:Play()
            H.tick(0.016)
            expect(target:GetAlpha()).near(1, 0.01)
            expect(a:IsPlaying()).eq(false)
        end)

        it("does not produce NaN on the target", function()
            target:SetAlpha(0)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0,
                easing   = "spring",
            })
            a:Play()
            H.tick(0.016)
            local alpha = target:GetAlpha()
            -- NaN ~= NaN, so x ~= x is the NaN check
            expect(alpha == alpha).as("alpha should not be NaN").eq(true)
            expect(alpha).near(1, 0.01)
        end)
    end)

    describe("regression: visibility guard calls IsShown()", function()
        it("does NOT write to a hidden target", function()
            target:SetAlpha(0.5)
            target:Hide()
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.2,
                easing   = "linear",
            })
            a:Play()
            H.tick(0.1)
            -- Alpha should stay at 0.5 because target is hidden
            expect(target:GetAlpha()).eq(0.5)
        end)

        it("hidden target still completes and fires onDone", function()
            target:Hide()
            local done = false
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.1,
                onDone   = function() done = true end,
            })
            a:Play()
            H.tick(0.2)
            expect(done).eq(true)
            expect(a:IsPlaying()).eq(false)
        end)
    end)

    describe("regression: Sequence restores onDone", function()
        it("handle onDone is restored after sequence passes through", function()
            local originalCalled = false
            local originalDone = function() originalCalled = true end
            local a1 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.1,
                easing   = "linear",
                onDone   = originalDone,
            })
            local a2 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 1,
                to       = 0,
                duration = 0.1,
                easing   = "linear",
            })
            H.SuuUI.Anim:Sequence({ a1, a2 })
            H.runAnimations()
            -- After sequence completes, a1.onDone should be back to original
            expect(a1.onDone).eq(originalDone)
        end)

        it("original onDone still fires during the sequence", function()
            local originalCalled = false
            local a1 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.1,
                onDone   = function() originalCalled = true end,
            })
            local a2 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 1,
                to       = 0,
                duration = 0.1,
            })
            H.SuuUI.Anim:Sequence({ a1, a2 })
            H.runAnimations()
            expect(originalCalled).eq(true)
        end)

        it("handle is reusable after sequence with intact onDone", function()
            local count = 0
            local a1 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 0.1,
                onDone   = function() count = count + 1 end,
            })
            local a2 = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 1,
                to       = 0,
                duration = 0.1,
            })
            -- Run it in a sequence
            H.SuuUI.Anim:Sequence({ a1, a2 })
            H.runAnimations()
            -- Now replay a1 standalone — its onDone should still fire
            a1:Play()
            H.runAnimations()
            expect(count).eq(2) -- once from sequence, once standalone
        end)
    end)

    describe("regression: CancelAll stops all anims on target", function()
        it("returns count of stopped animations", function()
            local a1 = H.SuuUI.Anim:New({ target = target, duration = 1, property = "alpha" })
            local a2 = H.SuuUI.Anim:New({ target = target, duration = 1, property = "width" })
            a1:Play()
            a2:Play()
            local count = H.SuuUI.Anim:CancelAll(target)
            expect(count).eq(2)
        end)

        it("IsPlaying goes false on cancelled handles", function()
            local a1 = H.SuuUI.Anim:New({ target = target, duration = 1 })
            local a2 = H.SuuUI.Anim:New({ target = target, duration = 1, property = "width" })
            a1:Play()
            a2:Play()
            H.SuuUI.Anim:CancelAll(target)
            expect(a1:IsPlaying()).eq(false)
            expect(a2:IsPlaying()).eq(false)
        end)

        it("does NOT fire onDone on cancelled animations", function()
            local called = false
            local a = H.SuuUI.Anim:New({
                target   = target,
                duration = 1,
                onDone   = function() called = true end,
            })
            a:Play()
            H.SuuUI.Anim:CancelAll(target)
            H.tick(2)
            expect(called).eq(false)
        end)

        it("returns 0 for a target with no running animations", function()
            local count = H.SuuUI.Anim:CancelAll(target)
            expect(count).eq(0)
        end)

        it("returns 0 for nil target", function()
            local count = H.SuuUI.Anim:CancelAll(nil)
            expect(count).eq(0)
        end)

        it("does not affect animations on other targets", function()
            local other = H.env.CreateFrame("Frame", nil, host)
            other:SetSize(50, 50)
            other:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            local aTarget = H.SuuUI.Anim:New({ target = target, duration = 1 })
            local aOther  = H.SuuUI.Anim:New({ target = other, duration = 1 })
            aTarget:Play()
            aOther:Play()
            H.SuuUI.Anim:CancelAll(target)
            expect(aOther:IsPlaying()).eq(true)
        end)
    end)

    describe("Parallel iterates with ipairs", function()
        it("plays all handles in an array", function()
            local a1 = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "alpha" })
            local a2 = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "width" })
            H.SuuUI.Anim:Parallel({ a1, a2 })
            expect(a1:IsPlaying()).eq(true)
            expect(a2:IsPlaying()).eq(true)
        end)

        it("does not play non-sequential keys (hash part)", function()
            local a1 = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "alpha" })
            local anims = { a1 }
            -- Add a non-sequential key — ipairs skips these
            anims["extra"] = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "width" })
            H.SuuUI.Anim:Parallel(anims)
            expect(a1:IsPlaying()).eq(true)
            expect(anims["extra"]:IsPlaying()).eq(false)
        end)
    end)

    describe("Sequence chaining", function()
        it("plays animations in order", function()
            local order = {}
            local a1 = H.SuuUI.Anim:New({
                target = target, duration = 0.1, property = "alpha",
                from = 0, to = 1,
                onDone = function() table.insert(order, "a1") end,
            })
            local a2 = H.SuuUI.Anim:New({
                target = target, duration = 0.1, property = "alpha",
                from = 1, to = 0,
                onDone = function() table.insert(order, "a2") end,
            })
            H.SuuUI.Anim:Sequence({ a1, a2 })
            H.runAnimations()
            expect(order[1]).eq("a1")
            expect(order[2]).eq("a2")
        end)

        it("second anim starts only after first completes", function()
            local a1 = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "alpha", from = 0, to = 1 })
            local a2 = H.SuuUI.Anim:New({ target = target, duration = 0.5, property = "alpha", from = 1, to = 0 })
            H.SuuUI.Anim:Sequence({ a1, a2 })
            -- After one tick a2 should not be playing yet
            H.tick(0.016)
            expect(a1:IsPlaying()).eq(true)
            expect(a2:IsPlaying()).eq(false)
        end)
    end)

    describe("position animation (x/y)", function()
        it("requires a container for x property", function()
            -- Without container, should log and degrade — not error
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "x",
                from     = 0,
                to       = 50,
                duration = 0.1,
            })
            expect(function() a:Play(); H.tick(0.1) end).notThrows()
        end)

        it("requires a container for y property", function()
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "y",
                from     = 0,
                to       = 50,
                duration = 0.1,
            })
            expect(function() a:Play(); H.tick(0.1) end).notThrows()
        end)

        it("drives SetChildAnchor on the container for x", function()
            local container = H.Layout:CreateContainer({ host = host, layout = "anchor" })
            container:Add(target, { anchor = {
                point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0,
            }})
            local anchorDef = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0 }
            local a = H.SuuUI.Anim:New({
                target    = target,
                container = container,
                anchor    = anchorDef,
                property  = "x",
                from      = 0,
                to        = 50,
                duration  = 0.1,
                easing    = "linear",
            })
            a:Play()
            H.runAnimations()
            -- After animation, x should be at 50
            -- Verify by checking the child's position shifted
            local box = H.box(target)
            expect(box).notNil()
            expect(box.left).near(50, 1)
        end)

        it("drives SetChildAnchor on the container for y", function()
            local container = H.Layout:CreateContainer({ host = host, layout = "anchor" })
            container:Add(target, { anchor = {
                point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0,
            }})
            local anchorDef = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0 }
            local a = H.SuuUI.Anim:New({
                target    = target,
                container = container,
                anchor    = anchorDef,
                property  = "y",
                from      = 0,
                to        = -30,
                duration  = 0.1,
                easing    = "linear",
            })
            a:Play()
            H.runAnimations()
            local box = H.box(target)
            expect(box).notNil()
        end)
    end)

    describe("Presets", function()
        it("FadeIn returns without error", function()
            expect(function()
                H.SuuUI.Anim.Presets.FadeIn(target, 0.1)
            end).notThrows()
        end)

        it("FadeIn shows the frame and starts at alpha 0", function()
            target:Hide()
            target:SetAlpha(1)
            H.SuuUI.Anim.Presets.FadeIn(target, 0.1)
            -- After calling, frame should be shown and alpha set to 0
            expect(target:IsShown()).eq(true)
            expect(target:GetAlpha()).eq(0)
        end)

        it("FadeIn reaches alpha 1 after completion", function()
            target:SetAlpha(0)
            H.SuuUI.Anim.Presets.FadeIn(target, 0.1)
            H.runAnimations()
            expect(target:GetAlpha()).near(1, 0.01)
        end)

        it("FadeOut hides the frame after completion", function()
            target:SetAlpha(1)
            target:Show()
            H.SuuUI.Anim.Presets.FadeOut(target, 0.1)
            H.runAnimations()
            expect(target:IsShown()).eq(false)
        end)

        it("ScalePop does not error", function()
            expect(function()
                H.SuuUI.Anim.Presets.ScalePop(target, 0.1)
            end).notThrows()
        end)

        it("ScalePop returns to scale 1 after completion", function()
            target:SetScale(1)
            H.SuuUI.Anim.Presets.ScalePop(target, 0.2)
            H.runAnimations()
            expect(target:GetScale()).near(1, 0.01)
        end)

        it("SlideIn does not error with a container", function()
            local container = H.Layout:CreateContainer({ host = host, layout = "anchor" })
            container:Add(target, { anchor = {
                point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0,
            }})
            expect(function()
                H.SuuUI.Anim.Presets.SlideIn(
                    container, target,
                    { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0 },
                    "left", 12, 0.1
                )
            end).notThrows()
        end)

        it("SlideOut does not error with a container", function()
            local container = H.Layout:CreateContainer({ host = host, layout = "anchor" })
            container:Add(target, { anchor = {
                point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0,
            }})
            expect(function()
                H.SuuUI.Anim.Presets.SlideOut(
                    container, target,
                    { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 0, y = 0 },
                    "right", 12, 0.1
                )
            end).notThrows()
        end)
    end)

    describe("property setters", function()
        it("animates width", function()
            target:SetWidth(10)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "width",
                from     = 10,
                to       = 200,
                duration = 0.1,
                easing   = "linear",
            })
            a:Play()
            H.runAnimations()
            expect(target:GetWidth()).near(200, 1)
        end)

        it("animates height", function()
            target:SetHeight(10)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "height",
                from     = 10,
                to       = 80,
                duration = 0.1,
                easing   = "linear",
            })
            a:Play()
            H.runAnimations()
            expect(target:GetHeight()).near(80, 1)
        end)

        it("animates scale", function()
            target:SetScale(1)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "scale",
                from     = 1,
                to       = 2,
                duration = 0.1,
                easing   = "linear",
            })
            a:Play()
            H.runAnimations()
            expect(target:GetScale()).near(2, 0.01)
        end)
    end)

    describe("intermediate values during animation", function()
        it("alpha is between from and to mid-animation with linear easing", function()
            target:SetAlpha(0)
            local a = H.SuuUI.Anim:New({
                target   = target,
                property = "alpha",
                from     = 0,
                to       = 1,
                duration = 1,
                easing   = "linear",
            })
            a:Play()
            H.tick(0.5)
            expect(target:GetAlpha()).near(0.5, 0.05)
        end)
    end)
end)
