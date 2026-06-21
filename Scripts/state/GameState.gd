# GameState.gd
# Godot 4.x
# Project path: res://Scripts/state/GameState.gd
#
# RETIRED FORWARDER ONLY.
#
# This file is not an active autoload. Prototype 0 uses /root/TRGameState.
# CampaignState owns live/save data.
#
# Do not add gameplay rules here.
# Do not read or write old TRGameState state fields here.
# Keep this file as a thin redirect for any old scene/script that accidentally
# instantiates GameState.

extends Node

signal turn_advanced(current_veintena: int, ritual_year: int)
signal state_rebuilt


func _ready() -> void:
	push_warning("Retired GameState.gd was instantiated. Prototype 0 should use /root/TRGameState instead.")


func _tr_game_state() -> Node:
	return get_node_or_null("/root/TRGameState")


func _forward(method_name: String, args: Array = []) -> Variant:
	var runtime_state: Node = _tr_game_state()
	if runtime_state != null and runtime_state.has_method(method_name):
		return runtime_state.callv(method_name, args)

	push_warning("Retired GameState could not forward method: " + method_name)
	return null


func _forward_dictionary(method_name: String, args: Array = []) -> Dictionary:
	var result: Variant = _forward(method_name, args)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}


func _forward_dictionary_array(method_name: String, args: Array = []) -> Array[Dictionary]:
	var result: Variant = _forward(method_name, args)
	var output: Array[Dictionary] = []
	if result is Array:
		for item: Variant in result as Array:
			if item is Dictionary:
				output.append((item as Dictionary).duplicate(true))
	return output


func _forward_int(method_name: String, default_value: int = 0, args: Array = []) -> int:
	var result: Variant = _forward(method_name, args)
	if result is int or result is float:
		return int(result)
	return default_value


func new_game() -> void:
	_forward("new_game")


func reset() -> void:
	_forward("new_game")


func reset_runtime_state() -> void:
	_forward("new_game")


func advance_placeholder_turn() -> void:
	var runtime_state: Node = _tr_game_state()
	if runtime_state == null:
		emit_signal("state_rebuilt")
		return

	if runtime_state.has_method("advance_turn"):
		runtime_state.call("advance_turn")
	elif runtime_state.has_method("advance_veintena"):
		runtime_state.call("advance_veintena")
	else:
		push_warning("Retired GameState could not forward turn advance.")

	var current: int = _forward_int("get_current_veintena", 1)
	var year: int = _forward_int("get_ritual_year", 1)
	emit_signal("turn_advanced", current, year)
	emit_signal("state_rebuilt")


func get_estate_stockpile_rows() -> Array[Dictionary]:
	return _forward_dictionary_array("get_storehouse_goods")


func get_market_rows() -> Array[Dictionary]:
	return _forward_dictionary_array("get_market_goods")


func get_resource_definition(good_id: String) -> Dictionary:
	# There is no current TRGameState public resource-definition API. This remains
	# a pure redirect point only, so it returns an empty dictionary unless a future
	# facade method with this name is added.
	return _forward_dictionary("get_resource_definition", [good_id])


func get_stockpile(good_id: String) -> Variant:
	# Kept only for old callers. This redirects to TRGameState's CampaignState-
	# backed stock read and does not inspect any local state.
	return _forward("_stock", [good_id])


func get_market_stockpile(_good_id: String) -> Variant:
	push_warning("Retired GameState.get_market_stockpile() has no public TRGameState redirect. Use current market/storehouse APIs.")
	return null
