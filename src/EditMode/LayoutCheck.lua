-- EditMode/LayoutCheck.lua
-- "/suu layoutcheck" (plan 4.1, the UI-scale check): where every frame of
-- your layout lands at 1080p, 1440p, 4K and 3440 × 1440, worked out from
-- its saved anchor and offset (no switching resolutions): frames that leave
-- the screen and frames that overlap. SuuUI's root has its own scale
-- (Appearance › Scale): automatic is 1 up to 1440p and larger above, so 4K
-- is 2560 × 1440 root units; a fixed scale divides every size by it.
-- Frames that place themselves (bars attached to the dock) move with what
-- they're attached to and aren't checked on their own; the party and raid
-- frames never show together, and the tooltip's place is only an anchor.
-- The report goes to the chat and to SuuUIProbe.layoutCheck.

local _, ns = ...

local EditMode, Settings = ns.EditMode, ns.Settings

local LayoutCheck = {}
ns.LayoutCheck = LayoutCheck

local SCREENS = {
    { "1080p", 1920, 1080 }, { "1440p", 2560, 1440 }, { "4K", 3840, 2160 }, { "3440 × 1440", 3440, 1440 },
}
-- pairs that never show at once, and places that are only anchors
local APART = { ["party.position"] = "raid.position", ["raid.position"] = "party.position" }
local ANCHOR_ONLY = { ["tooltips.position"] = true }
local SLACK = 2 -- px of touching that doesn't count

-- The root's size on a screen of pw × ph pixels with your scale setting.
local function rootSize(pw, ph)
    local s = Settings.Get("ui", "scale")
    if s == 0 then s = ph <= 1440 and 1 or math.floor(ph / 1440 * 4 + 0.5) / 4 end
    return pw / s, ph / s
end

-- A frame's rectangle on a W × H root from its anchor (the frame's point at
-- the screen's same point, offset by x, y).
local function place(pos, w, h, W, H)
    local point = pos.point or "CENTER"
    local horiz = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or ""
    local vert = point:find("BOTTOM") and "BOTTOM" or point:find("TOP") and "TOP" or ""
    local rx = (horiz == "LEFT" and 0) or (horiz == "RIGHT" and W) or W / 2
    local ry = (vert == "BOTTOM" and 0) or (vert == "TOP" and H) or H / 2
    local fx, fy = rx + (pos.x or 0), ry + (pos.y or 0)
    local l = (horiz == "LEFT" and fx) or (horiz == "RIGHT" and fx - w) or fx - w / 2
    local b = (vert == "BOTTOM" and fy) or (vert == "TOP" and fy - h) or fy - h / 2
    return l, b, w, h
end

local function overlap(a, b)
    local x = math.min(a.l + a.w, b.l + b.w) - math.max(a.l, b.l)
    local y = math.min(a.b + a.h, b.b + b.h) - math.max(a.b, b.b)
    if x > SLACK and y > SLACK then return math.floor(x + 0.5), math.floor(y + 0.5) end
end

function LayoutCheck.Run()
    local frames = {}
    for _, m in ipairs(EditMode.Movers()) do
        local id = m.namespace .. "." .. m.key
        local pos = Settings.Get(m.namespace, m.key)
        if m.enabled and not m.custom and not pos.hidden and not ANCHOR_ONLY[id] then
            -- the size, in root units (a hidden frame has no rectangle on
            -- screen, but its size: the party frames while you're solo)
            local scale = m.frame:GetEffectiveScale() / ns.Root:GetEffectiveScale()
            local w, h = m.frame:GetSize()
            w, h = (w or 0) * scale, (h or 0) * scale
            if w > 1 and h > 1 then frames[#frames + 1] = { id = id, label = m.label, pos = pos, w = w, h = h } end
        end
    end
    local report = { at = date("%Y-%m-%d %H:%M:%S"), screens = {} }
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.layoutCheck = report
    local total = 0
    for _, sc in ipairs(SCREENS) do
        local W, H = rootSize(sc[2], sc[3])
        local issues = {}
        local rects = {}
        for _, f in ipairs(frames) do
            local l, b, w, h = place(f.pos, f.w, f.h, W, H)
            local r = { f = f, l = l, b = b, w = w, h = h }
            rects[#rects + 1] = r
            local out = {}
            if l < -1 then out[#out + 1] = ("%d px past the left"):format(-l + 0.5) end
            if b < -1 then out[#out + 1] = ("%d px below the bottom"):format(-b + 0.5) end
            if l + w > W + 1 then out[#out + 1] = ("%d px past the right"):format(l + w - W + 0.5) end
            if b + h > H + 1 then out[#out + 1] = ("%d px above the top"):format(b + h - H + 0.5) end
            if #out > 0 then issues[#issues + 1] = f.label .. " leaves the screen: " .. table.concat(out, ", ") end
        end
        for i = 1, #rects do
            for j = i + 1, #rects do
                local a, c = rects[i], rects[j]
                if APART[a.f.id] ~= c.f.id then
                    local x, y = overlap(a, c)
                    if x then issues[#issues + 1] = ("%s and %s overlap (%d × %d px)"):format(a.f.label, c.f.label, x, y) end
                end
            end
        end
        report.screens[sc[1]] = { root = ("%d × %d"):format(W + 0.5, H + 0.5), issues = issues }
        total = total + #issues
        ns.Print(("%s (%d × %d): %s"):format(sc[1], W + 0.5, H + 0.5, #issues == 0 and "fits" or (#issues .. (#issues == 1 and " issue" or " issues"))))
        for _, text in ipairs(issues) do ns.Print("  " .. text) end
    end
    if total == 0 then ns.Print("Your layout fits every screen size, nothing overlapping.") end
    ns.Print("Layout check: /reload to save the report.")
end

ns.RegisterCommand("layoutcheck", "Where your layout lands at 1080p, 1440p, 4K and ultrawide: frames off the screen or overlapping.", function()
    LayoutCheck.Run()
end)
