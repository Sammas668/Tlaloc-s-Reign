# Patch 8O2E — External Mirror Dependency Sweep: Calendar UI

## Purpose

Patch 8O2E continues the external mirror-dependency cleanup.

This slice updates:

- `Scripts/ui/widgets/CalendarPacingController.gd`

## What changed

The calendar widget no longer falls back to TRGameState compatibility mirror fields for CampaignState-owned calendar data.

Removed direct mirror-style reads for:

- `state.get("current_veintena")`
- `state.get("calendar_period")`
- `state.get("ritual_year")`

The widget now prefers:

- `get_current_veintena()`
- `get_calendar_period()`
- `get_ritual_year()`
- CampaignState snapshot access through `get_campaign_state_snapshot()`
- direct CampaignState access through `_get_campaign_state()` only as a final runtime fallback

## What did not change

No gameplay values changed.

This patch does not change:

- calendar order
- Veintena god mapping
- Nemontemi display
- advance button text rules
- calendar card layout
- calendar report wording

## Notes

This patch intentionally keeps `host.get("advance_turn_button")` and `host.get("_veintenas")` because those are UI/controller fields, not CampaignState live/save mirrors.

## What remains for 8O2F

Continue the UI sweep for:

- TradeBasketView fallback stockpile/report writes
- ShrineScreenController calendar-period fallback
- any remaining active controller `state.get(...)` fallbacks

Do not delete TRGameState mirrors yet.
