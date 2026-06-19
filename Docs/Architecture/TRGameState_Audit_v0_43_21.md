# v0.43.21 — TRGameState Architecture Audit

## Summary

This is a documentation-only audit pass for the current architecture after the large v0.43 extraction sequence.

`TRGameState.gd` has genuinely shrunk, but it still looks large because it now serves three roles at once:

```text
1. live campaign state owner
2. system coordinator
3. public compatibility API for the UI
```

The split has succeeded as a first stage, but the file will not become small until live campaign data is moved into `CampaignState.gd`.

## Current measured status from Git comparison

Compared with the pre-extraction baseline, `TRGameState.gd` shows approximately:

```text
+393 lines added
-3173 lines removed
net shrink: about 2780 lines
```

The current file is still roughly 5,391 lines.

That means the reduction is real. The reason it still feels huge is that the remaining responsibilities are broad.

## What has already moved out

The following rule areas are now represented by system files:

```text
Prestige calculation and summary
Market trade pricing/validation/application
Population upkeep calculation/payment
Housing summary/capacity/maintenance
Production resolution/building operation
Turn resolution orchestration
Palace routes/structures/authority/court needs
Religious sacrifice
Warband public API
Flower War previews/resolution
Rival identity/pressure/placeholder prestige
```

## What TRGameState still owns

### 1. Live state

These are the main variables that should eventually move into `CampaignState.gd`:

```text
resources
resource_order
buildings
building_order
estate_stockpiles
market_stockpiles
market_demand
estate_buildings
active_housing_counts
population
base_housing_capacity
labour_assignments
market_economy
current_veintena
last_report
initialized
player_palace_dedicated_god
palace_built_structures
palace_structure_runtime_statuses
palace_delivered_ruler_demands
palace_ruler_demand_donations
player_prestige
rival_prestige
prestige_history
sacrifice_prestige_records
last_palace_maintenance_report
flower_war_palace_gate_enabled
warbands
last_flower_war_report
flower_war_report_archive
```

### 2. System wiring

These belong in the temporary wrapper for now, but may later become a `CampaignController` or be moved into an autoload bootstrap:

```text
system preload constants
system instance variables
_get_prestige_system()
_get_market_trade_system()
_get_population_upkeep_system()
_get_housing_system()
_get_production_system()
_get_turn_resolution_system()
_get_palace_system()
_get_religion_system()
_get_warband_system()
_get_flower_war_system()
_get_rival_system()
```

### 3. Data loading and start-state setup

These are strong candidates for `CampaignState.gd` in v0.44:

```text
new_game()
_load_json_dictionary()
_load_resource_definitions()
_load_building_definitions()
_load_market_economy_definitions()
_load_start_state()
_float_dictionary()
_int_dictionary()
_nested_int_dictionary()
_ensure_all_resource_keys()
_ensure_all_building_keys()
```

### 4. Public API wrappers

These should remain in `TRGameState.gd` until the UI has migrated, because they protect the screens from direct system dependencies.

Examples include:

```text
get_storehouse_goods()
get_market_goods()
estimate_market_resolution()
estimate_population_upkeep()
estimate_housing_maintenance()
estimate_production_resolution()
get_palace_*()
get_flower_war_*()
get_warband_*()
get_rival_*()
```

### 5. Compatibility shims

Some methods now only exist so older UI code or earlier wrapper paths still work. These should not be deleted blindly. They need caller checks first.

## Section-header plan for TRGameState.gd

When the actual code file is next edited, add headers using this pattern:

```gdscript
# -----------------------------------------------------------------------------
# v0.43.21 AUDIT — Live Campaign State
# Pending CampaignState migration.
# -----------------------------------------------------------------------------
```

Recommended section map:

```text
1. Script header and signals
2. System script preloads
3. God/resource constants
4. Live campaign state variables
5. Extracted-system instances
6. System accessors
7. Lifecycle / new game
8. Static data loading
9. State normalisation helpers
10. Resource/building name helpers
11. Storehouse and market public API
12. Building and construction public API
13. Turn public API
14. Population upkeep wrappers
15. Housing wrappers
16. Production wrappers
17. Palace wrappers
18. Religion wrappers
19. Warband wrappers
20. Flower War wrappers
21. Prestige wrappers
22. Rival wrappers
23. Remaining pending-extraction helpers
24. Compatibility shims
```

## Safe cleanup rules

Only delete code if all of the following are true:

```text
1. The replacement system method exists.
2. TRGameState already delegates to the replacement.
3. No UI script directly calls the old private helper.
4. The project opens and the relevant screen works after deletion.
```

Do not delete methods simply because the name looks old.

## Recommended next patch

The next patch should be:

```text
v0.44.0 — CampaignState scaffold
```

That patch should add:

```text
Scripts/State/CampaignState.gd
```

with live-state fields and reset/load placeholders, but should not yet move all data ownership in one jump.

## Why not remove more from TRGameState immediately?

Because `TRGameState.gd` is still the UI-facing public API. Removing wrappers too early risks breaking screens that currently work.

The next visible shrink will come from moving live data into `CampaignState.gd`, not from shaving off individual helper functions.
