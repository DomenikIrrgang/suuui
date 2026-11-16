local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local function estimate(root)
  local seenT, seenS = {}, {}
  local tables, arr, hash, strBytes, strCount, nums = 0, 0, 0, 0, 0, 0
  local function str(s) if not seenS[s] then seenS[s] = true; strCount = strCount + 1; strBytes = strBytes + 25 + #s end end
  local function walk(t)
    if seenT[t] then return end
    seenT[t] = true; tables = tables + 1
    local n = #t
    arr = arr + n
    local h = 0
    for k, v in pairs(t) do
      local inArr = math.type(k) == "integer" and k >= 1 and k <= n
      if not inArr then h = h + 1; if type(k) == "string" then str(k) end end
      if type(v) == "table" then walk(v) elseif type(v) == "string" then str(v) elseif type(v) == "number" then nums = nums + 1 end
    end
    if h > 0 then local p = 1; while p < h do p = p * 2 end; hash = hash + p end
  end
  walk(root)
  return { tables = tables, strCount = strCount, strBytes = strBytes, bytes51 = tables * 64 + arr * 16 + hash * 40 + strBytes }
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local tot = {0,0,0}
for _, f in ipairs({ "QuestStarts", "MapPlaces", "CollectionSources", "RecipeSources", "FlightPaths", "MapOverlays" }) do
  local b0 = kb()
  local t0 = os.clock()
  local chunk = assert(loadfile(f .. ".lua"))
  local steps = chunk(); chunk = nil
  local tload = os.clock() - t0
  local b1 = kb()
  local n = #steps
  local t = {}
  local worst = 0
  local t1 = os.clock()
  for i = 1, n do local c = os.clock(); steps[i](t); steps[i] = nil; c = os.clock() - c; if c > worst then worst = c end end
  local trun = os.clock() - t1
  steps = nil
  local b2 = kb()
  local e = estimate(t)
  print(("%-18s steps %3d | unbuilt (code) %6.0f KB | built %6.0f KB (est 5.1 %6.0f KB, %d tables, %d uniq strings %.0f KB) | parse %.1f ms, build %.1f ms, worst step %.2f ms"):format(
    f, n, b1 - b0, b2 - b0, e.bytes51 / 1024, e.tables, e.strCount, e.strBytes / 1024, tload * 1000, trun * 1000, worst * 1000))
  tot[1] = tot[1] + b1 - b0; tot[2] = tot[2] + b2 - b0; tot[3] = tot[3] + e.bytes51 / 1024
  for k, v in pairs(t) do
    if type(v) == "table" and type(k) == "string" then
      local e2 = estimate(v)
      print(("    .%s: %d entries, est 5.1 %.0f KB (tables %d, strings %d / %.0f KB)"):format(k, count(v), e2.bytes51 / 1024, e2.tables, e2.strCount, e2.strBytes / 1024))
    end
  end
  KEEP = KEEP or {}; KEEP[f] = t
end
print(("SUM unbuilt %.0f KB, built %.0f KB, est5.1 %.0f KB"):format(tot[1], tot[2], tot[3]))
