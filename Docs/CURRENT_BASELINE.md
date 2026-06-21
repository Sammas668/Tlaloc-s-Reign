# Tlaloc's Reign — Current Baseline

Last updated: 2026-06-21  
Current milestone: Patch 8L / v0.48.0 — Clean Architecture Baseline

This document records the current working baseline for the Godot Prototype 0 branch of **Tlaloc's Reign**. It should be treated as the repo truth before starting the next gameplay phase.

Patch 8L follows the architecture cleanup sequence from Patch 8A through Patch 8K2. It records the final clean baseline after UI extraction, CampaignState authority work, religion-state migration, GameState legacy retirement, market extraction and dead-code cleanup.

---

## 1. Active project structure

### Active Godot autoload

```text
TRGameState = res://Scripts/Autoload/TRGameState.gd
```

`TRGameState` is the active Prototype 0 runtime facade.

### Legacy state path

```text
Scripts/state/GameState.gd
```

`GameState.gd` is now a legacy shim only. It is not an active autoload. Do not add Prototype 0 gameplay logic to it.

### Active gameplay UI

```text
Scripts/ui/GameScreen.gd
Scripts/ui/GameScreenMarketOverviewPatch.gd
```

`GameScreenMarketOverviewPatch.gd` is the active screen coordinator. It should route UI, open controllers/widgets, and call runtime systems. It should not own new gameplay rules or major screen blocks.

---

## 2. Clean architecture baseline

The project now follows this intended direction:

```text
UI screens/widgets
  -> TRGameState public runtime facade
    -> Systems
      -> CampaignState live/save data
```

### Core ownership rules

| Area | Owner |
|---|---|
| Public runtime API | `TRGameState.gd` |
| Live/save campaign data | `CampaignState.gd` |
| Legacy compatibility only | `GameState.gd` |
| Turn / Veintena / Nemontemi resolution | `TurnResolutionSystem.gd` |
| Mutable religion state | `ReligionStateSystem.gd`, backed by `CampaignState.religion_state` |
| Flower War / warband doctrine values | `WarDoctrineRules.gd` |
| Market UI | `MarketScreenController.gd` |
| Palace UI | `PalaceScreenController.gd` |
| Barracks / Warband / Flower War bridge UI | `BarracksScreenController.gd` |
| Shrine / Religion UI | `ShrineScreenController.gd` |
| Screen dependency bridge | `UIScreenContext.gd` |
| Full-screen Flower War event modal | `FlowerWarEventOverlay.gd` |
| Warband skill web canvas | `WarbandSkillWebCanvas.gd` |
| Calendar strip / forecast card helper | `CalendarPacingController.gd` |

---

## 3. Active UI controllers and widgets

```text
Scripts/ui/
  GameScreen.gd
  GameScreenMarketOverviewPatch.gd
  UIScreenContext.gd

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

### Screen controller rule

Large screen-specific UI belongs in `Scripts/ui/screens/`.

### Widget rule

Reusable, modal, canvas or helper UI belongs in `Scripts/ui/widgets/`.

### Wrapper rule

`GameScreenMarketOverviewPatch.gd` should remain a coordinator. It should not absorb future market, palace, shrine, warband, rival, religion or turn logic.

---

## 4. Runtime state baseline

### `TRGameState.gd`

`TRGameState` is the public facade. UI should call it for gameplay data and actions.

It still contains some compatibility mirrors while the project migrates fully to `CampaignState`, but those mirrors are not the intended long-term source of truth.

### `CampaignState.gd`

`CampaignState` is the live/save-state owner.

It owns or scaffolds containers for:

- calendar state
- last report
- last turn summary
- resources and buildings
- estate stockpiles
- market stockpiles and demand
- market economy data
- estate buildings
- active housing
- population
- base housing capacity
- labour assignments
- palace state
- prestige state
- religion state
- Flower War report state
- warbands
- rival houses
- rival stockpiles
- rival build progress
- rival action history

### `CampaignBridgeSystem.gd`

`CampaignBridgeSystem` handles transitional `TRGameState <-> CampaignState` syncing.

Calendar/report state and religion state are CampaignState-authoritative. Legacy mirrors exist only so older UI/system paths do not break during migration.

---

## 5. Turn ownership baseline

`TurnResolutionSystem.gd` owns ordinary Veintena and Nemontemi resolution.

The UI advance button should route like this:

```text
Advance button
  -> TRGameState.advance_turn() / advance_veintena()
    -> TurnResolutionSystem.advance_veintena()
      -> CampaignState-backed state
      -> last_report
      -> last_turn_summary
      -> state_changed / turn_advanced signals
```

Current turn-order scaffold:

1. Population upkeep.
2. Housing maintenance.
3. Palace maintenance.
4. Building operations.
5. Warband recovery.
6. Religion decay.
7. Stockpile delta report.
8. Calendar transition.
9. Court-need transition.
10. Turn summary write.
11. Signals.

Nemontemi currently resolves as a special end-year turn with stronger religion decay and hooks for future annual review.

---

## 6. Religion baseline

`ReligionStateSystem.gd` is the mutable religion-state system.

It is backed by:

```text
CampaignState.religion_state
```

It owns:

- divine favour
- shrine levels
- shrine upgrades
- ritual capacity used this Veintena
- recent offering report lines

`ShrineScreenController.gd` is UI-only. It reads and mutates religion through `UIScreenContext` / runtime access. Legacy shrine decay methods may remain as compatibility bridges only; authoritative turn decay belongs in `TurnResolutionSystem.gd`.

---

## 7. War doctrine baseline

`WarDoctrineRules.gd` is the single source of truth for Flower War / Warband doctrine values.

| Doctrine | Offence | Defence | Role |
|---|---:|---:|---|
| Unspecialised | 1.0 | 1.0 | Balanced household warriors. |
| Eagle | 1.0 | 1.2 | Captive specialists and sustained war fighters. |
| Jaguar | 1.3 | 1.0 | Elite offensive warriors. Prestige comes from outcomes, not a hidden doctrine bonus. |
| Otomi | 0.8 | 1.5 | Defensive veterans who trade offence for survival. |
| Coyote | 1.4 | 0.5 | Glass-cannon raiders who favour loot. |

Do not duplicate doctrine values in `FlowerWarSystem`, `WarbandSystem`, UI controllers or docs.

---

## 8. Economy / market baseline

The MVP economy does not use abstract Wealth as a normal currency.

The market remains barter and goods-driven:

- estate stockpiles are separate from market stockpiles
- the market does not replace estate storage
- Trade Basket sells estate free stock and buys from market stock
- positive surplus value in barter is lost as inefficiency
- Savvy Trade Prestige comes from good trade decisions, not passive surplus

Canonical scarcity floor:

```text
0.50
```

Do not restore the older 0.75 floor.

`MarketScreenController.gd` owns market UI routing, Trade Basket wiring, Savvy Trade Prestige preview and market report-card composition. Pricing, validation, trade application and Prestige rules remain in backend state/systems.

---

## 9. Palace baseline

`PalaceScreenController.gd` owns Palace UI.

`PalaceSystem.gd` owns palace structure / route logic.

`PalacePresentationRules.gd` owns palace presentation helpers.

Current palace dedication powers:

| God | Palace authority |
|---|---|
| Tlaloc | Deeper calendar / natural-event forecast information. |
| Huitzilopochtli | Formal Flower Wars authority / war route. |
| Tezcatlipoca | Scarcity, intrigue and market-pressure authority. |
| Quetzalcoatl | Legitimacy, recognition and palace-performance authority. |

Prestige is score / recognition. It is never spent.

---

## 10. Rival baseline

Prototype 0 rivals are:

| Rival | Patron god | Identity |
|---|---|---|
| War Rival | Huitzilopochtli | Martial prestige, weapons, captives, Flower Wars. |
| Cunning Rival | Tezcatlipoca | Scarcity pressure, market leverage, tools, cloth, sabotage later. |
| Diplomatic Rival | Quetzalcoatl | Legitimacy, palace goods, cacao, fine textiles, ruler-facing credibility. |

Rivals are not yet full duplicate player estates. Future Rival Prototype 1 should use stockpiles, fixed build orders, procurement caps, personality hoards and readable turn-summary output.

---

## 11. Removed or rejected mechanics

Do not reintroduce these casually:

- abstract Wealth as normal MVP currency
- generic local stability meter
- old artisan/ritual rival labels
- tactical battlefield Flower Wars
- new gods beyond Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl for Prototype 0
- passive economic Prestige from simply hoarding maize or surplus
- spending Prestige as currency

---

## 12. Legacy / inactive files

### `Scripts/state/GameState.gd`

Legacy shim only. Not active autoload.

### `Scripts/ui/GameScreenStateDriven.gd`

Legacy / inactive screen shim only. The active gameplay screen uses `GameScreenMarketOverviewPatch.gd` and extracted controllers/widgets.

Future work should not target either file unless deliberately removing or archiving legacy compatibility paths.

---

## 13. Current architecture status

The architecture is clean enough to move to the next gameplay phase.

Remaining technical debt is normal prototype migration debt:

- `TRGameState` still has compatibility mirrors.
- Some fallback metadata bridges remain for older local paths.
- Some domains are not fully CampaignState-authoritative yet.
- Save/load still needs hardening after the next gameplay loop becomes visible.

These are not blockers for the next feature.

---

## 14. Next gameplay target

The next major gameplay patch should be:

```text
Patch 9 — Structured Veintena Results Summary
```

It should display the `last_turn_summary` generated by turn resolution and make each turn readable to the player.
