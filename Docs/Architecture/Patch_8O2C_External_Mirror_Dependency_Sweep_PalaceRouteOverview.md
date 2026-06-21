# Patch 8O2C — External Mirror Dependency Sweep: Palace Route Overview

## Purpose

Patch 8O2C continues the safe external mirror-dependency cleanup.

This slice updates:

- `Scripts/Systems/PalaceRouteOverviewSystem.gd`

## What changed

`PalaceRouteOverviewSystem.gd` no longer uses `state.get(...)` fallbacks for active CampaignState-owned palace/calendar data.

It now prefers:

- `get_palace_dedicated_god()`
- `get_palace_structure_runtime_statuses()`
- `get_current_veintena()`
- CampaignState helper access through `_get_campaign_state()` where a public TRGameState method is unavailable

The following mirror-style reads were removed from active logic:

- `state.get("player_palace_dedicated_god")`
- `state.get("palace_structure_runtime_statuses")`
- `state.get("current_veintena")`

## What did not change

No gameplay balance changed.

This patch does not change:

- Tlaloc forecast events
- Tezcatlipoca pressure scoring
- Quetzalcoatl legitimacy rows
- palace route texts
- UI layout
- market behaviour
- rival behaviour

## Why this is safe

This is an information-only system. It reads palace and calendar state to produce route overview dictionaries; it does not mutate live state.

TRGameState mirrors still remain for compatibility elsewhere. This patch only removes one more external system's dependence on mirror reads.
