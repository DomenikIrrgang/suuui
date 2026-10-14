# tools/match_recipes.py
# Matches the game's recipe lists (tools/extract_recipe_probe.lua) against
# tools/data/forever_recipes.json, recipe by recipe: only in the game, only in
# the client's tables, names, grey levels, recipes without a category.
#   python3 -I tools/match_recipes.py <probe.tsv> tools/data/forever_recipes.json
import json, sys, os, collections
PROBE, DATA = sys.argv[1:3]
rec = json.load(open(DATA))['recipes']
byID = {r['recipeID']: r for r in rec}
probed, game = {}, collections.defaultdict(dict)
for l in open(PROBE):
    f = l.rstrip('\n').split('\t')
    if f[0] == 'probed': probed[f[1]] = f[2:]
    elif f[0] == 'recipe' and len(f) >= 8:   # grey is last (older probes also had a yellow before it)
        game[f[1]][int(f[2])] = {'name': f[3], 'cat': f[4], 'learned': f[5] == '1', 'grey': int(f[-1])}
for sl, (name, n, at) in sorted(probed.items()):
    g = game[sl]; db = {r['recipeID']: r for r in rec if r['skillLine'] == int(sl) and not r['listed'].startswith('not a recipe')}
    print(f'\n## {name} ({sl}): game {len(g)}, game data {len(db)}  [{at}]')
    onlyGame = [i for i in g if i not in db]; onlyDB = [i for i in db if i not in g]
    for i in onlyGame: print(f'  only in game: {i} {g[i]["name"]}')
    for i in onlyDB: print(f'  only in game data: {i} {db[i]["name"]} ({db[i]["listed"]})')
    names = sum(1 for i in g if i in db and g[i]['name'] != db[i]['name'])
    # GetRecipeInfo on Forever has maxTrivialLevel (grey) but no minTrivialLevel: the probe saves yellow as 0
    levels = [(i, g[i], db[i]['skill']) for i in g if i in db and g[i]['grey'] != db[i]['skill']['grey']]
    print(f'  name differences: {names}; grey level differences: {len(levels)}')
    for i, a, b in levels[:10]: print(f'    {i} {a["name"]}: game {a["yellow"]}/{a["grey"]}, game data {b["yellow"]}/{b["grey"]}')
    nocat = [i for i in g if g[i]['cat'] == '0']
    if nocat: print('  listed without category: ' + ', '.join(f'{i} {g[i]["name"]}' for i in nocat))
