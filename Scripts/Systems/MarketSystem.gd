# MarketSystem.gd
# Godot 4.x
# Project path: res://Scripts/systems/MarketSystem.gd
#
# Calculates central market stock, demand, coverage, scarcity multiplier and display values.
class_name MarketSystem
extends RefCounted

const MIN_SCARCITY_MULTIPLIER: float = 0.75
const MAX_SCARCITY_MULTIPLIER: float = 3.0
const TARGET_COVERAGE_TURNS: float = 3.0

func get_market_rows(market_stockpiles: Dictionary, market_static: Dictionary, static_data: StaticData) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var market_definitions: Dictionary = market_static.get("stockpiles", {}) as Dictionary

	for good_id: String in static_data.market_order:
		if not market_stockpiles.has(good_id):
			continue

		var stockpile: Stockpile = market_stockpiles[good_id] as Stockpile
		var market_data: Dictionary = market_definitions.get(good_id, {}) as Dictionary
		var row: Dictionary = static_data.get_resource_definition(good_id)

		var demand: float = float(market_data.get("outgoing", 0.0))
		var incoming: float = float(market_data.get("incoming", 0.0))
		var coverage: float = coverage_for(stockpile.stored, demand)
		var multiplier: float = scarcity_multiplier_for(coverage)
		var base_value: float = float(market_data.get("base_value", row.get("base_value", 0.0)))

		row["market_stock"] = stockpile.stored
		row["incoming"] = incoming
		row["outgoing"] = demand
		row["demand"] = demand
		row["coverage"] = _round_to(coverage, 0.01)
		row["multiplier"] = _round_to(multiplier, 0.01)
		row["base_value"] = base_value
		row["current_value"] = _round_to(base_value * multiplier, 0.01)
		row["label"] = market_label_for(coverage)
		row["trend"] = market_trend_for(incoming - demand, coverage)
		row["buy_note"] = String(market_data.get("buy_note", "No buy note yet."))
		row["sell_note"] = String(market_data.get("sell_note", "No sell note yet."))
		row["rival_note"] = String(market_data.get("rival_note", "No rival signal recorded yet."))

		rows.append(row)

	return rows

func apply_market_turn(market_stockpiles: Dictionary, market_static: Dictionary) -> void:
	var market_definitions: Dictionary = market_static.get("stockpiles", {}) as Dictionary

	for good_id_variant: Variant in market_stockpiles.keys():
		var good_id: String = String(good_id_variant)
		var stockpile: Stockpile = market_stockpiles[good_id] as Stockpile
		var market_data: Dictionary = market_definitions.get(good_id, {}) as Dictionary
		var incoming: float = float(market_data.get("incoming", 0.0))
		var outgoing: float = float(market_data.get("outgoing", 0.0))
		stockpile.stored = maxf(0.0, _round_to(stockpile.stored + incoming - outgoing, 0.01))

func coverage_for(stock: float, demand: float) -> float:
	if demand <= 0.0:
		return 999.0
	return stock / demand

func scarcity_multiplier_for(coverage: float) -> float:
	if coverage <= 0.0:
		return MAX_SCARCITY_MULTIPLIER
	return clampf(TARGET_COVERAGE_TURNS / coverage, MIN_SCARCITY_MULTIPLIER, MAX_SCARCITY_MULTIPLIER)

func market_label_for(coverage: float) -> String:
	if coverage <= 0.0:
		return "Crisis"
	if coverage >= 5.0:
		return "Abundant"
	if coverage >= 3.0:
		return "Comfortable"
	if coverage >= 1.5:
		return "Tight"
	if coverage >= 0.75:
		return "Shortage"
	return "Crisis"

func market_trend_for(net: float, coverage: float) -> String:
	if coverage <= 0.0:
		return "Critical"
	if net < -1.0:
		return "Rising"
	if net > 1.0:
		return "Soft"
	return "Stable"

func _round_to(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return roundf(value / step) * step
