# Patch 8O2B — External Mirror Dependency Sweep: Prestige

## Purpose

Patch 8O2B continues the safe external mirror-dependency cleanup.

This slice updates:

- `Scripts/Systems/PrestigeSystem.gd`

## What changed

`PrestigeSystem.gd` no longer treats TRGameState mirror fields as the source of truth for:

- `resources`
- `player_prestige`
- `rival_prestige`
- `prestige_history`
- `last_report`

It now prefers CampaignState/runtime access through helper methods:

- `_campaign_resources(...)`
- `_player_prestige(...)`
- `_rival_prestige(...)`
- `_set_rival_prestige(...)`
- `_prestige_history(...)`
- `_append_report_line(...)`

## What did not change

No gameplay balance changed.

This patch does not change:

- savvy trade Prestige scale
- Flower War Prestige values
- rival placeholder values
- leaderboard sorting
- summary structure
- UI layout

## Why this is safe

This patch does not remove TRGameState mirror variables.

It only stops one more external system from depending on them as live data.

## What remains for 8O2C

The next slice should handle Palace route overview and any remaining active UI fallback reads that still use `state.get(...)` for campaign live/save data.
