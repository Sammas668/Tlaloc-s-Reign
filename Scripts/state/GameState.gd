# GameState.gd
# Godot 4.x
# Project path: res://Scripts/state/GameState.gd
#
# LEGACY ONLY.
#
# This file is no longer an active autoload.
# TRGameState is the Prototype 0 runtime facade.
# CampaignState is the live campaign/save-state data owner.
#
# Do not add new gameplay rules here.
# Do not target this file in future Prototype 0 patches.
#
# The small forwarding helpers below exist only so legacy scenes/scripts that
# accidentally instantiate this node fail softly and redirect to /root/TRGameState
# when possible.

extends Node

signal turn_advanced(current_veintena: int, ritual_year: int)
signal state_rebuilt()


func _ready() -> void:
	push_warning("Legacy GameState.gd was instantiated. Prototype 0 should use /root/TRGameState instead.")


func _tr_game_state() -> Node:
	return get_node_or_null("/root/TRGameState")


func _forward(method_name: String, args: Array = []) -> Variant:
	var runtime_state: Node = _tr_game_state()
	if runtime_state != null and runtime_state.has_method(method_name):
		return runtime_state.callv(method_name, args)
	push_warning("Legacy GameState could not forward method: " + method_name)
	return null


func new_game() -> void:
	_forward("new_game")


func reset() -> void:
	_forward("new_game")


func reset_runtime_state() -> void:
	_forward("new_game")


func advance_placeholder_turn() -> void:
	var runtime_state: Node = _tr_game_state()
	if runtime_state != null:
		if runtime_state.has_method("advance_turn"):
			runtime_state.call("advance_turn")
		elif runtime_state.has_method("advance_veintena"):
			runtime_state.call("advance_veintena")
		var current: int = 1
		var year: int = 1
		if runtime_state.has_method("get_current_veintena"):
			current = int(runtime_state.call("get_current_veintena"))
		if runtime_state.has_method("get_ritual_year"):
			year = int(runtime_state.call("get_ritual_year"))
		emit_signal("turn_advanced", current, year)
	emit_signal("state_rebuilt")


func get_estate_stockpile_rows() -> Array[Dictionary]:
	var result: Variant = _forward("get_storehouse_goods")
	if result is Array:
		var output: Array[Dictionary] = []
		for item: Variant in result:
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
		return output
	return []


func get_market_rows() -> Array[Dictionary]:
	var result: Variant = _forward("get_market_goods")
	if result is Array:
		var output: Array[Dictionary] = []
		for item: Variant in result:
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
		return output
	return []


func get_resource_definition(good_id: String) -> Dictionary:
	var runtime_state: Node = _tr_game_state()
	if runtime_state != null:
		var resources_variant: Variant = runtime_state.get("resources")
		if resources_variant is Dictionary:
			var resources: Dictionary = resources_variant as Dictionary
			if resources.has(good_id) and resources[good_id] is Dictionary:
				return (resources[good_id] as Dictionary).duplicate(true)
	return {}


func get_stockpile(_good_id: String) -> Variant:
	push_warning("Legacy GameState.get_stockpile() is not supported. Use TRGameState/CampaignState APIs.")
	return null


func get_market_stockpile(_good_id: String) -> Variant:
	push_warning("Legacy GameState.get_market_stockpile() is not supported. Use TRGameState/CampaignState APIs.")
	return null
