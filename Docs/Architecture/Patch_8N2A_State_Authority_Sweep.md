# Patch 8N2A — Economy System Dependency Sweep

This patch is the first safe slice of the broader Patch 8N2 system dependency sweep.

It updates the economy-facing systems that most directly read stockpile / market / production state:

- `ProductionSystem.gd`
- `StorehouseSystem.gd`
- `MarketEconomySystem.gd`
- `MarketTradeSystem.gd`

## What changed

These systems now prefer CampaignState-backed access through `TRGameState` bridge/accessors for:

- estate stockpiles
- market stockpiles
- market demand
- resources
- resource order
- buildings
- building order
- estate building counts
- last-report appending after accepted trades

TRGameState dictionary fallback remains only for compatibility.

## What did not change

This patch does not change:

- prices
- scarcity values
- production outputs
- upkeep values
- barter validation
- Savvy Trade Prestige rules
- turn order
- UI layout

## Why Patch 8N2 is split

The full sweep touches many systems. Doing all of them in one drag-and-drop patch would be high risk.

Recommended next slices:

1. `8N2B` — Housing / Labour / EstateBuilding systems.
2. `8N2C` — Palace / Warband / FlowerWar / Rival systems.
3. `8N3` — TRGameState mirror removal / facade conversion after all systems have been migrated and tested.

Do not start 8N3 until 8N2A, 8N2B and 8N2C have each been smoke-tested.
