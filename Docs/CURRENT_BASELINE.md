# Tlaloc's Reign — Current Baseline

Last updated: 2026-06-21  
Current milestone: Patch 8A / v0.47.5 — Architecture Stabilisation Baseline

This file records the current implementation baseline for Tlaloc's Reign so future coding work does not accidentally revive old systems, target inactive files, or use outdated assumptions from earlier prototype stages.

## 1. Active project entry points

- Godot project: `project.godot`
- Main scene: `res://Scenes/Main/MainMenu.tscn`
- Main gameplay scene: `res://Scenes/Main/GameScreen.tscn`
- Active gameplay coordinator/wrapper: `res://Scripts/ui/GameScreenMarketOverviewPatch.gd`
- Base gameplay screen: `res://Scripts/ui/GameScreen.gd`

`GameScreenMarketOverviewPatch.gd` remains the active gameplay UI coordinator. It should be treated as a coordinator, not as the permanent home for new gameplay rules.

## 2. Runtime state baseline

There are two state paths in the project.

### `Scripts/Autoload/TRGameState.gd`

Current role: active runtime facade and practical gameplay API.

For Prototype 0 work, treat `TRGameState.gd` as the active runtime facade. It exposes the public methods used by UI screens and coordinates the extracted systems. It still contains architecture debt because it remains close to live state ownership and compatibility wrappers.

### `Scripts/state/GameState.gd`

Current role: legacy / older architecture path.

`GameState.gd` should not be assumed to contain the full live prototype rules. It remains present for compatibility and older project structure, but future implementation should not add new Prototype 0 gameplay to this file unless a deliberate migration plan says otherwise.

### Future state target

The intended long-term direction is:

```text
UI screens/widgets
  -> TRGameState public runtime facade
    -> CampaignState live campaign data
    -> Systems for rule calculation and mutation
```

## 3. Active UI architecture

The project has moved beyond the old single giant wrapper model.

Current UI structure:

```text
Scripts/ui/
  GameScreen.gd
  GameScreenMarketOverviewPatch.gd       active coordinator/wrapper

Scripts/ui/screens/
  PalaceScreenController.gd              Palace / Prestige / Divine Seat / Authority / Court Needs UI
  BarracksScreenController.gd            Barracks / Warbands / Flower War bridge UI
  ShrineScreenController.gd              Shrine / Religion UI

Scripts/ui/widgets/
  FlowerWarEventOverlay.gd               full-screen Flower War event modal
  WarbandSkillWebCanvas.gd               Warband skill web canvas
  CalendarPacingController.gd            Veintena card/calendar pacing helper
```

`GameScreenMarketOverviewPatch.gd` is now coordinator-only in principle. It may route screens, connect signals, open extracted controllers/widgets, and bridge to backend systems. It should not absorb new rules or major UI blocks.

## 4. Extracted rule / presentation systems

Current extracted systems include:

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
```

`ReligionStateSystem.gd` owns mutable Prototype 0 religion state that previously lived in the UI wrapper: divine favour, shrine levels, shrine upgrades, ritual capacity and recent ritual/offering report lines.

Important unresolved issue: religion state is extracted, but runtime ownership still needs cleanup. It should be owned through `TRGameState` / future `CampaignState`, not by a UI screen controller.

## 5. Design guardrails

These are current baseline rules and should not be casually changed.

- No abstract Wealth resource in the MVP economy.
- Prestige is score / public recognition only. It is earned or lost, never spent.
- Do not reintroduce a generic local stability meter casually.
- Flower Wars are capitalised as `Flower Wars`.
- Rivals are `War Rival`, `Cunning Rival` and `Diplomatic Rival`, not old artisan/ritual labels.
- The player starts from a relatively blank-slate estate, mainly maize and slight cacao surplus, not full mature production chains.
- Each estate has its own stockpiles.
- The central marketplace is shared, but it does not replace estate storage.
- All goods should flow through estate stockpiles and the central marketplace.
- Do not add gods beyond Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl for Prototype 0.
- Do not turn Flower Wars into tactical battlefield combat.
- Do not turn rivals into full hidden duplicate player estates before the MVP needs it.

## 6. Canonical balance corrections

### Market scarcity floor

The canonical scarcity multiplier floor is:

```text
0.50
```

Abundant goods may fall to half base value. Do not restore the older 0.75 scarcity floor.

### Flower War doctrine baseline

| Doctrine | Offence | Defence | Main identity |
|---|---:|---:|---|
| Unspecialised | 1.0 | 1.0 | Baseline. |
| Eagle | 1.0 | 1.2 | Captives / capture reliability. |
| Jaguar | 1.3 | 1.0 | Prestige / shock power. |
| Otomi | 0.8 | 1.5 | Survival / defensive veterans. |
| Coyote | 1.4 | 0.5 | Loot / risky aggression. |

Otomi deliberately trades offence for survival. This is intentional.

## 7. Implemented or partially implemented systems

### Market / Trade

Current status: implemented enough for prototype use.

- Market overview, goods ledger, village economy and trade-basket UI exist.
- Trade Basket is barter-based.
- Positive surplus barter value is lost as inefficiency; it is not stored as Wealth or credit.
- Savvy Trade Prestige exists: selling above base value or buying below base value can award economic prestige.
- Market screen previews Savvy Trade Prestige before accepting trade.
- Remaining architecture target: consider extracting market/trade UI into a `MarketScreenController.gd` if the market UI grows again.

### Prestige

Current status: active but still improving.

- Player prestige exists.
- Prestige history / ledger records source, amount, detail, Veintena and context.
- Palace -> Prestige tab exists through `PalaceScreenController.gd`.
- Prestige is never spent.
- Prestige sources currently include Savvy Trade and Flower Wars, with hooks for court needs, ritual sacrifice and future sources.

### Palace

Current status: UI extracted, route logic partially implemented.

- Palace screen exists through `PalaceScreenController.gd`.
- Palace -> Prestige, Divine Seat, Authority and Court Needs exist.
- Palace presentation rules live in `PalacePresentationRules.gd`.
- Palace route / structure logic lives in `PalaceSystem.gd`.

Current palace dedication powers:

| God | Palace authority |
|---|---|
| Tlaloc | Deeper calendar / natural-event forecast information. |
| Huitzilopochtli | Formal Flower Wars authority / war route. |
| Tezcatlipoca | Scarcity, intrigue and market-pressure authority. |
| Quetzalcoatl | Legitimacy, recognition and palace-performance authority. |

### Flower Wars / Warbands

Current status: partially implemented and structurally improved.

- Flower War rules live in `FlowerWarSystem.gd`.
- Warband public API and skill-web rules live in `WarbandSystem.gd`.
- Warband Skill Web canvas lives in `WarbandSkillWebCanvas.gd`.
- Flower War event modal lives in `FlowerWarEventOverlay.gd`.
- Barracks / Warband UI lives in `BarracksScreenController.gd`.
- Warband skill effects are not yet fully connected to Flower War resolution.

Remaining architecture target: create shared `WarDoctrineRules.gd` so `FlowerWarSystem.gd` and `WarbandSystem.gd` do not duplicate doctrine data.

### Religion / Shrines

Current status: UI extracted and state partly extracted.

- Shrine / Religion UI lives in `ShrineScreenController.gd`.
- Shrine static rules live in `ShrineRitualRules.gd`.
- Mutable religion state lives in `ReligionStateSystem.gd`.
- The current gods are only Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl.

Remaining architecture target: move religion runtime ownership into `TRGameState` / future `CampaignState` so UI controllers do not own live campaign state.

### Housing / Labour / Buildings

Current status: partially implemented.

- Housing view exists.
- Active / mothballed housing concepts exist.
- Population groups and labour assignment are represented through runtime state.
- Building data is JSON-driven.
- Future work should keep building rules data-driven where possible.

### Rival Houses

Current status: design-defined and partially represented, but not yet active enough.

Current rival identities:

| Rival | Patron god | Role |
|---|---|---|
| War Rival | Huitzilopochtli | Martial prestige, Flower Wars, captives, force, weapons and warrior capacity. |
| Cunning Rival | Tezcatlipoca | Market leverage, scarcity pressure, practical bottlenecks and future sabotage. |
| Diplomatic Rival | Quetzalcoatl | Legitimacy, palace influence, tribute goods, fine textiles and cacao. |

Current rival build-order design:

| Rival | Build order |
|---|---|
| War Rival | Weapon Yard -> Warrior House -> Captive Holding Pen -> Huitzilopochtli Shrine Support |
| Cunning Rival | Storehouse / Market Storage -> Advanced Tool Workshop -> Cloth Workshop -> Cacao Access |
| Diplomatic Rival | Fine Textile House -> Noble Residence -> Cacao Expansion -> Quetzalcoatl Shrine Support |

Rival procurement should use capped buying, true-surplus selling and personality hoards. Rivals should become visible structured economic actors before full AI is attempted.

## 8. Known architecture debt after Patch 8A

### A. State ownership

`TRGameState.gd` is still too broad. It should become a public runtime facade and system coordinator, while live campaign data gradually moves into `CampaignState.gd`.

### B. `GameState.gd` legacy path

`GameState.gd` still exists as the older state path. Do not add new Prototype 0 rules to it unless deliberately migrating.

### C. Religion runtime ownership

Religion state is no longer stored directly in the wrapper, but it still needs to be owned by runtime/campaign state rather than by a UI controller.

### D. Turn/calendar ownership

`GameScreenMarketOverviewPatch.gd` still coordinates calendar period, ritual year and Veintena/Nemontemi resolution. This should move into `TRGameState.advance_turn()` and `TurnResolutionSystem.gd`.

### E. Duplicated doctrine data

Flower War doctrine data is duplicated between `FlowerWarSystem.gd` and `WarbandSystem.gd`. Add `WarDoctrineRules.gd` as the single source of truth.

### F. Controller coupling

The extracted screen controllers call back into the wrapper through host bridge methods. This is acceptable for now, but should be cleaned with a shared UI context object.

## 9. Next architecture targets

Before adding more gameplay, complete this architecture cleanup sequence:

1. Patch 8B — Shared `WarDoctrineRules.gd`.
2. Patch 8C — Shared `UIScreenContext.gd`.
3. Patch 8D — Religion runtime ownership cleanup.
4. Patch 8E — `CampaignState.gd` scaffold.
5. Patch 8F — Move turn/calendar ownership out of the wrapper.
6. Patch 8G — Controller audit and dead-code cleanup.

Only after this should the project move to Structured Veintena Results Summary and Rival Prototype 1.

## 10. Next gameplay target after architecture cleanup

The next gameplay feature remains:

```text
Structured Veintena Results Summary
```

It should show:

- production changes
- population upkeep
- building upkeep / blocked buildings
- market changes
- religion decay / ritual results
- palace effects / court needs
- prestige changes and reasons
- rival movements
- warnings for the next Veintena
