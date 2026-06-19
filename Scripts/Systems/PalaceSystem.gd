# PalaceSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PalaceSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Palace dedication route data and route effects.
# - Palace structure build/active status rules.
# - Court Needs / ruler demand donation calculations and reports.
#
# Migration note: Canonical palace powers: Tlaloc forecast, Huitzilopochtli Flower Wars authority, Tezcatlipoca scarcity/intrigue/market pressure, Quetzalcoatl legitimacy/recognition.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name PalaceSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "PalaceSystem"
