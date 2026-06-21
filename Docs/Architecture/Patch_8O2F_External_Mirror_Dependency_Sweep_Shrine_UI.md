# Patch 8O2F — External Mirror Dependency Sweep: Shrine UI

## Purpose

Patch 8O2F continues the external mirror-dependency cleanup.

This slice updates:

- `Scripts/ui/screens/ShrineScreenController.gd`

## What changed

`ShrineScreenController.gd` no longer uses direct TRGameState compatibility mirror reads/writes for active CampaignState-owned data in the shrine UI paths.

Removed direct mirror-style use of:

- `state.get("calendar_period")`
- `state.get("last_report")`
- `state.set("last_report", ...)`
- `state.get("estate_stockpiles")`
- `state.set("estate_stockpiles", ...)`
- `state.get("population")`

The controller now prefers:

- `get_calendar_period()`
- CampaignState snapshot/runtime access
- `_stock(...)`
- `_add_stock(...)`
- `_active_population_for_group(...)`
- `_append_report_line(...)`

## What did not change

No gameplay values changed.

This patch does not change:

- shrine costs
- shrine upgrade requirements
- ritual costs
- ritual favour rolls
- divine favour decay values
- religion prestige values
- shrine UI layout

## Notes

The old `RELIGION_STATE_META_KEY` fallback remains in this patch because it is a separate legacy religion-state fallback, not one of the TRGameState live-data mirror dictionaries being removed in the 8O2 external sweep.

## What remains for 8O2G

Continue the UI sweep for `TradeBasketView.gd`, especially its local emergency fallback that still directly mutates stockpile/report mirror fields if the MarketTradeSystem API is missing.

Do not delete TRGameState mirrors yet.
