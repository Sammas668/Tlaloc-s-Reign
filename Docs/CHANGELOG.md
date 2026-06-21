# Tlaloc's Reign — Changelog

This changelog records implementation milestones for the playable Godot prototype.

The project is still in Prototype 0. Version numbers and patch numbers here are development checkpoints, not public release versions.

## Patch 8A / v0.47.5 — Architecture Truth Pass

Status: current baseline.

### Added

- Added `Docs/Architecture/Clean_Architecture_Baseline.md`.
- Recorded the current extracted UI architecture:
  - `Scripts/ui/screens/PalaceScreenController.gd`
  - `Scripts/ui/screens/BarracksScreenController.gd`
  - `Scripts/ui/screens/ShrineScreenController.gd`
  - `Scripts/ui/widgets/FlowerWarEventOverlay.gd`
  - `Scripts/ui/widgets/WarbandSkillWebCanvas.gd`
  - `Scripts/ui/widgets/CalendarPacingController.gd`
- Recorded extracted rule/presentation/state helpers:
  - `Scripts/Systems/MarketPricingRules.gd`
  - `Scripts/Systems/ShrineRitualRules.gd`
  - `Scripts/Systems/ReligionStateSystem.gd`
  - `Scripts/Systems/PalacePresentationRules.gd`
- Recorded the next architecture-cleanup sequence:
  - shared doctrine rules
  - UI screen context
  - religion runtime ownership
  - CampaignState scaffold
  - turn/calendar ownership cleanup
  - controller/dead-code audit

### Changed

- Updated `CURRENT_BASELINE.md` so the project is no longer described as v0.42.
- Updated `ROADMAP.md` so the next work is architecture stabilisation before more gameplay.
- Reframed `GameScreenMarketOverviewPatch.gd` as an active coordinator/wrapper, not a place for new gameplay rules.
- Clarified that `TRGameState.gd` is the active runtime facade.
- Clarified that `GameState.gd` is the legacy / older state path.
- Clarified that religion live state has been extracted from the wrapper but still needs runtime ownership cleanup.
- Confirmed Otomi doctrine baseline as 0.8 offence / 1.5 defence.
- Confirmed market scarcity floor baseline as 0.50.

### Notes

- This is a documentation / source-of-truth patch only.
- No gameplay balance or runtime behaviour should change from this patch.
- The next code patch should be Patch 8B: shared `WarDoctrineRules.gd`.

## Patch 7E — Shrine UI Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/screens/ShrineScreenController.gd`.

### Changed

- Moved Shrine / Religion UI composition out of `GameScreenMarketOverviewPatch.gd`.
- Kept shrine art routing in the wrapper because it is tied to the main screen background system.
- Kept `ShrineRitualRules.gd` as the static rule/balance source.
- Kept `ReligionStateSystem.gd` as the mutable Prototype 0 religion state holder.

## Patch 7D — Religion State Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/Systems/ReligionStateSystem.gd`.

### Changed

- Moved mutable religion state out of `GameScreenMarketOverviewPatch.gd`, including:
  - divine favour
  - shrine levels
  - shrine upgrades
  - ritual capacity used this Veintena
  - recent ritual/offering report lines

### Remaining

- Runtime ownership still needs cleanup. The religion-state instance should be owned by `TRGameState` / future `CampaignState`, not by a UI screen controller.

## Patch 7C — Barracks UI Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/screens/BarracksScreenController.gd`.

### Changed

- Moved Barracks / Warbands / Flower War bridge UI out of `GameScreenMarketOverviewPatch.gd`.
- Kept Flower War event modal in `FlowerWarEventOverlay.gd`.
- Kept Warband Skill Web canvas in `WarbandSkillWebCanvas.gd`.

### Fixed

- Hotfixed `FlowerWarEventOverlay.gd` so the Flower War event host can be an extracted controller object.
- Confirmed Flower War event flow still works after extraction.

## Patch 7B — Palace UI Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/screens/PalaceScreenController.gd`.

### Changed

- Moved Palace / Prestige / Divine Seat / Authority / Court Needs UI out of `GameScreenMarketOverviewPatch.gd`.
- Kept `PalacePresentationRules.gd` as the stable presentation rule helper.

## Patch 7A — Otomi Doctrine Revert

Status: implemented locally / architecture baseline recorded.

### Changed

- Reverted Otomi to:
  - offence 0.8
  - defence 1.5
- Confirmed Otomi is a defensive veteran doctrine that trades offence for survival.

## Patch 6D — Palace Presentation Rules Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/Systems/PalacePresentationRules.gd`.

### Changed

- Moved stable palace / prestige presentation text, colours, glyphs and formatting helpers out of the active wrapper.

### Fixed

- Added explicit preload usage so `PalacePresentationRules` resolves at parse time.

## Patch 6C — Shrine Ritual Rules Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/Systems/ShrineRitualRules.gd`.

### Changed

- Moved shrine and ritual static data out of the wrapper.

## Patch 6B — Calendar Pacing Controller Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/widgets/CalendarPacingController.gd`.

### Changed

- Moved calendar strip / Veintena card helper logic out of the wrapper.

## Patch 6A — Flower War Event Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/widgets/FlowerWarEventOverlay.gd`.

### Changed

- Moved the Flower War event flow out of the wrapper.
- Restored full-screen modal behaviour after layout hotfixes.

## Patch 5 — Warband Skill Web Canvas Extraction

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/ui/widgets/WarbandSkillWebCanvas.gd`.

### Changed

- Moved Warband Skill Web canvas out of the wrapper.

## Patch 4 — Wrapper Containment

Status: implemented locally / architecture baseline recorded.

### Changed

- Added active wrapper boundary comments to `GameScreenMarketOverviewPatch.gd`.
- Defined the rule that new gameplay logic belongs in `Scripts/Systems/`.
- Defined the rule that new screen/widget UI belongs in `Scripts/ui/screens/` or `Scripts/ui/widgets/`.

## Patch 3 — TRGameState Runtime Autoload Stabilisation

Status: implemented locally / architecture baseline recorded.

### Changed

- Added `TRGameState` as an explicit autoload alongside legacy `GameState`.
- Updated main-menu lookup so new-game reset prefers `TRGameState`.

## Patch 2 — Otomi Doctrine Correction

Status: superseded by Patch 7A.

### Changed

- Temporarily changed Otomi to 1.0 / 1.5 based on older baseline text.

### Superseded

- Patch 7A restores the intended doctrine identity: Otomi 0.8 / 1.5.

## Patch 1 — Market Scarcity Floor Unification

Status: implemented locally / architecture baseline recorded.

### Added

- Added `Scripts/Systems/MarketPricingRules.gd`.

### Changed

- Unified scarcity multiplier floor at 0.50.
- Removed old 0.75 scarcity-floor behaviour from market-pricing paths.

## v0.42 — Repository Baseline & Cleanup

Status: historical baseline.

### Added

- Added `CURRENT_BASELINE.md`.
- Added `ROADMAP.md`.
- Recorded the current active gameplay scene path:
  - `Scenes/Main/GameScreen.tscn`
- Recorded the active gameplay wrapper at the time:
  - `Scripts/ui/GameScreenMarketOverviewPatch.gd`
- Recorded the practical runtime state source:
  - `Scripts/Autoload/TRGameState.gd`
- Recorded design guardrails:
  - no abstract Wealth resource in MVP
  - Prestige is score / public recognition only and is never spent
  - Flower Wars should be capitalised as `Flower Wars`
  - rival houses are War Rival, Cunning Rival and Diplomatic Rival
  - the market does not replace estate stockpiles

### Removed

- Removed temporary Godot scene duplicate:
  - `Scenes/Main/GameScreen.tscn2577238696.tmp`
