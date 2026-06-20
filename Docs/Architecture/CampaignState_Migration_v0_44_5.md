# CampaignState Migration v0.44.5 — Sync Audit

## Summary

v0.44.5 adds a safe audit bridge before making `CampaignState.gd` authoritative.

The current architecture remains:

```text
UI
↓
TRGameState.gd public API / compatibility wrapper
↓
CampaignState mirror + extracted systems
```

`TRGameState.gd` is still the active runtime owner. `CampaignState.gd` is still a mirror/data container.

## Added helpers

`TRGameState.gd` now exposes:

```gdscript
get_campaign_state_sync_report(sync_first: bool = false) -> Dictionary
is_campaign_state_mirror_in_sync() -> bool
```

These compare the live fields in `TRGameState.gd` against the corresponding fields in `CampaignState.gd`.

## Why this patch exists

Before moving real live state ownership to `CampaignState.gd`, we need a way to prove the mirror is reliable.

This patch gives the next migration patches a simple diagnostic:

- check the mirror before sync
- check the mirror after sync
- identify which fields drift
- avoid guessing when a future state migration breaks something

## Fields currently checked

- resources
- resource_order
- buildings
- building_order
- estate_stockpiles
- market_stockpiles
- market_demand
- market_economy
- estate_buildings
- active_housing_counts
- population
- base_housing_capacity
- labour_assignments
- current_veintena
- last_report
- initialized
- player_palace_dedicated_god
- palace_built_structures
- palace_structure_runtime_statuses
- palace_delivered_ruler_demands
- palace_ruler_demand_donations
- last_palace_maintenance_report
- player_prestige
- rival_prestige
- prestige_history
- sacrifice_prestige_records
- flower_war_palace_gate_enabled
- last_flower_war_report
- flower_war_report_archive
- warbands

## No gameplay changes

This patch does not change formulas, turn order, UI, resources, rival behaviour or save format.

## Next intended step

If v0.44.5 is stable, the next patch can start making one small state category authoritative in `CampaignState.gd`, probably calendar/report state or stockpile helper access.
