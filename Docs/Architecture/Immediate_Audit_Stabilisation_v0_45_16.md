# Immediate Audit Stabilisation v0.45.16

This note records the immediate stabilisation pass agreed after the project audit.

## Completed patches

### Patch 1 — Market scarcity floor

Canonical scarcity-price floor is now:

```text
0.50
```

The old `0.75` value should not be used as a price floor. Any remaining `0.75` values should only be UI pressure thresholds or unrelated balance values.

### Patch 2 — Otomi doctrine correction

Canonical Otomi doctrine values are now:

```text
Offence 1.0
Defence 1.5
```

Otomi should be defensive veterans who preserve warriors without falling below baseline offence.

### Patch 3 — TRGameState runtime autoload stabilisation

`TRGameState` should be present as the active runtime autoload while `GameState` remains in place as legacy/formal architecture.

`MainMenu.gd` should prefer `/root/TRGameState` when starting a new game.

## Patch 4 — UI wrapper containment

`GameScreenMarketOverviewPatch.gd` remains the active gameplay UI wrapper for now, but it should not absorb new gameplay rules.

New gameplay rules go in:

```text
Scripts/Systems/
```

New reusable UI widgets go in:

```text
Scripts/ui/widgets/
```

New reusable screen panels go in:

```text
Scripts/ui/screens/
```

## Next recommended patch

Patch 5 should be the first real shrink of the wrapper.

Recommended target:

```text
Scripts/ui/widgets/WarbandSkillWebCanvas.gd
```

This should be a behaviour-preserving extraction only.
