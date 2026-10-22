# Brief for a unit-test agent (SuuUI, branch wowlua-tests)

The text an orchestrator gives each test agent, followed by the area it
owns (see Docs/HANDOFF-tests.md for the areas). Feature-module areas
(src/Units) also get the second part.

## Part 1: every test agent

You are writing unit tests for part of SuuUI (a World of Warcraft addon written in wowlua, strict mode) as one of ~20 agents working in parallel in the same git worktree, and you may redesign the code you own so it is well suited for testing.

- Worktree (work only here): /Users/domenikirrgang/repositories/suuui.worktrees/wowlua-tests (branch wowlua-tests).
- Compiler/test runner: `wowlua` 0.9.1 on PATH. `wowlua check` (fast), `wowlua test <filter>` (each test file loads the whole addon with Blizzard's UI in the emulated client: ~4-15 s per file; run only your own files while working: `wowlua test unit/Core/Settings`). Never build or read ~/repositories/wowlua's working tree.
- Spec for 0.9.1: $SPEC (extract it once: `mkdir -p /tmp/wl091 && git -C ~/repositories/wowlua archive v0.9.1 spec crates/wowlua-stdlib | tar -x -C /tmp/wl091`) — spec/toolchain/tooling.md §16.1 (wowlua:test, wowlua:mock, world controls, matchers), crates/wowlua-stdlib/std/mock.wowlua and test.wowlua (the real API; read them for exact signatures), spec/language/*.md.
- READ FIRST: Docs/Testing.md (layout, what a unit test is here, tools, design rules) and CLAUDE.md; look at tests/helpers.wowlua and tests/smoke/*.test.wowlua for working examples.

Your job, for each source file you own:
1. Read it fully. Write tests/unit/<Dir>/<File>.test.wowlua (one per source file) that test every export, every public method of the objects it makes, and every branch you can reach: normal cases, edge cases (nil, empty, secret values via mock.secret where the code guards them, combat via mock.player:enterCombat()), and error paths. The user asked for (near) full coverage: aim to make every line and branch run. Measure with `wowlua test --coverage <your filter>` (tests/mocks/gc.wowlua works around a wowlua coverage crash; the summary lists each file's lines that never ran; `--reporter html` writes a report). It only works while the whole tree compiles, and other agents are editing: if it doesn't compile, retry later or cover by reading the code.
2. Redesign where it makes testing better: extract logic tangled with frames/events into functions or sibling modules, turn scattered upvalue state into classes, pass world reads as parameters (Docs/Testing.md "Design for testing"). You may split a file (git mv to keep history; new files are fine).
3. HARD CONSTRAINTS: what the player sees and when stays the same; secure frames, protected calls, taint-sensitive hooks, combat guards and secret-value guards stay exactly as they are; the public API (Docs/API.md, everything on the SuuUI global and on module objects) keeps every name and behaviour; SuuUIDB/SuuUIProbe layout unchanged. Other agents' files import yours: never remove or change the signature/behaviour of an export another file uses (`grep -rn "from \"/<your module>\"" src tests`); adding exports is fine. Only edit your own files, their tests, and new files you create. No git commands at all except `git mv`.
4. Tests must be deterministic: fake time with mock.advanceTime/advanceFrames, undo settings and frames between tests, no reliance on test order across files.
5. If a test reveals a real bug in SuuUI: fix it only if the fix is small and clearly right, add the test, and list it in your report; otherwise leave the code, mark the test `@skip("bug: …")`, and report it.
6. If the emulated client behaves differently from what the game does (per the code's comments, which record in-game probes), don't bend the code: note it as a VM suspicion with a repro.
7. Before finishing: `wowlua check` has no errors in your files (and none you caused elsewhere); `wowlua test <each of your test files>` all pass; `wowlua test smoke` and `wowlua test compat` still pass (they guard behaviour).

Write notes to Docs/test-notes/<AREA>.md: refactors you made (what moved where and why, and why behaviour is unchanged), bugs found (fixed / skipped), VM suspicions, wowlua compiler/test-runner issues with minimal repros (check Docs/wowlua-0.9.1-report.md first; only new ones), and anything you could not test (and why).

Reply when done with: files tested (test file per source file), refactors, bugs found, what's left untested and why, and the notes path. Be concise.

STRICT TYPING IN TESTS (the user asked for it explicitly): test files are checked in strict mode like src/ (the manifest's check.mode covers them). No `--!nocheck`, no `--!basic`, no `@nocheck`. Annotate every parameter of named functions, type locals that start empty (`local seen: string[] = {}`), give module objects and components real types where they exist (e.g. `modules.Module`, exported frame types such as `panel.Panel`, the data modules' exported types) instead of `any`. `:: any` only for genuinely dynamic values (a stand-in API table, a field the declarations lack), each such cast kept local and as narrow as possible. Mock world data passed to wowlua:mock (tables for spawnUnit, defineItem…) is fine as literals.

NAMES IN TESTS (public repository): never use a real player's or character's name or GUID in tests, comments or notes — not even one you find in SuuUI's source comments. Use invented placeholders: "Tamsin Ashford" (with a last name, as Forever's characters have), "Brannoc Ironhand", "Player", "Realm"; GUIDs like "Player-0000-00000000".


## Part 2: feature modules (src/Units) only

Your files are SuuUI feature modules (src/Units/*.wowlua): each registers itself with SuuUI.RegisterModule and is written against the public API only (`import SuuUI from "/Core/API"`).

Specific to Units:
- Get the module in tests with `SuuUI.GetModule("<id>")` (its id is in its RegisterModule call); it is enabled at login when on by default. Call its methods, fire the events it listens to (mock.fireEvent / fireUnitEvent, or the world controls that fire them for real: mock.player:target, setBag, openMerchant, defineItem…), change its settings with M:Set / settings.set and undo them.
- Many of these files are big (1–3k lines) and mix logic with frame code. Full redesign is allowed where it makes testing better: extract the logic (sorting, parsing, maths, text building, state) into module-level functions or sibling modules (e.g. src/Units/Bags/Sort.wowlua beside src/Units/Bags.wowlua, or src/Units/Bags/*.wowlua with the module in src/Units/Bags/init.wowlua — keep the module's id and what it does), test those directly, and test the frame code through the module.
- A feature module keeps using only the public API for SuuUI's own parts (no imports from src/Core or src/UI); its own sibling modules are fine.
- Services it provides (M:Provide) and the SuuUI.* functions that reach it keep their names and results.
