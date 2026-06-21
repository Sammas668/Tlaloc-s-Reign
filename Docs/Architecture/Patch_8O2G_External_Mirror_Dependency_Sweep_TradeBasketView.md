# Patch 8O2G — External Mirror Dependency Sweep: TradeBasketView

## Purpose

Patch 8O2G continues the external mirror-dependency cleanup.

This slice updates:

- `Scripts/ui/screens/TradeBasketView.gd`

## How to apply

Unzip this patch and drag the `Scripts` and `Docs` folders into the Godot project root. Overwrite existing files when prompted.

No script or `.bat` file is required.

## What changed

The emergency `_apply_trade_fallback(...)` path no longer directly reads/writes TRGameState compatibility mirrors.

Removed direct mirror-style use of:

- `state.get("estate_stockpiles")`
- `state.get("market_stockpiles")`
- `state.set("estate_stockpiles", ...)`
- `state.set("market_stockpiles", ...)`
- `state.get("last_report")`
- `state.set("last_report", ...)`

The fallback now writes through:

- `_add_stock(...)` / CampaignState `add_estate_stock(...)`
- CampaignState `add_market_stock(...)`
- `_append_report_line(...)` / CampaignState `append_report_line(...)`

## What did not change

No gameplay values changed.

This patch does not change market pricing, trade validation, trade preview, barter balance rules, savvy trade Prestige, row layout, slider behaviour, or the MarketTradeSystem primary path.

## Notes

The normal active path still uses `apply_market_trade_plan(...)` on TRGameState / MarketTradeSystem.

The fallback only exists for safety if that API is unavailable.
