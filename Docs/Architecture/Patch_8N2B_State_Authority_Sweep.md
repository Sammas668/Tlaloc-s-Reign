# Patch 8N2B — Housing / Labour / EstateBuilding Dependency Sweep

This patch is the second safe slice of the wider Patch 8N2 system dependency sweep.

It updates:

- `HousingSystem.gd`
- `LabourSystem.gd`
- `EstateBuildingSystem.gd`

## Goal

Systems should read/write CampaignState through TRGameState bridge/accessors instead of treating TRGameState dictionary fields as the source of truth.

## What changed

### HousingSystem

- Reads buildings, building order, estate buildings, active housing counts, population, base housing capacity and estate stockpiles from CampaignState first.
- Writes active housing counts, base housing capacity and housing-maintenance stockpile payments back to CampaignState first.
- Keeps TRGameState field fallback only for compatibility.

### LabourSystem

- Reads buildings, building order, estate buildings, population and labour assignments from CampaignState first.
- Writes labour assignments back through CampaignState first.
- Keeps TRGameState fallback only for compatibility.

### EstateBuildingSystem

- Reads buildings, estate buildings, active housing counts and stockpiles from CampaignState first.
- Builds/destroys by mutating CampaignState first.
- Construction costs subtract from CampaignState stockpiles first.
- Keeps TRGameState helper fallbacks only for compatibility.

## What did not change

No balance values changed.

This patch does not change:

- building costs
- housing capacity
- housing upkeep
- labour requirements
- production output
- turn order
- UI layout

## Next remaining sweep

Patch 8N2C should handle:

- `PalaceSystem.gd`
- `WarbandSystem.gd`
- `FlowerWarSystem.gd`
- `RivalSystem.gd`

Patch 8N3 should still wait until 8N2C has been applied and smoke-tested.
