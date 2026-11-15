local function build(f) local steps=assert(loadfile(f..".lua"))(); local t={}; for i=1,#steps do steps[i](t) end; return t end
local function ser(v)
  if type(v)~="table" then return type(v):sub(1,1)..tostring(v) end
  local keys={}; for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local o={}; for _,k in ipairs(keys) do o[#o+1]=tostring(k).."="..ser(v[k]) end
  return "{"..table.concat(o,",").."}"
end
local cs=build("CollectionSources")
local rows,distinct,inner,innerD,seen,seenI,ponly=0,0,0,0,{},{},0
for id,row in pairs(cs.item) do
  rows=rows+1; local s=ser(row); if not seen[s] then seen[s]=true; distinct=distinct+1 end
  local n=0; for k,v in pairs(row) do n=n+1; if type(v)=="table" then inner=inner+1; local si=ser(v); if not seenI[si] then seenI[si]=true; innerD=innerD+1 end end end
  if n==1 and row.p then ponly=ponly+1 end
end
print("CollectionSources.item rows",rows,"distinct",distinct,"inner lists",inner,"distinct",innerD,"p-only rows",ponly)
local rs=build("RecipeSources")
local rec,src,srcD,il,ilD,tt=0,0,0,0,0,0; seen,seenI={},{}
for id,list in pairs(rs) do rec=rec+1
  for _,s in ipairs(list) do src=src+1; local x=ser(s); if not seen[x] then seen[x]=true; srcD=srcD+1 end
    if x=="{t=st}" then tt=tt+1 end
    for k,v in pairs(s) do if type(v)=="table" then il=il+1; local si=ser(v); if not seenI[si] then seenI[si]=true; ilD=ilD+1 end end end end end
print("RecipeSources recipes",rec,"source tables",src,"distinct",srcD,"inner lists",il,"distinct",ilD,"{t='t'} only",tt)
local qs=build("QuestStarts")
local q,slots,used,sub=0,0,0,0
for id,row in pairs(qs.quests) do q=q+1; local mx=0; for k,v in pairs(row) do if k>mx then mx=k end; used=used+1; if type(v)=="table" then sub=sub+1 end end; slots=slots+mx end
print("QuestStarts.quests rows",q,"positions up to last used",slots,"non-nil",used,"sub tables",sub)
local mp=build("MapPlaces"); local n,sl,us=0,0,0
for id,row in pairs(mp.npcs) do n=n+1; local mx=0; for k,v in pairs(row) do if k>mx then mx=k end; us=us+1 end; sl=sl+mx end
print("MapPlaces.npcs rows",n,"positions",sl,"non-nil",us)
