# FlowerWarSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/FlowerWarSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Flower War combat resolution.
# - Captive and loot calculation.
# - Attack/defence outcome reporting and integration with PrestigeSystem.
#
# Migration note: Do not reintroduce armour. Current doctrine baseline should be preserved during extraction.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name FlowerWarSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "FlowerWarSystem"
