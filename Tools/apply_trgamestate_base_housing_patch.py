#!/usr/bin/env python3
from pathlib import Path

path = Path("Scripts/Autoload/TRGameState.gd")
if not path.exists():
    raise SystemExit("Could not find Scripts/Autoload/TRGameState.gd. Run this from the Godot project root.")

text = path.read_text(encoding="utf-8")
old = """func _ensure_base_housing_capacity() -> void:
\tfor group_variant: Variant in population.keys():
\t\tvar group_id: String = String(group_variant)
\t\tif not base_housing_capacity.has(group_id):
\t\t\tbase_housing_capacity[group_id] = int(population[group_id])
"""
new = """func _ensure_base_housing_capacity() -> void:
\tfor group_variant: Variant in population.keys():
\t\tvar group_id: String = String(group_variant)
\t\tif not base_housing_capacity.has(group_id):
\t\t\t# Missing base capacity should not silently house the population.
\t\t\t# Starting housing now comes from start_state estate_buildings +
\t\t\t# active_housing_counts, so future/new groups default to 0 unless
\t\t\t# the start data explicitly grants inherited base capacity.
\t\t\tbase_housing_capacity[group_id] = 0
"""
if old not in text:
    raise SystemExit("Patch target not found. The file may already be patched or has changed.")

path.write_text(text.replace(old, new), encoding="utf-8")
print("Patched Scripts/Autoload/TRGameState.gd: missing base housing capacity now defaults to 0.")
