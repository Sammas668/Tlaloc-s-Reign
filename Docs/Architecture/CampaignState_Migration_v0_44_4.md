# CampaignState Migration v0.44.4 — Sync Helper Bridge

## Purpose

This pass keeps the new `CampaignState` mirror closer to the live `TRGameState` runtime without making `CampaignState` authoritative yet.

Before this pass, `CampaignState` was synced after `new_game()` and after `advance_veintena()`. That was safe, but some direct runtime changes inside `TRGameState` could leave the mirror stale until the next explicit snapshot request.

## Change

`TRGameState.gd` now routes local `state_changed` emissions through:

```gdscript
func _emit_state_changed_and_sync() -> void:
    _sync_campaign_state_from_current_runtime()
    emit_signal("state_changed")
```

This means the mirror updates before UI listeners are notified for most local `TRGameState` mutations.

## Architecture status after v0.44.4

Current runtime path remains:

```text
UI
↓
TRGameState public API / compatibility wrapper
↓
Extracted systems
↓
TRGameState-owned live variables
↓
CampaignState mirror snapshot
```

`CampaignState` is still a mirror, not the owner.

## Why this step matters

This is a small preparation step before actual state ownership migration. It makes later patches safer because `CampaignState` is kept current more often and can be inspected as a reliable snapshot.

## Remaining before CampaignState can become authoritative

- Move static data/resource/building live fields into `CampaignState` as the primary owner.
- Move stockpiles and market dictionaries to `CampaignState` authority.
- Move population/housing/labour dictionaries to `CampaignState` authority.
- Move palace/prestige/religion live fields to `CampaignState` authority.
- Move warband and Flower War report fields to `CampaignState` authority.
- Replace direct `TRGameState` variable access in systems with `CampaignState` access, one system at a time.
