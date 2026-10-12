-- Units/Chat.lua
-- Chat (step 2.2): SuuUI's own chat display over Blizzard's chat.
--
-- Blizzard's chat keeps receiving and formatting every message (filters of
-- other addons, links, secret payloads during encounters), but invisibly:
-- its frames' text at alpha 0, their mouse, wheel and links off. Each finished
-- line is copied (a post-hook on the window's AddMessage) into SuuUI's own
-- ScrollingMessageFrame for that window, in SuuUI's panel: a glass panel
-- `chat-w` wide at the bottom left, SuuUI's tabs (real buttons, in SuuUI's
-- order: General, Global, then the rest, whispers last; each tab is one of
-- Blizzard's windows, so its own chat settings decide what goes where), the
-- input field behind Blizzard's restyled edit box (the input stays Blizzard's:
-- the game blocks addon-sent chat in lockdown and secure slash commands), and
-- an idle fade (ground, border, tabs and input go; the lines stay). Links in
-- SuuUI's windows open with SetItemRef; shift-click inserts them. A built-in
-- module written against the public API only.
--
-- Rules from EllesmereUIChat on this client (see IMPLEMENTATION_PLAN 2.2):
-- no FCF_* hooks, no writes to the tab alpha globals, no hooks on edit box
-- scripts, no fields on Blizzard frames, and chat frame geometry is never
-- read: ChatFrame1 is placed from the panel's own rectangle (SetPointBase,
-- two corners, no SetSize).

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "chat",
    name = "Chat",
    description = "Blizzard's chat in SuuUI's look: a glass panel, SuuUI tabs and input, fading while idle.",
    api = "0.10",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMLEFT", x = 28, y = 28 },
        logHeight = 160,
        fadeIdle = true,
        idleDelay = 10,
        globalTab = true, -- the numbered (global) channels in a "Global" tab, not in General
    },
})

local isSecret = issecretvalue or function() return false end
local BODY_FONT = "Interface\\AddOns\\SuuUI\\Media\\Fonts\\Figtree-Regular.ttf"
local PAD_X, PAD_TOP, PAD_BOTTOM = S["space-5"], S["space-2"], S["space-5"]
local TABS_H, INPUT_H, GAP = 24, 30, S["space-3"]
local TICK = 0.2

-- chat messages that wake the panel: to you and your group (public chat,
-- Trade, say and yell, would keep it awake for good)
local WAKE = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

local hidden = CreateFrame("Frame")
hidden:Hide()

local function chatFrames()
    local out = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then out[#out + 1] = cf end
    end
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf and cf.isTemporary then out[#out + 1] = cf end
    end
    return out
end

local function alphaOff(f)
    if not f then return end
    f:SetAlpha(0)
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
end

-- every texture region of a frame emptied (Blizzard's fades find nothing to show)
local function emptyTextures(f)
    if not f or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture("")
            if r.SetAtlas then pcall(r.SetAtlas, r, "") end
            r:SetAlpha(0)
        end
    end
end

--------------------------------------------------------------------------------
-- The panel (SuuUI's own frame, the mover)
--------------------------------------------------------------------------------

function M:PanelSize()
    local w = UI.Size("chat-w")
    local h = PAD_TOP + TABS_H + GAP + self:Get("logHeight") + GAP + INPUT_H + PAD_BOTTOM
    return w, h
end

function M:BuildPanel()
    local p = CreateFrame("Frame", "SuuUIChat", SuuUI.Root)
    p:SetFrameStrata("BACKGROUND")
    p:EnableMouse(false)
    p.deco = CreateFrame("Frame", nil, p)
    p.deco:SetAllPoints()
    p.ground = UI.Fill(p.deco, "surface-glass", "BACKGROUND")
    p.ground:SetAllPoints()
    p.border = UI.Border(p.deco, "gilt-line")
    -- the input field: surface-sunk, a gilt-line edge (Blizzard's edit box sits on it)
    p.field = CreateFrame("Frame", nil, p.deco)
    p.field:SetPoint("BOTTOMLEFT", PAD_X, PAD_BOTTOM)
    p.field:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_BOTTOM)
    p.field:SetHeight(INPUT_H)
    UI.Fill(p.field, "surface-sunk", "BACKGROUND"):SetAllPoints()
    UI.Border(p.field, "gilt-line")
    -- the tab bar: SuuUI's own tab buttons, above Blizzard's (invisible) dock
    p.tabs = CreateFrame("Frame", nil, p)
    p.tabs:SetFrameStrata("MEDIUM")
    p.tabs:SetPoint("TOPLEFT", PAD_X, -PAD_TOP)
    p.tabs:SetPoint("TOPRIGHT", -PAD_X, -PAD_TOP)
    p.tabs:SetHeight(TABS_H)
    p.tabButtons = {}
    -- the lines' area: SuuUI's message frames, one per Blizzard window
    p.log = CreateFrame("Frame", nil, p)
    p.log:SetFrameStrata("LOW")
    p.log:SetPoint("TOPLEFT", PAD_X, -(PAD_TOP + TABS_H + GAP))
    p.log:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_BOTTOM + INPUT_H + GAP)
    self.panel = p
end

--------------------------------------------------------------------------------
-- Blizzard's chat into it
--------------------------------------------------------------------------------

-- The log's rectangle in UIParent units, from the panel (SuuUI's own frame).
function M:LogRect()
    local p = self.panel
    local l, b, w, h = p:GetLeft(), p:GetBottom(), p:GetWidth(), p:GetHeight()
    if not (l and b) then return nil end
    local k = p:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left = (l + PAD_X) * k
    local right = (l + w - PAD_X) * k
    local bottom = (b + PAD_BOTTOM + INPUT_H + GAP) * k
    local top = bottom + self:Get("logHeight") * k
    return left, bottom, right, top
end

function M:PlaceChat()
    local cf = ChatFrame1
    if not cf or not self.panel then return end
    if InCombatLockdown() and cf:IsProtected() then self.pendingPlace = true return end
    self.pendingPlace = nil
    local left, bottom, right, top = self:LogRect()
    if not left then return end
    local clear = cf.ClearAllPointsBase or cf.ClearAllPoints
    local setPoint = cf.SetPointBase or cf.SetPoint
    self.placing = true
    clear(cf)
    setPoint(cf, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    setPoint(cf, "TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    self.placing = nil
end

-- One window's art away, its font SuuUI's (at Blizzard's size for it), its
-- edit box on the panel's field.
function M:SkinFrame(cf)
    local name = cf:GetName()
    if not name then return end
    emptyTextures(cf)
    if cf.Background then
        cf.Background:SetAlpha(0)
        emptyTextures(cf.Background)
    end
    local buttons = _G[name .. "ButtonFrame"]
    alphaOff(buttons)
    emptyTextures(buttons)
    -- Blizzard shows these again with its own fades: the scroll-to-bottom
    -- button hides itself whenever shown; the scrollbar's steppers go to a
    -- hidden frame, its track and thumb invisible (EllesmereUI's way)
    local sb = cf.ScrollToBottomButton
    if sb then
        alphaOff(sb)
        sb:Hide()
        self.sbHooked = self.sbHooked or {}
        if not self.sbHooked[sb] then
            self.sbHooked[sb] = true
            sb:HookScript("OnShow", sb.Hide)
        end
    end
    local bar = cf.ScrollBar
    if bar then
        for _, key in ipairs({ "Back", "Forward" }) do
            if bar[key] then bar[key]:SetParent(hidden) end
        end
        if bar.Track then alphaOff(bar.Track) end
        alphaOff(bar)
    end
    alphaOff(_G[name .. "ResizeButton"])
    self:ApplyFont(cf)
    -- inert: its text invisible, no mouse, wheel or links (SuuUI's copy is the
    -- one shown and clicked); chat frames can be protected in combat while a
    -- whisper window exists: then again after combat
    if cf.FontStringContainer then cf.FontStringContainer:SetAlpha(0) end
    local ok = pcall(function()
        cf:EnableMouse(false)
        if cf.EnableMouseWheel then cf:EnableMouseWheel(false) end
        if cf.SetHyperlinksEnabled then cf:SetHyperlinksEnabled(false) end
    end)
    if not ok then self.pendingSkin = true end
    self:Mirror(cf)
    -- the edit box (temporary windows' too: restyled only, never hooked)
    local id = cf:GetID()
    local eb = _G[name .. "EditBox"]
    if eb then
        for _, part in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
            alphaOff(_G[name .. "EditBox" .. part])
        end
        for _, key in ipairs({ "focusLeft", "focusMid", "focusRight" }) do
            if eb[key] then eb[key]:SetAlpha(0) end
        end
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 0, -GAP)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 0, -GAP)
        eb:SetHeight(INPUT_H)
        if eb.SetTextInsets then eb:SetTextInsets(S["space-4"], S["space-4"], 0, 0) end
        -- Up and Down recall what you sent (the edit box's own history),
        -- without Alt
        if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
        local size = (id and select(2, FCF_GetChatWindowInfo(id))) or 13
        if isSecret(size) or type(size) ~= "number" or size <= 0 then size = 13 end
        eb:SetFont(BODY_FONT, size, "")
        if eb.header then eb.header:SetFont(BODY_FONT, size, "") end
        if eb.headerSuffix then eb.headerSuffix:SetFont(BODY_FONT, size, "") end
    end
end

-- SuuUI's body face at Blizzard's size for the window (its own setting),
-- with the design's shadow. Checked again on each tick: the window's menu
-- changes the size.
function M:ApplyFont(cf)
    local id = cf:GetID()
    local size = (id and select(2, FCF_GetChatWindowInfo(id))) or 13
    if isSecret(size) or type(size) ~= "number" or size <= 0 then size = 13 end
    self.fontSizes = self.fontSizes or {}
    if self.fontSizes[cf] == size then return false end
    self.fontSizes[cf] = size
    cf:SetFont(BODY_FONT, size, "")
    cf:SetShadowOffset(1, -1)
    cf:SetShadowColor(0, 0, 0, 0.8)
    return true
end

function M:SkinAll()
    for _, cf in ipairs(chatFrames()) do self:SkinFrame(cf) end
    -- Blizzard's tab strip: invisible and out of the mouse's way (SuuUI's own
    -- tabs are the ones used)
    if GeneralDockManager then
        GeneralDockManager:SetAlpha(0)
        for _, cf in ipairs(GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES or {}) do
            local tab = cf:GetName() and _G[cf:GetName() .. "Tab"]
            if tab then pcall(tab.EnableMouse, tab, false) end
        end
    end
    for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
                            "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
        alphaOff(_G[name])
    end
end

--------------------------------------------------------------------------------
-- Mirrors: SuuUI's message frame for each Blizzard window
--------------------------------------------------------------------------------

local MAX_LINES = 500

local function linkClick(frame, link, text, button)
    if isSecret(link) then return end
    pcall(SetItemRef, link, text, button, frame)
end

local function linkEnter(frame, link)
    if isSecret(link) or type(link) ~= "string" then return end
    local kind = link:match("^(%a+):")
    if kind == "item" or kind == "spell" or kind == "achievement" or kind == "quest" or kind == "currency" then
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end
end

function M:MirrorFrame(cf)
    local m = CreateFrame("ScrollingMessageFrame", nil, self.panel.log)
    m:SetAllPoints()
    m:SetJustifyH("LEFT")
    m:SetFading(false)
    m:SetMaxLines(MAX_LINES)
    m:SetIndentedWordWrap(true)
    m:SetHyperlinksEnabled(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    m:SetScript("OnHyperlinkClick", linkClick)
    m:SetScript("OnHyperlinkEnter", linkEnter)
    m:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    m:Hide()
    return m
end

-- Every line Blizzard adds to the window, copied (a secret one whole), and
-- what it already holds.
function M:Mirror(cf)
    self.mirrors = self.mirrors or {}
    if self.mirrors[cf] then return end
    local m = self:MirrorFrame(cf)
    self.mirrors[cf] = m
    self:ApplyMirrorFont(cf)
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    for i = 1, n do
        local ok, text, r, g, b = pcall(cf.GetMessageInfo, cf, i)
        if ok and text ~= nil then m:AddMessage(text, r, g, b) end
    end
    -- the combat log clears and refills its window on a filter change
    hooksecurefunc(cf, "Clear", function() m:Clear() end)
    hooksecurefunc(cf, "AddMessage", function(_, text, r, g, b)
        if text == nil then return end
        m:AddMessage(text, r, g, b)
        if m ~= self.activeMirror and cf ~= ChatFrame2 then
            self.unread = self.unread or {}
            self.unread[cf] = true
        end
    end)
end

function M:ApplyMirrorFont(cf)
    local m = self.mirrors and self.mirrors[cf]
    if not m then return end
    local id = cf:GetID()
    local size = (id and select(2, FCF_GetChatWindowInfo(id))) or 13
    if isSecret(size) or type(size) ~= "number" or size <= 0 then size = 13 end
    m:SetFont(BODY_FONT, size, "")
    m:SetShadowOffset(1, -1)
    m:SetShadowColor(0, 0, 0, 0.8)
end

--------------------------------------------------------------------------------
-- Tabs: SuuUI's own buttons, one per Blizzard window, in SuuUI's order
--------------------------------------------------------------------------------

-- The windows as tabs: docked ones (General first, Global second, the rest in
-- the dock's order), then whisper windows.
function M:Windows()
    local out, seen = {}, {}
    local function add(cf)
        if cf and not seen[cf] then seen[cf] = true; out[#out + 1] = cf end
    end
    local docked = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES or { ChatFrame1 }
    local function named(wanted)
        for _, cf in ipairs(docked) do
            local name = GetChatWindowInfo(cf:GetID())
            if type(name) == "string" and not isSecret(name) and name:lower() == wanted then return cf end
        end
    end
    add(ChatFrame1)
    add(named("global"))
    for _, cf in ipairs(docked) do if not cf.isTemporary then add(cf) end end
    for _, cf in ipairs(docked) do add(cf) end
    return out
end

local function tabButton(m, i)
    local p = m.panel
    local b = p.tabButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, p.tabs)
    b:SetHeight(TABS_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.label = UI.Text(b, "header", "ink-muted")
    b.label:SetFont(SuuUI.Fonts.Get("header"):GetFont(), 12, "")
    b.label:SetShadowed(true)
    b.label:SetPoint("LEFT", 0, 1)
    b.label:SetWordWrap(false)
    b.line = UI.Hairline(b, "gilt-line", "both")
    b.line:SetPoint("BOTTOMLEFT", 0, 2)
    b.line:SetPoint("BOTTOMRIGHT", 0, 2)
    b.jewel = UI.Diamond(b, 5, "gilt")
    b.jewel:SetPoint("CENTER", b, "BOTTOM", 0, 2)
    b.unread = UI.Diamond(b, 4, "ink")
    b.unread:SetPoint("LEFT", b.label, "RIGHT", S["space-2"], 1)
    b:SetScript("OnEnter", function(self) if not self.active then self.label:SetColor("ink") end end)
    b:SetScript("OnLeave", function(self) if not self.active then self.label:SetColor("ink-muted") end end)
    b:SetScript("OnClick", function(self) m:Select(self.cf) end)
    p.tabButtons[i] = b
    return b
end

-- The combat log's filter bar (Blizzard's: My actions, What happened to me?
-- …), shown at the top of the lines while the Combat Log tab is: Blizzard
-- shows it only while its own dock has the combat log selected, which it no
-- longer is. The lines move down to make room.
local FILTER_H = 24
function M:CombatFilterBar(show)
    local bar = _G.CombatLogQuickButtonFrame_Custom
    local mirror = self.mirrors and self.mirrors[ChatFrame2]
    if mirror then
        mirror:ClearAllPoints()
        mirror:SetPoint("TOPLEFT", 0, (show and bar) and -(FILTER_H + S["space-1"]) or 0)
        mirror:SetPoint("BOTTOMRIGHT")
    end
    if not bar then return end
    if show then
        -- out of ChatFrame2 (always hidden now: Blizzard's dock stays on
        -- General) into the lines' area
        if bar:GetParent() ~= self.panel.log then bar:SetParent(self.panel.log) end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", self.panel.log, "TOPLEFT", 0, 0)
        bar:SetPoint("TOPRIGHT", self.panel.log, "TOPRIGHT", 0, 0)
        bar:SetHeight(FILTER_H)
        bar:SetFrameStrata("MEDIUM")
        bar:Show()
    else
        bar:Hide()
    end
end

function M:Select(cf)
    self.selected = cf
    if self.unread then self.unread[cf] = nil end
    for frame, mirror in pairs(self.mirrors or {}) do
        mirror:SetShown(frame == cf)
        if frame == cf then self.activeMirror = mirror end
    end
    self:CombatFilterBar(cf == ChatFrame2)
    self:UpdateTabs()
end

function M:UpdateTabs()
    local p = self.panel
    local windows = self:Windows()
    if not self.selected or not tContains(windows, self.selected) then
        self.selected = nil
        self:Select(ChatFrame1)
        return
    end
    -- its mirror may have come after the choice
    local mirror = self.mirrors and self.mirrors[self.selected]
    if mirror and not mirror:IsShown() then self:Select(self.selected) return end
    local x = 0
    for i, cf in ipairs(windows) do
        local b = tabButton(self, i)
        b.cf = cf
        local name = GetChatWindowInfo(cf:GetID())
        if cf.isTemporary and cf.chatTarget then name = cf.chatTarget end
        b.label:SetText(name or "")
        b.label.value = nil
        local w = 60
        if not isSecret(name) and type(name) == "string" then
            w = math.min(140, math.ceil(UI.MeasureText("header", name)) + 2)
        end
        b.label:SetWidth(w)
        local active = cf == self.selected
        b.active = active
        b.label:SetColor(active and "gilt-text" or "ink-muted")
        b.line:SetShown(active)
        b.jewel:SetShown(active)
        b.unread:SetShown(not active and self.unread and self.unread[cf] or false)
        b:SetWidth(w + 8)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", p.tabs, "BOTTOMLEFT", x, 0)
        b:Show()
        x = x + w + 8 + S["space-5"]
    end
    for i = #windows + 1, #p.tabButtons do p.tabButtons[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Idle: ground, border, tabs and input fade; the lines stay
--------------------------------------------------------------------------------

function M:Wake()
    self.lastActive = GetTime()
end

local function editBoxes()
    local out = {}
    for _, cf in ipairs(chatFrames()) do
        local eb = cf:GetName() and _G[cf:GetName() .. "EditBox"]
        if eb then out[#out + 1] = eb end
    end
    return out
end

local function editBoxFocused()
    for _, eb in ipairs(editBoxes()) do
        if eb.HasFocus then
            local ok, f = pcall(eb.HasFocus, eb)
            if ok and not isSecret(f) and f then return true end
        end
    end
    return false
end

function M:Tick()
    local p = self.panel
    if not p then return end
    -- a new window (a whisper tab): skinned
    local frames = chatFrames()
    if #frames ~= self.frameCount then
        self.frameCount = #frames
        self:SkinAll()
    end
    -- the window's own font size may have changed in its menu
    for _, cf in ipairs(frames) do
        if self:ApplyFont(cf) then self:ApplyMirrorFont(cf) end
    end
    self:UpdateTabs()
    local awake = true
    if self:Get("fadeIdle") then
        local hovered = p:IsMouseOver() and true or false
        local focused = editBoxFocused()
        if hovered or focused then self:Wake() end
        awake = (GetTime() - (self.lastActive or 0)) < self:Get("idleDelay")
    end
    if awake ~= self.awake then
        self.awake = awake
        local a = awake and 1 or 0
        SuuUI.Motion.AlphaTo(p.deco, a, awake and 0.2 or 1.2)
        SuuUI.Motion.AlphaTo(p.tabs, a, awake and 0.2 or 1.2)
        -- Blizzard's edit boxes: hidden while idle and unfocused
        for _, eb in ipairs(editBoxes()) do
            local ok, f = pcall(eb.HasFocus, eb)
            if not (ok and not isSecret(f) and f) then eb:SetAlpha(a) end
        end
    end
end

--------------------------------------------------------------------------------
-- Global channels in their own tab (Blizzard's own chat settings, as its tab
-- menu sets them): General keeps everything but the numbered channels; a
-- "Global" tab (a "Guild" tab renamed, else a new one) shows only those.
-- Channels joined later move there too. Out of combat only.
--------------------------------------------------------------------------------

-- The channels a window is set to show (joined or not: GetChatWindowChannels
-- lists name, id pairs).
local function windowChannels(id)
    local out = {}
    local list = { GetChatWindowChannels(id) }
    for i = 1, #list, 2 do
        local name = list[i]
        if type(name) == "string" and not isSecret(name) then out[#out + 1] = name end
    end
    return out
end

-- the numbered channels you're in, by name
local function joinedChannels()
    local out = {}
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if type(name) == "string" and not isSecret(name) then out[#out + 1] = name end
    end
    return out
end

-- the window with this name (any case), or nil
local function windowNamed(...)
    local wanted = {}
    for _, n in ipairs({ ... }) do wanted[n:lower()] = true end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = GetChatWindowInfo(i)
        if type(name) == "string" and not isSecret(name) and wanted[name:lower()] then return _G["ChatFrame" .. i] end
    end
end

-- Channels live on the windows on this client: frame:AddChannel(name),
-- frame:RemoveChannel(name), frame:RemoveAllMessageGroups() (/suu probe chat).
function M:ApplyGlobalTab()
    if not self:Get("globalTab") or InCombatLockdown() then return end
    local general = ChatFrame1
    if not (general and general.AddChannel and general.RemoveChannel) then
        if not self.warnedGlobal then
            self.warnedGlobal = true
            self:Print("This client's chat windows have no AddChannel/RemoveChannel: the Global tab can't be set up.")
        end
        return
    end
    local global = windowNamed("Global")
    if not global then
        -- a "Guild" tab becomes Global (its guild messages go back to General), else a new tab
        local guild = windowNamed("Guild")
        if guild and FCF_SetWindowName then
            FCF_SetWindowName(guild, "Global")
            if guild.RemoveAllMessageGroups then guild:RemoveAllMessageGroups() end
            global = guild
        elseif FCF_OpenNewWindow then
            local made = FCF_OpenNewWindow("Global")
            global = (type(made) == "table" and made) or windowNamed("Global")
            if global and global.RemoveAllMessageGroups then global:RemoveAllMessageGroups() end
        end
    end
    if not global then return end
    -- (its place among the tabs is the player's: dragging it, as with any
    -- tab; moving the dock from addon code upsets whisper windows, and the
    -- game docks by its own order on load)
    -- everything General was set to show, and every channel you're in
    local channels, seen = {}, {}
    for _, list in ipairs({ windowChannels(general:GetID()), joinedChannels() }) do
        for _, name in ipairs(list) do
            if not seen[name] then seen[name] = true; channels[#channels + 1] = name end
        end
    end
    for _, name in ipairs(channels) do
        pcall(global.AddChannel, global, name)
        pcall(general.RemoveChannel, general, name)
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function idleOff() return not M:Get("fadeIdle"), "Turn the idle fade on first." end

local SECTION = {
    id = "chat", label = "Chat", category = "World", order = 20,
    groups = {
        { title = "Chat", description = "Blizzard's chat in SuuUI's look: tabs, links, filters of other addons and the input all stay Blizzard's own. Each window's font size is its own setting (right click its tab).", rows = {
            { key = "logHeight", label = "Height", control = "slider", min = 100, max = 400, step = 10, unit = "px", combat = true,
              description = "The lines' area; the panel adds the tabs and the input." },
            { key = "fadeIdle", label = "Fade when idle", control = "toggle",
              description = "Ground, border, tabs and input fade; the lines stay. Back on the mouse, a new message or typing." },
            { key = "idleDelay", label = "Idle after", control = "slider", min = 5, max = 60, step = 1, unit = "s", disabled = idleOff },
            { key = "globalTab", label = "Global channels in their own tab", control = "toggle",
              description = "General, Trade, LocalDefense and the rest in a Global tab (your Guild tab renamed, or a new one); the General tab keeps everything else. Channels you join later go there too. Off: SuuUI leaves your tabs as they are." },
        } },
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:Layout()
    local w, h = self:PanelSize()
    self.panel:SetSize(w, h)
    C_Timer.After(0, function() if self:IsEnabled() then self:PlaceChat() end end)
end

function M:OnEnable()
    if not ChatFrame1 then return end
    -- Blizzard's combat log loads when its tab is first shown, which never
    -- happens now: loaded here (its lines and its filter bar)
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_CombatLog") then pcall(C_AddOns.LoadAddOn, "Blizzard_CombatLog") end
    if not self.panel then self:BuildPanel() end
    self.panel.suuManagedShow = true
    self:Layout()
    self:RegisterMover(self.panel, { key = "position", label = "Chat" })
    self:RegisterSettings(SECTION)
    self:Wake()
    -- one frame later: never while the chat code is mid-update
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:SkinAll()
        self:PlaceChat()
    end)
    -- Blizzard places ChatFrame1 again (Edit Mode, layout passes): ours again
    if ChatFrame1.ApplySystemAnchor and not self.anchorHooked then
        self.anchorHooked = true
        hooksecurefunc(ChatFrame1, "ApplySystemAnchor", function()
            if self.placing or not self:IsEnabled() then return end
            C_Timer.After(0, function() self:PlaceChat() end)
        end)
    end
    -- new windows (whispers, a new tab): skinned a frame later
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                C_Timer.After(0, function()
                    if not self:IsEnabled() then return end
                    self:SkinAll()
                    self:PlaceChat()
                end)
            end)
        end
    end
    for _, e in ipairs(WAKE) do
        if not valid or valid(e) then self:OnGameEvent(e, function() self:Wake() end) end
    end
    -- a whisper opens a temporary window: skinned a frame later
    for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                C_Timer.After(0, function() if self:IsEnabled() then self:SkinAll() end end)
            end)
        end
    end
    self:OnGameEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingPlace then self:PlaceChat() end
        if self.pendingSkin then self.pendingSkin = nil; self:SkinAll() end
        self:ApplyGlobalTab()
    end)
    -- the channels settle a moment after login; joins and leaves later
    C_Timer.After(3, function() if self:IsEnabled() then self:ApplyGlobalTab() end end)
    for _, e in ipairs({ "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function()
                C_Timer.After(0.5, function() if self:IsEnabled() then self:ApplyGlobalTab() end end)
            end)
        end
    end
    self:Watch("globalTab", function() self:ApplyGlobalTab() end)
    self:Watch("position", function() C_Timer.After(0, function() self:PlaceChat() end) end)
    self:Watch("logHeight", function() self:Layout() end)
    self:Watch("fadeIdle", function() self:Wake() end)
    self:On("SUUUI_ROOT_SCALED", function() C_Timer.After(0, function() self:PlaceChat() end) end)
    if not self.driver then
        self.driver = CreateFrame("Frame")
        local wait = 0
        self.driver:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = TICK
            if self:IsEnabled() then self:Tick() end
        end)
    end
end
