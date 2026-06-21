# TurnSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/TurnSystem.gd
#
# Legacy compatibility wrapper.
# Active Prototype 0 turn resolution is owned by TurnResolutionSystem through
# TRGameState. This class remains only so any old reference fails safely instead
# of mutating TRGameState mirror fields directly.

class_name TurnSystem
extends RefCounted


func advance_veintena(game_state: Node) -> void:
	if game_state == null:
		return
	if game_state.has_method("advance_veintena"):
		game_state.call("advance_veintena")
	elif game_state.has_method("advance_turn"):
		game_state.call("advance_turn")
