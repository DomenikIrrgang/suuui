#!/usr/bin/env python3
# tools/lazy_data.py: turns a generated data file's table into steps that
# build it later, a part at a time (the performance work of 2026-11-09).
#
#   python3 -I tools/lazy_data.py src/Data/QuestStarts.wowlua ...
#
# The generators write `export local name: Type = { ... }`: a table the
# client built at login for everyone (QuestStarts alone 3 MB), whether the
# map, the collections or the professions were ever opened. Each generator
# runs this on what it wrote (the update scripts too); it rewrites the
# table as
#
#   export const nameSteps: ((t: Type) -> ())[] = {
#       function(t: Type)
#           t.quests = {}
#           local s = t.quests
#           s[2] = { ... }
#           ...
#       end,
#       ...
#   }
#
# the same fields in the same order, cut into functions of about STEP_WORK
# each: the values and tables a step makes, which is what building costs
# (2026-11-13: cut by bytes of source, a step of quest objectives' text ran
# 700 instructions and one of map pins 12,000, so four of those made one
# frame's spike; by work, each step costs about the same). Core/Data runs
# them on first use (all at once) or a few a frame (Prepare), and lets each
# go once it ran, so the code that built the table is garbage after. A big
# section (a field whose value is a table of keyed entries) is filled entry
# by entry, so it can span steps; anything else is one statement. Comments
# after an entry stay with it. A list's trailing nils are left out
# ({ "a", 3, nil, nil } is { "a", 3 }: the same values, without the empty
# slots the constructor would make).
#
# A file already in this form is cut again from its statements (the data
# kept as it is), so a change here reaches the data without its source.
import re
import sys

# a step's work: each value (a number, a string, true, nil, a name) one, and
# each table two more (it is made and filled)
STEP_WORK = 5000
SPLIT = 4 * 1024  # a section at least this big is filled entry by entry


def work(text):
    """What building `text` costs: its values, and two more per table."""
    w = 0
    for t in tokens(text, 0):
        if t.kind in ('word', 'string'):
            w += 1
        elif t.kind == '{':
            w += 2
    return w

HEAD = re.compile(r'^export local (\w+): ([^=]+?) = ', re.M)


class Tok:
    __slots__ = ('kind', 'text', 'start', 'end')

    def __init__(self, kind, text, start, end):
        self.kind, self.text, self.start, self.end = kind, text, start, end


def tokens(src, pos):
    """The tokens from pos: strings, comments, brackets, commas, '=', words."""
    i, n = pos, len(src)
    while i < n:
        c = src[i]
        if c in ' \t\r\n':
            i += 1
            continue
        if src.startswith('--', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            if src.startswith('--[[', i) or src.startswith('--[=', i):
                raise SystemExit('lazy_data: long comments are not supported')
            yield Tok('comment', src[i:j], i, j)
            i = j
            continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    j += 1
                if src[j] == '\n':
                    raise SystemExit('lazy_data: a string runs over a line end')
                j += 1
            yield Tok('string', src[i:j + 1], i, j + 1)
            i = j + 1
            continue
        if src.startswith('[[', i) or src.startswith('[=', i):
            raise SystemExit('lazy_data: long strings are not supported')
        if c in '{}[](),;=':
            yield Tok(c, c, i, i + 1)
            i += 1
            continue
        j = i
        while j < n and src[j] not in ' \t\r\n{}[](),;="\'' and not src.startswith('--', j):
            j += 1
        yield Tok('word', src[i:j], i, j)
        i = j


class Field:
    """One field of a table constructor: its key (`name`, `[expr]`, or None
    for a positional one), its value's text, a comment after it on its line;
    or a comment on a line of its own (`only`)."""

    def __init__(self, key=None, value=None, comment=None, only=None):
        self.key, self.value, self.comment, self.only = key, value, comment, only


def field_of(src, toks):
    """A field from its tokens (with their depth inside the field)."""
    first = toks[0]
    eq = None
    if first[0].kind == 'word' and len(toks) > 1 and toks[1][0].kind == '=':
        eq = 1
    elif first[0].kind == '[':
        for i, (t, d) in enumerate(toks):
            if t.kind == ']' and d == 0:
                if i + 1 < len(toks) and toks[i + 1][0].kind == '=':
                    eq = i + 1
                break
    last = toks[-1][0]
    if eq is None:
        return Field(None, src[first[0].start:last.end])
    key = src[first[0].start:toks[eq][0].start].strip()
    return Field(key, src[toks[eq + 1][0].start:last.end])


def fields(src, open_pos):
    """The fields of the table constructor whose `{` is at open_pos, and the
    position after its `}`."""
    out = []
    depth = 0
    cur = []  # the current field's tokens, with their depth below the table
    sep_end = None  # where the last field's separator ended
    for t in tokens(src, open_pos):
        if depth == 0:
            if t.kind != '{':
                raise SystemExit('lazy_data: not a table at the start')
            depth = 1
            continue
        if depth == 1 and t.kind == 'comment':
            if cur:
                # (after a last field without a separator)
                cur.append((t, -1))
            elif out and sep_end is not None and '\n' not in src[sep_end:t.start] and out[-1].only is None:
                out[-1].comment = t.text
            else:
                out.append(Field(only=t.text))
            continue
        if depth == 1 and t.kind in (',', ';', '}'):
            if cur:
                comment = None
                if cur[-1][1] == -1:
                    comment = cur.pop()[0].text
                f = field_of(src, cur)
                f.comment = comment
                out.append(f)
                cur = []
            sep_end = t.end
            if t.kind == '}':
                return out, t.end
            continue
        # (a closing bracket at the depth of its opening one)
        if t.kind in '}])':
            depth -= 1
        cur.append((t, depth - 1))
        if t.kind in '{[(':
            depth += 1
    raise SystemExit('lazy_data: the table never closes')


def finish(f, src):
    return f.value


def target(base, key):
    if key.startswith('['):
        return base + key
    return base + '.' + key


def trim_nils(text):
    """`text` with the trailing `nil`s of each list left out ({ "a", 3, nil,
    nil } is { "a", 3 }): the same values at the same places, without the
    empty slots the constructor would make (QuestStarts' rows had 28,000).
    A list whose last value before them is a call or `...` keeps them (it
    would give all its values instead of one)."""
    toks = [t for t in tokens(text, 0)]
    cuts = []  # (start, end, replacement)

    def table(i):
        # toks[i] is '{': its fields' token ranges, then the index after '}'
        fields_ = []
        j = i + 1
        start = j
        depth = 0
        while True:
            k = toks[j].kind
            if k == '{':
                j = table(j)
                continue
            if k in '[(':
                depth += 1
            elif k in '])':
                depth -= 1
            elif depth == 0 and k in (',', ';', '}'):
                if j > start:
                    fields_.append((start, j - 1))
                if k == '}':
                    trim(i, j, fields_)
                    return j + 1
                start = j + 1
            j += 1

    def trim(open_i, close_i, fields_):
        n = len(fields_)
        while n > 0:
            a, b = fields_[n - 1]
            if a == b and toks[a].kind == 'word' and toks[a].text == 'nil':
                n -= 1
            else:
                break
        if n == len(fields_):
            return
        if n > 0:
            a, b = fields_[n - 1]
            if toks[b].kind == ')' or toks[b].text == '...':
                return
            if any(toks[x].kind == 'comment' for x in range(b + 1, close_i)):
                return
            gap = ' ' if text[toks[close_i].start - 1] in ' \t' else ''
            cuts.append((toks[b].end, toks[close_i].start, gap))
        else:
            if any(toks[x].kind == 'comment' for x in range(open_i + 1, close_i)):
                return
            cuts.append((toks[open_i].end, toks[close_i].start, ''))

    i = 0
    while i < len(toks):
        if toks[i].kind == '{':
            i = table(i)
        else:
            i += 1
    if not cuts:
        return text
    cuts.sort()
    out = []
    at = 0
    for a, b, rep in cuts:
        out.append(text[at:a])
        out.append(rep)
        at = b
    out.append(text[at:])
    return ''.join(out)


STEPS_HEAD = re.compile(r'^export const (\w+)Steps: \(\(t: ([^)]+?)\) -> \(\)\)\[\] = ', re.M)


def value_end(toks, i):
    """The index after the value starting at toks[i]: a table constructor
    (balanced) or one token."""
    if toks[i].kind != '{':
        return i + 1
    depth = 0
    while True:
        k = toks[i].kind
        if k == '{':
            depth += 1
        elif k == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1


def steps_stmts(src):
    """A file in step form: its name, type, the statements its steps hold
    (as `lazy` makes them), and where the steps' list starts and ends."""
    m = STEPS_HEAD.search(src)
    if not m:
        return None
    name, typ = m.group(1), m.group(2).strip()
    toks = list(tokens(src, m.end()))
    if toks[0].kind != '{':
        raise SystemExit('lazy_data: the steps are not a list')
    stmts = []
    i = 1
    current = None
    while toks[i].kind != '}':
        if toks[i].kind == ',':
            i += 1
            continue
        if toks[i].text != 'function':
            raise SystemExit('lazy_data: a step is not a function at %d' % toks[i].start)
        # function(t: Type)
        while toks[i].kind != ')':
            i += 1
        i += 1
        current = None
        while toks[i].text != 'end':
            t = toks[i]
            if t.kind == 'comment':
                stmts.append((current, None, t.text))
                i += 1
                continue
            if t.text == 'local':
                # local s = <section>
                start = toks[i + 3]
                j = i + 4
                while toks[j].kind in '[]' or (toks[j].kind in ('string', 'word') and toks[j - 1].kind == '['):
                    j += 1
                current = src[start.start:toks[j - 1].end]
                i = j
                continue
            # <target> = <value>
            start = t
            j = i
            while toks[j].kind != '=':
                j += 1
            k = value_end(toks, j + 1)
            text = src[start.start:toks[k - 1].end]
            comment = None
            if toks[k].kind == 'comment' and '\n' not in src[toks[k - 1].end:toks[k].start]:
                comment = toks[k].text
                k += 1
            section = current if text.startswith('s[') or text.startswith('s.') else None
            stmts.append((section, text, comment))
            i = k
        i += 1
    return name, typ, stmts, m.start(), toks[i].end


def lazy(src):
    m = HEAD.search(src)
    if not m:
        found = steps_stmts(src)
        if found:
            name, typ, stmts, start, end = found
            return src[:start] + steps_list(name, typ, stmts) + src[end:]
        raise SystemExit('lazy_data: no `export local name: Type = {` in the file')
    name, typ = m.group(1), m.group(2).strip()
    open_pos = m.end()
    if src[open_pos] != '{':
        raise SystemExit('lazy_data: the value is not a table')
    root, end = fields(src, open_pos)
    # the fields written whole first (small ones: a list a module wants
    # without the rest, Core/Data's Until), then the big sections entry by entry
    whole = []
    stmts = []  # (section or None, text, comment)
    for f in root:
        if f.only is not None:
            whole.append((None, None, f.only))
            continue
        if f.key is None:
            raise SystemExit('lazy_data: a positional field at the top')
        value = f.value
        inner = None
        if value.startswith('{') and len(value) >= SPLIT:
            inner, _ = fields(value, 0)
            if any(e.key is None and e.only is None for e in inner):
                inner = None
        if inner is None:
            whole.append((None, target('t', f.key) + ' = ' + value, f.comment))
            continue
        section = target('t', f.key)
        stmts.append((None, section + ' = {}', f.comment))
        for e in inner:
            if e.only is not None:
                stmts.append((section, None, e.only))
            else:
                stmts.append((section, target('s', e.key) + ' = ' + e.value, e.comment))
    stmts = whole + stmts
    note = (f'-- Built on first use, a step at a time (tools/lazy_data.py): each of\n'
            f'-- `{name}Steps` fills a part of one {typ} table, in order (Core/Data).\n')
    head = src[:m.start()]
    tail = src[end:]
    return f'{head}{note}{steps_list(name, typ, stmts)}{tail}'


def steps_list(name, typ, stmts):
    """The steps' list from the statements, cut into steps of about
    STEP_WORK."""
    out = []
    size = 0
    current = None
    for section, text, comment in stmts:
        if text is not None:
            text = trim_nils(text)
        cost = work(text) if text is not None else 0
        # (a step full: the next statement starts another)
        if not out or (size > 0 and size + cost > STEP_WORK):
            if out:
                out.append('    end,')
            out.append(f'    function(t: {typ})')
            size, current = 0, None
        if section is not None and section != current:
            out.append(f'        local s = {section}')
            current = section
        if text is None:
            line = '        ' + comment
        else:
            line = '        ' + text + ((' ' + comment) if comment else '')
        out.append(line)
        size += cost
    if out:
        out.append('    end,')
    body = '\n'.join(out)
    return f'export const {name}Steps: ((t: {typ}) -> ())[] = {{\n{body}\n}}'


def main(paths):
    for p in paths:
        with open(p, encoding='utf-8') as fh:
            src = fh.read()
        new = lazy(src)
        if new != src:
            with open(p, 'w', encoding='utf-8') as fh:
                fh.write(new)
            print('lazy_data:', p)


if __name__ == '__main__':
    main(sys.argv[1:])
