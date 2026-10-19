-- UI/TalentBuilds.lua
-- Talent builds' pieces that draw nothing (step 3.2e): whether an order of
-- points is one the game allows, SuuUI's share text and the game's own
-- talent string. They take a tree as the Talents module reads it:
--
--   tree = { treeID,
--       order = { nodeID, … },     -- C_Traits.GetTreeNodes' order (the game's string)
--       byID = { [nodeID] = { id, max, row, col, treeIndex, name, treeName,
--                             requires = { nodeID, … },   -- the arrows into it
--                             requiresAll = false,        -- every one (else any one)
--                             choice = false, entryIDs } } }
--   steps = { { node = nodeID, entry = entryID? }, … }    -- one rank each, in order
--
--   UI.TalentOrderCheck(steps, tree) -> true, or false, the step, why
--   UI.TalentNextProblem(steps, tree, nodeID) -> nil, or why one more rank
--       of it can't come next
--   UI.TalentStepProblem(tree, node, count, spent) -> nil, or why one more
--       rank can't come with `count` ranks ({ [nodeID] = n }) and `spent` points
--   UI.TalentStepsFromRanks(ranks, tree) -> steps, allPlaced
--       ranks = { [nodeID] = n }: the game's string has no order, so the
--       points go top to bottom, left to right, as the rows and arrows allow
--   UI.EncodeTalentBuild({ name, classID, treeID, steps }, entryIndex) -> "SuuUI:T1:…"
--   UI.DecodeTalentBuild(text) -> { name, classID, treeID, steps = { { node, entryIndex } } }
--       or nil and why
--   UI.ReadGameTalentHeader(text) -> version, specID, hash (16 bytes), or nil
--   UI.ReadGameTalentString(text, tree) -> { version, specID, hash,
--       ranks = { [nodeID] = n }, entries = { [nodeID] = index } }, or nil and why
--   UI.WriteGameTalentString(version, specID, hash, tree, ranks, entries) -> text
--
-- Forever's rows open by points spent in the whole tree: 5 a row
-- (TALENT_ROW_POINTS; /suu probe talentbuilds, every class), and a talent an
-- arrow points to needs the talent it starts from at full rank.

local _, ns = ...

local UI = ns.UI
local Serialize = ns.Serialize

UI.TALENT_ROW_POINTS = 5
UI.TALENT_MAX_POINTS = 51 -- at level 60 (the game's currency, every class)

local function plural(n, one, many) return n == 1 and one or many end

--------------------------------------------------------------------------------
-- The order check
--------------------------------------------------------------------------------

-- Whether one more rank of `n` can come after `count` (ranks so far) with
-- `spent` points before it. Nil, or why not (the step number in the text).
local function stepProblem(tree, n, count, spent, step)
    local have = count[n.id] or 0
    if have >= (n.max or 1) then
        return ("%s has only %d %s; step %d would be rank %d."):format(n.name or "?", n.max or 1,
            plural(n.max or 1, "rank", "ranks"), step, have + 1)
    end
    local need = (n.row or 0) * UI.TALENT_ROW_POINTS
    if spent < need then
        return ("%s needs %d points spent before it; at step %d only %d %s."):format(n.name or "?", need, step,
            spent, plural(spent, "is", "are"))
    end
    if n.requires and #n.requires > 0 then
        local met, missing = n.requiresAll, nil
        for _, id in ipairs(n.requires) do
            local p = tree.byID[id]
            local full = p and (count[id] or 0) >= (p.max or 1)
            if n.requiresAll then
                if not full then met = false; missing = missing or p end
            elseif full then
                met = true
            else
                missing = missing or p
            end
        end
        if not met and missing then
            return ("%s needs %s at %d/%d before it; at step %d it has %d."):format(n.name or "?", missing.name or "?",
                missing.max or 1, missing.max or 1, step, count[missing.id] or 0)
        end
    end
end

-- One more rank of node `n` with `count` ranks so far ({ [nodeID] = n })
-- and `spent` points before it: nil, or why not.
function UI.TalentStepProblem(tree, n, count, spent)
    return stepProblem(tree, n, count, spent, spent + 1)
end

function UI.TalentOrderCheck(steps, tree)
    if #steps > UI.TALENT_MAX_POINTS then
        return false, UI.TALENT_MAX_POINTS + 1, ("A build holds %d points at most."):format(UI.TALENT_MAX_POINTS)
    end
    local count = {}
    for i, s in ipairs(steps) do
        local n = tree.byID[s.node]
        if not n then return false, i, ("Step %d isn't a talent of this tree any more."):format(i) end
        local why = stepProblem(tree, n, count, i - 1, i)
        if why then return false, i, why end
        count[n.id] = (count[n.id] or 0) + 1
    end
    return true
end

-- Why one more rank of a node can't come next (nil: it can).
function UI.TalentNextProblem(steps, tree, nodeID)
    if #steps >= UI.TALENT_MAX_POINTS then
        return ("A build holds %d points at most."):format(UI.TALENT_MAX_POINTS)
    end
    local n = tree.byID[nodeID]
    if not n then return "Not a talent of this tree." end
    local count = {}
    for _, s in ipairs(steps) do count[s.node] = (count[s.node] or 0) + 1 end
    return stepProblem(tree, n, count, #steps, #steps + 1)
end

-- Ranks without an order: placed top to bottom, left to right, as the
-- rows and arrows allow; a talent's ranks one after another.
function UI.TalentStepsFromRanks(ranks, tree, entries)
    local left, list = {}, {}
    for id, r in pairs(ranks) do
        local n = tree.byID[id]
        if n and r > 0 then
            left[id] = math.min(r, n.max or r)
            list[#list + 1] = n
        end
    end
    table.sort(list, function(a, b)
        if (a.row or 0) ~= (b.row or 0) then return (a.row or 0) < (b.row or 0) end
        if (a.treeIndex or 0) ~= (b.treeIndex or 0) then return (a.treeIndex or 0) < (b.treeIndex or 0) end
        if (a.col or 0) ~= (b.col or 0) then return (a.col or 0) < (b.col or 0) end
        return a.id < b.id
    end)
    local steps, count, all = {}, {}, true
    local function place(n)
        while (left[n.id] or 0) > 0 and #steps < UI.TALENT_MAX_POINTS do
            steps[#steps + 1] = { node = n.id, entry = entries and entries[n.id] or nil }
            count[n.id] = (count[n.id] or 0) + 1
            left[n.id] = left[n.id] - 1
        end
    end
    local progress = true
    while progress do
        progress = false
        for _, n in ipairs(list) do
            if (left[n.id] or 0) > 0 and not stepProblem(tree, n, count, #steps, #steps + 1) then
                place(n)
                progress = true
                break
            end
        end
    end
    -- what the rows and arrows never allowed: after the rest, as it came
    for _, n in ipairs(list) do
        if (left[n.id] or 0) > 0 then all = false; place(n) end
    end
    return steps, all
end

--------------------------------------------------------------------------------
-- SuuUI's share text: "SuuUI:T1:" and base64 of the class (1 byte), the
-- tree (2), the name's length (1) and its UTF-8 (48 at most), the steps'
-- count (1), the lowest node ID among them (3), each step as its node's
-- offset from that (2; the high bit: a choice, its entry's index follows in
-- 1 byte), then a Fletcher-16 of all that (2).
--------------------------------------------------------------------------------

local PREFIX = "SuuUI:T1:"
local NAME_MAX = 48

local function u16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function u24(n) return string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end

-- Cut to `max` bytes without splitting a character.
local function cutUTF8(s, max)
    if #s <= max then return s end
    local i = max
    -- back off continuation bytes (10xxxxxx) and the lead byte they follow
    while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 128 and s:byte(i + 1) < 192 do i = i - 1 end
    return s:sub(1, i)
end

function UI.EncodeTalentBuild(b, entryIndex)
    local name = cutUTF8(b.name or "", NAME_MAX)
    local steps = b.steps or {}
    local base
    for _, s in ipairs(steps) do base = math.min(base or s.node, s.node) end
    base = base or 0
    local out = { string.char((b.classID or 0) % 256), u16(b.treeID or 0), string.char(#name), name,
        string.char(#steps), u24(base) }
    for _, s in ipairs(steps) do
        local index = entryIndex and s.entry and entryIndex(s)
        local offset = s.node - base
        if offset >= 32768 then return nil, "These talents are too far apart to share." end
        if index then
            out[#out + 1] = u16(offset + 32768) .. string.char(index % 256)
        else
            out[#out + 1] = u16(offset)
        end
    end
    local payload = table.concat(out)
    return PREFIX .. Serialize.Base64(payload .. u16(Serialize.Fletcher16(payload)))
end

function UI.DecodeTalentBuild(text)
    text = (text or ""):gsub("%s", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "This isn't a SuuUI talent build." end
    local raw = Serialize.FromBase64(text:sub(#PREFIX + 1))
    if not raw or #raw < 10 then return nil, "The text is incomplete; copy all of it." end
    local payload, sum = raw:sub(1, -3), raw:sub(-2)
    if u16(Serialize.Fletcher16(payload)) ~= sum then return nil, "The text is damaged or incomplete; copy all of it." end
    local pos = 1
    local function byte()
        local v = payload:byte(pos)
        pos = pos + 1
        return v
    end
    local classID = byte()
    local hi, lo = byte(), byte()
    local treeID = hi and lo and hi * 256 + lo
    local len = byte()
    if not (classID and treeID and len) then return nil, "The text is damaged." end
    local name = payload:sub(pos, pos + len - 1)
    pos = pos + len
    local count = byte()
    local b1, b2, b3 = byte(), byte(), byte()
    if not (count and b1 and b2 and b3) then return nil, "The text is damaged." end
    local base = b1 * 65536 + b2 * 256 + b3
    local steps = {}
    for i = 1, count do
        local h, l = byte(), byte()
        if not (h and l) then return nil, "The text is damaged." end
        local v = h * 256 + l
        local step = {}
        if v >= 32768 then
            v = v - 32768
            step.entryIndex = byte()
            if not step.entryIndex then return nil, "The text is damaged." end
        end
        step.node = base + v
        steps[i] = step
    end
    if pos ~= #payload + 1 then return nil, "The text has extra data at the end." end
    return { name = name, classID = classID, treeID = treeID, steps = steps }
end

--------------------------------------------------------------------------------
-- The game's talent string (its published format, serialization 2): base64
-- with 6 bits a character, each value's low bits first. A header (version 8
-- bits, spec 16, the tree's hash 16 × 8), then each node of the tree in
-- C_Traits.GetTreeNodes' order: selected (1); if so purchased (1); if so
-- partly ranked (1) and then its ranks (6), and a choice (1) and then the
-- entry's index (2, from 0).
--------------------------------------------------------------------------------

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local INDEX = {}
for i = 1, 64 do INDEX[CHARS:sub(i, i)] = i - 1 end

local function reader(text)
    local values = {}
    for i = 1, #text do
        local v = INDEX[text:sub(i, i)]
        if not v then return nil end
        values[i] = v
    end
    local r = { at = 0 } -- bits read
    function r.bits() return #values * 6 - r.at end
    function r.take(width)
        local value, shift = 0, 1
        for _ = 1, width do
            local c = values[math.floor(r.at / 6) + 1]
            if not c then return nil end
            local b = math.floor(c / 2 ^ (r.at % 6)) % 2
            value = value + b * shift
            shift = shift * 2
            r.at = r.at + 1
        end
        return value
    end
    return r
end

local function writer()
    local w = { out = {}, cur = 0, used = 0 }
    function w.put(width, value)
        for _ = 1, width do
            local b = value % 2
            value = math.floor(value / 2)
            w.cur = w.cur + b * 2 ^ w.used
            w.used = w.used + 1
            if w.used == 6 then
                w.out[#w.out + 1] = CHARS:sub(w.cur + 1, w.cur + 1)
                w.cur, w.used = 0, 0
            end
        end
    end
    function w.text()
        if w.used > 0 then return table.concat(w.out) .. CHARS:sub(w.cur + 1, w.cur + 1) end
        return table.concat(w.out)
    end
    return w
end

local function header(r)
    if not r or r.bits() < 8 + 16 + 128 then return nil end
    local version, specID = r.take(8), r.take(16)
    local hash = {}
    for i = 1, 16 do hash[i] = r.take(8) end
    return version, specID, hash
end

function UI.ReadGameTalentHeader(text)
    return header(reader(((text or ""):gsub("%s", ""))))
end

function UI.ReadGameTalentString(text, tree)
    text = (text or ""):gsub("%s", "")
    local r = reader(text)
    local version, specID, hash = header(r)
    if not version then return nil, "This isn't a talent string." end
    local ranks, entries = {}, {}
    for _, id in ipairs(tree.order or {}) do
        local selected = r.take(1)
        if selected == nil then return nil, "The string is incomplete; copy all of it." end
        if selected == 1 then
            local purchased = r.take(1)
            if purchased == 1 then
                local partial = r.take(1)
                local n
                if partial == 1 then n = r.take(6) end
                local choice = r.take(1)
                local index
                if choice == 1 then index = r.take(2) end
                if partial == nil or choice == nil or (partial == 1 and n == nil) or (choice == 1 and index == nil) then
                    return nil, "The string is incomplete; copy all of it."
                end
                local node = tree.byID[id]
                if not n then
                    if not node then return nil, "The string doesn't match this class's talents." end
                    n = node.max or 1
                end
                ranks[id] = n
                if index then entries[id] = index + 1 end
            elseif purchased == nil then
                return nil, "The string is incomplete; copy all of it."
            end
        end
    end
    return { version = version, specID = specID, hash = hash, ranks = ranks, entries = entries }
end

function UI.WriteGameTalentString(version, specID, hash, tree, ranks, entries)
    local w = writer()
    w.put(8, version or 0)
    w.put(16, specID or 0)
    for i = 1, 16 do w.put(8, hash and hash[i] or 0) end
    for _, id in ipairs(tree.order or {}) do
        local r = ranks[id] or 0
        local node = tree.byID[id]
        if r > 0 and node then
            w.put(1, 1)
            w.put(1, 1)
            local partial = r ~= (node.max or 1)
            w.put(1, partial and 1 or 0)
            if partial then w.put(6, r) end
            local index = node.choice and entries and entries[id]
            w.put(1, index and 1 or 0)
            if index then w.put(2, index - 1) end
        else
            w.put(1, 0)
        end
    end
    return w.text()
end
