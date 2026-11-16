import re,os,sys
root='./src'
dirs=['Core','EditMode','SettingsUI','UI','Units']
pat=re.compile(r'hooksecurefunc\(|\bhookScript\(|\bhook\(|:HookScript\(')
rows=[]
for d in dirs:
  for dp,_,fs in os.walk(os.path.join(root,d)):
    for f in sorted(fs):
      p=os.path.join(dp,f); L=open(p).read().split('\n')
      for i,l in enumerate(L):
        if l.strip().startswith('--') or not pat.search(l): continue
        ind=len(l)-len(l.lstrip())
        # enclosing named function chain
        chain=[];cur=ind;j=i-1;top=None;guard=''
        while j>=0:
            s=L[j]
            if s.strip():
                si=len(s)-len(s.lstrip())
                if si<cur and re.search(r'\bfunction\b|\bconstructor\b',s):
                    m=re.search(r'function\s+([\w.:]+)|(constructor)',s)
                    nm=(m.group(1) or m.group(2)) if m else 'anon'
                    chain.append(nm); cur=si
                    if nm!='anon' and top is None: top=j
                    if si==0: break
                elif si<cur and re.match(r'\s*(class|if|for|while|else|elseif|do|local function)',s) is None and si==0:
                    break
            j-=1
        named=[c for c in chain if c!='anon']
        encl=named[0] if named else 'FILE'
        if top is not None:
            body='\n'.join(L[top:i])
            if re.search(r'if (not )?[\w.\[\]:()"]*(hooked|Hooked|skinned|Skinned|once|Once|wrapped|Wrapped|done|Done|built|Built|made|watched|Watched|styled|Styled|seen)[\w.\[\]]*( then|\s*==|\s*~=)',body): guard='G'
            elif re.search(r'if [^\n]* then\s*\n\s*return',body): guard='r'
        m=re.search(r'(hooksecurefunc|hookScript|hook|:HookScript)\(\s*([^,)]*)',l)
        tgt=l.strip()[:95]
        rows.append((p[len(root)+1:],i+1,encl,'/'.join(chain[:4]),guard,tgt))
for r in rows: print('%s:%d | %s | %s | %s | %s'%(r[0],r[1],r[2],r[4],r[3],r[5]))
