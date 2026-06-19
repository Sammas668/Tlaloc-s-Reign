# ProductionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ProductionSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Production resolution for staffed buildings.
# - Input consumption and output creation.
# - Blocked / unstaffed productive-building reporting.
#
# Migration note: Should preserve current building_order behaviour during extraction.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name ProductionSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "ProductionSystem"
