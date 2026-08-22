-- Minimal BDD test framework. No external dependencies.
-- describe / it / before_each / after_each / before_all / after_all + expect().
local M = {}

local root = { name = "", children = {}, tests = {}, depth = -1 }
local current = root
local focused = false

local results = { passed = 0, failed = 0, skipped = 0, failures = {}, tests = 0 }

--- Declares a group of tests.
-- @param name string
-- @param fn function
function M.describe(name, fn)
    local group = {
        name       = name,
        parent     = current,
        depth      = current.depth + 1,
        children   = {},
        tests      = {},
        beforeEach = {},
        afterEach  = {},
        beforeAll  = {},
        afterAll   = {},
    }
    table.insert(current.children, group)
    local prev = current
    current = group
    fn()
    current = prev
    return group
end

--- Declares a single test case.
-- @param name string
-- @param fn function
function M.it(name, fn)
    table.insert(current.tests, { name = name, fn = fn, group = current })
end

--- Declares a test that is reported as skipped without running.
function M.xit(name, fn)
    table.insert(current.tests, { name = name, fn = fn, group = current, skip = true })
end

--- Declares a test that, once present, is the only one that runs.
function M.fit(name, fn)
    focused = true
    table.insert(current.tests, { name = name, fn = fn, group = current, only = true })
end

function M.before_each(fn) table.insert(current.beforeEach, fn) end
function M.after_each(fn)  table.insert(current.afterEach, fn) end
function M.before_all(fn)  table.insert(current.beforeAll, fn) end
function M.after_all(fn)   table.insert(current.afterAll, fn) end

----------------------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------------------

local DEFAULT_TOL = 0.001

-- Depth and cycle capped. A widget handle is a table whose fields reach frames, which
-- point back at their parent and at every sibling, so formatting one naively recurses
-- until the stack goes -- and a spec comparing two handles then reports "stack overflow"
-- instead of a diagnosis, exactly when it most needs one. Depth is capped rather than
-- made cycle-safe alone: an acyclic frame tree is still far too deep to read.
local FMT_MAX_DEPTH = 4

local function fmt(v, depth, seen)
    depth = depth or 0
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return string.format("%.4f", v)
    elseif type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "table" then
        if depth >= FMT_MAX_DEPTH then return "{...}" end
        seen = seen or {}
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 8 then table.insert(parts, "...") break end
            if type(k) == "number" then
                table.insert(parts, fmt(val, depth + 1, seen))
            else
                table.insert(parts, tostring(k) .. "=" .. fmt(val, depth + 1, seen))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

M.fmt = fmt

local function fail(msg, note)
    error({ __assertion = true, message = msg .. (note and ("  -- " .. note) or "") }, 3)
end

local function deepEq(a, b, tol)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" then return math.abs(a - b) <= (tol or DEFAULT_TOL) end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deepEq(v, b[k], tol) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

M.deepEq = deepEq

local Expect = {}
Expect.__index = Expect

-- Assertions read as expect(x).eq(y), so lookups hand back a bound closure rather
-- than a raw method. That keeps specs free of the colon and lets calls chain.
local expectProxy = {
    __index = function(t, key)
        -- A nil subject means the stored fields miss too, so name them explicitly
        if key == "actual" or key == "note" then return nil end
        local fn = Expect[key]
        if not fn then
            error("harness: unknown assertion 'expect(...)." .. tostring(key) .. "'", 2)
        end
        return function(...) return fn(t, ...) end
    end,
}

--- Wraps a value in an assertion chain.
-- @param actual any
-- @return table
function M.expect(actual)
    return setmetatable({ actual = actual }, expectProxy)
end

--- Attaches a note shown on failure.
-- @param text string
function Expect:as(text)
    self.note = text
    return self
end

function Expect:eq(expected)
    if type(self.actual) == "number" and type(expected) == "number" then
        if math.abs(self.actual - expected) > DEFAULT_TOL then
            fail("expected " .. fmt(expected) .. ", got " .. fmt(self.actual), self.note)
        end
    elseif self.actual ~= expected then
        fail("expected " .. fmt(expected) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:neq(expected)
    if self.actual == expected then
        fail("expected value to differ from " .. fmt(expected), self.note)
    end
    return self
end

--- Numeric comparison with an explicit tolerance (default 0.5 px).
-- @param expected number
-- @param tol number
function Expect:near(expected, tol)
    tol = tol or 0.5
    if type(self.actual) ~= "number" then
        fail("expected a number near " .. fmt(expected) .. ", got " .. fmt(self.actual), self.note)
    end
    if math.abs(self.actual - expected) > tol then
        fail("expected " .. fmt(expected) .. " +/-" .. fmt(tol) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:truthy()
    if not self.actual then fail("expected truthy, got " .. fmt(self.actual), self.note) end
    return self
end

function Expect:falsy()
    if self.actual then fail("expected falsy, got " .. fmt(self.actual), self.note) end
    return self
end

function Expect:isNil()
    if self.actual ~= nil then fail("expected nil, got " .. fmt(self.actual), self.note) end
    return self
end

function Expect:notNil()
    if self.actual == nil then fail("expected non-nil", self.note) end
    return self
end

function Expect:gt(n)
    if not (self.actual > n) then
        fail("expected > " .. fmt(n) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:gte(n)
    if not (self.actual >= n) then
        fail("expected >= " .. fmt(n) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:lt(n)
    if not (self.actual < n) then
        fail("expected < " .. fmt(n) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:lte(n)
    if not (self.actual <= n) then
        fail("expected <= " .. fmt(n) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:between(lo, hi)
    if self.actual < lo or self.actual > hi then
        fail("expected within [" .. fmt(lo) .. ", " .. fmt(hi) .. "], got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:deepEq(expected, tol)
    if not deepEq(self.actual, expected, tol) then
        fail("expected " .. fmt(expected) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:matches(pattern)
    if type(self.actual) ~= "string" or not self.actual:match(pattern) then
        fail("expected string matching " .. fmt(pattern) .. ", got " .. fmt(self.actual), self.note)
    end
    return self
end

function Expect:contains(needle)
    if type(self.actual) == "string" then
        if not self.actual:find(needle, 1, true) then
            fail("expected " .. fmt(self.actual) .. " to contain " .. fmt(needle), self.note)
        end
        return self
    end
    for _, v in pairs(self.actual) do
        if v == needle then return self end
    end
    fail("expected table to contain " .. fmt(needle), self.note)
end

function Expect:len(n)
    if #self.actual ~= n then
        fail("expected length " .. fmt(n) .. ", got " .. fmt(#self.actual), self.note)
    end
    return self
end

--- Asserts the wrapped function raises. Optional pattern matched against the message.
-- @param pattern string
function Expect:throws(pattern)
    local ok, err = pcall(self.actual)
    if ok then fail("expected function to raise", self.note) end
    if pattern then
        local msg = type(err) == "table" and (err.message or "") or tostring(err)
        if not msg:find(pattern, 1, true) then
            fail("expected error containing " .. fmt(pattern) .. ", got " .. fmt(msg), self.note)
        end
    end
    return self
end

function Expect:notThrows()
    local ok, err = pcall(self.actual)
    if not ok then
        local msg = type(err) == "table" and (err.message or "") or tostring(err)
        fail("expected no error, got " .. fmt(msg), self.note)
    end
    return self
end

----------------------------------------------------------------------------------
-- Runner
----------------------------------------------------------------------------------

local COLOR = {
    reset = "\27[0m", red = "\27[31m", green = "\27[32m",
    yellow = "\27[33m", grey = "\27[90m", bold = "\27[1m", cyan = "\27[36m",
}

local useColor = true
local function c(name, s)
    if not useColor then return s end
    return COLOR[name] .. s .. COLOR.reset
end

local function chainOf(group, field)
    local out = {}
    local stack = {}
    local g = group
    while g and g ~= root do table.insert(stack, 1, g) g = g.parent end
    for _, node in ipairs(stack) do
        for _, fn in ipairs(node[field] or {}) do table.insert(out, fn) end
    end
    return out
end

local function fullName(group)
    local parts = {}
    local g = group
    while g and g ~= root do table.insert(parts, 1, g.name) g = g.parent end
    return table.concat(parts, " > ")
end

local function runTest(test, opts)
    results.tests = results.tests + 1
    local indent = string.rep("  ", test.group.depth + 1)

    if test.skip or (focused and not test.only) then
        results.skipped = results.skipped + 1
        if opts.verbose then print(indent .. c("yellow", "- " .. test.name)) end
        return
    end

    local errObj
    local function handler(e)
        if type(e) == "table" and e.__assertion then return e end
        return { message = tostring(e), traceback = debug.traceback("", 2) }
    end

    for _, fn in ipairs(chainOf(test.group, "beforeEach")) do
        local ok, e = xpcall(fn, handler)
        if not ok then errObj = e break end
    end

    if not errObj then
        local ok, e = xpcall(test.fn, handler)
        if not ok then errObj = e end
    end

    local afters = chainOf(test.group, "afterEach")
    for i = #afters, 1, -1 do
        local ok, e = xpcall(afters[i], handler)
        if not ok and not errObj then errObj = e end
    end

    if errObj then
        results.failed = results.failed + 1
        table.insert(results.failures, {
            name = fullName(test.group) .. " > " .. test.name,
            message = errObj.message,
            traceback = errObj.traceback,
        })
        print(indent .. c("red", "x " .. test.name))
        print(indent .. "  " .. c("red", errObj.message or "?"))
    else
        results.passed = results.passed + 1
        if opts.verbose then print(indent .. c("green", "v " .. test.name)) end
    end
end

local function runGroup(group, opts)
    local matches = not opts.filter or fullName(group):lower():find(opts.filter:lower(), 1, true)

    local anyTest = #group.tests > 0
    if group ~= root and (anyTest or #group.children > 0) then
        print(string.rep("  ", group.depth) .. c("bold", group.name))
    end

    if anyTest then
        for _, fn in ipairs(group.beforeAll or {}) do fn() end
    end
    for _, test in ipairs(group.tests) do
        if matches or (opts.filter and test.name:lower():find(opts.filter:lower(), 1, true)) then
            runTest(test, opts)
        else
            results.skipped = results.skipped + 1
        end
    end
    for _, child in ipairs(group.children) do runGroup(child, opts) end
    if anyTest then
        for _, fn in ipairs(group.afterAll or {}) do fn() end
    end
end

--- Runs every declared test and prints a report.
-- @param opts table  { filter, verbose, color }
-- @return bool  true when everything passed
function M.run(opts)
    opts = opts or {}
    if opts.color == false then useColor = false end
    local start = os.clock()
    runGroup(root, opts)
    local elapsed = os.clock() - start

    print("")
    if #results.failures > 0 then
        print(c("bold", "Failures:"))
        for i, f in ipairs(results.failures) do
            print(c("red", string.format("%3d) %s", i, f.name)))
            print("     " .. (f.message or "?"))
            if opts.trace and f.traceback then
                print(c("grey", (f.traceback:gsub("\n", "\n     "))))
            end
        end
        print("")
    end

    local summary = string.format("%d passed, %d failed, %d skipped  (%.0f ms)",
        results.passed, results.failed, results.skipped, elapsed * 1000)
    print(results.failed == 0 and c("green", summary) or c("red", summary))
    return results.failed == 0
end

--- Clears all declared suites and results. Used between runner invocations.
function M.reset()
    root = { name = "", children = {}, tests = {}, depth = -1 }
    current = root
    focused = false
    results = { passed = 0, failed = 0, skipped = 0, failures = {}, tests = 0 }
end

--- Installs describe/it/expect and friends into a table (usually _G).
-- @param env table
function M.install(env)
    env.describe = M.describe
    env.it = M.it
    env.xit = M.xit
    env.fit = M.fit
    env.before_each = M.before_each
    env.after_each = M.after_each
    env.before_all = M.before_all
    env.after_all = M.after_all
    env.expect = M.expect
end

return M
