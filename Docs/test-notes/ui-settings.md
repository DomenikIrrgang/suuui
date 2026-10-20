# Test notes: ui-settings

Area: the talent and spell pages in `src/UI/` (TalentTree, TalentBuilds,
Spellbook, Timeline), the settings window and its sections
(`src/SettingsUI/`: Registry, Window, Sections, GameMenu) and edit mode
(`src/EditMode/`: EditMode, LayoutCheck). One test file per source file,
next to the others of its folder (`tests/unit/UI/`, `tests/unit/SettingsUI/`,
`tests/unit/EditMode/`), with the shared helper
`tests/unit/SettingsUI/UiSettingsHelpers.wowlua` (the colour token Draw
keeps for a region, a region's point as a table, what was printed, a
theme change). Written on wowlua 0.9.4. The TalentBuilds, Timeline,
Registry and LayoutCheck tests came from the WIP checkpoint 68d8ab6 and
were verified here (Timeline and Registry needed one line each, below).

The window and edit mode are tested with sections and movers of the
test's own (a `wtest` / `emtest` settings namespace registered at the top
of the file), so the tests don't depend on which modules are loaded:

- Window: one section with a row for every control type (toggle,
  checkbox, segmented, select with options and a description from
  functions, slider, stepper, text, button, custom bound and unbound, no
  control, an unknown control, rows that refuse, a disabled row, a
  module's on switch), a section with `build`, and one merged into it.
  Rows are found through the page table (`import internal pages`); custom
  controls record their `onChange` so a test can change a value as the
  player does.
- EditMode: a named mover with a settings section, a bare one, and one
  that places itself, takes drops over when asked, has an action and its
  own reset; per-test movers (turned off, placed by another, never shown)
  are registered with a second owner and unregistered after each test.

## Test files

| Source | Test file | Tests |
|---|---|---|
| TalentTree | `UI/TalentTree.test.wowlua` | nodes in every state, hover, clicks, the build's next talent, a marked one; the trees' panels and arrows; the spec row; the summary (yours, someone else's read only, the build picker, its badge and buttons); the foot (points, what's planned, Undo and Apply or a build's actions, Back); the order panel (lines, hover, dragging a line, scrolling along); the game's talent tooltip |
| TalentBuilds | `UI/TalentBuilds.test.wowlua` | (from the checkpoint) the order check, ranks to steps, the share text, the game's talent string |
| Spellbook | `UI/Spellbook.test.wowlua` | the schools (open, to train, hover, click); the head (to train here, in all, the cost, as room allows); the switches; cells by status; column widths; rows fitted to the page; the pager; hover and drag; the cooldown sweep |
| Timeline | `UI/Timeline.test.wowlua` | (from the checkpoint) the track and the list |
| Registry | `SettingsUI/Registry.test.wowlua` | (from the checkpoint) registering, the order, merged sections, a module's section, unregistering |
| Window | `SettingsUI/Window.test.wowlua` | opening (the first section, the nav's choice, the header's profile); the nav (headings per category, hover, leave, click); merged and built sections; every control bound, refused values in chat, descriptions (the combat note, from functions), disabled rows, the changed mark, group counts, the nav's dot, a row's reset; search (typed, by row, description, group, section, merged section; the nav's order; no match; cleared; a page that fails to build is reported and skipped); the preview (title, note, centred or from its edge, placed again on a size change, an old view ignored); Reset section (armed, timed out, not while searching, not a module's switch); refreshes (on the next frame, once per burst; while hidden on the next show; module events); the profile picker; Export; Import (by the string's name or the one given, not a profile, a taken name); sections that come and go (added, searched, removed, merged in later); a page dropping its groups; toggle, Done, close |
| Sections | `SettingsUI/Sections.test.wowlua` | Appearance (scale, theme, colour vision, Edit layout, the welcome), Motion, Profiles (new, copy, delete, role presets, by role, export and import, reset everything), Modules (built in, plugins, every state, what can't be turned on, a module without an id, one registered later) |
| GameMenu | `SettingsUI/GameMenu.test.wowlua` | the button under the menu (made once), a click (menu closed, window opened), none in combat |
| EditMode | `EditMode/EditMode.test.wowlua` | positions (placed, the defaults for key and label, a self-placing mover, a position that isn't a table, hidden, a module's own show, after combat); rect and anchorFor; entering and leaving (events, `/suu edit`, toggle, refused in combat, closed by combat); outlines (size, tag, hidden, turned off and refreshed, never shown, registered while open, unregistered and reused); movers(); selecting (toolbar above or under, the settings hint, hover); clicks elsewhere; right-click settings; drops (snap, no snap, screen thirds, a pinned anchor, a mover's own drop), the real frame following a drag, a frame placed by another; the arrows (Shift, a mover's own drop), Enter, Escape; X and Y (typed, kept on screen with a warning, Tab, the keys); the anchor and its tooltips; Hide, Reset, a mover's action; the toolbar with nothing selected; the panel (snap, grid size and its veto, the grid drawn again, dragged and put back, Reset all, Done, the group preview); a theme change |
| LayoutCheck | `EditMode/LayoutCheck.test.wowlua` | (from the checkpoint) the root's size per screen, rectangles from anchors, overlaps, which frames are checked, the report |

Coverage (`wowlua test -j 2 --coverage`, each file measured with its own
test file): every line of all ten runs.

## Refactors

None.

## Bugs found

None in the code. One comment was out of date: Timeline's header still
showed the later-events line as "then Inferno in 0:52", where the code
writes "52s" (the checkpoint's test expected the old text).

Seen, not changed: when the settings window goes from a section with a
preview to one without, the preview's note keeps the old text. The column
is hidden then, so nothing shows.

## VM / wowlua findings (new)

- **`mock.drag` runs no frame between `OnDragStart` and `OnDragStop`**, so
  an `OnUpdate` set while dragging (edit mode's frames following the
  outline) never runs. The tests call the two scripts themselves, move the
  outline and advance a frame in between. A drag that takes a frame (or
  `n` frames) would make this a one-liner.
- **A key no frame keeps runs its real binding** (`mock.pressKey("ENTER")`
  opens the chat box), as in the client. Tests of "this key passes"
  call the handler directly instead.
- **The test profile's runtime checks reject `nil` for a typed parameter
  before the function's own assert** (Registry's `register(nil)` now
  expects "expected, got nil"). This is C39 ("exports"), already listed.

## Not tested, and why

Nothing in these ten files.
