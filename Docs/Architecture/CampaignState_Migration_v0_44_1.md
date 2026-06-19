# CampaignState Migration v0.44.1 — Data Container Pass

This pass expands `Scripts/state/CampaignState.gd` into the future live campaign data container.

## Purpose

The previous architecture split moved many rule bodies out of `TRGameState.gd`, but `TRGameState.gd` still owns the live campaign state. This is why it remains large even after thousands of lines were removed.

`CampaignState.gd` is the next shrink target. It should eventually hold live save-game data while `TRGameState.gd` becomes a temporary compatibility API.

## What v0.44.1 adds

`CampaignState.gd` now defines explicit containers for:

- calendar and reports
- resource and building definitions
- estate and market stockpiles
- market demand and economy data
- estate buildings
- active housing counts
- population
- base housing capacity
- labour assignments
- palace dedication and palace structures
- palace court donations
- prestige and rival prestige
- sacrifice records
- warbands
- Flower War reports and archive

It also adds bridge helpers:

- `copy_from_game_state(game_state)`
- `apply_to_game_state(game_state)`
- `to_save_dictionary()`
- `apply_save_dictionary(data)`

## What this pass does not do

This pass does not wire `CampaignState` into `TRGameState.gd` yet.

No gameplay should change.

## Next pass

`v0.44.2 — TRGameState owns CampaignState instance`

That pass should add a `campaign_state` instance to `TRGameState.gd`, copy the current runtime data into it after `new_game()`, and keep it synchronised without yet removing the old variables.
