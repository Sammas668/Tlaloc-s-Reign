# Tlaloc's Reign — Changelog

This changelog records implementation milestones for the Godot Prototype 0 project.

---

## Patch 8L / v0.48.0 — Documentation Refresh / Clean Architecture Baseline

Status: current baseline.

### Added

- Updated final clean architecture baseline documentation after the full Patch 8A–8K2 cleanup sequence.
- Recorded the final current architecture:
  - `TRGameState` = public runtime facade
  - `CampaignState` = live/save-state owner
  - `GameState` = legacy shim, not active autoload
  - `GameScreenMarketOverviewPatch` = UI coordinator
  - `TurnResolutionSystem` = turn owner
  - `ReligionStateSystem` = CampaignState-backed religion state
  - `WarDoctrineRules` = doctrine source of truth
  - `MarketScreenController`, `PalaceScreenController`, `BarracksScreenController`, `ShrineScreenController` = extracted screen controllers

### Changed

- Updated `Docs/CURRENT_BASELINE.md`.
- Updated `Docs/ROADMAP.md`.
- Updated `Docs/Architecture/Clean_Architecture_Baseline.md`.
- Updated this changelog to reflect the full architecture stabilisation sequence.
- Reframed next development as Patch 9: Structured Veintena Results Summary.

### Notes

- Documentation-only patch.
- No runtime behaviour changes.
- Architecture is now considered clean enough to resume gameplay development.

---

## Patch 8K2 — Architecture Cleanup Completion

Status: completed.

### Changed

- Cleaned leftover wrapper references to extracted systems/widgets.
- Cleaned stale wrapper header comments.
- Marked Shrine UI favour-decay methods as legacy compatibility only.
- Confirmed authoritative divine favour decay belongs in `TurnResolutionSystem`.
- Updated stale `CampaignBridgeSystem` comments.
- Stopped `MarketScreenController.gd` from calling the private `TradeBasketView._trade_pricing()` method.
- Marked `GameScreenStateDriven.gd` as legacy / inactive.

### Notes

- This patch completed the architecture cleanup started in Patch 8K.

---

## Patch 8K — Architecture Dead-Code and Duplicate-Constant Audit

Status: completed / superseded by 8K2 completion.

### Changed

- Began cleanup of stale wrapper constants, preloads and comments.
- Identified remaining cleanup targets completed in Patch 8K2.

---

## Patch 8J — Market Screen Controller Extraction

Status: completed.

### Added

- Added `Scripts/ui/screens/MarketScreenController.gd`.

### Changed

- Moved market main-view routing into `MarketScreenController.gd`.
- Moved Trade Basket wiring into `MarketScreenController.gd`.
- Moved Savvy Trade Prestige preview UI into `MarketScreenController.gd`.
- Kept `TradeBasketView.tscn` as the view component.
- Kept market pricing, trade validation, trade application and Prestige rules in backend state/systems.

---

## Patch 8I — GameState Legacy Decision

Status: completed.

### Changed

- Removed `GameState` from active autoloads.
- Left `TRGameState` as the active runtime facade autoload.
- Converted `Scripts/state/GameState.gd` into a legacy shim.
- Updated main menu routing to prefer `TRGameState`.

---

## Patch 8H Hotfix — Religion Decay Turn Runtime

Status: completed.

### Fixed

- Restored divine favour decay after turn ownership moved out of the UI wrapper.
- Ordinary Veintenas apply normal divine favour decay.
- Nemontemi applies stronger end-year decay.
- Ritual capacity resets after turn resolution.
- Decay uses the CampaignState-backed religion state.

---

## Patch 8H — Religion State into CampaignState

Status: completed.

### Changed

- Made `CampaignState.religion_state` the save/load-facing home for religion state.
- Updated `ReligionStateSystem.gd` to bind to CampaignState.
- Updated `UIScreenContext.gd` to prefer CampaignState-backed religion state.
- Updated `ShrineScreenController.gd` so Shrine UI does not own live religion state.

---

## Patch 8G — CampaignState Authority Pass

Status: completed.

### Changed

- Made CampaignState the authority for:
  - `current_veintena`
  - `calendar_period`
  - `ritual_year`
  - `last_report`
  - `last_turn_summary`
- Updated `CampaignBridgeSystem.gd` so calendar/report state is preserved from CampaignState rather than overwritten by TRGameState compatibility mirrors.
- Updated turn/calendar UI reads to prefer CampaignState snapshots.

---

## Patch 8F — Turn / Calendar Ownership Cleanup

Status: completed.

### Changed

- Removed wrapper-owned turn/calendar resolution.
- Moved ordinary Veintena and Nemontemi resolution to `TurnResolutionSystem.gd`.
- Advance button now delegates to runtime state.
- Calendar widgets and Shrine festival focus read from runtime/CampaignState rather than wrapper-owned variables.

---

## Patch 8E — CampaignState Scaffold

Status: completed.

### Added

- Strengthened `Scripts/state/CampaignState.gd`.

### Changed

- Added scaffold containers for:
  - calendar period
  - ritual year
  - last turn summary
  - religion state
  - rival houses
  - rival stockpiles
  - rival build progress
  - rival action history

---

## Patch 8D — Religion Runtime Ownership

Status: completed.

### Changed

- Stopped Shrine UI from owning its own mutable religion-state instance.
- Added runtime-owned religion-state access through `UIScreenContext`.
- Kept metadata only as a temporary fallback.

---

## Patch 8C — UI Screen Context

Status: completed.

### Added

- Added `Scripts/ui/UIScreenContext.gd`.

### Changed

- Updated Palace, Barracks and Shrine controllers to use shared context.
- Reduced ad-hoc dependency passing.

---

## Patch 8B — Shared War Doctrine Rules

Status: completed.

### Added

- Added `Scripts/Systems/WarDoctrineRules.gd`.

### Changed

- Centralised doctrine values.
- Confirmed Otomi as offence 0.8 / defence 1.5.

---

## Patch 8A — Architecture Truth Pass

Status: completed.

### Added

- Added `Docs/Architecture/Clean_Architecture_Baseline.md`.

### Changed

- Updated baseline and roadmap so the repo no longer described itself as v0.42.
- Recorded extracted controllers and the new architecture cleanup path.

---

## Earlier architecture and gameplay patches

The earlier patch sequence established:

- Market scarcity floor at 0.50.
- `TRGameState` runtime autoload stabilisation.
- wrapper containment rules.
- Warband Skill Web extraction.
- Flower War event overlay extraction.
- Calendar pacing controller extraction.
- Shrine ritual rules extraction.
- Palace presentation rules extraction.
- Otomi doctrine correction/revert.
- Palace UI extraction.
- Barracks UI extraction.
- Religion state extraction.
- Shrine UI extraction.

These are now absorbed into the Patch 8L clean architecture baseline.
