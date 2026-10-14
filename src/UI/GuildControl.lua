-- UI/GuildControl.lua
-- The Guild window's Settings tab (design component GuildControl): the
-- game's own guild control window (GuildControlUI) laid out in a host frame,
-- page by page. Every control that acts stays the game's (saving must come
-- from your clicks on them: GuildControlSetRank and the like are forbidden to
-- addons); SuuUI moves, sizes, restyles and relabels them, and adds only
-- headings, rules, cards and captions. Frame names from
-- /suu probe social guildui (2026-10-14).
--
--   local c = UI.GuildControl(host, GuildControlUI)
--   c:Layout()   -- again, whenever the game may have redrawn a page
--
-- Head row (30px, a gilt-faint rule under it): "Page" and the page dropdown;
-- on the permission pages "Rank" and its dropdown; the page's extra at the
-- right.
--   Guild ranks       two columns of five rows: "Rank 3", the name, move up,
--                     move down, remove; "New rank" in the next free row
--   Rank permissions  left: Members and Guild bank; right: the Officer card
--   Bank tabs, Discord  the dropdowns in the head row; the rest as the game
--                     draws it until probed

local _, ns = ...

local UI, T = ns.UI, ns.Tokens
local S = T.space

local GLYPHS = "Interface\\AddOns\\SuuUI\\Media\\Textures\\Glyphs\\"
-- the head row: the 24px dropdowns, then space-5 down to its rule
local BAND_H = 24
local HEAD_H = BAND_H + S["space-5"]
local TOP = -(HEAD_H + S["space-5"])
local ROW_H = 30
local ICON_B = 26
local CHECK_H = 24
local MAX_RANKS = 10

local function ask(r, method, ...)
    if not r or type(r[method]) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(r[method], r, ...)
    if ok then return a, b, c, d end
end

local function hideArt(f)
    if not f then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" and not r.suuArt then r:SetAlpha(0) end
    end
    if f.NineSlice then f.NineSlice:SetAlpha(0) end
    if f.Bg then f.Bg:SetAlpha(0) end
end

-- a dropdown's own label (the font string beside it, not its Text)
local function labelOf(d)
    if not d then return nil end
    for _, r in ipairs({ d:GetRegions() }) do
        if r:GetObjectType() == "FontString" and r ~= d.Text and r ~= d.text then return r end
    end
end

local function style(fs, styleName, color)
    if not fs then return end
    ns.Fonts.Apply(fs, styleName)
    fs:SetTextColor(UI.RGBA(color or "ink"))
    fs:SetShadowOffset(0, 0)
end

-- SuuUI's own decoration inside a page: drawn under the page's controls,
-- never under the mouse
local function deco(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetFrameLevel(page:GetFrameLevel())
    f:EnableMouse(false)
    f.suuOwn = true
    return f
end

-- One of the game's checkboxes: SuuUI's box, its label in `label` ink.
local function check(b, label)
    if not b then return end
    UI.ReskinCheckButton(b)
    b:SetSize(20, 20)
    local fs = b.Text or b.text or _G[(b:GetName() or "") .. "Text"]
    if fs then
        style(fs, "label", "ink")
        if label then fs:SetText(label) end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "RIGHT", S["space-3"], 0)
    end
end

local function place(f, page, x, y)
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
end

-- One of the game's small buttons (move up, move down, remove) as a 26px
-- icon button: surface-raised, gilt-line edge, a glyph in ink-muted; gilt
-- (or ember for remove) on hover; dimmed while the game has it disabled,
-- its tooltip saying why.
local function iconButton(b, glyph, danger, why)
    if not b then return end
    b:SetSize(ICON_B, ICON_B)
    b.suuWhy = why
    if b.suuIconButton then b.suuIconButton.draw() return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = ask(b, get)
        if t then t:SetAlpha(0) end
    end
    hideArt(b)
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetColorTexture(UI.RGBA("surface-raised"))
    bg:SetAllPoints()
    bg.suuArt = true
    local edge = UI.Border(b, "gilt-line")
    local g = b:CreateTexture(nil, "OVERLAY", nil, 7)
    g:SetTexture(GLYPHS .. glyph .. ".tga")
    g:SetSize(14, 14)
    g:SetPoint("CENTER")
    g.suuArt = true
    local st = { hover = false }
    st.draw = function()
        local on = ask(b, "IsEnabled") ~= false
        b:SetAlpha(on and 1 or T.opacity["opacity-disabled"])
        local hot = on and st.hover
        edge:SetColor(hot and (danger and "ember" or "gilt") or "gilt-line")
        g:SetVertexColor(UI.RGBA(hot and (danger and "ember-text" or "ink") or "ink-muted"))
    end
    b:HookScript("OnEnter", function(self)
        st.hover = true
        st.draw()
        if ask(self, "IsEnabled") == false and self.suuWhy then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.suuWhy, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function()
        st.hover = false
        st.draw()
        GameTooltip:Hide()
    end)
    hooksecurefunc(b, "SetEnabled", st.draw)
    if b.Enable then hooksecurefunc(b, "Enable", st.draw) end
    if b.Disable then hooksecurefunc(b, "Disable", st.draw) end
    b.suuIconButton = st
    st.draw()
end

-- Words after the first in lower case, names kept ("Edit Guild Info" ->
-- "Edit guild info", "Link Guild Chat to Discord" -> "Link guild chat to
-- Discord").
local KEEP = { Discord = true }
local function sentence(s)
    local first = true
    return (s:gsub("%a[%w']*", function(w)
        if first then first = false return w end
        if KEEP[w] then return w end
        return w:lower()
    end))
end

--------------------------------------------------------------------------------
-- The component
--------------------------------------------------------------------------------

local GuildControl = {}

function UI.GuildControl(host, ui)
    local c = setmetatable({ host = host, ui = ui }, { __index = GuildControl })
    ui:SetParent(host)
    ui.suuOwn = true
    -- the window's own frame: away; its title and bar give way to the head row
    hideArt(ui)
    for _, part in ipairs({ ui.NineSlice, ui.TitleContainer, ui.TopTileStreaks, ui.PortraitContainer }) do
        if part then part:SetAlpha(0) end
    end
    for _, ch in ipairs({ ui:GetChildren() }) do
        local name = ch:GetName() or ""
        if name:find("CloseButton") then ch:SetAlpha(0); ch:EnableMouse(false) end
    end
    if _G.GuildControlUITitle then _G.GuildControlUITitle:SetAlpha(0) end
    if _G.GuildControlUIHbar then _G.GuildControlUIHbar:SetAlpha(0) end
    -- the head row
    local head = deco(ui)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_H)
    head:SetFrameLevel(ui:GetFrameLevel() + 1)
    c.head = head
    local band = CreateFrame("Frame", nil, head)
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(BAND_H)
    band:EnableMouse(false)
    c.band = band
    c.pageLabel = UI.Text(band, "caption", "ink-muted")
    c.pageLabel:SetValue("Page")
    c.pageLabel:SetPoint("LEFT", 0, 0)
    c.extra = UI.Text(band, "caption", "ink-muted")
    c.extra:SetPoint("RIGHT", 0, 0)
    local rule = head:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(UI.RGBA("gilt-faint"))
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    for _, fn in ipairs({ "GuildControlUI_RankOrder_Update", "GuildControlUI_RankPermissions_Update",
                          "GuildControlUI_BankTabPermissions_Update", "GuildControlUI_Discord_Update" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, function() c:Layout() end) end
    end
    for _, key in ipairs({ "orderFrame", "rankPermFrame", "bankTabFrame", "discordFrame" }) do
        local page = ui[key]
        if page then page:HookScript("OnShow", function() c:Layout() end) end
    end
    ui:HookScript("OnShow", function() c:Layout() end)
    c:Layout()
    return c
end

-- the dropdowns of the head row: Page, then Rank on the pages that have one
function GuildControl:HeadRow(rankDropdown)
    local ui = self.ui
    local nav = _G.GuildControlUINavigationDropdown or ui.dropdown
    if nav then
        UI.ReskinDropdown(nav)
        nav:SetSize(200, 24)
        nav:ClearAllPoints()
        nav:SetPoint("LEFT", self.pageLabel, "RIGHT", S["space-4"], 0)
    end
    if rankDropdown then
        UI.ReskinDropdown(rankDropdown)
        rankDropdown:SetSize(180, 24)
        local label = labelOf(rankDropdown)
        if label then
            style(label, "caption", "ink-muted")
            label:SetText("Rank")
            label:SetWidth(0)
            label:ClearAllPoints()
            label:SetPoint("LEFT", nav, "RIGHT", S["space-5"], 0)
            rankDropdown:ClearAllPoints()
            rankDropdown:SetPoint("LEFT", label, "RIGHT", S["space-4"], 0)
        else
            rankDropdown:ClearAllPoints()
            rankDropdown:SetPoint("LEFT", nav, "RIGHT", S["space-5"], 0)
        end
    end
end

function GuildControl:Layout()
    local ui = self.ui
    if self.busy or not ui then return end
    self.busy = true
    ui:ClearAllPoints()
    ui:SetAllPoints(self.host)
    for _, key in ipairs({ "orderFrame", "rankPermFrame", "bankTabFrame", "discordFrame" }) do
        local page = ui[key]
        if page then
            page:ClearAllPoints()
            page:SetAllPoints(ui)
        end
    end
    self.extra:SetValue("")
    local cur = ui.currFrame
    if cur and cur == ui.orderFrame then self:Ranks(cur)
    elseif cur and cur == ui.rankPermFrame then self:Permissions(cur)
    elseif cur and cur == ui.bankTabFrame then self:Bank(cur)
    elseif cur and cur == ui.discordFrame then self:Discord(cur)
    else self:HeadRow() end
    self.busy = false
end

--------------------------------------------------------------------------------
-- Guild ranks
--------------------------------------------------------------------------------

function GuildControl:Ranks(page)
    self:HeadRow()
    hideArt(page)
    local ok, count = pcall(GuildControlGetNumRanks)
    local n = ok and tonumber(count) or 0
    self.extra:SetValue(("%d of %d ranks"):format(n, MAX_RANKS))
    local colW = math.floor((page:GetWidth() - S["space-6"]) / 2)
    if colW < 200 then colW = 360 end
    local function slot(i)
        local col = (i - 1) >= 5 and 1 or 0
        local row = (i - 1) % 5
        return col * (colW + S["space-6"]), TOP - row * (ROW_H + S["space-3"])
    end
    local base = page:GetName() or "GuildControlUIRankOrderFrame"
    for i = 1, MAX_RANKS do
        local row = _G[base .. "Rank" .. i]
        if row and i <= n then
            local x, y = slot(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
            row:SetSize(colW, ROW_H)
            hideArt(row)
            local label = row.rankLabel
            if label then
                style(label, "numeric", "ink-muted")
                label:SetText("Rank " .. i)
                label:SetJustifyH("LEFT")
                label:SetWidth(52)
                label:ClearAllPoints()
                label:SetPoint("LEFT", row, "LEFT", 0, 0)
            end
            local del = _G[base .. "Rank" .. i .. "DeleteButton"]
            local down = _G[base .. "Rank" .. i .. "ShiftDownButton"]
            local up = _G[base .. "Rank" .. i .. "ShiftUpButton"]
            iconButton(del, "trash", true, i == 1 and "The guild master's rank can't be removed."
                or (i == n and "The lowest rank can't be removed." or "This rank can't be removed now."))
            iconButton(down, "chevronDown", false, i == 1 and "The guild master's rank stays first."
                or "This is already the lowest rank.")
            iconButton(up, "chevronUp", false, i == 1 and "The guild master's rank stays first."
                or "Nothing moves above the guild master's rank.")
            if del then del:ClearAllPoints(); del:SetPoint("RIGHT", row, "RIGHT", 0, 0) end
            if down then down:ClearAllPoints(); down:SetPoint("RIGHT", del or row, del and "LEFT" or "RIGHT", -S["space-2"], 0) end
            if up then up:ClearAllPoints(); up:SetPoint("RIGHT", down or row, down and "LEFT" or "RIGHT", -S["space-2"], 0) end
            local edit = _G[base .. "Rank" .. i .. "NameEditBox"]
            if edit then
                UI.ReskinEditBox(edit)
                edit:SetHeight(ICON_B)
                edit:ClearAllPoints()
                edit:SetPoint("LEFT", row, "LEFT", 52 + S["space-3"] + 4, 0)
                edit:SetPoint("RIGHT", up or row, up and "LEFT" or "RIGHT", -S["space-3"], 0)
            end
        end
    end
    -- New rank: in the next free row
    local new = _G[base .. "NewButton"]
    if new then
        UI.ReskinButton(new)
        local fs = ask(new, "GetFontString")
        if fs then fs:SetText("New rank") end
        if not new.suuPlus then
            new.suuPlus = new:CreateTexture(nil, "OVERLAY", nil, 7)
            new.suuPlus:SetTexture(GLYPHS .. "plus.tga")
            new.suuPlus:SetSize(12, 12)
            new.suuPlus:SetVertexColor(UI.RGBA("ink-muted"))
        end
        new:SetSize(120, ICON_B)
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", 8, 0)
            new.suuPlus:ClearAllPoints()
            new.suuPlus:SetPoint("RIGHT", fs, "LEFT", -S["space-3"], 0)
        end
        if n < MAX_RANKS then
            local x, y = slot(n + 1)
            new:ClearAllPoints()
            new:SetPoint("TOPLEFT", page, "TOPLEFT", x + 52 + S["space-3"], y - (ROW_H - ICON_B) / 2)
        end
    end
    if not self.rankFoot then
        local foot = deco(page)
        foot:SetAllPoints(page)
        local fs = UI.Text(foot, "caption", "ink-muted")
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", 0, TOP - 5 * (ROW_H + S["space-3"]) - S["space-4"])
        fs:SetValue("Rank 1 is the guild master's. New members join at the lowest rank.")
        self.rankFoot = foot
    end
end

--------------------------------------------------------------------------------
-- Rank permissions
--------------------------------------------------------------------------------

local MEMBERS = {
    { 5, "Promote" }, { 6, "Demote" },
    { 7, "Invite member" }, { 8, "Remove member" },
    { 2, "Guild chat speak" }, { 21, "Recruitment" },
}

function GuildControl:Permissions(page)
    local base = page:GetName() or "GuildControlUIRankSettingsFrame"
    self:HeadRow(_G[base .. "RankDropdown"])
    hideArt(page)
    local w = page:GetWidth()
    local colW = math.floor((w - S["space-6"]) / 2)
    if colW < 200 then colW = 360 end
    local half = math.floor(colW / 2)
    local d = self.permDeco
    if not d then
        d = deco(page)
        d:SetAllPoints(page)
        d.members = UI.SectionHeader(d, "Members", nil, colW)
        d.bank = UI.SectionHeader(d, "Guild bank", nil, colW)
        -- the Officer card
        d.card = CreateFrame("Frame", nil, d)
        d.card:SetFrameLevel(page:GetFrameLevel())
        UI.Fill(d.card, "surface-sunk"):SetAllPoints()
        d.cardEdge = UI.Border(d.card, "gilt-faint")
        d.intro = UI.Text(d.card, "caption", "ink-muted")
        d.intro:SetValue("Officers of this rank can:")
        d.powers = {}
        d.g = UI.Text(d, "label", "coin-gold")
        d.g:SetValue("g")
        d.aDay = UI.Text(d, "caption", "ink-muted")
        d.aDay:SetValue("a day")
        self.permDeco = d
    end
    -- left: Members
    d.members:SetWidth(colW)
    d.members:ClearAllPoints()
    d.members:SetPoint("TOPLEFT", page, "TOPLEFT", 0, TOP)
    local y = TOP - T.type.header.lineHeight - S["space-4"]
    for i, m in ipairs(MEMBERS) do
        local b = _G[base .. "Checkbox" .. m[1]]
        check(b, m[2])
        place(b, page, ((i - 1) % 2) * half, y - math.floor((i - 1) / 2) * CHECK_H)
    end
    y = y - 3 * CHECK_H - S["space-6"]
    -- left: Guild bank
    d.bank:SetWidth(colW)
    d.bank:ClearAllPoints()
    d.bank:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    if _G[base .. "BankLabel"] then _G[base .. "BankLabel"]:SetAlpha(0) end
    y = y - T.type.header.lineHeight - S["space-4"]
    local repair, tabs, withdraw = _G[base .. "Checkbox15"], _G[base .. "Checkbox19"], _G[base .. "Checkbox16"]
    check(repair, "Guild bank repair")
    check(tabs, "Modify bank tabs")
    check(withdraw, "Withdraw gold")
    place(repair, page, 0, y)
    place(tabs, page, half, y)
    place(withdraw, page, 0, y - CHECK_H)
    local gold = _G[base .. "GoldBox"]
    if gold then
        UI.ReskinEditBox(gold)
        gold:SetSize(84, 22)
        gold:ClearAllPoints()
        gold:SetPoint("TOPLEFT", page, "TOPLEFT", half + 4, y - CHECK_H + 1)
        if gold.parentLabel then gold.parentLabel:SetAlpha(0) end
        d.g:ClearAllPoints()
        d.g:SetPoint("LEFT", gold, "RIGHT", S["space-3"], 0)
        d.aDay:ClearAllPoints()
        d.aDay:SetPoint("LEFT", d.g, "RIGHT", S["space-3"], 0)
        local banking = gold:IsShown()
        d.g:SetShown(banking)
        d.aDay:SetShown(banking)
    end
    d.bank:SetShown(repair == nil or repair:IsShown())
    -- right: the Officer card, the game's list of powers as a muted list
    local x = colW + S["space-6"]
    local pad = S["space-5"]
    local officer = _G[base .. "OfficerCheckbox"]
    check(officer, "Is officer")
    d.card:ClearAllPoints()
    d.card:SetPoint("TOPLEFT", page, "TOPLEFT", x, TOP)
    d.card:SetWidth(colW)
    place(officer, d.card, pad, -pad)
    d.intro:ClearAllPoints()
    d.intro:SetPoint("TOPLEFT", d.card, "TOPLEFT", pad, -pad - 20 - S["space-4"])
    local list = page.OfficerPermissions
    local lines = {}
    if list then
        list:SetAlpha(0)
        local text = list:GetText() or ""
        for line in (text:gsub("|n", "\n")):gmatch("[^\n]+") do
            line = line:gsub("^%s*%-%s*", "")
            if line ~= "" then lines[#lines + 1] = sentence(line) end
        end
    end
    local lh = T.type.caption.lineHeight + S["space-1"]
    for i, line in ipairs(lines) do
        local fs = d.powers[i]
        if not fs then
            fs = UI.Text(d.card, "caption", "ink-muted")
            d.powers[i] = fs
        end
        fs:SetValue("•  " .. line)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", d.intro, "BOTTOMLEFT", S["space-3"], -S["space-3"] - (i - 1) * lh)
        fs:Show()
    end
    for i = #lines + 1, #d.powers do d.powers[i]:Hide() end
    d.card:SetHeight(pad + 20 + S["space-4"] + T.type.caption.lineHeight + S["space-3"] + #lines * lh + pad)
    local on = officer and ask(officer, "GetChecked")
    d.cardEdge:SetColor(on and "gilt-line" or "gilt-faint")
    if officer and not officer.suuCardHook then
        officer.suuCardHook = true
        officer:HookScript("OnClick", function(b) d.cardEdge:SetColor(ask(b, "GetChecked") and "gilt-line" or "gilt-faint") end)
    end
    -- the head row's right: Requires authenticator
    local auth = _G[base .. "Checkbox18"]
    if auth then
        check(auth, "Requires authenticator")
        local fs = auth.Text or _G[base .. "Checkbox18Text"]
        local tw = fs and fs:GetStringWidth() or 130
        auth:ClearAllPoints()
        auth:SetPoint("RIGHT", self.band, "RIGHT", -(tw + S["space-3"]), 0)
    end
end

--------------------------------------------------------------------------------
-- Bank tab permissions and Discord: the head row and their area; their
-- contents follow once probed
--------------------------------------------------------------------------------

function GuildControl:Bank(page)
    local base = page:GetName() or "GuildControlUIRankBankFrame"
    self:HeadRow(_G[base .. "RankDropdown"])
    local inset = _G[base .. "Inset"]
    if inset then
        hideArt(inset)
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", page, "TOPLEFT", 0, TOP)
        inset:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        local scroll = _G[base .. "InsetScrollFrame"]
        if scroll then
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -16, 0)
            if scroll.ScrollBar then UI.ReskinScrollBar(scroll.ScrollBar) end
        end
    end
end

function GuildControl:Discord(page)
    self:HeadRow()
    local base = page:GetName() or "GuildControlUIRankDiscordFrame"
    local server, channel, link = _G[base .. "ServerDropdown"], _G[base .. "ChannelDropdown"], _G[base .. "ChannelButton"]
    -- not linked: the game's link flow in a centred 420px card
    local d = self.discordDeco
    if not d then
        d = deco(page)
        d:SetSize(420, 230)
        UI.Fill(d, "surface-sunk"):SetAllPoints()
        UI.Border(d, "gilt-faint")
        d.title = UI.Text(d, "header", "gilt-text")
        d.title:SetValue("Not linked to Discord")
        d.title:SetPoint("TOP", 0, -S["space-5"])
        self.discordDeco = d
    end
    d:ClearAllPoints()
    d:SetPoint("TOP", page, "TOP", 0, TOP)
    local notLinked = server and server:IsShown()
    d:SetShown(notLinked and true or false)
    if not notLinked then return end
    local pad, w = S["space-5"], 420 - 2 * S["space-5"]
    local function field(dd, text, y)
        if not dd then return end
        UI.ReskinDropdown(dd)
        dd:SetSize(w, 24)
        dd:ClearAllPoints()
        dd:SetPoint("TOPLEFT", d, "TOPLEFT", pad, y - 16)
        local label = labelOf(dd)
        if label then
            style(label, "caption", "ink-muted")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, S["space-2"])
        end
    end
    field(server, "Discord server", -48)
    local listTitle, err = page.channelListTitle, page.noChannelsError
    if listTitle then
        style(listTitle, "caption", "ink-muted")
        listTitle:ClearAllPoints()
        listTitle:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -100)
        listTitle:SetWidth(w)
    end
    field(channel, "Discord channel", -118)
    if err then
        style(err, "caption", "ember-text")
        err:ClearAllPoints()
        err:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -124)
        err:SetWidth(w)
    end
    if link then
        UI.ReskinButton(link)
        link:SetSize(w, 26)
        link:ClearAllPoints()
        link:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", pad, pad)
    end
end
