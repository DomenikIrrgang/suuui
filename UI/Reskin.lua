-- UI/Reskin.lua
-- Blizzard's list and detail parts in SuuUI's look, restyled in place (Phase
-- 3's windows): rows, collapsible category bars, status bars, check
-- buttons, the thin scrollbar, dividers. Clicks and data stay Blizzard's; a
-- pass only changes how things look, so it can run again whenever Blizzard
-- redraws (each ScrollBox update).
--
--   UI.Reskin(frame)              -- the frame and everything in it, once more
--   UI.ReskinScrollBox(box)       -- its rows now and after every update
--   UI.ReskinStatusBar(bar)       -- a flat bar on a track, standing colours kept
--   UI.ReskinCheckButton(button)  -- a 16px box, arcane check
--   UI.ReskinScrollBar(bar)       -- no track art, a 2px gilt-line thumb
--
-- What a pass does, by what it finds (Blizzard's atlas names, probed in the
-- Character window 2026-10-13):
--   *collapseExpand*, *ScrollLine*, *insideframe*, *stat-bar-BG*, the
--   panes' backgrounds: hidden
--   a row's minus/plus state icon: tinted gilt-text
--   a category row (one with a collapse/expand bar): its name in `header`
--   gilt-text, a gilt-faint rule under it
--   *highlight*/*hover* textures: surface-raised; *select* ones: arcane-soft
--   text: Blizzard's yellow and white become ink, grey ink-muted, green fel,
--   red ember-text; the font follows the text's size (label, body, caption);
--   big titles become `header` gilt-text

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local isSecret = issecretvalue or function() return false end

local HIDE = { "collapseexpand", "scrollline", "insideframe", "stat%-bar%-bg", "stat%-bg", "%-info%-.*%-bg",
               "stattab", "button%-list%-header", "common%-search%-border", "plunderstorm" }
local BAR_COLORS = {
    red = "rep-hostile", orange = "rep-unfriendly", yellow = "rep-neutral", green = "rep-friendly",
    blue = "progress-fill", purple = "arcane", gold = "gilt-text",
}

local function ask(r, method, ...)
    if type(r[method]) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(r[method], r, ...)
    if ok then return a, b, c, d end
end

local function matchesAny(s, list)
    for _, p in ipairs(list) do if s:find(p) then return true end end
    return false
end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

function UI.ReskinScrollBar(bar)
    if not bar or bar.suuReskinned then return end
    bar.suuReskinned = true
    local track = bar.Track
    if track then
        for _, r in ipairs({ track:GetRegions() }) do r:SetAlpha(0) end
        local thumb = track.Thumb
        if thumb then
            for _, r in ipairs({ thumb:GetRegions() }) do r:SetAlpha(0) end
            local t = thumb:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(UI.RGBA("gilt-line"))
            t:SetPoint("TOP")
            t:SetPoint("BOTTOM")
            t:SetWidth(2)
        end
    end
    for _, key in ipairs({ "Back", "Forward" }) do
        if bar[key] then bar[key]:SetAlpha(0) end
    end
end

-- A flat fill on a track inside a gilt-hairline edge, as tall as Blizzard's
-- fill; the colour from the fill's atlas (standing colours kept).
function UI.ReskinStatusBar(bar)
    if not bar then return end
    local fill = ask(bar, "GetStatusBarTexture")
    local atlas = fill and ask(fill, "GetAtlas")
    if atlas and atlas ~= "" then bar.suuAtlas = atlas end
    if not bar.suuReskinned then
        bar.suuReskinned = true
        for _, r in ipairs({ bar:GetRegions() }) do
            local t = r:GetObjectType()
            if t == "Texture" and r ~= fill then r:SetAlpha(0) end
            if t == "MaskTexture" and fill then pcall(fill.RemoveMaskTexture, fill, r) end
        end
        local h = (fill and fill:GetHeight() or 12)
        if h < 4 or h > bar:GetHeight() then h = math.min(14, bar:GetHeight()) end
        local track = CreateFrame("Frame", nil, bar)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(h)
        track:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        UI.Fill(track, "track"):SetAllPoints()
        UI.Border(track, "gilt-hairline")
        bar.suuTrack = track
    end
    local function flatten()
        local f = ask(bar, "GetStatusBarTexture")
        if not f then return end
        local a = ask(f, "GetAtlas")
        if a and a ~= "" then bar.suuAtlas = a end
        bar.suuFlattening = true
        f:SetTexture(WHITE)
        local word = bar.suuAtlas and bar.suuAtlas:lower():match("stat%-bar%-(%a+)")
        f:SetVertexColor(UI.RGBA(BAR_COLORS[word or ""] or "progress-fill"))
        bar.suuFlattening = false
    end
    if fill and not bar.suuFillHooked then
        bar.suuFillHooked = true
        -- Blizzard sets the fill again (its standing's atlas): flat again
        local function again() if not bar.suuFlattening then flatten() end end
        hooksecurefunc(fill, "SetAtlas", again)
        if bar.SetStatusBarTexture then hooksecurefunc(bar, "SetStatusBarTexture", again) end
    end
    flatten()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "FontString" then
            ns.Fonts.Apply(r, "numeric")
            r:SetJustifyH("CENTER")
            -- on the track's middle, a pixel up (the figures sit low otherwise)
            if bar.suuTrack then
                r:ClearAllPoints()
                r:SetPoint("LEFT", bar.suuTrack, "LEFT", 0, 1)
                r:SetPoint("RIGHT", bar.suuTrack, "RIGHT", 0, 1)
            end
            r:SetTextColor(UI.RGBA("ink"))
            r:SetShadowColor(0, 0, 0, 1)
            r:SetShadowOffset(0, -1)
        end
    end
end

-- A bar Blizzard draws itself (a frame with a Fill texture it sizes and
-- tints: the reputation's standing bars): the fill flat in Blizzard's tint
-- (the standing's colour), a track in a gilt-hairline edge, the text centred.
function UI.ReskinFillBar(bar)
    local fill = bar and bar.Fill
    if not fill then return end
    if not bar.suuFillBar then
        bar.suuFillBar = true
        for _, r in ipairs({ bar:GetRegions() }) do
            local t = r:GetObjectType()
            if t == "Texture" and r ~= fill then r:SetAlpha(0) end
            if t == "MaskTexture" then pcall(fill.RemoveMaskTexture, fill, r) end
        end
        local h = math.max(6, math.min(14, fill:GetHeight() or 12))
        local track = CreateFrame("Frame", nil, bar)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(h)
        track:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        UI.Fill(track, "track"):SetAllPoints()
        UI.Border(track, "gilt-hairline")
        bar.suuTrack = track
        fill:SetHeight(h - 2)
        local flattening = false
        local function flat()
            if flattening then return end
            flattening = true
            fill:SetTexture(WHITE)
            flattening = false
        end
        hooksecurefunc(fill, "SetAtlas", flat)
        bar.suuFlat = flat
    end
    bar.suuFlat()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "FontString" then
            ns.Fonts.Apply(r, "numeric")
            r:SetJustifyH("CENTER")
            -- on the track's middle (the reputation's figures sit right there;
            -- a pixel up was too high, found in game)
            r:ClearAllPoints()
            r:SetPoint("LEFT", bar.suuTrack, "LEFT", 0, 0)
            r:SetPoint("RIGHT", bar.suuTrack, "RIGHT", 0, 0)
            r:SetTextColor(UI.RGBA("ink"))
            r:SetShadowColor(0, 0, 0, 1)
            r:SetShadowOffset(0, -1)
        end
    end
end

-- Blizzard's dropdown (WowStyle): surface-sunk in a gilt-line edge, its text
-- in label ink, a chevron on the right.
function UI.ReskinDropdown(d)
    if not d or d.suuDropdown then return end
    for _, r in ipairs({ d:GetRegions() }) do
        if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "Arrow", "Background" }) do
        if d[key] and d[key].SetAlpha then d[key]:SetAlpha(0) end
    end
    local bg = d:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetColorTexture(UI.RGBA("surface-sunk"))
    bg:SetAllPoints()
    bg.suuArt = true
    local edge = UI.Border(d, "gilt-line")
    local chev = d:CreateTexture(nil, "OVERLAY", nil, 7)
    chev:SetTexture(GLYPHS .. "chevronDown.tga")
    chev:SetSize(12, 12)
    chev:SetPoint("RIGHT", -S["space-3"], 0)
    chev:SetVertexColor(UI.RGBA("ink-muted"))
    chev.suuArt = true
    d:HookScript("OnEnter", function() edge:SetColor("gilt") end)
    d:HookScript("OnLeave", function() edge:SetColor("gilt-line") end)
    local text = d.Text or d.text
    if text then
        ns.Fonts.Apply(text, "label")
        text:SetTextColor(UI.RGBA("ink"))
        text:SetShadowOffset(0, 0)
    end
    d.suuDropdown = true
end

-- An icon button (the set popup's grid and its chosen icon): every bit of
-- Blizzard's frame art away, the icon cropped on a surface-sunk well in a
-- gilt-hairline edge, gilt on hover, arcane while selected (Blizzard's own
-- SelectedTexture says when).
function UI.ReskinIconButton(b)
    if not b then return end
    local icon = b.Icon or b.icon
    if not b.suuIcon then
        local well = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        well:SetColorTexture(UI.RGBA("surface-sunk"))
        well:SetAllPoints()
        well.suuArt = true
        local edgeHolder = CreateFrame("Frame", nil, b)
        edgeHolder:SetAllPoints()
        edgeHolder:EnableMouse(false)
        edgeHolder:SetFrameLevel(b:GetFrameLevel() + 2)
        local edge = UI.Border(edgeHolder, "gilt-hairline")
        local st = { edge = edge, hover = false }
        b.suuIcon = st
        b:HookScript("OnEnter", function() st.hover = true; st.draw() end)
        b:HookScript("OnLeave", function() st.hover = false; st.draw() end)
        local sel = b.SelectedTexture or b.selectedTexture
        st.draw = function()
            local on = sel and sel:IsShown()
            edge:SetColor(on and "arcane" or (st.hover and "gilt" or "gilt-hairline"))
        end
        if sel then
            for _, m in ipairs({ "Show", "Hide", "SetShown" }) do hooksecurefunc(sel, m, function() st.draw() end) end
        end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetCheckedTexture" }) do
        local t = ask(b, get)
        if t and t ~= icon then t:SetAlpha(0) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r ~= icon and not r.suuArt then r:SetAlpha(0) end
    end
    if icon then
        icon:SetAlpha(1)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.suuIcon.draw()
end

function UI.ReskinCheckButton(b)
    if not b or b.suuCheck then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = ask(b, get)
        if t then t:SetAlpha(0) end
    end
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    box:EnableMouse(false)
    UI.Fill(box, "surface-sunk"):SetAllPoints()
    local edge = UI.Border(box, "gilt-line")
    local check = box:CreateTexture(nil, "OVERLAY")
    check:SetTexture(GLYPHS .. "check.tga")
    check:SetSize(14, 14)
    check:SetPoint("CENTER")
    check:SetVertexColor(UI.RGBA("arcane"))
    local function draw()
        local on = ask(b, "GetChecked")
        check:SetShown(on and true or false)
        edge:SetColor(on and "arcane" or "gilt-line")
    end
    hooksecurefunc(b, "SetChecked", draw)
    b:HookScript("OnClick", draw)
    b:HookScript("OnShow", draw)
    b.suuCheck = { box = box, draw = draw }
    draw()
end

-- Blizzard's panel button (Left/Middle/Right art, or a red button atlas) as
-- SuuUI's quiet button: surface-raised, gilt-line edge (gilt on hover), its
-- label in `label` ink; dimmed while disabled.
function UI.ReskinButton(b)
    if not b or b.suuButton then return end
    for _, key in ipairs({ "Left", "Middle", "Center", "Right", "LeftSeparator", "RightSeparator" }) do
        if b[key] and b[key].SetAlpha then b[key]:SetAlpha(0) end
    end
    -- any other button art (an atlas with "button" in it)
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local a = (ask(r, "GetAtlas") or ""):lower()
            if a:find("button") then r:SetAlpha(0) end
        end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = ask(b, get)
        if t then t:SetAlpha(0) end
    end
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetColorTexture(UI.RGBA("surface-raised"))
    bg:SetAllPoints()
    local edge = UI.Border(b, "gilt-line")
    b:HookScript("OnEnter", function() edge:SetColor("gilt") end)
    b:HookScript("OnLeave", function() edge:SetColor("gilt-line") end)
    local function draw()
        b:SetAlpha(ask(b, "IsEnabled") == false and T.opacity["opacity-disabled"] or 1)
        local fs = ask(b, "GetFontString")
        if fs then
            ns.Fonts.Apply(fs, "label")
            fs:SetTextColor(UI.RGBA("ink"))
            fs:SetShadowOffset(0, 0)
        end
    end
    hooksecurefunc(b, "SetEnabled", draw)
    if b.Enable then hooksecurefunc(b, "Enable", draw) end
    if b.Disable then hooksecurefunc(b, "Disable", draw) end
    b.suuButton = { draw = draw }
    draw()
end

-- An input box: Blizzard's Left/Middle/Right art away, surface-sunk inside a
-- gilt-line edge (arcane while typing), body ink.
function UI.ReskinEditBox(e)
    if not e or e.suuEdit then return end
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        if e[key] and e[key].SetAlpha then e[key]:SetAlpha(0) end
    end
    local name = e:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right", "Mid" }) do
            local t = _G[name .. suffix]
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
    end
    -- whatever else Blizzard drew it with (its own art, a backdrop frame)
    for _, r in ipairs({ e:GetRegions() }) do
        if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    for _, c in ipairs({ e:GetChildren() }) do
        if c.NineSlice then c.NineSlice:SetAlpha(0) end
        for _, r in ipairs({ c:GetRegions() }) do
            if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
    end
    if e.NineSlice then e.NineSlice:SetAlpha(0) end
    local bg = e:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetColorTexture(UI.RGBA("surface-sunk"))
    bg:SetPoint("TOPLEFT", -4, -1)
    bg:SetPoint("BOTTOMRIGHT", 0, 1)
    local holder = CreateFrame("Frame", nil, e)
    holder:SetPoint("TOPLEFT", bg)
    holder:SetPoint("BOTTOMRIGHT", bg)
    holder:EnableMouse(false)
    local edge = UI.Border(holder, "gilt-line")
    e:HookScript("OnEditFocusGained", function() edge:SetColor("arcane") end)
    e:HookScript("OnEditFocusLost", function() edge:SetColor("gilt-line") end)
    e:SetFontObject(ns.Fonts.Get("body"))
    e:SetTextColor(UI.RGBA("ink"))
    e.suuEdit = true
end

-- A small collapse/expand button (Statistics' sub-categories): SuuUI's
-- minus or plus in gilt-text, following the state Blizzard sets.
function UI.ReskinCollapseButton(b)
    if not b or b.suuCollapse then return end
    local glyph = b:CreateTexture(nil, "OVERLAY", nil, 7)
    glyph:SetSize(12, 12)
    glyph:SetPoint("CENTER")
    glyph:SetVertexColor(UI.RGBA("gilt-text"))
    local function draw()
        local t = ask(b, "GetNormalTexture")
        local name = ""
        if t then
            name = (ask(t, "GetAtlas") or tostring(ask(t, "GetTexture") or "")):lower()
            t:SetAlpha(0)
        end
        for _, get in ipairs({ "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local x = ask(b, get)
            if x then x:SetAlpha(0) end
        end
        for _, r in ipairs({ b:GetRegions() }) do
            if r ~= glyph and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
        local plus = name:find("plus") or name:find("expand") and not name:find("expanded")
        glyph:SetTexture(GLYPHS .. (plus and "plus" or "minus") .. ".tga")
    end
    if b.SetNormalTexture then hooksecurefunc(b, "SetNormalTexture", draw) end
    if b.SetNormalAtlas then hooksecurefunc(b, "SetNormalAtlas", draw) end
    b:HookScript("OnClick", function() C_Timer.After(0, draw) end)
    b.suuCollapse = { draw = draw }
    draw()
end

local function isPanelButton(b)
    if b.Left and b.Right and (b.Middle or b.Center) then return true end
    -- art with "button" in its atlas (not a list's collapse bar or a minus/plus)
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local a = (ask(r, "GetAtlas") or ""):lower()
            if a:find("button") and not a:find("list") and not a:find("minus") and not a:find("plus") then return true end
        end
    end
    local t = ask(b, "GetNormalTexture")
    if not t then return false end
    local name = (ask(t, "GetAtlas") or tostring(ask(t, "GetTexture") or "")):lower()
    return name:find("panel%-button") or name:find("redbutton") or name:find("128%-red") or name:find("common%-button") or false
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function textColor(r, g, b)
    if not r then return "ink" end
    if r > 0.9 and g > 0.7 and g < 0.9 and b < 0.2 then return "ink" end -- Blizzard's yellow
    if r > 0.85 and g > 0.85 and b > 0.85 then return "ink" end
    if g > 0.7 and r < 0.5 and b < 0.5 then return "fel" end
    if r > 0.8 and g < 0.4 and b < 0.4 then return "ember-text" end
    if math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 and r < 0.75 then return "ink-muted" end
    return nil -- another colour of Blizzard's (a quality, a standing): kept
end

local function reskinText(fs, isHead)
    if fs.suuSkip then return end
    local _, size = ask(fs, "GetFont")
    size = tonumber(size) or 12
    local fo = ask(fs, "GetFontObject")
    local foName = fo and ask(fo, "GetName") or ""
    local text = ask(fs, "GetText")
    local long = type(text) == "string" and not isSecret(text) and #text > 40
    if isHead then
        ns.Fonts.Apply(fs, "header")
        fs:SetTextColor(UI.RGBA("gilt-text"))
    elseif not long and (size >= 14 or foName:find("Med") or foName:find("Large")) then
        ns.Fonts.Apply(fs, "header")
        fs:SetTextColor(UI.RGBA("gilt-text"))
    else
        local r, g, b = ask(fs, "GetTextColor")
        local token = textColor(r, g, b)
        ns.Fonts.Apply(fs, foName:find("Number") and "numeric" or (size < 11 and "caption" or (long and "body" or "label")))
        if token then fs:SetTextColor(UI.RGBA(token)) else fs:SetTextColor(r, g, b) end
    end
    fs:SetShadowOffset(0, 0)
end

--------------------------------------------------------------------------------
-- A pass over a frame
--------------------------------------------------------------------------------

local function reskinTexture(t, ctx)
    local atlas = ask(t, "GetAtlas")
    local a = atlas and atlas:lower() or ""
    local layer = ask(t, "GetDrawLayer")
    if a ~= "" and matchesAny(a, HIDE) then
        if a:find("collapseexpand") then ctx.head = true end
        t:SetAlpha(0)
    elseif a:find("checkmark") and not a:find("minimal") and not t.suuMoved then
        -- a list row's check (the equipment set you wear): its top right corner
        local parent = t:GetParent()
        t.suuMoved = true
        t:ClearAllPoints()
        t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -S["space-2"], -S["space-2"])
        t:SetSize(12, 12)
    elseif a:find("minus") or a:find("plus") then
        t:SetDesaturated(true)
        t:SetVertexColor(UI.RGBA("gilt-text"))
    elseif a:find("select") then
        t:SetColorTexture(UI.RGBA("arcane-soft"))
    elseif layer == "HIGHLIGHT" or a:find("highlight") or a:find("hover") then
        t:SetColorTexture(UI.RGBA("surface-raised"))
        t:SetAlpha(0.6)
    end
end

local function pass(f, depth, ctx)
    if depth > 6 or ask(f, "IsForbidden") then return end
    local kind = ask(f, "GetObjectType")
    if kind == "StatusBar" then UI.ReskinStatusBar(f); return end
    if kind == "CheckButton" and not f.suuNoCheck then UI.ReskinCheckButton(f) end
    if kind == "EditBox" then UI.ReskinEditBox(f) end
    if kind == "DropdownButton" or (f.Arrow and f.Text and kind == "Button" and not f.suuButton) then
        UI.ReskinDropdown(f)
        return
    end
    if f.Fill and ask(f.Fill, "GetObjectType") == "Texture" then
        local a = (ask(f.Fill, "GetAtlas") or ""):lower()
        if a:find("stat%-bar") or f.suuFillBar then UI.ReskinFillBar(f); return end
    end
    if kind == "Button" then
        local key = ask(f, "GetParentKey") or ""
        if key:find("Collapse") or key:find("Expand") then UI.ReskinCollapseButton(f)
        elseif not f.suuNoButton and isPanelButton(f) then UI.ReskinButton(f) end
        if f.suuCollapse then f.suuCollapse.draw() end
        if f.suuButton then f.suuButton.draw() end
    end
    -- a ScrollBar (Blizzard's minimal one)
    if f.Track and f.Back and f.Forward then UI.ReskinScrollBar(f); return end
    -- a ScrollBox: its rows, one by one, now and after every update
    if f.ScrollTarget and f.ForEachFrame then UI.ReskinScrollBox(f); return end
    local texts = {}
    for _, r in ipairs({ f:GetRegions() }) do
        local t = r:GetObjectType()
        if t == "Texture" then reskinTexture(r, ctx)
        elseif t == "FontString" then texts[#texts + 1] = r end
    end
    -- a category row: its name as a head, a rule under it
    if ctx.head and depth == ctx.rowDepth then
        for _, fs in ipairs(texts) do reskinText(fs, true) end
        if not f.suuHeadRule then
            f.suuHeadRule = f:CreateTexture(nil, "ARTWORK")
            f.suuHeadRule:SetColorTexture(UI.RGBA("gilt-faint"))
            f.suuHeadRule:SetHeight(1)
            f.suuHeadRule:SetPoint("BOTTOMLEFT", S["space-3"], 0)
            f.suuHeadRule:SetPoint("BOTTOMRIGHT", -S["space-3"], 0)
        end
    else
        for _, fs in ipairs(texts) do reskinText(fs, false) end
    end
    for _, c in ipairs({ f:GetChildren() }) do pass(c, depth + 1, ctx) end
end

function UI.Reskin(frame)
    if not frame then return end
    pass(frame, 0, { rowDepth = 0 })
end

-- One row: a fresh context, so a category bar marks only its own row.
local function reskinRow(row)
    local ctx = { rowDepth = 0 }
    -- a category bar is a texture of the row itself: look first
    for _, r in ipairs({ row:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local a = ask(r, "GetAtlas")
            if a and a:lower():find("collapseexpand") then ctx.head = true end
        end
    end
    pass(row, 0, ctx)
end

function UI.ReskinScrollBox(box)
    if not box or box.suuReskinBox then return end
    box.suuReskinBox = true
    local function all()
        if box.ForEachFrame then
            box:ForEachFrame(reskinRow)
        elseif box.ScrollTarget then
            for _, row in ipairs({ box.ScrollTarget:GetChildren() }) do reskinRow(row) end
        end
    end
    if box.Update then hooksecurefunc(box, "Update", all) end
    if box.RegisterCallback and box.Event and box.Event.OnDataRangeChanged then
        box:RegisterCallback(box.Event.OnDataRangeChanged, all, box)
    end
    box:HookScript("OnShow", function() C_Timer.After(0, all) end)
    if box.Shadows then box.Shadows:SetAlpha(0) end
    all()
end
