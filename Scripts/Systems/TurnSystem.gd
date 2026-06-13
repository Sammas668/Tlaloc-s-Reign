# TurnSystem.gd
# Godot 4.x
# Project path: res://Scripts/systems/TurnSystem.gd
#
# Owns the turn update order. GameState owns the live data; systems own the rules.
class_name TurnSystem
extends RefCounted

func advance_veintena(game_state: Node) -> void:
	if game_state == null:
		return

	if game_state.has_method("rebuild_current_flows"):
		game_state.call("rebuild_current_flows")

	var economy_system: EconomySystem = game_state.get("economy_system") as EconomySystem
	var market_system: MarketSystem = game_state.get("market_system") as MarketSystem
	var estate_stockpiles: Dictionary = game_state.get("estate_stockpiles") as Dictionary
	var market_stockpiles: Dictionary = game_state.get("market_stockpiles") as Dictionary
	var static_data: StaticData = game_state.get("static_data") as StaticData

	if economy_system:
		economy_system.apply_estate_turn(estate_stockpiles)
	if market_system and static_data:
		market_system.apply_market_turn(market_stockpiles, static_data.market_start)

	var turn_count: int = int(game_state.get("turn_count"))
	var current_veintena: int = int(game_state.get("current_veintena"))
	var ritual_year: int = int(game_state.get("ritual_year"))

	turn_count += 1
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		ritual_year += 1

	game_state.set("turn_count", turn_count)
	game_state.set("current_veintena", current_veintena)
	game_state.set("ritual_year", ritual_year)

	if game_state.has_method("rebuild_current_flows"):
		game_state.call("rebuild_current_flows")
