# CampaignState Pre-Migration Checklist

Version: v0.43.21

Before moving live data out of `TRGameState.gd`, confirm this checklist.

## 1. Current extracted systems are stable

- [ ] PrestigeSystem tested
- [ ] MarketTradeSystem tested
- [ ] PopulationUpkeepSystem tested
- [ ] HousingSystem tested
- [ ] ProductionSystem tested
- [ ] TurnResolutionSystem tested
- [ ] PalaceSystem tested
- [ ] ReligionSystem tested
- [ ] WarbandSystem tested
- [ ] FlowerWarSystem tested
- [ ] RivalSystem tested

## 2. UI still uses TRGameState as public API

- [ ] Market screen works
- [ ] Trade Basket works
- [ ] Storehouse works
- [ ] Housing works
- [ ] Production works
- [ ] Palace tabs work
- [ ] Palace → Prestige works
- [ ] Palace → Court Needs works
- [ ] Shrine/sacrifice UI works
- [ ] Warriors/Warbands works
- [ ] Flower Wars work
- [ ] Rivals info remains visible

## 3. CampaignState first ownership targets

Move these first:

```text
current_veintena
last_report
estate_stockpiles
market_stockpiles
market_demand
estate_buildings
active_housing_counts
population
base_housing_capacity
labour_assignments
```

Do not move everything at once.

## 4. CampaignState second ownership targets

Move these after the basic state is stable:

```text
player_palace_dedicated_god
palace_built_structures
palace_structure_runtime_statuses
palace_ruler_demand_donations
player_prestige
rival_prestige
prestige_history
sacrifice_prestige_records
warbands
last_flower_war_report
flower_war_report_archive
```

## 5. Safety rule

For each moved variable:

```text
1. Add it to CampaignState.
2. Initialise it from the same start-state/default path.
3. Keep TRGameState getter/setter compatibility.
4. Test the relevant screen.
5. Only then remove the old direct TRGameState ownership.
```

## 6. Suggested v0.44 sequence

```text
v0.44.0 — CampaignState scaffold only
v0.44.1 — Move current Veintena, last_report and basic stockpile dictionaries
v0.44.2 — Move buildings/population/labour state
v0.44.3 — Move palace/prestige/rival state
v0.44.4 — Move warband/Flower War report state
v0.44.5 — TRGameState becomes compatibility wrapper over CampaignState
```
