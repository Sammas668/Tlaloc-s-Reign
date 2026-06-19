# Tlaloc's Reign — Current Baseline

Last updated: 2026-06-19  
Milestone: v0.42 — Repository Baseline & Cleanup

This file records the current implementation baseline for Tlaloc's Reign so future coding work does not accidentally revive old systems, target inactive files, or invent mechanics that have already been removed.

## 1. Active project entry points

- Godot project: `project.godot`
- Main scene: `res://Scenes/Main/MainMenu.tscn`
- Main gameplay scene: `res://Scenes/Main/GameScreen.tscn`
- Active gameplay screen script: `res://Scripts/ui/GameScreenMarketOverviewPatch.gd`
- Base gameplay screen script: `res://Scripts/ui/GameScreen.gd`

`GameScreen.tscn` currently uses `GameScreenMarketOverviewPatch.gd`. Treat the wrapper as the active gameplay UI layer for current prototype work.

## 2. Runtime state baseline

There are currently two state paths in the repository.

### `Scripts/state/GameState.gd`

- Registered as the formal `GameState` autoload in `project.godot`.
- Represents the older cleaner modular architecture path.
- Should not be assumed to contain the full live prototype rules.

### `Scripts/Autoload/TRGameState.gd`

- Contains most of the live prototype gameplay state and rules.
- Used by the current screen path through wrapper/base-screen lookup and local fallback behaviour.
- Holds current practical systems for stockpiles, population, labour, buildings, housing, market state, palace state, prestige, Flower Wars, religion hooks and rival placeholders.

For current development, treat `TRGameState.gd` as the practical gameplay source of truth, while recognising this as architecture debt.

## 3. Active UI model

The active screen model is still the Estate Screen + Secondary Management Layer model.

Main bottom navigation areas:

- Estate
- Production / Estate Land
- Storehouse
- Market
- Housing
- Shrines
- Warriors / Barracks
- Palace
- Rivals

Current active Palace top tabs:

- Overview
- Prestige
- Divine Seat
- Authority
- Court Needs

Current active Market top tabs:

- Overview
- Goods
- Village Economy
- Trade
- Rivals
- Reports

## 4. Canonical design source documents

Use these as the design baseline unless deliberately superseded:

- `Tlalocs_Reign_Master_GDD_v1_FINAL_MERGED_REVISED_flower_wars_capitalisation.docx`
- `Tlalocs_Reign_Prototype_0_Variables_Register_v14_Rival_Procurement_Support_Pass.docx`
- `Tlalocs_Reign_Prototype_0_Balance_Baseline_v0_12_Rival_Procurement_Support_Pass.xlsx`
- `Flower_Wars_v0_5_1_Jaguar_Defence_1_0.xlsx`
- `Tlalocs_Reign_Production_Route_Saturation_Test_v0_21_Wood_Value_Correction.xlsx`

## 5. Design guardrails

These are current baseline rules and should not be casually changed.

- No abstract Wealth resource in the MVP economy.
- Prestige is score / public recognition only. It is earned or lost, never spent.
- Do not reintroduce a generic local stability meter casually.
- Flower Wars are capitalised as `Flower Wars`.
- Rivals are `War Rival`, `Cunning Rival` and `Diplomatic Rival`, not old artisan/ritual labels.
- The player starts from a relatively blank-slate estate, mainly maize and slight cacao surplus, not full production chains.
- Each estate has its own stockpiles.
- The central marketplace is shared, but it does not replace estate storage.
- All goods should flow through estate stockpiles and the central marketplace.
- Do not add gods beyond Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl for Prototype 0.
- Do not turn Flower Wars into tactical battlefield combat.
- Do not turn rivals into full hidden duplicate player estates before the MVP needs it.

## 6. Implemented or partially implemented systems

### Market / Trade

Current status: implemented enough for prototype use.

- Market overview, goods ledger, village economy and trade-basket UI exist.
- Trade Basket is barter-based.
- Positive surplus barter value is lost as inefficiency; it is not stored as Wealth or credit.
- Savvy Trade Prestige exists: selling above base value or buying below base value can award economic prestige.
- Market screen previews Savvy Trade Prestige before accepting trade.

### Prestige

Current status: partially implemented but active.

- Player prestige exists in `TRGameState.gd`.
- Prestige history / ledger records source, amount, detail, Veintena and context.
- Palace -> Prestige tab exists in the active wrapper.
- Prestige is never spent.
- Prestige sources currently include at least Savvy Trade and Flower Wars, with hooks for court needs, ritual sacrifice and future sources.

### Palace

Current status: partially implemented.

- Palace screen exists.
- Palace -> Prestige tab exists.
- Palace -> Divine Seat / Authority / Court Needs are active UI areas.
- Palace dedication route logic exists for the four gods.

Current palace dedication powers:

| God | Palace authority |
|---|---|
| Tlaloc | Deeper calendar / natural-event forecast information. |
| Huitzilopochtli | Formal Flower Wars authority / war route. |
| Tezcatlipoca | Scarcity, intrigue and market-pressure authority. |
| Quetzalcoatl | Legitimacy, recognition and palace-performance authority. |

### Flower Wars / Warbands

Current status: partially implemented.

- Flower War reporting and prestige calculations exist.
- Warbands and skill web UI exist in prototype form.
- Warband skill web effects are not yet fully connected to Flower War resolution.
- Future work should connect XP, injuries, veteran value, rank thresholds and skill effects before adding large new war content.

Current doctrine baseline:

| Doctrine | Offence | Defence | Main identity |
|---|---:|---:|---|
| Unspecialised | 1.0 | 1.0 | Baseline. |
| Eagle | 1.0 | 1.2 | Captives / capture reliability. |
| Jaguar | 1.3 | 1.0 | Prestige / shock power. |
| Otomi | 1.0 | 1.5 | Survival / defence. |
| Coyote | 1.4 | 0.5 | Loot / risky aggression. |

### Religion / Shrines

Current status: partially implemented.

- Four-god shrine structure exists.
- Shrine tabs and offering hooks exist in the wrapper.
- The current gods are only Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl.
- Do not add new gods for Prototype 0.

### Housing / Labour / Buildings

Current status: partially implemented.

- Housing view exists.
- Active / mothballed housing concepts exist.
- Population groups and labour assignment are represented in `TRGameState.gd`.
- Building data is JSON-driven.
- Future work should keep building rules data-driven where possible.

### Rival Houses

Current status: design-defined, only partly implemented.

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

Rival procurement rules should use capped buying, true-surplus selling and personality hoards. Rivals should become visible structured economic actors before full AI is attempted.

## 7. Known architecture debt

### Patch-wrapper accumulation

`GameScreenMarketOverviewPatch.gd` has grown into a large wrapper over `GameScreen.gd`. This is acceptable for fast prototyping, but future cleanup should avoid endlessly adding unrelated systems to the wrapper.

Preferred direction:

- Keep wrapper stable for now.
- Extract rule logic into system files as systems are touched.
- Avoid new mechanics that only exist as one-off UI patch code.

### State duplication

`GameState.gd` is the formal autoload, but `TRGameState.gd` is where most live gameplay currently lives.

Preferred direction:

- Do not immediately rewrite everything.
- Treat `TRGameState.gd` as current runtime truth for prototype continuity.
- Gradually extract systems into dedicated files such as:
  - `PrestigeSystem.gd`
  - `MarketTradeSystem.gd`
  - `TurnResolutionSystem.gd`
  - `PalaceSystem.gd`
  - `ReligionSystem.gd`
  - `FlowerWarSystem.gd`
  - `RivalSystem.gd`

### Temporary files

Temporary Godot scene files such as `*.tmp` should not remain in the repository.

`Scenes/Main/GameScreen.tscn2577238696.tmp` was removed during v0.42 cleanup.

## 8. Current milestone status

Current milestone: `v0.42 — Repository Baseline & Cleanup`

Completed:

- Removed the temporary `GameScreen.tscn2577238696.tmp` file.
- Added / prepared this `CURRENT_BASELINE.md` file.

Next recommended steps:

1. Add `ROADMAP.md`.
2. Add or update `CHANGELOG.md`.
3. Decide how explicit the `TRGameState` runtime status should be in `project.godot`.
4. Begin `v0.43 — Structured Veintena Results Summary`.

## 9. v0.43 target

The next gameplay feature should be a structured Veintena Results Summary.

It should show, after advancing a Veintena:

- production changes
- population upkeep
- building upkeep / blocked buildings
- market changes
- prestige changes and reasons
- rival movements
- warnings for the next Veintena

This should become the bridge between the hidden simulation and readable player feedback.
