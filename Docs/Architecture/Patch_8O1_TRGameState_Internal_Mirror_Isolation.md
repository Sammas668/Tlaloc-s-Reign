# Patch 8O1 — TRGameState Internal Mirror Isolation

## Purpose

This patch starts the safe removal path for TRGameState compatibility mirrors.

It does not delete the mirror variables yet. Instead, it stops TRGameState public/runtime methods from reading those mirrors internally wherever this can be done safely.

## Why this is not another 8N3

Patch 8N3 tried to replace mirror fields with GDScript property getters/setters. That caused lag because ordinary UI reads triggered many getter calls, dictionary copies and bridge syncs.

Patch 8O1 does not use property getters/setters.

Instead, it adds plain CampaignState-backed helper methods such as:

```gdscript
_campaign_resources()
_campaign_buildings()
_campaign_population()
_campaign_player_prestige()
```

These are ordinary methods, not properties.

## What changed in TRGameState.gd

TRGameState now reads CampaignState directly for its own internal logic in these paths:

- `_ready()` initialisation check
- `get_campaign_state_snapshot()` read path
- resource-name lookups
- building-name lookups
- building list lookups
- looted-goods validation
- dictionary-to-readable-name formatting
- warrior count
- estate stockpile read/write helpers
- market trade application post-processing
- player Prestige reads/writes
- rival Prestige reads/writes
- Prestige history reads
- sacrifice Prestige record capture
- Flower War report reads
- Flower War archive reads/writes
- auto-staff / labour-assignment post-processing
- Palace runtime-status / maintenance post-processing
- turn-advance post-processing

The old mirror fields still remain as compatibility fields for older UI/system paths.

## What did not change

No gameplay balance changed.

This patch does not change:

- production values
- housing values
- market pricing
- palace costs
- court needs
- religion decay
- Flower War maths
- warband doctrine
- UI layout

## What remains for 8O2

Other systems and UI may still use `state.get(...)` / `state.set(...)` against TRGameState compatibility fields.

That is deliberately not fixed here.

Patch 8O2 should migrate external systems/controllers away from mirror-style access.

## Success criteria

- Godot launches.
- New Game opens without new lag.
- Storehouse / Market / Housing / Palace / Shrines / Barracks still open.
- Advancing one Veintena still works.
- TRGameState mirrors still exist, but TRGameState itself no longer depends on them for the migrated internal paths.
