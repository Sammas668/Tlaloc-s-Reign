# Tlaloc's Reign — Changelog

This changelog records implementation milestones for the playable Godot prototype.

The project is still in Prototype 0. Version numbers here are development checkpoints, not public release versions.

## v0.42 — Repository Baseline & Cleanup

Status: in progress / local baseline cleanup.

### Added

- Added `CURRENT_BASELINE.md` as the root-level source-of-truth file for the active prototype baseline.
- Added `ROADMAP.md` as the root-level staged development plan.
- Recorded the current active gameplay scene path:
  - `Scenes/Main/GameScreen.tscn`
- Recorded the current active gameplay wrapper:
  - `Scripts/ui/GameScreenMarketOverviewPatch.gd`
- Recorded the current practical runtime state source:
  - `Scripts/Autoload/TRGameState.gd`
- Recorded current design guardrails:
  - no abstract Wealth resource in MVP
  - Prestige is score / public recognition only and is never spent
  - Flower Wars should be capitalised as `Flower Wars`
  - rival houses are War Rival, Cunning Rival and Diplomatic Rival
  - the market does not replace estate stockpiles

### Removed

- Removed temporary Godot scene duplicate:
  - `Scenes/Main/GameScreen.tscn2577238696.tmp`

### Notes

- `TRGameState.gd` remains the practical live gameplay state for current prototype work.
- `GameState.gd` remains the formal autoload in `project.godot`, creating known architecture debt.
- `GameScreenMarketOverviewPatch.gd` remains the active wrapper layer and should not keep absorbing unrelated systems forever.
- Future work should gradually extract rule logic into dedicated systems rather than expanding the wrapper and state singleton indefinitely.

## v0.43 — Structured Veintena Results Summary

Status: planned.

### Target

Create a structured end-of-turn / Veintena Results Summary that explains what changed, why it changed, and what the player should worry about next.

### Planned sections

- Production changes
- Population upkeep
- Building upkeep and blocked buildings
- Market movement
- Prestige changes and reasons
- Palace pressure
- Rival movement
- Warnings for the next Veintena

### Technical goal

Move from loose report strings toward structured turn events that can feed:

- the Veintena Results Summary
- the right-side reports panel
- Palace → Prestige
- future notifications and warnings
- rival movement reports

## v0.44 — Rival Prototype 1

Status: planned.

### Target

Make rival houses visible structured economic actors.

### Planned features

- Rival stockpiles
- Fixed rival build orders
- Procurement caps
- Personality hoards
- True-surplus selling
- Minor support steps when main builds are blocked
- Rival prestige changes with readable reasons
- Rival report lines in the Veintena Summary

## v0.45 — Palace Route Effects Pass

Status: planned.

### Target

Make Palace dedication routes strategically meaningful.

### Route baseline

- Tlaloc: deeper calendar / natural-event forecast information
- Huitzilopochtli: Flower Wars authority / war route
- Tezcatlipoca: scarcity, intrigue and market-pressure authority
- Quetzalcoatl: legitimacy, recognition and palace-performance authority

## v0.46 — Flower Wars / Warband Progression Connection

Status: planned.

### Target

Connect warband persistence and skill-web decisions to Flower War outcomes.

### Planned features

- Warband XP
- Rank thresholds
- Injury and recovery
- Skill-web effects applied to combat
- Veteran loss reporting

## v0.47 — Religion / Shrine Loop Consolidation

Status: planned.

### Target

Make the four-god religious loop readable, costly and connected to prestige, favour and events.

### Planned features

- Clear favour display by god
- Maintenance offerings
- Major rituals
- Sacrifice reporting
- Shrine upgrades affecting decay, capacity or ritual strength

## v0.48 — One Full Ritual Year Playable

Status: planned.

### Target

Make one full year of 18 Veintenas + Nemontemi playable from start to finish.

## v0.49 — Balance and Readability Pass

Status: planned.

### Target

Tune the first playable year after market, rivals, prestige, palace, religion and Flower Wars are all visible.

## v0.50 — Prototype 0 Vertical Slice

Status: planned.

### Target

A coherent playable Prototype 0 where the player can understand and complete a full pressure cycle.

### Success criteria

- Estate production works.
- Market trade matters.
- Prestige is readable.
- Palace route matters.
- Rival houses visibly compete.
- Flower Wars are usable.
- Religion has real pressure.
- Veintena results explain what happened.
- The game feels like a connected prototype, not separate test systems.
