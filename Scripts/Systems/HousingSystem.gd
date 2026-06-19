# HousingSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/HousingSystem.gd
#
# v0.43.0 architecture split scaffold only.
# This file intentionally does not change gameplay yet.
#
# Intended ownership:
# - Housing capacity and active/mothballed housing rules.
# - Housing building maintenance estimation and payment.
# - Overcrowding and housing destroy/build validation helpers.
#
# Migration note: Keep housing distinct from generic local stability; there is no broad local-stability meter.
#
# Extraction rule: UI should continue to call TRGameState / future CampaignState.
# Systems should own rules, not scene/UI code.
class_name HousingSystem
extends RefCounted

const SCAFFOLD_VERSION: String = "v0.43.0"

func system_name() -> String:
	return "HousingSystem"
