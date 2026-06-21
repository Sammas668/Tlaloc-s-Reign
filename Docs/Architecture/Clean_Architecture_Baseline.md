# Tlaloc's Reign — Clean Architecture Baseline

Last updated: 2026-06-21  
Milestone: Patch 8O4F — Post-Mirror Architecture Baseline

This document defines where code belongs after the 8O3 mirror deletion series and the 8O4 post-mirror cleanup sequence.

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
- No old live-state mirror fields should be restored on `TRGameState`.

---

## 2. Active ownership map

| Responsibility | Current owner |
|---|---|
| Public runtime facade | `Scripts/Autoload/TRGameState.gd` |
| Live/save state owner | `Scripts/state/CampaignState.gd` |
| Legacy state forwarder | `Scripts/state/GameState.gd` |
| Active gameplay coordinator | `Scripts/ui/GameScreenMarketOverviewPatch.gd` |
| Turn / Veintena / Nemontemi resolution | `Scripts/Systems/TurnResolutionSystem.gd` |
| State compatibility/audit bridge | `Scripts/Systems/CampaignBridgeSystem.gd` |
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
- provide small compatibility helpers during migration

Not allowed:

- new gameplay rules
- new major screen-sized UI blocks
- mutable religion state ownership
- turn/calendar resolution
- duplicated doctrine values
- market pricing rules
- new rival AI logic
- direct live-state storage

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
- delegate to `CampaignState`
- emit state/turn signals
- provide stable public helper methods for UI and systems

It is not allowed to:

- own duplicated live-state containers
- recreate old live-state mirror fields
- use broad sync calls in read paths
- use property getters/setters for state migration
- become the permanent live-state owner

### `CampaignState.gd`

Current role: live/save campaign data owner.

It owns the authoritative containers for:

- calendar state
- report state
- turn summary state
- static resource/building definitions loaded for the campaign
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
- Flower War reports
- warbands
- rival scaffold state

`CampaignState` should contain data containers, data-shaping helpers and save/load helpers. It should not become a gameplay-rules dumping ground.

### `CampaignBridgeSystem.gd`

Current role: compatibility and diagnostics.

It no longer owns broad `TRGameState <-> CampaignState` syncing.

Allowed:

- return CampaignState handles for old callers
- emit `state_changed` through the runtime facade
- provide diagnostic sync-report text
- retain harmless no-op compatibility hooks until 8O4G proves callers are gone

Not allowed:

- copying live state from `TRGameState` into `CampaignState`
- writing old mirror fields back onto `TRGameState`
- seeding religion/rival state from metadata or old facade fields
- broad sync calls in read paths

### `GameState.gd`

Role: retired legacy forwarder only.

It is not an autoload. Do not target it for new Prototype 0 work.

It may forward old calls to `/root/TRGameState`, but it must not inspect old `TRGameState` fields.

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

8O4C removed metadata seeding and mirror write-back from the religion bridge. New religion work should use CampaignState-backed APIs only.

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

## 11. Rival architecture

`RivalSystem.gd` owns rival identity, pressure-note and placeholder rival-prestige rules.

Rival live data belongs in `CampaignState`:

- `rival_houses`
- `rival_stockpiles`
- `rival_build_progress`
- `rival_action_history`
- `rival_prestige`

8O4D removed old `game_state.get("rival_prestige")` and `game_state.set("rival_prestige", ...)` fallback paths. New rival work should not restore those paths.

---

## 12. Legacy / inactive files

### `Scripts/state/GameState.gd`

Retired forwarder only.

### `Scripts/ui/GameScreenStateDriven.gd`

Legacy / inactive screen shim only.

Do not use these as sources of truth for future coding.

---

## 13. File placement rules

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

## 14. Post-mirror definition of clean

The architecture is post-mirror when:

- `TRGameState` is the public facade only.
- `CampaignState` is the live/save data owner.
- `GameState` is legacy and not an active autoload.
- `GameScreenMarketOverviewPatch` is a coordinator.
- major UI screens are extracted controllers.
- turn resolution is system-owned.
- religion state is CampaignState-backed.
- rival state is CampaignState-backed.
- doctrine values have one source of truth.
- market UI is extracted.
- no live-state compatibility mirrors remain on `TRGameState`.
- no broad `apply_to_game_state()` / `copy_from_game_state()` bridge path remains active.
- remaining compatibility hooks are no-op/direct CampaignState access only.

8O4F records this baseline. 8O4G should verify it with a final grep audit.

---

## 15. Next development target

First complete:

```text
8O4G — Final grep audit: state.get/state.set/mirror/legacy/fallback
```

Then proceed to:

```text
Patch 9 — Structured Veintena Results Summary
```

Patch 9 should display `CampaignState.last_turn_summary` / runtime turn-summary output in a readable player-facing panel after turn advancement.
