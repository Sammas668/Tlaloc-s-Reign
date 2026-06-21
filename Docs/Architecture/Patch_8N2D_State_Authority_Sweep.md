# Patch 8N2D — PalaceSystem Dependency Sweep

This patch migrates `Scripts/Systems/PalaceSystem.gd` toward CampaignState-first state access.

## Files changed

- `Scripts/Systems/PalaceSystem.gd`

## What changed

`PalaceSystem.gd` now reads/writes CampaignState first, with TRGameState field access kept only as compatibility fallback, for:

- palace dedication
- Flower War palace gate
- built palace structures
- palace structure runtime statuses
- last palace maintenance report
- palace ruler demand donations
- palace delivered ruler demands
- estate stockpiles used by palace build/maintenance
- current Veintena reads in palace/court-needs summaries
- player Prestige reads in palace/court-needs summaries
- palace report appending

## What did not change

This patch does not change:

- palace structure-tree data
- palace build costs
- palace maintenance costs
- palace staff requirements
- dedication powers
- court-needs math
- Prestige reward values
- UI layout

## Notes

`TRGameState` remains the public facade. `CampaignState` is the live/save-state owner. This patch keeps fallback compatibility paths inside helper methods only.
