import re,sys,os
N=sys.argv[1]
for f in ['AuraCatalog','Talents','Defensives','FlightRoutes','InstanceLevels','RaidPlanner']:
    s=open(f'{N}/src/Data/{f}.wowlua').read()
    m=re.search(r'^export local \w+: [^=]+ = \{$',s,re.M)
    body=s[m.end()-1:]
    if '::' in body or 'export' in body: print('WARN',f, body.count('::'), body.count('export'))
    open(f'e_{f}.lua','w').write('return '+body)
for d in ['Presets','Trainer']:
    for c in ['DRUID','HUNTER','MAGE','PALADIN','PRIEST','ROGUE','SHAMAN','WARLOCK','WARRIOR']:
        s=open(f'{N}/src/Data/{d}/{c}.wowlua').read()
        names=re.findall(r'^export function (\w+)\(\): [^\n]*? return \{$',s,re.M)
        s2=re.sub(r'^export function (\w+)\(\): [^\n]*? return \{$',r'local function \1() return {',s,flags=re.M)
        if 'export' in s2 or '::' in s2 or 'import' in s2: print('WARN',d,c,[l for l in s2.split('\n') if 'export' in l or '::' in l or 'import' in l][:3])
        s2+='\nreturn {'+','.join(f'{n}={n}' for n in names)+'}\n'
        open(f'c_{d}_{c}.lua','w').write(s2)
