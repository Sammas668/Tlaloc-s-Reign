# PopulationUpkeepSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PopulationUpkeepSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Population upkeep estimation and payment.
# - Per-status-group upkeep profiles.
# - Shortage reporting for active population groups.
#
# Migration note: Rates must remain in the agreed per-5-people format.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name PopulationUpkeepSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "PopulationUpkeepSystem"
