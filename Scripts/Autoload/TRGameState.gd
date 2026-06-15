# TRGameState.gd
# Godot 4.x
# Suggested autoload name: TRGameState
# Project path: res://Scripts/autoload/TRGameState.gd
extends Node

signal state_changed
signal turn_advanced(report: Array)
signal build_completed(building_id: String)
signal build_failed(building_id: String, reason: String)
signal destroy_completed(building_id: String)
signal destroy_failed(building_id: String, reason: String)

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
	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("Data file did not parse as Dictionary: " + path)
	return {}

func _load_resource_definitions() -> void:
	resources.clear()
	resource_order.clear()
	var data: Dictionary = _load_json_dictionary(RESOURCE_DATA_PATH)
	var rows: Array = data.get("resources", []) as Array
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
	var data: Dictionary = _load_json_dictionary(BUILDING_DATA_PATH)
	var rows: Array = data.get("buildings", []) as Array
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var building_id: String = String(row.get("id", ""))
		if building_id == "":
			continue
		buildings[building_id] = row
		building_order.append(building_id)
	building_order.sort_custom(func(a: String, b: String) -> bool:
		var a_data: Dictionary = buildings[a] as Dictionary
		var b_data: Dictionary = buildings[b] as Dictionary
		return int(a_data.get("priority", 999)) < int(b_data.get("priority", 999))
	)

func _load_market_economy_definitions() -> void:
	market_economy.clear()
	var data: Dictionary = _load_json_dictionary(MARKET_ECONOMY_DATA_PATH)
	if data.is_empty():
		return
	market_economy = data

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
	# New-game start states should not begin with productive buildings idle just
	# because a previous patch or save file left empty labour assignment entries.
	# Default setup staffs production automatically in priority order, with maize
	# protected first, then other production buildings until population runs out.
	_auto_staff_all_productive_buildings()

func _float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key])
	return output

func _int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = int(source[key])
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
		if not estate_stockpiles.has(resource_id):
			estate_stockpiles[resource_id] = 0.0
		if not market_stockpiles.has(resource_id):
			market_stockpiles[resource_id] = 0.0
		if not market_demand.has(resource_id):
			market_demand[resource_id] = 0.0

func _ensure_all_building_keys() -> void:
	for building_id: String in building_order:
		if not estate_buildings.has(building_id):
			estate_buildings[building_id] = 0

func get_current_veintena() -> int:
	return current_veintena

func get_last_report() -> Array[String]:
	var output: Array[String] = []
	for line_variant: Variant in last_report:
		output.append(String(line_variant))
	return output

func get_resource_name(resource_id: String) -> String:
	if resources.has(resource_id):
		var data: Dictionary = resources[resource_id] as Dictionary
		return String(data.get("name", resource_id.capitalize()))
	return resource_id.capitalize()

func get_building_name(building_id: String) -> String:
	if buildings.has(building_id):
		var data: Dictionary = buildings[building_id] as Dictionary
		return String(data.get("name", building_id.capitalize()))
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
		var reserved: float = outgoing
		var free_value: float = maxf(0.0, stored - reserved)
		var good: Dictionary = {
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"stored": stored,
			"incoming": in_value,
			"outgoing": outgoing,
			"reserved": reserved,
			"free": free_value,
			"net": in_value - outgoing,
			"pressure": _pressure_label(stored, outgoing),
			"uses": resource_data.get("uses", []) as Array,
			"reserved_breakdown": _reserve_breakdown(resource_id, upkeep_value, input_value, housing_value)
		}
		output.append(good)
	return output

func get_market_goods() -> Array[Dictionary]:
	var raw_goods: Array = estimate_market_resolution().get("goods", []) as Array
	var output: Array[Dictionary] = []
	for item_variant: Variant in raw_goods:
		var item: Dictionary = item_variant as Dictionary
		output.append(item.duplicate(true))
	return output

func estimate_market_resolution() -> Dictionary:
	var base_goods: Array[Dictionary] = _base_market_goods()
	var resolved_goods: Array[Dictionary] = _apply_market_economy_to_goods(base_goods)
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
	return {
		"goods": resolved_goods,
		"source_of_truth": String(market_economy.get("source_of_truth", "start_state market stock/demand")),
		"total_output": total_output,
		"total_demand": total_demand,
		"net_change": net_value,
		"crisis_goods": crisis_goods,
		"shortage_goods": shortage_goods,
		"surplus_goods": surplus_goods,
		"village_population": (market_economy.get("village_population", {}) as Dictionary).duplicate(true),
		"schema_version": String(market_economy.get("schema_version", ""))
	}

func get_market_economy_summary() -> Dictionary:
	return estimate_market_resolution()

func get_village_economy_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var goods: Array = estimate_market_resolution().get("goods", []) as Array
	for good_variant: Variant in goods:
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

func _base_market_goods() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for resource_id: String in resource_order:
		var resource_data: Dictionary = resources[resource_id] as Dictionary
		var stock_value: float = float(market_stockpiles.get(resource_id, 0.0))
		var demand_value: float = maxf(0.0, float(market_demand.get(resource_id, 0.0)))
		var coverage: float = 0.0
		if demand_value > 0.0:
			coverage = stock_value / demand_value
		var multiplier: float = _scarcity_multiplier(coverage, demand_value)
		var base_value: float = float(resource_data.get("base_value", 1.0))
		var current_value: float = base_value * multiplier
		var good: Dictionary = {
			"id": resource_id,
			"name": String(resource_data.get("name", resource_id.capitalize())),
			"category": String(resource_data.get("category", "raw")),
			"market_stock": stock_value,
			"demand": demand_value,
			"base_value": base_value,
			"current_value": current_value,
			"coverage": coverage,
			"label": _market_label(coverage, demand_value),
			"trend": _market_trend(coverage, demand_value),
			"buy_note": "Buy when estate free stock is low or a build needs this good.",
			"sell_note": "Sell only true surplus after upkeep, input and build reserves are protected.",
			"rival_note": _rival_market_note(resource_id)
		}
		output.append(good)
	return output

func get_buildings_for_screen(screen_id: String, focus_id: String = "overview") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for building_id: String in building_order:
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("screen", "")) != screen_id:
			continue
		if not _building_matches_focus(definition, focus_id):
			continue
		output.append(_building_view_data(building_id))
	return output


func get_housing_summary() -> Dictionary:
	var tiers: Array[Dictionary] = []
	var total_population: int = 0
	var total_active_population: int = 0
	var total_inactive_population: int = 0
	var total_capacity: int = 0
	var total_active_capacity: int = 0
	var total_over: int = 0
	var total_free: int = 0
	var built_capacity_by_group: Dictionary = housing_capacity_by_group({}, false)
	var active_capacity_by_group: Dictionary = housing_capacity_by_group({}, true)
	var maintenance: Dictionary = estimate_housing_maintenance()
	for category_id: String in _housing_category_order():
		var tier: Dictionary = _housing_category_summary(category_id, built_capacity_by_group, active_capacity_by_group)
		tiers.append(tier)
		total_population += int(tier.get("population", 0))
		total_active_population += int(tier.get("active_population", 0))
		total_inactive_population += int(tier.get("inactive_population", 0))
		total_capacity += int(tier.get("capacity", 0))
		total_active_capacity += int(tier.get("active_capacity", 0))
		total_over += int(tier.get("over_capacity", 0))
		total_free += int(tier.get("free_capacity", 0))
	return {
		"tiers": tiers,
		"capacity_by_group": active_capacity_by_group,
		"built_capacity_by_group": built_capacity_by_group,
		"maintenance": maintenance,
		"total_population": total_population,
		"total_active_population": total_active_population,
		"total_inactive_population": total_inactive_population,
		"total_capacity": total_capacity,
		"total_active_capacity": total_active_capacity,
		"total_over_capacity": total_over,
		"total_free_capacity": total_free,
		"status_text": _housing_status_text(total_active_population, total_active_capacity)
	}

func get_housing_rows(focus_id: String = "overview") -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var built_capacity_by_group: Dictionary = housing_capacity_by_group({}, false)
	var active_capacity_by_group: Dictionary = housing_capacity_by_group({}, true)
	if focus_id == "" or focus_id == "overview":
		for category_id: String in _housing_category_order():
			var tier: Dictionary = _housing_category_summary(category_id, built_capacity_by_group, active_capacity_by_group)
			tier["is_summary"] = true
			output.append(tier)
		return output
	if focus_id == "mothball":
		return get_housing_mothball_rows()

	for building_id: String in building_order:
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("screen", "")) != "housing":
			continue
		if String(definition.get("category", "")) != focus_id:
			continue
		output.append(_housing_building_view_data(building_id))
	return output

func housing_capacity_by_group(overrides: Dictionary = {}, active_only: bool = true) -> Dictionary:
	_ensure_active_housing_counts()
	var result: Dictionary = {}
	for group_variant: Variant in base_housing_capacity.keys():
		var group_id: String = String(group_variant)
		result[group_id] = int(base_housing_capacity[group_id])
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		if not result.has(group_id):
			result[group_id] = 0
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			continue
		var built_count: int = int(estate_buildings.get(building_id, 0))
		var count: int = built_count
		if active_only:
			count = int(active_housing_counts.get(building_id, built_count))
		if overrides.has(building_id):
			count = int(overrides[building_id])
		count = clampi(count, 0, built_count)
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
		for group_variant: Variant in capacity.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(capacity[group_variant]) * count
	return result

func active_population_by_group() -> Dictionary:
	var result: Dictionary = {}
	var active_capacity: Dictionary = housing_capacity_by_group({}, true)
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		var total: int = int(population.get(group_id, 0))
		var active_cap: int = int(active_capacity.get(group_id, total))
		result[group_id] = mini(total, max(0, active_cap))
	return result

func inactive_population_by_group() -> Dictionary:
	var result: Dictionary = {}
	var active: Dictionary = active_population_by_group()
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		result[group_id] = max(0, int(population.get(group_id, 0)) - int(active.get(group_id, 0)))
	return result

func _active_population_for_group(group_id: String) -> int:
	return int(active_population_by_group().get(group_id, 0))

func estimate_housing_maintenance() -> Dictionary:
	# Mothballing does not avoid building maintenance. Maintenance is paid for all
	# built housing, active or inactive.
	var result: Dictionary = {}
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant]) * float(count)
	return result

func _housing_building_view_data(building_id: String) -> Dictionary:
	_ensure_active_housing_counts()
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var active_count: int = int(active_housing_counts.get(building_id, count))
	var mothballed_count: int = max(0, count - active_count)
	var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
	var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
	var category_id: String = String(definition.get("category", ""))
	var category_summary: Dictionary = _housing_category_summary(category_id, housing_capacity_by_group({}, false), housing_capacity_by_group({}, true))
	return {
		"id": building_id,
		"name": String(definition.get("name", building_id.capitalize())),
		"screen": "housing",
		"category": category_id,
		"tier": String(definition.get("tier", "")),
		"description": String(definition.get("description", "")),
		"count": count,
		"active_count": active_count,
		"mothballed_count": mothballed_count,
		"operating": active_count,
		"blocked": mothballed_count,
		"build_cost": definition.get("build_cost", {}) as Dictionary,
		"housing_capacity": capacity,
		"housing_maintenance": maintenance,
		"inputs": maintenance,
		"outputs": capacity,
		"capacity_total": _multiply_dictionary(capacity, count),
		"active_capacity_total": _multiply_dictionary(capacity, active_count),
		"maintenance_total": _multiply_dictionary(maintenance, count),
		"capacity_after_build": _multiply_dictionary(capacity, count + 1),
		"maintenance_after_build": _multiply_dictionary(maintenance, count + 1),
		"capacity_after_destroy": _multiply_dictionary(capacity, max(0, count - 1)),
		"maintenance_after_destroy": _multiply_dictionary(maintenance, max(0, count - 1)),
		"category_summary": category_summary,
		"efficiency_text": _housing_efficiency_text(capacity, maintenance),
		"can_build": can_build(building_id),
		"build_status": build_status_text(building_id),
		"can_destroy": can_destroy(building_id),
		"destroy_status": destroy_status_text(building_id),
		"status_text": _housing_building_status_text(building_id)
	}

func _housing_category_summary(category_id: String, built_capacity_by_group: Dictionary, active_capacity_by_group: Dictionary) -> Dictionary:
	var group_ids: Array[String] = _housing_group_ids_for_category(category_id)
	var population_total: int = 0
	var active_population_total: int = 0
	var inactive_population_total: int = 0
	var built_capacity_total: int = 0
	var active_capacity_total: int = 0
	var member_rows: Array[Dictionary] = []
	for group_id: String in group_ids:
		var pop_count: int = int(population.get(group_id, 0))
		var active_pop: int = _active_population_for_group(group_id)
		var inactive_pop: int = max(0, pop_count - active_pop)
		var built_capacity_count: int = int(built_capacity_by_group.get(group_id, 0))
		var active_capacity_count: int = int(active_capacity_by_group.get(group_id, 0))
		population_total += pop_count
		active_population_total += active_pop
		inactive_population_total += inactive_pop
		built_capacity_total += built_capacity_count
		active_capacity_total += active_capacity_count
		member_rows.append({
			"id": group_id,
			"name": _labour_group_name(group_id),
			"population": pop_count,
			"active_population": active_pop,
			"inactive_population": inactive_pop,
			"capacity": built_capacity_count,
			"active_capacity": active_capacity_count,
			"free_capacity": max(0, active_capacity_count - active_pop),
			"over_capacity": max(0, active_pop - active_capacity_count),
			"status": _housing_status_text(active_pop, active_capacity_count)
		})
	var building_options: Array[Dictionary] = []
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("category", "")) != category_id:
			continue
		building_options.append({
			"id": building_id,
			"name": String(definition.get("name", building_id.capitalize())),
			"tier": String(definition.get("tier", "")),
			"count": int(estate_buildings.get(building_id, 0)),
			"active_count": int(active_housing_counts.get(building_id, int(estate_buildings.get(building_id, 0)))),
			"build_cost": definition.get("build_cost", {}) as Dictionary,
			"housing_capacity": definition.get("housing_capacity", {}) as Dictionary,
			"housing_maintenance": definition.get("housing_maintenance", {}) as Dictionary,
			"efficiency_text": _housing_efficiency_text(definition.get("housing_capacity", {}) as Dictionary, definition.get("housing_maintenance", {}) as Dictionary)
		})
	return {
		"id": category_id,
		"name": _housing_category_name(category_id),
		"population": population_total,
		"active_population": active_population_total,
		"inactive_population": inactive_population_total,
		"capacity": built_capacity_total,
		"active_capacity": active_capacity_total,
		"free_capacity": max(0, active_capacity_total - active_population_total),
		"over_capacity": max(0, active_population_total - active_capacity_total),
		"status": _housing_status_text(active_population_total, active_capacity_total),
		"members": member_rows,
		"building_options": building_options,
		"maintenance": _housing_maintenance_for_category(category_id)
	}

func _housing_category_order() -> Array[String]:
	return ["field_labour", "artisans", "tlacotin", "warriors", "priests", "nobles", "captives"]

func _housing_category_name(category_id: String) -> String:
	match category_id:
		"field_labour":
			return "Field Labour"
		"artisans":
			return "Artisans"
		"tlacotin":
			return "Tlacotin"
		"warriors":
			return "Warriors"
		"priests":
			return "Priests"
		"nobles":
			return "Nobles"
		"captives":
			return "Captives"
	return category_id.capitalize()

func _housing_group_ids_for_category(category_id: String) -> Array[String]:
	match category_id:
		"field_labour":
			return ["macehualtin"]
		"artisans":
			return ["tolteca"]
		"tlacotin":
			return ["tlacotin"]
		"warriors":
			return ["yaotequihuaqueh"]
		"priests":
			return ["tlamacazqueh"]
		"nobles":
			return ["pipiltin"]
		"captives":
			return ["malli"]
	return []

func _housing_maintenance_for_category(category_id: String) -> Dictionary:
	var result: Dictionary = {}
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		if String(definition.get("category", "")) != category_id:
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant]) * float(count)
	return result

func _housing_status_text(population_count: int, capacity_count: int) -> String:
	if capacity_count <= 0:
		if population_count <= 0:
			return "No population"
		return "No active capacity"
	if population_count > capacity_count:
		return "Inactive overflow"
	if population_count == capacity_count:
		return "Full"
	var use_ratio: float = float(population_count) / float(capacity_count)
	if use_ratio >= 0.9:
		return "Strained"
	if use_ratio >= 0.7:
		return "Tight"
	return "Comfortable"

func _housing_building_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var active_count: int = int(active_housing_counts.get(building_id, count))
	var capacity: Dictionary = definition.get("housing_capacity", {}) as Dictionary
	var maintenance: Dictionary = definition.get("housing_maintenance", {}) as Dictionary
	var text: String = "Built " + str(count) + "; active " + str(active_count) + "; mothballed " + str(max(0, count - active_count)) + ". Adds " + _dictionary_to_named_string(capacity, "capacity") + " each."
	if not maintenance.is_empty():
		text += " Building upkeep each: " + _dictionary_to_named_string(maintenance, "") + "."
	return text

func _housing_efficiency_text(capacity: Dictionary, maintenance: Dictionary) -> String:
	if maintenance.is_empty():
		return "No building upkeep"
	return "Larger housing tiers have lower upkeep per capacity."

func _would_destroy_overcrowd(building_id: String) -> Dictionary:
	# Destroying removes the building entirely. It is blocked if that would make
	# currently active people inactive. Mothballing is the safe way to deactivate.
	var result: Dictionary = {"blocked": false, "lines": []}
	if not _is_housing_building_id(building_id):
		return result
	var current_count: int = int(estate_buildings.get(building_id, 0))
	if current_count <= 0:
		return result
	var active_count: int = int(active_housing_counts.get(building_id, current_count))
	var active_after: int = mini(active_count, max(0, current_count - 1))
	var overrides: Dictionary = {building_id: active_after}
	var after_capacity: Dictionary = housing_capacity_by_group(overrides, true)
	var lines: Array[String] = []
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		var active_pop: int = _active_population_for_group(group_id)
		var capacity_count: int = int(after_capacity.get(group_id, 0))
		if active_pop > capacity_count:
			lines.append(_labour_group_name(group_id) + " by " + str(active_pop - capacity_count))
	if not lines.is_empty():
		result["blocked"] = true
		result["lines"] = lines
	return result

func _is_housing_building_id(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	return String(definition.get("screen", "")) == "housing" and (definition.has("housing_capacity") or definition.has("housing_maintenance"))

func _ensure_base_housing_capacity() -> void:
	for group_variant: Variant in population.keys():
		var group_id: String = String(group_variant)
		if not base_housing_capacity.has(group_id):
			# Missing base capacity should not silently house the population.
			# Starting housing now comes from start_state estate_buildings +
			# active_housing_counts, so future/new groups default to 0 unless
			# the start data explicitly grants inherited base capacity.
			base_housing_capacity[group_id] = 0

func _ensure_active_housing_counts() -> void:
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			if active_housing_counts.has(building_id):
				active_housing_counts.erase(building_id)
			continue
		var built_count: int = int(estate_buildings.get(building_id, 0))
		if built_count <= 0:
			active_housing_counts[building_id] = 0
			continue
		if not active_housing_counts.has(building_id):
			active_housing_counts[building_id] = built_count
		else:
			active_housing_counts[building_id] = clampi(int(active_housing_counts[building_id]), 0, built_count)

func set_active_housing_count(building_id: String, active_count: int) -> bool:
	if not _is_housing_building_id(building_id):
		return false
	_ensure_active_housing_counts()
	var built_count: int = int(estate_buildings.get(building_id, 0))
	active_housing_counts[building_id] = clampi(active_count, 0, built_count)
	_ensure_labour_assignments()
	emit_signal("state_changed")
	return true

func get_housing_mothball_rows() -> Array[Dictionary]:
	_ensure_active_housing_counts()
	var rows: Array[Dictionary] = []
	for building_id: String in building_order:
		if not _is_housing_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		rows.append(_housing_building_view_data(building_id))
	return rows

func get_housing_mothball_data() -> Dictionary:
	return {"summary": get_housing_summary(), "rows": get_housing_mothball_rows()}

func get_productive_labour_rows() -> Array[Dictionary]:
	_ensure_labour_assignments()
	var required: Dictionary = _productive_labour_required()
	var assigned_by_group: Dictionary = _assigned_labour_by_group()
	var rows: Array[Dictionary] = []
	for group_id: String in _productive_labour_group_ids():
		var total: int = _active_population_for_group(group_id)
		var assigned_value: int = int(assigned_by_group.get(group_id, 0))
		var required_value: int = int(required.get(group_id, assigned_value))
		var free: int = max(0, total - assigned_value)
		var short: int = max(0, assigned_value - total)
		var pressure: String = "Available"
		if total <= 0:
			pressure = "Absent"
		elif assigned_value > total:
			pressure = "Overstretched"
		elif free == 0 and total > 0:
			pressure = "Fully assigned"
		elif assigned_value >= int(total * 0.75):
			pressure = "Tight"
		rows.append({
			"id": "labour_" + group_id,
			"name": _labour_group_name(group_id),
			"screen": "production",
			"category": "labour",
			"is_labour": true,
			"description": _labour_group_description(group_id),
			"count": total,
			"staff": {
				"total_population": total,
				"required_by_staffed_production": required_value,
				"assigned_to_production": assigned_value,
				"free_or_background_labour": free,
				"shortfall": short
			},
			"inputs": {},
			"outputs": {},
			"build_cost": {},
			"can_build": false,
			"build_status": "Use the Labour tab to choose which built productive buildings are staffed.",
			"operating": assigned_value,
			"blocked": short,
			"status_text": pressure + ": assigned " + str(assigned_value) + " / total " + str(total) + "; unassigned " + str(free) + "."
		})
	return rows

func get_labour_assignment_data() -> Dictionary:
	_ensure_labour_assignments()
	var assigned_by_group: Dictionary = _assigned_labour_by_group()
	var required_by_group: Dictionary = _productive_labour_required()
	var groups: Array[Dictionary] = []

	# Player-facing labour buttons are deliberately simpler than the underlying
	# population groups. Macehualtin and Tlacotin both staff the same productive
	# field/chinampa buildings, so the UI presents them as one Field Labour pool
	# while still showing the two population groups underneath. Tolteca remain
	# separate because they operate workshops.
	groups.append(_combined_labour_assignment_group_data(
		"field_labour",
		"Field Labour",
		"Macehualtin and Tlacotin can both staff chinampas and raw production buildings. The slider assigns staffed building copies from their combined pool.",
		_field_labour_group_ids(),
		assigned_by_group,
		required_by_group
	))
	groups.append(_single_labour_assignment_group_data("tolteca", assigned_by_group, required_by_group))

	var building_rows: Array[Dictionary] = []
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var staff_by_group: Dictionary = _production_staff_for_building(building_id)
		if staff_by_group.is_empty():
			continue
		var assignments: Dictionary = _staff_assignments_for_building(building_id)
		var max_by_group: Dictionary = {}
		for group_variant: Variant in staff_by_group.keys():
			var group_id: String = String(group_variant)
			max_by_group[group_id] = _max_staffable_count_for_building_group(building_id, group_id)
		if _building_can_use_field_labour(building_id):
			max_by_group["field_labour"] = _max_staffable_count_for_field_labour(building_id)
		var staffed_count: int = _staffed_count_for_building(building_id)
		var status: Dictionary = _estimate_building_status(building_id)
		var operating: int = int(status.get("operating", 0))
		building_rows.append({
			"id": building_id,
			"name": String(definition.get("name", building_id.capitalize())),
			"count": count,
			"staffed_count": staffed_count,
			"staff_assignments": assignments,
			"allowed_worker_groups": _allowed_worker_groups_for_building(building_id),
			"staff_per_instance_by_group": staff_by_group,
			"max_staffable_by_group": max_by_group,
			"max_staffable": _max_staffable_count_for_building(building_id),
			"staff_population_by_group": _staff_population_by_building(building_id),
			"operating": operating,
			"blocked": int(status.get("blocked", 0)),
			"unstaffed": int(status.get("unstaffed", 0)),
			"status_text": String(status.get("status_text", "")),
			"staff_per_instance": staff_by_group,
			"staff_at_staffed": _assigned_staff_for_building(building_id),
			"inputs_per_instance": definition.get("inputs", {}) as Dictionary,
			"outputs_per_instance": definition.get("outputs", {}) as Dictionary,
			"inputs_at_staffed": _multiply_dictionary(definition.get("inputs", {}) as Dictionary, staffed_count),
			"outputs_at_staffed": _multiply_dictionary(definition.get("outputs", {}) as Dictionary, staffed_count),
			"inputs_at_operating": _multiply_dictionary(definition.get("inputs", {}) as Dictionary, operating),
			"outputs_at_operating": _multiply_dictionary(definition.get("outputs", {}) as Dictionary, operating)
		})

	return {"groups": groups, "buildings": building_rows}

func _single_labour_assignment_group_data(group_id: String, assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = _active_population_for_group(group_id)
	var assigned: int = int(assigned_by_group.get(group_id, 0))
	var required: int = int(required_by_group.get(group_id, assigned))
	return {
		"id": group_id,
		"name": _labour_group_name(group_id),
		"description": _labour_group_description(group_id),
		"total": total,
		"assigned": assigned,
		"required": required,
		"unassigned": max(0, total - assigned),
		"shortfall": max(0, assigned - total),
		"members": [{
			"id": group_id,
			"name": _labour_group_name(group_id),
			"total": total,
			"assigned": assigned,
			"required": required,
			"unassigned": max(0, total - assigned),
			"shortfall": max(0, assigned - total)
		}]
	}

func _combined_labour_assignment_group_data(group_id: String, display_name: String, description: String, member_ids: Array[String], assigned_by_group: Dictionary, required_by_group: Dictionary) -> Dictionary:
	var total: int = 0
	var assigned: int = 0
	var required: int = 0
	var shortfall: int = 0
	var members: Array[Dictionary] = []
	for member_id: String in member_ids:
		var member_total: int = _active_population_for_group(member_id)
		var member_assigned: int = int(assigned_by_group.get(member_id, 0))
		var member_required: int = int(required_by_group.get(member_id, member_assigned))
		var member_shortfall: int = max(0, member_assigned - member_total)
		total += member_total
		assigned += member_assigned
		required += member_required
		shortfall += member_shortfall
		members.append({
			"id": member_id,
			"name": _labour_group_name(member_id),
			"total": member_total,
			"assigned": member_assigned,
			"required": member_required,
			"unassigned": max(0, member_total - member_assigned),
			"shortfall": member_shortfall
		})
	return {
		"id": group_id,
		"name": display_name,
		"description": description,
		"total": total,
		"assigned": assigned,
		"required": required,
		"unassigned": max(0, total - assigned),
		"shortfall": shortfall,
		"members": members
	}

func assign_labour_to_building(building_id: String, group_id: String, amount: int) -> bool:
	# Labour is assigned by staffing built building copies. If a group is supplied,
	# only that worker type changes; otherwise this falls back to the old total-count behaviour.
	if group_id != "":
		return set_staffed_building_count_for_group(building_id, group_id, amount)
	return set_staffed_building_count(building_id, amount)

func set_staffed_building_count(building_id: String, requested_count: int) -> bool:
	# Backwards-compatible total-staffing setter. It fills the building using the
	# first available productive worker types in order.
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var wanted: int = clampi(requested_count, 0, count)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if remaining <= 0:
			break
		var max_for_group: int = _max_staffable_count_for_building_group(building_id, group_id, requested)
		var amount: int = mini(remaining, max_for_group)
		requested[group_id] = amount
		remaining -= amount
	labour_assignments[building_id] = requested
	_ensure_labour_assignments()
	return _staffed_count_for_building(building_id) == wanted

func set_staffed_building_count_for_group(building_id: String, group_id: String, requested_count: int) -> bool:
	if group_id == "field_labour":
		return set_staffed_building_count_for_field_labour(building_id, requested_count)
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	if not allowed.has(group_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var current: Dictionary = _staff_assignments_for_building(building_id)
	var final_count: int = _clamp_staffed_count_for_building_group(building_id, group_id, requested_count)
	current[group_id] = final_count

	# If the selected worker type now claims too many building slots, displace
	# other worker types on this same building. This lets the player select
	# Tlacotin, drag the bar up, and have those copies replace Macehualtin rather
	# than first having to reduce the Macehualtin bar manually.
	var used_slots: int = 0
	for key_variant: Variant in current.keys():
		used_slots += int(current[key_variant])
	if used_slots > count:
		var excess: int = used_slots - count
		for other_group: String in allowed:
			if other_group == group_id:
				continue
			if excess <= 0:
				break
			var other_value: int = int(current.get(other_group, 0))
			var reduction: int = mini(other_value, excess)
			current[other_group] = other_value - reduction
			excess -= reduction

	for key_variant: Variant in current.keys().duplicate():
		if int(current[key_variant]) <= 0:
			current.erase(key_variant)

	labour_assignments[building_id] = current
	_ensure_labour_assignments()
	return int((_staff_assignments_for_building(building_id)).get(group_id, 0)) == requested_count

func set_staffed_building_count_for_field_labour(building_id: String, requested_count: int) -> bool:
	_ensure_labour_assignments()
	if not buildings.has(building_id):
		return false
	if not _is_productive_building_id(building_id):
		return false
	if not _building_can_use_field_labour(building_id):
		return false
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return false
	var max_allowed: int = _max_staffable_count_for_field_labour(building_id)
	var wanted: int = clampi(requested_count, 0, mini(count, max_allowed))
	var current: Dictionary = _staff_assignments_for_building(building_id)

	# Replace any old per-member field assignments with one combined pool value.
	for member_id: String in _field_labour_group_ids():
		current.erase(member_id)
	current.erase("field_labour")
	if wanted > 0:
		current["field_labour"] = wanted

	# Do not overfill building slots if future data allows mixed specialist and
	# field-labour staffing on the same building.
	var used_slots: int = 0
	for key_variant: Variant in current.keys():
		used_slots += int(current[key_variant])
	if used_slots > count:
		current["field_labour"] = max(0, int(current.get("field_labour", 0)) - (used_slots - count))

	for key_variant: Variant in current.keys().duplicate():
		if int(current[key_variant]) <= 0:
			current.erase(key_variant)

	labour_assignments[building_id] = current
	_ensure_labour_assignments()
	return _field_labour_staffed_count_for_building(building_id) == wanted

func _productive_labour_required() -> Dictionary:
	# In the current prototype, "required" means the population committed to the
	# currently staffed production buildings. Storehouse input/output estimates use
	# the same staffed building counts.
	return _assigned_labour_by_group()

func _productive_labour_group_ids() -> Array[String]:
	# Warriors are deliberately excluded here. They belong to Barracks and Flower
	# Wars. Production labour is commoner/bonded labour and skilled artisans.
	return ["macehualtin", "tlacotin", "tolteca"]


func _max_staffable_count_for_field_labour_with_used(building_id: String, used_by_group: Dictionary) -> int:
	if not buildings.has(building_id):
		return 0
	if not _building_can_use_field_labour(building_id):
		return 0
	var count: int = int(estate_buildings.get(building_id, 0))
	var needed_per: int = _field_labour_fallback_staff_required(building_id)
	if needed_per <= 0:
		return 0
	var available_total: int = 0
	for member_id: String in _field_labour_group_ids():
		var total_pop: int = _active_population_for_group(member_id)
		var already: int = int(used_by_group.get(member_id, 0))
		available_total += max(0, total_pop - already)
	return mini(count, int(floor(float(available_total) / float(needed_per))))

func _field_labour_population_split_for_building(building_id: String, staffed_copies: int, used_by_group: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	var needed_per: int = _field_labour_fallback_staff_required(building_id)
	if needed_per <= 0 or staffed_copies <= 0:
		return result
	var remaining_people: int = staffed_copies * needed_per
	for member_id: String in _field_labour_group_ids():
		if remaining_people <= 0:
			break
		var total_pop: int = _active_population_for_group(member_id)
		var already: int = int(used_by_group.get(member_id, 0))
		var available_pop: int = max(0, total_pop - already)
		var use_pop: int = mini(remaining_people, available_pop)
		if use_pop > 0:
			result[member_id] = use_pop
			remaining_people -= use_pop
	return result

func _field_labour_distribution_for_building(target_building_id: String, target_copies: int) -> Dictionary:
	# Work through buildings in a stable order so the displayed Macehualtin/Tlacotin
	# split is deterministic and does not double-count the same population.
	var used_by_group: Dictionary = {}
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var assignments: Dictionary = _staff_assignments_for_building(building_id)
		var copies: int = int(assignments.get("field_labour", 0))
		if building_id == target_building_id:
			copies = target_copies
		if copies <= 0:
			if building_id == target_building_id:
				return {}
			continue
		var split: Dictionary = _field_labour_population_split_for_building(building_id, copies, used_by_group)
		if building_id == target_building_id:
			return split
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			used_by_group[member_id] = int(used_by_group.get(member_id, 0)) + int(split[member_id])
	return {}

func _field_labour_fallback_staff_required(building_id: String) -> int:
	# If old building data only lists one field-labour member, use that same
	# per-building requirement for the combined pool. The shipped buildings.json in
	# this patch lists both Macehualtin and Tlacotin for chinampas, but this keeps
	# older local data from breaking the combined pool.
	for member_id: String in _field_labour_group_ids():
		var amount: int = _staff_required_per_copy_for_group(building_id, member_id)
		if amount > 0:
			return amount
	return 0

func _field_labour_group_ids() -> Array[String]:
	return ["macehualtin", "tlacotin"]

func _production_staff_for_building(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return {}
	var output: Dictionary = {}
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		var required: int = _staff_required_per_copy_for_group(building_id, group_id)
		if required > 0:
			output[group_id] = required
	return output

func _labour_group_name(group_id: String) -> String:
	match group_id:
		"macehualtin":
			return "Macehualtin Labourers"
		"tlacotin":
			return "Tlacotin Labourers"
		"tolteca":
			return "Tolteca Artisans"
		"yaotequihuaqueh":
			return "Yaotequihuaqueh Warriors"
	return group_id.capitalize()

func _labour_group_description(group_id: String) -> String:
	match group_id:
		"macehualtin":
			return "Commoner labourers are the main productive base for chinampas and estate work."
		"tlacotin":
			return "Bonded or enslaved labour can support productive work where the estate has capacity and control."
		"tolteca":
			return "Skilled artisans operate workshops and convert raw goods into processed or luxury goods."
		"yaotequihuaqueh":
			return "Warriors mostly belong to Barracks and Flower Wars, but some production chains such as weapon yards can require martial staff."
	return "Productive labour group."

func _building_matches_focus(definition: Dictionary, focus_id: String) -> bool:
	if focus_id == "" or focus_id == "overview" or focus_id == "build":
		return true
	var category: String = String(definition.get("category", ""))
	if focus_id == category:
		return true
	if focus_id == "maize" and String(definition.get("id", "")) == "maize_chinampa":
		return true
	if focus_id == "cacao" and String(definition.get("id", "")) == "cacao_garden":
		return true
	if focus_id == "cotton" and String(definition.get("id", "")) == "cotton_chinampa":
		return true
	return false

func _building_view_data(building_id: String) -> Dictionary:
	var definition: Dictionary = buildings[building_id] as Dictionary
	var count: int = int(estate_buildings.get(building_id, 0))
	var status: Dictionary = _estimate_building_status(building_id)
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if _is_productive_building_id(building_id):
		staff = _production_staff_for_building(building_id)
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
	var build_time: int = int(definition.get("build_time_veintenas", definition.get("build_time", 0)))
	return {
		"id": building_id,
		"name": String(definition.get("name", building_id.capitalize())),
		"screen": String(definition.get("screen", "")),
		"category": String(definition.get("category", "")),
		"description": String(definition.get("description", "")),
		"count": count,
		"staff": staff,
		"inputs": inputs,
		"outputs": outputs,
		"staff_total": _multiply_dictionary(staff, count),
		"staff_assigned": _assigned_staff_for_building(building_id),
		"inputs_total": _multiply_dictionary(inputs, int(status.get("operating", 0))),
		"outputs_total": _multiply_dictionary(outputs, int(status.get("operating", 0))),
		"staff_after_build": _multiply_dictionary(staff, count + 1),
		"inputs_after_build": _multiply_dictionary(inputs, count + 1),
		"outputs_after_build": _multiply_dictionary(outputs, count + 1),
		"staff_after_destroy": _multiply_dictionary(staff, max(0, count - 1)),
		"inputs_after_destroy": _multiply_dictionary(inputs, max(0, count - 1)),
		"outputs_after_destroy": _multiply_dictionary(outputs, max(0, count - 1)),
		"build_cost": definition.get("build_cost", {}) as Dictionary,
		"build_time_veintenas": build_time,
		"can_build": can_build(building_id),
		"build_status": build_status_text(building_id),
		"can_destroy": can_destroy(building_id),
		"destroy_status": destroy_status_text(building_id),
		"operating": int(status.get("operating", 0)),
		"blocked": int(status.get("blocked", 0)),
		"status_text": String(status.get("status_text", ""))
	}

func reserved_resources_for_current_turn() -> Dictionary:
	# Goods spoken for before construction spending: population upkeep, housing
	# maintenance, and current production input demand. This matches the Storehouse
	# Reserved / Free to spend logic.
	var reserved: Dictionary = {}
	var upkeep: Dictionary = estimate_population_upkeep()
	var maintenance: Dictionary = estimate_housing_maintenance()
	var inputs: Dictionary = estimate_building_inputs()
	for resource_variant: Variant in upkeep.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(upkeep[resource_id])
	for resource_variant: Variant in maintenance.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(maintenance[resource_id])
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		reserved[resource_id] = float(reserved.get(resource_id, 0.0)) + float(inputs[resource_id])
	return reserved

func free_stock_after_reserves(resource_id: String) -> float:
	var reserved: Dictionary = reserved_resources_for_current_turn()
	return maxf(0.0, _stock(resource_id) - float(reserved.get(resource_id, 0.0)))

func can_build(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn()
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var free_after_reserves: float = maxf(0.0, _stock(resource_id) - float(reserved.get(resource_id, 0.0)))
		if free_after_reserves < float(cost[resource_id]):
			return false
	return true

func build_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	var reserved: Dictionary = reserved_resources_for_current_turn()
	var missing: Array[String] = []
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_id])
		var stored: float = _stock(resource_id)
		var reserved_amount: float = float(reserved.get(resource_id, 0.0))
		var free_after_reserves: float = maxf(0.0, stored - reserved_amount)
		if free_after_reserves < needed:
			var shortfall: float = needed - free_after_reserves
			var part: String = get_resource_name(resource_id) + " " + _format_amount(shortfall)
			if reserved_amount > 0.0:
				part += " after reserves"
			missing.append(part)
	if missing.is_empty():
		return "Buildable now using free stock after reserves."
	return "Missing: " + ", ".join(missing)

func build_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		emit_signal("build_failed", building_id, "Unknown building.")
		return false
	if not can_build(building_id):
		var reason: String = build_status_text(building_id)
		last_report.append(get_building_name(building_id) + " not built. " + reason)
		emit_signal("build_failed", building_id, reason)
		emit_signal("state_changed")
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var cost: Dictionary = definition.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_id]))
	var previous_count: int = int(estate_buildings.get(building_id, 0))
	var previous_staffed: int = _staffed_count_for_building(building_id)
	estate_buildings[building_id] = previous_count + 1
	if _is_housing_building_id(building_id):
		_ensure_active_housing_counts()
		active_housing_counts[building_id] = int(active_housing_counts.get(building_id, previous_count)) + 1
		active_housing_counts[building_id] = clampi(int(active_housing_counts[building_id]), 0, int(estate_buildings.get(building_id, 0)))
	# If this building type was previously fully staffed, try to staff the new
	# copy automatically. If the player had deliberately left copies unstaffed,
	# keep that manual choice instead of silently overriding it.
	if _is_productive_building_id(building_id) and previous_staffed >= previous_count:
		_auto_staff_single_building_to_max(building_id)
	else:
		_ensure_labour_assignments()
	var message: String = "Built " + get_building_name(building_id) + "."
	last_report.append(message)
	emit_signal("build_completed", building_id)
	emit_signal("state_changed")
	return true

func can_destroy(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return false
	if _is_housing_building_id(building_id):
		var overcrowd: Dictionary = _would_destroy_overcrowd(building_id)
		return not bool(overcrowd.get("blocked", false))
	return true

func destroy_status_text(building_id: String) -> String:
	if not buildings.has(building_id):
		return "Unknown building."
	if int(estate_buildings.get(building_id, 0)) <= 0:
		return "None built."
	if _is_housing_building_id(building_id):
		var overcrowd: Dictionary = _would_destroy_overcrowd(building_id)
		if bool(overcrowd.get("blocked", false)):
			var lines: Array = overcrowd.get("lines", []) as Array
			return "Cannot destroy: would overcrowd " + ", ".join(lines) + "."
		return "Can destroy one. No refund in this prototype."
	if can_destroy(building_id):
		return "Can destroy one. No refund in this prototype."
	return "None built."

func destroy_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		emit_signal("destroy_failed", building_id, "Unknown building.")
		return false
	if not can_destroy(building_id):
		var reason: String = destroy_status_text(building_id)
		last_report.append(get_building_name(building_id) + " not destroyed. " + reason)
		emit_signal("destroy_failed", building_id, reason)
		emit_signal("state_changed")
		return false
	var before_destroy_count: int = int(estate_buildings.get(building_id, 0))
	estate_buildings[building_id] = max(0, before_destroy_count - 1)
	if _is_housing_building_id(building_id):
		_ensure_active_housing_counts()
		active_housing_counts[building_id] = mini(int(active_housing_counts.get(building_id, 0)), int(estate_buildings.get(building_id, 0)))
	_ensure_labour_assignments()
	last_report.append("Destroyed one " + get_building_name(building_id) + ". No refund given.")
	emit_signal("destroy_completed", building_id)
	emit_signal("state_changed")
	return true

func advance_veintena() -> void:
	if not initialized:
		new_game()
	last_report.clear()
	last_report.append("Veintena " + str(current_veintena) + " resolves.")
	_pay_population_upkeep()
	_pay_housing_maintenance()
	_operate_buildings()
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
		last_report.append("Nemontemi reckoning placeholder: the next Ritual Year begins.")
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
			var amount: float = float(rates[resource_id]) * float(count) / 5.0
			result[resource_id] = float(result.get(resource_id, 0.0)) + amount
	return result

func estimate_building_inputs() -> Dictionary:
	# Single source of truth for Storehouse / Production / Labour previews.
	# This now uses the same dry-run resolver as the rest of the UI, so input
	# demand reflects staffed buildings, population upkeep paid first, and shared
	# input goods being consumed by earlier buildings in building_order.
	var resolution: Dictionary = estimate_production_resolution()
	return (resolution.get("inputs", {}) as Dictionary).duplicate(true)

func estimate_building_outputs() -> Dictionary:
	# Single source of truth for Storehouse / Production / Labour previews.
	# This now uses the same dry-run resolver as the rest of the UI, so output
	# only comes from buildings that are both staffed and supplied in the shared
	# temporary stockpile.
	var resolution: Dictionary = estimate_production_resolution()
	return (resolution.get("outputs", {}) as Dictionary).duplicate(true)

func estimate_production_resolution() -> Dictionary:
	# Authoritative production preview. This mirrors Advance Veintena order:
	# 1. copy current stockpiles
	# 2. pay population upkeep and housing building upkeep from the copied stockpile
	# 3. process staffed production buildings in building_order
	# 4. consume inputs from the copied stockpile
	# 5. add outputs to the copied stockpile
	# 6. record exactly what would operate, block, or sit unstaffed
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
		var needed: float = float(upkeep_needed[resource_variant])
		var available: float = float(temp_stockpile.get(resource_id, 0.0))
		var paid: float = minf(available, needed)
		temp_stockpile[resource_id] = available - paid
		upkeep_paid[resource_id] = paid
		if paid < needed:
			upkeep_shortfalls[resource_id] = needed - paid

	for resource_variant: Variant in maintenance_needed.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(maintenance_needed[resource_variant])
		var available: float = float(temp_stockpile.get(resource_id, 0.0))
		var paid: float = minf(available, needed)
		temp_stockpile[resource_id] = available - paid
		maintenance_paid[resource_id] = paid
		if paid < needed:
			maintenance_shortfalls[resource_id] = needed - paid

	var total_inputs: Dictionary = {}
	var total_outputs: Dictionary = {}
	var building_statuses: Dictionary = {}
	var report_lines: Array[String] = []

	for building_id: String in building_order:
		if not buildings.has(building_id):
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			building_statuses[building_id] = {
				"operating": 0,
				"blocked": 0,
				"staffed_count": 0,
				"unstaffed": 0,
				"input_blocked": 0,
				"status_text": "Not built.",
				"input_shortages": []
			}
			continue

		var staffed_count: int = count
		if _is_productive_building_id(building_id):
			staffed_count = _staffed_count_for_building(building_id)
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
				if not input_shortages.has(reason):
					input_shortages.append(reason)

		var unstaffed: int = max(0, count - staffed_count)
		var blocked: int = input_blocked + unstaffed
		var status_text: String = "Staffed " + str(staffed_count) + " / " + str(count) + "; operating " + str(operated) + " / " + str(staffed_count) + " staffed"
		if unstaffed > 0:
			status_text += "; unstaffed " + str(unstaffed)
		if input_blocked > 0:
			status_text += "; input blocked " + str(input_blocked)
		if not input_shortages.is_empty():
			status_text += "; " + "; ".join(input_shortages)

		building_statuses[building_id] = {
			"operating": operated,
			"blocked": blocked,
			"staffed_count": staffed_count,
			"unstaffed": unstaffed,
			"input_blocked": input_blocked,
			"status_text": status_text,
			"input_shortages": input_shortages.duplicate()
		}

		if operated > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would operate x" + str(operated) + ".")
		if input_blocked > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would be input-blocked x" + str(input_blocked) + ".")
		if _is_productive_building_id(building_id) and unstaffed > 0:
			report_lines.append(String(definition.get("name", building_id)) + " would be unstaffed x" + str(unstaffed) + ".")

	return {
		"inputs": total_inputs,
		"outputs": total_outputs,
		"building_statuses": building_statuses,
		"stockpile_after_upkeep_and_production": temp_stockpile,
		"upkeep_needed": upkeep_needed,
		"upkeep_paid": upkeep_paid,
		"upkeep_shortfalls": upkeep_shortfalls,
		"housing_maintenance_needed": maintenance_needed,
		"housing_maintenance_paid": maintenance_paid,
		"housing_maintenance_shortfalls": maintenance_shortfalls,
		"reports": report_lines
	}

func _copy_stockpile_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _can_operate_instance_with_stockpile(definition: Dictionary, temp_stockpile: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(inputs[resource_variant])
		if float(temp_stockpile.get(resource_id, 0.0)) < needed:
			return "not enough " + get_resource_name(resource_id) + " input"
	return ""

func _consume_inputs_from_stockpile(inputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - float(inputs[resource_variant])

func _add_outputs_to_stockpile(outputs: Dictionary, temp_stockpile: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) + float(outputs[resource_variant])

func _add_dictionary_amounts(target: Dictionary, amounts: Dictionary) -> void:
	for resource_variant: Variant in amounts.keys():
		var resource_id: String = String(resource_variant)
		target[resource_id] = float(target.get(resource_id, 0.0)) + float(amounts[resource_variant])

func _pay_population_upkeep() -> void:
	var upkeep: Dictionary = estimate_population_upkeep()
	for resource_variant: Variant in upkeep.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(upkeep[resource_id])
		var available: float = _stock(resource_id)
		var paid: float = minf(available, needed)
		_add_stock(resource_id, -paid)
		if paid >= needed:
			last_report.append("Paid population upkeep: " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")
		else:
			last_report.append("Shortage: paid only " + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + " for population upkeep.")

func _pay_housing_maintenance() -> void:
	var maintenance: Dictionary = estimate_housing_maintenance()
	for resource_variant: Variant in maintenance.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(maintenance[resource_id])
		var available: float = _stock(resource_id)
		var paid: float = minf(available, needed)
		_add_stock(resource_id, -paid)
		if paid >= needed:
			last_report.append("Paid housing building upkeep: " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")
		else:
			last_report.append("Housing building upkeep shortage: paid only " + _format_amount(paid) + " / " + _format_amount(needed) + " " + get_resource_name(resource_id) + ".")

func _operate_buildings() -> void:
	_ensure_labour_assignments()
	for building_id: String in building_order:
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var definition: Dictionary = buildings[building_id] as Dictionary
		var target_count: int = count
		if _is_productive_building_id(building_id):
			target_count = _staffed_count_for_building(building_id)
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
		if operated > 0:
			last_report.append(String(definition.get("name", building_id)) + " operated x" + str(operated) + ".")
		if _is_productive_building_id(building_id) and target_count < count:
			last_report.append(String(definition.get("name", building_id)) + " unstaffed x" + str(count - target_count) + ".")

func _can_operate_instance(definition: Dictionary) -> String:
	var inputs: Dictionary = definition.get("inputs", {}) as Dictionary
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		if _stock(resource_id) < float(inputs[resource_id]):
			return "not enough " + get_resource_name(resource_id) + " input"
	return ""

func _reserve_staff(staff: Dictionary, available_staff: Dictionary) -> void:
	# Legacy helper retained for older patches. Production staffing is now handled
	# by staffed building counts rather than per-population sliders.
	for group_variant: Variant in staff.keys():
		var group_id: String = String(group_variant)
		available_staff[group_id] = int(available_staff.get(group_id, 0)) - int(staff[group_id])

func _consume_inputs(inputs: Dictionary) -> void:
	for resource_variant: Variant in inputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(inputs[resource_id]))

func _add_outputs(outputs: Dictionary) -> void:
	for resource_variant: Variant in outputs.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, float(outputs[resource_id]))

func _estimate_building_status(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return {"operating": 0, "blocked": 0, "staffed_count": 0, "unstaffed": 0, "input_blocked": 0, "status_text": "Unknown building.", "input_shortages": []}
	var resolution: Dictionary = estimate_production_resolution()
	var statuses: Dictionary = resolution.get("building_statuses", {}) as Dictionary
	if statuses.has(building_id):
		return (statuses[building_id] as Dictionary).duplicate(true)
	return {"operating": 0, "blocked": 0, "staffed_count": 0, "unstaffed": 0, "input_blocked": 0, "status_text": "Not built.", "input_shortages": []}

func _estimated_operating_count_for_building(building_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	return int(_estimate_building_status(building_id).get("operating", 0))

func _is_productive_building_id(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	return screen_id == "chinampas" or screen_id == "workshops"

func _auto_staff_all_productive_buildings() -> void:
	# Force a clean automatic staffing pass. Used for new-game setup so built
	# production starts staffed when the estate has the people for it.
	labour_assignments.clear()
	var running_by_group: Dictionary = {}
	for building_id: String in _production_auto_staff_order():
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			continue
		var assignment: Dictionary = _default_assignment_for_building(building_id, count, running_by_group)
		labour_assignments[building_id] = assignment
	_ensure_labour_assignments()

func _auto_staff_single_building_to_max(building_id: String) -> void:
	# Try to staff as many copies of one building as possible without rewriting
	# all other manual assignments. This is mainly used after constructing one
	# extra productive building.
	if not _is_productive_building_id(building_id):
		return
	var count: int = int(estate_buildings.get(building_id, 0))
	if count <= 0:
		return
	var running_by_group: Dictionary = _assigned_labour_by_group_excluding(building_id)
	var assignment: Dictionary = _default_assignment_for_building(building_id, count, running_by_group)
	labour_assignments[building_id] = assignment
	_ensure_labour_assignments()

func _production_auto_staff_order() -> Array[String]:
	# Maize is the protected food base and should be staffed before every other
	# productive building. After maize, use normal building priority/order so the
	# fewest possible lower-priority buildings are left idle when labour is short.
	var maize_ids: Array[String] = []
	var other_ids: Array[String] = []
	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		if _is_maize_production_building(building_id):
			maize_ids.append(building_id)
		else:
			other_ids.append(building_id)
	maize_ids.append_array(other_ids)
	return maize_ids

func _is_maize_production_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	if building_id.find("maize") >= 0:
		return true
	var definition: Dictionary = buildings[building_id] as Dictionary
	var outputs: Dictionary = definition.get("outputs", {}) as Dictionary
	return outputs.has("maize")

func _ensure_labour_assignments() -> void:
	# Labour assignment is stored as: building_id -> {worker_group_id: staffed_building_count}.
	# For the combined Field Labour UI, raw/chinampa buildings store
	# {"field_labour": count}. That count means "this many building copies are
	# staffed from the combined Macehualtin + Tlacotin pool". The population split
	# is calculated separately so the two populations can combine to staff one
	# building copy.
	var running_by_group: Dictionary = {}

	for building_key_variant: Variant in labour_assignments.keys().duplicate():
		var existing_id: String = String(building_key_variant)
		if not _is_productive_building_id(existing_id) or int(estate_buildings.get(existing_id, 0)) <= 0:
			labour_assignments.erase(existing_id)

	for building_id: String in building_order:
		if not _is_productive_building_id(building_id):
			continue
		var count: int = int(estate_buildings.get(building_id, 0))
		if count <= 0:
			labour_assignments.erase(building_id)
			continue
		var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
		if allowed.is_empty() and not _building_can_use_field_labour(building_id):
			labour_assignments.erase(building_id)
			continue

		var requested: Dictionary = {}
		if labour_assignments.has(building_id):
			requested = _coerce_staff_assignments_for_building(building_id, labour_assignments[building_id])
		else:
			requested = _default_assignment_for_building(building_id, count, running_by_group)

		var final_assignments: Dictionary = {}
		var remaining_slots: int = count

		# Combined Field Labour is handled before the individual worker loop because
		# one staffed building can be supplied by a mixture of Macehualtin and Tlacotin.
		if _building_can_use_field_labour(building_id):
			var field_wanted: int = clampi(int(requested.get("field_labour", 0)), 0, remaining_slots)
			if field_wanted > 0:
				var field_possible: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
				var field_count: int = mini(field_wanted, field_possible)
				if field_count > 0:
					final_assignments["field_labour"] = field_count
					var split: Dictionary = _field_labour_population_split_for_building(building_id, field_count, running_by_group)
					for member_variant: Variant in split.keys():
						var member_id: String = String(member_variant)
						running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
					remaining_slots -= field_count

		# Specialist / non-field groups are still handled individually.
		for group_id: String in allowed:
			if group_id == "macehualtin" or group_id == "tlacotin":
				# These are represented by the combined field_labour entry for chinampas.
				if _building_can_use_field_labour(building_id):
					continue
			if remaining_slots <= 0:
				break
			var wanted: int = clampi(int(requested.get(group_id, 0)), 0, remaining_slots)
			var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
			var total: int = _active_population_for_group(group_id)
			var already: int = int(running_by_group.get(group_id, 0))
			var available_pop: int = max(0, total - already)
			var max_by_pop: int = 0
			if needed_per > 0:
				max_by_pop = int(floor(float(available_pop) / float(needed_per)))
			var final_count: int = mini(wanted, max_by_pop)
			if final_count > 0:
				final_assignments[group_id] = final_count
				running_by_group[group_id] = already + final_count * needed_per
				remaining_slots -= final_count

		labour_assignments[building_id] = final_assignments

func _default_assignment_for_building(building_id: String, count: int, running_by_group: Dictionary) -> Dictionary:
	var requested: Dictionary = {}
	var remaining: int = count
	if _building_can_use_field_labour(building_id):
		var possible_field: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			requested["field_labour"] = use_field
			var split: Dictionary = _field_labour_population_split_for_building(building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			remaining -= use_field
		if remaining <= 0:
			return requested

	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if group_id == "macehualtin" or group_id == "tlacotin":
			if _building_can_use_field_labour(building_id):
				continue
		if remaining <= 0:
			break
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		var total: int = _active_population_for_group(group_id)
		var already: int = int(running_by_group.get(group_id, 0))
		var available_pop: int = max(0, total - already)
		var possible: int = 0
		if needed_per > 0:
			possible = int(floor(float(available_pop) / float(needed_per)))
		var use_count: int = mini(remaining, possible)
		if use_count > 0:
			requested[group_id] = use_count
			running_by_group[group_id] = already + use_count * needed_per
			remaining -= use_count
	return requested

func _allowed_worker_groups_for_building(building_id: String) -> Array[String]:
	var output: Array[String] = []
	if not buildings.has(building_id):
		return output
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	var screen_id: String = String(definition.get("screen", ""))
	# Chinampa/raw field labour can be staffed by free Macehualtin or Tlacotin.
	# Workshops remain Tolteca/artisan-led unless the building data explicitly says otherwise.
	if screen_id == "chinampas" and staff.has("macehualtin"):
		output.append("macehualtin")
		output.append("tlacotin")
	else:
		for group_variant: Variant in staff.keys():
			var group_id: String = String(group_variant)
			if _productive_labour_group_ids().has(group_id):
				output.append(group_id)
	return output

func _staff_required_per_copy_for_group(building_id: String, group_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	if group_id == "field_labour":
		return _field_labour_fallback_staff_required(building_id)
	var definition: Dictionary = buildings[building_id] as Dictionary
	var staff: Dictionary = definition.get("staff", {}) as Dictionary
	if staff.has(group_id):
		return int(staff[group_id])
	# Tlacotin can substitute for Macehualtin on chinampa/raw production buildings.
	if group_id == "tlacotin" and String(definition.get("screen", "")) == "chinampas" and staff.has("macehualtin"):
		return int(staff["macehualtin"])
	return 0

func _coerce_staff_assignments_for_building(building_id: String, value: Variant) -> Dictionary:
	var output: Dictionary = {}
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	if allowed.is_empty() and not _building_can_use_field_labour(building_id):
		return output
	var count: int = int(estate_buildings.get(building_id, 0))
	if value is int or value is float:
		var amount: int = clampi(int(value), 0, count)
		if amount <= 0:
			return output
		if _building_can_use_field_labour(building_id):
			output["field_labour"] = amount
		elif not allowed.is_empty():
			output[allowed[0]] = amount
		return output
	if not (value is Dictionary):
		return output
	var assignment: Dictionary = value as Dictionary

	if _building_can_use_field_labour(building_id):
		var field_amount: int = int(assignment.get("field_labour", 0))
		# Older patches stored Macehualtin/Tlacotin copy counts separately. Merge
		# them into the combined Field Labour pool so the two populations can staff
		# one building together.
		for member_id: String in _field_labour_group_ids():
			field_amount += int(assignment.get(member_id, 0))
		if field_amount > 0:
			output["field_labour"] = clampi(field_amount, 0, count)

	for group_id: String in allowed:
		if _field_labour_group_ids().has(group_id) and _building_can_use_field_labour(building_id):
			continue
		var raw_amount: int = int(assignment.get(group_id, 0))
		if raw_amount <= 0:
			continue
		var needed_per: int = max(1, _staff_required_per_copy_for_group(building_id, group_id))
		if raw_amount > count:
			output[group_id] = int(floor(float(raw_amount) / float(needed_per)))
		else:
			output[group_id] = raw_amount
	return output

func _staff_assignments_for_building(building_id: String) -> Dictionary:
	if not labour_assignments.has(building_id):
		return {}
	return _coerce_staff_assignments_for_building(building_id, labour_assignments[building_id])

func _assigned_staff_for_building(building_id: String) -> Dictionary:
	_ensure_labour_assignments()
	return _staff_population_by_building(building_id)

func _staff_population_by_building(building_id: String) -> Dictionary:
	var result: Dictionary = {}
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	if assignments.has("field_labour"):
		var copies: int = int(assignments.get("field_labour", 0))
		var split: Dictionary = _field_labour_distribution_for_building(building_id, copies)
		for member_variant: Variant in split.keys():
			var member_id: String = String(member_variant)
			result[member_id] = int(result.get(member_id, 0)) + int(split[member_id])
	for group_variant: Variant in assignments.keys():
		var group_id: String = String(group_variant)
		if group_id == "field_labour":
			continue
		var copies: int = int(assignments[group_id])
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		if copies > 0 and needed_per > 0:
			result[group_id] = int(result.get(group_id, 0)) + copies * needed_per
	return result

func _staffed_count_for_building(building_id: String) -> int:
	var total: int = 0
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func _staffed_count_for_group(building_id: String, group_id: String) -> int:
	if group_id == "field_labour":
		return _field_labour_staffed_count_for_building(building_id)
	return int(_staff_assignments_for_building(building_id).get(group_id, 0))

func _coerce_staffed_count_from_assignment(building_id: String, value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var assignments: Dictionary = _coerce_staff_assignments_for_building(building_id, value)
	var total: int = 0
	for group_variant: Variant in assignments.keys():
		total += int(assignments[group_variant])
	return total

func _clamp_staffed_count_for_building(building_id: String, requested_count: int) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	if _building_can_use_field_labour(building_id):
		return mini(wanted, _max_staffable_count_for_field_labour(building_id))
	var assigned_elsewhere: Dictionary = _assigned_labour_by_group_excluding(building_id)
	var requested: Dictionary = {}
	var remaining: int = wanted
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if remaining <= 0:
			break
		var max_for_group: int = _max_staffable_count_for_building_group(building_id, group_id, requested, assigned_elsewhere)
		var use_count: int = mini(remaining, max_for_group)
		requested[group_id] = use_count
		remaining -= use_count
	var total: int = 0
	for group_variant: Variant in requested.keys():
		total += int(requested[group_variant])
	return total

func _clamp_staffed_count_for_building_group(building_id: String, group_id: String, requested_count: int) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var wanted: int = clampi(requested_count, 0, count)
	var max_allowed: int = _max_staffable_count_for_building_group(building_id, group_id)
	return mini(wanted, max_allowed)

func _building_can_use_field_labour(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	var definition: Dictionary = buildings[building_id] as Dictionary
	if String(definition.get("screen", "")) == "chinampas":
		return true
	var allowed: Array[String] = _allowed_worker_groups_for_building(building_id)
	for member_id: String in _field_labour_group_ids():
		if allowed.has(member_id):
			return true
	return false

func _field_labour_staffed_count_for_building(building_id: String) -> int:
	var assignments: Dictionary = _staff_assignments_for_building(building_id)
	var total: int = int(assignments.get("field_labour", 0))
	# Keep older per-member assignments readable if they still exist.
	for member_id: String in _field_labour_group_ids():
		total += int(assignments.get(member_id, 0))
	return clampi(total, 0, int(estate_buildings.get(building_id, 0)))

func _max_staffable_count_for_field_labour(building_id: String) -> int:
	return _max_staffable_count_for_field_labour_with_used(building_id, _assigned_labour_by_group_excluding(building_id))

func _max_staffable_count_for_building_group(building_id: String, group_id: String, override_for_building: Dictionary = {}, precomputed_elsewhere: Dictionary = {}) -> int:
	if group_id == "field_labour":
		var elsewhere: Dictionary = precomputed_elsewhere
		if elsewhere.is_empty():
			elsewhere = _assigned_labour_by_group_excluding(building_id)
		return _max_staffable_count_for_field_labour_with_used(building_id, elsewhere)
	if not buildings.has(building_id):
		return 0
	if not _allowed_worker_groups_for_building(building_id).has(group_id):
		return 0
	var count: int = int(estate_buildings.get(building_id, 0))
	var assigned_elsewhere: Dictionary = precomputed_elsewhere
	if assigned_elsewhere.is_empty():
		assigned_elsewhere = _assigned_labour_by_group_excluding(building_id)
	var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
	if needed_per <= 0:
		return 0
	var total_pop: int = _active_population_for_group(group_id)
	var already_elsewhere: int = int(assigned_elsewhere.get(group_id, 0))
	var available_pop: int = max(0, total_pop - already_elsewhere)
	var max_by_pop: int = int(floor(float(available_pop) / float(needed_per)))
	return mini(count, max_by_pop)

func _clamp_staffed_count_with_running(building_id: String, requested_count: int, running_by_group: Dictionary) -> int:
	var count: int = int(estate_buildings.get(building_id, 0))
	var remaining: int = clampi(requested_count, 0, count)
	var staffed: int = 0
	if _building_can_use_field_labour(building_id):
		var possible_field: int = _max_staffable_count_for_field_labour_with_used(building_id, running_by_group)
		var use_field: int = mini(remaining, possible_field)
		if use_field > 0:
			var split: Dictionary = _field_labour_population_split_for_building(building_id, use_field, running_by_group)
			for member_variant: Variant in split.keys():
				var member_id: String = String(member_variant)
				running_by_group[member_id] = int(running_by_group.get(member_id, 0)) + int(split[member_id])
			staffed += use_field
			remaining -= use_field
	if remaining <= 0:
		return staffed
	for group_id: String in _allowed_worker_groups_for_building(building_id):
		if _field_labour_group_ids().has(group_id) and _building_can_use_field_labour(building_id):
			continue
		if remaining <= 0:
			break
		var needed_per: int = _staff_required_per_copy_for_group(building_id, group_id)
		var total: int = _active_population_for_group(group_id)
		var already: int = int(running_by_group.get(group_id, 0))
		var available: int = max(0, total - already)
		var possible: int = 0
		if needed_per > 0:
			possible = int(floor(float(available) / float(needed_per)))
		var use_count: int = mini(remaining, possible)
		staffed += use_count
		running_by_group[group_id] = already + use_count * needed_per
		remaining -= use_count
	return staffed

func _max_staffable_count_for_building(building_id: String) -> int:
	if not buildings.has(building_id):
		return 0
	return _clamp_staffed_count_for_building(building_id, int(estate_buildings.get(building_id, 0)))

func _assigned_labour_by_group_excluding(excluded_building_id: String) -> Dictionary:
	var result: Dictionary = {}
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		if building_id == excluded_building_id:
			continue
		var assigned: Dictionary = _staff_population_by_building(building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result

func _assigned_labour_by_group() -> Dictionary:
	var result: Dictionary = {}
	for building_variant: Variant in labour_assignments.keys():
		var building_id: String = String(building_variant)
		var assigned: Dictionary = _staff_population_by_building(building_id)
		for group_variant: Variant in assigned.keys():
			var group_id: String = String(group_variant)
			result[group_id] = int(result.get(group_id, 0)) + int(assigned[group_id])
	return result


func _multiply_dictionary(values: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		result[key] = float(values[key_variant]) * float(multiplier)
	return result

func add_looted_goods_bundle(loot: Dictionary) -> void:
	# Flower Wars should not create a separate "Looted Goods" stockpile.
	# Loot is immediately assigned into actual goods such as maize, wood, cacao,
	# obsidian, cloth, tools, weapons, ritual goods, or fine textiles.
	var gained_parts: Array[String] = []
	for resource_variant: Variant in loot.keys():
		var resource_id: String = String(resource_variant)
		if not resource_order.has(resource_id):
			push_warning("Ignoring looted item that is not a real good: " + resource_id)
			continue
		var amount: float = maxf(0.0, float(loot[resource_id]))
		if amount <= 0.0:
			continue
		_add_stock(resource_id, amount)
		gained_parts.append(_format_amount(amount) + " " + get_resource_name(resource_id))
	if not gained_parts.is_empty():
		last_report.append("Loot assigned into goods: " + ", ".join(gained_parts) + ".")
	emit_signal("state_changed")

func _dictionary_to_named_string(values: Dictionary, suffix: String = "") -> String:
	var parts: Array[String] = []
	for key_variant: Variant in values.keys():
		var key: String = String(key_variant)
		var label: String = key
		if resources.has(key):
			label = get_resource_name(key)
		elif population.has(key) or base_housing_capacity.has(key):
			label = _labour_group_name(key)
		var amount_text: String = ""
		var value: Variant = values[key_variant]
		if value is int:
			amount_text = str(int(value))
		else:
			amount_text = _format_amount(float(value))
		if suffix != "":
			parts.append(label + " " + amount_text + " " + suffix)
		else:
			parts.append(label + " " + amount_text)
	if parts.is_empty():
		return "None"
	return "; ".join(parts)

func _stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func _add_stock(resource_id: String, amount: float) -> void:
	estate_stockpiles[resource_id] = maxf(0.0, _stock(resource_id) + amount)

func _reserve_breakdown(resource_id: String, upkeep_value: float, input_value: float, housing_value: float = 0.0) -> Array[String]:
	var lines: Array[String] = []
	if upkeep_value > 0.0:
		lines.append("Population upkeep: " + _format_amount(upkeep_value))
	if housing_value > 0.0:
		lines.append("Housing building upkeep: " + _format_amount(housing_value))
	if input_value > 0.0:
		lines.append("Building inputs: " + _format_amount(input_value))
	if lines.is_empty():
		lines.append("No current reserve pressure")
	return lines

func _pressure_label(stored: float, outgoing: float) -> String:
	if outgoing <= 0.0:
		if stored <= 0.0:
			return "Absent"
		return "Stored"
	var coverage: float = stored / outgoing
	if coverage >= 5.0:
		return "Abundant"
	if coverage >= 3.0:
		return "Comfortable"
	if coverage >= 1.5:
		return "Tight"
	if coverage >= 0.75:
		return "Shortage"
	return "Crisis"

func _scarcity_multiplier(coverage: float, demand_value: float) -> float:
	if demand_value <= 0.0:
		return 0.75
	if coverage <= 0.0:
		return 3.0
	return maxf(0.75, minf(3.0, 3.0 / coverage))

func _market_label(coverage: float, demand_value: float) -> String:
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

func _market_trend(coverage: float, demand_value: float) -> String:
	if demand_value <= 0.0:
		return "Idle"
	if coverage >= 5.0:
		return "Soft"
	if coverage >= 3.0:
		return "Stable"
	if coverage >= 1.5:
		return "Rising"
	return "Critical"

func _rival_market_note(resource_id: String) -> String:
	match resource_id:
		"weapons", "obsidian":
			return "War Rival pressure: weapons, obsidian and martial goods."
		"tools", "cloth":
			return "Cunning Rival pressure: practical bottlenecks and market leverage."
		"cacao", "fine_textiles":
			return "Diplomatic Rival pressure: palace-facing status goods."
	return "Rival behaviour can alter this market once procurement is connected."


func _apply_market_economy_to_goods(goods: Array[Dictionary]) -> Array[Dictionary]:
	if market_economy.is_empty():
		return goods
	var natural: Dictionary = market_economy.get("village_natural_production", {}) as Dictionary
	var building_outputs: Dictionary = market_economy.get("village_building_outputs", {}) as Dictionary
	var population_use: Dictionary = market_economy.get("village_population_consumption", {}) as Dictionary
	var building_inputs: Dictionary = market_economy.get("village_building_inputs", {}) as Dictionary
	var construction_demand: Dictionary = market_economy.get("year1_construction_demand_per_turn", {}) as Dictionary
	var estate_inputs: Dictionary = market_economy.get("starter_estate_input_demand", {}) as Dictionary
	var estate_outputs: Dictionary = market_economy.get("starter_estate_output_supply", {}) as Dictionary
	var event_modifiers: Dictionary = market_economy.get("event_modifiers", {}) as Dictionary
	for index: int in range(goods.size()):
		var good: Dictionary = goods[index]
		var resource_id: String = String(good.get("id", ""))
		var market_stock: float = float(good.get("market_stock", 0.0))
		var base_value: float = float(good.get("base_value", 1.0))
		var natural_output: float = _market_resource_value(natural, resource_id)
		var building_output: float = _market_resource_value(building_outputs, resource_id)
		var estate_output: float = _market_resource_value(estate_outputs, resource_id)
		var population_demand: float = _market_resource_value(population_use, resource_id)
		var building_demand: float = _market_resource_value(building_inputs, resource_id)
		var construction_need: float = _market_resource_value(construction_demand, resource_id)
		var estate_demand: float = _market_resource_value(estate_inputs, resource_id)
		var event_delta: float = _market_resource_value(event_modifiers, resource_id)
		# Spreadsheet reconciliation: the background market uses the v0.12 balance
		# workbook as its source of truth. Natural output + village building output
		# + the modelled starter-estate supply are compared against population
		# upkeep + village production inputs + year-one construction pressure +
		# starter-estate input pressure. This reproduces the Market Balance sheet
		# net / turn values while still showing the village pieces separately.
		var total_output: float = maxf(0.0, natural_output + building_output + estate_output + event_delta)
		var total_demand: float = maxf(0.0, population_demand + building_demand + construction_need + estate_demand)
		if total_demand <= 0.001:
			total_demand = maxf(0.0, float(good.get("demand", 0.0)))
		var net_change: float = total_output - total_demand
		var projected_stock: float = maxf(0.0, market_stock + net_change)
		var projected_coverage: float = 0.0
		if total_demand > 0.001:
			projected_coverage = projected_stock / total_demand
		var multiplier: float = _market_scarcity_multiplier(projected_coverage, total_demand)
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
		good["label"] = _market_pressure_label(projected_coverage, total_demand)
		good["trend"] = _market_net_trend(net_change, total_demand)
		good["village_note"] = _market_good_note(resource_id)
		goods[index] = good
	return goods

func _market_resource_value(source: Dictionary, resource_id: String) -> float:
	return float(source.get(resource_id, 0.0))

func _market_scarcity_multiplier(coverage: float, demand: float) -> float:
	if demand <= 0.001:
		return 1.0
	if coverage <= 0.001:
		return 3.0
	return clampf(3.0 / coverage, 0.50, 3.0)

func _market_pressure_label(coverage: float, demand: float) -> String:
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

func _market_net_trend(net_change: float, demand: float) -> String:
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

func _market_good_note(resource_id: String) -> String:
	var notes: Dictionary = market_economy.get("resource_notes", {}) as Dictionary
	return String(notes.get(resource_id, "No village economy note recorded yet."))

func _format_amount(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))



# -----------------------------------------------------------------------------
# Warbands v0.1 — backend read-only
# -----------------------------------------------------------------------------

var warbands: Dictionary = {}

func _ensure_warband_state() -> void:
	if not warbands.is_empty():
		return
	var ready_count: int = get_warrior_count()
	warbands["household"] = {
		"id": "household",
		"name": "Household Warband",
		"doctrine_id": "unspecialised",
		"doctrine_name": "Unspecialised",
		"ready_warriors": ready_count,
		"injured_warriors": 0,
		"dead_warriors": 0,
		"xp": 1.0,
		"level": 1,
		"commander": "Unassigned",
		"status": "Ready" if ready_count > 0 else "No ready warriors"
	}

func get_primary_warband() -> Dictionary:
	_ensure_warband_state()
	return (warbands.get("household", {}) as Dictionary).duplicate(true)

func get_warband_rows() -> Array[Dictionary]:
	_ensure_warband_state()
	var rows: Array[Dictionary] = []
	for key_variant: Variant in warbands.keys():
		var warband_id: String = String(key_variant)
		var row: Dictionary = (warbands[warband_id] as Dictionary).duplicate(true)
		row["total_warriors"] = int(row.get("ready_warriors", 0)) + int(row.get("injured_warriors", 0))
		row["available_for_flower_war"] = int(row.get("ready_warriors", 0))
		rows.append(row)
	return rows

# -----------------------------------------------------------------------------
# Barracks / Flower Wars v0.2 — backend launch only
# -----------------------------------------------------------------------------

var last_flower_war_report: Dictionary = {}

const FLOWER_WAR_DOCTRINES: Dictionary = {
	"unspecialised": {"name": "Unspecialised", "offence": 1.0, "defence": 1.0, "role": "Balanced household warriors."},
	"eagle": {"name": "Eagle", "offence": 1.0, "defence": 1.2, "role": "Captive specialists and sustained war fighters."},
	"jaguar": {"name": "Jaguar", "offence": 1.3, "defence": 1.0, "role": "Elite offensive warriors. Prestige values pending calibration."},
	"otomi": {"name": "Otomi", "offence": 0.8, "defence": 1.5, "role": "Defensive veterans who preserve warriors."},
	"coyote": {"name": "Coyote", "offence": 1.4, "defence": 0.5, "role": "Glass-cannon raiders who favour loot."}
}

const FLOWER_WAR_PROVISIONING: Dictionary = {
	"standard": {"name": "Standard", "supply_multiplier": 1.0, "combat_multiplier": 1.0},
	"well": {"name": "Well Provisioned", "supply_multiplier": 2.0, "combat_multiplier": 1.1},
	"royal": {"name": "Royal Provision", "supply_multiplier": 4.0, "combat_multiplier": 1.2}
}

const FLOWER_WAR_OPTIONS: Dictionary = {
	"minor": {"name": "Minor Flower War", "warriors": 5, "enemy_warriors": 5, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 1.2},
	"standard": {"name": "Standard Flower War", "warriors": 10, "enemy_warriors": 10, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 2.4},
	"major": {"name": "Major Flower War", "warriors": 20, "enemy_warriors": 20, "enemy_xp": 1.0, "enemy_offence": 1.0, "enemy_defence": 1.0, "base_loot_value": 4.8}
}

func get_warrior_count() -> int:
	return int(population.get("yaotequihuaqueh", 0))

func get_warrior_capacity() -> int:
	var capacity: Dictionary = housing_capacity_by_group({}, true)
	return int(capacity.get("yaotequihuaqueh", 0))

func get_barracks_summary() -> Dictionary:
	var warriors: int = get_warrior_count()
	var capacity: int = get_warrior_capacity()
	return {
		"warriors": warriors,
		"capacity": capacity,
		"free_capacity": max(0, capacity - warriors),
		"status": "Ready" if warriors > 0 else "No warriors available",
		"doctrines": FLOWER_WAR_DOCTRINES.duplicate(true),
		"provisioning": FLOWER_WAR_PROVISIONING.duplicate(true)
	}

func get_flower_war_options() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for option_id: String in ["minor", "standard", "major"]:
		var data: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
		var row: Dictionary = data.duplicate(true)
		row["id"] = option_id
		row["can_launch_standard"] = get_warrior_count() >= int(row.get("warriors", 0))
		rows.append(row)
	return rows

func get_flower_war_preview(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
		doctrine_id = "unspecialised"
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		provisioning_id = "standard"
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var doctrine: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var warriors_committed: int = int(option.get("warriors", 0))
	var enemy_warriors: int = int(option.get("enemy_warriors", warriors_committed))
	var combat_multiplier: float = float(provisioning.get("combat_multiplier", 1.0))
	var attacker_attack: float = float(warriors_committed) * float(doctrine.get("offence", 1.0)) * combat_multiplier
	var defender_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, attacker_attack - defender_defence * 0.55))), 0, enemy_warriors)
	var surviving_defenders: int = max(0, enemy_warriors - defender_casualties)
	var defender_attack: float = float(surviving_defenders) * float(option.get("enemy_offence", 1.0))
	var attacker_defence: float = float(warriors_committed) * float(doctrine.get("defence", 1.0))
	var attacker_casualties: int = clampi(int(round(maxf(0.0, defender_attack - attacker_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = defender_casualties - attacker_casualties
	var result: String = _flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var captives: int = _flower_war_captives(result, defender_casualties, warriors_committed, doctrine_id)
	var loot: Dictionary = _flower_war_loot(result, defender_casualties, doctrine_id, float(option.get("base_loot_value", 1.2)))
	var provisioning_cost: Dictionary = _flower_war_provisioning_cost(warriors_committed, float(provisioning.get("supply_multiplier", 1.0)))
	return {
		"ok": true,
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"doctrine_id": doctrine_id,
		"doctrine_name": String(doctrine.get("name", doctrine_id.capitalize())),
		"provisioning_id": provisioning_id,
		"provisioning_name": String(provisioning.get("name", provisioning_id.capitalize())),
		"warriors_committed": warriors_committed,
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"provisioning_cost": provisioning_cost,
		"prestige_pending": true,
		"prestige_text": "Prestige pending calibration."
	}

func can_launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	var preview: Dictionary = get_flower_war_preview(option_id, doctrine_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var needed_warriors: int = int(preview.get("warriors_committed", 0))
	if get_warrior_count() < needed_warriors:
		return {"ok": false, "reason": "Need " + str(needed_warriors) + " warriors."}
	return _can_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)

func launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_flower_war(option_id, doctrine_id, provisioning_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch."))}
		last_report.append("Flower War not launched: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		emit_signal("state_changed")
		return last_flower_war_report.duplicate(true)
	var preview: Dictionary = get_flower_war_preview(option_id, doctrine_id, provisioning_id)
	_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	var committed: int = int(preview.get("warriors_committed", 0))
	var dead: int = int(preview.get("attacker_dead", 0))
	population["yaotequihuaqueh"] = max(0, get_warrior_count() - dead)
	var captives: int = int(preview.get("captives", 0))
	if captives > 0:
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
	add_looted_goods_bundle(preview.get("loot", {}) as Dictionary)
	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["warriors_returned"] = max(0, committed - int(preview.get("attacker_casualties", 0)))
	var line: String = String(preview.get("option_name", "Flower War")) + " resolved: " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + "; casualties " + str(int(preview.get("attacker_casualties", 0))) + " (dead " + str(dead) + "). Captives gained " + str(captives) + ". Prestige pending calibration."
	last_report.append(line)
	emit_signal("state_changed")
	return last_flower_war_report.duplicate(true)

func get_last_flower_war_report() -> Dictionary:
	return last_flower_war_report.duplicate(true)

func _flower_war_result_label(net_damage: int, attacker_size: int, defender_size: int) -> String:
	var scale: float = maxf(1.0, float(max(attacker_size, defender_size)))
	var ratio: float = float(net_damage) / scale
	if ratio >= 0.65:
		return "Crushing Victory"
	if ratio >= 0.25:
		return "Victory"
	if ratio > 0.05:
		return "Marginal Victory"
	if ratio >= -0.05:
		return "Stalemate"
	if ratio > -0.35:
		return "Defeat"
	return "Crushing Defeat"

func _flower_war_captives(result: String, defender_casualties: int, warriors_committed: int, doctrine_id: String) -> int:
	if defender_casualties <= 0:
		return 0
	var rate: float = 0.0
	match result:
		"Crushing Victory":
			rate = 0.45
		"Victory":
			rate = 0.30
		"Marginal Victory":
			rate = 0.15
		_:
			rate = 0.0
	if doctrine_id == "eagle":
		rate += float(warriors_committed) * 0.02
	var raw: float = float(defender_casualties) * rate
	if raw > 0.0:
		return mini(defender_casualties, max(1, int(ceil(raw))))
	return 0

func _flower_war_loot(result: String, defender_casualties: int, doctrine_id: String, base_loot_value: float) -> Dictionary:
	var multiplier: float = 0.0
	match result:
		"Crushing Victory":
			multiplier = 2.0
		"Victory":
			multiplier = 1.2
		"Marginal Victory":
			multiplier = 0.6
		"Stalemate":
			multiplier = 0.3
		"Defeat":
			multiplier = 0.1
		_:
			multiplier = 0.0
	if doctrine_id == "coyote":
		multiplier *= 1.5
	var units: float = maxf(0.0, float(defender_casualties) * base_loot_value * multiplier)
	if units <= 0.0:
		return {}
	return {"maize": snappedf(units * 0.50, 0.01), "wood": snappedf(units * 0.25, 0.01), "cloth": snappedf(units * 0.15, 0.01), "obsidian": snappedf(units * 0.10, 0.01)}

func _flower_war_provisioning_cost(warriors_committed: int, supply_multiplier: float) -> Dictionary:
	return {"maize": float(warriors_committed) * 1.0 * supply_multiplier, "weapons": float(warriors_committed) * 0.2 * supply_multiplier}

func _can_pay_free_stock(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		if free_stock_after_reserves(resource_id) + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(needed) + " free " + get_resource_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Ready."}

func _pay_free_stock(cost: Dictionary) -> void:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_variant]))
