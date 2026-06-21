# Patch 8N6 — Remaining Lag Reduction

## Why this patch exists

After Patch 8N5 the large lag spikes were reduced, but smaller spikes remained on New Game and some heavy screen opens.

Git now shows the 8N5 version is present. The remaining avoidable costs were:

- read-only `TRGameState.get_current_veintena()` and `get_last_report()` still forced calendar/report bridge synchronisation;
- `HousingSystem.active_population_for_group()` could still rebuild the whole active-population table repeatedly;
- `HousingSystem.housing_capacity_by_group()` still called `is_housing_building_id()` inside a hot loop, which re-read buildings repeatedly;
- `PalaceScreenController._palace_probe_summary()` still calculated staff, maintenance and operation-preview summaries even when no palace structures were built;
- Palace notification/main-content refreshes could call the same probe summary multiple times in one refresh.

## What changed

### TRGameState

Read-only calendar/report access no longer forces a bridge sync.

### HousingSystem

- Adds a tiny active-population cache.
- Invalidates the cache when active housing/base capacity changes.
- Inlines the housing-building check inside the hot capacity loop.

### PalaceScreenController

- Adds a short-lived palace probe-summary cache per refresh.
- Clears that cache when the Palace screen/report refreshes.
- Skips staff/maintenance/operation-preview calculations when no palace structures are built.

## What did not change

No gameplay values changed.

This patch does not change balance, production, housing capacity, labour requirements, palace costs, court needs, prestige values, Flower War maths or UI layout.

## Expected result

- New Game should have less start-up hitching.
- Palace opening should be lighter, especially before structures exist.
- Housing and Labour should avoid repeated active-population recalculation.
