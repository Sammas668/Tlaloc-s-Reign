# Tlaloc's Reign — Development Roadmap

Last updated: 2026-06-21  
Current milestone: Patch 8A / v0.47.5 — Architecture Stabilisation Baseline

This roadmap defines the development order from the current Godot systems prototype toward Prototype 0 Vertical Slice. It is intended to keep future coding work focused, prevent scope drift, and stop old or removed mechanics from being accidentally reintroduced.

## 1. Current strategic read

Tlaloc's Reign is no longer just a screen mock-up. It is a systems prototype with:

- a live market and barter trade interface
- estate and market stockpiles
- building and production data
- housing and labour systems
- palace tabs and dedication-route hooks
- prestige ledger and Palace -> Prestige tab
- Flower Wars reports and prestige logic
- warband roster / skill-web UI
- shrine/religion UI and extracted religion state holder
- rival identities and procurement design
- a smaller active gameplay coordinator over the base game screen
- extracted Palace, Barracks and Shrine screen controllers

The main risk is no longer the old giant wrapper alone. The main risk is now state ownership, turn ownership, duplicated rules and documentation drift.

## 2. Roadmap principles

### Resolve architecture debt before adding more gameplay

The project has enough systems that more features would now increase risk unless the structure is stabilised first.

### Build readability before more complexity

The player must understand what changed, why it changed and what pressure is coming next.

### Keep systems connected

Market, prestige, palace, Flower Wars, religion, rivals, population and estate development should not become separate test panels.

### Avoid reviving removed mechanics

Do not reintroduce:

- abstract Wealth as a normal MVP currency
- generic local stability as an unfocused meter
- old artisan/ritual rival identities
- tactical battlefield combat
- new gods beyond the four-god model

### Extract architecture gradually

Do not attempt a huge rewrite. Move ownership in narrow, testable patches.

## 3. Current structure after UI extraction

```text
Scripts/ui/
  GameScreen.gd
  GameScreenMarketOverviewPatch.gd

Scripts/ui/screens/
  PalaceScreenController.gd
  BarracksScreenController.gd
  ShrineScreenController.gd

Scripts/ui/widgets/
  FlowerWarEventOverlay.gd
  WarbandSkillWebCanvas.gd
  CalendarPacingController.gd

Scripts/Systems/
  MarketPricingRules.gd
  MarketTradeSystem.gd
  MarketEconomySystem.gd
  TurnResolutionSystem.gd
  PrestigeSystem.gd
  PalaceSystem.gd
  PalacePresentationRules.gd
  FlowerWarSystem.gd
  WarbandSystem.gd
  ReligionStateSystem.gd
  ShrineRitualRules.gd
  RivalSystem.gd
```

`GameScreenMarketOverviewPatch.gd` should remain as a coordinator only. New screen-sized UI belongs in `Scripts/ui/screens/`. Reusable UI pieces belong in `Scripts/ui/widgets/`. Gameplay rules belong in `Scripts/Systems/`.

## 4. Version roadmap overview

| Version / Patch | Milestone | Main goal |
|---|---|---|
| v0.42 | Repository Baseline & Cleanup | Historical baseline; superseded by current architecture patches. |
| v0.43 | Early extraction / Turn Summary target | Historical/partial; Structured Veintena Summary still remains a future target. |
| v0.44 | Rival Prototype target | Still future gameplay target. |
| v0.45 | Palace / Flower War / Warband extraction period | Partially implemented across later patches. |
| v0.46 | Screen extraction / UI stabilisation period | Partially implemented. |
| v0.47.5 / Patch 8A | Architecture Stabilisation Baseline | Current truth pass and cleanup plan. |
| Patch 8B | Shared Doctrine Rules | Create one doctrine source of truth. |
| Patch 8C | UI Screen Context | Reduce host-coupled controller bridges. |
| Patch 8D | Religion Runtime Ownership | Move religion state ownership out of UI controller territory. |
| Patch 8E | CampaignState Scaffold | Begin proper live campaign state ownership. |
| Patch 8F | Turn / Calendar Ownership | Move turn and calendar resolution out of UI wrapper. |
| Patch 8G | Controller Audit / Dead-Code Cleanup | Clean leftovers after architecture migration. |
| Patch 9 | Structured Veintena Results Summary | Explain end-turn changes clearly. |
| Patch 10 | Rival Prototype 1 | Make rivals visible economic competitors. |
| Patch 11 | Warband Progression Connection | Connect XP, injuries and skill web effects to outcomes. |
| Patch 12 | Religion Loop Consolidation | Make offerings, favour and shrine upkeep a real loop. |
| Patch 13 | One Full Ritual Year Playable | Play 18 Veintenas + Nemontemi coherently. |
| Patch 14 | Balance and Readability Pass | Tune economy, prestige, rivals and UI feedback. |
| Patch 15 | Prototype 0 Vertical Slice | Deliver a coherent playable prototype year. |

## 5. Patch 8A — Architecture Truth Pass

### Goal

Update the repo truth before more code is added.

### Status

Current patch.

### Deliverables

- Update `Docs/CURRENT_BASELINE.md`.
- Update `Docs/ROADMAP.md`.
- Update `Docs/CHANGELOG.md`.
- Add `Docs/Architecture/Clean_Architecture_Baseline.md`.

### Records

- Current milestone is no longer v0.42.
- Wrapper is now coordinator-only in intent.
- Palace/Barracks/Shrine controllers exist.
- Religion live state has been extracted but still needs runtime ownership cleanup.
- `TRGameState` is the current runtime facade.
- `GameState` is the legacy/older path.
- Next architecture targets are CampaignState, turn ownership, shared doctrine rules and controller context.

## 6. Patch 8B — Shared Doctrine Rules

### Goal

Stop Flower War doctrine stats from drifting between systems.

### Required work

Create:

```text
Scripts/Systems/WarDoctrineRules.gd
```

Move doctrine definitions there:

| Doctrine | Offence | Defence | Main identity |
|---|---:|---:|---|
| Unspecialised | 1.0 | 1.0 | Baseline |
| Eagle | 1.0 | 1.2 | Captives / capture reliability |
| Jaguar | 1.3 | 1.0 | Prestige / shock power |
| Otomi | 0.8 | 1.5 | Survival / defensive veterans |
| Coyote | 1.4 | 0.5 | Loot / risky aggression |

Then `FlowerWarSystem.gd`, `WarbandSystem.gd`, and any UI fallback should read from the same rules file.

### Success criteria

- There is one source of truth for doctrine values.
- Search for duplicate doctrine dictionaries does not reveal separate combat values.
- Otomi remains 0.8 / 1.5.

## 7. Patch 8C — UI Screen Context

### Goal

Reduce host-coupled controller bridges.

### Required work

Create:

```text
Scripts/ui/UIScreenContext.gd
```

It should carry common screen dependencies:

- host
- state access
- content root
- content text
- dynamic view host
- notification list
- refresh callbacks
- shared formatting access where needed

Then gradually update `PalaceScreenController.gd`, `BarracksScreenController.gd` and `ShrineScreenController.gd` to accept a context object.

### Success criteria

- Controllers no longer need long parameter lists.
- Controllers are still lightweight and testable.
- No gameplay rule logic moves into UI context.

## 8. Patch 8D — Religion Runtime Ownership

### Goal

Move religion state ownership out of UI controller territory.

### Required work

`ReligionStateSystem.gd` should be owned by runtime state through `TRGameState` for now, and later by `CampaignState`.

The Shrine screen should call public runtime methods such as:

- get religion summary
- perform ritual
- upgrade shrine
- sacrifice for prestige
- apply favour decay
- reset ritual capacity

### Success criteria

- `ShrineScreenController.gd` does not own the religion-state instance.
- Religion state survives screen changes reliably.
- Religion is ready for save/load inclusion later.

## 9. Patch 8E — CampaignState Scaffold

### Goal

Begin separating live campaign data from `TRGameState`.

### Required work

Create or strengthen:

```text
Scripts/State/CampaignState.gd
```

Initial containers:

- calendar
- stockpiles
- population
- buildings
- housing
- market
- palace
- prestige
- religion
- warbands
- rivals
- last_report
- last_turn_summary

### Success criteria

- `TRGameState` can keep acting as public facade.
- Campaign data has a clear destination.
- No massive data migration is attempted in one patch.

## 10. Patch 8F — Turn / Calendar Ownership

### Goal

Move calendar and turn resolution out of `GameScreenMarketOverviewPatch.gd`.

### Required direction

```text
Advance button
  -> TRGameState.advance_turn()
    -> TurnResolutionSystem
      -> CampaignState / systems
```

The UI should display results, not own the turn.

### Success criteria

- `_calendar_period`, `_ritual_year`, `_resolve_veintena` and `_resolve_nemontemi` no longer live as wrapper-owned gameplay state.
- `last_report` still works.
- Structured `last_turn_summary` is now possible cleanly.

## 11. Patch 8G — Controller Audit and Dead-Code Cleanup

### Goal

Finish the architecture-stabilisation pass.

### Required work

- Remove stale comments.
- Remove unused wrapper methods.
- Remove duplicate constants.
- Check all extracted controllers compile.
- Check no screen controller owns gameplay state.
- Check no system depends on UI nodes.
- Check wrapper is only a coordinator.

### Success criteria

The project has a clean enough architecture baseline to continue gameplay implementation.

## 12. Patch 9 — Structured Veintena Results Summary

### Goal

After the player advances a Veintena, show a readable report explaining what changed and why.

### Required sections

- Production
- Upkeep
- Buildings
- Market
- Religion
- Palace
- Prestige
- Rivals
- Warnings

### Success criteria

- The player sees a summary after advancing a Veintena.
- Prestige gains/losses are explained.
- Major stockpile changes are explained.
- Blocked buildings or failed upkeep are visible.
- Rival movement can be added without rebuilding the UI.

## 13. Patch 10 — Rival Prototype 1

### Goal

Make the three rival houses visible economic actors.

### Required mechanics

- Rival stockpiles.
- Fixed build orders.
- Procurement caps.
- Personality hoards.
- True-surplus selling.
- Minor support steps when blocked.
- Rival prestige changes with readable reasons.
- Rival reports in Veintena Summary.

## 14. Patch 11 — Warband Progression Connection

### Goal

Make persistent warbands matter mechanically and emotionally.

### Required work

- Warband XP gain after Flower Wars.
- Rank thresholds.
- Injury and recovery logic.
- Skill web node effects applied to combat/rewards.
- Veteran value.
- Loss reports that make warrior death/injury meaningful.
- Replacement warriors and recovery pressure.

## 15. Patch 12 — Religion / Shrine Loop Consolidation

### Goal

Make offerings, favour and shrine upkeep into a real recurring loop.

### Required work

- Clear favour display per god.
- Predictable favour decay.
- Shrine upgrades modifying favour decay/output.
- Major ritual choice per relevant Veintena.
- Sacrifice UI polish.
- Ritual prestige/favour reporting.
- Religion entries in Veintena Summary.

## 16. Patch 13 — One Full Ritual Year Playable

### Goal

Make 18 Veintenas and Nemontemi playable from start to finish.

### Required work

- Turn loop runs reliably for a full year.
- At least one palace demand cycle.
- At least one Flower War opportunity.
- Rival movement across the year.
- Prestige race updates.
- Nemontemi annual review.
- Carry-forward pressure into next year.

## 17. Patch 14 — Balance and Readability Pass

### Goal

Tune the first-year economy, prestige and pressure after the main loop is visible.

### Required tests

- Can the player pursue a war route in Year 1?
- Can the player pursue a palace/diplomatic route in Year 1?
- Can the player pursue a religion/shrine route in Year 1?
- Is Savvy Trade useful but not dominant?
- Do rivals pressure the market without making it unreadable?
- Do shortages feel meaningful rather than random?
- Are goods values and scarcity multipliers readable?

## 18. Patch 15 — Prototype 0 Vertical Slice

### Goal

Deliver a coherent playable prototype year.

### Prototype 0 should prove

- Estate production works.
- Market trade matters.
- Prestige is readable.
- Palace route matters.
- Rivals visibly compete.
- Flower Wars are usable.
- Religion creates real pressure.
- Veintena results explain what happened.
- The game feels like one connected noble-house strategy game, not separate test systems.

## 19. Post-vertical-slice direction

Only after the vertical slice should the project consider larger expansions such as:

- richer event libraries
- deeper rival plots
- fuller Tezcatlipoca sabotage
- more palace demand variety
- expanded shrine trees
- deeper warband traits
- richer art/audio polish
- save/load hardening
- tutorial/onboarding

The priority before then is not more content. It is making the existing loop coherent, readable and playable.
