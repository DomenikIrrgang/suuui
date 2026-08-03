#!/usr/bin/env lua
-- SuuUI test runner.
--
--   lua Tests/run.lua                      run everything
--   lua Tests/run.lua --filter Button      only suites/tests matching "Button"
--   lua Tests/run.lua -v                   list every passing test
--   lua Tests/run.lua --trace              print tracebacks for failures
--   lua Tests/run.lua Tests/spec/x_spec.lua   run one spec file
--
-- Run it from the addon root so relative paths resolve.

local scriptPath = arg[0]:gsub("[^/\\]+$", "")
local testsDir = (scriptPath == "" and "./" or scriptPath)
local addonRoot = testsDir:gsub("[/\\]$", ""):gsub("[^/\\]*$", "")
if addonRoot == "" then addonRoot = "." end
addonRoot = addonRoot:gsub("[/\\]$", "")
if addonRoot == "" then addonRoot = "." end

package.path = table.concat({
    testsDir .. "?.lua",
    testsDir .. "?/init.lua",
    package.path,
}, ";")

local framework = require("harness.framework")
local harness   = require("harness")

harness.root = addonRoot

local opts = { verbose = false, filter = nil, trace = false, color = true }
local explicitFiles = {}

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "-v" or a == "--verbose" then
        opts.verbose = true
    elseif a == "--trace" then
        opts.trace = true
    elseif a == "--no-color" then
        opts.color = false
    elseif a == "-f" or a == "--filter" then
        i = i + 1
        opts.filter = arg[i]
    elseif a:match("%.lua$") then
        explicitFiles[#explicitFiles + 1] = a
    end
    i = i + 1
end

--- Lists spec files, sorted, so run order is deterministic.
local function discoverSpecs()
    local files = {}
    local cmd = string.format('ls -1 "%sspec" 2>/dev/null', testsDir)
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            if line:match("_spec%.lua$") then files[#files + 1] = testsDir .. "spec/" .. line end
        end
        pipe:close()
    end
    table.sort(files)
    return files
end

local specs = #explicitFiles > 0 and explicitFiles or discoverSpecs()

if #specs == 0 then
    print("No spec files found under " .. testsDir .. "spec/")
    os.exit(1)
end

framework.install(_G)
_G.H = harness

for _, spec in ipairs(specs) do
    local chunk, err = loadfile(spec)
    if not chunk then
        print("Failed to load " .. spec .. ": " .. tostring(err))
        os.exit(1)
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        print("Error while declaring " .. spec .. ": " .. tostring(runErr))
        os.exit(1)
    end
end

local passed = framework.run(opts)
os.exit(passed and 0 or 1)
