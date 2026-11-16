#!/usr/bin/env python3
# tools/perf.py: SuuUI's performance scenarios (tests/perf/README.md).
#
#   python3 -I tools/perf.py run [filter ...] [--fail]
#                                               run the scenarios (all, or the
#                                               files matching a filter), then
#                                               summarize and compare
#   python3 -I tools/perf.py summarize          summarize the last run's profiles
#   python3 -I tools/perf.py compare [A] [B] [--fail]
#                                               compare results A (default: the
#                                               last run) with B (default: the
#                                               baseline); --fail: exit 1 when a
#                                               metric is WORSE (past 2 %)
#   python3 -I tools/perf.py baseline           make the last run the baseline
#   python3 -I tools/perf.py restore            put back wowlua.json from the
#                                               backup a killed run left
#   python3 -I tools/perf.py top <scenario> [phase] [--frame N] [--event NAME]
#                                               where a phase's (or one frame's)
#                                               work goes: SuuUI's entry points
#                                               and functions, by instructions
#                                               and by garbage
#
# A run is `wowlua test --features perf -u --profile-out dist/perf/profiles
# tests/perf/...`: each scenario file's tests run in one emulated client, its
# profile (speedscope JSON with wowlua's per-frame trees) lands in
# dist/perf/profiles. It measures what players get: no runtime checks, no
# dev monitor (MEASURED). wowlua 0.13.15 builds `wowlua test` only from the
# `test` profile (wowlua#266), so for the run that profile in wowlua.json is
# rewritten, and the file is put back byte for byte afterwards (the backup
# beside it, MANIFEST_BACKUP). The summary (dist/perf/results.json) has, per scenario
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
import json, os, re, subprocess, sys, collections, datetime, glob, shutil, signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dist', 'perf')
PROFILES = os.path.join(OUT, 'profiles')
RESULTS = os.path.join(OUT, 'results.json')
BASELINE = os.path.join(ROOT, 'tests', 'perf', 'baseline.json')
SNAPSHOTS = os.path.join(ROOT, 'tests', 'perf', '__snapshots__')
MANIFEST = os.path.join(ROOT, 'wowlua.json')
# Ignored by git (.gitignore): wowlua.json as it was before a run rewrote it.
MANIFEST_BACKUP = os.path.join(ROOT, 'wowlua.json.perf-backup')
# The settings of the last run (summarize reads them)
RUN_SETTINGS = os.path.join(OUT, 'settings.json')

# The build a run measures: a player's (release builds have neither runtime
# checks nor the dev monitor, whose script wrapper costs instructions and
# makes everything under it, the scenario's driving and the game's handlers,
# count as SuuUI's). Set on the `test` profile for the run's duration.
MEASURED = collections.OrderedDict([('runtime-checks', 'none'), ('monitor', False)])
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

# A change past this (in percent) is marked: `better`, or `WORSE` (which
# `--fail` turns into exit status 1).
THRESHOLD = 2


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
        'settings': read_run_settings(),
        'scenarios': scenarios,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(RESULTS, 'w') as f:
        json.dump(results, f, indent=1)
        f.write('\n')
    print_results(results)
    return results


def read_run_settings():
    """the settings `run` measured the profiles with; None when unknown (no
    record, or a profile newer than it: made by hand, not by `run`)"""
    try:
        written = os.path.getmtime(RUN_SETTINGS)
        if any(os.path.getmtime(p) > written for p in glob.glob(os.path.join(PROFILES, '*.speedscope.json'))):
            return None
        with open(RUN_SETTINGS) as f:
            return json.load(f, object_pairs_hook=collections.OrderedDict)
    except (OSError, ValueError):
        return None


def describe(settings):
    if not settings:
        return 'settings not recorded'
    return ', '.join('%s %s' % (k, json.dumps(v)) for k, v in settings.items())


def print_results(results):
    print('\nwowlua %s, commit %s, %s (%s)' % (results['wowlua'], results['commit'], results['date'],
                                          describe(results.get('settings'))))
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


class SettingsDiffer(Exception):
    pass


def compare(a_path=RESULTS, b_path=BASELINE):
    """prints each metric's change; returns how many are WORSE. Raises
    SettingsDiffer when the two were recorded under different build settings
    (or one of them without any recorded): their numbers don't compare."""
    with open(a_path) as f:
        a = json.load(f)
    with open(b_path) as f:
        b = json.load(f)
    sa, sb = a.get('settings'), b.get('settings')
    if not sa or not sb or dict(sa) != dict(sb):
        raise SettingsDiffer(
            'not comparing: the two were measured under different build settings\n'
            '  %s: %s\n  %s: %s\n'
            'Runtime checks and the dev monitor change every count; measure both the same way '
            '(tools/perf.py run records its settings; a result without them is from before it did).' % (
                os.path.relpath(a_path, ROOT), describe(sa), os.path.relpath(b_path, ROOT), describe(sb)))
    print('now:      wowlua %s, commit %s, %s' % (a['wowlua'], a['commit'], a['date']))
    print('baseline: wowlua %s, commit %s, %s' % (b['wowlua'], b['commit'], b['date']))
    print('settings: %s' % describe(sa))
    if a['wowlua'] != b['wowlua']:
        print('note: another wowlua version; the emulator and the game UI it loads may differ')
    print('%-40s %-20s %12s %12s %8s' % ('scenario / phase', 'metric', 'baseline', 'now', 'change'))
    worse = []
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
                mark = '' if abs(ch) < THRESHOLD else ('  better' if ch < 0 else '  WORSE')
                if ch >= THRESHOLD:
                    worse.append('%s / %s %s' % (name, phase, label))
                print('%-40s %-20s %12s %12s %+7.1f%%%s' % (
                    (name + ' / ' + phase)[:40], label, fmt(old), fmt(new), ch, mark))
        for k, v in s.get('memory_kb', {}).items():
            old = bs.get('memory_kb', {}).get(k)
            if old:
                print('%-40s %-20s %12s %12s %+7.1f%%' % (
                    name[:40], ('mem ' + k)[:20], fmt(old), fmt(v), (v - old) / old * 100))
    if worse:
        print('\n%d metric(s) WORSE than the baseline by %d %% or more:' % (len(worse), THRESHOLD))
        for w in worse:
            print('  ' + w)
    return len(worse)


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


def manifest_dirty():
    """why wowlua.json may not be rewritten, or None"""
    if os.path.exists(MANIFEST_BACKUP):
        return ('%s is there: a run was killed before it put wowlua.json back. '
                'Check wowlua.json, then `python3 -I tools/perf.py restore` puts the backup back.'
                % os.path.relpath(MANIFEST_BACKUP, ROOT))
    try:
        r = subprocess.run(['git', '-C', ROOT, 'status', '--porcelain', '--', 'wowlua.json'],
                           capture_output=True, text=True)
    except OSError as e:
        return 'git could not tell whether wowlua.json has changes (%s)' % e
    if r.returncode != 0 and 'not a git repository' in r.stderr:
        # (an exported tree: nothing to compare with; the backup still puts it back)
        print('perf: not a git checkout; wowlua.json is put back from its backup', file=sys.stderr)
        return None
    if r.returncode != 0:
        return 'git could not tell whether wowlua.json has changes: %s' % r.stderr.strip()
    if r.stdout.strip():
        return ('wowlua.json has uncommitted changes; commit or undo them first '
                '(a run rewrites it for its duration and puts back what was committed)')
    return None


def measured_manifest(original):
    """wowlua.json's text with the `test` profile set to MEASURED"""
    data = json.loads(original.decode('utf-8'), object_pairs_hook=collections.OrderedDict)
    profiles = data.setdefault('profiles', collections.OrderedDict())
    test = profiles.setdefault('test', collections.OrderedDict())
    for k, v in MEASURED.items():
        test[k] = v
    return (json.dumps(data, indent=2, ensure_ascii=False) + '\n').encode('utf-8')


class Interrupted(Exception):
    pass


def write_atomic(path, data, mode_from):
    """path holds data or what it held before, never a part of data"""
    tmp = path + '.perf-tmp'
    try:
        with open(tmp, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        shutil.copymode(mode_from, tmp)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def restore_manifest(original, written):
    """puts the backup back in place (an atomic rename) and checks it"""
    try:
        with open(MANIFEST, 'rb') as f:
            now = f.read()
    except OSError:
        now = None
    if now is not None and now != written and now != original:
        os.makedirs(OUT, exist_ok=True)
        kept = os.path.join(OUT, 'wowlua.json.changed-during-run')
        with open(kept, 'wb') as f:
            f.write(now)
        print('perf: wowlua.json was changed during the run; that version is kept in %s'
              % os.path.relpath(kept, ROOT), file=sys.stderr)
    os.replace(MANIFEST_BACKUP, MANIFEST)
    with open(MANIFEST, 'rb') as f:
        if f.read() != original:
            sys.exit('perf: wowlua.json is not what it was before the run; check it (git diff wowlua.json)')


def with_measured_profile(work):
    """runs work() with wowlua.json's `test` profile set to MEASURED, and
    puts the file back byte for byte afterwards: after an error, Ctrl-C,
    SIGTERM or SIGHUP too (only a SIGKILL leaves the backup: `restore`)"""
    why = manifest_dirty()
    if why:
        sys.exit('perf: not running: ' + why)
    with open(MANIFEST, 'rb') as f:
        original = f.read()
    written = measured_manifest(original)
    caught = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    previous = {sig: signal.getsignal(sig) for sig in caught}

    def stop(sig, frame):
        raise Interrupted(signal.Signals(sig).name)

    for sig in caught:
        signal.signal(sig, stop)
    try:
        try:
            # No backup was there (manifest_dirty): one there now is this run's.
            write_atomic(MANIFEST_BACKUP, original, MANIFEST)
            write_atomic(MANIFEST, written, MANIFEST_BACKUP)
            print('perf: measuring under the `test` profile set to %s for this run (a player\'s build; '
                  'wowlua.json is put back afterwards)' % describe(MEASURED), file=sys.stderr)
            return work()
        finally:
            for sig in caught:
                signal.signal(sig, signal.SIG_IGN)
            if os.path.exists(MANIFEST_BACKUP):
                restore_manifest(original, written)
                print('perf: wowlua.json put back', file=sys.stderr)
    except Interrupted as e:
        sys.exit('perf: stopped (%s)' % e)
    finally:
        for sig in caught:
            signal.signal(sig, previous[sig])


def restore():
    if not os.path.exists(MANIFEST_BACKUP):
        print('perf: nothing to restore (no %s)' % os.path.relpath(MANIFEST_BACKUP, ROOT))
        return
    os.replace(MANIFEST_BACKUP, MANIFEST)
    print('perf: wowlua.json put back from %s; `git diff wowlua.json` shows what differs from the commit'
          % os.path.relpath(MANIFEST_BACKUP, ROOT))


def run(filters, fail=False):
    os.makedirs(PROFILES, exist_ok=True)
    for old in glob.glob(os.path.join(PROFILES, '*.speedscope.json')):
        os.remove(old)
    if os.path.exists(RUN_SETTINGS):
        os.remove(RUN_SETTINGS)
    targets = ['tests/perf/' + f for f in filters] or ['tests/perf/']
    jobs = os.environ.get('PERF_JOBS', '2')
    cmd = [WOWLUA, 'test', '--features', 'perf', '-u', '-j', jobs, '--profile-out', PROFILES] + targets

    def test():
        print(' '.join(cmd), file=sys.stderr)
        return subprocess.run(cmd, cwd=ROOT).returncode

    code = with_measured_profile(test)
    if code != 0:
        sys.exit(code)
    with open(RUN_SETTINGS, 'w') as f:
        json.dump(MEASURED, f)
        f.write('\n')
    summarize()
    if os.path.exists(BASELINE):
        print()
        try:
            worse = compare()
        except SettingsDiffer as e:
            print(e)
            if fail:
                sys.exit(2)
            return
        if worse and fail:
            sys.exit(1)


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__ or open(__file__).read().split('\nimport ')[0])
        return
    cmd, rest = argv[0], argv[1:]
    fail = '--fail' in rest
    rest = [r for r in rest if r != '--fail']
    if cmd == 'run':
        run(rest, fail)
    elif cmd == 'summarize':
        summarize()
    elif cmd == 'compare':
        try:
            worse = compare(*(rest[:2] or []))
        except SettingsDiffer as e:
            print(e, file=sys.stderr)
            sys.exit(2)
        if worse and fail:
            sys.exit(1)
    elif cmd == 'restore':
        restore()
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
