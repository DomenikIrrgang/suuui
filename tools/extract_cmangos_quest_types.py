# tools/extract_cmangos_quest_types.py
# Which of Classic's quests need a group, from cMaNGOS's Classic world
# database (github.com/cmangos/classic-db, GPL-3.0; quest_template's Type:
# 1 elite, 81 dungeon, 62 raid), into tools/data/cmangos_quest_types.tsv:
# quest ID, type. The game tags a quest only once it is in your log (probe
# questgroup), so the map marks the others from these and from QuestieDB's
# dungeon zones (tools/gen_quest_starts.lua). Classic 1.12 values: Forever's
# own new quests aren't in it.
#   curl -sfLO https://raw.githubusercontent.com/cmangos/classic-db/<commit>/Full_DB/ClassicDB_1_12_1_z2815.sql.gz
#   python3 -I tools/extract_cmangos_quest_types.py <ClassicDB.sql.gz> <commit> tools/data/cmangos_quest_types.tsv
import gzip, re, sys

SRC, COMMIT, OUT = sys.argv[1:4]
TYPES = {'1': 'elite', '81': 'dungeon', '62': 'raid'}

def tuples(s):
    """The value tuples of one INSERT line, quoted strings kept whole."""
    i, n = 0, len(s)
    while i < n:
        if s[i] != '(': i += 1; continue
        i += 1; vals, cur, q = [], [], False
        while i < n:
            ch = s[i]
            if q:
                if ch == '\\': cur.append(s[i + 1]); i += 2; continue
                if ch == "'": q = False
                else: cur.append(ch)
            elif ch == "'": q = True
            elif ch == ',': vals.append(''.join(cur)); cur = []
            elif ch == ')': vals.append(''.join(cur)); i += 1; break
            else: cur.append(ch)
            i += 1
        yield vals

quests, columns, inSchema = {}, [], False
with gzip.open(SRC, 'rt', encoding='utf-8', errors='replace') as f:
    for line in f:
        if line.startswith('CREATE TABLE `quest_template`'): inSchema = True; continue
        if inSchema:
            m = re.match(r'\s*`(\w+)`', line)
            if m: columns.append(m.group(1))
            elif line.startswith(')'): inSchema = False
            continue
        if line.startswith('INSERT INTO `quest_template`'):
            entry, kind = columns.index('entry'), columns.index('Type')
            for vals in tuples(line):
                if vals[kind] in TYPES: quests[int(vals[entry])] = TYPES[vals[kind]]

with open(OUT, 'w') as o:
    o.write(f"# Classic quests that need a group (cMaNGOS classic-db {COMMIT}, GPL-3.0): quest ID, elite, dungeon or raid; Classic 1.12 values\n")
    o.write('questID\ttype\n')
    for q in sorted(quests):
        o.write(f'{q}\t{quests[q]}\n')
print(f'{len(quests)} quests')
