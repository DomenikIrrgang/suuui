# tools/gen_recipes.py
# Every profession recipe of Forever with where it is learned, into
# tools/data/forever_recipes.tsv (one line each) and forever_recipes.json (all
# vendors and drops, trainers per profession).
#   * the recipes: Forever's client tables (DB2) from wago.tools. A
#     profession's crafting spells with a name, in a category or making an
#     item; matched recipe by recipe against the game's own lists (/suu probe
#     professions, all twelve professions, 2026-10-14)
#   * where they are learned: the item that teaches one (ItemEffect, trigger
#     6), and that item's vendors, drops, objects and quests from QuestieDB's
#     Forever data (github.com/Questie/QuestieDB, no license stated); no item
#     is "trainer" (the game gives no sources: GetRecipeSourceText is nil)
#   sh tools/fetch_recipe_sources.sh <dir>
#   lua tools/extract_questie.lua <dir>/questiedb <dir>
#   python3 -I tools/gen_recipes.py <dir> tools/data
import csv, sys, os, json, collections
DIR, OUT = sys.argv[1:3]
W = os.path.join(DIR, 'wago')
Q = DIR
SOURCES = dict(l.rstrip('\n').split('\t', 1) for l in open(os.path.join(DIR, 'SOURCES')))
def rows(t): return csv.DictReader(open(os.path.join(W, t + '.csv'), encoding='utf-8'))
def tsv(name): return csv.DictReader(open(os.path.join(Q, name), encoding='utf-8'), delimiter='\t', quoting=csv.QUOTE_NONE)

PROFESSIONS = {'164','165','171','182','185','186','197','202','333','393','356','129'}
NOT_CRAFT = {'6','33','47','50','95','99','118'}   # auras, open lock, trade skill/skill ranks, campfire, disenchant
CREATE_ITEM, LEARN_SPELL = '24', '36'

skill = {r['ID']: r['DisplayName_lang'] for r in rows('SkillLine')}
spellName = {r['ID']: r['Name_lang'] for r in rows('SpellName')}
cats = {r['ID']: r for r in rows('TradeSkillCategory')}
area = {r['ID']: r['AreaName_lang'] for r in rows('AreaTable')}
# zone IDs QuestieDB uses that Forever's AreaTable doesn't have (its NPCs there
# say which: 1585 holds the Anvilrage, Doomforge and Lord Roccor)
ZONE_FIXES = {'1585': 'Blackrock Depths'}
itemName = {r['ID']: r['Display_lang'] for r in rows('ItemSparse')}

effects = collections.defaultdict(list)
learnedBy = collections.defaultdict(set)      # recipe spell -> spells that teach it
for r in rows('SpellEffect'):
    effects[r['SpellID']].append(r)
    if r['Effect'] == LEARN_SPELL and r['EffectTriggerSpell'] != '0':
        learnedBy[r['EffectTriggerSpell']].add(r['SpellID'])
effectItems = collections.defaultdict(set)
for r in rows('ItemXItemEffect'): effectItems[r['ItemEffectID']].add(r['ItemID'])
itemsBySpell = collections.defaultdict(set)   # spell an item casts on use -> items
itemsTeaching = collections.defaultdict(set)  # spell an item teaches (trigger 6, "on learn") -> items
for r in rows('ItemEffect'):
    for item in effectItems.get(r['ID'], ()):
        (itemsTeaching if r['TriggerType'] == '6' else itemsBySpell)[r['SpellID']].add(item)
reagents = {}
for r in rows('SpellReagents'):
    reagents[r['SpellID']] = [(r[f'Reagent_{i}'], int(r[f'ReagentCount_{i}'])) for i in range(8) if r[f'Reagent_{i}'] not in ('0', '')]

qitems = {r['id']: r for r in tsv('questie_items.tsv')}
qnpcs = {r['id']: r for r in tsv('questie_npcs.tsv')}
qobjs = {r['id']: r for r in tsv('questie_objects.tsv')}
def ids(s): return [x for x in (s or '').split(',') if x]
def zone(z):
    if not z or z == '0': return ''
    if not z.isdigit(): return z.replace('_', ' ').title()   # a correction's zone by name
    return area.get(z) or ZONE_FIXES.get(z) or f'zone {z}'
def npc(i):
    n = qnpcs.get(i)
    if not n: return {'id': int(i), 'name': None}
    d = {'id': int(i), 'name': n['name'], 'zone': zone(n['zoneID'])}
    if n['friendly']: d['faction'] = n['friendly']
    if n['minLevel']: d['level'] = n['minLevel'] if n['minLevel'] == n['maxLevel'] else f"{n['minLevel']}-{n['maxLevel']}"
    return d

def chain(c):
    out, g = [], 0
    while c in cats and g < 10:
        out.append(cats[c]); c = cats[c]['ParentTradeSkillCategoryID']; g += 1
    return out

trainers = collections.defaultdict(list)
for n in qnpcs.values():
    sub = n['subName'] or ''
    for sid in PROFESSIONS:
        nm = skill[sid]
        if sub.startswith(nm + ' Trainer') or sub in (f'Master {nm} Trainer', f'Expert {nm} Trainer', f'Journeyman {nm}', f'Artisan {nm}'):
            trainers[sid].append(npc(n['id']))

recipes = []
for r in rows('SkillLineAbility'):
    sid, spell = r['SkillLine'], r['Spell']
    if sid not in PROFESSIONS: continue
    effs = effects.get(spell, [])
    if not effs or all(e['Effect'] in NOT_CRAFT for e in effs): continue
    name = spellName.get(spell)
    ch = chain(r['TradeSkillCategoryID']) if r['TradeSkillCategoryID'] != '0' else []
    header = ch[-1]['Name_lang'] if ch else None
    if name is None: listed = 'hidden (no spell name in client)'
    elif header is None and not any(e['Effect'] == CREATE_ITEM for e in effs): listed = 'not a recipe (no category, makes nothing)'
    elif header is None: listed = 'no category'
    elif header == skill[sid]: listed = 'profession'
    else: listed = header
    product = next((e['EffectItemType'] for e in effs if e['Effect'] == CREATE_ITEM and e['EffectItemType'] != '0'), None)
    rec = {
        'profession': skill[sid], 'skillLine': int(sid), 'recipeID': int(spell), 'name': name,
        'header': header, 'category': ch[0]['Name_lang'] if ch else None, 'listed': listed,
        # Forever's camp objects: a "Camping" category under each profession's header
        'isCamping': any(c['Name_lang'] == 'Camping' for c in ch),
        'skill': {'learn': int(r['MinSkillLineRank']), 'yellow': int(r['TrivialSkillLineRankLow']), 'grey': int(r['TrivialSkillLineRankHigh'])},
        'product': {'itemID': int(product), 'name': itemName.get(product)} if product else None,
        'reagents': [{'itemID': int(i), 'name': itemName.get(i), 'count': c} for i, c in reagents.get(spell, [])],
    }
    # items that teach it: the item casts a spell whose LEARN_SPELL effect names the recipe (or the recipe itself)
    teach = set(itemsTeaching.get(spell, ()))
    for s in learnedBy.get(spell, ()): teach |= itemsBySpell.get(s, set())
    teach = {i for i in teach if i != product}
    sources = []
    if r['AcquireMethod'] in ('1', '2'):
        sources.append({'type': 'auto', 'note': 'learned with the profession' if r['AcquireMethod'] == '2' else 'learned automatically at skill ' + r['MinSkillLineRank']})
    for item in sorted(teach, key=lambda i: (i not in itemName, int(i))):
        q = qitems.get(item, {})
        src = {'type': 'item', 'itemID': int(item), 'name': itemName.get(item) or q.get('name'), 'inQuestie': bool(q), 'inClient': item in itemName}
        if ids(q.get('vendors')): src['vendors'] = [npc(i) for i in ids(q['vendors'])]
        if ids(q.get('npcDrops')): src['drops'] = [npc(i) for i in ids(q['npcDrops'])]
        if ids(q.get('objectDrops')): src['objects'] = [{'id': int(i), 'name': (qobjs.get(i) or {}).get('name'), 'zone': zone((qobjs.get(i) or {}).get('zoneID'))} for i in ids(q['objectDrops'])]
        if ids(q.get('itemDrops')): src['containers'] = [{'itemID': int(i), 'name': itemName.get(i)} for i in ids(q['itemDrops'])]
        if ids(q.get('questRewards')): src['questRewards'] = [int(i) for i in ids(q['questRewards'])]
        sources.append(src)
    if not sources: sources.append({'type': 'trainer'})
    rec['sources'] = sources
    recipes.append(rec)

recipes.sort(key=lambda x: (x['profession'], x['skill']['learn'], x['name'] or ''))
about = {
    'recipes': f"Forever client tables (DB2), build {SOURCES['build']}, from wago.tools",
    'sources': f"QuestieDB Forever data, commit {SOURCES['questiedb']} (github.com/Questie/QuestieDB, no license stated)",
    'fetched': SOURCES['fetched'],
}
json.dump({'about': about, 'recipes': recipes, 'trainers': {skill[k]: v for k, v in trainers.items()}},
          open(os.path.join(OUT, 'forever_recipes.json'), 'w'), separators=(',', ':'))

# flat CSV for a spreadsheet
def summary(srcs):
    parts = []
    known = [s for s in srcs if s.get('inClient', True)]
    for s in known or srcs:
        if s['type'] == 'trainer': parts.append('Trainer')
        elif s['type'] == 'auto': parts.append('Auto (' + s['note'] + ')')
        else:
            bits = []
            if s.get('vendors'): bits.append('Vendor: ' + '; '.join(f"{v['name']} ({v.get('zone','')}{', ' + v['faction'] if v.get('faction') else ''})" for v in s['vendors'][:6]) + (f" +{len(s['vendors'])-6}" if len(s['vendors']) > 6 else ''))
            if s.get('drops'): bits.append(f"Drop: {len(s['drops'])} NPCs, e.g. " + '; '.join(f"{v['name']} ({v.get('zone','')})" for v in s['drops'][:3]))
            if s.get('objects'): bits.append('Object: ' + '; '.join(f"{o['name']} ({o['zone']})" for o in s['objects'][:3]))
            if s.get('containers'): bits.append('Container: ' + '; '.join(str(c['name']) for c in s['containers'][:3]))
            if s.get('questRewards'): bits.append('Quest reward: ' + ', '.join(map(str, s['questRewards'][:5])))
            if not bits: bits.append('no source in Questie' if s['inQuestie'] else 'item not in Questie')
            parts.append(f"{s['name']} [{s['itemID']}]: " + ' | '.join(bits))
    return ' || '.join(parts)
with open(os.path.join(OUT, 'forever_recipes.tsv'), 'w', newline='', encoding='utf-8') as f:
    f.write(f"# Forever's profession recipes, {about['fetched']}: {about['recipes']}; where they are learned: {about['sources']}\n")
    w = csv.writer(f, delimiter='\t', lineterminator='\n')
    w.writerow(['profession', 'recipeID', 'name', 'listed', 'category', 'isCamping', 'learn', 'yellow', 'grey', 'productID', 'product', 'reagents', 'source'])
    for x in recipes:
        w.writerow([x['profession'], x['recipeID'], x['name'], x['listed'], x['category'], 'yes' if x['isCamping'] else '', x['skill']['learn'], x['skill']['yellow'], x['skill']['grey'],
                    x['product'] and x['product']['itemID'], x['product'] and x['product']['name'],
                    ', '.join(f"{g['count']}x {g['name']}" for g in x['reagents']), summary(x['sources'])])
c = collections.Counter((x['profession'], x['listed']) for x in recipes)
for k in sorted(c): print(k, c[k])
st = collections.Counter()
for x in recipes:
    if x['listed'] != 'profession': continue
    for s in x['sources']:
        if s['type'] != 'item': st[s['type']] += 1
        else:
            st['item'] += 1
            for k in ('vendors', 'drops', 'objects', 'containers', 'questRewards'):
                if s.get(k): st['item:' + k] += 1
            if not any(s.get(k) for k in ('vendors', 'drops', 'objects', 'containers', 'questRewards')): st['item:NO SOURCE' + ('' if s['inQuestie'] else ' (not in Questie)')] += 1
print(dict(st))
