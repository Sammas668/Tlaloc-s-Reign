# CampaignState Migration v0.44.11 — Palace State Bridge

## Purpose

This patch continues the CampaignState authority migration by adding palace-state access helpers to `CampaignState.gd` and routing selected `TRGameState.gd` palace-facing calls through the CampaignState bridge.

This is still a bridge pass, not a full authority cut-over.

## Scope

Added CampaignState helpers for:

- palace dedication state
- Flower War palace-gate state
- built palace structures
- palace structure runtime statuses
- palace ruler demand donation records
- last palace maintenance report
- palace-state mirroring back to `TRGameState`

Updated `TRGameState.gd` so selected palace calls now sync CampaignState after palace mutations.

## Still true after this patch

- `TRGameState.gd` remains the public API used by UI screens.
- `CampaignState.gd` is becoming the live-state owner, but some palace logic still runs through `PalaceSystem.gd` with `TRGameState` as the compatibility façade.
- Palace formulas and costs are not intentionally changed.
- Palace structure tree definitions are still in `TRGameState.gd` for now.

## Test checklist

1. Open Godot and check for parser errors.
2. Start or load a game.
3. Open Palace → Overview.
4. Open Palace → Divine Seat.
5. Dedicate the palace if possible.
6. Build a palace structure if resources allow.
7. Open Palace → Court Needs and donate if possible.
8. Advance one Veintena.
9. Confirm Palace → Prestige, Authority and Court Needs still update.
10. Optional debug check:

```gdscript
print(TRGameState.get_campaign_state_sync_report(true))
```

Expected result:

```text
"in_sync": true
```

## Next likely patch

`v0.44.12 — CampaignState Population / Building / Housing State Bridge`

That should begin moving the next live-state cluster out of direct `TRGameState` ownership.
