# CampaignState Migration v0.44.6 — Project Data Loading Bridge

## Purpose

This migration step moves project-data loading and start-state shaping into `CampaignState` while keeping `TRGameState` as the public API and active gameplay runtime owner.

The goal is to reduce `TRGameState` from a full game-state monolith into a compatibility wrapper around a proper campaign-state object.

## Changed responsibility

`CampaignState` now owns the bridge-level loading flow for:

- `resources.json`
- `buildings.json`
- `market_economy.json`
- `start_state.json`

It parses the JSON files, shapes dictionaries into runtime-safe values, ensures resource/building keys exist, and returns warnings to `TRGameState` for Godot warning output.

## TRGameState responsibility after this pass

`TRGameState` still:

- exposes public UI-facing methods
- owns the active live variables for now
- coordinates systems
- emits signals
- performs remaining compatibility work

But it no longer needs to carry separate local implementations of the project-data loading helpers removed in this pass.

## Not yet done

`CampaignState` is not authoritative yet. The next migration steps should start changing systems/wrappers to read and write selected state through `CampaignState` directly.

Recommended next step:

`v0.44.7 — CampaignState calendar/report authority bridge`

This should make the least risky state fields, such as `current_veintena`, `last_report`, and `initialized`, read/write through `CampaignState` while preserving compatibility properties on `TRGameState`.
