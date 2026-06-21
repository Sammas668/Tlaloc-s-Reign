# Patch 8N5 — New Game / Housing / Palace Lag Hotfix

## Why this patch exists

After the state-authority migration, New Game, Housing and Palace developed heavy lag.

The remaining issue was repeated expensive read work during screen construction:

- Housing repeatedly duplicated CampaignState dictionaries inside nested loops.
- Housing recalculated active-population capacity several times per category/building card.
- Labour and EstateBuilding helpers also copied large dictionaries on read.
- Palace overview/probe reports called the full `get_palace_summary()`, which builds much more data than the overview needs.

## What changed

### HousingSystem

- Read helpers now return direct CampaignState dictionary references for read paths instead of duplicated copies.
- Category summaries use already-known active capacity instead of recalculating active population repeatedly.
- Housing building view data accepts cached capacity dictionaries.
- Mothball rows use cached capacity dictionaries.
- `ensure_active_housing_counts()` caches buildings and estate-building dictionaries for the whole pass.

### LabourSystem

- Read helpers now return direct CampaignState dictionary references for read paths instead of duplicated copies.

### EstateBuildingSystem

- Read helpers now return direct CampaignState dictionary references for read paths instead of duplicated copies.

### PalaceScreenController

- Palace overview and navigation probe reports now use a lightweight palace summary instead of the full `get_palace_summary()` payload.
- The full palace summary remains available for deeper tabs and backend compatibility.

## What did not change

No balance values changed.

This patch does not change:

- stockpile values
- building costs
- housing capacities
- labour requirements
- palace costs
- palace structure data
- court-needs math
- turn order
- UI layout

## Expected result

- New Game should open faster.
- Housing should open faster.
- Palace overview should open faster.

If Palace is still slow after this, the next optimisation should cache palace structure-tree generation inside `PalaceSystem.gd`.
