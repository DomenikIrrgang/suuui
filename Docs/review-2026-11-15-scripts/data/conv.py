import re,sys
N=sys.argv[1]
for f in ['QuestStarts','MapPlaces','CollectionSources','RecipeSources','FlightPaths','MapOverlays']:
    s=open(f'{N}/src/Data/{f}.wowlua').read()
    m=re.search(r'^export const \w+Steps: .*? = \{$',s,re.M)
    body=s[m.end()-1:]
    body=re.sub(r'^    function\(t: [^)]*\)$','    function(t)',body,flags=re.M)
    open(f'{f}.lua','w').write('return '+body)
    print(f,len(body))
