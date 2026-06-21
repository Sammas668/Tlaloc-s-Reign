# GameScreenMarketOverviewPatch Containment — Patch 4

## Purpose

`Scripts/ui/GameScreenMarketOverviewPatch.gd` is the current active gameplay UI wrapper. It is allowed to coordinate screens, refresh panels, call systems, and pass data between UI widgets and the live runtime state.

It should **not** continue absorbing new gameplay rules.

This patch deliberately avoids replacing the huge active wrapper file. The goal is to create a clear architecture boundary without risking a large UI break.

## Current rule

New gameplay rule logic belongs in:

```text
Scripts/Systems/
```

New reusable UI panels or widgets belong in:

```text
Scripts/ui/widgets/
Scripts/ui/screens/
```

`GameScreenMarketOverviewPatch.gd` may call those systems/widgets, but it should not become the permanent home for new mechanics.

## Allowed responsibilities for the wrapper

The wrapper may:

- route button presses,
- open and close panels,
- refresh visible UI text,
- call public methods on `TRGameState`,
- call extracted systems through `TRGameState`,
- connect signals,
- translate system results into player-facing labels,
- temporarily coordinate legacy UI while the prototype stabilises.

## Disallowed responsibilities for the wrapper

Do not add new logic here for:

- market pricing formulas,
- resource production formulas,
- stockpile mutation rules,
- Flower War combat formulas,
- prestige scoring formulas,
- palace route powers,
- shrine/favour calculations,
- rival procurement/build-order behaviour,
- save-state ownership,
- warband XP/trait effects,
- new event resolution rules.

Those should be placed in `Scripts/Systems/` and called from the wrapper.

## Immediate extraction priority

The safest first real shrink target is the Warband Skill Web canvas/UI class, because it is a UI object rather than core runtime state.

Recommended next extraction target:

```text
Scripts/ui/widgets/WarbandSkillWebCanvas.gd
```

The extraction should be behaviour-preserving:

1. Move the canvas class into its own script.
2. Preload it from `GameScreenMarketOverviewPatch.gd`.
3. Replace local `WarbandSkillWebCanvas.new()` calls with the preloaded script.
4. Do not change skill-node effects yet.
5. Do not redesign the visual web during extraction.
6. Test pan, zoom, hover and selection after the move.

## Future extraction order

Recommended order after this containment patch:

1. Warband Skill Web canvas/widget extraction.
2. Shrine/offering panel extraction.
3. Market trade basket UI extraction.
4. Palace route UI extraction.
5. Rival dashboard UI extraction after rival AI/procurement is actually implemented.

## State boundary

The wrapper should treat `TRGameState` as the active runtime-facing API during the current migration.

`CampaignState` is the future live/save-state owner, but the wrapper should not directly manage that migration. It should call public runtime methods rather than mutate deep state directly wherever possible.

## Test checklist after containment

Because this patch is documentation-only, it should not change runtime behaviour. After applying it, simply confirm the project still opens and the docs are visible in the repo.

Before any later extraction patch, test:

- main menu starts,
- new game opens the game screen,
- storehouse tab opens,
- market tab opens,
- trade basket still works,
- shrine tab opens,
- palace tab opens,
- warriors tab opens,
- warband skill web opens,
- Flower War preview still works,
- advance Veintena still works.
