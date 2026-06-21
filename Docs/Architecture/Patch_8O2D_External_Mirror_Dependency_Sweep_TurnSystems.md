# Patch 8O2D — External Mirror Dependency Sweep: Turn Systems

## Purpose

Patch 8O2D continues the external mirror-dependency cleanup.

This slice updates:

- `Scripts/Systems/TurnResolutionSystem.gd`
- `Scripts/Systems/TurnSystem.gd`

## What changed

### TurnResolutionSystem.gd

The active turn resolver no longer uses `state.get(...)` or `state.set(...)` compatibility mirror fallbacks for campaign-owned state.

It now reads/writes through:

- CampaignState via `_get_campaign_state()`
- TRGameState public report helpers where available
- CampaignBridgeSystem where it already owns calendar / summary write-through

Removed active fallback reads/writes for:

- `initialized`
- `current_veintena`
- `calendar_period`
- `ritual_year`
- `last_report`
- generic campaign dictionaries

### TurnSystem.gd

`TurnSystem.gd` was an old unused legacy path that still referenced older GameState-style fields directly.

It is now a safe compatibility wrapper that delegates to the runtime state if it is ever accidentally used.

## What did not change

No gameplay values changed.

This patch does not change:

- turn order
- population upkeep
- housing upkeep
- palace maintenance
- building operations
- warband recovery
- religion decay
- Nemontemi behaviour
- report text
- summary structure

## What remains for 8O2E

Continue external sweep for remaining active UI/system fallbacks, especially where search still finds `state.get(...)` in active controllers or system compatibility helpers.

Do not delete TRGameState mirrors yet.
