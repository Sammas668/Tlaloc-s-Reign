# CampaignState Migration — v0.44.0 Scaffold

## Purpose

This patch begins the next shrink phase after the v0.43 architecture split.

`TRGameState.gd` has already stopped owning many rule bodies, but it still owns the live campaign/save data. The next real shrink comes from introducing `CampaignState.gd` as the future live-state container.

## What v0.44.0 adds

- `Scripts/state/CampaignState.gd`

This is a scaffold only. It is not wired into `TRGameState.gd` yet.

## Why this path is lower-case `Scripts/state`

The repository already contains `Scripts/state/GameState.gd`, so this patch uses the existing lower-case state folder rather than creating a second `Scripts/State` folder.

## Intended architecture

```text
UI
↓
TRGameState compatibility API, temporary
↓
CampaignState live save data
↓
Systems own rules
```

Later, once the compatibility layer is no longer needed, `TRGameState.gd` can be renamed, removed, or reduced to a very thin bridge.

## What CampaignState should own

- Calendar / turn counters
- Estate stockpiles
- Market stockpiles
- Market demand
- Estate buildings
- Active housing counts
- Population
- Base housing capacity
- Labour assignments
- Palace dedication and structure state
- Palace court-need donations
- Prestige state and history
- Sacrifice records
- Warband / Flower War state
- Rival state
- Recent reports

## What CampaignState should not own

- Prestige formulas
- Market pricing formulas
- Production formulas
- Housing rules
- Palace rule logic
- Religion/sacrifice formulas
- Flower War combat formulas
- Rival AI/procurement rules
- UI layout logic

Those belong in system files.

## v0.44 migration plan

### v0.44.0 — CampaignState scaffold

Add `CampaignState.gd` without wiring it in. No gameplay changes.

### v0.44.1 — TRGameState owns a CampaignState instance

Add a `campaign_state` variable to `TRGameState.gd` and initialise it, but keep existing direct variables for compatibility.

### v0.44.2 — Mirror start-state loading into CampaignState

After loading JSON, copy start-state data into `campaign_state`. Use it as a verified mirror first.

### v0.44.3 — Move first live-state reads to CampaignState

Start with safe state such as calendar/report values, then stockpiles.

### v0.44.4+ — Replace direct TRGameState state variables gradually

Move one state family at a time:

1. Calendar/report state
2. Stockpiles/market demand
3. Buildings/housing/population/labour
4. Palace/prestige/religion records
5. Warband/Flower War/rival state

## Safety rule

Do not remove a direct `TRGameState.gd` state variable until:

1. The equivalent CampaignState field exists.
2. It is initialised correctly.
3. UI calls still pass through `TRGameState.gd`.
4. The current screen using that data has been tested in Godot.
