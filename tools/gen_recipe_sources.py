# tools/gen_recipe_sources.py
# Where each of Forever's profession recipes is learned, for the addon:
# tools/data/forever_recipes.json (tools/gen_recipes.py) into
# src/Data/RecipeSources.lua.
#   ns.RecipeSources[recipeID] = { source, ... }
#     { t = "t", s = skill,                    a profession trainer, the skill
#       n = { "Name|Zone|Faction" } }          it asks for and the trainers
#                                              that teach it (recorded in game)
#     { t = "a" }                              learned automatically
#     { t = "i", i = itemID, s = skill,        a recipe item (the skill it
#                                              needs), and where it is:
#       v = { "Name|Zone|A" },                 sold by (faction A, H or none)
#       d = { "Name|Zone|Level" }, dn = n,     dropped by (the first few, of n)
#       o = { "Name|Zone" },                   found in (chests, objects)
#       q = { questID },                       a quest's reward
#       c = { itemID } }                       inside (packages, lockboxes)
#   An item with none of these: where it is isn't known yet.
#   The skill a recipe needs: on its recipe item (ItemSparse.RequiredSkillRank,
#   the client tables), and for trainer recipes from the trainers SuuUI
#   recorded in game (tools/data/trainer_records.tsv,
#   tools/merge_trainer_records.lua): the game keeps those on the server.
#   Recipes no trainer is recorded for yet take Classic's value from
#   cMaNGOS (tools/data/cmangos_trainers.tsv, GPL-3.0); Forever's own new
#   recipes have none until recorded.
#   python3 -I tools/gen_recipe_sources.py tools/data/forever_recipes.json src/Data/RecipeSources.lua \
#       [--itemsparse <wago>/ItemSparse.csv] [--trainers tools/data/trainer_records.tsv]
#       [--cmangos tools/data/cmangos_trainers.tsv]
import csv, json, os, sys

SRC, OUT = sys.argv[1:3]
OPTS = dict(zip(sys.argv[3::2], sys.argv[4::2]))

# the skill a recipe item asks for
itemSkill = {}
if OPTS.get('--itemsparse'):
    for r in csv.DictReader(open(OPTS['--itemsparse'], encoding='utf-8')):
        rank = int(r.get('RequiredSkillRank') or 0)
        if rank > 0:
            itemSkill[int(r['ID'])] = rank

# what the trainers SuuUI recorded teach: (profession, recipe name) -> skill, trainers
taught = {}
path = OPTS.get('--trainers')
if path and os.path.exists(path):
    lines = [l for l in open(path, encoding='utf-8') if not l.startswith('#')]
    for r in csv.DictReader(lines, delimiter='\t', quoting=csv.QUOTE_NONE):
        key = (r['profession'], r['recipe'].lower())
        t = taught.setdefault(key, {'skill': None, 'trainers': []})
        if r['skill']:
            t['skill'] = min(int(r['skill']), t['skill'] or 10**6)
        faction = {'Alliance': 'A', 'Horde': 'H'}.get(r['faction'], '')
        place = '|'.join([r['npc'], r['zone'], faction])
        if place not in t['trainers']:
            t['trainers'].append(place)
MAX_DROPS, MAX_VENDORS, MAX_OBJECTS = 4, 6, 3

def lua(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

# zones the recipe data couldn't name ("zone 1585": an ID QuestieDB uses that
# Forever's AreaTable lacks; tools/gen_recipes.py knows them too)
ZONE_FIXES = {'zone 1585': 'Blackrock Depths'}

# places QuestieDB gives no zone, where there is only one (dungeon bosses,
# creatures of one zone). Chests that spawn in many zones (Tattered Chest,
# Large Solid Chest) and wanderers stay without one.
NAME_ZONES = {
    'Sneed': 'The Deadmines',
    'Lady Anacondra': 'Wailing Caverns',
    'Mutanus the Devourer': 'Wailing Caverns',
    'Darkmaster Gandling': 'Scholomance',
    'Balnazzar': 'Stratholme',
    'Gyth': 'Blackrock Spire',
    'Solakar Flamewreath': 'Blackrock Spire',
    'Overmaster Pyron': 'Blackrock Depths',
    'Grizzle': 'Blackrock Depths',
    'Gordok Bushwacker': 'Dire Maul',
    'Stitches': 'Duskwood',
    'Eliza': 'Duskwood',
    'Wastewander Scofflaw': 'Tanaris',
    'Moonrage Tailor': 'Silverpine Forest',
    'Arena Treasure Chest': 'Stranglethorn Vale',
}

def zone(z, name=None):
    z = ZONE_FIXES.get(z or '', z or '')
    return z or NAME_ZONES.get(name or '', '')

def npc(n, third):
    return lua('|'.join([n.get('name') or '', zone(n.get('zone'), n.get('name')), str(n.get(third) or '')]))

def named(entries):
    # a place without a name says nothing ("Dropped by" and no one)
    return [e for e in entries or [] if e.get('name')]

# Classic's trainer skill by recipe ID (cMaNGOS), for recipes not recorded
classic = {}
path = OPTS.get('--cmangos')
if path and os.path.exists(path):
    lines = [l for l in open(path, encoding='utf-8') if not l.startswith('#')]
    for r in csv.DictReader(lines, delimiter='\t', quoting=csv.QUOTE_NONE):
        if r['skill']:
            classic[int(r['recipeID'])] = int(r['skill'])

def trainer(t, recipeID=None):
    parts = ['t = "t"']
    skill = (t and t['skill']) or classic.get(recipeID)
    if skill:
        parts.append('s = %d' % skill)
    if t and t['trainers']:
        parts.append('n = { %s }' % ', '.join(lua(p) for p in t['trainers']))
    return '{ ' + ', '.join(parts) + ' }'

def source(s, recipe):
    t = s['type']
    if t == 'trainer':
        return trainer(taught.get((recipe['profession'], (recipe['name'] or '').lower())), recipe['recipeID'])
    if t == 'auto':
        return '{ t = "a" }'
    parts = ['t = "i"', 'i = %d' % s['itemID']]
    if itemSkill.get(s['itemID']):
        parts.append('s = %d' % itemSkill[s['itemID']])
    vendors = named(s.get('vendors'))
    if vendors:
        parts.append('v = { %s }' % ', '.join(npc(v, 'faction') for v in vendors[:MAX_VENDORS]))
    drops = named(s.get('drops'))
    if drops:
        parts.append('d = { %s }' % ', '.join(npc(d, 'level') for d in drops[:MAX_DROPS]))
        parts.append('dn = %d' % len(drops))
    seen, objects = set(), []
    for o in named(s.get('objects')):
        key = (o.get('name'), zone(o.get('zone'), o.get('name')))
        if key not in seen:
            seen.add(key)
            objects.append(lua('|'.join(key)))
    if objects:
        parts.append('o = { %s }' % ', '.join(objects[:MAX_OBJECTS]))
    quests = s.get('questRewards') or []
    if quests:
        parts.append('q = { %s }' % ', '.join(str(int(q)) for q in quests))
    containers = s.get('containers') or []
    if containers:
        parts.append('c = { %s }' % ', '.join(str(int(c['itemID'])) for c in containers))
    return '{ ' + ', '.join(parts) + ' }'

data = json.load(open(SRC, encoding='utf-8'))
about = data.get('about', {})
lines = [
    '-- Data/RecipeSources.lua (generated by tools/gen_recipe_sources.py: do not edit)',
    '-- Where each of Forever\'s profession recipes is learned.',
    '--   recipes: %s' % about.get('recipes', ''),
    '--   sources: %s' % about.get('sources', ''),
    '--   fetched %s' % about.get('fetched', ''),
    '--   skill needed: recipe items (client tables); trainers recorded in game by SuuUI, else',
    '--   Classic\'s from cMaNGOS classic-db (GPL-3.0, tools/data/cmangos_trainers.tsv)',
    '',
    'local _, ns = ...',
    '',
    'ns.RecipeSources = {',
]
for r in sorted(data['recipes'], key=lambda r: r['recipeID']):
    srcs = [source(s, r) for s in r.get('sources') or []]
    # a trainer recorded teaching it, which the data didn't know of
    t = taught.get((r['profession'], (r['name'] or '').lower()))
    if t and not any(s['type'] == 'trainer' for s in r.get('sources') or []):
        srcs.append(trainer(t, r['recipeID']))
    if srcs:
        lines.append('    [%d] = { %s }, -- %s' % (r['recipeID'], ', '.join(srcs), r['name']))
lines.append('}')
open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('%d recipes into %s' % (len(lines) - 10, OUT))
