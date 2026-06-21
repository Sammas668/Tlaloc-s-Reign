# Tlaloc's Reign — Clean Architecture Baseline

Last updated: 2026-06-21  
Milestone: Patch 8A / v0.47.5 — Architecture Stabilisation Baseline

This document defines the intended clean architecture for Tlaloc's Reign after the UI extraction patches and before the next gameplay implementation phase.

It should be used as the architectural source of truth when deciding where new code belongs.

## 1. Current architecture goal

The project should move toward this rule:

```text
UI displays and sends commands.
TRGameState exposes the public gameplay API.
CampaignState owns live campaign data.
Systems calculate and mutate state.
```

The active wrapper should coordinate the screen, not own systems.

## 2. Target dependency direction

Allowed dependency direction:

```text
UI screens/widgets
  -> TRGameState public methods / UI context
    -> Systems
      -> CampaignState / state dictionaries
```

Avoid this direction:

```text
Systems -> UI nodes
Screen controllers -> hidden gameplay state ownership
Widgets -> direct campaign mutation without state facade
Random UI helpers -> duplicate rule constants
```

## 3. Current UI structure

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
```

### `GameScreenMarketOverviewPatch.gd`

Role: active coordinator/wrapper.

Allowed responsibilities:

- route main screen focus and location changes
- instantiate screen controllers
- instantiate modal/event widgets
- bridge existing UI signals
- call public runtime methods
- maintain temporary compatibility helpers during migration

Not allowed responsibilities:

- new gameplay rules
- new major screen UI blocks
- live campaign-state ownership
- duplicate balance constants where a system/rules file exists

### Screen controllers

Screen controllers own large UI composition for a screen area.

Current controllers:

- `PalaceScreenController.gd`
- `BarracksScreenController.gd`
- `ShrineScreenController.gd`

They may build UI panels, connect buttons and ask the runtime state for data. They should not become gameplay state owners.

### Widgets

Widgets are reusable or modal UI pieces.

Current widgets:

- `FlowerWarEventOverlay.gd`
- `WarbandSkillWebCanvas.gd`
- `CalendarPacingController.gd`

Widgets should not own strategic rules. They should display data and emit or call clearly routed actions.

## 4. Runtime state structure

### `TRGameState.gd`

Current role: active runtime facade and compatibility API.

Near-term responsibilities:

- expose public gameplay methods to UI
- coordinate systems
- hold temporary live state until CampaignState migration
- provide compatibility methods for existing screens

Long-term responsibilities:

- facade / coordinator only
- delegate live data to CampaignState
- delegate rule logic to systems

### `GameState.gd`

Current role: legacy / older architecture path.

Rules:

- do not add new Prototype 0 gameplay here
- do not assume it is the active gameplay source of truth
- later either remove it, migrate it, or clearly mark it inactive

### `CampaignState.gd`

Target role: live campaign data owner.

Planned containers:

```text
calendar
stockpiles
population
buildings
housing
market
palace
prestige
religion
warbands
rivals
last_report
last_turn_summary
```

Migration should be incremental. Do not move all live data in one patch.

## 5. Systems structure

Systems should own rules, calculations and state mutation helpers.

Current or expected systems:

```text
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
  WarDoctrineRules.gd           planned
```

### Rules systems

Rules systems contain static balance/presentation logic.

Examples:

- `MarketPricingRules.gd`
- `ShrineRitualRules.gd`
- `PalacePresentationRules.gd`
- planned `WarDoctrineRules.gd`

### Runtime systems

Runtime systems calculate and mutate campaign data through the runtime state.

Examples:

- `MarketTradeSystem.gd`
- `TurnResolutionSystem.gd`
- `PrestigeSystem.gd`
- `PalaceSystem.gd`
- `FlowerWarSystem.gd`
- `WarbandSystem.gd`
- `RivalSystem.gd`

### State-holder systems

`ReligionStateSystem.gd` currently holds mutable religion state. This is better than UI ownership, but still needs runtime ownership cleanup. It should be owned by `TRGameState` / future `CampaignState`, not by `ShrineScreenController.gd`.

## 6. Known architecture debt

### A. Shared doctrine rules missing

Problem:

`FlowerWarSystem.gd` and `WarbandSystem.gd` both know doctrine values.

Fix:

Create `WarDoctrineRules.gd` and make both systems read from it.

### B. Controller context missing

Problem:

Extracted controllers call back into the wrapper through repeated host bridge methods.

Fix:

Create `UIScreenContext.gd` to pass common dependencies.

### C. Religion state ownership

Problem:

Religion state is extracted, but not yet owned by runtime/campaign state.

Fix:

Move `ReligionStateSystem` ownership to `TRGameState` first, and later into `CampaignState`.

### D. CampaignState not yet active

Problem:

`TRGameState.gd` still owns too much live data.

Fix:

Add `CampaignState.gd` scaffold and migrate one data area at a time.

### E. Turn/calendar ownership

Problem:

The UI wrapper still owns turn/calendar bridge state and loose turn report flow.

Fix:

Move turn advancement to:

```text
UI button -> TRGameState.advance_turn() -> TurnResolutionSystem -> CampaignState/systems
```

### F. Documentation drift

Problem:

Older docs still described the project as v0.42.

Fix:

Patch 8A updates the source-of-truth docs.

## 7. File placement rules

### Put new gameplay rule code in:

```text
Scripts/Systems/
```

### Put new screen-sized UI controllers in:

```text
Scripts/ui/screens/
```

### Put reusable widgets and modal panels in:

```text
Scripts/ui/widgets/
```

### Put live campaign data in:

```text
Scripts/State/CampaignState.gd
```

or temporarily behind `TRGameState` until migration.

### Do not put new gameplay rules in:

```text
Scripts/ui/GameScreenMarketOverviewPatch.gd
```

### Do not put new Prototype 0 implementation into:

```text
Scripts/state/GameState.gd
```

unless a deliberate migration plan says so.

## 8. Clean architecture patch sequence

### Patch 8B — Shared Doctrine Rules

Create one source of truth for Flower War doctrine values.

### Patch 8C — UI Screen Context

Create a shared context object for extracted screen controllers.

### Patch 8D — Religion Runtime Ownership

Move religion state ownership behind `TRGameState` / runtime state.

### Patch 8E — CampaignState Scaffold

Create the future live-state owner and begin incremental migration.

### Patch 8F — Turn / Calendar Ownership

Move turn advancement and calendar state out of the UI wrapper.

### Patch 8G — Controller Audit and Dead-Code Cleanup

Clean stale comments, duplicate constants and unused compatibility helpers.

## 9. Definition of clean enough to continue gameplay

The architecture is clean enough to continue gameplay when:

- `GameScreenMarketOverviewPatch.gd` is coordinator-only.
- Doctrine data has one source of truth.
- Screen controllers use a shared context or clearly limited host bridge.
- Religion state is not owned by the Shrine UI controller.
- Calendar/turn advancement is owned by runtime systems, not UI.
- `CampaignState.gd` exists as the future live-state home.
- Docs match the actual project.
- The project opens and the main screens still work.

After that, the next gameplay feature should be Structured Veintena Results Summary.
