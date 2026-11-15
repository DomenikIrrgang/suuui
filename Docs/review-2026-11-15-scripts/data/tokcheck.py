import json,re,sys
N=sys.argv[1]
tj=json.load(open(N+'/Design/tokens.json'))
gen=open(N+'/tools/gen_tokens.py').read()
tok=open(N+'/src/Core/Tokens.wowlua').read()
print('tokens.json top keys',list(tj.keys())[:20])
def names(o,out):
    if isinstance(o,dict):
        for k,v in o.items():
            out.add(k); names(v,out)
    elif isinstance(o,list):
        for v in o:
            names(v,out)
            if isinstance(v,dict) and 'name' in v: out.add(str(v['name']))
    return out
known=names(tj,set())
quoted=set(re.findall(r'\["([^"]+)"\]\s*=',tok))|set(re.findall(r'^\s+([A-Za-z_]\w*)\s*=',tok,re.M))
missing=[q for q in sorted(quoted) if q not in known and ('"%s"'%q) not in gen and ("'%s'"%q) not in gen and not re.search(r'\b%s\b'%re.escape(q),gen)]
print('keys in Tokens.wowlua found neither in tokens.json nor in gen_tokens.py:',len(missing),missing[:60])
