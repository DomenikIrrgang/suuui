#!/usr/bin/env python3
# tools/check_imports.py: holds the line between SuuUI's layers (API 0.47).
#
#   python3 -I tools/check_imports.py        (from the repository root)
#
# Prints every import that breaks a rule, as file:line, and exits 1; prints
# one "ok" line and exits 0 when there is none. The rules:
#
#   1. A feature module (src/Units/**) imports only the public API, values
#      and types alike (`import SuuUI, Module from "/Core/API"`, `import type
#      Text from "/Core/API"`), the standard library (wowlua:*), the data
#      (/Data/*), its own submodules (src/Units/Chat.wowlua and
#      src/Units/Chat/* are one feature) and the package's dependencies
#      (wowlua.json). What a plugin can't import, a built-in module doesn't.
#   2. Nothing below the modules (src/Core, src/UI, src/SettingsUI,
#      src/EditMode, src/Data) imports a module (/Units/*).
#   3. src/Core imports src/UI, src/SettingsUI, src/EditMode and
#      src/Diagnostics as types only (types make no code and never order the
#      load), except Core/API, which assembles the public table from all of
#      them (the composition root).
#   4. Nothing in src/Core, src/UI, src/SettingsUI or src/EditMode imports
#      the public API (/Core/API): it is built from them.
#   5. An example plugin (Examples/*/src) imports SuuUI's types from its
#      public API only (`import type X from "suuui/Core/API"`), as the plugin
#      guide teaches; its values come through the SuuUI global.
#
# An import a rule refuses that is right anyway goes into EXCEPTIONS below,
# with the reason: the one list of them.
#
# The test emulator (wowlua test) can't read source files, so this is a
# script: run it with `wowlua check` before a commit (CLAUDE.md), and CI runs
# it next to the tests.
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (importing file, imported module): why it is right. Empty is the goal.
EXCEPTIONS = {
}

IMPORT = re.compile(r'^import\s+(.*?)\s+from\s+"([^"]+)"', re.S)


def wowlua_files(top):
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, top)):
        dirnames.sort()
        for f in sorted(filenames):
            if f.endswith('.wowlua'):
                yield os.path.join(dirpath, f)


def imports(path):
    """(line, is_type, names, target) for each import statement at the top."""
    lines = open(path, encoding='utf-8').read().split('\n')
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('import ') or line.strip() == 'import':
            j, buf = i, line
            while 'from "' not in buf and j + 1 < len(lines) and j - i < 40:
                j += 1
                buf += '\n' + lines[j]
            m = IMPORT.match(buf)
            if m:
                head = ' '.join(m.group(1).split())
                is_type = head.startswith('type ') and head != 'type'
                out.append((i + 1, is_type, head, m.group(2)))
            i = j
        i += 1
    return out


def resolve(path, target):
    """A module path from the source root ("/UI/Panel"), or the target as written."""
    if target.startswith('./') or target.startswith('../'):
        src = os.path.join(ROOT, 'src')
        base = os.path.dirname(os.path.relpath(path, src))
        return '/' + os.path.normpath(os.path.join(base, target)).replace(os.sep, '/')
    return target


def dependencies():
    with open(os.path.join(ROOT, 'wowlua.json'), encoding='utf-8') as f:
        return set(json.load(f).get('dependencies', {}))


def layer(rel):
    parts = rel.split('/')
    return parts[1] if len(parts) > 2 and parts[0] == 'src' else None


def check():
    deps = dependencies()
    problems = []

    def refuse(path, line, target, why):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        if (rel, target) in EXCEPTIONS:
            return
        problems.append('%s:%d: imports "%s": %s' % (rel, line, target, why))

    def is_dependency(target):
        return target.split('/')[0] in deps and not target.startswith('/')

    for path in wowlua_files('src'):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        where = layer(rel)
        for line, is_type, head, written in imports(path):
            target = resolve(path, written)
            if where == 'Units':
                feature = rel.split('/')[2].replace('.wowlua', '')
                own = target.startswith('/Units/') and target.split('/')[2].replace('.wowlua', '') == feature
                if not (target == '/Core/API' or target.startswith('wowlua:') or target.startswith('/Data/')
                        or own or is_dependency(target)):
                    if target.startswith('/Units/'):
                        why = 'another feature module; reach it through a service (SuuUI.UseService)'
                    elif head.startswith('* as '):
                        why = ('SuuUI\'s insides; a module uses the public API only (SuuUI.* and SuuUI.UI.*'
                               ' from "/Core/API", exported and documented in Docs/API.md)')
                    else:
                        why = ('SuuUI\'s insides; a module uses the public API only (import %s from "/Core/API",'
                               ' exported and documented in Docs/API.md)' % ('type ' + head[5:] if is_type else head))
                    refuse(path, line, written, why)
                continue
            if where in ('Core', 'UI', 'SettingsUI', 'EditMode', 'Data') and target.startswith('/Units/'):
                refuse(path, line, written, 'a feature module, from below the modules')
                continue
            if where in ('Core', 'UI', 'SettingsUI', 'EditMode') and target == '/Core/API' and rel != 'src/Core/API.wowlua':
                refuse(path, line, written, 'the public API, from the layers it is built from')
                continue
            if where == 'Core' and rel != 'src/Core/API.wowlua' and not is_type and \
                    re.match(r'^/(UI|SettingsUI|EditMode|Diagnostics)/', target):
                refuse(path, line, written, 'a value from above the core (types only: `import type`)')

    for path in wowlua_files('Examples'):
        for line, is_type, head, written in imports(path):
            if written.startswith('wowlua:'):
                continue
            if not (is_type and written == 'suuui/Core/API'):
                refuse(path, line, written, 'an example imports SuuUI\'s types from "suuui/Core/API" only')

    for (rel, target), why in sorted(EXCEPTIONS.items()):
        if not os.path.exists(os.path.join(ROOT, rel)):
            problems.append('%s: listed in EXCEPTIONS but missing (%s)' % (rel, target))
    return problems


if __name__ == '__main__':
    found = check()
    for p in found:
        print(p)
    if found:
        print('%d import%s break the layers (tools/check_imports.py says why each rule holds)'
              % (len(found), '' if len(found) == 1 else 's'))
        sys.exit(1)
    print('ok: every import keeps to the layers')
