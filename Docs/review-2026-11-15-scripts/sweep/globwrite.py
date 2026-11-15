import re,os,sys
root=sys.argv[1]
for d in ['Core','EditMode','SettingsUI','UI','Units']:
  for dp,_,fs in os.walk(os.path.join(root,d)):
    for f in sorted(fs):
      p=os.path.join(dp,f); src=open(p).read(); L=src.split('\n')
      declared=set(re.findall(r'\blocal\s+(?:function\s+)?([A-Za-z_]\w*)',src))
      for m in re.finditer(r'\blocal\s+([^=\n]+)',src):
          declared.update(re.findall(r'(?:^|,)\s*([A-Za-z_]\w*)',m.group(1)))
      for m in re.finditer(r'(?:function[^(\n]*|constructor)\(([^)]*)\)',src):
          declared.update(re.findall(r'(?:^|,)\s*([A-Za-z_]\w*)',m.group(1)))
      for m in re.finditer(r'\bfor\s+([^\n]*?)\s+(?:in|=)\b',src):
          declared.update(re.findall(r'[A-Za-z_]\w*',m.group(1)))
      for m in re.finditer(r'^import\s+(.*?)\s+from',src,re.M):
          declared.update(re.findall(r'[A-Za-z_]\w*',m.group(1)))
      declared.update(re.findall(r'^(?:export\s+)?(?:const|function|class|enum)\s+([A-Za-z_]\w*)',src,re.M))
      depth=0
      for i,l in enumerate(L):
          s=re.sub(r'--.*$','',l); s2=re.sub(r'"(\\.|[^"\\])*"','""',s)
          m=re.match(r'^\s+([A-Za-z_]\w*)\s*(?:[-+*/]|\.\.)?=(?!=)',s2)
          if m and depth==0 and m.group(1) not in declared and not s2.rstrip().endswith(','):
              print('%s:%d: %s'%(p[len(root)+1:],i+1,l.strip()[:120]))
          depth+=s2.count('{')-s2.count('}')
