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
-- Rules for chat on this client (see IMPLEMENTATION_PLAN 2.2):
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
    api = "0.11",
    reloadToToggle = true,
    defaults = {
        position = { point = "BOTTOMLEFT", x = 28, y = 28 },
        logHeight = 160,
        fadeIdle = true,
        idleDelay = 10,
        globalTab = true, -- the numbered (global) channels in a "Global" tab, not in General
        timestamps = true,    -- the time before each line, while the chat is in use
        classDiamonds = true, -- the class diamond before names
        classNames = true,    -- players' names in their class colour (asked 2026-10-18)
        shortChannels = true, -- "2. Trade", not "[2. Trade - City]"
        recall = true,        -- Up and Down bring back what you sent
    },
})

local isSecret = issecretvalue or function() return false end
-- a value that's there and readable
local function plain(v) return v ~= nil and not isSecret(v) end
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

-- A window's font size: Blizzard's setting for it; a whisper window (no
-- saved settings) keeps the one chosen in SuuUI's tab menu.
local tempSizes = {}
local function fontSize(cf)
    if tempSizes[cf] then return tempSizes[cf] end
    local id = cf:GetID()
    local size = id and select(2, FCF_GetChatWindowInfo(id))
    if isSecret(size) or type(size) ~= "number" or size <= 0 then size = 13 end
    return size
end
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
    -- the panel (tabs and lines), then the input below it at the same width
    local h = PAD_TOP + TABS_H + GAP + self:Get("logHeight") + PAD_BOTTOM + GAP + INPUT_H
    return w, h
end

function M:BuildPanel()
    local p = CreateFrame("Frame", "SuuUIChat", SuuUI.Root)
    p:SetFrameStrata("BACKGROUND")
    p:EnableMouse(false)
    p.deco = CreateFrame("Frame", nil, p)
    p.deco:SetAllPoints()
    -- the panel: glass ground and gilt-line edge around the tabs and lines
    p.box = CreateFrame("Frame", nil, p.deco)
    p.box:SetPoint("TOPLEFT")
    p.box:SetPoint("BOTTOMRIGHT", 0, INPUT_H + GAP)
    p.ground = UI.Fill(p.box, "surface-glass", "BACKGROUND")
    p.ground:SetAllPoints()
    p.border = UI.Border(p.box, "gilt-line")
    -- the input field below the panel, as wide: surface-sunk, a gilt-line
    -- edge (Blizzard's edit box sits on it)
    p.field = CreateFrame("Frame", nil, p.deco)
    p.field:SetPoint("BOTTOMLEFT")
    p.field:SetPoint("BOTTOMRIGHT")
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
    p.log:SetPoint("BOTTOMRIGHT", -PAD_X, INPUT_H + GAP + PAD_BOTTOM)
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
    local bottom = (b + INPUT_H + GAP + PAD_BOTTOM) * k
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
    -- hidden frame, its track and thumb invisible
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
        -- on the field below the panel: out by the panel's padding, down by
        -- its bottom padding and the gap
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -PAD_X, -(PAD_BOTTOM + GAP))
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", PAD_X, -(PAD_BOTTOM + GAP))
        eb:SetHeight(INPUT_H)
        if eb.SetTextInsets then eb:SetTextInsets(S["space-4"], S["space-4"], 0, 0) end
        -- Up and Down recall what you sent (the edit box's own history),
        -- without Alt
        if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
        self:HistoryFor(eb)
        self:EditBoxFont(eb, fontSize(cf))
    end
end

function M:EditBoxFont(eb, size)
    eb:SetFont(BODY_FONT, size, "")
    if eb.header then eb.header:SetFont(BODY_FONT, size, "") end
    if eb.headerSuffix then eb.headerSuffix:SetFont(BODY_FONT, size, "") end
end

-- SuuUI's body face at Blizzard's size for the window (its own setting),
-- with the design's shadow. Checked again on each tick: the window's menu
-- changes the size.
function M:ApplyFont(cf)
    local size = fontSize(cf)
    self.fontSizes = self.fontSizes or {}
    if self.fontSizes[cf] == size then return false end
    local first = self.fontSizes[cf] == nil
    self.fontSizes[cf] = size
    cf:SetFont(BODY_FONT, size, "")
    cf:SetShadowOffset(1, -1)
    cf:SetShadowColor(0, 0, 0, 0.8)
    local eb = not first and cf:GetName() and _G[cf:GetName() .. "EditBox"]
    if eb then self:EditBoxFont(eb, size) end
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

-- A name to copy: a small box with it selected, Ctrl+C, Esc or Enter closes.
-- A small box with one line of text (copy a name, name a window): Enter
-- gives the text to `onAccept` (if any) and closes, Esc closes.
local textBox
local function askText(title, text, hint, onAccept)
    if not textBox then
        local p = UI.Panel(SuuUI.Root, { title = title, width = 260, solid = true })
        local field = UI.TextField(p.body, { width = 260 - S["space-5"] * 2 })
        field:SetPoint("TOPLEFT")
        p.field = field
        p.hint = UI.Text(p.body, "caption", "ink-muted")
        p.hint:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -S["space-2"])
        p.body:SetHeight(field:GetHeight() + S["space-2"] + (T.type.caption.lineHeight or 16))
        field.edit:SetScript("OnEscapePressed", function() p:Hide() end)
        field.edit:SetScript("OnEnterPressed", function(edit)
            local accept = p.onAccept
            p:Hide()
            if accept then accept(strtrim(edit:GetText() or "")) end
        end)
        UI.MakeModal(p)
        textBox = p
    end
    textBox.title:SetValue(title)
    textBox.hint:SetValue(hint)
    textBox.onAccept = onAccept
    textBox:Show()
    local edit = textBox.field.edit
    edit:SetText(text or "")
    edit:SetFocus()
    -- a frame later, once the box has its width: from the start, all selected
    -- (set before that, the text scrolls out of view to the left)
    C_Timer.After(0, function()
        edit:SetCursorPosition(0)
        edit:HighlightText()
    end)
end

local function copyName(name)
    askText("Copy name", name, "Ctrl+C to copy · Esc closes")
end

-- Right click on a player's name: SuuUI's own menu (Blizzard's, opened from
-- an addon, runs tainted: copying a name is blocked then). Nothing in it
-- needs a protected action.
local function playerMenu(owner, name)
    -- in the tooltip's look (asked for in game)
    UI.ContextMenuFrom(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton("Whisper", function()
            local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
            if tell then tell(name, ChatFrame1) end
        end)
        if FCF_OpenTemporaryWindow then
            root:CreateButton("Whisper window", function()
                local ok, cf = pcall(FCF_OpenTemporaryWindow, "WHISPER", name)
                M:OpenedWindow(ok and cf or nil, name)
            end)
        end
        root:CreateButton("Invite", function()
            local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
            if invite then pcall(invite, name) end
        end)
        root:CreateButton("Copy name", function() copyName(name) end)
        root:CreateButton("Add friend", function()
            -- a friend request (Forever's classic friends list is off)
            if SuuUI.AddFriend(name) then M:Print("Friend request sent to " .. name .. ".") end
        end)
        root:CreateButton("Ignore", function()
            if C_FriendList and C_FriendList.AddIgnore then pcall(C_FriendList.AddIgnore, name) end
        end)
    end, "chatPlayer", { name = name })
    return true
end

local function linkClick(frame, link, text, button)
    if isSecret(link) or type(link) ~= "string" then return end
    if button == "RightButton" then
        local name = link:match("^player:([^:]+)")
        if name and name ~= "" and playerMenu(frame, name) then return end
    end
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

--------------------------------------------------------------------------------
-- Lines in the design's form: the time (ink-muted, only while the chat is
-- in use), the tag without brackets ("Party", "2. Trade", "From", "Yell"),
-- the class diamond before a name, the name in the line's colour. Taken
-- from Blizzard's finished line (its links stay as they are); a secret line
-- goes in whole. The combat log's lines are left as Blizzard writes them.
--------------------------------------------------------------------------------

local DIAMOND = "Interface\\AddOns\\SuuUI\\Media\\Textures\\ChatDiamond.tga"
local classByName = {}

local function tail(fmt)
    return type(fmt) == "string" and fmt:match("^%%s(.+)$") or nil
end

-- what follows the author in Blizzard's line → the tag the design puts first
-- ("" for none)
local VERBS
local function verbs()
    if VERBS then return VERBS end
    VERBS = {}
    local function add(fmt, tag) local t = tail(fmt); if t then VERBS[#VERBS + 1] = { tail = t, tag = tag } end end
    add(_G.CHAT_SAY_GET, "")
    add(_G.CHAT_YELL_GET, _G.CHAT_MSG_YELL or "Yell")
    add(_G.CHAT_WHISPER_GET, "From")
    add(_G.CHAT_BN_WHISPER_GET, "From")
    return VERBS
end

local function classOf(name, lineID)
    local guid
    local get = C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID
    if get and lineID then
        local ok, g = pcall(get, tonumber(lineID))
        if ok and plain(g) then guid = g end
    end
    if guid and GetPlayerInfoByGUID then
        local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
        if ok and plain(class) and class then return class end
    end
    local key = name and name:lower()
    if key and classByName[key] then return classByName[key] end
    local base = key and key:match("^([^%-]+)")
    if base and base ~= key and classByName[base] then return classByName[base] end
    local ok, _, class = pcall(UnitClass, name)
    if ok and plain(class) and class then return class end
    return nil
end

local function chip(class)
    local c = class and T.color["class-" .. class:lower()]
    if not c then return "" end
    return ("|T%s:0:0:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(DIAMOND,
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function stripColour(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Blizzard's own timestamp (its option in Social) as a pattern for the
-- start of a line: its date format with the numbers as wildcards.
local stampFormat, stampPattern
local function blizzardStamp()
    local fmt = GetCVar and GetCVar("showTimestamps")
    if not plain(fmt) or type(fmt) ~= "string" or fmt == "" or fmt == "none" then return nil end
    if fmt ~= stampFormat then
        stampFormat = fmt
        local out = {}
        local i = 1
        while i <= #fmt do
            local c = fmt:sub(i, i)
            if c == "%" and i < #fmt then
                local k = fmt:sub(i + 1, i + 1)
                out[#out + 1] = (k == "p") and "[AaPp]%.?[Mm]%.?" or "%d+"
                i = i + 2
            else
                out[#out + 1] = c:gsub("%p", "%%%0")
                i = i + 1
            end
        end
        stampPattern = table.concat(out)
    end
    return stampPattern
end

local function stripBlizzardStamp(text)
    local pattern = blizzardStamp()
    if not pattern then return text end
    local rest = text:match("^" .. pattern .. "(.*)$")
    if rest then return rest end
    -- coloured
    local colour = text:match("^|c%x%x%x%x%x%x%x%x")
    if colour then
        rest = text:sub(11):match("^" .. pattern .. "|r(.*)$")
        if rest then return rest end
    end
    return text
end

-- Blizzard's finished line → the design's (without the time).
function M:FormatLine(text)
    if not plain(text) or type(text) ~= "string" then return text end
    local diamonds, short = self:Get("classDiamonds"), self:Get("shortChannels")
    local colored = self:Get("classNames")
    -- SuuUI shows the time: Blizzard's own goes
    if self:Get("timestamps") then text = stripBlizzardStamp(text) end
    -- channel tags: no brackets, numbered ones without the zone
    if short then
        text = text:gsub("(|Hchannel:[^|]*|h)%[(.-)%](|h)", function(open, label, close)
            return open .. label:gsub("%s+%-%s+.*$", "") .. close
        end)
    end
    -- the say/yell/whisper verb after the first name → a tag before it
    local head, link, after = text:match("^(.-)(|Hplayer:.-|h.-|h)(.*)$")
    if link then
        for _, v in ipairs(verbs()) do
            if after:sub(1, #v.tail) == v.tail then
                text = head .. (v.tag ~= "" and (v.tag .. " ") or "") .. link .. ": " .. after:sub(#v.tail + 1)
                break
            end
        end
    end
    -- names: no brackets, the class diamond first, the name in its class
    -- colour (or the line's)
    text = text:gsub("|Hplayer:([^|]*)|h%[(.-)%]|h", function(data, shown)
        local name, lineID = data:match("^([^:]+):?(%d*)")
        local class = (diamonds or colored) and classOf(name, lineID ~= "" and lineID or nil)
        local mark = diamonds and chip(class) or ""
        local c = colored and class and T.color["class-" .. class:lower()]
        local label = stripColour(shown)
        if c then label = "|cff" .. c.hex .. label .. "|r" end
        return mark .. "|Hplayer:" .. data .. "|h" .. label .. "|h"
    end)
    text = text:gsub("(|HBNplayer:[^|]*|h)%[(.-)%](|h)", "%1%2%3")
    return text
end

local TIME_HEX = T.color["ink-muted"].hex

-- One line into a mirror: kept (to show again with or without the time)
-- and shown as the chat is now.
function M:Put(m, text, r, g, b)
    local line = { r = r, g = g, b = b, at = time() }
    if m.raw or not plain(text) then
        line.text, line.raw = text, true
    else
        line.text = self:FormatLine(text)
    end
    local lines = m.lines
    lines[#lines + 1] = line
    if #lines > MAX_LINES then table.remove(lines, 1) end
    local withTime = self:ShowTimes()
    -- drawn otherwise than its earlier lines: all again when it's next shown
    if m.drawnWithTime ~= withTime then m.drawnWithTime = nil end
    m:AddMessage(self:Render(line, withTime), r, g, b)
end

function M:ShowTimes()
    return self:Get("timestamps") and (self.awake ~= false)
end

function M:Render(line, withTime)
    if line.raw or not withTime then return line.text end
    return "|cff" .. TIME_HEX .. date("%H:%M", line.at) .. "|r  " .. line.text
end

-- The mirror's lines again (the time came or went), where it was scrolled.
function M:Redraw(m)
    local withTime = self:ShowTimes()
    if m.raw or m.drawnWithTime == withTime then return end
    m.drawnWithTime = withTime
    local offset = m.GetScrollOffset and m:GetScrollOffset() or 0
    m:Clear()
    for _, line in ipairs(m.lines) do m:AddMessage(self:Render(line, withTime), line.r, line.g, line.b) end
    if offset > 0 and m.SetScrollOffset then pcall(m.SetScrollOffset, m, offset) end
end

-- The shown window now, the others when they're chosen.
function M:RedrawShown()
    if self.activeMirror then self:Redraw(self.activeMirror) end
end

-- Names' classes from the chat events (a line whose sender the client
-- can't tell from its line id).
function M:WatchClasses()
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                         "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
                         "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER",
                         "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL" }) do
        if not valid or valid(e) then
            self:OnGameEvent(e, function(_, _, sender, _, _, _, _, _, _, _, _, _, guid)
                if not (plain(sender) and plain(guid) and type(sender) == "string" and guid) then return end
                local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
                if ok and plain(class) and class then classByName[sender:lower()] = class end
            end)
        end
    end
end

-- Whisper lines (to and from), kept for a whisper window opened later.
local WHISPER_KEEP = 300
local WHISPER_TYPES = { "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" }

local function sameColor(info, r, g, b)
    return info and type(r) == "number" and type(g) == "number" and type(b) == "number"
        and math.abs(info.r - r) < 0.01 and math.abs(info.g - g) < 0.01 and math.abs(info.b - b) < 0.01
end

local function isWhisperLine(r, g, b, event)
    if type(event) == "string" and not isSecret(event) then
        return event:find("WHISPER", 1, true) ~= nil
    end
    if isSecret(r) or isSecret(g) or isSecret(b) then return false end
    for _, t in ipairs(WHISPER_TYPES) do
        if sameColor(ChatTypeInfo and ChatTypeInfo[t], r, g, b) then return true end
    end
    return false
end

function M:KeepWhisper(text, r, g, b, event)
    if isSecret(text) or type(text) ~= "string" or not isWhisperLine(r, g, b, event) then return end
    local who = text:match("|Hplayer:([^:|]+)")
    if not who then return end
    self.whispers = self.whispers or {}
    local list = self.whispers
    -- the same line in a second window
    if list[#list] and list[#list].text == text then return end
    list[#list + 1] = { who = who:lower(), text = text, r = r, g = g, b = b }
    if #list > WHISPER_KEEP then table.remove(list, 1) end
end

-- The kept lines with a player: "Name" matches "Name-Realm" too.
function M:WhispersWith(name)
    local out = {}
    local want = name:lower()
    local base = want:match("^([^%-]+)")
    for _, line in ipairs(self.whispers or {}) do
        local who = line.who
        if who == want or who:match("^([^%-]+)") == base then out[#out + 1] = line end
    end
    return out
end

-- Every line Blizzard adds to the window, copied (a secret one whole), and
-- what it already holds.
function M:Mirror(cf)
    self.mirrors = self.mirrors or {}
    if self.mirrors[cf] then return end
    local m = self:MirrorFrame(cf)
    self.mirrors[cf] = m
    m.lines = {}
    m.raw = cf == ChatFrame2
    self:ApplyMirrorFont(cf)
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    for i = 1, n do
        local ok, text, r, g, b = pcall(cf.GetMessageInfo, cf, i)
        if ok and text ~= nil then
            self:Put(m, text, r, g, b)
            if cf == ChatFrame1 then self:KeepWhisper(text, r, g, b) end
        end
    end
    m.drawnWithTime = self:ShowTimes()
    -- the combat log clears and refills its window on a filter change
    hooksecurefunc(cf, "Clear", function() m:Clear(); wipe(m.lines) end)
    hooksecurefunc(cf, "AddMessage", function(_, text, r, g, b, _, _, _, event)
        if text == nil then return end
        self:Put(m, text, r, g, b)
        if not cf.isTemporary then self:KeepWhisper(text, r, g, b, event) end
        if m ~= self.activeMirror and cf ~= ChatFrame2 then
            self.unread = self.unread or {}
            self.unread[cf] = true
        end
    end)
end

function M:ApplyMirrorFont(cf)
    local m = self.mirrors and self.mirrors[cf]
    if not m then return end
    m:SetFont(BODY_FONT, fontSize(cf), "")
    m:SetShadowOffset(1, -1)
    m:SetShadowColor(0, 0, 0, 0.8)
end

--------------------------------------------------------------------------------
-- History: what you sent and the commands you ran, recalled with Up and
-- Down, kept for the character across reloads. This client's input has no
-- recall of its own. Taken on Enter, before Blizzard runs the line (a
-- message as the command that sends it again: "/p hi", "/w Name hi"); your
-- own lines coming back as chat events fill in if that key never reaches
-- SuuUI. A recalled line is typed in by SuuUI, so what's sent with it runs
-- as SuuUI's: in combat Up and Down pass over protected commands (/cast,
-- /target …: blocked then), and in an encounter's chat lockdown (messages
-- blocked) they do nothing.
--------------------------------------------------------------------------------

local HISTORY_KEEP = 50
-- the input's chat type → the command that sends there
local TYPE_CMD = {
    SAY = "/s", YELL = "/y", EMOTE = "/e", PARTY = "/p", RAID = "/raid", RAID_WARNING = "/rw",
    INSTANCE_CHAT = "/i", GUILD = "/g", OFFICER = "/o",
}
-- your own line's chat event → the command that sends there
local SENT = {
    CHAT_MSG_SAY = "/s", CHAT_MSG_YELL = "/y", CHAT_MSG_EMOTE = "/e",
    CHAT_MSG_PARTY = "/p", CHAT_MSG_PARTY_LEADER = "/p",
    CHAT_MSG_RAID = "/raid", CHAT_MSG_RAID_LEADER = "/raid", CHAT_MSG_RAID_WARNING = "/rw",
    CHAT_MSG_INSTANCE_CHAT = "/i", CHAT_MSG_INSTANCE_CHAT_LEADER = "/i",
    CHAT_MSG_GUILD = "/g", CHAT_MSG_OFFICER = "/o",
    CHAT_MSG_CHANNEL = "channel", CHAT_MSG_WHISPER_INFORM = "/w",
}

-- What the input holds as a line to keep: a command as typed, a message
-- with the command for where it goes.
local function typedLine(eb)
    local text = eb:GetText()
    if not plain(text) or type(text) ~= "string" then return nil end
    text = strtrim(text)
    if text == "" then return nil end
    if text:sub(1, 1) == "/" then return text end
    local chatType = eb:GetAttribute("chatType")
    if not plain(chatType) then return nil end
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        local target = eb:GetAttribute("tellTarget")
        if plain(target) and type(target) == "string" and target ~= "" then return "/w " .. target .. " " .. text end
        return nil
    end
    if chatType == "CHANNEL" then
        local channel = eb:GetAttribute("channelTarget")
        if plain(channel) and channel then return "/" .. tostring(channel) .. " " .. text end
        return nil
    end
    local cmd = TYPE_CMD[chatType]
    return cmd and (cmd .. " " .. text) or nil
end

-- Your own line from a chat event, as the command that sends it again.
local function sentLine(event, text, sender, channelNumber, guid)
    local cmd = SENT[event]
    if not cmd or not plain(text) or type(text) ~= "string" or text == "" then return nil end
    if event == "CHAT_MSG_WHISPER_INFORM" then
        if not plain(sender) or type(sender) ~= "string" or sender == "" then return nil end
        return "/w " .. sender .. " " .. text
    end
    local me = UnitGUID("player")
    if not (plain(guid) and plain(me) and guid == me) then return nil end
    if cmd == "channel" then
        if not plain(channelNumber) or type(channelNumber) ~= "number" or channelNumber <= 0 then return nil end
        cmd = "/" .. channelNumber
    end
    return cmd .. " " .. text
end

function M:History()
    local data = self:CharData()
    data.history = data.history or {}
    return data.history
end

function M:AddHistory(line)
    local list = self:History()
    if list[#list] == line then return end
    list[#list + 1] = line
    while #list > HISTORY_KEEP do table.remove(list, 1) end
    self.recall = nil
end

-- A protected command (/cast, /target, /focus …): blocked in combat when
-- SuuUI typed it in.
local PROTECTED = {}
for _, c in ipairs({ "cast", "castsequence", "castrandom", "use", "userandom", "target", "tar", "targetexact",
                     "targetenemy", "targetfriend", "targetparty", "targetraid", "targetlasttarget", "targetlastenemy",
                     "targetlastfriend", "cleartarget", "focus", "clearfocus", "assist", "click", "stopcasting",
                     "stopattack", "startattack", "petattack", "petfollow", "petstay", "petpassive", "petdefensive",
                     "petaggressive", "petassist", "equip", "equipslot", "equipset", "cancelaura", "cancelform",
                     "dismount", "stopmacro", "changeactionbar", "swapactionbar", "worldmarker", "clearworldmarker" }) do
    PROTECTED["/" .. c] = true
end

local function isProtectedLine(line)
    local cmd = line:match("^(/%S+)")
    if not cmd then return false end
    cmd = cmd:lower()
    if IsSecureCmd then
        local ok, secure = pcall(IsSecureCmd, cmd)
        if ok and plain(secure) then return secure and true or false end
    end
    return PROTECTED[cmd] or false
end

local function chatLockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, locked = pcall(f)
    return ok and plain(locked) and locked == true
end

-- Up: one line further back; Down: one forward, past the newest an empty
-- input. A recall starts over once the text isn't the recalled line.
function M:Recall(eb, step)
    if not self:Get("recall") or chatLockdown() then return end
    local list = self:History()
    if #list == 0 then return end
    local r = self.recall
    local text = eb:GetText()
    if not (r and r.eb == eb and plain(text) and text == r.shown) then
        r = { eb = eb, index = #list + 1 }
        self.recall = r
    end
    local index = r.index + step
    if InCombatLockdown() then
        while list[index] and isProtectedLine(list[index]) do index = index + step end
    end
    if index < 1 or index > #list + 1 then return end
    r.index = index
    eb:SetText(list[index] or "")
    eb:SetCursorPosition(#eb:GetText())
    -- as the input shows it (Blizzard may turn "/p " into its header)
    r.shown = eb:GetText()
end

-- An edit box gets the history: Enter keeps the line, Up and Down recall.
function M:HistoryFor(eb)
    self.historyBoxes = self.historyBoxes or {}
    if self.historyBoxes[eb] then return end
    self.historyBoxes[eb] = true
    eb:HookScript("OnKeyDown", function(box, key)
        if key ~= "ENTER" and key ~= "NUMPADENTER" then return end
        local line = typedLine(box)
        if line then
            self.keyCapture = true
            self:AddHistory(line)
        end
    end)
    eb:HookScript("OnArrowPressed", function(box, key)
        if key == "UP" then self:Recall(box, -1) elseif key == "DOWN" then self:Recall(box, 1) end
    end)
end

function M:WatchSent()
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for event in pairs(SENT) do
        if not valid or valid(event) then
            self:OnGameEvent(event, function(_, text, sender, _, _, _, _, _, channelNumber, _, _, _, guid)
                if self.keyCapture then return end
                local line = sentLine(event, text, sender, channelNumber, guid)
                if line then self:AddHistory(line) end
            end)
        end
    end
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
    -- whisper windows Blizzard didn't dock (a closed one is hidden)
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf and cf.isTemporary and cf:IsShown() then add(cf) end
    end
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
    b:SetScript("OnEnter", function(self) self.hover = true; if not self.active then self.label:SetColor("ink") end end)
    b:SetScript("OnLeave", function(self) self.hover = false; if not self.active then self.label:SetColor("ink-muted") end end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then m:TabMenu(self) else m:Select(self.cf) end
    end)
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

-- Right click on a tab: Blizzard's chat settings for its window (asked
-- 2026-10-18); on a whisper tab, a menu to close it. The windows' font size,
-- name, new and closing are in SuuUI's settings, Chat › Windows.
function M:TabMenu(b)
    local cf = b.cf
    if cf and not cf.isTemporary then
        self:OpenChatSettings(cf)
        return
    end
    if not (cf and FCF_Close) then return end
    UI.ContextMenuFrom(b, function(_, root)
        root:CreateButton("Close", function() self:CloseWindow(cf) end)
    end, "chatTab", { chatFrame = cf })
end

function M:CloseWindow(cf)
    pcall(FCF_Close, cf)
    if self.selected == cf then self:Select(ChatFrame1) else self:UpdateTabs() end
    if self.windowsEditor and self.windowsEditor:IsVisible() then self.windowsEditor:Refresh() end
end

-- Sizes and names go through the client's own chat window settings;
-- Blizzard's chat settings open on the window.
function M:SetFontSize(cf, size)
    if cf.isTemporary then
        tempSizes[cf] = size
    elseif SetChatWindowSize then
        pcall(SetChatWindowSize, cf:GetID(), size)
    end
    if self:ApplyFont(cf) then self:ApplyMirrorFont(cf) end
end

function M:RenameWindow(cf, name)
    if name == "" or cf.isTemporary or not SetChatWindowName then return end
    pcall(SetChatWindowName, cf:GetID(), name)
    self:UpdateTabs()
end

function M:OpenChatSettings(cf)
    if not ChatConfigFrame then return end
    -- the window Blizzard's chat settings act on (its tab menu sets it so)
    CURRENT_CHAT_FRAME_ID = cf:GetID()
    if ChatConfigFrame:IsShown() then HideUIPanel(ChatConfigFrame) end
    ShowUIPanel(ChatConfigFrame)
end

function M:NewWindow(name)
    if name == "" or not FCF_OpenNewWindow then return end
    local ok, cf = pcall(FCF_OpenNewWindow, name)
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:SkinAll()
        if ok and cf and self.mirrors and self.mirrors[cf] then self:Select(cf) end
        if self.windowsEditor and self.windowsEditor:IsVisible() then self.windowsEditor:Refresh() end
    end)
end

-- A whisper window just opened from SuuUI's menu: skinned, the whispers
-- with that player so far put in (Blizzard's starts empty), and shown.
function M:OpenedWindow(cf, name)
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:SkinAll()
        local m = cf and self.mirrors and self.mirrors[cf]
        if not m then return end
        if name and m:GetNumMessages() == 0 then
            for _, line in ipairs(self:WhispersWith(name)) do self:Put(m, line.text, line.r, line.g, line.b) end
        end
        self:Select(cf)
    end)
end

function M:Select(cf)
    self.selected = cf
    if self.unread then self.unread[cf] = nil end
    for frame, mirror in pairs(self.mirrors or {}) do
        mirror:SetShown(frame == cf)
        if frame == cf then self.activeMirror = mirror end
    end
    self:RedrawShown()
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
        -- the hover's ink kept (this runs every tick: it reset it at once)
        b.label:SetColor(active and "gilt-text" or (b.hover and "ink" or "ink-muted"))
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
        self:RedrawShown()
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
        -- channels the group finder reads but keeps out of chat
        -- (LookingForGroup): on no window
        if SuuUI.LFG and SuuUI.LFG.IsHiddenChannel and SuuUI.LFG.IsHiddenChannel(name) then
            pcall(global.RemoveChannel, global, name)
        else
            pcall(global.AddChannel, global, name)
        end
        pcall(general.RemoveChannel, general, name)
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function idleOff() return not M:Get("fadeIdle"), "Turn the idle fade on first." end

-- Settings › Chat › Windows: each window (whisper windows aside) with its
-- name, font size, Blizzard's chat settings for it and closing; a new one.
local EDIT_W, ROW_H = 520, 38

local function windowRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(EDIT_W - 12, ROW_H)
    r.name = UI.TextField(r, { width = 200, onChange = function(text)
        if r.cf then M:RenameWindow(r.cf, strtrim(text)) end
    end })
    r.name:SetPoint("LEFT")
    r.size = UI.Stepper(r, { min = 8, max = 24, step = 1, unit = "px", onChange = function(v)
        if r.cf then M:SetFontSize(r.cf, v) end
    end })
    r.size:SetPoint("LEFT", r.name, "RIGHT", S["space-4"], 0)
    r.config = UI.Button(r, { text = "Chat settings…", onClick = function() if r.cf then M:OpenChatSettings(r.cf) end end,
        tooltip = { title = "Chat settings", description = "Blizzard's settings for this window: which channels and messages it shows." } })
    r.config:SetPoint("LEFT", r.size, "RIGHT", S["space-4"], 0)
    r.close = UI.CloseButton(r, function() if r.cf then M:CloseWindow(r.cf) end end)
    r.close:SetPoint("RIGHT", -S["space-2"], 0)
    return r
end

local function buildWindows(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(EDIT_W, 100)
    f.rows = {}
    f.well = CreateFrame("Frame", nil, f)
    UI.Fill(f.well, "surface-sunk"):SetAllPoints()
    UI.Border(f.well, "gilt-faint")
    f.well:SetPoint("TOPLEFT")
    f.add = UI.Button(f, { text = "New window", onClick = function()
        askText("New window", "", "A name · Enter makes it · Esc cancels", function(name) M:NewWindow(name) end)
    end })
    function f:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        local y = 6
        local i = 0
        for _, cf in ipairs(M:Windows()) do
            if not cf.isTemporary then
                i = i + 1
                local r = self.rows[i] or windowRow(self.well)
                self.rows[i] = r
                r.cf = cf
                local name = GetChatWindowInfo(cf:GetID())
                r.name:SetValue(plain(name) and name or "")
                r.size:SetValue(fontSize(cf))
                r.config:SetShown(ChatConfigFrame ~= nil)
                r.close:SetShown(cf ~= ChatFrame1 and cf ~= ChatFrame2 and FCF_Close ~= nil)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 6, -y)
                r:Show()
                y = y + ROW_H
            end
        end
        local wellH = y + 6
        self.well:SetSize(EDIT_W, wellH)
        local canNew = FCF_OpenNewWindow and (not FCF_CanOpenNewWindow or FCF_CanOpenNewWindow())
        self.add:SetShown(canNew and true or false)
        self.add:ClearAllPoints()
        self.add:SetPoint("TOPLEFT", 0, -(wellH + 10))
        self:SetHeight(wellH + (canNew and (10 + 30) or 0))
    end
    M.windowsEditor = f
    f:Refresh()
    f:HookScript("OnShow", function() f:Refresh() end)
    return f
end

local SECTION = {
    id = "chat", label = "Chat", category = "World", order = 20,
    groups = {
        { title = "Chat", description = "SuuUI shows Blizzard's chat windows as its own tabs: what goes in which window, other addons' filters and the input stay Blizzard's.", rows = {
            { key = "logHeight", label = "Height", control = "slider", min = 100, max = 400, step = 10, unit = "px", combat = true,
              description = "The lines' area; the panel adds the tabs and the input." },
            { key = "fadeIdle", label = "Fade when idle", control = "toggle",
              description = "Ground, border, tabs and input fade; the lines stay. Back on the mouse, a new message or typing." },
            { key = "idleDelay", label = "Idle after", control = "slider", min = 5, max = 60, step = 1, unit = "s", disabled = idleOff },
            { key = "globalTab", label = "Global channels in their own tab", control = "toggle",
              description = "General, Trade, LocalDefense and the rest in a Global tab (your Guild tab renamed, or a new one); the General tab keeps everything else. Channels you join later go there too. Off: SuuUI leaves your tabs as they are." },
        } },
        { title = "Windows", description = "Each tab's window: its name, font size and Blizzard's settings for what it shows. A right click on a tab opens Blizzard's settings for it; whisper windows close with a right click on their tab.", rows = {
            { label = "Windows", control = "custom", build = buildWindows, stacked = true },
        } },
        { title = "Lines", rows = {
            { key = "timestamps", label = "Timestamps", control = "toggle",
              description = "The time before each line while you're using the chat; gone when it fades. Blizzard's own (Options › Social) is left out then." },
            { key = "classNames", label = "Names in class colour", control = "toggle",
              description = "Players' names in chat in their class colour." },
            { key = "classDiamonds", label = "Class diamonds", control = "toggle",
              description = "A diamond in the class colour before each name. Names take the line's colour." },
            { key = "shortChannels", label = "Short channel names", control = "toggle",
              description = "\"2. Trade\" rather than \"[2. Trade - City]\"; tags without brackets." },
        } },
        { title = "Input", rows = {
            { key = "recall", label = "Up and Down recall", control = "toggle",
              description = "Up and Down bring back what you sent (messages and commands, per character). SuuUI types the line in, so the game then treats the input as SuuUI's until you /reload: commands it protects typed in chat (/camp, /logout, /target, /focus) may be refused, and so may chat in a boss fight. Turn it off for dungeons and raids if that bites." },
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
    self:WatchSent()
    self:WatchClasses()
    self:Watch("timestamps", function() for _, m in pairs(self.mirrors or {}) do m.drawnWithTime = nil end; self:RedrawShown() end)
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
