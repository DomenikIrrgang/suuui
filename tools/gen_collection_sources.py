# tools/gen_collection_sources.py
# Where Forever's mounts, toys and appearances come from, for SuuUI's own
# collections window (asked 2026-10-16: show what you lack and where to get
# it; the game gives no source for mounts, only the kind for appearances, and
# won't list the toys you lack). Into src/Data/CollectionSources.lua:
#   ns.CollectionSources = {
#     npc   = { [npcID] = "Name|Zone|Level|Faction" },   every NPC named below, once
#     obj   = { [objectID] = "Name|Zone" },
#     mount = { [mountID] = source },     the item that teaches or summons it
#     toy   = { [itemID] = source },      every toy of Forever, sources or not
#     toys  = { itemID, ... },            Forever's toys, in the client's order
#     item  = { [itemID] = source },      items with an appearance and a source
#   }
#   source = { i = itemID (mounts), x = "text" (the client's own source text),
#              v = { npcID } (sold by), d = { npcID } (dropped by, the first
#              few), dn = n (of how many), o = { objectID } (found in),
#              q = { questID } (a quest's reward), c = { itemID } (inside),
#              p = "Profession" (crafted: tools/data/forever_recipes.json) }
#   An entry whose drops come from more than WORLD NPCs is a world drop:
#   dn says how many, d keeps the first few.
# Sources: Forever's client tables (DB2) from wago.tools, and QuestieDB's
# Forever data (github.com/Questie/QuestieDB, no license stated), as for the
# recipe sources:
#   sh tools/fetch_recipe_sources.sh <dir>
#   lua tools/extract_questie.lua <dir>/questiedb <dir>
#   python3 -I tools/gen_collection_sources.py <dir> src/Data/CollectionSources.lua [tools/data/forever_recipes.json]
import csv, os, sys, collections, re

import json
DIR, OUT = sys.argv[1:3]
RECIPES = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'forever_recipes.json')
W = os.path.join(DIR, 'wago')
SOURCES = dict(l.rstrip('\n').split('\t', 1) for l in open(os.path.join(DIR, 'SOURCES')))
def rows(t): return csv.DictReader(open(os.path.join(W, t + '.csv'), encoding='utf-8'))
def tsv(name): return csv.DictReader(open(os.path.join(DIR, name), encoding='utf-8'), delimiter='\t', quoting=csv.QUOTE_NONE)
def ids(s): return [x for x in (s or '').split(',') if x]

MAX_DROPS, MAX_VENDORS, MAX_OBJECTS, MAX_CONTAINERS, MAX_QUESTS = 3, 3, 2, 2, 3
WORLD = 12

area = {r['ID']: r['AreaName_lang'] for r in rows('AreaTable')}
ZONE_FIXES = {'1585': 'Blackrock Depths'}
def zone(z):
    if not z or z == '0': return ''
    if not z.isdigit(): return z.replace('_', ' ').title()
    return area.get(z) or ZONE_FIXES.get(z) or ''

qitems = {r['id']: r for r in tsv('questie_items.tsv')}
qnpcs = {r['id']: r for r in tsv('questie_npcs.tsv')}
qobjs = {r['id']: r for r in tsv('questie_objects.tsv')}

# the items that teach or cast a spell (a mount's summon spell)
effectItems = collections.defaultdict(set)
for r in rows('ItemXItemEffect'): effectItems[r['ItemEffectID']].add(r['ItemID'])
itemsBySpell = collections.defaultdict(set)
for r in rows('ItemEffect'):
    for item in effectItems.get(r['ID'], ()):
        itemsBySpell[r['SpellID']].add(item)

# what the professions make (listed recipes only)
crafted = {}
if os.path.exists(RECIPES):
    for r in json.load(open(RECIPES, encoding='utf-8'))['recipes']:
        if r.get('product') and r.get('listed') not in ('hidden (no spell name in client)', 'not a recipe (no category, makes nothing)'):
            crafted.setdefault(str(r['product']['itemID']), r['profession'])

npcsUsed, objsUsed = {}, {}
def npcRef(i):
    n = qnpcs.get(i)
    if not n or not n['name']: return None
    if i not in npcsUsed:
        lvl = n['minLevel'] if n['minLevel'] == n['maxLevel'] else f"{n['minLevel']}-{n['maxLevel']}"
        npcsUsed[i] = '|'.join([n['name'], zone(n['zoneID']), lvl if n['minLevel'] else '', n['friendly'] or ''])
    return int(i)
def objRef(i):
    o = qobjs.get(i)
    if not o or not o['name']: return None
    if i not in objsUsed: objsUsed[i] = '|'.join([o['name'], zone(o['zoneID'])])
    return int(i)

def clean(text):
    # the client's source text: colour codes away, |n as " · "
    t = re.sub(r'\|c[0-9A-Fa-f]{8}|\|r', '', text or '')
    return t.replace('|n', ' · ').strip()

def source(item, text=None, withItem=False):
    q = qitems.get(item, {})
    s = {}
    if withItem: s['i'] = int(item)
    if text: s['x'] = clean(text)
    v = [r for r in (npcRef(i) for i in ids(q.get('vendors'))) if r]
    if v: s['v'] = v[:MAX_VENDORS]
    d = [r for r in (npcRef(i) for i in ids(q.get('npcDrops'))) if r]
    if d:
        s['d'] = d[:MAX_DROPS]
        if len(d) > MAX_DROPS: s['dn'] = len(d)
    o = [r for r in (objRef(i) for i in ids(q.get('objectDrops'))) if r]
    if o: s['o'] = o[:MAX_OBJECTS]
    qs = [int(i) for i in ids(q.get('questRewards'))]
    if qs: s['q'] = qs[:MAX_QUESTS]
    c = [int(i) for i in ids(q.get('itemDrops'))]
    if c: s['c'] = c[:MAX_CONTAINERS]
    if crafted.get(item): s['p'] = crafted[item]
    return s

def lua(v):
    if isinstance(v, str): return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, list): return '{ ' + ', '.join(lua(x) for x in v) + ' }'
    if isinstance(v, dict): return '{ ' + ', '.join(f'{k} = {lua(x)}' for k, x in v.items()) + ' }'
    return str(v)

# mounts: the item that casts or teaches the mount's spell
mounts, mountStats = {}, collections.Counter()
for r in rows('Mount'):
    items = sorted(itemsBySpell.get(r['SourceSpellID'], ()), key=int)
    best = None
    for item in items:
        s = source(item, withItem=True)
        if len(s) > 1: best = s; break
        best = best or s
    if r['SourceText_lang']:
        best = best or {}
        best['x'] = clean(r['SourceText_lang'])
    if best and len(best) > (1 if 'i' in best else 0):
        mounts[int(r['ID'])] = best
        mountStats['with source'] += 1
    elif best:
        mounts[int(r['ID'])] = best
        mountStats['item only'] += 1
    else:
        mountStats['nothing'] += 1

# toys: every one, in the client's order
toys, toyList = {}, []
for r in rows('Toy'):
    toyList.append(int(r['ItemID']))
    toys[int(r['ItemID'])] = source(r['ItemID'], r['SourceText_lang'])

# appearances: items with an appearance that have a source
appearanceItems = {r['ItemID'] for r in rows('ItemModifiedAppearance')}
items, itemStats = {}, collections.Counter()
for item in sorted(appearanceItems, key=int):
    s = source(item)
    if s:
        items[int(item)] = s
        itemStats['with source'] += 1
        if s.get('dn', 0) > WORLD: itemStats['world drop'] += 1
    else:
        itemStats['none'] += 1

with open(OUT, 'w', encoding='utf-8') as f:
    f.write('-- Data/CollectionSources.lua (generated by tools/gen_collection_sources.py: do not edit)\n')
    f.write("-- Where Forever's mounts, toys and appearances come from, for the collections window.\n")
    f.write(f"--   mounts, toys, appearance items: Forever client tables (DB2), build {SOURCES['build']}, from wago.tools\n")
    f.write(f"--   sources: QuestieDB Forever data, commit {SOURCES['questiedb']} (github.com/Questie/QuestieDB, no license stated)\n")
    f.write(f"--   fetched {SOURCES['fetched']}\n\n")
    f.write('local _, ns = ...\n\n')
    f.write('ns.CollectionSources = {\n')
    f.write('    npc = {\n')
    for k in sorted(npcsUsed, key=int): f.write(f'        [{k}] = {lua(npcsUsed[k])},\n')
    f.write('    },\n    obj = {\n')
    for k in sorted(objsUsed, key=int): f.write(f'        [{k}] = {lua(objsUsed[k])},\n')
    f.write('    },\n    mount = {\n')
    for k in sorted(mounts): f.write(f'        [{k}] = {lua(mounts[k])},\n')
    f.write('    },\n    toy = {\n')
    for k in toyList: f.write(f'        [{k}] = {lua(toys[k])},\n')
    f.write('    },\n    toys = ' + lua(toyList) + ',\n    item = {\n')
    for k in sorted(items): f.write(f'        [{k}] = {lua(items[k])},\n')
    f.write('    },\n}\n')

print('mounts', dict(mountStats))
print('toys', len(toyList), 'with a source', sum(1 for t in toys.values() if t))
print('appearance items', len(appearanceItems), dict(itemStats))
print('npcs', len(npcsUsed), 'objects', len(objsUsed), 'bytes', os.path.getsize(OUT))
