# Patch 8O2I + 8O2J — Market / Production Fallback Cleanup and Final Readiness Audit

## Purpose

This patch combines the two requested follow-up tasks:

- **8O2I — MarketTradeSystem fallback cleanup**
- **8O2J — ProductionSystem fallback cleanup / final readiness audit**

The goal is to remove the remaining active fallback paths where normal systems could still read or write TRGameState mirror dictionaries directly.

## Files changed

- `Scripts/Systems/MarketTradeSystem.gd`
- `Scripts/Systems/ProductionSystem.gd`

## 8O2I — MarketTradeSystem fallback cleanup

`MarketTradeSystem.gd` no longer falls back to direct TRGameState mirror mutation when CampaignState is unavailable.

Removed direct fallback use of:

```gdscript
state.get("estate_stockpiles")
state.get("market_stockpiles")
state.set("estate_stockpiles", ...)
state.set("market_stockpiles", ...)
state.get("last_report")
state.set("last_report", ...)
```

The active trade path now requires the CampaignState stockpile API:

```gdscript
add_estate_stock(...)
add_market_stock(...)
```

If that API is unavailable, trade application fails safely instead of mutating mirror dictionaries.

Report appending now uses the runtime report helper / CampaignState only. If neither is available, it does not write to `last_report` mirrors.

## 8O2J — ProductionSystem fallback cleanup

`ProductionSystem.gd` no longer falls back to direct TRGameState mirror dictionaries for production resolution.

Removed direct fallback use of:

```gdscript
state.get(key)
state.set("estate_stockpiles", ...)
```

The production system now reads these from CampaignState only:

- `estate_stockpiles`
- `buildings`
- `estate_buildings`
- `building_order`

For stock changes, it uses CampaignState `add_estate_stock(...)` first, then the TRGameState `_add_stock(...)` public helper if available. It no longer manually writes to the `estate_stockpiles` mirror.

## What did not change

No gameplay values changed.

This patch does not change:

- market pricing
- trade validation
- barter value balance
- savvy trade Prestige
- production building recipes
- production output values
- staffing rules
- upkeep rules
- turn order
- UI layout

## Final readiness audit

After this patch, the known active blockers found in 8O2H have been addressed:

- TradeBasketView fallback cleanup was already done in 8O2G.
- MarketTradeSystem no longer directly mutates stockpile/report mirrors.
- ProductionSystem no longer directly reads/writes stockpile/building mirrors as fallback live data.

The remaining mirror-related code is now primarily expected bridge compatibility code in:

- `Scripts/Systems/CampaignBridgeSystem.gd`
- `Scripts/Autoload/TRGameState.gd`
- CampaignState mirror-to-game-state helper methods

That means full mirror deletion can now begin, but only domain-by-domain.

## Recommended next step

Begin **8O3A — Calendar/report mirror removal**.

Do not remove all mirrors in one patch.

Suggested order:

```text
8O3A — calendar/report mirrors
8O3B — prestige mirrors
8O3C — palace mirrors
8O3D — warband/Flower War mirrors
8O3E — housing/labour mirrors
8O3F — stockpile/economy mirrors
8O3G — resources/buildings mirrors last
```

## Test checklist

After applying this patch:

1. Start New Game.
2. Open Market.
3. Move trade sliders.
4. Accept a valid trade.
5. Confirm estate and market stockpiles update.
6. Confirm the trade report line appears.
7. Advance one Veintena.
8. Confirm production reports still appear.
9. Confirm production inputs and outputs still update stockpiles.
10. Confirm no new lag appears.
