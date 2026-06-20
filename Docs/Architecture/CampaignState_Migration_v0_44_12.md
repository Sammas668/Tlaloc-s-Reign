# CampaignState Migration v0.44.12 — Population / Buildings / Housing Bridge

## Purpose

This patch continues the CampaignState migration by adding explicit bridge helpers for the estate-structure part of live campaign state:

- population counts
- estate building counts
- active housing counts
- base housing capacity
- labour assignments

`TRGameState.gd` remains the public UI-facing API and still owns many legacy compatibility fields. `CampaignState.gd` now has the access/mirror helpers needed for these fields so later patches can make this domain authoritative one section at a time.

## What changed

### CampaignState.gd

Adds helpers for:

- `get_population_copy()`
- `get_population_count(...)`
- `set_population_count(...)`
- `add_population_count(...)`
- `get_estate_buildings_copy()`
- `get_estate_building_count(...)`
- `set_estate_building_count(...)`
- `add_estate_building_count(...)`
- `get_active_housing_counts_copy()`
- `get_active_housing_count(...)`
- `set_active_housing_count_value(...)`
- `get_base_housing_capacity_copy()`
- `set_base_housing_capacity_values(...)`
- `set_base_housing_capacity_value(...)`
- `get_labour_assignments_copy()`
- `get_labour_assignment_for_building(...)`
- `set_labour_assignments_values(...)`
- `set_labour_assignment_for_building(...)`
- `clear_labour_assignment_for_building(...)`
- `mirror_population_building_housing_to_game_state(...)`

### TRGameState.gd

Adds bridge helpers:

- `_ensure_campaign_state_estate_structure_bridge()`
- `_mirror_estate_structure_compatibility_from_campaign_state()`

Selected mutation paths now sync this domain into CampaignState:

- building construction
- building destruction
- active housing changes through existing state-change sync
- labour staffing changes

## What did not change

- No new gameplay formulas.
- No new UI screens.
- No change to population upkeep rates.
- No change to building costs.
- No change to housing maintenance rules.
- No change to labour allocation design.

## Migration status after this patch

CampaignState is now prepared to become authoritative for population/building/housing state, but this patch is still a bridge. The next safe step is an authority pass once this version has been tested.

Expected direction:

1. v0.44.12 — bridge helpers and selected sync. **This patch.**
2. v0.44.13 — population/building/housing authority pass.
3. v0.44.14 — labour assignment authority cleanup.
4. v0.44.15 — CampaignState authority audit.
