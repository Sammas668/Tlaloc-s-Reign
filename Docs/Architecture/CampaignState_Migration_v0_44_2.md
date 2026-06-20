# CampaignState Migration v0.44.2 — TRGameState Owns CampaignState

## Purpose

This patch is the first bridge step where `TRGameState.gd` owns a `CampaignState` instance.

It does **not** make `CampaignState` authoritative yet. `TRGameState.gd` still owns the live runtime variables and remains the public API used by the UI.

## What changed

`TRGameState.gd` now:

- preloads `res://Scripts/state/CampaignState.gd`
- holds `var campaign_state: CampaignState = null`
- lazily creates the CampaignState through `_get_campaign_state()`
- exposes `get_campaign_state_snapshot()` for migration/debugging
- syncs the CampaignState snapshot after `new_game()`
- syncs the CampaignState snapshot after `advance_veintena()`

## Current architecture after this patch

```text
UI
↓
TRGameState.gd public API / compatibility wrapper
↓
CampaignState snapshot + extracted Systems
```

## Important constraint

`CampaignState` is still a **snapshot bridge**, not the source of truth.

Do not move UI calls directly to `CampaignState` yet. The UI should continue to use `TRGameState.gd` until a later patch explicitly makes CampaignState authoritative.

## Why this is safe

The patch does not move gameplay formulas, UI methods, or turn logic. It only keeps a migration snapshot of the current runtime.

## Test checklist

1. Open Godot and check for parser errors.
2. Start/load the game.
3. Confirm Market opens.
4. Confirm Palace opens.
5. Confirm Warriors / Flower Wars opens.
6. Advance one Veintena.
7. Confirm reports and stockpiles still update.
8. Confirm no visible gameplay behaviour has changed.

## Next patch

`v0.44.3 — CampaignState Static/Start-State Loading Bridge`

Recommended next step:

- shift static/start-state loading into `CampaignState` in a controlled way
- keep TRGameState variables mirrored for UI compatibility
- begin reducing duplicate state-loading functions from TRGameState
