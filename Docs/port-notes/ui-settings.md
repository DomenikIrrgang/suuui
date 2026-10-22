# Port notes: ui-settings (settings window, edit mode, talent tree, spellbook, timeline)

Files: `src/UI/TalentTree`, `src/UI/TalentBuilds`, `src/UI/Spellbook`,
`src/UI/Timeline`, `src/SettingsUI/GameMenu`, `src/SettingsUI/Registry`,
`src/SettingsUI/Sections`, `src/SettingsUI/Window`, `src/EditMode/EditMode`,
`src/EditMode/LayoutCheck` (all `.wowlua` now).

## 1. VM suspicions

None: the VM wasn't run for these files.

## 2. Compiler and tooling issues (0.9.1)

No new compiler issues. Two notes on how strict mode reads the code:

- Methods named `export` and `import` work as export names
  (`export function export()`, `settingsWindow.import()`, `{ onClick = import }`).
  I checked this in a scratch project, build output included.
- A function typed with several returns, `(number?, number, number, number)`,
  can't `return nil` alone. Every value has to be written out (see 4.1).

## 3. Standard library gaps

### Spellbook's coin text (`coinText`)

`wowlua:format` has money formatting, but not this output. SuuUI writes the
digits in ink and the units in the coin colours, or all of it in
ember-text when you can't afford it. It also returns a plain copy for
measuring. So SuuUI's code stays. The stdlib would need a money formatter
that takes a colour per part (digits, each unit) and can return a plain
copy too.

### Timers: `after` for `C_Timer.After` / `C_Timer.NewTimer`

Every `C_Timer.After(0, fn)` and `C_Timer.NewTimer(3, fn)` is now
`after(…)`, which is a `NewTimer`. The timing is the same: next frame, or
3 s. An error inside is now reported through wowlua:errors instead of
raised. The confirm timers (Reset section, Reset everything, role presets,
Copy/Delete profile) keep their handles as `TimerHandle?` and call
`:Cancel()` as before.

### `hookScript` for the game menu

`GameMenuFrame:HookScript("OnShow", …)` became `hookScript(GameMenuFrame,
"OnShow", …)`. The hook now runs inside `callIn`, so an error is reported
instead of raised. The hooks on SuuUI's own frames (`view:HookScript`,
`b:HookScript`) are unchanged.

## 4. Port decisions

### 4.1 Behaviour changes, all small

- **`editMode.rect` (public: `SuuUI.EditMode.Rect`)**: for a frame with no
  rectangle it returns `nil, nil, nil, nil` instead of a single `nil`
  (strict mode needs all four values). Callers that test the first value
  see no difference. Only `select("#", Rect(f))` does.
- **LayoutCheck** writes the report to `DB.probe.layoutCheck` (/Core/DB)
  and no longer does `SuuUIProbe = SuuUIProbe or {}` first. That's the
  same table once the SavedVariables have loaded, and `/suu layoutcheck`
  only runs after that.
- **Profile export/import** go through `/Core/Serialize` `encode`/`decode`,
  as before. The string is now wowlua:serialize, and old SUU1 strings
  still decode (Core's change, not this file's).
- **"Show the welcome again"** calls `SuuUI.ShowWelcome()` from
  `/Core/API`, not `ns.API.ShowWelcome()`. It's the same function.
- **Sections' Theme options** use `themes.all()`, which was `Themes.List`.
- **The edit-mode veto** on `layout.gridSize` now returns `nil, nil`
  explicitly on the accept path. Before, it fell off the end.

### 4.2 Renames forced by export names or shadowing

All behaviour-neutral:

- EditMode: the module-level `movers` list is now `moverList`, because
  `movers()` is the export. `groupPreview` / `groupPreviewAuras` are now
  `previewSize` / `previewAuras`, because `groupPreview()` is the export.
  The panel's inner `place` is now `placePanel`. The frame's own
  methods are unchanged.
- Window: the footer's `import` / `export` locals are now
  `importButton` / `exportButton`. The search callback's `text` is now
  `typed`, and `any` is now `anyHit`.
- `text` parameters and locals that shadowed the imported `text()` were
  renamed, in TalentTree (`smallTag`, the tooltip's `need`), Spellbook
  (`coinText`) and Timeline (`SetMeta`).
- Parameters that were reassigned (`SetData(d)`, `SetHead(…, toTrain)`,
  `fmtTime(s)`, `decodeTalentBuild(text)`, `anchorFor(…, point)`) now
  copy into a local first.

### 4.3 Casts and narrowing to look at

- **TalentTree `traitTooltip`**: the declared `TraitCondInfo` has no
  `tooltipText` field (E2003). The condition is read untyped
  (`local okC, c: any = pcall(…)`). Either the wow-api declaration is
  missing the field, or the client's struct doesn't have it and the "spend
  N more points" line never shows. Check it against the client's
  `C_Traits.GetConditionInfo` docs, or with a probe.
- **Window `export`**: `profiles.export()` is cast to `settings.Exported`,
  because the current profile always exists. Before, a nil would have
  errored on `data.name` too.
- **Sections**: `profiles.current() :: string` in the "Reset everything"
  message. `vision.LABEL[mode] :: string`, `rolePresets.NAME[role] ::
  string` and `roles.LABEL[…] :: string` are casts on lookups that always
  hit. They aren't fallbacks, so the behaviour is unchanged.
- **TalentBuilds** has typed shapes now (`TalentNode`, `TalentTreeData`,
  `TalentStep`, `DecodedBuild`, `GameTalents`). The records have a
  `[string]: any` indexer, so the Talents module's extra fields fit.
  `cutUTF8`'s loop was rewritten so the byte reads narrow. The logic is
  the same.
- Frames with fields of their own (`b.icon`, `o.tagFrame`, `page.stack`, …)
  are typed `any`, and so are the UI helpers' results that they hold.

### 4.4 Bugs noticed and left

- **Sections `moduleRow`**: `parts = { m.description, … }` is walked with
  `ipairs`. For a module with no `description`, `ipairs` stops at the nil
  in slot 1, so the row's description comes out empty: no "Built in", no
  state, no error text. `parts` is typed `any[]` to keep that behaviour.
  The fix would be to drop nils before the walk.
