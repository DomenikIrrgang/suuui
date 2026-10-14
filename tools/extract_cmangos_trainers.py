# tools/extract_cmangos_trainers.py
# What Classic's profession trainers teach and the skill each recipe asks
# for, from cMaNGOS's Classic world database (github.com/cmangos/classic-db,
# GPL-3.0; npc_trainer and npc_trainer_template, the teaching spells from
# spell_template), into tools/data/cmangos_trainers.tsv: profession, recipe ID,
# recipe, skill, cost (copper), level. Classic 1.12 values, not Forever's:
# Forever's own come from the trainers SuuUI records in game
# (tools/merge_trainer_records.lua); these are for the recipes no trainer has
# been recorded for yet (a trainer only lists recipes up to your rank).
#   curl -sfLO https://raw.githubusercontent.com/cmangos/classic-db/<commit>/Full_DB/ClassicDB_1_12_1_z2815.sql.gz
#   python3 -I tools/extract_cmangos_trainers.py <ClassicDB.sql.gz> <commit> tools/data/cmangos_trainers.tsv
import gzip, re, sys, collections

SRC, COMMIT, OUT = sys.argv[1:4]
PROFESSIONS = {'164': 'Blacksmithing', '165': 'Leatherworking', '171': 'Alchemy', '182': 'Herbalism',
               '185': 'Cooking', '186': 'Mining', '197': 'Tailoring', '202': 'Engineering',
               '333': 'Enchanting', '393': 'Skinning', '356': 'Fishing', '129': 'First Aid'}
LEARN_SPELL = '36'

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

trainers, spells, columns, inSchema = [], {}, [], False
with gzip.open(SRC, 'rt', encoding='utf-8', errors='replace') as f:
    for line in f:
        if line.startswith('CREATE TABLE `spell_template`'): inSchema = True; continue
        if inSchema:
            m = re.match(r"\s*`(\w+)`", line)
            if m: columns.append(m.group(1))
            elif line.startswith(')'): inSchema = False
            continue
        if line.startswith('INSERT INTO `npc_trainer'):
            # entry, spell, spellcost, reqskill, reqskillvalue, reqlevel, ...
            for v in tuples(line[line.index('VALUES') + 6:]):
                if v[3] in PROFESSIONS: trainers.append(v[1:6])
        elif line.startswith('INSERT INTO `spell_template`'):
            pick = [columns.index(c) for c in ('Id', 'Effect1', 'Effect2', 'Effect3',
                    'EffectTriggerSpell1', 'EffectTriggerSpell2', 'EffectTriggerSpell3', 'SpellName')]
            for v in tuples(line[line.index('VALUES') + 6:]):
                spells[v[0]] = [v[p] for p in pick]

# a trainer's spell teaches the recipe (LEARN_SPELL's trigger); keep the lowest skill, cost and level
best = {}
for spell, cost, skill, value, level in trainers:
    s = spells.get(spell)
    if not s: continue
    for i in range(3):
        if s[1 + i] == LEARN_SPELL and s[4 + i] != '0':
            recipe = s[4 + i]
            taught = spells.get(recipe, [None] * 8)
            if {'47', '118'} & set(taught[1:4]): continue   # a profession rank, not a recipe
            name = taught[7] or s[7]
            row = (PROFESSIONS[skill], int(recipe), name, int(value), int(cost), int(level))
            old = best.get(row[1])
            best[row[1]] = row if not old else (row[0], row[1], row[2], min(old[3], row[3]), min(old[4], row[4]), min(old[5], row[5]))

with open(OUT, 'w', encoding='utf-8') as o:
    o.write(f"# Classic profession trainers (cMaNGOS classic-db {COMMIT}, GPL-3.0): recipe, the skill it asks for, cost, level; Classic 1.12 values\n")
    o.write('profession\trecipeID\trecipe\tskill\tcost\tlevel\n')
    for row in sorted(best.values()):
        o.write('\t'.join(map(str, row)) + '\n')
print(len(best), 'recipes from', len(trainers), 'trainer rows')
