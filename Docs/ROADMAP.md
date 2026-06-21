# Tlaloc's Reign — Development Roadmap

Last updated: 2026-06-21  
Current milestone: Patch 8L / v0.48.0 — Clean Architecture Baseline

This roadmap starts from the post-architecture-cleanup project state. The architecture stabilisation sequence from Patch 8A through Patch 8L is now considered complete enough to resume gameplay development.

---

## 1. Completed architecture stabilisation

### Patch 8A — Architecture Truth Pass

Updated repo truth and created the clean architecture baseline documentation.

### Patch 8B — Shared War Doctrine Rules

Created `WarDoctrineRules.gd` as the single source of truth for Flower War / Warband doctrine values.

### Patch 8C — UI Screen Context

Created `UIScreenContext.gd` so extracted screen controllers use a shared context rather than long ad-hoc parameter lists.

### Patch 8D — Religion Runtime Ownership

Moved active religion-state access out of Shrine UI ownership and into runtime-backed access.

### Patch 8E — CampaignState Scaffold

Strengthened `CampaignState.gd` as the future live/save-state owner.

### Patch 8F — Turn / Calendar Ownership Cleanup

Moved ordinary Veintena and Nemontemi resolution out of `GameScreenMarketOverviewPatch.gd` and into `TurnResolutionSystem.gd`.

### Patch 8G — CampaignState Authority Pass

Made CampaignState authoritative for calendar/report state:

- `current_veintena`
- `calendar_period`
- `ritual_year`
- `last_report`
- `last_turn_summary`

### Patch 8H — Religion State into CampaignState

Made `CampaignState.religion_state` the save/load-facing religion-state container.

### Patch 8H Hotfix — Religion Decay Turn Runtime

Restored divine favour decay from the new turn runtime path after turn ownership moved out of the UI.

### Patch 8I — GameState Legacy Decision

Removed `GameState` from active autoloads and marked `GameState.gd` as a legacy shim.

### Patch 8J — Market Screen Controller Extraction

Moved market UI, Trade Basket wiring and Savvy Trade Prestige preview into `MarketScreenController.gd`.

### Patch 8K — Architecture Dead-Code Audit

Started cleanup of stale wrapper code and duplicate references.

### Patch 8K2 — Architecture Cleanup Completion

Completed the cleanup:

- wrapper preloads/constants cleaned
- stale comments cleaned
- Shrine UI decay methods marked legacy compatibility only
- `CampaignBridgeSystem` comments updated
- `MarketScreenController` stopped calling private Trade Basket methods
- `GameScreenStateDriven.gd` marked legacy / inactive

### Patch 8L — Documentation Refresh

Current patch. Records the final clean baseline.

---

## 2. Current architecture summary

```text
UI screens/widgets
  -> TRGameState public runtime facade
    -> Systems
      -> CampaignState live/save data
```

Current ownership:

| Area | Owner |
|---|---|
| Runtime facade | `TRGameState.gd` |
| Live/save state | `CampaignState.gd` |
| Legacy state shim | `GameState.gd` |
| Active UI coordinator | `GameScreenMarketOverviewPatch.gd` |
| Turn resolution | `TurnResolutionSystem.gd` |
| Religion state | `ReligionStateSystem.gd`, backed by `CampaignState.religion_state` |
| Doctrine values | `WarDoctrineRules.gd` |
| Market UI | `MarketScreenController.gd` |
| Palace UI | `PalaceScreenController.gd` |
| Barracks / Warband UI | `BarracksScreenController.gd` |
| Shrine UI | `ShrineScreenController.gd` |

---

## 3. Roadmap principles from here

### Build on the clean structure

New systems should follow the current dependency direction:

```text
UI -> TRGameState -> Systems -> CampaignState
```

### Do not add gameplay rules to the wrapper

`GameScreenMarketOverviewPatch.gd` is a coordinator only.

### Make turn outcomes readable

The next gameplay objective is not more systems depth. It is showing clearly what happened each Veintena.

### Keep Prototype 0 narrow

Do not attempt full game AI, full event libraries or deep save/load polish until the first Ritual Year loop is readable and playable.

---

## 4. Next development sequence

| Patch | Milestone | Main goal |
|---|---|---|
| Patch 9 | Structured Veintena Results Summary | Display turn summary sections clearly after each Veintena. |
| Patch 10 | Rival Prototype 1 | Make rivals visible economic actors with stockpiles, procurement caps and simple reports. |
| Patch 11 | Warband Progression Connection | Connect XP, injuries and skill web effects more fully to Flower War outcomes. |
| Patch 12 | Religion Loop Consolidation | Make offerings, favour decay, shrine upgrades and festival pressure feel like a real recurring loop. |
| Patch 13 | Palace / Recognition Loop Pass | Make palace route, ruler demands and recognition pressure clearer across the year. |
| Patch 14 | First Full Ritual Year Playtest | Ensure 18 Veintenas + Nemontemi can be played coherently. |
| Patch 15 | Balance and Readability Pass | Tune economy, Prestige, war, religion and rivals after the year loop is visible. |
| Patch 16 | Prototype 0 Vertical Slice | Package a coherent one-year playable prototype. |

---

## 5. Patch 9 — Structured Veintena Results Summary

### Goal

Turn resolution already creates `last_turn_summary`. Patch 9 should make that summary visible and useful.

### Required UI

Create a reusable panel or modal such as:

```text
Scripts/ui/widgets/VeintenaResultsSummaryPanel.gd
```

It should appear after advancing a Veintena and show clear sections.

### Required sections

- Calendar
- Population Upkeep
- Housing Maintenance
- Palace Maintenance
- Building Operations
- Warband Recovery
- Religion
- Stockpile Changes
- Court Needs
- Warnings
- Next Veintena / Nemontemi

### Success criteria

- The player knows what changed.
- The player knows why it changed.
- Divine favour decay is visible.
- Stockpile changes are readable.
- Upkeep and production are understandable.
- The summary can accept rival reports later without redesign.

---

## 6. Patch 10 — Rival Prototype 1

### Goal

Make rivals visible economic competitors rather than decorative score entries.

### Required mechanics

- Rival stockpiles.
- Fixed first-year build orders.
- Procurement caps.
- Personality hoards.
- True-surplus selling.
- Simple blocked-build fallback behaviour.
- Rival Prestige movement.
- Rival action lines in Veintena Results Summary.

### Rival identities

| Rival | Build direction |
|---|---|
| War Rival | Weapon Yard -> Warrior House -> Captive Holding Pen -> Huitzilopochtli support |
| Cunning Rival | Storehouse / Market Storage -> Tool Workshop -> Cloth Workshop -> Cacao access |
| Diplomatic Rival | Fine Textile House -> Noble Residence -> Cacao expansion -> Quetzalcoatl support |

---

## 7. Patch 11 — Warband Progression Connection

### Goal

Make persistent warbands matter.

### Required work

- XP gain after Flower Wars.
- Rank thresholds.
- Injury and recovery pressure.
- Skill web node effects affecting combat or rewards.
- Better loss reports.
- Clear veteran value.

### Success criteria

- The Warband Skill Web is not just UI.
- Injuries and deaths matter emotionally and strategically.
- Doctrine identity remains clear.
- Effects still use `WarDoctrineRules.gd` for baseline values.

---

## 8. Patch 12 — Religion Loop Consolidation

### Goal

Make religion a recurring strategic loop rather than a static shrine panel.

### Required work

- Clear favour decay reporting.
- Ritual capacity reporting.
- Shrine upgrade effects visible.
- Festival relevance by Veintena.
- Offering trade-offs.
- Sacrifice consequences.
- Religion entries in Veintena Results Summary.

### Success criteria

- The player understands which god is being neglected.
- Upgrades visibly reduce pressure or improve capacity.
- Ritual choices compete with economy, palace and war needs.

---

## 9. Patch 13 — Palace / Recognition Loop Pass

### Goal

Make the palace path and recognition race more legible.

### Required work

- Improve ruler/court-need reporting.
- Show delivery value and Prestige consequences clearly.
- Show Palace route authority effects more concretely.
- Improve route-power feedback for the four gods.
- Prepare for Level 4 palace victory requirement later.

---

## 10. Patch 14 — First Full Ritual Year Playtest

### Goal

Make one full Ritual Year playable from Veintena 1 through Nemontemi.

### Required checks

- Turn loop remains stable for 18 Veintenas.
- Nemontemi transitions correctly to next Ritual Year.
- Divine favour decays every turn.
- Stockpiles move logically.
- Buildings operate or fail for readable reasons.
- Palace demand pressure appears.
- Rivals move enough to feel present.
- Flower Wars remain optional but meaningful.

---

## 11. Patch 15 — Balance and Readability Pass

### Goal

Tune the first-year experience after the loop is visible.

### Test questions

- Can the player pursue a war route?
- Can the player pursue a palace/diplomatic route?
- Can the player pursue a shrine/religion route?
- Does the economy punish bad planning without becoming opaque?
- Do rivals pressure the market without overwhelming the player?
- Is Savvy Trade useful but not dominant?
- Are shortages visible before they become failures?

---

## 12. Patch 16 — Prototype 0 Vertical Slice

### Goal

Package a coherent one-year playable prototype.

Prototype 0 should prove:

- estate production works
- stockpiles matter
- market trade matters
- Prestige is readable
- Palace route matters
- Flower Wars are usable
- religion pressure matters
- rivals visibly compete
- Veintena summaries explain the game

---

## 13. Later, not now

Do not prioritise these until after the vertical slice:

- full save/load polish
- large event libraries
- deep AI rival decision trees
- Tezcatlipoca sabotage system
- major art/audio polish
- tutorial/onboarding
- multiple-year victory balance
