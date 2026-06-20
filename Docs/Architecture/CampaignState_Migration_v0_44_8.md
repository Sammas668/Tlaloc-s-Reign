# CampaignState Migration v0.44.8 — Stockpile Authority Pass

## Purpose

This pass makes stockpile access flow through `CampaignState` first while keeping `TRGameState` as the public compatibility API.

The immediate goal is not to remove the old `TRGameState.estate_stockpiles` and `TRGameState.market_stockpiles` variables yet. Those dictionaries remain as compatibility mirrors for UI and system code that still reads properties directly.

## What changed

- `CampaignState` schema updated to `campaign_state_v0_44_8`.
- `CampaignState` keeps the stockpile helper API added in v0.44.7:
  - `get_estate_stock(...)`
  - `set_estate_stock(...)`
  - `add_estate_stock(...)`
  - `get_market_stock(...)`
  - `set_market_stock(...)`
  - `add_market_stock(...)`
- Added `CampaignState.mirror_stockpiles_to_game_state(...)`.
- `TRGameState._sync_campaign_state_from_current_runtime()` now preserves CampaignState stockpiles when syncing other fields from the compatibility wrapper.
- `TRGameState._ensure_campaign_state_stockpile_bridge()` now seeds CampaignState from legacy dictionaries only if CampaignState stockpiles are empty, then mirrors CampaignState back to the legacy dictionaries.
- `TRGameState._base_market_goods()` reads market stock through CampaignState.
- `TRGameState._pay_population_upkeep()` pays from CampaignState estate stockpiles and then mirrors back to the compatibility dictionary.
- `TRGameState.get_barracks_summary()` reads captives through `_stock("captives")`.
- Remaining direct captive gain in the legacy Flower War path now uses `_add_stock("captives", ...)`.
- `MarketTradeSystem.apply_trade_plan(...)` now uses the CampaignState stockpile bridge when available.

## What did not change

- `TRGameState` remains the public API.
- UI calls still go through `TRGameState`.
- No economy formulas changed.
- No market pricing formulas changed.
- No save/load system has been activated or redesigned.
- Legacy stockpile dictionaries still exist for compatibility.

## Intended architecture after this pass

```text
UI
↓
TRGameState compatibility API
↓
CampaignState-owned stockpiles + extracted systems
```

## Test checklist

1. Open Godot and check for parser errors.
2. Start/load the game.
3. Check Storehouse stock values.
4. Accept a Market trade.
5. Confirm Storehouse updates after trade.
6. Advance one Veintena.
7. Confirm population upkeep changes stockpiles.
8. Launch/resolve a Flower War if possible.
9. Confirm captives and loot still apply.
10. Run:

```gdscript
print(TRGameState.get_campaign_state_sync_report(true))
```

Expected result:

```text
"in_sync": true
```

## Next migration target

If this works, the next pass should be one of:

- `v0.44.9 — CampaignState Calendar / Report Authority`
- `v0.44.9 — CampaignState Prestige State Authority`

Calendar/report is probably safer because it is simple. Prestige is more important but touches Palace, Market and Religion.
