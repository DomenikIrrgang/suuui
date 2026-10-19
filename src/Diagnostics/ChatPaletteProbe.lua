-- Diagnostics/ChatPaletteProbe.lua
-- "/suu probe chatpalette" (asked 2026-10-19: a slash command palette for the
-- chat input, design C on the board "Chat command suggestions": "/" alone
-- opens every command by category, typing filters, a pick puts the command
-- into the input): what the game tells about its commands, and what writing
-- into the input and watching its keys costs.
--   now:   every slash command. SlashCmdList (the game empties it into a
--          proxy behind its metatable once it has read it, so both), each
--          key's SLASH_<KEY>1..n (the first 30 keys in full, the total of
--          aliases), hash_SlashCmdList, hash_ChatTypeInfoList (it also holds
--          the secure commands and the chat types; IsSecureCmd says which),
--          the emotes (EMOTE<n>_TOKEN, EMOTE<n>_CMD<m>, hash_EmoteTokenList),
--          and who registered a command: issecurevariable on its SLASH_<KEY>1
--          global, the proxy's entry and the hash's entry (a count per
--          addon too); the game's name AutoComplete and the input's hooks
--   then (this session, by itself): the EventRegistry callbacks
--          ChatFrame.OnEditBoxShow/Hide/FocusGained/FocusLost/PreSendText as
--          they fire; AutoCompleteBox while an input has focus: shown, which
--          input it sits on, its names (type "/w " and a friend's first
--          letters)
--
--   /suu probe chatpalette write a|b|c   the main question: can a palette
--          put a command into the input without tainting it, as recall's
--          SetText does (the plan, 2026-10-13: /camp refused until /reload)?
--          a: editBox:SetText, b: editBox:Insert into the empty input (both
--          the next time you open the input), c: ChatFrameUtil.OpenChat(text)
--          2 s later, the input closed (as the game opens /w replies). One
--          variant per /reload. Recorded: the input's fields written by addon
--          code (issecurevariable, as /suu probe taint does) before, just
--          after, each time the input opens again and 60 s later; every
--          ADDON_ACTION_BLOCKED / FORBIDDEN with the seconds since the write;
--          a result line after 60 s
--   /suu probe chatpalette keys          for 60 s, the keys SuuUI sees while
--          the input has focus: a HookScript("OnKeyDown") and
--          ("OnArrowPressed") on the inputs (both already used by SuuUI's
--          chat history; the plan forbids hooks on Show/Hide/Focus/
--          TextChanged, so none here), ChatEdit_CustomTabPressed wrapped
--          (the game calls it through securecall, made for addons' Tab
--          completion; put back after), and a hidden keyboard frame that
--          passes every key on (SetPropagateKeyboardInput), to learn whether
--          it sees anything while the input has focus. Tab and Escape: the
--          input's text and focus right after, to see the game still did
--          its part
-- Saved in SuuUIProbe.chatpalette on /reload. Values the game hides read SECRET.
-- issecure() only says whether the code calling it is secure (SuuUI's never
-- is), so it isn't recorded; issecurevariable is what tells.

local _, ns = ...

local CP = {}
ns.ChatPaletteProbe = CP

local isSecret = issecretvalue or function() return false end
local function show(v)
    if isSecret(v) then return "SECRET" end
    return tostring(v)
end

-- A function that may not exist, may error or may answer secret.
local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "error: " .. tostring(a):sub(1, 120) end
    return a, b, c, d
end

local function out()
    SuuUIProbe = SuuUIProbe or {}
    SuuUIProbe.chatpalette = SuuUIProbe.chatpalette or {}
    return SuuUIProbe.chatpalette
end

local function push(list, line, cap)
    if #list < (cap or 60) then list[#list + 1] = line end
end

-- "secure" or "tainted by <addon>"; the key may be a global's name
local function secureText(t, key)
    if not issecurevariable then return "no issecurevariable" end
    local ok, secure, by
    if key == nil then ok, secure, by = pcall(issecurevariable, t) else ok, secure, by = pcall(issecurevariable, t, key) end
    if not ok then return "error" end
    return secure and "secure" or ("tainted by " .. tostring(by))
end

local function count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function sortedKeys(t)
    local list = {}
    if type(t) ~= "table" then return list end
    for k in pairs(t) do if type(k) == "string" then list[#list + 1] = k end end
    table.sort(list)
    return list
end

local function aliases(key)
    local list, i = {}, 1
    while i <= 30 do
        local s = _G["SLASH_" .. key .. i]
        if s == nil then break end
        list[#list + 1] = show(s)
        i = i + 1
    end
    return list
end

local function inputs()
    local list = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then list[#list + 1] = eb end
    end
    return list
end

local function boxName(eb)
    return eb and eb.GetName and eb:GetName() or tostring(eb)
end

local function text(eb)
    local t = eb and call(eb.GetText, eb)
    return show(t)
end

--------------------------------------------------------------------------------
-- What the game knows about its commands
--------------------------------------------------------------------------------

local function enumerate()
    local e = {}
    -- SlashCmdList and the proxy it's emptied into
    local raw = SlashCmdList
    local mt = type(raw) == "table" and getmetatable(raw)
    local proxy = type(mt) == "table" and type(mt.__index) == "table" and mt.__index or nil
    local keys, seen = {}, {}
    for _, t in ipairs({ raw, proxy or {} }) do
        for _, k in ipairs(sortedKeys(t)) do
            if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
        end
    end
    table.sort(keys)
    e.slashCmdList = ("%d in SlashCmdList itself, %d in its proxy (%s), %d keys together"):format(count(raw),
        count(proxy), proxy and "metatable __index" or "none", #keys)
    local total, byAddon = 0, {}
    e.sample = {}
    for i, k in ipairs(keys) do
        local list = aliases(k)
        total = total + #list
        local who = secureText("SLASH_" .. k .. "1")
        byAddon[who] = (byAddon[who] or 0) + 1
        if i <= 30 then
            local first = list[1] and list[1]:upper()
            e.sample[#e.sample + 1] = ("%s: %s | SLASH_%s1 %s; SlashCmdList %s; proxy %s; hash %s"):format(k,
                #list > 0 and table.concat(list, " ") or "no SLASH_ globals", k, who,
                raw and raw[k] ~= nil and secureText(raw, k) or "absent",
                proxy and proxy[k] ~= nil and secureText(proxy, k) or "absent",
                first and type(hash_SlashCmdList) == "table" and hash_SlashCmdList[first] ~= nil
                    and secureText(hash_SlashCmdList, first) or "absent")
        end
    end
    e.aliases = total
    e.keysByRegisteredBy = {}
    for who, n in pairs(byAddon) do e.keysByRegisteredBy[#e.keysByRegisteredBy + 1] = ("%s: %d"):format(who, n) end
    table.sort(e.keysByRegisteredBy)
    -- the hashes the game reads when a line is sent
    local hash = hash_SlashCmdList
    e.hashSlashCmdList = type(hash) == "table" and count(hash) or show(hash)
    e.hashSample = {}
    for i, k in ipairs(sortedKeys(hash)) do
        if i > 10 then break end
        e.hashSample[#e.hashSample + 1] = k .. " " .. secureText(hash, k)
    end
    -- every command and chat type the game has (secure ones too)
    local all = hash_ChatTypeInfoList
    e.hashChatTypeInfoList = type(all) == "table" and count(all) or show(all)
    local secureList, chatTypes = {}, {}
    for _, alias in ipairs(sortedKeys(all)) do
        local id = all[alias]
        local isSecure = call(IsSecureCmd, alias)
        if isSecure == true then
            secureList[#secureList + 1] = alias .. " → " .. show(id)
        elseif type(ChatTypeInfo) == "table" and ChatTypeInfo[id] ~= nil then
            chatTypes[#chatTypes + 1] = alias .. " → " .. show(id)
        end
    end
    e.secureCommands = #secureList
    e.secureSample = {}
    for i = 1, math.min(30, #secureList) do e.secureSample[i] = secureList[i] end
    e.chatTypes = #chatTypes
    e.chatTypeSample = {}
    for i = 1, math.min(20, #chatTypes) do e.chatTypeSample[i] = chatTypes[i] end
    -- emotes: EMOTE<n>_TOKEN and EMOTE<n>_CMD<m>, up to MAXEMOTEINDEX (or
    -- until 50 numbers in a row have neither)
    local tokens, cmds, misses, n = 0, 0, 0, 1
    local max = type(MAXEMOTEINDEX) == "number" and MAXEMOTEINDEX or nil
    e.emoteSample = {}
    while (max and n <= max) or (not max and misses < 50) do
        local token = _G["EMOTE" .. n .. "_TOKEN"]
        local names, m = {}, 1
        while _G["EMOTE" .. n .. "_CMD" .. m] ~= nil and m <= 20 do
            names[#names + 1] = show(_G["EMOTE" .. n .. "_CMD" .. m])
            m = m + 1
        end
        if token ~= nil then tokens = tokens + 1 end
        cmds = cmds + #names
        if token == nil and #names == 0 then misses = misses + 1 else
            misses = 0
            if #e.emoteSample < 20 then
                e.emoteSample[#e.emoteSample + 1] = ("%d %s: %s"):format(n, show(token), table.concat(names, " "))
            end
        end
        n = n + 1
        if n > 5000 then break end
    end
    e.emotes = ("%d tokens, %d commands, numbers 1-%d, MAXEMOTEINDEX %s"):format(tokens, cmds, n - 1, show(MAXEMOTEINDEX))
    e.hashEmoteTokenList = type(hash_EmoteTokenList) == "table" and count(hash_EmoteTokenList) or show(hash_EmoteTokenList)
    -- what the game offers around the input
    local CFU = ChatFrameUtil or {}
    e.functions = {}
    for _, name in ipairs({ "IsSecureCmd", "ChatEdit_CustomTabPressed", "ChatFrame_OpenChat", "ChatEdit_InsertLink",
                            "ChatEdit_GetActiveWindow", "GetCurrentKeyBoardFocus", "AutoComplete_Update",
                            "AutoCompleteEditBox_SetAutoCompleteSource", "MAXEMOTEINDEX", "ACTIVE_CHAT_EDIT_BOX",
                            "LAST_ACTIVE_CHAT_EDIT_BOX", "CHAT_FOCUS_OVERRIDE" }) do
        e.functions[#e.functions + 1] = ("%s: %s, %s"):format(name, type(_G[name]), secureText(name))
    end
    for _, name in ipairs({ "OpenChat", "InsertLink", "GetActiveWindow", "GetLastActiveWindow", "ActivateChat",
                            "ImportAllListsToHash", "ChooseBoxForSend" }) do
        e.functions[#e.functions + 1] = ("ChatFrameUtil.%s: %s"):format(name, type(CFU[name]))
    end
    e.autoComplete = ("AutoCompleteBox %s, C_AutoComplete.GetAutoCompleteResults %s, AUTOCOMPLETE_LIST.WHISPER %s"):format(
        type(AutoCompleteBox), type(C_AutoComplete and C_AutoComplete.GetAutoCompleteResults),
        type(AUTOCOMPLETE_LIST) == "table" and type(AUTOCOMPLETE_LIST.WHISPER) or "missing")
    -- the input's own scripts (which a palette would sit beside)
    local eb = ChatFrame1EditBox
    e.inputScripts = {}
    if eb then
        for _, sc in ipairs({ "OnKeyDown", "OnKeyUp", "OnChar", "OnTabPressed", "OnArrowPressed", "OnEscapePressed",
                              "OnEnterPressed", "OnTextChanged", "OnTextSet" }) do
            local ok, has = pcall(eb.HasScript, eb, sc)
            local fn = ok and has and eb:GetScript(sc)
            e.inputScripts[#e.inputScripts + 1] = sc .. ": " .. (fn and "set" or (ok and has and "none" or "unsupported"))
        end
        e.inputScripts[#e.inputScripts + 1] = "altArrowKeyMode " .. show(call(eb.GetAltArrowKeyMode, eb))
    end
    return e, #keys
end

--------------------------------------------------------------------------------
-- Taint of the input: its fields written by addon code (the same check as
-- /suu probe taint, over the input instead of the Escape path)
--------------------------------------------------------------------------------

local GLOBALS = { "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "CHAT_FOCUS_OVERRIDE", "ChatEdit_CustomTabPressed",
                  "SlashCmdList", "hash_SlashCmdList", "hash_ChatTypeInfoList", "hash_EmoteTokenList", "AutoCompleteBox" }

local function boxTaint(eb)
    local tainted = {}
    if not issecurevariable then return { "no issecurevariable" } end
    if eb then
        for k in pairs(eb) do
            if type(k) == "string" then
                local s = secureText(eb, k)
                if s ~= "secure" then tainted[#tainted + 1] = boxName(eb) .. "." .. k .. " (" .. s .. ")" end
            end
        end
    end
    for _, name in ipairs(GLOBALS) do
        local s = secureText(name)
        if s ~= "secure" then tainted[#tainted + 1] = name .. " (" .. s .. ")" end
    end
    if type(AutoCompleteBox) == "table" then
        for _, k in ipairs({ "parent", "attachPoint" }) do
            local s = secureText(AutoCompleteBox, k)
            if s ~= "secure" then tainted[#tainted + 1] = "AutoCompleteBox." .. k .. " (" .. s .. ")" end
        end
    end
    table.sort(tainted)
    return tainted
end

local function state(eb, label)
    local chatType, sticky
    if eb then
        chatType = call(eb.GetAttribute, eb, "chatType")
        sticky = call(eb.GetAttribute, eb, "stickyType")
    end
    local tainted = boxTaint(eb)
    return { at = date("%H:%M:%S"), what = label, box = boxName(eb), text = text(eb), chatType = show(chatType),
             stickyType = show(sticky), taintedCount = #tainted, tainted = tainted }
end

--------------------------------------------------------------------------------
-- Session listening: EventRegistry callbacks, AutoCompleteBox, blocked actions
--------------------------------------------------------------------------------

local write          -- the armed write: { variant, at, ... }
local keysUntil      -- GetTime() the keys test ends
local onFocus        -- what the next focus does (the armed write)
local acTicker

local function autoCompleteState()
    local box = AutoCompleteBox
    if type(box) ~= "table" then return "no AutoCompleteBox" end
    if not box:IsShown() then return nil end
    local names = {}
    for i = 1, (AUTOCOMPLETE_MAX_BUTTONS or 5) do
        local b = _G["AutoCompleteButton" .. i]
        if b and b:IsShown() then names[#names + 1] = show(call(b.GetText, b)) end
    end
    return ("shown on %s (input text %s): %s"):format(boxName(box.parent), text(box.parent), table.concat(names, ", "))
end

local function watchAutoComplete(on)
    if acTicker then acTicker:Cancel(); acTicker = nil end
    if not on then return end
    local last
    acTicker = C_Timer.NewTicker(0.25, function()
        local s = autoCompleteState()
        if s and s ~= last then push(out().autoComplete, date("%H:%M:%S") .. " " .. s, 30) end
        last = s
    end, 240)
end

local function doWrite(eb)
    local o = out()
    local w = write
    if not (w and not w.done) then return end
    w.done = true
    w.at = GetTime()
    o.write.before = state(eb, "before the write")
    local ok, err
    if w.variant == "a" then
        ok, err = pcall(eb.SetText, eb, w.text)
    elseif w.variant == "b" then
        o.write.emptyBefore = text(eb) == ""
        ok, err = pcall(eb.Insert, eb, w.text)
    else
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if type(open) ~= "function" then ok, err = false, "no ChatFrameUtil.OpenChat or ChatFrame_OpenChat" else
            local box
            ok, box = pcall(open, w.text)
            if ok then eb = type(box) == "table" and box or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()) or eb
            else err = box end
        end
    end
    o.write.call = ok and "ran" or ("error: " .. tostring(err))
    w.box = eb
    C_Timer.After(0.1, function() o.write.after = state(eb, "0.1 s after the write") end)
    ns.Print(("Chat palette probe: %s put %q into the input (%s). Press Enter to send it, then open the input and type /camp yourself (Cancel the logout if it starts); then /suu probe taint. In 60 s a result line comes."):format(
        w.label, w.text, o.write.call))
    C_Timer.After(60, function()
        local later = state(eb, "60 s after the write")
        o.write.later = later
        local blocked = o.write.blocked or {}
        local before = o.write.before and o.write.before.taintedCount or 0
        o.write.result = ("write %s (%s): %d blocked/forbidden in 60 s%s; input values written by addon code: %d before, %d now"):format(
            w.variant, w.label, #blocked, #blocked > 0 and (" (" .. blocked[1] .. ")") or "", before, later.taintedCount)
        ns.Print("Chat palette probe: " .. o.write.result .. ". /reload to save it, and tell Claude whether /camp worked.")
    end)
end

local listening
local function listen()
    if listening then return end
    listening = true
    local o = out()
    o.registry = o.registry or {}
    o.autoComplete = o.autoComplete or {}
    if EventRegistry and EventRegistry.RegisterCallback then
        for _, name in ipairs({ "ChatFrame.OnEditBoxShow", "ChatFrame.OnEditBoxHide", "ChatFrame.OnEditBoxFocusGained",
                                "ChatFrame.OnEditBoxFocusLost", "ChatFrame.OnEditBoxPreSendText" }) do
            pcall(EventRegistry.RegisterCallback, EventRegistry, name, function(_, eb)
                local r = out().registry
                r[name] = (r[name] or 0) + 1
                r.log = r.log or {}
                push(r.log, ("%s %s %s, text %s"):format(date("%H:%M:%S"), name, boxName(eb), text(eb)), 40)
                if name == "ChatFrame.OnEditBoxFocusGained" then
                    watchAutoComplete(true)
                    if onFocus then
                        local f = onFocus
                        onFocus = nil
                        -- a moment later, outside Blizzard's focus handling
                        C_Timer.After(0.2, function() f(eb) end)
                    elseif write and write.done and write.reopened and #write.reopened < 10 then
                        C_Timer.After(0.2, function()
                            write.reopened[#write.reopened + 1] = state(eb, "the input opened again")
                        end)
                    end
                elseif name == "ChatFrame.OnEditBoxFocusLost" then
                    watchAutoComplete(false)
                end
            end)
        end
        o.registryHooked = "yes"
    else
        o.registryHooked = "no EventRegistry"
    end
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addon, func)
        local p = out()
        p.blocked = p.blocked or {}
        local since = write and write.at and ("%.1f s after the write"):format(GetTime() - write.at) or "no write yet"
        local line = ("%s %s %s %s (%s, combat %s)"):format(date("%H:%M:%S"), event, show(addon), show(func), since,
            tostring(InCombatLockdown()))
        push(p.blocked, line, 40)
        if write and write.at and GetTime() - write.at <= 60 and p.write then
            p.write.blocked = p.write.blocked or {}
            push(p.write.blocked, line, 20)
        end
    end)
end

--------------------------------------------------------------------------------
-- Keys while the input has focus
--------------------------------------------------------------------------------

local hooked = {}
local keyFrame, tabOriginal

local function keyName(key)
    local mods = (IsControlKeyDown() and "CTRL-" or "") .. (IsAltKeyDown() and "ALT-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
    return mods .. tostring(key)
end

local function noteKey(source, line)
    local k = out().keys
    if not k then return end
    k.counts[source] = (k.counts[source] or 0) + 1
    push(k.log, ("%.1fs %s %s"):format(GetTime() - k.start, source, line), 150)
end

local function hookInputs()
    for _, eb in ipairs(inputs()) do
        if not hooked[eb] then
            hooked[eb] = true
            eb:HookScript("OnKeyDown", function(box, key)
                if not (keysUntil and GetTime() < keysUntil) then return end
                local name = keyName(key)
                local before = text(box)
                if key == "TAB" or key == "ESCAPE" then
                    -- after the game's own handling: the text and the focus
                    C_Timer.After(0, function()
                        noteKey("OnKeyDown", ("%s on %s: text %s → %s, focus %s"):format(name, boxName(box), before,
                            text(box), show(call(box.HasFocus, box))))
                    end)
                else
                    noteKey("OnKeyDown", ("%s on %s, text %s"):format(name, boxName(box), before))
                end
            end)
            eb:HookScript("OnArrowPressed", function(box, key)
                if not (keysUntil and GetTime() < keysUntil) then return end
                noteKey("OnArrowPressed", ("%s on %s, text %s"):format(keyName(key), boxName(box), text(box)))
            end)
        end
    end
end

local function startKeys()
    local o = out()
    o.keys = { at = date("%H:%M:%S"), start = GetTime(), counts = {}, log = {} }
    local k = o.keys
    keysUntil = GetTime() + 60
    hookInputs()
    -- Tab: the game's own hook for addons (OnTabPressed calls it through
    -- securecall; a true return skips the game's completion, so nil here)
    k.customTab = ("ChatEdit_CustomTabPressed: %s, %s"):format(type(ChatEdit_CustomTabPressed), secureText("ChatEdit_CustomTabPressed"))
    if type(ChatEdit_CustomTabPressed) == "function" and not tabOriginal then
        tabOriginal = ChatEdit_CustomTabPressed
        ChatEdit_CustomTabPressed = function(eb, ...)
            noteKey("CustomTabPressed", ("on %s, text %s"):format(boxName(eb), text(eb)))
            return tabOriginal(eb, ...)
        end
        k.customTab = k.customTab .. "; wrapped for 60 s"
    end
    -- a hidden keyboard frame that passes keys on: does it see any while the
    -- input has focus? Only out of combat (the propagate flag is protected
    -- in combat, and without it the frame would swallow every key)
    if InCombatLockdown() then
        k.frame = "skipped: in combat"
    else
        keyFrame = keyFrame or CreateFrame("Frame", nil, UIParent)
        local ok = pcall(keyFrame.SetPropagateKeyboardInput, keyFrame, true)
        if ok then
            keyFrame:EnableKeyboard(true)
            keyFrame:SetScript("OnKeyDown", function(_, key)
                if not (keysUntil and GetTime() < keysUntil) then return end
                local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
                noteKey("keyboardFrame", ("%s, keyboard focus %s"):format(keyName(key), focus and boxName(focus) or "none"))
            end)
            keyFrame:Show()
            k.frame = "listening, propagating"
        else
            k.frame = "SetPropagateKeyboardInput refused"
        end
    end
    C_Timer.After(60, function()
        keysUntil = nil
        if tabOriginal then ChatEdit_CustomTabPressed = tabOriginal; tabOriginal = nil end
        if keyFrame then
            keyFrame:SetScript("OnKeyDown", nil)
            pcall(keyFrame.EnableKeyboard, keyFrame, false)
            keyFrame:Hide()
        end
        local c = k.counts
        k.result = ("OnKeyDown %d, OnArrowPressed %d, CustomTabPressed %d, keyboard frame %d"):format(c.OnKeyDown or 0,
            c.OnArrowPressed or 0, c.CustomTabPressed or 0, c.keyboardFrame or 0)
        ns.Print("Chat palette keys: " .. k.result .. ". Did Tab completion, Escape and the arrows still do what they did before? Tell Claude, then /reload to save it.")
    end)
    ns.Print("Chat palette keys: for 60 s, open the chat input and type /pla, press Tab twice, Up and Down, Ctrl+Left and Ctrl+Right, then Escape. Again with \"/w \" and the first letters of a friend's name (Tab, Down). Notice whether each still does what it did before.")
end

--------------------------------------------------------------------------------

local VARIANTS = {
    a = "SetText on the open input",
    b = "Insert into the empty open input",
    c = "ChatFrameUtil.OpenChat(text), the input closed",
}

function CP.Command(arg)
    local o = out()
    local e, n = enumerate()
    o.now = e
    o.now.at = date("%H:%M:%S")
    listen()
    local mode, variant = (arg or ""):match("^(%S*)%s*(%S*)")
    if mode == "keys" then
        startKeys()
        return
    end
    if mode == "write" then
        variant = (variant or ""):lower()
        if not VARIANTS[variant] then
            ns.Print("Chat palette probe: write a, write b or write c (one per /reload).")
            return
        end
        if write then
            ns.Print("Chat palette probe: one write per session; /reload first, then the next variant.")
            return
        end
        write = { variant = variant, label = VARIANTS[variant], text = "/played", reopened = {} }
        o.write = { variant = variant, label = VARIANTS[variant], text = write.text, armedAt = date("%H:%M:%S"),
                    reopened = write.reopened }
        if variant == "c" then
            C_Timer.After(2, function() doWrite(ChatFrameUtil and ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.GetLastActiveWindow() or ChatFrame1EditBox) end)
            ns.Print("Chat palette probe: in 2 s SuuUI opens the input with /played in it (don't press Up or Down this session: recall taints by itself).")
        else
            onFocus = doWrite
            ns.Print("Chat palette probe: now press Enter to open the chat input; SuuUI puts /played into it (don't press Up or Down this session: recall taints by itself).")
        end
        return
    end
    ns.Print(("Chat palette probe: %d commands, %s aliases recorded. Now open the chat input a few times, type \"/w \" and a friend's first letters; then /reload to save it. Next: /reload, then /suu probe chatpalette write a (b, c after a /reload each), and /suu probe chatpalette keys."):format(
        n, show(e.aliases)))
end
