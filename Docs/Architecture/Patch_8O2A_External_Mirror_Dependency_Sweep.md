# Patch 8O2A — External Mirror Dependency Sweep: Religion + Turn Runtime

## Purpose

Patch 8O1 stopped `TRGameState.gd` from depending on its own mirror variables internally.

Patch 8O2 begins moving external systems away from treating `TRGameState` mirror fields as live data. This is deliberately split into safe slices.

This first slice updates:

- `ReligionSystem.gd`
- `TurnRuntimeSystem.gd`

## ReligionSystem changes

The sacrifice path no longer uses direct mirror reads/writes for:

- `population`
- `current_veintena`
- `sacrifice_prestige_records`
- `last_report`

It now prefers CampaignState/runtime access through:

- `_stock(...)`
- `_add_stock(...)`
- `_active_population_for_group(...)`
- `CampaignState.add_population_count(...)`
- `CampaignState.append_sacrifice_prestige_record(...)`
- `_append_report_line(...)`
- `get_current_veintena()`

## TurnRuntimeSystem changes

Turn-runtime helpers no longer use direct mirror reads for:

- `buildings`
- `last_report`

Population upkeep now reads/writes stockpiles through CampaignState directly instead of forcing the stockpile bridge on entry.

`population_upkeep_rates` remains a TRGameState rule/static table because it is not campaign live/save state.

## What did not change

No gameplay balance changed.

This patch does not change sacrifice values, favour values, Prestige values, population upkeep rates, production values, turn order or UI layout.

## What remains for 8O2B

Search and migrate the next set of external `state.get(...)` / `state.set(...)` call sites, likely:

- `PrestigeSystem.gd`
- `PalaceRouteOverviewSystem.gd`
- remaining active UI controller fallback reads

Do not delete TRGameState mirrors yet.
