import re,os,sys,collections,json
R='.'
def files(d):
    for dp,dn,fn in os.walk(os.path.join(R,d)):
        for f in fn:
            if f.endswith('.wowlua'): yield os.path.join(dp,f)
imp_re=re.compile(r'^(import\b.*?)\bfrom\s+"([^"]+)"',re.S)
def imports(path):
    lines=open(path).read().split('\n')
    out=[];i=0
    while i<len(lines):
        l=lines[i]
        if l.startswith('import ') or l.startswith('import\t') or l.strip()=='import':
            j=i;buf=l
            while 'from "' not in buf and j+1<len(lines) and j-i<40:
                j+=1;buf+='\n'+lines[j]
            m=imp_re.match(buf)
            if m:
                head=m.group(1)[len('import'):].strip()
                out.append((i+1,head,m.group(2)))
            i=j
        i+=1
    return out
def kind(head):
    # type-only if "type " prefix for whole statement
    if head.startswith('type '): return 'type'
    return 'value'
def resolve(path,target):
    if target.startswith('./') or target.startswith('../'):
        base=os.path.dirname(os.path.relpath(path,os.path.join(R,'src')))
        return '/'+os.path.normpath(os.path.join(base,target))
    return target
if __name__=='__main__':
    viol=collections.defaultdict(list)
    for p in sorted(files('src/Units')):
        rel=os.path.relpath(p,R)
        parts=rel.split('/')
        feature=parts[2].replace('.wowlua','')
        for ln,head,tgt in imports(p):
            t=resolve(p,tgt)
            if t=='/Core/API' or t.startswith('wowlua:') or t.startswith('/Data/') or t=='foreverlfg': continue
            if t.startswith('/Units/'):
                tf=t.split('/')[2]
                if tf==feature: continue
                viol['UNITS->other Units feature'].append((rel,ln,kind(head),head,t)); continue
            viol[t].append((rel,ln,kind(head),head,t))
    json.dump({k:v for k,v in viol.items()},open('viol.json','w'))
    tot=0
    for k in sorted(viol,key=lambda k:-len(viol[k])):
        v=viol[k]; tv=sum(1 for x in v if x[2]=='type')
        print(f"## {k}: {len(v)} imports ({tv} type-only, {len(v)-tv} value)")
        tot+=len(v)
        for rel,ln,kd,head,t in v:
            h=' '.join(head.split())
            print(f"  {rel}:{ln} [{kd}] {h[:150]}{' -> '+t if k.startswith('UNITS') else ''}")
    print('TOTAL',tot)
    print('--- reverse: UI/Core/others importing Units')
    for d in ['src/UI','src/Core','src/SettingsUI','src/EditMode','src/Data']:
        for p in sorted(files(d)):
            for ln,head,tgt in imports(p):
                t=resolve(p,tgt)
                if t.startswith('/Units/'):
                    print(' ',os.path.relpath(p,R),ln,kind(head),' '.join(head.split())[:120],t)
    print('--- UI/SettingsUI/EditMode importing API; Core importing UI')
    for d in ['src/UI','src/Core','src/SettingsUI','src/EditMode']:
        for p in sorted(files(d)):
            for ln,head,tgt in imports(p):
                t=resolve(p,tgt)
                rel=os.path.relpath(p,R)
                if t=='/Core/API' and rel!='src/Core/API.wowlua': print('  API<-',rel,ln)
                if d=='src/Core' and rel!='src/Core/API.wowlua' and (t.startswith('/UI/') or t.startswith('/SettingsUI') or t.startswith('/EditMode') or t.startswith('/Diagnostics')):
                    print('  Core->',rel,ln,kind(head),t)
                if d!='src/Core' and t.startswith('/Diagnostics'): print('  ->Diag',rel,ln,kind(head),t)
