# Test notes: units-hud

Area: ActionBars, Auras, CastBars, UnitFrames, SwingTimer, Threat,
Timeline and DamageMeter (`src/Units/`). Written on wowlua 0.9.6 and fixes
after it on `m9-coverage-stale-handle` (decisions T247 to T249, see below).

None of these had tests. They run over the engine's units, threat lists,
damage meter, nameplates-free HUD and Blizzard's own frames (stood down
by the modules). The encounter timeline's calls are a stand-in (see
below); everything else is the engine's.

## Test files

| Source | Test file | Tests | Lines |
|---|---|---|---|
| ActionBars | `Units/ActionBars.test.wowlua`, `Units/ActionBars/Totems.test.wowlua` (a shaman profile, `tests/profiles/shaman.json`) | 14 | 98.9% |
| Auras | `Units/Auras.test.wowlua` | 10 | 98.6% |
| CastBars | `Units/CastBars.test.wowlua` | 5 | 100% |
| UnitFrames | `Units/UnitFrames.test.wowlua` | 13 | 96.7% |
| SwingTimer | `Units/SwingTimer.test.wowlua` | 7 | 100% |
| Threat | `Units/Threat.test.wowlua` | 13 | 99.3% |
| Timeline | `Units/Timeline.test.wowlua` | 14 | 97.9% |
| DamageMeter | `Units/DamageMeter.test.wowlua` | 9 | 99.3% |

Not run: UnitFrames' combo points above 0 (the engine keeps none:
`GetComboPoints` recorded 0) and its health check's readable branch (your
health is always secret); Auras' enchant row refused in combat (the
engine lets the container move); ActionBars' reputation through the old
`GetWatchedFactionInfo`; Timeline's raid-assistant refusal and a client
without the timeline; DamageMeter on a client without `C_DamageMeter`.

## Bugs found

- **Fixed: your buffs ran into the encounter timeline.** Growing left (the
  default), the row only got shorter when the timeline's right edge was
  past the buffs' own, which can't happen beside the screen's edge, so 16
  to a row went on under the timeline at 1920 wide. It measures from the
  timeline's right edge now.

Not fixed, noted:

- **The frames dim out of combat even when you're hurt.** Your own
  health is secret to addons on Forever (`UnitHealth`,
  `UnitHealthPercent`), so "at full health" can't be told; the fallback
  rests on combat alone, as its comment says. A curve-driven alpha
  (`UnitHealthPercent` with a step curve into `SetAlpha`) could do it,
  but not with the animated fade. A design question.

## VM / wowlua findings (new)

Fixed in wowlua (after 0.9.6):

- **T247: only the player could be on a threat list.** Tests faked
  `UnitThreatSituation` and `UnitDetailedThreatSituation` for the group,
  and a faked global runs Blizzard's unit frames tainted (they then fail
  on the group's secret health). `mob:setThreat(value, who)` puts a group
  member or pet on the list; each unit's status and percentages follow
  (the creature's target holds it; someone above is about to pull), and
  each change is told.
- **T248: a spell learned from a trainer stayed unknown.**
  `IsPlayerSpell` and `C_SpellBook.IsSpellKnown` answer true for it now
  (Threat's test teaches a priest Fade).
- **T249: a member logging out sent no `UNIT_CONNECTION`.** Only the
  roster update came; Auras dims an offline target's auras on the
  documented event. A probe for its order is noted in wowlua.

Not fixed, noted:

- **A stubbed global runs Blizzard's code tainted** (as in Nameplates):
  prefer the engine's own state (`mob:setThreat`), a module's own API
  table, or SuuUI's stand-in tables (`/UI/WeaponEnchants`' `G`).
- **Forever's encounter timeline is off** (`IsFeatureAvailable()` false)
  and whether an addon's `AddScriptEvent` still works there is unknown:
  the engine answers 0 and an empty list (unrecorded), so Timeline's test
  stands in for the calls. A probe is noted in wowlua's `PROBES.md`; if
  the game refuses it too, SuuUI's pull countdown never shows on the
  timeline (its alert still counts).
- **`mock.advanceTime` runs no frames**: animations (Motion's fades)
  need `mock.advanceFrames`.
