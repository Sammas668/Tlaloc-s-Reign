# WarbandSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/WarbandSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Warband state, assignment and persistence helpers.
# - Warband XP, rank, injury recovery and veteran value once connected.
# - Skill-web effect data and future combat modifiers.
#
# Migration note: Skill web UI exists, but effects should be connected slowly after extraction.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name WarbandSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "WarbandSystem"
