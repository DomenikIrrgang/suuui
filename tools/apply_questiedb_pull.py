# tools/apply_questiedb_pull.py
# Puts a QuestieDB pull request (its diff from where it branched) on top of
# the files tools/fetch_quest_starts.sh fetched from QuestieDB's main.
# A hunk that adds whole entries ("[id] = { ... },") adds them to the
# table its function returns, wherever main has moved its neighbours to (an
# entry main already has is left as main has it); any other hunk must find
# its lines exactly as they were. Anything else stops with an error: then
# leave the pull request out until it is merged.
# Only the fetched files are touched; the diff is read as text, never run.
#   python3 -I tools/apply_questiedb_pull.py <dir> <pull.diff> <file> ...
import re, sys

DIR, DIFF, FILES = sys.argv[1], sys.argv[2], set(sys.argv[3:])
ENTRY = re.compile(r'^        \[(\d+)\] = \{')


def hunks(text):
    """(path, function header, [(op, line)]) per hunk, for the fetched files."""
    path = None
    for part in re.split(r'^(?=diff --git )', text, flags=re.M):
        m = re.search(r'^\+\+\+ b/(\S+)', part, re.M)
        path = m and m.group(1)
        if path not in FILES: continue
        for h in re.split(r'^(?=@@ )', part, flags=re.M)[1:]:
            head, *body = h.split('\n')
            lines = [(l[0], l[1:] + '\n') for l in body if l[:1] in (' ', '+', '-')]
            yield path, head.split('@@')[-1].strip(), lines


def entries(added):
    """The added lines as whole entries, or None."""
    out, cur = [], None
    for line in added:
        if cur is None:
            if not ENTRY.match(line): return None
            cur = [line]
        else:
            cur.append(line)
        if line.rstrip() == '        },':
            out.append(cur); cur = None
    return out if cur is None and out else None


texts, added, kept = {}, 0, 0
for path, function, lines in hunks(open(DIFF, encoding='utf-8').read()):
    src = texts.get(path) or open(f'{DIR}/{path}', encoding='utf-8').read()
    plus = [l for op, l in lines if op == '+']
    whole = entries(plus) if not any(op == '-' for op, _ in lines) else None
    if whole:
        at = src.find(function + '\n') if function else -1
        ret = src.find('    return {\n', at if at >= 0 else 0)
        if at < 0 or ret < 0: sys.exit(f'apply_questiedb_pull: {path}: no table for "{function}"')
        have = set(re.findall(r'^        \[(\d+)\] = \{', src, re.M))
        new = [e for e in whole if ENTRY.match(e[0]).group(1) not in have]
        kept += len(whole) - len(new)
        ret += len('    return {\n')
        src = src[:ret] + ''.join(''.join(e) for e in new) + src[ret:]
        added += len(new)
    else:
        old = ''.join(l for op, l in lines if op != '+')
        rep = ''.join(l for op, l in lines if op != '-')
        if src.count(old) != 1: sys.exit(f'apply_questiedb_pull: {path}: a hunk at "{function}" no longer fits main')
        src = src.replace(old, rep)
    texts[path] = src
for path, src in texts.items():
    open(f'{DIR}/{path}', 'w', encoding='utf-8').write(src)
print(f'apply_questiedb_pull: {len(texts)} files, {added} entries added ({kept} main has already)')
