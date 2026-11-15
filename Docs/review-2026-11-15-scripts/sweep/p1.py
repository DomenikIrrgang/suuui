import re,sys,os
root='./src'
dirs=['Core','EditMode','SettingsUI','UI','Units']
def strip(s):
    # remove strings and comments crudely
    s=re.sub(r'"(\\.|[^"\\])*"','""',s)
    s=re.sub(r"'(\\.|[^'\\])*'","''",s)
    s=re.sub(r'--.*$','',s)
    return s
def toplevel_split(s):
    parts=[];d=0;cur=''
    for ch in s:
        if ch in '([{': d+=1
        elif ch in ')]}': d-=1
        if ch==',' and d==0: parts.append(cur);cur=''
        else: cur+=ch
    parts.append(cur);return parts
def top_has_andor(e):
    d=0;out=''
    for ch in e:
        if ch in '([{': d+=1
        elif ch in ')]}': d-=1
        elif d==0: out+=ch
        if d==0 and ch in ')]}': out+=' @ '
    return re.search(r'\b(and|or)\b',out) is not None
def ends_with_call(e):
    return re.search(r'\)\s*$',e) is not None
n_assign=0;n_ret=0;DBG=[0,0]
for d in dirs:
  for dp,_,fs in os.walk(os.path.join(root,d)):
    for f in fs:
      p=os.path.join(dp,f)
      lines=open(p).read().split('\n')
      i=0
      # function return type stack by indent
      stack=[]
      while i<len(lines):
        raw=strip(lines[i]); start=i
        # join until balanced
        bal=raw.count('(')+raw.count('{')+raw.count('[')-raw.count(')')-raw.count('}')-raw.count(']')
        st=raw
        while (bal>0 or re.search(r'(\band|\bor|=|,)\s*$',st)) and i+1<len(lines) and i-start<12:
            i+=1; nx=strip(lines[i]); st+=' '+nx.strip()
            bal+=nx.count('(')+nx.count('{')+nx.count('[')-nx.count(')')-nx.count('}')-nx.count(']')
        indent=len(raw)-len(raw.lstrip())
        m=re.search(r'\bfunction\b[^(]*\(.*\)\s*:\s*\((.*)\)\s*$',raw)
        if re.search(r"\bfunction\b",raw):
            DBG[0]+=1
            multi = bool(m and len(toplevel_split(m.group(1)))>1)
            while stack and stack[-1][0]>=indent: stack.pop()
            stack.append((indent,multi))
        else:
            while stack and stack[-1][0]>=indent and raw.strip(): stack.pop()
        s=st.strip()
        m=re.match(r'(local\s+)?([A-Za-z_][\w.\[\]]*(\s*:\s*[^=,]+)?(\s*,\s*[A-Za-z_][\w.\[\]]*(\s*:\s*[^=,]+)?)+)\s*=\s*(.+)$',s)
        if m and not s.startswith(('if ','for ','return','while ')):
            nv=len(toplevel_split(m.group(2))); ex=toplevel_split(m.group(6))
            if len(ex)<nv and top_has_andor(ex[-1]):
                n_assign+=1; print('ASSIGN %s:%d: %s'%(p[len(root)-3:],start+1,s[:200]))
        m=re.match(r'return\s+(.+)$',s)
        if m and stack and stack[-1][1]:
            ex=toplevel_split(m.group(1))
            if len(ex)==1 and top_has_andor(ex[0]):
                n_ret+=1; print('RETURN %s:%d: %s'%(p[len(root)-3:],start+1,s[:200]))
        i+=1
print(n_assign,n_ret,DBG)
