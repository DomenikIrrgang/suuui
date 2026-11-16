import re,os
root='./src'
dirs=['Core','EditMode','SettingsUI','UI','Units']
pat=re.compile(r':SetAttribute\(|RegisterStateDriver|UnregisterStateDriver|RegisterUnitWatch|UnregisterUnitWatch|Secure\w*Template|SetOverrideBinding|ClearOverrideBindings|\bSetBinding\w*\(|SaveBindings|secure\.(visibility|\w+)\(|RegisterAttributeDriver|SetFrameRef|WrapScript|:Execute\(')
for d in dirs:
  for dp,_,fs in os.walk(os.path.join(root,d)):
    for f in sorted(fs):
      p=os.path.join(dp,f); L=open(p).read().split('\n')
      for i,l in enumerate(L):
        if l.strip().startswith('--') or not pat.search(l): continue
        ind=len(l)-len(l.lstrip()); cur=ind;j=i-1;names=[];guard=''
        while j>=0:
            s=L[j]
            if s.strip():
                si=len(s)-len(s.lstrip())
                if si<cur:
                    if re.search(r'InCombatLockdown|RunOutOfCombat|combat\.run|inCombat\(\)|defer\(',s): guard+='C'
                    if re.search(r'\bfunction\b|\bconstructor\b',s):
                        m=re.search(r'function\s+([\w.:]+)|(constructor)',s)
                        nm=(m.group(1) or m.group(2)) if m else 'anon'
                        names.append(nm)
                        if nm!='anon':
                            body='\n'.join(L[j:i])
                            if re.search(r'InCombatLockdown|RunOutOfCombat|combat\.run|inCombat\(\)',body): guard+='b'
                            break
                    cur=si
                    if si==0: break
            j-=1
        print('%s:%d | %s | %s | %s'%(p[len(root)+1:],i+1,'/'.join(names[:3]) or 'FILE',guard,l.strip()[:110]))
