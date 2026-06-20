# CampaignState Migration v0.44.10 — Prestige Bridge

## Purpose

This patch moves the first Prestige-state access paths through `CampaignState` while keeping `TRGameState` as the public API and compatibility wrapper.

This is a bridge step, not the final Prestige authority cutover.

## Added to CampaignState

`CampaignState.gd` now includes Prestige helpers for:

- player Prestige value
- player Prestige record creation
- Prestige history copies
- rival Prestige values
- sacrifice Prestige record copies
- mirroring Prestige state back to `TRGameState`

## Changed in TRGameState

`TRGameState.gd` now routes these public methods through the CampaignState bridge:

- `get_player_prestige()`
- `add_player_prestige(...)`
- `get_prestige_history()`
- `get_rival_prestige()`
- `set_rival_prestige(...)`
- `get_sacrifice_prestige_records()`

Sacrifice execution still uses `ReligionSystem`; after sacrifice, the compatibility record list is mirrored into `CampaignState`.

## What did not change

- No Prestige formula changes.
- No Palace formula changes.
- No Flower War formula changes.
- No UI changes.
- `TRGameState` remains the public API.
- `CampaignState` is not fully authoritative for all Prestige-related writes yet.

## Test checklist

1. Open Godot and check for parser errors.
2. Start/load the game.
3. Open Palace -> Prestige.
4. Accept a Savvy Trade and confirm Prestige increases.
5. Launch/resolve a Flower War if available and confirm Prestige records still appear.
6. Perform a sacrifice if available and confirm the sacrifice appears in Palace -> Prestige.
7. Confirm rival leaderboard still displays.
8. Optional debug check:

```gdscript
print(TRGameState.get_campaign_state_sync_report(true))
```

Expected result: `"in_sync": true`.

## Next target

`v0.44.11 — CampaignState Palace State Bridge`

That should move palace dedication, built structures, structure statuses and court-need donation records toward CampaignState.
