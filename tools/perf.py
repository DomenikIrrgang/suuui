#!/usr/bin/env python3
# tools/perf.py: SuuUI's performance scenarios (tests/perf/README.md).
#
#   python3 -I tools/perf.py run [filter ...]   run the scenarios (all, or the
#                                               files matching a filter), then
#                                               summarize and compare
#   python3 -I tools/perf.py summarize          summarize the last run's profiles
#   python3 -I tools/perf.py compare [A] [B]    compare results A (default: the
#                                               last run) with B (default: the
#                                               baseline)
#   python3 -I tools/perf.py baseline           make the last run the baseline
#   python3 -I tools/perf.py top <scenario> [phase] [--frame N] [--event NAME]
#                                               where a phase's (or one frame's)
#                                               work goes: SuuUI's entry points
#                                               and functions, by instructions
#                                               and by garbage
#
# A run is `wowlua test --features perf -u --profile-out dist/perf/profiles
# tests/perf/...`: each scenario file's tests run in one emulated client, its
# profile (speedscope JSON with wowlua's per-frame trees) lands in
# dist/perf/profiles. The summary (dist/perf/results.json) has, per scenario
# and measured phase (a test whose name does not start with "setup"):
#   frames                 frames the phase ran
#   suu_instr_*            Lua instructions run by SuuUI (its code and the
#                          game's functions it called) per frame: mean, p95,
#                          max, total. The same on every machine and run.
#   suu_kb_*               KB SuuUI allocated per frame (what becomes garbage
#                          unless kept): mean, p95, max, total
#   all_instr_mean         every addon's and Blizzard's UI per frame (the
#                          test's own driving left out)
#   suu_ms_mean, suu_ms_max  the emulator's host time: machine-dependent and
#                          noisy, shown but never compared
#   worst_frame            the frame with SuuUI's most instructions, with its
#                          top entry points
# and the memory each scenario recorded (tests/perf/__snapshots__).
import json, os, re, subprocess, sys, collections, datetime, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dist', 'perf')
PROFILES = os.path.join(OUT, 'profiles')
RESULTS = os.path.join(OUT, 'results.json')
BASELINE = os.path.join(ROOT, 'tests', 'perf', 'baseline.json')
SNAPSHOTS = os.path.join(ROOT, 'tests', 'perf', '__snapshots__')
WOWLUA = os.environ.get('WOWLUA', 'wowlua')

# Compared metrics: (key, label, lower is better)
COMPARED = [
    ('suu_instr_mean', 'instr/frame mean'),
    ('suu_instr_p95', 'instr/frame p95'),
    ('suu_instr_max', 'instr worst frame'),
    ('suu_kb_mean', 'KB/frame mean'),
    ('suu_kb_p95', 'KB/frame p95'),
    ('suu_kb_max', 'KB worst frame'),
    ('all_instr_mean', 'all UI instr/frame'),
]

HARNESS = ('/std/mock.lua', '/std/test.lua', 'tests/')


def load_profile(path):
    with open(path, 'rb') as f:
        data = f.read()
    a = data.find(b'"shared":{"frames":')
    b = data.find(b'},"profiles":[', a)
    shared = json.loads(data[a + len(b'"shared":{"frames":'):b])
    i = data.rfind(b'"wowlua":{')
    w = json.loads(data[i + len(b'"wowlua":'):-1])
    return shared, w


class Profile:
    def __init__(self, path):
        self.shared, w = load_profile(path)
        self.kinds = w['kinds']
        nodes = w['nodes']
        self.parent = [n[1] for n in nodes]
        self.fidx = [n[0] for n in nodes]
        self.frames = w['frames']
        self._chain = {}
        self._suu = {}

    def name(self, nid):
        return self.shared[self.fidx[nid]]['name']

    def file(self, nid):
        return self.shared[self.fidx[nid]].get('file') or ''

    def label(self, nid):
        s = self.shared[self.fidx[nid]]
        f = s.get('file') or ''
        if '/src/' in f or f.startswith('src/'):
            f = f.split('src/', 1)[1]
        elif '/wowlua/' in f:
            f = 'wowlua/' + f.split('/wowlua/', 1)[1]
        if f:
            return '%s:%s' % (f, s.get('line', ''))
        return s['name']

    def chain(self, nid):
        c = self._chain.get(nid)
        if c is None:
            out = []
            x = nid
            while x != 0 and len(out) < 400:
                out.append(x)
                x = self.parent[x]
            out.reverse()
            c = out
            self._chain[nid] = c
        return c

    def dispatch(self, ch):
        """the innermost event and script (OnEvent, OnUpdate, timer) on a path"""
        ev = sc = None
        for x in ch:
            k = self.kinds[self.fidx[x]]
            if k == 'event':
                ev = self.name(x)
            elif k in ('script', 'update', 'timer'):
                sc = self.name(x)
        if ev and sc and sc.endswith(':OnEvent'):
            return ev
        return sc or ev or '-'

    def is_harness(self, nid):
        f = self.file(nid)
        return any(h in f for h in HARNESS)

    def is_suu(self, nid):
        r = self._suu.get(nid)
        if r is None:
            f = self.file(nid)
            r = bool(f) and not any(h in f for h in HARNESS) and (
                'src/' in f or '/SuuUI/' in f or 'foreverlfg' in f or f.endswith('.wowlua')) and 'Blizzard' not in f
            self._suu[nid] = r
        return r


def test_names(source):
    """line of each test function -> its name (the profile names a decorated
    function by its first decorator's line; the function's own line too)"""
    out = {}
    pending = None
    first = None
    with open(source, encoding='utf-8') as f:
        for no, line in enumerate(f, 1):
            if re.match(r'\s*@', line) and first is None:
                first = no
            m = re.match(r'\s*@test\("([^"]*)"', line)
            if m:
                pending = m.group(1)
                continue
            if re.match(r'\s*local function ', line):
                if pending:
                    out[no] = pending
                    if first is not None:
                        out[first] = pending
                pending = None
                first = None
            elif not re.match(r'\s*@', line):
                first = None
    return out


def pct(vals, p):
    if not vals:
        return 0
    s = sorted(vals)
    return s[min(len(s) - 1, int(len(s) * p))]


def summarize_file(path):
    base = os.path.basename(path)
    m = re.match(r'tests_perf_(.+)\.test\.wowlua\.(\w+)\.speedscope\.json$', base)
    if not m:
        return None
    scenario, flavor = m.group(1), m.group(2)
    source = os.path.join(ROOT, 'tests', 'perf', scenario + '.test.wowlua')
    names = test_names(source)
    prof = Profile(path)
    test_prefix = 'tests/perf/%s.test.wowlua:' % scenario
    phases = collections.OrderedDict()
    for fr in prof.frames:
        num = int(fr['name'].split()[-1])
        phase = None
        si = sb = sn = ai = 0
        entries = collections.Counter()
        for nid, calls, cost in fr['nodes']:
            ch = prof.chain(nid)
            if phase is None:
                for x in ch:
                    f = prof.file(x)
                    if f.endswith(test_prefix[:-1]) or test_prefix[:-1] in f:
                        line = prof.shared[prof.fidx[x]].get('line')
                        if line in names:
                            phase = names[line]
                            break
            if not prof.is_harness(nid):
                ai += cost[0]
            outer = None
            for x in ch:
                if prof.is_suu(x):
                    outer = x
                    break
            if outer is not None:
                si += cost[0]
                sb += cost[1]
                sn += cost[2]
                entries[prof.dispatch(ch) + ' > ' + prof.label(outer)] += cost[0]
        if phase is None or phase.startswith('setup'):
            continue
        phases.setdefault(phase, []).append((num, si, sb, sn, ai, entries))
    out = {'scenario': scenario, 'flavor': flavor, 'phases': collections.OrderedDict()}
    for phase, rows in phases.items():
        ins = [r[1] for r in rows]
        kb = [r[2] / 1024 for r in rows]
        ms = [r[3] / 1e6 for r in rows]
        worst = max(rows, key=lambda r: r[1])
        out['phases'][phase] = {
            'frames': len(rows),
            'suu_instr_total': sum(ins),
            'suu_instr_mean': round(sum(ins) / len(ins)),
            'suu_instr_p95': pct(ins, 0.95),
            'suu_instr_max': max(ins),
            'suu_kb_total': round(sum(kb), 1),
            'suu_kb_mean': round(sum(kb) / len(kb), 2),
            'suu_kb_p95': round(pct(kb, 0.95), 2),
            'suu_kb_max': round(max(kb), 2),
            'all_instr_mean': round(sum(r[4] for r in rows) / len(rows)),
            'suu_ms_mean': round(sum(ms) / len(ms), 3),
            'suu_ms_max': round(max(ms), 3),
            'worst_frame': {
                'frame': worst[0],
                'instr': worst[1],
                'kb': round(worst[2] / 1024, 1),
                'top': [[k, v] for k, v in worst[5].most_common(4)],
            },
        }
    return out


def read_snapshots():
    mem = {}
    for snap in glob.glob(os.path.join(SNAPSHOTS, '*.test.wowlua.snap')):
        scenario = os.path.basename(snap)[:-len('.test.wowlua.snap')]
        key = None
        with open(snap, encoding='utf-8') as f:
            for line in f:
                m = re.match(r'# .* › (.*)$', line.rstrip('\n'))
                if m:
                    key = m.group(1)
                    continue
                m = re.match(r'\| "?kb=(\d+)', line.strip())
                if m and key:
                    mem.setdefault(scenario, {})[key] = int(m.group(1))
    return mem


def wowlua_version():
    try:
        return subprocess.run([WOWLUA, '--version'], capture_output=True, text=True).stdout.strip()
    except OSError:
        return '?'


def git_head():
    try:
        return subprocess.run(['git', '-C', ROOT, 'rev-parse', '--short', 'HEAD'], capture_output=True,
                              text=True).stdout.strip()
    except OSError:
        return '?'


def summarize():
    scenarios = collections.OrderedDict()
    for path in sorted(glob.glob(os.path.join(PROFILES, 'tests_perf_*.speedscope.json'))):
        print('summarizing', os.path.basename(path), file=sys.stderr)
        s = summarize_file(path)
        if s:
            scenarios[s['scenario']] = s
    mem = read_snapshots()
    for name, s in scenarios.items():
        s['memory_kb'] = mem.get(name, {})
    results = {
        'date': datetime.date.today().isoformat(),
        'wowlua': wowlua_version(),
        'commit': git_head(),
        'scenarios': scenarios,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(RESULTS, 'w') as f:
        json.dump(results, f, indent=1)
        f.write('\n')
    print_results(results)
    return results


def print_results(results):
    print('\nwowlua %s, commit %s, %s' % (results['wowlua'], results['commit'], results['date']))
    print('%-34s %6s %9s %9s %9s %8s %8s %8s %9s' % (
        'scenario / phase', 'frames', 'instr/f', 'p95', 'worst', 'KB/f', 'KB p95', 'KB max', 'all/f'))
    for name, s in results['scenarios'].items():
        if not s['phases']:
            print(name)
        for phase, p in s['phases'].items():
            print('%-34s %6d %9d %9d %9d %8.2f %8.2f %8.2f %9d' % (
                (name + ' / ' + phase)[:34], p['frames'], p['suu_instr_mean'], p['suu_instr_p95'],
                p['suu_instr_max'], p['suu_kb_mean'], p['suu_kb_p95'], p['suu_kb_max'], p['all_instr_mean']))
            w = p['worst_frame']
            print('    worst frame %d: %s' % (w['frame'], ', '.join('%s %d' % (k, v) for k, v in w['top'][:3])))
        for k, v in s.get('memory_kb', {}).items():
            what = '' if k.startswith(('data ', 'saved ')) else ' (the whole emulated client)'
            print('    %s: %.1f MB%s' % (k, v / 1024, what))


def compare(a_path=RESULTS, b_path=BASELINE):
    with open(a_path) as f:
        a = json.load(f)
    with open(b_path) as f:
        b = json.load(f)
    print('now:      wowlua %s, commit %s, %s' % (a['wowlua'], a['commit'], a['date']))
    print('baseline: wowlua %s, commit %s, %s' % (b['wowlua'], b['commit'], b['date']))
    if a['wowlua'] != b['wowlua']:
        print('note: another wowlua version; the emulator and the game UI it loads may differ')
    print('%-40s %-20s %12s %12s %8s' % ('scenario / phase', 'metric', 'baseline', 'now', 'change'))
    for name, s in a['scenarios'].items():
        bs = b['scenarios'].get(name)
        if not bs:
            print('%-40s (new scenario)' % name)
            continue
        for phase, p in s['phases'].items():
            bp = bs['phases'].get(phase)
            if not bp:
                print('%-40s (new phase)' % (name + ' / ' + phase))
                continue
            for key, label in COMPARED:
                old, new = bp.get(key), p.get(key)
                if old is None or new is None:
                    continue
                ch = ((new - old) / old * 100) if old else (0 if new == old else float('inf'))
                mark = '' if abs(ch) < 2 else ('  better' if ch < 0 else '  WORSE')
                print('%-40s %-20s %12s %12s %+7.1f%%%s' % (
                    (name + ' / ' + phase)[:40], label, fmt(old), fmt(new), ch, mark))
        for k, v in s.get('memory_kb', {}).items():
            old = bs.get('memory_kb', {}).get(k)
            if old:
                print('%-40s %-20s %12s %12s %+7.1f%%' % (
                    name[:40], ('mem ' + k)[:20], fmt(old), fmt(v), (v - old) / old * 100))


def fmt(v):
    return ('%.2f' % v) if isinstance(v, float) else str(v)


def top(scenario, phase=None, frame=None, k=20, event=None):
    path = glob.glob(os.path.join(PROFILES, 'tests_perf_%s.test.wowlua.*.speedscope.json' % scenario))[0]
    names = test_names(os.path.join(ROOT, 'tests', 'perf', scenario + '.test.wowlua'))
    prof = Profile(path)
    test_prefix = 'tests/perf/%s.test.wowlua' % scenario
    outer = collections.defaultdict(lambda: [0, 0, 0])
    incl = collections.defaultdict(lambda: [0, 0, 0])
    selfc = collections.defaultdict(lambda: [0, 0, 0])
    callee = collections.defaultdict(lambda: [0, 0, 0])
    disp = collections.defaultdict(lambda: [0, 0, 0])
    n = 0
    for fr in prof.frames:
        num = int(fr['name'].split()[-1])
        if frame is not None and num != frame:
            continue
        ph = None
        for nid, calls, cost in fr['nodes'][:50]:
            for x in prof.chain(nid):
                if test_prefix in prof.file(x):
                    ph = names.get(prof.shared[prof.fidx[x]].get('line'), ph)
            if ph:
                break
        if frame is None and phase is not None and ph != phase:
            continue
        n += 1
        for nid, calls, cost in fr['nodes']:
            ch = prof.chain(nid)
            if event and prof.dispatch(ch) != event:
                continue
            first = None
            last = None
            seen = set()
            for x in ch:
                if prof.is_suu(x):
                    lab = prof.label(x)
                    if first is None:
                        first = lab
                    last = lab
                    if lab not in seen:
                        seen.add(lab)
                        e = incl[lab]
                        e[0] += cost[0]; e[1] += cost[1]; e[2] += calls if x == nid else 0
            if first is None:
                continue
            e = outer[first]; e[0] += cost[0]; e[1] += cost[1]
            e = disp[prof.dispatch(ch) + ' > ' + first]; e[0] += cost[0]; e[1] += cost[1]
            if prof.is_suu(nid):
                e = selfc[prof.label(nid)]; e[0] += cost[0]; e[1] += cost[1]; e[2] += calls
            else:
                e = callee[prof.name(nid) + '  <- ' + last]; e[0] += cost[0]; e[1] += cost[1]; e[2] += calls
    n = max(1, n)
    print('%s / %s: %d frames; per frame' % (scenario, phase or ('frame %s' % frame if frame else 'all'), n))
    for title, d, key in (('events/scripts > SuuUI entry, by instructions', disp, 0),
                          ('events/scripts > SuuUI entry, by KB', disp, 1),
                          ('entry points by instructions', outer, 0), ('entry points by KB', outer, 1),
                          ('functions (inclusive) by instructions', incl, 0),
                          ('functions (self) by KB', selfc, 1), ('functions (self) by instructions', selfc, 0),
                          ('game functions SuuUI called, by KB', callee, 1)):
        print('\n' + title)
        for lab, v in sorted(d.items(), key=lambda kv: -kv[1][key])[:k]:
            print('  %10.0f instr %9.2f KB  %8.0f calls  %s' % (v[0] / n, v[1] / 1024 / n, v[2] / n, lab[:140]))


def run(filters):
    os.makedirs(PROFILES, exist_ok=True)
    for old in glob.glob(os.path.join(PROFILES, '*.speedscope.json')):
        os.remove(old)
    targets = ['tests/perf/' + f for f in filters] or ['tests/perf/']
    jobs = os.environ.get('PERF_JOBS', '2')
    cmd = [WOWLUA, 'test', '--features', 'perf', '-u', '-j', jobs, '--profile-out', PROFILES] + targets
    print(' '.join(cmd), file=sys.stderr)
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        sys.exit(r.returncode)
    summarize()
    if os.path.exists(BASELINE):
        print()
        compare()


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__ or open(__file__).read().split('\nimport ')[0])
        return
    cmd, rest = argv[0], argv[1:]
    if cmd == 'run':
        run(rest)
    elif cmd == 'summarize':
        summarize()
    elif cmd == 'compare':
        compare(*(rest[:2] or []))
    elif cmd == 'baseline':
        with open(RESULTS) as f:
            data = f.read()
        with open(BASELINE, 'w') as f:
            f.write(data)
        print('baseline written:', os.path.relpath(BASELINE, ROOT))
    elif cmd == 'top':
        frame = None
        event = None
        if '--event' in rest:
            i = rest.index('--event')
            event = rest[i + 1]
            rest = rest[:i] + rest[i + 2:]
        if '--frame' in rest:
            i = rest.index('--frame')
            frame = int(rest[i + 1])
            rest = rest[:i] + rest[i + 2:]
        top(rest[0], rest[1] if len(rest) > 1 else None, frame, event=event)
    else:
        sys.exit('unknown command ' + cmd)


if __name__ == '__main__':
    main(sys.argv[1:])
