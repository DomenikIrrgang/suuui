-- UI/Reskin.lua
-- Blizzard's list and detail parts in SuuUI's look, restyled in place (Phase
-- 3's windows): rows, collapsible category bars, status bars, check
-- buttons, the thin scrollbar, dividers. Clicks and data stay Blizzard's; a
-- pass only changes how things look, so it can run again whenever Blizzard
-- redraws (each ScrollBox update).
--
--   UI.Reskin(frame)              -- the frame and everything in it, once more
--                                 -- (frames marked suuOwn = true skipped)
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
            UI.PaintFill(t, "gilt-line")
            t:SetPoint("TOP")
            t:SetPoint("BOTTOM")
            t:SetWidth(2)
            -- under the mouse: gilt and a little wider, so it reads as
            -- something to grab (it showed no hover, found in game)
            if thumb.HookScript then
                thumb:HookScript("OnEnter", function() UI.PaintFill(t, "gilt"); t:SetWidth(4) end)
                thumb:HookScript("OnLeave", function() UI.PaintFill(t, "gilt-line"); t:SetWidth(2) end)
            end
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
        -- the track as tall as the fill, whatever the fill's height comes to
        -- be (a bar skinned while hidden reported none and got a guess)
        local track = CreateFrame("Frame", nil, bar)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        if fill then
            track:SetPoint("TOP", fill, "TOP")
            track:SetPoint("BOTTOM", fill, "BOTTOM")
        else
            track:SetHeight(math.min(14, bar:GetHeight()))
        end
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
        UI.Paint(f, BAR_COLORS[word or ""] or "progress-fill")
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
            UI.Paint(r, "ink")
            r:SetShadowColor(0, 0, 0, 1)
            r:SetShadowOffset(0, -1)
        end
    end
end

local fillBars = setmetatable({}, { __mode = "k" })
ns.Events.On("SUUUI_THEME_CHANGED", function()
    for bar in pairs(fillBars) do bar.suuTint() end
end, "UI.ReskinFillBar")

-- A bar Blizzard draws itself (a frame with a Fill texture it sizes and
-- tints: the reputation's standing bars, the skills' bars): the fill flat in
-- Blizzard's tint (the standing's colour) or its atlas's colour (the skills'
-- blue), a track in a gilt-hairline edge, the text centred.
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
        -- the colour: Blizzard's tint on a white atlas (the reputation's
        -- standings); a coloured atlas (the skills' blue, tinted white on
        -- top) keeps its colour as a token
        -- (set raw, not painted: the SetVertexColor hook below would tint
        -- again inside a repaint; fillBars tints again on a theme change)
        local flattening = false
        local function tint()
            local token = BAR_COLORS[bar.suuAtlasWord or ""]
            if not token then return end
            flattening = true
            fill:SetVertexColor(UI.RGBA(token))
            flattening = false
        end
        local function flat()
            if flattening then return end
            local a = (fill:GetAtlas() or ""):lower()
            if a ~= "" then bar.suuAtlasWord = a:match("stat%-bar%-(%a+)") end
            flattening = true
            fill:SetTexture(WHITE)
            flattening = false
            tint()
        end
        hooksecurefunc(fill, "SetAtlas", flat)
        hooksecurefunc(fill, "SetVertexColor", function() if not flattening then tint() end end)
        bar.suuFlat = flat
        bar.suuTint = tint
        fillBars[bar] = true
        -- Blizzard sizes the fill as a share of its FillArea's width once
        -- (SetFillPercent); a row filled in before it had a width got 0,
        -- which a texture draws at its own size (8 px of white: seen
        -- 2026-10-18, 3,210 / 6,000 as a sliver). Keep the share and size the
        -- fill again whenever the width changes; none: no fill.
        if bar.SetFillPercent and bar.FillArea then
            -- the share Blizzard set before this: the right edge of its
            -- texture coordinates (SetTexCoord(0, p, 1, 0)), read before
            -- the flat texture goes on
            local _, _, _, _, right = fill:GetTexCoord()
            bar.suuPercent = tonumber(right) and math.min(1, math.max(0, right)) or nil
            local function size()
                local w = (bar.suuPercent or 0) * (bar.FillArea:GetWidth() or 0)
                fill:SetAlpha(w >= 0.5 and 1 or 0)
                if w >= 0.5 then fill:SetWidth(w) end
            end
            hooksecurefunc(bar, "SetFillPercent", function(_, percent)
                bar.suuPercent = math.min(1, math.max(0, tonumber(percent) or 0))
                size()
            end)
            bar.FillArea:HookScript("OnSizeChanged", size)
            bar.suuSizeFill = size
        end
    end
    bar.suuFlat()
    if bar.suuSizeFill then bar.suuSizeFill() end
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "FontString" then
            ns.Fonts.Apply(r, "numeric")
            r:SetJustifyH("CENTER")
            -- on the track's middle (the reputation's figures sit right there;
            -- a pixel up was too high, found in game)
            r:ClearAllPoints()
            r:SetPoint("LEFT", bar.suuTrack, "LEFT", 0, 0)
            r:SetPoint("RIGHT", bar.suuTrack, "RIGHT", 0, 0)
            UI.Paint(r, "ink")
            r:SetShadowColor(0, 0, 0, 1)
            r:SetShadowOffset(0, -1)
        end
    end
end

-- Blizzard's dropdown (WowStyle): surface-sunk in a gilt-line edge, its text
-- in label ink, a chevron on the right.
function UI.ReskinDropdown(d, opts)
    if not d or d.suuDropdown then return end
    for _, r in ipairs({ d:GetRegions() }) do
        if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "Arrow", "Background" }) do
        if d[key] and d[key].SetAlpha then d[key]:SetAlpha(0) end
    end
    local text = d.Text or d.text
    if opts and opts.glyph then
        -- an icon-only dropdown (the map's filter): a glyph, its edge on hover
        if d.Icon and d.Icon.SetAlpha then d.Icon:SetAlpha(0) end
        local edge = UI.Border(d, "gilt-line")
        edge:SetShown(false)
        local glyph = d:CreateTexture(nil, "OVERLAY", nil, 7)
        glyph:SetTexture(GLYPHS .. opts.glyph .. ".tga")
        glyph:SetSize(14, 14)
        glyph:SetPoint("CENTER")
        UI.Paint(glyph, "ink-muted")
        glyph.suuArt = true
        d:HookScript("OnEnter", function() edge:SetShown(true); UI.Paint(glyph, "ink") end)
        d:HookScript("OnLeave", function() edge:SetShown(false); UI.Paint(glyph, "ink-muted") end)
        if text then text:SetAlpha(0) end
        text = nil
    else
        local bg = d:CreateTexture(nil, "BACKGROUND", nil, -7)
        UI.PaintFill(bg, "surface-sunk")
        bg:SetAllPoints()
        bg.suuArt = true
        local edge = UI.Border(d, "gilt-line")
        local chev = d:CreateTexture(nil, "OVERLAY", nil, 7)
        chev:SetTexture(GLYPHS .. "chevronDown.tga")
        chev:SetSize(12, 12)
        chev:SetPoint("RIGHT", -S["space-3"], 0)
        UI.Paint(chev, "ink-muted")
        chev.suuArt = true
        d:HookScript("OnEnter", function() edge:SetColor("gilt") end)
        d:HookScript("OnLeave", function() edge:SetColor("gilt-line") end)
    end
    if text then
        ns.Fonts.Apply(text, "label")
        UI.Paint(text, "ink")
        text:SetShadowOffset(0, 0)
    end
    -- the menu it opens: in SuuUI's look while it's this dropdown's
    local event = DropdownButtonMixin and DropdownButtonMixin.Event and DropdownButtonMixin.Event.OnMenuOpen
    if d.RegisterCallback and event then
        d:RegisterCallback(event, function()
            local manager = Menu and Menu.GetManager and Menu.GetManager()
            local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
            if not menu then return end
            UI.ReskinMenu(menu)
            -- its rows may come a frame later
            C_Timer.After(0, function() if menu:IsShown() then UI.ReskinMenu(menu) end end)
        end, d)
    end
    d.suuDropdown = true
end

-- One of Blizzard's menus (Menu.GetManager():GetOpenMenu(), probed
-- 2026-10-14: a common-dropdown-bg texture, 20px rows with a radio or check
-- and a highlight, the rows' text) in the context menu's look: glass, a
-- gilt-line edge, the gilt corner diamond, rows in body ink on arcane-soft
-- while hovered, the chosen one marked by an arcane check. The game reuses
-- its menu frames for every menu, so all of it is undone when it closes.
local menus = setmetatable({}, { __mode = "k" })
local rowMenu = setmetatable({}, { __mode = "k" }) -- a row: the menu state it belongs to now
local hooked = setmetatable({}, { __mode = "k" })

local function restoreMenu(st)
    for i = #st.undo, 1, -1 do pcall(st.undo[i]) end
    st.undo = {}
    st.panel:Hide()
    for _, t in pairs(st.marks) do t:Hide() end
    for _, t in pairs(st.chevrons or {}) do t:Hide() end
    st.hover:Hide()
    st.nMarks, st.nChevrons = 0, 0
    st.active = false
end

local function hideRegion(st, r)
    if r.suuArt then return end
    local a = r:GetAlpha()
    if a == 0 then return end
    r:SetAlpha(0)
    st.undo[#st.undo + 1] = function() r:SetAlpha(a) end
end

local function menuText(st, fs, color)
    local fo = fs:GetFontObject()
    local file, size, flags = fs:GetFont()
    local r, g, b, a = fs:GetTextColor()
    local sx, sy = fs:GetShadowOffset()
    st.undo[#st.undo + 1] = function()
        if fo then fs:SetFontObject(fo) elseif file then fs:SetFont(file, size, flags) end
        fs:SetTextColor(r, g, b, a)
        fs:SetShadowOffset(sx, sy)
    end
    ns.Fonts.Apply(fs, "body")
    -- (set raw: again on every open, and the game's shared menu rows get
    -- no hooks of SuuUI's)
    fs:SetTextColor(UI.RGBA(color))
    fs:SetShadowOffset(0, 0)
end

local function menuRow(st, row)
    local chosen, indicator
    local texts = {}
    for _, r in ipairs({ row:GetRegions() }) do
        local kind = r:GetObjectType()
        if kind == "Texture" and not r.suuArt then
            local atlas = (ask(r, "GetAtlas") or ""):lower()
            if atlas:find("common%-dropdown%-icon") then
                -- the chosen row's tick
                if r:IsShown() then chosen = true end
                indicator = indicator or r
                hideRegion(st, r)
            elseif atlas:find("common%-dropdown%-tick") then
                indicator = r
                hideRegion(st, r)
            elseif r:GetDrawLayer() == "HIGHLIGHT" or not r:IsShown() then
                hideRegion(st, r)
            end
        elseif kind == "FontString" then
            texts[#texts + 1] = r
        end
    end
    for _, fs in ipairs(texts) do menuText(st, fs, "ink") end
    -- a submenu's arrow (a plain texture, the game's yellow): SuuUI's chevron
    local arrow = row.arrow
    if arrow and arrow.GetObjectType and arrow:IsShown() then
        hideRegion(st, arrow)
        st.nChevrons = (st.nChevrons or 0) + 1
        local chev = st.chevrons[st.nChevrons]
        if not chev then
            chev = st.panel:CreateTexture(nil, "OVERLAY", nil, 7)
            chev:SetTexture(GLYPHS .. "chevronRight.tga")
            chev:SetSize(12, 12)
            UI.Paint(chev, "ink-muted")
            st.chevrons[st.nChevrons] = chev
        end
        chev:ClearAllPoints()
        chev:SetPoint("CENTER", arrow, "CENTER", 0, 0)
        chev:Show()
    end
    -- SuuUI's hover and mark: on its own panel behind the rows (the game
    -- forbids new textures on its menu rows)
    rowMenu[row] = st
    if not hooked[row] then
        hooked[row] = true
        row:HookScript("OnEnter", function(self)
            local owner = rowMenu[self]
            if owner and owner.active then
                owner.hover:ClearAllPoints()
                owner.hover:SetAllPoints(self)
                owner.hover:Show()
            end
        end)
        row:HookScript("OnLeave", function(self)
            local owner = rowMenu[self]
            if owner then owner.hover:Hide() end
        end)
    end
    if chosen then
        st.nMarks = st.nMarks + 1
        local mark = st.marks[st.nMarks]
        if not mark then
            mark = st.panel:CreateTexture(nil, "OVERLAY", nil, 7)
            mark:SetTexture(GLYPHS .. "check.tga")
            mark:SetSize(12, 12)
            UI.Paint(mark, "arcane")
            st.marks[st.nMarks] = mark
        end
        mark:ClearAllPoints()
        if indicator then mark:SetPoint("CENTER", indicator, "CENTER", 0, 0) else mark:SetPoint("LEFT", row, "LEFT", 2, 0) end
        mark:Show()
    end
end

-- A submenu opened from a menu SuuUI restyled (the Who filter's Class,
-- Race, Zone, Sort): restyled too. Every menu frame announces itself.
local function openRoot()
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    return manager and manager.GetOpenMenu and manager:GetOpenMenu()
end
if EventRegistry and EventRegistry.RegisterCallback then
    -- (the event hands over the menu's frame, which has no GetLevel: any
    -- menu other than the open root, while the root is restyled)
    EventRegistry:RegisterCallback("MenuProxy.OnShow", function(_, menu)
        if not (menu and menu.GetRegions) then return end
        local root = openRoot()
        local st = root and root ~= menu and menus[root]
        if st and st.active then
            UI.ReskinMenu(menu)
            C_Timer.After(0, function() if menu:IsShown() then UI.ReskinMenu(menu) end end)
        end
    end, "SuuUI.Reskin")
end

function UI.ReskinMenu(menu)
    if not menu or ask(menu, "IsForbidden") then return end
    local st = menus[menu]
    if not st then
        st = { undo = {}, marks = {}, nMarks = 0, chevrons = {}, nChevrons = 0 }
        local panel = CreateFrame("Frame", nil, menu)
        panel:SetAllPoints()
        panel:SetFrameLevel(menu:GetFrameLevel())
        panel:EnableMouse(false)
        UI.Fill(panel, "surface-glass"):SetAllPoints()
        UI.Border(panel, "gilt-line")
        UI.Shadow(panel, "shadow-panel")
        UI.Diamond(panel, 7, "gilt"):SetPoint("CENTER", panel, "TOPLEFT", 0, 0)
        st.hover = panel:CreateTexture(nil, "ARTWORK")
        UI.PaintFill(st.hover, "arcane-soft")
        st.hover:Hide()
        st.panel = panel
        menus[menu] = st
        menu:HookScript("OnHide", function() if st.active then restoreMenu(st) end end)
        -- a choice that refreshes the menu (a sort order) sets its rows up
        -- again: marked again
        if menu.ReinitializeAll then
            hooksecurefunc(menu, "ReinitializeAll", function()
                if st.active then C_Timer.After(0, function() if st.active and menu:IsShown() then UI.ReskinMenu(menu) end end) end
            end)
        end
    end
    -- a second pass (the rows came later) starts from the game's look again
    if st.active then restoreMenu(st) end
    st.active = true
    st.panel:Show()
    for _, r in ipairs({ menu:GetRegions() }) do
        if r:GetObjectType() == "Texture" then hideRegion(st, r) end
    end
    local rows = {}
    for _, c in ipairs({ menu:GetChildren() }) do
        if c:GetObjectType() == "Button" then rows[#rows + 1] = c end
    end
    local target = menu.ScrollBox and menu.ScrollBox.ScrollTarget
    if target and menu.ScrollBox:IsShown() then
        for _, c in ipairs({ target:GetChildren() }) do
            if c:GetObjectType() == "Button" then rows[#rows + 1] = c end
        end
    end
    for _, row in ipairs(rows) do menuRow(st, row) end
    -- the game's frame keeps room under its rows for its own drop shadow: the
    -- panel ends under the last row instead, as far below it as the first
    -- row is below the top
    local top, first, last = menu:GetTop(), nil, nil
    -- a row with words in it (the game ends some menus, the unit menus, with
    -- an empty spacer: the panel stopped a row too low, found in game)
    local function hasText(row)
        for _, r in ipairs({ row:GetRegions() }) do
            if r:GetObjectType() == "FontString" and r:IsShown() then
                local t = r:GetText()
                if t and t ~= "" then return true end
            end
        end
        for _, c in ipairs({ row:GetChildren() }) do
            for _, r in ipairs({ c:GetRegions() }) do
                if r:GetObjectType() == "FontString" and r:IsShown() then
                    local t = r:GetText()
                    if t and t ~= "" then return true end
                end
            end
        end
        return false
    end
    -- every line with words counts for the edges: the buttons, and titles
    -- and headings, which aren't buttons (a unit menu's name on top: the
    -- panel's padding came out 28 instead of 8, found with /suu probe unitmenu)
    local lines = {}
    for _, c in ipairs({ menu:GetChildren() }) do
        if c ~= st.panel then lines[#lines + 1] = c end
    end
    if target and menu.ScrollBox:IsShown() then
        for _, c in ipairs({ target:GetChildren() }) do lines[#lines + 1] = c end
    end
    for _, row in ipairs(lines) do
        local t, b = row:GetTop(), row:GetBottom()
        if row:IsShown() and t and b and hasText(row) then
            if not first or t > first:GetTop() then first = row end
            if not last or b < last:GetBottom() then last = row end
        end
    end
    st.panel:ClearAllPoints()
    -- (a scrolling menu's last row can sit below what shows: then all of it)
    local bottom = menu:GetBottom()
    if top and first and last and bottom and last:GetBottom() >= bottom then
        local pad = math.max(0, top - first:GetTop())
        st.panel:SetPoint("TOPLEFT", menu, "TOPLEFT")
        st.panel:SetPoint("RIGHT", menu, "RIGHT")
        st.panel:SetPoint("BOTTOM", last, "BOTTOM", 0, -pad)
    else
        st.panel:SetAllPoints(menu)
    end
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
        UI.PaintFill(well, "surface-sunk")
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
    UI.Paint(check, "arcane")
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
    UI.PaintFill(bg, "surface-raised")
    bg:SetAllPoints()
    local edge = UI.Border(b, "gilt-line")
    b:HookScript("OnEnter", function() edge:SetColor("gilt") end)
    b:HookScript("OnLeave", function() edge:SetColor("gilt-line") end)
    local function draw()
        b:SetAlpha(ask(b, "IsEnabled") == false and T.opacity["opacity-disabled"] or 1)
        local fs = ask(b, "GetFontString")
        if fs then
            ns.Fonts.Apply(fs, "label")
            UI.Paint(fs, "ink")
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
    -- a search box (its magnifier and "Search" placeholder): the field is the
    -- box itself, the text and placeholder space-3 in from its left
    local search = e.searchIcon or e.Instructions
    local bg = e:CreateTexture(nil, "BACKGROUND", nil, -7)
    UI.PaintFill(bg, "surface-sunk")
    if search then
        bg:SetAllPoints()
        e:SetTextInsets(S["space-3"], S["space-5"], 0, 0)
        local hint = e.Instructions
        if hint and hint.ClearAllPoints then
            hint:ClearAllPoints()
            hint:SetPoint("LEFT", S["space-3"], 0)
            hint:SetPoint("RIGHT", -S["space-3"], 0)
            hint:SetJustifyH("LEFT")
            ns.Fonts.Apply(hint, "body")
            UI.Paint(hint, "ink-muted")
            hint.suuSkip = true
        end
    else
        bg:SetPoint("TOPLEFT", -4, -1)
        bg:SetPoint("BOTTOMRIGHT", 0, 1)
    end
    local holder = CreateFrame("Frame", nil, e)
    holder:SetPoint("TOPLEFT", bg)
    holder:SetPoint("BOTTOMRIGHT", bg)
    holder:EnableMouse(false)
    local edge = UI.Border(holder, "gilt-line")
    e:HookScript("OnEditFocusGained", function() edge:SetColor("arcane") end)
    e:HookScript("OnEditFocusLost", function() edge:SetColor("gilt-line") end)
    e:SetFontObject(ns.Fonts.Get("body"))
    UI.Paint(e, "ink")
    e.suuEdit = true
end

-- A small collapse/expand button (Statistics' sub-categories): SuuUI's
-- minus or plus in gilt-text, following the state Blizzard sets.
function UI.ReskinCollapseButton(b)
    if not b or b.suuCollapse then return end
    local glyph = b:CreateTexture(nil, "OVERLAY", nil, 7)
    glyph:SetSize(12, 12)
    glyph:SetPoint("CENTER")
    UI.Paint(glyph, "gilt-text")
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

local function sameColor(token, r, g, b)
    local tr, tg, tb = UI.RGBA(token)
    return math.abs(r - tr) < 0.01 and math.abs(g - tg) < 0.01 and math.abs(b - tb) < 0.01
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
        UI.Paint(fs, "gilt-text")
    elseif not long and (size >= 14 or foName:find("Med") or foName:find("Large")) then
        ns.Fonts.Apply(fs, "header")
        UI.Paint(fs, "gilt-text")
    else
        local r, g, b = ask(fs, "GetTextColor")
        local token = textColor(r, g, b)
        -- a text an earlier pass coloured still has its token's colour: kept
        -- (a theme's colours may read as none of Blizzard's)
        if fs.suuToken and r and sameColor(fs.suuToken, r, g, b) then token = fs.suuToken end
        fs.suuToken = token
        ns.Fonts.Apply(fs, foName:find("Number") and "numeric" or (size < 11 and "caption" or (long and "body" or "label")))
        if token then UI.Paint(fs, token) else fs:SetTextColor(r, g, b) end
    end
    fs:SetShadowOffset(0, 0)
end

--------------------------------------------------------------------------------
-- A pass over a frame
--------------------------------------------------------------------------------

-- Blizzard's scrolling text (a side pane's description): it measures its
-- text for the font it has when the text is set, so after SuuUI's font goes
-- on the box was a line short and its first line out of view (the skills'
-- description, seen 2026-10-18). Measured again, from the top, a frame
-- after SuuUI's pass and after each text.
local function refitScrollingFont(f)
    local fs = ask(f, "GetFontString")
    local box = ask(f, "GetScrollBox")
    local container = ask(f, "GetFontStringContainer")
    if not (fs and box and container) then return end
    container:SetHeight(fs:GetStringHeight())
    local consts = ScrollBoxConstants or {}
    pcall(box.FullUpdate, box, consts.UpdateImmediately)
    pcall(box.ScrollToBegin, box, consts.NoScrollInterpolation)
end

local function reskinScrollingFont(f)
    if not f.suuScrollingFont then
        f.suuScrollingFont = true
        hooksecurefunc(f, "SetText", function() C_Timer.After(0, function() refitScrollingFont(f) end) end)
    end
    C_Timer.After(0, function() refitScrollingFont(f) end)
end

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
        UI.Paint(t, "gilt-text")
    elseif a:find("select") then
        -- the chosen fill goes behind what it marks (an icon, a row's text)
        UI.PaintFill(t, "arcane-soft")
        t:SetDrawLayer("BACKGROUND", 2)
    elseif layer == "HIGHLIGHT" or a:find("highlight") or a:find("hover") then
        UI.PaintFill(t, "surface-raised")
        t:SetAlpha(0.6)
    end
end

local function pass(f, depth, ctx)
    if depth > 6 or ask(f, "IsForbidden") then return end
    -- SuuUI's own frames inside a Blizzard window (pages, the skin's header):
    -- never restyled
    if f.suuOwn then return end
    local kind = ask(f, "GetObjectType")
    if f.GetFontStringContainer and f.ScrollBox and f.SetText then reskinScrollingFont(f) end
    -- Blizzard's coloured progress bar (a Fill it sizes itself: the
    -- reputation's and the skills' bars, the skills' a StatusBar)
    if f.Fill and f.FillArea and f.SetFillPercent then UI.ReskinFillBar(f); return end
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
            UI.PaintFill(f.suuHeadRule, "gilt-faint")
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

-- One of Blizzard's small dialogs (the guild's text editor for the message
-- of the day and the information) as a SuuUI panel: its frame art away,
-- surface-glass inside a gilt-line edge with the gilt corner diamond, its
-- title in `header` gilt-text, its corner close as SuuUI's cross, the box
-- inside on surface-sunk in a gilt-line edge, the rest (buttons, the text,
-- the scrollbar) by the usual pass. Its clicks stay Blizzard's.
local function dialogBox(c)
    -- a frame holding the text (Blizzard's inset box): its own art away
    if c.suuBox then return end
    c.suuBox = true
    if c.NineSlice then c.NineSlice:SetAlpha(0) end
    for _, r in ipairs({ c:GetRegions() }) do
        if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    local bg = c:CreateTexture(nil, "BACKGROUND", nil, -7)
    UI.PaintFill(bg, "surface-sunk")
    bg:SetAllPoints()
    bg.suuArt = true
    UI.Border(c, "gilt-line")
    -- the text inside: the box is its field already (no second edge)
    local function walk(fr, depth)
        if depth > 4 then return end
        for _, k in ipairs({ fr:GetChildren() }) do
            if k:GetObjectType() == "EditBox" then
                k.suuEdit = true
                k:SetFontObject(ns.Fonts.Get("body"))
                UI.Paint(k, "ink")
            end
            walk(k, depth + 1)
        end
    end
    walk(c, 0)
end

function UI.ReskinDialog(f)
    if not f or ask(f, "IsForbidden") then return end
    if not f.suuDialog then
        f.suuDialog = true
        for _, r in ipairs({ f:GetRegions() }) do
            local kind = r:GetObjectType()
            if kind == "Texture" then
                r:SetAlpha(0)
            elseif kind == "FontString" then
                ns.Fonts.Apply(r, "header")
                UI.Paint(r, "gilt-text")
                r:SetShadowOffset(0, 0)
                r.suuSkip = true
            end
        end
        for _, key in ipairs({ "NineSlice", "Border", "Bg", "TitleBg" }) do
            if f[key] and f[key].SetAlpha then f[key]:SetAlpha(0) end
        end
        local panel = CreateFrame("Frame", nil, f)
        panel:SetAllPoints()
        panel:SetFrameLevel(f:GetFrameLevel())
        panel:EnableMouse(false)
        panel.suuOwn = true
        UI.Fill(panel, "surface-glass"):SetAllPoints()
        UI.Border(panel, "gilt-line")
        UI.Shadow(panel, "shadow-panel")
        UI.Diamond(panel, 7, "gilt"):SetPoint("CENTER", panel, "TOPLEFT", 0, 0)
        for _, c in ipairs({ f:GetChildren() }) do
            local kind = c:GetObjectType()
            local name = c:GetName() or ""
            local text = ask(c, "GetText")
            if kind == "Button" and (name:find("Close") or c == f.CloseButton) and (not text or text == "") then
                -- the corner close: SuuUI's cross
                for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                    local t = ask(c, get)
                    if t then t:SetAlpha(0) end
                end
                for _, r in ipairs({ c:GetRegions() }) do
                    if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
                end
                c:SetSize(22, 22)
                c:ClearAllPoints()
                c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S["space-3"], -S["space-3"])
                local border = UI.Border(c, "gilt-line")
                border:SetShown(false)
                local cross = UI.Cross(c, 10, "ink-muted")
                cross:SetPoint("CENTER")
                c:HookScript("OnEnter", function() border:SetShown(true); cross:SetColor("ink") end)
                c:HookScript("OnLeave", function() border:SetShown(false); cross:SetColor("ink-muted") end)
            elseif kind == "Frame" or kind == "ScrollFrame" then
                if (c:GetWidth() or 0) > 100 and (c:GetHeight() or 0) > 40 then dialogBox(c) end
            end
        end
    end
    pass(f, 0, { rowDepth = 0 })
end

-- One of the game's shared popups (StaticPopup1-4: the guild note popup)
-- in SuuUI's look while it shows that dialog: solid surface inside a gilt-line edge
-- with the corner diamond, its text in body ink, the edit box as a sunk
-- field, Accept as the primary (arcane) button, the others quiet. The game
-- reuses these frames for every popup, so it's all undone when it hides.
-- SuuUI's art lives on its own child frames (shown only while it's ours).
local popups = setmetatable({}, { __mode = "k" })

local function skinFrame(parent, fill, edge, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:SetFrameLevel(level or parent:GetFrameLevel())
    f:EnableMouse(false)
    f.fill = UI.Fill(f, fill)
    f.fill:SetAllPoints()
    f.edge = UI.Border(f, edge)
    f:Hide()
    return f
end

local function restorePopup(st)
    for i = #st.undo, 1, -1 do pcall(st.undo[i]) end
    st.undo = {}
    for _, f in pairs(st.skins) do f:Hide() end
    st.active = false
end

local function popupButton(st, b, primary)
    if not (b and b:IsShown()) then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = ask(b, get)
        if t then hideRegion(st, t) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" then hideRegion(st, r) end
    end
    local skin = st.skins[b]
    if not skin then
        skin = skinFrame(b, primary and "arcane" or "surface-raised", primary and "arcane" or "gilt-line")
        st.skins[b] = skin
        b:HookScript("OnEnter", function() if st.active and not primary then skin.edge:SetColor("gilt") end end)
        b:HookScript("OnLeave", function() if st.active and not primary then skin.edge:SetColor("gilt-line") end end)
    end
    skin.edge:SetColor(primary and "arcane" or "gilt-line")
    skin:Show()
    local fs = ask(b, "GetFontString")
    if fs then menuText(st, fs, primary and "on-signal" or "ink"); ns.Fonts.Apply(fs, "label") end
end

function UI.ReskinPopup(dialog)
    if not dialog or ask(dialog, "IsForbidden") then return end
    local st = popups[dialog]
    if not st then
        st = { undo = {}, skins = {} }
        -- solid: it opens over windows, whose text showed through the glass
        local panel = skinFrame(dialog, "surface", "gilt-line")
        UI.Shadow(panel, "shadow-panel")
        UI.Diamond(panel, 7, "gilt"):SetPoint("CENTER", panel, "TOPLEFT", 0, 0)
        st.skins[dialog] = panel
        popups[dialog] = st
        dialog:HookScript("OnHide", function() if st.active then restorePopup(st) end end)
    end
    if st.active then restorePopup(st) end
    st.active = true
    st.skins[dialog]:Show()
    -- the game's frame art
    for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg" }) do
        local part = dialog[key]
        if part and part.SetAlpha then hideRegion(st, part) end
    end
    for _, r in ipairs({ dialog:GetRegions() }) do
        if r:GetObjectType() == "Texture" then hideRegion(st, r) end
    end
    local text = dialog.Text
    if text then menuText(st, text, "ink") end
    -- the edit box: a sunk field
    local edit = dialog.EditBox
    if edit and edit:IsShown() then
        if edit.NineSlice then hideRegion(st, edit.NineSlice) end
        for _, r in ipairs({ edit:GetRegions() }) do
            if r:GetObjectType() == "Texture" then hideRegion(st, r) end
        end
        local skin = st.skins[edit]
        if not skin then
            skin = skinFrame(edit, "surface-sunk", "gilt-line")
            skin:ClearAllPoints()
            skin:SetPoint("TOPLEFT", -4, 2)
            skin:SetPoint("BOTTOMRIGHT", 4, -2)
            st.skins[edit] = skin
        end
        skin:Show()
    end
    local container = dialog.ButtonContainer
    for i = 1, 4 do
        local b = (container and container["Button" .. i]) or dialog["button" .. i]
        popupButton(st, b, i == 1)
    end
end
