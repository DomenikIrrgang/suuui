-- Loads the SuuUI addon into a sandbox, in .toc order, against the simulated client.
local api = require("harness.wow.api")

local M = {}

local chunkCache = {}
local tocCache

--- Reads a file as a string.
-- @param path string
-- @return string
local function readFile(path)
    local fh = assert(io.open(path, "rb"), "harness: cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    return src
end

--- Parses the .toc and returns the ordered list of Lua file paths.
-- @param root string  Addon root directory
-- @return table
function M.readToc(root)
    if tocCache then return tocCache end
    local files = {}
    for line in readFile(root .. "/SuuUI.toc"):gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" and trimmed:lower():match("%.lua$") then
            files[#files + 1] = trimmed:gsub("\\", "/")
        end
    end
    tocCache = files
    return files
end

local function chunkFor(root, relPath)
    local cached = chunkCache[relPath]
    if cached then return cached end
    local src = readFile(root .. "/" .. relPath)
    local fn, err = load(src, "@" .. relPath, "t", {})
    assert(fn, "harness: syntax error in " .. relPath .. ": " .. tostring(err))
    chunkCache[relPath] = fn
    return fn
end

--- Loads every addon file into a fresh sandbox and boots it.
-- @param opts table  { root, boot = true, debug = false }
-- @return table  { env, SuuUI, wow, files }
function M.load(opts)
    opts = opts or {}
    local root = opts.root or "."

    local env = {}
    env._G = env
    setmetatable(env, { __index = _G })

    local wow = api.install(env)
    local files = M.readToc(root)

    for _, relPath in ipairs(files) do
        local fn = chunkFor(root, relPath)
        debug.setupvalue(fn, 1, env)
        local ok, err = pcall(fn)
        if not ok then
            error("harness: error loading " .. relPath .. ": " .. tostring(err), 0)
        end
    end

    local SuuUI = env.SuuUI
    assert(SuuUI, "harness: SuuUI namespace was not created")
    SuuUI._debug = opts.debug == true

    if opts.boot ~= false then
        wow.fireEvent("ADDON_LOADED", "SuuUI")
        wow.fireEvent("PLAYER_LOGIN")
    end

    return { env = env, SuuUI = SuuUI, wow = wow, files = files }
end

--- Clears the compiled-chunk cache. Call after editing addon source in a long session.
function M.flushCache()
    chunkCache = {}
    tocCache = nil
end

return M
