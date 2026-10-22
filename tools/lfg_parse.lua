-- tools/lfg_parse.lua
-- Replays chat through ForeverLFG's parser outside the game: the same
-- Parser and language modules SuuUI loads (libs/ForeverLFG), compiled to
-- plain Lua with `wowlua compile --release` into a temporary folder, fed
-- with the lines the LFG recorder kept (/suu probe lfg record) or with lines
-- given on the command line. Prints what the parser made of each one. The
-- SavedVariables run in an empty sandbox (no io, no os). Needs wowlua and
-- lua (5.1 or later) on the PATH.
--
--   lua tools/lfg_parse.lua <SuuUI.lua SavedVariables>       -- the recorded lines
--   lua tools/lfg_parse.lua -e "LFM tank RFK" "lfg sfk healer" -- lines of your own
--   add --lang koKR,zhTW to read with more languages than enUS

local root = (arg[0]:match("^(.*)/tools/") or ".") .. "/libs/ForeverLFG"
local out = os.tmpname()
os.remove(out)
local LANGS = { "enUS", "koKR", "zhCN" }
local files = { "src/Parser.wowlua" }
for _, l in ipairs(LANGS) do files[#files + 1] = "src/Lang/" .. l .. ".wowlua" end
local cmd = ('cd "%s" && wowlua compile --release --no-bundle -o "%s" %s >/dev/null 2>&1'):format(root, out, table.concat(files, " "))
assert(os.execute(cmd), "wowlua compile failed: " .. cmd)

-- the compiled modules register with the wowlua runtime in the addon table
local ns = {}
local function load(path)
    local chunk = assert(loadfile(out .. "/" .. path))
    chunk("SuuUI", ns)
end
load("wowlua/runtime.lua")
load("src/Parser.lua")
for _, l in ipairs(LANGS) do load("src/Lang/" .. l .. ".lua") end
os.execute(('rm -rf "%s"'):format(out))
local parse = ns.__wowlua.require("Parser")
for _, l in ipairs(LANGS) do parse.lang.Register(l, ns.__wowlua.require("Lang/" .. l)[l]) end
local P = parse.parser

local languages = { "enUS" }
local lines = {}
local i = 1
while arg[i] do
    if arg[i] == "--lang" then
        for code in arg[i + 1]:gmatch("[^,]+") do languages[#languages + 1] = code end
        i = i + 2
    elseif arg[i] == "-e" then
        i = i + 1
        while arg[i] and arg[i]:sub(1, 2) ~= "--" do
            lines[#lines + 1] = { channel = "-", author = "-", text = arg[i] }
            i = i + 1
        end
    else
        -- a SavedVariables file: the recorder's lines
        local env = {}
        local chunk = assert(loadfile(arg[i], "t", env))
        chunk()
        local rec = env.SuuUIProbe and env.SuuUIProbe.lfg and env.SuuUIProbe.lfg.record
        for _, l in ipairs(rec and rec.lines or {}) do
            -- "time | channel | author | text | where"; the text may hold "|" itself
            local time, channel, author, rest = l:match("^(.-) | (.-) | (.-) | (.*)$")
            local text = rest and rest:match("^(.*) | [^|]*$") or rest
            lines[#lines + 1] = { time = time, channel = channel, author = author, text = text }
        end
        i = i + 1
    end
end

local function keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

local counts = { read = 0, dropped = 0 }
for _, l in ipairs(lines) do
    local r, why = P.Parse(l.text or "", { languages = languages })
    local head = ("%s %-16s %-22s %s"):format(l.time or "", l.channel or "", l.author or "", l.text or "")
    print(head)
    if r then
        counts.read = counts.read + 1
        print(("    -> %s | %s%s | roles %s | classes %s | need %s | members %s | level %s | lang %s | conf %.2f"):format(
            r.intent or "?", table.concat(r.activities, ","),
            #r.quests > 0 and (" quest " .. table.concat(r.quests, ",")) or "",
            keys(r.roles), keys(r.classes), tostring(r.need),
            r.members and (r.members[1] .. "/" .. r.members[2]) or "-",
            r.level and ((r.level[1] or "") .. "-" .. (r.level[2] or "")) or "-",
            table.concat(r.languages, ","), r.confidence))
    else
        counts.dropped = counts.dropped + 1
        print("    -> (" .. tostring(why) .. ")")
    end
end
print(("%d lines: %d read, %d dropped"):format(#lines, counts.read, counts.dropped))
