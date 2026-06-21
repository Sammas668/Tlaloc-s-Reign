# MarketEconomySystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/MarketEconomySystem.gd
#
# Owns market/village economy presentation and scarcity projection logic.
# Reads CampaignState first through TRGameState accessors, with TRGameState
# field fallback kept only for compatibility.

class_name MarketEconomySystem
extends RefCounted


func get_market_goods(state: Node) -> Array[Dictionary]:
	var raw_goods: Array = estimate_market_resolution(state).get("goods", []) as Array
	var output: Array[Dictionary] = []
	for item_variant: Variant in raw_goods:
		if item_variant is Dictionary:
			output.append((item_variant as Dictionary).duplicate(true))
	return output


func estimate_market_resolution(state: Node) -> Dictionary:
	if state == null:
		return {
			"goods": [],
			"source_of_truth": "No state connected.",
			"total_output": 0.0,
			"total_demand": 0.0,
			"net_change": 0.0,
			"crisis_goods": [],
			"shortage_goods": [],
			"surplus_goods": [],
			"village_population": {},
			"schema_version": ""
		}

	var base_goods: Array[Dictionary] = base_market_goods(state)
	var resolved_goods: Array[Dictionary] = apply_market_economy_to_goods(state, base_goods)
	var total_output: float = 0.0
	var total_demand: float = 0.0
	var net_value: float = 0.0
	var crisis_goods: Array[String] = []
	var shortage_goods: Array[String] = []
	var surplus_goods: Array[String] = []

	for good: Dictionary in resolved_goods:
		total_output += float(good.get("village_total_production", 0.0))
		total_demand += float(good.get("village_total_demand", 0.0))
		net_value += float(good.get("village_net_change", 0.0))
		var label: String = String(good.get("label", ""))
		var name: String = String(good.get("name", good.get("id", "Good")))
		if label == "Crisis":
			crisis_goods.append(name)
		elif label == "Shortage":
			shortage_goods.append(name)
		elif label == "Abundant":
			surplus_goods.append(name)

	var economy: Dictionary = _market_economy(state)
	return {
		"goods": resolved_goods,
		"source_of_truth": String(economy.get("source_of_truth", "start_state market stock/demand")),
		"total_output": total_output,
		"total_demand": total_demand,
		"net_change": net_value,
		"crisis_goods": crisis_goods,
		"shortage_goods": shortage_goods,
		"surplus_goods": surplus_goods,
		"village_population": (economy.get("village_population", {}) as Dictionary).duplicate(true),
		"schema_version": String(economy.get("schema_version", ""))
	}


func get_village_economy_rows(state: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var goods: Array = estimate_market_resolution(state).get("goods", []) as Array

	for good_variant: Variant in goods:
		if not (good_variant is Dictionary):
			continue
		var good: Dictionary = good_variant as Dictionary
		rows.append({
			"id": String(good.get("id", "")),
			"name": String(good.get("name", "Good")),
			"natural_production": float(good.get("village_natural_production", 0.0)),
			"building_output": float(good.get("village_building_output", 0.0)),
			"estate_output": float(good.get("market_estate_output_supply", 0.0)),
			"total_production": float(good.get("village_total_production", 0.0)),
			"population_consumption": float(good.get("village_population_consumption", 0.0)),
			"building_input_demand": float(good.get("village_building_input_demand", 0.0)),
			"construction_demand": float(good.get("market_construction_demand", 0.0)),
			"estate_input_demand": float(good.get("market_estate_input_demand", 0.0)),
			"total_demand": float(good.get("village_total_demand", 0.0)),
			"net_change": float(good.get("village_net_change", 0.0)),
			"projected_market_stock": float(good.get("projected_market_stock", 0.0)),
			"label": String(good.get("label", "Unknown")),
			"trend": String(good.get("trend", "Stable")),
			"note": String(good.get("village_note", ""))
		})

	return rows


func base_market_goods(state: Node) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if state == null:
		return output

	var order: Array[String] = _campaign_string_array(state, "resource_order")
	var resources: Dictionary = _campaign_dictionary(state, "resources")
	var market_demand: Dictionary = _campaign_dictionary(state, "market_demand")

	for resource_id: String in order:
		if not resources.has(resource_id):
			continue

		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stock_value: float = _market_stock(state, resource_id)
		var demand_value: float = maxf(0.0, float(market_demand.get(resource_id, 0.0)))
		var coverage: float = 0.0
		if demand_value > 0.0:
			coverage = stock_value / demand_value

		var multiplier: float = scarcity_multiplier(coverage, demand_value)
		var base_value: float = float(resource_data.get("base_value", 1.0))
		var current_value: float = base_value * multiplier

		output.append({
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"market_stock": stock_value,
			"demand": demand_value,
			"base_value": base_value,
			"current_value": current_value,
			"coverage": coverage,
			"label": market_label(coverage, demand_value),
			"trend": market_trend(coverage, demand_value),
			"buy_note": "Buy when estate free stock is low or a build needs this good.",
			"sell_note": "Sell only true surplus after upkeep, input and build reserves are protected.",
			"rival_note": _rival_market_note(state, resource_id)
		})

	return output


func apply_market_economy_to_goods(state: Node, goods: Array[Dictionary]) -> Array[Dictionary]:
	if state == null:
		return goods

	var economy: Dictionary = _market_economy(state)
	if economy.is_empty():
		return goods

	var natural: Dictionary = economy.get("village_natural_production", {}) as Dictionary
	var building_outputs: Dictionary = economy.get("village_building_outputs", {}) as Dictionary
	var population_use: Dictionary = economy.get("village_population_consumption", {}) as Dictionary
	var building_inputs: Dictionary = economy.get("village_building_inputs", {}) as Dictionary
	var construction_demand: Dictionary = economy.get("year1_construction_demand_per_turn", {}) as Dictionary
	var estate_inputs: Dictionary = economy.get("starter_estate_input_demand", {}) as Dictionary
	var estate_outputs: Dictionary = economy.get("starter_estate_output_supply", {}) as Dictionary
	var event_modifiers: Dictionary = economy.get("event_modifiers", {}) as Dictionary

	for index: int in range(goods.size()):
		var good: Dictionary = goods[index]
		var resource_id: String = String(good.get("id", ""))
		var market_stock: float = float(good.get("market_stock", 0.0))
		var base_value: float = float(good.get("base_value", 1.0))
		var natural_output: float = market_resource_value(natural, resource_id)
		var building_output: float = market_resource_value(building_outputs, resource_id)
		var estate_output: float = market_resource_value(estate_outputs, resource_id)
		var population_demand: float = market_resource_value(population_use, resource_id)
		var building_demand: float = market_resource_value(building_inputs, resource_id)
		var construction_need: float = market_resource_value(construction_demand, resource_id)
		var estate_demand: float = market_resource_value(estate_inputs, resource_id)
		var event_delta: float = market_resource_value(event_modifiers, resource_id)

		var total_output: float = maxf(0.0, natural_output + building_output + estate_output + event_delta)
		var total_demand: float = maxf(0.0, population_demand + building_demand + construction_need + estate_demand)
		if total_demand <= 0.001:
			total_demand = maxf(0.0, float(good.get("demand", 0.0)))

		var net_change: float = total_output - total_demand
		var projected_stock: float = maxf(0.0, market_stock + net_change)
		var projected_coverage: float = 0.0
		if total_demand > 0.001:
			projected_coverage = projected_stock / total_demand

		var multiplier: float = market_scarcity_multiplier(projected_coverage, total_demand)
		var projected_value: float = base_value * multiplier

		good["starting_market_stock"] = market_stock
		good["village_natural_production"] = natural_output
		good["village_building_output"] = building_output
		good["market_estate_output_supply"] = estate_output
		good["village_event_delta"] = event_delta
		good["village_total_production"] = total_output
		good["village_population_consumption"] = population_demand
		good["village_building_input_demand"] = building_demand
		good["market_construction_demand"] = construction_need
		good["market_estate_input_demand"] = estate_demand
		good["village_total_demand"] = total_demand
		good["village_net_change"] = net_change
		good["projected_market_stock"] = projected_stock
		good["projected_coverage"] = projected_coverage
		good["projected_value"] = projected_value
		good["demand"] = total_demand
		good["coverage"] = projected_coverage
		good["current_value"] = projected_value
		good["label"] = market_pressure_label(projected_coverage, total_demand)
		good["trend"] = market_net_trend(net_change, total_demand)
		good["village_note"] = market_good_note(state, resource_id)
		goods[index] = good

	return goods


func market_resource_value(source: Dictionary, resource_id: String) -> float:
	return float(source.get(resource_id, 0.0))


func scarcity_multiplier(coverage: float, demand_value: float) -> float:
	return MarketPricingRules.scarcity_multiplier(coverage, demand_value)


func market_label(coverage: float, demand_value: float) -> String:
	if demand_value <= 0.0:
		return "No demand"
	if coverage >= 5.0:
		return "Abundant"
	if coverage >= 3.0:
		return "Comfortable"
	if coverage >= 1.5:
		return "Tight"
	if coverage >= 0.75:
		return "Shortage"
	return "Crisis"


func market_trend(coverage: float, demand_value: float) -> String:
	if demand_value <= 0.0:
		return "Idle"
	if coverage >= 5.0:
		return "Soft"
	if coverage >= 3.0:
		return "Stable"
	if coverage >= 1.5:
		return "Rising"
	return "Critical"


func market_scarcity_multiplier(coverage: float, demand: float) -> float:
	return MarketPricingRules.scarcity_multiplier(coverage, demand)


func market_pressure_label(coverage: float, demand: float) -> String:
	if demand <= 0.001:
		return "No demand"
	if coverage < 1.0:
		return "Crisis"
	if coverage < 2.0:
		return "Shortage"
	if coverage < 3.0:
		return "Tight"
	if coverage > 6.0:
		return "Abundant"
	return "Comfortable"


func market_net_trend(net_change: float, demand: float) -> String:
	if demand <= 0.001:
		return "Stable"
	if net_change <= -demand * 0.35:
		return "Falling fast"
	if net_change < -0.01:
		return "Falling"
	if net_change >= demand * 0.35:
		return "Rising fast"
	if net_change > 0.01:
		return "Rising"
	return "Stable"


func market_good_note(state: Node, resource_id: String) -> String:
	var notes: Dictionary = _market_economy(state).get("resource_notes", {}) as Dictionary
	return String(notes.get(resource_id, "No village economy note recorded yet."))


func _campaign_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _campaign_dictionary(state: Node, key: String) -> Dictionary:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null:
		match key:
			"market_stockpiles":
				if runtime_state.has_method("get_market_stockpiles_copy"):
					return runtime_state.call("get_market_stockpiles_copy") as Dictionary
			"market_demand":
				var demand_value: Variant = runtime_state.get("market_demand")
				if demand_value is Dictionary:
					return (demand_value as Dictionary).duplicate(true)
			_:
				var runtime_value: Variant = runtime_state.get(key)
				if runtime_value is Dictionary:
					return (runtime_value as Dictionary).duplicate(true)

	if state != null:
		var fallback: Variant = state.get(key)
		if fallback is Dictionary:
			return (fallback as Dictionary).duplicate(true)

	return {}


func _campaign_string_array(state: Node, key: String) -> Array[String]:
	var output: Array[String] = []
	var runtime_state: RefCounted = _campaign_state(state)
	var raw_value: Variant = null

	if runtime_state != null:
		raw_value = runtime_state.get(key)
	if raw_value == null and state != null:
		raw_value = state.get(key)

	if raw_value is Array:
		for item: Variant in raw_value as Array:
			output.append(String(item))

	return output


func _market_economy(state: Node) -> Dictionary:
	return _campaign_dictionary(state, "market_economy")


func _market_stock(state: Node, resource_id: String) -> float:
	var runtime_state: RefCounted = _campaign_state(state)
	if runtime_state != null and runtime_state.has_method("get_market_stock"):
		return float(runtime_state.call("get_market_stock", resource_id))

	var stockpiles: Dictionary = _campaign_dictionary(state, "market_stockpiles")
	return float(stockpiles.get(resource_id, 0.0))


func _rival_market_note(state: Node, resource_id: String) -> String:
	if state != null and state.has_method("get_rival_market_note"):
		return String(state.call("get_rival_market_note", resource_id))
	if state != null and state.has_method("_rival_market_note"):
		return String(state.call("_rival_market_note", resource_id))
	return ""
