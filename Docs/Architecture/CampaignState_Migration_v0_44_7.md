# CampaignState Migration v0.44.7 — Stockpile Access Bridge

## Purpose

This patch begins the next stage of the `TRGameState` → `CampaignState` migration by routing the core estate stockpile helper methods through `CampaignState`.

`CampaignState` is still not fully authoritative. `TRGameState` remains the public API and compatibility wrapper. However, stockpile reads/writes that use `_stock(...)` and `_add_stock(...)` now pass through the `CampaignState` bridge first and then keep the legacy `estate_stockpiles` dictionary synchronised.

## Changed files

- `Scripts/Autoload/TRGameState.gd`
- `Scripts/state/CampaignState.gd`

## What changed

### CampaignState

Added stockpile helper methods:

```gdscript
get_estate_stock(resource_id)
set_estate_stock(resource_id, amount)
add_estate_stock(resource_id, amount)
get_market_stock(resource_id)
set_market_stock(resource_id, amount)
add_market_stock(resource_id, amount)
```

### TRGameState

- Added `_ensure_campaign_state_stockpile_bridge()`.
- `_stock(...)` now reads from `CampaignState`.
- `_add_stock(...)` now writes to `CampaignState` first, then mirrors the value back into `TRGameState.estate_stockpiles`.
- `apply_market_trade_plan(...)` now syncs the CampaignState mirror after public market trade application.

## No intended gameplay changes

This patch should not alter economy values, production outputs, upkeep costs, trade calculations, prestige values, or UI behaviour.

## Test checklist

1. Open Godot and check for parser errors.
2. Start/load the game.
3. Open Storehouse and confirm stockpiles display.
4. Build something or attempt to build something.
5. Use Market → Trade and accept a trade.
6. Advance one Veintena.
7. Confirm stockpiles, reports, Palace → Prestige, Housing and Warriors still work.
8. Optional debug: run `print(TRGameState.get_campaign_state_sync_report(false))` and check for unexpected mismatches.

## Next migration target

After this works, the next safe step is likely `v0.44.8 — CampaignState report/calendar bridge`, moving `current_veintena` and `last_report` helper paths toward CampaignState while still preserving `TRGameState` compatibility.
