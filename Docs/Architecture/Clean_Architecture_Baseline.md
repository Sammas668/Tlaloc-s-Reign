# Tlaloc's Reign — Clean Architecture Baseline

Last updated: 2026-06-21  
Milestone: Patch 8L / v0.48.0 — Clean Architecture Baseline

This document defines where code belongs after the Patch 8A–8K2 architecture cleanup sequence.

---

## 1. Architectural rule

The project should now follow this dependency direction:

```text
UI screens/widgets
  -> TRGameState public runtime facade
    -> Systems
      -> CampaignState live/save data
```

This means:

- UI displays information and sends commands.
- `TRGameState` exposes public runtime methods.
- Systems calculate rules and mutate state.
- `CampaignState` owns live/save campaign data.
- Legacy files do not receive new gameplay work.

---

## 2. Active ownership map

| Responsibility | Current owner |
|---|---|
| Public runtime facade | `Scripts/Autoload/TRGameState.gd` |
| Live/save state owner | `Scripts/state/CampaignState.gd` |
| Legacy state shim | `Scripts/state/GameState.gd` |
| Active gameplay coordinator | `Scripts/ui/GameScreenMarketOverviewPatch.gd` |
| Turn / Veintena / Nemontemi resolution | `Scripts/Systems/TurnResolutionSystem.gd` |
| CampaignState bridge | `Scripts/Systems/CampaignBridgeSystem.gd` |
| Religion state | `Scripts/Systems/ReligionStateSystem.gd` |
| Shrine / ritual static rules | `Scripts/Systems/ShrineRitualRules.gd` |
| War doctrine rules | `Scripts/Systems/WarDoctrineRules.gd` |
| Palace route logic | `Scripts/Systems/PalaceSystem.gd` |
| Palace presentation helpers | `Scripts/Systems/PalacePresentationRules.gd` |
| Market trade rules | `Scripts/Systems/MarketTradeSystem.gd` |
| Market economy/pricing | `Scripts/Systems/MarketEconomySystem.gd`, `MarketPricingRules.gd` |
| Prestige rules | `Scripts/Systems/PrestigeSystem.gd` |
| Warband rules | `Scripts/Systems/WarbandSystem.gd` |
| Flower War rules | `Scripts/Systems/FlowerWarSystem.gd` |
| Rival scaffold/rules | `Scripts/Systems/RivalSystem.gd` |

---

## 3. UI structure

```text
Scripts/ui/
  GameScreen.gd
  GameScreenMarketOverviewPatch.gd
  UIScreenContext.gd
  GameScreenStateDriven.gd              legacy / inactive shim

Scripts/ui/screens/
  MarketScreenController.gd
  PalaceScreenController.gd
  BarracksScreenController.gd
  ShrineScreenController.gd
  TradeBasketView.gd
  LabourAssignmentView.gd

Scripts/ui/widgets/
  CalendarPacingController.gd
  FlowerWarEventOverlay.gd
  WarbandSkillWebCanvas.gd
```

### `GameScreenMarketOverviewPatch.gd`

Role: active coordinator.

Allowed:

- route screen focus
- instantiate controllers and widgets
- connect UI events
- call `TRGameState`
- provide compatibility helpers during migration

Not allowed:

- new gameplay rules
- new major screen-sized UI blocks
- mutable religion state ownership
- turn/calendar resolution
- duplicated doctrine values
- market pricing rules
- new rival AI logic

### `UIScreenContext.gd`

Role: shared dependency object for extracted screen controllers.

Allowed:

- host access
- runtime state access
- content-root references
- notification panel reference
- shared UI formatting calls

Not allowed:

- owning gameplay state
- storing campaign rules
- replacing `CampaignState`

---

## 4. Runtime state structure

### `TRGameState.gd`

Current role: public runtime facade.

It is allowed to:

- expose gameplay methods to UI
- instantiate/access systems
- bridge to CampaignState
- emit state/turn signals
- hold compatibility mirrors during migration

It should not become the permanent live-state owner.

### `CampaignState.gd`

Current role: live/save campaign data owner.

It owns the authoritative containers for:

- calendar state
- report state
- turn summary state
- stockpiles
- market state
- population/housing/labour state
- palace state
- prestige state
- religion state
- Flower War reports
- warbands
- rival scaffold state

### `CampaignBridgeSystem.gd`

Role: transitional bridge.

It keeps old TRGameState mirrors from breaking active UI while preserving CampaignState-authoritative domains.

Calendar/report state and religion state should not be overwritten by legacy mirrors.

### `GameState.gd`

Role: legacy shim only.

It is not an autoload. Do not target it for new Prototype 0 work.

---

## 5. Turn architecture

`TurnResolutionSystem.gd` owns ordinary Veintena and Nemontemi resolution.

Turn resolution should write to:

```text
CampaignState.last_report
CampaignState.last_turn_summary
CampaignState.current_veintena
CampaignState.calendar_period
CampaignState.ritual_year
```

The active UI should only request turn advancement and display the result.

---

## 6. Religion architecture

`ReligionStateSystem.gd` owns mutable religion state and persists it through:

```text
CampaignState.religion_state
```

`ShrineScreenController.gd` is UI-only.

Authoritative ordinary and Nemontemi divine favour decay belongs in `TurnResolutionSystem.gd`.

Shrine controller decay/reset methods are legacy compatibility bridges only and should not be used by new turn code.

---

## 7. Doctrine architecture

`WarDoctrineRules.gd` is the only source of truth for doctrine values.

Do not duplicate this table anywhere else:

| Doctrine | Offence | Defence |
|---|---:|---:|
| Unspecialised | 1.0 | 1.0 |
| Eagle | 1.0 | 1.2 |
| Jaguar | 1.3 | 1.0 |
| Otomi | 0.8 | 1.5 |
| Coyote | 1.4 | 0.5 |

`FlowerWarSystem.gd`, `WarbandSystem.gd` and UI fallback display should read from `WarDoctrineRules.gd`.

---

## 8. Market architecture

`MarketScreenController.gd` owns market presentation and Trade Basket wiring.

`TradeBasketView.gd` remains the view component.

Market rules should remain backend-owned:

- pricing
- scarcity values
- trade validation
- trade application
- Savvy Trade Prestige

Do not call private methods across controller/view boundaries. Use public methods or backend runtime methods.

---

## 9. Palace architecture

`PalaceScreenController.gd` owns Palace UI.

`PalaceSystem.gd` owns palace state/rules.

`PalacePresentationRules.gd` owns presentation text/formatting helpers.

Palace dedication powers are:

- Tlaloc: deeper calendar / natural-event information
- Huitzilopochtli: Flower Wars authority
- Tezcatlipoca: scarcity / intrigue / market pressure
- Quetzalcoatl: legitimacy / recognition / palace performance

---

## 10. Barracks / Warband / Flower War architecture

`BarracksScreenController.gd` owns Barracks and warband UI.

`WarbandSystem.gd` owns warband data/rules.

`FlowerWarSystem.gd` owns Flower War resolution.

`FlowerWarEventOverlay.gd` owns the full-screen event modal.

`WarbandSkillWebCanvas.gd` owns skill-web presentation.

Doctrine values come from `WarDoctrineRules.gd`.

---

## 11. Legacy / inactive files

### `Scripts/state/GameState.gd`

Legacy compatibility shim only.

### `Scripts/ui/GameScreenStateDriven.gd`

Legacy / inactive screen shim only.

Do not use these as sources of truth for future coding.

---

## 12. File placement rules

### Put new gameplay rules in:

```text
Scripts/Systems/
```

### Put new live/save state containers in:

```text
Scripts/state/CampaignState.gd
```

or helper state classes under `Scripts/state/`.

### Put new screen controllers in:

```text
Scripts/ui/screens/
```

### Put new reusable UI widgets/modals in:

```text
Scripts/ui/widgets/
```

### Do not put new gameplay rules in:

```text
Scripts/ui/GameScreenMarketOverviewPatch.gd
Scripts/state/GameState.gd
Scripts/ui/GameScreenStateDriven.gd
```

---

## 13. Clean enough definition

The architecture is now clean enough to continue gameplay because:

- `TRGameState` is the public facade.
- `CampaignState` is the live/save data owner.
- `GameState` is legacy and not an active autoload.
- `GameScreenMarketOverviewPatch` is a coordinator.
- major UI screens are extracted controllers.
- turn resolution is system-owned.
- religion state is CampaignState-backed.
- doctrine values have one source of truth.
- market UI is extracted.
- docs match the current structure.

Remaining compatibility mirrors are acceptable Prototype 0 migration debt, not blockers.

---

## 14. Next development target

Proceed to:

```text
Patch 9 — Structured Veintena Results Summary
```

This should display `CampaignState.last_turn_summary` / runtime turn-summary output in a readable player-facing panel after turn advancement.
