# GameState.gd
# Godot 4.x
# Project path: res://Scripts/state/GameState.gd
#
# Runtime owner for the campaign.
# GameState owns live state; StaticData owns definitions; Systems own rules.
extends Node

signal turn_advanced(current_veintena: int, ritual_year: int)
signal state_rebuilt()

var static_data: StaticData
var economy_system: EconomySystem
var market_system: MarketSystem
var turn_system: TurnSystem

var ritual_year: int = 1
var current_veintena: int = 1
var turn_count: int = 0

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}

func _ready() -> void:
	_bootstrap_systems()
	reset_runtime_state()

func new_game() -> void:
	reset_runtime_state()

func reset() -> void:
	reset_runtime_state()

func reset_runtime_state() -> void:
	if static_data == null:
		_bootstrap_systems()

	ritual_year = 1
	current_veintena = 1
	turn_count = 0

	estate_stockpiles = _create_estate_stockpiles()
	market_stockpiles = _create_market_stockpiles()

	rebuild_current_flows()
	emit_signal("state_rebuilt")

func rebuild_current_flows() -> void:
	if economy_system == null or static_data == null:
		return
	economy_system.rebuild_estate_flows(estate_stockpiles, static_data.estate_flow_sources)
	emit_signal("state_rebuilt")

func advance_placeholder_turn() -> void:
	if turn_system == null:
		return
	turn_system.advance_veintena(self)
	emit_signal("turn_advanced", current_veintena, ritual_year)
	emit_signal("state_rebuilt")

func get_estate_stockpile_rows() -> Array[Dictionary]:
	rebuild_current_flows()
	if economy_system == null or static_data == null:
		return []
	return economy_system.get_estate_stockpile_rows(estate_stockpiles, static_data)

func get_market_rows() -> Array[Dictionary]:
	if market_system == null or static_data == null:
		return []
	return market_system.get_market_rows(market_stockpiles, static_data.market_start, static_data)

func get_resource_definition(good_id: String) -> Dictionary:
	if static_data == null:
		return {}
	return static_data.get_resource_definition(good_id)

func get_stockpile(good_id: String) -> Stockpile:
	if estate_stockpiles.has(good_id):
		return estate_stockpiles[good_id] as Stockpile
	return null

func get_market_stockpile(good_id: String) -> Stockpile:
	if market_stockpiles.has(good_id):
		return market_stockpiles[good_id] as Stockpile
	return null

func _bootstrap_systems() -> void:
	static_data = StaticData.new()
	var loaded: bool = static_data.load_all()
	if not loaded:
		for error_text: String in static_data.load_errors:
			push_error(error_text)

	economy_system = EconomySystem.new()
	market_system = MarketSystem.new()
	turn_system = TurnSystem.new()

func _create_estate_stockpiles() -> Dictionary:
	var output: Dictionary = {}
	var start_stockpiles: Dictionary = static_data.estate_start.get("stockpiles", {}) as Dictionary

	for good_id: String in static_data.resource_order:
		var stored: float = float(start_stockpiles.get(good_id, 0.0))
		output[good_id] = Stockpile.new(good_id, stored)

	return output

func _create_market_stockpiles() -> Dictionary:
	var output: Dictionary = {}
	var market_data: Dictionary = static_data.market_start.get("stockpiles", {}) as Dictionary

	for good_id: String in static_data.market_order:
		var row: Dictionary = market_data.get(good_id, {}) as Dictionary
		var stock: float = float(row.get("stock", 0.0))
		output[good_id] = Stockpile.new(good_id, stock)

	return output
