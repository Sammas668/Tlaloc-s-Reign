# Patch 8N3 — TRGameState Facade Conversion

This patch converts TRGameState's live-data mirrors into CampaignState-backed compatibility properties.

## Files

- `Scripts/Autoload/TRGameState.gd`

## Goal

The target architecture is now enforced more directly:

```text
TRGameState exposes methods and compatibility properties.
CampaignState owns live/save data.
Systems mutate CampaignState through bridge/accessors.
```

## What changed

The former independent TRGameState mirror fields are now property accessors backed by CampaignState.

This includes:

- resources
- resource order
- buildings
- building order
- estate stockpiles
- market stockpiles
- market demand
- estate buildings
- active housing counts
- population
- base housing capacity
- labour assignments
- market economy
- current Veintena
- calendar period
- ritual year
- last report
- last turn summary
- initialized state
- palace dedication
- palace structures
- palace runtime statuses
- court-need donation records
- palace maintenance report
- player Prestige
- rival Prestige
- Prestige history
- sacrifice Prestige records
- Flower War palace gate
- last Flower War report
- Flower War report archive
- warbands

## Why properties instead of deleting names outright?

Several UI and older compatibility paths still use `state.get(...)`, `state.set(...)` or direct property access. Removing the names outright would break those paths immediately.

The names now remain as facade compatibility properties, but reads and writes go through CampaignState.

## What did not change

No gameplay values changed.

This patch does not change:

- economy balance
- turn order
- production values
- palace costs
- religion decay
- Flower War doctrine
- warband stats
- UI layout

## Success criteria

- Godot launches without parser errors.
- New Game still loads.
- Storehouse, Market, Housing, Labour, Palace, Barracks and Shrines still open.
- Advancing a Veintena still works.
- Stockpiles and reports still update.
- `TRGameState` no longer owns independent live-data mirrors.
