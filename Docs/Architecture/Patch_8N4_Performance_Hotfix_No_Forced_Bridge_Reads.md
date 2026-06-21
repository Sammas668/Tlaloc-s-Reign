# Patch 8N4 — Performance Hotfix: No Forced Bridge Reads

## Why this patch exists

After the 8N2 state-authority sweep, New Game and heavy screens such as Housing and Palace developed large lag spikes.

The cause was repeated bridge synchronisation in read-heavy UI paths. Several new helper methods called bridge methods such as `_ensure_campaign_state_stockpile_bridge()` and `_ensure_campaign_state_estate_structure_bridge()` every time a system read a dictionary. That is expensive inside screen-refresh loops because it can repeatedly copy and mirror state.

## What changed

This hotfix updates the system helper functions so read paths use:

```gdscript
_get_campaign_state()
```

instead of forcing an `_ensure_campaign_state_*_bridge()` sync every time.

The migrated systems still read CampaignState first. The difference is that they no longer perform a full bridge sync on every dictionary read.

## Files updated

- `ProductionSystem.gd`
- `StorehouseSystem.gd`
- `MarketEconomySystem.gd`
- `MarketTradeSystem.gd`
- `HousingSystem.gd`
- `LabourSystem.gd`
- `EstateBuildingSystem.gd`
- `WarbandSystem.gd`
- `FlowerWarSystem.gd`
- `RivalSystem.gd`
- `PalaceSystem.gd`

## What did not change

No gameplay values changed.

This patch does not change production outputs, stockpile values, building costs, housing capacity, labour requirements, market pricing, palace costs, Flower War maths, doctrine stats, rival behaviour or UI layout.

## Expected result

- New Game should open much faster.
- Opening Housing should no longer trigger a huge spike.
- Opening Palace should be closer to the old performance.
- CampaignState remains the source of truth for migrated systems.

## If lag remains

The next place to optimise is screen-level caching in Housing and Palace. But this patch removes the worst repeated bridge-sync cost.
