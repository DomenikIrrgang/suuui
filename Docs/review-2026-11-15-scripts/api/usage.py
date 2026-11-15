import re,os,collections,json
R='.'
ex=json.load(open('exports.json'))
top,ui,sub,raw=ex['top'],ex['ui'],ex['sub'],ex['raw']
def strip(t):
    # remove comments and strings (keep line structure)
    t=re.sub(r'--\[\[.*?\]\]',lambda m:'\n'*m.group(0).count('\n'),t,flags=re.S)
    out=[]
    for l in t.split('\n'):
        # naive: remove strings then comments
        l2=re.sub(r'"(?:[^"\\]|\\.)*"','""',l)
        l2=re.sub(r"'(?:[^'\\]|\\.)*'","''",l2)
        l2=re.sub(r'--.*$','',l2)
        out.append(l2)
    return out
use_top=collections.defaultdict(list);use_ui=collections.defaultdict(list);use_sub=collections.defaultdict(list)
missing=[]
dyn=[]
def scan(path,group):
    rel=os.path.relpath(path,R)
    L=strip(open(path).read())
    txt='\n'.join(L)
    aliases={}  # local name -> path like 'UI','Tokens','Layout'
    for m in re.finditer(r'\b(?:local|const)\s+([\w, ]+?)\s*=\s*((?:SuuUI\.\w+\s*,\s*)*SuuUI\.\w+)\s*$',txt,re.M):
        names=[x.strip() for x in m.group(1).split(',')]; vals=[x.strip() for x in m.group(2).split(',')]
        for nm,v in zip(names,vals):
            aliases[nm]=v.split('.')[1]
            use_top[v.split('.')[1]].append((group,rel,txt.count('\n',0,m.start())+1))
    hasS = 'SuuUI' in txt
    for i,l in enumerate(L):
        for m in re.finditer(r'(?<![\w.:])SuuUI\.(\w+)(?:\.(\w+))?',l):
            a,b=m.groups()
            if a=='UI':
                use_top['UI'].append((group,rel,i+1))
                if b: 
                    use_ui[b].append((group,rel,i+1))
                    if b not in ui: missing.append((rel,i+1,'SuuUI.UI.'+b, 'in Raw.UI' if b in raw else ''))
                continue
            use_top[a].append((group,rel,i+1))
            if a not in top: missing.append((rel,i+1,'SuuUI.'+a,''))
            elif b and a in sub and a!='Raw':
                use_sub[a+'.'+b].append((group,rel,i+1))
                if b not in sub[a]: missing.append((rel,i+1,'SuuUI.%s.%s'%(a,b),''))
        if re.search(r'SuuUI(\.UI)?\s*\[',l) or re.search(r'(?<![\w.])UI\s*\[',l) and aliases.get('UI')=='UI': dyn.append((rel,i+1,l.strip()[:120]))
        for al,tgt in aliases.items():
            for m in re.finditer(r'(?<![\w.:])%s\.(\w+)'%re.escape(al),l):
                b=m.group(1)
                if tgt=='UI':
                    use_ui[b].append((group,rel,i+1))
                    if b not in ui: missing.append((rel,i+1,'UI.'+b+' (alias of SuuUI.UI)','in Raw.UI' if b in raw else ''))
                elif tgt in ('Tokens','LFG'): pass
                elif tgt in sub and tgt not in ('Raw',):
                    use_sub[tgt+'.'+b].append((group,rel,i+1))
                    if b not in sub[tgt]: missing.append((rel,i+1,'%s.%s (alias of SuuUI.%s)'%(al,b,tgt),''))
    return aliases
allal=collections.Counter()
groups={'units':'src/Units','examples':'Examples','ui':'src/UI','settingsui':'src/SettingsUI','editmode':'src/EditMode','core':'src/Core','diag':'src/Diagnostics','tests':'tests'}
for g,d in groups.items():
    for dp,dn,fn in os.walk(os.path.join(R,d)):
        for f in fn:
            if f.endswith('.wowlua'):
                p=os.path.join(dp,f)
                if p.endswith('src/Core/API.wowlua'): continue
                al=scan(p,g)
                if g in('units','examples'):
                    for k,v in al.items(): allal[(k,v)]+=1
print('aliases in Units/Examples:',dict(allal))
print('\n== A2a used but NOT exported (nil in game)')
for g in ['units','examples','ui','settingsui','editmode','core','diag','tests']:
    pass
seen=collections.defaultdict(list)
for rel,ln,name,note in missing:
    seen[(name,note)].append('%s:%d'%(rel,ln))
for (name,note),locs in sorted(seen.items()):
    print('  %s %s  x%d: %s'%(name,note,len(locs),', '.join(locs[:6])))
print('\n== dynamic access:');[print('  ',d) for d in dyn[:30]]
def cnt(lst):
    c=collections.Counter(g for g,_,_ in lst); return dict(c)
api=open(R+'/Docs/API.md').read()
print('\n== A2b exports not used by src (outside API.wowlua) or Examples; [T]=used only by tests')
def report(name,full,uses,line):
    c=cnt(uses)
    prod=sum(v for k,v in c.items() if k not in('tests','diag'))
    if prod==0:
        print('  %-40s API.wowlua:%-5d %s'%(full,line,'[tests/diag only: %s]'%c if c else '[unused anywhere]'))
        return 1
    return 0
n=0
for k in sorted(top): n+=report(k,'SuuUI.'+k,use_top.get(k,[]),top[k])
print('  -- top unused:',n,'of',len(top)); n=0
for k in sorted(ui): n+=report(k,'SuuUI.UI.'+k,use_ui.get(k,[]),ui[k])
print('  -- UI unused:',n,'of',len(ui)); 
for t in sorted(sub):
    if t in('Raw','UI'):continue
    for k in sorted(sub[t]): report(k,'SuuUI.%s.%s'%(t,k),use_sub.get(t+'.'+k,[]),sub[t][k])
json.dump({'top':{k:cnt(v) for k,v in use_top.items()},'ui':{k:cnt(v) for k,v in use_ui.items()},'sub':{k:cnt(v) for k,v in use_sub.items()}},open('usage.json','w'))
print('\n== usage of exports by group (units only vs direct import)')
print(' UI names used via SuuUI.UI in Units:',sum(1 for k in ui if cnt(use_ui.get(k,[])).get('units')), 'of',len(ui))
