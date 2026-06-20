# CampaignState.gd
# Godot 4.x
# Project path: res://Scripts/state/CampaignState.gd
#
# v0.44.8 stockpile authority pass.
#
# CampaignState is the future owner of live campaign/save data.
# It intentionally contains data-shaping helpers, including start-state loading, but not gameplay rules.
# During the TRGameState migration, TRGameState remains the public API and
# compatibility wrapper while systems increasingly read/write through this object.

class_name CampaignState
extends RefCounted

const SCHEMA_VERSION: String = "campaign_state_v0_44_12"

# -----------------------------------------------------------------------------
# Calendar / report state
# -----------------------------------------------------------------------------

var current_veintena: int = 1
var last_report: Array[String] = []
var initialized: bool = false

# -----------------------------------------------------------------------------
# Static-data-derived live dictionaries
# -----------------------------------------------------------------------------

var resources: Dictionary = {}
var resource_order: Array[String] = []
var buildings: Dictionary = {}
var building_order: Array[String] = []

# -----------------------------------------------------------------------------
# Economy / estate live state
# -----------------------------------------------------------------------------

var estate_stockpiles: Dictionary = {}
var market_stockpiles: Dictionary = {}
var market_demand: Dictionary = {}
var market_economy: Dictionary = {}

var estate_buildings: Dictionary = {}
var active_housing_counts: Dictionary = {}
var population: Dictionary = {}
var base_housing_capacity: Dictionary = {}
var labour_assignments: Dictionary = {}

# -----------------------------------------------------------------------------
# Palace / prestige / religion live state
# -----------------------------------------------------------------------------

var player_palace_dedicated_god: String = ""
var palace_built_structures: Dictionary = {}
var palace_structure_runtime_statuses: Dictionary = {}
var palace_delivered_ruler_demands: Dictionary = {} # Legacy compatibility only.
var palace_ruler_demand_donations: Array[Dictionary] = []
var last_palace_maintenance_report: Array[String] = []

var player_prestige: float = 0.0
var rival_prestige: Dictionary = {}
var prestige_history: Array[Dictionary] = []
var sacrifice_prestige_records: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# War / Flower War live state
# -----------------------------------------------------------------------------

var flower_war_palace_gate_enabled: bool = true
var last_flower_war_report: Dictionary = {}
var flower_war_report_archive: Array[Dictionary] = []
var warbands: Dictionary = {}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func reset_runtime_state() -> void:
	current_veintena = 1
	last_report.clear()
	initialized = false

	resources.clear()
	resource_order.clear()
	buildings.clear()
	building_order.clear()

	estate_stockpiles.clear()
	market_stockpiles.clear()
	market_demand.clear()
	market_economy.clear()

	estate_buildings.clear()
	active_housing_counts.clear()
	population.clear()
	base_housing_capacity.clear()
	labour_assignments.clear()

	player_palace_dedicated_god = ""
	palace_built_structures.clear()
	palace_structure_runtime_statuses.clear()
	palace_delivered_ruler_demands.clear()
	palace_ruler_demand_donations.clear()
	last_palace_maintenance_report.clear()

	player_prestige = 0.0
	rival_prestige.clear()
	prestige_history.clear()
	sacrifice_prestige_records.clear()

	flower_war_palace_gate_enabled = true
	last_flower_war_report.clear()
	flower_war_report_archive.clear()
	warbands.clear()

func load_static_definitions(new_resources: Dictionary, new_resource_order: Array[String], new_buildings: Dictionary, new_building_order: Array[String], new_market_economy: Dictionary) -> void:
	resources = _duplicate_dictionary(new_resources)
	resource_order = new_resource_order.duplicate()
	buildings = _duplicate_dictionary(new_buildings)
	building_order = new_building_order.duplicate()
	market_economy = _duplicate_dictionary(new_market_economy)

func load_start_state(start_data: Dictionary) -> void:
	current_veintena = int(start_data.get("current_veintena", 1))
	estate_stockpiles = _float_dictionary(start_data.get("estate_stockpiles", {}) as Dictionary)
	market_stockpiles = _float_dictionary(start_data.get("market_stockpiles", {}) as Dictionary)
	market_demand = _float_dictionary(start_data.get("market_demand", {}) as Dictionary)
	estate_buildings = _int_dictionary(start_data.get("estate_buildings", {}) as Dictionary)
	active_housing_counts = _int_dictionary(start_data.get("active_housing_counts", {}) as Dictionary)
	population = _int_dictionary(start_data.get("population", {}) as Dictionary)
	base_housing_capacity = _int_dictionary(start_data.get("base_housing_capacity", {}) as Dictionary)
	labour_assignments = _nested_int_dictionary(start_data.get("labour_assignments", {}) as Dictionary)
	ensure_all_resource_keys()
	ensure_all_building_keys()

func ensure_all_resource_keys() -> void:
	for resource_id: String in resource_order:
		if not estate_stockpiles.has(resource_id):
			estate_stockpiles[resource_id] = 0.0
		if not market_stockpiles.has(resource_id):
			market_stockpiles[resource_id] = 0.0
		if not market_demand.has(resource_id):
			market_demand[resource_id] = 0.0

func ensure_all_building_keys() -> void:
	for building_id: String in building_order:
		if not estate_buildings.has(building_id):
			estate_buildings[building_id] = 0


# -----------------------------------------------------------------------------
# Project-data loading helpers
# -----------------------------------------------------------------------------

func load_project_data_from_paths(resource_path: String, building_path: String, start_state_path: String, market_economy_path: String) -> Dictionary:
	# v0.44.6 bridge: CampaignState now owns project/start-data shaping.
	# This keeps TRGameState from carrying JSON-loading and dictionary-conversion
	# helpers while CampaignState is prepared to become the authoritative live-state
	# owner. This method does not run gameplay rules.
	reset_runtime_state()
	var warnings: Array[String] = []
	var resource_data: Dictionary = _load_json_dictionary(resource_path, warnings)
	var building_data: Dictionary = _load_json_dictionary(building_path, warnings)
	var market_data: Dictionary = _load_json_dictionary(market_economy_path, warnings)
	var start_data: Dictionary = _load_json_dictionary(start_state_path, warnings)
	_load_resource_definitions_from_data(resource_data)
	_load_building_definitions_from_data(building_data)
	market_economy = _duplicate_dictionary(market_data)
	load_start_state(start_data)
	return {
		"schema_version": "campaign_state_project_data_load_v0_44_6",
		"ok": warnings.is_empty(),
		"warnings": warnings,
		"resource_count": resources.size(),
		"building_count": buildings.size(),
		"market_economy_loaded": not market_economy.is_empty(),
		"start_state_loaded": not start_data.is_empty()
	}

func _load_json_dictionary(path: String, warnings: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		warnings.append("Missing data file: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		warnings.append("Could not open data file: " + path)
		return {}
	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	warnings.append("Data file did not parse as Dictionary: " + path)
	return {}

func _load_resource_definitions_from_data(data: Dictionary) -> void:
	resources.clear()
	resource_order.clear()
	var rows: Array = data.get("resources", []) as Array
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant as Dictionary
		var resource_id: String = String(row.get("id", ""))
		if resource_id == "":
			continue
		resources[resource_id] = row
		resource_order.append(resource_id)

func _load_building_definitions_from_data(data: Dictionary) -> void:
	buildings.clear()
	building_order.clear()
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

# -----------------------------------------------------------------------------
# TRGameState bridge helpers
# -----------------------------------------------------------------------------

func copy_from_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	resources = _get_dictionary(game_state, "resources")
	resource_order = _get_string_array(game_state, "resource_order")
	buildings = _get_dictionary(game_state, "buildings")
	building_order = _get_string_array(game_state, "building_order")

	estate_stockpiles = _get_dictionary(game_state, "estate_stockpiles")
	market_stockpiles = _get_dictionary(game_state, "market_stockpiles")
	market_demand = _get_dictionary(game_state, "market_demand")
	market_economy = _get_dictionary(game_state, "market_economy")

	estate_buildings = _get_dictionary(game_state, "estate_buildings")
	active_housing_counts = _get_dictionary(game_state, "active_housing_counts")
	population = _get_dictionary(game_state, "population")
	base_housing_capacity = _get_dictionary(game_state, "base_housing_capacity")
	labour_assignments = _get_dictionary(game_state, "labour_assignments")

	current_veintena = int(game_state.get("current_veintena"))
	last_report = _get_string_array(game_state, "last_report")
	initialized = bool(game_state.get("initialized"))

	player_palace_dedicated_god = String(game_state.get("player_palace_dedicated_god"))
	palace_built_structures = _get_dictionary(game_state, "palace_built_structures")
	palace_structure_runtime_statuses = _get_dictionary(game_state, "palace_structure_runtime_statuses")
	palace_delivered_ruler_demands = _get_dictionary(game_state, "palace_delivered_ruler_demands")
	palace_ruler_demand_donations = _get_dictionary_array(game_state, "palace_ruler_demand_donations")
	last_palace_maintenance_report = _get_string_array(game_state, "last_palace_maintenance_report")

	player_prestige = float(game_state.get("player_prestige"))
	rival_prestige = _get_dictionary(game_state, "rival_prestige")
	prestige_history = _get_dictionary_array(game_state, "prestige_history")
	sacrifice_prestige_records = _get_dictionary_array(game_state, "sacrifice_prestige_records")

	flower_war_palace_gate_enabled = bool(game_state.get("flower_war_palace_gate_enabled"))
	last_flower_war_report = _get_dictionary(game_state, "last_flower_war_report")
	flower_war_report_archive = _get_dictionary_array(game_state, "flower_war_report_archive")
	warbands = _get_dictionary(game_state, "warbands")

func apply_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("resources", _duplicate_dictionary(resources))
	game_state.set("resource_order", resource_order.duplicate())
	game_state.set("buildings", _duplicate_dictionary(buildings))
	game_state.set("building_order", building_order.duplicate())

	game_state.set("estate_stockpiles", _duplicate_dictionary(estate_stockpiles))
	game_state.set("market_stockpiles", _duplicate_dictionary(market_stockpiles))
	game_state.set("market_demand", _duplicate_dictionary(market_demand))
	game_state.set("market_economy", _duplicate_dictionary(market_economy))

	game_state.set("estate_buildings", _duplicate_dictionary(estate_buildings))
	game_state.set("active_housing_counts", _duplicate_dictionary(active_housing_counts))
	game_state.set("population", _duplicate_dictionary(population))
	game_state.set("base_housing_capacity", _duplicate_dictionary(base_housing_capacity))
	game_state.set("labour_assignments", _duplicate_dictionary(labour_assignments))

	game_state.set("current_veintena", current_veintena)
	game_state.set("last_report", last_report.duplicate())
	game_state.set("initialized", initialized)

	game_state.set("player_palace_dedicated_god", player_palace_dedicated_god)
	game_state.set("palace_built_structures", _duplicate_dictionary(palace_built_structures))
	game_state.set("palace_structure_runtime_statuses", _duplicate_dictionary(palace_structure_runtime_statuses))
	game_state.set("palace_delivered_ruler_demands", _duplicate_dictionary(palace_delivered_ruler_demands))
	game_state.set("palace_ruler_demand_donations", _duplicate_dictionary_array(palace_ruler_demand_donations))
	game_state.set("last_palace_maintenance_report", last_palace_maintenance_report.duplicate())

	game_state.set("player_prestige", player_prestige)
	game_state.set("rival_prestige", _duplicate_dictionary(rival_prestige))
	game_state.set("prestige_history", _duplicate_dictionary_array(prestige_history))
	game_state.set("sacrifice_prestige_records", _duplicate_dictionary_array(sacrifice_prestige_records))

	game_state.set("flower_war_palace_gate_enabled", flower_war_palace_gate_enabled)
	game_state.set("last_flower_war_report", _duplicate_dictionary(last_flower_war_report))
	game_state.set("flower_war_report_archive", _duplicate_dictionary_array(flower_war_report_archive))
	game_state.set("warbands", _duplicate_dictionary(warbands))

# -----------------------------------------------------------------------------
# Stockpile access helpers
# -----------------------------------------------------------------------------

func get_estate_stock(resource_id: String) -> float:
	return float(estate_stockpiles.get(resource_id, 0.0))

func set_estate_stock(resource_id: String, amount: float) -> float:
	var value: float = maxf(0.0, amount)
	estate_stockpiles[resource_id] = value
	return value

func add_estate_stock(resource_id: String, amount: float) -> float:
	return set_estate_stock(resource_id, get_estate_stock(resource_id) + amount)

func get_market_stock(resource_id: String) -> float:
	return float(market_stockpiles.get(resource_id, 0.0))

func set_market_stock(resource_id: String, amount: float) -> float:
	var value: float = maxf(0.0, amount)
	market_stockpiles[resource_id] = value
	return value

func add_market_stock(resource_id: String, amount: float) -> float:
	return set_market_stock(resource_id, get_market_stock(resource_id) + amount)

func mirror_stockpiles_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("estate_stockpiles", _duplicate_dictionary(estate_stockpiles))
	game_state.set("market_stockpiles", _duplicate_dictionary(market_stockpiles))

# -----------------------------------------------------------------------------
# Calendar / report access helpers
# -----------------------------------------------------------------------------

func get_current_veintena_value() -> int:
	return current_veintena

func set_current_veintena(value: int) -> int:
	current_veintena = maxi(1, value)
	return current_veintena

func set_initialized(value: bool) -> void:
	initialized = value

func get_last_report_copy() -> Array[String]:
	var output: Array[String] = []
	for line_variant: Variant in last_report:
		output.append(String(line_variant))
	return output

func set_last_report(lines: Array) -> void:
	last_report = _string_array_from_variant(lines)

func clear_last_report() -> void:
	last_report.clear()

func append_report_line(line: String) -> void:
	if line.strip_edges() == "":
		return
	last_report.append(line)

func mirror_calendar_report_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("current_veintena", current_veintena)
	game_state.set("last_report", last_report.duplicate())
	game_state.set("initialized", initialized)


# -----------------------------------------------------------------------------
# Prestige access helpers
# -----------------------------------------------------------------------------

func get_player_prestige_value() -> float:
	return player_prestige

func set_player_prestige_value(value: float) -> float:
	player_prestige = maxf(0.0, value)
	return player_prestige

func add_player_prestige_record(amount: float, source_id: String, detail: String, context: Dictionary = {}, veintena: int = 1) -> Dictionary:
	if absf(amount) <= 0.0001:
		return {"ok": true, "amount": 0.0, "prestige": player_prestige}
	var before: float = player_prestige
	player_prestige = maxf(0.0, player_prestige + amount)
	var record: Dictionary = {
		"veintena": veintena,
		"source_id": source_id,
		"detail": detail,
		"amount": amount,
		"prestige_before": before,
		"prestige_after": player_prestige,
		"context": context.duplicate(true)
	}
	prestige_history.append(record)
	return {"ok": true, "amount": amount, "prestige": player_prestige, "record": record}

func get_prestige_history_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(prestige_history)

func set_rival_prestige_values(values: Dictionary) -> Dictionary:
	rival_prestige = _duplicate_dictionary(values)
	return rival_prestige.duplicate(true)

func get_rival_prestige_copy() -> Dictionary:
	return _duplicate_dictionary(rival_prestige)

func set_rival_prestige_value(house_id: String, value: float) -> Dictionary:
	rival_prestige[house_id] = maxf(0.0, value)
	return {"ok": true, "house_id": house_id, "prestige": float(rival_prestige.get(house_id, 0.0))}

func get_sacrifice_prestige_records_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(sacrifice_prestige_records)

func set_sacrifice_prestige_records(records: Array) -> void:
	sacrifice_prestige_records = _duplicate_dictionary_array(records)

func mirror_prestige_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("player_prestige", player_prestige)
	game_state.set("rival_prestige", _duplicate_dictionary(rival_prestige))
	game_state.set("prestige_history", _duplicate_dictionary_array(prestige_history))
	game_state.set("sacrifice_prestige_records", _duplicate_dictionary_array(sacrifice_prestige_records))


# -----------------------------------------------------------------------------
# Palace state access helpers
# -----------------------------------------------------------------------------

func get_palace_dedicated_god_value() -> String:
	return player_palace_dedicated_god

func set_palace_dedicated_god_value(god_id: String) -> String:
	player_palace_dedicated_god = god_id.strip_edges().to_lower()
	return player_palace_dedicated_god

func clear_palace_state() -> void:
	player_palace_dedicated_god = ""
	palace_built_structures.clear()
	palace_structure_runtime_statuses.clear()
	palace_delivered_ruler_demands.clear()
	palace_ruler_demand_donations.clear()
	last_palace_maintenance_report.clear()

func get_palace_built_structures_copy() -> Dictionary:
	return _duplicate_dictionary(palace_built_structures)

func set_palace_built_structures(value: Dictionary) -> void:
	palace_built_structures = _duplicate_dictionary(value)

func clear_palace_built_structures() -> void:
	palace_built_structures.clear()

func is_palace_structure_built(structure_id: String) -> bool:
	return bool(palace_built_structures.get(structure_id, false))

func mark_palace_structure_built(structure_id: String) -> void:
	if structure_id.strip_edges() == "":
		return
	palace_built_structures[structure_id] = true

func get_palace_structure_runtime_statuses_copy() -> Dictionary:
	return _duplicate_dictionary(palace_structure_runtime_statuses)

func set_palace_structure_runtime_statuses(value: Dictionary) -> void:
	palace_structure_runtime_statuses = _duplicate_dictionary(value)

func clear_palace_structure_runtime_statuses() -> void:
	palace_structure_runtime_statuses.clear()

func get_palace_ruler_demand_donations_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(palace_ruler_demand_donations)

func set_palace_ruler_demand_donations(value: Array) -> void:
	palace_ruler_demand_donations = _duplicate_dictionary_array(value)

func append_palace_ruler_demand_donation(record: Dictionary) -> void:
	palace_ruler_demand_donations.append(record.duplicate(true))

func get_last_palace_maintenance_report_copy() -> Array[String]:
	return _string_array_from_variant(last_palace_maintenance_report)

func set_last_palace_maintenance_report(lines: Array) -> void:
	last_palace_maintenance_report = _string_array_from_variant(lines)

func get_flower_war_palace_gate_enabled_value() -> bool:
	return flower_war_palace_gate_enabled

func set_flower_war_palace_gate_enabled_value(enabled: bool) -> void:
	flower_war_palace_gate_enabled = enabled

func mirror_palace_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("player_palace_dedicated_god", player_palace_dedicated_god)
	game_state.set("palace_built_structures", _duplicate_dictionary(palace_built_structures))
	game_state.set("palace_structure_runtime_statuses", _duplicate_dictionary(palace_structure_runtime_statuses))
	game_state.set("palace_delivered_ruler_demands", _duplicate_dictionary(palace_delivered_ruler_demands))
	game_state.set("palace_ruler_demand_donations", _duplicate_dictionary_array(palace_ruler_demand_donations))
	game_state.set("last_palace_maintenance_report", last_palace_maintenance_report.duplicate())
	game_state.set("flower_war_palace_gate_enabled", flower_war_palace_gate_enabled)


# -----------------------------------------------------------------------------
# Population / buildings / housing state access helpers
# -----------------------------------------------------------------------------

func get_population_copy() -> Dictionary:
	return _duplicate_dictionary(population)

func get_population_count(group_id: String) -> int:
	return int(population.get(group_id, 0))

func set_population_count(group_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	population[group_id] = value
	return value

func add_population_count(group_id: String, amount: int) -> int:
	return set_population_count(group_id, get_population_count(group_id) + amount)

func get_estate_buildings_copy() -> Dictionary:
	return _duplicate_dictionary(estate_buildings)

func get_estate_building_count(building_id: String) -> int:
	return int(estate_buildings.get(building_id, 0))

func set_estate_building_count(building_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	estate_buildings[building_id] = value
	return value

func add_estate_building_count(building_id: String, amount: int) -> int:
	return set_estate_building_count(building_id, get_estate_building_count(building_id) + amount)

func get_active_housing_counts_copy() -> Dictionary:
	return _duplicate_dictionary(active_housing_counts)

func get_active_housing_count(building_id: String) -> int:
	return int(active_housing_counts.get(building_id, 0))

func set_active_housing_count_value(building_id: String, amount: int) -> int:
	var built_count: int = get_estate_building_count(building_id)
	var value: int = clampi(amount, 0, built_count)
	active_housing_counts[building_id] = value
	return value

func get_base_housing_capacity_copy() -> Dictionary:
	return _duplicate_dictionary(base_housing_capacity)

func set_base_housing_capacity_values(values: Dictionary) -> void:
	base_housing_capacity = _int_dictionary(values)

func set_base_housing_capacity_value(group_id: String, amount: int) -> int:
	var value: int = max(0, amount)
	base_housing_capacity[group_id] = value
	return value

func get_labour_assignments_copy() -> Dictionary:
	return _duplicate_dictionary(labour_assignments)

func get_labour_assignment_for_building(building_id: String) -> Dictionary:
	var value: Variant = labour_assignments.get(building_id, {})
	if value is Dictionary:
		return _duplicate_dictionary(value as Dictionary)
	return {}

func set_labour_assignments_values(values: Dictionary) -> void:
	labour_assignments = _duplicate_dictionary(values)

func set_labour_assignment_for_building(building_id: String, assignments: Dictionary) -> void:
	labour_assignments[building_id] = _duplicate_dictionary(assignments)

func clear_labour_assignment_for_building(building_id: String) -> void:
	labour_assignments.erase(building_id)

func mirror_population_building_housing_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("population", _duplicate_dictionary(population))
	game_state.set("estate_buildings", _duplicate_dictionary(estate_buildings))
	game_state.set("active_housing_counts", _duplicate_dictionary(active_housing_counts))
	game_state.set("base_housing_capacity", _duplicate_dictionary(base_housing_capacity))
	game_state.set("labour_assignments", _duplicate_dictionary(labour_assignments))

# -----------------------------------------------------------------------------
# Warband / Flower War report state access helpers
# -----------------------------------------------------------------------------

func get_warbands_copy() -> Dictionary:
	return _duplicate_dictionary(warbands)

func set_warbands_values(values: Dictionary) -> void:
	warbands = _duplicate_dictionary(values)

func has_warband(warband_id: String) -> bool:
	return warbands.has(warband_id)

func get_warband_copy(warband_id: String) -> Dictionary:
	var value: Variant = warbands.get(warband_id, {})
	if value is Dictionary:
		return _duplicate_dictionary(value as Dictionary)
	return {}

func set_warband_value(warband_id: String, warband: Dictionary) -> void:
	if warband_id == "":
		return
	warbands[warband_id] = _duplicate_dictionary(warband)

func erase_warband(warband_id: String) -> void:
	warbands.erase(warband_id)

func clear_warbands() -> void:
	warbands.clear()

func get_last_flower_war_report_copy() -> Dictionary:
	return _duplicate_dictionary(last_flower_war_report)

func set_last_flower_war_report(report: Dictionary) -> void:
	last_flower_war_report = _duplicate_dictionary(report)

func clear_last_flower_war_report() -> void:
	last_flower_war_report.clear()

func get_flower_war_report_archive_copy() -> Array[Dictionary]:
	return _duplicate_dictionary_array(flower_war_report_archive)

func get_flower_war_report_archive_count() -> int:
	return flower_war_report_archive.size()

func set_flower_war_report_archive(values: Array) -> void:
	flower_war_report_archive = _duplicate_dictionary_array(values)

func append_flower_war_report_archive(report: Dictionary, max_entries: int = 20) -> void:
	if report.is_empty():
		return
	flower_war_report_archive.append(_duplicate_dictionary(report))
	var cap: int = max(0, max_entries)
	if cap <= 0:
		return
	while flower_war_report_archive.size() > cap:
		flower_war_report_archive.pop_front()

func clear_flower_war_report_archive() -> void:
	flower_war_report_archive.clear()

func mirror_warband_flower_war_state_to_game_state(game_state: Node) -> void:
	if game_state == null:
		return
	game_state.set("warbands", _duplicate_dictionary(warbands))
	game_state.set("last_flower_war_report", _duplicate_dictionary(last_flower_war_report))
	game_state.set("flower_war_report_archive", _duplicate_dictionary_array(flower_war_report_archive))

# -----------------------------------------------------------------------------
# Save/load-facing helpers
# -----------------------------------------------------------------------------

func to_save_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"current_veintena": current_veintena,
		"estate_stockpiles": _duplicate_dictionary(estate_stockpiles),
		"market_stockpiles": _duplicate_dictionary(market_stockpiles),
		"market_demand": _duplicate_dictionary(market_demand),
		"estate_buildings": _duplicate_dictionary(estate_buildings),
		"active_housing_counts": _duplicate_dictionary(active_housing_counts),
		"population": _duplicate_dictionary(population),
		"base_housing_capacity": _duplicate_dictionary(base_housing_capacity),
		"labour_assignments": _duplicate_dictionary(labour_assignments),
		"player_palace_dedicated_god": player_palace_dedicated_god,
		"palace_built_structures": _duplicate_dictionary(palace_built_structures),
		"palace_structure_runtime_statuses": _duplicate_dictionary(palace_structure_runtime_statuses),
		"palace_delivered_ruler_demands": _duplicate_dictionary(palace_delivered_ruler_demands),
		"palace_ruler_demand_donations": _duplicate_dictionary_array(palace_ruler_demand_donations),
		"player_prestige": player_prestige,
		"rival_prestige": _duplicate_dictionary(rival_prestige),
		"prestige_history": _duplicate_dictionary_array(prestige_history),
		"sacrifice_prestige_records": _duplicate_dictionary_array(sacrifice_prestige_records),
		"last_flower_war_report": _duplicate_dictionary(last_flower_war_report),
		"flower_war_report_archive": _duplicate_dictionary_array(flower_war_report_archive),
		"warbands": _duplicate_dictionary(warbands),
		"last_report": last_report.duplicate()
	}

func apply_save_dictionary(data: Dictionary) -> void:
	current_veintena = int(data.get("current_veintena", current_veintena))
	estate_stockpiles = _float_dictionary(data.get("estate_stockpiles", estate_stockpiles) as Dictionary)
	market_stockpiles = _float_dictionary(data.get("market_stockpiles", market_stockpiles) as Dictionary)
	market_demand = _float_dictionary(data.get("market_demand", market_demand) as Dictionary)
	estate_buildings = _int_dictionary(data.get("estate_buildings", estate_buildings) as Dictionary)
	active_housing_counts = _int_dictionary(data.get("active_housing_counts", active_housing_counts) as Dictionary)
	population = _int_dictionary(data.get("population", population) as Dictionary)
	base_housing_capacity = _int_dictionary(data.get("base_housing_capacity", base_housing_capacity) as Dictionary)
	labour_assignments = _nested_int_dictionary(data.get("labour_assignments", labour_assignments) as Dictionary)
	player_palace_dedicated_god = String(data.get("player_palace_dedicated_god", player_palace_dedicated_god))
	palace_built_structures = _duplicate_dictionary(data.get("palace_built_structures", palace_built_structures) as Dictionary)
	palace_structure_runtime_statuses = _duplicate_dictionary(data.get("palace_structure_runtime_statuses", palace_structure_runtime_statuses) as Dictionary)
	palace_delivered_ruler_demands = _duplicate_dictionary(data.get("palace_delivered_ruler_demands", palace_delivered_ruler_demands) as Dictionary)
	palace_ruler_demand_donations = _duplicate_dictionary_array(data.get("palace_ruler_demand_donations", palace_ruler_demand_donations) as Array)
	player_prestige = float(data.get("player_prestige", player_prestige))
	rival_prestige = _duplicate_dictionary(data.get("rival_prestige", rival_prestige) as Dictionary)
	prestige_history = _duplicate_dictionary_array(data.get("prestige_history", prestige_history) as Array)
	sacrifice_prestige_records = _duplicate_dictionary_array(data.get("sacrifice_prestige_records", sacrifice_prestige_records) as Array)
	last_flower_war_report = _duplicate_dictionary(data.get("last_flower_war_report", last_flower_war_report) as Dictionary)
	flower_war_report_archive = _duplicate_dictionary_array(data.get("flower_war_report_archive", flower_war_report_archive) as Array)
	warbands = _duplicate_dictionary(data.get("warbands", warbands) as Dictionary)
	last_report = _string_array_from_variant(data.get("last_report", last_report))
	ensure_all_resource_keys()
	ensure_all_building_keys()

# -----------------------------------------------------------------------------
# Utility helpers
# -----------------------------------------------------------------------------

func _get_dictionary(node: Node, property_name: String) -> Dictionary:
	var value: Variant = node.get(property_name)
	if value is Dictionary:
		return _duplicate_dictionary(value as Dictionary)
	return {}

func _get_string_array(node: Node, property_name: String) -> Array[String]:
	return _string_array_from_variant(node.get(property_name))

func _get_dictionary_array(node: Node, property_name: String) -> Array[Dictionary]:
	var value: Variant = node.get(property_name)
	if value is Array:
		return _duplicate_dictionary_array(value as Array)
	return []

func _string_array_from_variant(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if value is Array:
		for item: Variant in value:
			output.append(String(item))
	return output

func _float_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = float(source[key_variant])
	return output

func _int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		output[key] = int(source[key_variant])
	return output

func _nested_int_dictionary(source: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in source.keys():
		var key: String = String(key_variant)
		var value: Variant = source[key_variant]
		if value is Dictionary:
			output[key] = _int_dictionary(value as Dictionary)
	return output

func _duplicate_dictionary(source: Dictionary) -> Dictionary:
	return source.duplicate(true)

func _duplicate_dictionary_array(source: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Variant in source:
		if item is Dictionary:
			output.append((item as Dictionary).duplicate(true))
	return output
