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

const GOD_TLALOC: String = "tlaloc"
const GOD_HUITZILOPOCHTLI: String = "huitzilopochtli"
const GOD_TEZCATLIPOCA: String = "tezcatlipoca"
const GOD_QUETZALCOATL: String = "quetzalcoatl"
const PALACE_GOD_IDS: Array[String] = [GOD_TLALOC, GOD_HUITZILOPOCHTLI, GOD_TEZCATLIPOCA, GOD_QUETZALCOATL]

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
var player_palace_dedicated_god: String = ""
var palace_built_structures: Dictionary = {}
var palace_structure_runtime_statuses: Dictionary = {}
var last_palace_maintenance_report: Array[String] = []
# Palace gating infrastructure is present, but disabled for now.
# Later palace implementation can flip this to true so Flower Wars require
# a Huitzilopochtli-dedicated palace without rewriting the war backend.
var flower_war_palace_gate_enabled: bool = false

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
	palace_built_structures.clear()
	_ensure_warband_state()
	last_flower_war_report.clear()
	flower_war_report_archive.clear()
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
	_pay_palace_maintenance()
	_operate_buildings()
	_recover_injured_warriors()
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
# Barracks / Flower Wars v0.15 — injured recovery + reinforcement clarity
# -----------------------------------------------------------------------------

var last_flower_war_report: Dictionary = {}
var flower_war_report_archive: Array[Dictionary] = []
var warbands: Dictionary = {}

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

const FLOWER_WAR_DEFENCE_STRATEGIES: Dictionary = {
	"balanced": {"name": "Balanced Defence", "offence_multiplier": 1.0, "defence_multiplier": 1.0, "description": "A steady response with no bonus or penalty."},
	"depth": {"name": "Defence in Depth", "offence_multiplier": 0.85, "defence_multiplier": 1.25, "description": "Protect the warbands and absorb the attack. More defence, less offence."},
	"good_offence": {"name": "The Best Defence is a Good Offence", "offence_multiplier": 1.25, "defence_multiplier": 0.85, "description": "Counterattack hard. More offence, less defence."}
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
		"unassigned_warriors": _unassigned_warrior_pool(),
		"status": "Ready" if warriors > 0 else "No warriors available",
		"weapons": free_stock_after_reserves("weapons"),
		"captives": int(estate_stockpiles.get("captives", 0.0)),
		"palace_dedicated_god": get_player_palace_dedicated_god(),
		"has_war_god_palace": has_war_god_palace(),
		"flower_war_palace_gate_enabled": is_flower_war_palace_gate_enabled(),
		"flower_war_palace_gate_passed": flower_war_palace_gate_passed(),
		"doctrines": FLOWER_WAR_DOCTRINES.duplicate(true),
		"provisioning": FLOWER_WAR_PROVISIONING.duplicate(true),
		"defence_strategies": FLOWER_WAR_DEFENCE_STRATEGIES.duplicate(true),
		"army_muster": get_army_muster_summary()
	}

func get_warband_combat_stats(warband_id: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {}
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return _warband_combat_stats_from_warband(warband)

func get_army_muster_summary() -> Dictionary:
	_ensure_warband_state()
	var rows: Array[Dictionary] = []
	var total_ready: int = 0
	var total_injured: int = 0
	var total_dead: int = 0
	var total_offence: float = 0.0
	var total_defence: float = 0.0
	var active_warbands: int = 0
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = warband
		var stats: Dictionary = _warband_combat_stats_from_warband(warband)
		rows.append(stats)
		total_ready += int(stats.get("ready", 0))
		total_injured += int(stats.get("injured", 0))
		total_dead += int(stats.get("dead_total", 0))
		total_offence += float(stats.get("effective_offence", 0.0))
		total_defence += float(stats.get("effective_defence", 0.0))
		if int(stats.get("ready", 0)) > 0:
			active_warbands += 1
	return {
		"warbands": rows,
		"warband_count": rows.size(),
		"active_warband_count": active_warbands,
		"ready_warriors": total_ready,
		"injured_not_fighting": total_injured,
		"dead_suffered": total_dead,
		"effective_offence": snappedf(total_offence, 0.01),
		"effective_defence": snappedf(total_defence, 0.01),
		"skill_web_effects_connected": false,
		"stats_note": "Combat stats use ready warriors and the doctrine chosen through the Skill Web specialism. Other node effects are not connected to Flower War resolution yet.",
		"injury_note": "Injured warriors do not fight, cannot be unassigned, and recover on the next Veintena advance."
	}

func _warband_doctrine_data(doctrine_id: String) -> Dictionary:
	var cleaned: String = doctrine_id
	if not FLOWER_WAR_DOCTRINES.has(cleaned):
		cleaned = "unspecialised"
	var data: Dictionary = (FLOWER_WAR_DOCTRINES[cleaned] as Dictionary).duplicate(true)
	data["id"] = cleaned
	return data

func _warband_combat_stats_from_warband(warband: Dictionary) -> Dictionary:
	var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
	var doctrine: Dictionary = _warband_doctrine_data(doctrine_id)
	var ready: int = max(0, int(warband.get("ready_warriors", warband.get("ready", 0))))
	var injured: int = max(0, int(warband.get("injured_warriors", warband.get("injured", 0))))
	var dead_total: int = max(0, int(warband.get("dead_total", 0)))
	var total_known: int = ready + injured
	var offence_mod: float = float(doctrine.get("offence", 1.0))
	var defence_mod: float = float(doctrine.get("defence", 1.0))
	return {
		"id": String(warband.get("id", "")),
		"name": String(warband.get("name", "Warband")),
		"doctrine_id": String(doctrine.get("id", "unspecialised")),
		"doctrine_name": String(doctrine.get("name", "Unspecialised")),
		"doctrine_role": String(doctrine.get("role", "")),
		"ready": ready,
		"injured": injured,
		"dead_total": dead_total,
		"total_present": total_known,
		"offence_modifier": offence_mod,
		"defence_modifier": defence_mod,
		"effective_offence": snappedf(float(ready) * offence_mod, 0.01),
		"effective_defence": snappedf(float(ready) * defence_mod, 0.01),
		"skill_web_effects_connected": false,
		"stats_note": "Doctrine preview. The Skill Web specialism sets combat doctrine; other node effects are recorded as prototype data but are not connected to Flower War resolution yet."
	}


func get_player_palace_dedicated_god() -> String:
	return player_palace_dedicated_god

func set_player_palace_dedicated_god(god_id: String) -> Dictionary:
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		player_palace_dedicated_god = ""
		if is_flower_war_palace_gate_enabled():
			last_report.append("Palace dedication cleared. Flower Wars are locked until the palace is dedicated to Huitzilopochtli.")
		else:
			last_report.append("Palace dedication cleared. Flower Wars remain open because the palace gate is not active yet.")
		emit_signal("state_changed")
		return {"ok": true, "reason": "Palace dedication cleared."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	player_palace_dedicated_god = cleaned
	last_report.append("Palace dedicated to " + _god_display_name(cleaned) + ".")
	emit_signal("state_changed")
	return {"ok": true, "reason": "Palace dedicated to " + _god_display_name(cleaned) + "."}

func has_war_god_palace() -> bool:
	# This reports the actual palace dedication state only. It does not bypass the
	# rule when the temporary gate is disabled. Use flower_war_palace_gate_passed()
	# for launch permission.
	return player_palace_dedicated_god == GOD_HUITZILOPOCHTLI

func is_flower_war_palace_gate_enabled() -> bool:
	return flower_war_palace_gate_enabled

func set_flower_war_palace_gate_enabled(enabled: bool) -> Dictionary:
	flower_war_palace_gate_enabled = enabled
	if enabled:
		last_report.append("Flower War palace gate enabled. Flower Wars now require a Huitzilopochtli-dedicated palace.")
	else:
		last_report.append("Flower War palace gate disabled. Flower Wars are open until the Palace system is implemented.")
	emit_signal("state_changed")
	return {"ok": true, "enabled": enabled}

func flower_war_palace_gate_passed() -> bool:
	# Temporary MVP behaviour: the infrastructure exists, but the gate is disabled
	# until the Palace screen/dedication system is implemented. When enabled, the
	# existing Huitzilopochtli dedication check becomes active immediately.
	if not is_flower_war_palace_gate_enabled():
		return true
	return has_war_god_palace()

func flower_war_palace_gate_status_text() -> String:
	if not is_flower_war_palace_gate_enabled():
		return "Palace gate inactive: Flower Wars are currently open. Future implementation will require a Huitzilopochtli palace."
	if has_war_god_palace():
		return "War palace gate open: Palace dedicated to Huitzilopochtli."
	if player_palace_dedicated_god == "":
		return "Flower Wars locked: Requires Palace dedicated to Huitzilopochtli."
	return "Flower Wars locked: current palace dedication is " + _god_display_name(player_palace_dedicated_god) + "; requires Huitzilopochtli."

func _god_display_name(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Tlaloc"
		"huitzilopochtli":
			return "Huitzilopochtli"
		"tezcatlipoca":
			return "Tezcatlipoca"
		"quetzalcoatl":
			return "Quetzalcoatl"
	return god_id.capitalize()


# -----------------------------------------------------------------------------
# Palace backend probe v0.20.1
# -----------------------------------------------------------------------------
# Read-only palace planning data. This deliberately does not add Palace UI,
# dedication buttons, structure construction, ruler-demand mechanics, or Flower War
# gate changes. Palace structures can now be built and can become active/inactive
# based on upkeep and existing staff availability.

func get_palace_dedicated_god() -> String:
	return get_player_palace_dedicated_god()

func get_palace_route_name(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Natural Calendar Foresight"
		"huitzilopochtli":
			return "Flower Wars Authority"
		"tezcatlipoca":
			return "Scarcity and Intrigue"
		"quetzalcoatl":
			return "Legitimacy and Recognition"
	return "No Palace Route"

func get_palace_route_power_summary(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Deep calendar and natural-event foresight: higher palace levels will reveal droughts, floods, harvest pressure and other natural events earlier and in more detail."
		"huitzilopochtli":
			return "Flower Wars authority: dedicating the Palace to Huitzilopochtli will formally authorise attacking Flower Wars and the war route once the palace gate is reconnected."
		"tezcatlipoca":
			return "Scarcity, intrigue and market pressure: future structures will support rival pressure, disruption, manipulation, sabotage hooks and market leverage."
		"quetzalcoatl":
			return "Legitimacy, recognition and palace trust: future structures will strengthen ruler-facing credibility, order, tribute reliability and prestige-style authority."
	return "No palace dedication has been chosen. Dedication will define the house's palace route."


func can_dedicate_palace_to_god(god_id: String) -> Dictionary:
	var cleaned: String = god_id.strip_edges().to_lower()
	if cleaned == "":
		return {"ok": false, "reason": "Choose a palace god."}
	if not PALACE_GOD_IDS.has(cleaned):
		return {"ok": false, "reason": "Unknown palace god: " + god_id + "."}
	if get_palace_dedicated_god() != "":
		return {"ok": false, "reason": "The palace is already dedicated to " + _god_display_name(get_palace_dedicated_god()) + ". Prototype 0 dedication is permanent."}
	return {"ok": true, "reason": "Ready to dedicate the palace to " + _god_display_name(cleaned) + "."}

func dedicate_palace_to_god(god_id: String) -> Dictionary:
	var status: Dictionary = can_dedicate_palace_to_god(god_id)
	if not bool(status.get("ok", false)):
		last_report.append("Palace dedication failed: " + String(status.get("reason", "")))
		emit_signal("state_changed")
		return status
	var cleaned: String = god_id.strip_edges().to_lower()
	player_palace_dedicated_god = cleaned
	last_report.append("Palace dedicated to " + _god_display_name(cleaned) + ". The Divine Seat now displays the " + get_palace_route_name(cleaned) + " structure node data.")
	emit_signal("state_changed")
	return {"ok": true, "reason": "Palace dedicated to " + _god_display_name(cleaned) + ".", "god_id": cleaned}

func get_palace_structure_tree_shell(god_id: String = "") -> Dictionary:
	var route_id: String = god_id.strip_edges().to_lower()
	if route_id == "":
		route_id = get_palace_dedicated_god()
	if not PALACE_GOD_IDS.has(route_id):
		return {"god_id": "", "god_name": "None", "route_name": "No Palace Route", "tiers": [], "note": "Dedicate the palace to reveal a route-specific palace structure tree."}
	var tiers: Array[Dictionary] = _palace_structure_tree_tiers(route_id)
	_apply_palace_structure_statuses(tiers, route_id)
	return {
		"god_id": route_id,
		"god_name": _god_display_name(route_id),
		"route_name": get_palace_route_name(route_id),
		"power_summary": get_palace_route_power_summary(route_id),
		"tiers": tiers,
		"built_structure_count": get_built_palace_structure_ids().size(),
		"total_maintenance": get_palace_total_maintenance(),
		"required_staff": get_palace_required_staff(),
		"note": "Palace structures can be built and now preview active/inactive status from maintenance and staff availability. Authority effects are still future patches."
	}

func _palace_structure_node(
	id: String,
	god_id: String,
	tier: int,
	name: String,
	description: String,
	build_cost: Dictionary,
	maintenance_cost: Dictionary,
	staff_requirement: Dictionary,
	prerequisites: Array[String],
	effect_summary: String
) -> Dictionary:
	var prerequisite_text: String = "None"
	if not prerequisites.is_empty():
		prerequisite_text = ", ".join(prerequisites)
	var built: bool = _is_palace_structure_built(id)
	var status_text: String = "Not built"
	if built:
		status_text = "Built — operation check pending"
	return {
		"id": id,
		"name": name,
		"god_id": god_id,
		"route": get_palace_route_name(god_id),
		"tier": tier,
		"level": tier,
		"description": description,
		"summary": effect_summary,
		"build_cost": build_cost,
		"maintenance_cost": maintenance_cost,
		"staff_requirement": staff_requirement,
		"prerequisites": prerequisites,
		"prerequisite_text": prerequisite_text,
		"effect_summary": effect_summary,
		"status": status_text,
		"built": built,
		"active": false,
		"inactive_reason": "Not built.",
		"prototype_note": "Construction, maintenance payment and staff checks are implemented. Authority effects are not active yet."
	}

func _palace_structure_tree_tiers(god_id: String) -> Array[Dictionary]:
	match god_id:
		"tlaloc":
			return [
				{"tier": 1, "title": "Level 1 — Household Water Court", "structures": [
					_palace_structure_node("tlaloc_rain_reading_basin", god_id, 1, "Rain-Reading Basin", "A polished basin set in the palace court for reading rain, reflected sky, canal levels and field signs.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Reveals basic nearby natural pressure once the Tlaloc authority system is active."),
					_palace_structure_node("tlaloc_canal_listening_court", god_id, 1, "Canal Listening Court", "A quiet court where priests and estate nobles listen for canal, flood and lake warnings.", {"wood": 22.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for canal, flood and water-management warnings."),
					_palace_structure_node("tlaloc_field_omen_chamber", god_id, 1, "Field Omen Chamber", "A chamber for crop samples, pest signs and soil offerings brought in from the estate lands.", {"wood": 16.0, "cloth": 4.0, "cacao": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1}, [], "Future hook for crop, pest and harvest-risk signs.")
				]},
				{"tier": 2, "title": "Level 2 — Storm Calendar Wing", "structures": [
					_palace_structure_node("tlaloc_storm_calendar_archive", god_id, 2, "Storm Calendar Archive", "Painted bark records and priestly tallies compare present weather signs against previous ritual years.", {"wood": 40.0, "cloth": 10.0, "ritual_goods": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["One Level 1 Tlaloc structure"], "Extends natural-event forecast range."),
					_palace_structure_node("tlaloc_drought_vessel_court", god_id, 2, "Drought Vessel Court", "Rows of sealed vessels hold water, dust and field offerings to read dry-season severity.", {"wood": 34.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2}, ["Rain-Reading Basin"], "Future hook for drought severity and preparation."),
					_palace_structure_node("tlaloc_flood_marker_terrace", god_id, 2, "Flood Marker Terrace", "A raised terrace marked with carved flood levels and canal measures.", {"wood": 44.0, "cloth": 8.0, "tools": 2.0}, {"cacao": 0.75, "tools": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, ["Canal Listening Court"], "Future hook for flood severity and likely affected goods.")
				]},
				{"tier": 3, "title": "Level 3 — Deep Omen Court", "structures": [
					_palace_structure_node("tlaloc_deep_calendar_observatory", god_id, 3, "Deep Calendar Observatory", "A high palace platform for aligning rain, mountain, canal and crop records into long-range forecast patterns.", {"wood": 80.0, "cloth": 18.0, "ritual_goods": 6.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 1.0, "fine_textiles": 0.25}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Storm Calendar Archive"], "Reveals event duration and affected goods once forecast mechanics are active."),
					_palace_structure_node("tlaloc_lake_mirror_priests", god_id, 3, "Lake-Mirror Priests", "A staffed priestly office that compares mirrored water signs against tribute and field records.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 4, "pipiltin": 1}, ["Drought Vessel Court or Flood Marker Terrace"], "Future hook for better forecast accuracy and fewer unknowns.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tlaloc", "structures": [
					_palace_structure_node("tlaloc_great_court", god_id, 4, "Great Court of Tlaloc", "A full palace court dedicated to rain, waters, fields and the hidden calendar of natural pressure.", {"wood": 140.0, "cloth": 35.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "fine_textiles": 0.5}, {"tlamacazqueh": 6, "pipiltin": 3}, ["Deep Calendar Observatory", "Lake-Mirror Priests"], "Long-range natural calendar foresight and full Tlaloc palace authority.")
				]}
			]
		"huitzilopochtli":
			return [
				{"tier": 1, "title": "Level 1 — War Banner Court", "structures": [
					_palace_structure_node("huitz_war_banner_court", god_id, 1, "War Banner Court", "A court for public war standards, muster rites and the formal authority of the war route.", {"wood": 20.0, "cloth": 5.0, "weapons": 1.0}, {"cacao": 0.5, "cloth": 0.5}, {"pipiltin": 1}, [], "Future home of formal Flower War authority."),
					_palace_structure_node("huitz_captive_procession_steps", god_id, 1, "Captive Procession Steps", "Ceremonial steps for bringing captives, witnesses and war spoils into palace view.", {"wood": 18.0, "cloth": 4.0, "ritual_goods": 1.0}, {"cacao": 0.5, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for captives, sacrifice and war-route visibility."),
					_palace_structure_node("huitz_weapon_oath_hall", god_id, 1, "Weapon Oath Hall", "A hall where warriors and nobles bind weapons, discipline and palace service to the war god.", {"wood": 24.0, "cloth": 4.0, "weapons": 2.0}, {"cacao": 0.5, "weapons": 0.25}, {"pipiltin": 1}, [], "Future hook for military organisation and warrior preparation.")
				]},
				{"tier": 2, "title": "Level 2 — Martial Review Wing", "structures": [
					_palace_structure_node("huitz_eagle_jaguar_review_court", god_id, 2, "Eagle-Jaguar Review Court", "A review court for warbands, captains and noble witnesses before a Flower War muster.", {"wood": 45.0, "cloth": 10.0, "weapons": 3.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["War Banner Court"], "Future hook for warband management authority."),
					_palace_structure_node("huitz_sacrifice_ledger_chamber", god_id, 2, "Sacrifice Ledger Chamber", "A palace office recording captives, ritual use, witnesses and obligation fulfilment.", {"wood": 36.0, "cloth": 8.0, "ritual_goods": 3.0}, {"cacao": 1.0, "ritual_goods": 0.5}, {"tlamacazqueh": 2, "pipiltin": 1}, ["Captive Procession Steps"], "Future hook for captive-to-ritual administration."),
					_palace_structure_node("huitz_martial_tribute_office", god_id, 2, "Martial Tribute Office", "An office that separates war spoils, weapon obligations and ruler-facing martial goods.", {"wood": 38.0, "cloth": 8.0, "tools": 2.0, "weapons": 2.0}, {"cacao": 1.0, "tools": 0.25}, {"pipiltin": 2}, ["Weapon Oath Hall"], "Future hook for war spoils and obligations.")
				]},
				{"tier": 3, "title": "Level 3 — Sun-War Tribunal", "structures": [
					_palace_structure_node("huitz_sun_war_tribunal", god_id, 3, "Sun-War Tribunal", "A high tribunal where war success, captives and noble martial claims are judged.", {"wood": 85.0, "cloth": 18.0, "ritual_goods": 6.0, "weapons": 5.0, "fine_textiles": 1.0}, {"cacao": 1.5, "ritual_goods": 0.75, "weapons": 0.5}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Eagle-Jaguar Review Court"], "Stronger war-route legitimacy and martial recognition hooks."),
					_palace_structure_node("huitz_captive_witness_court", god_id, 3, "Captive Witness Court", "A public court where captives, witnesses and palace representatives make war results visible.", {"wood": 74.0, "cloth": 16.0, "ritual_goods": 6.0, "cacao": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 3, "pipiltin": 2}, ["Sacrifice Ledger Chamber or Martial Tribute Office"], "Future hook for public war legitimacy and captive display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Huitzilopochtli", "structures": [
					_palace_structure_node("huitz_great_court", god_id, 4, "Great Court of Huitzilopochtli", "A full palace court for war, captives, martial claims and the authority to pursue the war route.", {"wood": 150.0, "cloth": 35.0, "weapons": 10.0, "ritual_goods": 10.0, "fine_textiles": 2.0}, {"cacao": 3.0, "ritual_goods": 1.5, "weapons": 0.75}, {"tlamacazqueh": 4, "pipiltin": 5}, ["Sun-War Tribunal", "Captive Witness Court"], "Full war palace authority and late war-route support.")
				]}
			]
		"tezcatlipoca":
			return [
				{"tier": 1, "title": "Level 1 — Mirror Court", "structures": [
					_palace_structure_node("tez_obsidian_mirror_chamber", god_id, 1, "Obsidian Mirror Chamber", "A dark palace room for reading rivals, scarcity and hidden pressure through polished obsidian.", {"wood": 18.0, "cloth": 4.0, "obsidian": 2.0}, {"cacao": 0.75, "obsidian": 0.25}, {"pipiltin": 1}, [], "Future hook for rival and market-pressure hints."),
					_palace_structure_node("tez_smoke_messenger_room", god_id, 1, "Smoke Messenger Room", "A chamber for controlled smoke rites, secret messages and dangerous promises.", {"wood": 20.0, "cloth": 5.0, "ritual_goods": 1.0}, {"cacao": 0.75, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 1}, [], "Future hook for manipulation and hidden communication."),
					_palace_structure_node("tez_night_ledger_office", god_id, 1, "Night Ledger Office", "A concealed ledger office for recording shortages, debts, rival needs and pressure points.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 1.0, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for shortage and pressure-point tracking.")
				]},
				{"tier": 2, "title": "Level 2 — Shadow Administration", "structures": [
					_palace_structure_node("tez_rival_shadow_court", god_id, 2, "Rival Shadow Court", "A hidden court for measuring rival weakness, pride, debts and dangerous opportunities.", {"wood": 42.0, "cloth": 10.0, "obsidian": 3.0, "cacao": 3.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Obsidian Mirror Chamber"], "Future hook for rival disruption."),
					_palace_structure_node("tez_scarcity_granary_office", god_id, 2, "Scarcity Granary Office", "An office that tracks shortages, market bottlenecks and which goods can be pressured.", {"wood": 40.0, "cloth": 8.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.25, "tools": 0.25}, {"pipiltin": 2}, ["Night Ledger Office"], "Future hook for market pressure leverage."),
					_palace_structure_node("tez_whispering_servant_network", god_id, 2, "Whispering Servant Network", "A staff network of servants, messengers and obligated listeners around rival households.", {"wood": 34.0, "cloth": 10.0, "cacao": 4.0}, {"cacao": 1.5, "cloth": 0.5}, {"pipiltin": 1, "tlacotin": 5}, ["Smoke Messenger Room"], "Future hook for intrigue and hidden pressure.")
				]},
				{"tier": 3, "title": "Level 3 — Black Mirror Council", "structures": [
					_palace_structure_node("tez_black_mirror_council", god_id, 3, "Black Mirror Council", "A dangerous council for coordinating hidden pressure, scarcity plays and rival manipulation.", {"wood": 82.0, "cloth": 20.0, "obsidian": 6.0, "fine_textiles": 1.0}, {"cacao": 2.5, "obsidian": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 2, "pipiltin": 3}, ["Rival Shadow Court or Scarcity Granary Office"], "Stronger hidden pressure and manipulation hooks."),
					_palace_structure_node("tez_broken_oath_chamber", god_id, 3, "Broken Oath Chamber", "A private chamber for dangerous bargains, threats and promises that should never be spoken publicly.", {"wood": 70.0, "cloth": 16.0, "ritual_goods": 5.0, "obsidian": 4.0}, {"cacao": 2.0, "ritual_goods": 0.75}, {"tlamacazqueh": 2, "pipiltin": 2}, ["Whispering Servant Network"], "Future hook for dangerous rival-pressure tools.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Tezcatlipoca", "structures": [
					_palace_structure_node("tez_great_court", god_id, 4, "Great Court of Tezcatlipoca", "A hidden-palace court where scarcity, fear, ambition and rival weakness are treated as instruments of power.", {"wood": 145.0, "cloth": 35.0, "obsidian": 10.0, "ritual_goods": 8.0, "fine_textiles": 2.0}, {"cacao": 4.0, "obsidian": 1.0, "fine_textiles": 0.5}, {"tlamacazqueh": 3, "pipiltin": 6}, ["Black Mirror Council", "Broken Oath Chamber"], "High-level scarcity, intrigue and rival-pressure authority.")
				]}
			]
		"quetzalcoatl":
			return [
				{"tier": 1, "title": "Level 1 — Feathered Audience Hall", "structures": [
					_palace_structure_node("quetz_feathered_audience_hall", god_id, 1, "Feathered Audience Hall", "An elegant audience hall where the palace presents orderly, legitimate authority to guests and retainers.", {"wood": 20.0, "cloth": 6.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for ruler-facing legitimacy."),
					_palace_structure_node("quetz_tribute_record_office", god_id, 1, "Tribute Record Office", "A record office for tribute promises, deliveries, stored goods and ruler-facing reliability.", {"wood": 18.0, "cloth": 5.0, "tools": 1.0}, {"cacao": 0.5, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for demand delivery clarity."),
					_palace_structure_node("quetz_scribe_mat_court", god_id, 1, "Scribe Mat Court", "A court of mats, painted records and formal speech for orderly palace administration.", {"wood": 18.0, "cloth": 5.0, "cacao": 1.0}, {"cacao": 0.75, "cloth": 0.25}, {"pipiltin": 1}, [], "Future hook for order and palace administration.")
				]},
				{"tier": 2, "title": "Level 2 — Diplomatic Reception Wing", "structures": [
					_palace_structure_node("quetz_diplomatic_reception_court", god_id, 2, "Diplomatic Reception Court", "A reception court for rival houses, messengers, ruler agents and formal negotiation.", {"wood": 42.0, "cloth": 12.0, "cacao": 3.0, "fine_textiles": 1.0}, {"cacao": 1.5, "fine_textiles": 0.25}, {"pipiltin": 2}, ["Feathered Audience Hall"], "Future negotiation and recognition hooks."),
					_palace_structure_node("quetz_law_speech_chamber", god_id, 2, "Law-Speech Chamber", "A chamber where obligations, promises and public judgements are spoken before witnesses.", {"wood": 38.0, "cloth": 10.0, "ritual_goods": 2.0}, {"cacao": 1.0, "ritual_goods": 0.25}, {"tlamacazqueh": 1, "pipiltin": 2}, ["Scribe Mat Court"], "Future hook for trust and formal legitimacy."),
					_palace_structure_node("quetz_market_wind_gallery", god_id, 2, "Market-Wind Gallery", "A palace gallery where trade information, tribute expectation and visible order are brought together.", {"wood": 40.0, "cloth": 10.0, "tools": 2.0, "cacao": 2.0}, {"cacao": 1.0, "cloth": 0.5}, {"pipiltin": 2}, ["Tribute Record Office"], "Future hook for palace performance and credibility.")
				]},
				{"tier": 3, "title": "Level 3 — Feathered Legitimacy Court", "structures": [
					_palace_structure_node("quetz_feathered_legitimacy_court", god_id, 3, "Feathered Legitimacy Court", "A major court of record, ceremony and noble reception for proving the house deserves recognition.", {"wood": 82.0, "cloth": 22.0, "cacao": 5.0, "fine_textiles": 2.0}, {"cacao": 2.0, "fine_textiles": 0.5}, {"pipiltin": 4}, ["Diplomatic Reception Court or Law-Speech Chamber"], "Stronger recognition-route and tribute credibility hooks."),
					_palace_structure_node("quetz_ruler_witness_hall", god_id, 3, "Ruler Witness Hall", "A formal hall designed to make obligation, success and legitimacy visible to agents of higher authority.", {"wood": 74.0, "cloth": 18.0, "ritual_goods": 4.0, "fine_textiles": 1.0}, {"cacao": 2.0, "ritual_goods": 0.5, "fine_textiles": 0.25}, {"tlamacazqueh": 1, "pipiltin": 3}, ["Market-Wind Gallery"], "Future hook for high-trust ruler-facing display.")
				]},
				{"tier": 4, "title": "Level 4 — Great Court of Quetzalcoatl", "structures": [
					_palace_structure_node("quetz_great_court", god_id, 4, "Great Court of Quetzalcoatl", "A full legitimacy court for tribute reliability, palace order, recognition and ruler-facing trust.", {"wood": 150.0, "cloth": 40.0, "cacao": 8.0, "ritual_goods": 8.0, "fine_textiles": 3.0}, {"cacao": 3.5, "fine_textiles": 0.75}, {"tlamacazqueh": 2, "pipiltin": 6}, ["Feathered Legitimacy Court", "Ruler Witness Hall"], "Full legitimacy palace authority and late recognition-route support.")
				]}
			]
	return []


func get_built_palace_structure_ids() -> Array[String]:
	var output: Array[String] = []
	for key_variant: Variant in palace_built_structures.keys():
		var structure_id: String = String(key_variant)
		if bool(palace_built_structures.get(structure_id, false)):
			output.append(structure_id)
	output.sort()
	return output

func _is_palace_structure_built(structure_id: String) -> bool:
	return bool(palace_built_structures.get(structure_id, false))

func _apply_palace_structure_statuses(tiers: Array[Dictionary], route_id: String) -> void:
	var operation_preview: Dictionary = get_palace_structure_operation_preview()
	var operation_statuses: Dictionary = operation_preview.get("statuses", {}) as Dictionary
	for tier_index: int in range(tiers.size()):
		var tier: Dictionary = tiers[tier_index]
		var structures: Array = tier.get("structures", []) as Array
		for structure_index: int in range(structures.size()):
			if not (structures[structure_index] is Dictionary):
				continue
			var structure: Dictionary = structures[structure_index] as Dictionary
			var structure_id: String = String(structure.get("id", ""))
			var built: bool = _is_palace_structure_built(structure_id)
			var build_status: Dictionary = can_build_palace_structure(structure_id)
			structure["built"] = built
			structure["can_build"] = bool(build_status.get("ok", false))
			structure["build_status"] = String(build_status.get("reason", ""))
			if built:
				var op_status: Dictionary = operation_statuses.get(structure_id, {}) as Dictionary
				var active: bool = bool(op_status.get("active", false))
				structure["active"] = active
				structure["inactive_reason"] = String(op_status.get("inactive_reason", "Operation status not calculated."))
				structure["maintenance_paid_preview"] = op_status.get("maintenance_paid", {}) as Dictionary
				structure["staff_assigned_preview"] = op_status.get("staff_assigned", {}) as Dictionary
				if active:
					structure["status"] = "Active"
				else:
					structure["status"] = "Built, inactive"
			elif bool(build_status.get("ok", false)):
				structure["active"] = false
				structure["inactive_reason"] = "Not built."
				structure["status"] = "Ready to build"
			else:
				structure["active"] = false
				structure["inactive_reason"] = "Not built."
				structure["status"] = "Locked"
			structures[structure_index] = structure
		tier["structures"] = structures
		tiers[tier_index] = tier

func _palace_structure_by_id(structure_id: String, route_id: String = "") -> Dictionary:
	var search_routes: Array[String] = []
	if route_id.strip_edges() != "":
		search_routes.append(route_id.strip_edges().to_lower())
	else:
		var dedicated: String = get_palace_dedicated_god()
		if dedicated != "":
			search_routes.append(dedicated)
		else:
			for palace_god_id: String in PALACE_GOD_IDS:
				search_routes.append(palace_god_id)
	for god_id: String in search_routes:
		var tiers: Array[Dictionary] = _palace_structure_tree_tiers(god_id)
		for tier: Dictionary in tiers:
			var structures: Array = tier.get("structures", []) as Array
			for structure_variant: Variant in structures:
				if not (structure_variant is Dictionary):
					continue
				var structure: Dictionary = structure_variant as Dictionary
				if String(structure.get("id", "")) == structure_id:
					return structure.duplicate(true)
	return {}

func _palace_structure_id_by_name(god_id: String, structure_name: String) -> String:
	var needle: String = structure_name.strip_edges().to_lower()
	if needle == "":
		return ""
	var tiers: Array[Dictionary] = _palace_structure_tree_tiers(god_id)
	for tier: Dictionary in tiers:
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			if String(structure.get("name", "")).strip_edges().to_lower() == needle:
				return String(structure.get("id", ""))
	return ""

func _palace_any_built_in_tier(god_id: String, tier_number: int) -> bool:
	var tiers: Array[Dictionary] = _palace_structure_tree_tiers(god_id)
	for tier: Dictionary in tiers:
		if int(tier.get("tier", 0)) != tier_number:
			continue
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			if _is_palace_structure_built(String(structure.get("id", ""))):
				return true
	return false

func _palace_prerequisite_check(god_id: String, prerequisite_text: String) -> Dictionary:
	var text: String = prerequisite_text.strip_edges()
	if text == "":
		return {"ok": true, "reason": "No prerequisite."}
	if text.begins_with("One Level 1"):
		if _palace_any_built_in_tier(god_id, 1):
			return {"ok": true, "reason": text + " met."}
		return {"ok": false, "reason": "Requires any Level 1 " + _god_display_name(god_id) + " palace structure."}
	if text.find(" or ") >= 0:
		var options: PackedStringArray = text.split(" or ")
		for option: String in options:
			var option_id: String = _palace_structure_id_by_name(god_id, option)
			if option_id != "" and _is_palace_structure_built(option_id):
				return {"ok": true, "reason": text + " met."}
		return {"ok": false, "reason": "Requires one of: " + text + "."}
	var required_id: String = _palace_structure_id_by_name(god_id, text)
	if required_id == "":
		return {"ok": false, "reason": "Unknown prerequisite: " + text + "."}
	if _is_palace_structure_built(required_id):
		return {"ok": true, "reason": text + " met."}
	return {"ok": false, "reason": "Requires " + text + "."}

func _palace_prerequisites_met(structure: Dictionary) -> Dictionary:
	var god_id: String = String(structure.get("god_id", get_palace_dedicated_god()))
	var prerequisites: Array = structure.get("prerequisites", []) as Array
	var blocked: Array[String] = []
	for prereq_variant: Variant in prerequisites:
		var check: Dictionary = _palace_prerequisite_check(god_id, String(prereq_variant))
		if not bool(check.get("ok", false)):
			blocked.append(String(check.get("reason", "Prerequisite not met.")))
	if blocked.is_empty():
		return {"ok": true, "reason": "Prerequisites met."}
	return {"ok": false, "reason": " ".join(blocked)}

func _can_pay_palace_build_cost(cost: Dictionary) -> Dictionary:
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		var needed: float = float(cost[resource_variant])
		var free_value: float = free_stock_after_reserves(resource_id)
		if free_value + 0.001 < needed:
			return {"ok": false, "reason": "Need " + _format_amount(needed - free_value) + " more free " + get_resource_name(resource_id) + " after reserves."}
	return {"ok": true, "reason": "Build cost available."}

func can_build_palace_structure(structure_id: String) -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god()
	if dedicated_god == "":
		return {"ok": false, "reason": "Dedicate the palace before building palace structures."}
	var structure: Dictionary = _palace_structure_by_id(structure_id, dedicated_god)
	if structure.is_empty():
		return {"ok": false, "reason": "Unknown palace structure for the chosen route."}
	if _is_palace_structure_built(structure_id):
		return {"ok": false, "reason": "Already built."}
	var prereq_status: Dictionary = _palace_prerequisites_met(structure)
	if not bool(prereq_status.get("ok", false)):
		return {"ok": false, "reason": String(prereq_status.get("reason", "Prerequisites not met."))}
	var cost_status: Dictionary = _can_pay_palace_build_cost(structure.get("build_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready to build " + String(structure.get("name", "palace structure")) + "."}

func build_palace_structure(structure_id: String) -> Dictionary:
	var status: Dictionary = can_build_palace_structure(structure_id)
	if not bool(status.get("ok", false)):
		last_report.append("Palace structure not built: " + String(status.get("reason", "Blocked.")))
		emit_signal("state_changed")
		return status
	var structure: Dictionary = _palace_structure_by_id(structure_id, get_palace_dedicated_god())
	var cost: Dictionary = structure.get("build_cost", {}) as Dictionary
	for resource_variant: Variant in cost.keys():
		var resource_id: String = String(resource_variant)
		_add_stock(resource_id, -float(cost[resource_variant]))
	palace_built_structures[structure_id] = true
	palace_structure_runtime_statuses.clear()
	last_report.append("Built palace structure: " + String(structure.get("name", structure_id)) + ". It must now be maintained and staffed each Veintena to remain active.")
	emit_signal("state_changed")
	return {"ok": true, "reason": "Built " + String(structure.get("name", structure_id)) + ".", "structure_id": structure_id}


func _palace_built_structure_ids_in_tree_order(god_id: String) -> Array[String]:
	var output: Array[String] = []
	if god_id == "":
		return output
	var tiers: Array[Dictionary] = _palace_structure_tree_tiers(god_id)
	for tier: Dictionary in tiers:
		var structures: Array = tier.get("structures", []) as Array
		for structure_variant: Variant in structures:
			if not (structure_variant is Dictionary):
				continue
			var structure: Dictionary = structure_variant as Dictionary
			var structure_id: String = String(structure.get("id", ""))
			if structure_id != "" and _is_palace_structure_built(structure_id):
				output.append(structure_id)
	return output

func get_palace_staff_capacity() -> Dictionary:
	var result: Dictionary = {}
	for group_id: String in ["tlamacazqueh", "pipiltin", "tolteca"]:
		result[group_id] = _active_population_for_group(group_id)
	return result

func get_palace_structure_operation_preview() -> Dictionary:
	return _resolve_palace_structure_operation(false)

func get_palace_structure_runtime_statuses() -> Dictionary:
	if palace_structure_runtime_statuses.is_empty():
		return (get_palace_structure_operation_preview().get("statuses", {}) as Dictionary).duplicate(true)
	return palace_structure_runtime_statuses.duplicate(true)

func get_active_palace_structure_ids() -> Array[String]:
	var output: Array[String] = []
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for key_variant: Variant in statuses.keys():
		var structure_id: String = String(key_variant)
		var status: Dictionary = statuses[structure_id] as Dictionary
		if bool(status.get("active", false)):
			output.append(structure_id)
	output.sort()
	return output

func get_inactive_palace_structure_ids() -> Array[String]:
	var output: Array[String] = []
	var statuses: Dictionary = get_palace_structure_runtime_statuses()
	for key_variant: Variant in statuses.keys():
		var structure_id: String = String(key_variant)
		var status: Dictionary = statuses[structure_id] as Dictionary
		if bool(status.get("built", false)) and not bool(status.get("active", false)):
			output.append(structure_id)
	output.sort()
	return output

func _resolve_palace_structure_operation(pay_costs: bool) -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god()
	var result: Dictionary = {
		"dedicated_god": dedicated_god,
		"statuses": {},
		"active_structure_ids": [],
		"inactive_structure_ids": [],
		"maintenance_needed": {},
		"maintenance_paid": {},
		"maintenance_shortfalls": {},
		"staff_capacity": get_palace_staff_capacity(),
		"staff_used": {},
		"staff_shortfalls": {},
		"reports": []
	}
	if dedicated_god == "":
		return result
	var temp_stockpile: Dictionary = _copy_stockpile_dictionary(estate_stockpiles)
	var available_staff: Dictionary = get_palace_staff_capacity()
	var structure_ids: Array[String] = _palace_built_structure_ids_in_tree_order(dedicated_god)
	for structure_id: String in structure_ids:
		var structure: Dictionary = _palace_structure_by_id(structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var maintenance: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
		var staff: Dictionary = structure.get("staff_requirement", {}) as Dictionary
		_add_dictionary_amounts(result["maintenance_needed"] as Dictionary, maintenance)
		var missing_parts: Array[String] = []
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			var needed: float = float(maintenance[resource_variant])
			var available: float = float(temp_stockpile.get(resource_id, 0.0))
			if available + 0.001 < needed:
				var shortfall: float = needed - available
				(result["maintenance_shortfalls"] as Dictionary)[resource_id] = float((result["maintenance_shortfalls"] as Dictionary).get(resource_id, 0.0)) + shortfall
				missing_parts.append(_format_amount(shortfall) + " " + get_resource_name(resource_id))
		for staff_variant: Variant in staff.keys():
			var staff_id: String = String(staff_variant)
			var needed_staff: int = int(staff[staff_variant])
			var available_staff_count: int = int(available_staff.get(staff_id, 0))
			if available_staff_count < needed_staff:
				var staff_shortfall: int = needed_staff - available_staff_count
				(result["staff_shortfalls"] as Dictionary)[staff_id] = int((result["staff_shortfalls"] as Dictionary).get(staff_id, 0)) + staff_shortfall
				missing_parts.append(_labour_group_name(staff_id) + " " + str(staff_shortfall))
		var structure_status: Dictionary = {
			"id": structure_id,
			"name": String(structure.get("name", structure_id)),
			"built": true,
			"active": false,
			"inactive_reason": "",
			"maintenance_paid": {},
			"staff_assigned": {}
		}
		if missing_parts.is_empty():
			structure_status["active"] = true
			structure_status["inactive_reason"] = "Active."
			for resource_variant: Variant in maintenance.keys():
				var resource_id: String = String(resource_variant)
				var amount: float = float(maintenance[resource_variant])
				temp_stockpile[resource_id] = float(temp_stockpile.get(resource_id, 0.0)) - amount
				(structure_status["maintenance_paid"] as Dictionary)[resource_id] = amount
				(result["maintenance_paid"] as Dictionary)[resource_id] = float((result["maintenance_paid"] as Dictionary).get(resource_id, 0.0)) + amount
			for staff_variant: Variant in staff.keys():
				var staff_id: String = String(staff_variant)
				var amount: int = int(staff[staff_variant])
				available_staff[staff_id] = int(available_staff.get(staff_id, 0)) - amount
				(structure_status["staff_assigned"] as Dictionary)[staff_id] = amount
				(result["staff_used"] as Dictionary)[staff_id] = int((result["staff_used"] as Dictionary).get(staff_id, 0)) + amount
			(result["active_structure_ids"] as Array).append(structure_id)
			(result["reports"] as Array).append("Palace structure active: " + String(structure.get("name", structure_id)) + ".")
		else:
			structure_status["inactive_reason"] = "Missing: " + ", ".join(missing_parts) + "."
			(result["inactive_structure_ids"] as Array).append(structure_id)
			(result["reports"] as Array).append("Palace structure inactive: " + String(structure.get("name", structure_id)) + " — " + String(structure_status["inactive_reason"]))
		(result["statuses"] as Dictionary)[structure_id] = structure_status
	if pay_costs:
		for resource_variant: Variant in (result["maintenance_paid"] as Dictionary).keys():
			var resource_id: String = String(resource_variant)
			_add_stock(resource_id, -float((result["maintenance_paid"] as Dictionary)[resource_variant]))
	return result

func _pay_palace_maintenance() -> void:
	last_palace_maintenance_report.clear()
	if get_palace_dedicated_god() == "" or get_built_palace_structure_ids().is_empty():
		palace_structure_runtime_statuses.clear()
		return
	var resolution: Dictionary = _resolve_palace_structure_operation(true)
	palace_structure_runtime_statuses = (resolution.get("statuses", {}) as Dictionary).duplicate(true)
	var reports: Array = resolution.get("reports", []) as Array
	if reports.is_empty():
		return
	last_report.append("Palace maintenance resolves.")
	for report_variant: Variant in reports:
		var line: String = String(report_variant)
		last_palace_maintenance_report.append(line)
		last_report.append(line)

func get_palace_total_maintenance() -> Dictionary:
	var result: Dictionary = {}
	var dedicated_god: String = get_palace_dedicated_god()
	if dedicated_god == "":
		return result
	for structure_id: String in get_built_palace_structure_ids():
		var structure: Dictionary = _palace_structure_by_id(structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var maintenance: Dictionary = structure.get("maintenance_cost", {}) as Dictionary
		for resource_variant: Variant in maintenance.keys():
			var resource_id: String = String(resource_variant)
			result[resource_id] = float(result.get(resource_id, 0.0)) + float(maintenance[resource_variant])
	return result

func get_palace_required_staff() -> Dictionary:
	var result: Dictionary = {}
	var dedicated_god: String = get_palace_dedicated_god()
	if dedicated_god == "":
		return result
	for structure_id: String in get_built_palace_structure_ids():
		var structure: Dictionary = _palace_structure_by_id(structure_id, dedicated_god)
		if structure.is_empty():
			continue
		var staff: Dictionary = structure.get("staff_requirement", {}) as Dictionary
		for staff_variant: Variant in staff.keys():
			var staff_id: String = String(staff_variant)
			result[staff_id] = int(result.get(staff_id, 0)) + int(staff[staff_variant])
	return result

func get_palace_level() -> int:
	var dedicated_god: String = get_palace_dedicated_god()
	if dedicated_god == "":
		return 1
	var highest: int = 1
	for structure_id: String in get_built_palace_structure_ids():
		var structure: Dictionary = _palace_structure_by_id(structure_id, dedicated_god)
		if structure.is_empty():
			continue
		highest = maxi(highest, int(structure.get("tier", 1)))
	return highest

func get_palace_dedication_routes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var current_god: String = get_palace_dedicated_god()
	for god_id: String in PALACE_GOD_IDS:
		rows.append({
			"id": god_id,
			"god_id": god_id,
			"god_name": _god_display_name(god_id),
			"route_name": get_palace_route_name(god_id),
			"power_summary": get_palace_route_power_summary(god_id),
			"is_chosen": god_id == current_god,
			"is_available_for_future_dedication": current_god == "",
			"can_dedicate": bool(can_dedicate_palace_to_god(god_id).get("ok", false)),
			"dedication_status": String(can_dedicate_palace_to_god(god_id).get("reason", "")),
			"prototype_status": "Dedication UI active. Palace structures can be built and must be maintained/staffed to stay active; authority effects and Flower War gate reconnection are future patches."
		})
	return rows

func get_palace_summary() -> Dictionary:
	var dedicated_god: String = get_palace_dedicated_god()
	var dedicated: bool = dedicated_god != ""
	var route_name: String = "No dedication"
	var god_name: String = "None"
	if dedicated:
		route_name = get_palace_route_name(dedicated_god)
		god_name = _god_display_name(dedicated_god)
	return {
		"schema_version": "palace_maintenance_active_state_v0_24",
		"palace_level": get_palace_level(),
		"dedicated": dedicated,
		"dedicated_god": dedicated_god,
		"dedicated_god_name": god_name,
		"route_name": route_name,
		"power_summary": get_palace_route_power_summary(dedicated_god),
		"dedication_routes": get_palace_dedication_routes(),
		"structure_tree_shell": get_palace_structure_tree_shell(dedicated_god),
		"built_structures": get_built_palace_structure_ids(),
		"active_structures": get_active_palace_structure_ids(),
		"inactive_structures": get_inactive_palace_structure_ids(),
		"built_structure_count": get_built_palace_structure_ids().size(),
		"active_structure_count": get_active_palace_structure_ids().size(),
		"inactive_structure_count": get_inactive_palace_structure_ids().size(),
		"total_maintenance": get_palace_total_maintenance(),
		"required_staff": get_palace_required_staff(),
		"staff_capacity": get_palace_staff_capacity(),
		"palace_operation_preview": get_palace_structure_operation_preview(),
		"last_palace_maintenance_report": last_palace_maintenance_report.duplicate(),
		"authority_status": "No authority effects are implemented yet. Only active palace structures will count once authority systems are connected.",
		"ruler_demand_status": "Ruler demand UI/mechanics are reserved for a later palace patch.",
		"flower_war_gate_enabled": is_flower_war_palace_gate_enabled(),
		"flower_war_gate_passed": flower_war_palace_gate_passed(),
		"flower_war_gate_status": flower_war_palace_gate_status_text(),
		"implementation_note": "v0.24 pays palace maintenance on Veintena advance and marks built palace structures active or inactive based on upkeep and existing staff. Authority effects, ruler-demand mechanics and Flower War gate reconnection remain future patches."
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

func get_flower_war_defence_strategies() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for strategy_id: String in ["balanced", "depth", "good_offence"]:
		var data: Dictionary = FLOWER_WAR_DEFENCE_STRATEGIES[strategy_id] as Dictionary
		var row: Dictionary = data.duplicate(true)
		row["id"] = strategy_id
		rows.append(row)
	return rows

func start_flower_war_attack_event(option_id: String = "standard", source_id: String = "player", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the attacking Flower War muster later.
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var selected_ids: Array[String] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		if int(row.get("ready_warriors", 0)) > 0:
			selected_ids.append(warband_id)
	var preview: Dictionary = get_flower_war_preview_with_selected_warbands(selected_ids, option_id, "standard")
	return {
		"ok": true,
		"event_type": "flower_war_attack_muster",
		"war_direction": "attack",
		"source_id": source_id,
		"context": context.duplicate(true),
		"option_id": option_id,
		"default_provisioning_id": "standard",
		"default_selected_warbands": selected_ids,
		"preview": preview,
		"message": "Flower War attack event ready. Open the full-screen muster to choose warbands and provisions."
	}

func start_flower_war_defence_event(option_id: String = "standard", source_id: String = "rival", context: Dictionary = {}) -> Dictionary:
	# Event-hook infrastructure only. This does not resolve a Flower War. It returns
	# a standard payload that UI, rivals, calendar, palace or religion systems can
	# use to open the defensive Flower War strategy event later.
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		option_id = "standard"
	var preview: Dictionary = get_flower_war_defence_preview(option_id, "balanced")
	return {
		"ok": true,
		"event_type": "flower_war_defence",
		"war_direction": "defence",
		"source_id": source_id,
		"context": context.duplicate(true),
		"option_id": option_id,
		"default_strategy_id": "balanced",
		"preview": preview,
		"message": "Flower War defence event ready. Open the full-screen defence event to choose a strategy."
	}

func get_flower_war_event_hook_summary() -> Dictionary:
	return {
		"ok": true,
		"attack_hook": "start_flower_war_attack_event(option_id, source_id, context)",
		"defence_hook": "start_flower_war_defence_event(option_id, source_id, context)",
		"possible_sources": ["player", "rival", "calendar", "palace", "religion"],
		"note": "Hooks prepare event payloads only; they do not add rival AI or new combat rules."
	}

func _flower_war_defence_strategy_data(strategy_id: String) -> Dictionary:
	var cleaned: String = strategy_id
	if not FLOWER_WAR_DEFENCE_STRATEGIES.has(cleaned):
		cleaned = "balanced"
	var data: Dictionary = (FLOWER_WAR_DEFENCE_STRATEGIES[cleaned] as Dictionary).duplicate(true)
	data["id"] = cleaned
	return data

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
	var loot_value: float = _flower_war_loot_display_value(loot)
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
		"committed_warriors": warriors_committed,
		"injured_not_fighting": int(get_army_muster_summary().get("injured_not_fighting", 0)),
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_losses": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"loot_value": loot_value,
		"provisioning_cost": provisioning_cost,
		"prestige_pending": true,
		"prestige_text": "Prestige pending calibration."
	}

func can_launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	# Backwards-compatible wrapper. The old generic launch path now sends all
	# ready warbands, so it cannot bypass warband casualties, XP or the
	# Temporary palace gate infrastructure is currently disabled. doctrine_id is ignored because each warband
	# carries its own doctrine once traits/specialisation are connected.
	return can_launch_flower_war_with_all_warbands(option_id, provisioning_id)

func launch_flower_war(option_id: String = "minor", doctrine_id: String = "unspecialised", provisioning_id: String = "standard") -> Dictionary:
	# Backwards-compatible wrapper. All current Flower War launches commit every
	# ready warband together. doctrine_id is ignored for the all-warband launch.
	return launch_flower_war_with_all_warbands(option_id, provisioning_id)

func get_last_flower_war_report() -> Dictionary:
	return last_flower_war_report.duplicate(true)

func get_flower_war_report_archive(limit_count: int = 12) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var copied: Array[Dictionary] = []
	for report_variant: Variant in flower_war_report_archive:
		if report_variant is Dictionary:
			copied.append((report_variant as Dictionary).duplicate(true))
	copied.reverse()
	var limit_value: int = max(0, limit_count)
	for report: Dictionary in copied:
		if limit_value > 0 and output.size() >= limit_value:
			break
		output.append(report)
	return output

func _archive_flower_war_report(report: Dictionary) -> void:
	if report.is_empty() or not bool(report.get("ok", false)):
		return
	var stored: Dictionary = report.duplicate(true)
	stored["archive_index"] = flower_war_report_archive.size() + 1
	stored["archive_veintena"] = current_veintena
	stored["archive_title"] = _flower_war_archive_title(stored)
	flower_war_report_archive.append(stored)
	while flower_war_report_archive.size() > 20:
		flower_war_report_archive.pop_front()

func _flower_war_archive_title(report: Dictionary) -> String:
	var direction: String = String(report.get("war_direction", "attack"))
	var option_name: String = String(report.get("option_name", "Flower War"))
	var result: String = String(report.get("result", "Unknown"))
	if direction == "defence":
		return "Defence — " + option_name + " — " + result
	return "Muster — " + option_name + " — " + result

func get_flower_war_preview_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		provisioning_id = "standard"
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var participants: Array[Dictionary] = []
	var warriors_committed: int = 0
	var weighted_offence: float = 0.0
	var weighted_defence: float = 0.0
	var eagle_warriors: int = 0
	var coyote_warriors: int = 0

	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var ready: int = max(0, int(warband.get("ready_warriors", 0)))
		if ready <= 0:
			continue
		var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
		if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
			doctrine_id = "unspecialised"
		var synced: Dictionary = _sync_warband_progress(warband.duplicate(true))
		var stats: Dictionary = _warband_combat_stats_from_warband(synced)
		participants.append({
			"id": warband_id,
			"name": String(stats.get("name", "Warband")),
			"committed": ready,
			"ready": ready,
			"injured": int(stats.get("injured", 0)),
			"level": int(synced.get("level", 1)),
			"doctrine_id": doctrine_id,
			"doctrine_name": String(stats.get("doctrine_name", doctrine_id.capitalize())),
			"offence": float(stats.get("offence_modifier", 1.0)),
			"defence": float(stats.get("defence_modifier", 1.0)),
			"effective_offence": float(stats.get("effective_offence", 0.0)),
			"effective_defence": float(stats.get("effective_defence", 0.0)),
			"combat_stats": stats
		})
		warriors_committed += ready
		weighted_offence += float(stats.get("effective_offence", 0.0))
		weighted_defence += float(stats.get("effective_defence", 0.0))
		if doctrine_id == "eagle":
			eagle_warriors += ready
		elif doctrine_id == "coyote":
			coyote_warriors += ready

	if warriors_committed <= 0:
		return {"ok": false, "reason": "No ready warriors are assigned to warbands."}

	var enemy_warriors: int = int(option.get("enemy_warriors", option.get("warriors", warriors_committed)))
	var minimum_warriors: int = int(option.get("warriors", enemy_warriors))
	var combat_multiplier: float = float(provisioning.get("combat_multiplier", 1.0))
	var attacker_attack: float = weighted_offence * combat_multiplier
	var defender_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, attacker_attack - defender_defence * 0.55))), 0, enemy_warriors)
	var surviving_defenders: int = max(0, enemy_warriors - defender_casualties)
	var defender_attack: float = float(surviving_defenders) * float(option.get("enemy_offence", 1.0))
	var attacker_defence: float = weighted_defence
	var attacker_casualties: int = clampi(int(round(maxf(0.0, defender_attack - attacker_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = defender_casualties - attacker_casualties
	var result: String = _flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var captives: int = _flower_war_captives_for_all_warbands(result, defender_casualties, warriors_committed, eagle_warriors)
	var loot: Dictionary = _flower_war_loot_for_all_warbands(result, defender_casualties, coyote_warriors, warriors_committed, float(option.get("base_loot_value", 1.2)))
	var loot_value: float = _flower_war_loot_display_value(loot)
	var provisioning_cost: Dictionary = _flower_war_provisioning_cost(warriors_committed, float(provisioning.get("supply_multiplier", 1.0)))
	var xp_gained: int = _flower_war_xp_gain(result, warriors_committed, defender_casualties, captives)

	return {
		"ok": true,
		"all_warbands": true,
		"warband_id": "all_warbands",
		"warband_name": "All Warbands",
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"option_minimum_warriors": minimum_warriors,
		"doctrine_id": "combined",
		"doctrine_name": "Combined Warbands",
		"provisioning_id": provisioning_id,
		"provisioning_name": String(provisioning.get("name", provisioning_id.capitalize())),
		"participants": participants,
		"participating_warband_count": participants.size(),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"injured_not_fighting": int(get_army_muster_summary().get("injured_not_fighting", 0)),
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_losses": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"loot_value": loot_value,
		"provisioning_cost": provisioning_cost,
		"xp_gained": xp_gained,
		"eagle_warriors": eagle_warriors,
		"coyote_warriors": coyote_warriors,
		"prestige_pending": true,
		"prestige_text": "Prestige pending calibration."
	}

func can_launch_flower_war_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not flower_war_palace_gate_passed():
		return {"ok": false, "reason": flower_war_palace_gate_status_text()}
	var preview: Dictionary = get_flower_war_preview_with_all_warbands(option_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var committed: int = int(preview.get("warriors_committed", 0))
	var minimum_warriors: int = int(preview.get("option_minimum_warriors", 0))
	if committed < minimum_warriors:
		return {"ok": false, "reason": "This scale needs at least " + str(minimum_warriors) + " ready warriors across all warbands; only " + str(committed) + " ready."}
	var cost_status: Dictionary = _can_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready. All ready warbands will be committed.", "preview": preview}

func launch_flower_war_with_all_warbands(option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_flower_war_with_all_warbands(option_id, provisioning_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch.")), "warband_id": "all_warbands", "all_warbands": true}
		last_report.append("Flower War not launched: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		emit_signal("state_changed")
		return last_flower_war_report.duplicate(true)

	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_flower_war_preview_with_all_warbands(option_id, provisioning_id)
	_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)

	var participants: Array = preview.get("participants", []) as Array
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("attacker_casualties", 0))
	var captives: int = int(preview.get("captives", 0))
	var xp_total: int = int(preview.get("xp_gained", 0))
	var casualty_alloc: Dictionary = _distribute_integer_by_weights(casualties, participants, "committed", true)
	var xp_alloc: Dictionary = _distribute_integer_by_weights(xp_total, participants, "committed", false)
	var total_injured: int = 0
	var total_dead: int = 0
	var participant_reports: Array[Dictionary] = []
	var level_reports: Array[String] = []

	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		var warband_id: String = String(participant.get("id", ""))
		if not warbands.has(warband_id):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var level_before: int = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
		var committed_i: int = int(participant.get("committed", 0))
		var casualties_i: int = clampi(int(casualty_alloc.get(warband_id, 0)), 0, committed_i)
		var dead_i: int = int(floor(float(casualties_i) * 0.4))
		var injured_i: int = max(0, casualties_i - dead_i)
		var xp_i: int = max(0, int(xp_alloc.get(warband_id, 0)))
		total_injured += injured_i
		total_dead += dead_i
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties_i)
		warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured_i)
		warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead_i)
		warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_i)
		var history: Array = warband.get("battle_history", []) as Array
		history.append({
			"veintena": current_veintena,
			"option_id": option_id,
			"result": String(preview.get("result", "Unknown")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"captives": captives,
			"xp_gained": xp_i,
			"all_warbands": true
		})
		warband["battle_history"] = history
		warbands[warband_id] = _sync_warband_progress(warband)
		var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))
		if level_after > level_before:
			level_reports.append(String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)")
		participant_reports.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"xp_gained": xp_i,
			"level_before": level_before,
			"level_after": level_after
		})

	if total_dead > 0:
		population["yaotequihuaqueh"] = max(0, get_warrior_count() - total_dead)
	if captives > 0:
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
	add_looted_goods_bundle(preview.get("loot", {}) as Dictionary)

	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["all_warbands"] = true
	last_flower_war_report["warband_id"] = "all_warbands"
	last_flower_war_report["warband_name"] = "All Warbands"
	last_flower_war_report["warriors_returned"] = max(0, committed - casualties)
	last_flower_war_report["attacker_injured"] = total_injured
	last_flower_war_report["attacker_dead"] = total_dead
	last_flower_war_report["participant_reports"] = participant_reports
	last_flower_war_report["level_reports"] = level_reports
	_archive_flower_war_report(last_flower_war_report)

	var line: String = "All warbands fought " + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + " across " + str(participant_reports.size()) + " warbands; casualties " + str(casualties) + " (injured " + str(total_injured) + ", dead " + str(total_dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_total) + " shared by participating warbands. Prestige pending calibration."
	if not level_reports.is_empty():
		line += " " + "; ".join(level_reports) + "."
	last_report.append(line)
	emit_signal("state_changed")
	return last_flower_war_report.duplicate(true)


func _selected_warband_ids_or_all_ready(warband_ids: Array) -> Array[String]:
	_ensure_warband_state()
	var output: Array[String] = []
	if warband_ids.is_empty():
		for id_variant: Variant in warbands.keys():
			var id_value: String = String(id_variant)
			var warband: Dictionary = warbands[id_value] as Dictionary
			if int(warband.get("ready_warriors", 0)) > 0:
				output.append(id_value)
		return output
	for id_variant: Variant in warband_ids:
		var id_value: String = String(id_variant)
		if id_value == "" or output.has(id_value):
			continue
		if warbands.has(id_value):
			output.append(id_value)
	return output

func get_flower_war_preview_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	if not FLOWER_WAR_PROVISIONING.has(provisioning_id):
		provisioning_id = "standard"
	var selected_ids: Array[String] = _selected_warband_ids_or_all_ready(warband_ids)
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var provisioning: Dictionary = FLOWER_WAR_PROVISIONING[provisioning_id] as Dictionary
	var participants: Array[Dictionary] = []
	var warriors_committed: int = 0
	var weighted_offence: float = 0.0
	var weighted_defence: float = 0.0
	var eagle_warriors: int = 0
	var coyote_warriors: int = 0

	for warband_id: String in selected_ids:
		if not warbands.has(warband_id):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var ready: int = max(0, int(warband.get("ready_warriors", 0)))
		if ready <= 0:
			continue
		var doctrine_id: String = String(warband.get("doctrine", "unspecialised"))
		if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
			doctrine_id = "unspecialised"
		var synced: Dictionary = _sync_warband_progress(warband.duplicate(true))
		var stats: Dictionary = _warband_combat_stats_from_warband(synced)
		participants.append({
			"id": warband_id,
			"name": String(stats.get("name", "Warband")),
			"committed": ready,
			"ready": ready,
			"injured": int(stats.get("injured", 0)),
			"level": int(synced.get("level", 1)),
			"doctrine_id": doctrine_id,
			"doctrine_name": String(stats.get("doctrine_name", doctrine_id.capitalize())),
			"offence": float(stats.get("offence_modifier", 1.0)),
			"defence": float(stats.get("defence_modifier", 1.0)),
			"effective_offence": float(stats.get("effective_offence", 0.0)),
			"effective_defence": float(stats.get("effective_defence", 0.0)),
			"combat_stats": stats
		})
		warriors_committed += ready
		weighted_offence += float(stats.get("effective_offence", 0.0))
		weighted_defence += float(stats.get("effective_defence", 0.0))
		if doctrine_id == "eagle":
			eagle_warriors += ready
		elif doctrine_id == "coyote":
			coyote_warriors += ready

	if warriors_committed <= 0:
		return {"ok": false, "reason": "No selected warbands have ready warriors."}

	var enemy_warriors: int = int(option.get("enemy_warriors", option.get("warriors", warriors_committed)))
	var minimum_warriors: int = int(option.get("warriors", enemy_warriors))
	var combat_multiplier: float = float(provisioning.get("combat_multiplier", 1.0))
	var attacker_attack: float = weighted_offence * combat_multiplier
	var defender_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, attacker_attack - defender_defence * 0.55))), 0, enemy_warriors)
	var surviving_defenders: int = max(0, enemy_warriors - defender_casualties)
	var defender_attack: float = float(surviving_defenders) * float(option.get("enemy_offence", 1.0))
	var attacker_defence: float = weighted_defence
	var attacker_casualties: int = clampi(int(round(maxf(0.0, defender_attack - attacker_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = defender_casualties - attacker_casualties
	var result: String = _flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var captives: int = _flower_war_captives_for_all_warbands(result, defender_casualties, warriors_committed, eagle_warriors)
	var loot: Dictionary = _flower_war_loot_for_all_warbands(result, defender_casualties, coyote_warriors, warriors_committed, float(option.get("base_loot_value", 1.2)))
	var loot_value: float = _flower_war_loot_display_value(loot)
	var provisioning_cost: Dictionary = _flower_war_provisioning_cost(warriors_committed, float(provisioning.get("supply_multiplier", 1.0)))
	var xp_gained: int = _flower_war_xp_gain(result, warriors_committed, defender_casualties, captives)

	return {
		"ok": true,
		"event_type": "flower_war_attack",
		"selected_warbands": true,
		"selected_warband_ids": selected_ids.duplicate(),
		"all_warbands": false,
		"warband_id": "selected_warbands",
		"warband_name": "Selected Warbands",
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"option_minimum_warriors": minimum_warriors,
		"doctrine_id": "combined",
		"doctrine_name": "Combined Warbands",
		"provisioning_id": provisioning_id,
		"provisioning_name": String(provisioning.get("name", provisioning_id.capitalize())),
		"participants": participants,
		"participating_warband_count": participants.size(),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"injured_not_fighting": int(get_army_muster_summary().get("injured_not_fighting", 0)),
		"enemy_warriors": enemy_warriors,
		"attacker_attack": attacker_attack,
		"attacker_defence": attacker_defence,
		"defender_casualties": defender_casualties,
		"attacker_casualties": attacker_casualties,
		"attacker_losses": attacker_casualties,
		"attacker_injured": int(ceil(float(attacker_casualties) * 0.6)),
		"attacker_dead": int(floor(float(attacker_casualties) * 0.4)),
		"result": result,
		"captives": captives,
		"loot": loot,
		"loot_value": loot_value,
		"provisioning_cost": provisioning_cost,
		"xp_gained": xp_gained,
		"eagle_warriors": eagle_warriors,
		"coyote_warriors": coyote_warriors,
		"prestige_pending": true,
		"prestige_text": "Prestige pending calibration."
	}

func can_launch_flower_war_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not flower_war_palace_gate_passed():
		return {"ok": false, "reason": flower_war_palace_gate_status_text()}
	var preview: Dictionary = get_flower_war_preview_with_selected_warbands(warband_ids, option_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var committed: int = int(preview.get("warriors_committed", 0))
	var minimum_warriors: int = int(preview.get("option_minimum_warriors", 0))
	if committed < minimum_warriors:
		return {"ok": false, "reason": "This scale needs at least " + str(minimum_warriors) + " ready warriors; selected warbands provide " + str(committed) + "."}
	var cost_status: Dictionary = _can_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready. Selected warbands will be committed.", "preview": preview}

func launch_flower_war_with_selected_warbands(warband_ids: Array, option_id: String = "minor", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_flower_war_with_selected_warbands(warband_ids, option_id, provisioning_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch.")), "warband_id": "selected_warbands", "selected_warbands": true}
		last_report.append("Flower War not launched: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		emit_signal("state_changed")
		return last_flower_war_report.duplicate(true)

	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_flower_war_preview_with_selected_warbands(warband_ids, option_id, provisioning_id)
	_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)

	var participants: Array = preview.get("participants", []) as Array
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("attacker_casualties", 0))
	var captives: int = int(preview.get("captives", 0))
	var xp_total: int = int(preview.get("xp_gained", 0))
	var casualty_alloc: Dictionary = _distribute_integer_by_weights(casualties, participants, "committed", true)
	var xp_alloc: Dictionary = _distribute_integer_by_weights(xp_total, participants, "committed", false)
	var total_injured: int = 0
	var total_dead: int = 0
	var participant_reports: Array[Dictionary] = []
	var level_reports: Array[String] = []

	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		var warband_id: String = String(participant.get("id", ""))
		if not warbands.has(warband_id):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var level_before: int = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
		var committed_i: int = int(participant.get("committed", 0))
		var casualties_i: int = clampi(int(casualty_alloc.get(warband_id, 0)), 0, committed_i)
		var dead_i: int = int(floor(float(casualties_i) * 0.4))
		var injured_i: int = max(0, casualties_i - dead_i)
		var xp_i: int = max(0, int(xp_alloc.get(warband_id, 0)))
		total_injured += injured_i
		total_dead += dead_i
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties_i)
		warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured_i)
		warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead_i)
		warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_i)
		var history: Array = warband.get("battle_history", []) as Array
		history.append({
			"veintena": current_veintena,
			"option_id": option_id,
			"provisioning_id": provisioning_id,
			"result": String(preview.get("result", "Unknown")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"captives": captives,
			"xp_gained": xp_i,
			"selected_warbands": true
		})
		warband["battle_history"] = history
		warbands[warband_id] = _sync_warband_progress(warband)
		var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))
		if level_after > level_before:
			level_reports.append(String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)")
		participant_reports.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": committed_i,
			"sent": committed_i,
			"returned_ready": max(0, committed_i - casualties_i),
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"xp_gained": xp_i,
			"level_before": level_before,
			"level_after": level_after
		})

	if total_dead > 0:
		population["yaotequihuaqueh"] = max(0, get_warrior_count() - total_dead)
	if captives > 0:
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
	add_looted_goods_bundle(preview.get("loot", {}) as Dictionary)

	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["event_type"] = "flower_war_return"
	last_flower_war_report["selected_warbands"] = true
	last_flower_war_report["all_warbands"] = false
	last_flower_war_report["warband_id"] = "selected_warbands"
	last_flower_war_report["warband_name"] = "Selected Warbands"
	last_flower_war_report["warriors_returned"] = max(0, committed - casualties)
	last_flower_war_report["attacker_injured"] = total_injured
	last_flower_war_report["attacker_dead"] = total_dead
	last_flower_war_report["participant_reports"] = participant_reports
	last_flower_war_report["level_reports"] = level_reports
	_archive_flower_war_report(last_flower_war_report)

	var line: String = "Selected warbands fought " + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + " across " + str(participant_reports.size()) + " warbands; casualties " + str(casualties) + " (injured " + str(total_injured) + ", dead " + str(total_dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_total) + " shared by participating warbands. Prestige pending calibration."
	if not level_reports.is_empty():
		line += " " + "; ".join(level_reports) + "."
	last_report.append(line)
	emit_signal("state_changed")
	return last_flower_war_report.duplicate(true)

func get_flower_war_defence_preview(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	_ensure_warband_state()
	if not FLOWER_WAR_OPTIONS.has(option_id):
		return {"ok": false, "reason": "Unknown Flower War option."}
	var option: Dictionary = FLOWER_WAR_OPTIONS[option_id] as Dictionary
	var strategy: Dictionary = _flower_war_defence_strategy_data(strategy_id)
	var participants: Array[Dictionary] = []
	var warriors_committed: int = 0
	var weighted_offence: float = 0.0
	var weighted_defence: float = 0.0
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = warband
		var stats: Dictionary = _warband_combat_stats_from_warband(warband)
		var ready: int = int(stats.get("ready", 0))
		if ready <= 0:
			continue
		participants.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": ready,
			"ready": ready,
			"doctrine": String(warband.get("doctrine", "unspecialised")),
			"doctrine_name": String(stats.get("doctrine_name", "Unspecialised")),
			"effective_offence": float(stats.get("effective_offence", 0.0)),
			"effective_defence": float(stats.get("effective_defence", 0.0))
		})
		warriors_committed += ready
		weighted_offence += float(stats.get("effective_offence", 0.0))
		weighted_defence += float(stats.get("effective_defence", 0.0))
	if warriors_committed <= 0:
		return {"ok": false, "reason": "No ready warbands can defend."}
	var enemy_warriors: int = int(option.get("enemy_warriors", option.get("warriors", 0)))
	var player_attack: float = weighted_offence * float(strategy.get("offence_multiplier", 1.0))
	var player_defence: float = weighted_defence * float(strategy.get("defence_multiplier", 1.0))
	var enemy_attack: float = float(enemy_warriors) * float(option.get("enemy_offence", 1.0))
	var enemy_defence: float = float(enemy_warriors) * float(option.get("enemy_defence", 1.0))
	var enemy_casualties: int = clampi(int(round(maxf(0.0, player_attack - enemy_defence * 0.55))), 0, enemy_warriors)
	var surviving_enemy: int = max(0, enemy_warriors - enemy_casualties)
	var returning_enemy_attack: float = float(surviving_enemy) * float(option.get("enemy_offence", 1.0))
	var defender_casualties: int = clampi(int(round(maxf(0.0, returning_enemy_attack - player_defence * 0.55))), 0, warriors_committed)
	var net_damage: int = enemy_casualties - defender_casualties
	var result: String = _flower_war_result_label(net_damage, warriors_committed, enemy_warriors)
	var xp_gained: int = _flower_war_xp_gain(result, warriors_committed, enemy_casualties, 0)
	return {
		"ok": true,
		"event_type": "flower_war_defence_preview",
		"war_direction": "defence",
		"option_id": option_id,
		"option_name": String(option.get("name", option_id.capitalize())),
		"option_minimum_warriors": int(option.get("warriors", 0)),
		"defence_strategy_id": String(strategy.get("id", "balanced")),
		"defence_strategy_name": String(strategy.get("name", "Balanced Defence")),
		"defence_strategy_description": String(strategy.get("description", "")),
		"offence_multiplier": float(strategy.get("offence_multiplier", 1.0)),
		"defence_multiplier": float(strategy.get("defence_multiplier", 1.0)),
		"participants": participants,
		"participating_warband_count": participants.size(),
		"warriors_committed": warriors_committed,
		"committed_warriors": warriors_committed,
		"enemy_warriors": enemy_warriors,
		"attacker_attack": enemy_attack,
		"attacker_defence": enemy_defence,
		"defender_attack": player_attack,
		"defender_defence": player_defence,
		"enemy_casualties": enemy_casualties,
		"defender_casualties": defender_casualties,
		"attacker_casualties": defender_casualties,
		"attacker_losses": defender_casualties,
		"attacker_injured": int(ceil(float(defender_casualties) * 0.6)),
		"attacker_dead": int(floor(float(defender_casualties) * 0.4)),
		"result": result,
		"captives": 0,
		"loot": {},
		"loot_value": 0.0,
		"provisioning_cost": {},
		"xp_gained": xp_gained,
		"prestige_pending": true,
		"prestige_text": "Prestige pending calibration. Defensive rewards are not balanced yet."
	}

func can_resolve_flower_war_defence(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	_ensure_warband_state()
	var preview: Dictionary = get_flower_war_defence_preview(option_id, strategy_id)
	if not bool(preview.get("ok", false)):
		return preview
	var committed: int = int(preview.get("warriors_committed", 0))
	var minimum_warriors: int = int(preview.get("option_minimum_warriors", 0))
	if committed < minimum_warriors:
		return {"ok": false, "reason": "This defence needs at least " + str(minimum_warriors) + " ready warriors; defending warbands provide " + str(committed) + "."}
	return {"ok": true, "reason": "Ready. Warbands will defend the estate.", "preview": preview}

func resolve_flower_war_defence(option_id: String = "standard", strategy_id: String = "balanced") -> Dictionary:
	var status: Dictionary = can_resolve_flower_war_defence(option_id, strategy_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War defence cannot resolve.")), "war_direction": "defence"}
		last_report.append("Flower War defence not resolved: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		emit_signal("state_changed")
		return last_flower_war_report.duplicate(true)

	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_flower_war_defence_preview(option_id, strategy_id)
	var participants: Array = preview.get("participants", []) as Array
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("defender_casualties", preview.get("attacker_casualties", 0)))
	var xp_total: int = int(preview.get("xp_gained", 0))
	var casualty_alloc: Dictionary = _distribute_integer_by_weights(casualties, participants, "committed", true)
	var xp_alloc: Dictionary = _distribute_integer_by_weights(xp_total, participants, "committed", false)
	var total_injured: int = 0
	var total_dead: int = 0
	var participant_reports: Array[Dictionary] = []
	var level_reports: Array[String] = []

	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		var warband_id: String = String(participant.get("id", ""))
		if not warbands.has(warband_id):
			continue
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var level_before: int = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
		var committed_i: int = int(participant.get("committed", 0))
		var casualties_i: int = clampi(int(casualty_alloc.get(warband_id, 0)), 0, committed_i)
		var dead_i: int = int(floor(float(casualties_i) * 0.4))
		var injured_i: int = max(0, casualties_i - dead_i)
		var xp_i: int = max(0, int(xp_alloc.get(warband_id, 0)))
		total_injured += injured_i
		total_dead += dead_i
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties_i)
		warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured_i)
		warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead_i)
		warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_i)
		var history: Array = warband.get("battle_history", []) as Array
		history.append({
			"veintena": current_veintena,
			"option_id": option_id,
			"strategy_id": strategy_id,
			"result": String(preview.get("result", "Unknown")),
			"committed": committed_i,
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"captives": 0,
			"xp_gained": xp_i,
			"defensive": true
		})
		warband["battle_history"] = history
		warbands[warband_id] = _sync_warband_progress(warband)
		var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))
		if level_after > level_before:
			level_reports.append(String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)")
		participant_reports.append({
			"id": warband_id,
			"name": String(warband.get("name", "Warband")),
			"committed": committed_i,
			"sent": committed_i,
			"returned_ready": max(0, committed_i - casualties_i),
			"casualties": casualties_i,
			"injured": injured_i,
			"dead": dead_i,
			"xp_gained": xp_i,
			"level_before": level_before,
			"level_after": level_after
		})

	if total_dead > 0:
		population["yaotequihuaqueh"] = max(0, get_warrior_count() - total_dead)

	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["event_type"] = "flower_war_return"
	last_flower_war_report["war_direction"] = "defence"
	last_flower_war_report["warband_id"] = "defending_warbands"
	last_flower_war_report["warband_name"] = "Defending Warbands"
	last_flower_war_report["warriors_returned"] = max(0, committed - casualties)
	last_flower_war_report["attacker_injured"] = total_injured
	last_flower_war_report["attacker_dead"] = total_dead
	last_flower_war_report["participant_reports"] = participant_reports
	last_flower_war_report["level_reports"] = level_reports
	_archive_flower_war_report(last_flower_war_report)

	var line: String = "Defending warbands resolved " + String(preview.get("option_name", "Flower War")) + " using " + String(preview.get("defence_strategy_name", "Balanced Defence")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors defending " + str(committed) + " across " + str(participant_reports.size()) + " warbands; casualties " + str(casualties) + " (injured " + str(total_injured) + ", dead " + str(total_dead) + "). Enemy casualties " + str(int(preview.get("enemy_casualties", 0))) + ". XP +" + str(xp_total) + " shared by defending warbands. Prestige pending calibration."
	if not level_reports.is_empty():
		line += " " + "; ".join(level_reports) + "."
	last_report.append(line)
	emit_signal("state_changed")
	return last_flower_war_report.duplicate(true)

func _flower_war_captives_for_all_warbands(result: String, defender_casualties: int, warriors_committed: int, eagle_warriors: int) -> int:
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
	if eagle_warriors > 0:
		rate += float(eagle_warriors) * 0.02
	var raw: float = float(defender_casualties) * rate
	if raw > 0.0:
		return mini(defender_casualties, max(1, int(ceil(raw))))
	return 0

func _flower_war_loot_for_all_warbands(result: String, defender_casualties: int, coyote_warriors: int, warriors_committed: int, base_loot_value: float) -> Dictionary:
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
	if coyote_warriors > 0 and warriors_committed > 0:
		multiplier *= 1.0 + 0.5 * (float(coyote_warriors) / float(warriors_committed))
	var units: float = maxf(0.0, float(defender_casualties) * base_loot_value * multiplier)
	if units <= 0.0:
		return {}
	return {"maize": snappedf(units * 0.50, 0.01), "wood": snappedf(units * 0.25, 0.01), "cloth": snappedf(units * 0.15, 0.01), "obsidian": snappedf(units * 0.10, 0.01)}

func _distribute_integer_by_weights(total: int, participants: Array, weight_key: String = "committed", cap_by_weight: bool = false) -> Dictionary:
	var result: Dictionary = {}
	if total <= 0:
		return result
	var total_weight: int = 0
	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		total_weight += max(0, int(participant.get(weight_key, 0)))
	if total_weight <= 0:
		return result
	var remaining: int = total
	var remainders: Array[Dictionary] = []
	for participant_variant: Variant in participants:
		var participant: Dictionary = participant_variant as Dictionary
		var participant_id: String = String(participant.get("id", ""))
		var weight: int = max(0, int(participant.get(weight_key, 0)))
		if participant_id == "" or weight <= 0:
			continue
		var raw: float = float(total) * float(weight) / float(total_weight)
		var base: int = int(floor(raw))
		var cap_value: int = total
		if cap_by_weight:
			cap_value = weight
		base = mini(base, cap_value)
		result[participant_id] = base
		remaining -= base
		remainders.append({"id": participant_id, "fraction": raw - float(base), "cap": cap_value})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("fraction", 0.0)) > float(b.get("fraction", 0.0))
	)
	var guard: int = 0
	while remaining > 0 and guard < 1000:
		var allocated: bool = false
		for item: Dictionary in remainders:
			if remaining <= 0:
				break
			var participant_id: String = String(item.get("id", ""))
			var cap_value: int = int(item.get("cap", total))
			if int(result.get(participant_id, 0)) < cap_value:
				result[participant_id] = int(result.get(participant_id, 0)) + 1
				remaining -= 1
				allocated = true
		if not allocated:
			break
		guard += 1
	return result

func get_flower_war_preview_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var resolved_doctrine: String = doctrine_id
	if resolved_doctrine == "" or resolved_doctrine == "warband":
		resolved_doctrine = String(warband.get("doctrine", "unspecialised"))
	var preview: Dictionary = get_flower_war_preview(option_id, resolved_doctrine, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	preview["warband_id"] = warband_id
	preview["warband_name"] = String(warband.get("name", "Warband"))
	preview["warband_ready"] = int(warband.get("ready_warriors", 0))
	preview["warband_injured"] = int(warband.get("injured_warriors", 0))
	preview["warband_level"] = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
	preview["xp_gained"] = _flower_war_xp_gain(String(preview.get("result", "Stalemate")), int(preview.get("warriors_committed", 0)), int(preview.get("defender_casualties", 0)), int(preview.get("captives", 0)))
	return preview

func can_launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	_ensure_warband_state()
	if not flower_war_palace_gate_passed():
		return {"ok": false, "reason": flower_war_palace_gate_status_text()}
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var preview: Dictionary = get_flower_war_preview_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(preview.get("ok", false)):
		return preview
	var needed_warriors: int = int(preview.get("warriors_committed", 0))
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var ready: int = int(warband.get("ready_warriors", 0))
	if ready < needed_warriors:
		return {"ok": false, "reason": String(warband.get("name", "Warband")) + " needs " + str(needed_warriors) + " ready warriors; only " + str(ready) + " ready."}
	var cost_status: Dictionary = _can_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	if not bool(cost_status.get("ok", false)):
		return cost_status
	return {"ok": true, "reason": "Ready.", "preview": preview}

func launch_flower_war_with_warband(warband_id: String, option_id: String = "minor", doctrine_id: String = "", provisioning_id: String = "standard") -> Dictionary:
	var status: Dictionary = can_launch_flower_war_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	if not bool(status.get("ok", false)):
		last_flower_war_report = {"ok": false, "reason": String(status.get("reason", "Flower War cannot launch.")), "warband_id": warband_id}
		last_report.append("Flower War not launched: " + String(last_flower_war_report.get("reason", "blocked")) + ".")
		emit_signal("state_changed")
		return last_flower_war_report.duplicate(true)
	var preview: Dictionary = status.get("preview", {}) as Dictionary
	if preview.is_empty():
		preview = get_flower_war_preview_with_warband(warband_id, option_id, doctrine_id, provisioning_id)
	_pay_free_stock(preview.get("provisioning_cost", {}) as Dictionary)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var level_before: int = int(_sync_warband_progress(warband.duplicate(true)).get("level", 1))
	var committed: int = int(preview.get("warriors_committed", 0))
	var casualties: int = int(preview.get("attacker_casualties", 0))
	var injured: int = int(preview.get("attacker_injured", 0))
	var dead: int = int(preview.get("attacker_dead", 0))
	var captives: int = int(preview.get("captives", 0))
	var xp_gain: int = int(preview.get("xp_gained", 0))

	warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - casualties)
	warband["injured_warriors"] = max(0, int(warband.get("injured_warriors", 0)) + injured)
	warband["dead_total"] = max(0, int(warband.get("dead_total", 0)) + dead)
	warband["xp"] = max(0, int(warband.get("xp", 0)) + xp_gain)
	var history: Array = warband.get("battle_history", []) as Array
	history.append({
		"veintena": current_veintena,
		"option_id": option_id,
		"result": String(preview.get("result", "Unknown")),
		"committed": committed,
		"casualties": casualties,
		"injured": injured,
		"dead": dead,
		"captives": captives,
		"xp_gained": xp_gain
	})
	warband["battle_history"] = history
	warbands[warband_id] = _sync_warband_progress(warband)
	var level_after: int = int((warbands[warband_id] as Dictionary).get("level", level_before))

	if dead > 0:
		population["yaotequihuaqueh"] = max(0, get_warrior_count() - dead)
	if captives > 0:
		estate_stockpiles["captives"] = float(estate_stockpiles.get("captives", 0.0)) + float(captives)
	add_looted_goods_bundle(preview.get("loot", {}) as Dictionary)

	last_flower_war_report = preview.duplicate(true)
	last_flower_war_report["ok"] = true
	last_flower_war_report["warband_id"] = warband_id
	last_flower_war_report["warband_name"] = String(warband.get("name", "Warband"))
	last_flower_war_report["warriors_returned"] = max(0, committed - casualties)
	last_flower_war_report["xp_gained"] = xp_gain
	last_flower_war_report["level_before"] = level_before
	last_flower_war_report["level_after"] = level_after

	var line: String = String(warband.get("name", "Warband")) + " fought " + String(preview.get("option_name", "Flower War")) + ": " + String(preview.get("result", "Unknown")) + ". Warriors committed " + str(committed) + "; casualties " + str(casualties) + " (injured " + str(injured) + ", dead " + str(dead) + "). Captives gained " + str(captives) + ". XP +" + str(xp_gain) + ". Prestige pending calibration."
	if level_after > level_before:
		line += " " + String(warband.get("name", "Warband")) + " reached Level " + str(level_after) + " and gained " + str(max(0, level_after - level_before)) + " skill point(s)."
	last_report.append(line)
	emit_signal("state_changed")
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

func _flower_war_loot_display_value(loot: Dictionary) -> float:
	var total: float = 0.0
	for resource_variant: Variant in loot.keys():
		var resource_id: String = String(resource_variant)
		var base_value: float = 1.0
		if resources.has(resource_id):
			var resource_data: Dictionary = resources[resource_id] as Dictionary
			base_value = float(resource_data.get("base_value", 1.0))
		total += float(loot[resource_variant]) * base_value
	return snappedf(total, 0.01)

func _flower_war_xp_gain(result: String, warriors_committed: int, defender_casualties: int, captives: int) -> int:
	var result_bonus: int = 0
	match result:
		"Crushing Victory":
			result_bonus = 8
		"Victory":
			result_bonus = 5
		"Marginal Victory":
			result_bonus = 3
		"Stalemate":
			result_bonus = 2
		"Defeat":
			result_bonus = 1
		_:
			result_bonus = 1
	return max(1, warriors_committed + defender_casualties * 2 + captives * 4 + result_bonus)

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


# -----------------------------------------------------------------------------
# Warband Roster Backend v0.2 — canonical infrastructure, no launch mutation yet
# -----------------------------------------------------------------------------

func _ensure_warband_state() -> void:
	if not warbands.is_empty():
		return
	var total_warriors: int = get_warrior_count()
	var first: int = int(ceil(float(total_warriors) / 3.0))
	var second: int = int(floor(float(total_warriors) / 3.0))
	var third: int = max(0, total_warriors - first - second)
	warbands["first_warband"] = _make_starting_warband("first_warband", "First Warband", "Household Captain", first)
	warbands["second_warband"] = _make_starting_warband("second_warband", "Second Warband", "Senior Warrior", second)
	warbands["third_warband"] = _make_starting_warband("third_warband", "Third Warband", "Young Captain", third)

func _make_starting_warband(warband_id: String, name: String, commander: String, ready_warriors: int) -> Dictionary:
	return {
		"id": warband_id,
		"name": name,
		"commander": commander,
		"doctrine": "unspecialised",
		"ready_warriors": max(0, ready_warriors),
		"injured_warriors": 0,
		"dead_total": 0,
		"xp": 0,
		"level": 1,
		"total_trait_points": 0,
		"spent_trait_points": 0,
		"trait_points": 0,
		"purchased_traits": ["household_muster"],
		"traits": ["household_muster"],
		"skill_effects": {},
		"specialisation": {},
		"battle_history": []
	}

func _sync_warband_progress(warband: Dictionary) -> Dictionary:
	var xp: int = max(0, int(warband.get("xp", 0)))
	var level: int = _warband_level_for_xp(xp)
	warband["xp"] = xp
	warband["level"] = level
	warband["xp_to_next"] = _warband_xp_to_next(level)
	warband["xp_current_level_start"] = _warband_xp_required_for_level(level)
	warband["xp_next_level"] = _warband_xp_required_for_level(level + 1)
	warband["xp_in_level"] = xp - int(warband.get("xp_current_level_start", 0))
	warband["xp_needed_in_level"] = max(1, int(warband.get("xp_next_level", 0)) - int(warband.get("xp_current_level_start", 0)))
	warband["xp_progress"] = clampf(float(warband.get("xp_in_level", 0)) / float(warband.get("xp_needed_in_level", 1)), 0.0, 1.0)
	warband = _ensure_warband_skill_defaults(warband)
	warband["total_trait_points"] = max(0, level - 1)
	warband["spent_trait_points"] = _warband_spent_trait_points(warband)
	warband["trait_points"] = max(0, int(warband.get("total_trait_points", 0)) - int(warband.get("spent_trait_points", 0)))
	warband["skill_effects"] = _warband_trait_effect_totals_from_purchased(_warband_purchased_trait_ids(warband))
	warband["specialisation"] = _warband_specialisation_summary_for_warband(warband)
	# Canonical rule: the Skill Web specialism is the warband's doctrine identity.
	# Unspecialised warbands remain doctrine-neutral until a specialism gateway is bought.
	warband["doctrine"] = _warband_doctrine_from_specialisation(warband)
	return warband

func _warband_xp_required_for_level(level: int) -> int:
	var target: int = max(1, level)
	return (target - 1) * target * 5

func _warband_xp_to_next(level: int) -> int:
	return _warband_xp_required_for_level(max(1, level) + 1)

func _warband_level_for_xp(xp: int) -> int:
	var level: int = 1
	while xp >= _warband_xp_required_for_level(level + 1):
		level += 1
	return level

func _warband_spent_trait_points(warband: Dictionary) -> int:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var spent: int = 0
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		spent += max(0, int(node.get("cost", 0)))
	return spent

func _warband_doctrine_from_specialisation(warband: Dictionary) -> String:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if FLOWER_WAR_DOCTRINES.has(chosen_cluster):
		return chosen_cluster
	return "unspecialised"


func recover_injured_warriors_now() -> Dictionary:
	# Test/dev helper. Normal recovery happens automatically when the Veintena advances.
	_ensure_warband_state()
	var report: Dictionary = _recover_injured_warriors()
	emit_signal("state_changed")
	return report

func _recover_injured_warriors() -> Dictionary:
	_ensure_warband_state()
	var recovered_total: int = 0
	var lines: Array[String] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var warband: Dictionary = warbands[warband_id] as Dictionary
		var injured: int = max(0, int(warband.get("injured_warriors", 0)))
		if injured <= 0:
			continue
		warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0))) + injured
		warband["injured_warriors"] = 0
		warbands[warband_id] = _sync_warband_progress(warband)
		recovered_total += injured
		var name: String = String(warband.get("name", "Warband"))
		lines.append(str(injured) + " injured warrior" + ("s" if injured != 1 else "") + " returned to " + name + ".")
	if recovered_total > 0:
		last_report.append("Warband recovery: " + " ".join(lines))
	return {"recovered": recovered_total, "lines": lines}

func get_warband_rows() -> Array[Dictionary]:
	_ensure_warband_state()
	var rows: Array[Dictionary] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var combat_stats: Dictionary = _warband_combat_stats_from_warband(row)
		row["specialisation_name"] = String(spec.get("name", "None"))
		row["doctrine_name"] = String(combat_stats.get("doctrine_name", _warband_doctrine_name(String(row.get("doctrine", "unspecialised")))))
		row["combat_stats"] = combat_stats
		row["offence_modifier"] = float(combat_stats.get("offence_modifier", 1.0))
		row["defence_modifier"] = float(combat_stats.get("defence_modifier", 1.0))
		row["effective_offence"] = float(combat_stats.get("effective_offence", 0.0))
		row["effective_defence"] = float(combat_stats.get("effective_defence", 0.0))
		row["ready"] = int(row.get("ready_warriors", 0))
		row["injured"] = int(row.get("injured_warriors", 0))
		row["total"] = int(row.get("ready_warriors", 0)) + int(row.get("injured_warriors", 0))
		row["warriors"] = int(row.get("ready_warriors", 0))
		row["total_warriors"] = int(row.get("total", 0))
		row["can_launch"] = int(row.get("ready_warriors", 0)) > 0
		row["injured_recovery_text"] = "Injured warriors recover on the next Veintena advance." if int(row.get("injured_warriors", 0)) > 0 else "No injured warriors awaiting recovery."
		rows.append(row)
	return rows

func get_warband_by_id(warband_id: String) -> Dictionary:
	_ensure_warband_state()
	if warbands.has(warband_id):
		var row: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var combat_stats: Dictionary = _warband_combat_stats_from_warband(row)
		row["specialisation_name"] = String(spec.get("name", "None"))
		row["doctrine_name"] = String(combat_stats.get("doctrine_name", _warband_doctrine_name(String(row.get("doctrine", "unspecialised")))))
		row["combat_stats"] = combat_stats
		row["offence_modifier"] = float(combat_stats.get("offence_modifier", 1.0))
		row["defence_modifier"] = float(combat_stats.get("defence_modifier", 1.0))
		row["effective_offence"] = float(combat_stats.get("effective_offence", 0.0))
		row["effective_defence"] = float(combat_stats.get("effective_defence", 0.0))
		return row
	return {}

func can_rename_warband(warband_id: String, new_name: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var cleaned: String = new_name.strip_edges()
	if cleaned == "":
		return {"ok": false, "reason": "Warband name cannot be empty."}
	if cleaned.length() > 32:
		return {"ok": false, "reason": "Warband name must be 32 characters or fewer."}
	for other_id_variant: Variant in warbands.keys():
		var other_id: String = String(other_id_variant)
		if other_id == warband_id:
			continue
		var other: Dictionary = warbands[other_id] as Dictionary
		if String(other.get("name", "")).strip_edges().to_lower() == cleaned.to_lower():
			return {"ok": false, "reason": "Another warband already uses that name."}
	return {"ok": true, "reason": "Ready.", "clean_name": cleaned}

func rename_warband(warband_id: String, new_name: String) -> Dictionary:
	var status: Dictionary = can_rename_warband(warband_id, new_name)
	if not bool(status.get("ok", false)):
		last_report.append("Warband rename failed: " + String(status.get("reason", "Unknown reason.")))
		emit_signal("state_changed")
		return status
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var old_name: String = String(warband.get("name", "Warband"))
	var clean_name: String = String(status.get("clean_name", new_name.strip_edges()))
	warband["name"] = clean_name
	warbands[warband_id] = _sync_warband_progress(warband)
	last_report.append(old_name + " renamed to " + clean_name + ".")
	emit_signal("state_changed")
	return {"ok": true, "reason": "Warband renamed.", "warband_id": warband_id, "name": clean_name}

func can_set_warband_name(warband_id: String, new_name: String) -> Dictionary:
	return can_rename_warband(warband_id, new_name)

func set_warband_name(warband_id: String, new_name: String) -> Dictionary:
	return rename_warband(warband_id, new_name)

func get_primary_warband() -> Dictionary:
	return get_warband_by_id("first_warband")

func get_unassigned_warrior_pool() -> int:
	return _unassigned_warrior_pool()

func can_create_warband(name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	_ensure_warband_state()
	if warriors < 0:
		return {"ok": false, "reason": "Warrior count cannot be negative."}
	if not FLOWER_WAR_DOCTRINES.has(doctrine_id):
		return {"ok": false, "reason": "Unknown doctrine."}
	var available: int = _unassigned_warrior_pool()
	if warriors > available:
		return {"ok": false, "reason": "Need " + str(warriors) + " unassigned warriors; only " + str(available) + " available."}
	return {"ok": true, "reason": "Ready."}

func create_warband(name: String = "New Warband", warriors: int = 0, doctrine_id: String = "unspecialised", commander: String = "Household Captain") -> Dictionary:
	var status: Dictionary = can_create_warband(name, warriors, doctrine_id, commander)
	if not bool(status.get("ok", false)):
		return status
	var base_id: String = name.strip_edges().to_lower().replace(" ", "_")
	if base_id == "":
		base_id = "warband"
	var warband_id: String = base_id
	var suffix: int = 2
	while warbands.has(warband_id):
		warband_id = base_id + "_" + str(suffix)
		suffix += 1
	warbands[warband_id] = _make_starting_warband(warband_id, name, commander, warriors)
	warbands[warband_id]["doctrine"] = doctrine_id
	emit_signal("state_changed")
	return {"ok": true, "reason": "Created warband.", "warband_id": warband_id}

func can_reinforce_warband(warband_id: String, amount: int) -> Dictionary:
	return can_assign_warriors_to_warband(warband_id, amount)

func reinforce_warband(warband_id: String, amount: int) -> Dictionary:
	return assign_warriors_to_warband(warband_id, amount)

func can_assign_warriors_to_warband(warband_id: String, amount: int) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	if amount <= 0:
		return {"ok": false, "reason": "Choose at least 1 warrior."}
	var available: int = _unassigned_warrior_pool()
	if amount > available:
		return {"ok": false, "reason": "Need " + str(amount) + " unassigned warriors; only " + str(available) + " available."}
	return {"ok": true, "reason": "Ready."}

func assign_warriors_to_warband(warband_id: String, amount: int) -> Dictionary:
	var status: Dictionary = can_assign_warriors_to_warband(warband_id, amount)
	if not bool(status.get("ok", false)):
		return status
	var warband: Dictionary = warbands[warband_id] as Dictionary
	warband["ready_warriors"] = int(warband.get("ready_warriors", 0)) + amount
	warbands[warband_id] = _sync_warband_progress(warband)
	emit_signal("state_changed")
	return {"ok": true, "reason": "Assigned " + str(amount) + " warriors to " + String(warband.get("name", "warband")) + "."}

func can_unassign_warriors_from_warband(warband_id: String, amount: int) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	if amount <= 0:
		return {"ok": false, "reason": "Choose at least 1 warrior."}
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var ready: int = int(warband.get("ready_warriors", 0))
	if amount > ready:
		return {"ok": false, "reason": "Only " + str(ready) + " ready warriors can be unassigned."}
	return {"ok": true, "reason": "Ready."}

func unassign_warriors_from_warband(warband_id: String, amount: int) -> Dictionary:
	var status: Dictionary = can_unassign_warriors_from_warband(warband_id, amount)
	if not bool(status.get("ok", false)):
		return status
	var warband: Dictionary = warbands[warband_id] as Dictionary
	warband["ready_warriors"] = max(0, int(warband.get("ready_warriors", 0)) - amount)
	warbands[warband_id] = _sync_warband_progress(warband)
	emit_signal("state_changed")
	return {"ok": true, "reason": "Unassigned " + str(amount) + " warriors from " + String(warband.get("name", "warband")) + "."}

func can_specialise_warband(warband_id: String, doctrine_id: String) -> Dictionary:
	# Deprecated compatibility hook. Doctrine is no longer chosen through a
	# separate oath/action; it is derived from the Skill Web specialism gateway.
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	return {"ok": false, "reason": "Choose doctrine by purchasing a Skill Web specialism gateway."}

func specialise_warband(warband_id: String, doctrine_id: String) -> Dictionary:
	# Deprecated compatibility hook. Kept so older UI calls fail safely instead of
	# silently changing doctrine outside the Skill Web.
	return can_specialise_warband(warband_id, doctrine_id)

func get_warband_skill_web(warband_id: String = "") -> Dictionary:
	_ensure_warband_state()
	var nodes: Array[Dictionary] = _warband_skill_node_definitions()
	var connections: Array[Dictionary] = _warband_skill_connections()
	if warband_id == "":
		return {"ok": true, "nodes": nodes, "connections": connections, "description": "Warband Skill Web backend data. UI drawing comes later."}
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband.", "nodes": nodes, "connections": connections}
	var stored: Dictionary = warbands[warband_id] as Dictionary
	var warband: Dictionary = _sync_warband_progress(stored.duplicate(true))
	warbands[warband_id] = warband
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var statuses: Dictionary = {}
	for node: Dictionary in nodes:
		var trait_id: String = String(node.get("id", ""))
		if trait_id == "":
			continue
		var status: Dictionary = can_purchase_warband_trait(warband_id, trait_id)
		var requirements_met: bool = _warband_trait_requirements_met(purchased, node)
		statuses[trait_id] = {
			"purchased": purchased.has(trait_id),
			"requirements_met": requirements_met,
			"can_purchase": bool(status.get("ok", false)),
			"reason": String(status.get("reason", "")),
			"cost": int(node.get("cost", 1)),
			"cluster": String(node.get("cluster", "general"))
		}
	return {
		"ok": true,
		"warband": warband,
		"combat_stats": _warband_combat_stats_from_warband(warband),
		"nodes": nodes,
		"traits": nodes,
		"connections": connections,
		"statuses": statuses,
		"points_available": int(warband.get("trait_points", 0)),
		"points_total": int(warband.get("total_trait_points", 0)),
		"points_spent": int(warband.get("spent_trait_points", 0)),
		"purchased_traits": purchased,
		"available_traits": get_warband_available_traits(warband_id),
		"locked_traits": get_warband_locked_traits(warband_id),
		"effect_totals": get_warband_trait_effect_totals(warband_id),
		"specialisation": get_warband_specialisation_summary(warband_id)
	}

func get_warband_trait_tree(warband_id: String) -> Dictionary:
	# Backwards-compatible name. The old rigid trait tree is now a Diablo/PoE-style
	# connected skill web with clusters and mutually exclusive specialism gateways.
	return get_warband_skill_web(warband_id)

func get_warband_trait_points(warband_id: String) -> int:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return 0
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return int(warband.get("trait_points", 0))

func get_warband_purchased_traits(warband_id: String) -> Array[String]:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return []
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return _warband_purchased_trait_ids(warband)

func get_warband_available_traits(warband_id: String) -> Array[Dictionary]:
	_ensure_warband_state()
	var output: Array[Dictionary] = []
	if not warbands.has(warband_id):
		return output
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var points: int = int(warband.get("trait_points", 0))
	for node: Dictionary in _warband_skill_node_definitions():
		var trait_id: String = String(node.get("id", ""))
		if trait_id == "" or purchased.has(trait_id):
			continue
		if _warband_trait_locked_by_specialisation(purchased, node):
			continue
		if not _warband_trait_requirements_met(purchased, node):
			continue
		var row: Dictionary = node.duplicate(true)
		row["can_afford"] = points >= int(node.get("cost", 1))
		row["status_text"] = "Available" if bool(row.get("can_afford", false)) else "Connected, but needs more skill points"
		output.append(row)
	return output

func get_warband_locked_traits(warband_id: String) -> Array[Dictionary]:
	_ensure_warband_state()
	var output: Array[Dictionary] = []
	if not warbands.has(warband_id):
		return output
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	for node: Dictionary in _warband_skill_node_definitions():
		var trait_id: String = String(node.get("id", ""))
		if trait_id == "" or purchased.has(trait_id):
			continue
		if _warband_trait_locked_by_specialisation(purchased, node):
			var spec_row: Dictionary = node.duplicate(true)
			spec_row["status_text"] = _warband_specialisation_lock_text(purchased)
			output.append(spec_row)
			continue
		if _warband_trait_requirements_met(purchased, node):
			continue
		var row: Dictionary = node.duplicate(true)
		row["status_text"] = "Locked: requires " + _warband_requirements_text(node)
		output.append(row)
	return output

func can_purchase_warband_trait(warband_id: String, trait_id: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"ok": false, "reason": "Unknown warband."}
	var node: Dictionary = _warband_skill_node_by_id(trait_id)
	if node.is_empty():
		return {"ok": false, "reason": "Unknown skill node."}
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	if purchased.has(trait_id):
		return {"ok": false, "reason": "Already purchased."}
	if _warband_trait_locked_by_specialisation(purchased, node):
		return {"ok": false, "reason": _warband_specialisation_lock_text(purchased)}
	if not _warband_trait_requirements_met(purchased, node):
		return {"ok": false, "reason": "Requires " + _warband_requirements_text(node) + "."}
	var cost: int = max(0, int(node.get("cost", 1)))
	var points: int = int(warband.get("trait_points", 0))
	if points < cost:
		return {"ok": false, "reason": "Need " + str(cost) + " skill point(s); only " + str(points) + " available."}
	return {"ok": true, "reason": "Ready.", "cost": cost, "points_available": points, "trait": node.duplicate(true)}

func purchase_warband_trait(warband_id: String, trait_id: String) -> Dictionary:
	var status: Dictionary = can_purchase_warband_trait(warband_id, trait_id)
	if not bool(status.get("ok", false)):
		return status
	var node: Dictionary = _warband_skill_node_by_id(trait_id)
	var warband: Dictionary = warbands[warband_id] as Dictionary
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	purchased.append(trait_id)
	warband["purchased_traits"] = purchased
	warband["traits"] = purchased.duplicate()
	warband = _sync_warband_progress(warband)
	warbands[warband_id] = warband
	var spec: Dictionary = warband.get("specialisation", {}) as Dictionary
	var message: String = String(warband.get("name", "Warband")) + " purchased skill node: " + String(node.get("name", trait_id)) + ". Specialisation: " + String(spec.get("name", "Unspecialised")) + "."
	if bool(node.get("specialisation", false)):
		message += " Combat doctrine is now " + _warband_doctrine_name(String(warband.get("doctrine", "unspecialised"))) + "."
	last_report.append(message)
	emit_signal("state_changed")
	return {"ok": true, "reason": message, "warband": warband.duplicate(true), "specialisation": spec}

func get_warband_trait_effect_totals(warband_id: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {}
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return _warband_trait_effect_totals_from_purchased(_warband_purchased_trait_ids(warband))

func get_warband_specialisation_summary(warband_id: String) -> Dictionary:
	_ensure_warband_state()
	if not warbands.has(warband_id):
		return {"name": "Unknown", "primary": "", "secondary": "", "keystones": [], "points_by_cluster": {}}
	var warband: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
	warbands[warband_id] = warband
	return (warband.get("specialisation", {}) as Dictionary).duplicate(true)

func _ensure_warband_skill_defaults(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	if not purchased.has("household_muster"):
		purchased.insert(0, "household_muster")
	warband["purchased_traits"] = purchased
	warband["traits"] = purchased.duplicate()
	return warband

func _warband_purchased_trait_ids(warband: Dictionary) -> Array[String]:
	var output: Array[String] = []
	var raw: Array = []
	if warband.has("purchased_traits"):
		raw = warband.get("purchased_traits", []) as Array
	elif warband.has("traits"):
		raw = warband.get("traits", []) as Array
	for item_variant: Variant in raw:
		var trait_id: String = String(item_variant)
		if trait_id == "":
			continue
		if output.has(trait_id):
			continue
		if _warband_skill_node_by_id(trait_id).is_empty():
			continue
		output.append(trait_id)
	if output.is_empty():
		output.append("household_muster")
	elif not output.has("household_muster"):
		output.insert(0, "household_muster")
	return output

func _warband_trait_effect_totals_from_purchased(purchased: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		var effects: Dictionary = node.get("effects", {}) as Dictionary
		for effect_variant: Variant in effects.keys():
			var effect_id: String = String(effect_variant)
			result[effect_id] = float(result.get(effect_id, 0.0)) + float(effects[effect_variant])
	return result

func _warband_specialisation_summary_for_warband(warband: Dictionary) -> Dictionary:
	var purchased: Array[String] = _warband_purchased_trait_ids(warband)
	var point_clusters: Dictionary = {"eagle": 0, "jaguar": 0, "otomi": 0, "coyote": 0, "veteran": 0, "supply": 0, "core": 0}
	var keystones: Array[String] = _warband_purchased_specialisation_clusters(purchased)
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		var cluster: String = String(node.get("cluster", "core"))
		var cost: int = max(0, int(node.get("cost", 0)))
		point_clusters[cluster] = int(point_clusters.get(cluster, 0)) + cost
	var military_clusters: Array[String] = ["eagle", "jaguar", "otomi", "coyote"]
	var primary: String = ""
	var primary_points: int = 0
	for cluster_id: String in military_clusters:
		var points: int = int(point_clusters.get(cluster_id, 0))
		if points > primary_points:
			primary = cluster_id
			primary_points = points
	var name: String = "Unspecialised"
	var style: String = "none"
	var locked: bool = false
	if not keystones.is_empty():
		primary = keystones[0]
		locked = true
		style = "specialised"
		name = _warband_cluster_display_name(primary) + " Specialist"
		if keystones.size() > 1:
			# Legacy safeguard for older test saves made before specialisms locked.
			name += " (legacy mixed)"
			style = "legacy_mixed"
	elif primary != "" and primary_points > 0:
		name = _warband_cluster_display_name(primary) + "-leaning"
		style = "leaning"
	var doctrine_id: String = primary if locked and FLOWER_WAR_DOCTRINES.has(primary) else "unspecialised"
	return {
		"name": name,
		"style": style,
		"primary": primary,
		"primary_name": _warband_cluster_display_name(primary),
		"secondary": "",
		"secondary_name": "None",
		"keystones": keystones,
		"locked_specialism": locked,
		"specialism_locked": locked,
		"doctrine_id": doctrine_id,
		"doctrine_name": _warband_doctrine_name(doctrine_id),
		"sets_combat_doctrine": locked,
		"points_by_cluster": point_clusters,
		"effect_totals": _warband_trait_effect_totals_from_purchased(purchased)
	}

func _warband_cluster_display_name(cluster_id: String) -> String:
	match cluster_id:
		"eagle":
			return "Eagle"
		"jaguar":
			return "Jaguar"
		"otomi":
			return "Otomi"
		"coyote":
			return "Coyote"
		"veteran":
			return "Veteran"
		"supply":
			return "Supply"
		"core":
			return "Household"
	return cluster_id.capitalize()


func _warband_chosen_specialisation_cluster(purchased: Array[String]) -> String:
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			return String(node.get("cluster", ""))
	return ""

func _warband_purchased_specialisation_clusters(purchased: Array[String]) -> Array[String]:
	var output: Array[String] = []
	for trait_id: String in purchased:
		var node: Dictionary = _warband_skill_node_by_id(trait_id)
		if bool(node.get("specialisation", false)):
			var cluster_id: String = String(node.get("cluster", ""))
			if cluster_id != "" and not output.has(cluster_id):
				output.append(cluster_id)
	return output

func _warband_trait_locked_by_specialisation(purchased: Array[String], node: Dictionary) -> bool:
	# A warband may only take one major troop specialism. The approach and
	# preparation nodes remain open, but once a specialist gateway is bought,
	# the other specialist gateways are permanently locked.
	if not bool(node.get("specialisation", false)):
		return false
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return false
	return String(node.get("cluster", "")) != chosen_cluster

func _warband_specialisation_lock_text(purchased: Array[String]) -> String:
	var chosen_cluster: String = _warband_chosen_specialisation_cluster(purchased)
	if chosen_cluster == "":
		return ""
	return "Locked by " + _warband_cluster_display_name(chosen_cluster) + " specialism. A warband can only choose one specialism."

func _warband_trait_requirements_met(purchased: Array[String], node: Dictionary) -> bool:
	var requirements: Array = node.get("requires", []) as Array
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		if not purchased.has(req_id):
			return false
	var any_requirements: Array = node.get("requires_any", []) as Array
	if not any_requirements.is_empty():
		var any_met: bool = false
		for req_variant: Variant in any_requirements:
			var req_id: String = String(req_variant)
			if purchased.has(req_id):
				any_met = true
				break
		if not any_met:
			return false
	return true

func _warband_requirements_text(node: Dictionary) -> String:
	var requirements: Array = node.get("requires", []) as Array
	var any_requirements: Array = node.get("requires_any", []) as Array
	var names: Array[String] = []
	for req_variant: Variant in requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = _warband_skill_node_by_id(req_id)
		if req_node.is_empty():
			names.append(req_id)
		else:
			names.append(String(req_node.get("name", req_id)))
	var any_names: Array[String] = []
	for req_variant: Variant in any_requirements:
		var req_id: String = String(req_variant)
		var req_node: Dictionary = _warband_skill_node_by_id(req_id)
		if req_node.is_empty():
			any_names.append(req_id)
		else:
			any_names.append(String(req_node.get("name", req_id)))
	if names.is_empty() and any_names.is_empty():
		return "no prerequisite"
	if names.is_empty():
		return "one of " + ", ".join(any_names)
	if any_names.is_empty():
		return ", ".join(names)
	return ", ".join(names) + " and one of " + ", ".join(any_names)

func _warband_skill_connections() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for node: Dictionary in _warband_skill_node_definitions():
		var to_id: String = String(node.get("id", ""))
		var requirements: Array = node.get("requires", []) as Array
		for req_variant: Variant in requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "required"})
		var any_requirements: Array = node.get("requires_any", []) as Array
		for req_variant: Variant in any_requirements:
			output.append({"from": String(req_variant), "to": to_id, "type": "any"})
	return output

func _warband_skill_node_by_id(trait_id: String) -> Dictionary:
	for node: Dictionary in _warband_skill_node_definitions():
		if String(node.get("id", "")) == trait_id:
			return node.duplicate(true)
	return {}

func _warband_skill_node_definitions() -> Array[Dictionary]:
	# v0.12.11 symmetric branched rejoin web structure.
	# Each doctrine follows the same symmetric readable pattern:
	# approach -> preparation -> specialist gateway -> three short branches ->
	# elite rejoin node -> three advanced branches -> final chosen capstone.
	# Specialisation gateways are now mutually exclusive: one warband, one major troop specialism.
	return [
		{
			"id": "household_muster",
			"name": "Household Muster",
			"cluster": "core",
			"tier": 0,
			"x": 0,
			"y": 0,
			"cost": 0,
			"effects": {
				"readiness_add": 1.0
			},
			"description": "The founding muster node. Every warband starts here for free."
		},
		{
			"id": "formation_drill",
			"name": "Formation Drill",
			"cluster": "core",
			"tier": 1,
			"x": 0,
			"y": 1,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"defence_add": 0.01
			},
			"description": "Basic formation practice makes the band steadier in battle."
		},
		{
			"id": "weapon_familiarity",
			"name": "Weapon Familiarity",
			"cluster": "core",
			"tier": 1,
			"x": 1,
			"y": 0,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"offence_add": 0.01
			},
			"description": "Warriors become more comfortable with house weapons and drill patterns."
		},
		{
			"id": "veteran_captains",
			"name": "Veteran Captains",
			"cluster": "veteran",
			"tier": 1,
			"x": -1,
			"y": 0,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"xp_gain_add": 0.02
			},
			"description": "Experienced captains help the warband learn from each expedition."
		},
		{
			"id": "battle_rhythm",
			"name": "Battle Rhythm",
			"cluster": "veteran",
			"tier": 2,
			"x": 0,
			"y": -1,
			"cost": 1,
			"requires": [
				"household_muster"
			],
			"effects": {
				"offence_add": 0.005,
				"defence_add": 0.005,
				"provisioning_discount_add": 0.01
			},
			"description": "The company learns how to move, close, withdraw, reform and keep supplies ordered as one body. This now folds in the old Supply Habits support bonus so the centre web stays clean and symmetrical."
		},
		{
			"id": "eagle_approach",
			"name": "Eagle Approach",
			"cluster": "eagle",
			"tier": 1,
			"x": 0,
			"y": 3,
			"cost": 1,
			"requires": [
				"formation_drill"
			],
			"effects": {
				"capture_chance_add": 0.01
			},
			"description": "The warband begins training toward controlled capture and disciplined advance."
		},
		{
			"id": "eagle_controlled_advance",
			"name": "Controlled Advance",
			"cluster": "eagle",
			"tier": 2,
			"x": 0,
			"y": 4,
			"cost": 1,
			"requires": [
				"eagle_approach"
			],
			"effects": {
				"capture_chance_add": 0.015,
				"defence_add": 0.01
			},
			"description": "The band learns to close while preserving valuable enemies alive."
		},
		{
			"id": "eagle_specialisation",
			"name": "Eagle Specialist",
			"cluster": "eagle",
			"tier": 3,
			"x": 0,
			"y": 5,
			"cost": 1,
			"requires": [
				"eagle_controlled_advance"
			],
			"effects": {
				"capture_chance_add": 0.025
			},
			"description": "A locking specialism gateway into Eagle traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "eagle_net_drill",
			"name": "Net Drill",
			"cluster": "eagle",
			"tier": 4,
			"x": -2,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"capture_chance_add": 0.025
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_prisoner_rings",
			"name": "Prisoner Rings",
			"cluster": "eagle",
			"tier": 5,
			"x": -2,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_net_drill"
			],
			"effects": {
				"capture_chance_add": 0.03
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_living_tribute",
			"name": "Living Tribute",
			"cluster": "eagle",
			"tier": 6,
			"x": -2,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_prisoner_rings"
			],
			"effects": {
				"capture_chance_add": 0.04
			},
			"description": "Capture",
			"path": "capture"
		},
		{
			"id": "eagle_temple_guard",
			"name": "Temple Guard",
			"cluster": "eagle",
			"tier": 4,
			"x": 0,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"defence_add": 0.025
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_sacred_discipline",
			"name": "Sacred Discipline",
			"cluster": "eagle",
			"tier": 5,
			"x": 0,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_temple_guard"
			],
			"effects": {
				"defence_add": 0.03
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_shielded_capture",
			"name": "Shielded Capture",
			"cluster": "eagle",
			"tier": 6,
			"x": 0,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_sacred_discipline"
			],
			"effects": {
				"defence_add": 0.025,
				"capture_chance_add": 0.015
			},
			"description": "Temple",
			"path": "temple"
		},
		{
			"id": "eagle_war_banners",
			"name": "War Banners",
			"cluster": "eagle",
			"tier": 4,
			"x": 2,
			"y": 6,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"effects": {
				"prestige_pending_add": 0.025
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "eagle_noble_witnesses",
			"name": "Noble Witnesses",
			"cluster": "eagle",
			"tier": 5,
			"x": 2,
			"y": 7,
			"cost": 1,
			"requires": [
				"eagle_war_banners"
			],
			"effects": {
				"prestige_pending_add": 0.035
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "eagle_victory_procession",
			"name": "Victory Procession",
			"cluster": "eagle",
			"tier": 6,
			"x": 2,
			"y": 8,
			"cost": 1,
			"requires": [
				"eagle_noble_witnesses"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Banner",
			"path": "banner"
		},
		{
			"id": "elite_eagle_warriors",
			"name": "Elite Eagle Warriors",
			"cluster": "eagle",
			"tier": 7,
			"x": 0,
			"y": 9,
			"cost": 1,
			"requires": [
				"eagle_specialisation"
			],
			"requires_any": [
				"eagle_living_tribute",
				"eagle_shielded_capture",
				"eagle_victory_procession"
			],
			"effects": {
				"capture_chance_add": 0.04,
				"defence_add": 0.02
			},
			"description": "The branches rejoin into an elite Eagle company identity. Any completed first Eagle branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "eagle_captive_masters",
			"name": "Captive Masters",
			"cluster": "eagle",
			"tier": 8,
			"x": -2,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"capture_chance_add": 0.045
			},
			"description": "High Captors",
			"path": "high_capture"
		},
		{
			"id": "eagle_prince_takers",
			"name": "Prince Takers",
			"cluster": "eagle",
			"tier": 9,
			"x": -2,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_captive_masters"
			],
			"effects": {
				"capture_chance_add": 0.055
			},
			"description": "High Captors",
			"path": "high_capture"
		},
		{
			"id": "eagle_temple_oath",
			"name": "Temple Oath",
			"cluster": "eagle",
			"tier": 8,
			"x": 0,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"defence_add": 0.04
			},
			"description": "Honour Guard",
			"path": "honour"
		},
		{
			"id": "eagle_guarded_return",
			"name": "Guarded Return",
			"cluster": "eagle",
			"tier": 9,
			"x": 0,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_temple_oath"
			],
			"effects": {
				"defence_add": 0.04,
				"death_chance_add": -0.01
			},
			"description": "Honour Guard",
			"path": "honour"
		},
		{
			"id": "eagle_procession_songs",
			"name": "Procession Songs",
			"cluster": "eagle",
			"tier": 8,
			"x": 2,
			"y": 10,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Public Glory",
			"path": "public"
		},
		{
			"id": "eagle_radiant_standards",
			"name": "Radiant Standards",
			"cluster": "eagle",
			"tier": 9,
			"x": 2,
			"y": 11,
			"cost": 1,
			"requires": [
				"eagle_procession_songs"
			],
			"effects": {
				"prestige_pending_add": 0.06
			},
			"description": "Public Glory",
			"path": "public"
		},
		{
			"id": "chosen_eagles",
			"name": "Chosen Eagles",
			"cluster": "eagle",
			"tier": 10,
			"x": 0,
			"y": 12,
			"cost": 1,
			"requires": [
				"elite_eagle_warriors"
			],
			"requires_any": [
				"eagle_prince_takers",
				"eagle_guarded_return",
				"eagle_radiant_standards"
			],
			"effects": {
				"capture_chance_add": 0.075,
				"prestige_pending_add": 0.035
			},
			"description": "The advanced branches rejoin into the Chosen Eagles: an elite warband known for living captives, sacred discipline and public honour.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "jaguar_approach",
			"name": "Jaguar Approach",
			"cluster": "jaguar",
			"tier": 1,
			"x": 3,
			"y": 0,
			"cost": 1,
			"requires": [
				"weapon_familiarity"
			],
			"effects": {
				"offence_add": 0.02
			},
			"description": "The warband begins training toward shock, killing power and visible martial fame."
		},
		{
			"id": "jaguar_close_drill",
			"name": "Close Drill",
			"cluster": "jaguar",
			"tier": 2,
			"x": 4,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_approach"
			],
			"effects": {
				"offence_add": 0.025
			},
			"description": "Close-order fighting makes the band more dangerous once battle is joined."
		},
		{
			"id": "jaguar_specialisation",
			"name": "Jaguar Specialist",
			"cluster": "jaguar",
			"tier": 3,
			"x": 5,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_close_drill"
			],
			"effects": {
				"offence_add": 0.03
			},
			"description": "A locking specialism gateway into Jaguar traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "jaguar_blooded_charge",
			"name": "Blooded Charge",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"offence_add": 0.025
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_close_killers",
			"name": "Close Killers",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_blooded_charge"
			],
			"effects": {
				"offence_add": 0.03
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_red_hands",
			"name": "Red Hands",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_close_killers"
			],
			"effects": {
				"offence_add": 0.035
			},
			"description": "The Blooded line favours direct assault and decisive melee pressure.",
			"path": "blooded"
		},
		{
			"id": "jaguar_trophy_display",
			"name": "Trophy Display",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"prestige_pending_add": 0.03
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_war_fame",
			"name": "War Fame",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_trophy_display"
			],
			"effects": {
				"prestige_pending_add": 0.035
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_public_terror",
			"name": "Public Terror",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_war_fame"
			],
			"effects": {
				"prestige_pending_add": 0.04
			},
			"description": "The Trophy line turns victories into renown and fear.",
			"path": "trophy"
		},
		{
			"id": "jaguar_death_oath",
			"name": "Death-Seeker Oath",
			"cluster": "jaguar",
			"tier": 4,
			"x": 6,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"effects": {
				"offence_add": 0.02,
				"death_chance_add": 0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "jaguar_ritual_ferocity",
			"name": "Ritual Ferocity",
			"cluster": "jaguar",
			"tier": 5,
			"x": 7,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_death_oath"
			],
			"effects": {
				"offence_add": 0.025,
				"capture_chance_add": 0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "jaguar_no_retreat",
			"name": "No Retreat",
			"cluster": "jaguar",
			"tier": 6,
			"x": 8,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_ritual_ferocity"
			],
			"effects": {
				"offence_add": 0.035,
				"defence_add": -0.005
			},
			"description": "The Death-Seeker line trades safety for terrifying commitment.",
			"path": "death"
		},
		{
			"id": "elite_jaguar_warriors",
			"name": "Elite Jaguar Warriors",
			"cluster": "jaguar",
			"tier": 7,
			"x": 9,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_specialisation"
			],
			"requires_any": [
				"jaguar_red_hands",
				"jaguar_public_terror",
				"jaguar_no_retreat"
			],
			"effects": {
				"offence_add": 0.05,
				"defence_add": 0.015
			},
			"description": "The branches rejoin into an elite Jaguar company identity. Any completed first Jaguar branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "jaguar_breaking_strike",
			"name": "Breaking Strike",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": 2,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"offence_add": 0.04,
				"enemy_defence_add": -0.005
			},
			"description": "Elite Butchers",
			"path": "butchers"
		},
		{
			"id": "jaguar_blooded_veterans",
			"name": "Blooded Veterans",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": 2,
			"cost": 1,
			"requires": [
				"jaguar_breaking_strike"
			],
			"effects": {
				"offence_add": 0.05
			},
			"description": "Elite Butchers",
			"path": "butchers"
		},
		{
			"id": "jaguar_named_victories",
			"name": "Named Victories",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"prestige_pending_add": 0.045
			},
			"description": "Fame Bearers",
			"path": "fame"
		},
		{
			"id": "jaguar_trophy_procession",
			"name": "Trophy Procession",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": 0,
			"cost": 1,
			"requires": [
				"jaguar_named_victories"
			],
			"effects": {
				"prestige_pending_add": 0.06
			},
			"description": "Fame Bearers",
			"path": "fame"
		},
		{
			"id": "jaguar_blood_debt",
			"name": "Blood Debt",
			"cluster": "jaguar",
			"tier": 8,
			"x": 10,
			"y": -2,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"effects": {
				"capture_chance_add": 0.015,
				"offence_add": 0.025
			},
			"description": "Ritual Killers",
			"path": "ritual"
		},
		{
			"id": "jaguar_ritual_panic",
			"name": "Ritual Panic",
			"cluster": "jaguar",
			"tier": 9,
			"x": 11,
			"y": -2,
			"cost": 1,
			"requires": [
				"jaguar_blood_debt"
			],
			"effects": {
				"offence_add": 0.04,
				"capture_chance_add": 0.02
			},
			"description": "Ritual Killers",
			"path": "ritual"
		},
		{
			"id": "chosen_jaguars",
			"name": "Chosen Jaguars",
			"cluster": "jaguar",
			"tier": 10,
			"x": 12,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_jaguar_warriors"
			],
			"requires_any": [
				"jaguar_blooded_veterans",
				"jaguar_trophy_procession",
				"jaguar_ritual_panic"
			],
			"effects": {
				"offence_add": 0.08,
				"prestige_pending_add": 0.04
			},
			"description": "The advanced branches rejoin into the Chosen Jaguars: a famous elite warband whose identity is built on fear, trophies and decisive violence.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "otomi_approach",
			"name": "Otomi Approach",
			"cluster": "otomi",
			"tier": 1,
			"x": -3,
			"y": 0,
			"cost": 1,
			"requires": [
				"veteran_captains"
			],
			"effects": {
				"defence_add": 0.02
			},
			"description": "The warband begins training toward endurance, formation and survival."
		},
		{
			"id": "otomi_brace_drill",
			"name": "Brace Drill",
			"cluster": "otomi",
			"tier": 2,
			"x": -4,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_approach"
			],
			"effects": {
				"defence_add": 0.025
			},
			"description": "The band learns to absorb pressure without breaking."
		},
		{
			"id": "otomi_specialisation",
			"name": "Otomi Specialist",
			"cluster": "otomi",
			"tier": 3,
			"x": -5,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_brace_drill"
			],
			"effects": {
				"defence_add": 0.035,
				"death_chance_add": -0.005
			},
			"description": "A locking specialism gateway into Otomi traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "otomi_shield_wall",
			"name": "Shield Wall",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"defence_add": 0.03
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_hold_ground",
			"name": "Hold Ground",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_shield_wall"
			],
			"effects": {
				"defence_add": 0.035
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_unbroken_line",
			"name": "Unbroken Line",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_hold_ground"
			],
			"effects": {
				"defence_add": 0.045
			},
			"description": "Shield",
			"path": "shield"
		},
		{
			"id": "otomi_iron_resolve",
			"name": "Iron Resolve",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"death_chance_add": -0.015
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_carry_wounded",
			"name": "Carry the Wounded",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_iron_resolve"
			],
			"effects": {
				"death_chance_add": -0.015,
				"injury_recovery_add": 0.02
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_death_avoidance",
			"name": "Death Avoidance",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_carry_wounded"
			],
			"effects": {
				"death_chance_add": -0.025
			},
			"description": "Survival",
			"path": "survival"
		},
		{
			"id": "otomi_hard_march",
			"name": "Hard March",
			"cluster": "otomi",
			"tier": 4,
			"x": -6,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"effects": {
				"provisioning_discount_add": 0.02
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "otomi_lean_camp",
			"name": "Lean Camp",
			"cluster": "otomi",
			"tier": 5,
			"x": -7,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_hard_march"
			],
			"effects": {
				"provisioning_discount_add": 0.025
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "otomi_rough_ground",
			"name": "Rough Ground",
			"cluster": "otomi",
			"tier": 6,
			"x": -8,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_lean_camp"
			],
			"effects": {
				"provisioning_discount_add": 0.03,
				"casualty_chance_add": -0.005
			},
			"description": "Frontier",
			"path": "frontier"
		},
		{
			"id": "elite_otomi_warriors",
			"name": "Elite Otomi Warriors",
			"cluster": "otomi",
			"tier": 7,
			"x": -9,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_specialisation"
			],
			"requires_any": [
				"otomi_unbroken_line",
				"otomi_death_avoidance",
				"otomi_rough_ground"
			],
			"effects": {
				"defence_add": 0.055,
				"death_chance_add": -0.01
			},
			"description": "The branches rejoin into an elite Otomi company identity. Any completed first Otomi branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "otomi_braced_veterans",
			"name": "Braced Veterans",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": 2,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"defence_add": 0.045
			},
			"description": "Wall Veterans",
			"path": "wall"
		},
		{
			"id": "otomi_stone_line",
			"name": "Stone Line",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": 2,
			"cost": 1,
			"requires": [
				"otomi_braced_veterans"
			],
			"effects": {
				"defence_add": 0.06
			},
			"description": "Wall Veterans",
			"path": "wall"
		},
		{
			"id": "otomi_wounded_return",
			"name": "Wounded Return",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"injury_recovery_add": 0.035,
				"death_chance_add": -0.015
			},
			"description": "Recovery Veterans",
			"path": "recovery"
		},
		{
			"id": "otomi_veteran_recovery",
			"name": "Veteran Recovery",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": 0,
			"cost": 1,
			"requires": [
				"otomi_wounded_return"
			],
			"effects": {
				"injury_recovery_add": 0.045,
				"death_chance_add": -0.02
			},
			"description": "Recovery Veterans",
			"path": "recovery"
		},
		{
			"id": "otomi_route_hardening",
			"name": "Route Hardening",
			"cluster": "otomi",
			"tier": 8,
			"x": -10,
			"y": -2,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"effects": {
				"provisioning_discount_add": 0.045
			},
			"description": "Frontier Veterans",
			"path": "frontier_elite"
		},
		{
			"id": "otomi_low_upkeep_veterans",
			"name": "Low-Upkeep Veterans",
			"cluster": "otomi",
			"tier": 9,
			"x": -11,
			"y": -2,
			"cost": 1,
			"requires": [
				"otomi_route_hardening"
			],
			"effects": {
				"provisioning_discount_add": 0.06,
				"casualty_chance_add": -0.01
			},
			"description": "Frontier Veterans",
			"path": "frontier_elite"
		},
		{
			"id": "unbroken_otomi",
			"name": "Unbroken Otomi",
			"cluster": "otomi",
			"tier": 10,
			"x": -12,
			"y": 0,
			"cost": 1,
			"requires": [
				"elite_otomi_warriors"
			],
			"requires_any": [
				"otomi_stone_line",
				"otomi_veteran_recovery",
				"otomi_low_upkeep_veterans"
			],
			"effects": {
				"defence_add": 0.08,
				"death_chance_add": -0.025
			},
			"description": "The advanced branches rejoin into the Unbroken Otomi: an elite warband famous for survival, discipline and holding the line.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		},
		{
			"id": "coyote_approach",
			"name": "Coyote Approach",
			"cluster": "coyote",
			"tier": 1,
			"x": 0,
			"y": -3,
			"cost": 1,
			"requires": [
				"battle_rhythm"
			],
			"effects": {
				"loot_value_add": 0.02
			},
			"description": "The warband begins training toward speed, raiding and opportunistic returns."
		},
		{
			"id": "coyote_route_drill",
			"name": "Route Drill",
			"cluster": "coyote",
			"tier": 2,
			"x": 0,
			"y": -4,
			"cost": 1,
			"requires": [
				"coyote_approach"
			],
			"effects": {
				"loot_value_add": 0.02,
				"provisioning_discount_add": 0.005
			},
			"description": "Known routes help the band find goods and escape cleanly."
		},
		{
			"id": "coyote_specialisation",
			"name": "Coyote Specialist",
			"cluster": "coyote",
			"tier": 3,
			"x": 0,
			"y": -5,
			"cost": 1,
			"requires": [
				"coyote_route_drill"
			],
			"effects": {
				"loot_value_add": 0.035
			},
			"description": "A locking specialism gateway into Coyote traditions. Once chosen, other troop specialism gateways are closed to this warband.",
			"specialisation": true
		},
		{
			"id": "coyote_spoil_takers",
			"name": "Spoil Takers",
			"cluster": "coyote",
			"tier": 4,
			"x": -2,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"loot_value_add": 0.03
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_fast_looting",
			"name": "Fast Looting",
			"cluster": "coyote",
			"tier": 5,
			"x": -2,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_spoil_takers"
			],
			"effects": {
				"loot_value_add": 0.035
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_prize_scouts",
			"name": "Prize Scouts",
			"cluster": "coyote",
			"tier": 6,
			"x": -2,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_fast_looting"
			],
			"effects": {
				"loot_value_add": 0.045
			},
			"description": "Raider",
			"path": "raider"
		},
		{
			"id": "coyote_light_provisioning",
			"name": "Light Provisioning",
			"cluster": "coyote",
			"tier": 4,
			"x": 0,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"provisioning_discount_add": 0.025
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_route_knowledge",
			"name": "Route Knowledge",
			"cluster": "coyote",
			"tier": 5,
			"x": 0,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_light_provisioning"
			],
			"effects": {
				"provisioning_discount_add": 0.03,
				"casualty_chance_add": -0.005
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_cheap_campaigns",
			"name": "Cheap Campaigns",
			"cluster": "coyote",
			"tier": 6,
			"x": 0,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_route_knowledge"
			],
			"effects": {
				"provisioning_discount_add": 0.04
			},
			"description": "Scout",
			"path": "scout"
		},
		{
			"id": "coyote_sudden_strike",
			"name": "Sudden Strike",
			"cluster": "coyote",
			"tier": 4,
			"x": 2,
			"y": -6,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"effects": {
				"offence_add": 0.025,
				"defence_add": -0.005
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "coyote_vanishing_line",
			"name": "Vanishing Line",
			"cluster": "coyote",
			"tier": 5,
			"x": 2,
			"y": -7,
			"cost": 1,
			"requires": [
				"coyote_sudden_strike"
			],
			"effects": {
				"offence_add": 0.025,
				"casualty_chance_add": -0.005
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "coyote_fragile_violence",
			"name": "Fragile Violence",
			"cluster": "coyote",
			"tier": 6,
			"x": 2,
			"y": -8,
			"cost": 1,
			"requires": [
				"coyote_vanishing_line"
			],
			"effects": {
				"offence_add": 0.04,
				"defence_add": -0.01
			},
			"description": "Ghost",
			"path": "ghost"
		},
		{
			"id": "elite_coyote_warriors",
			"name": "Elite Coyote Warriors",
			"cluster": "coyote",
			"tier": 7,
			"x": 0,
			"y": -9,
			"cost": 1,
			"requires": [
				"coyote_specialisation"
			],
			"requires_any": [
				"coyote_prize_scouts",
				"coyote_cheap_campaigns",
				"coyote_fragile_violence"
			],
			"effects": {
				"loot_value_add": 0.055,
				"provisioning_discount_add": 0.015
			},
			"description": "The branches rejoin into an elite Coyote company identity. Any completed first Coyote branch can reach this node.",
			"rejoin": true
		},
		{
			"id": "coyote_night_plunder",
			"name": "Night Plunder",
			"cluster": "coyote",
			"tier": 8,
			"x": -2,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"loot_value_add": 0.05
			},
			"description": "Plunder Veterans",
			"path": "plunder"
		},
		{
			"id": "coyote_choice_spoils",
			"name": "Choice Spoils",
			"cluster": "coyote",
			"tier": 9,
			"x": -2,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_night_plunder"
			],
			"effects": {
				"loot_value_add": 0.07
			},
			"description": "Plunder Veterans",
			"path": "plunder"
		},
		{
			"id": "coyote_hidden_paths",
			"name": "Hidden Paths",
			"cluster": "coyote",
			"tier": 8,
			"x": 0,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"provisioning_discount_add": 0.045,
				"casualty_chance_add": -0.005
			},
			"description": "Route Veterans",
			"path": "routes"
		},
		{
			"id": "coyote_supply_vanish",
			"name": "Supply Vanish",
			"cluster": "coyote",
			"tier": 9,
			"x": 0,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_hidden_paths"
			],
			"effects": {
				"provisioning_discount_add": 0.06,
				"casualty_chance_add": -0.01
			},
			"description": "Route Veterans",
			"path": "routes"
		},
		{
			"id": "coyote_ghost_assault",
			"name": "Ghost Assault",
			"cluster": "coyote",
			"tier": 8,
			"x": 2,
			"y": -10,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"effects": {
				"offence_add": 0.045,
				"loot_value_add": 0.02
			},
			"description": "Shadow Veterans",
			"path": "shadow"
		},
		{
			"id": "coyote_no_tracks",
			"name": "No Tracks",
			"cluster": "coyote",
			"tier": 9,
			"x": 2,
			"y": -11,
			"cost": 1,
			"requires": [
				"coyote_ghost_assault"
			],
			"effects": {
				"offence_add": 0.06,
				"defence_add": -0.01,
				"loot_value_add": 0.025
			},
			"description": "Shadow Veterans",
			"path": "shadow"
		},
		{
			"id": "shadow_coyotes",
			"name": "Shadow Coyotes",
			"cluster": "coyote",
			"tier": 10,
			"x": 0,
			"y": -12,
			"cost": 1,
			"requires": [
				"elite_coyote_warriors"
			],
			"requires_any": [
				"coyote_choice_spoils",
				"coyote_supply_vanish",
				"coyote_no_tracks"
			],
			"effects": {
				"loot_value_add": 0.08,
				"provisioning_discount_add": 0.035,
				"offence_add": 0.025
			},
			"description": "The advanced branches rejoin into the Shadow Coyotes: an elite warband known for plunder, routes and sudden disappearance.",
			"capstone": true,
			"rejoin": true,
			"chosen_capstone": true
		}
	]

func _unassigned_warrior_pool() -> int:
	_ensure_warband_state()
	var assigned: int = 0
	for warband_variant: Variant in warbands.values():
		var warband: Dictionary = warband_variant as Dictionary
		assigned += int(warband.get("ready_warriors", 0))
		assigned += int(warband.get("injured_warriors", 0))
	return max(0, get_warrior_count() - assigned)

func get_warband_flower_war_stability_audit() -> Dictionary:
	# Non-mechanical audit helper for testing the current canonical warband rules.
	_ensure_warband_state()
	var issues: Array[String] = []
	var rows: Array[Dictionary] = []
	for warband_id_variant: Variant in warbands.keys():
		var warband_id: String = String(warband_id_variant)
		var row: Dictionary = _sync_warband_progress((warbands[warband_id] as Dictionary).duplicate(true))
		warbands[warband_id] = row
		var spec: Dictionary = row.get("specialisation", {}) as Dictionary
		var doctrine_id: String = String(row.get("doctrine", "unspecialised"))
		var expected_doctrine: String = String(spec.get("doctrine_id", "unspecialised"))
		if doctrine_id != expected_doctrine:
			issues.append(String(row.get("name", warband_id)) + " doctrine mismatch: " + doctrine_id + " vs " + expected_doctrine)
		rows.append({
			"id": warband_id,
			"name": String(row.get("name", "Warband")),
			"doctrine": doctrine_id,
			"specialism": String(spec.get("name", "None")),
			"ready": int(row.get("ready_warriors", 0)),
			"injured": int(row.get("injured_warriors", 0)),
			"dead_total_report_only": int(row.get("dead_total", 0))
		})
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"warbands": rows,
		"specialism_sets_doctrine": true,
		"other_specialisms_lock": true,
		"dead_normal_cards": false,
		"skill_node_effects_connected": false,
		"event_hooks_ready": true
	}

func _warband_doctrine_name(doctrine_id: String) -> String:
	if FLOWER_WAR_DOCTRINES.has(doctrine_id):
		var data: Dictionary = FLOWER_WAR_DOCTRINES[doctrine_id] as Dictionary
		return String(data.get("name", doctrine_id.capitalize()))
	return doctrine_id.capitalize()
