# ReligionSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/ReligionSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Four-god favour state and favour decay.
# - Shrine upgrades and maintenance offering rules.
# - Major ritual and sacrifice resolution once extracted.
#
# Migration note: Prototype 0 gods remain Tlaloc, Huitzilopochtli, Tezcatlipoca and Quetzalcoatl only.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name ReligionSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "ReligionSystem"
