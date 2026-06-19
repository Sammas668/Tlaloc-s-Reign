# RivalSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/RivalSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - War Rival, Cunning Rival and Diplomatic Rival state/rules.
# - Fixed build orders for Prototype 0.
# - Rival procurement caps, hoards, true-surplus selling and prestige reports.
#
# Migration note: Do not build full AI first. Start with visible fixed rival behaviour.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name RivalSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "RivalSystem"
