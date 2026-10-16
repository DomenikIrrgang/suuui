-- Units/Mail.lua
-- SuuUI's own mail window (plan 3.6, design component MailWindow): the game's
-- MailFrame stays open (it holds the mailbox conversation) but out of sight,
-- and this window shows the whole inbox as one list with the open mail
-- beside it, Collect all and Collect money, a form to send, and the mails
-- this character sent. None of it is protected (/suu probe windows,
-- 2026-10-16); sending money goes through the game's own confirmation.
-- A built-in module written against the public API only.

local UI, T = SuuUI.UI, SuuUI.Tokens
local S = T.space

local M = SuuUI.RegisterModule({
    id = "mail",
    name = "Mail",
    description = "SuuUI's mail window: the whole inbox with Collect all, sending with suggestions, and the mails you sent.",
    api = "0.16",
    reloadToToggle = true,
    defaults = {},
})

local isSecret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not isSecret(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o end
end

local WIDTH, HEIGHT = 720, 560
local LIST_W = 300
local ROW_H = 44
local ATTACH_IN = ATTACHMENTS_MAX_RECEIVE or 16
local ATTACH_OUT = ATTACHMENTS_MAX_SEND or 12
local SENT_MAX = 50
local SUGGEST_W = 320 -- To and its suggestions
local QUALITY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "legendary", "legendary" }
local ENVELOPE = "Interface\\Icons\\INV_Letter_15"

local function coins(copper)
    copper = math.max(0, math.floor(copper or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    local function part(v, unit, token) parts[#parts + 1] = v .. "|cff" .. T.color[token].hex .. unit .. "|r" end
    if g > 0 then part(g, "g", "coin-gold") end
    if s > 0 or (g > 0 and c > 0) then part(s, "s", "coin-silver") end
    if c > 0 or #parts == 0 then part(c, "c", "coin-copper") end
    return table.concat(parts, " ")
end
local function tint(token, text) return "|cff" .. T.color[token].hex .. text .. "|r" end

-- "12 d", "5 h", "under an hour" from the days a mail has left.
local function daysLeft(d)
    if not d then return "" end
    if d >= 1 then return math.floor(d) .. " d" end
    local h = math.floor(d * 24)
    return h >= 1 and (h .. " h") or "< 1 h"
end

-- "3 days ago" from a time() stamp.
local function ago(stamp)
    local s = math.max(0, time() - (stamp or 0))
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " d ago"
end

--------------------------------------------------------------------------------
-- The inbox
--------------------------------------------------------------------------------

-- One mail's header as the list shows it.
local function header(i)
    local packageIcon, _, sender, subject, money, cod, days, itemCount, wasRead, wasReturned, _, canReply, isGM =
        call(GetInboxHeaderInfo, i)
    if subject == nil and sender == nil then return nil end
    local firstIcon
    if itemCount and itemCount > 0 then
        for a = 1, ATTACH_IN do
            local _, _, texture = call(GetInboxItem, i, a)
            if texture then firstIcon = texture break end
        end
    end
    return { index = i, icon = firstIcon or packageIcon or ENVELOPE, sender = sender or "?", subject = subject or "",
             money = money or 0, cod = cod or 0, days = days, items = itemCount or 0, read = wasRead,
             returned = wasReturned, canReply = canReply, gm = isGM }
end

-- What Collect all takes next: the money, else an attachment, of the first
-- mail it may take from (not COD, not from a game master).
local function nextTake(moneyOnly)
    for i = 1, (call(GetInboxNumItems) or 0) do
        local h = header(i)
        if h and h.cod == 0 and not h.gm then
            if h.money > 0 then return i, nil end
            if not moneyOnly and h.items > 0 then
                for a = ATTACH_IN, 1, -1 do
                    if call(HasInboxItem, i, a) then return i, a end
                end
            end
        end
    end
end

-- Takes one thing a moment until nothing is left, the bags are full or the
-- mailbox closes.
function M:CollectAll(moneyOnly)
    if self.collecting then return end
    self.collecting = C_Timer.NewTicker(0.25, function(ticker)
        if C_Mail.IsCommandPending and call(C_Mail.IsCommandPending) then return end
        local i, a = nextTake(moneyOnly)
        local full = a and (call(C_Container.CalculateTotalNumberOfFreeBagSlots) or 1) == 0
        if not self.open or not i or full then
            ticker:Cancel()
            self.collecting = nil
            self:Refresh()
            return
        end
        if a then TakeInboxItem(i, a) else TakeInboxMoney(i) end
    end)
    self:Refresh()
end

local function buildMailRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.hl = UI.Fill(r, "arcane-soft", "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:Hide()
    r.rule = UI.Fill(r, "gilt-faint", "ARTWORK")
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.rule:SetHeight(1)
    r.slot = UI.ItemSlot(r)
    r.slot:SetPoint("LEFT", S["space-2"], 0)
    r.slot:EnableMouse(false)
    r.right = UI.Text(r, "caption", "ink-muted")
    r.right:SetPoint("TOPRIGHT", -S["space-2"], -S["space-3"])
    r.right2 = UI.Text(r, "caption", "ink")
    r.right2:SetPoint("BOTTOMRIGHT", -S["space-2"], S["space-3"])
    r.sender = UI.Text(r, "label", "ink")
    r.sender:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", S["space-4"], 0)
    r.sender:SetPoint("RIGHT", r.right, "LEFT", -S["space-2"], 0)
    r.sender:SetWordWrap(false)
    r.subject = UI.Text(r, "caption", "ink-muted")
    r.subject:SetPoint("BOTTOMLEFT", r.slot, "BOTTOMRIGHT", S["space-4"], 0)
    r.subject:SetPoint("RIGHT", r.right2, "LEFT", -S["space-2"], 0)
    r.subject:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) if not self.selected then self.hl:Show() self.hl:SetAlpha(0.5) end end)
    r:SetScript("OnLeave", function(self) if not self.selected then self.hl:Hide() end end)
    return r
end

function M:DrawInbox()
    local n, total = call(GetInboxNumItems)
    n, total = n or 0, total or 0
    local c = self.inbox.list.child
    self.inbox.count:SetValue(total > n and ("%d mails, %d more once these are gone"):format(n, total - n) or (n == 1 and "1 mail" or (n .. " mails")))
    self.inbox.collect:SetEnabledState(not self.collecting and nextTake(false) ~= nil)
    self.inbox.collect:SetLabel(self.collecting and "Collecting…" or "Collect all")
    self.inbox.money:SetEnabledState(not self.collecting and nextTake(true) ~= nil)
    local rows = self.inbox.rows
    for i = 1, math.max(n, #rows) do
        local r = rows[i]
        if i <= n then
            if not r then
                r = buildMailRow(c)
                rows[i] = r
            end
            local h = header(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("RIGHT", c, "RIGHT")
            r.index = i
            r.slot.skin:SetItem({ icon = h and h.icon or ENVELOPE, quality = "common" })
            r.sender:SetValue(h and h.sender or "")
            r.sender:SetColor(h and not h.read and "gilt-text" or "ink")
            r.subject:SetValue(h and h.subject or "")
            r.right:SetValue(h and (h.days and h.days <= 3 and tint("amber", daysLeft(h.days)) or daysLeft(h.days)) or "")
            local what = ""
            if h then
                if h.cod > 0 then what = tint("amber", "COD " .. coins(h.cod))
                elseif h.money > 0 then what = coins(h.money)
                elseif h.items > 0 then what = h.items == 1 and "1 item" or (h.items .. " items") end
            end
            r.right2:SetValue(what)
            r.selected = self.openIndex == i
            r.hl:SetShown(r.selected)
            r.hl:SetAlpha(1)
            r.rule:SetShown(i < n)
            r:SetScript("OnClick", function()
                if IsModifiedClick("AUTOLOOTTOGGLE") and h and h.cod == 0 then call(AutoLootMailItem, i) end
                self.openIndex = i
                self:Refresh()
            end)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    c:SetHeight(math.max(1, n * ROW_H))
    self.inbox.empty:SetShown(n == 0)
    if self.openIndex and self.openIndex > n then self.openIndex = nil end
    self:DrawOpen()
end

-- The open mail beside the list.
function M:DrawOpen()
    local p = self.inbox.open
    local i = self.openIndex
    local h = i and header(i)
    p:SetShown(h ~= nil)
    self.inbox.none:SetShown(h == nil)
    if not h then return end
    local body, _, _, _, isInvoice = call(GetInboxText, i)
    p.subject:SetValue(h.subject ~= "" and h.subject or "(no subject)")
    p.from:SetValue("From " .. h.sender .. (h.returned and "  ·  returned" or ""))
    local text = plain(body) and body or ""
    if isInvoice then
        local kind, itemName, playerName, bid, buyout, deposit, cut = call(GetInboxInvoiceInfo, i)
        local lines = {}
        if kind == "seller" then
            lines[#lines + 1] = "Item sold: " .. (itemName or "?")
            lines[#lines + 1] = "Buyer: " .. (playerName or "?")
            lines[#lines + 1] = "Sale price: " .. coins(bid or buyout or 0)
            lines[#lines + 1] = "Deposit: " .. coins(deposit or 0)
            lines[#lines + 1] = "Auction house cut: " .. coins(cut or 0)
            lines[#lines + 1] = "Amount received: " .. coins((bid or 0) + (deposit or 0) - (cut or 0))
        elseif kind == "buyer" then
            lines[#lines + 1] = "Item bought: " .. (itemName or "?")
            lines[#lines + 1] = "Seller: " .. (playerName or "?")
            lines[#lines + 1] = "Price: " .. coins(bid or buyout or 0)
        end
        if #lines > 0 then text = table.concat(lines, "\n") .. (text ~= "" and ("\n\n" .. text) or "") end
    end
    p.body:SetValue(text)
    -- attachments, then money and COD
    local used = 0
    for a = 1, ATTACH_IN do
        local name, _, texture, count, quality = call(GetInboxItem, i, a)
        local b = p.slots[a]
        if texture then
            used = used + 1
            b:ClearAllPoints()
            local col, row = (used - 1) % 8, math.floor((used - 1) / 8)
            b:SetPoint("TOPLEFT", p.attach, "TOPLEFT", col * (36 + S["space-2"]), -row * (36 + S["space-2"]))
            b.skin:SetItem({ icon = texture, count = count, quality = QUALITY[quality or 1] or "common" })
            b.attachment = a
            b:Show()
        else
            b:Hide()
        end
    end
    p.attach:SetHeight(used > 0 and (math.ceil(used / 8) * (36 + S["space-2"])) or 1)
    p.moneyRow:SetShown(h.money > 0)
    p.moneyText:SetValue(coins(h.money))
    p.codRow:SetShown(h.cod > 0)
    p.codText:SetValue(tint("amber", "Cash on delivery: " .. coins(h.cod)))
    p.reply:SetEnabledState(h.canReply and true or false)
    local canDelete = call(InboxItemCanDelete, i)
    -- Delete only once nothing is attached; Return a player's mail
    p.delete:SetEnabledState(canDelete and h.items == 0 and h.money == 0 and true or false)
    p.delete.tooltip = (h.items > 0 or h.money > 0) and { title = "Delete", description = "Take what's attached first." } or nil
    p.ret:SetShown(not canDelete and not h.returned)
end

-- Takes an attachment of the open mail; asks first for COD.
function M:Take(a)
    local i = self.openIndex
    local h = i and header(i)
    if not h then return end
    if h.cod > 0 then
        if h.cod > (GetMoney() or 0) then
            UI.Confirm({ title = "Not enough money", text = "Cash on delivery: " .. coins(h.cod) .. ". You have " .. coins(GetMoney() or 0) .. ".", confirm = "OK" })
            return
        end
        UI.Confirm({ title = "Pay cash on delivery?", text = ("Pay %s to %s for this?"):format(coins(h.cod), h.sender),
            confirm = "Pay", onConfirm = function() TakeInboxItem(i, a) end })
        return
    end
    TakeInboxItem(i, a)
end

function M:BuildInbox(page)
    local inbox = { rows = {} }
    self.inbox = inbox
    inbox.collect = UI.Button(page, { text = "Collect all", variant = "primary", width = 120, onClick = function() self:CollectAll(false) end,
        tooltip = { title = "Collect all", description = "Every item and the money of every mail; mails with cash on delivery, and a game master's, stay for you to open." } })
    inbox.collect:SetPoint("TOPLEFT")
    inbox.money = UI.Button(page, { text = "Collect money", onClick = function() self:CollectAll(true) end })
    inbox.money:SetPoint("LEFT", inbox.collect, "RIGHT", S["space-2"], 0)
    inbox.count = UI.Text(page, "caption", "ink-muted")
    inbox.count:SetPoint("LEFT", inbox.money, "RIGHT", S["space-4"], 0)
    local BAR = S["space-3"]
    inbox.list = UI.ScrollArea(page, BAR)
    inbox.list:SetPoint("TOPLEFT", 0, -(30 + S["space-4"]))
    inbox.list:SetPoint("BOTTOMLEFT")
    inbox.list:SetWidth(LIST_W)
    inbox.list.child:SetWidth(LIST_W)
    inbox.empty = UI.Text(inbox.list.child, "body", "ink-muted")
    inbox.empty:SetPoint("TOPLEFT", 0, -S["space-4"])
    inbox.empty:SetValue("Your mailbox is empty.")
    -- the open mail
    local p = CreateFrame("Frame", nil, page)
    p:SetPoint("TOPLEFT", LIST_W + BAR + 3 + S["space-5"], -(30 + S["space-4"]))
    p:SetPoint("BOTTOMRIGHT")
    inbox.open = p
    inbox.none = UI.Text(page, "body", "ink-muted")
    inbox.none:SetPoint("TOPLEFT", p, "TOPLEFT")
    inbox.none:SetValue("Choose a mail to read it.")
    p.subject = UI.Text(p, "unit-name-lg", "ink")
    p.subject:SetPoint("TOPLEFT")
    p.subject:SetPoint("RIGHT")
    p.subject:SetWordWrap(false)
    p.from = UI.Text(p, "caption", "ink-muted")
    p.from:SetPoint("TOPLEFT", p.subject, "BOTTOMLEFT", 0, -S["space-2"])
    -- the buttons at the foot of the pane
    p.delete = UI.Button(p, { text = "Delete", onClick = function()
        local i = self.openIndex
        if i then call(DeleteInboxItem, i); self.openIndex = nil end
    end })
    p.delete:SetPoint("BOTTOMRIGHT")
    p.ret = UI.Button(p, { text = "Return", onClick = function()
        local i = self.openIndex
        if i then call(ReturnInboxItem, i); self.openIndex = nil end
    end })
    p.ret:SetPoint("RIGHT", p.delete, "LEFT", -S["space-2"], 0)
    p.reply = UI.Button(p, { text = "Reply", onClick = function()
        local h = self.openIndex and header(self.openIndex)
        if not h then return end
        self.window:SetTab("send")
        self.send.to:SetValue(h.sender)
        self.send.subject:SetValue((h.subject:find("^RE:") and "" or "RE: ") .. h.subject)
        self.send.body.edit:SetFocus()
    end })
    p.reply:SetPoint("BOTTOMLEFT")
    -- money and COD over the buttons
    p.moneyRow = CreateFrame("Frame", nil, p)
    p.moneyRow:SetHeight(30)
    p.moneyRow:SetPoint("BOTTOMLEFT", p.reply, "TOPLEFT", 0, S["space-4"])
    p.moneyRow:SetPoint("RIGHT")
    p.moneyText = UI.Text(p.moneyRow, "numeric", "ink")
    p.moneyText:SetPoint("LEFT")
    p.takeMoney = UI.Button(p.moneyRow, { text = "Take", width = 70, onClick = function()
        if self.openIndex then call(TakeInboxMoney, self.openIndex) end
    end })
    p.takeMoney:SetPoint("RIGHT")
    p.codRow = CreateFrame("Frame", nil, p)
    p.codRow:SetHeight(20)
    p.codRow:SetPoint("BOTTOMLEFT", p.moneyRow, "TOPLEFT", 0, S["space-2"])
    p.codRow:SetPoint("RIGHT")
    p.codText = UI.Text(p.codRow, "label", "ink")
    p.codText:SetPoint("LEFT")
    -- the attachments over the money
    p.attach = CreateFrame("Frame", nil, p)
    p.attach:SetPoint("BOTTOMLEFT", p.codRow, "TOPLEFT", 0, S["space-4"])
    p.attach:SetPoint("RIGHT")
    p.attach:SetHeight(1)
    p.slots = {}
    for a = 1, ATTACH_IN do
        local b = UI.ItemSlot(p.attach)
        b:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetInboxItem(self.openIndex, btn.attachment)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(btn)
            local link = call(GetInboxItemLink, self.openIndex, btn.attachment)
            if link and IsModifiedClick() and HandleModifiedItemClick(link) then return end
            self:Take(btn.attachment)
        end)
        b:Hide()
        p.slots[a] = b
    end
    -- the message between the header and the attachments
    p.scroll = UI.ScrollArea(p, S["space-3"])
    p.scroll:SetPoint("TOPLEFT", p.from, "BOTTOMLEFT", 0, -S["space-5"])
    p.scroll:SetPoint("BOTTOMRIGHT", p.attach, "TOPRIGHT", -(S["space-3"] + 3), S["space-4"])
    p.body = UI.Text(p.scroll.child, "body", "ink")
    p.body:SetPoint("TOPLEFT")
    p.body:SetJustifyH("LEFT")
    p.body:SetWordWrap(true)
    p.scroll:HookScript("OnSizeChanged", function(scroll, w)
        scroll.child:SetWidth(w)
        p.body:SetWidth(w)
        scroll.child:SetHeight(math.max(1, p.body:GetStringHeight()))
    end)
    hooksecurefunc(p.body, "SetText", function()
        p.scroll.child:SetHeight(math.max(1, p.body:GetStringHeight()))
    end)
end

--------------------------------------------------------------------------------
-- Send
--------------------------------------------------------------------------------

local function moneyInput(parent, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 30)
    local fields = {}
    local x = 0
    for _, d in ipairs({ { "g", "coin-gold", 70, 6 }, { "s", "coin-silver", 44, 2 }, { "c", "coin-copper", 44, 2 } }) do
        local t = UI.TextField(f, { width = d[3], onTextChanged = onChange })
        t.edit:SetNumeric(true)
        t.edit:SetMaxLetters(d[4])
        t:SetPoint("LEFT", x, 0)
        local unit = UI.Text(f, "label", d[2])
        unit:SetValue(d[1])
        unit:SetPoint("LEFT", t, "RIGHT", 3, 0)
        x = x + d[3] + 14
        fields[#fields + 1] = t
    end
    f:SetWidth(x)
    function f:GetCopper()
        local g, s, c = tonumber(fields[1].edit:GetText()) or 0, tonumber(fields[2].edit:GetText()) or 0, tonumber(fields[3].edit:GetText()) or 0
        return g * 10000 + math.min(99, s) * 100 + math.min(99, c)
    end
    function f:Clear() for _, t in ipairs(fields) do t:SetValue("") end end
    f.fields = fields
    return f
end

function M:BuildSend(page)
    local send = {}
    self.send = send
    local labelW = 70
    local function label(text, anchor, y)
        local l = UI.Text(page, "label", "ink-muted")
        l:SetValue(text)
        l:SetPoint("TOPLEFT", 0, y)
        return l
    end
    label("To", nil, -7)
    -- as wide as its suggestions under it
    send.to = UI.TextField(page, { width = SUGGEST_W, onTextChanged = function() self:DrawSendState() end })
    send.to:SetPoint("TOPLEFT", labelW, 0)
    label("Subject", nil, -(30 + S["space-4"] + 7))
    send.subject = UI.TextField(page, { width = WIDTH - 2 * S["space-5"] - labelW, onTextChanged = function() self:DrawSendState() end })
    send.subject:SetPoint("TOPLEFT", labelW, -(30 + S["space-4"]))
    send.subject.edit:SetMaxLetters(64)
    self:BuildSuggest(send.to)
    -- the message: a multi-line field in a sunk well, 500 characters
    local well = CreateFrame("Frame", nil, page)
    well:SetPoint("TOPLEFT", 0, -2 * (30 + S["space-4"]))
    well:SetPoint("RIGHT")
    well:SetHeight(150)
    UI.Fill(well, "surface-sunk"):SetAllPoints()
    UI.Border(well, "gilt-line")
    local scroll = UI.ScrollArea(well, -S["space-3"])
    scroll:SetPoint("TOPLEFT", S["space-4"], -S["space-3"])
    scroll:SetPoint("BOTTOMRIGHT", -S["space-5"], S["space-3"])
    local e = CreateFrame("EditBox", nil, scroll.child)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(send.subject.edit:GetFontObject())
    e:SetMaxLetters(MAX_MAIL_TEXT_LENGTH or 500)
    e:SetPoint("TOPLEFT")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function(box)
        scroll.child:SetHeight(math.max(scroll:GetHeight(), box:GetHeight()))
        send.counter:SetValue(("%d / %d"):format(#(box:GetText() or ""), MAX_MAIL_TEXT_LENGTH or 500))
    end)
    scroll:HookScript("OnSizeChanged", function(s, w) s.child:SetWidth(w); e:SetWidth(w) end)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() e:SetFocus() end)
    send.body = { edit = e, well = well }
    send.counter = UI.Text(page, "caption", "ink-muted")
    send.counter:SetPoint("TOPRIGHT", well, "BOTTOMRIGHT", 0, -S["space-2"])
    send.counter:SetValue("0 / " .. (MAX_MAIL_TEXT_LENGTH or 500))
    -- the attachments: drop or click an item from your bags, right click takes it back
    local attachY = 2 * (30 + S["space-4"]) + 150 + S["space-5"] + 12
    local hint = UI.Text(page, "caption", "ink-muted")
    hint:SetPoint("TOPLEFT", 0, -attachY + 14)
    hint:SetValue("Attachments: drag an item here, or right-click it in your bags. Right-click one here to take it back.")
    send.slots = {}
    for a = 1, ATTACH_OUT do
        local b = UI.ItemSlot(page)
        b:SetPoint("TOPLEFT", (a - 1) * (36 + S["space-2"]), -attachY - 4)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(_, button) call(ClickSendMailItemButton, a, button == "RightButton") end)
        b:SetScript("OnReceiveDrag", function() call(ClickSendMailItemButton, a) end)
        b:SetScript("OnEnter", function(btn)
            if not call(HasSendMailItem, a) then return end
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetSendMailItem(a)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        send.slots[a] = b
    end
    -- money: send it, or ask it on delivery
    local moneyY = attachY + 36 + S["space-5"] + 4
    send.mode = UI.Segmented(page, { options = { { value = "send", label = "Send money" }, { value = "cod", label = "Cash on delivery" } },
        value = "send", onChange = function() self:DrawSendState() end })
    send.mode:SetPoint("TOPLEFT", 0, -moneyY)
    send.money = moneyInput(page, function() self:DrawSendState() end)
    send.money:SetPoint("LEFT", send.mode, "RIGHT", S["space-5"], 0)
    -- the foot: postage and Send
    send.postage = UI.Text(page, "label", "ink-muted")
    send.postage:SetPoint("BOTTOMLEFT", 0, 7)
    send.go = UI.Button(page, { text = "Send", variant = "primary", width = 110, onClick = function() self:Send() end })
    send.go:SetPoint("BOTTOMRIGHT")
end

-- The attachments, the postage and whether Send can go.
function M:DrawSendState()
    local send = self.send
    if not send then return end
    local first
    for a = 1, ATTACH_OUT do
        local b = send.slots[a]
        if call(HasSendMailItem, a) then
            local name, _, texture, count, quality = call(GetSendMailItem, a)
            first = first or name
            b.skin:SetItem({ icon = texture, count = count, quality = QUALITY[quality or 1] or "common" })
        else
            b.skin:SetItem(nil)
        end
    end
    -- an attachment names an empty subject, as the game does
    if first and (send.subject.edit:GetText() or "") == "" and not send.subject.edit:HasFocus() then
        send.subject:SetValue(first)
    end
    local postage = call(GetSendMailPrice) or 0
    local copper = send.money:GetCopper()
    local total = postage + ((send.mode.value or "send") == "send" and copper or 0)
    send.postage:SetValue("Postage " .. coins(postage) .. (total > postage and ("  ·  in all " .. coins(total)) or ""))
    local to = strtrim(send.to.edit:GetText() or "")
    local subject = strtrim(send.subject.edit:GetText() or "")
    local cod = (send.mode.value or "send") == "cod"
    local ok, why = true, nil
    if to == "" then ok, why = false, "Who is it for?" end
    if ok and subject == "" then ok, why = false, "Give it a subject." end
    if ok and cod and (copper == 0 or not first) then ok, why = false, "Cash on delivery needs an amount and an attachment." end
    if ok and total > (GetMoney() or 0) then ok, why = false, "You don't have enough money." end
    send.go:SetEnabledState(ok and not self.sending)
    send.go.tooltip = why and { title = "Send", description = why } or nil
end

function M:Send()
    local send = self.send
    local to = strtrim(send.to.edit:GetText() or "")
    local subject = strtrim(send.subject.edit:GetText() or "")
    local body = send.body.edit:GetText() or ""
    local copper = send.money:GetCopper()
    local cod = (send.mode.value or "send") == "cod"
    call(SetSendMailCOD, 0)
    call(SetSendMailMoney, 0)
    if copper > 0 then
        if cod then call(SetSendMailCOD, copper) else call(SetSendMailMoney, copper) end
    end
    -- what goes out, for the Sent list once the game says it went
    local items = {}
    for a = 1, ATTACH_OUT do
        if call(HasSendMailItem, a) then
            local name, _, texture, count = call(GetSendMailItem, a)
            items[#items + 1] = { name = name, icon = texture, count = count }
        end
    end
    self.pending = { to = to, subject = subject, items = items, money = cod and 0 or copper, cod = cod and copper or 0 }
    self.sending = true
    self:DrawSendState()
    SendMail(to, subject, body)
end

function M:SendDone(ok)
    self.sending = false
    if ok and self.pending then
        local data = self:CharData()
        data.sent = data.sent or {}
        local p = self.pending
        p.at = time()
        table.insert(data.sent, 1, p)
        while #data.sent > SENT_MAX do table.remove(data.sent) end
        self.send.subject:SetValue("")
        self.send.body.edit:SetText("")
        self.send.money:Clear()
        self.send.mode:SetValue("send")
    end
    self.pending = nil
    self:DrawSendState()
end

--------------------------------------------------------------------------------
-- To's suggestions: your characters, the people you sent to lately, and the
-- guild members whose name matches what you typed
--------------------------------------------------------------------------------

local SUGGEST_ROW, SUGGEST_HEAD = 26, 20
local GUILD_MAX = 8

local function classToken(file)
    return file and T.color["class-" .. file:lower()] and ("class-" .. file:lower()) or "ink"
end

-- "Online", or "last online 3 d" from the roster.
local function lastOnline(i)
    local y, mo, d, h = call(GetGuildRosterLastOnline, i)
    if not (y or mo or d or h) then return "Offline" end
    y, mo, d, h = y or 0, mo or 0, d or 0, h or 0
    if y > 0 then return "last online " .. y .. " y" end
    if mo > 0 then return "last online " .. mo .. " mo" end
    if d > 0 then return "last online " .. d .. " d" end
    if h > 0 then return "last online " .. h .. " h" end
    return "last online < 1 h"
end

-- The groups for what's typed: { { title, rows = { { name, color, note, right } } } }.
function M:Suggestions(typed)
    typed = strtrim(typed or ""):lower()
    local seen, groups = {}, {}
    local function matches(name)
        if typed == "" then return 1 end
        local low = name:lower()
        if low:sub(1, #typed) == typed then return 1 end
        if low:find(typed, 1, true) then return 2 end
    end
    local function add(title, rows)
        local out = {}
        for _, r in ipairs(rows) do
            local key = r.name:lower()
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = r
            end
        end
        if #out > 0 then groups[#groups + 1] = { title = title, rows = out } end
    end
    -- your characters on this realm and side
    local me = self:CharData()
    local mine = {}
    for key, d in pairs(self:AllCharData()) do
        if key ~= self:CharKey() and d.name and d.realm == me.realm and d.faction == me.faction and matches(d.name) then
            mine[#mine + 1] = { name = d.name, color = classToken(d.class), right = d.level and ("level " .. d.level) or nil }
        end
    end
    table.sort(mine, function(a, b) return a.name < b.name end)
    add("Your characters", mine)
    -- the people you sent to lately
    local recent, had = {}, {}
    for _, e in ipairs(me.sent or {}) do
        if e.to and not had[e.to:lower()] and matches(e.to) then
            had[e.to:lower()] = true
            recent[#recent + 1] = { name = e.to, color = "ink", right = ago(e.at) }
        end
    end
    add("Recent", recent)
    -- the guild, only for something typed
    if typed ~= "" and IsInGuild() then
        local first, rest = {}, {}
        local myName = Ambiguate(SuuUI.FullName("player") or "", "short")
        for i = 1, (call(GetNumGuildMembers) or 0) do
            local full, rank, _, _, _, _, _, _, online, _, file = call(GetGuildRosterInfo, i)
            if plain(full) and full then
                local name = Ambiguate(full, "mail")
                local m = matches(name)
                if m and Ambiguate(full, "short") ~= myName then
                    local row = { name = name, color = classToken(file), note = plain(rank) and rank or nil,
                                  right = online and tint("fel", "● ") .. "Online" or lastOnline(i), diamond = true }
                    if m == 1 then first[#first + 1] = row else rest[#rest + 1] = row end
                end
            end
        end
        table.sort(first, function(a, b) return a.name < b.name end)
        table.sort(rest, function(a, b) return a.name < b.name end)
        local guild = {}
        for _, list in ipairs({ first, rest }) do
            for _, r in ipairs(list) do if #guild < GUILD_MAX then guild[#guild + 1] = r end end
        end
        add("Guild", guild)
    end
    return groups
end

function M:BuildSuggest(field)
    local d = CreateFrame("Frame", nil, self.window)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetWidth(SUGGEST_W)
    d:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -S["space-2"])
    UI.Fill(d, "surface"):SetAllPoints()
    UI.Border(d, "gilt-line")
    UI.Shadow(d, "shadow-panel")
    d:Hide()
    d.heads, d.rows = {}, {}
    self.suggest = d
    local edit = field.edit
    edit:SetAltArrowKeyMode(false)
    -- (guarded: an error here is recorded under the module's name)
    -- any change of the text while you're in the field (not only the ones
    -- the game flags as typed)
    edit:HookScript("OnTextChanged", self:Guard(function(box)
        local text = box:GetText() or ""
        if text == d.lastText or not box:HasFocus() then return end
        d.lastText = text
        d.pick = 1
        self:DrawSuggest()
    end))
    edit:HookScript("OnEditFocusGained", self:Guard(function()
        -- the roster comes a moment after it's asked for; an open list redraws then
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then call(C_GuildInfo.GuildRoster) end
        d.pick = 1
        self:DrawSuggest()
    end))
    edit:HookScript("OnEditFocusLost", function() C_Timer.After(0.15, function() d:Hide() end) end)
    edit:SetScript("OnArrowPressed", function(_, key)
        if not d:IsShown() or #d.flat == 0 then return end
        d.pick = ((d.pick or 1) + (key == "DOWN" and 1 or (key == "UP" and -1 or 0)) - 1) % #d.flat + 1
        self:DrawSuggest(true)
    end)
    edit:HookScript("OnEnterPressed", function()
        if d:IsShown() and d.flat and d.flat[d.pick or 1] then self:PickSuggest(d.flat[d.pick or 1]) end
    end)
    edit:HookScript("OnTabPressed", function()
        if d:IsShown() and d.flat and d.flat[d.pick or 1] then self:PickSuggest(d.flat[d.pick or 1]) end
        self.send.subject.edit:SetFocus()
    end)
end

function M:PickSuggest(row)
    self.suggest.lastText = row.name
    self.send.to:SetValue(row.name)
    self.suggest:Hide()
    self:DrawSendState()
end

-- The dropdown for what To says now (keep: only the highlight moved).
function M:DrawSuggest(keep)
    local d = self.suggest
    local edit = self.send.to.edit
    if not edit:HasFocus() then d:Hide() return end
    if not keep then d.groups = self:Suggestions(edit:GetText()) end
    local groups = d.groups or {}
    d.flat = {}
    local y, nh, nr = S["space-2"], 0, 0
    for _, g in ipairs(groups) do
        nh = nh + 1
        local h = d.heads[nh]
        if not h then
            h = UI.Text(d, "caption", "ink-muted")
            d.heads[nh] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", S["space-4"], -(y + 4))
        h:SetValue(g.title)
        h:Show()
        y = y + SUGGEST_HEAD
        for _, row in ipairs(g.rows) do
            nr = nr + 1
            d.flat[#d.flat + 1] = row
            local r = d.rows[nr]
            if not r then
                r = CreateFrame("Button", nil, d)
                r:SetHeight(SUGGEST_ROW)
                r.hl = UI.Fill(r, "arcane-soft", "BACKGROUND")
                r.hl:SetAllPoints()
                r.dot = UI.Diamond(r, 5, "ink")
                r.dot:SetPoint("LEFT", S["space-4"], 0)
                r.name = UI.Text(r, "label", "ink")
                r.note = UI.Text(r, "caption", "ink-muted")
                r.right = UI.Text(r, "caption", "ink-muted")
                r.right:SetPoint("RIGHT", -S["space-4"], 0)
                r:SetScript("OnEnter", function(btn) d.pick = btn.flatIndex; self:DrawSuggest(true) end)
                r:SetScript("OnClick", function(btn) self:PickSuggest(btn.row) end)
                d.rows[nr] = r
            end
            r.row, r.flatIndex = row, #d.flat
            r:ClearAllPoints()
            -- inside the border: the highlight leaves its edge showing
            r:SetPoint("TOPLEFT", 1, -y)
            r:SetPoint("RIGHT", d, "RIGHT", -1, 0)
            r.dot:SetShown(row.diamond and true or false)
            if row.diamond then r.dot:SetVertexColor(UI.RGBA(row.color or "ink")) end
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", row.diamond and (S["space-4"] + 10) or S["space-4"], 0)
            r.name:SetValue(row.name)
            r.name:SetColor(row.color or "ink")
            r.note:ClearAllPoints()
            r.note:SetPoint("LEFT", r.name, "RIGHT", S["space-3"], 0)
            r.note:SetValue(row.note or "")
            r.right:SetValue(row.right or "")
            r.hl:SetShown(r.flatIndex == (d.pick or 1))
            r:Show()
            y = y + SUGGEST_ROW
        end
    end
    for i = nh + 1, #d.heads do d.heads[i]:Hide() end
    for i = nr + 1, #d.rows do d.rows[i]:Hide() end
    d:SetHeight(y + S["space-2"])
    d:SetShown(nr > 0)
end

-- This character, for the other characters' suggestions.
function M:RememberMe()
    local d = self:CharData()
    d.name = UnitName("player")
    d.realm = GetRealmName()
    d.level = UnitLevel("player")
    local _, file = UnitClass("player")
    d.class = file
    d.faction = UnitFactionGroup("player")
end

--------------------------------------------------------------------------------
-- Sent: the last mails this character sent
--------------------------------------------------------------------------------

function M:BuildSent(page)
    local sent = { rows = {} }
    self.sent = sent
    sent.list = UI.ScrollArea(page, S["space-3"])
    sent.list:SetPoint("TOPLEFT")
    sent.list:SetPoint("BOTTOMRIGHT", -(S["space-3"] + 3), 0)
    sent.list:HookScript("OnSizeChanged", function(s, w) s.child:SetWidth(w) end)
    sent.empty = UI.Text(sent.list.child, "body", "ink-muted")
    sent.empty:SetPoint("TOPLEFT", 0, -S["space-4"])
    sent.empty:SetValue("Mails you send show here: the last " .. SENT_MAX .. ", for this character.")
end

function M:DrawSent()
    local list = (self:CharData().sent) or {}
    local c = self.sent.list.child
    local rows = self.sent.rows
    for i = 1, math.max(#list, #rows) do
        local r = rows[i]
        local e = list[i]
        if e then
            if not r then
                r = buildMailRow(c)
                r:EnableMouse(false)
                rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("RIGHT", c, "RIGHT")
            local first = e.items and e.items[1]
            r.slot.skin:SetItem({ icon = first and first.icon or ENVELOPE, count = first and first.count, quality = "common" })
            r.sender:SetValue("To " .. (e.to or "?"))
            r.sender:SetColor("ink")
            local what = {}
            if e.items and #e.items > 1 then what[#what + 1] = #e.items .. " items" end
            if (e.money or 0) > 0 then what[#what + 1] = coins(e.money) end
            if (e.cod or 0) > 0 then what[#what + 1] = tint("amber", "COD " .. coins(e.cod)) end
            r.subject:SetValue(e.subject or "")
            r.right:SetValue(ago(e.at))
            r.right2:SetValue(table.concat(what, "  "))
            r.hl:Hide()
            r.rule:SetShown(i < #list)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    c:SetHeight(math.max(1, #list * ROW_H))
    self.sent.empty:SetShown(#list == 0)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function M:Build()
    local w = UI.WindowFrame(SuuUI.Root, { name = "SuuUIMailWindow", title = "Mail", width = WIDTH, height = HEIGHT,
        onClose = function(win) win:Hide() end,
        tabs = { { key = "inbox", label = "Inbox" }, { key = "send", label = "Send" }, { key = "sent", label = "Sent" } },
        onTab = function(key)
            self.tab = key
            for k, page in pairs(self.pages) do page:SetShown(k == key) end
            -- the game attaches a right-clicked bag item while its send page shows
            call(SetSendMailShowing, key == "send")
            self:Refresh()
        end })
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    w:Hide()
    w:HookScript("OnHide", function()
        call(SetSendMailShowing, false)
        if self.open then CloseMail() end
    end)
    w.scroll:Hide()
    self.window = w
    self.pages = {}
    for _, key in ipairs({ "inbox", "send", "sent" }) do
        local page = CreateFrame("Frame", nil, w.body)
        page:SetAllPoints()
        page:Hide()
        self.pages[key] = page
    end
    self:BuildInbox(self.pages.inbox)
    self:BuildSend(self.pages.send)
    self:BuildSent(self.pages.sent)
end

function M:Refresh()
    if not (self.window and self.window:IsShown()) then return end
    local tab = self.tab or "inbox"
    if tab == "inbox" then self:DrawInbox()
    elseif tab == "send" then self:DrawSendState()
    else self:DrawSent() end
end

function M:QueueRefresh()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(0.05, function()
        self.refreshPending = nil
        self:Refresh()
    end)
end

-- The game's frame out of sight: see-through and off screen, still shown,
-- and back off screen whenever the game places it again.
function M:Away(frame)
    if not frame or self.away then return end
    self.away = true
    local placing = false
    local function away()
        if not self:IsEnabled() then return end
        placing = true
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 5000, 0)
        placing = false
    end
    away()
    hooksecurefunc(frame, "SetPoint", function() if not placing then C_Timer.After(0, away) end end)
    frame:HookScript("OnShow", function() C_Timer.After(0, away) end)
end

function M:OnEnable()
    if not self.window then self:Build() end
    self:RememberMe()
    -- what To would suggest for a text, and what the guild roster gives
    -- (also saved to SuuUIProbe.mailSuggest on /reload)
    self:RegisterCommand("mailsuggest", "test: what Send's To suggests for a text, and what the guild roster gives: /suu mailsuggest <text>", function(arg)
        local lines = {}
        local function out(text) lines[#lines + 1] = text; self:Print(text) end
        local n, online = call(GetNumGuildMembers)
        out(("typed %q; in a guild %s, roster %s members (%s online)"):format(arg or "", tostring(IsInGuild()), tostring(n), tostring(online)))
        for i = 1, math.min(3, n or 0) do
            local full, rank, _, _, _, _, _, _, isOnline, _, file = call(GetGuildRosterInfo, i)
            out(("  %d: %s, %s, %s, online %s, as To %s"):format(i, tostring(full), tostring(rank), tostring(file), tostring(isOnline),
                tostring(full and call(Ambiguate, full, "mail"))))
        end
        local ok, groups = pcall(self.Suggestions, self, arg)
        if not ok then out("suggestions failed: " .. tostring(groups)) groups = {} end
        if #groups == 0 then out("no suggestions") end
        for _, g in ipairs(groups) do
            local names = {}
            for _, r in ipairs(g.rows) do names[#names + 1] = r.name end
            out(g.title .. ": " .. table.concat(names, ", "))
        end
        SuuUIProbe = SuuUIProbe or {}
        SuuUIProbe.mailSuggest = { at = date("%H:%M:%S"), lines = lines }
    end)
    self:OnGameEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() self:RememberMe() end) end)
    self:OnGameEvent("MAIL_SHOW", function()
        self.open = true
        self.openIndex = nil
        self:Away(MailFrame)
        if OpenMailFrame then self:Away(OpenMailFrame) end
        self.window:Show()
        self.window:SetTab("inbox")
        call(CheckInbox)
        -- the guild roster for To's suggestions
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then call(C_GuildInfo.GuildRoster) end
    end)
    self:OnGameEvent("MAIL_CLOSED", function()
        self.open = false
        if self.collecting then self.collecting:Cancel(); self.collecting = nil end
        self.window:Hide()
    end)
    for _, e in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_SEND_INFO_UPDATE", "CLOSE_INBOX_ITEM", "PLAYER_MONEY", "BAG_UPDATE_DELAYED" }) do
        self:OnGameEvent(e, function() self:QueueRefresh() end)
    end
    self:OnGameEvent("GUILD_ROSTER_UPDATE", function()
        if self.suggest and self.suggest:IsShown() or (self.send and self.send.to.edit:HasFocus()) then self:DrawSuggest() end
    end)
    self:OnGameEvent("MAIL_SEND_SUCCESS", function() self:SendDone(true) end)
    self:OnGameEvent("MAIL_FAILED", function() if self.sending then self:SendDone(false) end end)
end

function M:OnDisable()
    if self.window then self.window:Hide() end
end
