# file-level non-hoisted `local NAME` / `local function NAME` / `const NAME` / `local { a, b }`
# referenced on an earlier line of the same file (wowlua hoists only top-level `function`, class, enum).
import re,os,sys
root=sys.argv[1]
def strip_file(src):
    # blank out comments and strings, keep line structure
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i]
        if src.startswith('--[',i):
            m=re.match(r'--\[(=*)\[',src[i:])
            if m:
                close=']'+m.group(1)+']'; j=src.find(close,i); j=n if j<0 else j+len(close)
                out.append(re.sub(r'[^\n]',' ',src[i:j])); i=j; continue
        if src.startswith('--',i):
            j=src.find('\n',i); j=n if j<0 else j
            out.append(' '*(j-i)); i=j; continue
        if c=='[' and re.match(r'\[(=*)\[',src[i:]):
            m=re.match(r'\[(=*)\[',src[i:]); close=']'+m.group(1)+']'; j=src.find(close,i); j=n if j<0 else j+len(close)
            out.append(re.sub(r'[^\n]',' ',src[i:j])); i=j; continue
        if c in '"\'`':
            j=i+1
            while j<n and src[j]!=c and src[j]!='\n':
                if src[j]=='\\': j+=1
                j+=1
            # interpolated strings `...{expr}...` : keep the {expr} parts readable
            body=src[i+1:j]
            if c=='`':
                keep=''.join(ch if depth else ' ' for ch,depth in _interp(body))
                out.append(' '+keep+' ')
            else:
                out.append('"'+' '*(j-i-1)+'"')
            i=j+1; continue
        out.append(c); i+=1
    return ''.join(out)
def _interp(body):
    d=0
    for ch in body:
        if ch=='{': d+=1; yield (' ',0); continue
        if ch=='}': d=max(0,d-1); yield (' ',0); continue
        yield (ch,d)
decl_re=[
 (re.compile(r'^(?:export\s+)?local\s+function\s+([A-Za-z_]\w*)'),'local function'),
 (re.compile(r'^(?:export\s+)?const\s+([A-Za-z_]\w*)'),'const'),
]
total=0
for dp,_,fs in sorted(os.walk(root)):
  for f in sorted(fs):
    if not f.endswith('.wowlua'): continue
    p=os.path.join(dp,f); rel=p[len(root)-3:]
    src=strip_file(open(p).read()); L=src.split('\n')
    decl={}  # name -> (line, kind)
    earlier=set()  # names bound at file level before (imports, hoisted)
    hoisted=set()
    for i,l in enumerate(L):
        m=re.match(r'^(?:export\s+)?(?:abstract\s+)?(?:function|class|enum)\s+([A-Za-z_]\w*)',l)
        if m: hoisted.add(m.group(1))
    for i,l in enumerate(L):
        names=[];kind=None
        for rx,k in decl_re:
            m=rx.match(l)
            if m: names=[m.group(1)];kind=k
        if not names:
            m=re.match(r'^(?:export\s+)?local\s+\{([^}]*)\}',l)
            if m: names=[re.match(r'\s*([A-Za-z_]\w*)',x).group(1) for x in m.group(1).split(',') if re.match(r'\s*[A-Za-z_]',x)];kind='local {}'
        if not names:
            m=re.match(r'^(?:export\s+)?local\s+([A-Za-z_]\w*(?:\s*:\s*[^=,]+?)?(?:\s*,\s*[A-Za-z_]\w*(?:\s*:\s*[^=,]+?)?)*)\s*(=|$)',l)
            if m:
                names=[re.match(r'\s*([A-Za-z_]\w*)',x).group(1) for x in re.split(r',(?![^<({]*[>)}])',m.group(1))];kind='local'
        if not names:
            m=re.match(r'^import\s+(.*)\s+from\b',l)
            if m:
                for nm in re.findall(r'[A-Za-z_]\w*',m.group(1)):
                    decl.setdefault(nm,(i,'import'))
            continue
        for nm in names:
            if nm=='_' : continue
            if nm not in decl and nm not in hoisted: decl[nm]=(i,kind)
    for nm,(dl,kind) in decl.items():
        if kind=='import': continue
        rx=re.compile(r'(?<![\w.:])'+re.escape(nm)+r'(?!\w)')
        for i in range(dl):
            l=L[i]
            for m in rx.finditer(l):
                before=l[:m.start()].rstrip(); after=l[m.end():]
                a=after.lstrip()
                if re.match(r'\??:\s',after) or (a.startswith(':') and not re.match(r':[A-Za-z_]\w*\(',a)): continue  # field/param declaration or type annotation
                if a.startswith('=') and not a.startswith('==') and (before.endswith(('{',',',';')) or before==''and l.startswith('    ')and False): continue  # table key
                if a.startswith('=') and not a.startswith('==') and l.rstrip().endswith((',','{')) and before=='': continue  # key on its own line in a table literal
                if re.search(r'\bfunction\s*$',before) and l[:1] in ' \t': continue  # a class method of the same name
                if re.match(r'^(export\s+)?type\s',l) or nm in ('number','string','boolean','type','T'): continue  # type position
                # shadowed? look back through the enclosing top-level statement
                j=i
                while j>0 and (L[j][:1] in (' ','\t','') or re.match(r'^(end|\}|\)|else|elseif|until)',L[j])): j-=1
                blk='\n'.join(L[j:i+1])
                sh=re.search(r'\blocal\s+(?:function\s+)?(?:\{[^}\n]*\b%s\b|[^=\n]*\b%s\b)'%(nm,nm),blk) or \
                   re.search(r'(?:function\b[^(\n]*|constructor|\bset\s+\w+|=\s*)\((?:[^()]|\([^()]*\))*\b%s\b\s*[:,)?]'%nm,blk) or \
                   re.search(r'\bfor\s+[^=\n]*\b%s\b[^\n]*\b(in|=)\b'%nm,blk) or \
                   re.search(r'^\s+(?:(?:static|readonly|private|protected|public)\s+)*%s\??\s*:'%nm,blk,re.M) or \
                   re.search(r'\(\s*(?:[\w?: .<>\[\]|{}]+,\s*)*%s\s*[,)]'%nm,blk)
                total+=1
                print('%s %s:%d  `%s` (%s at line %d)  | %s'%('SHADOW?' if sh else 'HIT    ',rel,i+1,nm,kind,dl+1,open(p).read().split('\n')[i].strip()[:150]))
print('total',total)
