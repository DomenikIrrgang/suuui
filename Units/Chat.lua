-- Units/Chat.lua
-- Chat, the skin (step 2.2a; the line layer, 2.2b, comes next). Blizzard's
-- chat keeps doing all the work: its message frames (filters, links, secret
-- payloads), the edit box and the dock. SuuUI strips their art and draws the
-- design around them: a glass panel `chat-w` wide at the bottom left, the
-- tabs (SuuUI's labels over Blizzard's invisible tabs, which keep clicks,
-- drags and menus: the labels take no mouse), the input field behind
-- Blizzard's restyled edit box, and an idle fade (ground, border, tabs and
-- input go; the lines stay). A built-in module written against the public
-- API only.
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
    -- the tab labels' holder: above the chat frames, no mouse
    p.tabs = CreateFrame("Frame", nil, UIParent)
    p.tabs:SetFrameStrata("MEDIUM")
    p.tabs:SetAllPoints(p)
    p.tabs:EnableMouse(false)
    p.ghosts = {}
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
    if self.fontSizes[cf] == size then return end
    self.fontSizes[cf] = size
    cf:SetFont(BODY_FONT, size, "")
    cf:SetShadowOffset(1, -1)
    cf:SetShadowColor(0, 0, 0, 0.8)
end

function M:SkinAll()
    for _, cf in ipairs(chatFrames()) do self:SkinFrame(cf) end
    alphaOff(GeneralDockManager)
    for _, name in ipairs({ "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
                            "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
        alphaOff(_G[name])
    end
end

--------------------------------------------------------------------------------
-- Tabs: SuuUI's labels over Blizzard's invisible docked tabs
--------------------------------------------------------------------------------

local function ghost(p, i)
    local g = p.ghosts[i]
    if g then return g end
    g = CreateFrame("Frame", nil, p.tabs)
    g:EnableMouse(false)
    -- inside its tab (Blizzard sizes tabs to its own, narrower font): the
    -- header face at 12px, centred, cut with "…" when a name is longer
    g.label = UI.Text(g, "header", "ink-muted")
    g.label:SetFont(SuuUI.Fonts.Get("header"):GetFont(), 12, "")
    g.label:SetShadowed(true)
    g.label:SetPoint("LEFT", 2, 0)
    g.label:SetPoint("RIGHT", -2, 0)
    g.label:SetJustifyH("CENTER")
    g.label:SetWordWrap(false)
    -- the active tab: a hairline fading at both ends, and a gilt diamond
    -- (Blizzard's tabs reach into the lines' area: 4px up)
    g.line = UI.Hairline(g, "gilt-line", "both")
    g.line:SetPoint("BOTTOMLEFT", 0, 4)
    g.line:SetPoint("BOTTOMRIGHT", 0, 4)
    g.jewel = UI.Diamond(g, 5, "gilt")
    g.jewel:SetPoint("CENTER", g, "BOTTOM", 0, 4)
    -- unread: a small ink diamond before the label
    g.unread = UI.Diamond(g, 4, "ink")
    g.unread:SetPoint("CENTER", g, "LEFT", 2, 0)
    p.ghosts[i] = g
    return g
end

function M:UpdateTabs()
    local p = self.panel
    local dock = GENERAL_CHAT_DOCK
    local frames = dock and dock.DOCKED_CHAT_FRAMES or { ChatFrame1 }
    local selected = dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock)
    local n = 0
    for _, cf in ipairs(frames) do
        local tab = cf and cf:GetName() and _G[cf:GetName() .. "Tab"]
        if tab and tab:IsShown() then
            n = n + 1
            local g = ghost(p, n)
            g:ClearAllPoints()
            g:SetAllPoints(tab)
            local text = tab.GetText and tab:GetText()
            g.label:SetText(text or "")
            local active = cf == selected
            g.label:SetColor(active and "gilt-text" or "ink-muted")
            g.line:SetShown(active)
            g.jewel:SetShown(active)
            local alerting = false
            local reader = ChatFrameUtil and ChatFrameUtil.IsTabAlerting
            if reader then
                local ok, a = pcall(reader, tab)
                alerting = ok and not isSecret(a) and a and true or false
            end
            g.unread:SetShown(alerting and not active)
            g:Show()
        end
    end
    for i = n + 1, #p.ghosts do p.ghosts[i]:Hide() end
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
    for _, cf in ipairs(frames) do self:ApplyFont(cf) end
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

local function chatFn(name)
    return _G["ChatFrame_" .. name] or (ChatFrameUtil and ChatFrameUtil[name])
end

-- the numbered channels you're in, by name
local function globalChannels()
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

function M:ApplyGlobalTab()
    if not self:Get("globalTab") or InCombatLockdown() then return end
    local add, remove = chatFn("AddChannel"), chatFn("RemoveChannel")
    if not (add and remove) then
        if not self.warnedGlobal then
            self.warnedGlobal = true
            self:Print("This client's chat has no AddChannel/RemoveChannel: the Global tab can't be set up.")
        end
        return
    end
    local global = windowNamed("Global")
    if not global then
        -- a "Guild" tab becomes Global (its guild messages go back to General)
        local guild = windowNamed("Guild")
        if guild and FCF_SetWindowName then
            FCF_SetWindowName(guild, "Global")
            local removeGroups = chatFn("RemoveAllMessageGroups")
            if removeGroups then removeGroups(guild) end
            global = guild
        elseif FCF_OpenNewWindow then
            global = FCF_OpenNewWindow("Global")
            local removeGroups = chatFn("RemoveAllMessageGroups")
            if global and removeGroups then removeGroups(global) end
        end
    end
    if not global then return end
    for _, channel in ipairs(globalChannels()) do
        pcall(add, global, channel)
        pcall(remove, ChatFrame1, channel)
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
