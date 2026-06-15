# TRGameState.gd
# Godot 4.x
# Suggested autoload name: TRGameState
# Project path: res://Scripts/Autoload/TRGameState.gd
extends Node

signal state_changed
signal turn_advanced(report: Array)
signal build_completed(building_id: String)
signal build_failed(building_id: String, reason: String)
signal destroy_completed(building_id: String)
signal destroy_failed(building_id: String, reason: String)
signal flower_war_resolved(result: Dictionary)

const RESOURCE_DATA_PATH: String = "res://Data/Prototype0/resources.json"
const BUILDING_DATA_PATH: String = "res://Data/Prototype0/buildings.json"
const START_STATE_PATH: String = "res://Data/Prototype0/start_state.json"
const MARKET_ECONOMY_DATA_PATH: String = "res://Data/Prototype0/market_economy.json"

var resources: Dictionary = {}
var resource_order: Array[String] = []
var buildings: Dictionary = {}
var building_order: Array[String] = []

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}
var market_demand: Dictionary = {}
var estate_buildings: Dictionary = {}
var active_housing_counts: Dictionary = {}
var population: Dictionary = {}
var base_housing_capacity: Dictionary = {}
var labour_assignments: Dictionary = {}
var market_economy: Dictionary = {}

const RELIGION_STARTING_FAVOUR: float = 40.0
const RELIGION_NORMAL_DECAY: float = 2.0
const RELIGION_NEMONTEMI_DECAY: float = 4.0
const GOD_IDS: Array[String] = ["tlaloc", "huitzilopochtli", "tezcatlipoca", "quetzalcoatl"]

var divine_favour: Dictionary = {}
var shrine_levels: Dictionary = {}
var shrine_upgrades: Dictionary = {}
var ritual_capacity_used_this_veintena: float = 0.0
var recent_ritual_reports: Array[String] = []

const FLOWER_WAR_DOCTRINES: Dictionary = {
	"unspecialised": {"name": "Unspecialised", "offence": 1.0, "defence": 1.0, "role": "General purpose."},
	"eagle": {"name": "Eagle", "offence": 1.0, "defence": 1.2, "role": "Captive specialists.", "capture_bonus_per_warrior": 0.02},
	"jaguar": {"name": "Jaguar", "offence": 1.3, "defence": 1.0, "role": "Elite assault warriors.", "prestige_mult": 1.15},
	"otomi": {"name": "Otomi", "offence": 0.8, "defence": 1.5, "role": "Defensive veterans.", "death_mult": 0.8},
	"coyote": {"name": "Coyote", "offence": 1.4, "defence": 0.5, "role": "Looting raiders.", "loot_mult": 1.25}
}

const FLOWER_WAR_SCALES: Dictionary = {
	"minor": {"name": "Minor Flower War", "recommended": 5, "enemy_warriors": 5, "difficulty": 0.85},
	"standard": {"name": "Standard Flower War", "recommended": 10, "enemy_warriors": 10, "difficulty": 1.0},
	"major": {"name": "Major Flower War", "recommended": 20, "enemy_warriors": 20, "difficulty": 1.10}
}

const FLOWER_WAR_PROVISIONING: Dictionary = {
	"standard": {"name": "Standard", "cost_mult": 1.0, "combat_mult": 1.0},
	"well": {"name": "Well-Provisioned", "cost_mult": 2.0, "combat_mult": 1.10},
	"royal": {"name": "Royal", "cost_mult": 4.0, "combat_mult": 1.25}
}

var warrior_recruits_used_this_veintena: int = 0
var warrior_xp: float = 0.0
var player_prestige: float = 0.0
var last_flower_war_report: Array[String] = []
var flower_war_history: Array[Dictionary] = []

var current_veintena: int = 1
var last_report: Array[String] = []
var initialized: bool = false

var population_upkeep_rates: Dictionary = {
	"macehualtin": {"maize": 1.0, "cotton": 0.05, "cloth": 0.2, "tools": 0.1},
	"tlacotin": {"maize": 0.5, "cotton": 0.025, "cloth": 0.1, "tools": 0.05},
	"tolteca": {"maize": 1.0, "cotton": 0.1, "cloth": 0.3, "tools": 0.25},
	"yaotequihuaqueh": {"maize": 1.25, "cloth": 0.3, "tools": 0.1, "weapons": 0.2, "cacao": 0.05},
	"tlamacazqueh": {"maize": 1.0, "cloth": 0.2, "ritual_goods": 0.2, "cacao": 0.1},
	"pipiltin": {"maize": 1.0, "cloth": 0.4, "ritual_goods": 0.1, "cacao": 0.3, "fine_textiles": 0.2},
	"malli": {"maize": 0.5}
}

func _ready() -> void:
	if not initialized:
		new_game()

func new_game() -> void:
	_load_resource_definitions()
	_load_building_definitions()
	_load_market_economy_definitions()
	_load_start_state()
	initialized = true
	last_report.clear()
	last_report.append("New estate simulation started.")
	emit_signal("state_changed")

func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing data file: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open data file: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("Data file did not parse as Dictionary: " + path)
	return {}

func _load_resource_definitions() -> void:
	resources.clear()
	resource_order.clear()
	var rows: Array = (_load_json_dictionary(RESOURCE_DATA_PATH).get("resources", []) as Array)
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var resource_id: String = String(row.get("id", ""))
		if resource_id == "":
			continue
		resources[resource_id] = row
		resource_order.append(resource_id)

func _load_building_definitions() -> void:
	buildings.clear()
	building_order.clear()
	var rows: Array = (_load_json_dictionary(BUILDING_DATA_PATH).get("buildings", []) as Array)
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var building_id: String = String(row.get("id", ""))
		if building_id == "":
			continue
		buildings[building_id] = row
		building_order.append(building_id)
	building_order.sort_custom(func(a: String, b: String) -> bool:
		return int((buildings[a] as Dictionary).get("priority", 999)) < int((buildings[b] as Dictionary).get("priority", 999))
	)

func _load_market_economy_definitions() -> void:
	market_economy.clear()
	market_economy = _load_json_dictionary(MARKET_ECONOMY_DATA_PATH)

func _load_start_state() -> void:
	var data: Dictionary = _load_json_dictionary(START_STATE_PATH)
	current_veintena = int(data.get("current_veintena", 1))
	estate_stockpiles = _float_dictionary(data.get("estate_stockpiles", {}) as Dictionary)
	market_stockpiles = _float_dictionary(data.get("market_stockpiles", {}) as Dictionary)
	market_demand = _float_dictionary(data.get("market_demand", {}) as Dictionary)
	estate_buildings = _int_dictionary(data.get("estate_buildings", {}) as Dictionary)
	active_housing_counts = _int_dictionary(data.get("active_housing_counts", {}) as Dictionary)
	population = _int_dictionary(data.get("population", {}) as Dictionary)
	base_housing_capacity = _int_dictionary(data.get("base_housing_capacity", {}) as Dictionary)
	labour_assignments = _nested_int_dictionary(data.get("labour_assignments", {}) as Dictionary)
	_ensure_all_resource_keys()
	_ensure_all_building_keys()
	_ensure_base_housing_capacity()
	_ensure_active_housing_counts()
	_auto_staff_all_productive_buildings()
	_ensure_religion_state()

func _float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		output[String(key_variant)] = float(source[key_variant])
	return output

func _int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		output[String(key_variant)] = int(source[key_variant])
	return output

func _nested_int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var value: Variant = source[key_variant]
		if value is Dictionary:
			output[key] = _int_dictionary(value as Dictionary)
	return output

func _ensure_all_resource_keys() -> void:
	for resource_id: String in resource_order:
		if not estate_stockpiles.has(resource_id): estate_stockpiles[resource_id] = 0.0
		if not market_stockpiles.has(resource_id): market_stockpiles[resource_id] = 0.0
		if not market_demand.has(resource_id): market_demand[resource_id] = 0.0

func _ensure_all_building_keys() -> void:
	for building_id: String in building_order:
		if not estate_buildings.has(building_id): estate_buildings[building_id] = 0

func get_current_veintena() -> int:
	return current_veintena

func get_last_report() -> Array[String]:
	return _string_array(last_report)

func get_resource_name(resource_id: String) -> String:
	if resources.has(resource_id):
		return String((resources[resource_id] as Dictionary).get("name", resource_id.capitalize()))
	return resource_id.capitalize()

func get_building_name(building_id: String) -> String:
	if buildings.has(building_id):
		return String((buildings[building_id] as Dictionary).get("name", building_id.capitalize()))
	return building_id.capitalize()

func get_storehouse_goods() -> Array[Dictionary]:
	var incoming: Dictionary = estimate_building_outputs()
	var building_inputs: Dictionary = estimate_building_inputs()
	var housing_maintenance: Dictionary = estimate_housing_maintenance()
	var upkeep: Dictionary = estimate_population_upkeep()
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stored: float = _stock(resource_id)
		var in_value: float = float(incoming.get(resource_id, 0.0))
		var upkeep_value: float = float(upkeep.get(resource_id, 0.0))
		var input_value: float = float(building_inputs.get(resource_id, 0.0))
		var housing_value: float = float(housing_maintenance.get(resource_id, 0.0))
		var outgoing: float = upkeep_value + input_value + housing_value
		output.append({"id": resource_id, "name": String(resource_data.get("name", resource_id.capitalize())), "category": String(resource_data.get("category", "raw")), "stored": stored, "incoming": in_value, "outgoing": outgoing, "reserved": outgoing, "free": maxf(0.0, stored - outgoing), "net": in_value - outgoing, "pressure": _pressure_label(stored, outgoing), "uses": resource_data.get("uses", []) as Array, "reserved_breakdown": _reserve_breakdown(resource_id, upkeep_value, input_value, housing_value)})
	return output

func get_market_goods() -> Array[Dictionary]:
	var raw_goods: Array = estimate_market_resolution().get("goods", []) as Array
	var output: Array[Dictionary] = []
	for item_variant: Variant in raw_goods:
		output.append((item_variant as Dictionary).duplicate(true))
	return output

func estimate_market_resolution() -> Dictionary:
	var resolved_goods: Array[Dictionary] = _apply_market_economy_to_goods(_base_market_goods())
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
		if label == "Crisis": crisis_goods.append(name)
		elif label == "Shortage": shortage_goods.append(name)
		elif label == "Abundant": surplus_goods.append(name)
	return {"goods": resolved_goods, "source_of_truth": String(market_economy.get("source_of_truth", "start_state market stock/demand")), "total_output": total_output, "total_demand": total_demand, "net_change": net_value, "crisis_goods": crisis_goods, "shortage_goods": shortage_goods, "surplus_goods": surplus_goods, "village_population": (market_economy.get("village_population", {}) as Dictionary).duplicate(true), "schema_version": String(market_economy.get("schema_version", ""))}

func get_market_economy_summary() -> Dictionary:
	return estimate_market_resolution()

func get_village_economy_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var goods: Array = estimate_market_resolution().get("goods", []) as Array
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		rows.append({"id": String(good.get("id", "")), "name": String(good.get("name", "Good")), "natural_production": float(good.get("village_natural_production", 0.0)), "building_output": float(good.get("village_building_output", 0.0)), "estate_output": float(good.get("market_estate_output_supply", 0.0)), "total_production": float(good.get("village_total_production", 0.0)), "population_consumption": float(good.get("village_population_consumption", 0.0)), "building_input_demand": float(good.get("village_building_input_demand", 0.0)), "construction_demand": float(good.get("market_construction_demand", 0.0)), "estate_input_demand": float(good.get("market_estate_input_demand", 0.0)), "total_demand": float(good.get("village_total_demand", 0.0)), "net_change": float(good.get("village_net_change", 0.0)), "projected_market_stock": float(good.get("projected_market_stock", 0.0)), "label": String(good.get("label", "Unknown"))})
	return rows

func apply_trade_basket(trade_plan: Dictionary) -> Dictionary:
	var sold_value: float = 0.0
	var bought_value: float = 0.0
	var applied: Array[String] = []
	var goods: Dictionary = {}
	for good: Dictionary in get_market_goods():
		goods[String(good.get("id", ""))] = good
	for resource_variant: Variant in trade_plan.keys():
		var resource_id: String = String(resource_variant)
		var amount: float = float(trade_plan[resource_variant])
		if absf(amount) < 0.001 or not goods.has(resource_id): continue
		var good: Dictionary = goods[resource_id] as Dictionary
		var unit_value: float = float(good.get("current_value", good.get("projected_value", 1.0)))
		if amount < 0.0:
			var sell_amount: float = minf(-amount, free_stock_after_reserves(resource_id))
			if sell_amount <= 0.0: continue
			_add_stock(resource_id, -sell_amount)
			market_stockpiles[resource_id] = float(market_stockpiles.get(resource_id, 0.0)) + sell_amount
			sold_value += sell_amount * unit_value
			applied.append("Sold " + _format_amount(sell_amount) + " " + get_resource_name(resource_id) + ".")
		else:
			var buy_amount: float = minf(amount, float(market_stockpiles.get(resource_id, 0.0)))
			if buy_amount <= 0.0: continue
			_add_stock(resource_id, buy_amount)
			market_stockpiles[resource_id] = float(market_stockpiles.get(resource_id, 0.0)) - buy_amount
			bought_value += buy_amount * unit_value
			applied.append("Bought " + _format_amount(buy_amount) + " " + get_resource_name(resource_id) + ".")
	var balance: float = sold_value - bought_value
	if balance < -0.01:
		return {"accepted": false, "reason": "Trade rejected: bought value exceeds sold value.", "sold_value": sold_value, "bought_value": bought_value, "balance": balance, "applied": []}
	last_report.append("Barter trade accepted. Sold value " + _format_amount(sold_value) + ", bought value " + _format_amount(bought_value) + ". Surplus value is lost, not stored.")
	for line: String in applied: last_report.append(line)
	emit_signal("state_changed")
	return {"accepted": true, "reason": "Trade accepted.", "sold_value": sold_value, "bought_value": bought_value, "balance": balance, "applied": applied}

func _base_market_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var base_value: float = float(resource_data.get("base_value", 1.0))
		var stock: float = float(market_stockpiles.get(resource_id, 0.0))
		var demand: float = float(market_demand.get(resource_id, 0.0))
		var coverage: float = 999.0 if demand <= 0.0 else stock / maxf(1.0, demand)
		var multiplier: float = _scarcity_multiplier(coverage)
		var value: float = base_value * multiplier
		output.append({"id": resource_id, "name": String(resource_data.get("name", resource_id.capitalize())), "category": String(resource_data.get("category", "raw")), "base_value": base_value, "market_stock": stock, "demand": demand, "coverage": coverage, "current_value": value, "projected_value": value, "projected_market_stock": stock, "label": _market_label(coverage), "trend": "Stable", "village_net_change": 0.0, "rival_note": "No rival signal recorded yet."})
	return output

func _apply_market_economy_to_goods(goods: Array[Dictionary]) -> Array[Dictionary]:
	var configured_goods: Dictionary = market_economy.get("goods", {}) as Dictionary
	for good: Dictionary in goods:
		var resource_id: String = String(good.get("id", ""))
		var config: Dictionary = configured_goods.get(resource_id, {}) as Dictionary
		var natural: float = float(config.get("natural_production", 0.0))
		var building_output: float = float(config.get("building_output", 0.0))
		var estate_supply: float = float(config.get("estate_output_supply", 0.0))
		var pop_consumption: float = float(config.get("population_consumption", 0.0))
		var building_demand: float = float(config.get("building_input_demand", 0.0))
		var construction: float = float(config.get("construction_demand", 0.0))
		var estate_demand: float = float(config.get("estate_input_demand", 0.0))
		var total_production: float = natural + building_output + estate_supply
		var total_demand: float = pop_consumption + building_demand + construction + estate_demand
		var net: float = total_production - total_demand
		var projected_stock: float = maxf(0.0, float(good.get("market_stock", 0.0)) + net)
		var demand: float = float(good.get("demand", 0.0))
		var coverage: float = 999.0 if demand <= 0.0 else projected_stock / maxf(1.0, demand)
		var value: float = float(good.get("base_value", 1.0)) * _scarcity_multiplier(coverage)
		good["village_natural_production"] = natural
		good["village_building_output"] = building_output
		good["market_estate_output_supply"] = estate_supply
		good["village_total_production"] = total_production
		good["village_population_consumption"] = pop_consumption
		good["village_building_input_demand"] = building_demand
		good["market_construction_demand"] = construction
		good["market_estate_input_demand"] = estate_demand
		good["village_total_demand"] = total_demand
		good["village_net_change"] = net
		good["projected_market_stock"] = projected_stock
		good["coverage"] = coverage
		good["projected_value"] = value
		good["current_value"] = value
		good["label"] = _market_label(coverage)
		good["trend"] = "Rising" if net > 0.01 else ("Falling" if net < -0.01 else "Stable")
	return goods

func _scarcity_multiplier(coverage: float) -> float:
	if coverage <= 0.0: return 3.0
	return clampf(3.0 / coverage, 0.50, 3.0)

func _market_label(coverage: float) -> String:
	if coverage < 0.75: return "Crisis"
	if coverage < 1.25: return "Shortage"
	if coverage < 2.5: return "Tight"
	if coverage > 5.0: return "Abundant"
	return "Stable"

func _reserve_breakdown(resource_id: String, upkeep: float, input_value: float, housing: float) -> Array[String]:
	var lines: Array[String] = []
	if upkeep > 0.0: lines.append("Population upkeep " + _format_amount(upkeep))
	if input_value > 0.0: lines.append("Building inputs " + _format_amount(input_value))
	if housing > 0.0: lines.append("Housing maintenance " + _format_amount(housing))
	return lines

func reserved_resources_for_current_turn() -> Dictionary:
	var reserved: Dictionary = {}
	_add_dictionary_amounts(reserved, estimate_population_upkeep())
	_add_dictionary_amounts(reserved, estimate_housing_maintenance())
	_add_dictionary_amounts(reserved, estimate_building_inputs())
	return reserved

func free_stock_after_reserves(resource_id: String) -> float:
	return maxf(0.0, _stock(resource_id) - float(reserved_resources_for_current_turn().get(resource_id, 0.0)))

func can_build(building_id: String) -> bool:
	if not buildings.has(building_id): return false
	var cost: Dictionary = (buildings[building_id] as Dictionary).get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn()
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		if maxf(0.0, _stock(resource_id) - float(reserved.get(resource_id, 0.0))) < float(cost[resource_id]): return false
	return true

func build_status_text(building_id: String) -> String:
	if not buildings.has(building_id): return "Unknown building."
	if can_build(building_id): return "Buildable now using free stock after reserves."
	return "Missing required free stock after reserves."

func build_building(building_id: String) -> bool:
	if not can_build(building_id):
		var reason: String = build_status_text(building_id)
		last_report.append(get_building_name(building_id) + " not built. " + reason)
		emit_signal("build_failed", building_id, reason)
		emit_signal("state_changed")
		return false
	var cost: Dictionary = (buildings[building_id] as Dictionary).get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys(): _add_stock(String(resource_variant), -float(cost[resource_variant]))
	estate_buildings[building_id] = int(estate_buildings.get(building_id, 0)) + 1
	if _is_housing_building_id(building_id):
		_ensure_active_housing_counts()
		active_housing_counts[building_id] = clampi(int(active_housing_counts.get(building_id, 0)) + 1, 0, int(estate_buildings.get(building_id, 0)))
	_ensure_labour_assignments()
	last_report.append("Built " + get_building_name(building_id) + ".")
	emit_signal("build_completed", building_id)
	emit_signal("state_changed")
	return true

func can_destroy(building_id: String) -> bool:
	return buildings.has(building_id) and int(estate_buildings.get(building_id, 0)) > 0

func destroy_status_text(building_id: String) -> String:
	return "Can destroy one. No refund in this prototype." if can_destroy(building_id) else "None built."

func destroy_building(building_id: String) -> bool:
	if not can_destroy(building_id):
		emit_signal("destroy_failed", building_id, destroy_status_text(building_id))
		return false
	estate_buildings[building_id] = max(0, int(estate_buildings.get(building_id, 0)) - 1)
	_ensure_active_housing_counts()
	_ensure_labour_assignments()
	last_report.append("Destroyed one " + get_building_name(building_id) + ". No refund given.")
	emit_signal("destroy_completed", building_id)
	emit_signal("state_changed")
	return true


# -----------------------------------------------------------------------------
# Religion / Shrine state
# -----------------------------------------------------------------------------

func _ensure_religion_state() -> void:
	for god_id: String in GOD_IDS:
		if not divine_favour.has(god_id):
			divine_favour[god_id] = RELIGION_STARTING_FAVOUR
		if not shrine_levels.has(god_id):
			shrine_levels[god_id] = 1
		if not shrine_upgrades.has(god_id):
			shrine_upgrades[god_id] = []

func get_religion_state() -> Dictionary:
	_ensure_religion_state()
	return {
		"divine_favour": divine_favour.duplicate(true),
		"shrine_levels": shrine_levels.duplicate(true),
		"shrine_upgrades": shrine_upgrades.duplicate(true),
		"ritual_capacity_used_this_veintena": ritual_capacity_used_this_veintena,
		"recent_ritual_reports": recent_ritual_reports.duplicate(),
		"active_priests": religion_active_priest_count(),
		"priest_capacity": religion_priest_conversion_cap(),
		"remaining_capacity": religion_remaining_ritual_capacity()
	}

func religion_active_priest_count() -> int:
	return int(population.get("tlamacazqueh", 0))

func religion_priest_conversion_cap() -> float:
	return 8.0 + float(religion_active_priest_count()) * 2.0

func religion_remaining_ritual_capacity() -> float:
	return maxf(0.0, religion_priest_conversion_cap() - ritual_capacity_used_this_veintena)

func get_divine_favour(god_id: String) -> float:
	_ensure_religion_state()
	return clampf(float(divine_favour.get(god_id, RELIGION_STARTING_FAVOUR)), 0.0, 100.0)

func get_shrine_level(god_id: String) -> int:
	_ensure_religion_state()
	return clampi(int(shrine_levels.get(god_id, 1)), 1, 4)

func get_purchased_shrine_upgrades(god_id: String) -> Array[String]:
	_ensure_religion_state()
	var output: Array[String] = []
	var raw: Array = shrine_upgrades.get(god_id, []) as Array
	for item: Variant in raw:
		output.append(String(item))
	return output

func has_shrine_upgrade(god_id: String, upgrade_id: String) -> bool:
	return get_purchased_shrine_upgrades(god_id).has(upgrade_id)

func can_pay_religion_cost(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		if free_stock_after_reserves(resource_id) + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(needed) + " free " + get_resource_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Ready."}

func pay_religion_cost(cost: Dictionary) -> void:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_variant]))

func shrine_level_cost(next_level: int) -> Dictionary:
	match next_level:
		2:
			return {"wood": 20.0, "cloth": 6.0, "ritual_goods": 1.0}
		3:
			return {"wood": 50.0, "cloth": 15.0, "ritual_goods": 4.0, "cacao": 2.0}
		4:
			return {"wood": 100.0, "cloth": 30.0, "ritual_goods": 8.0, "cacao": 4.0, "fine_textiles": 1.0}
	return {}

func shrine_level_priest_requirement(next_level: int) -> int:
	match next_level:
		2:
			return 2
		3:
			return 5
		4:
			return 8
	return 0

func can_upgrade_shrine(god_id: String) -> Dictionary:
	var level: int = get_shrine_level(god_id)
	if level >= 4:
		return {"ok": false, "reason": "Shrine is already Level 4."}
	var next_level: int = level + 1
	var priest_req: int = shrine_level_priest_requirement(next_level)
	if religion_active_priest_count() < priest_req:
		return {"ok": false, "reason": "Requires " + str(priest_req) + " active priests."}
	return can_pay_religion_cost(shrine_level_cost(next_level))

func upgrade_shrine(god_id: String) -> Dictionary:
	_ensure_religion_state()
	var status: Dictionary = can_upgrade_shrine(god_id)
	if not bool(status.get("ok", false)):
		_record_religion_report("Shrine upgrade failed: " + String(status.get("reason", "")))
		return status
	var next_level: int = get_shrine_level(god_id) + 1
	pay_religion_cost(shrine_level_cost(next_level))
	shrine_levels[god_id] = next_level
	var message: String = god_name(god_id) + " Shrine upgraded to Level " + str(next_level) + "."
	_record_religion_report(message)
	emit_signal("state_changed")
	return {"ok": true, "reason": message, "level": next_level}

func god_upgrade_definitions(god_id: String) -> Array[Dictionary]:
	match god_id:
		"tlaloc":
			return [
				{"id": "rain_basin", "title": "Rain Basin", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A basin for reading water, clouds and lake signs.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "canal_offering_steps", "title": "Canal Offering Steps", "level": 2, "priests": 2, "cost": {"wood": 20.0, "cloth": 5.0, "ritual_goods": 2.0}, "description": "Ritual steps linking shrine offerings to fields, canals and chinampas.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "harvest_idol", "title": "Harvest Idol", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cacao": 1.0, "ritual_goods": 4.0}, "description": "A major idol for harvest gratitude and drought protection hooks.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "storm_court", "title": "Storm Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full court for future rain boons, drought softening and agricultural rites.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
		"huitzilopochtli":
			return [
				{"id": "war_banners", "title": "War Banners", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "Battle banners sanctify warrior musters and small martial rites.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "captive_stone", "title": "Captive Stone", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A ritual stone for future captive sacrifice and Flower War payoff.", "favour_bonus": 2, "decay_reduction": 0.20},
				{"id": "eagle_arsenal_altar", "title": "Eagle Arsenal Altar", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "An altar binding weapon preparation to martial prestige.", "favour_bonus": 3, "decay_reduction": 0.30},
				{"id": "sun_war_court", "title": "Sun-War Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full war court for future Flower War boons, captive yield and martial recognition.", "favour_bonus": 5, "decay_reduction": 0.45}
			]
		"tezcatlipoca":
			return [
				{"id": "obsidian_mirror", "title": "Obsidian Mirror", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A mirror for reading first omens and hidden danger.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "smoke_vestry", "title": "Smoke Vestry", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A chamber for controlled smoke rites, future warnings and rival pressure hooks.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "jaguar_shadow_wall", "title": "Jaguar Shadow Wall", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "A symbolic barrier against plots, scandals and sabotage.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "night_court", "title": "Night Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A court for future intrigue boons, counter-plots and hidden information.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
		"quetzalcoatl":
			return [
				{"id": "feathered_brazier", "title": "Feathered Brazier", "level": 1, "priests": 1, "cost": {"wood": 8.0, "ritual_goods": 1.0}, "description": "A civilising fire for transition rites and household legitimacy.", "favour_bonus": 1, "decay_reduction": 0.0},
				{"id": "scribe_mat", "title": "Scribe Mat", "level": 2, "priests": 2, "cost": {"wood": 18.0, "cacao": 1.0, "ritual_goods": 2.0}, "description": "A ritual space for record, order, tribute promises and palace-facing legitimacy.", "favour_bonus": 2, "decay_reduction": 0.25},
				{"id": "market_wind_gate", "title": "Market Wind Gate", "level": 3, "priests": 4, "cost": {"wood": 35.0, "cloth": 8.0, "ritual_goods": 4.0}, "description": "A ceremonial gate linking trade, diplomacy and public order.", "favour_bonus": 3, "decay_reduction": 0.35},
				{"id": "feathered_court", "title": "Feathered Court", "level": 4, "priests": 6, "cost": {"wood": 70.0, "cloth": 15.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, "description": "A full court for future recognition boons, ruler interactions and legitimacy protection.", "favour_bonus": 5, "decay_reduction": 0.50}
			]
	return []

func upgrade_by_id(god_id: String, upgrade_id: String) -> Dictionary:
	for data: Dictionary in god_upgrade_definitions(god_id):
		if String(data.get("id", "")) == upgrade_id:
			return data
	return {}

func upgrade_is_active(upgrade: Dictionary) -> bool:
	return religion_active_priest_count() >= int(upgrade.get("priests", 0))

func can_purchase_shrine_upgrade(god_id: String, upgrade_id: String) -> Dictionary:
	var upgrade: Dictionary = upgrade_by_id(god_id, upgrade_id)
	if upgrade.is_empty():
		return {"ok": false, "reason": "Unknown shrine upgrade."}
	if has_shrine_upgrade(god_id, upgrade_id):
		return {"ok": false, "reason": "Already built."}
	var req_level: int = int(upgrade.get("level", 1))
	if get_shrine_level(god_id) < req_level:
		return {"ok": false, "reason": "Requires Shrine Level " + str(req_level) + "."}
	var req_priests: int = int(upgrade.get("priests", 0))
	if religion_active_priest_count() < req_priests:
		return {"ok": false, "reason": "Requires " + str(req_priests) + " active priests."}
	return can_pay_religion_cost(upgrade.get("cost", {}) as Dictionary)

func purchase_shrine_upgrade(god_id: String, upgrade_id: String) -> Dictionary:
	_ensure_religion_state()
	var upgrade: Dictionary = upgrade_by_id(god_id, upgrade_id)
	var status: Dictionary = can_purchase_shrine_upgrade(god_id, upgrade_id)
	if not bool(status.get("ok", false)):
		_record_religion_report("Shrine upgrade failed: " + String(status.get("reason", "")))
		return status
	pay_religion_cost(upgrade.get("cost", {}) as Dictionary)
	var upgrades: Array[String] = get_purchased_shrine_upgrades(god_id)
	upgrades.append(upgrade_id)
	shrine_upgrades[god_id] = upgrades
	var message: String = "Built " + String(upgrade.get("title", "upgrade")) + " for " + god_name(god_id) + "."
	_record_religion_report(message)
	emit_signal("state_changed")
	return {"ok": true, "reason": message}

func ritual_data(god_id: String, tier_id: String) -> Dictionary:
	var title_prefix: String = "Ritual"
	match tier_id:
		"minor":
			title_prefix = "Minor Rite"
		"medium":
			title_prefix = "Medium Ceremony"
		"large":
			title_prefix = "Large Festival"
	var data: Dictionary = {"tier": tier_id, "title": title_prefix, "level": 1, "capacity": 4.0, "min": 3, "max": 7, "cost": {}, "description": ""}
	match tier_id:
		"minor":
			data["level"] = 1
			data["capacity"] = 4.0
			data["min"] = 3
			data["max"] = 7
		"medium":
			data["level"] = 2
			data["capacity"] = 10.0
			data["min"] = 8
			data["max"] = 16
		"large":
			data["level"] = 3
			data["capacity"] = 18.0
			data["min"] = 18
			data["max"] = 32
	match god_id:
		"tlaloc":
			if tier_id == "minor":
				data["cost"] = {"maize": 10.0}
				data["description"] = "A small food and water rite to maintain rain favour."
			elif tier_id == "medium":
				data["cost"] = {"maize": 25.0, "cacao": 1.0, "ritual_goods": 1.0}
				data["description"] = "A serious agricultural ceremony for rain, canals and fertility."
			else:
				data["cost"] = {"maize": 60.0, "cacao": 2.0, "ritual_goods": 3.0, "fine_textiles": 1.0}
				data["description"] = "A public harvest and rain festival with major future drought-protection hooks."
		"huitzilopochtli":
			if tier_id == "minor":
				data["cost"] = {"maize": 8.0, "ritual_goods": 1.0}
				data["description"] = "A small martial rite for warrior courage and public discipline."
			elif tier_id == "medium":
				data["cost"] = {"maize": 15.0, "cacao": 1.0, "ritual_goods": 2.0}
				data["description"] = "A warrior ceremony preparing the house for Flower Wars and sacrifice."
			else:
				data["cost"] = {"cacao": 2.0, "ritual_goods": 4.0, "fine_textiles": 1.0, "captives": 2.0}
				data["description"] = "A great war festival using captives for major future martial-prestige hooks."
		"tezcatlipoca":
			if tier_id == "minor":
				data["cost"] = {"cacao": 1.0}
				data["description"] = "A small omen rite using elite goods to read hidden pressure."
			elif tier_id == "medium":
				data["cost"] = {"cacao": 2.0, "ritual_goods": 2.0}
				data["description"] = "A smoke and mirror ceremony for intrigue, ambition and rival danger."
			else:
				data["cost"] = {"cacao": 4.0, "ritual_goods": 4.0, "fine_textiles": 1.0, "captives": 1.0}
				data["description"] = "A dangerous night festival for future sabotage, counter-plot and scandal hooks."
		"quetzalcoatl":
			if tier_id == "minor":
				data["cost"] = {"maize": 5.0, "cacao": 1.0}
				data["description"] = "A small legitimacy rite for order, wisdom and transition."
			elif tier_id == "medium":
				data["cost"] = {"cacao": 2.0, "ritual_goods": 1.0}
				data["description"] = "A civil ceremony for trade, diplomacy and palace-facing legitimacy."
			else:
				data["cost"] = {"cacao": 3.0, "ritual_goods": 3.0, "fine_textiles": 2.0}
				data["description"] = "A great ceremonial festival for future recognition and ruler-interaction hooks."
	return data

func ritual_favour_bonus(god_id: String, tier_id: String, festival_god_id: String = "") -> int:
	var bonus: int = max(0, get_shrine_level(god_id) - 1)
	if festival_god_id == god_id:
		match tier_id:
			"minor":
				bonus += 1
			"medium":
				bonus += 2
			"large":
				bonus += 4
	for upgrade_id: String in get_purchased_shrine_upgrades(god_id):
		var upgrade: Dictionary = upgrade_by_id(god_id, upgrade_id)
		if not upgrade.is_empty() and upgrade_is_active(upgrade):
			bonus += int(upgrade.get("favour_bonus", 0))
	return bonus

func ritual_favour_range(god_id: String, tier_id: String, festival_god_id: String = "") -> Array:
	var data: Dictionary = ritual_data(god_id, tier_id)
	var bonus: int = ritual_favour_bonus(god_id, tier_id, festival_god_id)
	return [int(data.get("min", 0)) + bonus, int(data.get("max", 0)) + bonus]

func can_perform_ritual(god_id: String, tier_id: String) -> Dictionary:
	var data: Dictionary = ritual_data(god_id, tier_id)
	var req_level: int = int(data.get("level", 1))
	if get_shrine_level(god_id) < req_level:
		return {"ok": false, "reason": "Requires Shrine Level " + str(req_level) + "."}
	var capacity_cost: float = float(data.get("capacity", 0.0))
	if religion_remaining_ritual_capacity() + 0.001 < capacity_cost:
		return {"ok": false, "reason": "Not enough remaining priest ritual capacity this Veintena."}
	return can_pay_religion_cost(data.get("cost", {}) as Dictionary)

func perform_ritual(god_id: String, tier_id: String, festival_god_id: String = "") -> Dictionary:
	_ensure_religion_state()
	var status: Dictionary = can_perform_ritual(god_id, tier_id)
	if not bool(status.get("ok", false)):
		_record_religion_report("Ritual failed: " + String(status.get("reason", "")))
		return status
	var data: Dictionary = ritual_data(god_id, tier_id)
	pay_religion_cost(data.get("cost", {}) as Dictionary)
	ritual_capacity_used_this_veintena += float(data.get("capacity", 0.0))
	var range: Array = ritual_favour_range(god_id, tier_id, festival_god_id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var gain: int = rng.randi_range(int(range[0]), int(range[1]))
	var before: float = get_divine_favour(god_id)
	var after: float = clampf(before + float(gain), 0.0, 100.0)
	divine_favour[god_id] = after
	var message: String = String(data.get("title", "Ritual")) + " performed for " + god_name(god_id) + ". Favour roll: +" + str(gain) + ". Favour " + _format_amount(before) + " → " + _format_amount(after) + "."
	_record_religion_report(message)
	emit_signal("state_changed")
	return {"ok": true, "reason": message, "gain": gain, "before": before, "after": after}

func apply_divine_favour_decay(decay_amount: float = RELIGION_NORMAL_DECAY) -> Array[String]:
	_ensure_religion_state()
	var parts: Array[String] = []
	for god_id: String in GOD_IDS:
		var before: float = get_divine_favour(god_id)
		var actual_decay: float = religion_decay_for_god(god_id, decay_amount)
		var after: float = clampf(before - actual_decay, 0.0, 100.0)
		divine_favour[god_id] = after
		parts.append(god_name(god_id) + " " + _format_amount(before) + "→" + _format_amount(after))
	_record_religion_report("Divine favour decays: " + "; ".join(parts) + ".")
	return parts

func religion_decay_for_god(god_id: String, base_decay: float) -> float:
	var reduction: float = 0.0
	for upgrade_id: String in get_purchased_shrine_upgrades(god_id):
		var upgrade: Dictionary = upgrade_by_id(god_id, upgrade_id)
		if not upgrade.is_empty() and upgrade_is_active(upgrade):
			reduction += float(upgrade.get("decay_reduction", 0.0))
	return maxf(0.0, base_decay - reduction)

func reset_religion_veintena_capacity() -> void:
	ritual_capacity_used_this_veintena = 0.0

func get_recent_ritual_reports() -> Array[String]:
	var output: Array[String] = []
	for line: String in recent_ritual_reports:
		output.append(line)
	return output

func _record_religion_report(message: String) -> void:
	recent_ritual_reports.clear()
	recent_ritual_reports.append(message)
	last_report.append(message)

func god_name(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Tlaloc"
		"huitzilopochtli":
			return "Huitzilopochtli"
		"tezcatlipoca":
			return "Tezcatlipoca"
		"quetzalcoatl":
			return "Quetzalcoatl"
	return "Unknown God"



# -----------------------------------------------------------------------------
# Barracks / Flower Wars v1
# -----------------------------------------------------------------------------

func get_warrior_house_count() -> int:
	var total: int = 0
	for id: String in ["warrior_house", "warrior_housing", "barracks"]:
		total += int(estate_buildings.get(id, 0))
	return total

func get_warrior_capacity() -> int:
	return get_warrior_house_count() * 10

func get_warrior_count() -> int:
	return int(population.get("yaotequihuaqueh", 0))

func get_player_prestige() -> float:
	return player_prestige

func get_prestige_summary() -> Dictionary:
	return {"prestige": player_prestige, "standing": "Standing: local claim forming", "recognition": "Recognition: unproven", "recent": "Last change: " + (last_flower_war_report[0] if not last_flower_war_report.is_empty() else "none")}

func _warrior_recruitment_cost(amount: int) -> Dictionary:
	return {"weapons": float(amount), "maize": float(amount), "cloth": float(amount) * 0.5}

func _can_pay_free_stock(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		if free_stock_after_reserves(resource_id) + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(needed) + " free " + get_resource_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Ready."}

func _pay_cost(cost: Dictionary) -> void:
	for resource_variant: Variant in cost.keys():
		_add_stock(String(resource_variant), -float(cost[resource_variant]))

func can_recruit_warriors(amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "Choose at least 1 warrior."}
	var remaining_turn_recruits: int = max(0, 2 - warrior_recruits_used_this_veintena)
	if remaining_turn_recruits <= 0:
		return {"ok": false, "reason": "Warrior recruitment limit reached this Veintena."}
	if amount > remaining_turn_recruits:
		return {"ok": false, "reason": "Can recruit only " + str(remaining_turn_recruits) + " more warrior(s) this Veintena."}
	var free_capacity: int = get_warrior_capacity() - get_warrior_count()
	if free_capacity <= 0:
		return {"ok": false, "reason": "No free Warrior House capacity."}
	if amount > free_capacity:
		return {"ok": false, "reason": "Only " + str(free_capacity) + " free warrior capacity."}
	return _can_pay_free_stock(_warrior_recruitment_cost(amount))

func recruit_warriors(amount: int) -> Dictionary:
	var status: Dictionary = can_recruit_warriors(amount)
	if not bool(status.get("ok", false)):
		last_report.append("Warrior recruitment failed: " + String(status.get("reason", "")))
		emit_signal("state_changed")
		return status
	_pay_cost(_warrior_recruitment_cost(amount))
	population["yaotequihuaqueh"] = get_warrior_count() + amount
	warrior_recruits_used_this_veintena += amount
	var message: String = "Recruited " + str(amount) + " warrior(s)."
	last_report.append(message)
	emit_signal("state_changed")
	return {"ok": true, "reason": message, "recruited": amount}

func get_flower_war_options() -> Dictionary:
	return {"doctrines": FLOWER_WAR_DOCTRINES.duplicate(true), "scales": FLOWER_WAR_SCALES.duplicate(true), "provisioning": FLOWER_WAR_PROVISIONING.duplicate(true)}

func _provisioning_cost(committed_warriors: int, provisioning_id: String) -> Dictionary:
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING.get(provisioning_id, FLOWER_WAR_PROVISIONING["standard"]) as Dictionary
	var mult: float = float(provisioning.get("cost_mult", 1.0))
	return {"maize": float(committed_warriors) * 1.0 * mult, "cacao": float(committed_warriors) * 0.05 * mult, "cloth": float(committed_warriors) * 0.1 * mult}

func _flower_war_weapon_commitment(committed_warriors: int) -> Dictionary:
	return {"weapons": float(committed_warriors)}

func _combined_flower_war_cost(committed_warriors: int, provisioning_id: String) -> Dictionary:
	var cost: Dictionary = _provisioning_cost(committed_warriors, provisioning_id)
	_add_dictionary_amounts(cost, _flower_war_weapon_commitment(committed_warriors))
	return cost

func can_launch_flower_war(scale_id: String, doctrine_id: String, provisioning_id: String, committed_warriors: int) -> Dictionary:
	if not FLOWER_WAR_SCALES.has(scale_id):
		return {"ok": false, "reason": "Unknown Flower War scale."}
	if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
		return {"ok": false, "reason": "Unknown doctrine."}
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		return {"ok": false, "reason": "Unknown provisioning."}
	if committed_warriors <= 0:
		return {"ok": false, "reason": "Commit at least 1 warrior."}
	if committed_warriors > get_warrior_count():
		return {"ok": false, "reason": "Not enough warriors."}
	return _can_pay_free_stock(_combined_flower_war_cost(committed_warriors, provisioning_id))

func get_flower_war_preview(scale_id: String, doctrine_id: String, provisioning_id: String, committed_warriors: int) -> Dictionary:
	var scale: Dictionary = FLOWER_WAR_SCALES.get(scale_id, FLOWER_WAR_SCALES["minor"]) as Dictionary
	var status: Dictionary = can_launch_flower_war(scale_id, doctrine_id, provisioning_id, committed_warriors)
	var recommended: int = int(scale.get("recommended", 5))
	var risk: String = "Good match"
	if committed_warriors < recommended:
		risk = "Understrength"
	elif committed_warriors >= recommended * 2:
		risk = "Overwhelming commitment"
	return {"ok": bool(status.get("ok", false)), "reason": String(status.get("reason", "")), "cost": _combined_flower_war_cost(committed_warriors, provisioning_id), "recommended": recommended, "risk": risk, "scale": scale.duplicate(true)}

func launch_flower_war(scale_id: String, doctrine_id: String, provisioning_id: String, committed_warriors: int) -> Dictionary:
	var status: Dictionary = can_launch_flower_war(scale_id, doctrine_id, provisioning_id, committed_warriors)
	if not bool(status.get("ok", false)):
		last_flower_war_report = ["Flower War could not be launched: " + String(status.get("reason", ""))]
		emit_signal("state_changed")
		return status
	_pay_cost(_combined_flower_war_cost(committed_warriors, provisioning_id))
	var result: Dictionary = _resolve_flower_war(scale_id, doctrine_id, provisioning_id, committed_warriors)
	_apply_flower_war_result(result)
	last_flower_war_report = _flower_war_report_lines(result)
	flower_war_history.append(result.duplicate(true))
	last_report.clear()
	for line: String in last_flower_war_report:
		last_report.append(line)
	emit_signal("flower_war_resolved", result)
	emit_signal("state_changed")
	return result

func _resolve_flower_war(scale_id: String, doctrine_id: String, provisioning_id: String, committed_warriors: int) -> Dictionary:
	var scale: Dictionary = FLOWER_WAR_SCALES[scale_id] as Dictionary
	var doctrine: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var enemy_count: int = int(scale.get("enemy_warriors", 5))
	var difficulty: float = float(scale.get("difficulty", 1.0))
	var h_favour: float = get_divine_favour("huitzilopochtli")
	var favour_mult: float = 1.0
	if h_favour >= 80.0:
		favour_mult = 1.10
	elif h_favour >= 60.0:
		favour_mult = 1.05
	elif h_favour < 25.0:
		favour_mult = 0.95
	var attacker_offence: float = float(committed_warriors) * float(doctrine.get("offence", 1.0)) * float(provisioning.get("combat_mult", 1.0)) * favour_mult * rng.randf_range(0.92, 1.08)
	var attacker_defence: float = float(committed_warriors) * float(doctrine.get("defence", 1.0)) * rng.randf_range(0.92, 1.08)
	var defender_offence: float = float(enemy_count) * difficulty
	var defender_defence: float = float(enemy_count) * difficulty
	var defender_damage_ratio: float = attacker_offence / maxf(1.0, defender_defence)
	var defender_casualty_rate: float = clampf((defender_damage_ratio - 0.55) * 0.35, 0.05, 0.65)
	var defender_casualties: int = clampi(int(round(float(enemy_count) * defender_casualty_rate)), 0, enemy_count)
	var remaining_defenders: int = max(0, enemy_count - defender_casualties)
	var counterattack_strength: float = float(remaining_defenders) * difficulty
	var attacker_damage_ratio: float = counterattack_strength / maxf(1.0, attacker_defence)
	var attacker_casualty_rate: float = clampf((attacker_damage_ratio - 0.45) * 0.35, 0.03, 0.75)
	var attacker_casualties: int = clampi(int(round(float(committed_warriors) * attacker_casualty_rate)), 0, committed_warriors)
	var net_per_warrior: float = float(defender_casualties - attacker_casualties) / maxf(1.0, float(committed_warriors))
	var result_label: String = "Stalemate"
	if net_per_warrior >= 0.45:
		result_label = "Crushing Victory"
	elif net_per_warrior >= 0.15:
		result_label = "Victory"
	elif net_per_warrior > -0.15:
		result_label = "Stalemate"
	elif net_per_warrior > -0.45:
		result_label = "Defeat"
	else:
		result_label = "Crushing Loss"
	var death_share: float = _flower_war_death_share(result_label) * float(doctrine.get("death_mult", 1.0))
	var deaths: int = clampi(int(round(float(attacker_casualties) * death_share)), 0, attacker_casualties)
	var injuries: int = max(0, attacker_casualties - deaths)
	var captives: int = _flower_war_captives(result_label, defender_casualties, committed_warriors, doctrine_id)
	var loot_value: float = _flower_war_loot_value(result_label, committed_warriors, doctrine_id)
	var loot: Dictionary = _flower_war_loot_goods(loot_value)
	var prestige_gain: float = _flower_war_prestige(result_label, captives, defender_casualties, loot_value, doctrine_id)
	var weapon_loss_rate: float = 0.20
	match result_label:
		"Crushing Victory", "Victory": weapon_loss_rate = 0.10
		"Stalemate": weapon_loss_rate = 0.20
		"Defeat": weapon_loss_rate = 0.35
		"Crushing Loss": weapon_loss_rate = 0.45
	var weapons_lost: int = clampi(int(ceil(float(committed_warriors) * weapon_loss_rate + float(deaths) * 0.5)), 0, committed_warriors)
	return {"ok": true, "scale_id": scale_id, "scale_name": String(scale.get("name", scale_id)), "doctrine_id": doctrine_id, "doctrine_name": String(doctrine.get("name", doctrine_id)), "provisioning_id": provisioning_id, "provisioning_name": String(provisioning.get("name", provisioning_id)), "committed_warriors": committed_warriors, "enemy_warriors": enemy_count, "result": result_label, "attacker_casualties": attacker_casualties, "defender_casualties": defender_casualties, "deaths": deaths, "injuries": injuries, "captives": captives, "loot_value": loot_value, "loot": loot, "prestige": prestige_gain, "weapons_lost": weapons_lost}

func _flower_war_death_share(result_label: String) -> float:
	match result_label:
		"Crushing Victory": return 0.10
		"Victory": return 0.20
		"Stalemate": return 0.30
		"Defeat": return 0.45
		"Crushing Loss": return 0.65
	return 0.30

func _flower_war_captives(result_label: String, defender_casualties: int, committed_warriors: int, doctrine_id: String) -> int:
	if result_label != "Victory" and result_label != "Crushing Victory":
		return 0
	var rate: float = 0.30
	if result_label == "Crushing Victory":
		rate = 0.45
	if doctrine_id == "eagle":
		rate = minf(0.75, rate + float(committed_warriors) * 0.02)
	var raw: float = float(defender_casualties) * rate
	var captives: int = int(floor(raw))
	if defender_casualties >= 1 and raw > 0.0 and captives < 1:
		captives = 1
	return clampi(captives, 0, defender_casualties)

func _flower_war_loot_value(result_label: String, committed_warriors: int, doctrine_id: String) -> float:
	var value: float = 0.0
	match result_label:
		"Crushing Victory": value = float(committed_warriors) * 4.0
		"Victory": value = float(committed_warriors) * 2.5
		"Stalemate": value = float(committed_warriors) * 1.2
		_: value = 0.0
	if doctrine_id == "coyote":
		value *= 1.25
	return value

func _flower_war_loot_goods(loot_value: float) -> Dictionary:
	var loot: Dictionary = {}
	if loot_value <= 0.001:
		return loot
	var weights: Dictionary = {"maize": 0.35, "wood": 0.20, "cotton": 0.15, "cloth": 0.10, "tools": 0.08, "obsidian": 0.06, "cacao": 0.04, "ritual_goods": 0.02}
	for resource_variant: Variant in weights.keys():
		var resource_id: String = String(resource_variant)
		var value_share: float = loot_value * float(weights[resource_variant])
		var unit_value: float = 1.0
		if resources.has(resource_id):
			unit_value = maxf(0.1, float((resources[resource_id] as Dictionary).get("base_value", 1.0)))
		var amount: float = snappedf(value_share / unit_value, 0.01)
		if amount > 0.001:
			loot[resource_id] = amount
	return loot

func _flower_war_prestige(result_label: String, captives: int, defender_casualties: int, loot_value: float, doctrine_id: String) -> float:
	var prestige: float = 0.0
	match result_label:
		"Crushing Victory": prestige += 12.0
		"Victory": prestige += 6.0
		"Stalemate": prestige += 1.0
		"Crushing Loss": prestige -= 3.0
	prestige += float(captives) * 3.0
	prestige += float(defender_casualties) * 0.5
	prestige += loot_value * 0.05
	if doctrine_id == "jaguar" and prestige > 0.0:
		prestige *= 1.15
	return snappedf(prestige, 0.01)

func _apply_flower_war_result(result: Dictionary) -> void:
	population["yaotequihuaqueh"] = max(0, get_warrior_count() - int(result.get("deaths", 0)))
	_add_stock("weapons", -float(result.get("weapons_lost", 0)))
	_add_stock("captives", float(result.get("captives", 0)))
	var loot: Dictionary = result.get("loot", {}) as Dictionary
	for resource_variant: Variant in loot.keys():
		_add_stock(String(resource_variant), float(loot[resource_variant]))
	player_prestige += float(result.get("prestige", 0.0))
	warrior_xp += maxf(0.0, float(result.get("defender_casualties", 0)))

func _flower_war_report_lines(result: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append(String(result.get("scale_name", "Flower War")) + " resolved: " + String(result.get("result", "Result")) + ".")
	lines.append("Committed " + str(int(result.get("committed_warriors", 0))) + " " + String(result.get("doctrine_name", "warriors")) + " warriors with " + String(result.get("provisioning_name", "Standard")) + " provisioning.")
	lines.append("Casualties: " + str(int(result.get("attacker_casualties", 0))) + " affected; " + str(int(result.get("deaths", 0))) + " dead, " + str(int(result.get("injuries", 0))) + " injured and returned.")
	lines.append("Enemy casualties: " + str(int(result.get("defender_casualties", 0))) + "; captives gained: " + str(int(result.get("captives", 0))) + ".")
	lines.append("Loot value: " + _format_amount(float(result.get("loot_value", 0.0))) + "; prestige change: " + _format_amount(float(result.get("prestige", 0.0))) + "; weapons lost: " + str(int(result.get("weapons_lost", 0))) + ".")
	var loot: Dictionary = result.get("loot", {}) as Dictionary
	if not loot.is_empty():
		var parts: Array[String] = []
		for resource_variant: Variant in loot.keys():
			parts.append(get_resource_name(String(resource_variant)) + " " + _format_amount(float(loot[resource_variant])))
		lines.append("Looted goods: " + ", ".join(parts) + ".")
	return lines

func get_last_flower_war_report() -> Array[String]:
	var output: Array[String] = []
	for line: String in last_flower_war_report:
		output.append(line)
	return output

func get_barracks_summary() -> Dictionary:
	var warriors: int = get_warrior_count()
	var capacity: int = get_warrior_capacity()
	var weapons: float = _stock("weapons")
	return {"warriors": warriors, "capacity": capacity, "free_capacity": max(0, capacity - warriors), "weapons": weapons, "minor_ready": warriors >= 5 and weapons >= 5.0, "standard_ready": warriors >= 10 and weapons >= 10.0, "major_ready": warriors >= 20 and weapons >= 20.0, "recruits_remaining": max(0, 2 - warrior_recruits_used_this_veintena), "prestige": player_prestige, "warrior_xp": warrior_xp, "last_report": get_last_flower_war_report()}

func advance_veintena() -> void:
	if not initialized: new_game()
	last_report.clear()
	last_report.append("Veintena " + str(current_veintena) + " resolves.")
	_pay_population_upkeep()
	_pay_housing_maintenance()
	_operate_buildings()
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		last_report.append("Nemontemi reckoning placeholder: the next Ritual Year begins.")
	warrior_recruits_used_this_veintena = 0
	last_report.append("Now entering Veintena " + str(current_veintena) + ".")
	emit_signal("turn_advanced", last_report)
	emit_signal("state_changed")

func estimate_population_upkeep() -> Dictionary:
	var result: Dictionary = {}
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		var count: int = _active_population_for_group(group_id)
		var rates: Dictionary = population_upkeep_rates.get(group_id, {}) as Dictionary
		for resource_variant: Variant in rates.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(rates[resource_id]) * float(count) / 5.0
	return result

func estimate_housing_maintenance() -> Dictionary:
	var result: Dictionary = {}
	_ensure_active_housing_counts()
	for building_id: String in active_housing_counts.keys():
		if not buildings.has(building_id): continue
		var count: int = int(active_housing_counts.get(building_id, 0))
		var maintenance: Dictionary = (buildings[building_id] as Dictionary).get("housing_maintenance", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_id]) * count
	return result

func estimate_building_inputs() -> Dictionary:
	return (estimate_production_resolution().get("inputs", {}) as Dictionary).duplicate(true)

func estimate_building_outputs() -> Dictionary:
	return (estimate_production_resolution().get("outputs", {}) as Dictionary).duplicate(true)

func estimate_production_resolution() -> Dictionary:
	_ensure_labour_assignments()
	var temp_stockpile: Dictionary = _copy_stockpile_dictionary(estate_stockpiles)
	var upkeep_needed: Dictionary = estimate_population_upkeep()
	var maintenance_needed: Dictionary = estimate_housing_maintenance()
	var upkeep_paid: Dictionary = {}
	var upkeep_shortfalls: Dictionary = {}
	var maintenance_paid: Dictionary = {}
	var maintenance_shortfalls: Dictionary = {}
	for resource_variant: Variant in upkeep_needed.keys():
		var resource_id: String = String(resource_variant)
		var paid: float = minf(float(temp_stockpile.get(resource_id, 0.0)), float(upkeep_needed[resource_variant]))
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - paid
		upkeep_paid[resource_id] = paid
		if paid < float(upkeep_needed[resource_variant]): upkeep_shortfalls[resource_id] = float(upkeep_needed[resource_variant]) - paid
	for resource_variant: Variant in maintenance_needed.keys():
		var resource_id: String = String(resource_variant)
		var paid: float = minf(float(temp_stockpile.get(resource_id, 0.0)), float(maintenance_needed[resource_variant]))
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - paid
		maintenance_paid[resource_id] = paid
		if paid < float(maintenance_needed[resource_variant]): maintenance_shortfalls[resource_id] = float(maintenance_needed[resource_variant]) - paid
	var total_inputs: Dictionary = {}
	var total_outputs: Dictionary = {}
	var building_statuses: Dictionary = {}
	var report_lines: Array[String] = []
	for building_id: String in building_order:
		if not buildings.has(building_id): continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var count: int = int(estate_buildings.get(building_id, 0))
		var staffed_count: int = count if not _is_productive_building_id(building_id) else _staffed_count_for_building(building_id)
		staffed_count = clampi(staffed_count, 0, count)
		var operated: int = 0
		var input_blocked: int = 0
		var input_shortages: Array[String] = []
		for index: int in range(staffed_count):
			var reason: String = _can_operate_instance_with_stockpile(definition, temp_stockpile)
			if reason == "":
				var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
				var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
				_consume_inputs_from_stockpile(inputs, temp_stockpile)
				_add_outputs_to_stockpile(outputs, temp_stockpile)
				_add_dictionary_amounts(total_inputs, inputs)
				_add_dictionary_amounts(total_outputs, outputs)
				operated += 1
			else:
				input_blocked += 1
				input_shortages.append(reason)
		var unstaffed: int = max(0, count - staffed_count)
		var status_text: String = "Operating x" + str(operated)
		if unstaffed > 0: status_text += "; unstaffed x" + str(unstaffed)
		if input_blocked > 0: status_text += "; input blocked " + str(input_blocked)
		building_statuses[building_id] = {"operating": operated, "blocked": input_blocked + unstaffed, "staffed_count": staffed_count, "unstaffed": unstaffed, "input_blocked": input_blocked, "status_text": status_text, "input_shortages": input_shortages.duplicate()}
		if operated > 0: report_lines.append(String(definition.get("name", building_id)) + " would operate x" + str(operated) + ".")
	return {"inputs": total_inputs, "outputs": total_outputs, "building_statuses": building_statuses, "stockpile_after_upkeep_and_production": temp_stockpile, "upkeep_needed": upkeep_needed, "upkeep_paid": upkeep_paid, "upkeep_shortfalls": upkeep_shortfalls, "housing_maintenance_needed": maintenance_needed, "housing_maintenance_paid": maintenance_paid, "housing_maintenance_shortfalls": maintenance_shortfalls, "reports": report_lines}

func _copy_stockpile_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys(): output[String(key_variant)] = float(source[key_variant])
	return output

func _can_operate_instance_with_stockpile(definition: Dictionary, temp_stockpile: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if float(temp_stockpile.get(resource_id, 0.0)) < float(inputs[resource_variant]): return "not enough " + get_resource_name(resource_id) + " input"
	return ""

func _consume_inputs_from_stockpile(inputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys(): temp_stockpile[String(resource_variant)] = float(temp_stockpile.get(String(resource_variant), 0.0)) - float(inputs[resource_variant])

func _add_outputs_to_stockpile(outputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys(): temp_stockpile[String(resource_variant)] = float(temp_stockpile.get(String(resource_variant), 0.0)) + float(outputs[resource_variant])

func _add_dictionary_amounts(target: Dictionary, amounts: Dictionary) -> void:
	for resource_variant: Variant in amounts.keys():
		var resource_id: String = String(resource_variant)
		target[resource_id] = float(target.get(resource_id, 0.0)) + float(amounts[resource_variant])

func _pay_population_upkeep() -> void:
	for resource_variant: Variant in estimate_population_upkeep().keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(estimate_population_upkeep()[resource_id])
		var paid: float = minf(_stock(resource_id), needed)
		_add_stock(resource_id, -paid)
		last_report.append(("Paid population upkeep: " if paid >= needed else "Shortage: paid population upkeep ") + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")

func _pay_housing_maintenance() -> void:
	for resource_variant: Variant in estimate_housing_maintenance().keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(estimate_housing_maintenance()[resource_id])
		var paid: float = minf(_stock(resource_id), needed)
		_add_stock(resource_id, -paid)
		last_report.append(("Paid housing building upkeep: " if paid >= needed else "Housing building upkeep shortage: ") + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")

func _operate_buildings() -> void:
	_ensure_labour_assignments()
	for building_id: String in building_order:
		if not buildings.has(building_id): continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0: continue
		var target_count: int = count if not _is_productive_building_id(building_id) else _staffed_count_for_building(building_id)
		var operated: int = 0
		var blocked: int = 0
		for index: int in range(target_count):
			var reason: String = _can_operate_instance(definition)
			if reason == "":
				_consume_inputs(definition.get("inputs", {}) as Dictionary)
				_add_outputs(definition.get("outputs", {}) as Dictionary)
				operated += 1
			else:
				blocked += 1
				last_report.append(String(definition.get("name", building_id)) + " blocked: " + reason)
		if operated > 0: last_report.append(String(definition.get("name", building_id)) + " operated x" + str(operated) + ".")
		if _is_productive_building_id(building_id) and target_count < count: last_report.append(String(definition.get("name", building_id)) + " unstaffed x" + str(count - target_count) + ".")

func _can_operate_instance(definition: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if _stock(resource_id) < float(inputs[resource_variant]): return "not enough " + get_resource_name(resource_id) + " input"
	return ""

func _consume_inputs(inputs: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys(): _add_stock(String(resource_variant), -float(inputs[resource_variant]))

func _add_outputs(outputs: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys(): _add_stock(String(resource_variant), float(outputs[resource_variant]))

func _estimate_building_status(building_id: String) -> Dictionary:
	var statuses: Dictionary = estimate_production_resolution().get("building_statuses", {}) as Dictionary
	if statuses.has(building_id): return (statuses[building_id] as Dictionary).duplicate(true)
	return {"operating": 0, "blocked": 0, "staffed_count": 0, "unstaffed": 0, "input_blocked": 0, "status_text": "Not built.", "input_shortages": []}

func _estimated_operating_count_for_building(building_id: String) -> int:
	return int(_estimate_building_status(building_id).get("operating", 0))

func _is_productive_building_id(building_id: String) -> bool:
	if not buildings.has(building_id): return false
	var screen_id: String = String((buildings[building_id] as Dictionary).get("screen", ""))
	return screen_id == "chinampas" or screen_id == "workshops"

func _is_housing_building_id(building_id: String) -> bool:
	return buildings.has(building_id) and (buildings[building_id] as Dictionary).has("housing_capacity")

func _auto_staff_all_productive_buildings() -> void:
	labour_assignments.clear()
	var running_by_group: Dictionary = {}
	for building_id: String in _production_auto_staff_order():
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0: continue
		labour_assignments[building_id] = _default_assignment_for_building(building_id, count, running_by_group)
	_ensure_labour_assignments()

func _auto_staff_single_building_to_max(building_id: String) -> void:
	if not _is_productive_building_id(building_id): return
	labour_assignments[building_id] = _default_assignment_for_building(building_id, int(estate_buildings.get(building_id, 0)), {})
	_ensure_labour_assignments()

func _production_auto_staff_order() -> Array[String]:
	var maize_ids: Array[String] = []
	var other_ids: Array[String] = []
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id): continue
		if _is_maize_production_building(building_id): maize_ids.append(building_id)
		else: other_ids.append(building_id)
	maize_ids.append_array(other_ids)
	return maize_ids

func _is_maize_production_building(building_id: String) -> bool:
	if building_id.find("maize") >= 0: return true
	return buildings.has(building_id) and ((buildings[building_id] as Dictionary).get("outputs", {}) as Dictionary).has("maize")

func _ensure_labour_assignments() -> void:
	var running_by_group: Dictionary = {}
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id): continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			labour_assignments.erase(building_id)
			continue
		var requested: Dictionary = labour_assignments.get(building_id, {}) as Dictionary
		if requested.is_empty(): requested = _default_assignment_for_building(building_id, count, running_by_group)
		var final_assignments: Dictionary = {}
		var remaining_slots: int = count
		if _building_can_use_field_labour(building_id):
			var field_wanted: int = clampi(int(requested.get("field_labour", count)), 0, remaining_slots)
			var field_possible: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
			var field_count: int = mini(field_wanted, field_possible)
			if field_count > 0:
				final_assignments["field_labour"] = field_count
				var split: Dictionary = _field_labour_population_split_for_building(building_id, field_count, running_by_group)
				for member_variant: Variant in split.keys(): running_by_group[String(member_variant)] = int(running_by_group.get(String(member_variant), 0)) + int(split[member_variant])
				remaining_slots -= field_count
		for group_id: String in _allowed_worker_groups_for_building(building_id):
			if remaining_slots <= 0: break
			if _building_can_use_field_labour(building_id) and (group_id == "macehualtin" or group_id == "tlacotin"): continue
			var wanted: int = clampi(int(requested.get(group_id, remaining_slots)), 0, remaining_slots)
			var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
			var available_pop: int = max(0, _active_population_for_group(group_id) - int(running_by_group.get(group_id, 0)))
			var final_count: int = mini(wanted, int(floor(float(available_pop) / float(max(1, needed_per)))))
			if final_count > 0:
				final_assignments[group_id] = final_count
				running_by_group[group_id] = int(running_by_group.get(group_id, 0)) + final_count * needed_per
				remaining_slots -= final_count
		labour_assignments[building_id] = final_assignments

func _default_assignment_for_building(building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	var requested: Dictionary = {}
	if _building_can_use_field_labour(building_id):
		var use_field: int = mini(count, _max_staffable_count_for_field_labour_with_used(building_id, running_by_group))
		if use_field > 0:
			requested["field_labour"] = use_field
			return requested
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		var available_pop: int = max(0, _active_population_for_group(group_id) - int(running_by_group.get(group_id, 0)))
		var possible: int = int(floor(float(available_pop) / float(max(1, needed_per))))
		var use_count: int = mini(count, possible)
		if use_count > 0:
			requested[group_id] = use_count
			return requested
	return requested

func _allowed_worker_groups_for_building(building_id: String) -> Array[String]:
	var output: Array[String] = []
	if not buildings.has(building_id): return output
	var staff: Dictionary = (buildings[building_id] as Dictionary).get("staff", {}) as Dictionary
	for group_variant: Variant in staff.keys(): output.append(String(group_variant))
	return output

func _building_can_use_field_labour(building_id: String) -> bool:
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	return allowed.has("macehualtin") or allowed.has("tlacotin")

func _max_staffable_count_for_field_labour_with_used(building_id: String, running_by_group: Dictionary) -> int:
	var needed: int = _staff_required_per_copy_for_group(building_id, "macehualtin")
	var available: int = max(0, _active_population_for_group("macehualtin") + _active_population_for_group("tlacotin") - int(running_by_group.get("macehualtin", 0)) - int(running_by_group.get("tlacotin", 0)))
	return int(floor(float(available) / float(max(1, needed))))

func _field_labour_population_split_for_building(building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	var needed_total: int = _staff_required_per_copy_for_group(building_id, "macehualtin") * count
	var mace_available: int = max(0, _active_population_for_group("macehualtin") - int(running_by_group.get("macehualtin", 0)))
	var use_mace: int = mini(mace_available, needed_total)
	var use_tlacotin: int = max(0, needed_total - use_mace)
	var split: Dictionary = {}
	if use_mace > 0: split["macehualtin"] = use_mace
	if use_tlacotin > 0: split["tlacotin"] = use_tlacotin
	return split

func _staff_required_per_copy_for_group(building_id: String, group_id: String) -> int:
	if not buildings.has(building_id): return 0
	return int(((buildings[building_id] as Dictionary).get("staff", {}) as Dictionary).get(group_id, 0))

func _staffed_count_for_building(building_id: String) -> int:
	_ensure_labour_assignments()
	var assignment: Dictionary = labour_assignments.get(building_id, {}) as Dictionary
	var total: int = 0
	for key: Variant in assignment.keys(): total += int(assignment[key])
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func _active_population_for_group(group_id: String) -> int:
	return int(population.get(group_id, 0))

func _ensure_base_housing_capacity() -> void:
	for group_id: String in population.keys():
		if not base_housing_capacity.has(group_id): base_housing_capacity[group_id] = 0

func _ensure_active_housing_counts() -> void:
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id): continue
		active_housing_counts[building_id] = clampi(int(active_housing_counts.get(building_id, 0)), 0, int(estate_buildings.get(building_id, 0)))

func get_housing_mothball_data() -> Dictionary:
	return {"buildings": get_housing_buildings(), "summary": get_housing_summary()}

func get_housing_summary() -> Dictionary:
	var capacity: Dictionary = {}
	for group_id: String in base_housing_capacity.keys(): capacity[group_id] = int(base_housing_capacity.get(group_id, 0))
	_ensure_active_housing_counts()
	for building_id: String in active_housing_counts.keys():
		if not buildings.has(building_id): continue
		var count: int = int(active_housing_counts.get(building_id, 0))
		var cap: Dictionary = (buildings[building_id] as Dictionary).get("housing_capacity", {}) as Dictionary
		for group_variant: Variant in cap.keys(): capacity[String(group_variant)] = int(capacity.get(String(group_variant), 0)) + int(cap[group_variant]) * count
	var rows: Array[Dictionary] = []
	for group_id: String in population.keys():
		var pop: int = int(population.get(group_id, 0))
		var cap_value: int = int(capacity.get(group_id, 0))
		rows.append({"group_id": group_id, "name": _population_group_name(group_id), "population": pop, "capacity": cap_value, "free_capacity": cap_value - pop, "status": "OK" if cap_value >= pop else "Overcrowded"})
	return {"rows": rows}

func get_housing_buildings() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id): continue
		var data: Dictionary = buildings[building_id] as Dictionary
		output.append({"id": building_id, "name": String(data.get("name", building_id.capitalize())), "category": String(data.get("category", "housing")), "tier": String(data.get("tier", "")), "description": String(data.get("description", "")), "built": int(estate_buildings.get(building_id, 0)), "active": int(active_housing_counts.get(building_id, 0)), "capacity": (data.get("housing_capacity", {}) as Dictionary).duplicate(true), "maintenance": (data.get("housing_maintenance", {}) as Dictionary).duplicate(true), "build_status": build_status_text(building_id), "can_build": can_build(building_id), "can_destroy": can_destroy(building_id), "destroy_status": destroy_status_text(building_id)})
	return output

func set_active_housing_count(building_id: String, active_count: int) -> void:
	if not _is_housing_building_id(building_id): return
	active_housing_counts[building_id] = clampi(active_count, 0, int(estate_buildings.get(building_id, 0)))
	emit_signal("state_changed")

func get_building_rows_for_screen(screen_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for building_id: String in building_order:
		if not buildings.has(building_id): continue
		var data: Dictionary = buildings[building_id] as Dictionary
		if String(data.get("screen", "")) != screen_id: continue
		var status: Dictionary = _estimate_building_status(building_id)
		output.append({"id": building_id, "name": String(data.get("name", building_id.capitalize())), "category": String(data.get("category", "")), "description": String(data.get("description", "")), "built": int(estate_buildings.get(building_id, 0)), "can_build": can_build(building_id), "build_status": build_status_text(building_id), "can_destroy": can_destroy(building_id), "destroy_status": destroy_status_text(building_id), "operating": int(status.get("operating", 0)), "blocked": int(status.get("blocked", 0)), "status_text": String(status.get("status_text", "")), "inputs": (data.get("inputs", {}) as Dictionary).duplicate(true), "outputs": (data.get("outputs", {}) as Dictionary).duplicate(true), "staff": (data.get("staff", {}) as Dictionary).duplicate(true), "build_cost": (data.get("build_cost", {}) as Dictionary).duplicate(true)})
	return output

func get_labour_assignment_data() -> Dictionary:
	_ensure_labour_assignments()
	return {"buildings": get_building_rows_for_screen("chinampas") + get_building_rows_for_screen("workshops"), "assignments": labour_assignments.duplicate(true), "population": population.duplicate(true)}

func set_labour_assignment(building_id: String, group_id: String, count: int) -> void:
	if not labour_assignments.has(building_id): labour_assignments[building_id] = {}
	var assignment: Dictionary = labour_assignments[building_id] as Dictionary
	assignment[group_id] = max(0, count)
	labour_assignments[building_id] = assignment
	_ensure_labour_assignments()
	emit_signal("state_changed")

func _stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func _add_stock(resource_id: String, amount: float) -> void:
	estate_stockpiles[resource_id] = maxf(0.0, float(estate_stockpiles.get(resource_id, 0.0)) + amount)

func _pressure_label(stored: float, outgoing: float) -> String:
	if outgoing <= 0.0: return "Free"
	var coverage: float = stored / maxf(1.0, outgoing)
	if coverage < 1.0: return "Critical"
	if coverage < 2.0: return "Tight"
	return "Stable"

func _population_group_name(group_id: String) -> String:
	match group_id:
		"macehualtin": return "Macehualtin"
		"tlacotin": return "Tlacotin"
		"tolteca": return "Tolteca"
		"yaotequihuaqueh": return "Warriors"
		"tlamacazqueh": return "Priests"
		"pipiltin": return "Nobles"
		"malli": return "Captives"
	return group_id.capitalize()

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01: return str(int(roundf(value)))
	return str(snappedf(value, 0.01))

func _string_array(source: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in source: output.append(String(value))
	return output
