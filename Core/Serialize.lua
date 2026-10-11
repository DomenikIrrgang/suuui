-- Core/Serialize.lua
-- Profile strings for Import and Export: plain data (tables, strings, numbers,
-- booleans) written in a small typed format, checksummed and base64 encoded
-- so they survive chat and copy-paste. Reading never runs code: the parser
-- below only understands that format.
--
--   Serialize.Encode(value) -> "SUU1:…"
--   Serialize.Decode(text)  -> value, or nil and why not
--
-- Format: T / F, n<number>; , s<length>:<bytes>, { key value key value … }

local _, ns = ...

local Serialize = {}
ns.Serialize = Serialize

local PREFIX = "SUU1:"

--------------------------------------------------------------------------------
-- Typed format
--------------------------------------------------------------------------------

local function write(v, out)
    local t = type(v)
    if t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            local x = v[k]
            local xt = type(x)
            if xt == "boolean" or xt == "number" or xt == "string" or xt == "table" then
                write(k, out)
                write(x, out)
            end
        end
        out[#out + 1] = "}"
    end
end

-- Returns value, next position; errors with a message on malformed input.
local function read(s, i, depth)
    if depth > 20 then error("too deeply nested") end
    local c = s:sub(i, i)
    if c == "T" then return true, i + 1 end
    if c == "F" then return false, i + 1 end
    if c == "n" then
        local j = s:find(";", i + 1, true)
        local n = j and tonumber(s:sub(i + 1, j - 1))
        if not n then error("bad number") end
        return n, j + 1
    end
    if c == "s" then
        local colon = s:find(":", i + 1, true)
        local len = colon and tonumber(s:sub(i + 1, colon - 1))
        if not len or len < 0 or colon + len > #s then error("bad string") end
        return s:sub(colon + 1, colon + len), colon + len + 1
    end
    if c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("unterminated table") end
            local k, v
            k, i = read(s, i, depth + 1)
            if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
            v, i = read(s, i, depth + 1)
            t[k] = v
        end
        return t, i + 1
    end
    error("unexpected '" .. c .. "'")
end

--------------------------------------------------------------------------------
-- Base64 and a checksum
--------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INDEX = {}
for i = 1, 64 do B64INDEX[B64:sub(i, i)] = i - 1 end

local function encode64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function decode64(s)
    s = s:gsub("%s", "")
    if #s % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q = { s:byte(i, i + 3) }
        local v = {}
        for j = 1, 4 do
            local ch = string.char(q[j])
            if ch == "=" then v[j] = nil else
                v[j] = B64INDEX[ch]
                if not v[j] then return nil end
            end
        end
        if not (v[1] and v[2]) or (v[4] and not v[3]) then return nil end
        local n = v[1] * 262144 + v[2] * 4096 + (v[3] or 0) * 64 + (v[4] or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if v[3] then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if v[4] then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

-- Fletcher-16 over the payload, as four hex digits.
local function checksum(s)
    local a, b = 0, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 255
        b = (b + a) % 255
    end
    return string.format("%04x", b * 256 + a)
end

--------------------------------------------------------------------------------

function Serialize.Encode(value)
    local out = {}
    write(value, out)
    local payload = table.concat(out)
    return PREFIX .. encode64(checksum(payload) .. payload)
end

function Serialize.Decode(text)
    text = strtrim(text or "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "This isn't a SuuUI profile string." end
    local raw = decode64(text:sub(#PREFIX + 1))
    if not raw or #raw < 5 then return nil, "The string is incomplete; copy all of it." end
    local sum, payload = raw:sub(1, 4), raw:sub(5)
    if checksum(payload) ~= sum then return nil, "The string is damaged or incomplete; copy all of it." end
    local ok, value, last = pcall(read, payload, 1, 0)
    if not ok then return nil, "The string is damaged: " .. tostring(value) .. "." end
    if last ~= #payload + 1 then return nil, "The string has extra data at the end." end
    return value
end
