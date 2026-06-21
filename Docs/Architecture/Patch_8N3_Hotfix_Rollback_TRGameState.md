# Patch 8N3 Hotfix — Roll back TRGameState facade-property conversion

## Why this exists

Patch 8N3 converted TRGameState's top-level mirror dictionaries into CampaignState-backed GDScript properties. The game then crashed when opening a new game.

The likely cause is that New Game initialisation and/or Godot property access is touching TRGameState facade properties before CampaignState has completed the expected initialisation path.

## What this hotfix does

This hotfix restores the pre-8N3 `Scripts/Autoload/TRGameState.gd` file.

That means:

- New Game should return to the last working state.
- The 8N2A / 8N2B / 8N2C / 8N2D system migrations remain valid.
- Systems still prefer CampaignState first where we migrated them.
- TRGameState mirror fields remain temporarily as compatibility mirrors.

## What this hotfix does not do

It does not undo:

- ProductionSystem migration.
- Storehouse/Market migration.
- Housing/Labour/EstateBuilding migration.
- Warband/FlowerWar/Rival migration.
- PalaceSystem migration.

It only rolls back the risky TRGameState property conversion.

## Next step

After this hotfix, 8N3 should be redesigned as a safer staged conversion:

1. Add explicit public CampaignState-backed getters/setters.
2. Keep mirror variables during New Game initialisation.
3. Add a runtime audit function to confirm mirrors and CampaignState match.
4. Only remove/convert individual mirrors after each dependent path has been proven safe.
