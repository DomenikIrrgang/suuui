import re,os,collections,json
R='.'
src=open(R+'/src/Core/API.wowlua').read()
lines=src.split('\n')
top={};ui={};sub=collections.defaultdict(dict);raw={}
# blocks
def block(startpat):
    out=[];on=False
    for i,l in enumerate(lines):
        if re.match(startpat,l): on=True;continue
        if on:
            if l.startswith('}'): break
            m=re.match(r'\s+(\w+)\s*=',l)
            if m: out.append((m.group(1),i+1))
    return out
for n,i in block(r'^API\.UI = \{'): ui[n]=i
for n,i in block(r'^local rawUI = \{'): raw[n]=i
for i,l in enumerate(lines):
    m=re.match(r'^API\.UI\.(\w+)\s*=',l)
    if m: ui[m.group(1)]=i+1;continue
    m=re.match(r'^API\.(\w+)\.(\w+)\s*=',l)
    if m: sub[m.group(1)][m.group(2)]=i+1;continue
    m=re.match(r'^API\.(\w+)\s*=\s*(.*)',l)
    if m:
        top[m.group(1)]=i+1
        for k in re.findall(r'(\w+)\s*=',m.group(2)):
            sub[m.group(1)][k]=i+1
        continue
    m=re.match(r'^function API\.(\w+)\(',l)
    if m: top[m.group(1)]=i+1
# multi-line sub tables (EditMode, KeybindMode)
for name in ['EditMode','KeybindMode']:
    for n,i in block(r'^API\.%s = \{'%name): sub[name][n]=i
json.dump({'top':top,'ui':ui,'sub':sub,'raw':raw},open('exports.json','w'),indent=0)
print('top',len(top),'ui',len(ui),'raw',len(raw),{k:sorted(v) for k,v in sub.items()})
print('UI not in rawUI:',sorted(set(ui)-set(raw)))
print('rawUI not in UI:',sorted(set(raw)-set(ui)))

# ---- docs
docs={}
for f in ['Docs/API.md','Docs/PluginGuide.md','README.md']:
    docs[f]=open(R+'/'+f).read()
api=docs['Docs/API.md']
def documented(name,scope):
    # scope 'top' : SuuUI.name ; 'ui': SuuUI.UI.name or UI.name or bare in components
    if scope=='top':
        return re.search(r'SuuUI\.%s\b'%re.escape(name),api) is not None
    if scope=='ui':
        if re.search(r'\bUI\.%s\b'%re.escape(name),api): return 'qualified'
        if re.search(r'`%s\b'%re.escape(name),api) or re.search(r'[ ,(]`?%s\('%re.escape(name),api): return 'bare'
        return None
print('\n== A1a exported top-level, not documented as SuuUI.X in API.md')
for n in sorted(top):
    if not documented(n,'top'): print('  SuuUI.%s (API.wowlua:%d)'%(n,top[n]), ' [bare mention]' if re.search(r'\b%s\b'%n,api) else '')
print('\n== A1b exported SuuUI.UI.X, not documented')
for n in sorted(ui):
    d=documented(n,'ui')
    if not d: print('  SuuUI.UI.%s (API.wowlua:%d)'%(n,ui[n]),' [word appears]' if re.search(r'\b%s\b'%n,api) else '')
print('\n== A1c exported sub-table members not documented')
for t in sorted(sub):
    if t in ('UI','Raw'): continue
    for n in sorted(sub[t]):
        if not (re.search(r'SuuUI\.%s\.%s\b'%(t,n),api) or re.search(r'`\.%s\b'%n,api) or re.search(r'\.%s\('%n,api)):
            print('  SuuUI.%s.%s (API.wowlua:%d)'%(t,n,sub[t][n]))
print('\n== A1d documented but not exported')
seen=set()
for f,txt in docs.items():
    for m in re.finditer(r'SuuUI\.(\w+)(?:\.(\w+))?(?:\.(\w+))?',txt):
        a,b,c=m.groups()
        ln=txt.count('\n',0,m.start())+1
        key=(f,a,b)
        if a=='UI':
            if b and b not in ui and (f,'UI',b) not in seen: seen.add((f,'UI',b));print('  %s:%d SuuUI.UI.%s'%(f,ln,b))
        elif a in ('dev',): pass
        elif a not in top:
            if (f,a) not in seen: seen.add((f,a));print('  %s:%d SuuUI.%s'%(f,ln,a))
        elif b and a in sub and a not in('Tokens','LFG','Raw','Root') and b not in sub[a]:
            if key not in seen: seen.add(key);print('  %s:%d SuuUI.%s.%s'%(f,ln,a,b))
        elif a=='Raw' and b and b not in ('UI','Mixins','ns','Module'):
            print('  %s:%d SuuUI.Raw.%s'%(f,ln,b))
    for m in re.finditer(r'(?<![\w.])UI\.(\w+)',txt):
        b=m.group(1); ln=txt.count('\n',0,m.start())+1
        if b not in ui and (f,'UI',b) not in seen and not re.match(r'(lua|wowlua)$',b):
            seen.add((f,'UI',b)); print('  %s:%d UI.%s%s'%(f,ln,b,'  (in Raw.UI)' if b in raw else ''))
# components section bare names: `Name(` at start of table cell within Components..Layout
comp=api[api.index('## Components (0.2)'):api.index('## Edit mode (0.4)')]
for m in re.finditer(r'`([A-Z]\w+)\(',comp):
    b=m.group(1)
    if b not in ui and ('c',b) not in seen:
        seen.add(('c',b)); print('  Docs/API.md components: bare %s( not in SuuUI.UI'%b)
# messages
print('\n== messages')
decl=set(re.findall(r'declare message (SUUUI_\w+)',open(R+'/src/Core/Messages.d.wowlua').read()))
alldecl=set()
emitted=collections.defaultdict(list)
for dp,dn,fn in os.walk(R+'/src'):
    for f in fn:
        if f.endswith('.wowlua'):
            p=os.path.join(dp,f);t=open(p).read()
            for m in re.finditer(r'declare message (SUUUI_\w+)',t): alldecl.add(m.group(1))
            for m in re.finditer(r'"(SUUUI_[A-Z_]+)"',t):
                emitted[m.group(1)].append(os.path.relpath(p,R))
docmsg=set(re.findall(r'SUUUI_[A-Z_]+',api))
# expand _ENABLED etc
if 'SUUUI_MODULE_REGISTERED' in docmsg: docmsg|={'SUUUI_MODULE_ENABLED','SUUUI_MODULE_DISABLED','SUUUI_MODULE_ERRORED'}
print(' declared elsewhere than Messages.d:',sorted(alldecl-decl))
print(' used in src but not declared:',sorted(set(emitted)-alldecl))
print(' used/declared but not in API.md:',sorted((set(emitted)|alldecl)-docmsg))
print(' in API.md but not declared/used:',sorted(docmsg-(set(emitted)|alldecl)))
print(' in API.md messages table?')
tbl=api[api.index("### SuuUI's messages"):api.index('## Extending SuuUI')]
tm=set(re.findall(r'SUUUI_[A-Z_]+',tbl))|{'SUUUI_MODULE_ENABLED','SUUUI_MODULE_DISABLED','SUUUI_MODULE_ERRORED'}
print(' declared/used but missing from the messages TABLE:',sorted((set(emitted)|alldecl)-tm))
for k in sorted((set(emitted)|alldecl)-tm): print('   ',k,sorted(set(emitted.get(k,[])))[:6])
# module methods
mod=open(R+'/src/Core/Modules.wowlua').read()
cls=mod[mod.index('export class Module<'):mod.index('export type PluginDef')]
meths=re.findall(r'^    function (\w+)',cls,re.M)
getters=re.findall(r'^    get (\w+)\(',cls,re.M)
print('\n== module methods not documented as M:X in API.md')
for n in meths:
    if not re.search(r'[M`]:%s\b'%n,api) and not re.search(r'module:%s\b'%n,api): print('  M:%s'%n, '[word appears]' if re.search(r'\b%s\b'%n,api) else '')
print(' getters not documented as M.X:',[g for g in getters if not re.search(r'M\.%s\b'%g,api)])
print(' documented M:X not methods:',sorted(set(re.findall(r'\bM:(\w+)',api))-set(meths)))
loose=mod[mod.index('export type ModuleOf<D>'):mod.index('export type LooseDef')]
lm=set(re.findall(r'^    (\w+):',loose,re.M))
print(' class methods missing from ModuleOf (loose type):',sorted(set(meths)-lm))
# services
sk=open(R+'/src/Core/ServiceKeys.wowlua').read()
keys=dict(re.findall(r'export const (\w+): ServiceKey<\w+> = ServiceKey\.new\("(\w+)"\)',sk))
print('\n== services: keys',keys)
svc=api[api.index('### Services and replacing'):api.index('**Replacing a module.**')]
docsvc=set(re.findall(r'^\| `(\w+)`',svc,re.M))
print(' service keys not in docs table:',sorted(set(keys.values())-docsvc),' docs not in keys:',sorted(docsvc-set(keys.values())))
prov=collections.defaultdict(list)
for dp,dn,fn in os.walk(R+'/src'):
    for f in fn:
        if f.endswith('.wowlua'):
            p=os.path.join(dp,f)
            for i,l in enumerate(open(p)):
                m=re.search(r':Provide(Service)?\(\s*("?\w+"?)',l)
                if m: prov[m.group(2)].append('%s:%d'%(os.path.relpath(p,R),i+1))
                m=re.search(r'(SuuUI\.Service|services\.get|SuuUI\.UseService|services\.use)\(\s*("?\w+"?)',l)
                if m: prov['USE '+m.group(2)].append('%s:%d'%(os.path.relpath(p,R),i+1))
for k in sorted(prov): print('  ',k,prov[k][:8],len(prov[k]))
