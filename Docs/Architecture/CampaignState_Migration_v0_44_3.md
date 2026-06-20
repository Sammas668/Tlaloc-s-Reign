# CampaignState Migration v0.44.3 — Start-State Shaping Bridge

## Purpose

This patch makes `CampaignState.gd` responsible for shaping the Prototype 0 start-state data before it is applied back into the current `TRGameState.gd` runtime.

This is still a bridge phase. `TRGameState.gd` remains the public API and active compatibility wrapper. The UI should continue to call `TRGameState` exactly as before.

## What changed

- `TRGameState._load_start_state()` now delegates dictionary shaping to `CampaignState.load_start_state(...)`.
- `CampaignState.load_static_definitions(...)` receives the loaded resource/building/market definitions before start-state application.
- `CampaignState.apply_to_game_state(self)` applies the shaped data back into `TRGameState`.
- Obsolete duplicate conversion helpers were removed from `TRGameState.gd`:
  - `_float_dictionary(...)`
  - `_int_dictionary(...)`
  - `_nested_int_dictionary(...)`
  - `_ensure_all_resource_keys()`
  - `_ensure_all_building_keys()`
- A duplicate `buildings.clear()` call in `_load_building_definitions()` was removed.

## What did not change

- No UI calls changed.
- No gameplay formulas changed.
- No system APIs changed.
- `CampaignState` is not authoritative during turns yet.
- `TRGameState` still owns active runtime mutation.

## Why this matters

This is the first real reduction of `TRGameState` state-loading responsibility. It proves that start-state shaping can move into `CampaignState` without changing gameplay.

## Next migration target

`v0.44.4` should start moving read/write access for one safe group of live state fields through `CampaignState`, probably calendar/report state or static definitions first, before moving high-risk economic mutation.
