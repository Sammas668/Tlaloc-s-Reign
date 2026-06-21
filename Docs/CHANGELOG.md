# Tlaloc's Reign — Changelog

This changelog records implementation milestones for the Godot Prototype 0 project.

---

## Patch 8O4F — Post-Mirror Documentation Baseline

Status: current baseline.

### Changed

- Updated `Docs/CURRENT_BASELINE.md` to reflect the post-8O3/8O4 architecture.
- Updated `Docs/Architecture/Clean_Architecture_Baseline.md` so it no longer describes active `TRGameState` compatibility mirrors as acceptable migration debt.
- Updated `Docs/ROADMAP.md` so the next technical step is 8O4G final grep audit before Patch 9 gameplay work.
- Added `Docs/Architecture/Patch_8O4F_Post_Mirror_Baseline_Update.md` as the patch-specific architecture note.

### Clarified

- `TRGameState` is now a public runtime facade only.
- `CampaignState` is the live/save-state owner.
- `CampaignBridgeSystem` is no longer a broad state synchroniser.
- `GameState.gd` is a retired forwarder only.
- Live-state mirrors must not be restored on `TRGameState`.
- Broad `copy_from_game_state()` / `apply_to_game_state()` style sync paths are retired.

### Notes

- Documentation-only patch.
- No runtime behaviour changes.
- 8O4G remains the final verification step for stale `state.get`, `state.set`, `mirror`, `legacy` and `fallback` artefacts.

---

## Patch 8O4E — Legacy GameState Pure Forwarder

Status: completed.

### Changed

- Kept `Scripts/state/GameState.gd` as a safe retired forwarder rather than deleting it.
- Removed direct inspection of old `TRGameState` fields from the legacy path.
- Preserved soft forwarding to `/root/TRGameState` for older calls.

---

## Patch 8O4D — Rival Mirror/Fallback Cleanup

Status: completed.

### Changed

- Removed rival mirror write-back from the bridge path.
- Removed old rival prestige fallback reads/writes through `TRGameState` fields.
- Kept rival state CampaignState-direct.

---

## Patch 8O4C — Religion Mirror/Fallback Cleanup

Status: completed.

### Changed

- Removed religion metadata seeding and mirror write-back from the bridge path.
- Removed religion-system calls to old mirror refresh hooks.
- Kept religion state CampaignState-direct.

---

## Patch 8O4B — Remove CampaignState Mirror Helpers

Status: completed.

### Changed

- Removed broad `CampaignState` helpers that copied from or wrote to a game-state node.
- Removed domain-specific `mirror_*_to_game_state` helpers.

---

## Patch 8O4A — Remove Broad apply_to_game_state Usage

Status: completed.

### Changed

- Removed active usage of broad `CampaignState.apply_to_game_state()` during project-data loading.
- Converted the bridge application path into a no-op compatibility hook.

---

## Patch 8O3A-G — TRGameState Mirror Deletion Series

Status: completed.

### Changed

- Removed `TRGameState` live-state mirrors across:
  - calendar/report
  - prestige
  - palace
  - stockpiles
  - estate/population/labour
  - warband and Flower War reports
  - static resources/buildings and market demand/economy

---

## Patch 8L / v0.48.0 — Documentation Refresh / Clean Architecture Baseline

Status: superseded by 8O4F post-mirror documentation.

### Added

- Updated final clean architecture baseline documentation after the full Patch 8A–8K2 cleanup sequence.
- Recorded the first clean architecture baseline:
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
- This baseline was later superseded by the 8O3/8O4 post-mirror architecture cleanup.

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

Status: completed / superseded by 8O4E.

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

Status: completed / superseded by 8O4C cleanup.

### Changed

- Made `CampaignState.religion_state` the save/load-facing home for religion state.
- Updated `ReligionStateSystem.gd` to bind to CampaignState.
- Updated `UIScreenContext.gd` to prefer CampaignState-backed religion state.
- Updated `ShrineScreenController.gd` so Shrine UI does not own live religion state.

---

## Patch 8G — CampaignState Authority Pass

Status: completed / superseded by 8O3A and 8O4A-B cleanup.

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

Status: completed / superseded by 8H and 8O4C.

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
