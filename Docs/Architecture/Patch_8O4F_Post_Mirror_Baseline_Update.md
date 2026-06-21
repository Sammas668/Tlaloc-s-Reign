# Patch 8O4F — Post-Mirror Baseline Documentation Update

Status: ready to apply  
Date: 2026-06-21

---

## Purpose

Patch 8O4F updates the repo documentation after the 8O3 mirror-deletion series and the 8O4A–8O4E post-mirror cleanup passes.

The previous baseline still described `TRGameState` compatibility mirrors and transitional bridge sync as acceptable migration debt. That is no longer accurate after the mirror removal work.

---

## Files updated

```text
Docs/CURRENT_BASELINE.md
Docs/ROADMAP.md
Docs/CHANGELOG.md
Docs/Architecture/Clean_Architecture_Baseline.md
```

This patch also adds this note:

```text
Docs/Architecture/Patch_8O4F_Post_Mirror_Baseline_Update.md
```

---

## New architecture statement

The active dependency direction is:

```text
UI screens/widgets
  -> TRGameState public runtime facade
    -> Systems
      -> CampaignState live/save data
```

`TRGameState` is a facade only.

`CampaignState` is the live/save-state owner.

`CampaignBridgeSystem` is no longer a broad live-state synchroniser.

`GameState.gd` is a retired forwarder only.

---

## Do not restore

Future patches should not restore:

- `TRGameState` live-state compatibility mirrors
- broad `copy_from_game_state()` import paths
- broad `apply_to_game_state()` write-back paths
- religion metadata seeding as an authority path
- rival prestige fallback reads/writes through `TRGameState` fields
- direct `state.get()` / `state.set()` access to deleted mirror fields
- broad sync calls in read paths
- GDScript property getters/setters for state migration

---

## 8O4 sequence status

Completed before this documentation patch:

- 8O4A — removed broad `apply_to_game_state` usage.
- 8O4B — removed CampaignState mirror helpers.
- 8O4C — cleaned religion mirror/fallback paths.
- 8O4D — cleaned rival mirror/fallback paths.
- 8O4E — converted legacy `GameState.gd` into a pure forwarder.

This patch:

- 8O4F — updates documentation and architecture baseline.

Remaining:

- 8O4G — final grep audit.

---

## Next step

Run 8O4G before returning to gameplay feature work.

The final audit should search for:

```text
state.get(
state.set(
mirror_
compatibility mirror
legacy mirror
fallback
copy_from_game_state
apply_to_game_state
```

Expected result: active code should not depend on deleted mirrors. Any remaining occurrences should be either safe no-op compatibility hooks, legacy pure-forwarder text, documentation history, or non-architecture lore wording.
