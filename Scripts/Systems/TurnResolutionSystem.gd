# TurnResolutionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnResolutionSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Canonical Veintena resolution order.
# - Calling upkeep, housing, palace, production, recovery, rival and calendar systems in order.
# - Future structured turn summary orchestration.
#
# Migration note: Current TRGameState.advance_veintena() remains live until extraction is deliberate and tested.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name TurnResolutionSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "TurnResolutionSystem"
