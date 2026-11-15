local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local sum=0
for _, f in ipairs({'AuraCatalog','Talents','Defensives','FlightRoutes','InstanceLevels'}) do
  local b0=kb(); local t=assert(loadfile("e_"..f..".lua"))(); local b1=kb()
  print(("%-16s built at load %5.0f KB"):format(f,b1-b0)); sum=sum+b1-b0; KEEP=KEEP or {}; KEEP[f]=t
end
print(("eager sum %.0f KB"):format(sum))
for _, d in ipairs({'Presets','Trainer'}) do
  local protoSum, builtMin, builtMax = 0, 1e9, 0
  for _, c in ipairs({'DRUID','HUNTER','MAGE','PALADIN','PRIEST','ROGUE','SHAMAN','WARLOCK','WARRIOR'}) do
    local b0=kb(); local m=assert(loadfile("c_"..d.."_"..c..".lua"))(); local b1=kb()
    local built={}; for k,fn in pairs(m) do built[k]=fn() end; local b2=kb()
    protoSum=protoSum+(b1-b0); local bu=b2-b1; if bu<builtMin then builtMin=bu end; if bu>builtMax then builtMax=bu end
    io.write(("  %s/%s: functions %.0f KB, built %.0f KB\n"):format(d,c,b1-b0,bu))
    KEEP[d..c]=m
  end
  print(("%s: nine classes' functions %.0f KB; one class built %.0f-%.0f KB"):format(d,protoSum,builtMin,builtMax))
end
