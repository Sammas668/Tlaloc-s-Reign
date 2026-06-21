# Patch 8N2C — War / Rival Dependency Sweep

This patch is the third safe slice of the wider Patch 8N2 system dependency sweep.

It updates:

- `WarbandSystem.gd`
- `FlowerWarSystem.gd`
- `RivalSystem.gd`

## Goal

War/rival systems should read/write CampaignState through TRGameState bridge/accessors instead of treating TRGameState dictionary fields as the source of truth.

## What changed

### WarbandSystem

- Reads warbands from CampaignState first.
- Writes warbands back to CampaignState first.
- Warband report lines prefer runtime report helpers / CampaignState-backed report handling.
- TRGameState field fallback remains only for compatibility.

### FlowerWarSystem

- Reads warbands, population, stockpiles, resources and current Veintena from CampaignState first.
- Writes warbands, population, estate stockpiles and last Flower War report back to CampaignState first.
- Accepted Flower War report lines prefer runtime report helpers / CampaignState-backed report handling.
- TRGameState field fallback remains only for compatibility.

### RivalSystem

- Reads rival Prestige from CampaignState first.
- Writes rival Prestige back to CampaignState first.
- TRGameState field fallback remains only for compatibility.

## Palace note

`PalaceSystem.gd` is the remaining large state-heavy system and should be migrated as a separate focused patch.

Do not start 8N3 until `PalaceSystem.gd` has also been migrated and smoke-tested.

Recommended next patch:

```text
Patch 8N2D — PalaceSystem dependency sweep
```

## What did not change

No balance values changed.

This patch does not change:

- doctrine values
- Flower War combat maths
- capture rules
- loot rules
- XP thresholds
- warband skill tree data
- rival AI behaviour
- UI layout
