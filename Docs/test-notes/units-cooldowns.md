# Test notes: units-cooldowns

Area: the Cooldown Manager module (`src/Units/CooldownManager.wowlua` and
its sibling modules `src/Units/CooldownManager/`: Lists, Conditions,
Migrations), Defensives (`src/Units/Defensives.wowlua`) and Buff
indicators (`src/Units/BuffIndicators.wowlua`). Written on wowlua 0.9.4.

The sibling modules came from the WIP checkpoint 68d8ab6: the list work
(paths, moves, shared slots, counting changes, "Seen recently"), the
conditions (their words and sentences, the editor's changes) and the
migrations moved out of the module into pure functions, with a test file
each in `tests/unit/Units/CooldownManager/` (the migrations' with the
profile `tests/profiles/cooldowns-migrations.json`). Reviewed here against
the code they replaced: the same behaviour (the aura scan now hands on a
secret name as nil, which the merge skips as the old loop did; a
condition's new type goes through `Conditions.changeType`, as
`setCondition` did). The checkpoint's `CooldownManager.test.wowlua` was a
probe; it is replaced by the module's tests.

The modules are tested through their settings: each section's custom rows
built in a host (the Cooldown Manager's preset bar and list editor, the
Defensives and Buff indicators editors), worked with clicks, the controls'
own `onChange`, drags with `mock.setCursorPosition` and the rows'
`OnDragStart`/`OnDragStop` (the indicators' grips), and their previews.
The tracker and the resource bar themselves are UI/CooldownTracker's and
UI/ResourceBar's (tested in ui-hud); here only what the module gives them.
The character is an Unspecced warrior: its four presets (Unspecced, Arms,
Fury, Protection) fill the lists, with conditions, a collection holding
shared slots and a shared slot of their own. The talent trees, the
spellbook's cooldowns and a talent list are stubbed where a test needs
them; the confirm dialog is stubbed to capture its question.

## Test files

| Source | Test file | Tests |
|---|---|---|
| CooldownManager | `Units/CooldownManager.test.wowlua` | the spec from the trees (most points, none, a broken read, new points); setups from presets, Load, a missing preset; the lists from before setups (moved once, kept, another class's dropped); what the tracker, its visibility and the resource bar get (the cast bar's width live); the preset bar (setups, the character's talents, the status, Load at once or after asking, Reset, no preset); the editor: Cooldowns and Auras, heads and counts, every kind of row and its summary, folds and folded icons, the switch, Move to, ×, "+ Add" (seen recently, by name, by ID, the presets' shared slots, auras on you), "+ Shared slot", "+ Collection", "+ Add to", weapon enchants; dragging (before, after, onto a list's foot, nowhere, onto a spell: a new shared slot after asking, onto a shared slot, a collection, a "+ Add to" row, a member out, a collection refused); the Behaviour panel for a cooldown, a cooldown slot, a single aura, a debuff, an aura slot, a member, a collection, a weapon enchant, every control and Reset and Done; conditions (added, Not, every type and its control, talents from the list, by ID, read live, removed, any of these); the panel closing; "Seen recently" (casts, auras, combat); Blizzard's manager off and back on; the settings rows' reasons |
| CooldownManager/Lists | `Units/CooldownManager/Lists.test.wowlua` | (from the checkpoint) presets, copies, paths, moves, combining, accepts, counting changes, recent |
| CooldownManager/Conditions | `Units/CooldownManager/Conditions.test.wowlua` | (from the checkpoint) new conditions, words, sentences, types, talents |
| CooldownManager/Migrations | `Units/CooldownManager/Migrations.test.wowlua` | (from the checkpoint) each migration on a saved profile |
| Defensives | `Units/Defensives.test.wowlua` | SuuUI's list and the profile's own; what the group frames get (by kind, Warded, on only); off and on; the editor's wells and counts, a row's switch, kind, Warded (its tooltip) and ×, an empty well, "+ Add" by name and ID, Reset; the preview's party and raid |
| BuffIndicators | `Units/BuffIndicators.test.wowlua` | defaults per spec, lists per spec, the older one-list shape; what the group frames get; a new spec; off and on; the editor (the spec picker, a tree no preset names, rows and summaries of every kind, "+ Add", ×, reordering by the grip); the Edit indicator modal (each field and what applies, Reset, Done, the live frames waiting for it, closing with its entry, another spec, the page); the preview |

Coverage (`wowlua test -j 2 --coverage`, the area's files): every line of
all six sources. Two lines are marked `-- wowlua: coverage ignore`: the
combo points' and druid mana's `return false` for a rogue or druid (the
test character is a warrior; the class is read once at load).

## Refactors

The checkpoint's (reviewed, kept): the Cooldown Manager's list work,
conditions and migrations in `CooldownManager/`. Here: the remove button's
up and down arrows, never used, are gone (`glyphButton(kind)` is
`removeButton`).

## Bugs found

- **Fixed: the Defensives editor couldn't save a change** (in the plain-Lua
  SuuUI too). The `list` setting defaulted to `false` and every change
  wrote the entries' table, which Settings refuses ("defensives.list takes
  a boolean, not a table"): switching an entry off, its kind, Warded, "+
  Add", × all errored. The setting is `{ entries = … }` now (`{}`: SuuUI's
  list). No profile can hold the old shape: nothing was ever saved.
- **Fixed: the Behaviour panel's Timer and Stacks switches couldn't be
  turned off** (in the plain-Lua SuuUI too). They saved
  `(not v) and false or nil`, which is always nil (`x and false` is false,
  so `or nil` wins): the timer and the stack count kept showing.

## VM / wowlua findings (new)

None new in this area.

## Not tested, and why

Nothing in these six files.
