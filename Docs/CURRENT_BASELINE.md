# Tlaloc's Reign — Current Baseline

Last updated: 2026-06-21  
Current milestone: Patch 8O4F — Post-Mirror Architecture Baseline

This document records the current working baseline for the Godot Prototype 0 branch of **Tlaloc's Reign** after the 8O3 mirror-deletion series and the 8O4 post-mirror cleanup sequence.

Treat this as the repo truth for architecture until the final 8O4G grep audit is completed.

---

## 1. Active project structure

### Active Godot autoload

```text
TRGameState = res://Scripts/Autoload/TRGameState.gd
```

`TRGameState` is the active Prototype 0 runtime facade.

It exposes public methods to UI and delegates rules/state work to systems and `CampaignState`.

It is **not** the live-state owner.

### Live/save state owner

```text
Scripts/state/CampaignState.gd
```

`CampaignState` owns live campaign state and save/load-facing state containers.

### Legacy state path

```text
Scripts/state/GameState.gd
```

`GameState.gd` is a retired legacy forwarder only. It is not an active autoload. It must not inspect old `TRGameState` fields or receive new Prototype 0 gameplay logic.

### Active gameplay UI

```text
Scripts/ui/GameScreen.gd
Scripts/ui/GameScreenMarketOverviewPatch.gd
```

`GameScreenMarketOverviewPatch.gd` is the active screen coordinator. It should route UI, open controllers/widgets, and call runtime systems. It should not own new gameplay rules or major screen blocks.

---

## 2. Post-mirror architecture baseline

The project now follows this dependency direction:

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
| Legacy compatibility only | `GameState.gd` as pure forwarder |
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

After 8O3, the old live-state compatibility mirrors were removed from `TRGameState` across:

- calendar/report state
- prestige state
- palace state
- estate and market stockpiles
- estate buildings, housing, population and labour assignments
- warbands and Flower War reports
- static resource/building dictionaries
- market demand/economy data

`TRGameState` may still expose small private helper methods that delegate into `CampaignState` or systems, but it must not own duplicated live data containers.

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

8O4B removed broad `CampaignState -> TRGameState` mirror helpers and old `TRGameState -> CampaignState` import helpers. Future code should use direct CampaignState access methods or TRGameState public facade methods, not mirror sync.

### `CampaignBridgeSystem.gd`

`CampaignBridgeSystem` is no longer a broad state synchroniser.

Its remaining purpose is:

- safe compatibility entry points for old callers
- state-changed signal routing
- diagnostic sync-report text

It must not copy live state from `TRGameState` into `CampaignState`, and it must not write old mirror fields back onto `TRGameState`.

---

## 5. Turn ownership baseline

`TurnResolutionSystem.gd` owns ordinary Veintena and Nemontemi resolution.

The UI advance button should route like this:

```text
Advance button
  -> TRGameState.advance_turn() / advance_veintena()
    -> TurnResolutionSystem.advance_veintena()
      -> CampaignState-backed state
      -> CampaignState.last_report
      -> CampaignState.last_turn_summary
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

`ShrineScreenController.gd` is UI-only. It reads and mutates religion through `UIScreenContext` / runtime access. Authoritative turn decay belongs in `TurnResolutionSystem.gd`.

8O4C removed religion metadata seeding and mirror write-back. Future religion work must not restore metadata-backed state as an authority path.

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

8O4D removed the old rival prestige fallback path through `TRGameState` fields. Rival state should remain CampaignState-direct.

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
- live-state compatibility mirrors on `TRGameState`
- broad sync-from-runtime calls in read paths
- property getters/setters for state access

---

## 12. Legacy / inactive files

### `Scripts/state/GameState.gd`

Retired forwarder only. Not active autoload. It should forward old calls to `/root/TRGameState` where possible, and it must not inspect old runtime fields.

### `Scripts/ui/GameScreenStateDriven.gd`

Legacy / inactive screen shim only. The active gameplay screen uses `GameScreenMarketOverviewPatch.gd` and extracted controllers/widgets.

Future work should not target either file unless deliberately removing or archiving legacy compatibility paths.

---

## 13. Current architecture status

The architecture is now post-mirror and ready for a final grep audit.

Completed cleanup:

- 8O3A-G removed TRGameState live-state mirrors.
- 8O4A removed broad active `apply_to_game_state` usage.
- 8O4B removed CampaignState mirror-to-game-state helpers.
- 8O4C removed religion mirror/fallback paths.
- 8O4D removed rival mirror/fallback paths.
- 8O4E converted legacy `GameState.gd` into a pure forwarder.
- 8O4F updates documentation to match the post-mirror baseline.

Remaining technical debt before resuming gameplay:

- 8O4G final grep audit for `state.get`, `state.set`, `mirror`, `legacy`, `fallback` and stale documentation references.
- Save/load hardening after the next gameplay loop becomes visible.

---

## 14. Next technical target

The next patch should be:

```text
8O4G — Final grep audit: state.get/state.set/mirror/legacy/fallback
```

After that passes, resume gameplay work with:

```text
Patch 9 — Structured Veintena Results Summary
```

Patch 9 should display the `last_turn_summary` generated by turn resolution and make each turn readable to the player.
