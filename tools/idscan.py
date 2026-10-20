#!/usr/bin/env python3
# tools/idscan.py: before every commit, checks the STAGED diff's added lines
# for real character names, GUIDs and player links taken from the local
# recordings (WoW's SavedVariables: StdTest.lua, SuuUI.lua) and from
# ~/.config/suuui/idscan-names.txt. Prints COUNTS only, never a name:
#   python3 -I tools/idscan.py .            -> every line must end in ": 0"
#   python3 -I tools/idscan.py . --where    -> file:line of each name hit
# The repository is public: no real name or GUID may be committed.
import glob, os, re, subprocess, sys
names = set()
for f in glob.glob('/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/StdTest.lua'):
    s = open(f, encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'UnitName\(\\"(?:player|target|party\d|targettarget|npc)\\"\) -> 2: string ([^,"\\]+), string ([^,"\\]+)', s):
        names.add(m.group(1))
    for m in re.finditer(r'"string ([^"]+?) creates ', s):
        names.add(m.group(1))
    # Any UnitName answer (both values: the name, the last name or realm),
    # in either form (`-> 2:` or the group probe's `"] = "2:`).
    for m in re.finditer(r'UnitName\(\\"[a-z0-9]+\\"\)(?: -> |"\] = ")2: string ([^,"\\]+), string ([^,"\\]+)', s):
        names.add(m.group(1)); names.add(m.group(2))
    for m in re.finditer(r'GetRaidRosterInfo\(\d+\)"\] = "12: string ([^,"\\]+),', s):
        names.add(m.group(1))
    for m in re.finditer(r'GetInboxInvoiceInfo\(\d+\) -> \d+: string [a-z]+, string [^,]*, string ([^,"\\]+),', s):
        names.add(m.group(1))
    for m in re.finditer(r'GetInboxHeaderInfo\(\d+\) -> \d+: [^,]+, [^,]+, string ([^,"\\]+), (?:[^,]+, ){8}boolean true,', s):
        names.add(m.group(1))
    for o in re.finditer(r'owners=\{([^}]*)\}', s):
        for m in re.finditer(r'\d+=string ([^,}]+)', o.group(1)):
            if m.group(1) != 'player': names.add(m.group(1))
    for m in re.finditer(r'GetGuildInfo\([^)]*\) -> \d+: string ([^,"\\]+)', s):
        names.add(m.group(1))
# Extra names that never appear in the recordings (seen elsewhere): one per
# line in a local file outside the repository, never committed.
EXTRA = os.path.expanduser("~/.config/suuui/idscan-names.txt")
if os.path.exists(EXTRA):
    names |= {l.strip() for l in open(EXTRA, encoding="utf-8") if l.strip()}
names = {n.strip() for n in names if len(n.strip()) > 3}
names -= {"Player", "Otherplayer", "Someone", "Realm", "Lastname"}
# The probes' own placeholders, alone or combined ("Player Lastname",
# "Member1 Member1Last", "Member1-Realm").
placeholder = r"(Player|Lastname|Realm|Member\d+(Last)?)"
names = {n for n in names if not re.fullmatch(placeholder + r"([ -]" + placeholder + r")*", n)}
diff = subprocess.run(['git', 'diff', '--cached'], capture_output=True, text=True, cwd=sys.argv[1]).stdout
diff = '\n'.join(l for l in diff.splitlines() if l.startswith('+'))
hits = sum(1 for n in names if re.search(r'\b' + re.escape(n) + r'\b', diff))
crafters = set()
for f in glob.glob('/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/StdTest.lua'):
    for m in re.finditer(r'"string ([^"]+?) creates ', open(f, encoding='utf-8', errors='replace').read()):
        crafters.add(m.group(1).strip())
print("crafters in added lines:", sum(1 for n in crafters if re.search(r'\b' + re.escape(n) + r'\b', diff)))
print(f"names checked: {len(names)}, found in staged diff: {hits}")
# Friends coming online / going offline, and the scrub's fragments: the
# player's placeholder glued to the rest of another's name ("Player" + "tina").
friends = set()
for f in glob.glob('/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/StdTest.lua'):
    for m in re.finditer(r'string (?:\|Hplayer:[^|]*\|h\[)?([^\[\]|;"\\]+?)(?:\]\|h)? has (?:gone offline|come online)', open(f, encoding='utf-8', errors='replace').read()):
        friends.add(m.group(1).strip().split(' ')[0])
print("friends in added lines:", sum(1 for n in friends if len(n) > 3 and re.search(r'\b' + re.escape(n) + r'\b', diff)))
print("name fragments in added lines:", len(re.findall(r'\b(?:Player|Lastname)[a-z]{2,}\b', diff)))
# The characters SuuUI's probes name (its saved variables' `character`).
suu = set()
for f in glob.glob('/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/SuuUI.lua'):
    for m in re.finditer(r'\["character"\] = "([^"]+)"', open(f, encoding='utf-8', errors='replace').read()):
        suu.add(m.group(1))
print(f"SuuUI characters checked: {len(suu)}, in added lines:", sum(1 for n in suu if len(n) > 3 and re.search(r'\b' + re.escape(n) + r'\b', diff)))
# Any player link or invite/whisper payload naming someone not a placeholder
# (2026-10-19: an inviter's name leaked through a group finder recording).
PLACEHOLDERS = {'Player', 'Otherplayer', 'Lastname', 'Tester', 'Tamsin', 'Ashford', 'Partyone', 'Partytwo'}
linked = re.findall(r'\|Hplayer:([^|:\]]+)', diff) + re.findall(r'PARTY_INVITE_REQUEST\(string ([^;)]+)', diff)
unknown = sorted({n for n in linked if not set(re.split(r'[\s-]+', n)) <= PLACEHOLDERS})
print("player links/invites not placeholders in added lines:", len(unknown))
# Possessives naming someone in log lines ("<name>'s pet ..."), 2026-10-20.
poss = sorted({m for m in re.findall(r"string ([A-Z][a-z]+)'s (?:pet|minion|guardian) ", diff) if m not in PLACEHOLDERS | {'Someone'}})
print("possessive owners not placeholders in added lines:", len(poss))

if "--where" in sys.argv:
    file = None; line = 0
    for l in subprocess.run(['git', 'diff', '--cached', '-U0'], capture_output=True, text=True, cwd=sys.argv[1]).stdout.splitlines():
        if l.startswith('+++ '): file = l[6:]; continue
        m = re.match(r'@@ -\S+ \+(\d+)', l)
        if m: line = int(m.group(1)); continue
        if l.startswith('+'):
            if any(re.search(r'\b' + re.escape(n) + r'\b', l) for n in names | suu):
                print(f"{file}:{line}")
            line += 1
